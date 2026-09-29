-- Soil: tilling, watering, fertilizing and amendments, plus daily upkeep of
-- empty soil (drying, sprinklers, reverting to grass when neglected).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Soil = require(Shared.Config.Soil)
local Registry = require(Shared.Lib.Registry)
local GameTime = require(Shared.Lib.GameTime)
local CropMath = require(Shared.Lib.CropMath)

local S = require(script.Parent)

local SoilService = {}

local random = Random.new()

-- Till a tile (or clear an empty tilled tile back to grass). Returns true if changed.
function SoilService.Till(owner: Player, gx: number, gz: number, toolTier: number): (boolean, string?)
	local profile = S.Data.Get(owner)
	if not profile then
		return false, "Not ready"
	end
	local key = S.Farm.Key(gx, gz)
	local tile = profile.Farm.Tiles[key]
	if tile then
		if tile.C then
			return false, "Use the shovel to remove crops"
		end
		profile.Farm.Tiles[key] = nil
		S.Farm.RenderTile(owner, key)
		return true
	end
	local ok, reason = S.Farm.Tillable(owner, gx, gz)
	if not ok then
		return false, reason
	end
	local row, col = S.Farm.ParcelOf(gx, gz)
	local mods = if row then S.Farm.ParcelType(row :: number, col :: number).Soil else {}
	local base = Soil.NewSoil
	local now = GameTime.Now()
	tile = {
		W = math.clamp(base.Moisture + (mods.Moisture or 0), 0, 100),
		H = math.clamp(base.Health + (mods.Health or 0) + (if toolTier >= 5 then 10 else 0), 0, 100),
		N = math.clamp(base.N + (mods.N or 0), 0, 100),
		P = math.clamp(base.P + (mods.P or 0), 0, 100),
		K = math.clamp(base.K + (mods.K or 0), 0, 100),
		Idle = now,
		Wt = now,
	}
	if toolTier >= 6 then
		tile.W = 100
	end
	profile.Farm.Tiles[key] = tile
	S.Farm.RenderTile(owner, key)
	return true
end

function SoilService.Water(owner: Player, key: string, actor: Player): (boolean, string?)
	local profile = S.Data.Get(owner)
	local tile = profile and profile.Farm.Tiles[key]
	if not tile then
		return false, "Till the soil first"
	end
	if tile.C then
		S.Crop.Sync(owner, key)
	end
	if (tile.W or 0) >= 99 then
		return false, "Already soaked"
	end
	tile.W = math.min(100, (tile.W or 0) + Soil.WaterAmount)
	tile.Wt = GameTime.Now()
	S.Farm.RenderTile(owner, key)
	S.Data.AddStat(actor, "TilesWatered")
	if actor ~= owner then
		S.Data.AddStat(actor, "CropsWateredForOthers")
	end
	S.Quest.Progress(actor, "Water", "*", 1)
	S.Tutorial.Event(actor, "Water")
	return true
end

local function applyNutrients(tile: any, nutrients: any?)
	if not nutrients then
		return
	end
	tile.N = math.clamp((tile.N or 50) + (nutrients.N or 0), 0, 100)
	tile.P = math.clamp((tile.P or 50) + (nutrients.P or 0), 0, 100)
	tile.K = math.clamp((tile.K or 50) + (nutrients.K or 0), 0, 100)
	tile.H = math.clamp((tile.H or 50) + (nutrients.Health or 0), 0, 100)
end

-- Apply a fertilizer to a tile. Growth-effect fertilizers need a crop.
function SoilService.Fertilize(owner: Player, key: string, fertId: string, actor: Player): (boolean, string?)
	local profile = S.Data.Get(owner)
	local tile = profile and profile.Farm.Tiles[key]
	local fert = Registry.Fertilizers[fertId]
	if not tile or not fert then
		return false, "Till the soil first"
	end
	local needsCrop = fert.Quality ~= nil
		or fert.Speed ~= nil
		or fert.Retain ~= nil
		or fert.Mutations ~= nil
		or fert.AllMutations ~= nil
	-- Compost is pure soil food: it works on empty soil too.
	if fertId == "compost" then
		needsCrop = false
	end
	local cs = tile.C
	if needsCrop and not cs then
		return false, "Plant something first"
	end
	if cs then
		S.Crop.Sync(owner, key)
		if needsCrop then
			if cs.Fe == fertId then
				return false, "Already fertilized"
			end
			cs.Fe = fertId
			if fert.Overgrow and random:NextNumber() < fert.Overgrow then
				CropMath.AddMutation(cs, "Overgrown", S.Farm.EnvFor(owner, key))
			end
		end
	end
	applyNutrients(tile, fert.Nutrients)
	S.Farm.RenderTile(owner, key)
	S.Data.AddStat(actor, "Fertilized")
	S.Tutorial.Event(actor, "Fertilize")
	return true
end

-- Permanent soil amendments (Cloud Soil...).
function SoilService.Amend(owner: Player, key: string, tag: string): (boolean, string?)
	local profile = S.Data.Get(owner)
	local tile = profile and profile.Farm.Tiles[key]
	if not tile then
		return false, "Till the soil first"
	end
	tile.Am = tile.Am or {}
	if table.find(tile.Am, tag) then
		return false, "Already mixed in"
	end
	table.insert(tile.Am, tag)
	S.Farm.InvalidateAround(owner, key)
	S.Farm.RenderTile(owner, key)
	return true
end

-- Rain totem: water every tile on the farm.
function SoilService.WaterAll(owner: Player): number
	local profile = S.Data.Get(owner)
	if not profile then
		return 0
	end
	local count = 0
	for key, tile in profile.Farm.Tiles do
		if tile.C then
			S.Crop.Sync(owner, key)
		end
		tile.W = 100
		tile.Wt = GameTime.Now()
		S.Farm.RenderTile(owner, key)
		count += 1
	end
	return count
end

-- Daily upkeep for empty tiles (crops handle their own moisture in CropMath).
local function dawn()
	local now = GameTime.Now()
	for player in S.Farm.All() do
		local profile = S.Data.Get(player)
		if profile then
			local toRemove = {}
			for key, tile in profile.Farm.Tiles do
				if not tile.C then
					local hours = math.max(0, now - (tile.Wt or now)) / GameTime.HOUR
					tile.W = math.max(0, (tile.W or 0) - Soil.DrainPerHour * hours)
					tile.Wt = now
					local env = S.Farm.EnvFor(player, key)
					if env and env.Sprinkler > 0 then
						tile.W = 100
					end
					if
						tile.Idle
						and now - tile.Idle > Soil.RevertDays * GameTime.DAY
						and not (tile.Am and #tile.Am > 0)
					then
						table.insert(toRemove, key)
					end
				end
			end
			for _, key in toRemove do
				profile.Farm.Tiles[key] = nil
			end
			for key in profile.Farm.Tiles do
				S.Farm.RenderTile(player, key)
			end
			for _, key in toRemove do
				S.Farm.RenderTile(player, key)
			end
		end
	end
end

function SoilService.Start()
	S.Time.Dawn:Connect(dawn)
end

return SoilService

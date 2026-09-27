-- Farms: lot assignment, the tile grid, land parcels and per-tile environment.
--
-- Each server has six lots (Config/World.Farms.Lots). A joining player gets a
-- free lot and their saved farm is rebuilt on it. Lot-local tile coordinates:
--   gx 0..59 (east), gz -11..-1 is the yard, gz 0..59 are the parcels (south).
--
-- Tilled tiles are real parts in workspace.Farms.Lot<N>.Tiles carrying compact
-- attributes (crop, stage, ripe ETA, moisture state, soil, mutations). Clients
-- render crops from those attributes, so crops cost the server almost nothing.
--
-- Environment (CropMath.Env) per tile = parcel type tags + building interiors
-- (greenhouse, cellar, hydroponics) + nearby placeable effects (scarecrows,
-- lightning rods, beacons, sprinklers, water towers) + companion planting +
-- the owner's skills and buffs. It's cached per tile and invalidated when
-- placeables or neighbouring crops change.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local World = require(Shared.Config.World)
local Land = require(Shared.Config.Land)
local Soil = require(Shared.Config.Soil)
local Mutations = require(Shared.Config.Mutations)
local Social = require(Shared.Config.Social)
local Net = require(Shared.Lib.Net)
local Signal = require(Shared.Lib.Signal)
local Registry = require(Shared.Lib.Registry)
local CropMath = require(Shared.Lib.CropMath)
local Stats = require(Shared.Lib.Stats)
local GameTime = require(Shared.Lib.GameTime)
local Format = require(Shared.Lib.Format)

local FarmBuilder = require(script.Parent.Parent.World.FarmBuilder)
local S = require(script.Parent)

local TILE = World.Farms.TileSize
local PARCEL = World.Farms.ParcelTiles
local PARCELS = World.Farms.Parcels
local GRID = PARCEL * PARCELS
local YARD_TILES = math.floor(World.Farms.YardDepth / TILE)

local FarmService = {}
FarmService.Ready = Signal.new() -- (player, farm) the farm is built and services can populate it
FarmService.Released = Signal.new() -- (player, farm) the owner left; lot is being cleared
FarmService.TileChanged = Signal.new() -- (player, key)

export type Farm = {
	Owner: Player,
	Lot: any,
	Origin: Vector3,
	Model: Model,
	Tiles: Folder,
	Placed: Folder,
	Animals: Folder,
	TileParts: { [string]: BasePart },
	Occ: { [string]: { Uid: string, Interior: boolean, Tags: { string }?, Walkable: boolean? } },
	EnvCache: { [string]: any },
	Effects: { any },
	Version: number,
	PlayerFx: any?,
	PlayerFxAt: number,
	Water: { [string]: string }, -- tile key → water tag (ponds)
}

local farms: { [Player]: Farm } = {}
local lotOwner: { [number]: Player } = {}
local lots: { [number]: any } = {}

-- Geometry --------------------------------------------------------------------------------------

function FarmService.Key(gx: number, gz: number): string
	return gx .. "_" .. gz
end

function FarmService.ParseKey(key: string): (number, number)
	local x, z = string.match(key, "^(%-?%d+)_(%-?%d+)$")
	return tonumber(x) :: number, tonumber(z) :: number
end

function FarmService.TileCenter(farm: Farm, gx: number, gz: number): Vector3
	return farm.Origin + Vector3.new((gx + 0.5) * TILE, 0, (gz + 0.5) * TILE)
end

function FarmService.InGrid(gx: number, gz: number): boolean
	return gx >= 0 and gx < GRID and gz >= -YARD_TILES and gz < GRID
end

function FarmService.TileAt(farm: Farm, position: Vector3): (number?, number?)
	local rel = position - farm.Origin
	local gx = math.floor(rel.X / TILE)
	local gz = math.floor(rel.Z / TILE)
	if not FarmService.InGrid(gx, gz) or math.abs(rel.Y) > 40 then
		return nil, nil
	end
	return gx, gz
end

-- Parcel row/col (1-based) of a field tile, or nil in the yard.
function FarmService.ParcelOf(gx: number, gz: number): (number?, number?)
	if gz < 0 or gx < 0 or gx >= GRID or gz >= GRID then
		return nil, nil
	end
	return gz // PARCEL + 1, gx // PARCEL + 1
end

function FarmService.ParcelKey(row: number, col: number): string
	return row .. "_" .. col
end

function FarmService.ParcelType(row: number, col: number)
	local typeId = Land.Layout[row] and Land.Layout[row][col]
	return Land.Types[typeId or "Field"]
end

function FarmService.OwnsTile(profile: any, gx: number, gz: number): boolean
	if gz < 0 then
		return FarmService.InGrid(gx, gz) -- the yard always belongs to you
	end
	local row, col = FarmService.ParcelOf(gx, gz)
	return row ~= nil and profile.Farm.Parcels[FarmService.ParcelKey(row :: number, col :: number)] == true
end

-- Lookup -----------------------------------------------------------------------------------------

function FarmService.Get(player: Player): Farm?
	return farms[player]
end

function FarmService.All(): { [Player]: Farm }
	return farms
end

-- The farm (and tile) at a world position.
function FarmService.FarmAt(position: Vector3): (Farm?, number?, number?)
	for _, farm in farms do
		local gx, gz = FarmService.TileAt(farm, position)
		if gx then
			return farm, gx, gz
		end
	end
	return nil, nil, nil
end

function FarmService.LotOfPosition(position: Vector3): number?
	for id, lot in lots do
		local rel = position - lot.Origin
		if rel.X >= -8 and rel.X <= GRID * TILE + 8 and rel.Z >= -World.Farms.YardDepth - 8 and rel.Z <= GRID * TILE + 8 then
			return id
		end
	end
	return nil
end

-- Occupancy (placeables) ---------------------------------------------------------------------------

function FarmService.Occupant(farm: Farm, key: string)
	return farm.Occ[key]
end

-- Rebuild occupancy and the effect list from the saved placeables.
function FarmService.RebuildOccupancy(player: Player)
	local farm = farms[player]
	local profile = S.Data.Get(player)
	if not farm or not profile then
		return
	end
	table.clear(farm.Occ)
	table.clear(farm.Effects)
	table.clear(farm.Water)
	for uid, placed in profile.Farm.Placed do
		local def = Registry.Placeables[placed.Id]
		if def then
			local tiles = S.Building.Footprint(placed, def)
			local interior = def.Function ~= nil and def.Function.Kind == "Interior"
			for _, key in tiles do
				farm.Occ[key] = { Uid = uid, Interior = interior, Tags = if interior then def.Function.Tags else nil, Walkable = def.Walkable }
				if def.Function and def.Function.Kind == "Water" then
					farm.Water[key] = def.Function.Water
				end
			end
			if def.Tags or (def.Function and (def.Function.Kind == "Sprinkler" or def.Function.Kind == "Power")) then
				local cx, cz = S.Building.CenterTile(placed, def)
				table.insert(farm.Effects, { Uid = uid, Def = def, X = cx, Z = cz, Placed = placed })
			end
		end
	end
	-- Riverside parcels have a natural pond in the middle.
	for key in profile.Farm.Parcels do
		local row, col = string.match(key, "^(%d+)_(%d+)$")
		local r, c = tonumber(row) :: number, tonumber(col) :: number
		local ptype = FarmService.ParcelType(r, c)
		if ptype.Water then
			for _, tile in FarmService.PondTiles(r, c) do
				farm.Occ[tile] = farm.Occ[tile] or { Uid = "pond", Interior = false }
				farm.Water[tile] = "Pond"
			end
		end
	end
	farm.Version += 1
	table.clear(farm.EnvCache)
end

function FarmService.PondTiles(row: number, col: number): { string }
	local out = {}
	local x0 = (col - 1) * PARCEL + 4
	local z0 = (row - 1) * PARCEL + 4
	for dx = 0, 3 do
		for dz = 0, 2 do
			table.insert(out, FarmService.Key(x0 + dx, z0 + dz))
		end
	end
	return out
end

-- Water tag at a tile (ponds, wells) for fishing and refilling.
function FarmService.WaterAt(farm: Farm, key: string): string?
	return farm.Water[key]
end

-- Environment -------------------------------------------------------------------------------------

local function playerEffects(farm: Farm): any
	local now = os.clock()
	if farm.PlayerFx and now - farm.PlayerFxAt < 8 then
		return farm.PlayerFx
	end
	local profile = S.Data.Get(farm.Owner)
	local gameNow = GameTime.Now()
	local fx = {
		Growth = 0,
		Quality = 0,
		Mutation = 1,
		MaxMutations = Mutations.MaxPerCrop,
		Afflictions = true,
		Retain = 0,
		Automation = 0,
	}
	if profile then
		fx.Growth = Stats.Effect(profile, "GrowthSpeed", gameNow)
		fx.Quality = Stats.Effect(profile, "QualityScore", gameNow)
		fx.Mutation = 1 + Stats.Effect(profile, "MutationChance", gameNow)
		fx.MaxMutations = Mutations.MaxPerCrop + Stats.Effect(profile, "MaxMutations")
		fx.Afflictions = Stats.SkillLevel(profile, "Farming") >= Soil.AfflictionsFromLevel
		fx.Retain = if (profile.Tools.can or 1) >= 5 then 0.25 else 0
		fx.Automation = Stats.Effect(profile, "Automation")
	end
	farm.PlayerFx = fx
	farm.PlayerFxAt = now
	return fx
end

function FarmService.InvalidatePlayerEffects(player: Player)
	local farm = farms[player]
	if farm then
		farm.PlayerFx = nil
		table.clear(farm.EnvCache)
	end
end

local companionRules = Soil.Companions

local function applyCompanions(env: any, myCrop: string, neighbours: { string })
	for _, other in neighbours do
		for _, rule in companionRules do
			local applies = (rule.A == other and (rule.B == "*" or rule.B == myCrop))
				or (rule.B == other and rule.A == myCrop)
			if applies then
				local e = rule.Effect
				env.GrowthBonus += e.Growth or 0
				env.QualityBonus += e.Quality or 0
				env.PestMult *= e.Pests or 1
				env.BlightMult *= e.Blight or 1
			end
		end
		for _, mutation in Mutations.List do
			local mult = mutation.Neighbors and mutation.Neighbors[other]
			if mult then
				env.MutationBonus[mutation.Id] = math.max(env.MutationBonus[mutation.Id] or 1, mult)
			end
		end
	end
end

local function computeEnv(farm: Farm, key: string, tile: any?): any
	local env = CropMath.DefaultEnv()
	local gx, gz = FarmService.ParseKey(key)
	env.Tags.Homestead = true
	local row, col = FarmService.ParcelOf(gx, gz)
	if row then
		for _, tag in FarmService.ParcelType(row :: number, col :: number).Tags do
			env.Tags[tag] = true
		end
	end
	-- Building interiors
	local occ = farm.Occ[key]
	if occ and occ.Interior and occ.Tags then
		for _, tag in occ.Tags do
			env.Tags[tag] = true
		end
		local placed = S.Data.Get(farm.Owner)
		local def = placed and placed.Farm.Placed[occ.Uid] and Registry.Placeables[placed.Farm.Placed[occ.Uid].Id]
		if def and def.Function and def.Function.MutationBoost then
			env.MutationMult *= def.Function.MutationBoost
		end
	end
	env.Indoor = env.Tags.Indoor == true
	env.Climate = env.Tags.Climate == true
	env.Hydroponic = env.Tags.Hydroponic == true
	-- Amendments
	if tile and tile.Am then
		for _, tag in tile.Am do
			env.Tags[tag] = true
		end
	end
	-- Radius effects and sprinklers
	local fx = playerEffects(farm)
	local towerBonus = 0
	for _, effect in farm.Effects do
		if effect.Def.Tags and table.find(effect.Def.Tags, "WaterTower") then
			local r = effect.Def.Radius or 0
			if (effect.X - gx) ^ 2 + (effect.Z - gz) ^ 2 <= r * r then
				towerBonus = 1
			end
		end
	end
	for _, effect in farm.Effects do
		local def = effect.Def
		local dx, dz = gx - effect.X, gz - effect.Z
		if def.Tags and def.Radius then
			local r = def.Radius + math.max(def.Size[1], def.Size[2]) / 2
			if dx * dx + dz * dz <= r * r then
				for _, tag in def.Tags do
					env.Tags[tag] = true
				end
			end
		end
		local fn = def.Function
		if fn and fn.Kind == "Sprinkler" then
			local range = fn.Range + towerBonus + (if fx.Automation >= 0.3 then 1 else 0)
			local covered
			if fn.Shape == "Cross" then
				covered = math.abs(dx) + math.abs(dz) <= range
			else
				covered = math.max(math.abs(dx), math.abs(dz)) <= range
			end
			if covered and not (dx == 0 and dz == 0) then
				env.Sprinkler = math.max(env.Sprinkler, if fn.Keep then 2 else 1)
			end
		end
	end
	-- Companions and neighbour mutation bonuses
	local profile = S.Data.Get(farm.Owner)
	local myCrop = tile and tile.C and tile.C.Id
	if myCrop and profile then
		local neighbours = {}
		for ox = -1, 1 do
			for oz = -1, 1 do
				if ox ~= 0 or oz ~= 0 then
					local n = profile.Farm.Tiles[FarmService.Key(gx + ox, gz + oz)]
					if n and n.C then
						table.insert(neighbours, n.C.Id)
					end
				end
			end
		end
		applyCompanions(env, myCrop, neighbours)
	end
	-- Owner's skills and buffs
	env.GrowthBonus += fx.Growth
	env.QualityBonus += fx.Quality
	env.MutationMult *= fx.Mutation
	env.MaxMutations = fx.MaxMutations
	env.Afflictions = fx.Afflictions
	env.RetainBonus = fx.Retain
	return env
end

function FarmService.EnvFor(player: Player, key: string): any?
	local farm = farms[player]
	local profile = S.Data.Get(player)
	if not farm or not profile then
		return nil
	end
	local cached = farm.EnvCache[key]
	if cached and farm.PlayerFx and os.clock() - farm.PlayerFxAt < 8 then
		return cached
	end
	local env = computeEnv(farm, key, profile.Farm.Tiles[key])
	farm.EnvCache[key] = env
	return env
end

-- A tile's crop changed: its neighbours' companion effects change too.
function FarmService.InvalidateAround(player: Player, key: string)
	local farm = farms[player]
	if not farm then
		return
	end
	local gx, gz = FarmService.ParseKey(key)
	for ox = -1, 1 do
		for oz = -1, 1 do
			farm.EnvCache[FarmService.Key(gx + ox, gz + oz)] = nil
		end
	end
end

-- Tile parts ------------------------------------------------------------------------------------------

local DRY = Color3.fromRGB(150, 108, 72)
local WET = Color3.fromRGB(92, 64, 44)
local SOAKED = Color3.fromRGB(70, 50, 38)

local function moistureState(tile: any, crop: any?): number
	local w = tile.W or 0
	local band = Soil.WaterBands[(crop and crop.Water) or "Medium"]
	if w < band.Min then
		return 0
	elseif w > 90 then
		return 2
	end
	return 1
end

-- Create/update the tile's part and attributes from the saved tile.
function FarmService.RenderTile(player: Player, key: string)
	local farm = farms[player]
	local profile = S.Data.Get(player)
	if not farm or not profile then
		return
	end
	local tile = profile.Farm.Tiles[key]
	local part = farm.TileParts[key]
	if not tile then
		if part then
			part:Destroy()
			farm.TileParts[key] = nil
		end
		return
	end
	if not part then
		local gx, gz = FarmService.ParseKey(key)
		local newPart = Instance.new("Part")
		newPart.Name = key
		newPart.Anchored = true
		newPart.CanCollide = false
		newPart.CanTouch = false
		newPart.CastShadow = false
		newPart.Material = Enum.Material.Ground
		newPart.Size = Vector3.new(TILE - 0.15, 0.3, TILE - 0.15)
		newPart.Position = FarmService.TileCenter(farm, gx, gz) + Vector3.new(0, 0.12, 0)
		newPart.TopSurface = Enum.SurfaceType.Smooth
		newPart:SetAttribute("X", gx)
		newPart:SetAttribute("Z", gz)
		newPart.Parent = farm.Tiles
		farm.TileParts[key] = newPart
		part = newPart
	end
	local cs = tile.C
	local crop = cs and Registry.Crops[cs.Id]
	local wet = moistureState(tile, crop)
	part.Color = if wet == 0 then DRY elseif wet == 1 then WET else SOAKED
	part.Material = if wet == 2 then Enum.Material.Mud else Enum.Material.Ground

	local env = FarmService.EnvFor(player, key)
	local function set(name: string, value: any)
		if part:GetAttribute(name) ~= value then
			part:SetAttribute(name, value)
		end
	end
	set("Wb", wet)
	set("Soil", string.format("%d,%d,%d,%d,%d", tile.W or 0, tile.H or 0, tile.N or 0, tile.P or 0, tile.K or 0))
	set("Am", if tile.Am then table.concat(tile.Am, ",") else nil)
	set("Ind", if env and env.Indoor then true else nil)
	set("Spr", if env and env.Sprinkler > 0 then env.Sprinkler else nil)
	if cs and crop then
		local now = GameTime.Now()
		set("C", cs.Id)
		set("S", CropMath.StageOf(cs.P or 0))
		set("P", math.floor((cs.P or 0) * 100) / 100)
		set("R", (cs.P or 0) >= 1)
		set("M", if cs.M and #cs.M > 0 then table.concat(cs.M, ",") else nil)
		set("Af", cs.Af)
		set("Fe", cs.Fe)
		set("Pr", cs.Pr == true)
		set("G", if cs.G then table.concat(cs.G, ".") else nil)
		set("Hv", cs.Hv or 0)
		if env then
			local eta = CropMath.TimeToRipe(tile, cs, env, now)
			set("E", if eta == math.huge then -1 else math.floor(now + eta))
			local score = CropMath.Score(tile, cs, env, now)
			set("Q", require(Shared.Lib.QualityMath).TierFor(score, CropMath.MaxTier(cs, env)))
			set("Qs", math.floor(score * 100))
			local info = GameTime.Info(now)
			set("Dn", not CropMath.InSeason(crop, info.SeasonId) and not env.Indoor and not env.Climate)
			set("Nm", if CropMath.NeedsMet(crop, env) then nil else crop.Needs)
		end
	else
		for _, name in { "C", "S", "P", "R", "M", "Af", "Fe", "Pr", "G", "Hv", "E", "Q", "Qs", "Dn", "Nm" } do
			if part:GetAttribute(name) ~= nil then
				part:SetAttribute(name, nil)
			end
		end
	end
	FarmService.TileChanged:Fire(player, key)
end

-- Tiles ------------------------------------------------------------------------------------------------

function FarmService.Tile(player: Player, key: string): any?
	local profile = S.Data.Get(player)
	return profile and profile.Farm.Tiles[key]
end

-- Can a tile be tilled? (owned, not under a building/pond, inside the grid, not the yard)
function FarmService.Tillable(player: Player, gx: number, gz: number): (boolean, string?)
	local farm = farms[player]
	local profile = S.Data.Get(player)
	if not farm or not profile then
		return false, "No farm"
	end
	if gz < 0 or not FarmService.InGrid(gx, gz) then
		return false, "You can't farm in the yard"
	end
	if not FarmService.OwnsTile(profile, gx, gz) then
		return false, "You don't own this land yet"
	end
	local occ = farm.Occ[FarmService.Key(gx, gz)]
	if occ and not occ.Interior then
		return false, "Something is in the way"
	end
	if S.Mining.FarmNodeAt(player, FarmService.Key(gx, gz)) then
		return false, "Clear the tree or rock first"
	end
	return true
end

-- Permissions ------------------------------------------------------------------------------------------

-- Can `actor` do an action needing `level` on `owner`'s farm?
function FarmService.CanAct(actor: Player, owner: Player, level: string): boolean
	if actor == owner then
		return true
	end
	return S.Permission.Allows(owner, actor, level)
end

-- Land ------------------------------------------------------------------------------------------------------

function FarmService.ParcelPrice(profile: any): (number, { any })
	local owned = 0
	for _ in profile.Farm.Parcels do
		owned += 1
	end
	local price = math.floor(Land.ParcelBase * Land.ParcelGrowth ^ (owned - 1) / 100) * 100
	local mats = if owned >= 5 then Land.ParcelMats else {}
	return price, mats
end

local function adjacentOwned(profile: any, row: number, col: number): boolean
	for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		if profile.Farm.Parcels[FarmService.ParcelKey(row + d[1], col + d[2])] then
			return true
		end
	end
	return false
end

local function buyParcel(player: Player, parcelKey: string)
	local profile = S.Data.Get(player)
	local farm = farms[player]
	if not profile or not farm then
		return false, "Not ready"
	end
	local row, col = string.match(parcelKey, "^(%d+)_(%d+)$")
	local r, c = tonumber(row), tonumber(col)
	if not r or not c or r < 1 or r > PARCELS or c < 1 or c > PARCELS then
		return false, "No such parcel"
	end
	if profile.Farm.Parcels[parcelKey] then
		return false, "You already own this land"
	end
	if Land.RequireAdjacent and not adjacentOwned(profile, r, c) then
		return false, "Buy land next to land you own"
	end
	local price, mats = FarmService.ParcelPrice(profile)
	local discount = Stats.ShopDiscount(profile, "carpenter")
	price = math.floor(price * (1 - discount))
	if profile.Coins < price then
		return false, "Not enough coins (" .. Format.Commas(price) .. ")"
	end
	for _, mat in mats do
		if S.Inventory.Count(player, mat.Id) < mat.N then
			return false, "You need " .. mat.N .. " " .. Registry.Items[mat.Id].Name
		end
	end
	S.Economy.Spend(player, price, "Land")
	for _, mat in mats do
		S.Inventory.Remove(player, mat.Id, mat.N)
	end
	profile.Farm.Parcels[parcelKey] = true
	S.Data.Changed(player, "Farm", "Parcels")
	FarmService.RebuildOccupancy(player)
	FarmBuilder.UpdateParcels(farm, profile)
	S.Mining.RefreshFarmNodes(player)
	S.Data.AddStat(player, "ParcelsBought")
	local owned = 0
	for _ in profile.Farm.Parcels do
		owned += 1
	end
	S.Data.MaxStat(player, "ParcelsOwned", owned)
	S.Quest.Progress(player, "BuyLand", "*", 1)
	local ptype = FarmService.ParcelType(r, c)
	S.Notify.Banner(player, "New land!", ptype.Icon .. " " .. ptype.Name .. " — " .. ptype.Description, "Land")
	return true, parcelKey
end

local function upgradeHouse(player: Player)
	local profile = S.Data.Get(player)
	local farm = farms[player]
	if not profile or not farm then
		return false, "Not ready"
	end
	local nextLevel = profile.Farm.House + 1
	local def = Land.House[nextLevel]
	if not def then
		return false, "Your house is fully upgraded"
	end
	if Stats.EstateLevel(profile) < (def.Level or 1) then
		return false, "Requires Estate level " .. def.Level
	end
	local price = math.floor(def.Cost * (1 - Stats.ShopDiscount(profile, "carpenter")))
	if profile.Coins < price then
		return false, "Not enough coins"
	end
	for _, mat in def.Mats do
		if S.Inventory.Count(player, mat.Id) < mat.N then
			return false, "You need " .. mat.N .. " " .. Registry.Items[mat.Id].Name
		end
	end
	S.Economy.Spend(player, price, "House")
	for _, mat in def.Mats do
		S.Inventory.Remove(player, mat.Id, mat.N)
	end
	profile.Farm.House = nextLevel
	S.Data.Changed(player, "Farm", "House")
	S.Data.MaxStat(player, "HouseLevel", nextLevel)
	S.Inventory.RecalculateHomeStorage(player)
	FarmBuilder.UpdateHouse(farm, nextLevel, profile)
	S.Notify.Banner(player, "Your " .. def.Name .. " is ready!", def.Description, "Land", "🏡")
	return true, nextLevel
end

local function rename(player: Player, name: string)
	local profile = S.Data.Get(player)
	local farm = farms[player]
	if not profile or not farm then
		return false, "Not ready"
	end
	local clean = Format.CleanName(name, Social.Names.FarmMax)
	if #clean < 2 then
		return false, "That name is too short"
	end
	local filtered = S.Multiplayer.FilterText(player, clean)
	if not filtered then
		return false, "That name isn't allowed"
	end
	profile.Farm.Name = filtered
	S.Data.Changed(player, "Farm", "Name")
	farm.Model:SetAttribute("FarmName", filtered)
	FarmBuilder.UpdateSign(farm, filtered)
	return true, filtered
end

-- Lot assignment --------------------------------------------------------------------------------------------

local function freeLot(): number?
	for id in lots do
		if not lotOwner[id] then
			return id
		end
	end
	return nil
end

local function assign(player: Player, profile: any)
	local lotId = freeLot()
	if not lotId then
		warn("[Evergrove] No free farm lot for", player.Name)
		S.Notify.Error(player, "This server is full of farmers! Your farm will load on a server with space.")
		return
	end
	lotOwner[lotId] = player
	local lot = lots[lotId]
	local model = lot.Model :: Model
	local function folder(name: string): Folder
		local existing = model:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = model
		return f
	end
	local farm: Farm = {
		Owner = player,
		Lot = lot,
		Origin = lot.Origin,
		Model = model,
		Tiles = folder("Tiles"),
		Placed = folder("Placed"),
		Animals = folder("Animals"),
		TileParts = {},
		Occ = {},
		EnvCache = {},
		Effects = {},
		Version = 0,
		PlayerFx = nil,
		PlayerFxAt = 0,
		Water = {},
	}
	farms[player] = farm
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("OwnerName", player.DisplayName)
	model:SetAttribute("FarmName", if profile.Farm.Name ~= "" then profile.Farm.Name else player.DisplayName .. "'s Farm")
	player:SetAttribute("Lot", lotId)
	FarmBuilder.ApplyOwner(farm, profile, player)

	S.Building.SpawnAll(player)
	FarmService.RebuildOccupancy(player)
	FarmService.Ready:Fire(player, farm)
	for key in profile.Farm.Tiles do
		FarmService.RenderTile(player, key)
	end
end

local function release(player: Player)
	local farm = farms[player]
	if not farm then
		return
	end
	FarmService.Released:Fire(player, farm)
	for _, name in { "Tiles", "Placed", "Animals" } do
		local f = farm.Model:FindFirstChild(name)
		if f then
			f:Destroy()
		end
	end
	FarmBuilder.Clear(farm)
	farm.Model:SetAttribute("Owner", nil)
	farm.Model:SetAttribute("OwnerName", nil)
	farm.Model:SetAttribute("FarmName", nil)
	lotOwner[farm.Lot.Id] = nil
	farms[player] = nil
end

-- Spawn point at the farm gate.
function FarmService.SpawnCFrame(player: Player): CFrame?
	local farm = farms[player]
	if not farm then
		return nil
	end
	local gate = farm.Origin + Vector3.new(GRID * TILE / 2, 4, -World.Farms.YardDepth + 6)
	return CFrame.lookAt(gate, gate + Vector3.new(0, 0, 10))
end

function FarmService.OwnerOfLot(lotId: number): Player?
	return lotOwner[lotId]
end

function FarmService.Init()
	local root = Instance.new("Folder")
	root.Name = "Farms"
	root.Parent = workspace
	for _, lotDef in World.Farms.Lots do
		local model = FarmBuilder.BuildLot(lotDef, root)
		lots[lotDef.Id] = { Id = lotDef.Id, Origin = lotDef.Origin, Model = model }
	end

	Net.Handle("LandBuy", buyParcel)
	Net.Handle("HouseUpgrade", upgradeHouse)
	Net.Handle("FarmRename", rename)
end

function FarmService.Start()
	S.Data.Loaded:Connect(function(player, profile)
		assign(player, profile)
	end)
	S.Data.Removing:Connect(function(player)
		release(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		-- Data.Removing normally releases first; this catches players whose data never loaded.
		task.defer(release, player)
	end)
end

return FarmService

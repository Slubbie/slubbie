-- Crops: planting, growth scheduling, harvesting, pruning, sprays and hazards.
--
-- Growth is timestamp based (Lib/CropMath). The scheduler walks every crop on
-- every loaded farm round-robin, advancing a slice of them each Heartbeat, so
-- the cost is flat no matter how many crops exist. A crop is only re-rendered
-- (tile attributes) when something visible changes.
--
-- When a farm loads, each crop is advanced from its saved timestamp to now
-- (capped by Config.Gameplay.Offline) — that's the offline progress — and the
-- player gets a "while you were away" summary.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local CropsConfig = require(Shared.Config.Crops)
local Soil = require(Shared.Config.Soil)
local Gameplay = require(Shared.Config.Gameplay)
local Registry = require(Shared.Lib.Registry)
local CropMath = require(Shared.Lib.CropMath)
local ItemUtil = require(Shared.Lib.ItemUtil)
local GameTime = require(Shared.Lib.GameTime)
local Genetics = require(Shared.Lib.Genetics)
local Stats = require(Shared.Lib.Stats)
local RNG = require(Shared.Lib.RNG)

local S = require(script.Parent)

local PERF = Gameplay.Performance
local HOUR = GameTime.HOUR

local CropService = {}

local random = Random.new()

type Entry = { Player: Player, Key: string, NextAt: number, RenderAt: number, LastStage: number, LastWet: number }

local entries: { Entry } = {}
local index: { [Player]: { [string]: Entry } } = {}
local cursor = 1

local function track(player: Player, key: string)
	index[player] = index[player] or {}
	if index[player][key] then
		return
	end
	local entry: Entry = { Player = player, Key = key, NextAt = 0, RenderAt = 0, LastStage = 0, LastWet = -1 }
	index[player][key] = entry
	table.insert(entries, entry)
end

local function untrack(player: Player, key: string)
	local byKey = index[player]
	local entry = byKey and byKey[key]
	if not entry then
		return
	end
	byKey[key] = nil
	local i = table.find(entries, entry)
	if i then
		entries[i] = entries[#entries]
		entries[#entries] = nil
	end
end

local function wetState(tile: any, crop: any): number
	local band = Soil.WaterBands[crop.Water] or Soil.WaterBands.Medium
	local w = tile.W or 0
	return if w < band.Min then 0 elseif w > 90 then 2 else 1
end

-- Events ---------------------------------------------------------------------------------------------

local function announceMutations(player: Player, key: string, cs: any, events: any)
	local farm = S.Farm.Get(player)
	if not farm then
		return
	end
	local gx, gz = S.Farm.ParseKey(key)
	local position = S.Farm.TileCenter(farm, gx, gz)
	for _, id in events.Mutations do
		S.Notify.FX(position, "Mutation", { Id = id, Crop = cs.Id, Key = key })
	end
	for _, id in events.Combos do
		S.Notify.FX(position, "Combo", { Id = id, Crop = cs.Id, Key = key }, 400)
		S.Notify.Toast(
			player,
			string.format("✨ A %s %s is growing on your farm!", id, Registry.Crops[cs.Id].Name),
			"Success"
		)
	end
	if events.Afflicted then
		local aff = Soil.Afflictions[events.Afflicted]
		S.Notify.FX(position, "Affliction", { Id = events.Afflicted, Key = key })
		S.Notify.Toast(
			player,
			string.format(
				"%s %s on your %s! Use %s.",
				aff.Icon,
				aff.Name,
				Registry.Crops[cs.Id].Name,
				Registry.Items[aff.Cure].Name
			),
			"Warning"
		)
	end
end

-- Advance one crop to `now`. Returns events (or nil if nothing to do).
function CropService.Sync(player: Player, key: string, now: number?, rng: Random?)
	local profile = S.Data.Get(player)
	local tile = profile and profile.Farm.Tiles[key]
	local cs = tile and tile.C
	if not cs then
		return nil
	end
	local env = S.Farm.EnvFor(player, key)
	if not env then
		return nil
	end
	local t = now or GameTime.Now()
	local events = CropMath.Advance(tile, cs, env, cs.T or t, t, rng or random)
	if #events.Mutations > 0 or #events.Combos > 0 or events.Afflicted then
		announceMutations(player, key, cs, events)
	end
	-- Blight spreads to same-family neighbours.
	if cs.Af == "Blight" and env.Afflictions then
		local hours = math.max(0, t - (cs.Bs or t)) / HOUR
		cs.Bs = t
		if hours > 0 and random:NextNumber() < 1 - (1 - Soil.Afflictions.Blight.SpreadChancePerHour) ^ hours then
			local gx, gz = S.Farm.ParseKey(key)
			local family = Registry.Crops[cs.Id].Family
			local ox, oz = random:NextInteger(-1, 1), random:NextInteger(-1, 1)
			local neighbour = profile.Farm.Tiles[S.Farm.Key(gx + ox, gz + oz)]
			local nenv = S.Farm.EnvFor(player, S.Farm.Key(gx + ox, gz + oz))
			if neighbour and neighbour.C and not neighbour.C.Af and nenv and not nenv.Tags.Greenhouse then
				if Registry.Crops[neighbour.C.Id].Family == family then
					neighbour.C.Af = "Blight"
					S.Farm.RenderTile(player, S.Farm.Key(gx + ox, gz + oz))
				end
			end
		end
	end
	return events
end

-- Advance and re-render one tile right away (after watering, fertilizing...).
function CropService.Touch(player: Player, key: string)
	CropService.Sync(player, key)
	S.Farm.RenderTile(player, key)
	local entry = index[player] and index[player][key]
	if entry then
		entry.RenderAt = os.clock() + 30
	end
end

-- Scheduler ---------------------------------------------------------------------------------------------

local function step()
	local count = #entries
	if count == 0 then
		return
	end
	local clock = os.clock()
	local now = GameTime.Now()
	local budget = math.min(PERF.CropsPerStep, count)
	for _ = 1, budget do
		if cursor > #entries then
			cursor = 1
		end
		local entry = entries[cursor]
		cursor += 1
		if entry and clock >= entry.NextAt then
			entry.NextAt = clock + PERF.CropRefresh
			local profile = S.Data.Get(entry.Player)
			local tile = profile and profile.Farm.Tiles[entry.Key]
			if not tile or not tile.C then
				untrack(entry.Player, entry.Key)
			else
				local events = CropService.Sync(entry.Player, entry.Key, now)
				local crop = Registry.Crops[tile.C.Id]
				local stage = CropMath.StageOf(tile.C.P or 0)
				local wet = wetState(tile, crop)
				local visible = events
					and (events.Ripened or #events.Mutations > 0 or #events.Combos > 0 or events.Afflicted ~= nil)
				if visible or stage ~= entry.LastStage or wet ~= entry.LastWet or clock >= entry.RenderAt then
					entry.LastStage = stage
					entry.LastWet = wet
					entry.RenderAt = clock + 30
					S.Farm.RenderTile(entry.Player, entry.Key)
				end
				if events and events.Ripened then
					S.Tutorial.Event(entry.Player, "Ripe")
				end
			end
		end
	end
end

-- Offline catch-up when a farm loads --------------------------------------------------------------------

local function catchUp(player: Player)
	local profile = S.Data.Get(player)
	if not profile then
		return
	end
	local now = GameTime.Now()
	local cap = Gameplay.Offline.Cap * GameTime.Scale()
	local summary = { Ripened = 0, Mutations = {}, Afflicted = 0, Seconds = 0 }
	for key, tile in profile.Farm.Tiles do
		local cs = tile.C
		if cs then
			local from = cs.T or now
			summary.Seconds = math.max(summary.Seconds, now - from)
			if now - from > cap then
				-- Growth beyond the cap is forfeited (but time still moves on).
				cs.T = now - cap
			end
			local wasRipe = (cs.P or 0) >= 1
			local events = CropService.Sync(player, key, now)
			if events then
				if events.Ripened and not wasRipe then
					summary.Ripened += 1
				end
				for _, m in events.Mutations do
					table.insert(summary.Mutations, { Crop = cs.Id, Id = m })
				end
				if events.Afflicted then
					summary.Afflicted += 1
				end
			end
			track(player, key)
		else
			-- Empty soil dries out while you're away.
			local last = tile.Idle or now
			local hours = math.max(0, now - last) / HOUR
			tile.W = math.max(0, (tile.W or 0) - Soil.DrainPerHour * hours)
		end
	end
	if summary.Seconds >= Gameplay.Offline.SummaryAfter then
		S.Notify.FXPlayer(player, "Offline", {
			Seconds = summary.Seconds,
			Ripened = summary.Ripened,
			Mutations = summary.Mutations,
			Afflicted = summary.Afflicted,
		})
	end
end

-- Planting ---------------------------------------------------------------------------------------------------

local function seasonalCrop(): string
	local info = GameTime.Info()
	local options = {}
	for _, crop in CropsConfig.List do
		if crop.Seed and CropMath.InSeason(crop, info.SeasonId) and Registry.RarityOrder(crop.Rarity) <= 3 then
			table.insert(options, crop.Id)
		end
	end
	return if #options > 0 then options[random:NextInteger(1, #options)] else "carrot"
end

-- Plant from a seed stack (already removed from the planter's inventory by the caller).
function CropService.Plant(owner: Player, key: string, seed: ItemUtil.Stack, actor: Player?): (boolean, string?)
	local profile = S.Data.Get(owner)
	if not profile then
		return false, "Not ready"
	end
	local tile = profile.Farm.Tiles[key]
	if not tile then
		return false, "Till the soil first"
	end
	if tile.C then
		return false, "Something is already growing here"
	end
	local def = Registry.Items[seed.Id]
	local cropId = def and def.Plants
	local extraMutation = nil
	if seed.Id == "mystery_seed" then
		cropId = seasonalCrop()
	elseif seed.Id == "ancient_seed" then
		cropId = seasonalCrop()
		extraMutation = "Ancient"
	end
	if not cropId or not Registry.Crops[cropId] then
		return false, "That can't be planted"
	end
	local crop = Registry.Crops[cropId]
	local env = S.Farm.EnvFor(owner, key)
	if crop.Tree and env and env.Tags.Hydroponic then
		return false, "Trees can't grow in hydroponics"
	end
	local now = GameTime.Now()
	tile.C = {
		Id = cropId,
		P = 0,
		T = now,
		At = now,
		G = seed.G or { 1, 1, 1, 1 },
		Lt = seed.T,
		M = if extraMutation then { extraMutation } else nil,
		Tt = 0,
		Wg = 0,
		Cs = 0,
	}
	tile.Idle = nil
	S.Farm.InvalidateAround(owner, key)
	S.Farm.RenderTile(owner, key)
	track(owner, key)
	local planter = actor or owner
	S.Data.AddStat(planter, "CropsPlanted")
	S.Quest.Progress(planter, "Plant", cropId, 1)
	S.Tutorial.Event(planter, "Plant")
	if not CropMath.InSeason(crop, GameTime.Info().SeasonId) and not (env and (env.Indoor or env.Climate)) then
		S.Notify.Toast(planter, crop.Name .. " is out of season here; it will barely grow outdoors.", "Warning")
	end
	return true
end

-- Harvesting ---------------------------------------------------------------------------------------------------

local function isSpecimen(crop: any, roll: any): boolean
	if crop.Size[1] <= 0 then
		return false
	end
	if table.find(roll.Mutations, "Giant") or table.find(roll.Mutations, "Colossal") then
		return true
	end
	return roll.Size >= crop.Size[1] * 1.8 or crop.Id == "giant_pumpkin"
end

local function recordHarvest(player: Player, crop: any, roll: any)
	local profile = S.Data.Get(player)
	if not profile then
		return
	end
	S.Data.AddStat(player, "CropsHarvested", roll.Count)
	S.Data.MaxStat(player, "LargestCropKg", math.floor(roll.Size * 100) / 100)
	local mutationCount = 0
	local combo = false
	for _, id in roll.Mutations do
		if ItemUtil.IsCombo(id) then
			combo = true
		else
			mutationCount += 1
		end
	end
	if mutationCount > 0 or combo then
		S.Data.AddStat(player, "MutationsHarvested")
	end
	if combo then
		S.Data.AddStat(player, "CombosHarvested")
	end
	if table.find(roll.Mutations, "Perfect") then
		S.Data.AddStat(player, "PerfectHarvested")
	end
	if roll.Tier >= 6 then
		S.Data.AddStat(player, "RadiantHarvested")
	end
	if crop.Rarity == "Mythic" then
		S.Data.AddStat(player, "MythicHarvested")
	end
	local season = GameTime.Info().SeasonId
	profile.Stats["Harvested_" .. season] = 1
	local seasons = 0
	for _, s in { "Spring", "Summer", "Autumn", "Winter" } do
		if profile.Stats["Harvested_" .. s] then
			seasons += 1
		end
	end
	S.Data.MaxStat(player, "SeasonsHarvested", seasons)
	-- Favourite crop tracking for the profile card.
	local key = "H_" .. crop.Id
	profile.Stats[key] = (profile.Stats[key] or 0) + roll.Count
	S.Collection.Discover(player, "Crops", crop.Id, { Quality = roll.Tier, Size = roll.Size })
	for _, id in roll.Mutations do
		S.Collection.Discover(player, "Mutations", id, { Crop = crop.Id })
	end
end

-- Harvest one tile. `actor` is who swung the sickle (may be a helper with permission).
-- Returns the produced stacks or nil + reason.
function CropService.Harvest(owner: Player, key: string, actor: Player, opts: any?): ({ ItemUtil.Stack }?, string?)
	local profile = S.Data.Get(owner)
	local tile = profile and profile.Farm.Tiles[key]
	local cs = tile and tile.C
	if not cs then
		return nil, "Nothing to harvest"
	end
	CropService.Sync(owner, key)
	if (cs.P or 0) < 1 then
		return nil, "Not ripe yet"
	end
	local crop = Registry.Crops[cs.Id]
	local env = S.Farm.EnvFor(owner, key)
	if not crop or not env then
		return nil, "Not ready"
	end
	opts = opts or {}
	local actorProfile = S.Data.Get(actor) or profile
	local now = GameTime.Now()
	local roll = CropMath.RollHarvest(tile, cs, env, now, random, {
		QualityBonus = opts.ToolQuality or 0,
		YieldChance = Stats.Effect(actorProfile, "YieldChance") + (opts.BonusChance or 0),
		PremiumBonus = Stats.Effect(actorProfile, "PremiumChance"),
	})

	-- Build the produce stacks.
	local stacks = {}
	local count = roll.Count
	if isSpecimen(crop, roll) then
		table.insert(stacks, {
			Id = crop.Id,
			N = 1,
			Q = if roll.Tier > 1 then roll.Tier else nil,
			M = if #roll.Mutations > 0 then roll.Mutations else nil,
			S = math.floor(roll.Size * 100) / 100,
			U = RNG.Uid("sp"),
		})
		count -= 1
	end
	if count > 0 then
		table.insert(stacks, ItemUtil.New(crop.Id, count, roll.Tier, roll.Mutations))
	end
	-- Seed drops from wild/farming skill (Wild Seeds node) are handled by Foraging; crops
	-- occasionally drop a seed back so fields can self-sustain.
	if random:NextNumber() < 0.08 + Genetics.YieldChance(cs.G) * 0.5 then
		table.insert(stacks, { Id = "seed_" .. crop.Id, N = 1, G = Genetics.Inherit(cs.G, random) })
	end

	for _, stack in stacks do
		if opts.ToSilo then
			-- Harvest drones deliver into silos; anything that doesn't fit goes to the bag.
			local leftover = S.Inventory.SiloAdd(owner, stack)
			if leftover > 0 then
				S.Inventory.Add(owner, ItemUtil.Split(stack, leftover), { Source = "Harvest drones", Silent = true })
			end
		else
			S.Inventory.Add(owner, stack, { Source = "Harvest", Position = opts.Position })
		end
	end
	if actor ~= owner then
		S.Notify.Toast(owner, actor.DisplayName .. " harvested " .. crop.Name .. " for you!", "Info")
		S.Data.AddStat(actor, "CropsHarvestedForOthers", roll.Count)
	end

	-- XP & progress (the actor earns the XP; the owner gets the items).
	local xp = math.floor(crop.XP * (1 + (roll.Tier - 1) * 0.15) * (if #roll.Mutations > 0 then 1.5 else 1))
	S.Skill.AddXP(actor, "Farming", xp)
	recordHarvest(owner, crop, roll)
	S.Quest.Progress(actor, "Harvest", crop.Id, roll.Count, { Quality = roll.Tier })
	for _, id in roll.Mutations do
		S.Quest.Progress(actor, "Mutation", id, 1)
	end
	S.Festival.OnHarvest(actor, crop.Id, roll)
	S.Tutorial.Event(actor, "Harvest")

	-- Feedback
	local farm = S.Farm.Get(owner)
	if farm then
		local gx, gz = S.Farm.ParseKey(key)
		local combo = false
		for _, id in roll.Mutations do
			if ItemUtil.IsCombo(id) then
				combo = true
			end
		end
		S.Notify.FX(S.Farm.TileCenter(farm, gx, gz), "Harvest", {
			Crop = crop.Id,
			Count = roll.Count,
			Q = roll.Tier,
			M = roll.Mutations,
			Size = roll.Size,
			Premium = roll.Premium,
			Rare = combo or roll.Tier >= 5 or Registry.RarityOrder(crop.Rarity) >= 5,
			By = actor.UserId,
		})
	end

	-- Soil and what happens to the plant.
	if crop.Fixes then
		tile.N = math.min(100, (tile.N or 50) + crop.Fixes)
	end
	local fert = cs.Fe and Registry.Fertilizers[cs.Fe]
	local keepFert = fert and random:NextNumber() < Stats.Effect(actorProfile, "FertilizerSave")
	if crop.Regrow then
		cs.P = CropsConfig.RegrowFrom
		cs.Hv = (cs.Hv or 0) + 1
		cs.Rp = nil
		cs.Tt, cs.Wg, cs.Cs = 0, 0, 0
		cs.M = nil
		cs.Pr = nil
		cs.T = now
		if not keepFert then
			cs.Fe = nil
		end
	else
		if tile.Lf == crop.Family then
			tile.H = math.max(0, (tile.H or 50) - Soil.MonoculturePenalty)
		else
			tile.H = math.min(100, (tile.H or 50) + Soil.RotationBonus)
		end
		tile.Lf = crop.Family
		tile.C = nil
		tile.Idle = now
		-- Phoenix Bloom rises from its ashes.
		if crop.Id == "phoenix_bloom" and random:NextNumber() < 0.25 then
			tile.C = { Id = crop.Id, P = 0, T = now, At = now, G = cs.G, Tt = 0, Wg = 0, Cs = 0 }
			S.Notify.Toast(owner, "🔥 The Phoenix Bloom rose from its ashes!", "Success")
		end
		if not tile.C then
			untrack(owner, key)
		end
	end
	-- Chrono Melon hastens every crop within 2 tiles by an in-game hour.
	if crop.Id == "chrono_melon" then
		local gx, gz = S.Farm.ParseKey(key)
		for ox = -2, 2 do
			for oz = -2, 2 do
				local nkey = S.Farm.Key(gx + ox, gz + oz)
				local n = profile.Farm.Tiles[nkey]
				if n and n.C and nkey ~= key and (n.C.P or 0) < 1 then
					n.C.P = math.min(1, (n.C.P or 0) + CropMath.BaseRate(n.C) * HOUR)
					S.Farm.RenderTile(owner, nkey)
				end
			end
		end
	end
	S.Farm.InvalidateAround(owner, key)
	S.Farm.RenderTile(owner, key)
	return stacks
end

-- Pruning: once per growth cycle on bushes, vines and trees.
local PRUNABLE = { Bush = true, Vine = true, Tree = true, Pepper = true, Herb = true }
function CropService.Prune(owner: Player, key: string): (boolean, string?)
	local profile = S.Data.Get(owner)
	local tile = profile and profile.Farm.Tiles[key]
	local cs = tile and tile.C
	if not cs then
		return false, "Nothing to prune"
	end
	local crop = Registry.Crops[cs.Id]
	if not PRUNABLE[crop.Visual.Arch] then
		return false, "Only bushes, vines and trees need pruning"
	end
	if cs.Pr then
		return false, "Already pruned this cycle"
	end
	CropService.Sync(owner, key)
	cs.Pr = true
	S.Farm.RenderTile(owner, key)
	return true
end

-- Shovel: dig up a crop. Unsprouted seeds come back.
function CropService.Remove(owner: Player, key: string, actor: Player): (boolean, string?)
	local profile = S.Data.Get(owner)
	local tile = profile and profile.Farm.Tiles[key]
	local cs = tile and tile.C
	if not cs then
		return false, "Nothing planted"
	end
	if (cs.P or 0) < CropsConfig.Stages[2] then
		S.Inventory.Add(actor, { Id = "seed_" .. cs.Id, N = 1, G = cs.G, T = cs.Lt })
	end
	tile.C = nil
	tile.Idle = GameTime.Now()
	untrack(owner, key)
	S.Farm.InvalidateAround(owner, key)
	S.Farm.RenderTile(owner, key)
	return true
end

-- Sprays and potions on a tile.
function CropService.Spray(owner: Player, key: string, itemId: string): boolean
	local profile = S.Data.Get(owner)
	local tile = profile and profile.Farm.Tiles[key]
	local cs = tile and tile.C
	if not cs then
		return false
	end
	CropService.Sync(owner, key)
	local changed = false
	if itemId == "pest_spray" and cs.Af == "Pests" then
		cs.Af = nil
		changed = true
	elseif itemId == "fungicide" and cs.Af == "Blight" then
		cs.Af = nil
		changed = true
	elseif itemId == "growth_elixir" and (cs.P or 0) < 1 then
		cs.P = math.min(1, (cs.P or 0) + CropMath.BaseRate(cs) * HOUR * 2)
		if cs.P >= 1 then
			cs.Rp = GameTime.Now()
		end
		changed = true
	elseif itemId == "mutation_serum" and (cs.P or 0) < 1 then
		local env = S.Farm.EnvFor(owner, key)
		if env then
			local info = GameTime.Info()
			local weather = CropMath.WeatherAt(env, info.Time)
			for _, mutation in require(Shared.Config.Mutations).List do
				local chance = CropMath.MutationChance(mutation, cs, env, weather, info) * 20
				if random:NextNumber() < chance and CropMath.AddMutation(cs, mutation.Id, env) then
					announceMutations(
						owner,
						key,
						cs,
						{ Mutations = { mutation.Id }, Combos = CropMath.ResolveCombos(cs) }
					)
				end
			end
		end
		changed = true
	end
	if changed then
		S.Farm.RenderTile(owner, key)
	end
	return changed
end

-- Weather hazards (called by WeatherService).
function CropService.Hazard(owner: Player, key: string, kind: string)
	local profile = S.Data.Get(owner)
	local tile = profile and profile.Farm.Tiles[key]
	local cs = tile and tile.C
	if not cs or (cs.P or 0) <= 0 then
		return
	end
	CropService.Sync(owner, key)
	if kind == "Lightning" then
		if random:NextNumber() < 0.5 then
			local env = S.Farm.EnvFor(owner, key)
			if CropMath.AddMutation(cs, "Charged", env) then
				announceMutations(owner, key, cs, { Mutations = { "Charged" }, Combos = CropMath.ResolveCombos(cs) })
			end
		else
			cs.P = math.max(0, (cs.P or 0) - 0.12)
			cs.Cs = (cs.Cs or 0) * 0.85
		end
	elseif kind == "Hail" or kind == "Scorch" then
		-- A bruise: lose some care credit (quality), never the crop.
		cs.Wg = (cs.Wg or 0) * 0.88
		cs.Cs = (cs.Cs or 0) * 0.88
	end
	S.Farm.RenderTile(owner, key)
end

-- Debug helpers ---------------------------------------------------------------------------------------------

function CropService.GrowAll(owner: Player, fraction: number)
	local profile = S.Data.Get(owner)
	if not profile then
		return 0
	end
	local count = 0
	for key, tile in profile.Farm.Tiles do
		if tile.C then
			CropService.Sync(owner, key)
			local before = tile.C.P or 0
			tile.C.P = math.min(1, before + fraction)
			tile.C.Tt = math.max(tile.C.Tt or 0, 1)
			tile.C.Wg = math.max(tile.C.Wg or 0, tile.C.Tt)
			tile.C.Cs = math.max(tile.C.Cs or 0, tile.C.Tt)
			if tile.C.P >= 1 and before < 1 then
				tile.C.Rp = GameTime.Now()
			end
			S.Farm.RenderTile(owner, key)
			count += 1
		end
	end
	return count
end

function CropService.ForceMutation(owner: Player, key: string, mutationId: string): boolean
	local profile = S.Data.Get(owner)
	local tile = profile and profile.Farm.Tiles[key]
	if not tile or not tile.C then
		return false
	end
	local ok = CropMath.AddMutation(tile.C, mutationId, { MaxMutations = 99 } :: any)
	CropMath.ResolveCombos(tile.C)
	S.Farm.RenderTile(owner, key)
	return ok
end

function CropService.ActiveCount(): number
	return #entries
end

function CropService.Init() end

function CropService.Start()
	S.Farm.Ready:Connect(function(player)
		catchUp(player)
		local profile = S.Data.Get(player)
		if profile then
			for key in profile.Farm.Tiles do
				S.Farm.RenderTile(player, key)
			end
		end
	end)
	S.Farm.Released:Connect(function(player)
		-- Bring every crop up to date so the save holds exact timestamps.
		local profile = S.Data.Get(player)
		if profile then
			local now = GameTime.Now()
			for key, tile in profile.Farm.Tiles do
				if tile.C then
					CropService.Sync(player, key, now)
				end
			end
		end
		local byKey = index[player]
		if byKey then
			for key in table.clone(byKey) do
				untrack(player, key)
			end
		end
		index[player] = nil
	end)
	RunService.Heartbeat:Connect(step)
end

return CropService

-- Fishing: casting, bites, the reeling minigame and catches.
--
-- The server decides everything that matters when you cast: which fish (or
-- junk/treasure) is on the line, when it bites, its difficulty and size. The
-- client only plays the minigame (Config/Fish.Minigame) and reports whether
-- it was won. The server rejects results that are impossible for that fish:
-- resolved before the bite, faster than the minimum reel time for its
-- difficulty, or long after the line would have snapped.
--
--   FishCast(target, baitRef?)  → { Id, BiteIn, Difficulty, Behavior, Zone, Legend }
--   FishResolve(id, { Caught, Perfect }) → catch result
--
-- Fishing spots: water zones from Config/Regions (Tag, Center, Radius), farm
-- ponds (FarmService water tiles) and any terrain water (ToolService.IsWater
-- falls back to the region's first water tag).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local FishConfig = require(Shared.Config.Fish)
local Regions = require(Shared.Config.Regions)
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local ItemUtil = require(Shared.Lib.ItemUtil)
local Stats = require(Shared.Lib.Stats)
local RNG = require(Shared.Lib.RNG)
local GameTime = require(Shared.Lib.GameTime)
local WeatherMath = require(Shared.Lib.WeatherMath)

local S = require(script.Parent)

local GAME = FishConfig.Minigame
local CAST_RANGE = 70
local SLACK = 4
local random = Random.new()

local FishingService = {}

type Cast = {
	Id: string,
	Kind: string, -- "Fish" | "Junk" | "Treasure"
	Item: string,
	Water: string,
	Region: string,
	Target: Vector3,
	CastAt: number,
	BiteAt: number,
	Difficulty: number,
	Bait: string?,
}

local casts: { [Player]: Cast } = {}

-- Water detection ------------------------------------------------------------------------------------------

function FishingService.WaterTagAt(player: Player, position: Vector3): (string?, string?)
	-- Farm ponds
	local farm, gx, gz = S.Farm.FarmAt(position)
	if farm and gx then
		local tag = S.Farm.WaterAt(farm, S.Farm.Key(gx, gz :: number))
		if tag == "Pond" then
			return "Pond", "Homestead"
		end
		return nil, nil
	end
	-- Region water zones
	for _, region in Regions.List do
		for _, water in region.Waters do
			local flat = Vector3.new(position.X - water.Center.X, 0, position.Z - water.Center.Z).Magnitude
			if flat <= water.Radius and math.abs(position.Y - water.Center.Y) <= 30 then
				return water.Tag, region.Id
			end
		end
	end
	-- Any other terrain water counts as the region's main water.
	if S.Tool.IsWater(player, position) then
		local regionId = S.Player.RegionAt(position)
		local region = Registry.Regions[regionId]
		if region and region.Waters[1] then
			return region.Waters[1].Tag, regionId
		end
		return "Pond", regionId
	end
	return nil, nil
end

-- Fish table -------------------------------------------------------------------------------------------------

local function inTime(range: { number }?, hour: number): boolean
	if not range then
		return true
	end
	local from, to = range[1], range[2]
	if from <= to then
		return hour >= from and hour < to
	end
	return hour >= from or hour < to
end

function FishingService.Table(player: Player, water: string, bait: string?): { [string]: number }
	local profile = S.Data.Get(player)
	local t = GameTime.Now()
	local info = GameTime.Info(t)
	local weather = WeatherMath.Current(t)
	local wdef = WeatherMath.Def(weather) or {}
	local wfish = wdef.Fish or {}
	local legendWeight = if profile then 1 + Stats.Effect(profile, "LegendWeight") else 1
	local out = {}
	for _, fish in FishConfig.List do
		local ok = table.find(fish.Waters, water) ~= nil
			and table.find(fish.Seasons, info.SeasonId) ~= nil
			and inTime(fish.Time, info.Hour)
			and (not fish.Weather or table.find(fish.Weather, weather) ~= nil)
			and (not fish.FullMoon or info.FullMoon)
		if ok and fish.Legendary then
			-- Legends only bite on the legendary lure, once per player.
			ok = bait == "legend_lure" and not (profile and profile.Unlocks["Legend_" .. fish.Id])
		end
		if ok then
			local w = FishConfig.RarityWeight[fish.Rarity] or 1
			if fish.Rarity ~= "Common" then
				w *= wfish.Rarity or 1
			end
			for _, tag in fish.Tags or {} do
				if wfish.Tags and wfish.Tags[tag] then
					w *= wfish.Tags[tag]
				end
			end
			if bait and fish.Bait == bait then
				w *= 2
			end
			if bait == "deluxe_bait" and Registry.RarityOrder(fish.Rarity) >= 3 then
				w *= 2
			end
			if fish.Legendary then
				w *= legendWeight
			end
			out[fish.Id] = w
		end
	end
	return out
end

-- Casting --------------------------------------------------------------------------------------------------------

local function cast(player: Player, target: Vector3, baitRef: string?)
	local profile = S.Data.Get(player)
	if not profile then
		return false, "Not ready"
	end
	local character = player.Character
	if not character or character:GetAttribute("Held") ~= "tool_rod" then
		return false, "Hold your fishing rod"
	end
	if not S.Security.InReach(player, target, CAST_RANGE) then
		return false, "That's too far to cast"
	end
	local water, regionId = FishingService.WaterTagAt(player, target)
	if not water or not regionId then
		return false, "Cast into water"
	end
	local ok, why = S.Player.CanAccess(player, regionId)
	if not ok then
		return false, why
	end
	local tier = S.Tool.Tier(player, "rod")
	local tierDef = S.Tool.TierDef(player, "rod")
	-- Bait (rod tier 3+)
	local bait: string? = nil
	if baitRef and baitRef ~= "" then
		local stack = S.Inventory.Slot(player, baitRef)
		local def = stack and Registry.Items[stack.Id]
		if not def or def.Category ~= "Bait" then
			return false, "That isn't bait"
		end
		if tier < 3 and stack.Id ~= "bait" then
			return false, "Upgrade your rod to use special bait"
		end
		bait = stack.Id
	end
	if not S.Player.SpendEnergy(player, tierDef.Energy or 2) then
		return false, "Too tired"
	end
	if bait and random:NextNumber() >= Stats.Effect(profile, "BaitSave") then
		S.Inventory.TakeFromSlot(player, baitRef :: string, 1)
	end
	-- What's on the line?
	local kind, item, difficulty = "Fish", nil, 20
	local treasureChance = FishConfig.TreasureChance * (if tier >= 4 then 1.5 else 1) * (if bait == "magnet_bait" then 3 else 1) + Stats.Effect(profile, "TreasureChance")
	local roll = random:NextNumber()
	if roll < treasureChance then
		kind, item, difficulty = "Treasure", "treasure_chest", 45
	elseif roll < treasureChance + FishConfig.Junk.Chance then
		kind = "Junk"
		item = FishConfig.Junk.Items[random:NextInteger(1, #FishConfig.Junk.Items)]
		difficulty = 5
	else
		local weights = FishingService.Table(player, water, bait)
		item = RNG.WeightedKey(weights, random:NextNumber())
		if not item then
			kind = "Junk"
			item = FishConfig.Junk.Items[1]
			difficulty = 5
		else
			local fish = Registry.Fish[item]
			difficulty = fish.Difficulty
			if fish.Legendary and tier >= 5 then
				difficulty = math.max(40, difficulty - 8)
			end
		end
	end
	-- Bite timing: bait and weather speed it up.
	local weather = WeatherMath.Def(WeatherMath.Current(GameTime.Now())) or {}
	local biteMult = ((weather.Fish and weather.Fish.Bite) or 1) * (if bait then 1.35 else 1)
	local delay = random:NextNumber(GAME.BiteDelay[1], GAME.BiteDelay[2]) / biteMult
	local now = os.clock()
	local id = RNG.Uid("c")
	casts[player] = {
		Id = id,
		Kind = kind,
		Item = item :: string,
		Water = water,
		Region = regionId,
		Target = target,
		CastAt = now,
		BiteAt = now + delay,
		Difficulty = difficulty,
		Bait = bait,
	}
	character:SetAttribute("Act", "Cast@" .. string.format("%.2f", now))
	character:SetAttribute("Bobber", target)
	local fish = Registry.Fish[item :: string]
	local zone = GAME.BaseZone + GAME.ZonePerTier * (tier - 1) + Stats.Effect(profile, "FishZone") * GAME.BaseZone
	return true, {
		Id = id,
		BiteIn = delay,
		Difficulty = difficulty,
		Behavior = if fish then fish.Behavior elseif kind == "Treasure" then "Floater" else "Smooth",
		Zone = math.clamp(zone, 0.12, 0.6),
		Fill = GAME.FillRate * (1 + Stats.Effect(profile, "FishFill")),
		Legend = fish ~= nil and fish.Legendary == true,
		Water = water,
	}
end

-- Resolving ---------------------------------------------------------------------------------------------------------

local function qualityFor(sizeFraction: number, perfect: boolean, rodTier: number): number
	local q = 1
	for i, threshold in FishConfig.QualityBySize do
		if sizeFraction >= threshold then
			q = i + 1
		end
	end
	if perfect then
		q += 1
	end
	if rodTier >= 6 then
		q = math.max(q, 2)
	end
	return math.clamp(q, 1, 6)
end

local function resolve(player: Player, castId: string, outcome: any)
	local c = casts[player]
	local character = player.Character
	if character then
		character:SetAttribute("Bobber", nil)
	end
	if not c or c.Id ~= castId then
		return false, "No bite"
	end
	casts[player] = nil
	if type(outcome) ~= "table" or not outcome.Caught then
		S.Notify.FX(c.Target, "FishEscape", { By = player.UserId }, 80)
		return true, { Caught = false }
	end
	local now = os.clock()
	local minReel = GAME.MinSeconds * (1 + c.Difficulty / 100)
	local elapsed = now - c.BiteAt
	if elapsed < minReel - 0.25 then
		S.Security.Flag(player, "Fish reeled impossibly fast", 2)
		return false, "The line slipped"
	end
	if now - c.CastAt > GAME.MaxSeconds + GAME.BiteDelay[2] + SLACK then
		return false, "The fish got away"
	end
	local profile = S.Data.Get(player)
	local tier = S.Tool.Tier(player, "rod")
	local stack
	local fish = Registry.Fish[c.Item]
	if c.Kind == "Fish" and fish then
		local luck = random:NextNumber() ^ (1 / (1 + Stats.SkillLevel(profile, "Fishing") / 40))
		local size = fish.Size[1] + (fish.Size[2] - fish.Size[1]) * luck
		local fraction = (size - fish.Size[1]) / math.max(1, fish.Size[2] - fish.Size[1])
		local q = qualityFor(fraction, outcome.Perfect == true, tier)
		stack = ItemUtil.New(fish.Id, 1, q)
		stack.S = math.floor(size * 10) / 10
		if fraction >= 0.95 or fish.Legendary then
			stack.U = RNG.Uid("sp") -- a specimen: unique, shows size in the book and contests
		end
		S.Data.AddStat(player, "FishCaught")
		S.Data.MaxStat(player, "BiggestFish", math.floor(size))
		if fish.Legendary then
			S.Data.AddStat(player, "LegendaryFish")
			profile.Unlocks["Legend_" .. fish.Id] = true
			S.Data.Changed(player, "Unlocks")
			S.Notify.BannerAll("🐉 " .. player.DisplayName .. " caught " .. fish.Name .. "!", "A legend of the valley, landed at last.", "Legend")
		end
		S.Quest.Progress(player, "Catch", fish.Id, 1, { Quality = q, Size = size })
		local xp = 6 + (Registry.RarityOrder(fish.Rarity) - 1) * 14 + math.floor(fish.Difficulty / 5)
		S.Skill.AddXP(player, "Fishing", xp)
		S.Festival.OnCatch(player, fish.Id, size, q)
	elseif c.Kind == "Treasure" then
		stack = ItemUtil.New("treasure_chest", 1)
		S.Data.AddStat(player, "TreasuresFished")
		S.Skill.AddXP(player, "Fishing", 20)
	else
		stack = ItemUtil.New(c.Item, 1)
		S.Skill.AddXP(player, "Fishing", 2)
	end
	S.Inventory.Add(player, stack, { Source = "Fishing", Position = c.Target })
	S.Collection.OnItem(player, stack)
	for _, itemId in S.Quest.DropsFor(player, "Fish", c.Region) do
		S.Inventory.Give(player, itemId, 1, nil, nil, { Source = "Fishing" })
	end
	S.Tutorial.Event(player, "Fish")
	S.Notify.FX(c.Target, "Catch", { Item = stack.Id, Q = stack.Q, Size = stack.S, By = player.UserId, Legend = fish ~= nil and fish.Legendary == true }, 120)
	if character then
		character:SetAttribute("Act", "Catch@" .. string.format("%.2f", now))
	end
	return true, { Caught = true, Stack = stack }
end

-- Lifecycle ---------------------------------------------------------------------------------------------------------

function FishingService.Init()
	Net.Handle("FishCast", cast)
	Net.Handle("FishResolve", resolve)
end

function FishingService.Start()
	Players.PlayerRemoving:Connect(function(player)
		casts[player] = nil
	end)
end

return FishingService

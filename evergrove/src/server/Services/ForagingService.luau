-- Foraging, bug catching and dig spots out in the world.
--
-- Spots are anchor parts in workspace.Gatherables.<Region> with attributes the
-- client renders from:
--   Forage anchors  Kind="Forage", Item=<id> (rerolled each in-game morning)
--   Bug points      Kind="Bug", Bug=<id>, Until=<unix> (a bug visits for a while)
--   Dig spots       Kind="Dig" (wiggling worms; rerolled each morning)
--
-- Everyone sees the same spots, but each player collects their own copy:
-- profile.Gather = { Day, Got = { [spotId] = true } } (replicated, so the
-- client hides what you've already picked). Nobody can steal your forage.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Gathering = require(Shared.Config.Gathering)
local Regions = require(Shared.Config.Regions)
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local ItemUtil = require(Shared.Lib.ItemUtil)
local Stats = require(Shared.Lib.Stats)
local RNG = require(Shared.Lib.RNG)
local GameTime = require(Shared.Lib.GameTime)
local WeatherMath = require(Shared.Lib.WeatherMath)

local S = require(script.Parent)

local REACH = Gathering.Reach
local DIG_ENERGY = 4
local random = Random.new()

local ForagingService = {}

type Spot = { Id: string, Region: string, Kind: string, Part: BasePart, Position: Vector3, Index: number }

local spots: { [string]: Spot } = {}
local bugCaught: { [Player]: { [string]: number } } = {} -- player → point id → bug window caught/fled
local root: Folder
local currentDay = -1

local RARITY_WEIGHT = { Common = 60, Uncommon = 25, Rare = 9, Epic = 3, Legendary = 1, Mythic = 0.3 }

-- Spots reroll at 6 AM, so the "forage day" starts at dawn rather than midnight.
local function forageDay(): number
	return GameTime.DayIndex(GameTime.Now() - 6 * GameTime.HOUR)
end

-- Spot anchors ------------------------------------------------------------------------------------------

local function anchor(region: string, id: string, kind: string, position: Vector3, index: number): Spot
	local folder = root:FindFirstChild(region) :: Folder?
	if not folder then
		local f = Instance.new("Folder")
		f.Name = region
		f.Parent = root
		folder = f
	end
	local part = Instance.new("Part")
	part.Name = id
	part.Size = Vector3.new(2, 2, 2)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part.Position = position + Vector3.new(0, 1, 0)
	part:SetAttribute("Kind", kind)
	part:SetAttribute("Spot", id)
	part.Parent = folder
	local spot = { Id = id, Region = region, Kind = kind, Part = part, Position = position, Index = index }
	spots[id] = spot
	return spot
end

local function buildSpots()
	for _, region in Regions.List do
		local forage = Gathering.ForagePerRegion
		local bugs = Gathering.BugPointsPerRegion
		local digs = Gathering.DigSpotsPerRegion + 3 -- a few extra positions so daily picks vary
		if #region.Forage == 0 then
			forage = 0
		end
		if #region.Bugs == 0 then
			bugs = 0
		end
		for i = 1, forage do
			local id = region.Id .. "_f" .. i
			local point = S.World.SpawnPoint(region.Id, RNG.HashInt(id), 3)
			if point then
				anchor(region.Id, id, "Forage", point, i)
			end
		end
		for i = 1, bugs do
			local id = region.Id .. "_b" .. i
			local point = S.World.SpawnPoint(region.Id, RNG.HashInt(id), 3)
			if point then
				anchor(region.Id, id, "Bug", point, i)
			end
		end
		for i = 1, digs do
			local id = region.Id .. "_d" .. i
			local point = S.World.SpawnPoint(region.Id, RNG.HashInt(id), 3)
			if point then
				anchor(region.Id, id, "Dig", point, i)
			end
		end
	end
end

-- Daily reroll ------------------------------------------------------------------------------------------------

local function forageFor(region: any, day: number, index: number, info: any): string?
	local options = {}
	for _, id in region.Forage do
		local def = Registry.Forage[id]
		if def and table.find(def.Seasons, info.SeasonId) then
			options[id] = RARITY_WEIGHT[def.Rarity] or 1
		end
	end
	if next(options) == nil then
		return nil
	end
	-- Not every spot has something every day.
	if RNG.Hash("forage-empty", region.Id, day, index) < 0.15 then
		return nil
	end
	return RNG.WeightedKey(options, RNG.Hash("forage", region.Id, day, index))
end

local function reroll(day: number)
	currentDay = day
	local info = GameTime.Info()
	for _, spot in spots do
		local region = Registry.Regions[spot.Region]
		if spot.Kind == "Forage" then
			spot.Part:SetAttribute("Item", forageFor(region, day, spot.Index, info))
			spot.Part:SetAttribute("Day", day)
		elseif spot.Kind == "Dig" then
			local active = RNG.Hash("dig", spot.Region, day, spot.Index)
				< Gathering.DigSpotsPerRegion / (Gathering.DigSpotsPerRegion + 3)
			spot.Part:SetAttribute("Active", active)
			spot.Part:SetAttribute("Day", day)
		end
	end
end

-- Bugs visit points in windows of (lifetime + respawn) seconds.
local WINDOW = Gathering.BugLifetime + Gathering.BugRespawn

local function bugFor(region: any, spot: Spot, window: number, info: any, weather: string): string?
	if RNG.Hash("bug-empty", spot.Id, window) < 0.35 then
		return nil
	end
	local options = {}
	local hour = info.Hour
	for _, id in region.Bugs do
		local def = Registry.Bugs[id]
		if def then
			local seasonOk = not def.Seasons or table.find(def.Seasons, info.SeasonId) ~= nil
			local timeOk = true
			if def.Time then
				local from, to = def.Time[1], def.Time[2]
				timeOk = if from <= to then hour >= from and hour < to else hour >= from or hour < to
			end
			local weatherOk = not def.Weather or table.find(def.Weather, weather) ~= nil
			if seasonOk and timeOk and weatherOk then
				options[id] = RARITY_WEIGHT[def.Rarity] or 1
			end
		end
	end
	if next(options) == nil then
		return nil
	end
	return RNG.WeightedKey(options, RNG.Hash("bug", spot.Id, window))
end

local function updateBugs()
	local now = os.time()
	local window = now // WINDOW
	local phase = now % WINDOW
	local info = GameTime.Info()
	local weather = WeatherMath.Current(GameTime.Now())
	for _, spot in spots do
		if spot.Kind == "Bug" then
			local region = Registry.Regions[spot.Region]
			local bug = if phase < Gathering.BugLifetime then bugFor(region, spot, window, info, weather) else nil
			if spot.Part:GetAttribute("Bug") ~= bug then
				spot.Part:SetAttribute("Bug", bug)
				spot.Part:SetAttribute("Window", window)
				spot.Part:SetAttribute("Until", if bug then window * WINDOW + Gathering.BugLifetime else nil)
			end
		end
	end
end

-- Player state ------------------------------------------------------------------------------------------------------

local function gather(profile: any): any
	local today = forageDay()
	profile.Gather = profile.Gather or { Day = today, Got = {} }
	if profile.Gather.Day ~= today then
		profile.Gather.Day = today
		profile.Gather.Got = {}
	end
	return profile.Gather
end

local function check(player: Player, spotId: string, kind: string): (Spot?, any?, string?)
	local spot = spots[spotId]
	local profile = S.Data.Get(player)
	if not spot or spot.Kind ~= kind or not profile then
		return nil, nil, "Nothing there"
	end
	if not S.Security.InReach(player, spot.Position, REACH) then
		return nil, nil, "Too far away"
	end
	local ok, why = S.Player.CanAccess(player, spot.Region)
	if not ok then
		return nil, nil, why
	end
	return spot, profile, nil
end

local function forageQuality(profile: any): number
	local level = Stats.SkillLevel(profile, "Foraging")
	local roll = random:NextNumber() + level / 100 + Stats.Effect(profile, "ForageQuality")
	if roll > 1.35 then
		return 4
	elseif roll > 1.05 then
		return 3
	elseif roll > 0.8 then
		return 2
	end
	return 1
end

local function questDrops(player: Player, source: string, region: string, position: Vector3)
	for _, itemId in S.Quest.DropsFor(player, source, region) do
		S.Inventory.Give(player, itemId, 1, nil, nil, { Source = "Found", Position = position })
	end
end

-- Actions --------------------------------------------------------------------------------------------------------------

local function collect(player: Player, spotId: string)
	local spot, profile, reason = check(player, spotId, "Forage")
	if not spot then
		return false, reason
	end
	local itemId = spot.Part:GetAttribute("Item")
	local state = gather(profile)
	if type(itemId) ~= "string" or state.Got[spotId] then
		return false, "Nothing left here today"
	end
	state.Got[spotId] = true
	S.Data.Changed(player, "Gather")
	local count = if random:NextNumber() < Stats.Effect(profile, "ForageDouble") then 2 else 1
	local stack = ItemUtil.New(itemId, count, forageQuality(profile))
	S.Inventory.Add(player, stack, { Source = "Forage", Position = spot.Position })
	S.Collection.OnItem(player, stack)
	if random:NextNumber() < Stats.Effect(profile, "ForageSeeds") then
		-- Wild seeds: a random common crop in season.
		local info = GameTime.Info()
		local options = {}
		for _, crop in Registry.Crops do
			if crop.Rarity == "Common" and table.find(crop.Seasons, info.SeasonId) then
				table.insert(options, crop.Id)
			end
		end
		if #options > 0 then
			S.Inventory.Give(
				player,
				"seed_" .. options[random:NextInteger(1, #options)],
				1,
				nil,
				nil,
				{ Source = "Wild Seeds" }
			)
		end
	end
	questDrops(player, "Forage", spot.Region, spot.Position)
	S.Skill.AddXP(player, "Foraging", 4 + (Registry.RarityOrder(Registry.Items[itemId].Rarity) - 1) * 6)
	S.Data.AddStat(player, "ForageCollected", count)
	S.Quest.Progress(player, "Forage", itemId, count)
	S.Notify.FX(spot.Position, "Forage", { Spot = spotId, Item = itemId, By = player.UserId }, 60)
	local character = player.Character
	if character then
		character:SetAttribute("Act", "Pick@" .. string.format("%.2f", os.clock()))
	end
	return true, stack
end

local function catchBug(player: Player, spotId: string)
	local spot, profile, reason = check(player, spotId, "Bug")
	if not spot then
		return false, reason
	end
	local held = player.Character and player.Character:GetAttribute("Held")
	if held ~= "tool_net" then
		return false, "Hold your bug net"
	end
	local bugId = spot.Part:GetAttribute("Bug")
	local window = spot.Part:GetAttribute("Window")
	if type(bugId) ~= "string" then
		return false, "It flew away"
	end
	bugCaught[player] = bugCaught[player] or {}
	if bugCaught[player][spotId] == window then
		return false, "It's gone"
	end
	bugCaught[player][spotId] = window
	local def = Registry.Bugs[bugId]
	local tier = S.Tool.Tier(player, "net")
	local chance =
		math.clamp(0.55 + tier * 0.08 + Stats.Effect(profile, "NetRadius") * 0.05 - def.Speed * 0.04, 0.15, 0.98)
	local character = player.Character
	if character then
		character:SetAttribute("Act", "Net@" .. string.format("%.2f", os.clock()))
	end
	if random:NextNumber() > chance then
		S.Notify.FX(spot.Position, "BugFlee", { Spot = spotId, By = player.UserId }, 60)
		return false, "The " .. def.Name .. " got away!"
	end
	local stack = ItemUtil.New(bugId, 1)
	S.Inventory.Add(player, stack, { Source = "Bug net", Position = spot.Position })
	S.Collection.OnItem(player, stack)
	S.Skill.AddXP(player, "Foraging", 6 + (Registry.RarityOrder(def.Rarity) - 1) * 10)
	S.Data.AddStat(player, "BugsCaught")
	S.Quest.Progress(player, "Bug", bugId, 1)
	S.Notify.FX(spot.Position, "BugCatch", { Spot = spotId, Bug = bugId, By = player.UserId }, 60)
	return true, stack
end

-- Dig a spot with the shovel (ToolService forwards shovel use on a spot here).
function ForagingService.Dig(player: Player, spotId: string): (boolean, string?)
	local spot, profile, reason = check(player, spotId, "Dig")
	if not spot then
		return false, reason
	end
	local state = gather(profile)
	if not spot.Part:GetAttribute("Active") or state.Got[spotId] then
		return false, "Nothing buried here today"
	end
	if not S.Player.SpendEnergy(player, DIG_ENERGY) then
		return false, "Too tired"
	end
	state.Got[spotId] = true
	S.Data.Changed(player, "Gather")
	local region = Registry.Regions[spot.Region]
	local weights = {}
	local artifactBoost = 1 + Stats.Effect(profile, "ArtifactChance")
	for _, entry in region.Dig do
		local def = Registry.Items[entry.Id]
		if def then
			local w = entry.Weight
			if def.Category == "Artifact" or def.Tags.Artifact then
				w *= artifactBoost
			end
			weights[entry.Id] = (weights[entry.Id] or 0) + w
		end
	end
	local found = {}
	local first = RNG.WeightedKey(weights, random:NextNumber())
	if first then
		table.insert(found, first)
	end
	if random:NextNumber() < 0.2 + Stats.Effect(profile, "TreasureChance") then
		local second = RNG.WeightedKey(weights, random:NextNumber())
		if second then
			table.insert(found, second)
		end
	end
	for _, id in found do
		local stack =
			ItemUtil.New(id, if id == "clay" or id == "sand" or id == "worm" then random:NextInteger(1, 3) else 1)
		S.Inventory.Add(player, stack, { Source = "Dig spot", Position = spot.Position })
		S.Collection.OnItem(player, stack)
	end
	questDrops(player, "Dig", spot.Region, spot.Position)
	S.Skill.AddXP(player, "Exploration", 8)
	S.Data.AddStat(player, "SpotsDug")
	S.Quest.Progress(player, "Dig", found[1] or "*", 1)
	S.Notify.FX(spot.Position, "Dig", { Spot = spotId, Items = found, By = player.UserId }, 80)
	local character = player.Character
	if character then
		character:SetAttribute("Act", "Dig@" .. string.format("%.2f", os.clock()))
	end
	return true
end

-- Lifecycle ----------------------------------------------------------------------------------------------------------

function ForagingService.Init()
	root = Instance.new("Folder")
	root.Name = "Gatherables"
	root.Parent = workspace
	Net.Handle("ForageCollect", collect)
	Net.Handle("BugCatch", catchBug)
	Net.Handle("DigSpot", function(player, spotId)
		return ForagingService.Dig(player, spotId)
	end)
end

function ForagingService.Start()
	task.spawn(function()
		buildSpots()
		reroll(forageDay())
		updateBugs()
		while true do
			task.wait(3)
			local day = forageDay()
			if day ~= currentDay then
				reroll(day)
			end
			updateBugs()
		end
	end)
	S.Data.Loaded:Connect(function(_player, profile)
		gather(profile)
	end)
	Players.PlayerRemoving:Connect(function(player)
		bugCaught[player] = nil
	end)
end

return ForagingService

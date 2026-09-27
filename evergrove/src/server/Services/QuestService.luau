-- Quests: story chapters, villager quests, daily requests, weekly challenges
-- and server-wide community goals.
--
-- Gameplay services report what happened with Progress(player, type, target,
-- count, meta). Matching objectives of active quests (and today's dailies,
-- this week's weeklies and the community goal) move forward. Deliver
-- objectives are checked and consumed when the quest is turned in.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local QuestsConfig = require(Shared.Config.Quests)
local CropsConfig = require(Shared.Config.Crops)
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local Stats = require(Shared.Lib.Stats)
local GameTime = require(Shared.Lib.GameTime)
local RNG = require(Shared.Lib.RNG)
local CropMath = require(Shared.Lib.CropMath)

local S = require(script.Parent)

local QuestService = {}

local ITEM_TYPES = { Harvest = true, Deliver = true, Sell = false, Craft = true, Process = true, Cook = true, Catch = true, Forage = true, Bug = true, Plant = true }

-- Matching -------------------------------------------------------------------------------------------

local function matches(objective: any, kind: string, target: string?, meta: any?): boolean
	if objective.Type ~= kind then
		return false
	end
	if objective.Quality and (not meta or (meta.Quality or 1) < objective.Quality) then
		return false
	end
	local want = objective.Target
	if want == nil or want == "*" then
		return true
	end
	if target == nil then
		return false
	end
	if ITEM_TYPES[kind] and Registry.Items[target] then
		return Registry.Matches(target, want)
	end
	if kind == "Place" then
		return Registry.Matches(target, want)
	end
	return want == target
end

local function objectiveDone(player: Player, profile: any, objective: any, progress: number): boolean
	if objective.Type == "Deliver" then
		return S.Inventory.Count(player, objective.Target, objective.Quality) >= objective.Count
	elseif objective.Type == "Reach" then
		local npcId = string.match(objective.Target or "", "^Hearts:(.+)$")
		if npcId then
			return Stats.Hearts(profile, npcId) >= objective.Count
		end
		return Stats.SkillLevel(profile, objective.Target) >= objective.Count
	end
	return progress >= objective.Count
end

-- Availability ---------------------------------------------------------------------------------------

function QuestService.RequirementsMet(player: Player, profile: any, quest: any): boolean
	local req = quest.Requires
	if not req then
		return true
	end
	if req.Quest and not profile.Quests.Done[req.Quest] then
		return false
	end
	if req.Hearts and Stats.Hearts(profile, req.Hearts[1]) < req.Hearts[2] then
		return false
	end
	if req.Estate and Stats.EstateLevel(profile) < req.Estate then
		return false
	end
	if req.Skill and Stats.SkillLevel(profile, req.Skill[1]) < req.Skill[2] then
		return false
	end
	if req.Project and not (profile.Projects[req.Project] and profile.Projects[req.Project].Done) then
		return false
	end
	if req.Item and S.Inventory.Count(player, req.Item) <= 0 then
		return false
	end
	-- Villagers who haven't arrived yet can't give quests.
	if quest.Giver and not S.NPC.IsUnlocked(player, quest.Giver) then
		return false
	end
	return true
end

function QuestService.Available(player: Player): { string }
	local profile = S.Data.Get(player)
	local out = {}
	if not profile then
		return out
	end
	for _, quest in QuestsConfig.List do
		if not profile.Quests.Active[quest.Id] and not profile.Quests.Done[quest.Id] and QuestService.RequirementsMet(player, profile, quest) then
			table.insert(out, quest.Id)
		end
	end
	return out
end

local function startQuest(player: Player, profile: any, quest: any, silent: boolean?)
	local progress = table.create(#quest.Objectives, 0)
	profile.Quests.Active[quest.Id] = { P = progress, At = GameTime.Now() }
	if #profile.Quests.Tracked < QuestsConfig.MaxTracked and not table.find(profile.Quests.Tracked, quest.Id) then
		table.insert(profile.Quests.Tracked, quest.Id)
	end
	S.Data.Changed(player, "Quests")
	if not silent then
		S.Notify.Quest(player, "Started", quest.Id)
	end
	-- Objectives already satisfied (e.g. Reach) complete immediately if nothing needs turning in.
	QuestService.CheckComplete(player, quest.Id)
end

-- Auto-accept quests whose requirements are met.
function QuestService.Refresh(player: Player)
	local profile = S.Data.Get(player)
	if not profile then
		return
	end
	local active = 0
	for _ in profile.Quests.Active do
		active += 1
	end
	for _, quest in QuestsConfig.List do
		if active >= QuestsConfig.MaxActive then
			break
		end
		if quest.Auto and not profile.Quests.Active[quest.Id] and not profile.Quests.Done[quest.Id] then
			if QuestService.RequirementsMet(player, profile, quest) then
				startQuest(player, profile, quest)
				active += 1
			end
		end
	end
end

-- Completion --------------------------------------------------------------------------------------------

local function ready(player: Player, profile: any, quest: any): boolean
	local state = profile.Quests.Active[quest.Id]
	if not state then
		return false
	end
	for i, objective in quest.Objectives do
		if not objectiveDone(player, profile, objective, state.P[i] or 0) then
			return false
		end
	end
	return true
end

local function complete(player: Player, profile: any, quest: any)
	-- Consume deliveries.
	for _, objective in quest.Objectives do
		if objective.Type == "Deliver" then
			if not S.Inventory.Remove(player, objective.Target, objective.Count, objective.Quality) then
				S.Notify.Error(player, "You need " .. objective.Count .. " " .. Registry.SpecName(objective.Target))
				return false
			end
		end
	end
	profile.Quests.Active[quest.Id] = nil
	profile.Quests.Done[quest.Id] = GameTime.Now()
	local tracked = table.find(profile.Quests.Tracked, quest.Id)
	if tracked then
		table.remove(profile.Quests.Tracked, tracked)
	end
	S.Data.Changed(player, "Quests")
	S.Economy.GrantReward(player, quest.Rewards, quest.Name)
	if quest.Rewards.Unlock then
		profile.Unlocks["Npc_" .. quest.Rewards.Unlock] = true
		S.Data.Changed(player, "Unlocks")
		S.NPC.RefreshVisibility(player)
	end
	if quest.Giver then
		S.Friendship.Add(player, quest.Giver, require(Shared.Config.NPCs).QuestPoints)
	end
	S.Data.AddStat(player, "QuestsCompleted")
	S.Notify.Quest(player, "Completed", quest.Id)
	if quest.Finish and quest.TurnIn then
		S.NPC.Say(player, quest.TurnIn, quest.Finish)
	end
	QuestService.Refresh(player)
	return true
end

function QuestService.CheckComplete(player: Player, questId: string)
	local profile = S.Data.Get(player)
	local quest = Registry.Quests[questId]
	if not profile or not quest or not ready(player, profile, quest) then
		return
	end
	if quest.TurnIn then
		local state = profile.Quests.Active[questId]
		if not state.Ready then
			state.Ready = true
			S.Data.Changed(player, "Quests")
			S.Notify.Quest(player, "Ready", questId, { TurnIn = quest.TurnIn })
		end
	else
		complete(player, profile, quest)
	end
end

local function turnIn(player: Player, questId: string)
	local profile = S.Data.Get(player)
	local quest = Registry.Quests[questId]
	if not profile or not quest or not profile.Quests.Active[questId] then
		return false, "You're not on that quest"
	end
	if quest.TurnIn and not S.NPC.Near(player, quest.TurnIn) then
		return false, "Talk to " .. Registry.Npcs[quest.TurnIn].Name
	end
	if not ready(player, profile, quest) then
		return false, "Not finished yet"
	end
	return complete(player, profile, quest)
end

-- Talking to an NPC can complete Talk objectives and turn quests in.
function QuestService.OnTalk(player: Player, npcId: string): { string }
	QuestService.Progress(player, "Talk", npcId, 1)
	local profile = S.Data.Get(player)
	local finished = {}
	if not profile then
		return finished
	end
	for questId in table.clone(profile.Quests.Active) do
		local quest = Registry.Quests[questId]
		if quest and quest.TurnIn == npcId and ready(player, profile, quest) then
			if complete(player, profile, quest) then
				table.insert(finished, questId)
			end
		end
	end
	return finished
end

-- Progress ----------------------------------------------------------------------------------------------------

local communityProgress = 0
local communityContributors: { [number]: number } = {}
local communityDay = -1
local communityDone = false

local function currentCommunity()
	local day = GameTime.Info().Day
	local list = QuestsConfig.Community
	return list[(day % #list) + 1], day
end

local function dailyRewardScale(profile: any): number
	return 1 + QuestsConfig.EstateScale * (Stats.EstateLevel(profile) - 1)
end

local function progressList(player: Player, profile: any, listName: string, kind: string, target: string?, count: number, meta: any?)
	local list = profile.Quests[listName]
	if not list or not list.List then
		return
	end
	for _, entry in list.List do
		if not entry.Done and matches(entry, kind, target, meta) then
			entry.P = math.min(entry.Count, (entry.P or 0) + count)
			if entry.P >= entry.Count then
				entry.Done = true
				local template
				local templates: { any } = if listName == "Daily" then QuestsConfig.Daily else QuestsConfig.Weekly
				for _, t in templates do
					if t.Id == entry.Id then
						template = t
					end
				end
				if template then
					local reward = table.clone(template.Reward)
					if reward.Coins then
						reward.Coins = math.floor(reward.Coins * dailyRewardScale(profile))
					end
					S.Economy.GrantReward(player, reward, template.Name)
				end
				S.Notify.Quest(player, "Completed", entry.Id, { List = listName, Name = template and template.Name })
				if listName == "Daily" then
					S.Data.AddStat(player, "DailiesCompleted")
					QuestService.Progress(player, "Daily", "*", 1)
				end
			end
			S.Data.Changed(player, "Quests", listName)
		end
	end
end

-- Report an event. meta: { Quality = tier }
function QuestService.Progress(player: Player, kind: string, target: string?, count: number, meta: any?)
	local profile = S.Data.Get(player)
	if not profile or count < 0 then
		return
	end
	local changed = false
	for questId, state in profile.Quests.Active do
		local quest = Registry.Quests[questId]
		if quest then
			for i, objective in quest.Objectives do
				if objective.Type ~= "Deliver" and matches(objective, kind, target, meta) then
					local before = state.P[i] or 0
					if before < objective.Count then
						state.P[i] = math.min(objective.Count, before + count)
						changed = true
					end
				end
			end
			if changed then
				QuestService.CheckComplete(player, questId)
			end
		end
	end
	if kind == "Reach" or kind == "Talk" then
		-- Reach objectives are evaluated live; re-check anything waiting on them.
		for questId in table.clone(profile.Quests.Active) do
			QuestService.CheckComplete(player, questId)
		end
	end
	if changed then
		S.Data.Changed(player, "Quests", "Active")
	end
	progressList(player, profile, "Daily", kind, target, count, meta)
	progressList(player, profile, "Weekly", kind, target, count, meta)

	-- Community goal (server-wide).
	local goal = currentCommunity()
	if not communityDone and goal and count > 0 and matches(goal.Objective, kind, target, meta) then
		communityProgress += count
		communityContributors[player.UserId] = (communityContributors[player.UserId] or 0) + count
		if communityProgress >= goal.Objective.Count then
			communityDone = true
			for userId in communityContributors do
				local contributor = Players:GetPlayerByUserId(userId)
				if contributor then
					S.Economy.GrantReward(contributor, goal.Reward, goal.Name)
					S.Notify.Banner(contributor, "Community goal complete!", goal.Name .. " — thanks for helping!", "Quest", "🤝")
				end
			end
		end
	end
end

-- Inventory changes can make Deliver objectives ready.
function QuestService.OnItemGained(player: Player, _stack: any)
	local profile = S.Data.Get(player)
	if not profile then
		return
	end
	for questId in profile.Quests.Active do
		local quest = Registry.Quests[questId]
		if quest and quest.TurnIn then
			for _, objective in quest.Objectives do
				if objective.Type == "Deliver" then
					QuestService.CheckComplete(player, questId)
					break
				end
			end
		end
	end
end

-- Quest items that drop only while a quest is active (and you don't have them yet).
function QuestService.DropsFor(player: Player, source: string, regionId: string?): { string }
	local profile = S.Data.Get(player)
	local out = {}
	if not profile then
		return out
	end
	for _, drop in QuestsConfig.Drops do
		if drop.Source == source and profile.Quests.Active[drop.Quest] and (not drop.Region or drop.Region == regionId) then
			local flag = "Drop_" .. drop.Quest .. "_" .. drop.Tag
			if not profile.Unlocks[flag] and math.random() < drop.Chance then
				profile.Unlocks[flag] = true
				S.Data.Changed(player, "Unlocks")
				table.insert(out, drop.Item)
			end
		end
	end
	return out
end

-- Daily & weekly generation -----------------------------------------------------------------------------------

local function seasonalTarget(seed: number): string
	local info = GameTime.Info()
	local options = {}
	for _, crop in CropsConfig.List do
		if crop.Seed and CropMath.InSeason(crop, info.SeasonId) and crop.Rarity == "Common" then
			table.insert(options, crop.Id)
		end
	end
	if #options == 0 then
		return "carrot"
	end
	return options[1 + seed % #options]
end

local function requestTarget(seed: number): string
	local pool = { "#Fruit", "#Vegetable", "#Egg", "#Fish", "#Flower", "#Artisan", "#Mushroom" }
	return pool[1 + seed % #pool]
end

local function makeList(player: Player, profile: any, templates: { any }, count: number, salt: string)
	local list = {}
	local used = {}
	local estate = Stats.EstateLevel(profile)
	local scale = dailyRewardScale(profile)
	local attempts = 0
	while #list < count and attempts < 60 do
		attempts += 1
		local seed = RNG.HashInt(salt, player.UserId, attempts)
		local template = templates[1 + seed % #templates]
		if not used[template.Id] and (template.MinEstate or 1) <= estate then
			used[template.Id] = true
			local objective = template.Objective
			local target = objective.Target
			if target == "@Seasonal" then
				target = seasonalTarget(seed)
			elseif target == "@Request" then
				target = requestTarget(seed)
			end
			local goal = objective.Count
			if template.Scale then
				goal = math.floor(goal * scale)
			end
			table.insert(list, {
				Id = template.Id,
				Type = if objective.Type == "Deliver" then "Harvest" else objective.Type,
				Target = target,
				Count = goal,
				Quality = objective.Quality,
				P = 0,
				Done = false,
			})
		end
	end
	return list
end

function QuestService.RefreshDaily(player: Player)
	local profile = S.Data.Get(player)
	if not profile then
		return
	end
	-- Daily requests follow the real (UTC) day so they don't churn every 20 minutes.
	local realDay = math.floor(os.time() / 86400)
	if profile.Quests.Daily.Day ~= realDay then
		profile.Quests.Daily = { Day = realDay, List = makeList(player, profile, QuestsConfig.Daily, QuestsConfig.DailyCount, "daily" .. realDay) }
		S.Data.Changed(player, "Quests", "Daily")
	end
	local week = math.floor(realDay / 7)
	if profile.Quests.Weekly.Week ~= week then
		profile.Quests.Weekly = { Week = week, List = makeList(player, profile, QuestsConfig.Weekly, QuestsConfig.WeeklyCount, "weekly" .. week) }
		S.Data.Changed(player, "Quests", "Weekly")
	end
end

-- Community goal state for the quest board.
function QuestService.CommunityState()
	local goal, day = currentCommunity()
	if day ~= communityDay then
		communityDay = day
		communityProgress = 0
		communityDone = false
		table.clear(communityContributors)
	end
	local contributors = 0
	for _ in communityContributors do
		contributors += 1
	end
	return { Id = goal.Id, Name = goal.Name, Progress = communityProgress, Goal = goal.Objective.Count, Contributors = contributors, Done = communityDone, Reward = goal.Reward }
end

-- Handlers ---------------------------------------------------------------------------------------------------------

local function accept(player: Player, questId: string)
	local profile = S.Data.Get(player)
	local quest = Registry.Quests[questId]
	if not profile or not quest then
		return false, "Unknown quest"
	end
	if profile.Quests.Active[questId] or profile.Quests.Done[questId] then
		return false, "Already taken"
	end
	if not QuestService.RequirementsMet(player, profile, quest) then
		return false, "Not available yet"
	end
	local active = 0
	for _ in profile.Quests.Active do
		active += 1
	end
	if active >= QuestsConfig.MaxActive then
		return false, "Your quest log is full"
	end
	startQuest(player, profile, quest)
	return true
end

local function abandon(player: Player, questId: string)
	local profile = S.Data.Get(player)
	local quest = Registry.Quests[questId]
	if not profile or not quest or not profile.Quests.Active[questId] then
		return false, "Not on that quest"
	end
	if quest.Kind == "Story" then
		return false, "Story quests can't be abandoned"
	end
	profile.Quests.Active[questId] = nil
	local tracked = table.find(profile.Quests.Tracked, questId)
	if tracked then
		table.remove(profile.Quests.Tracked, tracked)
	end
	S.Data.Changed(player, "Quests")
	return true
end

local function track(player: Player, questId: string)
	local profile = S.Data.Get(player)
	if not profile or not profile.Quests.Active[questId] then
		return false, "Not on that quest"
	end
	local tracked = profile.Quests.Tracked
	local index = table.find(tracked, questId)
	if index then
		table.remove(tracked, index)
	else
		if #tracked >= QuestsConfig.MaxTracked then
			table.remove(tracked, 1)
		end
		table.insert(tracked, questId)
	end
	S.Data.Changed(player, "Quests", "Tracked")
	return true
end

function QuestService.Init()
	Net.Handle("QuestAccept", accept)
	Net.Handle("QuestAbandon", abandon)
	Net.Handle("QuestTurnIn", turnIn)
	Net.Handle("QuestTrack", track)
	Net.Handle("BoardGet", function(player)
		return true, {
			Community = QuestService.CommunityState(),
			Available = QuestService.Available(player),
			Contracts = S.Market.ContractBoard(player),
		}
	end)
end

function QuestService.Start()
	S.Data.Loaded:Connect(function(player)
		QuestService.RefreshDaily(player)
		QuestService.Refresh(player)
	end)
	S.Time.NewDay:Connect(function()
		for player in S.Data.All() do
			QuestService.RefreshDaily(player)
			QuestService.Refresh(player)
		end
		QuestService.CommunityState()
	end)
	-- Periodic refresh catches requirement changes from anywhere (hearts, estate...).
	task.spawn(function()
		while true do
			task.wait(15)
			for player in S.Data.All() do
				QuestService.Refresh(player)
				QuestService.RefreshDaily(player)
			end
		end
	end)
end

return QuestService

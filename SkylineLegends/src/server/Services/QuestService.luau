-- Quests: the main story, side quests and expert trials (Config/Quests), plus
-- daily objectives, weekly expeditions and district contracts.
--
-- Every step is checked against validated events (course finishes, moves the
-- movement guard accepted, discoveries, points the character was actually
-- near), never against what the client says it did.
--
-- Profile layout:
--   Quests    = { Active = { [id] = { Step, Progress, Started } }, Completed = { [id] = time }, Pinned = { id } }
--   Daily     = { Day, Picks = { id }, Progress = { [id] = n }, Done = { [id] = true }, Bonus }
--   Weekly    = { Week, Picks, Progress, Done, Seen }
--   Contracts = { Offers = { [district] = { offer } }, Active = contract?, Completed, Refresh }

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Courses = require(ReplicatedStorage.Shared.Config.Courses)
local Districts = require(ReplicatedStorage.Shared.Config.Districts)
local Net = require(ReplicatedStorage.Shared.Net)
local NPCs = require(ReplicatedStorage.Shared.Config.NPCs)
local Progression = require(ReplicatedStorage.Shared.Config.Progression)
local Quests = require(ReplicatedStorage.Shared.Config.Quests)
local Rotation = require(ReplicatedStorage.Shared.Logic.Rotation)
local Stats = require(ReplicatedStorage.Shared.Logic.Stats)
local Tags = require(ReplicatedStorage.Shared.Tags)

local DataService = require(script.Parent.Parent.Data.DataService)
local Events = require(script.Parent.Parent.Events)
local MovementGuard = require(script.Parent.MovementGuard)
local Notify = require(script.Parent.Notify)
local ProgressionService = require(script.Parent.ProgressionService)

local QuestService = {}

local points: { [string]: Vector3 } = {}
local contractPoints: { [string]: { Id: string, Position: Vector3 } } = {}
local contractByDistrict: { [string]: { string } } = {}
local npcSpots: { [string]: Vector3 } = {}

-- Carried packages for deliveries: { [player] = { Quest, Fragile, Expires? } }
local carrying: { [Player]: { QuestId: string?, Contract: boolean?, Fragile: boolean, Expires: number? } } = {}

-- Helpers -------------------------------------------------------------------------------------

local function push(player: Player)
	DataService.Push(player, "Quests")
	DataService.MarkDirty(player)
end

local function district(player: Player): string?
	return MovementGuard.District(player)
end

local function available(profile: any, quest: Quests.Quest, level: number): boolean
	if profile.Quests.Completed[quest.Id] or profile.Quests.Active[quest.Id] then
		return false
	end
	local requires = quest.Requires or {}
	if requires.Level and level < requires.Level then
		return false
	end
	for _, id in requires.Quests or {} do
		if not profile.Quests.Completed[id] then
			return false
		end
	end
	return true
end

function QuestService.Available(player: Player): { string }
	local profile = DataService.Get(player)
	local result = {}
	if not profile then
		return result
	end
	local level = ProgressionService.Level(player)
	for _, quest in Quests.List do
		if available(profile, quest, level) then
			table.insert(result, quest.Id)
		end
	end
	return result
end

local function pin(profile: any, questId: string)
	local pinned = profile.Quests.Pinned
	if table.find(pinned, questId) then
		return
	end
	if #pinned >= Quests.MaxPinned then
		table.remove(pinned, #pinned)
	end
	table.insert(pinned, 1, questId)
end

local function unpin(profile: any, questId: string)
	local index = table.find(profile.Quests.Pinned, questId)
	if index then
		table.remove(profile.Quests.Pinned, index)
	end
end

-- Completion --------------------------------------------------------------------------------------

local checkStep: (Player, string) -> ()

local function completeQuest(player: Player, quest: Quests.Quest)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	profile.Quests.Active[quest.Id] = nil
	profile.Quests.Completed[quest.Id] = os.time()
	unpin(profile, quest.Id)
	if carrying[player] and carrying[player].QuestId == quest.Id then
		carrying[player] = nil
	end
	if quest.Id == "p_graduation" then
		profile.Flags.Graduated = true
	end
	ProgressionService.Grant(player, quest.Rewards, nil, true)
	Notify.Send(player, {
		Kind = "Quest",
		Title = "Quest complete: " .. quest.Name,
		Text = quest.Outro[1],
		XP = quest.Rewards.XP,
		Credits = quest.Rewards.Credits,
		Prestige = quest.Rewards.Prestige,
		Sound = "Quest",
	})
	-- Finishing a chapter's last main quest pays a chapter bonus.
	if quest.Type == "Main" and quest.Chapter then
		local done = true
		for _, other in Quests.List do
			if other.Type == "Main" and other.Chapter == quest.Chapter and not profile.Quests.Completed[other.Id] then
				done = false
				break
			end
		end
		if done and quest.Chapter > 0 then
			ProgressionService.Grant(player, { Prestige = Progression.Prestige.ChapterComplete }, nil, true)
			Notify.Send(player, {
				Kind = "Unlock",
				Title = (Quests.ChapterNames[quest.Chapter] or "Chapter") .. " complete",
				Prestige = Progression.Prestige.ChapterComplete,
				Sound = "Unlock",
			})
		end
	end
	push(player)
	Events.QuestCompleted:Fire(player, quest.Id, quest)
end

local function advance(player: Player, questId: string)
	local profile = DataService.Get(player)
	local quest = Quests.ById[questId]
	if not profile or not quest then
		return
	end
	local state = profile.Quests.Active[questId]
	if not state then
		return
	end
	state.Step += 1
	state.Progress = {}
	if state.Step > #quest.Steps then
		completeQuest(player, quest)
		return
	end
	push(player)
	Notify.Send(player, { Kind = "Objective", Title = quest.Name, Text = quest.Steps[state.Step].Text })
	-- Some steps may already be satisfied (lessons done, crew joined...).
	checkStep(player, questId)
end

local function currentStep(profile: any, questId: string): (Quests.Step?, any)
	local quest = Quests.ById[questId]
	local state = profile.Quests.Active[questId]
	if not quest or not state then
		return nil, nil
	end
	return quest.Steps[state.Step], state
end

local function countSet(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

-- Steps that depend on standing state rather than an event.
checkStep = function(player: Player, questId: string)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local step = currentStep(profile, questId)
	if not step then
		return
	end
	local kind = step.Kind
	if kind == "Lessons" then
		if countSet(profile.Lessons) >= (step.Count or 1) then
			advance(player, questId)
		end
	elseif kind == "Crew" then
		if profile.Crew then
			advance(player, questId)
		end
	elseif kind == "Mastery" then
		local reached = 0
		for _, tier in Stats.MasteryTiers(profile) do
			if tier >= (step.Tier or 1) then
				reached += 1
			end
		end
		if reached >= (step.Count or 1) then
			advance(player, questId)
		end
	elseif kind == "Tower" then
		if (profile.Tower.Highest or 0) >= (step.Floor or 1) then
			advance(player, questId)
		end
	elseif kind == "Course" then
		local record = profile.Courses[step.Course]
		-- A course already conquered to the required standard counts straight away
		-- (but not for no-fall / shortcut / flow conditions, which need a fresh run).
		if record and (record.Completions or 0) > 0 and (record.Medal or 0) >= (step.Medal or 0) then
			if not step.NoFalls and not step.Shortcut and not step.Flow then
				advance(player, questId)
			end
		end
	end
end

-- For each active quest whose current step is `kind`, call fn(step, state, questId).
local function forActive(player: Player, kind: string, fn: (any, any, string) -> boolean?)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local ids = {}
	for questId in profile.Quests.Active do
		table.insert(ids, questId)
	end
	for _, questId in ids do
		local step, state = currentStep(profile, questId)
		if step and state and step.Kind == kind then
			if fn(step, state, questId) then
				advance(player, questId)
			end
		end
	end
end

-- Dailies, weeklies and contracts ---------------------------------------------------------------

local function refreshDaily(player: Player, profile: any)
	local day = Rotation.Day()
	local daily = profile.Daily
	if daily.Day == day then
		return
	end
	daily.Day = day
	daily.Progress = {}
	daily.Done = {}
	daily.Bonus = false
	daily.Picks = {}
	local have = ProgressionService.Abilities(player)
	for tier = 1, 3 do
		local pool = {}
		for _, template in Quests.Daily do
			if template.Tier == tier and (not template.Needs or have[template.Needs]) then
				table.insert(pool, template.Id)
			end
		end
		local pick = Rotation.PickDistinct(pool, 1, Rotation.Hash(player.UserId, day, tier))
		if pick[1] then
			table.insert(daily.Picks, pick[1])
		end
	end
end

local function refreshWeekly(profile: any)
	local week = Rotation.Week()
	local weekly = profile.Weekly
	if weekly.Week == week then
		return
	end
	weekly.Week = week
	weekly.Progress = {}
	weekly.Done = {}
	weekly.Seen = {}
	local ids = {}
	for _, template in Quests.Weekly do
		table.insert(ids, template.Id)
	end
	-- The same three for everyone this week.
	weekly.Picks = Rotation.PickDistinct(ids, 3, Rotation.Hash("weekly", week))
end

local function templateById(list: { any }, id: string): any?
	for _, template in list do
		if template.Id == id then
			return template
		end
	end
	return nil
end

-- Add progress to every daily/weekly objective of `kind` that `filter` accepts.
local function objective(player: Player, kind: string, amount: number, filter: ((any) -> boolean)?, key: any?)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	refreshDaily(player, profile)
	refreshWeekly(profile)
	local changed = false
	for _, entry in
		{
			{ Data = profile.Daily, List = Quests.Daily, Kind = "Daily" },
			{ Data = profile.Weekly, List = Quests.Weekly, Kind = "Weekly" },
		}
	do
		local data = entry.Data
		for index, id in data.Picks do
			local template = templateById(entry.List, id)
			if template and template.Kind == kind and not data.Done[id] and (not filter or filter(template)) then
				local target = template.Count or 1
				if key ~= nil then
					-- Distinct-key objectives (e.g. different districts).
					local seen = data.Seen or {}
					data.Seen = seen
					local seenKey = id .. ":" .. tostring(key)
					if seen[seenKey] then
						continue
					end
					seen[seenKey] = true
				end
				data.Progress[id] = math.min((data.Progress[id] or 0) + amount, target)
				changed = true
				if data.Progress[id] >= target then
					data.Done[id] = true
					local reward = if entry.Kind == "Daily"
						then Quests.DailyRewards[template.Tier or index] or Quests.DailyRewards[1]
						else Quests.WeeklyReward
					ProgressionService.Grant(player, reward, nil, true)
					profile.Stats[if entry.Kind == "Daily" then "Dailies" else "Weeklies"] = (
						profile.Stats[if entry.Kind == "Daily" then "Dailies" else "Weeklies"] or 0
					) + 1
					Notify.Send(player, {
						Kind = "Quest",
						Title = (if entry.Kind == "Daily" then "Daily complete: " else "Expedition complete: ")
							.. template.Text,
						XP = reward.XP,
						Credits = reward.Credits,
						Prestige = reward.Prestige,
						Sound = "Quest",
					})
					Events.ObjectiveCompleted:Fire(player, entry.Kind)
					Events.StatChanged:Fire(player, if entry.Kind == "Daily" then "Dailies" else "Weeklies")
					if entry.Kind == "Daily" and not data.Bonus then
						local all = true
						for _, pick in data.Picks do
							if not data.Done[pick] then
								all = false
							end
						end
						if all then
							data.Bonus = true
							ProgressionService.Grant(player, Quests.DailyBonus, nil, true)
							Notify.Send(player, {
								Kind = "Reward",
								Title = "All dailies done!",
								XP = Quests.DailyBonus.XP,
								Credits = Quests.DailyBonus.Credits,
							})
						end
					end
				end
			end
		end
	end
	if changed then
		DataService.Push(player, "Daily")
		DataService.Push(player, "Weekly")
		DataService.MarkDirty(player)
	end
end

-- Contracts: three offers per district board, refreshed on a timer or when taken.
local function makeOffers(player: Player, profile: any, districtId: string): { any }
	local offers = {}
	local seed = Rotation.Hash(
		player.UserId,
		districtId,
		profile.Contracts.Completed or 0,
		math.floor(os.time() / Quests.ContractRefresh)
	)
	local rng = Rotation.Rng(seed)
	local spots = contractByDistrict[districtId] or {}
	local courses = Courses.Of(districtId, "Course")
	local difficulty = (Districts.ById[districtId] and Districts.ById[districtId].Order or 1)
	for slot = 1, 3 do
		local template = Quests.Contracts[((slot - 1) % #Quests.Contracts) + 1]
		local offer: { [string]: any } = { Kind = template.Kind, Name = template.Name, District = districtId }
		if template.Kind == "Delivery" and #spots >= 2 then
			local from = spots[rng:Int(1, #spots)]
			local to = from
			while to == from do
				to = spots[rng:Int(1, #spots)]
			end
			local distance = (contractPoints[from].Position - contractPoints[to].Position).Magnitude
			offer.From, offer.To = from, to
			offer.Time = math.floor(distance / 14 + 25)
			offer.Text = ("Carry a parcel across %s within %ds."):format(Districts.ById[districtId].Short, offer.Time)
		elseif template.Kind == "Relays" and #spots >= 3 then
			local picks = Rotation.PickDistinct(spots, 3, seed + slot)
			offer.Points = picks
			offer.Time = 90 + difficulty * 10
			offer.Text = ("Ping %d relay points within %ds."):format(#picks, offer.Time)
		elseif #courses > 0 then
			local course = courses[rng:Int(1, #courses)]
			offer.Kind = "Course"
			offer.Name = "Route Certification"
			offer.Course = course.Id
			offer.Medal = if rng:Next() < 0.6 then 2 else 3
			offer.Text = ("Earn %s or better on %s."):format(Courses.MedalNames[offer.Medal], course.Name)
		else
			continue
		end
		offer.Reward = { XP = 140 + difficulty * 40, Credits = 90 + difficulty * 30 }
		table.insert(offers, offer)
	end
	return offers
end

local function finishContract(player: Player, profile: any)
	local contract = profile.Contracts.Active
	if not contract then
		return
	end
	profile.Contracts.Active = nil
	profile.Contracts.Completed = (profile.Contracts.Completed or 0) + 1
	profile.Stats.Contracts = (profile.Stats.Contracts or 0) + 1
	if carrying[player] and carrying[player].Contract then
		carrying[player] = nil
	end
	ProgressionService.Grant(player, contract.Reward, nil, true)
	Notify.Send(player, {
		Kind = "Quest",
		Title = "Contract complete: " .. contract.Name,
		XP = contract.Reward.XP,
		Credits = contract.Reward.Credits,
		Sound = "Quest",
	})
	DataService.Push(player, "Contracts")
	DataService.MarkDirty(player)
	Events.ObjectiveCompleted:Fire(player, "Contract")
	Events.StatChanged:Fire(player, "Contracts")
	objective(player, "Contracts", 1)
end

local function failContract(player: Player, profile: any, reason: string)
	if not profile.Contracts.Active then
		return
	end
	profile.Contracts.Active = nil
	if carrying[player] and carrying[player].Contract then
		carrying[player] = nil
	end
	Notify.Warn(player, "Contract failed: " .. reason)
	DataService.Push(player, "Contracts")
end

-- Points ---------------------------------------------------------------------------------------------

local function onPoint(player: Player, id: any)
	if type(id) ~= "string" then
		return
	end
	local position = points[id] or (contractPoints[id] and contractPoints[id].Position)
	if not position or not MovementGuard.WasNear(player, position, 16, 2) then
		return
	end
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local now = os.time()

	forActive(player, "Reach", function(step)
		return step.Point == id
	end)
	for _, kind in { "Collect", "Activate" } do
		forActive(player, kind, function(step, state)
			if table.find(step.Points, id) and not state.Progress[id] then
				state.Progress[id] = true
				Notify.Send(player, {
					Kind = "Objective",
					Title = step.Text,
					Text = ("%d / %d"):format(countSet(state.Progress), #step.Points),
				})
				push(player)
			end
			return countSet(state.Progress) >= #step.Points
		end)
	end
	forActive(player, "Deliver", function(step, state, questId)
		local carry = carrying[player]
		if id == step.From and not (carry and carry.QuestId == questId) then
			carrying[player] = {
				QuestId = questId,
				Fragile = step.Fragile == true,
				Expires = if step.Time then os.clock() + step.Time else nil,
			}
			state.Progress = {}
			Notify.Send(player, {
				Kind = "Objective",
				Title = "Package picked up",
				Text = if step.Fragile
					then "Fragile! No stumbles or falls."
					elseif step.Time then ("You have %ds."):format(step.Time)
					else nil,
			})
			Net.Push(player, "Quest.Carry", questId, step.Fragile == true, step.Time)
			push(player)
			return false
		end
		if carry and carry.QuestId == questId and table.find(step.To, id) and not state.Progress[id] then
			if carry.Expires and os.clock() > carry.Expires then
				return false
			end
			state.Progress[id] = true
			Notify.Send(player, {
				Kind = "Objective",
				Title = "Delivered",
				Text = ("%d / %d"):format(countSet(state.Progress), #step.To),
			})
			push(player)
			if countSet(state.Progress) >= #step.To then
				carrying[player] = nil
				Net.Push(player, "Quest.Carry", nil)
				return true
			end
		end
		return false
	end)
	forActive(player, "Timed", function(step, state)
		if id == step.From then
			state.Progress = { Started = os.clock() }
			Notify.Send(player, { Kind = "Objective", Title = "Go!", Text = ("%ds on the clock"):format(step.Time) })
			Net.Push(player, "Quest.Timer", step.Time)
			return false
		end
		local started = state.Progress.Started
		if id == step.To and type(started) == "number" then
			if os.clock() - started <= step.Time + 1 then
				Net.Push(player, "Quest.Timer", nil)
				return true
			end
			state.Progress = {}
			Notify.Warn(player, "Too slow. Head back to the start and try again.")
			Net.Push(player, "Quest.Timer", nil)
		end
		return false
	end)

	-- Contracts.
	local contract = profile.Contracts.Active
	if contract then
		if contract.Expires and now > contract.Expires then
			failContract(player, profile, "out of time")
			return
		end
		if contract.Kind == "Delivery" then
			if id == contract.From and not contract.Picked then
				contract.Picked = true
				carrying[player] = { Contract = true, Fragile = false, Expires = nil }
				contract.Expires = now + contract.Time
				Notify.Send(
					player,
					{ Kind = "Objective", Title = "Parcel picked up", Text = ("%ds to deliver"):format(contract.Time) }
				)
				Net.Push(player, "Quest.Timer", contract.Time)
				DataService.Push(player, "Contracts")
			elseif id == contract.To and contract.Picked then
				Net.Push(player, "Quest.Timer", nil)
				finishContract(player, profile)
			end
		elseif contract.Kind == "Relays" then
			contract.Done = contract.Done or {}
			if table.find(contract.Points, id) and not contract.Done[id] then
				contract.Done[id] = true
				if not contract.Expires then
					contract.Expires = now + contract.Time
					Net.Push(player, "Quest.Timer", contract.Time)
				end
				if countSet(contract.Done) >= #contract.Points then
					Net.Push(player, "Quest.Timer", nil)
					finishContract(player, profile)
				else
					DataService.Push(player, "Contracts")
				end
			end
		end
	end
end

-- Talking ------------------------------------------------------------------------------------------

local function nearNpc(player: Player, npcId: string): boolean
	local spot = npcSpots[npcId]
	return spot ~= nil and MovementGuard.WasNear(player, spot, 22, 2)
end

local function offerFor(quest: Quests.Quest): { [string]: any }
	local steps = {}
	for _, step in quest.Steps do
		table.insert(steps, step.Text)
	end
	return {
		Id = quest.Id,
		Name = quest.Name,
		Type = quest.Type,
		Chapter = quest.Chapter,
		Summary = quest.Summary,
		Intro = quest.Intro,
		Steps = steps,
		Rewards = quest.Rewards,
	}
end

local function onTalk(player: Player, npcId: any): any
	if type(npcId) ~= "string" then
		return nil
	end
	local npc = NPCs.ById[npcId]
	local profile = DataService.Get(player)
	if not npc or not profile or not nearNpc(player, npcId) then
		return nil
	end
	Events.Talk:Fire(player, npcId)
	local response: { [string]: any } = { Npc = npcId, Lines = {}, Offers = {}, Service = npc.Service, Completed = {} }

	-- Talk steps first: they move the story along.
	local spoke = false
	forActive(player, "Talk", function(step, _, questId)
		if step.Npc == npcId then
			spoke = true
			for _, line in step.Say or {} do
				table.insert(response.Lines, line)
			end
			local quest = Quests.ById[questId]
			local state = profile.Quests.Active[questId]
			if quest and state and state.Step == #quest.Steps then
				for _, line in quest.Outro do
					table.insert(response.Lines, line)
				end
				table.insert(response.Completed, { Id = quest.Id, Name = quest.Name, Rewards = quest.Rewards })
			end
			return true
		end
		return false
	end)

	-- New work this character can give.
	local level = ProgressionService.Level(player)
	for _, quest in Quests.List do
		if quest.Giver == npcId and available(profile, quest, level) then
			table.insert(response.Offers, offerFor(quest))
		end
	end
	if not spoke then
		local lines = if #response.Offers > 0 then npc.Greeting else npc.Idle
		local pick = lines[math.random(1, #lines)]
		table.insert(response.Lines, pick)
		-- Point the way if a quest waits elsewhere.
		for questId in profile.Quests.Active do
			local quest = Quests.ById[questId]
			local state = profile.Quests.Active[questId]
			local step = quest and state and quest.Steps[state.Step]
			if quest and step and quest.Giver == npcId then
				table.insert(response.Lines, 'Still working on "' .. quest.Name .. '"? ' .. step.Text .. ".")
				break
			end
		end
	end
	return response
end

local function onAccept(player: Player, questId: any): (boolean, string?)
	if type(questId) ~= "string" then
		return false, "Bad request"
	end
	local quest = Quests.ById[questId]
	local profile = DataService.Get(player)
	if not quest or not profile then
		return false, "Unknown quest"
	end
	if not available(profile, quest, ProgressionService.Level(player)) then
		return false, "Not available"
	end
	-- Expert trials and some side quests are offered from the journal, not a person.
	if quest.Type ~= "Expert" and not nearNpc(player, quest.Giver) then
		return false, "Talk to " .. (NPCs.ById[quest.Giver] and NPCs.ById[quest.Giver].Name or "them") .. " first"
	end
	profile.Quests.Active[questId] = { Step = 1, Progress = {}, Started = os.time() }
	pin(profile, questId)
	push(player)
	Notify.Send(
		player,
		{ Kind = "Objective", Title = "New quest: " .. quest.Name, Text = quest.Steps[1].Text, Sound = "Quest" }
	)
	checkStep(player, questId)
	return true, nil
end

local function onAbandon(player: Player, questId: any)
	local profile = DataService.Get(player)
	local quest = type(questId) == "string" and Quests.ById[questId]
	if not profile or not quest or not profile.Quests.Active[questId] then
		return
	end
	if quest.Type == "Main" then
		Notify.Warn(player, "Story quests can't be abandoned.")
		return
	end
	profile.Quests.Active[questId] = nil
	unpin(profile, questId)
	if carrying[player] and carrying[player].QuestId == questId then
		carrying[player] = nil
		Net.Push(player, "Quest.Carry", nil)
	end
	push(player)
end

local function onPin(player: Player, questId: any, pinned: any)
	local profile = DataService.Get(player)
	if not profile or type(questId) ~= "string" or not profile.Quests.Active[questId] then
		return
	end
	if pinned then
		pin(profile, questId)
	else
		unpin(profile, questId)
	end
	push(player)
end

local function onClaim(player: Player): any
	-- Refreshes rolling objectives and returns their state (rewards are paid automatically).
	local profile = DataService.Get(player)
	if not profile then
		return nil
	end
	refreshDaily(player, profile)
	refreshWeekly(profile)
	DataService.Push(player, "Daily")
	DataService.Push(player, "Weekly")
	return {
		Daily = profile.Daily,
		Weekly = profile.Weekly,
		NextDay = Rotation.SecondsUntilNextDay(),
		NextWeek = Rotation.SecondsUntilNextWeek(),
	}
end

-- Contract board: (district) → offers; (district, index) → take; (nil) → abandon.
local function onContract(player: Player, districtId: any, index: any): any
	local profile = DataService.Get(player)
	if not profile then
		return nil
	end
	if districtId == nil then
		failContract(player, profile, "abandoned")
		return true
	end
	if type(districtId) ~= "string" or not Districts.ById[districtId] then
		return nil
	end
	local contracts = profile.Contracts
	contracts.Offers = contracts.Offers or {}
	if not contracts.Offers[districtId] or os.time() > (contracts.Refresh or 0) then
		contracts.Offers[districtId] = makeOffers(player, profile, districtId)
		contracts.Refresh = os.time() + Quests.ContractRefresh
	end
	if index == nil then
		return {
			Offers = contracts.Offers[districtId],
			Active = contracts.Active,
			Refresh = contracts.Refresh - os.time(),
		}
	end
	if contracts.Active then
		return { Error = "Finish or abandon your current contract first" }
	end
	local offer = type(index) == "number" and contracts.Offers[districtId][index]
	if not offer then
		return nil
	end
	local active = table.clone(offer)
	active.Taken = os.time()
	if active.Kind == "Relays" then
		active.Expires = nil -- starts at the first relay point
	end
	contracts.Active = active
	table.remove(contracts.Offers[districtId], index)
	DataService.Push(player, "Contracts")
	DataService.MarkDirty(player)
	Notify.Send(player, { Kind = "Objective", Title = "Contract: " .. active.Name, Text = active.Text })
	return { Active = active }
end

-- Event wiring ----------------------------------------------------------------------------------------

local function onCourseFinished(player: Player, result: any)
	local profile = DataService.Get(player)
	if not profile or result.Mode == "Practice" then
		return
	end
	local distinctions = result.Distinctions or {}
	forActive(player, "Course", function(step)
		if step.Course ~= result.CourseId then
			return false
		end
		local record = profile.Courses[result.CourseId]
		local medal = math.max(
			result.Medal or 0,
			if step.NoFalls or step.Shortcut or step.Flow then 0 else (record and record.Medal or 0)
		)
		if (step.Medal or 0) > 0 and medal < step.Medal then
			return false
		end
		if (step.Medal or 0) > 0 and step.NoFalls and (result.Medal or 0) < step.Medal then
			return false
		end
		if step.NoFalls and not distinctions.NoFall then
			return false
		end
		if step.Shortcut and not distinctions.Shortcut then
			return false
		end
		if step.Flow and not distinctions.Flow then
			return false
		end
		return true
	end)
	forActive(player, "Courses", function(step, state)
		if step.District and step.District ~= result.District then
			return false
		end
		state.Progress[result.CourseId] = true
		push(player)
		return countSet(state.Progress) >= (step.Count or 1)
	end)
	objective(player, "Courses", 1)
	objective(player, "Districts", 1, nil, result.District)
	if (result.Medal or 0) > 0 then
		objective(player, "Medal", 1, function(template)
			return (result.Medal or 0) >= (template.Medal or 1)
		end)
	end
	if distinctions.NoFall then
		objective(player, "NoFall", 1)
	end
	-- Contracts: course certification.
	local contract = profile.Contracts.Active
	if
		contract
		and contract.Kind == "Course"
		and contract.Course == result.CourseId
		and (result.Medal or 0) >= (contract.Medal or 1)
	then
		finishContract(player, profile)
	end
end

local function chainContains(chain: { string }, wanted: { string }): boolean
	local index = 1
	for _, action in chain do
		if action == wanted[index] then
			index += 1
			if index > #wanted then
				return true
			end
		end
	end
	return false
end

function QuestService.Start()
	-- Index world points.
	for _, part in CollectionService:GetTagged(Tags.QuestPoint) do
		if part:IsA("BasePart") then
			local id = part:GetAttribute("Id")
			if type(id) == "string" then
				points[id] = part.Position
			end
		end
	end
	for _, part in CollectionService:GetTagged(Tags.ContractPoint) do
		if part:IsA("BasePart") then
			local id = part:GetAttribute("Id")
			local districtId = part:GetAttribute("District")
			if type(id) == "string" and type(districtId) == "string" then
				contractPoints[id] = { Id = id, Position = part.Position }
				contractByDistrict[districtId] = contractByDistrict[districtId] or {}
				table.insert(contractByDistrict[districtId], id)
			end
		end
	end
	for _, list in contractByDistrict do
		table.sort(list)
	end
	for _, part in CollectionService:GetTagged(Tags.NPCSpot) do
		if part:IsA("BasePart") then
			local id = part:GetAttribute("Id")
			if type(id) == "string" then
				for _, npc in NPCs.List do
					if npc.Spot == id then
						npcSpots[npc.Id] = part.Position
					end
				end
			end
		end
	end

	Net.Handle("Quest.Talk", onTalk)
	Net.Handle("Quest.Accept", onAccept)
	Net.On("Quest.Abandon", onAbandon)
	Net.On("Quest.Pin", onPin)
	Net.On("Quest.Point", onPoint)
	Net.Handle("Quest.Claim", onClaim)
	Net.Handle("Contract.Take", onContract)

	DataService.Loaded:Connect(function(player, profile)
		refreshDaily(player, profile)
		refreshWeekly(profile)
		-- New players start the prologue straight away.
		if not profile.Quests.Completed.p_welcome and not profile.Quests.Active.p_welcome then
			profile.Quests.Active.p_welcome = { Step = 1, Progress = {}, Started = os.time() }
			pin(profile, "p_welcome")
		end
		for questId in profile.Quests.Active do
			task.defer(checkStep, player, questId)
		end
	end)

	Events.CourseFinished:Connect(onCourseFinished)
	Events.Action:Connect(function(player: Player, action: string, _, districtId: string?)
		forActive(player, "Technique", function(step, state)
			if step.Action ~= action or (step.District and step.District ~= districtId) then
				return false
			end
			state.Progress.Count = (state.Progress.Count or 0) + 1
			if state.Progress.Count % 5 == 0 then
				push(player)
			end
			return state.Progress.Count >= (step.Count or 1)
		end)
		objective(player, "Technique", 1, function(template)
			return template.Action == action
		end)
	end)
	Events.Chain:Connect(function(player: Player, chain: { string })
		local here = district(player)
		forActive(player, "Chain", function(step)
			if step.District and step.District ~= here then
				return false
			end
			return chainContains(chain, step.Actions)
		end)
	end)
	Events.ChainEnded:Connect(function(player: Player, length: number)
		objective(player, "ChainLength", 1, function(template)
			return length >= (template.Count or 1)
		end)
	end)
	Events.FlowTier:Connect(function(player: Player, tier: number, districtId: string?)
		forActive(player, "Flow", function(step)
			return tier >= (step.Tier or 1) and (not step.District or step.District == districtId)
		end)
		objective(player, "Flow", 1, function(template)
			return tier >= (template.Tier2 or 3)
		end)
	end)
	Events.Discovery:Connect(function(player: Player, id: string, kind: string, districtId: string)
		forActive(player, "Discover", function(step, state)
			if (step.District and step.District ~= districtId) or (step.Type and step.Type ~= kind) then
				return false
			end
			state.Progress[id] = true
			push(player)
			return countSet(state.Progress) >= (step.Count or 1)
		end)
		objective(player, "Discover", 1)
	end)
	Events.Lesson:Connect(function(player: Player)
		forActive(player, "Lessons", function(step)
			local profile = DataService.Get(player)
			return profile ~= nil and countSet(profile.Lessons) >= (step.Count or 1)
		end)
	end)
	Events.Token:Connect(function(player: Player)
		objective(player, "Tokens", 1)
	end)
	Events.RaceFinished:Connect(function(player: Player)
		forActive(player, "Race", function(step, state)
			state.Progress.Count = (state.Progress.Count or 0) + 1
			return state.Progress.Count >= (step.Count or 1)
		end)
		objective(player, "Race", 1)
		objective(player, "Social", 1)
	end)
	Events.RelayFinished:Connect(function(player: Player)
		forActive(player, "Relay", function(step, state)
			state.Progress.Count = (state.Progress.Count or 0) + 1
			return state.Progress.Count >= (step.Count or 1)
		end)
		objective(player, "Social", 1)
	end)
	Events.TowerFloor:Connect(function(player: Player, floor: number)
		forActive(player, "Tower", function(step)
			return floor >= (step.Floor or 1)
		end)
		objective(player, "Tower", 1)
	end)
	Events.EndlessSection:Connect(function(player: Player)
		objective(player, "Endless", 1)
	end)
	Events.MasteryTier:Connect(function(player: Player)
		local profile = DataService.Get(player)
		if profile then
			for questId in profile.Quests.Active do
				checkStep(player, questId)
			end
		end
	end)
	Events.CrewJoined:Connect(function(player: Player)
		forActive(player, "Crew", function()
			return true
		end)
	end)
	-- Fragile packages break on stumbles and falls; timed packages expire.
	Events.Break:Connect(function(player: Player, reason: string)
		local carry = carrying[player]
		if not carry or not carry.Fragile then
			return
		end
		carrying[player] = nil
		local profile = DataService.Get(player)
		if profile and carry.QuestId then
			local state = profile.Quests.Active[carry.QuestId]
			if state then
				state.Progress = {}
			end
			push(player)
		end
		Net.Push(player, "Quest.Carry", nil)
		Notify.Warn(player, ("The package broke (%s). Pick up a fresh one."):format(string.lower(reason)))
	end)
	Players.PlayerRemoving:Connect(function(player)
		carrying[player] = nil
	end)
end

return QuestService

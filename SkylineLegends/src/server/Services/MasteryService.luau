-- Technique mastery: points from validated moves (capped per minute so
-- spamming doesn't work) plus proficiency challenges that gate each tier.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Courses = require(ReplicatedStorage.Shared.Config.Courses)
local Mastery = require(ReplicatedStorage.Shared.Config.Mastery)
local Stats = require(ReplicatedStorage.Shared.Logic.Stats)

local DataService = require(script.Parent.Parent.Data.DataService)
local Events = require(script.Parent.Parent.Events)
local Notify = require(script.Parent.Notify)
local ProgressionService = require(script.Parent.ProgressionService)

local MasteryService = {}

-- Items granted at tier 3 (Expert) for some categories; Grandmaster gives a title.
local EXPERT_ITEMS = {
	Climbing = "gloves_climber",
	Grappling = "gloves_hook",
	WallRunning = "shoes_wall",
	PrecisionLanding = "land_precision",
}

-- Which categories each action feeds.
local actionCategories: { [string]: { { Id: string, Points: number } } } = {}
for _, category in Mastery.Categories do
	for action, points in category.Actions do
		local list = actionCategories[action]
		if not list then
			list = {}
			actionCategories[action] = list
		end
		table.insert(list, { Id = category.Id, Points = points })
	end
end

type Budget = { Window: number, Used: { [string]: number } }
local budgets: { [Player]: Budget } = {}
local streaks: { [Player]: { [string]: number } } = {}

local function tiersOf(profile: any): { [string]: number }
	return Stats.MasteryTiers(profile)
end

local function settle(player: Player, before: { [string]: number })
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local after = tiersOf(profile)
	for _, category in Mastery.Categories do
		local old, new = before[category.Id] or 0, after[category.Id] or 0
		for tier = old + 1, new do
			local reward = Mastery.TierRewards[tier]
			local items = {}
			if tier == 3 and EXPERT_ITEMS[category.Id] then
				table.insert(items, EXPERT_ITEMS[category.Id])
			end
			if tier == 5 then
				table.insert(items, "title_master_" .. string.lower(category.Id))
			end
			ProgressionService.Grant(player, {
				XP = reward.XP,
				Credits = reward.Credits,
				Prestige = reward.Prestige,
				Items = items,
			}, nil, true)
			Notify.Send(player, {
				Kind = "Mastery",
				Title = ("%s: %s"):format(category.Name, Mastery.TierNames[tier]),
				Text = category.Blurb,
				Color = category.Color,
				XP = reward.XP,
				Credits = reward.Credits,
				Prestige = reward.Prestige,
				Sound = "Mastery",
			})
			Events.MasteryTier:Fire(player, category.Id, tier)
		end
	end
	DataService.Push(player, "Mastery")
end

local function addPoints(player: Player, categoryId: string, action: string, points: number)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local budget = budgets[player]
	local now = os.clock()
	if not budget or now - budget.Window > 60 then
		budget = { Window = now, Used = {} }
		budgets[player] = budget
	end
	local key = categoryId .. ":" .. action
	local used = budget.Used[key] or 0
	local allowed = math.max(0, math.min(points, Mastery.PointsPerMinuteCap - used))
	if allowed <= 0 then
		return
	end
	budget.Used[key] = used + allowed
	profile.Mastery.Points[categoryId] = (profile.Mastery.Points[categoryId] or 0) + allowed
end

local function complete(player: Player, challengeId: string)
	local profile = DataService.Get(player)
	if not profile or profile.Mastery.Challenges[challengeId] then
		return
	end
	local challenge = Mastery.ChallengeById[challengeId]
	profile.Mastery.Challenges[challengeId] = true
	Notify.Send(player, {
		Kind = "Toast",
		Title = "Challenge complete: " .. challenge.Name,
		Text = challenge.Text,
		Icon = Mastery.ById[challenge.Category].Icon,
		Sound = "Challenge",
	})
end

-- Is `needle` a subsequence (in order) of `haystack`?
local function containsInOrder(haystack: { string }, needle: { string }): boolean
	local index = 1
	for _, action in haystack do
		if action == needle[index] then
			index += 1
			if index > #needle then
				return true
			end
		end
	end
	return false
end

local function onAction(player: Player, action: string, value: number?)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local before = tiersOf(profile)
	for _, entry in actionCategories[action] or ({} :: { { Id: string, Points: number } }) do
		addPoints(player, entry.Id, action, entry.Points)
	end
	local playerStreaks = streaks[player]
	if not playerStreaks then
		playerStreaks = {}
		streaks[player] = playerStreaks
	end
	for _, challenge in Mastery.Challenges do
		if not profile.Mastery.Challenges[challenge.Id] then
			if challenge.Kind == "Count" and challenge.Action == action then
				if (profile.Stats[action] or 0) >= (challenge.Count or 1) then
					complete(player, challenge.Id)
				end
			elseif challenge.Kind == "Feat" and challenge.Action == action then
				if value and value >= (challenge.Value or math.huge) then
					complete(player, challenge.Id)
				end
			elseif challenge.Kind == "Streak" and challenge.Action == action then
				playerStreaks[challenge.Id] = (playerStreaks[challenge.Id] or 0) + 1
				if playerStreaks[challenge.Id] >= (challenge.Count or 1) then
					complete(player, challenge.Id)
				end
			end
		end
	end
	settle(player, before)
end

local function onBreak(player: Player, breaker: string)
	local playerStreaks = streaks[player]
	if not playerStreaks then
		return
	end
	for _, challenge in Mastery.Challenges do
		if challenge.Kind == "Streak" and challenge.Breaks and table.find(challenge.Breaks, breaker) then
			playerStreaks[challenge.Id] = 0
		end
	end
end

local function onChain(player: Player, actions: { string })
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local before = tiersOf(profile)
	local variety = {}
	local distinct = 0
	for _, action in actions do
		if not variety[action] then
			variety[action] = true
			distinct += 1
		end
	end
	for _, challenge in Mastery.Challenges do
		if not profile.Mastery.Challenges[challenge.Id] then
			if challenge.Kind == "Chain" and challenge.Actions and containsInOrder(actions, challenge.Actions) then
				complete(player, challenge.Id)
			elseif challenge.Kind == "ChainLength" and #actions >= (challenge.Count or math.huge) then
				complete(player, challenge.Id)
			elseif challenge.Kind == "ChainVariety" and distinct >= (challenge.Count or math.huge) then
				complete(player, challenge.Id)
			end
		end
	end
	settle(player, before)
end

local function onChainEnded(player: Player, length: number, variety: number)
	local profile = DataService.Get(player)
	if not profile or length < 3 then
		return
	end
	local before = tiersOf(profile)
	addPoints(player, "FlowChains", "Chain", math.floor(length * (1 + variety * 0.5)))
	settle(player, before)
end

local function onCourseFinished(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local before = tiersOf(profile)
	for _, challenge in Mastery.Challenges do
		if challenge.Kind == "Medal" and not profile.Mastery.Challenges[challenge.Id] then
			local n = 0
			for id, record in profile.Courses do
				local course = Courses.ById[id]
				if course and (record.Medal or 0) >= (challenge.Medal or 1) and table.find(course.Focus, challenge.Focus) then
					n += 1
				end
			end
			if n >= (challenge.Count or 1) then
				complete(player, challenge.Id)
			end
		end
	end
	settle(player, before)
end

function MasteryService.Start()
	Events.Action:Connect(onAction)
	Events.Break:Connect(onBreak)
	Events.Chain:Connect(onChain)
	Events.ChainEnded:Connect(onChainEnded)
	Events.CourseFinished:Connect(onCourseFinished)
	Players.PlayerRemoving:Connect(function(player)
		budgets[player] = nil
		streaks[player] = nil
	end)
end

return MasteryService

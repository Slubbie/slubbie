-- XP, levels, daily quests and nametags.
--
-- Moves, shards, combos and trials earn XP. Levelling up grants shards and a
-- new title on your nametag. Three daily quests (the same for everyone, reset
-- at midnight UTC) pay out shards and XP when completed.
--
-- Quests are mirrored to the client as a JSON string in the "Quests" attribute.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local PlayerData = require(script.Parent.PlayerData)

local P = Config.Progression
local Q = Config.Quests
local LANDMARK_RADIUS = 160

-- Moves that earn XP, and how many per second can count (stops remote spam).
local XP_MOVES = {
	Grapple = true,
	WallRun = true,
	WallJump = true,
	Dash = true,
	Slingshot = true,
	BunnyHop = true,
	SlideJump = true,
	Launch = true,
}
local MOVE_XP_PER_SECOND = 5

local Progression = {}

local notify: RemoteEvent
local moveBudget: { [Player]: { Count: number, Window: number } } = {}
local landmarks: { { Name: string, Position: Vector3 } } = {}

-- Achievements ----------------------------------------------------------------------

local function publishAchievements(player: Player)
	local data = PlayerData.Get(player)
	if data then
		player:SetAttribute("AchievementStats", HttpService:JSONEncode(data.Stats))
		player:SetAttribute("Achievements", HttpService:JSONEncode(data.Achievements))
	end
end

-- Update a lifetime stat and unlock any achievements it completes.
local function bumpStat(player: Player, stat: string, value: number, best: boolean)
	local data = PlayerData.Get(player)
	if not data then
		return
	end
	local current = data.Stats[stat] or 0
	data.Stats[stat] = if best then math.max(current, value) else current + value
	local total = data.Stats[stat]
	for _, achievement in Config.Achievements do
		if achievement.Stat == stat and not data.Achievements[achievement.Id] and total >= achievement.Goal then
			data.Achievements[achievement.Id] = true
			PlayerData.AddShards(player, achievement.Reward)
			notify:FireClient(player, "Achievement", {
				Name = achievement.Name,
				Desc = achievement.Desc,
				Reward = achievement.Reward,
			})
		end
	end
	publishAchievements(player)
end

local BEST_STATS = { TopSpeed = true, ComboScore = true, Landmarks = true, Level = true }

local function today(): string
	local date = os.date("!*t")
	return string.format("%d-%d-%d", date.year, date.month, date.day)
end

-- Today's quests: a shuffled pick from the pool, easy → medium → hard.
local function questsFor(day: string)
	local seed = 0
	for i = 1, #day do
		seed = (seed * 31 + string.byte(day, i)) % 2147483647
	end
	local rng = Random.new(seed)
	local pool = table.clone(Q.Pool)
	for i = #pool, 2, -1 do
		local j = rng:NextInteger(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local list = {}
	for i = 1, math.min(Q.PerDay, #pool) do
		local template = pool[i]
		table.insert(list, {
			Id = template.Id,
			Goal = template.Goals[math.min(i, #template.Goals)],
			Progress = 0,
			Done = false,
			Tier = i,
		})
	end
	return list
end

local function template(id: string)
	for _, entry in Q.Pool do
		if entry.Id == id then
			return entry
		end
	end
	return nil
end

local function publish(player: Player)
	local data = PlayerData.Get(player)
	if not data or type(data.Quests.List) ~= "table" then
		return
	end
	local view = {}
	for _, quest in data.Quests.List do
		local entry = template(quest.Id)
		if entry then
			table.insert(view, {
				Text = string.format(entry.Text, quest.Goal),
				Progress = math.min(quest.Progress, quest.Goal),
				Goal = quest.Goal,
				Done = quest.Done,
				Reward = Q.RewardShards[quest.Tier] or 0,
			})
		end
	end
	player:SetAttribute("Quests", HttpService:JSONEncode(view))
end

local function ensureQuests(player: Player)
	local data = PlayerData.Get(player)
	if not data then
		return
	end
	local day = today()
	if data.Quests.Day ~= day or type(data.Quests.List) ~= "table" then
		data.Quests = { Day = day, List = questsFor(day) }
		publish(player)
	end
end

function Progression.AddXP(player: Player, amount: number)
	local data = PlayerData.Get(player)
	amount = math.floor(amount)
	if not data or amount <= 0 then
		return
	end
	local before = Config.LevelForXP(data.XP)
	local after = Config.LevelForXP(data.XP + amount)
	local bonus = 0
	for level = before + 1, after do
		bonus += level * P.ShardsPerLevel
	end
	PlayerData.Update(player, function(d)
		d.XP += amount
		d.Shards += bonus
	end)
	if after > before then
		notify:FireClient(player, "LevelUp", { Level = after, Title = Config.TitleForLevel(after), Shards = bonus })
		bumpStat(player, "Level", after, true)
	end
end

-- Count progress toward quests. `amount` defaults to 1; "Best" quests (like the
-- combo one) track the highest single value instead of a running total.
function Progression.Record(player: Player, stat: string, amount: number?)
	local value = amount or 1
	if XP_MOVES[stat] then
		local now = os.clock()
		local budget = moveBudget[player]
		if not budget or now - budget.Window > 1 then
			budget = { Count = 0, Window = now }
			moveBudget[player] = budget
		end
		budget.Count += 1
		if budget.Count > MOVE_XP_PER_SECOND then
			return
		end
		Progression.AddXP(player, P.XP.Move)
	end

	bumpStat(player, stat, value, BEST_STATS[stat] == true)
	ensureQuests(player)
	local data = PlayerData.Get(player)
	if not data then
		return
	end
	local changed = false
	for _, quest in data.Quests.List do
		local entry = template(quest.Id)
		if entry and entry.Stat == stat and not quest.Done then
			quest.Progress = if entry.Best then math.max(quest.Progress, value) else quest.Progress + value
			changed = true
			if quest.Progress >= quest.Goal then
				quest.Done = true
				local shards = Q.RewardShards[quest.Tier] or 0
				local xp = Q.RewardXP[quest.Tier] or 0
				PlayerData.AddShards(player, shards)
				Progression.AddXP(player, xp)
				notify:FireClient(player, "QuestComplete", {
					Text = string.format(entry.Text, quest.Goal),
					Shards = shards,
					XP = xp,
				})
			end
		end
	end
	if changed then
		publish(player)
	end
end

-- Nametags ---------------------------------------------------------------------

local function nametag(player: Player, character: Model)
	local head = character:WaitForChild("Head", 10)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not head or not humanoid then
		return
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	local gui = Instance.new("BillboardGui")
	gui.Name = "Nametag"
	gui.Size = UDim2.fromOffset(220, 46)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, 0, 0, 24)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBlack
	name.TextSize = 20
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextStrokeTransparency = 0.4
	name.Text = player.DisplayName
	name.Parent = gui
	local rank = Instance.new("TextLabel")
	rank.Position = UDim2.fromOffset(0, 24)
	rank.Size = UDim2.new(1, 0, 0, 18)
	rank.BackgroundTransparency = 1
	rank.Font = Enum.Font.GothamBold
	rank.TextSize = 15
	rank.TextStrokeTransparency = 0.5
	rank.Parent = gui
	gui.Parent = head

	local function refresh()
		local color = player:GetAttribute("RopeColor")
		rank.TextColor3 = if typeof(color) == "Color3" then color else Config.Grapple.RopeColor
		rank.Text =
			string.format("Lv %d · %s", player:GetAttribute("Level") or 1, player:GetAttribute("Title") or "Drifter")
	end
	refresh()
	for _, attribute in { "Level", "Title", "RopeColor" } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if gui.Parent then
				refresh()
			end
		end)
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		nametag(player, character)
	end)
	if player.Character then
		task.spawn(nametag, player, player.Character)
	end
end

function Progression.SetLandmarks(list)
	landmarks = list or {}
end

function Progression.Start()
	notify = Net.Event("Notify")

	PlayerData.Loaded.Event:Connect(function(player)
		ensureQuests(player)
		publish(player)
		publishAchievements(player)
	end)

	-- Top speed and landmark visits, sampled from where players actually are.
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local data = PlayerData.Get(player)
				if root and data then
					local speed = math.floor(root.AssemblyLinearVelocity.Magnitude)
					if speed > (data.Stats.TopSpeed or 0) and speed <= Config.Movement.MaxSpeed * 1.3 then
						bumpStat(player, "TopSpeed", speed, true)
					end
					for _, landmark in landmarks do
						if
							not data.Visited[landmark.Name]
							and (root.Position - landmark.Position).Magnitude < LANDMARK_RADIUS
						then
							data.Visited[landmark.Name] = true
							local count = 0
							for _ in data.Visited do
								count += 1
							end
							notify:FireClient(player, "Landmark", { Name = landmark.Name })
							bumpStat(player, "Landmarks", count, true)
						end
					end
				end
			end
		end
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		moveBudget[player] = nil
	end)

	Net.Event("CompleteTutorial").OnServerEvent:Connect(function(player)
		local data = PlayerData.Get(player)
		if data and not data.TutorialDone then
			PlayerData.Update(player, function(d)
				d.TutorialDone = true
				d.Shards += 25
			end)
			Progression.AddXP(player, 100)
		end
	end)

	-- Roll quests over at midnight UTC for players who stay online.
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in Players:GetPlayers() do
				ensureQuests(player)
			end
		end
	end)
end

return Progression

-- The achievement journal: checks stats after relevant events and pays out
-- automatically, with an unlock card.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Achievements = require(ReplicatedStorage.Shared.Config.Achievements)
local Stats = require(ReplicatedStorage.Shared.Logic.Stats)

local DataService = require(script.Parent.Parent.Data.DataService)
local DiscoveryService = require(script.Parent.DiscoveryService)
local Events = require(script.Parent.Parent.Events)
local Notify = require(script.Parent.Notify)
local ProgressionService = require(script.Parent.ProgressionService)

local AchievementService = {}

local pending: { [Player]: boolean } = {}

local lastStatsPush: { [Player]: number } = {}

local function check(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local context = { CacheTotals = DiscoveryService.CacheTotals }
	local earnedAny = false
	for _, achievement in Achievements.List do
		if not profile.Achievements[achievement.Id] then
			local value = Stats.Get(profile, achievement.Stat, context)
			if value >= achievement.Target then
				profile.Achievements[achievement.Id] = os.time()
				earnedAny = true
				ProgressionService.Grant(player, {
					XP = achievement.XP,
					Credits = achievement.Credits,
					Prestige = achievement.Prestige,
					Items = if achievement.Item then { achievement.Item } else nil,
				}, nil, true)
				Notify.Send(player, {
					Kind = "Achievement",
					Title = achievement.Name,
					Text = achievement.Text,
					XP = achievement.XP,
					Credits = achievement.Credits,
					Prestige = achievement.Prestige,
					Item = achievement.Item,
					Sound = "Achievement",
				})
			end
		end
	end
	if earnedAny then
		DataService.Push(player, "Achievements")
	end
	-- Counters feed the journal's progress bars (at most once every few seconds).
	local now = os.clock()
	if now - (lastStatsPush[player] or 0) > 4 then
		lastStatsPush[player] = now
		DataService.Push(player, "Stats")
	end
end

function AchievementService.Queue(player: Player)
	pending[player] = true
end

function AchievementService.Start()
	-- Any of these can move a statistic; checks are batched once a second.
	local function queue(player: Player)
		pending[player] = true
	end
	Events.StatChanged:Connect(queue)
	Events.CourseFinished:Connect(queue)
	Events.Discovery:Connect(queue)
	Events.QuestCompleted:Connect(queue)
	Events.LevelUp:Connect(queue)
	Events.MasteryTier:Connect(queue)
	Events.ItemGranted:Connect(queue)
	Events.RaceFinished:Connect(queue)
	Events.RelayFinished:Connect(queue)
	Events.TowerFloor:Connect(queue)
	Events.EndlessEnded:Connect(queue)
	DataService.Loaded:Connect(queue)

	task.spawn(function()
		while true do
			task.wait(1)
			for player in pending do
				pending[player] = nil
				if player.Parent then
					local ok, err = pcall(check, player)
					if not ok then
						warn("[Achievements] " .. tostring(err))
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
		lastStatsPush[player] = nil
	end)
end

return AchievementService

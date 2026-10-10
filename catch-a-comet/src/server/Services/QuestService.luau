-- The quest framework: the onboarding guide and the Explorer missions.
--
-- Quests are data (QuestDefinitions). Each objective type either counts
-- gameplay events ("Event") or reads the profile ("State"). Services fire
-- signals; this service maps them to objective events, so adding a quest
-- never needs new code unless it introduces a new objective type.
--
-- Onboarding steps complete and pay out automatically and persist in
-- TutorialStage, so a player who leaves mid-tutorial resumes where they were.
-- Missions are claimed by hand, once (ClaimQuest is idempotent).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreatureDefinitions = require(Shared.CreatureDefinitions)
local EconomyMath = require(Shared.EconomyMath)
local GameConfig = require(Shared.GameConfig)
local Loop = require(Shared.Loop)
local QuestDefinitions = require(Shared.QuestDefinitions)
local RarityConfig = require(Shared.RarityConfig)
local Signal = require(Shared.Signal)

local QuestService = { Name = "QuestService" }

-- (player, chain, quest)
QuestService.QuestCompleted = Signal.new()

local services: { [string]: any } = {}
local tutorialComets: { [Player]: any } = {}

local function stateValue(profile: any, objective: QuestDefinitions.Objective): number
	local kind = objective.Type
	if kind == "DeployedCount" then
		local n = 0
		for _ in profile.EquippedCreatures do
			n += 1
		end
		return n
	elseif kind == "UpgradeLevel" then
		return profile.Equipment[(objective.Track or "Scanner") .. "Level"] or 1
	elseif kind == "SpeciesDiscovered" then
		local n = 0
		for _ in profile.DiscoveredSpecies do
			n += 1
		end
		return n
	elseif kind == "DiscoverRarity" then
		local need = RarityConfig.RarityIndex(objective.Rarity or "Rare")
		for speciesId in profile.DiscoveredSpecies do
			local species = CreatureDefinitions.Get(speciesId)
			if species and RarityConfig.RarityIndex(species.Rarity) >= need then
				return 1
			end
		end
		return 0
	elseif kind == "ReachLevel" then
		return profile.Level
	end
	return 0
end

-- How much an event advances an objective (0 when it doesn't match).
local function eventAmount(objective: QuestDefinitions.Objective, eventName: string, data: any): number
	local def = QuestDefinitions.ObjectiveTypes[objective.Type]
	if not def or def.Kind ~= "Event" or def.Event ~= eventName then
		return 0
	end
	if objective.Type == "CaptureRank" then
		return if EconomyMath.RankIndex(data.Rank) >= EconomyMath.RankIndex(objective.Rank or "Gold") then 1 else 0
	elseif objective.Type == "PurchaseUpgrade" then
		return if objective.Track == nil or objective.Track == data.Track then 1 else 0
	elseif objective.Type == "EarnPassive" then
		return data.Amount or 0
	end
	return 1
end

local function grant(player: Player, reward: QuestDefinitions.Reward, source: string)
	if reward.Stardust and reward.Stardust > 0 then
		services.EconomyService.Grant(player, "Stardust", reward.Stardust, source)
	end
	if reward.MeteorShards and reward.MeteorShards > 0 then
		services.EconomyService.Grant(player, "MeteorShards", reward.MeteorShards, source)
	end
	if reward.XP and reward.XP > 0 then
		services.ProgressionService.AddXP(player, reward.XP, source)
	end
end

-- Onboarding ----------------------------------------------------------------------

function QuestService.CurrentStep(profile: any): QuestDefinitions.Quest?
	return QuestDefinitions.Onboarding[profile.TutorialStage + 1]
end

local function onStepStarted(player: Player, profile: any)
	local step = QuestService.CurrentStep(profile)
	if not step then
		return
	end
	if step.Id == "FollowComet" or step.Id == "CaptureComet" then
		QuestService.EnsureTutorialComet(player)
	elseif step.Objective.Type == "EnterSanctuary" and services.SanctuaryService.IsInside(player) then
		-- Already standing in it: no need to walk out and back in.
		task.defer(QuestService.Record, player, "EnteredOwnSanctuary")
	end
end

local function advanceOnboarding(player: Player, profile: any)
	-- Loop: several state-based steps can already be satisfied.
	while true do
		local step = QuestService.CurrentStep(profile)
		if not step then
			return
		end
		local def = QuestDefinitions.ObjectiveTypes[step.Objective.Type]
		local progress = if def.Kind == "State"
			then stateValue(profile, step.Objective)
			else profile.QuestProgress.Onboarding.Progress
		if progress < step.Objective.Target then
			return
		end
		profile.TutorialStage += 1
		profile.QuestProgress.Onboarding.Progress = 0
		services.ReplicationService.Set(player, { "TutorialStage" }, profile.TutorialStage)
		services.ReplicationService.Set(player, { "QuestProgress", "Onboarding" }, profile.QuestProgress.Onboarding)
		grant(player, step.Reward, "Tutorial")
		services.AnalyticsService.Funnel(player, profile.TutorialStage + 1, step.Id)
		QuestService.QuestCompleted:Fire(player, "Onboarding", step)
		services.ReplicationService.Notify(player, "QuestCompleted", {
			Chain = "Onboarding",
			Id = step.Id,
			Reward = step.Reward,
			Done = profile.TutorialStage >= #QuestDefinitions.Onboarding,
		})
		if profile.TutorialStage >= #QuestDefinitions.Onboarding then
			services.AnalyticsService.Funnel(player, #QuestDefinitions.Onboarding + 2, "TutorialComplete")
			services.PlayerDataService.RequestSave(player)
			QuestService.EvaluateMission(player)
			return
		end
		onStepStarted(player, profile)
	end
end

function QuestService.EnsureTutorialComet(player: Player)
	local existing = tutorialComets[player]
	if existing and not existing.Expired and not existing.Claims[player.UserId] then
		return
	end
	local profile = services.PlayerDataService.GetProfile(player)
	if not profile or profile.TutorialStage > 1 then
		return
	end
	-- A starter core already captured but not opened? Then the comet step is done.
	for _, core in profile.Cores do
		if core.Kind == "Starter" then
			return
		end
	end
	task.delay(GameConfig.Tutorial.CometDelay, function()
		if
			player.Parent
			and services.PlayerDataService.GetProfile(player) == profile
			and profile.TutorialStage <= 1
		then
			tutorialComets[player] = services.CometService.SpawnTutorial(player)
		end
	end)
end

-- Missions ----------------------------------------------------------------------

function QuestService.CurrentMission(profile: any): QuestDefinitions.Quest?
	return QuestDefinitions.Missions[profile.QuestProgress.Missions.Index]
end

function QuestService.EvaluateMission(player: Player)
	local profile = services.PlayerDataService.GetProfile(player)
	if not profile or profile.TutorialStage < #QuestDefinitions.Onboarding then
		return
	end
	local state = profile.QuestProgress.Missions
	local mission = QuestService.CurrentMission(profile)
	if not mission or state.Complete then
		return
	end
	local def = QuestDefinitions.ObjectiveTypes[mission.Objective.Type]
	if def.Kind == "State" then
		state.Progress = math.min(stateValue(profile, mission.Objective), mission.Objective.Target)
	end
	if state.Progress >= mission.Objective.Target then
		state.Complete = true
		services.ReplicationService.Notify(
			player,
			"QuestCompleted",
			{ Chain = "Missions", Id = mission.Id, Reward = mission.Reward }
		)
		QuestService.QuestCompleted:Fire(player, "Missions", mission)
	end
	services.ReplicationService.Set(player, { "QuestProgress", "Missions" }, state)
end

function QuestService.Claim(player: Player, questId: string): { [string]: any }
	local profile = services.PlayerDataService.GetProfile(player)
	if not profile then
		return { Ok = false, Reason = "NotReady" }
	end
	local state = profile.QuestProgress.Missions
	local mission = QuestService.CurrentMission(profile)
	if not mission or mission.Id ~= questId then
		return { Ok = false, Reason = "NotActive" }
	end
	if not state.Complete then
		return { Ok = false, Reason = "NotComplete" }
	end
	-- Advance first, then pay: a repeated request now targets the next mission.
	state.Index += 1
	state.Progress = 0
	state.Complete = false
	services.ReplicationService.Set(player, { "QuestProgress", "Missions" }, state)
	grant(player, mission.Reward, "Mission")
	services.PlayerDataService.RequestSave(player)
	QuestService.EvaluateMission(player)
	return { Ok = true, Reward = mission.Reward }
end

-- Events --------------------------------------------------------------------------

-- Feeds a gameplay event into the player's active quests.
function QuestService.Record(player: Player, eventName: string, data: any?)
	local profile = services.PlayerDataService.GetProfile(player)
	if not profile then
		return
	end
	local payload = data or {}
	local step = QuestService.CurrentStep(profile)
	if step then
		local amount = eventAmount(step.Objective, eventName, payload)
		if amount > 0 then
			local progress = profile.QuestProgress.Onboarding
			progress.Progress = math.min(progress.Progress + amount, step.Objective.Target)
			services.ReplicationService.Set(player, { "QuestProgress", "Onboarding" }, progress)
		end
		advanceOnboarding(player, profile)
		return
	end
	local mission = QuestService.CurrentMission(profile)
	local state = profile.QuestProgress.Missions
	if mission and not state.Complete then
		local amount = eventAmount(mission.Objective, eventName, payload)
		if amount > 0 then
			state.Progress = math.min(state.Progress + amount, mission.Objective.Target)
		end
		QuestService.EvaluateMission(player)
	end
end

-- Re-checks state-based objectives after the profile changed.
function QuestService.Refresh(player: Player)
	QuestService.Record(player, "StateChanged")
end

-- Tutorial proximity: completes "follow the trail" when the player reaches the comet.
function QuestService.CheckTutorialProximity()
	for player, comet in tutorialComets do
		local profile = services.PlayerDataService.GetProfile(player)
		if not profile or profile.TutorialStage ~= 0 or comet.Expired then
			continue
		end
		local position = services.SecurityService.GetRootPosition(player)
		if position and (position - comet.Position).Magnitude <= GameConfig.Tutorial.ReachDistance then
			QuestService.Record(player, "NearTutorialComet")
		end
	end
end

function QuestService.Init(registry: { [string]: any })
	services = registry
end

function QuestService.Start()
	local data = services.PlayerDataService
	data.ProfileLoaded:Connect(function(player, profile)
		services.AnalyticsService.Funnel(
			player,
			profile.TutorialStage + 1,
			if profile.TutorialStage == 0 then "Joined" else "Resumed"
		)
		-- Characters spawn after the profile loads; give the tutorial comet a moment.
		onStepStarted(player, profile)
		advanceOnboarding(player, profile)
		QuestService.EvaluateMission(player)
	end)

	services.CaptureService.CaptureStarted:Connect(function(player, comet)
		if comet.IsTutorial then
			QuestService.Record(player, "NearTutorialComet")
		end
	end)
	services.CaptureService.CaptureSucceeded:Connect(function(player, result)
		QuestService.Record(player, "CaptureSucceeded", { Rank = result.Rank, Biome = result.Comet.Biome })
	end)
	services.CreatureService.CoreOpened:Connect(function(player)
		QuestService.Record(player, "CoreOpened")
	end)
	services.CreatureService.CreatureObtained:Connect(function(player)
		QuestService.Refresh(player)
	end)
	services.SanctuaryService.CreatureDeployed:Connect(function(player)
		QuestService.Refresh(player)
	end)
	services.SanctuaryService.CreatureWithdrawn:Connect(function(player)
		QuestService.Refresh(player)
	end)
	services.SanctuaryService.EnteredOwnSanctuary:Connect(function(player)
		QuestService.Record(player, "EnteredOwnSanctuary")
	end)
	services.IncomeService.PassiveIncome:Connect(function(player, amount)
		QuestService.Record(player, "PassiveIncome", { Amount = amount })
	end)
	services.UpgradeService.Upgraded:Connect(function(player, trackId)
		QuestService.Record(player, "UpgradePurchased", { Track = trackId })
	end)
	services.WispService.WispCollected:Connect(function(player)
		QuestService.Record(player, "WispCollected")
	end)
	services.ProgressionService.LevelUp:Connect(function(player)
		QuestService.Refresh(player)
	end)
	services.SecurityService.BindFunction("ClaimQuest", QuestService.Claim)

	Players.PlayerRemoving:Connect(function(player)
		tutorialComets[player] = nil
	end)
	Loop.Every(0.5, "TutorialProximity", QuestService.CheckTutorialProximity)
end

return QuestService

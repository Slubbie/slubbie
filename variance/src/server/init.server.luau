-- VARIANCE server bootstrap.
--
-- Loads every ModuleScript in Services/, calls Init(services) on each in a fixed
-- order (no yielding allowed in Init), then Start() on each in its own thread.
-- Services reach each other through the shared `services` table at call time,
-- so there are no require cycles and load order only matters for Init.

local ServerScriptService = game:GetService("ServerScriptService")

local servicesFolder = script:WaitForChild("Services")

local ORDER = {
	"AntiExploitService",
	"NetworkService",
	"DataService",
	"SettingsService",
	"CosmeticService",
	"ProgressionService",
	"StatisticsService",
	"ChallengeService",
	"AchievementService",
	"LoreService",
	"MonetizationService",
	"LeaderboardService",
	"RankedService",
	"CharacterService",
	"ArenaService",
	"DialogueService",
	"AIService",
	"SpectatorService",
	"ChatGuardService",
	"MatchService",
	"MatchmakingService",
	"LobbyService",
	"TournamentService",
	"ReconnectService",
	"TutorialService",
	"AmbientEventService",
	"LobbyWorldService",
	"DebugService",
}

local services = {}
for _, module in servicesFolder:GetChildren() do
	if module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok then
			services[module.Name] = result
		else
			warn("[VARIANCE] failed to load " .. module.Name .. ": " .. tostring(result))
		end
	end
end

for _, name in ORDER do
	if services[name] == nil then
		warn("[VARIANCE] missing service " .. name)
	end
end

for _, name in ORDER do
	local service = services[name]
	if service and service.Init then
		local ok, err = pcall(service.Init, service, services)
		if not ok then
			warn("[VARIANCE] " .. name .. ".Init failed: " .. tostring(err))
		end
	end
end

for _, name in ORDER do
	local service = services[name]
	if service and service.Start then
		task.spawn(function()
			local ok, err = pcall(service.Start, service)
			if not ok then
				warn("[VARIANCE] " .. name .. ".Start failed: " .. tostring(err))
			end
		end)
	end
end

ServerScriptService:SetAttribute("VarianceReady", true)

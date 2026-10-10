-- Catch a Comet! — server entry point.
--
-- Creates the remotes, then initializes every service in dependency order
-- (Init: wire references, build the world; no gameplay yet), then starts
-- them in the same order (Start: connect events, bind remotes, run loops).
-- Shared content is validated first; broken content stops the server
-- loudly instead of producing a half-working game.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BiomeDefinitions = require(Shared.BiomeDefinitions)
local CreatureDefinitions = require(Shared.CreatureDefinitions)
local CreatureRig = require(Shared.CreatureRig)
local GameConfig = require(Shared.GameConfig)
local QuestDefinitions = require(Shared.QuestDefinitions)
local RarityConfig = require(Shared.RarityConfig)
local RemoteDefinitions = require(Shared.RemoteDefinitions)
local UpgradeDefinitions = require(Shared.UpgradeDefinitions)

local Services = script.Parent.Services

-- Order matters: each service may use the ones listed before it during Start.
local ORDER = {
	"SecurityService",
	"AnalyticsService",
	"PlayerDataService",
	"ReplicationService",
	"EconomyService",
	"ProgressionService",
	"CreatureService",
	"WorldService",
	"UpgradeService",
	"IncomeService",
	"SanctuaryService",
	"CometService",
	"CaptureService",
	"WispService",
	"QuestService",
	"TravelService",
	"CharacterService",
	"LeaderboardService",
}

local function validateContent()
	local problems = {}
	for _, list in
		{
			RarityConfig.Validate(),
			BiomeDefinitions.Validate(),
			CreatureDefinitions.Validate(),
			UpgradeDefinitions.Validate(),
			QuestDefinitions.Validate(),
		}
	do
		table.move(list, 1, #list, #problems + 1, problems)
	end
	for _, speciesId in CreatureDefinitions.Order do
		if not CreatureRig.HasBuilder(speciesId) then
			warn(`[Content] {speciesId} has no procedural builder; it will use an override model or a placeholder`)
		end
	end
	if #problems > 0 then
		error("[Content] Invalid game content:\n  " .. table.concat(problems, "\n  "))
	end
end

validateContent()
RemoteDefinitions.CreateAll()

local registry: { [string]: any } = {}
for _, name in ORDER do
	registry[name] = require(Services:WaitForChild(name))
end
for _, name in ORDER do
	local ok, err = pcall(registry[name].Init, registry)
	if not ok then
		error(`[Bootstrap] {name}.Init failed: {err}`)
	end
end
for _, name in ORDER do
	local ok, err = pcall(registry[name].Start)
	if not ok then
		error(`[Bootstrap] {name}.Start failed: {err}`)
	end
end

registry.PlayerDataService.BeginLoading()

print(`[Catch a Comet] Server ready (v{GameConfig.Version}).`)

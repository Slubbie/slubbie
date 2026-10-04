-- Skyline Legends: server bootstrap.
--
-- Order matters: profiles start loading as soon as players join, the city is
-- generated (deterministically, so every server builds the same Meridian),
-- then every service starts, and only then are characters spawned.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Remotes exist before any client asks for them.
require(ReplicatedStorage.Shared.Net)

local DataService = require(script.Data.DataService)
local WorldBuilder = require(script.World.WorldBuilder)

local Services = script.Services
local AchievementService = require(Services.AchievementService)
local CosmeticService = require(Services.CosmeticService)
local CourseService = require(Services.CourseService)
local CrewService = require(Services.CrewService)
local DiscoveryService = require(Services.DiscoveryService)
local DistrictService = require(Services.DistrictService)
local EconomyService = require(Services.EconomyService)
local EndlessService = require(Services.EndlessService)
local LessonService = require(Services.LessonService)
local MasteryService = require(Services.MasteryService)
local MovementGuard = require(Services.MovementGuard)
local NPCService = require(Services.NPCService)
local PlayerService = require(Services.PlayerService)
local ProgressionService = require(Services.ProgressionService)
local QuestService = require(Services.QuestService)
local RaceService = require(Services.RaceService)
local RecordService = require(Services.RecordService)
local RelayService = require(Services.RelayService)
local SocialService = require(Services.SocialService)
local TowerService = require(Services.TowerService)

DataService.Start()

local started = os.clock()
WorldBuilder.Build()
for name, cframe in WorldBuilder.Spawns do
	PlayerService.Spawns[name] = cframe
end
MovementGuard.RefreshCache()
print(("[Skyline] Meridian built in %.1fs"):format(os.clock() - started))

local ordered = {
	{ "Progression", ProgressionService },
	{ "Economy", EconomyService },
	{ "Cosmetics", CosmeticService },
	{ "MovementGuard", MovementGuard },
	{ "Districts", DistrictService },
	{ "Discoveries", DiscoveryService },
	{ "Achievements", AchievementService },
	{ "Mastery", MasteryService },
	{ "Records", RecordService },
	{ "Courses", CourseService },
	{ "Quests", QuestService },
	{ "NPCs", NPCService },
	{ "Lessons", LessonService },
	{ "Tower", TowerService },
	{ "Endless", EndlessService },
	{ "Races", RaceService },
	{ "Relays", RelayService },
	{ "Crews", CrewService },
	{ "Social", SocialService },
	{ "Players", PlayerService },
}
for _, entry in ordered do
	local ok, err = pcall(entry[2].Start)
	if not ok then
		warn(("[Skyline] %s failed to start: %s"):format(entry[1], tostring(err)))
	end
end

workspace:SetAttribute("SkylineReady", true)
print("[Skyline] Server ready")

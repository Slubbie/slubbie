-- Skyline Legends: client bootstrap.
--
-- Core state and input first, then movement and the world, presentation,
-- gameplay, and finally the interface. Each system starts once, in order; a
-- failure in one is reported without taking the rest down.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

require(ReplicatedStorage.Shared.Net)

local Core = script.Core
local State = require(Core.State)
local Settings = require(Core.Settings)
local Input = require(Core.Input)

local Controller = require(script.Movement.Controller)
local Mechanisms = require(script.World.Mechanisms)
local Hazards = require(script.World.Hazards)
local Atmosphere = require(script.World.Atmosphere)
local Detail = require(script.World.Detail)

local Animator = require(script.Animation.Animator)
local CameraController = require(script.Camera.CameraController)
local Sfx = require(script.Audio.Sfx)
local Music = require(script.Audio.Music)
local Effects = require(script.Effects.Effects)

local Flow = require(script.Gameplay.Flow)
local Ghosts = require(script.Gameplay.Ghosts)
local CourseClient = require(script.Gameplay.CourseClient)
local QuestClient = require(script.Gameplay.QuestClient)
local Modes = require(script.Gameplay.Modes)
local Lessons = require(script.Gameplay.Lessons)
local Explore = require(script.Gameplay.Explore)
local Prompts = require(script.Gameplay.Prompts)

local Root = require(script.UI.Root)
local Hud = require(script.UI.Hud)
local Overlay = require(script.UI.Overlay)
local Menu = require(script.UI.Menu)
local Touch = require(script.UI.Touch)
local Emotes = require(script.UI.Emotes)

local Districts = require(ReplicatedStorage.Shared.Config.Districts)

-- Our own HUD replaces the default health bar; chat and the player list stay.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local function start(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn(("[Skyline] %s failed to start: %s"):format(name, tostring(err)))
	end
end

start("State", State.Start)
start("Settings", Settings.Start)
start("Input", Input.Start)
State.Await(30)

start("Controller", Controller.Start)
start("Mechanisms", Mechanisms.Start)
start("Hazards", Hazards.Start)
start("Atmosphere", Atmosphere.Start)
task.spawn(start, "Detail", Detail.Start)

start("Animator", Animator.Start)
start("Camera", CameraController.Start)
start("Sfx", Sfx.Start)
start("Music", Music.Start)
start("Effects", Effects.Start)

start("Flow", Flow.Start)
start("Ghosts", Ghosts.Start)
start("Courses", CourseClient.Start)
start("Quests", QuestClient.Start)
start("Modes", Modes.Start)
start("Lessons", Lessons.Start)
start("Explore", Explore.Start)
start("Prompts", Prompts.Start)

start("UI", Root.Start)
start("Hud", Hud.Start)
start("Overlay", Overlay.Start)
start("Menu", Menu.Start)
start("Touch", Touch.Start)
start("Emotes", Emotes.Start)

-- Presentation follows the district you're in and how well you're moving.
Atmosphere.Changed:Connect(function(districtId: string)
	Music.SetDistrict(districtId)
	local district = Districts.ById[districtId]
	Sfx.SetAmbience(if district then district.Ambience elseif districtId == "Dreamline" then "Aether" else "Plaza")
end)
Flow.TierChanged:Connect(function(tier: number)
	Music.SetFlowTier(tier)
end)

-- Saving is off in Studio without API access: say so once, clearly.
task.delay(4, function()
	if State.Persistent == false then
		Overlay.Banner("Progress won't be saved", "Enable Studio Access to API Services to test saving.", Color3.fromRGB(255, 176, 60))
	end
end)

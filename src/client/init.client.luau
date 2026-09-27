-- SKYBOUND client entry point.

local Settings = require(script.Settings)
local Movement = require(script.Movement)
local Graphics = require(script.Graphics)
local CameraFX = require(script.CameraFX)
local R6Animator = require(script.R6Animator)
local VFX = require(script.VFX)
local Sounds = require(script.Sounds)
local HUD = require(script.HUD)
local Combo = require(script.Combo)
local Trials = require(script.Trials)
local WorldFX = require(script.WorldFX)
local Menu = require(script.Menu)
local Emotes = require(script.Emotes)
local Progress = require(script.Progress)
local Tutorial = require(script.Tutorial)

-- No tools in this game: free up keys 1-4 for emotes.
game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

-- Saved settings arrive from the server shortly; everything reacts when they do.
task.spawn(Settings.Load)

Movement.Start()
Graphics.Start(Movement)
CameraFX.Start(Movement)
R6Animator.Start(Movement)
VFX.Start(Movement)
Sounds.Start(Movement)
HUD.Start(Movement)
Combo.Start(Movement)
WorldFX.Start()
Emotes.Start(Movement)
Progress.Start(Movement)
Menu.Start(Movement, HUD)
task.spawn(Tutorial.Start, Movement, Menu)
task.spawn(Trials.Start, Movement)

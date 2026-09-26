-- SKYBOUND client entry point.

local Movement = require(script.Movement)
local CameraFX = require(script.CameraFX)
local CharacterFX = require(script.CharacterFX)
local HUD = require(script.HUD)
local WorldFX = require(script.WorldFX)

Movement.Start()
CameraFX.Start(Movement)
CharacterFX.Start(Movement)
HUD.Start(Movement)
WorldFX.Start()

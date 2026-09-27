-- Dicebound server entry point. Builds the world, then starts saving and request handling.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Creating Net here (on the server) makes the remotes before any client asks for them.
require(ReplicatedStorage.Dicebound.Net)

local WorldBuilder = require(script.World.WorldBuilder)
local PlayerData = require(script.Services.PlayerData)
local Requests = require(script.Services.Requests)
local EventService = require(script.Services.EventService)

WorldBuilder.Build()
EventService.Start()
Requests.Start()
PlayerData.Start()

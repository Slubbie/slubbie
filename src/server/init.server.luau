-- SKYBOUND server entry point.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Before anything yields, so the engine never loads a default (non-R6) character.
Players.CharacterAutoLoads = false

require(ReplicatedStorage.Shared.Net) -- creates the remotes

local CharacterSpawner = require(script.CharacterSpawner)
local Economy = require(script.Economy)
local PlayerData = require(script.PlayerData)
local Progression = require(script.Progression)
local Shards = require(script.Shards)
local StateRelay = require(script.StateRelay)
local TimeTrials = require(script.TimeTrials)
local WorldBuilder = require(script.WorldBuilder)

local islands = WorldBuilder.Build()
PlayerData.Start()
Progression.Start()
Shards.Start()
StateRelay.Start()
Economy.Start()
TimeTrials.Start(islands)
CharacterSpawner.Start()

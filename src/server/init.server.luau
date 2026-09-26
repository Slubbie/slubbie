-- SKYBOUND server entry point.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local ropeRemote = Instance.new("RemoteEvent")
ropeRemote.Name = "Rope"
ropeRemote.Parent = remotes
remotes.Parent = ReplicatedStorage

local WorldBuilder = require(script.WorldBuilder)
local Shards = require(script.Shards)
local RopeRelay = require(script.RopeRelay)

WorldBuilder.Build()
Shards.Start()
RopeRelay.Start(ropeRemote)

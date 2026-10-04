-- Client glue for the multiplayer and challenge modes: race lobbies, relay
-- teams and baton handoffs, Spire floor clears, and Dreamline endless runs
-- (gates, lives and respawns).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MathUtil = require(ReplicatedStorage.Shared.Util.MathUtil)
local Net = require(ReplicatedStorage.Shared.Net)
local Tags = require(ReplicatedStorage.Shared.Tags)

local Bus = require(script.Parent.Parent.Core.Bus)
local Controller = require(script.Parent.Parent.Movement.Controller)
local Hazards = require(script.Parent.Parent.World.Hazards)
local Music = require(script.Parent.Parent.Audio.Music)
local Sfx = require(script.Parent.Parent.Audio.Sfx)
local Flow = require(script.Parent.Flow)

local Modes = {}

Modes.Race = nil :: any -- current race lobby summary
Modes.Relay = nil :: any -- current relay team summary
Modes.Endless = nil :: any -- current Dreamline state

local gates: { [number]: BasePart } = {}
local endlessCourse: string? = nil
local sentGate = 0

-- Races and relays ---------------------------------------------------------------------------------------

function Modes.RaceList(): any
	local ok, result = pcall(Net.Invoke, "Race.List")
	return if ok then result else nil
end

function Modes.CreateRace(courseId: string): (boolean, any)
	local ok, success, info = pcall(Net.Invoke, "Race.Create", courseId)
	if not ok then
		return false, "Couldn't reach the board"
	end
	return success == true, info
end

function Modes.JoinRace(lobbyId: string): (boolean, any)
	local ok, success, info = pcall(Net.Invoke, "Race.Join", lobbyId)
	if not ok then
		return false, "Couldn't reach the board"
	end
	return success == true, info
end

function Modes.CreateRelay(courseId: string): (boolean, any)
	local ok, success, info = pcall(Net.Invoke, "Relay.Create", courseId)
	if not ok then
		return false, "Couldn't reach the board"
	end
	return success == true, info
end

function Modes.JoinRelay(teamId: string): (boolean, any)
	local ok, success, info = pcall(Net.Invoke, "Relay.Join", teamId)
	if not ok then
		return false, "Couldn't reach the board"
	end
	return success == true, info
end

-- Spire ----------------------------------------------------------------------------------------------------

function Modes.EnterTower(floor: number?): (boolean, string?)
	local ok, success, info = pcall(Net.Invoke, "Tower.Enter", floor)
	if not ok then
		return false, "The lift is stuck"
	end
	if not success then
		return false, if type(info) == "string" then info else "The lift won't move"
	end
	return true, nil
end

function Modes.TowerFloor(floor: number): (boolean, string?)
	local ok, success, info = pcall(Net.Invoke, "Tower.Floor", floor)
	if not ok then
		return false, "The lift is stuck"
	end
	if not success then
		return false, if type(info) == "string" then info else "That floor isn't open"
	end
	if type(info) == "table" and typeof(info.Roof) == "CFrame" then
		Controller.Teleport(info.Roof)
		Bus.Banner:Fire("The roof of the Spire", "The whole city, laid out below you.", Color3.fromRGB(255, 196, 92))
	end
	return true, nil
end

function Modes.LeaveTower()
	task.spawn(function()
		local ok, destination = pcall(Net.Invoke, "Tower.Leave")
		if ok and typeof(destination) == "CFrame" then
			Controller.Teleport(destination)
		end
	end)
end

-- Dreamline ----------------------------------------------------------------------------------------------

local function indexGates()
	table.clear(gates)
	local courseId = endlessCourse
	if not courseId then
		return
	end
	for _, part in CollectionService:GetTagged(Tags.CourseCheckpoint) do
		if part:IsA("BasePart") and part:GetAttribute("CourseId") == courseId then
			local index = part:GetAttribute("Index")
			if type(index) == "number" then
				gates[index] = part
			end
		end
	end
end

local function endlessCleanup()
	Modes.Endless = nil
	endlessCourse = nil
	table.clear(gates)
	Hazards.PopHandler("Endless")
	Hazards.KillY = nil
	Music.SetIntensity(0)
end

local function applyEndless(info: any)
	Modes.Endless = info
	endlessCourse = info.CourseId
	Hazards.KillY = info.KillY
	Music.SetIntensity(if (info.Cleared or 0) >= 15 then 2 else 1)
	indexGates()
	Bus.Mode:Fire("Endless", info)
end

function Modes.StartEndless()
	task.spawn(function()
		local ok, success, info = pcall(Net.Invoke, "Endless.Start")
		if not ok or not success then
			Bus.Banner:Fire("The Dreamline is closed", if ok and type(info) == "string" then info else nil)
			return
		end
		sentGate = 0
		Controller.Teleport(info.Spawn)
		applyEndless(info)
		Flow.Break("Respawn")
		Hazards.PushHandler("Endless", function(): CFrame?
			local current = Modes.Endless
			if not current then
				return nil
			end
			Net.Send("Endless.Gate", -1)
			return current.Respawn
		end)
		Bus.Banner:Fire("The Dreamline", "Three lives. How far can you go?", Color3.fromRGB(255, 160, 240))
	end)
end

function Modes.EndEndless()
	Net.Send("Endless.End")
end

function Modes.Start()
	Net.Listen("Race.Lobby", function(lobby)
		Modes.Race = lobby
		Bus.Mode:Fire("Race", lobby)
	end)
	Net.Listen("Race.Progress", function(userId, index)
		Bus.Mode:Fire("RaceProgress", { UserId = userId, Index = index })
	end)
	Net.Listen("Race.Reward", function(data)
		Bus.Mode:Fire("RaceReward", data)
		if type(data) == "table" and data.Place == 1 and (data.Field or 0) >= 2 then
			Sfx.Stinger("Platinum")
		end
	end)
	Net.Listen("Relay.Team", function(team)
		Modes.Relay = team
		Bus.Mode:Fire("Relay", team)
	end)
	Net.Listen("Relay.Wait", function(data)
		if type(data) == "table" and typeof(data.Spawn) == "CFrame" then
			Controller.Teleport(data.Spawn)
			Bus.Banner:Fire(("Leg %d"):format(data.Leg or 2), "Wait here for the baton", Color3.fromRGB(255, 120, 220))
		end
	end)
	Net.Listen("Relay.Handoff", function(data)
		Bus.Mode:Fire("RelayHandoff", data)
		Sfx.Stinger("Go")
	end)
	Net.Listen("Relay.Results", function(data)
		Bus.Mode:Fire("RelayResults", data)
		Sfx.Stinger(if (data.Medal or 0) >= 4 then "Platinum" else "Medal")
	end)
	Net.Listen("Relay.Stopped", function(reason)
		Bus.Banner:Fire("Relay stopped", tostring(reason))
	end)
	Net.Listen("Tower.Cleared", function(data)
		Bus.Mode:Fire("TowerCleared", data)
	end)
	Net.Listen("Endless.State", function(info)
		if type(info) == "table" then
			local previous = Modes.Endless
			applyEndless(info)
			if previous and info.Lives < previous.Lives then
				Bus.Banner:Fire(("%d %s left"):format(info.Lives, if info.Lives == 1 then "life" else "lives"), nil, Color3.fromRGB(255, 140, 140))
			end
		end
	end)
	Net.Listen("Endless.Ended", function(data)
		endlessCleanup()
		if type(data) == "table" and typeof(data.Lobby) == "CFrame" then
			Controller.Teleport(data.Lobby)
		end
		Bus.Mode:Fire("EndlessEnded", data)
	end)
	-- Dreamline gates.
	RunService.Heartbeat:Connect(function()
		local state = Modes.Endless
		local root = Controller.Info.Root
		if not state or not root then
			return
		end
		local nextIndex = (state.Cleared or 0) + 1
		local gate = gates[nextIndex]
		if not gate then
			indexGates()
			gate = gates[nextIndex]
		end
		if gate and sentGate < nextIndex and MathUtil.InBox(gate.CFrame, gate.Size, root.Position, 1) then
			sentGate = nextIndex
			Net.Send("Endless.Gate", nextIndex)
			Sfx.Stinger("Checkpoint")
		end
	end)
end

return Modes

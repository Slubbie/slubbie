-- Movement runs on each player's own client. This relays what they're doing to
-- everyone else so their animations, ropes and effects show up for all players.
--
--   MoveState  → mirrored onto the character as attributes:
--                MoveState (string), WallNormal (Vector3), GrapplePoint (Vector3)
--   MoveAction → one-shot moves (dash, wall jump...) re-broadcast to other clients

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local CharacterSpawner = require(script.Parent.CharacterSpawner)
local Progression = require(script.Parent.Progression)

local VALID_STATES = { Ground = true, Air = true, Grapple = true, WallRun = true, Slide = true }
local VALID_ACTIONS = {
	Grapple = true,
	WallRun = true,
	Slide = true,
	Emote_Stop = true,
	Dash = true,
	WallJump = true,
	Launch = true,
	Slingshot = true,
	HardLand = true,
	Roll = true,
	BunnyHop = true,
	SlideJump = true,
}
for _, name in Config.Emotes do
	VALID_ACTIONS["Emote_" .. name] = true
end
local MAX_PER_SECOND = 30
local lastLook: { [Player]: number } = {}

local StateRelay = {}

local budget: { [Player]: { Count: number, Window: number } } = {}

local function allow(player: Player): boolean
	local now = os.clock()
	local entry = budget[player]
	if not entry or now - entry.Window > 1 then
		entry = { Count = 0, Window = now }
		budget[player] = entry
	end
	entry.Count += 1
	return entry.Count <= MAX_PER_SECOND
end

function StateRelay.Start()
	local moveState = Net.Event("MoveState")
	local moveAction = Net.Event("MoveAction")

	moveState.OnServerEvent:Connect(function(player, state, wallNormal, grapplePoint)
		if not allow(player) or type(state) ~= "string" or not VALID_STATES[state] then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not root then
			return
		end
		character:SetAttribute("MoveState", state)
		-- Remember solid ground so a fall respawns you where you last landed.
		if state == "Ground" then
			CharacterSpawner.SetSafeSpot(player, (root :: BasePart).Position)
		end
		character:SetAttribute("WallNormal", if typeof(wallNormal) == "Vector3" then wallNormal.Unit else nil)
		local point = nil
		if
			typeof(grapplePoint) == "Vector3"
			and (grapplePoint - root.Position).Magnitude < Config.Grapple.Range + 60
		then
			point = grapplePoint
		end
		character:SetAttribute("GrapplePoint", point)
	end)

	-- Head direction, mirrored to the "Look" character attribute for other players.
	Net.Event("Look").OnServerEvent:Connect(function(player, direction)
		local now = os.clock()
		if now - (lastLook[player] or 0) < 0.08 or typeof(direction) ~= "Vector3" then
			return
		end
		if direction.Magnitude < 0.5 or direction.Magnitude > 1.5 then
			return
		end
		lastLook[player] = now
		local character = player.Character
		if character then
			character:SetAttribute("Look", direction.Unit)
		end
	end)

	moveAction.OnServerEvent:Connect(function(player, action)
		if not allow(player) or type(action) ~= "string" or not VALID_ACTIONS[action] then
			return
		end
		for _, other in Players:GetPlayers() do
			if other ~= player then
				moveAction:FireClient(other, player, action)
			end
		end
		if string.sub(action, 1, 6) ~= "Emote_" then
			Progression.Record(player, action)
		elseif action ~= "Emote_Stop" then
			Progression.Record(player, "Emote")
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastLook[player] = nil
		budget[player] = nil
	end)
end

return StateRelay

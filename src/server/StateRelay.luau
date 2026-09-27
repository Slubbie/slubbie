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

local VALID_STATES = { Ground = true, Air = true, Grapple = true, WallRun = true, Slide = true }
local VALID_ACTIONS = {
	Dash = true,
	WallJump = true,
	Launch = true,
	Slingshot = true,
	HardLand = true,
	Roll = true,
	BunnyHop = true,
	SlideJump = true,
}
local MAX_PER_SECOND = 30

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

	moveAction.OnServerEvent:Connect(function(player, action)
		if not allow(player) or type(action) ~= "string" or not VALID_ACTIONS[action] then
			return
		end
		for _, other in Players:GetPlayers() do
			if other ~= player then
				moveAction:FireClient(other, player, action)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		budget[player] = nil
	end)
end

return StateRelay

-- Every remote in one place. The server creates them, clients wait for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	-- client → server: (state, wallNormal?, grapplePoint?)  — mirrored onto character attributes
	"MoveState",
	-- client → server: (action)   server → other clients: (player, action)
	"MoveAction",
	-- client → server: (score)    server → client: (shardsEarned)
	"BankCombo",
	-- client → server: (courseId, ringIndex) ; ringIndex 0 cancels the run
	"TrialCheckpoint",
	-- server → client: (kind, data)
	"TrialEvent",
	-- client → server: (settings table)
	"SaveSettings",
	-- server → client: (kind, data) — level ups, quest completions
	"Notify",
	-- client → server: (courseId, ghostData) right after a record run
	"SubmitGhost",
	-- client → server: () when the tutorial is finished or skipped
	"CompleteTutorial",
}

local FUNCTIONS = {
	-- (action: "Buy" | "Equip", itemId) → (ok, message)
	"Shop",
	-- () → leaderboards
	"GetLeaderboards",
	-- (courseId) → ok ; teleports you to a course start
	"GoToTrial",
	-- () → saved settings table (or nil)
	"GetSettings",
	-- (courseId) → your best-run ghost data (or nil)
	"GetGhost",
	-- () → teleports you back to the spawn plaza
	"ReturnToSpawn",
}

local Net = {}

local folder: Folder
if RunService:IsServer() then
	folder = Instance.new("Folder")
	folder.Name = "Remotes"
	for _, name in EVENTS do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	for _, name in FUNCTIONS do
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = folder
	end
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

function Net.Event(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

function Net.Function(name: string): RemoteFunction
	return folder:WaitForChild(name) :: RemoteFunction
end

return Net

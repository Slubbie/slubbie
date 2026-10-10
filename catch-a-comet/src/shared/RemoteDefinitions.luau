--!strict
-- The documented remote contract. The server creates exactly these remotes;
-- the client waits for them. Every client → server remote declares its
-- argument schema and rate limit, and the server's SecurityService rejects
-- anything that doesn't match before a handler ever runs.
--
-- Clients never send amounts, rarities, rewards, success flags or arbitrary
-- tables. They send IDs, choices from fixed lists, and timing reports that
-- the server re-checks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type ArgSpec = {
	Type: "string" | "integer" | "number" | "boolean" | "enum" | "settings",
	MaxLength: number?,
	Min: number?,
	Max: number?,
	Values: { string }?,
	Optional: boolean?,
}

export type RemoteSpec = {
	Kind: "Function" | "Event",
	-- "ToServer" remotes are validated + rate limited; "ToClient" are server pushes.
	Direction: "ToServer" | "ToClient",
	Args: { ArgSpec }?,
	-- Token bucket: refills PerSecond tokens each second, holds at most Burst.
	Rate: { PerSecond: number, Burst: number }?,
	Doc: string,
}

local ID = { Type = "string", MaxLength = 48 } :: ArgSpec
local SLOT = { Type = "integer", Min = 1, Max = 12 } :: ArgSpec

local RemoteDefinitions = {}

RemoteDefinitions.Remotes = {
	-- Client → server ------------------------------------------------------
	StateSnapshot = {
		Kind = "Function",
		Direction = "ToServer",
		Args = {},
		Rate = { PerSecond = 0.5, Burst = 3 },
		Doc = "() → full state for the local player (profile view, comets, wisps). Waits for the profile to load.",
	},
	StartCapture = {
		Kind = "Function",
		Direction = "ToServer",
		Args = { ID },
		Rate = { PerSecond = 2, Burst = 4 },
		Doc = "(cometId) → { Ok, Reason?, Session? }. Server checks the comet, distance, claims and storage.",
	},
	CaptureAction = {
		Kind = "Function",
		Direction = "ToServer",
		Args = {
			{ Type = "integer", Min = 1, Max = 2 ^ 31 } :: ArgSpec,
			{ Type = "enum", Values = { "Lock", "Release", "Cancel" } } :: ArgSpec,
			{ Type = "number", Min = 0, Max = 600, Optional = true } :: ArgSpec,
			{ Type = "number", Min = 0, Max = 600, Optional = true } :: ArgSpec,
		},
		Rate = { PerSecond = 8, Burst = 12 },
		Doc = "(sessionId, action, t1?, t2?) → stage result. Times are seconds since the session began on the client.",
	},
	OpenComet = {
		Kind = "Function",
		Direction = "ToServer",
		Args = { ID },
		Rate = { PerSecond = 2, Burst = 4 },
		Doc = "(coreId) → { Ok, Reason?, Creature? }. Opens a sealed comet core; the server rolls the creature.",
	},
	EquipCreature = {
		Kind = "Function",
		Direction = "ToServer",
		Args = { ID, SLOT },
		Rate = { PerSecond = 4, Burst = 8 },
		Doc = "(creatureId, slot) → { Ok, Reason? }. Places an owned creature in an unlocked habitat slot.",
	},
	RemoveCreature = {
		Kind = "Function",
		Direction = "ToServer",
		Args = { SLOT },
		Rate = { PerSecond = 4, Burst = 8 },
		Doc = "(slot) → { Ok, Reason? }. Returns a deployed creature to the inventory.",
	},
	ReleaseCreature = {
		Kind = "Function",
		Direction = "ToServer",
		Args = { ID },
		Rate = { PerSecond = 3, Burst = 6 },
		Doc = "(creatureId) → { Ok, Reason?, Stardust? }. Releases an unlocked, undeployed creature for Stardust.",
	},
	SetCreatureFlag = {
		Kind = "Function",
		Direction = "ToServer",
		Args = { ID, { Type = "enum", Values = { "Locked", "Favorite" } } :: ArgSpec, { Type = "boolean" } :: ArgSpec },
		Rate = { PerSecond = 5, Burst = 10 },
		Doc = "(creatureId, flag, value) → { Ok, Reason? }.",
	},
	PurchaseUpgrade = {
		Kind = "Function",
		Direction = "ToServer",
		Args = { { Type = "enum", Values = { "Scanner", "Tether", "Habitat" } } :: ArgSpec },
		Rate = { PerSecond = 2, Burst = 4 },
		Doc = "(track) → { Ok, Reason?, Level? }. Atomic: currency is spent and the level raised together, or neither.",
	},
	ClaimQuest = {
		Kind = "Function",
		Direction = "ToServer",
		Args = { ID },
		Rate = { PerSecond = 2, Burst = 4 },
		Doc = "(questId) → { Ok, Reason? }. Claims a completed mission's reward once.",
	},
	CollectWisp = {
		Kind = "Function",
		Direction = "ToServer",
		Args = { { Type = "string", MaxLength = 16 } :: ArgSpec },
		Rate = { PerSecond = 6, Burst = 10 },
		Doc = "(wispId) → { Ok, Reason? }. Server checks distance and the per-player respawn timer.",
	},
	Travel = {
		Kind = "Function",
		Direction = "ToServer",
		Args = {
			{
				Type = "enum",
				Values = {
					"Hub",
					"Sanctuary",
					"DawnCommons",
					"PrismCliffs",
					"ThunderReef",
					"ShadowCrater",
					"AstralExpanse",
				},
			} :: ArgSpec,
		},
		Rate = { PerSecond = 1, Burst = 2 },
		Doc = "(destination) → { Ok, Reason? }. Quick travel to unlocked places.",
	},
	UpdateSettings = {
		Kind = "Event",
		Direction = "ToServer",
		Args = { { Type = "settings" } :: ArgSpec },
		Rate = { PerSecond = 2, Burst = 6 },
		Doc = "(settings) — only known keys with valid values are stored.",
	},
	-- Server → client ------------------------------------------------------
	StateDelta = {
		Kind = "Event",
		Direction = "ToClient",
		Doc = "(sequence, { { Path, Value } }) — profile changes since the snapshot, applied in order.",
	},
	CometBroadcast = {
		Kind = "Event",
		Direction = "ToClient",
		Doc = "(kind: 'Spawn' | 'Expire' | 'Claimed', payload) — comet registry changes.",
	},
	Notification = {
		Kind = "Event",
		Direction = "ToClient",
		Doc = "(kind, payload) — toasts, level ups, offline earnings, save status, tutorial cues.",
	},
} :: { [string]: RemoteSpec }

-- Settings the client may store, with their allowed values.
RemoteDefinitions.SettingsSchema = {
	MusicVolume = { Type = "number", Min = 0, Max = 1 } :: ArgSpec,
	EffectsVolume = { Type = "number", Min = 0, Max = 1 } :: ArgSpec,
	AmbientVolume = { Type = "number", Min = 0, Max = 1 } :: ArgSpec,
	ReducedMotion = { Type = "boolean" } :: ArgSpec,
	EasyCapture = { Type = "boolean" } :: ArgSpec,
	AutoOpenCores = { Type = "boolean" } :: ArgSpec,
	GraphicsQuality = { Type = "enum", Values = { "Auto", "Low", "Medium", "High" } } :: ArgSpec,
} :: { [string]: ArgSpec }

local FOLDER_NAME = "Remotes"
local folder: Folder? = nil

-- Server only: create every remote. Call once from the bootstrap.
function RemoteDefinitions.CreateAll(): Folder
	assert(RunService:IsServer(), "RemoteDefinitions.CreateAll is server-only")
	if folder then
		return folder
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = FOLDER_NAME
	for name, spec in RemoteDefinitions.Remotes do
		local remote = Instance.new(if spec.Kind == "Function" then "RemoteFunction" else "RemoteEvent")
		remote.Name = name
		remote.Parent = newFolder
	end
	newFolder.Parent = ReplicatedStorage
	folder = newFolder
	return newFolder
end

local function getFolder(): Folder
	if folder then
		return folder
	end
	local found = ReplicatedStorage:WaitForChild(FOLDER_NAME, 60)
	assert(found, "Remotes folder never appeared — is the server bootstrap running?")
	folder = found :: Folder
	return found :: Folder
end

function RemoteDefinitions.GetFunction(name: string): RemoteFunction
	assert(RemoteDefinitions.Remotes[name], `Unknown remote '{name}'`)
	return getFolder():WaitForChild(name) :: RemoteFunction
end

function RemoteDefinitions.GetEvent(name: string): RemoteEvent
	assert(RemoteDefinitions.Remotes[name], `Unknown remote '{name}'`)
	return getFolder():WaitForChild(name) :: RemoteEvent
end

return RemoteDefinitions

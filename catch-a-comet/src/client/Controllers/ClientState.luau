-- The client's read-only mirror of its own server state.
--
-- Load() fetches a snapshot (profile view, session values, comets, wisps);
-- StateDelta events then apply path-based changes in order. Deltas that
-- arrive before the snapshot are buffered; any at or below the snapshot's
-- sequence number are already included and are skipped.
--
-- UI code subscribes with Observe(key, fn), which runs immediately and after
-- every change to that top-level key. Nothing here can change the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteDefinitions = require(Shared.RemoteDefinitions)
local Signal = require(Shared.Signal)

local ClientState = {}

ClientState.Ready = false
ClientState.ReadySignal = Signal.new()
-- (root: "Profile" | "Session", key: string)
ClientState.Changed = Signal.new()
ClientState.Profile = {} :: { [string]: any }
ClientState.Session = {} :: { [string]: any }
ClientState.InitialComets = {} :: { any }
ClientState.InitialWisps = nil :: any

local lastSeq = -1
local buffered: { { Seq: number, Changes: { any } } } = {}

type Touched = { [string]: { [string]: boolean } }

local function applyChanges(changes: { any }): Touched
	local touched: Touched = { Profile = {}, Session = {} }
	for _, change in changes do
		local path = change.Path
		if type(path) ~= "table" or #path < 2 then
			continue
		end
		local root = if path[1] == "Profile"
			then ClientState.Profile
			elseif path[1] == "Session" then ClientState.Session
			else nil
		if not root then
			continue
		end
		local node = root
		for i = 2, #path - 1 do
			local key = path[i]
			if type(node[key]) ~= "table" then
				node[key] = {}
			end
			node = node[key]
		end
		node[path[#path]] = change.Value
		touched[path[1]][path[2]] = true
	end
	return touched
end

local function fireTouched(touched: Touched)
	for root, keys in touched do
		for key in keys do
			ClientState.Changed:Fire(root, key)
		end
	end
end

local function onDelta(seq: number, changes: { any })
	if type(seq) ~= "number" or type(changes) ~= "table" then
		return
	end
	if not ClientState.Ready then
		table.insert(buffered, { Seq = seq, Changes = changes })
		return
	end
	-- Deltas apply in order, once each; anything older is already included.
	if seq <= lastSeq then
		return
	end
	lastSeq = seq
	fireTouched(applyChanges(changes))
end

-- Yields until the snapshot arrives. Retries a few times if the server is busy.
function ClientState.Load(): boolean
	RemoteDefinitions.GetEvent("StateDelta").OnClientEvent:Connect(onDelta)
	local remote = RemoteDefinitions.GetFunction("StateSnapshot")
	for attempt = 1, 8 do
		local ok, result = pcall(function()
			return remote:InvokeServer()
		end)
		if ok and type(result) == "table" and result.Ok and result.Snapshot then
			local snapshot = result.Snapshot
			ClientState.Profile = snapshot.Profile or {}
			ClientState.Session = snapshot.Session or {}
			ClientState.InitialComets = snapshot.Comets or {}
			ClientState.InitialWisps = snapshot.Wisps
			lastSeq = snapshot.Seq or 0
			ClientState.Ready = true
			table.sort(buffered, function(a, b)
				return a.Seq < b.Seq
			end)
			for _, entry in buffered do
				if entry.Seq > lastSeq then
					lastSeq = entry.Seq
					applyChanges(entry.Changes)
				end
			end
			buffered = {}
			ClientState.ReadySignal:Fire()
			return true
		end
		task.wait(math.min(2 ^ attempt * 0.25, 5))
	end
	warn("[ClientState] Couldn't load state from the server")
	return false
end

function ClientState.Get(key: string): any
	return ClientState.Profile[key]
end

function ClientState.GetSession(key: string): any
	return ClientState.Session[key]
end

-- Runs fn(value) now and whenever Profile[key] changes. Returns a disconnect function.
function ClientState.Observe(key: string, fn: (any) -> ()): () -> ()
	fn(ClientState.Profile[key])
	local connection = ClientState.Changed:Connect(function(root, changedKey)
		if root == "Profile" and changedKey == key then
			fn(ClientState.Profile[key])
		end
	end)
	return function()
		connection:Disconnect()
	end
end

function ClientState.ObserveSession(key: string, fn: (any) -> ()): () -> ()
	fn(ClientState.Session[key])
	local connection = ClientState.Changed:Connect(function(root, changedKey)
		if root == "Session" and changedKey == key then
			fn(ClientState.Session[key])
		end
	end)
	return function()
		connection:Disconnect()
	end
end

-- Convenience readers --------------------------------------------------------------

function ClientState.Creatures(): { [string]: any }
	return ClientState.Profile.Creatures or {}
end

function ClientState.Equipped(): { [string]: string }
	return ClientState.Profile.EquippedCreatures or {}
end

function ClientState.SlotOf(creatureId: string): number?
	for slot, id in ClientState.Equipped() do
		if id == creatureId then
			return tonumber(slot)
		end
	end
	return nil
end

function ClientState.Equipment(): { [string]: number }
	return ClientState.Profile.Equipment or { ScannerLevel = 1, TetherLevel = 1, HabitatLevel = 1 }
end

function ClientState.Settings(): { [string]: any }
	return ClientState.Profile.Settings or {}
end

return ClientState

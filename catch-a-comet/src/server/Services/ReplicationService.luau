-- Mirrors each player's state to their own client.
--
--   StateSnapshot (RemoteFunction): the client asks once on start and gets
--     its profile view, session values and world registries (comets, wisps).
--   StateDelta (RemoteEvent): path-based changes, batched and flushed once
--     per frame, numbered so the client ignores anything older than its snapshot.
--   Notification (RemoteEvent): one-off UI events (toasts, level ups…).
--
-- Services call Set() after they change the profile. Private profile fields
-- (receipts, fractional income) are never sent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteDefinitions = require(Shared.RemoteDefinitions)

local ProfileSchema = require(script.Parent.Parent.Data.ProfileSchema)

local ReplicationService = { Name = "ReplicationService" }

type Change = { Path: { string }, Value: any }

local services: { [string]: any } = {}
local queues: { [Player]: { Change } } = {}
local sequence: { [Player]: number } = {}
local sessionState: { [Player]: { [string]: any } } = {}
local providers: { [string]: (Player) -> any } = {}
local deltaRemote: RemoteEvent? = nil
local notifyRemote: RemoteEvent? = nil

-- Test hook: capture outgoing traffic instead of firing remotes.
ReplicationService.Sent = nil :: { any }?

local function queue(player: Player, change: Change)
	local list = queues[player]
	if not list then
		list = {}
		queues[player] = list
	end
	table.insert(list, change)
end

-- Queues a profile change. `path` is relative to the profile, e.g. {"Stardust"}
-- or {"Creatures", id}. A nil value deletes the entry on the client.
function ReplicationService.Set(player: Player, path: { string }, value: any)
	if #path == 0 or ProfileSchema.IsPrivateField(path[1]) then
		return
	end
	local full = { "Profile" }
	table.move(path, 1, #path, 2, full)
	queue(player, { Path = full, Value = value })
end

-- Runtime values that aren't saved: plot index, income rate, save status…
function ReplicationService.SetSession(player: Player, key: string, value: any)
	local state = sessionState[player]
	if not state then
		state = {}
		sessionState[player] = state
	end
	if state[key] == value and type(value) ~= "table" then
		return
	end
	state[key] = value
	queue(player, { Path = { "Session", key }, Value = value })
end

function ReplicationService.GetSession(player: Player, key: string): any
	local state = sessionState[player]
	return state and state[key]
end

-- Other services add their registries (comets, wisps…) to the snapshot.
function ReplicationService.RegisterSnapshotProvider(name: string, provider: (Player) -> any)
	providers[name] = provider
end

function ReplicationService.BuildSnapshot(player: Player): { [string]: any }?
	local profile = services.PlayerDataService.GetProfile(player)
	if not profile then
		return nil
	end
	local snapshot: { [string]: any } = {
		Seq = sequence[player] or 0,
		Profile = ProfileSchema.ClientView(profile),
		Session = table.clone(sessionState[player] or {}),
		ServerTime = workspace:GetServerTimeNow(),
	}
	for name, provider in providers do
		local ok, result = pcall(provider, player)
		if ok then
			snapshot[name] = result
		else
			warn(`[Replication] Snapshot provider '{name}' failed: {result}`)
		end
	end
	return snapshot
end

function ReplicationService.Notify(player: Player, kind: string, payload: any?)
	if ReplicationService.Sent then
		table.insert(ReplicationService.Sent, { Player = player, Kind = kind, Payload = payload })
		return
	end
	if notifyRemote and player.Parent then
		notifyRemote:FireClient(player, kind, payload)
	end
end

function ReplicationService.NotifyAll(kind: string, payload: any?)
	for _, player in Players:GetPlayers() do
		ReplicationService.Notify(player, kind, payload)
	end
end

function ReplicationService.Flush()
	for player, list in queues do
		if #list == 0 then
			continue
		end
		queues[player] = {}
		local seq = (sequence[player] or 0) + 1
		sequence[player] = seq
		if ReplicationService.Sent then
			table.insert(ReplicationService.Sent, { Player = player, Kind = "Delta", Payload = list, Seq = seq })
		elseif deltaRemote and player.Parent then
			deltaRemote:FireClient(player, seq, list)
		end
	end
end

function ReplicationService.Init(registry: { [string]: any })
	services = registry
end

function ReplicationService.Start()
	if not ReplicationService.Sent then
		deltaRemote = RemoteDefinitions.GetEvent("StateDelta")
		notifyRemote = RemoteDefinitions.GetEvent("Notification")
	end

	services.SecurityService.BindFunction("StateSnapshot", function(player)
		local profile = services.PlayerDataService.WaitForProfile(player, 45)
		if not profile then
			return { Ok = false, Reason = "NotReady" }
		end
		return { Ok = true, Snapshot = ReplicationService.BuildSnapshot(player) }
	end, { RequireProfile = false })

	services.PlayerDataService.ProfileLoaded:Connect(function(player, _profile, session)
		ReplicationService.SetSession(player, "SaveStatus", session.SaveStatus)
	end)
	services.PlayerDataService.SaveStatusChanged:Connect(function(player, status)
		ReplicationService.SetSession(player, "SaveStatus", status)
		ReplicationService.Notify(player, "SaveStatus", { Status = status })
	end)

	RunService.Heartbeat:Connect(ReplicationService.Flush)
	Players.PlayerRemoving:Connect(function(player)
		queues[player] = nil
		sequence[player] = nil
		sessionState[player] = nil
	end)
end

return ReplicationService

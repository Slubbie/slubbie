-- Owns every player's profile for the session.
--
-- Gameplay mutates the in-memory profile (the single source of truth while
-- the player is here); this service persists it at safe checkpoints:
-- periodic autosave, a debounced priority save after high-value moments,
-- on leave (releasing the session lock) and on server shutdown.
--
-- Saves for one player never overlap: a save requested while one is running
-- waits its turn. Failure handling is conservative:
--   * load error in a live server  → kick with an explanation (never play on a blank profile)
--   * lock held by another server  → wait/retry, then kick with an explanation
--   * data from a newer game build → kick, data untouched
--   * save error                   → keep retrying, tell the player saving is delayed
--   * lock stolen by another server→ stop saving, kick (prevents two live copies)
--   * Studio without API access    → session-only mode with a visible banner

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Loop = require(Shared.Loop)
local Signal = require(Shared.Signal)

local ProfileSchema = require(script.Parent.Parent.Data.ProfileSchema)
local ProfileStore = require(script.Parent.Parent.Data.ProfileStore)

export type SaveStatus = "OK" | "Degraded" | "SessionOnly" | "Locked"

export type Session = {
	Player: Player,
	UserId: number,
	Key: string,
	Data: ProfileSchema.Profile,
	Persistent: boolean,
	SaveStatus: SaveStatus,
	Saving: boolean,
	Released: boolean,
	PriorityPending: boolean,
	LastSaved: number,
	-- LastSeenTimestamp as it was when the profile loaded (offline earnings use it).
	PreviousLastSeen: number,
	IsNew: boolean,
}

local PlayerDataService = { Name = "PlayerDataService" }

-- (player, profile, session) — fires once the profile is ready. Handlers must not yield.
PlayerDataService.ProfileLoaded = Signal.new()
-- (player, profile) — fires before the final save on leave/shutdown. Handlers must not yield.
PlayerDataService.ProfileReleasing = Signal.new()
-- (player, status)
PlayerDataService.SaveStatusChanged = Signal.new()

local config = GameConfig.Data
local sessions: { [Player]: Session } = {}
local loading: { [Player]: boolean } = {}
local releasing: { [number]: boolean } = {}
local store: ProfileStore.ProfileStore? = nil
local sessionOnly = false
local sessionId = ""
local isStudio = false
local configured = false
local clock: () -> number = os.time
local waitFn: (number) -> () = function(seconds)
	task.wait(seconds)
end

local function keyFor(userId: number): string
	return config.KeyPrefix .. tostring(userId)
end

local function looksLikeStudioAccessError(message: string?): boolean
	if not message then
		return false
	end
	local text = message:lower()
	return text:find("studioaccesstoapisnotallowed", 1, true) ~= nil
		or text:find("403", 1, true) ~= nil
		or text:find("publish", 1, true) ~= nil
		or text:find("api services", 1, true) ~= nil
end

local function setStatus(session: Session, status: SaveStatus)
	if session.SaveStatus == status then
		return
	end
	session.SaveStatus = status
	PlayerDataService.SaveStatusChanged:Fire(session.Player, status)
end

-- Test hook: replace the DataStore with any UpdateAsync backend.
function PlayerDataService.Configure(options: {
	Backend: ProfileStore.Backend?,
	SessionId: string?,
	Clock: (() -> number)?,
	Wait: ((number) -> ())?,
	IsStudio: boolean?,
	SessionOnly: boolean?,
})
	configured = true
	if options.Clock then
		clock = options.Clock
	end
	if options.Wait then
		waitFn = options.Wait
	end
	if options.SessionId then
		sessionId = options.SessionId
	end
	if options.IsStudio ~= nil then
		isStudio = options.IsStudio
	end
	if options.SessionOnly ~= nil then
		sessionOnly = options.SessionOnly
	end
	if options.Backend then
		store = ProfileStore.new(options.Backend, {
			SessionId = sessionId,
			Clock = function()
				return clock()
			end,
			Wait = function(seconds)
				waitFn(seconds)
			end,
			LockStaleSeconds = config.LockStaleSeconds,
			LoadLockRetries = config.LoadLockRetries,
			LoadLockRetryDelay = config.LoadLockRetryDelay,
			MaxRequestRetries = config.MaxRequestRetries,
			RetryBaseDelay = config.RetryBaseDelay,
		})
	end
end

-- The profile clock (unix seconds; injectable for tests).
function PlayerDataService.Now(): number
	return clock()
end

function PlayerDataService.GetSession(player: Player): Session?
	return sessions[player]
end

function PlayerDataService.GetProfile(player: Player): ProfileSchema.Profile?
	local session = sessions[player]
	return if session then session.Data else nil
end

function PlayerDataService.IsLoaded(player: Player): boolean
	return sessions[player] ~= nil
end

function PlayerDataService.IsSessionOnly(): boolean
	return sessionOnly
end

function PlayerDataService.GetSaveStatus(player: Player): SaveStatus?
	local session = sessions[player]
	return if session then session.SaveStatus else nil
end

function PlayerDataService.WaitForProfile(player: Player, timeout: number?): ProfileSchema.Profile?
	local deadline = os.clock() + (timeout or 30)
	while not sessions[player] and player.Parent and os.clock() < deadline do
		task.wait(0.1)
	end
	return PlayerDataService.GetProfile(player)
end

local function attach(player: Player, data: ProfileSchema.Profile, persistent: boolean, isNew: boolean): Session
	local session: Session = {
		Player = player,
		UserId = player.UserId,
		Key = keyFor(player.UserId),
		Data = data,
		Persistent = persistent,
		SaveStatus = if persistent then "OK" else "SessionOnly",
		Saving = false,
		Released = false,
		PriorityPending = false,
		LastSaved = clock(),
		PreviousLastSeen = data.LastSeenTimestamp,
		IsNew = isNew,
	}
	sessions[player] = session
	PlayerDataService.ProfileLoaded:Fire(player, data, session)
	return session
end

-- Loads (or creates) a player's profile. Yields. Returns a status string.
function PlayerDataService.LoadPlayer(player: Player): string
	if sessions[player] or loading[player] then
		return "AlreadyLoaded"
	end
	loading[player] = true
	-- Rejoining the same server: let our own final save finish first.
	local waited = 0
	while releasing[player.UserId] and waited < 30 do
		waitFn(0.2)
		waited += 0.2
	end

	local now = clock()
	if sessionOnly or not store then
		local data = ProfileSchema.Default(now)
		loading[player] = nil
		if not player.Parent then
			return "Left"
		end
		attach(player, data, false, true)
		return "SessionOnly"
	end

	local key = keyFor(player.UserId)
	local result, raw, message = (store :: ProfileStore.ProfileStore):Load(key)

	if result == "Error" then
		loading[player] = nil
		if isStudio and config.AllowSessionOnlyInStudio and looksLikeStudioAccessError(message) then
			warn(
				"[PlayerData] DataStores are unavailable in this Studio session (enable Game Settings → Security → API Services). Running in session-only mode; nothing will be saved."
			)
			sessionOnly = true
			return PlayerDataService.LoadPlayer(player)
		end
		warn(`[PlayerData] Failed to load {player.Name} ({player.UserId}): {message}`)
		player:Kick(
			"We couldn't load your save because Roblox's data service is having trouble. Your progress is safe — please rejoin in a minute."
		)
		return "Error"
	elseif result == "Locked" then
		loading[player] = nil
		warn(`[PlayerData] Profile for {player.Name} is locked by another server`)
		player:Kick("Your save is still open on another server. Please wait a moment and rejoin.")
		return "Locked"
	end

	local data, status, fixes = ProfileSchema.Prepare(raw, now, player.UserId)
	if not data then
		loading[player] = nil
		-- Don't overwrite what we can't read. Give the lock back untouched.
		task.spawn(function()
			(store :: ProfileStore.ProfileStore):Release(key)
		end)
		warn(`[PlayerData] Refusing to load {player.Name}: {status} {table.concat(fixes, "; ")}`)
		if status == "TooNew" then
			player:Kick("This server is running an older version of the game. Please rejoin to get the latest one.")
		else
			player:Kick(
				"Your save couldn't be read. It has not been changed. Please contact support if this keeps happening."
			)
		end
		return status
	end
	if #fixes > 0 then
		warn(`[PlayerData] Repaired {#fixes} issue(s) in {player.Name}'s profile: {table.concat(fixes, "; ")}`)
	end

	loading[player] = nil
	if not player.Parent then
		-- Left while loading: release the lock without changes.
		task.spawn(function()
			(store :: ProfileStore.ProfileStore):Release(key)
		end)
		return "Left"
	end
	attach(player, data, true, status == "New")
	return status
end

local function runSave(session: Session, release: boolean): string
	if not session.Persistent or not store then
		return "SessionOnly"
	end
	if session.Released then
		return "Released"
	end
	while session.Saving do
		task.wait(0.05)
	end
	if session.Released then
		return "Released"
	end
	session.Saving = true
	session.Data.LastSeenTimestamp = clock()
	local snapshot = ProfileSchema.DeepCopy(session.Data)
	local result, message = (store :: ProfileStore.ProfileStore):Save(session.Key, snapshot, release)
	session.Saving = false

	if result == "Saved" then
		session.LastSaved = clock()
		if release then
			session.Released = true
		end
		if session.SaveStatus == "Degraded" then
			setStatus(session, "OK")
		end
	elseif result == "LockLost" then
		warn(`[PlayerData] Lost the session lock for {session.UserId}; stopping saves for this session`)
		session.Persistent = false
		session.Released = true
		setStatus(session, "Locked")
		local player = session.Player
		if player.Parent then
			player:Kick("Your profile was opened on another server. Please rejoin.")
		end
	else
		warn(`[PlayerData] Save failed for {session.UserId}: {message}`)
		setStatus(session, "Degraded")
	end
	return result
end

-- Saves now (yields). `release` frees the session lock afterwards.
function PlayerDataService.SavePlayer(player: Player, release: boolean?): string
	local session = sessions[player]
	if not session then
		return "NoProfile"
	end
	return runSave(session, release == true)
end

-- Asks for a save soon, after high-value moments. Debounced.
function PlayerDataService.RequestSave(player: Player)
	local session = sessions[player]
	if not session or not session.Persistent or session.PriorityPending then
		return
	end
	session.PriorityPending = true
	task.delay(config.PrioritySaveDelay, function()
		session.PriorityPending = false
		if sessions[player] == session then
			runSave(session, false)
		end
	end)
end

-- Final save and lock release when a player leaves. Yields.
function PlayerDataService.ReleasePlayer(player: Player): string
	local session = sessions[player]
	if not session then
		return "NoProfile"
	end
	PlayerDataService.ProfileReleasing:Fire(player, session.Data)
	releasing[session.UserId] = true
	local result = runSave(session, true)
	sessions[player] = nil
	releasing[session.UserId] = nil
	return result
end

function PlayerDataService.Init(_registry: { [string]: any })
	if configured then
		return -- a test supplied its own backend and clock
	end
	isStudio = RunService:IsStudio()
	sessionId = HttpService:GenerateGUID(false)
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(config.StoreName)
	end)
	if ok then
		PlayerDataService.Configure({
			Backend = result,
			SessionId = sessionId,
			Clock = os.time,
			Wait = function(seconds)
				task.wait(seconds)
			end,
		})
	elseif isStudio and config.AllowSessionOnlyInStudio then
		warn(`[PlayerData] DataStores unavailable in Studio ({result}). Session-only mode: nothing will be saved.`)
		sessionOnly = true
	else
		-- Live servers keep trying per player and kick with an explanation if loading fails.
		warn(`[PlayerData] GetDataStore failed: {result}`)
	end
end

function PlayerDataService.Start()
	local function budgetWaiter()
		-- Back off when the UpdateAsync budget is exhausted instead of queueing errors.
		local deadline = os.clock() + 10
		while os.clock() < deadline do
			local ok, budget = pcall(function()
				return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
			end)
			if not ok or budget > 0 then
				return
			end
			task.wait(0.5)
		end
	end
	if store then
		(store :: any)._options.WaitForBudget = budgetWaiter
	end

	Players.PlayerRemoving:Connect(function(player)
		PlayerDataService.ReleasePlayer(player)
	end)

	-- Autosave. Also refreshes the session lock heartbeat.
	Loop.Every(config.AutosaveInterval, "Autosave", function()
		for _, session in sessions do
			if session.Persistent and not session.Saving and not session.Released then
				task.spawn(runSave, session, false)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in sessions do
			pending += 1
			task.spawn(function()
				PlayerDataService.ReleasePlayer(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + config.ShutdownTimeout
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
		if pending > 0 then
			warn(`[PlayerData] Shutdown timed out with {pending} save(s) unfinished`)
		end
	end)
end

-- Called by the bootstrap once every service has started, so no service can
-- miss a ProfileLoaded event.
function PlayerDataService.BeginLoading()
	Players.PlayerAdded:Connect(function(player)
		PlayerDataService.LoadPlayer(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(PlayerDataService.LoadPlayer, player)
	end
end

return PlayerDataService

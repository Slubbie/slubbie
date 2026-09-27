-- Loads, holds and saves every player's progress with DataStoreService.
--
-- Record stored under key "u_<UserId>":  { Data = <Schema.Data>, Lock = { Job, At }?, SavedAt }
--
-- SESSION LOCK: a server writes its JobId into Lock when it loads a player and refreshes it on
-- every autosave. Another server that finds a fresh lock waits (the first server is probably
-- still saving the player's exit) and, if the lock stays, disconnects the player with a
-- "try again in a minute" message instead of loading stale data. A lock older than LOCK_STALE
-- (a crashed server) is taken over. Every save checks the lock is still ours, so two servers can
-- never overwrite each other.
--
-- LOAD FAILURE: if the DataStore can't be read, the player is disconnected with a friendly
-- message. An empty default profile is NEVER saved over real progress. In Studio without API
-- access, the player instead gets an unsaved session and a banner saying so.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Dicebound.Config)
local Schema = require(script.Parent.Parent.Core.Schema)

local AUTOSAVE_INTERVAL = 90 -- seconds between saves of each player
local LOCK_STALE = 300 -- a lock not refreshed for this long belongs to a dead server
local LOAD_ATTEMPTS = 5
local SAVE_ATTEMPTS = 3
local JOB_ID = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false)

export type Profile = {
	Player: Player,
	Data: Schema.Data,
	SaveEnabled: boolean,
	SaveMode: string, -- "live" | "studio" (unsaved Studio session)
	Saving: boolean,
	Released: boolean,
}

local PlayerData = {}

-- Fired with (player, profile) once a player's data is ready.
local loadedEvent = Instance.new("BindableEvent")
PlayerData.Loaded = loadedEvent.Event

local profiles: { [Player]: Profile } = {}
local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Game.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[Dicebound] DataStores unavailable:", result)
	end
end

local function key(player: Player): string
	return "u_" .. player.UserId
end

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value :: any do
		copy[k] = deepCopy(v)
	end
	return copy :: any
end

local function backoff(attempt: number)
	task.wait(math.min(2 ^ (attempt - 1), 8) + math.random() * 0.5)
end

local function hasBudget(): boolean
	local ok, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
	end)
	return not ok or budget > 0
end

-- One attempt to read + lock a player's record.
-- Returns status ("ok" | "locked" | "newer" | "error"), raw data, error message.
local function tryAcquire(player: Player): (string, any, string?)
	if not store then
		return "error", nil, "no datastore"
	end
	local status, raw = "ok", nil
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(key(player), function(record)
			status, raw = "ok", nil
			if type(record) ~= "table" then
				record = nil
			end
			local lock = record and record.Lock
			if type(lock) == "table" and lock.Job ~= JOB_ID and os.time() - (tonumber(lock.At) or 0) < LOCK_STALE then
				status = "locked"
				return nil -- cancel: don't touch another server's session
			end
			raw = record and record.Data
			if type(raw) == "table" and (tonumber(raw.Version) or 1) > Schema.Version then
				status = "newer"
				return nil
			end
			local updated = record or {}
			updated.Lock = { Job = JOB_ID, At = os.time() }
			return updated
		end)
	end)
	if not ok then
		return "error", nil, tostring(err)
	end
	return status, raw, nil
end

-- Writes a snapshot. `release` clears the session lock (player left / server closing).
local function writeOnce(player: Player, snapshot: any, release: boolean): (boolean, boolean)
	local lost = false
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(key(player), function(record)
			lost = false
			local lock = type(record) == "table" and record.Lock
			if type(lock) == "table" and lock.Job ~= JOB_ID then
				lost = true
				return nil -- another server owns this save now; never overwrite it
			end
			return {
				Data = snapshot,
				Lock = if release then nil else { Job = JOB_ID, At = os.time() },
				SavedAt = os.time(),
			}
		end)
	end)
	if not ok then
		warn("[Dicebound] Save failed for", player.Name, err)
	end
	return ok, lost
end

local function save(profile: Profile, release: boolean): boolean
	if not profile.SaveEnabled or not store then
		return true
	end
	-- Wait for an in-flight save (autosave) so saves never race each other.
	local waited = 0
	while profile.Saving and waited < 30 do
		waited += task.wait(0.1)
	end
	profile.Saving = true
	local snapshot = deepCopy(profile.Data)
	local attempts = if release then SAVE_ATTEMPTS else 1
	local success = false
	for attempt = 1, attempts do
		local ok, lost = writeOnce(profile.Player, snapshot, release)
		if lost then
			profile.SaveEnabled = false
			warn(
				"[Dicebound] Session for",
				profile.Player.Name,
				"was taken over by another server; stopped saving here."
			)
			if profile.Player.Parent then
				profile.Player:Kick("Your save was opened on another server. Please rejoin.")
			end
			break
		end
		if ok then
			success = true
			break
		end
		if attempt < attempts then
			backoff(attempt)
		end
	end
	profile.Saving = false
	return success
end

local function load(player: Player)
	local raw, status, lastError
	for attempt = 1, LOAD_ATTEMPTS do
		status, raw, lastError = tryAcquire(player)
		if status == "ok" or status == "newer" then
			break
		end
		-- In Studio an error almost always means API access is off: don't make the tester wait.
		if status == "error" and RunService:IsStudio() then
			break
		end
		if not player.Parent then
			return
		end
		if attempt < LOAD_ATTEMPTS then
			backoff(attempt)
		end
	end

	local profile: Profile
	if status == "ok" then
		local data, reason = Schema.Load(raw)
		if not data then
			-- Can't happen for "ok" (newer versions are caught in tryAcquire) but never risk it.
			player:Kick(
				"We couldn't read your save (" .. tostring(reason) .. "). Your progress is safe; please rejoin."
			)
			return
		end
		profile =
			{ Player = player, Data = data, SaveEnabled = true, SaveMode = "live", Saving = false, Released = false }
	elseif status == "newer" then
		player:Kick("This server is running an older version of the game. Please rejoin to get a newer server.")
		return
	elseif status == "locked" then
		player:Kick("Your save is still open on another server. Please wait a minute and rejoin.")
		return
	elseif RunService:IsStudio() then
		warn(
			"[Dicebound] Couldn't reach DataStores in Studio (" .. tostring(lastError) .. ").",
			"Playing an UNSAVED session. Enable Game Settings > Security > 'Enable Studio Access to API Services' to test saving."
		)
		profile = {
			Player = player,
			Data = Schema.Defaults(),
			SaveEnabled = false,
			SaveMode = "studio",
			Saving = false,
			Released = false,
		}
	else
		player:Kick(
			"We couldn't load your save right now (Roblox data service issue). Your progress is safe; please rejoin."
		)
		return
	end

	if not player.Parent then
		-- Left while loading: hand the lock straight back.
		if profile.SaveEnabled then
			save(profile, true)
		end
		return
	end
	profiles[player] = profile
	loadedEvent:Fire(player, profile)
end

local function release(player: Player)
	local profile = profiles[player]
	if not profile or profile.Released then
		return
	end
	profile.Released = true
	save(profile, true)
	profiles[player] = nil
end

-- The loaded profile, or nil while loading / after leaving.
function PlayerData.Get(player: Player): Profile?
	local profile = profiles[player]
	return if profile and not profile.Released then profile else nil
end

function PlayerData.All(): { [Player]: Profile }
	return profiles
end

function PlayerData.Start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(load, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(release)

	-- Autosave: spread players across the interval so requests don't burst.
	task.spawn(function()
		while true do
			local list = {}
			for player in profiles do
				table.insert(list, player)
			end
			local gap = AUTOSAVE_INTERVAL / math.max(#list, 1)
			for _, player in list do
				local profile = profiles[player]
				if profile and not profile.Released and hasBudget() then
					task.spawn(save, profile, false)
				end
				task.wait(gap)
			end
			if #list == 0 then
				task.wait(AUTOSAVE_INTERVAL)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				release(player)
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.1)
		end
	end)
end

return PlayerData

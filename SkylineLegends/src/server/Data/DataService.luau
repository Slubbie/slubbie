-- Reliable saving with session locking.
--
-- Each profile is stored as { Data, Lock = { JobId, Time } }. A server only
-- writes a profile while it holds the lock, so joining a new server right
-- after leaving another can never roll progress back. Profiles autosave every
-- couple of minutes, on leave and on shutdown, with retries.
--
-- Without DataStore access (Studio with API services off) everything still
-- works in memory and a warning explains why progress won't persist.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Schema = require(script.Parent.Schema)

local STORE_NAME = "SkylineLegends_Profiles_v1"
local AUTOSAVE_INTERVAL = 120
local LOCK_EXPIRY = 30 * 60
local MAX_LOAD_ATTEMPTS = 6

local DataService = {}
DataService.Persistent = true
DataService.Loaded = Signal.new() -- (player, profile)
DataService.Releasing = Signal.new() -- (player, profile) just before the final save

local store: DataStore? = nil
local profiles: { [Player]: { [string]: any } } = {}
local dirty: { [Player]: boolean } = {}
local loading: { [Player]: boolean } = {}
local jobId = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false)

local function keyFor(player: Player): string
	return "u_" .. player.UserId
end

local function openStore()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		DataService.Persistent = false
		warn("[Data] DataStores unavailable; progress will not be saved this session: " .. tostring(result))
	end
end

-- Store access -------------------------------------------------------------------

local function load(player: Player): { [string]: any }?
	if not store then
		return Schema.Default()
	end
	local key = keyFor(player)
	for attempt = 1, MAX_LOAD_ATTEMPTS do
		local lockedElsewhere = false
		local loaded: { [string]: any }? = nil
		local force = attempt == MAX_LOAD_ATTEMPTS
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(key, function(old: any)
				if type(old) == "table" and type(old.Lock) == "table" and not force then
					local lock = old.Lock
					if lock.JobId ~= jobId and os.time() - (lock.Time or 0) < LOCK_EXPIRY then
						lockedElsewhere = true
						return nil
					end
				end
				local data = if type(old) == "table" and type(old.Data) == "table" then old.Data else nil
				loaded = Schema.Migrate(data or Schema.Default())
				return { Data = loaded, Lock = { JobId = jobId, Time = os.time() } }
			end)
		end)
		if ok and loaded then
			return loaded
		end
		if not ok then
			if string.find(tostring(err), "403") or string.find(tostring(err), "API") then
				-- No API access in Studio: run in memory.
				DataService.Persistent = false
				warn("[Data] No DataStore access (enable Studio Access to API Services to test saving).")
				return Schema.Default()
			end
			warn(("[Data] Load attempt %d for %s failed: %s"):format(attempt, player.Name, tostring(err)))
		elseif lockedElsewhere then
			-- The previous server is probably still saving; give it time.
			warn(("[Data] %s's profile is still open on another server; retrying."):format(player.Name))
		end
		if not player.Parent then
			return nil
		end
		task.wait(math.min(2 ^ attempt, 15))
	end
	return nil
end

local function save(player: Player, release: boolean): boolean
	local profile = profiles[player]
	if not profile then
		return true
	end
	if not store or not DataService.Persistent then
		return true
	end
	local key = keyFor(player)
	for attempt = 1, 4 do
		local stolen = false
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(key, function(old: any)
				if type(old) == "table" and type(old.Lock) == "table" and old.Lock.JobId ~= jobId then
					-- Another server took over this profile; never overwrite it.
					stolen = true
					return nil
				end
				return { Data = profile, Lock = if release then nil else { JobId = jobId, Time = os.time() } }
			end)
		end)
		if ok then
			if stolen then
				warn(("[Data] %s's profile was claimed by another server; skipped save."):format(player.Name))
			else
				dirty[player] = nil
			end
			return not stolen
		end
		warn(("[Data] Save attempt %d for %s failed: %s"):format(attempt, player.Name, tostring(err)))
		task.wait(attempt)
	end
	return false
end

-- Public API ------------------------------------------------------------------------

function DataService.Get(player: Player): { [string]: any }?
	return profiles[player]
end

-- Waits for a player's profile (or nil if they leave first).
function DataService.Await(player: Player, timeout: number?): { [string]: any }?
	local deadline = os.clock() + (timeout or 30)
	while player.Parent and not profiles[player] and os.clock() < deadline do
		task.wait(0.1)
	end
	return profiles[player]
end

-- Mark changed and send one top-level section to the owning client.
function DataService.Push(player: Player, section: string)
	local profile = profiles[player]
	if not profile then
		return
	end
	dirty[player] = true
	Net.Push(player, "Profile.Section", section, profile[section])
end

function DataService.MarkDirty(player: Player)
	dirty[player] = true
end

function DataService.SaveNow(player: Player)
	task.spawn(save, player, false)
end

local function onPlayerAdded(player: Player)
	if loading[player] or profiles[player] then
		return
	end
	loading[player] = true
	local profile = load(player)
	loading[player] = nil
	if not player.Parent then
		return
	end
	if not profile then
		player:Kick("Skyline Legends couldn't load your progress safely. Please rejoin in a moment.")
		return
	end
	profile.LastJoin = os.time()
	profiles[player] = profile
	player:SetAttribute("ProfileLoaded", true)
	Net.Push(player, "Profile.Full", profile, DataService.Persistent)
	DataService.Loaded:Fire(player, profile)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	DataService.Releasing:Fire(player, profile)
	save(player, true)
	profiles[player] = nil
	dirty[player] = nil
end

function DataService.Start()
	openStore()
	Net.Handle("Profile.Get", function(player)
		return profiles[player], DataService.Persistent
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Track play time and autosave.
	task.spawn(function()
		local elapsed = 0
		while true do
			task.wait(10)
			elapsed += 10
			for player, profile in profiles do
				profile.PlaySeconds = (profile.PlaySeconds or 0) + 10
				dirty[player] = true
			end
			if elapsed >= AUTOSAVE_INTERVAL then
				elapsed = 0
				for player in profiles do
					if dirty[player] then
						task.spawn(save, player, false)
					end
				end
			end
		end
	end)

	game:BindToClose(function()
		if RunService:IsStudio() and not DataService.Persistent then
			return
		end
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				save(player, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService

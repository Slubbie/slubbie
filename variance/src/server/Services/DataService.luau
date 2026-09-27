-- Player profiles on DataStoreService, with session locking.
--
-- Guarantees
--   * One server owns a profile at a time. The lock (JobId + timestamp) is written
--     with UpdateAsync on load and refreshed on every save. Another server holding a
--     fresh lock makes us wait and retry; a lock older than Config.Data.LockStaleAfter
--     (a crashed server) is taken over. If we ever find our lock was taken by
--     someone else, we stop saving and remove the player, so two servers can
--     never overwrite each other.
--   * Every write is UpdateAsync, retried with exponential backoff.
--   * Loaded data is migrated to the current schema, then sanitized: wrong types,
--     unknown cosmetics, out-of-range numbers and oversized lists are repaired.
--   * If DataStores are down (or Studio has no API access) the player plays in
--     guest mode: nothing is saved, and a background retry adopts their real profile
--     (plus the XP and Marks earned meanwhile) as soon as it can be loaded.
--   * Autosave every Config.Data.AutosaveInterval seconds (staggered), save on leave,
--     and BindToClose saves and releases every profile before shutdown.
--   * The client never writes profile data: every change goes through a server
--     service calling DataService:update().

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Variance.Config)
local Signal = require(ReplicatedStorage.Variance.Util.Signal)
local TableUtil = require(ReplicatedStorage.Variance.Util.TableUtil)
local Cosmetics = require(ReplicatedStorage.Variance.Data.Cosmetics)
local Instruments = require(ReplicatedStorage.Variance.Core.Instruments)
local SettingsSchema = require(ReplicatedStorage.Variance.Data.SettingsSchema)
local Levels = require(ReplicatedStorage.Variance.Data.Levels)
local Achievements = require(ReplicatedStorage.Variance.Data.Achievements)
local Lore = require(ReplicatedStorage.Variance.Data.Lore)
local Rating = require(ReplicatedStorage.Variance.Core.Rating)

local DataService = {}
DataService.Loaded = Signal.new() -- (player, profile)
DataService.Releasing = Signal.new() -- (player, profile)

export type Profile = {
	Player: Player,
	UserId: number,
	Data: { [string]: any },
	Guest: boolean, -- not being saved
	Dirty: boolean,
	LastSave: number,
	Released: boolean,
	LockLost: boolean,
	GuestDelta: { XP: number, Marks: number },
}

local profiles: { [Player]: Profile } = {}
local store: DataStore? = nil
local storeUnavailable = false
local shuttingDown = false

---------------------------------------------------------------------------
-- Schema
---------------------------------------------------------------------------

function DataService.defaults(): { [string]: any }
	local owned, equipped = {}, {}
	for category, id in Cosmetics.Defaults do
		owned[id] = true
		equipped[category] = id
	end
	local instrumentUse = {}
	for _, id in Instruments.ids() do
		instrumentUse[id] = 0
	end
	return {
		Version = Config.Data.SchemaVersion,
		Marks = Config.Economy.StartingMarks,
		XP = 0,
		Level = 1,
		Stats = {
			Matches = 0,
			Wins = 0,
			Losses = 0,
			Streak = 0,
			BestStreak = 0,
			Reads = 0,
			Shots = 0,
			SelfShots = 0,
			SelfSurvived = 0,
			RiskySurvived = 0,
			DamageDealt = 0,
			DamageTaken = 0,
			Healed = 0,
			Instruments = 0,
			ClutchWins = 0,
			TrialsWon = 0,
			PvPMatches = 0,
			PvPWins = 0,
			SoloMatches = 0,
			SoloWins = 0,
			Forfeits = 0,
			EnduranceBest = 0,
			TournamentsWon = 0,
			PlayTime = 0,
			BestRisk = 0,
			SuddenDeathWins = 0,
		},
		EnvironmentWins = {},
		AIWins = { Casual = 0, Standard = 0, Advanced = 0, Expert = 0, Adaptive = 0 },
		SurrogateWins = {},
		InstrumentUse = instrumentUse,
		AdaptiveSkill = 0.35,
		Ranked = {
			Rating = Rating.Start,
			Games = 0,
			SeasonGames = 0,
			Wins = 0,
			Peak = Rating.Start,
			SeasonPeak = Rating.Start,
			Season = Config.Ranked.Season.Id,
			History = {},
			Strikes = 0,
			CleanSinceStrike = 0,
			LockoutUntil = 0,
			Opponents = {},
			SeasonPeaks = {},
		},
		History = {},
		Cosmetics = { Owned = owned, Equipped = equipped },
		Achievements = {},
		Challenges = { Day = 0, Daily = {}, Week = 0, Weekly = {} },
		Lore = { Unlocked = {}, Read = {}, AllRead = false },
		Tutorial = { Basic = false, Seminars = {}, Offered = false },
		Settings = SettingsSchema.defaults(),
		Flags = { ProctorUnlocked = false, WitnessedProctor = false },
		Purchases = {},
		PurchaseOrder = {},
		Meta = { Created = os.time(), LastLogin = os.time(), Sessions = 0 },
	}
end

-- Migrations from older schema versions. Each step upgrades by one version.
local MIGRATIONS = {
	-- v1 -> v2: "Currency.Marks" became top-level "Marks".
	[1] = function(data)
		if type(data.Currency) == "table" and type(data.Currency.Marks) == "number" then
			data.Marks = data.Currency.Marks
		end
		data.Currency = nil
		return data
	end,
	-- v2 -> v3: per-environment win counts and ranked season games were added.
	[2] = function(data)
		data.EnvironmentWins = data.EnvironmentWins or {}
		if type(data.Ranked) == "table" then
			data.Ranked.SeasonGames = data.Ranked.SeasonGames or data.Ranked.Games or 0
			data.Ranked.SeasonPeak = data.Ranked.SeasonPeak or data.Ranked.Rating
		end
		return data
	end,
}

local function migrate(data)
	local version = type(data.Version) == "number" and data.Version or 1
	while version < Config.Data.SchemaVersion do
		local step = MIGRATIONS[version]
		if step then
			local ok, result = pcall(step, data)
			if ok and type(result) == "table" then
				data = result
			else
				warn("[VARIANCE/Data] migration from v" .. version .. " failed: " .. tostring(result))
			end
		end
		version += 1
	end
	data.Version = Config.Data.SchemaVersion
	return data
end

local function clampNumber(value: any, lo: number, hi: number, default: number): number
	if type(value) ~= "number" or value ~= value then
		return default
	end
	return math.clamp(math.floor(value), lo, hi)
end

-- Repairs anything invalid. Never throws; always returns a complete profile.
local function sanitize(data)
	local template = DataService.defaults()
	if type(data) ~= "table" then
		return template
	end
	TableUtil.reconcile(data, template)
	data.Marks = clampNumber(data.Marks, 0, Config.Economy.MaxMarks, template.Marks)
	data.XP = clampNumber(data.XP, 0, 1e9, 0)
	data.Level = Levels.fromXP(data.XP)
	for key, value in data.Stats do
		if type(value) ~= "number" or value ~= value or value < 0 then
			data.Stats[key] = 0
		end
	end
	-- Cosmetics: drop unknown ids, re-own defaults, fix equipped slots.
	for id in data.Cosmetics.Owned do
		if Cosmetics.get(id) == nil then
			data.Cosmetics.Owned[id] = nil
		end
	end
	for category, id in Cosmetics.Defaults do
		data.Cosmetics.Owned[id] = true
		local equipped = data.Cosmetics.Equipped[category]
		local item = equipped and Cosmetics.get(equipped)
		if item == nil or item.Category ~= category or not data.Cosmetics.Owned[equipped] then
			data.Cosmetics.Equipped[category] = id
		end
	end
	for id in data.Achievements do
		if Achievements.get(id) == nil then
			data.Achievements[id] = nil
		end
	end
	for id in data.Lore.Unlocked do
		if Lore.ById[id] == nil then
			data.Lore.Unlocked[id] = nil
		end
	end
	data.Settings = SettingsSchema.cleanAll(data.Settings)
	local ranked = data.Ranked
	ranked.Rating = clampNumber(ranked.Rating, 0, 5000, Rating.Start)
	ranked.Peak = math.max(clampNumber(ranked.Peak, 0, 5000, Rating.Start), ranked.Rating)
	TableUtil.trimFront(ranked.History, Config.Data.RatingHistoryLimit)
	TableUtil.trimFront(data.History, Config.Data.MatchHistoryLimit)
	TableUtil.trimFront(data.PurchaseOrder, Config.Data.PurchaseLogLimit)
	data.AdaptiveSkill = math.clamp(type(data.AdaptiveSkill) == "number" and data.AdaptiveSkill or 0.35, 0, 1)
	-- Prune old ranked opponent records.
	local now = os.time()
	for key, record in ranked.Opponents do
		if type(record) ~= "table" or type(record.Since) ~= "number" or now - record.Since > Config.Ranked.SameOpponentWindow then
			ranked.Opponents[key] = nil
		end
	end
	return data
end
DataService.sanitize = sanitize

---------------------------------------------------------------------------
-- Store access
---------------------------------------------------------------------------

local function keyFor(userId: number): string
	return "u_" .. tostring(userId)
end

local function isPermanentError(err: string): boolean
	-- Studio without API access, or experiences with DataStores disabled.
	return string.find(err, "StudioAccessToApisNotAllowed") ~= nil
		or string.find(err, "403") ~= nil
		or string.find(err, "must publish") ~= nil
		or string.find(err, "not allowed") ~= nil
end

local function budgetWait(requestType: Enum.DataStoreRequestType)
	for _ = 1, 20 do
		local ok, budget = pcall(DataStoreService.GetRequestBudgetForRequestType, DataStoreService, requestType)
		if not ok or budget > 0 then
			return
		end
		task.wait(1)
	end
end

-- Loads (and locks) a profile. Returns (data, guest).
local function loadRecord(userId: number): ({ [string]: any }?, boolean)
	if store == nil or storeUnavailable then
		return nil, true
	end
	local key = keyFor(userId)
	for attempt = 1, Config.Data.LoadAttempts do
		local lockedElsewhere = false
		local loaded = nil
		budgetWait(Enum.DataStoreRequestType.UpdateAsync)
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(key, function(old)
				lockedElsewhere = false
				loaded = nil
				local record = type(old) == "table" and old or {}
				local lock = record.Lock
				local fresh = type(lock) == "table" and type(lock.Time) == "number" and os.time() - lock.Time < Config.Data.LockStaleAfter
				if fresh and lock.JobId ~= game.JobId and attempt < Config.Data.LoadAttempts then
					lockedElsewhere = true
					return nil -- leave it alone and retry
				end
				record.Lock = { JobId = game.JobId, Time = os.time() }
				loaded = record
				return record
			end)
		end)
		if ok and not lockedElsewhere and loaded ~= nil then
			local data = loaded :: any
			data.Lock = nil
			if next(data) == nil then
				return nil, false -- brand new player
			end
			return data, false
		end
		if not ok then
			local message = tostring(err)
			warn(string.format("[VARIANCE/Data] load %d attempt %d failed: %s", userId, attempt, message))
			if isPermanentError(message) then
				storeUnavailable = true
				return nil, true
			end
		end
		task.wait(Config.Data.LoadRetryDelay * attempt)
	end
	return nil, true
end

-- Writes a profile. Returns false if the write failed or our lock was lost.
local function writeRecord(profile: Profile, release: boolean): boolean
	if store == nil or profile.Guest or profile.LockLost then
		return false
	end
	local key = keyFor(profile.UserId)
	local snapshot = TableUtil.deepCopy(profile.Data)
	for attempt = 1, Config.Data.SaveAttempts do
		local lockLost = false
		budgetWait(Enum.DataStoreRequestType.UpdateAsync)
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(key, function(old)
				lockLost = false
				if type(old) == "table" and type(old.Lock) == "table" and old.Lock.JobId ~= game.JobId then
					lockLost = true
					return nil
				end
				local record = snapshot
				record.Lock = if release then nil else { JobId = game.JobId, Time = os.time() }
				return record
			end)
		end)
		if ok then
			if lockLost then
				profile.LockLost = true
				warn(string.format("[VARIANCE/Data] lock for %d was taken by another server; not saving", profile.UserId))
				return false
			end
			profile.LastSave = os.clock()
			profile.Dirty = false
			return true
		end
		warn(string.format("[VARIANCE/Data] save %d attempt %d failed: %s", profile.UserId, attempt, tostring(err)))
		task.wait(2 ^ attempt)
	end
	return false
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function DataService:Init(services)
	self.Services = services
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Data.StoreName)
	end)
	if ok then
		store = result
	else
		warn("[VARIANCE/Data] DataStores unavailable; running in guest mode: " .. tostring(result))
		storeUnavailable = true
	end
end

function DataService:get(player: Player): Profile?
	local profile = profiles[player]
	if profile and not profile.Released then
		return profile
	end
	return nil
end

-- Yields until the player's profile is ready (or timeout / the player left).
function DataService:waitFor(player: Player, timeout: number?): Profile?
	local deadline = os.clock() + (timeout or 30)
	while player.Parent and os.clock() < deadline do
		local profile = self:get(player)
		if profile then
			return profile
		end
		task.wait(0.2)
	end
	return self:get(player)
end

-- Mutates a profile's data. `fn` receives the data table and may return a value.
function DataService:update(player: Player, fn: ({ [string]: any }) -> any): any
	local profile = self:get(player)
	if profile == nil then
		return nil
	end
	local result = fn(profile.Data)
	profile.Dirty = true
	return result
end

-- Tracks earnings while in guest mode so they survive adopting the real profile.
function DataService:noteEarnings(player: Player, xp: number, marks: number)
	local profile = self:get(player)
	if profile and profile.Guest then
		profile.GuestDelta.XP += xp
		profile.GuestDelta.Marks += marks
	end
end

function DataService:save(player: Player): boolean
	local profile = profiles[player]
	if profile == nil or profile.Released then
		return false
	end
	local saved = writeRecord(profile, false)
	if profile.LockLost then
		self:_lockLost(player)
	end
	return saved
end

function DataService:isGuest(player: Player): boolean
	local profile = profiles[player]
	return profile == nil or profile.Guest
end

function DataService:_lockLost(player: Player)
	if player.Parent then
		player:Kick("Your VARIANCE profile was opened on another server. Please rejoin.")
	end
end

local function release(player: Player)
	local profile = profiles[player]
	if profile == nil or profile.Released then
		return
	end
	DataService.Releasing:Fire(player, profile)
	profile.Data.Meta.LastLogin = os.time()
	writeRecord(profile, true)
	profile.Released = true
	profiles[player] = nil
end

local function adoptLater(player: Player, profile: Profile)
	-- Background retries while in guest mode (only if the store might recover).
	task.spawn(function()
		while player.Parent and profile.Guest and not storeUnavailable and not shuttingDown do
			task.wait(60)
			if not player.Parent or storeUnavailable then
				return
			end
			local data, guest = loadRecord(profile.UserId)
			if not guest then
				local adopted = sanitize(migrate(data or DataService.defaults()))
				adopted.XP += profile.GuestDelta.XP
				adopted.Marks = math.min(Config.Economy.MaxMarks, adopted.Marks + profile.GuestDelta.Marks)
				adopted.Level = Levels.fromXP(adopted.XP)
				profile.Data = adopted
				profile.Guest = false
				profile.Dirty = true
				DataService.Loaded:Fire(player, profile)
				local network = DataService.Services.NetworkService
				network:notify(player, "PROFILE RESTORED", "Your saved progress is back. Earnings from this session were added.", "Good")
				return
			end
		end
	end)
end

local function onPlayerAdded(player: Player)
	local data, guest = loadRecord(player.UserId)
	if not player.Parent then
		-- Left while loading: release the lock we may have taken.
		if not guest and data ~= nil then
			local temp = {
				Player = player,
				UserId = player.UserId,
				Data = sanitize(migrate(data)),
				Guest = false,
				Dirty = false,
				LastSave = 0,
				Released = false,
				LockLost = false,
				GuestDelta = { XP = 0, Marks = 0 },
			}
			writeRecord(temp :: any, true)
		end
		return
	end
	local isNew = data == nil
	local prepared = sanitize(migrate(data or DataService.defaults()))
	prepared.Meta.Sessions += 1
	prepared.Meta.LastLogin = os.time()
	local profile: Profile = {
		Player = player,
		UserId = player.UserId,
		Data = prepared,
		Guest = guest,
		Dirty = isNew,
		LastSave = os.clock(),
		Released = false,
		LockLost = false,
		GuestDelta = { XP = 0, Marks = 0 },
	}
	profiles[player] = profile
	player:SetAttribute("VarianceGuest", guest)
	DataService.Loaded:Fire(player, profile)
	if guest then
		local network = DataService.Services.NetworkService
		local reason = storeUnavailable and RunService:IsStudio()
				and "Studio has no DataStore access (Game Settings > Security). Progress won't save."
			or "Saved progress couldn't be loaded. You're playing as a guest; we'll keep retrying."
		task.delay(3, function()
			network:notify(player, "GUEST SESSION", reason, "Warn")
		end)
		adoptLater(player, profile)
	end
end

function DataService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		release(player)
	end)

	-- Staggered autosave.
	task.spawn(function()
		while not shuttingDown do
			task.wait(5)
			for player, profile in profiles do
				if
					not profile.Released
					and not profile.Guest
					and profile.Dirty
					and os.clock() - profile.LastSave >= Config.Data.AutosaveInterval
				then
					task.spawn(function()
						DataService:save(player)
					end)
					task.wait(0.5)
				end
			end
		end
	end)

	game:BindToClose(function()
		shuttingDown = true
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				local ok, err = pcall(release, player)
				if not ok then
					warn("[VARIANCE/Data] release on close failed: " .. tostring(err))
				end
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

-- A unique id for matches / lobbies (not security sensitive).
function DataService.newId(prefix: string): string
	return prefix .. "_" .. string.sub(string.gsub(HttpService:GenerateGUID(false), "-", ""), 1, 12)
end

return DataService

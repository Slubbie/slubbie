-- Player data: loading, saving, session locking, migrations and replication.
--
-- Storage format (one DataStore key per player):
--   { Data = <profile>, Lock = { Job, Time } | nil, Saved = unix, Version = n }
--
-- * Session lock: loading takes the lock with UpdateAsync. If another server
--   holds a fresh lock we wait (it's probably saving on leave) and then take it;
--   a server that lost its lock never overwrites the save.
-- * Every save goes through UpdateAsync, is sanitised (no NaN/inf, only JSON
--   types) and retried with backoff. A backup copy is written every N saves; a
--   corrupt main record falls back to the backup and keeps the corrupt copy.
-- * Profiles carry a schema Version and are migrated step by step on load.
-- * Autosave, save-on-leave and a BindToClose that waits for every save.
-- * Studio without API access (or DataStores unavailable) runs in memory.
--
-- Replication: the owning client gets a full snapshot on load, then batched
-- path patches (Net "Sync") whenever a service calls Data.Changed.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Gameplay = require(Shared.Config.Gameplay)
local Economy = require(Shared.Config.Economy)
local Tutorial = require(Shared.Config.Tutorial)
local Tools = require(Shared.Config.Tools)
local Skills = require(Shared.Config.Skills)
local Land = require(Shared.Config.Land)
local Social = require(Shared.Config.Social)
local Net = require(Shared.Lib.Net)
local Signal = require(Shared.Lib.Signal)
local TableUtil = require(Shared.Lib.TableUtil)
local GameTime = require(Shared.Lib.GameTime)
local ItemUtil = require(Shared.Lib.ItemUtil)

local S = require(script.Parent)

local CFG = Gameplay.Data
local SCHEMA = CFG.SchemaVersion

local DataService = {}
DataService.Loaded = Signal.new() -- (player, profile, info { New, OfflineSeconds, LastGameTime })
DataService.Removing = Signal.new() -- (player, profile) just before the final save
DataService.Saved = Signal.new() -- (player)

type Session = {
	Profile: any,
	ReadOnly: boolean,
	Saves: number,
	LastSave: number,
	Saving: boolean,
	Released: boolean,
	Pending: { [string]: { any } }, -- replication queue path string → path
	LoadedAt: number,
}

local sessions: { [Player]: Session } = {}
local loadingThreads: { [Player]: { thread } } = {}

local mainStore: DataStore? = nil
local backupStore: DataStore? = nil
local memoryMode = false

do
	local ok, err = pcall(function()
		mainStore = DataStoreService:GetDataStore(CFG.StoreName)
		backupStore = DataStoreService:GetDataStore(CFG.BackupStoreName)
	end)
	if not ok then
		memoryMode = true
		warn("[Evergrove] DataStores unavailable, running in memory (progress won't save):", err)
	end
end

local function keyFor(userId: number): string
	return "u_" .. userId
end

-- Default profile ---------------------------------------------------------------------------------

function DataService.CanCapacity(tier: number): number
	for _, family in Tools.Families do
		if family.Id == "can" then
			local def = family.Tiers[math.clamp(tier, 1, #family.Tiers)]
			return def.Capacity or 25
		end
	end
	return 25
end

function DataService.NewProfile(): any
	local now = GameTime.Now()
	local toolTiers = {}
	for _, family in Tools.Families do
		toolTiers[family.Id] = 1
	end
	local skills = {}
	for _, skill in Skills.List do
		skills[skill.Id] = { XP = 0, Nodes = {}, Respecs = 0 }
	end
	local slots = {}
	for i, entry in Tutorial.StarterItems do
		slots[tostring(i)] = ItemUtil.New(entry[1], entry[2])
	end
	local starter = Land.Starter
	return {
		Version = SCHEMA,
		Created = os.time(),
		Coins = Economy.StartingCoins,
		Tokens = 0,
		Energy = Skills.Energy.Base,
		Inventory = { Size = 30, Slots = slots },
		Hotbar = 1,
		Storage = {},
		Silo = { Items = {} },
		Farm = {
			Name = "",
			House = 1,
			Parcels = { [starter.Row .. "_" .. starter.Col] = true },
			Tiles = {},
			Placed = {},
			Animals = {},
			Perm = { Default = Social.Permissions.Default, Players = {} },
			Layouts = {},
			Cleared = {},
			Rules = { Sell = {}, Replant = {}, Priority = {} },
			Bin = {},
			Visitors = 0,
		},
		Tools = toolTiers,
		Water = DataService.CanCapacity(1),
		Powered = {},
		Skills = skills,
		Quests = { Active = {}, Done = {}, Tracked = {}, Daily = { Day = -1, List = {} }, Weekly = { Week = -1, List = {} } },
		Friendship = {},
		Collection = {},
		Claimed = {},
		Museum = {},
		Showcase = {},
		Achievements = {},
		Stats = {},
		Mail = { List = {}, Overflow = {}, Next = 1 },
		Daily = { Last = -1, Index = 0, Streak = 0, Best = 0 },
		Settings = {},
		Cosmetics = { Owned = {}, Equipped = {} },
		Titles = { Newcomer = true },
		Recipes = {},
		Secrets = {},
		Lore = {},
		Travel = { town = true, homestead = true },
		Regions = {},
		Projects = {},
		Unlocks = {},
		Contracts = { Day = -1, Board = {}, Active = {} },
		Exports = {},
		Stall = {},
		Buffs = {},
		Tutorial = { Step = 1, Count = 0, Done = false },
		Guild = {},
		Purchases = {},
		Passes = {},
		Pending = {},
		Offline = { Last = now, LastReal = os.time() },
		PlayTime = 0,
	}
end

-- Migrations: Migrations[v] upgrades a profile from version v to v + 1.
local Migrations: { [number]: (any) -> () } = {
	[1] = function(data)
		-- v1 → v2: shipping bin moved under Farm, tokens added.
		data.Farm = data.Farm or {}
		data.Farm.Bin = data.Bin or data.Farm.Bin or {}
		data.Bin = nil
		data.Tokens = data.Tokens or 0
	end,
	[2] = function(data)
		-- v2 → v3: quest tracking list and cosmetics slots.
		data.Quests = data.Quests or {}
		data.Quests.Tracked = data.Quests.Tracked or {}
		data.Cosmetics = data.Cosmetics or { Owned = {}, Equipped = {} }
	end,
}

local function migrate(data: any): (boolean, string?)
	local version = tonumber(data.Version) or 1
	if version > SCHEMA then
		return false, "This save is from a newer version of the game."
	end
	while version < SCHEMA do
		local step = Migrations[version]
		if step then
			step(data)
		end
		version += 1
		data.Version = version
	end
	return true
end

-- Sanitising -------------------------------------------------------------------------------------------

local function sanitize(value: any, depth: number): any
	local kind = type(value)
	if kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return 0
		end
		return value
	elseif kind == "string" or kind == "boolean" then
		return value
	elseif kind == "table" then
		if depth > 16 then
			return nil
		end
		local out = {}
		for k, v in value do
			local kt = type(k)
			if kt == "string" or (kt == "number" and k == math.floor(k) and k > 0) then
				local clean = sanitize(v, depth + 1)
				if clean ~= nil then
					out[k] = clean
				end
			end
		end
		return out
	end
	return nil
end

-- Store access with retries ---------------------------------------------------------------------------

local function waitForBudget(requestType: Enum.DataStoreRequestType)
	local waited = 0
	while DataStoreService:GetRequestBudgetForRequestType(requestType) < 1 and waited < 10 do
		task.wait(0.5)
		waited += 0.5
	end
end

local function withRetries<T>(label: string, fn: () -> T): (boolean, T | string)
	local lastErr
	for attempt = 1, CFG.Retries do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		warn(string.format("[Evergrove] %s failed (attempt %d): %s", label, attempt, tostring(result)))
		if RunService:IsStudio() and string.find(tostring(result), "API") then
			break
		end
		task.wait(math.min(2 ^ attempt, 12))
	end
	return false, lastErr
end

-- Loading ------------------------------------------------------------------------------------------------

local function validProfile(data: any): boolean
	return type(data) == "table" and type(data.Inventory) == "table" and type(data.Farm) == "table"
end

local function loadBackup(userId: number): any?
	if not backupStore then
		return nil
	end
	local ok, result = withRetries("Backup load " .. userId, function()
		return (backupStore :: DataStore):GetAsync(keyFor(userId))
	end)
	if ok and type(result) == "table" and validProfile(result.Data) then
		return result.Data
	end
	return nil
end

-- Returns (profile | nil, readOnly, message?)
local function loadProfile(player: Player): (any?, boolean, string?)
	if memoryMode or player.UserId <= 0 or not mainStore then
		return nil, memoryMode, nil
	end
	local key = keyFor(player.UserId)
	local jobId = if game.JobId ~= "" then game.JobId else "studio"
	local waited = 0
	local force = false
	while true do
		local lockedBy = nil
		local loadedData = nil
		waitForBudget(Enum.DataStoreRequestType.UpdateAsync)
		local ok, _err = withRetries("Load " .. player.UserId, function()
			return (mainStore :: DataStore):UpdateAsync(key, function(old)
				lockedBy = nil
				if type(old) == "table" and type(old.Lock) == "table" and old.Lock.Job ~= jobId and not force then
					if os.time() - (tonumber(old.Lock.Time) or 0) < CFG.LockTimeout then
						lockedBy = old.Lock.Job
						return nil
					end
				end
				local record = if type(old) == "table" then old else {}
				loadedData = record.Data
				record.Lock = { Job = jobId, Time = os.time() }
				return record
			end)
		end)
		if not ok then
			return nil, true, "We couldn't load your farm. Progress this session won't be saved. Please rejoin later."
		end
		if lockedBy == nil then
			if loadedData == nil then
				return nil, false, nil -- brand new player
			end
			if not validProfile(loadedData) then
				warn("[Evergrove] Corrupt save for", player.UserId, "- trying backup")
				pcall(function()
					(mainStore :: DataStore):SetAsync(key .. "_corrupt_" .. os.time(), { Data = loadedData })
				end)
				local backup = loadBackup(player.UserId)
				if backup then
					return backup, false, "Your farm was restored from a backup."
				end
				return nil, false, "Your save couldn't be read, so a fresh farm was started. Contact support to recover it."
			end
			return loadedData, false, nil
		end
		-- Locked by another server: wait for it to finish its leave-save.
		if waited >= CFG.LockWaitSeconds then
			force = true
		else
			task.wait(3)
			waited += 3
		end
		if not player.Parent then
			return nil, true, nil
		end
	end
end

-- Saving -----------------------------------------------------------------------------------------------------

local function saveSession(player: Player, session: Session, release: boolean): boolean
	if session.ReadOnly or memoryMode or player.UserId <= 0 or not mainStore then
		return true
	end
	if session.Saving then
		-- Wait for the in-flight save, then save again (latest data wins).
		local waited = 0
		while session.Saving and waited < 30 do
			task.wait(0.2)
			waited += 0.2
		end
	end
	session.Saving = true
	local profile = session.Profile
	profile.Offline = { Last = GameTime.Now(), LastReal = os.time() }
	local clean = sanitize(profile, 0)
	local jobId = if game.JobId ~= "" then game.JobId else "studio"
	local size = #HttpService:JSONEncode(clean)
	if size > CFG.SizeWarnBytes then
		warn(string.format("[Evergrove] Profile for %d is large: %d bytes", player.UserId, size))
	end
	local lostLock = false
	waitForBudget(Enum.DataStoreRequestType.UpdateAsync)
	local ok = withRetries("Save " .. player.UserId, function()
		return (mainStore :: DataStore):UpdateAsync(keyFor(player.UserId), function(old)
			if type(old) == "table" and type(old.Lock) == "table" and old.Lock.Job ~= jobId then
				lostLock = true
				return nil
			end
			return {
				Data = clean,
				Lock = if release then nil else { Job = jobId, Time = os.time() },
				Saved = os.time(),
				Version = SCHEMA,
			}
		end)
	end)
	session.Saving = false
	if lostLock then
		warn("[Evergrove] Lost the session lock for", player.UserId, "- this server will stop saving them.")
		session.ReadOnly = true
		return false
	end
	if ok then
		session.Saves += 1
		session.LastSave = os.clock()
		if backupStore and session.Saves % CFG.BackupEvery == 0 then
			task.spawn(function()
				pcall(function()
					(backupStore :: DataStore):SetAsync(keyFor(player.UserId), { Data = clean, Saved = os.time() })
				end)
			end)
		end
		DataService.Saved:Fire(player)
	end
	return ok == true
end

function DataService.SaveNow(player: Player): boolean
	local session = sessions[player]
	if not session then
		return false
	end
	return saveSession(player, session, false)
end

-- Replication -----------------------------------------------------------------------------------------------

-- Keys the owning client mirrors (Farm is filtered: tiles/placed live in the world).
local REPLICATED = {
	Coins = true, Tokens = true, Energy = true, Inventory = true, Hotbar = true, Storage = true, Silo = true,
	Farm = true, Tools = true, Water = true, Powered = true, Skills = true, Quests = true, Friendship = true,
	Collection = true, Claimed = true, Museum = true, Showcase = true, Achievements = true, Stats = true,
	Mail = true, Daily = true, Settings = true, Cosmetics = true, Titles = true, Recipes = true, Secrets = true,
	Lore = true, Travel = true, Regions = true, Projects = true, Unlocks = true, Contracts = true, Exports = true,
	Stall = true, Buffs = true, Tutorial = true, Guild = true, PlayTime = true, Created = true,
}
local FARM_PRIVATE = { Tiles = true, Placed = true }

local function replicatedValue(profile: any, path: { any }): any
	if path[1] == "Farm" then
		if #path == 1 then
			local copy = {}
			for k, v in profile.Farm do
				if not FARM_PRIVATE[k] then
					copy[k] = v
				end
			end
			return copy
		elseif FARM_PRIVATE[path[2]] then
			return nil
		end
	end
	return TableUtil.Get(profile, path)
end

local function snapshot(profile: any): any
	local out = {}
	for key in REPLICATED do
		out[key] = replicatedValue(profile, { key })
	end
	return out
end

-- Mark a path as changed. Patches are batched and sent at most once per frame.
function DataService.Changed(player: Player, ...: any)
	local session = sessions[player]
	if not session then
		return
	end
	local path = { ... }
	if #path == 0 or not REPLICATED[path[1]] then
		return
	end
	if path[1] == "Farm" and path[2] and FARM_PRIVATE[path[2]] then
		return
	end
	local keyParts = table.create(#path)
	for i, part in path do
		keyParts[i] = tostring(part)
	end
	local key = table.concat(keyParts, "\0")
	-- A pending parent path already covers this child.
	for i = #keyParts - 1, 1, -1 do
		if session.Pending[table.concat(keyParts, "\0", 1, i)] then
			return
		end
	end
	session.Pending[key] = path
end

local function flush()
	for player, session in sessions do
		if next(session.Pending) then
			local patches = {}
			for _, path in session.Pending do
				table.insert(patches, { path, replicatedValue(session.Profile, path) })
			end
			table.clear(session.Pending)
			-- Parents before children so the client applies them in a stable order.
			table.sort(patches, function(a, b)
				return #a[1] < #b[1]
			end)
			Net.Fire(player, "Sync", { Patches = patches })
		end
	end
end

-- Public API --------------------------------------------------------------------------------------------------

function DataService.Get(player: Player): any?
	local session = sessions[player]
	return if session then session.Profile else nil
end

function DataService.IsLoaded(player: Player): boolean
	return sessions[player] ~= nil
end

function DataService.IsReadOnly(player: Player): boolean
	local session = sessions[player]
	return session == nil or session.ReadOnly
end

-- Yields until the player's data is loaded (or they leave / timeout).
function DataService.Wait(player: Player, timeout: number?): any?
	local profile = DataService.Get(player)
	if profile then
		return profile
	end
	local thread = coroutine.running()
	loadingThreads[player] = loadingThreads[player] or {}
	table.insert(loadingThreads[player], thread)
	local timer = task.delay(timeout or 30, function()
		task.spawn(thread, nil)
	end)
	local result = coroutine.yield()
	task.cancel(timer)
	return result
end

function DataService.All(): { [Player]: any }
	local out = {}
	for player, session in sessions do
		out[player] = session.Profile
	end
	return out
end

-- Increment a stat (and let achievements know).
function DataService.AddStat(player: Player, name: string, amount: number?)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	profile.Stats[name] = (profile.Stats[name] or 0) + (amount or 1)
	DataService.Changed(player, "Stats", name)
	S.Achievement.OnStat(player, name, profile.Stats[name])
end

-- Keep the best value of a stat.
function DataService.MaxStat(player: Player, name: string, value: number)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	if value > (profile.Stats[name] or 0) then
		profile.Stats[name] = value
		DataService.Changed(player, "Stats", name)
		S.Achievement.OnStat(player, name, value)
	end
end

-- Lifecycle ---------------------------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	local data, readOnly, message = loadProfile(player)
	if not player.Parent then
		return
	end
	local isNew = data == nil
	local profile = data or DataService.NewProfile()
	if not isNew then
		local ok, err = migrate(profile)
		if not ok then
			readOnly = true
			message = err
		end
		TableUtil.Reconcile(profile, DataService.NewProfile())
	end
	local lastGameTime = (profile.Offline and profile.Offline.Last) or GameTime.Now()
	local lastReal = (profile.Offline and profile.Offline.LastReal) or os.time()
	local session: Session = {
		Profile = profile,
		ReadOnly = readOnly,
		Saves = 0,
		LastSave = os.clock(),
		Saving = false,
		Released = false,
		Pending = {},
		LoadedAt = os.clock(),
	}
	sessions[player] = session
	player:SetAttribute("DataLoaded", true)

	Net.Fire(player, "Sync", { Full = snapshot(profile), ReadOnly = readOnly })
	if message then
		S.Notify.Toast(player, message, "Warning")
	end

	DataService.Loaded:Fire(player, profile, {
		New = isNew,
		OfflineSeconds = math.max(0, os.time() - lastReal),
		LastGameTime = lastGameTime,
	})

	for _, thread in pairs(loadingThreads[player] or {}) do
		task.spawn(thread, profile)
	end
	loadingThreads[player] = nil
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	for _, thread in pairs(loadingThreads[player] or {}) do
		task.spawn(thread, nil)
	end
	loadingThreads[player] = nil
	if not session or session.Released then
		return
	end
	session.Released = true
	local ok, err = pcall(function()
		DataService.Removing:Fire(player, session.Profile)
	end)
	if not ok then
		warn("[Evergrove] Removing handlers failed:", err)
	end
	saveSession(player, session, true)
	sessions[player] = nil
end

function DataService.Init()
	Net.Handle("SaveSettings", function(player, settings)
		local profile = DataService.Get(player)
		if not profile then
			return
		end
		profile.Settings = S.Player.CleanSettings(settings)
		DataService.Changed(player, "Settings")
	end)
end

function DataService.Start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	RunService.Heartbeat:Connect(flush)

	-- Autosave with jitter so players don't all save at once.
	task.spawn(function()
		while true do
			task.wait(10)
			for player, session in sessions do
				if os.clock() - session.LastSave > CFG.AutosaveSeconds + (player.UserId % 30) then
					task.spawn(saveSession, player, session, false)
				end
			end
		end
	end)

	-- Play time
	task.spawn(function()
		while true do
			task.wait(60)
			for player, session in sessions do
				session.Profile.PlayTime = (session.Profile.PlayTime or 0) + 60
				DataService.Changed(player, "PlayTime")
			end
		end
	end)

	game:BindToClose(function()
		local remaining = 0
		for player, session in sessions do
			if not session.Released then
				remaining += 1
				task.spawn(function()
					session.Released = true
					pcall(function()
						DataService.Removing:Fire(player, session.Profile)
					end)
					saveSession(player, session, true)
					remaining -= 1
				end)
			end
		end
		local waited = 0
		while remaining > 0 and waited < 26 do
			task.wait(0.25)
			waited += 0.25
		end
	end)
end

return DataService

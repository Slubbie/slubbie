-- The saved profile: defaults, versioned migrations and integrity repair.
--
-- Every load runs Prepare(): migrate → reconcile (fill missing fields) →
-- sanitize (fix impossible values). Repairs are reported so they can be
-- logged. Unknown creature species are kept untouched (never delete player
-- data because content changed); they simply earn nothing until restored.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreatureDefinitions = require(Shared.CreatureDefinitions)
local EconomyMath = require(Shared.EconomyMath)
local GameConfig = require(Shared.GameConfig)
local ProfileTypes = require(Shared.ProfileTypes)
local QuestDefinitions = require(Shared.QuestDefinitions)
local RarityConfig = require(Shared.RarityConfig)
local RemoteDefinitions = require(Shared.RemoteDefinitions)
local UpgradeDefinitions = require(Shared.UpgradeDefinitions)

export type Profile = ProfileTypes.Profile

local ProfileSchema = {}

ProfileSchema.CurrentVersion = 1

-- Migrations[n] upgrades a profile from SchemaVersion n to n + 1, in place.
-- Add one whenever the saved shape changes; never edit a shipped migration.
ProfileSchema.Migrations = {} :: { [number]: (data: { [string]: any }) -> () }

function ProfileSchema.DefaultSettings(): ProfileTypes.Settings
	return {
		MusicVolume = 0.7,
		EffectsVolume = 0.8,
		AmbientVolume = 0.6,
		ReducedMotion = false,
		EasyCapture = false,
		AutoOpenCores = true,
		GraphicsQuality = "Auto",
	}
end

function ProfileSchema.Default(now: number): Profile
	return {
		SchemaVersion = ProfileSchema.CurrentVersion,
		Stardust = 0,
		MeteorShards = 0,
		Level = 1,
		XP = 0,
		TutorialStage = 0,
		UnlockedBiomes = { DawnCommons = true },
		Equipment = { ScannerLevel = 1, TetherLevel = 1, HabitatLevel = 1 },
		Creatures = {},
		NextCreatureSerial = 1,
		Cores = {},
		NextCoreSerial = 1,
		EquippedCreatures = {},
		DiscoveredSpecies = {},
		QuestProgress = {
			Onboarding = { Progress = 0 },
			Missions = { Index = 1, Progress = 0, Complete = false },
		},
		Achievements = {},
		SanctuaryDecorations = {},
		AscensionCount = 0,
		Settings = ProfileSchema.DefaultSettings(),
		Stats = {},
		LastSeenTimestamp = 0,
		CreatedAt = now,
		IncomeRemainder = 0,
		ProcessedReceipts = {},
	}
end

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value :: any do
		out[deepCopy(k)] = deepCopy(v)
	end
	return out :: any
end
ProfileSchema.DeepCopy = deepCopy

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function wholeNumber(value: any, min: number, max: number?): number
	if not isFiniteNumber(value) then
		return min
	end
	local n = math.floor(value)
	if n < min then
		return min
	end
	if max and n > max then
		return max
	end
	return n
end

-- Base36 helpers for compact, unique IDs.
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

function ProfileSchema.ToBase36(n: number): string
	n = math.floor(math.abs(n))
	if n == 0 then
		return "0"
	end
	local out = {}
	while n > 0 do
		local d = n % 36
		table.insert(out, 1, DIGITS:sub(d + 1, d + 1))
		n = n // 36
	end
	return table.concat(out)
end

function ProfileSchema.FromBase36(text: string): number?
	if type(text) ~= "string" or #text == 0 or #text > 12 then
		return nil
	end
	local n = 0
	for i = 1, #text do
		local d = DIGITS:find(text:sub(i, i), 1, true)
		if not d then
			return nil
		end
		n = n * 36 + (d - 1)
	end
	return n
end

function ProfileSchema.CreatureId(userId: number, serial: number): string
	return ProfileSchema.ToBase36(userId) .. "-" .. ProfileSchema.ToBase36(serial)
end

function ProfileSchema.CoreId(serial: number): string
	return "k" .. ProfileSchema.ToBase36(serial)
end

-- Migrate ------------------------------------------------------------------

-- Returns "ok", or "TooNew" when the data was written by a newer game
-- version (this server must not touch it), or "Failed".
function ProfileSchema.Migrate(data: { [string]: any }): (string, string?)
	local version = data.SchemaVersion
	if not isFiniteNumber(version) then
		version = 0
	end
	if version > ProfileSchema.CurrentVersion then
		return "TooNew", `profile schema {version} is newer than this server ({ProfileSchema.CurrentVersion})`
	end
	while version < ProfileSchema.CurrentVersion do
		local step = ProfileSchema.Migrations[version]
		if step then
			local ok, err = pcall(step, data)
			if not ok then
				return "Failed", `migration from v{version} failed: {err}`
			end
		end
		version += 1
		data.SchemaVersion = version
	end
	return "ok", nil
end

-- Reconcile: add any field the template has that the data lacks ----------------

local function reconcile(data: { [string]: any }, template: { [string]: any }, path: string, fixes: { string })
	for key, default in template do
		local current = data[key]
		if current == nil or type(current) ~= type(default) then
			data[key] = deepCopy(default)
			if current ~= nil then
				table.insert(fixes, `{path}{key}: wrong type, reset`)
			end
		elseif type(default) == "table" and next(default) ~= nil then
			-- Only recurse into structured defaults; open dictionaries ({} defaults) are kept as-is.
			reconcile(current, default, `{path}{key}.`, fixes)
		end
	end
end

-- Sanitize: repair values that would break invariants ---------------------------

local function sanitizeSettings(settings: { [string]: any }, fixes: { string })
	local defaults = ProfileSchema.DefaultSettings() :: any
	for key, value in settings do
		local spec = RemoteDefinitions.SettingsSchema[key]
		local valid = false
		if spec then
			if spec.Type == "number" then
				valid = isFiniteNumber(value) and value >= (spec.Min or -math.huge) and value <= (spec.Max or math.huge)
			elseif spec.Type == "boolean" then
				valid = type(value) == "boolean"
			elseif spec.Type == "enum" then
				valid = type(value) == "string" and spec.Values ~= nil and table.find(spec.Values, value) ~= nil
			end
		end
		if not valid then
			settings[key] = defaults[key]
			table.insert(fixes, `Settings.{key}: invalid, reset`)
		end
	end
end

local function sanitizeCreature(id: string, record: any, userId: number?, fixes: { string }): boolean
	if type(record) ~= "table" or type(id) ~= "string" then
		return false
	end
	if record.Id ~= id then
		record.Id = id
		table.insert(fixes, `Creature {id}: Id field repaired`)
	end
	if type(record.Species) ~= "string" then
		return false
	end
	if not CreatureDefinitions.IsSpecies(record.Species) then
		-- Keep the record; it may belong to content that is temporarily disabled.
		table.insert(fixes, `Creature {id}: unknown species '{record.Species}' kept`)
	end
	if not RarityConfig.IsMutation(record.Mutation) then
		record.Mutation = "Standard"
		table.insert(fixes, `Creature {id}: invalid mutation reset`)
	end
	record.Bond = wholeNumber(record.Bond, 1, GameConfig.Creatures.MaxBond)
	record.Obtained = wholeNumber(record.Obtained, 0)
	record.Locked = record.Locked == true
	record.Favorite = record.Favorite == true
	if type(record.Origin) ~= "string" then
		record.Origin = "Capture"
	end
	if type(record.Biome) ~= "string" then
		record.Biome = "DawnCommons"
	end
	return true
end

local function serialOf(id: string): number?
	local serialText = id:match("%-([0-9a-z]+)$") or id:match("^k([0-9a-z]+)$")
	return if serialText then ProfileSchema.FromBase36(serialText) else nil
end

function ProfileSchema.Sanitize(data: Profile, userId: number?): { string }
	local fixes: { string } = {}
	local d = data :: any

	d.Stardust = wholeNumber(d.Stardust, 0)
	d.MeteorShards = wholeNumber(d.MeteorShards, 0)
	d.AscensionCount = wholeNumber(d.AscensionCount, 0)
	d.IncomeRemainder = if isFiniteNumber(d.IncomeRemainder) then math.clamp(d.IncomeRemainder, 0, 1) else 0
	d.LastSeenTimestamp = wholeNumber(d.LastSeenTimestamp, 0)

	-- Level and XP must be consistent.
	local cap = GameConfig.Progression.LevelCap
	local level = wholeNumber(d.Level, 1, cap)
	local xp = wholeNumber(d.XP, 0)
	if level ~= d.Level then
		table.insert(fixes, "Level out of range")
	end
	if level >= cap then
		xp = 0
	elseif xp >= EconomyMath.XPToNext(level) then
		xp = EconomyMath.XPToNext(level) - 1
		table.insert(fixes, "XP exceeded the level threshold")
	end
	d.Level, d.XP = level, xp

	d.TutorialStage = wholeNumber(d.TutorialStage, 0, #QuestDefinitions.Onboarding)
	d.UnlockedBiomes.DawnCommons = true
	for biomeId, unlocked in d.UnlockedBiomes do
		if unlocked ~= true then
			d.UnlockedBiomes[biomeId] = nil
		end
	end

	for _, trackId in UpgradeDefinitions.Order do
		local track = UpgradeDefinitions.Tracks[trackId]
		local key = track.ProfileKey
		local value = wholeNumber(d.Equipment[key], 1, #track.Levels)
		if value ~= d.Equipment[key] then
			table.insert(fixes, `Equipment.{key} out of range`)
		end
		d.Equipment[key] = value
	end

	-- Creatures: drop unusable records, track the highest serial so new IDs stay unique.
	local highestSerial = 0
	for id, record in d.Creatures do
		if not sanitizeCreature(id, record, userId, fixes) then
			d.Creatures[id] = nil
			table.insert(fixes, `Creature {tostring(id)}: unreadable record removed`)
		else
			highestSerial = math.max(highestSerial, serialOf(id) or 0)
		end
	end
	d.NextCreatureSerial = math.max(wholeNumber(d.NextCreatureSerial, 1), highestSerial + 1)

	local highestCore = 0
	for id, core in d.Cores do
		if type(core) ~= "table" or type(id) ~= "string" or type(core.Biome) ~= "string" then
			d.Cores[id] = nil
			table.insert(fixes, `Core {tostring(id)}: unreadable record removed`)
		else
			core.Id = id
			core.Kind = if core.Kind == "Starter" then "Starter" else "Normal"
			core.Quality = if isFiniteNumber(core.Quality) then math.clamp(core.Quality, 0, 1) else 0
			core.CometType = if type(core.CometType) == "string" then core.CometType else "Ember"
			core.Obtained = wholeNumber(core.Obtained, 0)
			highestCore = math.max(highestCore, serialOf(id) or 0)
		end
	end
	d.NextCoreSerial = math.max(wholeNumber(d.NextCoreSerial, 1), highestCore + 1)

	-- Habitats: valid slot keys, owned and known creatures, each creature in at most one slot.
	local unlocked = UpgradeDefinitions.HabitatSlots(d.Equipment.HabitatLevel)
	local used = {}
	for slotKey, creatureId in d.EquippedCreatures do
		local slot = tonumber(slotKey)
		local creature = type(creatureId) == "string" and d.Creatures[creatureId]
		local valid = slot ~= nil
			and slot == math.floor(slot)
			and slot >= 1
			and slot <= unlocked
			and tostring(slot) == slotKey
			and creature
			and CreatureDefinitions.IsSpecies(creature.Species)
			and not used[creatureId]
		if valid then
			used[creatureId] = true
		else
			d.EquippedCreatures[slotKey] = nil
			table.insert(fixes, `Habitat slot {tostring(slotKey)}: invalid assignment cleared`)
		end
	end

	-- Every owned species counts as discovered.
	for id, discovery in d.DiscoveredSpecies do
		if type(discovery) ~= "table" or not CreatureDefinitions.IsSpecies(id) then
			if type(discovery) ~= "table" then
				d.DiscoveredSpecies[id] = nil
			end
		else
			discovery.First = wholeNumber(discovery.First, 0)
			discovery.Count = wholeNumber(discovery.Count, 0)
			if type(discovery.Mutations) ~= "table" then
				discovery.Mutations = {}
			end
		end
	end
	for _, creature in d.Creatures do
		if CreatureDefinitions.IsSpecies(creature.Species) and not d.DiscoveredSpecies[creature.Species] then
			d.DiscoveredSpecies[creature.Species] = {
				First = creature.Obtained,
				Count = 1,
				Mutations = { [creature.Mutation] = true },
			}
			table.insert(fixes, `Discovery for {creature.Species} restored`)
		end
	end

	local missions = d.QuestProgress.Missions
	missions.Index = wholeNumber(missions.Index, 1, #QuestDefinitions.Missions + 1)
	missions.Progress = wholeNumber(missions.Progress, 0)
	missions.Complete = missions.Complete == true
	d.QuestProgress.Onboarding.Progress = wholeNumber(d.QuestProgress.Onboarding.Progress, 0)

	for key, value in d.Stats do
		if not isFiniteNumber(value) then
			d.Stats[key] = nil
		end
	end

	sanitizeSettings(d.Settings, fixes)
	return fixes
end

-- Prepare: everything a fresh load needs ----------------------------------------

-- Returns (profile, status, fixes). status: "New" | "Loaded" | "TooNew" | "Failed".
function ProfileSchema.Prepare(raw: any, now: number, userId: number?): (Profile?, string, { string })
	if raw == nil then
		return ProfileSchema.Default(now), "New", {}
	end
	if type(raw) ~= "table" then
		return nil, "Failed", { "saved data is not a table" }
	end
	local data = raw :: { [string]: any }
	local result, message = ProfileSchema.Migrate(data)
	if result ~= "ok" then
		return nil, result, { message or result }
	end
	local fixes = {}
	reconcile(data, ProfileSchema.Default(now) :: any, "", fixes)
	local sanitizeFixes = ProfileSchema.Sanitize(data :: any, userId)
	table.move(sanitizeFixes, 1, #sanitizeFixes, #fixes + 1, fixes)
	return data :: any, "Loaded", fixes
end

-- What the client is allowed to see of its own profile.
local PRIVATE_FIELDS = { ProcessedReceipts = true, IncomeRemainder = true }

function ProfileSchema.ClientView(data: Profile): { [string]: any }
	local view = {}
	for key, value in data :: any do
		if not PRIVATE_FIELDS[key] then
			view[key] = deepCopy(value)
		end
	end
	return view
end

function ProfileSchema.IsPrivateField(key: string): boolean
	return PRIVATE_FIELDS[key] == true
end

return ProfileSchema

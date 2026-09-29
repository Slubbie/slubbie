-- Core gameplay tuning that doesn't belong to a single content module:
-- saving, offline progress, performance budgets, security and debug access.

return {
	Data = {
		StoreName = "Evergrove_Players_v1",
		BackupStoreName = "Evergrove_Backups_v1",
		SchemaVersion = 3,
		AutosaveSeconds = 150,
		-- Session lock: a lock older than this (seconds) is considered stale and can be taken.
		LockTimeout = 1800,
		-- How long to wait for another server to release the lock before taking it.
		LockWaitSeconds = 12,
		-- Keep a backup copy every N successful saves.
		BackupEvery = 6,
		-- Warn in the log when a profile gets this large (DataStore limit is 4 MB).
		SizeWarnBytes = 2500000,
		Retries = 4,
	},

	Offline = {
		-- Offline progress is capped at this many real seconds.
		Cap = 12 * 3600,
		-- Efficiency of offline progress per system (1 = same as online).
		Crops = 1,
		Machines = 1,
		Animals = 0.75,
		Automation = 0.8,
		-- Show a "While you were away" summary when offline longer than this.
		SummaryAfter = 300,
	},

	Performance = {
		-- Crops advanced per server Heartbeat (the scheduler walks all crops round-robin).
		-- Machines and animals need no budget: they settle lazily from timestamps.
		CropsPerStep = 180,
		-- Target seconds between visual updates of the same crop.
		CropRefresh = 4,
	},

	Energy = {
		-- With no energy left heavy actions are blocked; light ones still work.
		-- (Harvesting and planting cost no energy at all.)
		Enabled = true,
		LightActions = { Water = false, Net = true },
	},

	Security = {
		-- Violations within this window before an automatic kick (0 = never kick).
		KickThreshold = 60,
		Window = 60,
		LogToOutput = true,
		-- Max studs a character can move per second before actions are rejected (teleport check).
		MaxSpeed = 140,
	},

	Debug = {
		-- UserIds allowed to use the admin panel in live servers. Studio always allows it.
		Admins = {},
		-- Group admins: { GroupId = n, MinRank = n }
		Group = nil,
		Hotkey = "F8",
	},
}

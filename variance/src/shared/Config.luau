-- Runtime configuration for VARIANCE. Game rules live in Core/Modes and
-- Core/Instruments; this file holds everything operational: saving,
-- networking limits, matchmaking, ranked seasons, spectating, monetization
-- ids and developer tools.
--
-- BEFORE PUBLISHING: set Config.Debug.Enabled = false (or leave it on and keep
-- Config.Debug.Admins to your own UserIds; Studio-only access is always safe).

local Config = {}

Config.Version = "1.0.0"
Config.GameName = "VARIANCE"

---------------------------------------------------------------------------
-- Persistence
---------------------------------------------------------------------------
Config.Data = {
	StoreName = "VarianceProfiles_v1",
	SchemaVersion = 3,
	AutosaveInterval = 120, -- seconds between autosaves per player (staggered)
	LockStaleAfter = 1800, -- a session lock older than this is considered abandoned
	LoadAttempts = 6,
	LoadRetryDelay = 3,
	SaveAttempts = 4,
	MatchHistoryLimit = 15,
	RatingHistoryLimit = 30,
	PurchaseLogLimit = 60,
	LeaderboardRefresh = 120,
	Leaderboards = {
		Standing = "VarianceStanding_S1",
		Wins = "VarianceWins_v1",
	},
	MemoryStoreMap = "VarianceSessions", -- cross-server lobby codes and active matches
}

---------------------------------------------------------------------------
-- Networking and anti-exploit
---------------------------------------------------------------------------
Config.Net = {
	-- Token buckets: Rate tokens per second, up to Burst.
	Buckets = {
		Act = { Rate = 5, Burst = 8 },
		Request = { Rate = 6, Burst = 14 },
		Look = { Rate = 12, Burst = 20 },
	},
	-- Per-endpoint overrides (requests are also counted against Request).
	EndpointBuckets = {
		["Settings.Save"] = { Rate = 0.5, Burst = 3 },
		["Lobby.SetRules"] = { Rate = 1, Burst = 4 },
		["Match.Sync"] = { Rate = 0.5, Burst = 3 },
		["Match.Emote"] = { Rate = 0.4, Burst = 2 },
		["Leaderboard.Get"] = { Rate = 0.2, Burst = 2 },
		["Cosmetics.Buy"] = { Rate = 0.5, Burst = 3 },
		["Debug.Command"] = { Rate = 4, Burst = 10 },
	},
	-- Suspicion scoring: each flag adds points that decay over time.
	FlagDecayPerSecond = 0.5,
	KickThreshold = 150,
	LogThreshold = 20,
}

---------------------------------------------------------------------------
-- Matches
---------------------------------------------------------------------------
Config.Match = {
	MaxArenas = 20,
	ArenaOrigin = { 3000, 0, 0 }, -- first arena slot (studs); far from the lobby
	ArenaSpacing = 800,
	ReconnectGrace = 45, -- seconds a disconnected subject's seat is held
	AfkTimeoutsToForfeit = 2, -- consecutive turn timeouts before an AFK forfeit (PvP)
	RematchWindow = 15,
	PostMatchLinger = 30, -- seconds on the summary screen before returning to the lobby
	AIThinkTimeout = 10, -- hard cap on AI decision time (fallback action after)
	DisconnectPause = true, -- pause the turn timer while the acting subject is reconnecting
	AmbientEventInterval = { 22, 55 },
	RareEventChance = 0.03,
	ProctorEventChance = 0.006,
	HesitationSeconds = 16,
}

---------------------------------------------------------------------------
-- Matchmaking (in-server; see docs/ARCHITECTURE.md for cross-server notes)
---------------------------------------------------------------------------
Config.Matchmaking = {
	TickInterval = 1,
	Queues = {
		Duel = { Mode = "Standard", Name = "STANDARD", Size = 2, MinSize = 2, BotAfter = 45 },
		Ranked = { Mode = "Ranked", Name = "RANKED", Size = 2, MinSize = 2, Ranked = true },
		Rapid = { Mode = "Rapid", Name = "RAPID", Size = 2, MinSize = 2, BotAfter = 45 },
		Chaos = { Mode = "Chaos", Name = "CHAOS", Size = 2, MinSize = 2, BotAfter = 45 },
		Precision = { Mode = "Precision", Name = "PRECISION", Size = 2, MinSize = 2, BotAfter = 45 },
		Crossfire = { Mode = "Crossfire", Name = "CROSSFIRE", Size = 4, MinSize = 3, FillWait = 25, BotAfter = 60 },
	},
	BotDifficulty = "Standard",
}

---------------------------------------------------------------------------
-- Ranked
---------------------------------------------------------------------------
Config.Ranked = {
	Season = {
		Id = "S1",
		Name = "SEASON ONE: INTAKE",
		Starts = 1788220800, -- 2026-09-01 UTC
		Ends = 1796083200, -- 2026-12-01 UTC
	},
	SameOpponentLimit = 3, -- rated matches against one opponent per window
	SameOpponentWindow = 24 * 3600,
	StrikeDecayMatches = 3, -- clean ranked matches that remove one abandon strike
	MinMatchSeconds = 45, -- shorter matches (e.g. instant forfeits) don't move the winner's rating
	LockoutMessage = "Ranked queue locked for leaving an active match.",
}

---------------------------------------------------------------------------
-- Private lobbies, parties and tournaments
---------------------------------------------------------------------------
Config.Lobby = {
	MaxMembers = 8,
	CodeLength = 6,
	CodeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789",
	CodeTTL = 6 * 3600,
	IdleTimeout = 45 * 60,
	MaxBots = 3,
}

Config.Tournament = {
	MinPlayers = 3,
	MaxPlayers = 8,
	BetweenRounds = 12,
	Mode = "Standard",
}

---------------------------------------------------------------------------
-- Spectating
---------------------------------------------------------------------------
Config.Spectate = {
	CompetitiveDelay = 6, -- seconds of delay for ranked / tournament spectators
	MaxPerMatch = 12,
	MuteSpectatorsInCompetitive = true, -- spectator chat never reaches the players
}

---------------------------------------------------------------------------
-- Endurance
---------------------------------------------------------------------------
Config.Endurance = {
	Stages = {
		{ Personality = "Ledger", Difficulty = "Standard" },
		{ Personality = "Volta", Difficulty = "Standard" },
		{ Personality = "Magpie", Difficulty = "Advanced" },
		{ Personality = "Kismet", Difficulty = "Advanced" },
		{ Personality = "Proctor", Difficulty = "Expert" },
	},
	RecoveryBetweenStages = 2, -- Integrity restored between stages
	CarryInstruments = true,
}

---------------------------------------------------------------------------
-- Economy
---------------------------------------------------------------------------
Config.Economy = {
	StartingMarks = 150,
	MaxMarks = 10000000,
	PrivateLobbyXPScale = 0.8, -- custom rules earn a little less than public play
	RepeatOpponentDecay = 0.25, -- XP multiplier lost per repeated private opponent within a day
}

---------------------------------------------------------------------------
-- Monetization (cosmetic only). Set real ids from the Creator Dashboard;
-- entries with Id = 0 are hidden from the shop.
---------------------------------------------------------------------------
Config.Monetization = {
	Products = {
		{
			Id = 0,
			Key = "Founder",
			Name = "FOUNDER'S BUNDLE",
			Description = "Walnut Arbiter finish and a Founder banner. Cosmetic only.",
			Grants = { "skin_founder" },
		},
		{
			Id = 0,
			Key = "Marks500",
			Name = "500 MARKS",
			Description = "Cosmetic currency. Buys nothing that affects a Trial.",
			Marks = 500,
		},
	},
	Passes = {
		{
			Id = 0,
			Key = "Supporter",
			Name = "SUPPORTER",
			Description = "A gold nameplate and our thanks. Cosmetic only.",
			Grants = { "plate_gold" },
		},
	},
}

---------------------------------------------------------------------------
-- Developer tools
---------------------------------------------------------------------------
Config.Debug = {
	Enabled = true, -- master switch
	AllowInStudio = true, -- anyone testing in Studio gets the panel
	Admins = {}, -- UserIds allowed in live servers, e.g. { 12345678 }
	LogRemoteRejections = true,
}

return Config

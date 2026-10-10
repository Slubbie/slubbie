--!strict
-- Catch a Comet! — systems tuning.
--
-- Content lives in the *Definitions modules (creatures, biomes, upgrades,
-- quests) and odds live in RarityConfig. This file holds the numbers that
-- drive the systems themselves. Every value here is a starting balance point,
-- not a final answer: adjust after playtests.

local GameConfig = {}

GameConfig.Version = "0.1.0-phase1"

-- Must match Game Settings → Places → Max Players. One sanctuary plot per player.
GameConfig.MaxPlayers = 12

-- Feature flags. A disabled feature is never shown as a working button.
GameConfig.Features = {
	-- Direct trading stays off until its transaction + recovery design (see
	-- docs/ROADMAP.md) is implemented and tested. The inventory already uses
	-- globally unique creature IDs so it can be added safely.
	Trading = false,
	-- No developer product / game pass IDs are configured yet.
	Purchases = false,
	-- Phase 3+ systems. The architecture has room for them; they are not built.
	WorldEvents = false,
	Expeditions = false,
	Bonding = false,
	Ascension = false,
}

GameConfig.Data = {
	StoreName = "CatchAComet_Profiles_v1",
	KeyPrefix = "Player_",
	AutosaveInterval = 60,
	-- A session lock with no heartbeat for this long is treated as abandoned
	-- (crashed server). Autosaves refresh the heartbeat.
	LockStaleSeconds = 300,
	-- If another server still holds the lock (usually because it is saving the
	-- player on leave) we wait and retry this many times before giving up.
	LoadLockRetries = 8,
	LoadLockRetryDelay = 4,
	-- Retries for transient DataStore errors, with exponential backoff.
	MaxRequestRetries = 5,
	RetryBaseDelay = 1,
	-- Debounce for the extra save requested after high-value moments
	-- (rare creatures, upgrades).
	PrioritySaveDelay = 4,
	ShutdownTimeout = 25,
	-- In a live server, a profile that can't be loaded kicks the player with an
	-- explanation instead of letting them play on a blank profile.
	-- In Studio without API access the game runs in session-only mode instead.
	AllowSessionOnlyInStudio = true,
}

GameConfig.Character = {
	WalkSpeed = 20,
	RespawnDelay = 2,
	-- Falling below this height returns you to safe ground; you never lose anything.
	VoidY = -70,
}

GameConfig.Inventory = {
	MaxCreatures = 300,
	MaxCores = 40,
}

-- Comet visual types. Types change size, look, capture difficulty and the
-- immediate Stardust/XP payout. They never change creature or mutation odds.
export type CometType = {
	Id: string,
	DisplayName: string,
	Weight: number,
	Size: number,
	Color: Color3,
	TrailColor: Color3,
	StardustMult: number,
	XPMult: number,
	SpeedMult: number,
	ZoneMult: number,
}

local cometTypes: { [string]: CometType } = {
	Spark = {
		Id = "Spark",
		DisplayName = "Spark",
		Weight = 45,
		Size = 0.8,
		Color = Color3.fromRGB(255, 236, 170),
		TrailColor = Color3.fromRGB(255, 196, 120),
		StardustMult = 0.8,
		XPMult = 0.9,
		SpeedMult = 0.92,
		ZoneMult = 1.05,
	},
	Ember = {
		Id = "Ember",
		DisplayName = "Ember",
		Weight = 31,
		Size = 1,
		Color = Color3.fromRGB(255, 160, 110),
		TrailColor = Color3.fromRGB(255, 110, 90),
		StardustMult = 1,
		XPMult = 1,
		SpeedMult = 1,
		ZoneMult = 1,
	},
	Glacier = {
		Id = "Glacier",
		DisplayName = "Glacier",
		Weight = 16,
		Size = 1.15,
		Color = Color3.fromRGB(150, 235, 255),
		TrailColor = Color3.fromRGB(116, 229, 254),
		StardustMult = 1.3,
		XPMult = 1.15,
		SpeedMult = 1.08,
		ZoneMult = 0.93,
	},
	Nova = {
		Id = "Nova",
		DisplayName = "Nova",
		Weight = 8,
		Size = 1.45,
		Color = Color3.fromRGB(214, 190, 255),
		TrailColor = Color3.fromRGB(182, 156, 255),
		StardustMult = 1.8,
		XPMult = 1.4,
		SpeedMult = 1.16,
		ZoneMult = 0.86,
	},
	-- Only used for the onboarding comet.
	Starter = {
		Id = "Starter",
		DisplayName = "Guiding",
		Weight = 0,
		Size = 1.2,
		Color = Color3.fromRGB(255, 220, 140),
		TrailColor = Color3.fromRGB(255, 207, 112),
		StardustMult = 1,
		XPMult = 1,
		SpeedMult = 1,
		ZoneMult = 1,
	},
}

GameConfig.Comets = {
	-- Seconds between comets in each active biome (random within the range).
	SpawnIntervalMin = 20,
	SpawnIntervalMax = 35,
	-- The first comet in a fresh server comes quickly.
	FirstSpawnDelay = 6,
	-- How long a landed comet stays capturable.
	Lifetime = 90,
	-- Seconds from appearing in the sky to impact.
	FallDuration = 4.5,
	TutorialFallDuration = 3.5,
	MaxPerBiome = 5,
	MaxTotal = 14,
	-- Minimum studs between two active comets.
	MinSpacing = 45,
	-- A location isn't reused until this many seconds after its last comet.
	LocationCooldown = 60,
	-- Players must be this close to start stabilizing (plus leeway for lag).
	CaptureDistance = 16,
	DistanceLeeway = 8,
	TypeOrder = { "Spark", "Ember", "Glacier", "Nova" },
	Types = cometTypes,
}

-- The capture minigame. All timing math lives in CaptureMath, shared by the
-- client (to draw and predict) and the server (to validate and score).
GameConfig.Capture = {
	-- Stage 1 (Energy Lock): an indicator circles the dial; press inside the zone.
	DialPeriod = 1.9, -- seconds per revolution
	ZoneHalfWidth = 30, -- degrees either side of the zone centre
	-- Stage 2 (Stabilize): hold to charge, release while the level is in the band.
	ChargeTime = 1.5, -- seconds of holding to reach full charge
	OverchargeTime = 2.1, -- holding longer than this always misses
	BandHalfWidth = 0.13, -- fraction of the meter
	BandDrift = 0.18, -- how far the band wanders up/down
	BandPeriod = 2.6,
	-- Score inside a zone falls from 1.0 (dead centre) to this value at the edge.
	EdgeScore = 0.55,
	MissesAllowed = 3, -- a 4th miss fails the attempt
	MissPenalty = 0.05, -- quality lost per miss
	MissPause = 0.7, -- seconds of feedback before a stage restarts
	IntroTime = 0.6, -- before the dial starts
	TransitionTime = 0.55, -- between stages
	MinReaction = 0.12, -- presses faster than this after a stage starts are rejected
	StageTimeout = 9,
	FailCooldown = 2.5, -- after a failed attempt, before you can retry the same comet
	-- Easy Capture (accessibility setting): wider, slower zones. Perfect rank is
	-- not available in this mode — the setting says so.
	EasyZoneMult = 1.9,
	EasySpeedMult = 0.72,
	EasyBandMult = 1.8,
	EasyQualityCap = 0.899,
	-- The onboarding comet is extra forgiving and can't fail.
	TutorialZoneMult = 2.2,
	TutorialSpeedMult = 0.7,
	TutorialBandMult = 2,
	-- Network tolerance: reported press times may lag the server by up to
	-- clamp(ping * PingFactor + Base, Base, Max) seconds.
	LatencyBase = 0.25,
	LatencyPingFactor = 1.5,
	LatencyMax = 1,
	FutureTolerance = 0.08,
}

export type QualityRank = {
	Id: string,
	Min: number,
	StardustMult: number,
	XPMult: number,
	Color: Color3,
}

-- Capture quality ranks. Quality changes Stardust, XP and (later) event
-- contribution. It never changes creature rarity.
GameConfig.QualityRanks = {
	{ Id = "Bronze", Min = 0, StardustMult = 1, XPMult = 1, Color = Color3.fromRGB(222, 156, 110) },
	{ Id = "Silver", Min = 0.55, StardustMult = 1.25, XPMult = 1.1, Color = Color3.fromRGB(205, 216, 236) },
	{ Id = "Gold", Min = 0.75, StardustMult = 1.5, XPMult = 1.2, Color = Color3.fromRGB(255, 207, 112) },
	{ Id = "Perfect", Min = 0.9, StardustMult = 2, XPMult = 1.35, Color = Color3.fromRGB(116, 229, 254) },
} :: { QualityRank }

GameConfig.Income = {
	TickInterval = 1,
	-- Offline earnings: a share of the sanctuary rate, capped per absence.
	OfflineRate = 0.25,
	OfflineMaxSeconds = 2 * 60 * 60,
	-- Absences shorter than this don't count (quick rejoins).
	OfflineMinSeconds = 5 * 60,
	-- Optional hard cap on a single offline award (math.huge = no cap).
	OfflineMaxAward = math.huge,
}

-- Stardust Wisps: faint motes only a scanner can see. They make exploring
-- between comets worthwhile and give the scanner a real job.
GameConfig.Wisps = {
	-- Per player: a collected wisp comes back for you after this long.
	RespawnSeconds = 150,
	PickupRadius = 7,
	PickupLeeway = 5,
	-- Scanner level 5 pulls wisps in from this far.
	MagnetRadius = 22,
}

GameConfig.Progression = {
	LevelCap = 50,
	-- XP to next level = floor(Base + Scale * (level - 1) ^ Exponent)
	XPBase = 100,
	XPScale = 45,
	XPExponent = 1.3,
	-- Base XP for an ordinary capture (scaled by biome, comet type and rank).
	CaptureXP = 45,
	-- Stardust awarded on reaching a level: LevelUpStardust * newLevel.
	LevelUpStardust = 40,
}

GameConfig.Creatures = {
	-- Releasing a creature returns this many seconds of its base production.
	ReleaseValueSeconds = 45,
	-- Bond levels (Phase 4 adds the bonding action; the income formula already uses it).
	MaxBond = 5,
	BondBonusPerLevel = 0.1,
}

GameConfig.Tutorial = {
	StarterSpecies = "Pebblepuff",
	-- Delay after the character first spawns before the guiding comet falls.
	CometDelay = 2.5,
	-- Stardust gift on deploying the first creature (enough for the first scanner upgrade).
	WelcomeGift = 250,
	-- Being this close to the guiding comet completes "follow the trail".
	ReachDistance = 26,
}

GameConfig.Travel = {
	Cooldown = 4,
}

-- Sounds. Only Roblox's built-in client sounds are used so nothing depends on
-- assets that may be moderated or private. Swap any entry for a Creator Store
-- ID ("rbxassetid://...") to upgrade it; pitch and volume still apply.
GameConfig.Audio = {
	Sounds = {
		UIClick = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.25, Pitch = 2.2 },
		UIOpen = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.22, Pitch = 1.6 },
		UIClose = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.18, Pitch = 1.25 },
		UIError = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.3, Pitch = 0.6 },
		Purchase = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.4, Pitch = 1.5 },
		CometFall = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.6, Pitch = 0.45 },
		CometImpact = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 1, Pitch = 0.35 },
		CometHum = { Id = "rbxasset://sounds/action_falling.mp3", Volume = 0.25, Pitch = 2.4 },
		DialTick = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.12, Pitch = 3 },
		LockHit = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.45, Pitch = 1.8 },
		Miss = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.35, Pitch = 0.5 },
		Charge = { Id = "rbxasset://sounds/action_falling.mp3", Volume = 0.25, Pitch = 1.2 },
		Contain = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.5, Pitch = 0.8 },
		Chime = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.3, Pitch = 1 },
		Wisp = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.22, Pitch = 2.6 },
		Portal = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.5, Pitch = 0.7 },
		Wind = { Id = "rbxasset://sounds/action_falling.mp3", Volume = 0.12, Pitch = 0.55 },
		Splash = { Id = "rbxasset://sounds/impact_water.mp3", Volume = 0.3, Pitch = 1.4 },
	},
	-- Optional music tracks per area, e.g. { Id = "rbxassetid://123", Volume = 0.5 }.
	-- Empty = the built-in generative chime ambience.
	Music = {
		Hub = {},
		DawnCommons = {},
	},
}

-- Client graphics presets. "Auto" follows the player's Roblox graphics level.
GameConfig.Graphics = {
	Presets = {
		Low = {
			Particles = 0.3,
			CreatureAnimDistance = 70,
			CreatureDetailDistance = 0,
			PostProcessing = false,
			Decorations = 0.5,
		},
		Medium = {
			Particles = 0.65,
			CreatureAnimDistance = 130,
			CreatureDetailDistance = 45,
			PostProcessing = true,
			Decorations = 0.8,
		},
		High = {
			Particles = 1,
			CreatureAnimDistance = 200,
			CreatureDetailDistance = 90,
			PostProcessing = true,
			Decorations = 1,
		},
	},
}

return GameConfig

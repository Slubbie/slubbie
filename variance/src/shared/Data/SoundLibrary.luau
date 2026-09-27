-- Every sound in VARIANCE is a recipe: an asset, a playback speed (pitch),
-- volume, mixer group, optional randomisation and a Fallback recipe.
--
-- Out of the box everything is built from sounds that ship with every Roblox
-- client (rbxasset://sounds/...), shaped with pitch and effects, so the game is
-- fully audible with zero uploads. To use real sound design, replace an Id
-- with your own "rbxassetid://..." (the Fallback still protects you if an
-- asset is missing, moderated or fails to load).
--
-- Groups: Effects, Ambience, Music, Voice, Interface (all under Master).

local SoundLibrary = {}

local PING = "rbxasset://sounds/electronicpingshort.wav"
local THUMP = "rbxasset://sounds/action_jump_land.mp3"
local HOP = "rbxasset://sounds/action_jump.mp3"
local SWOOSH = "rbxasset://sounds/swoosh.wav"
local WIND = "rbxasset://sounds/action_falling.mp3"
local STEPS = "rbxasset://sounds/action_footsteps_plastic.mp3"
local CLICK = "rbxasset://sounds/clickfast.wav"
local SWITCH = "rbxasset://sounds/switch.wav"
local SNAP = "rbxasset://sounds/snap.mp3"
local BUTTON = "rbxasset://sounds/button.wav"
local ROCKET = "rbxasset://sounds/Rocket shot.wav"
local SWIM = "rbxasset://sounds/action_swim.mp3"
local GLASS = "rbxasset://sounds/glassbreak.wav"

export type Recipe = {
	Id: string,
	Pitch: number?,
	PitchVar: number?,
	Volume: number?,
	Group: string?,
	Looped: boolean?,
	Fallback: string?,
	Rolloff: number?, -- max distance for positional sounds
	Reverb: boolean?,
	LowPass: number?, -- 0..1 amount of high-frequency cut
	Distort: number?,
	Echo: number?,
}

SoundLibrary.Recipes = {
	-- Base fallbacks (known to ship with every client).
	BasePing = { Id = PING, Volume = 0.3, Group = "Effects" },
	BaseThump = { Id = THUMP, Volume = 0.5, Group = "Effects" },
	BaseSwoosh = { Id = SWOOSH, Volume = 0.4, Group = "Effects" },

	-- Interface
	Hover = { Id = PING, Pitch = 2.4, Volume = 0.04, Group = "Interface", PitchVar = 0.04 },
	Click = { Id = CLICK, Pitch = 1.1, Volume = 0.35, Group = "Interface", Fallback = "UiClickAlt" },
	UiClickAlt = { Id = BUTTON, Pitch = 1.2, Volume = 0.3, Group = "Interface", Fallback = "Tick" },
	Tick = { Id = PING, Pitch = 3.2, Volume = 0.06, Group = "Interface" },
	Tab = { Id = SWITCH, Pitch = 1.6, Volume = 0.2, Group = "Interface", Fallback = "Tick" },
	Deny = { Id = THUMP, Pitch = 1.9, Volume = 0.25, Group = "Interface" },
	Confirm = { Id = PING, Pitch = 1.4, Volume = 0.14, Group = "Interface" },
	Open = { Id = SWOOSH, Pitch = 1.7, Volume = 0.12, Group = "Interface" },
	Close = { Id = SWOOSH, Pitch = 1.25, Volume = 0.1, Group = "Interface" },
	Toast = { Id = PING, Pitch = 1.9, Volume = 0.1, Group = "Interface" },
	Unlock = { Id = PING, Pitch = 1.1, Volume = 0.2, Group = "Interface", Echo = 0.3 },
	TimerTick = { Id = CLICK, Pitch = 1.9, Volume = 0.12, Group = "Interface", Fallback = "Tick" },
	TimerUrgent = { Id = PING, Pitch = 1.2, Volume = 0.16, Group = "Interface" },

	-- The Arbiter
	CellShow = {
		Id = CLICK,
		Pitch = 0.95,
		Volume = 0.28,
		PitchVar = 0.08,
		Group = "Effects",
		Fallback = "BaseThump",
		Rolloff = 40,
	},
	CellInsert = {
		Id = SWITCH,
		Pitch = 0.75,
		Volume = 0.4,
		PitchVar = 0.06,
		Group = "Effects",
		Fallback = "BaseThump",
		Rolloff = 40,
	},
	BoltBack = { Id = SWITCH, Pitch = 0.62, Volume = 0.55, Group = "Effects", Fallback = "BaseThump", Rolloff = 45 },
	BoltForward = { Id = SWITCH, Pitch = 0.85, Volume = 0.55, Group = "Effects", Fallback = "BaseThump", Rolloff = 45 },
	Pickup = { Id = HOP, Pitch = 0.62, Volume = 0.22, Group = "Effects", Fallback = "BaseSwoosh", Rolloff = 35 },
	SetDown = { Id = THUMP, Pitch = 1.25, Volume = 0.45, Group = "Effects", Rolloff = 40 },
	Aim = { Id = SWOOSH, Pitch = 0.7, Volume = 0.14, Group = "Effects", Rolloff = 30 },
	CoilWhine = {
		Id = PING,
		Pitch = 0.42,
		Volume = 0.12,
		Group = "Effects",
		Looped = true,
		Rolloff = 30,
		Reverb = true,
	},
	HollowClick = { Id = CLICK, Pitch = 0.58, Volume = 0.75, Group = "Effects", Fallback = "HollowAlt", Rolloff = 60 },
	HollowAlt = { Id = SWITCH, Pitch = 0.5, Volume = 0.7, Group = "Effects", Fallback = "BaseThump", Rolloff = 60 },
	HollowHiss = { Id = SWOOSH, Pitch = 0.5, Volume = 0.2, Group = "Effects", Rolloff = 40 },
	Discharge = {
		Id = ROCKET,
		Pitch = 0.72,
		Volume = 0.95,
		Group = "Effects",
		Fallback = "DischargeAlt",
		Rolloff = 120,
		Distort = 0.4,
		Reverb = true,
	},
	DischargeAlt = {
		Id = THUMP,
		Pitch = 0.42,
		Volume = 1,
		Group = "Effects",
		Distort = 0.6,
		Rolloff = 120,
		Reverb = true,
	},
	Crack = { Id = SNAP, Pitch = 0.8, Volume = 0.9, Group = "Effects", Fallback = "BaseThump", Rolloff = 120 },
	Zap = { Id = PING, Pitch = 0.3, Volume = 0.5, Group = "Effects", Distort = 0.8, Rolloff = 80 },
	Eject = { Id = SWITCH, Pitch = 1.3, Volume = 0.4, Group = "Effects", Fallback = "BaseThump", Rolloff = 40 },
	Tink = { Id = PING, Pitch = 4.2, Volume = 0.12, PitchVar = 0.15, Group = "Effects", Rolloff = 30 },
	Surge = { Id = PING, Pitch = 0.22, Volume = 0.4, Group = "Effects", Distort = 0.5, Rolloff = 80 },

	-- Bodies
	Flinch = { Id = THUMP, Pitch = 0.85, Volume = 0.6, Group = "Effects", Rolloff = 50 },
	Relief = { Id = SWOOSH, Pitch = 0.42, Volume = 0.18, Group = "Effects", Rolloff = 25 },
	Heartbeat = { Id = THUMP, Pitch = 0.5, Volume = 0.5, Group = "Effects", LowPass = 0.7 },
	Breath = { Id = SWOOSH, Pitch = 0.38, Volume = 0.1, Group = "Effects", LowPass = 0.4 },
	Slump = { Id = THUMP, Pitch = 0.62, Volume = 0.55, Group = "Effects", Rolloff = 50 },
	Knock = { Id = THUMP, Pitch = 1.6, Volume = 0.4, Group = "Effects", Rolloff = 35 },

	-- Instruments
	Lens = { Id = PING, Pitch = 2.6, Volume = 0.2, Group = "Effects", Rolloff = 30 },
	Ejector = { Id = SWITCH, Pitch = 1.05, Volume = 0.5, Group = "Effects", Fallback = "BaseThump", Rolloff = 40 },
	Suture = { Id = PING, Pitch = 1.8, Volume = 0.18, Group = "Effects", Echo = 0.2, Rolloff = 30 },
	Capacitor = { Id = PING, Pitch = 0.5, Volume = 0.35, Group = "Effects", Distort = 0.3, Rolloff = 40 },
	Clamp = { Id = SWITCH, Pitch = 0.55, Volume = 0.7, Group = "Effects", Fallback = "BaseThump", Rolloff = 45 },
	Inverter = { Id = SWOOSH, Pitch = 1.9, Volume = 0.25, Group = "Effects", Echo = 0.3, Rolloff = 35 },
	Sonar = { Id = PING, Pitch = 1.15, Volume = 0.3, Group = "Effects", Echo = 0.6, Reverb = true, Rolloff = 60 },
	Dampener = { Id = SWOOSH, Pitch = 0.8, Volume = 0.25, Group = "Effects", Reverb = true, Rolloff = 35 },
	Rotor = { Id = STEPS, Pitch = 2.2, Volume = 0.3, Group = "Effects", Rolloff = 35 },
	Overclock = { Id = PING, Pitch = 1.6, Volume = 0.3, Group = "Effects", Distort = 0.4, Rolloff = 35 },
	SerumGood = { Id = PING, Pitch = 1.5, Volume = 0.25, Group = "Effects", Echo = 0.4, Rolloff = 35 },
	SerumBad = { Id = THUMP, Pitch = 0.7, Volume = 0.5, Group = "Effects", Distort = 0.5, Rolloff = 35 },
	Drink = { Id = SWIM, Pitch = 2.2, Volume = 0.2, Group = "Effects", Fallback = "BaseSwoosh", Rolloff = 25 },
	PowerTap = { Id = PING, Pitch = 0.35, Volume = 0.35, Group = "Effects", Distort = 0.6, Rolloff = 40 },
	Tether = { Id = PING, Pitch = 0.6, Volume = 0.35, Group = "Effects", Reverb = true, Echo = 0.5, Rolloff = 60 },
	Scrambler = { Id = STEPS, Pitch = 3.2, Volume = 0.35, Group = "Effects", Distort = 0.5, Rolloff = 45 },
	Deal = {
		Id = CLICK,
		Pitch = 1.35,
		Volume = 0.22,
		PitchVar = 0.1,
		Group = "Effects",
		Fallback = "BaseThump",
		Rolloff = 35,
	},
	Lost = { Id = GLASS, Pitch = 1.4, Volume = 0.2, Group = "Effects", Fallback = "Deny", Rolloff = 35 },

	-- Room and announcer
	Hum = { Id = WIND, Pitch = 0.3, Volume = 0.22, Group = "Ambience", Looped = true, LowPass = 0.85 },
	RoomTone = { Id = WIND, Pitch = 0.55, Volume = 0.08, Group = "Ambience", Looped = true, LowPass = 0.6 },
	Machinery = { Id = STEPS, Pitch = 0.32, Volume = 0.14, Group = "Ambience", Looped = true, LowPass = 0.7 },
	Rain = {
		Id = SWIM,
		Pitch = 0.55,
		Volume = 0.16,
		Group = "Ambience",
		Looped = true,
		Fallback = "RoomTone",
		LowPass = 0.3,
	},
	Servers = { Id = WIND, Pitch = 1.6, Volume = 0.05, Group = "Ambience", Looped = true, LowPass = 0.5 },
	Crowd = { Id = WIND, Pitch = 0.8, Volume = 0.05, Group = "Ambience", Looped = true, LowPass = 0.8 },
	Creak = {
		Id = SWITCH,
		Pitch = 0.3,
		Volume = 0.2,
		PitchVar = 0.08,
		Group = "Ambience",
		Reverb = true,
		Fallback = "BaseThump",
		Rolloff = 90,
	},
	DistantThud = {
		Id = THUMP,
		Pitch = 0.35,
		Volume = 0.3,
		Group = "Ambience",
		Reverb = true,
		LowPass = 0.8,
		Rolloff = 150,
	},
	Vent = { Id = WIND, Pitch = 1.1, Volume = 0.25, Group = "Ambience", LowPass = 0.4, Rolloff = 70 },
	PowerDown = { Id = PING, Pitch = 0.28, Volume = 0.4, Group = "Ambience", Distort = 0.4, Rolloff = 150 },
	Alarm = { Id = PING, Pitch = 0.9, Volume = 0.3, Group = "Ambience", Distort = 0.2, Rolloff = 120 },
	Chime = { Id = PING, Pitch = 1.0, Volume = 0.28, Group = "Voice", Reverb = true },
	ChimeLow = { Id = PING, Pitch = 0.75, Volume = 0.28, Group = "Voice", Reverb = true },
	Blip = { Id = PING, Pitch = 1, Volume = 0.08, PitchVar = 0.08, Group = "Voice" },
	Buzz = { Id = PING, Pitch = 1, Volume = 0.07, PitchVar = 0.12, Group = "Voice", Distort = 0.5 },
	Chirp = { Id = PING, Pitch = 1, Volume = 0.07, PitchVar = 0.2, Group = "Voice" },
	Drone = { Id = PING, Pitch = 1, Volume = 0.09, PitchVar = 0.03, Group = "Voice", Reverb = true },
	Stinger = { Id = PING, Pitch = 0.5, Volume = 0.35, Group = "Music", Reverb = true, Echo = 0.4 },
	WinSting = { Id = PING, Pitch = 1.26, Volume = 0.3, Group = "Music", Reverb = true },
	LoseSting = { Id = PING, Pitch = 0.67, Volume = 0.3, Group = "Music", Reverb = true },
}

-- Optional licensed music. Leave Id empty to use the generative score.
SoundLibrary.Music = {
	Lobby = { Id = "", Volume = 0.35 },
	Low = { Id = "", Volume = 0.35 },
	Mid = { Id = "", Volume = 0.35 },
	High = { Id = "", Volume = 0.4 },
}

-- Environment beds: which loops play in each room.
SoundLibrary.Beds = {
	Lobby = { "RoomTone", "Hum" },
	Vent = { "Hum", "Machinery" },
	Studio = { "Hum", "Crowd" },
	Servers = { "Hum", "Servers" },
	Rain = { "Hum", "Rain" },
	Casino = { "Hum", "Crowd" },
	Office = { "Hum", "Servers" },
}

function SoundLibrary.get(name: string): Recipe?
	return SoundLibrary.Recipes[name]
end

return SoundLibrary

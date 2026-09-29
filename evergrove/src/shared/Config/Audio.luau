-- Audio hooks.
--
-- Every sound the game plays is named here. Out of the box they use Roblox's
-- built-in engine sounds (always available), shaped with pitch/volume, so the
-- game is never silent. To use proper recordings, replace an Id with an asset
-- from the Creator Store (Toolbox → Audio), e.g. "rbxassetid://1234567890".
--
-- Fields: Id, Volume, Pitch (or {min,max} random), Group (Master bus: SFX/UI/Ambient/Weather/Music),
--         Caption (subtitle text), Loop, Rolloff (3D max distance).

local BUILTIN = {
	Ping = "rbxasset://sounds/electronicpingshort.wav",
	Swoosh = "rbxasset://sounds/swoosh.wav",
	Jump = "rbxasset://sounds/action_jump.mp3",
	Land = "rbxasset://sounds/action_jump_land.mp3",
	Wind = "rbxasset://sounds/action_falling.mp3",
	Steps = "rbxasset://sounds/action_footsteps_plastic.mp3",
	Splash = "rbxasset://sounds/impact_water.mp3",
	Swim = "rbxasset://sounds/action_swim.mp3",
	Click = "rbxasset://sounds/clickfast.wav",
	Button = "rbxasset://sounds/button.wav",
}

export type Sound = {
	Id: string,
	Volume: number,
	Pitch: any,
	Group: string,
	Caption: string?,
	Loop: boolean?,
	Rolloff: number?,
}

local function s(
	id: string,
	volume: number,
	pitch: any,
	group: string,
	caption: string?,
	extra: { [string]: any }?
): Sound
	local def: any = { Id = id, Volume = volume, Pitch = pitch, Group = group, Caption = caption }
	for k, v in pairs(extra or {}) do
		def[k] = v
	end
	return def
end

local Sounds: { [string]: Sound } = {
	-- Interface
	UIClick = s(BUILTIN.Click, 0.35, { 1.1, 1.2 }, "UI"),
	UIHover = s(BUILTIN.Click, 0.12, 1.6, "UI"),
	UIOpen = s(BUILTIN.Swoosh, 0.25, 1.4, "UI"),
	UIClose = s(BUILTIN.Swoosh, 0.2, 1.1, "UI"),
	UIError = s(BUILTIN.Button, 0.35, 0.6, "UI"),
	UIConfirm = s(BUILTIN.Ping, 0.3, 1.5, "UI"),
	Coins = s(BUILTIN.Ping, 0.35, { 1.8, 2.1 }, "UI", "[Coins jingle]"),
	ItemPickup = s(BUILTIN.Ping, 0.25, { 1.3, 1.6 }, "UI"),
	QuestComplete = s(BUILTIN.Ping, 0.5, 1.2, "UI", "[Quest complete fanfare]"),
	LevelUp = s(BUILTIN.Ping, 0.55, 1, "UI", "[Level up chime]"),
	Discovery = s(BUILTIN.Ping, 0.45, 0.8, "UI", "[New discovery]"),
	LegendaryReveal = s(BUILTIN.Ping, 0.65, 0.5, "UI", "[Legendary reveal]"),
	Notification = s(BUILTIN.Ping, 0.2, 1.7, "UI"),
	Mail = s(BUILTIN.Swoosh, 0.3, 1.8, "UI", "[Mail arrives]"),

	-- Farming actions (3D, at the target)
	Till = s(BUILTIN.Land, 0.5, { 0.55, 0.7 }, "SFX", nil, { Rolloff = 60 }),
	Plant = s(BUILTIN.Steps, 0.35, { 1.4, 1.7 }, "SFX", nil, { Rolloff = 50 }),
	Water = s(BUILTIN.Swim, 0.45, { 1.2, 1.4 }, "SFX", "[Watering]", { Rolloff = 50 }),
	Fertilize = s(BUILTIN.Swoosh, 0.3, { 0.7, 0.8 }, "SFX", nil, { Rolloff = 50 }),
	Harvest = s(BUILTIN.Swoosh, 0.45, { 1.2, 1.45 }, "SFX", nil, { Rolloff = 60 }),
	HarvestPop = s(BUILTIN.Ping, 0.25, { 1.6, 2.2 }, "SFX", nil, { Rolloff = 50 }),
	HarvestRare = s(BUILTIN.Ping, 0.5, 1.1, "SFX", "[Rare harvest]", { Rolloff = 80 }),
	Chop = s(BUILTIN.Land, 0.6, { 0.9, 1.05 }, "SFX", "[Chopping]", { Rolloff = 80 }),
	TreeFall = s(BUILTIN.Land, 0.9, 0.4, "SFX", "[Tree falls]", { Rolloff = 120 }),
	Mine = s(BUILTIN.Land, 0.6, { 1.4, 1.6 }, "SFX", "[Pickaxe clink]", { Rolloff = 80 }),
	RockBreak = s(BUILTIN.Land, 0.8, 0.7, "SFX", nil, { Rolloff = 100 }),
	Dig = s(BUILTIN.Land, 0.5, { 0.5, 0.6 }, "SFX", nil, { Rolloff = 60 }),
	NetSwing = s(BUILTIN.Swoosh, 0.4, { 1.3, 1.5 }, "SFX", nil, { Rolloff = 50 }),
	Cast = s(BUILTIN.Swoosh, 0.5, 0.8, "SFX", "[Line cast]", { Rolloff = 60 }),
	Bobber = s(BUILTIN.Splash, 0.35, 1.5, "SFX", nil, { Rolloff = 60 }),
	Bite = s(BUILTIN.Splash, 0.6, 1.1, "SFX", "[Fish bites!]", { Rolloff = 60 }),
	Reel = s(BUILTIN.Click, 0.25, 0.8, "SFX", nil, { Rolloff = 40 }),
	FishCaught = s(BUILTIN.Splash, 0.6, 0.9, "SFX", "[Splash]", { Rolloff = 60 }),
	Place = s(BUILTIN.Land, 0.45, 0.9, "SFX", nil, { Rolloff = 60 }),
	Remove = s(BUILTIN.Swoosh, 0.35, 0.7, "SFX", nil, { Rolloff = 60 }),
	MachineStart = s(BUILTIN.Button, 0.35, 0.8, "SFX", "[Machine whirs]", { Rolloff = 50 }),
	MachineDone = s(BUILTIN.Ping, 0.35, 1.3, "SFX", "[Machine ding]", { Rolloff = 60 }),
	MachineLoop = s(BUILTIN.Wind, 0.12, 2.2, "SFX", nil, { Loop = true, Rolloff = 40 }),
	Eat = s(BUILTIN.Click, 0.4, 0.7, "SFX", "[Munching]"),
	Pet = s(BUILTIN.Ping, 0.25, 2.4, "SFX", nil, { Rolloff = 40 }),
	Footstep = s(BUILTIN.Steps, 0.3, 1, "SFX", nil, { Rolloff = 40 }),

	-- Animals (procedural "voices" from pitched sounds)
	Cluck = s(BUILTIN.Click, 0.3, 2.6, "SFX", "[Cluck]", { Rolloff = 60 }),
	Quack = s(BUILTIN.Button, 0.3, 1.8, "SFX", "[Quack]", { Rolloff = 60 }),
	Squeak = s(BUILTIN.Ping, 0.15, 3, "SFX", nil, { Rolloff = 40 }),
	Moo = s(BUILTIN.Wind, 0.45, 0.35, "SFX", "[Moo]", { Rolloff = 90 }),
	Bleat = s(BUILTIN.Wind, 0.35, 0.7, "SFX", "[Bleat]", { Rolloff = 70 }),
	Oink = s(BUILTIN.Button, 0.35, 0.5, "SFX", "[Oink]", { Rolloff = 70 }),
	Baa = s(BUILTIN.Wind, 0.35, 0.8, "SFX", "[Baa]", { Rolloff = 70 }),
	Hum = s(BUILTIN.Wind, 0.25, 0.9, "SFX", nil, { Rolloff = 50 }),
	Neigh = s(BUILTIN.Wind, 0.45, 1.2, "SFX", "[Neigh]", { Rolloff = 90 }),
	Buzz = s(BUILTIN.Wind, 0.15, 3.5, "SFX", nil, { Rolloff = 30 }),
	Flutter = s(BUILTIN.Swoosh, 0.15, 2.5, "SFX", nil, { Rolloff = 30 }),
	Chime = s(BUILTIN.Ping, 0.2, 2.8, "SFX", nil, { Rolloff = 40 }),

	-- Weather & ambience loops (2D, crossfaded)
	Rain = s(BUILTIN.Swim, 0.5, 0.55, "Weather", "[Rain]", { Loop = true }),
	Storm = s(BUILTIN.Wind, 0.7, 0.45, "Weather", "[Storm winds]", { Loop = true }),
	Thunder = s(BUILTIN.Land, 1, 0.22, "Weather", "[Thunder]"),
	Hail = s(BUILTIN.Click, 0.25, 0.9, "Weather", "[Hail]", { Loop = true }),
	Snow = s(BUILTIN.Wind, 0.25, 0.4, "Weather", nil, { Loop = true }),
	Breeze = s(BUILTIN.Wind, 0.3, 0.6, "Ambient", nil, { Loop = true }),
	WindLoop = s(BUILTIN.Wind, 0.55, 0.8, "Weather", "[Wind]", { Loop = true }),
	River = s(BUILTIN.Swim, 0.35, 0.8, "Ambient", nil, { Loop = true }),
	Waves = s(BUILTIN.Swim, 0.5, 0.45, "Ambient", "[Waves]", { Loop = true }),
	Cave = s(BUILTIN.Wind, 0.25, 0.3, "Ambient", nil, { Loop = true }),
	Arcane = s(BUILTIN.Wind, 0.4, 1.6, "Weather", nil, { Loop = true }),
}

return {
	Builtin = BUILTIN,
	Sounds = Sounds,
	-- Procedural ambience "voices" (birds, insects, frogs...) are synthesised by the
	-- client AudioController from these pitched tones.
	Voices = {
		Bird = { Id = BUILTIN.Ping, Pitch = { 2.6, 3.4 }, Volume = 0.05, Glide = 0.25 },
		Insect = { Id = BUILTIN.Click, Pitch = { 3, 3.6 }, Volume = 0.03 },
		Frog = { Id = BUILTIN.Button, Pitch = { 0.5, 0.7 }, Volume = 0.08 },
		Owl = { Id = BUILTIN.Wind, Pitch = { 0.9, 1 }, Volume = 0.08 },
		Gull = { Id = BUILTIN.Ping, Pitch = { 1.9, 2.2 }, Volume = 0.05, Glide = -0.6 },
		Chimes = { Id = BUILTIN.Ping, Pitch = { 2, 3 }, Volume = 0.04 },
		Drip = { Id = BUILTIN.Splash, Pitch = { 2.4, 3 }, Volume = 0.06 },
		Chatter = { Id = BUILTIN.Button, Pitch = { 1.2, 1.6 }, Volume = 0.015 },
		Livestock = { Id = BUILTIN.Wind, Pitch = { 0.35, 0.8 }, Volume = 0.05 },
	},
	-- Adaptive soundtrack. Leave Tracks empty to use the generative score; or map a
	-- mood/season to Creator Store music ids to use real tracks.
	Music = {
		Tone = BUILTIN.Ping,
		Kick = BUILTIN.Land,
		Snare = BUILTIN.Jump,
		Hat = BUILTIN.Swoosh,
		Tracks = {},
		-- Mood tempo/brightness tweaks (applied on top of the season's Music settings).
		Moods = {
			Farm = { Tempo = 0, Bright = 1 },
			Village = { Tempo = 6, Bright = 1.1 },
			Forest = { Tempo = -6, Bright = 0.9 },
			River = { Tempo = -4, Bright = 1 },
			Mountain = { Tempo = -8, Bright = 0.85 },
			Cave = { Tempo = -14, Bright = 0.6, Minor = true },
			Crystal = { Tempo = -10, Bright = 1.3 },
			Beach = { Tempo = 4, Bright = 1.15 },
			Desert = { Tempo = -2, Bright = 1, Mode = "Phrygian" },
			Snow = { Tempo = -10, Bright = 0.95 },
			Ruins = { Tempo = -12, Bright = 0.8, Mode = "Dorian" },
			Hollow = { Tempo = -16, Bright = 0.6, Minor = true },
			Sky = { Tempo = 0, Bright = 1.4, Mode = "Lydian" },
			Valley = { Tempo = 2, Bright = 1.3, Mode = "Lydian" },
			Grove = { Tempo = -8, Bright = 1.1, Mode = "Dorian" },
			Glade = { Tempo = -12, Bright = 1.2, Mode = "Lydian" },
			Festival = { Tempo = 22, Bright = 1.2 },
			Winter = { Tempo = -4, Bright = 1.1 },
			Night = { Tempo = -12, Bright = 0.8 },
		},
	},
}

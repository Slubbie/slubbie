-- Sound sources. Everything uses sounds that ship with the Roblox client, so the
-- place works with no uploads. Swap any entry for "rbxassetid://..." to use your
-- own audio. Pitch/volume shaping per surface lives in Audio/Sfx on the client.

local Sounds = {
	Footstep = "rbxasset://sounds/action_footsteps_plastic.mp3",
	Jump = "rbxasset://sounds/action_jump.mp3",
	Land = "rbxasset://sounds/action_jump_land.mp3",
	Wind = "rbxasset://sounds/action_falling.mp3",
	Swoosh = "rbxasset://sounds/swoosh.wav",
	Ping = "rbxasset://sounds/electronicpingshort.wav",
	Splash = "rbxasset://sounds/impact_water.mp3",
	Swim = "rbxasset://sounds/action_swim.mp3",
	GetUp = "rbxasset://sounds/action_get_up.mp3",
	Hurt = "rbxasset://sounds/uuhhh.mp3",
	Click = "rbxasset://sounds/electronicpingshort.wav",

	-- Generative music voices (pitched per note by Audio/Music).
	Tone = "rbxasset://sounds/electronicpingshort.wav",
	Kick = "rbxasset://sounds/action_jump_land.mp3",
	Snare = "rbxasset://sounds/action_jump.mp3",
	Hat = "rbxasset://sounds/swoosh.wav",
	Pad = "rbxasset://sounds/action_falling.mp3",

	-- Optional licensed tracks by district: { Id = "rbxassetid://...", Volume = 0.5 }.
	-- When a district has a track, it replaces the generative music there.
	Tracks = {} :: { [string]: { Id: string, Volume: number } },
}

-- How each surface material sounds: footstep pitch, volume and a filter.
-- Materials not listed fall back to "Default".
Sounds.Surfaces = {
	Default = { Pitch = 1, Volume = 0.45, Low = 0, High = 0 },
	Concrete = { Pitch = 0.95, Volume = 0.5, Low = 0, High = -2 },
	Brick = { Pitch = 0.9, Volume = 0.5, Low = 1, High = -3 },
	Metal = { Pitch = 1.35, Volume = 0.55, Low = -4, High = 4, Ring = true },
	DiamondPlate = { Pitch = 1.3, Volume = 0.55, Low = -4, High = 5, Ring = true },
	CorrodedMetal = { Pitch = 1.2, Volume = 0.5, Low = -3, High = 3, Ring = true },
	Wood = { Pitch = 0.8, Volume = 0.5, Low = 3, High = -4 },
	WoodPlanks = { Pitch = 0.75, Volume = 0.55, Low = 4, High = -5 },
	Grass = { Pitch = 0.7, Volume = 0.35, Low = -2, High = -12 },
	LeafyGrass = { Pitch = 0.7, Volume = 0.35, Low = -2, High = -12 },
	Ground = { Pitch = 0.75, Volume = 0.4, Low = 0, High = -10 },
	Mud = { Pitch = 0.6, Volume = 0.4, Low = 3, High = -14 },
	Slate = { Pitch = 1, Volume = 0.5, Low = 0, High = 0 },
	Rock = { Pitch = 0.9, Volume = 0.5, Low = 0, High = -2 },
	Cobblestone = { Pitch = 0.95, Volume = 0.5, Low = 0, High = -1 },
	Marble = { Pitch = 1.15, Volume = 0.5, Low = -2, High = 3, Ring = true },
	Granite = { Pitch = 1.05, Volume = 0.5, Low = 0, High = 1 },
	Glass = { Pitch = 1.5, Volume = 0.45, Low = -6, High = 6, Ring = true },
	Ice = { Pitch = 1.4, Volume = 0.45, Low = -5, High = 5, Ring = true },
	Glacier = { Pitch = 1.3, Volume = 0.45, Low = -4, High = 4, Ring = true },
	Snow = { Pitch = 0.55, Volume = 0.35, Low = 2, High = -16 },
	Sand = { Pitch = 0.6, Volume = 0.35, Low = 0, High = -14 },
	Fabric = { Pitch = 0.6, Volume = 0.3, Low = 2, High = -16 },
	Plastic = { Pitch = 1.05, Volume = 0.45, Low = 0, High = 0 },
	SmoothPlastic = { Pitch = 1.05, Volume = 0.45, Low = 0, High = 0 },
	Neon = { Pitch = 1.6, Volume = 0.4, Low = -6, High = 6, Ring = true },
	ForceField = { Pitch = 1.8, Volume = 0.35, Low = -8, High = 6, Ring = true },
	Water = { Pitch = 0.7, Volume = 0.5, Low = 0, High = -8, Splash = true },
}

return Sounds

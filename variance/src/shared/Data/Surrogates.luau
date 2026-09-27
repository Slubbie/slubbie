-- Visual and audio identity of each surrogate, used by the server's
-- PuppetBuilder (their bodies at the table), the client's RigAnimator (their
-- idle style) and DialogueController (their "voice" blips).
-- Colors are {R, G, B}. Head kinds are built in server/World/PuppetBuilder.luau.

local Surrogates = {}

Surrogates.ById = {
	Ledger = {
		Head = "Monitor",
		Body = { 42, 44, 48 },
		Limbs = { 58, 60, 64 },
		Shirt = { 205, 205, 198 },
		Accent = { 120, 225, 150 },
		Eye = { 120, 255, 160 },
		Extras = { "Tie", "Visor" },
		Voice = { Pitch = 0.78, Rate = 9, Tone = "Blip" },
		Idle = { Sway = 0.15, Fidget = 0.1, Tempo = 0.85, HeadTilt = 0 },
		Portrait = { 30, 48, 38 },
	},
	Volta = {
		Head = "Coil",
		Body = { 190, 82, 32 },
		Limbs = { 150, 64, 28 },
		Shirt = { 60, 60, 60 },
		Accent = { 255, 190, 80 },
		Eye = { 255, 220, 120 },
		Extras = { "Antennae", "Harness" },
		Voice = { Pitch = 1.25, Rate = 15, Tone = "Buzz" },
		Idle = { Sway = 0.35, Fidget = 0.7, Tempo = 1.35, HeadTilt = 0.05 },
		Portrait = { 70, 34, 18 },
	},
	Magpie = {
		Head = "Beak",
		Body = { 24, 24, 34 },
		Limbs = { 30, 30, 42 },
		Shirt = { 60, 70, 110 },
		Accent = { 130, 170, 255 },
		Eye = { 170, 200, 255 },
		Extras = { "Cloak", "Trinkets" },
		Voice = { Pitch = 1.05, Rate = 12, Tone = "Chirp" },
		Idle = { Sway = 0.1, Fidget = 0.3, Tempo = 1.0, HeadTilt = 0.25 },
		Portrait = { 22, 26, 48 },
	},
	Kismet = {
		Head = "Die",
		Body = { 96, 22, 32 },
		Limbs = { 70, 18, 26 },
		Shirt = { 230, 225, 215 },
		Accent = { 225, 180, 80 },
		Eye = { 255, 230, 160 },
		Extras = { "Vest", "Visor" },
		Voice = { Pitch = 1.15, Rate = 13, Tone = "Chime" },
		Idle = { Sway = 0.5, Fidget = 0.45, Tempo = 1.1, HeadTilt = 0.12 },
		Portrait = { 60, 18, 24 },
	},
	Proctor = {
		Head = "Aperture",
		Body = { 236, 236, 232 },
		Limbs = { 220, 220, 216 },
		Shirt = { 200, 200, 196 },
		Accent = { 230, 40, 40 },
		Eye = { 255, 60, 50 },
		Extras = { "Halo" },
		Voice = { Pitch = 0.6, Rate = 7, Tone = "Drone" },
		Idle = { Sway = 0.02, Fidget = 0, Tempo = 0.6, HeadTilt = 0 },
		Portrait = { 50, 12, 12 },
	},
	Proxy = {
		Head = "Dummy",
		Body = { 230, 190, 40 },
		Limbs = { 215, 175, 35 },
		Shirt = { 40, 40, 40 },
		Accent = { 30, 30, 30 },
		Eye = { 40, 40, 40 },
		Extras = { "Markers" },
		Voice = { Pitch = 1.4, Rate = 10, Tone = "Blip" },
		Idle = { Sway = 0.05, Fidget = 0, Tempo = 1, HeadTilt = 0 },
		Portrait = { 70, 58, 14 },
	},
}

function Surrogates.get(id: string?)
	return Surrogates.ById[id or ""] or Surrogates.ById.Ledger
end

return Surrogates

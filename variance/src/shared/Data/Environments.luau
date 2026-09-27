-- The six rooms Trials are held in. Each uses the same table, Arbiter and seats
-- (server/World/ArenaBuilder.luau) around its own props (server/World/Environments),
-- lighting profile, ambience and ambient events.
--
-- Escalation: EnvironmentController blends from the base lighting toward the
-- escalation targets as match intensity rises (later Trials, low Integrity,
-- match point) and runs flicker / warning / machinery effects at the listed
-- rates, always keeping the table readable.

local Environments = {}

export type Environment = {
	Id: string,
	Name: string,
	Nickname: string,
	Description: string,
	Palette: { [string]: { number } },
	Materials: { [string]: string },
	Lighting: { [string]: any },
	Escalation: { [string]: any },
	Audio: { [string]: any },
	Events: { [string]: number },
}

local list: { Environment } = {
	{
		Id = "TestChamber",
		Name = "TEST CHAMBER 04",
		Nickname = "THE CRUCIBLE",
		Description = "A sealed industrial test chamber: blast door, hazard paint, one caged lamp.",
		Palette = {
			Wall = { 66, 68, 66 },
			Floor = { 48, 49, 47 },
			Ceiling = { 36, 37, 36 },
			Trim = { 225, 178, 40 },
			Accent = { 225, 178, 40 },
			Glass = { 30, 42, 42 },
			Prop = { 88, 90, 86 },
		},
		Materials = { Wall = "Concrete", Floor = "Concrete", Ceiling = "Concrete", Trim = "Metal" },
		Lighting = {
			Ambient = { 26, 28, 30 },
			OutdoorAmbient = { 18, 18, 20 },
			Brightness = 0.3,
			ClockTime = 0,
			ExposureCompensation = 0.1,
			FogColor = { 18, 20, 22 },
			Atmosphere = {
				Density = 0.32,
				Offset = 0.1,
				Color = { 66, 66, 62 },
				Decay = { 28, 28, 28 },
				Haze = 1.4,
				Glare = 0,
			},
			ColorCorrection = { Tint = { 255, 244, 228 }, Contrast = 0.12, Saturation = -0.22, Brightness = 0 },
			Bloom = { Intensity = 0.55, Size = 22, Threshold = 1.3 },
			Key = { Color = { 255, 224, 176 }, Brightness = 3.4, Range = 24 },
			Fill = { Color = { 120, 140, 160 }, Brightness = 0.5, Range = 40 },
		},
		Escalation = {
			Tint = { 255, 206, 190 },
			Saturation = -0.05,
			Contrast = 0.22,
			Density = 0.45,
			Warning = { 255, 70, 40 },
			FlickerMin = 0.01,
			FlickerMax = 0.16,
		},
		Audio = { HumPitch = 0.55, HumVolume = 0.32, Bed = "Vent", Reverb = "Hangar" },
		Events = { PowerDip = 3, Vent = 3, CameraTurn = 2, Monitor = 3, Announcement = 2, Silhouette = 1, Warning = 2 },
	},
	{
		Id = "BroadcastStudio",
		Name = "STUDIO 9",
		Nickname = "DEAD AIR",
		Description = "An abandoned broadcast studio. Trusses, dead cameras, an audience of empty seats.",
		Palette = {
			Wall = { 24, 24, 28 },
			Floor = { 34, 30, 30 },
			Ceiling = { 16, 16, 18 },
			Trim = { 200, 40, 40 },
			Accent = { 255, 60, 60 },
			Glass = { 20, 20, 28 },
			Prop = { 50, 50, 56 },
		},
		Materials = { Wall = "Fabric", Floor = "WoodPlanks", Ceiling = "Metal", Trim = "SmoothPlastic" },
		Lighting = {
			Ambient = { 18, 16, 22 },
			OutdoorAmbient = { 12, 10, 14 },
			Brightness = 0.25,
			ClockTime = 0,
			ExposureCompensation = 0.15,
			FogColor = { 12, 10, 14 },
			Atmosphere = {
				Density = 0.28,
				Offset = 0.05,
				Color = { 60, 50, 60 },
				Decay = { 30, 20, 28 },
				Haze = 1.6,
				Glare = 0.2,
			},
			ColorCorrection = { Tint = { 255, 240, 245 }, Contrast = 0.2, Saturation = -0.1, Brightness = 0 },
			Bloom = { Intensity = 0.8, Size = 26, Threshold = 1.2 },
			Key = { Color = { 255, 246, 230 }, Brightness = 4.2, Range = 26 },
			Fill = { Color = { 200, 60, 80 }, Brightness = 0.6, Range = 45 },
		},
		Escalation = {
			Tint = { 255, 200, 205 },
			Saturation = 0.05,
			Contrast = 0.3,
			Density = 0.4,
			Warning = { 255, 40, 50 },
			FlickerMin = 0.005,
			FlickerMax = 0.12,
		},
		Audio = { HumPitch = 0.7, HumVolume = 0.24, Bed = "Studio", Reverb = "Auditorium" },
		Events = { PowerDip = 2, CameraTurn = 4, Monitor = 4, Announcement = 3, Silhouette = 2, Warning = 1, Vent = 1 },
	},
	{
		Id = "ResearchVault",
		Name = "SUBLEVEL C",
		Nickname = "THE VAULT",
		Description = "An underground research floor: server racks, specimen tanks, cold blue light.",
		Palette = {
			Wall = { 52, 60, 66 },
			Floor = { 40, 46, 50 },
			Ceiling = { 30, 34, 38 },
			Trim = { 90, 180, 220 },
			Accent = { 90, 200, 240 },
			Glass = { 40, 90, 100 },
			Prop = { 70, 78, 84 },
		},
		Materials = { Wall = "Metal", Floor = "SmoothPlastic", Ceiling = "Metal", Trim = "Neon" },
		Lighting = {
			Ambient = { 22, 30, 36 },
			OutdoorAmbient = { 14, 20, 26 },
			Brightness = 0.3,
			ClockTime = 0,
			ExposureCompensation = 0.05,
			FogColor = { 14, 20, 26 },
			Atmosphere = {
				Density = 0.3,
				Offset = 0.1,
				Color = { 50, 70, 80 },
				Decay = { 20, 30, 40 },
				Haze = 1.2,
				Glare = 0,
			},
			ColorCorrection = { Tint = { 225, 240, 255 }, Contrast = 0.1, Saturation = -0.15, Brightness = 0 },
			Bloom = { Intensity = 0.7, Size = 24, Threshold = 1.2 },
			Key = { Color = { 210, 235, 255 }, Brightness = 3.2, Range = 24 },
			Fill = { Color = { 60, 160, 200 }, Brightness = 0.6, Range = 40 },
		},
		Escalation = {
			Tint = { 255, 215, 215 },
			Saturation = -0.05,
			Contrast = 0.2,
			Density = 0.42,
			Warning = { 255, 60, 60 },
			FlickerMin = 0.005,
			FlickerMax = 0.1,
		},
		Audio = { HumPitch = 0.85, HumVolume = 0.3, Bed = "Servers", Reverb = "StoneCorridor" },
		Events = { PowerDip = 2, Monitor = 4, Vent = 2, CameraTurn = 2, Announcement = 2, Silhouette = 1, Warning = 3 },
	},
	{
		Id = "FreightTerminal",
		Name = "CUSTOMS 77-C",
		Nickname = "THE CONTAINER",
		Description = "An interrogation room in a freight terminal. One bulb, a two-way mirror, rain outside.",
		Palette = {
			Wall = { 70, 76, 72 },
			Floor = { 50, 52, 50 },
			Ceiling = { 40, 42, 40 },
			Trim = { 150, 60, 40 },
			Accent = { 240, 150, 60 },
			Glass = { 20, 24, 26 },
			Prop = { 96, 70, 50 },
		},
		Materials = { Wall = "CorrodedMetal", Floor = "Concrete", Ceiling = "CorrodedMetal", Trim = "Metal" },
		Lighting = {
			Ambient = { 24, 22, 20 },
			OutdoorAmbient = { 16, 16, 18 },
			Brightness = 0.25,
			ClockTime = 0,
			ExposureCompensation = 0.1,
			FogColor = { 18, 18, 20 },
			Atmosphere = {
				Density = 0.34,
				Offset = 0.1,
				Color = { 70, 64, 56 },
				Decay = { 34, 28, 24 },
				Haze = 1.5,
				Glare = 0,
			},
			ColorCorrection = { Tint = { 255, 238, 215 }, Contrast = 0.16, Saturation = -0.25, Brightness = 0 },
			Bloom = { Intensity = 0.6, Size = 22, Threshold = 1.3 },
			Key = { Color = { 255, 214, 150 }, Brightness = 3.6, Range = 20 },
			Fill = { Color = { 90, 110, 140 }, Brightness = 0.4, Range = 36 },
		},
		Escalation = {
			Tint = { 255, 205, 180 },
			Saturation = -0.1,
			Contrast = 0.26,
			Density = 0.48,
			Warning = { 255, 110, 40 },
			FlickerMin = 0.02,
			FlickerMax = 0.2,
		},
		Audio = { HumPitch = 0.5, HumVolume = 0.28, Bed = "Rain", Reverb = "Room" },
		Events = { PowerDip = 4, Silhouette = 3, Monitor = 1, Announcement = 2, Vent = 1, CameraTurn = 1, Warning = 1 },
	},
	{
		Id = "CasinoBackroom",
		Name = "THE GILDED ROOM",
		Nickname = "BACKROOM",
		Description = "A decaying luxury casino backroom: velvet, a failing chandelier, dust on the wheel.",
		Palette = {
			Wall = { 70, 20, 28 },
			Floor = { 40, 20, 18 },
			Ceiling = { 30, 16, 14 },
			Trim = { 200, 160, 80 },
			Accent = { 230, 190, 100 },
			Glass = { 40, 30, 20 },
			Prop = { 80, 50, 30 },
		},
		Materials = { Wall = "Fabric", Floor = "Carpet", Ceiling = "Wood", Trim = "Foil" },
		Lighting = {
			Ambient = { 30, 20, 16 },
			OutdoorAmbient = { 18, 12, 10 },
			Brightness = 0.3,
			ClockTime = 0,
			ExposureCompensation = 0.1,
			FogColor = { 22, 14, 12 },
			Atmosphere = {
				Density = 0.36,
				Offset = 0.1,
				Color = { 90, 60, 44 },
				Decay = { 40, 24, 16 },
				Haze = 2.0,
				Glare = 0.1,
			},
			ColorCorrection = { Tint = { 255, 232, 205 }, Contrast = 0.1, Saturation = -0.05, Brightness = 0 },
			Bloom = { Intensity = 0.8, Size = 28, Threshold = 1.1 },
			Key = { Color = { 255, 206, 140 }, Brightness = 3.0, Range = 24 },
			Fill = { Color = { 180, 90, 60 }, Brightness = 0.6, Range = 40 },
		},
		Escalation = {
			Tint = { 255, 200, 180 },
			Saturation = 0.08,
			Contrast = 0.2,
			Density = 0.5,
			Warning = { 255, 80, 60 },
			FlickerMin = 0.01,
			FlickerMax = 0.14,
		},
		Audio = { HumPitch = 0.62, HumVolume = 0.22, Bed = "Casino", Reverb = "LivingRoom" },
		Events = { PowerDip = 3, Silhouette = 2, Announcement = 2, Monitor = 1, CameraTurn = 1, Vent = 1, Warning = 1 },
	},
	{
		Id = "EvaluationSuite",
		Name = "EVALUATION SUITE",
		Nickname = "THE BOARD",
		Description = "A sterile corporate evaluation chamber. Frosted glass, silhouettes, a wall of metrics.",
		Palette = {
			Wall = { 210, 212, 210 },
			Floor = { 170, 172, 170 },
			Ceiling = { 225, 226, 224 },
			Trim = { 40, 40, 44 },
			Accent = { 220, 50, 50 },
			Glass = { 190, 205, 210 },
			Prop = { 60, 62, 66 },
		},
		Materials = { Wall = "SmoothPlastic", Floor = "Marble", Ceiling = "SmoothPlastic", Trim = "Metal" },
		Lighting = {
			Ambient = { 70, 72, 74 },
			OutdoorAmbient = { 50, 52, 54 },
			Brightness = 0.6,
			ClockTime = 0,
			ExposureCompensation = -0.1,
			FogColor = { 60, 62, 64 },
			Atmosphere = {
				Density = 0.22,
				Offset = 0.1,
				Color = { 190, 195, 200 },
				Decay = { 120, 125, 130 },
				Haze = 0.6,
				Glare = 0,
			},
			ColorCorrection = { Tint = { 240, 245, 255 }, Contrast = 0.08, Saturation = -0.3, Brightness = 0.02 },
			Bloom = { Intensity = 0.45, Size = 20, Threshold = 1.5 },
			Key = { Color = { 240, 248, 255 }, Brightness = 2.6, Range = 26 },
			Fill = { Color = { 220, 230, 240 }, Brightness = 0.8, Range = 44 },
		},
		Escalation = {
			Tint = { 255, 220, 220 },
			Saturation = -0.2,
			Contrast = 0.18,
			Density = 0.32,
			Warning = { 230, 40, 40 },
			FlickerMin = 0.004,
			FlickerMax = 0.08,
		},
		Audio = { HumPitch = 1.0, HumVolume = 0.2, Bed = "Office", Reverb = "Room" },
		Events = { Monitor = 4, Silhouette = 3, Announcement = 3, CameraTurn = 2, PowerDip = 1, Vent = 1, Warning = 1 },
	},
}

-- The Intake (lobby): warm institutional light, not part of the rotation.
Environments.Lobby = {
	Id = "Lobby",
	Name = "THE INTAKE",
	Nickname = "SUBLEVEL 0",
	Description = "Halden Decision Sciences, intake level.",
	Palette = {},
	Materials = {},
	Lighting = {
		Ambient = { 70, 68, 62 },
		OutdoorAmbient = { 60, 58, 54 },
		Brightness = 0.8,
		ClockTime = 0,
		ExposureCompensation = 0.15,
		FogColor = { 60, 58, 54 },
		Atmosphere = {
			Density = 0.18,
			Offset = 0.05,
			Color = { 170, 160, 140 },
			Decay = { 110, 100, 90 },
			Haze = 0.8,
			Glare = 0,
		},
		ColorCorrection = { Tint = { 255, 246, 232 }, Contrast = 0.08, Saturation = -0.12, Brightness = 0 },
		Bloom = { Intensity = 0.5, Size = 24, Threshold = 1.4 },
		Key = { Color = { 255, 240, 215 }, Brightness = 1, Range = 30 },
		Fill = { Color = { 200, 200, 190 }, Brightness = 0.5, Range = 40 },
	},
	Escalation = {
		Tint = { 255, 246, 232 },
		Saturation = -0.12,
		Contrast = 0.08,
		Density = 0.18,
		Warning = { 255, 80, 60 },
		FlickerMin = 0.01,
		FlickerMax = 0.02,
	},
	Audio = { HumPitch = 0.45, HumVolume = 0.2, Bed = "Lobby", Reverb = "Hangar" },
	Events = {},
}

Environments.List = list
Environments.ById = {} :: { [string]: Environment }
Environments.Ids = {} :: { string }
for _, env in list do
	Environments.ById[env.Id] = env
	table.insert(Environments.Ids, env.Id)
end

function Environments.get(id: string?): Environment
	return Environments.ById[id or ""] or list[1]
end

-- Picks an environment: the requested one, or a rotation that avoids repeats.
function Environments.pick(requested: string?, rng: any, last: string?): string
	if requested and requested ~= "Rotate" and Environments.ById[requested] then
		return requested
	end
	local options = {}
	for _, env in list do
		if env.Id ~= last then
			table.insert(options, env.Id)
		end
	end
	return options[rng:NextInteger(1, #options)]
end

return Environments

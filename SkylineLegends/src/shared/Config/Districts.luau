-- The Guildhall hub and the six districts of Meridian.
--
-- Origins are world positions of each district's social plaza. Districts sit on
-- a ring around the hub, climbing higher the further the story goes, so every
-- district can see the next one glowing on the horizon.

export type Lighting = {
	Clock: { number }, -- time-of-day range the cycle moves through (hours)
	CycleMinutes: number,
	Brightness: number,
	Ambient: Color3,
	OutdoorAmbient: Color3,
	ShiftTop: Color3,
	ShiftBottom: Color3,
	Exposure: number,
	Atmosphere: { Density: number, Offset: number, Color: Color3, Decay: Color3, Glare: number, Haze: number },
	Bloom: { Intensity: number, Size: number, Threshold: number },
	Grade: { Brightness: number, Contrast: number, Saturation: number, Tint: Color3 },
	SunRays: number,
	Clouds: { Cover: number, Density: number, Color: Color3 },
	Night: Color3?,
}

export type District = {
	Id: string,
	Name: string,
	Short: string,
	Tagline: string,
	Lore: string,
	Traits: { string },
	Origin: Vector3,
	KillDepth: number,
	Level: number,
	Chapter: number, -- main story chapter that opens the district
	Order: number,
	Palette: { [string]: Color3 },
	Lighting: Lighting,
	Weather: { Kind: string, Chance: number },
	Music: { Root: number, Tempo: number, Mood: string },
	Ambience: string,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local list: { District } = {
	{
		Id = "Hub",
		Name = "Guildhall Commons",
		Short = "Guildhall",
		Tagline = "Home of the Runners' Guild",
		Lore = "The last tower that never lost its signal. The Guild trains new runners in its yard and sends them out along the broken lines of the city.",
		Traits = { "Training Yard", "Practice Playground", "The Spire challenge tower", "Race board and travel gates" },
		Origin = Vector3.new(0, 260, 0),
		KillDepth = 140,
		Level = 1,
		Chapter = 0,
		Order = 0,
		Palette = {
			Stone = rgb(214, 205, 190),
			Trim = rgb(150, 120, 90),
			Roof = rgb(70, 110, 140),
			Accent = rgb(255, 196, 92),
			Signal = rgb(80, 200, 255),
			Fabric = rgb(196, 66, 58),
			Wood = rgb(150, 105, 70),
		},
		Lighting = {
			Clock = { 9.5, 16.5 },
			CycleMinutes = 24,
			Brightness = 2.4,
			Ambient = rgb(110, 110, 120),
			OutdoorAmbient = rgb(150, 145, 140),
			ShiftTop = rgb(255, 236, 200),
			ShiftBottom = rgb(120, 140, 170),
			Exposure = 0.1,
			Atmosphere = {
				Density = 0.3,
				Offset = 0.15,
				Color = rgb(205, 220, 235),
				Decay = rgb(120, 140, 170),
				Glare = 0.2,
				Haze = 1.4,
			},
			Bloom = { Intensity = 0.55, Size = 22, Threshold = 1.6 },
			Grade = { Brightness = 0.02, Contrast = 0.08, Saturation = 0.12, Tint = rgb(255, 250, 244) },
			SunRays = 0.06,
			Clouds = { Cover = 0.5, Density = 0.6, Color = rgb(255, 255, 255) },
		},
		Weather = { Kind = "Motes", Chance = 0.3 },
		Music = { Root = 0, Tempo = 92, Mood = "Bright" },
		Ambience = "Plaza",
	},
	{
		Id = "Tinroof",
		Name = "Tinroof Terraces",
		Short = "Tinroof",
		Tagline = "Water towers, washing lines and narrow alleys",
		Lore = "A tumble of family rooftops stitched together by clotheslines and planks. When the lift lines failed, the Terraces kept going on favours and rooftop gardens.",
		Traits = {
			"Gentle gaps and forgiving roofs",
			"Clotheslines to ride and balance",
			"Water towers to climb",
			"Narrow alley crossings",
		},
		Origin = Vector3.new(1600, 170, 0),
		KillDepth = 120,
		Level = 1,
		Chapter = 1,
		Order = 1,
		Palette = {
			Brick = rgb(176, 98, 74),
			BrickDark = rgb(130, 70, 56),
			Plaster = rgb(232, 214, 186),
			Tin = rgb(140, 160, 170),
			Roof = rgb(96, 120, 132),
			Wood = rgb(152, 108, 70),
			Accent = rgb(255, 170, 80),
			Signal = rgb(255, 214, 90),
			Leaf = rgb(96, 160, 86),
			Fabric = rgb(90, 160, 210),
		},
		Lighting = {
			Clock = { 6.6, 18.2 },
			CycleMinutes = 22,
			Brightness = 2.6,
			Ambient = rgb(120, 105, 95),
			OutdoorAmbient = rgb(160, 140, 125),
			ShiftTop = rgb(255, 214, 170),
			ShiftBottom = rgb(140, 120, 150),
			Exposure = 0.15,
			Atmosphere = {
				Density = 0.33,
				Offset = 0.2,
				Color = rgb(240, 214, 190),
				Decay = rgb(160, 120, 120),
				Glare = 0.35,
				Haze = 1.8,
			},
			Bloom = { Intensity = 0.6, Size = 24, Threshold = 1.55 },
			Grade = { Brightness = 0.02, Contrast = 0.1, Saturation = 0.18, Tint = rgb(255, 244, 232) },
			SunRays = 0.1,
			Clouds = { Cover = 0.55, Density = 0.55, Color = rgb(255, 236, 220) },
		},
		Weather = { Kind = "Drizzle", Chance = 0.2 },
		Music = { Root = 2, Tempo = 96, Mood = "Warm" },
		Ambience = "Rooftops",
	},
	{
		Id = "Ironworks",
		Name = "Ironworks Quarter",
		Short = "Ironworks",
		Tagline = "Cranes, conveyors and steam",
		Lore = "The foundries that built Meridian's skyways. Half the machines still run on their own schedules, and nobody remembers how to stop them.",
		Traits = {
			"Moving cranes and swinging cargo",
			"Conveyors that push you along",
			"Timed steam vents",
			"Rotating machinery",
		},
		Origin = Vector3.new(800, 150, 1386),
		KillDepth = 120,
		Level = 6,
		Chapter = 2,
		Order = 2,
		Palette = {
			Steel = rgb(96, 100, 108),
			SteelDark = rgb(58, 60, 66),
			Rust = rgb(150, 82, 52),
			Hazard = rgb(240, 180, 40),
			Concrete = rgb(150, 145, 138),
			Accent = rgb(255, 120, 40),
			Signal = rgb(255, 150, 50),
			Glow = rgb(255, 110, 40),
			Pipe = rgb(120, 130, 110),
		},
		Lighting = {
			Clock = { 16.8, 19.2 },
			CycleMinutes = 18,
			Brightness = 2.1,
			Ambient = rgb(110, 90, 80),
			OutdoorAmbient = rgb(150, 115, 95),
			ShiftTop = rgb(255, 170, 110),
			ShiftBottom = rgb(110, 90, 110),
			Exposure = 0.05,
			Atmosphere = {
				Density = 0.42,
				Offset = 0.12,
				Color = rgb(210, 160, 130),
				Decay = rgb(120, 80, 70),
				Glare = 0.5,
				Haze = 2.6,
			},
			Bloom = { Intensity = 0.7, Size = 26, Threshold = 1.45 },
			Grade = { Brightness = 0, Contrast = 0.14, Saturation = 0.05, Tint = rgb(255, 236, 220) },
			SunRays = 0.12,
			Clouds = { Cover = 0.7, Density = 0.7, Color = rgb(220, 180, 160) },
		},
		Weather = { Kind = "Embers", Chance = 0.6 },
		Music = { Root = 5, Tempo = 104, Mood = "Driving" },
		Ambience = "Industrial",
	},
	{
		Id = "Verdant",
		Name = "Verdant Hollow",
		Short = "Verdant",
		Tagline = "Giant trees, ruins and waterfalls",
		Lore = "Meridian's old botanical tier, swallowed by its own gardens. The Starfall Observatory still turns its broken dome toward the Citadel.",
		Traits = {
			"Vines and rope swings",
			"Climbable giant trunks",
			"Crumbling stone walkways",
			"Rising water in the flooded ruins",
		},
		Origin = Vector3.new(-800, 230, 1386),
		KillDepth = 130,
		Level = 14,
		Chapter = 3,
		Order = 3,
		Palette = {
			Stone = rgb(150, 150, 130),
			StoneDark = rgb(100, 104, 92),
			Moss = rgb(84, 140, 70),
			Leaf = rgb(70, 150, 80),
			LeafLight = rgb(130, 190, 90),
			Bark = rgb(110, 80, 58),
			Water = rgb(90, 170, 200),
			Accent = rgb(255, 120, 160),
			Signal = rgb(120, 255, 190),
			Flower = rgb(240, 120, 170),
		},
		Lighting = {
			Clock = { 7.5, 11 },
			CycleMinutes = 20,
			Brightness = 2.2,
			Ambient = rgb(90, 110, 90),
			OutdoorAmbient = rgb(120, 150, 115),
			ShiftTop = rgb(220, 255, 210),
			ShiftBottom = rgb(90, 120, 110),
			Exposure = 0.1,
			Atmosphere = {
				Density = 0.45,
				Offset = 0.25,
				Color = rgb(190, 225, 200),
				Decay = rgb(90, 130, 110),
				Glare = 0.25,
				Haze = 2.2,
			},
			Bloom = { Intensity = 0.6, Size = 26, Threshold = 1.5 },
			Grade = { Brightness = 0.01, Contrast = 0.08, Saturation = 0.22, Tint = rgb(244, 255, 244) },
			SunRays = 0.2,
			Clouds = { Cover = 0.6, Density = 0.5, Color = rgb(240, 255, 245) },
		},
		Weather = { Kind = "Leaves", Chance = 0.8 },
		Music = { Root = 7, Tempo = 88, Mood = "Mystic" },
		Ambience = "Forest",
	},
	{
		Id = "Gilded",
		Name = "Gilded Exchange",
		Short = "Exchange",
		Tagline = "Glass towers, neon and maintenance rigs",
		Lore = "The financial heights, where the trading never stopped even after the city split. Security grids still guard empty floors, and holographic adverts sell to no one.",
		Traits = {
			"High-speed rooftop runs",
			"Moving maintenance platforms",
			"Blinking holographic platforms",
			"Security laser patterns",
		},
		Origin = Vector3.new(-1600, 390, 0),
		KillDepth = 140,
		Level = 22,
		Chapter = 4,
		Order = 4,
		Palette = {
			Glass = rgb(110, 140, 170),
			GlassDark = rgb(40, 52, 70),
			Steel = rgb(170, 175, 190),
			Night = rgb(26, 28, 40),
			Neon = rgb(255, 70, 190),
			Neon2 = rgb(70, 230, 255),
			Gold = rgb(255, 200, 90),
			Accent = rgb(255, 70, 190),
			Signal = rgb(70, 230, 255),
		},
		Lighting = {
			Clock = { 20.5, 23.5 },
			CycleMinutes = 26,
			Brightness = 1.6,
			Ambient = rgb(90, 80, 120),
			OutdoorAmbient = rgb(110, 100, 150),
			ShiftTop = rgb(200, 160, 255),
			ShiftBottom = rgb(60, 80, 140),
			Exposure = 0.25,
			Atmosphere = {
				Density = 0.38,
				Offset = 0.1,
				Color = rgb(120, 100, 170),
				Decay = rgb(60, 40, 110),
				Glare = 0.2,
				Haze = 1.6,
			},
			Bloom = { Intensity = 0.85, Size = 28, Threshold = 1.3 },
			Grade = { Brightness = 0.03, Contrast = 0.16, Saturation = 0.2, Tint = rgb(240, 236, 255) },
			SunRays = 0,
			Clouds = { Cover = 0.45, Density = 0.4, Color = rgb(150, 130, 200) },
			Night = rgb(120, 110, 170),
		},
		Weather = { Kind = "Drizzle", Chance = 0.35 },
		Music = { Root = 9, Tempo = 118, Mood = "Pulse" },
		Ambience = "City",
	},
	{
		Id = "Frostreach",
		Name = "Frostreach",
		Short = "Frostreach",
		Tagline = "Ice, ridgelines and the howling wind",
		Lore = "A mountain settlement grown around the old signal mast at Hollowpeak. Its rope bridges were the last link to the Citadel before the storms came.",
		Traits = {
			"Slippery ice that keeps your momentum",
			"Exposed ridgelines",
			"Gusting wind with visible warnings",
			"Swaying, fragile bridges",
		},
		Origin = Vector3.new(-800, 660, -1386),
		KillDepth = 150,
		Level = 32,
		Chapter = 5,
		Order = 5,
		Palette = {
			Snow = rgb(236, 242, 250),
			Ice = rgb(160, 210, 240),
			Rock = rgb(110, 114, 126),
			RockDark = rgb(70, 74, 86),
			Wood = rgb(120, 86, 62),
			Fabric = rgb(200, 60, 60),
			Accent = rgb(255, 90, 80),
			Signal = rgb(255, 120, 70),
			Lamp = rgb(255, 200, 120),
		},
		Lighting = {
			Clock = { 10, 15.5 },
			CycleMinutes = 22,
			Brightness = 2.8,
			Ambient = rgb(120, 130, 150),
			OutdoorAmbient = rgb(160, 175, 200),
			ShiftTop = rgb(220, 235, 255),
			ShiftBottom = rgb(150, 170, 210),
			Exposure = 0.05,
			Atmosphere = {
				Density = 0.5,
				Offset = 0.3,
				Color = rgb(220, 232, 245),
				Decay = rgb(150, 170, 200),
				Glare = 0.6,
				Haze = 2.4,
			},
			Bloom = { Intensity = 0.45, Size = 20, Threshold = 1.7 },
			Grade = { Brightness = 0.03, Contrast = 0.06, Saturation = -0.05, Tint = rgb(240, 248, 255) },
			SunRays = 0.08,
			Clouds = { Cover = 0.75, Density = 0.75, Color = rgb(240, 245, 255) },
		},
		Weather = { Kind = "Snow", Chance = 0.85 },
		Music = { Root = 4, Tempo = 84, Mood = "Cold" },
		Ambience = "Wind",
	},
	{
		Id = "Citadel",
		Name = "Aether Citadel",
		Short = "Citadel",
		Tagline = "Floating architecture and bent gravity",
		Lore = "The highest settlement, lifted by the Aether Keel. It went silent the night the skyways fell. Nobody who climbed up to find out why ever came back down.",
		Traits = {
			"Floating platforms in orbit",
			"Low-gravity chambers",
			"Aerial currents that carry you",
			"Demanding chains of every technique",
		},
		Origin = Vector3.new(800, 1000, -1386),
		KillDepth = 170,
		Level = 44,
		Chapter = 6,
		Order = 6,
		Palette = {
			Marble = rgb(236, 232, 244),
			MarbleDark = rgb(170, 160, 196),
			Gold = rgb(240, 196, 100),
			Aether = rgb(150, 110, 255),
			Aether2 = rgb(110, 230, 255),
			Stone = rgb(130, 120, 160),
			Accent = rgb(255, 210, 110),
			Signal = rgb(180, 140, 255),
			Glow = rgb(200, 170, 255),
		},
		Lighting = {
			Clock = { 17.6, 18.6 },
			CycleMinutes = 30,
			Brightness = 2.3,
			Ambient = rgb(120, 100, 140),
			OutdoorAmbient = rgb(160, 130, 180),
			ShiftTop = rgb(255, 200, 220),
			ShiftBottom = rgb(120, 100, 190),
			Exposure = 0.2,
			Atmosphere = {
				Density = 0.32,
				Offset = 0.05,
				Color = rgb(230, 190, 220),
				Decay = rgb(140, 100, 190),
				Glare = 0.8,
				Haze = 1.4,
			},
			Bloom = { Intensity = 0.75, Size = 30, Threshold = 1.4 },
			Grade = { Brightness = 0.02, Contrast = 0.1, Saturation = 0.2, Tint = rgb(255, 244, 255) },
			SunRays = 0.18,
			Clouds = { Cover = 0.5, Density = 0.45, Color = rgb(255, 220, 240) },
		},
		Weather = { Kind = "Motes", Chance = 1 },
		Music = { Root = 11, Tempo = 100, Mood = "Epic" },
		Ambience = "Aether",
	},
}

local Districts = {}
Districts.List = list
Districts.ById = {} :: { [string]: District }
for _, district in list do
	Districts.ById[district.Id] = district
end

-- Districts in travel/story order, excluding the hub.
function Districts.Ordered(): { District }
	local result = {}
	for _, district in list do
		if district.Id ~= "Hub" then
			table.insert(result, district)
		end
	end
	table.sort(result, function(a, b)
		return a.Order < b.Order
	end)
	return result
end

-- Which district a world position belongs to (nearest plaza within range).
function Districts.At(position: Vector3): District?
	local best, bestDistance = nil, 900
	for _, district in list do
		local offset = position - district.Origin
		local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
		if flat < bestDistance and offset.Y > -district.KillDepth - 60 and offset.Y < 900 then
			best, bestDistance = district, flat
		end
	end
	return best
end

-- Special mode areas far from the districts.
Districts.Dreamline = Vector3.new(0, 1700, 3800) -- endless mode lanes
Districts.SpireOffset = Vector3.new(0, 0, -250) -- challenge tower, relative to the hub

return Districts

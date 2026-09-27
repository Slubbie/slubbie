-- The four seasons. Order matters: the calendar cycles through them in order.
--
-- Palette values drive client lighting, terrain and foliage colours. Demand
-- multiplies market prices for item categories/tags during the season.

export type Season = {
	Id: string,
	Name: string,
	Icon: string,
	Flavor: string,
	Palette: {
		Grass: Color3,
		Leaves: { Color3 },
		Ambient: Color3,
		Tint: Color3,
		Sky: Color3,
		Saturation: number,
	},
	Music: { Mode: string, Tempo: number, Root: number },
	Demand: { [string]: number },
	Wildlife: { string },
}

local Seasons: { Season } = {
	{
		Id = "Spring",
		Name = "Spring",
		Icon = "🌸",
		Flavor = "Blossoms open and the soil wakes up. Rain is common.",
		Palette = {
			Grass = Color3.fromRGB(104, 172, 76),
			Leaves = { Color3.fromRGB(134, 196, 92), Color3.fromRGB(246, 180, 206), Color3.fromRGB(120, 184, 88) },
			Ambient = Color3.fromRGB(150, 160, 170),
			Tint = Color3.fromRGB(255, 250, 244),
			Sky = Color3.fromRGB(170, 210, 245),
			Saturation = 0.12,
		},
		Music = { Mode = "Major", Tempo = 84, Root = 0 },
		Demand = { Flower = 1.25, Seed = 1.1, Egg = 1.15, Fish = 0.95 },
		Wildlife = { "Butterfly", "Songbird", "Bee" },
	},
	{
		Id = "Summer",
		Name = "Summer",
		Icon = "☀️",
		Flavor = "Long bright days. Water often, and watch for heatwaves.",
		Palette = {
			Grass = Color3.fromRGB(92, 164, 60),
			Leaves = { Color3.fromRGB(78, 150, 58), Color3.fromRGB(96, 166, 64), Color3.fromRGB(70, 138, 52) },
			Ambient = Color3.fromRGB(160, 160, 150),
			Tint = Color3.fromRGB(255, 246, 228),
			Sky = Color3.fromRGB(140, 196, 250),
			Saturation = 0.18,
		},
		Music = { Mode = "Lydian", Tempo = 96, Root = 2 },
		Demand = { Juice = 1.3, Fruit = 1.15, Fish = 1.1, Hot = 0.85 },
		Wildlife = { "Firefly", "Cicada", "Dragonfly" },
	},
	{
		Id = "Autumn",
		Name = "Autumn",
		Icon = "🍂",
		Flavor = "The harvest season. Crops ripen gold and markets are busy.",
		Palette = {
			Grass = Color3.fromRGB(150, 150, 70),
			Leaves = { Color3.fromRGB(226, 128, 46), Color3.fromRGB(200, 70, 40), Color3.fromRGB(236, 176, 60) },
			Ambient = Color3.fromRGB(165, 150, 135),
			Tint = Color3.fromRGB(255, 236, 214),
			Sky = Color3.fromRGB(176, 200, 226),
			Saturation = 0.1,
		},
		Music = { Mode = "Dorian", Tempo = 78, Root = -3 },
		Demand = { Artisan = 1.2, Baked = 1.25, Vegetable = 1.05, Wine = 1.2 },
		Wildlife = { "Crow", "Moth", "Squirrel" },
	},
	{
		Id = "Winter",
		Name = "Winter",
		Icon = "❄️",
		Flavor = "Snow blankets the valley. Only hardy crops grow outdoors.",
		Palette = {
			Grass = Color3.fromRGB(226, 234, 240),
			Leaves = { Color3.fromRGB(236, 242, 248), Color3.fromRGB(64, 104, 84), Color3.fromRGB(220, 230, 240) },
			Ambient = Color3.fromRGB(150, 160, 180),
			Tint = Color3.fromRGB(236, 244, 255),
			Sky = Color3.fromRGB(196, 214, 232),
			Saturation = -0.05,
		},
		Music = { Mode = "Minor", Tempo = 70, Root = 5 },
		Demand = { Vegetable = 1.3, Fruit = 1.35, Cooked = 1.25, Hot = 1.3, Fish = 0.9 },
		Wildlife = { "Snow Owl", "Winter Wren" },
	},
}

return Seasons

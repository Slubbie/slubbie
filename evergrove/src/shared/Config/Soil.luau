-- Soil, water, fertilizer, pests, diseases and companion planting.
--
-- Each tilled tile tracks:
--   Moisture   0-100, drains over time (see Drain), filled by watering/rain/sprinklers
--   Health     0-100 soil health; rises with compost/rotation, falls with monoculture
--   N, P, K    0-100 nutrients, consumed by growing crops, restored by fertilizer
--   Fert       fertilizer applied to the current crop (its effects last until harvest)

export type Fertilizer = {
	Id: string,
	Name: string,
	Icon: string,
	Description: string,
	Price: number?,
	Quality: number?, -- adds to the fertilizer quality factor (0-1)
	Speed: number?, -- growth speed bonus (0.1 = +10%)
	Retain: number?, -- moisture drain reduction (0.5 = half drain)
	Nutrients: { N: number?, P: number?, K: number?, Health: number? }?,
	Mutations: { [string]: number }?, -- chance multipliers
	AllMutations: number?, -- multiplier for every mutation
	Tolerance: { [string]: number }?, -- extra weather tolerance
	Rarity: string,
	Overgrow: number?, -- chance of Overgrown on apply
}

local function fert(def: any): Fertilizer
	def.Rarity = def.Rarity or "Common"
	return def
end

local Fertilizers: { Fertilizer } = {
	fert({
		Id = "compost",
		Name = "Compost",
		Icon = "🟫",
		Description = "Restores nutrients and slowly heals soil.",
		Price = 15,
		Quality = 0.05,
		Nutrients = { N = 20, P = 20, K = 20, Health = 6 },
	}),
	fert({
		Id = "basic_fertilizer",
		Name = "Basic Fertilizer",
		Icon = "🧂",
		Description = "A small boost to crop quality.",
		Price = 40,
		Quality = 0.25,
		Nutrients = { N = 10, P = 10, K = 10 },
	}),
	fert({
		Id = "quality_fertilizer",
		Name = "Quality Fertilizer",
		Icon = "🧪",
		Description = "A strong boost to crop quality.",
		Price = 120,
		Quality = 0.55,
		Nutrients = { N = 15, P = 15, K = 15 },
		Rarity = "Uncommon",
	}),
	fert({
		Id = "deluxe_fertilizer",
		Name = "Deluxe Fertilizer",
		Icon = "⚗️",
		Description = "The best quality boost money can buy.",
		Quality = 0.9,
		Nutrients = { N = 25, P = 25, K = 25, Health = 3 },
		Rarity = "Rare",
	}),
	fert({
		Id = "speed_gro",
		Name = "Speed-Gro",
		Icon = "⏩",
		Description = "Crops grow 12% faster.",
		Price = 80,
		Speed = 0.12,
		Nutrients = { N = 10 },
	}),
	fert({
		Id = "deluxe_speed_gro",
		Name = "Deluxe Speed-Gro",
		Icon = "⏭️",
		Description = "Crops grow 25% faster.",
		Speed = 0.25,
		Nutrients = { N = 15 },
		Rarity = "Uncommon",
	}),
	fert({
		Id = "hyper_speed_gro",
		Name = "Hyper Speed-Gro",
		Icon = "🚀",
		Description = "Crops grow 35% faster and may become Overgrown.",
		Speed = 0.35,
		Nutrients = { N = 20 },
		Rarity = "Rare",
		Overgrow = 0.1,
	}),
	fert({
		Id = "hydro_gel",
		Name = "Hydro Gel",
		Icon = "💧",
		Description = "Soil keeps its water twice as long.",
		Price = 90,
		Retain = 0.5,
	}),
	fert({
		Id = "nitro_mix",
		Name = "Nitro Mix",
		Icon = "🟩",
		Description = "+35 Nitrogen. Leafy crops love it.",
		Price = 30,
		Nutrients = { N = 35 },
	}),
	fert({
		Id = "bone_meal",
		Name = "Bone Meal",
		Icon = "🦴",
		Description = "+35 Phosphorus. Great for roots, fruit and flowers.",
		Price = 30,
		Nutrients = { P = 35 },
	}),
	fert({
		Id = "potash",
		Name = "Potash",
		Icon = "🟧",
		Description = "+35 Potassium. Hardier, higher quality crops.",
		Price = 30,
		Nutrients = { K = 35 },
	}),
	fert({
		Id = "mutagen",
		Name = "Mutagen Mix",
		Icon = "🧬",
		Description = "Every mutation is 1.6× more likely.",
		AllMutations = 1.6,
		Rarity = "Rare",
	}),
	fert({
		Id = "golden_dust",
		Name = "Golden Dust",
		Icon = "✨",
		Description = "Golden mutations are 4× more likely.",
		Mutations = { Golden = 4 },
		Rarity = "Epic",
	}),
	fert({
		Id = "crystal_dust",
		Name = "Crystal Dust",
		Icon = "💎",
		Description = "Crystalized mutations are 4× more likely.",
		Mutations = { Crystalized = 4 },
		Rarity = "Rare",
	}),
	fert({
		Id = "stardust",
		Name = "Stardust Fertilizer",
		Icon = "🌟",
		Description = "Celestial mutations are 3× more likely.",
		Mutations = { Celestial = 3, Glowing = 1.5 },
		Rarity = "Epic",
	}),
	fert({
		Id = "prism_fertilizer",
		Name = "Prism Fertilizer",
		Icon = "🌈",
		Description = "Rainbow mutations are 3× more likely.",
		Mutations = { Rainbow = 3 },
		Rarity = "Epic",
	}),
	fert({
		Id = "ruin_dust",
		Name = "Ruin Dust",
		Icon = "🏺",
		Description = "Ancient mutations are 5× more likely.",
		Mutations = { Ancient = 5 },
		Rarity = "Rare",
	}),
	fert({
		Id = "frost_salt",
		Name = "Frost Salt",
		Icon = "🧊",
		Description = "Frosted is 4× more likely and crops shrug off cold.",
		Mutations = { Frosted = 4 },
		Tolerance = { Cold = 0.4 },
		Rarity = "Uncommon",
	}),
	fert({
		Id = "fire_ash",
		Name = "Fire Ash",
		Icon = "🔥",
		Description = "Spicy and Sunscorched are 3× more likely; crops shrug off heat.",
		Mutations = { Spicy = 3, Sunscorched = 3 },
		Tolerance = { Heat = 0.4 },
		Rarity = "Uncommon",
	}),
	fert({
		Id = "giant_grow",
		Name = "Giant-Grow",
		Icon = "🏋️",
		Description = "Giant mutations are 4× more likely.",
		Mutations = { Giant = 4 },
		Rarity = "Rare",
	}),
	fert({
		Id = "moon_mulch",
		Name = "Moon Mulch",
		Icon = "🌙",
		Description = "Moonkissed and Glowing are 3× more likely.",
		Mutations = { Moonkissed = 3, Glowing = 3 },
		Rarity = "Rare",
	}),
}

-- Pests and diseases: a gentle risk that rewards crop rotation and companions.
local Afflictions = {
	Pests = {
		Id = "Pests",
		Name = "Aphids",
		Icon = "🐛",
		ChancePerHour = 0.0035, -- base, before modifiers
		Growth = 0.5, -- growth multiplier while infested
		QualityPenalty = 0.15,
		Cure = "pest_spray",
		Protect = "PestGuard", -- placeable tag that prevents it nearby
		Seasons = { Spring = 1.2, Summer = 1.5, Autumn = 0.8, Winter = 0.1 },
		Weather = { Heatwave = 1.5, PollenBloom = 1.3, Rain = 0.7 },
	},
	Blight = {
		Id = "Blight",
		Name = "Leaf Blight",
		Icon = "🍂",
		ChancePerHour = 0.002,
		Growth = 0.35,
		QualityPenalty = 0.25,
		Cure = "fungicide",
		Protect = "Greenhouse",
		SpreadChancePerHour = 0.03, -- to neighbours of the same family
		Seasons = { Spring = 1.3, Summer = 0.8, Autumn = 1.4, Winter = 0.2 },
		Weather = { Rain = 2, Fog = 2, Thunderstorm = 1.5, Sunny = 0.5, Heatwave = 0.3 },
	},
}

-- Companion planting: neighbours (8-way) that help or hurt.
-- Effects: Growth (+fraction), Quality (+score), Pests (multiplier), Blight (multiplier).
local Companions = {
	{ A = "carrot", B = "onion", Effect = { Pests = 0.5 }, Note = "Onions keep carrot flies away." },
	{ A = "tomato", B = "basil", Effect = { Quality = 0.05, Pests = 0.7 }, Note = "Basil sweetens tomatoes." },
	{ A = "corn", B = "green_bean", Effect = { Growth = 0.08 }, Note = "Beans feed corn nitrogen." },
	{ A = "corn", B = "pumpkin", Effect = { Growth = 0.05, Quality = 0.03 }, Note = "The 'three sisters'." },
	{ A = "green_bean", B = "pumpkin", Effect = { Growth = 0.05 }, Note = "The 'three sisters'." },
	{ A = "strawberry", B = "lettuce", Effect = { Quality = 0.04 }, Note = "Lettuce shades strawberry roots." },
	{ A = "cabbage", B = "garlic", Effect = { Pests = 0.4 }, Note = "Garlic wards off cabbage worms." },
	{
		A = "sunflower",
		B = "*",
		Effect = { Growth = 0.02 },
		Note = "Sunflowers attract pollinators to every neighbour.",
	},
	{ A = "lavender", B = "*", Effect = { Pests = 0.75 }, Note = "Lavender repels pests nearby." },
	{ A = "potato", B = "tomato", Effect = { Blight = 2.5 }, Note = "Both catch blight and share it." },
	{ A = "onion", B = "green_bean", Effect = { Growth = -0.06 }, Note = "Onions stunt beans." },
	{ A = "moonflower", B = "*", Effect = { Quality = 0.02 }, Note = "Moonflowers calm the night garden." },
}

return {
	Fertilizers = Fertilizers,
	Afflictions = Afflictions,
	Companions = Companions,

	-- Moisture drains this much per in-game hour (× weather Drain × crop water need).
	DrainPerHour = 3.4,
	-- Watering can adds this much per use (capped at 100).
	WaterAmount = 100,
	-- Moisture bands per crop water need: inside the band = full growth + quality credit.
	WaterBands = {
		Low = { Min = 12, Max = 90 },
		Medium = { Min = 25, Max = 100 },
		High = { Min = 45, Max = 100 },
	},
	-- Growth multiplier when moisture is below the band's Min.
	DryGrowth = 0.15,
	-- Nutrients consumed per full crop cycle (scaled by the crop's demand profile).
	NutrientUse = 30,
	-- Health change when harvesting: rotation (different family than last) vs repeat.
	RotationBonus = 3,
	MonoculturePenalty = 4,
	-- Starting values for freshly tilled soil (per parcel type modifiers in Land).
	NewSoil = { Moisture = 0, Health = 55, N = 55, P = 55, K = 55 },
	-- Untilled soil reverts after this many in-game days with nothing planted.
	RevertDays = 4,
	-- New-player grace: no pests/blight until this Farming level.
	AfflictionsFromLevel = 4,
	-- Maximum tiles one tool action can affect (safety cap).
	MaxAoETiles = 49,
}

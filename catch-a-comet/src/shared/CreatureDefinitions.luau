--!strict
-- The celestial creature catalog.
--
-- Adding a creature: add an entry here (and to Order), give it a builder in
-- CreatureRig (or drop a model named after its Id into
-- ReplicatedStorage.Assets.CreatureModels), and list the biomes it lives in.
-- Validate() checks that every biome can still roll every rarity.

local BiomeDefinitions = require(script.Parent.BiomeDefinitions)
local RarityConfig = require(script.Parent.RarityConfig)

export type Palette = {
	Primary: Color3,
	Secondary: Color3,
	Accent: Color3,
	Glow: Color3,
}

export type Species = {
	Id: string,
	DisplayName: string,
	Rarity: string,
	Biomes: { string },
	Description: string,
	-- Habitat size class; all Phase 1 habitats fit every class (models are scaled).
	Size: "Small" | "Medium" | "Large",
	-- Idle animation archetype used by the client animator.
	Idle: "Float" | "Hop" | "Swim" | "Flutter" | "Prowl" | "Waddle" | "Soar" | "Coil",
	-- Voice pitch for the creature's chirp.
	Voice: number,
	Palette: Palette,
	-- Overrides the rarity's base Stardust/second when set.
	BaseRate: number?,
	Bondable: boolean,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local CreatureDefinitions = {}

CreatureDefinitions.Order = {
	"Pebblepuff",
	"OrbitOtter",
	"SparkMoth",
	"Nebble",
	"Crumbtail",
	"Flickerfin",
	"CometFox",
	"HaloHare",
	"MoondropFrog",
	"PolarityPup",
	"StardriftGecko",
	"AuroraLynx",
	"CrystalWisp",
	"SatelliteTurtle",
	"CelestialStingray",
	"PulsarPenguin",
	"NebulaPhoenix",
	"PrismStag",
	"TempestDragonling",
	"ClockworkStarling",
	"EclipseSerpent",
	"SolarLeviathan",
	"AstralGryphon",
	"TheFirstStar",
}

local ALL_BIOMES = { "DawnCommons", "PrismCliffs", "ThunderReef", "ShadowCrater", "AstralExpanse" }

CreatureDefinitions.Species = {
	-- Common ---------------------------------------------------------------
	Pebblepuff = {
		Id = "Pebblepuff",
		DisplayName = "Pebblepuff",
		Rarity = "Common",
		Biomes = { "DawnCommons", "PrismCliffs" },
		Description = "A tiny floating stone with sleepy eyes and crystal freckles. It hums when it's happy, which is always.",
		Size = "Small",
		Idle = "Float",
		Voice = 1.5,
		Palette = {
			Primary = rgb(184, 178, 206),
			Secondary = rgb(150, 144, 178),
			Accent = rgb(116, 229, 254),
			Glow = rgb(170, 245, 255),
		},
		Bondable = true,
	},
	OrbitOtter = {
		Id = "OrbitOtter",
		DisplayName = "Orbit Otter",
		Rarity = "Common",
		Biomes = { "ThunderReef", "AstralExpanse" },
		Description = "A playful otter that keeps a few pebbles in orbit, just in case it needs something to juggle.",
		Size = "Small",
		Idle = "Swim",
		Voice = 1.35,
		Palette = {
			Primary = rgb(150, 112, 170),
			Secondary = rgb(246, 226, 214),
			Accent = rgb(255, 207, 112),
			Glow = rgb(255, 230, 170),
		},
		Bondable = true,
	},
	SparkMoth = {
		Id = "SparkMoth",
		DisplayName = "Spark Moth",
		Rarity = "Common",
		Biomes = { "PrismCliffs", "ShadowCrater" },
		Description = "Its star-patterned wings leave faint glitter wherever it flutters.",
		Size = "Small",
		Idle = "Flutter",
		Voice = 1.8,
		Palette = {
			Primary = rgb(255, 238, 186),
			Secondary = rgb(255, 214, 140),
			Accent = rgb(255, 160, 210),
			Glow = rgb(255, 250, 200),
		},
		Bondable = true,
	},
	Nebble = {
		Id = "Nebble",
		DisplayName = "Nebble",
		Rarity = "Common",
		Biomes = { "DawnCommons", "ShadowCrater", "AstralExpanse" },
		Description = "A soft little cloud with glowing cheeks. Nebbles drift toward anyone who looks lonely.",
		Size = "Small",
		Idle = "Float",
		Voice = 1.6,
		Palette = {
			Primary = rgb(236, 232, 255),
			Secondary = rgb(208, 200, 250),
			Accent = rgb(255, 150, 190),
			Glow = rgb(255, 190, 215),
		},
		Bondable = true,
	},
	Crumbtail = {
		Id = "Crumbtail",
		DisplayName = "Crumbtail",
		Rarity = "Common",
		Biomes = { "DawnCommons", "ShadowCrater" },
		Description = "A bouncy critter with a comet for a tail. It can't sit still, and its tail can't either.",
		Size = "Small",
		Idle = "Hop",
		Voice = 1.7,
		Palette = {
			Primary = rgb(255, 196, 150),
			Secondary = rgb(255, 238, 214),
			Accent = rgb(255, 120, 90),
			Glow = rgb(255, 207, 112),
		},
		Bondable = true,
	},
	Flickerfin = {
		Id = "Flickerfin",
		DisplayName = "Flickerfin",
		Rarity = "Common",
		Biomes = { "ThunderReef" },
		Description = "Translucent celestial fins let it swim through the air as if it were water.",
		Size = "Small",
		Idle = "Swim",
		Voice = 1.45,
		Palette = {
			Primary = rgb(120, 220, 230),
			Secondary = rgb(200, 250, 255),
			Accent = rgb(255, 160, 200),
			Glow = rgb(170, 245, 255),
		},
		Bondable = true,
	},
	-- Uncommon -------------------------------------------------------------
	CometFox = {
		Id = "CometFox",
		DisplayName = "Comet Fox",
		Rarity = "Uncommon",
		Biomes = { "DawnCommons", "ShadowCrater" },
		Description = "Glowing paws, a trailing star tail and a habit of following comets home.",
		Size = "Medium",
		Idle = "Prowl",
		Voice = 1.2,
		Palette = {
			Primary = rgb(255, 150, 96),
			Secondary = rgb(255, 240, 224),
			Accent = rgb(116, 229, 254),
			Glow = rgb(190, 248, 255),
		},
		Bondable = true,
	},
	HaloHare = {
		Id = "HaloHare",
		DisplayName = "Halo Hare",
		Rarity = "Uncommon",
		Biomes = { "DawnCommons", "PrismCliffs" },
		Description = "A graceful hare that wears its golden ring the way other hares wear ears.",
		Size = "Small",
		Idle = "Hop",
		Voice = 1.55,
		Palette = {
			Primary = rgb(252, 244, 250),
			Secondary = rgb(255, 200, 220),
			Accent = rgb(255, 207, 112),
			Glow = rgb(255, 236, 170),
		},
		Bondable = true,
	},
	MoondropFrog = {
		Id = "MoondropFrog",
		DisplayName = "Moondrop Frog",
		Rarity = "Uncommon",
		Biomes = { "ThunderReef", "AstralExpanse" },
		Description = "Its translucent skin shows the phases of the moon, one crescent at a time.",
		Size = "Small",
		Idle = "Hop",
		Voice = 1.1,
		Palette = {
			Primary = rgb(150, 200, 255),
			Secondary = rgb(220, 238, 255),
			Accent = rgb(255, 250, 220),
			Glow = rgb(240, 248, 255),
		},
		Bondable = true,
	},
	PolarityPup = {
		Id = "PolarityPup",
		DisplayName = "Polarity Pup",
		Rarity = "Uncommon",
		Biomes = { "ThunderReef", "ShadowCrater" },
		Description = "Tiny magnetic motes orbit this pup. Red ones chase blue ones forever.",
		Size = "Small",
		Idle = "Prowl",
		Voice = 1.3,
		Palette = {
			Primary = rgb(236, 226, 214),
			Secondary = rgb(150, 122, 104),
			Accent = rgb(255, 110, 120),
			Glow = rgb(110, 170, 255),
		},
		Bondable = true,
	},
	StardriftGecko = {
		Id = "StardriftGecko",
		DisplayName = "Stardrift Gecko",
		Rarity = "Uncommon",
		Biomes = { "PrismCliffs", "AstralExpanse" },
		Description = "Climbs walls, ceilings and, when nobody is watching, thin air.",
		Size = "Small",
		Idle = "Prowl",
		Voice = 1.4,
		Palette = {
			Primary = rgb(120, 230, 170),
			Secondary = rgb(220, 255, 210),
			Accent = rgb(255, 236, 120),
			Glow = rgb(200, 255, 220),
		},
		Bondable = true,
	},
	-- Rare -----------------------------------------------------------------
	AuroraLynx = {
		Id = "AuroraLynx",
		DisplayName = "Aurora Lynx",
		Rarity = "Rare",
		Biomes = { "DawnCommons", "PrismCliffs" },
		Description = "A luminous feline trailed by ribbons of sky. Its tufted ears hear meteors before they fall.",
		Size = "Medium",
		Idle = "Prowl",
		Voice = 1,
		Palette = {
			Primary = rgb(214, 226, 255),
			Secondary = rgb(140, 150, 210),
			Accent = rgb(120, 250, 200),
			Glow = rgb(255, 150, 230),
		},
		Bondable = true,
	},
	CrystalWisp = {
		Id = "CrystalWisp",
		DisplayName = "Crystal Wisp",
		Rarity = "Rare",
		Biomes = { "PrismCliffs", "ShadowCrater" },
		Description = "A floating spirit made of crystal shards that chime softly as they turn.",
		Size = "Small",
		Idle = "Float",
		Voice = 1.9,
		Palette = {
			Primary = rgb(190, 240, 255),
			Secondary = rgb(150, 200, 255),
			Accent = rgb(220, 180, 255),
			Glow = rgb(230, 250, 255),
		},
		Bondable = true,
	},
	SatelliteTurtle = {
		Id = "SatelliteTurtle",
		DisplayName = "Satellite Turtle",
		Rarity = "Rare",
		Biomes = { "ShadowCrater", "AstralExpanse" },
		Description = "Carries a tiny orbital station on its shell. The station has a tiny turtle on it.",
		Size = "Medium",
		Idle = "Waddle",
		Voice = 0.8,
		Palette = {
			Primary = rgb(130, 196, 150),
			Secondary = rgb(84, 120, 150),
			Accent = rgb(220, 226, 240),
			Glow = rgb(116, 229, 254),
		},
		Bondable = true,
	},
	CelestialStingray = {
		Id = "CelestialStingray",
		DisplayName = "Celestial Stingray",
		Rarity = "Rare",
		Biomes = { "ThunderReef", "AstralExpanse" },
		Description = "Glides on star-patterned wings, leaving the faintest wake in the air.",
		Size = "Medium",
		Idle = "Soar",
		Voice = 0.9,
		Palette = {
			Primary = rgb(70, 76, 150),
			Secondary = rgb(150, 160, 230),
			Accent = rgb(255, 250, 220),
			Glow = rgb(116, 229, 254),
		},
		Bondable = true,
	},
	PulsarPenguin = {
		Id = "PulsarPenguin",
		DisplayName = "Pulsar Penguin",
		Rarity = "Rare",
		Biomes = { "DawnCommons", "ThunderReef" },
		Description = "Waddles to a rhythm only it can hear: a steady pulse of light every second.",
		Size = "Small",
		Idle = "Waddle",
		Voice = 1.25,
		Palette = {
			Primary = rgb(52, 60, 104),
			Secondary = rgb(245, 247, 255),
			Accent = rgb(255, 180, 90),
			Glow = rgb(116, 229, 254),
		},
		Bondable = true,
	},
	-- Epic -----------------------------------------------------------------
	NebulaPhoenix = {
		Id = "NebulaPhoenix",
		DisplayName = "Nebula Phoenix",
		Rarity = "Epic",
		Biomes = { "DawnCommons", "AstralExpanse" },
		Description = "A bird of cosmic fire and mist. When it sleeps, small stars form in its feathers.",
		Size = "Medium",
		Idle = "Soar",
		Voice = 1.15,
		Palette = {
			Primary = rgb(255, 120, 170),
			Secondary = rgb(255, 180, 110),
			Accent = rgb(182, 120, 255),
			Glow = rgb(255, 214, 150),
		},
		Bondable = true,
	},
	PrismStag = {
		Id = "PrismStag",
		DisplayName = "Prism Stag",
		Rarity = "Epic",
		Biomes = { "PrismCliffs" },
		Description = "Its crystal antlers split light into soft rainbows across the ground.",
		Size = "Large",
		Idle = "Prowl",
		Voice = 0.85,
		Palette = {
			Primary = rgb(240, 236, 255),
			Secondary = rgb(200, 190, 240),
			Accent = rgb(150, 230, 255),
			Glow = rgb(255, 200, 250),
		},
		Bondable = true,
	},
	TempestDragonling = {
		Id = "TempestDragonling",
		DisplayName = "Tempest Dragonling",
		Rarity = "Epic",
		Biomes = { "ThunderReef" },
		Description = "A pocket-sized dragon that brings its own weather: two small, grumpy clouds.",
		Size = "Medium",
		Idle = "Flutter",
		Voice = 1.05,
		Palette = {
			Primary = rgb(80, 170, 200),
			Secondary = rgb(200, 240, 250),
			Accent = rgb(255, 236, 120),
			Glow = rgb(180, 240, 255),
		},
		Bondable = true,
	},
	ClockworkStarling = {
		Id = "ClockworkStarling",
		DisplayName = "Clockwork Starling",
		Rarity = "Epic",
		Biomes = { "ShadowCrater", "AstralExpanse" },
		Description = "A celestial construct of brass and starlight. Nobody knows who wound it up.",
		Size = "Medium",
		Idle = "Flutter",
		Voice = 1.3,
		Palette = {
			Primary = rgb(214, 170, 96),
			Secondary = rgb(140, 100, 70),
			Accent = rgb(116, 229, 254),
			Glow = rgb(190, 248, 255),
		},
		Bondable = true,
	},
	-- Legendary ------------------------------------------------------------
	EclipseSerpent = {
		Id = "EclipseSerpent",
		DisplayName = "Eclipse Serpent",
		Rarity = "Legendary",
		Biomes = { "ShadowCrater", "AstralExpanse" },
		Description = "A majestic floating serpent marked with suns and moons that trade places as it coils.",
		Size = "Large",
		Idle = "Coil",
		Voice = 0.7,
		Palette = {
			Primary = rgb(40, 34, 70),
			Secondary = rgb(90, 80, 140),
			Accent = rgb(255, 207, 112),
			Glow = rgb(225, 232, 255),
		},
		Bondable = true,
	},
	SolarLeviathan = {
		Id = "SolarLeviathan",
		DisplayName = "Solar Leviathan",
		Rarity = "Legendary",
		Biomes = { "ThunderReef", "AstralExpanse" },
		Description = "Enormous, gentle and warm. Its luminous fins glow like a sunrise underwater.",
		Size = "Large",
		Idle = "Swim",
		Voice = 0.55,
		Palette = {
			Primary = rgb(255, 170, 110),
			Secondary = rgb(255, 232, 196),
			Accent = rgb(255, 207, 112),
			Glow = rgb(255, 236, 170),
		},
		Bondable = true,
	},
	AstralGryphon = {
		Id = "AstralGryphon",
		DisplayName = "Astral Gryphon",
		Rarity = "Legendary",
		Biomes = { "DawnCommons", "PrismCliffs", "AstralExpanse" },
		Description = "A regal winged guardian with a radiant cosmic mane. It bows only to the patient.",
		Size = "Large",
		Idle = "Prowl",
		Voice = 0.75,
		Palette = {
			Primary = rgb(255, 240, 210),
			Secondary = rgb(120, 150, 255),
			Accent = rgb(255, 207, 112),
			Glow = rgb(255, 236, 170),
		},
		Bondable = true,
	},
	-- Mythic ---------------------------------------------------------------
	TheFirstStar = {
		Id = "TheFirstStar",
		DisplayName = "The First Star",
		Rarity = "Mythic",
		Biomes = ALL_BIOMES,
		Description = "Older than the islands. Whole orbits turn around it, and it seems to like you.",
		Size = "Large",
		Idle = "Float",
		Voice = 0.6,
		Palette = {
			Primary = rgb(255, 250, 230),
			Secondary = rgb(255, 207, 112),
			Accent = rgb(116, 229, 254),
			Glow = rgb(255, 255, 255),
		},
		Bondable = false,
	},
} :: { [string]: Species }

function CreatureDefinitions.Get(id: string): Species?
	return CreatureDefinitions.Species[id]
end

function CreatureDefinitions.IsSpecies(id: any): boolean
	return type(id) == "string" and CreatureDefinitions.Species[id] ~= nil
end

function CreatureDefinitions.BaseRate(id: string): number
	local species = CreatureDefinitions.Species[id]
	if not species then
		return 0
	end
	return species.BaseRate or RarityConfig.Rarities[species.Rarity].BaseRate
end

-- Species that can be discovered in a biome at a given rarity.
function CreatureDefinitions.Pool(biomeId: string, rarity: string): { string }
	local pool = {}
	for _, id in CreatureDefinitions.Order do
		local species = CreatureDefinitions.Species[id]
		if species.Rarity == rarity and table.find(species.Biomes, biomeId) then
			table.insert(pool, id)
		end
	end
	return pool
end

function CreatureDefinitions.Validate(): { string }
	local problems = {}
	local seen = {}
	for _, id in CreatureDefinitions.Order do
		local species = CreatureDefinitions.Species[id]
		if not species then
			table.insert(problems, `Species '{id}' is listed but not defined`)
			continue
		end
		seen[id] = true
		if species.Id ~= id then
			table.insert(problems, `Species '{id}' has mismatched Id '{species.Id}'`)
		end
		if not RarityConfig.IsRarity(species.Rarity) then
			table.insert(problems, `Species '{id}' has unknown rarity '{species.Rarity}'`)
		end
		if #species.Biomes == 0 then
			table.insert(problems, `Species '{id}' lives in no biome`)
		end
		for _, biomeId in species.Biomes do
			if not BiomeDefinitions.IsBiome(biomeId) then
				table.insert(problems, `Species '{id}' lists unknown biome '{biomeId}'`)
			end
		end
	end
	for id in CreatureDefinitions.Species do
		if not seen[id] then
			table.insert(problems, `Species '{id}' is defined but missing from Order`)
		end
	end
	-- Every biome must be able to roll every rarity, or a roll could come up empty.
	for _, biomeId in BiomeDefinitions.Order do
		for _, rarity in RarityConfig.Order do
			if #CreatureDefinitions.Pool(biomeId, rarity) == 0 then
				table.insert(problems, `Biome '{biomeId}' has no {rarity} species`)
			end
		end
	end
	return problems
end

return CreatureDefinitions

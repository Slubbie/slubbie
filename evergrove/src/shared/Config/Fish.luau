-- Fish. Each water body in the world has a Water tag (Pond, River, Swamp, Ocean,
-- Lake, IceLake, Cave, Oasis, Cloud, Spring, Glade). When you cast, the server
-- builds a table from every fish whose Waters/Seasons/Time/Weather/Depth match,
-- weighted by rarity and modified by bait, rod, skills, buffs and weather tags.
--
--   Time      { from, to } in-game hours (wraps past midnight), nil = any time
--   Weather   list of weather ids required, nil = any
--   Tags      weather tags that boost this fish (see Weather.Fish.Tags)
--   Difficulty 1-100: fish speed and how erratic it is in the minigame
--   Behavior  Smooth | Dart | Sinker | Floater | Mixed | Legend
--   Size      { min cm, max cm }
--   Bait      preferred bait id (×2 chance with it)

export type Fish = {
	Id: string,
	Name: string,
	Icon: string,
	Rarity: string,
	Value: number,
	Waters: { string },
	Seasons: { string },
	Time: { number }?,
	Weather: { string }?,
	Tags: { string }?,
	Difficulty: number,
	Behavior: string,
	Size: { number },
	Bait: string?,
	Deep: boolean?,
	Legendary: boolean?,
	FullMoon: boolean?,
	Description: string?,
	Tint: Color3?,
}

local ANY = { "Spring", "Summer", "Autumn", "Winter" }

local function fish(def: any): Fish
	def.Seasons = def.Seasons or ANY
	def.Icon = def.Icon or "🐟"
	return def
end

local List: { Fish } = {
	-- Farm pond --------------------------------------------------------------------------------
	fish({ Id = "pond_loach", Name = "Pond Loach", Rarity = "Common", Value = 22, Waters = { "Pond" }, Difficulty = 12, Behavior = "Smooth", Size = { 8, 20 } }),
	fish({ Id = "sunfish", Name = "Sunfish", Icon = "🐠", Rarity = "Common", Value = 30, Waters = { "Pond", "River" }, Seasons = { "Spring", "Summer" }, Time = { 6, 19 }, Difficulty = 18, Behavior = "Smooth", Size = { 10, 22 } }),
	fish({ Id = "goldfish", Name = "Goldfish", Icon = "🐠", Rarity = "Uncommon", Value = 90, Waters = { "Pond" }, Time = { 6, 18 }, Difficulty = 24, Behavior = "Dart", Size = { 5, 15 }, Tint = Color3.fromRGB(255, 160, 40) }),
	fish({ Id = "koi", Name = "Koi", Icon = "🎏", Rarity = "Rare", Value = 380, Waters = { "Pond", "Spring" }, Seasons = { "Spring", "Summer" }, Time = { 7, 17 }, Difficulty = 45, Behavior = "Floater", Size = { 30, 70 } }),

	-- Mossback River ---------------------------------------------------------------------------
	fish({ Id = "river_perch", Name = "River Perch", Rarity = "Common", Value = 28, Waters = { "River" }, Difficulty = 15, Behavior = "Smooth", Size = { 12, 30 } }),
	fish({ Id = "silver_minnow", Name = "Silver Minnow", Rarity = "Common", Value = 18, Waters = { "River", "Pond" }, Seasons = { "Spring", "Summer" }, Difficulty = 20, Behavior = "Dart", Size = { 4, 9 } }),
	fish({ Id = "mossback_carp", Name = "Mossback Carp", Rarity = "Common", Value = 35, Waters = { "River", "Swamp", "Pond" }, Difficulty = 14, Behavior = "Sinker", Size = { 25, 60 } }),
	fish({ Id = "brook_trout", Name = "Brook Trout", Rarity = "Uncommon", Value = 95, Waters = { "River" }, Seasons = { "Spring", "Autumn" }, Time = { 5, 12 }, Difficulty = 35, Behavior = "Mixed", Size = { 20, 45 } }),
	fish({ Id = "rainbow_trout", Name = "Rainbow Trout", Rarity = "Uncommon", Value = 120, Waters = { "River", "Lake" }, Seasons = { "Summer" }, Time = { 6, 19 }, Tags = { "Rain" }, Difficulty = 40, Behavior = "Mixed", Size = { 25, 60 } }),
	fish({ Id = "pike", Name = "Pike", Rarity = "Uncommon", Value = 140, Waters = { "River", "Lake" }, Seasons = { "Autumn", "Winter" }, Difficulty = 50, Behavior = "Dart", Size = { 40, 110 } }),
	fish({ Id = "river_catfish", Name = "Whisker Catfish", Rarity = "Uncommon", Value = 160, Waters = { "River", "Swamp" }, Seasons = { "Spring", "Autumn" }, Time = { 19, 4 }, Tags = { "Rain", "Storm" }, Difficulty = 55, Behavior = "Sinker", Size = { 30, 120 }, Bait = "bait" }),
	fish({ Id = "sturgeon", Name = "Sturgeon", Rarity = "Rare", Value = 420, Waters = { "River", "Lake" }, Seasons = { "Summer", "Winter" }, Time = { 6, 19 }, Difficulty = 62, Behavior = "Sinker", Size = { 80, 200 }, Deep = true }),
	fish({ Id = "glowtail", Name = "Glowtail", Icon = "✨", Rarity = "Rare", Value = 480, Waters = { "River", "Glade" }, Time = { 20, 4 }, Tags = { "Fog" }, Difficulty = 58, Behavior = "Floater", Size = { 15, 35 }, Bait = "glow_bait" }),
	fish({ Id = "river_king", Name = "The River King", Icon = "👑", Rarity = "Legendary", Value = 6000, Legendary = true, Waters = { "River" }, Seasons = { "Spring" }, Weather = { "Rain", "Thunderstorm" }, Time = { 6, 10 }, Difficulty = 90, Behavior = "Legend", Size = { 150, 260 }, Bait = "legend_lure", Description = "An enormous old carp with a crown-shaped fin. Only surfaces on rainy spring mornings." }),

	-- Wetlands swamp ---------------------------------------------------------------------------
	fish({ Id = "mudskipper", Name = "Mudskipper", Rarity = "Common", Value = 32, Waters = { "Swamp" }, Seasons = { "Summer", "Autumn" }, Difficulty = 22, Behavior = "Dart", Size = { 8, 18 } }),
	fish({ Id = "bog_eel", Name = "Bog Eel", Rarity = "Uncommon", Value = 150, Waters = { "Swamp" }, Time = { 18, 5 }, Difficulty = 52, Behavior = "Mixed", Size = { 50, 140 } }),
	fish({ Id = "swamp_gar", Name = "Swamp Gar", Rarity = "Uncommon", Value = 170, Waters = { "Swamp" }, Seasons = { "Summer", "Autumn" }, Difficulty = 48, Behavior = "Dart", Size = { 60, 150 } }),
	fish({ Id = "lanternfish", Name = "Lanternfish", Icon = "🏮", Rarity = "Rare", Value = 520, Waters = { "Swamp", "Ocean" }, Time = { 21, 4 }, Tags = { "Fog" }, Difficulty = 60, Behavior = "Floater", Size = { 8, 20 }, Deep = true, Bait = "glow_bait" }),
	fish({ Id = "mire_serpent", Name = "Mire Serpent", Icon = "🐍", Rarity = "Legendary", Value = 7200, Legendary = true, Waters = { "Swamp" }, Seasons = { "Autumn" }, Weather = { "Thunderstorm", "Fog" }, Time = { 22, 3 }, Difficulty = 93, Behavior = "Legend", Size = { 300, 600 }, Bait = "legend_lure", Description = "Wetland folk say it's the swamp itself, swimming." }),

	-- Sunpetal Coast (ocean) ---------------------------------------------------------------------
	fish({ Id = "sardine", Name = "Sardine", Rarity = "Common", Value = 20, Waters = { "Ocean" }, Time = { 5, 13 }, Difficulty = 18, Behavior = "Dart", Size = { 10, 20 } }),
	fish({ Id = "mackerel", Name = "Mackerel", Rarity = "Common", Value = 38, Waters = { "Ocean" }, Seasons = { "Spring", "Summer" }, Difficulty = 26, Behavior = "Mixed", Size = { 25, 45 } }),
	fish({ Id = "sea_bass", Name = "Sea Bass", Rarity = "Common", Value = 55, Waters = { "Ocean" }, Difficulty = 28, Behavior = "Smooth", Size = { 30, 70 } }),
	fish({ Id = "red_snapper", Name = "Red Snapper", Icon = "🐠", Rarity = "Uncommon", Value = 110, Waters = { "Ocean" }, Seasons = { "Summer", "Autumn" }, Tags = { "Rain" }, Difficulty = 38, Behavior = "Mixed", Size = { 30, 80 } }),
	fish({ Id = "pufferfish", Name = "Pufferfish", Icon = "🐡", Rarity = "Uncommon", Value = 200, Waters = { "Ocean" }, Seasons = { "Summer" }, Weather = { "Sunny", "Heatwave" }, Time = { 12, 17 }, Difficulty = 60, Behavior = "Floater", Size = { 15, 40 } }),
	fish({ Id = "tuna", Name = "Bluefin Tuna", Rarity = "Uncommon", Value = 190, Waters = { "Ocean" }, Seasons = { "Summer", "Winter" }, Difficulty = 62, Behavior = "Smooth", Size = { 80, 250 }, Deep = true }),
	fish({ Id = "octopus", Name = "Octopus", Icon = "🐙", Rarity = "Rare", Value = 420, Waters = { "Ocean" }, Seasons = { "Summer" }, Time = { 6, 13 }, Difficulty = 72, Behavior = "Sinker", Size = { 40, 120 } }),
	fish({ Id = "swordfish", Name = "Swordfish", Rarity = "Rare", Value = 520, Waters = { "Ocean" }, Seasons = { "Summer", "Autumn" }, Time = { 7, 18 }, Difficulty = 75, Behavior = "Dart", Size = { 120, 300 }, Deep = true }),
	fish({ Id = "anglerfish", Name = "Anglerfish", Rarity = "Rare", Value = 560, Waters = { "Ocean", "Cave" }, Time = { 20, 5 }, Difficulty = 66, Behavior = "Sinker", Size = { 20, 60 }, Deep = true, Bait = "glow_bait" }),
	fish({ Id = "manta_ray", Name = "Manta Ray", Rarity = "Epic", Value = 1400, Waters = { "Ocean" }, Seasons = { "Summer" }, Weather = { "Sunny", "RainbowMist" }, Time = { 9, 16 }, Difficulty = 78, Behavior = "Floater", Size = { 300, 600 } }),
	fish({ Id = "tidecaller", Name = "Tidecaller", Icon = "🌊", Rarity = "Legendary", Value = 9000, Legendary = true, Waters = { "Ocean" }, Seasons = { "Winter" }, Weather = { "Thunderstorm", "Snow" }, Time = { 21, 4 }, Difficulty = 96, Behavior = "Legend", Size = { 400, 900 }, Bait = "legend_lure", Description = "A silver giant that rides the storm tides." }),

	-- Emberstone lake ------------------------------------------------------------------------------
	fish({ Id = "lake_char", Name = "Lake Char", Rarity = "Common", Value = 40, Waters = { "Lake" }, Difficulty = 24, Behavior = "Smooth", Size = { 25, 55 } }),
	fish({ Id = "alpine_trout", Name = "Alpine Trout", Rarity = "Uncommon", Value = 115, Waters = { "Lake" }, Seasons = { "Spring", "Summer" }, Time = { 5, 11 }, Difficulty = 42, Behavior = "Mixed", Size = { 20, 50 } }),
	fish({ Id = "golden_perch", Name = "Golden Perch", Icon = "🐠", Rarity = "Uncommon", Value = 150, Waters = { "Lake" }, Seasons = { "Summer" }, Weather = { "Sunny" }, Difficulty = 44, Behavior = "Dart", Size = { 15, 40 }, Tint = Color3.fromRGB(255, 200, 60) }),
	fish({ Id = "emberfin", Name = "Emberfin", Icon = "🔥", Rarity = "Rare", Value = 640, Waters = { "Lake", "Cave" }, Tags = { "Heat" }, Difficulty = 70, Behavior = "Dart", Size = { 20, 45 }, Deep = true }),

	-- Frostveil ice lake ---------------------------------------------------------------------------
	fish({ Id = "frost_cod", Name = "Frost Cod", Rarity = "Common", Value = 48, Waters = { "IceLake" }, Difficulty = 26, Behavior = "Smooth", Size = { 30, 80 } }),
	fish({ Id = "ice_pike", Name = "Ice Pike", Rarity = "Uncommon", Value = 170, Waters = { "IceLake", "Lake" }, Seasons = { "Winter" }, Tags = { "Cold" }, Difficulty = 55, Behavior = "Dart", Size = { 40, 100 } }),
	fish({ Id = "glacier_salmon", Name = "Glacier Salmon", Rarity = "Uncommon", Value = 180, Waters = { "IceLake" }, Seasons = { "Autumn", "Winter" }, Difficulty = 50, Behavior = "Mixed", Size = { 40, 90 } }),
	fish({ Id = "snow_crab", Name = "Snow Crab", Icon = "🦀", Rarity = "Rare", Value = 380, Waters = { "IceLake", "Ocean" }, Seasons = { "Winter" }, Tags = { "Snow" }, Difficulty = 48, Behavior = "Sinker", Size = { 15, 40 } }),
	fish({ Id = "aurora_salmon", Name = "Aurora Salmon", Icon = "🌌", Rarity = "Legendary", Value = 8000, Legendary = true, Waters = { "IceLake" }, Weather = { "Aurora" }, Time = { 20, 4 }, Difficulty = 92, Behavior = "Legend", Size = { 80, 150 }, Bait = "legend_lure", Description = "Its scales hold the colours of the aurora." }),

	-- Caves ------------------------------------------------------------------------------------------
	fish({ Id = "cave_blindfish", Name = "Cave Blindfish", Rarity = "Common", Value = 60, Waters = { "Cave" }, Difficulty = 30, Behavior = "Smooth", Size = { 8, 20 } }),
	fish({ Id = "crystal_shrimp", Name = "Crystal Shrimp", Icon = "🦐", Rarity = "Uncommon", Value = 220, Waters = { "Cave" }, Difficulty = 46, Behavior = "Dart", Size = { 3, 10 }, Tint = Color3.fromRGB(170, 230, 255) }),
	fish({ Id = "ghostfish", Name = "Ghostfish", Icon = "👻", Rarity = "Rare", Value = 600, Waters = { "Cave", "Glade" }, Difficulty = 68, Behavior = "Floater", Size = { 15, 35 } }),
	fish({ Id = "void_angler", Name = "Void Angler", Icon = "🕳️", Rarity = "Legendary", Value = 10000, Legendary = true, Waters = { "Cave" }, Time = { 23, 2 }, Difficulty = 97, Behavior = "Legend", Size = { 60, 140 }, Deep = true, Bait = "legend_lure", Description = "Lives in the deepest pool of the Crystal Caverns. Its lure is a tiny black star." }),

	-- Dunewind oasis ------------------------------------------------------------------------------------
	fish({ Id = "oasis_guppy", Name = "Oasis Guppy", Icon = "🐠", Rarity = "Common", Value = 45, Waters = { "Oasis" }, Difficulty = 22, Behavior = "Dart", Size = { 3, 7 } }),
	fish({ Id = "dune_eel", Name = "Dune Eel", Rarity = "Uncommon", Value = 190, Waters = { "Oasis" }, Time = { 18, 6 }, Difficulty = 54, Behavior = "Mixed", Size = { 40, 90 } }),
	fish({ Id = "mirage_koi", Name = "Mirage Koi", Icon = "🎏", Rarity = "Rare", Value = 700, Waters = { "Oasis" }, Tags = { "Heat" }, Difficulty = 66, Behavior = "Floater", Size = { 30, 60 } }),
	fish({ Id = "solar_koi", Name = "Solar Koi", Icon = "🌞", Rarity = "Legendary", Value = 8500, Legendary = true, Waters = { "Oasis" }, Weather = { "Heatwave" }, Time = { 11, 14 }, Difficulty = 94, Behavior = "Legend", Size = { 60, 110 }, Bait = "legend_lure", Description = "Blazing gold. Only rises at the height of a heatwave." }),

	-- Skyreach cloud pools --------------------------------------------------------------------------------
	fish({ Id = "cloud_guppy", Name = "Cloud Guppy", Icon = "☁️", Rarity = "Uncommon", Value = 240, Waters = { "Cloud" }, Difficulty = 40, Behavior = "Floater", Size = { 5, 12 } }),
	fish({ Id = "star_ray", Name = "Star Ray", Icon = "⭐", Rarity = "Rare", Value = 900, Waters = { "Cloud" }, Time = { 20, 5 }, Tags = { "Cosmic" }, Difficulty = 72, Behavior = "Floater", Size = { 50, 140 } }),
	fish({ Id = "skywhale_calf", Name = "Skywhale Calf", Icon = "🐋", Rarity = "Legendary", Value = 12000, Legendary = true, Waters = { "Cloud" }, Weather = { "MeteorShower", "Aurora" }, Difficulty = 95, Behavior = "Legend", Size = { 500, 900 }, Bait = "legend_lure", Description = "Its mother sings somewhere above the clouds." }),

	-- Hidden Valley spring & Moonlit Glade ----------------------------------------------------------------
	fish({ Id = "rainbow_koi", Name = "Rainbow Koi", Icon = "🌈", Rarity = "Epic", Value = 2400, Waters = { "Spring" }, Tags = { "Rainbow" }, Difficulty = 80, Behavior = "Mixed", Size = { 40, 80 } }),
	fish({ Id = "elder_carp", Name = "Elder Carp", Icon = "🐉", Rarity = "Legendary", Value = 15000, Legendary = true, Waters = { "Spring" }, Seasons = { "Autumn" }, Time = { 16, 19 }, Difficulty = 98, Behavior = "Legend", Size = { 200, 400 }, Bait = "legend_lure", Description = "Older than the valley. It remembers the first farmers." }),
	fish({ Id = "moonfish", Name = "Moonfish", Icon = "🌙", Rarity = "Rare", Value = 820, Waters = { "Glade" }, Time = { 20, 4 }, FullMoon = true, Difficulty = 64, Behavior = "Floater", Size = { 20, 45 } }),
}

return {
	List = List,
	-- Relative catch weights per rarity (before bait/rod/weather/skill modifiers).
	RarityWeight = { Common = 60, Uncommon = 26, Rare = 9, Epic = 3, Legendary = 1.2 },
	-- Chance a cast hooks junk or treasure instead of a fish.
	Junk = { Chance = 0.06, Items = { "fiber", "stone", "clay", "old_coin" } },
	TreasureChance = 0.04,
	-- Minigame tuning (client uses these; server checks timing plausibility).
	Minigame = {
		BarHeight = 1, -- normalised
		BaseZone = 0.24, -- catch zone size at rod tier 1
		ZonePerTier = 0.03,
		FillRate = 0.34, -- progress per second while fish in zone
		DrainRate = 0.22,
		StartProgress = 0.3,
		-- A catch can't be claimed faster than this (seconds) × difficulty factor.
		MinSeconds = 1.6,
		MaxSeconds = 60,
		BiteDelay = { 1.5, 6 }, -- seconds until a bite
		PerfectBonus = 0.1, -- quality score bonus for a catch that never left the zone
	},
	-- Size-based quality: bigger than this fraction of the max size → higher quality.
	QualityBySize = { 0.5, 0.7, 0.85, 0.95 },
}

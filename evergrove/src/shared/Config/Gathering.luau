-- Foraging, bug catching, logging and mining content.
--
-- Where things spawn is set per region in Config/Regions (which forage, bugs,
-- trees and rocks a region has). This module defines the things themselves.

export type Forage = {
	Id: string,
	Name: string,
	Icon: string,
	Rarity: string,
	Value: number,
	Seasons: { string },
	Tags: { string }?,
	Night: boolean?,
	Energy: number?,
	Description: string?,
	Tint: Color3?,
}

export type Bug = {
	Id: string,
	Name: string,
	Icon: string,
	Rarity: string,
	Value: number,
	Seasons: { string },
	Time: { number }?,
	Weather: { string }?,
	Flying: boolean,
	Speed: number, -- how skittish (1-10)
	Description: string?,
	Tint: Color3?,
}

export type Node = {
	Id: string,
	Name: string,
	Kind: string, -- "Tree" | "Rock"
	Tier: number, -- axe/pickaxe tier needed
	HP: number,
	Drops: { { Id: string, Count: { number }, Chance: number? } },
	Respawn: number, -- real seconds
	XP: number,
	Visual: { Color: Color3, Accent: Color3?, Size: number, Shape: string, Material: string?, Glow: boolean? },
}

local ANY = { "Spring", "Summer", "Autumn", "Winter" }
local hex = Color3.fromHex

local function f(id, name, icon, rarity, value, seasons, extra): Forage
	local def = { Id = id, Name = name, Icon = icon, Rarity = rarity, Value = value, Seasons = seasons or ANY }
	for k, v in extra or {} do
		def[k] = v
	end
	return def
end

local Forage: { Forage } = {
	-- Spring
	f("wild_leek", "Wild Leek", "🌱", "Common", 30, { "Spring" }, { Energy = 10 }),
	f("daffodil", "Daffodil", "🌼", "Common", 28, { "Spring" }, { Tags = { "Flower" } }),
	f("dandelion", "Dandelion", "🌼", "Common", 22, { "Spring", "Summer" }, { Tags = { "Flower" }, Energy = 5 }),
	f("morel", "Morel", "🍄", "Uncommon", 120, { "Spring" }, { Tags = { "Mushroom" } }),
	f("violet", "Sweet Violet", "💜", "Uncommon", 60, { "Spring" }, { Tags = { "Flower" } }),
	-- Summer
	f("spice_berry", "Spice Berry", "🔴", "Common", 40, { "Summer" }, { Tags = { "Fruit" }, Energy = 8 }),
	f("sweet_pea", "Sweet Pea", "🌸", "Common", 36, { "Summer" }, { Tags = { "Flower" } }),
	f("fiddlehead", "Fiddlehead Fern", "🌿", "Uncommon", 70, { "Summer" }, { Energy = 12 }),
	f("poppy", "Poppy", "🌺", "Uncommon", 80, { "Summer" }, { Tags = { "Flower" } }),
	-- Autumn
	f("blackberry", "Blackberry", "🫐", "Common", 24, { "Autumn" }, { Tags = { "Fruit", "Berry" }, Energy = 8 }),
	f("hazelnut", "Hazelnut", "🌰", "Common", 40, { "Autumn" }, { Tags = { "Nut" } }),
	f("chanterelle", "Chanterelle", "🍄", "Uncommon", 110, { "Autumn" }, { Tags = { "Mushroom" } }),
	f("wild_plum", "Wild Plum", "🍑", "Common", 50, { "Autumn", "Summer" }, { Tags = { "Fruit" }, Energy = 10 }),
	f("common_mushroom", "Common Mushroom", "🍄", "Common", 25, { "Spring", "Autumn" }, { Tags = { "Mushroom" } }),
	-- Winter
	f("crocus", "Crocus", "🌷", "Common", 40, { "Winter" }, { Tags = { "Flower" } }),
	f("winter_root", "Winter Root", "🥔", "Common", 45, { "Winter" }, { Energy = 12 }),
	f("holly", "Holly", "🍃", "Uncommon", 60, { "Winter" }),
	f("crystal_fruit", "Crystal Fruit", "❄️", "Rare", 200, { "Winter" }, { Tags = { "Fruit" } }),
	-- Beach
	f("seashell", "Seashell", "🐚", "Common", 20, ANY),
	f("sea_urchin", "Sea Urchin", "🟣", "Uncommon", 90, ANY),
	f("seaweed", "Seaweed", "🌿", "Common", 15, ANY, { Energy = 5 }),
	f("pearl", "Pearl", "⚪", "Epic", 1200, ANY, { Description = "A perfect pearl, washed up on the tide." }),
	f("driftwood", "Driftwood", "🪵", "Common", 12, ANY),
	-- Desert
	f("cactus_flower", "Cactus Flower", "🌵", "Uncommon", 90, { "Spring", "Summer" }, { Tags = { "Flower" } }),
	f("desert_sage", "Desert Sage", "🌿", "Common", 45, ANY, { Tags = { "Herb" } }),
	f("sand_dollar", "Sand Dollar", "🪙", "Uncommon", 80, ANY),
	f("coconut", "Coconut", "🥥", "Common", 60, ANY, { Tags = { "Fruit" }, Energy = 15 }),
	-- Mountains & Frostveil
	f("mountain_herb", "Mountain Thyme", "🌿", "Common", 38, { "Spring", "Summer", "Autumn" }, { Tags = { "Herb" } }),
	f("edelweiss", "Edelweiss", "🤍", "Rare", 260, { "Summer" }, { Tags = { "Flower" } }),
	f(
		"frost_berry",
		"Frost Berry",
		"🫐",
		"Uncommon",
		90,
		ANY,
		{ Tags = { "Fruit", "Berry" }, Tint = hex("#90caf9") }
	),
	f("snow_lotus", "Snow Lotus", "❄️", "Epic", 900, { "Winter" }, { Tags = { "Flower" } }),
	-- Forest
	f("moss", "Moss", "🟩", "Common", 10, ANY),
	f("pinecone", "Pinecone", "🌲", "Common", 12, ANY),
	f("acorn", "Acorn", "🌰", "Common", 14, ANY, { Description = "Plant it for a tree, or feed it to pigs." }),
	f("forest_honeycomb", "Wild Honeycomb", "🐝", "Uncommon", 150, { "Spring", "Summer" }),
	-- Mushroom grove & caves
	f(
		"glowcap",
		"Glowcap",
		"🍄",
		"Uncommon",
		140,
		ANY,
		{ Tags = { "Mushroom" }, Night = true, Tint = hex("#80deea") }
	),
	f("purple_mushroom", "Purple Mushroom", "🍄", "Rare", 260, ANY, { Tags = { "Mushroom" }, Tint = hex("#b388ff") }),
	f("cave_carrot", "Cave Carrot", "🥕", "Common", 30, ANY, { Energy = 12, Tint = hex("#bcaaa4") }),
	-- Skyreach
	f("sky_blossom", "Sky Blossom", "🌸", "Rare", 320, ANY, { Tags = { "Flower" }, Tint = hex("#b3e5fc") }),
	f("star_petal", "Star Petal", "⭐", "Epic", 900, ANY, { Tags = { "Flower" }, Night = true }),
	-- Ruins, Hollow Farm, Hidden Valley, Glade
	f("ancient_herb", "Ancient Herb", "🌿", "Rare", 300, ANY, { Tags = { "Herb" }, Tint = hex("#a1887f") }),
	f("ghost_bloom", "Ghost Bloom", "🥀", "Rare", 380, { "Autumn", "Winter" }, { Tags = { "Flower" }, Night = true }),
	f("rainbow_petal", "Rainbow Petal", "🌈", "Legendary", 2400, ANY, { Tags = { "Flower" } }),
	f("elder_bloom", "Elder Bloom", "🌼", "Epic", 1100, ANY, { Tags = { "Flower" } }),
	f("moon_petal", "Moon Petal", "🌙", "Rare", 420, ANY, { Tags = { "Flower" }, Night = true }),
	f("fairy_dust", "Fairy Dust", "✨", "Epic", 800, ANY, { Night = true }),
}

local function b(id, name, icon, rarity, value, seasons, time, extra): Bug
	local def = {
		Id = id,
		Name = name,
		Icon = icon,
		Rarity = rarity,
		Value = value,
		Seasons = seasons or ANY,
		Time = time,
		Flying = true,
		Speed = 4,
	}
	for k, v in extra or {} do
		def[k] = v
	end
	return def
end

local Bugs: { Bug } = {
	b("cabbage_white", "Cabbage White", "🦋", "Common", 30, { "Spring", "Summer" }, { 7, 18 }, { Speed = 3 }),
	b(
		"monarch",
		"Monarch Butterfly",
		"🦋",
		"Uncommon",
		90,
		{ "Summer", "Autumn" },
		{ 8, 17 },
		{ Speed = 4, Tint = hex("#ff9800") }
	),
	b("blue_morpho", "Blue Morpho", "🦋", "Rare", 380, { "Summer" }, { 9, 16 }, { Speed = 6, Tint = hex("#2196f3") }),
	b("ladybug", "Ladybug", "🐞", "Common", 25, { "Spring", "Summer" }, { 6, 18 }, { Flying = false, Speed = 2 }),
	b("honeybee", "Honeybee", "🐝", "Common", 35, { "Spring", "Summer" }, { 7, 18 }, { Speed = 5 }),
	b(
		"grasshopper",
		"Grasshopper",
		"🦗",
		"Common",
		30,
		{ "Summer", "Autumn" },
		{ 8, 18 },
		{ Flying = false, Speed = 6 }
	),
	b("cricket", "Cricket", "🦗", "Common", 35, { "Summer", "Autumn" }, { 19, 4 }, { Flying = false, Speed = 5 }),
	b("firefly", "Firefly", "✨", "Uncommon", 70, { "Summer" }, { 20, 3 }, { Speed = 3, Tint = hex("#ffee58") }),
	b("dragonfly", "Dragonfly", "🪰", "Uncommon", 80, { "Summer" }, { 8, 17 }, { Speed = 8 }),
	b("stag_beetle", "Stag Beetle", "🪲", "Rare", 420, { "Summer" }, { 18, 5 }, { Flying = false, Speed = 3 }),
	b(
		"rhino_beetle",
		"Rhino Beetle",
		"🪲",
		"Uncommon",
		180,
		{ "Summer", "Autumn" },
		nil,
		{ Flying = false, Speed = 2 }
	),
	b("cicada", "Cicada", "🪰", "Common", 45, { "Summer" }, { 9, 17 }, { Flying = false, Speed = 3 }),
	b("moth", "Moth", "🦋", "Common", 30, nil, { 19, 5 }, { Speed = 4, Tint = hex("#bcaaa4") }),
	b(
		"luna_moth",
		"Luna Moth",
		"🦋",
		"Rare",
		460,
		{ "Spring", "Summer" },
		{ 21, 4 },
		{ Speed = 5, Tint = hex("#b9f6ca") }
	),
	b(
		"garden_snail",
		"Garden Snail",
		"🐌",
		"Common",
		20,
		{ "Spring", "Autumn" },
		nil,
		{ Flying = false, Speed = 1, Weather = { "Rain", "Fog", "Thunderstorm" } }
	),
	b(
		"tree_frog",
		"Tree Frog",
		"🐸",
		"Uncommon",
		110,
		{ "Spring", "Summer" },
		nil,
		{ Flying = false, Speed = 7, Weather = { "Rain", "Thunderstorm" } }
	),
	b("scorpion", "Desert Scorpion", "🦂", "Uncommon", 200, nil, { 19, 5 }, { Flying = false, Speed = 5 }),
	b(
		"scarab",
		"Golden Scarab",
		"🪲",
		"Epic",
		1500,
		nil,
		{ 11, 15 },
		{ Flying = false, Speed = 6, Tint = hex("#ffd54f"), Weather = { "Heatwave", "Sunny" } }
	),
	b(
		"ice_beetle",
		"Ice Beetle",
		"🪲",
		"Uncommon",
		160,
		{ "Winter" },
		nil,
		{ Flying = false, Speed = 3, Tint = hex("#b3e5fc") }
	),
	b("crystal_moth", "Crystal Moth", "🦋", "Rare", 520, nil, nil, { Speed = 5, Tint = hex("#e1f5fe") }),
	b("cloud_butterfly", "Cloud Butterfly", "🦋", "Rare", 600, nil, { 6, 19 }, { Speed = 5, Tint = hex("#ffffff") }),
	b(
		"star_beetle",
		"Star Beetle",
		"🪲",
		"Epic",
		1100,
		nil,
		{ 20, 4 },
		{ Flying = false, Speed = 4, Tint = hex("#7e57c2") }
	),
	b(
		"spectral_moth",
		"Spectral Moth",
		"🦋",
		"Rare",
		640,
		{ "Autumn", "Winter" },
		{ 21, 4 },
		{ Speed = 5, Tint = hex("#e0f7fa") }
	),
	b("fairy_fly", "Fairy Fly", "✨", "Epic", 1300, nil, { 21, 3 }, { Speed = 7, Tint = hex("#f8bbd0") }),
	b(
		"rainbow_butterfly",
		"Rainbow Butterfly",
		"🦋",
		"Legendary",
		4000,
		nil,
		{ 7, 18 },
		{ Speed = 8, Weather = { "RainbowMist" } }
	),
	b(
		"mole_cricket",
		"Mole Cricket",
		"🦗",
		"Uncommon",
		150,
		{ "Spring", "Summer" },
		{ 19, 4 },
		{ Flying = false, Speed = 4 }
	),
}

local function node(def): Node
	return def
end

local Nodes: { Node } = {
	-- Trees --------------------------------------------------------------------------------
	node({
		Id = "oak",
		Name = "Oak Tree",
		Kind = "Tree",
		Tier = 1,
		HP = 6,
		Respawn = 480,
		XP = 8,
		Drops = {
			{ Id = "wood", Count = { 6, 10 } },
			{ Id = "acorn", Count = { 1, 2 }, Chance = 0.4 },
			{ Id = "sap", Count = { 1, 3 }, Chance = 0.5 },
		},
		Visual = { Color = hex("#5d8a3a"), Accent = hex("#6d4c33"), Size = 1, Shape = "Round" },
	}),
	node({
		Id = "maple",
		Name = "Maple Tree",
		Kind = "Tree",
		Tier = 1,
		HP = 7,
		Respawn = 540,
		XP = 9,
		Drops = { { Id = "wood", Count = { 6, 10 } }, { Id = "maple_sap", Count = { 1, 3 } } },
		Visual = { Color = hex("#c0582a"), Accent = hex("#5d4037"), Size = 1.1, Shape = "Round" },
	}),
	node({
		Id = "pine",
		Name = "Pine Tree",
		Kind = "Tree",
		Tier = 1,
		HP = 7,
		Respawn = 540,
		XP = 9,
		Drops = {
			{ Id = "wood", Count = { 7, 11 } },
			{ Id = "pinecone", Count = { 1, 3 } },
			{ Id = "sap", Count = { 2, 4 } },
		},
		Visual = { Color = hex("#2e6b3a"), Accent = hex("#5d4037"), Size = 1.2, Shape = "Cone" },
	}),
	node({
		Id = "birch",
		Name = "Birch Tree",
		Kind = "Tree",
		Tier = 1,
		HP = 5,
		Respawn = 420,
		XP = 7,
		Drops = { { Id = "wood", Count = { 5, 8 } }, { Id = "sap", Count = { 2, 5 } } },
		Visual = { Color = hex("#9ccc65"), Accent = hex("#eeeeee"), Size = 0.9, Shape = "Round" },
	}),
	node({
		Id = "palm",
		Name = "Palm Tree",
		Kind = "Tree",
		Tier = 1,
		HP = 5,
		Respawn = 480,
		XP = 8,
		Drops = {
			{ Id = "wood", Count = { 4, 7 } },
			{ Id = "coconut", Count = { 1, 2 }, Chance = 0.6 },
			{ Id = "fiber", Count = { 2, 4 } },
		},
		Visual = { Color = hex("#66bb6a"), Accent = hex("#a1887f"), Size = 1.1, Shape = "Palm" },
	}),
	node({
		Id = "mahogany",
		Name = "Mahogany Tree",
		Kind = "Tree",
		Tier = 3,
		HP = 14,
		Respawn = 900,
		XP = 22,
		Drops = { { Id = "hardwood", Count = { 3, 6 } }, { Id = "wood", Count = { 4, 6 } } },
		Visual = { Color = hex("#33691e"), Accent = hex("#4e342e"), Size = 1.4, Shape = "Round" },
	}),
	node({
		Id = "frost_pine",
		Name = "Frost Pine",
		Kind = "Tree",
		Tier = 3,
		HP = 12,
		Respawn = 900,
		XP = 20,
		Drops = { { Id = "hardwood", Count = { 2, 4 } }, { Id = "frost_crystal", Count = { 1, 1 }, Chance = 0.15 } },
		Visual = { Color = hex("#b3cfd9"), Accent = hex("#5d4037"), Size = 1.3, Shape = "Cone" },
	}),
	node({
		Id = "crystal_tree",
		Name = "Crystal Tree",
		Kind = "Tree",
		Tier = 4,
		HP = 18,
		Respawn = 1200,
		XP = 34,
		Drops = { { Id = "crystal_shard", Count = { 1, 3 } }, { Id = "hardwood", Count = { 1, 3 } } },
		Visual = {
			Color = hex("#80deea"),
			Accent = hex("#b2ebf2"),
			Size = 1.2,
			Shape = "Crystal",
			Material = "Glass",
			Glow = true,
		},
	}),
	node({
		Id = "cloud_tree",
		Name = "Cloudpuff Tree",
		Kind = "Tree",
		Tier = 4,
		HP = 16,
		Respawn = 1200,
		XP = 32,
		Drops = { { Id = "cloud_essence", Count = { 1, 2 } }, { Id = "wood", Count = { 3, 5 } } },
		Visual = { Color = hex("#ffffff"), Accent = hex("#90a4ae"), Size = 1.3, Shape = "Cloud" },
	}),
	node({
		Id = "ancient_oak",
		Name = "Ancient Oak",
		Kind = "Tree",
		Tier = 5,
		HP = 40,
		Respawn = 3600,
		XP = 90,
		Drops = {
			{ Id = "ancient_wood", Count = { 1, 2 } },
			{ Id = "hardwood", Count = { 6, 10 } },
			{ Id = "worldtree_acorn", Count = { 1, 1 }, Chance = 0.002 },
		},
		Visual = { Color = hex("#2e7d32"), Accent = hex("#3e2723"), Size = 2.4, Shape = "Round" },
	}),
	node({
		Id = "dead_tree",
		Name = "Hollow Tree",
		Kind = "Tree",
		Tier = 2,
		HP = 8,
		Respawn = 600,
		XP = 12,
		Drops = { { Id = "wood", Count = { 4, 6 } }, { Id = "ghost_bloom", Count = { 1, 1 }, Chance = 0.08 } },
		Visual = { Color = hex("#6d6d6d"), Accent = hex("#424242"), Size = 1.1, Shape = "Dead" },
	}),

	-- Rocks --------------------------------------------------------------------------------
	node({
		Id = "rock",
		Name = "Rock",
		Kind = "Rock",
		Tier = 1,
		HP = 3,
		Respawn = 240,
		XP = 3,
		Drops = { { Id = "stone", Count = { 2, 4 } }, { Id = "geode", Count = { 1, 1 }, Chance = 0.04 } },
		Visual = { Color = hex("#8d8d8d"), Size = 1, Shape = "Boulder" },
	}),
	node({
		Id = "copper_node",
		Name = "Copper Vein",
		Kind = "Rock",
		Tier = 1,
		HP = 5,
		Respawn = 420,
		XP = 7,
		Drops = { { Id = "copper_ore", Count = { 2, 4 } }, { Id = "stone", Count = { 1, 2 } } },
		Visual = { Color = hex("#8d8d8d"), Accent = hex("#e07b39"), Size = 1, Shape = "Ore" },
	}),
	node({
		Id = "coal_node",
		Name = "Coal Seam",
		Kind = "Rock",
		Tier = 1,
		HP = 5,
		Respawn = 420,
		XP = 7,
		Drops = { { Id = "coal", Count = { 1, 3 } }, { Id = "stone", Count = { 1, 2 } } },
		Visual = { Color = hex("#757575"), Accent = hex("#212121"), Size = 1, Shape = "Ore" },
	}),
	node({
		Id = "iron_node",
		Name = "Iron Vein",
		Kind = "Rock",
		Tier = 2,
		HP = 8,
		Respawn = 600,
		XP = 12,
		Drops = { { Id = "iron_ore", Count = { 2, 4 } }, { Id = "stone", Count = { 1, 2 } } },
		Visual = { Color = hex("#7a7a7a"), Accent = hex("#d7ccc8"), Size = 1.1, Shape = "Ore" },
	}),
	node({
		Id = "gold_node",
		Name = "Gold Vein",
		Kind = "Rock",
		Tier = 3,
		HP = 12,
		Respawn = 900,
		XP = 20,
		Drops = { { Id = "gold_ore", Count = { 2, 3 } }, { Id = "stone", Count = { 1, 2 } } },
		Visual = { Color = hex("#6d6d6d"), Accent = hex("#ffca28"), Size = 1.1, Shape = "Ore", Glow = true },
	}),
	node({
		Id = "gem_node",
		Name = "Gem Node",
		Kind = "Rock",
		Tier = 2,
		HP = 9,
		Respawn = 900,
		XP = 16,
		Drops = {
			{ Id = "quartz", Count = { 1, 2 } },
			{ Id = "amethyst", Count = { 1, 1 }, Chance = 0.35 },
			{ Id = "topaz", Count = { 1, 1 }, Chance = 0.35 },
			{ Id = "jade", Count = { 1, 1 }, Chance = 0.12 },
			{ Id = "emerald", Count = { 1, 1 }, Chance = 0.04 },
		},
		Visual = { Color = hex("#616161"), Accent = hex("#ce93d8"), Size = 1, Shape = "Ore", Glow = true },
	}),
	node({
		Id = "geode_node",
		Name = "Geode Rock",
		Kind = "Rock",
		Tier = 2,
		HP = 7,
		Respawn = 600,
		XP = 10,
		Drops = {
			{ Id = "geode", Count = { 1, 2 } },
			{ Id = "frost_geode", Count = { 1, 1 }, Chance = 0.2 },
			{ Id = "magma_geode", Count = { 1, 1 }, Chance = 0.2 },
			{ Id = "omni_geode", Count = { 1, 1 }, Chance = 0.06 },
		},
		Visual = { Color = hex("#8d6e63"), Accent = hex("#b39ddb"), Size = 0.9, Shape = "Boulder" },
	}),
	node({
		Id = "crystal_node",
		Name = "Crystal Cluster",
		Kind = "Rock",
		Tier = 4,
		HP = 16,
		Respawn = 1200,
		XP = 30,
		Drops = {
			{ Id = "crystal_shard", Count = { 2, 4 } },
			{ Id = "quartz", Count = { 1, 3 } },
			{ Id = "diamond", Count = { 1, 1 }, Chance = 0.02 },
		},
		Visual = {
			Color = hex("#80deea"),
			Accent = hex("#e1f5fe"),
			Size = 1.2,
			Shape = "Crystal",
			Material = "Glass",
			Glow = true,
		},
	}),
	node({
		Id = "magma_node",
		Name = "Magma Rock",
		Kind = "Rock",
		Tier = 3,
		HP = 14,
		Respawn = 900,
		XP = 24,
		Drops = {
			{ Id = "ember_core", Count = { 1, 1 }, Chance = 0.3 },
			{ Id = "magma_geode", Count = { 1, 1 }, Chance = 0.4 },
			{ Id = "gold_ore", Count = { 1, 2 } },
			{ Id = "ruby", Count = { 1, 1 }, Chance = 0.08 },
		},
		Visual = { Color = hex("#3e2723"), Accent = hex("#ff5722"), Size = 1.1, Shape = "Ore", Glow = true },
	}),
	node({
		Id = "frost_node",
		Name = "Frost Vein",
		Kind = "Rock",
		Tier = 3,
		HP = 12,
		Respawn = 900,
		XP = 20,
		Drops = {
			{ Id = "iron_ore", Count = { 1, 3 } },
			{ Id = "frost_crystal", Count = { 1, 1 }, Chance = 0.35 },
			{ Id = "frost_geode", Count = { 1, 1 }, Chance = 0.35 },
			{ Id = "aquamarine", Count = { 1, 1 }, Chance = 0.1 },
		},
		Visual = { Color = hex("#90a4ae"), Accent = hex("#e1f5fe"), Size = 1, Shape = "Ore" },
	}),
	node({
		Id = "starsteel_node",
		Name = "Starsteel Vein",
		Kind = "Rock",
		Tier = 5,
		HP = 26,
		Respawn = 1800,
		XP = 60,
		Drops = {
			{ Id = "starsteel_ore", Count = { 1, 3 } },
			{ Id = "meteor_fragment", Count = { 1, 1 }, Chance = 0.05 },
			{ Id = "moonstone", Count = { 1, 1 }, Chance = 0.06 },
		},
		Visual = { Color = hex("#263238"), Accent = hex("#b388ff"), Size = 1.2, Shape = "Ore", Glow = true },
	}),
	node({
		Id = "meteorite_rock",
		Name = "Fallen Meteorite",
		Kind = "Rock",
		Tier = 3,
		HP = 10,
		Respawn = 999999,
		XP = 40,
		Drops = {
			{ Id = "meteorite", Count = { 1, 1 } },
			{ Id = "starsteel_ore", Count = { 1, 2 }, Chance = 0.5 },
			{ Id = "prism_shard", Count = { 1, 1 }, Chance = 0.03 },
		},
		Visual = { Color = hex("#37474f"), Accent = hex("#7c4dff"), Size = 1, Shape = "Boulder", Glow = true },
	}),
	node({
		Id = "clay_mound",
		Name = "Clay Mound",
		Kind = "Rock",
		Tier = 1,
		HP = 2,
		Respawn = 300,
		XP = 3,
		Drops = { { Id = "clay", Count = { 2, 4 } }, { Id = "worm", Count = { 1, 2 }, Chance = 0.4 } },
		Visual = { Color = hex("#a1664b"), Size = 0.8, Shape = "Mound" },
	}),
	node({
		Id = "sand_pile",
		Name = "Sand Dune",
		Kind = "Rock",
		Tier = 1,
		HP = 2,
		Respawn = 300,
		XP = 3,
		Drops = { { Id = "sand", Count = { 3, 6 } }, { Id = "sand_dollar", Count = { 1, 1 }, Chance = 0.08 } },
		Visual = { Color = hex("#e6c98f"), Size = 0.9, Shape = "Mound" },
	}),
}

return {
	Forage = Forage,
	Bugs = Bugs,
	Nodes = Nodes,
	-- Forage spots per region refresh every in-game morning. Each player sees
	-- and collects their own copy, so nobody steals anyone's forage.
	ForagePerRegion = 14,
	-- Bug spawn points per region; a bug appears at a point for BugLifetime seconds.
	BugPointsPerRegion = 10,
	BugLifetime = 45,
	BugRespawn = 30,
	-- Dig spots (wiggling worms) per region per day.
	DigSpotsPerRegion = 5,
	-- Energy cost per axe/pickaxe hit at tier 1 (tier reduces it).
	HitEnergy = 2,
	-- Max distance (studs) from a node/spot to interact.
	Reach = 14,
}

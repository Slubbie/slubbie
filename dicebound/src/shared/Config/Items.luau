-- Every collectible treasure. Plain data: edit values, weights and descriptions freely.
--
--   Id        stable save key. Never rename an Id after release (saves reference it).
--   Rarity    one of Config.Rarities
--   Value     base sell value in coins (mutations multiply this)
--   Weight    relative chance within its region + rarity (only compared to same-tier items)
--   Glyph     placeholder icon (emoji), shown when Icon is empty
--   Icon      optional "rbxassetid://..." image; leave "" to use the placeholder
--   Visual    simple 3D look for reveals: Shape = Ball | Block | Cylinder | Coin | Gem | Egg | Wedge,
--             Color {r,g,b}, Material (Enum.Material name), optional Accent part
--   Special   the region's special collectible: never drawn from normal rolls, only from
--             Straight combos (chance) and Jackpots. See Config.Economy.Combos.

local Items = {
	List = {},
	ById = {},
}

local function add(region: string, def: { [string]: any })
	def.Region = region
	def.Icon = def.Icon or ""
	def.Weight = def.Weight or 1
	table.insert(Items.List, def)
	assert(Items.ById[def.Id] == nil, "Duplicate item id " .. def.Id)
	Items.ById[def.Id] = def
end

-- ── Meadow Market ───────────────────────────────────────────────────────────
add("meadow", {
	Id = "meadow_old_coin",
	Name = "Old Copper Coin",
	Rarity = "Common",
	Value = 3,
	Weight = 55,
	Glyph = "🪙",
	Description = "Worn smooth by a thousand pockets. The king on it looks mildly surprised.",
	Visual = { Shape = "Coin", Color = { 184, 115, 51 }, Material = "Metal" },
})
add("meadow", {
	Id = "meadow_acorn",
	Name = "Lucky Acorn",
	Rarity = "Common",
	Value = 2,
	Weight = 45,
	Glyph = "🌰",
	Description = "Squirrels swear by them. Squirrels swear a lot.",
	Visual = {
		Shape = "Egg",
		Color = { 150, 95, 50 },
		Material = "Wood",
		Accent = { Shape = "Cylinder", Color = { 95, 60, 30 }, Scale = 0.5, Offset = { 0, 0.55, 0 } },
	},
})
add("meadow", {
	Id = "meadow_teacup_snail",
	Name = "Teacup Snail",
	Rarity = "Uncommon",
	Value = 8,
	Weight = 50,
	Glyph = "🐌",
	Description = "Lives in a porcelain cup and refuses to leave. Very polite about it.",
	Visual = { Shape = "Cylinder", Color = { 240, 235, 225 }, Material = "Glass" },
})
add("meadow", {
	Id = "meadow_prize_ribbon",
	Name = "Prize Ribbon",
	Rarity = "Uncommon",
	Value = 7,
	Weight = 50,
	Glyph = "🎀",
	Description = "First place at the Meadow Fair, awarded to a very large turnip.",
	Visual = { Shape = "Coin", Color = { 60, 110, 220 }, Material = "Fabric" },
})
add("meadow", {
	Id = "meadow_sunhoney",
	Name = "Jar of Sunhoney",
	Rarity = "Rare",
	Value = 20,
	Weight = 60,
	Glyph = "🍯",
	Description = "Bees made it from sunbeams. It glows faintly at breakfast.",
	Visual = { Shape = "Cylinder", Color = { 255, 190, 40 }, Material = "Glass" },
})
add("meadow", {
	Id = "meadow_pocket_windmill",
	Name = "Pocket Windmill",
	Rarity = "Rare",
	Value = 24,
	Weight = 40,
	Glyph = "🎐",
	Description = "Spins whenever someone nearby tells a joke.",
	Visual = { Shape = "Block", Color = { 230, 220, 200 }, Material = "Wood" },
})
add("meadow", {
	Id = "meadow_clover_locket",
	Name = "Four-Leaf Locket",
	Rarity = "Epic",
	Value = 55,
	Weight = 1,
	Glyph = "🍀",
	Description = "A real four-leaf clover pressed inside silver. Luck not included (probably).",
	Visual = { Shape = "Coin", Color = { 70, 190, 90 }, Material = "Glass" },
})
add("meadow", {
	Id = "meadow_dandelion_crown",
	Name = "Everbloom Crown",
	Rarity = "Legendary",
	Value = 170,
	Weight = 1,
	Glyph = "👑",
	Description = "Woven from dandelions that never wilt and never, ever blow away.",
	Visual = { Shape = "Cylinder", Color = { 255, 225, 70 }, Material = "Grass" },
})
add("meadow", {
	Id = "meadow_mini_castle",
	Name = "Miniature Enchanted Castle",
	Rarity = "Mythic",
	Value = 520,
	Weight = 1,
	Glyph = "🏰",
	Description = "Tiny lights flicker in its windows. Someone inside is having a lovely party.",
	Visual = {
		Shape = "Block",
		Color = { 200, 200, 215 },
		Material = "Cobblestone",
		Accent = { Shape = "Wedge", Color = { 90, 70, 180 }, Scale = 0.7, Offset = { 0, 0.8, 0 } },
	},
})
add("meadow", {
	Id = "meadow_golden_goose_egg",
	Name = "Golden Goose Egg",
	Rarity = "Secret",
	Value = 1600,
	Weight = 1,
	Special = true,
	Glyph = "🥚",
	Description = "The Meadow's special collectible. Warm to the touch, and it hums a little tune.",
	Visual = { Shape = "Egg", Color = { 255, 205, 60 }, Material = "Foil" },
})

-- ── Crystal Caverns (Stage 2) ───────────────────────────────────────────────
add("crystal", {
	Id = "crystal_glowpebble",
	Name = "Glowpebble",
	Rarity = "Common",
	Value = 6,
	Weight = 55,
	Glyph = "💠",
	Description = "A pebble that forgot to stop glowing after a party.",
	Visual = { Shape = "Ball", Color = { 120, 220, 255 }, Material = "Neon" },
})
add("crystal", {
	Id = "crystal_echo_shell",
	Name = "Echo Shell",
	Rarity = "Common",
	Value = 7,
	Weight = 45,
	Glyph = "🐚",
	Description = "Hold it to your ear and it repeats whatever you said a minute ago.",
	Visual = { Shape = "Wedge", Color = { 235, 200, 220 }, Material = "Marble" },
})
add("crystal", {
	Id = "crystal_tiny_frog",
	Name = "Tiny Crystal Frog",
	Rarity = "Uncommon",
	Value = 20,
	Weight = 50,
	Glyph = "🐸",
	Description = "Ribbits in perfect pitch. Prefers the key of C.",
	Visual = { Shape = "Ball", Color = { 90, 230, 160 }, Material = "Glass" },
})
add("crystal", {
	Id = "crystal_hollow_geode",
	Name = "Hollow Geode",
	Rarity = "Uncommon",
	Value = 18,
	Weight = 50,
	Glyph = "🪨",
	Description = "Plain outside, a tiny purple cathedral inside.",
	Visual = { Shape = "Ball", Color = { 120, 110, 100 }, Material = "Slate" },
})
add("crystal", {
	Id = "crystal_glowworm_lantern",
	Name = "Glowworm Lantern",
	Rarity = "Rare",
	Value = 55,
	Weight = 55,
	Glyph = "🏮",
	Description = "Three glowworms who agreed to share the rent.",
	Visual = { Shape = "Cylinder", Color = { 120, 255, 180 }, Material = "Neon" },
})
add("crystal", {
	Id = "crystal_singing_prism",
	Name = "Singing Prism",
	Rarity = "Rare",
	Value = 50,
	Weight = 45,
	Glyph = "🔷",
	Description = "Turns light into music and music into slightly different light.",
	Visual = { Shape = "Gem", Color = { 150, 200, 255 }, Material = "Glass" },
})
add("crystal", {
	Id = "crystal_amethyst_heart",
	Name = "Amethyst Heart",
	Rarity = "Epic",
	Value = 140,
	Weight = 1,
	Glyph = "💜",
	Description = "It beats once a day, at exactly noon.",
	Visual = { Shape = "Gem", Color = { 170, 90, 230 }, Material = "Glass" },
})
add("crystal", {
	Id = "crystal_dragon_scale",
	Name = "Cave Dragon Scale",
	Rarity = "Legendary",
	Value = 420,
	Weight = 1,
	Glyph = "🐉",
	Description = "Shed by a dragon so shy that nobody has ever seen it.",
	Visual = { Shape = "Wedge", Color = { 60, 180, 150 }, Material = "Glass" },
})
add("crystal", {
	Id = "crystal_deepstar_gem",
	Name = "Deepstar Gem",
	Rarity = "Mythic",
	Value = 1300,
	Weight = 1,
	Glyph = "💎",
	Description = "A star that fell so deep it turned into a gemstone to feel at home.",
	Visual = { Shape = "Gem", Color = { 200, 240, 255 }, Material = "Neon" },
})
add("crystal", {
	Id = "crystal_quartz_king",
	Name = "The Quartz King",
	Rarity = "Secret",
	Value = 4000,
	Weight = 1,
	Special = true,
	Glyph = "🔮",
	Description = "The Caverns' special collectible. A crystal crown that crowns itself.",
	Visual = { Shape = "Gem", Color = { 240, 180, 255 }, Material = "ForceField" },
})

-- ── Frostfall Village (Stage 2) ─────────────────────────────────────────────
add("frost", {
	Id = "frost_lost_mitten",
	Name = "Lost Mitten",
	Rarity = "Common",
	Value = 15,
	Weight = 50,
	Glyph = "🧤",
	Description = "Its twin is out there somewhere. Stay strong, little mitten.",
	Visual = { Shape = "Block", Color = { 200, 60, 60 }, Material = "Fabric" },
})
add("frost", {
	Id = "frost_perfect_icicle",
	Name = "Perfect Icicle",
	Rarity = "Common",
	Value = 18,
	Weight = 50,
	Glyph = "🧊",
	Description = "Judges gave it a 10 for pointiness.",
	Visual = { Shape = "Wedge", Color = { 200, 235, 255 }, Material = "Ice" },
})
add("frost", {
	Id = "frost_tiny_snow_globe",
	Name = "Tiny Snow Globe",
	Rarity = "Uncommon",
	Value = 50,
	Weight = 50,
	Glyph = "❄️",
	Description = "Inside, a miniature Frostfall Village. Someone inside is waving.",
	Visual = { Shape = "Ball", Color = { 220, 240, 255 }, Material = "Glass" },
})
add("frost", {
	Id = "frost_clockwork_penguin",
	Name = "Clockwork Penguin",
	Rarity = "Uncommon",
	Value = 45,
	Weight = 50,
	Glyph = "🐧",
	Description = "Wind it up and it waddles, slides, and bows.",
	Visual = { Shape = "Egg", Color = { 40, 40, 50 }, Material = "Metal" },
})
add("frost", {
	Id = "frost_everwarm_cocoa",
	Name = "Everwarm Cocoa",
	Rarity = "Rare",
	Value = 130,
	Weight = 55,
	Glyph = "☕",
	Description = "Never cools, never empties, never has enough marshmallows.",
	Visual = { Shape = "Cylinder", Color = { 120, 70, 40 }, Material = "SmoothPlastic" },
})
add("frost", {
	Id = "frost_runebound_sled",
	Name = "Runebound Sled",
	Rarity = "Rare",
	Value = 120,
	Weight = 45,
	Glyph = "🛷",
	Description = "Carved with runes that make every hill a little steeper.",
	Visual = { Shape = "Block", Color = { 150, 100, 60 }, Material = "Wood" },
})
add("frost", {
	Id = "frost_bottled_aurora",
	Name = "Bottled Aurora",
	Rarity = "Epic",
	Value = 330,
	Weight = 1,
	Glyph = "🌌",
	Description = "A northern light caught in a jar. Open only in emergencies.",
	Visual = { Shape = "Cylinder", Color = { 90, 255, 180 }, Material = "Neon" },
})
add("frost", {
	Id = "frost_ivory_mammoth",
	Name = "Ivory Mammoth Figurine",
	Rarity = "Legendary",
	Value = 1000,
	Weight = 1,
	Glyph = "🦣",
	Description = "Carved by the first villagers to thank the herd that led them here.",
	Visual = { Shape = "Block", Color = { 245, 235, 215 }, Material = "Marble" },
})
add("frost", {
	Id = "frost_heart_of_winter",
	Name = "Heart of Winter",
	Rarity = "Mythic",
	Value = 3200,
	Weight = 1,
	Glyph = "💙",
	Description = "Every snowflake in Frostfall starts here.",
	Visual = { Shape = "Gem", Color = { 140, 210, 255 }, Material = "Ice" },
})
add("frost", {
	Id = "frost_yeti_footprint",
	Name = "Framed Yeti Footprint",
	Rarity = "Secret",
	Value = 10000,
	Weight = 1,
	Special = true,
	Glyph = "👣",
	Description = "Frostfall's special collectible. Proof. Finally, proof.",
	Visual = { Shape = "Block", Color = { 230, 240, 255 }, Material = "Snow" },
})

-- ── Emberforge (Stage 2) ────────────────────────────────────────────────────
add("ember", {
	Id = "ember_forge_rivet",
	Name = "Forge Rivet",
	Rarity = "Common",
	Value = 35,
	Weight = 55,
	Glyph = "🔩",
	Description = "Holds the whole forge together. Probably shouldn't have taken it.",
	Visual = { Shape = "Cylinder", Color = { 110, 110, 120 }, Material = "DiamondPlate" },
})
add("ember", {
	Id = "ember_smiling_coal",
	Name = "Smiling Coal",
	Rarity = "Common",
	Value = 40,
	Weight = 45,
	Glyph = "⚫",
	Description = "Still warm, still smiling. Nobody knows why.",
	Visual = { Shape = "Ball", Color = { 40, 35, 35 }, Material = "Basalt" },
})
add("ember", {
	Id = "ember_mechanical_beetle",
	Name = "Mechanical Beetle",
	Rarity = "Uncommon",
	Value = 110,
	Weight = 50,
	Glyph = "🪲",
	Description = "Brass shell, ruby eyes, and an opinion about everything.",
	Visual = { Shape = "Egg", Color = { 200, 150, 60 }, Material = "Metal" },
})
add("ember", {
	Id = "ember_brass_gearheart",
	Name = "Brass Gearheart",
	Rarity = "Uncommon",
	Value = 100,
	Weight = 50,
	Glyph = "⚙️",
	Description = "Ticks in time with whoever holds it.",
	Visual = { Shape = "Coin", Color = { 210, 160, 70 }, Material = "Metal" },
})
add("ember", {
	Id = "ember_obsidian_shard",
	Name = "Obsidian Shard",
	Rarity = "Rare",
	Value = 300,
	Weight = 50,
	Glyph = "🗡️",
	Description = "Sharper than a bad review.",
	Visual = { Shape = "Wedge", Color = { 30, 20, 40 }, Material = "Glass" },
})
add("ember", {
	Id = "ember_salamander_jar",
	Name = "Salamander in a Jar",
	Rarity = "Rare",
	Value = 280,
	Weight = 50,
	Glyph = "🦎",
	Description = "A fire salamander who likes the view. The jar is fireproof. Mostly.",
	Visual = { Shape = "Cylinder", Color = { 255, 120, 40 }, Material = "Glass" },
})
add("ember", {
	Id = "ember_pocket_anvil",
	Name = "Pocket Anvil",
	Rarity = "Epic",
	Value = 750,
	Weight = 1,
	Glyph = "⚒️",
	Description = "Weighs as much as a real anvil. Your pockets will never recover.",
	Visual = { Shape = "Block", Color = { 70, 70, 80 }, Material = "Metal" },
})
add("ember", {
	Id = "ember_phoenix_feather",
	Name = "Phoenix Feather",
	Rarity = "Legendary",
	Value = 2300,
	Weight = 1,
	Glyph = "🪶",
	Description = "Burns without burning. Lovely for writing very passionate letters.",
	Visual = { Shape = "Wedge", Color = { 255, 110, 30 }, Material = "Neon" },
})
add("ember", {
	Id = "ember_molten_core",
	Name = "Molten Core",
	Rarity = "Mythic",
	Value = 7200,
	Weight = 1,
	Glyph = "🌋",
	Description = "The beating heart of the forge, somehow the size of a plum.",
	Visual = { Shape = "Ball", Color = { 255, 80, 20 }, Material = "CrackedLava" },
})
add("ember", {
	Id = "ember_forgemaster_die",
	Name = "Forgemaster's Die",
	Rarity = "Secret",
	Value = 22000,
	Weight = 1,
	Special = true,
	Glyph = "🎲",
	Description = "Emberforge's special collectible. The die every forged die was measured against.",
	Visual = { Shape = "Block", Color = { 255, 150, 50 }, Material = "Foil" },
})

-- ── Astral Sanctuary (Stage 2) ──────────────────────────────────────────────
add("astral", {
	Id = "astral_stardust",
	Name = "Pinch of Stardust",
	Rarity = "Common",
	Value = 80,
	Weight = 50,
	Glyph = "✨",
	Description = "Makes anything it touches feel slightly famous.",
	Visual = { Shape = "Ball", Color = { 255, 240, 200 }, Material = "Neon" },
})
add("astral", {
	Id = "astral_moon_fragment",
	Name = "Moon Fragment",
	Rarity = "Common",
	Value = 90,
	Weight = 50,
	Glyph = "🌙",
	Description = "The moon won't miss it. Please don't tell the moon.",
	Visual = { Shape = "Wedge", Color = { 220, 220, 235 }, Material = "Slate" },
})
add("astral", {
	Id = "astral_comet_ribbon",
	Name = "Comet Tail Ribbon",
	Rarity = "Uncommon",
	Value = 250,
	Weight = 50,
	Glyph = "☄️",
	Description = "Snipped from a passing comet, which did not stop to argue.",
	Visual = { Shape = "Coin", Color = { 120, 200, 255 }, Material = "Neon" },
})
add("astral", {
	Id = "astral_constellation_owl",
	Name = "Constellation Owl",
	Rarity = "Uncommon",
	Value = 230,
	Weight = 50,
	Glyph = "🦉",
	Description = "Made of seven stars. Hoots only on clear nights.",
	Visual = { Shape = "Egg", Color = { 70, 80, 160 }, Material = "Glass" },
})
add("astral", {
	Id = "astral_starbound_compass",
	Name = "Starbound Compass",
	Rarity = "Rare",
	Value = 700,
	Weight = 50,
	Glyph = "🧭",
	Description = "Always points toward the nearest wish.",
	Visual = { Shape = "Coin", Color = { 230, 200, 120 }, Material = "Metal" },
})
add("astral", {
	Id = "astral_nebula_harp",
	Name = "Nebula Harp",
	Rarity = "Rare",
	Value = 650,
	Weight = 50,
	Glyph = "🎼",
	Description = "Its strings are made of light from a very distant, very musical galaxy.",
	Visual = { Shape = "Wedge", Color = { 200, 120, 255 }, Material = "Neon" },
})
add("astral", {
	Id = "astral_clockwork_orrery",
	Name = "Clockwork Orrery",
	Rarity = "Epic",
	Value = 1700,
	Weight = 1,
	Glyph = "🪐",
	Description = "A working model of every planet, including three nobody has found yet.",
	Visual = { Shape = "Ball", Color = { 210, 170, 90 }, Material = "Metal" },
})
add("astral", {
	Id = "astral_captured_sunrise",
	Name = "Captured Sunrise",
	Rarity = "Legendary",
	Value = 5200,
	Weight = 1,
	Glyph = "🌅",
	Description = "One perfect morning, kept for a rainy day.",
	Visual = { Shape = "Ball", Color = { 255, 170, 80 }, Material = "Neon" },
})
add("astral", {
	Id = "astral_crown_of_stars",
	Name = "Crown of Constellations",
	Rarity = "Mythic",
	Value = 16000,
	Weight = 1,
	Glyph = "💫",
	Description = "Worn by whoever named the stars. Currently unclaimed.",
	Visual = { Shape = "Cylinder", Color = { 240, 230, 255 }, Material = "ForceField" },
})
add("astral", {
	Id = "astral_first_die",
	Name = "The First Die",
	Rarity = "Secret",
	Value = 50000,
	Weight = 1,
	Special = true,
	Glyph = "🌠",
	Description = "The Sanctuary's special collectible. Legend says the world began with a roll.",
	Visual = { Shape = "Block", Color = { 255, 255, 255 }, Material = "Neon" },
})

return Items

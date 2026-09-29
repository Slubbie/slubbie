-- Minerals, gems, geode minerals and artifacts (all collectible & donatable to the museum).
--
-- Ore rocks (mining nodes) are defined in Config/Gathering; this file is the
-- collectible items themselves. Artifacts come from dig spots (archaeology),
-- fishing treasure and rare drops.

export type Mineral = {
	Id: string,
	Name: string,
	Icon: string,
	Category: string, -- "Gem" | "Mineral" | "Artifact"
	Rarity: string,
	Value: number,
	Description: string,
	Regions: { string }?,
	Tint: Color3?,
}

local function gem(id, name, icon, rarity, value, description, tint): Mineral
	return {
		Id = id,
		Name = name,
		Icon = icon,
		Category = "Gem",
		Rarity = rarity,
		Value = value,
		Description = description,
		Tint = tint,
	}
end

local function mineral(id, name, icon, rarity, value, description, tint): Mineral
	return {
		Id = id,
		Name = name,
		Icon = icon,
		Category = "Mineral",
		Rarity = rarity,
		Value = value,
		Description = description,
		Tint = tint,
	}
end

local function artifact(id, name, icon, rarity, value, description, regions): Mineral
	return {
		Id = id,
		Name = name,
		Icon = icon,
		Category = "Artifact",
		Rarity = rarity,
		Value = value,
		Description = description,
		Regions = regions,
	}
end

local List: { Mineral } = {
	-- Gems (mining nodes and geodes)
	gem(
		"quartz",
		"Quartz",
		"🔹",
		"Common",
		30,
		"Clear and common. Smelts into glass or refined crystal.",
		Color3.fromRGB(230, 240, 255)
	),
	gem("amethyst", "Amethyst", "💜", "Uncommon", 110, "A purple variety of quartz.", Color3.fromRGB(160, 100, 220)),
	gem("topaz", "Topaz", "🟡", "Uncommon", 90, "Warm golden crystal.", Color3.fromRGB(250, 200, 80)),
	gem("jade", "Jade", "🟢", "Rare", 240, "Prized by collectors and chefs alike.", Color3.fromRGB(80, 190, 120)),
	gem("aquamarine", "Aquamarine", "🩵", "Rare", 220, "The colour of shallow sea.", Color3.fromRGB(120, 220, 230)),
	gem("ruby", "Ruby", "❤️", "Rare", 320, "Burns red in the light.", Color3.fromRGB(220, 30, 60)),
	gem("sapphire", "Sapphire", "💙", "Rare", 300, "Deep blue and flawless.", Color3.fromRGB(40, 80, 220)),
	gem("emerald", "Emerald", "💚", "Epic", 480, "Green fire.", Color3.fromRGB(30, 180, 90)),
	gem("moonstone", "Moonstone", "🌙", "Epic", 520, "Glows faintly on full moons.", Color3.fromRGB(210, 220, 255)),
	gem("fire_opal", "Fire Opal", "🔥", "Epic", 560, "Flickers like a candle.", Color3.fromRGB(255, 120, 60)),
	gem(
		"diamond",
		"Diamond",
		"💎",
		"Legendary",
		1400,
		"The hardest thing in the valley.",
		Color3.fromRGB(235, 250, 255)
	),
	gem(
		"prismatic_gem",
		"Prismatic Gem",
		"🌈",
		"Mythic",
		6000,
		"Every colour at once. Nobody knows where they come from.",
		Color3.fromRGB(255, 160, 220)
	),

	-- Geode minerals
	mineral("geode_mineral_calcite", "Calcite", "🔸", "Common", 40, "Soft, banded crystal."),
	mineral("geode_mineral_frostite", "Frostite", "❄️", "Uncommon", 90, "Chilly to the touch."),
	mineral("geode_mineral_obsidian", "Obsidian", "⬛", "Uncommon", 110, "Volcanic glass with a razor edge."),
	mineral(
		"geode_mineral_stardrop",
		"Stardrop Crystal",
		"🌟",
		"Legendary",
		1800,
		"A crystal that seems to hold a tiny star."
	),
	mineral("geode_mineral_celestine", "Celestine", "🔷", "Rare", 260, "Sky-blue crystal found on floating islands."),
	mineral("geode_mineral_sunstone", "Sunstone", "🌞", "Rare", 280, "Sparkles with trapped sunlight."),
	mineral("geode_mineral_bismuth", "Bismuth", "🟪", "Epic", 600, "Rainbow staircase crystal."),

	-- Artifacts (archaeology, fishing treasure, secrets)
	artifact(
		"old_coin",
		"Old Coin",
		"🪙",
		"Common",
		60,
		"Minted before the valley had a name.",
		{ "Ruins", "Beach" }
	),
	artifact(
		"clay_pot",
		"Clay Pot Shard",
		"🏺",
		"Common",
		50,
		"Part of a painted storage jar.",
		{ "Ruins", "Forest" }
	),
	artifact(
		"arrowhead",
		"Flint Arrowhead",
		"🔺",
		"Common",
		55,
		"Chipped by a skilled hand.",
		{ "Forest", "Mountains" }
	),
	artifact(
		"fossil_shell",
		"Spiral Shell Fossil",
		"🐚",
		"Uncommon",
		140,
		"An ancient sea creature. The valley was once an ocean.",
		{ "Beach", "Dunewind" }
	),
	artifact(
		"fossil_fish",
		"Fossil Fish",
		"🐟",
		"Rare",
		300,
		"Perfectly preserved in stone.",
		{ "Frostveil", "Dunewind" }
	),
	artifact(
		"fossil_fern",
		"Fossil Fern",
		"🌿",
		"Uncommon",
		160,
		"A frond from a forest older than time.",
		{ "Forest", "Mountains" }
	),
	artifact("dino_egg", "Petrified Egg", "🥚", "Epic", 900, "Something enormous laid this.", { "Dunewind" }),
	artifact(
		"farmers_sickle",
		"Ancient Sickle",
		"🌙",
		"Uncommon",
		180,
		"The first farmers of Evergrove used these.",
		{ "Ruins", "HollowFarm" }
	),
	artifact("stone_tablet", "Glyph Tablet", "🪧", "Rare", 320, "Covered in growing-season glyphs.", { "Ruins" }),
	artifact(
		"golden_idol",
		"Golden Idol",
		"🗿",
		"Epic",
		1200,
		"A figure holding a sheaf of wheat.",
		{ "Ruins", "Dunewind" }
	),
	artifact("sky_compass", "Sky Compass", "🧭", "Rare", 420, "Always points up.", { "Skyreach" }),
	artifact("frozen_tear", "Frozen Tear", "💧", "Rare", 380, "A droplet that never thaws.", { "Frostveil" }),
	artifact(
		"crystal_skull",
		"Crystal Skull",
		"💀",
		"Legendary",
		2600,
		"It seems to be smiling.",
		{ "CrystalCaverns" }
	),
	artifact(
		"seed_vault_key",
		"Seed Vault Key",
		"🗝️",
		"Legendary",
		2000,
		"Opens something under the ruins.",
		{ "Ruins" }
	),
	artifact(
		"rusty_spur",
		"Rusty Spur",
		"⭐",
		"Common",
		45,
		"From a rancher long gone.",
		{ "HollowFarm", "Dunewind" }
	),
	artifact(
		"ghost_lantern",
		"Ghost Lantern",
		"🏮",
		"Epic",
		1100,
		"Still flickers with a blue flame.",
		{ "HollowFarm" }
	),
	artifact("mermaid_comb", "Mermaid's Comb", "🧜", "Epic", 950, "Carved from pearl.", { "Beach" }),
	artifact(
		"meteor_fragment",
		"Iron Meteorite",
		"☄️",
		"Rare",
		500,
		"Heavier than it looks.",
		{ "Mountains", "Skyreach" }
	),
}

return {
	List = List,
}

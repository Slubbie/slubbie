-- Crafting and cooking recipes.
--
--   In        list of { itemId, count }; "#Tag" means any item with that tag
--             (e.g. { "#Fish", 2 } = any two fish)
--   Station   Hand (anywhere) · Workbench (your farm yard) · Workshop · Kitchen · Alchemy
--   Unlock    how the recipe is learned:
--               Default = true               known from the start
--               Skill = { "Crafting", 5 }    reach that skill level
--               Friend = { "pip", 4 }        reach that many hearts with an NPC
--               Quest = "questId"            quest reward
--               Book = true                  taught by a recipe book item (Config/Items)
--               Festival = "festivalId"      festival shop / prize
--               Secret = true                discovered by experimenting in the crafting menu
--   Category  catalog tab

export type Recipe = {
	Id: string,
	Out: string,
	N: number,
	In: { { any } },
	Station: string,
	Unlock: { [string]: any },
	Category: string,
	XP: number,
	Skill: string,
}

local List: { Recipe } = {}

local function r(
	id: string,
	out: string?,
	n: number?,
	inputs: { { any } },
	station: string,
	unlock: any,
	category: string,
	skill: string?
)
	table.insert(List, {
		Id = id,
		Out = out or id,
		N = n or 1,
		In = inputs,
		Station = station,
		Unlock = unlock,
		Category = category,
		Skill = skill or (if station == "Kitchen" then "Cooking" else "Crafting"),
		XP = 0, -- filled below from input value
	})
end

local DEFAULT = { Default = true }
local function skill(name: string, level: number)
	return { Skill = { name, level } }
end
local function friend(npc: string, hearts: number)
	return { Friend = { npc, hearts } }
end
local BOOK = { Book = true }
local SECRET = { Secret = true }

-- Construction & components ------------------------------------------------------------------------
r("plank", nil, 1, { { "wood", 2 } }, "Workbench", DEFAULT, "Components")
r("stone_brick", nil, 1, { { "stone", 3 } }, "Workbench", DEFAULT, "Components")
r("rope", nil, 1, { { "fiber", 5 } }, "Hand", DEFAULT, "Components")
r("hay", nil, 2, { { "fiber", 10 } }, "Hand", DEFAULT, "Animal Care", "Ranching")
r("gear", nil, 1, { { "iron_bar", 2 } }, "Workshop", skill("Crafting", 6), "Components")
r(
	"battery",
	nil,
	1,
	{ { "copper_bar", 2 }, { "coal", 5 }, { "gold_ore", 1 } },
	"Workshop",
	skill("Crafting", 12),
	"Components"
)
r(
	"circuit",
	nil,
	1,
	{ { "copper_bar", 2 }, { "gold_bar", 1 }, { "refined_crystal", 1 } },
	"Workshop",
	BOOK,
	"Components"
)
r("motor", nil, 1, { { "gear", 3 }, { "copper_bar", 5 }, { "battery", 1 } }, "Workshop", BOOK, "Components")
r(
	"solar_cell",
	nil,
	1,
	{ { "glass", 5 }, { "gold_bar", 1 }, { "refined_crystal", 1 } },
	"Workshop",
	skill("Crafting", 20),
	"Components"
)
r(
	"drone_core",
	nil,
	1,
	{ { "circuit", 2 }, { "motor", 2 }, { "solar_cell", 1 }, { "refined_crystal", 2 } },
	"Workshop",
	skill("Crafting", 24),
	"Components"
)

-- Farming supplies -------------------------------------------------------------------------------------
r("compost", nil, 2, { { "fiber", 5 }, { "sap", 1 } }, "Hand", DEFAULT, "Farming", "Farming")
r("compost_from_crops", "compost", 3, { { "#Crop", 3 } }, "Hand", DEFAULT, "Farming", "Farming")
r(
	"basic_fertilizer",
	nil,
	2,
	{ { "sap", 2 }, { "compost", 1 } },
	"Workbench",
	skill("Farming", 2),
	"Farming",
	"Farming"
)
r(
	"quality_fertilizer",
	nil,
	2,
	{ { "#Fish", 1 }, { "sap", 2 }, { "compost", 2 } },
	"Workbench",
	skill("Farming", 5),
	"Farming",
	"Farming"
)
r(
	"deluxe_fertilizer",
	nil,
	5,
	{ { "refined_crystal", 1 }, { "quality_fertilizer", 5 }, { "bone_meal", 2 } },
	"Workshop",
	skill("Farming", 12),
	"Farming",
	"Farming"
)
r("speed_gro", nil, 2, { { "pinecone", 2 }, { "moss", 2 } }, "Workbench", skill("Farming", 3), "Farming", "Farming")
r(
	"deluxe_speed_gro",
	nil,
	3,
	{ { "coffee", 2 }, { "speed_gro", 3 } },
	"Workbench",
	skill("Farming", 8),
	"Farming",
	"Farming"
)
r(
	"hyper_speed_gro",
	nil,
	5,
	{ { "ember_core", 1 }, { "deluxe_speed_gro", 5 } },
	"Workshop",
	skill("Farming", 15),
	"Farming",
	"Farming"
)
r("hydro_gel", nil, 2, { { "clay", 3 }, { "seaweed", 2 } }, "Workbench", skill("Farming", 4), "Farming", "Farming")
r("nitro_mix", nil, 2, { { "bug_bits", 3 }, { "fiber", 3 } }, "Workbench", friend("rosalind", 2), "Farming", "Farming")
r("bone_meal", nil, 3, { { "#Fish", 1 }, { "stone", 3 } }, "Workbench", friend("rosalind", 3), "Farming", "Farming")
r("potash", nil, 3, { { "coal", 1 }, { "wood", 5 } }, "Workbench", friend("rosalind", 2), "Farming", "Farming")
r(
	"mutagen",
	nil,
	2,
	{ { "crystal_shard", 1 }, { "whisperleaf", 1 }, { "bug_bits", 5 } },
	"Workshop",
	BOOK,
	"Farming",
	"Farming"
)
r("golden_dust", nil, 2, { { "gold_bar", 1 }, { "topaz", 1 } }, "Workshop", skill("Farming", 16), "Farming", "Farming")
r(
	"crystal_dust",
	nil,
	2,
	{ { "crystal_shard", 2 }, { "quartz", 2 } },
	"Workshop",
	friend("juniper", 4),
	"Farming",
	"Farming"
)
r(
	"stardust",
	nil,
	5,
	{ { "stardust_powder", 1 }, { "compost", 5 } },
	"Workshop",
	friend("luna", 4),
	"Farming",
	"Farming"
)
r("prism_fertilizer", nil, 5, { { "prism_shard", 1 }, { "compost", 5 } }, "Workshop", SECRET, "Farming", "Farming")
r(
	"ruin_dust",
	nil,
	3,
	{ { "ancient_herb", 1 }, { "clay", 5 } },
	"Workbench",
	friend("beatrix", 4),
	"Farming",
	"Farming"
)
r(
	"frost_salt",
	nil,
	3,
	{ { "frost_crystal", 1 }, { "salt", 3 } },
	"Workbench",
	skill("Farming", 10),
	"Farming",
	"Farming"
)
r("fire_ash", nil, 3, { { "ember_core", 1 }, { "coal", 3 } }, "Workbench", skill("Farming", 10), "Farming", "Farming")
r("giant_grow", nil, 2, { { "bone_meal", 3 }, { "pumpkin", 1 } }, "Workbench", friend("mayor", 5), "Farming", "Farming")
r("moon_mulch", nil, 3, { { "moon_petal", 2 }, { "compost", 3 } }, "Workbench", SECRET, "Farming", "Farming")
r("cloud_soil", nil, 5, { { "cloud_essence", 2 }, { "compost", 5 } }, "Workshop", BOOK, "Farming", "Farming")
r("pest_spray", nil, 3, { { "spice_berry", 2 }, { "sap", 1 } }, "Workbench", skill("Farming", 4), "Farming", "Farming")
r(
	"pest_spray_pepper",
	"pest_spray",
	3,
	{ { "hot_pepper", 2 }, { "sap", 1 } },
	"Workbench",
	skill("Farming", 4),
	"Farming",
	"Farming"
)
r("fungicide", nil, 3, { { "garlic", 2 }, { "sap", 1 } }, "Workbench", skill("Farming", 5), "Farming", "Farming")

-- Fishing ------------------------------------------------------------------------------------------------
r("bait", nil, 5, { { "bug_bits", 1 } }, "Hand", DEFAULT, "Fishing", "Fishing")
r("bait_worms", "bait", 5, { { "worm", 2 } }, "Hand", DEFAULT, "Fishing", "Fishing")
r("glow_bait", nil, 5, { { "glowcap", 1 }, { "bait", 5 } }, "Workbench", skill("Fishing", 6), "Fishing", "Fishing")
r("magnet_bait", nil, 10, { { "iron_bar", 1 }, { "bait", 10 } }, "Workbench", friend("finn", 3), "Fishing", "Fishing")
r(
	"deluxe_bait",
	nil,
	10,
	{ { "bait", 10 }, { "gold_ore", 2 } },
	"Workbench",
	skill("Fishing", 12),
	"Fishing",
	"Fishing"
)
r(
	"legend_lure",
	nil,
	1,
	{ { "prism_shard", 1 }, { "deluxe_bait", 10 }, { "pearl", 1 } },
	"Workshop",
	SECRET,
	"Fishing",
	"Fishing"
)
r("fish_food", nil, 5, { { "bug_bits", 2 }, { "seaweed", 1 } }, "Hand", skill("Fishing", 2), "Fishing", "Fishing")

-- Animal care ----------------------------------------------------------------------------------------------
r(
	"animal_feed",
	nil,
	4,
	{ { "wheat", 2 }, { "corn", 1 } },
	"Workbench",
	skill("Ranching", 2),
	"Animal Care",
	"Ranching"
)
r(
	"treat",
	nil,
	3,
	{ { "animal_feed", 2 }, { "#Honey", 1 } },
	"Workbench",
	friend("hattie", 3),
	"Animal Care",
	"Ranching"
)

-- Travel & utility ---------------------------------------------------------------------------------------------
r(
	"warp_home",
	nil,
	1,
	{ { "wood", 10 }, { "fiber", 10 }, { "sap", 5 } },
	"Hand",
	skill("Exploration", 3),
	"Utility",
	"Exploration"
)
r(
	"warp_town",
	nil,
	1,
	{ { "stone", 10 }, { "fiber", 10 }, { "sap", 5 } },
	"Hand",
	skill("Exploration", 4),
	"Utility",
	"Exploration"
)
r(
	"rain_totem",
	nil,
	1,
	{ { "wood", 10 }, { "sap", 5 }, { "seaweed", 2 } },
	"Workbench",
	skill("Foraging", 6),
	"Utility",
	"Foraging"
)

-- Placeables ------------------------------------------------------------------------------------------------------
r("chest", nil, 1, { { "wood", 30 } }, "Workbench", DEFAULT, "Storage")
r("big_chest", nil, 1, { { "hardwood", 10 }, { "chest", 1 } }, "Workbench", skill("Crafting", 4), "Storage")
r("scarecrow", nil, 1, { { "wood", 20 }, { "fiber", 20 } }, "Workbench", skill("Farming", 2), "Automation", "Farming")
r(
	"sprinkler",
	nil,
	1,
	{ { "copper_bar", 1 }, { "iron_ore", 2 } },
	"Workbench",
	skill("Farming", 3),
	"Automation",
	"Farming"
)
r(
	"quality_sprinkler",
	nil,
	1,
	{ { "iron_bar", 1 }, { "gold_ore", 2 }, { "glass", 2 } },
	"Workbench",
	skill("Farming", 6),
	"Automation",
	"Farming"
)
r(
	"crystal_sprinkler",
	nil,
	1,
	{ { "gold_bar", 1 }, { "refined_crystal", 2 }, { "battery", 1 } },
	"Workshop",
	skill("Farming", 12),
	"Automation",
	"Farming"
)
r(
	"mist_tower",
	nil,
	1,
	{ { "crystal_sprinkler", 2 }, { "motor", 1 }, { "circuit", 1 } },
	"Workshop",
	skill("Farming", 18),
	"Automation",
	"Farming"
)
r(
	"lightning_rod",
	nil,
	1,
	{ { "iron_bar", 1 }, { "copper_bar", 3 }, { "glass", 1 } },
	"Workbench",
	skill("Crafting", 6),
	"Automation"
)
r(
	"celestial_beacon",
	nil,
	1,
	{ { "stardust_powder", 2 }, { "refined_crystal", 3 }, { "starsteel_bar", 1 } },
	"Workshop",
	BOOK,
	"Automation"
)
r(
	"auto_feeder",
	nil,
	1,
	{ { "iron_bar", 5 }, { "gear", 2 } },
	"Workshop",
	skill("Ranching", 8),
	"Automation",
	"Ranching"
)
r(
	"product_collector",
	nil,
	1,
	{ { "iron_bar", 5 }, { "gear", 2 }, { "circuit", 1 } },
	"Workshop",
	skill("Ranching", 10),
	"Automation",
	"Ranching"
)
r(
	"harvest_drone_hub",
	nil,
	1,
	{ { "drone_core", 1 }, { "iron_bar", 10 }, { "circuit", 2 } },
	"Workshop",
	BOOK,
	"Automation"
)
r(
	"farmbot",
	nil,
	1,
	{ { "drone_core", 1 }, { "motor", 2 }, { "circuit", 3 }, { "starsteel_bar", 2 } },
	"Workshop",
	skill("Crafting", 26),
	"Automation"
)
r(
	"logistics_hub",
	nil,
	1,
	{ { "circuit", 2 }, { "gear", 5 }, { "iron_bar", 10 } },
	"Workshop",
	skill("Crafting", 16),
	"Automation"
)
r(
	"farm_controller",
	nil,
	1,
	{ { "circuit", 4 }, { "refined_crystal", 2 }, { "solar_cell", 1 } },
	"Workshop",
	skill("Crafting", 20),
	"Automation"
)
r("solar_array", nil, 1, { { "solar_cell", 4 }, { "iron_bar", 6 } }, "Workshop", skill("Crafting", 14), "Automation")
r(
	"magic_planter",
	nil,
	1,
	{ { "clay", 20 }, { "refined_crystal", 1 }, { "whisperleaf", 2 } },
	"Workshop",
	skill("Farming", 10),
	"Buildings",
	"Farming"
)
r(
	"genetics_lab",
	nil,
	1,
	{ { "glass", 20 }, { "circuit", 1 }, { "refined_crystal", 2 }, { "hardwood", 20 } },
	"Workshop",
	BOOK,
	"Buildings",
	"Farming"
)
r("alchemy_table", nil, 1, { { "hardwood", 10 }, { "glass", 5 }, { "whisperleaf", 1 } }, "Workbench", BOOK, "Buildings")

-- Machines -----------------------------------------------------------------------------------------------------------
r(
	"preserves_jar",
	nil,
	1,
	{ { "wood", 30 }, { "stone", 20 }, { "coal", 3 } },
	"Workbench",
	skill("Crafting", 2),
	"Machines"
)
r(
	"fermenter",
	nil,
	1,
	{ { "hardwood", 10 }, { "copper_bar", 1 }, { "sap", 5 } },
	"Workbench",
	skill("Crafting", 5),
	"Machines"
)
r(
	"juicer",
	nil,
	1,
	{ { "copper_bar", 2 }, { "glass", 2 }, { "wood", 10 } },
	"Workbench",
	skill("Crafting", 3),
	"Machines"
)
r(
	"dehydrator",
	nil,
	1,
	{ { "wood", 20 }, { "clay", 10 }, { "copper_bar", 2 } },
	"Workbench",
	skill("Crafting", 6),
	"Machines"
)
r(
	"mill",
	nil,
	1,
	{ { "plank", 20 }, { "stone_brick", 20 }, { "gear", 1 } },
	"Workshop",
	skill("Crafting", 3),
	"Machines"
)
r(
	"cheese_press",
	nil,
	1,
	{ { "wood", 30 }, { "stone", 30 }, { "hardwood", 5 }, { "copper_bar", 1 } },
	"Workbench",
	skill("Ranching", 4),
	"Machines",
	"Ranching"
)
r(
	"butter_churn",
	nil,
	1,
	{ { "wood", 25 }, { "copper_bar", 1 } },
	"Workbench",
	skill("Ranching", 3),
	"Machines",
	"Ranching"
)
r(
	"mayo_mixer",
	nil,
	1,
	{ { "wood", 20 }, { "stone", 20 }, { "copper_bar", 1 } },
	"Workbench",
	skill("Ranching", 3),
	"Machines",
	"Ranching"
)
r("loom", nil, 1, { { "wood", 40 }, { "fiber", 30 }, { "sap", 10 } }, "Workbench", skill("Crafting", 5), "Machines")
r(
	"oil_press",
	nil,
	1,
	{ { "hardwood", 10 }, { "iron_bar", 1 }, { "gear", 1 } },
	"Workshop",
	skill("Crafting", 6),
	"Machines"
)
r(
	"smoker",
	nil,
	1,
	{ { "stone", 40 }, { "coal", 10 }, { "copper_bar", 2 } },
	"Workbench",
	skill("Fishing", 5),
	"Machines",
	"Fishing"
)
r(
	"syrup_boiler",
	nil,
	1,
	{ { "copper_bar", 3 }, { "stone", 20 } },
	"Workbench",
	skill("Foraging", 6),
	"Machines",
	"Foraging"
)
r(
	"canning_station",
	nil,
	1,
	{ { "iron_bar", 2 }, { "glass", 4 }, { "gear", 1 } },
	"Workshop",
	skill("Crafting", 8),
	"Machines"
)
r(
	"perfumery",
	nil,
	1,
	{ { "glass", 6 }, { "copper_bar", 3 }, { "gold_bar", 1 } },
	"Workshop",
	friend("ivy", 4),
	"Machines"
)
r("flower_press", nil, 1, { { "wood", 20 }, { "plank", 5 } }, "Workbench", friend("ivy", 2), "Machines")
r("furnace", nil, 1, { { "copper_ore", 20 }, { "stone", 25 } }, "Workbench", DEFAULT, "Machines", "Mining")
r(
	"crystal_refinery",
	nil,
	1,
	{ { "crystal_shard", 5 }, { "iron_bar", 5 }, { "gold_bar", 1 } },
	"Workshop",
	skill("Mining", 12),
	"Machines",
	"Mining"
)
r(
	"seed_maker",
	nil,
	1,
	{ { "wood", 25 }, { "coal", 10 }, { "gold_bar", 1 } },
	"Workbench",
	skill("Farming", 5),
	"Machines",
	"Farming"
)
r(
	"honey_extractor",
	nil,
	1,
	{ { "wood", 20 }, { "iron_bar", 1 } },
	"Workbench",
	skill("Ranching", 5),
	"Machines",
	"Ranching"
)
r(
	"alchemy_still",
	nil,
	1,
	{ { "glass", 10 }, { "gold_bar", 2 }, { "whisperleaf", 2 } },
	"Workshop",
	skill("Crafting", 12),
	"Machines"
)
r(
	"grand_kitchen",
	nil,
	1,
	{ { "motor", 2 }, { "circuit", 2 }, { "iron_bar", 20 }, { "glass", 10 } },
	"Workshop",
	skill("Crafting", 16),
	"Machines"
)

-- Cooking --------------------------------------------------------------------------------------------------------------
r("garden_salad", nil, 1, { { "lettuce", 1 }, { "#Vegetable", 1 } }, "Kitchen", DEFAULT, "Cooking")
r("carrot_soup", nil, 1, { { "carrot", 3 }, { "onion", 1 } }, "Kitchen", DEFAULT, "Cooking")
r("baked_potato", nil, 1, { { "potato", 1 }, { "butter", 1 } }, "Kitchen", skill("Cooking", 2), "Cooking")
r("veggie_stew", nil, 1, { { "#Vegetable", 4 }, { "potato", 1 } }, "Kitchen", BOOK, "Cooking")
r("bread", nil, 1, { { "flour", 2 } }, "Kitchen", DEFAULT, "Cooking")
r("pancakes", nil, 1, { { "flour", 1 }, { "#Egg", 1 }, { "milk", 1 } }, "Kitchen", skill("Cooking", 3), "Cooking")
r(
	"pumpkin_pie",
	nil,
	1,
	{ { "pumpkin", 1 }, { "flour", 1 }, { "sugar", 1 }, { "#Egg", 1 } },
	"Kitchen",
	BOOK,
	"Cooking"
)
r("apple_pie", nil, 1, { { "apple", 2 }, { "flour", 1 }, { "sugar", 1 }, { "butter", 1 } }, "Kitchen", BOOK, "Cooking")
r("berry_tart", nil, 1, { { "#Berry", 3 }, { "flour", 1 }, { "sugar", 1 } }, "Kitchen", BOOK, "Cooking")
r("omelette", nil, 1, { { "#Egg", 2 }, { "milk", 1 } }, "Kitchen", DEFAULT, "Cooking")
r(
	"fried_rice",
	nil,
	1,
	{ { "rice", 2 }, { "#Egg", 1 }, { "#Vegetable", 1 } },
	"Kitchen",
	skill("Cooking", 4),
	"Cooking"
)
r("pizza", nil, 1, { { "flour", 1 }, { "tomato", 2 }, { "cheese", 1 } }, "Kitchen", friend("marco", 3), "Cooking")
r("fish_stew", nil, 1, { { "#Fish", 2 }, { "potato", 1 }, { "tomato", 1 } }, "Kitchen", friend("finn", 4), "Cooking")
r("grilled_fish", nil, 1, { { "#Fish", 1 } }, "Kitchen", DEFAULT, "Cooking")
r("sushi_roll", nil, 1, { { "rice", 1 }, { "#Fish", 1 }, { "seaweed", 1 } }, "Kitchen", skill("Cooking", 8), "Cooking")
r(
	"miners_pie",
	nil,
	1,
	{ { "flour", 1 }, { "potato", 2 }, { "butter", 1 }, { "#Mushroom", 1 } },
	"Kitchen",
	friend("bram", 4),
	"Cooking"
)
r("trail_mix", nil, 1, { { "#Nut", 3 }, { "#Berry", 2 } }, "Kitchen", friend("rook", 2), "Cooking")
r(
	"mushroom_risotto",
	nil,
	1,
	{ { "rice", 2 }, { "#Mushroom", 3 }, { "butter", 1 } },
	"Kitchen",
	skill("Cooking", 12),
	"Cooking"
)
r(
	"cheese_platter",
	nil,
	1,
	{ { "cheese", 1 }, { "goat_cheese", 1 }, { "grape", 2 } },
	"Kitchen",
	friend("marco", 6),
	"Cooking"
)
r(
	"strawberry_shortcake",
	nil,
	1,
	{ { "strawberry", 3 }, { "flour", 1 }, { "sugar", 1 }, { "milk", 1 } },
	"Kitchen",
	friend("pip", 5),
	"Cooking"
)
r("hot_chocolate", nil, 1, { { "milk", 2 }, { "sugar", 1 } }, "Kitchen", skill("Cooking", 2), "Cooking")
r("honey_toast", nil, 1, { { "bread", 1 }, { "#Honey", 1 } }, "Kitchen", skill("Cooking", 3), "Cooking")
r("tomato_soup", nil, 1, { { "tomato", 3 }, { "basil", 1 } }, "Kitchen", skill("Cooking", 3), "Cooking")
r("sweet_potato_fries", nil, 1, { { "sweet_potato", 2 }, { "#Oil", 1 } }, "Kitchen", skill("Cooking", 5), "Cooking")
r("chilled_melon", nil, 1, { { "melon", 1 }, { "watermelon", 1 } }, "Kitchen", skill("Cooking", 6), "Cooking")
r("golden_loaf", nil, 1, { { "golden_flour", 2 }, { "butter", 1 } }, "Kitchen", skill("Cooking", 15), "Cooking")
r(
	"starfruit_sorbet",
	nil,
	1,
	{ { "starfruit", 1 }, { "sugar", 2 }, { "milk", 1 } },
	"Kitchen",
	skill("Cooking", 12),
	"Cooking"
)
r(
	"celestial_feast",
	nil,
	1,
	{ { "celestial_vine", 1 }, { "starlight_flour", 1 }, { "moon_cheese", 1 } },
	"Kitchen",
	SECRET,
	"Cooking"
)
r(
	"forager_salad",
	nil,
	1,
	{ { "wild_leek", 1 }, { "dandelion", 1 }, { "#Mushroom", 1 } },
	"Kitchen",
	skill("Foraging", 4),
	"Cooking"
)
r("campfire_stew", nil, 1, { { "#Mushroom", 1 }, { "#Vegetable", 2 } }, "Hand", skill("Exploration", 5), "Cooking")

-- Alchemy ------------------------------------------------------------------------------------------------------------------
r("energy_tonic", nil, 1, { { "whisperleaf", 1 }, { "#Juice", 1 } }, "Alchemy", BOOK, "Potions")
r("glow_potion", nil, 1, { { "glowcap", 2 }, { "whisperleaf", 1 } }, "Alchemy", BOOK, "Potions")
r(
	"growth_elixir",
	nil,
	1,
	{ { "whisperleaf", 2 }, { "deluxe_speed_gro", 2 }, { "refined_crystal", 1 } },
	"Alchemy",
	skill("Crafting", 14),
	"Potions"
)
r(
	"luck_potion",
	nil,
	1,
	{ { "lucky_foot", 1 }, { "whisperleaf", 2 }, { "#Mystic", 1 } },
	"Alchemy",
	friend("wisp", 4),
	"Potions"
)
r("anglers_draught", nil, 1, { { "whisperleaf", 1 }, { "#Fish", 2 } }, "Alchemy", friend("finn", 6), "Potions")
r(
	"miners_tonic",
	nil,
	1,
	{ { "whisperleaf", 1 }, { "coal", 3 }, { "topaz", 1 } },
	"Alchemy",
	friend("bram", 6),
	"Potions"
)
r("fire_tonic", nil, 1, { { "ember_pepper", 2 }, { "whisperleaf", 1 } }, "Alchemy", skill("Exploration", 10), "Potions")
r(
	"frost_tonic",
	nil,
	1,
	{ { "frost_crystal", 1 }, { "whisperleaf", 1 } },
	"Alchemy",
	skill("Exploration", 10),
	"Potions"
)
r(
	"mutation_serum",
	nil,
	1,
	{ { "mutagen", 3 }, { "prism_shard", 1 }, { "whisperleaf", 3 } },
	"Alchemy",
	SECRET,
	"Potions"
)
r("speed_potion", nil, 1, { { "roasted_coffee", 2 }, { "whisperleaf", 1 } }, "Alchemy", skill("Crafting", 9), "Potions")
r(
	"friendship_perfume",
	nil,
	1,
	{ { "#Perfume", 1 }, { "rose", 3 }, { "whisperleaf", 1 } },
	"Alchemy",
	friend("ivy", 8),
	"Potions"
)

return {
	List = List,
	Stations = {
		Hand = { Name = "Anywhere", Icon = "✋" },
		Workbench = { Name = "Workbench", Icon = "🪚" },
		Workshop = { Name = "Workshop", Icon = "🛠️" },
		Kitchen = { Name = "Kitchen", Icon = "🍳" },
		Alchemy = { Name = "Alchemy Table", Icon = "⚗️" },
	},
	-- Studs from a station you must be to use it (Hand works anywhere).
	StationRange = 18,
	-- XP per craft = sum of input values × this, at least 2.
	XPPerValue = 0.05,
	-- Experimenting with a combination that isn't a secret recipe gives a hint
	-- after this many failed attempts.
	HintAfter = 5,
	MaxExperimentItems = 4,
	MaxBatch = 99,
}

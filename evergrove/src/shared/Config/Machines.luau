-- Artisan machines and their processing recipes.
--
-- A machine is a placeable (see Config/Placeables, Machine = <id>). It has a
-- queue of jobs; each job starts when the previous finishes. Timestamps make
-- this cheap: nothing ticks per machine, the server works out what's done when
-- someone looks or when automation runs, including while you're offline.
--
-- Recipe fields
--   In     { Id = itemId, N = count } or { Tag = "Fruit", N = count } (tag of the input item)
--   Extra  additional fixed inputs, e.g. { { Id = "coal", N = 1 } }
--   Out    item id; "%s" is replaced by the tagged input's id (jam_%s → jam_strawberry)
--   N      output count (default 1)
--   Time   real seconds at level 1
-- Output quality = input quality (× machine level bonus chance to go up a tier).
-- Output mutations = input mutations, so mutated crops make mutated goods.
--
-- Generated products: for "%s" outputs the Registry creates the item from the
-- input crop using the matching Products entry below (name, icon, value formula).

export type Recipe = {
	In: { Id: string?, Tag: string?, N: number },
	Extra: { { Id: string, N: number } }?,
	Out: string,
	N: number?,
	Time: number,
	Level: number?, -- machine level required
}

export type Machine = {
	Id: string,
	Name: string,
	Icon: string,
	Description: string,
	Queue: number, -- job slots at level 1
	Output: number, -- output storage at level 1
	Recipes: { Recipe },
	Skill: string,
	Anim: string, -- client animation style: Spin, Bubble, Press, Heat, Loom, Sparkle
}

-- Generated product templates. Value = input value × Mult + Add.
local Products = {
	jam = { Name = "%s Jam", Icon = "🫙", Mult = 2, Add = 40, Category = "Artisan", Tags = { "Artisan", "Preserve" } },
	pickles = {
		Name = "Pickled %s",
		Icon = "🥫",
		Mult = 2,
		Add = 40,
		Category = "Artisan",
		Tags = { "Artisan", "Preserve" },
	},
	wine = {
		Name = "%s Wine",
		Icon = "🍷",
		Mult = 3,
		Add = 0,
		Category = "Artisan",
		Tags = { "Artisan", "Wine", "Brew" },
	},
	juice = {
		Name = "%s Juice",
		Icon = "🧃",
		Mult = 2.25,
		Add = 0,
		Category = "Artisan",
		Tags = { "Artisan", "Juice" },
		Use = "Drink",
		Energy = 25,
	},
	dried = { Name = "Dried %s", Icon = "🍂", Mult = 7.5, Add = 25, Category = "Artisan", Tags = { "Artisan" } },
	perfume = {
		Name = "%s Perfume",
		Icon = "🧴",
		Mult = 4,
		Add = 60,
		Category = "Artisan",
		Tags = { "Artisan", "Perfume" },
	},
	pressed = {
		Name = "Pressed %s",
		Icon = "📜",
		Mult = 2.5,
		Add = 20,
		Category = "Artisan",
		Tags = { "Artisan", "Pressed" },
	},
	canned = {
		Name = "Canned %s",
		Icon = "🥫",
		Mult = 4,
		Add = 30,
		Category = "Artisan",
		Tags = { "Artisan", "Preserve", "Export", "Canned" },
	},
	smoked = {
		Name = "Smoked %s",
		Icon = "🍢",
		Mult = 2,
		Add = 0,
		Category = "Artisan",
		Tags = { "Artisan", "Smoked" },
	},
	honey = { Name = "%s Honey", Icon = "🍯", Mult = 2, Add = 100, Category = "AnimalProduct", Tags = { "Honey" } },
	oil = { Name = "%s Oil", Icon = "🫗", Mult = 3.2, Add = 20, Category = "Artisan", Tags = { "Artisan", "Oil" } },
	extract = {
		Name = "%s Essence",
		Icon = "⚗️",
		Mult = 3.5,
		Add = 100,
		Category = "Artisan",
		Tags = { "Artisan", "Mystic" },
	},
}

local List: { Machine } = {
	{
		Id = "preserves_jar",
		Name = "Preserves Jar",
		Icon = "🫙",
		Description = "Turns fruit into jam and vegetables into pickles.",
		Queue = 2,
		Output = 12,
		Skill = "Crafting",
		Anim = "Bubble",
		Recipes = {
			{ In = { Tag = "Fruit", N = 1 }, Out = "jam_%s", Time = 240 },
			{ In = { Tag = "Vegetable", N = 1 }, Out = "pickles_%s", Time = 240 },
		},
	},
	{
		Id = "fermenter",
		Name = "Fermenter Keg",
		Icon = "🛢️",
		Description = "Slowly brews fruit into wine, hops into ale, honey into mead.",
		Queue = 2,
		Output = 8,
		Skill = "Crafting",
		Anim = "Bubble",
		Recipes = {
			{ In = { Tag = "Fruit", N = 1 }, Out = "wine_%s", Time = 900 },
			{ In = { Id = "hops", N = 2 }, Out = "pale_ale", Time = 480 },
			{ In = { Tag = "Honey", N = 1 }, Out = "mead", Time = 600 },
			{ In = { Id = "coffee", N = 5 }, Out = "roasted_coffee", Time = 120 },
			{ In = { Id = "tea", N = 2 }, Out = "green_tea", Time = 180 },
		},
	},
	{
		Id = "juicer",
		Name = "Juicer",
		Icon = "🧃",
		Description = "Fast, fresh juice from fruit or vegetables.",
		Queue = 3,
		Output = 16,
		Skill = "Crafting",
		Anim = "Spin",
		Recipes = {
			{ In = { Tag = "Fruit", N = 1 }, Out = "juice_%s", Time = 90 },
			{ In = { Tag = "Vegetable", N = 1 }, Out = "juice_%s", Time = 90 },
		},
	},
	{
		Id = "dehydrator",
		Name = "Dehydrator",
		Icon = "🍂",
		Description = "Dries five fruits or mushrooms into a long-lasting snack.",
		Queue = 2,
		Output = 10,
		Skill = "Crafting",
		Anim = "Heat",
		Recipes = {
			{ In = { Tag = "Fruit", N = 5 }, Out = "dried_%s", Time = 420 },
			{ In = { Tag = "Mushroom", N = 5 }, Out = "dried_%s", Time = 420 },
		},
	},
	{
		Id = "mill",
		Name = "Mill",
		Icon = "🌾",
		Description = "Grinds grain into flour.",
		Queue = 4,
		Output = 40,
		Skill = "Crafting",
		Anim = "Spin",
		Recipes = {
			{ In = { Id = "wheat", N = 2 }, Out = "flour", Time = 60 },
			{ In = { Id = "corn", N = 1 }, Out = "cornmeal", Time = 60 },
			{ In = { Id = "rice", N = 2 }, Out = "rice_flour", Time = 60 },
			{ In = { Id = "golden_wheat", N = 2 }, Out = "golden_flour", Time = 180 },
			{ In = { Id = "starlight_wheat", N = 2 }, Out = "starlight_flour", Time = 600 },
			{ In = { Id = "sugarcane", N = 2 }, Out = "sugar", Time = 90 },
			{ In = { Id = "wheat", N = 3 }, Out = "hay", N = 4, Time = 30 },
		},
	},
	{
		Id = "cheese_press",
		Name = "Cheese Press",
		Icon = "🧀",
		Description = "Presses milk into cheese.",
		Queue = 2,
		Output = 10,
		Skill = "Ranching",
		Anim = "Press",
		Recipes = {
			{ In = { Id = "milk", N = 1 }, Out = "cheese", Time = 300 },
			{ In = { Id = "goat_milk", N = 1 }, Out = "goat_cheese", Time = 360 },
			{ In = { Id = "moon_milk", N = 1 }, Out = "moon_cheese", Time = 600 },
		},
	},
	{
		Id = "butter_churn",
		Name = "Butter Churn",
		Icon = "🧈",
		Description = "Churns milk into butter.",
		Queue = 2,
		Output = 10,
		Skill = "Ranching",
		Anim = "Press",
		Recipes = { { In = { Id = "milk", N = 1 }, Out = "butter", Time = 180 } },
	},
	{
		Id = "mayo_mixer",
		Name = "Mayo Mixer",
		Icon = "🥚",
		Description = "Whips eggs into mayonnaise.",
		Queue = 3,
		Output = 16,
		Skill = "Ranching",
		Anim = "Spin",
		Recipes = {
			{ In = { Id = "egg", N = 1 }, Out = "mayonnaise", Time = 150 },
			{ In = { Id = "brown_egg", N = 1 }, Out = "mayonnaise", Time = 150 },
			{ In = { Id = "duck_egg", N = 1 }, Out = "mayonnaise", N = 2, Time = 180 },
			{ In = { Id = "golden_egg", N = 1 }, Out = "golden_mayo", Time = 300 },
		},
	},
	{
		Id = "loom",
		Name = "Loom",
		Icon = "🧵",
		Description = "Weaves wool, fiber and silk into cloth.",
		Queue = 2,
		Output = 10,
		Skill = "Crafting",
		Anim = "Loom",
		Recipes = {
			{ In = { Id = "wool", N = 1 }, Out = "cloth", Time = 240 },
			{ In = { Id = "cotton", N = 3 }, Out = "cloth", Time = 240 },
			{ In = { Id = "alpaca_fiber", N = 1 }, Out = "fine_cloth", Time = 300 },
			{ In = { Id = "moonsilk", N = 1 }, Out = "silk_cloth", Time = 480 },
			{ In = { Id = "cloud_wool", N = 1 }, Out = "fine_cloth", N = 3, Time = 360 },
			{ In = { Id = "fiber", N = 10 }, Out = "rope", Time = 45 },
		},
	},
	{
		Id = "oil_press",
		Name = "Oil Press",
		Icon = "🫗",
		Description = "Presses oilseeds and truffles into oil.",
		Queue = 2,
		Output = 10,
		Skill = "Crafting",
		Anim = "Press",
		Recipes = {
			{ In = { Tag = "Oilseed", N = 1 }, Out = "oil_%s", Time = 240 },
			{ In = { Id = "truffle", N = 1 }, Out = "truffle_oil", Time = 300 },
		},
	},
	{
		Id = "smoker",
		Name = "Smoker",
		Icon = "🔥",
		Description = "Smokes fish over coal, doubling its value.",
		Queue = 3,
		Output = 12,
		Skill = "Fishing",
		Anim = "Heat",
		Recipes = {
			{ In = { Tag = "Fish", N = 1 }, Extra = { { Id = "coal", N = 1 } }, Out = "smoked_%s", Time = 180 },
		},
	},
	{
		Id = "syrup_boiler",
		Name = "Syrup Boiler",
		Icon = "🍁",
		Description = "Boils sap down to syrup, and cane into candy.",
		Queue = 2,
		Output = 10,
		Skill = "Crafting",
		Anim = "Bubble",
		Recipes = {
			{ In = { Id = "maple_sap", N = 4 }, Out = "maple_syrup", Time = 360 },
			{
				In = { Id = "cloud_essence", N = 1 },
				Extra = { { Id = "sugar", N = 2 } },
				Out = "cloud_candy",
				Time = 300,
			},
		},
	},
	{
		Id = "canning_station",
		Name = "Canning Station",
		Icon = "🥫",
		Description = "Cans three vegetables together: shelf-stable and loved by exporters.",
		Queue = 2,
		Output = 12,
		Skill = "Crafting",
		Anim = "Press",
		Recipes = { { In = { Tag = "Vegetable", N = 3 }, Out = "canned_%s", Time = 300 } },
	},
	{
		Id = "perfumery",
		Name = "Perfume Still",
		Icon = "🧴",
		Description = "Distils five flowers into perfume.",
		Queue = 2,
		Output = 8,
		Skill = "Crafting",
		Anim = "Bubble",
		Recipes = { { In = { Tag = "Flower", N = 5 }, Out = "perfume_%s", Time = 600 } },
	},
	{
		Id = "flower_press",
		Name = "Flower Press",
		Icon = "📜",
		Description = "Presses a flower into a keepsake.",
		Queue = 3,
		Output = 16,
		Skill = "Crafting",
		Anim = "Press",
		Recipes = { { In = { Tag = "Flower", N = 1 }, Out = "pressed_%s", Time = 150 } },
	},
	{
		Id = "furnace",
		Name = "Furnace",
		Icon = "🔥",
		Description = "Smelts ore into bars and sand into glass.",
		Queue = 3,
		Output = 20,
		Skill = "Mining",
		Anim = "Heat",
		Recipes = {
			{ In = { Id = "copper_ore", N = 5 }, Extra = { { Id = "coal", N = 1 } }, Out = "copper_bar", Time = 60 },
			{ In = { Id = "iron_ore", N = 5 }, Extra = { { Id = "coal", N = 1 } }, Out = "iron_bar", Time = 120 },
			{ In = { Id = "gold_ore", N = 5 }, Extra = { { Id = "coal", N = 1 } }, Out = "gold_bar", Time = 180 },
			{
				In = { Id = "starsteel_ore", N = 5 },
				Extra = { { Id = "coal", N = 2 } },
				Out = "starsteel_bar",
				Time = 480,
			},
			{ In = { Id = "sand", N = 5 }, Extra = { { Id = "coal", N = 1 } }, Out = "glass", Time = 60 },
			{ In = { Id = "quartz", N = 1 }, Out = "glass", N = 2, Time = 45 },
			{ In = { Id = "wood", N = 10 }, Out = "coal", Time = 90 },
		},
	},
	{
		Id = "crystal_refinery",
		Name = "Crystal Refinery",
		Icon = "🔷",
		Description = "Refines raw crystal and crystal crops.",
		Queue = 2,
		Output = 10,
		Skill = "Mining",
		Anim = "Sparkle",
		Recipes = {
			{ In = { Id = "crystal_shard", N = 3 }, Out = "refined_crystal", Time = 300 },
			{ In = { Id = "crystal_berry", N = 5 }, Out = "crystal_shard", N = 2, Time = 240 },
			{ In = { Id = "meteorite", N = 1 }, Out = "stardust_powder", N = 2, Time = 600 },
			{ In = { Id = "prism_shard", N = 1 }, Out = "prismatic_gem", Time = 1800 },
		},
	},
	{
		Id = "seed_maker",
		Name = "Seed Maker",
		Icon = "🌱",
		Description = "Turns a crop back into 1-3 seeds that inherit its genes (and maybe a latent trait).",
		Queue = 3,
		Output = 20,
		Skill = "Farming",
		Anim = "Spin",
		Recipes = { { In = { Tag = "Crop", N = 1 }, Out = "seed_%s", Time = 120 } },
	},
	{
		Id = "honey_extractor",
		Name = "Honey Extractor",
		Icon = "🍯",
		Description = "Spins honeycomb into honey.",
		Queue = 2,
		Output = 10,
		Skill = "Ranching",
		Anim = "Spin",
		Recipes = {
			{ In = { Id = "honeycomb", N = 1 }, Out = "honey", N = 2, Time = 180 },
			{ In = { Id = "forest_honeycomb", N = 1 }, Out = "honey", N = 2, Time = 180 },
		},
	},
	{
		Id = "alchemy_still",
		Name = "Essence Still",
		Icon = "⚗️",
		Description = "Extracts magical essences from mystic crops.",
		Queue = 1,
		Output = 6,
		Skill = "Crafting",
		Anim = "Sparkle",
		Recipes = { { In = { Tag = "Mystic", N = 2 }, Out = "extract_%s", Time = 900 } },
	},
	{
		Id = "grand_kitchen",
		Name = "Grand Kitchen Factory",
		Icon = "🏭",
		Description = "An industrial line: mills, cans, juices and preserves at double speed with a big queue.",
		Queue = 6,
		Output = 60,
		Skill = "Crafting",
		Anim = "Spin",
		Recipes = {
			{ In = { Id = "wheat", N = 2 }, Out = "flour", Time = 30 },
			{ In = { Tag = "Fruit", N = 1 }, Out = "jam_%s", Time = 120 },
			{ In = { Tag = "Vegetable", N = 3 }, Out = "canned_%s", Time = 150 },
			{ In = { Tag = "Fruit", N = 1 }, Out = "juice_%s", Time = 45 },
			{ In = { Id = "milk", N = 1 }, Out = "cheese", Time = 150 },
		},
	},
}

return {
	List = List,
	Products = Products,
	-- Machine upgrades (level 1 → MaxLevel): speed, queue slots, output storage.
	MaxLevel = 5,
	LevelSpeed = 0.15, -- each level makes jobs this much faster
	LevelQueue = 1, -- extra queue slot per level
	LevelOutput = 6, -- extra output storage per level
	UpgradeCost = { 0, 2500, 8000, 24000, 70000 },
	UpgradeMats = {
		{},
		{ { Id = "copper_bar", N = 3 } },
		{ { Id = "iron_bar", N = 3 }, { Id = "gear", N = 1 } },
		{ { Id = "gold_bar", N = 3 }, { Id = "gear", N = 2 } },
		{ { Id = "refined_crystal", N = 2 }, { Id = "circuit", N = 1 } },
	},
	-- Chance per level (above 1) for output to go up one quality tier.
	QualityUpChance = 0.04,
	-- Offline processing cap in real seconds.
	OfflineCap = 8 * 3600,
}

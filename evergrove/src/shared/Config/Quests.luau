-- Quests.
--
-- Kinds: Story · Npc · Side · Daily · Weekly · Community
--
-- Objective types (Target can be an id, "#Tag", "*" for anything):
--   Till Plant Water Harvest(Target, Quality?, Mutation?) Sell(Value or Count) Earn
--   Ship Craft Process Cook Catch Mine Chop Forage Bug Dig Visit Talk Gift Pet
--   Collect(animal products) BuyAnimal Breed SeedBreed Place BuyLand Deliver
--   Reach(skill, level) Discover(collection count) Donate Project Festival Export
--   Upgrade(tool) Travel Secret Mutation(harvest a crop with Target mutation)
-- Deliver objectives are checked and consumed at turn-in (Quality = min tier).
--
-- Requires: Quest, Hearts {npc, n}, Estate, Skill {name, level}, Project, Item.
-- Rewards: Coins, XP { Skill = n }, Items { {id, n} }, Recipe, Title, Friendship { npc = pts },
--          Unlock (npc/secret), Tokens, Cosmetic.

export type Objective = {
	Type: string,
	Target: string?,
	Count: number,
	Quality: number?,
	Mutation: string?,
	Text: string?,
}

export type Quest = {
	Id: string,
	Kind: string,
	Name: string,
	Giver: string?,
	TurnIn: string?,
	Chapter: number?,
	Description: string,
	Requires: { [string]: any }?,
	Objectives: { Objective },
	Rewards: { [string]: any },
	Start: { string }?,
	Finish: { string }?,
	Auto: boolean?, -- auto-accept when requirements are met
	Repeat: boolean?,
}

local List: { Quest } = {}

local function q(def: any)
	def.Rewards = def.Rewards or {}
	table.insert(List, def)
end

local function o(kind: string, target: string?, count: number?, extra: { [string]: any }?): Objective
	local objective: any = { Type = kind, Target = target, Count = count or 1 }
	for k, v in pairs(extra or {}) do
		objective[k] = v
	end
	return objective
end

-- Chapter 1: New Roots ------------------------------------------------------------------------
q({
	Id = "story_1_1",
	Kind = "Story",
	Chapter = 1,
	Name = "Welcome Home",
	Giver = "mabel",
	TurnIn = "mabel",
	Auto = true,
	Description = "Mabel wants to see how you're settling in.",
	Objectives = { o("Talk", "mabel", 1, { Text = "Talk to Mabel at your farm" }) },
	Rewards = { Coins = 200, Items = { { "seed_carrot", 10 }, { "seed_lettuce", 10 } }, XP = { Farming = 30 } },
	Start = { "There you are! Come say hello when you've caught your breath." },
	Finish = { "Welcome to Evergrove, dear. Here, some seeds from my old shed." },
})
q({
	Id = "story_1_2",
	Kind = "Story",
	Chapter = 1,
	Name = "First Furrows",
	Giver = "mabel",
	TurnIn = "mabel",
	Auto = true,
	Requires = { Quest = "story_1_1" },
	Description = "Every great farm starts with a single row.",
	Objectives = {
		o("Harvest", "*", 15, { Text = "Harvest 15 crops" }),
		o("Water", "*", 20, { Text = "Water 20 tiles" }),
	},
	Rewards = { Coins = 400, Items = { { "compost", 10 }, { "seed_potato", 8 } }, XP = { Farming = 80 } },
	Finish = { "Look at that! You're a natural." },
})
q({
	Id = "story_1_3",
	Kind = "Story",
	Chapter = 1,
	Name = "Market Day",
	Giver = "mabel",
	TurnIn = "pip",
	Auto = true,
	Requires = { Quest = "story_1_2" },
	Description = "Sell your harvest and introduce yourself to Pip at the seed shop.",
	Objectives = {
		o("Sell", "*", 500, { Text = "Earn 500 coins from selling" }),
		o("Talk", "pip", 1, { Text = "Visit Pip in the village" }),
	},
	Rewards = {
		Coins = 500,
		Items = { { "basic_fertilizer", 10 }, { "bridge_plans", 1 } },
		XP = { Trading = 60 },
		Friendship = { pip = 60 },
	},
	Finish = { "The Mayor left these plans for whoever fixes the forest bridge. That's you, I reckon!" },
})
q({
	Id = "story_1_4",
	Kind = "Story",
	Chapter = 1,
	Name = "The Broken Bridge",
	Giver = "gus",
	TurnIn = "gus",
	Auto = true,
	Requires = { Quest = "story_1_3" },
	Description = "Bring Gus the bridge plans and materials to repair the bridge to Whispering Woods.",
	Objectives = { o("Deliver", "wood", 50), o("Deliver", "stone", 30), o("Deliver", "bridge_plans", 1) },
	Rewards = { Coins = 800, XP = { Foraging = 100, Exploration = 60 }, Friendship = { gus = 80 } },
	Finish = { "Bridge is fixed! The woods are all yours. Watch for mushrooms." },
})
q({
	Id = "story_1_5",
	Kind = "Story",
	Chapter = 1,
	Name = "Into the Woods",
	Giver = "rook",
	TurnIn = "rook",
	Auto = true,
	Requires = { Quest = "story_1_4" },
	Description = "Explore Whispering Woods: forage, chop and find your way.",
	Objectives = { o("Visit", "Forest", 1), o("Forage", "*", 10), o("Chop", "*", 5) },
	Rewards = {
		Coins = 1000,
		Items = { { "warp_home", 3 }, { "trail_mix", 3 } },
		XP = { Exploration = 120 },
		Friendship = { rook = 80 },
	},
	Finish = { "Not bad for a farmer! Keep exploring, there's more out there." },
})

-- Chapter 2: Growing Pains ----------------------------------------------------------------------
q({
	Id = "story_2_1",
	Kind = "Story",
	Chapter = 2,
	Name = "Town Revival",
	Giver = "mayor",
	TurnIn = "mayor",
	Auto = true,
	Requires = { Quest = "story_1_5" },
	Description = "Help the Mayor reopen the market. A lively market brings new people to town.",
	Objectives = { o("Project", "market_stalls", 1, { Text = "Complete the Reopen the Market project" }) },
	Rewards = { Coins = 2000, XP = { Trading = 200 }, Unlock = "juniper", Friendship = { mayor = 100 } },
	Finish = { "Marvellous! And look, a scientist has arrived on the morning cart!" },
})
q({
	Id = "story_2_2",
	Kind = "Story",
	Chapter = 2,
	Name = "Samples, Please",
	Giver = "juniper",
	TurnIn = "juniper",
	Auto = true,
	Requires = { Quest = "story_2_1" },
	Description = "Juniper wants mutated crops to study.",
	Objectives = { o("Mutation", "*", 3, { Text = "Harvest 3 crops with any mutation" }) },
	Rewards = {
		Coins = 1500,
		Items = { { "mutagen", 3 }, { "seed_maker", 1 } },
		XP = { Farming = 250 },
		Friendship = { juniper = 100 },
	},
	Finish = { "Fascinating. Take this Seed Maker: it keeps a crop's genes in its seeds." },
})
q({
	Id = "story_2_3",
	Kind = "Story",
	Chapter = 2,
	Name = "Animal Friends",
	Giver = "hattie",
	TurnIn = "hattie",
	Auto = true,
	Requires = { Quest = "story_2_1" },
	Description = "Build a coop, adopt two chickens and collect their eggs.",
	Objectives = { o("Place", "coop", 1), o("BuyAnimal", "chicken", 2), o("Collect", "*", 5) },
	Rewards = {
		Coins = 1500,
		Items = { { "animal_feed", 20 }, { "treat", 3 } },
		XP = { Ranching = 250 },
		Friendship = { hattie = 100 },
	},
	Finish = { "Look at those happy hens! You're a rancher now, partner." },
})
q({
	Id = "story_2_4",
	Kind = "Story",
	Chapter = 2,
	Name = "The Old Mine",
	Giver = "bram",
	TurnIn = "bram",
	Auto = true,
	Requires = { Quest = "story_2_2" },
	Description = "Bram wants proof you can handle a pickaxe before he trusts you with the mine key.",
	Objectives = { o("Visit", "Mountains", 1), o("Mine", "*", 25), o("Deliver", "copper_ore", 20) },
	Rewards = { Coins = 2000, Items = { { "mine_key", 1 } }, XP = { Mining = 250 }, Friendship = { bram = 100 } },
	Finish = { "Here. The lift key. Don't go deeper than you can climb." },
})
q({
	Id = "story_2_5",
	Kind = "Story",
	Chapter = 2,
	Name = "Deep Delving",
	Giver = "bram",
	TurnIn = "bram",
	Auto = true,
	Requires = { Quest = "story_2_4" },
	Description = "Mine the depths and smelt your first iron.",
	Objectives = { o("Visit", "Mine", 1), o("Deliver", "iron_bar", 5) },
	Rewards = {
		Coins = 3000,
		Items = { { "furnace", 1 }, { "gold_ore", 10 } },
		XP = { Mining = 400 },
		Friendship = { bram = 100 },
	},
	Finish = { "Good iron. Clean. You'll make a smith yet." },
})

-- Chapter 3: Echoes of the Past ------------------------------------------------------------------
q({
	Id = "story_3_1",
	Kind = "Story",
	Chapter = 3,
	Name = "Strange Carvings",
	Giver = "beatrix",
	TurnIn = "beatrix",
	Auto = true,
	Requires = { Quest = "story_2_5" },
	Description = "Beatrix is building the museum's collection. Donate discoveries to earn her trust.",
	Objectives = { o("Donate", "*", 5) },
	Rewards = { Coins = 3000, XP = { Exploration = 300 }, Friendship = { beatrix = 120 } },
	Finish = { "These carvings match the ruins to the northeast. Would you go and look?" },
})
q({
	Id = "story_3_2",
	Kind = "Story",
	Chapter = 3,
	Name = "The First Tablet",
	Giver = "beatrix",
	TurnIn = "beatrix",
	Auto = true,
	Requires = { Quest = "story_3_1" },
	Description = "Search the Ancient Ruins for carved tablets.",
	Objectives = {
		o("Visit", "Ruins", 1),
		o("Dig", "*", 5),
		o("Secret", "tablet_1", 1, { Text = "Find the first tablet" }),
	},
	Rewards = { Coins = 3000, XP = { Exploration = 400 } },
	Finish = { "A tablet! There must be more..." },
})
q({
	Id = "story_3_3",
	Kind = "Story",
	Chapter = 3,
	Name = "Tablets of Growth",
	Giver = "beatrix",
	TurnIn = "beatrix",
	Auto = true,
	Requires = { Quest = "story_3_2" },
	Description = "Three more tablets are hidden in the ruins. Their glyphs are clues.",
	Objectives = { o("Secret", "tablet_2", 1), o("Secret", "tablet_3", 1), o("Secret", "tablet_4", 1) },
	Rewards = { Coins = 5000, XP = { Exploration = 600 }, Friendship = { beatrix = 150 } },
	Finish = { "All four! Together they form a key..." },
})
q({
	Id = "story_3_4",
	Kind = "Story",
	Chapter = 3,
	Name = "The Seed Vault",
	Giver = "beatrix",
	TurnIn = "beatrix",
	Auto = true,
	Requires = { Quest = "story_3_3" },
	Description = "Use the four tablets to open the vault beneath the ruins.",
	Objectives = { o("Secret", "seed_vault", 1) },
	Rewards = {
		Coins = 6000,
		Items = { { "ancient_seed", 3 }, { "book_alchemy", 1 }, { "ruin_dust", 10 } },
		XP = { Exploration = 800, Farming = 400 },
	},
	Finish = { "Seeds from the first farmers... incredible." },
})
q({
	Id = "story_3_5",
	Kind = "Story",
	Chapter = 3,
	Name = "Ancient Harvest",
	Giver = "beatrix",
	TurnIn = "beatrix",
	Auto = true,
	Requires = { Quest = "story_3_4" },
	Description = "Grow a crop that carries the Ancient trait.",
	Objectives = { o("Mutation", "Ancient", 1) },
	Rewards = { Coins = 8000, Title = "Keeper of Seeds", XP = { Farming = 800 } },
	Finish = { "It's as if the old valley is growing again." },
})

-- Chapter 4: Reach for the Sky ---------------------------------------------------------------------
q({
	Id = "story_4_1",
	Kind = "Story",
	Chapter = 4,
	Name = "Stargazer",
	Giver = "mayor",
	TurnIn = "luna",
	Auto = true,
	Requires = { Quest = "story_3_1", Estate = 8 },
	Description = "An astronomer has moved into the observatory. Visit her at night.",
	Objectives = { o("Visit", "Mountains", 1), o("Talk", "luna", 1) },
	Rewards = { Coins = 3000, XP = { Exploration = 400 }, Unlock = "luna", Friendship = { luna = 100 } },
	Finish = { "Oh! A visitor! Do you believe in floating islands?" },
})
q({
	Id = "story_4_2",
	Kind = "Story",
	Chapter = 4,
	Name = "Chart the Stars",
	Giver = "luna",
	TurnIn = "luna",
	Auto = true,
	Requires = { Quest = "story_4_1" },
	Description = "Luna's star chart was torn into three pieces. One went to the fishermen, one to the museum, one into the mine.",
	Objectives = { o("Deliver", "star_chart", 3) },
	Rewards = { Coins = 5000, XP = { Exploration = 600 }, Friendship = { luna = 120 } },
	Finish = { "Complete! Now the lift just needs a heart of starlight." },
})
q({
	Id = "story_4_3",
	Kind = "Story",
	Chapter = 4,
	Name = "Meteor Night",
	Giver = "luna",
	TurnIn = "luna",
	Auto = true,
	Requires = { Quest = "story_4_2" },
	Description = "Find a meteorite. They fall during meteor showers.",
	Objectives = { o("Deliver", "meteorite", 1) },
	Rewards = { Coins = 6000, Items = { { "sky_key", 1 } }, XP = { Mining = 500 } },
	Finish = { "The Sky Lift is ready! Here's your pass." },
})
q({
	Id = "story_4_4",
	Kind = "Story",
	Chapter = 4,
	Name = "Above the Clouds",
	Giver = "luna",
	TurnIn = "luna",
	Auto = true,
	Requires = { Quest = "story_4_3" },
	Description = "Ride the Sky Lift to Skyreach Isles.",
	Objectives = { o("Visit", "Skyreach", 1), o("Forage", "*", 5) },
	Rewards = { Coins = 8000, Items = { { "seed_cloud_melon", 3 }, { "cloud_soil", 10 } }, XP = { Exploration = 1000 } },
	Finish = { "You were really up there! Try growing cloud melons at home with cloud soil." },
})
q({
	Id = "story_4_5",
	Kind = "Story",
	Chapter = 4,
	Name = "Cloud Farming",
	Giver = "luna",
	TurnIn = "luna",
	Auto = true,
	Requires = { Quest = "story_4_4" },
	Description = "Grow a Cloud Melon.",
	Objectives = { o("Harvest", "cloud_melon", 1) },
	Rewards = { Coins = 15000, Title = "Sky Farmer", XP = { Farming = 1500 } },
	Finish = { "A melon made of sky. You're a wonder." },
})

-- Chapter 5: Empire of the Valley -------------------------------------------------------------------
q({
	Id = "story_5_1",
	Kind = "Story",
	Chapter = 5,
	Name = "Automation Age",
	Giver = "nell",
	TurnIn = "nell",
	Auto = true,
	Requires = { Quest = "story_4_1", Estate = 12 },
	Description = "Nell thinks your farm is ready to run itself.",
	Objectives = {
		o("Place", "logistics_hub", 1),
		o("Place", "silo", 1),
		o("Place", "#Sprinkler", 10, { Text = "Place 10 sprinklers" }),
	},
	Rewards = { Coins = 20000, Items = { { "battery", 5 } }, XP = { Crafting = 1500 }, Friendship = { nell = 150 } },
	Finish = { "Beep boop! Your farm is officially smart." },
})
q({
	Id = "story_5_2",
	Kind = "Story",
	Chapter = 5,
	Name = "Master Artisan",
	Giver = "marco",
	TurnIn = "marco",
	Auto = true,
	Requires = { Quest = "story_5_1" },
	Description = "Turn raw harvest into fine goods.",
	Objectives = { o("Process", "*", 200) },
	Rewards = { Coins = 30000, XP = { Crafting = 2500 } },
	Finish = { "Your goods are on every table in the valley!" },
})
q({
	Id = "story_5_3",
	Kind = "Story",
	Chapter = 5,
	Name = "Export Magnate",
	Giver = "wendell",
	TurnIn = "wendell",
	Auto = true,
	Requires = { Quest = "story_5_2" },
	Description = "Ship goods overseas worth a fortune.",
	Objectives = { o("Export", "*", 100000, { Text = "Export goods worth 100,000 coins" }) },
	Rewards = { Coins = 40000, XP = { Trading = 3000 } },
	Finish = { "The whole world knows Evergrove now." },
})
q({
	Id = "story_5_4",
	Kind = "Story",
	Chapter = 5,
	Name = "Festival Champion",
	Giver = "mayor",
	TurnIn = "mayor",
	Auto = true,
	Requires = { Quest = "story_5_3" },
	Description = "Place in the top three of any festival contest.",
	Objectives = { o("Festival", "Podium", 1) },
	Rewards = { Coins = 30000, Items = { { "champion_statue", 1 } }, XP = { Trading = 2000 } },
	Finish = { "A champion! Evergrove is proud of you!" },
})
q({
	Id = "story_5_5",
	Kind = "Story",
	Chapter = 5,
	Name = "Pillar of Evergrove",
	Giver = "mayor",
	TurnIn = "mayor",
	Auto = true,
	Requires = { Quest = "story_5_4" },
	Description = "Help build Evergrove into a thriving town.",
	Objectives = { o("Project", "*", 6, { Text = "Complete 6 town projects" }) },
	Rewards = { Coins = 100000, Title = "Pillar of Evergrove", XP = { Trading = 5000 } },
	Finish = { "Evergrove will never forget what you've done." },
})

-- The Worldtree (legendary line) ------------------------------------------------------------------
q({
	Id = "worldtree_1",
	Kind = "Story",
	Chapter = 6,
	Name = "The Torn Map",
	Giver = "mabel",
	TurnIn = "mabel",
	Auto = true,
	Requires = { Quest = "story_3_5" },
	Description = "Mabel speaks of a tree of light in a valley no one remembers.",
	Objectives = { o("Deliver", "valley_map", 1, { Text = "Find the torn map" }) },
	Rewards = { Coins = 5000, Items = { { "valley_map", 1 } }, XP = { Exploration = 1000 } },
	Finish = { "That's it! That's the valley! Keep the map, dear." },
})
q({
	Id = "worldtree_2",
	Kind = "Story",
	Chapter = 6,
	Name = "The Hidden Valley",
	Giver = "mabel",
	TurnIn = "mabel",
	Auto = true,
	Requires = { Quest = "worldtree_1" },
	Description = "Follow the map west, beyond the woods.",
	Objectives = { o("Visit", "HiddenValley", 1) },
	Rewards = { Coins = 10000, XP = { Exploration = 2000 } },
	Finish = { "You found it... after all these years." },
})
q({
	Id = "worldtree_3",
	Kind = "Story",
	Chapter = 6,
	Name = "Rainbow's End",
	Giver = "mabel",
	TurnIn = "mabel",
	Auto = true,
	Requires = { Quest = "worldtree_2" },
	Description = "Grow a Rainbow Fruit from the valley.",
	Objectives = { o("Harvest", "rainbow_fruit", 1) },
	Rewards = { Coins = 20000, XP = { Farming = 3000 } },
	Finish = { "The tree I saw was covered in these." },
})
q({
	Id = "worldtree_4",
	Kind = "Story",
	Chapter = 6,
	Name = "The Stranger's Name",
	Giver = "wisp",
	TurnIn = "wisp",
	Auto = true,
	Requires = { Quest = "worldtree_3" },
	Description = "The Hooded Stranger knows more than they say.",
	Objectives = { o("Reach", "Hearts:wisp", 8, { Text = "Reach 8 hearts with the Hooded Stranger" }) },
	Rewards = { Coins = 10000 },
	Finish = { "My name was Wendeline. I was the valley's last keeper." },
})
q({
	Id = "worldtree_5",
	Kind = "Story",
	Chapter = 6,
	Name = "The Acorn",
	Giver = "wisp",
	TurnIn = "wisp",
	Auto = true,
	Requires = { Quest = "worldtree_4" },
	Description = "Wendeline entrusts you with the Worldtree acorn.",
	Objectives = { o("Deliver", "worldtree_acorn", 1, { Text = "Hold the Worldtree Acorn" }) },
	Rewards = { Items = { { "worldtree_acorn", 1 } } },
	Finish = { "Plant it in the valley's heart, where the ground hums." },
})
q({
	Id = "worldtree_6",
	Kind = "Story",
	Chapter = 6,
	Name = "Awakening",
	Giver = "wisp",
	TurnIn = "wisp",
	Auto = true,
	Requires = { Quest = "worldtree_5" },
	Description = "Plant the acorn in the Hidden Valley's grove.",
	Objectives = { o("Secret", "worldtree_grove", 1) },
	Rewards = {
		Coins = 250000,
		Items = { { "seed_worldtree", 1 } },
		Title = "Keeper of the Worldtree",
		XP = { Farming = 10000, Exploration = 5000 },
	},
	Finish = { "The Worldtree wakes. Take a seedling for your own farm, keeper." },
})

-- Starlight (celestial side line) --------------------------------------------------------------------
q({
	Id = "starlight_1",
	Kind = "Npc",
	Name = "Night Sky",
	Giver = "luna",
	TurnIn = "luna",
	Requires = { Quest = "story_4_4" },
	Description = "Catch a Star Ray in Skyreach.",
	Objectives = { o("Catch", "star_ray", 1) },
	Rewards = { Coins = 8000, XP = { Fishing = 1000 } },
})
q({
	Id = "starlight_2",
	Kind = "Npc",
	Name = "Beacon",
	Giver = "luna",
	TurnIn = "luna",
	Requires = { Quest = "starlight_1" },
	Description = "Craft a Celestial Beacon.",
	Objectives = { o("Craft", "celestial_beacon", 1) },
	Rewards = { Coins = 10000, XP = { Crafting = 1000 } },
})
q({
	Id = "starlight_3",
	Kind = "Npc",
	Name = "Celestial Touch",
	Giver = "luna",
	TurnIn = "luna",
	Requires = { Quest = "starlight_2" },
	Description = "Harvest a crop with the Celestial mutation.",
	Objectives = { o("Mutation", "Celestial", 1) },
	Rewards = { Coins = 15000, XP = { Farming = 2000 } },
})
q({
	Id = "starlight_4",
	Kind = "Npc",
	Name = "Vine of Stars",
	Giver = "luna",
	TurnIn = "luna",
	Requires = { Quest = "starlight_3" },
	Description = "Luna has something special for you.",
	Objectives = { o("Talk", "luna", 1) },
	Rewards = { Items = { { "seed_celestial_vine", 2 } }, Title = "Starfarmer" },
})

-- Villager quests -----------------------------------------------------------------------------------------
q({
	Id = "pip_1",
	Kind = "Npc",
	Name = "Seed Sampler",
	Giver = "pip",
	TurnIn = "pip",
	Requires = { Hearts = { "pip", 1 } },
	Description = "Pip wants to know which seeds grow best for you.",
	Objectives = { o("Plant", "*", 40) },
	Rewards = { Coins = 800, Items = { { "mystery_seed", 5 } }, Friendship = { pip = 80 } },
})
q({
	Id = "pip_2",
	Kind = "Npc",
	Name = "Strawberry Season",
	Giver = "pip",
	TurnIn = "pip",
	Requires = { Hearts = { "pip", 3 } },
	Description = "Bring Pip 20 Fine or better strawberries.",
	Objectives = { o("Deliver", "strawberry", 20, { Quality = 2 }) },
	Rewards = { Coins = 2000, Friendship = { pip = 120 } },
})
q({
	Id = "bram_1",
	Kind = "Npc",
	Name = "Ore for the Forge",
	Giver = "bram",
	TurnIn = "bram",
	Requires = { Hearts = { "bram", 1 } },
	Description = "Bram's running low on copper.",
	Objectives = { o("Deliver", "copper_ore", 30) },
	Rewards = { Coins = 900, Items = { { "coal", 10 } }, Friendship = { bram = 80 } },
})
q({
	Id = "bram_2",
	Kind = "Npc",
	Name = "Starsteel",
	Giver = "bram",
	TurnIn = "bram",
	Requires = { Hearts = { "bram", 6 } },
	Description = "Bram dreams of forging starsteel.",
	Objectives = { o("Deliver", "starsteel_bar", 5) },
	Rewards = { Coins = 12000, Friendship = { bram = 200 }, Title = "Starsmith" },
})
q({
	Id = "juniper_1",
	Kind = "Npc",
	Name = "Charged Up",
	Giver = "juniper",
	TurnIn = "juniper",
	Requires = { Hearts = { "juniper", 2 } },
	Description = "Grow a Charged crop in a thunderstorm.",
	Objectives = { o("Mutation", "Charged", 1) },
	Rewards = { Coins = 3000, Items = { { "lightning_rod", 1 } }, Friendship = { juniper = 120 } },
})
q({
	Id = "juniper_2",
	Kind = "Npc",
	Name = "Hybrid Vigor",
	Giver = "juniper",
	TurnIn = "juniper",
	Requires = { Hearts = { "juniper", 4 } },
	Description = "Cross-breed two seeds into a hybrid.",
	Objectives = { o("SeedBreed", "Hybrid", 1) },
	Rewards = { Coins = 6000, Items = { { "golden_dust", 2 } }, Friendship = { juniper = 150 } },
})
q({
	Id = "rosalind_1",
	Kind = "Npc",
	Name = "A Bouquet",
	Giver = "rosalind",
	TurnIn = "rosalind",
	Requires = { Hearts = { "rosalind", 1 } },
	Description = "Rosalind would love fresh flowers for the glasshouse.",
	Objectives = { o("Deliver", "#Flower", 10) },
	Rewards = { Coins = 1000, Items = { { "quality_fertilizer", 10 } }, Friendship = { rosalind = 100 } },
})
q({
	Id = "rosalind_2",
	Kind = "Npc",
	Name = "The Frozen Bloom",
	Giver = "rosalind",
	TurnIn = "rosalind",
	Requires = { Hearts = { "rosalind", 7 } },
	Description = "Grow a Frost Orchid for Rosalind.",
	Objectives = { o("Deliver", "frost_orchid", 1) },
	Rewards = { Coins = 15000, Friendship = { rosalind = 250 }, Title = "Orchid Whisperer" },
})
q({
	Id = "marco_1",
	Kind = "Npc",
	Name = "Tomato Tuesday",
	Giver = "marco",
	TurnIn = "marco",
	Requires = { Hearts = { "marco", 1 } },
	Description = "Marco's sauce needs 15 tomatoes.",
	Objectives = { o("Deliver", "tomato", 15) },
	Rewards = { Coins = 1200, Items = { { "pizza", 2 } }, Friendship = { marco = 100 } },
})
q({
	Id = "marco_2",
	Kind = "Npc",
	Name = "Chef's Table",
	Giver = "marco",
	TurnIn = "marco",
	Requires = { Hearts = { "marco", 4 } },
	Description = "Cook 15 dishes of any kind.",
	Objectives = { o("Cook", "*", 15) },
	Rewards = { Coins = 5000, Friendship = { marco = 150 } },
})
q({
	Id = "hattie_1",
	Kind = "Npc",
	Name = "Happy Herd",
	Giver = "hattie",
	TurnIn = "hattie",
	Requires = { Hearts = { "hattie", 1 } },
	Description = "Pet your animals 30 times.",
	Objectives = { o("Pet", "*", 30) },
	Rewards = { Coins = 1500, Items = { { "treat", 5 } }, Friendship = { hattie = 100 } },
})
q({
	Id = "hattie_2",
	Kind = "Npc",
	Name = "Golden Genes",
	Giver = "hattie",
	TurnIn = "hattie",
	Requires = { Hearts = { "hattie", 5 } },
	Description = "Breed an animal with a rare coat.",
	Objectives = { o("Breed", "Rare", 1) },
	Rewards = { Coins = 8000, Friendship = { hattie = 200 }, Title = "Master Breeder" },
})
q({
	Id = "finn_1",
	Kind = "Npc",
	Name = "Catch of the Day",
	Giver = "finn",
	TurnIn = "finn",
	Requires = { Hearts = { "finn", 1 } },
	Description = "Catch 20 fish.",
	Objectives = { o("Catch", "*", 20) },
	Rewards = { Coins = 1200, Items = { { "deluxe_bait", 10 } }, Friendship = { finn = 100 } },
})
q({
	Id = "finn_2",
	Kind = "Npc",
	Name = "Grandpa's Rod",
	Giver = "finn",
	TurnIn = "finn",
	Requires = { Hearts = { "finn", 4 } },
	Description = "Finn lost his grandfather's rod in the river. Fishing treasure sometimes turns up old things...",
	Objectives = { o("Deliver", "old_rod", 1) },
	Rewards = { Coins = 5000, Friendship = { finn = 250 } },
})
q({
	Id = "finn_3",
	Kind = "Npc",
	Name = "The River King",
	Giver = "finn",
	TurnIn = "finn",
	Requires = { Hearts = { "finn", 6 } },
	Description = "Catch the legendary River King.",
	Objectives = { o("Catch", "river_king", 1) },
	Rewards = { Coins = 20000, Items = { { "fishing_trophy", 1 } }, Title = "King Catcher" },
})
q({
	Id = "gus_1",
	Kind = "Npc",
	Name = "Lumber Order",
	Giver = "gus",
	TurnIn = "gus",
	Requires = { Hearts = { "gus", 1 } },
	Description = "Gus needs 100 wood for a big job.",
	Objectives = { o("Deliver", "wood", 100) },
	Rewards = { Coins = 1200, Items = { { "hardwood", 10 } }, Friendship = { gus = 100 } },
})
q({
	Id = "gus_2",
	Kind = "Npc",
	Name = "Room to Grow",
	Giver = "gus",
	TurnIn = "gus",
	Requires = { Hearts = { "gus", 3 } },
	Description = "Expand your farm by 3 parcels.",
	Objectives = { o("BuyLand", "*", 3) },
	Rewards = { Coins = 6000, Friendship = { gus = 150 } },
})
q({
	Id = "beatrix_1",
	Kind = "Npc",
	Name = "Growing Collection",
	Giver = "beatrix",
	TurnIn = "beatrix",
	Requires = { Hearts = { "beatrix", 2 } },
	Description = "Donate 15 items to the museum.",
	Objectives = { o("Donate", "*", 15) },
	Rewards = { Coins = 4000, Friendship = { beatrix = 150 } },
})
q({
	Id = "beatrix_2",
	Kind = "Npc",
	Name = "A Complete Set",
	Giver = "beatrix",
	TurnIn = "beatrix",
	Requires = { Hearts = { "beatrix", 5 } },
	Description = "Donate 40 items to the museum.",
	Objectives = { o("Donate", "*", 40) },
	Rewards = { Coins = 15000, Items = { { "trophy_case", 1 } }, Friendship = { beatrix = 200 }, Title = "Curator" },
})
q({
	Id = "rook_1",
	Kind = "Npc",
	Name = "Pathfinder",
	Giver = "rook",
	TurnIn = "rook",
	Requires = { Hearts = { "rook", 1 } },
	Description = "Discover 6 signposts.",
	Objectives = { o("Travel", "*", 6) },
	Rewards = { Coins = 2000, Items = { { "warp_home", 5 } }, Friendship = { rook = 100 } },
})
q({
	Id = "rook_2",
	Kind = "Npc",
	Name = "Buried Treasure",
	Giver = "rook",
	TurnIn = "rook",
	Requires = { Hearts = { "rook", 3 } },
	Description = "Dig up 25 dig spots.",
	Objectives = { o("Dig", "*", 25) },
	Rewards = { Coins = 4000, Items = { { "treasure_chest", 1 } }, Friendship = { rook = 150 } },
})
q({
	Id = "ivy_1",
	Kind = "Npc",
	Name = "Pretty as a Picture",
	Giver = "ivy",
	TurnIn = "ivy",
	Requires = { Hearts = { "ivy", 1 } },
	Description = "Place 25 decorations on your farm.",
	Objectives = { o("Place", "#Decor", 25) },
	Rewards = { Coins = 2000, Items = { { "flower_bed", 4 } }, Friendship = { ivy = 100 } },
})
q({
	Id = "ivy_2",
	Kind = "Npc",
	Name = "Blooming Marvellous",
	Giver = "ivy",
	TurnIn = "ivy",
	Requires = { Hearts = { "ivy", 4 } },
	Description = "Harvest 60 flowers.",
	Objectives = { o("Harvest", "#Flower", 60) },
	Rewards = { Coins = 5000, Items = { { "string_lights", 3 } }, Friendship = { ivy = 150 } },
})
q({
	Id = "mayor_1",
	Kind = "Npc",
	Name = "Civic Duty",
	Giver = "mayor",
	TurnIn = "mayor",
	Requires = { Hearts = { "mayor", 1 } },
	Description = "Contribute to any town project.",
	Objectives = { o("Project", "Contribute", 1) },
	Rewards = { Coins = 1500, Friendship = { mayor = 100 } },
})
q({
	Id = "nell_1",
	Kind = "Npc",
	Name = "Sprinkler System",
	Giver = "nell",
	TurnIn = "nell",
	Requires = { Hearts = { "nell", 1 } },
	Description = "Place 8 sprinklers.",
	Objectives = { o("Place", "#Sprinkler", 8) },
	Rewards = { Coins = 3000, Items = { { "quality_sprinkler", 2 } }, Friendship = { nell = 100 } },
})
q({
	Id = "nell_2",
	Kind = "Npc",
	Name = "Drone Pilot",
	Giver = "nell",
	TurnIn = "nell",
	Requires = { Hearts = { "nell", 4 } },
	Description = "Set up a Harvest Drone Hub.",
	Objectives = { o("Place", "harvest_drone_hub", 1) },
	Rewards = { Coins = 10000, Items = { { "battery", 5 } }, Friendship = { nell = 150 } },
})
q({
	Id = "wendell_1",
	Kind = "Npc",
	Name = "First Shipment",
	Giver = "wendell",
	TurnIn = "wendell",
	Requires = { Hearts = { "wendell", 0 } },
	Description = "Send an export shipment from the harbour.",
	Objectives = { o("Export", "*", 1000) },
	Rewards = { Coins = 2000, Items = { { "canning_station", 1 } }, Friendship = { wendell = 100 } },
})
q({
	Id = "mabel_hollow_1",
	Kind = "Npc",
	Name = "The Old Farm",
	Giver = "mabel",
	TurnIn = "mabel",
	Requires = { Hearts = { "mabel", 3 } },
	Description = "Mabel mentions an abandoned farm to the southwest.",
	Objectives = { o("Talk", "mabel", 1) },
	Rewards = { Coins = 1000 },
	Finish = {
		"The Hollow Farm... my sister's place. Nobody's farmed it in decades, but the crops still grow. Be careful.",
	},
})
q({
	Id = "mabel_hollow_2",
	Kind = "Npc",
	Name = "Ghost Crops",
	Giver = "mabel",
	TurnIn = "mabel",
	Requires = { Quest = "mabel_hollow_1" },
	Description = "Grow a Spectral crop.",
	Objectives = { o("Mutation", "Spectral", 1) },
	Rewards = { Coins = 6000, Items = { { "seed_wraithpepper", 3 } }, Friendship = { mabel = 150 } },
})
q({
	Id = "mabel_hollow_3",
	Kind = "Npc",
	Name = "For H.",
	Giver = "mabel",
	TurnIn = "hattie",
	Requires = { Quest = "mabel_hollow_2" },
	Description = "A locket from the Hollow Farm is engraved 'For H.'. Hattie's grandmother lived there...",
	Objectives = { o("Deliver", "lost_locket", 1) },
	Rewards = { Coins = 5000, Friendship = { hattie = 300, mabel = 100 } },
})

-- Daily request templates (3 are picked per player per day) ---------------------------------------------
local Daily = {
	{
		Id = "d_harvest",
		Name = "Busy Harvest",
		Objective = o("Harvest", "*", 30),
		Scale = true,
		Reward = { Coins = 400, XP = { Farming = 120 } },
	},
	{
		Id = "d_harvest_seasonal",
		Name = "In-Season Order",
		Objective = o("Harvest", "@Seasonal", 12),
		Scale = true,
		Reward = { Coins = 500, XP = { Farming = 140 } },
	},
	{
		Id = "d_water",
		Name = "Thirsty Fields",
		Objective = o("Water", "*", 40),
		Scale = true,
		Reward = { Coins = 250, XP = { Farming = 80 } },
	},
	{
		Id = "d_sell",
		Name = "Market Rush",
		Objective = o("Sell", "*", 2000),
		Scale = true,
		Reward = { Coins = 500, XP = { Trading = 150 } },
	},
	{
		Id = "d_fish",
		Name = "Gone Fishing",
		Objective = o("Catch", "*", 6),
		Reward = { Coins = 450, Items = { { "bait", 10 } }, XP = { Fishing = 150 } },
	},
	{
		Id = "d_mine",
		Name = "Rock Breaker",
		Objective = o("Mine", "*", 20),
		Reward = { Coins = 400, XP = { Mining = 150 } },
	},
	{
		Id = "d_chop",
		Name = "Timber!",
		Objective = o("Chop", "*", 8),
		Reward = { Coins = 350, XP = { Foraging = 120 } },
	},
	{
		Id = "d_forage",
		Name = "Wild Pickings",
		Objective = o("Forage", "*", 10),
		Reward = { Coins = 350, XP = { Foraging = 120 } },
	},
	{
		Id = "d_bugs",
		Name = "Bug Hunt",
		Objective = o("Bug", "*", 4),
		Reward = { Coins = 400, XP = { Foraging = 140 } },
	},
	{
		Id = "d_craft",
		Name = "Handy Work",
		Objective = o("Craft", "*", 5),
		Reward = { Coins = 350, XP = { Crafting = 120 } },
	},
	{
		Id = "d_process",
		Name = "Artisan Hours",
		Objective = o("Process", "*", 8),
		Scale = true,
		Reward = { Coins = 600, XP = { Crafting = 180 } },
	},
	{
		Id = "d_cook",
		Name = "Home Cooking",
		Objective = o("Cook", "*", 3),
		Reward = { Coins = 400, XP = { Cooking = 150 } },
	},
	{
		Id = "d_pet",
		Name = "Animal Love",
		Objective = o("Pet", "*", 6),
		Reward = { Coins = 300, Items = { { "treat", 1 } }, XP = { Ranching = 120 } },
	},
	{
		Id = "d_collect",
		Name = "Fresh Produce",
		Objective = o("Collect", "*", 6),
		Reward = { Coins = 450, XP = { Ranching = 150 } },
	},
	{
		Id = "d_gift",
		Name = "Good Neighbour",
		Objective = o("Gift", "*", 3),
		Reward = { Coins = 300, XP = { Exploration = 80 } },
	},
	{
		Id = "d_talk",
		Name = "Village Rounds",
		Objective = o("Talk", "*", 5),
		Reward = { Coins = 250, XP = { Exploration = 80 } },
	},
	{
		Id = "d_deliver",
		Name = "Special Request",
		Objective = o("Deliver", "@Request", 5),
		Scale = true,
		Reward = { Coins = 800, XP = { Trading = 200 } },
	},
	{
		Id = "d_mutation",
		Name = "Oddity Hunter",
		Objective = o("Mutation", "*", 1),
		Reward = { Coins = 900, XP = { Farming = 250 } },
		MinEstate = 3,
	},
	{
		Id = "d_quality",
		Name = "Quality Control",
		Objective = o("Harvest", "*", 10, { Quality = 3 }),
		Reward = { Coins = 700, XP = { Farming = 200 } },
		MinEstate = 2,
	},
}

local Weekly = {
	{
		Id = "w_harvest",
		Name = "Bumper Week",
		Objective = o("Harvest", "*", 400),
		Scale = true,
		Reward = { Coins = 6000, Items = { { "seed_crate", 1 } }, XP = { Farming = 1500 } },
	},
	{
		Id = "w_earn",
		Name = "Profitable Week",
		Objective = o("Sell", "*", 40000),
		Scale = true,
		Reward = { Coins = 5000, XP = { Trading = 1500 } },
	},
	{
		Id = "w_fish",
		Name = "Angler's Week",
		Objective = o("Catch", "*", 50),
		Reward = { Coins = 5000, Items = { { "deluxe_bait", 25 } }, XP = { Fishing = 1500 } },
	},
	{
		Id = "w_process",
		Name = "Production Line",
		Objective = o("Process", "*", 100),
		Scale = true,
		Reward = { Coins = 7000, XP = { Crafting = 2000 } },
	},
	{
		Id = "w_discover",
		Name = "Discovery Week",
		Objective = o("Discover", "*", 6),
		Reward = { Coins = 6000, Items = { { "omni_geode", 3 } }, XP = { Exploration = 1500 } },
	},
	{
		Id = "w_mutation",
		Name = "Mutation Madness",
		Objective = o("Mutation", "*", 8),
		Reward = { Coins = 9000, Items = { { "mutagen", 5 } }, XP = { Farming = 2500 } },
	},
	{
		Id = "w_dailies",
		Name = "Reliable Farmer",
		Objective = o("Daily", "*", 10),
		Reward = { Coins = 8000, Items = { { "festival_box", 1 } } },
	},
	{
		Id = "w_animals",
		Name = "Ranch Week",
		Objective = o("Collect", "*", 60),
		Reward = { Coins = 6000, Items = { { "treat", 10 } }, XP = { Ranching = 1800 } },
	},
	{
		Id = "w_explore",
		Name = "Wanderlust",
		Objective = o("Forage", "*", 60),
		Reward = { Coins = 5000, XP = { Foraging = 1500, Exploration = 800 } },
	},
}

-- Community goals: every player on the server contributes; everyone who helped gets the reward.
local Community = {
	{
		Id = "c_harvest",
		Name = "Harvest Drive",
		Objective = o("Harvest", "*", 3000),
		Reward = { Coins = 3000, Items = { { "festival_box", 1 } } },
	},
	{
		Id = "c_fish",
		Name = "Village Fish Fry",
		Objective = o("Catch", "*", 400),
		Reward = { Coins = 3000, Items = { { "fish_stew", 3 } } },
	},
	{
		Id = "c_process",
		Name = "Artisan Fair",
		Objective = o("Process", "*", 800),
		Reward = { Coins = 4000, Items = { { "luck_potion", 1 } } },
	},
	{
		Id = "c_explore",
		Name = "Great Expedition",
		Objective = o("Forage", "*", 600),
		Reward = { Coins = 3000, Items = { { "treasure_chest", 1 } } },
	},
}

-- Quest items that only drop while the quest is active.
-- Source: FishTreasure · Mine · Donate · Dig · Forage · Chop
local Drops = {
	{ Quest = "story_4_2", Item = "star_chart", Source = "FishTreasure", Chance = 0.5, Max = 1, Tag = "fish" },
	{
		Quest = "story_4_2",
		Item = "star_chart",
		Source = "Mine",
		Chance = 0.03,
		Max = 1,
		Tag = "mine",
		Region = "Mine",
	},
	{ Quest = "story_4_2", Item = "star_chart", Source = "Donate", Chance = 1, Max = 1, Tag = "museum" },
	{ Quest = "finn_2", Item = "old_rod", Source = "FishTreasure", Chance = 0.35, Max = 1, Tag = "rod" },
	{
		Quest = "mabel_hollow_3",
		Item = "lost_locket",
		Source = "Dig",
		Chance = 0.25,
		Max = 1,
		Tag = "locket",
		Region = "HollowFarm",
	},
}

return {
	List = List,
	Drops = Drops,
	Daily = Daily,
	Weekly = Weekly,
	Community = Community,
	DailyCount = 3,
	WeeklyCount = 3,
	MaxActive = 25,
	-- Daily/weekly goals with Scale = true grow with Estate level: × (1 + EstateScale × (level - 1)).
	EstateScale = 0.08,
	-- Tracked quests shown on the HUD.
	MaxTracked = 4,
}

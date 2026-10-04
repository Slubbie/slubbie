-- Every cosmetic: outfits, gloves, shoes, backpacks, trails, landing effects,
-- emotes, titles and victory animations.
--
-- Nothing here affects movement. Items are built from parts and effects at
-- runtime (Services/CosmeticService, client Effects), so no uploaded assets
-- are needed. Each item says where it comes from:
--   Shop      bought with credits (Price) at the Guildhall outfitter or a district stall
--   Prestige  bought with prestige tokens (PrestigePrice)
--   Reward    granted by an achievement, quest, mastery tier, medal or mode (Source explains)

export type Item = {
	Id: string,
	Category: string,
	Name: string,
	Description: string,
	Rarity: string,
	Price: number?,
	PrestigePrice: number?,
	Source: string, -- "Shop" | "Prestige" | "Reward"
	Unlock: string?, -- how a Reward item is earned (shown in the locker)
	District: string?,
	Style: string?,
	Colors: { Color3 }?,
	Default: boolean?,
	Text: string?,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local items: { Item } = {}

local function add(item: Item)
	table.insert(items, item)
end

local function shop(
	category: string,
	id: string,
	name: string,
	price: number,
	rarity: string,
	style: string,
	colors: { Color3 },
	description: string,
	district: string?
)
	add({
		Id = id,
		Category = category,
		Name = name,
		Description = description,
		Rarity = rarity,
		Price = price,
		Source = "Shop",
		Style = style,
		Colors = colors,
		District = district,
	})
end

local function prestige(
	category: string,
	id: string,
	name: string,
	cost: number,
	style: string,
	colors: { Color3 },
	description: string
)
	add({
		Id = id,
		Category = category,
		Name = name,
		Description = description,
		Rarity = "Prestige",
		PrestigePrice = cost,
		Source = "Prestige",
		Style = style,
		Colors = colors,
	})
end

local function reward(
	category: string,
	id: string,
	name: string,
	rarity: string,
	style: string,
	colors: { Color3 },
	description: string,
	unlock: string,
	district: string?
)
	add({
		Id = id,
		Category = category,
		Name = name,
		Description = description,
		Rarity = rarity,
		Source = "Reward",
		Unlock = unlock,
		Style = style,
		Colors = colors,
		District = district,
	})
end

-- Outfits ------------------------------------------------------------------------
-- Styles: Hoodie, Jacket, Vest, Coat, Suit, Robe, Tracksuit
add({
	Id = "outfit_none",
	Category = "Outfit",
	Name = "Your Avatar",
	Description = "No overlay: run in your own look.",
	Rarity = "Common",
	Source = "Reward",
	Unlock = "Always available",
	Default = true,
	Style = "None",
	Colors = {},
})
reward(
	"Outfit",
	"outfit_recruit",
	"Guild Recruit",
	"Common",
	"Hoodie",
	{ rgb(70, 110, 140), rgb(230, 220, 200), rgb(255, 196, 92) },
	"The hoodie every new runner gets on their first day.",
	"Complete the Training Yard"
)
shop(
	"Outfit",
	"outfit_tracksuit",
	"Street Tracksuit",
	600,
	"Common",
	"Tracksuit",
	{ rgb(40, 44, 52), rgb(240, 240, 240), rgb(255, 90, 90) },
	"Two stripes, zero drag."
)
shop(
	"Outfit",
	"outfit_courier",
	"Courier Jacket",
	900,
	"Rare",
	"Jacket",
	{ rgb(196, 66, 58), rgb(40, 40, 46), rgb(255, 210, 90) },
	"Reflective trim for night deliveries."
)
shop(
	"Outfit",
	"outfit_laundry",
	"Laundry Day",
	700,
	"Common",
	"Vest",
	{ rgb(90, 160, 210), rgb(232, 214, 186), rgb(255, 170, 80) },
	"Borrowed from Mrs. Okafor's line. She knows.",
	"Tinroof"
)
shop(
	"Outfit",
	"outfit_foundry",
	"Foundry Coveralls",
	1200,
	"Rare",
	"Suit",
	{ rgb(150, 82, 52), rgb(58, 60, 66), rgb(240, 180, 40) },
	"Heat-proof, oil-stained, proud of it.",
	"Ironworks"
)
shop(
	"Outfit",
	"outfit_ranger",
	"Hollow Ranger",
	1500,
	"Rare",
	"Coat",
	{ rgb(70, 110, 60), rgb(110, 80, 58), rgb(240, 120, 170) },
	"Moss-green and quiet as the canopy.",
	"Verdant"
)
shop(
	"Outfit",
	"outfit_exec",
	"Night Exec",
	2200,
	"Epic",
	"Suit",
	{ rgb(26, 28, 40), rgb(255, 70, 190), rgb(70, 230, 255) },
	"A suit cut for rooftop sprints.",
	"Gilded"
)
shop(
	"Outfit",
	"outfit_parka",
	"Frostreach Parka",
	2400,
	"Epic",
	"Coat",
	{ rgb(200, 60, 60), rgb(236, 242, 250), rgb(255, 200, 120) },
	"Fur-lined and wind-proof.",
	"Frostreach"
)
shop(
	"Outfit",
	"outfit_skywright",
	"Skywright Robes",
	3200,
	"Epic",
	"Robe",
	{ rgb(236, 232, 244), rgb(150, 110, 255), rgb(240, 196, 100) },
	"The flowing robes of the Citadel's builders.",
	"Citadel"
)
reward(
	"Outfit",
	"outfit_legend",
	"Skyline Legend",
	"Legendary",
	"Jacket",
	{ rgb(255, 225, 120), rgb(30, 30, 40), rgb(110, 200, 255) },
	"Worn only by runners who completed the Skyline Legend route.",
	"Finish the main story epilogue"
)
reward(
	"Outfit",
	"outfit_spire",
	"Spire Climber",
	"Epic",
	"Tracksuit",
	{ rgb(80, 200, 255), rgb(30, 40, 60), rgb(255, 255, 255) },
	"For those who reached the top of the Spire.",
	"Clear floor 25 of the Spire"
)
prestige(
	"Outfit",
	"outfit_prestige",
	"Guild Regalia",
	12,
	"Coat",
	{ rgb(30, 30, 36), rgb(255, 196, 92), rgb(196, 66, 58) },
	"Formal Guild colours, earned not bought."
)

-- Gloves ---------------------------------------------------------------------------
add({
	Id = "gloves_none",
	Category = "Gloves",
	Name = "Bare Hands",
	Description = "Nothing between you and the rooftops.",
	Rarity = "Common",
	Source = "Reward",
	Unlock = "Always available",
	Default = true,
	Style = "None",
	Colors = {},
})
reward(
	"Gloves",
	"gloves_grip",
	"Grip Tape",
	"Common",
	"Wrap",
	{ rgb(240, 240, 240), rgb(180, 180, 180) },
	"Tape wraps for better holds.",
	"Reach level 3"
)
shop(
	"Gloves",
	"gloves_leather",
	"Courier Leathers",
	400,
	"Common",
	"Glove",
	{ rgb(110, 70, 40), rgb(60, 40, 30) },
	"Worn soft by a thousand ledges."
)
shop(
	"Gloves",
	"gloves_work",
	"Foundry Gauntlets",
	700,
	"Rare",
	"Gauntlet",
	{ rgb(240, 180, 40), rgb(58, 60, 66) },
	"Heavy-duty and heat-proof.",
	"Ironworks"
)
shop(
	"Gloves",
	"gloves_vine",
	"Vine Wraps",
	900,
	"Rare",
	"Wrap",
	{ rgb(84, 140, 70), rgb(240, 120, 170) },
	"Woven from Old Moss's best vines.",
	"Verdant"
)
shop(
	"Gloves",
	"gloves_neon",
	"Neon Knuckles",
	1300,
	"Epic",
	"Glove",
	{ rgb(26, 28, 40), rgb(255, 70, 190) },
	"Glow-stitched for night runs.",
	"Gilded"
)
shop(
	"Gloves",
	"gloves_mitts",
	"Ice Mitts",
	1300,
	"Epic",
	"Gauntlet",
	{ rgb(236, 242, 250), rgb(160, 210, 240) },
	"Warm, grippy, Frostreach-made.",
	"Frostreach"
)
reward(
	"Gloves",
	"gloves_climber",
	"Climber's Grips",
	"Epic",
	"Gauntlet",
	{ rgb(230, 160, 100), rgb(40, 40, 40) },
	"Proof you can hang anywhere.",
	"Reach Expert in Climbing mastery"
)
reward(
	"Gloves",
	"gloves_hook",
	"Hookmaster Gloves",
	"Epic",
	"Glove",
	{ rgb(80, 230, 220), rgb(30, 50, 60) },
	"Calloused from a thousand swings.",
	"Reach Expert in Grappling mastery"
)
prestige(
	"Gloves",
	"gloves_aether",
	"Aether Touch",
	8,
	"Glove",
	{ rgb(150, 110, 255), rgb(110, 230, 255) },
	"Gloves that leave a faint shimmer on everything you grab."
)

-- Shoes ------------------------------------------------------------------------------
add({
	Id = "shoes_none",
	Category = "Shoes",
	Name = "Avatar Shoes",
	Description = "Whatever you showed up in.",
	Rarity = "Common",
	Source = "Reward",
	Unlock = "Always available",
	Default = true,
	Style = "None",
	Colors = {},
})
reward(
	"Shoes",
	"shoes_trainers",
	"Guild Trainers",
	"Common",
	"Trainer",
	{ rgb(255, 255, 255), rgb(70, 110, 140) },
	"Standard issue, surprisingly good.",
	"Complete the Graduation Run"
)
shop(
	"Shoes",
	"shoes_hightops",
	"Rooftop High-Tops",
	500,
	"Common",
	"HighTop",
	{ rgb(196, 66, 58), rgb(255, 255, 255) },
	"Ankle support for the long drops."
)
shop(
	"Shoes",
	"shoes_boots",
	"Steel Toes",
	800,
	"Rare",
	"Boot",
	{ rgb(90, 70, 50), rgb(240, 180, 40) },
	"Ironworks safety boots.",
	"Ironworks"
)
reward(
	"Shoes",
	"shoes_spring",
	"Spring Soles",
	"Rare",
	"Trainer",
	{ rgb(255, 214, 90), rgb(90, 160, 210) },
	"The gear that makes a double jump possible.",
	"Complete Chapter 1",
	"Tinroof"
)
shop(
	"Shoes",
	"shoes_moss",
	"Moss Runners",
	1000,
	"Rare",
	"Trainer",
	{ rgb(84, 140, 70), rgb(110, 80, 58) },
	"Silent on stone.",
	"Verdant"
)
shop(
	"Shoes",
	"shoes_chrome",
	"Chrome Sprinters",
	1500,
	"Epic",
	"Trainer",
	{ rgb(200, 205, 220), rgb(70, 230, 255) },
	"Built for the Express Lane.",
	"Gilded"
)
shop(
	"Shoes",
	"shoes_crampons",
	"Crampon Boots",
	1500,
	"Epic",
	"Boot",
	{ rgb(70, 74, 86), rgb(160, 210, 240) },
	"Bite into the ice.",
	"Frostreach"
)
reward(
	"Shoes",
	"shoes_wall",
	"Wallrunner Treads",
	"Epic",
	"HighTop",
	{ rgb(110, 190, 255), rgb(20, 30, 50) },
	"Soles worn on their sides.",
	"Reach Expert in Wall Running mastery"
)
prestige(
	"Shoes",
	"shoes_gold",
	"Golden Soles",
	10,
	"Trainer",
	{ rgb(255, 210, 90), rgb(255, 245, 210) },
	"Every step a statement."
)

-- Backpacks ----------------------------------------------------------------------------
add({
	Id = "pack_none",
	Category = "Backpack",
	Name = "No Pack",
	Description = "Travel light.",
	Rarity = "Common",
	Source = "Reward",
	Unlock = "Always available",
	Default = true,
	Style = "None",
	Colors = {},
})
reward(
	"Backpack",
	"pack_satchel",
	"Guild Satchel",
	"Common",
	"Satchel",
	{ rgb(150, 105, 70), rgb(255, 196, 92) },
	"Carries one letter and two sandwiches.",
	"Complete your first quest"
)
shop(
	"Backpack",
	"pack_courier",
	"Courier Bag",
	700,
	"Common",
	"Courier",
	{ rgb(196, 66, 58), rgb(40, 40, 46) },
	"Waterproof, crush-proof, mostly."
)
shop(
	"Backpack",
	"pack_tank",
	"Steam Tank",
	1400,
	"Rare",
	"Tank",
	{ rgb(150, 82, 52), rgb(255, 120, 40) },
	"Hisses when you land.",
	"Ironworks"
)
shop(
	"Backpack",
	"pack_planter",
	"Planter Pack",
	1400,
	"Rare",
	"Planter",
	{ rgb(110, 80, 58), rgb(70, 150, 80) },
	"A tiny garden that goes everywhere you go.",
	"Verdant"
)
shop(
	"Backpack",
	"pack_cube",
	"Holo Cube",
	2000,
	"Epic",
	"Cube",
	{ rgb(70, 230, 255), rgb(255, 70, 190) },
	"A floating advert for yourself.",
	"Gilded"
)
shop(
	"Backpack",
	"pack_frame",
	"Mountain Frame",
	2000,
	"Epic",
	"Frame",
	{ rgb(120, 86, 62), rgb(200, 60, 60) },
	"Rope coil included.",
	"Frostreach"
)
shop(
	"Backpack",
	"pack_wings",
	"Skywright Wings",
	3500,
	"Legendary",
	"Wings",
	{ rgb(236, 232, 244), rgb(240, 196, 100) },
	"Decorative. Probably.",
	"Citadel"
)
reward(
	"Backpack",
	"pack_relay",
	"Relay Beacon",
	"Epic",
	"Beacon",
	{ rgb(255, 214, 90), rgb(80, 200, 255) },
	"A working piece of the city's signal network.",
	"Complete Chapter 4"
)
reward(
	"Backpack",
	"pack_crystal",
	"Keel Shard",
	"Legendary",
	"Crystal",
	{ rgb(180, 140, 255), rgb(110, 230, 255) },
	"A fragment of the Aether Keel, humming softly.",
	"Complete Chapter 6"
)
prestige(
	"Backpack",
	"pack_banner",
	"Guild Banner",
	14,
	"Banner",
	{ rgb(196, 66, 58), rgb(255, 196, 92) },
	"Carry the Guild's colours on every route."
)

-- Trails -------------------------------------------------------------------------------
add({
	Id = "trail_none",
	Category = "Trail",
	Name = "No Trail",
	Description = "Leave no trace.",
	Rarity = "Common",
	Source = "Reward",
	Unlock = "Always available",
	Default = true,
	Style = "None",
	Colors = {},
})
reward(
	"Trail",
	"trail_chalk",
	"Chalk Line",
	"Common",
	"Ribbon",
	{ rgb(255, 255, 255), rgb(220, 220, 230) },
	"The classic runner's mark.",
	"Reach level 2"
)
shop(
	"Trail",
	"trail_sunset",
	"Sunset Ribbon",
	800,
	"Rare",
	"Ribbon",
	{ rgb(255, 170, 80), rgb(255, 90, 120) },
	"Tinroof evenings, behind you.",
	"Tinroof"
)
shop(
	"Trail",
	"trail_sparks",
	"Spark Shower",
	1200,
	"Rare",
	"Sparks",
	{ rgb(255, 160, 60), rgb(255, 230, 140) },
	"Grinder sparks from the Ironworks.",
	"Ironworks"
)
shop(
	"Trail",
	"trail_leaves",
	"Falling Leaves",
	1200,
	"Rare",
	"Leaves",
	{ rgb(130, 190, 90), rgb(240, 120, 170) },
	"The Hollow follows you.",
	"Verdant"
)
shop(
	"Trail",
	"trail_neon",
	"Neon Streak",
	1800,
	"Epic",
	"Ribbon",
	{ rgb(255, 70, 190), rgb(70, 230, 255) },
	"Exchange lights at speed.",
	"Gilded"
)
shop(
	"Trail",
	"trail_frost",
	"Frost Breath",
	1800,
	"Epic",
	"Frost",
	{ rgb(220, 240, 255), rgb(160, 210, 240) },
	"Crystals in your wake.",
	"Frostreach"
)
shop(
	"Trail",
	"trail_aether",
	"Aether Wake",
	2800,
	"Legendary",
	"Aether",
	{ rgb(150, 110, 255), rgb(110, 230, 255) },
	"Bent light and drifting motes.",
	"Citadel"
)
reward(
	"Trail",
	"trail_flow",
	"Flow State",
	"Epic",
	"Ribbon",
	{ rgb(240, 120, 220), rgb(110, 200, 255) },
	"Shifts colour with your flow tier.",
	"Reach Legendary flow"
)
reward(
	"Trail",
	"trail_platinum",
	"Platinum Streak",
	"Legendary",
	"Ribbon",
	{ rgb(150, 235, 255), rgb(255, 255, 255) },
	"For runners with ten platinum medals.",
	"Earn 10 platinum medals"
)
reward(
	"Trail",
	"trail_dream",
	"Dreamline",
	"Epic",
	"Aether",
	{ rgb(255, 160, 240), rgb(140, 160, 255) },
	"Brought back from the endless lanes.",
	"Clear 50 sections in one Dreamline run"
)
prestige(
	"Trail",
	"trail_gold",
	"Gilded Wake",
	10,
	"Sparks",
	{ rgb(255, 210, 90), rgb(255, 250, 220) },
	"Golden sparks for golden runners."
)

-- Landing effects -------------------------------------------------------------------------
add({
	Id = "land_dust",
	Category = "Landing",
	Name = "Dust Puff",
	Description = "A simple cloud of dust.",
	Rarity = "Common",
	Source = "Reward",
	Unlock = "Always available",
	Default = true,
	Style = "Dust",
	Colors = { rgb(200, 190, 175) },
})
shop(
	"Landing",
	"land_ripple",
	"Ripple",
	600,
	"Common",
	"Ripple",
	{ rgb(150, 220, 255) },
	"A ring spreads out from every landing."
)
shop(
	"Landing",
	"land_sparks",
	"Anvil Sparks",
	1000,
	"Rare",
	"Sparks",
	{ rgb(255, 150, 50) },
	"Land like a hammer.",
	"Ironworks"
)
shop(
	"Landing",
	"land_petals",
	"Petal Burst",
	1000,
	"Rare",
	"Petals",
	{ rgb(240, 120, 170) },
	"Soft landings, literally.",
	"Verdant"
)
shop(
	"Landing",
	"land_glitch",
	"Glitch",
	1500,
	"Epic",
	"Prism",
	{ rgb(70, 230, 255), rgb(255, 70, 190) },
	"The floor briefly forgets you were there.",
	"Gilded"
)
shop(
	"Landing",
	"land_snow",
	"Snowburst",
	1500,
	"Epic",
	"Snow",
	{ rgb(240, 248, 255) },
	"A puff of fresh powder.",
	"Frostreach"
)
shop(
	"Landing",
	"land_shock",
	"Shockwave",
	2600,
	"Legendary",
	"Shockwave",
	{ rgb(200, 170, 255) },
	"The Citadel feels it.",
	"Citadel"
)
reward(
	"Landing",
	"land_precision",
	"Bullseye",
	"Epic",
	"Ripple",
	{ rgb(255, 210, 100), rgb(255, 255, 255) },
	"Rings that snap to the centre of every perfect landing.",
	"Reach Expert in Precision Landing mastery"
)
prestige(
	"Landing",
	"land_crown",
	"Crowned",
	9,
	"Shockwave",
	{ rgb(255, 210, 90) },
	"A golden ring for every touchdown."
)

-- Emotes ---------------------------------------------------------------------------------
for _, emote in
	{
		{ "Wave", "Common", "Say hi.", 0 },
		{ "Salute", "Common", "Guild-style.", 0 },
		{ "Stretch", "Common", "Warm up properly.", 0 },
		{ "Cheer", "Common", "For a good run.", 300 },
		{ "Clap", "Common", "Respect.", 300 },
		{ "Bow", "Rare", "After a perfect line.", 500 },
		{ "Sit", "Common", "Take in the view.", 300 },
		{ "Flex", "Rare", "Earned it.", 600 },
		{ "Dance", "Rare", "Rooftop rhythm.", 800 },
		{ "Shrug", "Common", "Eh.", 300 },
		{ "Point", "Common", "That way.", 300 },
		{ "Handstand", "Epic", "Show-off.", 1400 },
	}
do
	local name, rarity, description, price = emote[1], emote[2], emote[3], emote[4]
	if price == 0 then
		add({
			Id = "emote_" .. string.lower(name),
			Category = "Emote",
			Name = name,
			Description = description,
			Rarity = rarity,
			Source = "Reward",
			Unlock = "Always available",
			Default = true,
			Style = name,
			Colors = {},
		})
	else
		shop("Emote", "emote_" .. string.lower(name), name, price, rarity, name, {}, description)
	end
end
reward("Emote", "emote_victorylap", "Victory Lap", "Epic", "Spin", {}, "A spinning celebration.", "Win 5 races")

-- Victory animations -------------------------------------------------------------------------
add({
	Id = "victory_fist",
	Category = "Victory",
	Name = "Fist Pump",
	Description = "Simple. Effective.",
	Rarity = "Common",
	Source = "Reward",
	Unlock = "Always available",
	Default = true,
	Style = "FistPump",
	Colors = {},
})
shop("Victory", "victory_salute", "Guild Salute", 500, "Common", "Salute", {}, "Formal, proud.")
shop("Victory", "victory_bow", "Curtain Call", 900, "Rare", "Bow", {}, "A deep bow to an empty rooftop.")
shop("Victory", "victory_backflip", "Backflip", 1600, "Epic", "Backflip", {}, "Finish with a flip.")
reward("Victory", "victory_point", "Point to the Sky", "Rare", "PointSky", {}, "Next stop: higher.", "Win a race")
reward(
	"Victory",
	"victory_spin",
	"Champion Spin",
	"Epic",
	"Spin",
	{},
	"For runners at the top of the board.",
	"Win 10 races"
)
prestige("Victory", "victory_kneel", "Legend's Rest", 8, "Kneel", {}, "One knee, head bowed. They know.")

-- Titles ---------------------------------------------------------------------------------------
local function title(id: string, text: string, rarity: string, unlock: string)
	add({
		Id = id,
		Category = "Title",
		Name = text,
		Text = text,
		Description = unlock,
		Rarity = rarity,
		Source = "Reward",
		Unlock = unlock,
		Style = "Title",
		Colors = {},
	})
end
add({
	Id = "title_rank",
	Category = "Title",
	Name = "Your Rank",
	Text = "",
	Description = "Show your reputation rank.",
	Rarity = "Common",
	Source = "Reward",
	Unlock = "Always available",
	Default = true,
	Style = "Title",
	Colors = {},
})
title("title_graduate", "Graduate", "Common", "Complete the Graduation Run")
title("title_tinroof", "Terrace Friend", "Common", "Complete Chapter 1")
title("title_ironworks", "Crane Whisperer", "Rare", "Complete Chapter 2")
title("title_verdant", "Rootwalker", "Rare", "Complete Chapter 3")
title("title_gilded", "Night Courier", "Rare", "Complete Chapter 4")
title("title_frost", "Summiteer", "Epic", "Complete Chapter 5")
title("title_citadel", "Keelbearer", "Epic", "Complete Chapter 6")
title("title_legend", "Skyline Legend", "Legendary", "Complete the epilogue")
title("title_platinum", "Platinum Runner", "Epic", "Earn 10 platinum medals")
title("title_collector", "Token Hoarder", "Rare", "Collect 300 course tokens")
title("title_explorer", "Cartographer", "Rare", "Find 40 discoveries")
title("title_secret", "Keeper of Secrets", "Epic", "Find every hidden cache in one district")
title("title_racer", "Podium Regular", "Rare", "Win 5 races")
title("title_relay", "Anchor Leg", "Rare", "Finish 10 relays")
title("title_spire", "Spire Climber", "Epic", "Clear floor 25 of the Spire")
title("title_dream", "Dreamwalker", "Epic", "Clear 50 Dreamline sections in one run")
title("title_flow", "Seamless", "Epic", "Reach Legendary flow")
for _, category in
	{ "WallRunning", "PrecisionLanding", "Grappling", "FlowChains", "Groundwork", "Climbing", "Aerial", "Traverse" }
do
	title(
		"title_master_" .. string.lower(category),
		"Grandmaster of " .. (string.gsub(category, "(%l)(%u)", "%1 %2")),
		"Legendary",
		"Reach Grandmaster in " .. (string.gsub(category, "(%l)(%u)", "%1 %2")) .. " mastery"
	)
end
title("title_crew", "Crewmate", "Common", "Join a runner crew")
title("title_century", "Centurion", "Legendary", "Reach level 100")

local Cosmetics = {}
Cosmetics.List = items
Cosmetics.ById = {} :: { [string]: Item }
Cosmetics.Categories = { "Outfit", "Gloves", "Shoes", "Backpack", "Trail", "Landing", "Emote", "Victory", "Title" }
Cosmetics.CategoryNames = {
	Outfit = "Outfits",
	Gloves = "Gloves",
	Shoes = "Shoes",
	Backpack = "Backpacks",
	Trail = "Trails",
	Landing = "Landing Effects",
	Emote = "Emotes",
	Victory = "Victory Animations",
	Title = "Titles",
}
-- Categories where you can equip several at once (everything else is one slot).
Cosmetics.MultiEquip = { Emote = 8 }
Cosmetics.Rarities = {
	Common = Color3.fromRGB(190, 195, 205),
	Rare = Color3.fromRGB(90, 170, 255),
	Epic = Color3.fromRGB(190, 110, 255),
	Legendary = Color3.fromRGB(255, 190, 70),
	Prestige = Color3.fromRGB(255, 120, 110),
}
Cosmetics.Defaults = {} :: { [string]: string }

for _, item in items do
	Cosmetics.ById[item.Id] = item
	if item.Default and not Cosmetics.Defaults[item.Category] then
		Cosmetics.Defaults[item.Category] = item.Id
	end
end

function Cosmetics.OfCategory(category: string): { Item }
	local result = {}
	for _, item in items do
		if item.Category == category then
			table.insert(result, item)
		end
	end
	return result
end

-- Items every player owns from the start.
function Cosmetics.StarterItems(): { string }
	local result = {}
	for _, item in items do
		if item.Default then
			table.insert(result, item.Id)
		end
	end
	return result
end

return Cosmetics

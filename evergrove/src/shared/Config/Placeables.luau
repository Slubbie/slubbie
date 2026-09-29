-- Everything you can place on your farm: buildings, machines, automation,
-- storage and decorations.
--
--   Size       { W, D } footprint in farm tiles (4 studs each)
--   Price      coins at Gus's shop (nil = craft only, see Config/Recipes)
--   Mats       materials also required when buying
--   Level      Estate level needed
--   Limit      max per farm (nil = no limit beyond the farm's total cap)
--   Model      builder in Shared/Models, Params passed to it
--   Paint      can be recoloured; Materials: allowed material choices
--   Scale      { min, max } free scale range, nil = fixed size
--   OnSoil     may be placed on tilled soil (sprinklers, scarecrows)
--   Walkable   no collision (paths, rugs)
--   Tags       environment tags it provides in Radius tiles (Greenhouse, PestGuard, ...)
--   Function   gameplay: Machine / Storage / Animal / Sprinkler / Interior / ...
--   Theme      decoration set shown in the catalog

export type Placeable = {
	Id: string,
	Name: string,
	Icon: string,
	Category: string,
	Size: { number },
	Height: number,
	Price: number?,
	Mats: { { Id: string, N: number } }?,
	Level: number,
	Limit: number?,
	Model: string,
	Params: { [string]: any },
	Paint: boolean?,
	Materials: { string }?,
	Scale: { number }?,
	OnSoil: boolean?,
	Walkable: boolean?,
	Tags: { string }?,
	Radius: number?,
	Function: { [string]: any }?,
	Theme: string?,
	Description: string?,
	Seasonal: string?,
	Rarity: string,
	Value: number?,
}

local List: { Placeable } = {}

local function p(def: any)
	def.Level = def.Level or 1
	def.Height = def.Height or 4
	def.Params = def.Params or {}
	def.Rarity = def.Rarity or "Common"
	table.insert(List, def)
end

local WOODS = { "Wood", "WoodPlanks", "Plastic" }
local STONES = { "Cobblestone", "Brick", "Slate", "Marble", "Granite", "Sandstone" }

-- Buildings -------------------------------------------------------------------------------------
p({
	Id = "coop",
	Name = "Coop",
	Icon = "🛖",
	Category = "Building",
	Size = { 4, 3 },
	Height = 9,
	Price = 6000,
	Mats = { { Id = "wood", N = 120 }, { Id = "stone", N = 40 } },
	Level = 2,
	Model = "Coop",
	Paint = true,
	Materials = WOODS,
	Function = { Kind = "Animal", Home = "Coop", Capacity = 4 },
	Description = "Houses 4 chickens, ducks or rabbits.",
})
p({
	Id = "big_coop",
	Name = "Big Coop",
	Icon = "🏠",
	Category = "Building",
	Size = { 6, 4 },
	Height = 11,
	Price = 18000,
	Mats = { { Id = "plank", N = 60 }, { Id = "stone_brick", N = 30 } },
	Level = 6,
	Model = "Coop",
	Params = { Big = true },
	Paint = true,
	Materials = WOODS,
	Function = { Kind = "Animal", Home = "Coop", Capacity = 10 },
	Description = "Houses 10 coop animals and comes with an incubator.",
})
p({
	Id = "barn",
	Name = "Barn",
	Icon = "🏚️",
	Category = "Building",
	Size = { 6, 5 },
	Height = 13,
	Price = 12000,
	Mats = { { Id = "wood", N = 200 }, { Id = "stone", N = 80 } },
	Level = 3,
	Model = "Barn",
	Paint = true,
	Materials = WOODS,
	Function = { Kind = "Animal", Home = "Barn", Capacity = 4 },
	Description = "Houses 4 cows, goats, sheep, pigs or alpacas.",
})
p({
	Id = "big_barn",
	Name = "Big Barn",
	Icon = "🏡",
	Category = "Building",
	Size = { 8, 6 },
	Height = 15,
	Price = 32000,
	Mats = { { Id = "plank", N = 120 }, { Id = "stone_brick", N = 60 } },
	Level = 8,
	Model = "Barn",
	Params = { Big = true },
	Paint = true,
	Materials = WOODS,
	Function = { Kind = "Animal", Home = "Barn", Capacity = 10 },
	Description = "Houses 10 barn animals with a breeding pen.",
})
p({
	Id = "stable",
	Name = "Stable",
	Icon = "🐎",
	Category = "Building",
	Size = { 4, 4 },
	Height = 10,
	Price = 15000,
	Mats = { { Id = "plank", N = 60 } },
	Level = 7,
	Model = "Stable",
	Paint = true,
	Materials = WOODS,
	Function = { Kind = "Animal", Home = "Stable", Capacity = 2 },
	Description = "Houses 2 horses. Whistle to ride them anywhere.",
})
p({
	Id = "apiary",
	Name = "Apiary",
	Icon = "🐝",
	Category = "Building",
	Size = { 3, 3 },
	Height = 6,
	Price = 7000,
	Mats = { { Id = "wood", N = 80 }, { Id = "sap", N = 20 } },
	Level = 4,
	Model = "Apiary",
	Tags = { "Apiary" },
	Radius = 6,
	Function = { Kind = "Animal", Home = "Apiary", Capacity = 4 },
	Description = "4 hives. Bees make flavoured honey from the flowers around them and pollinate crops.",
})
p({
	Id = "sanctuary",
	Name = "Mystic Sanctuary",
	Icon = "🔮",
	Category = "Building",
	Size = { 6, 6 },
	Height = 14,
	Price = 90000,
	Mats = { { Id = "refined_crystal", N = 10 }, { Id = "hardwood", N = 60 } },
	Level = 15,
	Model = "Sanctuary",
	Function = { Kind = "Animal", Home = "Sanctuary", Capacity = 4 },
	Rarity = "Epic",
	Description = "A glowing home for fantastical creatures.",
})
p({
	Id = "greenhouse",
	Name = "Greenhouse",
	Icon = "🌿",
	Category = "Building",
	Size = { 6, 5 },
	Height = 10,
	Price = 25000,
	Mats = { { Id = "glass", N = 40 }, { Id = "plank", N = 40 } },
	Level = 5,
	Model = "Greenhouse",
	Function = { Kind = "Interior", Tags = { "Greenhouse", "Cover", "Indoor" } },
	Description = "Grow anything year round (90% speed) and safe from storms. Its floor is plantable.",
})
p({
	Id = "large_greenhouse",
	Name = "Grand Greenhouse",
	Icon = "🏛️",
	Category = "Building",
	Size = { 10, 8 },
	Height = 14,
	Price = 80000,
	Mats = { { Id = "glass", N = 120 }, { Id = "iron_bar", N = 20 } },
	Level = 11,
	Model = "Greenhouse",
	Params = { Big = true },
	Function = { Kind = "Interior", Tags = { "Greenhouse", "Cover", "Indoor" } },
	Rarity = "Rare",
	Description = "A vast glasshouse.",
})
p({
	Id = "climate_dome",
	Name = "Climate Dome",
	Icon = "🔆",
	Category = "Building",
	Size = { 10, 8 },
	Height = 16,
	Price = 240000,
	Mats = { { Id = "glass", N = 150 }, { Id = "circuit", N = 6 }, { Id = "solar_cell", N = 4 } },
	Level = 18,
	Model = "Greenhouse",
	Params = { Big = true, Dome = true },
	Function = { Kind = "Interior", Tags = { "Greenhouse", "Cover", "Indoor", "Climate" } },
	Rarity = "Epic",
	Description = "Full climate control: every crop grows at 100% in any season.",
})
p({
	Id = "hydroponics",
	Name = "Hydroponics Bay",
	Icon = "💧",
	Category = "Building",
	Size = { 6, 3 },
	Height = 8,
	Price = 60000,
	Mats = { { Id = "glass", N = 40 }, { Id = "gear", N = 6 } },
	Level = 12,
	Model = "Hydroponics",
	Function = { Kind = "Interior", Tags = { "Indoor", "Cover", "Hydroponic" } },
	Rarity = "Rare",
	Description = "Soil-free racks: crops grow 30% faster and never need watering, but quality caps at Pristine.",
})
p({
	Id = "mushroom_cellar",
	Name = "Underground Cellar",
	Icon = "🕳️",
	Category = "Building",
	Size = { 5, 4 },
	Height = 5,
	Price = 30000,
	Mats = { { Id = "stone_brick", N = 60 }, { Id = "hardwood", N = 20 } },
	Level = 9,
	Model = "Cellar",
	Function = { Kind = "Interior", Tags = { "Indoor", "Cover", "Dark", "Underground" } },
	Description = "Dark, damp and perfect for mushrooms (any season).",
})
p({
	Id = "magic_planter",
	Name = "Enchanted Planter",
	Icon = "🪴",
	Category = "Building",
	Size = { 1, 1 },
	Height = 3,
	Level = 10,
	Limit = 12,
	Model = "Planter",
	Function = { Kind = "Interior", Tags = { "Indoor", "Planter", "Climate" }, MutationBoost = 1.5 },
	Rarity = "Rare",
	Description = "One enchanted pot: any season, and mutations are 1.5× more likely.",
})
p({
	Id = "workshop",
	Name = "Workshop",
	Icon = "🛠️",
	Category = "Building",
	Size = { 4, 3 },
	Height = 9,
	Price = 9000,
	Mats = { { Id = "wood", N = 150 }, { Id = "copper_bar", N = 5 } },
	Level = 3,
	Limit = 1,
	Model = "Workshop",
	Paint = true,
	Function = { Kind = "Station", Station = "Workshop" },
	Description = "Unlocks advanced crafting.",
})
p({
	Id = "kitchen",
	Name = "Farm Kitchen",
	Icon = "🍳",
	Category = "Building",
	Size = { 3, 3 },
	Height = 8,
	Price = 7000,
	Mats = { { Id = "stone_brick", N = 20 }, { Id = "plank", N = 20 } },
	Level = 2,
	Limit = 1,
	Model = "Kitchen",
	Paint = true,
	Function = { Kind = "Station", Station = "Kitchen" },
	Description = "Cook meals that restore energy and give buffs.",
})
p({
	Id = "genetics_lab",
	Name = "Genetics Lab",
	Icon = "🧬",
	Category = "Building",
	Size = { 4, 3 },
	Height = 9,
	Level = 9,
	Limit = 1,
	Model = "Lab",
	Function = { Kind = "Station", Station = "Lab" },
	Rarity = "Rare",
	Description = "Cross-breed seeds into hybrids and study animal genes.",
})
p({
	Id = "alchemy_table",
	Name = "Alchemy Table",
	Icon = "⚗️",
	Category = "Building",
	Size = { 2, 2 },
	Height = 5,
	Level = 7,
	Limit = 1,
	Model = "AlchemyTable",
	Function = { Kind = "Station", Station = "Alchemy" },
	Rarity = "Uncommon",
	Description = "Brew potions.",
})

-- Storage -------------------------------------------------------------------------------------------
p({
	Id = "chest",
	Name = "Chest",
	Icon = "🧰",
	Category = "Storage",
	Size = { 1, 1 },
	Height = 3,
	Price = 400,
	Mats = { { Id = "wood", N = 30 } },
	Model = "Chest",
	Paint = true,
	Materials = WOODS,
	Function = { Kind = "Storage", Slots = 24 },
})
p({
	Id = "big_chest",
	Name = "Big Chest",
	Icon = "🗃️",
	Category = "Storage",
	Size = { 2, 1 },
	Height = 3,
	Price = 2400,
	Mats = { { Id = "hardwood", N = 10 } },
	Level = 4,
	Model = "Chest",
	Params = { Big = true },
	Paint = true,
	Materials = WOODS,
	Function = { Kind = "Storage", Slots = 48 },
})
p({
	Id = "storage_barn",
	Name = "Storage Barn",
	Icon = "🏬",
	Category = "Storage",
	Size = { 5, 4 },
	Height = 11,
	Price = 30000,
	Mats = { { Id = "plank", N = 100 } },
	Level = 7,
	Limit = 2,
	Model = "Barn",
	Params = { Storage = true },
	Paint = true,
	Function = { Kind = "Storage", Slots = 120 },
})
p({
	Id = "silo",
	Name = "Silo",
	Icon = "🗼",
	Category = "Automation",
	Size = { 2, 2 },
	Height = 16,
	Price = 8000,
	Mats = { { Id = "stone", N = 100 }, { Id = "copper_bar", N = 5 } },
	Level = 4,
	Model = "Silo",
	Paint = true,
	Function = { Kind = "Silo", Capacity = 600 },
	Description = "Network storage for automation (and hay for auto-feeders).",
})
p({
	Id = "smart_silo",
	Name = "Smart Silo",
	Icon = "🏙️",
	Category = "Automation",
	Size = { 3, 3 },
	Height = 22,
	Price = 60000,
	Mats = { { Id = "iron_bar", N = 20 }, { Id = "circuit", N = 2 } },
	Level = 12,
	Model = "Silo",
	Params = { Smart = true },
	Paint = true,
	Function = { Kind = "Silo", Capacity = 4000, Sort = true },
	Rarity = "Rare",
	Description = "Huge network storage that sorts itself.",
})

-- Machines (one placeable per machine in Config/Machines) ----------------------------------------------
local machines = {
	{ "preserves_jar", 1, 1, 4, 2 },
	{ "fermenter", 1, 1, 4, 5 },
	{ "juicer", 1, 1, 4, 3 },
	{ "dehydrator", 1, 1, 4, 6 },
	{ "mill", 2, 2, 12, 3 },
	{ "cheese_press", 1, 1, 4, 4 },
	{ "butter_churn", 1, 1, 4, 3 },
	{ "mayo_mixer", 1, 1, 4, 3 },
	{ "loom", 2, 1, 6, 5 },
	{ "oil_press", 1, 1, 5, 6 },
	{ "smoker", 1, 1, 5, 5 },
	{ "syrup_boiler", 1, 1, 5, 6 },
	{ "canning_station", 2, 1, 5, 8 },
	{ "perfumery", 1, 1, 6, 9 },
	{ "flower_press", 1, 1, 4, 4 },
	{ "furnace", 1, 1, 6, 2 },
	{ "crystal_refinery", 2, 2, 7, 12 },
	{ "seed_maker", 1, 1, 5, 5 },
	{ "honey_extractor", 1, 1, 4, 5 },
	{ "alchemy_still", 1, 1, 6, 12 },
	{ "grand_kitchen", 4, 3, 12, 16 },
}
for _, m in machines do
	p({
		Id = m[1],
		Name = "",
		Icon = "",
		Category = "Machine",
		Size = { m[2], m[3] },
		Height = m[4],
		Level = m[5],
		Model = "Machine",
		Params = { Style = m[1] },
		Function = { Kind = "Machine", Machine = m[1] },
	})
end

-- Automation ------------------------------------------------------------------------------------------
p({
	Id = "sprinkler",
	Name = "Sprinkler",
	Icon = "💦",
	Category = "Automation",
	Size = { 1, 1 },
	Height = 2,
	Level = 3,
	OnSoil = true,
	Model = "Sprinkler",
	Params = { Tier = 1 },
	Function = { Kind = "Sprinkler", Shape = "Cross", Range = 1 },
	Description = "Waters the 4 adjacent tiles every morning.",
})
p({
	Id = "quality_sprinkler",
	Name = "Quality Sprinkler",
	Icon = "💦",
	Category = "Automation",
	Size = { 1, 1 },
	Height = 2,
	Level = 6,
	OnSoil = true,
	Model = "Sprinkler",
	Params = { Tier = 2 },
	Function = { Kind = "Sprinkler", Shape = "Square", Range = 1 },
	Rarity = "Uncommon",
	Description = "Waters the 8 surrounding tiles every morning.",
})
p({
	Id = "crystal_sprinkler",
	Name = "Crystal Sprinkler",
	Icon = "💎",
	Category = "Automation",
	Size = { 1, 1 },
	Height = 2,
	Level = 12,
	OnSoil = true,
	Model = "Sprinkler",
	Params = { Tier = 3 },
	Function = { Kind = "Sprinkler", Shape = "Square", Range = 2 },
	Rarity = "Rare",
	Description = "Waters a 5×5 area every morning.",
})
p({
	Id = "mist_tower",
	Name = "Mist Tower",
	Icon = "🌫️",
	Category = "Automation",
	Size = { 1, 1 },
	Height = 8,
	Level = 18,
	OnSoil = true,
	Model = "MistTower",
	Function = { Kind = "Sprinkler", Shape = "Square", Range = 4, Keep = true },
	Rarity = "Epic",
	Description = "Keeps a 9×9 area moist all day.",
})
p({
	Id = "water_tower",
	Name = "Water Tower",
	Icon = "🗼",
	Category = "Automation",
	Size = { 2, 2 },
	Height = 18,
	Price = 40000,
	Mats = { { Id = "iron_bar", N = 15 } },
	Level = 10,
	Limit = 2,
	Model = "WaterTower",
	Radius = 18,
	Tags = { "WaterTower" },
	Description = "Sprinklers within 18 tiles reach 1 tile further.",
})
p({
	Id = "scarecrow",
	Name = "Scarecrow",
	Icon = "🧑‍🌾",
	Category = "Automation",
	Size = { 1, 1 },
	Height = 7,
	Price = 500,
	Mats = { { Id = "wood", N = 20 }, { Id = "fiber", N = 20 } },
	Level = 2,
	OnSoil = true,
	Model = "Scarecrow",
	Paint = true,
	Tags = { "PestGuard" },
	Radius = 6,
	Description = "Keeps pests off crops within 6 tiles.",
})
p({
	Id = "lightning_rod",
	Name = "Lightning Rod",
	Icon = "⚡",
	Category = "Automation",
	Size = { 1, 1 },
	Height = 12,
	Level = 6,
	Model = "LightningRod",
	Tags = { "LightningRod" },
	Radius = 8,
	Function = { Kind = "LightningRod" },
	Description = "Catches lightning (making batteries) and makes nearby crops Charged more often.",
})
p({
	Id = "hail_net",
	Name = "Crop Cover",
	Icon = "⛺",
	Category = "Automation",
	Size = { 3, 3 },
	Height = 5,
	Price = 1500,
	Mats = { { Id = "cloth", N = 2 }, { Id = "wood", N = 20 } },
	Level = 5,
	OnSoil = true,
	Model = "HailNet",
	Tags = { "Cover" },
	Radius = 2,
	Walkable = true,
	Description = "Protects crops underneath from hail.",
})
p({
	Id = "shade_sail",
	Name = "Shade Sail",
	Icon = "⛱️",
	Category = "Automation",
	Size = { 3, 3 },
	Height = 6,
	Price = 1800,
	Mats = { { Id = "cloth", N = 2 } },
	Level = 6,
	OnSoil = true,
	Model = "ShadeSail",
	Paint = true,
	Tags = { "Shade", "Dark" },
	Radius = 2,
	Walkable = true,
	Description = "Shade protects from scorch and lets mushrooms grow.",
})
p({
	Id = "celestial_beacon",
	Name = "Celestial Beacon",
	Icon = "🌟",
	Category = "Automation",
	Size = { 1, 1 },
	Height = 10,
	Level = 16,
	Limit = 4,
	Model = "Beacon",
	Tags = { "CelestialBeacon" },
	Radius = 6,
	Rarity = "Epic",
	Description = "Starlight for Celestial Vines, and more Celestial mutations nearby.",
})
p({
	Id = "windmill",
	Name = "Windmill",
	Icon = "🌬️",
	Category = "Automation",
	Size = { 3, 3 },
	Height = 24,
	Price = 35000,
	Mats = { { Id = "plank", N = 80 }, { Id = "gear", N = 4 } },
	Level = 9,
	Limit = 3,
	Model = "Windmill",
	Paint = true,
	Radius = 12,
	Function = { Kind = "Power", Speed = 0.1, Windy = 0.25 },
	Description = "Machines within 12 tiles run 10% faster (25% in wind).",
})
p({
	Id = "solar_array",
	Name = "Solar Array",
	Icon = "🔆",
	Category = "Automation",
	Size = { 3, 2 },
	Height = 5,
	Level = 14,
	Limit = 4,
	Model = "Solar",
	Radius = 10,
	Function = { Kind = "Power", Speed = 0.15, Sunny = 0.3 },
	Rarity = "Rare",
	Description = "Machines within 10 tiles run 15% faster (30% in sunshine).",
})
p({
	Id = "auto_feeder",
	Name = "Auto-Feeder",
	Icon = "🥣",
	Category = "Automation",
	Size = { 1, 1 },
	Height = 4,
	Level = 8,
	Model = "Feeder",
	Radius = 12,
	Function = { Kind = "Feeder" },
	Description = "Feeds animals in buildings within 12 tiles every morning, from your silos.",
})
p({
	Id = "product_collector",
	Name = "Product Collector",
	Icon = "🧺",
	Category = "Automation",
	Size = { 1, 1 },
	Height = 4,
	Level = 10,
	Model = "Collector",
	Radius = 12,
	Function = { Kind = "Collector" },
	Rarity = "Uncommon",
	Description = "Collects animal products within 12 tiles into your silos.",
})
p({
	Id = "harvest_drone_hub",
	Name = "Harvest Drone Hub",
	Icon = "🛸",
	Category = "Automation",
	Size = { 2, 2 },
	Height = 5,
	Level = 14,
	Limit = 6,
	Model = "DroneHub",
	Radius = 10,
	Function = { Kind = "Harvester", Replant = true, PerMinute = 30 },
	Rarity = "Rare",
	Description = "Drones harvest ripe crops within 10 tiles into your silos and can replant from silo seeds.",
})
p({
	Id = "farmbot",
	Name = "Farmbot",
	Icon = "🤖",
	Category = "Automation",
	Size = { 1, 1 },
	Height = 4,
	Level = 20,
	Limit = 4,
	Model = "Farmbot",
	Radius = 8,
	Function = { Kind = "Farmbot", PerMinute = 20 },
	Rarity = "Epic",
	Description = "Tills, plants (a crop you choose) and waters every tile within 8 tiles.",
})
p({
	Id = "logistics_hub",
	Name = "Logistics Hub",
	Icon = "📡",
	Category = "Automation",
	Size = { 2, 2 },
	Height = 7,
	Level = 12,
	Limit = 1,
	Model = "Hub",
	Function = { Kind = "Logistics" },
	Rarity = "Rare",
	Description = "Links machines to silos: machines set to Auto pull inputs from and push outputs to silos.",
})
p({
	Id = "farm_controller",
	Name = "Farm Controller",
	Icon = "🖥️",
	Category = "Automation",
	Size = { 1, 1 },
	Height = 5,
	Level = 16,
	Limit = 1,
	Model = "Controller",
	Function = { Kind = "Controller" },
	Rarity = "Epic",
	Description = "Program your farm: auto-sell rules, machine priorities and replant choices.",
})
p({
	Id = "shipping_dock",
	Name = "Shipping Dock",
	Icon = "🚢",
	Category = "Automation",
	Size = { 3, 2 },
	Height = 6,
	Price = 45000,
	Mats = { { Id = "hardwood", N = 40 }, { Id = "iron_bar", N = 10 } },
	Level = 12,
	Limit = 1,
	Model = "Dock",
	Function = { Kind = "Dock" },
	Description = "Auto-sells silo items you choose every morning at market price (minus 5%).",
})
p({
	Id = "conveyor",
	Name = "Conveyor Belt",
	Icon = "➡️",
	Category = "Automation",
	Size = { 1, 1 },
	Height = 1,
	Price = 300,
	Mats = { { Id = "iron_bar", N = 1 } },
	Level = 12,
	Walkable = true,
	Model = "Conveyor",
	Description = "Decorative logistics: shows items flowing between your machines.",
})

-- Farm utilities --------------------------------------------------------------------------------------
p({
	Id = "pond",
	Name = "Fishing Pond",
	Icon = "🎣",
	Category = "Utility",
	Size = { 4, 3 },
	Height = 1,
	Price = 5000,
	Mats = { { Id = "stone", N = 60 } },
	Level = 3,
	Limit = 3,
	Model = "Pond",
	Function = { Kind = "Water", Water = "Pond" },
	Description = "Fish at home. Also refills your watering can.",
})
p({
	Id = "well",
	Name = "Well",
	Icon = "🪣",
	Category = "Utility",
	Size = { 1, 1 },
	Height = 5,
	Price = 1000,
	Mats = { { Id = "stone", N = 50 } },
	Model = "Well",
	Paint = true,
	Materials = STONES,
	Function = { Kind = "Water", Water = "Well" },
	Description = "Refill your watering can.",
})
p({
	Id = "display_pedestal",
	Name = "Display Pedestal",
	Icon = "🏆",
	Category = "Utility",
	Size = { 1, 1 },
	Height = 4,
	Price = 1200,
	Level = 3,
	Model = "Pedestal",
	Paint = true,
	Materials = STONES,
	Function = { Kind = "Display", Slots = 1 },
	Description = "Show off a prized crop, fish or gem to visitors.",
})
p({
	Id = "trophy_case",
	Name = "Trophy Case",
	Icon = "🏅",
	Category = "Utility",
	Size = { 2, 1 },
	Height = 6,
	Price = 5000,
	Level = 6,
	Model = "TrophyCase",
	Paint = true,
	Function = { Kind = "Display", Slots = 4 },
})
p({
	Id = "market_stall",
	Name = "Market Stall",
	Icon = "🏪",
	Category = "Utility",
	Size = { 2, 2 },
	Height = 7,
	Price = 4000,
	Mats = { { Id = "plank", N = 30 }, { Id = "cloth", N = 2 } },
	Level = 4,
	Limit = 1,
	Model = "Stall",
	Paint = true,
	Function = { Kind = "Stall", Slots = 6 },
	Description = "Sell your goods to other players at your own prices.",
})
p({
	Id = "sign",
	Name = "Wooden Sign",
	Icon = "🪧",
	Category = "Decor",
	Size = { 1, 1 },
	Height = 4,
	Price = 150,
	Model = "Sign",
	Paint = true,
	Function = { Kind = "Sign" },
	Theme = "Rustic",
})
p({
	Id = "big_sign",
	Name = "Farm Sign",
	Icon = "🪧",
	Category = "Decor",
	Size = { 3, 1 },
	Height = 7,
	Price = 900,
	Model = "Sign",
	Params = { Big = true },
	Paint = true,
	Function = { Kind = "Sign" },
	Theme = "Rustic",
})

-- Decorations -----------------------------------------------------------------------------------------
local function decor(id, name, icon, category, size, height, price, model, params, extra)
	local def = {
		Id = id,
		Name = name,
		Icon = icon,
		Category = category,
		Size = size,
		Height = height,
		Price = price,
		Model = model,
		Params = params or {},
	}
	for k, v in extra or {} do
		def[k] = v
	end
	p(def)
end

-- Fences & gates
decor(
	"wood_fence",
	"Wood Fence",
	"🪵",
	"Fence",
	{ 1, 1 },
	3,
	20,
	"Fence",
	{ Style = "Wood" },
	{ Paint = true, Materials = WOODS, Theme = "Rustic" }
)
decor(
	"picket_fence",
	"Picket Fence",
	"🤍",
	"Fence",
	{ 1, 1 },
	3,
	35,
	"Fence",
	{ Style = "Picket" },
	{ Paint = true, Theme = "Cottage" }
)
decor(
	"stone_wall",
	"Stone Wall",
	"🧱",
	"Fence",
	{ 1, 1 },
	3,
	45,
	"Fence",
	{ Style = "Stone" },
	{ Paint = true, Materials = STONES, Theme = "Rustic" }
)
decor(
	"iron_fence",
	"Iron Fence",
	"⚫",
	"Fence",
	{ 1, 1 },
	4,
	90,
	"Fence",
	{ Style = "Iron" },
	{ Paint = true, Level = 5, Theme = "Industrial" }
)
decor("hedge", "Hedge", "🌳", "Fence", { 1, 1 }, 4, 60, "Fence", { Style = "Hedge" }, { Theme = "Cottage" })
decor(
	"bamboo_fence",
	"Bamboo Fence",
	"🎋",
	"Fence",
	{ 1, 1 },
	4,
	55,
	"Fence",
	{ Style = "Bamboo" },
	{ Theme = "Zen" }
)
decor(
	"crystal_fence",
	"Crystal Fence",
	"💎",
	"Fence",
	{ 1, 1 },
	4,
	400,
	"Fence",
	{ Style = "Crystal" },
	{ Level = 12, Theme = "Celestial", Rarity = "Rare" }
)
decor(
	"wood_gate",
	"Wood Gate",
	"🚪",
	"Fence",
	{ 1, 1 },
	3,
	80,
	"Gate",
	{ Style = "Wood" },
	{ Paint = true, Walkable = true, Theme = "Rustic" }
)

-- Paths & ground
decor("dirt_path", "Dirt Path", "🟫", "Path", { 1, 1 }, 0.2, 5, "Path", { Style = "Dirt" }, { Walkable = true })
decor("gravel_path", "Gravel Path", "⚪", "Path", { 1, 1 }, 0.2, 10, "Path", { Style = "Gravel" }, { Walkable = true })
decor(
	"cobble_path",
	"Cobblestone Path",
	"🪨",
	"Path",
	{ 1, 1 },
	0.2,
	18,
	"Path",
	{ Style = "Cobble" },
	{ Walkable = true, Paint = true, Theme = "Rustic" }
)
decor(
	"brick_path",
	"Brick Path",
	"🧱",
	"Path",
	{ 1, 1 },
	0.2,
	22,
	"Path",
	{ Style = "Brick" },
	{ Walkable = true, Paint = true, Theme = "Cottage" }
)
decor(
	"plank_path",
	"Boardwalk",
	"🟫",
	"Path",
	{ 1, 1 },
	0.3,
	20,
	"Path",
	{ Style = "Plank" },
	{ Walkable = true, Paint = true, Materials = WOODS }
)
decor(
	"stepping_stones",
	"Stepping Stones",
	"🪨",
	"Path",
	{ 1, 1 },
	0.3,
	15,
	"Path",
	{ Style = "Stepping" },
	{ Walkable = true, Theme = "Zen" }
)
decor(
	"raked_sand",
	"Raked Sand",
	"〰️",
	"Path",
	{ 1, 1 },
	0.2,
	25,
	"Path",
	{ Style = "Sand" },
	{ Walkable = true, Theme = "Zen" }
)
decor(
	"crystal_path",
	"Crystal Path",
	"🔷",
	"Path",
	{ 1, 1 },
	0.2,
	120,
	"Path",
	{ Style = "Crystal" },
	{ Walkable = true, Level = 10, Theme = "Celestial" }
)
decor(
	"flower_carpet",
	"Flower Carpet",
	"🌸",
	"Path",
	{ 1, 1 },
	0.3,
	40,
	"Path",
	{ Style = "Flowers" },
	{ Walkable = true, Paint = true, Theme = "Fairy" }
)

-- Lighting
decor(
	"lantern_post",
	"Lantern Post",
	"🏮",
	"Lighting",
	{ 1, 1 },
	6,
	250,
	"Lamp",
	{ Style = "Lantern" },
	{ Paint = true, Theme = "Rustic" }
)
decor(
	"street_lamp",
	"Street Lamp",
	"💡",
	"Lighting",
	{ 1, 1 },
	9,
	400,
	"Lamp",
	{ Style = "Street" },
	{ Paint = true, Theme = "Industrial" }
)
decor("torch", "Garden Torch", "🔥", "Lighting", { 1, 1 }, 4, 60, "Lamp", { Style = "Torch" })
decor(
	"crystal_lamp",
	"Crystal Lamp",
	"🔷",
	"Lighting",
	{ 1, 1 },
	5,
	1200,
	"Lamp",
	{ Style = "Crystal" },
	{ Level = 10, Theme = "Celestial", Rarity = "Rare" }
)
decor(
	"paper_lantern",
	"Paper Lantern",
	"🏮",
	"Lighting",
	{ 1, 1 },
	5,
	180,
	"Lamp",
	{ Style = "Paper" },
	{ Paint = true, Theme = "Zen" }
)
decor(
	"stone_lantern",
	"Stone Lantern",
	"🗿",
	"Lighting",
	{ 1, 1 },
	4,
	300,
	"Lamp",
	{ Style = "Stone" },
	{ Theme = "Zen" }
)
decor("firefly_jar", "Firefly Jar", "✨", "Lighting", { 1, 1 }, 2, 220, "Lamp", { Style = "Jar" }, { Theme = "Fairy" })
decor(
	"string_lights",
	"String Lights",
	"💡",
	"Lighting",
	{ 3, 1 },
	6,
	350,
	"StringLights",
	{},
	{ Paint = true, Theme = "Cottage" }
)
decor(
	"campfire",
	"Campfire",
	"🔥",
	"Lighting",
	{ 1, 1 },
	2,
	200,
	"Campfire",
	{},
	{ Theme = "Rustic", Tags = { "Warmth" }, Radius = 3 }
)
decor(
	"star_lamp",
	"Star Lamp",
	"⭐",
	"Lighting",
	{ 1, 1 },
	7,
	2500,
	"Lamp",
	{ Style = "Star" },
	{ Level = 14, Theme = "Celestial", Rarity = "Epic" }
)

-- Nature
decor(
	"oak_tree",
	"Oak Tree",
	"🌳",
	"Nature",
	{ 2, 2 },
	16,
	600,
	"DecorTree",
	{ Style = "Round" },
	{ Scale = { 0.6, 1.6 } }
)
decor(
	"cherry_tree",
	"Blossom Tree",
	"🌸",
	"Nature",
	{ 2, 2 },
	14,
	900,
	"DecorTree",
	{ Style = "Blossom" },
	{ Scale = { 0.6, 1.6 }, Theme = "Zen" }
)
decor(
	"pine_tree",
	"Pine Tree",
	"🌲",
	"Nature",
	{ 2, 2 },
	18,
	600,
	"DecorTree",
	{ Style = "Cone" },
	{ Scale = { 0.6, 1.6 } }
)
decor(
	"palm_tree",
	"Palm Tree",
	"🌴",
	"Nature",
	{ 2, 2 },
	16,
	800,
	"DecorTree",
	{ Style = "Palm" },
	{ Scale = { 0.6, 1.4 } }
)
decor(
	"maple_tree",
	"Maple Tree",
	"🍁",
	"Nature",
	{ 2, 2 },
	15,
	800,
	"DecorTree",
	{ Style = "Maple" },
	{ Scale = { 0.6, 1.6 } }
)
decor(
	"bonsai",
	"Bonsai",
	"🪴",
	"Nature",
	{ 1, 1 },
	3,
	1200,
	"DecorTree",
	{ Style = "Bonsai" },
	{ Theme = "Zen", Scale = { 0.8, 1.5 } }
)
decor("bush", "Round Bush", "🌿", "Nature", { 1, 1 }, 3, 80, "Bush", {}, { Paint = true, Scale = { 0.6, 1.8 } })
decor(
	"flower_bed",
	"Flower Bed",
	"🌷",
	"Nature",
	{ 2, 1 },
	2,
	150,
	"FlowerBed",
	{},
	{ Paint = true, Theme = "Cottage" }
)
decor(
	"rock_cluster",
	"Rock Cluster",
	"🪨",
	"Nature",
	{ 1, 1 },
	3,
	60,
	"Rocks",
	{},
	{ Scale = { 0.5, 2 }, Paint = true, Materials = STONES }
)
decor("mushroom_ring", "Mushroom Ring", "🍄", "Nature", { 2, 2 }, 2, 350, "MushroomRing", {}, { Theme = "Fairy" })
decor(
	"glow_mushrooms",
	"Glowing Mushrooms",
	"🍄",
	"Nature",
	{ 1, 1 },
	3,
	600,
	"MushroomRing",
	{ Glow = true, Small = true },
	{ Theme = "Fairy", Level = 8 }
)
decor("hay_bale", "Hay Bale", "🌾", "Nature", { 1, 1 }, 2, 40, "HayBale", {}, { Theme = "Rustic" })
decor("log_pile", "Log Pile", "🪵", "Nature", { 2, 1 }, 2, 60, "LogPile", {}, { Theme = "Rustic" })
decor(
	"tall_grass",
	"Wild Grass",
	"🌾",
	"Nature",
	{ 1, 1 },
	2,
	15,
	"Grass",
	{},
	{ Walkable = true, Scale = { 0.6, 1.6 } }
)
decor(
	"sunflower_patch",
	"Sunflower Patch",
	"🌻",
	"Nature",
	{ 1, 1 },
	5,
	90,
	"FlowerBed",
	{ Tall = true },
	{ Theme = "Cottage" }
)

-- Water features
decor(
	"fountain",
	"Fountain",
	"⛲",
	"Water",
	{ 2, 2 },
	6,
	3500,
	"Fountain",
	{},
	{ Paint = true, Materials = STONES, Level = 4 }
)
decor(
	"grand_fountain",
	"Grand Fountain",
	"⛲",
	"Water",
	{ 4, 4 },
	10,
	18000,
	"Fountain",
	{ Big = true },
	{ Paint = true, Materials = STONES, Level = 10, Rarity = "Rare" }
)
decor(
	"birdbath",
	"Birdbath",
	"🐦",
	"Water",
	{ 1, 1 },
	3,
	400,
	"Birdbath",
	{},
	{ Paint = true, Materials = STONES, Theme = "Cottage" }
)
decor("koi_pond", "Koi Pond", "🎏", "Water", { 3, 3 }, 1, 4500, "Pond", { Koi = true }, { Theme = "Zen", Level = 6 })
decor("waterfall_rock", "Waterfall Rock", "🏞️", "Water", { 2, 2 }, 7, 5200, "Waterfall", {}, { Level = 7 })

-- Furniture
decor(
	"bench",
	"Garden Bench",
	"🪑",
	"Furniture",
	{ 2, 1 },
	3,
	220,
	"Bench",
	{},
	{ Paint = true, Materials = WOODS, Theme = "Cottage" }
)
decor("log_bench", "Log Bench", "🪵", "Furniture", { 2, 1 }, 2, 120, "Bench", { Log = true }, { Theme = "Rustic" })
decor(
	"picnic_table",
	"Picnic Table",
	"🧺",
	"Furniture",
	{ 2, 2 },
	3,
	500,
	"Table",
	{ Picnic = true },
	{ Paint = true, Theme = "Rustic" }
)
decor(
	"garden_table",
	"Garden Table",
	"☕",
	"Furniture",
	{ 1, 1 },
	3,
	300,
	"Table",
	{},
	{ Paint = true, Theme = "Cottage" }
)
decor("swing", "Porch Swing", "🪢", "Furniture", { 2, 1 }, 7, 800, "Swing", {}, { Paint = true, Theme = "Cottage" })
decor("hammock", "Hammock", "🏝️", "Furniture", { 3, 1 }, 5, 700, "Hammock", {}, { Paint = true })
decor(
	"rocking_chair",
	"Rocking Chair",
	"🪑",
	"Furniture",
	{ 1, 1 },
	4,
	380,
	"Chair",
	{ Rocking = true },
	{ Paint = true, Theme = "Rustic" }
)
decor("parasol", "Parasol", "⛱️", "Furniture", { 1, 1 }, 6, 300, "Parasol", {}, { Paint = true })
decor("bbq_grill", "BBQ Grill", "🍖", "Furniture", { 1, 1 }, 4, 900, "Grill", {}, { Theme = "Industrial" })
decor("barrel", "Barrel", "🛢️", "Furniture", { 1, 1 }, 3, 60, "Barrel", {}, { Paint = true, Theme = "Rustic" })
decor(
	"crate_stack",
	"Crate Stack",
	"📦",
	"Furniture",
	{ 1, 1 },
	4,
	80,
	"Crates",
	{},
	{ Paint = true, Theme = "Industrial" }
)
decor("wagon", "Farm Wagon", "🛒", "Furniture", { 2, 1 }, 4, 1500, "Wagon", {}, { Paint = true, Theme = "Rustic" })
decor("milk_cans", "Milk Cans", "🥛", "Furniture", { 1, 1 }, 2, 120, "MilkCans", {}, { Theme = "Rustic" })
decor(
	"birdhouse",
	"Birdhouse",
	"🏠",
	"Furniture",
	{ 1, 1 },
	6,
	250,
	"Birdhouse",
	{},
	{ Paint = true, Theme = "Cottage" }
)

-- Structures
decor(
	"gazebo",
	"Gazebo",
	"⛩️",
	"Structure",
	{ 3, 3 },
	12,
	7500,
	"Gazebo",
	{},
	{ Paint = true, Materials = WOODS, Level = 5 }
)
decor(
	"pergola",
	"Pergola",
	"🌿",
	"Structure",
	{ 2, 2 },
	9,
	3200,
	"Pergola",
	{},
	{ Paint = true, Walkable = true, Theme = "Cottage" }
)
decor(
	"flower_arch",
	"Flower Arch",
	"💐",
	"Structure",
	{ 2, 1 },
	8,
	1500,
	"Arch",
	{ Flowers = true },
	{ Paint = true, Walkable = true, Theme = "Cottage" }
)
decor(
	"torii",
	"Torii Gate",
	"⛩️",
	"Structure",
	{ 3, 1 },
	10,
	4000,
	"Arch",
	{ Torii = true },
	{ Walkable = true, Theme = "Zen", Level = 6 }
)
decor(
	"constellation_arch",
	"Constellation Arch",
	"🌌",
	"Structure",
	{ 3, 1 },
	11,
	12000,
	"Arch",
	{ Stars = true },
	{ Walkable = true, Theme = "Celestial", Level = 14, Rarity = "Epic" }
)
decor(
	"bridge",
	"Garden Bridge",
	"🌉",
	"Structure",
	{ 3, 2 },
	3,
	2800,
	"Bridge",
	{},
	{ Paint = true, Materials = WOODS }
)
decor(
	"tool_shed",
	"Tool Shed",
	"🛖",
	"Structure",
	{ 2, 2 },
	8,
	2500,
	"Shed",
	{},
	{ Paint = true, Materials = WOODS, Theme = "Rustic" }
)
decor("doghouse", "Doghouse", "🐕", "Structure", { 1, 1 }, 4, 700, "Doghouse", {}, { Paint = true })
decor(
	"treehouse",
	"Treehouse",
	"🌳",
	"Structure",
	{ 4, 4 },
	22,
	22000,
	"Treehouse",
	{},
	{ Paint = true, Level = 9, Rarity = "Rare" }
)
decor(
	"mushroom_house",
	"Mushroom House",
	"🍄",
	"Structure",
	{ 3, 3 },
	12,
	9000,
	"MushroomHouse",
	{},
	{ Paint = true, Theme = "Fairy", Level = 8 }
)
decor(
	"windmill_decor",
	"Little Windmill",
	"🌬️",
	"Structure",
	{ 1, 1 },
	7,
	900,
	"Windmill",
	{ Small = true },
	{ Paint = true, Theme = "Cottage" }
)
decor(
	"gear_sculpture",
	"Gear Sculpture",
	"⚙️",
	"Structure",
	{ 2, 2 },
	8,
	3000,
	"GearSculpture",
	{},
	{ Theme = "Industrial", Level = 8 }
)
decor(
	"pipe_works",
	"Pipe Works",
	"🔧",
	"Structure",
	{ 2, 1 },
	5,
	1400,
	"Pipes",
	{},
	{ Paint = true, Theme = "Industrial" }
)
decor(
	"orb_pedestal",
	"Orb Pedestal",
	"🔮",
	"Structure",
	{ 1, 1 },
	5,
	3600,
	"OrbPedestal",
	{},
	{ Theme = "Celestial", Level = 12, Rarity = "Rare" }
)

-- Statues
decor(
	"gnome",
	"Garden Gnome",
	"🧙",
	"Statue",
	{ 1, 1 },
	2,
	250,
	"Statue",
	{ Shape = "Gnome" },
	{ Paint = true, Theme = "Cottage", Scale = { 0.7, 2.5 } }
)
decor(
	"chicken_statue",
	"Chicken Statue",
	"🐔",
	"Statue",
	{ 1, 1 },
	4,
	800,
	"Statue",
	{ Shape = "Chicken" },
	{ Paint = true, Materials = STONES, Scale = { 0.7, 2 } }
)
decor(
	"cow_statue",
	"Cow Statue",
	"🐄",
	"Statue",
	{ 2, 1 },
	5,
	1400,
	"Statue",
	{ Shape = "Cow" },
	{ Paint = true, Materials = STONES, Scale = { 0.7, 2 } }
)
decor(
	"angel_statue",
	"Garden Angel",
	"👼",
	"Statue",
	{ 1, 1 },
	7,
	2600,
	"Statue",
	{ Shape = "Angel" },
	{ Paint = true, Materials = STONES, Scale = { 0.8, 2 } }
)
decor(
	"stone_lion",
	"Stone Lion",
	"🦁",
	"Statue",
	{ 1, 1 },
	4,
	1800,
	"Statue",
	{ Shape = "Lion" },
	{ Paint = true, Materials = STONES, Theme = "Zen" }
)
decor(
	"moon_bench",
	"Moon Bench",
	"🌙",
	"Statue",
	{ 2, 1 },
	4,
	6000,
	"Bench",
	{ Moon = true },
	{ Theme = "Celestial", Level = 12, Rarity = "Rare" }
)

-- Seasonal (sold only during their season, kept forever)
decor("snowman", "Snowman", "⛄", "Seasonal", { 1, 1 }, 5, 300, "Snowman", {}, { Seasonal = "Winter" })
decor(
	"winter_pine",
	"Festive Pine",
	"🎄",
	"Seasonal",
	{ 2, 2 },
	14,
	2400,
	"WinterPine",
	{},
	{ Seasonal = "Winter", Paint = true }
)
decor("pumpkin_pile", "Pumpkin Pile", "🎃", "Seasonal", { 1, 1 }, 3, 400, "PumpkinPile", {}, { Seasonal = "Autumn" })
decor(
	"scarecrow_fancy",
	"Harvest Scarecrow",
	"🧑‍🌾",
	"Seasonal",
	{ 1, 1 },
	7,
	900,
	"Scarecrow",
	{ Fancy = true },
	{ Seasonal = "Autumn", Tags = { "PestGuard" }, Radius = 6, OnSoil = true }
)
decor(
	"spring_arch",
	"Blossom Arch",
	"🌸",
	"Seasonal",
	{ 2, 1 },
	8,
	1800,
	"Arch",
	{ Flowers = true, Blossom = true },
	{ Seasonal = "Spring", Walkable = true }
)
decor("egg_basket", "Egg Basket", "🧺", "Seasonal", { 1, 1 }, 2, 350, "EggBasket", {}, { Seasonal = "Spring" })
decor(
	"beach_umbrella",
	"Beach Umbrella",
	"🏖️",
	"Seasonal",
	{ 1, 1 },
	6,
	450,
	"Parasol",
	{ Stripes = true },
	{ Seasonal = "Summer", Paint = true }
)
decor(
	"lantern_garland",
	"Lantern Garland",
	"🏮",
	"Seasonal",
	{ 3, 1 },
	6,
	800,
	"StringLights",
	{ Lanterns = true },
	{ Seasonal = "Winter", Paint = true }
)

-- Festival & contest rewards (not sold; granted by events/achievements)
decor(
	"golden_pumpkin_statue",
	"Golden Pumpkin Trophy",
	"🏆",
	"Trophy",
	{ 1, 1 },
	4,
	nil,
	"Statue",
	{ Shape = "Pumpkin", Gold = true },
	{ Rarity = "Legendary" }
)
decor(
	"fishing_trophy",
	"Angler's Trophy",
	"🏆",
	"Trophy",
	{ 1, 1 },
	4,
	nil,
	"Statue",
	{ Shape = "Fish", Gold = true },
	{ Rarity = "Epic" }
)
decor(
	"blue_ribbon_plaque",
	"Blue Ribbon Plaque",
	"🎖️",
	"Trophy",
	{ 1, 1 },
	4,
	nil,
	"Plaque",
	{},
	{ Rarity = "Rare" }
)
decor(
	"champion_statue",
	"Champion Farmer Statue",
	"🗽",
	"Trophy",
	{ 2, 2 },
	10,
	nil,
	"Statue",
	{ Shape = "Farmer", Gold = true },
	{ Rarity = "Legendary" }
)
decor(
	"lantern_of_winter",
	"Lantern of Winter",
	"🏮",
	"Trophy",
	{ 1, 1 },
	6,
	nil,
	"Lamp",
	{ Style = "Winter" },
	{ Rarity = "Epic" }
)

-- Fill in machine names/icons from Config/Machines.
local Machines = require(script.Parent.Machines)
local machineById = {}
for _, machine in Machines.List do
	machineById[machine.Id] = machine
end
for _, def in List do
	if def.Category == "Machine" then
		local machine = machineById[def.Id]
		if machine then
			def.Name = machine.Name
			def.Icon = machine.Icon
			def.Description = machine.Description
		end
	end
end

return {
	List = List,
	Categories = {
		{ Id = "Building", Name = "Buildings", Icon = "🏡" },
		{ Id = "Machine", Name = "Machines", Icon = "⚙️" },
		{ Id = "Automation", Name = "Automation", Icon = "🤖" },
		{ Id = "Storage", Name = "Storage", Icon = "🧰" },
		{ Id = "Utility", Name = "Utility", Icon = "🪣" },
		{ Id = "Fence", Name = "Fences", Icon = "🚧" },
		{ Id = "Path", Name = "Paths", Icon = "🟫" },
		{ Id = "Lighting", Name = "Lighting", Icon = "🏮" },
		{ Id = "Nature", Name = "Nature", Icon = "🌳" },
		{ Id = "Water", Name = "Water", Icon = "⛲" },
		{ Id = "Furniture", Name = "Furniture", Icon = "🪑" },
		{ Id = "Structure", Name = "Structures", Icon = "⛩️" },
		{ Id = "Statue", Name = "Statues", Icon = "🗿" },
		{ Id = "Decor", Name = "Signs", Icon = "🪧" },
		{ Id = "Seasonal", Name = "Seasonal", Icon = "🎄" },
		{ Id = "Trophy", Name = "Trophies", Icon = "🏆" },
	},
	Themes = { "Rustic", "Cottage", "Zen", "Fairy", "Industrial", "Celestial" },
	Palette = {
		Color3.fromRGB(245, 240, 230),
		Color3.fromRGB(200, 60, 50),
		Color3.fromRGB(230, 130, 50),
		Color3.fromRGB(245, 205, 70),
		Color3.fromRGB(120, 180, 80),
		Color3.fromRGB(50, 120, 70),
		Color3.fromRGB(70, 160, 200),
		Color3.fromRGB(50, 80, 160),
		Color3.fromRGB(140, 90, 190),
		Color3.fromRGB(230, 120, 170),
		Color3.fromRGB(140, 95, 60),
		Color3.fromRGB(90, 60, 40),
		Color3.fromRGB(160, 160, 160),
		Color3.fromRGB(60, 60, 64),
		Color3.fromRGB(20, 20, 22),
		Color3.fromRGB(255, 255, 255),
	},
	-- Placed-object cap per farm (keeps servers fast); raised by Estate level.
	BaseCap = 350,
	CapPerLevel = 30,
	MaxCap = 1500,
	-- Sell-back refund when removing a purchased placeable.
	Refund = 1,
	GridSnap = { 0.5, 1, 2, 4 }, -- stud options for free placement
	LayoutSlots = 3, -- saved decoration layouts per farm
}

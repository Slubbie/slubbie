-- Skills and skill trees.
--
-- Each discipline levels 1-50 from its own XP. Every level gives a small passive
-- bonus (Passive) and one skill point. Points buy ranks in that discipline's
-- tree. Each tier offers two branches and you may only invest in ONE branch
-- per tier, so specialisations differ between players. Respec refunds every
-- point for a steep, escalating coin cost.
--
-- Effect keys are read by the services (see Lib/Stats.Effect):
--   GrowthSpeed, QualityScore, MutationChance, YieldChance, FertilizerSave,
--   Automation, MaxMutations, PremiumChance, FarmingEnergy, SeedSave, ...

export type Node = {
	Id: string,
	Name: string,
	Icon: string,
	Description: string, -- %s is replaced with the per-rank value summary
	Tier: number,
	Branch: string?, -- "A" | "B" (nil for capstone)
	MaxRank: number,
	Cost: number, -- points per rank
	Effects: { [string]: number }, -- per rank
}

export type Skill = {
	Id: string,
	Name: string,
	Icon: string,
	Color: Color3,
	Description: string,
	Passive: { Key: string, PerLevel: number, Text: string },
	Titles: { [number]: string },
	Tree: { Node },
}

local function node(id, name, icon, tier, branch, maxRank, cost, effects, description): Node
	return {
		Id = id,
		Name = name,
		Icon = icon,
		Tier = tier,
		Branch = branch,
		MaxRank = maxRank,
		Cost = cost,
		Effects = effects,
		Description = description,
	}
end

local List: { Skill } = {
	{
		Id = "Farming",
		Name = "Farming",
		Icon = "🌾",
		Color = Color3.fromRGB(126, 196, 90),
		Description = "Tilling, planting, watering and harvesting.",
		Passive = { Key = "GrowthSpeed", PerLevel = 0.003, Text = "+0.3% crop growth speed per level" },
		Titles = { [10] = "Green Thumb", [25] = "Master Grower", [50] = "Legend of the Fields" },
		Tree = {
			node(
				"green_thumb",
				"Green Thumb",
				"🌱",
				1,
				"A",
				3,
				1,
				{ GrowthSpeed = 0.04 },
				"Crops grow +4% faster per rank."
			),
			node(
				"careful_hands",
				"Careful Hands",
				"🤲",
				1,
				"B",
				3,
				1,
				{ QualityScore = 0.02 },
				"+2 quality score per rank on every harvest."
			),
			node(
				"mutation_whisperer",
				"Mutation Whisperer",
				"🧬",
				2,
				"A",
				3,
				2,
				{ MutationChance = 0.15 },
				"Mutations are 15% more likely per rank."
			),
			node(
				"bountiful",
				"Bountiful Harvest",
				"🧺",
				2,
				"B",
				3,
				2,
				{ YieldChance = 0.06 },
				"+6% chance per rank of an extra item per harvest."
			),
			node(
				"frugal_fertilizer",
				"Frugal Fertilizer",
				"🧂",
				3,
				"A",
				2,
				3,
				{ FertilizerSave = 0.2 },
				"20% chance per rank that fertilizer isn't used up."
			),
			node(
				"automation_engineer",
				"Automation Engineer",
				"🤖",
				3,
				"B",
				2,
				3,
				{ Automation = 0.15 },
				"Sprinklers, drones and farmbots work 15% faster/further per rank."
			),
			node(
				"master_of_fields",
				"Master of the Fields",
				"👑",
				4,
				nil,
				1,
				5,
				{ MaxMutations = 1, PremiumChance = 0.05 },
				"Crops can hold one more mutation, and premium harvests are 5% more likely."
			),
		},
	},
	{
		Id = "Ranching",
		Name = "Ranching",
		Icon = "🐄",
		Color = Color3.fromRGB(230, 170, 110),
		Description = "Caring for, breeding and collecting from animals.",
		Passive = { Key = "AnimalQuality", PerLevel = 0.004, Text = "+0.4 product quality score per level" },
		Titles = { [10] = "Herder", [25] = "Rancher", [50] = "Beast Whisperer" },
		Tree = {
			node(
				"animal_whisperer",
				"Animal Whisperer",
				"💞",
				1,
				"A",
				3,
				1,
				{ FriendshipGain = 0.1 },
				"Animals gain friendship 10% faster per rank."
			),
			node(
				"efficient_feeding",
				"Efficient Feeding",
				"🥣",
				1,
				"B",
				3,
				1,
				{ FeedSave = 0.15 },
				"15% chance per rank that feeding costs nothing."
			),
			node(
				"prize_breeder",
				"Prize Breeder",
				"🧬",
				2,
				"A",
				2,
				2,
				{ BreedMutation = 0.5 },
				"Rare alleles appear in offspring 50% more often per rank."
			),
			node(
				"productive_herd",
				"Productive Herd",
				"⏱️",
				2,
				"B",
				3,
				2,
				{ ProductSpeed = 0.06 },
				"Animals produce 6% faster per rank."
			),
			node(
				"artisan_rancher",
				"Artisan Rancher",
				"🧀",
				3,
				"A",
				2,
				3,
				{ AnimalValue = 0.1 },
				"Animal products and dairy sell for 10% more per rank."
			),
			node(
				"golden_touch",
				"Golden Touch",
				"✨",
				3,
				"B",
				2,
				3,
				{ BonusProduct = 0.08 },
				"8% chance per rank for a bonus product."
			),
			node(
				"beloved",
				"Beloved",
				"🏅",
				4,
				nil,
				1,
				5,
				{ WeatherImmune = 1 },
				"Your animals never lose happiness to bad weather."
			),
		},
	},
	{
		Id = "Fishing",
		Name = "Fishing",
		Icon = "🎣",
		Color = Color3.fromRGB(90, 170, 230),
		Description = "Catching fish, treasure and legends.",
		Passive = { Key = "FishZone", PerLevel = 0.004, Text = "+0.4% catch zone size per level" },
		Titles = { [10] = "Angler", [25] = "Master Angler", [50] = "Tide Legend" },
		Tree = {
			node("steady_hands", "Steady Hands", "✋", 1, "A", 3, 1, { FishZone = 0.05 }, "Catch zone +5% per rank."),
			node("quick_reel", "Quick Reel", "🌀", 1, "B", 3, 1, { FishFill = 0.08 }, "Reel in 8% faster per rank."),
			node(
				"treasure_hunter",
				"Treasure Hunter",
				"🧰",
				2,
				"A",
				2,
				2,
				{ TreasureChance = 0.25 },
				"Treasure 25% more often per rank."
			),
			node(
				"bait_master",
				"Bait Master",
				"🪱",
				2,
				"B",
				3,
				2,
				{ BaitSave = 0.2 },
				"20% chance per rank bait isn't used."
			),
			node(
				"legend_seeker",
				"Legend Seeker",
				"🐉",
				3,
				"A",
				2,
				3,
				{ LegendWeight = 0.4 },
				"Legendary fish bite 40% more often per rank."
			),
			node(
				"fishmonger",
				"Fishmonger",
				"🐟",
				3,
				"B",
				2,
				3,
				{ FishValue = 0.08 },
				"Fish sell for 8% more per rank."
			),
			node(
				"anglers_soul",
				"Angler's Soul",
				"🌊",
				4,
				nil,
				1,
				5,
				{ PerfectQuality = 1 },
				"Perfect catches gain a quality tier."
			),
		},
	},
	{
		Id = "Mining",
		Name = "Mining",
		Icon = "⛏️",
		Color = Color3.fromRGB(170, 160, 150),
		Description = "Rocks, ore, gems and geodes.",
		Passive = { Key = "OreChance", PerLevel = 0.01, Text = "+1% chance of an extra ore per level" },
		Titles = { [10] = "Prospector", [25] = "Deep Delver", [50] = "Heart of the Mountain" },
		Tree = {
			node(
				"prospector",
				"Prospector",
				"🪨",
				1,
				"A",
				3,
				1,
				{ OreChance = 0.1 },
				"+10% chance per rank of an extra ore."
			),
			node(
				"stonebreaker",
				"Stonebreaker",
				"💥",
				1,
				"B",
				3,
				1,
				{ MineDamage = 0.15 },
				"Pickaxe hits 15% harder per rank."
			),
			node(
				"gem_finder",
				"Gem Finder",
				"💎",
				2,
				"A",
				3,
				2,
				{ GemChance = 0.2 },
				"Gems 20% more often per rank."
			),
			node(
				"geologist",
				"Geologist",
				"🔮",
				2,
				"B",
				3,
				2,
				{ GeodeChance = 0.25 },
				"Geodes 25% more often per rank."
			),
			node(
				"smelter",
				"Smelter",
				"🔥",
				3,
				"A",
				2,
				3,
				{ SmeltSpeed = 0.2 },
				"Furnaces work 20% faster per rank."
			),
			node(
				"excavator",
				"Excavator",
				"🦾",
				3,
				"B",
				2,
				3,
				{ MiningEnergy = 0.15 },
				"Mining costs 15% less energy per rank."
			),
			node(
				"mountain_heart",
				"Heart of the Mountain",
				"🏔️",
				4,
				nil,
				1,
				5,
				{ Starsteel = 1 },
				"Starsteel can appear in any mine vein."
			),
		},
	},
	{
		Id = "Foraging",
		Name = "Foraging",
		Icon = "🍄",
		Color = Color3.fromRGB(120, 180, 120),
		Description = "Wild plants, trees and bugs.",
		Passive = { Key = "ForageDouble", PerLevel = 0.005, Text = "+0.5% chance to double forage per level" },
		Titles = { [10] = "Gatherer", [25] = "Woodland Sage", [50] = "Spirit of the Wild" },
		Tree = {
			node(
				"gatherer",
				"Gatherer",
				"🧺",
				1,
				"A",
				3,
				1,
				{ ForageDouble = 0.1 },
				"+10% double forage chance per rank."
			),
			node("lumberjack", "Lumberjack", "🪓", 1, "B", 3, 1, { WoodBonus = 0.2 }, "+20% wood per rank."),
			node(
				"botanist",
				"Botanist",
				"🌺",
				2,
				"A",
				3,
				2,
				{ ForageQuality = 0.15 },
				"15% chance per rank that forage is a tier better."
			),
			node(
				"bug_whisperer",
				"Bug Whisperer",
				"🦋",
				2,
				"B",
				3,
				2,
				{ NetRadius = 0.15 },
				"Net swings reach 15% further per rank."
			),
			node("tapper", "Tapper", "🍁", 3, "A", 2, 3, { SapBonus = 0.25 }, "+25% sap per rank."),
			node(
				"wild_seeds",
				"Wild Seeds",
				"🌰",
				3,
				"B",
				2,
				3,
				{ ForageSeeds = 0.15 },
				"15% chance per rank that forage also gives a seed."
			),
			node(
				"natures_blessing",
				"Nature's Blessing",
				"🌿",
				4,
				nil,
				1,
				5,
				{ RareForage = 1 },
				"Rare forage appears twice as often."
			),
		},
	},
	{
		Id = "Crafting",
		Name = "Crafting",
		Icon = "🛠️",
		Color = Color3.fromRGB(200, 150, 90),
		Description = "Crafting, machines and production chains.",
		Passive = { Key = "MachineSpeed", PerLevel = 0.004, Text = "+0.4% machine speed per level" },
		Titles = { [10] = "Tinkerer", [25] = "Artisan", [50] = "Grand Artisan" },
		Tree = {
			node(
				"tinkerer",
				"Tinkerer",
				"🔧",
				1,
				"A",
				3,
				1,
				{ MachineSpeed = 0.05 },
				"Machines run 5% faster per rank."
			),
			node(
				"resourceful",
				"Resourceful",
				"♻️",
				1,
				"B",
				3,
				1,
				{ CraftSave = 0.1 },
				"10% chance per rank a craft refunds one input."
			),
			node(
				"mass_production",
				"Mass Production",
				"🏭",
				2,
				"A",
				2,
				2,
				{ MachineQueue = 1 },
				"+1 machine queue slot per rank."
			),
			node(
				"fine_artisan",
				"Fine Artisan",
				"🎨",
				2,
				"B",
				3,
				2,
				{ QualityUp = 0.08 },
				"8% chance per rank that artisan output gains a tier."
			),
			node(
				"efficient_designs",
				"Efficient Designs",
				"📐",
				3,
				"A",
				2,
				3,
				{ CraftCost = 0.1 },
				"Placeables cost 10% less to buy per rank."
			),
			node(
				"master_artisan",
				"Master Artisan",
				"🍷",
				3,
				"B",
				2,
				3,
				{ ArtisanValue = 0.08 },
				"Artisan goods sell for 8% more per rank."
			),
			node(
				"grand_artisan",
				"Grand Artisan",
				"🏆",
				4,
				nil,
				1,
				5,
				{ MachineBonus = 0.1 },
				"Machines output an extra item 10% of the time."
			),
		},
	},
	{
		Id = "Cooking",
		Name = "Cooking",
		Icon = "🍳",
		Color = Color3.fromRGB(240, 130, 110),
		Description = "Meals, buffs and restaurant orders.",
		Passive = { Key = "BuffDuration", PerLevel = 0.01, Text = "+1% buff duration per level" },
		Titles = { [10] = "Home Cook", [25] = "Chef", [50] = "Legendary Chef" },
		Tree = {
			node(
				"hearty_meals",
				"Hearty Meals",
				"🍲",
				1,
				"A",
				3,
				1,
				{ EnergyRestore = 0.15 },
				"Food restores 15% more energy per rank."
			),
			node(
				"lingering_flavor",
				"Lingering Flavor",
				"⏳",
				1,
				"B",
				3,
				1,
				{ BuffDuration = 0.2 },
				"Buffs last 20% longer per rank."
			),
			node(
				"chefs_kiss",
				"Chef's Kiss",
				"💋",
				2,
				"A",
				3,
				2,
				{ DishValue = 0.12 },
				"Dishes sell for 12% more per rank."
			),
			node(
				"double_batch",
				"Double Batch",
				"🥘",
				2,
				"B",
				3,
				2,
				{ ExtraDish = 0.1 },
				"10% chance per rank to cook an extra dish."
			),
			node(
				"gourmet",
				"Gourmet",
				"🌟",
				3,
				"A",
				2,
				3,
				{ BuffStrength = 0.05 },
				"Buff effects +5% stronger per rank."
			),
			node(
				"restaurateur",
				"Restaurateur",
				"🧑‍🍳",
				3,
				"B",
				2,
				3,
				{ OrderPay = 0.15 },
				"Restaurant orders pay 15% more per rank."
			),
			node(
				"legendary_chef",
				"Legendary Chef",
				"👨‍🍳",
				4,
				nil,
				1,
				5,
				{ MinDishQuality = 3 },
				"Every dish you cook is at least Superior."
			),
		},
	},
	{
		Id = "Trading",
		Name = "Trading",
		Icon = "💰",
		Color = Color3.fromRGB(240, 200, 90),
		Description = "Selling, contracts, exports and market savvy.",
		Passive = { Key = "SellBonus", PerLevel = 0.002, Text = "+0.2% sell prices per level" },
		Titles = { [10] = "Merchant", [25] = "Market Maven", [50] = "Tycoon" },
		Tree = {
			node(
				"haggler",
				"Haggler",
				"🗣️",
				1,
				"A",
				3,
				1,
				{ ShopDiscount = 0.03 },
				"Shop prices 3% lower per rank."
			),
			node("salesperson", "Salesperson", "🤝", 1, "B", 3, 1, { SellBonus = 0.02 }, "Sell prices +2% per rank."),
			node(
				"market_savvy",
				"Market Savvy",
				"📈",
				2,
				"A",
				2,
				2,
				{ ContractBonus = 0.1, MarketInsight = 1 },
				"Contracts pay 10% more per rank and you see price forecasts."
			),
			node(
				"bulk_dealer",
				"Bulk Dealer",
				"📦",
				2,
				"B",
				3,
				2,
				{ BulkBonus = 0.05 },
				"Selling 25+ of an item at once pays 5% more per rank."
			),
			node("exporter", "Exporter", "🚢", 3, "A", 2, 3, { ExportBonus = 0.08 }, "Exports pay 8% more per rank."),
			node(
				"stall_keeper",
				"Stall Keeper",
				"🏪",
				3,
				"B",
				2,
				3,
				{ StallFee = 0.5 },
				"Your market stall fee is halved per rank."
			),
			node("tycoon", "Tycoon", "🎩", 4, nil, 1, 5, { SellBonus = 0.05 }, "+5% on every sale."),
		},
	},
	{
		Id = "Exploration",
		Name = "Exploration",
		Icon = "🧭",
		Color = Color3.fromRGB(150, 140, 220),
		Description = "Travel, discovery, digging and secrets.",
		Passive = { Key = "WalkSpeed", PerLevel = 0.003, Text = "+0.3% walk speed per level" },
		Titles = { [10] = "Wanderer", [25] = "Pathfinder", [50] = "Wayfinder" },
		Tree = {
			node("trailblazer", "Trailblazer", "👟", 1, "A", 3, 1, { WalkSpeed = 0.03 }, "+3% walk speed per rank."),
			node("stamina", "Stamina", "💪", 1, "B", 3, 1, { MaxEnergy = 10 }, "+10 max energy per rank."),
			node(
				"cartographer",
				"Cartographer",
				"🗺️",
				2,
				"A",
				1,
				2,
				{ FreeTravel = 1, SecretHints = 1 },
				"Fast travel is free and secrets show hints on your map."
			),
			node(
				"archaeologist",
				"Archaeologist",
				"🏺",
				2,
				"B",
				3,
				2,
				{ ArtifactChance = 0.2 },
				"Artifacts 20% more often per rank."
			),
			node(
				"survivalist",
				"Survivalist",
				"🔥",
				3,
				"A",
				2,
				3,
				{ HazardResist = 0.25 },
				"Hazards affect you 25% less per rank."
			),
			node(
				"treasure_sense",
				"Treasure Sense",
				"✨",
				3,
				"B",
				2,
				3,
				{ DigSpots = 1 },
				"+1 dig spot per region per rank."
			),
			node(
				"wayfinder",
				"Wayfinder",
				"🌠",
				4,
				nil,
				1,
				5,
				{ TravelAnywhere = 1 },
				"Fast travel from anywhere, not just signposts."
			),
		},
	},
}

return {
	List = List,
	MaxLevel = 50,
	-- Tier N unlocks at this skill level.
	TierLevels = { 5, 15, 30, 45 },
	-- XP needed to go from level L to L+1.
	XPForNext = function(level: number): number
		return math.floor(60 * level ^ 1.45)
	end,
	-- Respec cost = Base × skill level × Growth^(previous respecs of that skill).
	Respec = { Base = 1500, Growth = 1.8, Max = 5000000 },
	-- Base energy and energy per total skill level.
	Energy = { Base = 120, PerTotalLevels = 0.5, RegenPerSecond = 0.35, Max = 400 },
	-- Estate level = total skill levels / this.
	EstateDivisor = 3,
}

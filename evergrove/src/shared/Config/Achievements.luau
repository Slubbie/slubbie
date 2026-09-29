-- Achievements, badges, titles and cosmetic rewards.
--
-- Stat achievements unlock when Stats[Stat] >= Goal (see Lib/Stats names).
-- Special ones are granted directly by services (Special = true).
-- Rewards: Coins, Title, Banner, Frame, Effect (cosmetic aura), Items, BadgeId (Roblox badge, 0 = none).

export type Achievement = {
	Id: string,
	Name: string,
	Icon: string,
	Description: string,
	Stat: string?,
	Goal: number?,
	Special: boolean?,
	Tier: string, -- Bronze · Silver · Gold · Platinum
	Reward: { [string]: any },
	Hidden: boolean?,
	BadgeId: number?,
}

local List: { Achievement } = {}

local function a(id, name, icon, description, stat, goal, tier, reward, extra)
	local def = { Id = id, Name = name, Icon = icon, Description = description, Stat = stat, Goal = goal, Tier = tier, Reward = reward or {} }
	for k, v in extra or {} do
		def[k] = v
	end
	table.insert(List, def)
end

local function ladder(prefix, name, icon, stat, goals, noun, rewards)
	local tiers = { "Bronze", "Silver", "Gold", "Platinum" }
	local numerals = { "I", "II", "III", "IV" }
	for i, goal in goals do
		local reward = if rewards then rewards[i] else { Coins = math.min(goal * 10, 250000) }
		a(prefix .. i, name .. " " .. numerals[i], icon, string.format("%s %s.", noun, tostring(goal)), stat, goal, tiers[i], reward)
	end
end

-- Farming
ladder("harvest_", "Harvester", "🧺", "CropsHarvested", { 100, 1000, 10000, 100000 }, "Harvest crops:", { { Coins = 500 }, { Coins = 5000, Title = "Harvester" }, { Coins = 30000, Banner = "golden_fields" }, { Coins = 200000, Title = "Harvest Legend", Effect = "wheat_aura" } })
ladder("plant_", "Sower", "🌱", "CropsPlanted", { 100, 1000, 10000, 50000 }, "Plant seeds:")
ladder("water_", "Rainmaker", "💧", "TilesWatered", { 500, 5000, 50000, 250000 }, "Water tiles:")
ladder("mutant_", "Mutation Hunter", "🧬", "MutationsHarvested", { 10, 100, 1000, 5000 }, "Harvest mutated crops:", { { Coins = 1000 }, { Coins = 10000, Title = "Mutation Hunter" }, { Coins = 50000, Frame = "helix" }, { Coins = 250000, Title = "Gene Wizard", Effect = "dna_aura" } })
a("first_mutation", "Something's Different", "✨", "Harvest your first mutated crop.", "MutationsHarvested", 1, "Bronze", { Coins = 300 })
a("first_combo", "Legendary Specimen", "🌟", "Harvest a crop with a legendary combo mutation.", "CombosHarvested", 1, "Gold", { Coins = 25000, Title = "Specimen Collector", Frame = "prism" })
a("radiant", "Radiant", "✦", "Harvest a Radiant quality crop.", "RadiantHarvested", 1, "Gold", { Coins = 15000, Title = "Perfectionist" })
a("perfect_10", "Flawless", "💯", "Harvest 10 Perfect crops.", "PerfectHarvested", 10, "Gold", { Coins = 20000 })
a("giant_crop", "It's Huge!", "🏔️", "Grow a crop over 100 kg.", "LargestCropKg", 100, "Silver", { Coins = 5000 })
a("giant_crop_500", "Colossus", "🗻", "Grow a crop over 500 kg.", "LargestCropKg", 500, "Platinum", { Coins = 100000, Title = "Colossus Grower" })
a("all_seasons", "Four Seasons", "🍂", "Harvest crops in every season.", "SeasonsHarvested", 4, "Silver", { Coins = 5000 })
a("hybrid", "Mad Scientist", "🧪", "Breed a hybrid seed.", "HybridsMade", 1, "Silver", { Coins = 8000, Title = "Mad Scientist" })
a("mythic_crop", "Myth Made Real", "🌈", "Harvest a Mythic crop.", "MythicHarvested", 1, "Platinum", { Coins = 100000, Title = "Mythmaker", Effect = "rainbow_aura" })

-- Land & building
ladder("parcels_", "Landowner", "🗺️", "ParcelsOwned", { 3, 8, 15, 25 }, "Own parcels:", { { Coins = 1000 }, { Coins = 10000 }, { Coins = 60000, Title = "Land Baron" }, { Coins = 300000, Title = "Master of the Valley", Banner = "estate" } })
ladder("decor_", "Decorator", "🌷", "DecorPlaced", { 25, 150, 500, 1200 }, "Place decorations:", { { Coins = 500 }, { Coins = 5000, Title = "Decorator" }, { Coins = 25000, Frame = "floral" }, { Coins = 100000, Title = "Master Designer" } })
a("house_5", "Lord of the Manor", "🏰", "Upgrade your house to an Estate.", "HouseLevel", 5, "Platinum", { Coins = 50000, Title = "Estate Owner" })
a("automated", "Hands Free", "🤖", "Own a logistics hub, a drone hub and 20 sprinklers.", nil, nil, "Gold", { Coins = 30000, Title = "Automator" }, { Special = true })
ladder("visitors_", "Popular Farm", "🚶", "FarmVisitors", { 5, 25, 100, 500 }, "Receive farm visitors:")

-- Animals
ladder("animals_", "Rancher", "🐑", "AnimalsOwnedTotal", { 1, 10, 40, 100 }, "Raise animals:")
ladder("products_", "Fresh from the Farm", "🥚", "AnimalProducts", { 50, 500, 5000, 25000 }, "Collect animal products:")
ladder("breed_", "Breeder", "🐣", "AnimalsBred", { 1, 10, 50, 200 }, "Breed animals:")
a("rare_coat", "Rare Beauty", "🌟", "Own an animal with a Legendary or Mythic coat.", nil, nil, "Gold", { Coins = 20000, Title = "Rare Breeder" }, { Special = true })
a("best_friends", "Best Friends", "💞", "Max out friendship with an animal.", "MaxFriendAnimals", 1, "Silver", { Coins = 5000 })

-- Fishing
ladder("fish_", "Angler", "🎣", "FishCaught", { 25, 250, 2000, 10000 }, "Catch fish:", { { Coins = 500 }, { Coins = 5000, Title = "Angler" }, { Coins = 30000, Frame = "waves" }, { Coins = 150000, Title = "Master Angler" } })
ladder("legend_", "Legend Seeker", "🐉", "LegendaryFish", { 1, 3, 6, 11 }, "Catch legendary fish:", { { Coins = 10000 }, { Coins = 30000 }, { Coins = 80000, Title = "Legend Seeker" }, { Coins = 250000, Title = "Tide Legend", Effect = "water_aura" } })
a("perfect_catch", "Perfect Catch", "🎯", "Land 25 perfect catches.", "PerfectCatches", 25, "Silver", { Coins = 5000 })
a("treasure_10", "Sunken Riches", "🧰", "Fish up 10 treasure chests.", "TreasuresFished", 10, "Silver", { Coins = 5000 })

-- Gathering
ladder("mine_", "Miner", "⛏️", "RocksMined", { 100, 1000, 8000, 40000 }, "Break rocks:")
ladder("chop_", "Lumberjack", "🪓", "TreesChopped", { 50, 500, 4000, 20000 }, "Chop trees:")
ladder("forage_", "Forager", "🍄", "ForageCollected", { 50, 500, 4000, 20000 }, "Forage items:")
ladder("bugs_", "Entomologist", "🦋", "BugsCaught", { 10, 100, 1000, 5000 }, "Catch bugs:")
ladder("dig_", "Archaeologist", "🏺", "SpotsDug", { 10, 100, 800, 4000 }, "Dig up dig spots:")
a("gem_diamond", "Diamond in the Rough", "💎", "Find a diamond.", "DiamondsFound", 1, "Silver", { Coins = 5000 })
a("prismatic", "All the Colours", "🌈", "Find a Prismatic Gem.", "PrismaticFound", 1, "Platinum", { Coins = 50000, Title = "Prism Seeker" })

-- Crafting & cooking
ladder("craft_", "Crafter", "🛠️", "ItemsCrafted", { 25, 250, 2000, 10000 }, "Craft items:")
ladder("artisan_", "Artisan", "🍷", "ArtisanMade", { 50, 500, 5000, 25000 }, "Make artisan goods:", { { Coins = 1000 }, { Coins = 10000, Title = "Artisan" }, { Coins = 50000, Frame = "vineyard" }, { Coins = 250000, Title = "Grand Artisan" } })
ladder("cook_", "Cook", "🍳", "DishesCooked", { 10, 100, 1000, 5000 }, "Cook dishes:")
a("secret_recipe", "Eureka!", "💡", "Discover a secret recipe by experimenting.", "SecretRecipes", 1, "Silver", { Coins = 5000, Title = "Inventor" })

-- Economy
ladder("earn_", "Wealthy", "💰", "CoinsEarned", { 10000, 250000, 5000000, 100000000 }, "Earn coins in total:", { { Coins = 500 }, { Title = "Prosperous" }, { Title = "Tycoon", Banner = "gold" }, { Title = "Magnate of Evergrove", Effect = "coin_aura" } })
a("big_sale", "Big Sale", "💸", "Sell a single item for over 50,000 coins.", "HighestSale", 50000, "Gold", { Coins = 10000 })
ladder("contracts_", "Contractor", "📜", "ContractsDone", { 5, 50, 250, 1000 }, "Complete contracts:")
ladder("exports_", "Exporter", "🚢", "ExportsShipped", { 1, 25, 150, 600 }, "Ship exports:")
ladder("stall_", "Shopkeeper", "🏪", "StallSales", { 10, 100, 1000, 5000 }, "Sell items from your stall:")

-- Social & world
ladder("friends_", "Beloved", "💖", "NpcsAtMaxHearts", { 1, 5, 10, 18 }, "Reach 10 hearts with villagers:", { { Coins = 5000 }, { Coins = 20000, Title = "Town Favourite" }, { Coins = 80000 }, { Coins = 300000, Title = "Heart of Evergrove", Effect = "heart_aura" } })
ladder("quests_", "Helpful", "📋", "QuestsCompleted", { 10, 100, 500, 2000 }, "Complete quests:")
ladder("festivals_", "Festival Goer", "🎉", "FestivalsAttended", { 1, 8, 24, 60 }, "Attend festivals:")
ladder("contest_", "Champion", "🏆", "ContestWins", { 1, 5, 20, 50 }, "Win festival contests:", { { Coins = 5000 }, { Coins = 25000, Title = "Champion" }, { Coins = 100000, Frame = "laurel" }, { Coins = 400000, Title = "Grand Champion", Effect = "trophy_aura" } })
ladder("regions_", "Explorer", "🧭", "RegionsVisited", { 4, 8, 12, 16 }, "Visit regions:", { { Coins = 1000 }, { Coins = 8000 }, { Coins = 30000, Title = "Explorer" }, { Coins = 150000, Title = "Wayfinder" } })
ladder("secrets_", "Secret Keeper", "🔍", "SecretsFound", { 1, 5, 12, 20 }, "Find secrets:", { { Coins = 2000 }, { Coins = 15000 }, { Coins = 60000, Title = "Secret Keeper" }, { Coins = 250000, Title = "Keeper of Mysteries" } })
ladder("collection_", "Collector", "📖", "CollectionPercent", { 10, 40, 75, 100 }, "Complete the collection book (%):", { { Coins = 2000 }, { Coins = 25000, Title = "Collector" }, { Coins = 150000, Frame = "gilded" }, { Coins = 1000000, Title = "Completionist", Effect = "star_aura" } })
ladder("trade_", "Trader", "🤝", "TradesCompleted", { 1, 10, 50, 250 }, "Complete player trades:")
ladder("help_", "Good Neighbour", "🫶", "CropsWateredForOthers", { 10, 100, 1000, 5000 }, "Water crops on friends' farms:")
ladder("streak_", "Dedicated", "📅", "DailyStreakBest", { 7, 28, 100, 365 }, "Log in on consecutive days:")
a("worldtree", "Keeper of the Worldtree", "🌳", "Awaken the Worldtree.", nil, nil, "Platinum", { Coins = 100000, Effect = "leaf_aura" }, { Special = true, Hidden = true })
a("night_owl", "Night Owl", "🦉", "Catch a moonfish under a full moon.", nil, nil, "Silver", { Coins = 5000 }, { Special = true, Hidden = true })
a("all_weather", "Storm Chaser", "⛈️", "Experience every kind of weather.", "WeatherSeen", 17, "Gold", { Coins = 30000, Title = "Storm Chaser" })

return {
	List = List,
	TierColors = {
		Bronze = Color3.fromRGB(205, 127, 50),
		Silver = Color3.fromRGB(200, 205, 215),
		Gold = Color3.fromRGB(255, 205, 70),
		Platinum = Color3.fromRGB(160, 230, 255),
	},
	-- Cosmetic rewards referenced above.
	Banners = {
		golden_fields = { Name = "Golden Fields", Colors = { Color3.fromRGB(255, 214, 102), Color3.fromRGB(196, 140, 50) } },
		estate = { Name = "Grand Estate", Colors = { Color3.fromRGB(80, 130, 90), Color3.fromRGB(30, 60, 40) } },
		gold = { Name = "Solid Gold", Colors = { Color3.fromRGB(255, 220, 110), Color3.fromRGB(230, 170, 40) } },
		meadow = { Name = "Meadow", Colors = { Color3.fromRGB(170, 220, 120), Color3.fromRGB(90, 160, 80) } },
		night = { Name = "Night Sky", Colors = { Color3.fromRGB(60, 60, 130), Color3.fromRGB(20, 20, 50) } },
	},
	Frames = {
		helix = { Name = "Double Helix", Color = Color3.fromRGB(120, 220, 180) },
		floral = { Name = "Floral", Color = Color3.fromRGB(240, 150, 190) },
		waves = { Name = "Waves", Color = Color3.fromRGB(90, 170, 230) },
		vineyard = { Name = "Vineyard", Color = Color3.fromRGB(150, 70, 120) },
		laurel = { Name = "Laurel", Color = Color3.fromRGB(230, 200, 90) },
		gilded = { Name = "Gilded", Color = Color3.fromRGB(255, 205, 70) },
		prism = { Name = "Prism", Color = Color3.fromRGB(255, 160, 230) },
	},
	Effects = {
		wheat_aura = { Name = "Wheat Wisps", Color = Color3.fromRGB(240, 210, 110) },
		dna_aura = { Name = "Helix Glow", Color = Color3.fromRGB(120, 240, 190) },
		rainbow_aura = { Name = "Rainbow Aura", Color = Color3.fromRGB(255, 120, 200) },
		water_aura = { Name = "Tidal Aura", Color = Color3.fromRGB(90, 190, 255) },
		coin_aura = { Name = "Golden Shimmer", Color = Color3.fromRGB(255, 215, 80) },
		heart_aura = { Name = "Hearts", Color = Color3.fromRGB(255, 120, 150) },
		trophy_aura = { Name = "Champion's Glow", Color = Color3.fromRGB(255, 200, 60) },
		star_aura = { Name = "Starlight", Color = Color3.fromRGB(200, 190, 255) },
		leaf_aura = { Name = "Worldtree Leaves", Color = Color3.fromRGB(140, 230, 120) },
	},
}

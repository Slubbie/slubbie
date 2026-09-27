-- Economy, odds and upgrade tuning. Plain data: the server and the odds display both read this.
--
-- ROLL MODEL (see docs/DESIGN.md for worked odds)
--   1. Each equipped die lands on one of its six faces (1 in 6 each).
--   2. The LEAD die (slot 1) picks the reward tier using FaceTiers[face].
--   3. A weighted draw picks an item of that tier from the region's loot table (item Weight).
--   4. One mutation roll: Mutations.BaseChance (x die perks), then a weighted pick of an
--      allowed mutation. At most one mutation per item.
--   5. With 2-3 dice, the single highest-priority combo applies (Combos.Priority).

local Economy = {}

-- Tier weights for each lead-die face. Weights in a row are relative (each row sums to 100 here).
-- Secret items are never drawn from this table: they come only from combos.
Economy.FaceTiers = {
	[1] = { Common = 100 },
	[2] = { Common = 85, Uncommon = 15 },
	[3] = { Common = 60, Uncommon = 35, Rare = 5 },
	[4] = { Common = 40, Uncommon = 45, Rare = 13, Epic = 2 },
	[5] = { Uncommon = 55, Rare = 33, Epic = 10, Legendary = 2 },
	[6] = { Rare = 62, Epic = 30, Legendary = 7, Mythic = 1 },
}

Economy.Mutations = {
	-- Chance that a found item is mutated, before die perks. Capped at MaxChance.
	BaseChance = 0.05,
	MaxChance = 0.25,
	-- Regions = nil means the mutation can appear anywhere. Die perks (MutationWeights) also
	-- unlock a mutation outside its regions.
	List = {
		{ Id = "Shiny", Label = "Shiny", Multiplier = 2, Weight = 60, Color = { 255, 255, 200 } },
		{ Id = "Golden", Label = "Golden", Multiplier = 4, Weight = 22, Color = { 255, 200, 50 } },
		{
			Id = "Overgrown",
			Label = "Overgrown",
			Multiplier = 3,
			Weight = 18,
			Color = { 90, 200, 80 },
			Regions = { meadow = true, crystal = true },
		},
		{
			Id = "Frozen",
			Label = "Frozen",
			Multiplier = 3,
			Weight = 25,
			Color = { 160, 220, 255 },
			Regions = { frost = true },
		},
		{
			Id = "Cosmic",
			Label = "Cosmic",
			Multiplier = 8,
			Weight = 8,
			Color = { 190, 120, 255 },
			Regions = { astral = true },
		},
	},
	ById = {},
}
for _, mutation in Economy.Mutations.List do
	Economy.Mutations.ById[mutation.Id] = mutation
end

-- Dice combos (need 2-3 equipped dice). Exactly ONE combo applies per roll: the first match in
-- Priority. So three 6s is a Jackpot (not also a Triple and a Pair).
Economy.Combos = {
	Priority = { "Jackpot", "Triple", "Straight", "Pair" },
	-- Every die shows its own maximum face. Adds one extra reward drawn from JackpotTiers
	-- plus the region's JackpotCoins.
	Jackpot = { MinDice = 2, Label = "JACKPOT ROLL!", JackpotTiers = { Legendary = 80, Mythic = 18, Secret = 2 } },
	-- Three dice, same face (not max). Adds one guaranteed bonus reward using BonusFace's tier row.
	Triple = { MinDice = 3, Label = "Triple!", BonusFace = 6 },
	-- Three dice forming a run like 2-3-4. Chance to add the region's special collectible.
	Straight = { MinDice = 3, Label = "Straight!", CollectibleChance = 0.05 },
	-- At least two dice share a face. The main reward's quantity becomes MainQuantity.
	Pair = { MinDice = 2, Label = "Pair!", MainQuantity = 2 },
}

-- Upgrades. Level 0 is Levels[1] (free). Buying level n costs Levels[n + 1].Cost.
Economy.Upgrades = {
	List = {
		{
			Id = "Bag",
			Name = "Treasure Bag",
			Stage = 1,
			Icon = "🎒",
			Description = "Carry more treasure between trips to the merchant.",
			Format = "%d items",
			Levels = {
				{ Value = 20 },
				{ Value = 30, Cost = 40 },
				{ Value = 45, Cost = 220 },
				{ Value = 65, Cost = 800 },
				{ Value = 90, Cost = 2200 },
				{ Value = 120, Cost = 6000 },
				{ Value = 160, Cost = 15000 },
				{ Value = 220, Cost = 40000 },
			},
		},
		{
			Id = "Speed",
			Name = "Quick Hands",
			Stage = 1,
			Icon = "⚡",
			Description = "Shorter cooldown between rolls.",
			Format = "%.2fs cooldown",
			Levels = {
				{ Value = 2.6 },
				{ Value = 2.4, Cost = 150 },
				{ Value = 2.2, Cost = 500 },
				{ Value = 2.0, Cost = 1400 },
				{ Value = 1.85, Cost = 4000 },
				{ Value = 1.7, Cost = 11000 },
				{ Value = 1.6, Cost = 30000 },
			},
		},
		{
			Id = "Sell",
			Name = "Silver Tongue",
			Stage = 1,
			Icon = "💬",
			Description = "Merchants pay a little more for everything.",
			Format = "+%d%% sell price",
			FormatScale = 100,
			Levels = {
				{ Value = 0 },
				{ Value = 0.05, Cost = 350 },
				{ Value = 0.10, Cost = 1800 },
				{ Value = 0.15, Cost = 7000 },
				{ Value = 0.20, Cost = 25000 },
			},
		},
		{
			Id = "AutoRoll",
			Name = "Auto-Roller",
			Stage = 1,
			Icon = "🔁",
			Description = "Unlocks auto-roll. Same cooldown and bag rules as rolling by hand.",
			Format = "%s",
			Levels = {
				{ Value = 0 },
				{ Value = 1, Cost = 2000 },
			},
		},
		{
			Id = "DiceSlots",
			Name = "Dice Tray",
			Stage = 2,
			Icon = "🎲",
			Description = "Roll more dice at once to form combos.",
			Format = "%d dice",
			Levels = {
				{ Value = 1 },
				{ Value = 2, Cost = 5000 },
				{ Value = 3, Cost = 30000 },
			},
		},
	},
	ById = {},
}
for index, upgrade in Economy.Upgrades.List do
	upgrade.Order = index
	Economy.Upgrades.ById[upgrade.Id] = upgrade
end

-- Hard ceilings so bonuses can never run away, whatever gets added later.
Economy.MaxSellMultiplier = 1.5
Economy.MinRollCooldown = 1.5
Economy.MaxDice = 3

-- Coins for finishing the tutorial (skipping it gives nothing, but costs nothing either).
Economy.TutorialReward = 25

-- ── World events (Stage 3) ──────────────────────────────────────────────────────
-- Every Interval seconds the server starts one event in a random live region for Duration
-- seconds. Effects only apply to rolls (and sales) in that region while it runs.
Economy.Events = {
	FirstDelay = 90,
	Interval = 600,
	Duration = 240,
	List = {
		{
			Id = "GoldenHour",
			Name = "Golden Hour",
			Icon = "👑",
			Text = "Golden mutations are 4× as likely",
			Effects = { MutationWeights = { Golden = 4 } },
		},
		{
			Id = "LuckyWinds",
			Name = "Lucky Winds",
			Icon = "🍃",
			Text = "Mutation chance ×2",
			Effects = { MutationChanceMult = 2 },
		},
		{
			Id = "TreasureRush",
			Name = "Treasure Rush",
			Icon = "💎",
			Text = "Rare-and-better tiers are 1.5× as likely",
			Effects = { TierBoost = 1.5 },
		},
		{
			Id = "MerchantFestival",
			Name = "Merchant Festival",
			Icon = "🎪",
			Text = "+25% sell price at this region's merchant",
			Effects = { SellBonus = 0.25 },
		},
		{
			Id = "DiscoveryDay",
			Name = "Discovery Day",
			Icon = "🔭",
			Text = "Undiscovered items are 3× as likely within their tier",
			Effects = { UndiscoveredBoost = 3 },
		},
	},
	ById = {},
}
for _, event in Economy.Events.List do
	Economy.Events.ById[event.Id] = event
end

-- ── Merchant orders (Stage 3) ───────────────────────────────────────────────────
-- Merchants ask for specific treasure and pay RewardMult × its sell value, so filling an order
-- always beats selling the same items. Orders only use regions you've unlocked.
Economy.Orders = {
	Slots = 3,
	ReplaceDelay = 45, -- seconds before a completed or skipped order is replaced
	SkipCooldown = 180, -- seconds between skips
	RewardMult = { Min = 1.6, Max = 2.1 },
	MutatedChance = 0.15, -- chance an order asks for a specific mutation
	MutatedRewardBonus = 1.3,
	RarityWeights = { Common = 45, Uncommon = 35, Rare = 17, Epic = 3 },
	Quantity = { Common = { 3, 6 }, Uncommon = { 2, 4 }, Rare = { 1, 2 }, Epic = { 1, 1 } },
}

-- ── Daily objectives (Stage 3) ──────────────────────────────────────────────────
-- Three a day (UTC), optional, no streaks to lose. Rewards scale with your best unlocked region.
Economy.Dailies = {
	Count = 3,
	RegionScale = { 1, 2.5, 6, 14, 32 },
	Pool = {
		{ Id = "roll", Stat = "Rolls", Goal = 60, Reward = 150, Text = "Roll %d times" },
		{ Id = "roll_big", Stat = "Rolls", Goal = 150, Reward = 350, Text = "Roll %d times" },
		{ Id = "rare", Stat = "Rares", Goal = 8, Reward = 200, Text = "Find %d Rare-or-better items" },
		{ Id = "mutation", Stat = "Mutated", Goal = 3, Reward = 250, Text = "Find %d mutated items" },
		{
			Id = "sell",
			Stat = "SaleCoins",
			Goal = 800,
			Reward = 200,
			Text = "Earn %d coins from selling",
			Scales = true,
		},
		{ Id = "order", Stat = "Orders", Goal = 2, Reward = 300, Text = "Complete %d merchant orders" },
		{ Id = "combo", Stat = "Combos", Goal = 10, Reward = 300, Text = "Roll %d dice combos", NeedsDice = 2 },
	},
}

-- ── Milestones (Stage 3) ────────────────────────────────────────────────────────
-- Permanent, one-time rewards. Stat "Unique" = unique discoveries, "Regions" = regions unlocked.
Economy.Milestones = {
	{ Id = "rolls_100", Name = "Warm Hands", Stat = "Rolls", Goal = 100, Reward = 300 },
	{ Id = "rolls_1000", Name = "Seasoned Roller", Stat = "Rolls", Goal = 1000, Reward = 3000 },
	{ Id = "rolls_5000", Name = "Dice Devotee", Stat = "Rolls", Goal = 5000, Reward = 25000 },
	{ Id = "rolls_20000", Name = "Legend of the Tray", Stat = "Rolls", Goal = 20000, Reward = 150000 },
	{ Id = "unique_5", Name = "Curious Collector", Stat = "Unique", Goal = 5, Reward = 150 },
	{ Id = "unique_15", Name = "Keen Eye", Stat = "Unique", Goal = 15, Reward = 2000 },
	{ Id = "unique_30", Name = "Treasure Scholar", Stat = "Unique", Goal = 30, Reward = 20000 },
	{ Id = "unique_50", Name = "Completionist", Stat = "Unique", Goal = 50, Reward = 250000 },
	{ Id = "orders_5", Name = "Helpful Hand", Stat = "Orders", Goal = 5, Reward = 1000 },
	{ Id = "orders_25", Name = "Trusted Supplier", Stat = "Orders", Goal = 25, Reward = 10000 },
	{ Id = "orders_100", Name = "Merchant's Favorite", Stat = "Orders", Goal = 100, Reward = 80000 },
	{ Id = "regions_2", Name = "Wanderer", Stat = "Regions", Goal = 2, Reward = 500 },
	{ Id = "regions_3", Name = "Explorer", Stat = "Regions", Goal = 3, Reward = 5000 },
	{ Id = "regions_4", Name = "Pathfinder", Stat = "Regions", Goal = 4, Reward = 30000 },
	{ Id = "regions_5", Name = "Star Walker", Stat = "Regions", Goal = 5, Reward = 150000 },
	{ Id = "jackpot_1", Name = "Jackpot!", Stat = "Jackpots", Goal = 1, Reward = 2000 },
	{ Id = "jackpot_10", Name = "Lady Luck", Stat = "Jackpots", Goal = 10, Reward = 30000 },
	{ Id = "mutated_10", Name = "Oddity Hunter", Stat = "Mutated", Goal = 10, Reward = 1500 },
	{ Id = "mutated_100", Name = "Mutation Maven", Stat = "Mutated", Goal = 100, Reward = 25000 },
	{ Id = "crafts_1", Name = "Tinkerer's Apprentice", Stat = "Crafts", Goal = 1, Reward = 1000 },
}

-- Seconds between teleports on the travel map.
Economy.TravelCooldown = 3

return Economy

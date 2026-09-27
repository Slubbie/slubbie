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

return Economy

-- Core logic tests: odds, roll engine, bag, selling, upgrades, save schema, tutorial.

local Config = require(game:GetService("ReplicatedStorage").Dicebound.Config)
local LootMath = require(game:GetService("ReplicatedStorage").Dicebound.LootMath)
local Odds = require(game:GetService("ReplicatedStorage").Dicebound.Odds)
local Core = game:GetService("ServerScriptService").Dicebound.Core
local RollEngine = require(Core.RollEngine)
local Bag = require(Core.Bag)
local Shop = require(Core.Shop)
local Schema = require(Core.Schema)
local Tutorial = require(Core.Tutorial)

print("Config")

T.test("item ids are unique and every region has 10 items incl. one special", function()
	T.truthy(#Config.Items.List >= 30, "at least 30 items")
	for _, region in Config.Regions.List do
		local items = Config.ItemsIn(region.Id)
		T.eq(#items, 10, region.Id .. " item count")
		local specials = 0
		for _, item in items do
			T.truthy(Config.Rarities.ById[item.Rarity], item.Id .. " rarity")
			T.truthy(item.Value > 0 and item.Weight > 0, item.Id .. " value/weight")
			T.truthy(#item.Description > 0 and #item.Name > 0, item.Id .. " text")
			if item.Special then
				specials += 1
			end
		end
		T.eq(specials, 1, region.Id .. " specials")
	end
end)

T.test("every die has six faces", function()
	for _, die in Config.Dice.List do
		T.eq(#die.Faces, 6, die.Id)
		for _, faces in die.RegionFaces or {} do
			T.eq(#faces, 6, die.Id .. " regional")
		end
	end
end)

T.test("upgrade prices increase and values move the right way", function()
	for _, upgrade in Config.Economy.Upgrades.List do
		for i = 3, #upgrade.Levels do
			T.truthy(upgrade.Levels[i].Cost > upgrade.Levels[i - 1].Cost, upgrade.Id .. " cost order")
		end
	end
	T.truthy(Config.UpgradeValue("Speed", Config.UpgradeMaxLevel("Speed")) >= Config.Economy.MinRollCooldown)
end)

print("Odds")

T.test("odds sum to 1 for every region and dice setup", function()
	for _, region in Config.Regions.List do
		for _, setup in { { "wooden" }, { "wooden", "glass" }, { "clover", "frost", "celestial" } } do
			local o = Odds.Compute(region.Id, setup)
			local tiers, items = 0, 0
			for _, p in o.Tiers do
				tiers += p
			end
			for _, p in o.Items do
				items += p
			end
			T.near(tiers, 1, 1e-9, region.Id .. " tiers")
			T.near(items, 1, 1e-9, region.Id .. " items")
		end
	end
end)

T.test("base Meadow tier odds match the documented table", function()
	local o = Odds.Compute("meadow", { "wooden" })
	T.near(o.Tiers.Common, 285 / 600, 1e-9, "Common")
	T.near(o.Tiers.Uncommon, 150 / 600, 1e-9, "Uncommon")
	T.near(o.Tiers.Rare, 113 / 600, 1e-9, "Rare")
	T.near(o.Tiers.Epic, 42 / 600, 1e-9, "Epic")
	T.near(o.Tiers.Legendary, 9 / 600, 1e-9, "Legendary")
	T.near(o.Tiers.Mythic, 1 / 600, 1e-9, "Mythic")
	T.eq(o.Tiers.Secret, nil, "Secret from normal rolls")
	T.near(o.MutationChance, 0.05, 1e-9, "mutation chance")
	T.eq(o.Mutations.Frozen, nil, "no Frozen in the Meadow")
	T.eq(o.MaxRewardUnits, 1, "one die reserves one slot")
end)

T.test("combo probabilities for three standard dice", function()
	local o = Odds.Compute("meadow", { "wooden", "copper", "frost" })
	T.near(o.Combos.Jackpot, 1 / 216, 1e-9, "Jackpot")
	T.near(o.Combos.Triple, 5 / 216, 1e-9, "Triple (6-6-6 counts as Jackpot)")
	T.near(o.Combos.Straight, 24 / 216, 1e-9, "Straight")
	T.near(o.Combos.Pair, 90 / 216, 1e-9, "Pair")
end)

print("Roll engine")

T.test("simulated rolls match the computed odds", function()
	local rng = T.Rng(12345)
	local n = 200000
	local counts = {}
	local mutated = 0
	for _ = 1, n do
		local outcome = RollEngine.Roll(rng, "meadow", { "wooden" }, nil)
		T.eq(#outcome.Rewards, 1)
		local reward = outcome.Rewards[1]
		local rarity = Config.Items.ById[reward.Id].Rarity
		counts[rarity] = (counts[rarity] or 0) + 1
		if reward.Mut then
			mutated += 1
			T.truthy(reward.Mut ~= "Frozen" and reward.Mut ~= "Cosmic", "regional mutation leaked")
		end
	end
	local o = Odds.Compute("meadow", { "wooden" })
	for tier, p in o.Tiers do
		local sd = math.sqrt(p * (1 - p) / n)
		T.near((counts[tier] or 0) / n, p, 5 * sd + 1e-4, tier)
	end
	T.near(mutated / n, 0.05, 0.003, "mutation rate")
end)

T.test("combos: detection and precedence", function()
	local six = { 6, 6, 6 }
	T.eq(LootMath.DetectCombo({ 6, 6, 6 }, six), "Jackpot")
	T.eq(LootMath.DetectCombo({ 3, 3, 3 }, six), "Triple")
	T.eq(LootMath.DetectCombo({ 4, 2, 3 }, six), "Straight")
	T.eq(LootMath.DetectCombo({ 4, 1, 4 }, six), "Pair")
	T.eq(LootMath.DetectCombo({ 1, 3, 5 }, six), nil)
	T.eq(LootMath.DetectCombo({ 6, 6 }, { 6, 6 }), "Jackpot", "two dice jackpot")
	T.eq(LootMath.DetectCombo({ 5, 5 }, { 5, 6 }), "Pair", "glass + wooden 5-5")
	T.eq(LootMath.DetectCombo({ 5, 6 }, { 5, 6 }), "Jackpot", "glass max is 5")
	T.eq(LootMath.DetectCombo({ 6 }, { 6 }), nil, "single die never combos")
	T.eq(LootMath.MaxRewardUnits(1), 1)
	T.eq(LootMath.MaxRewardUnits(2), 2)
	T.eq(LootMath.MaxRewardUnits(3), 2)
end)

T.test("multi-dice rewards never exceed the reserved space", function()
	local rng = T.Rng(777)
	local seen = {}
	for _ = 1, 50000 do
		for _, setup in { { "wooden", "copper" }, { "wooden", "copper", "glass" }, { "clover", "frost", "magma" } } do
			local outcome = RollEngine.Roll(rng, "frost", setup, nil)
			T.truthy(outcome.Units <= LootMath.MaxRewardUnits(#setup), "units")
			for _, reward in outcome.Rewards do
				T.eq(Config.Items.ById[reward.Id].Region, "frost", "region loot")
			end
			if outcome.Combo then
				seen[outcome.Combo] = true
			end
		end
	end
	for _, name in { "Pair", "Triple", "Straight", "Jackpot" } do
		T.truthy(seen[name], name .. " seen")
	end
end)

print("Bag")

T.test("capacity counts items, not stacks", function()
	local data = Schema.Defaults()
	T.eq(Bag.Capacity(data), 20)
	T.truthy(Bag.Add(data, "meadow_old_coin", nil, 15))
	T.truthy(Bag.Add(data, "meadow_old_coin", "Shiny", 5))
	T.eq(Bag.Used(data), 20)
	T.eq(Bag.Free(data), 0)
	T.eq(Bag.Add(data, "meadow_acorn", nil, 1), nil, "full bag refuses")
	T.eq(Bag.Used(data), 20)
	T.truthy(Bag.Remove(data, "meadow_old_coin", 15))
	T.eq(data.Bag.meadow_old_coin, nil, "empty stack removed")
	T.eq(Bag.Remove(data, "meadow_old_coin|Shiny", 6), false, "can't remove more than owned")
end)

T.test("discoveries survive selling", function()
	local data = Schema.Defaults()
	local key = Bag.Add(data, "meadow_sunhoney", "Golden", 1) :: string
	local isNew, newMut = Bag.Discover(data, "meadow_sunhoney", "Golden", 1, 100)
	T.truthy(isNew and newMut)
	local plan = Shop.PlanSale(data, { [key] = 1 }, false)
	Shop.ApplySale(data, plan :: any)
	T.truthy(data.Discovered.meadow_sunhoney, "still discovered")
	T.eq(select(1, Bag.Discover(data, "meadow_sunhoney", nil, 1, 200)), false, "not new again")
end)

print("Selling")

T.test("locked items are never sold", function()
	local data = Schema.Defaults()
	Bag.Add(data, "meadow_old_coin", nil, 3)
	Bag.Add(data, "meadow_acorn", nil, 2)
	Bag.SetLocked(data, "meadow_acorn", true)
	local plan, err = Shop.PlanSale(data, { meadow_acorn = 1 }, true)
	T.eq(plan, nil)
	T.truthy(err and string.find(err, "Locked"))
	local all = Shop.PlanSellAll(data, true) :: any
	Shop.ApplySale(data, all)
	T.eq(data.Bag.meadow_acorn.Qty, 2, "locked stack untouched by Sell All")
	T.eq(data.Bag.meadow_old_coin, nil)
	T.eq(data.Coins, 25 + 9)
end)

T.test("selling the same items twice pays once", function()
	local data = Schema.Defaults()
	Bag.Add(data, "meadow_teacup_snail", nil, 2)
	local plan = Shop.PlanSale(data, { meadow_teacup_snail = 2 }, false) :: any
	local planAgain = Shop.PlanSale(data, { meadow_teacup_snail = 2 }, false) :: any
	T.eq(Shop.ApplySale(data, plan), 16)
	T.eq(Shop.ApplySale(data, planAgain), 0, "stale plan pays nothing")
	T.eq(select(1, Shop.PlanSale(data, { meadow_teacup_snail = 2 }, false)), nil, "second request refused")
	T.eq(data.Coins, 25 + 16)
end)

T.test("legendary+ needs confirmation; Sell All skips it unless included", function()
	local data = Schema.Defaults()
	Bag.Add(data, "meadow_dandelion_crown", nil, 1)
	Bag.Add(data, "meadow_acorn", nil, 1)
	local _, err = Shop.PlanSale(data, { meadow_dandelion_crown = 1 }, false)
	T.eq(err, "CONFIRM")
	local plan = Shop.PlanSellAll(data, false) :: any
	T.eq(#plan.Lines, 1)
	T.eq(plan.Lines[1].Id, "meadow_acorn")
	T.truthy(Shop.PlanSale(data, { meadow_dandelion_crown = 1 }, true), "confirmed sale ok")
end)

T.test("sale input validation", function()
	local data = Schema.Defaults()
	Bag.Add(data, "meadow_acorn", nil, 2)
	for _, bad in
		{
			{ meadow_acorn = 3 },
			{ meadow_acorn = 0 },
			{ meadow_acorn = 1.5 },
			{ meadow_acorn = -1 },
			{ nope = 1 },
			{},
			"x",
		}
	do
		T.eq(select(1, Shop.PlanSale(data, bad, true)), nil)
	end
end)

T.test("sell multiplier includes upgrade and die perk, capped", function()
	local data = Schema.Defaults()
	data.Upgrades.Sell = 2
	data.Dice.Owned.copper = true
	data.Dice.Equipped = { "wooden", "copper" }
	T.near(Shop.SellMultiplier(data), 1.2, 1e-9)
	Bag.Add(data, "meadow_sunhoney", nil, 3)
	local plan = Shop.PlanSale(data, { meadow_sunhoney = 3 }, false) :: any
	T.eq(plan.Total, 72)
	data.Upgrades.Sell = 4
	data.Dice.Equipped = { "copper" }
	T.near(Shop.SellMultiplier(data), 1.3, 1e-9)
end)

print("Upgrades")

T.test("buying upgrades: funds, duplicates and max level", function()
	local data = Schema.Defaults()
	data.Coins = 30
	local ok, err = Shop.BuyUpgrade(data, "Bag", 0)
	T.eq(ok, false)
	T.truthy(string.find(err :: string, "10 more"))
	data.Coins = 1000
	T.eq(Shop.BuyUpgrade(data, "Bag", 0), true)
	T.eq(data.Coins, 960)
	T.eq(Shop.BuyUpgrade(data, "Bag", 0), false, "duplicate click refused")
	T.eq(data.Coins, 960)
	T.eq(Bag.Capacity(data), 30)
	T.eq(Shop.BuyUpgrade(data, "AutoRoll", 0), false, "too expensive")
	data.Coins = 1e6
	T.eq(Shop.BuyUpgrade(data, "AutoRoll", 0), true)
	T.eq(select(2, Shop.BuyUpgrade(data, "AutoRoll", 1)), "Already at max level.")
	T.eq(Shop.BuyUpgrade(data, "Nope", 0), false)
	T.eq(Shop.BuyUpgrade(data, "DiceSlots", 0), false, "stage 2 upgrade not live yet")
	T.eq(Shop.BuyUpgrade(data, "Bag", "1"), false, "string level refused")
end)

print("Save schema")

T.test("defaults and round trip", function()
	local data = Schema.Defaults()
	Bag.Add(data, "meadow_acorn", "Shiny", 2)
	data.Bag["meadow_acorn|Shiny"].Locked = true
	data.Upgrades.Speed = 3
	data.Tutorial.Step = 3
	local loaded = Schema.Load(data) :: any
	T.eq(loaded.Bag["meadow_acorn|Shiny"].Qty, 2)
	T.eq(loaded.Bag["meadow_acorn|Shiny"].Locked, true)
	T.eq(loaded.Upgrades.Speed, 3)
	T.eq(loaded.Tutorial.Step, 3)
	T.eq(loaded.Coins, 25)
end)

T.test("garbage is sanitized and unknown items are kept aside", function()
	local loaded = Schema.Load({
		Version = 1,
		Coins = -5,
		Bag = { x = { Id = "removed_item", Qty = 4 }, y = { Id = "meadow_acorn", Qty = "lots" } },
		Upgrades = { Bag = 999, Speed = -1 },
		Dice = { Owned = { wooden = true, fake = true }, Equipped = { "fake", "wooden", "wooden" } },
		Settings = { Music = 7, ReducedMotion = "yes" },
	}) :: any
	T.eq(loaded.Coins, 25, "negative coins rejected")
	T.eq(next(loaded.Bag), nil)
	T.eq(#loaded.Orphans, 1)
	T.eq(loaded.Upgrades.Bag, Config.UpgradeMaxLevel("Bag"))
	T.eq(loaded.Upgrades.Speed, 0)
	T.eq(#loaded.Dice.Equipped, 1)
	T.eq(loaded.Settings.Music, 1)
	T.eq(loaded.Settings.ReducedMotion, false)
end)

T.test("a save from a newer version is refused, not overwritten", function()
	local data, err = Schema.Load({ Version = Schema.Version + 1, Coins = 99 })
	T.eq(data, nil)
	T.truthy(err)
	T.eq(select(1, Schema.Load("corrupt")), nil)
	T.eq((Schema.Load(nil) :: any).Coins, Config.Game.StartingCoins, "new player")
end)

print("Tutorial")

T.test("tutorial advances only in order and rewards once", function()
	local data = Schema.Defaults()
	T.eq(Tutorial.OnAction(data, "Sell"), nil)
	T.eq(data.Tutorial.Step, 1)
	Tutorial.OnAction(data, "Roll")
	Tutorial.OnAction(data, "Roll")
	T.eq(data.Tutorial.Step, 2)
	Tutorial.OnAction(data, "Sell")
	T.eq(Tutorial.OnAction(data, "Upgrade"), Config.Economy.TutorialReward)
	T.eq(data.Tutorial.Done, true)
	T.eq(Tutorial.OnAction(data, "Upgrade"), nil, "no second reward")
end)

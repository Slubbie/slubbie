-- Stage 2/3 logic: dice shop + equipping, region unlocks, orders, crafting, dailies,
-- milestones, collection rewards, world events and the v1 -> v2 save migration.

local Config = require(game:GetService("ReplicatedStorage").Dicebound.Config)
local LootMath = require(game:GetService("ReplicatedStorage").Dicebound.LootMath)
local Odds = require(game:GetService("ReplicatedStorage").Dicebound.Odds)
local Core = game:GetService("ServerScriptService").Dicebound.Core
local RollEngine = require(Core.RollEngine)
local Bag = require(Core.Bag)
local Shop = require(Core.Shop)
local Schema = require(Core.Schema)
local Orders = require(Core.Orders)
local Workshop = require(Core.Workshop)
local Progress = require(Core.Progress)

print("Dice")

T.test("buying dice: region gate, funds, no duplicates", function()
	local data = Schema.Defaults()
	data.Coins = 1e6
	T.eq(select(2, Workshop.BuyDie(data, "glass")), "Unlock Crystal Caverns first.")
	T.eq(Workshop.BuyDie(data, "copper"), true)
	T.eq(data.Coins, 1e6 - 2500)
	T.eq(Workshop.BuyDie(data, "copper"), false, "no double buy")
	T.eq(Workshop.BuyDie(data, "celestial"), false, "crafted dice can't be bought")
	T.eq(Workshop.BuyDie(data, "nope"), false)
end)

T.test("equipping validates ownership, duplicates and slots", function()
	local data = Schema.Defaults()
	data.Dice.Owned.copper = true
	T.eq(Workshop.Equip(data, { "wooden", "copper" }), false, "only one slot")
	data.Upgrades.DiceSlots = 1
	T.eq(Workshop.Equip(data, { "copper", "wooden" }), true)
	T.eq(data.Dice.Equipped[1], "copper", "lead die is slot 1")
	T.eq(Workshop.Equip(data, { "copper", "copper" }), false, "duplicate")
	T.eq(Workshop.Equip(data, { "glass" }), false, "not owned")
	T.eq(Workshop.Equip(data, {}), false, "empty")
	T.eq(Workshop.Equip(data, "wooden"), false, "wrong type")
end)

print("Regions")

T.test("unlocking needs the previous region, discoveries and coins", function()
	local data = Schema.Defaults()
	data.Coins = 1e7
	T.truthy(string.find(select(2, Workshop.UnlockRegion(data, "frost")) :: string, "Crystal Caverns first"))
	local _, err = Workshop.UnlockRegion(data, "crystal")
	T.truthy(string.find(err :: string, "Discover 6"))
	for i, item in Config.ItemsIn("meadow") do
		if i <= 6 then
			Bag.Discover(data, item.Id, nil, 1, 0)
		end
	end
	T.eq(Workshop.UnlockRegion(data, "crystal"), true)
	T.eq(data.Coins, 1e7 - 2500)
	T.eq(Workshop.UnlockRegion(data, "crystal"), false, "no double unlock")
end)

print("Orders")

T.test("orders generate from unlocked regions and pay more than selling", function()
	local rng = T.Rng(99)
	for _ = 1, 500 do
		local data = Schema.Defaults()
		local order = Orders.Generate(data, rng) :: any
		T.eq(Config.Items.ById[order.ItemId].Region, "meadow")
		T.truthy(not Config.Items.ById[order.ItemId].Special, "never a special")
		local sellValue = Config.ItemValue(order.ItemId, order.Mut) * order.Qty
		T.truthy(order.Reward >= math.floor(sellValue * Config.Economy.Orders.RewardMult.Min), "reward beats selling")
	end
end)

T.test("fulfilling uses unlocked items only, plain copies first, and pays once", function()
	local data = Schema.Defaults()
	data.Upgrades.Bag = 3
	data.Orders.Slots[1] = { Id = 1, ItemId = "meadow_acorn", Qty = 3, Reward = 20, ReadyAt = 0 }
	Bag.Add(data, "meadow_acorn", nil, 2)
	Bag.Add(data, "meadow_acorn", "Golden", 1)
	Bag.Add(data, "meadow_acorn", "Shiny", 5)
	Bag.SetLocked(data, "meadow_acorn|Shiny", true)
	T.eq(Bag.Available(data, "meadow_acorn", nil), 3, "locked stack excluded")
	local reward = Orders.Fulfill(data, 1, 100)
	T.eq(reward, 20)
	T.eq(data.Bag.meadow_acorn, nil)
	T.eq(data.Bag["meadow_acorn|Golden"], nil)
	T.eq(data.Bag["meadow_acorn|Shiny"].Qty, 5, "locked untouched")
	T.eq(select(1, Orders.Fulfill(data, 1, 100)), nil, "second claim refused")
	T.eq(data.Coins, 25 + 20)
	Orders.Refresh(data, T.Rng(1), 120)
	T.eq(data.Orders.Slots[1].ItemId, nil, "not replaced before the delay")
	T.truthy(data.Orders.Slots[2].ItemId, "empty slots fill immediately")
	T.eq(Orders.Refresh(data, T.Rng(1), 200), true)
	T.truthy(data.Orders.Slots[1].ItemId, "replaced after the delay")
end)

T.test("not enough items: nothing is taken", function()
	local data = Schema.Defaults()
	data.Orders.Slots[1] = { Id = 1, ItemId = "meadow_acorn", Mut = "Golden", Qty = 1, Reward = 50, ReadyAt = 0 }
	Bag.Add(data, "meadow_acorn", nil, 4)
	T.eq(select(1, Orders.Fulfill(data, 1, 0)), nil, "plain doesn't satisfy a Golden order")
	T.eq(data.Bag.meadow_acorn.Qty, 4)
end)

T.test("skipping has a cooldown", function()
	local data = Schema.Defaults()
	Orders.Refresh(data, T.Rng(5), 0)
	T.eq(Orders.Skip(data, 1, 10), true)
	T.eq(Orders.Skip(data, 2, 20), false)
	T.eq(Orders.Skip(data, 2, 10 + Config.Economy.Orders.SkipCooldown), true)
end)

print("Crafting")

T.test("crafting consumes ingredients once and never locked ones", function()
	local data = Schema.Defaults()
	data.Upgrades.Bag = 4
	data.Coins = 1000
	Bag.Add(data, "meadow_acorn", nil, 10)
	Bag.Add(data, "meadow_old_coin", nil, 12)
	Bag.Add(data, "meadow_teacup_snail", nil, 3)
	Bag.SetLocked(data, "meadow_teacup_snail", true)
	T.eq(Workshop.Craft(data, "craft_petals"), false, "locked snail can't be used")
	Bag.SetLocked(data, "meadow_teacup_snail", false)
	T.eq(Workshop.Craft(data, "craft_petals"), true)
	T.eq(data.Coins, 600)
	T.eq(data.Bag.meadow_old_coin.Qty, 2)
	T.eq(data.Bag.meadow_acorn, nil)
	T.eq(data.Cosmetics.Aura, "petals", "auto-equipped")
	T.eq(Workshop.Craft(data, "craft_petals"), false, "already owned")
	T.eq(data.Stats.Crafts, 1)
	T.eq(Workshop.EquipCosmetic(data, "Aura", ""), true)
	T.eq(Workshop.EquipCosmetic(data, "Aura", "embers"), false)
	T.eq(Workshop.EquipCosmetic(data, "Tray", "royal"), false)
end)

print("Dailies & milestones")

T.test("dailies are stable per day, track progress, and pay once", function()
	local data = Schema.Defaults()
	Progress.EnsureDaily(data, 86400 * 100 + 5, 42)
	local first = data.Daily.List[1].Id
	T.eq(#data.Daily.List, 3)
	T.eq(Progress.EnsureDaily(data, 86400 * 100 + 999, 42), false, "same day, same list")
	T.eq(data.Daily.List[1].Id, first)
	for _, entry in data.Daily.List do
		T.truthy(entry.Id ~= "combo", "combo dailies need 2 dice")
	end
	local entry = data.Daily.List[1]
	Progress.Track(data, entry.Stat, entry.Goal * 5)
	T.eq(entry.Progress, entry.Goal, "progress capped")
	local coins = data.Coins
	T.eq(Progress.ClaimDaily(data, 1), entry.Reward)
	T.eq(data.Coins, coins + entry.Reward)
	T.eq(select(1, Progress.ClaimDaily(data, 1)), nil, "claimed once")
	T.eq(select(1, Progress.ClaimDaily(data, "1")), nil)
	T.eq(Progress.EnsureDaily(data, 86400 * 101, 42), true, "new day, fresh list")
end)

T.test("milestones and collection rewards", function()
	local data = Schema.Defaults()
	T.eq(select(1, Progress.ClaimMilestone(data, "rolls_100")), nil)
	data.Stats.Rolls = 100
	T.eq(Progress.Claimable(data).Milestones, 1)
	T.eq(Progress.ClaimMilestone(data, "rolls_100"), 300)
	T.eq(select(1, Progress.ClaimMilestone(data, "rolls_100")), nil, "once")
	T.eq(select(1, Progress.ClaimCollection(data, "meadow")), nil)
	for _, item in Config.ItemsIn("meadow") do
		Bag.Discover(data, item.Id, nil, 1, 0)
	end
	T.eq(Progress.Claimable(data).Collection, 1)
	T.eq(Progress.ClaimCollection(data, "meadow"), Config.Regions.ById.meadow.CollectionReward)
	T.eq(select(1, Progress.ClaimCollection(data, "meadow")), nil, "once")
	T.eq(Progress.StatValue(data, "Unique"), 10)
end)

print("World events")

T.test("events only apply in their region and odds still sum to 1", function()
	local event = { Id = "TreasureRush", Region = "meadow" }
	local base = Odds.Compute("meadow", { "wooden" })
	local boosted = Odds.Compute("meadow", { "wooden" }, nil, event)
	local elsewhere = Odds.Compute("crystal", { "wooden" }, nil, event)
	T.truthy(boosted.Tiers.Rare > base.Tiers.Rare, "rush boosts rare")
	T.near(elsewhere.Tiers.Rare, Odds.Compute("crystal", { "wooden" }).Tiers.Rare, 1e-12, "other regions unaffected")
	local total = 0
	for _, p in boosted.Tiers do
		total += p
	end
	T.near(total, 1, 1e-9)
	local lucky = Odds.Compute("meadow", { "glass" }, nil, { Id = "LuckyWinds", Region = "meadow" })
	T.near(lucky.MutationChance, 0.2, 1e-9, "glass x2 then event x2")
	local perks = LootMath.Perks({ "wooden" }, "meadow", { Id = "MerchantFestival", Region = "meadow" })
	T.eq(perks.EventSellBonus, 0.25)
end)

T.test("simulated event rolls match computed event odds", function()
	local event = { Id = "GoldenHour", Region = "meadow" }
	local rng = T.Rng(2024)
	local golden, mutated, n = 0, 0, 100000
	for _ = 1, n do
		local reward = RollEngine.Roll(rng, "meadow", { "wooden" }, nil, event).Rewards[1]
		if reward.Mut then
			mutated += 1
			if reward.Mut == "Golden" then
				golden += 1
			end
		end
	end
	local o = Odds.Compute("meadow", { "wooden" }, nil, event)
	T.near(golden / mutated, o.Mutations.Golden, 0.03, "golden share")
end)

print("Save migration")

T.test("a v1 save migrates to v2 without losing progress", function()
	local v1 = {
		Version = 1,
		Coins = 1234,
		Bag = { meadow_acorn = { Id = "meadow_acorn", Qty = 3, Locked = true, Seq = 4 } },
		Upgrades = { Bag = 2, Speed = 1, Sell = 0, AutoRoll = 1, DiceSlots = 0 },
		MutationsFound = { ["meadow_acorn|Shiny"] = true, ["meadow_old_coin|Golden"] = true },
		Stats = { Rolls = 77 },
		Tutorial = { Step = 4, Done = true },
	}
	local data = Schema.Load(v1) :: any
	T.eq(data.Version, Schema.Version)
	T.eq(data.Coins, 1234)
	T.eq(data.Bag.meadow_acorn.Locked, true)
	T.eq(data.Stats.Rolls, 77)
	T.eq(data.Stats.Mutated, 2, "backfilled")
	T.eq(data.Cosmetics.Tray, "classic")
	T.eq(#data.Orders.Slots, 0)
end)

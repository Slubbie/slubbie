-- Balance simulation: plays the Stage 1 loop with the real roll engine, bag and shop logic and
-- prints how long milestones take. Assumptions (also listed in docs/DESIGN.md):
--   * Manual rolling: cooldown + 0.35s reaction per roll. Auto-roll: cooldown + 0.1s.
--   * A sell trip (walk to the stall, sell, walk back) takes 12 seconds.
--   * The player sells everything when the bag is full, and also at each "shopping" check.
--   * Buying policy: buy any upgrade costing <= 600 (cheapest first), then save for the Crystal
--     Caverns gate (coins + Meadow discoveries). After paying for the gate, buy the cheapest
--     upgrade whenever affordable. (Stage 1 has no gate yet; the sim just deducts its price.)
--   * Only Meadow Market, one Wooden Die (Stage 1 content).

local Config = require(game:GetService("ReplicatedStorage").Dicebound.Config)
local Odds = require(game:GetService("ReplicatedStorage").Dicebound.Odds)
local Core = game:GetService("ServerScriptService").Dicebound.Core
local RollEngine = require(Core.RollEngine)
local Bag = require(Core.Bag)
local Shop = require(Core.Shop)
local Schema = require(Core.Schema)

local REACTION, AUTO_REACTION, SELL_TRIP = 0.35, 0.1, 12
local CHEAP = 600
local GATE = Config.Regions.ById.crystal.Unlock

local function simulate(seed: number)
	local rng = T.Rng(seed)
	local data = Schema.Defaults()
	local t = 0
	local marks = {}
	local function mark(name)
		if not marks[name] then
			marks[name] = t
		end
	end
	local function discoveries()
		local n = 0
		for id in data.Discovered do
			if Config.Items.ById[id].Region == "meadow" then
				n += 1
			end
		end
		return n
	end
	local function sellAll()
		local plan = Shop.PlanSellAll(data, true)
		if plan then
			Shop.ApplySale(data, plan)
		end
		t += SELL_TRIP
		mark("First sale")
	end
	local function shop()
		local bought = true
		while bought do
			bought = false
			local best, bestCost
			for _, upgrade in Config.Economy.Upgrades.List do
				local level = data.Upgrades[upgrade.Id]
				local nextLevel = upgrade.Levels[level + 2]
				if
					Config.IsLive(upgrade)
					and nextLevel
					and (nextLevel.Cost <= CHEAP or marks["Crystal Caverns affordable"])
				then
					if not bestCost or nextLevel.Cost < bestCost then
						best, bestCost = upgrade, nextLevel.Cost
					end
				end
			end
			if best and data.Coins >= bestCost then
				Shop.BuyUpgrade(data, best.Id, data.Upgrades[best.Id])
				mark("First upgrade")
				if best.Id == "AutoRoll" then
					mark("Auto-Roller")
				end
				bought = true
			end
		end
	end
	local rolls = 0
	while t < 3600 do
		if Bag.Free(data) < 1 then
			sellAll()
			shop()
		end
		local outcome = RollEngine.Roll(rng, "meadow", data.Dice.Equipped, data.Discovered)
		for _, reward in outcome.Rewards do
			Bag.Add(data, reward.Id, reward.Mut, reward.Qty)
			Bag.Discover(data, reward.Id, reward.Mut, reward.Qty, 0)
			local rarity = Config.Items.ById[reward.Id].Rarity
			if rarity == "Rare" then
				mark("First Rare")
			elseif rarity == "Epic" then
				mark("First Epic")
			elseif rarity == "Legendary" or rarity == "Mythic" then
				mark("First Legendary+")
			end
		end
		rolls += 1
		local auto = data.Upgrades.AutoRoll > 0
		t += Config.UpgradeValue("Speed", data.Upgrades.Speed) + (if auto then AUTO_REACTION else REACTION)
		if
			not marks["Crystal Caverns affordable"]
			and data.Coins >= GATE.Coins
			and discoveries() >= GATE.Discoveries
		then
			mark("Crystal Caverns affordable")
			data.Coins -= GATE.Coins
		end
		if rolls == 50 then
			marks.CoinsAfter50Rolls = data.Coins + Shop.PlanSellAll(data, true).Total
		end
	end
	marks.Upgrades = data.Stats.Upgrades
	marks.Discoveries = discoveries()
	marks.Rolls = rolls
	return marks
end

local function percentile(list: { number }, p: number): number
	table.sort(list)
	return list[math.max(1, math.floor(#list * p + 0.5))]
end

local function mmss(seconds: number?): string
	if not seconds then
		return "  >60:00"
	end
	return string.format("%5d:%02d", math.floor(seconds / 60), math.floor(seconds % 60))
end

print("Balance simulation (300 players, first hour of Stage 1)")
local runs = {}
for seed = 1, 300 do
	table.insert(runs, simulate(seed * 7919))
end

local o = Odds.Compute("meadow", { "wooden" })
print(string.format("  Expected value per roll (Wooden Die, Meadow): %.1f coins", o.ExpectedCoins))

local milestones = {
	"First sale",
	"First Rare",
	"First upgrade",
	"First Epic",
	"Auto-Roller",
	"Crystal Caverns affordable",
	"First Legendary+",
}
print("  Milestone                       p10      median   p90     (reached)")
local results = {}
for _, name in milestones do
	local times, reached = {}, 0
	for _, run in runs do
		if run[name] then
			reached += 1
		end
		table.insert(times, run[name] or math.huge)
	end
	local median = percentile(table.clone(times), 0.5)
	results[name] = median
	print(
		string.format(
			"  %-30s %s %s %s  %d%%",
			name,
			mmss(if percentile(table.clone(times), 0.1) == math.huge then nil else percentile(table.clone(times), 0.1)),
			mmss(if median == math.huge then nil else median),
			mmss(if percentile(table.clone(times), 0.9) == math.huge then nil else percentile(table.clone(times), 0.9)),
			math.floor(reached / #runs * 100)
		)
	)
end
local upgrades, discoveries, coins50 = {}, {}, {}
for _, run in runs do
	table.insert(upgrades, run.Upgrades)
	table.insert(discoveries, run.Discoveries)
	table.insert(coins50, run.CoinsAfter50Rolls)
end
print(string.format("  Coins from the first 50 rolls (median): %d", percentile(coins50, 0.5)))
print(string.format("  Upgrades bought in the first hour (median): %d", percentile(upgrades, 0.5)))
print(string.format("  Meadow items discovered in the first hour (median): %d / 9", percentile(discoveries, 0.5)))

T.test("pacing targets", function()
	T.truthy(results["First upgrade"] < 4 * 60, "first upgrade within a few minutes")
	T.truthy(results["Crystal Caverns affordable"] >= 8 * 60, "second region not too fast")
	T.truthy(results["Crystal Caverns affordable"] <= 17 * 60, "second region not too slow")
end)

-- ── Full progression (all regions, dice, slots) ────────────────────────────────
-- Extra assumptions: the player buys any upgrade or die costing <= 20% of the next region's
-- price (cheapest first), unlocks each region as soon as it can and moves there, leads with
-- the best die for the region (regional die > Clover > anything) and fills the other slots.
-- Orders, dailies, milestones and collection rewards are ignored, so real pacing is faster.
local Workshop = require(Core.Workshop)
local LootMath = require(game:GetService("ReplicatedStorage").Dicebound.LootMath)

local DIE_PREFERENCE = { "clover", "glass", "copper", "wooden" }

local function equipBest(data, regionId)
	local order = {}
	for _, die in Config.Dice.List do
		if data.Dice.Owned[die.Id] and die.RegionFaces and die.RegionFaces[regionId] then
			table.insert(order, die.Id)
		end
	end
	for _, id in DIE_PREFERENCE do
		if data.Dice.Owned[id] and not table.find(order, id) then
			table.insert(order, id)
		end
	end
	for _, die in Config.Dice.List do
		if data.Dice.Owned[die.Id] and not table.find(order, die.Id) then
			table.insert(order, die.Id)
		end
	end
	local slots = Config.UpgradeValue("DiceSlots", data.Upgrades.DiceSlots)
	while #order > slots do
		table.remove(order)
	end
	Workshop.Equip(data, order)
end

local function fullRun(seed: number, limit: number)
	local rng = T.Rng(seed)
	local data = Schema.Defaults()
	local t, region = 0, "meadow"
	local marks = {}
	local nextIndex = 2
	local function shop()
		local target = Config.Regions.List[nextIndex]
		local budget = if target then target.Unlock.Coins * 0.2 else math.huge
		local bought = true
		while bought do
			bought = false
			local bestKind, bestId, bestCost
			for _, upgrade in Config.Economy.Upgrades.List do
				local nextLevel = upgrade.Levels[data.Upgrades[upgrade.Id] + 2]
				if Config.IsLive(upgrade) and nextLevel and nextLevel.Cost <= budget then
					if not bestCost or nextLevel.Cost < bestCost then
						bestKind, bestId, bestCost = "Upgrade", upgrade.Id, nextLevel.Cost
					end
				end
			end
			for _, die in Config.Dice.List do
				local source = die.Source
				if
					source.Kind == "Shop"
					and not data.Dice.Owned[die.Id]
					and data.Regions[source.Region]
					and source.Price <= budget
				then
					if not bestCost or source.Price < bestCost then
						bestKind, bestId, bestCost = "Die", die.Id, source.Price
					end
				end
			end
			if bestCost and data.Coins >= bestCost then
				if bestKind == "Upgrade" then
					Shop.BuyUpgrade(data, bestId, data.Upgrades[bestId])
				else
					Workshop.BuyDie(data, bestId)
				end
				bought = true
			end
		end
		local target2 = Config.Regions.List[nextIndex]
		if target2 and Workshop.UnlockRegion(data, target2.Id) then
			marks[target2.Name] = t
			region = target2.Id
			nextIndex += 1
		end
		equipBest(data, region)
	end
	while t < limit and nextIndex <= #Config.Regions.List do
		local need = LootMath.MaxRewardUnits(#data.Dice.Equipped)
		if Bag.Free(data) < need then
			local plan = Shop.PlanSellAll(data, true)
			if plan then
				Shop.ApplySale(data, plan)
			end
			t += SELL_TRIP
			shop()
		end
		local outcome = RollEngine.Roll(rng, region, data.Dice.Equipped, data.Discovered)
		for _, reward in outcome.Rewards do
			Bag.Add(data, reward.Id, reward.Mut, reward.Qty)
			Bag.Discover(data, reward.Id, reward.Mut, reward.Qty, 0)
		end
		data.Coins += outcome.Coins
		local auto = data.Upgrades.AutoRoll > 0
		t += Config.UpgradeValue("Speed", data.Upgrades.Speed) + (if auto then AUTO_REACTION else REACTION)
	end
	return marks
end

print("\nFull progression (100 players, up to 6 hours of active play)")
local fullRuns = {}
for seed = 1, 100 do
	table.insert(fullRuns, fullRun(seed * 104729, 6 * 3600))
end
for i = 2, #Config.Regions.List do
	local name = Config.Regions.List[i].Name
	local times, reached = {}, 0
	for _, run in fullRuns do
		if run[name] then
			reached += 1
		end
		table.insert(times, run[name] or math.huge)
	end
	local function fmt(p)
		local v = percentile(table.clone(times), p)
		return if v == math.huge then "    >6h" else string.format("%4dh%02dm", v // 3600, (v % 3600) // 60)
	end
	print(string.format("  %-22s p10 %s   median %s   p90 %s   (%d%%)", name, fmt(0.1), fmt(0.5), fmt(0.9), reached))
end
for _, region in Config.Regions.List do
	local one = Odds.Compute(region.Id, { "wooden" }).ExpectedCoins
	local three = Odds.Compute(region.Id, { "clover", "glass", "copper" }).ExpectedCoins
	print(string.format("  EV/roll %-18s 1 wooden: %8.1f   clover+glass+copper: %8.1f", region.Name, one, three))
end

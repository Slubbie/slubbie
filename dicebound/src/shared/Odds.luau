-- Exact odds for a dice setup, computed from the same tables the server rolls with.
-- Used by the odds panel (base vs. your equipped dice) and by the balance tests.

local Config = require(script.Parent.Config)
local LootMath = require(script.Parent.LootMath)

local Economy = Config.Economy

local Odds = {}

export type Result = {
	Tiers: { [string]: number }, -- main reward tier (after fallback)
	Items: { [string]: number }, -- chance each item is the main reward
	MutationChance: number,
	Mutations: { [string]: number }, -- chance of each mutation, given the item is mutated
	Combos: { [string]: number },
	ExpectedCoins: number, -- average sell value per roll (before sell bonuses)
	MaxRewardUnits: number,
}

-- Distribution of item draws for one tier row: { [itemId] = probability }.
local function itemsForRow(regionId: string, row: { [string]: number }, perks, discovered): { [string]: number }
	local total = 0
	for _, weight in row do
		total += weight
	end
	local result = {}
	for tier, weight in row do
		local resolved = LootMath.ResolveTier(regionId, tier)
		if resolved then
			local list = LootMath.ItemWeights(regionId, resolved, perks, discovered)
			local sum = 0
			for _, entry in list do
				sum += entry.Weight
			end
			for _, entry in list do
				local p = (weight / total) * (entry.Weight / sum)
				result[entry.Item.Id] = (result[entry.Item.Id] or 0) + p
			end
		end
	end
	return result
end

local function expectedValue(items: { [string]: number }, mutationFactor: number): number
	local total = 0
	for itemId, p in items do
		total += p * Config.Items.ById[itemId].Value
	end
	return total * mutationFactor
end

function Odds.Compute(regionId: string, diceIds: { string }, discovered: { [string]: any }?): Result
	local perks = LootMath.Perks(diceIds)
	local chance, mutations = LootMath.MutationTable(regionId, perks)

	local mutationWeightSum = 0
	for _, entry in mutations do
		mutationWeightSum += entry.Weight
	end
	local mutationOdds = {}
	local averageMult = 0
	for _, entry in mutations do
		local p = entry.Weight / mutationWeightSum
		mutationOdds[entry.Id] = p
		averageMult += p * Economy.Mutations.ById[entry.Id].Multiplier
	end
	local mutationFactor = 1 + chance * (averageMult - 1)

	-- Per-face main reward distributions (cached).
	local faceItems = {}
	local faceValue = {}
	for face, row in Economy.FaceTiers do
		faceItems[face] = itemsForRow(regionId, row, perks, discovered)
		faceValue[face] = expectedValue(faceItems[face], mutationFactor)
	end

	local faceLists, maxFaces = {}, {}
	for i, dieId in diceIds do
		faceLists[i] = LootMath.FacesFor(dieId, regionId)
		maxFaces[i] = Config.Dice.MaxFace(faceLists[i])
	end

	local combos = Economy.Combos
	local region = Config.Regions.ById[regionId]
	local special = LootMath.ResolveTier(regionId, "Secret") == "Secret"
		and LootMath.ItemWeights(regionId, "Secret", perks, discovered)
	local specialValue = 0
	if special and #special > 0 then
		local sum = 0
		for _, entry in special do
			sum += entry.Weight
		end
		for _, entry in special do
			specialValue += entry.Weight / sum * entry.Item.Value
		end
		specialValue *= mutationFactor
	end
	local jackpotValue = expectedValue(itemsForRow(regionId, combos.Jackpot.JackpotTiers, perks, discovered), mutationFactor)
	local tripleValue = faceValue[combos.Triple.BonusFace]

	local result: Result = {
		Tiers = {},
		Items = {},
		MutationChance = chance,
		Mutations = mutationOdds,
		Combos = {},
		ExpectedCoins = 0,
		MaxRewardUnits = LootMath.MaxRewardUnits(#diceIds),
	}

	-- Enumerate every way the dice can land (at most 6^3 = 216 outcomes).
	local n = #diceIds
	local faces = table.create(n, 0)
	local p = 1 / (6 ^ n)
	local function visit(depth: number)
		if depth > n then
			local lead = faces[1]
			for itemId, q in faceItems[lead] do
				result.Items[itemId] = (result.Items[itemId] or 0) + p * q
			end
			local combo = LootMath.DetectCombo(faces, maxFaces)
			local value = faceValue[lead]
			if combo then
				result.Combos[combo] = (result.Combos[combo] or 0) + p
				if combo == "Pair" then
					value *= combos.Pair.MainQuantity
				elseif combo == "Triple" then
					value += tripleValue
				elseif combo == "Straight" then
					value += combos.Straight.CollectibleChance * specialValue
				elseif combo == "Jackpot" then
					value += jackpotValue + (region and region.JackpotCoins or 0)
				end
			end
			result.ExpectedCoins += p * value
			return
		end
		for _, face in faceLists[depth] do
			faces[depth] = face
			visit(depth + 1)
		end
	end
	visit(1)

	for itemId, q in result.Items do
		local tier = Config.Items.ById[itemId].Rarity
		result.Tiers[tier] = (result.Tiers[tier] or 0) + q
	end
	return result
end

-- Human-friendly percentage: 0.0123 -> "1.23%", tiny values -> "<0.01%".
function Odds.Format(p: number): string
	if p <= 0 then
		return "0%"
	elseif p < 0.0001 then
		return "<0.01%"
	elseif p < 0.01 then
		return string.format("%.2f%%", p * 100)
	elseif p < 0.1 then
		return string.format("%.1f%%", p * 100)
	end
	return string.format("%d%%", math.floor(p * 100 + 0.5))
end

return Odds

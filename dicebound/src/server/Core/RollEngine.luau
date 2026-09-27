-- Server-side roll resolution. Pure logic: give it a random source and it returns the outcome.
-- The client only ever animates what this decided.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Dicebound.Config)
local LootMath = require(ReplicatedStorage.Dicebound.LootMath)

local Economy = Config.Economy

local RollEngine = {}

-- Anything with NextNumber() in [0, 1) and NextInteger(min, max), e.g. Roblox's Random.
export type Rng = { NextNumber: (any) -> number, NextInteger: (any, number, number) -> number }

export type Reward = { Id: string, Mut: string?, Qty: number, Source: string }

export type Outcome = {
	DiceIds: { string },
	Faces: { number },
	Combo: string?,
	Tier: string,
	Rewards: { Reward },
	Coins: number,
	Units: number,
}

local function pickWeighted<T>(rng: Rng, entries: { T }, weightOf: (T) -> number): T?
	local total = 0
	for _, entry in entries do
		total += weightOf(entry)
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber() * total
	for _, entry in entries do
		roll -= weightOf(entry)
		if roll < 0 then
			return entry
		end
	end
	return entries[#entries]
end

-- Picks a tier from a { [tier] = weight } row. Iterates in rarity order for determinism.
local function pickTier(rng: Rng, row: { [string]: number }): string
	local entries = {}
	for _, rarity in Config.Rarities.List do
		if row[rarity.Id] then
			table.insert(entries, { Id = rarity.Id, Weight = row[rarity.Id] })
		end
	end
	local picked = pickWeighted(rng, entries, function(e)
		return e.Weight
	end)
	return if picked then picked.Id else "Common"
end

local function drawItem(rng: Rng, regionId: string, tier: string, perks, discovered): { [string]: any }?
	local resolved = LootMath.ResolveTier(regionId, tier)
	if not resolved then
		return nil
	end
	local entry = pickWeighted(rng, LootMath.ItemWeights(regionId, resolved, perks, discovered), function(e)
		return e.Weight
	end)
	return entry and entry.Item
end

local function rollMutation(rng: Rng, regionId: string, perks): string?
	local chance, list = LootMath.MutationTable(regionId, perks)
	if rng:NextNumber() >= chance then
		return nil
	end
	local picked = pickWeighted(rng, list, function(e)
		return e.Weight
	end)
	return picked and picked.Id
end

function RollEngine.Roll(
	rng: Rng,
	regionId: string,
	diceIds: { string },
	discovered: { [string]: any }?,
	event: LootMath.Event?
): Outcome
	assert(#diceIds >= 1 and #diceIds <= Economy.MaxDice, "bad dice count")
	local perks = LootMath.Perks(diceIds, regionId, event)

	local faces, maxFaces = {}, {}
	for i, dieId in diceIds do
		local list = LootMath.FacesFor(dieId, regionId)
		faces[i] = list[rng:NextInteger(1, #list)]
		maxFaces[i] = Config.Dice.MaxFace(list)
	end

	local outcome: Outcome = {
		DiceIds = table.clone(diceIds),
		Faces = faces,
		Combo = LootMath.DetectCombo(faces, maxFaces),
		Tier = "Common",
		Rewards = {},
		Coins = 0,
		Units = 0,
	}

	local function grant(item: { [string]: any }?, qty: number, source: string)
		if item then
			table.insert(outcome.Rewards, {
				Id = item.Id,
				Mut = rollMutation(rng, regionId, perks),
				Qty = qty,
				Source = source,
			})
			outcome.Units += qty
		end
	end

	-- Main reward: lead die face -> tier -> item.
	local tier = pickTier(rng, LootMath.TierRow(Economy.FaceTiers[faces[1]], perks))
	local main = drawItem(rng, regionId, tier, perks, discovered)
	outcome.Tier = if main then main.Rarity else tier

	local combos = Economy.Combos
	local combo = outcome.Combo
	grant(main, if combo == "Pair" then combos.Pair.MainQuantity else 1, "Main")

	if combo == "Triple" then
		local bonusTier = pickTier(rng, LootMath.TierRow(Economy.FaceTiers[combos.Triple.BonusFace], perks))
		grant(drawItem(rng, regionId, bonusTier, perks, discovered), 1, "Triple")
	elseif combo == "Straight" then
		if rng:NextNumber() < combos.Straight.CollectibleChance then
			grant(drawItem(rng, regionId, "Secret", perks, discovered), 1, "Straight")
		end
	elseif combo == "Jackpot" then
		local jackpotTier = pickTier(rng, combos.Jackpot.JackpotTiers)
		grant(drawItem(rng, regionId, jackpotTier, perks, discovered), 1, "Jackpot")
		local region = Config.Regions.ById[regionId]
		outcome.Coins = if region then region.JackpotCoins else 0
	end

	assert(outcome.Units <= LootMath.MaxRewardUnits(#diceIds), "reward bundle exceeds reserved space")
	return outcome
end

return RollEngine

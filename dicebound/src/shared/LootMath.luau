-- The deterministic half of the roll model: tables, weights and combo rules.
-- The server's RollEngine adds randomness on top of this; the client's odds display uses it to
-- show exact probabilities. Keeping both on one module means the displayed odds are the real odds.

local Config = require(script.Parent.Config)

local Economy = Config.Economy
local Rarities = Config.Rarities

local LootMath = {}

export type Perks = {
	SellBonus: number,
	MutationChanceMult: number,
	MutationWeights: { [string]: number },
	UndiscoveredBoost: number,
	TierBoost: number, -- multiplies Rare-and-better weights in face tier rows (world events)
	EventSellBonus: number, -- extra sell bonus from a world event at this merchant
}

-- An active world event: { Id = eventId, Region = regionId }.
export type Event = { Id: string, Region: string }

-- Combined perks of the equipped dice, plus the world event if it is running in `regionId`.
-- The same dice perk never stacks (the largest value wins). Event effects multiply on top.
function LootMath.Perks(diceIds: { string }, regionId: string?, event: Event?): Perks
	local perks: Perks = {
		SellBonus = 0,
		MutationChanceMult = 1,
		MutationWeights = {},
		UndiscoveredBoost = 1,
		TierBoost = 1,
		EventSellBonus = 0,
	}
	for _, dieId in diceIds do
		local die = Config.Dice.ById[dieId]
		local p = die and die.Perks or {}
		perks.SellBonus = math.max(perks.SellBonus, p.SellBonus or 0)
		perks.MutationChanceMult = math.max(perks.MutationChanceMult, p.MutationChanceMult or 1)
		perks.UndiscoveredBoost = math.max(perks.UndiscoveredBoost, p.UndiscoveredBoost or 1)
		for mutationId, mult in p.MutationWeights or {} do
			perks.MutationWeights[mutationId] = math.max(perks.MutationWeights[mutationId] or 1, mult)
		end
	end
	local def = event and regionId and event.Region == regionId and Economy.Events.ById[event.Id]
	if def then
		local e = def.Effects
		perks.MutationChanceMult *= e.MutationChanceMult or 1
		perks.TierBoost *= e.TierBoost or 1
		perks.UndiscoveredBoost = math.max(perks.UndiscoveredBoost, e.UndiscoveredBoost or 1)
		perks.EventSellBonus += e.SellBonus or 0
		for mutationId, mult in e.MutationWeights or {} do
			perks.MutationWeights[mutationId] = (perks.MutationWeights[mutationId] or 1) * mult
		end
	end
	return perks
end

-- A face tier row adjusted by perks: TierBoost multiplies Rare-and-better weights.
function LootMath.TierRow(row: { [string]: number }, perks: Perks?): { [string]: number }
	local boost = if perks then perks.TierBoost else 1
	if boost == 1 then
		return row
	end
	local adjusted = {}
	for tier, weight in row do
		adjusted[tier] = if Rarities.Order(tier) >= 3 then weight * boost else weight
	end
	return adjusted
end

function LootMath.FacesFor(dieId: string, regionId: string): { number }
	local die = Config.Dice.ById[dieId] or Config.Dice.ById[Config.Game.StartingDie]
	return Config.Dice.FacesFor(die, regionId)
end

-- Items that can be drawn for a region + tier. Normal tiers exclude Special collectibles;
-- the Secret tier contains only them.
local function candidates(regionId: string, tier: string): { { [string]: any } }
	local result = {}
	for _, item in Config.ItemsIn(regionId, tier) do
		if (tier == "Secret") == (item.Special == true) then
			table.insert(result, item)
		end
	end
	return result
end

-- If a region has no items of the requested tier, step DOWN to the nearest tier that has some
-- (then up, as a last resort). Returns nil only for a region with no items at all.
function LootMath.ResolveTier(regionId: string, tier: string): string?
	local start = Rarities.Order(tier)
	for order = start, 1, -1 do
		local id = Rarities.List[order].Id
		if #candidates(regionId, id) > 0 then
			return id
		end
	end
	for order = start + 1, #Rarities.List do
		local id = Rarities.List[order].Id
		if #candidates(regionId, id) > 0 then
			return id
		end
	end
	return nil
end

-- Weighted item list for a region + tier. `discovered` enables the UndiscoveredBoost perk.
function LootMath.ItemWeights(
	regionId: string,
	tier: string,
	perks: Perks?,
	discovered: { [string]: any }?
): { { Item: { [string]: any }, Weight: number } }
	local list = {}
	local boost = if perks then perks.UndiscoveredBoost else 1
	for _, item in candidates(regionId, tier) do
		local weight = item.Weight
		if boost > 1 and discovered and not discovered[item.Id] then
			weight *= boost
		end
		table.insert(list, { Item = item, Weight = weight })
	end
	return list
end

-- Mutation chance and the weighted list of mutations allowed in a region with these perks.
function LootMath.MutationTable(regionId: string, perks: Perks?): (number, { { Id: string, Weight: number } })
	local chanceMult = if perks then perks.MutationChanceMult else 1
	local chance = math.min(Economy.Mutations.BaseChance * chanceMult, Economy.Mutations.MaxChance)
	local list = {}
	for _, mutation in Economy.Mutations.List do
		local perkMult = perks and perks.MutationWeights[mutation.Id]
		local allowed = mutation.Regions == nil or mutation.Regions[regionId] == true or perkMult ~= nil
		if allowed then
			table.insert(list, { Id = mutation.Id, Weight = mutation.Weight * (perkMult or 1) })
		end
	end
	return chance, list
end

-- Which combo (if any) a set of faces makes. `maxFaces[i]` is die i's highest face.
-- Only one combo applies: the first match in Economy.Combos.Priority.
function LootMath.DetectCombo(faces: { number }, maxFaces: { number }): string?
	local count = #faces
	local combos = Economy.Combos
	for _, name in combos.Priority do
		local rule = combos[name]
		if count >= rule.MinDice then
			if name == "Jackpot" then
				local all = true
				for i, face in faces do
					if face ~= maxFaces[i] then
						all = false
						break
					end
				end
				if all then
					return name
				end
			elseif name == "Triple" then
				if count >= 3 and faces[1] == faces[2] and faces[2] == faces[3] then
					return name
				end
			elseif name == "Straight" then
				if count >= 3 then
					local sorted = table.clone(faces)
					table.sort(sorted)
					if sorted[2] == sorted[1] + 1 and sorted[3] == sorted[2] + 1 then
						return name
					end
				end
			elseif name == "Pair" then
				local seen = {}
				for _, face in faces do
					if seen[face] then
						return name
					end
					seen[face] = true
				end
			end
		end
	end
	return nil
end

-- The largest number of item units a single roll can grant with this many dice. The server
-- only accepts a roll when the bag has at least this much free space, so rewards are never lost.
function LootMath.MaxRewardUnits(diceCount: number): number
	if diceCount <= 1 then
		return 1
	end
	local combos = Economy.Combos
	local best = 1
	for _, name in combos.Priority do
		local rule = combos[name]
		if diceCount >= rule.MinDice then
			if name == "Pair" then
				best = math.max(best, rule.MainQuantity)
			else
				best = math.max(best, 2) -- main reward + one extra reward
			end
		end
	end
	return best
end

return LootMath

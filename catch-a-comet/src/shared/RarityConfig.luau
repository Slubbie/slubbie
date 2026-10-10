--!strict
-- Creature rarity and mutation odds, plus the weighted roll used by the
-- server. The client only reads these tables to *display* odds; it never
-- rolls rewards.
--
-- Weights don't have to add up to 100 (they are normalized), but the
-- shipped tables do, and Validate() reports any table that doesn't.

local RarityConfig = {}

export type Rarity = {
	Id: string,
	Index: number,
	Weight: number,
	BaseRate: number, -- Stardust per second for a creature of this rarity
	Color: Color3,
	-- How elaborate the reveal is: 1 quick pop … 4 full cinematic.
	RevealTier: number,
}

export type Mutation = {
	Id: string,
	Index: number,
	Weight: number,
	Bonus: number, -- +0.05 = +5% Stardust
	Color: Color3,
	Description: string,
}

export type Odds = { { Id: string, Chance: number } }

-- An event (Phase 3) can multiply weights, e.g. { Rarity = { Epic = 2 } }.
export type Modifiers = {
	Rarity: { [string]: number }?,
	Mutation: { [string]: number }?,
}

-- Anything with :NextNumber() returning [0, 1): Roblox's Random, or a test double.
-- (Typed loosely because Random:NextNumber is overloaded.)
export type RNG = any

RarityConfig.Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

RarityConfig.Rarities = {
	Common = {
		Id = "Common",
		Index = 1,
		Weight = 55,
		BaseRate = 1,
		Color = Color3.fromRGB(230, 233, 245),
		RevealTier = 1,
	},
	Uncommon = {
		Id = "Uncommon",
		Index = 2,
		Weight = 26,
		BaseRate = 3,
		Color = Color3.fromRGB(125, 227, 170),
		RevealTier = 1,
	},
	Rare = { Id = "Rare", Index = 3, Weight = 12, BaseRate = 9, Color = Color3.fromRGB(111, 182, 255), RevealTier = 2 },
	Epic = { Id = "Epic", Index = 4, Weight = 5, BaseRate = 27, Color = Color3.fromRGB(182, 156, 255), RevealTier = 3 },
	Legendary = {
		Id = "Legendary",
		Index = 5,
		Weight = 1.7,
		BaseRate = 90,
		Color = Color3.fromRGB(255, 207, 112),
		RevealTier = 4,
	},
	Mythic = {
		Id = "Mythic",
		Index = 6,
		Weight = 0.3,
		BaseRate = 250,
		Color = Color3.fromRGB(255, 126, 152),
		RevealTier = 4,
	},
} :: { [string]: Rarity }

-- Mythic shimmers through these colours in the UI.
RarityConfig.MythicGradient = {
	Color3.fromRGB(255, 126, 152),
	Color3.fromRGB(255, 207, 112),
	Color3.fromRGB(116, 229, 254),
	Color3.fromRGB(182, 156, 255),
}

RarityConfig.MutationOrder = { "Standard", "Charged", "Aurora", "Eclipse", "Prismatic" }

RarityConfig.Mutations = {
	Standard = {
		Id = "Standard",
		Index = 1,
		Weight = 88,
		Bonus = 0,
		Color = Color3.fromRGB(169, 178, 214),
		Description = "The creature's natural colours.",
	},
	Charged = {
		Id = "Charged",
		Index = 2,
		Weight = 8,
		Bonus = 0.05,
		Color = Color3.fromRGB(116, 229, 254),
		Description = "Crackles with electric sparks.",
	},
	Aurora = {
		Id = "Aurora",
		Index = 3,
		Weight = 3,
		Bonus = 0.1,
		Color = Color3.fromRGB(156, 245, 216),
		Description = "Shifting pastel light and drifting ribbons.",
	},
	Eclipse = {
		Id = "Eclipse",
		Index = 4,
		Weight = 0.9,
		Bonus = 0.15,
		Color = Color3.fromRGB(255, 231, 160),
		Description = "Dark body traced with bright corona light.",
	},
	Prismatic = {
		Id = "Prismatic",
		Index = 5,
		Weight = 0.1,
		Bonus = 0.25,
		Color = Color3.fromRGB(255, 160, 230),
		Description = "A slow rainbow shimmer. Extraordinarily rare.",
	},
} :: { [string]: Mutation }

local function weightsOf(order: { string }, defs: { [string]: any }, multipliers: { [string]: number }?): { number }
	local weights = table.create(#order)
	for i, id in order do
		local weight = defs[id].Weight
		if multipliers and multipliers[id] then
			weight *= multipliers[id]
		end
		weights[i] = math.max(weight, 0)
	end
	return weights
end

-- Picks an index from a list of weights. Returns the last positive weight
-- if floating point error pushes the roll past the end.
function RarityConfig.PickWeighted(weights: { number }, rng: RNG): number
	local total = 0
	for _, weight in weights do
		total += weight
	end
	assert(total > 0, "PickWeighted: weights must contain a positive value")
	local roll = rng:NextNumber() * total
	local lastPositive = 1
	for i, weight in weights do
		if weight > 0 then
			lastPositive = i
			if roll < weight then
				return i
			end
			roll -= weight
		end
	end
	return lastPositive
end

function RarityConfig.RollRarity(rng: RNG, modifiers: Modifiers?): string
	local weights = weightsOf(RarityConfig.Order, RarityConfig.Rarities, modifiers and modifiers.Rarity)
	return RarityConfig.Order[RarityConfig.PickWeighted(weights, rng)]
end

function RarityConfig.RollMutation(rng: RNG, modifiers: Modifiers?): string
	local weights = weightsOf(RarityConfig.MutationOrder, RarityConfig.Mutations, modifiers and modifiers.Mutation)
	return RarityConfig.MutationOrder[RarityConfig.PickWeighted(weights, rng)]
end

local function oddsOf(order: { string }, defs: { [string]: any }, multipliers: { [string]: number }?): Odds
	local weights = weightsOf(order, defs, multipliers)
	local total = 0
	for _, weight in weights do
		total += weight
	end
	local odds = {}
	for i, id in order do
		table.insert(odds, { Id = id, Chance = if total > 0 then weights[i] / total else 0 })
	end
	return odds
end

-- The exact odds the server uses, after any modifiers. The UI shows these,
-- so a boosted event never displays misleading numbers.
function RarityConfig.GetRarityOdds(modifiers: Modifiers?): Odds
	return oddsOf(RarityConfig.Order, RarityConfig.Rarities, modifiers and modifiers.Rarity)
end

function RarityConfig.GetMutationOdds(modifiers: Modifiers?): Odds
	return oddsOf(RarityConfig.MutationOrder, RarityConfig.Mutations, modifiers and modifiers.Mutation)
end

function RarityConfig.IsRarity(id: any): boolean
	return type(id) == "string" and RarityConfig.Rarities[id] ~= nil
end

function RarityConfig.IsMutation(id: any): boolean
	return type(id) == "string" and RarityConfig.Mutations[id] ~= nil
end

function RarityConfig.RarityIndex(id: string): number
	local rarity = RarityConfig.Rarities[id]
	return if rarity then rarity.Index else 0
end

-- Returns a list of problems (empty when the tables are sound).
function RarityConfig.Validate(): { string }
	local problems = {}
	local function check(name: string, order: { string }, defs: { [string]: any })
		local total = 0
		local seen = {}
		for i, id in order do
			local def = defs[id]
			if not def then
				table.insert(problems, `{name}: '{id}' is in the order list but has no definition`)
				continue
			end
			seen[id] = true
			if def.Id ~= id then
				table.insert(problems, `{name}: '{id}' has mismatched Id '{def.Id}'`)
			end
			if def.Index ~= i then
				table.insert(problems, `{name}: '{id}' has Index {def.Index}, expected {i}`)
			end
			if type(def.Weight) ~= "number" or def.Weight < 0 or def.Weight ~= def.Weight then
				table.insert(problems, `{name}: '{id}' has an invalid weight`)
			else
				total += def.Weight
			end
		end
		for id in defs do
			if not seen[id] then
				table.insert(problems, `{name}: '{id}' is defined but missing from the order list`)
			end
		end
		if math.abs(total - 100) > 1e-6 then
			table.insert(problems, `{name}: weights total {total}, expected 100`)
		end
	end
	check("Rarity", RarityConfig.Order, RarityConfig.Rarities)
	check("Mutation", RarityConfig.MutationOrder, RarityConfig.Mutations)
	return problems
end

return RarityConfig

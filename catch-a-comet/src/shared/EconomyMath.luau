--!strict
-- Every economy formula in one place. The server uses these to award
-- currency; the client uses the same functions only to *display* numbers,
-- so the UI and the real payout can't drift apart.

local BiomeDefinitions = require(script.Parent.BiomeDefinitions)
local CreatureDefinitions = require(script.Parent.CreatureDefinitions)
local GameConfig = require(script.Parent.GameConfig)
local RarityConfig = require(script.Parent.RarityConfig)

local EconomyMath = {}

export type CreatureLike = {
	Species: string,
	Mutation: string,
	Bond: number,
}

function EconomyMath.MutationMultiplier(mutation: string): number
	local def = RarityConfig.Mutations[mutation]
	return 1 + (if def then def.Bonus else 0)
end

function EconomyMath.BondMultiplier(bond: number): number
	local level = math.clamp(math.floor(bond), 1, GameConfig.Creatures.MaxBond)
	return 1 + GameConfig.Creatures.BondBonusPerLevel * (level - 1)
end

-- Creature Income = Base Species Rate × Mutation × Bond × Progression bonus
function EconomyMath.CreatureIncome(creature: CreatureLike, progressionBonus: number?): number
	return CreatureDefinitions.BaseRate(creature.Species)
		* EconomyMath.MutationMultiplier(creature.Mutation)
		* EconomyMath.BondMultiplier(creature.Bond)
		* (progressionBonus or 1)
end

-- Total Stardust/second from every deployed creature.
function EconomyMath.SanctuaryIncome(
	creatures: { [string]: CreatureLike },
	equipped: { [string]: string },
	progressionBonus: number?
): number
	local total = 0
	for _, creatureId in equipped do
		local creature = creatures[creatureId]
		if creature then
			total += EconomyMath.CreatureIncome(creature, progressionBonus)
		end
	end
	return total
end

function EconomyMath.XPToNext(level: number): number
	local p = GameConfig.Progression
	return math.floor(p.XPBase + p.XPScale * math.max(level - 1, 0) ^ p.XPExponent)
end

-- Adds XP and rolls over levels. Returns the new level, the XP into that
-- level, and how many levels were gained. At the cap, XP stops accumulating.
function EconomyMath.AddXP(level: number, xp: number, amount: number): (number, number, number)
	local cap = GameConfig.Progression.LevelCap
	local gained = 0
	xp += math.max(amount, 0)
	while level < cap do
		local need = EconomyMath.XPToNext(level)
		if xp < need then
			break
		end
		xp -= need
		level += 1
		gained += 1
	end
	if level >= cap then
		level = cap
		xp = 0
	end
	return level, xp, gained
end

function EconomyMath.LevelUpStardust(newLevel: number): number
	return GameConfig.Progression.LevelUpStardust * newLevel
end

function EconomyMath.RankForQuality(quality: number): GameConfig.QualityRank
	local ranks = GameConfig.QualityRanks
	local chosen = ranks[1]
	for _, rank in ranks do
		if quality >= rank.Min - 1e-9 then
			chosen = rank
		end
	end
	return chosen
end

function EconomyMath.RankIndex(rankId: string): number
	for i, rank in GameConfig.QualityRanks do
		if rank.Id == rankId then
			return i
		end
	end
	return 0
end

-- Immediate rewards for a successful capture.
function EconomyMath.CaptureReward(biomeId: string, cometTypeId: string, quality: number): (number, number, string)
	local biome = BiomeDefinitions.Biomes[biomeId]
	local cometType = GameConfig.Comets.Types[cometTypeId]
	local rank = EconomyMath.RankForQuality(quality)
	local baseStardust = if biome then biome.CaptureStardust else 0
	local xpMultiplier = if biome then biome.XPMultiplier else 1
	local typeStardust = if cometType then cometType.StardustMult else 1
	local typeXP = if cometType then cometType.XPMult else 1
	local stardust = math.floor(baseStardust * typeStardust * rank.StardustMult + 0.5)
	local xp = math.floor(GameConfig.Progression.CaptureXP * xpMultiplier * typeXP * rank.XPMult + 0.5)
	return stardust, xp, rank.Id
end

-- Offline earnings for an absence of `seconds` at `ratePerSecond`.
-- Returns the award and the seconds that were counted.
function EconomyMath.OfflineEarnings(ratePerSecond: number, seconds: number): (number, number)
	local income = GameConfig.Income
	if seconds < income.OfflineMinSeconds or ratePerSecond <= 0 then
		return 0, 0
	end
	local counted = math.min(seconds, income.OfflineMaxSeconds)
	local award = math.floor(ratePerSecond * income.OfflineRate * counted)
	return math.min(award, income.OfflineMaxAward), counted
end

function EconomyMath.ReleaseValue(creature: CreatureLike): number
	return math.max(1, math.floor(EconomyMath.CreatureIncome(creature) * GameConfig.Creatures.ReleaseValueSeconds))
end

return EconomyMath

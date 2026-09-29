-- Genetics for seeds and animals.
--
-- Seeds carry four genes (0-10):
--   V Vigor      +2% growth speed per point
--   B Bounty     +3% chance of an extra harvest item per point
--   H Hardiness  +3% weather tolerance and pest resistance per point
--   L Luster     counts toward crop quality (Quality.Weights.Genes)
-- plus an optional latent trait (a mutation id) that makes that mutation far
-- more likely when the seed is grown.
--
-- Animals carry two alleles for Coat and Pattern (the lowest Dom shows, so rare
-- coats are recessive) and quantitative traits Size, Yield, Temper, Speed (0-10).
--
-- Everything here takes a Random so the server can roll and the client can
-- show odds; nothing here decides outcomes by itself.

local Config = script.Parent.Parent.Config
local Animals = require(Config.Animals)
local Crops = require(Config.Crops)
local Mutations = require(Config.Mutations)
local RNG = require(script.Parent.RNG)

local Genetics = {}

Genetics.GeneNames = { "Vigor", "Bounty", "Hardiness", "Luster" }
Genetics.GeneIcons = { "⚡", "🧺", "🛡️", "✨" }

-- Seeds -------------------------------------------------------------------------------------------

function Genetics.ShopGenes(random: Random): { number }
	local lo, hi = Crops.ShopGeneRange[1], Crops.ShopGeneRange[2]
	return {
		random:NextInteger(lo, hi),
		random:NextInteger(lo, hi),
		random:NextInteger(lo, hi),
		random:NextInteger(lo, hi),
	}
end

local function clampGene(g: number): number
	return math.clamp(math.floor(g + 0.5), 0, 10)
end

-- Seeds made from a crop (Seed Maker): genes drift slightly. `improve` (0-1)
-- biases drift upward (Farming skill).
function Genetics.Inherit(genes: { number }?, random: Random, improve: number?): { number }
	local base = genes or { 1, 1, 1, 1 }
	local out = {}
	for i = 1, 4 do
		local g = base[i] or 1
		if random:NextNumber() < 0.3 then
			local up = random:NextNumber() < 0.5 + (improve or 0) * 0.3
			g += if up then 1 else -1
		end
		out[i] = clampGene(g)
	end
	return out
end

-- Cross two seeds of the same species.
function Genetics.Cross(a: { number }, b: { number }, random: Random, breakthrough: number?): { number }
	local out = {}
	for i = 1, 4 do
		local mean = ((a[i] or 0) + (b[i] or 0)) / 2
		local roll = random:NextNumber()
		local noise = if roll < 0.25 then -1 elseif roll < 0.75 then 0 else 1
		out[i] = mean + noise
	end
	if random:NextNumber() < 0.08 + (breakthrough or 0) then
		local i = random:NextInteger(1, 4)
		out[i] += 2
	end
	for i = 1, 4 do
		out[i] = clampGene(out[i])
	end
	return out
end

-- Latent trait for a seed made from a crop with these mutations (or nil).
function Genetics.LatentFrom(mutations: { string }?, random: Random, chance: number?): string?
	if not mutations or #mutations == 0 then
		return nil
	end
	local candidates = {}
	for _, id in mutations do
		for _, def in Mutations.List do
			if def.Id == id and not def.OnHarvest then
				table.insert(candidates, id)
			end
		end
	end
	if #candidates == 0 or random:NextNumber() > (chance or 0.25) then
		return nil
	end
	return candidates[random:NextInteger(1, #candidates)]
end

function Genetics.GrowthMult(genes: { number }?): number
	return 1 + 0.02 * ((genes and genes[1]) or 0)
end

function Genetics.YieldChance(genes: { number }?): number
	return 0.03 * ((genes and genes[2]) or 0)
end

function Genetics.Hardiness(genes: { number }?): number
	return 0.03 * ((genes and genes[3]) or 0)
end

function Genetics.Luster(genes: { number }?): number
	return ((genes and genes[4]) or 0) / 10
end

function Genetics.GeneScore(genes: { number }?): number
	if not genes then
		return 0
	end
	return (genes[1] + genes[2] + genes[3] + genes[4]) / 40
end

-- Hybrid species for two crop ids (either order), or nil.
function Genetics.Hybrid(cropA: string, cropB: string)
	for _, hybrid in Crops.Hybrids do
		if (hybrid.A == cropA and hybrid.B == cropB) or (hybrid.A == cropB and hybrid.B == cropA) then
			return hybrid
		end
	end
	return nil
end

-- Animals -------------------------------------------------------------------------------------------

local speciesById = {}
for _, s in Animals.List do
	speciesById[s.Id] = s
end

export type AnimalGenes = {
	Coat: { string },
	Pattern: { string },
	Size: number,
	Yield: number,
	Temper: number,
	Speed: number,
}

local function alleleDef(list: { any }, id: string)
	for _, allele in list do
		if allele.Id == id then
			return allele
		end
	end
	return list[1]
end

local function drawAllele(list: { any }, random: Random): string
	local entry = RNG.WeightedEntry(list, function(a)
		return a.Weight
	end, random:NextNumber())
	return (entry or list[1]).Id
end

function Genetics.RandomAnimal(speciesId: string, random: Random): AnimalGenes
	local species = speciesById[speciesId]
	local function trait()
		return math.clamp(5 + RNG.Gaussian(random) * 1.6, 0, 10)
	end
	return {
		Coat = { drawAllele(species.Coats, random), drawAllele(species.Coats, random) },
		Pattern = { drawAllele(species.Patterns, random), drawAllele(species.Patterns, random) },
		Size = trait(),
		Yield = trait(),
		Temper = trait(),
		Speed = trait(),
	}
end

-- The visible allele for a pair (lowest Dom wins).
function Genetics.Express(list: { any }, pair: { string })
	local a = alleleDef(list, pair[1])
	local b = alleleDef(list, pair[2] or pair[1])
	return if a.Dom <= b.Dom then a else b
end

function Genetics.Phenotype(speciesId: string, genes: AnimalGenes)
	local species = speciesById[speciesId]
	return {
		Coat = Genetics.Express(species.Coats, genes.Coat),
		Pattern = Genetics.Express(species.Patterns, genes.Pattern),
		Size = 0.7 + genes.Size / 10 * 0.7,
	}
end

local RARITY_ORDER = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6 }
local RARITY_NAMES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

-- Overall rarity of an animal: its rarest expressed trait, nudged up by great stats.
function Genetics.AnimalRarity(speciesId: string, genes: AnimalGenes): string
	local p = Genetics.Phenotype(speciesId, genes)
	local order = math.max(RARITY_ORDER[p.Coat.Rarity] or 1, RARITY_ORDER[p.Pattern.Rarity] or 1)
	local stats = (genes.Size + genes.Yield + genes.Temper + genes.Speed) / 40
	if stats > 0.8 then
		order += 1
	end
	return RARITY_NAMES[math.clamp(order, 1, 6)]
end

-- Breed two animals of the same species.
function Genetics.Breed(
	speciesId: string,
	a: AnimalGenes,
	b: AnimalGenes,
	random: Random,
	mutationBonus: number?
): AnimalGenes
	local species = speciesById[speciesId]
	local function pick(pair: { string }): string
		return pair[random:NextInteger(1, #pair)]
	end
	local function quant(x: number, y: number): number
		return math.clamp((x + y) / 2 + RNG.Gaussian(random) * Animals.QuantitativeNoise, 0, 10)
	end
	local child: AnimalGenes = {
		Coat = { pick(a.Coat), pick(b.Coat) },
		Pattern = { pick(a.Pattern), pick(b.Pattern) },
		Size = quant(a.Size, b.Size),
		Yield = quant(a.Yield, b.Yield),
		Temper = quant(a.Temper, b.Temper),
		Speed = quant(a.Speed, b.Speed),
	}
	-- Rare mutation: a new rare allele appears on one side.
	if random:NextNumber() < Animals.MutationChance * (1 + (mutationBonus or 0)) then
		local rare = {}
		for _, allele in species.Coats do
			if (RARITY_ORDER[allele.Rarity] or 1) >= 3 then
				table.insert(rare, allele.Id)
			end
		end
		if #rare > 0 then
			child.Coat[random:NextInteger(1, 2)] = rare[random:NextInteger(1, #rare)]
		end
	end
	return child
end

-- Punnett-square odds of each visible coat/pattern from two parents.
function Genetics.BreedOdds(
	speciesId: string,
	a: AnimalGenes,
	b: AnimalGenes
): { Coat: { [string]: number }, Pattern: { [string]: number } }
	local species = speciesById[speciesId]
	local out = { Coat = {}, Pattern = {} }
	for _, x in a.Coat do
		for _, y in b.Coat do
			local shown = Genetics.Express(species.Coats, { x, y })
			out.Coat[shown.Id] = (out.Coat[shown.Id] or 0) + 1 / (#a.Coat * #b.Coat)
		end
	end
	for _, x in a.Pattern do
		for _, y in b.Pattern do
			local shown = Genetics.Express(species.Patterns, { x, y })
			out.Pattern[shown.Id] = (out.Pattern[shown.Id] or 0) + 1 / (#a.Pattern * #b.Pattern)
		end
	end
	return out
end

function Genetics.ValidAnimal(speciesId: string, genes: any): boolean
	local species = speciesById[speciesId]
	if not species or type(genes) ~= "table" then
		return false
	end
	for _, key in { "Coat", "Pattern" } do
		local pair = genes[key]
		if type(pair) ~= "table" or #pair ~= 2 then
			return false
		end
	end
	for _, key in { "Size", "Yield", "Temper", "Speed" } do
		if type(genes[key]) ~= "number" then
			return false
		end
	end
	return true
end

return Genetics

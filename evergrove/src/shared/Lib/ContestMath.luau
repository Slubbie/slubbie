-- Transparent festival contest scoring, shared by server (judging) and client
-- (the entry screen shows exactly how an entry will score before you submit).
--
-- Score (0-100) = Σ weight × criterion over Scoring weights that sum to 100.
-- Each criterion is in [0, 1]:
--   Quality    item quality tier / 6            | animal: average of its four stat genes / 10
--   Size       item size vs the species range   | animal: Size gene / 10
--   Rarity     rarity order / 6                 | animal: expressed rarity / 6
--   Mutations  log-scaled mutation value (+ combos) | animals: 0
--   Care       specimens and top quality count as well tended | animal: (happiness + friendship) / 2

local Registry = require(script.Parent.Registry)
local ItemUtil = require(script.Parent.ItemUtil)
local Genetics = require(script.Parent.Genetics)

local ContestMath = {}

export type Breakdown = { Quality: number, Size: number, Rarity: number, Mutations: number, Care: number }

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

-- Does an entry satisfy an activity's Accept list?
function ContestMath.Accepts(activity: any, entry: any): boolean
	for _, spec in activity.Accept or {} do
		if spec == "Animal" then
			if entry.Kind == "Animal" then
				return true
			end
		elseif entry.Kind == "Item" and entry.Stack and Registry.Matches(entry.Stack.Id, spec) then
			return true
		end
	end
	return false
end

local function sizeOf(stack: any): number
	local s = tonumber(stack.S)
	if not s then
		return 0.4
	end
	local crop = Registry.Crops[stack.Id]
	if crop then
		local top = crop.Size[1] + crop.Size[2] * 3
		return clamp01(s / math.max(0.01, top))
	end
	local fish = Registry.Fish[stack.Id]
	if fish then
		return clamp01((s - fish.Size[1]) / math.max(1, fish.Size[2] - fish.Size[1]))
	end
	return 0.4
end

function ContestMath.Criteria(entry: any): Breakdown
	if entry.Kind == "Animal" then
		local animal = entry.Animal
		local g = animal.G
		local rarity = Genetics.AnimalRarity(animal.Sp, g)
		return {
			Quality = clamp01((g.Size + g.Yield + g.Temper + g.Speed) / 40),
			Size = clamp01(g.Size / 10),
			Rarity = clamp01(Registry.RarityOrder(rarity) / 6),
			Mutations = 0,
			Care = clamp01(((animal.Hap or 0) / 100 + (animal.Fr or 0) / 1000) / 2),
		}
	end
	local stack = entry.Stack
	local mult = ItemUtil.MutationMultiplier(stack.M)
	local combos = 0
	for _, id in stack.M or {} do
		if ItemUtil.IsCombo(id) then
			combos += 1
		end
	end
	return {
		Quality = clamp01((stack.Q or 1) / 6),
		Size = sizeOf(stack),
		Rarity = clamp01(Registry.RarityOrder(ItemUtil.Rarity(stack)) / 6),
		Mutations = clamp01(math.log(math.max(1, mult)) / math.log(60) + combos * 0.15),
		Care = if stack.U then 1 elseif (stack.Q or 1) >= 4 then 0.8 else 0.5,
	}
end

-- Total score (0-100, one decimal) and the per-criterion points.
function ContestMath.Score(activity: any, entry: any): (number, { [string]: number })
	local criteria = ContestMath.Criteria(entry)
	local points = {}
	local total = 0
	for key, weight in activity.Scoring or {} do
		local value = (criteria :: any)[key] or 0
		points[key] = math.floor(value * weight * 10 + 0.5) / 10
		total += value * weight
	end
	return math.floor(total * 10 + 0.5) / 10, points
end

return ContestMath

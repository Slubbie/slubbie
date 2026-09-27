-- Item stacks: identity, stacking, value and display names.
--
-- A stack is a small table saved in inventories:
--   Id  item id              N  count
--   Q   quality tier (1-6)   M  mutation ids (sorted; combos included)
--   G   seed genes {V,B,H,L} T  latent trait carried by a bred seed
--   S   size in kg (specimens — a notable single crop — never stack)
--   U   unique id (specimens, named items)
--   L   locked (can't be sold/trashed until unlocked)
-- Stacks with the same key (everything except N and L) merge.

local Config = script.Parent.Parent.Config
local Mutations = require(Config.Mutations)
local Quality = require(Config.Quality)
local Registry = require(script.Parent.Registry)

export type Stack = {
	Id: string,
	N: number,
	Q: number?,
	M: { string }?,
	G: { number }?,
	T: string?,
	S: number?,
	U: string?,
	L: boolean?,
}

local ItemUtil = {}

function ItemUtil.New(id: string, count: number?, quality: number?, mutations: { string }?): Stack
	local stack: Stack = { Id = id, N = count or 1 }
	if quality and quality > 1 then
		stack.Q = quality
	end
	if mutations and #mutations > 0 then
		local sorted = table.clone(mutations)
		table.sort(sorted)
		stack.M = sorted
	end
	return stack
end

function ItemUtil.Key(stack: Stack): string
	local parts = { stack.Id, tostring(stack.Q or 1) }
	if stack.M and #stack.M > 0 then
		table.insert(parts, table.concat(stack.M, ","))
	else
		table.insert(parts, "")
	end
	if stack.G then
		table.insert(parts, table.concat(stack.G, "."))
	else
		table.insert(parts, "")
	end
	table.insert(parts, stack.T or "")
	table.insert(parts, stack.U or "")
	return table.concat(parts, "|")
end

function ItemUtil.CanStack(a: Stack, b: Stack): boolean
	if a.U or b.U then
		return false
	end
	return ItemUtil.Key(a) == ItemUtil.Key(b)
end

function ItemUtil.MaxStack(id: string): number
	local def = Registry.Items[id]
	return if def then def.Stack else 999
end

-- Copy with a different count (shares nothing mutable).
function ItemUtil.Split(stack: Stack, count: number): Stack
	local copy = table.clone(stack)
	copy.N = count
	copy.L = nil
	if stack.M then
		copy.M = table.clone(stack.M)
	end
	if stack.G then
		copy.G = table.clone(stack.G)
	end
	return copy
end

-- Mutations ------------------------------------------------------------------------------------

local mutationById = {}
for _, m in Mutations.List do
	mutationById[m.Id] = m
end
local comboById = {}
for _, c in Mutations.Combos do
	comboById[c.Id] = c
end

function ItemUtil.MutationDef(id: string)
	return mutationById[id] or comboById[id]
end

function ItemUtil.IsCombo(id: string): boolean
	return comboById[id] ~= nil
end

-- Combined value multiplier: the best mutation counts fully, the rest at StackFalloff,
-- combos multiply fully, capped at ValueCap.
function ItemUtil.MutationMultiplier(mutations: { string }?): number
	if not mutations or #mutations == 0 then
		return 1
	end
	local bonuses = {}
	local comboMult = 1
	for _, id in mutations do
		local combo = comboById[id]
		if combo then
			comboMult *= combo.Value
		else
			local def = mutationById[id]
			if def then
				table.insert(bonuses, def.Value - 1)
			end
		end
	end
	table.sort(bonuses, function(a, b)
		return a > b
	end)
	local mult = 1
	for i, bonus in bonuses do
		mult *= 1 + bonus * (if i == 1 then 1 else Mutations.StackFalloff)
	end
	return math.min(mult * comboMult, Mutations.ValueCap)
end

function ItemUtil.QualityDef(tier: number?)
	return Quality.Tiers[math.clamp(tier or 1, 1, #Quality.Tiers)]
end

-- Base value of one item in this stack (before market effects).
function ItemUtil.UnitValue(stack: Stack): number
	local def = Registry.Items[stack.Id]
	if not def then
		return 0
	end
	local value = def.Value * ItemUtil.QualityDef(stack.Q).Value * ItemUtil.MutationMultiplier(stack.M)
	-- Specimens: bigger than average is worth a little more.
	if stack.S and def.Crop then
		local crop = Registry.Crops[def.Crop]
		if crop and crop.Size[1] > 0 then
			value *= math.clamp(stack.S / crop.Size[1], 1, 3)
		end
	end
	return math.floor(value + 0.5)
end

-- "Golden Giant Strawberry", "Astral Moonflower"
function ItemUtil.DisplayName(stack: Stack): string
	local def = Registry.Items[stack.Id]
	local name = if def then def.Name else stack.Id
	if not stack.M or #stack.M == 0 then
		return name
	end
	-- Prefer combos, then the most valuable mutations; show at most two words.
	local ordered = table.clone(stack.M)
	table.sort(ordered, function(a, b)
		local ca, cb = comboById[a] ~= nil, comboById[b] ~= nil
		if ca ~= cb then
			return ca
		end
		local da, db = ItemUtil.MutationDef(a), ItemUtil.MutationDef(b)
		return (da and da.Value or 0) > (db and db.Value or 0)
	end)
	local words = {}
	for i = 1, math.min(2, #ordered) do
		local m = ItemUtil.MutationDef(ordered[i])
		table.insert(words, if m then m.Name else ordered[i])
	end
	if #ordered > 2 then
		table.insert(words, "+" .. (#ordered - 2))
	end
	return table.concat(words, " ") .. " " .. name
end

function ItemUtil.Rarity(stack: Stack): string
	local def = Registry.Items[stack.Id]
	local rarity = if def then def.Rarity else "Common"
	-- Combo mutations make any item at least Legendary; any mutation at least Rare-ish bump.
	if stack.M then
		for _, id in stack.M do
			if comboById[id] then
				return if Registry.RarityOrder(rarity) >= 6 then rarity else "Legendary"
			end
		end
	end
	return rarity
end

function ItemUtil.Tradable(stack: Stack): boolean
	local def = Registry.Items[stack.Id]
	return def ~= nil and not def.NoTrade and not stack.L
end

function ItemUtil.Sellable(stack: Stack): boolean
	local def = Registry.Items[stack.Id]
	return def ~= nil and not def.NoSell and not stack.L and def.Value > 0
end

-- Sanity check a stack loaded from a save or received from anywhere.
function ItemUtil.Valid(stack: any): boolean
	if type(stack) ~= "table" or type(stack.Id) ~= "string" or not Registry.Items[stack.Id] then
		return false
	end
	if type(stack.N) ~= "number" or stack.N < 1 or stack.N ~= math.floor(stack.N) then
		return false
	end
	if stack.Q ~= nil and (type(stack.Q) ~= "number" or stack.Q < 1 or stack.Q > #Quality.Tiers) then
		return false
	end
	if stack.M ~= nil then
		if type(stack.M) ~= "table" then
			return false
		end
		for _, m in stack.M do
			if type(m) ~= "string" or not ItemUtil.MutationDef(m) then
				return false
			end
		end
	end
	if stack.G ~= nil then
		if type(stack.G) ~= "table" or #stack.G ~= 4 then
			return false
		end
		for _, g in stack.G do
			if type(g) ~= "number" or g < 0 or g > 10 then
				return false
			end
		end
	end
	return true
end

return ItemUtil

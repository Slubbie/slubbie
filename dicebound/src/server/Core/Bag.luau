-- The treasure bag. Pure logic over a player's Data table.
--
-- CAPACITY RULE: capacity counts individual items, not stacks. Three Old Copper Coins in one
-- stack use 3 slots. Items stack when they share an item id AND mutation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Dicebound.Config)

local Bag = {}

function Bag.Key(itemId: string, mutation: string?): string
	return if mutation then itemId .. "|" .. mutation else itemId
end

function Bag.Used(data): number
	local used = 0
	for _, stack in data.Bag do
		used += stack.Qty
	end
	return used
end

function Bag.Capacity(data): number
	return Config.UpgradeValue("Bag", data.Upgrades.Bag)
end

function Bag.Free(data): number
	return math.max(0, Bag.Capacity(data) - Bag.Used(data))
end

-- Adds items. Callers must check Free() first; this refuses (returns nil) rather than overfill.
function Bag.Add(data, itemId: string, mutation: string?, qty: number): string?
	if qty < 1 or Bag.Free(data) < qty or not Config.Items.ById[itemId] then
		return nil
	end
	local key = Bag.Key(itemId, mutation)
	data.Seq += 1
	local stack = data.Bag[key]
	if stack then
		stack.Qty += qty
		stack.Seq = data.Seq
	else
		data.Bag[key] = { Id = itemId, Mut = mutation, Qty = qty, Locked = false, Seq = data.Seq }
	end
	return key
end

-- Removes items from a stack. Returns false (and changes nothing) if there aren't enough.
function Bag.Remove(data, key: string, qty: number): boolean
	local stack = data.Bag[key]
	if not stack or qty < 1 or stack.Qty < qty then
		return false
	end
	stack.Qty -= qty
	if stack.Qty == 0 then
		data.Bag[key] = nil
	end
	return true
end

function Bag.SetLocked(data, key: string, locked: boolean): (boolean, string?)
	local stack = data.Bag[key]
	if not stack then
		return false, "That item isn't in your bag anymore."
	end
	stack.Locked = locked
	return true, nil
end

-- Records a discovery in the collection book. Discoveries are permanent: selling the item later
-- never removes them. Returns (newItem, newMutationVariant).
function Bag.Discover(data, itemId: string, mutation: string?, qty: number, now: number): (boolean, boolean)
	local entry = data.Discovered[itemId]
	local isNew = entry == nil
	if isNew then
		entry = { N = 0, T = now }
		data.Discovered[itemId] = entry
	end
	entry.N += qty
	local newMutation = false
	if mutation then
		local key = Bag.Key(itemId, mutation)
		newMutation = not data.MutationsFound[key]
		data.MutationsFound[key] = true
	end
	return isNew, newMutation
end

return Bag

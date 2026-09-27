-- Merchant orders: requests for specific treasure that pay more than selling it.
-- Pure logic over a Data table. Each slot is either an order or an empty slot with ReadyAt
-- (the time a new order appears there).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Dicebound.Config)
local Bag = require(script.Parent.Bag)

local Orders = {}

local O = Config.Economy.Orders

type Rng = { NextNumber: (any) -> number, NextInteger: (any, number, number) -> number }

local function pick<T>(rng: Rng, entries: { T }, weight: (T) -> number): T?
	local total = 0
	for _, e in entries do
		total += weight(e)
	end
	if total <= 0 then
		return nil
	end
	local r = rng:NextNumber() * total
	for _, e in entries do
		r -= weight(e)
		if r < 0 then
			return e
		end
	end
	return entries[#entries]
end

-- Builds a new order from the player's unlocked regions (newer regions are more likely).
function Orders.Generate(data, rng: Rng): { [string]: any }?
	local regions = {}
	for _, region in Config.Regions.List do
		if data.Regions[region.Id] and Config.IsLive(region) then
			table.insert(regions, region)
		end
	end
	local region = pick(rng, regions, function(r)
		return r.Order
	end)
	if not region then
		return nil
	end
	local rarities = {}
	for rarity, weight in O.RarityWeights do
		table.insert(rarities, { Id = rarity, Weight = weight })
	end
	table.sort(rarities, function(a, b)
		return Config.Rarities.Order(a.Id) < Config.Rarities.Order(b.Id)
	end)
	local rarity = pick(rng, rarities, function(r)
		return r.Weight
	end)
	if not rarity then
		return nil
	end
	local items = {}
	for _, item in Config.ItemsIn(region.Id, rarity.Id) do
		if not item.Special then
			table.insert(items, item)
		end
	end
	local item = pick(rng, items, function(i)
		return i.Weight
	end)
	if not item then
		return nil
	end
	local range = O.Quantity[rarity.Id]
	local qty = rng:NextInteger(range[1], range[2])

	local mutation = nil
	if rng:NextNumber() < O.MutatedChance then
		local allowed = {}
		for _, m in Config.Economy.Mutations.List do
			if m.Regions == nil or m.Regions[region.Id] then
				table.insert(allowed, m)
			end
		end
		local m = pick(rng, allowed, function(x)
			return x.Weight
		end)
		mutation = m and m.Id
		qty = 1
	end

	local mult = O.RewardMult.Min + rng:NextNumber() * (O.RewardMult.Max - O.RewardMult.Min)
	if mutation then
		mult *= O.MutatedRewardBonus
	end
	data.Orders.NextId += 1
	return {
		Id = data.Orders.NextId,
		ItemId = item.Id,
		Mut = mutation,
		Qty = qty,
		Reward = math.max(1, math.floor(Config.ItemValue(item.Id, mutation) * qty * mult)),
		Giver = region.Merchant.Name,
		ReadyAt = 0,
	}
end

-- Fills empty slots whose timer has passed. Returns true if anything changed.
function Orders.Refresh(data, rng: Rng, now: number): boolean
	local changed = false
	for i = 1, O.Slots do
		local slot = data.Orders.Slots[i]
		if slot == nil or (slot.ItemId == nil and now >= slot.ReadyAt) then
			local order = Orders.Generate(data, rng)
			if order then
				data.Orders.Slots[i] = order
				changed = true
			end
		end
	end
	return changed
end

-- Hands over the requested items (unlocked only, cheapest variants first) for the reward.
function Orders.Fulfill(data, index: any, now: number): (number?, string?)
	local slot = type(index) == "number" and data.Orders.Slots[index]
	if not slot or slot.ItemId == nil then
		return nil, "That order isn't available."
	end
	local have = Bag.Available(data, slot.ItemId, slot.Mut)
	if have < slot.Qty then
		return nil, string.format("You need %d more (locked items don't count).", slot.Qty - have)
	end
	if not Bag.Take(data, slot.ItemId, slot.Mut, slot.Qty) then
		return nil, "Couldn't hand over those items."
	end
	local reward = slot.Reward
	data.Coins += reward
	data.Stats.CoinsEarned += reward
	data.Orders.Slots[index] = { ReadyAt = now + O.ReplaceDelay }
	return reward, nil
end

-- Swaps an order for a new one later. Limited by a cooldown.
function Orders.Skip(data, index: any, now: number): (boolean, string?)
	local slot = type(index) == "number" and data.Orders.Slots[index]
	if not slot or slot.ItemId == nil then
		return false, "That order isn't available."
	end
	if now < data.Orders.SkipAt then
		return false, string.format("You can skip another order in %ds.", data.Orders.SkipAt - now)
	end
	data.Orders.SkipAt = now + O.SkipCooldown
	data.Orders.Slots[index] = { ReadyAt = now + O.ReplaceDelay }
	return true, nil
end

return Orders

-- Selling and upgrade purchases. Pure logic over a player's Data table.
-- Every price comes from Config; nothing the client sends is trusted except WHICH stacks and
-- HOW MANY, and both are checked against the player's real bag.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Dicebound.Config)
local LootMath = require(ReplicatedStorage.Dicebound.LootMath)
local Bag = require(script.Parent.Bag)

local Shop = {}

Shop.MaxSelectionSize = 250

export type SaleLine = { Key: string, Id: string, Mut: string?, Qty: number, Coins: number }
export type SalePlan = { Lines: { SaleLine }, Total: number, Multiplier: number, Units: number }

-- Sell price multiplier from the Silver Tongue upgrade + equipped dice perks, capped.
function Shop.SellMultiplier(data): number
	local upgrade = Config.UpgradeValue("Sell", data.Upgrades.Sell)
	local perks = LootMath.Perks(data.Dice.Equipped)
	return math.min(1 + upgrade + perks.SellBonus, Config.Economy.MaxSellMultiplier)
end

local function needsConfirm(itemId: string): boolean
	local item = Config.Items.ById[itemId]
	local rarity = item and Config.Rarities.ById[item.Rarity]
	return rarity ~= nil and rarity.ConfirmSell == true
end

local function line(key: string, stack, qty: number, mult: number): SaleLine
	return {
		Key = key,
		Id = stack.Id,
		Mut = stack.Mut,
		Qty = qty,
		Coins = math.floor(Config.ItemValue(stack.Id, stack.Mut) * qty * mult),
	}
end

local function finish(lines: { SaleLine }, mult: number): SalePlan
	local total, units = 0, 0
	for _, l in lines do
		total += l.Coins
		units += l.Qty
	end
	return { Lines = lines, Total = total, Multiplier = mult, Units = units }
end

-- selection: { [stackKey] = quantity }. Fails as a whole if any entry is invalid, so a stale
-- or duplicated request can never sell part of what the player meant.
function Shop.PlanSale(data, selection: any, confirmHighValue: boolean): (SalePlan?, string?)
	if type(selection) ~= "table" then
		return nil, "Nothing selected."
	end
	local mult = Shop.SellMultiplier(data)
	local lines = {}
	local count = 0
	for key, qty in selection do
		count += 1
		if count > Shop.MaxSelectionSize then
			return nil, "Too many items selected."
		end
		if type(key) ~= "string" or type(qty) ~= "number" or qty % 1 ~= 0 or qty < 1 then
			return nil, "Invalid selection."
		end
		local stack = data.Bag[key]
		if not stack or stack.Qty < qty then
			return nil, "Some of those items are no longer in your bag."
		end
		if stack.Locked then
			return nil, "Locked items can't be sold. Unlock them first."
		end
		if needsConfirm(stack.Id) and not confirmHighValue then
			return nil, "CONFIRM"
		end
		table.insert(lines, line(key, stack, qty, mult))
	end
	if #lines == 0 then
		return nil, "Nothing selected."
	end
	return finish(lines, mult), nil
end

-- Every unlocked stack. Legendary-or-better stacks are included only when includeHighValue.
function Shop.PlanSellAll(data, includeHighValue: boolean): (SalePlan?, string?)
	local mult = Shop.SellMultiplier(data)
	local lines = {}
	for key, stack in data.Bag do
		if not stack.Locked and (includeHighValue or not needsConfirm(stack.Id)) then
			table.insert(lines, line(key, stack, stack.Qty, mult))
		end
	end
	if #lines == 0 then
		return nil, "Nothing to sell: every item is locked or needs confirming."
	end
	return finish(lines, mult), nil
end

-- Applies a plan made from this same data in the same server frame. Re-checks every line so it
-- can never remove more than exists or pay for anything twice.
function Shop.ApplySale(data, plan: SalePlan): number
	local earned = 0
	for _, l in plan.Lines do
		local stack = data.Bag[l.Key]
		if stack and not stack.Locked and stack.Qty >= l.Qty and Bag.Remove(data, l.Key, l.Qty) then
			earned += l.Coins
			data.Stats.Sold += l.Qty
		end
	end
	data.Coins += earned
	data.Stats.CoinsEarned += earned
	return earned
end

-- Buys the next level of an upgrade. `expectedLevel` is the level the client saw; if it doesn't
-- match, the request is a duplicate or stale and is refused, so a double-click never buys twice.
function Shop.BuyUpgrade(data, upgradeId: any, expectedLevel: any): (boolean, string?)
	local upgrade = type(upgradeId) == "string" and Config.Economy.Upgrades.ById[upgradeId]
	if not upgrade or not Config.IsLive(upgrade) then
		return false, "That upgrade doesn't exist."
	end
	local level = data.Upgrades[upgrade.Id] or 0
	if expectedLevel ~= level then
		return false, "Already purchased."
	end
	local nextLevel = upgrade.Levels[level + 2]
	if not nextLevel then
		return false, "Already at max level."
	end
	if data.Coins < nextLevel.Cost then
		return false, string.format("You need %d more coins.", nextLevel.Cost - data.Coins)
	end
	data.Coins -= nextLevel.Cost
	data.Upgrades[upgrade.Id] = level + 1
	data.Stats.Upgrades += 1
	return true, nil
end

return Shop

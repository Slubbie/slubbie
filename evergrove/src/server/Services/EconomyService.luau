-- Currencies, reward granting, NPC shops and player market stalls.
--
-- All prices are computed here on the server; the client only ever asks.
-- Shop stock is per player per day for limited items, and the traveling
-- merchant's rotation is the same for everyone on a given day.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Economy = require(Shared.Config.Economy)
local Shops = require(Shared.Config.Shops)
local Placeables = require(Shared.Config.Placeables)
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local Stats = require(Shared.Lib.Stats)
local ItemUtil = require(Shared.Lib.ItemUtil)
local Genetics = require(Shared.Lib.Genetics)
local GameTime = require(Shared.Lib.GameTime)
local CropMath = require(Shared.Lib.CropMath)
local RNG = require(Shared.Lib.RNG)
local Format = require(Shared.Lib.Format)

local S = require(script.Parent)

local EconomyService = {}

local random = Random.new()

-- Currency -----------------------------------------------------------------------------------------

function EconomyService.AddCoins(player: Player, amount: number, reason: string?)
	local profile = S.Data.Get(player)
	if not profile or amount == 0 or amount ~= amount then
		return
	end
	amount = math.floor(amount)
	profile.Coins = math.clamp(profile.Coins + amount, 0, Economy.MaxCoins)
	S.Data.Changed(player, "Coins")
	if amount > 0 then
		S.Data.AddStat(player, "CoinsEarned", amount)
		S.Notify.Coins(player, amount, reason)
	end
end

function EconomyService.Spend(player: Player, amount: number, reason: string?): boolean
	local profile = S.Data.Get(player)
	if not profile or amount < 0 or amount ~= amount then
		return false
	end
	amount = math.floor(amount)
	if profile.Coins < amount then
		return false
	end
	profile.Coins -= amount
	S.Data.Changed(player, "Coins")
	S.Data.AddStat(player, "CoinsSpent", amount)
	if amount > 0 then
		S.Notify.Coins(player, -amount, reason)
	end
	return true
end

function EconomyService.AddTokens(player: Player, amount: number)
	local profile = S.Data.Get(player)
	if not profile or amount <= 0 then
		return
	end
	profile.Tokens = math.min(profile.Tokens + math.floor(amount), Economy.MaxTokens)
	S.Data.Changed(player, "Tokens")
	S.Notify.Toast(player, "🎟️ +" .. math.floor(amount) .. " Festival Tokens", "Success")
end

function EconomyService.SpendTokens(player: Player, amount: number): boolean
	local profile = S.Data.Get(player)
	if not profile or profile.Tokens < amount then
		return false
	end
	profile.Tokens -= amount
	S.Data.Changed(player, "Tokens")
	return true
end

-- Grant a reward table: Coins, Tokens, Items {{id, n}}, XP {Skill = n}, Title,
-- Recipe, Friendship {npc = pts}, Animal, Unlocks, Cosmetic.
function EconomyService.GrantReward(player: Player, reward: { [string]: any }?, source: string?)
	local profile = S.Data.Get(player)
	if not profile or not reward then
		return
	end
	local shown = {}
	if reward.Coins and reward.Coins > 0 then
		EconomyService.AddCoins(player, reward.Coins, source)
	end
	if reward.Tokens and reward.Tokens > 0 then
		EconomyService.AddTokens(player, reward.Tokens)
	end
	for _, entry in reward.Items or {} do
		local id, count = entry[1], entry[2] or 1
		if Registry.Items[id] then
			local stack = ItemUtil.New(id, count)
			if reward.Genes and Registry.Items[id].Plants then
				stack.G = table.clone(reward.Genes)
			end
			S.Inventory.Add(player, stack, { Silent = true, Source = source })
			table.insert(shown, stack)
		end
	end
	for skill, xp in reward.XP or {} do
		S.Skill.AddXP(player, skill, xp)
	end
	if reward.Title then
		profile.Titles[reward.Title] = true
		S.Data.Changed(player, "Titles")
		S.Notify.Toast(player, "🏷️ New title: " .. reward.Title, "Success")
	end
	if reward.Recipe then
		S.Crafting.Learn(player, reward.Recipe, false)
	end
	for npcId, points in reward.Friendship or {} do
		S.Friendship.Add(player, npcId, points)
	end
	if reward.Animal then
		S.Animal.Grant(player, reward.Animal.Species, reward.Animal)
	end
	if reward.Unlocks then
		profile.Unlocks[reward.Unlocks] = true
		S.Data.Changed(player, "Unlocks")
	end
	if reward.Cosmetic then
		profile.Cosmetics.Owned[reward.Cosmetic] = true
		S.Data.Changed(player, "Cosmetics")
	end
	if #shown > 0 or (reward.Coins or 0) > 0 then
		S.Notify.Reward(player, shown, reward.Coins or 0, source)
	end
end

-- Shops ----------------------------------------------------------------------------------------------

local function dayKey(): number
	return GameTime.Info().Day
end

local function stockUsed(profile: any, shopId: string, itemId: string): number
	local bought = profile.Unlocks.Bought
	if type(bought) ~= "table" or bought.Day ~= dayKey() then
		return 0
	end
	return bought.Counts[shopId .. "|" .. itemId] or 0
end

local function useStock(player: Player, profile: any, shopId: string, itemId: string, qty: number)
	local bought = profile.Unlocks.Bought
	if type(bought) ~= "table" or bought.Day ~= dayKey() then
		bought = { Day = dayKey(), Counts = {} }
		profile.Unlocks.Bought = bought
	end
	local key = shopId .. "|" .. itemId
	bought.Counts[key] = (bought.Counts[key] or 0) + qty
	S.Data.Changed(player, "Unlocks")
end

local function isOpen(shop: any): boolean
	local info = GameTime.Info()
	if shop.Days and not table.find(shop.Days, info.Weekday) then
		return false
	end
	if shop.Hours then
		local open, close = shop.Hours[1], shop.Hours[2]
		if open <= close then
			return info.Hour >= open and info.Hour < close
		end
		return info.Hour >= open or info.Hour < close
	end
	return true
end

-- The traveling merchant's rotation for today (same for everyone).
local function rotation(shop: any): { any }
	local out = {}
	if not shop.Rotating then
		return out
	end
	local pool = shop.Rotating.Pool
	local day = math.floor(os.time() / 86400)
	local used = {}
	local attempts = 0
	while #out < shop.Rotating.Count and attempts < 100 do
		attempts += 1
		local entry = pool[1 + RNG.HashInt("rotation", shop.Id, day, attempts) % #pool]
		if not used[entry.Id] then
			used[entry.Id] = true
			table.insert(out, entry)
		end
	end
	return out
end

local function basePrice(entry: any, def: any): number
	if entry.Price then
		return entry.Price
	end
	if def.Plants then
		local crop = Registry.Crops[def.Plants]
		return crop.Seed or math.floor(crop.Sell * 2)
	end
	if def.Placeable and def.Placeable.Price then
		return def.Placeable.Price
	end
	return math.max(1, def.Value * Shops.BuyMarkup)
end

-- Every entry the shop currently offers this player, with price and lock state.
function EconomyService.ShopEntries(player: Player, shopId: string): { any }
	local profile = S.Data.Get(player)
	local shop = Registry.Shops[shopId]
	if not profile or not shop then
		return {}
	end
	local entries = table.clone(shop.Stock)
	local info = GameTime.Info()
	if shop.AllSeeds then
		local nextSeason = Stats.HasPerk(profile, "NextSeasonSeeds")
		local nextId = require(Shared.Config.Seasons)[info.Season % 4 + 1].Id
		for _, crop in Registry.ShopSeeds() do
			local inSeason = CropMath.InSeason(crop, info.SeasonId) or (nextSeason and CropMath.InSeason(crop, nextId))
			if inSeason and #crop.Sources == 0 then
				table.insert(entries, { Id = "seed_" .. crop.Id, Level = crop.Level })
			end
		end
	end
	if shop.AllDecor then
		for _, placeable in Placeables.List do
			local decorCategory = placeable.Category ~= "Building"
				and placeable.Category ~= "Machine"
				and placeable.Category ~= "Automation"
				and placeable.Category ~= "Storage"
				and placeable.Category ~= "Utility"
				and placeable.Category ~= "Trophy"
			if
				decorCategory
				and placeable.Price
				and (not placeable.Seasonal or placeable.Seasonal == info.SeasonId)
			then
				table.insert(entries, { Id = placeable.Id, Level = placeable.Level })
			end
		end
	end
	for _, entry in rotation(shop) do
		table.insert(entries, entry)
	end
	local out = {}
	local farming = Stats.SkillLevel(profile, "Farming")
	local estate = Stats.EstateLevel(profile)
	local owner = shop.Owner
	for _, entry in entries do
		local def = Registry.Items[entry.Id]
		if def then
			local price = basePrice(entry, def)
			local discount = Stats.ShopDiscount(profile, shopId, def)
			if def.Placeable then
				discount = math.max(discount, Stats.Effect(profile, "CraftCost"))
			end
			price = math.max(1, math.floor(price * (1 - discount)))
			local level = entry.Level or 1
			local haveLevel = if def.Plants then farming else estate
			local locked = nil
			if haveLevel < level then
				locked = (if def.Plants then "Farming " else "Estate ") .. "level " .. level
			elseif entry.Hearts and Stats.Hearts(profile, owner) < entry.Hearts then
				locked = entry.Hearts .. " hearts with " .. Registry.Npcs[owner].Name
			end
			local left = if entry.Stock then math.max(0, entry.Stock - stockUsed(profile, shopId, entry.Id)) else nil
			table.insert(out, {
				Id = entry.Id,
				Price = price,
				Currency = entry.Currency or "Coins",
				Locked = locked,
				Left = left,
				Mats = def.Placeable and def.Placeable.Mats,
			})
		end
	end
	return out
end

local function shopGet(player: Player, shopId: string)
	local shop = Registry.Shops[shopId]
	if not shop then
		return false, "Unknown shop"
	end
	if not S.NPC.Near(player, shop.Owner) then
		return false, "Talk to " .. Registry.Npcs[shop.Owner].Name .. " to shop"
	end
	return true,
		{
			Id = shop.Id,
			Name = shop.Name,
			Icon = shop.Icon,
			Open = isOpen(shop),
			Entries = EconomyService.ShopEntries(player, shopId),
			Buys = shop.Buys,
			Services = shop.Services,
			Hours = shop.Hours,
		}
end

local function shopBuy(player: Player, shopId: string, itemId: string, qty: number)
	local profile = S.Data.Get(player)
	local shop = Registry.Shops[shopId]
	if not profile or not shop then
		return false, "Unknown shop"
	end
	if qty < 1 or qty > 999 then
		return false, "Bad amount"
	end
	if not S.NPC.Near(player, shop.Owner) then
		return false, "Too far from the shop"
	end
	if not isOpen(shop) then
		return false, shop.Name .. " is closed right now"
	end
	local entry
	for _, e in EconomyService.ShopEntries(player, shopId) do
		if e.Id == itemId then
			entry = e
		end
	end
	if not entry then
		return false, "Not sold here"
	end
	if entry.Locked then
		return false, "Requires " .. entry.Locked
	end
	if entry.Left and qty > entry.Left then
		return false, "Only " .. entry.Left .. " left today"
	end
	local total = entry.Price * qty
	for _, mat in entry.Mats or {} do
		if S.Inventory.Count(player, mat.Id) < mat.N * qty then
			return false, "You need " .. mat.N * qty .. " " .. Registry.Items[mat.Id].Name
		end
	end
	local stack = ItemUtil.New(itemId, qty)
	if Registry.Items[itemId].Plants then
		stack.G = Genetics.ShopGenes(random)
	end
	if not S.Inventory.CanFit(player, { stack }) then
		return false, "Your bag is full"
	end
	if entry.Currency == "Tokens" then
		if not EconomyService.SpendTokens(player, total) then
			return false, "Not enough tokens"
		end
	elseif not EconomyService.Spend(player, total, shop.Name) then
		return false, "Not enough coins (" .. Format.Commas(total) .. ")"
	end
	for _, mat in entry.Mats or {} do
		S.Inventory.Remove(player, mat.Id, mat.N * qty)
	end
	if entry.Left then
		useStock(player, profile, shopId, itemId, qty)
	end
	S.Inventory.Add(player, stack, { Source = shop.Name })
	S.Data.AddStat(player, "ItemsBought", qty)
	S.Tutorial.Event(player, "Buy")
	return true
end

-- Market stalls (player to player) -------------------------------------------------------------------

local STALL = Economy.Selling.Stall

local function hasStall(profile: any): string?
	for uid, placed in profile.Farm.Placed do
		if placed.Id == "market_stall" then
			return uid
		end
	end
	return nil
end

local function stallSet(player: Player, slot: number, ref: string, count: number, price: number)
	local profile = S.Data.Get(player)
	if not profile then
		return false, "Not ready"
	end
	if not hasStall(profile) then
		return false, "Place a Market Stall on your farm first"
	end
	if slot < 1 or slot > STALL.Slots then
		return false, "Bad slot"
	end
	local key = tostring(slot)
	if profile.Stall[key] then
		return false, "That shelf is taken"
	end
	local stack = S.Inventory.Slot(player, ref)
	if not stack or not ItemUtil.Tradable(stack) or not ItemUtil.Sellable(stack) then
		return false, "You can't sell that"
	end
	local value = ItemUtil.UnitValue(stack)
	if price < math.floor(value * STALL.MinPrice) or price > math.ceil(value * STALL.MaxPrice) then
		return false,
			string.format(
				"Price must be between %d and %d",
				math.floor(value * STALL.MinPrice),
				math.ceil(value * STALL.MaxPrice)
			)
	end
	local taken = S.Inventory.TakeFromSlot(player, ref, count)
	if not taken then
		return false, "Can't take that"
	end
	profile.Stall[key] = { Stack = taken, Price = price }
	S.Data.Changed(player, "Stall")
	return true
end

local function stallClear(player: Player, slot: number)
	local profile = S.Data.Get(player)
	local key = tostring(slot)
	local listing = profile and profile.Stall[key]
	if not listing then
		return false, "Empty shelf"
	end
	profile.Stall[key] = nil
	S.Data.Changed(player, "Stall")
	S.Inventory.Add(player, listing.Stack, { Silent = true })
	return true
end

local function stallGet(player: Player, ownerUserId: number)
	local owner = Players:GetPlayerByUserId(ownerUserId)
	local profile = owner and S.Data.Get(owner)
	if not owner or not profile then
		return false, "That farmer isn't here"
	end
	if owner ~= player and not S.Permission.Allows(owner, player, "View") then
		return false, "You're not allowed on that farm"
	end
	local out = {}
	for key, listing in profile.Stall do
		out[key] = { Stack = listing.Stack, Price = listing.Price }
	end
	return true, { Owner = owner.DisplayName, Listings = out }
end

local function stallBuy(player: Player, ownerUserId: number, slot: number, qty: number)
	local owner = Players:GetPlayerByUserId(ownerUserId)
	local ownerProfile = owner and S.Data.Get(owner)
	local buyerProfile = S.Data.Get(player)
	if not owner or not ownerProfile or not buyerProfile or owner == player then
		return false, "Not available"
	end
	local stallUid = hasStall(ownerProfile)
	local stallPos = stallUid and S.Building.WorldPosition(owner, stallUid)
	if not stallPos or not S.Security.InReach(player, stallPos, 24) then
		return false, "Walk up to the stall"
	end
	local key = tostring(slot)
	local listing = ownerProfile.Stall[key]
	if not listing or qty < 1 or qty > listing.Stack.N then
		return false, "Not available"
	end
	local total = listing.Price * qty
	local bought = ItemUtil.Split(listing.Stack, qty)
	if not S.Inventory.CanFit(player, { bought }) then
		return false, "Your bag is full"
	end
	if not EconomyService.Spend(player, total, "Stall purchase") then
		return false, "Not enough coins"
	end
	listing.Stack.N -= qty
	if listing.Stack.N <= 0 then
		ownerProfile.Stall[key] = nil
	end
	S.Data.Changed(owner, "Stall")
	local fee = math.clamp(STALL.Fee * (1 - Stats.Effect(ownerProfile, "StallFee")), 0, 1)
	EconomyService.AddCoins(owner, math.floor(total * (1 - fee)), "Stall sale")
	S.Inventory.Add(player, bought, { Source = owner.DisplayName .. "'s stall" })
	S.Data.AddStat(owner, "StallSales", qty)
	S.Notify.Toast(
		owner,
		player.DisplayName .. " bought " .. qty .. "× " .. ItemUtil.DisplayName(bought) .. " from your stall!",
		"Success"
	)
	-- Both sides changed hands: save both promptly.
	task.spawn(S.Data.SaveNow, owner)
	task.spawn(S.Data.SaveNow, player)
	return true
end

function EconomyService.Init()
	Net.Handle("ShopGet", shopGet)
	Net.Handle("ShopBuy", shopBuy)
	Net.Handle("StallSet", stallSet)
	Net.Handle("StallClear", stallClear)
	Net.Handle("StallGet", stallGet)
	Net.Handle("StallBuy", stallBuy)
end

function EconomyService.IsOpen(shopId: string): boolean
	local shop = Registry.Shops[shopId]
	return shop ~= nil and isOpen(shop)
end

return EconomyService

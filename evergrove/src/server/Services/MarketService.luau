-- Market prices and every way to sell: the shipping bin, merchants, bulk
-- contracts (incl. collector and restaurant orders) and overseas exports.
--
-- Prices = item value (quality, mutations) × market factor (Lib/MarketMath)
--          × the seller's skills/perks × venue.
-- Supply pressure rises as items are sold and recovers over time. With
-- Economy.Market.Supply.CrossServer, pressure is shared through a MemoryStore
-- so a flood of pumpkins on one server nudges pumpkin prices everywhere.

local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Economy = require(Shared.Config.Economy)
local Shops = require(Shared.Config.Shops)
local Festivals = require(Shared.Config.Festivals)
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local Stats = require(Shared.Lib.Stats)
local ItemUtil = require(Shared.Lib.ItemUtil)
local MarketMath = require(Shared.Lib.MarketMath)
local GameTime = require(Shared.Lib.GameTime)
local RNG = require(Shared.Lib.RNG)
local CropMath = require(Shared.Lib.CropMath)
local Format = require(Shared.Lib.Format)

local S = require(script.Parent)

local SELL = Economy.Selling
local SUPPLY = Economy.Market.Supply
local CONTRACTS = Economy.Contracts

local MarketService = {}

local random = Random.new()
local pressure: { [string]: number } = {}
local pendingDelta: { [string]: number } = {}
local lastDecay = GameTime.Now()

local supplyMap: MemoryStoreSortedMap? = nil
if SUPPLY.CrossServer then
	local ok, map = pcall(function()
		return MemoryStoreService:GetSortedMap("EvergroveSupply")
	end)
	if ok then
		supplyMap = map
	end
end

-- Prices ------------------------------------------------------------------------------------------

local function eventMultiplier(): number
	local nm = Festivals.NightMarket
	local info = GameTime.Info()
	if info.Weekday == nm.Weekday and info.Hour >= nm.Hours[1] and info.Hour < nm.Hours[2] then
		return 1 + nm.SellBonus
	end
	return 1
end

-- Skill/perk multiplier for what this player sells.
local function sellerBonus(profile: any, def: any): number
	local bonus = Stats.Effect(profile, "SellBonus")
	if def.Category == "Fish" or def.Tags.Smoked then
		bonus += Stats.Effect(profile, "FishValue")
	end
	if def.Category == "AnimalProduct" or def.Tags.Dairy then
		bonus += Stats.Effect(profile, "AnimalValue")
	end
	if def.Tags.Artisan then
		bonus += Stats.Effect(profile, "ArtisanValue")
	end
	if def.Tags.Cooked then
		bonus += Stats.Effect(profile, "DishValue")
	end
	return 1 + bonus
end

function MarketService.Factor(itemId: string): number
	return MarketMath.Factor(itemId, {
		Time = GameTime.Now(),
		Weather = S.Weather.Current(),
		Pressure = pressure[itemId] or 0,
		Event = eventMultiplier(),
	})
end

-- Unit price for this player selling this stack at a venue multiplier.
function MarketService.UnitPrice(player: Player, stack: ItemUtil.Stack, venueMult: number?): number
	local profile = S.Data.Get(player)
	local def = Registry.Items[stack.Id]
	if not profile or not def then
		return 0
	end
	local price = ItemUtil.UnitValue(stack) * MarketService.Factor(stack.Id) * sellerBonus(profile, def) * (venueMult or 1)
	return math.max(1, math.floor(price))
end

local function addPressure(itemId: string, value: number)
	local p = value * SUPPLY.PressurePerValue
	pressure[itemId] = math.min(SUPPLY.MaxDrop, (pressure[itemId] or 0) + p)
	pendingDelta[itemId] = (pendingDelta[itemId] or 0) + p
end

-- Venue multiplier for selling to a shop's owner.
local function shopMultiplier(shopId: string?, def: any): number
	local shop = shopId and Registry.Shops[shopId]
	if not shop or not shop.Buys then
		return Shops.OffListSell
	end
	local best = nil
	for tag, mult in shop.Buys do
		if def.Tags[tag] then
			best = math.max(best or 0, mult)
		end
	end
	return best or Shops.OffListSell
end

-- Selling ----------------------------------------------------------------------------------------------

local function recordSale(player: Player, stack: ItemUtil.Stack, total: number)
	S.Data.AddStat(player, "ItemsSold", stack.N)
	S.Data.MaxStat(player, "HighestSale", math.floor(total / math.max(stack.N, 1)))
	S.Quest.Progress(player, "Sell", stack.Id, total)
	S.Skill.AddXP(player, "Trading", math.max(1, math.floor(total / 40)))
	addPressure(stack.Id, total)
end

local function binPosition(player: Player): Vector3?
	local farm = S.Farm.Get(player)
	return farm and farm.Lot.Bin
end

-- Sell `count` from a slot. venue: "Bin" | "Merchant:<npcId>"
local function sell(player: Player, ref: string, count: number, venue: string): (boolean, any)
	local profile = S.Data.Get(player)
	local stack = S.Inventory.Slot(player, ref)
	if not profile or not stack then
		return false, "Nothing there"
	end
	if not ItemUtil.Sellable(stack) then
		return false, if stack.L then "Unlock it first" else "That can't be sold"
	end
	count = math.clamp(count, 1, stack.N)
	local def = Registry.Items[stack.Id]
	if venue == "Bin" then
		local pos = binPosition(player)
		if not pos or not S.Security.InReach(player, pos, 16) then
			return false, "Walk up to your shipping bin"
		end
		local binCount = 0
		for _, s in profile.Farm.Bin do
			binCount += s.N
		end
		if binCount + count > SELL.Bin.Capacity then
			return false, "The bin is full until morning"
		end
		local taken = S.Inventory.TakeFromSlot(player, ref, count)
		if not taken then
			return false, "Can't take that"
		end
		table.insert(profile.Farm.Bin, taken)
		profile.Farm.BinAt = GameTime.Now()
		S.Data.Changed(player, "Farm", "Bin")
		S.Tutorial.Event(player, "Sell")
		return true, { Pending = true, Estimate = MarketService.UnitPrice(player, taken) * taken.N }
	end
	local npcId = string.match(venue, "^Merchant:(.+)$")
	local npc = npcId and Registry.Npcs[npcId]
	if not npc or not npc.Shop then
		return false, "Nobody to sell to"
	end
	if not S.NPC.Near(player, npcId) then
		return false, "Talk to " .. npc.Name .. " to sell"
	end
	local mult = shopMultiplier(npc.Shop, def) * (1 - SELL.Merchant.Spread)
	if count >= SELL.Bulk.Threshold then
		mult *= 1 + SELL.Bulk.Bonus + Stats.Effect(profile, "BulkBonus")
	end
	local unit = MarketService.UnitPrice(player, stack, mult)
	local taken = S.Inventory.TakeFromSlot(player, ref, count)
	if not taken then
		return false, "Can't take that"
	end
	local total = unit * taken.N
	S.Economy.AddCoins(player, total, "Sold to " .. npc.Name)
	recordSale(player, taken, total)
	S.Tutorial.Event(player, "Sell")
	return true, { Total = total, Unit = unit }
end

local function sellMany(player: Player, refs: { any }, venue: string)
	local total = 0
	local sold = 0
	for _, ref in refs do
		if type(ref) == "string" then
			local stack = S.Inventory.Slot(player, ref)
			if stack then
				local ok, result = sell(player, ref, stack.N, venue)
				if ok then
					sold += 1
					total += if type(result) == "table" then (result.Total or result.Estimate or 0) else 0
				end
			end
		end
	end
	return sold > 0, { Sold = sold, Total = total }
end

-- Shipping bin payout (every morning, and on login for bins left overnight).
local function payBin(player: Player)
	local profile = S.Data.Get(player)
	if not profile or #profile.Farm.Bin == 0 then
		return
	end
	local total, count = 0, 0
	for _, stack in profile.Farm.Bin do
		local unit = MarketService.UnitPrice(player, stack, 1 + SELL.Bin.Bonus)
		local value = unit * stack.N
		total += value
		count += stack.N
		recordSale(player, stack, value)
		S.Data.AddStat(player, "ItemsShipped", stack.N)
		S.Quest.Progress(player, "Ship", stack.Id, stack.N)
	end
	profile.Farm.Bin = {}
	profile.Farm.BinAt = nil
	S.Data.Changed(player, "Farm", "Bin")
	S.Economy.AddCoins(player, total, "Shipping")
	S.Notify.Banner(player, "📦 Shipping paid", string.format("%s items sold for %s coins", Format.Commas(count), Format.Commas(total)), "Coins")
end

-- Contracts -------------------------------------------------------------------------------------------------

local NPC_FOR = { Crop = "pip", Artisan = "marco", Fish = "finn", AnimalProduct = "hattie", Forage = "rook", Mineral = "bram", Gem = "bram", Flower = "ivy" }

local function contractCandidates(player: Player): { string }
	local info = GameTime.Info()
	local out = {}
	local profile = S.Data.Get(player)
	local farming = if profile then Stats.SkillLevel(profile, "Farming") else 1
	for _, crop in Registry.Crops do
		if crop.Seed and CropMath.InSeason(crop, info.SeasonId) and crop.Level <= farming + 2 then
			table.insert(out, crop.Id)
		end
	end
	for _, id in { "egg", "milk", "wool", "cheese", "mayonnaise", "cloth", "honey", "flour", "copper_bar", "iron_bar", "sea_bass", "river_perch", "glacier_salmon", "jam_strawberry", "pale_ale" } do
		if Registry.Items[id] then
			table.insert(out, id)
		end
	end
	return out
end

local function makeContract(player: Player, seed: number, kind: string): any?
	local candidates = contractCandidates(player)
	local itemId = candidates[1 + seed % #candidates]
	local def = Registry.Items[itemId]
	if not def then
		return nil
	end
	local lo, hi = CONTRACTS.SizeRange[1], CONTRACTS.SizeRange[2]
	local count = lo + (seed // 7) % (hi - lo + 1)
	count = math.max(3, math.floor(count * math.clamp(60 / math.max(def.Value, 1), 0.2, 1.5)))
	local payLo, payHi = CONTRACTS.PayMultiplier[1], CONTRACTS.PayMultiplier[2]
	local quality = nil
	local mutation = nil
	if kind == "Collector" then
		payLo, payHi = CONTRACTS.Collector.PayMultiplier[1], CONTRACTS.Collector.PayMultiplier[2]
		count = math.max(1, math.floor(count / 6))
		quality = 4
	elseif kind == "Restaurant" then
		payLo, payHi = CONTRACTS.Restaurant.PayMultiplier[1], CONTRACTS.Restaurant.PayMultiplier[2]
		local dishes = Registry.WithTag("Cooked")
		def = dishes[1 + seed % #dishes]
		itemId = def.Id
		count = 1 + seed % 3
	end
	local mult = payLo + ((seed % 1000) / 1000) * (payHi - payLo)
	local pay = math.floor(def.Value * count * mult * (if quality then 2.1 else 1))
	return {
		Id = RNG.Uid("c"),
		Kind = kind,
		Npc = if kind == "Collector" then "beatrix" elseif kind == "Restaurant" then "marco" else (NPC_FOR[def.Category] or "mayor"),
		Item = itemId,
		Count = count,
		Quality = quality,
		Mutation = mutation,
		Pay = pay,
		Expires = GameTime.Now() + CONTRACTS.DurationDays * GameTime.DAY,
	}
end

local function refreshBoard(player: Player)
	local profile = S.Data.Get(player)
	if not profile then
		return
	end
	local day = GameTime.Info().Day
	local contracts = profile.Contracts
	if contracts.Day == day then
		return
	end
	contracts.Day = day
	contracts.Board = {}
	local seedBase = RNG.HashInt("contracts", player.UserId, day)
	for i = 1, CONTRACTS.Count do
		local c = makeContract(player, RNG.HashInt(seedBase, i), "Standard")
		if c then
			table.insert(contracts.Board, c)
		end
	end
	if Stats.HasPerk(profile, "CollectorContracts") or profile.Unlocks.CollectorContracts then
		for i = 1, CONTRACTS.Collector.Count do
			local c = makeContract(player, RNG.HashInt(seedBase, "col", i), "Collector")
			if c then
				table.insert(contracts.Board, c)
			end
		end
	end
	if profile.Recipes and next(profile.Recipes) then
		for i = 1, CONTRACTS.Restaurant.Count do
			local c = makeContract(player, RNG.HashInt(seedBase, "res", i), "Restaurant")
			if c then
				table.insert(contracts.Board, c)
			end
		end
	end
	-- Expire old active contracts.
	local now = GameTime.Now()
	for i = #contracts.Active, 1, -1 do
		if contracts.Active[i].Expires < now then
			table.remove(contracts.Active, i)
		end
	end
	S.Data.Changed(player, "Contracts")
end

function MarketService.ContractBoard(player: Player)
	refreshBoard(player)
	local profile = S.Data.Get(player)
	return if profile then profile.Contracts else nil
end

local function accept(player: Player, contractId: string)
	local profile = S.Data.Get(player)
	if not profile then
		return false, "Not ready"
	end
	refreshBoard(player)
	if #profile.Contracts.Active >= CONTRACTS.MaxActive then
		return false, "You can take " .. CONTRACTS.MaxActive .. " contracts at a time"
	end
	for i, contract in profile.Contracts.Board do
		if contract.Id == contractId then
			table.remove(profile.Contracts.Board, i)
			table.insert(profile.Contracts.Active, contract)
			S.Data.Changed(player, "Contracts")
			return true
		end
	end
	return false, "That contract is gone"
end

local function deliver(player: Player, contractId: string)
	local profile = S.Data.Get(player)
	if not profile then
		return false, "Not ready"
	end
	for i, contract in profile.Contracts.Active do
		if contract.Id == contractId then
			if contract.Expires < GameTime.Now() then
				table.remove(profile.Contracts.Active, i)
				S.Data.Changed(player, "Contracts")
				return false, "That contract expired"
			end
			if not S.NPC.Near(player, contract.Npc) then
				return false, "Deliver it to " .. Registry.Npcs[contract.Npc].Name
			end
			if not S.Inventory.Remove(player, contract.Item, contract.Count, contract.Quality) then
				return false, "You need " .. contract.Count .. " " .. Registry.Items[contract.Item].Name .. (if contract.Quality then " (Pristine+)" else "")
			end
			table.remove(profile.Contracts.Active, i)
			S.Data.Changed(player, "Contracts")
			local bonus = 1 + Stats.Effect(profile, "ContractBonus")
			if contract.Kind == "Restaurant" then
				bonus += Stats.Effect(profile, "OrderPay")
				for _, effect in Stats.Perks(profile) do
					bonus += effect.OrderBonus or 0
				end
			end
			local pay = math.floor(contract.Pay * bonus)
			S.Economy.AddCoins(player, pay, "Contract")
			S.Friendship.Add(player, contract.Npc, 30)
			S.Data.AddStat(player, "ContractsDone")
			S.Skill.AddXP(player, "Trading", math.floor(pay / 25))
			return true, pay
		end
	end
	return false, "Not an active contract"
end

-- Exports -------------------------------------------------------------------------------------------------------

local EXPORT = SELL.Export

local function exportShip(player: Player, refs: { any })
	local profile = S.Data.Get(player)
	if not profile then
		return false, "Not ready"
	end
	if not S.NPC.Near(player, "wendell") then
		return false, "Ship from the harbour with Old Wendell"
	end
	if #profile.Exports >= EXPORT.MaxActive then
		return false, "The boat can carry " .. EXPORT.MaxActive .. " shipments at a time"
	end
	local stacks = {}
	local value = 0
	local preferred = 0
	for _, ref in refs do
		if type(ref) == "string" then
			local stack = S.Inventory.Slot(player, ref)
			if stack and ItemUtil.Sellable(stack) then
				local unit = MarketService.UnitPrice(player, stack)
				value += unit * stack.N
				local def = Registry.Items[stack.Id]
				for tag, bonus in EXPORT.PreferredTags do
					if def.Tags[tag] then
						preferred += unit * stack.N * bonus
					end
				end
				table.insert(stacks, ref)
			end
		end
	end
	if value < EXPORT.MinValue then
		return false, "Exports need at least " .. EXPORT.MinValue .. " coins of goods"
	end
	local items = {}
	for _, ref in stacks do
		local taken = S.Inventory.TakeFromSlot(player, ref)
		if taken then
			table.insert(items, taken)
		end
	end
	local premium = math.min(EXPORT.MaxPremium, EXPORT.Premium + math.floor(value / 10000) * EXPORT.BulkPremiumPer10k)
	premium += Stats.Effect(profile, "ExportBonus")
	for _, effect in Stats.Perks(profile) do
		premium += effect.ExportBonus or 0
	end
	local payout = math.floor(value * (1 + premium) + preferred)
	local days = EXPORT.DeliveryDays
	local delayed = random:NextNumber() < EXPORT.StormDelayChance * (if S.Weather.Def().Hazard then 2 else 1)
	if delayed then
		days += 1
	end
	table.insert(profile.Exports, { Value = value, Payout = payout, Due = GameTime.Now() + days * GameTime.DAY, Delayed = delayed, Count = #items })
	S.Data.Changed(player, "Exports")
	S.Data.AddStat(player, "ExportsShipped")
	S.Quest.Progress(player, "Export", "*", value)
	for _, stack in items do
		addPressure(stack.Id, MarketService.UnitPrice(player, stack) * stack.N * 0.5)
	end
	return true, { Payout = payout, Days = days, Delayed = delayed }
end

local function payExports(player: Player)
	local profile = S.Data.Get(player)
	if not profile or #profile.Exports == 0 then
		return
	end
	local now = GameTime.Now()
	for i = #profile.Exports, 1, -1 do
		local export = profile.Exports[i]
		if export.Due <= now then
			table.remove(profile.Exports, i)
			S.Mail.Send(player, {
				From = "Old Wendell",
				Subject = "Your shipment arrived!",
				Body = string.format("The buyers overseas paid %s coins for your goods.%s Fair winds!", Format.Commas(export.Payout), if export.Delayed then " Sorry about the storm delay." else ""),
				Coins = export.Payout,
			})
		end
	end
	S.Data.Changed(player, "Exports")
end

-- Supply decay & cross-server sync ---------------------------------------------------------------------------

local function decay()
	local now = GameTime.Now()
	local hours = (now - lastDecay) / GameTime.HOUR
	lastDecay = now
	if hours <= 0 then
		return
	end
	local factor = (1 - SUPPLY.RecoveryPerHour) ^ hours
	for id, p in pressure do
		local value = p * factor
		pressure[id] = if value < 0.001 then nil else value
	end
end

local function sync()
	if not supplyMap then
		return
	end
	local deltas = pendingDelta
	pendingDelta = {}
	for itemId, delta in deltas do
		pcall(function()
			(supplyMap :: MemoryStoreSortedMap):UpdateAsync(itemId, function(old)
				local p = 0
				local t = os.time()
				if type(old) == "table" then
					local hours = (t - (old.T or t)) / (GameTime.HOUR)
					p = (old.P or 0) * (1 - SUPPLY.RecoveryPerHour) ^ math.max(0, hours)
				end
				p = math.min(SUPPLY.MaxDrop, p + delta)
				pressure[itemId] = math.max(pressure[itemId] or 0, p)
				return { P = p, T = t }
			end, 6 * 3600)
		end)
	end
	pcall(function()
		local items = (supplyMap :: MemoryStoreSortedMap):GetRangeAsync(Enum.SortDirection.Ascending, 200)
		local t = os.time()
		for _, entry in items do
			local v = entry.value
			if type(v) == "table" and type(v.P) == "number" then
				local hours = (t - (v.T or t)) / GameTime.HOUR
				local p = v.P * (1 - SUPPLY.RecoveryPerHour) ^ math.max(0, hours)
				pressure[entry.key] = math.max(pressure[entry.key] or 0, math.min(SUPPLY.MaxDrop, p))
			end
		end
	end)
end

-- Market screen data ------------------------------------------------------------------------------------------

local function marketGet(player: Player)
	local profile = S.Data.Get(player)
	if not profile then
		return false, "Not ready"
	end
	local info = GameTime.Info()
	local relevant = {}
	for _, id in MarketMath.HotItems(info.Day) do
		relevant[id] = true
	end
	local shortage = MarketMath.Shortage(info.Day)
	if shortage then
		relevant[shortage] = true
	end
	for _, stack in profile.Inventory.Slots do
		relevant[stack.Id] = true
	end
	for _, id in profile.Contracts.Tracked or {} do
		relevant[id] = true
	end
	local out = {}
	for id in relevant do
		out[id] = pressure[id] or 0
	end
	return true, {
		Pressure = out,
		Event = eventMultiplier(),
		Weather = S.Weather.Current(),
		Tracked = profile.Contracts.Tracked or {},
		Insight = Stats.Effect(profile, "MarketInsight") > 0,
		SellerBonus = Stats.Effect(profile, "SellBonus"),
	}
end

local function track(player: Player, itemId: string, on: boolean)
	local profile = S.Data.Get(player)
	if not profile or not Registry.Items[itemId] then
		return false, "Unknown item"
	end
	profile.Contracts.Tracked = profile.Contracts.Tracked or {}
	local list = profile.Contracts.Tracked
	local index = table.find(list, itemId)
	if on and not index then
		if #list >= 12 then
			table.remove(list, 1)
		end
		table.insert(list, itemId)
	elseif not on and index then
		table.remove(list, index)
	end
	S.Data.Changed(player, "Contracts")
	return true
end

function MarketService.Init()
	Net.Handle("Sell", sell)
	Net.Handle("SellMany", sellMany)
	Net.Handle("MarketGet", marketGet)
	Net.Handle("MarketTrack", track)
	Net.Handle("ContractList", function(player)
		return true, MarketService.ContractBoard(player)
	end)
	Net.Handle("ContractAccept", accept)
	Net.Handle("ContractDeliver", deliver)
	Net.Handle("ExportShip", exportShip)
end

function MarketService.Start()
	S.Time.Hour:Connect(decay)
	S.Time.Dawn:Connect(function()
		for player in S.Data.All() do
			payBin(player)
			refreshBoard(player)
		end
	end)
	S.Time.NewDay:Connect(function()
		for player in S.Data.All() do
			payExports(player)
		end
	end)
	S.Data.Loaded:Connect(function(player, profile)
		-- A bin filled before a morning you missed gets paid now.
		if profile.Farm.BinAt and #profile.Farm.Bin > 0 then
			local hoursSince = (GameTime.Now() - profile.Farm.BinAt) / GameTime.HOUR
			if hoursSince >= 24 or GameTime.Info(profile.Farm.BinAt).Day ~= GameTime.Info().Day then
				payBin(player)
			end
		end
		payExports(player)
		refreshBoard(player)
	end)
	task.spawn(function()
		while true do
			task.wait(SUPPLY.SyncSeconds)
			sync()
		end
	end)
end

return MarketService

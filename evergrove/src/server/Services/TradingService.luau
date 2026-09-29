-- Player-to-player trading.
--
-- Flow: TradeRequest(userId) → the other player accepts with TradeRespond →
-- both add items (TradeOffer slot, count) and coins (TradeCoins) → both press
-- TradeConfirm. Any change un-confirms both sides and restarts a short
-- countdown (Social.Trading.ConfirmDelay) so nobody can swap an item at the
-- last second. On the final confirm the server re-validates everything
-- (items still in the same slots, coins still there, both bags have room),
-- then swaps atomically and saves both players immediately.
--
-- Offers reference slots, not copies: items stay in the owner's bag until the
-- swap, so a crash mid-trade can never duplicate or lose anything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Social = require(Shared.Config.Social)
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local ItemUtil = require(Shared.Lib.ItemUtil)

local S = require(script.Parent)

local CFG = Social.Trading
local REQUEST_TIMEOUT = 30

local TradingService = {}

type Offer = { Items: { { Ref: string, Id: string, N: number, Key: string } }, Coins: number, Ready: boolean }
type Trade = { A: Player, B: Player, Offers: { [Player]: Offer }, Changed: number, Id: number }

local trades: { [Player]: Trade } = {}
local requests: { [Player]: { [Player]: number } } = {} -- target → requester → time
local cooldown: { [Player]: number } = {}
local nextId = 0

local function other(trade: Trade, player: Player): Player
	return if trade.A == player then trade.B else trade.A
end

-- What each side sees (their own and the other's offer, with item snapshots).
local function view(trade: Trade, player: Player): any
	local function describe(p: Player)
		local offer = trade.Offers[p]
		local items = {}
		for i, entry in offer.Items do
			local stack = S.Inventory.Slot(p, entry.Ref)
			items[i] = if stack
				then { Id = stack.Id, N = entry.N, Q = stack.Q, M = stack.M, S = stack.S, G = stack.G }
				else { Id = entry.Id, N = 0 }
		end
		return { Name = p.DisplayName, UserId = p.UserId, Items = items, Coins = offer.Coins, Ready = offer.Ready }
	end
	local wait = math.max(0, CFG.ConfirmDelay - (os.clock() - trade.Changed))
	return { Id = trade.Id, Me = describe(player), Them = describe(other(trade, player)), ConfirmIn = wait }
end

local function push(trade: Trade)
	for _, p in { trade.A, trade.B } do
		if p.Parent then
			Net.Fire(p, "Trade", view(trade, p))
		end
	end
end

local function close(trade: Trade, reason: string)
	for _, p in { trade.A, trade.B } do
		if trades[p] == trade then
			trades[p] = nil
		end
		if p.Parent then
			Net.Fire(p, "Trade", { Closed = true, Reason = reason })
		end
	end
end

local function touched(trade: Trade)
	trade.Changed = os.clock()
	for _, offer in trade.Offers do
		offer.Ready = false
	end
	push(trade)
end

local function near(a: Player, b: Player): boolean
	local pa = S.Security.RootPosition(a)
	local pb = S.Security.RootPosition(b)
	return pa ~= nil and pb ~= nil and (pa - pb).Magnitude <= CFG.Distance
end

-- Requests ---------------------------------------------------------------------------------------------------------

local function request(player: Player, userId: number)
	local target = Players:GetPlayerByUserId(userId)
	if not target or target == player then
		return false, "Nobody to trade with"
	end
	if trades[player] or trades[target] then
		return false, "Someone is already trading"
	end
	if (cooldown[player] or 0) > os.clock() then
		return false, "Wait a moment before trading again"
	end
	if not near(player, target) then
		return false, "Stand closer to trade"
	end
	requests[target] = requests[target] or {}
	requests[target][player] = os.clock()
	Net.Fire(target, "Trade", { Request = true, From = player.UserId, Name = player.DisplayName })
	return true
end

local function respond(player: Player, userId: number, accept: boolean)
	local requester = Players:GetPlayerByUserId(userId)
	local pending = requests[player]
	local at = requester and pending and pending[requester]
	if not requester or not at or os.clock() - at > REQUEST_TIMEOUT then
		return false, "That request expired"
	end
	pending[requester] = nil
	if not accept then
		Net.Fire(requester, "Trade", { Declined = true, Name = player.DisplayName })
		return true
	end
	if trades[player] or trades[requester] then
		return false, "Someone is already trading"
	end
	if not near(player, requester) then
		return false, "Stand closer to trade"
	end
	nextId += 1
	local trade: Trade = {
		A = requester,
		B = player,
		Offers = {
			[requester] = { Items = {}, Coins = 0, Ready = false },
			[player] = { Items = {}, Coins = 0, Ready = false },
		},
		Changed = os.clock(),
		Id = nextId,
	}
	trades[requester] = trade
	trades[player] = trade
	push(trade)
	return true
end

-- Offers --------------------------------------------------------------------------------------------------------------

local function offerItem(player: Player, ref: string, count: number)
	local trade = trades[player]
	if not trade then
		return false, "You're not trading"
	end
	if string.sub(ref, 1, 4) ~= "inv:" then
		return false, "Offer items from your bag"
	end
	local stack = S.Inventory.Slot(player, ref)
	if not stack then
		return false, "Nothing there"
	end
	if not ItemUtil.Tradable(stack) or (Registry.Items[stack.Id] and Registry.Items[stack.Id].Tool) then
		return false, "That can't be traded"
	end
	local offer = trade.Offers[player]
	count = math.clamp(count, 1, stack.N)
	for _, entry in offer.Items do
		if entry.Ref == ref then
			entry.N = count
			touched(trade)
			return true
		end
	end
	if #offer.Items >= CFG.MaxSlots then
		return false, "The trade window is full"
	end
	table.insert(offer.Items, { Ref = ref, Id = stack.Id, N = count, Key = ItemUtil.Key(stack) })
	touched(trade)
	return true
end

local function removeItem(player: Player, index: number)
	local trade = trades[player]
	if not trade then
		return false, "You're not trading"
	end
	local offer = trade.Offers[player]
	if not offer.Items[index] then
		return false, "Nothing there"
	end
	table.remove(offer.Items, index)
	touched(trade)
	return true
end

local function offerCoins(player: Player, amount: number)
	local trade = trades[player]
	local profile = S.Data.Get(player)
	if not trade or not profile then
		return false, "You're not trading"
	end
	amount = math.clamp(amount, 0, math.min(CFG.MaxCoins, profile.Coins))
	trade.Offers[player].Coins = amount
	touched(trade)
	return true
end

-- Completing -----------------------------------------------------------------------------------------------------------

-- Re-check an offer against the live inventory; returns the stacks to move.
local function collect(player: Player, offer: Offer): ({ any }?, string?)
	local profile = S.Data.Get(player)
	if not profile then
		return nil, "Not ready"
	end
	if profile.Coins < offer.Coins then
		return nil, player.DisplayName .. " no longer has those coins"
	end
	local stacks = {}
	for _, entry in offer.Items do
		local stack = S.Inventory.Slot(player, entry.Ref)
		if
			not stack
			or stack.Id ~= entry.Id
			or ItemUtil.Key(stack) ~= entry.Key
			or stack.N < entry.N
			or not ItemUtil.Tradable(stack)
		then
			return nil, "An offered item changed"
		end
		table.insert(stacks, ItemUtil.Split(stack, entry.N))
	end
	return stacks, nil
end

local function execute(trade: Trade): (boolean, string?)
	local a, b = trade.A, trade.B
	if not near(a, b) then
		return false, "You moved too far apart"
	end
	local fromA, whyA = collect(a, trade.Offers[a])
	local fromB, whyB = collect(b, trade.Offers[b])
	if not fromA or not fromB then
		return false, whyA or whyB
	end
	-- Room check on the other side (ignoring the slots each side frees up; being strict is safe).
	if #fromB > 0 and not S.Inventory.CanFit(a, fromB) then
		return false, a.DisplayName .. "'s bag is too full"
	end
	if #fromA > 0 and not S.Inventory.CanFit(b, fromA) then
		return false, b.DisplayName .. "'s bag is too full"
	end
	-- Take everything first, then give. Nothing yields in between.
	local takenA, takenB = {}, {}
	for _, entry in trade.Offers[a].Items do
		table.insert(takenA, S.Inventory.TakeFromSlot(a, entry.Ref, entry.N))
	end
	for _, entry in trade.Offers[b].Items do
		table.insert(takenB, S.Inventory.TakeFromSlot(b, entry.Ref, entry.N))
	end
	local coinsA, coinsB = trade.Offers[a].Coins, trade.Offers[b].Coins
	if coinsA > 0 then
		S.Economy.Spend(a, coinsA, "Trade")
		S.Economy.AddCoins(b, coinsA, "Trade")
	end
	if coinsB > 0 then
		S.Economy.Spend(b, coinsB, "Trade")
		S.Economy.AddCoins(a, coinsB, "Trade")
	end
	for _, stack in takenA do
		S.Inventory.Add(b, stack, { Source = "Trade with " .. a.DisplayName, Silent = true })
	end
	for _, stack in takenB do
		S.Inventory.Add(a, stack, { Source = "Trade with " .. b.DisplayName, Silent = true })
	end
	S.Data.AddStat(a, "TradesCompleted")
	S.Data.AddStat(b, "TradesCompleted")
	print(
		string.format(
			"[Evergrove] Trade %d: %s (%d items, %d coins) <-> %s (%d items, %d coins)",
			trade.Id,
			a.Name,
			#takenA,
			coinsA,
			b.Name,
			#takenB,
			coinsB
		)
	)
	task.spawn(S.Data.SaveNow, a)
	task.spawn(S.Data.SaveNow, b)
	return true, nil
end

local function confirm(player: Player)
	local trade = trades[player]
	if not trade then
		return false, "You're not trading"
	end
	if os.clock() - trade.Changed < CFG.ConfirmDelay then
		return false, "Take a moment to review the trade"
	end
	trade.Offers[player].Ready = true
	local them = other(trade, player)
	if not trade.Offers[them].Ready then
		push(trade)
		return true, { Waiting = true }
	end
	local ok, why = execute(trade)
	if not ok then
		touched(trade)
		return false, why
	end
	cooldown[trade.A] = os.clock() + CFG.Cooldown
	cooldown[trade.B] = os.clock() + CFG.Cooldown
	close(trade, "Trade complete!")
	return true, { Done = true }
end

local function cancel(player: Player)
	local trade = trades[player]
	if trade then
		close(trade, player.DisplayName .. " cancelled the trade")
	end
	return true
end

function TradingService.Init()
	Net.Handle("TradeRequest", request)
	Net.Handle("TradeRespond", respond)
	Net.Handle("TradeOffer", offerItem)
	Net.Handle("TradeRemove", removeItem)
	Net.Handle("TradeCoins", offerCoins)
	Net.Handle("TradeConfirm", confirm)
	Net.Handle("TradeCancel", cancel)
end

function TradingService.Start()
	Players.PlayerRemoving:Connect(function(player)
		local trade = trades[player]
		if trade then
			close(trade, player.DisplayName .. " left")
		end
		requests[player] = nil
		for _, pending in requests do
			pending[player] = nil
		end
		cooldown[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			for player, trade in trades do
				if trade.A == player and not near(trade.A, trade.B) then
					close(trade, "You moved too far apart")
				end
			end
		end
	end)
end

return TradingService

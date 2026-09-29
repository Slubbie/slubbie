-- Monetization (Config/Store): cosmetic game passes and developer products,
-- plus equipping cosmetics earned anywhere (store, achievements, festivals).
--
-- Fairness rules live in Config/Store: nothing sold affects crops, currency,
-- speed, luck or competitions.
--
-- Game passes are checked on join and after a purchase prompt closes, and
-- granted idempotently (profile.Passes[id]). Developer product receipts are
-- recorded by PurchaseId in profile.Purchases and only acknowledged after the
-- grant has been saved, so a receipt is never granted twice or lost.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Store = require(Shared.Config.Store)
local Net = require(Shared.Lib.Net)
local ItemUtil = require(Shared.Lib.ItemUtil)

local S = require(script.Parent)

local GIFT_TARGET_SECONDS = 300
local MAX_PURCHASE_RECORDS = 200

local StoreService = {}

local byId: { [string]: any } = {}
local byProduct: { [number]: any } = {}
local byPass: { [number]: any } = {}
for _, item in Store.Items do
	byId[item.Id] = item
	if item.ProductId and item.ProductId > 0 then
		byProduct[item.ProductId] = item
	end
	if item.GamePassId and item.GamePassId > 0 then
		byPass[item.GamePassId] = item
	end
end

local giftTargets: { [Player]: { UserId: number, At: number } } = {}

-- Grants ---------------------------------------------------------------------------------------------------------

local function applyGrants(player: Player, profile: any, item: any)
	local g = item.Grants or {}
	for _, cosmetic in g.Cosmetic or {} do
		profile.Cosmetics.Owned[cosmetic] = true
	end
	for _, plate in g.Nameplate or {} do
		profile.Cosmetics.Owned["Nameplate:" .. plate] = true
	end
	for _, emote in g.Emotes or {} do
		profile.Cosmetics.Owned["Emote:" .. emote] = true
	end
	if g.Companion then
		profile.Cosmetics.Owned["Companion:" .. g.Companion] = true
	end
	if g.MusicPack then
		profile.Cosmetics.Owned["Music:" .. g.MusicPack] = true
	end
	if g.Title then
		profile.Titles[g.Title] = true
		S.Data.Changed(player, "Titles")
	end
	if g.LayoutSlots then
		profile.Unlocks.LayoutSlots = math.max(tonumber(profile.Unlocks.LayoutSlots) or 0, g.LayoutSlots)
		S.Data.Changed(player, "Unlocks")
	end
	if g.Supporter and not profile.Unlocks.SupporterLetter then
		profile.Unlocks.SupporterLetter = true
		S.Mail.Send(player, {
			From = "The Evergrove Team",
			Subject = "Thank you! 💚",
			Body = "Your support keeps the valley growing. Enjoy your title and nameplate — and here's a little something for the farm.",
			Items = { ItemUtil.New("festival_box", 1) },
		})
	end
	S.Data.Changed(player, "Cosmetics")
end

local function grantPass(player: Player, item: any)
	local profile = S.Data.Get(player)
	if not profile or profile.Passes[item.Id] then
		return
	end
	profile.Passes[item.Id] = true
	S.Data.Changed(player, "Passes")
	applyGrants(player, profile, item)
	S.Notify.Banner(player, "Thank you!", item.Name .. " is yours.", "Store", item.Icon)
end

local function checkPasses(player: Player)
	for passId, item in byPass do
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
		end)
		if ok and owns then
			grantPass(player, item)
		end
	end
end

-- Developer products --------------------------------------------------------------------------------------------------

local function grantProduct(player: Player, profile: any, item: any): boolean
	local g = item.Grants or {}
	if g.GiftCosmeticBox then
		local target = giftTargets[player]
		local box = { ItemUtil.New("festival_box", 1) }
		if target and os.clock() - target.At < GIFT_TARGET_SECONDS and target.UserId ~= player.UserId then
			giftTargets[player] = nil
			local sent = S.Mail.SendTo(target.UserId, {
				From = player.DisplayName,
				Subject = "🎁 A gift from " .. player.DisplayName,
				Body = "Someone thought your farm could use some festive decorations!",
				Items = box,
			})
			if not sent then
				return false
			end
			S.Notify.Toast(player, "🎁 Your gift is on its way!", "Success")
		else
			S.Mail.Send(player, { From = "Evergrove Store", Subject = "Your Festival Box", Items = box })
		end
		return true
	end
	applyGrants(player, profile, item)
	return true
end

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local profile = S.Data.Wait(player)
	if not profile or S.Data.IsReadOnly(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	if profile.Purchases[purchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local item = byProduct[receipt.ProductId]
	if not item then
		warn("[Evergrove] Receipt for unknown product", receipt.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not grantProduct(player, profile, item) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	profile.Purchases[purchaseId] = os.time()
	-- Keep the record list bounded (Roblox never re-sends very old receipts).
	local count, oldestKey, oldestTime = 0, nil, math.huge
	for key, at in profile.Purchases do
		count += 1
		if at < oldestTime then
			oldestKey, oldestTime = key, at
		end
	end
	if count > MAX_PURCHASE_RECORDS and oldestKey then
		profile.Purchases[oldestKey] = nil
	end
	if not S.Data.SaveNow(player) then
		-- Not saved: don't acknowledge; the grant is idempotent via PurchaseId on retry.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Equipping ---------------------------------------------------------------------------------------------------------

local SLOT_PREFIX =
	{ Banner = true, Frame = true, Effect = true, Nameplate = true, Companion = true, Music = true, Emote = true }

local function owns(profile: any, slot: string, id: string): boolean
	if slot == "Title" then
		return profile.Titles[id] == true
	end
	if SLOT_PREFIX[slot] then
		return profile.Cosmetics.Owned[slot .. ":" .. id] == true
	end
	local def = Store.Cosmetics[id]
	return def ~= nil and def.Slot == slot and profile.Cosmetics.Owned[id] == true
end

local function equip(player: Player, slot: string, id: string?)
	local profile = S.Data.Get(player)
	if not profile then
		return false, "Not ready"
	end
	if id and not owns(profile, slot, id) then
		return false, "You don't own that"
	end
	profile.Cosmetics.Equipped[slot] = id
	S.Data.Changed(player, "Cosmetics")
	S.Player.UpdateNametag(player)
	local character = player.Character
	if character and slot == "Companion" then
		character:SetAttribute("Companion", id)
	end
	if slot == "House" or slot == "Fence" or slot == "Path" then
		S.Farm.RefreshCosmetics(player)
	end
	return true
end

local function storeGet(player: Player)
	local profile = S.Data.Get(player)
	if not profile then
		return false, "Not ready"
	end
	local list = {}
	for _, item in Store.Items do
		local configured = (item.GamePassId or 0) > 0 or (item.ProductId or 0) > 0
		table.insert(list, {
			Id = item.Id,
			Name = item.Name,
			Icon = item.Icon,
			Kind = item.Kind,
			Price = item.Price,
			Description = item.Description,
			Owned = profile.Passes[item.Id] == true,
			Available = configured,
			GamePassId = item.GamePassId,
			ProductId = item.ProductId,
		})
	end
	return true, list
end

-- Lifecycle ---------------------------------------------------------------------------------------------------------

function StoreService.Init()
	Net.Handle("StoreGet", storeGet)
	Net.Handle("CosmeticEquip", equip)
	Net.Handle("StoreGiftTarget", function(player, userId)
		giftTargets[player] = { UserId = userId, At = os.clock() }
		return true
	end)
	MarketplaceService.ProcessReceipt = processReceipt
end

function StoreService.Start()
	S.Data.Loaded:Connect(function(player, profile)
		-- Re-apply grants (idempotent) in case new cosmetics were added to a pass.
		for id in profile.Passes do
			local item = byId[id]
			if item then
				applyGrants(player, profile, item)
			end
		end
		task.spawn(checkPasses, player)
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local item = byPass[passId]
		if purchased and item then
			grantPass(player, item)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		giftTargets[player] = nil
	end)
end

return StoreService

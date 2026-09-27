-- Optional cosmetic purchases. Nothing sold here can change odds, damage,
-- health, instruments, AI behaviour or ranked Standing.
--
-- ProcessReceipt is idempotent: every PurchaseId is recorded in the profile and
-- saved before the purchase is acknowledged. If the save fails we answer
-- NotProcessedYet so Roblox retries later (grants are idempotent too).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Variance.Config)

local MonetizationService = {}

local productsById = {}
local productsByKey = {}
local passesById = {}
local passesByKey = {}

function MonetizationService:Init(services)
	self.Services = services
	for _, product in Config.Monetization.Products do
		if product.Id and product.Id > 0 then
			productsById[product.Id] = product
			productsByKey[product.Key] = product
		end
	end
	for _, pass in Config.Monetization.Passes do
		if pass.Id and pass.Id > 0 then
			passesById[pass.Id] = pass
			passesByKey[pass.Key] = pass
		end
	end
end

local function grantBundle(self, player: Player, bundle, reason: string)
	for _, id in bundle.Grants or {} do
		self.Services.CosmeticService:grant(player, id, reason)
	end
	if bundle.Marks and bundle.Marks > 0 then
		self.Services.ProgressionService:award(player, 0, bundle.Marks, reason)
	end
end

local function processReceipt(self, receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if player == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local profile = self.Services.DataService:waitFor(player, 15)
	if profile == nil or profile.Guest then
		-- Can't persist it right now; Roblox will retry.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	if profile.Data.Purchases[purchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local product = productsById[receipt.ProductId]
	if product == nil then
		warn("[VARIANCE/Monetization] receipt for unknown product " .. tostring(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	grantBundle(self, player, product, "Purchase")
	self.Services.DataService:update(player, function(data)
		data.Purchases[purchaseId] = os.time()
		table.insert(data.PurchaseOrder, purchaseId)
		while #data.PurchaseOrder > Config.Data.PurchaseLogLimit do
			local oldest = table.remove(data.PurchaseOrder, 1)
			data.Purchases[oldest] = nil
		end
	end)
	if self.Services.DataService:save(player) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

local function checkPasses(self, player: Player)
	for id, pass in passesById do
		local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, id)
		if ok and owns then
			grantBundle(self, player, pass, "Game pass")
		end
	end
end

function MonetizationService:catalog()
	local out = {}
	for key, product in productsByKey do
		table.insert(out, { Key = key, Name = product.Name, Description = product.Description, Kind = "Product" })
	end
	for key, pass in passesByKey do
		table.insert(out, { Key = key, Name = pass.Name, Description = pass.Description, Kind = "Pass" })
	end
	table.sort(out, function(a, b)
		return a.Key < b.Key
	end)
	return out
end

function MonetizationService:Start()
	MarketplaceService.ProcessReceipt = function(receipt)
		local ok, result = pcall(processReceipt, self, receipt)
		if ok then
			return result
		end
		warn("[VARIANCE/Monetization] ProcessReceipt error: " .. tostring(result))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local pass = passesById[passId]
		if purchased and pass then
			grantBundle(self, player, pass, "Game pass")
		end
	end)
	self.Services.DataService.Loaded:Connect(function(player)
		task.spawn(checkPasses, self, player)
	end)
	self.Services.NetworkService:handle("Shop.Prompt", function(player, key)
		local product = productsByKey[key]
		if product then
			MarketplaceService:PromptProductPurchase(player, product.Id)
			return true
		end
		local pass = passesByKey[key]
		if pass then
			MarketplaceService:PromptGamePassPurchase(player, pass.Id)
			return true
		end
		return false, "Not available."
	end)
end

return MonetizationService

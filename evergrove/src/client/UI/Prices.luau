-- Client-side price estimates, mirroring MarketService's formula so every
-- selling screen can show what you'd get before you commit. The server
-- computes the real price when you sell; supply pressure comes from
-- MarketGet (refreshed by the screens that need it).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Registry = require(Shared.Lib.Registry)
local ItemUtil = require(Shared.Lib.ItemUtil)
local MarketMath = require(Shared.Lib.MarketMath)
local GameTime = require(Shared.Lib.GameTime)
local Stats = require(Shared.Lib.Stats)
local Economy = require(Shared.Config.Economy)
local Shops = require(Shared.Config.Shops)

local Prices = {}

-- Latest market snapshot from MarketGet.
Prices.Snapshot = { Pressure = {} :: { [string]: number }, Event = 1, Weather = "Sunny", At = 0 }

function Prices.SetSnapshot(data: any)
	if type(data) == "table" then
		Prices.Snapshot = {
			Pressure = data.Pressure or {},
			Event = data.Event or 1,
			Weather = data.Weather or "Sunny",
			At = os.clock(),
		}
	end
end

function Prices.Factor(itemId: string): number
	local snap = Prices.Snapshot
	return MarketMath.Factor(
		itemId,
		{ Time = GameTime.Now(), Weather = snap.Weather, Pressure = snap.Pressure[itemId] or 0, Event = snap.Event }
	)
end

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

-- Venue multiplier: "Bin" or "Merchant:<npcId>" (count matters for the bulk bonus).
function Prices.VenueMultiplier(profile: any, venue: string, def: any, count: number): number
	if venue == "Bin" then
		return 1 + Economy.Selling.Bin.Bonus
	end
	local npcId = string.match(venue, "^Merchant:(.+)$")
	local npc = npcId and Registry.Npcs[npcId]
	local shop = npc and npc.Shop and Registry.Shops[npc.Shop]
	local mult = Shops.OffListSell
	if shop and shop.Buys then
		local best = nil
		for tag, m in shop.Buys do
			if def.Tags[tag] then
				best = math.max(best or 0, m)
			end
		end
		mult = best or Shops.OffListSell
	end
	mult *= 1 - Economy.Selling.Merchant.Spread
	if count >= Economy.Selling.Bulk.Threshold then
		mult *= 1 + Economy.Selling.Bulk.Bonus + Stats.Effect(profile, "BulkBonus")
	end
	return mult
end

-- Estimated unit price for selling a stack at a venue (nil venue = plain market price).
function Prices.Unit(profile: any, stack: any, venue: string?, count: number?): number
	local def = Registry.Items[stack.Id]
	if not def or not profile then
		return 0
	end
	local venueMult = if venue then Prices.VenueMultiplier(profile, venue, def, count or stack.N) else 1
	return math.max(
		1,
		math.floor(ItemUtil.UnitValue(stack) * Prices.Factor(stack.Id) * sellerBonus(profile, def) * venueMult)
	)
end

-- "▲ 18%" style trend text vs. base value.
function Prices.TrendText(itemId: string): (string, string)
	local factor = Prices.Factor(itemId)
	local pct = math.floor((factor - 1) * 100 + 0.5)
	if pct >= 3 then
		return "▲ " .. pct .. "%", "Good"
	elseif pct <= -3 then
		return "▼ " .. -pct .. "%", "Bad"
	end
	return "● steady", "SubText"
end

return Prices

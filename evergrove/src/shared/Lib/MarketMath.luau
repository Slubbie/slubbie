-- Market price model (see Config/Economy). Deterministic parts (trend waves,
-- hot items, shortages) are the same on every server and client, so the market
-- screen can draw history and forecasts locally; supply pressure is server state
-- that the server replicates.

local Config = script.Parent.Parent.Config
local Economy = require(Config.Economy)
local Seasons = require(Config.Seasons)
local WeatherConfig = require(Config.Weather)
local GameTime = require(script.Parent.GameTime)
local RNG = require(script.Parent.RNG)
local Registry = require(script.Parent.Registry)

local M = Economy.Market
local SEED = "evergrove-market-1"

local MarketMath = {}

local seasonDemand: { [string]: { [string]: number } } = {}
for _, season in Seasons do
	seasonDemand[season.Id] = season.Demand
end

-- Items that appear on the market board (everything sellable with a real value).
local tradable: { string } = {}
for _, item in Registry.ItemList do
	if not item.NoSell and item.Value > 0 and item.Category ~= "Placeable" and item.Category ~= "Tool" then
		table.insert(tradable, item.Id)
	end
end
table.sort(tradable)
MarketMath.Tradable = tradable

function MarketMath.HourIndex(t: number): number
	return math.floor(t / GameTime.HOUR)
end

-- Smooth deterministic trend factor for an item at a (fractional) in-game hour.
function MarketMath.Trend(itemId: string, hour: number): number
	local periodLo, periodHi = M.TrendPeriodHours[1], M.TrendPeriodHours[2]
	local period = periodLo + RNG.Hash(SEED, "period", itemId) * (periodHi - periodLo)
	local phase = RNG.Hash(SEED, "phase", itemId)
	local phase2 = RNG.Hash(SEED, "phase2", itemId)
	local wave = math.sin(2 * math.pi * (hour / period + phase)) * 0.7
		+ math.sin(2 * math.pi * (hour / (period * 0.37) + phase2)) * 0.3
	return 1 + wave * M.TrendAmp
end

local function tagMultiplier(def: any, table_: { [string]: number }?): number
	if not table_ then
		return 1
	end
	local mult = 1
	for tag, value in table_ do
		if def.Tags[tag] then
			mult *= value
		end
	end
	return mult
end

function MarketMath.SeasonFactor(itemId: string, seasonId: string): number
	local def = Registry.Items[itemId]
	if not def then
		return 1
	end
	local mult = tagMultiplier(def, seasonDemand[seasonId])
	-- Out-of-season fresh crops are scarcer, so they sell a little higher.
	if def.Crop then
		local crop = Registry.Crops[def.Crop]
		local inSeason = false
		for _, s in crop.Seasons do
			if s == seasonId or s == "Any" then
				inSeason = true
			end
		end
		if not inSeason then
			mult *= 1.2
		end
	end
	return mult
end

function MarketMath.WeatherFactor(itemId: string, weatherId: string): number
	local def = Registry.Items[itemId]
	local weather = WeatherConfig.Types[weatherId]
	if not def or not weather then
		return 1
	end
	return tagMultiplier(def, weather.Market)
end

-- Hot items for a day: a few in-demand items, the same everywhere.
local hotCache: { [number]: { string } } = {}
function MarketMath.HotItems(day: number): { string }
	local cached = hotCache[day]
	if cached then
		return cached
	end
	local picks = {}
	local used = {}
	local attempts = 0
	while #picks < M.HotItems.Count and attempts < 50 do
		attempts += 1
		local index = 1 + (RNG.HashInt(SEED, "hot", day, attempts) % #tradable)
		local id = tradable[index]
		local def = Registry.Items[id]
		if
			not used[id]
			and def
			and (
				def.Category == "Crop"
				or def.Category == "Artisan"
				or def.Category == "Fish"
				or def.Category == "AnimalProduct"
			)
		then
			used[id] = true
			table.insert(picks, id)
		end
	end
	hotCache[day] = picks
	return picks
end

-- A shortage (bigger boost) some days.
function MarketMath.Shortage(day: number): string?
	if RNG.Hash(SEED, "shortage?", day) > M.Shortage.Chance then
		return nil
	end
	local crops = {}
	for _, id in tradable do
		local def = Registry.Items[id]
		if def.Category == "Crop" and Registry.RarityOrder(def.Rarity) <= 3 then
			table.insert(crops, id)
		end
	end
	if #crops == 0 then
		return nil
	end
	return crops[1 + RNG.HashInt(SEED, "shortage", day) % #crops]
end

export type Context = {
	Time: number,
	Weather: string,
	Pressure: number?, -- supply pressure for this item (0-1)
	Event: number?, -- extra multiplier (festivals, night market)
}

-- Market factor for an item (multiplies the stack's unit value).
function MarketMath.Factor(itemId: string, ctx: Context): number
	local info = GameTime.Info(ctx.Time)
	local factor = MarketMath.Trend(itemId, ctx.Time / GameTime.HOUR)
	factor *= MarketMath.SeasonFactor(itemId, info.SeasonId)
	factor *= MarketMath.WeatherFactor(itemId, ctx.Weather)
	if table.find(MarketMath.HotItems(info.Day), itemId) then
		factor *= M.HotItems.Multiplier
	end
	if MarketMath.Shortage(info.Day) == itemId then
		factor *= M.Shortage.Multiplier
	end
	factor *= 1 - math.clamp(ctx.Pressure or 0, 0, M.Supply.MaxDrop)
	factor *= ctx.Event or 1
	return math.clamp(factor, M.MinFactor, M.MaxFactor)
end

-- Price history for the market graph (deterministic parts only).
function MarketMath.History(itemId: string, now: number, points: number?): { number }
	local out = {}
	local n = points or M.HistoryPoints
	local hour = MarketMath.HourIndex(now)
	for i = n - 1, 0, -1 do
		local t = (hour - i) * GameTime.HOUR
		local info = GameTime.Info(t)
		local factor = MarketMath.Trend(itemId, hour - i) * MarketMath.SeasonFactor(itemId, info.SeasonId)
		table.insert(out, factor)
	end
	return out
end

-- Simple forecast: the trend for the next few hours (Market Savvy perk shows it).
function MarketMath.Forecast(itemId: string, now: number, hours: number): { number }
	local out = {}
	local hour = MarketMath.HourIndex(now)
	for i = 1, hours do
		table.insert(out, MarketMath.Trend(itemId, hour + i))
	end
	return out
end

-- Demand label for the UI.
function MarketMath.DemandLabel(factor: number): (string, string)
	if factor >= 1.35 then
		return "Very High", "🔥"
	elseif factor >= 1.12 then
		return "High", "📈"
	elseif factor >= 0.92 then
		return "Normal", "➖"
	elseif factor >= 0.75 then
		return "Low", "📉"
	end
	return "Very Low", "🧊"
end

return MarketMath

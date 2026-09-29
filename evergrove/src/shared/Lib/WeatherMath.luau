-- Deterministic weather.
--
-- The weather for each time slot is a pure function of the slot number, so every
-- server and client computes the same weather and forecast without networking.
-- A slot keeps the previous slot's weather with Time.WeatherPersistence chance,
-- rainbows tend to follow rain, and night-only weather (meteors, aurora) only
-- rolls in night slots. Debug overrides are published as ReplicatedStorage
-- attributes (WeatherOverride / WeatherOverrideUntil in game seconds).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = script.Parent.Parent.Config
local TimeConfig = require(Config.Time)
local WeatherConfig = require(Config.Weather)
local GameTime = require(script.Parent.GameTime)
local RNG = require(script.Parent.RNG)

local SEED = "evergrove-weather-1"
local SLOT_HOURS = TimeConfig.WeatherSlotHours

local WeatherMath = {}

function WeatherMath.SlotIsNight(slot: number): boolean
	local startHour = (slot * SLOT_HOURS) % 24
	return GameTime.IsNightHour((startHour + SLOT_HOURS / 2) % 24)
end

local function allowed(weatherId: string, night: boolean): boolean
	local def = WeatherConfig.Types[weatherId]
	if not def then
		return false
	end
	if def.Time == "Night" then
		return night
	elseif def.Time == "Day" then
		return not night
	end
	return true
end

local cache: { [number]: string } = {}
local cacheSize = 0

local function basePick(slot: number): string
	local cached = cache[slot]
	if cached then
		return cached
	end
	local season = GameTime.SeasonOf(GameTime.SlotStart(slot))
	local night = WeatherMath.SlotIsNight(slot)
	local weights = {}
	for id, weight in pairs(WeatherConfig.SeasonWeights[season] or {}) do
		if allowed(id, night) then
			weights[id] = weight
		end
	end
	local pick = RNG.WeightedKey(weights, RNG.Hash(SEED, "base", slot)) or "Sunny"
	if cacheSize > 512 then
		table.clear(cache)
		cacheSize = 0
	end
	cache[slot] = pick
	cacheSize += 1
	return pick
end

-- Natural weather for a slot (ignores overrides).
function WeatherMath.At(slot: number): string
	local night = WeatherMath.SlotIsNight(slot)
	local previous = basePick(slot - 1)
	-- Rainbows like to follow rain during the day.
	if not night and (previous == "Rain" or previous == "Thunderstorm") and RNG.Hash(SEED, "rainbow", slot) < 0.12 then
		return "RainbowMist"
	end
	if RNG.Hash(SEED, "persist", slot) < TimeConfig.WeatherPersistence and allowed(previous, night) then
		return previous
	end
	return basePick(slot)
end

-- Active debug override, if any.
function WeatherMath.Override(t: number): string?
	local id = ReplicatedStorage:GetAttribute("WeatherOverride")
	local untilTime = ReplicatedStorage:GetAttribute("WeatherOverrideUntil")
	if type(id) == "string" and id ~= "" and type(untilTime) == "number" and t < untilTime then
		if WeatherConfig.Types[id] then
			return id
		end
	end
	return nil
end

-- Weather at game time t (override first).
function WeatherMath.Current(t: number?): string
	local time = t or GameTime.Now()
	return WeatherMath.Override(time) or WeatherMath.At(GameTime.SlotOf(time))
end

-- Regional variant (desert turns rain into sandstorms, etc.).
function WeatherMath.ForRegion(weatherId: string, region: any?): string
	if region and region.Weather then
		if region.Weather.Force then
			return region.Weather.Force
		end
		local replaced = region.Weather.Replace and region.Weather.Replace[weatherId]
		if replaced then
			return replaced
		end
	end
	return weatherId
end

export type ForecastEntry = { Slot: number, Start: number, Weather: string, Night: boolean }

-- The next `count` slots after the current one.
function WeatherMath.Forecast(count: number, t: number?): { ForecastEntry }
	local time = t or GameTime.Now()
	local slot = GameTime.SlotOf(time)
	local out = {}
	for i = 1, count do
		local s = slot + i
		table.insert(out, {
			Slot = s,
			Start = GameTime.SlotStart(s),
			Weather = WeatherMath.At(s),
			Night = WeatherMath.SlotIsNight(s),
		})
	end
	return out
end

function WeatherMath.Def(weatherId: string)
	return WeatherConfig.Types[weatherId] or WeatherConfig.Types.Sunny
end

return WeatherMath

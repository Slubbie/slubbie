-- The world clock and calendar, identical on server and clients.
--
-- Game time is "game seconds since Epoch". On public servers it advances 1:1 with
-- real time, so every server agrees on the day, season and weather. The server
-- publishes an anchor on ReplicatedStorage so it can slow time (solo private
-- servers with menus open) or jump it (debug tools):
--
--   gameTime = ClockBase + (serverTimeNow - ClockAnchor) * ClockScale
--
-- All saved timestamps (planting, machines, animals) are in game seconds.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TimeConfig = require(script.Parent.Parent.Config.Time)
local Seasons = require(script.Parent.Parent.Config.Seasons)

local DAY = TimeConfig.DayLength
local HOUR = DAY / 24
local SEASON_DAYS = TimeConfig.DaysPerSeason
local YEAR_DAYS = SEASON_DAYS * #Seasons

export type Info = {
	Time: number, -- game seconds
	Day: number, -- absolute day index (0-based)
	Hour: number, -- 0-24 float
	Minute: number,
	Season: number, -- 1..4
	SeasonId: string,
	SeasonName: string,
	DayOfSeason: number, -- 1..DaysPerSeason
	Year: number,
	IsNight: boolean,
	IsDaytime: boolean,
	Slot: number, -- weather slot index
	Moon: number, -- 0..MoonCycleDays-1
	FullMoon: boolean,
	Weekday: number, -- 1..7
}

local GameTime = {}
GameTime.DAY = DAY
GameTime.HOUR = HOUR
GameTime.SEASON_DAYS = SEASON_DAYS
GameTime.YEAR_DAYS = YEAR_DAYS
GameTime.WEEKDAYS = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }

-- Real time shared by server and clients.
function GameTime.ServerNow(): number
	return workspace:GetServerTimeNow()
end

-- The default mapping from real time to game time (public servers).
function GameTime.FromReal(real: number): number
	return (real - TimeConfig.Epoch) + TimeConfig.StartHour * HOUR
end

function GameTime.Now(): number
	local anchor = ReplicatedStorage:GetAttribute("ClockAnchor")
	local base = ReplicatedStorage:GetAttribute("ClockBase")
	local scale = ReplicatedStorage:GetAttribute("ClockScale")
	local now = GameTime.ServerNow()
	if type(anchor) ~= "number" or type(base) ~= "number" then
		return GameTime.FromReal(now)
	end
	return base + (now - anchor) * (if type(scale) == "number" then scale else 1)
end

function GameTime.DayIndex(t: number): number
	return math.floor(t / DAY)
end

function GameTime.HourOf(t: number): number
	return (t % DAY) / HOUR
end

function GameTime.SeasonIndex(day: number): number
	return math.floor(day / SEASON_DAYS) % #Seasons + 1
end

function GameTime.SeasonOf(t: number): string
	return Seasons[GameTime.SeasonIndex(GameTime.DayIndex(t))].Id
end

function GameTime.IsNightHour(hour: number): boolean
	return hour >= TimeConfig.NightHour or hour < TimeConfig.DawnHour
end

function GameTime.SlotOf(t: number): number
	return math.floor(t / (TimeConfig.WeatherSlotHours * HOUR))
end

function GameTime.SlotStart(slot: number): number
	return slot * TimeConfig.WeatherSlotHours * HOUR
end

function GameTime.Info(t: number?): Info
	local time = t or GameTime.Now()
	local day = GameTime.DayIndex(time)
	local hour = GameTime.HourOf(time)
	local seasonIndex = GameTime.SeasonIndex(day)
	local season = Seasons[seasonIndex]
	local moon = day % TimeConfig.MoonCycleDays
	return {
		Time = time,
		Day = day,
		Hour = hour,
		Minute = math.floor((hour % 1) * 60),
		Season = seasonIndex,
		SeasonId = season.Id,
		SeasonName = season.Name,
		DayOfSeason = day % SEASON_DAYS + 1,
		Year = math.floor(day / YEAR_DAYS) + 1,
		IsNight = GameTime.IsNightHour(hour),
		IsDaytime = not GameTime.IsNightHour(hour),
		Slot = GameTime.SlotOf(time),
		Moon = moon,
		FullMoon = moon == math.floor(TimeConfig.MoonCycleDays / 2),
		Weekday = day % 7 + 1,
	}
end

-- Game seconds until the clock next reads `hour` (0-24).
function GameTime.UntilHour(hour: number, t: number?): number
	local time = t or GameTime.Now()
	local current = GameTime.HourOf(time)
	local delta = (hour - current) % 24
	if delta == 0 then
		delta = 24
	end
	return delta * HOUR
end

-- Absolute day index for a calendar date (season 1-4, day 1..N) in the current year
-- or the next occurrence if it has passed.
function GameTime.NextDate(seasonIndex: number, dayOfSeason: number, t: number?): number
	local now = GameTime.DayIndex(t or GameTime.Now())
	local yearStart = now - now % YEAR_DAYS
	local target = yearStart + (seasonIndex - 1) * SEASON_DAYS + (dayOfSeason - 1)
	if target < now then
		target += YEAR_DAYS
	end
	return target
end

-- Real seconds per game second right now (1 on public servers).
function GameTime.Scale(): number
	local scale = ReplicatedStorage:GetAttribute("ClockScale")
	return if type(scale) == "number" then scale else 1
end

-- "Spring 3, Year 1"
function GameTime.DateText(info: Info): string
	return string.format("%s %d, Year %d", info.SeasonName, info.DayOfSeason, info.Year)
end

return GameTime

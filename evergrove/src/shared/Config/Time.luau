-- World clock and calendar.
--
-- The calendar is derived from the real time since Epoch, so every public server
-- shows the same day, season and weather. Private servers owned by a solo
-- player can slow time while that player has a blocking menu open.

return {
	-- Real seconds in one in-game day (24 in-game hours).
	DayLength = 1200,
	DaysPerSeason = 7,
	-- Real unix time of Spring 1, Year 1 (the world "launch"). 2026-09-27 00:00 UTC.
	Epoch = 1790467200,
	-- The clock reads this hour at Epoch, so a fresh world begins at dawn.
	StartHour = 6,

	-- Hours used by lighting, NPC schedules, fish and bugs.
	DawnHour = 5.5,
	MorningHour = 6,
	DuskHour = 18.5,
	NightHour = 20,

	-- The weather rolls once per slot (4 slots per day by default).
	WeatherSlotHours = 6,
	-- Chance a slot keeps the previous slot's weather (makes weather feel persistent).
	WeatherPersistence = 0.45,

	-- Moon phases cycle every N days; phase N/2 is the full moon.
	MoonCycleDays = 8,

	-- Private servers with one player: slow the clock while a blocking menu is open.
	SoloSlowdown = {
		Enabled = true,
		MenuScale = 0.2,
	},
}

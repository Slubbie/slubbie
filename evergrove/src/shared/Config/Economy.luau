-- Economy: currencies, the dynamic market and every way to sell.
--
-- Market price of an item =
--   base value × quality × mutations
--   × season demand (Config/Seasons.Demand by tag/category)
--   × weather demand (Config/Weather.Market)
--   × trend: a smooth deterministic wave per item (same on every server) in [1-TrendAmp, 1+TrendAmp]
--   × supply: falls as players on this server (and, if enabled, all servers) sell a lot of it,
--             recovering over time
--   × events: festival / shortage / "hot item" multipliers
-- Prices are only ever computed on the server when you sell.

return {
	StartingCoins = 300,
	-- Currency caps protect against overflow bugs.
	MaxCoins = 1e12,
	MaxTokens = 1e7,

	Market = {
		-- Price history points are sampled every in-game hour.
		HistoryPoints = 24,
		TrendAmp = 0.18, -- ±18% smooth wave
		TrendPeriodHours = { 30, 90 }, -- each item gets its own period in this range
		Supply = {
			-- Each coin of value sold adds this much pressure; price × (1 - pressure), capped.
			PressurePerValue = 1 / 60000,
			MaxDrop = 0.35,
			-- Pressure decays by this fraction per in-game hour.
			RecoveryPerHour = 0.08,
			-- Share supply between servers through MemoryStore (falls back to local).
			CrossServer = true,
			SyncSeconds = 45,
		},
		-- Daily "hot" and "shortage" items (deterministic per day, same everywhere).
		HotItems = { Count = 3, Multiplier = 1.4 },
		Shortage = { Chance = 0.35, Multiplier = 1.8 },
		-- Sale floor/ceiling vs. base value.
		MinFactor = 0.45,
		MaxFactor = 3,
	},

	Selling = {
		-- Shipping bin at your farm: paid at the next in-game morning at that moment's price.
		Bin = { Bonus = 0, PayHour = 6, Capacity = 500 },
		-- Selling directly to a merchant: instant, but a small spread.
		Merchant = { Spread = 0.08 },
		-- Market stall (player-to-player): the town takes a fee on each sale.
		Stall = { Fee = 0.05, MaxPrice = 10, MinPrice = 0.5, Slots = 6 }, -- price bounds × item value
		-- Exports from the harbour: pay after DeliveryDays, with a premium that grows with batch value,
		-- and a storm risk that delays (never loses) the shipment.
		Export = {
			DeliveryDays = 2,
			Premium = 0.25,
			BulkPremiumPer10k = 0.01,
			MaxPremium = 0.45,
			StormDelayChance = 0.25,
			PreferredTags = { Export = 0.15, Preserve = 0.1 },
			MinValue = 500,
			MaxActive = 3,
		},
		-- Bulk bonus when selling many of one item at once (Trading skill adds more).
		Bulk = { Threshold = 25, Bonus = 0.03 },
		-- Confirm before selling items worth more than this (client setting can change it).
		ConfirmAbove = 5000,
	},

	Contracts = {
		-- Contract board: NPC bulk orders refreshed every in-game morning.
		Count = 5,
		DurationDays = 3,
		PayMultiplier = { 1.5, 2.4 },
		SizeRange = { 10, 60 },
		MaxActive = 3,
		-- Collector contracts (Beatrix, 3 hearts): specific mutations/qualities, big payouts.
		Collector = { Count = 2, PayMultiplier = { 4, 8 } },
		-- Restaurant orders (Marco): cooked dishes.
		Restaurant = { Count = 3, PayMultiplier = { 1.6, 2.5 } },
	},

	-- Values used for "Farm value" in the statistics dashboard.
	FarmValue = { ParcelWeight = 1, PlaceableWeight = 1, AnimalWeight = 1, InventoryWeight = 0.5 },
}

-- Multiplayer: visitor permissions, trading, cooperatives, mail and daily rewards.

return {
	-- Visitor permission levels, lowest to highest. Each level includes the ones before it.
	Permissions = {
		Order = { "None", "View", "Crops", "Animals", "Machines", "Harvest", "Build", "Trusted" },
		Levels = {
			None = { Name = "No Visitors", Icon = "🚫", Description = "Nobody can enter your farm." },
			View = { Name = "View Only", Icon = "👀", Description = "Visitors can walk around and look." },
			Crops = { Name = "Help With Crops", Icon = "💧", Description = "Visitors can water, fertilize and cure pests." },
			Animals = { Name = "Feed Animals", Icon = "🐔", Description = "Visitors can feed, pet and brush animals." },
			Machines = { Name = "Use Machines", Icon = "⚙️", Description = "Visitors can load machines with their own items and collect for you." },
			Harvest = { Name = "Harvest", Icon = "🧺", Description = "Visitors can harvest crops. The harvest goes to YOUR mail." },
			Build = { Name = "Build", Icon = "🛠️", Description = "Visitors can move and place decorations (not sell or remove buildings)." },
			Trusted = { Name = "Full Trusted Access", Icon = "🤝", Description = "Everything except selling your items or buying land." },
		},
		Default = "View",
		-- Friends of the owner get this level by default (owners can override per player).
		FriendDefault = "Crops",
	},

	Trading = {
		MaxSlots = 12,
		MaxCoins = 1e9,
		Distance = 40, -- studs between traders
		ConfirmDelay = 3, -- seconds both must wait after the last change before confirming
		Cooldown = 8,
		-- Items with NoTrade, locked items and tools can't be traded.
	},

	Guilds = {
		NameMin = 3,
		NameMax = 24,
		MaxMembers = 20,
		CreateCost = 25000,
		-- Shared upgrades bought with contributed coins/items (cosmetic + small quality-of-life).
		Upgrades = {
			{ Id = "banner", Name = "Guild Banner", Icon = "🚩", Cost = 50000, Description = "A banner in the Co-op Hall and on members' farms." },
			{ Id = "hall_decor", Name = "Hall Decor", Icon = "🏮", Cost = 150000, Description = "Lanterns and flowers in the Co-op Hall." },
			{ Id = "shared_chest", Name = "Shared Chest", Icon = "🧰", Cost = 250000, Description = "A cross-server chest all members can use." },
			{ Id = "emblem", Name = "Golden Emblem", Icon = "🏅", Cost = 500000, Description = "A golden emblem on every member's nameplate." },
			{ Id = "statue", Name = "Founders' Statue", Icon = "🗽", Cost = 1500000, Description = "A statue of your founders in the village." },
		},
		-- Weekly objectives: contributions from all members add up.
		Weekly = {
			{ Id = "g_harvest", Text = "Harvest 5,000 crops together", Stat = "CropsHarvested", Goal = 5000, Reward = { Coins = 5000, GuildPoints = 100 } },
			{ Id = "g_fish", Text = "Catch 500 fish together", Stat = "FishCaught", Goal = 500, Reward = { Coins = 4000, GuildPoints = 80 } },
			{ Id = "g_artisan", Text = "Make 1,000 artisan goods together", Stat = "ArtisanMade", Goal = 1000, Reward = { Coins = 6000, GuildPoints = 120 } },
		},
		ContributionPoints = 1, -- guild points per 1000 coins of contributed value
	},

	Mail = {
		Capacity = 60,
		-- Mail over capacity waits in an overflow queue (never lost) and moves in as you claim.
		OverflowCapacity = 200,
		ExpireDays = 60, -- claimed mail without attachments is cleaned up after this many real days
	},

	-- Daily login rewards: a 28-day cycle. Missing days never resets progress; the
	-- cycle simply continues the next time you log in (streaks are tracked for fun).
	Daily = {
		{ Coins = 200 },
		{ Items = { { "compost", 10 } } },
		{ Items = { { "seed_crate", 1 } } },
		{ Coins = 400 },
		{ Items = { { "basic_fertilizer", 10 } } },
		{ Items = { { "treat", 3 } } },
		{ Coins = 1000, Items = { { "festival_box", 1 } } },
		{ Items = { { "bait", 20 } } },
		{ Coins = 600 },
		{ Items = { { "speed_gro", 8 } } },
		{ Items = { { "geode", 5 } } },
		{ Items = { { "quality_fertilizer", 8 } } },
		{ Items = { { "mystery_seed", 5 } } },
		{ Coins = 2500, Items = { { "lantern_post", 2 } } },
		{ Coins = 800 },
		{ Items = { { "deluxe_bait", 10 } } },
		{ Items = { { "hydro_gel", 8 } } },
		{ Items = { { "omni_geode", 2 } } },
		{ Coins = 1200 },
		{ Items = { { "energy_tonic", 3 } } },
		{ Coins = 5000, Items = { { "mutagen", 2 } } },
		{ Items = { { "flower_bed", 4 } } },
		{ Coins = 1500 },
		{ Items = { { "deluxe_speed_gro", 5 } } },
		{ Items = { { "treasure_chest", 1 } } },
		{ Items = { { "golden_dust", 1 } } },
		{ Coins = 3000 },
		{ Coins = 10000, Items = { { "prism_shard", 1 }, { "festival_box", 2 } }, Title = "Loyal Farmer" },
	},

	-- Names (farms, animals, layouts, guilds, signs) are filtered with TextService.
	Names = { FarmMax = 28, AnimalMax = 20, LayoutMax = 24, SignMax = 40, GuildMax = 24 },

	Profile = {
		ShowcaseSlots = 6,
		-- Everything shown on a profile card is gameplay data; no account info.
	},

	-- Emotes / photo-mode poses. Pack = needs "Emote:<Id>" from the store's emote pack.
	Emotes = {
		{ Id = "Wave", Name = "Wave", Icon = "👋" },
		{ Id = "Cheer", Name = "Cheer", Icon = "🙌" },
		{ Id = "Clap", Name = "Clap", Icon = "👏" },
		{ Id = "Think", Name = "Think", Icon = "🤔" },
		{ Id = "Bow", Name = "Bow", Icon = "🙇" },
		{ Id = "Point", Name = "Point", Icon = "👉" },
		{ Id = "HarvestDance", Name = "Harvest Dance", Icon = "🕺", Pack = true },
		{ Id = "Yodel", Name = "Yodel", Icon = "🎶", Pack = true },
		{ Id = "TipHat", Name = "Tip Hat", Icon = "🎩", Pack = true },
		{ Id = "Scarecrow", Name = "Scarecrow", Icon = "🧍", Pack = true },
	},
}

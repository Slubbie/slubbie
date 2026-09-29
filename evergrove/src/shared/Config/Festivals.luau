-- Festivals and competitions.
--
-- A festival runs on its calendar day (Season index 1-4, Day of season) between
-- Hours. The village is decorated, NPCs gather at the FestivalStage, the music
-- changes and a festival shop opens (paid in Festival Tokens).
--
-- Activities
--   Scavenger  collectibles hidden around the village; each find pays tokens
--   Contest    submit one entry; judged on transparent criteria (Scoring weights)
--   Derby      fishing: biggest catch (by size) during the festival wins
--   Race       run through checkpoints; fastest time wins
--   Lanterns   release lanterns at the lake (night): pays tokens, lights the sky
--
-- Contest score (0-100) = Σ weight × criterion, criteria each in [0,1]:
--   Quality   quality tier / 6
--   Size      size vs the species' record range
--   Rarity    rarity order / 6
--   Mutations mutation value (log-scaled) and combos
--   Care      freshness (crops) or friendship/happiness (animals)

export type Festival = {
	Id: string,
	Name: string,
	Icon: string,
	Season: number,
	Day: number,
	Hours: { number },
	Description: string,
	Decor: string,
	Weather: string?,
	Activities: { { [string]: any } },
	Shop: { { Id: string, Price: number, Stock: number? } },
	Challenges: { { Id: string, Text: string, Type: string, Target: string?, Count: number, Tokens: number } },
	Prizes: { [string]: { [string]: any } },
	Music: string,
}

local List: { Festival } = {
	{
		Id = "SpringFair",
		Name = "Spring Fair",
		Icon = "🌸",
		Season = 1,
		Day = 3,
		Hours = { 8, 21 },
		Description = "Blossoms, an egg hunt and the Flower Show.",
		Decor = "Spring",
		Weather = "Sunny",
		Music = "Festival",
		Activities = {
			{
				Kind = "Scavenger",
				Id = "egg_hunt",
				Name = "Egg Hunt",
				Icon = "🥚",
				Count = 24,
				Tokens = 5,
				Model = "Egg",
			},
			{
				Kind = "Contest",
				Id = "flower_show",
				Name = "Flower Show",
				Icon = "🌷",
				Accept = { "#Flower" },
				Scoring = { Quality = 35, Size = 10, Rarity = 20, Mutations = 30, Care = 5 },
			},
		},
		Shop = {
			{ Id = "spring_arch", Price = 60 },
			{ Id = "egg_basket", Price = 30 },
			{ Id = "seed_rose", Price = 8 },
			{ Id = "flower_carpet", Price = 4 },
			{ Id = "cherry_tree", Price = 80 },
			{ Id = "mystery_seed", Price = 10, Stock = 10 },
		},
		Challenges = {
			{ Id = "sf_eggs", Text = "Find 10 eggs", Type = "Scavenger", Count = 10, Tokens = 30 },
			{
				Id = "sf_flowers",
				Text = "Harvest 10 flowers today",
				Type = "Harvest",
				Target = "#Flower",
				Count = 10,
				Tokens = 25,
			},
		},
		Prizes = {
			First = { Coins = 8000, Tokens = 150, Items = { { "blue_ribbon_plaque", 1 } }, Title = "Flower Champion" },
			Second = { Coins = 4000, Tokens = 90 },
			Third = { Coins = 2000, Tokens = 60 },
			Entry = { Tokens = 25 },
		},
	},
	{
		Id = "LivestockShow",
		Name = "Livestock Exhibition",
		Icon = "🐄",
		Season = 1,
		Day = 6,
		Hours = { 9, 18 },
		Description = "Bring your best animal. Judges look at genes, happiness and friendship.",
		Decor = "Ranch",
		Music = "Festival",
		Activities = {
			{
				Kind = "Contest",
				Id = "livestock",
				Name = "Best in Show",
				Icon = "🎀",
				Accept = { "Animal" },
				Scoring = { Quality = 20, Size = 20, Rarity = 30, Mutations = 0, Care = 30 },
			},
		},
		Shop = {
			{ Id = "treat", Price = 6 },
			{ Id = "cow_statue", Price = 80 },
			{ Id = "chicken_statue", Price = 50 },
			{ Id = "hay_bale", Price = 3 },
		},
		Challenges = {
			{ Id = "ls_pet", Text = "Pet 10 animals", Type = "Pet", Count = 10, Tokens = 30 },
			{ Id = "ls_collect", Text = "Collect 10 animal products", Type = "Collect", Count = 10, Tokens = 30 },
		},
		Prizes = {
			First = { Coins = 10000, Tokens = 150, Items = { { "blue_ribbon_plaque", 1 } }, Title = "Best in Show" },
			Second = { Coins = 5000, Tokens = 90 },
			Third = { Coins = 2500, Tokens = 60 },
			Entry = { Tokens = 25 },
		},
	},
	{
		Id = "FishingDerby",
		Name = "Fishing Tournament",
		Icon = "🎣",
		Season = 2,
		Day = 2,
		Hours = { 6, 18 },
		Description = "Catch the biggest fish before the horn blows.",
		Decor = "Summer",
		Music = "Festival",
		Activities = {
			{ Kind = "Derby", Id = "derby", Name = "Biggest Catch", Icon = "🐟" },
		},
		Shop = {
			{ Id = "deluxe_bait", Price = 2 },
			{ Id = "legend_lure", Price = 250, Stock = 1 },
			{ Id = "koi_pond", Price = 120 },
			{ Id = "beach_umbrella", Price = 30 },
		},
		Challenges = {
			{ Id = "fd_catch", Text = "Catch 12 fish", Type = "Catch", Count = 12, Tokens = 40 },
			{
				Id = "fd_rare",
				Text = "Catch a Rare or better fish",
				Type = "Catch",
				Target = "@Rare",
				Count = 1,
				Tokens = 50,
			},
		},
		Prizes = {
			First = { Coins = 12000, Tokens = 180, Items = { { "fishing_trophy", 1 } }, Title = "Derby Champion" },
			Second = { Coins = 6000, Tokens = 100 },
			Third = { Coins = 3000, Tokens = 70 },
			Entry = { Tokens = 25 },
		},
	},
	{
		Id = "CookOff",
		Name = "Summer Cook-Off",
		Icon = "🍲",
		Season = 2,
		Day = 5,
		Hours = { 10, 21 },
		Description = "Chef Marco judges the valley's finest dishes.",
		Decor = "Summer",
		Music = "Festival",
		Activities = {
			{
				Kind = "Contest",
				Id = "cookoff",
				Name = "Cook-Off",
				Icon = "👨‍🍳",
				Accept = { "#Cooked" },
				Scoring = { Quality = 40, Size = 0, Rarity = 35, Mutations = 15, Care = 10 },
			},
		},
		Shop = {
			{ Id = "bbq_grill", Price = 60 },
			{ Id = "picnic_table", Price = 40 },
			{ Id = "book_cooking", Price = 150, Stock = 1 },
			{ Id = "golden_dust", Price = 200, Stock = 1 },
		},
		Challenges = {
			{ Id = "co_cook", Text = "Cook 5 dishes", Type = "Cook", Count = 5, Tokens = 40 },
		},
		Prizes = {
			First = { Coins = 12000, Tokens = 160, Title = "Golden Ladle" },
			Second = { Coins = 6000, Tokens = 90 },
			Third = { Coins = 3000, Tokens = 60 },
			Entry = { Tokens = 25 },
		},
	},
	{
		Id = "StarfallNight",
		Name = "Starfall Night",
		Icon = "🌠",
		Season = 2,
		Day = 7,
		Hours = { 19, 24 },
		Description = "A guaranteed meteor shower. Meteorites land around the valley. Make a wish!",
		Decor = "Night",
		Weather = "MeteorShower",
		Music = "Night",
		Activities = {
			{
				Kind = "Scavenger",
				Id = "star_hunt",
				Name = "Fallen Stars",
				Icon = "⭐",
				Count = 16,
				Tokens = 8,
				Model = "Star",
			},
		},
		Shop = {
			{ Id = "star_lamp", Price = 90 },
			{ Id = "stardust", Price = 60 },
			{ Id = "constellation_arch", Price = 300 },
			{ Id = "seed_starfruit", Price = 40 },
		},
		Challenges = {
			{ Id = "st_stars", Text = "Collect 8 fallen stars", Type = "Scavenger", Count = 8, Tokens = 60 },
		},
		Prizes = { Entry = { Tokens = 20 } },
	},
	{
		Id = "HarvestFestival",
		Name = "Harvest Festival",
		Icon = "🎃",
		Season = 3,
		Day = 4,
		Hours = { 8, 22 },
		Description = "The biggest day of the year: the Giant Crop Contest, apple bobbing and golden wheat seeds.",
		Decor = "Autumn",
		Weather = "Sunny",
		Music = "Festival",
		Activities = {
			{
				Kind = "Contest",
				Id = "giant_crop",
				Name = "Giant Crop Contest",
				Icon = "🏆",
				Accept = { "#Crop" },
				Scoring = { Quality = 20, Size = 40, Rarity = 15, Mutations = 20, Care = 5 },
			},
			{
				Kind = "Scavenger",
				Id = "apple_bob",
				Name = "Apple Bobbing",
				Icon = "🍎",
				Count = 20,
				Tokens = 4,
				Model = "Apple",
			},
		},
		Shop = {
			{ Id = "seed_golden_wheat", Price = 60, Stock = 5 },
			{ Id = "seed_giant_pumpkin", Price = 90, Stock = 3 },
			{ Id = "giant_grow", Price = 25 },
			{ Id = "pumpkin_pile", Price = 20 },
			{ Id = "scarecrow_fancy", Price = 50 },
		},
		Challenges = {
			{ Id = "hf_harvest", Text = "Harvest 40 crops today", Type = "Harvest", Count = 40, Tokens = 40 },
			{
				Id = "hf_quality",
				Text = "Harvest 10 Pristine or better crops",
				Type = "Harvest",
				Count = 10,
				Tokens = 60,
				Quality = 4,
			},
		},
		Prizes = {
			First = { Coins = 20000, Tokens = 250, Items = { { "golden_pumpkin_statue", 1 } }, Title = "Harvest King" },
			Second = { Coins = 10000, Tokens = 150 },
			Third = { Coins = 5000, Tokens = 100 },
			Entry = { Tokens = 30 },
		},
	},
	{
		Id = "TreasureHunt",
		Name = "Great Treasure Hunt",
		Icon = "🗺️",
		Season = 3,
		Day = 7,
		Hours = { 8, 20 },
		Description = "Rook buried treasure all over the village. Follow the clues and dig!",
		Decor = "Autumn",
		Music = "Festival",
		Activities = {
			{
				Kind = "Scavenger",
				Id = "treasure",
				Name = "Buried Treasure",
				Icon = "🧰",
				Count = 12,
				Tokens = 12,
				Model = "Chest",
				Dig = true,
			},
		},
		Shop = {
			{ Id = "treasure_chest", Price = 60 },
			{ Id = "omni_geode", Price = 30 },
			{ Id = "warp_home", Price = 4 },
		},
		Challenges = {
			{ Id = "th_find", Text = "Dig up 6 treasures", Type = "Scavenger", Count = 6, Tokens = 50 },
		},
		Prizes = { Entry = { Tokens = 20 } },
	},
	{
		Id = "WinterLantern",
		Name = "Winter Lantern Night",
		Icon = "🏮",
		Season = 4,
		Day = 3,
		Hours = { 16, 24 },
		Description = "Collect glowing lanterns and release them over the lake. The Frost Orchid seed stall opens.",
		Decor = "Winter",
		Weather = "Snow",
		Music = "Winter",
		Activities = {
			{
				Kind = "Scavenger",
				Id = "lanterns",
				Name = "Lantern Gathering",
				Icon = "🏮",
				Count = 20,
				Tokens = 6,
				Model = "Lantern",
			},
			{
				Kind = "Contest",
				Id = "winter_gift",
				Name = "Winter Gift Swap",
				Icon = "🎁",
				Accept = { "*" },
				Scoring = { Quality = 30, Size = 0, Rarity = 40, Mutations = 30, Care = 0 },
			},
		},
		Shop = {
			{ Id = "seed_frost_orchid", Price = 120, Stock = 2 },
			{ Id = "winter_pine", Price = 80 },
			{ Id = "snowman", Price = 20 },
			{ Id = "lantern_garland", Price = 40 },
			{ Id = "hot_chocolate", Price = 5 },
		},
		Challenges = {
			{ Id = "wl_lanterns", Text = "Gather 12 lanterns", Type = "Scavenger", Count = 12, Tokens = 50 },
		},
		Prizes = {
			First = { Coins = 12000, Tokens = 160, Items = { { "lantern_of_winter", 1 } }, Title = "Lantern Keeper" },
			Second = { Coins = 6000, Tokens = 90 },
			Third = { Coins = 3000, Tokens = 60 },
			Entry = { Tokens = 25 },
		},
	},
	{
		Id = "FrostRace",
		Name = "Frost Races",
		Icon = "⛸️",
		Season = 4,
		Day = 6,
		Hours = { 9, 18 },
		Description = "Race through the snowy village checkpoints. Horses allowed!",
		Decor = "Winter",
		Music = "Festival",
		Activities = {
			{
				Kind = "Race",
				Id = "frost_race",
				Name = "Village Dash",
				Icon = "🏁",
				Checkpoints = {
					Vector3.new(0, 0, 30),
					Vector3.new(-100, 0, 0),
					Vector3.new(-106, 0, -106),
					Vector3.new(0, 0, -150),
					Vector3.new(106, 0, -106),
					Vector3.new(150, 0, 0),
					Vector3.new(106, 0, 106),
					Vector3.new(0, 0, 150),
					Vector3.new(0, 0, 30),
				},
			},
		},
		Shop = {
			{ Id = "speed_potion", Price = 12 },
			{ Id = "snowman", Price = 20 },
			{ Id = "street_lamp", Price = 25 },
		},
		Challenges = {
			{ Id = "fr_race", Text = "Finish the race 3 times", Type = "Race", Count = 3, Tokens = 50 },
		},
		Prizes = {
			First = { Coins = 10000, Tokens = 150, Title = "Frostfoot" },
			Second = { Coins = 5000, Tokens = 90 },
			Third = { Coins = 2500, Tokens = 60 },
			Entry = { Tokens = 20 },
		},
	},
}

return {
	List = List,
	-- Night Market: every Saturday evening once the Festival Square project is done.
	NightMarket = { Weekday = 6, Hours = { 18, 24 }, Project = "festival_square", SellBonus = 0.1 },
	Currency = { Id = "Tokens", Name = "Festival Tokens", Icon = "🎟️" },
	ScavengerReach = 10,
}

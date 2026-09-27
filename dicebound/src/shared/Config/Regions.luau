-- The five regions. Positions are {x, y, z} in studs; ground level of each region is its Origin.y.
--
--   Bounds       box (relative to Origin) where you count as "in" the region. Rolls use the
--                loot table of the region you stand in when the server accepts the roll.
--   Merchant     where the merchant stands (relative to Origin). Selling requires being nearby.
--   Stall        the second stall (west side): which panel its prompt opens.
--   Portal       the travel stone that opens the map.
--   CollectionReward  coins for discovering every item of the region (claimed in the book).
--   Unlock       what it costs to open. Coins are spent; Discoveries is the number of unique
--                items you must have discovered in the previous region (never spent).
--   JackpotCoins bonus coins for a Jackpot combo rolled here.
--   Palette      colors used by the world builder and the region banner.

local Regions = {
	List = {
		{
			Id = "meadow",
			Stall = {
				Position = { -30, 0, 0 },
				Name = "Tobble the Tinkerer",
				Title = "Upgrades",
				Panel = "Upgrades",
				Action = "Upgrades & crafting",
			},
			CollectionReward = 1000,
			Name = "Meadow Market",
			Stage = 1,
			Tagline = "Where every treasure hunter rolls their first die.",
			Origin = { 0, 0, 0 },
			Bounds = { Center = { 0, 30, 0 }, Size = { 220, 90, 220 } },
			Merchant = { Position = { 30, 0, 0 }, Name = "Marta the Merchant" },
			SpawnPosition = { 0, 0, 44 },
			Portal = { 0, 0, -86 },
			Unlock = { Coins = 0 },
			JackpotCoins = 250,
			RevisitReason = "Home of the Golden Goose Egg and the cheapest merchant orders.",
			Palette = {
				Ground = { 110, 170, 80 },
				Path = { 200, 180, 140 },
				Accent = { 255, 200, 120 },
				Banner = { 120, 190, 90 },
			},
		},
		{
			Id = "crystal",
			Stall = {
				Position = { -30, 0, 0 },
				Name = "Quill the Dicewright",
				Title = "Dice Shop",
				Panel = "Dice",
				Action = "Browse dice",
			},
			CollectionReward = 6000,
			Name = "Crystal Caverns",
			Stage = 2,
			Tagline = "Glowing tunnels full of gems and very small frogs.",
			Origin = { 0, 0, -260 },
			Bounds = { Center = { 0, 30, 0 }, Size = { 200, 90, 200 } },
			Merchant = { Position = { 30, 0, 0 }, Name = "Glim the Gemcutter" },
			SpawnPosition = { 0, 0, 44 },
			Portal = { 0, 0, -86 },
			Unlock = { Coins = 2500, Discoveries = 6 },
			JackpotCoins = 700,
			RevisitReason = "Glass and Clover dice are sold here.",
			Palette = {
				Ground = { 60, 55, 80 },
				Path = { 90, 80, 120 },
				Accent = { 120, 220, 255 },
				Banner = { 130, 100, 220 },
			},
		},
		{
			Id = "frost",
			Stall = {
				Position = { -30, 0, 0 },
				Name = "Nessa the Carver",
				Title = "Workbench",
				Panel = "Craft",
				Action = "Craft",
			},
			CollectionReward = 40000,
			Name = "Frostfall Village",
			Stage = 2,
			Tagline = "Cozy lanterns, northern lights, and treasure frozen in time.",
			Origin = { -300, 0, -260 },
			Bounds = { Center = { 0, 30, 0 }, Size = { 200, 90, 200 } },
			Merchant = { Position = { 30, 0, 0 }, Name = "Old Pim" },
			SpawnPosition = { 0, 0, 44 },
			Portal = { 0, 0, -86 },
			Unlock = { Coins = 30000, Discoveries = 7 },
			JackpotCoins = 2000,
			RevisitReason = "Frozen mutations are native here, and the Frost Die shines.",
			Palette = {
				Ground = { 235, 240, 250 },
				Path = { 180, 190, 210 },
				Accent = { 140, 255, 200 },
				Banner = { 120, 190, 255 },
			},
		},
		{
			Id = "ember",
			Stall = {
				Position = { -30, 0, 0 },
				Name = "Forgemaster Ulf",
				Title = "Dice Forge",
				Panel = "Dice",
				Action = "Browse dice",
			},
			CollectionReward = 150000,
			Name = "Emberforge",
			Stage = 2,
			Tagline = "A volcanic workshop where dice are forged and beetles tick.",
			Origin = { 300, 0, -260 },
			Bounds = { Center = { 0, 30, 0 }, Size = { 200, 90, 200 } },
			Merchant = { Position = { 30, 0, 0 }, Name = "Brakka the Smith" },
			SpawnPosition = { 0, 0, 44 },
			Portal = { 0, 0, -86 },
			Unlock = { Coins = 400000, Discoveries = 7 },
			JackpotCoins = 5000,
			RevisitReason = "Golden mutations run hot here, and the Magma Die is forged on site.",
			Palette = {
				Ground = { 50, 40, 40 },
				Path = { 90, 70, 60 },
				Accent = { 255, 110, 40 },
				Banner = { 230, 90, 40 },
			},
		},
		{
			Id = "astral",
			Stall = {
				Position = { -30, 0, 0 },
				Name = "The Archivist",
				Title = "Collection",
				Panel = "Book",
				Action = "Open collection book",
			},
			CollectionReward = 600000,
			Name = "Astral Sanctuary",
			Stage = 2,
			Tagline = "Floating islands among the stars, scattered with moon relics.",
			Origin = { 0, 60, -560 },
			Bounds = { Center = { 0, 30, 0 }, Size = { 220, 110, 220 } },
			Merchant = { Position = { 30, 0, 0 }, Name = "The Stargazer" },
			SpawnPosition = { 0, 0, 44 },
			Portal = { 0, 0, -86 },
			Unlock = { Coins = 3000000, Discoveries = 7 },
			JackpotCoins = 12000,
			RevisitReason = "Cosmic mutations and the Celestial Die's crafting materials.",
			Palette = {
				Ground = { 60, 50, 110 },
				Path = { 200, 190, 255 },
				Accent = { 255, 240, 170 },
				Banner = { 90, 70, 200 },
			},
		},
	},
	ById = {},
}

for index, region in Regions.List do
	region.Order = index
	Regions.ById[region.Id] = region
end

-- The region before this one in unlock order (nil for the first).
function Regions.Previous(regionId: string): { [string]: any }?
	local region = Regions.ById[regionId]
	return if region and region.Order > 1 then Regions.List[region.Order - 1] else nil
end

-- True if a world position {x, y, z} lies inside a region's bounds.
function Regions.Contains(region: { [string]: any }, x: number, y: number, z: number): boolean
	local origin, center, size = region.Origin, region.Bounds.Center, region.Bounds.Size
	return math.abs(x - (origin[1] + center[1])) <= size[1] / 2
		and math.abs(y - (origin[2] + center[2])) <= size[2] / 2
		and math.abs(z - (origin[3] + center[3])) <= size[3] / 2
end

return Regions

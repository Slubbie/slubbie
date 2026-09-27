-- Farm land: parcels, farmhouse upgrades and town projects.
--
-- A farm is a 5×5 grid of parcels (Config/World.Farms). You start owning the
-- centre-front parcel. Each parcel has a type that changes what's there and
-- gives its soil a character. Buying parcels costs more the more you own.

export type ParcelType = {
	Id: string,
	Name: string,
	Icon: string,
	Description: string,
	Soil: { Health: number?, N: number?, P: number?, K: number?, Moisture: number? },
	Clear: { string }?, -- resource nodes that start on it (cleared by chopping/mining)
	Tags: { string }, -- environment tags for crops/animals on this parcel
	Water: boolean?, -- has a pond
	Color: Color3,
}

local hex = Color3.fromHex

local Types: { [string]: ParcelType } = {
	Homestead = { Id = "Homestead", Name = "Homestead", Icon = "🏡", Description = "Good all-round soil.", Soil = {}, Tags = {}, Color = hex("#7cb35b") },
	Field = { Id = "Field", Name = "Open Field", Icon = "🌾", Description = "Flat and fertile. Great for big crops.", Soil = { Health = 8, N = 10 }, Tags = { "Field" }, Color = hex("#9ccc65") },
	Meadow = { Id = "Meadow", Name = "Wildflower Meadow", Icon = "🌼", Description = "Bees and pollinators love it here.", Soil = { P = 10 }, Tags = { "Meadow" }, Color = hex("#c5e1a5") },
	Forest = { Id = "Forest", Name = "Woodland", Icon = "🌲", Description = "Clear the trees for wood; wild traits are common here.", Soil = { Health = 12, K = 8 }, Clear = { "oak", "oak", "pine", "birch", "maple", "rock" }, Tags = { "Forest" }, Color = hex("#558b2f") },
	Riverside = { Id = "Riverside", Name = "Riverside", Icon = "💧", Description = "A pond and wet soil: rice and thirsty crops thrive.", Soil = { Moisture = 60, N = 5 }, Tags = { "Riverside" }, Water = true, Color = hex("#4db6ac") },
	Hillside = { Id = "Hillside", Name = "Sunny Hillside", Icon = "⛰️", Description = "Sun-drenched slope. Orchards and vines ripen sweeter.", Soil = { K = 12 }, Clear = { "rock", "rock", "copper_node" }, Tags = { "Hillside" }, Color = hex("#aed581") },
	Pasture = { Id = "Pasture", Name = "Pasture", Icon = "🐑", Description = "Animals housed here are happier.", Soil = { N = 8 }, Tags = { "Pasture" }, Color = hex("#8bc34a") },
}

-- Parcel layout for every farm, row by row from the front (z = 0, next to the yard).
-- The front-centre parcel ("c1") is the starter.
local Layout = {
	{ "Field", "Meadow", "Homestead", "Pasture", "Field" },
	{ "Forest", "Field", "Field", "Field", "Riverside" },
	{ "Forest", "Meadow", "Hillside", "Pasture", "Riverside" },
	{ "Forest", "Field", "Hillside", "Field", "Meadow" },
	{ "Forest", "Hillside", "Hillside", "Pasture", "Riverside" },
}

local House = {
	{ Name = "Cabin", Cost = 0, Mats = {}, Storage = 0, Energy = 0, Description = "A cosy one-room cabin." },
	{ Name = "Cottage", Cost = 12000, Mats = { { Id = "wood", N = 300 } }, Level = 3, Storage = 24, Energy = 20, Description = "+24 home storage, +20 max energy, a kitchen corner." },
	{ Name = "Farmhouse", Cost = 60000, Mats = { { Id = "hardwood", N = 120 }, { Id = "stone_brick", N = 80 } }, Level = 8, Storage = 48, Energy = 40, Description = "+48 storage, +40 energy, a porch and a second floor." },
	{ Name = "Manor", Cost = 250000, Mats = { { Id = "hardwood", N = 300 }, { Id = "glass", N = 80 }, { Id = "gold_bar", N = 10 } }, Level = 15, Storage = 96, Energy = 70, Description = "+96 storage, +70 energy, a trophy hall." },
	{ Name = "Estate", Cost = 1200000, Mats = { { Id = "ancient_wood", N = 20 }, { Id = "refined_crystal", N = 20 }, { Id = "starsteel_bar", N = 10 } }, Level = 25, Storage = 160, Energy = 110, Description = "The grandest house in the valley. +160 storage, +110 energy." },
}

-- Town projects: fund them with coins and items. Completing one changes the
-- village for you (new buildings, NPCs, stalls) and can unlock regions.
local Projects = {
	{ Id = "market_stalls", Name = "Reopen the Market", Icon = "🏪", Description = "Rebuild the market stalls so traders return.", Cost = 5000, Items = { { "wood", 100 }, { "#Crop", 30 } }, Unlocks = { "Market stalls", "Contracts board" }, Estate = 2 },
	{ Id = "lab_restore", Name = "Restore the Lab", Icon = "🧪", Description = "Juniper needs power and glass to reopen her lab.", Cost = 15000, Items = { { "glass", 20 }, { "copper_bar", 10 } }, Unlocks = { "Vale Research Lab" }, Estate = 4, Requires = "market_stalls" },
	{ Id = "coast_road", Name = "Coast Road", Icon = "🛣️", Description = "Clear the road to Sunpetal Coast.", Cost = 20000, Items = { { "stone", 200 }, { "wood", 150 } }, Unlocks = { "Sunpetal Coast road" }, Estate = 3 },
	{ Id = "workshop_power", Name = "Power the Workshop", Icon = "⚡", Description = "Wire Nell's workshop to the windmill.", Cost = 30000, Items = { { "copper_bar", 20 }, { "battery", 2 } }, Unlocks = { "Sparks Engineering" }, Estate = 8 },
	{ Id = "caravan_route", Name = "Caravan Route", Icon = "🐪", Description = "Mark a safe route to the Dunewind oasis.", Cost = 60000, Items = { { "rope", 40 }, { "#Fruit", 60 }, { "campfire", 5 } }, Unlocks = { "Dunewind Desert" }, Estate = 8 },
	{ Id = "mountain_pass", Name = "Mountain Pass", Icon = "🏔️", Description = "Build a lodge and heated pass into Frostveil.", Cost = 90000, Items = { { "hardwood", 80 }, { "coal", 60 }, { "cloth", 10 } }, Unlocks = { "Frostveil Valley" }, Estate = 10 },
	{ Id = "guild_hall", Name = "Cooperative Hall", Icon = "🤝", Description = "A hall where farming cooperatives meet.", Cost = 50000, Items = { { "plank", 100 }, { "stone_brick", 100 } }, Unlocks = { "Cooperatives" }, Estate = 6 },
	{ Id = "festival_square", Name = "Festival Square", Icon = "🎪", Description = "A permanent stage and lanterns for every festival.", Cost = 40000, Items = { { "cloth", 12 }, { "lantern_post", 8 } }, Unlocks = { "Bigger festivals", "Night Market" }, Estate = 5 },
	{ Id = "orchard_row", Name = "Village Orchard", Icon = "🍎", Description = "Plant fruit trees along the village roads.", Cost = 25000, Items = { { "seed_apple", 4 }, { "seed_cherry", 4 } }, Unlocks = { "Village orchard (free fruit daily)" }, Estate = 5 },
	{ Id = "grand_museum", Name = "Museum Wing", Icon = "🏛️", Description = "A new wing for your donated discoveries.", Cost = 120000, Items = { { "#Artifact", 15 }, { "#Gem", 15 } }, Unlocks = { "Museum wing", "Legendary collector contracts" }, Estate = 12 },
}

return {
	Types = Types,
	Layout = Layout,
	House = House,
	Projects = Projects,
	Starter = { Row = 1, Col = 3 },
	-- Parcel price = Base × Growth^(owned - 1), plus materials from the 6th parcel on.
	ParcelBase = 2500,
	ParcelGrowth = 1.45,
	ParcelMats = { { Id = "wood", N = 60 }, { Id = "stone", N = 40 } },
	-- Parcels must touch one you already own.
	RequireAdjacent = true,
}

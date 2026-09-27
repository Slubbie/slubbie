-- Tools and their upgrade tiers.
--
-- Every player owns one of each tool family ("tool_<family>" items live in the
-- inventory and can't be sold/traded/trashed). The tier is stored in the save
-- and upgraded at Bram's forge. Higher tiers unlock bigger areas of effect,
-- lower energy costs, and special abilities.
--
-- Area sizes are square N×N centred on the target tile (players can choose any
-- size up to MaxArea with the scroll wheel / D-pad / area button).

export type Tier = {
	Name: string,
	Color: Color3,
	Material: string,
	Cost: number,
	Mats: { { Id: string, N: number } },
	Level: number, -- skill level required (for the family's skill)
	MaxArea: number,
	Energy: number, -- energy per tile at this tier
	Speed: number, -- action cooldown multiplier (lower = faster)
	Power: number, -- node damage per hit (axe/pickaxe), rod zone bonus, etc.
	Capacity: number?, -- watering can water
	Quality: number?, -- quality score bonus (sickle/pruners)
	Ability: string?,
}

export type Family = {
	Id: string,
	Name: string,
	Icon: string,
	Skill: string,
	Action: string,
	Description: string,
	Tiers: { Tier },
	Starter: boolean,
}

local TIER_LOOK = {
	{ Name = "Rusty", Color = Color3.fromRGB(150, 110, 80), Material = "CorrodedMetal" },
	{ Name = "Copper", Color = Color3.fromRGB(214, 128, 70), Material = "Metal" },
	{ Name = "Iron", Color = Color3.fromRGB(190, 196, 204), Material = "Metal" },
	{ Name = "Gold", Color = Color3.fromRGB(255, 204, 70), Material = "Foil" },
	{ Name = "Crystal", Color = Color3.fromRGB(150, 230, 255), Material = "Glass" },
	{ Name = "Starsteel", Color = Color3.fromRGB(170, 130, 255), Material = "Neon" },
}

local COSTS = {
	{ Cost = 0, Mats = {}, Level = 1 },
	{ Cost = 1500, Mats = { { Id = "copper_bar", N = 5 } }, Level = 3 },
	{ Cost = 6000, Mats = { { Id = "iron_bar", N = 5 } }, Level = 8 },
	{ Cost = 20000, Mats = { { Id = "gold_bar", N = 5 } }, Level = 14 },
	{ Cost = 60000, Mats = { { Id = "refined_crystal", N = 5 }, { Id = "gold_bar", N = 3 } }, Level = 22 },
	{ Cost = 200000, Mats = { { Id = "starsteel_bar", N = 5 }, { Id = "refined_crystal", N = 3 } }, Level = 32 },
}

local function tiers(perTier: { { [string]: any } }): { Tier }
	local out = {}
	for i, extra in perTier do
		local tier: any = {
			Name = TIER_LOOK[i].Name,
			Color = TIER_LOOK[i].Color,
			Material = TIER_LOOK[i].Material,
			Cost = COSTS[i].Cost,
			Mats = COSTS[i].Mats,
			Level = COSTS[i].Level,
			MaxArea = 1,
			Energy = 1,
			Speed = 1,
			Power = 1,
		}
		for key, value in extra do
			tier[key] = value
		end
		out[i] = tier
	end
	return out
end

local Families: { Family } = {
	{
		Id = "hoe",
		Name = "Hoe",
		Icon = "⛏️",
		Skill = "Farming",
		Action = "Till",
		Starter = true,
		Description = "Tills grass into farmland. Hit tilled soil again to clear it.",
		Tiers = tiers({
			{ MaxArea = 1, Energy = 2 },
			{ MaxArea = 3, Energy = 1.6 },
			{ MaxArea = 3, Energy = 1.2, Speed = 0.8 },
			{ MaxArea = 5, Energy = 1, Speed = 0.7 },
			{ MaxArea = 5, Energy = 0.6, Speed = 0.6, Ability = "Tilled soil gains +10 health." },
			{ MaxArea = 7, Energy = 0.4, Speed = 0.5, Ability = "Tilled soil starts fully watered." },
		}),
	},
	{
		Id = "can",
		Name = "Watering Can",
		Icon = "🚿",
		Skill = "Farming",
		Action = "Water",
		Starter = true,
		Description = "Waters soil. Refill at any water: wells, ponds, rivers.",
		Tiers = tiers({
			{ MaxArea = 1, Energy = 1, Capacity = 25 },
			{ MaxArea = 3, Energy = 0.8, Capacity = 55 },
			{ MaxArea = 3, Energy = 0.6, Capacity = 90, Speed = 0.8 },
			{ MaxArea = 5, Energy = 0.4, Capacity = 140, Speed = 0.7 },
			{ MaxArea = 5, Energy = 0.3, Capacity = 220, Speed = 0.6, Ability = "Watered soil drains 25% slower." },
			{ MaxArea = 7, Energy = 0.2, Capacity = 9999, Speed = 0.5, Ability = "Never runs dry." },
		}),
	},
	{
		Id = "sickle",
		Name = "Sickle",
		Icon = "🌙",
		Skill = "Farming",
		Action = "Harvest",
		Starter = true,
		Description = "Harvests ripe crops and cuts grass into fiber. Better sickles keep more quality.",
		Tiers = tiers({
			{ MaxArea = 1, Energy = 0, Quality = 0 },
			{ MaxArea = 3, Energy = 0, Quality = 0.01 },
			{ MaxArea = 3, Energy = 0, Quality = 0.02, Speed = 0.8 },
			{ MaxArea = 5, Energy = 0, Quality = 0.03, Speed = 0.7 },
			{ MaxArea = 5, Energy = 0, Quality = 0.045, Speed = 0.6, Ability = "+5% chance of a bonus item." },
			{ MaxArea = 7, Energy = 0, Quality = 0.06, Speed = 0.5, Ability = "+10% chance of a bonus item." },
		}),
	},
	{
		Id = "axe",
		Name = "Axe",
		Icon = "🪓",
		Skill = "Foraging",
		Action = "Chop",
		Starter = true,
		Description = "Chops trees and clears stumps. Hardwood needs an Iron Axe.",
		Tiers = tiers({
			{ Energy = 2, Power = 1 },
			{ Energy = 1.8, Power = 1.5 },
			{ Energy = 1.5, Power = 2.2, Speed = 0.85 },
			{ Energy = 1.2, Power = 3, Speed = 0.75 },
			{ Energy = 1, Power = 4, Speed = 0.65, Ability = "Double wood 10% of the time." },
			{ Energy = 0.8, Power = 6, Speed = 0.55, Ability = "Double wood 20% of the time." },
		}),
	},
	{
		Id = "pickaxe",
		Name = "Pickaxe",
		Icon = "⛏️",
		Skill = "Mining",
		Action = "Mine",
		Starter = true,
		Description = "Breaks rocks and ore. Harder ores need better pickaxes.",
		Tiers = tiers({
			{ Energy = 2, Power = 1 },
			{ Energy = 1.8, Power = 1.5 },
			{ Energy = 1.5, Power = 2.2, Speed = 0.85 },
			{ Energy = 1.2, Power = 3, Speed = 0.75 },
			{ Energy = 1, Power = 4, Speed = 0.65, Ability = "Gems drop 25% more often." },
			{ Energy = 0.8, Power = 6, Speed = 0.55, Ability = "Gems drop 50% more often." },
		}),
	},
	{
		Id = "shovel",
		Name = "Shovel",
		Icon = "🪏",
		Skill = "Exploration",
		Action = "Dig",
		Starter = true,
		Description = "Digs up dig spots, clay and worms. Removes planted crops (returns the seed if unsprouted).",
		Tiers = tiers({
			{ Energy = 2, Power = 1 },
			{ Energy = 1.6, Power = 1.2 },
			{ Energy = 1.3, Power = 1.4 },
			{ Energy = 1, Power = 1.6, Ability = "Artifacts 20% more often." },
			{ Energy = 0.8, Power = 1.8, Ability = "Artifacts 35% more often." },
			{ Energy = 0.6, Power = 2, Ability = "Artifacts 50% more often." },
		}),
	},
	{
		Id = "rod",
		Name = "Fishing Rod",
		Icon = "🎣",
		Skill = "Fishing",
		Action = "Fish",
		Starter = true,
		Description = "Cast into any water. Better rods have a bigger catch zone and reel faster.",
		Tiers = tiers({
			{ Energy = 3, Power = 0 },
			{ Energy = 2.5, Power = 1 },
			{ Energy = 2, Power = 2, Ability = "Can use bait." },
			{ Energy = 1.6, Power = 3, Ability = "Treasure 50% more often." },
			{ Energy = 1.3, Power = 4, Ability = "Legendary fish are less erratic." },
			{ Energy = 1, Power = 5, Ability = "Every catch is at least Fine quality." },
		}),
	},
	{
		Id = "net",
		Name = "Bug Net",
		Icon = "🥅",
		Skill = "Foraging",
		Action = "Catch",
		Starter = true,
		Description = "Swing at bugs to catch them.",
		Tiers = tiers({
			{ Energy = 1, Power = 1 },
			{ Energy = 0.9, Power = 1.25 },
			{ Energy = 0.8, Power = 1.5 },
			{ Energy = 0.7, Power = 1.75, Ability = "Bugs flee less." },
			{ Energy = 0.6, Power = 2 },
			{ Energy = 0.5, Power = 2.5, Ability = "Rare bugs appear more often." },
		}),
	},
	{
		Id = "pruners",
		Name = "Pruning Shears",
		Icon = "✂️",
		Skill = "Farming",
		Action = "Prune",
		Starter = false,
		Description = "Prune bushes, vines and trees once per growth cycle for better quality and yield.",
		Tiers = tiers({
			{ MaxArea = 1, Energy = 1, Quality = 0.04 },
			{ MaxArea = 1, Energy = 0.8, Quality = 0.05 },
			{ MaxArea = 3, Energy = 0.6, Quality = 0.06 },
			{ MaxArea = 3, Energy = 0.5, Quality = 0.07 },
			{ MaxArea = 5, Energy = 0.4, Quality = 0.08 },
			{ MaxArea = 5, Energy = 0.3, Quality = 0.1 },
		}),
	},
	{
		Id = "seeder",
		Name = "Seed Pouch",
		Icon = "🌱",
		Skill = "Farming",
		Action = "Plant",
		Starter = true,
		Description = "Passive: how many tiles you can sow at once with a seed.",
		Tiers = tiers({
			{ MaxArea = 1, Energy = 0 },
			{ MaxArea = 3, Energy = 0 },
			{ MaxArea = 3, Energy = 0 },
			{ MaxArea = 5, Energy = 0 },
			{ MaxArea = 5, Energy = 0 },
			{ MaxArea = 7, Energy = 0 },
		}),
	},
}

-- Powered equipment: crafted/bought, equipped like tools, unlocked late.
local Powered = {
	{
		Id = "tractor",
		Name = "Tractor",
		Icon = "🚜",
		Description = "Drive over your fields. Pick a mode: Plow, Sow, Water or Harvest; it works a 3-wide strip as you drive.",
		Width = 3,
		Speed = 26,
		EnergyPerTile = 0,
		Fuel = "battery", -- one battery = FuelTiles tiles
		FuelTiles = 400,
		Level = 18,
	},
	{
		Id = "hover_tractor",
		Name = "Hover Harvester",
		Icon = "🛸",
		Description = "Like the tractor, but 5 wide, faster, and works on every mode at once.",
		Width = 5,
		Speed = 34,
		EnergyPerTile = 0,
		Fuel = "battery",
		FuelTiles = 900,
		Level = 30,
	},
	{
		Id = "drone_remote",
		Name = "Drone Remote",
		Icon = "🎮",
		Description = "Send your drone to water or harvest a 5×5 area up to 80 studs away.",
		Width = 5,
		Range = 80,
		Fuel = "battery",
		FuelTiles = 300,
		Level = 22,
	},
}

return {
	Families = Families,
	Powered = Powered,
	TierLook = TIER_LOOK,
	-- Studs from the character to a target tile.
	Reach = 22,
	-- Base action cooldown in seconds (× tier Speed).
	Cooldown = 0.32,
}

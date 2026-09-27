-- Crafting recipes and the cosmetics they create. Crafting turns duplicate treasure into special
-- dice and cosmetics. Locked items are NEVER used; plain (unmutated) copies are used first.
--
--   Kind      "Die" (grants a die), "Aura" (particles around your character, visible to everyone)
--             or "Tray" (a new felt for your dice tray)
--   Grants    the die / aura / tray id
--   Needs     { { Id = itemId, Qty = n }, ... }
--   Coins     crafting fee

local Crafting = {
	Recipes = {
		{
			Id = "craft_celestial",
			Kind = "Die",
			Grants = "celestial",
			Name = "Celestial Die",
			Needs = {
				{ Id = "astral_moon_fragment", Qty = 8 },
				{ Id = "astral_stardust", Qty = 8 },
				{ Id = "astral_constellation_owl", Qty = 3 },
				{ Id = "astral_starbound_compass", Qty = 1 },
			},
			Coins = 50000,
		},
		{
			Id = "craft_petals",
			Kind = "Aura",
			Grants = "petals",
			Name = "Petal Drift Aura",
			Needs = {
				{ Id = "meadow_acorn", Qty = 10 },
				{ Id = "meadow_old_coin", Qty = 10 },
				{ Id = "meadow_teacup_snail", Qty = 3 },
			},
			Coins = 400,
		},
		{
			Id = "craft_tray_royal",
			Kind = "Tray",
			Grants = "royal",
			Name = "Royal Velvet Tray",
			Needs = {
				{ Id = "meadow_prize_ribbon", Qty = 4 },
				{ Id = "meadow_sunhoney", Qty = 2 },
			},
			Coins = 600,
		},
		{
			Id = "craft_glimmer",
			Kind = "Aura",
			Grants = "glimmer",
			Name = "Crystal Glimmer Aura",
			Needs = {
				{ Id = "crystal_glowpebble", Qty = 10 },
				{ Id = "crystal_echo_shell", Qty = 10 },
				{ Id = "crystal_tiny_frog", Qty = 3 },
			},
			Coins = 4000,
		},
		{
			Id = "craft_tray_geode",
			Kind = "Tray",
			Grants = "geode",
			Name = "Amethyst Geode Tray",
			Needs = {
				{ Id = "crystal_hollow_geode", Qty = 5 },
				{ Id = "crystal_singing_prism", Qty = 2 },
			},
			Coins = 6000,
		},
		{
			Id = "craft_snowfall",
			Kind = "Aura",
			Grants = "snowfall",
			Name = "Snowfall Aura",
			Needs = {
				{ Id = "frost_lost_mitten", Qty = 10 },
				{ Id = "frost_perfect_icicle", Qty = 10 },
				{ Id = "frost_clockwork_penguin", Qty = 3 },
			},
			Coins = 25000,
		},
		{
			Id = "craft_embers",
			Kind = "Aura",
			Grants = "embers",
			Name = "Ember Sparks Aura",
			Needs = {
				{ Id = "ember_forge_rivet", Qty = 10 },
				{ Id = "ember_smiling_coal", Qty = 10 },
				{ Id = "ember_mechanical_beetle", Qty = 3 },
			},
			Coins = 80000,
		},
		{
			Id = "craft_tray_obsidian",
			Kind = "Tray",
			Grants = "obsidian",
			Name = "Obsidian Forge Tray",
			Needs = {
				{ Id = "ember_obsidian_shard", Qty = 3 },
				{ Id = "ember_brass_gearheart", Qty = 4 },
			},
			Coins = 90000,
		},
		{
			Id = "craft_starlight",
			Kind = "Aura",
			Grants = "starlight",
			Name = "Starlight Aura",
			Needs = {
				{ Id = "astral_stardust", Qty = 10 },
				{ Id = "astral_moon_fragment", Qty = 10 },
				{ Id = "astral_comet_ribbon", Qty = 3 },
			},
			Coins = 250000,
		},
	},
	ById = {},

	-- Auras: particle effects around your character.
	Auras = {
		petals = { Name = "Petal Drift", Color = { 255, 170, 200 }, Rate = 6, Size = 0.5 },
		glimmer = { Name = "Crystal Glimmer", Color = { 150, 220, 255 }, Rate = 8, Size = 0.4 },
		snowfall = { Name = "Snowfall", Color = { 240, 250, 255 }, Rate = 10, Size = 0.35 },
		embers = { Name = "Ember Sparks", Color = { 255, 130, 40 }, Rate = 10, Size = 0.3 },
		starlight = { Name = "Starlight", Color = { 255, 240, 170 }, Rate = 9, Size = 0.45 },
	},

	-- Dice tray felts. "classic" is free for everyone.
	Trays = {
		classic = { Name = "Classic Felt", Color = { 70, 130, 80 }, Material = "Fabric" },
		royal = { Name = "Royal Velvet", Color = { 120, 40, 90 }, Material = "Fabric" },
		geode = { Name = "Amethyst Geode", Color = { 110, 70, 170 }, Material = "Glass" },
		obsidian = { Name = "Obsidian Forge", Color = { 35, 25, 30 }, Material = "Basalt" },
	},
}

for _, recipe in Crafting.Recipes do
	Crafting.ById[recipe.Id] = recipe
end

return Crafting

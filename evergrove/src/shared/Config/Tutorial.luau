-- The onboarding tutorial. Each step waits for a real game event (the server
-- confirms it happened) before moving on. Players can skip at any time.
--
-- Target: where the arrow points ("Tile" = your farm's first field tiles,
-- "Bin", "Chest", "Well", "Npc:<id>", "Hotbar:<slot>", "Menu:<screen>").

return {
	Steps = {
		{ Id = "welcome", Title = "Welcome to Evergrove!", Text = "This little plot is yours now. Let's get it growing. Mabel will show you the basics.", Wait = "Ack", Target = "Npc:mabel", Speaker = "mabel" },
		{ Id = "till", Title = "Till the Soil", Text = "Select your Hoe (slot 1) and click the grass to till 4 tiles.", Wait = "Till", Count = 4, Target = "Tile", Hotbar = 1 },
		{ Id = "plant", Title = "Plant Seeds", Text = "Select Carrot Seeds and click the tilled soil to plant them.", Wait = "Plant", Count = 4, Target = "Tile", Hotbar = 4 },
		{ Id = "water", Title = "Water Your Crops", Text = "Select the Watering Can (slot 2) and water the seeds. Dry soil means slow growth!", Wait = "Water", Count = 4, Target = "Tile", Hotbar = 2 },
		{ Id = "refill", Title = "Refill at the Well", Text = "Your can holds limited water. Click the well (or any pond or river) with the can to refill it.", Wait = "Refill", Count = 1, Target = "Well", Hotbar = 2 },
		{ Id = "fertilize", Title = "Fertilize", Text = "Compost feeds the soil. Select it and apply it to one of your crops.", Wait = "Fertilize", Count = 1, Target = "Tile", Hotbar = 5 },
		{ Id = "soil", Title = "Reading Your Soil", Text = "Hover over a tile to see its moisture, soil health and growth. Keep crops in their water band for better quality!", Wait = "Ack", Target = "Tile" },
		{ Id = "grow", Title = "Let Them Grow", Text = "Crops grow in real time, even while you're away. For your first harvest, Mabel's magic compost speeds things up!", Wait = "Ripe", Count = 1, Target = "Tile", Boost = 12 },
		{ Id = "harvest", Title = "Harvest", Text = "Select the Sickle (slot 3) and harvest your ripe carrots.", Wait = "Harvest", Count = 4, Target = "Tile", Hotbar = 3 },
		{ Id = "store", Title = "Storage", Text = "Open your inventory (Tab / B) and drag one carrot into the chest next to your house. Chests keep things safe.", Wait = "Store", Count = 1, Target = "Chest" },
		{ Id = "sell", Title = "Sell Your Harvest", Text = "Drop carrots in the Shipping Bin. You'll be paid at 6 AM at the market price. Or sell instantly to Pip in town.", Wait = "Sell", Count = 1, Target = "Bin" },
		{ Id = "upgrade", Title = "Grow Your Farm", Text = "Open the Farm menu (F) to see land you can buy. For now, buy more seeds from Pip in the village!", Wait = "Buy", Count = 1, Target = "Npc:pip" },
		{ Id = "world", Title = "The World Awaits", Text = "Talk to villagers, fish, forage and explore. Your quest log (J) always shows what to do next. Have fun!", Wait = "Ack", Target = "Menu:Quests" },
	},
	-- Starter kit given with a fresh save.
	StarterItems = {
		{ "tool_hoe", 1 },
		{ "tool_can", 1 },
		{ "tool_sickle", 1 },
		{ "seed_carrot", 12 },
		{ "compost", 5 },
		{ "tool_axe", 1 },
		{ "tool_pickaxe", 1 },
		{ "tool_rod", 1 },
		{ "tool_shovel", 1 },
		{ "tool_net", 1 },
		{ "seed_lettuce", 8 },
		{ "bait", 5 },
	},
	RewardCoins = 250,
	RewardItems = { { "seed_potato", 6 }, { "basic_fertilizer", 5 } },
}

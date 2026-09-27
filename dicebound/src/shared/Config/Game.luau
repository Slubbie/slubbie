-- Game-wide settings. Rename the game here: every UI title and sign reads from this.

return {
	Name = "Dicebound: Roll & Riches",
	ShortName = "Dicebound",

	-- Content with a Stage higher than this is hidden and rejected by the server.
	-- 1 = Meadow foundation, 2 = dice + regions + collection, 3 = orders, crafting, events, quests.
	Stage = 3,

	-- DataStore name. Changing it starts everyone with fresh saves (old saves stay in the old store).
	DataStoreName = "Dicebound_Players_v1",

	StartingCoins = 25,
	StartingDie = "wooden",

	-- How close (studs) a player's character must be to a merchant to sell.
	MerchantRange = 22,
}

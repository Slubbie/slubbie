-- Game-wide settings. Rename the game here: every UI title and sign reads from this.

return {
	Name = "Dicebound: Roll & Riches",
	ShortName = "Dicebound",

	-- Content with a Stage higher than this is hidden and rejected by the server.
	-- Stage 1 = Meadow Market foundation. Raise it only when the next stage's code is installed.
	Stage = 1,

	-- DataStore name. Changing it starts everyone with fresh saves (old saves stay in the old store).
	DataStoreName = "Dicebound_Players_v1",

	StartingCoins = 25,
	StartingDie = "wooden",

	-- How close (studs) a player's character must be to a merchant to sell.
	MerchantRange = 22,
}

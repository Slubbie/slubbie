-- Sound effects and music. Every entry is optional: leave an id as "" and that sound is skipped.
-- The defaults use sounds that ship with Roblox ("rbxasset://sounds/...") so the game has audio
-- out of the box. Swap in your own uploads as "rbxassetid://1234567890".

return {
	Effects = {
		Click = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.4 },
		Windup = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.35, Pitch = 1.4 },
		Land = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.45, Pitch = 1.6 },
		RevealCommon = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.25, Pitch = 1.0 },
		RevealRare = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.35, Pitch = 1.25 },
		RevealEpic = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.45, Pitch = 1.5 },
		RevealLegendary = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.55, Pitch = 0.8 },
		Sell = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.4, Pitch = 2 },
		Purchase = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.45, Pitch = 1.7 },
		Error = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.5, Pitch = 0.6 },
		Combo = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.5, Pitch = 0.9 },
	},

	-- Background music playlist. Add your own tracks, e.g.
	--   { Id = "rbxassetid://1234567890", Volume = 0.5 },
	-- An empty list means no music (the music slider still works once tracks exist).
	Music = {},
}

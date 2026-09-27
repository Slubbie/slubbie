-- Rarity tiers, lowest to highest. Colors are {r, g, b} (0-255) so this file is plain data.
-- Label + Stars make a rarity readable without relying on color alone.
--   Reveal: how dramatic the reveal is ("quick" | "nice" | "rare" | "epic" | "cinematic")
--   ConfirmSell: the client asks "are you sure?" and the server requires the confirmation flag.

local Rarities = {
	List = {
		{ Id = "Common", Label = "COMMON", Stars = "★", Color = { 196, 196, 190 }, Reveal = "quick" },
		{ Id = "Uncommon", Label = "UNCOMMON", Stars = "★★", Color = { 110, 200, 110 }, Reveal = "nice" },
		{ Id = "Rare", Label = "RARE", Stars = "★★★", Color = { 80, 160, 255 }, Reveal = "rare" },
		{ Id = "Epic", Label = "EPIC", Stars = "★★★★", Color = { 180, 100, 255 }, Reveal = "epic" },
		{
			Id = "Legendary",
			Label = "LEGENDARY",
			Stars = "★★★★★",
			Color = { 255, 176, 40 },
			Reveal = "cinematic",
			ConfirmSell = true,
		},
		{
			Id = "Mythic",
			Label = "MYTHIC",
			Stars = "★★★★★★",
			Color = { 255, 80, 120 },
			Reveal = "cinematic",
			ConfirmSell = true,
		},
		{
			Id = "Secret",
			Label = "SECRET",
			Stars = "✦✦✦",
			Color = { 90, 240, 220 },
			Reveal = "cinematic",
			ConfirmSell = true,
		},
	},
	ById = {},
}

for index, rarity in Rarities.List do
	rarity.Order = index
	Rarities.ById[rarity.Id] = rarity
end

function Rarities.Order(id: string): number
	local rarity = Rarities.ById[id]
	return if rarity then rarity.Order else 0
end

return Rarities

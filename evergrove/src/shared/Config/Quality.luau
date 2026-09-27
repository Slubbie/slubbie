-- Crop / product quality tiers and item rarity tiers.
--
-- Quality comes from how well a crop was cared for (see Lib/QualityMath):
--   score = weighted care factors in [0,1] → first tier whose Threshold ≤ score.
-- Every tier has a star count and a glyph so it reads without colour.

export type QualityTier = {
	Tier: number,
	Name: string,
	Threshold: number,
	Value: number, -- sell value multiplier
	Output: number, -- crafting/processing output bonus multiplier
	Stars: number,
	Glyph: string,
	Color: Color3,
}

local Tiers: { QualityTier } = {
	{ Tier = 1, Name = "Common", Threshold = 0, Value = 1, Output = 1, Stars = 0, Glyph = "", Color = Color3.fromRGB(196, 190, 176) },
	{ Tier = 2, Name = "Fine", Threshold = 0.36, Value = 1.25, Output = 1, Stars = 1, Glyph = "★", Color = Color3.fromRGB(160, 214, 120) },
	{ Tier = 3, Name = "Superior", Threshold = 0.56, Value = 1.6, Output = 1.1, Stars = 2, Glyph = "★★", Color = Color3.fromRGB(96, 176, 236) },
	{ Tier = 4, Name = "Pristine", Threshold = 0.73, Value = 2.1, Output = 1.2, Stars = 3, Glyph = "★★★", Color = Color3.fromRGB(190, 132, 240) },
	{ Tier = 5, Name = "Masterwork", Threshold = 0.87, Value = 3, Output = 1.35, Stars = 4, Glyph = "★★★★", Color = Color3.fromRGB(250, 186, 70) },
	{ Tier = 6, Name = "Radiant", Threshold = 0.955, Value = 4.5, Output = 1.5, Stars = 5, Glyph = "✦★★★★", Color = Color3.fromRGB(255, 120, 160) },
}

-- How much each care factor counts toward the score (sums to 1).
local Weights = {
	Water = 0.3, -- time spent inside the crop's preferred moisture band
	Soil = 0.17, -- soil health
	Nutrients = 0.13, -- nutrient balance vs the crop's needs
	Fertilizer = 0.1, -- best fertilizer quality bonus applied
	Climate = 0.12, -- season + weather fit while growing
	Genes = 0.1, -- the seed's Luster gene
	Timing = 0.08, -- harvested while fresh
}

export type Rarity = {
	Id: string,
	Order: number,
	Color: Color3,
	Glyph: string, -- shape so rarity reads without colour
	Glow: boolean,
}

local Rarities: { [string]: Rarity } = {
	Common = { Id = "Common", Order = 1, Color = Color3.fromRGB(176, 176, 168), Glyph = "●", Glow = false },
	Uncommon = { Id = "Uncommon", Order = 2, Color = Color3.fromRGB(106, 196, 96), Glyph = "◆", Glow = false },
	Rare = { Id = "Rare", Order = 3, Color = Color3.fromRGB(80, 156, 240), Glyph = "▲", Glow = false },
	Epic = { Id = "Epic", Order = 4, Color = Color3.fromRGB(176, 104, 240), Glyph = "⬟", Glow = true },
	Legendary = { Id = "Legendary", Order = 5, Color = Color3.fromRGB(250, 170, 50), Glyph = "★", Glow = true },
	Mythic = { Id = "Mythic", Order = 6, Color = Color3.fromRGB(255, 96, 170), Glyph = "✦", Glow = true },
}

local RarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

-- Colour-blind safe replacements (Okabe–Ito based), chosen in Settings.
local ColorblindRarity = {
	Common = Color3.fromRGB(190, 190, 190),
	Uncommon = Color3.fromRGB(0, 158, 115),
	Rare = Color3.fromRGB(86, 180, 233),
	Epic = Color3.fromRGB(204, 121, 167),
	Legendary = Color3.fromRGB(230, 159, 0),
	Mythic = Color3.fromRGB(240, 228, 66),
}

return {
	Tiers = Tiers,
	Weights = Weights,
	Rarities = Rarities,
	RarityOrder = RarityOrder,
	ColorblindRarity = ColorblindRarity,
	-- Random ± spread applied to the score so identical care still varies a little.
	Noise = 0.04,
	-- After a crop ripens it stays fresh this many in-game hours, then its timing
	-- factor decays linearly to zero over DecayHours (never below Common).
	FreshHours = 30,
	DecayHours = 72,
	-- Score needed for the care-based "Perfect" trait.
	PerfectScore = 0.975,
}

-- Dice definitions. Every die is six-sided; each listed face has an equal 1-in-6 chance.
--
--   Faces         the six face values. Duplicates are allowed (Clover shows 6 twice).
--   RegionFaces   optional face lists that replace Faces while rolling in a given region.
--   Perks         applied while the die is equipped in any slot. The same perk from two
--                 equipped dice does NOT stack: the largest value wins.
--                   SellBonus          +fraction on sell prices (0.10 = +10%)
--                   MutationChanceMult multiplies the chance that a find is mutated
--                   MutationWeights    { [mutationId] = multiplier } on mutation weights, and
--                                      unlocks that mutation outside its home regions
--                   UndiscoveredBoost  weight multiplier for items you haven't discovered yet
--   Tradeoff      shown on the dice card so every die has a clear downside or niche.
--   Source        how players get it: Starter | Shop (Price, Region) | Craft (Stage 3)
--   Stage         content stage that introduces it.

local Dice = {
	List = {
		{
			Id = "wooden",
			Name = "Wooden Die",
			Stage = 1,
			Faces = { 1, 2, 3, 4, 5, 6 },
			Color = { 196, 150, 100 },
			PipColor = { 60, 35, 20 },
			Material = "Wood",
			Perks = {},
			Description = "Your trusty starter die. Fair, honest, and a little bit splintery.",
			Tradeoff = "No special perks.",
			Source = { Kind = "Starter" },
		},
		{
			Id = "copper",
			Name = "Copper Die",
			Stage = 2,
			Faces = { 1, 2, 3, 4, 5, 6 },
			Color = { 190, 110, 60 },
			PipColor = { 250, 230, 200 },
			Material = "Metal",
			Perks = { SellBonus = 0.10 },
			Description = "Merchants love the jingle. Everything you sell is worth 10% more.",
			Tradeoff = "Same odds as a Wooden Die.",
			Source = { Kind = "Shop", Price = 2500, Region = "meadow" },
		},
		{
			Id = "glass",
			Name = "Glass Die",
			Stage = 2,
			Faces = { 1, 2, 3, 4, 5, 5 },
			Color = { 190, 230, 255 },
			PipColor = { 30, 80, 140 },
			Material = "Glass",
			Perks = { MutationChanceMult = 2 },
			Description = "Refracts luck into mutations: doubles your mutation chance.",
			Tradeoff = "Has no 6. Its top face is 5, so its best tier rolls are rarer.",
			Source = { Kind = "Shop", Price = 6000, Region = "crystal" },
		},
		{
			Id = "clover",
			Name = "Clover Die",
			Stage = 2,
			Faces = { 1, 1, 3, 5, 6, 6 },
			Color = { 90, 190, 100 },
			PipColor = { 255, 255, 255 },
			Material = "SmoothPlastic",
			Perks = {},
			Description = "Streaky luck: two 6s give it the best shot at rare tiers.",
			Tradeoff = "Also has two 1s and no 2 or 4, so it's swingy and misses many straights.",
			Source = { Kind = "Shop", Price = 15000, Region = "crystal" },
		},
		{
			Id = "frost",
			Name = "Frost Die",
			Stage = 2,
			Faces = { 1, 2, 3, 4, 5, 6 },
			RegionFaces = { frost = { 2, 3, 4, 5, 6, 6 } },
			Color = { 170, 220, 255 },
			PipColor = { 20, 60, 120 },
			Material = "Ice",
			Perks = { MutationWeights = { Frozen = 3 } },
			Description = "In Frostfall its faces become 2-3-4-5-6-6. Frozen mutations can appear anywhere.",
			Tradeoff = "Just a normal die outside Frostfall Village.",
			Source = { Kind = "Shop", Price = 40000, Region = "frost" },
		},
		{
			Id = "magma",
			Name = "Magma Die",
			Stage = 2,
			Faces = { 1, 2, 3, 4, 5, 6 },
			RegionFaces = { ember = { 2, 3, 4, 5, 6, 6 } },
			Color = { 60, 30, 25 },
			PipColor = { 255, 120, 30 },
			Material = "CrackedLava",
			Perks = { MutationWeights = { Golden = 2 } },
			Description = "In Emberforge its faces become 2-3-4-5-6-6. Golden mutations are twice as likely.",
			Tradeoff = "Just a normal die outside Emberforge.",
			Source = { Kind = "Shop", Price = 120000, Region = "ember" },
		},
		{
			Id = "celestial",
			Name = "Celestial Die",
			Stage = 3,
			Faces = { 1, 2, 3, 4, 5, 6 },
			Color = { 40, 30, 90 },
			PipColor = { 255, 240, 170 },
			Material = "Neon",
			Perks = { UndiscoveredBoost = 3, MutationWeights = { Cosmic = 2 } },
			Description = "Guides you to the unknown: undiscovered items are 3x as likely within their tier.",
			Tradeoff = "Crafted, not bought. No bonus once your collection is complete.",
			Source = { Kind = "Craft" },
		},
	},
	ById = {},
}

for index, die in Dice.List do
	die.Order = index
	Dice.ById[die.Id] = die
end

-- The face list a die uses in a region.
function Dice.FacesFor(die: { [string]: any }, regionId: string): { number }
	local regional = die.RegionFaces and die.RegionFaces[regionId]
	return regional or die.Faces
end

function Dice.MaxFace(faces: { number }): number
	local best = faces[1]
	for _, face in faces do
		best = math.max(best, face)
	end
	return best
end

return Dice

-- Content tables: internal consistency and the numbers from the design spec.

local Loader = require("../harness/Loader")
local T = require("../harness/T")

return function()
	local loader = Loader.new(".")
	local function shared(name: string): any
		return loader:require("Shared." .. name)
	end
	local RarityConfig = shared("RarityConfig")
	local BiomeDefinitions = shared("BiomeDefinitions")
	local CreatureDefinitions = shared("CreatureDefinitions")
	local UpgradeDefinitions = shared("UpgradeDefinitions")
	local QuestDefinitions = shared("QuestDefinitions")
	local CreatureRig = shared("CreatureRig")
	local EconomyMath = shared("EconomyMath")
	local GameConfig = shared("GameConfig")

	T.Suite("Content definitions")

	T.Case("every validator reports no problems", function()
		for name, problems in
			{
				Rarity = RarityConfig.Validate(),
				Biomes = BiomeDefinitions.Validate(),
				Creatures = CreatureDefinitions.Validate(),
				Upgrades = UpgradeDefinitions.Validate(),
				Quests = QuestDefinitions.Validate(),
			}
		do
			T.Equal(#problems, 0, `{name}: {table.concat(problems, "; ")}`)
		end
	end)

	T.Case("rarity odds match the design table and total 100%", function()
		local expected = { Common = 55, Uncommon = 26, Rare = 12, Epic = 5, Legendary = 1.7, Mythic = 0.3 }
		local total = 0
		for id, weight in expected do
			T.Equal(RarityConfig.Rarities[id].Weight, weight, id)
			total += weight
		end
		T.Near(total, 100, 1e-9, "total")
		local rates = { Common = 1, Uncommon = 3, Rare = 9, Epic = 27, Legendary = 90, Mythic = 250 }
		for id, rate in rates do
			T.Equal(RarityConfig.Rarities[id].BaseRate, rate, `{id} base rate`)
		end
	end)

	T.Case("mutation odds and bonuses match the design table", function()
		local expected = {
			Standard = { 88, 0 },
			Charged = { 8, 0.05 },
			Aurora = { 3, 0.1 },
			Eclipse = { 0.9, 0.15 },
			Prismatic = { 0.1, 0.25 },
		}
		for id, spec in expected do
			T.Equal(RarityConfig.Mutations[id].Weight, spec[1], `{id} weight`)
			T.Equal(RarityConfig.Mutations[id].Bonus, spec[2], `{id} bonus`)
		end
	end)

	T.Case("the catalog has all 24 species, each with a procedural builder", function()
		T.Equal(#CreatureDefinitions.Order, 24)
		local counts = {}
		for _, id in CreatureDefinitions.Order do
			local species = CreatureDefinitions.Species[id]
			counts[species.Rarity] = (counts[species.Rarity] or 0) + 1
			T.True(CreatureRig.HasBuilder(id), `{id} has no builder`)
			T.True(#species.Description > 10, `{id} needs a description`)
		end
		T.Equal(counts.Common, 6)
		T.Equal(counts.Uncommon, 5)
		T.Equal(counts.Rare, 5)
		T.Equal(counts.Epic, 4)
		T.Equal(counts.Legendary, 3)
		T.Equal(counts.Mythic, 1)
	end)

	T.Case("upgrade tables match the spec", function()
		local radii = { 38, 44, 51, 59, 68 }
		local scannerCosts = { 0, 250, 1600, 10000, 65000 }
		local slots = { 4, 6, 8, 10, 12 }
		local habitatCosts = { 0, 1200, 10000, 80000, 450000 }
		for level = 1, 5 do
			T.Equal(UpgradeDefinitions.ScannerRadius(level), radii[level], `scanner radius L{level}`)
			T.Equal(UpgradeDefinitions.GetLevel("Scanner", level).Cost, scannerCosts[level], `scanner cost L{level}`)
			T.Equal(UpgradeDefinitions.HabitatSlots(level), slots[level], `slots L{level}`)
			T.Equal(UpgradeDefinitions.GetLevel("Habitat", level).Cost, habitatCosts[level], `habitat cost L{level}`)
		end
		T.True(UpgradeDefinitions.HasFeature("Scanner", 4, "GuideBeam"))
		T.False(UpgradeDefinitions.HasFeature("Scanner", 3, "GuideBeam"))
	end)

	T.Case("biome unlock requirements match the spec", function()
		local expected = {
			DawnCommons = { 1, 0 },
			PrismCliffs = { 5, 2500 },
			ThunderReef = { 12, 25000 },
			ShadowCrater = { 20, 200000 },
			AstralExpanse = { 30, 1500000 },
		}
		for id, spec in expected do
			local biome = BiomeDefinitions.Biomes[id]
			T.Equal(biome.Unlock.Level, spec[1], `{id} level`)
			T.Equal(biome.Unlock.Stardust, spec[2], `{id} stardust`)
		end
		T.True(BiomeDefinitions.Biomes.DawnCommons.Implemented)
	end)

	T.Case("XP curve follows floor(100 + 45 × (level − 1)^1.3)", function()
		for level = 1, 49 do
			T.Equal(EconomyMath.XPToNext(level), math.floor(100 + 45 * (level - 1) ^ 1.3), `level {level}`)
		end
		T.Equal(GameConfig.Progression.LevelCap, 50)
		T.Equal(GameConfig.Progression.CaptureXP, 45)
	end)

	T.Case("quality rank thresholds match the spec", function()
		T.Equal(EconomyMath.RankForQuality(0.5).Id, "Bronze")
		T.Equal(EconomyMath.RankForQuality(0.55).Id, "Silver")
		T.Equal(EconomyMath.RankForQuality(0.749).Id, "Silver")
		T.Equal(EconomyMath.RankForQuality(0.75).Id, "Gold")
		T.Equal(EconomyMath.RankForQuality(0.899).Id, "Gold")
		T.Equal(EconomyMath.RankForQuality(0.9).Id, "Perfect")
		T.Equal(EconomyMath.RankForQuality(1).Id, "Perfect")
	end)

	T.Case("trading and purchases are disabled by feature flag", function()
		T.False(GameConfig.Features.Trading)
		T.False(GameConfig.Features.Purchases)
	end)
end

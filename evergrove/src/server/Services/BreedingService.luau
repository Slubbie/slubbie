-- Breeding: animals (Punnett-square genetics, pregnancies) and seeds (gene
-- crossing and hybrid species at the Genetics Lab).
--
-- Animals
--   Two adults of the same species that are happy (Hap ≥ 60) and friendly
--   (Fr ≥ 250), both off cooldown. The first animal carries the baby for
--   GestationHours (in-game) and it's delivered into the same building when
--   due (AnimalService.Deliver). Offspring genes come from Genetics.Breed:
--   coat/pattern alleles are inherited one from each parent, stats are
--   averaged with noise, and rare alleles can appear by mutation.
--   The client shows exact odds with Genetics.BreedOdds before confirming.
--
-- Seeds (Genetics Lab station)
--   Same crop: genes are crossed (Genetics.Cross) — a steady way to breed
--   better Vigor / Bounty / Hardiness / Luster, with rare breakthroughs.
--   Different crops listed in Config/Crops.Hybrids: a chance to create a new
--   species. The chance multiplies when the hybrid's weather or season is
--   active, so players plan experiments around the forecast. A failed
--   hybrid still returns one crossed parent seed so nothing is wasted.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Animals = require(Shared.Config.Animals)
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local ItemUtil = require(Shared.Lib.ItemUtil)
local Genetics = require(Shared.Lib.Genetics)
local GameTime = require(Shared.Lib.GameTime)
local WeatherMath = require(Shared.Lib.WeatherMath)
local Stats = require(Shared.Lib.Stats)
local Format = require(Shared.Lib.Format)

local S = require(script.Parent)

local HOUR = GameTime.HOUR
local MIN_HAPPINESS = 60
local MIN_FRIENDSHIP = 250
local HYBRID_WEATHER_MULT = 3
local random = Random.new()

local BreedingService = {}

-- Animals ---------------------------------------------------------------------------------------------------

function BreedingService.CanBreed(profile: any, a: any, b: any, t: number): (boolean, string?)
	if a == b then
		return false, "Pick two different animals"
	end
	if a.Sp ~= b.Sp then
		return false, "Only animals of the same species can breed"
	end
	for _, animal in { a, b } do
		if os.time() - (animal.Born or 0) < 3 * 3600 then
			return false, animal.Nm .. " is still a baby"
		end
		if (animal.Hap or 0) < MIN_HAPPINESS then
			return false, animal.Nm .. " isn't happy enough (needs " .. MIN_HAPPINESS .. ")"
		end
		if (animal.Fr or 0) < MIN_FRIENDSHIP then
			return false, animal.Nm .. " doesn't trust you enough yet"
		end
		if animal.Bred and t - animal.Bred < Animals.BreedCooldownHours * HOUR then
			return false, animal.Nm .. " needs a rest before breeding again"
		end
	end
	if a.Preg or b.Preg then
		return false, "One of them is already expecting"
	end
	-- Room for the baby in the mother's building (counting other pregnancies).
	local record = profile.Farm.Placed[a.Home]
	local def = record and Registry.Placeables[record.Id]
	if not def or not def.Function or def.Function.Kind ~= "Animal" then
		return false, "They need a proper home first"
	end
	local occupants = 0
	for _, other in profile.Farm.Animals do
		if other.Home == a.Home then
			occupants += if other.Preg then 2 else 1
		end
	end
	if occupants >= def.Function.Capacity then
		return false, "Their " .. def.Name .. " has no room for a baby"
	end
	return true
end

local function breedAnimals(player: Player, aidA: string, aidB: string)
	local profile = S.Data.Get(player)
	if not profile then
		return false, "Not ready"
	end
	local a = profile.Farm.Animals[aidA]
	local b = profile.Farm.Animals[aidB]
	if not a or not b then
		return false, "Pick two of your animals"
	end
	local position = S.Building.WorldPosition(player, a.Home)
	if not position or not S.Security.InReach(player, position, 40) then
		return false, "Go to their home first"
	end
	local t = GameTime.Now()
	S.Animal.Settle(player, aidA)
	S.Animal.Settle(player, aidB)
	local ok, reason = BreedingService.CanBreed(profile, a, b, t)
	if not ok then
		return false, reason
	end
	local bonus = Stats.Effect(profile, "BreedMutation")
	local child = Genetics.Breed(a.Sp, a.G, b.G, random, bonus)
	a.Bred = t
	b.Bred = t
	a.Preg = { Due = t + Animals.GestationHours * HOUR, G = child, Sire = b.Nm }
	S.Data.Changed(player, "Farm", "Animals")
	S.Animal.Render(player, aidA)
	S.Notify.FX(position, "Animal", { Aid = aidA, Kind = "Hearts" }, 120)
	local species = S.Animal.Species(a.Sp)
	S.Notify.Toast(player, string.format("💞 %s and %s are expecting! The baby %s arrives in about %s.", a.Nm, b.Nm, species.Name, Format.Duration(Animals.GestationHours * HOUR)), "Success")
	return true, { Due = a.Preg.Due }
end

-- Seeds ------------------------------------------------------------------------------------------------------

local function isSeed(stack: any): (boolean, string?)
	local def = stack and Registry.Items[stack.Id]
	if not def or not def.Plants then
		return false, nil
	end
	return true, def.Plants
end

local function hybridChance(hybrid: any, profile: any): number
	local chance = hybrid.Chance or 0.1
	local t = GameTime.Now()
	local weather = WeatherMath.Current(t)
	local info = GameTime.Info(t)
	if hybrid.Weather and (hybrid.Weather == weather or (hybrid.Weather == "Windy" and (WeatherMath.Def(weather).Visual.Wind or 0) >= 0.5)) then
		chance *= HYBRID_WEATHER_MULT
	end
	if hybrid.Season and hybrid.Season == info.SeasonId then
		chance *= 2
	end
	chance *= 1 + Stats.Effect(profile, "MutationChance")
	return math.clamp(chance, 0, 0.9)
end

local function seedBreed(player: Player, refA: string, refB: string)
	local profile = S.Data.Get(player)
	if not profile then
		return false, "Not ready"
	end
	-- Your own Genetics Lab, or Juniper's research lab in town (during opening hours).
	if not S.Crafting.AtStation(player, "Lab") and not (S.NPC.Near(player, "juniper") and S.Economy.IsOpen("lab")) then
		return false, "Use a Genetics Lab, or visit Juniper at the Vale Research Lab"
	end
	if refA == refB then
		local stack = S.Inventory.Slot(player, refA)
		if not stack or stack.N < 2 then
			return false, "Pick two seeds"
		end
	end
	local a = S.Inventory.Slot(player, refA)
	local b = S.Inventory.Slot(player, refB)
	local okA, cropA = isSeed(a)
	local okB, cropB = isSeed(b)
	if not okA or not okB or not cropA or not cropB then
		return false, "Pick two seeds"
	end
	if a.L or b.L then
		return false, "Unlock the seeds first"
	end
	local genesA = a.G or Genetics.ShopGenes(random)
	local genesB = b.G or Genetics.ShopGenes(random)
	local result: any
	local hybridMade = false
	if cropA == cropB then
		result = ItemUtil.New(a.Id, 1)
		result.G = Genetics.Cross(genesA, genesB, random, Stats.Effect(profile, "MutationChance") * 0.3)
		-- Latent traits pass on from either parent.
		result.T = if random:NextNumber() < 0.5 then (a.T or b.T) else (b.T or a.T)
	else
		local hybrid = Genetics.Hybrid(cropA, cropB)
		if not hybrid then
			return false, "Those two won't cross. Try pairs from the Hybrid notes in your Collection."
		end
		local seedId = "seed_" .. hybrid.Result
		if not Registry.Items[seedId] then
			return false, "Unknown hybrid"
		end
		if random:NextNumber() < hybridChance(hybrid, profile) then
			result = ItemUtil.New(seedId, 1)
			result.G = Genetics.Cross(genesA, genesB, random)
			hybridMade = true
		else
			-- Failed: keep one parent line, crossed.
			local keep = if random:NextNumber() < 0.5 then a else b
			result = ItemUtil.New(keep.Id, 1)
			result.G = Genetics.Cross(genesA, genesB, random)
		end
	end
	local takenA = S.Inventory.TakeFromSlot(player, refA, 1)
	local takenB = S.Inventory.TakeFromSlot(player, refB, 1)
	if not takenA or not takenB then
		-- Put back anything taken (race with another request).
		if takenA then
			S.Inventory.Add(player, takenA, { Silent = true })
		end
		if takenB then
			S.Inventory.Add(player, takenB, { Silent = true })
		end
		return false, "Pick two seeds"
	end
	S.Inventory.Add(player, result, { Source = "Genetics Lab" })
	S.Skill.AddXP(player, "Farming", if hybridMade then 120 else 15)
	S.Data.AddStat(player, "SeedsBred")
	S.Quest.Progress(player, "SeedBreed", result.Id, 1)
	if hybridMade then
		local crop = Registry.Crops[string.sub(result.Id, 6)]
		S.Data.AddStat(player, "HybridsMade")
		S.Collection.Discover(player, "Crops", crop.Id, { Hybrid = true })
		S.Notify.Banner(player, "Hybrid breakthrough!", "You created " .. crop.Name .. " seeds!", "Discovery", crop.Icon)
	end
	return true, { Seed = result, Hybrid = hybridMade, Score = Genetics.GeneScore(result.G) }
end

function BreedingService.Init()
	Net.Handle("AnimalBreed", breedAnimals)
	Net.Handle("SeedBreed", seedBreed)
end

return BreedingService

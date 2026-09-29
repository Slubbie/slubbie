-- Shared helpers for animal screens: moods, hearts, genes and homes, read
-- from the replicated profile (Farm.Animals) and the farm's placed models.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Registry = require(Shared.Lib.Registry)
local Genetics = require(Shared.Lib.Genetics)
local GameTime = require(Shared.Lib.GameTime)
local Animals = require(Shared.Config.Animals)

local AnimalInfo = {}

AnimalInfo.MOOD_ICON = { Hungry = "🍽️", Joyful = "😄", Content = "🙂", Glum = "😕", Sad = "😢" }

function AnimalInfo.Mood(animal: any): string
	local today = GameTime.DayIndex(GameTime.Now())
	if (animal.Fed or -99) < today - 1 then
		return "Hungry"
	elseif (animal.Hap or 0) >= 80 then
		return "Joyful"
	elseif (animal.Hap or 0) >= 50 then
		return "Content"
	elseif (animal.Hap or 0) >= 25 then
		return "Glum"
	end
	return "Sad"
end

-- Care done today: { Fed, Pet, Brushed, Treat }.
function AnimalInfo.Today(animal: any): { [string]: boolean }
	local today = GameTime.DayIndex(GameTime.Now())
	return {
		Fed = (animal.Fed or -99) >= today,
		Pet = (animal.Pet or -99) >= today,
		Brushed = (animal.Br or -99) >= today,
		Treat = (animal.Tr or -99) >= today,
	}
end

function AnimalInfo.Hearts(animal: any): string
	local n = math.floor((animal.Fr or 0) / Animals.MaxFriendship * 5 + 0.0001)
	return string.rep("❤", n) .. string.rep("♡", 5 - n)
end

function AnimalInfo.IsBaby(animal: any): boolean
	return os.time() - (animal.Born or 0) < 3 * 3600
end

function AnimalInfo.Phenotype(animal: any): any
	return Genetics.Phenotype(animal.Sp, animal.G)
end

function AnimalInfo.Rarity(animal: any): string
	return Genetics.AnimalRarity(animal.Sp, animal.G)
end

function AnimalInfo.Personality(animal: any): any
	return Registry.Personalities[animal.Pe] or { Id = animal.Pe or "?", Icon = "🙂", Note = "" }
end

-- "Golden · Spotted" with the hidden (carried) alleles when they differ.
function AnimalInfo.LookText(animal: any): (string, string?)
	local species = Registry.Species[animal.Sp]
	local p = AnimalInfo.Phenotype(animal)
	local shown = p.Coat.Name .. (if p.Pattern.Id ~= "plain" then " · " .. p.Pattern.Name else "")
	local carried = {}
	for _, pair in { { animal.G.Coat, species.Coats, p.Coat }, { animal.G.Pattern, species.Patterns, p.Pattern } } do
		for _, alleleId in pair[1] do
			if alleleId ~= pair[3].Id then
				for _, a in pair[2] do
					if a.Id == alleleId then
						table.insert(carried, a.Name)
					end
				end
			end
		end
	end
	return shown, if #carried > 0 then "carries " .. table.concat(carried, ", ") else nil
end

-- The player's farm lot model.
function AnimalInfo.MyLot(): Instance?
	local lotId = Players.LocalPlayer:GetAttribute("Lot")
	local farms = workspace:FindFirstChild("Farms")
	if not lotId or not farms then
		return nil
	end
	for _, lot in farms:GetChildren() do
		if lot:GetAttribute("Lot") == lotId then
			return lot
		end
	end
	return nil
end

-- Animal homes on your farm: { Uid, Def, Residents }.
function AnimalInfo.Homes(profile: any): { any }
	local out = {}
	local lot = AnimalInfo.MyLot()
	local placed = lot and lot:FindFirstChild("Placed")
	if not placed then
		return out
	end
	for _, model in placed:GetChildren() do
		local def = Registry.Placeables[model:GetAttribute("Placeable") or ""]
		if def and def.Function and def.Function.Kind == "Animal" then
			local residents = 0
			for _, animal in (profile and profile.Farm and profile.Farm.Animals) or {} do
				if animal.Home == model.Name then
					residents += if animal.Preg then 2 else 1
				end
			end
			table.insert(out, { Uid = model.Name, Def = def, Residents = residents })
		end
	end
	table.sort(out, function(a, b)
		return a.Def.Name < b.Def.Name
	end)
	return out
end

function AnimalInfo.HomeDef(uid: string): any?
	local lot = AnimalInfo.MyLot()
	local placed = lot and lot:FindFirstChild("Placed")
	local model = placed and placed:FindFirstChild(uid)
	return model and Registry.Placeables[model:GetAttribute("Placeable") or ""]
end

-- Can these two breed (client preview of the server's checks)?
function AnimalInfo.BreedCheck(a: any, b: any): (boolean, string?)
	if a == b then
		return false, "Pick two different animals"
	elseif a.Sp ~= b.Sp then
		return false, "Same species only"
	end
	local t = GameTime.Now()
	for _, animal in { a, b } do
		if AnimalInfo.IsBaby(animal) then
			return false, animal.Nm .. " is still a baby"
		elseif (animal.Hap or 0) < 60 then
			return false, animal.Nm .. " needs happiness 60+"
		elseif (animal.Fr or 0) < 250 then
			return false, animal.Nm .. " needs more friendship"
		elseif animal.Bred and t - animal.Bred < Animals.BreedCooldownHours * GameTime.HOUR then
			return false, animal.Nm .. " is resting"
		elseif animal.Preg then
			return false, animal.Nm .. " is expecting"
		end
	end
	return true, nil
end

return AnimalInfo

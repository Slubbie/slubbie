-- Crafting, cosmetics, the dice shop, dice equipping and region unlocks.
-- Pure logic over a Data table; every check and change happens in one call.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Dicebound.Config)
local Bag = require(script.Parent.Bag)

local Workshop = {}

-- ── Crafting ──────────────────────────────────────────────────────────────────

local function owns(data, recipe): boolean
	if recipe.Kind == "Die" then
		return data.Dice.Owned[recipe.Grants] == true
	elseif recipe.Kind == "Aura" then
		return data.Cosmetics.Auras[recipe.Grants] == true
	elseif recipe.Kind == "Tray" then
		return data.Cosmetics.Trays[recipe.Grants] == true
	end
	return false
end
Workshop.OwnsRecipeResult = owns

-- What's missing for a recipe: a list of { Id, Need, Have } (empty when craftable).
function Workshop.Missing(data, recipe): { { Id: string, Need: number, Have: number } }
	local missing = {}
	for _, need in recipe.Needs do
		local have = Bag.Available(data, need.Id, nil)
		if have < need.Qty then
			table.insert(missing, { Id = need.Id, Need = need.Qty, Have = have })
		end
	end
	return missing
end

function Workshop.Craft(data, recipeId: any): (boolean, string?)
	local recipe = type(recipeId) == "string" and Config.Crafting.ById[recipeId]
	if not recipe then
		return false, "That recipe doesn't exist."
	end
	if owns(data, recipe) then
		return false, "You already have that."
	end
	if data.Coins < recipe.Coins then
		return false, string.format("You need %d more coins.", recipe.Coins - data.Coins)
	end
	if #Workshop.Missing(data, recipe) > 0 then
		return false, "You're missing some ingredients (locked items are never used)."
	end
	-- Everything was checked above, so every Take succeeds.
	for _, need in recipe.Needs do
		assert(Bag.Take(data, need.Id, nil, need.Qty), "ingredient vanished")
	end
	data.Coins -= recipe.Coins
	if recipe.Kind == "Die" then
		data.Dice.Owned[recipe.Grants] = true
	elseif recipe.Kind == "Aura" then
		data.Cosmetics.Auras[recipe.Grants] = true
		data.Cosmetics.Aura = recipe.Grants
	elseif recipe.Kind == "Tray" then
		data.Cosmetics.Trays[recipe.Grants] = true
		data.Cosmetics.Tray = recipe.Grants
	end
	data.Stats.Crafts += 1
	return true, nil
end

-- kind = "Aura" | "Tray"; id = "" removes an aura.
function Workshop.EquipCosmetic(data, kind: any, id: any): (boolean, string?)
	if type(id) ~= "string" then
		return false, "Invalid cosmetic."
	end
	if kind == "Aura" then
		if id ~= "" and not data.Cosmetics.Auras[id] then
			return false, "You don't own that aura."
		end
		data.Cosmetics.Aura = id
		return true, nil
	elseif kind == "Tray" then
		if not data.Cosmetics.Trays[id] then
			return false, "You don't own that tray."
		end
		data.Cosmetics.Tray = id
		return true, nil
	end
	return false, "Invalid cosmetic."
end

-- ── Dice ──────────────────────────────────────────────────────────────────────

function Workshop.BuyDie(data, dieId: any): (boolean, string?)
	local die = type(dieId) == "string" and Config.Dice.ById[dieId]
	if not die or not Config.IsLive(die) then
		return false, "That die doesn't exist."
	end
	if data.Dice.Owned[die.Id] then
		return false, "You already own it."
	end
	local source = die.Source
	if source.Kind ~= "Shop" then
		return false, "That die can't be bought."
	end
	if source.Region and not data.Regions[source.Region] then
		local region = Config.Regions.ById[source.Region]
		return false, "Unlock " .. (if region then region.Name else source.Region) .. " first."
	end
	if data.Coins < source.Price then
		return false, string.format("You need %d more coins.", source.Price - data.Coins)
	end
	data.Coins -= source.Price
	data.Dice.Owned[die.Id] = true
	return true, nil
end

-- Sets the equipped dice in slot order (slot 1 = lead die). Must be owned, unique, and fit
-- the player's Dice Tray slots.
function Workshop.Equip(data, list: any): (boolean, string?)
	if type(list) ~= "table" then
		return false, "Invalid dice."
	end
	local slots = Config.UpgradeValue("DiceSlots", data.Upgrades.DiceSlots)
	local equipped, seen = {}, {}
	for i, dieId in list do
		if type(i) ~= "number" or type(dieId) ~= "string" then
			return false, "Invalid dice."
		end
		if not data.Dice.Owned[dieId] or not Config.IsLive(Config.Dice.ById[dieId]) then
			return false, "You don't own that die."
		end
		if seen[dieId] then
			return false, "Each die can only be used once."
		end
		seen[dieId] = true
		table.insert(equipped, dieId)
	end
	if #equipped < 1 then
		return false, "Equip at least one die."
	end
	if #equipped > slots then
		return false, string.format("You only have %d dice slot%s.", slots, if slots == 1 then "" else "s")
	end
	data.Dice.Equipped = equipped
	return true, nil
end

-- ── Regions ───────────────────────────────────────────────────────────────────

-- (canUnlock, reason, discoveredInPrevious, needed)
function Workshop.UnlockStatus(data, region): (boolean, string?)
	if data.Regions[region.Id] then
		return false, "Already unlocked."
	end
	if not Config.IsLive(region) then
		return false, "Coming soon."
	end
	local previous = Config.Regions.Previous(region.Id)
	if previous and not data.Regions[previous.Id] then
		return false, "Unlock " .. previous.Name .. " first."
	end
	local need = region.Unlock.Discoveries or 0
	if previous and need > 0 then
		local found = 0
		for _, item in Config.ItemsIn(previous.Id) do
			if data.Discovered[item.Id] then
				found += 1
			end
		end
		if found < need then
			return false, string.format("Discover %d %s treasures first (%d/%d).", need, previous.Name, found, need)
		end
	end
	if data.Coins < region.Unlock.Coins then
		return false, string.format("You need %d more coins.", region.Unlock.Coins - data.Coins)
	end
	return true, nil
end

function Workshop.UnlockRegion(data, regionId: any): (boolean, string?)
	local region = type(regionId) == "string" and Config.Regions.ById[regionId]
	if not region then
		return false, "That region doesn't exist."
	end
	local ok, err = Workshop.UnlockStatus(data, region)
	if not ok then
		return false, err
	end
	data.Coins -= region.Unlock.Coins
	data.Regions[region.Id] = true
	return true, nil
end

return Workshop

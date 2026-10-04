-- Credits, prestige tokens, the shop and equipping cosmetics.
--
-- Credits come from steady play; prestige tokens only from significant
-- achievements. District items unlock in the shop once you've visited that
-- district, so every stall sells things tied to a place you've been.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cosmetics = require(ReplicatedStorage.Shared.Config.Cosmetics)
local Districts = require(ReplicatedStorage.Shared.Config.Districts)
local Net = require(ReplicatedStorage.Shared.Net)

local DataService = require(script.Parent.Parent.Data.DataService)
local Events = require(script.Parent.Parent.Events)
local Notify = require(script.Parent.Notify)
local ProgressionService = require(script.Parent.ProgressionService)

local EconomyService = {}

-- Called after equipment changes so characters update (set by CosmeticService).
EconomyService.OnEquipChanged = nil :: ((Player) -> ())?

function EconomyService.AddCredits(player: Player, amount: number, _reason: string?)
	local profile = DataService.Get(player)
	if not profile or amount <= 0 then
		return
	end
	amount = math.floor(amount + 0.5)
	profile.Credits += amount
	profile.Stats.CreditsEarned = (profile.Stats.CreditsEarned or 0) + amount
	DataService.Push(player, "Credits")
end

function EconomyService.AddPrestige(player: Player, amount: number, _reason: string?)
	local profile = DataService.Get(player)
	if not profile or amount <= 0 then
		return
	end
	profile.Prestige += math.floor(amount)
	DataService.Push(player, "Prestige")
end

function EconomyService.Owns(player: Player, itemId: string): boolean
	local profile = DataService.Get(player)
	return profile ~= nil and profile.Inventory[itemId] == true
end

function EconomyService.GrantItem(player: Player, itemId: string, silent: boolean?)
	local profile = DataService.Get(player)
	local item = Cosmetics.ById[itemId]
	if not profile or not item or profile.Inventory[itemId] then
		return
	end
	profile.Inventory[itemId] = true
	DataService.Push(player, "Inventory")
	Events.ItemGranted:Fire(player, itemId)
	Events.StatChanged:Fire(player, "ItemsOwned")
	if not silent then
		Notify.Send(player, {
			Kind = "Item",
			Title = item.Name,
			Text = Cosmetics.CategoryNames[item.Category] .. " unlocked: " .. item.Description,
			Item = itemId,
			Color = Cosmetics.Rarities[item.Rarity],
			Sound = "Unlock",
		})
	end
end

-- Whether an item is on sale to this player right now (and why not).
function EconomyService.CanBuy(player: Player, itemId: string): (boolean, string?)
	local profile = DataService.Get(player)
	local item = Cosmetics.ById[itemId]
	if not profile or not item then
		return false, "Unknown item"
	end
	if profile.Inventory[itemId] then
		return false, "Already owned"
	end
	if item.Source == "Reward" then
		return false, item.Unlock or "Earned, not bought"
	end
	if item.District and not profile.Districts.Visited[item.District] then
		local district = Districts.ById[item.District]
		return false, "Visit " .. (if district then district.Name else item.District) .. " to unlock"
	end
	if item.Source == "Prestige" then
		if profile.Prestige < (item.PrestigePrice or 0) then
			return false, ("Needs %d prestige tokens"):format(item.PrestigePrice or 0)
		end
	elseif profile.Credits < (item.Price or 0) then
		return false, ("Needs %d credits"):format(item.Price or 0)
	end
	return true, nil
end

local function equip(player: Player, category: string, itemId: string?): (boolean, string?)
	local profile = DataService.Get(player)
	if not profile or not table.find(Cosmetics.Categories, category) then
		return false, "Unknown category"
	end
	if category == "Emote" then
		-- Emotes: toggle in the equipped list (up to 8).
		if type(itemId) ~= "string" then
			return false, "Pick an emote"
		end
		local item = Cosmetics.ById[itemId]
		if not item or item.Category ~= "Emote" or not profile.Inventory[itemId] then
			return false, "Not owned"
		end
		local list = profile.Equipped.Emotes or {}
		local index = table.find(list, itemId)
		if index then
			table.remove(list, index)
		elseif #list >= Cosmetics.MultiEquip.Emote then
			return false, "Emote wheel is full"
		else
			table.insert(list, itemId)
		end
		profile.Equipped.Emotes = list
	else
		local target = itemId or Cosmetics.Defaults[category]
		local item = target and Cosmetics.ById[target]
		if not item or item.Category ~= category or not profile.Inventory[target] then
			return false, "Not owned"
		end
		profile.Equipped[category] = target
	end
	DataService.Push(player, "Equipped")
	if EconomyService.OnEquipChanged then
		EconomyService.OnEquipChanged(player)
	end
	return true, nil
end

function EconomyService.Start()
	ProgressionService.AddCredits = EconomyService.AddCredits
	ProgressionService.AddPrestige = EconomyService.AddPrestige
	ProgressionService.GrantItem = EconomyService.GrantItem

	Net.Handle("Shop.Buy", function(player, itemId)
		if type(itemId) ~= "string" then
			return false, "Invalid item"
		end
		local ok, reason = EconomyService.CanBuy(player, itemId)
		if not ok then
			return false, reason
		end
		local profile = DataService.Get(player) :: any
		local item = Cosmetics.ById[itemId]
		if item.Source == "Prestige" then
			profile.Prestige -= item.PrestigePrice or 0
			DataService.Push(player, "Prestige")
		else
			profile.Credits -= item.Price or 0
			DataService.Push(player, "Credits")
		end
		EconomyService.GrantItem(player, itemId, true)
		-- Wearables are put on straight away.
		if item.Category ~= "Emote" and item.Category ~= "Title" then
			equip(player, item.Category, itemId)
		end
		DataService.SaveNow(player)
		return true, nil
	end)

	Net.Handle("Shop.Equip", function(player, category, itemId)
		if type(category) ~= "string" or (itemId ~= nil and type(itemId) ~= "string") then
			return false, "Invalid"
		end
		return equip(player, category, itemId)
	end)
end

return EconomyService

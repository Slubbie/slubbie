-- Using items from the inventory: eating and drinking, reading recipe books,
-- opening geodes and treasure, warp totems and farm totems. Loot tables live
-- in Config/Items.Loot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Items = require(Shared.Config.Items)
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local RNG = require(Shared.Lib.RNG)
local Stats = require(Shared.Lib.Stats)
local ItemUtil = require(Shared.Lib.ItemUtil)

local S = require(script.Parent)

local ItemService = {}

local random = Random.new()

-- Roll a loot table: returns stacks.
function ItemService.RollLoot(tableId: string, rolls: number?, luck: number?): { ItemUtil.Stack }
	local loot = Items.Loot[tableId]
	local out = {}
	if not loot then
		return out
	end
	for _ = 1, rolls or 1 do
		local entry = RNG.WeightedEntry(loot, function(e)
			local def = Registry.Items[e.Id]
			local rarityBoost = if def and luck then 1 + (Registry.RarityOrder(def.Rarity) - 1) * luck else 1
			return e.Weight * rarityBoost
		end, random:NextNumber())
		if entry then
			local count = if entry.Count then random:NextInteger(entry.Count[1], entry.Count[2]) else 1
			table.insert(out, ItemUtil.New(entry.Id, count))
		end
	end
	return out
end

local function use(player: Player, ref: string)
	local profile = S.Data.Get(player)
	local stack = S.Inventory.Slot(player, ref)
	if not profile or not stack then
		return false, "Nothing there"
	end
	local def = Registry.Items[stack.Id]
	if not def or not def.Use then
		return false, "You can't use that"
	end
	local kind = def.Use
	if kind == "Eat" or kind == "Drink" then
		local max = S.Player.MaxEnergy(player)
		if (def.Energy or 0) > 0 and profile.Energy >= max and not def.Buff then
			return false, "You're not hungry"
		end
		local taken = S.Inventory.TakeFromSlot(player, ref, 1)
		if not taken then
			return false, "Unlock it first"
		end
		local qualityBonus = 1 + ((taken.Q or 1) - 1) * 0.1
		local restore = (def.Energy or 0) * qualityBonus * (1 + Stats.Effect(profile, "EnergyRestore"))
		S.Player.RestoreEnergy(player, restore)
		if def.Buff then
			S.Player.ApplyBuff(player, def.Buff)
		end
		S.Data.AddStat(player, "FoodEaten")
		S.Notify.FXPlayer(player, "Eat", { Id = def.Id, Energy = math.floor(restore) })
		return true
	elseif kind == "Read" then
		local learned = {}
		for _, recipeId in def.Teaches or {} do
			if S.Crafting.Learn(player, recipeId, true) then
				table.insert(learned, recipeId)
			end
		end
		S.Inventory.TakeFromSlot(player, ref, 1, true)
		if #learned == 0 then
			S.Notify.Toast(player, "You already knew everything in this book.", "Info")
		else
			S.Notify.Banner(player, "📖 " .. def.Name, "Learned " .. #learned .. " new recipe" .. (if #learned > 1 then "s" else ""), "Recipe")
		end
		return true
	elseif kind == "Open" then
		if not def.Loot then
			return false, "It won't open"
		end
		local taken = S.Inventory.TakeFromSlot(player, ref, 1)
		if not taken then
			return false, "Unlock it first"
		end
		local luck = Stats.Effect(profile, "GeodeChance") * 0.2 + Stats.Effect(profile, "GemChance") * 0.2
		local drops = ItemService.RollLoot(def.Loot, if def.Category == "Treasure" and def.Id ~= "geode" then 3 else 1, luck)
		for _, drop in drops do
			S.Inventory.Add(player, drop, { Source = def.Name })
			S.Collection.OnItem(player, drop)
		end
		S.Data.AddStat(player, "ContainersOpened")
		S.Notify.FXPlayer(player, "Open", { Id = def.Id, Items = drops })
		return true
	elseif kind == "Warp" then
		if not S.Player.Warp(player, def.Warp or "home") then
			return false, "Can't warp right now"
		end
		S.Inventory.TakeFromSlot(player, ref, 1, true)
		return true
	elseif kind == "Totem" then
		if def.Id == "rain_totem" then
			local count = S.Soil.WaterAll(player)
			if count == 0 then
				return false, "You have no tilled soil to water"
			end
			S.Inventory.TakeFromSlot(player, ref, 1, true)
			S.Notify.Toast(player, "🌧️ A gentle rain waters your whole farm.", "Success")
			return true
		end
	elseif kind == "Place" then
		return true, "Build" -- the client opens build mode with this item
	elseif kind == "Plant" or kind == "Fertilize" or kind == "Spray" or kind == "Amend" then
		return false, "Select it in your hotbar, then use it on your soil"
	end
	return false, "You can't use that here"
end

function ItemService.Init()
	Net.Handle("InvUse", use)
end

return ItemService

-- The collection book's catalog, built from the registries so new content
-- appears automatically. Shared so the client book and the server agree on
-- entries, categories and milestone rewards.
--
-- Entry ids: items use their item id; mutations their mutation id; animal
-- breeds "species:coat"; artisan product families "type:jam"; NPCs, regions,
-- weather and lore use their ids.

local Config = script.Parent.Parent.Config
local Animals = require(Config.Animals)
local Mutations = require(Config.Mutations)
local Weather = require(Config.Weather)
local Secrets = require(Config.Secrets)
local Machines = require(Config.Machines)
local NPCs = require(Config.NPCs)
local Regions = require(Config.Regions)
local Recipes = require(Config.Recipes)
local Registry = require(script.Parent.Registry)

export type Entry = {
	Id: string,
	Name: string,
	Icon: string,
	Rarity: string,
	Hint: string?,
	Tint: Color3?,
}

export type Category = {
	Id: string,
	Name: string,
	Icon: string,
	Entries: { Entry },
	Index: { [string]: Entry },
	Milestones: { { Percent: number, Reward: { [string]: any } } },
}

local Collections = {}

local function milestones(scale: number)
	return {
		{ Percent = 0.25, Reward = { Coins = math.floor(1000 * scale), Items = { { "seed_crate", 1 } } } },
		{ Percent = 0.5, Reward = { Coins = math.floor(5000 * scale), Items = { { "festival_box", 1 } } } },
		{ Percent = 0.75, Reward = { Coins = math.floor(20000 * scale), Items = { { "omni_geode", 3 } } } },
		{ Percent = 1, Reward = { Coins = math.floor(80000 * scale), Items = { { "prism_shard", 1 } } } },
	}
end

local categories: { Category } = {}
local byId: { [string]: Category } = {}

local function category(id: string, name: string, icon: string, entries: { Entry }, scale: number?)
	table.sort(entries, function(a, b)
		local ra, rb = Registry.RarityOrder(a.Rarity), Registry.RarityOrder(b.Rarity)
		if ra ~= rb then
			return ra < rb
		end
		return a.Name < b.Name
	end)
	local index = {}
	for _, entry in entries do
		index[entry.Id] = entry
	end
	local cat: Category =
		{ Id = id, Name = name, Icon = icon, Entries = entries, Index = index, Milestones = milestones(scale or 1) }
	table.insert(categories, cat)
	byId[id] = cat
end

local function itemEntries(filter: (any) -> boolean): { Entry }
	local out = {}
	for _, item in Registry.ItemList do
		if filter(item) then
			table.insert(
				out,
				{ Id = item.Id, Name = item.Name, Icon = item.Icon, Rarity = item.Rarity, Tint = item.Tint }
			)
		end
	end
	return out
end

-- Crops
do
	local entries = {}
	for _, crop in Registry.Crops do
		local hint = if #crop.Sources > 0 then "Found: " .. table.concat(crop.Sources, ", ") else "Sold as seeds"
		table.insert(entries, {
			Id = crop.Id,
			Name = crop.Name,
			Icon = crop.Icon,
			Rarity = crop.Rarity,
			Hint = hint,
			Tint = crop.Visual.Fruit,
		})
	end
	category("Crops", "Crops", "🌾", entries, 1.5)
end

-- Mutations (incl. legendary combos)
do
	local entries = {}
	for _, m in Mutations.List do
		table.insert(entries, { Id = m.Id, Name = m.Name, Icon = m.Icon, Rarity = m.Rarity, Hint = m.Description })
	end
	for _, c in Mutations.Combos do
		table.insert(entries, {
			Id = c.Id,
			Name = c.Name,
			Icon = c.Icon,
			Rarity = "Legendary",
			Hint = "Combine " .. table.concat(c.Requires, " + "),
		})
	end
	category("Mutations", "Mutations", "🧬", entries, 2)
end

-- Animal breeds (species × visible coat)
do
	local entries = {}
	for _, species in Animals.List do
		for _, coat in species.Coats do
			table.insert(entries, {
				Id = species.Id .. ":" .. coat.Id,
				Name = coat.Name .. " " .. species.Name,
				Icon = species.Icon,
				Rarity = coat.Rarity,
				Tint = coat.Color,
				Hint = if coat.Dom >= 3 then "Recessive: breed two carriers" else nil,
			})
		end
	end
	category("Animals", "Animal Breeds", "🐄", entries, 1.5)
end

category(
	"Fish",
	"Fish",
	"🐟",
	itemEntries(function(item)
		return item.Category == "Fish"
	end),
	1.5
)

category(
	"Minerals",
	"Minerals & Gems",
	"💎",
	itemEntries(function(item)
		return item.Category == "Gem" or item.Category == "Mineral"
	end)
)

category(
	"Artifacts",
	"Artifacts",
	"🏺",
	itemEntries(function(item)
		return item.Category == "Artifact"
	end)
)

category(
	"Forage",
	"Forage",
	"🍄",
	itemEntries(function(item)
		return item.Category == "Forage"
	end)
)

category(
	"Flowers",
	"Flowers",
	"🌸",
	itemEntries(function(item)
		return item.Tags.Flower == true and (item.Category == "Crop" or item.Category == "Forage")
	end)
)

category(
	"Bugs",
	"Bugs",
	"🦋",
	itemEntries(function(item)
		return item.Category == "Bug"
	end)
)

-- Crafted products: fixed artisan goods, food, potions and one entry per product family.
do
	local entries = itemEntries(function(item)
		return item.Product == nil
			and (item.Category == "Artisan" or item.Category == "Food" or item.Category == "Potion")
	end)
	for productType, template in Machines.Products do
		table.insert(entries, {
			Id = "type:" .. productType,
			Name = string.gsub(string.gsub(template.Name, "%%s ?", ""), "^%s+", ""),
			Icon = template.Icon,
			Rarity = "Common",
			Hint = "Any " .. productType,
		})
	end
	category("Artisan", "Crafted Goods", "🍷", entries, 1.5)
end

do
	local entries = {}
	for _, recipe in Recipes.List do
		local out = Registry.Items[recipe.Out]
		if out then
			table.insert(entries, {
				Id = recipe.Id,
				Name = out.Name,
				Icon = out.Icon,
				Rarity = if recipe.Unlock.Secret then "Epic" else out.Rarity,
			})
		end
	end
	category("Recipes", "Recipes", "📜", entries)
end

do
	local entries = {}
	for _, npc in NPCs.List do
		table.insert(entries, { Id = npc.Id, Name = npc.Name, Icon = npc.Icon, Rarity = "Common", Hint = npc.Role })
	end
	category("Villagers", "Villagers", "🧑‍🌾", entries)
end

do
	local entries = {}
	for _, region in Regions.List do
		table.insert(entries, {
			Id = region.Id,
			Name = region.Name,
			Icon = region.Icon,
			Rarity = if region.Unlock then "Rare" else "Common",
			Hint = region.UnlockText,
		})
	end
	category("Regions", "Regions", "🗺️", entries)
end

do
	local entries = {}
	for _, id in Weather.Order do
		local w = Weather.Types[id]
		table.insert(entries, {
			Id = id,
			Name = w.Name,
			Icon = w.Icon,
			Rarity = if w.Rare then "Epic" else "Common",
			Hint = w.Description,
		})
	end
	category("Weather", "Weather", "⛅", entries)
end

do
	local entries = {}
	for _, lore in Secrets.Lore do
		table.insert(entries, { Id = lore.Id, Name = lore.Title, Icon = "📜", Rarity = "Rare" })
	end
	category("Lore", "Lore Pages", "📜", entries, 2)
end

Collections.Categories = categories
Collections.ById = byId

function Collections.Get(categoryId: string): Category?
	return byId[categoryId]
end

-- Which category an obtained item counts toward (nil for none).
function Collections.CategoryForItem(itemId: string): (string?, string?)
	local item = Registry.Items[itemId]
	if not item then
		return nil, nil
	end
	local c = item.Category
	if c == "Fish" then
		return "Fish", itemId
	elseif c == "Gem" or c == "Mineral" then
		return "Minerals", itemId
	elseif c == "Artifact" then
		return "Artifacts", itemId
	elseif c == "Forage" then
		return "Forage", itemId
	elseif c == "Bug" then
		return "Bugs", itemId
	elseif item.Product then
		return "Artisan", "type:" .. item.Product
	elseif c == "Artisan" or c == "Food" or c == "Potion" then
		return "Artisan", itemId
	end
	return nil, nil
end

-- Completion fraction for a category given a profile's Collection table.
function Collections.Progress(collection: any, categoryId: string): (number, number)
	local cat = byId[categoryId]
	if not cat then
		return 0, 0
	end
	local found = 0
	local records = collection and collection[categoryId]
	if records then
		for id in records do
			if cat.Index[id] then
				found += 1
			end
		end
	end
	return found, #cat.Entries
end

function Collections.TotalPercent(collection: any): number
	local found, total = 0, 0
	for _, cat in categories do
		local f, t = Collections.Progress(collection, cat.Id)
		found += f
		total += t
	end
	return if total > 0 then found / total else 0
end

return Collections

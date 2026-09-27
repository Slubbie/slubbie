-- The item registry: one lookup for every item in the game.
--
-- Built once (on require) from every Config module:
--   crops → produce + seeds, fertilizers, fish, minerals, forage, bugs,
--   tools, powered equipment, placeables, hand-written items, and artisan
--   products generated from machine recipes (jam_strawberry, smoked_tuna, ...).
--
-- It also indexes crops, machines, recipes, NPCs, regions, quests and more by
-- id, and answers tag questions (Registry.Matches(itemId, "#Fruit")).

local Config = script.Parent.Parent.Config
local Crops = require(Config.Crops)
local Soil = require(Config.Soil)
local Items = require(Config.Items)
local Fish = require(Config.Fish)
local Minerals = require(Config.Minerals)
local Gathering = require(Config.Gathering)
local Tools = require(Config.Tools)
local Placeables = require(Config.Placeables)
local Machines = require(Config.Machines)
local Recipes = require(Config.Recipes)
local Animals = require(Config.Animals)
local NPCs = require(Config.NPCs)
local Shops = require(Config.Shops)
local Regions = require(Config.Regions)
local Quests = require(Config.Quests)
local Festivals = require(Config.Festivals)
local Mutations = require(Config.Mutations)
local Weather = require(Config.Weather)
local Achievements = require(Config.Achievements)
local Skills = require(Config.Skills)
local Secrets = require(Config.Secrets)
local Quality = require(Config.Quality)
local Land = require(Config.Land)

export type ItemDef = {
	Id: string,
	Name: string,
	Icon: string,
	SubIcon: string?,
	Tint: Color3?,
	Category: string,
	Rarity: string,
	Value: number,
	Tags: { [string]: boolean },
	TagList: { string },
	Description: string,
	Stack: number,
	NoTrade: boolean,
	NoSell: boolean,
	NoTrash: boolean,
	Use: string?,
	Energy: number?,
	Buff: { Id: string, Mult: number, Minutes: number }?,
	Teaches: { string }?,
	Loot: string?,
	Warp: string?,
	Amend: string?,
	Crop: string?, -- produce: its crop id
	Plants: string?, -- seeds: the crop they grow
	Fertilizer: any?,
	Fish: any?,
	Placeable: any?,
	Tool: string?, -- tool family id
	Powered: any?,
	Source: string, -- which config it came from
	Input: string?, -- generated artisan products: the input item
	Product: string?, -- generated artisan products: product type (jam, wine...)
}

local Registry = {}

Registry.Items = {} :: { [string]: ItemDef }
Registry.ItemList = {} :: { ItemDef }

-- Extra tags for hand-written items (kept here so Items stays readable).
local EXTRA_TAGS: { [string]: { string } } = {
	copper_bar = { "Metal" },
	iron_bar = { "Metal" },
	gold_bar = { "Metal", "Golden" },
	starsteel_bar = { "Metal" },
	golden_egg = { "Golden" },
	golden_mayo = { "Golden" },
	golden_flour = { "Golden" },
	golden_loaf = { "Golden" },
	golden_idol = { "Golden" },
	golden_wheat = { "Golden" },
	meteorite = { "Star" },
	stardust_powder = { "Star" },
	star_petal = { "Star" },
	fiber = { "Junk" },
	driftwood = { "Junk" },
	crystal_shard = { "Crystal" },
	refined_crystal = { "Crystal" },
	crystal_berry = { "Crystal" },
	quartz = { "Crystal" },
}

local function register(def: any, source: string)
	if Registry.Items[def.Id] then
		error(string.format("[Registry] duplicate item id '%s' (%s vs %s)", def.Id, Registry.Items[def.Id].Source, source))
	end
	local tagSet = {}
	local tagList = {}
	local function addTag(tag: string)
		if not tagSet[tag] then
			tagSet[tag] = true
			table.insert(tagList, tag)
		end
	end
	for _, tag in def.Tags or {} do
		addTag(tag)
	end
	addTag(def.Category)
	for _, tag in ipairs(EXTRA_TAGS[def.Id] or {}) do
		addTag(tag)
	end
	def.Tags = tagSet
	def.TagList = tagList
	def.Rarity = def.Rarity or "Common"
	def.Value = math.max(0, math.floor(def.Value or 0))
	def.Description = def.Description or ""
	def.Stack = def.Stack or 999
	def.NoTrade = def.NoTrade == true
	def.NoSell = def.NoSell == true
	def.NoTrash = def.NoTrash == true
	def.Source = source
	Registry.Items[def.Id] = def
	table.insert(Registry.ItemList, def)
	return def
end

-- Lookup tables ----------------------------------------------------------------------------

local function index<T>(list: { T }, key: string?): { [string]: T }
	local out = {}
	for _, entry in list do
		out[(entry :: any)[key or "Id"]] = entry
	end
	return out
end

Registry.Crops = index(Crops.List)
Registry.Fertilizers = index(Soil.Fertilizers)
Registry.Fish = index(Fish.List)
Registry.Minerals = index(Minerals.List)
Registry.Forage = index(Gathering.Forage)
Registry.Bugs = index(Gathering.Bugs)
Registry.Nodes = index(Gathering.Nodes)
Registry.ToolFamilies = index(Tools.Families)
Registry.Powered = index(Tools.Powered)
Registry.Placeables = index(Placeables.List)
Registry.Machines = index(Machines.List)
Registry.Recipes = index(Recipes.List)
Registry.Species = index(Animals.List)
Registry.Personalities = index(Animals.Personalities)
Registry.Npcs = index(NPCs.List)
Registry.Shops = index(Shops.List)
Registry.Regions = index(Regions.List)
Registry.Quests = index(Quests.List)
Registry.Festivals = index(Festivals.List)
Registry.Mutations = index(Mutations.List)
Registry.Combos = index(Mutations.Combos)
Registry.Weather = Weather.Types
Registry.Achievements = index(Achievements.List)
Registry.Skills = index(Skills.List)
Registry.Secrets = index(Secrets.List)
Registry.Lore = index(Secrets.Lore)
Registry.Projects = index(Land.Projects)
Registry.QualityTiers = Quality.Tiers
Registry.Rarities = Quality.Rarities

Registry.SkillNodes = {} :: { [string]: { [string]: any } }
for _, skill in Skills.List do
	Registry.SkillNodes[skill.Id] = index(skill.Tree)
end

-- Items from each source -------------------------------------------------------------------

for _, crop in Crops.List do
	local tags = table.clone(crop.Tags)
	table.insert(tags, "Crop")
	table.insert(tags, crop.Family)
	register({
		Id = crop.Id,
		Name = crop.Name,
		Icon = crop.Icon,
		Tint = crop.Visual.Fruit,
		Category = "Crop",
		Rarity = crop.Rarity,
		Value = crop.Sell,
		Tags = tags,
		Description = crop.Special or "",
		Crop = crop.Id,
	}, "Crops")
end

for _, crop in Crops.List do
	local seedValue = if crop.Seed then crop.Seed / 2 else crop.Sell / 4
	register({
		Id = "seed_" .. crop.Id,
		Name = crop.Name .. (if crop.Tree then " Sapling" else " Seeds"),
		Icon = if crop.Tree then "🌱" else "🫘",
		SubIcon = crop.Icon,
		Tint = crop.Visual.Leaf,
		Category = "Seed",
		Rarity = crop.Rarity,
		Value = seedValue,
		Tags = { "Seed" },
		Description = string.format(
			"Grows %s. Season: %s.",
			crop.Name,
			table.concat(crop.Seasons, ", ")
		),
		Use = "Plant",
		Plants = crop.Id,
	}, "Crops")
end

for _, fert in Soil.Fertilizers do
	local rarityValue = { Common = 20, Uncommon = 60, Rare = 180, Epic = 600, Legendary = 2000, Mythic = 6000 }
	register({
		Id = fert.Id,
		Name = fert.Name,
		Icon = fert.Icon,
		Category = "Fertilizer",
		Rarity = fert.Rarity,
		Value = if fert.Price then fert.Price / 2 else rarityValue[fert.Rarity] or 30,
		Tags = { "Fertilizer" },
		Description = fert.Description,
		Use = "Fertilize",
		Fertilizer = fert,
	}, "Soil")
end

for _, item in Items.List do
	register(table.clone(item), "Items")
end

for _, fish in Fish.List do
	local tags = { "Fish" }
	if fish.Legendary then
		table.insert(tags, "Legendary")
	end
	register({
		Id = fish.Id,
		Name = fish.Name,
		Icon = fish.Icon,
		Tint = fish.Tint,
		Category = "Fish",
		Rarity = fish.Rarity,
		Value = fish.Value,
		Tags = tags,
		Description = fish.Description or "",
		Fish = fish,
	}, "Fish")
end

for _, mineral in Minerals.List do
	register({
		Id = mineral.Id,
		Name = mineral.Name,
		Icon = mineral.Icon,
		Tint = mineral.Tint,
		Category = mineral.Category,
		Rarity = mineral.Rarity,
		Value = mineral.Value,
		Tags = {},
		Description = mineral.Description,
	}, "Minerals")
end

for _, forage in Gathering.Forage do
	register({
		Id = forage.Id,
		Name = forage.Name,
		Icon = forage.Icon,
		Tint = forage.Tint,
		Category = "Forage",
		Rarity = forage.Rarity,
		Value = forage.Value,
		Tags = forage.Tags or {},
		Description = forage.Description or "",
		Use = if forage.Energy then "Eat" else nil,
		Energy = forage.Energy,
	}, "Gathering")
end

for _, bug in Gathering.Bugs do
	register({
		Id = bug.Id,
		Name = bug.Name,
		Icon = bug.Icon,
		Tint = bug.Tint,
		Category = "Bug",
		Rarity = bug.Rarity,
		Value = bug.Value,
		Tags = {},
		Description = bug.Description or "",
	}, "Gathering")
end

for _, family in Tools.Families do
	register({
		Id = "tool_" .. family.Id,
		Name = family.Name,
		Icon = family.Icon,
		Category = "Tool",
		Rarity = "Common",
		Value = 0,
		Tags = { "Tool" },
		Description = family.Description,
		Stack = 1,
		NoTrade = true,
		NoSell = true,
		NoTrash = true,
		Use = "Equip",
		Tool = family.Id,
	}, "Tools")
end

for _, powered in Tools.Powered do
	register({
		Id = powered.Id,
		Name = powered.Name,
		Icon = powered.Icon,
		Category = "Tool",
		Rarity = "Epic",
		Value = 0,
		Tags = { "Tool", "Powered" },
		Description = powered.Description,
		Stack = 1,
		NoTrade = true,
		NoSell = true,
		Use = "Equip",
		Powered = powered,
	}, "Tools")
end

local DECOR_CATEGORIES = {
	Fence = true,
	Path = true,
	Lighting = true,
	Nature = true,
	Water = true,
	Furniture = true,
	Structure = true,
	Statue = true,
	Decor = true,
	Seasonal = true,
	Trophy = true,
}

for _, placeable in Placeables.List do
	local tags = { "Placeable", placeable.Category }
	if DECOR_CATEGORIES[placeable.Category] then
		table.insert(tags, "Decor")
	end
	local fn = placeable.Function
	if fn and fn.Kind then
		table.insert(tags, fn.Kind)
	end
	for _, tag in placeable.Tags or {} do
		table.insert(tags, tag)
	end
	register({
		Id = placeable.Id,
		Name = placeable.Name,
		Icon = placeable.Icon,
		Category = "Placeable",
		Rarity = placeable.Rarity,
		Value = (placeable.Price or 400) / 2,
		Tags = tags,
		Description = placeable.Description or "",
		Stack = 99,
		Use = "Place",
		Placeable = placeable,
		NoSell = placeable.Category == "Trophy",
	}, "Placeables")
end

-- Generated artisan products ---------------------------------------------------------------------

local baseItems = table.clone(Registry.ItemList)

local function tagged(tag: string): { ItemDef }
	local out = {}
	for _, item in baseItems do
		if item.Tags[tag] then
			table.insert(out, item)
		end
	end
	return out
end

local function productTypeOf(outPattern: string): string?
	return string.match(outPattern, "^([%a]+)_%%s$")
end

local function generate(productType: string, input: ItemDef)
	local template = Machines.Products[productType]
	if not template then
		return
	end
	local id = productType .. "_" .. input.Id
	if Registry.Items[id] then
		return
	end
	local tags = table.clone(template.Tags)
	register({
		Id = id,
		Name = string.format(template.Name, input.Name),
		Icon = template.Icon,
		SubIcon = input.Icon,
		Tint = input.Tint,
		Category = template.Category,
		Rarity = input.Rarity,
		Value = input.Value * template.Mult + template.Add,
		Tags = tags,
		Description = string.format("Made from %s.", input.Name),
		Use = template.Use,
		Energy = template.Energy,
		Input = input.Id,
		Product = productType,
	}, "Machines")
end

for _, machine in Machines.List do
	for _, recipe in machine.Recipes do
		local productType = productTypeOf(recipe.Out)
		if productType and recipe.In.Tag and Machines.Products[productType] then
			for _, input in tagged(recipe.In.Tag) do
				generate(productType, input)
			end
		end
	end
end

-- Flavoured honey from every flower crop (bees near flowers).
for _, input in tagged("Flower") do
	if input.Crop then
		generate("honey", input)
	end
end

-- Queries -----------------------------------------------------------------------------------------

function Registry.Get(id: string?): ItemDef?
	if id == nil then
		return nil
	end
	return Registry.Items[id]
end

function Registry.HasTag(id: string, tag: string): boolean
	local item = Registry.Items[id]
	return item ~= nil and item.Tags[tag] == true
end

-- spec: "*" (anything), "#Tag", "@Rarity" (that rarity or better), or an exact id.
function Registry.Matches(id: string, spec: string?): boolean
	if spec == nil or spec == "*" then
		return Registry.Items[id] ~= nil
	end
	local first = string.sub(spec, 1, 1)
	if first == "#" then
		return Registry.HasTag(id, string.sub(spec, 2))
	elseif first == "@" then
		local item = Registry.Items[id]
		local want = Quality.Rarities[string.sub(spec, 2)]
		if not item or not want then
			return false
		end
		return Quality.Rarities[item.Rarity].Order >= want.Order
	end
	return id == spec
end

local tagCache: { [string]: { ItemDef } } = {}
function Registry.WithTag(tag: string): { ItemDef }
	local cached = tagCache[tag]
	if cached then
		return cached
	end
	local out = {}
	for _, item in Registry.ItemList do
		if item.Tags[tag] then
			table.insert(out, item)
		end
	end
	tagCache[tag] = out
	return out
end

function Registry.SpecName(spec: string): string
	if spec == "*" then
		return "Anything"
	end
	local first = string.sub(spec, 1, 1)
	if first == "#" then
		return "Any " .. string.sub(spec, 2)
	elseif first == "@" then
		return string.sub(spec, 2) .. "+ item"
	end
	local item = Registry.Items[spec]
	return if item then item.Name else spec
end

function Registry.RarityOrder(rarity: string): number
	local def = Quality.Rarities[rarity]
	return if def then def.Order else 1
end

-- Machine recipe for a given input item (first match wins; exact ids before tags).
function Registry.MachineRecipe(machineId: string, inputId: string): (any?, string?)
	local machine = Registry.Machines[machineId]
	local item = Registry.Items[inputId]
	if not machine or not item then
		return nil, nil
	end
	for pass = 1, 2 do
		for _, recipe in machine.Recipes do
			local matches = if pass == 1 then recipe.In.Id == inputId else (recipe.In.Tag ~= nil and item.Tags[recipe.In.Tag] == true)
			if matches then
				local out = recipe.Out
				if string.find(out, "%%s") then
					out = string.format(out, inputId)
				end
				if Registry.Items[out] then
					return recipe, out
				end
			end
		end
	end
	return nil, nil
end

-- Where an item is used (for tooltips): recipes and machines.
local usesCache: { [string]: { string } } = {}
function Registry.UsesOf(id: string): { string }
	local cached = usesCache[id]
	if cached then
		return cached
	end
	local uses = {}
	local seen = {}
	local function add(text: string)
		if not seen[text] then
			seen[text] = true
			table.insert(uses, text)
		end
	end
	for _, recipe in Recipes.List do
		for _, input in recipe.In do
			if Registry.Matches(id, input[1]) then
				local out = Registry.Items[recipe.Out]
				add((if out then out.Name else recipe.Out) .. " (" .. recipe.Station .. ")")
				break
			end
		end
	end
	for _, machine in Machines.List do
		local recipe = Registry.MachineRecipe(machine.Id, id)
		if recipe then
			add(machine.Name)
		end
	end
	usesCache[id] = uses
	return uses
end

-- Seeds that shops can sell (crops with a Seed price).
function Registry.ShopSeeds(): { any }
	local out = {}
	for _, crop in Crops.List do
		if crop.Seed then
			table.insert(out, crop)
		end
	end
	return out
end

return Registry

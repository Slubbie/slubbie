-- Config validation and unit tests for the shared modules.
-- Run: python3 tests/bundle.py   (see README)

local Config = SHARED.Config
local Lib = SHARED.Lib

local failures = 0
local passes = 0
local function check(cond: any, message: string)
	if cond then
		passes += 1
	else
		failures += 1
		print("  ✗ " .. message)
	end
end
local function section(name: string)
	print("• " .. name)
end

local Registry = require(Lib.Registry)
local ItemUtil = require(Lib.ItemUtil)
local Genetics = require(Lib.Genetics)
local QualityMath = require(Lib.QualityMath)
local CropMath = require(Lib.CropMath)
local GameTime = require(Lib.GameTime)
local WeatherMath = require(Lib.WeatherMath)
local MarketMath = require(Lib.MarketMath)
local Stats = require(Lib.Stats)
local RNG = require(Lib.RNG)
local Format = require(Lib.Format)
local TableUtil = require(Lib.TableUtil)
local Net = require(Lib.Net)
local ContestMath = require(Lib.ContestMath)

local Crops = require(Config.Crops)
local Soil = require(Config.Soil)
local Items = require(Config.Items)
local Machines = require(Config.Machines)
local Recipes = require(Config.Recipes)
local Placeables = require(Config.Placeables)
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
local Gathering = require(Config.Gathering)
local Tools = require(Config.Tools)
local Land = require(Config.Land)
local Social = require(Config.Social)
local Tutorial = require(Config.Tutorial)
local World = require(Config.World)
local Seasons = require(Config.Seasons)
local Store = require(Config.Store)
local Settings = require(Config.Settings)
local AudioConfig = require(Config.Audio)
local Fish = require(Config.Fish)
local Economy = require(Config.Economy)
local Gameplay = require(Config.Gameplay)
local Minerals = require(Config.Minerals)

-- Helpers ----------------------------------------------------------------------------------

local function specValid(spec: string): boolean
	if spec == "*" then
		return true
	end
	local first = string.sub(spec, 1, 1)
	if first == "#" then
		return #Registry.WithTag(string.sub(spec, 2)) > 0
	elseif first == "@" then
		return require(Config.Quality).Rarities[string.sub(spec, 2)] ~= nil
	end
	return Registry.Items[spec] ~= nil
end

local function item(id: any, where: string)
	check(type(id) == "string" and Registry.Items[id] ~= nil, where .. ": unknown item '" .. tostring(id) .. "'")
end

local function spec(s: any, where: string)
	check(type(s) == "string" and specValid(s), where .. ": bad item spec '" .. tostring(s) .. "'")
end

local function rewards(r: any, where: string)
	if not r then
		return
	end
	for _, entry in r.Items or {} do
		item(entry[1], where .. " reward")
		check(type(entry[2]) == "number" and entry[2] > 0, where .. " reward count")
	end
	if r.Recipe then
		check(Registry.Recipes[r.Recipe] ~= nil, where .. ": unknown recipe " .. r.Recipe)
	end
	for skill in r.XP or {} do
		check(Registry.Skills[skill] ~= nil, where .. ": unknown XP skill " .. skill)
	end
	for npc in r.Friendship or {} do
		check(Registry.Npcs[npc] ~= nil, where .. ": unknown friendship npc " .. npc)
	end
	if r.Animal then
		check(Registry.Species[r.Animal.Species] ~= nil, where .. ": unknown species")
	end
end

-- Registry ---------------------------------------------------------------------------------
section("Registry")
check(#Registry.ItemList > 400, "expected a large item catalog, got " .. #Registry.ItemList)
print(
	string.format(
		"    %d items, %d crops, %d fish, %d placeables, %d recipes, %d quests",
		#Registry.ItemList,
		#Crops.List,
		#Fish.List,
		#Placeables.List,
		#Recipes.List,
		#Quests.List
	)
)
for _, def in Registry.ItemList do
	check(type(def.Name) == "string" and def.Name ~= "", "item has a name: " .. def.Id)
	check(type(def.Icon) == "string" and def.Icon ~= "", "item has an icon: " .. def.Id)
	check(
		require(Config.Quality).Rarities[def.Rarity] ~= nil,
		"item rarity valid: " .. def.Id .. " " .. tostring(def.Rarity)
	)
	check(def.Value >= 0, "item value >= 0: " .. def.Id)
end
check(Registry.Items["jam_strawberry"] ~= nil, "generated jam_strawberry")
check(Registry.Items["smoked_tuna"] ~= nil, "generated smoked_tuna")
check(Registry.Items["honey_lavender"] ~= nil, "generated honey_lavender")
check(
	Registry.Items["wine_grape"] and Registry.Items["wine_grape"].Value == Registry.Items.grape.Value * 3,
	"wine value formula"
)
check(Registry.Matches("strawberry", "#Fruit"), "strawberry is fruit")
check(not Registry.Matches("carrot", "#Fruit"), "carrot isn't fruit")
check(Registry.Matches("starfruit", "@Rare"), "starfruit is Rare+")
check(Registry.Items["sprinkler"].Tags.Sprinkler, "sprinkler tag")
check(Registry.Items["gazebo"].Tags.Decor, "decor tag")

-- Crops ------------------------------------------------------------------------------------
section("Crops")
local seasonIds = {}
for _, s in Seasons do
	seasonIds[s.Id] = true
end
seasonIds.Any = true
for _, crop in Crops.List do
	for _, s in crop.Seasons do
		check(seasonIds[s], crop.Id .. ": bad season " .. s)
	end
	check(crop.Grow > 0, crop.Id .. ": grow time")
	check(Soil.WaterBands[crop.Water] ~= nil, crop.Id .. ": water need")
	check(crop.MaxQuality >= 1 and crop.MaxQuality <= 6, crop.Id .. ": max quality")
	check(crop.Yield[1] <= crop.Yield[2], crop.Id .. ": yield range")
	for _, source in crop.Sources do
		local kind, id = string.match(source, "^(%a+):?(.*)$")
		if kind == "Region" then
			check(Registry.Regions[id] ~= nil, crop.Id .. ": unknown source region " .. id)
		elseif kind == "Npc" then
			check(Registry.Npcs[id] ~= nil, crop.Id .. ": unknown source npc " .. id)
		elseif kind == "Quest" then
			check(Registry.Quests[id] ~= nil, crop.Id .. ": unknown source quest " .. id)
		elseif kind == "Festival" then
			check(Registry.Festivals[id] ~= nil, crop.Id .. ": unknown source festival " .. id)
		else
			check(kind == "Traveler" or kind == "Breeding", crop.Id .. ": unknown source kind " .. tostring(kind))
		end
	end
	local obtainable = crop.Seed ~= nil or #crop.Sources > 0
	check(obtainable, crop.Id .. ": no way to obtain seeds")
end
for _, hybrid in Crops.Hybrids do
	check(
		Registry.Crops[hybrid.A] and Registry.Crops[hybrid.B] and Registry.Crops[hybrid.Result],
		"hybrid crops exist " .. hybrid.Result
	)
	check(hybrid.Weather == nil or Weather.Types[hybrid.Weather] ~= nil, "hybrid weather " .. tostring(hybrid.Weather))
end
for _, comp in Soil.Companions do
	check(Registry.Crops[comp.A] ~= nil, "companion crop " .. comp.A)
	check(comp.B == "*" or Registry.Crops[comp.B] ~= nil, "companion crop " .. comp.B)
end
for _, aff in Soil.Afflictions do
	item(aff.Cure, "affliction cure")
end

-- Mutations --------------------------------------------------------------------------------
section("Mutations")
for _, m in Mutations.List do
	for cropId in m.Neighbors or {} do
		check(Registry.Crops[cropId] ~= nil, m.Id .. ": unknown neighbour crop " .. cropId)
	end
	for weatherId in m.Weather or {} do
		check(Weather.Types[weatherId] ~= nil, m.Id .. ": unknown weather " .. weatherId)
	end
end
for _, combo in Mutations.Combos do
	for _, req in combo.Requires do
		check(Registry.Mutations[req] ~= nil, combo.Id .. ": unknown required mutation " .. req)
	end
end
for id, w in Weather.Types do
	for m in w.Mutations do
		check(Registry.Mutations[m] ~= nil, "weather " .. id .. ": unknown mutation " .. m)
	end
end
for _, fert in Soil.Fertilizers do
	for m in fert.Mutations or {} do
		check(Registry.Mutations[m] ~= nil, "fertilizer " .. fert.Id .. ": unknown mutation " .. m)
	end
end
for season, weights in Weather.SeasonWeights do
	check(seasonIds[season], "weather season " .. season)
	for id in weights do
		check(Weather.Types[id] ~= nil, "season weights: unknown weather " .. id)
	end
end
for _, id in Weather.Order do
	check(Weather.Types[id] ~= nil, "weather order " .. id)
end

-- Items / loot -----------------------------------------------------------------------------
section("Items & loot")
for tableId, loot in Items.Loot do
	for _, entry in loot do
		item(entry.Id, "loot " .. tableId)
	end
end
for _, def in Items.List do
	if def.Loot then
		check(Items.Loot[def.Loot] ~= nil, def.Id .. ": unknown loot table " .. def.Loot)
	end
	for _, recipeId in def.Teaches or {} do
		check(Registry.Recipes[recipeId] ~= nil, def.Id .. ": teaches unknown recipe " .. recipeId)
	end
end

-- Machines & recipes -----------------------------------------------------------------------
section("Machines & recipes")
for _, machine in Machines.List do
	check(Registry.Placeables[machine.Id] ~= nil, "machine has a placeable: " .. machine.Id)
	for _, recipe in machine.Recipes do
		if recipe.In.Id then
			item(recipe.In.Id, machine.Id .. " input")
		else
			spec("#" .. recipe.In.Tag, machine.Id .. " input tag")
		end
		for _, extra in recipe.Extra or {} do
			item(extra.Id, machine.Id .. " extra input")
		end
		if not string.find(recipe.Out, "%%s") then
			item(recipe.Out, machine.Id .. " output")
		else
			local anyInput = Registry.WithTag(recipe.In.Tag or "")[1]
			if anyInput then
				local r, out = Registry.MachineRecipe(machine.Id, anyInput.Id)
				check(r ~= nil and Registry.Items[out] ~= nil, machine.Id .. ": generated output for " .. anyInput.Id)
			end
		end
	end
end
local craftable = {}
for _, recipe in Recipes.List do
	item(recipe.Out, "recipe " .. recipe.Id .. " output")
	craftable[recipe.Out] = true
	for _, input in recipe.In do
		spec(input[1], "recipe " .. recipe.Id .. " input")
		check(type(input[2]) == "number" and input[2] > 0, "recipe " .. recipe.Id .. " input count")
	end
	check(Recipes.Stations[recipe.Station] ~= nil, "recipe " .. recipe.Id .. " station " .. recipe.Station)
	local u = recipe.Unlock
	if u.Skill then
		check(Registry.Skills[u.Skill[1]] ~= nil, "recipe " .. recipe.Id .. " unlock skill")
	end
	if u.Friend then
		check(Registry.Npcs[u.Friend[1]] ~= nil, "recipe " .. recipe.Id .. " unlock npc " .. u.Friend[1])
	end
	if u.Book then
		local taught = false
		for _, def in Items.List do
			if def.Teaches and table.find(def.Teaches, recipe.Id) then
				taught = true
			end
		end
		-- NPC events can also teach recipes.
		for _, npc in NPCs.List do
			for _, event in npc.Events do
				if event.Reward.Recipe == recipe.Id then
					taught = true
				end
			end
		end
		check(taught, "book recipe " .. recipe.Id .. " is taught by some book")
	end
end

-- Placeables ---------------------------------------------------------------------------------
section("Placeables")
local sold = {}
for _, shop in Shops.List do
	for _, entry in shop.Stock do
		sold[entry.Id] = true
	end
	for _, entry in (shop.Rotating and shop.Rotating.Pool) or {} do
		sold[entry.Id] = true
	end
end
for _, p in Placeables.List do
	check(p.Name ~= "" and p.Icon ~= "", "placeable named " .. p.Id)
	check(#p.Size == 2 and p.Size[1] >= 1 and p.Size[2] >= 1, "placeable size " .. p.Id)
	for _, mat in p.Mats or {} do
		item(mat.Id, "placeable " .. p.Id .. " mats")
	end
	if p.Function and p.Function.Kind == "Machine" then
		check(Registry.Machines[p.Function.Machine] ~= nil, "placeable machine " .. p.Id)
	end
	local obtainable = p.Price ~= nil
		or craftable[p.Id]
		or sold[p.Id]
		or p.Category == "Trophy"
		or p.Category == "Seasonal"
	if not obtainable then
		-- Also obtainable from festival shops / NPC rewards.
		for _, festival in Festivals.List do
			for _, entry in festival.Shop do
				if entry.Id == p.Id then
					obtainable = true
				end
			end
		end
	end
	check(obtainable, "placeable obtainable: " .. p.Id)
end

-- Shops ------------------------------------------------------------------------------------
section("Shops")
for _, shop in Shops.List do
	check(Registry.Npcs[shop.Owner] ~= nil, shop.Id .. ": unknown owner " .. shop.Owner)
	for _, entry in shop.Stock do
		item(entry.Id, "shop " .. shop.Id)
	end
	for _, entry in (shop.Rotating and shop.Rotating.Pool) or {} do
		item(entry.Id, "shop " .. shop.Id .. " rotating")
	end
end
for _, npc in NPCs.List do
	if npc.Shop then
		check(Registry.Shops[npc.Shop] ~= nil, npc.Id .. ": unknown shop " .. npc.Shop)
	end
end

-- NPCs -------------------------------------------------------------------------------------
section("NPCs")
local buildingIds = {}
for _, b in World.Buildings do
	buildingIds[b.Id] = true
end
local function waypointValid(name: string): boolean
	if World.Waypoints[name] or buildingIds[name] then
		return true
	end
	local npcId = string.match(name, "^Home_(.+)$")
	return npcId ~= nil and Registry.Npcs[npcId] ~= nil
end
for _, npc in NPCs.List do
	for _, key in { "Love", "Like", "Dislike", "Hate" } do
		for _, s in npc.Gifts[key] do
			spec(s, npc.Id .. " gift " .. key)
		end
	end
	for listName, list in npc.Schedule do
		for _, entry in list do
			check(
				waypointValid(entry[2]),
				npc.Id .. " schedule " .. listName .. ": unknown waypoint " .. tostring(entry[2])
			)
		end
	end
	for _, key in
		{ "Stranger", "Acquaintance", "Friend", "Close", "Love", "Like", "Neutral", "Dislike", "Hate", "Birthday" }
	do
		check(npc.Lines[key] and #npc.Lines[key] > 0, npc.Id .. ": missing lines " .. key)
	end
	for _, event in npc.Events do
		rewards(event.Reward, npc.Id .. " event " .. event.Title)
	end
	check(npc.Birthday[1] >= 1 and npc.Birthday[1] <= 4, npc.Id .. " birthday season")
end
for _, s in NPCs.Universal.Love do
	spec(s, "universal love")
end

-- Regions & world --------------------------------------------------------------------------
section("Regions")
for _, region in Regions.List do
	for nodeId in region.Nodes do
		check(Registry.Nodes[nodeId] ~= nil, region.Id .. ": unknown node " .. nodeId)
	end
	for _, id in region.Forage do
		check(Registry.Forage[id] ~= nil, region.Id .. ": unknown forage " .. id)
	end
	for _, id in region.Bugs do
		check(Registry.Bugs[id] ~= nil, region.Id .. ": unknown bug " .. id)
	end
	for _, entry in region.Dig do
		item(entry.Id, region.Id .. " dig")
	end
	for _, water in region.Waters do
		local ok = false
		for _, fish in Fish.List do
			if table.find(fish.Waters, water.Tag) then
				ok = true
			end
		end
		check(ok, region.Id .. ": no fish for water " .. water.Tag)
	end
	if region.Weather and region.Weather.Replace then
		for a, b in region.Weather.Replace do
			check(Weather.Types[a] and Weather.Types[b], region.Id .. ": weather replace " .. a .. "->" .. b)
		end
	end
	if region.Unlock then
		local u = region.Unlock
		if u.Quest then
			check(Registry.Quests[u.Quest] ~= nil, region.Id .. ": unlock quest " .. u.Quest)
		end
		if u.Item then
			item(u.Item, region.Id .. " unlock item")
		end
		if u.Project then
			check(Registry.Projects[u.Project] ~= nil, region.Id .. ": unlock project " .. u.Project)
		end
		if u.Secret then
			check(Registry.Secrets[u.Secret] ~= nil, region.Id .. ": unlock secret " .. u.Secret)
		end
	end
end
for _, node in Gathering.Nodes do
	for _, drop in node.Drops do
		item(drop.Id, "node " .. node.Id)
	end
end
for _, travel in World.Travel do
	check(Registry.Regions[travel.Region] ~= nil, "travel region " .. travel.Region)
end
for _, fish in Fish.List do
	check(fish.Difficulty >= 1 and fish.Difficulty <= 100, fish.Id .. " difficulty")
	if fish.Bait then
		item(fish.Bait, fish.Id .. " bait")
	end
	for _, w in fish.Weather or {} do
		check(Weather.Types[w] ~= nil, fish.Id .. ": weather " .. w)
	end
	local waterExists = false
	for _, region in Regions.List do
		for _, water in region.Waters do
			if table.find(fish.Waters, water.Tag) then
				waterExists = true
			end
		end
	end
	if table.find(fish.Waters, "Pond") then
		waterExists = true
	end
	check(waterExists, fish.Id .. ": its water exists somewhere")
end
for _, id in Fish.Junk.Items do
	item(id, "fish junk")
end

-- Quests -------------------------------------------------------------------------------------
section("Quests")
for _, quest in Quests.List do
	if quest.Giver then
		check(Registry.Npcs[quest.Giver] ~= nil, quest.Id .. ": unknown giver")
	end
	if quest.TurnIn then
		check(Registry.Npcs[quest.TurnIn] ~= nil, quest.Id .. ": unknown turn-in npc")
	end
	local req = quest.Requires or {}
	if req.Quest then
		check(Registry.Quests[req.Quest] ~= nil, quest.Id .. ": requires unknown quest " .. req.Quest)
	end
	if req.Hearts then
		check(Registry.Npcs[req.Hearts[1]] ~= nil, quest.Id .. ": requires hearts of unknown npc")
	end
	for _, o in quest.Objectives do
		if o.Type == "Deliver" or o.Type == "Harvest" or o.Type == "Craft" or o.Type == "Catch" then
			if o.Target and string.sub(o.Target, 1, 1) ~= "@" then
				spec(o.Target, quest.Id .. " objective")
			end
		elseif o.Type == "Talk" and o.Target ~= "*" then
			check(Registry.Npcs[o.Target] ~= nil, quest.Id .. ": talk to unknown npc " .. tostring(o.Target))
		elseif o.Type == "Visit" then
			check(Registry.Regions[o.Target] ~= nil, quest.Id .. ": visit unknown region " .. tostring(o.Target))
		elseif o.Type == "Secret" then
			check(Registry.Secrets[o.Target] ~= nil, quest.Id .. ": unknown secret " .. tostring(o.Target))
		elseif o.Type == "Mutation" and o.Target ~= "*" then
			check(Registry.Mutations[o.Target] ~= nil, quest.Id .. ": unknown mutation " .. tostring(o.Target))
		elseif o.Type == "Place" then
			spec(o.Target, quest.Id .. " place")
		elseif o.Type == "Project" and o.Target ~= "*" and o.Target ~= "Contribute" then
			check(Registry.Projects[o.Target] ~= nil, quest.Id .. ": unknown project " .. tostring(o.Target))
		elseif o.Type == "BuyAnimal" then
			check(Registry.Species[o.Target] ~= nil, quest.Id .. ": unknown species")
		end
	end
	rewards(quest.Rewards, quest.Id)
	if quest.Rewards.Unlock then
		check(Registry.Npcs[quest.Rewards.Unlock] ~= nil, quest.Id .. ": unlocks unknown npc")
	end
end
for _, drop in Quests.Drops do
	check(Registry.Quests[drop.Quest] ~= nil, "quest drop quest " .. drop.Quest)
	item(drop.Item, "quest drop")
end
for _, list in { Quests.Daily, Quests.Weekly, Quests.Community } do
	for _, template in list do
		rewards(template.Reward, template.Id)
	end
end

-- Festivals ------------------------------------------------------------------------------------
section("Festivals")
for _, festival in Festivals.List do
	check(festival.Season >= 1 and festival.Season <= 4, festival.Id .. " season")
	check(festival.Day >= 1 and festival.Day <= require(Config.Time).DaysPerSeason, festival.Id .. " day")
	for _, entry in festival.Shop do
		item(entry.Id, festival.Id .. " shop")
	end
	for _, prize in festival.Prizes do
		rewards(prize, festival.Id .. " prize")
	end
	if festival.Weather then
		check(Weather.Types[festival.Weather] ~= nil, festival.Id .. " weather")
	end
end

-- Achievements, secrets, social, tutorial, land ------------------------------------------------
section("Misc references")
for _, achievement in Achievements.List do
	rewards(achievement.Reward, "achievement " .. achievement.Id)
	if achievement.Reward.Banner then
		check(Achievements.Banners[achievement.Reward.Banner] ~= nil, achievement.Id .. " banner")
	end
	if achievement.Reward.Frame then
		check(Achievements.Frames[achievement.Reward.Frame] ~= nil, achievement.Id .. " frame")
	end
	if achievement.Reward.Effect then
		check(Achievements.Effects[achievement.Reward.Effect] ~= nil, achievement.Id .. " effect")
	end
end
local loreIds = {}
for _, lore in Secrets.Lore do
	loreIds[lore.Id] = true
end
for _, secret in Secrets.List do
	check(Registry.Regions[secret.Region] ~= nil, secret.Id .. " region")
	rewards(secret.Reward, "secret " .. secret.Id)
	if secret.Reward.Lore then
		check(loreIds[secret.Reward.Lore], secret.Id .. ": unknown lore")
	end
	if secret.Needs and secret.Needs.Item then
		spec(secret.Needs.Item, secret.Id .. " needs")
	end
	for _, entry in secret.Consume or {} do
		spec(entry[1], secret.Id .. " consume")
	end
end
for i, reward in Social.Daily do
	rewards(reward, "daily " .. i)
end
check(#Social.Daily == 28, "28 daily rewards")
for _, entry in Tutorial.StarterItems do
	item(entry[1], "starter item")
end
for _, entry in Tutorial.RewardItems do
	item(entry[1], "tutorial reward")
end
for _, row in Land.Layout do
	for _, typeId in row do
		check(Land.Types[typeId] ~= nil, "parcel type " .. typeId)
	end
end
for _, house in Land.House do
	for _, mat in house.Mats do
		item(mat.Id, "house mats")
	end
end
for _, project in Land.Projects do
	for _, entry in project.Items do
		spec(entry[1], "project " .. project.Id)
	end
end
for _, family in Tools.Families do
	check(#family.Tiers == 6, family.Id .. " has 6 tiers")
	for _, tier in family.Tiers do
		for _, mat in tier.Mats do
			item(mat.Id, family.Id .. " upgrade mats")
		end
	end
end
for _, species in Animals.List do
	item(species.Product, species.Id .. " product")
	for _, feed in species.Feed do
		item(feed, species.Id .. " feed")
	end
	for _, product in species.CoatProducts or {} do
		item(product, species.Id .. " coat product")
	end
end
for _, s in Settings.Specs do
	if s.Kind == "Choice" then
		check(table.find(s.Options, s.Default) ~= nil, "setting default in options: " .. s.Key)
	elseif s.Kind == "Slider" then
		check(s.Default >= s.Min and s.Default <= s.Max, "setting default in range: " .. s.Key)
	end
end
for name, sound in AudioConfig.Sounds do
	check(type(sound.Id) == "string" and sound.Id ~= "", "sound id " .. name)
end
for _, entry in Store.Items do
	for _, c in (entry.Grants.Cosmetic or {}) do
		check(Store.Cosmetics[c] ~= nil, "store cosmetic " .. c)
	end
end

-- Math -----------------------------------------------------------------------------------------
section("RNG / Format / TableUtil")
check(RNG.Hash("a", 1) == RNG.Hash("a", 1), "hash deterministic")
check(RNG.Hash("a", 1) ~= RNG.Hash("a", 2), "hash varies")
do
	local sum = 0
	for i = 1, 2000 do
		sum += RNG.Hash("dist", i)
	end
	check(math.abs(sum / 2000 - 0.5) < 0.05, "hash roughly uniform (" .. sum / 2000 .. ")")
end
check(Format.Short(1234) == "1,234", "short small " .. Format.Short(1234))
check(Format.Short(15300000) == "15.3M", "short big " .. Format.Short(15300000))
check(Format.Duration(3725) == "1h 02m", "duration " .. Format.Duration(3725))
do
	local target = { A = 1, B = { C = 2 } }
	TableUtil.Reconcile(target, { A = 5, B = { C = 9, D = 3 }, E = {} })
	check(target.A == 1 and target.B.C == 2 and target.B.D == 3 and type(target.E) == "table", "reconcile")
end

section("Net validation")
check(Net.Validate("ShopBuy", "general", "seed_carrot", 5), "valid ShopBuy")
check(not Net.Validate("ShopBuy", "general", "seed_carrot", 5.5), "non-int rejected")
check(not Net.Validate("ShopBuy", "general", string.rep("x", 100), 5), "long string rejected")
check(not Net.Validate("ShopBuy", "general", "seed_carrot", 0 / 0), "NaN rejected")
check(not Net.Validate("Nope"), "unknown action rejected")
check(Net.Validate("ToolUse", "tool_hoe", Vector3.new(1, 2, 3), { Size = 3 }), "ToolUse ok")
check(not Net.Validate("ToolUse", "tool_hoe", Vector3.new(1, 0 / 0, 3)), "NaN vector rejected")

section("GameTime / Weather")
do
	local t = GameTime.FromReal(require(Config.Time).Epoch)
	local info = GameTime.Info(t)
	check(
		info.Day == 0 and math.abs(info.Hour - 6) < 1e-6 and info.SeasonId == "Spring" and info.Year == 1,
		"epoch = Spring 1, 6 AM"
	)
	local later = GameTime.Info(t + GameTime.DAY * GameTime.SEASON_DAYS)
	check(later.SeasonId == "Summer", "next season")
	check(GameTime.Info(t + GameTime.YEAR_DAYS * GameTime.DAY).Year == 2, "next year")
	local counts = {}
	for slot = 0, 4000 do
		local w = WeatherMath.At(slot)
		check(Weather.Types[w] ~= nil, "weather valid at " .. slot)
		counts[w] = (counts[w] or 0) + 1
		if (w == "MeteorShower" or w == "Aurora") and not WeatherMath.SlotIsNight(slot) then
			check(false, "night-only weather in a day slot " .. slot)
		end
	end
	check((counts.Sunny or 0) > 800, "sunny is common")
	check((counts.Rain or 0) > 100, "rain happens")
	check(WeatherMath.At(1234) == WeatherMath.At(1234), "weather deterministic")
	check(#WeatherMath.Forecast(3, t) == 3, "forecast length")
end

section("Items / quality")
do
	local a = ItemUtil.New("strawberry", 3, 2, { "Golden" })
	local b = ItemUtil.New("strawberry", 5, 2, { "Golden" })
	local c = ItemUtil.New("strawberry", 5, 3, { "Golden" })
	check(ItemUtil.CanStack(a, b), "same stacks merge")
	check(not ItemUtil.CanStack(a, c), "different quality doesn't merge")
	check(ItemUtil.DisplayName(a) == "Golden Strawberry", "display name " .. ItemUtil.DisplayName(a))
	check(ItemUtil.MutationMultiplier({ "Golden" }) == 3, "golden x3")
	local mm = ItemUtil.MutationMultiplier({ "Golden", "Rainbow" })
	check(math.abs(mm - 4 * (1 + 2 * Mutations.StackFalloff)) < 1e-9, "stack falloff " .. mm)
	check(
		ItemUtil.MutationMultiplier({ "Celestial", "Glowing", "Moonkissed", "Astral", "Rainbow" }) <= Mutations.ValueCap,
		"value cap"
	)
	check(ItemUtil.UnitValue(ItemUtil.New("carrot", 1)) == Registry.Items.carrot.Value, "unit value base")
	check(
		ItemUtil.Valid(a)
			and not ItemUtil.Valid({ Id = "nope", N = 1 })
			and not ItemUtil.Valid({ Id = "carrot", N = 0 }),
		"stack validation"
	)
	local last = -1
	for score = 0, 100 do
		local tier = QualityMath.TierFor(score / 100)
		check(tier >= last, "tiers monotonic")
		last = tier
	end
	check(QualityMath.TierFor(1) == 6 and QualityMath.TierFor(0) == 1, "tier bounds")
	check(QualityMath.TierFor(1, 3) == 3, "max tier clamp")
end

section("Genetics")
do
	local random = Random.new(42)
	for _ = 1, 200 do
		local g = Genetics.Cross({ 10, 10, 10, 10 }, { 0, 0, 0, 0 }, random)
		for i = 1, 4 do
			check(g[i] >= 0 and g[i] <= 10, "gene in range")
		end
	end
	local chickenA = Genetics.RandomAnimal("chicken", random)
	local chickenB = Genetics.RandomAnimal("chicken", random)
	local odds = Genetics.BreedOdds("chicken", chickenA, chickenB)
	local total = 0
	for _, p in odds.Coat do
		total += p
	end
	check(math.abs(total - 1) < 1e-9, "coat odds sum to 1")
	local golden =
		{ Coat = { "golden", "golden" }, Pattern = { "plain", "plain" }, Size = 5, Yield = 5, Temper = 5, Speed = 5 }
	check(Genetics.Phenotype("chicken", golden).Coat.Id == "golden", "homozygous recessive shows")
	local carrier =
		{ Coat = { "white", "golden" }, Pattern = { "plain", "plain" }, Size = 5, Yield = 5, Temper = 5, Speed = 5 }
	check(Genetics.Phenotype("chicken", carrier).Coat.Id == "white", "carrier hides recessive")
	local o = Genetics.BreedOdds("chicken", carrier, carrier)
	check(math.abs((o.Coat.golden or 0) - 0.25) < 1e-9, "carrier x carrier = 25% golden")
	check(Genetics.Hybrid("sunflower", "wheat") ~= nil, "hybrid lookup either order")
	for _ = 1, 50 do
		local child =
			Genetics.Breed("cow", Genetics.RandomAnimal("cow", random), Genetics.RandomAnimal("cow", random), random)
		check(Genetics.ValidAnimal("cow", child), "bred genes valid")
	end
end

section("Crop growth")
do
	local epoch = GameTime.FromReal(require(Config.Time).Epoch)
	local env = CropMath.DefaultEnv()
	env.WeatherAt = function()
		return "Cloudy"
	end
	-- A watered carrot in spring should ripen in about its grow time (± soil/nutrient factors).
	local tile = { W = 100, H = 70, N = 70, P = 70, K = 70 }
	local cs = { Id = "carrot", P = 0, T = epoch, At = epoch, G = { 0, 0, 0, 0 } }
	local grow = Registry.Crops.carrot.Grow
	CropMath.Advance(tile, cs, env, epoch, epoch + grow * 1.05, nil)
	check(cs.P >= 0.99, "carrot ripe after its grow time (P=" .. string.format("%.3f", cs.P) .. ")")
	check(cs.Rp ~= nil, "ripe time recorded")
	-- Dry soil grows much slower.
	local dryTile = { W = 0, H = 70, N = 70, P = 70, K = 70 }
	local dry = { Id = "carrot", P = 0, T = epoch, At = epoch }
	CropMath.Advance(dryTile, dry, env, epoch, epoch + grow, nil)
	check(dry.P < 0.35, "dry carrot grows slowly (P=" .. string.format("%.3f", dry.P) .. ")")
	-- Rain waters outdoor soil.
	local rainEnv = CropMath.DefaultEnv()
	rainEnv.WeatherAt = function()
		return "Rain"
	end
	local rainTile = { W = 0, H = 60, N = 60, P = 60, K = 60 }
	CropMath.Advance(rainTile, { Id = "potato", P = 0, T = epoch }, rainEnv, epoch, epoch + 100, nil)
	check(rainTile.W == 100, "rain fills moisture")
	-- Off-season is dormant outdoors, fine in a greenhouse.
	local winter = epoch + GameTime.DAY * GameTime.SEASON_DAYS * 3
	local outdoor = { Id = "tomato", P = 0, T = winter }
	CropMath.Advance({ W = 100, H = 60, N = 60, P = 60, K = 60 }, outdoor, env, winter, winter + 400, nil)
	local ghEnv = CropMath.DefaultEnv()
	ghEnv.Indoor = true
	ghEnv.WeatherAt = env.WeatherAt
	local indoor = { Id = "tomato", P = 0, T = winter }
	CropMath.Advance({ W = 100, H = 60, N = 60, P = 60, K = 60 }, indoor, ghEnv, winter, winter + 400, nil)
	check(indoor.P > outdoor.P * 4, "greenhouse beats winter outdoors")
	-- A long offline span finishes quickly (chunked) and sprinklers keep soil wet.
	local sprEnv = CropMath.DefaultEnv()
	sprEnv.Sprinkler = 1
	local start = os.clock()
	local sprTile = { W = 100, H = 60, N = 60, P = 60, K = 60 }
	local melon = { Id = "melon", P = 0, T = epoch }
	local summer = epoch + GameTime.DAY * GameTime.SEASON_DAYS
	CropMath.Advance(sprTile, melon, sprEnv, summer, summer + 12 * 3600, Random.new(3))
	check(os.clock() - start < 0.05, "12h offline advance is fast")
	check(melon.P >= 1, "sprinkled melon ripens offline")
	-- Mutations: with a big multiplier, a long grow should mutate at least sometimes.
	local mutated = 0
	local random = Random.new(7)
	for i = 1, 60 do
		local mEnv = CropMath.DefaultEnv()
		mEnv.MutationMult = 20
		local c = { Id = "pumpkin", P = 0, T = epoch }
		CropMath.Advance({ W = 100, H = 60, N = 60, P = 60, K = 60 }, c, mEnv, epoch, epoch + 900, random)
		if c.M and #c.M > 0 then
			mutated += 1
			-- groups stay exclusive
			local hasGiant = table.find(c.M, "Giant")
			local hasTiny = table.find(c.M, "Tiny")
			check(not (hasGiant and hasTiny), "Giant/Tiny exclusive")
		end
	end
	check(mutated > 5, "mutations happen with boosts (" .. mutated .. "/60)")
	-- Combos resolve.
	local comboCrop = { Id = "carrot", M = { "Frosted", "Crystalized" } }
	local added = CropMath.ResolveCombos(comboCrop)
	check(table.find(added, "Glacial") ~= nil, "Glacial combo")
	-- Harvest roll
	local roll = CropMath.RollHarvest(tile, cs, env, cs.Rp + 10, Random.new(1), {})
	check(roll.Tier >= 1 and roll.Tier <= 6 and roll.Count >= 1 and roll.Size > 0, "harvest roll sane")
	local score = CropMath.Score(tile, cs, env, cs.Rp + 10)
	check(score > 0.4, "well-watered carrot scores decently (" .. string.format("%.2f", score) .. ")")
end

section("Market")
do
	local t = GameTime.FromReal(require(Config.Time).Epoch) + 5000
	for _, id in { "carrot", "wine_grape", "tuna", "cheese" } do
		local f = MarketMath.Factor(id, { Time = t, Weather = "Sunny" })
		check(f >= Economy.Market.MinFactor and f <= Economy.Market.MaxFactor, "market factor bounds " .. id)
	end
	check(#MarketMath.HotItems(3) == Economy.Market.HotItems.Count, "hot items")
	check(#MarketMath.History("carrot", t) == Economy.Market.HistoryPoints, "history length")
	local pressured = MarketMath.Factor("carrot", { Time = t, Weather = "Sunny", Pressure = 0.3 })
	local free = MarketMath.Factor("carrot", { Time = t, Weather = "Sunny", Pressure = 0 })
	check(pressured < free, "supply pressure lowers price")
end

section("Stats")
do
	local profile = {
		Skills = { Farming = { XP = 5000, Nodes = { green_thumb = 2 } } },
		Friendship = { pip = { Pts = 800 } },
		Farm = { House = 2 },
	}
	local level = Stats.SkillLevel(profile, "Farming")
	check(level > 5, "farming level from xp " .. level)
	check(
		math.abs(Stats.Effect(profile, "GrowthSpeed") - (0.08 + 0.003 * (level - 1))) < 1e-9,
		"growth effect sums ranks + passive"
	)
	check(Stats.Hearts(profile, "pip") == 3, "hearts")
	check(Stats.ShopDiscount(profile, "general") == 0.05, "pip discount at 3 hearts")
	check(Stats.EstateLevel({ Skills = {} }) == 1, "estate level starts at 1")
	check(Stats.MaxEnergy(profile) > 120, "energy grows with house")
end

-- Contest scoring --------------------------------------------------------------------------------
section("ContestMath")
do
	local giantCrop
	for _, fest in Festivals.List do
		for _, activity in fest.Activities do
			if activity.Id == "giant_crop" then
				giantCrop = activity
			end
			if activity.Kind == "Contest" then
				local total = 0
				for _, w in activity.Scoring do
					total += w
				end
				check(total == 100, activity.Id .. ": scoring weights must sum to 100 (got " .. total .. ")")
			end
		end
	end
	check(giantCrop ~= nil, "giant crop contest exists")
	local plain = { Kind = "Item", Stack = { Id = "pumpkin", N = 1, S = Registry.Crops.pumpkin.Size[1] } }
	local prize = {
		Kind = "Item",
		Stack = {
			Id = "pumpkin",
			N = 1,
			Q = 6,
			S = Registry.Crops.pumpkin.Size[1] + Registry.Crops.pumpkin.Size[2] * 3,
			M = { "Golden" },
			U = "sp1",
		},
	}
	check(ContestMath.Accepts(giantCrop, plain), "crops are accepted in the giant crop contest")
	check(not ContestMath.Accepts(giantCrop, { Kind = "Item", Stack = { Id = "wood", N = 1 } }), "wood isn't a crop")
	local low, lowPoints = ContestMath.Score(giantCrop, plain)
	local high = ContestMath.Score(giantCrop, prize)
	check(low >= 0 and high <= 100, "scores are within 0-100")
	check(high > low + 30, string.format("a giant golden radiant pumpkin beats a plain one (%.1f vs %.1f)", high, low))
	local sum = 0
	for _, pts in lowPoints do
		sum += pts
	end
	check(math.abs(sum - low) < 0.6, "breakdown points add up to the total")
	local animal = {
		Kind = "Animal",
		Animal = { Sp = "cow", Hap = 100, Fr = 1000, G = Genetics.RandomAnimal("cow", Random.new(3)) },
	}
	local livestock = Festivals.List[2].Activities[1]
	check(ContestMath.Accepts(livestock, animal), "animals enter the livestock show")
	local score = ContestMath.Score(livestock, animal)
	check(score > 20, "a happy, loved cow scores well (" .. score .. ")")
end

-- Balance report -----------------------------------------------------------------------------------
section("Balance report (coins per real minute per tile, Common quality, first harvest)")
local rows = {}
for _, crop in Crops.List do
	if crop.Seed then
		local avgYield = (crop.Yield[1] + crop.Yield[2]) / 2
		local profit = crop.Sell * avgYield - crop.Seed
		local perMin = profit / (crop.Grow / 60)
		local regrowPerMin = if crop.Regrow then crop.Sell * avgYield / (crop.Regrow / 60) else nil
		table.insert(rows, { crop.Id, perMin, regrowPerMin, crop.Rarity })
		check(profit > -crop.Seed * 0.5 or crop.Regrow ~= nil, crop.Id .. ": first harvest loses too much")
	end
end
table.sort(rows, function(a, b)
	return a[2] < b[2]
end)
for _, row in rows do
	print(
		string.format(
			"    %-18s %8.1f/min%s  %s",
			row[1],
			row[2],
			if row[3] then string.format("  regrow %6.1f/min", row[3]) else "",
			row[4]
		)
	)
end

if #__warnings > 0 then
	print("warnings:")
	for _, w in __warnings do
		print("  " .. w)
	end
end
print(string.format("\n%d passed, %d failed", passes, failures))
if failures > 0 then
	error("tests failed")
end

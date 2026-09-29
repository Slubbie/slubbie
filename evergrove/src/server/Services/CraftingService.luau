-- Crafting, cooking and alchemy (Config/Recipes), recipe knowledge and
-- experimentation (secret recipes are discovered by combining the right items).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Recipes = require(Shared.Config.Recipes)
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local Stats = require(Shared.Lib.Stats)
local ItemUtil = require(Shared.Lib.ItemUtil)

local S = require(script.Parent)

local CraftingService = {}

local random = Random.new()

function CraftingService.Knows(profile: any, recipe: any): boolean
	return recipe.Unlock.Default == true or profile.Recipes[recipe.Id] == true
end

-- Learn a recipe. Returns true if it was new.
function CraftingService.Learn(player: Player, recipeId: string, silent: boolean?): boolean
	local profile = S.Data.Get(player)
	local recipe = Registry.Recipes[recipeId]
	if not profile or not recipe or profile.Recipes[recipeId] then
		return false
	end
	profile.Recipes[recipeId] = true
	S.Data.Changed(player, "Recipes")
	S.Collection.Discover(player, "Recipes", recipeId)
	if not silent then
		local out = Registry.Items[recipe.Out]
		S.Notify.Toast(player, "📜 New recipe: " .. (out and out.Name or recipeId), "Success")
	end
	return true
end

-- Learn every recipe whose skill/friendship conditions are already met.
function CraftingService.Sync(player: Player)
	local profile = S.Data.Get(player)
	if not profile then
		return
	end
	for _, recipe in Recipes.List do
		local u = recipe.Unlock
		if not profile.Recipes[recipe.Id] then
			if u.Default then
				profile.Recipes[recipe.Id] = true
			elseif u.Skill and Stats.SkillLevel(profile, u.Skill[1]) >= u.Skill[2] then
				profile.Recipes[recipe.Id] = true
			elseif u.Friend and Stats.Hearts(profile, u.Friend[1]) >= u.Friend[2] then
				profile.Recipes[recipe.Id] = true
			end
		end
	end
	S.Data.Changed(player, "Recipes")
end

-- Is the player at a station of this kind?
local function atStation(player: Player, station: string): boolean
	if station == "Hand" then
		return true
	end
	local profile = S.Data.Get(player)
	local farm = S.Farm.Get(player)
	if not profile or not farm then
		return false
	end
	local range = Recipes.StationRange
	if station == "Workbench" then
		return farm.Lot.Workbench ~= nil and S.Security.InReach(player, farm.Lot.Workbench, range)
	end
	if station == "Kitchen" and profile.Farm.House >= 2 and farm.Lot.House then
		-- Cottages and up have a kitchen corner.
		if S.Security.InReach(player, farm.Lot.House, range + 10) then
			return true
		end
	end
	for uid, placed in profile.Farm.Placed do
		local def = Registry.Placeables[placed.Id]
		if def and def.Function and def.Function.Kind == "Station" and def.Function.Station == station then
			local position = S.Building.WorldPosition(player, uid)
			if position and S.Security.InReach(player, position, range) then
				return true
			end
		end
	end
	return false
end
CraftingService.AtStation = atStation

local function craft(player: Player, recipeId: string, times: number)
	local profile = S.Data.Get(player)
	local recipe = Registry.Recipes[recipeId]
	if not profile or not recipe then
		return false, "Unknown recipe"
	end
	times = math.clamp(times, 1, Recipes.MaxBatch)
	if not CraftingService.Knows(profile, recipe) then
		return false, "You don't know that recipe yet"
	end
	if not atStation(player, recipe.Station) then
		return false, "You need to be at a " .. Recipes.Stations[recipe.Station].Name
	end
	for _, input in recipe.In do
		if S.Inventory.Count(player, input[1]) < input[2] * times then
			return false, "Missing " .. Registry.SpecName(input[1])
		end
	end
	local out = Registry.Items[recipe.Out]
	local produced = recipe.N * times
	if recipe.Station == "Kitchen" then
		local extra = Stats.Effect(profile, "ExtraDish")
		for _ = 1, times do
			if random:NextNumber() < extra then
				produced += 1
			end
		end
	end
	if not S.Inventory.CanFit(player, { ItemUtil.New(recipe.Out, produced) }) then
		return false, "Your bag is full"
	end
	-- Consume inputs, tracking quality for cooked dishes.
	local value, qualitySum, qualityCount = 0, 0, 0
	for _, input in recipe.In do
		local removed = S.Inventory.Remove(player, input[1], input[2] * times)
		for _, stack in removed or {} do
			value += ItemUtil.UnitValue(stack) * stack.N
			qualitySum += (stack.Q or 1) * stack.N
			qualityCount += stack.N
		end
	end
	-- Resourceful: sometimes one input comes back.
	local save = Stats.Effect(profile, "CraftSave")
	local refunds = 0
	for _ = 1, times do
		if random:NextNumber() < save then
			refunds += 1
		end
	end
	if refunds > 0 then
		local first = recipe.In[1][1]
		if string.sub(first, 1, 1) ~= "#" then
			S.Inventory.Give(player, first, refunds, nil, nil, { Silent = true })
		end
	end
	local quality = 1
	if recipe.Station == "Kitchen" and qualityCount > 0 then
		quality = math.max(1, math.floor(qualitySum / qualityCount))
		quality = math.max(quality, Stats.Effect(profile, "MinDishQuality"))
	end
	S.Inventory.Add(player, ItemUtil.New(recipe.Out, produced, quality), { Source = "Crafted" })
	S.Collection.OnItem(player, ItemUtil.New(recipe.Out, 1, quality))
	local xp = math.max(2, math.floor(value * Recipes.XPPerValue))
	S.Skill.AddXP(player, recipe.Skill, xp)
	S.Data.AddStat(player, "ItemsCrafted", produced)
	if recipe.Station == "Kitchen" then
		S.Data.AddStat(player, "DishesCooked", produced)
		S.Quest.Progress(player, "Cook", recipe.Out, produced)
	end
	S.Quest.Progress(player, "Craft", recipe.Out, produced)
	if out and out.Placeable then
		S.Notify.Toast(player, "Open Build mode (H) to place your " .. out.Name, "Info")
	end
	return true, produced
end

-- Experimenting: put up to 4 items in; if they match a secret recipe you learn it.
local function experiment(player: Player, ids: { any })
	local profile = S.Data.Get(player)
	if not profile then
		return false, "Not ready"
	end
	local chosen = {}
	for _, id in ids do
		if type(id) == "string" and Registry.Items[id] then
			if S.Inventory.Count(player, id) <= 0 then
				return false, "You don't have " .. Registry.Items[id].Name
			end
			table.insert(chosen, id)
		end
	end
	if #chosen < 2 or #chosen > Recipes.MaxExperimentItems then
		return false, "Combine 2 to " .. Recipes.MaxExperimentItems .. " different items"
	end
	for _, recipe in Recipes.List do
		if recipe.Unlock.Secret and #recipe.In == #chosen and not profile.Recipes[recipe.Id] then
			local used = {}
			local ok = true
			for _, input in recipe.In do
				local found = false
				for i, id in chosen do
					if not used[i] and Registry.Matches(id, input[1]) then
						used[i] = true
						found = true
						break
					end
				end
				if not found then
					ok = false
					break
				end
			end
			if ok then
				CraftingService.Learn(player, recipe.Id, true)
				S.Data.AddStat(player, "SecretRecipes")
				local out = Registry.Items[recipe.Out]
				S.Notify.Discovery(
					player,
					"Recipes",
					recipe.Id,
					{ Name = out.Name, Icon = out.Icon, Rarity = "Epic", Secret = true }
				)
				return true, recipe.Id
			end
		end
	end
	profile.Stats.ExperimentFails = (profile.Stats.ExperimentFails or 0) + 1
	S.Data.Changed(player, "Stats", "ExperimentFails")
	if profile.Stats.ExperimentFails % Recipes.HintAfter == 0 then
		for _, recipe in Recipes.List do
			if recipe.Unlock.Secret and not profile.Recipes[recipe.Id] then
				local hintItem = recipe.In[1][1]
				return false,
					"Nothing happened... but you sense "
						.. Registry.SpecName(hintItem)
						.. " wants to be part of something."
			end
		end
	end
	return false, "Nothing happened."
end

function CraftingService.Init()
	Net.Handle("Craft", craft)
	Net.Handle("Experiment", experiment)
end

function CraftingService.Start()
	S.Data.Loaded:Connect(CraftingService.Sync)
	S.Skill.LevelUp:Connect(function(player)
		CraftingService.Sync(player)
	end)
end

return CraftingService

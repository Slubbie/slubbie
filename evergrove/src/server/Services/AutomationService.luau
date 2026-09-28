-- Farm automation: harvest drones, farmbots, auto-feeders, product
-- collectors, the logistics network, the shipping dock and farm rules.
--
-- Sprinklers, mist towers and water towers work through the crop
-- environment (FarmService/CropMath), so they're not handled here.
--
-- Rules (profile.Farm.Rules, edited with the Farm Controller / dock UI):
--   Sell      { spec... }         silo items the shipping dock sells each dawn ("#Fruit", "egg")
--   Replant   { [cropId] = false } drones skip replanting these crops
--   Priority  { [machineUid] = n } logistics feeds higher priority machines first
--   Bots      { [farmbotUid] = cropId } what each farmbot plants
--
-- Devices run in cycles (every CYCLE seconds) on online farms with a per-cycle
-- budget from their PerMinute rate (raised by the Automation skill). The first
-- cycle after joining gets a bigger budget so drones catch up on crops that
-- ripened while you were away.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local ItemUtil = require(Shared.Lib.ItemUtil)
local Stats = require(Shared.Lib.Stats)
local Format = require(Shared.Lib.Format)
local GameTime = require(Shared.Lib.GameTime)
local Soil = require(Shared.Config.Soil)

local S = require(script.Parent)

local CYCLE = 30
local CATCH_UP_MULT = 10
local DOCK_RATE = 0.95
local MAX_SELL_RULES = 40

local AutomationService = {}

local catchUp: { [Player]: boolean } = {}

-- Helpers ------------------------------------------------------------------------------------------------

local function devices(profile: any, kind: string): { { Uid: string, Def: any, Record: any, X: number, Z: number } }
	local out = {}
	for uid, record in profile.Farm.Placed do
		local def = Registry.Placeables[record.Id]
		if def and def.Function and def.Function.Kind == kind then
			local cx, cz = S.Building.CenterTile(record)
			table.insert(out, { Uid = uid, Def = def, Record = record, X = cx, Z = cz })
		end
	end
	return out
end

local function inRange(device: any, gx: number, gz: number): boolean
	local r = (device.Def.Radius or 0) + math.max(device.Def.Size[1], device.Def.Size[2]) / 2
	return (gx - device.X) ^ 2 + (gz - device.Z) ^ 2 <= r * r
end

local function budget(profile: any, perMinute: number, player: Player): number
	local rate = perMinute * CYCLE / 60 * (1 + Stats.Effect(profile, "Automation"))
	if catchUp[player] then
		rate *= CATCH_UP_MULT
	end
	return math.max(1, math.floor(rate))
end

local function siloFree(player: Player): number
	return S.Inventory.SiloCapacity(player) - S.Inventory.SiloCount(player)
end

local function droneFx(player: Player, device: any, farm: any, keys: { string })
	if #keys == 0 then
		return
	end
	local from = S.Building.WorldPosition(player, device.Uid)
	local targets = {}
	for i = 1, math.min(#keys, 8) do
		local gx, gz = S.Farm.ParseKey(keys[i])
		table.insert(targets, S.Farm.TileCenter(farm, gx, gz))
	end
	if from then
		S.Notify.FX(from, "Drones", { From = from, To = targets, Kind = device.Def.Function.Kind }, 300)
	end
end

-- Harvest drones -------------------------------------------------------------------------------------------

local function runHarvesters(player: Player, profile: any, farm: any): number
	local hubs = devices(profile, "Harvester")
	if #hubs == 0 then
		return 0
	end
	local harvested = 0
	for _, hub in hubs do
		local left = budget(profile, hub.Def.Function.PerMinute, player)
		local done = {}
		for key, tile in profile.Farm.Tiles do
			if left <= 0 or siloFree(player) <= 0 then
				break
			end
			local cs = tile.C
			if cs and (cs.P or 0) >= 0.999 then
				local gx, gz = S.Farm.ParseKey(key)
				if inRange(hub, gx, gz) then
					local cropId = cs.Id
					local regrows = Registry.Crops[cropId] and Registry.Crops[cropId].Regrow ~= nil
					local stacks = S.Crop.Harvest(player, key, player, { ToSilo = true })
					if stacks then
						harvested += 1
						left -= 1
						table.insert(done, key)
						-- Replant from silo seeds unless a rule says not to.
						if hub.Def.Function.Replant and not regrows and profile.Farm.Rules.Replant[cropId] ~= false then
							local seed = S.Inventory.SiloTake(player, "seed_" .. cropId, 1)[1]
							if seed then
								local ok = S.Crop.Plant(player, key, seed, player)
								if not ok then
									S.Inventory.SiloAdd(player, seed)
								end
							end
						end
					end
				end
			end
		end
		droneFx(player, hub, farm, done)
	end
	if harvested > 0 then
		S.Data.AddStat(player, "DroneHarvests", harvested)
	end
	return harvested
end

-- Farmbots --------------------------------------------------------------------------------------------------

local function runFarmbots(player: Player, profile: any, farm: any)
	for _, bot in devices(profile, "Farmbot") do
		local left = budget(profile, bot.Def.Function.PerMinute, player)
		local cropId = profile.Farm.Rules.Bots[bot.Uid]
		local crop = cropId and Registry.Crops[cropId]
		local r = math.ceil(bot.Def.Radius or 0)
		local touched = {}
		for dx = -r, r do
			for dz = -r, r do
				if left <= 0 then
					break
				end
				local gx, gz = bot.X + dx, bot.Z + dz
				if (dx ~= 0 or dz ~= 0) and gz >= 0 and inRange(bot, gx, gz) then
					local key = S.Farm.Key(gx, gz)
					local tile = profile.Farm.Tiles[key]
					if not tile and crop then
						-- Till only when there's something to plant.
						if S.Farm.Tillable(player, gx, gz) and S.Inventory.SiloCountOf(player, "seed_" .. cropId) > 0 then
							if S.Soil.Till(player, gx, gz, 1) then
								left -= 1
								tile = profile.Farm.Tiles[key]
								table.insert(touched, key)
							end
						end
					end
					if tile and not tile.C and crop and left > 0 then
						local seed = S.Inventory.SiloTake(player, "seed_" .. cropId, 1)[1]
						if seed then
							if S.Crop.Plant(player, key, seed, player) then
								left -= 1
								table.insert(touched, key)
							else
								S.Inventory.SiloAdd(player, seed)
							end
						end
					end
					if tile and tile.C and left > 0 then
						local band = Soil.WaterBands[(Registry.Crops[tile.C.Id] or {}).Water or "Medium"]
						if (tile.W or 0) < band.Min + 5 then
							if S.Soil.Water(player, key, player) then
								left -= 1
								table.insert(touched, key)
							end
						end
					end
				end
			end
		end
		droneFx(player, bot, farm, touched)
	end
end

-- Animal automation ---------------------------------------------------------------------------------------------

local function homeTile(profile: any, uid: string): (number?, number?)
	local record = profile.Farm.Placed[uid]
	if not record then
		return nil, nil
	end
	return S.Building.CenterTile(record)
end

local function runCollectors(player: Player, profile: any): number
	local collectors = devices(profile, "Collector")
	if #collectors == 0 then
		return 0
	end
	local collected = 0
	for aid, animal in profile.Farm.Animals do
		local hx, hz = homeTile(profile, animal.Home)
		if hx then
			for _, device in collectors do
				if inRange(device, hx :: number, hz :: number) then
					S.Animal.Settle(player, aid)
					if (animal.Rd or 0) > 0 and siloFree(player) > 0 then
						for _, stack in S.Animal.Harvest(player, aid, animal.Rd) do
							local leftover = S.Inventory.SiloAdd(player, stack)
							if leftover > 0 then
								S.Inventory.Add(player, ItemUtil.Split(stack, leftover), { Source = "Product Collector", Silent = true })
							end
							collected += stack.N
						end
						S.Animal.Render(player, aid)
					end
					break
				end
			end
		end
	end
	if collected > 0 then
		S.Data.Changed(player, "Farm", "Animals")
	end
	return collected
end

local function runFeeders(player: Player, profile: any): (number, number)
	local feeders = devices(profile, "Feeder")
	if #feeders == 0 then
		return 0, 0
	end
	local fed, hungry = 0, 0
	local today = GameTime.DayIndex(GameTime.Now())
	for aid, animal in profile.Farm.Animals do
		local hx, hz = homeTile(profile, animal.Home)
		if hx then
			for _, device in feeders do
				if inRange(device, hx :: number, hz :: number) then
					if S.Animal.FeedFromSilo(player, aid) then
						fed += 1
						S.Animal.Render(player, aid)
					else
						local settled = S.Animal.Settle(player, aid)
						if settled and (settled.Fed or -1) < today then
							hungry += 1
						end
					end
					break
				end
			end
		end
	end
	if fed > 0 then
		S.Data.Changed(player, "Farm", "Animals")
	end
	return fed, hungry
end

-- Logistics ----------------------------------------------------------------------------------------------------

local function runLogistics(player: Player, profile: any)
	if not S.Machine.HasLogistics(player) then
		return
	end
	local machines = {}
	S.Machine.Each(player, function(uid, record)
		if record.M and record.M.A then
			table.insert(machines, uid)
		end
	end)
	local priority = profile.Farm.Rules.Priority
	table.sort(machines, function(a, b)
		local pa, pb = tonumber(priority[a]) or 0, tonumber(priority[b]) or 0
		if pa ~= pb then
			return pa > pb
		end
		return a < b
	end)
	for _, uid in machines do
		S.Machine.AutoCycle(player, uid)
	end
end

-- Shipping dock -------------------------------------------------------------------------------------------------

local function matchesSellRule(profile: any, itemId: string): boolean
	for _, spec in profile.Farm.Rules.Sell do
		if Registry.Matches(itemId, spec) then
			return true
		end
	end
	return false
end

local function runDock(player: Player, profile: any)
	if #devices(profile, "Dock") == 0 or #profile.Farm.Rules.Sell == 0 then
		return
	end
	local total, count = 0, 0
	for key, stack in profile.Silo.Items do
		if matchesSellRule(profile, stack.Id) and ItemUtil.Sellable(stack) then
			local earned = S.Market.AutoSell(player, stack, DOCK_RATE)
			if earned > 0 then
				total += earned
				count += stack.N
				profile.Silo.Items[key] = nil
			end
		end
	end
	if count > 0 then
		S.Data.Changed(player, "Silo")
		S.Data.AddStat(player, "DockSales", total)
		S.Notify.Toast(player, string.format("🚢 The shipping dock sold %s items for %s.", Format.Commas(count), Format.Coins(total)), "Success")
	end
end

-- Rules ------------------------------------------------------------------------------------------------------------

local function setRules(player: Player, rules: any)
	local profile = S.Data.Get(player)
	if not profile or type(rules) ~= "table" then
		return false, "Bad rules"
	end
	local current = profile.Farm.Rules
	current.Bots = current.Bots or {}
	local hasController = #devices(profile, "Controller") > 0
	local hasDock = #devices(profile, "Dock") > 0
	if rules.Sell ~= nil then
		if not hasDock and not hasController then
			return false, "Build a Shipping Dock to set auto-sell rules"
		end
		if type(rules.Sell) ~= "table" then
			return false, "Bad sell list"
		end
		local list = {}
		for _, spec in rules.Sell do
			if type(spec) == "string" and #spec <= 48 and #list < MAX_SELL_RULES then
				local valid = Registry.Items[spec] ~= nil or (string.sub(spec, 1, 1) == "#" and #Registry.WithTag(string.sub(spec, 2)) > 0)
				if valid and not table.find(list, spec) then
					table.insert(list, spec)
				end
			end
		end
		current.Sell = list
	end
	if rules.Replant ~= nil then
		if not hasController then
			return false, "Build a Farm Controller to program replanting"
		end
		local map = {}
		for cropId, allow in rules.Replant do
			if type(cropId) == "string" and Registry.Crops[cropId] and allow == false then
				map[cropId] = false
			end
		end
		current.Replant = map
	end
	if rules.Priority ~= nil then
		if not hasController then
			return false, "Build a Farm Controller to set machine priorities"
		end
		local map = {}
		for uid, n in rules.Priority do
			local record = type(uid) == "string" and profile.Farm.Placed[uid]
			local def = record and Registry.Placeables[record.Id]
			if def and def.Function and def.Function.Kind == "Machine" and type(n) == "number" then
				map[uid] = math.clamp(math.floor(n), -10, 10)
			end
		end
		current.Priority = map
	end
	if rules.Bots ~= nil then
		for uid, cropId in rules.Bots do
			local record = type(uid) == "string" and profile.Farm.Placed[uid]
			local def = record and Registry.Placeables[record.Id]
			if def and def.Function and def.Function.Kind == "Farmbot" then
				if cropId == false or cropId == "" then
					current.Bots[uid] = nil
				elseif type(cropId) == "string" and Registry.Crops[cropId] and Registry.Items["seed_" .. cropId] then
					current.Bots[uid] = cropId
				end
			end
		end
	end
	S.Data.Changed(player, "Farm", "Rules")
	return true, current
end

-- Lifecycle ----------------------------------------------------------------------------------------------------

local function cycle(player: Player)
	local profile = S.Data.Get(player)
	local farm = S.Farm.Get(player)
	if not profile or not farm then
		return
	end
	profile.Farm.Rules.Bots = profile.Farm.Rules.Bots or {}
	local ok, err = pcall(function()
		runHarvesters(player, profile, farm)
		runFarmbots(player, profile, farm)
		runCollectors(player, profile)
		runLogistics(player, profile)
	end)
	if not ok then
		warn("[Evergrove] Automation cycle failed for", player.Name, err)
	end
	catchUp[player] = nil
end

function AutomationService.Init()
	Net.Handle("AutomationRules", setRules)
end

function AutomationService.Start()
	S.Farm.Ready:Connect(function(player)
		catchUp[player] = true
		task.delay(5, cycle, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		catchUp[player] = nil
	end)
	S.Time.Dawn:Connect(function()
		for player in S.Farm.All() do
			local profile = S.Data.Get(player)
			if profile then
				local ok, err = pcall(function()
					local fed, hungry = runFeeders(player, profile)
					if fed > 0 or hungry > 0 then
						local text = string.format("🥣 Auto-feeders fed %d animal%s.", fed, if fed == 1 then "" else "s")
						if hungry > 0 then
							text ..= string.format(" %d went hungry — stock your silo with feed!", hungry)
						end
						S.Notify.Toast(player, text, if hungry > 0 then "Warning" else "Info")
					end
					runDock(player, profile)
				end)
				if not ok then
					warn("[Evergrove] Dawn automation failed for", player.Name, err)
				end
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(CYCLE)
			for player in S.Farm.All() do
				cycle(player)
				task.wait() -- spread the work across frames
			end
		end
	end)
end

return AutomationService

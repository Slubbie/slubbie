-- Tools and field actions.
--
-- The client sends ToolUse(itemId, targetPosition, { Size, Mode, Dir }) when
-- the player uses whatever is in their selected hotbar slot. The server checks,
-- in order: the item really is equipped, the action cooldown, reach, which
-- farm/tile is targeted, the visitor permission for that action, the area of
-- effect allowed by the tool tier, and energy — then dispatches to the owning
-- service (Soil, Crop...). Nothing the client says about outcomes is trusted.
--
-- Also: hotbar selection (and the held-item attribute other clients animate),
-- watering can refills, tool upgrades at the forge, and powered equipment.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tools = require(Shared.Config.Tools)
local Soil = require(Shared.Config.Soil)
local World = require(Shared.Config.World)
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local Stats = require(Shared.Lib.Stats)
local ItemUtil = require(Shared.Lib.ItemUtil)

local S = require(script.Parent)

local ToolService = {}

local familyById = {}
for _, family in Tools.Families do
	familyById[family.Id] = family
end

local lastUse: { [Player]: number } = {}
local FORGE_RANGE = 40

-- Equipped item ------------------------------------------------------------------------------------

function ToolService.Equipped(player: Player): (ItemUtil.Stack?, string?)
	local profile = S.Data.Get(player)
	if not profile then
		return nil, nil
	end
	local slot = profile.Hotbar or 0
	if slot < 1 or slot > 9 then
		return nil, nil
	end
	local stack = profile.Inventory.Slots[tostring(slot)]
	return stack, "inv:" .. slot
end

function ToolService.Tier(player: Player, familyId: string): number
	local profile = S.Data.Get(player)
	return if profile then profile.Tools[familyId] or 1 else 1
end

function ToolService.TierDef(player: Player, familyId: string)
	local family = familyById[familyId]
	return family.Tiers[math.clamp(ToolService.Tier(player, familyId), 1, #family.Tiers)]
end

local function setHeld(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local stack = ToolService.Equipped(player)
	local def = stack and Registry.Items[stack.Id]
	character:SetAttribute("Held", if stack then stack.Id else nil)
	character:SetAttribute("HeldTier", if def and def.Tool then ToolService.Tier(player, def.Tool) else nil)
	-- Powered equipment: drive it.
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if def and def.Powered and def.Powered.Speed then
		character:SetAttribute("Vehicle", def.Id)
		if humanoid then
			humanoid.WalkSpeed = def.Powered.Speed
		end
	elseif character:GetAttribute("Vehicle") then
		character:SetAttribute("Vehicle", nil)
		S.Player.ApplyWalkSpeed(player)
	end
end

function ToolService.OnInventoryChanged(player: Player)
	setHeld(player)
end

local function selectSlot(player: Player, slot: number)
	local profile = S.Data.Get(player)
	if not profile then
		return
	end
	profile.Hotbar = math.clamp(slot, 0, 9)
	S.Data.Changed(player, "Hotbar")
	setHeld(player)
end

-- Helpers -----------------------------------------------------------------------------------------------

local function actAnimation(player: Player, action: string)
	local character = player.Character
	if character then
		character:SetAttribute("Act", action .. "@" .. string.format("%.3f", os.clock()))
	end
end

local function result(player: Player, ok: number, reason: string?, extra: { [string]: any }?)
	local payload = { Ok = ok, Reason = reason }
	for k, v in pairs(extra or {}) do
		payload[k] = v
	end
	Net.Fire(player, "FX", "ToolResult", payload)
end

-- Square of tiles (size odd) around gx, gz, clipped to the grid.
local function area(gx: number, gz: number, size: number): { { number } }
	local half = math.floor(size / 2)
	local out = {}
	for dx = -half, half do
		for dz = -half, half do
			if #out < Soil.MaxAoETiles and S.Farm.InGrid(gx + dx, gz + dz) then
				table.insert(out, { gx + dx, gz + dz })
			end
		end
	end
	return out
end

-- A strip `width` wide across the direction of travel (tractors).
local function strip(gx: number, gz: number, width: number, dir: Vector3?): { { number } }
	local half = math.floor(width / 2)
	local out = {}
	local horizontal = dir == nil or math.abs(dir.Z) >= math.abs(dir.X)
	for i = -half, half do
		local x, z = if horizontal then gx + i else gx, if horizontal then gz else gz + i
		if S.Farm.InGrid(x, z) then
			table.insert(out, { x, z })
		end
	end
	return out
end

local function chosenSize(opts: any?, maxArea: number, player: Player): number
	local profile = S.Data.Get(player)
	local default = if profile and profile.Settings.ToolArea == "1x1" then 1 else maxArea
	local size = if opts and type(opts.Size) == "number" then opts.Size else default
	size = math.clamp(math.floor(size), 1, maxArea)
	if size % 2 == 0 then
		size -= 1
	end
	return math.max(1, size)
end

-- Is there water at this position (farm pond/well, or terrain water)?
function ToolService.IsWater(_player: Player, position: Vector3): boolean
	local farm, gx, gz = S.Farm.FarmAt(position)
	if farm and gx and S.Farm.WaterAt(farm, S.Farm.Key(gx, gz :: number)) then
		return true
	end
	if farm and farm.Lot.Well and (farm.Lot.Well - position).Magnitude < 8 then
		return true
	end
	local region = Vector3.new(4, 6, 4)
	local ok, materials = pcall(function()
		local r = Region3.new(position - region, position + region):ExpandToGrid(4)
		return workspace.Terrain:ReadVoxels(r, 4)
	end)
	if ok and materials then
		for x = 1, materials.Size.X do
			for y = 1, materials.Size.Y do
				for z = 1, materials.Size.Z do
					if materials[x][y][z] == Enum.Material.Water then
						return true
					end
				end
			end
		end
	end
	return false
end

-- Actions -----------------------------------------------------------------------------------------------------

local function energyFor(player: Player, family: any, tier: any, tiles: number): number
	local profile = S.Data.Get(player)
	local reduction = 0
	if profile then
		if family.Skill == "Mining" then
			reduction = Stats.Effect(profile, "MiningEnergy")
		elseif family.Skill == "Farming" then
			reduction = Stats.Effect(profile, "FarmingEnergy")
		end
	end
	return tier.Energy * tiles * (1 - math.clamp(reduction, 0, 0.8))
end

local function farmAction(player: Player, target: Vector3, permission: string): (any?, number?, number?, string?)
	local farm, gx, gz = S.Farm.FarmAt(target)
	if not farm or not gx then
		return nil, nil, nil, "That's not farmland"
	end
	if not S.Farm.CanAct(player, farm.Owner, permission) then
		return nil, nil, nil, "You don't have permission to do that here"
	end
	return farm, gx, gz, nil
end

local function doTill(player, target, opts)
	local family = familyById.hoe
	local tier = ToolService.TierDef(player, "hoe")
	local farm, gx, gz, reason = farmAction(player, target, "Trusted")
	if not farm then
		result(player, 0, reason)
		return
	end
	local tiles = area(gx, gz, chosenSize(opts, tier.MaxArea, player))
	if not S.Player.SpendEnergy(player, energyFor(player, family, tier, #tiles)) then
		result(player, 0, "Too tired")
		return
	end
	local done, lastReason = 0, nil
	for _, t in tiles do
		local ok, why = S.Soil.Till(farm.Owner, t[1], t[2], ToolService.Tier(player, "hoe"))
		if ok then
			done += 1
		else
			lastReason = why
		end
	end
	if done > 0 then
		actAnimation(player, "Till")
		S.Data.AddStat(player, "TilesTilled", done)
		S.Quest.Progress(player, "Till", "*", done)
		S.Tutorial.Event(player, "Till", done)
		S.Skill.AddXP(player, "Farming", done)
	end
	result(player, done, if done == 0 then lastReason else nil, { Action = "Till" })
end

local function doWater(player, target, opts)
	local profile = S.Data.Get(player)
	local family = familyById.can
	local tier = ToolService.TierDef(player, "can")
	if ToolService.IsWater(player, target) and S.Security.InReach(player, target, Tools.Reach) then
		profile.Water = tier.Capacity or 25
		S.Data.Changed(player, "Water")
		actAnimation(player, "Refill")
		S.Tutorial.Event(player, "Refill")
		result(player, 1, nil, { Action = "Refill" })
		return
	end
	local farm, gx, gz, reason = farmAction(player, target, "Crops")
	if not farm then
		result(player, 0, reason)
		return
	end
	local infinite = (tier.Capacity or 0) >= 9999
	if not infinite and (profile.Water or 0) <= 0 then
		result(player, 0, "Your can is empty. Refill it at water.", { Empty = true })
		return
	end
	local tiles = area(gx, gz, chosenSize(opts, tier.MaxArea, player))
	if not S.Player.SpendEnergy(player, energyFor(player, family, tier, #tiles), false) then
		result(player, 0, "Too tired")
		return
	end
	local done, lastReason = 0, nil
	for _, t in tiles do
		if not infinite and profile.Water <= 0 then
			lastReason = "Your can ran dry"
			break
		end
		local ok, why = S.Soil.Water(farm.Owner, S.Farm.Key(t[1], t[2]), player)
		if ok then
			done += 1
			if not infinite then
				profile.Water -= 1
			end
		else
			lastReason = why
		end
	end
	S.Data.Changed(player, "Water")
	if done > 0 then
		actAnimation(player, "Water")
		S.Skill.AddXP(player, "Farming", math.ceil(done / 2))
	end
	result(player, done, if done == 0 then lastReason else nil, { Action = "Water" })
end

local function doHarvest(player, target, opts)
	local tier = ToolService.TierDef(player, "sickle")
	local farm, gx, gz, reason = farmAction(player, target, "Harvest")
	if not farm then
		result(player, 0, reason)
		return
	end
	local tiles = area(gx, gz, chosenSize(opts, tier.MaxArea, player))
	local done, lastReason = 0, nil
	local bonus = if tier.Ability and string.find(tier.Ability, "10%%") then 0.1 elseif tier.Ability then 0.05 else 0
	for _, t in tiles do
		local key = S.Farm.Key(t[1], t[2])
		local produced, why = S.Crop.Harvest(farm.Owner, key, player, {
			ToolQuality = tier.Quality or 0,
			BonusChance = bonus,
			Position = S.Farm.TileCenter(farm, t[1], t[2]),
		})
		if produced then
			done += 1
		else
			lastReason = why
		end
	end
	if done > 0 then
		actAnimation(player, "Harvest")
		if done >= 5 then
			Net.Fire(player, "FX", "HarvestChain", { Count = done })
		end
	end
	result(player, done, if done == 0 then lastReason else nil, { Action = "Harvest" })
end

local function doPrune(player, target, opts)
	local family = familyById.pruners
	local tier = ToolService.TierDef(player, "pruners")
	local farm, gx, gz, reason = farmAction(player, target, "Crops")
	if not farm then
		result(player, 0, reason)
		return
	end
	local tiles = area(gx, gz, chosenSize(opts, tier.MaxArea, player))
	if not S.Player.SpendEnergy(player, energyFor(player, family, tier, #tiles)) then
		result(player, 0, "Too tired")
		return
	end
	local done, lastReason = 0, nil
	for _, t in tiles do
		local ok, why = S.Crop.Prune(farm.Owner, S.Farm.Key(t[1], t[2]))
		if ok then
			done += 1
		else
			lastReason = why
		end
	end
	if done > 0 then
		actAnimation(player, "Prune")
	end
	result(player, done, if done == 0 then lastReason else nil, { Action = "Prune" })
end

local function doShovel(player, target, opts)
	local family = familyById.shovel
	local tier = ToolService.TierDef(player, "shovel")
	-- Dig spots out in the world take priority.
	if opts and type(opts.Spot) == "string" then
		S.Foraging.Dig(player, opts.Spot)
		return
	end
	local farm, gx, gz, reason = farmAction(player, target, "Trusted")
	if not farm then
		result(player, 0, reason)
		return
	end
	if not S.Player.SpendEnergy(player, energyFor(player, family, tier, 1)) then
		result(player, 0, "Too tired")
		return
	end
	local ok, why = S.Crop.Remove(farm.Owner, S.Farm.Key(gx, gz), player)
	if ok then
		actAnimation(player, "Dig")
	end
	result(player, if ok then 1 else 0, why, { Action = "Dig" })
end

local function doPlant(player, target, opts, stack: ItemUtil.Stack, ref: string)
	local tier = ToolService.TierDef(player, "seeder")
	local farm, gx, gz, reason = farmAction(player, target, "Trusted")
	if not farm then
		result(player, 0, reason)
		return
	end
	local tiles = area(gx, gz, chosenSize(opts, tier.MaxArea, player))
	local done, lastReason = 0, nil
	local profile = S.Data.Get(player)
	for _, t in tiles do
		local current = profile.Inventory.Slots[string.sub(ref, 5)]
		if not current or current.Id ~= stack.Id then
			lastReason = "Out of seeds"
			break
		end
		local key = S.Farm.Key(t[1], t[2])
		local tile = S.Farm.Tile(farm.Owner, key)
		if tile and not tile.C then
			local seed = S.Inventory.TakeFromSlot(player, ref, 1, true)
			if seed then
				local ok, why = S.Crop.Plant(farm.Owner, key, seed, player)
				if ok then
					done += 1
				else
					S.Inventory.Add(player, seed, { Silent = true })
					lastReason = why
				end
			end
		else
			lastReason = if tile then "Something is already growing here" else "Till the soil first"
		end
	end
	if done > 0 then
		actAnimation(player, "Plant")
		S.Skill.AddXP(player, "Farming", done)
	end
	result(player, done, if done == 0 then lastReason else nil, { Action = "Plant" })
end

local function doFertilize(player, target, opts, stack: ItemUtil.Stack, ref: string)
	local farm, gx, gz, reason = farmAction(player, target, "Crops")
	if not farm then
		result(player, 0, reason)
		return
	end
	local size = chosenSize(opts, ToolService.TierDef(player, "seeder").MaxArea, player)
	local tiles = area(gx, gz, size)
	local done, lastReason = 0, nil
	local profile = S.Data.Get(player)
	for _, t in tiles do
		local current = profile.Inventory.Slots[string.sub(ref, 5)]
		if not current or current.Id ~= stack.Id then
			break
		end
		local ok, why = S.Soil.Fertilize(farm.Owner, S.Farm.Key(t[1], t[2]), stack.Id, player)
		if ok then
			done += 1
			S.Inventory.TakeFromSlot(player, ref, 1, true)
		else
			lastReason = why
		end
	end
	if done > 0 then
		actAnimation(player, "Fertilize")
	end
	result(player, done, if done == 0 then lastReason else nil, { Action = "Fertilize" })
end

local SPRAY_AREA = { pest_spray = 3, fungicide = 3, growth_elixir = 5, mutation_serum = 3 }

local function doSpray(player, target, _opts, stack: ItemUtil.Stack, ref: string)
	local farm, gx, gz, reason = farmAction(player, target, "Crops")
	if not farm then
		result(player, 0, reason)
		return
	end
	local tiles = area(gx, gz, SPRAY_AREA[stack.Id] or 3)
	local done = 0
	for _, t in tiles do
		if S.Crop.Spray(farm.Owner, S.Farm.Key(t[1], t[2]), stack.Id) then
			done += 1
		end
	end
	if done == 0 then
		result(player, 0, "Nothing here needs that")
		return
	end
	S.Inventory.TakeFromSlot(player, ref, 1, true)
	actAnimation(player, "Spray")
	result(player, done, nil, { Action = "Spray" })
end

local function doAmend(player, target, _opts, stack: ItemUtil.Stack, ref: string)
	local def = Registry.Items[stack.Id]
	local farm, gx, gz, reason = farmAction(player, target, "Trusted")
	if not farm then
		result(player, 0, reason)
		return
	end
	local ok, why = S.Soil.Amend(farm.Owner, S.Farm.Key(gx, gz), def.Amend)
	if ok then
		S.Inventory.TakeFromSlot(player, ref, 1, true)
		actAnimation(player, "Fertilize")
	end
	result(player, if ok then 1 else 0, why, { Action = "Amend" })
end

-- Powered equipment: tractors work a strip in the chosen mode; the drone works remotely.
local function doPowered(player, target, opts, stack: ItemUtil.Stack)
	local def = Registry.Items[stack.Id]
	local powered = def.Powered
	local profile = S.Data.Get(player)
	local mode = opts and opts.Mode or "Harvest"
	local reach = powered.Range or Tools.Reach
	if not S.Security.InReach(player, target, reach) then
		result(player, 0, "Too far away")
		return
	end
	local farm, gx, gz, reason = farmAction(player, target, if mode == "Harvest" then "Harvest" elseif mode == "Water" then "Crops" else "Trusted")
	if not farm then
		result(player, 0, reason)
		return
	end
	local tiles = if powered.Range then area(gx, gz, powered.Width) else strip(gx, gz, powered.Width, opts and opts.Dir)
	-- Fuel: batteries.
	profile.Powered[stack.Id] = profile.Powered[stack.Id] or { Fuel = 0 }
	local fuel = profile.Powered[stack.Id]
	if fuel.Fuel < #tiles then
		if S.Inventory.Remove(player, "battery", 1) then
			fuel.Fuel += powered.FuelTiles
		else
			result(player, 0, "Out of fuel: carry Battery Packs")
			return
		end
	end
	local done = 0
	local modes = if stack.Id == "hover_tractor" then { "Plow", "Sow", "Water", "Harvest" } else { mode }
	for _, m in modes do
		for _, t in tiles do
			local key = S.Farm.Key(t[1], t[2])
			if m == "Plow" then
				local tile = S.Farm.Tile(farm.Owner, key)
				if not tile and S.Soil.Till(farm.Owner, t[1], t[2], 3) then
					done += 1
				end
			elseif m == "Water" then
				if S.Soil.Water(farm.Owner, key, player) then
					done += 1
				end
			elseif m == "Harvest" then
				if S.Crop.Harvest(farm.Owner, key, player, { Position = S.Farm.TileCenter(farm, t[1], t[2]) }) then
					done += 1
				end
			elseif m == "Sow" and opts and type(opts.Seed) == "string" then
				local tile = S.Farm.Tile(farm.Owner, key)
				if tile and not tile.C then
					local seeds = S.Inventory.Remove(player, opts.Seed, 1)
					if seeds and Registry.Items[opts.Seed] and Registry.Items[opts.Seed].Plants then
						if S.Crop.Plant(farm.Owner, key, seeds[1], player) then
							done += 1
						else
							S.Inventory.Add(player, seeds[1], { Silent = true })
						end
					elseif seeds then
						S.Inventory.Add(player, seeds[1], { Silent = true })
					end
				end
			end
		end
	end
	fuel.Fuel = math.max(0, fuel.Fuel - #tiles)
	S.Data.Changed(player, "Powered")
	if done > 0 then
		actAnimation(player, "Drive")
	end
	result(player, done, nil, { Action = mode, Fuel = fuel.Fuel })
end

-- Dispatch --------------------------------------------------------------------------------------------------

local function toolUse(player: Player, itemId: string, target: Vector3, opts: any?)
	local stack, ref = ToolService.Equipped(player)
	if not stack or stack.Id ~= itemId or not ref then
		return -- stale client state; ignore quietly
	end
	local def = Registry.Items[stack.Id]
	if not def then
		return
	end
	-- Cooldown
	local now = os.clock()
	local speed = if def.Tool then ToolService.TierDef(player, def.Tool).Speed else 1
	if now - (lastUse[player] or 0) < Tools.Cooldown * speed * 0.6 then
		return
	end
	lastUse[player] = now
	-- Reach (powered equipment checks its own range)
	if not def.Powered and not S.Security.InReach(player, target, Tools.Reach) then
		result(player, 0, "Too far away")
		return
	end

	if def.Tool then
		local family = def.Tool
		if family == "hoe" then
			doTill(player, target, opts)
		elseif family == "can" then
			doWater(player, target, opts)
		elseif family == "sickle" then
			doHarvest(player, target, opts)
		elseif family == "pruners" then
			doPrune(player, target, opts)
		elseif family == "shovel" then
			doShovel(player, target, opts)
		elseif family == "axe" or family == "pickaxe" then
			if opts and type(opts.Node) == "string" then
				S.Mining.Hit(player, opts.Node, family)
			else
				actAnimation(player, if family == "axe" then "Chop" else "Mine")
			end
		elseif family == "net" then
			actAnimation(player, "Net")
			local tier = ToolService.TierDef(player, "net")
			S.Player.SpendEnergy(player, tier.Energy, true)
		elseif family == "rod" then
			-- Casting goes through FishCast; this is just the animation for others.
			actAnimation(player, "Cast")
		end
	elseif def.Powered then
		doPowered(player, target, opts, stack)
	elseif def.Plants or stack.Id == "mystery_seed" or stack.Id == "ancient_seed" then
		doPlant(player, target, opts, stack, ref)
	elseif def.Fertilizer then
		doFertilize(player, target, opts, stack, ref)
	elseif def.Use == "Spray" then
		doSpray(player, target, opts, stack, ref)
	elseif def.Use == "Amend" then
		doAmend(player, target, opts, stack, ref)
	end
end

-- Upgrades ------------------------------------------------------------------------------------------------------

local forgePosition: Vector3? = nil
for _, building in World.Buildings do
	if building.Id == "Forge" then
		forgePosition = building.Position
	end
end

local function upgrade(player: Player, familyId: string)
	local profile = S.Data.Get(player)
	local family = familyById[familyId]
	if not profile or not family then
		return false, "Unknown tool"
	end
	if forgePosition and not S.Security.InReach(player, forgePosition, FORGE_RANGE) then
		return false, "Visit Bram's forge to upgrade tools"
	end
	local current = profile.Tools[familyId] or 1
	local nextTier = family.Tiers[current + 1]
	if not nextTier then
		return false, "Already the best there is"
	end
	if Stats.SkillLevel(profile, family.Skill) < nextTier.Level then
		return false, string.format("Requires %s level %d", family.Skill, nextTier.Level)
	end
	local price = math.floor(nextTier.Cost * (1 - Stats.ShopDiscount(profile, "forge")))
	if profile.Coins < price then
		return false, "Not enough coins"
	end
	for _, mat in nextTier.Mats do
		if S.Inventory.Count(player, mat.Id) < mat.N then
			return false, "You need " .. mat.N .. " " .. Registry.Items[mat.Id].Name
		end
	end
	S.Economy.Spend(player, price, "Tool upgrade")
	for _, mat in nextTier.Mats do
		S.Inventory.Remove(player, mat.Id, mat.N)
	end
	profile.Tools[familyId] = current + 1
	S.Data.Changed(player, "Tools")
	if familyId == "can" then
		profile.Water = nextTier.Capacity or profile.Water
		S.Data.Changed(player, "Water")
	end
	-- Pruning shears are learned, not owned, until the first upgrade grants the item.
	if familyId == "pruners" and S.Inventory.Count(player, "tool_pruners") == 0 then
		S.Inventory.Give(player, "tool_pruners", 1)
	end
	S.Farm.InvalidatePlayerEffects(player)
	setHeld(player)
	S.Data.AddStat(player, "ToolUpgrades")
	S.Quest.Progress(player, "Upgrade", familyId, 1)
	S.Notify.Banner(player, nextTier.Name .. " " .. family.Name .. "!", nextTier.Ability or "Bigger area and less effort.", "Upgrade", family.Icon)
	return true, current + 1
end

function ToolService.Init()
	Net.Handle("ToolUse", toolUse)
	Net.Handle("Hotbar", selectSlot)
	Net.Handle("ToolUpgrade", upgrade)
end

function ToolService.Start()
	Players.PlayerRemoving:Connect(function(player)
		lastUse[player] = nil
	end)
	S.Data.Loaded:Connect(function(player)
		setHeld(player)
		-- Old saves may predate a tool: make sure every starter tool exists.
		for _, family in Tools.Families do
			if family.Starter and S.Inventory.Count(player, "tool_" .. family.Id) == 0 then
				S.Inventory.Give(player, "tool_" .. family.Id, 1, nil, nil, { Silent = true })
			end
		end
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function()
			task.wait(0.5)
			setHeld(player)
		end)
	end
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.wait(0.5)
			setHeld(player)
		end)
	end)
end

return ToolService

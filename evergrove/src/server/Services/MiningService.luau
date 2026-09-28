-- Trees, rocks, ore veins and crystals: in regions and on farm parcels.
--
-- Region nodes are shared by everyone on the server. Each hit is validated
-- (reach, region access, tool family and tier, energy). The player who lands
-- the final hit gets the full drops; anyone else who hit it in the last 30
-- seconds gets an assist share, so chopping together is rewarded, not stolen.
-- Depleted nodes leave a stump/rubble and respawn after Respawn seconds.
--
-- Farm nodes grow on Forest and Hillside parcels (Config/Land Clear lists) at
-- stable, per-parcel positions. Clearing one is permanent for that farm
-- (profile.Farm.Cleared[key]) and frees the tile for farming.
--
-- Temporary nodes (meteorites from meteor showers) vanish after a while.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Gathering = require(Shared.Config.Gathering)
local Land = require(Shared.Config.Land)
local Regions = require(Shared.Config.Regions)
local World = require(Shared.Config.World)
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local ItemUtil = require(Shared.Lib.ItemUtil)
local Stats = require(Shared.Lib.Stats)
local RNG = require(Shared.Lib.RNG)
local Nodes = require(Shared.Models.Nodes)

local S = require(script.Parent)

local PARCEL = World.Farms.ParcelTiles
local ASSIST_WINDOW = 30
local ASSIST_SHARE = 0.5
local NODE_COPIES_PER_CLEAR = 2
local random = Random.new()

local MiningService = {}

type NodeState = {
	Nid: string,
	Def: any,
	Region: string?,
	Position: Vector3,
	HP: number,
	Active: boolean,
	Model: Model?,
	Remains: Model?,
	Hitters: { [Player]: number },
	Farm: Player?, -- owner for farm nodes
	Key: string?, -- farm tile key
	Expires: number?,
	Seed: number,
}

local nodes: { [string]: NodeState } = {}
local farmNodes: { [Player]: { [string]: NodeState } } = {} -- owner → tile key → node
local root: Folder

-- Models ------------------------------------------------------------------------------------------------

local function folderFor(node: NodeState): Instance
	if node.Farm then
		local farm = S.Farm.Get(node.Farm)
		if farm then
			local f = farm.Model:FindFirstChild("Nodes")
			if not f then
				f = Instance.new("Folder")
				f.Name = "Nodes"
				f.Parent = farm.Model
			end
			return f
		end
	end
	local regionFolder = root:FindFirstChild(node.Region or "Misc")
	if not regionFolder then
		regionFolder = Instance.new("Folder")
		regionFolder.Name = node.Region or "Misc"
		regionFolder.Parent = root
	end
	return regionFolder
end

local function yawOf(seed: number): CFrame
	return CFrame.Angles(0, (seed % 360) * math.pi / 180, 0)
end

local function show(node: NodeState)
	if node.Remains then
		node.Remains:Destroy()
		node.Remains = nil
	end
	if node.Model then
		node.Model:Destroy()
	end
	local model = Nodes.Build(node.Def, node.Seed)
	model.Name = node.Nid
	model:SetAttribute("Nid", node.Nid)
	model:SetAttribute("HP", node.HP)
	model:SetAttribute("MaxHP", node.Def.HP)
	model:SetAttribute("Tier", node.Def.Tier)
	if node.Farm then
		model:SetAttribute("Owner", node.Farm.UserId)
	end
	model:PivotTo(CFrame.new(node.Position) * yawOf(node.Seed))
	model.Parent = folderFor(node)
	node.Model = model
end

local function hide(node: NodeState)
	if node.Model then
		node.Model:Destroy()
		node.Model = nil
	end
	if not node.Farm and not node.Expires then
		local remains = Nodes.Remains(node.Def)
		remains.Name = node.Nid .. "_remains"
		remains:PivotTo(CFrame.new(node.Position) * yawOf(node.Seed))
		remains.Parent = folderFor(node)
		node.Remains = remains
	end
end

local function destroy(node: NodeState)
	if node.Model then
		node.Model:Destroy()
	end
	if node.Remains then
		node.Remains:Destroy()
	end
	nodes[node.Nid] = nil
end

local function register(nid: string, def: any, position: Vector3, extra: { [string]: any }?): NodeState
	local node: NodeState = {
		Nid = nid,
		Def = def,
		Region = nil,
		Position = position,
		HP = def.HP,
		Active = true,
		Model = nil,
		Remains = nil,
		Hitters = {},
		Farm = nil,
		Key = nil,
		Expires = nil,
		Seed = RNG.HashInt(nid),
	}
	for k, v in pairs(extra or {}) do
		(node :: any)[k] = v
	end
	nodes[nid] = node
	show(node)
	return node
end

-- Region nodes ---------------------------------------------------------------------------------------------

local function spawnRegionNodes()
	for _, region in Regions.List do
		local i = 0
		local ids = {}
		for id in region.Nodes do
			table.insert(ids, id)
		end
		table.sort(ids)
		for _, id in ids do
			local def = Registry.Nodes[id]
			local count = region.Nodes[id]
			if def then
				for n = 1, count do
					i += 1
					local nid = region.Id .. "_" .. id .. "_" .. n
					local point = S.World.SpawnPoint(region.Id, RNG.HashInt(nid), 7)
					if point then
						register(nid, def, point, { Region = region.Id })
					end
				end
			end
		end
	end
end

-- Farm nodes ---------------------------------------------------------------------------------------------------

-- Stable tile positions for a parcel's clearable nodes.
local function parcelNodeTiles(row: number, col: number, clear: { string }): { { Key: string, Id: string } }
	local out = {}
	local used = {}
	local ponds = {}
	local ptype = S.Farm.ParcelType(row, col)
	if ptype.Water then
		for _, key in S.Farm.PondTiles(row, col) do
			ponds[key] = true
		end
	end
	local x0, z0 = (col - 1) * PARCEL, (row - 1) * PARCEL
	local index = 0
	for copy = 1, NODE_COPIES_PER_CLEAR do
		for i, id in clear do
			index += 1
			for attempt = 0, 12 do
				local h = RNG.HashInt("farmnode", row, col, i, copy, attempt)
				local gx = x0 + 1 + h % (PARCEL - 2)
				local gz = z0 + 1 + (h // PARCEL) % (PARCEL - 2)
				local key = gx .. "_" .. gz
				if not used[key] and not ponds[key] then
					used[key] = true
					table.insert(out, { Key = key, Id = id })
					break
				end
			end
		end
	end
	return out
end

function MiningService.RefreshFarmNodes(player: Player)
	local profile = S.Data.Get(player)
	local farm = S.Farm.Get(player)
	if not profile or not farm then
		return
	end
	farmNodes[player] = farmNodes[player] or {}
	local byKey = farmNodes[player]
	for row = 1, World.Farms.Parcels do
		for col = 1, World.Farms.Parcels do
			local typeId = Land.Layout[row][col]
			local ptype = Land.Types[typeId]
			if ptype and ptype.Clear then
				for _, entry in parcelNodeTiles(row, col, ptype.Clear) do
					local key = entry.Key
					local def = Registry.Nodes[entry.Id]
					local blocked = profile.Farm.Cleared[key] or profile.Farm.Tiles[key] or (farm.Occ[key] ~= nil)
					if def and not blocked and not byKey[key] then
						local gx, gz = S.Farm.ParseKey(key)
						local nid = "f" .. player.UserId .. "_" .. key
						byKey[key] = register(nid, def, S.Farm.TileCenter(farm, gx, gz), { Farm = player, Key = key })
					elseif blocked and byKey[key] then
						destroy(byKey[key])
						byKey[key] = nil
					end
				end
			end
		end
	end
end

function MiningService.FarmNodeAt(player: Player, key: string): NodeState?
	local byKey = farmNodes[player]
	local node = byKey and byKey[key]
	if node and node.Active then
		return node
	end
	return nil
end

-- Temporary nodes --------------------------------------------------------------------------------------------------

-- Spawn a node for `lifetime` seconds at (x, z) of `position`, snapped to the ground.
function MiningService.SpawnTemporary(nodeId: string, position: Vector3, lifetime: number): Vector3?
	local def = Registry.Nodes[nodeId]
	if not def then
		return nil
	end
	local ground = S.World.GroundAt(position, 200)
	if not ground then
		return nil
	end
	local nid = "t_" .. RNG.Uid()
	register(nid, def, ground, { Region = S.Player.RegionAt(ground), Expires = os.time() + lifetime })
	return ground
end

-- Hitting ----------------------------------------------------------------------------------------------------------

local function toolFits(def: any, family: string): boolean
	if def.Kind == "Tree" then
		return family == "axe"
	end
	if def.Visual and def.Visual.Shape == "Mound" then
		return family == "pickaxe" or family == "shovel"
	end
	return family == "pickaxe"
end

local function roll(countRange: { number }): number
	return random:NextInteger(countRange[1], countRange[2] or countRange[1])
end

local function dropsFor(player: Player, def: any, share: number): { any }
	local profile = S.Data.Get(player)
	local stacks = {}
	for _, drop in def.Drops do
		if random:NextNumber() < (drop.Chance or 1) * (if share < 1 then 0.6 else 1) then
			local n = math.max(1, math.floor(roll(drop.Count) * share + 0.5))
			table.insert(stacks, ItemUtil.New(drop.Id, n))
		end
	end
	if profile then
		if def.Kind == "Tree" then
			local bonus = Stats.Effect(profile, "WoodBonus")
			if bonus > 0 and random:NextNumber() < bonus then
				table.insert(stacks, ItemUtil.New("wood", random:NextInteger(2, 5)))
			end
			if Stats.Effect(profile, "SapBonus") > 0 and random:NextNumber() < Stats.Effect(profile, "SapBonus") then
				table.insert(stacks, ItemUtil.New("sap", 2))
			end
		else
			-- Extra ore, gems and geodes from Mining perks.
			if random:NextNumber() < Stats.Effect(profile, "OreChance") and #stacks > 0 then
				local first = stacks[1]
				table.insert(stacks, ItemUtil.New(first.Id, 1))
			end
			if random:NextNumber() < Stats.Effect(profile, "GemChance") * 0.25 then
				local gems = Registry.WithTag("Gem")
				if #gems > 0 then
					local gem = gems[random:NextInteger(1, #gems)]
					table.insert(stacks, ItemUtil.New(gem.Id, 1))
				end
			end
			if random:NextNumber() < Stats.Effect(profile, "GeodeChance") * 0.3 and Registry.Items.geode then
				table.insert(stacks, ItemUtil.New("geode", 1))
			end
		end
	end
	return stacks
end

local function reward(player: Player, node: NodeState, share: number)
	local def = node.Def
	local stacks = dropsFor(player, def, share)
	for _, stack in stacks do
		S.Inventory.Add(player, stack, { Source = def.Name, Position = node.Position })
		S.Collection.OnItem(player, stack)
	end
	local skill = if def.Kind == "Tree" then "Foraging" else "Mining"
	S.Skill.AddXP(player, skill, math.max(1, math.floor(def.XP * share)))
	if def.Kind == "Tree" then
		S.Data.AddStat(player, "TreesChopped")
		S.Quest.Progress(player, "Chop", def.Id, 1)
	else
		S.Data.AddStat(player, "RocksMined")
		S.Quest.Progress(player, "Mine", def.Id, 1)
	end
end

local function deplete(player: Player, node: NodeState)
	node.Active = false
	local now = os.clock()
	reward(player, node, 1)
	for other, at in node.Hitters do
		if other ~= player and other.Parent and now - at <= ASSIST_WINDOW then
			reward(other, node, ASSIST_SHARE)
		end
	end
	table.clear(node.Hitters)
	S.Notify.FX(node.Position, "NodeBreak", { Nid = node.Nid, Id = node.Def.Id, Kind = node.Def.Kind }, 250)
	hide(node)
	if node.Farm and node.Key then
		-- Farm clears are permanent.
		local profile = S.Data.Get(node.Farm)
		if profile then
			profile.Farm.Cleared[node.Key] = true
			S.Data.Changed(node.Farm, "Farm", "Cleared")
		end
		if farmNodes[node.Farm] then
			farmNodes[node.Farm][node.Key] = nil
		end
		destroy(node)
		return
	end
	if node.Expires then
		destroy(node)
		return
	end
	task.delay(node.Def.Respawn, function()
		if nodes[node.Nid] == node then
			node.HP = node.Def.HP
			node.Active = true
			show(node)
			S.Notify.FX(node.Position, "NodeRespawn", { Nid = node.Nid }, 250)
		end
	end)
end

function MiningService.Hit(player: Player, nid: string, family: string): (boolean, string?)
	local node = nodes[nid]
	if not node or not node.Active then
		return false, "Nothing there"
	end
	local def = node.Def
	if not toolFits(def, family) then
		return false, if def.Kind == "Tree" then "Use an axe on trees" else "Use a pickaxe on rocks"
	end
	local size = (def.Visual and def.Visual.Size or 1) * 4
	if not S.Security.InReach(player, node.Position, Gathering.Reach + size) then
		return false, "Too far away"
	end
	if node.Farm then
		if not S.Farm.CanAct(player, node.Farm, "Trusted") then
			return false, "That's on someone else's farm"
		end
	elseif node.Region then
		local ok, why = S.Player.CanAccess(player, node.Region)
		if not ok then
			return false, why
		end
	end
	local tier = S.Tool.Tier(player, family)
	if tier < def.Tier then
		local names = { "Copper", "Iron", "Gold", "Crystal", "Starsteel" }
		return false, "You need a " .. (names[def.Tier - 1] or "better") .. " " .. family .. " or better"
	end
	local tierDef = S.Tool.TierDef(player, family)
	local profile = S.Data.Get(player)
	local energy = Gathering.HitEnergy * (tierDef.Energy or 1)
	if def.Kind ~= "Tree" and profile then
		energy *= math.max(0.2, 1 - Stats.Effect(profile, "MiningEnergy"))
	end
	if not S.Player.SpendEnergy(player, energy) then
		return false, "Too tired"
	end
	local damage = (tierDef.Power or 1)
	if profile and def.Kind ~= "Tree" then
		damage *= 1 + Stats.Effect(profile, "MineDamage")
	end
	-- Crits for flavour and pace.
	local crit = random:NextNumber() < 0.08
	if crit then
		damage *= 2
	end
	node.HP = math.max(0, node.HP - damage)
	node.Hitters[player] = os.clock()
	local character = player.Character
	if character then
		character:SetAttribute("Act", (if def.Kind == "Tree" then "Chop" else "Mine") .. "@" .. string.format("%.2f", os.clock()))
	end
	if node.Model then
		node.Model:SetAttribute("HP", node.HP)
	end
	S.Notify.FX(node.Position, "NodeHit", { Nid = nid, HP = node.HP, Max = def.HP, Crit = crit, Kind = def.Kind, By = player.UserId }, 150)
	if node.HP <= 0 then
		deplete(player, node)
	end
	return true
end

-- Lifecycle ----------------------------------------------------------------------------------------------------------

function MiningService.Init()
	root = Instance.new("Folder")
	root.Name = "ResourceNodes"
	root.Parent = workspace
	Net.Handle("NodeHit", function(player, nid)
		local held = player.Character and player.Character:GetAttribute("Held")
		local def = type(held) == "string" and Registry.Items[held]
		if not def or not def.Tool then
			return false, "Hold an axe or pickaxe"
		end
		return MiningService.Hit(player, nid, def.Tool)
	end)
end

function MiningService.Start()
	task.spawn(spawnRegionNodes)
	S.Farm.Ready:Connect(function(player)
		MiningService.RefreshFarmNodes(player)
	end)
	S.Farm.Released:Connect(function(player)
		local byKey = farmNodes[player]
		if byKey then
			for _, node in byKey do
				destroy(node)
			end
		end
		farmNodes[player] = nil
	end)
	S.Building.Placed:Connect(function(player)
		MiningService.RefreshFarmNodes(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		for _, node in nodes do
			node.Hitters[player] = nil
		end
	end)
	-- Expire temporary nodes.
	task.spawn(function()
		while true do
			task.wait(20)
			local now = os.time()
			for _, node in nodes do
				if node.Expires and now >= node.Expires then
					destroy(node)
				end
			end
		end
	end)
end

return MiningService

-- Placing, moving, restyling and removing everything on a farm: buildings,
-- machines, automation, storage and decorations.
--
-- Placeables are inventory items (Config/Placeables, item Use = "Place"). A
-- placed object is saved in profile.Farm.Placed[uid]:
--   { Id, Px, Pz, Ry, Py?, Sc?, C?, Mt?, Tx?, T, By? }
--   Px/Pz  centre in studs relative to the lot origin (Z grows into the fields)
--   Ry     yaw in degrees; grid objects use multiples of 90
--   Py     lift for free-placed decor (hanging lights, stacking)
--   Sc/C/Mt/Tx  scale, paint colour hex, material name, sign text
--
-- Two placement modes:
--   Grid  functional objects snap to whole tiles and quarter turns.
--   Free  decorations (Registry tag "Decor") can use any position on the
--         GridSnap increments, 15° rotation steps, scale and lift.
--
-- Occupancy has two layers: "Ground" (paths, carpets) and "Object" (everything
-- else). Objects may sit on paths but never overlap other objects, except
-- soil equipment inside interior buildings (sprinklers in a greenhouse).
-- The client shows the same checks live (green/red ghost) using
-- BuildingService.Footprint's shared rules, but the server always decides.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local World = require(Shared.Config.World)
local Placeables = require(Shared.Config.Placeables)
local Net = require(Shared.Lib.Net)
local Signal = require(Shared.Lib.Signal)
local Registry = require(Shared.Lib.Registry)
local ItemUtil = require(Shared.Lib.ItemUtil)
local Stats = require(Shared.Lib.Stats)
local RNG = require(Shared.Lib.RNG)
local Format = require(Shared.Lib.Format)
local Models = require(Shared.Models)

local S = require(script.Parent)

local TILE = World.Farms.TileSize
local GRID = World.Farms.ParcelTiles * World.Farms.Parcels
local YARD = World.Farms.YardDepth
local ROT_STEP = 15
local MAX_LIFT = 12

-- Saved decoration layouts: 3, plus any from the Extra Layout Slots pass.
local function layoutSlots(profile: any): number
	return (Placeables.LayoutSlots or 3) + (tonumber(profile.Unlocks.LayoutSlots) or 0)
end

local BuildingService = {}
BuildingService.Spawned = Signal.new() -- (player, uid, model, def) a model exists in the world
BuildingService.Despawned = Signal.new() -- (player, uid, def)
BuildingService.Placed = Signal.new() -- (player, uid, def) newly placed by the player
BuildingService.Removed = Signal.new() -- (player, uid, def, record) picked up
BuildingService.Moved = Signal.new() -- (player, uid, def)
BuildingService.Styled = Signal.new() -- (player, uid, def) paint/material/scale/text changed

-- Models by player → uid.
local spawned: { [Player]: { [string]: Model } } = {}

-- Geometry ---------------------------------------------------------------------------------------------

local function isDecor(def: any): boolean
	return Registry.HasTag(def.Id, "Decor")
end

local function layerOf(def: any): string
	return if def.Category == "Path" then "Ground" else "Object"
end

local function scaleOf(record: any, def: any): number
	local sc = tonumber(record.Sc) or 1
	if not def.Scale then
		return 1
	end
	return math.clamp(sc, def.Scale[1], def.Scale[2])
end

-- Tile keys covered by a placed object: tiles whose centres fall inside its
-- rotated, scaled rectangle, plus always the tile under its centre.
function BuildingService.Footprint(record: any, def: any): { string }
	local scale = scaleOf(record, def)
	local halfW = def.Size[1] * TILE * scale / 2 - 0.05
	local halfD = def.Size[2] * TILE * scale / 2 - 0.05
	local yaw = math.rad(tonumber(record.Ry) or 0)
	local cos, sin = math.cos(yaw), math.sin(yaw)
	local px, pz = tonumber(record.Px) or 0, tonumber(record.Pz) or 0
	local reach = math.sqrt(halfW * halfW + halfD * halfD)
	local x0, x1 = math.floor((px - reach) / TILE), math.floor((px + reach) / TILE)
	local z0, z1 = math.floor((pz - reach) / TILE), math.floor((pz + reach) / TILE)
	local out = {}
	local seen = {}
	for gx = x0, x1 do
		for gz = z0, z1 do
			local cx, cz = (gx + 0.5) * TILE - px, (gz + 0.5) * TILE - pz
			-- Rotate the tile centre into the object's local frame.
			local lx = cx * cos - cz * sin
			local lz = cx * sin + cz * cos
			if math.abs(lx) <= halfW and math.abs(lz) <= halfD then
				local key = gx .. "_" .. gz
				seen[key] = true
				table.insert(out, key)
			end
		end
	end
	local centre = math.floor(px / TILE) .. "_" .. math.floor(pz / TILE)
	if not seen[centre] then
		table.insert(out, centre)
	end
	return out
end

function BuildingService.CenterTile(record: any, _def: any?): (number, number)
	return math.floor((tonumber(record.Px) or 0) / TILE), math.floor((tonumber(record.Pz) or 0) / TILE)
end

function BuildingService.WorldCFrame(player: Player, record: any): CFrame?
	local farm = S.Farm.Get(player)
	if not farm then
		return nil
	end
	local position = farm.Origin + Vector3.new(record.Px, tonumber(record.Py) or 0, record.Pz)
	return CFrame.new(position) * CFrame.Angles(0, math.rad(tonumber(record.Ry) or 0), 0)
end

function BuildingService.WorldPosition(player: Player, uid: string): Vector3?
	local profile = S.Data.Get(player)
	local record = profile and profile.Farm.Placed[uid]
	if not record then
		return nil
	end
	local cf = BuildingService.WorldCFrame(player, record)
	return cf and cf.Position
end

function BuildingService.Model(player: Player, uid: string): Model?
	return spawned[player] and spawned[player][uid]
end

function BuildingService.Cap(profile: any): number
	local level = Stats.EstateLevel(profile)
	return math.min(Placeables.MaxCap, Placeables.BaseCap + Placeables.CapPerLevel * (level - 1))
end

function BuildingService.Count(profile: any, id: string?): number
	local n = 0
	for _, record in profile.Farm.Placed do
		if not id or record.Id == id then
			n += 1
		end
	end
	return n
end

-- Normalise a client spec into a record, snapping grid objects to tiles.
local function normalise(def: any, spec: any, base: any?): any?
	if type(spec) ~= "table" then
		return nil
	end
	local px, pz = tonumber(spec.X), tonumber(spec.Z)
	local ry = tonumber(spec.R) or 0
	if not px or not pz or px ~= px or pz ~= pz or ry ~= ry then
		return nil
	end
	local record = if base then table.clone(base) else { Id = def.Id }
	local free = isDecor(def) and spec.Free == true
	if free then
		local snap = tonumber(spec.Snap) or Placeables.GridSnap[1]
		if not table.find(Placeables.GridSnap, snap) then
			snap = Placeables.GridSnap[1]
		end
		record.Px = math.round(px / snap) * snap
		record.Pz = math.round(pz / snap) * snap
		record.Ry = (math.round(ry / ROT_STEP) * ROT_STEP) % 360
		local lift = tonumber(spec.Y) or 0
		record.Py = if lift > 0 then math.clamp(math.round(lift * 2) / 2, 0, MAX_LIFT) else nil
		if def.Scale and tonumber(spec.Sc) then
			record.Sc = math.clamp(math.round(tonumber(spec.Sc) :: number * 20) / 20, def.Scale[1], def.Scale[2])
		end
		record.F = true
	else
		local quarter = math.round(ry / 90) % 4
		record.Ry = quarter * 90
		local w, d = def.Size[1], def.Size[2]
		if quarter % 2 == 1 then
			w, d = d, w
		end
		local gx0 = math.round(px / TILE - w / 2)
		local gz0 = math.round(pz / TILE - d / 2)
		record.Px = (gx0 + w / 2) * TILE
		record.Pz = (gz0 + d / 2) * TILE
		record.Py = nil
		record.F = nil
		if def.Scale and tonumber(spec.Sc) then
			-- Grid objects with a scale range may shrink but not overflow their tiles.
			record.Sc = math.clamp(tonumber(spec.Sc) :: number, def.Scale[1], 1)
		end
	end
	return record
end

-- Validation --------------------------------------------------------------------------------------------

-- Returns ok, reason. `ignoreUid` skips the object being moved.
function BuildingService.Validate(owner: Player, def: any, record: any, ignoreUid: string?): (boolean, string?)
	local profile = S.Data.Get(owner)
	local farm = S.Farm.Get(owner)
	if not profile or not farm then
		return false, "Farm not ready"
	end
	local tiles = BuildingService.Footprint(record, def)
	local layer = layerOf(def)
	local interiorKind = def.Function and def.Function.Kind == "Interior"
	local reserved = farm.Lot.Reserved or {}
	for _, key in tiles do
		local gx, gz = S.Farm.ParseKey(key)
		if not S.Farm.InGrid(gx, gz) then
			return false, "That's outside your farm"
		end
		if not S.Farm.OwnsTile(profile, gx, gz) then
			return false, "You don't own that land yet"
		end
		if reserved[key] then
			return false, "Too close to your house"
		end
		local occ = farm.Occ[key]
		if occ and occ.Uid == "pond" then
			return false, "You can't build on the pond"
		end
		if S.Mining.FarmNodeAt(owner, key) then
			return false, "Clear the tree or rock first"
		end
		local tile = profile.Farm.Tiles[key]
		if tile and layer == "Object" and not interiorKind then
			if not def.OnSoil then
				return false, "Clear the tilled soil first"
			end
			if tile.C and not def.Walkable then
				return false, "There's a crop in the way"
			end
		elseif tile and layer == "Ground" then
			return false, "Paths can't go on tilled soil"
		end
	end
	-- Overlap with other placeables (checked against records, not the cache,
	-- so a move can ignore its own footprint).
	local mine = {}
	for _, key in tiles do
		mine[key] = true
	end
	for uid, other in profile.Farm.Placed do
		if uid ~= ignoreUid then
			local otherDef = Registry.Placeables[other.Id]
			if otherDef then
				local otherLayer = layerOf(otherDef)
				local otherInterior = otherDef.Function and otherDef.Function.Kind == "Interior"
				local conflict = false
				if otherLayer == layer then
					conflict = true
					if layer == "Object" then
						-- Soil gear may go inside interiors; interiors may cover soil gear.
						if otherInterior and def.OnSoil and not interiorKind then
							conflict = false
						elseif interiorKind and otherDef.OnSoil and not otherInterior then
							conflict = false
						end
					end
				end
				if conflict then
					for _, key in BuildingService.Footprint(other, otherDef) do
						if mine[key] then
							return false, "Overlaps your " .. otherDef.Name
						end
					end
				end
			end
		end
	end
	-- Interiors can't be dropped on top of existing objects' tiles when they aren't soil gear (handled above).
	return true
end

local function canBuild(actor: Player, owner: Player, def: any, action: string): (boolean, string?)
	if actor == owner then
		return true
	end
	local level = S.Permission.LevelFor(owner, actor)
	if level == "Trusted" then
		return true
	end
	if level == "Build" and isDecor(def) and action ~= "Remove" then
		return true
	end
	return false, if level == "Build" then "Only the owner can do that here" else "You don't have build permission here"
end

-- The farm the actor is standing on (their own or one they're visiting).
local function ownerAt(actor: Player): Player?
	local root = S.Security.RootPosition(actor)
	if root then
		local farm = S.Farm.FarmAt(root)
		if farm then
			return farm.Owner
		end
		local lotId = S.Farm.LotOfPosition(root)
		local owner = lotId and S.Farm.OwnerOfLot(lotId)
		if owner then
			return owner
		end
	end
	return if S.Farm.Get(actor) then actor else nil
end

-- Models -------------------------------------------------------------------------------------------------

local PROMPTS: { [string]: { string } } = {
	Machine = { "Machine", "Use" },
	Storage = { "Chest", "Open" },
	Silo = { "Silo", "Open" },
	Animal = { "AnimalHome", "Animals" },
	Station = { "Station", "Craft" },
	Water = { "Water", "Refill" },
	Display = { "Display", "Showcase" },
	Stall = { "Stall", "Browse" },
	Sign = { "Sign", "Read" },
	Controller = { "Controller", "Program" },
	Dock = { "Dock", "Shipping" },
	Farmbot = { "Farmbot", "Configure" },
	Harvester = { "Drones", "Status" },
	Logistics = { "Logistics", "Network" },
	Feeder = { "Feeder", "Status" },
	Collector = { "Collector", "Status" },
	Power = { "Power", "Status" },
}

local SEATS = { Bench = 1.6, Chair = 1.6, Swing = 2.2, Hammock = 2.4 }

local function promptHost(model: Model): BasePart
	local best: BasePart? = nil
	local bestVolume = 0
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and d.Name ~= "Base" then
			local v = d.Size.X * d.Size.Y * d.Size.Z
			if v > bestVolume then
				best, bestVolume = d, v
			end
		end
	end
	return best or model.PrimaryPart :: BasePart
end

local function decorate(model: Model, def: any, uid: string, owner: Player, record: any)
	local fn = def.Function
	local prompt = fn and PROMPTS[fn.Kind]
	if prompt then
		local host = promptHost(model)
		local reach = math.max(8, math.max(def.Size[1], def.Size[2]) * TILE * 0.75)
		local p = Models.Kit.Prompt(host, prompt[1], prompt[2], def.Name, reach)
		p:SetAttribute("Target", uid)
		p:SetAttribute("Owner", owner.UserId)
		if fn.Station then
			p:SetAttribute("Station", fn.Station)
		end
		if fn.Water then
			p:SetAttribute("Water", fn.Water)
		end
	end
	local seatHeight = SEATS[def.Model]
	if seatHeight then
		local seat = Instance.new("Seat")
		seat.Name = "Seat"
		seat.Size = Vector3.new(math.max(1.5, def.Size[1] * TILE * 0.6), 0.2, 1.6)
		seat.Transparency = 1
		seat.Anchored = true
		seat.CanCollide = false
		seat.CFrame = CFrame.new(0, seatHeight, 0)
		seat.Parent = model
	end
	if fn and fn.Kind == "Sign" and record.Tx then
		model:SetAttribute("Text", record.Tx)
	end
	model:SetAttribute("Uid", uid)
	model:SetAttribute("Owner", owner.UserId)
	-- Placement and style, so build mode can move, copy and undo precisely.
	model:SetAttribute("Px", record.Px)
	model:SetAttribute("Pz", record.Pz)
	model:SetAttribute("Py", record.Py)
	model:SetAttribute("Ry", record.Ry)
	model:SetAttribute("Free", record.F == true)
	model:SetAttribute("C", record.C)
	model:SetAttribute("Mt", record.Mt)
	model:SetAttribute("Sc", record.Sc)
	model:SetAttribute("Kind", fn and fn.Kind or "Decor")
	if def.Walkable then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and not d:IsA("Seat") then
				d.CanCollide = false
			end
		end
	end
end

local function spawnOne(player: Player, uid: string, record: any): Model?
	local def = Registry.Placeables[record.Id]
	local farm = S.Farm.Get(player)
	if not def or not farm then
		return nil
	end
	local byUid = spawned[player]
	if not byUid then
		byUid = {}
		spawned[player] = byUid
	end
	if byUid[uid] then
		byUid[uid]:Destroy()
	end
	local model = Models.Placeable(def, record)
	model.Name = uid
	decorate(model, def, uid, player, record)
	local cf = BuildingService.WorldCFrame(player, record) :: CFrame
	model:PivotTo(cf)
	model.Parent = farm.Placed
	byUid[uid] = model
	BuildingService.Spawned:Fire(player, uid, model, def)
	return model
end

local function despawn(player: Player, uid: string)
	local byUid = spawned[player]
	local model = byUid and byUid[uid]
	if model then
		local def = Registry.Placeables[model:GetAttribute("Placeable") or ""]
		model:Destroy()
		byUid[uid] = nil
		BuildingService.Despawned:Fire(player, uid, def)
	end
end

function BuildingService.SpawnAll(player: Player)
	local profile = S.Data.Get(player)
	if not profile then
		return
	end
	local changed = false
	local built = 0
	for uid, record in profile.Farm.Placed do
		if not Registry.Placeables[record.Id] then
			-- Content was removed from the game: refund it with coins.
			warn("[Evergrove] Unknown placeable", record.Id, "removed from", player.Name)
			profile.Farm.Placed[uid] = nil
			S.Economy.AddCoins(player, 400, "Removed content refund")
			changed = true
		else
			spawnOne(player, uid, record)
			built += 1
		end
	end
	if built > 0 then
		S.Data.MaxStat(player, "ObjectsOnFarm", built)
	end
	if changed then
		S.Data.Changed(player, "Farm", "Placed")
	end
	BuildingService.RefreshDisplays(player)
end

-- Put showcased items on display pedestals/cases (in uid order).
function BuildingService.RefreshDisplays(player: Player)
	local profile = S.Data.Get(player)
	local byUid = spawned[player]
	if not profile or not byUid then
		return
	end
	local displays = {}
	for uid, record in profile.Farm.Placed do
		local def = Registry.Placeables[record.Id]
		if def and def.Function and def.Function.Kind == "Display" then
			table.insert(displays, { Uid = uid, Slots = def.Function.Slots })
		end
	end
	table.sort(displays, function(a, b)
		return a.Uid < b.Uid
	end)
	local slot = 1
	for _, display in displays do
		local shown = {}
		for _ = 1, display.Slots do
			local stack = profile.Showcase[tostring(slot)]
			if stack then
				table.insert(shown, stack.Id .. ":" .. (stack.Q or 1) .. ":" .. (if stack.M then table.concat(stack.M, "+") else ""))
			end
			slot += 1
		end
		local model = byUid[display.Uid]
		if model then
			model:SetAttribute("Show", if #shown > 0 then table.concat(shown, ",") else nil)
		end
	end
end

-- Tiles near a change get their crops settled, then re-rendered with the new environment.
local function affectRadius(def: any): number
	local r = math.max(def.Size[1], def.Size[2])
	if def.Radius then
		r += def.Radius
	end
	local fn = def.Function
	if fn and fn.Kind == "Sprinkler" then
		r += fn.Range + 2
	end
	return r + 1
end

local function settleAround(player: Player, record: any, def: any)
	local profile = S.Data.Get(player)
	if not profile then
		return {}
	end
	local cx, cz = BuildingService.CenterTile(record)
	local r = affectRadius(def)
	local keys = {}
	for key, tile in profile.Farm.Tiles do
		local gx, gz = S.Farm.ParseKey(key)
		if math.abs(gx - cx) <= r and math.abs(gz - cz) <= r then
			if tile.C then
				S.Crop.Sync(player, key)
			end
			table.insert(keys, key)
		end
	end
	return keys
end

local function rerender(player: Player, keys: { string })
	for _, key in keys do
		S.Farm.RenderTile(player, key)
	end
end

-- Apply an occupancy change: settle growth under the old environment, rebuild, re-render.
local function commit(player: Player, before: { any }, after: { any })
	local keys = {}
	local seen = {}
	for _, pair in before do
		for _, key in settleAround(player, pair[1], pair[2]) do
			if not seen[key] then
				seen[key] = true
				table.insert(keys, key)
			end
		end
	end
	S.Farm.RebuildOccupancy(player)
	for _, pair in after do
		for _, key in settleAround(player, pair[1], pair[2]) do
			if not seen[key] then
				seen[key] = true
				table.insert(keys, key)
			end
		end
	end
	rerender(player, keys)
	S.Data.Changed(player, "Farm", "Placed")
end

-- Actions -------------------------------------------------------------------------------------------------

local function newUid(profile: any): string
	local uid
	repeat
		uid = RNG.Uid()
	until not profile.Farm.Placed[uid]
	return uid
end

-- Place an object for free (starter kit, quest rewards, admin tools). Uses the
-- normal validation; returns the uid or nil, reason.
function BuildingService.Grant(player: Player, placeableId: string, spec: any): (string?, string?)
	local profile = S.Data.Get(player)
	local def = Registry.Placeables[placeableId]
	if not profile or not def then
		return nil, "Unknown placeable"
	end
	local record = normalise(def, spec)
	if not record then
		return nil, "Bad placement"
	end
	local valid, why = BuildingService.Validate(player, def, record)
	if not valid then
		return nil, why
	end
	local uid = newUid(profile)
	record.T = os.time()
	profile.Farm.Placed[uid] = record
	spawnOne(player, uid, record)
	commit(player, {}, { { record, def } })
	BuildingService.Placed:Fire(player, uid, def)
	return uid, nil
end

-- Place an object from the actor's inventory on the farm they're standing on.
function BuildingService.Place(actor: Player, ref: string, spec: any): (boolean, any)
	local actorProfile = S.Data.Get(actor)
	if not actorProfile then
		return false, "Not ready"
	end
	local stack, container = S.Inventory.Slot(actor, ref)
	local itemId = if stack then stack.Id else ref
	local def = Registry.Placeables[itemId]
	if not def then
		return false, "That can't be placed"
	end
	if not stack then
		-- A bare id: use the first matching stack from the bag or home storage.
		if S.Inventory.Count(actor, itemId) < 1 then
			return false, "You don't have a " .. def.Name
		end
	end
	local owner = ownerAt(actor)
	if not owner then
		return false, "Stand on a farm to build"
	end
	local ok, reason = canBuild(actor, owner, def, "Place")
	if not ok then
		return false, reason
	end
	local profile = S.Data.Get(owner)
	if not profile then
		return false, "Not ready"
	end
	if Stats.EstateLevel(profile) < (def.Level or 1) then
		return false, "Requires Estate level " .. def.Level
	end
	if def.Limit and BuildingService.Count(profile, def.Id) >= def.Limit then
		return false, "You can only have " .. Format.Plural(def.Limit, def.Name)
	end
	if BuildingService.Count(profile) >= BuildingService.Cap(profile) then
		return false, "Your farm is full (" .. BuildingService.Cap(profile) .. " objects). Raise your Estate level for more."
	end
	local record = normalise(def, spec)
	if not record then
		return false, "Bad placement"
	end
	local valid, why = BuildingService.Validate(owner, def, record)
	if not valid then
		return false, why
	end
	-- Consume the item (from the exact slot if given).
	local taken
	if stack and container then
		taken = S.Inventory.TakeFromSlot(actor, ref, 1)
	else
		local removed = S.Inventory.Remove(actor, itemId, 1)
		taken = removed and removed[1]
	end
	if not taken then
		return false, "You don't have a " .. def.Name
	end
	local uid = newUid(profile)
	record.T = os.time()
	if actor ~= owner then
		record.By = actor.UserId
	end
	if def.Paint and type(spec.C) == "string" and Models.ColorOf(spec.C) then
		record.C = string.upper(spec.C)
	end
	if def.Materials and type(spec.Mt) == "string" and table.find(def.Materials, spec.Mt) then
		record.Mt = spec.Mt
	end
	profile.Farm.Placed[uid] = record
	spawnOne(owner, uid, record)
	commit(owner, {}, { { record, def } })
	BuildingService.Placed:Fire(owner, uid, def)
	S.Data.AddStat(owner, "ObjectsPlaced")
	if isDecor(def) then
		S.Data.AddStat(owner, "DecorPlaced")
	end
	S.Quest.Progress(owner, "Place", def.Id, 1)
	S.Tutorial.Event(owner, "Place")
	local position = BuildingService.WorldPosition(owner, uid)
	if position then
		S.Notify.FX(position, "Build", { Id = def.Id }, 200)
	end
	if def.Function and def.Function.Kind == "Display" then
		BuildingService.RefreshDisplays(owner)
	end
	return true, uid
end

local function findOwnerOf(actor: Player, uid: string): (Player?, any?)
	local owner = ownerAt(actor)
	local profile = owner and S.Data.Get(owner)
	if owner and profile and profile.Farm.Placed[uid] then
		return owner, profile.Farm.Placed[uid]
	end
	return nil, nil
end

function BuildingService.Move(actor: Player, uid: string, spec: any): (boolean, string?)
	local owner, record = findOwnerOf(actor, uid)
	if not owner or not record then
		return false, "Nothing there"
	end
	local def = Registry.Placeables[record.Id]
	local ok, reason = canBuild(actor, owner, def, "Move")
	if not ok then
		return false, reason
	end
	-- Animal homes with residents and machines mid-job still move fine: their state lives in data.
	local moved = normalise(def, spec, record)
	if not moved then
		return false, "Bad placement"
	end
	local valid, why = BuildingService.Validate(owner, def, moved, uid)
	if not valid then
		return false, why
	end
	local profile = S.Data.Get(owner)
	local before = table.clone(record)
	profile.Farm.Placed[uid] = moved
	spawnOne(owner, uid, moved)
	commit(owner, { { before, def } }, { { moved, def } })
	BuildingService.Moved:Fire(owner, uid, def)
	return true
end

-- Can this object be picked up right now?
local function removable(owner: Player, uid: string, def: any): (boolean, string?)
	local profile = S.Data.Get(owner)
	local fn = def.Function
	if not fn then
		return true
	end
	if fn.Kind == "Storage" then
		local store = profile.Storage[uid]
		if store and next(store.Slots) then
			return false, "Empty the " .. def.Name .. " first"
		end
	elseif fn.Kind == "Animal" then
		for _, animal in profile.Farm.Animals do
			if animal.Home == uid then
				return false, "Move or sell the animals living here first"
			end
		end
	elseif fn.Kind == "Silo" then
		local capacityAfter = S.Inventory.SiloCapacity(owner) - fn.Capacity
		if S.Inventory.SiloCount(owner) > capacityAfter then
			return false, "Your other silos can't hold everything. Withdraw some items first."
		end
	elseif fn.Kind == "Interior" then
		-- Crops inside keep growing outdoors; warn only through the client.
		return true
	end
	return true
end

function BuildingService.Remove(actor: Player, uid: string): (boolean, string?)
	local owner, record = findOwnerOf(actor, uid)
	if not owner or not record then
		return false, "Nothing there"
	end
	local def = Registry.Placeables[record.Id]
	local ok, reason = canBuild(actor, owner, def, "Remove")
	if not ok then
		return false, reason
	end
	local can, why = removable(owner, uid, def)
	if not can then
		return false, why
	end
	local profile = S.Data.Get(owner)
	local position = BuildingService.WorldPosition(owner, uid)
	-- Machines hand back their queue before disappearing.
	if def.Function and def.Function.Kind == "Machine" then
		S.Machine.Release(owner, uid)
	end
	profile.Farm.Placed[uid] = nil
	profile.Storage[uid] = nil
	despawn(owner, uid)
	commit(owner, { { record, def } }, {})
	BuildingService.Removed:Fire(owner, uid, def, record)
	-- The item always returns to the owner (mail if their bag is full).
	S.Inventory.Add(owner, ItemUtil.New(def.Id, 1), { Source = "Picked up", Silent = actor ~= owner })
	if actor ~= owner then
		S.Notify.Toast(owner, actor.DisplayName .. " picked up your " .. def.Name .. " (returned to your bag).", "Info")
	end
	if position then
		S.Notify.FX(position, "Unbuild", { Id = def.Id }, 200)
	end
	if def.Function and def.Function.Kind == "Display" then
		BuildingService.RefreshDisplays(owner)
	end
	return true
end

function BuildingService.Style(actor: Player, uid: string, style: any): (boolean, string?)
	local owner, record = findOwnerOf(actor, uid)
	if not owner or not record or type(style) ~= "table" then
		return false, "Nothing there"
	end
	local def = Registry.Placeables[record.Id]
	local ok, reason = canBuild(actor, owner, def, "Style")
	if not ok then
		return false, reason
	end
	local changedFootprint = false
	if style.C ~= nil then
		if not def.Paint then
			return false, "That can't be painted"
		end
		if style.C == false or style.C == "" then
			record.C = nil
		elseif type(style.C) == "string" and Models.ColorOf(style.C) then
			record.C = string.upper(style.C)
		else
			return false, "Bad colour"
		end
	end
	if style.Mt ~= nil then
		if style.Mt == false or style.Mt == "" then
			record.Mt = nil
		elseif def.Materials and type(style.Mt) == "string" and table.find(def.Materials, style.Mt) then
			record.Mt = style.Mt
		else
			return false, "That material isn't available"
		end
	end
	if style.Sc ~= nil then
		if not def.Scale then
			return false, "That can't be resized"
		end
		local sc = tonumber(style.Sc)
		if not sc or sc ~= sc then
			return false, "Bad size"
		end
		local maxScale = if record.F then def.Scale[2] else 1
		local newScale = math.clamp(math.round(sc * 20) / 20, def.Scale[1], maxScale)
		local trial = table.clone(record)
		trial.Sc = newScale
		local valid, why = BuildingService.Validate(owner, def, trial, uid)
		if not valid then
			return false, why
		end
		record.Sc = newScale
		changedFootprint = true
	end
	if style.Tx ~= nil then
		if not (def.Function and def.Function.Kind == "Sign") then
			return false, "Only signs have text"
		end
		local text = Format.CleanName(tostring(style.Tx), 60)
		if text == "" then
			record.Tx = nil
		else
			local filtered = S.Multiplayer.FilterText(actor, text)
			if not filtered then
				return false, "That text isn't allowed"
			end
			record.Tx = filtered
		end
	end
	spawnOne(owner, uid, record)
	if changedFootprint then
		commit(owner, { { record, def } }, { { record, def } })
	else
		S.Data.Changed(owner, "Farm", "Placed")
	end
	BuildingService.Styled:Fire(owner, uid, def)
	return true
end

-- Layouts ----------------------------------------------------------------------------------------------
-- A layout is a snapshot of your decorations. Loading one picks up every
-- current decoration and re-places the saved arrangement using the items you
-- own; anything missing is listed so you can buy it.

local function layoutSave(player: Player, slot: number, name: string)
	local profile = S.Data.Get(player)
	if not profile or slot < 1 or slot > layoutSlots(profile) then
		return false, "Bad slot"
	end
	local items = {}
	for _, record in profile.Farm.Placed do
		local def = Registry.Placeables[record.Id]
		if def and isDecor(def) then
			table.insert(items, { Id = record.Id, Px = record.Px, Pz = record.Pz, Ry = record.Ry, Py = record.Py, Sc = record.Sc, C = record.C, Mt = record.Mt, F = record.F })
		end
	end
	local clean = Format.CleanName(name, 24)
	if clean == "" then
		clean = "Layout " .. slot
	end
	local filtered = S.Multiplayer.FilterText(player, clean) or ("Layout " .. slot)
	profile.Farm.Layouts[tostring(slot)] = { Name = filtered, Items = items, Saved = os.time() }
	S.Data.Changed(player, "Farm", "Layouts")
	return true, #items
end

local function layoutList(player: Player)
	local profile = S.Data.Get(player)
	if not profile then
		return false, "Not ready"
	end
	local out = {}
	for i = 1, layoutSlots(profile) do
		local layout = profile.Farm.Layouts[tostring(i)]
		out[i] = if layout then { Name = layout.Name, Count = #layout.Items, Saved = layout.Saved } else false
	end
	return true, out
end

local function layoutLoad(player: Player, slot: number)
	local profile = S.Data.Get(player)
	local farm = S.Farm.Get(player)
	local layout = profile and profile.Farm.Layouts[tostring(slot)]
	if not profile or not farm or not layout then
		return false, "Nothing saved there"
	end
	local root = S.Security.RootPosition(player)
	if not root or S.Farm.FarmAt(root) ~= farm then
		return false, "Go home to load a layout"
	end
	-- 1. Pick up current decorations (into a virtual pool, not the bag, so full bags don't matter).
	local pool: { [string]: number } = {}
	local before = {}
	for uid, record in profile.Farm.Placed do
		local def = Registry.Placeables[record.Id]
		if def and isDecor(def) then
			pool[record.Id] = (pool[record.Id] or 0) + 1
			table.insert(before, { record, def })
			profile.Farm.Placed[uid] = nil
			despawn(player, uid)
		end
	end
	-- 2. Place the saved arrangement from the pool, then from the bag.
	local placedCount, missing = 0, {}
	local after = {}
	for _, saved in layout.Items do
		local def = Registry.Placeables[saved.Id]
		if def then
			local record = { Id = saved.Id, Px = saved.Px, Pz = saved.Pz, Ry = saved.Ry, Py = saved.Py, Sc = saved.Sc, C = saved.C, Mt = saved.Mt, F = saved.F, T = os.time() }
			local fromPool = (pool[saved.Id] or 0) > 0
			local available = fromPool or S.Inventory.Count(player, saved.Id) > 0
			local capOk = BuildingService.Count(profile) < BuildingService.Cap(profile)
			if available and capOk and BuildingService.Validate(player, def, record) then
				if fromPool then
					pool[saved.Id] -= 1
				else
					S.Inventory.Remove(player, saved.Id, 1)
				end
				local uid = newUid(profile)
				profile.Farm.Placed[uid] = record
				spawnOne(player, uid, record)
				table.insert(after, { record, def })
				placedCount += 1
			else
				missing[saved.Id] = (missing[saved.Id] or 0) + 1
			end
		end
	end
	-- 3. Leftover picked-up decorations go back to the bag (or mail).
	for id, n in pool do
		if n > 0 then
			S.Inventory.Add(player, ItemUtil.New(id, n), { Source = "Layout", Silent = true })
		end
	end
	commit(player, before, after)
	local missingList = {}
	for id, n in missing do
		table.insert(missingList, { Id = id, N = n })
	end
	return true, { Placed = placedCount, Missing = missingList }
end

-- Lifecycle ----------------------------------------------------------------------------------------------

function BuildingService.Init()
	Net.Handle("BuildPlace", function(player, ref, spec)
		return BuildingService.Place(player, ref, spec)
	end)
	Net.Handle("BuildMove", function(player, uid, spec)
		return BuildingService.Move(player, uid, spec)
	end)
	Net.Handle("BuildRemove", function(player, uid)
		return BuildingService.Remove(player, uid)
	end)
	Net.Handle("BuildStyle", function(player, uid, style)
		return BuildingService.Style(player, uid, style)
	end)
	Net.Handle("LayoutSave", layoutSave)
	Net.Handle("LayoutLoad", layoutLoad)
	Net.Handle("LayoutList", layoutList)
end

function BuildingService.Start()
	S.Farm.Released:Connect(function(player)
		local byUid = spawned[player]
		if byUid then
			for uid in byUid do
				despawn(player, uid)
			end
		end
		spawned[player] = nil
	end)
end

-- Constants shared with the client's build mode.
BuildingService.TILE = TILE
BuildingService.GRID = GRID
BuildingService.YARD = YARD

return BuildingService

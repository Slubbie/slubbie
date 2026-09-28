-- The world: terrain, roads, the village, every region, signposts, lifts and
-- lighting. Built once at server start (WorldService.Init runs before the
-- gameplay services that place things in it).
--
-- Queries used by other services:
--   Waypoint(name)                → Vector3?  named places, building doors, NPC homes
--   Path(from, to)                → { Vector3 } along the road graph (A*)
--   GroundAt(position, span?)     → Vector3?  terrain surface under/over a point
--   SpawnPoint(regionId, seed, clearance) → Vector3?  a free spot on the ground
--   LiftNear(position, liftId)    → lift def if standing at that lift

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local World = require(Shared.Config.World)
local Regions = require(Shared.Config.Regions)
local Registry = require(Shared.Lib.Registry)

local TerrainKit = require(script.Parent.Parent.World.TerrainKit)
local VillageBuilder = require(script.Parent.Parent.World.VillageBuilder)
local RegionBuilder = require(script.Parent.Parent.World.RegionBuilder)

local WorldService = {}

local ROAD_WIDTH = 12
local BOUNDS = { MinX = -1700, MaxX = 1800, MinZ = -1350, MaxZ = 1550 }
local LOT_MARGIN = 12
local BUILDING_MARGIN = 10

local root: Folder
local waypoints: { [string]: Vector3 } = {}
local lifts: { any } = {}
local exclusions: { { Center: Vector3, Radius: number } } = {}
local rects: { { MinX: number, MaxX: number, MinZ: number, MaxZ: number } } = {}
local rayTop: { [string]: number } = {}
local roadSegments: { { Vector3 } } = {}

-- Road graph -------------------------------------------------------------------------------------------------

type Node = { P: Vector3, Links: { number } }
local nodes: { Node } = {}

local function nodeIndex(p: Vector3): number
	for i, node in nodes do
		if (node.P - p).Magnitude < 2 then
			return i
		end
	end
	table.insert(nodes, { P = p, Links = {} })
	return #nodes
end

local function link(a: number, b: number)
	if a ~= b and not table.find(nodes[a].Links, b) then
		table.insert(nodes[a].Links, b)
		table.insert(nodes[b].Links, a)
	end
end

local function closestOnSegment(p: Vector3, a: Vector3, b: Vector3): (Vector3, number)
	local ab = b - a
	local lengthSq = ab:Dot(ab)
	local t = if lengthSq > 0 then math.clamp((p - a):Dot(ab) / lengthSq, 0, 1) else 0
	local q = a + ab * t
	return q, (p - q).Magnitude
end

local function buildGraph()
	-- Split every polyline at vertices of other polylines that touch it (junctions).
	local lines = {}
	for _, line in World.Roads do
		table.insert(lines, table.clone(line))
	end
	local vertices = {}
	for _, line in lines do
		for _, p in line do
			table.insert(vertices, p)
		end
	end
	for _, line in lines do
		local i = 1
		while i < #line do
			local a, b = line[i], line[i + 1]
			local inserted = false
			for _, v in vertices do
				local q, d = closestOnSegment(v, a, b)
				if d < 2 and (q - a).Magnitude > 2 and (q - b).Magnitude > 2 then
					table.insert(line, i + 1, q)
					inserted = true
					break
				end
			end
			if not inserted then
				i += 1
			end
		end
	end
	for _, line in lines do
		for i = 1, #line - 1 do
			link(nodeIndex(line[i]), nodeIndex(line[i + 1]))
			table.insert(roadSegments, { line[i], line[i + 1] })
		end
	end
end

local function nearestNode(p: Vector3): number?
	local best, bestD = nil, math.huge
	for i, node in nodes do
		local d = (Vector3.new(node.P.X, 0, node.P.Z) - Vector3.new(p.X, 0, p.Z)).Magnitude
		if d < bestD then
			best, bestD = i, d
		end
	end
	return best
end

function WorldService.Path(from: Vector3, to: Vector3): { Vector3 }
	local start, goal = nearestNode(from), nearestNode(to)
	if not start or not goal then
		return { to }
	end
	-- Walking directly is shorter than detouring via the roads.
	local direct = (to - from).Magnitude
	if direct < (nodes[start].P - from).Magnitude + (nodes[goal].P - to).Magnitude then
		return { to }
	end
	-- A* over the road graph.
	local open = { [start] = true }
	local came: { [number]: number } = {}
	local g = { [start] = 0 }
	local f = { [start] = (nodes[start].P - nodes[goal].P).Magnitude }
	while next(open) do
		local current, best = nil, math.huge
		for i in open do
			if f[i] < best then
				current, best = i, f[i]
			end
		end
		if current == goal then
			break
		end
		open[current :: number] = nil
		for _, n in nodes[current :: number].Links do
			local tentative = g[current :: number] + (nodes[current :: number].P - nodes[n].P).Magnitude
			if tentative < (g[n] or math.huge) then
				came[n] = current :: number
				g[n] = tentative
				f[n] = tentative + (nodes[n].P - nodes[goal].P).Magnitude
				open[n] = true
			end
		end
	end
	local route = {}
	local at: number? = goal
	while at do
		table.insert(route, 1, nodes[at].P)
		at = came[at]
	end
	if route[1] ~= nodes[start].P then
		return { to }
	end
	table.insert(route, to)
	return route
end

-- Queries ---------------------------------------------------------------------------------------------------------

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { workspace.Terrain }
rayParams.IgnoreWater = false

function WorldService.GroundAt(position: Vector3, span: number?): Vector3?
	local height = span or 400
	local result = workspace:Raycast(position + Vector3.new(0, height, 0), Vector3.new(0, -height * 2, 0), rayParams)
	if result and result.Material ~= Enum.Material.Water then
		return result.Position
	end
	return nil
end

function WorldService.Waypoint(name: string): Vector3?
	return waypoints[name]
end

function WorldService.LiftNear(position: Vector3?, liftId: string): any?
	if not position then
		return nil
	end
	for _, lift in lifts do
		if lift.Id == liftId and (lift.From - position).Magnitude <= 16 then
			return lift
		end
	end
	return nil
end

local function blocked(p: Vector3, clearance: number): boolean
	for _, r in rects do
		if p.X >= r.MinX - clearance and p.X <= r.MaxX + clearance and p.Z >= r.MinZ - clearance and p.Z <= r.MaxZ + clearance then
			return true
		end
	end
	for _, e in exclusions do
		if (Vector3.new(p.X, e.Center.Y, p.Z) - e.Center).Magnitude < e.Radius + clearance and math.abs(p.Y - e.Center.Y) < 60 then
			return true
		end
	end
	if math.abs(p.Y) < 60 then
		for _, seg in roadSegments do
			local _, d = closestOnSegment(Vector3.new(p.X, 0, p.Z), seg[1], seg[2])
			if d < ROAD_WIDTH / 2 + clearance then
				return true
			end
		end
	end
	return false
end

-- A free ground spot inside a region (deterministic for a given seed).
function WorldService.SpawnPoint(regionId: string, seed: number, clearance: number?): Vector3?
	local region = Registry.Regions[regionId]
	if not region then
		return nil
	end
	local rng = Random.new(seed)
	local top = rayTop[regionId] or (region.Center.Y + 300)
	local c = clearance or 4
	for _ = 1, 24 do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = math.sqrt(rng:NextNumber()) * region.Radius * 0.9
		local x = region.Center.X + math.cos(a) * d
		local z = region.Center.Z + math.sin(a) * d
		local probe = Vector3.new(x, top, z)
		if not blocked(Vector3.new(x, region.Center.Y, z), c) then
			local hit = workspace:Raycast(probe, Vector3.new(0, -(top - region.Center.Y) - 200, 0), rayParams)
			if hit and hit.Material ~= Enum.Material.Water and hit.Normal.Y > 0.7 then
				-- The spot must still be in this region (not a neighbour's hill or cave).
				if math.abs(hit.Position.Y - region.Center.Y) <= (region.Height or 400) then
					return hit.Position
				end
			end
		end
	end
	return nil
end

-- Building -------------------------------------------------------------------------------------------------------

local function setupLighting()
	Lighting.Technology = Enum.Technology.Future
	Lighting.Brightness = 2.2
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.GlobalShadows = true
	Lighting.OutdoorAmbient = Color3.fromRGB(120, 120, 130)
	Lighting.ClockTime = 9
	local function ensure(className: string, name: string): Instance
		local existing = Lighting:FindFirstChild(name)
		if existing then
			return existing
		end
		local inst = Instance.new(className)
		inst.Name = name
		inst.Parent = Lighting
		return inst
	end
	local atmosphere = ensure("Atmosphere", "Atmosphere") :: Atmosphere
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(199, 215, 230)
	atmosphere.Decay = Color3.fromRGB(106, 120, 140)
	atmosphere.Glare = 0.1
	atmosphere.Haze = 1.2
	local bloom = ensure("BloomEffect", "Bloom") :: BloomEffect
	bloom.Intensity = 0.6
	bloom.Size = 26
	bloom.Threshold = 1.6
	local sun = ensure("SunRaysEffect", "SunRays") :: SunRaysEffect
	sun.Intensity = 0.04
	sun.Spread = 0.6
	local grade = ensure("ColorCorrectionEffect", "Grade") :: ColorCorrectionEffect
	grade.Saturation = 0.12
	grade.Contrast = 0.05
	grade.TintColor = Color3.fromRGB(255, 250, 240)
	ensure("Sky", "Sky")
	local terrain = workspace.Terrain
	if not terrain:FindFirstChildOfClass("Clouds") then
		local clouds = Instance.new("Clouds")
		clouds.Cover = 0.55
		clouds.Density = 0.6
		clouds.Parent = terrain
	end
	terrain.WaterColor = Color3.fromRGB(60, 140, 170)
	terrain.WaterTransparency = 0.5
	terrain.WaterWaveSize = 0.12
	terrain.WaterWaveSpeed = 8
	terrain.WaterReflectance = 0.6
	pcall(function()
		terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(110, 170, 80))
		terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(90, 145, 70))
		terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(125, 100, 75))
		terrain:SetMaterialColor(Enum.Material.Mud, Color3.fromRGB(95, 80, 60))
		terrain:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(230, 210, 160))
		terrain:SetMaterialColor(Enum.Material.Cobblestone, Color3.fromRGB(165, 160, 150))
		terrain:SetMaterialColor(Enum.Material.Snow, Color3.fromRGB(240, 245, 255))
	end)
end

local function buildBase()
	local cx = (BOUNDS.MinX + BOUNDS.MaxX) / 2
	local cz = (BOUNDS.MinZ + BOUNDS.MaxZ) / 2
	TerrainKit.Slab(Vector3.new(cx, 0, cz), BOUNDS.MaxX - BOUNDS.MinX, BOUNDS.MaxZ - BOUNDS.MinZ, 12, Enum.Material.Grass, 0)
	-- Invisible walls at the edge of the world.
	local walls = Instance.new("Folder")
	walls.Name = "Bounds"
	walls.Parent = root
	local function wall(center: Vector3, size: Vector3)
		local part = Instance.new("Part")
		part.Anchored = true
		part.Transparency = 1
		part.CanQuery = false
		part.Size = size
		part.Position = center
		part.Parent = walls
	end
	local w, d = BOUNDS.MaxX - BOUNDS.MinX, BOUNDS.MaxZ - BOUNDS.MinZ
	wall(Vector3.new(cx, 400, BOUNDS.MinZ), Vector3.new(w, 1400, 4))
	wall(Vector3.new(cx, 400, BOUNDS.MaxZ), Vector3.new(w, 1400, 4))
	wall(Vector3.new(BOUNDS.MinX, 400, cz), Vector3.new(4, 1400, d))
	wall(Vector3.new(BOUNDS.MaxX, 400, cz), Vector3.new(4, 1400, d))
end

local function buildRoads()
	for _, line in World.Roads do
		for i = 1, #line - 1 do
			TerrainKit.PaintStrip(line[i], line[i + 1], ROAD_WIDTH, Enum.Material.Ground)
		end
		for _, p in line do
			TerrainKit.PaintDisc(p, ROAD_WIDTH / 2 + 1, Enum.Material.Ground)
		end
	end
	-- Village roads are cobbled.
	for _, line in { World.Roads[1], World.Roads[2], World.Roads[3] } do
		for i = 1, #line - 1 do
			local a, b = line[i], line[i + 1]
			if a.Magnitude < 230 and b.Magnitude < 230 then
				TerrainKit.PaintStrip(a, b, ROAD_WIDTH - 2, Enum.Material.Cobblestone)
			end
		end
	end
end

local function buildSignposts()
	local folder = Instance.new("Folder")
	folder.Name = "Signposts"
	folder.Parent = root
	for _, travel in World.Travel do
		local ground = WorldService.GroundAt(travel.Position, 60) or travel.Position
		VillageBuilder.Signpost(folder, travel, ground + Vector3.new(6, 0, 6))
		waypoints["Travel_" .. travel.Id] = ground
	end
end

local function registerExclusions(villageInfo: any)
	-- Farm lots (fields + yard) are never used for world spawns.
	for _, lot in World.Farms.Lots do
		local size = World.Farms.ParcelTiles * World.Farms.Parcels * World.Farms.TileSize
		table.insert(rects, {
			MinX = lot.Origin.X - LOT_MARGIN,
			MaxX = lot.Origin.X + size + LOT_MARGIN,
			MinZ = lot.Origin.Z - World.Farms.YardDepth - LOT_MARGIN,
			MaxZ = lot.Origin.Z + size + LOT_MARGIN,
		})
	end
	for _, b in World.Buildings do
		local r = math.max(b.Size.X, b.Size.Z) / 2 + BUILDING_MARGIN
		table.insert(exclusions, { Center = b.Position, Radius = r })
	end
	for _, home in villageInfo.Homes do
		table.insert(exclusions, { Center = home, Radius = 14 })
	end
	table.insert(exclusions, { Center = Vector3.new(0, 0, 18), Radius = 40 }) -- plaza
	table.insert(exclusions, { Center = Vector3.new(0, 0, 62), Radius = 18 }) -- stage
	for _, region in Regions.List do
		for _, water in region.Waters do
			table.insert(exclusions, { Center = water.Center, Radius = water.Radius * 0.35 + 4 })
		end
	end
	for _, travel in World.Travel do
		table.insert(exclusions, { Center = travel.Position, Radius = 10 })
	end
end

function WorldService.Init()
	root = Instance.new("Folder")
	root.Name = "World"
	root.Parent = workspace
	local started = os.clock()
	setupLighting()
	buildBase()
	local regionInfo = RegionBuilder.Build(root)
	lifts = regionInfo.Lifts
	for _, e in regionInfo.Exclusions do
		table.insert(exclusions, e)
	end
	for id, y in regionInfo.RayTop do
		rayTop[id] = y
	end
	buildRoads()
	buildGraph()
	local villageInfo = VillageBuilder.Build(root)
	-- Waypoints: config spots, building doors and homes, all snapped to the ground.
	for name, p in World.Waypoints do
		waypoints[name] = p
	end
	for id, p in villageInfo.Doors do
		waypoints[id] = p
	end
	for npcId, p in villageInfo.Homes do
		waypoints["Home_" .. npcId] = p
	end
	for name, p in waypoints do
		if name ~= "Away" then
			local ground = WorldService.GroundAt(p, 80)
			if ground then
				waypoints[name] = ground + Vector3.new(0, 3, 0)
			end
		end
	end
	registerExclusions(villageInfo)
	-- The river crosses a road: lay a bridge wherever they meet.
	if regionInfo.River then
		local bridges = Instance.new("Folder")
		bridges.Name = "Bridges"
		bridges.Parent = root
		local placed: { Vector3 } = {}
		local function nearPlaced(p: Vector3): boolean
			for _, q in placed do
				if (q - p).Magnitude < 40 then
					return true
				end
			end
			return false
		end
		for _, seg in roadSegments do
			for i = 1, #regionInfo.River - 1 do
				local a, b = regionInfo.River[i], regionInfo.River[i + 1]
				for t = 0, 1, 0.02 do
					local p = seg[1]:Lerp(seg[2], t)
					local _, d = closestOnSegment(p, a, b)
					if d < 20 and not nearPlaced(p) then
						table.insert(placed, p)
						local dir = (seg[2] - seg[1]).Unit
						local bridge = Instance.new("Part")
						bridge.Name = "Bridge"
						bridge.Anchored = true
						bridge.Size = Vector3.new(ROAD_WIDTH, 1, 56)
						bridge.CFrame = CFrame.lookAt(p + Vector3.new(0, 0.4, 0), p + dir + Vector3.new(0, 0.4, 0))
						bridge.Material = Enum.Material.WoodPlanks
						bridge.Color = Color3.fromRGB(160, 115, 75)
						bridge.Parent = bridges
						break
					end
				end
			end
		end
	end
	buildSignposts()
	print(string.format("[Evergrove] World built in %.1fs (%d road nodes, %d lifts)", os.clock() - started, #nodes, #lifts))
end

return WorldService

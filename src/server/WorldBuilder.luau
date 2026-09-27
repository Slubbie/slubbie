-- Generates a test sky archipelago so the movement can be played immediately:
-- floating islands that climb higher the further out you go, glowing grapple
-- anchors in the gaps, wall-run corridors, launch pads and shards to collect.
--
-- Swap this out for a hand-built map once the feel is locked in: put your map in
-- a Workspace folder named "Map" and generation is skipped.
--
-- Build() returns the list of islands ({ Position, Radius }) so time-trial
-- courses can be laid out across them, or nil for a hand-built map.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MathUtil = require(ReplicatedStorage.Shared.MathUtil)

local WORLD = Config.World
local Flat = MathUtil.Flat

local GRASS = {
	Color3.fromRGB(122, 196, 104),
	Color3.fromRGB(143, 206, 110),
	Color3.fromRGB(104, 176, 118),
	Color3.fromRGB(168, 210, 112),
}
local ROCK = {
	Color3.fromRGB(118, 110, 128),
	Color3.fromRGB(96, 92, 112),
	Color3.fromRGB(134, 122, 118),
}
local LEAVES = {
	Color3.fromRGB(84, 170, 96),
	Color3.fromRGB(255, 170, 200),
	Color3.fromRGB(250, 200, 110),
}
local STONE = Color3.fromRGB(226, 214, 190)
local SHARD = Color3.fromRGB(255, 214, 90)
local PAD = Color3.fromRGB(255, 90, 190)

local WorldBuilder = {}

local function part(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

-- A vertical cylinder (Roblox cylinders lie along X, so we rotate them upright).
local function cylinder(parent: Instance, center: Vector3, height: number, radius: number, props: { [string]: any })
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(height, radius * 2, radius * 2)
	props.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2)
	return part(props, parent)
end

local function shard(parent: Instance, position: Vector3)
	local p = part({
		Name = "Shard",
		Size = Vector3.new(1.4, 2.6, 1.4),
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(45)),
		Material = Enum.Material.Neon,
		Color = SHARD,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	}, parent)
	local light = Instance.new("PointLight")
	light.Color = SHARD
	light.Range = 10
	light.Brightness = 1.5
	light.Parent = p
	CollectionService:AddTag(p, "Shard")
end

local function tree(parent: Instance, base: Vector3, rng: Random)
	local height = rng:NextNumber(8, 15)
	cylinder(parent, base + Vector3.new(0, height / 2, 0), height, 0.9, {
		Name = "Trunk",
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(120, 86, 64),
	})
	local size = rng:NextNumber(7, 11)
	part({
		Name = "Leaves",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * size,
		Position = base + Vector3.new(0, height + size * 0.3, 0),
		Color = LEAVES[rng:NextInteger(1, #LEAVES)],
	}, parent)
end

local function island(parent: Instance, center: Vector3, radius: number, rng: Random): Model
	local model = Instance.new("Model")
	model.Name = "Island"

	cylinder(model, center, 4, radius, {
		Name = "Top",
		Material = Enum.Material.Grass,
		Color = GRASS[rng:NextInteger(1, #GRASS)],
	})
	cylinder(model, center - Vector3.new(0, 3.5, 0), 3, radius * 0.97, {
		Name = "Dirt",
		Material = Enum.Material.Ground,
		Color = Color3.fromRGB(128, 96, 70),
	})

	-- Tapering rock layers underneath.
	local y = center.Y - 5
	local r = radius * 0.95
	for _ = 1, rng:NextInteger(3, 5) do
		local h = rng:NextNumber(6, 12)
		r *= rng:NextNumber(0.6, 0.8)
		local wobble = Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2))
		cylinder(model, Vector3.new(center.X, y - h / 2, center.Z) + wobble, h, r, {
			Name = "Rock",
			Material = Enum.Material.Slate,
			Color = ROCK[rng:NextInteger(1, #ROCK)],
		})
		y -= h
	end

	local surface = center.Y + 2
	for _ = 1, math.floor(radius / 22) do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(0, radius * 0.7)
		tree(model, Vector3.new(center.X + math.cos(angle) * dist, surface, center.Z + math.sin(angle) * dist), rng)
	end

	-- Ruined wall near the edge: a wall-run ramp off the island.
	if radius > 30 and rng:NextNumber() < 0.45 then
		local angle = rng:NextNumber(0, math.pi * 2)
		local edge = Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius * 0.8
		local wallPos = Vector3.new(center.X, surface + 11, center.Z) + edge
		part({
			Name = "RuinWall",
			Size = Vector3.new(2.5, 22, 40),
			CFrame = CFrame.lookAt(wallPos, wallPos + edge) * CFrame.Angles(0, math.pi / 2, 0),
			Material = Enum.Material.Limestone,
			Color = STONE,
		}, model)
	end

	for _ = 1, rng:NextInteger(1, 2) do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(0, radius * 0.5)
		shard(model, Vector3.new(center.X + math.cos(angle) * dist, surface + 4, center.Z + math.sin(angle) * dist))
	end

	model.Parent = parent
	return model
end

-- Floating glowing crystal: the obvious "hook me" target between islands.
local function anchor(parent: Instance, position: Vector3, rng: Random)
	local model = Instance.new("Model")
	model.Name = "SkyAnchor"
	part({
		Name = "Rock",
		Size = Vector3.new(9, 5, 9),
		CFrame = CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
		Material = Enum.Material.Slate,
		Color = ROCK[1],
	}, model)
	local crystal = part({
		Name = "Crystal",
		Size = Vector3.new(3, 10, 3),
		CFrame = CFrame.new(position + Vector3.new(0, 6, 0))
			* CFrame.Angles(0, math.rad(45), math.rad(rng:NextNumber(-12, 12))),
		Material = Enum.Material.Neon,
		Color = Config.Grapple.RopeColor,
		CastShadow = false,
	}, model)
	local light = Instance.new("PointLight")
	light.Color = Config.Grapple.RopeColor
	light.Range = 18
	light.Brightness = 2
	light.Parent = crystal
	model.Parent = parent
end

-- Two parallel floating walls: chain wall-runs through the middle.
local function corridor(parent: Instance, from: Vector3, to: Vector3)
	local mid = (from + to) / 2
	local look = CFrame.lookAt(mid, Vector3.new(to.X, mid.Y, to.Z))
	for _, side in { -1, 1 } do
		part({
			Name = "CorridorWall",
			Size = Vector3.new(2.5, 20, 64),
			CFrame = look * CFrame.new(side * 11, 0, 0),
			Material = Enum.Material.Limestone,
			Color = STONE,
		}, parent)
	end
	for i = -2, 2 do
		shard(parent, (look * CFrame.new(0, 2, i * 12)).Position)
	end
end

local function launchPad(parent: Instance, position: Vector3, outward: Vector3)
	local pad = part({
		Name = "LaunchPad",
		Size = Vector3.new(8, 0.6, 8),
		Position = position,
		Material = Enum.Material.Neon,
		Color = PAD,
	}, parent)
	pad:SetAttribute("LaunchVelocity", outward * 85 + Vector3.new(0, 150, 0))
	CollectionService:AddTag(pad, "LaunchPad")
end

local function setupLighting()
	Lighting.ClockTime = 16.6
	Lighting.Brightness = 2.6
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 160, 195)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1

	local function ensure(className: string): any
		local existing = Lighting:FindFirstChildOfClass(className)
		if existing then
			return existing
		end
		local created = Instance.new(className)
		created.Parent = Lighting
		return created
	end
	local atmosphere = ensure("Atmosphere")
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.25
	atmosphere.Color = Color3.fromRGB(199, 220, 255)
	atmosphere.Decay = Color3.fromRGB(120, 120, 180)
	atmosphere.Glare = 0.4
	atmosphere.Haze = 1.4
	local bloom = ensure("BloomEffect")
	bloom.Intensity = 0.7
	bloom.Size = 28
	bloom.Threshold = 1.4
	local sunRays = ensure("SunRaysEffect")
	sunRays.Intensity = 0.08
	sunRays.Spread = 0.8
	local grade = ensure("ColorCorrectionEffect")
	grade.Saturation = 0.12
	grade.Contrast = 0.06
end

function WorldBuilder.Build()
	setupLighting()

	if workspace:FindFirstChild("Map") then
		return nil
	end
	-- The default template baseplate would ruin the sky; hand-built maps go in "Map".
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	local rng = Random.new(WORLD.Seed)
	local map = Instance.new("Folder")
	map.Name = "GeneratedMap"
	map.Parent = workspace

	-- Sea of clouds below. You can fall through it... and you won't come back.
	part({
		Name = "CloudSea",
		Size = Vector3.new(2048, 8, 2048),
		Position = Vector3.new(0, -60, 0),
		Color = Color3.new(1, 1, 1),
		Transparency = 0.25,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	}, map)

	-- Spawn island with launch pads to get new players into the air fast.
	local islands = { { Position = Vector3.new(0, 100, 0), Radius = 60 } }
	island(map, islands[1].Position, islands[1].Radius, rng)
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(0, 102.5, 0)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Color = STONE
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = map
	for i = 0, 3 do
		local angle = i * math.pi / 2 + math.pi / 4
		local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
		launchPad(map, Vector3.new(0, 102.3, 0) + outward * 38, outward)
	end

	-- Scatter islands; they climb higher the further out you go.
	local attempts = 0
	while #islands < WORLD.IslandCount and attempts < 4000 do
		attempts += 1
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = math.sqrt(rng:NextNumber()) * WORLD.WorldRadius
		local radius = rng:NextNumber(18, 50)
		local pos =
			Vector3.new(math.cos(angle) * dist, 90 + dist * 0.18 + rng:NextNumber(-40, 40), math.sin(angle) * dist)
		local fits = true
		for _, other in islands do
			if (Flat(pos) - Flat(other.Position)).Magnitude < radius + other.Radius + 45 then
				fits = false
				break
			end
		end
		if fits then
			table.insert(islands, { Position = pos, Radius = radius })
			island(map, pos, radius, rng)
		end
	end

	-- Link each island to its two nearest neighbours with an anchor or a corridor.
	local linked = {}
	for i, a in islands do
		local neighbours = {}
		for j, b in islands do
			if i ~= j then
				table.insert(neighbours, { Index = j, Dist = (a.Position - b.Position).Magnitude })
			end
		end
		table.sort(neighbours, function(x, y)
			return x.Dist < y.Dist
		end)
		for k = 1, math.min(2, #neighbours) do
			local j = neighbours[k].Index
			local key = math.min(i, j) .. ":" .. math.max(i, j)
			if not linked[key] then
				linked[key] = true
				local b = islands[j]
				local gap = neighbours[k].Dist - a.Radius - b.Radius
				local mid = (a.Position + b.Position) / 2
				if gap > 110 and rng:NextNumber() < 0.35 then
					corridor(map, a.Position, b.Position)
				elseif gap > 35 then
					local height = math.max(a.Position.Y, b.Position.Y) + rng:NextNumber(40, 70)
					anchor(map, Vector3.new(mid.X, height, mid.Z), rng)
					-- Reward the swing arc with shards hanging under the anchor.
					for s = 1, 3 do
						shard(map, Vector3.new(mid.X, height - 25 - s * 6, mid.Z))
					end
				end
			end
		end
	end

	-- Decorative cloud puffs drifting between islands.
	for _ = 1, 40 do
		local pos = Vector3.new(
			rng:NextNumber(-WORLD.WorldRadius, WORLD.WorldRadius),
			rng:NextNumber(20, 320),
			rng:NextNumber(-WORLD.WorldRadius, WORLD.WorldRadius)
		)
		cylinder(map, pos, rng:NextNumber(6, 14), rng:NextNumber(20, 45), {
			Name = "Cloud",
			Color = Color3.new(1, 1, 1),
			Transparency = 0.35,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
		})
	end

	return islands
end

return WorldBuilder

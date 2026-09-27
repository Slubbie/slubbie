-- Generates the sky archipelago: sculpted Terrain islands in four biomes
-- (meadow, blossom, ruins, alpine) that climb higher the further out you go,
-- with trees, flowers, waterfalls, rope bridges, glowing grapple crystals,
-- wall-run corridors, a spawn plaza with a beacon, banks of clouds below and
-- golden-hour lighting.
--
-- Swap this out for a hand-built map once the feel is locked in: put your map in
-- a Workspace folder named "Map" and generation is skipped.
--
-- Build() returns the list of islands ({ Position, Radius }) so time-trial
-- courses can be laid out across them, or nil for a hand-built map.
-- An island's walkable surface is at Position.Y + 2.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MathUtil = require(ReplicatedStorage.Shared.MathUtil)

local WORLD = Config.World
local Flat = MathUtil.Flat
local Terrain = workspace.Terrain
local M = Enum.Material

type Biome = "Meadow" | "Blossom" | "Ruins" | "Alpine" | "Plaza"

local TOP_MATERIAL: { [Biome]: Enum.Material } = {
	Meadow = M.Grass,
	Blossom = M.LeafyGrass,
	Ruins = M.Grass,
	Alpine = M.Snow,
	Plaza = M.Grass,
}
local LEAVES = {
	Meadow = { Color3.fromRGB(88, 168, 84), Color3.fromRGB(110, 186, 90), Color3.fromRGB(70, 150, 90) },
	Blossom = { Color3.fromRGB(255, 176, 208), Color3.fromRGB(255, 205, 225), Color3.fromRGB(248, 150, 190) },
	Autumn = { Color3.fromRGB(250, 170, 70), Color3.fromRGB(240, 120, 60), Color3.fromRGB(255, 205, 100) },
	Pine = { Color3.fromRGB(46, 110, 80), Color3.fromRGB(58, 128, 88), Color3.fromRGB(40, 96, 74) },
}
local FLOWERS = {
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(255, 225, 90),
	Color3.fromRGB(255, 140, 190),
	Color3.fromRGB(180, 140, 255),
	Color3.fromRGB(120, 200, 255),
}
local STONE = Color3.fromRGB(228, 218, 196)
local WOOD = Color3.fromRGB(116, 82, 60)
local SHARD = Color3.fromRGB(255, 214, 90)
local PAD = Color3.fromRGB(255, 90, 190)
local LANTERN = Color3.fromRGB(255, 196, 120)
local WATER = Color3.fromRGB(150, 215, 245)
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local WorldBuilder = {}

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.FilterDescendantsInstances = { Terrain }

-- Helpers ------------------------------------------------------------------------

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

-- Decoration that shouldn't block movement, grappling or shadows.
local function decor(props: { [string]: any }, parent: Instance): Part
	props.CanCollide = false
	props.CanQuery = false
	props.CanTouch = false
	return part(props, parent)
end

-- A vertical cylinder (Roblox cylinders lie along X, so we rotate them upright).
local function cylinder(parent: Instance, center: Vector3, height: number, radius: number, props: { [string]: any })
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(height, radius * 2, radius * 2)
	props.CFrame = (props.CFrame or CFrame.new(center)) * CFrame.Angles(0, 0, math.pi / 2)
	return part(props, parent)
end

local function vary(color: Color3, rng: Random, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(
		h,
		math.clamp(s + rng:NextNumber(-amount, amount), 0, 1),
		math.clamp(v + rng:NextNumber(-amount, amount), 0, 1)
	)
end

local function pick<T>(list: { T }, rng: Random): T
	return list[rng:NextInteger(1, #list)]
end

-- Height of the terrain surface under (x, z), or nil over water / empty sky.
local function groundAt(x: number, z: number, fromY: number): Vector3?
	local hit = workspace:Raycast(Vector3.new(x, fromY + 150, z), Vector3.new(0, -300, 0), groundParams)
	if not hit or hit.Material == M.Water or hit.Material == M.Rock or hit.Material == M.Slate then
		return nil
	end
	return hit.Position
end

local function randomSpot(center: Vector3, minR: number, maxR: number, rng: Random): (number, number)
	local angle = rng:NextNumber(0, math.pi * 2)
	local dist = rng:NextNumber(minR, maxR)
	return center.X + math.cos(angle) * dist, center.Z + math.sin(angle) * dist
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = parent
	return e
end

-- Decorations ----------------------------------------------------------------------

local function leafyTree(parent: Instance, base: Vector3, palette: { Color3 }, rng: Random, petals: boolean?)
	local model = Instance.new("Model")
	model.Name = "Tree"
	local height = rng:NextNumber(10, 17)
	local lean = CFrame.Angles(rng:NextNumber(-0.08, 0.08), 0, rng:NextNumber(-0.08, 0.08))
	local trunkFrame = CFrame.new(base) * lean * CFrame.new(0, height / 2 - 1, 0)
	cylinder(model, Vector3.zero, height, rng:NextNumber(0.7, 1.0), {
		Name = "Trunk",
		CFrame = trunkFrame,
		Material = Enum.Material.Wood,
		Color = vary(WOOD, rng, 0.05),
	})
	local top = (trunkFrame * CFrame.new(0, height / 2, 0)).Position
	local crown = height * rng:NextNumber(0.5, 0.65)
	part({
		Name = "Leaves",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * crown,
		Position = top,
		Color = vary(pick(palette, rng), rng, 0.06),
	}, model)
	for _ = 1, rng:NextInteger(3, 5) do
		local offset = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.5, 0.2), rng:NextNumber(-1, 1)).Unit
			* crown
			* 0.45
		part({
			Name = "Leaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * crown * rng:NextNumber(0.55, 0.8),
			Position = top + offset,
			Color = vary(pick(palette, rng), rng, 0.06),
		}, model)
	end
	if petals then
		local holder = decor({ Name = "Petals", Transparency = 1, Size = Vector3.one * crown, Position = top }, model)
		emitter(holder, {
			Texture = SPARKLE,
			Color = ColorSequence.new(palette[1]),
			Rate = 2,
			Lifetime = NumberRange.new(4, 6),
			Speed = NumberRange.new(0.5, 1.5),
			Acceleration = Vector3.new(0.6, -1.5, 0.3),
			Size = NumberSequence.new(0.35),
			RotSpeed = NumberRange.new(-60, 60),
			Shape = Enum.ParticleEmitterShape.Sphere,
		})
	end
	model.Parent = parent
end

-- Stylised tiered pine.
local function pineTree(parent: Instance, base: Vector3, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Pine"
	local scale = rng:NextNumber(0.8, 1.3)
	cylinder(model, base + Vector3.new(0, 2 * scale, 0), 5 * scale, 0.7 * scale, {
		Name = "Trunk",
		Material = Enum.Material.Wood,
		Color = vary(WOOD, rng, 0.05),
	})
	for tier = 0, 3 do
		cylinder(model, base + Vector3.new(0, (4 + tier * 2.6) * scale, 0), 2.6 * scale, (5.2 - tier * 1.15) * scale, {
			Name = "Needles",
			Color = vary(pick(LEAVES.Pine, rng), rng, 0.04),
		})
	end
	-- Snow on the top tier.
	cylinder(model, base + Vector3.new(0, (4 + 3 * 2.6 + 1.2) * scale, 0), 0.6 * scale, 1.6 * scale, {
		Name = "Snow",
		Color = Color3.fromRGB(245, 248, 255),
	})
	model.Parent = parent
end

local function flowerPatch(parent: Instance, center: Vector3, rng: Random)
	local color = pick(FLOWERS, rng)
	for _ = 1, rng:NextInteger(5, 9) do
		local offset = Vector3.new(rng:NextNumber(-3, 3), 0.3, rng:NextNumber(-3, 3))
		decor({
			Name = "Flower",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * rng:NextNumber(0.5, 0.9),
			Position = center + offset,
			Color = vary(color, rng, 0.05),
			CastShadow = false,
		}, parent)
	end
end

local function lantern(parent: Instance, base: Vector3)
	part({
		Name = "LanternPost",
		Size = Vector3.new(0.6, 7, 0.6),
		Position = base + Vector3.new(0, 3.5, 0),
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(70, 52, 40),
	}, parent)
	local light = decor({
		Name = "Lantern",
		Size = Vector3.new(1.4, 1.6, 1.4),
		Position = base + Vector3.new(0, 7.6, 0),
		Material = Enum.Material.Neon,
		Color = LANTERN,
	}, parent)
	local glow = Instance.new("PointLight")
	glow.Color = LANTERN
	glow.Range = 18
	glow.Brightness = 1.4
	glow.Shadows = true
	glow.Parent = light
	part({
		Name = "LanternCap",
		Size = Vector3.new(2, 0.4, 2),
		Position = base + Vector3.new(0, 8.6, 0),
		Color = Color3.fromRGB(70, 52, 40),
	}, parent)
end

local function column(parent: Instance, base: Vector3, height: number, rng: Random)
	cylinder(
		parent,
		base + Vector3.new(0, 0.5, 0),
		1,
		2.2,
		{ Name = "ColumnBase", Material = Enum.Material.Marble, Color = STONE }
	)
	cylinder(parent, base + Vector3.new(0, height / 2, 0), height, 1.5, {
		Name = "Column",
		Material = Enum.Material.Marble,
		Color = vary(STONE, rng, 0.03),
	})
	if rng:NextNumber() < 0.5 then
		part({
			Name = "Capital",
			Size = Vector3.new(4.4, 1, 4.4),
			Position = base + Vector3.new(0, height + 0.5, 0),
			Material = Enum.Material.Marble,
			Color = STONE,
		}, parent)
	else
		-- Broken: the top lies toppled beside it.
		local fallen = CFrame.new(base + Vector3.new(4, 1.5, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
		cylinder(parent, Vector3.zero, height * 0.5, 1.5, {
			Name = "FallenColumn",
			CFrame = fallen * CFrame.Angles(0, 0, -math.pi / 2),
			Material = Enum.Material.Marble,
			Color = STONE,
		})
	end
end

-- Ruined wall with an arch: a wall-run ramp off the island edge.
local function ruinWall(parent: Instance, base: Vector3, outward: Vector3, rng: Random)
	local frame = CFrame.lookAt(base, base + outward) * CFrame.Angles(0, math.pi / 2, 0)
	local length = rng:NextNumber(34, 44)
	local height = rng:NextNumber(18, 24)
	for _, side in { -1, 1 } do
		part({
			Name = "RuinWall",
			Size = Vector3.new(2.5, height, length / 2 - 4),
			CFrame = frame * CFrame.new(0, height / 2, side * (length / 4 + 2)),
			Material = Enum.Material.Limestone,
			Color = vary(STONE, rng, 0.03),
		}, parent)
	end
	part({
		Name = "RuinLintel",
		Size = Vector3.new(2.5, 4, 10),
		CFrame = frame * CFrame.new(0, height - 2, 0),
		Material = Enum.Material.Limestone,
		Color = STONE,
	}, parent)
end

local function waterfall(parent: Instance, center: Vector3, radius: number, rng: Random)
	local angle = rng:NextNumber(0, math.pi * 2)
	local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local surface = center.Y + 2
	local pondRadius = math.max(radius * 0.2, 5)
	local pond = Flat(center) + dir * radius * 0.5 + Vector3.new(0, surface, 0)

	Terrain:FillCylinder(CFrame.new(pond - Vector3.new(0, 1.5, 0)), 3, pondRadius, M.Water)
	local streamStart = pond + dir * pondRadius * 0.6
	local streamEnd = Flat(center) + dir * (radius + 1) + Vector3.new(0, surface, 0)
	local streamLength = (streamEnd - streamStart).Magnitude
	Terrain:FillBlock(
		CFrame.lookAt(streamStart:Lerp(streamEnd, 0.5) - Vector3.new(0, 1, 0), streamEnd - Vector3.new(0, 1, 0)),
		Vector3.new(pondRadius * 0.6, 2, streamLength),
		M.Water
	)

	local fallHeight = 70
	local edge = streamEnd + dir * 1.2
	local sheet = decor({
		Name = "Waterfall",
		Size = Vector3.new(pondRadius * 1.1, fallHeight, 0.6),
		CFrame = CFrame.lookAt(
			edge - Vector3.new(0, fallHeight / 2 - 1, 0),
			edge - Vector3.new(0, fallHeight / 2 - 1, 0) + dir
		),
		Color = WATER,
		Material = Enum.Material.Glass,
		Transparency = 0.45,
		CastShadow = false,
	}, parent)
	emitter(sheet, {
		Texture = SMOKE,
		Color = ColorSequence.new(Color3.new(1, 1, 1)),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 5) }),
		Rate = 30,
		Lifetime = NumberRange.new(1.2, 2),
		Speed = NumberRange.new(4, 8),
		Acceleration = Vector3.new(0, -30, 0),
		EmissionDirection = Enum.NormalId.Front,
		SpreadAngle = Vector2.new(15, 15),
	})
	local mist = Instance.new("Attachment")
	mist.Position = Vector3.new(0, -fallHeight / 2, 0)
	mist.Parent = sheet
	emitter(mist, {
		Texture = SMOKE,
		Color = ColorSequence.new(Color3.new(1, 1, 1)),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) }),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 14) }),
		Rate = 6,
		Lifetime = NumberRange.new(2, 3),
		Speed = NumberRange.new(2, 4),
		SpreadAngle = Vector2.new(180, 180),
	})
end

local function floatingDebris(center: Vector3, radius: number, rng: Random)
	for _ = 1, rng:NextInteger(3, 6) do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = radius * rng:NextNumber(1.1, 1.5)
		local pos = Vector3.new(
			center.X + math.cos(angle) * dist,
			center.Y - rng:NextNumber(8, 40),
			center.Z + math.sin(angle) * dist
		)
		Terrain:FillBall(pos, rng:NextNumber(2, 4.5), M.Rock)
	end
end

-- Islands --------------------------------------------------------------------------

local function sculptIsland(center: Vector3, radius: number, biome: Biome, rng: Random)
	local top = TOP_MATERIAL[biome]
	local rock = if biome == "Alpine" then M.Slate else M.Rock

	-- Rocky underside: layers of boulders, each narrower than the one above,
	-- tapering to a point. Built first so the grass cap can cover its top.
	local layerRadius = radius * 0.95
	local layerTop = center.Y
	while layerRadius > 4 do
		local ball = layerRadius * 0.5
		local y = layerTop + 1 - ball
		local function jitter(): Vector3
			return Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.5, 0.5), rng:NextNumber(-1, 1)) * ball * 0.2
		end
		Terrain:FillBall(Vector3.new(center.X, y, center.Z) + jitter(), ball * 1.05, rock)
		if layerRadius > 12 then
			for k = 1, 5 do
				local angle = k / 5 * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
				local ring = Vector3.new(math.cos(angle), 0, math.sin(angle)) * layerRadius * 0.5
				Terrain:FillBall(
					Vector3.new(center.X, y, center.Z) + ring + jitter(),
					ball * rng:NextNumber(0.8, 1),
					rock
				)
			end
		end
		layerTop = y - ball * 0.35
		layerRadius *= rng:NextNumber(0.6, 0.72)
	end
	Terrain:FillBall(Vector3.new(center.X, layerTop - 2, center.Z), 3, rock)

	-- Grass cap over a band of soil.
	Terrain:FillCylinder(CFrame.new(center - Vector3.new(0, 1, 0)), 6, radius, top)
	Terrain:FillCylinder(CFrame.new(center - Vector3.new(0, 6, 0)), 5, radius * 0.97, M.Ground)

	-- Rolling hills on top.
	if biome ~= "Plaza" then
		for _ = 1, rng:NextInteger(1, 3) do
			local x, z = randomSpot(center, 0, radius * 0.45, rng)
			local hill = radius * rng:NextNumber(0.2, 0.3)
			Terrain:FillBall(Vector3.new(x, center.Y + 2 - hill * 0.75, z), hill, top)
		end
	end

	-- Rocky outcrops along the rim.
	for _ = 1, rng:NextInteger(3, 6) do
		local x, z = randomSpot(center, radius * 0.8, radius * 1.02, rng)
		Terrain:FillBall(Vector3.new(x, center.Y + rng:NextNumber(-2, 1.5), z), rng:NextNumber(3, 6), rock)
	end

	floatingDebris(center, radius, rng)
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

local function decorate(parent: Instance, center: Vector3, radius: number, biome: Biome, rng: Random)
	local model = Instance.new("Model")
	model.Name = biome .. "Island"
	local surfaceY = center.Y + 2

	local function spot(minR: number, maxR: number): Vector3?
		local x, z = randomSpot(center, minR, maxR, rng)
		return groundAt(x, z, surfaceY)
	end

	-- Trees.
	local treeCount = math.floor(radius / 12) + rng:NextInteger(0, 2)
	for _ = 1, treeCount do
		local base = spot(radius * 0.15, radius * 0.8)
		if base then
			if biome == "Alpine" then
				pineTree(model, base, rng)
			elseif biome == "Blossom" then
				leafyTree(model, base, LEAVES.Blossom, rng, rng:NextNumber() < 0.4)
			else
				leafyTree(model, base, if rng:NextNumber() < 0.2 then LEAVES.Autumn else LEAVES.Meadow, rng)
			end
		end
	end

	-- Flowers.
	if biome ~= "Alpine" then
		for _ = 1, rng:NextInteger(2, 5) do
			local base = spot(0, radius * 0.85)
			if base then
				flowerPatch(model, base, rng)
			end
		end
	end

	-- Ruins.
	if biome == "Ruins" then
		for _ = 1, rng:NextInteger(2, 4) do
			local base = spot(radius * 0.2, radius * 0.7)
			if base then
				column(model, base, rng:NextNumber(10, 20), rng)
			end
		end
		local x, z = randomSpot(center, radius * 0.1, radius * 0.4, rng)
		Terrain:FillCylinder(CFrame.new(x, surfaceY - 0.5, z), 1, radius * 0.3, M.Pavement)
	end
	if radius > 28 and (biome == "Ruins" or rng:NextNumber() < 0.35) then
		local angle = rng:NextNumber(0, math.pi * 2)
		local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
		ruinWall(model, Vector3.new(center.X, surfaceY - 1, center.Z) + outward * radius * 0.78, outward, rng)
	end

	if (biome == "Meadow" or biome == "Blossom") and radius > 30 and rng:NextNumber() < 0.45 then
		waterfall(model, center, radius, rng)
	end

	for _ = 1, rng:NextInteger(1, 2) do
		local base = spot(0, radius * 0.5)
		if base then
			shard(model, base + Vector3.new(0, 3, 0))
		end
	end

	model.Parent = parent
end

-- Floating glowing crystals: the obvious "hook me" targets between islands.
local function anchor(parent: Instance, position: Vector3, rng: Random, tint: Color3?)
	Terrain:FillBall(position, 5, M.Rock)
	Terrain:FillBall(position - Vector3.new(0, 4, 0), 3, M.Rock)
	local model = Instance.new("Model")
	model.Name = "SkyAnchor"
	local color = tint or Config.Grapple.RopeColor
	local core = part({
		Name = "Crystal",
		Size = Vector3.new(3, 10, 3),
		CFrame = CFrame.new(position + Vector3.new(0, 8, 0)) * CFrame.Angles(0, math.rad(45), 0),
		Material = Enum.Material.Neon,
		Color = color,
		CastShadow = false,
	}, model)
	for i = 1, 3 do
		local angle = i / 3 * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		part({
			Name = "Crystal",
			Size = Vector3.new(1.6, rng:NextNumber(4, 6.5), 1.6),
			CFrame = CFrame.new(position + Vector3.new(math.cos(angle) * 2.2, 5.5, math.sin(angle) * 2.2))
				* CFrame.Angles(math.cos(angle) * 0.5, 0, -math.sin(angle) * 0.5),
			Material = Enum.Material.Neon,
			Color = vary(color, rng, 0.08),
			CastShadow = false,
		}, model)
	end
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 22
	light.Brightness = 2
	light.Parent = core
	emitter(core, {
		Texture = SPARKLE,
		Color = ColorSequence.new(color),
		LightEmission = 1,
		Rate = 4,
		Lifetime = NumberRange.new(1.5, 2.5),
		Speed = NumberRange.new(1, 3),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) }),
		SpreadAngle = Vector2.new(180, 180),
	})
	model.Parent = parent
end

-- Two parallel floating walls: chain wall-runs through the middle.
local function corridor(parent: Instance, from: Vector3, to: Vector3, rng: Random)
	local mid = (from + to) / 2
	local look = CFrame.lookAt(mid, Vector3.new(to.X, mid.Y, to.Z))
	for _, side in { -1, 1 } do
		local wall = look * CFrame.new(side * 11, 0, 0)
		part({
			Name = "CorridorWall",
			Size = Vector3.new(2.5, 20, 64),
			CFrame = wall,
			Material = Enum.Material.Limestone,
			Color = vary(STONE, rng, 0.03),
		}, parent)
		-- Glowing trim so the walls read as "run on me".
		for _, y in { -10.2, 10.2 } do
			decor({
				Name = "Trim",
				Size = Vector3.new(2.7, 0.5, 64.2),
				CFrame = wall * CFrame.new(0, y, 0),
				Material = Enum.Material.Neon,
				Color = Config.Grapple.RopeColor,
				CastShadow = false,
			}, parent)
		end
	end
	for i = -2, 2 do
		shard(parent, (look * CFrame.new(0, 2, i * 12)).Position)
	end
end

-- Plank bridge with sagging rope rails between two nearby islands.
local function bridge(parent: Instance, a, b)
	local dir = Flat(b.Position - a.Position).Unit
	local startPos = Flat(a.Position) + dir * (a.Radius - 3) + Vector3.new(0, a.Position.Y + 2, 0)
	local endPos = Flat(b.Position) - dir * (b.Radius - 3) + Vector3.new(0, b.Position.Y + 2, 0)
	local length = (endPos - startPos).Magnitude
	local sag = length * 0.06
	local count = math.floor(length / 2.2)
	local model = Instance.new("Model")
	model.Name = "Bridge"

	local function pointAt(t: number): Vector3
		return startPos:Lerp(endPos, t) - Vector3.new(0, sag * math.sin(math.pi * t), 0)
	end
	for i = 0, count do
		local t = i / count
		local here = pointAt(t)
		local ahead = pointAt(math.min(t + 0.01, 1))
		if (ahead - here).Magnitude < 0.001 then
			ahead = here + dir
		end
		part({
			Name = "Plank",
			Size = Vector3.new(5.5, 0.4, 1.9),
			CFrame = CFrame.lookAt(here, here + (ahead - here).Unit) * CFrame.Angles(0, 0, (i % 2 - 0.5) * 0.04),
			Material = Enum.Material.WoodPlanks,
			Color = Color3.fromRGB(160, 118, 80),
		}, model)
	end
	-- Posts and rope rails.
	local right = dir:Cross(Vector3.yAxis)
	for _, side in { -1, 1 } do
		local attachments = {}
		for _, t in { 0, 1 } do
			local base = pointAt(t) + right * side * 2.8
			local post = part({
				Name = "Post",
				Size = Vector3.new(0.6, 4, 0.6),
				Position = base + Vector3.new(0, 1.8, 0),
				Material = Enum.Material.Wood,
				Color = WOOD,
			}, model)
			local attachment = Instance.new("Attachment")
			attachment.Position = Vector3.new(0, 1.6, 0)
			attachment.Parent = post
			attachment.WorldAxis = -Vector3.yAxis
			table.insert(attachments, attachment)
		end
		local rail = Instance.new("Beam")
		rail.Attachment0 = attachments[1]
		rail.Attachment1 = attachments[2]
		rail.CurveSize0 = sag * 1.3
		rail.CurveSize1 = -sag * 1.3
		rail.Width0 = 0.25
		rail.Width1 = 0.25
		rail.FaceCamera = true
		rail.Segments = 16
		rail.Color = ColorSequence.new(Color3.fromRGB(190, 160, 110))
		rail.Parent = model
	end
	model.Parent = parent
end

local function launchPad(parent: Instance, position: Vector3, outward: Vector3)
	cylinder(parent, position - Vector3.new(0, 0.3, 0), 1, 5.5, {
		Name = "PadBase",
		Material = Enum.Material.Marble,
		Color = STONE,
	})
	local pad = cylinder(parent, position + Vector3.new(0, 0.35, 0), 0.4, 4.2, {
		Name = "LaunchPad",
		Material = Enum.Material.Neon,
		Color = PAD,
	})
	pad:SetAttribute("LaunchVelocity", outward * 85 + Vector3.new(0, 150, 0))
	CollectionService:AddTag(pad, "LaunchPad")
	emitter(pad, {
		Texture = SPARKLE,
		Color = ColorSequence.new(PAD),
		LightEmission = 1,
		Rate = 14,
		Lifetime = NumberRange.new(0.6, 1),
		Speed = NumberRange.new(14, 22),
		EmissionDirection = Enum.NormalId.Right, -- the cylinder's axis, which points up
		SpreadAngle = Vector2.new(8, 8),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
	})
	local light = Instance.new("PointLight")
	light.Color = PAD
	light.Range = 14
	light.Parent = pad
end

-- Spinning ring of neon segments (the client spins anything tagged "Spinner").
local function spinnerRing(
	parent: Instance,
	center: Vector3,
	radius: number,
	tilt: CFrame,
	speed: number,
	color: Color3
)
	local model = Instance.new("Model")
	model.Name = "Ring"
	local segments = 18
	local chord = 2 * math.pi * radius / segments * 1.05
	local frame = CFrame.new(center) * tilt
	for i = 1, segments do
		decor({
			Name = "Segment",
			Size = Vector3.new(chord, 0.5, 0.5),
			CFrame = frame * CFrame.Angles(0, i / segments * math.pi * 2, 0) * CFrame.new(0, 0, radius),
			Material = Enum.Material.Neon,
			Color = color,
			CastShadow = false,
		}, model)
	end
	model.WorldPivot = frame
	model:SetAttribute("SpinSpeed", speed)
	CollectionService:AddTag(model, "Spinner")
	model.Parent = parent
end

-- Spawn plaza: cobblestone circle, beacon, lanterns, launch pads, waterfall.
local function buildPlaza(parent: Instance, center: Vector3, radius: number, rng: Random)
	local surface = center.Y + 2
	Terrain:FillCylinder(CFrame.new(center.X, surface - 0.5, center.Z), 1.2, 30, M.Cobblestone)
	Terrain:FillCylinder(CFrame.new(center.X, surface - 0.5, center.Z), 1.3, 9, M.Pavement)

	local plaza = Instance.new("Model")
	plaza.Name = "SpawnPlaza"
	local accent = Config.Grapple.RopeColor

	-- Beacon.
	cylinder(plaza, Vector3.new(center.X, surface + 1.5, center.Z), 3, 5, {
		Name = "Pedestal",
		Material = Enum.Material.Marble,
		Color = STONE,
	})
	local crystal = part({
		Name = "BeaconCrystal",
		Size = Vector3.new(5, 14, 5),
		CFrame = CFrame.new(center.X, surface + 16, center.Z) * CFrame.Angles(0, math.rad(45), 0),
		Material = Enum.Material.Neon,
		Color = accent,
		CanCollide = false,
		CastShadow = false,
	}, plaza)
	local glow = Instance.new("PointLight")
	glow.Color = accent
	glow.Range = 45
	glow.Brightness = 2.5
	glow.Parent = crystal
	emitter(crystal, {
		Texture = SPARKLE,
		Color = ColorSequence.new(accent),
		LightEmission = 1,
		Rate = 10,
		Lifetime = NumberRange.new(2, 3),
		Speed = NumberRange.new(2, 5),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) }),
		SpreadAngle = Vector2.new(180, 180),
	})
	CollectionService:AddTag(crystal, "Spinner")
	crystal:SetAttribute("SpinSpeed", 0.4)
	spinnerRing(plaza, Vector3.new(center.X, surface + 16, center.Z), 8, CFrame.Angles(0.35, 0, 0.2), 0.8, accent)
	spinnerRing(
		plaza,
		Vector3.new(center.X, surface + 16, center.Z),
		10.5,
		CFrame.Angles(-0.3, 0, -0.35),
		-0.55,
		Color3.fromRGB(255, 255, 255)
	)

	-- Spawn point in front of the beacon.
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.Position = Vector3.new(center.X, surface + 0.5, center.Z - 16)
	spawn.Material = Enum.Material.Marble
	spawn.Color = STONE
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = plaza

	for i = 0, 7 do
		local angle = i / 8 * math.pi * 2 + math.pi / 8
		lantern(plaza, Vector3.new(center.X + math.cos(angle) * 27, surface, center.Z + math.sin(angle) * 27))
	end
	for i = 0, 3 do
		local angle = i * math.pi / 2 + math.pi / 4
		local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
		launchPad(plaza, Vector3.new(center.X, surface, center.Z) + outward * 38, outward)
	end
	for _, degrees in { 160, 250, 290, 20 } do
		local angle = math.rad(degrees)
		local base = groundAt(center.X + math.cos(angle) * 58, center.Z + math.sin(angle) * 58, surface)
		if base then
			leafyTree(plaza, base, LEAVES.Blossom, rng, true)
		end
	end
	plaza.Parent = parent
	waterfall(parent, center, radius, rng)
end

-- Landmarks -------------------------------------------------------------------------

-- Three giant islands far out, each with a sky beacon you can see from anywhere.
local LANDMARKS = {
	{
		Name = "Sky Temple",
		Position = Vector3.new(0, 212, -1450),
		Radius = 95,
		Biome = "Ruins" :: Biome,
		Color = Color3.fromRGB(255, 205, 110),
	},
	{
		Name = "Frost Peak",
		Position = Vector3.new(1350, 360, 650),
		Radius = 80,
		Biome = "Alpine" :: Biome,
		Color = Color3.fromRGB(170, 220, 255),
	},
	{
		Name = "Crystal Garden",
		Position = Vector3.new(-1300, 188, 850),
		Radius = 85,
		Biome = "Blossom" :: Biome,
		Color = Color3.fromRGB(200, 130, 255),
	},
}

local function beacon(parent: Instance, base: Vector3, color: Color3, name: string)
	local pillar = decor({
		Name = "Beacon",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(900, 3, 3),
		CFrame = CFrame.new(base + Vector3.new(0, 450, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = 0.55,
		CastShadow = false,
	}, parent)
	local label = Instance.new("BillboardGui")
	label.Size = UDim2.fromOffset(320, 50)
	label.StudsOffsetWorldSpace = Vector3.new(0, -420, 0)
	label.MaxDistance = 5000
	label.LightInfluence = 0
	label.Parent = pillar
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBlack
	text.TextScaled = true
	text.TextColor3 = color
	text.TextStrokeTransparency = 0.3
	text.Text = string.upper(name)
	text.Parent = label
end

local function buildLandmark(parent: Instance, landmark, rng: Random)
	local center, radius = landmark.Position, landmark.Radius
	local surface = center.Y + 2
	local model = Instance.new("Model")
	model.Name = landmark.Name

	if landmark.Name == "Sky Temple" then
		-- A colonnade around a paved court with a floating relic.
		Terrain:FillCylinder(CFrame.new(center.X, surface - 0.5, center.Z), 1.2, radius * 0.4, M.Pavement)
		for i = 1, 12 do
			local angle = i / 12 * math.pi * 2
			local base =
				groundAt(center.X + math.cos(angle) * radius * 0.6, center.Z + math.sin(angle) * radius * 0.6, surface)
			if base then
				column(model, base, rng:NextNumber(20, 30), rng)
			end
		end
		for tier = 0, 2 do
			part({
				Name = "Altar",
				Size = Vector3.new(18 - tier * 5, 3, 18 - tier * 5),
				Position = Vector3.new(center.X, surface + 1.5 + tier * 3, center.Z),
				Material = Enum.Material.Marble,
				Color = STONE,
			}, model)
		end
		local relic = part({
			Name = "Relic",
			Size = Vector3.new(6, 6, 6),
			CFrame = CFrame.new(center.X, surface + 22, center.Z) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
			Material = Enum.Material.Neon,
			Color = landmark.Color,
			CanCollide = false,
			CastShadow = false,
		}, model)
		CollectionService:AddTag(relic, "Spinner")
		relic:SetAttribute("SpinSpeed", 0.6)
		spinnerRing(model, relic.Position, 9, CFrame.Angles(0.4, 0, 0), 0.9, landmark.Color)
	elseif landmark.Name == "Frost Peak" then
		-- A towering snowy spire to climb and swing around.
		for i = 0, 10 do
			local jitter = Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3))
			Terrain:FillBall(
				Vector3.new(center.X, surface + 4 + i * 9, center.Z) + jitter,
				radius * 0.45 * (1 - i / 12),
				if i > 5 then M.Snow else M.Slate
			)
		end
		for i = 1, 5 do
			local angle = i / 5 * math.pi * 2
			anchor(
				model,
				Vector3.new(center.X + math.cos(angle) * 30, surface + 40 + i * 12, center.Z + math.sin(angle) * 30),
				rng,
				landmark.Color
			)
		end
	else
		-- A garden of glowing crystal clusters among blossom trees.
		for _ = 1, 14 do
			local x, z = randomSpot(center, radius * 0.1, radius * 0.8, rng)
			local base = groundAt(x, z, surface)
			if base then
				anchor(model, base + Vector3.new(0, 1, 0), rng, vary(landmark.Color, rng, 0.1))
			end
		end
	end

	for _ = 1, 10 do
		local x, z = randomSpot(center, 0, radius * 0.7, rng)
		local base = groundAt(x, z, surface)
		if base then
			shard(model, base + Vector3.new(0, 3, 0))
		end
	end
	beacon(model, Vector3.new(center.X, surface, center.Z), landmark.Color, landmark.Name)
	model.Parent = parent
end

-- Sky ------------------------------------------------------------------------------

local function cloud(parent: Instance, center: Vector3, size: number, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Cloud"
	for i = 1, rng:NextInteger(4, 7) do
		local ball = size * rng:NextNumber(0.5, 1)
		local offset = if i == 1
			then Vector3.zero
			else Vector3.new(
				rng:NextNumber(-0.8, 0.8) * size,
				rng:NextNumber(-0.12, 0.2) * size,
				rng:NextNumber(-0.5, 0.5) * size
			)
		decor({
			Name = "Puff",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * ball,
			Position = center + offset,
			Color = if offset.Y < 0 then Color3.fromRGB(232, 236, 250) else Color3.fromRGB(255, 255, 255),
			Transparency = 0.08,
			CastShadow = false,
		}, model)
	end
	model.Parent = parent
end

local function setupAtmosphere()
	Lighting.ClockTime = 16.4
	Lighting.GeographicLatitude = 35
	Lighting.Brightness = 3
	Lighting.ExposureCompensation = 0.15
	Lighting.Ambient = Color3.fromRGB(70, 72, 96)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 158, 196)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.3

	local function ensure(className: string, parent: Instance?): any
		local owner = parent or Lighting
		local existing = owner:FindFirstChildOfClass(className)
		if existing then
			return existing
		end
		local created = Instance.new(className)
		created.Parent = owner
		return created
	end
	local atmosphere = ensure("Atmosphere")
	atmosphere.Density = 0.34
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(212, 226, 255)
	atmosphere.Decay = Color3.fromRGB(150, 128, 190)
	atmosphere.Glare = 0.6
	atmosphere.Haze = 1.8
	local bloom = ensure("BloomEffect")
	bloom.Intensity = 0.8
	bloom.Size = 30
	bloom.Threshold = 1.25
	local sunRays = ensure("SunRaysEffect")
	sunRays.Intensity = 0.1
	sunRays.Spread = 0.85
	local grade = ensure("ColorCorrectionEffect")
	grade.Saturation = 0.18
	grade.Contrast = 0.08
	grade.TintColor = Color3.fromRGB(255, 248, 240)
	local depth = ensure("DepthOfFieldEffect")
	depth.FarIntensity = 0.12
	depth.FocusDistance = 60
	depth.InFocusRadius = 140
	depth.NearIntensity = 0

	local clouds = ensure("Clouds", Terrain)
	clouds.Cover = 0.5
	clouds.Density = 0.7
	clouds.Color = Color3.fromRGB(255, 250, 245)

	Terrain.WaterColor = Color3.fromRGB(60, 170, 205)
	Terrain.WaterTransparency = 0.5
	Terrain.WaterReflectance = 0.6
	Terrain.WaterWaveSize = 0.08
	Terrain.WaterWaveSpeed = 6
	local colors = {
		[M.Grass] = Color3.fromRGB(108, 178, 84),
		[M.LeafyGrass] = Color3.fromRGB(120, 176, 96),
		[M.Ground] = Color3.fromRGB(122, 94, 70),
		[M.Rock] = Color3.fromRGB(128, 120, 140),
		[M.Slate] = Color3.fromRGB(100, 98, 116),
		[M.Snow] = Color3.fromRGB(240, 244, 255),
		[M.Cobblestone] = Color3.fromRGB(172, 166, 152),
		[M.Pavement] = Color3.fromRGB(196, 188, 172),
	}
	for material, color in colors do
		Terrain:SetMaterialColor(material, color)
	end
end

-- Build ------------------------------------------------------------------------------

function WorldBuilder.Build()
	setupAtmosphere()

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

	-- Place islands; they climb higher the further out you go.
	local spawnIsland = { Position = Vector3.new(0, 100, 0), Radius = 70, Biome = "Plaza" :: Biome }
	local islands = { spawnIsland }
	for _, landmark in LANDMARKS do
		table.insert(islands, { Position = landmark.Position, Radius = landmark.Radius, Biome = landmark.Biome })
	end
	local attempts = 0
	while #islands < WORLD.IslandCount and attempts < 10000 do
		attempts += 1
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = math.sqrt(rng:NextNumber()) * WORLD.WorldRadius
		local radius = rng:NextNumber(20, 50)
		-- Snap heights to the terrain grid so surfaces are crisp.
		local height = math.floor((90 + dist * WORLD.HeightPerStud + rng:NextNumber(-40, 40)) / 4 + 0.5) * 4
		local pos = Vector3.new(math.cos(angle) * dist, height, math.sin(angle) * dist)
		local fits = true
		for _, other in islands do
			if (Flat(pos) - Flat(other.Position)).Magnitude < radius + other.Radius + 45 then
				fits = false
				break
			end
		end
		if fits then
			local roll = rng:NextNumber()
			local biome: Biome = if height > 240
				then "Alpine"
				elseif roll < 0.45 then "Meadow"
				elseif roll < 0.72 then "Blossom"
				else "Ruins"
			table.insert(islands, { Position = pos, Radius = radius, Biome = biome })
		end
	end

	-- Terrain first, so decorations can be placed on the real ground.
	for _, island in islands do
		sculptIsland(island.Position, island.Radius, island.Biome, rng)
	end
	buildPlaza(map, spawnIsland.Position, spawnIsland.Radius, rng)
	for i = 2, #islands do
		local island = islands[i]
		decorate(map, island.Position, island.Radius, island.Biome, rng)
	end
	for _, landmark in LANDMARKS do
		buildLandmark(map, landmark, rng)
	end

	-- Link each island to its two nearest neighbours: bridge, corridor or anchor.
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
				if gap < 80 and math.abs(a.Position.Y - b.Position.Y) < 24 and i ~= 1 and j ~= 1 then
					bridge(map, a, b)
				elseif gap > 110 and rng:NextNumber() < 0.35 then
					corridor(map, a.Position, b.Position, rng)
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

	-- A sea of clouds far below, plus drifting puffs between the islands.
	local sky = Instance.new("Folder")
	sky.Name = "Clouds"
	sky.Parent = map
	local scale = WORLD.WorldRadius / 1000
	for _ = 1, math.floor(70 * scale) do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = math.sqrt(rng:NextNumber()) * (WORLD.WorldRadius + 300)
		cloud(
			sky,
			Vector3.new(math.cos(angle) * dist, rng:NextNumber(-45, -25), math.sin(angle) * dist),
			rng:NextNumber(50, 90),
			rng
		)
	end
	for _ = 1, math.floor(30 * scale) do
		local pos = Vector3.new(
			rng:NextNumber(-WORLD.WorldRadius, WORLD.WorldRadius),
			rng:NextNumber(30, 320),
			rng:NextNumber(-WORLD.WorldRadius, WORLD.WorldRadius)
		)
		cloud(sky, pos, rng:NextNumber(14, 28), rng)
	end

	return islands
end

return WorldBuilder

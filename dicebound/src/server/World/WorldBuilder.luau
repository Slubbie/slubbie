-- Builds all five regions from parts at server start, so the game needs no purchased assets.
-- Every region shares one layout (so players always know where things are):
--   spawn pad (south) · rolling circle + big die (center) · merchant stall (east)
--   second stall (west: upgrades / dice / crafting / collection) · travel portal (north)
-- A theme then decorates each island with its own palette and props.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Dicebound.Config)
local Net = require(ReplicatedStorage.Dicebound.Net)
local Builder = require(script.Parent.Builder)
local Props = require(script.Parent.Props)

local WorldBuilder = {}

local function worldPos(region, rel: { number }): Vector3
	local o = region.Origin
	return Vector3.new(o[1] + rel[1], o[2] + rel[2], o[3] + rel[3])
end

-- Server defaults (Meadow mood). Clients re-tint lighting per region locally.
local function setupLighting()
	Lighting.ClockTime = 15.2
	Lighting.Brightness = 2.4
	Lighting.Ambient = Color3.fromRGB(90, 80, 70)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 140, 125)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.GlobalShadows = true

	local function ensure(className: string, parent: Instance): Instance
		local existing = parent:FindFirstChildOfClass(className)
		if existing then
			return existing
		end
		local created = Instance.new(className)
		created.Parent = parent
		return created
	end
	local atmosphere = ensure("Atmosphere", Lighting) :: Atmosphere
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(255, 236, 205)
	atmosphere.Decay = Color3.fromRGB(150, 180, 230)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 1.2

	local bloom = ensure("BloomEffect", Lighting) :: BloomEffect
	bloom.Intensity = 0.35
	bloom.Size = 20
	bloom.Threshold = 1.4

	local grade = ensure("ColorCorrectionEffect", Lighting) :: ColorCorrectionEffect
	grade.Saturation = 0.12
	grade.Contrast = 0.05
	grade.TintColor = Color3.fromRGB(255, 250, 240)

	local rays = ensure("SunRaysEffect", Lighting) :: SunRaysEffect
	rays.Intensity = 0.04
	rays.Spread = 0.6

	local clouds = ensure("Clouds", Workspace.Terrain) :: Clouds
	clouds.Cover = 0.55
	clouds.Density = 0.5
end

local function promptOpens(prompt: ProximityPrompt, panel: string, regionId: string)
	prompt.Triggered:Connect(function(player)
		Net.Events.OpenPanel:FireClient(player, panel, regionId)
	end)
end

local function nameTag(head: BasePart, text: string)
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(240, 50)
	tag.StudsOffset = Vector3.new(0, 2.6, 0)
	tag.MaxDistance = 90
	tag.Parent = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Text = text
	label.Parent = tag
end

-- Theme data: materials and colors for the shared layout.
local THEMES = {
	meadow = {
		Top = "Grass",
		Layers = { { 120, 85, 55 }, { 105, 100, 95 }, { 90, 85, 85 } },
		Plaza = { Color = { 175, 165, 150 }, Material = "Cobblestone" },
		Circle = { { 225, 205, 160 }, { 140, 190, 110 } },
		Stone = { 150, 140, 170 },
		Die = { { 250, 245, 235 }, { 220, 60, 60 } },
		StallA = { 230, 90, 80 },
		StallB = { 80, 130, 220 },
		Shirts = { { 200, 80, 70 }, { 70, 120, 200 } },
	},
	crystal = {
		Top = "Slate",
		Layers = { { 55, 50, 70 }, { 45, 40, 60 }, { 35, 32, 50 } },
		Plaza = { Color = { 80, 72, 105 }, Material = "Pebble" },
		Circle = { { 120, 100, 170 }, { 70, 60, 110 } },
		Stone = { 90, 80, 120 },
		Die = { { 210, 235, 255 }, { 120, 60, 200 } },
		StallA = { 130, 100, 220 },
		StallB = { 80, 200, 230 },
		Shirts = { { 120, 90, 200 }, { 60, 150, 190 } },
	},
	frost = {
		Top = "Snow",
		Layers = { { 180, 195, 215 }, { 120, 130, 150 }, { 100, 110, 130 } },
		Plaza = { Color = { 190, 200, 215 }, Material = "Cobblestone" },
		Circle = { { 230, 240, 255 }, { 150, 200, 235 } },
		Stone = { 170, 185, 205 },
		Die = { { 235, 245, 255 }, { 40, 110, 190 } },
		StallA = { 200, 60, 60 },
		StallB = { 60, 120, 90 },
		Shirts = { { 170, 50, 50 }, { 50, 100, 80 } },
	},
	ember = {
		Top = "Basalt",
		Layers = { { 55, 42, 40 }, { 45, 35, 35 }, { 35, 28, 28 } },
		Plaza = { Color = { 80, 65, 60 }, Material = "Slate" },
		Circle = { { 120, 80, 60 }, { 60, 40, 35 } },
		Stone = { 70, 60, 60 },
		Die = { { 60, 30, 25 }, { 255, 120, 30 } },
		StallA = { 230, 100, 40 },
		StallB = { 90, 90, 100 },
		Shirts = { { 160, 70, 40 }, { 80, 80, 95 } },
	},
	astral = {
		Top = "Marble",
		Layers = { { 90, 75, 140 }, { 70, 60, 115 }, { 55, 45, 95 } },
		Plaza = { Color = { 225, 220, 240 }, Material = "Marble" },
		Circle = { { 255, 240, 190 }, { 90, 70, 190 } },
		Stone = { 200, 195, 225 },
		Die = { { 40, 30, 90 }, { 255, 240, 170 } },
		StallA = { 90, 70, 200 },
		StallB = { 240, 200, 90 },
		Shirts = { { 80, 60, 180 }, { 200, 170, 80 } },
	},
}

-- Shared layout. Returns (model, origin, nature folder).
local function buildBase(root: Instance, region, theme): (Model, Vector3, Model)
	local palette = region.Palette
	local model = Builder.Model(root, region.Id)
	local origin = worldPos(region, { 0, 0, 0 })
	local ground = Builder.Model(model, "Ground")

	-- Floating island.
	Builder.Disc(ground, origin, 200, 8, origin.Y, { Name = "Top", Color = palette.Ground, Material = theme.Top })
	Builder.Disc(
		ground,
		origin,
		188,
		16,
		origin.Y - 8,
		{ Name = "Layer1", Color = theme.Layers[1], Material = "Ground" }
	)
	Builder.Disc(
		ground,
		origin,
		150,
		22,
		origin.Y - 24,
		{ Name = "Layer2", Color = theme.Layers[2], Material = "Rock" }
	)
	Builder.Disc(ground, origin, 90, 26, origin.Y - 46, { Name = "Layer3", Color = theme.Layers[3], Material = "Rock" })
	Builder.Disc(ground, origin, 36, 20, origin.Y - 68, { Name = "Tip", Color = theme.Layers[3], Material = "Rock" })

	-- Invisible rim so nobody walks off by accident.
	local rim = Builder.Model(model, "Rim")
	for i = 0, 35 do
		local angle = i / 36 * math.pi * 2
		local pos = origin + Vector3.new(math.cos(angle) * 99, 6, math.sin(angle) * 99)
		Builder.Part(rim, {
			Name = "Wall",
			Size = Vector3.new(18, 12, 1),
			CFrame = CFrame.lookAt(pos, origin + Vector3.new(0, 6, 0)),
			Transparency = 1,
			CastShadow = false,
		})
	end

	-- Plaza and rolling circle.
	local plaza = Builder.Model(model, "Plaza")
	Builder.Disc(
		plaza,
		origin,
		66,
		1,
		origin.Y + 0.15,
		{ Name = "Plaza", Color = theme.Plaza.Color, Material = theme.Plaza.Material }
	)
	Builder.Disc(
		plaza,
		origin,
		30,
		1,
		origin.Y + 0.3,
		{ Name = "RollingCircle", Color = theme.Circle[1], Material = "Sandstone" }
	)
	Builder.Disc(
		plaza,
		origin,
		26,
		1,
		origin.Y + 0.35,
		{ Name = "RollingCircleInner", Color = theme.Circle[2], Material = "Fabric" }
	)
	for i = 0, 11 do
		local angle = i / 12 * math.pi * 2
		local pos = origin + Vector3.new(math.cos(angle) * 15.5, 0, math.sin(angle) * 15.5)
		Builder.Part(plaza, {
			Name = "CirclePost",
			Size = Vector3.new(1, 1.4, 1),
			CFrame = CFrame.new(pos + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, angle, 0),
			Color = theme.Circle[1],
			Material = "Sandstone",
		})
	end
	Builder.Disc(plaza, origin, 7, 2.4, origin.Y + 2.4, { Name = "Pedestal", Color = theme.Stone, Material = "Marble" })
	Builder.BigDie(
		plaza,
		CFrame.new(origin + Vector3.new(0, 6.6, 0)) * CFrame.Angles(math.rad(35), math.rad(20), math.rad(45)),
		5,
		theme.Die[1],
		theme.Die[2]
	)
	local centerLight = Instance.new("PointLight")
	centerLight.Color = Builder.rgb(palette.Accent)
	centerLight.Range = 22
	centerLight.Brightness = 0.8
	centerLight.Parent = plaza:FindFirstChild("Pedestal")

	-- Region sign over the plaza entrance.
	local signBase = origin + Vector3.new(0, 0, 36)
	for _, x in { -6, 6 } do
		Builder.Part(plaza, {
			Name = "SignPost",
			Size = Vector3.new(0.8, 9, 0.8),
			Position = signBase + Vector3.new(x, 4.5, 0),
			Color = theme.Stone,
			Material = "Wood",
		})
	end
	local board = Builder.Part(plaza, {
		Name = "RegionSign",
		Size = Vector3.new(14, 2.6, 0.5),
		Position = signBase + Vector3.new(0, 8.5, 0),
		Color = palette.Banner,
		Material = "Wood",
	})
	Builder.Label(board, Enum.NormalId.Back, region.Name, { 255, 255, 255 })
	Builder.Label(board, Enum.NormalId.Front, region.Name, { 255, 255, 255 })

	-- Paths: spawn (south) and portal (north).
	local paths = Builder.Model(model, "Paths")
	Builder.Path(paths, origin + Vector3.new(0, 0, 33), origin + Vector3.new(0, 0, 95), 9, palette.Path)
	Builder.Path(paths, origin + Vector3.new(0, 0, -33), origin + Vector3.new(0, 0, -86), 9, palette.Path)

	-- Spawn pad (only Meadow is a real SpawnLocation; others are travel arrival pads).
	local spawnPos = worldPos(region, region.SpawnPosition)
	if region.Order == 1 then
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "MeadowSpawn"
		spawn.Anchored = true
		spawn.Size = Vector3.new(10, 1, 10)
		spawn.CFrame = CFrame.lookAt(spawnPos + Vector3.new(0, 0.5, 0), origin + Vector3.new(0, 0.5, 0))
		spawn.Color = Color3.fromRGB(215, 190, 140)
		spawn.Material = Enum.Material.WoodPlanks
		spawn.TopSurface = Enum.SurfaceType.Smooth
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.Parent = model
	else
		Builder.Disc(
			model,
			spawnPos,
			12,
			1,
			spawnPos.Y + 0.5,
			{ Name = "ArrivalPad", Color = theme.Stone, Material = "Slate" }
		)
		Builder.Disc(model, spawnPos, 8, 1, spawnPos.Y + 0.55, {
			Name = "ArrivalGlow",
			Color = palette.Accent,
			Material = "Neon",
			CanCollide = false,
		})
	end

	-- Merchant stall (east).
	local merchantBase = worldPos(region, region.Merchant.Position) + Vector3.new(3, 0, 0)
	local stall = Builder.Stall(model, merchantBase, Vector3.new(-1, 0, 0), { 250, 245, 235 }, theme.StallA, "Merchant")
	stall.Name = "MerchantStall"
	local _, merchantHead = Builder.Npc(
		stall,
		merchantBase + Vector3.new(1.8, 0, 0),
		Vector3.new(-1, 0, 0),
		theme.Shirts[1],
		{ 90, 60, 40 },
		region.Merchant.Name
	)
	nameTag(merchantHead, "🪙 " .. region.Merchant.Name)
	local counter = stall:FindFirstChild("Counter") :: BasePart
	promptOpens(Builder.Prompt(counter, "Sell & orders", region.Merchant.Name), "Merchant", region.Id)
	for i, offset in { -4, -1.5, 1.5, 4 } do
		Builder.Part(stall, {
			Name = "Goods",
			Shape = if i % 2 == 0 then Enum.PartType.Ball else Enum.PartType.Block,
			Size = Vector3.one * 1.1,
			Position = merchantBase + Vector3.new(-2, 4.35, offset),
			Color = ({ { 255, 190, 40 }, { 120, 200, 255 }, { 200, 110, 60 }, { 120, 220, 120 } })[i],
			Material = if i % 2 == 0 then "Glass" else "Wood",
		})
	end

	-- Second stall (west).
	local stallDef = region.Stall
	local stallBase = worldPos(region, stallDef.Position) + Vector3.new(-3, 0, 0)
	local second =
		Builder.Stall(model, stallBase, Vector3.new(1, 0, 0), { 250, 245, 235 }, theme.StallB, stallDef.Title)
	second.Name = stallDef.Title:gsub("%s", "") .. "Stall"
	local _, keeperHead = Builder.Npc(
		second,
		stallBase + Vector3.new(-1.8, 0, 0),
		Vector3.new(1, 0, 0),
		theme.Shirts[2],
		{ 60, 60, 70 },
		stallDef.Name
	)
	nameTag(keeperHead, "✨ " .. stallDef.Name)
	local bench = second:FindFirstChild("Counter") :: BasePart
	promptOpens(Builder.Prompt(bench, stallDef.Action, stallDef.Name), stallDef.Panel, region.Id)

	-- Travel portal (north).
	local portalPos = worldPos(region, region.Portal)
	local _, gateway = Props.Portal(model, portalPos, Vector3.new(0, 0, 1), theme.Stone, palette.Accent)
	promptOpens(Builder.Prompt(gateway, "Travel", "Travel Stone"), "Map", region.Id)

	-- Lanterns ringing the plaza (skipping the stall and path directions).
	for i = 0, 7 do
		local angle = (i + 0.5) / 8 * math.pi * 2
		Builder.Lantern(model, origin + Vector3.new(math.cos(angle) * 35, 0, math.sin(angle) * 35), palette.Accent)
	end
	for _, z in { 55, 75, -55, -75 } do
		Builder.Lantern(model, origin + Vector3.new(6.5, 0, z), palette.Accent, 7)
		Builder.Lantern(model, origin + Vector3.new(-6.5, 0, z), palette.Accent, 7)
	end

	return model, origin, Builder.Model(model, "Nature")
end

-- Ring positions around the island that stay clear of paths and stalls.
local function ringSpots(rng: Random, count: number, rMin: number, rMax: number): { { Angle: number, R: number } }
	local spots = {}
	for i = 0, count - 1 do
		local angle = i / count * math.pi * 2 + rng:NextNumber() * 0.12
		local clear = true
		for _, blocked in { 0, math.pi / 2, math.pi, math.pi * 1.5 } do
			if math.abs((angle - blocked + math.pi) % (math.pi * 2) - math.pi) < 0.22 then
				clear = false
			end
		end
		if clear then
			table.insert(spots, { Angle = angle, R = rMin + rng:NextNumber() * (rMax - rMin) })
		end
	end
	return spots
end

local function at(origin: Vector3, spot): Vector3
	return origin + Vector3.new(math.cos(spot.Angle) * spot.R, 0, math.sin(spot.Angle) * spot.R)
end

-- ── Themes ─────────────────────────────────────────────────────────────────────

local Decorate = {}

function Decorate.meadow(model: Model, origin: Vector3, nature: Model, rng: Random)
	for _, spot in ringSpots(rng, 30, 72, 90) do
		Builder.Tree(nature, at(origin, spot), 0.9 + rng:NextNumber() * 0.5, {
			70 + rng:NextInteger(0, 30),
			150 + rng:NextInteger(0, 40),
			60 + rng:NextInteger(0, 20),
		}, rng)
	end
	for _, spot in ringSpots(rng, 14, 48, 60) do
		local center = at(origin, spot)
		Builder.Flowers(nature, center, 5, 14, {
			{ 255, 120, 150 },
			{ 255, 220, 90 },
			{ 180, 140, 255 },
			{ 255, 255, 255 },
		}, rng)
		Builder.Rock(nature, center + Vector3.new(4, 0, 3), 2.5, { 150, 145, 135 }, rng)
	end
	local fence = { 170, 125, 80 }
	Builder.Fence(model, origin + Vector3.new(9, 0, 40), origin + Vector3.new(9, 0, 92), fence)
	Builder.Fence(model, origin + Vector3.new(-9, 0, 40), origin + Vector3.new(-9, 0, 92), fence)
end

function Decorate.crystal(_model: Model, origin: Vector3, nature: Model, rng: Random)
	local colors = { { 170, 110, 255 }, { 110, 220, 255 }, { 255, 140, 220 } }
	for _, spot in ringSpots(rng, 26, 60, 92) do
		Props.Crystals(nature, at(origin, spot), 1 + rng:NextNumber() * 1.3, colors[rng:NextInteger(1, #colors)], rng)
	end
	for _, spot in ringSpots(rng, 14, 84, 95) do
		Props.Spire(nature, at(origin, spot), 18 + rng:NextNumber() * 20, 7 + rng:NextNumber() * 4, { 70, 62, 90 })
	end
	for _, spot in ringSpots(rng, 18, 42, 58) do
		Props.Mushroom(
			nature,
			at(origin, spot),
			0.7 + rng:NextNumber() * 0.6,
			if rng:NextNumber() < 0.5 then { 90, 230, 200 } else { 200, 120, 255 }
		)
	end
	-- Hanging crystal chandeliers over the plaza.
	for i = 0, 3 do
		local angle = i / 4 * math.pi * 2 + math.pi / 4
		local pos = origin + Vector3.new(math.cos(angle) * 22, 26, math.sin(angle) * 22)
		Props.StarOrb(nature, pos, 2.2, colors[i % 3 + 1])
	end
end

function Decorate.frost(model: Model, origin: Vector3, nature: Model, rng: Random)
	for _, spot in ringSpots(rng, 28, 70, 92) do
		Props.Pine(nature, at(origin, spot), 0.8 + rng:NextNumber() * 0.5)
	end
	for i, spot in ringSpots(rng, 6, 55, 60) do
		local pos = at(origin, spot)
		Props.Cabin(model, pos, (origin - pos).Unit, if i % 2 == 0 then { 140, 90, 60 } else { 120, 75, 50 })
	end
	for _, spot in ringSpots(rng, 20, 40, 95) do
		Props.Drift(nature, at(origin, spot), 4 + rng:NextNumber() * 5)
	end
	Builder.Disc(
		nature,
		origin + Vector3.new(60, 0, 60),
		22,
		1,
		origin.Y + 0.2,
		{ Name = "Pond", Color = { 170, 215, 240 }, Material = "Ice" }
	)
	for i = 0, 2 do
		Props.Aurora(
			model,
			origin + Vector3.new(-40 + i * 40, 70 + i * 6, -60 + i * 10),
			if i == 1 then { 150, 120, 255 } else { 90, 255, 180 },
			90,
			math.rad(-20 + i * 25)
		)
	end
	-- Gentle snowfall around the plaza.
	local sky = Builder.Part(model, {
		Name = "SnowCloud",
		Size = Vector3.new(160, 1, 160),
		Position = origin + Vector3.new(0, 60, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})
	local snow = Instance.new("ParticleEmitter")
	snow.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	snow.Color = ColorSequence.new(Color3.new(1, 1, 1))
	snow.Size = NumberSequence.new(0.3)
	snow.Lifetime = NumberRange.new(12, 16)
	snow.Rate = 25
	snow.Speed = NumberRange.new(3, 5)
	snow.EmissionDirection = Enum.NormalId.Bottom
	snow.SpreadAngle = Vector2.new(15, 15)
	snow.Parent = sky
end

function Decorate.ember(model: Model, origin: Vector3, nature: Model, rng: Random)
	for _, spot in ringSpots(rng, 10, 50, 62) do
		Props.LavaPool(nature, at(origin, spot), 8 + rng:NextNumber() * 6)
	end
	for _, spot in ringSpots(rng, 30, 72, 95) do
		Props.Basalt(nature, at(origin, spot), 6 + rng:NextNumber() * 16, 3 + rng:NextNumber() * 3, rng)
	end
	for i, spot in ringSpots(rng, 5, 40, 44) do
		local pos = at(origin, spot)
		Props.Forge(model, pos, (origin - pos).Unit)
		Props.Anvil(model, pos + (origin - pos).Unit * 7, i)
	end
	-- Volcano backdrop to the north-east.
	local volcano = origin + Vector3.new(58, 0, -58)
	Props.Spire(nature, volcano, 45, 44, { 55, 40, 38 })
	local crater = Builder.Disc(nature, volcano, 9, 1, volcano.Y + 45.5, {
		Name = "Crater",
		Color = { 255, 110, 30 },
		Material = "Neon",
		CanCollide = false,
	})
	Props.Smoke(crater, Color3.fromRGB(70, 60, 60))
	-- Rising embers.
	local vent = Builder.Part(model, {
		Name = "EmberVent",
		Size = Vector3.new(150, 1, 150),
		Position = origin + Vector3.new(0, 0.5, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})
	local embers = Instance.new("ParticleEmitter")
	embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 140, 40))
	embers.LightEmission = 1
	embers.Size = NumberSequence.new(0.25, 0)
	embers.Lifetime = NumberRange.new(4, 7)
	embers.Rate = 18
	embers.Speed = NumberRange.new(2, 4)
	embers.EmissionDirection = Enum.NormalId.Top
	embers.SpreadAngle = Vector2.new(25, 25)
	embers.Parent = vent
end

function Decorate.astral(model: Model, origin: Vector3, nature: Model, rng: Random)
	for _, spot in ringSpots(rng, 12, 50, 60) do
		Props.StarPillar(nature, at(origin, spot), 10 + rng:NextNumber() * 6, { 255, 240, 170 })
	end
	-- Floating islands drifting around the sanctuary.
	for i = 0, 9 do
		local angle = i / 10 * math.pi * 2 + rng:NextNumber() * 0.3
		local r = 125 + rng:NextNumber() * 40
		local pos = origin + Vector3.new(math.cos(angle) * r, -10 + rng:NextNumber() * 40, math.sin(angle) * r)
		Props.FloatingRock(nature, pos, 12 + rng:NextNumber() * 14, { 170, 150, 230 }, rng)
	end
	-- Star field.
	for _ = 1, 40 do
		local pos = origin
			+ Vector3.new(rng:NextNumber() * 400 - 200, 40 + rng:NextNumber() * 120, rng:NextNumber() * 400 - 200)
		Props.StarOrb(nature, pos, 0.6 + rng:NextNumber() * 1.2, { 255, 250, 220 })
	end
	-- A crescent moon.
	local moon = origin + Vector3.new(-90, 110, -120)
	Builder.Part(model, {
		Name = "Moon",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 40,
		Position = moon,
		Color = { 255, 250, 225 },
		Material = "Neon",
		CanCollide = false,
		CastShadow = false,
	})
	Builder.Part(model, {
		Name = "MoonShadow",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 38,
		Position = moon + Vector3.new(10, 6, 8),
		Color = { 20, 15, 45 },
		Material = "SmoothPlastic",
		CanCollide = false,
		CastShadow = false,
	})
	-- Orbiting ring of lights over the plaza.
	for i = 0, 23 do
		local angle = i / 24 * math.pi * 2
		Props.StarOrb(
			nature,
			origin + Vector3.new(math.cos(angle) * 30, 24 + math.sin(angle * 2) * 2, math.sin(angle) * 30),
			0.9,
			{ 180, 160, 255 }
		)
	end
end

function WorldBuilder.Build()
	-- Remove the Baseplate template's floor and spawn if the project was synced into one.
	for _, name in { "Baseplate", "SpawnLocation" } do
		local leftover = Workspace:FindFirstChild(name)
		if leftover then
			leftover:Destroy()
		end
	end
	local existing = Workspace:FindFirstChild("Dicebound")
	if existing then
		existing:Destroy()
	end
	setupLighting()
	local root = Instance.new("Folder")
	root.Name = "Dicebound"
	for _, region in Config.Regions.List do
		if Config.IsLive(region) then
			local theme = THEMES[region.Id] or THEMES.meadow
			local rng = Random.new(20260927 + region.Order) -- fixed seeds: same layout every server
			local model, origin, nature = buildBase(root, region, theme)
			local decorate = Decorate[region.Id]
			if decorate then
				decorate(model, origin, nature, rng)
			end
		end
	end
	root.Parent = Workspace
end

return WorldBuilder

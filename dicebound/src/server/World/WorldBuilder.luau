-- Builds the playable world from parts at server start, so the game needs no purchased assets.
-- Stage 1: Meadow Market, a compact floating island with a rolling circle, the merchant stall,
-- the tinkerer's upgrade stall and the (sealed) gate toward Crystal Caverns.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Dicebound.Config)
local Net = require(ReplicatedStorage.Dicebound.Net)
local Builder = require(script.Parent.Builder)

local WorldBuilder = {}

local function worldPos(region, rel: { number }): Vector3
	local o = region.Origin
	return Vector3.new(o[1] + rel[1], o[2] + rel[2], o[3] + rel[3])
end

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

-- Opens a client panel when a world prompt is used.
local function promptOpens(prompt: ProximityPrompt, panel: string, regionId: string)
	prompt.Triggered:Connect(function(player)
		Net.Events.OpenPanel:FireClient(player, panel, regionId)
	end)
end

local function buildMeadow(root: Instance)
	local region = Config.Regions.ById.meadow
	local palette = region.Palette
	local model = Builder.Model(root, region.Id)
	local rng = Random.new(20260927) -- fixed seed: the same layout every server
	local origin = worldPos(region, { 0, 0, 0 })
	local ground = Builder.Model(model, "Ground")

	-- Floating island: grass top, earth and rock layers underneath.
	Builder.Disc(ground, origin, 200, 8, origin.Y, { Name = "Grass", Color = palette.Ground, Material = "Grass" })
	Builder.Disc(ground, origin, 188, 16, origin.Y - 8, { Name = "Earth", Color = { 120, 85, 55 }, Material = "Ground" })
	Builder.Disc(ground, origin, 150, 22, origin.Y - 24, { Name = "Rock", Color = { 105, 100, 95 }, Material = "Rock" })
	Builder.Disc(ground, origin, 90, 26, origin.Y - 46, { Name = "RockLow", Color = { 90, 85, 85 }, Material = "Rock" })
	Builder.Disc(ground, origin, 36, 20, origin.Y - 68, { Name = "RockTip", Color = { 80, 75, 75 }, Material = "Rock" })

	-- Invisible rim so nobody walks off the island by accident.
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

	-- Plaza and rolling circle in the middle.
	local plaza = Builder.Model(model, "Plaza")
	Builder.Disc(plaza, origin, 66, 1, origin.Y + 0.15, {
		Name = "Cobbles",
		Color = { 175, 165, 150 },
		Material = "Cobblestone",
	})
	Builder.Disc(plaza, origin, 30, 1, origin.Y + 0.3, {
		Name = "RollingCircle",
		Color = { 225, 205, 160 },
		Material = "Sandstone",
	})
	Builder.Disc(plaza, origin, 26, 1, origin.Y + 0.35, {
		Name = "RollingCircleInner",
		Color = { 140, 190, 110 },
		Material = "Fabric",
	})
	for i = 0, 11 do
		local angle = i / 12 * math.pi * 2
		local pos = origin + Vector3.new(math.cos(angle) * 15.5, 0, math.sin(angle) * 15.5)
		Builder.Part(plaza, {
			Name = "CirclePost",
			Size = Vector3.new(1, 1.4, 1),
			CFrame = CFrame.new(pos + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, angle, 0),
			Color = { 240, 225, 190 },
			Material = "Sandstone",
		})
	end
	-- Centerpiece: a big die on a pedestal, tipped on its corner.
	Builder.Disc(plaza, origin, 7, 2.4, origin.Y + 2.4, { Name = "Pedestal", Color = { 200, 185, 150 }, Material = "Marble" })
	Builder.BigDie(
		plaza,
		CFrame.new(origin + Vector3.new(0, 6.6, 0)) * CFrame.Angles(math.rad(35), math.rad(20), math.rad(45)),
		5,
		{ 250, 245, 235 },
		{ 220, 60, 60 }
	)
	local centerLight = Instance.new("PointLight")
	centerLight.Color = Color3.fromRGB(255, 220, 170)
	centerLight.Range = 22
	centerLight.Brightness = 0.8
	centerLight.Parent = plaza:FindFirstChild("Pedestal")

	-- Paths: spawn (south) and gate (north). The stalls sit on the plaza's east and west edges.
	local paths = Builder.Model(model, "Paths")
	local pathColor = palette.Path
	Builder.Path(paths, origin + Vector3.new(0, 0, 33), origin + Vector3.new(0, 0, 95), 9, pathColor)
	Builder.Path(paths, origin + Vector3.new(0, 0, -33), origin + Vector3.new(0, 0, -95), 9, pathColor)

	-- Spawn pad.
	local spawnPos = worldPos(region, region.SpawnPosition)
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
	Builder.Sign(
		model,
		spawnPos + Vector3.new(-15, 0, -6),
		Vector3.new(0.4, 0, 1),
		Config.Game.Name,
		{ 250, 240, 215 },
		{ 110, 70, 30 },
		14
	)

	-- Merchant stall (east) and tinkerer stall (west), both facing the plaza.
	local merchantPos = worldPos(region, region.Merchant.Position)
	local merchantBase = merchantPos + Vector3.new(3, 0, 0)
	local stall = Builder.Stall(model, merchantBase, Vector3.new(-1, 0, 0), { 250, 245, 235 }, { 230, 90, 80 }, "Merchant")
	stall.Name = "MerchantStall"
	local _, merchantHead = Builder.Npc(
		stall,
		merchantBase + Vector3.new(1.8, 0, 0),
		Vector3.new(-1, 0, 0),
		{ 200, 80, 70 },
		{ 90, 60, 40 },
		region.Merchant.Name
	)
	local counter = stall:FindFirstChild("Counter") :: BasePart
	promptOpens(Builder.Prompt(counter, "Sell treasure", region.Merchant.Name), "Merchant", region.Id)
	local merchantTag = Instance.new("BillboardGui")
	merchantTag.Size = UDim2.fromOffset(220, 50)
	merchantTag.StudsOffset = Vector3.new(0, 2.6, 0)
	merchantTag.MaxDistance = 90
	merchantTag.Parent = merchantHead
	local tagLabel = Instance.new("TextLabel")
	tagLabel.Size = UDim2.fromScale(1, 1)
	tagLabel.BackgroundTransparency = 1
	tagLabel.Font = Enum.Font.FredokaOne
	tagLabel.TextScaled = true
	tagLabel.TextColor3 = Color3.new(1, 1, 1)
	tagLabel.TextStrokeTransparency = 0.4
	tagLabel.Text = "🪙 " .. region.Merchant.Name
	tagLabel.Parent = merchantTag

	local tinkerPos = worldPos(region, region.Tinkerer.Position)
	local tinkerBase = tinkerPos + Vector3.new(-3, 0, 0)
	local workshop = Builder.Stall(model, tinkerBase, Vector3.new(1, 0, 0), { 250, 245, 235 }, { 80, 130, 220 }, "Upgrades")
	workshop.Name = "TinkererStall"
	local _, tinkerHead = Builder.Npc(
		workshop,
		tinkerBase + Vector3.new(-1.8, 0, 0),
		Vector3.new(1, 0, 0),
		{ 70, 120, 200 },
		{ 60, 60, 70 },
		region.Tinkerer.Name
	)
	local workbench = workshop:FindFirstChild("Counter") :: BasePart
	promptOpens(Builder.Prompt(workbench, "Upgrades", region.Tinkerer.Name), "Upgrades", region.Id)
	local tinkerTag = merchantTag:Clone()
	tinkerTag.Parent = tinkerHead;
	(tinkerTag:FindFirstChildOfClass("TextLabel") :: TextLabel).Text = "🔧 " .. region.Tinkerer.Name

	-- Goods on the counters: a few crates and jars.
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
	for _, offset in { -4, 0, 4 } do
		Builder.Part(workshop, {
			Name = "Gear",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, 1.4, 1.4),
			CFrame = CFrame.new(tinkerBase + Vector3.new(2, 4.5, offset)) * CFrame.Angles(0, math.rad(90), 0),
			Color = { 190, 150, 70 },
			Material = "Metal",
		})
	end

	-- Lanterns ringing the plaza.
	for i = 0, 7 do
		local angle = (i + 0.5) / 8 * math.pi * 2
		Builder.Lantern(model, origin + Vector3.new(math.cos(angle) * 35, 0, math.sin(angle) * 35), palette.Accent)
	end
	-- Lanterns along the spawn and gate paths.
	for _, z in { 55, 75, -55, -75 } do
		Builder.Lantern(model, origin + Vector3.new(6.5, 0, z), palette.Accent, 7)
		Builder.Lantern(model, origin + Vector3.new(-6.5, 0, z), palette.Accent, 7)
	end

	-- Trees, rocks and flowers around the edge, keeping the paths clear.
	local nature = Builder.Model(model, "Nature")
	local function nearPath(angle: number): boolean
		for _, pathAngle in { 0, math.pi / 2, math.pi, math.pi * 1.5 } do
			local d = math.abs((angle - pathAngle + math.pi) % (math.pi * 2) - math.pi)
			if d < 0.2 then
				return true
			end
		end
		return false
	end
	for i = 0, 29 do
		local angle = i / 30 * math.pi * 2 + rng:NextNumber() * 0.1
		if not nearPath(angle) then
			local r = 72 + rng:NextNumber() * 18
			local base = origin + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
			Builder.Tree(nature, base, 0.9 + rng:NextNumber() * 0.5, {
				70 + rng:NextInteger(0, 30),
				150 + rng:NextInteger(0, 40),
				60 + rng:NextInteger(0, 20),
			}, rng)
		end
	end
	for i = 0, 13 do
		local angle = i / 14 * math.pi * 2 + 0.2
		if not nearPath(angle) then
			local r = 50 + rng:NextNumber() * 12
			local center = origin + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
			Builder.Flowers(nature, center, 5, 14, {
				{ 255, 120, 150 },
				{ 255, 220, 90 },
				{ 180, 140, 255 },
				{ 255, 255, 255 },
			}, rng)
			Builder.Rock(nature, center + Vector3.new(4, 0, 3), 2.5, { 150, 145, 135 }, rng)
		end
	end

	-- Fences framing the spawn path.
	local fenceColor = { 170, 125, 80 }
	Builder.Fence(model, origin + Vector3.new(9, 0, 34), origin + Vector3.new(9, 0, 92), fenceColor)
	Builder.Fence(model, origin + Vector3.new(-9, 0, 34), origin + Vector3.new(-9, 0, 92), fenceColor)

	-- Sealed gate toward Crystal Caverns (opens in Stage 2).
	local next = Config.Regions.List[2]
	local gate = Builder.Model(model, "GateToCrystal")
	local gateBase = origin + Vector3.new(0, 0, -93)
	for _, x in { -7, 7 } do
		Builder.Part(gate, {
			Name = "Pillar",
			Size = Vector3.new(3, 16, 3),
			Position = gateBase + Vector3.new(x, 8, 0),
			Color = { 150, 140, 170 },
			Material = "Slate",
		})
	end
	Builder.Part(gate, {
		Name = "Lintel",
		Size = Vector3.new(18, 3, 3.4),
		Position = gateBase + Vector3.new(0, 17.5, 0),
		Color = { 130, 120, 160 },
		Material = "Slate",
	})
	local barrier = Builder.Part(gate, {
		Name = "Barrier",
		Size = Vector3.new(11, 16, 0.6),
		Position = gateBase + Vector3.new(0, 8, 0),
		Color = next.Palette.Accent,
		Material = "ForceField",
		Transparency = 0.2,
		CastShadow = false,
	})
	local gateLabel = Builder.Label(
		Builder.Part(gate, {
			Name = "GateSign",
			Size = Vector3.new(14, 2.4, 0.4),
			Position = gateBase + Vector3.new(0, 20.5, 0),
			Color = { 60, 50, 90 },
			Material = "Wood",
		}),
		Enum.NormalId.Back,
		"💎 " .. next.Name,
		{ 220, 240, 255 }
	)
	gateLabel.Name = "GateTitle"
	Builder.Sign(
		gate,
		gateBase + Vector3.new(11, 0, 5),
		Vector3.new(0, 0, 1),
		if Config.IsLive(next) then "Unlock ahead!" else "Opening in the next update!",
		{ 245, 235, 210 },
		{ 90, 60, 120 },
		11
	)
	local glow = Instance.new("PointLight")
	glow.Color = Builder.rgb(next.Palette.Accent)
	glow.Range = 16
	glow.Brightness = 1.5
	glow.Parent = barrier
end

function WorldBuilder.Build()
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
	local existing = Workspace:FindFirstChild("Dicebound")
	if existing then
		existing:Destroy()
	end
	setupLighting()
	local root = Instance.new("Folder")
	root.Name = "Dicebound"
	buildMeadow(root)
	root.Parent = Workspace
end

return WorldBuilder

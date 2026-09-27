-- Themed props built from plain parts: portals, crystals, pines, cabins, forges, star orbs...
-- Each returns a Model so regions can place them like furniture.

local Builder = require(script.Parent.Builder)

local Props = {}

local P = Builder.Part

-- Travel stone: an arch with a glowing disc. Returns the model and the disc (for the prompt).
function Props.Portal(parent: Instance, base: Vector3, facing: Vector3, stone, glow): (Model, BasePart)
	local model = Builder.Model(parent, "Portal")
	local cf = CFrame.lookAt(base, base + Vector3.new(facing.X, 0, facing.Z))
	for _, x in { -6.5, 6.5 } do
		P(model, {
			Name = "Pillar",
			Size = Vector3.new(2.6, 15, 2.6),
			CFrame = cf * CFrame.new(x, 7.5, 0),
			Color = stone,
			Material = "Slate",
		})
		P(model, {
			Name = "Rune",
			Size = Vector3.new(0.4, 6, 0.4),
			CFrame = cf * CFrame.new(x, 8, -1.35),
			Color = glow,
			Material = "Neon",
			CanCollide = false,
			CastShadow = false,
		})
	end
	P(model, {
		Name = "Lintel",
		Size = Vector3.new(17, 2.6, 3.2),
		CFrame = cf * CFrame.new(0, 16, 0),
		Color = stone,
		Material = "Slate",
	})
	P(model, {
		Name = "Step",
		Size = Vector3.new(15, 0.6, 7),
		CFrame = cf * CFrame.new(0, 0.3, 0),
		Color = stone,
		Material = "Slate",
	})
	local disc = P(model, {
		Name = "Gateway",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, 11, 11),
		CFrame = cf * CFrame.new(0, 7.5, 0) * CFrame.Angles(0, math.rad(90), 0),
		Color = glow,
		Material = "ForceField",
		CanCollide = false,
		CastShadow = false,
	})
	local light = Instance.new("PointLight")
	light.Color = Builder.rgb(glow)
	light.Range = 18
	light.Brightness = 1.6
	light.Parent = disc
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Color = ColorSequence.new(Builder.rgb(glow))
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new(0.4, 0)
	sparkles.Lifetime = NumberRange.new(1, 2)
	sparkles.Rate = 6
	sparkles.Speed = NumberRange.new(0.5, 1.5)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Parent = disc
	return model, disc
end

-- Cluster of glowing crystal shards.
function Props.Crystals(parent: Instance, base: Vector3, scale: number, color, rng: Random): Model
	local model = Builder.Model(parent, "Crystals")
	for _ = 1, rng:NextInteger(3, 5) do
		local h = (3 + rng:NextNumber() * 5) * scale
		local w = (0.8 + rng:NextNumber() * 0.8) * scale
		local offset = Vector3.new(rng:NextNumber() * 2 - 1, 0, rng:NextNumber() * 2 - 1) * scale * 1.2
		P(model, {
			Name = "Shard",
			Size = Vector3.new(w, h, w),
			CFrame = CFrame.new(base + offset + Vector3.new(0, h / 2 - 0.3, 0))
				* CFrame.Angles(rng:NextNumber() * 0.6 - 0.3, rng:NextNumber() * math.pi, rng:NextNumber() * 0.6 - 0.3),
			Color = color,
			Material = if rng:NextNumber() < 0.5 then "Neon" else "Glass",
			Transparency = 0.1,
			CastShadow = false,
		})
	end
	local light = Instance.new("PointLight")
	light.Color = Builder.rgb(color)
	light.Range = 12 * scale
	light.Brightness = 1.2
	light.Parent = model:FindFirstChildWhichIsA("BasePart")
	return model
end

-- Tapered rock spire (stacked cylinders).
function Props.Spire(parent: Instance, base: Vector3, height: number, width: number, color): Model
	local model = Builder.Model(parent, "Spire")
	local steps = 4
	for i = 0, steps - 1 do
		local w = width * (1 - i / steps)
		local h = height / steps
		P(model, {
			Name = "Segment",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(h, w, w),
			CFrame = CFrame.new(base + Vector3.new(0, h * i + h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = color,
			Material = "Rock",
		})
	end
	return model
end

-- Glowing mushroom.
function Props.Mushroom(parent: Instance, base: Vector3, scale: number, capColor): Model
	local model = Builder.Model(parent, "Mushroom")
	P(model, {
		Name = "Stem",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2 * scale, 0.7 * scale, 0.7 * scale),
		CFrame = CFrame.new(base + Vector3.new(0, scale, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = { 230, 225, 210 },
	})
	P(model, {
		Name = "Cap",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.4, 1.2, 2.4) * scale,
		Position = base + Vector3.new(0, 2 * scale, 0),
		Color = capColor,
		Material = "Neon",
		CastShadow = false,
	})
	return model
end

-- Snowy pine tree.
function Props.Pine(parent: Instance, base: Vector3, scale: number): Model
	local model = Builder.Model(parent, "Pine")
	P(model, {
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4 * scale, 1.2 * scale, 1.2 * scale),
		CFrame = CFrame.new(base + Vector3.new(0, 2 * scale, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = { 90, 60, 40 },
		Material = "Wood",
	})
	for i = 0, 3 do
		local w = (9 - i * 2) * scale
		local y = (3.5 + i * 2.6) * scale
		P(model, {
			Name = "Needles",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2.2 * scale, w, w),
			CFrame = CFrame.new(base + Vector3.new(0, y, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = { 45, 95, 70 },
			Material = "Grass",
		})
		P(model, {
			Name = "Snow",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.5 * scale, w * 0.8, w * 0.8),
			CFrame = CFrame.new(base + Vector3.new(0, y + 1.2 * scale, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = { 245, 250, 255 },
			Material = "Snow",
		})
	end
	return model
end

-- Cozy cabin with a snowy roof and a warm window.
function Props.Cabin(parent: Instance, base: Vector3, facing: Vector3, wallColor): Model
	local model = Builder.Model(parent, "Cabin")
	local cf = CFrame.lookAt(base, base + Vector3.new(facing.X, 0, facing.Z))
	P(model, {
		Name = "Walls",
		Size = Vector3.new(14, 9, 11),
		CFrame = cf * CFrame.new(0, 4.5, 0),
		Color = wallColor,
		Material = "WoodPlanks",
	})
	for _, side in { -1, 1 } do
		local roof = Instance.new("WedgePart")
		roof.Anchored = true
		roof.Size = Vector3.new(15, 4.5, 6.5)
		roof.CFrame = cf * CFrame.new(0, 11.25, side * 3.1) * CFrame.Angles(0, if side > 0 then math.pi else 0, 0)
		roof.Color = Color3.fromRGB(245, 250, 255)
		roof.Material = Enum.Material.Snow
		roof.Parent = model
	end
	local window = P(model, {
		Name = "Window",
		Size = Vector3.new(3, 2.4, 0.3),
		CFrame = cf * CFrame.new(-3, 5, -5.55),
		Color = { 255, 200, 120 },
		Material = "Neon",
		CastShadow = false,
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 190, 110)
	light.Range = 14
	light.Parent = window
	P(model, {
		Name = "Door",
		Size = Vector3.new(3, 6, 0.3),
		CFrame = cf * CFrame.new(3, 3, -5.55),
		Color = { 110, 70, 45 },
		Material = "Wood",
	})
	P(model, {
		Name = "Chimney",
		Size = Vector3.new(2, 5, 2),
		CFrame = cf * CFrame.new(4.5, 12, 2),
		Color = { 120, 110, 110 },
		Material = "Brick",
	})
	return model
end

-- Soft snow mound.
function Props.Drift(parent: Instance, base: Vector3, size: number): BasePart
	return P(parent, {
		Name = "Drift",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(size * 1.6, size * 0.6, size),
		Position = base,
		Color = { 245, 250, 255 },
		Material = "Snow",
		CanCollide = false,
	})
end

-- Aurora ribbon: a tall, faint neon curtain in the sky.
function Props.Aurora(parent: Instance, center: Vector3, color, length: number, angle: number): Model
	local model = Builder.Model(parent, "Aurora")
	for i = 0, 5 do
		local offset = CFrame.Angles(0, angle, 0)
			* CFrame.new((i - 2.5) * length / 6, math.sin(i) * 4, math.cos(i * 1.3) * 6)
		P(model, {
			Name = "Ribbon",
			Size = Vector3.new(length / 6 + 1, 18, 0.2),
			CFrame = CFrame.new(center) * offset * CFrame.Angles(0, math.sin(i) * 0.3, 0),
			Color = color,
			Material = "Neon",
			Transparency = 0.72,
			CanCollide = false,
			CastShadow = false,
		})
	end
	return model
end

-- A pool of lava.
function Props.LavaPool(parent: Instance, center: Vector3, diameter: number): Model
	local model = Builder.Model(parent, "LavaPool")
	Builder.Disc(
		model,
		center,
		diameter + 3,
		1,
		center.Y + 0.3,
		{ Name = "Rim", Color = { 40, 32, 32 }, Material = "Basalt" }
	)
	local lava = Builder.Disc(model, center, diameter, 1, center.Y + 0.45, {
		Name = "Lava",
		Color = { 255, 100, 20 },
		Material = "CrackedLava",
		CanCollide = false,
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 120, 40)
	light.Range = diameter + 8
	light.Brightness = 1.4
	light.Parent = lava
	return model
end

local function smoke(part: BasePart, color: Color3)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new(2, 6)
	emitter.Transparency = NumberSequence.new(0.5, 1)
	emitter.Lifetime = NumberRange.new(3, 5)
	emitter.Rate = 3
	emitter.Speed = NumberRange.new(3, 5)
	emitter.SpreadAngle = Vector2.new(12, 12)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Parent = part
end
Props.Smoke = smoke

-- Glowing forge with a smoking chimney.
function Props.Forge(parent: Instance, base: Vector3, facing: Vector3): Model
	local model = Builder.Model(parent, "Forge")
	local cf = CFrame.lookAt(base, base + Vector3.new(facing.X, 0, facing.Z))
	P(model, {
		Name = "Body",
		Size = Vector3.new(9, 7, 7),
		CFrame = cf * CFrame.new(0, 3.5, 0),
		Color = { 70, 60, 60 },
		Material = "Brick",
	})
	local mouth = P(model, {
		Name = "Mouth",
		Size = Vector3.new(4, 3, 0.4),
		CFrame = cf * CFrame.new(0, 3, -3.55),
		Color = { 255, 120, 30 },
		Material = "Neon",
		CastShadow = false,
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 130, 50)
	light.Range = 16
	light.Brightness = 2
	light.Parent = mouth
	local chimney = P(model, {
		Name = "Chimney",
		Size = Vector3.new(2.6, 9, 2.6),
		CFrame = cf * CFrame.new(2.5, 11, 1.5),
		Color = { 60, 50, 50 },
		Material = "Brick",
	})
	smoke(chimney, Color3.fromRGB(90, 85, 85))
	return model
end

function Props.Anvil(parent: Instance, base: Vector3, angle: number): Model
	local model = Builder.Model(parent, "Anvil")
	local cf = CFrame.new(base) * CFrame.Angles(0, angle, 0)
	P(model, {
		Name = "Stump",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, 2.4, 2.4),
		CFrame = cf * CFrame.new(0, 1, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = { 90, 60, 40 },
		Material = "Wood",
	})
	P(model, {
		Name = "Base",
		Size = Vector3.new(1.4, 1, 1.2),
		CFrame = cf * CFrame.new(0, 2.5, 0),
		Color = { 60, 60, 70 },
		Material = "Metal",
	})
	P(model, {
		Name = "Top",
		Size = Vector3.new(3.2, 0.9, 1.4),
		CFrame = cf * CFrame.new(0, 3.4, 0),
		Color = { 70, 70, 80 },
		Material = "Metal",
	})
	return model
end

-- Hexagonal-ish basalt column.
function Props.Basalt(parent: Instance, base: Vector3, height: number, width: number, rng: Random): BasePart
	return P(parent, {
		Name = "Basalt",
		Size = Vector3.new(width, height, width),
		CFrame = CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, rng:NextNumber() * math.pi, 0),
		Color = { 45, 40, 42 },
		Material = "Basalt",
	})
end

-- Floating star orb with a soft light.
function Props.StarOrb(parent: Instance, position: Vector3, size: number, color): BasePart
	local orb = P(parent, {
		Name = "StarOrb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * size,
		Position = position,
		Color = color,
		Material = "Neon",
		CanCollide = false,
		CastShadow = false,
	})
	local light = Instance.new("PointLight")
	light.Color = Builder.rgb(color)
	light.Range = size * 5
	light.Brightness = 1
	light.Parent = orb
	return orb
end

-- Marble pillar topped with a glowing star.
function Props.StarPillar(parent: Instance, base: Vector3, height: number, color): Model
	local model = Builder.Model(parent, "StarPillar")
	P(model, {
		Name = "Column",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, 2.2, 2.2),
		CFrame = CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = { 235, 230, 245 },
		Material = "Marble",
	})
	P(model, {
		Name = "Cap",
		Size = Vector3.new(3, 0.8, 3),
		Position = base + Vector3.new(0, height + 0.4, 0),
		Color = { 220, 215, 235 },
		Material = "Marble",
	})
	Props.StarOrb(model, base + Vector3.new(0, height + 2.2, 0), 1.8, color)
	return model
end

-- Small floating island chunk.
function Props.FloatingRock(parent: Instance, center: Vector3, diameter: number, topColor, rng: Random): Model
	local model = Builder.Model(parent, "FloatingRock")
	Builder.Disc(model, center, diameter, 2, center.Y, { Name = "Top", Color = topColor, Material = "Grass" })
	Builder.Disc(
		model,
		center,
		diameter * 0.8,
		3,
		center.Y - 2,
		{ Name = "Under", Color = { 80, 70, 110 }, Material = "Rock" }
	)
	Builder.Disc(
		model,
		center,
		diameter * 0.45,
		3,
		center.Y - 5,
		{ Name = "Tip", Color = { 70, 60, 100 }, Material = "Rock" }
	)
	if rng:NextNumber() < 0.6 then
		Props.StarOrb(model, center + Vector3.new(0, 2.5, 0), 1.2, { 255, 240, 170 })
	end
	return model
end

return Props

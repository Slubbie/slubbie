-- Reusable construction helpers for building regions out of plain parts.
-- Every region is assembled from these, so new regions share one look and one set of rules.

local Builder = {}

local function rgb(c: any): Color3
	if typeof(c) == "Color3" then
		return c
	end
	return Color3.fromRGB(c[1], c[2], c[3])
end
Builder.rgb = rgb

-- An anchored part. props may include any Part property plus Color as {r,g,b}.
function Builder.Part(parent: Instance, props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	for name, value in props do
		if name == "Color" then
			part.Color = rgb(value)
		elseif name == "Material" and type(value) == "string" then
			part.Material = (Enum.Material :: any)[value]
		else
			(part :: any)[name] = value
		end
	end
	part.Parent = parent
	return part
end

function Builder.Model(parent: Instance, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

-- Flat disc lying on the ground, top surface at `top`.
function Builder.Disc(parent: Instance, center: Vector3, diameter: number, height: number, top: number, props)
	props = props or {}
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(height, diameter, diameter)
	props.CFrame = CFrame.new(center.X, top - height / 2, center.Z) * CFrame.Angles(0, 0, math.rad(90))
	return Builder.Part(parent, props)
end

-- A strip of path between two ground points.
function Builder.Path(parent: Instance, from: Vector3, to: Vector3, width: number, color, material: string?)
	local mid = (from + to) / 2
	local length = (to - from).Magnitude
	return Builder.Part(parent, {
		Name = "Path",
		Size = Vector3.new(width, 0.3, length),
		CFrame = CFrame.lookAt(Vector3.new(mid.X, from.Y + 0.1, mid.Z), Vector3.new(to.X, from.Y + 0.1, to.Z)),
		Color = color,
		Material = material or "Ground",
		CanCollide = false,
	})
end

-- Round-canopy tree. `scale` 1 is roughly 14 studs tall.
function Builder.Tree(parent: Instance, base: Vector3, scale: number, leafColor, rng: Random)
	local model = Builder.Model(parent, "Tree")
	local trunkHeight = 7 * scale
	Builder.Part(model, {
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(trunkHeight, 1.6 * scale, 1.6 * scale),
		CFrame = CFrame.new(base + Vector3.new(0, trunkHeight / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = { 110, 75, 45 },
		Material = "Wood",
	})
	local leaf = rgb(leafColor)
	for i = 1, 3 do
		local size = (7 - i) * scale * (0.9 + rng:NextNumber() * 0.25)
		local offset = Vector3.new(rng:NextNumber() * 2 - 1, 0, rng:NextNumber() * 2 - 1) * scale * 1.2
		Builder.Part(model, {
			Name = "Leaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * size,
			Position = base + Vector3.new(0, trunkHeight + i * 1.4 * scale, 0) + offset,
			Color = leaf:Lerp(Color3.new(1, 1, 0.6), (i - 1) * 0.08),
			Material = "Grass",
			CastShadow = true,
		})
	end
	return model
end

-- Lamp post with a warm light.
function Builder.Lantern(parent: Instance, base: Vector3, lightColor, height: number?)
	local model = Builder.Model(parent, "Lantern")
	local h = height or 8
	Builder.Part(model, {
		Name = "Post",
		Size = Vector3.new(0.6, h, 0.6),
		Position = base + Vector3.new(0, h / 2, 0),
		Color = { 60, 45, 35 },
		Material = "Wood",
	})
	local lamp = Builder.Part(model, {
		Name = "Lamp",
		Size = Vector3.new(1.4, 1.6, 1.4),
		Position = base + Vector3.new(0, h + 0.8, 0),
		Color = lightColor,
		Material = "Neon",
		CanCollide = false,
		CastShadow = false,
	})
	Builder.Part(model, {
		Name = "Cap",
		Size = Vector3.new(2, 0.4, 2),
		Position = base + Vector3.new(0, h + 1.8, 0),
		Color = { 50, 40, 35 },
		Material = "Metal",
	})
	local light = Instance.new("PointLight")
	light.Color = rgb(lightColor)
	light.Range = 18
	light.Brightness = 1.4
	light.Shadows = false
	light.Parent = lamp
	return model
end

-- Wooden fence from a to b with posts every ~6 studs.
function Builder.Fence(parent: Instance, a: Vector3, b: Vector3, color)
	local model = Builder.Model(parent, "Fence")
	local length = (b - a).Magnitude
	local posts = math.max(1, math.floor(length / 6))
	for i = 0, posts do
		local p = a:Lerp(b, i / posts)
		Builder.Part(model, {
			Name = "Post",
			Size = Vector3.new(0.7, 3.2, 0.7),
			Position = p + Vector3.new(0, 1.6, 0),
			Color = color,
			Material = "Wood",
		})
	end
	for _, y in { 1.2, 2.4 } do
		local mid = (a + b) / 2 + Vector3.new(0, y, 0)
		Builder.Part(model, {
			Name = "Rail",
			Size = Vector3.new(0.3, 0.35, length),
			CFrame = CFrame.lookAt(mid, (b + Vector3.new(0, y, 0))),
			Color = color,
			Material = "Wood",
		})
	end
	return model
end

-- A SurfaceGui text label on one face of a part.
function Builder.Label(part: BasePart, face: Enum.NormalId, text: string, textColor, background)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.3
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = if background then 0 else 1
	if background then
		label.BackgroundColor3 = rgb(background)
	end
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = rgb(textColor or { 255, 255, 255 })
	label.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.06, 0)
	pad.PaddingRight = UDim.new(0.06, 0)
	pad.PaddingTop = UDim.new(0.1, 0)
	pad.PaddingBottom = UDim.new(0.1, 0)
	pad.Parent = label
	return label
end

-- Signboard on two posts, facing `facing` (a direction on the ground plane).
function Builder.Sign(
	parent: Instance,
	base: Vector3,
	facing: Vector3,
	text: string,
	boardColor,
	textColor,
	width: number?
)
	local model = Builder.Model(parent, "Sign")
	local w = width or 10
	local cf = CFrame.lookAt(base, base + Vector3.new(facing.X, 0, facing.Z))
	for _, side in { -1, 1 } do
		Builder.Part(model, {
			Name = "Post",
			Size = Vector3.new(0.5, 6, 0.5),
			CFrame = cf * CFrame.new(side * (w / 2 - 0.6), 3, 0),
			Color = { 90, 60, 40 },
			Material = "Wood",
		})
	end
	local board = Builder.Part(model, {
		Name = "Board",
		Size = Vector3.new(w, 2.6, 0.4),
		CFrame = cf * CFrame.new(0, 5, 0),
		Color = boardColor,
		Material = "Wood",
	})
	Builder.Label(board, Enum.NormalId.Front, text, textColor)
	return model
end

-- Market stall with striped awning. Faces `facing`. Returns the model and the counter part.
function Builder.Stall(parent: Instance, base: Vector3, facing: Vector3, stripeA, stripeB, title: string)
	local model = Builder.Model(parent, "Stall")
	local cf = CFrame.lookAt(base, base + Vector3.new(facing.X, 0, facing.Z))
	local wood = { 150, 105, 65 }
	-- Counter
	local counter = Builder.Part(model, {
		Name = "Counter",
		Size = Vector3.new(12, 3.4, 3),
		CFrame = cf * CFrame.new(0, 1.7, -2),
		Color = wood,
		Material = "WoodPlanks",
	})
	Builder.Part(model, {
		Name = "CounterTop",
		Size = Vector3.new(12.6, 0.4, 3.6),
		CFrame = cf * CFrame.new(0, 3.6, -2),
		Color = { 110, 75, 45 },
		Material = "Wood",
	})
	-- Posts
	for _, x in { -5.8, 5.8 } do
		for _, z in { -3.6, 5 } do
			Builder.Part(model, {
				Name = "Post",
				Size = Vector3.new(0.6, 9, 0.6),
				CFrame = cf * CFrame.new(x, 4.5, z),
				Color = wood,
				Material = "Wood",
			})
		end
	end
	-- Striped awning, tilted toward the customer.
	local stripes = 6
	for i = 1, stripes do
		local x = -6 + (i - 0.5) * (12 / stripes)
		Builder.Part(model, {
			Name = "Awning",
			Size = Vector3.new(12 / stripes, 0.3, 10),
			CFrame = cf * CFrame.new(x, 9.4, 0.7) * CFrame.Angles(math.rad(-12), 0, 0),
			Color = if i % 2 == 0 then stripeA else stripeB,
			Material = "Fabric",
		})
	end
	-- Title board above the awning front.
	local board = Builder.Part(model, {
		Name = "TitleBoard",
		Size = Vector3.new(9, 1.8, 0.3),
		CFrame = cf * CFrame.new(0, 10.6, -4.6),
		Color = { 245, 235, 210 },
		Material = "Wood",
	})
	Builder.Label(board, Enum.NormalId.Front, title, { 90, 55, 30 })
	-- Back wall
	Builder.Part(model, {
		Name = "BackWall",
		Size = Vector3.new(12, 8, 0.4),
		CFrame = cf * CFrame.new(0, 4, 5.2),
		Color = { 190, 150, 105 },
		Material = "WoodPlanks",
	})
	return model, counter
end

-- A friendly blocky shopkeeper. Returns the model and its head (for prompts / labels).
function Builder.Npc(parent: Instance, base: Vector3, facing: Vector3, shirt, hat, name: string)
	local model = Builder.Model(parent, name)
	local cf = CFrame.lookAt(base, base + Vector3.new(facing.X, 0, facing.Z))
	local skin = { 255, 205, 160 }
	Builder.Part(
		model,
		{ Name = "Legs", Size = Vector3.new(2, 2.4, 1), CFrame = cf * CFrame.new(0, 1.2, 0), Color = { 70, 60, 90 } }
	)
	local torso = Builder.Part(model, {
		Name = "Torso",
		Size = Vector3.new(2.4, 2.4, 1.2),
		CFrame = cf * CFrame.new(0, 3.6, 0),
		Color = shirt,
	})
	for _, x in { -1.6, 1.6 } do
		Builder.Part(model, {
			Name = "Arm",
			Size = Vector3.new(0.8, 2.2, 0.8),
			CFrame = cf * CFrame.new(x, 3.6, 0),
			Color = shirt,
		})
	end
	local head = Builder.Part(model, {
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 2,
		CFrame = cf * CFrame.new(0, 5.8, 0),
		Color = skin,
	})
	-- Eyes and a smile so it reads as a character from a distance.
	for _, x in { -0.35, 0.35 } do
		Builder.Part(model, {
			Name = "Eye",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.25,
			CFrame = cf * CFrame.new(x, 6.0, -0.92),
			Color = { 30, 30, 40 },
			CanCollide = false,
		})
	end
	Builder.Part(model, {
		Name = "Smile",
		Size = Vector3.new(0.6, 0.12, 0.1),
		CFrame = cf * CFrame.new(0, 5.55, -0.95),
		Color = { 150, 60, 60 },
		CanCollide = false,
	})
	Builder.Part(model, {
		Name = "HatBrim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 3, 3),
		CFrame = cf * CFrame.new(0, 6.7, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = hat,
		Material = "Fabric",
	})
	Builder.Part(model, {
		Name = "HatTop",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.1, 1.8, 1.8),
		CFrame = cf * CFrame.new(0, 7.3, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = hat,
		Material = "Fabric",
	})
	model.PrimaryPart = torso
	return model, head
end

-- Decorative giant die showing `top` on its upper face (pips as neon dots).
function Builder.BigDie(parent: Instance, cf: CFrame, size: number, bodyColor, pipColor)
	local model = Builder.Model(parent, "BigDie")
	Builder.Part(model, {
		Name = "Body",
		Size = Vector3.one * size,
		CFrame = cf,
		Color = bodyColor,
		Material = "SmoothPlastic",
	})
	-- Standard layout: 1 top, 6 bottom, 2 front, 5 back, 3 right, 4 left.
	local faces = {
		{ 1, Vector3.yAxis, Vector3.xAxis, Vector3.zAxis },
		{ 6, -Vector3.yAxis, Vector3.xAxis, Vector3.zAxis },
		{ 2, -Vector3.zAxis, Vector3.xAxis, Vector3.yAxis },
		{ 5, Vector3.zAxis, Vector3.xAxis, Vector3.yAxis },
		{ 3, Vector3.xAxis, Vector3.zAxis, Vector3.yAxis },
		{ 4, -Vector3.xAxis, Vector3.zAxis, Vector3.yAxis },
	}
	local patterns = Builder.PipPatterns
	local half = size / 2
	for _, f in faces do
		for _, uv in patterns[f[1]] do
			local offset = f[2] * (half - size * 0.04) + f[3] * uv[1] * size * 0.27 + f[4] * uv[2] * size * 0.27
			Builder.Part(model, {
				Name = "Pip",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * size * 0.17,
				CFrame = cf * CFrame.new(offset),
				Color = pipColor,
				Material = "Neon",
				CanCollide = false,
				CastShadow = false,
			})
		end
	end
	return model
end

-- Pip positions per value on a face, in face-local (u, v) units of -1..1.
Builder.PipPatterns = {
	[1] = { { 0, 0 } },
	[2] = { { -1, -1 }, { 1, 1 } },
	[3] = { { -1, -1 }, { 0, 0 }, { 1, 1 } },
	[4] = { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } },
	[5] = { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 }, { 0, 0 } },
	[6] = { { -1, -1 }, { -1, 0 }, { -1, 1 }, { 1, -1 }, { 1, 0 }, { 1, 1 } },
}

-- Scatter small flowers in a circle.
function Builder.Flowers(parent: Instance, center: Vector3, radius: number, count: number, colors, rng: Random)
	local model = Builder.Model(parent, "Flowers")
	for _ = 1, count do
		local angle = rng:NextNumber() * math.pi * 2
		local r = math.sqrt(rng:NextNumber()) * radius
		local pos = center + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
		Builder.Part(model, {
			Name = "Stem",
			Size = Vector3.new(0.15, 0.8, 0.15),
			Position = pos + Vector3.new(0, 0.4, 0),
			Color = { 70, 140, 60 },
			CanCollide = false,
			CastShadow = false,
		})
		Builder.Part(model, {
			Name = "Bloom",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.6,
			Position = pos + Vector3.new(0, 0.9, 0),
			Color = colors[rng:NextInteger(1, #colors)],
			CanCollide = false,
			CastShadow = false,
		})
	end
	return model
end

function Builder.Rock(parent: Instance, pos: Vector3, size: number, color, rng: Random)
	return Builder.Part(parent, {
		Name = "Rock",
		Size = Vector3.new(size * (0.8 + rng:NextNumber() * 0.5), size * 0.6, size * (0.8 + rng:NextNumber() * 0.5)),
		CFrame = CFrame.new(pos + Vector3.new(0, size * 0.2, 0))
			* CFrame.Angles(rng:NextNumber() * 0.3, rng:NextNumber() * math.pi, rng:NextNumber() * 0.3),
		Color = color,
		Material = "Slate",
	})
end

-- A ProximityPrompt on a part.
function Builder.Prompt(part: BasePart, action: string, object: string, key: Enum.KeyCode?): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = key or Enum.KeyCode.E
	prompt.Parent = part
	return prompt
end

return Builder

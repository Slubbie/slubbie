-- Small building toolkit shared by the world builders: parts, labels,
-- lights, emitters, bridges, terrain fills and welded "moving" models.
--
-- Conventions:
--   * Everything is anchored. Walkable surfaces collide; decoration doesn't
--     (CanCollide/CanQuery/CanTouch off, no shadow when small).
--   * Models the client animates (spinning rings, bobbing crystals, swaying
--     banners) are built around one anchored Root with the rest welded to it,
--     so the client moves one part per frame. They carry a CollectionService
--     tag ("Spinner", "Bobber", "Sway") plus attributes.

local Kit = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
Kit.Textures = {
	Sparkle = SPARKLE,
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
}

Kit.Colors = {
	Marble = Color3.fromRGB(238, 233, 250),
	MarbleShade = Color3.fromRGB(206, 198, 232),
	Stone = Color3.fromRGB(178, 168, 204),
	StoneDark = Color3.fromRGB(118, 108, 150),
	Wood = Color3.fromRGB(160, 116, 92),
	WoodDark = Color3.fromRGB(112, 80, 68),
	Gold = Color3.fromRGB(255, 207, 112),
	Cyan = Color3.fromRGB(116, 229, 254),
	Lavender = Color3.fromRGB(182, 156, 255),
	Coral = Color3.fromRGB(255, 126, 152),
	Grass = Color3.fromRGB(170, 212, 140),
	Leaf = {
		Color3.fromRGB(255, 190, 214),
		Color3.fromRGB(200, 176, 255),
		Color3.fromRGB(160, 222, 196),
		Color3.fromRGB(255, 216, 160),
	},
	Flower = {
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(255, 225, 120),
		Color3.fromRGB(255, 150, 200),
		Color3.fromRGB(190, 160, 255),
		Color3.fromRGB(130, 220, 255),
	},
}

export type PartProps = {
	Name: string?,
	Shape: Enum.PartType?,
	Color: Color3?,
	Material: Enum.Material?,
	Transparency: number?,
	Reflectance: number?,
	CanCollide: boolean?,
	Decor: boolean?, -- non-colliding, non-queryable decoration
	CastShadow: boolean?,
}

function Kit.Folder(name: string, parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

function Kit.Model(name: string, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

function Kit.Part(parent: Instance, size: Vector3, cframe: CFrame, props: PartProps?): Part
	local p = props or {}
	local part = Instance.new("Part")
	part.Name = p.Name or "Part"
	if p.Shape then
		part.Shape = p.Shape
	end
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.Color = p.Color or Kit.Colors.Stone
	part.Material = p.Material or Enum.Material.SmoothPlastic
	part.Transparency = p.Transparency or 0
	part.Reflectance = p.Reflectance or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if p.Decor then
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
	else
		part.CanCollide = if p.CanCollide == nil then true else p.CanCollide
	end
	if p.CastShadow ~= nil then
		part.CastShadow = p.CastShadow
	else
		part.CastShadow = size.Magnitude > 6
	end
	part.Parent = parent
	return part
end

function Kit.Block(
	parent: Instance,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	decor: boolean?
): Part
	return Kit.Part(parent, size, cframe, { Color = color, Material = material, Decor = decor })
end

function Kit.Ball(
	parent: Instance,
	diameter: number,
	position: Vector3,
	color: Color3,
	material: Enum.Material?,
	decor: boolean?
): Part
	return Kit.Part(parent, Vector3.new(diameter, diameter, diameter), CFrame.new(position), {
		Shape = Enum.PartType.Ball,
		Color = color,
		Material = material,
		Decor = if decor == nil then true else decor,
	})
end

-- Vertical cylinder whose base centre sits at `base`.
function Kit.Column(
	parent: Instance,
	diameter: number,
	height: number,
	base: Vector3,
	color: Color3,
	material: Enum.Material?,
	decor: boolean?
): Part
	return Kit.Part(
		parent,
		Vector3.new(height, diameter, diameter),
		CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		{
			Shape = Enum.PartType.Cylinder,
			Color = color,
			Material = material,
			Decor = decor,
		}
	)
end

-- Flat disc whose top surface is at `top`.
function Kit.Disc(
	parent: Instance,
	diameter: number,
	thickness: number,
	top: Vector3,
	color: Color3,
	material: Enum.Material?,
	decor: boolean?
): Part
	return Kit.Column(parent, diameter, thickness, top - Vector3.new(0, thickness, 0), color, material, decor)
end

function Kit.Wedge(
	parent: Instance,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	decor: boolean?
): WedgePart
	local wedge = Instance.new("WedgePart")
	wedge.Size = size
	wedge.CFrame = cframe
	wedge.Anchored = true
	wedge.Color = color
	wedge.Material = material or Enum.Material.SmoothPlastic
	wedge.TopSurface = Enum.SurfaceType.Smooth
	wedge.BottomSurface = Enum.SurfaceType.Smooth
	if decor then
		wedge.CanCollide = false
		wedge.CanQuery = false
		wedge.CanTouch = false
	end
	wedge.CastShadow = size.Magnitude > 6
	wedge.Parent = parent
	return wedge
end

function Kit.Light(parent: BasePart, color: Color3, range: number, brightness: number?): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness or 1
	light.Shadows = false
	light.Parent = parent
	return light
end

function Kit.Emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLE
	emitter.LightEmission = 1
	emitter.Rate = 4
	emitter.Lifetime = NumberRange.new(1, 2)
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	for key, value in props do
		(emitter :: any)[key] = value
	end
	emitter:AddTag("WorldFX")
	emitter.Parent = parent
	return emitter
end

-- A floating text label above a part.
function Kit.Billboard(adornee: BasePart, title: string, subtitle: string?, options: { [string]: any }?): BillboardGui
	local o = options or {}
	local gui = Instance.new("BillboardGui")
	gui.Name = o.Name or "Label"
	gui.Size = UDim2.fromOffset(o.Width or 260, if subtitle then 64 else 40)
	gui.StudsOffsetWorldSpace = o.Offset or Vector3.new(0, 6, 0)
	gui.MaxDistance = o.MaxDistance or 140
	gui.LightInfluence = 0
	gui.AlwaysOnTop = o.AlwaysOnTop == true
	gui.ResetOnSpawn = false
	gui.Adornee = adornee

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.new(1, 0, 0, 34)
	titleLabel.Font = Enum.Font.FredokaOne
	titleLabel.Text = title
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = o.Color or Color3.fromRGB(245, 247, 255)
	titleLabel.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(11, 16, 40)
	stroke.Thickness = 2
	stroke.Transparency = 0.2
	stroke.Parent = titleLabel

	if subtitle then
		local sub = Instance.new("TextLabel")
		sub.Name = "Subtitle"
		sub.BackgroundTransparency = 1
		sub.Position = UDim2.fromOffset(0, 36)
		sub.Size = UDim2.new(1, 0, 0, 24)
		sub.Font = Enum.Font.BuilderSansBold
		sub.Text = subtitle
		sub.TextScaled = true
		sub.TextColor3 = o.SubColor or Color3.fromRGB(255, 207, 112)
		sub.Parent = gui
		local subStroke = stroke:Clone()
		subStroke.Parent = sub
	end
	gui.Parent = adornee
	return gui
end

-- Text painted onto a face of a part.
function Kit.Sign(part: BasePart, face: Enum.NormalId, lines: { string }, options: { [string]: any }?): SurfaceGui
	local o = options or {}
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = o.PixelsPerStud or 40
	gui.LightInfluence = o.LightInfluence or 0.2
	gui.Adornee = part
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = gui
	for i, line in lines do
		local label = Instance.new("TextLabel")
		label.Name = "Line" .. i
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(0.92, 0, if i == 1 then 0.42 else 0.22, 0)
		label.Font = if i == 1 then Enum.Font.FredokaOne else Enum.Font.BuilderSansBold
		label.TextScaled = true
		label.Text = line
		label.TextColor3 = if i == 1
			then (o.Color or Color3.fromRGB(245, 247, 255))
			else (o.SubColor or Color3.fromRGB(255, 207, 112))
		label.LayoutOrder = i
		label.Parent = gui
	end
	gui.Parent = part
	return gui
end

-- A ProximityPrompt the client turns into a UI action (attribute "Action").
function Kit.Prompt(
	part: BasePart,
	action: string,
	actionText: string,
	objectText: string,
	distance: number?
): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ActionPrompt"
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = distance or 12
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Action", action)
	prompt.Parent = part
	return prompt
end

-- Builds a set of parts welded to one anchored Root, tagged for client animation.
function Kit.Animated(
	parent: Instance,
	name: string,
	center: CFrame,
	tag: string,
	attributes: { [string]: any }
): (Model, Part)
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.5, 0.5, 0.5)
	root.CFrame = center
	root.Anchored = true
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Parent = model
	model.PrimaryPart = root
	for key, value in attributes do
		model:SetAttribute(key, value)
	end
	-- Stream as one unit so the client always gets the root with its parts.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:AddTag(tag)
	model.Parent = parent
	return model, root
end

-- Welds a decoration part to an animated root (call after positioning it).
function Kit.WeldTo(part: BasePart, root: BasePart)
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
end

-- Ring of blocks around `center` in the plane of its XZ axes.
function Kit.Ring(
	parent: Instance,
	center: CFrame,
	radius: number,
	thickness: Vector2,
	segments: number,
	color: Color3,
	material: Enum.Material?,
	decor: boolean?
): { Part }
	local parts = {}
	local step = math.pi * 2 / segments
	local length = 2 * radius * math.sin(step / 2) * 1.04
	for i = 0, segments - 1 do
		local a = i * step
		local cf = center * CFrame.new(math.cos(a) * radius, 0, math.sin(a) * radius) * CFrame.Angles(0, -a, 0)
		table.insert(
			parts,
			Kit.Block(
				parent,
				Vector3.new(thickness.X, thickness.Y, length),
				cf,
				color,
				material,
				if decor == nil then true else decor
			)
		)
	end
	return parts
end

-- A wooden bridge deck with rails, posts and lanterns from `a` to `b` (deck top heights).
function Kit.Bridge(parent: Instance, a: Vector3, b: Vector3, width: number, options: { [string]: any }?): Model
	local o = options or {}
	local model = Kit.Model(o.Name or "Bridge", parent)
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local length = (b - a).Magnitude
	local mid = (a + b) / 2
	local frame = CFrame.lookAt(mid, b)
	local deckColor = o.Color or Kit.Colors.Wood
	local deck = Kit.Part(model, Vector3.new(width, 1, length + 2), frame * CFrame.new(0, -0.5, 0), {
		Name = "Deck",
		Color = deckColor,
		Material = o.Material or Enum.Material.WoodPlanks,
		CastShadow = true,
	})
	deck:AddTag("Walkable")
	Kit.Part(model, Vector3.new(width + 1.2, 0.8, length + 2), frame * CFrame.new(0, -1.3, 0), {
		Name = "Beam",
		Color = Kit.Colors.WoodDark,
		Material = Enum.Material.Wood,
		Decor = true,
	})
	local railColor = o.RailColor or Kit.Colors.WoodDark
	for _, side in { -1, 1 } do
		Kit.Part(model, Vector3.new(0.5, 0.5, length), frame * CFrame.new(side * (width / 2 - 0.3), 3, 0), {
			Name = "Rail",
			Color = railColor,
			Material = Enum.Material.Wood,
		})
	end
	local spacing = o.PostSpacing or 16
	local count = math.max(1, math.floor(length / spacing))
	for i = 0, count do
		local t = i / count
		local z = -length / 2 + t * length
		for _, side in { -1, 1 } do
			local post =
				Kit.Part(model, Vector3.new(0.7, 4, 0.7), frame * CFrame.new(side * (width / 2 - 0.3), 1.5, -z), {
					Name = "Post",
					Color = railColor,
					Material = Enum.Material.Wood,
				})
			if i % 3 == 0 then
				local lantern = Kit.Ball(
					model,
					1.1,
					post.CFrame.Position + Vector3.new(0, 2.6, 0),
					o.LanternColor or Kit.Colors.Gold,
					Enum.Material.Neon
				)
				if i % 6 == 0 then
					Kit.Light(lantern, o.LanternColor or Kit.Colors.Gold, 14, 0.8)
				end
			end
		end
	end
	model:SetAttribute("Length", flat.Magnitude)
	return model
end

-- Terrain helpers. All terrain goes through here so tests can stub it.
Kit.Terrain = {
	Cylinder = function(center: CFrame, height: number, radius: number, material: Enum.Material)
		workspace.Terrain:FillCylinder(center, height, radius, material)
	end,
	Ball = function(center: Vector3, radius: number, material: Enum.Material)
		workspace.Terrain:FillBall(center, radius, material)
	end,
	Block = function(cframe: CFrame, size: Vector3, material: Enum.Material)
		workspace.Terrain:FillBlock(cframe, size, material)
	end,
	Color = function(material: Enum.Material, color: Color3)
		workspace.Terrain:SetMaterialColor(material, color)
	end,
}

-- A floating terrain island: flat top at `top.Y`, tapering rock underneath.
function Kit.Island(rng: Random, top: Vector3, radius: number, surface: Enum.Material?, rock: Enum.Material?)
	local rockMaterial = rock or Enum.Material.Rock
	local layers = math.clamp(math.floor(radius / 12), 4, 10)
	local depth = radius * 0.9
	for k = 1, layers do
		local t = k / layers
		local r = radius * (1 - t * 0.85) * (0.92 + rng:NextNumber() * 0.12)
		local y = top.Y - 6 - t * depth
		Kit.Terrain.Cylinder(CFrame.new(top.X, y, top.Z), depth / layers + 6, r, rockMaterial)
	end
	for _ = 1, math.floor(layers * 1.5) do
		local a = rng:NextNumber() * math.pi * 2
		local d = rng:NextNumber() * radius * 0.5
		local lumpRadius = radius * (0.12 + rng:NextNumber() * 0.12)
		local y = top.Y - depth * (0.45 + rng:NextNumber() * 0.45)
		Kit.Terrain.Ball(Vector3.new(top.X + math.cos(a) * d, y, top.Z + math.sin(a) * d), lumpRadius, rockMaterial)
	end
	Kit.Terrain.Cylinder(CFrame.new(top.X, top.Y - 9, top.Z), 6, radius * 0.985, Enum.Material.Ground)
	Kit.Terrain.Cylinder(CFrame.new(top.X, top.Y - 4, top.Z), 8, radius, surface or Enum.Material.Grass)
end

-- A puffy stylised tree: trunk plus a few overlapping canopy balls.
function Kit.Tree(parent: Instance, rng: Random, base: Vector3, scale: number?, palette: { Color3 }?)
	local s = scale or 1
	local model = Kit.Model("Tree", parent)
	local height = (7 + rng:NextNumber() * 4) * s
	local trunk =
		Kit.Column(model, 1.4 * s, height, base - Vector3.new(0, 1, 0), Kit.Colors.WoodDark, Enum.Material.Wood)
	trunk.CastShadow = true
	local colors = palette or Kit.Colors.Leaf
	local color = colors[rng:NextInteger(1, #colors)]
	local top = base + Vector3.new(0, height, 0)
	for i = 1, 3 do
		local offset = Vector3.new(
			(rng:NextNumber() - 0.5) * 4 * s,
			(rng:NextNumber() - 0.2) * 2 * s,
			(rng:NextNumber() - 0.5) * 4 * s
		)
		local ball = Kit.Ball(
			model,
			(5 + rng:NextNumber() * 3) * s,
			top + offset,
			color:Lerp(Color3.new(1, 1, 1), i * 0.06),
			Enum.Material.SmoothPlastic
		)
		ball.CastShadow = true
	end
	return model
end

-- A cluster of small flowers (non-colliding).
function Kit.Flowers(parent: Instance, rng: Random, center: Vector3, radius: number, count: number)
	for _ = 1, count do
		local a = rng:NextNumber() * math.pi * 2
		local d = math.sqrt(rng:NextNumber()) * radius
		local pos = center + Vector3.new(math.cos(a) * d, 0.5, math.sin(a) * d)
		local color = Kit.Colors.Flower[rng:NextInteger(1, #Kit.Colors.Flower)]
		Kit.Block(
			parent,
			Vector3.new(0.18, 1, 0.18),
			CFrame.new(pos),
			Color3.fromRGB(110, 170, 110),
			Enum.Material.SmoothPlastic,
			true
		)
		local bloom = Kit.Ball(parent, 0.7, pos + Vector3.new(0, 0.6, 0), color, Enum.Material.SmoothPlastic)
		bloom.CastShadow = false
	end
end

function Kit.Lantern(parent: Instance, base: Vector3, color: Color3?, withLight: boolean?): Model
	local model = Kit.Model("Lantern", parent)
	Kit.Column(model, 0.5, 6, base, Kit.Colors.StoneDark, Enum.Material.Slate)
	Kit.Block(
		model,
		Vector3.new(1.6, 0.4, 1.6),
		CFrame.new(base + Vector3.new(0, 6.1, 0)),
		Kit.Colors.StoneDark,
		Enum.Material.Slate
	)
	local glow = Kit.Ball(model, 1.3, base + Vector3.new(0, 7, 0), color or Kit.Colors.Gold, Enum.Material.Neon)
	if withLight then
		Kit.Light(glow, color or Kit.Colors.Gold, 16, 0.9)
	end
	return model
end

-- Picks well-spaced random points inside a circle, avoiding blocked circles.
function Kit.ScatterPoints(
	rng: Random,
	center: Vector3,
	radius: number,
	count: number,
	spacing: number,
	blocked: { { Position: Vector3, Radius: number } }?
): { Vector3 }
	local points: { Vector3 } = {}
	local attempts = 0
	while #points < count and attempts < count * 60 do
		attempts += 1
		local a = rng:NextNumber() * math.pi * 2
		local d = math.sqrt(rng:NextNumber()) * radius
		local p = center + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
		local ok = true
		for _, other in points do
			if (other - p).Magnitude < spacing then
				ok = false
				break
			end
		end
		if ok and blocked then
			for _, b in blocked do
				local flat = Vector3.new(b.Position.X - p.X, 0, b.Position.Z - p.Z)
				if flat.Magnitude < b.Radius then
					ok = false
					break
				end
			end
		end
		if ok then
			table.insert(points, p)
		end
	end
	return points
end

return Kit

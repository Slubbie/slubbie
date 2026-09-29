-- Tiny modelling kit used by every procedural builder (placeables, crops,
-- animals, resource nodes, tools). Models are built around a pivot at the
-- origin (ground level, centre of the footprint) and moved into place after.
--
-- Parts marked Paint (attribute) are recoloured by the player's chosen colour;
-- parts marked Mat take the chosen material.

local Kit = {}

export type Opts = {
	Material: Enum.Material?,
	Transparency: number?,
	Collide: boolean?,
	Shadow: boolean?,
	Paint: boolean?,
	Mat: boolean?,
	Name: string?,
	Reflectance: number?,
}

function Kit.Model(name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(1, 1, 1)
	base.Transparency = 1
	base.Anchored = true
	base.CanCollide = false
	base.CanQuery = false
	base.CanTouch = false
	base.CFrame = CFrame.new()
	base.Parent = model
	model.PrimaryPart = base
	return model
end

local function make(model: Model, className: string, size: Vector3, cf: CFrame, color: Color3, opts: Opts?): BasePart
	local o = opts or {}
	local p: BasePart
	if className == "Wedge" then
		p = Instance.new("WedgePart")
	elseif className == "Corner" then
		p = Instance.new("CornerWedgePart")
	else
		local part = Instance.new("Part")
		if className == "Ball" then
			part.Shape = Enum.PartType.Ball
		elseif className == "Cylinder" then
			part.Shape = Enum.PartType.Cylinder
		end
		p = part
	end
	p.Name = o.Name or className
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = o.Material or Enum.Material.SmoothPlastic
	p.Transparency = o.Transparency or 0
	p.Reflectance = o.Reflectance or 0
	p.Anchored = true
	p.CanCollide = o.Collide ~= false
	p.CanTouch = false
	p.CastShadow = o.Shadow ~= false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if o.Paint then
		p:SetAttribute("Paint", true)
	end
	if o.Mat then
		p:SetAttribute("Mat", true)
	end
	p.Parent = model
	return p
end

function Kit.Box(model: Model, size: Vector3, cf: CFrame, color: Color3, opts: Opts?): BasePart
	return make(model, "Block", size, cf, color, opts)
end

function Kit.Ball(model: Model, size: Vector3, cf: CFrame, color: Color3, opts: Opts?): BasePart
	return make(model, "Ball", size, cf, color, opts)
end

-- Cylinder standing upright (Roblox cylinders lie along X, so we rotate them).
function Kit.Cyl(model: Model, height: number, diameter: number, cf: CFrame, color: Color3, opts: Opts?): BasePart
	return make(
		model,
		"Cylinder",
		Vector3.new(height, diameter, diameter),
		cf * CFrame.Angles(0, 0, math.rad(90)),
		color,
		opts
	)
end

-- Cylinder lying along the given axis ("X" or "Z").
function Kit.CylFlat(
	model: Model,
	length: number,
	diameter: number,
	cf: CFrame,
	color: Color3,
	axis: string?,
	opts: Opts?
): BasePart
	local rot = if axis == "Z" then CFrame.Angles(0, math.rad(90), 0) else CFrame.new()
	return make(model, "Cylinder", Vector3.new(length, diameter, diameter), cf * rot, color, opts)
end

function Kit.Wedge(model: Model, size: Vector3, cf: CFrame, color: Color3, opts: Opts?): BasePart
	return make(model, "Wedge", size, cf, color, opts)
end

-- A gabled roof over a W×D rectangle whose eaves sit at height h.
function Kit.Roof(
	model: Model,
	w: number,
	d: number,
	h: number,
	rise: number,
	color: Color3,
	overhang: number?,
	opts: Opts?
)
	local o = overhang or 1
	local half = (w + o * 2) / 2
	local depth = d + o * 2
	Kit.Wedge(
		model,
		Vector3.new(depth, rise, half),
		CFrame.new(-half / 2, h + rise / 2, 0) * CFrame.Angles(0, math.rad(90), 0),
		color,
		opts
	)
	Kit.Wedge(
		model,
		Vector3.new(depth, rise, half),
		CFrame.new(half / 2, h + rise / 2, 0) * CFrame.Angles(0, math.rad(-90), 0),
		color,
		opts
	)
end

function Kit.Light(part: BasePart, color: Color3, range: number?, brightness: number?, shadows: boolean?)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range or 14
	light.Brightness = brightness or 1.2
	light.Shadows = shadows == true
	light.Parent = part
	return light
end

function Kit.Glow(part: BasePart, color: Color3)
	part.Material = Enum.Material.Neon
	part.Color = color
	part.CastShadow = false
end

-- Emitter helper for sparkles, smoke, bubbles...
function Kit.Particles(part: BasePart, kind: string, color: Color3?, rate: number?): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = kind
	e.Rate = rate or 4
	e.LightEmission = 0.4
	e.Color = ColorSequence.new(color or Color3.new(1, 1, 1))
	if kind == "Smoke" then
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Lifetime = NumberRange.new(2, 3.5)
		e.Speed = NumberRange.new(2, 3)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.4) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
		e.LightEmission = 0
		e.SpreadAngle = Vector2.new(10, 10)
		e.Acceleration = Vector3.new(0.5, 0.6, 0)
	elseif kind == "Sparkle" then
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Lifetime = NumberRange.new(0.8, 1.4)
		e.Speed = NumberRange.new(0.5, 1.5)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
		e.SpreadAngle = Vector2.new(180, 180)
		e.LightEmission = 1
	elseif kind == "Water" then
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Lifetime = NumberRange.new(0.6, 1)
		e.Speed = NumberRange.new(6, 9)
		e.Size = NumberSequence.new(0.2)
		e.SpreadAngle = Vector2.new(35, 35)
		e.Acceleration = Vector3.new(0, -25, 0)
		e.Color = ColorSequence.new(Color3.fromRGB(170, 210, 255))
		e.LightEmission = 0.2
	elseif kind == "Fire" then
		e.Texture = "rbxasset://textures/particles/fire_main.dds"
		e.Lifetime = NumberRange.new(0.4, 0.8)
		e.Speed = NumberRange.new(1, 2.5)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0.1) })
		e.Color = ColorSequence.new(Color3.fromRGB(255, 190, 80), Color3.fromRGB(255, 80, 30))
		e.LightEmission = 1
	elseif kind == "Bubbles" then
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Lifetime = NumberRange.new(0.6, 1.2)
		e.Speed = NumberRange.new(1, 2)
		e.Size = NumberSequence.new(0.25)
		e.SpreadAngle = Vector2.new(20, 20)
	end
	e.Parent = part
	return e
end

-- Interaction prompt (drawn by the client's custom prompt UI).
function Kit.Prompt(
	part: BasePart,
	kind: string,
	action: string,
	objectText: string?,
	distance: number?
): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Prompt"
	prompt.ActionText = action
	prompt.ObjectText = objectText or ""
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = distance or 10
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute("Kind", kind)
	prompt.Parent = part
	return prompt
end

-- Text on a sign face.
function Kit.Label(part: BasePart, text: string, face: Enum.NormalId?, color: Color3?, font: Enum.Font?)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Label"
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 1
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = font or Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color or Color3.fromRGB(60, 40, 25)
	label.Text = text
	label.Parent = gui
	return label
end

-- Apply the player's paint colour / material choice.
function Kit.Style(model: Model, color: Color3?, material: Enum.Material?)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if color and d:GetAttribute("Paint") then
				d.Color = color
			end
			if material and d:GetAttribute("Mat") then
				d.Material = material
			end
		end
	end
end

-- Darken/lighten a colour.
function Kit.Shade(color: Color3, amount: number): Color3
	if amount >= 0 then
		return color:Lerp(Color3.new(1, 1, 1), amount)
	end
	return color:Lerp(Color3.new(0, 0, 0), -amount)
end

Kit.C = {
	Wood = Color3.fromRGB(150, 105, 65),
	DarkWood = Color3.fromRGB(95, 65, 40),
	Plank = Color3.fromRGB(190, 145, 95),
	Stone = Color3.fromRGB(150, 150, 145),
	DarkStone = Color3.fromRGB(95, 95, 95),
	Metal = Color3.fromRGB(160, 165, 170),
	DarkMetal = Color3.fromRGB(70, 72, 78),
	Copper = Color3.fromRGB(200, 120, 70),
	Gold = Color3.fromRGB(240, 195, 70),
	Red = Color3.fromRGB(180, 55, 45),
	Cream = Color3.fromRGB(245, 238, 220),
	Leaf = Color3.fromRGB(90, 150, 70),
	DarkLeaf = Color3.fromRGB(55, 110, 55),
	Water = Color3.fromRGB(70, 150, 200),
	Glass = Color3.fromRGB(190, 225, 245),
	Straw = Color3.fromRGB(225, 195, 110),
	Soil = Color3.fromRGB(110, 80, 55),
	White = Color3.fromRGB(250, 250, 248),
	Black = Color3.fromRGB(30, 30, 32),
}

return Kit

-- Geometry kit: the primitives every district, course and room is built from.
--
-- A Builder owns a district folder with three children:
--   Core   gameplay geometry (always present for players in the district)
--   Decor  decoration the client may hide on low detail settings
--   Far    simplified silhouettes shown when you're in another district
-- Everything is anchored, smooth-surfaced and deterministic (seeded RNG), so
-- the world is identical on every server.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rotation = require(ReplicatedStorage.Shared.Logic.Rotation)
local Tags = require(ReplicatedStorage.Shared.Tags)

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

export type PartOptions = {
	Name: string?,
	Decor: boolean?,
	Far: boolean?,
	Parent: Instance?,
	Shape: Enum.PartType?,
	Transparency: number?,
	Reflectance: number?,
	CanCollide: boolean?,
	CanQuery: boolean?,
	CanTouch: boolean?,
	CastShadow: boolean?,
	Tag: string?,
	Attrs: { [string]: any }?,
	Group: string?,
	Class: string?,
}

local Kit = {}
Kit.__index = Kit

Kit.Textures = { Sparkle = SPARKLE, Smoke = SMOKE, Fire = FIRE }

export type Builder = typeof(setmetatable(
	{} :: {
		Root: Folder,
		Core: Folder,
		Decor: Folder,
		Far: Folder,
		District: string,
		Palette: { [string]: Color3 },
		Rng: Rotation.Rng,
		Parts: number,
		Current: Instance?,
	},
	Kit
))

function Kit.new(parent: Instance, districtId: string, palette: { [string]: Color3 }, seed: number?): Builder
	local root = Instance.new("Folder")
	root.Name = districtId
	root:SetAttribute("District", districtId)
	local core = Instance.new("Folder")
	core.Name = "Core"
	core.Parent = root
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = root
	local far = Instance.new("Folder")
	far.Name = "Far"
	far.Parent = root
	root.Parent = parent
	return setmetatable({
		Root = root,
		Core = core,
		Decor = decor,
		Far = far,
		District = districtId,
		Palette = palette,
		Rng = Rotation.Rng(seed or Rotation.Hash(districtId)),
		Parts = 0,
		Current = nil,
	}, Kit)
end

-- Group subsequent Core parts under a named folder (e.g. one per course).
function Kit.Group(self: Builder, name: string, parent: Instance?): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent or self.Core
	return folder
end

function Kit.Within(self: Builder, container: Instance?, fn: () -> ())
	local previous = self.Current
	self.Current = container
	fn()
	self.Current = previous
end

-- Primitives --------------------------------------------------------------------------

function Kit.Part(
	self: Builder,
	cframe: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	options: PartOptions?
): BasePart
	local o = options or {}
	local part = Instance.new((o.Class or "Part") :: any) :: BasePart
	part.Name = o.Name or "Part"
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if o.Shape and part:IsA("Part") then
		part.Shape = o.Shape
	end
	if o.Transparency then
		part.Transparency = o.Transparency
	end
	if o.Reflectance then
		part.Reflectance = o.Reflectance
	end
	if o.CanCollide ~= nil then
		part.CanCollide = o.CanCollide
	end
	if o.CanQuery ~= nil then
		part.CanQuery = o.CanQuery
	end
	if o.CanTouch ~= nil then
		part.CanTouch = o.CanTouch
	end
	local small = size.X * size.Y * size.Z < 60
	if o.CastShadow ~= nil then
		part.CastShadow = o.CastShadow
	elseif o.Decor and small then
		part.CastShadow = false
	end
	if o.Decor then
		-- Decoration never blocks movement queries in surprising ways.
		if o.CanCollide == nil and small then
			part.CanCollide = false
		end
		part.CanTouch = false
	end
	if o.Group then
		part.CollisionGroup = o.Group
	end
	if o.Attrs then
		for key, value in o.Attrs do
			part:SetAttribute(key, value)
		end
	end
	if o.Tag then
		CollectionService:AddTag(part, o.Tag)
	end
	part.Parent = o.Parent or (if o.Far then self.Far elseif o.Decor then self.Decor else (self.Current or self.Core))
	self.Parts += 1
	return part
end

function Kit.Box(
	self: Builder,
	cframe: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	options: PartOptions?
): BasePart
	return self:Part(cframe, size, color, material, options)
end

function Kit.Detail(
	self: Builder,
	cframe: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	options: PartOptions?
): BasePart
	local o = table.clone(options or {})
	o.Decor = true
	return self:Part(cframe, size, color, material, o)
end

function Kit.Wedge(
	self: Builder,
	cframe: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	options: PartOptions?
): BasePart
	local o = table.clone(options or {})
	o.Class = "WedgePart"
	return self:Part(cframe, size, color, material, o)
end

function Kit.Ball(
	self: Builder,
	position: Vector3,
	diameter: number,
	color: Color3,
	material: Enum.Material?,
	options: PartOptions?
): BasePart
	local o = table.clone(options or {})
	o.Shape = Enum.PartType.Ball
	return self:Part(CFrame.new(position), Vector3.one * diameter, color, material, o)
end

-- Cylinder whose axis runs along the CFrame's X axis (Roblox convention).
function Kit.Cylinder(
	self: Builder,
	cframe: CFrame,
	length: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?,
	options: PartOptions?
): BasePart
	local o = table.clone(options or {})
	o.Shape = Enum.PartType.Cylinder
	return self:Part(cframe, Vector3.new(length, diameter, diameter), color, material, o)
end

-- Upright cylinder (axis vertical) standing on `base`.
function Kit.Column(
	self: Builder,
	base: Vector3,
	height: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?,
	options: PartOptions?
): BasePart
	local cframe = CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	return self:Cylinder(cframe, height, diameter, color, material, options)
end

-- Cylinder from point a to point b.
function Kit.Rod(
	self: Builder,
	a: Vector3,
	b: Vector3,
	diameter: number,
	color: Color3,
	material: Enum.Material?,
	options: PartOptions?
): BasePart
	local offset = b - a
	local length = math.max(offset.Magnitude, 0.05)
	local up = if length > 0.05 and math.abs(offset.Unit.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
	local cframe = CFrame.lookAt((a + b) / 2, b, up) * CFrame.Angles(0, math.rad(90), 0)
	return self:Cylinder(cframe, length, diameter, color, material, options)
end

-- Box spanning from a to b (thin beam).
function Kit.Beam(
	self: Builder,
	a: Vector3,
	b: Vector3,
	width: number,
	height: number,
	color: Color3,
	material: Enum.Material?,
	options: PartOptions?
): BasePart
	local offset = b - a
	local length = math.max(offset.Magnitude, 0.05)
	local up = if math.abs(offset.Unit.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis
	local cframe = CFrame.lookAt((a + b) / 2, b, up)
	return self:Part(cframe, Vector3.new(width, height, length), color, material, options)
end

-- Silhouette for distant viewing.
function Kit.FarBox(self: Builder, cframe: CFrame, size: Vector3, color: Color3, material: Enum.Material?)
	return self:Part(
		cframe,
		size,
		color,
		material,
		{ Far = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
	)
end

-- Decoration helpers ---------------------------------------------------------------------

function Kit.Light(
	self: Builder,
	part: BasePart,
	color: Color3,
	range: number,
	brightness: number?,
	kind: string?,
	face: Enum.NormalId?
): Light
	local light: Light
	if kind == "Spot" then
		local spot = Instance.new("SpotLight")
		spot.Face = face or Enum.NormalId.Bottom
		spot.Angle = 70
		spot.Range = range
		light = spot
	elseif kind == "Surface" then
		local surface = Instance.new("SurfaceLight")
		surface.Face = face or Enum.NormalId.Front
		surface.Angle = 80
		surface.Range = range
		light = surface
	else
		local point = Instance.new("PointLight")
		point.Range = range
		light = point
	end
	light.Color = color
	light.Brightness = brightness or 1
	light.Shadows = false
	light.Parent = part
	return light
end

function Kit.Text(
	self: Builder,
	part: BasePart,
	face: Enum.NormalId,
	text: string,
	options: { [string]: any }?
): SurfaceGui
	local o = options or {}
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = o.PixelsPerStud or 24
	gui.LightInfluence = o.LightInfluence or 0.2
	gui.MaxDistance = o.MaxDistance or 260
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = if o.Background then 0 else 1
	label.BackgroundColor3 = o.Background or Color3.new(0, 0, 0)
	label.Text = text
	label.TextColor3 = o.Color or Color3.new(1, 1, 1)
	label.Font = o.Font or Enum.Font.GothamBold
	label.TextScaled = true
	label.TextWrapped = true
	label.RichText = o.Rich == true
	label.TextStrokeTransparency = o.Stroke or 1
	label.Parent = gui
	if o.Padding then
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, o.Padding)
		padding.PaddingRight = UDim.new(0, o.Padding)
		padding.PaddingTop = UDim.new(0, o.Padding)
		padding.PaddingBottom = UDim.new(0, o.Padding)
		padding.Parent = label
	end
	gui.Parent = part
	return gui
end

-- Accessibility icon: a shape glyph above an interactive surface, so nothing
-- relies on colour alone. Clients show them according to the player's setting.
function Kit.Icon(self: Builder, part: BasePart, glyph: string, color: Color3, offset: Vector3?, size: number?)
	local gui = Instance.new("BillboardGui")
	gui.Name = "SurfaceIcon"
	gui.Size = UDim2.fromOffset(size or 34, size or 34)
	gui.StudsOffsetWorldSpace = offset or Vector3.new(0, 2.5, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 70
	gui.AlwaysOnTop = false
	gui.Enabled = false
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
	label.BackgroundTransparency = 0.25
	label.TextColor3 = color
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = glyph
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 2
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = part
	CollectionService:AddTag(gui, Tags.SurfaceIcon)
	return gui
end

function Kit.Prompt(
	self: Builder,
	part: BasePart,
	action: string,
	object: string,
	options: { [string]: any }?
): ProximityPrompt
	local o = options or {}
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.MaxActivationDistance = o.Distance or 12
	prompt.HoldDuration = o.Hold or 0
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.Style = Enum.ProximityPromptStyle.Default
	if o.Name then
		prompt.Name = o.Name
	end
	if o.Attrs then
		for key, value in o.Attrs do
			prompt:SetAttribute(key, value)
		end
	end
	prompt.Parent = part
	return prompt
end

function Kit.Emitter(self: Builder, parent: Instance, preset: string, color: Color3?): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	local tint = color or Color3.new(1, 1, 1)
	emitter.Color = ColorSequence.new(tint)
	emitter.LightInfluence = 0.6
	if preset == "Steam" then
		emitter.Texture = SMOKE
		emitter.Rate = 0
		emitter.Lifetime = NumberRange.new(1, 1.6)
		emitter.Speed = NumberRange.new(26, 34)
		emitter.SpreadAngle = Vector2.new(8, 8)
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 7) })
		emitter.Transparency =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
		emitter.Drag = 1.5
	elseif preset == "Smoke" then
		emitter.Texture = SMOKE
		emitter.Rate = 3
		emitter.Lifetime = NumberRange.new(5, 8)
		emitter.Speed = NumberRange.new(4, 7)
		emitter.SpreadAngle = Vector2.new(10, 10)
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 14) })
		emitter.Transparency =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
		emitter.Acceleration = Vector3.new(2, 1, 0)
	elseif preset == "Sparks" then
		emitter.Texture = SPARKLE
		emitter.LightEmission = 1
		emitter.Rate = 6
		emitter.Lifetime = NumberRange.new(0.4, 0.9)
		emitter.Speed = NumberRange.new(8, 14)
		emitter.SpreadAngle = Vector2.new(35, 35)
		emitter.Acceleration = Vector3.new(0, -60, 0)
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	elseif preset == "Mist" then
		emitter.Texture = SMOKE
		emitter.Rate = 4
		emitter.Lifetime = NumberRange.new(3, 5)
		emitter.Speed = NumberRange.new(2, 5)
		emitter.SpreadAngle = Vector2.new(60, 20)
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 12) })
		emitter.Transparency =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	elseif preset == "Falls" then
		emitter.Texture = SMOKE
		emitter.Rate = 30
		emitter.Lifetime = NumberRange.new(1.2, 1.8)
		emitter.Speed = NumberRange.new(2, 4)
		emitter.SpreadAngle = Vector2.new(15, 5)
		emitter.Acceleration = Vector3.new(0, -70, 0)
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 6) })
		emitter.Transparency =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.9) })
	elseif preset == "Updraft" then
		emitter.Texture = SPARKLE
		emitter.LightEmission = 1
		emitter.Rate = 14
		emitter.Lifetime = NumberRange.new(1.5, 2.5)
		emitter.Speed = NumberRange.new(14, 22)
		emitter.SpreadAngle = Vector2.new(10, 10)
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	elseif preset == "Motes" then
		emitter.Texture = SPARKLE
		emitter.LightEmission = 1
		emitter.Rate = 3
		emitter.Lifetime = NumberRange.new(2, 4)
		emitter.Speed = NumberRange.new(0.5, 1.5)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
	elseif preset == "Fire" then
		emitter.Texture = FIRE
		emitter.LightEmission = 0.8
		emitter.Rate = 12
		emitter.Lifetime = NumberRange.new(0.6, 1.1)
		emitter.Speed = NumberRange.new(2, 4)
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0) })
	else -- Glow
		emitter.Texture = SPARKLE
		emitter.LightEmission = 1
		emitter.Rate = 2
		emitter.Lifetime = NumberRange.new(1, 2)
		emitter.Speed = NumberRange.new(0, 0.5)
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
	end
	emitter.Parent = parent
	return emitter
end

-- Gameplay markers -------------------------------------------------------------------------

function Kit.Tag(self: Builder, instance: Instance, tag: string, attrs: { [string]: any }?)
	CollectionService:AddTag(instance, tag)
	if attrs then
		for key, value in attrs do
			instance:SetAttribute(key, value)
		end
	end
end

-- Invisible trigger volume.
function Kit.Volume(self: Builder, cframe: CFrame, size: Vector3, tag: string, attrs: { [string]: any }?): BasePart
	return self:Part(cframe, size, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, {
		Name = tag,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Tag = tag,
		Attrs = attrs,
	})
end

-- Named point for quests, NPCs and contracts.
function Kit.Point(self: Builder, tag: string, id: string, position: Vector3, attrs: { [string]: any }?): BasePart
	local a = attrs and table.clone(attrs) or {}
	a.Id = id
	a.District = self.District
	return self:Part(CFrame.new(position), Vector3.new(2, 2, 2), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, {
		Name = id,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Tag = tag,
		Attrs = a,
	})
end

-- Random helpers (deterministic) ----------------------------------------------------------

function Kit.Rand(self: Builder, lo: number, hi: number): number
	return lo + (hi - lo) * self.Rng:Next()
end

function Kit.RandInt(self: Builder, lo: number, hi: number): number
	return self.Rng:Int(lo, hi)
end

function Kit.Pick<T>(self: Builder, list: { T }): T
	return list[self.Rng:Int(1, #list)]
end

function Kit.Vary(self: Builder, color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v + (self.Rng:Next() - 0.5) * amount, 0, 1))
end

return Kit

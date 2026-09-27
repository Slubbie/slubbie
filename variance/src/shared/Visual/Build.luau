-- Part-building helpers shared by the server (rooms, tables, the lobby) and the
-- client (cells, instrument props, previews). Everything in VARIANCE is built
-- from primitives, so the game needs no uploaded meshes to run.

local Build = {}

function Build.rgb(t: { number }?, fallback: Color3?): Color3
	if t == nil then
		return fallback or Color3.new(1, 0, 1)
	end
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function material(name: any): Enum.Material
	if typeof(name) == "EnumItem" then
		return name
	end
	local ok, value = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	if ok and value then
		return value
	end
	return Enum.Material.SmoothPlastic
end
Build.material = material

export type PartProps = {
	Name: string?,
	Size: Vector3?,
	CFrame: CFrame?,
	Color: Color3?,
	Material: any?,
	Shape: Enum.PartType?,
	Transparency: number?,
	Reflectance: number?,
	CanCollide: boolean?,
	CanQuery: boolean?,
	CastShadow: boolean?,
	Anchored: boolean?,
	Parent: Instance?,
}

-- Creates an anchored, non-colliding part (the default for decoration).
function Build.part(props: PartProps): BasePart
	local p = Instance.new("Part")
	p.Name = props.Name or "Part"
	p.Anchored = if props.Anchored == nil then true else props.Anchored
	p.CanCollide = props.CanCollide == true
	p.CanQuery = props.CanQuery == true
	p.CanTouch = false
	p.CastShadow = if props.CastShadow == nil then true else props.CastShadow
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props.Shape then
		p.Shape = props.Shape
	end
	p.Size = props.Size or Vector3.one
	p.CFrame = props.CFrame or CFrame.identity
	p.Color = props.Color or Color3.fromRGB(120, 120, 120)
	p.Material = material(props.Material or "SmoothPlastic")
	p.Transparency = props.Transparency or 0
	p.Reflectance = props.Reflectance or 0
	if props.Parent then
		p.Parent = props.Parent
	end
	return p
end

function Build.box(parent: Instance, size: Vector3, cf: CFrame, color: Color3, mat: any?, name: string?): BasePart
	return Build.part({ Name = name, Size = size, CFrame = cf, Color = color, Material = mat, Parent = parent })
end

-- Solid box you can walk on / bump into.
function Build.solid(parent: Instance, size: Vector3, cf: CFrame, color: Color3, mat: any?, name: string?): BasePart
	return Build.part({
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Material = mat,
		CanCollide = true,
		CanQuery = true,
		Parent = parent,
	})
end

-- Cylinder whose axis runs along the CFrame's X axis (Roblox convention).
function Build.cylinder(
	parent: Instance,
	length: number,
	diameter: number,
	cf: CFrame,
	color: Color3,
	mat: any?,
	name: string?
): BasePart
	return Build.part({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(length, diameter, diameter),
		CFrame = cf,
		Color = color,
		Material = mat,
		Parent = parent,
	})
end

-- Cylinder standing upright (axis along world Y at the given position).
function Build.column(
	parent: Instance,
	height: number,
	diameter: number,
	at: CFrame,
	color: Color3,
	mat: any?,
	name: string?
): BasePart
	return Build.cylinder(parent, height, diameter, at * CFrame.Angles(0, 0, math.pi / 2), color, mat, name)
end

function Build.ball(parent: Instance, diameter: number, cf: CFrame, color: Color3, mat: any?, name: string?): BasePart
	return Build.part({
		Name = name,
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * diameter,
		CFrame = cf,
		Color = color,
		Material = mat,
		Parent = parent,
	})
end

function Build.wedge(parent: Instance, size: Vector3, cf: CFrame, color: Color3, mat: any?, name: string?): BasePart
	local w = Instance.new("WedgePart")
	w.Name = name or "Wedge"
	w.Anchored = true
	w.CanCollide = false
	w.CanQuery = false
	w.CanTouch = false
	w.Size = size
	w.CFrame = cf
	w.Color = color
	w.Material = material(mat or "SmoothPlastic")
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	w.Parent = parent
	return w
end

function Build.neon(parent: Instance, size: Vector3, cf: CFrame, color: Color3, name: string?): BasePart
	local p = Build.part({
		Name = name or "Neon",
		Size = size,
		CFrame = cf,
		Color = color,
		Material = "Neon",
		Parent = parent,
	})
	p.CastShadow = false
	return p
end

function Build.model(name: string, parent: Instance?): Model
	local m = Instance.new("Model")
	m.Name = name
	if parent then
		m.Parent = parent
	end
	return m
end

function Build.folder(name: string, parent: Instance?): Folder
	local f = Instance.new("Folder")
	f.Name = name
	if parent then
		f.Parent = parent
	end
	return f
end

-- Welds `part` to `to` keeping the current offset (for unanchored assemblies).
function Build.weld(part: BasePart, to: BasePart): WeldConstraint
	local w = Instance.new("WeldConstraint")
	w.Part0 = to
	w.Part1 = part
	w.Parent = part
	return w
end

function Build.pointLight(
	parent: Instance,
	color: Color3,
	brightness: number,
	range: number,
	shadows: boolean?
): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Shadows = shadows == true
	l.Parent = parent
	return l
end

function Build.spotLight(
	parent: Instance,
	color: Color3,
	brightness: number,
	range: number,
	angle: number,
	face: Enum.NormalId?,
	shadows: boolean?
): SpotLight
	local l = Instance.new("SpotLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Angle = angle
	l.Face = face or Enum.NormalId.Bottom
	l.Shadows = shadows == true
	l.Parent = parent
	return l
end

-- A SurfaceGui with a single label (signs, monitors, plaques).
function Build.label(
	part: BasePart,
	face: Enum.NormalId,
	text: string,
	color: Color3,
	props: { [string]: any }?
): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = (props and props.PixelsPerStud) or 40
	gui.LightInfluence = (props and props.LightInfluence) or 0
	gui.Brightness = (props and props.Brightness) or 1.4
	gui.ClipsDescendants = true
	gui.AlwaysOnTop = false
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.Font = (props and props.Font) or Enum.Font.Code
	label.TextXAlignment = (props and props.XAlign) or Enum.TextXAlignment.Center
	label.TextYAlignment = (props and props.YAlign) or Enum.TextYAlignment.Center
	label.RichText = true
	label.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.05, 0)
	pad.PaddingRight = UDim.new(0.05, 0)
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.PaddingBottom = UDim.new(0.08, 0)
	pad.Parent = label
	return label
end

function Build.attachment(parent: BasePart, name: string, cf: CFrame?): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = cf or CFrame.identity
	a.Parent = parent
	return a
end

-- Marks a part for client effects (flicker, warning, monitor, spin, ...).
function Build.fx(instance: Instance, kind: string, attrs: { [string]: any }?): Instance
	instance:SetAttribute("Fx", kind)
	if attrs then
		for k, v in attrs do
			instance:SetAttribute(k, v)
		end
	end
	return instance
end

-- Sets every BasePart in a model to CanCollide/CanQuery false (decoration).
function Build.ghost(model: Instance)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
end

-- Recolours parts whose name matches a key in `map` ({ Body = Color3, ... }).
function Build.paint(model: Instance, map: { [string]: Color3 })
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local tag = d:GetAttribute("Paint")
			if tag and map[tag] then
				d.Color = map[tag]
			end
		end
	end
end

return Build

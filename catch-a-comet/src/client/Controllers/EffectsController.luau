-- Reusable world effects (client-only, cosmetic): shockwave rings, particle
-- bursts, light flashes, floating reward text and light pillars. Parts are
-- pooled and particle counts scale with the graphics preset. Nothing here
-- affects gameplay.

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local EffectsController = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local controllers: { [string]: any } = {}
local folder: Folder
local ringPool: { BasePart } = {}
local burstPart: BasePart
local burstEmitters: { [string]: ParticleEmitter } = {}

local function quality(): { [string]: any }
	return controllers.SettingsController.Quality()
end

local function newPart(name: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = folder
	return part
end

-- An expanding flat ring on the ground.
function EffectsController.Shockwave(position: Vector3, color: Color3, radius: number, duration: number?)
	local ring: Part
	if #ringPool > 0 then
		ring = table.remove(ringPool) :: Part
	else
		ring = newPart("Shockwave")
		ring.Shape = Enum.PartType.Cylinder
		ring.Material = Enum.Material.Neon
	end
	ring.Color = color
	ring.Transparency = 0.15
	ring.Size = Vector3.new(0.3, 1, 1)
	ring.CFrame = CFrame.new(position + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = folder
	local time = duration or 0.6
	local tween = TweenService:Create(ring, TweenInfo.new(time, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, radius * 2, radius * 2),
		Transparency = 1,
	})
	tween:Play()
	tween.Completed:Once(function()
		ring.Parent = nil
		table.insert(ringPool, ring)
	end)
end

local function emitter(name: string, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Enabled = false
	e.LightEmission = 1
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = burstPart
	burstEmitters[name] = e
	return e
end

-- A one-shot particle burst. kind: "Sparks" | "Dust" | "Stars"
function EffectsController.Burst(position: Vector3, color: Color3, count: number, kind: string?)
	local e = burstEmitters[kind or "Sparks"]
	if not e then
		return
	end
	burstPart.Position = position
	e.Color = ColorSequence.new(color, color:Lerp(Color3.new(1, 1, 1), 0.5))
	e:Emit(math.max(1, math.floor(count * quality().Particles)))
end

-- A short bright light at a position.
function EffectsController.Flash(position: Vector3, color: Color3, brightness: number, range: number, duration: number)
	if controllers.SettingsController.ReducedMotion() then
		brightness *= 0.4
	end
	local holder = newPart("Flash")
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.Position = position
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = holder
	TweenService
		:Create(light, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 })
		:Play()
	Debris:AddItem(holder, duration + 0.1)
end

-- Rising text in the world ("+30 ✦").
function EffectsController.FloatingText(position: Vector3, text: string, color: Color3)
	local anchor = newPart("FloatingText")
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 50)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(11, 16, 40)
	stroke.Thickness = 2.5
	stroke.Parent = label
	TweenService:Create(
		gui,
		TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffsetWorldSpace = Vector3.new(0, 4, 0) }
	):Play()
	TweenService
		:Create(label, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 })
		:Play()
	TweenService
		:Create(stroke, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 })
		:Play()
	Debris:AddItem(anchor, 1.5)
end

-- A vertical light pillar (beam) rising from a point. Returns the parts to clean up.
function EffectsController.Pillar(position: Vector3, color: Color3, height: number, width: number): BasePart
	local base = newPart("Pillar")
	base.Transparency = 1
	base.Size = Vector3.new(0.2, 0.2, 0.2)
	base.Position = position
	local a0 = Instance.new("Attachment")
	a0.Parent = base
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, height, 0)
	a1.Parent = base
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = width
	beam.Width1 = width * 2.4
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Color = ColorSequence.new(color)
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(0.6, 0.75),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.Segments = 2
	beam.Parent = base
	return base
end

function EffectsController.Folder(): Folder
	return folder
end

function EffectsController.Init(registry: { [string]: any })
	controllers = registry
	folder = Instance.new("Folder")
	folder.Name = "ClientEffects"
	folder.Parent = workspace
	burstPart = newPart("BurstEmitter")
	burstPart.Transparency = 1
	burstPart.Size = Vector3.new(1, 1, 1)
	emitter("Sparks", {
		Texture = SPARKLE,
		Lifetime = NumberRange.new(0.5, 1.1),
		Speed = NumberRange.new(10, 22),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 4,
		Acceleration = Vector3.new(0, -10, 0),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
	})
	emitter("Dust", {
		Texture = SMOKE,
		LightEmission = 0.2,
		Lifetime = NumberRange.new(1, 1.8),
		Speed = NumberRange.new(6, 12),
		SpreadAngle = Vector2.new(180, 10),
		Drag = 3,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }),
		EmissionDirection = Enum.NormalId.Top,
	})
	emitter("Stars", {
		Texture = SPARKLE,
		Lifetime = NumberRange.new(1, 1.8),
		Speed = NumberRange.new(3, 8),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 2,
		Acceleration = Vector3.new(0, 3, 0),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0) }),
		RotSpeed = NumberRange.new(-90, 90),
	})
end

function EffectsController.Start() end

return EffectsController

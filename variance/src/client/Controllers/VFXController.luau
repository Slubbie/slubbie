-- Visual effects, all client-side and built from primitives plus the particle
-- textures that ship with every Roblox client.
--
-- Everything is pooled: flash balls, arc segments and rings are recycled parts
-- in one folder, and particles come from a handful of emitters that are moved
-- and told to Emit(n) (no per-effect instance churn). Counts scale with the
-- graphics quality; Reduced Flashing caps light bursts and screen flashes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Build = require(ReplicatedStorage.Variance.Visual.Build)

local VFXController = {}

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

local folder: Folder
local pool: { BasePart } = {}
local emitterPart: BasePart
local emitters: { [string]: ParticleEmitter } = {}
local screen: Frame? = nil

function VFXController:Init(controllers)
	self.Controllers = controllers
end

local function qualityScale(): number
	local env = VFXController.Controllers.EnvironmentController
	local q = env and env:quality() or "High"
	return ({ Low = 0.3, Medium = 0.6, High = 1, Ultra = 1.35 })[q] or 1
end

local function reducedFlashing(): boolean
	return VFXController.Controllers.SettingsController:get("ReducedFlashing") == true
end

---------------------------------------------------------------------------
-- Pools
---------------------------------------------------------------------------

local function take(shape: Enum.PartType?): BasePart
	local part = table.remove(pool)
	if part == nil then
		part = Build.part({ Name = "Fx", CastShadow = false, Parent = folder })
	end
	local p = part :: Part
	p.Shape = shape or Enum.PartType.Block
	p.Transparency = 0
	p.Material = Enum.Material.Neon
	p.Parent = folder
	return p
end

local function give(part: BasePart)
	part.Parent = nil
	for _, child in part:GetChildren() do
		child:Destroy()
	end
	if #pool < 80 then
		table.insert(pool, part)
	else
		part:Destroy()
	end
end

local function emitter(name: string, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Enabled = false
	e.LightInfluence = 0
	for k, v in props do
		(e :: any)[k] = v
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Parent = emitterPart
	e.Parent = attachment
	emitters[name] = e
	return e
end

-- Emits `count` particles from `name` at `cf` (scaled by quality).
local function emit(name: string, cf: CFrame, count: number, color: Color3?)
	local e = emitters[name]
	if e == nil then
		return
	end
	local n = math.max(1, math.floor(count * qualityScale() + 0.5))
	local attachment = e.Parent :: Attachment
	attachment.WorldCFrame = cf
	if color then
		e.Color = ColorSequence.new(color)
	end
	e:Emit(n)
end

---------------------------------------------------------------------------
-- Primitives
---------------------------------------------------------------------------

-- Expanding, fading neon ball with a light burst.
function VFXController:flash(position: Vector3, color: Color3, size: number?, duration: number?, brightness: number?)
	local d = duration or 0.25
	local s = size or 1
	local ball = take(Enum.PartType.Ball)
	ball.Color = color
	ball.Size = Vector3.one * s * 0.35
	ball.CFrame = CFrame.new(position)
	ball.Transparency = 0.05
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 10 * s
	light.Brightness = (brightness or 6) * (if reducedFlashing() then 0.35 else 1)
	light.Shadows = false
	light.Parent = ball
	TweenService:Create(ball, TweenInfo.new(d, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * s, Transparency = 1 }):Play()
	TweenService:Create(light, TweenInfo.new(d * 1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
	task.delay(d * 1.7, give, ball)
end

function VFXController:sparks(position: Vector3, direction: Vector3?, color: Color3?, count: number?)
	local dir = direction or Vector3.new(0, 1, 0)
	local cf = CFrame.lookAt(position, position + dir) * CFrame.Angles(-math.pi / 2, 0, 0)
	emit("Spark", cf, count or 18, color or Color3.fromRGB(255, 200, 120))
end

function VFXController:smoke(position: Vector3, amount: number?, color: Color3?)
	emit("Smoke", CFrame.new(position), amount or 6, color or Color3.fromRGB(120, 118, 115))
end

function VFXController:motes(position: Vector3, color: Color3, count: number?)
	emit("Mote", CFrame.new(position), count or 14, color)
end

function VFXController:embers(position: Vector3, count: number?)
	emit("Ember", CFrame.new(position), count or 8)
end

-- Jagged electric arc between two points that flickers for `duration`.
function VFXController:arc(from: Vector3, to: Vector3, color: Color3?, duration: number?, thickness: number?)
	local c = color or Color3.fromRGB(255, 190, 110)
	local d = duration or 0.35
	local w = thickness or 0.07
	local segments = math.clamp(math.floor((to - from).Magnitude / 0.6), 3, 10)
	local parts = {}
	for _ = 1, segments do
		local p = take()
		p.Color = c
		p.Transparency = 0
		table.insert(parts, p)
	end
	task.spawn(function()
		local start = os.clock()
		while os.clock() - start < d do
			local previous = from
			local axis = to - from
			for i, p in parts do
				local t = i / segments
				local point = from + axis * t
				if i < segments then
					local jitter = 0.35 * math.sin(t * math.pi)
					point += Vector3.new((math.random() - 0.5) * jitter, (math.random() - 0.5) * jitter, (math.random() - 0.5) * jitter)
				end
				local length = (point - previous).Magnitude
				p.Size = Vector3.new(w, w, length)
				p.CFrame = CFrame.lookAt((previous + point) / 2, point)
				p.Transparency = math.random() < 0.15 and 1 or (os.clock() - start) / d * 0.7
				previous = point
			end
			task.wait(0.045)
		end
		for _, p in parts do
			give(p)
		end
	end)
end

-- Flat expanding ring (sonar pings, shockwaves). `cf` faces its normal along +Y.
function VFXController:ring(cf: CFrame, color: Color3, radius: number, duration: number?, thickness: number?)
	local d = duration or 0.8
	local p = take(Enum.PartType.Cylinder)
	p.Color = color
	p.Material = Enum.Material.ForceField
	p.Transparency = 0.1
	p.Size = Vector3.new(thickness or 0.05, 0.2, 0.2)
	p.CFrame = cf * CFrame.Angles(0, 0, math.pi / 2)
	TweenService:Create(p, TweenInfo.new(d, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(thickness or 0.05, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
	task.delay(d + 0.05, give, p)
end

-- A shimmering sphere that stays until handle.stop() (Dampener field).
function VFXController:bubble(getCenter: () -> Vector3?, color: Color3, radius: number)
	local p = take(Enum.PartType.Ball)
	p.Color = color
	p.Material = Enum.Material.ForceField
	p.Transparency = 1
	p.Size = Vector3.one * 0.5
	local alive = true
	local handle = {}
	TweenService:Create(p, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.one * radius * 2, Transparency = 0.25 }):Play()
	task.spawn(function()
		while alive do
			local c = getCenter()
			if c then
				p.CFrame = CFrame.new(c) * CFrame.Angles(0, os.clock() * 0.6, 0)
			end
			task.wait()
		end
	end)
	-- Pop: the field absorbing a hit.
	function handle.pop()
		if not alive then
			return
		end
		alive = false
		VFXController:flash(p.Position, color, radius * 2.2, 0.3, 3)
		TweenService:Create(p, TweenInfo.new(0.25), { Size = Vector3.one * radius * 2.6, Transparency = 1 }):Play()
		task.delay(0.3, give, p)
	end
	function handle.stop()
		if not alive then
			return
		end
		alive = false
		TweenService:Create(p, TweenInfo.new(0.4), { Transparency = 1, Size = Vector3.one * radius * 1.6 }):Play()
		task.delay(0.45, give, p)
	end
	return handle
end

-- A glowing beam between two moving points until handle.stop() (Tether).
function VFXController:link(getA: () -> Vector3?, getB: () -> Vector3?, color: Color3)
	local a, b = take(), take()
	a.Transparency, b.Transparency = 1, 1
	a.Size, b.Size = Vector3.one * 0.1, Vector3.one * 0.1
	local att0 = Instance.new("Attachment")
	att0.Parent = a
	local att1 = Instance.new("Attachment")
	att1.Parent = b
	local beam = Instance.new("Beam")
	beam.Attachment0 = att0
	beam.Attachment1 = att1
	beam.Color = ColorSequence.new(color)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Width0 = 0.12
	beam.Width1 = 0.12
	beam.CurveSize0 = 1.2
	beam.CurveSize1 = -1.2
	beam.Segments = 24
	beam.FaceCamera = true
	beam.Transparency = NumberSequence.new(0.15)
	beam.Parent = a
	local alive = true
	task.spawn(function()
		while alive do
			local pa, pb = getA(), getB()
			if pa and pb then
				a.CFrame = CFrame.new(pa)
				b.CFrame = CFrame.new(pb)
				local pulse = 0.1 + 0.06 * math.sin(os.clock() * 9)
				beam.Width0, beam.Width1 = pulse, pulse
			end
			task.wait()
		end
	end)
	return {
		stop = function()
			if not alive then
				return
			end
			alive = false
			local pa = a.Position
			local pb = b.Position
			VFXController:arc(pa, pb, color, 0.25)
			give(a)
			give(b)
		end,
	}
end

-- Glowing cuffs around both wrists of a rig (Clamp) until handle.stop().
function VFXController:cuffs(getHands: () -> (CFrame?, CFrame?), color: Color3)
	local rings = { take(Enum.PartType.Cylinder), take(Enum.PartType.Cylinder) }
	for _, r in rings do
		r.Color = color
		r.Material = Enum.Material.Neon
		r.Transparency = 0.1
		r.Size = Vector3.new(0.25, 1.25, 1.25)
	end
	local alive = true
	task.spawn(function()
		while alive do
			local right, left = getHands()
			for i, hand in { right, left } do
				if hand then
					rings[i].CFrame = hand * CFrame.new(0, 0.35, 0) * CFrame.Angles(0, 0, math.pi / 2)
				end
			end
			task.wait()
		end
	end)
	return {
		stop = function()
			if not alive then
				return
			end
			alive = false
			for _, r in rings do
				VFXController:sparks(r.Position, Vector3.new(0, 1, 0), color, 8)
				give(r)
			end
		end,
	}
end

-- Fades a model out and destroys it.
function VFXController:dissolve(model: Instance, duration: number?, color: Color3?)
	local d = duration or 0.5
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			TweenService:Create(part, TweenInfo.new(d), { Transparency = 1 }):Play()
			if color and math.random() < 0.4 then
				self:motes(part.Position, color, 3)
			end
		end
	end
	task.delay(d + 0.05, function()
		model:Destroy()
	end)
end

---------------------------------------------------------------------------
-- Composites
---------------------------------------------------------------------------

-- Muzzle discharge. `cf` is the muzzle attachment's world CFrame (-Z forward).
function VFXController:muzzle(cf: CFrame, color: Color3, strength: number?)
	local s = strength or 1
	local pos = cf.Position
	local forward = cf.LookVector
	self:flash(pos + forward * 0.4, color, 2.2 * s, 0.18, 9 * s)
	self:flash(pos + forward * 1.1, Color3.new(1, 1, 1):Lerp(color, 0.5), 1.1 * s, 0.1, 4)
	-- A brief cone of plasma.
	local cone = take()
	cone.Color = color
	cone.Size = Vector3.new(0.5 * s, 0.5 * s, 2.4 * s)
	cone.CFrame = CFrame.lookAt(pos + forward * 1.2 * s, pos + forward * 3)
	cone.Transparency = 0.2
	TweenService:Create(cone, TweenInfo.new(0.12), { Size = Vector3.new(0.05, 0.05, 3.2 * s), Transparency = 1 }):Play()
	task.delay(0.15, give, cone)
	self:sparks(pos + forward * 0.3, forward, color, 22 * s)
	self:smoke(pos + forward * 0.5, 5 * s)
	emit("Fire", CFrame.new(pos + forward * 0.3), 6 * s, color)
end

-- A CHARGED cell striking a subject at `position` (their chest).
function VFXController:impact(position: Vector3, from: Vector3?, color: Color3, damage: number?)
	local d = damage or 1
	self:flash(position, color, 2.4 + d * 0.5, 0.3, 8)
	self:sparks(position, (from and (from - position).Unit) or Vector3.new(0, 1, 0), color, 26 + d * 6)
	self:embers(position, 8 + d * 3)
	self:smoke(position, 4 + d * 2, Color3.fromRGB(70, 68, 66))
	for _ = 1, 2 + d do
		local offset = Vector3.new(math.random() - 0.5, math.random() * 1.6 - 0.2, math.random() - 0.5) * 2.2
		self:arc(position, position + offset, color, 0.25 + math.random() * 0.25, 0.05)
	end
end

-- Hollow: a harmless puff of pale vapour at the muzzle.
function VFXController:puff(cf: CFrame, color: Color3)
	self:smoke(cf.Position + cf.LookVector * 0.3, 4, color)
	emit("Mote", CFrame.new(cf.Position + cf.LookVector * 0.2), 4, color)
end

-- Full-screen colour flash (hits, surges). Respects Reduced Flashing.
function VFXController:screenFlash(color: Color3, alpha: number, duration: number?)
	if screen == nil then
		return
	end
	local a = alpha
	if reducedFlashing() then
		a *= 0.3
	end
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 1 - a
	f.Size = UDim2.fromScale(1, 1)
	f.ZIndex = 90
	f.Parent = screen
	TweenService:Create(f, TweenInfo.new(duration or 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
	task.delay((duration or 0.5) + 0.05, function()
		f:Destroy()
	end)
end

function VFXController:Start()
	folder = Instance.new("Folder")
	folder.Name = "VarianceFX"
	folder.Parent = workspace
	emitterPart = Build.part({ Name = "Emitters", Size = Vector3.one * 0.1, Transparency = 1, CastShadow = false, Parent = folder })
	emitter("Spark", {
		Texture = SPARK,
		LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.28), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.25, 0.6),
		Speed = NumberRange.new(10, 22),
		SpreadAngle = Vector2.new(35, 35),
		Acceleration = Vector3.new(0, -24, 0),
		Drag = 3,
		Transparency = NumberSequence.new(0),
		Rate = 0,
	})
	emitter("Ember", {
		Texture = SPARK,
		LightEmission = 1,
		Color = ColorSequence.new(Color3.fromRGB(255, 150, 80)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.8, 1.6),
		Speed = NumberRange.new(2, 6),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -6, 0),
		Drag = 1.5,
		Rate = 0,
	})
	emitter("Smoke", {
		Texture = SMOKE,
		LightEmission = 0,
		LightInfluence = 0.6,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.6) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(1.2, 2.2),
		Speed = NumberRange.new(0.6, 1.6),
		SpreadAngle = Vector2.new(40, 40),
		Acceleration = Vector3.new(0, 1.2, 0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-30, 30),
		Drag = 1,
		Rate = 0,
	})
	emitter("Mote", {
		Texture = SPARK,
		LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(0.5, 0.25), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(0.8, 2.2),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 2.5, 0),
		Drag = 2,
		Rate = 0,
	})
	emitter("Fire", {
		Texture = FIRE,
		LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.12, 0.25),
		Speed = NumberRange.new(4, 9),
		SpreadAngle = Vector2.new(15, 15),
		Rate = 0,
	})
	local ui = self.Controllers.UIController
	screen = Instance.new("Frame")
	screen.Name = "ScreenFx"
	screen.BackgroundTransparency = 1
	screen.Size = UDim2.fromScale(1, 1)
	screen.ZIndex = 90
	screen.Parent = ui.Overlay
end

return VFXController

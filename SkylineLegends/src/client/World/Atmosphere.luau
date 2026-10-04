-- Per-district lighting, time of day and weather.
--
-- Each district has its own look (Config/Districts.Lighting): warm morning
-- rooftops, an amber industrial dusk, a misty garden, a neon city at night, a
-- bright cold summit and a golden sky citadel. Crossing between districts
-- blends everything over a few seconds. Time of day moves through each
-- district's range on a shared clock, and weather comes and goes in windows
-- every player sees at the same time.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Districts = require(ReplicatedStorage.Shared.Config.Districts)
local Rotation = require(ReplicatedStorage.Shared.Logic.Rotation)
local Schedule = require(ReplicatedStorage.Shared.Logic.Schedule)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local Settings = require(script.Parent.Parent.Core.Settings)
local Controller = require(script.Parent.Parent.Movement.Controller)

local Atmosphere = {}

Atmosphere.District = "Hub"
Atmosphere.Changed = Signal.new() -- (districtId, previous)
Atmosphere.WeatherChanged = Signal.new() -- (kind or nil)

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- The Dreamline floats outside every district.
local DREAM: Districts.Lighting = {
	Clock = { 0.5, 2.5 },
	CycleMinutes = 30,
	Brightness = 1.6,
	Ambient = rgb(120, 90, 150),
	OutdoorAmbient = rgb(150, 110, 190),
	ShiftTop = rgb(255, 170, 240),
	ShiftBottom = rgb(90, 110, 255),
	Exposure = 0.25,
	Atmosphere = {
		Density = 0.38,
		Offset = 0.3,
		Color = rgb(190, 150, 255),
		Decay = rgb(255, 150, 220),
		Glare = 0.6,
		Haze = 2.2,
	},
	Bloom = { Intensity = 0.9, Size = 30, Threshold = 1.2 },
	Grade = { Brightness = 0.04, Contrast = 0.12, Saturation = 0.25, Tint = rgb(255, 235, 255) },
	SunRays = 0.12,
	Clouds = { Cover = 0.7, Density = 0.5, Color = rgb(255, 200, 250) },
	Night = rgb(60, 40, 90),
}

local atmosphere: Atmosphere
local bloom: BloomEffect
local grade: ColorCorrectionEffect
local rays: SunRaysEffect
local clouds: Clouds?

local target: Districts.Lighting = DREAM
local blend = 1
local weatherKind: string? = nil

-- Weather emitters on a part that follows the camera.
local weatherPart = Instance.new("Part")
weatherPart.Name = "SkylineWeather"
weatherPart.Anchored = true
weatherPart.CanCollide = false
weatherPart.CanQuery = false
weatherPart.CanTouch = false
weatherPart.Transparency = 1
weatherPart.Size = Vector3.new(140, 1, 140)
local emitters: { [string]: ParticleEmitter } = {}
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function makeEmitter(kind: string): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = kind
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Enabled = false
	e.LightInfluence = 0.6
	if kind == "Drizzle" then
		e.Texture = SPARKLE
		e.Color = ColorSequence.new(rgb(200, 215, 235))
		e.Transparency = NumberSequence.new(0.45)
		e.Size = NumberSequence.new(0.12)
		e.Squash = NumberSequence.new(-2.6)
		e.Orientation = Enum.ParticleOrientation.VelocityParallel
		e.Speed = NumberRange.new(90, 110)
		e.Lifetime = NumberRange.new(0.6, 0.9)
		e.Rate = 900
	elseif kind == "Snow" then
		e.Texture = SPARKLE
		e.Color = ColorSequence.new(rgb(255, 255, 255))
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0.15) })
		e.Speed = NumberRange.new(6, 12)
		e.Lifetime = NumberRange.new(5, 7)
		e.Acceleration = Vector3.new(4, 0, 2)
		e.SpreadAngle = Vector2.new(20, 20)
		e.Rate = 320
	elseif kind == "Embers" then
		e.Texture = SPARKLE
		e.EmissionDirection = Enum.NormalId.Top
		e.Color = ColorSequence.new(rgb(255, 170, 60), rgb(255, 80, 30))
		e.LightEmission = 1
		e.LightInfluence = 0
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.22), NumberSequenceKeypoint.new(1, 0) })
		e.Speed = NumberRange.new(4, 10)
		e.Lifetime = NumberRange.new(3, 5)
		e.Acceleration = Vector3.new(2, 3, 0)
		e.SpreadAngle = Vector2.new(40, 40)
		e.Rate = 70
	elseif kind == "Leaves" then
		e.Texture = SMOKE
		e.Color = ColorSequence.new(rgb(120, 170, 70), rgb(220, 150, 60))
		e.Size = NumberSequence.new(0.35)
		e.Squash = NumberSequence.new(0.6)
		e.Speed = NumberRange.new(3, 6)
		e.Lifetime = NumberRange.new(6, 8)
		e.RotSpeed = NumberRange.new(-200, 200)
		e.Rotation = NumberRange.new(0, 360)
		e.Acceleration = Vector3.new(3, -2, 1)
		e.Rate = 40
	else -- Motes
		e.Texture = SPARKLE
		e.Color = ColorSequence.new(rgb(255, 240, 200))
		e.LightEmission = 0.8
		e.LightInfluence = 0
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.Size = NumberSequence.new(0.18)
		e.Speed = NumberRange.new(0.4, 1.4)
		e.Lifetime = NumberRange.new(4, 7)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Rate = 60
	end
	e:SetAttribute("BaseRate", e.Rate)
	e.Parent = weatherPart
	return e
end

-- Is a district's weather active right now? Same answer for every player.
local function weatherFor(id: string): string?
	local district = Districts.ById[id]
	local weather = if district then district.Weather else { Kind = "Motes", Chance = 1 }
	local window = math.floor(Schedule.Now() / 240)
	local roll = (Rotation.Hash("weather", id, window) % 1000) / 1000
	if roll < weather.Chance then
		return weather.Kind
	end
	return nil
end

local function lightingFor(id: string): Districts.Lighting
	if id == "Dreamline" then
		return DREAM
	end
	local district = Districts.ById[id] or Districts.ById.Hub
	return district.Lighting
end

local function districtAt(position: Vector3): string?
	if (position - Districts.Dreamline).Magnitude < 2600 then
		return "Dreamline"
	end
	local district = Districts.At(position)
	return if district then district.Id else nil
end

-- Blend helpers.
local function lerpNumber(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function apply(dt: number)
	local l = target
	local t = 1 - math.exp(-dt * 0.9)
	if blend < 1 then
		blend = math.min(blend + dt * 0.35, 1)
	else
		t = 1 - math.exp(-dt * 3)
	end
	Lighting.Brightness = lerpNumber(Lighting.Brightness, l.Brightness, t)
	Lighting.Ambient = Lighting.Ambient:Lerp(l.Ambient, t)
	Lighting.OutdoorAmbient = Lighting.OutdoorAmbient:Lerp(l.OutdoorAmbient, t)
	Lighting.ColorShift_Top = Lighting.ColorShift_Top:Lerp(l.ShiftTop, t)
	Lighting.ColorShift_Bottom = Lighting.ColorShift_Bottom:Lerp(l.ShiftBottom, t)
	Lighting.ExposureCompensation = lerpNumber(Lighting.ExposureCompensation, l.Exposure, t)
	local a = l.Atmosphere
	atmosphere.Density = lerpNumber(atmosphere.Density, a.Density, t)
	atmosphere.Offset = lerpNumber(atmosphere.Offset, a.Offset, t)
	atmosphere.Color = atmosphere.Color:Lerp(a.Color, t)
	atmosphere.Decay = atmosphere.Decay:Lerp(a.Decay, t)
	atmosphere.Glare = lerpNumber(atmosphere.Glare, a.Glare, t)
	atmosphere.Haze =
		lerpNumber(atmosphere.Haze, a.Haze + (if weatherKind == "Drizzle" or weatherKind == "Snow" then 0.8 else 0), t)
	bloom.Intensity = lerpNumber(bloom.Intensity, l.Bloom.Intensity, t)
	bloom.Size = lerpNumber(bloom.Size, l.Bloom.Size, t)
	bloom.Threshold = lerpNumber(bloom.Threshold, l.Bloom.Threshold, t)
	grade.Brightness = lerpNumber(grade.Brightness, l.Grade.Brightness, t)
	grade.Contrast = lerpNumber(grade.Contrast, l.Grade.Contrast, t)
	grade.Saturation = lerpNumber(grade.Saturation, l.Grade.Saturation, t)
	grade.TintColor = grade.TintColor:Lerp(l.Grade.Tint, t)
	rays.Intensity = lerpNumber(rays.Intensity, l.SunRays, t)
	local c = clouds
	if c then
		c.Cover = lerpNumber(c.Cover, l.Clouds.Cover + (if weatherKind == "Drizzle" then 0.25 else 0), t)
		c.Density = lerpNumber(c.Density, l.Clouds.Density, t)
		c.Color = c.Color:Lerp(l.Clouds.Color, t)
	end

	-- Time of day moves through the district's range on a shared clock.
	local clock = l.Clock
	local target_: number
	if Settings.Get("DayCycle") then
		local phase = Schedule.PingPong(Schedule.Now(), l.CycleMinutes * 60, 0)
		target_ = lerpNumber(clock[1], clock[2], phase)
	else
		target_ = (clock[1] + clock[2]) / 2
	end
	local current = Lighting.ClockTime
	local delta = (target_ - current + 12) % 24 - 12
	Lighting.ClockTime = (current + delta * t) % 24
	Lighting.GlobalShadows = Settings.Get("Shadows") ~= false and Settings.Quality() ~= "Low"
end

local function setDistrict(id: string)
	if id == Atmosphere.District then
		return
	end
	local previous = Atmosphere.District
	Atmosphere.District = id
	target = lightingFor(id)
	blend = 0
	Atmosphere.Changed:Fire(id, previous)
end

local function updateWeather()
	local kind = if Settings.Get("Weather") then weatherFor(Atmosphere.District) else nil
	if kind ~= weatherKind then
		weatherKind = kind
		Atmosphere.WeatherChanged:Fire(kind)
	end
	local scale = if Settings.Quality() == "Low" then 0.35 elseif Settings.Quality() == "Medium" then 0.65 else 1
	for name, emitter in emitters do
		local on = name == kind
		emitter.Enabled = on
		local base = emitter:GetAttribute("BaseRate")
		if type(base) == "number" then
			emitter.Rate = base * scale
		end
	end
end

function Atmosphere.Weather(): string?
	return weatherKind
end

function Atmosphere.Start()
	local existing = Lighting:FindFirstChildOfClass("Atmosphere")
	atmosphere = existing or Instance.new("Atmosphere")
	atmosphere.Parent = Lighting
	bloom = Instance.new("BloomEffect")
	bloom.Name = "SkylineBloom"
	bloom.Parent = Lighting
	grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "SkylineGrade"
	grade.Parent = Lighting
	rays = Instance.new("SunRaysEffect")
	rays.Name = "SkylineRays"
	rays.Spread = 0.8
	rays.Parent = Lighting
	local ok, made = pcall(function()
		local c = workspace.Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
		c.Parent = workspace.Terrain
		return c
	end)
	if ok then
		clouds = made
	end
	for _, kind in { "Drizzle", "Snow", "Embers", "Leaves", "Motes" } do
		emitters[kind] = makeEmitter(kind)
	end

	target = lightingFor("Hub")
	Atmosphere.District = "Hub"
	blend = 1
	local lastCheck = 0
	local lastWeather = 0
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		local root = Controller.Info.Root
		local camera = workspace.CurrentCamera
		local position = if root then root.Position elseif camera then camera.CFrame.Position else nil
		if position and now - lastCheck > 0.5 then
			lastCheck = now
			local id = districtAt(position)
			if id then
				setDistrict(id)
			end
		end
		if now - lastWeather > 2 then
			lastWeather = now
			updateWeather()
		end
		apply(dt)
		if camera then
			local offset = if weatherKind == "Embers"
				then Vector3.new(0, -30, 0)
				elseif weatherKind == "Motes" then Vector3.zero
				else Vector3.new(0, 34, 0)
			weatherPart.Size = if weatherKind == "Motes" then Vector3.new(90, 40, 90) else Vector3.new(140, 1, 140)
			weatherPart.CFrame = CFrame.new(camera.CFrame.Position + offset)
			weatherPart.Parent = camera
		end
	end)
	Controller.Teleported:Connect(function(cframe: CFrame)
		local id = districtAt(cframe.Position)
		if id then
			setDistrict(id)
		end
	end)
	Players.LocalPlayer.CharacterAdded:Connect(function(character)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if root and root:IsA("BasePart") then
			local id = districtAt(root.Position)
			if id then
				setDistrict(id)
				blend = 1
			end
		end
	end)
end

return Atmosphere

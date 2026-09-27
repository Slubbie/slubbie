-- Look and feel of the world on this client: graphics quality, time of day and
-- a screen vignette that deepens with speed.
--
-- Changes to Lighting made here are local to this player, so everyone can pick
-- their own quality and time of day.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local MathUtil = require(game:GetService("ReplicatedStorage").Shared.MathUtil)
local Settings = require(script.Parent.Settings)
local UI = require(script.Parent.UI)

export type Profile = {
	Shadows: boolean,
	Bloom: boolean,
	SunRays: boolean,
	DepthOfField: boolean,
	SkyClouds: boolean,
	Vignette: boolean,
	Birds: boolean,
	Motes: number, -- ambient particle rate
}

local QUALITY: { [string]: Profile } = {
	Low = {
		Shadows = false,
		Bloom = false,
		SunRays = false,
		DepthOfField = false,
		SkyClouds = false,
		Vignette = false,
		Birds = false,
		Motes = 0,
	},
	Medium = {
		Shadows = true,
		Bloom = true,
		SunRays = false,
		DepthOfField = false,
		SkyClouds = true,
		Vignette = true,
		Birds = true,
		Motes = 6,
	},
	High = {
		Shadows = true,
		Bloom = true,
		SunRays = true,
		DepthOfField = false,
		SkyClouds = true,
		Vignette = true,
		Birds = true,
		Motes = 14,
	},
	Ultra = {
		Shadows = true,
		Bloom = true,
		SunRays = true,
		DepthOfField = true,
		SkyClouds = true,
		Vignette = true,
		Birds = true,
		Motes = 24,
	},
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Each time of day sets Lighting, Atmosphere, colour grading and bloom.
local TIMES = {
	Sunrise = {
		Lighting = {
			ClockTime = 6.4,
			Brightness = 2.4,
			Ambient = rgb(80, 70, 92),
			OutdoorAmbient = rgb(165, 142, 165),
			ExposureCompensation = 0.2,
		},
		Atmosphere = { Density = 0.38, Color = rgb(255, 212, 192), Decay = rgb(190, 120, 150), Haze = 2.4, Glare = 0.8 },
		Grade = { TintColor = rgb(255, 238, 230), Saturation = 0.16 },
		Bloom = 0.9,
	},
	["Golden Hour"] = {
		Lighting = {
			ClockTime = 16.4,
			Brightness = 3,
			Ambient = rgb(70, 72, 96),
			OutdoorAmbient = rgb(150, 158, 196),
			ExposureCompensation = 0.15,
		},
		Atmosphere = { Density = 0.34, Color = rgb(212, 226, 255), Decay = rgb(150, 128, 190), Haze = 1.8, Glare = 0.6 },
		Grade = { TintColor = rgb(255, 248, 240), Saturation = 0.18 },
		Bloom = 0.8,
	},
	Sunset = {
		Lighting = {
			ClockTime = 17.75,
			Brightness = 2.2,
			Ambient = rgb(84, 62, 84),
			OutdoorAmbient = rgb(175, 132, 150),
			ExposureCompensation = 0.25,
		},
		Atmosphere = { Density = 0.4, Color = rgb(255, 182, 142), Decay = rgb(170, 82, 122), Haze = 2.6, Glare = 1 },
		Grade = { TintColor = rgb(255, 228, 214), Saturation = 0.22 },
		Bloom = 1,
	},
	Night = {
		Lighting = {
			ClockTime = 0.3,
			Brightness = 1.2,
			Ambient = rgb(40, 46, 72),
			OutdoorAmbient = rgb(72, 86, 142),
			ExposureCompensation = 0.5,
		},
		Atmosphere = { Density = 0.3, Color = rgb(82, 96, 152), Decay = rgb(30, 30, 72), Haze = 1, Glare = 0.2 },
		Grade = { TintColor = rgb(220, 230, 255), Saturation = 0.1 },
		Bloom = 1.4,
	},
}

local Graphics = {}
Graphics.ProfileChanged = Instance.new("BindableEvent") -- (profile)

function Graphics.Profile(): Profile
	return QUALITY[Settings.Get("Quality")] or QUALITY.High
end

local function effect(className: string): any
	local existing = Lighting:FindFirstChildOfClass(className)
	if existing then
		return existing
	end
	local created = Instance.new(className)
	created.Parent = Lighting
	return created
end

local function tweenTo(target: Instance, props: { [string]: any }, time: number)
	if time <= 0 then
		for key, value in props do
			(target :: any)[key] = value
		end
	else
		TweenService:Create(target, TweenInfo.new(time, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), props)
			:Play()
	end
end

local function applyTimeOfDay(name: string, time: number)
	local preset = TIMES[name] or TIMES["Golden Hour"]
	tweenTo(Lighting, preset.Lighting, time)
	tweenTo(effect("Atmosphere"), preset.Atmosphere, time)
	tweenTo(effect("ColorCorrectionEffect"), preset.Grade, time)
	tweenTo(effect("BloomEffect"), { Intensity = preset.Bloom }, time)
end

local function applyQuality(profile: Profile)
	Lighting.GlobalShadows = profile.Shadows
	effect("BloomEffect").Enabled = profile.Bloom
	effect("SunRaysEffect").Enabled = profile.SunRays
	effect("DepthOfFieldEffect").Enabled = profile.DepthOfField
	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	if clouds then
		clouds.Enabled = profile.SkyClouds
	end
	Graphics.ProfileChanged:Fire(profile)
end

-- Four soft dark edges, darker the faster you go.
local function createVignette()
	local gui = UI.gui("Vignette", -5)
	local edges = {}
	local layout = {
		{ Size = UDim2.fromScale(1, 0.3), Position = UDim2.fromScale(0, 0), Rotation = 90 },
		{ Size = UDim2.fromScale(1, 0.3), Position = UDim2.fromScale(0, 0.7), Rotation = -90 },
		{ Size = UDim2.fromScale(0.22, 1), Position = UDim2.fromScale(0, 0), Rotation = 0 },
		{ Size = UDim2.fromScale(0.22, 1), Position = UDim2.fromScale(0.78, 0), Rotation = 180 },
	}
	for _, spec in layout do
		local frame = UI.new("Frame", {
			Size = spec.Size,
			Position = spec.Position,
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
		}, gui)
		local gradient = UI.new("UIGradient", { Rotation = spec.Rotation }, frame)
		table.insert(edges, gradient)
	end
	return gui,
		function(strength: number)
			local sequence = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1 - strength),
				NumberSequenceKeypoint.new(1, 1),
			})
			for _, gradient in edges do
				gradient.Transparency = sequence
			end
		end
end

function Graphics.Start(Movement)
	-- Bigger sun and moon, and a sky full of stars at night.
	local sky = effect("Sky")
	sky.StarCount = 4000
	sky.SunAngularSize = 16
	sky.MoonAngularSize = 12
	sky.CelestialBodiesShown = true

	local started = false
	Settings.Watch("TimeOfDay", function(name)
		applyTimeOfDay(name, if started then 3 else 0)
	end)
	Settings.Watch("Quality", function()
		applyQuality(Graphics.Profile())
	end)
	started = true

	local vignetteGui, setVignette = createVignette()
	local strength = 0.25
	RunService.RenderStepped:Connect(function(dt)
		local profile = Graphics.Profile()
		vignetteGui.Enabled = profile.Vignette and Movement.Enabled
		if not vignetteGui.Enabled then
			return
		end
		local speed = Movement.Info.Velocity.Magnitude
		local target = 0.22 + math.clamp((speed - 40) / 120, 0, 1) * 0.33
		strength = MathUtil.Damp(strength, target, 4, dt)
		setVignette(strength)
	end)
end

return Graphics

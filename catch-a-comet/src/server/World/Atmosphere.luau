-- Lighting, sky, post-processing, terrain colours, the cloud sea below the
-- islands and the distant celestial structures. The client scales the
-- post-processing down on lower graphics settings.

local Lighting = game:GetService("Lighting")

local Kit = require(script.Parent.Kit)

local Atmosphere = {}

local function ensure(className: string, name: string, parent: Instance): any
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA(className) then
		return existing
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

function Atmosphere.Apply()
	Lighting.ClockTime = 16.9
	Lighting.GeographicLatitude = 28
	Lighting.Brightness = 2.4
	Lighting.Ambient = Color3.fromRGB(70, 60, 112)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 130, 190)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.ColorShift_Top = Color3.fromRGB(255, 214, 176)
	Lighting.ExposureCompensation = 0.1

	local atmosphere = ensure("Atmosphere", "Atmosphere", Lighting) :: Atmosphere
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.18
	atmosphere.Color = Color3.fromRGB(199, 170, 255)
	atmosphere.Decay = Color3.fromRGB(120, 100, 214)
	atmosphere.Glare = 0.45
	atmosphere.Haze = 1.4

	local sky = ensure("Sky", "Sky", Lighting) :: Sky
	sky.StarCount = 3000
	sky.SunAngularSize = 16
	sky.MoonAngularSize = 9
	sky.CelestialBodiesShown = true

	local bloom = ensure("BloomEffect", "Bloom", Lighting) :: BloomEffect
	bloom.Intensity = 0.55
	bloom.Size = 32
	bloom.Threshold = 1.35

	local grade = ensure("ColorCorrectionEffect", "Grade", Lighting) :: ColorCorrectionEffect
	grade.Brightness = 0.02
	grade.Contrast = 0.06
	grade.Saturation = 0.14
	grade.TintColor = Color3.fromRGB(255, 247, 242)

	local rays = ensure("SunRaysEffect", "SunRays", Lighting) :: SunRaysEffect
	rays.Intensity = 0.05
	rays.Spread = 0.6

	local terrain = workspace.Terrain
	local ok = pcall(function()
		local clouds = ensure("Clouds", "Clouds", terrain) :: Clouds
		clouds.Cover = 0.6
		clouds.Density = 0.5
		clouds.Color = Color3.fromRGB(255, 236, 250)
		terrain.WaterColor = Color3.fromRGB(110, 220, 240)
		terrain.WaterTransparency = 0.55
		terrain.WaterReflectance = 0.35
		terrain.WaterWaveSize = 0.06
		terrain.WaterWaveSpeed = 6
	end)
	if not ok then
		warn("[World] Terrain clouds/water settings unavailable")
	end

	Kit.Terrain.Color(Enum.Material.Grass, Color3.fromRGB(172, 214, 142))
	Kit.Terrain.Color(Enum.Material.LeafyGrass, Color3.fromRGB(204, 176, 240))
	Kit.Terrain.Color(Enum.Material.Rock, Color3.fromRGB(152, 140, 182))
	Kit.Terrain.Color(Enum.Material.Ground, Color3.fromRGB(150, 126, 128))
	Kit.Terrain.Color(Enum.Material.Slate, Color3.fromRGB(118, 108, 152))
	Kit.Terrain.Color(Enum.Material.Sand, Color3.fromRGB(242, 222, 196))
end

-- Soft cloud sea far below the islands, and planets/rings on the horizon.
function Atmosphere.BuildSkyscape(parent: Instance, rng: Random)
	local below = Kit.Model("CloudSea", parent)
	below.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	Kit.Part(below, Vector3.new(2048, 2, 2048), CFrame.new(150, -190, 0), {
		Name = "Haze",
		Color = Color3.fromRGB(176, 150, 236),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.15,
		Decor = true,
		CastShadow = false,
	})
	for _ = 1, 34 do
		local a = rng:NextNumber() * math.pi * 2
		local d = 200 + rng:NextNumber() * 900
		local size = 70 + rng:NextNumber() * 110
		local puff = Kit.Ball(
			below,
			size,
			Vector3.new(150 + math.cos(a) * d, -150 - rng:NextNumber() * 40, math.sin(a) * d),
			Color3.fromRGB(255, 236, 250):Lerp(Color3.fromRGB(200, 176, 255), rng:NextNumber()),
			Enum.Material.SmoothPlastic
		)
		puff.Transparency = 0.25
		puff.CastShadow = false
	end

	local horizon = Kit.Model("Horizon", parent)
	horizon.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local planets = {
		{ Position = Vector3.new(-1600, 520, -1700), Size = 520, Color = Color3.fromRGB(255, 186, 214), Ring = true },
		{ Position = Vector3.new(1900, 360, 1300), Size = 300, Color = Color3.fromRGB(150, 210, 255), Ring = false },
		{ Position = Vector3.new(400, 760, 2100), Size = 220, Color = Color3.fromRGB(255, 220, 150), Ring = true },
	}
	for _, spec in planets do
		local planet = Kit.Ball(horizon, spec.Size, spec.Position, spec.Color, Enum.Material.SmoothPlastic)
		planet.CastShadow = false
		if spec.Ring then
			local tilt = CFrame.new(spec.Position) * CFrame.Angles(math.rad(70), math.rad(rng:NextNumber() * 180), 0)
			Kit.Ring(
				horizon,
				tilt,
				spec.Size * 0.95,
				Vector2.new(6, spec.Size * 0.06),
				48,
				spec.Color:Lerp(Color3.new(1, 1, 1), 0.4),
				Enum.Material.Neon
			)
		end
	end
	-- An enormous drifting celestial ring that the client slowly turns.
	local _, root = Kit.Animated(
		horizon,
		"GreatRing",
		CFrame.new(-300, 420, 900) * CFrame.Angles(math.rad(62), 0, math.rad(12)),
		"Spinner",
		{
			SpinAxis = "Y",
			SpinSpeed = 0.02,
		}
	)
	for _, part in
		Kit.Ring(horizon, root.CFrame, 360, Vector2.new(5, 14), 64, Color3.fromRGB(255, 220, 170), Enum.Material.Neon)
	do
		part.Parent = root.Parent
		Kit.WeldTo(part, root)
	end
end

return Atmosphere

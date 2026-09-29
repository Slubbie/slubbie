-- Time of day, weather visuals, seasons and world "state" dressing.
--
-- * Clock: Lighting.ClockTime follows GameTime (shared by every client).
-- * Weather: the current regional weather (WeatherMath.ForRegion) drives
--   clouds, atmosphere, colour grading, precipitation particles around the
--   camera, lightning flashes, and sky events (meteors, aurora, rainbows).
--   Values ease between states so changes feel natural.
-- * Seasons: terrain grass/leaf colours follow Config/Seasons palettes.
-- * Night: parts tagged NightGlow light up; NightLight lights switch on.
-- * Festivals: FestivalOnly decorations appear; the plaza gets bunting.
-- * Town projects: buildings the player hasn't funded show as scaffolding.
-- * Underground regions are dark and foggy (a lantern or Glow Potion helps).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Seasons = require(Shared.Config.Seasons)
local Regions = require(Shared.Config.Regions)
local GameTime = require(Shared.Lib.GameTime)
local WeatherMath = require(Shared.Lib.WeatherMath)
local Signal = require(Shared.Lib.Signal)

local C = require(script.Parent)

local LightingController = {}
LightingController.WeatherChanged = Signal.new() -- (weatherId)
LightingController.NightChanged = Signal.new() -- (isNight)

local player = Players.LocalPlayer
local random = Random.new()

local regionById: { [string]: any } = {}
for _, region in Regions.List do
	regionById[region.Id] = region
end

local currentWeather = "Sunny"
local isNight = false

function LightingController.Region(): any
	return regionById[player:GetAttribute("Region") or "Homestead"] or regionById.Homestead
end

function LightingController.Weather(): string
	return currentWeather
end

function LightingController.IsNight(): boolean
	return isNight
end

function LightingController.Underground(): boolean
	local biome = LightingController.Region().Biome
	return biome == "Cave" or biome == "Crystal"
end

-- Eased values ---------------------------------------------------------------------------------------------------------

local eased: { [string]: any } = {}
local function ease(key: string, target: any, rate: number, dt: number): any
	local value = eased[key]
	if value == nil then
		eased[key] = target
		return target
	end
	local t = 1 - math.exp(-rate * dt)
	if typeof(target) == "Color3" then
		value = (value :: Color3):Lerp(target, t)
	else
		value = value + (target - value) * t
	end
	eased[key] = value
	return value
end

-- Precipitation ----------------------------------------------------------------------------------------------------------

local rig: Part
local emitters: { [string]: ParticleEmitter } = {}

local PARTICLE_DEFS: { [string]: { [string]: any } } = {
	Rain = {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Lifetime = NumberRange.new(0.6, 0.8),
		Speed = NumberRange.new(80, 95),
		Size = NumberSequence.new(0.12),
		Color = ColorSequence.new(Color3.fromRGB(190, 210, 235)),
		Transparency = NumberSequence.new(0.35),
		Stretch = true,
		Rate = 900,
	},
	Snow = {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Lifetime = NumberRange.new(4, 6),
		Speed = NumberRange.new(6, 10),
		Size = NumberSequence.new(0.35),
		Color = ColorSequence.new(Color3.new(1, 1, 1)),
		Transparency = NumberSequence.new(0.1),
		Rate = 400,
		Spread = 25,
	},
	Hail = {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Lifetime = NumberRange.new(0.8, 1),
		Speed = NumberRange.new(60, 70),
		Size = NumberSequence.new(0.3),
		Color = ColorSequence.new(Color3.fromRGB(230, 240, 255)),
		Transparency = NumberSequence.new(0),
		Rate = 250,
	},
	Leaves = {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Lifetime = NumberRange.new(3, 5),
		Speed = NumberRange.new(10, 18),
		Size = NumberSequence.new(0.5),
		Color = ColorSequence.new(Color3.fromRGB(150, 180, 80), Color3.fromRGB(210, 140, 60)),
		Transparency = NumberSequence.new(0.1),
		Rate = 40,
		Spread = 60,
		Wind = true,
	},
	Pollen = {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Lifetime = NumberRange.new(5, 8),
		Speed = NumberRange.new(1, 3),
		Size = NumberSequence.new(0.18),
		Color = ColorSequence.new(Color3.fromRGB(255, 240, 150)),
		Transparency = NumberSequence.new(0.2),
		Rate = 120,
		Spread = 180,
		Light = 0.6,
	},
	Sand = {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Lifetime = NumberRange.new(2, 3),
		Speed = NumberRange.new(30, 40),
		Size = NumberSequence.new(3, 6),
		Color = ColorSequence.new(Color3.fromRGB(220, 190, 140)),
		Transparency = NumberSequence.new(0.7, 1),
		Rate = 120,
		Spread = 30,
		Wind = true,
	},
	Heat = {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Lifetime = NumberRange.new(2, 3),
		Speed = NumberRange.new(1, 2),
		Size = NumberSequence.new(4, 8),
		Color = ColorSequence.new(Color3.fromRGB(255, 230, 200)),
		Transparency = NumberSequence.new(0.92, 1),
		Rate = 30,
		Spread = 180,
	},
	Frost = {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Lifetime = NumberRange.new(3, 5),
		Speed = NumberRange.new(1, 3),
		Size = NumberSequence.new(0.2),
		Color = ColorSequence.new(Color3.fromRGB(200, 230, 255)),
		Transparency = NumberSequence.new(0.2),
		Rate = 90,
		Spread = 180,
		Light = 0.8,
	},
	Arcane = {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Lifetime = NumberRange.new(2, 4),
		Speed = NumberRange.new(4, 10),
		Size = NumberSequence.new(0.35),
		Color = ColorSequence.new(Color3.fromRGB(190, 120, 255), Color3.fromRGB(90, 220, 255)),
		Transparency = NumberSequence.new(0.1),
		Rate = 160,
		Spread = 180,
		Light = 1,
	},
	Rainbow = {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Lifetime = NumberRange.new(3, 5),
		Speed = NumberRange.new(1, 2),
		Size = NumberSequence.new(0.25),
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 120, 120)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(120, 255, 160)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(140, 150, 255)),
		}),
		Transparency = NumberSequence.new(0.2),
		Rate = 80,
		Spread = 180,
		Light = 1,
	},
}

local function buildRig()
	rig = Instance.new("Part")
	rig.Name = "WeatherRig"
	rig.Anchored = true
	rig.CanCollide = false
	rig.CanQuery = false
	rig.CanTouch = false
	rig.Transparency = 1
	rig.Size = Vector3.new(120, 1, 120)
	rig.Parent = workspace.CurrentCamera
	for name, def in PARTICLE_DEFS do
		local e = Instance.new("ParticleEmitter")
		e.Name = name
		e.Texture = def.Texture
		e.Lifetime = def.Lifetime
		e.Speed = def.Speed
		e.Size = def.Size
		e.Color = def.Color
		e.Transparency = def.Transparency
		e.LightEmission = def.Light or 0
		e.SpreadAngle = Vector2.new(def.Spread or 4, def.Spread or 4)
		e.EmissionDirection = Enum.NormalId.Bottom
		e.Rate = 0
		e.Enabled = false
		if def.Stretch then
			e.Orientation = Enum.ParticleOrientation.VelocityParallel
		end
		e.Parent = rig
		emitters[name] = e
	end
end

-- Sky events -------------------------------------------------------------------------------------------------------------

local skyFolder: Folder
local auroraParts: { BasePart } = {}
local rainbowModel: Model? = nil

local function ensureAurora()
	if #auroraParts > 0 then
		return
	end
	for i = 1, 6 do
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Size = Vector3.new(900, 120, 2)
		p.Transparency = 1
		p.Name = "Aurora"
		p.Parent = skyFolder
		p:SetAttribute("Phase", i * 0.9)
		table.insert(auroraParts, p)
	end
end

local function updateAurora(on: boolean, t: number)
	if not on then
		for _, p in auroraParts do
			p.Transparency = 1
		end
		return
	end
	ensureAurora()
	local cam = workspace.CurrentCamera.CFrame.Position
	for i, p in auroraParts do
		local phase = p:GetAttribute("Phase") or 0
		local wave = math.sin(t * 0.25 + phase)
		p.CFrame = CFrame.new(cam.X + (i - 3.5) * 60, 420 + wave * 20, cam.Z - 600)
			* CFrame.Angles(0, math.sin(t * 0.1 + phase) * 0.3, math.rad(10 + wave * 5))
		p.Color = Color3.fromHSV((0.38 + 0.12 * math.sin(t * 0.07 + phase)) % 1, 0.7, 1)
		p.Transparency = 0.7 + 0.15 * math.sin(t * 0.3 + phase * 2)
	end
end

local function meteor()
	local cam = workspace.CurrentCamera.CFrame.Position
	local start = cam
		+ Vector3.new(random:NextNumber(-500, 500), random:NextNumber(300, 450), random:NextNumber(-600, -200))
	local dir = Vector3.new(random:NextNumber(-1, 1), -0.35, random:NextNumber(-0.3, 0.3)).Unit
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 240, 200)
	p.Size = Vector3.new(1.5, 1.5, 40)
	p.CFrame = CFrame.lookAt(start, start + dir)
	p.Parent = skyFolder
	task.spawn(function()
		for i = 1, 30 do
			p.CFrame += dir * 18
			p.Transparency = i / 30
			task.wait(1 / 30)
		end
		p:Destroy()
	end)
end

local function setRainbow(on: boolean)
	if on and not rainbowModel then
		local m = Instance.new("Model")
		m.Name = "Rainbow"
		local colors = {
			Color3.fromRGB(255, 90, 90),
			Color3.fromRGB(255, 170, 70),
			Color3.fromRGB(255, 240, 90),
			Color3.fromRGB(110, 220, 110),
			Color3.fromRGB(90, 160, 255),
			Color3.fromRGB(160, 110, 240),
		}
		for band, color in colors do
			for seg = 0, 23 do
				local a = seg / 24 * math.pi
				local r = 600 - band * 12
				local p = Instance.new("Part")
				p.Anchored = true
				p.CanCollide = false
				p.CanQuery = false
				p.CastShadow = false
				p.Material = Enum.Material.Neon
				p.Color = color
				p.Transparency = 0.65
				p.Size = Vector3.new(12, 80, 2)
				p.CFrame = CFrame.new(math.cos(a) * r, math.sin(a) * r - 80, -900)
					* CFrame.Angles(0, 0, a - math.pi / 2)
				p.Parent = m
			end
		end
		m.Parent = skyFolder
		rainbowModel = m
	elseif not on and rainbowModel then
		rainbowModel:Destroy()
		rainbowModel = nil
	end
end

-- Lightning --------------------------------------------------------------------------------------------------------------

local flash = 0
function LightingController.Lightning(position: Vector3?)
	local gentle = C.Settings.Get("ReducedFlashing") == true
	flash = if gentle then 0.6 else 2.5
	local delay = if position
		then (workspace.CurrentCamera.CFrame.Position - position).Magnitude / 340
		else random:NextNumber(0.4, 2.2)
	task.delay(math.min(delay, 4), function()
		C.Audio.PlayUI("Thunder")
	end)
	C.Camera.Shake(0.25, 0.4)
end

-- Night lights, festival decor, projects --------------------------------------------------------------------------------

local glowParts: { [BasePart]: { Material: Enum.Material, Color: Color3 } } = setmetatable({} :: any, { __mode = "k" })
local nightLights: { [Light]: boolean } = setmetatable({} :: any, { __mode = "k" })
local festivalParts: { [BasePart]: number } = setmetatable({} :: any, { __mode = "k" })
local projectModels: { [Model]: string } = setmetatable({} :: any, { __mode = "k" })

local function register(d: Instance)
	if d:IsA("BasePart") then
		if d:GetAttribute("NightGlow") then
			glowParts[d] = { Material = d.Material, Color = d.Color }
			if isNight then
				d.Material = Enum.Material.Neon
			end
		end
		if d:GetAttribute("FestivalOnly") then
			festivalParts[d] = d.Transparency
			d.Transparency = if ReplicatedStorage:GetAttribute("Festival") then festivalParts[d] else 1
		end
	elseif d:IsA("Light") and d:GetAttribute("NightLight") then
		nightLights[d] = true
		d.Enabled = isNight
	elseif d:IsA("Model") and d:GetAttribute("Project") then
		projectModels[d] = tostring(d:GetAttribute("Project"))
	end
end

local function applyNight()
	for part, original in glowParts do
		if part.Parent then
			part.Material = if isNight then Enum.Material.Neon else original.Material
		end
	end
	for light in nightLights do
		if light.Parent then
			light.Enabled = isNight
		end
	end
end

local function applyFestival()
	local on = ReplicatedStorage:GetAttribute("Festival") ~= nil
	for part, transparency in festivalParts do
		if part.Parent then
			part.Transparency = if on then transparency else 1
		end
	end
end

-- Buildings behind unfinished town projects become scaffolding.
local scaffolds: { [Model]: Model } = {}
local function applyProjects()
	local projects = C.State.Get("Projects") or {}
	for model, projectId in projectModels do
		if model.Parent then
			local done = projects[projectId] and projects[projectId].Done
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = if done then 0 else 0.85
				end
			end
			if not done and not scaffolds[model] then
				local ok, cf, size = pcall(function()
					return model:GetBoundingBox()
				end)
				if ok then
					local s = Instance.new("Model")
					s.Name = "Scaffold"
					for _, corner in
						{ Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) }
					do
						local pole = Instance.new("Part")
						pole.Anchored = true
						pole.Size = Vector3.new(0.8, size.Y, 0.8)
						pole.Color = Color3.fromRGB(150, 110, 70)
						pole.Material = Enum.Material.Wood
						pole.CFrame = cf * CFrame.new(corner.X * size.X / 2, 0, corner.Z * size.Z / 2)
						pole.Parent = s
					end
					for y = 0.25, 0.75, 0.25 do
						local plank = Instance.new("Part")
						plank.Anchored = true
						plank.Size = Vector3.new(size.X, 0.5, 2)
						plank.Color = Color3.fromRGB(190, 150, 100)
						plank.Material = Enum.Material.WoodPlanks
						plank.CFrame = cf * CFrame.new(0, -size.Y / 2 + size.Y * y, size.Z / 2 + 1)
						plank.Parent = s
					end
					local sign = Instance.new("Part")
					sign.Anchored = true
					sign.Size = Vector3.new(8, 3, 0.4)
					sign.Color = Color3.fromRGB(250, 240, 210)
					sign.CFrame = cf * CFrame.new(0, -size.Y / 2 + 4, size.Z / 2 + 2)
					local gui = Instance.new("SurfaceGui")
					gui.Face = Enum.NormalId.Back
					gui.Parent = sign
					local label = Instance.new("TextLabel")
					label.Size = UDim2.fromScale(1, 1)
					label.BackgroundTransparency = 1
					label.TextScaled = true
					label.Font = Enum.Font.FredokaOne
					label.Text = "🚧 Town project"
					label.Parent = gui
					sign.Parent = s
					s.Parent = skyFolder
					scaffolds[model] = s
				end
			elseif done and scaffolds[model] then
				scaffolds[model]:Destroy()
				scaffolds[model] = nil
			end
		end
	end
end

-- Seasons -----------------------------------------------------------------------------------------------------------------

local lastSeason = -1
local function applySeason(info: any)
	if info.Season == lastSeason then
		return
	end
	lastSeason = info.Season
	local season = Seasons[info.Season]
	local palette = season.Palette
	local terrain = workspace.Terrain
	pcall(function()
		terrain:SetMaterialColor(Enum.Material.Grass, palette.Grass)
		terrain:SetMaterialColor(Enum.Material.LeafyGrass, palette.Grass:Lerp(Color3.new(0, 0, 0), 0.12))
		if season.Id == "Winter" then
			terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(214, 226, 230))
			terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(190, 206, 206))
		end
	end)
end

-- Main loop ------------------------------------------------------------------------------------------------------------

local lastWeather = ""
local nextMeteor = 0
local nextBolt = 0
local roofCheck = 0
local sheltered = false

local function step(dt: number)
	local now = GameTime.Now()
	local info = GameTime.Info(now)
	local region = LightingController.Region()
	local underground = region.Biome == "Cave" or region.Biome == "Crystal"
	Lighting.ClockTime = GameTime.HourOf(now)
	local night = info.IsNight
	if night ~= isNight then
		isNight = night
		applyNight()
		LightingController.NightChanged:Fire(isNight)
	end
	applySeason(info)

	local weather = WeatherMath.ForRegion(WeatherMath.Current(now), region)
	if underground then
		weather = "Cloudy"
	end
	if weather ~= lastWeather then
		lastWeather = weather
		currentWeather = weather
		LightingController.WeatherChanged:Fire(weather)
	end
	local def = WeatherMath.Def(weather)
	local v = def.Visual
	local season = Seasons[info.Season].Palette
	local intensity = (C.Settings.Get("WeatherIntensity") or 1)
	local particleScale = (C.Settings.Get("Particles") or 1) * intensity

	-- Atmosphere & grading
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	local grade = Lighting:FindFirstChild("Grade") :: ColorCorrectionEffect?
	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	local bright = v.Brightness
	if underground then
		Lighting.Brightness = ease("Brightness", 0, 1, dt)
		Lighting.OutdoorAmbient = ease("Ambient", Color3.fromRGB(40, 38, 48), 1, dt)
		Lighting.Ambient = ease("IndoorAmbient", Color3.fromRGB(30, 28, 36), 1, dt)
		if atmosphere then
			atmosphere.Density = ease("Density", 0.55, 1, dt)
			atmosphere.Color = ease("AtmoColor", Color3.fromRGB(40, 40, 60), 1, dt)
			atmosphere.Haze = ease("Haze", 2, 1, dt)
		end
	else
		Lighting.Brightness = ease("Brightness", 2.2 * bright + flash, 0.6, dt)
		Lighting.OutdoorAmbient =
			ease("Ambient", season.Ambient:Lerp(Color3.fromRGB(70, 74, 100), if night then 0.55 else 0), 0.6, dt)
		Lighting.Ambient = ease("IndoorAmbient", Color3.fromRGB(70, 66, 60), 0.6, dt)
		if atmosphere then
			atmosphere.Density = ease("Density", math.clamp(0.26 + v.Fog * 0.45 * intensity, 0, 0.8), 0.4, dt)
			atmosphere.Haze = ease("Haze", v.Haze + v.Fog * 2 * intensity, 0.4, dt)
			atmosphere.Color = ease("AtmoColor", season.Sky:Lerp(v.CloudColor, 0.4), 0.4, dt)
		end
	end
	if grade then
		grade.TintColor = ease("Tint", season.Tint:Lerp(v.Tint, 0.6), 0.5, dt)
		grade.Saturation = ease(
			"Saturation",
			season.Saturation + (if weather == "RainbowMist" or weather == "PollenBloom" then 0.15 else 0),
			0.5,
			dt
		)
		grade.Enabled = C.Settings.Get("PostFX") ~= false
	end
	if clouds then
		clouds.Cover = ease("Cover", if underground then 0 else v.Cover, 0.3, dt)
		clouds.Density = ease("CloudDensity", v.Density, 0.3, dt)
		clouds.Color = ease("CloudColor", v.CloudColor, 0.3, dt)
	end
	flash = math.max(0, flash - dt * 6)

	-- Precipitation around the camera (not under roofs).
	local cam = workspace.CurrentCamera.CFrame.Position
	rig.CFrame = CFrame.new(cam + Vector3.new(0, 45, 0))
	roofCheck -= dt
	if roofCheck <= 0 then
		roofCheck = 0.5
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { player.Character or workspace.CurrentCamera, rig }
		sheltered = workspace:Raycast(cam, Vector3.new(0, 40, 0), params) ~= nil
	end
	local outdoorScale = if underground then 0 elseif sheltered then 0.15 else 1
	local wanted: { [string]: number } = {
		Rain = v.Rain,
		Snow = v.Snow,
		Hail = v.Hail,
	}
	if v.Particles then
		wanted[v.Particles] = math.max(wanted[v.Particles] or 0, 1)
	end
	for name, e in emitters do
		local amount = (wanted[name] or 0) * particleScale * outdoorScale
		local def2 = PARTICLE_DEFS[name]
		local rate = ease("Rate_" .. name, amount * def2.Rate, 0.8, dt)
		e.Rate = rate
		e.Enabled = rate > 1
		if def2.Wind then
			e.Acceleration = Vector3.new(v.Wind * 12, 0, v.Wind * 4)
		end
	end

	-- Lightning, meteors, aurora, rainbow
	local t = os.clock()
	if v.Lightning and not underground and t >= nextBolt then
		nextBolt = t + random:NextNumber(6, 20)
		LightingController.Lightning(nil)
	end
	local skyShow = v.Sky
	if skyShow == "Meteors" and night and t >= nextMeteor and not underground then
		nextMeteor = t + random:NextNumber(0.4, 2)
		meteor()
	end
	updateAurora(skyShow == "Aurora" and night and not underground, t)
	setRainbow(skyShow == "Rainbow" and not night and not underground)
end

-- Festival plaza bunting (client-side decoration).
local festivalDecor: Model? = nil
local function updateFestivalDecor()
	local on = ReplicatedStorage:GetAttribute("Festival") ~= nil
	applyFestival()
	if on and not festivalDecor then
		local m = Instance.new("Model")
		m.Name = "FestivalBunting"
		local colors = {
			Color3.fromRGB(240, 90, 90),
			Color3.fromRGB(250, 200, 70),
			Color3.fromRGB(110, 190, 240),
			Color3.fromRGB(130, 210, 120),
		}
		for ring = 1, 2 do
			local r = 30 + ring * 12
			for i = 0, 47 do
				local a = i / 48 * math.pi * 2
				local p = Instance.new("WedgePart")
				p.Anchored = true
				p.CanCollide = false
				p.CanQuery = false
				p.Size = Vector3.new(0.1, 1.4, 1.2)
				p.Color = colors[i % #colors + 1]
				p.Material = Enum.Material.Fabric
				p.CFrame = CFrame.new(math.cos(a) * r, 12 + math.sin(i) * 0.6, 18 + math.sin(a) * r)
					* CFrame.Angles(math.pi, a, 0)
				p.Parent = m
			end
		end
		for i = 0, 7 do
			local a = i / 8 * math.pi * 2
			local lantern = Instance.new("Part")
			lantern.Anchored = true
			lantern.CanCollide = false
			lantern.Shape = Enum.PartType.Ball
			lantern.Size = Vector3.new(1.6, 1.6, 1.6)
			lantern.Material = Enum.Material.Neon
			lantern.Color = Color3.fromRGB(255, 190, 110)
			lantern.CFrame = CFrame.new(math.cos(a) * 40, 11, 18 + math.sin(a) * 40)
			local light = Instance.new("PointLight")
			light.Color = lantern.Color
			light.Range = 16
			light.Parent = lantern
			lantern.Parent = m
		end
		m.Parent = skyFolder
		festivalDecor = m
	elseif not on and festivalDecor then
		festivalDecor:Destroy()
		festivalDecor = nil
	end
end

function LightingController.Init()
	skyFolder = Instance.new("Folder")
	skyFolder.Name = "ClientSky"
	skyFolder.Parent = workspace
	buildRig()
end

function LightingController.Start()
	for _, d in workspace:GetDescendants() do
		register(d)
	end
	workspace.DescendantAdded:Connect(register)
	RunService.RenderStepped:Connect(function(dt)
		local ok, err = pcall(step, dt)
		if not ok then
			warn("[Evergrove] Lighting step failed:", err)
		end
	end)
	ReplicatedStorage:GetAttributeChangedSignal("Festival"):Connect(updateFestivalDecor)
	updateFestivalDecor()
	C.State.Watch("Projects", applyProjects)
	-- Projects may stream in later.
	task.spawn(function()
		while true do
			task.wait(5)
			applyProjects()
		end
	end)
end

return LightingController

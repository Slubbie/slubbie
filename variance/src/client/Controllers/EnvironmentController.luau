-- Lighting, room effects and atmosphere.
--
-- * Applies the lobby or an arena's lighting profile (client-local Lighting,
--   Atmosphere, ColorCorrection, Bloom).
-- * Escalation: setIntensity(0..1) blends toward the environment's escalation
--   targets and speeds up flicker, fans and monitor glitches; warning beacons
--   switch on at match point. The table's key light never drops below a
--   readable level, and Reduced Flashing softens every flicker.
-- * Plays server-chosen ambient events (power dips, cameras turning toward a
--   subject, vents, silhouettes, monitors, warnings, the Proctor watching).
-- * Graphics quality scales shadows, particles and post effects.
--
-- It scans a room's parts for "Fx" attributes once on entry and only updates
-- cached lists afterwards (no per-frame searches).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local Environments = require(ReplicatedStorage.Variance.Data.Environments)
local Lore = require(ReplicatedStorage.Variance.Data.Lore)
local Build = require(ReplicatedStorage.Variance.Visual.Build)

local EnvironmentController = {}

local env = Environments.Lobby
local room: Instance? = nil
local fx = {}
local intensity, targetIntensity = 0, 0
local quality = "High"
local effects: { [string]: Instance } = {}
local dip = 0 -- power dip amount (0..1), decays
local warningForced = 0 -- seconds of forced warning beacons
local monitorMode = "Calm"
local monitorOverride: { Text: string, Until: number }? = nil
local cameraTarget: { Position: Vector3, Until: number }? = nil
local silhouetteShift: { Until: number, Offset: Vector3 }? = nil
local rng = Random.new()
local clock = 0

function EnvironmentController:Init(controllers)
	self.Controllers = controllers
end

local function rgb(t, fallback)
	return Build.rgb(t, fallback)
end

local function ensure(className: string, name: string): Instance
	local existing = effects[name]
	if existing and existing.Parent then
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = Lighting
	effects[name] = inst
	return inst
end

function EnvironmentController:quality(): string
	local setting = self.Controllers.SettingsController:get("GraphicsQuality") or "Auto"
	if setting == "Auto" then
		if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
			return "Medium"
		end
		return "High"
	end
	return setting
end

local function applyProfile()
	local l = env.Lighting
	Lighting.Ambient = rgb(l.Ambient)
	Lighting.OutdoorAmbient = rgb(l.OutdoorAmbient)
	Lighting.Brightness = l.Brightness
	Lighting.ClockTime = l.ClockTime
	Lighting.ExposureCompensation = l.ExposureCompensation or 0
	Lighting.FogColor = rgb(l.FogColor)
	Lighting.FogEnd = 100000
	Lighting.GlobalShadows = quality ~= "Low"
	local atmosphere = ensure("Atmosphere", "VarianceAtmosphere") :: Atmosphere
	atmosphere.Density = l.Atmosphere.Density
	atmosphere.Offset = l.Atmosphere.Offset
	atmosphere.Color = rgb(l.Atmosphere.Color)
	atmosphere.Decay = rgb(l.Atmosphere.Decay)
	atmosphere.Haze = l.Atmosphere.Haze
	atmosphere.Glare = l.Atmosphere.Glare
	local cc = ensure("ColorCorrectionEffect", "VarianceColor") :: ColorCorrectionEffect
	cc.TintColor = rgb(l.ColorCorrection.Tint)
	cc.Contrast = l.ColorCorrection.Contrast
	cc.Saturation = l.ColorCorrection.Saturation
	cc.Brightness = l.ColorCorrection.Brightness
	local bloom = ensure("BloomEffect", "VarianceBloom") :: BloomEffect
	bloom.Enabled = quality ~= "Low"
	bloom.Intensity = l.Bloom.Intensity
	bloom.Size = l.Bloom.Size
	bloom.Threshold = l.Bloom.Threshold
	local ok = pcall(function()
		SoundService.AmbientReverb = (Enum.ReverbType :: any)[env.Audio.Reverb or "NoReverb"]
	end)
	if not ok then
		SoundService.AmbientReverb = Enum.ReverbType.NoReverb
	end
end

local function scan(model: Instance)
	fx = {
		Key = {},
		Fill = {},
		Flicker = {},
		Warning = {},
		Monitor = {},
		Spin = {},
		Camera = {},
		Silhouette = {},
		Vent = {},
		Blink = {},
		Particles = {},
		Speaker = {},
	}
	for _, d in model:GetDescendants() do
		local kind = d:GetAttribute("Fx")
		if kind == "Key" or kind == "Fill" or kind == "Flicker" then
			local light = d:FindFirstChildWhichIsA("Light")
			if light then
				table.insert(fx[kind], {
					Part = d,
					Light = light,
					Base = d:GetAttribute("BaseBrightness") or light.Brightness,
					Shadows = light.Shadows,
					Soft = d:GetAttribute("Soft") == true,
					Flick = 0,
					Material = d:IsA("BasePart") and d.Material or nil,
				})
			elseif kind == "Flicker" and d:IsA("BasePart") then
				table.insert(
					fx.Flicker,
					{ Part = d, Light = nil, Base = 0, Soft = true, Flick = 0, Transparency = d.Transparency }
				)
			end
		elseif kind == "Warning" and d:IsA("BasePart") then
			table.insert(fx.Warning, {
				Part = d,
				Light = d:FindFirstChildWhichIsA("Light"),
				Rest = d.CFrame,
				Angle = rng:NextNumber() * math.pi * 2,
			})
		elseif kind == "Monitor" then
			local gui = d:FindFirstChild("Screen")
			local label = gui and gui:FindFirstChild("Text")
			if label then
				table.insert(fx.Monitor, {
					Part = d,
					Label = label,
					Next = clock + rng:NextNumber(2, 8),
					Base = label.Text,
					Color = label.TextColor3,
				})
			end
		elseif kind == "Spin" then
			local pivot = d:GetAttribute("Pivot")
			if typeof(pivot) == "CFrame" then
				local parts = {}
				local list = d:IsA("BasePart") and { d } or d:GetDescendants()
				for _, p in list do
					if p:IsA("BasePart") and typeof(p:GetAttribute("Rest")) == "CFrame" then
						table.insert(parts, p)
					end
				end
				table.insert(fx.Spin, {
					Pivot = pivot,
					Parts = parts,
					Speed = d:GetAttribute("Speed") or 1,
					Axis = d:GetAttribute("Axis") or "Z",
					Angle = 0,
				})
			end
		elseif kind == "Camera" then
			local pivot = d:GetAttribute("Pivot")
			if typeof(pivot) == "CFrame" then
				local parts = {}
				for _, p in d:GetDescendants() do
					if p:IsA("BasePart") and typeof(p:GetAttribute("Rest")) == "CFrame" then
						table.insert(parts, p)
					end
				end
				table.insert(fx.Camera, {
					Pivot = pivot,
					Parts = parts,
					Track = d:GetAttribute("Track") == true,
					Yaw = 0,
					Pitch = 0,
					Phase = rng:NextNumber() * 10,
				})
			end
		elseif kind == "Silhouette" then
			local pivot = d:GetAttribute("Pivot")
			if typeof(pivot) == "CFrame" then
				local parts = {}
				local list = d:IsA("BasePart") and { d } or d:GetDescendants()
				for _, p in list do
					if p:IsA("BasePart") and typeof(p:GetAttribute("Rest")) == "CFrame" then
						table.insert(parts, p)
					end
				end
				table.insert(fx.Silhouette, {
					Pivot = pivot,
					Parts = parts,
					Phase = rng:NextNumber() * 10,
					Drift = d:GetAttribute("Drift") == true,
				})
			end
		elseif kind == "Vent" then
			local emitter = d:FindFirstChildWhichIsA("ParticleEmitter", true)
			if emitter then
				table.insert(fx.Vent, emitter)
			end
		elseif kind == "Blink" and d:IsA("BasePart") then
			table.insert(fx.Blink, { Part = d, Rate = d:GetAttribute("Rate") or 1, Phase = rng:NextNumber() })
		elseif kind == "Rain" or kind == "Haze" then
			local emitter = d:FindFirstChildWhichIsA("ParticleEmitter")
			if emitter then
				table.insert(fx.Particles, { Emitter = emitter, Rate = emitter.Rate })
			end
		elseif kind == "Speaker" and d:IsA("BasePart") then
			table.insert(fx.Speaker, d)
		end
	end
end

local function applyQuality()
	for _, list in { fx.Flicker or {}, fx.Fill or {} } do
		for _, entry in list do
			if entry.Light then
				entry.Light.Shadows = entry.Shadows == true and (quality == "High" or quality == "Ultra")
				entry.Light.Enabled = quality ~= "Low" or entry.Base >= 1
			end
		end
	end
	for _, p in fx.Particles or {} do
		p.Emitter.Enabled = quality ~= "Low"
		p.Emitter.Rate = quality == "Medium" and p.Rate * 0.5 or p.Rate
	end
	local bloom = effects.VarianceBloom
	if bloom then
		(bloom :: BloomEffect).Enabled = quality ~= "Low"
	end
	Lighting.GlobalShadows = quality ~= "Low"
end

function EnvironmentController:enter(model: Instance?, envId: string?)
	room = model
	env = envId and Environments.get(envId) or Environments.Lobby
	quality = self:quality()
	applyProfile()
	scan(model or workspace:FindFirstChild("Intake") or workspace)
	applyQuality()
	intensity, targetIntensity = 0, 0
	dip, warningForced = 0, 0
	monitorOverride, cameraTarget, silhouetteShift = nil, nil, nil
	local audio = self.Controllers.AudioController
	audio:setBed(env.Audio.Bed)
	audio:setHumPitch(env.Audio.HumPitch or 0.5)
end

function EnvironmentController:enterLobby()
	self:enter(workspace:FindFirstChild("Intake"), nil)
end

function EnvironmentController:setIntensity(value: number)
	targetIntensity = math.clamp(value, 0, 1)
end

function EnvironmentController:intensity(): number
	return intensity
end

-- Short global light dip (used for heavy discharges and power events).
function EnvironmentController:dim(amount: number)
	if self.Controllers.SettingsController:get("ReducedFlashing") then
		amount *= 0.4
	end
	dip = math.max(dip, amount)
end

function EnvironmentController:roomCentre(): Vector3?
	if room and room:GetAttribute("Origin") then
		local origin = room:GetAttribute("Origin") :: CFrame
		return (origin * CFrame.new(0, 2.5, 0)).Position
	end
	return nil
end

---------------------------------------------------------------------------
-- Ambient events
---------------------------------------------------------------------------

function EnvironmentController:ambient(data)
	local kind = data.Kind
	local audio = self.Controllers.AudioController
	local ui = self.Controllers.UIController
	local centre = self:roomCentre()
	local targetPos = self.Controllers.MatchPresenter and self.Controllers.MatchPresenter:subjectHead(data.Target)
	if kind == "PowerDip" then
		audio:play("PowerDown", { At = centre })
		self:dim(0.75)
		task.delay(1.1, function()
			audio:play("DistantThud", { At = centre })
		end)
	elseif kind == "CameraTurn" then
		if targetPos then
			cameraTarget = { Position = targetPos, Until = clock + 4 }
		end
		audio:play("Creak", { At = centre, Pitch = 1.8 })
	elseif kind == "Monitor" then
		local pool = Lore.Monitors[monitorMode] or Lore.Monitors.Calm
		monitorOverride = { Text = pool[rng:NextInteger(1, #pool)], Until = clock + 5 }
	elseif kind == "Vent" then
		for _, emitter in fx.Vent or {} do
			if quality ~= "Low" then
				emitter:Emit(24)
			end
		end
		audio:play("Vent", { At = centre })
	elseif kind == "Announcement" then
		audio:announce()
		local line = Lore.Broadcasts[rng:NextInteger(1, #Lore.Broadcasts)]
		ui:subtitle(nil, line, 4.5)
	elseif kind == "Silhouette" then
		silhouetteShift = { Until = clock + 5, Offset = Vector3.new(rng:NextNumber(-3, 3), 0, 0) }
		audio:play("Creak", { At = centre })
	elseif kind == "Warning" then
		warningForced = 2.5
		audio:play("Alarm", { At = centre })
		audio:play("Alarm", { At = centre, Delay = 0.6 })
	elseif kind == "ProctorWatching" then
		monitorOverride = { Text = "I AM WATCHING", Until = clock + 8, Proctor = true }
		cameraTarget = targetPos and { Position = targetPos, Until = clock + 8 } or nil
		self:dim(0.5)
		audio:play("Surge", { At = centre })
		ui:subtitle(nil, data.Text or "THE PROCTOR IS WATCHING THIS TRIAL.", 5)
	elseif kind == "ObserverSurge" or kind == "Sublevel7" then
		monitorOverride = { Text = data.Text or "", Until = clock + 6 }
		audio:play("Alarm", { At = centre, Pitch = 0.8 })
	end
end

---------------------------------------------------------------------------
-- Per-frame
---------------------------------------------------------------------------

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function glitch(text: string, amount: number): string
	if amount <= 0 then
		return text
	end
	local chars = {}
	for i = 1, #text do
		local ch = string.sub(text, i, i)
		if ch ~= " " and rng:NextNumber() < amount then
			ch = string.char(rng:NextInteger(33, 90))
		end
		chars[i] = ch
	end
	return table.concat(chars)
end

local function update(self, dt: number)
	clock += dt
	intensity += (targetIntensity - intensity) * math.min(1, dt * 0.8)
	dip = math.max(0, dip - dt * 1.6)
	warningForced = math.max(0, warningForced - dt)
	local reducedFlashing = self.Controllers.SettingsController:get("ReducedFlashing") == true
	local esc = env.Escalation
	local base = env.Lighting

	-- Colour grading toward the escalation targets.
	local cc = effects.VarianceColor :: ColorCorrectionEffect?
	if cc then
		cc.TintColor = rgb(base.ColorCorrection.Tint):Lerp(rgb(esc.Tint), intensity)
		cc.Contrast = lerp(base.ColorCorrection.Contrast, esc.Contrast, intensity)
		cc.Saturation = lerp(base.ColorCorrection.Saturation, esc.Saturation, intensity)
		cc.Brightness = -0.25 * dip
	end
	local atmosphere = effects.VarianceAtmosphere :: Atmosphere?
	if atmosphere then
		atmosphere.Density = lerp(base.Atmosphere.Density, esc.Density, intensity) * (quality == "Low" and 0.7 or 1)
	end

	-- Lights: the key light stays readable; others flicker with tension.
	local flickerRate = lerp(esc.FlickerMin, esc.FlickerMax, intensity) * (reducedFlashing and 0.3 or 1)
	for _, entry in fx.Key or {} do
		local breathe = 1 + math.sin(clock * 1.3) * 0.02
		entry.Light.Brightness = entry.Base * breathe * (1 - 0.45 * dip)
	end
	for _, entry in fx.Fill or {} do
		entry.Light.Brightness = entry.Base * (1 - 0.8 * dip)
	end
	for _, entry in fx.Flicker or {} do
		if entry.Flick > 0 then
			entry.Flick -= dt
		elseif rng:NextNumber() < flickerRate * dt * (entry.Soft and 0.4 or 1) then
			entry.Flick = rng:NextNumber(0.08, 0.35)
		end
		local level = 1
		if entry.Flick > 0 then
			local depth = reducedFlashing and 0.35 or 0.85
			level = (math.sin(clock * 60) > 0) and (1 - depth) or 1
		end
		level *= (1 - 0.9 * dip)
		if entry.Light then
			entry.Light.Brightness = entry.Base * level
		end
		if entry.Part:IsA("BasePart") and entry.Material == Enum.Material.Neon then
			entry.Part.Transparency = (1 - level) * 0.7
		end
	end

	-- Warning beacons at match point (or when an event forces them).
	local warningOn = intensity >= 0.8 or warningForced > 0
	for _, entry in fx.Warning or {} do
		if entry.Light then
			entry.Light.Brightness = warningOn and (reducedFlashing and 1.2 or 3) or 0
		end
		if warningOn then
			entry.Angle += dt * 5
			entry.Part.CFrame = entry.Rest * CFrame.Angles(0, entry.Angle, 0)
		end
	end

	-- Fans, rings, clocks.
	for _, entry in fx.Spin or {} do
		entry.Angle += dt * entry.Speed * (1 + intensity * 1.5)
		local rot = entry.Axis == "Y" and CFrame.Angles(0, entry.Angle, 0)
			or (entry.Axis == "X" and CFrame.Angles(entry.Angle, 0, 0) or CFrame.Angles(0, 0, entry.Angle))
		local pivot = entry.Pivot * rot
		for _, p in entry.Parts do
			p.CFrame = pivot * (p:GetAttribute("Rest") :: CFrame)
		end
	end

	-- Cameras: slow idle sweeps; turn toward a subject during events; lobby
	-- cameras quietly follow the local character.
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	for _, entry in fx.Camera or {} do
		local yaw = math.sin(clock * 0.25 + entry.Phase) * 0.5
		local pitch = 0
		local look = nil
		if cameraTarget and cameraTarget.Until > clock then
			look = cameraTarget.Position
		elseif entry.Track and root and (root.Position - entry.Pivot.Position).Magnitude < 70 then
			look = root.Position
		end
		if look then
			local localDir = entry.Pivot:PointToObjectSpace(look).Unit
			yaw = math.atan2(-localDir.X, -localDir.Z)
			pitch = math.asin(math.clamp(localDir.Y, -1, 1))
		end
		entry.Yaw += (yaw - entry.Yaw) * math.min(1, dt * 2)
		entry.Pitch += (pitch - entry.Pitch) * math.min(1, dt * 2)
		local pivot = entry.Pivot * CFrame.Angles(0, entry.Yaw, 0) * CFrame.Angles(entry.Pitch, 0, 0)
		for _, p in entry.Parts do
			p.CFrame = pivot * (p:GetAttribute("Rest") :: CFrame)
		end
	end
	if cameraTarget and cameraTarget.Until <= clock then
		cameraTarget = nil
	end

	-- Figures behind glass: barely there, until they aren't.
	for _, entry in fx.Silhouette or {} do
		local sway = CFrame.new(math.sin(clock * 0.4 + entry.Phase) * 0.08, 0, 0)
		if entry.Drift then
			sway = CFrame.new(0, math.sin(clock * 0.3 + entry.Phase) * 0.3, 0) * CFrame.Angles(0, clock * 0.05, 0)
		end
		if silhouetteShift and silhouetteShift.Until > clock then
			local t = 1 - (silhouetteShift.Until - clock) / 5
			sway *= CFrame.new(silhouetteShift.Offset * math.sin(t * math.pi))
		end
		local pivot = entry.Pivot * sway
		for _, p in entry.Parts do
			p.CFrame = pivot * (p:GetAttribute("Rest") :: CFrame)
		end
	end

	-- Blinking server LEDs.
	for _, entry in fx.Blink or {} do
		local on = math.sin((clock + entry.Phase) * entry.Rate * 6) > 0.2
		entry.Part.Transparency = on and 0 or 0.8
	end

	-- Monitors.
	monitorMode = intensity >= 0.8 and "Critical" or (intensity >= 0.4 and "Tense" or "Calm")
	for _, entry in fx.Monitor or {} do
		if monitorOverride and monitorOverride.Until > clock then
			entry.Label.Text = glitch(monitorOverride.Text, 0.04)
			entry.Label.TextColor3 = monitorOverride.Proctor and Color3.fromRGB(255, 70, 60) or entry.Color
		elseif clock >= entry.Next then
			entry.Label.TextColor3 = entry.Color
			entry.Next = clock + rng:NextNumber(5, 11)
			local pool = Lore.Monitors[monitorMode]
			entry.Label.Text = pool[rng:NextInteger(1, #pool)]
		elseif intensity > 0.5 and rng:NextNumber() < dt * intensity * 0.6 then
			entry.Label.Text = glitch(entry.Label.Text, 0.15 * intensity)
		end
	end
	if monitorOverride and monitorOverride.Until <= clock then
		monitorOverride = nil
	end
end

function EnvironmentController:Start()
	local settings = self.Controllers.SettingsController
	settings.Changed:Connect(function(key)
		if key == "GraphicsQuality" or key == "*" then
			quality = self:quality()
			applyProfile()
			applyQuality()
		end
	end)
	-- Wait for the lobby to stream in, then apply its look.
	task.spawn(function()
		workspace:WaitForChild("Intake", 30)
		if room == nil then
			self:enterLobby()
		end
	end)
	self:enterLobby()
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 1 / 30 then
			update(self, accumulator)
			accumulator = 0
		end
	end)
	self.Controllers.NetworkClient:onMatch("Ambient", function(data)
		self:ambient(data)
	end)
end

return EnvironmentController

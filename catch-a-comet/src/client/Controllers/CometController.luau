-- Draws every comet the server tells us about and turns it into something
-- you can walk up to:
--
--   falling → a glowing head with a ribbon trail streaks in from the sky
--             while a ring telegraphs the landing spot
--   impact  → shockwave, dust, sparks, a light flash, a thud and a camera
--             nudge if you're close
--   landed  → a scorched crater with a floating core, a light pillar visible
--             from far away, a marker with distance, and the capture prompt
--
-- The scanner (by level) locks onto comets within its radius: highlight,
-- type/payout and time readouts, and a guide beam at level 4. All of this is
-- client-side presentation; the server owns comet state and rewards.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BiomeDefinitions = require(Shared.BiomeDefinitions)
local Format = require(Shared.Format)
local GameConfig = require(Shared.GameConfig)
local RemoteDefinitions = require(Shared.RemoteDefinitions)
local Signal = require(Shared.Signal)
local UpgradeDefinitions = require(Shared.UpgradeDefinitions)
local WorldLayout = require(Shared.WorldLayout)

local CometController = {}

-- (view)
CometController.Landed = Signal.new()
-- (view)
CometController.Removed = Signal.new()
-- (view) entered scanner range
CometController.Locked = Signal.new()

export type View = {
	Data: { [string]: any },
	Type: GameConfig.CometType,
	State: string, -- "Falling" | "Landed" | "Gone"
	Claimed: boolean,
	Head: Model?,
	Telegraph: BasePart?,
	Site: Model?,
	Core: BasePart?,
	CoreBase: CFrame?,
	Pillar: BasePart?,
	Marker: BillboardGui?,
	MarkerTitle: TextLabel?,
	MarkerInfo: TextLabel?,
	Prompt: ProximityPrompt?,
	Highlight: Highlight?,
	InRange: boolean,
	Area: string,
}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local controllers: { [string]: any } = {}
local views: { [string]: View } = {}
local folder: Folder
local guideBeam: Beam? = nil
local guideTarget: Attachment? = nil
local markerClock = 0

local function now(): number
	return workspace:GetServerTimeNow()
end

local function localRoot(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function scannerLevel(): number
	return controllers.ClientState.Equipment().ScannerLevel or 1
end

function CometController.ScannerRadius(): number
	return UpgradeDefinitions.ScannerRadius(scannerLevel())
end

local function hasFeature(feature: string): boolean
	return UpgradeDefinitions.HasFeature("Scanner", scannerLevel(), feature)
end

local function part(name: string, size: Vector3, color: Color3, material: Enum.Material, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function ball(name: string, diameter: number, color: Color3, material: Enum.Material, parent: Instance): Part
	local p = part(name, Vector3.new(diameter, diameter, diameter), color, material, parent)
	p.Shape = Enum.PartType.Ball
	return p
end

local function particles(): number
	return controllers.SettingsController.Quality().Particles
end

-- Falling --------------------------------------------------------------------------

local function startPoint(view: View): Vector3
	local data = view.Data
	return data.Position + (data.Entry :: Vector3) * 520 + Vector3.new(0, 430, 0)
end

local function buildHead(view: View)
	local size = 3.2 * view.Type.Size
	local model = Instance.new("Model")
	model.Name = "CometHead"
	local core = ball("Core", size, view.Type.Color, Enum.Material.Neon, model)
	local glow = ball("Glow", size * 1.9, view.Type.TrailColor, Enum.Material.Neon, model)
	glow.Transparency = 0.65
	model.PrimaryPart = core
	local light = Instance.new("PointLight")
	light.Color = view.Type.Color
	light.Range = 45
	light.Brightness = 3
	light.Parent = core
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, size * 0.55, 0)
	top.Parent = core
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -size * 0.55, 0)
	bottom.Parent = core
	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 1.3
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1), view.Type.TrailColor)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.1) })
	trail.Parent = core
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARKLE
	sparks.LightEmission = 1
	sparks.Color = ColorSequence.new(view.Type.TrailColor)
	sparks.Rate = 60 * particles()
	sparks.Lifetime = NumberRange.new(0.6, 1.2)
	sparks.Speed = NumberRange.new(2, 6)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.35), NumberSequenceKeypoint.new(1, 0) })
	sparks.Parent = core
	local whoosh = Instance.new("Sound")
	local def = GameConfig.Audio.Sounds.CometFall
	whoosh.SoundId = def.Id
	whoosh.PlaybackSpeed = def.Pitch
	whoosh.Volume = def.Volume
	whoosh.RollOffMinDistance = 40
	whoosh.RollOffMaxDistance = 700
	whoosh.Parent = core
	model.Parent = folder
	whoosh:Play()
	view.Head = model

	-- A pulsing ring marks where it will land.
	local ring = part("Telegraph", Vector3.new(0.2, 12, 12), view.Type.Color, Enum.Material.Neon, folder)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.5
	ring.CFrame = CFrame.new(view.Data.Position + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.rad(90))
	view.Telegraph = ring
end

local function updateFall(view: View, t: number)
	local head = view.Head
	if not head or not head.PrimaryPart then
		return
	end
	local from = startPoint(view)
	local to = view.Data.Position + Vector3.new(0, 1.5, 0)
	local eased = t ^ 1.6
	local position = from:Lerp(to, eased)
	local ahead = from:Lerp(to, math.min(1, (t + 0.02) ^ 1.6))
	local cf = if (ahead - position).Magnitude > 0.01 then CFrame.lookAt(position, ahead) else CFrame.new(position)
	head:PivotTo(cf)
	if view.Telegraph then
		local pulse = 0.5 + 0.25 * math.sin(os.clock() * 10)
		view.Telegraph.Transparency = pulse
		local d = 10 + 4 * t
		view.Telegraph.Size = Vector3.new(0.2, d, d)
	end
end

-- Landed site ------------------------------------------------------------------------

local function buildMarker(view: View, core: BasePart)
	local gui = Instance.new("BillboardGui")
	gui.Name = "CometMarker"
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Size = UDim2.fromOffset(210, 58)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 5.5, 0)
	gui.MaxDistance = 1200
	gui.Adornee = core
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 30)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = view.Type.Color:Lerp(Color3.new(1, 1, 1), 0.4)
	title.Text = "☄️"
	title.Parent = gui
	local info = Instance.new("TextLabel")
	info.Name = "Info"
	info.BackgroundTransparency = 1
	info.Position = UDim2.fromOffset(0, 30)
	info.Size = UDim2.new(1, 0, 0, 22)
	info.Font = Enum.Font.BuilderSansBold
	info.TextScaled = true
	info.TextColor3 = Color3.fromRGB(245, 247, 255)
	info.Text = ""
	info.Parent = gui
	for _, label in { title, info } do
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(11, 16, 40)
		stroke.Thickness = 2
		stroke.Parent = label
	end
	gui.Parent = core
	view.Marker = gui
	view.MarkerTitle = title
	view.MarkerInfo = info
end

local function buildSite(view: View)
	local data = view.Data
	local size = view.Type.Size
	local model = Instance.new("Model")
	model.Name = "CometSite_" .. data.Id
	local ground = data.Position
	local scorch =
		part("Scorch", Vector3.new(0.2, 11 * size, 11 * size), Color3.fromRGB(46, 34, 70), Enum.Material.Slate, model)
	scorch.Shape = Enum.PartType.Cylinder
	scorch.Transparency = 0.2
	scorch.CFrame = CFrame.new(ground + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90))
	for i = 0, 6 do
		local a = i / 7 * math.pi * 2
		local rock = ball("Rock", 1.2 + (i % 3) * 0.5, Color3.fromRGB(90, 76, 120), Enum.Material.Slate, model)
		rock.Position = ground + Vector3.new(math.cos(a) * 5 * size, 0.3, math.sin(a) * 5 * size)
	end
	local base = CFrame.new(ground + Vector3.new(0, 2.8 * size, 0))
	local core = ball("Core", 2.2 * size, view.Type.Color, Enum.Material.Neon, model)
	core.CFrame = base
	local shell = ball("Shell", 3.3 * size, view.Type.TrailColor, Enum.Material.Glass, model)
	shell.Transparency = 0.45
	shell.CFrame = base
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = core
	weld.Part1 = shell
	weld.Parent = shell
	shell.Anchored = false
	local light = Instance.new("PointLight")
	light.Color = view.Type.Color
	light.Range = 20
	light.Brightness = 1.6
	light.Parent = core
	local glitter = Instance.new("ParticleEmitter")
	glitter.Texture = SPARKLE
	glitter.LightEmission = 1
	glitter.Color = ColorSequence.new(view.Type.Color)
	glitter.Rate = 8 * particles()
	glitter.Lifetime = NumberRange.new(1, 2)
	glitter.Speed = NumberRange.new(1, 3)
	glitter.SpreadAngle = Vector2.new(180, 180)
	glitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	glitter.Parent = core
	local attachment = Instance.new("Attachment")
	attachment.Name = "TetherTarget"
	attachment.Parent = core
	model.PrimaryPart = core
	model.Parent = folder

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CapturePrompt"
	prompt.ActionText = "Stabilize"
	prompt.ObjectText = "Comet"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = GameConfig.Comets.CaptureDistance - 1
	prompt:SetAttribute("CometId", data.Id)
	prompt.Parent = core
	prompt.Triggered:Connect(function()
		controllers.CaptureController.Begin(data.Id)
	end)

	view.Site = model
	view.Core = core
	view.CoreBase = base
	view.Prompt = prompt
	view.Pillar = controllers.EffectsController.Pillar(ground, view.Type.Color, 180, 2.4 * size)
	buildMarker(view, core)
end

local function applyClaimed(view: View)
	if view.Prompt then
		view.Prompt.Enabled = false
	end
	if view.Core then
		view.Core.Color = view.Core.Color:Lerp(Color3.fromRGB(140, 140, 170), 0.6)
	end
	if view.Pillar then
		local beam = view.Pillar:FindFirstChildOfClass("Beam")
		if beam then
			beam.Color = ColorSequence.new(Color3.fromRGB(150, 150, 180))
			beam.Width0 = 0.8
			beam.Width1 = 1.2
		end
	end
	if view.Highlight then
		view.Highlight:Destroy()
		view.Highlight = nil
	end
end

local function impact(view: View)
	local position = view.Data.Position
	if view.Head then
		view.Head:Destroy()
		view.Head = nil
	end
	if view.Telegraph then
		view.Telegraph:Destroy()
		view.Telegraph = nil
	end
	local fx = controllers.EffectsController
	local color = view.Type.Color
	fx.Shockwave(position, color, 26 * view.Type.Size, 0.7)
	fx.Burst(position + Vector3.new(0, 1, 0), Color3.fromRGB(220, 200, 255), 24, "Dust")
	fx.Burst(position + Vector3.new(0, 1.5, 0), color, 40, "Sparks")
	fx.Flash(position + Vector3.new(0, 4, 0), color, 8, 70, 0.9)
	controllers.AudioController.PlayAt("CometImpact", position, { Pitch = 0.42 - view.Type.Size * 0.06 })
	local root = localRoot()
	if root then
		local d = (root.Position - position).Magnitude
		if d < 150 then
			controllers.CameraController.Shake(1.4 * (1 - d / 150) * view.Type.Size, 0.5)
		end
	end
	buildSite(view)
	view.State = "Landed"
	if view.Claimed then
		applyClaimed(view)
	end
	CometController.Landed:Fire(view)
end

-- Registry -------------------------------------------------------------------------

local function add(data: { [string]: any })
	if views[data.Id] then
		return
	end
	local cometType = GameConfig.Comets.Types[data.Type] or GameConfig.Comets.Types.Ember
	local view: View = {
		Data = data,
		Type = cometType,
		State = "Falling",
		Claimed = data.Claimed == true,
		InRange = false,
		Area = WorldLayout.GetArea(data.Position).Id,
	}
	views[data.Id] = view
	if now() >= data.ImpactTime then
		-- Already down (joined late): skip the fall.
		buildSite(view)
		view.State = "Landed"
		if view.Claimed then
			applyClaimed(view)
		end
		CometController.Landed:Fire(view)
	else
		buildHead(view)
	end
end

local function remove(id: string)
	local view = views[id]
	if not view then
		return
	end
	views[id] = nil
	view.State = "Gone"
	for _, instance in { view.Head, view.Telegraph, view.Pillar } do
		if instance then
			instance:Destroy()
		end
	end
	local site = view.Site
	if site then
		if view.Prompt then
			view.Prompt.Enabled = false
		end
		if view.Core then
			TweenService:Create(view.Core, TweenInfo.new(0.6), { Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1 })
				:Play()
		end
		task.delay(0.7, function()
			site:Destroy()
		end)
	end
	CometController.Removed:Fire(view)
end

local function markClaimed(id: string)
	local view = views[id]
	if view then
		view.Claimed = true
		if view.State == "Landed" then
			applyClaimed(view)
		end
	end
end

function CometController.Get(id: string): View?
	return views[id]
end

function CometController.All(): { [string]: View }
	return views
end

function CometController.TutorialComet(): View?
	for _, view in views do
		if view.Data.IsTutorial then
			return view
		end
	end
	return nil
end

-- Nearest landed, uncaptured comet to a position (optionally in the same area).
function CometController.Nearest(position: Vector3, sameArea: boolean?): (View?, number)
	local best, bestDistance = nil, math.huge
	local area = if sameArea then WorldLayout.GetArea(position).Id else nil
	for _, view in views do
		if view.State ~= "Landed" or view.Claimed then
			continue
		end
		if area and view.Area ~= area and not (area == "Hub" and view.Data.IsTutorial) then
			continue
		end
		local d = (view.Data.Position - position).Magnitude
		if d < bestDistance then
			best, bestDistance = view, d
		end
	end
	return best, bestDistance
end

local function payoutText(view: View): string
	local biome = BiomeDefinitions.Get(view.Data.Biome)
	local base = if biome then biome.CaptureStardust else 0
	return `{view.Type.DisplayName} · ~{Format.Short(math.floor(base * view.Type.StardustMult))}+ ✦`
end

local function updateMarkers(root: BasePart?)
	local radius = CometController.ScannerRadius()
	local typeReadout = hasFeature("TypeReadout")
	local timeReadout = hasFeature("TimeReadout")
	local t = now()
	for _, view in views do
		if view.State ~= "Landed" or not view.Marker then
			continue
		end
		local title, info = view.MarkerTitle :: TextLabel, view.MarkerInfo :: TextLabel
		if view.Claimed then
			title.Text = "✓ Captured"
			info.Text = ""
			continue
		end
		local d = if root then (root.Position - view.Data.Position).Magnitude else math.huge
		local inRange = d <= radius
		if inRange ~= view.InRange then
			view.InRange = inRange
			if inRange then
				local highlight = Instance.new("Highlight")
				highlight.FillTransparency = 0.75
				highlight.OutlineColor = Color3.fromRGB(116, 229, 254)
				highlight.FillColor = view.Type.Color
				highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				highlight.Adornee = view.Site
				highlight.Parent = view.Site
				view.Highlight = highlight
				CometController.Locked:Fire(view)
				controllers.AudioController.Play("LockHit", { Pitch = 2.2, Volume = 0.6 })
			elseif view.Highlight then
				view.Highlight:Destroy()
				view.Highlight = nil
			end
		end
		title.Text = if inRange then "☄️ LOCKED" else `☄️ {math.floor(d)}m`
		local parts = {}
		if typeReadout or inRange then
			table.insert(parts, payoutText(view))
		end
		if timeReadout then
			table.insert(parts, Format.Duration(view.Data.ExpireTime - t))
		end
		if view.Data.IsTutorial then
			parts = { "Your first comet!" }
		end
		info.Text = table.concat(parts, "  ·  ")
		if view.Prompt then
			view.Prompt.ObjectText = if typeReadout or inRange then `{view.Type.DisplayName} Comet` else "Comet"
		end
	end
end

local function updateGuideBeam(root: BasePart?)
	if not root or not hasFeature("GuideBeam") then
		if guideBeam then
			guideBeam.Enabled = false
		end
		return
	end
	local target = CometController.Nearest(root.Position, true)
	if not target or not target.Core then
		if guideBeam then
			guideBeam.Enabled = false
		end
		return
	end
	if not guideBeam or not guideBeam.Parent then
		local beam = Instance.new("Beam")
		beam.Name = "ScannerGuide"
		beam.Width0 = 0.25
		beam.Width1 = 0.6
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.Segments = 12
		beam.CurveSize0 = 8
		beam.CurveSize1 = -8
		beam.Color = ColorSequence.new(Color3.fromRGB(116, 229, 254))
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.8),
			NumberSequenceKeypoint.new(0.5, 0.45),
			NumberSequenceKeypoint.new(1, 0.9),
		})
		beam.Parent = folder
		guideBeam = beam
	end
	local beam = guideBeam :: Beam
	local from = root:FindFirstChild("ScannerGuideFrom") :: Attachment?
	if not from then
		local attachment = Instance.new("Attachment")
		attachment.Name = "ScannerGuideFrom"
		attachment.Parent = root
		from = attachment
	end
	guideTarget = target.Core:FindFirstChild("TetherTarget") :: Attachment?
	beam.Attachment0 = from
	beam.Attachment1 = guideTarget
	beam.Enabled = guideTarget ~= nil
end

local function step(dt: number)
	local t = now()
	for _, view in views do
		if view.State == "Falling" then
			local duration = math.max(view.Data.ImpactTime - view.Data.SpawnTime, 0.1)
			local progress = (t - view.Data.SpawnTime) / duration
			if progress >= 1 then
				impact(view)
			else
				updateFall(view, math.max(progress, 0))
			end
		elseif view.State == "Landed" and view.Core and view.CoreBase then
			local bob = math.sin(os.clock() * 2 + view.Data.Position.X) * 0.35
			view.Core.CFrame = view.CoreBase * CFrame.new(0, bob, 0) * CFrame.Angles(0, os.clock() * 0.8, 0)
		end
	end
	markerClock += dt
	if markerClock >= 0.1 then
		markerClock = 0
		local root = localRoot()
		updateMarkers(root)
		updateGuideBeam(root)
	end
end

function CometController.Init(registry: { [string]: any })
	controllers = registry
	folder = Instance.new("Folder")
	folder.Name = "Comets"
	folder.Parent = workspace
end

function CometController.Start()
	for _, data in controllers.ClientState.InitialComets do
		add(data)
	end
	RemoteDefinitions.GetEvent("CometBroadcast").OnClientEvent:Connect(function(kind, payload)
		if type(payload) ~= "table" then
			return
		end
		if kind == "Spawn" then
			add(payload)
		elseif kind == "Expire" then
			remove(payload.Id)
		elseif kind == "Claimed" then
			markClaimed(payload.Id)
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return CometController

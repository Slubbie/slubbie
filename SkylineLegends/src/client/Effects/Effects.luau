-- Visual feedback: trails that wake up at speed, cosmetic landing effects for
-- every runner, speed lines, the grapple target marker, bursts for dashes and
-- double jumps, and an aura that grows with your flow tier.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Tags = require(ReplicatedStorage.Shared.Tags)

local Input = require(script.Parent.Parent.Core.Input)
local Settings = require(script.Parent.Parent.Core.Settings)
local Controller = require(script.Parent.Parent.Movement.Controller)
local Flow = require(script.Parent.Parent.Gameplay.Flow)

local player = Players.LocalPlayer

local Effects = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local fxFolder = Instance.new("Folder")
fxFolder.Name = "SkylineFx"

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function anchorAt(position: Vector3, lifetime: number): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = CFrame.new(position)
	part.CollisionGroup = Tags.Groups.Cosmetic
	part.Parent = fxFolder
	Debris:AddItem(part, lifetime)
	return part
end

local function burst(position: Vector3, options: { [string]: any })
	local part = anchorAt(position, 3)
	local e = Instance.new("ParticleEmitter")
	e.Texture = options.Texture or SMOKE
	e.Color = ColorSequence.new(options.Color or rgb(220, 215, 205))
	e.Size = options.Size or NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 2) })
	e.Transparency = options.Transparency or NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	e.Speed = options.Speed or NumberRange.new(6, 12)
	e.Lifetime = options.Lifetime or NumberRange.new(0.35, 0.7)
	e.SpreadAngle = options.Spread or Vector2.new(80, 10)
	e.Acceleration = options.Acceleration or Vector3.new(0, 2, 0)
	e.Drag = options.Drag or 4
	e.LightEmission = options.LightEmission or 0
	e.RotSpeed = options.RotSpeed or NumberRange.new(-90, 90)
	e.EmissionDirection = options.Direction or Enum.NormalId.Top
	e.Enabled = false
	e.Parent = part
	e:Emit(options.Count or 12)
end

local function ring(position: Vector3, color: Color3, radius: number, duration: number, thickness: number?)
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = 0.2
	part.Size = Vector3.new(thickness or 0.12, 1, 1)
	part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	part.Parent = fxFolder
	TweenService:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(thickness or 0.12, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(part, duration + 0.1)
end

-- Landing effects ----------------------------------------------------------------------------------

local MATERIAL_DUST: { [string]: Color3 } = {
	Snow = rgb(245, 250, 255),
	Glacier = rgb(220, 240, 255),
	Ice = rgb(220, 240, 255),
	Grass = rgb(120, 150, 80),
	LeafyGrass = rgb(110, 150, 70),
	Ground = rgb(140, 110, 80),
	Mud = rgb(100, 80, 60),
	Sand = rgb(220, 200, 150),
	Water = rgb(170, 210, 240),
}

function Effects.Landing(feet: Vector3, impact: number, style: string?, color: Color3?, material: Enum.Material?)
	local strength = math.clamp(impact / 90, 0.25, 1.4)
	local dustColor = (material and MATERIAL_DUST[material.Name]) or rgb(210, 205, 195)
	local kind = style or "Dust"
	if kind == "Dust" or impact > 70 then
		burst(feet, { Color = dustColor, Count = math.floor(8 + 14 * strength) })
	end
	if kind == "Ripple" then
		ring(feet + Vector3.new(0, 0.1, 0), color or rgb(120, 220, 255), 3 + 3 * strength, 0.45)
	elseif kind == "Shockwave" then
		ring(feet + Vector3.new(0, 0.1, 0), color or rgb(255, 210, 120), 5 + 6 * strength, 0.5, 0.2)
		ring(feet + Vector3.new(0, 0.3, 0), color or rgb(255, 240, 200), 3 + 3 * strength, 0.35)
	elseif kind == "Sparks" then
		burst(feet, {
			Texture = SPARKLE,
			Color = color or rgb(255, 200, 90),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) }),
			Speed = NumberRange.new(14, 26),
			Lifetime = NumberRange.new(0.3, 0.6),
			Acceleration = Vector3.new(0, -60, 0),
			LightEmission = 1,
			Spread = Vector2.new(70, 70),
			Count = math.floor(14 + 10 * strength),
		})
	elseif kind == "Petals" then
		burst(feet + Vector3.new(0, 0.5, 0), {
			Color = color or rgb(255, 170, 200),
			Size = NumberSequence.new(0.35),
			Speed = NumberRange.new(5, 10),
			Lifetime = NumberRange.new(1, 1.6),
			Acceleration = Vector3.new(0, -4, 0),
			Spread = Vector2.new(80, 80),
			RotSpeed = NumberRange.new(-300, 300),
			Count = 18,
		})
	elseif kind == "Prism" then
		for i = 0, 2 do
			ring(feet + Vector3.new(0, 0.1 + i * 0.15, 0), Color3.fromHSV((os.clock() * 0.3 + i * 0.33) % 1, 0.6, 1), 2.5 + i * 1.6, 0.4 + i * 0.08)
		end
	elseif kind == "Snow" then
		burst(feet, {
			Texture = SPARKLE,
			Color = rgb(255, 255, 255),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) }),
			Speed = NumberRange.new(8, 16),
			Lifetime = NumberRange.new(0.6, 1.1),
			Acceleration = Vector3.new(0, -20, 0),
			Spread = Vector2.new(60, 60),
			Count = 24,
		})
	end
end

-- Trails -------------------------------------------------------------------------------------------

local function updateTrails()
	local mode = Settings.Get("Trails") or "All"
	for _, target in Players:GetPlayers() do
		local character = target.Character
		local folder = character and character:FindFirstChild("SkylineCosmetics")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if folder and root and root:IsA("BasePart") then
			local speed = if target == player then Controller.Info.Speed else Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
			local visible = mode == "All" or (mode == "Mine" and target == player)
			local on = visible and speed > 22
			local trail = folder:FindFirstChild("SkylineTrail")
			if trail and trail:IsA("Trail") then
				trail.Enabled = on
			end
			local torso = character:FindFirstChild("Torso")
			local bottom = torso and torso:FindFirstChild("TrailBottom")
			local particles = bottom and bottom:FindFirstChild("SkylineTrailParticles")
			if particles and particles:IsA("ParticleEmitter") then
				particles.Rate = if on then math.clamp((speed - 22) * 2, 4, 60) else 0
			end
		end
	end
end

-- Speed lines --------------------------------------------------------------------------------------

local speedParts: { Part } = {}
local function makeSpeedLines()
	for i = 1, 4 do
		local part = Instance.new("Part")
		part.Name = "SpeedLines" .. i
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		local e = Instance.new("ParticleEmitter")
		e.Texture = SPARKLE
		e.Color = ColorSequence.new(rgb(255, 255, 255))
		e.LightEmission = 0.6
		e.LightInfluence = 0
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.55), NumberSequenceKeypoint.new(1, 1) })
		e.Size = NumberSequence.new(0.09)
		e.Squash = NumberSequence.new(-2.8)
		e.Orientation = Enum.ParticleOrientation.VelocityParallel
		e.EmissionDirection = Enum.NormalId.Back
		e.Speed = NumberRange.new(60, 90)
		e.Lifetime = NumberRange.new(0.25, 0.4)
		e.LockedToPart = true
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.Rate = 0
		e.Parent = part
		speedParts[i] = part
	end
end

local function updateSpeedLines()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local speed = Controller.Info.Velocity.Magnitude
	local on = Settings.Motion("SpeedLines") and speed > 45
	local rate = if on then math.clamp((speed - 45) * 4, 0, 160) else 0
	local layout = {
		{ CFrame.new(0, 9, -24), Vector3.new(36, 3, 6) },
		{ CFrame.new(0, -9, -24), Vector3.new(36, 3, 6) },
		{ CFrame.new(-15, 0, -24), Vector3.new(4, 18, 6) },
		{ CFrame.new(15, 0, -24), Vector3.new(4, 18, 6) },
	}
	for i, part in speedParts do
		part.Size = layout[i][2]
		part.CFrame = camera.CFrame * layout[i][1]
		part.Parent = camera
		local e = part:FindFirstChildOfClass("ParticleEmitter")
		if e then
			e.Rate = rate
		end
	end
end

-- Grapple target -------------------------------------------------------------------------------------

local highlight = Instance.new("Highlight")
highlight.Name = "SkylineGrappleTarget"
highlight.FillColor = rgb(120, 235, 255)
highlight.FillTransparency = 0.55
highlight.OutlineColor = rgb(255, 255, 255)
highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
highlight.Enabled = false
local marker = Instance.new("BillboardGui")
marker.Name = "SkylineGrappleMarker"
marker.Size = UDim2.fromOffset(120, 44)
marker.AlwaysOnTop = true
marker.LightInfluence = 0
marker.StudsOffset = Vector3.new(0, 3.2, 0)
marker.Enabled = false
local markerLabel = Instance.new("TextLabel")
markerLabel.Size = UDim2.fromScale(1, 1)
markerLabel.BackgroundTransparency = 1
markerLabel.Font = Enum.Font.GothamBold
markerLabel.TextScaled = true
markerLabel.TextColor3 = rgb(255, 255, 255)
markerLabel.TextStrokeTransparency = 0.3
markerLabel.Parent = marker

local function updateGrapple()
	local target = Controller.Info.GrappleTarget
	local busy = Controller.Info.State == "Swing" or Controller.Info.State == "Pull"
	if target and target.Parent and not busy then
		highlight.Adornee = target
		highlight.Enabled = true
		marker.Adornee = target
		marker.Enabled = Settings.Get("ShowInputHints") ~= false
		local pull = target:HasTag(Tags.PullAnchor)
		markerLabel.Text = ("[%s] %s"):format(Input.Glyph("Grapple"), if pull then "Pull" else "Swing")
		highlight.FillColor = if pull then rgb(255, 190, 90) else rgb(120, 235, 255)
	else
		highlight.Enabled = false
		marker.Enabled = false
	end
end

-- Flow aura ----------------------------------------------------------------------------------------

local aura: ParticleEmitter? = nil
local TIER_COLORS = {
	rgb(160, 220, 255),
	rgb(120, 255, 200),
	rgb(255, 220, 120),
	rgb(255, 150, 90),
	rgb(255, 120, 230),
}

local function attachAura(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end
	local e = Instance.new("ParticleEmitter")
	e.Name = "SkylineFlowAura"
	e.Texture = SPARKLE
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	e.Speed = NumberRange.new(1, 3)
	e.Lifetime = NumberRange.new(0.4, 0.8)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = 0
	e.Parent = root
	aura = e
end

local function updateAura()
	local e = aura
	if not e then
		return
	end
	local tier = Flow.Tier
	if tier >= 2 and Settings.Get("FlowEffects") ~= false then
		e.Rate = 6 + tier * 8
		e.Color = ColorSequence.new(TIER_COLORS[tier] or TIER_COLORS[1])
	else
		e.Rate = 0
	end
end

-- Remote landings ------------------------------------------------------------------------------------

local lastVy: { [Model]: number } = {}
local watched: { [Model]: boolean } = {}

local function watchRemote(character: Model)
	if watched[character] then
		return
	end
	watched[character] = true
	local previous = character:GetAttribute("MS")
	character:GetAttributeChangedSignal("MS"):Connect(function()
		local state = character:GetAttribute("MS")
		if previous == "Air" and (state == "Ground" or state == "Slide" or state == "Roll" or state == "Stumble") then
			local root = character:FindFirstChild("HumanoidRootPart")
			local camera = workspace.CurrentCamera
			if root and root:IsA("BasePart") and camera and (camera.CFrame.Position - root.Position).Magnitude < 150 then
				local impact = math.max(-(lastVy[character] or 0), 0)
				if impact > 35 then
					local style = character:GetAttribute("LandingFx")
					local color = character:GetAttribute("LandingColor")
					Effects.Landing(root.Position - Vector3.new(0, 3, 0), impact, if type(style) == "string" then style else nil, if typeof(color) == "Color3" then color else nil, nil)
				end
			end
		end
		previous = state
	end)
	character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(workspace) then
			watched[character] = nil
			lastVy[character] = nil
		end
	end)
end

function Effects.Start()
	fxFolder.Parent = workspace
	highlight.Parent = fxFolder
	marker.Parent = player:WaitForChild("PlayerGui")
	makeSpeedLines()

	Controller.Landed:Connect(function(impact: number, kind: string)
		local info = Controller.Info
		local root = info.Root
		local character = info.Character
		if not root or not character then
			return
		end
		if impact < 30 and kind ~= "Roll" and kind ~= "Precision" then
			return
		end
		local style = character:GetAttribute("LandingFx")
		local color = character:GetAttribute("LandingColor")
		Effects.Landing(
			root.Position - Vector3.new(0, 3, 0),
			impact,
			if type(style) == "string" then style else nil,
			if typeof(color) == "Color3" then color else nil,
			info.FloorMaterial
		)
		if kind == "Precision" then
			ring(root.Position - Vector3.new(0, 2.9, 0), rgb(255, 255, 255), 2.2, 0.3)
		end
	end)
	Controller.Action:Connect(function(action: string)
		local root = Controller.Info.Root
		if not root then
			return
		end
		local feet = root.Position - Vector3.new(0, 3, 0)
		if action == "DoubleJump" then
			ring(feet + Vector3.new(0, 0.4, 0), rgb(200, 240, 255), 3.2, 0.35)
			burst(feet, { Color = rgb(230, 245, 255), Count = 6, Speed = NumberRange.new(3, 6) })
		elseif action == "Dash" then
			burst(root.Position, {
				Color = rgb(200, 230, 255),
				Count = 10,
				Speed = NumberRange.new(2, 5),
				Spread = Vector2.new(180, 180),
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 2.6) }),
			})
		elseif action == "WallJump" or action == "WallKick" then
			burst(root.Position, { Color = rgb(215, 210, 200), Count = 8, Speed = NumberRange.new(3, 7), Spread = Vector2.new(60, 60) })
		elseif action == "Bounce" or action == "Launch" then
			ring(feet + Vector3.new(0, 0.3, 0), rgb(150, 255, 200), 4, 0.4)
		end
	end)

	local function onPlayer(target: Player)
		local function onCharacter(character: Model)
			if target == player then
				attachAura(character)
			else
				watchRemote(character)
			end
		end
		if target.Character then
			task.spawn(onCharacter, target.Character)
		end
		target.CharacterAdded:Connect(onCharacter)
	end
	for _, target in Players:GetPlayers() do
		onPlayer(target)
	end
	Players.PlayerAdded:Connect(onPlayer)

	local lastTrail = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - lastTrail > 0.1 then
			lastTrail = now
			updateTrails()
			for character in watched do
				local root = character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					lastVy[character] = root.AssemblyLinearVelocity.Y
				end
			end
		end
		updateGrapple()
		updateAura()
	end)
	RunService.RenderStepped:Connect(updateSpeedLines)
end

return Effects

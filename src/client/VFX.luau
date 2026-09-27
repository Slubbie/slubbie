-- Visual effects for every character: speed trails, dash afterimages, landing
-- dust, wall-run sparks, slide dust, grapple impacts and launch shockwaves.
--
-- Effects are local-only parts under the camera, so they cost the server nothing.
-- Other players' effects are driven by their relayed state and actions.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local MathUtil = require(ReplicatedStorage.Shared.MathUtil)
local Net = require(ReplicatedStorage.Shared.Net)
local Grapple = require(script.Parent.Grapple)

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local DUST_COLOR = Color3.fromRGB(235, 228, 215)
local BODY_PARTS = { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
local TRAIL_SPEED = 50

local VFX = {}

local Movement = nil

type CharacterFX = {
	Player: Player,
	Character: Model,
	Root: BasePart,
	Trail: Trail,
	Sparks: ParticleEmitter,
	Dust: ParticleEmitter,
	LastGrapplePoint: Vector3?,
}
local tracked: { [Model]: CharacterFX } = {}

local function folder(): Instance
	local camera = workspace.CurrentCamera
	local existing = camera:FindFirstChild("SkyboundVFX")
	if existing then
		return existing
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = "SkyboundVFX"
	newFolder.Parent = camera
	return newFolder
end

local function effectPart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = folder()
	return part
end

function VFX.PlayerColor(player: Player?): Color3
	if player and player:GetAttribute("Rainbow") then
		return Color3.fromHSV(os.clock() * 0.25 % 1, 0.7, 1)
	end
	local color = player and player:GetAttribute("RopeColor")
	return if typeof(color) == "Color3" then color else Config.Grapple.RopeColor
end

-- One-shot effects -----------------------------------------------------------------

local function burst(position: Vector3, emitterProps: { [string]: any }, count: number)
	local holder = effectPart({ Transparency = 1, Size = Vector3.one * 0.2, Position = position })
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	for key, value in emitterProps do
		(emitter :: any)[key] = value
	end
	emitter.Parent = holder
	emitter:Emit(count)
	Debris:AddItem(holder, 2)
end

function VFX.Dust(position: Vector3, amount: number)
	burst(position, {
		Texture = SMOKE,
		Color = ColorSequence.new(DUST_COLOR),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 4) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.4, 0.8),
		Speed = NumberRange.new(10, 18),
		SpreadAngle = Vector2.new(80, 80),
		Drag = 5,
		Acceleration = Vector3.new(0, -6, 0),
		RotSpeed = NumberRange.new(-90, 90),
	}, amount)
end

function VFX.Sparks(position: Vector3, color: Color3, amount: number)
	burst(position, {
		Texture = SPARKLE,
		Color = ColorSequence.new(color),
		LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.2, 0.45),
		Speed = NumberRange.new(20, 40),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 6,
	}, amount)
end

function VFX.Flash(position: Vector3, color: Color3, size: number)
	local ball = effectPart({ Shape = Enum.PartType.Ball, Color = color, Size = Vector3.one, Position = position })
	TweenService:Create(ball, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * size,
		Transparency = 1,
	}):Play()
	Debris:AddItem(ball, 0.35)
end

function VFX.Shockwave(position: Vector3, color: Color3)
	local ring = effectPart({
		Shape = Enum.PartType.Cylinder,
		Color = color,
		Transparency = 0.2,
		Size = Vector3.new(0.3, 2, 2),
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2),
	})
	TweenService:Create(ring, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, 26, 26),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.45)
end

-- Ghostly copies of the body left behind by a dash.
function VFX.Afterimages(character: Model, color: Color3)
	for i = 0, 3 do
		task.delay(i * 0.04, function()
			for _, name in BODY_PARTS do
				local limb = character:FindFirstChild(name)
				if limb and limb:IsA("BasePart") then
					local ghost = effectPart({
						Color = color,
						Size = limb.Size,
						CFrame = limb.CFrame,
						Transparency = 0.45,
					})
					TweenService:Create(ghost, TweenInfo.new(0.3), { Transparency = 1 }):Play()
					Debris:AddItem(ghost, 0.32)
				end
			end
		end)
	end
end

local function feet(root: BasePart): Vector3
	return root.Position - Vector3.new(0, 3, 0)
end

local function onAction(fx: CharacterFX, action: string)
	local root = fx.Root
	local color = VFX.PlayerColor(fx.Player)
	if action == "Dash" then
		VFX.Afterimages(fx.Character, color)
		VFX.Flash(root.Position, color, 6)
	elseif action == "Launch" then
		VFX.Shockwave(feet(root), color)
		VFX.Sparks(feet(root), color, 25)
	elseif action == "WallJump" then
		VFX.Sparks(root.Position, color, 18)
		VFX.Dust(root.Position, 6)
	elseif action == "Roll" or action == "HardLand" then
		VFX.Dust(feet(root), 22)
		VFX.Shockwave(feet(root) + Vector3.new(0, 0.3, 0), DUST_COLOR)
	elseif action == "Slingshot" then
		VFX.Flash(root.Position, color, 9)
		VFX.Sparks(root.Position, color, 30)
	elseif action == "BunnyHop" or action == "SlideJump" then
		VFX.Dust(feet(root), 8)
	end
end

-- Per-character trail and emitters ---------------------------------------------------

local function track(player: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	local torso = character:WaitForChild("Torso", 10) :: BasePart?
	if not root or not torso then
		return
	end

	local top = Instance.new("Attachment")
	top.Name = "TrailTop"
	top.Position = Vector3.new(0, 0.9, 0.4)
	top.Parent = torso
	local bottom = Instance.new("Attachment")
	bottom.Name = "TrailBottom"
	bottom.Position = Vector3.new(0, -0.9, 0.4)
	bottom.Parent = torso
	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.35
	trail.MinLength = 0.1
	trail.LightEmission = 0.8
	trail.FaceCamera = true
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
	trail.Enabled = false
	trail.Parent = torso

	local feetAttachment = Instance.new("Attachment")
	feetAttachment.Name = "FeetFX"
	feetAttachment.Position = Vector3.new(0, -3, 0)
	feetAttachment.Parent = torso

	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARKLE
	sparks.LightEmission = 1
	sparks.Rate = 45
	sparks.Lifetime = NumberRange.new(0.2, 0.35)
	sparks.Speed = NumberRange.new(8, 16)
	sparks.SpreadAngle = Vector2.new(60, 60)
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	sparks.Enabled = false
	sparks.Parent = feetAttachment

	local dust = Instance.new("ParticleEmitter")
	dust.Texture = SMOKE
	dust.Color = ColorSequence.new(DUST_COLOR)
	dust.Rate = 30
	dust.Lifetime = NumberRange.new(0.4, 0.7)
	dust.Speed = NumberRange.new(2, 5)
	dust.SpreadAngle = Vector2.new(50, 50)
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 3) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	dust.Enabled = false
	dust.Parent = feetAttachment

	tracked[character] = {
		Player = player,
		Character = character,
		Root = root,
		Trail = trail,
		Sparks = sparks,
		Dust = dust,
		LastGrapplePoint = nil,
	}
	character.Destroying:Connect(function()
		tracked[character] = nil
	end)
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		track(player, character)
	end)
	if player.Character then
		task.spawn(track, player, player.Character)
	end
end

local function update()
	local localPlayer = Players.LocalPlayer
	for character, fx in tracked do
		if not fx.Root.Parent then
			tracked[character] = nil
			continue
		end
		local isLocal = fx.Player == localPlayer
		local state = if isLocal then Movement.Info.State else character:GetAttribute("MoveState")
		local speed = MathUtil.Flat(fx.Root.AssemblyLinearVelocity).Magnitude
		local color = VFX.PlayerColor(fx.Player)

		fx.Trail.Enabled = speed > TRAIL_SPEED
		fx.Trail.Color = ColorSequence.new(color)
		fx.Sparks.Color = ColorSequence.new(color)
		fx.Sparks.Enabled = state == "WallRun"
		fx.Dust.Enabled = state == "Slide"

		-- Other players' grapple hits.
		if not isLocal then
			local point = character:GetAttribute("GrapplePoint")
			if typeof(point) == "Vector3" and point ~= fx.LastGrapplePoint then
				VFX.Sparks(point, color, 14)
			end
			fx.LastGrapplePoint = if typeof(point) == "Vector3" then point else nil
		end
	end
end

function VFX.Start(movement)
	Movement = movement
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)

	local function localFX(): CharacterFX?
		local character = Players.LocalPlayer.Character
		return character and tracked[character]
	end

	Movement.Action.Event:Connect(function(action: string)
		local fx = localFX()
		if fx then
			onAction(fx, action)
		end
	end)
	Movement.Landed.Event:Connect(function(impact: number)
		local fx = localFX()
		if fx and impact > 45 and impact <= Config.Movement.HardLandingSpeed then
			VFX.Dust(feet(fx.Root), 8)
		end
	end)
	Grapple.Attached.Event:Connect(function(position: Vector3)
		local color = VFX.PlayerColor(Players.LocalPlayer)
		VFX.Sparks(position, color, 18)
		VFX.Flash(position, color, 4)
	end)
	Net.Event("MoveAction").OnClientEvent:Connect(function(player: Player, action: string)
		local fx = player.Character and tracked[player.Character]
		if fx then
			onAction(fx, action)
		end
	end)

	RunService.RenderStepped:Connect(update)
end

return VFX

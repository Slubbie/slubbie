-- Grappling hook: aim, shoot, attach, swing, release.
--
-- The rope is a custom "soft rope": it only pulls when stretched past its current
-- length, so you swing like a pendulum instead of being dragged in a straight line.
-- Timing your release at the bottom of a swing is how you build speed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local MathUtil = require(ReplicatedStorage.Shared.MathUtil)

local G = Config.Grapple

local localPlayer = Players.LocalPlayer

local Grapple = {}
Grapple.Fired = Instance.new("BindableEvent") -- (hit: boolean)
Grapple.Attached = Instance.new("BindableEvent") -- (anchorPosition: Vector3)
Grapple.Released = Instance.new("BindableEvent") -- (releaseSpeed: number)

type Phase = "Idle" | "Shooting" | "Attached" | "Retracting"

local phase: Phase = "Idle"
local root: BasePart? = nil
local handAttachment: Attachment? = nil
local anchorAttachment: Attachment? = nil
local missPoint: Vector3? = nil
local held = false
local ropeLength = 0
local shotStart, shotDuration = 0, 0
local retractFrom, retractStart = Vector3.zero, 0
local lastRelease = -math.huge
local wobble = 0

-- Local-only visuals live under the camera so they never replicate or get raycast.
local hookPart = Instance.new("Part")
hookPart.Name = "GrappleHook"
hookPart.Shape = Enum.PartType.Ball
hookPart.Size = Vector3.one * 0.7
hookPart.Material = Enum.Material.Neon
hookPart.Color = G.RopeColor
hookPart.Anchored = true
hookPart.CanCollide = false
hookPart.CanQuery = false
hookPart.CanTouch = false
hookPart.CastShadow = false
hookPart.Transparency = 1

local hookAttachment = Instance.new("Attachment")
hookAttachment.Parent = hookPart

local beam = Instance.new("Beam")
beam.Attachment1 = hookAttachment
beam.Color = ColorSequence.new(G.RopeColor)
beam.LightEmission = 1
beam.LightInfluence = 0
beam.Width0 = 0.2
beam.Width1 = 0.12
beam.FaceCamera = true
beam.Segments = 16
beam.Enabled = false
beam.Parent = hookPart

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function refreshFilter()
	-- Never hook onto players (ours or anyone else's).
	local ignore = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = ignore
end

local function isValidHit(hit: RaycastResult?): boolean
	if not hit or not root then
		return false
	end
	if hit.Instance:GetAttribute("NoGrapple") then
		return false
	end
	return (hit.Position - root.Position).Magnitude <= G.Range
end

-- Returns what the crosshair is pointing at, or nil plus the point where a miss would end.
function Grapple.GetAimTarget(): (RaycastResult?, Vector3?)
	if not root then
		return nil, nil
	end
	refreshFilter()
	local camera = workspace.CurrentCamera
	local viewport = camera.ViewportSize
	local ray = camera:ViewportPointToRay(viewport.X / 2, viewport.Y / 2)
	local dir = ray.Direction.Unit
	-- Start the ray level with the character so nothing between camera and player gets hooked.
	local skip = math.max((root.Position - ray.Origin):Dot(dir), 0)
	local origin = ray.Origin + dir * skip
	local reach = dir * G.Range

	local hit = workspace:Raycast(origin, reach, rayParams)
	if not isValidHit(hit) then
		hit = workspace:Spherecast(origin, G.AimAssistRadius, reach, rayParams)
	end
	if isValidHit(hit) then
		return hit, nil
	end
	return nil, origin + reach
end

function Grapple.IsAttached(): boolean
	return phase == "Attached"
end

-- World position of the hook while it's out, for animation and camera effects.
function Grapple.GetHookPosition(): Vector3?
	if phase == "Idle" then
		return nil
	end
	return hookPart.Position
end

local function destroyAnchor()
	if anchorAttachment then
		anchorAttachment:Destroy()
		anchorAttachment = nil
	end
end

local function retract()
	retractFrom = hookPart.Position
	retractStart = os.clock()
	phase = "Retracting"
	destroyAnchor()
end

local function attach()
	local anchor = anchorAttachment :: Attachment
	phase = "Attached"
	ropeLength = math.max(((root :: BasePart).Position - anchor.WorldPosition).Magnitude, G.MinLength)
	hookPart.Position = anchor.WorldPosition
	Grapple.Attached:Fire(anchor.WorldPosition)
end

function Grapple.Fire()
	if not root or not handAttachment or phase ~= "Idle" then
		return
	end
	if os.clock() - lastRelease < G.Cooldown then
		return
	end
	held = true
	local hit, miss = Grapple.GetAimTarget()
	local destination: Vector3
	if hit then
		local attachment = Instance.new("Attachment")
		attachment.Name = "GrappleAnchor"
		attachment.Parent = hit.Instance -- also works on Terrain
		attachment.WorldPosition = hit.Position
		anchorAttachment = attachment
		missPoint = nil
		destination = hit.Position
	else
		missPoint = miss
		destination = miss :: Vector3
	end
	shotStart = os.clock()
	shotDuration = (destination - handAttachment.WorldPosition).Magnitude / G.HookSpeed
	phase = "Shooting"
	Grapple.Fired:Fire(hit ~= nil)
	wobble = G.RopeWobble
	hookPart.Position = handAttachment.WorldPosition
	hookPart.Transparency = 0
	beam.Enabled = true
end

-- Let go. `withBoost = false` skips the release boost (used by dash and launch pads).
function Grapple.Release(withBoost: boolean?)
	held = false
	if phase == "Shooting" then
		retract()
	elseif phase == "Attached" then
		if withBoost ~= false and root then
			local v = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(v.X * G.ReleaseBoost, v.Y + G.ReleasePop, v.Z * G.ReleaseBoost)
		end
		lastRelease = os.clock()
		retract()
		Grapple.Released:Fire(if root then root.AssemblyLinearVelocity.Magnitude else 0)
	end
end

-- Rope physics. Called by Movement every Heartbeat while attached.
function Grapple.Step(dt: number, moveDirection: Vector3)
	local anchor = anchorAttachment
	if not anchor or not root then
		return
	end
	local offset = anchor.WorldPosition - root.Position
	local dist = offset.Magnitude
	if dist < 0.01 then
		return
	end
	local dir = offset / dist
	local v = root.AssemblyLinearVelocity

	ropeLength = math.max(ropeLength - G.ReelSpeed * dt, G.MinLength)
	if dist > G.MinLength + 1 then
		v += dir * G.PullAccel * dt
	end

	-- Movement keys pump the swing, perpendicular to the rope.
	if moveDirection.Magnitude > 0.1 then
		local tangent = moveDirection - dir * moveDirection:Dot(dir)
		v += tangent * G.SwingAccel * dt
	end

	-- The rope: remove outward velocity and pull back any stretch.
	if dist > ropeLength then
		local radial = v:Dot(dir)
		if radial < 0 then
			v -= dir * radial
		end
		v += dir * (dist - ropeLength) * G.Stiffness * dt
	end

	if v.Magnitude > G.MaxSpeed then
		v = v.Unit * G.MaxSpeed
	end
	root.AssemblyLinearVelocity = v
end

function Grapple.SetCharacter(newCharacter: Model?)
	if phase == "Attached" or phase == "Shooting" then
		Grapple.Release(false)
	end
	destroyAnchor()
	phase = "Idle"
	hookPart.Transparency = 1
	beam.Enabled = false
	if handAttachment then
		handAttachment:Destroy()
		handAttachment = nil
	end

	root = nil
	if not newCharacter then
		return
	end
	root = newCharacter:WaitForChild("HumanoidRootPart") :: BasePart
	local hand = newCharacter:WaitForChild("Right Arm", 5)
	if hand and hand:IsA("BasePart") then
		local attachment = Instance.new("Attachment")
		attachment.Name = "GrappleHand"
		attachment.Position = Vector3.new(0, -hand.Size.Y / 2, 0)
		attachment.Parent = hand
		handAttachment = attachment
		beam.Attachment0 = attachment
	end
end

local function update(dt: number)
	hookPart.Parent = workspace.CurrentCamera
	if phase == "Idle" or not handAttachment then
		return
	end
	local now = os.clock()
	local handPos = handAttachment.WorldPosition

	if phase == "Shooting" then
		local destination = if anchorAttachment then anchorAttachment.WorldPosition else missPoint :: Vector3
		local alpha = if shotDuration > 0 then math.clamp((now - shotStart) / shotDuration, 0, 1) else 1
		hookPart.Position = handPos:Lerp(destination, alpha)
		wobble = G.RopeWobble
		if alpha >= 1 then
			if anchorAttachment and anchorAttachment:IsDescendantOf(workspace) and held then
				attach()
			else
				retract()
			end
		end
	elseif phase == "Attached" then
		if not anchorAttachment or not anchorAttachment:IsDescendantOf(workspace) then
			Grapple.Release(false)
			return
		end
		hookPart.Position = anchorAttachment.WorldPosition
	elseif phase == "Retracting" then
		local alpha = math.clamp((now - retractStart) / G.RetractTime, 0, 1)
		hookPart.Position = retractFrom:Lerp(handPos, alpha)
		if alpha >= 1 then
			phase = "Idle"
			hookPart.Transparency = 1
			beam.Enabled = false
		end
	end

	-- The rope whips while flying out, then settles taut.
	wobble = MathUtil.Damp(wobble, 0, 8, dt)
	local t = now * 38
	beam.CurveSize0 = math.sin(t) * wobble
	beam.CurveSize1 = math.sin(t + 2.1) * wobble
end

-- Rope colour comes from the equipped shop item ("Prism" cycles the rainbow).
local function updateColor()
	local color = localPlayer:GetAttribute("RopeColor")
	if typeof(color) ~= "Color3" then
		color = G.RopeColor
	end
	if localPlayer:GetAttribute("Rainbow") then
		color = Color3.fromHSV(os.clock() * 0.25 % 1, 0.7, 1)
	end
	hookPart.Color = color
	beam.Color = ColorSequence.new(color)
end

RunService.RenderStepped:Connect(function(dt)
	update(dt)
	updateColor()
end)

return Grapple

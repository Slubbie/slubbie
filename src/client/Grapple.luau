-- Grappling hook: aim, shoot, attach, swing, release.
--
-- The rope is a real RopeConstraint solved by the physics engine (many times per
-- frame, so swings are perfectly smooth) that slowly reels you in.
-- It only pulls when taut, so you swing like a pendulum rather than being dragged
-- in a straight line. Swing pumping and pull are physics forces too.
--
-- While attached the Humanoid is put in PlatformStand so its own air control
-- can't fight the swing. Timing your release at the bottom of the arc builds speed.

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
local humanoid: Humanoid? = nil
local handAttachment: Attachment? = nil
local anchorAttachment: Attachment? = nil
local rootAttachment: Attachment? = nil
local rope: RopeConstraint? = nil
local swingForce: VectorForce? = nil
local missPoint: Vector3? = nil
local held = false
local shotStart, shotDuration = 0, 0
local retractFrom, retractStart = Vector3.zero, 0
local lastRelease = -math.huge
local wobble = 0
local sag = 0
local thickness = 1

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

local function detachPhysics()
	if rope then
		rope:Destroy()
		rope = nil
	end
	if swingForce then
		swingForce.Enabled = false
		swingForce.Force = Vector3.zero
	end
	if humanoid and humanoid.PlatformStand then
		humanoid.PlatformStand = false
		if humanoid.Health > 0 then
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end
	end
end

local function attach()
	local anchor = anchorAttachment :: Attachment
	local body = root :: BasePart
	phase = "Attached"
	hookPart.Position = anchor.WorldPosition

	local dist = (body.Position - anchor.WorldPosition).Magnitude
	local newRope = Instance.new("RopeConstraint")
	newRope.Attachment0 = rootAttachment
	newRope.Attachment1 = anchor
	-- A touch of slack so the rope catches you softly instead of snapping.
	newRope.Length = math.max(dist * G.CatchSlack, G.MinLength)
	newRope.Restitution = 0
	newRope.Visible = false
	newRope.Parent = body
	rope = newRope

	thickness = 2.2
	if humanoid then
		humanoid.PlatformStand = true
	end
	if swingForce then
		swingForce.Enabled = true
	end
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
		detachPhysics()
		if withBoost ~= false and root then
			local v = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(v.X * G.ReleaseBoost, v.Y + G.ReleasePop, v.Z * G.ReleaseBoost)
		end
		lastRelease = os.clock()
		detachPhysics()
		retract()
		Grapple.Released:Fire(if root then root.AssemblyLinearVelocity.Magnitude else 0)
	end
end

-- Rope forces. Called by Movement every Heartbeat while attached. The rope itself
-- is solved by the physics engine; this only sets the forces we add on top.
-- `reelIn` (holding jump) winches you in fast.
function Grapple.Step(dt: number, moveDirection: Vector3, reelIn: boolean?)
	local anchor, body, force, currentRope = anchorAttachment, root, swingForce, rope
	if not anchor or not body or not force or not currentRope then
		return
	end
	local offset = anchor.WorldPosition - body.Position
	local dist = offset.Magnitude
	if dist < 0.01 then
		return
	end
	local dir = offset / dist
	local mass = body.AssemblyMass
	local velocity = body.AssemblyLinearVelocity

	-- Reel in: shorten the rope a little every frame and let the solver pull us
	-- smoothly along. Never shorter than MinLength.
	local reel = (if reelIn then G.FastReelSpeed else G.ReelSpeed) * dt
	currentRope.Length = math.max(math.min(currentRope.Length, dist + 2) - reel, G.MinLength)

	local total = Vector3.zero
	-- Gentle pull toward the anchor so swings gain height.
	if dist > G.MinLength + 1 then
		total += dir * G.PullAccel * mass
	end
	-- Movement keys pump the swing, perpendicular to the rope.
	if moveDirection.Magnitude > 0.1 then
		local tangent = moveDirection - dir * moveDirection:Dot(dir)
		total += tangent * G.SwingAccel * mass
	end
	-- Soft speed cap: drag only kicks in above MaxSpeed.
	local speed = velocity.Magnitude
	if speed > G.MaxSpeed then
		total -= velocity.Unit * (speed - G.MaxSpeed) * mass * 4
	end
	force.Force = total
end

-- How much the rope is currently longer than the distance to the hook.
function Grapple.GetSlack(): number
	if rope and anchorAttachment and root then
		return math.max(rope.Length - (anchorAttachment.WorldPosition - root.Position).Magnitude, 0)
	end
	return 0
end

function Grapple.SetCharacter(newCharacter: Model?)
	if phase == "Attached" or phase == "Shooting" then
		Grapple.Release(false)
	end
	detachPhysics()
	destroyAnchor()
	phase = "Idle"
	hookPart.Transparency = 1
	beam.Enabled = false
	for _, instance in { handAttachment, rootAttachment, swingForce } do
		if instance then
			instance:Destroy()
		end
	end
	handAttachment, rootAttachment, swingForce = nil, nil, nil

	root, humanoid = nil, nil
	if not newCharacter then
		return
	end
	local body = newCharacter:WaitForChild("HumanoidRootPart") :: BasePart
	root = body
	humanoid = newCharacter:WaitForChild("Humanoid") :: Humanoid

	local attachment0 = Instance.new("Attachment")
	attachment0.Name = "GrappleRoot"
	attachment0.Parent = body
	rootAttachment = attachment0
	local force = Instance.new("VectorForce")
	force.Attachment0 = attachment0
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Force = Vector3.zero
	force.Enabled = false
	force.Parent = body
	swingForce = force
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
		-- Ease out: the hook rockets away and decelerates as it bites.
		hookPart.Position = handPos:Lerp(destination, 1 - (1 - alpha) ^ 2)
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

	-- The rope whips while flying out, sags when slack, and snaps taut.
	wobble = MathUtil.Damp(wobble, 0, 8, dt)
	sag = MathUtil.Damp(sag, math.min(Grapple.GetSlack() * 0.6, 8), 12, dt)
	thickness = MathUtil.Damp(thickness, 1, 10, dt)
	-- Curve along world-down at both ends so sag always hangs downward.
	handAttachment.WorldAxis = -Vector3.yAxis
	hookAttachment.WorldAxis = -Vector3.yAxis
	local t = now * 38
	beam.CurveSize0 = sag + math.sin(t) * wobble
	beam.CurveSize1 = -sag + math.sin(t + 2.1) * wobble
	beam.Width0 = 0.2 * thickness
	beam.Width1 = 0.12 * thickness
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

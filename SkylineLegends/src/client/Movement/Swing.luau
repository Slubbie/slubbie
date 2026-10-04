-- Pendulum swinging for grapple anchors and hanging ropes.
--
-- The rope is a real RopeConstraint solved by the physics engine (substepped,
-- so swings are perfectly smooth). Pumping and reeling are a VectorForce on
-- top. While attached the Humanoid is PlatformStanded so its own air control
-- can't fight the swing, and an AlignOrientation keeps the body upright.
-- The grapple line is drawn locally; hanging ropes are bent toward the hand.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MathUtil = require(ReplicatedStorage.Shared.Util.MathUtil)

local Swing = {}

local root: BasePart? = nil
local humanoid: Humanoid? = nil
local rootAttachment: Attachment? = nil
local anchorAttachment: Attachment? = nil
local rope: RopeConstraint? = nil
local force: VectorForce? = nil
local upright: AlignOrientation? = nil
local hand: Attachment? = nil

local kind: string? = nil -- "Grapple" | "Rope"
local anchorPart: BasePart? = nil
local anchorOffset = Vector3.zero
local ropePart: BasePart? = nil
local ropeRest: CFrame? = nil
local ropeRestSize: Vector3? = nil
local lineTarget: Vector3? = nil
local shotStart = 0

-- Local-only line visuals (never replicated, never raycast).
local hookPart = Instance.new("Part")
hookPart.Name = "SkylineHook"
hookPart.Shape = Enum.PartType.Ball
hookPart.Size = Vector3.one * 0.6
hookPart.Material = Enum.Material.Neon
hookPart.Color = Color3.fromRGB(120, 235, 255)
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
beam.Color = ColorSequence.new(Color3.fromRGB(120, 235, 255))
beam.LightEmission = 1
beam.LightInfluence = 0
beam.Width0 = 0.18
beam.Width1 = 0.12
beam.FaceCamera = true
beam.Segments = 12
beam.Enabled = false
beam.Parent = hookPart

function Swing.SetCharacter(character: Model?)
	Swing.Detach(false)
	for _, instance in { rootAttachment, force, upright, hand } do
		if instance then
			instance:Destroy()
		end
	end
	rootAttachment, force, upright, hand = nil, nil, nil, nil
	root, humanoid = nil, nil
	if not character then
		return
	end
	local r = character:WaitForChild("HumanoidRootPart") :: BasePart
	root = r
	humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local attachment = Instance.new("Attachment")
	attachment.Name = "SwingRoot"
	attachment.Position = Vector3.new(0, 1.2, 0)
	attachment.Parent = r
	rootAttachment = attachment
	local vf = Instance.new("VectorForce")
	vf.Attachment0 = attachment
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.ApplyAtCenterOfMass = true
	vf.Force = Vector3.zero
	vf.Enabled = false
	vf.Parent = r
	force = vf
	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.Responsiveness = 25
	align.MaxTorque = math.huge
	align.Enabled = false
	align.Parent = r
	upright = align
	local arm = character:WaitForChild("Right Arm", 5)
	if arm and arm:IsA("BasePart") then
		local a = Instance.new("Attachment")
		a.Name = "SwingHand"
		a.Position = Vector3.new(0, -arm.Size.Y / 2, 0)
		a.Parent = arm
		hand = a
		beam.Attachment0 = a
	end
end

function Swing.IsAttached(): boolean
	return kind ~= nil
end

function Swing.Kind(): string?
	return kind
end

function Swing.Anchor(): Vector3?
	if not anchorAttachment then
		return nil
	end
	return anchorAttachment.WorldPosition
end

function Swing.Length(): number
	return if rope then rope.Length else 0
end

-- Attach to a point. `part` (optional) is what the hook bites; the anchor follows it if it moves.
function Swing.Attach(newKind: string, point: Vector3, part: BasePart?, length: number?, minLength: number)
	local r, h = root, humanoid
	if not r or not h or not rootAttachment then
		return
	end
	Swing.Detach(false)
	kind = newKind
	anchorPart = part
	local holder: Instance = part or workspace.Terrain
	local attachment = Instance.new("Attachment")
	attachment.Name = "SwingAnchor"
	attachment.Parent = holder
	attachment.WorldPosition = point
	anchorAttachment = attachment
	if part then
		anchorOffset = part.CFrame:PointToObjectSpace(point)
	end
	local distance = (rootAttachment.WorldPosition - point).Magnitude
	local constraint = Instance.new("RopeConstraint")
	constraint.Attachment0 = rootAttachment
	constraint.Attachment1 = attachment
	constraint.Length = math.max(length or distance, minLength)
	constraint.Restitution = 0
	constraint.Visible = false
	constraint.Parent = r
	rope = constraint
	h.PlatformStand = true
	if force then
		force.Enabled = true
	end
	if upright then
		upright.Enabled = true
	end
	if newKind == "Grapple" then
		hookPart.Position = if hand then hand.WorldPosition else r.Position
		hookPart.Transparency = 0
		beam.Enabled = true
		lineTarget = point
		shotStart = os.clock()
	elseif newKind == "Rope" and part then
		ropePart = part
		ropeRest = part.CFrame
		ropeRestSize = part.Size
	end
end

-- Forces each frame. Returns false if the swing broke (anchor gone).
function Swing.Step(dt: number, moveDirection: Vector3, reelSpeed: number, stats: { [string]: any }): boolean
	local r, constraint, vf, attachment = root, rope, force, anchorAttachment
	if not kind or not r or not constraint or not vf or not attachment then
		return false
	end
	if not attachment:IsDescendantOf(workspace) then
		return false
	end
	if anchorPart and anchorPart.Parent then
		attachment.WorldPosition = anchorPart.CFrame:PointToWorldSpace(anchorOffset)
	end
	local anchor = attachment.WorldPosition
	local offset = anchor - r.Position
	local distance = offset.Magnitude
	if distance < 0.05 then
		return true
	end
	local dir = offset / distance
	local mass = r.AssemblyMass
	local velocity = r.AssemblyLinearVelocity

	if reelSpeed > 0 then
		constraint.Length = math.max(math.min(constraint.Length, distance + 1) - reelSpeed * dt, stats.GrappleMinLength)
	end

	local total = Vector3.zero
	if kind == "Grapple" and distance > stats.GrappleMinLength + 1 then
		total += dir * stats.GrapplePull * mass
	end
	local pump = if kind == "Grapple" then stats.GrappleSwingAccel else stats.RopePump
	if moveDirection.Magnitude > 0.1 then
		local tangent = moveDirection - dir * moveDirection:Dot(dir)
		total += tangent * pump * mass
	end
	local speed = velocity.Magnitude
	local cap = stats.GrappleMaxSpeed
	if speed > cap then
		total -= velocity.Unit * (speed - cap) * mass * 4
	end
	vf.Force = total

	-- Keep upright, facing the way we're swinging.
	if upright then
		local flat = MathUtil.Flat(velocity)
		local facing = if flat.Magnitude > 2 then flat.Unit else MathUtil.FlatUnit(r.CFrame.LookVector)
		upright.CFrame = CFrame.lookAt(Vector3.zero, facing)
	end
	return true
end

-- Let go. Returns the release velocity.
function Swing.Detach(boost: boolean, stats: { [string]: any }?): Vector3
	local r, h = root, humanoid
	local velocity = if r then r.AssemblyLinearVelocity else Vector3.zero
	if kind and r and boost and stats then
		local factor = if kind == "Grapple" then stats.GrappleReleaseBoost else stats.RopeReleaseBoost
		local pop = if kind == "Grapple" then stats.GrappleReleasePop else stats.RopeReleasePop
		velocity = Vector3.new(velocity.X * factor, math.max(velocity.Y, 0) + pop, velocity.Z * factor)
		r.AssemblyLinearVelocity = velocity
	end
	if rope then
		rope:Destroy()
		rope = nil
	end
	if anchorAttachment then
		anchorAttachment:Destroy()
		anchorAttachment = nil
	end
	if force then
		force.Enabled = false
		force.Force = Vector3.zero
	end
	if upright then
		upright.Enabled = false
	end
	if kind and h then
		h.PlatformStand = false
		if h.Health > 0 then
			h:ChangeState(Enum.HumanoidStateType.Freefall)
		end
	end
	if ropePart and ropeRest then
		ropePart.CFrame = ropeRest
		if ropeRestSize then
			ropePart.Size = ropeRestSize
		end
	end
	ropePart, ropeRest, ropeRestSize = nil, nil, nil
	kind = nil
	anchorPart = nil
	if lineTarget then
		-- Let the line retract visually.
		shotStart = -os.clock()
	end
	return velocity
end

-- A straight line to a point (used while being pulled by a pull anchor).
function Swing.ShowLine(point: Vector3?)
	lineTarget = point
	if point then
		hookPart.Transparency = 0
		beam.Enabled = true
		shotStart = os.clock()
	end
end

RunService.RenderStepped:Connect(function()
	hookPart.Parent = workspace.CurrentCamera
	-- Bend a hanging rope toward the hand holding it.
	local part, rest, handAttachment = ropePart, ropeRest, hand
	if part and rest and handAttachment then
		local pivot = part:GetAttribute("Pivot")
		if typeof(pivot) == "Vector3" then
			local target = handAttachment.WorldPosition
			local length = (target - pivot).Magnitude
			part.Size = Vector3.new(length, part.Size.Y, part.Size.Z)
			local up = if math.abs((target - pivot).Unit.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
			part.CFrame = CFrame.lookAt((pivot + target) / 2, target, up) * CFrame.Angles(0, math.rad(90), 0)
		end
	end
	-- Grapple line: shoots out quickly, then follows the anchor.
	if lineTarget and handAttachment then
		local destination = if anchorAttachment then anchorAttachment.WorldPosition else lineTarget
		if shotStart >= 0 then
			local alpha = math.clamp((os.clock() - shotStart) / 0.08, 0, 1)
			hookPart.Position = handAttachment.WorldPosition:Lerp(destination, alpha)
		else
			local alpha = math.clamp((os.clock() + shotStart) / 0.15, 0, 1)
			hookPart.Position = destination:Lerp(handAttachment.WorldPosition, alpha)
			if alpha >= 1 then
				lineTarget = nil
				hookPart.Transparency = 1
				beam.Enabled = false
			end
		end
	elseif not lineTarget then
		hookPart.Transparency = 1
		beam.Enabled = false
	end
end)

return Swing

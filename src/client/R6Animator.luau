-- Procedural R6 animation for every character in the game.
--
-- Instead of playing uploaded animations, each client poses every R6 rig from
-- its movement state and velocity every frame:
--   idle breathing · speed-scaled run cycle · ninja run · jump tuck · flailing fall
--   superman dive · rope hang with the arm aimed at the hook · wall-run
--   slide · landing crouch · flips (wall jumps, launches, slingshots) · landing rolls
--
-- Our own state comes straight from Movement; other players' state arrives as
-- character attributes plus MoveAction events relayed by the server.
--
-- All poses are written in torso space (for limbs) or root space (for the body),
-- where +X rotation swings a limb forward and the body leans back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local MathUtil = require(ReplicatedStorage.Shared.MathUtil)
local Net = require(ReplicatedStorage.Shared.Net)
local Grapple = require(script.Parent.Grapple)

local A = Config.Animation
local Flat = MathUtil.Flat
local RotationBetween = MathUtil.RotationBetween
local Angles = CFrame.Angles
local I = CFrame.identity
local TAU = math.pi * 2
local MAX_ROPE_TILT = math.rad(65)

local JOINTS = {
	Root = { "HumanoidRootPart", "RootJoint" },
	Neck = { "Torso", "Neck" },
	RArm = { "Torso", "Right Shoulder" },
	LArm = { "Torso", "Left Shoulder" },
	RLeg = { "Torso", "Right Hip" },
	LLeg = { "Torso", "Left Hip" },
}

-- Knees-to-chest pose blended in during flips.
local TUCK = {
	Neck = Angles(-0.3, 0, 0),
	RArm = Angles(1.1, 0, 0.35),
	LArm = Angles(1.1, 0, -0.35),
	RLeg = Angles(1.45, 0, 0.1),
	LLeg = Angles(1.45, 0, -0.1),
}

type Pose = { [string]: CFrame }
type Flip = { Axis: Vector3, Angle: number, Start: number, Duration: number, Drop: number }
type Rig = {
	Character: Model,
	Root: BasePart,
	Torso: BasePart,
	IsLocal: boolean,
	Joints: { [string]: Motor6D },
	Rotation: { [string]: CFrame },
	RotationInverse: { [string]: CFrame },
	Current: Pose,
	Phase: number,
	State: string,
	LandTime: number,
	LandWeight: number,
	DashTime: number,
	LastWallNormal: Vector3,
	Flip: Flip?,
}

local R6Animator = {}

local rigs: { [Model]: Rig } = {}
local Movement = nil

-- State ------------------------------------------------------------------------

local function readState(rig: Rig): (string, Vector3, Vector3?, Vector3?)
	if rig.IsLocal then
		local info = Movement.Info
		return info.State, info.Velocity, info.WallNormal, Grapple.GetHookPosition()
	end
	local character = rig.Character
	local wallNormal = character:GetAttribute("WallNormal")
	local grapplePoint = character:GetAttribute("GrapplePoint")
	return character:GetAttribute("MoveState") or "Ground",
		rig.Root.AssemblyLinearVelocity,
		if typeof(wallNormal) == "Vector3" then wallNormal else nil,
		if typeof(grapplePoint) == "Vector3" then grapplePoint else nil
end

local function startFlip(rig: Rig, axis: Vector3, angle: number, duration: number, drop: number?)
	rig.Flip = { Axis = axis, Angle = angle, Start = os.clock(), Duration = duration, Drop = drop or 0 }
end

local function onAction(rig: Rig, action: string)
	local now = os.clock()
	if action == "WallJump" then
		-- Cartwheel away from the wall.
		local n = rig.Root.CFrame:VectorToObjectSpace(rig.LastWallNormal)
		local away = if n.X >= 0 then 1 else -1
		startFlip(rig, Vector3.zAxis, -away * TAU, A.FlipTime)
	elseif action == "Launch" or action == "SlideJump" then
		startFlip(rig, Vector3.xAxis, -TAU, A.FlipTime * 1.3)
	elseif action == "Slingshot" then
		startFlip(rig, Vector3.xAxis, TAU, A.FlipTime * 1.2)
	elseif action == "Roll" then
		startFlip(rig, Vector3.xAxis, -TAU, A.RollTime, 1.3)
		rig.LandTime = now
		rig.LandWeight = 0.5
	elseif action == "HardLand" then
		rig.LandTime = now
		rig.LandWeight = 1
	elseif action == "Dash" then
		rig.DashTime = now
	end
end

-- Poses ------------------------------------------------------------------------

local function groundPose(rig: Rig, P: Pose, dt: number, now: number, flatSpeed: number, forward: number)
	if flatSpeed < 2 then
		local breathe = math.sin(now * 2)
		P.Root = CFrame.new(0, breathe * 0.04, 0)
		P.Neck = Angles(breathe * 0.03, 0, 0)
		P.RArm = Angles(0, 0, 0.07 + breathe * 0.03)
		P.LArm = Angles(0, 0, -0.07 - breathe * 0.03)
		P.RLeg = Angles(0, 0, 0.03)
		P.LLeg = Angles(0, 0, -0.03)
		return
	end
	rig.Phase += dt * math.min(flatSpeed * 0.45 + 4, 24)
	local s, c = math.sin(rig.Phase), math.cos(rig.Phase)
	local dir = if forward < -1 then -1 else 1
	local amp = math.clamp(0.45 + flatSpeed / 45, 0.55, 1.25)
	local lean = -math.clamp(flatSpeed / 70, 0, 1) * 0.35 * dir

	P.RLeg = Angles(s * amp * dir, 0, 0.02)
	P.LLeg = Angles(-s * amp * dir, 0, -0.02)
	if flatSpeed > A.NinjaRunSpeed and dir > 0 then
		-- Arms swept back: you're going fast and you want everyone to know.
		lean = -0.55
		P.RArm = Angles(-1.35, 0, 0.2 + s * 0.05)
		P.LArm = Angles(-1.35, 0, -0.2 - s * 0.05)
	else
		P.RArm = Angles(-s * amp * 0.8 * dir, 0, 0.06)
		P.LArm = Angles(s * amp * 0.8 * dir, 0, -0.06)
	end
	P.Root = CFrame.new(0, math.abs(c) * 0.22 * amp - 0.08, 0) * Angles(lean, s * 0.12, 0)
	P.Neck = Angles(-lean * 0.6, -s * 0.12, 0)
end

local function slidePose(P: Pose, now: number)
	local rumble = math.sin(now * 45) * 0.02
	P.Root = CFrame.new(0, -1.3, 0) * Angles(1.15 + rumble, 0, 0)
	P.Neck = Angles(-0.95, 0, 0)
	P.RLeg = Angles(0.25, 0, 0.08)
	P.LLeg = Angles(0.95, 0, -0.12)
	P.RArm = Angles(-0.35, 0, 0.55)
	P.LArm = Angles(1.5, 0, -0.35)
end

local function wallRunPose(rig: Rig, P: Pose, dt: number, flatSpeed: number, wallNormal: Vector3)
	rig.Phase += dt * math.min(flatSpeed * 0.5 + 6, 26)
	local s, c = math.sin(rig.Phase), math.cos(rig.Phase)
	local n = rig.Root.CFrame:VectorToObjectSpace(wallNormal)
	local side = if n.X >= 0 then 1 else -1 -- +1: the wall is on our left

	P.RLeg = Angles(s * 1.1, 0, 0)
	P.LLeg = Angles(-s * 1.1, 0, 0)
	P.Root = CFrame.new(0, math.abs(c) * 0.15, 0) * Angles(-0.25, 0, -side * 0.5)
	P.Neck = Angles(0.2, 0, side * 0.3)
	-- The hand nearest the wall reaches out and skims it.
	if side > 0 then
		P.LArm = Angles(0.3, 0, -1.4 + s * 0.1)
		P.RArm = Angles(s * 0.9, 0, 0.2)
	else
		P.RArm = Angles(0.3, 0, 1.4 - s * 0.1)
		P.LArm = Angles(-s * 0.9, 0, -0.2)
	end
end

local function grapplePose(rig: Rig, P: Pose, now: number, localVel: Vector3, hookPos: Vector3)
	local torso = rig.Torso
	local shoulder = torso.CFrame * Vector3.new(1, 0.5, 0)
	local toHook = hookPos - shoulder
	if toHook.Magnitude > 0.1 then
		P.RArm = RotationBetween(-Vector3.yAxis, torso.CFrame:VectorToObjectSpace(toHook.Unit))
	end
	P.LArm = Angles(0.3 + math.sin(now * 3) * 0.1, 0, -1.2)

	-- Legs trail behind the swing.
	local trail = math.clamp(localVel.Z / 50, -1, 1)
	local wobble = math.sin(now * 4) * 0.12
	P.RLeg = Angles(trail * 0.8 + 0.15 + wobble, 0, 0.1)
	P.LLeg = Angles(trail * 0.8 - 0.35 - wobble, 0, -0.1)
	P.Neck = Angles(0.35, 0, 0)

	-- Body hangs toward the rope.
	local root = rig.Root
	local toAnchor = hookPos - root.Position
	if toAnchor.Magnitude > 0.1 then
		local rotation = RotationBetween(Vector3.yAxis, root.CFrame:VectorToObjectSpace(toAnchor.Unit))
		local axis, angle = rotation:ToAxisAngle()
		P.Root = CFrame.fromAxisAngle(axis, math.min(angle, MAX_ROPE_TILT))
	end
end

local function airPose(rig: Rig, P: Pose, now: number, flatSpeed: number, vy: number)
	local superman = (flatSpeed > A.SupermanSpeed and vy > -35) or now - rig.DashTime < 0.35
	if superman then
		local wobble = math.sin(now * 6) * 0.05
		P.Root = Angles(-1.25, 0, 0)
		P.RArm = Angles(2.9, 0, 0.12)
		P.LArm = Angles(-0.1, 0, -0.3)
		P.RLeg = Angles(-0.1 + wobble, 0, 0.06)
		P.LLeg = Angles(-0.3 - wobble, 0, -0.06)
		P.Neck = Angles(1.0, 0, 0)
	elseif vy > 4 then
		P.Root = Angles(-0.15, 0, 0)
		P.RLeg = Angles(0.9, 0, 0.05)
		P.LLeg = Angles(-0.35, 0, -0.05)
		P.RArm = Angles(0.5, 0, 0.6)
		P.LArm = Angles(-0.3, 0, -0.6)
		P.Neck = Angles(0.15, 0, 0)
	else
		local t = now * 9
		local fall = math.clamp(-vy / 80, 0, 1)
		P.RArm = Angles(0.2 + math.sin(t) * 0.35 * fall, 0, 1.2 + fall * 0.8 + math.sin(t * 1.3) * 0.15)
		P.LArm = Angles(0.2 - math.sin(t) * 0.35 * fall, 0, -1.2 - fall * 0.8 - math.sin(t * 1.1) * 0.15)
		P.RLeg = Angles(0.35 + math.sin(t * 0.8) * 0.3 * fall, 0, 0.12)
		P.LLeg = Angles(-0.25 - math.sin(t * 0.8) * 0.3 * fall, 0, -0.12)
		P.Neck = Angles(-0.2 * fall, 0, 0)
	end
end

-- Frame update -----------------------------------------------------------------

local function animate(rig: Rig, dt: number, now: number)
	local state, velocity, wallNormal, hookPos = readState(rig)
	local root = rig.Root
	local localVel = root.CFrame:VectorToObjectSpace(velocity)
	local flatSpeed = Flat(velocity).Magnitude

	if wallNormal then
		rig.LastWallNormal = wallNormal
	end
	if state ~= rig.State then
		-- Other players: landing is inferred from the state change.
		if not rig.IsLocal and state == "Ground" and rig.State ~= "Slide" then
			rig.LandTime = now
			rig.LandWeight = math.max(rig.LandWeight, 0.35)
		end
		rig.State = state
	end

	local P: Pose = { Root = I, Neck = I, RArm = I, LArm = I, RLeg = I, LLeg = I }
	if state == "Ground" then
		groundPose(rig, P, dt, now, flatSpeed, -localVel.Z)
		if rig.IsLocal then
			-- Glance where the camera is looking.
			local look = root.CFrame:VectorToObjectSpace(workspace.CurrentCamera.CFrame.LookVector)
			local yaw = math.clamp(math.atan2(-look.X, -look.Z), -1, 1)
			local pitch = math.clamp(math.asin(math.clamp(look.Y, -1, 1)), -0.6, 0.6)
			P.Neck = Angles(pitch * 0.6, yaw * 0.8, 0) * P.Neck
		end
	elseif state == "Slide" then
		slidePose(P, now)
	elseif state == "WallRun" then
		wallRunPose(rig, P, dt, flatSpeed, rig.LastWallNormal)
	elseif state == "Grapple" and hookPos then
		grapplePose(rig, P, now, localVel, hookPos)
	else
		airPose(rig, P, now, flatSpeed, velocity.Y)
	end

	-- Landing crouch.
	local landAge = now - rig.LandTime
	if landAge < 0.3 then
		local w = (1 - landAge / 0.3) ^ 2 * rig.LandWeight
		P.Root = CFrame.new(0, -0.9 * w, 0) * Angles(-0.4 * w, 0, 0) * P.Root
		P.RLeg = Angles(0.6 * w, 0, 0) * P.RLeg
		P.LLeg = Angles(0.3 * w, 0, 0) * P.LLeg
		P.RArm = Angles(0.3 * w, 0, 0.4 * w) * P.RArm
		P.LArm = Angles(0.3 * w, 0, -0.4 * w) * P.LArm
	elseif landAge > 0.5 then
		rig.LandWeight = 0
	end

	-- Flips: tuck in, spin around the body's centre.
	local flipRotation = I
	local flip = rig.Flip
	if flip then
		local alpha = (now - flip.Start) / flip.Duration
		if alpha >= 1 then
			rig.Flip = nil
		else
			local eased = 1 - (1 - alpha) ^ 3
			local tuck = math.sin(alpha * math.pi)
			for name, pose in TUCK do
				P[name] = P[name]:Lerp(pose, tuck)
			end
			flipRotation = CFrame.new(0, -flip.Drop * tuck, 0) * CFrame.fromAxisAngle(flip.Axis, flip.Angle * eased)
		end
	end

	local blend = 1 - math.exp(-A.Smoothing * dt)
	for name, joint in rig.Joints do
		local current = rig.Current[name]:Lerp(P[name], blend)
		rig.Current[name] = current
		local final = if name == "Root" then flipRotation * current else current
		joint.Transform = rig.RotationInverse[name] * final * rig.Rotation[name]
	end
end

-- Rig registration ---------------------------------------------------------------

local function addRig(character: Model, isLocal: boolean)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R6 then
		return
	end
	local defaultAnimate = character:FindFirstChild("Animate")
	if defaultAnimate then
		defaultAnimate:Destroy()
	end

	local joints, rotation, inverse, current = {}, {}, {}, {}
	for name, path in JOINTS do
		local part = character:WaitForChild(path[1], 10)
		local joint = part and part:WaitForChild(path[2], 10)
		if not joint or not joint:IsA("Motor6D") then
			return
		end
		joints[name] = joint
		rotation[name] = joint.C0.Rotation
		inverse[name] = joint.C0.Rotation:Inverse()
		current[name] = I
	end

	rigs[character] = {
		Character = character,
		Root = character:WaitForChild("HumanoidRootPart") :: BasePart,
		Torso = character:WaitForChild("Torso") :: BasePart,
		IsLocal = isLocal,
		Joints = joints,
		Rotation = rotation,
		RotationInverse = inverse,
		Current = current,
		Phase = 0,
		State = "Ground",
		LandTime = -math.huge,
		LandWeight = 0,
		DashTime = -math.huge,
		LastWallNormal = Vector3.xAxis,
		Flip = nil,
	}
	character.Destroying:Connect(function()
		rigs[character] = nil
	end)
	character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(workspace) then
			rigs[character] = nil
		end
	end)
end

local function watchPlayer(player: Player)
	local isLocal = player == Players.LocalPlayer
	player.CharacterAdded:Connect(function(character)
		addRig(character, isLocal)
	end)
	if player.Character then
		task.spawn(addRig, player.Character, isLocal)
	end
end

function R6Animator.Start(movement)
	Movement = movement

	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)

	Movement.Action.Event:Connect(function(action: string)
		local character = Players.LocalPlayer.Character
		local rig = character and rigs[character]
		if not rig then
			return
		end
		if action == "WallJump" and Movement.Info.LastWallJumpNormal then
			rig.LastWallNormal = Movement.Info.LastWallJumpNormal
		end
		onAction(rig, action)
	end)
	Movement.Landed.Event:Connect(function(impact: number)
		local character = Players.LocalPlayer.Character
		local rig = character and rigs[character]
		if rig and impact > 20 then
			rig.LandTime = os.clock()
			rig.LandWeight = math.max(rig.LandWeight, math.clamp(impact / 110, 0.25, 1))
		end
	end)
	Net.Event("MoveAction").OnClientEvent:Connect(function(player: Player, action: string)
		local rig = player.Character and rigs[player.Character]
		if rig then
			onAction(rig, action)
		end
	end)

	-- Runs every frame after the engine's animation step, so our poses win.
	RunService.PreSimulation:Connect(function(dt: number)
		if dt <= 0 then
			return
		end
		local now = os.clock()
		for character, rig in rigs do
			if rig.Root.Parent and rig.Torso.Parent then
				animate(rig, dt, now)
			else
				rigs[character] = nil
			end
		end
	end)
end

return R6Animator

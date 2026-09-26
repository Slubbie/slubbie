-- Procedural animation layered on top of the default Roblox animations:
-- leaning into speed and turns, hanging from the rope with the arm pointing at
-- the hook, tilting off walls, sliding on your back, squashing on hard landings.
--
-- Works on both R15 and R6 by rotating the root and right-shoulder joints.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local MathUtil = require(ReplicatedStorage.Shared.MathUtil)
local Grapple = require(script.Parent.Grapple)

local Damp = MathUtil.Damp
local Flat = MathUtil.Flat
local RotationBetween = MathUtil.RotationBetween

local CharacterFX = {}

local MAX_ROPE_TILT = math.rad(65)

function CharacterFX.Start(Movement)
	local rootJoint: Motor6D? = nil
	local rootC0 = CFrame.identity
	local shoulder: Motor6D? = nil
	local shoulderC0 = CFrame.identity

	local pitch, lean, drop, squash = 0, 0, 0, 0
	local ropeWeight, armWeight = 0, 0
	local lastHookPos = Vector3.zero
	local lastFlat = Vector3.zero
	local smoothedAccel = Vector3.zero

	local function bind(character: Model)
		rootJoint, shoulder = nil, nil
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		local joint, arm
		if humanoid.RigType == Enum.HumanoidRigType.R15 then
			joint = character:WaitForChild("LowerTorso"):WaitForChild("Root")
			arm = character:WaitForChild("RightUpperArm"):WaitForChild("RightShoulder")
		else
			joint = character:WaitForChild("HumanoidRootPart"):WaitForChild("RootJoint")
			arm = character:WaitForChild("Torso"):WaitForChild("Right Shoulder")
		end
		rootJoint, rootC0 = joint, joint.C0
		shoulder, shoulderC0 = arm, arm.C0
		pitch, lean, drop, squash, ropeWeight, armWeight = 0, 0, 0, 0, 0, 0
	end

	Movement.Landed.Event:Connect(function(impact: number)
		if impact > 30 then
			squash = math.clamp(impact / 150, 0.15, 0.9)
		end
	end)

	-- Runs after the Animator has posed the character, so our tweaks sit on top.
	RunService.PreSimulation:Connect(function(dt: number)
		local info = Movement.Info
		local root = info.Root
		if not rootJoint or not shoulder or not root or not rootJoint.Parent or dt <= 0 then
			return
		end

		local flat = Flat(info.Velocity)
		smoothedAccel = Damp(smoothedAccel, (flat - lastFlat) / dt, 10, dt)
		lastFlat = flat
		local localVel = root.CFrame:VectorToObjectSpace(flat)
		local localAccel = root.CFrame:VectorToObjectSpace(smoothedAccel)

		-- Lean forward with speed and into turns.
		local targetPitch = math.clamp(-localVel.Z / 140, -0.3, 1) * 0.35
		local targetLean = math.clamp(localAccel.X / 160, -1, 1) * 0.35
		local targetDrop = 0

		if info.State == "WallRun" and info.WallNormal then
			-- Body tilts away from the wall, feet planted on it.
			targetLean = root.CFrame:VectorToObjectSpace(info.WallNormal).X * 0.55
		elseif info.State == "Slide" then
			targetPitch = -0.95
			targetDrop = 1.1
		end

		pitch = Damp(pitch, targetPitch, 10, dt)
		lean = Damp(lean, targetLean, 10, dt)
		drop = Damp(drop, targetDrop, 14, dt)
		squash = Damp(squash, 0, 9, dt)

		-- Hang from the rope: body aligns toward the anchor.
		local hookPos = Grapple.GetHookPosition()
		if hookPos then
			lastHookPos = hookPos
		end
		ropeWeight = Damp(ropeWeight, if info.State == "Grapple" then 1 else 0, 8, dt)
		armWeight = Damp(armWeight, if hookPos then 1 else 0, 16, dt)

		local ropeTilt = CFrame.identity
		if ropeWeight > 0.01 then
			local toHook = lastHookPos - root.Position
			if toHook.Magnitude > 0.1 then
				local rotation = RotationBetween(Vector3.yAxis, root.CFrame:VectorToObjectSpace(toHook.Unit))
				local axis, angle = rotation:ToAxisAngle()
				ropeTilt = CFrame.fromAxisAngle(axis, math.min(angle, MAX_ROPE_TILT) * ropeWeight)
			end
		end

		rootJoint.C0 = CFrame.new(0, -(drop + squash), 0) * ropeTilt * CFrame.Angles(-pitch, 0, -lean) * rootC0

		-- Point the right arm at the hook.
		local torso = shoulder.Part0
		if armWeight > 0.01 and torso then
			local jointWorld = torso.CFrame * shoulderC0.Position
			local toHook = lastHookPos - jointWorld
			if toHook.Magnitude > 0.1 then
				local localDir = torso.CFrame:VectorToObjectSpace(toHook.Unit)
				local aim = CFrame.identity:Lerp(RotationBetween(-Vector3.yAxis, localDir), armWeight)
				shoulder.C0 = CFrame.new(shoulderC0.Position) * aim * shoulderC0.Rotation
				shoulder.Transform = shoulder.Transform:Lerp(CFrame.identity, armWeight)
			end
		else
			shoulder.C0 = shoulderC0
		end
	end)

	local player = game:GetService("Players").LocalPlayer
	player.CharacterAdded:Connect(bind)
	if player.Character then
		task.spawn(bind, player.Character)
	end
end

return CharacterFX

-- Camera feel: over-the-shoulder view, speed-based FOV, roll on walls and swings,
-- impact shake and speed lines.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local MathUtil = require(ReplicatedStorage.Shared.MathUtil)
local Grapple = require(script.Parent.Grapple)
local Settings = require(script.Parent.Settings)

local C = Config.Camera
local M = Config.Movement
local Damp = MathUtil.Damp

local CameraFX = {}

local trauma = 0
local fovKick = 0
local fov = C.BaseFOV
local roll = 0
local offset = Vector3.zero

function CameraFX.Shake(amount: number)
	if not Settings.Get("CameraShake") then
		return
	end
	trauma = math.min(trauma + amount, 1)
end

function CameraFX.Kick(fovAmount: number)
	fovKick += fovAmount
end

local function createSpeedLines()
	local gui = Instance.new("ScreenGui")
	gui.Name = "SpeedLines"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = -1
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local lines = {}
	for i = 1, C.SpeedLineCount do
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = Color3.new(1, 1, 1)
		frame.Visible = false
		frame.Parent = gui
		lines[i] = { Frame = frame, Age = math.huge, Life = 0, Angle = 0, Length = 0 }
	end

	return function(dt: number, intensity: number)
		local viewport = workspace.CurrentCamera.ViewportSize
		local cx, cy = viewport.X / 2, viewport.Y / 2
		local radius = math.max(viewport.X, viewport.Y) / 2
		for _, line in lines do
			line.Age += dt
			if line.Age >= line.Life then
				if intensity > 0 and math.random() < intensity then
					line.Age = 0
					line.Life = 0.18 + math.random() * 0.2
					line.Angle = math.random() * math.pi * 2
					line.Length = 60 + math.random() * 140
				else
					line.Frame.Visible = false
					continue
				end
			end
			local alpha = line.Age / line.Life
			local r = radius * (0.5 + 0.6 * alpha)
			local frame = line.Frame
			frame.Visible = true
			frame.Position = UDim2.fromOffset(cx + math.cos(line.Angle) * r, cy + math.sin(line.Angle) * r)
			frame.Size = UDim2.fromOffset(line.Length * (0.6 + intensity * 0.6), 2)
			frame.Rotation = math.deg(line.Angle)
			frame.BackgroundTransparency = 1 - intensity * 0.5 * (1 - alpha)
		end
	end
end

function CameraFX.Start(Movement)
	local updateSpeedLines = createSpeedLines()
	Settings.Watch("MouseSensitivity", function(value)
		UserInputService.MouseDeltaSensitivity = value
	end)
	-- Mouse users get a locked, over-the-shoulder camera; touch keeps the default.
	local shoulderCam = UserInputService.MouseEnabled and not UserInputService.TouchEnabled

	Movement.Landed.Event:Connect(function(impact: number)
		if impact > M.HardLandingSpeed then
			CameraFX.Shake(math.clamp((impact - M.HardLandingSpeed) / 90, 0.2, 0.7))
		end
	end)
	local actionKicks = {
		Dash = { 10, 0.15 },
		WallJump = { 5, 0 },
		Launch = { 14, 0.3 },
		Slingshot = { 12, 0.2 },
		Roll = { 0, 0.35 },
	}
	Movement.Action.Event:Connect(function(action: string)
		local kick = actionKicks[action]
		if kick then
			CameraFX.Kick(kick[1])
			if kick[2] > 0 then
				CameraFX.Shake(kick[2])
			end
		end
	end)
	Grapple.Attached.Event:Connect(function()
		CameraFX.Kick(4)
		CameraFX.Shake(0.2)
	end)

	RunService:BindToRenderStep("SkyboundCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local camera = workspace.CurrentCamera
		local info = Movement.Info

		-- Menus own the camera and mouse while open.
		if not Movement.Enabled then
			updateSpeedLines(dt, 0)
			return
		end

		if shoulderCam then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			UserInputService.MouseIconEnabled = false
		end

		-- Field of view opens up with speed.
		local speed = info.Velocity.Magnitude
		local speedAlpha = math.clamp((speed - C.FOVSpeedMin) / (C.FOVSpeedMax - C.FOVSpeedMin), 0, 1)
		fovKick = Damp(fovKick, 0, 5, dt)
		local baseFov = Settings.Get("FieldOfView")
		fov = Damp(fov, baseFov + (C.MaxFOV - C.BaseFOV) * speedAlpha + fovKick, 6, dt)
		camera.FieldOfView = fov

		-- Roll away from walls, lean into swings.
		local targetRoll = 0
		local right = camera.CFrame.RightVector
		if info.State == "WallRun" and info.WallNormal then
			targetRoll = -info.WallNormal:Dot(right) * math.rad(C.WallRunRoll)
		elseif info.State == "Grapple" then
			local lateral = info.Velocity:Dot(right) / Config.Grapple.MaxSpeed
			targetRoll = -math.clamp(lateral, -1, 1) * math.rad(C.SwingRoll)
		end
		roll = Damp(roll, targetRoll, 7, dt)

		-- Shoulder offset, dropping low while sliding.
		local targetOffset = if shoulderCam then C.ShoulderOffset else Vector3.zero
		if info.State == "Slide" then
			targetOffset += Vector3.new(0, -1.4, 0)
		end
		offset = Damp(offset, targetOffset, 10, dt)

		-- Trauma-based shake: squared so small hits stay subtle.
		trauma = math.max(trauma - dt * 1.6, 0)
		local shake = trauma * trauma * math.rad(C.ShakeAngle)
		local t = os.clock() * 22
		local shakeRotation =
			CFrame.Angles(math.noise(t, 1) * 2 * shake, math.noise(t, 2) * 2 * shake, math.noise(t, 3) * 2 * shake)

		camera.CFrame = camera.CFrame * CFrame.new(offset) * CFrame.Angles(0, 0, roll) * shakeRotation

		local lineStart, lineFull = C.SpeedLinesStart, C.SpeedLinesFull
		local lines = if Settings.Get("SpeedLines")
			then math.clamp((speed - lineStart) / (lineFull - lineStart), 0, 1)
			else 0
		updateSpeedLines(dt, lines)
	end)
end

return CameraFX

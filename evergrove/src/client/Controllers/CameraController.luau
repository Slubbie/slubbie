-- Camera: player-chosen modes, FOV, sensitivity, screen shake, and modes
-- other controllers request (build mode's top-down view, photo mode's free
-- camera, dialogue close-ups).
--
-- Modes
--   Classic   Roblox's default follow camera
--   Farm      angled overhead view that follows you (great for farming)
--   Shoulder  over-the-shoulder offset
--   Scripted  another controller drives the camera (Build, Photo, Dialogue)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local C = require(script.Parent)

local CameraController = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local mode = "Classic"
local scriptedBy: string? = nil
local farmZoom = 48
local farmYaw = 0

local shakeTime = 0
local shakeMagnitude = 0

function CameraController.Shake(magnitude: number, duration: number)
	local scale = C.Settings.Get("CameraShake") or 1
	if scale <= 0 then
		return
	end
	shakeMagnitude = math.max(shakeMagnitude, magnitude * scale)
	shakeTime = math.max(shakeTime, duration)
end

function CameraController.Mode(): string
	return mode
end

local function applyMode(newMode: string)
	mode = newMode
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if mode == "Classic" then
		camera.CameraType = Enum.CameraType.Custom
		if humanoid then
			humanoid.CameraOffset = Vector3.zero
		end
	elseif mode == "Shoulder" then
		camera.CameraType = Enum.CameraType.Custom
		if humanoid then
			humanoid.CameraOffset = Vector3.new(2.2, 0.6, 0)
		end
	elseif mode == "Farm" then
		camera.CameraType = Enum.CameraType.Scriptable
		if humanoid then
			humanoid.CameraOffset = Vector3.zero
		end
	end
end

local function settingMode(): string
	local choice = C.Settings.Get("CameraMode")
	if choice == "Farm (angled)" then
		return "Farm"
	elseif choice == "Shoulder" then
		return "Shoulder"
	end
	return "Classic"
end

-- Another controller takes the camera (returns a release function).
function CameraController.Take(owner: string): () -> ()
	scriptedBy = owner
	mode = "Scripted"
	camera.CameraType = Enum.CameraType.Scriptable
	return function()
		if scriptedBy == owner then
			scriptedBy = nil
			applyMode(settingMode())
		end
	end
end

function CameraController.IsScripted(): boolean
	return scriptedBy ~= nil
end

-- Smoothly look at something (dialogue close-ups); returns release fn.
function CameraController.Focus(target: CFrame, duration: number?): () -> ()
	local release = CameraController.Take("Focus")
	local start = camera.CFrame
	local t0 = os.clock()
	local d = duration or 0.6
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - t0) / d, 0, 1)
		a = 1 - (1 - a) ^ 3
		camera.CFrame = start:Lerp(target, a)
	end)
	return function()
		conn:Disconnect()
		release()
	end
end

function CameraController.Init()
	C.Settings.Changed:Connect(function(key, value)
		if key == "FOV" then
			camera.FieldOfView = value
		elseif key == "CameraMode" and not scriptedBy then
			applyMode(settingMode())
		elseif key == "Sensitivity" then
			UserInputService.MouseDeltaSensitivity = value
		end
	end)
end

function CameraController.Start()
	camera.FieldOfView = C.Settings.Get("FOV") or 70
	UserInputService.MouseDeltaSensitivity = C.Settings.Get("Sensitivity") or 1
	applyMode(settingMode())
	player.CharacterAdded:Connect(function()
		task.wait()
		if not scriptedBy then
			applyMode(settingMode())
		end
	end)
	-- Farm camera controls: scroll to zoom (Shift+scroll resizes tool area), Z/X or right stick to turn.
	UserInputService.InputChanged:Connect(function(input, processed)
		if mode ~= "Farm" or processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseWheel and not UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
			farmZoom = math.clamp(farmZoom - input.Position.Z * 4, 22, 90)
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			farmYaw -= input.Position.X * 0.05
		end
	end)
	RunService:BindToRenderStep("EvergroveCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		if mode == "Farm" and not scriptedBy then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				if not UserInputService:GetFocusedTextBox() then
					if UserInputService:IsKeyDown(Enum.KeyCode.Z) then
						farmYaw += dt * 1.6
					elseif UserInputService:IsKeyDown(Enum.KeyCode.X) then
						farmYaw -= dt * 1.6
					end
				end
				local focus = root.Position
				local offset = CFrame.Angles(0, farmYaw, 0) * Vector3.new(0, farmZoom * 0.85, farmZoom * 0.7)
				local target = CFrame.lookAt(focus + offset, focus)
				camera.CFrame = camera.CFrame:Lerp(target, 1 - math.exp(-10 * dt))
			end
		end
		if shakeTime > 0 then
			shakeTime -= dt
			local m = shakeMagnitude * math.clamp(shakeTime * 3, 0, 1)
			camera.CFrame *= CFrame.Angles(math.rad((math.random() - 0.5) * m * 4), math.rad((math.random() - 0.5) * m * 4), 0)
			if shakeTime <= 0 then
				shakeMagnitude = 0
			end
		end
	end)
end

return CameraController

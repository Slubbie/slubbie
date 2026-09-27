-- Photo mode (P): hides every HUD element and frees the camera so you can line
-- up screenshots. WASD / Q / E to fly, hold right mouse to look, scroll to zoom.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent.UI)

local FLY_SPEED = 40
local LOOK_SPEED = 0.25

local PhotoMode = {}
PhotoMode.Active = false

function PhotoMode.Start(Movement)
	local player = Players.LocalPlayer
	local hint = UI.gui("PhotoHint", 50)
	hint.Enabled = false
	local label = UI.label(hint, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(700, 22),
		TextSize = 14,
		TextTransparency = 0.3,
		TextStrokeTransparency = 0.6,
		Text = "PHOTO MODE  ·  WASD / Q / E fly  ·  hold RMB look  ·  scroll zoom  ·  H hide this  ·  P exit",
	})

	local hiddenGuis: { ScreenGui } = {}
	local yaw, pitch = 0, 0
	local fov = 70
	local position = Vector3.zero

	local function enter()
		if PhotoMode.Active or not Movement.Enabled then
			return
		end
		PhotoMode.Active = true
		Movement.SetEnabled(false)
		hiddenGuis = {}
		for _, gui in player.PlayerGui:GetChildren() do
			if gui:IsA("ScreenGui") and gui.Enabled and gui ~= hint then
				gui.Enabled = false
				table.insert(hiddenGuis, gui)
			end
		end
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
		end)
		local camera = workspace.CurrentCamera
		position = camera.CFrame.Position
		local look = camera.CFrame.LookVector
		yaw = math.atan2(-look.X, -look.Z)
		pitch = math.asin(math.clamp(look.Y, -1, 1))
		fov = camera.FieldOfView
		camera.CameraType = Enum.CameraType.Scriptable
		hint.Enabled = true
		label.Visible = true
	end

	local function exit()
		if not PhotoMode.Active then
			return
		end
		PhotoMode.Active = false
		for _, gui in hiddenGuis do
			gui.Enabled = true
		end
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
		hint.Enabled = false
		Movement.SetEnabled(true)
	end

	ContextActionService:BindAction("SkyboundPhotoMode", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			if PhotoMode.Active then
				exit()
			else
				enter()
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.P)

	UserInputService.InputBegan:Connect(function(input, processed)
		if PhotoMode.Active and not processed and input.KeyCode == Enum.KeyCode.H then
			label.Visible = not label.Visible
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not PhotoMode.Active then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			fov = math.clamp(fov - input.Position.Z * 4, 15, 110)
		end
	end)

	RunService:BindToRenderStep("SkyboundPhotoCamera", Enum.RenderPriority.Camera.Value + 5, function(dt)
		if not PhotoMode.Active then
			return
		end
		local looking = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
		UserInputService.MouseBehavior = if looking
			then Enum.MouseBehavior.LockCurrentPosition
			else Enum.MouseBehavior.Default
		if looking then
			local delta = UserInputService:GetMouseDelta()
			yaw -= math.rad(delta.X * LOOK_SPEED)
			pitch = math.clamp(pitch - math.rad(delta.Y * LOOK_SPEED), -1.5, 1.5)
		end
		local rotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
		local move = Vector3.zero
		local function held(key: Enum.KeyCode): number
			return if UserInputService:IsKeyDown(key) then 1 else 0
		end
		move += rotation.LookVector * (held(Enum.KeyCode.W) - held(Enum.KeyCode.S))
		move += rotation.RightVector * (held(Enum.KeyCode.D) - held(Enum.KeyCode.A))
		move += Vector3.yAxis * (held(Enum.KeyCode.E) - held(Enum.KeyCode.Q))
		local boost = if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then 3 else 1
		position += move * FLY_SPEED * boost * dt
		local camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.new(position) * rotation
		camera.FieldOfView = fov
	end)
end

return PhotoMode

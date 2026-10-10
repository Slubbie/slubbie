-- Input: which device the player is using (keyboard/mouse, touch or
-- gamepad), the matching prompt text for tutorials and hints, keyboard /
-- gamepad shortcuts for panels, and the capture action binding.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Signal)

local InputController = {}

export type Device = "Keyboard" | "Touch" | "Gamepad"

InputController.Device = "Keyboard" :: Device
InputController.DeviceChanged = Signal.new()

local function deviceFor(inputType: Enum.UserInputType): Device?
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	elseif inputType.Name:find("Gamepad") then
		return "Gamepad"
	elseif inputType == Enum.UserInputType.Keyboard or inputType.Name:find("Mouse") then
		return "Keyboard"
	end
	return nil
end

local function setDevice(device: Device?)
	if device and device ~= InputController.Device then
		InputController.Device = device
		InputController.DeviceChanged:Fire(device)
	end
end

-- "Press E" / "Tap the prompt" / "Press X" — for the world interaction prompt.
function InputController.InteractText(): string
	if InputController.Device == "Touch" then
		return "Tap the prompt"
	elseif InputController.Device == "Gamepad" then
		return "Press X"
	end
	return "Press E"
end

-- The minigame's action, by device.
function InputController.CaptureText(): string
	if InputController.Device == "Touch" then
		return "Tap"
	elseif InputController.Device == "Gamepad" then
		return "Press A"
	end
	return "Press Space"
end

function InputController.HoldText(): string
	if InputController.Device == "Touch" then
		return "Hold"
	elseif InputController.Device == "Gamepad" then
		return "Hold A"
	end
	return "Hold Space"
end

-- Shortcut keys for HUD panels. Ignored while typing in chat/text boxes.
local shortcuts: { [Enum.KeyCode]: () -> () } = {}

function InputController.BindShortcut(keys: { Enum.KeyCode }, callback: () -> ())
	for _, key in keys do
		shortcuts[key] = callback
	end
end

-- Binds the capture action (keyboard, mouse, gamepad) at high priority so
-- Space doesn't jump while stabilizing. Touch uses the on-screen button.
-- Returns an unbind function.
function InputController.BindCapture(onBegin: () -> (), onEnd: () -> ()): () -> ()
	local name = "CometCaptureAction"
	ContextActionService:BindActionAtPriority(
		name,
		function(_, state, input)
			if input.UserInputType == Enum.UserInputType.Touch then
				return Enum.ContextActionResult.Pass
			end
			if state == Enum.UserInputState.Begin then
				onBegin()
			elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				onEnd()
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value + 10,
		Enum.KeyCode.Space,
		Enum.KeyCode.E,
		Enum.UserInputType.MouseButton1,
		Enum.KeyCode.ButtonA,
		Enum.KeyCode.ButtonR2
	)
	return function()
		ContextActionService:UnbindAction(name)
	end
end

-- Freezes or restores character movement (used during the minigame).
local controls: any = nil
function InputController.SetMovementEnabled(enabled: boolean)
	if not controls then
		local ok, module = pcall(function()
			local playerModule = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 5)
			return playerModule and (require :: any)(playerModule):GetControls()
		end)
		controls = if ok then module else false
	end
	if controls then
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end
end

function InputController.Init() end

function InputController.Start()
	setDevice(
		deviceFor(UserInputService:GetLastInputType())
			or (if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "Touch" else "Keyboard")
	)
	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		setDevice(deviceFor(inputType))
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		local callback = shortcuts[input.KeyCode]
		if callback then
			callback()
		end
	end)
end

return InputController

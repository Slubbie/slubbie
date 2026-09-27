-- Input for every platform, mapped to the same actions so no device has an
-- advantage:
--   Keyboard  rebindable (Settings > Controls), defaults Q / E / 1-8 / Tab / L / G / M
--   Gamepad   X fire at self, Y fire at opponent, LB/RB previous/next instrument,
--             A use the focused instrument, D-pad left/right cycle target,
--             D-pad down event log, D-pad up emote, Select menu
--   Touch     on-screen buttons in the HUD (same actions)
--
-- Action(actionId, "Begin" | "End") fires for pressed/released, so "hold to
-- fire" behaves identically everywhere. Look input (right mouse drag, right
-- stick, one-finger drag on empty screen) is accumulated for the seat camera.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local SettingsSchema = require(ReplicatedStorage.Variance.Data.SettingsSchema)
local Signal = require(ReplicatedStorage.Variance.Util.Signal)

local InputController = {}
InputController.Action = Signal.new() -- (actionId, state)
InputController.DeviceChanged = Signal.new() -- (device)

local device = "Keyboard"
local lookDelta = Vector2.zero
local rightStick = Vector2.zero
local rmbDown = false
local touchLook: InputObject? = nil
local keyToAction: { [string]: string } = {}

local GAMEPAD = {
	[Enum.KeyCode.ButtonX] = "FireSelf",
	[Enum.KeyCode.ButtonY] = "FireOther",
	[Enum.KeyCode.ButtonL1] = "PrevSlot",
	[Enum.KeyCode.ButtonR1] = "NextSlot",
	[Enum.KeyCode.DPadLeft] = "PrevTarget",
	[Enum.KeyCode.DPadRight] = "NextTarget",
	[Enum.KeyCode.DPadDown] = "ToggleLog",
	[Enum.KeyCode.DPadUp] = "Emote",
	[Enum.KeyCode.ButtonSelect] = "Menu",
	[Enum.KeyCode.ButtonB] = "Back",
}

function InputController:Init(controllers)
	self.Controllers = controllers
end

function InputController:lastInput(): string
	return device
end

local function rebuildKeys(self)
	keyToAction = {}
	for _, action in SettingsSchema.Actions do
		local key = self.Controllers.SettingsController:bind(action.Id)
		if key then
			keyToAction[key] = action.Id
		end
	end
end

-- The key currently bound to an action, for on-screen hints.
function InputController:keyFor(actionId: string): string
	if device == "Gamepad" then
		for code, id in GAMEPAD do
			if id == actionId then
				return (string.gsub(code.Name, "^Button", ""))
			end
		end
		if actionId:sub(1, 4) == "Slot" then
			return "A"
		end
		return ""
	end
	if device == "Touch" then
		return ""
	end
	local key = self.Controllers.SettingsController:bind(actionId) or ""
	local pretty = {
		One = "1",
		Two = "2",
		Three = "3",
		Four = "4",
		Five = "5",
		Six = "6",
		Seven = "7",
		Eight = "8",
	}
	return pretty[key] or key
end

-- Consumes accumulated look input (pixels / stick units since last call).
function InputController:takeLook(dt: number): Vector2
	local delta = lookDelta
	lookDelta = Vector2.zero
	if rightStick.Magnitude > 0.15 then
		delta += Vector2.new(rightStick.X, -rightStick.Y) * 520 * dt
	end
	return delta
end

local function setDevice(new: string)
	if new ~= device then
		device = new
		InputController.DeviceChanged:Fire(device)
	end
end

local function classify(inputType: Enum.UserInputType)
	if inputType == Enum.UserInputType.Touch then
		setDevice("Touch")
	elseif inputType.Name:find("Gamepad") then
		setDevice("Gamepad")
	elseif inputType == Enum.UserInputType.Keyboard or inputType.Name:find("Mouse") then
		setDevice("Keyboard")
	end
end

function InputController:Start()
	rebuildKeys(self)
	self.Controllers.SettingsController.Changed:Connect(function(key)
		if key == "Binds" or key == "*" then
			rebuildKeys(self)
		end
	end)
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		setDevice("Touch")
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		setDevice("Gamepad")
	end
	UserInputService.LastInputTypeChanged:Connect(classify)

	UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			rmbDown = true
		end
		if input.UserInputType == Enum.UserInputType.Touch and not processed and touchLook == nil then
			touchLook = input
		end
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.Keyboard then
			local action = keyToAction[input.KeyCode.Name]
			if action then
				InputController.Action:Fire(action, "Begin")
			end
		elseif GAMEPAD[input.KeyCode] then
			InputController.Action:Fire(GAMEPAD[input.KeyCode], "Begin")
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			rmbDown = false
		end
		if touchLook == input then
			touchLook = nil
		end
		if input.UserInputType == Enum.UserInputType.Keyboard then
			local action = keyToAction[input.KeyCode.Name]
			if action then
				InputController.Action:Fire(action, "End")
			end
		elseif GAMEPAD[input.KeyCode] then
			InputController.Action:Fire(GAMEPAD[input.KeyCode], "End")
		end
	end)
	-- A release that happens outside the window never arrives.
	UserInputService.WindowFocusReleased:Connect(function()
		rmbDown = false
		touchLook = nil
		rightStick = Vector2.zero
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			if rmbDown and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
				lookDelta += Vector2.new(input.Delta.X, input.Delta.Y)
			else
				rmbDown = false
			end
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			rightStick = Vector2.new(input.Position.X, input.Position.Y)
		elseif input == touchLook then
			lookDelta += Vector2.new(input.Delta.X, input.Delta.Y) * 0.6
		end
	end)
end

return InputController

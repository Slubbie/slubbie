-- Input actions for keyboard, mouse, gamepad and touch, with remapping.
--
-- Gameplay code never reads keys directly: it asks Input whether an action is
-- held, when it was last pressed (for jump buffering), and listens to
-- Pressed/Released. Bindings come from Config/Settings defaults merged with the
-- player's saved remaps. Touch buttons call Input.Touch(action, down).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local SettingsConfig = require(ReplicatedStorage.Shared.Config.Settings)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local State = require(script.Parent.State)

local Input = {}

Input.Device = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "Touch" else "Keyboard"
Input.DeviceChanged = Signal.new() -- (device)
Input.Pressed = Signal.new() -- (action)
Input.Released = Signal.new() -- (action)
Input.Rebound = Signal.new() -- ()
-- False while menus are open: gameplay actions are ignored.
Input.GameplayEnabled = true

local GAMEPLAY = { Jump = true, Sprint = true, Crouch = true, Dash = true, Grapple = true, Retry = true, Emote = true, Mark = true }

type ActionState = { Held: boolean, PressedAt: number, ReleasedAt: number, Sources: { [string]: boolean } }
local actions: { [string]: ActionState } = {}
local bindings: { [string]: { Keyboard: { string }, Gamepad: { string } } } = {}
local keyToActions: { [string]: { string } } = {}

for _, def in SettingsConfig.Actions do
	actions[def.Id] = { Held = false, PressedAt = -math.huge, ReleasedAt = -math.huge, Sources = {} }
end

local function setSource(action: string, source: string, down: boolean)
	local state = actions[action]
	if not state then
		return
	end
	if down and GAMEPLAY[action] and not Input.GameplayEnabled then
		return
	end
	local wasHeld = state.Held
	state.Sources[source] = if down then true else nil
	state.Held = next(state.Sources) ~= nil
	if state.Held and not wasHeld then
		state.PressedAt = os.clock()
		Input.Pressed:Fire(action)
	elseif not state.Held and wasHeld then
		state.ReleasedAt = os.clock()
		Input.Released:Fire(action)
	end
end

function Input.Held(action: string): boolean
	local state = actions[action]
	return state ~= nil and state.Held
end

function Input.PressedAt(action: string): number
	local state = actions[action]
	return if state then state.PressedAt else -math.huge
end

function Input.ReleasedAt(action: string): number
	local state = actions[action]
	return if state then state.ReleasedAt else -math.huge
end

-- Was the action pressed within the last `window` seconds (and not consumed)?
function Input.Buffered(action: string, window: number): boolean
	return os.clock() - Input.PressedAt(action) <= window
end

-- Use up a buffered press so it can't trigger twice.
function Input.Consume(action: string)
	local state = actions[action]
	if state then
		state.PressedAt = -math.huge
	end
end

-- Release everything (menus opening, respawns).
function Input.ReleaseAll()
	for name, state in actions do
		if state.Held then
			table.clear(state.Sources)
			state.Held = false
			state.ReleasedAt = os.clock()
			Input.Released:Fire(name)
		end
	end
end

function Input.Touch(action: string, down: boolean)
	setSource(action, "Touch", down)
end

-- Bindings ------------------------------------------------------------------------

local function rebuild()
	table.clear(keyToActions)
	for action, entry in bindings do
		for _, device in { "Keyboard", "Gamepad" } do
			for _, key in entry[device] do
				local list = keyToActions[key]
				if not list then
					list = {}
					keyToActions[key] = list
				end
				table.insert(list, action)
			end
		end
	end
	-- Jump keys go through ContextActionService so the default controls never jump on their own.
	ContextActionService:UnbindAction("SkylineJump")
	local codes = {}
	for _, name in ((bindings.Jump and bindings.Jump.Keyboard) or {}) :: { string } do
		local ok, code = pcall(function()
			return (Enum.KeyCode :: any)[name]
		end)
		if ok and code then
			table.insert(codes, code)
		end
	end
	for _, name in ((bindings.Jump and bindings.Jump.Gamepad) or {}) :: { string } do
		local ok, code = pcall(function()
			return (Enum.KeyCode :: any)[name]
		end)
		if ok and code then
			table.insert(codes, code)
		end
	end
	-- Always swallow the default jump keys too.
	table.insert(codes, Enum.KeyCode.Space)
	table.insert(codes, Enum.KeyCode.ButtonA)
	ContextActionService:BindActionAtPriority("SkylineJump", function(_, inputState, inputObject)
		local name = inputObject.KeyCode.Name
		local isJump = false
		for _, action in (keyToActions[name] or {}) :: { string } do
			if action == "Jump" then
				isJump = true
			end
		end
		if isJump then
			setSource("Jump", "Key" .. name, inputState == Enum.UserInputState.Begin)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 50, table.unpack(codes))
	Input.Rebound:Fire()
end

function Input.Bindings(): { [string]: { Keyboard: { string }, Gamepad: { string } } }
	return bindings
end

local function applyBindings(saved: any)
	table.clear(bindings)
	for _, def in SettingsConfig.Actions do
		local custom = type(saved) == "table" and saved[def.Id] or nil
		bindings[def.Id] = {
			Keyboard = if custom and custom.Keyboard and #custom.Keyboard > 0 then table.clone(custom.Keyboard) else table.clone(def.Keyboard),
			Gamepad = if custom and custom.Gamepad and #custom.Gamepad > 0 then table.clone(custom.Gamepad) else table.clone(def.Gamepad),
		}
	end
	rebuild()
end

-- Replace the first binding for an action on a device; saved to the profile.
function Input.Rebind(action: string, device: string, keyName: string)
	local entry = bindings[action]
	if not entry or (device ~= "Keyboard" and device ~= "Gamepad") then
		return
	end
	-- A key can only do one thing: remove it from other actions first.
	for other, otherEntry in bindings do
		if other ~= action then
			local index = table.find(otherEntry[device], keyName)
			if index then
				table.remove(otherEntry[device], index)
			end
		end
	end
	entry[device] = { keyName }
	rebuild()
	Net.Send("Settings.Save", nil, bindings)
end

function Input.ResetBindings()
	applyBindings(nil)
	Net.Send("Settings.Save", nil, {})
end

-- Short label for the current device: "Space", "A", "LMB"...
local SHORT = {
	Space = "Space",
	LeftShift = "Shift",
	RightShift = "Shift",
	LeftControl = "Ctrl",
	MouseButton1 = "LMB",
	MouseButton2 = "RMB",
	ButtonA = "A",
	ButtonB = "B",
	ButtonX = "X",
	ButtonY = "Y",
	ButtonL1 = "LB",
	ButtonR1 = "RB",
	ButtonL2 = "LT",
	ButtonR2 = "RT",
	ButtonL3 = "LS",
	ButtonR3 = "RS",
	DPadUp = "D-Up",
	DPadDown = "D-Down",
	DPadLeft = "D-Left",
	DPadRight = "D-Right",
}
local TOUCH_LABEL = {
	Jump = "Jump",
	Sprint = "Sprint",
	Crouch = "Crouch",
	Dash = "Dash",
	Grapple = "Hook",
	Retry = "Retry",
	Mark = "Mark",
	Move = "Stick",
}

function Input.Glyph(action: string): string
	if action == "Move" then
		return if Input.Device == "Gamepad" then "Left Stick" elseif Input.Device == "Touch" then "Stick" else "WASD"
	end
	if Input.Device == "Touch" then
		return TOUCH_LABEL[action] or action
	end
	local entry = bindings[action]
	if not entry then
		return action
	end
	local list = if Input.Device == "Gamepad" then entry.Gamepad else entry.Keyboard
	local key = list[1]
	if not key then
		return "Unbound"
	end
	return SHORT[key] or key
end

-- Raw input --------------------------------------------------------------------------

local function deviceFor(inputType: Enum.UserInputType): string?
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	elseif string.find(inputType.Name, "Gamepad") then
		return "Gamepad"
	elseif inputType == Enum.UserInputType.Keyboard or string.find(inputType.Name, "Mouse") then
		return "Keyboard"
	end
	return nil
end

local function keyName(input: InputObject): string?
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		return "MouseButton1"
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		return "MouseButton2"
	elseif input.KeyCode.Name ~= "Unknown" then
		return input.KeyCode.Name
	end
	return nil
end

function Input.Start()
	applyBindings(nil)
	State.On("Bindings", function(saved)
		applyBindings(SettingsConfig.SanitizeBindings(saved))
	end)

	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		local device = deviceFor(inputType)
		if device and device ~= Input.Device then
			Input.Device = device
			Input.DeviceChanged:Fire(device)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		local name = keyName(input)
		if not name then
			return
		end
		for _, action in (keyToActions[name] or {}) :: { string } do
			if action ~= "Jump" then
				-- Menus and chat swallow input; gameplay keys only count when free.
				if not gameProcessed or not GAMEPLAY[action] then
					if not gameProcessed or action == "Menu" then
						setSource(action, "Key" .. name, true)
					end
				end
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local name = keyName(input)
		if not name then
			return
		end
		for _, action in (keyToActions[name] or {}) :: { string } do
			if action ~= "Jump" then
				setSource(action, "Key" .. name, false)
			end
		end
	end)

	-- Touch jump: the default touch button sets Humanoid.Jump. Read it after the
	-- control scripts run, then clear it so our controller decides when to jump.
	local player = Players.LocalPlayer
	RunService:BindToRenderStep("SkylineTouchJump", Enum.RenderPriority.Input.Value + 1, function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			setSource("Jump", "TouchButton", humanoid.Jump and Input.GameplayEnabled)
			humanoid.Jump = false
		end
	end)
end

return Input

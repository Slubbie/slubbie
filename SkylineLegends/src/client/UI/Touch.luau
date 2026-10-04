-- On-screen controls for touch devices: a large jump button under the right
-- thumb with crouch/slide, dash, grapple, sprint and retry around it, plus a
-- menu button. Button size follows the Touch Button Size setting; abilities
-- you haven't unlocked yet stay hidden so the screen stays clear.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Bus = require(script.Parent.Parent.Core.Bus)
local Input = require(script.Parent.Parent.Core.Input)
local Settings = require(script.Parent.Parent.Core.Settings)
local Controller = require(script.Parent.Parent.Movement.Controller)
local Kit = require(script.Parent.Kit)
local Root = require(script.Parent.Root)

local C = Kit.Colors
local Touch = {}

type Spec = { Action: string, Label: string, Size: number, X: number, Y: number, Ability: string?, Toggle: boolean? }

-- Offsets from the bottom-right corner (before scaling).
local SPECS: { Spec } = {
	{ Action = "Jump", Label = "JUMP", Size = 96, X = -70, Y = -90 },
	{ Action = "Crouch", Label = "SLIDE", Size = 66, X = -176, Y = -52, Ability = "Slide" },
	{ Action = "Dash", Label = "DASH", Size = 62, X = -160, Y = -152, Ability = "Dash" },
	{ Action = "Grapple", Label = "HOOK", Size = 62, X = -80, Y = -198, Ability = "Grapple" },
	{ Action = "Sprint", Label = "RUN", Size = 54, X = -246, Y = -120, Toggle = true },
	{ Action = "Retry", Label = "↻", Size = 46, X = -40, Y = -262 },
}

local buttons: { [string]: { Button: TextButton, Spec: Spec } } = {}
local frame: Frame
local sprintOn = false

local function hideDefaultJump()
	local gui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local touchGui = gui and gui:FindFirstChild("TouchGui")
	local controls = touchGui and touchGui:FindFirstChild("TouchControlFrame")
	local jump = controls and controls:FindFirstChild("JumpButton")
	if jump and jump:IsA("GuiObject") then
		jump.Visible = false
	end
end

local function layout()
	local scale = Settings.Get("TouchButtonScale") or 1
	for _, entry in buttons do
		local spec = entry.Spec
		local size = spec.Size * scale
		entry.Button.Size = UDim2.fromOffset(size, size)
		entry.Button.Position = UDim2.new(1, spec.X * scale - size / 2, 1, spec.Y * scale - size / 2)
	end
end

local function make(spec: Spec)
	local button = Kit.new("TextButton", {
		Name = spec.Action,
		Text = spec.Label,
		AutoButtonColor = false,
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.35,
		TextColor3 = C.Text,
		Font = Kit.Fonts.Black,
		Active = true,
		Parent = frame,
	})
	Kit.TextSize(button, if spec.Size > 80 then 18 else 14)
	Kit.Corner(button, 999)
	local stroke = Kit.Stroke(button, C.Text, 2, 0.5)
	local active: InputObject? = nil
	local function set(down: boolean)
		button.BackgroundTransparency = if down then 0.05 else 0.35
		stroke.Transparency = if down then 0 else 0.5
	end
	button.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch or active then
			return
		end
		active = input
		if spec.Toggle then
			sprintOn = not sprintOn
			Input.Touch(spec.Action, sprintOn)
			set(sprintOn)
		else
			Input.Touch(spec.Action, true)
			set(true)
		end
	end)
	button.InputEnded:Connect(function(input)
		if input ~= active then
			return
		end
		active = nil
		if not spec.Toggle then
			Input.Touch(spec.Action, false)
			set(false)
		end
	end)
	buttons[spec.Action] = { Button = button, Spec = spec }
end

local function refresh()
	local touch = Input.Device == "Touch"
	frame.Visible = touch and Controller.Enabled
	if not touch then
		return
	end
	hideDefaultJump()
	for _, entry in buttons do
		local ability = entry.Spec.Ability
		entry.Button.Visible = ability == nil or Controller.Has(ability)
	end
	-- The grapple button lights up when there's something to hook.
	local hook = buttons.Grapple
	if hook then
		hook.Button.TextColor3 = if Controller.Info.GrappleTarget then C.Signal else C.Muted
	end
	local dash = buttons.Dash
	if dash then
		dash.Button.TextColor3 = if Controller.Info.DashCharges > 0 then C.Text else C.Faint
	end
end

function Touch.Start()
	local gui = Root.Get("Touch")
	frame = Kit.new("Frame", { Name = "Controls", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui })
	for _, spec in SPECS do
		make(spec)
	end
	local menu = Kit.Button(frame, "☰", function()
		Bus.OpenPage:Fire("Map", nil)
	end, "Ghost", { Size = UDim2.fromOffset(48, 48), Position = UDim2.new(1, -64, 0, GuiService:GetGuiInset().Y + 8) })
	menu.Name = "Menu"
	layout()
	Settings.Changed:Connect(function(id)
		if id == "TouchButtonScale" then
			layout()
		end
	end)
	Input.DeviceChanged:Connect(refresh)
	local last = 0
	RunService.Heartbeat:Connect(function()
		if os.clock() - last > 0.2 then
			last = os.clock()
			refresh()
		end
	end)
	refresh()
end

return Touch

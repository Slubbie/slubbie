-- Settings: controls (sprint/crouch modes, sensitivity per device, invert,
-- camera assist), full key and button remapping, camera and motion comfort
-- (reduced motion turns every effect off at once), interface and
-- accessibility (text and HUD size, high-contrast markers, hints), graphics
-- and audio. Everything saves to your profile.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local SettingsConfig = require(ReplicatedStorage.Shared.Config.Settings)

local Input = require(script.Parent.Parent.Parent.Core.Input)
local Settings = require(script.Parent.Parent.Parent.Core.Settings)
local Kit = require(script.Parent.Parent.Kit)

local C = Kit.Colors
local section = "Controls"
local capturing: { Action: string, Device: string, Button: TextButton }? = nil

local function settingRow(parent: Instance, def: SettingsConfig.SettingDef)
	local row = Kit.Panel(parent, {
		Size = UDim2.new(1, -8, 0, if def.Hint then 64 else 48),
		BackgroundColor3 = C.PanelLight,
		BackgroundTransparency = 0.35,
	})
	Kit.Padding(row, 6, 12)
	Kit.Label(row, def.Name, 15, { Font = Kit.Fonts.Bold, Size = UDim2.new(0.5, 0, 0, 22) })
	if def.Hint then
		Kit.Label(row, def.Hint, 12, {
			Position = UDim2.fromOffset(0, 24),
			Size = UDim2.new(0.55, 0, 0, 28),
			TextColor3 = C.Muted,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
	end
	local control: GuiObject
	local value = Settings.Get(def.Id)
	if def.Kind == "Toggle" then
		control = Kit.Toggle(row, value == true, function(on)
			Settings.Set(def.Id, on)
		end)
	elseif def.Kind == "Slider" then
		control = Kit.Slider(
			row,
			def.Min or 0,
			def.Max or 1,
			def.Step or 0.05,
			if type(value) == "number" then value else def.Default,
			function(v)
				Settings.Set(def.Id, v)
			end,
			function(v)
				if def.Max and def.Max > 10 then
					return tostring(math.floor(v + 0.5))
				end
				return ("%d%%"):format(math.floor(v * 100 + 0.5))
			end
		)
	else
		control = Kit.Choice(row, def.Choices or {}, tostring(value), function(choice)
			Settings.Set(def.Id, choice)
		end)
	end
	control.AnchorPoint = Vector2.new(1, 0.5)
	control.Position = UDim2.new(1, 0, 0.5, 0)
end

local function keyLabel(list: { string }): string
	if #list == 0 then
		return "—"
	end
	return table.concat(list, " / ")
end

local function bindingRows(parent: Instance)
	Kit.Label(parent, "Key bindings", 18, { Font = Kit.Fonts.Black, TextColor3 = C.Accent })
	Kit.Paragraph(
		parent,
		"Click a binding, then press the key or button you want. A key can only do one thing, so it moves from any other action.",
		13,
		C.Muted
	)
	local bindings = Input.Bindings()
	for _, action in SettingsConfig.Actions do
		local entry = bindings[action.Id] or { Keyboard = {}, Gamepad = {} }
		local row = Kit.Panel(
			parent,
			{ Size = UDim2.new(1, -8, 0, 46), BackgroundColor3 = C.PanelLight, BackgroundTransparency = 0.35 }
		)
		Kit.Padding(row, 5, 12)
		Kit.Label(row, action.Name, 14, { Size = UDim2.new(0.45, 0, 1, 0) })
		for index, device in { "Keyboard", "Gamepad" } do
			local button = Kit.Button(row, keyLabel(entry[device] or {}), nil, "Secondary", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -(2 - index) * 170, 0.5, 0),
				Size = UDim2.fromOffset(160, 34),
			})
			button.Activated:Connect(function()
				capturing = { Action = action.Id, Device = device, Button = button }
				button.Text = if device == "Keyboard" then "Press a key…" else "Press a button…"
			end)
		end
	end
	Kit.Button(parent, "Reset all bindings", function()
		Input.ResetBindings()
	end, "Ghost", { Size = UDim2.fromOffset(200, 38) })
end

UserInputService.InputBegan:Connect(function(input)
	local capture = capturing
	if not capture then
		return
	end
	local name: string? = nil
	if capture.Device == "Keyboard" then
		if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode ~= Enum.KeyCode.Escape then
			name = input.KeyCode.Name
		elseif
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.MouseButton2
		then
			name = input.UserInputType.Name
		end
	elseif
		input.UserInputType == Enum.UserInputType.Gamepad1
		and (string.find(input.KeyCode.Name, "Button") or string.find(input.KeyCode.Name, "DPad"))
	then
		name = input.KeyCode.Name
	end
	if name then
		capturing = nil
		Input.Rebind(capture.Action, capture.Device, name)
		capture.Button.Text = name
	end
end)

return {
	Id = "Settings",
	Title = "Settings",
	Icon = "⚙",
	Order = 13,
	Build = function(container: Frame)
		capturing = nil
		local tabs = Kit.Row(container, 40, 8)
		local body = Kit.Scroll(container, { Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 1, -52) })
		Kit.List(body, false, 8)
		Kit.Padding(body, 4)
		local function render()
			Kit.Clear(body)
			for _, def in SettingsConfig.Definitions do
				if def.Section == section then
					settingRow(body, def)
				end
			end
			if section == "Controls" then
				bindingRows(body)
			end
		end
		for _, name in SettingsConfig.Sections do
			Kit.Button(
				tabs,
				name,
				function()
					section = name
					for _, child in tabs:GetChildren() do
						if child:IsA("TextButton") then
							child.BackgroundColor3 = if child.Text == section
								then C.Accent:Lerp(C.PanelLight, 0.5)
								else C.PanelLight
						end
					end
					render()
				end,
				"Secondary",
				{
					Size = UDim2.fromOffset(130, 36),
					BackgroundColor3 = if name == section then C.Accent:Lerp(C.PanelLight, 0.5) else C.PanelLight,
				}
			)
		end
		render()
	end,
}

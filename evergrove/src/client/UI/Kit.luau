-- UI component kit. Every screen is built from these so the whole interface
-- shares one look, one set of animations and one accessibility behaviour.
--
-- Colours are "painted" from the active Theme palette and repainted live when
-- the theme, high-contrast or colour-blind settings change (Kit.Retheme).
-- Animations respect Reduce Motion. Buttons are gamepad-selectable and play
-- the interface sounds.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Registry = require(Shared.Lib.Registry)
local ItemUtil = require(Shared.Lib.ItemUtil)
local Genetics = require(Shared.Lib.Genetics)
local Format = require(Shared.Lib.Format)

local Theme = require(script.Parent.Theme)

local Kit = {}
Kit.Theme = Theme

-- Hooks set by controllers (kept here to avoid require cycles).
Kit.PlaySound = function(_name: string) end
Kit.ReducedMotion = false
Kit.SimpleUI = false
Kit.TooltipLayer = nil :: Instance?

-- Theming ----------------------------------------------------------------------------------------------------------

local painted: { [Instance]: { [string]: string } } = setmetatable({} :: any, { __mode = "k" })

function Kit.Paint(inst: Instance, prop: string, key: string)
	painted[inst] = painted[inst] or {}
	painted[inst][prop] = key
	;(inst :: any)[prop] = (Theme.Current :: any)[key]
end

function Kit.Retheme()
	for inst, props in painted do
		if inst.Parent then
			for prop, key in props do
				(inst :: any)[prop] = (Theme.Current :: any)[key]
			end
		end
	end
end

-- Construction helpers ------------------------------------------------------------------------------------------------

function Kit.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	for k, v in pairs(props or {}) do
		if k == "Parent" then
			parent = v
		else
			(inst :: any)[k] = v
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Kit.Corner(parent: Instance, radius: number?): UICorner
	return Kit.new("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Sizes.Corner), Parent = parent })
end

function Kit.Stroke(parent: Instance, key: string?, thickness: number?, transparency: number?): UIStroke
	local stroke = Kit.new("UIStroke", { Thickness = thickness or Theme.Sizes.Stroke, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent })
	Kit.Paint(stroke, "Color", key or "Stroke")
	return stroke
end

function Kit.Padding(parent: Instance, all: number, horizontal: number?)
	local h = horizontal or all
	return Kit.new("UIPadding", { PaddingTop = UDim.new(0, all), PaddingBottom = UDim.new(0, all), PaddingLeft = UDim.new(0, h), PaddingRight = UDim.new(0, h), Parent = parent })
end

function Kit.List(parent: Instance, direction: string?, padding: number?, align: string?): UIListLayout
	local layout = Kit.new("UIListLayout", {
		FillDirection = if direction == "X" then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
	if align == "Center" then
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
	elseif align == "Right" then
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	end
	return layout
end

function Kit.Grid(parent: Instance, cell: number, padding: number?): UIGridLayout
	return Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(cell, cell),
		CellPadding = UDim2.fromOffset(padding or 6, padding or 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

function Kit.Gradient(parent: Instance, a: string, b: string, rotation: number?)
	local gradient = Kit.new("UIGradient", { Rotation = rotation or 90, Parent = parent })
	local function apply()
		gradient.Color = ColorSequence.new((Theme.Current :: any)[a], (Theme.Current :: any)[b])
	end
	apply()
	painted[gradient] = {}
	-- Gradients are repainted through a proxy attribute.
	gradient:SetAttribute("GradA", a)
	gradient:SetAttribute("GradB", b)
	return gradient
end

local function repaintGradients(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("UIGradient") and d:GetAttribute("GradA") then
			d.Color = ColorSequence.new((Theme.Current :: any)[d:GetAttribute("GradA")], (Theme.Current :: any)[d:GetAttribute("GradB")])
		end
	end
end
Kit.RepaintGradients = repaintGradients

-- Animation ---------------------------------------------------------------------------------------------------------------

function Kit.Tween(inst: Instance, props: { [string]: any }, time: number?, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local info = TweenInfo.new(if Kit.ReducedMotion then 0 else (time or 0.2), style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
	local tween = TweenService:Create(inst, info, props)
	tween:Play()
	return tween
end

local function scaleOf(gui: GuiObject): UIScale
	local s = gui:FindFirstChild("PopScale") :: UIScale?
	if not s then
		s = Kit.new("UIScale", { Name = "PopScale", Parent = gui })
	end
	return s :: UIScale
end

-- Springy entrance.
function Kit.Pop(gui: GuiObject, from: number?)
	local s = scaleOf(gui)
	if Kit.ReducedMotion then
		s.Scale = 1
		return
	end
	s.Scale = from or 0.85
	Kit.Tween(s, { Scale = 1 }, 0.35, Enum.EasingStyle.Back)
end

function Kit.PopOut(gui: GuiObject, callback: (() -> ())?)
	local s = scaleOf(gui)
	if Kit.ReducedMotion then
		if callback then
			callback()
		end
		return
	end
	local tween = Kit.Tween(s, { Scale = 0.9 }, 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	if callback then
		tween.Completed:Once(callback)
	end
end

function Kit.Pulse(gui: GuiObject)
	if Kit.ReducedMotion then
		return
	end
	local s = scaleOf(gui)
	s.Scale = 1.12
	Kit.Tween(s, { Scale = 1 }, 0.25, Enum.EasingStyle.Back)
end

-- Basic widgets ------------------------------------------------------------------------------------------------------

export type LabelProps = { Size: number?, Font: Enum.Font?, Color: string?, Wrap: boolean?, Align: string?, Rich: boolean? }

function Kit.Label(text: string, props: LabelProps?): TextLabel
	local p = props or {}
	local label = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		Font = p.Font or Theme.Fonts.Body,
		TextSize = Theme.Text(p.Size or Theme.Sizes.Body),
		TextWrapped = p.Wrap == true,
		RichText = p.Rich == true,
		TextXAlignment = if p.Align == "Center" then Enum.TextXAlignment.Center elseif p.Align == "Right" then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, Theme.Text(p.Size or Theme.Sizes.Body) + 6),
		AutomaticSize = if p.Wrap then Enum.AutomaticSize.Y else Enum.AutomaticSize.None,
	})
	Kit.Paint(label, "TextColor3", p.Color or "Text")
	return label
end

function Kit.Heading(text: string, size: number?): TextLabel
	return Kit.Label(text, { Size = size or Theme.Sizes.Heading, Font = Theme.Fonts.Heading })
end

function Kit.Panel(props: { [string]: any }?): Frame
	local p = props or {}
	local frame = Kit.new("Frame", { BorderSizePixel = 0, Size = p.Size or UDim2.fromScale(1, 1), Position = p.Position, AnchorPoint = p.AnchorPoint, Name = p.Name or "Panel" })
	Kit.Paint(frame, "BackgroundColor3", p.Color or "Panel")
	Kit.Corner(frame, p.Corner)
	if p.Stroke ~= false then
		Kit.Stroke(frame, p.StrokeKey)
	end
	if p.Shadow then
		local shadow = Kit.new("Frame", { Name = "Shadow", ZIndex = -1, BorderSizePixel = 0, BackgroundTransparency = 0.75, Size = UDim2.new(1, 8, 1, 10), Position = UDim2.fromOffset(-4, 2), Parent = frame })
		Kit.Paint(shadow, "BackgroundColor3", "Shadow")
		Kit.Corner(shadow, (p.Corner or Theme.Sizes.Corner) + 4)
	end
	return frame
end

export type ButtonProps = {
	Style: string?, -- Primary | Secondary | Danger | Ghost | Accent
	Icon: string?,
	Size: UDim2?,
	TextSize: number?,
	OnClick: (() -> ())?,
	Sound: string?,
	LayoutOrder: number?,
}

local STYLE_COLORS = {
	Primary = { "HeaderA", "HeaderText" },
	Secondary = { "PanelAlt", "Text" },
	Danger = { "Bad", "HeaderText" },
	Accent = { "Accent", "AccentText" },
	Ghost = { "Panel", "Text" },
	Good = { "Good", "HeaderText" },
}

function Kit.Button(text: string, props: ButtonProps?): TextButton
	local p = props or {}
	local style = STYLE_COLORS[p.Style or "Primary"] or STYLE_COLORS.Primary
	local button = Kit.new("TextButton", {
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = if p.Icon then p.Icon .. "  " .. text else text,
		Font = Theme.Fonts.Bold,
		TextSize = Theme.Text(p.TextSize or Theme.Sizes.Body),
		Size = p.Size or UDim2.new(0, 140, 0, 40),
		LayoutOrder = p.LayoutOrder or 0,
		Selectable = true,
	})
	Kit.Paint(button, "BackgroundColor3", style[1])
	Kit.Paint(button, "TextColor3", style[2])
	Kit.Corner(button, Theme.Sizes.SmallCorner)
	if p.Style == "Ghost" or p.Style == "Secondary" then
		Kit.Stroke(button, "Stroke", 1.5)
	end
	local s = scaleOf(button)
	button.MouseEnter:Connect(function()
		if button.Active then
			Kit.Tween(s, { Scale = 1.04 }, 0.12)
			Kit.PlaySound("UIHover")
		end
	end)
	button.MouseLeave:Connect(function()
		Kit.Tween(s, { Scale = 1 }, 0.12)
	end)
	button.MouseButton1Down:Connect(function()
		Kit.Tween(s, { Scale = 0.96 }, 0.06)
	end)
	button.MouseButton1Up:Connect(function()
		Kit.Tween(s, { Scale = 1.04 }, 0.1)
	end)
	button.Activated:Connect(function()
		if not button.Active then
			Kit.PlaySound("UIError")
			return
		end
		Kit.PlaySound(p.Sound or "UIClick")
		if p.OnClick then
			task.spawn(p.OnClick)
		end
	end)
	return button
end

function Kit.SetEnabled(button: GuiButton, enabled: boolean)
	button.Active = enabled
	button.AutoButtonColor = false
	button.BackgroundTransparency = if enabled then 0 else 0.45
	if button:IsA("TextButton") then
		button.TextTransparency = if enabled then 0 else 0.4
	end
end

-- Small square icon button with a tooltip.
function Kit.IconButton(icon: string, tip: string?, onClick: (() -> ())?, size: number?): TextButton
	local button = Kit.Button("", { Style = "Secondary", Size = UDim2.fromOffset(size or 38, size or 38), OnClick = onClick })
	button.Text = icon
	button.TextSize = Theme.Text(math.floor((size or 38) * 0.5))
	button.Font = Theme.Fonts.Body
	if tip then
		Kit.AttachTooltip(button, function()
			return { { Text = tip } }
		end)
	end
	return button
end

function Kit.TextBox(placeholder: string, props: { [string]: any }?): TextBox
	local p = props or {}
	local box = Kit.new("TextBox", {
		BorderSizePixel = 0,
		PlaceholderText = placeholder,
		Text = p.Text or "",
		ClearTextOnFocus = false,
		Font = Theme.Fonts.Body,
		TextSize = Theme.Text(p.TextSize or Theme.Sizes.Body),
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = p.Size or UDim2.new(1, 0, 0, 36),
	})
	Kit.Paint(box, "BackgroundColor3", "Inset")
	Kit.Paint(box, "TextColor3", "Text")
	Kit.Paint(box, "PlaceholderColor3", "SubText")
	Kit.Corner(box, Theme.Sizes.SmallCorner)
	Kit.Padding(box, 4, 10)
	if p.MaxLength then
		box:GetPropertyChangedSignal("Text"):Connect(function()
			if #box.Text > p.MaxLength then
				box.Text = string.sub(box.Text, 1, p.MaxLength)
			end
		end)
	end
	return box
end

function Kit.Scroll(props: { [string]: any }?): ScrollingFrame
	local p = props or {}
	local scroll = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = p.Size or UDim2.fromScale(1, 1),
		Position = p.Position,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = if p.Horizontal then Enum.AutomaticSize.X else Enum.AutomaticSize.Y,
		ScrollingDirection = if p.Horizontal then Enum.ScrollingDirection.X else Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		ScrollBarImageTransparency = 0.3,
		SelectionGroup = true,
	})
	Kit.Paint(scroll, "ScrollBarImageColor3", "Stroke")
	return scroll
end

function Kit.Progress(props: { [string]: any }?)
	local p = props or {}
	local back = Kit.new("Frame", { BorderSizePixel = 0, Size = p.Size or UDim2.new(1, 0, 0, 14), Name = "Progress" })
	Kit.Paint(back, "BackgroundColor3", "Inset")
	Kit.Corner(back, 7)
	local fill = Kit.new("Frame", { BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Name = "Fill", Parent = back })
	Kit.Paint(fill, "BackgroundColor3", p.Color or "Good")
	Kit.Corner(fill, 7)
	local label = Kit.new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = Theme.Fonts.Bold, TextSize = Theme.Text(Theme.Sizes.Tiny), Text = "", ZIndex = 3, Parent = back })
	Kit.Paint(label, "TextColor3", "Text")
	local obj = {}
	obj.Frame = back
	function obj.Set(fraction: number, text: string?, animate: boolean?)
		local f = math.clamp(fraction, 0, 1)
		if animate == false then
			fill.Size = UDim2.fromScale(f, 1)
		else
			Kit.Tween(fill, { Size = UDim2.fromScale(f, 1) }, 0.3)
		end
		label.Text = text or ""
	end
	function obj.SetColor(key: string)
		Kit.Paint(fill, "BackgroundColor3", key)
	end
	return obj
end

-- Tabs: returns { Frame, Select(id), Selected }.
function Kit.Tabs(tabs: { { Id: string, Label: string, Icon: string? } }, onSelect: (string) -> ())
	local bar = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 38), Name = "Tabs" })
	Kit.List(bar, "X", 6)
	local buttons = {}
	local obj = { Frame = bar, Selected = nil :: string? }
	function obj.Select(id: string)
		obj.Selected = id
		for tabId, button in buttons do
			local on = tabId == id
			Kit.Paint(button, "BackgroundColor3", if on then "HeaderA" else "PanelAlt")
			Kit.Paint(button, "TextColor3", if on then "HeaderText" else "Text")
		end
		onSelect(id)
	end
	for i, tab in tabs do
		local button = Kit.Button(tab.Label, { Style = "Secondary", Icon = tab.Icon, Size = UDim2.new(0, 0, 1, 0), LayoutOrder = i, TextSize = Theme.Sizes.Small, OnClick = function()
			obj.Select(tab.Id)
		end })
		button.AutomaticSize = Enum.AutomaticSize.X
		Kit.Padding(button, 0, 12)
		button.Parent = bar
		buttons[tab.Id] = button
	end
	return obj
end

function Kit.Toggle(value: boolean, onChange: (boolean) -> ())
	local button = Kit.new("TextButton", { AutoButtonColor = false, BorderSizePixel = 0, Text = "", Size = UDim2.fromOffset(52, 28), Selectable = true })
	Kit.Corner(button, 14)
	local knob = Kit.new("Frame", { BorderSizePixel = 0, Size = UDim2.fromOffset(22, 22), Parent = button })
	Kit.Corner(knob, 11)
	Kit.Paint(knob, "BackgroundColor3", "Panel")
	local state = value
	local function render()
		Kit.Paint(button, "BackgroundColor3", if state then "Good" else "Inset")
		Kit.Tween(knob, { Position = if state then UDim2.fromOffset(27, 3) else UDim2.fromOffset(3, 3) }, 0.15)
	end
	render()
	button.Activated:Connect(function()
		state = not state
		Kit.PlaySound("UIClick")
		render()
		onChange(state)
	end)
	return button, function(v: boolean)
		state = v
		render()
	end
end

function Kit.Slider(value: number, min: number, max: number, step: number?, onChange: (number) -> ())
	local frame = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28) })
	local track = Kit.new("TextButton", { AutoButtonColor = false, Text = "", BorderSizePixel = 0, Size = UDim2.new(1, -60, 0, 8), Position = UDim2.new(0, 0, 0.5, -4), Selectable = true, Parent = frame })
	Kit.Paint(track, "BackgroundColor3", "Inset")
	Kit.Corner(track, 4)
	local fill = Kit.new("Frame", { BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = track })
	Kit.Paint(fill, "BackgroundColor3", "HeaderA")
	Kit.Corner(fill, 4)
	local knob = Kit.new("Frame", { BorderSizePixel = 0, Size = UDim2.fromOffset(18, 18), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Parent = track })
	Kit.Paint(knob, "BackgroundColor3", "Accent")
	Kit.Corner(knob, 9)
	local readout = Kit.Label("", { Size = Theme.Sizes.Small, Align = "Right" })
	readout.Size = UDim2.new(0, 54, 1, 0)
	readout.Position = UDim2.new(1, -54, 0, 0)
	readout.Parent = frame
	local current = value
	local function render()
		local t = (current - min) / (max - min)
		fill.Size = UDim2.fromScale(t, 1)
		knob.Position = UDim2.fromScale(t, 0.5)
		readout.Text = if max <= 1.01 and min >= 0 then math.floor(current * 100 + 0.5) .. "%" else tostring(math.floor(current * 100 + 0.5) / 100)
	end
	local function setFromX(x: number)
		local t = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		local v = min + (max - min) * t
		if step and step > 0 then
			v = math.round(v / step) * step
		end
		v = math.clamp(v, min, max)
		if v ~= current then
			current = v
			render()
			onChange(v)
		end
	end
	local dragging = false
	local connections: { RBXScriptConnection } = {}
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))
	-- Gamepad: left/right nudges while the track is selected.
	table.insert(connections, UserInputService.InputBegan:Connect(function(input)
		if GuiService.SelectedObject == track and (input.KeyCode == Enum.KeyCode.DPadLeft or input.KeyCode == Enum.KeyCode.DPadRight) then
			local dir = if input.KeyCode == Enum.KeyCode.DPadRight then 1 else -1
			local nudge = step or (max - min) / 20
			current = math.clamp(current + dir * nudge, min, max)
			render()
			onChange(current)
		end
	end))
	frame.Destroying:Connect(function()
		for _, c in connections do
			c:Disconnect()
		end
	end)
	render()
	return frame
end

-- A button that cycles through options (works well on every input device).
function Kit.Choice(options: { string }, value: string, onChange: (string) -> ())
	local index = table.find(options, value) or 1
	local button = Kit.Button(options[index] .. "  ▸", { Style = "Secondary", Size = UDim2.new(0, 190, 0, 32), TextSize = Theme.Sizes.Small })
	button.Activated:Connect(function()
		index = index % #options + 1
		button.Text = options[index] .. "  ▸"
		onChange(options[index])
	end)
	return button
end

-- Rows and cards ---------------------------------------------------------------------------------------------------------

-- A horizontal row: left label + right widget.
function Kit.Row(labelText: string, widget: GuiObject, hint: string?): Frame
	local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, if hint then 50 else 36) })
	local label = Kit.Label(labelText, { Size = Theme.Sizes.Body })
	label.Size = UDim2.new(0.5, 0, 0, 22)
	label.Parent = row
	if hint then
		local h = Kit.Label(hint, { Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true })
		h.Size = UDim2.new(0.5, -8, 0, 0)
		h.Position = UDim2.fromOffset(0, 24)
		h.Parent = row
	end
	widget.AnchorPoint = Vector2.new(1, 0)
	widget.Position = UDim2.new(1, 0, 0, 2)
	if widget.Size.X.Scale == 1 then
		widget.Size = UDim2.new(0.48, 0, widget.Size.Y.Scale, widget.Size.Y.Offset)
	end
	widget.Parent = row
	return row
end

function Kit.Card(height: number?): Frame
	local card = Kit.Panel({ Size = UDim2.new(1, 0, 0, height or 64), Color = "PanelAlt", Corner = Theme.Sizes.SmallCorner })
	card.AutomaticSize = if height then Enum.AutomaticSize.None else Enum.AutomaticSize.Y
	Kit.Padding(card, 8, 10)
	return card
end

function Kit.Divider(): Frame
	local line = Kit.new("Frame", { BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 2), BackgroundTransparency = 0.4 })
	Kit.Paint(line, "BackgroundColor3", "Stroke")
	return line
end

-- Coins/tokens text.
function Kit.Money(amount: number, currency: string?): string
	local icon = if currency == "Tokens" then "🎟️" else "🪙"
	return icon .. " " .. Format.Commas(math.floor(amount))
end

-- Tooltip ---------------------------------------------------------------------------------------------------------------

export type TipLine = { Text: string, Color: (string | Color3)?, Size: number?, Bold: boolean? }

local tipFrame: Frame? = nil
local tipList: Frame? = nil
local tipOwner: GuiObject? = nil

local function ensureTip()
	if tipFrame then
		return
	end
	local frame = Kit.Panel({ Size = UDim2.fromOffset(260, 0), Name = "Tooltip", Shadow = true })
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Visible = false
	frame.ZIndex = 50
	Kit.Padding(frame, 10, 12)
	local list = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = frame })
	Kit.List(list, "Y", 3)
	frame.Parent = Kit.TooltipLayer
	tipFrame = frame
	tipList = list
end

function Kit.ShowTooltip(lines: { TipLine }, owner: GuiObject?)
	ensureTip()
	local frame, list = tipFrame :: Frame, tipList :: Frame
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for i, line in lines do
		local label = Kit.Label(line.Text, { Size = line.Size or Theme.Sizes.Small, Font = if line.Bold then Theme.Fonts.Bold else Theme.Fonts.Body, Wrap = true, Rich = true })
		label.LayoutOrder = i
		label.ZIndex = 51
		if typeof(line.Color) == "Color3" then
			label.TextColor3 = line.Color :: Color3
		elseif type(line.Color) == "string" then
			Kit.Paint(label, "TextColor3", line.Color :: string)
		end
		label.Parent = list
	end
	tipOwner = owner
	frame.Visible = #lines > 0
end

function Kit.HideTooltip(owner: GuiObject?)
	if tipFrame and (owner == nil or owner == tipOwner) then
		tipFrame.Visible = false
		tipOwner = nil
	end
end

function Kit.AttachTooltip(gui: GuiObject, build: () -> { TipLine }?)
	local function show()
		local lines = build()
		if lines and #lines > 0 then
			Kit.ShowTooltip(lines, gui)
		end
	end
	gui.MouseEnter:Connect(show)
	gui.SelectionGained:Connect(show)
	gui.MouseLeave:Connect(function()
		Kit.HideTooltip(gui)
	end)
	gui.SelectionLost:Connect(function()
		Kit.HideTooltip(gui)
	end)
	gui.Destroying:Connect(function()
		Kit.HideTooltip(gui)
	end)
end

-- Follow the pointer (or the selected gamepad object).
RunService.RenderStepped:Connect(function()
	local frame = tipFrame
	if not frame or not frame.Visible then
		return
	end
	local layer = Kit.TooltipLayer :: any
	local scale = if layer and layer:FindFirstChildOfClass("UIScale") then layer:FindFirstChildOfClass("UIScale").Scale else 1
	local pos
	local selected = GuiService.SelectedObject
	if selected and selected == tipOwner then
		pos = selected.AbsolutePosition + Vector2.new(selected.AbsoluteSize.X + 8, 0)
	else
		pos = UserInputService:GetMouseLocation() + Vector2.new(18, -18)
		local inset = GuiService:GetGuiInset()
		pos -= inset
	end
	local viewport = workspace.CurrentCamera.ViewportSize
	local size = frame.AbsoluteSize
	local x = math.min(pos.X, viewport.X - size.X - 8)
	local y = math.clamp(pos.Y, 8, math.max(8, viewport.Y - size.Y - 48))
	frame.Position = UDim2.fromOffset(x / scale, y / scale)
end)

-- Item presentation -------------------------------------------------------------------------------------------------------

function Kit.ItemIcon(id: string): string
	local def = Registry.Items[id]
	if not def then
		return "❔"
	end
	return def.Icon or "📦"
end

-- Rich tooltip lines for a stack.
function Kit.ItemTooltip(stack: any, extra: { TipLine }?): { TipLine }
	local def = Registry.Items[stack.Id]
	if not def then
		return { { Text = stack.Id } }
	end
	local rarity = ItemUtil.Rarity(stack)
	local r = Theme.Rarity(rarity)
	local lines: { TipLine } = {
		{ Text = (def.Icon or "") .. "  " .. ItemUtil.DisplayName(stack), Color = Theme.RarityColor(rarity), Size = Theme.Sizes.Body, Bold = true },
		{ Text = r.Glyph .. " " .. rarity .. " · " .. (def.Category or "Item"), Color = "SubText", Size = Theme.Sizes.Tiny },
	}
	if stack.Q and stack.Q > 1 then
		local tier = Theme.QualityTier(stack.Q)
		table.insert(lines, { Text = tier.Glyph .. " " .. tier.Name .. " quality (×" .. tier.Value .. " value)", Color = tier.Color })
	end
	if stack.M and #stack.M > 0 then
		local names = {}
		for _, id in stack.M do
			local mdef = ItemUtil.MutationDef(id)
			table.insert(names, (mdef and (mdef.Icon or "") .. " " .. mdef.Name) or id)
		end
		table.insert(lines, { Text = "🧬 " .. table.concat(names, ", ") .. string.format(" (×%.1f)", ItemUtil.MutationMultiplier(stack.M)), Color = "Info" })
	end
	if stack.S then
		local unit = if def.Category == "Fish" then " cm" else " kg"
		table.insert(lines, { Text = "📏 " .. tostring(stack.S) .. unit .. (if stack.U then " · Specimen" else ""), Color = "SubText" })
	end
	if stack.G and not Kit.SimpleUI then
		local g = stack.G
		table.insert(lines, { Text = string.format("🧪 Vigor %d · Bounty %d · Hardiness %d · Luster %d  (%.0f%%)", g[1] or 0, g[2] or 0, g[3] or 0, g[4] or 0, Genetics.GeneScore(g) * 100), Color = "SubText", Size = Theme.Sizes.Tiny })
	end
	if stack.T then
		local mdef = ItemUtil.MutationDef(stack.T)
		table.insert(lines, { Text = "💤 Latent trait: " .. (if mdef then mdef.Name else stack.T), Color = "Leaf", Size = Theme.Sizes.Tiny })
	end
	if def.Description and def.Description ~= "" then
		table.insert(lines, { Text = def.Description, Color = "Text", Size = Theme.Sizes.Small })
	end
	if not Kit.SimpleUI then
		local uses = Registry.UsesOf(stack.Id)
		if #uses > 0 then
			local shown = {}
			for i = 1, math.min(4, #uses) do
				table.insert(shown, uses[i])
			end
			table.insert(lines, { Text = "Used in: " .. table.concat(shown, ", ") .. (if #uses > 4 then "…" else ""), Color = "SubText", Size = Theme.Sizes.Tiny })
		end
	end
	if ItemUtil.Sellable(stack) then
		table.insert(lines, { Text = "Base value " .. Kit.Money(ItemUtil.UnitValue(stack)) .. (if stack.N > 1 then "  (stack " .. Kit.Money(ItemUtil.UnitValue(stack) * stack.N) .. ")" else ""), Color = "Accent", Size = Theme.Sizes.Small })
	end
	if stack.L then
		table.insert(lines, { Text = "🔒 Locked (won't be sold, trashed or traded)", Color = "Warn", Size = Theme.Sizes.Tiny })
	end
	for _, line in ipairs(extra or {}) do
		table.insert(lines, line)
	end
	return lines
end

-- An inventory slot. Returns an object with Set(stack?), SetSelected(bool), Button.
function Kit.ItemSlot(size: number?)
	local px = size or Theme.Sizes.Slot
	local button = Kit.new("TextButton", { AutoButtonColor = false, BorderSizePixel = 0, Text = "", Size = UDim2.fromOffset(px, px), Selectable = true, Name = "Slot" })
	Kit.Paint(button, "BackgroundColor3", "Slot")
	Kit.Corner(button, Theme.Sizes.SmallCorner)
	local stroke = Kit.new("UIStroke", { Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = button })
	local glow = Kit.new("UIGradient", { Enabled = false, Rotation = 45, Parent = stroke })
	local icon = Kit.new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = Theme.Fonts.Body, TextScaled = true, Text = "", Name = "Icon", Parent = button })
	Kit.new("UIPadding", { PaddingTop = UDim.new(0.16, 0), PaddingBottom = UDim.new(0.2, 0), PaddingLeft = UDim.new(0.16, 0), PaddingRight = UDim.new(0.16, 0), Parent = icon })
	local sub = Kit.new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(0.42, 0.42), Position = UDim2.fromScale(0.56, 0.02), Font = Theme.Fonts.Body, TextScaled = true, Text = "", Name = "SubIcon", Parent = button })
	local count = Kit.new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -4, 0, 16), Position = UDim2.new(0, 0, 1, -17), Font = Theme.Fonts.Number, TextSize = Theme.Text(13), TextXAlignment = Enum.TextXAlignment.Right, Text = "", Name = "Count", TextStrokeTransparency = 0.6, Parent = button })
	Kit.Paint(count, "TextColor3", "Text")
	local stars = Kit.new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -4, 0, 12), Position = UDim2.fromOffset(4, 2), Font = Theme.Fonts.Bold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, Text = "", Name = "Stars", TextStrokeTransparency = 0.5, Parent = button })
	local badge = Kit.new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(18, 18), Position = UDim2.new(0, 2, 1, -19), Font = Theme.Fonts.Body, TextSize = 13, Text = "", Name = "Badge", Parent = button })
	local lock = Kit.new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(16, 16), Position = UDim2.new(1, -17, 0, 1), Font = Theme.Fonts.Body, TextSize = 12, Text = "", Name = "Lock", Parent = button })
	local rarityGlyph = Kit.new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(14, 14), Position = UDim2.new(1, -15, 1, -32), Font = Theme.Fonts.Bold, TextSize = 11, Text = "", Name = "RarityGlyph", Parent = button })
	local obj = { Button = button, Stack = nil :: any, Selected = false }
	local s = scaleOf(button)
	button.MouseEnter:Connect(function()
		Kit.Paint(button, "BackgroundColor3", "SlotHover")
		Kit.Tween(s, { Scale = 1.05 }, 0.1)
	end)
	button.MouseLeave:Connect(function()
		Kit.Paint(button, "BackgroundColor3", if obj.Selected then "SlotHover" else "Slot")
		Kit.Tween(s, { Scale = 1 }, 0.1)
	end)
	function obj.Set(stack: any?)
		obj.Stack = stack
		if not stack then
			icon.Text = ""
			sub.Text = ""
			count.Text = ""
			stars.Text = ""
			badge.Text = ""
			lock.Text = ""
			rarityGlyph.Text = ""
			Kit.Paint(stroke, "Color", "Stroke")
			stroke.Transparency = 0.6
			glow.Enabled = false
			return
		end
		local def = Registry.Items[stack.Id]
		icon.Text = if def then def.Icon or "📦" else "❔"
		sub.Text = if def and def.SubIcon then def.SubIcon else ""
		count.Text = if stack.N and stack.N > 1 then Format.Short(stack.N) else ""
		local tier = Theme.QualityTier(stack.Q)
		stars.Text = tier.Glyph
		stars.TextColor3 = tier.Color
		local mcount = if stack.M then #stack.M else 0
		badge.Text = if mcount > 0 then "✨" elseif stack.U then "🏅" else ""
		lock.Text = if stack.L then "🔒" else ""
		local rarity = ItemUtil.Rarity(stack)
		local r = Theme.Rarity(rarity)
		stroke.Color = Theme.RarityColor(rarity)
		stroke.Transparency = if r.Order <= 1 then 0.55 else 0
		stroke.Thickness = if r.Order >= 4 then 3 else 2
		rarityGlyph.Text = if r.Order >= 2 then r.Glyph else ""
		rarityGlyph.TextColor3 = Theme.RarityColor(rarity)
		glow.Enabled = r.Glow
		if r.Glow then
			glow.Color = ColorSequence.new(Theme.RarityColor(rarity), Color3.new(1, 1, 1))
		end
	end
	function obj.SetSelected(on: boolean)
		obj.Selected = on
		Kit.Paint(button, "BackgroundColor3", if on then "SlotHover" else "Slot")
		if on then
			Kit.Pulse(button)
		end
	end
	Kit.AttachTooltip(button, function()
		return if obj.Stack then Kit.ItemTooltip(obj.Stack) else nil
	end)
	obj.Set(nil)
	return obj
end

-- Windows and modals --------------------------------------------------------------------------------------------------

-- A framed window with a gradient header. Returns { Root, Content, Header, Title, CloseButton }.
function Kit.Window(title: string, icon: string?, size: Vector2?)
	local w = size or Vector2.new(760, 520)
	local root = Kit.Panel({ Size = UDim2.fromOffset(w.X, w.Y), Name = "Window", Shadow = true })
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.52)
	root.Active = true
	root.SelectionGroup = true
	local header = Kit.new("Frame", { BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 52), Name = "Header", Parent = root })
	Kit.Paint(header, "BackgroundColor3", "HeaderA")
	Kit.Corner(header)
	Kit.Gradient(header, "HeaderA", "HeaderB", 90)
	-- Square off the header's bottom corners.
	local cover = Kit.new("Frame", { BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -14), Parent = header })
	Kit.Paint(cover, "BackgroundColor3", "HeaderB")
	-- Leafy accent
	local leaf = Kit.new("TextLabel", { BackgroundTransparency = 1, Text = "🌿", TextSize = 30, Font = Theme.Fonts.Body, Size = UDim2.fromOffset(40, 40), Position = UDim2.new(1, -96, 0, 6), TextTransparency = 0.35, Parent = header })
	leaf.Rotation = 20
	local titleLabel = Kit.Label((if icon then icon .. "  " else "") .. title, { Size = Theme.Sizes.Title, Font = Theme.Fonts.Heading, Color = "HeaderText" })
	titleLabel.Size = UDim2.new(1, -120, 1, 0)
	titleLabel.Position = UDim2.fromOffset(18, 0)
	titleLabel.Parent = header
	local close = Kit.Button("✕", { Style = "Danger", Size = UDim2.fromOffset(36, 36), Sound = "UIClose" })
	close.Position = UDim2.new(1, -44, 0, 8)
	close.Parent = header
	local content = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -24, 1, -68), Position = UDim2.fromOffset(12, 60), Name = "Content", Parent = root })
	return { Root = root, Content = content, Header = header, Title = titleLabel, CloseButton = close }
end

-- Confirmation dialog on the modal layer. Calls onResult(true/false).
Kit.ModalLayer = nil :: Instance?
function Kit.Confirm(title: string, body: string, onResult: (boolean) -> (), yesText: string?, danger: boolean?)
	local layer = Kit.ModalLayer
	if not layer then
		onResult(false)
		return
	end
	local shade = Kit.new("TextButton", { AutoButtonColor = false, Text = "", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Size = UDim2.fromScale(1, 1), ZIndex = 80, Parent = layer })
	local panel = Kit.Panel({ Size = UDim2.fromOffset(420, 0), Shadow = true })
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.ZIndex = 81
	panel.Parent = shade
	Kit.Padding(panel, 16, 18)
	Kit.List(panel, "Y", 10)
	local t = Kit.Heading(title)
	t.Parent = panel
	local b = Kit.Label(body, { Wrap = true, Color = "SubText" })
	b.LayoutOrder = 1
	b.Parent = panel
	local buttons = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 2, Parent = panel })
	Kit.List(buttons, "X", 10, "Right")
	local done = false
	local function finish(result: boolean)
		if done then
			return
		end
		done = true
		shade:Destroy()
		onResult(result)
	end
	local no = Kit.Button("Cancel", { Style = "Secondary", OnClick = function()
		finish(false)
	end })
	no.Parent = buttons
	local yes = Kit.Button(yesText or "Confirm", { Style = if danger then "Danger" else "Primary", OnClick = function()
		finish(true)
	end })
	yes.LayoutOrder = 1
	yes.Parent = buttons
	Kit.Pop(panel)
	GuiService.SelectedObject = yes
end

-- A small prompt asking for a number (quantities). onResult(n or nil).
function Kit.AskNumber(title: string, max: number, default: number, onResult: (number?) -> ())
	local layer = Kit.ModalLayer
	if not layer then
		onResult(nil)
		return
	end
	local shade = Kit.new("TextButton", { AutoButtonColor = false, Text = "", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Size = UDim2.fromScale(1, 1), ZIndex = 80, Parent = layer })
	local panel = Kit.Panel({ Size = UDim2.fromOffset(360, 0), Shadow = true })
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Parent = shade
	Kit.Padding(panel, 16, 18)
	Kit.List(panel, "Y", 10)
	Kit.Heading(title).Parent = panel
	local value = math.clamp(default, 1, math.max(1, max))
	local readout = Kit.Label(tostring(value) .. " / " .. max, { Align = "Center", Size = Theme.Sizes.Heading, Font = Theme.Fonts.Heading })
	readout.LayoutOrder = 1
	readout.Parent = panel
	local slider = Kit.Slider(value, 1, math.max(1, max), 1, function(v)
		value = math.floor(v)
		readout.Text = tostring(value) .. " / " .. max
	end)
	slider.LayoutOrder = 2
	slider.Parent = panel
	local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 3, Parent = panel })
	Kit.List(row, "X", 10, "Right")
	local done = false
	local function finish(v: number?)
		if done then
			return
		end
		done = true
		shade:Destroy()
		onResult(v)
	end
	local cancel = Kit.Button("Cancel", { Style = "Secondary", OnClick = function()
		finish(nil)
	end })
	cancel.Parent = row
	local ok = Kit.Button("OK", { OnClick = function()
		finish(value)
	end })
	ok.LayoutOrder = 1
	ok.Parent = row
	Kit.Pop(panel)
end

-- Empty-state message for lists.
function Kit.Empty(text: string): TextLabel
	local label = Kit.Label(text, { Align = "Center", Color = "SubText", Wrap = true })
	label.Size = UDim2.new(1, 0, 0, 60)
	return label
end

-- Clear a container's GUI children (keeps layouts/padding).
function Kit.Clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- Relative time for "3m ago" / "in 2h".
function Kit.Ago(unix: number): string
	local d = os.time() - unix
	if d < 60 then
		return "just now"
	end
	return Format.Duration(d) .. " ago"
end

Kit.LocalPlayer = Players.LocalPlayer

return Kit

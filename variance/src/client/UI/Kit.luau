-- Interface components. Every interactive element responds instantly to hover,
-- press, gamepad focus and touch, plays an interface sound, and supports being
-- disabled with a reason (shown as its tooltip), so the same controls work on
-- PC, console and mobile.

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local Motion = require(script.Parent.Motion)

local Kit = {}

-- Set by UIController: Kit.sound(name) plays an interface sound.
Kit.sound = function(_name: string) end
-- Set by UIController: the root ScreenGui (for modals and tooltips).
Kit.root = nil :: ScreenGui?

function Kit.create(className: string, props: { [string]: any }?, children: { Instance }?): Instance
	local instance = Instance.new(className)
	local parent = nil
	if props then
		for k, v in props do
			if k == "Parent" then
				parent = v
			else
				(instance :: any)[k] = v
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function Kit.corner(parent: Instance, radius: number?): UICorner
	return Kit.create("UICorner", { CornerRadius = UDim.new(0, radius or 3), Parent = parent }) :: UICorner
end

function Kit.stroke(parent: Instance, colorKey: string?, thickness: number?, transparency: number?): UIStroke
	local s = Kit.create("UIStroke", {
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	}) :: UIStroke
	Theme.bind(s, "Color", colorKey or "Line")
	return s
end

function Kit.padding(parent: Instance, all: number, horizontal: number?): UIPadding
	return Kit.create("UIPadding", {
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, horizontal or all),
		PaddingRight = UDim.new(0, horizontal or all),
		Parent = parent,
	}) :: UIPadding
end

function Kit.list(parent: Instance, direction: string?, padding: number?, align: string?): UIListLayout
	return Kit.create("UIListLayout", {
		FillDirection = direction == "X" and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align == "Center" and Enum.HorizontalAlignment.Center
			or (align == "Right" and Enum.HorizontalAlignment.Right or Enum.HorizontalAlignment.Left),
		VerticalAlignment = direction == "X" and Enum.VerticalAlignment.Center or Enum.VerticalAlignment.Top,
		Parent = parent,
	}) :: UIListLayout
end

function Kit.grid(parent: Instance, cell: UDim2, padding: number?): UIGridLayout
	return Kit.create("UIGridLayout", {
		CellSize = cell,
		CellPadding = UDim2.fromOffset(padding or 8, padding or 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	}) :: UIGridLayout
end

export type PanelProps = {
	Name: string?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Color: string?,
	Transparency: number?,
	Stroke: boolean?,
	Corner: number?,
	LayoutOrder: number?,
	ZIndex: number?,
	Visible: boolean?,
	Clip: boolean?,
}

function Kit.panel(parent: Instance?, props: PanelProps?): Frame
	local p = props or {}
	local frame = Kit.create("Frame", {
		Name = p.Name or "Panel",
		Size = p.Size or UDim2.fromScale(1, 1),
		Position = p.Position or UDim2.new(),
		AnchorPoint = p.AnchorPoint or Vector2.zero,
		BackgroundTransparency = p.Transparency or 0.04,
		BorderSizePixel = 0,
		LayoutOrder = p.LayoutOrder or 0,
		ZIndex = p.ZIndex or 1,
		Visible = p.Visible ~= false,
		ClipsDescendants = p.Clip == true,
		Parent = parent,
	}) :: Frame
	Theme.bind(frame, "BackgroundColor3", p.Color or "Panel")
	if p.Corner ~= 0 then
		Kit.corner(frame, p.Corner or 3)
	end
	if p.Stroke ~= false then
		Kit.stroke(frame, "Line", 1, 0)
	end
	return frame
end

export type LabelProps = {
	Name: string?,
	Text: string?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Font: string?,
	TextSize: string?,
	Color: string?,
	XAlign: string?,
	YAlign: string?,
	Wrap: boolean?,
	Rich: boolean?,
	AutoY: boolean?,
	LayoutOrder: number?,
	ZIndex: number?,
	Transparency: number?,
}

function Kit.label(parent: Instance?, props: LabelProps): TextLabel
	local label = Kit.create("TextLabel", {
		Name = props.Name or "Label",
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.new(1, 0, 0, Theme.textSize(props.TextSize or "Body") + 6),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Font = Theme.Fonts[props.Font or "Body"] or Theme.Fonts.Body,
		TextSize = Theme.textSize(props.TextSize or "Body"),
		Text = props.Text or "",
		TextWrapped = props.Wrap == true,
		RichText = props.Rich == true,
		TextXAlignment = props.XAlign == "Center" and Enum.TextXAlignment.Center
			or (props.XAlign == "Right" and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left),
		TextYAlignment = props.YAlign == "Top" and Enum.TextYAlignment.Top
			or (props.YAlign == "Bottom" and Enum.TextYAlignment.Bottom or Enum.TextYAlignment.Center),
		AutomaticSize = props.AutoY and Enum.AutomaticSize.Y or Enum.AutomaticSize.None,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		TextTransparency = props.Transparency or 0,
		Parent = parent,
	}) :: TextLabel
	Theme.bind(label, "TextColor3", props.Color or "Text")
	return label
end

-- A small keycap hint ("E", "1", "RB").
function Kit.keycap(parent: Instance?, text: string, order: number?): Frame
	local cap = Kit.create("Frame", {
		Name = "Keycap",
		BackgroundTransparency = 0.2,
		Size = UDim2.fromOffset(math.max(20, #text * 9 + 10), 20),
		LayoutOrder = order or 0,
		Parent = parent,
	}) :: Frame
	Theme.bind(cap, "BackgroundColor3", "Raised")
	Kit.corner(cap, 3)
	Kit.stroke(cap, "LineStrong", 1, 0)
	Kit.label(cap, {
		Text = text,
		Font = "Mono",
		TextSize = "Tiny",
		XAlign = "Center",
		Size = UDim2.fromScale(1, 1),
		Color = "Text",
	})
	return cap
end

---------------------------------------------------------------------------
-- Tooltips: any GuiObject with a "Tooltip" (or, when disabled, a
-- "DisabledReason") attribute shows it on hover or gamepad focus.
---------------------------------------------------------------------------

local tip: Frame? = nil
local tipLabel: TextLabel? = nil
local tipOwner: GuiObject? = nil

local function tipText(object: GuiObject): string?
	if object:GetAttribute("Enabled") == false and object:GetAttribute("DisabledReason") then
		return object:GetAttribute("DisabledReason")
	end
	return object:GetAttribute("Tooltip")
end

function Kit.showTip(object: GuiObject)
	local text = tipText(object)
	local root = Kit.root
	if text == nil or text == "" or root == nil then
		return
	end
	if tip == nil then
		local frame = Instance.new("Frame")
		frame.Name = "Tooltip"
		frame.BorderSizePixel = 0
		frame.BackgroundTransparency = 0.04
		frame.AutomaticSize = Enum.AutomaticSize.XY
		frame.Size = UDim2.fromOffset(0, 0)
		frame.ZIndex = 300
		Theme.bind(frame, "BackgroundColor3", "Bg")
		Kit.corner(frame, 3)
		Kit.stroke(frame, "LineStrong", 1, 0)
		Kit.padding(frame, 6, 10)
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.AutomaticSize = Enum.AutomaticSize.XY
		label.Size = UDim2.fromOffset(0, 0)
		label.TextWrapped = true
		label.RichText = true
		label.ZIndex = 301
		label.Parent = frame
		Theme.bind(label, "TextColor3", "Text")
		local limit = Instance.new("UISizeConstraint")
		limit.MaxSize = Vector2.new(300, 400)
		limit.Parent = label
		tip, tipLabel = frame, label
	end
	local frame, label = tip :: Frame, tipLabel :: TextLabel
	label.Font = Theme.Fonts.Body
	label.TextSize = Theme.textSize("Small")
	label.Text = text
	tipOwner = object
	frame.Parent = root
	local pos, size = object.AbsolutePosition, object.AbsoluteSize
	local inset = root.IgnoreGuiInset and 0 or 36
	local above = pos.Y > 140
	frame.AnchorPoint = Vector2.new(0.5, above and 1 or 0)
	frame.Position = UDim2.fromOffset(pos.X + size.X / 2, (above and pos.Y - 8 or pos.Y + size.Y + 8) + inset)
end

function Kit.hideTip(object: GuiObject?)
	if tip and (object == nil or object == tipOwner) then
		tip.Parent = nil
		tipOwner = nil
	end
end

-- Wires hover/focus tooltips onto any GuiObject.
function Kit.tooltip(object: GuiObject, text: string?)
	if text then
		object:SetAttribute("Tooltip", text)
	end
	if object:GetAttribute("TipWired") then
		return
	end
	object:SetAttribute("TipWired", true)
	object.MouseEnter:Connect(function()
		Kit.showTip(object)
	end)
	object.MouseLeave:Connect(function()
		Kit.hideTip(object)
	end)
	object.SelectionGained:Connect(function()
		Kit.showTip(object)
	end)
	object.SelectionLost:Connect(function()
		Kit.hideTip(object)
	end)
	object.AncestryChanged:Connect(function()
		if not object:IsDescendantOf(game) then
			Kit.hideTip(object)
		end
	end)
end

local selectionFrame: Frame? = nil
local function focusIndicator(): Frame
	if selectionFrame == nil then
		local f = Instance.new("Frame")
		f.Name = "Focus"
		f.BackgroundTransparency = 1
		f.Size = UDim2.new(1, 8, 1, 8)
		f.Position = UDim2.fromOffset(-4, -4)
		local s = Instance.new("UIStroke")
		s.Thickness = 2
		s.Color = Theme.Colors.Focus
		s.Parent = f
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 5)
		c.Parent = f
		selectionFrame = f
	end
	return selectionFrame :: Frame
end

local STYLE = {
	Default = { Bg = "PanelAlt", Hover = "Raised", Text = "Text", Stroke = "Line", HoverStroke = "Accent" },
	Primary = { Bg = "Accent", Hover = "Focus", Text = "Bg", Stroke = "Accent", HoverStroke = "Focus" },
	Danger = { Bg = "PanelAlt", Hover = "Raised", Text = "Bad", Stroke = "Bad", HoverStroke = "Bad" },
	Ghost = { Bg = "Panel", Hover = "PanelAlt", Text = "Dim", Stroke = "Line", HoverStroke = "LineStrong" },
}

export type ButtonProps = {
	Name: string?,
	Text: string,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Style: string?,
	Font: string?,
	TextSize: string?,
	Hotkey: string?,
	LayoutOrder: number?,
	OnClick: (() -> ())?,
	Tooltip: string?,
	ZIndex: number?,
	Sound: string?,
}

function Kit.button(parent: Instance?, props: ButtonProps): TextButton
	local style = STYLE[props.Style or "Default"] or STYLE.Default
	local button = Kit.create("TextButton", {
		Name = props.Name or "Button",
		AutoButtonColor = false,
		Size = props.Size or UDim2.new(1, 0, 0, 40),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Text = "",
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Selectable = true,
		SelectionImageObject = focusIndicator(),
		Parent = parent,
	}) :: TextButton
	Theme.bind(button, "BackgroundColor3", style.Bg)
	Kit.corner(button, 3)
	local stroke = Kit.stroke(button, style.Stroke, 1, 0)
	local label = Kit.label(button, {
		Name = "Text",
		Text = props.Text,
		Font = props.Font or "Bold",
		TextSize = props.TextSize or "Label",
		XAlign = "Center",
		Size = UDim2.fromScale(1, 1),
		Color = style.Text,
		ZIndex = (props.ZIndex or 1) + 1,
	})
	if props.Hotkey then
		local cap = Kit.keycap(button, props.Hotkey)
		cap.AnchorPoint = Vector2.new(1, 0.5)
		cap.Position = UDim2.new(1, -6, 0.5, 0)
		cap.ZIndex = (props.ZIndex or 1) + 2
	end
	button:SetAttribute("Enabled", true)
	button:SetAttribute("Tooltip", props.Tooltip)
	Kit.tooltip(button)
	local hovering = false
	local function refresh()
		local enabled = button:GetAttribute("Enabled") ~= false
		local active = button:GetAttribute("Active") == true
		local lit = (hovering or GuiService.SelectedObject == button or active) and enabled
		Theme.bind(button, "BackgroundColor3", lit and style.Hover or style.Bg)
		Theme.bind(stroke, "Color", lit and style.HoverStroke or style.Stroke)
		label.TextTransparency = enabled and 0 or 0.55
		button.BackgroundTransparency = enabled and 0 or 0.35
	end
	button.MouseEnter:Connect(function()
		hovering = true
		if button:GetAttribute("Enabled") ~= false then
			Kit.sound("Hover")
		end
		refresh()
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		refresh()
	end)
	button.SelectionGained:Connect(function()
		Kit.sound("Hover")
		refresh()
	end)
	button.SelectionLost:Connect(refresh)
	button.MouseButton1Down:Connect(function()
		if button:GetAttribute("Enabled") ~= false then
			Motion.punch(button, -0.035, 0.18)
		end
	end)
	button.Activated:Connect(function()
		if button:GetAttribute("Enabled") == false then
			Kit.sound("Deny")
			Motion.shake(button, 4, 0.2)
			return
		end
		Kit.sound(props.Sound or "Click")
		if props.OnClick then
			task.spawn(props.OnClick)
		end
	end)
	button:GetAttributeChangedSignal("Enabled"):Connect(refresh)
	button:GetAttributeChangedSignal("Active"):Connect(refresh)
	Theme.Changed:Connect(refresh)
	refresh()
	return button
end

function Kit.setEnabled(button: GuiButton, enabled: boolean, reason: string?)
	button:SetAttribute("Enabled", enabled)
	button:SetAttribute("DisabledReason", reason)
end

function Kit.setText(button: GuiButton, text: string)
	local label = button:FindFirstChild("Text") :: TextLabel?
	if label then
		label.Text = text
	end
end

-- On/off switch row.
function Kit.toggle(
	parent: Instance?,
	props: { Label: string, Value: boolean, OnChanged: (boolean) -> (), LayoutOrder: number? }
)
	local row = Kit.create("Frame", {
		Name = "Toggle",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 38),
		LayoutOrder = props.LayoutOrder or 0,
		Parent = parent,
	}) :: Frame
	Kit.label(
		row,
		{ Text = props.Label, Font = "Mono", TextSize = "Label", Size = UDim2.new(1, -90, 1, 0), Color = "Dim" }
	)
	local value = props.Value
	local button = Kit.button(row, {
		Text = value and "ON" or "OFF",
		Size = UDim2.fromOffset(80, 30),
		Position = UDim2.new(1, 0, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Style = value and "Primary" or "Default",
	})
	button.Activated:Connect(function()
		value = not value
		Kit.setText(button, value and "ON" or "OFF")
		Theme.bind(button, "BackgroundColor3", value and "Accent" or "PanelAlt")
		local text = button:FindFirstChild("Text") :: TextLabel
		Theme.bind(text, "TextColor3", value and "Bg" or "Text")
		props.OnChanged(value)
	end)
	return row
end

-- Horizontal slider with drag, click, and -/+ steppers (keyboard/gamepad friendly).
function Kit.slider(
	parent: Instance?,
	props: {
		Label: string,
		Min: number,
		Max: number,
		Step: number,
		Value: number,
		Format: ((number) -> string)?,
		OnChanged: (number) -> (),
		LayoutOrder: number?,
	}
)
	local row = Kit.create("Frame", {
		Name = "Slider",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 44),
		LayoutOrder = props.LayoutOrder or 0,
		Parent = parent,
	}) :: Frame
	local fmt = props.Format or function(v)
		return string.format("%d%%", math.floor(v * 100 + 0.5))
	end
	Kit.label(
		row,
		{ Text = props.Label, Font = "Mono", TextSize = "Label", Size = UDim2.new(0.4, 0, 1, 0), Color = "Dim" }
	)
	local readout = Kit.label(row, {
		Text = fmt(props.Value),
		Font = "Mono",
		TextSize = "Label",
		XAlign = "Right",
		Size = UDim2.new(0, 60, 1, 0),
		Position = UDim2.new(1, -60, 0, 0),
	})
	local minus = Kit.button(row, {
		Text = "-",
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.new(0.4, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Sound = "Tick",
	})
	local plus = Kit.button(row, {
		Text = "+",
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.new(1, -66, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Sound = "Tick",
	})
	local track = Kit.create("TextButton", {
		Name = "Track",
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.new(0.6, -140, 0, 6),
		Position = UDim2.new(0.4, 36, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BorderSizePixel = 0,
		Selectable = false,
		Parent = row,
	}) :: TextButton
	Theme.bind(track, "BackgroundColor3", "Raised")
	Kit.corner(track, 3)
	local fill = Kit.create(
		"Frame",
		{ Name = "Fill", BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = track }
	) :: Frame
	Theme.bind(fill, "BackgroundColor3", "Accent")
	Kit.corner(fill, 3)
	local knob = Kit.create("Frame", {
		Name = "Knob",
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(12, 18),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Parent = track,
	}) :: Frame
	Theme.bind(knob, "BackgroundColor3", "Text")
	Kit.corner(knob, 2)
	local value = props.Value
	local function set(v: number, fire: boolean)
		v = math.clamp(math.floor((v - props.Min) / props.Step + 0.5) * props.Step + props.Min, props.Min, props.Max)
		local changed = v ~= value
		value = v
		local t = (v - props.Min) / math.max(props.Max - props.Min, 1e-6)
		fill.Size = UDim2.fromScale(t, 1)
		knob.Position = UDim2.fromScale(t, 0.5)
		readout.Text = fmt(v)
		if fire and changed then
			Kit.sound("Tick")
			props.OnChanged(v)
		end
	end
	set(value, false)
	minus.Activated:Connect(function()
		set(value - props.Step, true)
	end)
	plus.Activated:Connect(function()
		set(value + props.Step, true)
	end)
	local dragging = false
	local function fromX(x: number)
		local t = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		set(props.Min + t * (props.Max - props.Min), true)
	end
	track.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			fromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if
			dragging
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			fromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = false
		end
	end)
	return row, function(v)
		set(v, false)
	end
end

-- Left/right option cycler.
function Kit.choice(
	parent: Instance?,
	props: {
		Label: string,
		Options: { string },
		Value: string,
		Display: ((string) -> string)?,
		OnChanged: (string) -> (),
		LayoutOrder: number?,
	}
)
	local row = Kit.create("Frame", {
		Name = "Choice",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 40),
		LayoutOrder = props.LayoutOrder or 0,
		Parent = parent,
	}) :: Frame
	Kit.label(
		row,
		{ Text = props.Label, Font = "Mono", TextSize = "Label", Size = UDim2.new(0.45, 0, 1, 0), Color = "Dim" }
	)
	local index = math.max(1, table.find(props.Options, props.Value) or 1)
	local display = props.Display or function(s)
		return string.upper(s)
	end
	local current = Kit.label(row, {
		Text = display(props.Options[index]),
		Font = "Mono",
		TextSize = "Label",
		XAlign = "Center",
		Size = UDim2.new(0.55, -72, 1, 0),
		Position = UDim2.new(0.45, 36, 0, 0),
	})
	local function step(delta: number)
		index = ((index - 1 + delta) % #props.Options) + 1
		current.Text = display(props.Options[index])
		Motion.punch(current, 0.06)
		props.OnChanged(props.Options[index])
	end
	Kit.button(row, {
		Text = "<",
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.new(0.45, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Sound = "Tick",
		OnClick = function()
			step(-1)
		end,
	})
	Kit.button(row, {
		Text = ">",
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.new(1, 0, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Sound = "Tick",
		OnClick = function()
			step(1)
		end,
	})
	return row
end

-- Tab strip. Returns (frame, select(id)).
function Kit.tabs(
	parent: Instance?,
	tabs: { { Id: string, Label: string } },
	onChanged: (string) -> (),
	height: number?
)
	local strip = Kit.create(
		"Frame",
		{ Name = "Tabs", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, height or 36), Parent = parent }
	) :: Frame
	Kit.list(strip, "X", 4)
	local buttons = {}
	local function choose(id: string)
		for tabId, button in buttons do
			button:SetAttribute("Active", tabId == id)
		end
		onChanged(id)
	end
	for i, tab in tabs do
		local b = Kit.button(strip, {
			Text = tab.Label,
			Size = UDim2.new(1 / #tabs, -4, 1, 0),
			Style = "Ghost",
			LayoutOrder = i,
			Sound = "Tab",
			OnClick = function()
				choose(tab.Id)
			end,
		})
		buttons[tab.Id] = b
	end
	return strip, choose
end

function Kit.scroll(
	parent: Instance?,
	props: { Size: UDim2?, Position: UDim2?, Padding: number?, Direction: string?, Name: string? }
): ScrollingFrame
	local frame = Kit.create("ScrollingFrame", {
		Name = props.Name or "Scroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		ScrollBarThickness = 4,
		ScrollingDirection = props.Direction == "X" and Enum.ScrollingDirection.X or Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = props.Direction == "X" and Enum.AutomaticSize.X or Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Selectable = false,
		Parent = parent,
	}) :: ScrollingFrame
	Theme.bind(frame, "ScrollBarImageColor3", "LineStrong")
	Kit.list(frame, props.Direction, props.Padding or 6)
	Kit.padding(frame, 2, 4)
	return frame
end

-- Progress bar. Kit.setBar(bar, 0..1).
function Kit.bar(
	parent: Instance?,
	props: { Size: UDim2?, Position: UDim2?, Color: string?, Value: number?, LayoutOrder: number? }
): Frame
	local bar = Kit.create("Frame", {
		Name = "Bar",
		BorderSizePixel = 0,
		Size = props.Size or UDim2.new(1, 0, 0, 6),
		Position = props.Position or UDim2.new(),
		LayoutOrder = props.LayoutOrder or 0,
		Parent = parent,
	}) :: Frame
	Theme.bind(bar, "BackgroundColor3", "Raised")
	Kit.corner(bar, 2)
	local fill = Kit.create("Frame", {
		Name = "Fill",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(math.clamp(props.Value or 0, 0, 1), 1),
		Parent = bar,
	}) :: Frame
	Theme.bind(fill, "BackgroundColor3", props.Color or "Accent")
	Kit.corner(fill, 2)
	return bar
end

function Kit.setBar(bar: Frame, value: number, animate: boolean?)
	local fill = bar:FindFirstChild("Fill") :: Frame?
	if fill == nil then
		return
	end
	local target = UDim2.fromScale(math.clamp(value, 0, 1), 1)
	if animate then
		Motion.tween(fill, 0.6, { Size = target }, "slide")
	else
		fill.Size = target
	end
end

-- Cell glyph. kind: "C" (CHARGED: filled diamond), "H" (HOLLOW: open ring),
-- "?" (unknown: dim slot), "~" (unknown but inverted: slot with a swap mark).
function Kit.glyph(parent: Instance?, kind: string, size: number): Frame
	local holder = Kit.create("Frame", {
		Name = "Glyph",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		Parent = parent,
	}) :: Frame
	if kind == "C" then
		local d = Kit.create("Frame", {
			Name = "Diamond",
			BorderSizePixel = 0,
			Size = UDim2.fromScale(0.62, 0.62),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = 45,
			Parent = holder,
		}) :: Frame
		Theme.bind(d, "BackgroundColor3", "Charged")
		Kit.corner(d, 1)
	elseif kind == "H" then
		local ring = Kit.create("Frame", {
			Name = "Ring",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(0.7, 0.7),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Parent = holder,
		}) :: Frame
		Kit.corner(ring, 999)
		local s = Kit.create("UIStroke", { Thickness = math.max(2, size * 0.1), Parent = ring }) :: UIStroke
		Theme.bind(s, "Color", "Hollow")
	else
		local slot = Kit.create("Frame", {
			Name = "Unknown",
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Parent = holder,
		}) :: Frame
		Theme.bind(slot, "BackgroundColor3", "Faint")
		Kit.corner(slot, 2)
		if kind == "~" then
			Kit.label(holder, {
				Text = "±",
				Font = "Mono",
				TextSize = "Small",
				XAlign = "Center",
				Size = UDim2.fromScale(1, 1),
				Color = "Text",
			})
		end
	end
	return holder
end

-- Integrity pips. Kit.setPips(frame, value, max).
function Kit.pips(parent: Instance?, max: number, value: number, pipSize: Vector2?): Frame
	local frame = Kit.create("Frame", {
		Name = "Pips",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Parent = parent,
	}) :: Frame
	Kit.list(frame, "X", 3)
	frame:SetAttribute("PipW", (pipSize or Vector2.new(14, 22)).X)
	frame:SetAttribute("PipH", (pipSize or Vector2.new(14, 22)).Y)
	Kit.setPips(frame, value, max)
	return frame
end

function Kit.setPips(frame: Frame, value: number, max: number)
	local w, h = frame:GetAttribute("PipW") or 14, frame:GetAttribute("PipH") or 22
	local existing = {}
	for _, child in frame:GetChildren() do
		if child:IsA("Frame") then
			table.insert(existing, child)
		end
	end
	for i = #existing + 1, max do
		local pip = Kit.create(
			"Frame",
			{ Name = "Pip" .. i, BorderSizePixel = 0, Size = UDim2.fromOffset(w, h), LayoutOrder = i, Parent = frame }
		) :: Frame
		Kit.corner(pip, 2)
		table.insert(existing, pip)
	end
	for i, pip in existing do
		if i > max then
			pip:Destroy()
		else
			local full = i <= value
			Theme.bind(pip, "BackgroundColor3", full and "Text" or "Raised")
			pip.BackgroundTransparency = full and 0 or 0.2
		end
	end
end

-- Subtle CRT scanlines over a container (static frames; cheap). `count` is the
-- number of lines across the container's height.
function Kit.scanlines(parent: Instance, count: number?, alpha: number?): Frame
	local layer = Kit.create(
		"Frame",
		{ Name = "Scanlines", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 50, Parent = parent }
	) :: Frame
	count = count or 90
	for i = 0, count - 1 do
		Kit.create("Frame", {
			BorderSizePixel = 0,
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 1 - (alpha or 0.08),
			Size = UDim2.new(1, 0, 0, 1),
			Position = UDim2.fromScale(0, i / count),
			ZIndex = 50,
			Parent = layer,
		})
	end
	return layer
end

function Kit.divider(parent: Instance?, order: number?): Frame
	local line = Kit.create("Frame", {
		Name = "Divider",
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 1),
		LayoutOrder = order or 0,
		Parent = parent,
	}) :: Frame
	Theme.bind(line, "BackgroundColor3", "Line")
	return line
end

-- A section header: small caps label with an accent tick.
function Kit.header(parent: Instance?, text: string, order: number?): Frame
	local row = Kit.create("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = order or 0,
		Parent = parent,
	}) :: Frame
	local tick = Kit.create("Frame", {
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(3, 14),
		Position = UDim2.new(0, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = row,
	}) :: Frame
	Theme.bind(tick, "BackgroundColor3", "Accent")
	Kit.label(row, {
		Text = text,
		Font = "Mono",
		TextSize = "Label",
		Color = "Accent",
		Size = UDim2.new(1, -10, 1, 0),
		Position = UDim2.fromOffset(10, 0),
	})
	return row
end

---------------------------------------------------------------------------
-- Modal dialogs
---------------------------------------------------------------------------

-- Shows a modal and yields until a button is chosen. Returns that button's
-- Value (nil if it was dismissed). opts.Tag lets Kit.dismiss close it.
function Kit.modal(
	title: string,
	body: string,
	buttons: { { Text: string, Style: string?, Value: any } },
	opts: { Tag: string? }?
): any
	local root = Kit.root
	if root == nil then
		return nil
	end
	local shade = Kit.create("TextButton", {
		Name = "ModalShade",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 200,
		Selectable = false,
		Parent = root,
	}) :: TextButton
	if opts and opts.Tag then
		shade:SetAttribute("ModalTag", opts.Tag)
	end
	Motion.tween(shade, 0.2, { BackgroundTransparency = 0.45 })
	local panel = Kit.panel(shade, {
		Name = "Modal",
		Size = UDim2.fromOffset(440, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 201,
	})
	panel.AutomaticSize = Enum.AutomaticSize.Y
	Kit.padding(panel, 18)
	Kit.list(panel, "Y", 10)
	Kit.label(
		panel,
		{ Text = title, Font = "Display", TextSize = "Title", Color = "Accent", ZIndex = 202, LayoutOrder = 1 }
	)
	Kit.label(
		panel,
		{ Text = body, Font = "Body", TextSize = "Body", Wrap = true, AutoY = true, ZIndex = 202, LayoutOrder = 2 }
	)
	local row = Kit.create(
		"Frame",
		{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 3, ZIndex = 202, Parent = panel }
	) :: Frame
	Kit.list(row, "X", 8, "Right")
	local result = nil
	local done = false
	local first = nil
	for i, spec in buttons do
		local b = Kit.button(row, {
			Text = spec.Text,
			Style = spec.Style or "Default",
			Size = UDim2.new(1 / #buttons, -8, 1, 0),
			LayoutOrder = i,
			ZIndex = 203,
			OnClick = function()
				if not done then
					done = true
					result = spec.Value
				end
			end,
		})
		first = first or b
	end
	panel.Position = UDim2.new(0.5, 0, 0.5, 16)
	Motion.tween(panel, 0.22, { Position = UDim2.fromScale(0.5, 0.5) }, "slide")
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = first
	end
	while not done and shade.Parent do
		task.wait()
	end
	shade:Destroy()
	return result
end

-- Closes open modals with this tag (their Kit.modal call returns nil).
function Kit.dismiss(tag: string)
	local root = Kit.root
	if root == nil then
		return
	end
	for _, child in root:GetChildren() do
		if child.Name == "ModalShade" and child:GetAttribute("ModalTag") == tag then
			child:Destroy()
		end
	end
end

function Kit.confirm(title: string, body: string, confirmText: string?, danger: boolean?): boolean
	local value = Kit.modal(title, body, {
		{ Text = "CANCEL", Style = "Ghost", Value = false },
		{ Text = confirmText or "CONFIRM", Style = danger and "Danger" or "Primary", Value = true },
	})
	return value == true
end

return Kit

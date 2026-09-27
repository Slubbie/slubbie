-- UI building blocks: consistent frames, labels, buttons (with hover / press / selected /
-- disabled states), progress bars, toggles and sliders.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)

local C = Theme.Colors

local Kit = {}

-- Set by the client when the Reduced Motion setting changes.
Kit.ReducedMotion = false
-- Optional click sound hook, set by the client.
Kit.OnClick = nil :: (() -> ())?

-- Creates an instance with properties and children. Children may be a list of instances.
function Kit.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	local properties: { [string]: any } = props or {}
	for key, value in properties do
		if key == "Parent" then
			parent = value
		else
			(inst :: any)[key] = value
		end
	end
	local kids: { Instance } = children or {}
	for _, child in kids do
		child.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Kit.Corner(parent: Instance, radius: number?): UICorner
	return Kit.new("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Radius), Parent = parent })
end

function Kit.Stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
	return Kit.new("UIStroke", {
		Color = color or C.Stroke,
		Thickness = thickness or Theme.StrokeWidth,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function Kit.Padding(parent: Instance, all: number, horizontal: number?): UIPadding
	local h = horizontal or all
	return Kit.new("UIPadding", {
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, h),
		PaddingRight = UDim.new(0, h),
		Parent = parent,
	})
end

function Kit.List(
	parent: Instance,
	direction: Enum.FillDirection?,
	padding: number?,
	align: Enum.HorizontalAlignment?
): UIListLayout
	return Kit.new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 6),
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

-- Rounded card with the standard stroke.
function Kit.Card(props: { [string]: any }): Frame
	local frame = Kit.new("Frame", {
		BackgroundColor3 = C.Panel,
		BorderSizePixel = 0,
	})
	for k, v in props do
		if k ~= "Parent" then
			(frame :: any)[k] = v
		end
	end
	Kit.Corner(frame)
	Kit.Stroke(frame)
	frame.Parent = props.Parent
	return frame
end

function Kit.Label(props: { [string]: any }): TextLabel
	local label = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		TextColor3 = C.Ink,
		TextSize = 16,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 20),
	})
	for k, v in props do
		if k ~= "Parent" then
			(label :: any)[k] = v
		end
	end
	label.Parent = props.Parent
	return label
end

function Kit.Tween(
	inst: Instance,
	seconds: number,
	goal: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local info = TweenInfo.new(
		if Kit.ReducedMotion then math.min(seconds, 0.08) else seconds,
		style or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out
	)
	local tween = TweenService:Create(inst, info, goal)
	tween:Play()
	return tween
end

local function shade(color: Color3, amount: number): Color3
	if amount > 0 then
		return color:Lerp(Color3.new(1, 1, 1), amount)
	end
	return color:Lerp(Color3.new(0, 0, 0), -amount)
end
Kit.Shade = shade

export type Button = {
	Instance: TextButton,
	Label: TextLabel,
	SetEnabled: (Button, boolean) -> (),
	SetSelected: (Button, boolean) -> (),
	SetText: (Button, string) -> (),
	SetColor: (Button, Color3) -> (),
	Enabled: boolean,
}

-- A button with clear hover, press, selected and disabled states.
-- props: Text, Color, TextColor, Size, Position, AnchorPoint, TextSize, Font, Parent, OnClick, LayoutOrder
function Kit.Button(props: { [string]: any }): Button
	local base: Color3 = props.Color or C.Green
	local textColor: Color3 = props.TextColor or C.White
	local instance = Kit.new("TextButton", {
		Size = props.Size or UDim2.fromOffset(140, 44),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundColor3 = base,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.LayoutOrder or 0,
		Name = props.Name or "Button",
		ZIndex = props.ZIndex or 1,
	})
	Kit.Corner(instance, props.Radius or 10)
	local stroke = Kit.Stroke(instance, shade(base, -0.35), 2)
	local scale = Kit.new("UIScale", { Parent = instance })
	local label = Kit.Label({
		Parent = instance,
		Size = UDim2.fromScale(1, 1),
		Text = props.Text or "",
		TextColor3 = textColor,
		TextSize = props.TextSize or 18,
		Font = props.Font or Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		ZIndex = instance.ZIndex,
	})
	Kit.Padding(label, 2, 6)

	local button = { Instance = instance, Label = label, Enabled = true } :: any
	local hovered, pressed, selected = false, false, false

	local function refresh()
		if not button.Enabled then
			instance.BackgroundColor3 = C.Disabled
			stroke.Color = shade(C.Disabled, -0.3)
			label.TextColor3 = C.DisabledInk
			scale.Scale = 1
			return
		end
		label.TextColor3 = textColor
		local color = base
		if pressed then
			color = shade(base, -0.15)
		elseif hovered then
			color = shade(base, 0.12)
		end
		instance.BackgroundColor3 = color
		stroke.Color = if selected then C.Gold else shade(base, -0.35)
		stroke.Thickness = if selected then 3 else 2
		local target = if pressed then 0.95 elseif hovered then 1.03 else 1
		if Kit.ReducedMotion then
			scale.Scale = target
		else
			TweenService:Create(scale, TweenInfo.new(0.08), { Scale = target }):Play()
		end
	end

	instance.MouseEnter:Connect(function()
		hovered = true
		refresh()
	end)
	instance.MouseLeave:Connect(function()
		hovered, pressed = false, false
		refresh()
	end)
	instance.MouseButton1Down:Connect(function()
		pressed = true
		refresh()
	end)
	instance.MouseButton1Up:Connect(function()
		pressed = false
		refresh()
	end)
	instance.Activated:Connect(function()
		if button.Enabled and props.OnClick then
			if Kit.OnClick then
				Kit.OnClick()
			end
			props.OnClick()
		end
	end)

	function button:SetEnabled(enabled: boolean)
		button.Enabled = enabled
		instance.Active = enabled
		refresh()
	end
	function button:SetSelected(value: boolean)
		selected = value
		refresh()
	end
	function button:SetText(text: string)
		label.Text = text
	end
	function button:SetColor(color: Color3)
		base = color
		refresh()
	end

	instance.Parent = props.Parent
	return button
end

export type Bar = { Instance: Frame, Fill: Frame, Set: (Bar, number, boolean?) -> () }

function Kit.Bar(props: { [string]: any }): Bar
	local back = Kit.new("Frame", {
		Size = props.Size or UDim2.new(1, 0, 0, 10),
		Position = props.Position or UDim2.new(),
		BackgroundColor3 = props.Back or C.PanelDeep,
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	})
	Kit.Corner(back, 6)
	local fill = Kit.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = props.Color or C.Gold,
		BorderSizePixel = 0,
		Parent = back,
	})
	Kit.Corner(fill, 6)
	local bar = { Instance = back, Fill = fill } :: any
	function bar:Set(fraction: number, animate: boolean?)
		local goal = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
		if animate then
			Kit.Tween(fill, 0.25, { Size = goal })
		else
			fill.Size = goal
		end
	end
	return bar
end

-- On/off switch. onChange(value) fires on user toggles.
function Kit.Toggle(parent: Instance, text: string, initial: boolean, onChange: (boolean) -> (), order: number?)
	local row = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		LayoutOrder = order or 0,
		Parent = parent,
	})
	Kit.Label({ Parent = row, Text = text, Size = UDim2.new(1, -90, 1, 0), TextSize = 17 })
	local value = initial
	local button: Button
	button = Kit.Button({
		Parent = row,
		Size = UDim2.fromOffset(80, 36),
		Position = UDim2.new(1, 0, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Text = if value then "ON" else "OFF",
		Color = if value then C.Green else C.InkFaint,
		OnClick = function()
			value = not value
			button:SetText(if value then "ON" else "OFF")
			button:SetColor(if value then C.Green else C.InkFaint)
			onChange(value)
		end,
	})
	return row
end

-- 0..1 slider. onChange(value) fires while dragging (callers should debounce saving).
function Kit.Slider(parent: Instance, text: string, initial: number, onChange: (number) -> (), order: number?)
	local row = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundTransparency = 1,
		LayoutOrder = order or 0,
		Parent = parent,
	})
	local label = Kit.Label({ Parent = row, Text = text, Size = UDim2.new(1, 0, 0, 22), TextSize = 17 })
	local track = Kit.new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.new(1, -16, 0, 12),
		Position = UDim2.new(0, 8, 0, 36),
		BackgroundColor3 = C.PanelDeep,
		Parent = row,
	})
	Kit.Corner(track, 6)
	local fill = Kit.new("Frame", { Size = UDim2.fromScale(initial, 1), BackgroundColor3 = C.Blue, Parent = track })
	Kit.Corner(fill, 6)
	local knob = Kit.new("Frame", {
		Size = UDim2.fromOffset(26, 26),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(initial, 0.5),
		BackgroundColor3 = C.White,
		Parent = track,
	})
	Kit.Corner(knob, 13)
	Kit.Stroke(knob, C.BlueDark, 2)

	local function set(x: number)
		local fraction = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		fraction = math.floor(fraction * 20 + 0.5) / 20
		fill.Size = UDim2.fromScale(fraction, 1)
		knob.Position = UDim2.fromScale(fraction, 0.5)
		label.Text = string.format("%s: %d%%", text, math.floor(fraction * 100 + 0.5))
		onChange(fraction)
	end
	label.Text = string.format("%s: %d%%", text, math.floor(initial * 100 + 0.5))

	local dragging = false
	track.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			set(input.Position.X)
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
			set(input.Position.X)
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
	return row
end

-- Small rounded tag, e.g. rarity or mutation chips.
function Kit.Chip(parent: Instance, text: string, color: Color3, textColor: Color3?, order: number?): TextLabel
	local chip = Kit.Label({
		Parent = parent,
		Text = text,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		TextSize = 12,
		Font = Theme.Fonts.Bold,
		TextColor3 = textColor or C.Ink,
		BackgroundTransparency = 0,
		BackgroundColor3 = color,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = order or 0,
	})
	Kit.Corner(chip, 6)
	Kit.Padding(chip, 0, 6)
	return chip
end

return Kit

-- The interface component kit. Every screen is assembled from these so the
-- game has one consistent look: layered rounded panels, soft strokes, gentle
-- gradients, and the same hover / press / focus / disabled / loading states
-- on every button. Sizes are design pixels; each ScreenGui has a UIScale that
-- adapts them to the device.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UITheme = require(Shared.UITheme)

local Components = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

Components.Colors = Colors
Components.Fonts = Fonts
Components.TextSize = UITheme.TextSize

-- Called when a button is clicked (the audio controller plugs a click sound in).
Components.OnClick = nil :: (() -> ())?
-- Set by the settings controller: shortens or removes UI motion.
Components.ReducedMotion = false

local scales: { UIScale } = {}
local currentScale = 1

-- Generic constructor: Components.Make("Frame", { props }, { children }).
function Components.Make(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(instance :: any)[key] = value
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
local Make = Components.Make

function Components.Corner(radius: number?): UICorner
	return Make("UICorner", { CornerRadius = UDim.new(0, radius or UITheme.Radius.Medium) })
end

function Components.Round(): UICorner
	return Make("UICorner", { CornerRadius = UDim.new(1, 0) })
end

function Components.Stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	return Make("UIStroke", {
		Color = color or Colors.Stroke,
		Thickness = thickness or 1.5,
		Transparency = transparency or 0.15,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Components.Padding(all: number, horizontal: number?): UIPadding
	return Make("UIPadding", {
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, horizontal or all),
		PaddingRight = UDim.new(0, horizontal or all),
	})
end

function Components.List(
	direction: Enum.FillDirection?,
	padding: number?,
	align: Enum.HorizontalAlignment?,
	valign: Enum.VerticalAlignment?
): UIListLayout
	return Make("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		VerticalAlignment = valign or Enum.VerticalAlignment.Top,
	})
end

function Components.Gradient(top: Color3, bottom: Color3, rotation: number?): UIGradient
	return Make("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = rotation or 90,
	})
end

function Components.Tween(
	instance: Instance,
	time: number,
	props: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local duration = if Components.ReducedMotion then math.min(time, 0.08) else time
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		props
	)
	tween:Play()
	return tween
end

-- A playful pop on any GuiObject (skipped with reduced motion).
function Components.Pop(target: GuiObject, strength: number?)
	if Components.ReducedMotion then
		return
	end
	local scale = target:FindFirstChild("PopScale") :: UIScale?
	if not scale then
		scale = Make("UIScale", { Name = "PopScale", Parent = target })
	end
	assert(scale)
	scale.Scale = 1 + (strength or 0.18)
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
end

function Components.Label(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		Font = Fonts.Bold,
		TextColor3 = Colors.Text,
		TextSize = UITheme.TextSize.Body,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 24),
	}
	for key, value in props do
		defaults[key] = value
	end
	return Make("TextLabel", defaults)
end

-- ScreenGui + UIScale that follows the device size.
function Components.Screen(name: string, displayOrder: number?, safeArea: boolean?): ScreenGui
	local gui = Make("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = displayOrder or 0,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ScreenInsets = if safeArea == false then Enum.ScreenInsets.None else Enum.ScreenInsets.CoreUISafeInsets,
	})
	local scale = Make("UIScale", { Name = "DeviceScale", Scale = currentScale, Parent = gui })
	table.insert(scales, scale)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

function Components.IsTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function Components.GetScale(): number
	return currentScale
end

-- Recomputes the UI scale for the current viewport.
function Components.UpdateScale(viewport: Vector2)
	local fit = math.min(viewport.X / 1280, viewport.Y / 760)
	local minimum = if Components.IsTouch() then 0.7 else 0.6
	currentScale = math.clamp(fit, minimum, 1.3)
	for _, scale in scales do
		scale.Scale = currentScale
	end
end

-- Buttons ---------------------------------------------------------------------

export type ButtonStyle = "Primary" | "Gold" | "Secondary" | "Danger" | "Ghost" | "Success"

local STYLES: { [string]: { Top: Color3, Bottom: Color3, Text: Color3, Stroke: Color3 } } = {
	Primary = {
		Top = Color3.fromHex("#9AF0FF"),
		Bottom = Colors.Cyan,
		Text = Colors.Background,
		Stroke = Color3.fromHex("#C8F7FF"),
	},
	Gold = {
		Top = Color3.fromHex("#FFE2A3"),
		Bottom = Colors.Gold,
		Text = Colors.Background,
		Stroke = Color3.fromHex("#FFF0CC"),
	},
	Success = {
		Top = Color3.fromHex("#A8F0C8"),
		Bottom = Colors.Green,
		Text = Colors.Background,
		Stroke = Color3.fromHex("#D4FAE6"),
	},
	Danger = {
		Top = Color3.fromHex("#FFA3B5"),
		Bottom = Colors.Coral,
		Text = Colors.Background,
		Stroke = Color3.fromHex("#FFD0DA"),
	},
	Secondary = { Top = Colors.PanelRaised, Bottom = Colors.Panel, Text = Colors.Text, Stroke = Colors.Stroke },
	Ghost = { Top = Colors.PanelSunken, Bottom = Colors.PanelSunken, Text = Colors.Muted, Stroke = Colors.Stroke },
}

export type Button = {
	Instance: TextButton,
	Label: TextLabel,
	SetText: (self: Button, text: string) -> (),
	SetEnabled: (self: Button, enabled: boolean) -> (),
	SetLoading: (self: Button, loading: boolean) -> (),
	SetStyle: (self: Button, style: ButtonStyle) -> (),
	Activated: RBXScriptSignal,
}

function Components.Button(text: string, style: ButtonStyle?, size: UDim2?, parent: Instance?): Button
	local current: ButtonStyle = style or "Primary"
	local spec = STYLES[current]
	local instance = Make("TextButton", {
		Name = "Button",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = size or UDim2.fromOffset(200, 48),
		Text = "",
		Selectable = true,
		Parent = parent,
	})
	Components.Corner(UITheme.Radius.Medium).Parent = instance
	local gradient = Components.Gradient(spec.Top, spec.Bottom)
	gradient.Parent = instance
	local stroke = Components.Stroke(spec.Stroke, 1.5, 0.35)
	stroke.Parent = instance
	local label = Components.Label({
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		Text = text,
		Font = Fonts.Heading,
		TextSize = UITheme.TextSize.Body + 1,
		TextColor3 = spec.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		TextScaled = false,
		Parent = instance,
	})
	Make("UITextSizeConstraint", { MaxTextSize = 22, MinTextSize = 12, Parent = label })
	label.TextScaled = true
	Components.Padding(6, 10).Parent = instance
	local scale = Make("UIScale", { Parent = instance })

	local enabled, loading = true, false
	local baseText = text
	local hovering = false

	local function refresh()
		local s = STYLES[current]
		gradient.Color = ColorSequence.new(s.Top, s.Bottom)
		stroke.Color = s.Stroke
		label.TextColor3 = s.Text
		instance.BackgroundTransparency = if enabled then 0 else 0.45
		label.TextTransparency = if enabled then 0 else 0.35
		stroke.Transparency = if hovering and enabled then 0 else 0.35
	end

	instance.MouseEnter:Connect(function()
		hovering = true
		refresh()
		if enabled then
			Components.Tween(scale, UITheme.Motion.Fast, { Scale = 1.04 })
		end
	end)
	instance.MouseLeave:Connect(function()
		hovering = false
		refresh()
		Components.Tween(scale, UITheme.Motion.Fast, { Scale = 1 })
	end)
	instance.SelectionGained:Connect(function()
		hovering = true
		refresh()
	end)
	instance.SelectionLost:Connect(function()
		hovering = false
		refresh()
	end)
	instance.MouseButton1Down:Connect(function()
		if enabled then
			Components.Tween(scale, 0.06, { Scale = 0.96 })
		end
	end)
	instance.MouseButton1Up:Connect(function()
		Components.Tween(scale, UITheme.Motion.Fast, { Scale = if hovering then 1.04 else 1 })
	end)
	instance.Activated:Connect(function()
		if enabled and not loading and Components.OnClick then
			Components.OnClick()
		end
	end)

	local button = {} :: any
	button.Instance = instance
	button.Label = label
	-- Fires only while the button is enabled and not loading.
	local activated = Instance.new("BindableEvent")
	instance.Activated:Connect(function()
		if enabled and not loading then
			activated:Fire()
		end
	end)
	button.Activated = activated.Event
	function button.SetText(_self, newText: string)
		baseText = newText
		if not loading then
			label.Text = newText
		end
	end
	function button.SetEnabled(_self, value: boolean)
		enabled = value
		instance.Selectable = value
		refresh()
	end
	function button.SetLoading(_self, value: boolean)
		loading = value
		label.Text = if value then "…" else baseText
		refresh()
	end
	function button.SetStyle(_self, newStyle: ButtonStyle)
		current = newStyle
		refresh()
	end
	refresh()
	return button :: Button
end

-- Square HUD button with an emoji icon, a caption and an optional badge.
export type IconButton = {
	Instance: TextButton,
	SetBadge: (self: IconButton, count: number?) -> (),
	SetHint: (self: IconButton, hint: string?) -> (),
	Activated: RBXScriptSignal,
}

function Components.IconButton(icon: string, caption: string, parent: Instance?): IconButton
	local instance = Make("TextButton", {
		Name = caption,
		AutoButtonColor = false,
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = 0.08,
		Size = UDim2.fromOffset(66, 66),
		Text = "",
		Parent = parent,
	})
	Components.Corner(18).Parent = instance
	local stroke = Components.Stroke(Colors.Stroke, 1.5, 0.2)
	stroke.Parent = instance
	Components.Gradient(Colors.PanelRaised, Colors.Panel).Parent = instance
	Components.Label({
		Name = "Icon",
		Text = icon,
		Font = Fonts.Heading,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 38),
		Position = UDim2.fromOffset(0, 5),
		Parent = instance,
	})
	Components.Label({
		Name = "Caption",
		Text = caption,
		Font = Fonts.Bold,
		TextSize = 12,
		TextColor3 = Colors.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.new(0, 0, 1, -21),
		Parent = instance,
	})
	local hint = Make("TextLabel", {
		Name = "Hint",
		BackgroundColor3 = Colors.Background,
		Size = UDim2.fromOffset(20, 18),
		Position = UDim2.new(1, -4, 0, -4),
		AnchorPoint = Vector2.new(1, 0),
		Font = Fonts.Heading,
		TextSize = 12,
		TextColor3 = Colors.Muted,
		Visible = false,
		Parent = instance,
	})
	Components.Corner(6).Parent = hint
	local badge = Make("TextLabel", {
		Name = "Badge",
		BackgroundColor3 = Colors.Coral,
		Size = UDim2.fromOffset(22, 22),
		Position = UDim2.new(1, 6, 0, -6),
		AnchorPoint = Vector2.new(1, 0),
		Font = Fonts.Heading,
		TextSize = 13,
		TextColor3 = Colors.Background,
		Visible = false,
		Parent = instance,
	})
	Components.Round().Parent = badge
	local scale = Make("UIScale", { Parent = instance })
	instance.MouseEnter:Connect(function()
		stroke.Color = Colors.Cyan
		Components.Tween(scale, UITheme.Motion.Fast, { Scale = 1.07 })
	end)
	instance.MouseLeave:Connect(function()
		stroke.Color = Colors.Stroke
		Components.Tween(scale, UITheme.Motion.Fast, { Scale = 1 })
	end)
	instance.MouseButton1Down:Connect(function()
		Components.Tween(scale, 0.06, { Scale = 0.94 })
	end)
	instance.MouseButton1Up:Connect(function()
		Components.Tween(scale, UITheme.Motion.Fast, { Scale = 1 })
	end)
	instance.Activated:Connect(function()
		if Components.OnClick then
			Components.OnClick()
		end
	end)
	local button = {} :: any
	button.Instance = instance
	button.Activated = instance.Activated
	function button.SetBadge(_self, count: number?)
		badge.Visible = count ~= nil and count > 0
		badge.Text = if count and count > 9 then "9+" else tostring(count or "")
		if badge.Visible then
			Components.Pop(badge, 0.4)
		end
	end
	function button.SetHint(_self, text: string?)
		hint.Visible = text ~= nil
		hint.Text = text or ""
		hint.Size = UDim2.fromOffset(math.max(20, 8 + #(text or "") * 8), 18)
	end
	return button :: IconButton
end

-- A rounded pill showing an icon and a value (currencies).
function Components.Pill(icon: string, accent: Color3, parent: Instance?): (Frame, TextLabel, TextLabel)
	local pill = Make("Frame", {
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = 0.06,
		Size = UDim2.fromOffset(170, 42),
		Parent = parent,
	})
	Components.Round().Parent = pill
	Components.Stroke(accent, 1.5, 0.45).Parent = pill
	local badge = Make("TextLabel", {
		Name = "Icon",
		BackgroundColor3 = accent,
		Size = UDim2.fromOffset(34, 34),
		Position = UDim2.fromOffset(4, 4),
		Font = Fonts.Heading,
		Text = icon,
		TextSize = 20,
		TextColor3 = Colors.Background,
		Parent = pill,
	})
	Components.Round().Parent = badge
	local value = Components.Label({
		Name = "Value",
		Text = "0",
		Font = Fonts.Display,
		TextSize = 22,
		TextWrapped = false,
		Size = UDim2.new(1, -48, 1, 0),
		Position = UDim2.fromOffset(44, -1),
		Parent = pill,
	})
	return pill, value, badge
end

-- Progress bar; returns the bar and a setter (alpha 0..1, animate?).
function Components.ProgressBar(fill: Color3, height: number?, parent: Instance?): (Frame, (number, boolean?) -> ())
	local bar = Make("Frame", {
		Name = "Progress",
		BackgroundColor3 = Colors.PanelSunken,
		Size = UDim2.new(1, 0, 0, height or 10),
		ClipsDescendants = true,
		Parent = parent,
	})
	Components.Round().Parent = bar
	local inner = Make("Frame", {
		Name = "Fill",
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromScale(0, 1),
		Parent = bar,
	})
	Components.Round().Parent = inner
	Components.Gradient(fill:Lerp(Color3.new(1, 1, 1), 0.3), fill, 0).Parent = inner
	local function set(alpha: number, animate: boolean?)
		local target = UDim2.fromScale(math.clamp(alpha, 0, 1), 1)
		if animate then
			Components.Tween(inner, 0.35, { Size = target })
		else
			inner.Size = target
		end
	end
	return bar, set
end

-- A toggle row: label on the left, switch on the right.
function Components.Toggle(
	text: string,
	description: string?,
	value: boolean,
	onChange: (boolean) -> (),
	parent: Instance?
): Frame
	local row = Make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, if description then 56 else 40),
		Parent = parent,
	})
	Components.Label({ Text = text, Size = UDim2.new(1, -80, 0, 24), Parent = row })
	if description then
		Components.Label({
			Text = description,
			Font = Fonts.Body,
			TextSize = UITheme.TextSize.Small,
			TextColor3 = Colors.Muted,
			Size = UDim2.new(1, -80, 0, 30),
			Position = UDim2.fromOffset(0, 24),
			Parent = row,
		})
	end
	local switch = Make("TextButton", {
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromOffset(58, 30),
		Position = UDim2.new(1, 0, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Colors.PanelSunken,
		Parent = row,
	})
	Components.Round().Parent = switch
	Components.Stroke(Colors.Stroke, 1.5, 0.2).Parent = switch
	local knob = Make("Frame", {
		Size = UDim2.fromOffset(24, 24),
		Position = UDim2.fromOffset(3, 3),
		BackgroundColor3 = Colors.Muted,
		Parent = switch,
	})
	Components.Round().Parent = knob
	local state = value
	local function render(animate: boolean)
		local props = {
			Position = if state then UDim2.fromOffset(31, 3) else UDim2.fromOffset(3, 3),
			BackgroundColor3 = if state then Colors.Cyan else Colors.Muted,
		}
		if animate then
			Components.Tween(knob, UITheme.Motion.Fast, props)
		else
			knob.Position = props.Position
			knob.BackgroundColor3 = props.BackgroundColor3
		end
		switch.BackgroundColor3 = if state then Color3.fromHex("#1E4A5C") else Colors.PanelSunken
	end
	switch.Activated:Connect(function()
		state = not state
		render(true)
		if Components.OnClick then
			Components.OnClick()
		end
		onChange(state)
	end)
	render(false)
	return row
end

-- A − [■■■□□] + stepper; works with mouse, touch and gamepad alike.
function Components.Stepper(
	text: string,
	value: number,
	step: number,
	onChange: (number) -> (),
	parent: Instance?
): Frame
	local row = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), Parent = parent })
	Components.Label({ Text = text, Size = UDim2.new(0.42, 0, 1, 0), Parent = row })
	local holder = Make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0.58, 0, 1, 0),
		Position = UDim2.fromScale(0.42, 0),
		Parent = row,
	})
	local minus = Components.Button("−", "Secondary", UDim2.fromOffset(40, 36), holder)
	local plus = Components.Button("+", "Secondary", UDim2.fromOffset(40, 36), holder)
	plus.Instance.Position = UDim2.new(1, -40, 0, 2)
	minus.Instance.Position = UDim2.fromOffset(0, 2)
	local bar, set = Components.ProgressBar(Colors.Cyan, 12, holder)
	bar.Size = UDim2.new(1, -100, 0, 12)
	bar.Position = UDim2.new(0, 50, 0.5, -6)
	local current = value
	set(current)
	local function change(delta: number)
		current = math.clamp(math.floor((current + delta) / step + 0.5) * step, 0, 1)
		set(current, true)
		onChange(current)
	end
	minus.Activated:Connect(function()
		change(-step)
	end)
	plus.Activated:Connect(function()
		change(step)
	end)
	return row
end

-- A panel window: header with title and close button, scrolling-capable body.
export type Panel = {
	Root: Frame,
	Body: Frame,
	Title: TextLabel,
	Close: TextButton,
	FirstSelectable: GuiObject?,
}

function Components.Panel(title: string, size: Vector2, parent: Instance): Panel
	local root = Make("Frame", {
		Name = title,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = 0.02,
		Visible = false,
		Parent = parent,
	})
	Components.Corner(UITheme.Radius.Large).Parent = root
	Components.Stroke(Colors.Stroke, 2, 0.1).Parent = root
	Components.Gradient(Color3.fromHex("#1C2550"), Colors.Panel).Parent = root
	-- Soft shadow.
	local shadow = Make("Frame", {
		Name = "Shadow",
		BackgroundColor3 = Colors.Black,
		BackgroundTransparency = 0.55,
		Size = UDim2.new(1, 16, 1, 16),
		Position = UDim2.fromOffset(-8, 4),
		ZIndex = 0,
		Parent = root,
	})
	Components.Corner(UITheme.Radius.Large + 6).Parent = shadow
	local header = Make("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 58),
		Parent = root,
	})
	local titleLabel = Components.Label({
		Name = "Title",
		Text = title,
		Font = Fonts.Display,
		TextSize = UITheme.TextSize.Title,
		Size = UDim2.new(1, -90, 1, 0),
		Position = UDim2.fromOffset(24, 4),
		TextWrapped = false,
		Parent = header,
	})
	local close = Make("TextButton", {
		Name = "Close",
		AutoButtonColor = false,
		BackgroundColor3 = Colors.PanelRaised,
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.new(1, -16, 0, 12),
		AnchorPoint = Vector2.new(1, 0),
		Text = "✕",
		Font = Fonts.Heading,
		TextSize = 20,
		TextColor3 = Colors.Muted,
		Parent = header,
	})
	Components.Round().Parent = close
	Components.Stroke(Colors.Stroke, 1.5, 0.2).Parent = close
	close.MouseEnter:Connect(function()
		close.TextColor3 = Colors.Coral
	end)
	close.MouseLeave:Connect(function()
		close.TextColor3 = Colors.Muted
	end)
	Make("Frame", {
		Name = "Divider",
		BackgroundColor3 = Colors.Stroke,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -40, 0, 1),
		Position = UDim2.fromOffset(20, 58),
		Parent = root,
	})
	local body = Make("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -40, 1, -78),
		Position = UDim2.fromOffset(20, 68),
		Parent = root,
	})
	return { Root = root, Body = body, Title = titleLabel, Close = close, FirstSelectable = nil }
end

-- Opens/closes a panel root with a gentle scale + fade.
function Components.ShowPanel(root: Frame, show: boolean)
	local scale = root:FindFirstChild("PanelScale") :: UIScale?
	if not scale then
		scale = Make("UIScale", { Name = "PanelScale", Parent = root })
	end
	assert(scale)
	if show then
		root.Visible = true
		if Components.ReducedMotion then
			scale.Scale = 1
		else
			scale.Scale = 0.92
			TweenService
				:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
				:Play()
		end
	else
		root.Visible = false
	end
end

-- Moves gamepad selection into a panel when the player is using a controller.
function Components.FocusFirst(target: GuiObject?)
	if not target then
		return
	end
	local last = UserInputService:GetLastInputType()
	if last.Name:find("Gamepad") then
		GuiService.SelectedObject = target
	end
end

-- Tabs: returns (holder, select(name)).
function Components.Tabs(names: { string }, onSelect: (string) -> (), parent: Instance): (Frame, (string) -> ())
	local holder = Make("Frame", {
		Name = "Tabs",
		BackgroundColor3 = Colors.PanelSunken,
		Size = UDim2.new(1, 0, 0, 42),
		Parent = parent,
	})
	Components.Round().Parent = holder
	Components.Padding(4).Parent = holder
	local layout = Components.List(Enum.FillDirection.Horizontal, 4)
	layout.Parent = holder
	local buttons: { [string]: TextButton } = {}
	local function select(name: string)
		for tabName, button in buttons do
			local active = tabName == name
			button.BackgroundColor3 = if active then Colors.PanelRaised else Colors.PanelSunken
			button.BackgroundTransparency = if active then 0 else 1
			button.TextColor3 = if active then Colors.Text else Colors.Muted
		end
		onSelect(name)
	end
	for i, name in names do
		local button = Make("TextButton", {
			Name = name,
			AutoButtonColor = false,
			LayoutOrder = i,
			Size = UDim2.new(1 / #names, -4, 1, 0),
			Font = Fonts.Heading,
			Text = name,
			TextSize = 16,
			TextColor3 = Colors.Muted,
			BackgroundTransparency = 1,
			Parent = holder,
		})
		Components.Round().Parent = button
		buttons[name] = button
		button.Activated:Connect(function()
			if Components.OnClick then
				Components.OnClick()
			end
			select(name)
		end)
	end
	return holder, select
end

-- A small rounded tag ("Rare", "Charged", "Deployed").
function Components.Tag(text: string, color: Color3, parent: Instance?): TextLabel
	local tag = Make("TextLabel", {
		BackgroundColor3 = color,
		BackgroundTransparency = 0.15,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		Font = Fonts.Heading,
		Text = text,
		TextSize = 12,
		TextColor3 = Colors.Background,
		Parent = parent,
	})
	Components.Round().Parent = tag
	Components.Padding(0, 8).Parent = tag
	return tag
end

return Components

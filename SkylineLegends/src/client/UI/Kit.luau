-- The interface toolkit: theme colours, text that follows the Text Size
-- setting, and small components (panels, buttons, bars, toggles, sliders,
-- choices, scrolling lists) shared by the HUD and every menu page.
--
-- Everything is built in code, so the place needs no uploaded images, and
-- every state that colour shows (locked, ready, warning...) is also shown
-- with text or a symbol.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Settings = require(script.Parent.Parent.Core.Settings)

local Kit = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Kit.Colors = {
	Background = rgb(12, 14, 20),
	Panel = rgb(20, 24, 33),
	PanelLight = rgb(32, 37, 50),
	Line = rgb(70, 78, 98),
	Text = rgb(240, 242, 248),
	Muted = rgb(160, 168, 186),
	Faint = rgb(110, 118, 136),
	Accent = rgb(255, 196, 92),
	Signal = rgb(80, 200, 255),
	Good = rgb(110, 230, 140),
	Bad = rgb(255, 110, 100),
	Warn = rgb(255, 176, 60),
	Prestige = rgb(255, 120, 110),
	Medal = {
		rgb(205, 127, 70),
		rgb(200, 210, 220),
		rgb(255, 200, 60),
		rgb(150, 235, 255),
	},
}
Kit.Fonts = {
	Body = Enum.Font.Gotham,
	Medium = Enum.Font.GothamMedium,
	Bold = Enum.Font.GothamBold,
	Black = Enum.Font.GothamBlack,
	Mono = Enum.Font.RobotoMono,
}

-- Text scaling -------------------------------------------------------------------------------------

local scaled: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any

local function textScale(): number
	return Settings.Get("TextScale") or 1
end

function Kit.TextSize(object: TextLabel | TextButton | TextBox, size: number)
	scaled[object] = size
	local target: any = object
	target.TextSize = math.floor(size * textScale() + 0.5)
end

Settings.Changed:Connect(function(id)
	if id == "TextScale" then
		for object, size in scaled do
			if object.Parent then
				(object :: any).TextSize = math.floor(size * textScale() + 0.5)
			end
		end
	end
end)

-- Construction ----------------------------------------------------------------------------------------

function Kit.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = nil
	for key, value in (props or {}) :: { [string]: any } do
		if key == "Parent" then
			parent = value
		else
			(instance :: any)[key] = value
		end
	end
	for _, child in (children or {}) :: { Instance } do
		child.Parent = instance
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function Kit.Corner(parent: Instance, radius: number?): UICorner
	return Kit.new("UICorner", { CornerRadius = UDim.new(0, radius or 10), Parent = parent })
end

function Kit.Stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
	return Kit.new("UIStroke", {
		Color = color or Kit.Colors.Line,
		Thickness = thickness or 1,
		Transparency = transparency or 0.4,
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
	horizontal: boolean?,
	spacing: number?,
	align: Enum.HorizontalAlignment?
): UIListLayout
	return Kit.new("UIListLayout", {
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, spacing or 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		VerticalAlignment = if horizontal then Enum.VerticalAlignment.Center else Enum.VerticalAlignment.Top,
		Parent = parent,
	})
end

function Kit.Panel(parent: Instance?, props: { [string]: any }?): Frame
	local frame = Kit.new("Frame", {
		BackgroundColor3 = Kit.Colors.Panel,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
	})
	for key, value in (props or {}) :: { [string]: any } do
		(frame :: any)[key] = value
	end
	Kit.Corner(frame, 12)
	Kit.Stroke(frame, Kit.Colors.Line, 1, 0.55)
	if parent then
		frame.Parent = parent
	end
	return frame
end

function Kit.Label(parent: Instance?, text: string, size: number?, props: { [string]: any }?): TextLabel
	local label = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = Kit.Colors.Text,
		Font = Kit.Fonts.Medium,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = true,
		RichText = true,
		Size = UDim2.new(1, 0, 0, math.floor((size or 16) * 1.5)),
		AutomaticSize = Enum.AutomaticSize.None,
	})
	for key, value in (props or {}) :: { [string]: any } do
		(label :: any)[key] = value
	end
	Kit.TextSize(label, size or 16)
	if parent then
		label.Parent = parent
	end
	return label
end

-- A paragraph that grows to fit its text.
function Kit.Paragraph(parent: Instance?, text: string, size: number?, color: Color3?): TextLabel
	return Kit.Label(parent, text, size or 15, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextColor3 = color or Kit.Colors.Muted,
		Font = Kit.Fonts.Body,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
end

local clickSound: Sound? = nil
local function click()
	local sound = clickSound
	if not sound then
		local s = Instance.new("Sound")
		s.SoundId = "rbxasset://sounds/electronicpingshort.wav"
		s.Volume = 0.15
		s.PlaybackSpeed = 2.2
		s.Parent = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui") or workspace
		clickSound = s
		sound = s
	end
	if sound then
		sound.TimePosition = 0
		sound:Play()
	end
end

export type ButtonStyle = "Primary" | "Secondary" | "Ghost" | "Danger"

function Kit.Button(
	parent: Instance?,
	text: string,
	onClick: (() -> ())?,
	style: ButtonStyle?,
	props: { [string]: any }?
): TextButton
	local kind = style or "Secondary"
	local base = if kind == "Primary"
		then Kit.Colors.Accent
		elseif kind == "Danger" then Kit.Colors.Bad
		elseif kind == "Ghost" then Kit.Colors.Panel
		else Kit.Colors.PanelLight
	local textColor = if kind == "Primary" then rgb(30, 22, 10) else Kit.Colors.Text
	local button = Kit.new("TextButton", {
		BackgroundColor3 = base,
		BackgroundTransparency = if kind == "Ghost" then 0.6 else 0,
		AutoButtonColor = false,
		Text = text,
		TextColor3 = textColor,
		Font = Kit.Fonts.Bold,
		Size = UDim2.new(0, 160, 0, 40),
		BorderSizePixel = 0,
		Selectable = true,
	})
	for key, value in (props or {}) :: { [string]: any } do
		(button :: any)[key] = value
	end
	Kit.TextSize(button, 16)
	Kit.Corner(button, 8)
	local stroke = Kit.Stroke(button, Kit.Colors.Text, 1.5, 1)
	local function hover(on: boolean)
		TweenService:Create(
			button,
			TweenInfo.new(0.12),
			{ BackgroundColor3 = if on then base:Lerp(Color3.new(1, 1, 1), 0.15) else base }
		):Play()
		stroke.Transparency = if on then 0.2 else 1
	end
	button.MouseEnter:Connect(function()
		hover(true)
	end)
	button.MouseLeave:Connect(function()
		hover(false)
	end)
	button.SelectionGained:Connect(function()
		hover(true)
	end)
	button.SelectionLost:Connect(function()
		hover(false)
	end)
	if onClick then
		button.Activated:Connect(function()
			click()
			onClick()
		end)
	end
	if parent then
		button.Parent = parent
	end
	return button
end

export type Bar = { Frame: Frame, Fill: Frame, Set: (number) -> (), Color: (Color3) -> () }

function Kit.Bar(parent: Instance?, color: Color3?, props: { [string]: any }?): Bar
	local frame = Kit.new("Frame", {
		BackgroundColor3 = rgb(40, 44, 56),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 8),
		ClipsDescendants = true,
	})
	for key, value in (props or {}) :: { [string]: any } do
		(frame :: any)[key] = value
	end
	Kit.Corner(frame, 4)
	local fill = Kit.new("Frame", {
		BackgroundColor3 = color or Kit.Colors.Accent,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = frame,
	})
	Kit.Corner(fill, 4)
	if parent then
		frame.Parent = parent
	end
	return {
		Frame = frame,
		Fill = fill,
		Set = function(value: number)
			fill.Size = UDim2.fromScale(math.clamp(value, 0, 1), 1)
		end,
		Color = function(c: Color3)
			fill.BackgroundColor3 = c
		end,
	}
end

function Kit.Scroll(parent: Instance?, props: { [string]: any }?): ScrollingFrame
	local scroll = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Kit.Colors.Line,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Selectable = false,
	})
	for key, value in (props or {}) :: { [string]: any } do
		(scroll :: any)[key] = value
	end
	if parent then
		scroll.Parent = parent
	end
	return scroll
end

-- Remove everything except layout helpers.
function Kit.Clear(container: Instance)
	for _, child in container:GetChildren() do
		if
			not child:IsA("UIListLayout")
			and not child:IsA("UIGridLayout")
			and not child:IsA("UIPadding")
			and not child:IsA("UICorner")
			and not child:IsA("UIStroke")
		then
			child:Destroy()
		end
	end
end

-- A row: a horizontal strip of fixed height.
function Kit.Row(parent: Instance?, height: number?, spacing: number?): Frame
	local row = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, height or 40),
	})
	Kit.List(row, true, spacing or 8)
	if parent then
		row.Parent = parent
	end
	return row
end

-- A card: a padded panel that grows with its content.
function Kit.Card(parent: Instance?, props: { [string]: any }?): Frame
	local card = Kit.Panel(nil, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Kit.Colors.PanelLight,
		BackgroundTransparency = 0.25,
	})
	for key, value in (props or {}) :: { [string]: any } do
		(card :: any)[key] = value
	end
	Kit.Padding(card, 12)
	Kit.List(card, false, 6)
	if parent then
		card.Parent = parent
	end
	return card
end

-- Controls ----------------------------------------------------------------------------------------------

function Kit.Toggle(parent: Instance?, value: boolean, onChange: (boolean) -> ()): TextButton
	local state = value
	local button = Kit.Button(nil, "", nil, "Secondary", { Size = UDim2.fromOffset(90, 34) })
	local function render()
		button.Text = if state then "ON" else "OFF"
		button.BackgroundColor3 = if state
			then Kit.Colors.Good:Lerp(Kit.Colors.PanelLight, 0.35)
			else Kit.Colors.PanelLight
	end
	button.Activated:Connect(function()
		state = not state
		render()
		onChange(state)
	end)
	render()
	if parent then
		button.Parent = parent
	end
	return button
end

function Kit.Choice(parent: Instance?, choices: { string }, value: string, onChange: (string) -> ()): TextButton
	local index = table.find(choices, value) or 1
	local button = Kit.Button(nil, "", nil, "Secondary", { Size = UDim2.fromOffset(150, 34) })
	local function render()
		button.Text = "‹  " .. choices[index] .. "  ›"
	end
	button.Activated:Connect(function()
		index = index % #choices + 1
		render()
		onChange(choices[index])
	end)
	button.MouseButton2Click:Connect(function()
		index = (index - 2) % #choices + 1
		render()
		onChange(choices[index])
	end)
	render()
	if parent then
		button.Parent = parent
	end
	return button
end

-- A slider with - and + buttons (works with mouse, touch and gamepad).
function Kit.Slider(
	parent: Instance?,
	min: number,
	max: number,
	step: number,
	value: number,
	onChange: (number) -> (),
	format: ((number) -> string)?
): Frame
	local current = value
	local frame = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(260, 34) })
	Kit.List(frame, true, 6)
	local minus = Kit.Button(frame, "−", nil, "Secondary", { Size = UDim2.fromOffset(34, 34), LayoutOrder = 1 })
	local track = Kit.new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = rgb(40, 44, 56),
		Size = UDim2.fromOffset(130, 10),
		LayoutOrder = 2,
		Parent = frame,
	})
	Kit.Corner(track, 5)
	local fill = Kit.new("Frame", { BackgroundColor3 = Kit.Colors.Signal, BorderSizePixel = 0, Parent = track })
	Kit.Corner(fill, 5)
	local plus = Kit.Button(frame, "+", nil, "Secondary", { Size = UDim2.fromOffset(34, 34), LayoutOrder = 3 })
	local label = Kit.Label(
		frame,
		"",
		14,
		{ Size = UDim2.fromOffset(46, 34), LayoutOrder = 4, TextXAlignment = Enum.TextXAlignment.Right }
	)
	local function render()
		local alpha = (current - min) / math.max(max - min, 1e-6)
		fill.Size = UDim2.fromScale(alpha, 1)
		label.Text = if format then format(current) else tostring(math.floor(current * 100 + 0.5) / 100)
	end
	local function set(v: number)
		v = math.clamp(math.floor(v / step + 0.5) * step, min, max)
		if math.abs(v - current) > 1e-6 then
			current = v
			render()
			onChange(current)
		end
	end
	minus.Activated:Connect(function()
		set(current - step)
	end)
	plus.Activated:Connect(function()
		set(current + step)
	end)
	track.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			local alpha = (input.Position.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1)
			set(min + (max - min) * math.clamp(alpha, 0, 1))
		end
	end)
	render()
	if parent then
		frame.Parent = parent
	end
	return frame
end

-- Formatting helpers -----------------------------------------------------------------------------------

function Kit.MedalText(medal: number): string
	local names = { "Bronze", "Silver", "Gold", "Platinum" }
	local glyphs = { "●", "◆", "★", "✦" }
	if medal <= 0 then
		return "No medal"
	end
	return glyphs[medal] .. " " .. names[medal]
end

function Kit.Rewards(rewards: { [string]: any }?): string
	if not rewards then
		return ""
	end
	local parts = {}
	if rewards.XP and rewards.XP > 0 then
		table.insert(parts, ("+%d XP"):format(rewards.XP))
	end
	if rewards.Credits and rewards.Credits > 0 then
		table.insert(parts, ("+%d ¢"):format(rewards.Credits))
	end
	if rewards.Prestige and rewards.Prestige > 0 then
		table.insert(parts, ("+%d ✪"):format(rewards.Prestige))
	end
	if rewards.Items and #rewards.Items > 0 then
		table.insert(parts, ("+%d item%s"):format(#rewards.Items, if #rewards.Items == 1 then "" else "s"))
	end
	return table.concat(parts, "   ")
end

return Kit

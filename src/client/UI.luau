-- Shared UI building blocks and style so every screen looks like one game.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)

local UI = {}

UI.Colors = {
	Panel = Color3.fromRGB(14, 18, 34),
	PanelLight = Color3.fromRGB(30, 36, 62),
	Accent = Config.Grapple.RopeColor,
	Text = Color3.new(1, 1, 1),
	Muted = Color3.fromRGB(165, 175, 200),
	Gold = Color3.fromRGB(255, 214, 90),
	Hot = Color3.fromRGB(255, 160, 70),
	Good = Color3.fromRGB(120, 255, 170),
	Bad = Color3.fromRGB(255, 90, 100),
}

UI.Fonts = {
	Title = Enum.Font.GothamBlack,
	Bold = Enum.Font.GothamBold,
	Body = Enum.Font.GothamMedium,
}

function UI.new(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	instance.Parent = parent
	return instance
end

function UI.corner(parent: Instance, radius: number?)
	return UI.new("UICorner", { CornerRadius = if radius then UDim.new(0, radius) else UDim.new(1, 0) }, parent)
end

function UI.stroke(parent: Instance, color: Color3, thickness: number?, transparency: number?)
	return UI.new("UIStroke", {
		Color = color,
		Thickness = thickness or 2,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

function UI.gui(name: string, displayOrder: number?): ScreenGui
	return UI.new("ScreenGui", {
		Name = name,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = displayOrder or 0,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, Players.LocalPlayer:WaitForChild("PlayerGui"))
end

function UI.label(parent: Instance, props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		Font = UI.Fonts.Bold,
		TextColor3 = UI.Colors.Text,
		TextSize = 18,
	}
	for key, value in props do
		defaults[key] = value
	end
	return UI.new("TextLabel", defaults, parent)
end

-- Bouncy "pop" scale animation on any GuiObject.
function UI.pop(target: GuiObject, strength: number?)
	local scale = target:FindFirstChildOfClass("UIScale") or UI.new("UIScale", {}, target)
	scale.Scale = 1 + (strength or 0.3)
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
end

function UI.tween(target: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?)
	local tween = TweenService:Create(
		target,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		props
	)
	tween:Play()
	return tween
end

-- Big chunky button with a hover grow.
function UI.button(parent: Instance, text: string, props: { [string]: any }?): TextButton
	local button = UI.new("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = UI.Colors.PanelLight,
		Font = UI.Fonts.Title,
		Text = text,
		TextColor3 = UI.Colors.Text,
		TextSize = 22,
		Size = UDim2.fromOffset(240, 52),
	}, parent)
	for key, value in props or {} do
		(button :: any)[key] = value
	end
	UI.corner(button, 12)
	local scale = UI.new("UIScale", {}, button)
	button.MouseEnter:Connect(function()
		UI.tween(scale, 0.12, { Scale = 1.05 })
	end)
	button.MouseLeave:Connect(function()
		UI.tween(scale, 0.12, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		UI.tween(scale, 0.06, { Scale = 0.96 })
	end)
	button.MouseButton1Up:Connect(function()
		UI.tween(scale, 0.1, { Scale = 1.05 })
	end)
	return button
end

-- A settings row: label on the left, control on the right. Returns the control slot.
function UI.row(parent: Instance, label: string, order: number): Frame
	local row = UI.new("Frame", {
		Size = UDim2.new(1, -8, 0, 44),
		BackgroundColor3 = UI.Colors.PanelLight,
		BackgroundTransparency = 0.3,
		LayoutOrder = order,
	}, parent)
	UI.corner(row, 10)
	UI.label(row, {
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(0.5, -14, 1, 0),
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = label,
	})
	return UI.new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.new(0.5, -10, 0, 32),
		BackgroundTransparency = 1,
	}, row)
end

function UI.header(parent: Instance, text: string, order: number)
	return UI.label(parent, {
		Size = UDim2.new(1, -8, 0, 26),
		Font = UI.Fonts.Title,
		TextSize = 14,
		TextColor3 = UI.Colors.Accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = order,
		Text = text,
	})
end

-- Button that shows the current value; clicking it calls `onClick`.
function UI.valueButton(slot: Instance, onClick: () -> ()): TextButton
	local button = UI.button(slot, "", {
		Size = UDim2.fromScale(1, 1),
		TextSize = 16,
		BackgroundColor3 = UI.Colors.Panel,
	})
	button.Activated:Connect(onClick)
	return button
end

-- Horizontal slider. Returns a setter to update it from outside.
function UI.slider(
	slot: Instance,
	min: number,
	max: number,
	step: number,
	format: (number) -> string,
	onChange: (number) -> ()
): (number) -> ()
	local UserInputService = game:GetService("UserInputService")
	local valueLabel = UI.label(slot, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(52, 24),
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
	})
	local hitbox = UI.new("TextButton", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, -62, 0, 28),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
	}, slot)
	local track = UI.new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = UI.Colors.Panel,
		BorderSizePixel = 0,
	}, hitbox)
	UI.corner(track)
	local fill = UI.new(
		"Frame",
		{ Size = UDim2.fromScale(0, 1), BackgroundColor3 = UI.Colors.Accent, BorderSizePixel = 0 },
		track
	)
	UI.corner(fill)
	local knob = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = UI.Colors.Text,
	}, track)
	UI.corner(knob)

	local function show(value: number)
		local alpha = (value - min) / (max - min)
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.fromScale(alpha, 0.5)
		valueLabel.Text = format(value)
	end
	local function setFromX(x: number)
		local alpha = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		local value = math.clamp(math.floor((min + alpha * (max - min)) / step + 0.5) * step, min, max)
		show(value)
		onChange(value)
	end

	local dragging = false
	hitbox.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			setFromX(input.Position.X)
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
			setFromX(input.Position.X)
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
	return show
end

function UI.formatTime(seconds: number): string
	return string.format("%d:%05.2f", math.floor(seconds / 60), seconds % 60)
end

-- Toasts: short messages that slide in at the top of the screen.
local toastGui: ScreenGui? = nil
local toastList: Frame? = nil

function UI.toast(text: string, color: Color3?)
	if not toastGui then
		toastGui = UI.gui("Toasts", 20)
		toastList = UI.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 90),
			Size = UDim2.fromOffset(500, 300),
			BackgroundTransparency = 1,
		}, toastGui)
		UI.new("UIListLayout", {
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 6),
		}, toastList)
	end
	local toast = UI.label(toastList :: Frame, {
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = UI.Colors.Panel,
		BackgroundTransparency = 0.2,
		Font = UI.Fonts.Title,
		TextSize = 22,
		TextColor3 = color or UI.Colors.Text,
		Text = "   " .. text .. "   ",
	})
	UI.corner(toast, 10)
	UI.pop(toast, 0.25)
	task.delay(2.6, function()
		UI.tween(toast, 0.4, { TextTransparency = 1, BackgroundTransparency = 1 })
		task.wait(0.45)
		toast:Destroy()
	end)
end

return UI

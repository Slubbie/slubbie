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

-- Catch a Comet! — client entry point.
--
-- Shows a loading screen, initializes every controller (no UI yet), loads
-- this player's state from the server, then starts the controllers in
-- order. Controllers talk to each other through the shared registry.

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Controllers = script.Parent:WaitForChild("Controllers")
local UI = script.Parent:WaitForChild("UI")

local ORDER = {
	"ClientState",
	"InputController",
	"PanelManager",
	"AudioController",
	"SettingsController",
	"CameraController",
	"EffectsController",
	"NotificationController",
	"CometController",
	"CaptureController",
	"RevealController",
	"WispController",
	"CreatureAnimator",
	"AmbientController",
	"SanctuaryController",
	"InventoryController",
	"WorkshopController",
	"HUDController",
	"ObjectiveController",
}

-- No tools in this game; free the hotbar area.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

-- Loading screen ------------------------------------------------------------------
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local loading = Instance.new("ScreenGui")
loading.Name = "Loading"
loading.IgnoreGuiInset = true
loading.DisplayOrder = 100
loading.ResetOnSpawn = false
local backdrop = Instance.new("Frame")
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Color3.fromHex("#0B1028")
backdrop.Parent = loading
local gradient = Instance.new("UIGradient")
gradient.Color = ColorSequence.new(Color3.fromHex("#2A1F5C"), Color3.fromHex("#0B1028"))
gradient.Rotation = 90
gradient.Parent = backdrop
local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.44)
title.Size = UDim2.fromScale(0.8, 0.12)
title.Font = Enum.Font.FredokaOne
title.TextScaled = true
title.Text = "Catch a Comet! ☄️"
title.TextColor3 = Color3.fromHex("#F5F7FF")
title.Parent = backdrop
local subtitle = Instance.new("TextLabel")
subtitle.BackgroundTransparency = 1
subtitle.AnchorPoint = Vector2.new(0.5, 0)
subtitle.Position = UDim2.fromScale(0.5, 0.53)
subtitle.Size = UDim2.fromScale(0.8, 0.05)
subtitle.Font = Enum.Font.BuilderSansBold
subtitle.TextScaled = true
subtitle.Text = "Charting the stars…"
subtitle.TextColor3 = Color3.fromHex("#A9B2D6")
subtitle.Parent = backdrop
loading.Parent = playerGui

local spinning = true
task.spawn(function()
	local dots = 0
	while spinning do
		dots = dots % 3 + 1
		subtitle.Text = "Charting the stars" .. string.rep(".", dots)
		task.wait(0.4)
	end
end)

-- Controllers -------------------------------------------------------------------------
local registry: { [string]: any } = {}
registry.Components = require(UI:WaitForChild("Components"))
registry.Viewport = require(UI:WaitForChild("Viewport"))

local camera = Workspace.CurrentCamera
registry.Components.UpdateScale(camera.ViewportSize)
camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
	registry.Components.UpdateScale(camera.ViewportSize)
end)

for _, name in ORDER do
	registry[name] = require(Controllers:WaitForChild(name))
end
for _, name in ORDER do
	local controller = registry[name]
	if controller.Init then
		local ok, err = pcall(controller.Init, registry)
		if not ok then
			warn(`[Client] {name}.Init failed: {err}`)
		end
	end
end

if not registry.ClientState.Load() then
	spinning = false
	subtitle.Text = "Couldn't reach the server. Please rejoin."
	return
end

for _, name in ORDER do
	local controller = registry[name]
	if controller.Start and name ~= "ClientState" then
		local ok, err = pcall(controller.Start)
		if not ok then
			warn(`[Client] {name}.Start failed: {err}`)
		end
	end
end

spinning = false
TweenService:Create(backdrop, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
TweenService:Create(title, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
TweenService:Create(subtitle, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
task.delay(0.7, function()
	loading:Destroy()
end)

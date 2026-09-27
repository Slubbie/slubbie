-- Dicebound client entry point: builds the interface and wires input, remotes and panels.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Dicebound.Config)
local Net = require(ReplicatedStorage.Dicebound.Net)
local ClientState = require(script.ClientState)
local Sound = require(script.Sound)
local UI = script.UI
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Toasts = require(UI.Toasts)
local Confirm = require(UI.Confirm)
local Panels = require(UI.Panels)
local Hud = require(UI.Hud)
local Reveal = require(UI.Reveal)
local Guide = require(UI.Guide)
local ItemIcon = require(UI.ItemIcon)
local InventoryPanel = require(UI.InventoryPanel)
local UpgradesPanel = require(UI.UpgradesPanel)
local OddsPanel = require(UI.OddsPanel)
local SettingsPanel = require(UI.SettingsPanel)
local RollController = require(script.Controllers.RollController)

local player = Players.LocalPlayer

-- ── Screen + responsive scaling ────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "Dicebound"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

-- Everything is laid out for ~1100×640 and scaled to fit, but never below 0.7 so touch targets
-- stay usable on phones.
local root = Kit.new("Frame", { Name = "Root", BackgroundTransparency = 1, Parent = gui })
local uiScale = Kit.new("UIScale", { Parent = root })
local function rescale()
	local size = gui.AbsoluteSize
	if size.X <= 0 then
		return
	end
	local s = math.clamp(math.min(size.X / 1100, size.Y / 640), 0.7, 1.25)
	uiScale.Scale = s
	root.Size = UDim2.fromScale(1 / s, 1 / s)
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
rescale()

Toasts.Init(root)
Confirm.Init(root)
Panels.Init(root)
Kit.OnClick = function()
	Sound.Play("Click")
end

-- ── Loading overlay (until the server sends our data) ────────────────────────
local loading = Kit.new("Frame", {
	Name = "Loading",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Theme.Colors.Dim,
	BackgroundTransparency = 0.2,
	ZIndex = 100,
	Parent = root,
})
Kit.Label({
	Parent = loading,
	Size = UDim2.new(1, 0, 0, 60),
	Position = UDim2.fromScale(0, 0.42),
	Text = "🎲 " .. Config.Game.Name,
	Font = Theme.Fonts.Title,
	TextSize = 44,
	TextColor3 = Theme.Colors.Gold,
	TextXAlignment = Enum.TextXAlignment.Center,
	ZIndex = 101,
})
Kit.Label({
	Parent = loading,
	Size = UDim2.new(1, 0, 0, 30),
	Position = UDim2.fromScale(0, 0.52),
	Text = "Loading your treasure...",
	TextSize = 20,
	TextColor3 = Theme.Colors.White,
	TextXAlignment = Enum.TextXAlignment.Center,
	ZIndex = 101,
})

-- ── Build the interface ─────────────────────────────────────────────────────
local hud = Hud.new(root, {
	Roll = function()
		RollController.Roll(false)
	end,
	Auto = function()
		RollController.ToggleAuto()
	end,
	Bag = function()
		Panels.Toggle("Bag")
	end,
	Upgrades = function()
		Panels.Toggle("Upgrades")
	end,
	Odds = function()
		Panels.Toggle("Odds")
	end,
	Settings = function()
		Panels.Toggle("Settings")
	end,
	SkipTutorial = function()
		local result = ClientState.Request("SkipTutorial")
		if result.ok then
			Toasts.Show("Tutorial skipped. Your goal card will keep pointing the way.", "info")
		end
	end,
})
local reveal = Reveal.new(root, hud.Tray.Frame)
InventoryPanel.new()
UpgradesPanel.new()
OddsPanel.new()
SettingsPanel.new()
RollController.Start(hud, reveal)
Guide.Start(hud)
Sound.Start()

ClientState.Changed:Connect(function(data)
	hud.Update(data)
	if loading.Parent then
		loading:Destroy()
	end
end)

local function applySettings(settings)
	Kit.ReducedMotion = settings.ReducedMotion == true
end
ClientState.SettingsChanged:Connect(applySettings)
applySettings(ClientState.Settings)
if ClientState.Data then
	hud.Update(ClientState.Data)
	Guide.Update()
	loading:Destroy()
end

-- ── Server messages ─────────────────────────────────────────────────────────
Net.Events.Notify.OnClientEvent:Connect(function(text: string, kind: string)
	Toasts.Show(text, kind)
	if kind == "success" then
		Sound.Play("Purchase")
	end
end)
Net.Events.OpenPanel.OnClientEvent:Connect(function(panel: string)
	if panel == "Merchant" then
		Panels.Open("Bag")
	elseif panel == "Upgrades" then
		Panels.Open("Upgrades")
	end
end)
Net.Events.Announce.OnClientEvent:Connect(function(name: string, itemId: string, mutation: string?)
	local item = Config.Items.ById[itemId]
	if item and name ~= player.DisplayName then
		Toasts.Show(
			string.format("⭐ %s found %s %s!", name, Theme.RarityText(item.Rarity), ItemIcon.Name(itemId, mutation)),
			"announce",
			4
		)
	end
end)

-- ── Region banner (display only) ────────────────────────────────────────────
task.spawn(function()
	local current = nil
	while true do
		local region = ClientState.CurrentRegion()
		if region ~= current then
			current = region
			hud.SetRegion(region)
		end
		task.wait(0.5)
	end
end)

-- ── Keyboard / gamepad shortcuts ─────────────────────────────────────────────
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or UserInputService:GetFocusedTextBox() then
		return
	end
	local key = input.KeyCode
	if key == Enum.KeyCode.R or key == Enum.KeyCode.ButtonX then
		RollController.Roll(false)
	elseif key == Enum.KeyCode.B then
		Panels.Toggle("Bag")
	elseif key == Enum.KeyCode.U then
		Panels.Toggle("Upgrades")
	elseif key == Enum.KeyCode.Escape then
		Panels.Close()
	end
end)

-- Dicebound client entry point: builds the interface and wires input, remotes and panels.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Dicebound.Config)
local Format = require(ReplicatedStorage.Dicebound.Format)
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
local DicePanel = require(UI.DicePanel)
local MapPanel = require(UI.MapPanel)
local BookPanel = require(UI.BookPanel)
local QuestsPanel = require(UI.QuestsPanel)
local CraftPanel = require(UI.CraftPanel)
local Effects = require(UI.Effects)
local RollController = require(script.Controllers.RollController)
local Atmosphere = require(script.Controllers.Atmosphere)

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
	Dice = function()
		Panels.Toggle("Dice")
	end,
	Map = function()
		Panels.Toggle("Map")
	end,
	Quests = function()
		Panels.Toggle("Quests")
	end,
	Book = function()
		Panels.Toggle("Book")
	end,
	Craft = function()
		Panels.Toggle("Craft")
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
DicePanel.new()
MapPanel.new()
BookPanel.new()
QuestsPanel.new()
CraftPanel.new()
Effects.Init(root, hud.CoinPill)
RollController.Start(hud, reveal)
Guide.Start(hud)
Sound.Start()
Atmosphere.Start()

local function updateBadges(data)
	local claimable = data.Claimable
	local readyOrders = 0
	for _, slot in data.Orders.Slots do
		if slot.ItemId then
			local have = 0
			for _, stack in data.Bag do
				if stack.Id == slot.ItemId and not stack.Locked and (slot.Mut == nil or stack.Mut == slot.Mut) then
					have += stack.Qty
				end
			end
			if have >= slot.Qty then
				readyOrders += 1
			end
		end
	end
	hud.SetBadge("Quests", claimable.Daily + claimable.Milestones + readyOrders)
	hud.SetBadge("Book", claimable.Collection)
	local canUnlock = 0
	for _, region in Config.Regions.List do
		if Config.IsLive(region) and not data.Regions[region.Id] then
			local previous = Config.Regions.Previous(region.Id)
			if previous and data.Regions[previous.Id] and data.Coins >= region.Unlock.Coins then
				local found = ClientState.DiscoveredIn(previous.Id)
				if found >= (region.Unlock.Discoveries or 0) then
					canUnlock += 1
				end
			end
			break
		end
	end
	hud.SetBadge("Map", canUnlock)
	local canBuyDie = 0
	for _, die in Config.Dice.List do
		local source = die.Source
		if
			Config.IsLive(die)
			and source.Kind == "Shop"
			and not data.Dice.Owned[die.Id]
			and data.Regions[source.Region]
			and data.Coins >= source.Price
		then
			canBuyDie += 1
		end
	end
	hud.SetBadge("Dice", canBuyDie)
end

ClientState.Changed:Connect(function(data)
	hud.Update(data)
	hud.Tray:SetFelt(data.Cosmetics.Tray)
	updateBadges(data)
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
		Effects.Coins(5)
	end
end)
local PANELS = { Upgrades = true, Dice = true, Map = true, Quests = true, Book = true, Craft = true, Bag = true }
Net.Events.OpenPanel.OnClientEvent:Connect(function(panel: string)
	if panel == "Merchant" then
		Panels.Open("Bag")
	elseif PANELS[panel] then
		Panels.Open(panel)
	end
end)
Net.Events.Announce.OnClientEvent:Connect(function(kind: string, name: string, a: any, b: any)
	if name == player.DisplayName then
		return
	end
	if kind == "find" then
		local item = Config.Items.ById[a]
		if item then
			Toasts.Show(
				string.format("⭐ %s found %s %s!", name, Theme.RarityText(item.Rarity), ItemIcon.Name(a, b)),
				"announce",
				4
			)
		end
	elseif kind == "unlock" then
		local region = Config.Regions.ById[a]
		if region then
			Toasts.Show(string.format("🗺️ %s unlocked %s!", name, region.Name), "announce", 4)
		end
	end
end)

-- ── World event banner ──────────────────────────────────────────────────────
task.spawn(function()
	while true do
		local event = ClientState.Event()
		if event then
			local def = Config.Economy.Events.ById[event.Id]
			local region = Config.Regions.ById[event.Region]
			local here = ClientState.CurrentRegion()
			local isHere = here ~= nil and here.Id == event.Region
			hud.SetEvent(
				string.format(
					"%s %s · %s · %s left%s",
					def and def.Icon or "✨",
					def and def.Name or event.Id,
					def and def.Text or "",
					Format.Seconds(event.EndsIn),
					if isHere then "" else "  (in " .. (region and region.Name or "?") .. ")"
				),
				isHere
			)
		else
			hud.SetEvent(nil, false)
		end
		task.wait(1)
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
	elseif key == Enum.KeyCode.M then
		Panels.Toggle("Map")
	elseif key == Enum.KeyCode.Q then
		Panels.Toggle("Quests")
	elseif key == Enum.KeyCode.C then
		Panels.Toggle("Book")
	elseif key == Enum.KeyCode.G then
		Panels.Toggle("Dice")
	elseif key == Enum.KeyCode.Escape then
		Panels.Close()
	end
end)

-- The always-on HUD.
--
--   top      Stardust (with income rate), Meteor Shards (once you have any),
--            level badge and XP bar
--   left     Quests · Inventory · Collection
--   right    Workshop · Home · Travel · Settings
--   bottom   the scanner strip: nearest comet, distance, direction, lock state
--
-- Touch devices get their own arrangement (navigation in a compact top-right
-- grid, away from the thumbstick and jump button) instead of a scaled-down
-- desktop layout. The Stardust counter animates toward the server value and
-- reconciles to it on every update.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BiomeDefinitions = require(Shared.BiomeDefinitions)
local EconomyMath = require(Shared.EconomyMath)
local Format = require(Shared.Format)
local GameConfig = require(Shared.GameConfig)
local RemoteDefinitions = require(Shared.RemoteDefinitions)
local UITheme = require(Shared.UITheme)
local WorldLayout = require(Shared.WorldLayout)

local HUDController = {}

local controllers: { [string]: any } = {}
local Components: any
local gui: ScreenGui
local top: Frame
local stardustValue: TextLabel
local rateLabel: TextLabel
local shardsPill: Frame
local shardsValue: TextLabel
local levelLabel: TextLabel
local setXP: (number, boolean?) -> ()
local xpLabel: TextLabel
local leftNav: Frame
local rightNav: Frame
local scanner: Frame
local scannerText: TextLabel
local scannerArrow: TextLabel
local buttons: { [string]: any } = {}
local displayedStardust = 0
local targetStardust = 0
local layoutMode = ""

local function travel(destination: string)
	task.spawn(function()
		local ok, result = pcall(function()
			return RemoteDefinitions.GetFunction("Travel"):InvokeServer(destination)
		end)
		if ok and type(result) == "table" and not result.Ok then
			local messages = {
				Cooldown = "Travel is recharging — try again in a moment.",
				Capturing = "Finish stabilizing first!",
				NoSanctuary = "You don't have a sanctuary in this server.",
				Locked = "You haven't unlocked that area yet.",
				ComingSoon = "That area is still being charted.",
			}
			controllers.NotificationController.Toast(messages[result.Reason] or "Can't travel right now.", "🧭")
		end
	end)
end
HUDController.Travel = travel

local function buildTop()
	local Make = Components.Make
	top = Make("Frame", {
		Name = "Top",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(560, 60),
		Parent = gui,
	})
	Components.List(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top).Parent =
		top

	local stardustPill, value = Components.Pill("✦", UITheme.Colors.Gold, top)
	stardustPill.LayoutOrder = 1
	stardustPill.Size = UDim2.fromOffset(196, 46)
	stardustValue = value
	stardustValue.Size = UDim2.new(1, -52, 0, 28)
	rateLabel = Components.Label({
		Text = "",
		Font = UITheme.Fonts.Bold,
		TextSize = 12,
		TextColor3 = UITheme.Colors.Gold,
		Size = UDim2.new(1, -52, 0, 14),
		Position = UDim2.fromOffset(44, 27),
		Parent = stardustPill,
	})

	local shards, shardValue = Components.Pill("◆", UITheme.Colors.Lavender, top)
	shards.LayoutOrder = 2
	shards.Size = UDim2.fromOffset(120, 46)
	shards.Visible = false
	shardsPill = shards
	shardsValue = shardValue

	local level = Make("Frame", {
		LayoutOrder = 3,
		BackgroundColor3 = UITheme.Colors.Panel,
		BackgroundTransparency = 0.06,
		Size = UDim2.fromOffset(210, 46),
		Parent = top,
	})
	Components.Round().Parent = level
	Components.Stroke(UITheme.Colors.Cyan, 1.5, 0.45).Parent = level
	local badge = Make("Frame", {
		BackgroundColor3 = UITheme.Colors.Cyan,
		Size = UDim2.fromOffset(38, 38),
		Position = UDim2.fromOffset(4, 4),
		Parent = level,
	})
	Components.Round().Parent = badge
	levelLabel = Components.Label({
		Text = "1",
		Font = UITheme.Fonts.Display,
		TextSize = 20,
		TextColor3 = UITheme.Colors.Background,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = badge,
	})
	xpLabel = Components.Label({
		Text = "Level 1",
		Font = UITheme.Fonts.Bold,
		TextSize = 13,
		TextColor3 = UITheme.Colors.Muted,
		Size = UDim2.new(1, -60, 0, 16),
		Position = UDim2.fromOffset(50, 5),
		Parent = level,
	})
	local bar, set = Components.ProgressBar(UITheme.Colors.Cyan, 10, level)
	bar.Size = UDim2.new(1, -62, 0, 10)
	bar.Position = UDim2.fromOffset(50, 26)
	setXP = set
end

local function navButton(
	parent: Frame,
	key: string,
	icon: string,
	caption: string,
	order: number,
	hint: string?,
	callback: () -> ()
)
	local button = Components.IconButton(icon, caption, parent)
	button.Instance.LayoutOrder = order
	if hint then
		button:SetHint(hint)
	end
	button.Activated:Connect(callback)
	buttons[key] = button
	return button
end

local function buildNav()
	local Make = Components.Make
	leftNav =
		Make("Frame", { Name = "LeftNav", BackgroundTransparency = 1, Size = UDim2.fromOffset(66, 230), Parent = gui })
	Components.List(Enum.FillDirection.Vertical, 10).Parent = leftNav
	rightNav =
		Make("Frame", { Name = "RightNav", BackgroundTransparency = 1, Size = UDim2.fromOffset(66, 310), Parent = gui })
	Components.List(Enum.FillDirection.Vertical, 10).Parent = rightNav

	local panels = controllers.PanelManager
	navButton(leftNav, "Quests", "📜", "Quests", 1, "J", function()
		panels.Toggle("Quests")
	end)
	navButton(leftNav, "Inventory", "🎒", "Creatures", 2, "I", function()
		controllers.InventoryController.Toggle("Creatures")
	end)
	navButton(leftNav, "Collection", "📖", "Collection", 3, "C", function()
		controllers.InventoryController.Toggle("Collection")
	end)
	navButton(rightNav, "Workshop", "🔧", "Workshop", 1, "U", function()
		panels.Toggle("Workshop")
	end)
	navButton(rightNav, "Home", "🏠", "Home", 2, "H", function()
		travel("Sanctuary")
	end)
	navButton(rightNav, "Travel", "🧭", "Travel", 3, "T", function()
		panels.Toggle("Travel")
	end)
	navButton(rightNav, "Settings", "⚙️", "Settings", 4, "O", function()
		panels.Toggle("Settings")
	end)

	local input = controllers.InputController
	input.BindShortcut({ Enum.KeyCode.J, Enum.KeyCode.DPadUp }, function()
		panels.Toggle("Quests")
	end)
	input.BindShortcut({ Enum.KeyCode.I, Enum.KeyCode.DPadLeft }, function()
		controllers.InventoryController.Toggle("Creatures")
	end)
	input.BindShortcut({ Enum.KeyCode.C }, function()
		controllers.InventoryController.Toggle("Collection")
	end)
	input.BindShortcut({ Enum.KeyCode.U, Enum.KeyCode.DPadRight }, function()
		panels.Toggle("Workshop")
	end)
	input.BindShortcut({ Enum.KeyCode.H }, function()
		travel("Sanctuary")
	end)
	input.BindShortcut({ Enum.KeyCode.T, Enum.KeyCode.DPadDown }, function()
		panels.Toggle("Travel")
	end)
	input.BindShortcut({ Enum.KeyCode.O, Enum.KeyCode.ButtonSelect }, function()
		panels.Toggle("Settings")
	end)
end

local function buildScanner()
	local Make = Components.Make
	scanner = Make("Frame", {
		Name = "Scanner",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -54),
		Size = UDim2.fromOffset(380, 44),
		BackgroundColor3 = UITheme.Colors.Panel,
		BackgroundTransparency = 0.12,
		Parent = gui,
	})
	Components.Round().Parent = scanner
	Components.Stroke(UITheme.Colors.Cyan, 1.5, 0.55).Parent = scanner
	scannerArrow = Components.Label({
		Text = "▲",
		Font = UITheme.Fonts.Heading,
		TextSize = 22,
		TextColor3 = UITheme.Colors.Cyan,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.fromOffset(6, 2),
		Parent = scanner,
	})
	scannerText = Components.Label({
		Text = "📡 Scanning…",
		Font = UITheme.Fonts.Bold,
		TextSize = 16,
		TextWrapped = false,
		Size = UDim2.new(1, -56, 1, 0),
		Position = UDim2.fromOffset(48, 0),
		Parent = scanner,
	})
end

local function applyLayout()
	local touch = controllers.InputController.Device == "Touch"
	local mode = if touch then "Touch" else "Desktop"
	if mode == layoutMode then
		return
	end
	layoutMode = mode
	local leftLayout = leftNav:FindFirstChildOfClass("UIListLayout") :: UIListLayout
	local rightLayout = rightNav:FindFirstChildOfClass("UIListLayout") :: UIListLayout
	if touch then
		-- Two compact rows in the top-right corner, clear of the thumbstick
		-- (bottom-left) and the jump button (bottom-right).
		leftLayout.FillDirection = Enum.FillDirection.Horizontal
		rightLayout.FillDirection = Enum.FillDirection.Horizontal
		leftLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		rightLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		rightNav.Size = UDim2.fromOffset(300, 66)
		leftNav.Size = UDim2.fromOffset(300, 66)
		rightNav.AnchorPoint = Vector2.new(1, 0)
		rightNav.Position = UDim2.new(1, -10, 0, 70)
		leftNav.AnchorPoint = Vector2.new(1, 0)
		leftNav.Position = UDim2.new(1, -10, 0, 146)
		scanner.AnchorPoint = Vector2.new(0, 0)
		scanner.Position = UDim2.new(0, 12, 0, 66)
		scanner.Size = UDim2.fromOffset(330, 38)
	else
		leftLayout.FillDirection = Enum.FillDirection.Vertical
		rightLayout.FillDirection = Enum.FillDirection.Vertical
		leftLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		rightLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		leftNav.Size = UDim2.fromOffset(66, 230)
		rightNav.Size = UDim2.fromOffset(66, 310)
		leftNav.AnchorPoint = Vector2.new(0, 0.5)
		leftNav.Position = UDim2.new(0, 16, 0.5, 0)
		rightNav.AnchorPoint = Vector2.new(1, 0.5)
		rightNav.Position = UDim2.new(1, -16, 0.5, 0)
		scanner.AnchorPoint = Vector2.new(0.5, 1)
		scanner.Position = UDim2.new(0.5, 0, 1, -54)
		scanner.Size = UDim2.fromOffset(380, 44)
	end
	for _, button in buttons do
		button:SetHint(if touch then nil else button.Instance:GetAttribute("Hint"))
	end
end

local function updateScanner()
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local comets = controllers.CometController
	local view, distance = comets.Nearest(root.Position, true)
	local area = WorldLayout.GetArea(root.Position)
	if not view then
		scannerArrow.Visible = false
		if area.Kind == "Biome" then
			scannerText.Text = "📡 No comets nearby — watch the sky!"
		else
			scannerText.Text = "📡 Comets fall in Dawn Commons  ·  🧭 Travel"
		end
		return
	end
	scannerArrow.Visible = true
	local camera = Workspace.CurrentCamera
	local look = camera.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	local toComet = view.Data.Position - root.Position
	local flatTo = Vector3.new(toComet.X, 0, toComet.Z)
	if flatLook.Magnitude > 0.01 and flatTo.Magnitude > 0.01 then
		local a = math.atan2(flatLook.Unit:Cross(flatTo.Unit).Y, flatLook.Unit:Dot(flatTo.Unit))
		scannerArrow.Rotation = -math.deg(a)
	end
	if distance <= comets.ScannerRadius() then
		scannerText.Text = `📡 LOCKED · {view.Type.DisplayName} comet · {math.floor(distance)}m`
		scannerText.TextColor3 = UITheme.Colors.Cyan
	else
		scannerText.Text = `📡 Nearest comet · {math.floor(distance)}m`
		scannerText.TextColor3 = UITheme.Colors.Text
	end
end

local function refreshProfile()
	local state = controllers.ClientState
	targetStardust = state.Get("Stardust") or 0
	local shards = state.Get("MeteorShards") or 0
	shardsPill.Visible = shards > 0
	shardsValue.Text = Format.Short(shards)
	local level = state.Get("Level") or 1
	local xp = state.Get("XP") or 0
	levelLabel.Text = tostring(level)
	if level >= GameConfig.Progression.LevelCap then
		xpLabel.Text = `Level {level} · MAX`
		setXP(1, true)
	else
		local need = EconomyMath.XPToNext(level)
		xpLabel.Text = `Level {level} · {Format.Short(xp)}/{Format.Short(need)} XP`
		setXP(xp / need, true)
	end
end

-- World prompts with an "Action" attribute open UI.
local function onPrompt(prompt: ProximityPrompt)
	local action = prompt:GetAttribute("Action")
	if action == "OpenWorkshop" then
		controllers.PanelManager.Open("Workshop")
	elseif action == "OpenQuests" then
		controllers.PanelManager.Open("Quests")
	elseif action == "OpenCores" then
		controllers.InventoryController.Open("Cores")
	elseif action == "Habitat" then
		controllers.SanctuaryController.OnPadPrompt(prompt)
	end
end

local function buildTravelPanel()
	local panel = Components.Panel("Travel", Vector2.new(460, 420), controllers.PanelManager.Gui())
	local body = panel.Body
	local list = Components.Make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = body })
	Components.List(Enum.FillDirection.Vertical, 8).Parent = list
	local entries: { { Id: string, Name: string, Sub: string } } = {
		{ Id = "Hub", Name = "Celestial Crossing", Sub = "The hub: workshop, missions, portals" },
		{ Id = "Sanctuary", Name = "Your Sanctuary", Sub = "Your creatures and habitats" },
	}
	for _, biomeId in BiomeDefinitions.Order do
		local biome = BiomeDefinitions.Biomes[biomeId]
		table.insert(entries, { Id = biomeId, Name = biome.DisplayName, Sub = biome.Tagline })
	end
	local rows = {}
	for i, entry in entries do
		local button = Components.Button(entry.Name, "Secondary", UDim2.new(1, 0, 0, 44), list)
		button.Instance.LayoutOrder = i
		button.Label.TextXAlignment = Enum.TextXAlignment.Left
		rows[entry.Id] = { Button = button, Entry = entry }
		button.Activated:Connect(function()
			controllers.PanelManager.Close()
			travel(entry.Id)
		end)
		if i == 1 then
			panel.FirstSelectable = button.Instance
		end
	end
	local function refresh()
		local unlocked = controllers.ClientState.Get("UnlockedBiomes") or {}
		for id, row in rows do
			local biome = BiomeDefinitions.Get(id)
			if biome then
				local open = biome.Implemented and unlocked[id] == true
				row.Button:SetEnabled(open)
				local suffix = if open
					then ""
					elseif not biome.Implemented then "  ·  charting in progress"
					else `  ·  Lv {biome.Unlock.Level}`
				row.Button:SetText(`{biome.DisplayName}{suffix}`)
			end
		end
	end
	controllers.PanelManager.Register("Travel", panel, refresh)
end

local function buildSettingsPanel()
	local panel = Components.Panel("Settings", Vector2.new(560, 520), controllers.PanelManager.Gui())
	controllers.SettingsController.BuildPanel(panel.Body)
	controllers.PanelManager.Register("Settings", panel)
end

function HUDController.SetBadge(key: string, count: number?)
	local button = buttons[key]
	if button then
		button:SetBadge(count)
	end
end

function HUDController.Init(registry: { [string]: any })
	controllers = registry
end

function HUDController.Start()
	Components = controllers.Components
	gui = Components.Screen("HUD", 5)
	buildTop()
	buildNav()
	buildScanner()
	buildTravelPanel()
	buildSettingsPanel()
	for key, hint in
		{ Quests = "J", Inventory = "I", Collection = "C", Workshop = "U", Home = "H", Travel = "T", Settings = "O" }
	do
		buttons[key].Instance:SetAttribute("Hint", hint)
	end
	applyLayout()
	controllers.InputController.DeviceChanged:Connect(applyLayout)

	local state = controllers.ClientState
	targetStardust = state.Get("Stardust") or 0
	displayedStardust = targetStardust
	for _, key in { "Stardust", "MeteorShards", "Level", "XP" } do
		state.Observe(key, refreshProfile)
	end
	state.ObserveSession("IncomeRate", function(rate)
		rateLabel.Text = if rate and rate > 0 then `+{Format.Rate(rate)}/s` else ""
	end)
	state.Observe("Cores", function(cores)
		local count = 0
		for _ in cores or {} do
			count += 1
		end
		HUDController.SetBadge("Inventory", count)
	end)

	ProximityPromptService.PromptTriggered:Connect(onPrompt)

	local scannerClock = 0
	RunService.RenderStepped:Connect(function(dt)
		-- Count up smoothly toward the server's value.
		if displayedStardust ~= targetStardust then
			local diff = targetStardust - displayedStardust
			local stepSize = math.max(math.abs(diff) * math.min(dt * 6, 1), 1)
			if math.abs(diff) <= stepSize then
				displayedStardust = targetStardust
			else
				displayedStardust += math.sign(diff) * stepSize
			end
			stardustValue.Text = Format.Short(math.floor(displayedStardust))
		end
		scannerClock += dt
		if scannerClock > 0.15 then
			scannerClock = 0
			updateScanner()
		end
	end)
	stardustValue.Text = Format.Short(displayedStardust)
end

return HUDController

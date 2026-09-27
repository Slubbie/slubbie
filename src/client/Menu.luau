-- Title screen, shop and trials browser.
--
-- On join the camera orbits the spawn island behind the title. Press PLAY to
-- drop in. Press M (or the MENU button) any time to come back.

local ContextActionService = game:GetService("ContextActionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Settings = require(script.Parent.Settings)
local Sounds = require(script.Parent.Sounds)
local UI = require(script.Parent.UI)

local ORBIT_CENTER = Vector3.new(0, 110, 0)
local localPlayer = Players.LocalPlayer

local Menu = {}
Menu.Opened = Instance.new("BindableEvent") -- (isOpen: boolean)

local isOpen = false

local function click()
	Sounds.Play(Config.Sounds.Ping, 0.25, 2)
end

local function owns(itemId: string): boolean
	local owned = localPlayer:GetAttribute("Owned")
	if type(owned) ~= "string" then
		return itemId == Config.Shop.Default
	end
	for id in string.gmatch(owned, "[^,]+") do
		if id == itemId then
			return true
		end
	end
	return false
end

function Menu.IsOpen(): boolean
	return isOpen
end

function Menu.Start(Movement, HUD)
	local shopRemote = Net.Function("Shop")
	local leaderboardRemote = Net.Function("GetLeaderboards")
	local goRemote = Net.Function("GoToTrial")

	local gui = UI.gui("Menu", 10)

	-- Dim gradient behind the title.
	local shade = UI.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.2,
	}, gui)
	UI.new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.55, 0.75),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, shade)

	-- Left column: title + buttons ------------------------------------------------
	local left = UI.new("Frame", {
		Position = UDim2.new(0, 70, 0.5, -270),
		Size = UDim2.fromOffset(460, 420),
		BackgroundTransparency = 1,
	}, gui)
	local title = UI.label(left, {
		Size = UDim2.new(1, 0, 0, 100),
		Font = UI.Fonts.Title,
		TextSize = 92,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "SKYBOUND",
	})
	UI.new("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), UI.Colors.Accent),
		Rotation = 90,
	}, title)
	UI.label(left, {
		Position = UDim2.fromOffset(4, 96),
		Size = UDim2.new(1, 0, 0, 24),
		Font = UI.Fonts.Body,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = UI.Colors.Muted,
		Text = "Swing. Run the walls. Never touch the ground.",
	})

	local buttons = UI.new("Frame", {
		Position = UDim2.fromOffset(0, 150),
		Size = UDim2.fromOffset(260, 410),
		BackgroundTransparency = 1,
	}, left)
	UI.new("UIListLayout", { Padding = UDim.new(0, 12) }, buttons)
	local playButton = UI.button(buttons, "PLAY", { BackgroundColor3 = UI.Colors.Accent, TextColor3 = UI.Colors.Panel })
	local trialsButton = UI.button(buttons, "TIME TRIALS")
	local shopButton = UI.button(buttons, "SHOP")
	local achievementsButton = UI.button(buttons, "ACHIEVEMENTS")
	local settingsButton = UI.button(buttons, "SETTINGS")
	local spawnButton = UI.button(buttons, "RETURN TO SPAWN", { TextSize = 18 })

	-- Right column: content panel --------------------------------------------------
	local panel = UI.new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -60, 0.5, 0),
		Size = UDim2.fromOffset(520, 460),
		BackgroundColor3 = UI.Colors.Panel,
		BackgroundTransparency = 0.12,
		Visible = false,
	}, gui)
	UI.corner(panel, 18)
	UI.new("UIPadding", {
		PaddingTop = UDim.new(0, 18),
		PaddingBottom = UDim.new(0, 18),
		PaddingLeft = UDim.new(0, 18),
		PaddingRight = UDim.new(0, 18),
	}, panel)
	local panelTitle = UI.label(panel, {
		Size = UDim2.new(1, 0, 0, 34),
		Font = UI.Fonts.Title,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})
	local shardsLabel = UI.label(panel, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(160, 34),
		Font = UI.Fonts.Title,
		TextSize = 22,
		TextColor3 = UI.Colors.Gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
	})
	local content = UI.new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 1, -48),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, panel)

	local function clearContent()
		for _, child in content:GetChildren() do
			child:Destroy()
		end
	end

	local function updateShards()
		shardsLabel.Text = "◆ " .. tostring(localPlayer:GetAttribute("Shards") or 0)
	end
	localPlayer:GetAttributeChangedSignal("Shards"):Connect(updateShards)
	updateShards()

	-- Shop tab ---------------------------------------------------------------------
	local currentTab: string? = nil

	local function showShop()
		currentTab = "Shop"
		panel.Visible = true
		panelTitle.Text = "ROPE & TRAIL COLOURS"
		clearContent()
		UI.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(150, 150),
			CellPadding = UDim2.fromOffset(12, 12),
		}, content)
		local equipped = localPlayer:GetAttribute("Equipped") or Config.Shop.Default
		for i, item in Config.Shop.Items do
			local card = UI.new("Frame", {
				BackgroundColor3 = UI.Colors.PanelLight,
				LayoutOrder = i,
			}, content)
			UI.corner(card, 14)
			if item.Id == equipped then
				UI.stroke(card, item.Color, 3)
			end
			local swatch = UI.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 14),
				Size = UDim2.fromOffset(56, 56),
				BackgroundColor3 = item.Color,
			}, card)
			UI.corner(swatch)
			if item.Rainbow then
				local keypoints = {}
				for k = 0, 6 do
					table.insert(keypoints, ColorSequenceKeypoint.new(k / 6, Color3.fromHSV(k / 6, 0.7, 1)))
				end
				UI.new("UIGradient", { Color = ColorSequence.new(keypoints) }, swatch)
			end
			UI.label(card, {
				Position = UDim2.fromOffset(0, 76),
				Size = UDim2.new(1, 0, 0, 22),
				Font = UI.Fonts.Title,
				Text = string.upper(item.Name),
			})
			local owned = owns(item.Id)
			local buttonText = if item.Id == equipped then "EQUIPPED" elseif owned then "EQUIP" else "◆ " .. item.Price
			local action = UI.button(card, buttonText, {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -10),
				Size = UDim2.new(1, -20, 0, 34),
				TextSize = 16,
				BackgroundColor3 = if owned then UI.Colors.Panel else UI.Colors.Gold,
				TextColor3 = if owned then UI.Colors.Text else UI.Colors.Panel,
			})
			action.Activated:Connect(function()
				if item.Id == equipped then
					return
				end
				click()
				local ok, message = shopRemote:InvokeServer(if owned then "Equip" else "Buy", item.Id)
				UI.toast(message, if ok then UI.Colors.Good else UI.Colors.Bad)
				if currentTab == "Shop" then
					showShop()
				end
			end)
		end
	end

	-- Trials tab -------------------------------------------------------------------
	local function showTrials()
		currentTab = "Trials"
		panel.Visible = true
		panelTitle.Text = "TIME TRIALS"
		clearContent()
		UI.new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, content)
		local ok, boards = pcall(function()
			return leaderboardRemote:InvokeServer()
		end)
		if currentTab ~= "Trials" then
			return
		end
		if not ok or type(boards) ~= "table" then
			UI.label(content, { Size = UDim2.new(1, 0, 0, 30), Text = "Couldn't load trials." })
			return
		end
		for order, definition in Config.Trials.Courses do
			local board = boards[definition.Id]
			if board then
				local card = UI.new("Frame", {
					Size = UDim2.new(1, -8, 0, 132),
					BackgroundColor3 = UI.Colors.PanelLight,
					LayoutOrder = order,
				}, content)
				UI.corner(card, 14)
				UI.stroke(card, definition.Color, 2, 0.4)
				UI.label(card, {
					Position = UDim2.fromOffset(14, 10),
					Size = UDim2.fromOffset(250, 26),
					Font = UI.Fonts.Title,
					TextSize = 24,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = definition.Color,
					Text = string.upper(definition.Name),
				})
				local best = localPlayer:GetAttribute("Best_" .. definition.Id)
				UI.label(card, {
					Position = UDim2.fromOffset(14, 38),
					Size = UDim2.fromOffset(250, 20),
					TextSize = 15,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = UI.Colors.Muted,
					Text = "Your best: " .. (if type(best) == "number" then UI.formatTime(best) else "—"),
				})
				local lines = {}
				for i = 1, 5 do
					local entry = board.Entries[i]
					table.insert(
						lines,
						if entry
							then string.format("%d. %s  %s", i, entry.Name, UI.formatTime(entry.Time))
							else string.format("%d. —", i)
					)
				end
				UI.label(card, {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -14, 0, 10),
					Size = UDim2.fromOffset(210, 112),
					Font = UI.Fonts.Body,
					TextSize = 15,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					Text = table.concat(lines, "\n"),
				})
				local go = UI.button(card, "GO", {
					Position = UDim2.fromOffset(14, 78),
					Size = UDim2.fromOffset(120, 40),
					BackgroundColor3 = definition.Color,
					TextColor3 = UI.Colors.Panel,
				})
				go.Activated:Connect(function()
					click()
					Menu.Close()
					goRemote:InvokeServer(definition.Id)
					UI.toast("Fly through the gate to start!", definition.Color)
				end)
			end
		end
	end

	-- Achievements tab ---------------------------------------------------------------
	local function showAchievements()
		currentTab = "Achievements"
		panel.Visible = true
		clearContent()
		UI.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, content)
		local okStats, stats = pcall(function()
			return HttpService:JSONDecode(localPlayer:GetAttribute("AchievementStats"))
		end)
		local okUnlocked, unlocked = pcall(function()
			return HttpService:JSONDecode(localPlayer:GetAttribute("Achievements"))
		end)
		stats = if okStats and type(stats) == "table" then stats else {}
		unlocked = if okUnlocked and type(unlocked) == "table" then unlocked else {}
		local count = 0
		for order, achievement in Config.Achievements do
			local done = unlocked[achievement.Id] == true
			if done then
				count += 1
			end
			local progress = math.min(stats[achievement.Stat] or 0, achievement.Goal)
			local card = UI.new("Frame", {
				Size = UDim2.new(1, -8, 0, 58),
				BackgroundColor3 = UI.Colors.PanelLight,
				BackgroundTransparency = if done then 0 else 0.35,
				LayoutOrder = order,
			}, content)
			UI.corner(card, 12)
			if done then
				UI.stroke(card, UI.Colors.Gold, 2, 0.2)
			end
			UI.label(card, {
				Position = UDim2.fromOffset(8, 0),
				Size = UDim2.fromOffset(44, 58),
				TextSize = 28,
				TextTransparency = if done then 0 else 0.6,
				Text = if done then "🏆" else "🔒",
			})
			UI.label(card, {
				Position = UDim2.fromOffset(56, 8),
				Size = UDim2.new(1, -150, 0, 20),
				Font = UI.Fonts.Title,
				TextSize = 17,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = if done then UI.Colors.Gold else UI.Colors.Text,
				Text = achievement.Name,
			})
			UI.label(card, {
				Position = UDim2.fromOffset(56, 28),
				Size = UDim2.new(1, -150, 0, 16),
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = UI.Colors.Muted,
				Text = achievement.Desc,
			})
			UI.label(card, {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, 8),
				Size = UDim2.fromOffset(90, 18),
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextColor3 = UI.Colors.Gold,
				Text = "◆ " .. achievement.Reward,
			})
			if not done then
				local track = UI.new("Frame", {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -12, 0, 34),
					Size = UDim2.fromOffset(90, 6),
					BackgroundColor3 = UI.Colors.Panel,
				}, card)
				UI.corner(track)
				local fill = UI.new("Frame", {
					Size = UDim2.fromScale(progress / achievement.Goal, 1),
					BackgroundColor3 = UI.Colors.Accent,
				}, track)
				UI.corner(fill)
			end
		end
		panelTitle.Text = string.format("ACHIEVEMENTS  %d/%d", count, #Config.Achievements)
	end

	-- Settings tab -----------------------------------------------------------------
	local function showSettings()
		currentTab = "Settings"
		panel.Visible = true
		panelTitle.Text = "SETTINGS"
		clearContent()
		UI.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, content)
		local order = 0
		local function nextOrder(): number
			order += 1
			return order
		end

		local function cycler(label: string, key: string)
			local button
			button = UI.valueButton(UI.row(content, label, nextOrder()), function()
				click()
				Settings.Cycle(key)
				button.Text = string.upper(Settings.Get(key))
			end)
			button.Text = string.upper(Settings.Get(key))
		end
		local function toggle(label: string, key: string)
			local button
			local function refresh()
				local on = Settings.Get(key)
				button.Text = if on then "ON" else "OFF"
				button.TextColor3 = if on then UI.Colors.Good else UI.Colors.Muted
			end
			button = UI.valueButton(UI.row(content, label, nextOrder()), function()
				click()
				Settings.Set(key, not Settings.Get(key))
				refresh()
			end)
			refresh()
		end
		local function slider(label: string, key: string, step: number, format: (number) -> string)
			local range = Config.Settings.Ranges[key]
			local show = UI.slider(
				UI.row(content, label, nextOrder()),
				range[1],
				range[2],
				step,
				format,
				function(value)
					Settings.Set(key, value)
				end
			)
			show(Settings.Get(key))
		end
		local function percent(value: number): string
			return math.floor(value * 100 + 0.5) .. "%"
		end

		UI.header(content, "GRAPHICS", nextOrder())
		cycler("Quality", "Quality")
		cycler("Time of day", "TimeOfDay")
		UI.header(content, "CAMERA", nextOrder())
		slider("Field of view", "FieldOfView", 1, function(value)
			return tostring(math.floor(value))
		end)
		slider("Mouse sensitivity", "MouseSensitivity", 0.05, function(value)
			return string.format("%.2f", value)
		end)
		toggle("Camera shake", "CameraShake")
		toggle("Speed lines", "SpeedLines")
		UI.header(content, "CONTROLS", nextOrder())
		cycler("Sprint (Shift)", "SprintMode")
		UI.header(content, "AUDIO", nextOrder())
		slider("Effects volume", "EffectsVolume", 0.05, percent)
		slider("Wind volume", "WindVolume", 0.05, percent)
		toggle("Music", "MusicEnabled")
		slider("Music volume", "MusicVolume", 0.05, percent)
		UI.header(content, "HUD", nextOrder())
		toggle("Speedometer", "ShowSpeedometer")
	end

	-- Open / close -----------------------------------------------------------------
	local orbiting = false
	local orbitAngle = 0

	function Menu.Open(withOrbit: boolean?)
		isOpen = true
		gui.Enabled = true
		orbiting = withOrbit == true
		if orbiting then
			workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
		end
		Movement.SetEnabled(false)
		HUD.SetVisible(false)
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		playButton.Text = if orbiting then "PLAY" else "RESUME"
		Menu.Opened:Fire(true)
	end

	function Menu.Close()
		isOpen = false
		gui.Enabled = false
		panel.Visible = false
		currentTab = nil
		if orbiting then
			orbiting = false
			workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
		end
		Movement.SetEnabled(true)
		HUD.SetVisible(true)
		Menu.Opened:Fire(false)
	end

	playButton.Activated:Connect(function()
		click()
		Menu.Close()
	end)
	spawnButton.Activated:Connect(function()
		click()
		Menu.Close()
		local ok = Net.Function("ReturnToSpawn"):InvokeServer()
		if not ok then
			UI.toast("Can't return right now", UI.Colors.Bad)
		end
	end)
	achievementsButton.Activated:Connect(function()
		click()
		if currentTab == "Achievements" then
			panel.Visible = false
			currentTab = nil
		else
			showAchievements()
		end
	end)
	settingsButton.Activated:Connect(function()
		click()
		if currentTab == "Settings" then
			panel.Visible = false
			currentTab = nil
		else
			showSettings()
		end
	end)
	trialsButton.Activated:Connect(function()
		click()
		if currentTab == "Trials" then
			panel.Visible = false
			currentTab = nil
		else
			showTrials()
		end
	end)
	shopButton.Activated:Connect(function()
		click()
		if currentTab == "Shop" then
			panel.Visible = false
			currentTab = nil
		else
			showShop()
		end
	end)
	localPlayer:GetAttributeChangedSignal("Equipped"):Connect(function()
		if currentTab == "Shop" then
			showShop()
		end
	end)

	ContextActionService:BindAction("SkyboundMenu", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			if isOpen then
				Menu.Close()
			else
				Menu.Open(false)
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.M, Enum.KeyCode.ButtonSelect)

	-- Small MENU button for touch / mouse players.
	local hudGui = UI.gui("MenuButton", 3)
	local menuButton = UI.button(hudGui, "MENU", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 60),
		Size = UDim2.fromOffset(90, 36),
		TextSize = 16,
		BackgroundTransparency = 0.25,
	})
	menuButton.Activated:Connect(function()
		click()
		Menu.Open(false)
	end)
	Menu.Opened.Event:Connect(function(open: boolean)
		menuButton.Visible = not open
	end)

	RunService:BindToRenderStep("SkyboundMenuCamera", Enum.RenderPriority.Camera.Value + 2, function(dt)
		if not orbiting then
			return
		end
		orbitAngle += dt * 0.08
		local offset = Vector3.new(math.cos(orbitAngle) * 150, 55, math.sin(orbitAngle) * 150)
		local camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.lookAt(ORBIT_CENTER + offset, ORBIT_CENTER + Vector3.new(0, -10, 0))
		camera.FieldOfView = 60
	end)

	Menu.Open(true)
end

return Menu

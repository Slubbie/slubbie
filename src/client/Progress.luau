-- Level / XP bar, level-up celebrations and the daily quest tracker.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Sounds = require(script.Parent.Sounds)
local UI = require(script.Parent.UI)
local VFX = require(script.Parent.VFX)

local Progress = {}

function Progress.Start(Movement)
	local player = Players.LocalPlayer
	local gui = UI.gui("Progress", 3)

	-- Level + XP bar ------------------------------------------------------------
	local panel = UI.new("Frame", {
		Position = UDim2.fromOffset(16, 60),
		Size = UDim2.fromOffset(280, 300),
		BackgroundTransparency = 1,
	}, gui)
	local levelLabel = UI.label(panel, {
		Size = UDim2.new(1, 0, 0, 24),
		Font = UI.Fonts.Title,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 0.5,
		Text = "LV 1",
	})
	local barBack = UI.new("Frame", {
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.fromOffset(220, 8),
		BackgroundColor3 = UI.Colors.Panel,
		BackgroundTransparency = 0.3,
	}, panel)
	UI.corner(barBack)
	local barFill = UI.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = UI.Colors.Gold }, barBack)
	UI.corner(barFill)
	local xpLabel = UI.label(panel, {
		Position = UDim2.fromOffset(226, 22),
		Size = UDim2.fromOffset(80, 20),
		TextSize = 12,
		TextColor3 = UI.Colors.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})

	local function refreshLevel()
		local xp = math.floor(player:GetAttribute("XP") or 0)
		local level = player:GetAttribute("Level") or 1
		local floor, ceiling = Config.XPForLevel(level), Config.XPForLevel(level + 1)
		levelLabel.Text = string.format("LV %d  ·  %s", level, string.upper(player:GetAttribute("Title") or "Drifter"))
		UI.tween(barFill, 0.4, { Size = UDim2.fromScale(math.clamp((xp - floor) / (ceiling - floor), 0, 1), 1) })
		xpLabel.Text = string.format("%d / %d", xp - floor, ceiling - floor)
	end
	player:GetAttributeChangedSignal("XP"):Connect(refreshLevel)
	player:GetAttributeChangedSignal("Level"):Connect(refreshLevel)
	refreshLevel()

	-- Daily quests ---------------------------------------------------------------
	UI.label(panel, {
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 0, 18),
		Font = UI.Fonts.Title,
		TextSize = 13,
		TextColor3 = UI.Colors.Accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 0.6,
		Text = "DAILY QUESTS",
	})
	local questList = UI.new("Frame", {
		Position = UDim2.fromOffset(0, 72),
		Size = UDim2.new(1, 0, 0, 200),
		BackgroundTransparency = 1,
	}, panel)
	UI.new("UIListLayout", { Padding = UDim.new(0, 6) }, questList)

	local function refreshQuests()
		for _, child in questList:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local raw = player:GetAttribute("Quests")
		local ok, quests = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		if not ok or type(quests) ~= "table" then
			return
		end
		for _, quest in quests do
			local row = UI.new("Frame", {
				Size = UDim2.new(1, 0, 0, 38),
				BackgroundColor3 = UI.Colors.Panel,
				BackgroundTransparency = 0.35,
			}, questList)
			UI.corner(row, 8)
			UI.label(row, {
				Position = UDim2.fromOffset(10, 3),
				Size = UDim2.new(1, -70, 0, 18),
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = if quest.Done then UI.Colors.Good else UI.Colors.Text,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = (if quest.Done then "✓ " else "") .. quest.Text,
			})
			UI.label(row, {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 3),
				Size = UDim2.fromOffset(60, 18),
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextColor3 = UI.Colors.Gold,
				Text = if quest.Done then "DONE" else "◆ " .. quest.Reward,
			})
			local track = UI.new("Frame", {
				Position = UDim2.fromOffset(10, 25),
				Size = UDim2.new(1, -20, 0, 5),
				BackgroundColor3 = UI.Colors.PanelLight,
			}, row)
			UI.corner(track)
			local fill = UI.new("Frame", {
				Size = UDim2.fromScale(math.clamp(quest.Progress / quest.Goal, 0, 1), 1),
				BackgroundColor3 = if quest.Done then UI.Colors.Good else UI.Colors.Accent,
			}, track)
			UI.corner(fill)
		end
	end
	player:GetAttributeChangedSignal("Quests"):Connect(refreshQuests)
	refreshQuests()

	-- Level-up banner --------------------------------------------------------------
	local banner = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(420, 110),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui)
	local bannerTitle = UI.label(banner, {
		Size = UDim2.new(1, 0, 0, 64),
		Font = UI.Fonts.Title,
		TextSize = 60,
		TextColor3 = UI.Colors.Gold,
		TextStrokeTransparency = 0.3,
		Text = "",
	})
	UI.new("UIGradient", { Color = ColorSequence.new(Color3.new(1, 1, 1), UI.Colors.Gold), Rotation = 90 }, bannerTitle)
	local bannerSub = UI.label(banner, {
		Position = UDim2.fromOffset(0, 66),
		Size = UDim2.new(1, 0, 0, 30),
		Font = UI.Fonts.Title,
		TextSize = 24,
		TextStrokeTransparency = 0.4,
		Text = "",
	})

	Net.Event("Notify").OnClientEvent:Connect(function(kind: string, data)
		if kind == "LevelUp" then
			bannerTitle.Text = "LEVEL " .. data.Level
			bannerSub.Text = string.upper(data.Title) .. "   ·   +" .. data.Shards .. " ◆"
			banner.Visible = true
			UI.pop(banner, 0.5)
			for i = 0, 4 do
				task.delay(i * 0.09, function()
					Sounds.Play(Config.Sounds.Ping, 0.5, 1 + i * 0.2)
				end)
			end
			local root = Movement.Info.Root
			if root then
				VFX.Flash(root.Position, UI.Colors.Gold, 16)
				VFX.Sparks(root.Position, UI.Colors.Gold, 40)
			end
			task.delay(3, function()
				banner.Visible = false
			end)
		elseif kind == "QuestComplete" then
			UI.toast("✓ QUEST COMPLETE: " .. data.Text .. "   +" .. data.Shards .. " ◆", UI.Colors.Good)
			Sounds.Play(Config.Sounds.Ping, 0.5, 1.3)
			task.delay(0.1, function()
				Sounds.Play(Config.Sounds.Ping, 0.5, 1.7)
			end)
		end
	end)

	-- Hidden while menus are open.
	RunService.RenderStepped:Connect(function()
		panel.Visible = Movement.Enabled
	end)
end

return Progress

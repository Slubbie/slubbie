-- Daily reward calendar. Pops up when you join if today's reward is waiting,
-- and can be opened from the menu any time.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Sounds = require(script.Parent.Sounds)
local UI = require(script.Parent.UI)
local VFX = require(script.Parent.VFX)

local Daily = {}
Daily.Open = false

local gui: ScreenGui? = nil
local Movement = nil

local function rewardText(reward): string
	local lines = { "◆ " .. (reward.Shards or 0) }
	if reward.XP then
		table.insert(lines, "+" .. reward.XP .. " XP")
	end
	if reward.Trail then
		local trail = Config.GetTrail(reward.Trail)
		table.insert(lines, (if trail then trail.Name else reward.Trail) .. " trail")
	end
	return table.concat(lines, "\n")
end

local function close()
	if gui then
		gui:Destroy()
		gui = nil
	end
	if Daily.Open then
		Daily.Open = false
		Movement.SetEnabled(true)
	end
end

function Daily.Show()
	if Daily.Open then
		return
	end
	local ok, status = pcall(function()
		return Net.Function("GetDaily"):InvokeServer()
	end)
	if not ok or type(status) ~= "table" then
		return
	end
	Daily.Open = true
	Movement.SetEnabled(false)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true

	local screen = UI.gui("DailyRewards", 30)
	gui = screen
	UI.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
	}, screen)
	local panel = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(760, 330),
		BackgroundColor3 = UI.Colors.Panel,
		BackgroundTransparency = 0.05,
	}, screen)
	UI.corner(panel, 20)
	UI.stroke(panel, UI.Colors.Gold, 2, 0.3)
	UI.pop(panel, 0.15)
	UI.label(panel, {
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.new(1, 0, 0, 40),
		Font = UI.Fonts.Title,
		TextSize = 34,
		TextColor3 = UI.Colors.Gold,
		Text = "DAILY REWARDS",
	})
	UI.label(panel, {
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 0, 20),
		TextSize = 15,
		TextColor3 = UI.Colors.Muted,
		Text = string.format(
			"Log in every day to build your streak  ·  current streak: %d day%s",
			status.Streak,
			if status.Streak == 1 then "" else "s"
		),
	})

	local row = UI.new("Frame", {
		Position = UDim2.fromOffset(20, 92),
		Size = UDim2.new(1, -40, 0, 150),
		BackgroundTransparency = 1,
	}, panel)
	UI.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 8),
	}, row)
	for day, reward in status.Rewards do
		local isToday = day == status.Day
		local claimed = day < status.Day or (isToday and not status.Available)
		local card = UI.new("Frame", {
			Size = UDim2.fromOffset(94, if isToday then 150 else 136),
			BackgroundColor3 = if isToday then UI.Colors.PanelLight else UI.Colors.Panel,
			BackgroundTransparency = if claimed and not isToday then 0.4 else 0,
			LayoutOrder = day,
		}, row)
		UI.corner(card, 12)
		UI.stroke(card, if isToday then UI.Colors.Gold else UI.Colors.PanelLight, if isToday then 3 else 1)
		UI.label(card, {
			Position = UDim2.fromOffset(0, 8),
			Size = UDim2.new(1, 0, 0, 18),
			Font = UI.Fonts.Title,
			TextSize = 14,
			TextColor3 = if isToday then UI.Colors.Gold else UI.Colors.Muted,
			Text = "DAY " .. day,
		})
		UI.label(card, {
			Position = UDim2.fromOffset(0, 30),
			Size = UDim2.new(1, 0, 0, 40),
			TextSize = 32,
			Text = if claimed
				then "✅"
				elseif reward.Trail then "✨"
				elseif day == #status.Rewards then "🎁"
				else "💎",
		})
		UI.label(card, {
			Position = UDim2.fromOffset(4, 76),
			Size = UDim2.new(1, -8, 0, 56),
			TextSize = 13,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = rewardText(reward),
		})
	end

	local claim = UI.button(panel, if status.Available then "CLAIM" else "COME BACK TOMORROW", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(if status.Available then 220 else 300, 50),
		BackgroundColor3 = if status.Available then UI.Colors.Gold else UI.Colors.PanelLight,
		TextColor3 = if status.Available then UI.Colors.Panel else UI.Colors.Muted,
	})
	local closeButton = UI.button(panel, "✕", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(40, 40),
		TextSize = 20,
		BackgroundColor3 = UI.Colors.PanelLight,
	})
	closeButton.Activated:Connect(close)
	claim.Activated:Connect(function()
		if not status.Available then
			close()
			return
		end
		local claimed, reward = Net.Function("ClaimDaily"):InvokeServer()
		close()
		if claimed and reward then
			UI.toast("DAILY REWARD  ·  " .. string.gsub(rewardText(reward), "\n", "  ·  "), UI.Colors.Gold)
			for i = 0, 4 do
				task.delay(i * 0.08, function()
					Sounds.Play(Config.Sounds.Ping, 0.45, 1.2 + i * 0.2)
				end)
			end
			local root = Movement.Info.Root
			if root then
				VFX.Flash(root.Position, UI.Colors.Gold, 14)
				VFX.Sparks(root.Position, UI.Colors.Gold, 40)
			end
		end
	end)
end

function Daily.Start(movement, Menu)
	Movement = movement
	local player = Players.LocalPlayer
	Menu.DailyRequested.Event:Connect(function()
		Menu.Close()
		Daily.Show()
	end)
	-- On join: wait for data and for the title screen to close, then pop up.
	while player:GetAttribute("DailyAvailable") == nil do
		task.wait(0.5)
	end
	while Menu.IsOpen() do
		task.wait(0.25)
	end
	task.wait(1)
	if player:GetAttribute("DailyAvailable") then
		Daily.Show()
	end
end

return Daily

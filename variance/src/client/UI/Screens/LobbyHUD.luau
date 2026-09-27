-- Always-on lobby interface: your file card (clearance, XP, Marks, standing),
-- the terminal menu (every lobby terminal is reachable from here), the queue
-- status bar and your private-trial chip. Hidden while you are at a table.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Format = require(ReplicatedStorage.Variance.Util.Format)
local Config = require(ReplicatedStorage.Variance.Config)
local Kit = require(script.Parent.Parent.Kit)
local Motion = require(script.Parent.Parent.Motion)
local Theme = require(script.Parent.Parent.Theme)
local Icons = require(script.Parent.Parent.Icons)

local LobbyHUD = {}
LobbyHUD.__index = LobbyHUD

local MENU = {
	{ Id = "Play", Label = "EVALUATION", Screen = "Play", Args = { Tab = "Queue" }, Icon = "Play" },
	{ Id = "Private", Label = "PRIVATE TRIALS", Screen = "Private" },
	{ Id = "Ranked", Label = "STANDING", Screen = "Ranked", Icon = "Target" },
	{ Id = "Locker", Label = "LOCKER", Screen = "Locker" },
	{ Id = "Challenges", Label = "DIRECTIVES", Screen = "Challenges" },
	{ Id = "Archive", Label = "ARCHIVE", Screen = "Archive", Icon = "Archive" },
	{ Id = "Record", Label = "RECORD", Screen = "Record", Icon = "Trophy" },
	{ Id = "Settings", Label = "SETTINGS", Screen = "Settings", Icon = "Gear" },
}

function LobbyHUD.new(ui, controllers)
	local self = setmetatable({}, LobbyHUD)
	self.UI = ui
	self.C = controllers
	self.Main = false
	self.Visible = false
	local root = Kit.create("Frame", { Name = "LobbyHUD", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = ui.Hud }) :: Frame
	self.Frame = root

	-- File card.
	local card = Kit.panel(root, { Name = "Card", Size = UDim2.fromOffset(300, 108), Position = UDim2.fromOffset(16, 16), Color = "Panel" })
	Kit.padding(card, 12, 14)
	self.Name = Kit.label(card, { Text = Players.LocalPlayer.DisplayName, Font = "Bold", TextSize = "Body", Size = UDim2.new(1, -70, 0, 20) })
	self.Clearance = Kit.label(card, { Text = "CLEARANCE 1", Font = "Mono", TextSize = "Label", Color = "Accent", Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 24) })
	self.XPBar = Kit.bar(card, { Size = UDim2.new(1, 0, 0, 5), Position = UDim2.fromOffset(0, 46), Value = 0 })
	self.XPText = Kit.label(card, { Text = "", Font = "Mono", TextSize = "Tiny", Color = "Dim", Size = UDim2.new(0.6, 0, 0, 14), Position = UDim2.fromOffset(0, 54) })
	self.Marks = Kit.label(card, { Text = "0 MARKS", Font = "Mono", TextSize = "Label", XAlign = "Right", Color = "Text", Size = UDim2.new(0.4, 0, 0, 14), Position = UDim2.new(0.6, 0, 0, 54) })
	self.Standing = Kit.label(card, { Text = "", Font = "Mono", TextSize = "Tiny", Color = "Dim", Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 72) })
	self.Guest = Kit.label(card, { Text = "OFFLINE FILE :: PROGRESS WILL SYNC WHEN RECORDS RETURN", Font = "Mono", TextSize = "Tiny", Color = "Warn", Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 72), Visible = false })
	local level = Kit.label(card, { Name = "Level", Text = "1", Font = "Display", TextSize = "Heading", XAlign = "Right", Color = "Accent", Size = UDim2.fromOffset(70, 34), Position = UDim2.new(1, -70, 0, -4) })
	self.Level = level

	-- Terminal menu.
	local menu = Kit.create("Frame", { Name = "Menu", BackgroundTransparency = 1, Size = UDim2.fromOffset(210, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = UDim2.new(1, -16, 0, 16), AnchorPoint = Vector2.new(1, 0), Parent = root }) :: Frame
	Kit.list(menu, "Y", 6)
	self.Badges = {}
	for i, entry in MENU do
		local button = Kit.button(menu, {
			Name = entry.Id,
			Text = entry.Label,
			Size = UDim2.new(1, 0, 0, 36),
			Style = if i == 1 then "Primary" else "Default",
			LayoutOrder = i,
			OnClick = function()
				ui:open(entry.Screen, entry.Args)
			end,
		})
		if entry.Icon then
			local holder = Kit.create("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(16, 16), Position = UDim2.new(0, 12, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 3, Parent = button }) :: Frame
			Icons.symbol(entry.Icon, holder, 16)
		end
		local badge = Kit.create("Frame", { Name = "Badge", BorderSizePixel = 0, Size = UDim2.fromOffset(20, 18), Position = UDim2.new(0, -8, 0, -6), Visible = false, ZIndex = 5, Parent = button }) :: Frame
		Theme.bind(badge, "BackgroundColor3", "Bad")
		Kit.corner(badge, 9)
		Kit.label(badge, { Name = "Count", Text = "", Font = "Bold", TextSize = "Tiny", XAlign = "Center", Size = UDim2.fromScale(1, 1), Color = "Text", ZIndex = 6 })
		self.Badges[entry.Id] = badge
		if i == 1 then
			self.PlayButton = button
		end
	end

	-- Queue bar.
	local queue = Kit.panel(root, { Name = "Queue", Size = UDim2.fromOffset(520, 52), Position = UDim2.new(0.5, 0, 1, -20), AnchorPoint = Vector2.new(0.5, 1), Visible = false })
	Kit.padding(queue, 8, 14)
	local pulse = Kit.create("Frame", { BorderSizePixel = 0, Size = UDim2.fromOffset(10, 10), Position = UDim2.new(0, 0, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Parent = queue }) :: Frame
	Theme.bind(pulse, "BackgroundColor3", "Accent")
	Kit.corner(pulse, 5)
	self.QueuePulse = pulse
	self.QueueText = Kit.label(queue, { Text = "", Font = "Mono", TextSize = "Label", Size = UDim2.new(1, -150, 1, 0), Position = UDim2.fromOffset(20, 0) })
	Kit.button(queue, {
		Text = "CANCEL",
		Size = UDim2.fromOffset(110, 34),
		Position = UDim2.new(1, 0, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Style = "Danger",
		OnClick = function()
			controllers.NetworkClient:request("Queue.Leave")
		end,
	})
	self.QueueFrame = queue

	-- Private trial chip.
	local chip = Kit.button(root, {
		Name = "LobbyChip",
		Text = "",
		Size = UDim2.fromOffset(300, 40),
		Position = UDim2.new(0, 16, 1, -20),
		AnchorPoint = Vector2.new(0, 1),
		OnClick = function()
			ui:open("Private")
		end,
	})
	chip.Visible = false
	self.Chip = chip

	-- Hint line for new players.
	self.Hint = Kit.label(root, {
		Text = "Walk to a terminal and press [E], or use the menu.",
		Font = "Mono",
		TextSize = "Small",
		Color = "Dim",
		XAlign = "Center",
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0, 0, 1, -84),
	})

	self.QueueState = nil
	controllers.ProfileController.Changed:Connect(function(profile)
		self:refreshProfile(profile)
	end)
	controllers.NetworkClient:onPush("Queue", function(data)
		self:setQueue(data)
	end)
	controllers.NetworkClient:onPush("Lobby", function(data)
		self:setLobby(data)
	end)
	controllers.MatchClient.Began:Connect(function()
		self:Close()
	end)
	controllers.MatchClient.Ended:Connect(function()
		self:Open()
	end)
	controllers.InputController.Action:Connect(function(action, phase)
		if phase ~= "Begin" or not self.Visible then
			return
		end
		if action == "Menu" then
			if ui:currentScreen() then
				ui:close()
			else
				ui:open("Play", { Tab = "Queue" })
			end
		elseif action == "Back" and ui:currentScreen() then
			ui:close()
		end
	end)
	RunService.Heartbeat:Connect(function()
		if self.Visible and self.QueueState and self.QueueState.Queue then
			local elapsed = workspace:GetServerTimeNow() - (self.QueueState.Joined or workspace:GetServerTimeNow())
			local def = Config.Matchmaking.Queues[self.QueueState.Queue]
			local text = string.format("SEARCHING :: %s  ·  %s  ·  %d WAITING", self.QueueState.Name or "", Format.clock(elapsed), self.QueueState.Waiting or 1)
			if def and def.BotAfter and elapsed < def.BotAfter then
				text ..= string.format("  ·  SURROGATE IN %s", Format.clock(def.BotAfter - elapsed))
			end
			self.QueueText.Text = text
			self.QueuePulse.BackgroundTransparency = 0.5 + 0.5 * math.sin(os.clock() * 5)
		end
	end)
	if controllers.ProfileController:get() then
		self:refreshProfile(controllers.ProfileController:get())
	end
	return self
end

function LobbyHUD:refreshProfile(profile)
	if profile == nil then
		return
	end
	self.Level.Text = tostring(profile.Level)
	self.Clearance.Text = string.format("CLEARANCE %d  ·  %s", profile.Level, profile.Title or "")
	Kit.setBar(self.XPBar, (profile.LevelInto or 0) / math.max(profile.LevelNeed or 1, 1), true)
	self.XPText.Text = string.format("%s / %s XP", Format.thousands(profile.LevelInto or 0), Format.thousands(profile.LevelNeed or 0))
	self.Marks.Text = Format.thousands(profile.Marks or 0) .. " MARKS"
	local ranked = profile.Ranked
	if ranked then
		self.Standing.Text = if ranked.Placed
			then string.format("STANDING %d  ·  %s", ranked.Rating, ranked.Division and ranked.Division.Label or "")
			else string.format("STANDING :: %d PLACEMENT%s LEFT", ranked.PlacementsLeft or 0, (ranked.PlacementsLeft or 0) == 1 and "" or "S")
	end
	self.Guest.Visible = profile.Guest == true
	self.Standing.Visible = profile.Guest ~= true
	-- Badges: claimable directives, unread files.
	local claimable = 0
	for _, list in { profile.Challenges and profile.Challenges.Daily or {}, profile.Challenges and profile.Challenges.Weekly or {} } do
		for _, c in list do
			if c.Done and not c.Claimed then
				claimable += 1
			end
		end
	end
	local unread = 0
	if profile.Lore then
		for id in profile.Lore.Unlocked or {} do
			if not (profile.Lore.Read or {})[id] then
				unread += 1
			end
		end
	end
	for id, count in { Challenges = claimable, Archive = unread } do
		local badge = self.Badges[id]
		badge.Visible = count > 0
		local label = badge:FindFirstChild("Count") :: TextLabel?
		if label then
			label.Text = tostring(count)
		end
	end
	self.Hint.Visible = (profile.Stats and profile.Stats.Matches or 0) < 3
end

function LobbyHUD:setQueue(data)
	if data and data.Queue then
		self.QueueState = data
		self.QueueFrame.Visible = self.Visible
		Kit.setText(self.PlayButton, "SEARCHING...")
	else
		self.QueueState = nil
		self.QueueFrame.Visible = false
		Kit.setText(self.PlayButton, "EVALUATION")
		if data and data.Matched then
			self.C.AudioController:play("Unlock")
			self.UI:banner("SUBJECT FOUND", if data.Backfill then "A SURROGATE TAKES THE EMPTY SEAT" else "PROCEED TO YOUR TABLE", "Accent", 1.6)
		end
	end
end

function LobbyHUD:setLobby(data)
	self.LobbyState = data
	if data then
		self.Chip.Visible = self.Visible
		Kit.setText(self.Chip, string.format("PRIVATE TRIAL :: %s  ·  %d/%d", data.Code, data.Total or 1, if data.Format == "Tournament" then 8 else 4))
	else
		self.Chip.Visible = false
	end
end

function LobbyHUD:Open()
	if self.C.MatchClient:active() then
		return
	end
	self.Visible = true
	self.Frame.Visible = true
	self.QueueFrame.Visible = self.QueueState ~= nil
	self.Chip.Visible = self.LobbyState ~= nil
	local card = self.Frame:FindFirstChild("Card") :: Frame
	card.Position = UDim2.fromOffset(-320, 16)
	Motion.tween(card, 0.4, { Position = UDim2.fromOffset(16, 16) }, "slide")
end

function LobbyHUD:Close()
	self.Visible = false
	self.Frame.Visible = false
end

return LobbyHUD

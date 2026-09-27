-- PRIVATE TRIALS: lobbies with friends.
--
-- Outside a lobby: create one, or join with a code (works across servers: the
-- server looks the code up and teleports you to the host's server).
-- Inside: the invite code, Roblox friend invites (the code rides along in the
-- invite's launch data, so accepting drops the friend straight into this
-- lobby), members and their ready state, surrogate seats, the format (single
-- match or tournament) and the custom rules, which only the host can edit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Personalities = require(ReplicatedStorage.Variance.Core.AI.Personalities)
local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Window = require(script.Parent.Parent.Window)
local RulesEditor = require(script.Parent.Parent.RulesEditor)

local Private = {}
Private.__index = Private

local DIFFICULTIES = { "Casual", "Standard", "Advanced", "Expert" }

function Private.new(ui, controllers)
	local self = setmetatable({}, Private)
	self.UI = ui
	self.C = controllers
	self.Main = true
	self.State = nil
	self.BotPersona = "Ledger"
	self.BotDifficulty = "Standard"
	self.Window = Window.new(ui, { Name = "Private", Title = "PRIVATE TRIALS", Subtitle = "INVITE-ONLY EVALUATIONS", Width = 980, Height = 620 })
	self.Frame = self.Window.Frame
	controllers.NetworkClient:onPush("Lobby", function(state)
		self.State = state
		if self.Window.Visible then
			self:render()
		end
	end)
	return self
end

local function request(self, endpoint: string, ...)
	local ok, err = self.C.NetworkClient:request(endpoint, ...)
	if not ok and err then
		self.UI:toast("PRIVATE TRIAL", tostring(err), "Warn")
	end
	return ok, err
end

function Private:render()
	Window.clear(self.Window.Body)
	if self.State == nil then
		self:renderOutside()
	else
		self:renderLobby(self.State)
	end
end

function Private:renderOutside()
	local body = self.Window.Body
	self.Window:setSubtitle("INVITE-ONLY EVALUATIONS")
	local create = Kit.panel(body, { Size = UDim2.new(0.5, -8, 0, 220), Color = "PanelAlt" })
	Kit.padding(create, 16, 18)
	Kit.label(create, { Text = "HOST A TRIAL", Font = "Display", TextSize = "Title", Color = "Accent", Size = UDim2.new(1, 0, 0, 28) })
	Kit.label(create, {
		Text = "Get an invite code, bring friends or surrogates, set every rule yourself, and play a single match or a bracket tournament.",
		Font = "Body",
		TextSize = "Small",
		Wrap = true,
		YAlign = "Top",
		Size = UDim2.new(1, 0, 0, 80),
		Position = UDim2.fromOffset(0, 36),
	})
	Kit.button(create, {
		Text = "CREATE LOBBY",
		Style = "Primary",
		Size = UDim2.new(1, 0, 0, 44),
		Position = UDim2.new(0, 0, 1, -44),
		OnClick = function()
			request(self, "Lobby.Create")
		end,
	})
	local join = Kit.panel(body, { Size = UDim2.new(0.5, -8, 0, 220), Position = UDim2.new(0.5, 8, 0, 0), Color = "PanelAlt" })
	Kit.padding(join, 16, 18)
	Kit.label(join, { Text = "JOIN WITH A CODE", Font = "Display", TextSize = "Title", Color = "Accent", Size = UDim2.new(1, 0, 0, 28) })
	local box = Kit.create("TextBox", {
		Name = "Code",
		Text = "",
		PlaceholderText = "ABC234",
		ClearTextOnFocus = false,
		Font = Theme.Fonts.Mono,
		TextSize = 28,
		Size = UDim2.new(1, 0, 0, 52),
		Position = UDim2.fromOffset(0, 50),
		BorderSizePixel = 0,
		Parent = join,
	}) :: TextBox
	Theme.bind(box, "BackgroundColor3", "Raised")
	Theme.bind(box, "TextColor3", "Text")
	Theme.bind(box, "PlaceholderColor3", "Faint")
	Kit.corner(box, 3)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		local clean = string.upper((string.gsub(box.Text, "[^%w]", "")))
		if #clean > 8 then
			clean = string.sub(clean, 1, 8)
		end
		if clean ~= box.Text then
			box.Text = clean
		end
	end)
	Kit.button(join, {
		Text = "JOIN",
		Size = UDim2.new(1, 0, 0, 44),
		Position = UDim2.new(0, 0, 1, -44),
		OnClick = function()
			if #box.Text >= 4 then
				request(self, "Lobby.Join", box.Text)
			else
				self.UI:toast("PRIVATE TRIAL", "Enter the code your host shared.", "Warn")
			end
		end,
	})
end

function Private:invite(code: string)
	local player = Players.LocalPlayer
	task.spawn(function()
		local ok, can = pcall(SocialService.CanSendGameInviteAsync, SocialService, player)
		if not ok or not can then
			self.UI:toast("INVITES UNAVAILABLE", "Share the code instead: " .. code, "Warn")
			return
		end
		local options = Instance.new("ExperienceInviteOptions")
		options.PromptMessage = "Join my Private Trial in VARIANCE (code " .. code .. ")"
		options.LaunchData = code
		local sent = pcall(SocialService.PromptGameInvite, SocialService, player, options)
		if not sent then
			self.UI:toast("INVITES UNAVAILABLE", "Share the code instead: " .. code, "Warn")
		end
	end)
end

function Private:renderLobby(state)
	local body = self.Window.Body
	local me = Players.LocalPlayer.UserId
	local isHost = state.Host == me
	self.Window:setSubtitle(if state.InMatch then "A TRIAL IS IN PROGRESS" else string.format("%d SUBJECT%s", state.Total or 1, (state.Total or 1) == 1 and "" or "S"))

	-- Left column: code, members, surrogates, controls.
	local left = Kit.create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.44, -8, 1, 0), Parent = body }) :: Frame
	local codePanel = Kit.panel(left, { Size = UDim2.new(1, 0, 0, 74), Color = "Bg" })
	Kit.padding(codePanel, 8, 14)
	Kit.label(codePanel, { Text = "INVITE CODE", Font = "Mono", TextSize = "Tiny", Color = "Dim", Size = UDim2.new(1, 0, 0, 14) })
	local codeBox = Kit.create("TextBox", {
		Text = state.Code,
		TextEditable = false,
		ClearTextOnFocus = false,
		Font = Theme.Fonts.Display,
		TextSize = 30,
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -150, 0, 40),
		Position = UDim2.fromOffset(0, 18),
		Parent = codePanel,
	}) :: TextBox
	Theme.bind(codeBox, "TextColor3", "Accent")
	Kit.tooltip(codeBox, "Select to copy. Friends can enter it at the Private Trials terminal.")
	Kit.button(codePanel, {
		Text = "INVITE FRIENDS",
		Size = UDim2.fromOffset(140, 36),
		Position = UDim2.new(1, 0, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Style = "Primary",
		OnClick = function()
			self:invite(state.Code)
		end,
	})

	local list = Kit.scroll(left, { Size = UDim2.new(1, 0, 1, -190), Position = UDim2.fromOffset(0, 84), Padding = 4 })
	for i, member in state.Members or {} do
		local rowFrame = Kit.panel(list, { Size = UDim2.new(1, -8, 0, 38), LayoutOrder = i, Color = "PanelAlt" })
		Kit.padding(rowFrame, 4, 10)
		local tag = if member.Host then "HOST" elseif member.Ready then "READY" else "NOT READY"
		Kit.label(rowFrame, { Text = string.upper(member.Name) .. "  ·  CL " .. tostring(member.Level or 1), Font = "Bold", TextSize = "Small", Size = UDim2.new(1, -150, 1, 0) })
		Kit.label(rowFrame, { Text = tag, Font = "Mono", TextSize = "Tiny", Color = if member.Ready or member.Host then "Good" else "Warn", XAlign = "Right", Size = UDim2.new(0, 80, 1, 0), Position = UDim2.new(1, -140, 0, 0) })
		if isHost and member.UserId ~= me then
			Kit.button(rowFrame, {
				Text = "KICK",
				Size = UDim2.fromOffset(54, 28),
				Position = UDim2.new(1, 0, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				Style = "Danger",
				TextSize = "Tiny",
				OnClick = function()
					if Kit.confirm("REMOVE SUBJECT", "Remove " .. member.Name .. " from the lobby?", "REMOVE", true) then
						request(self, "Lobby.Kick", member.UserId)
					end
				end,
			})
		end
	end
	for i, bot in state.Bots or {} do
		local rowFrame = Kit.panel(list, { Size = UDim2.new(1, -8, 0, 38), LayoutOrder = 100 + i, Color = "PanelAlt" })
		Kit.padding(rowFrame, 4, 10)
		Kit.label(rowFrame, { Text = string.upper(bot.Name or bot.Personality) .. "  ·  SURROGATE", Font = "Bold", TextSize = "Small", Color = "Dim", Size = UDim2.new(1, -150, 1, 0) })
		Kit.label(rowFrame, { Text = string.upper(bot.Difficulty or ""), Font = "Mono", TextSize = "Tiny", Color = "Dim", XAlign = "Right", Size = UDim2.new(0, 80, 1, 0), Position = UDim2.new(1, -140, 0, 0) })
		if isHost then
			Kit.button(rowFrame, {
				Text = "X",
				Size = UDim2.fromOffset(34, 28),
				Position = UDim2.new(1, 0, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				Style = "Danger",
				Tooltip = "Remove surrogate",
				OnClick = function()
					request(self, "Lobby.RemoveBot", i)
				end,
			})
		end
	end

	local controls = Kit.create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 96), Position = UDim2.new(0, 0, 1, -96), Parent = left }) :: Frame
	if isHost then
		local addRow = Kit.create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), Parent = controls }) :: Frame
		Kit.button(addRow, {
			Text = Personalities.get(self.BotPersona).Name,
			Size = UDim2.new(0.34, -4, 1, 0),
			TextSize = "Tiny",
			Tooltip = "Choose surrogate",
			OnClick = function()
				local all = Personalities.selectable(false)
				local index = 1
				for j, p in all do
					if p.Id == self.BotPersona then
						index = j
					end
				end
				self.BotPersona = all[(index % #all) + 1].Id
				self:render()
			end,
		})
		Kit.button(addRow, {
			Text = string.upper(self.BotDifficulty),
			Size = UDim2.new(0.3, -4, 1, 0),
			Position = UDim2.fromScale(0.34, 0),
			TextSize = "Tiny",
			Tooltip = "Choose difficulty",
			OnClick = function()
				local index = table.find(DIFFICULTIES, self.BotDifficulty) or 1
				self.BotDifficulty = DIFFICULTIES[(index % #DIFFICULTIES) + 1]
				self:render()
			end,
		})
		Kit.button(addRow, {
			Text = "+ SURROGATE",
			Size = UDim2.new(0.36, 0, 1, 0),
			Position = UDim2.fromScale(0.64, 0),
			TextSize = "Tiny",
			OnClick = function()
				request(self, "Lobby.AddBot", self.BotPersona, self.BotDifficulty)
			end,
		})
		local start = Kit.button(controls, {
			Text = if state.Format == "Tournament" then "START TOURNAMENT" else "START TRIAL",
			Style = "Primary",
			Size = UDim2.new(0.62, -4, 0, 46),
			Position = UDim2.new(0, 0, 1, -46),
			OnClick = function()
				if request(self, "Lobby.Start") then
					self.UI:close("Private")
				end
			end,
		})
		Kit.setEnabled(start, state.CanStart == true, state.StartBlocked)
	else
		local ready = false
		for _, member in state.Members or {} do
			if member.UserId == me then
				ready = member.Ready
			end
		end
		Kit.button(controls, {
			Text = if ready then "READY  ✓" else "MARK READY",
			Style = if ready then "Default" else "Primary",
			Size = UDim2.new(0.62, -4, 0, 46),
			Position = UDim2.new(0, 0, 1, -46),
			OnClick = function()
				request(self, "Lobby.SetReady", not ready)
			end,
		})
	end
	Kit.button(controls, {
		Text = "LEAVE",
		Style = "Danger",
		Size = UDim2.new(0.38, -4, 0, 46),
		Position = UDim2.new(0.62, 4, 1, -46),
		OnClick = function()
			request(self, "Lobby.Leave")
		end,
	})

	-- Right column: format and rules.
	local right = Kit.panel(body, { Size = UDim2.new(0.56, -8, 1, 0), Position = UDim2.new(0.44, 8, 0, 0), Color = "PanelAlt" })
	Kit.padding(right, 12, 14)
	local formatRow = Kit.create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), Parent = right }) :: Frame
	for i, format in { "Match", "Tournament" } do
		local b = Kit.button(formatRow, {
			Text = if format == "Match" then "SINGLE TRIAL" else "TOURNAMENT",
			Size = UDim2.new(0.5, -4, 1, 0),
			Position = UDim2.new((i - 1) * 0.5, (i - 1) * 4, 0, 0),
			Style = "Ghost",
			Sound = "Tab",
			Tooltip = if format == "Tournament" then "Single-elimination bracket; surrogates fill empty seats." else "One match for everyone in the lobby (up to four subjects).",
			OnClick = function()
				if isHost then
					request(self, "Lobby.SetFormat", format)
				end
			end,
		})
		b:SetAttribute("Active", state.Format == format)
		if not isHost then
			Kit.setEnabled(b, state.Format == format, "Only the host can change the format.")
		end
	end
	Kit.label(right, {
		Text = table.concat(state.Describe or {}, "  ·  "),
		Font = "Mono",
		TextSize = "Tiny",
		Color = "Dim",
		Wrap = true,
		YAlign = "Top",
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.fromOffset(0, 40),
	})
	local editorHolder = Kit.create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -84), Position = UDim2.fromOffset(0, 80), Parent = right }) :: Frame
	if state.Tournament then
		self:renderBracket(editorHolder, state.Tournament)
		return
	end
	RulesEditor.new(editorHolder, state.Rules, function(value)
		self.PendingRules = value
		-- Debounce edits so a slider drag sends one update.
		local token = os.clock()
		self.RulesToken = token
		task.delay(0.6, function()
			if self.RulesToken == token then
				request(self, "Lobby.SetRules", self.PendingRules)
			end
		end)
	end, not isHost)
end

-- Tournament bracket: every round's pairings, winners and live matches.
function Private:renderBracket(parent: Frame, t)
	local scroll = Kit.scroll(parent, { Padding = 6 })
	local order = 1
	Kit.header(scroll, if t.Champion then "CHAMPION :: " .. string.upper(t.Champion) else "BRACKET  ·  ROUND " .. tostring(t.Round or 1), order)
	for r, round in t.Rounds or {} do
		order += 1
		Kit.label(scroll, { Text = "ROUND " .. r, Font = "Mono", TextSize = "Label", Color = "Accent", LayoutOrder = order, Size = UDim2.new(1, 0, 0, 18) })
		for _, pair in round do
			order += 1
			local rowFrame = Kit.panel(scroll, { Size = UDim2.new(1, -8, 0, 34), LayoutOrder = order, Color = "Bg" })
			Kit.padding(rowFrame, 4, 10)
			local text = string.upper(pair.A) .. "  VS  " .. string.upper(pair.B)
			if pair.Winner then
				text ..= "   →   " .. string.upper(pair.Winner)
			end
			Kit.label(rowFrame, { Text = text, Font = "Mono", TextSize = "Tiny", Color = if pair.Winner then "Dim" else "Text", Size = UDim2.new(1, -90, 1, 0) })
			if pair.Live and pair.MatchId then
				Kit.button(rowFrame, {
					Text = "WATCH",
					Size = UDim2.fromOffset(80, 26),
					Position = UDim2.new(1, 0, 0.5, 0),
					AnchorPoint = Vector2.new(1, 0.5),
					TextSize = "Tiny",
					OnClick = function()
						self.C.SpectatorController:watch(pair.MatchId)
					end,
				})
			end
		end
	end
end

function Private:Open()
	self.Window:open()
	self:render()
end

function Private:Close()
	self.Window:close()
end

return Private

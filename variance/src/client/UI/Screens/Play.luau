-- EVALUATION: every way into a Trial.
--   QUEUE     public matchmaking (Standard, Rapid, Chaos, Precision, Crossfire),
--             plus Endurance and a link to Ranked.
--   SOLO      pick a surrogate and a difficulty (the Proctor appears once earned).
--   PRACTICE  a sandbox with every rule adjustable, against surrogates.
--   TRAINING  Orientation and the advanced seminars.
--   WATCH     live Trials you can spectate.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Variance.Config)
local Modes = require(ReplicatedStorage.Variance.Core.Modes)
local Personalities = require(ReplicatedStorage.Variance.Core.AI.Personalities)
local Difficulty = require(ReplicatedStorage.Variance.Core.AI.Difficulty)
local Surrogates = require(ReplicatedStorage.Variance.Data.Surrogates)
local Tutorials = require(ReplicatedStorage.Variance.Data.Tutorials)
local Environments = require(ReplicatedStorage.Variance.Data.Environments)
local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Window = require(script.Parent.Parent.Window)
local RulesEditor = require(script.Parent.Parent.RulesEditor)

local Play = {}
Play.__index = Play

local TABS = {
	{ Id = "Queue", Label = "QUEUE" },
	{ Id = "Solo", Label = "SURROGATES" },
	{ Id = "Practice", Label = "PRACTICE" },
	{ Id = "Training", Label = "TRAINING" },
	{ Id = "Watch", Label = "WATCH" },
}

local DIFFICULTIES = { "Casual", "Standard", "Advanced", "Expert", "Adaptive" }

function Play.new(ui, controllers)
	local self = setmetatable({}, Play)
	self.UI = ui
	self.C = controllers
	self.Main = true
	self.Surrogate = "Ledger"
	self.Difficulty = "Standard"
	self.SandboxBots = { { Personality = "Ledger", Difficulty = "Standard" } }
	self.SandboxRules = nil
	self.Window = Window.new(ui, {
		Name = "Play",
		Title = "EVALUATION",
		Subtitle = "CHOOSE HOW YOU WILL BE TESTED",
		Width = 980,
		Height = 620,
		Tabs = TABS,
		OnTab = function(id)
			self:show(id)
		end,
	})
	self.Frame = self.Window.Frame
	return self
end

function Play:clear()
	Window.clear(self.Window.Body)
end

function Play:show(tab: string)
	self:clear()
	self.Tab = tab
	if tab == "Queue" then
		self:queueTab()
	elseif tab == "Solo" then
		self:soloTab()
	elseif tab == "Practice" then
		self:practiceTab()
	elseif tab == "Training" then
		self:trainingTab()
	elseif tab == "Watch" then
		self:watchTab()
	end
end

local function request(self, endpoint: string, ...)
	local ok, err = self.C.NetworkClient:request(endpoint, ...)
	if not ok then
		self.UI:toast("NOT NOW", tostring(err), "Warn")
	end
	return ok, err
end

---------------------------------------------------------------------------
-- Queue
---------------------------------------------------------------------------

function Play:queueTab()
	local body = self.Window.Body
	local grid =
		Kit.create("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = body }) :: Frame
	Kit.grid(grid, UDim2.new(1 / 3, -8, 0, 210), 10)
	local order = { "Duel", "Rapid", "Chaos", "Precision", "Crossfire" }
	for i, queueId in order do
		local def = Config.Matchmaking.Queues[queueId]
		local mode = Modes.get(def.Mode)
		local card = Kit.panel(grid, { LayoutOrder = i, Color = "PanelAlt" })
		Kit.padding(card, 12, 14)
		Kit.label(card, {
			Text = mode and mode.Name or def.Name,
			Font = "Display",
			TextSize = "Body",
			Color = "Accent",
			Size = UDim2.new(1, 0, 0, 22),
		})
		Kit.label(card, {
			Text = string.format("%s  ·  %d SUBJECTS", if def.Size > 2 then "FREE-FOR-ALL" else "1 V 1", def.Size),
			Font = "Mono",
			TextSize = "Tiny",
			Color = "Dim",
			Size = UDim2.new(1, 0, 0, 14),
			Position = UDim2.fromOffset(0, 24),
		})
		Kit.label(card, {
			Text = mode and mode.Description or "",
			Font = "Body",
			TextSize = "Small",
			Wrap = true,
			YAlign = "Top",
			Size = UDim2.new(1, 0, 0, 96),
			Position = UDim2.fromOffset(0, 44),
		})
		Kit.button(card, {
			Text = "JOIN QUEUE",
			Style = if i == 1 then "Primary" else "Default",
			Size = UDim2.new(1, 0, 0, 36),
			Position = UDim2.new(0, 0, 1, -36),
			Tooltip = if def.BotAfter
				then string.format("If no subject is found within %ds, a surrogate takes the seat.", def.BotAfter)
				else nil,
			OnClick = function()
				if request(self, "Queue.Join", queueId) then
					self.UI:close("Play")
				end
			end,
		})
	end
	-- Endurance and Ranked.
	local endurance = Modes.get("Endurance")
	local card = Kit.panel(grid, { LayoutOrder = 6, Color = "PanelAlt" })
	Kit.padding(card, 12, 14)
	Kit.label(card, {
		Text = endurance and endurance.Name or "ENDURANCE",
		Font = "Display",
		TextSize = "Body",
		Color = "Accent",
		Size = UDim2.new(1, 0, 0, 22),
	})
	Kit.label(card, {
		Text = endurance and endurance.Description or "",
		Font = "Body",
		TextSize = "Small",
		Wrap = true,
		YAlign = "Top",
		Size = UDim2.new(1, 0, 0, 80),
		Position = UDim2.fromOffset(0, 28),
	})
	Kit.button(card, {
		Text = "BEGIN ENDURANCE",
		Size = UDim2.new(0.5, -4, 0, 36),
		Position = UDim2.new(0, 0, 1, -36),
		OnClick = function()
			if request(self, "Endurance.Start") then
				self.UI:close("Play")
			end
		end,
	})
	Kit.button(card, {
		Text = "RANKED",
		Style = "Danger",
		Size = UDim2.new(0.5, -4, 0, 36),
		Position = UDim2.new(0.5, 4, 1, -36),
		OnClick = function()
			self.UI:open("Ranked")
		end,
	})
end

---------------------------------------------------------------------------
-- Solo
---------------------------------------------------------------------------

function Play:soloTab()
	local body = self.Window.Body
	local profile = self.C.ProfileController:get()
	local unlocked = profile and profile.Flags and profile.Flags.ProctorUnlocked
	local list = Personalities.selectable(true)
	local left =
		Kit.create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.42, -8, 1, 0), Parent = body }) :: Frame
	Kit.list(left, "Y", 6)
	local right =
		Kit.panel(body, { Size = UDim2.new(0.58, -8, 1, 0), Position = UDim2.new(0.42, 8, 0, 0), Color = "PanelAlt" })
	Kit.padding(right, 14, 16)
	local function detail()
		for _, child in right:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local persona = Personalities.get(self.Surrogate)
		local look = Surrogates.get(persona.Id)
		local portrait =
			Kit.create("Frame", { BorderSizePixel = 0, Size = UDim2.fromOffset(84, 84), Parent = right }) :: Frame
		portrait.BackgroundColor3 = if look and look.Portrait
			then Color3.fromRGB(look.Portrait[1], look.Portrait[2], look.Portrait[3])
			else Theme.Colors.Raised
		Kit.corner(portrait, 4)
		Kit.label(portrait, {
			Text = string.sub(persona.Name, 1, 1),
			Font = "Display",
			TextSize = "Heading",
			XAlign = "Center",
			Size = UDim2.fromScale(1, 1),
		})
		Kit.label(right, {
			Text = persona.Name,
			Font = "Display",
			TextSize = "Title",
			Color = "Accent",
			Size = UDim2.new(1, -100, 0, 28),
			Position = UDim2.fromOffset(100, 0),
		})
		Kit.label(right, {
			Text = string.upper(persona.Epithet),
			Font = "Mono",
			TextSize = "Label",
			Color = "Dim",
			Size = UDim2.new(1, -100, 0, 18),
			Position = UDim2.fromOffset(100, 30),
		})
		local record = profile and profile.SurrogateWins and profile.SurrogateWins[persona.Id]
		local recordText = "NO WINS RECORDED YET"
		if type(record) == "table" then
			local parts = {}
			for _, tier in { "Casual", "Standard", "Advanced", "Expert" } do
				if (record[tier] or 0) > 0 then
					table.insert(parts, string.format("%s %d", string.upper(tier), record[tier]))
				end
			end
			if #parts > 0 then
				recordText = "WINS  ·  " .. table.concat(parts, "  ·  ")
			end
		end
		Kit.label(right, {
			Text = recordText,
			Font = "Mono",
			TextSize = "Tiny",
			Color = "Dim",
			Size = UDim2.new(1, -100, 0, 14),
			Position = UDim2.fromOffset(100, 52),
		})
		Kit.label(right, {
			Text = persona.Bio .. "\n\n" .. persona.Style,
			Font = "Body",
			TextSize = "Small",
			Wrap = true,
			YAlign = "Top",
			Size = UDim2.new(1, 0, 0, 110),
			Position = UDim2.fromOffset(0, 96),
		})
		Kit.header(right, "DIFFICULTY", 0).Position = UDim2.fromOffset(0, 212)
		local row = Kit.create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 34),
			Position = UDim2.fromOffset(0, 240),
			Parent = right,
		}) :: Frame
		Kit.list(row, "X", 6)
		local descLabel = Kit.label(right, {
			Text = "",
			Font = "Body",
			TextSize = "Small",
			Color = "Dim",
			Wrap = true,
			YAlign = "Top",
			Size = UDim2.new(1, 0, 0, 44),
			Position = UDim2.fromOffset(0, 280),
		})
		local function describe()
			local tier = if self.Difficulty == "Adaptive"
				then Difficulty.Adaptive
				else Difficulty.Tiers[self.Difficulty]
			descLabel.Text = tier and tier.Description or ""
		end
		for i, id in DIFFICULTIES do
			local b = Kit.button(row, {
				Text = string.upper(id),
				Size = UDim2.new(1 / #DIFFICULTIES, -6, 1, 0),
				Style = "Ghost",
				LayoutOrder = i,
				TextSize = "Tiny",
				Sound = "Tab",
				OnClick = function()
					self.Difficulty = id
					detail()
				end,
			})
			b:SetAttribute("Active", self.Difficulty == id)
		end
		describe()
		Kit.button(right, {
			Text = "BEGIN TRIAL",
			Style = "Primary",
			Size = UDim2.new(1, 0, 0, 44),
			Position = UDim2.new(0, 0, 1, -44),
			OnClick = function()
				if request(self, "Solo.Start", self.Surrogate, self.Difficulty) then
					self.UI:close("Play")
				end
			end,
		})
	end
	for i, persona in list do
		local locked = persona.Secret and not unlocked
		local b = Kit.button(left, {
			Text = if locked then "SURROGATE ??" else persona.Name .. "  ·  " .. string.upper(persona.Epithet),
			Size = UDim2.new(1, 0, 0, 52),
			LayoutOrder = i,
			Style = "Default",
			Tooltip = if locked then "Defeat every surrogate on Expert to request this file." else persona.Style,
			OnClick = function()
				if locked then
					Kit.sound("Deny")
					return
				end
				self.Surrogate = persona.Id
				detail()
			end,
		})
		if locked then
			Kit.setEnabled(b, false, "Defeat every surrogate on Expert to request this file.")
		end
	end
	detail()
end

---------------------------------------------------------------------------
-- Practice (sandbox)
---------------------------------------------------------------------------

function Play:practiceTab()
	local body = self.Window.Body
	local left =
		Kit.create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.6, -8, 1, -52), Parent = body }) :: Frame
	local editor = RulesEditor.new(left, self.SandboxRules, function(value)
		self.SandboxRules = value
	end, false)
	self.SandboxRules = editor:value()
	local right =
		Kit.panel(body, { Size = UDim2.new(0.4, -8, 1, -52), Position = UDim2.new(0.6, 8, 0, 0), Color = "PanelAlt" })
	Kit.padding(right, 12, 14)
	Kit.list(right, "Y", 6)
	Kit.header(right, "OPPONENTS (UP TO 3)", 1)
	local function redraw()
		self:show("Practice")
	end
	for i, bot in self.SandboxBots do
		local rowFrame = Kit.create(
			"Frame",
			{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 1 + i, Parent = right }
		) :: Frame
		local persona = Personalities.get(bot.Personality)
		Kit.button(rowFrame, {
			Text = persona.Name,
			Size = UDim2.new(0.45, -4, 1, 0),
			TextSize = "Tiny",
			Tooltip = "Change surrogate",
			OnClick = function()
				local all = Personalities.selectable(false)
				local index = 1
				for j, p in all do
					if p.Id == bot.Personality then
						index = j
					end
				end
				bot.Personality = all[(index % #all) + 1].Id
				redraw()
			end,
		})
		Kit.button(rowFrame, {
			Text = string.upper(bot.Difficulty),
			Size = UDim2.new(0.4, -4, 1, 0),
			Position = UDim2.fromScale(0.45, 0),
			TextSize = "Tiny",
			Tooltip = "Change difficulty",
			OnClick = function()
				local index = table.find(DIFFICULTIES, bot.Difficulty) or 1
				bot.Difficulty = DIFFICULTIES[(index % #DIFFICULTIES) + 1]
				redraw()
			end,
		})
		Kit.button(rowFrame, {
			Text = "X",
			Size = UDim2.new(0.15, 0, 1, 0),
			Position = UDim2.fromScale(0.85, 0),
			Style = "Danger",
			Tooltip = "Remove",
			OnClick = function()
				if #self.SandboxBots > 1 then
					table.remove(self.SandboxBots, i)
					redraw()
				end
			end,
		})
	end
	if #self.SandboxBots < 3 then
		Kit.button(right, {
			Text = "+ ADD SURROGATE",
			Size = UDim2.new(1, 0, 0, 34),
			Style = "Ghost",
			LayoutOrder = 10,
			OnClick = function()
				table.insert(self.SandboxBots, { Personality = "Volta", Difficulty = "Standard" })
				redraw()
			end,
		})
	end
	Kit.label(right, {
		Text = "Sandbox Trials earn reduced XP and never count toward directives, Standing or records.",
		Font = "Body",
		TextSize = "Tiny",
		Color = "Dim",
		Wrap = true,
		AutoY = true,
		LayoutOrder = 11,
		Size = UDim2.new(1, 0, 0, 0),
	})
	Kit.button(body, {
		Text = "BEGIN SANDBOX TRIAL",
		Style = "Primary",
		Size = UDim2.new(1, 0, 0, 44),
		Position = UDim2.new(0, 0, 1, -44),
		OnClick = function()
			local custom = table.clone(self.SandboxRules or {})
			custom.Bots = self.SandboxBots
			if request(self, "Sandbox.Start", custom) then
				self.UI:close("Play")
			end
		end,
	})
end

---------------------------------------------------------------------------
-- Training
---------------------------------------------------------------------------

function Play:trainingTab()
	local body = self.Window.Body
	local scroll = Kit.scroll(body, { Padding = 8 })
	local profile = self.C.ProfileController:get()
	local done = profile and profile.Tutorial or {}
	local lessons = { Tutorials.Basic }
	for _, seminar in Tutorials.Seminars do
		table.insert(lessons, seminar)
	end
	for i, lesson in lessons do
		local card = Kit.panel(scroll, { Size = UDim2.new(1, -8, 0, 74), LayoutOrder = i, Color = "PanelAlt" })
		Kit.padding(card, 10, 14)
		local complete = done[lesson.Id] == true
		Kit.label(card, {
			Text = lesson.Name .. (if complete then "  ·  COMPLETE" else ""),
			Font = "Display",
			TextSize = "Body",
			Color = if complete then "Good" else "Accent",
			Size = UDim2.new(1, -170, 0, 22),
		})
		Kit.label(card, {
			Text = lesson.Description or "",
			Font = "Body",
			TextSize = "Small",
			Color = "Dim",
			Wrap = true,
			Size = UDim2.new(1, -170, 0, 32),
			Position = UDim2.fromOffset(0, 24),
			YAlign = "Top",
		})
		Kit.button(card, {
			Text = if complete then "REPLAY" else "BEGIN",
			Style = if i == 1 and not complete then "Primary" else "Default",
			Size = UDim2.fromOffset(150, 40),
			Position = UDim2.new(1, 0, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			OnClick = function()
				if self.C.TutorialController:start(lesson.Id) then
					self.UI:close("Play")
				end
			end,
		})
	end
end

---------------------------------------------------------------------------
-- Watch
---------------------------------------------------------------------------

function Play:watchTab()
	local body = self.Window.Body
	local status = Kit.label(body, {
		Text = "Looking for live Trials...",
		Font = "Mono",
		TextSize = "Small",
		Color = "Dim",
		Size = UDim2.new(1, -140, 0, 30),
	})
	Kit.button(body, {
		Text = "REFRESH",
		Size = UDim2.fromOffset(130, 30),
		Position = UDim2.new(1, 0, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		Style = "Ghost",
		OnClick = function()
			self:show("Watch")
		end,
	})
	local holder = Kit.create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -40),
		Position = UDim2.fromOffset(0, 40),
		Parent = body,
	}) :: Frame
	local scroll = Kit.scroll(holder, { Padding = 6 })
	task.spawn(function()
		local list = self.C.SpectatorController:list()
		if self.Tab ~= "Watch" then
			return
		end
		status.Text = if #list == 0
			then "No live Trials right now. Check back soon."
			else string.format("%d LIVE TRIAL%s", #list, #list == 1 and "" or "S")
		for i, entry in list do
			local card = Kit.panel(scroll, { Size = UDim2.new(1, -8, 0, 60), LayoutOrder = i, Color = "PanelAlt" })
			Kit.padding(card, 8, 14)
			local env = Environments.get(entry.Environment)
			Kit.label(card, {
				Text = table.concat(entry.Names or {}, "  VS  "),
				Font = "Bold",
				TextSize = "Body",
				Size = UDim2.new(1, -160, 0, 20),
			})
			Kit.label(card, {
				Text = string.format(
					"%s  ·  TRIAL %d  ·  %s  ·  %s  ·  %d WATCHING%s",
					entry.Mode or "",
					entry.Trial or 1,
					entry.Score or "",
					env and env.Name or "",
					entry.Spectators or 0,
					if entry.Competitive then "  ·  DELAYED" else ""
				),
				Font = "Mono",
				TextSize = "Tiny",
				Color = "Dim",
				Size = UDim2.new(1, -160, 0, 16),
				Position = UDim2.fromOffset(0, 24),
			})
			Kit.button(card, {
				Text = "WATCH",
				Size = UDim2.fromOffset(130, 36),
				Position = UDim2.new(1, 0, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				OnClick = function()
					self.C.SpectatorController:watch(entry.MatchId)
				end,
			})
		end
	end)
end

---------------------------------------------------------------------------

function Play:Open(args)
	self.Window:open()
	local tab = args and args.Tab or self.Tab or "Queue"
	if args and args.Surrogate then
		self.Surrogate = args.Surrogate
		tab = "Solo"
	end
	if self.Window.select then
		self.Window.select(tab)
	end
end

function Play:Close()
	self.Window:close()
end

return Play

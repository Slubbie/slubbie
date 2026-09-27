-- RECORD: your file. Lifetime statistics, achievements (hidden ones stay
-- hidden until earned), recent match history and the global boards.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Achievements = require(ReplicatedStorage.Variance.Data.Achievements)
local Environments = require(ReplicatedStorage.Variance.Data.Environments)
local Instruments = require(ReplicatedStorage.Variance.Core.Instruments)
local Modes = require(ReplicatedStorage.Variance.Core.Modes)
local Format = require(ReplicatedStorage.Variance.Util.Format)
local Kit = require(script.Parent.Parent.Kit)
local Window = require(script.Parent.Parent.Window)

local Record = {}
Record.__index = Record

local TABS = {
	{ Id = "Stats", Label = "STATISTICS" },
	{ Id = "Achievements", Label = "ACHIEVEMENTS" },
	{ Id = "History", Label = "HISTORY" },
	{ Id = "Boards", Label = "BOARDS" },
}

local STATS = {
	{ "Matches", "TRIALS PLAYED" },
	{ "Wins", "TRIALS WON" },
	{ "BestStreak", "BEST WIN STREAK" },
	{ "TrialsWon", "ROUNDS WON" },
	{ "Shots", "SHOTS FIRED" },
	{ "SelfShots", "SHOTS AT SELF" },
	{ "SelfSurvived", "SELF-SHOTS SURVIVED" },
	{ "RiskySurvived", "RISKY SURVIVALS" },
	{ "Reads", "CORRECT READS" },
	{ "DamageDealt", "DAMAGE DEALT" },
	{ "DamageTaken", "DAMAGE TAKEN" },
	{ "Healed", "INTEGRITY RESTORED" },
	{ "Instruments", "INSTRUMENTS USED" },
	{ "ClutchWins", "WINS AT 1 INTEGRITY" },
	{ "SuddenDeathWins", "SUDDEN DEATH WINS" },
	{ "PvPWins", "WINS VS SUBJECTS" },
	{ "SoloWins", "WINS VS SURROGATES" },
	{ "EnduranceBest", "BEST ENDURANCE STAGE" },
	{ "TournamentsWon", "TOURNAMENTS WON" },
	{ "Forfeits", "FORFEITS" },
}

function Record.new(ui, controllers)
	local self = setmetatable({}, Record)
	self.UI = ui
	self.C = controllers
	self.Main = true
	self.Window = Window.new(ui, {
		Name = "Record",
		Title = "RECORD",
		Subtitle = "",
		Width = 1000,
		Height = 640,
		Tabs = TABS,
		OnTab = function(id)
			self:show(id)
		end,
	})
	self.Frame = self.Window.Frame
	return self
end

function Record:show(tab: string)
	self.Tab = tab
	local body = self.Window.Body
	Window.clear(body)
	local profile = self.C.ProfileController:get()
	if profile == nil then
		Kit.label(body, { Text = "Your file is still loading.", Font = "Mono", TextSize = "Small", Color = "Dim" })
		return
	end
	self.Window:setSubtitle(
		string.format(
			"CLEARANCE %d  ·  %s  ·  %s PLAYED",
			profile.Level,
			profile.Title or "",
			Format.clock((profile.Stats and profile.Stats.PlayTime) or 0)
		)
	)
	if tab == "Stats" then
		self:stats(body, profile)
	elseif tab == "Achievements" then
		self:achievements(body, profile)
	elseif tab == "History" then
		self:history(body)
	elseif tab == "Boards" then
		self:boards(body)
	end
end

function Record:stats(body: Instance, profile)
	local scroll = Kit.create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = body,
	}) :: ScrollingFrame
	Kit.grid(scroll, UDim2.fromOffset(180, 64), 8)
	local stats = profile.Stats or {}
	local order = 0
	local function tile(label: string, value: string)
		order += 1
		local card = Kit.panel(scroll, { LayoutOrder = order, Color = "PanelAlt" })
		Kit.padding(card, 8, 10)
		Kit.label(
			card,
			{ Text = value, Font = "Display", TextSize = "Title", Color = "Accent", Size = UDim2.new(1, 0, 0, 28) }
		)
		Kit.label(card, {
			Text = label,
			Font = "Mono",
			TextSize = "Tiny",
			Color = "Dim",
			Size = UDim2.new(1, 0, 0, 14),
			Position = UDim2.new(0, 0, 1, -14),
		})
	end
	for _, entry in STATS do
		tile(entry[2], Format.thousands(stats[entry[1]] or 0))
	end
	tile("WIN RATE", Format.percent((stats.Wins or 0) / math.max(stats.Matches or 0, 1)))
	tile("SELF-SHOT SURVIVAL", Format.percent((stats.SelfSurvived or 0) / math.max(stats.SelfShots or 0, 1)))
	tile("BOLDEST SELF-SHOT", Format.percent(stats.BestRisk or 0))
	for _, tier in { "Casual", "Standard", "Advanced", "Expert", "Adaptive" } do
		tile("WINS :: " .. string.upper(tier), tostring(profile.AIWins and profile.AIWins[tier] or 0))
	end
	local uses = {}
	for id, n in profile.InstrumentUse or {} do
		if n > 0 then
			table.insert(uses, { id, n })
		end
	end
	table.sort(uses, function(a, b)
		return a[2] > b[2]
	end)
	for i = 1, math.min(4, #uses) do
		local def = Instruments.get(uses[i][1])
		tile("USED :: " .. (def and def.Name or uses[i][1]), tostring(uses[i][2]))
	end
	for id, n in profile.EnvironmentWins or {} do
		local env = Environments.get(id)
		tile("WINS IN " .. string.upper(env and env.Name or id), tostring(n))
	end
end

function Record:achievements(body: Instance, profile)
	local scroll = Kit.scroll(body, { Padding = 6 })
	local earned = profile.Achievements or {}
	local list = table.clone(Achievements.List)
	table.sort(list, function(a, b)
		local ae, be = earned[a.Id] ~= nil, earned[b.Id] ~= nil
		if ae ~= be then
			return ae
		end
		return a.Name < b.Name
	end)
	local count = 0
	for _ in earned do
		count += 1
	end
	Kit.header(scroll, string.format("%d / %d EARNED", count, #list), 0)
	for i, a in list do
		local has = earned[a.Id] ~= nil
		local card = Kit.panel(
			scroll,
			{ Size = UDim2.new(1, -8, 0, 56), LayoutOrder = i, Color = if has then "PanelAlt" else "Panel" }
		)
		Kit.padding(card, 8, 12)
		local name = if has or not a.Hidden then a.Name else "CLASSIFIED"
		local desc = if has or not a.Hidden then a.Description else "A hidden achievement. Keep playing."
		Kit.label(card, {
			Text = name,
			Font = "Bold",
			TextSize = "Small",
			Color = if has then "Good" else "Text",
			Size = UDim2.new(1, -150, 0, 18),
		})
		Kit.label(card, {
			Text = desc,
			Font = "Body",
			TextSize = "Tiny",
			Color = "Dim",
			Size = UDim2.new(1, -150, 0, 18),
			Position = UDim2.fromOffset(0, 20),
		})
		local right = if has then "EARNED" else ""
		if not has and a.Progress and not a.Hidden then
			local ok, value, goal = pcall(a.Progress, profile)
			if ok and type(value) == "number" and type(goal) == "number" then
				right = string.format("%d / %d", math.min(value, goal), goal)
			end
		end
		if (a.Marks or 0) > 0 and not has then
			right ..= string.format("%s+%d MARKS", if right ~= "" then "  ·  " else "", a.Marks)
		end
		Kit.label(card, {
			Text = right,
			Font = "Mono",
			TextSize = "Tiny",
			Color = if has then "Good" else "Dim",
			XAlign = "Right",
			Size = UDim2.new(0, 150, 1, 0),
			Position = UDim2.new(1, -150, 0, 0),
		})
	end
end

function Record:history(body: Instance)
	local status = Kit.label(
		body,
		{ Text = "Retrieving...", Font = "Mono", TextSize = "Small", Color = "Dim", Size = UDim2.new(1, 0, 0, 20) }
	)
	task.spawn(function()
		local ok, entries = self.C.NetworkClient:request("History.Get")
		if self.Tab ~= "History" then
			return
		end
		if not ok or type(entries) ~= "table" then
			status.Text = "Records unavailable right now."
			return
		end
		status:Destroy()
		local scroll = Kit.scroll(body, { Padding = 4 })
		if #entries == 0 then
			Kit.label(
				scroll,
				{ Text = "No Trials on file yet.", Font = "Mono", TextSize = "Small", Color = "Dim", LayoutOrder = 1 }
			)
		end
		for i = #entries, 1, -1 do
			local e = entries[i]
			local rowFrame = Kit.panel(
				scroll,
				{ Size = UDim2.new(1, -8, 0, 40), LayoutOrder = #entries - i + 1, Color = "PanelAlt" }
			)
			Kit.padding(rowFrame, 6, 12)
			local mode = Modes.get(e.Mode)
			local env = Environments.get(e.Env)
			Kit.label(rowFrame, {
				Text = e.Result or "?",
				Font = "Bold",
				TextSize = "Small",
				Color = if e.Result == "WIN" then "Good" else "Bad",
				Size = UDim2.fromOffset(80, 28),
			})
			Kit.label(rowFrame, {
				Text = string.format(
					"VS %s  ·  %s  ·  %s%s",
					string.upper(e.Opponent or "?"),
					e.Score or "",
					mode and mode.Name or (e.Mode or ""),
					if e.Difficulty then "  ·  " .. string.upper(e.Difficulty) else ""
				),
				Font = "Mono",
				TextSize = "Tiny",
				Size = UDim2.new(1, -330, 1, 0),
				Position = UDim2.fromOffset(84, 0),
			})
			Kit.label(rowFrame, {
				Text = string.format(
					"%s%s  ·  %s",
					if e.Delta then Format.signed(e.Delta) .. "  ·  " else "",
					env and string.upper(env.Name) or "",
					Format.ago(os.time() - (e.Time or os.time()))
				),
				Font = "Mono",
				TextSize = "Tiny",
				Color = "Dim",
				XAlign = "Right",
				Size = UDim2.fromOffset(240, 28),
				Position = UDim2.new(1, -240, 0, 0),
			})
		end
	end)
end

function Record:boards(body: Instance)
	for i, board in { { Id = "Standing", Title = "STANDING" }, { Id = "Wins", Title = "MOST TRIALS WON" } } do
		local panel = Kit.panel(body, {
			Size = UDim2.new(0.5, -8, 1, 0),
			Position = UDim2.new((i - 1) * 0.5, (i - 1) * 8, 0, 0),
			Color = "PanelAlt",
		})
		Kit.padding(panel, 10, 14)
		Kit.header(panel, board.Title, 0)
		local list = Kit.create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, -30),
			Position = UDim2.fromOffset(0, 30),
			Parent = panel,
		}) :: Frame
		local scroll = Kit.scroll(list, { Padding = 2 })
		task.spawn(function()
			local ok, result = self.C.NetworkClient:request("Leaderboard.Get", board.Id)
			if not ok or type(result) ~= "table" then
				Kit.label(
					scroll,
					{ Text = "Board unavailable.", Font = "Mono", TextSize = "Small", Color = "Dim", LayoutOrder = 1 }
				)
				return
			end
			if #(result.Entries or {}) == 0 then
				Kit.label(scroll, {
					Text = "No entries yet this season.",
					Font = "Mono",
					TextSize = "Small",
					Color = "Dim",
					LayoutOrder = 1,
				})
			end
			local me = game:GetService("Players").LocalPlayer.UserId
			for _, entry in result.Entries or {} do
				local rowFrame = Kit.create("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, -8, 0, 22),
					LayoutOrder = entry.Rank,
					Parent = scroll,
				}) :: Frame
				local mine = entry.UserId == me
				Kit.label(rowFrame, {
					Text = string.format("%2d  %s", entry.Rank, string.upper(entry.Name or "?")),
					Font = "Mono",
					TextSize = "Small",
					Color = if mine then "Accent" else "Text",
					Size = UDim2.new(0.75, 0, 1, 0),
				})
				Kit.label(rowFrame, {
					Text = Format.thousands(entry.Value or 0),
					Font = "Mono",
					TextSize = "Small",
					Color = if mine then "Accent" else "Dim",
					XAlign = "Right",
					Size = UDim2.new(0.25, 0, 1, 0),
					Position = UDim2.fromScale(0.75, 0),
				})
			end
		end)
	end
end

function Record:Open(args)
	self.Window:open()
	if self.Window.select then
		self.Window.select(args and args.Tab or self.Tab or "Stats")
	end
end

function Record:Close()
	self.Window:close()
end

return Record

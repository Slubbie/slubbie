-- STANDING: ranked play, explained in full.
-- Shows your rating and division, placement progress, the season, your recent
-- changes, the whole division ladder, the exact rules (Elo with a K factor,
-- abandon penalties and lockouts) and the queue. Rewards are cosmetic only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rating = require(ReplicatedStorage.Variance.Core.Rating)
local Format = require(ReplicatedStorage.Variance.Util.Format)
local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Window = require(script.Parent.Parent.Window)

local Ranked = {}
Ranked.__index = Ranked

function Ranked.new(ui, controllers)
	local self = setmetatable({}, Ranked)
	self.UI = ui
	self.C = controllers
	self.Main = true
	self.Window = Window.new(ui, { Name = "Ranked", Title = "STANDING", Subtitle = "", Width = 980, Height = 620 })
	self.Frame = self.Window.Frame
	controllers.ProfileController.Changed:Connect(function()
		if self.Window.Visible then
			self:render()
		end
	end)
	return self
end

local function duration(seconds: number): string
	if seconds >= 86400 then
		return string.format("%dd %dh", seconds // 86400, (seconds % 86400) // 3600)
	elseif seconds >= 3600 then
		return string.format("%dh %dm", seconds // 3600, (seconds % 3600) // 60)
	end
	return Format.clock(seconds)
end

function Ranked:render()
	local body = self.Window.Body
	Window.clear(body)
	local profile = self.C.ProfileController:get()
	local info = profile and profile.Ranked
	if info == nil then
		Kit.label(body, { Text = "Your file is still loading.", Font = "Mono", TextSize = "Small", Color = "Dim" })
		return
	end
	self.Window:setSubtitle(string.format("%s  ·  ENDS IN %s", info.Season.Name or "", duration(info.Season.EndsIn or 0)))

	-- Division card.
	local card = Kit.panel(body, { Size = UDim2.new(0.4, -8, 0, 250), Color = "PanelAlt" })
	Kit.padding(card, 16, 18)
	local division = info.Division or Rating.division(info.Rating or 1000)
	local color = Color3.fromRGB(division.Color[1], division.Color[2], division.Color[3])
	local placed = info.Placed
	local title = Kit.label(card, { Text = if placed then division.Label else "UNPLACED", Font = "Display", TextSize = "Heading", Size = UDim2.new(1, 0, 0, 40) })
	title.TextColor3 = if placed then color else Theme.Colors.Dim
	Kit.label(card, {
		Text = if placed then string.format("STANDING %d", info.Rating) else string.format("%d PLACEMENT TRIAL%s LEFT", info.PlacementsLeft, info.PlacementsLeft == 1 and "" or "S"),
		Font = "Mono",
		TextSize = "Body",
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.fromOffset(0, 44),
	})
	Kit.bar(card, { Size = UDim2.new(1, 0, 0, 6), Position = UDim2.fromOffset(0, 76), Value = if placed then division.Progress else (Rating.Placements - info.PlacementsLeft) / Rating.Placements })
	local stats = {
		string.format("SEASON TRIALS %d  ·  ALL-TIME %d", info.SeasonGames or 0, info.Games or 0),
		string.format("WINS %d  ·  WIN RATE %s", info.Wins or 0, Format.percent((info.Wins or 0) / math.max(info.Games or 0, 1))),
		string.format("SEASON PEAK %d  ·  ALL-TIME PEAK %d", info.SeasonPeak or 0, info.Peak or 0),
		string.format("K FACTOR %d  ·  ABANDON STRIKES %d", info.K or 32, info.Strikes or 0),
	}
	Kit.label(card, { Text = table.concat(stats, "\n"), Font = "Mono", TextSize = "Tiny", Color = "Dim", YAlign = "Top", Size = UDim2.new(1, 0, 0, 80), Position = UDim2.fromOffset(0, 92) })
	local locked = (info.LockoutRemaining or 0) > 0
	local queue = Kit.button(card, {
		Text = if locked then "LOCKED :: " .. duration(info.LockoutRemaining) else "ENTER RANKED QUEUE",
		Style = "Danger",
		Size = UDim2.new(1, 0, 0, 44),
		Position = UDim2.new(0, 0, 1, -44),
		OnClick = function()
			local ok, err = self.C.NetworkClient:request("Queue.Join", "Ranked")
			if ok then
				self.UI:close("Ranked")
			else
				self.UI:toast("RANKED", tostring(err), "Warn")
			end
		end,
	})
	if locked then
		Kit.setEnabled(queue, false, "Leaving an active ranked Trial locks the queue for a while. Clean matches clear strikes.")
	end

	-- Recent changes (sparkline + list).
	local history = Kit.panel(body, { Size = UDim2.new(0.6, -8, 0, 250), Position = UDim2.new(0.4, 8, 0, 0), Color = "PanelAlt" })
	Kit.padding(history, 12, 14)
	Kit.header(history, "RECENT CHANGES", 0)
	local chart = Kit.create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 120), Position = UDim2.fromOffset(0, 30), Parent = history }) :: Frame
	local entries = info.History or {}
	local first = math.max(1, #entries - 19)
	local lo, hi = math.huge, -math.huge
	for i = first, #entries do
		lo = math.min(lo, entries[i].Rating)
		hi = math.max(hi, entries[i].Rating)
	end
	local count = #entries - first + 1
	if #entries > 0 then
		local span = math.max(hi - lo, 20)
		for i = first, #entries do
			local e = entries[i]
			local x = (i - first) / math.max(count - 1, 1)
			local y = 1 - (e.Rating - lo) / span
			local dot = Kit.create("Frame", { BorderSizePixel = 0, Size = UDim2.fromOffset(8, 8), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, 0.1 + y * 0.8), Parent = chart }) :: Frame
			Theme.bind(dot, "BackgroundColor3", if e.Delta >= 0 then "Good" else "Bad")
			Kit.corner(dot, 4)
			Kit.tooltip(dot, string.format("%d (%s)", e.Rating, Format.signed(e.Delta)))
		end
	else
		Kit.label(chart, { Text = "No ranked Trials this season yet.", Font = "Mono", TextSize = "Small", Color = "Dim", XAlign = "Center", Size = UDim2.fromScale(1, 1) })
	end
	local recent = {}
	for i = #entries, math.max(1, #entries - 4), -1 do
		table.insert(recent, string.format("%s  %d", Format.signed(entries[i].Delta), entries[i].Rating))
	end
	Kit.label(history, { Text = table.concat(recent, "   ·   "), Font = "Mono", TextSize = "Tiny", Color = "Dim", Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 1, -16) })

	-- Ladder and rules.
	local ladder = Kit.panel(body, { Size = UDim2.new(0.4, -8, 1, -262), Position = UDim2.fromOffset(0, 262), Color = "PanelAlt" })
	Kit.padding(ladder, 12, 14)
	Kit.list(ladder, "Y", 4)
	Kit.header(ladder, "DIVISIONS", 0)
	for i = #Rating.Divisions, 1, -1 do
		local div = Rating.Divisions[i]
		local label = Kit.label(ladder, {
			Text = string.format("%s  ·  %d+%s", div.Name, div.Min, if i < #Rating.Divisions then "  ·  III / II / I" else ""),
			Font = "Mono",
			TextSize = "Small",
			LayoutOrder = #Rating.Divisions - i + 1,
		})
		label.TextColor3 = Color3.fromRGB(div.Color[1], div.Color[2], div.Color[3])
	end
	local rules = Kit.panel(body, { Size = UDim2.new(0.6, -8, 1, -262), Position = UDim2.new(0.4, 8, 0, 262), Color = "PanelAlt" })
	Kit.padding(rules, 12, 14)
	Kit.header(rules, "HOW STANDING WORKS", 0)
	Kit.label(rules, {
		Text = table.concat({
			"Standard rules, locked. After each Trial your Standing moves by K × (result − expected), where expected comes from the gap between your Standing and your opponent's.",
			string.format("K is 48 for your first %d Trials, 32 until 30, then 24. Every win gains at least 1; every loss costs at least 1.", Rating.Placements),
			"Leaving an active ranked Trial counts as a loss, adds an abandon strike and locks the queue (5 min, 15 min, 1 h, 4 h). Clean Trials clear strikes. Reconnecting in time refunds it.",
			"The same opponent can only move your Standing a few times a day. Seasons end with a soft reset halfway toward 1000; your peak division earns its season cosmetic.",
		}, "\n\n"),
		Font = "Body",
		TextSize = "Tiny",
		Color = "Dim",
		Wrap = true,
		YAlign = "Top",
		Size = UDim2.new(1, 0, 1, -28),
		Position = UDim2.fromOffset(0, 28),
	})
end

function Ranked:Open()
	self.Window:open()
	self:render()
end

function Ranked:Close()
	self.Window:close()
end

return Ranked

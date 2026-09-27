-- Results after a Trial: the outcome, every subject's numbers, the key moments
-- of the match, what you earned (XP by line, Marks, clearance progress,
-- Standing change, directives, achievements, unlocks) and the rematch vote.
-- The table keeps turning behind it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Instruments = require(ReplicatedStorage.Variance.Core.Instruments)
local Cosmetics = require(ReplicatedStorage.Variance.Data.Cosmetics)
local Format = require(ReplicatedStorage.Variance.Util.Format)
local Kit = require(script.Parent.Parent.Kit)
local Motion = require(script.Parent.Parent.Motion)
local Theme = require(script.Parent.Parent.Theme)

local PostMatch = {}
PostMatch.__index = PostMatch

function PostMatch.new(ui, controllers)
	local self = setmetatable({}, PostMatch)
	self.UI = ui
	self.C = controllers
	self.Main = true
	self.Visible = false
	local root = Kit.create("Frame", {
		Name = "PostMatch",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = ui.Screens,
	}) :: Frame
	self.Frame = root
	local shade = Kit.create("Frame", {
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		Size = UDim2.fromScale(1, 1),
		Parent = root,
	}) :: Frame
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.55, 0.3),
		NumberSequenceKeypoint.new(1, 0.9),
	})
	gradient.Parent = shade

	self.Title = Kit.label(root, {
		Text = "",
		Font = "Display",
		TextSize = "Banner",
		Size = UDim2.new(0.6, 0, 0, 60),
		Position = UDim2.fromOffset(40, 36),
	})
	self.Subtitle = Kit.label(root, {
		Text = "",
		Font = "Mono",
		TextSize = "Body",
		Color = "Dim",
		Size = UDim2.new(0.6, 0, 0, 22),
		Position = UDim2.fromOffset(40, 98),
	})

	-- Left column: subjects and key moments.
	local left = Kit.scroll(
		root,
		{ Name = "Left", Size = UDim2.new(0.52, -40, 1, -230), Position = UDim2.fromOffset(40, 136), Padding = 10 }
	)
	self.Left = left
	-- Right column: rewards.
	local right = Kit.panel(root, {
		Name = "Rewards",
		Size = UDim2.new(0.4, -40, 1, -230),
		Position = UDim2.new(0.6, 0, 0, 136),
		Color = "Panel",
		Transparency = 0.1,
	})
	Kit.padding(right, 14, 16)
	local rightScroll = Kit.scroll(right, { Padding = 8 })
	self.Right = rightScroll

	-- Footer: rematch and leave.
	local footer = Kit.create("Frame", {
		Name = "Footer",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -80, 0, 52),
		Position = UDim2.new(0, 40, 1, -76),
		Parent = root,
	}) :: Frame
	self.RematchButton = Kit.button(footer, {
		Text = "REMATCH",
		Size = UDim2.fromOffset(220, 48),
		Style = "Primary",
		OnClick = function()
			self:vote(true)
		end,
	})
	self.LeaveButton = Kit.button(footer, {
		Text = "RETURN TO THE INTAKE",
		Size = UDim2.fromOffset(260, 48),
		Position = UDim2.fromOffset(236, 0),
		OnClick = function()
			self:leave()
		end,
	})
	self.RematchStatus = Kit.label(footer, {
		Text = "",
		Font = "Mono",
		TextSize = "Label",
		Color = "Dim",
		Size = UDim2.new(1, -520, 1, 0),
		Position = UDim2.fromOffset(516, 0),
	})

	controllers.MatchClient.Rematch:Connect(function(data)
		self:rematch(data)
	end)
	-- A rematch (or the next Endurance stage) begins at the same table.
	controllers.MatchClient.Began:Connect(function()
		if self.Visible then
			ui:close("PostMatch")
		end
	end)
	return self
end

local function section(parent: Instance, text: string, order: number)
	Kit.header(parent, text, order)
end

local function row(parent: Instance, left: string, right: string, order: number, color: string?)
	local frame = Kit.create(
		"Frame",
		{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = order, Parent = parent }
	) :: Frame
	Kit.label(frame, { Text = left, Font = "Mono", TextSize = "Small", Color = "Dim", Size = UDim2.new(0.65, 0, 1, 0) })
	return Kit.label(frame, {
		Text = right,
		Font = "Mono",
		TextSize = "Small",
		Color = color or "Text",
		XAlign = "Right",
		Size = UDim2.new(0.35, 0, 1, 0),
		Position = UDim2.fromScale(0.65, 0),
	})
end

function PostMatch:Open(data)
	if data == nil then
		return
	end
	self.Data = data
	self.Visible = true
	self.Frame.Visible = true
	-- The table HUD steps aside (a rematch opens it again).
	local hud = self.UI:screen("MatchHUD")
	if hud and hud.Visible then
		hud:Close()
	end
	local report = data.Report or {}
	local you = data.You
	local me = you and report.Subjects and report.Subjects[you]
	local title, color
	if data.Aborted then
		title, color = "EVALUATION ABORTED", "Warn"
	elseif data.Spectating or me == nil then
		local names = {}
		for _, s in report.Subjects or {} do
			if s.Won then
				table.insert(names, string.upper(s.Name))
			end
		end
		title, color = (#names > 0 and table.concat(names, " & ") or "NO ONE") .. " PREVAILS", "Accent"
	elseif me.Forfeited then
		title, color = "YOU FORFEITED", "Bad"
	elseif me.Won then
		title, color = "EVALUATION PASSED", "Good"
	else
		title, color = "EVALUATION FAILED", "Bad"
	end
	self.Title.Text = title
	Theme.bind(self.Title, "TextColor3", color)
	self.Subtitle.Text = string.format(
		"%s  ·  %d TRIAL%s  ·  %s",
		report.ModeName or report.ModeId or "",
		report.Trials or 0,
		(report.Trials or 0) == 1 and "" or "S",
		if report.Reason == "Forfeit" then "ENDED BY FORFEIT" else "DECIDED IN TRIALS"
	)
	self.Title.TextTransparency = 1
	Motion.tween(self.Title, 0.5, { TextTransparency = 0 }, "slide")
	self:renderLeft(report, you)
	self:renderRewards(data)
	local canRematch = data.CanRematch == true and not data.Spectating
	self.RematchButton.Visible = canRematch
	Kit.setEnabled(self.RematchButton, canRematch)
	Kit.setText(self.RematchButton, "REMATCH")
	self.RematchStatus.Text = if canRematch then "Everyone at the table must accept." else ""
	self.LeaveButton.Position = if canRematch then UDim2.fromOffset(236, 0) else UDim2.fromOffset(0, 0)
	self.UI:focus(if canRematch then self.RematchButton else self.LeaveButton)
	self.C.AudioController:play(if me and me.Won then "WinSting" else "LoseSting")
end

function PostMatch:renderLeft(report, you)
	local left = self.Left
	for _, child in left:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	section(left, "SUBJECTS", 1)
	local order = 2
	local ids = {}
	for id in report.Subjects or {} do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		local s = report.Subjects[id]
		local card = Kit.panel(
			left,
			{ Size = UDim2.new(1, -8, 0, 96), LayoutOrder = order, Color = "Panel", Transparency = 0.15 }
		)
		order += 1
		Kit.padding(card, 8, 12)
		local nameText = string.upper(s.Name or "?")
			.. (if id == you then "  (YOU)" else "")
			.. (if s.Won then "  ·  WINNER" else "")
		Kit.label(card, {
			Text = nameText,
			Font = "Bold",
			TextSize = "Body",
			Color = if s.Won then "Good" else "Text",
			Size = UDim2.new(1, 0, 0, 20),
		})
		local fav = s.Favourite and Instruments.get(s.Favourite)
		local lines = {
			string.format(
				"TRIALS WON %d   ·   SHOTS %d   ·   READS %d (%s)",
				s.TrialWins or 0,
				s.Shots or 0,
				s.Reads or 0,
				Format.percent(s.Accuracy or 0)
			),
			string.format(
				"DAMAGE DEALT %d   ·   TAKEN %d   ·   RESTORED %d",
				s.DamageDealt or 0,
				s.DamageTaken or 0,
				s.Healed or 0
			),
			string.format(
				"INSTRUMENTS %d%s%s",
				s.InstrumentCount or 0,
				fav and ("   ·   FAVOURITE " .. fav.Name) or "",
				if (s.BestRisk or 0) > 0 then "   ·   BOLDEST SELF-SHOT " .. Format.percent(s.BestRisk) else ""
			),
		}
		Kit.label(card, {
			Text = table.concat(lines, "\n"),
			Font = "Mono",
			TextSize = "Tiny",
			Color = "Dim",
			Size = UDim2.new(1, 0, 0, 54),
			Position = UDim2.fromOffset(0, 24),
			YAlign = "Top",
			Wrap = true,
		})
	end
	if report.KeyMoments and #report.KeyMoments > 0 then
		section(left, "KEY MOMENTS", order)
		order += 1
		for _, moment in report.KeyMoments do
			local card = Kit.panel(
				left,
				{ Size = UDim2.new(1, -8, 0, 0), LayoutOrder = order, Color = "PanelAlt", Transparency = 0.2 }
			)
			card.AutomaticSize = Enum.AutomaticSize.Y
			order += 1
			Kit.padding(card, 8, 12)
			Kit.list(card, "Y", 2)
			Kit.label(
				card,
				{ Text = moment.Title or "", Font = "Mono", TextSize = "Label", Color = "Accent", LayoutOrder = 1 }
			)
			Kit.label(card, {
				Text = moment.Text or "",
				Font = "Body",
				TextSize = "Small",
				Wrap = true,
				AutoY = true,
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 0, 0),
			})
		end
	end
end

function PostMatch:renderRewards(data)
	local right = self.Right
	for _, child in right:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local rewards = data.Rewards
	local order = 1
	if data.Spectating then
		section(right, "SPECTATOR", order)
		Kit.label(right, {
			Text = "You watched this Trial. Nothing was at stake for you.",
			Font = "Body",
			TextSize = "Small",
			Color = "Dim",
			Wrap = true,
			AutoY = true,
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 0),
		})
		return
	end
	if rewards == nil then
		section(right, "NO REWARDS", order)
		Kit.label(right, {
			Text = if data.Aborted
				then "The Trial was aborted."
				else "Training and sandbox Trials don't award progression.",
			Font = "Body",
			TextSize = "Small",
			Color = "Dim",
			Wrap = true,
			AutoY = true,
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 0),
		})
		return
	end
	section(right, "EXPERIENCE", order)
	order += 1
	local delay = 0.3
	for _, line in rewards.XPLines or {} do
		local value = row(right, string.upper(line.Label or ""), "", order)
		order += 1
		local amount = line.Amount or 0
		task.delay(delay, function()
			self.C.AudioController:play("Tick")
			value.Text = "+" .. Format.thousands(amount)
		end)
		delay += 0.18
	end
	local total = row(right, "TOTAL", "", order, "Accent")
	order += 1
	task.delay(delay, function()
		self.C.AudioController:play("Confirm")
		total.Text = "+" .. Format.thousands(rewards.XP or 0) .. " XP"
	end)
	row(
		right,
		"MARKS",
		"+" .. Format.thousands(rewards.Marks or 0) .. "  (" .. Format.thousands(rewards.MarksTotal or 0) .. ")",
		order
	)
	order += 1
	local levelText = if (rewards.LevelAfter or 1) > (rewards.LevelBefore or 1)
		then string.format("CLEARANCE %d → %d", rewards.LevelBefore, rewards.LevelAfter)
		else string.format("CLEARANCE %d", rewards.LevelAfter or 1)
	row(
		right,
		levelText,
		rewards.Title or "",
		order,
		if (rewards.LevelAfter or 1) > (rewards.LevelBefore or 1) then "Good" else "Text"
	)
	order += 1
	local bar = Kit.bar(right, { Size = UDim2.new(1, 0, 0, 6), LayoutOrder = order, Value = 0 })
	order += 1
	task.delay(delay + 0.2, function()
		Kit.setBar(bar, (rewards.LevelInto or 0) / math.max(rewards.LevelNeed or 1, 1), true)
	end)

	local rating = data.Rating
	if rating then
		section(right, "STANDING", order)
		order += 1
		local delta = rating.Delta or 0
		row(
			right,
			rating.Note and string.upper(rating.Note) or (if rating.Rated == false then "NOT RATED" else "CHANGE"),
			Format.signed(delta),
			order,
			if delta >= 0 then "Good" else "Bad"
		)
		order += 1
		if rating.Rating then
			row(right, "NEW STANDING", tostring(rating.Rating), order)
			order += 1
		end
	end
	if rewards.Challenges and #rewards.Challenges > 0 then
		section(right, "DIRECTIVES", order)
		order += 1
		for _, c in rewards.Challenges do
			row(
				right,
				c.Text or "",
				if c.Done then "COMPLETE" else string.format("%d/%d", c.Progress or 0, c.Goal or 1),
				order,
				if c.Done then "Good" else "Text"
			)
			order += 1
		end
	end
	if rewards.Achievements and #rewards.Achievements > 0 then
		section(right, "ACHIEVEMENTS", order)
		order += 1
		for _, a in rewards.Achievements do
			row(right, string.upper(a.Name or a.Id), if a.Hidden then "HIDDEN" else "", order, "Good")
			order += 1
		end
	end
	local unlocks = {}
	for _, id in rewards.Cosmetics or {} do
		local item = Cosmetics.get(id)
		if item then
			table.insert(unlocks, item.Name)
		end
	end
	for _, file in rewards.Lore or {} do
		table.insert(unlocks, "FILE " .. (file.Id or "") .. " :: " .. (file.Title or ""))
	end
	if #unlocks > 0 then
		section(right, "UNLOCKED", order)
		order += 1
		for _, text in unlocks do
			row(right, text, "", order, "Accent")
			order += 1
		end
	end
end

function PostMatch:rematch(data)
	if not self.Visible or data == nil then
		return
	end
	local accepted, total = 0, 0
	for _, vote in data.Votes or {} do
		total += 1
		if vote == true then
			accepted += 1
		end
	end
	if data.Closed then
		self.RematchStatus.Text = "Rematch declined."
		Kit.setEnabled(self.RematchButton, false, "Rematch closed.")
		return
	end
	local needed = data.Needed or total
	self.RematchStatus.Text = string.format(
		"REMATCH  %d/%d ACCEPTED%s",
		accepted,
		needed,
		if data.EndsIn then "  ·  " .. tostring(data.EndsIn) .. "s" else ""
	)
	local you = self.Data and self.Data.You
	if you and data.Votes and data.Votes[tostring(you)] then
		Kit.setText(self.RematchButton, "WAITING...")
		Kit.setEnabled(self.RematchButton, false, "You have accepted.")
	end
end

function PostMatch:vote(accept: boolean)
	task.spawn(function()
		local ok, err = self.C.NetworkClient:request("Match.Rematch", accept)
		if not ok and err then
			self.UI:toast("REMATCH", tostring(err), "Warn")
		end
	end)
end

function PostMatch:leave()
	local data = self.Data
	task.spawn(function()
		if data and data.Spectating then
			self.C.NetworkClient:request("Spectate.Stop")
		else
			self.C.NetworkClient:request("Match.Leave")
		end
	end)
	self.UI:close("PostMatch")
end

function PostMatch:Close()
	self.Visible = false
	self.Frame.Visible = false
end

return PostMatch

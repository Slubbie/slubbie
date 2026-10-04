-- Everything that appears over the game: notification toasts, banners, the
-- start countdown, level-up and unlock cards, the course preview, the results
-- screen, NPC dialogue, confirmations, and the panels that close out Spire
-- floors, relays, races and Dreamline runs.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Abilities = require(ReplicatedStorage.Shared.Config.Abilities)
local Courses = require(ReplicatedStorage.Shared.Config.Courses)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Medals = require(ReplicatedStorage.Shared.Logic.Medals)
local MoveStats = require(ReplicatedStorage.Shared.Logic.MoveStats)
local Net = require(ReplicatedStorage.Shared.Net)
local NPCs = require(ReplicatedStorage.Shared.Config.NPCs)
local Schedule = require(ReplicatedStorage.Shared.Logic.Schedule)

local Bus = require(script.Parent.Parent.Core.Bus)
local Input = require(script.Parent.Parent.Core.Input)
local State = require(script.Parent.Parent.Core.State)
local Controller = require(script.Parent.Parent.Movement.Controller)
local CameraController = require(script.Parent.Parent.Camera.CameraController)
local Sfx = require(script.Parent.Parent.Audio.Sfx)
local CourseClient = require(script.Parent.Parent.Gameplay.CourseClient)
local Modes = require(script.Parent.Parent.Gameplay.Modes)
local QuestClient = require(script.Parent.Parent.Gameplay.QuestClient)
local Kit = require(script.Parent.Kit)
local Root = require(script.Parent.Root)

local C = Kit.Colors
local Overlay = {}

local gui: ScreenGui
local toastStack: Frame
local banner: TextLabel
local bannerSub: TextLabel
local countdownLabel: TextLabel
local modal: Frame? = nil

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Modals ---------------------------------------------------------------------------------------------

function Overlay.CloseModal()
	if modal then
		modal:Destroy()
		modal = nil
	end
	CameraController.MenuOpen = false
	Controller.SetLock("Modal", false)
	GuiService.SelectedObject = nil
end

-- A centred modal card; returns its content frame.
local function openModal(width: number, title: string, subtitle: string?, color: Color3?): Frame
	Overlay.CloseModal()
	local shade = Kit.new("Frame", {
		Name = "Modal",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Parent = gui,
	})
	modal = shade
	local card = Kit.Panel(shade, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, width, 0.86, 0),
		BackgroundTransparency = 0.04,
	})
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(width, 720)
	constraint.Parent = card
	Kit.Padding(card, 18)
	local header = Kit.Label(
		card,
		title,
		24,
		{ Font = Kit.Fonts.Black, TextColor3 = color or C.Accent, Size = UDim2.new(1, -40, 0, 30) }
	)
	header.TextTruncate = Enum.TextTruncate.AtEnd
	if subtitle then
		Kit.Label(
			card,
			subtitle,
			14,
			{ Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 20), TextColor3 = C.Muted }
		)
	end
	local close = Kit.Button(
		card,
		"✕",
		Overlay.CloseModal,
		"Ghost",
		{ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(36, 36) }
	)
	close.Name = "Close"
	local body = Kit.Scroll(card, { Position = UDim2.fromOffset(0, 58), Size = UDim2.new(1, 0, 1, -58) })
	Kit.List(body, false, 10)
	Kit.Padding(body, 2, 4)
	CameraController.MenuOpen = true
	Controller.SetLock("Modal", true)
	if Input.Device == "Gamepad" then
		task.defer(function()
			GuiService.SelectedObject = close
		end)
	end
	return body
end

-- Toasts and banners -----------------------------------------------------------------------------------

local ICONS = {
	Reward = "✚",
	Quest = "✔",
	Objective = "◆",
	Achievement = "🏆",
	Mastery = "▲",
	Discovery = "◎",
	LevelUp = "★",
	Unlock = "✦",
	Warning = "!",
	Lesson = "✔",
	Toast = "•",
	Item = "▣",
}

local function toast(payload: any)
	local color = payload.Color
		or (
			if payload.Kind == "Warning"
				then C.Bad
				elseif payload.Kind == "Quest" then C.Accent
				elseif payload.Kind == "Achievement" then rgb(210, 180, 255)
				else C.Signal
		)
	local card = Kit.Panel(toastStack, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.15,
		LayoutOrder = -math.floor(os.clock() * 100),
	})
	Kit.Padding(card, 10, 12)
	Kit.List(card, false, 2)
	Kit.Label(card, ("%s  %s"):format(ICONS[payload.Kind] or "•", tostring(payload.Title or "")), 15, {
		Font = Kit.Fonts.Bold,
		TextColor3 = color,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	if payload.Text and payload.Text ~= "" then
		Kit.Paragraph(card, tostring(payload.Text), 13, C.Muted)
	end
	local rewards = Kit.Rewards(payload)
	if rewards ~= "" then
		Kit.Label(card, rewards, 13, { TextColor3 = C.Accent, Font = Kit.Fonts.Bold, Size = UDim2.new(1, 0, 0, 18) })
	end
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
		stroke.Transparency = 0.2
	end
	task.delay(if payload.Kind == "Warning" then 3.5 else 5, function()
		if card.Parent then
			TweenService:Create(card, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
			task.wait(0.3)
			card:Destroy()
		end
	end)
	-- Keep the stack short.
	local cards = {}
	for _, child in toastStack:GetChildren() do
		if child:IsA("Frame") then
			table.insert(cards, child)
		end
	end
	if #cards > 5 then
		table.sort(cards, function(a, b)
			return a.LayoutOrder > b.LayoutOrder
		end)
		cards[1]:Destroy()
	end
end

local bannerToken = 0
function Overlay.Banner(title: string, subtitle: string?, color: Color3?)
	bannerToken += 1
	local token = bannerToken
	banner.Text = title
	banner.TextColor3 = color or C.Text
	bannerSub.Text = subtitle or ""
	banner.TextTransparency = 0
	bannerSub.TextTransparency = 0
	banner.Visible = true
	bannerSub.Visible = true
	task.delay(2.8, function()
		if token == bannerToken then
			TweenService:Create(banner, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			TweenService:Create(bannerSub, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		end
	end)
end

local function onNotify(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local kind = payload.Kind
	if kind == "District" then
		Overlay.Banner(string.upper(tostring(payload.Title)), payload.Text, C.Accent)
		Sfx.Stinger("Discover")
		return
	elseif kind == "LevelUp" or kind == "Rank" or kind == "Ability" then
		Overlay.Banner(tostring(payload.Title), payload.Text, C.Accent)
		Sfx.Stinger("LevelUp")
	end
	local sound = payload.Sound
	if sound == "Quest" then
		Sfx.Stinger("Quest")
	elseif sound == "Achievement" or sound == "Mastery" or sound == "Unlock" then
		Sfx.Stinger("Unlock")
	elseif sound == "Discovery" then
		Sfx.Stinger("Discover")
	elseif sound == "Medal" then
		Sfx.Stinger("Medal")
	elseif kind == "Warning" then
		Sfx.Stinger("Error")
	end
	toast(payload)
end

-- Countdown ----------------------------------------------------------------------------------------------

local countdownAt: number? = nil
local lastShown = ""

local function updateCountdown()
	local at = countdownAt
	if not at then
		countdownLabel.Visible = false
		return
	end
	local left = at - Schedule.Now()
	local text
	if left > 0 then
		text = tostring(math.ceil(left))
	elseif left > -0.8 then
		text = "GO!"
	else
		countdownAt = nil
		countdownLabel.Visible = false
		return
	end
	countdownLabel.Visible = true
	if text ~= lastShown then
		lastShown = text
		countdownLabel.Text = text
		countdownLabel.TextColor3 = if text == "GO!" then C.Good else C.Text
		countdownLabel.TextSize = 120
		TweenService:Create(countdownLabel, TweenInfo.new(0.25, Enum.EasingStyle.Back), { TextSize = 96 }):Play()
		Sfx.Stinger(if text == "GO!" then "Go" else "Countdown")
	end
end

-- Course preview -------------------------------------------------------------------------------------------

local function medalRow(parent: Instance, medals: { number }, record: any?)
	local row = Kit.Row(parent, 34, 8)
	for index, seconds in medals do
		local earned = record and (record.Medal or 0) >= index
		local chip = Kit.Label(row, ("%s %s"):format(Kit.MedalText(index), Format.Time(seconds)), 14, {
			Size = UDim2.fromOffset(132, 30),
			TextXAlignment = Enum.TextXAlignment.Center,
			BackgroundTransparency = if earned then 0.2 else 0.75,
			BackgroundColor3 = C.Medal[index],
			TextColor3 = if earned then rgb(20, 20, 24) else C.Medal[index],
			Font = Kit.Fonts.Bold,
			LayoutOrder = index,
		})
		Kit.Corner(chip, 6)
	end
end

local function abilityNames(list: { string }): string
	local names = {}
	for _, id in list do
		local ability = Abilities.ById[id]
		table.insert(names, if ability then ability.Name else id)
	end
	return table.concat(names, ", ")
end

function Overlay.CoursePreview(courseId: string)
	local config = CourseClient.Config(courseId)
	if not config then
		return
	end
	local course = Courses.ById[courseId]
	local name = config:GetAttribute("Name") or courseId
	local difficulty = config:GetAttribute("Difficulty") or 1
	local kind = config:GetAttribute("Kind") or "Course"
	local body = openModal(
		560,
		name,
		("%s · %s · %s"):format(
			tostring(config:GetAttribute("District")),
			if kind == "Room" then "Challenge Room" elseif kind == "Relay" then "Relay" else "Course",
			Courses.DifficultyNames[difficulty] or ("Difficulty " .. difficulty)
		)
	)
	if course then
		Kit.Paragraph(body, course.Blurb, 15, C.Text)
		Kit.Paragraph(body, "Focus: " .. table.concat(course.Focus, " · "), 13, C.Muted)
	end
	local medals = CourseClient.Medals(config)
	local record = State.Profile and State.Profile.Courses and State.Profile.Courses[courseId]
	medalRow(body, medals, record)
	if record and (record.Completions or 0) > 0 then
		local tokens = 0
		for _ in record.Tokens or {} do
			tokens += 1
		end
		local distinctions = {}
		for _, def in Courses.Distinctions do
			table.insert(
				distinctions,
				(if record.Distinctions and record.Distinctions[def.Id] then "✓ " else "· ") .. def.Name
			)
		end
		Kit.Paragraph(
			body,
			("Best %s · Ranked %s · %d runs · ★ %d/%d tokens"):format(
				Format.Time(record.Best),
				Format.Time(record.RankedBest),
				record.Completions or 0,
				tokens,
				config:GetAttribute("Tokens") or 0
			),
			14,
			C.Text
		)
		Kit.Paragraph(body, table.concat(distinctions, "   "), 13, C.Muted)
	else
		Kit.Paragraph(body, "Not finished yet. Accessible route first, then hunt for the faster lines.", 14, C.Muted)
	end

	local status = Kit.Paragraph(body, "Loading records…", 13, C.Faint)
	local boards = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = body,
	})
	Kit.List(boards, false, 4)

	-- Mode selection.
	local modes = { "Casual", "Practice", "Ranked" }
	local mode = "Casual"
	local assists: { [string]: boolean } = {}
	local modeRow = Kit.Row(body, 40, 8)
	local modeText = Kit.Paragraph(body, "", 13, C.Muted)
	local assistBox = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = body,
	})
	Kit.List(assistBox, false, 4)
	for _, assist in MoveStats.Assists do
		local row = Kit.Row(assistBox, 36, 8)
		Kit.Toggle(row, false, function(on)
			assists[assist.Id] = on or nil
		end)
		Kit.Label(
			row,
			("%s: %s"):format(assist.Name, assist.Text),
			13,
			{ Size = UDim2.new(1, -100, 1, 0), TextColor3 = C.Muted }
		)
	end
	local modeButtons: { [string]: TextButton } = {}
	local function selectMode(m: string)
		mode = m
		for key, button in modeButtons do
			button.BackgroundColor3 = if key == m then C.Signal:Lerp(C.PanelLight, 0.4) else C.PanelLight
			button.Text = (if key == m then "● " else "") .. key
		end
		modeText.Text = if m == "Casual"
			then "Your own movement and upgrades. Medals, rewards and personal bests."
			elseif m == "Practice" then ("Assists allowed, [%s] sets a practice checkpoint. No medals."):format(
				Input.Glyph("Mark")
			)
			else "Standard attributes and the course's full kit for everyone. Leaderboards and ghosts."
		assistBox.Visible = m == "Practice"
	end
	for _, m in modes do
		modeButtons[m] = Kit.Button(modeRow, m, function()
			selectMode(m)
		end, "Secondary", { Size = UDim2.fromOffset(140, 36) })
	end
	selectMode("Casual")

	local actions = Kit.Row(body, 48, 10)
	local message = Kit.Paragraph(body, "", 14, C.Bad)
	local startButton = Kit.Button(actions, "▶  Start run", function()
		message.Text = "Starting…"
		message.TextColor3 = C.Muted
		task.spawn(function()
			local ok, reason = CourseClient.Begin(courseId, mode, assists)
			if ok then
				Overlay.CloseModal()
			else
				message.Text = reason or "Couldn't start"
				message.TextColor3 = C.Bad
				Sfx.Stinger("Error")
			end
		end)
	end, "Primary", { Size = UDim2.fromOffset(170, 44) })
	if kind == "Course" then
		Kit.Button(actions, "Open a race", function()
			task.spawn(function()
				local ok, info = Modes.CreateRace(courseId)
				if ok then
					Overlay.CloseModal()
					Bus.OpenPage:Fire("Races", nil)
				else
					message.Text = tostring(info)
				end
			end)
		end, "Secondary", { Size = UDim2.fromOffset(150, 44) })
	elseif kind == "Relay" then
		startButton.Visible = false
		Kit.Button(actions, "Form a relay team", function()
			task.spawn(function()
				local ok, info = Modes.CreateRelay(courseId)
				if ok then
					Overlay.CloseModal()
					Bus.OpenPage:Fire("Races", nil)
				else
					message.Text = tostring(info)
				end
			end)
		end, "Primary", { Size = UDim2.fromOffset(200, 44) })
	end
	if Input.Device == "Gamepad" then
		GuiService.SelectedObject = startButton
	end

	task.spawn(function()
		local ok, preview = pcall(Net.Invoke, "Course.Preview", courseId)
		if not ok or type(preview) ~= "table" or not body.Parent then
			status.Text = "Records unavailable right now."
			return
		end
		status.Text = if preview.Online == false then "Records are kept for this session only (offline mode)." else ""
		if preview.Locked then
			message.Text = "🔒 " .. preview.Locked
			startButton.Visible = false
		end
		if preview.MissingFast and #preview.MissingFast > 0 then
			Kit.Paragraph(
				boards,
				"Fast route needs: " .. abilityNames(preview.MissingFast) .. " (Ranked lends the full kit)",
				13,
				C.Warn
			)
		end
		if preview.MissingExpert and #preview.MissingExpert > 0 then
			Kit.Paragraph(boards, "Expert route needs: " .. abilityNames(preview.MissingExpert), 13, C.Warn)
		end
		local function board(title: string, entries: any)
			if type(entries) ~= "table" or #entries == 0 then
				return
			end
			Kit.Label(boards, title, 14, { Font = Kit.Fonts.Bold, TextColor3 = C.Signal })
			for _, entry in entries do
				Kit.Label(boards, ("%d.  %s   %s"):format(entry.Rank, entry.Name, Format.Time(entry.Seconds)), 14)
			end
		end
		board("Fastest ranked runs", preview.Top)
		board("Friends", preview.Friends)
	end)
end

-- Results -------------------------------------------------------------------------------------------------

function Overlay.Results(result: any, run: any)
	local medal = result.Medal or 0
	local title = if result.Partial then "Leg complete" elseif medal > 0 then Kit.MedalText(medal) else "Finished"
	local color = if medal > 0 then C.Medal[medal] else C.Text
	local body = openModal(
		560,
		title,
		("%s · %s"):format(tostring(result.Name or result.CourseId), tostring(result.Mode)),
		color
	)
	Kit.Label(
		body,
		Format.Time(result.Seconds),
		48,
		{ Font = Kit.Fonts.Mono, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 60) }
	)
	if result.PreviousBest then
		local delta = result.Seconds - result.PreviousBest
		Kit.Label(body, (if result.NewBest then "NEW PERSONAL BEST  " else "Best ") .. Format.Delta(delta), 16, {
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = if delta < 0 then C.Good else C.Muted,
			Font = Kit.Fonts.Bold,
		})
	elseif result.FirstCompletion then
		Kit.Label(
			body,
			"FIRST COMPLETION",
			16,
			{ TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Accent, Font = Kit.Fonts.Black }
		)
	end
	if result.Medals and not result.Partial and result.Mode ~= "Practice" then
		medalRow(body, result.Medals, { Medal = medal })
		local nextMedal, limit = Medals.Next(result.Seconds, result.Medals)
		if nextMedal and limit then
			Kit.Paragraph(
				body,
				("Next: %s at %s — %s faster."):format(
					Kit.MedalText(nextMedal),
					Format.Time(limit),
					Format.Time(result.Seconds - limit)
				),
				14,
				C.Text
			)
		end
	end
	-- Distinctions.
	if not result.Partial and result.Mode ~= "Practice" then
		local list = {}
		for _, def in Courses.Distinctions do
			local earned = result.Distinctions and result.Distinctions[def.Id]
			local fresh = table.find(result.NewDistinctions or {}, def.Id) ~= nil
			table.insert(
				list,
				("%s %s%s"):format(if earned then "✓" else "✗", def.Name, if fresh then " (new!)" else "")
			)
		end
		Kit.Paragraph(body, table.concat(list, "    "), 14, C.Text)
		Kit.Paragraph(
			body,
			("Tokens ★ %d/%d · Falls %d · Retries %d · Flow %d / %d"):format(
				result.Tokens or 0,
				result.TokenTotal or 0,
				result.Falls or 0,
				result.Retries or 0,
				result.Flow or 0,
				result.FlowTarget or 0
			),
			13,
			C.Muted
		)
	end
	-- Splits.
	if result.Splits and #result.Splits > 0 then
		local parts = {}
		for index, split in result.Splits do
			table.insert(parts, ("CP%d %s"):format(index, Format.Time(split)))
		end
		Kit.Paragraph(body, table.concat(parts, "   "), 13, C.Muted)
	end
	-- Rewards.
	for _, line in result.Lines or {} do
		Kit.Label(body, ("%s   %s"):format(line.Label, Kit.Rewards(line)), 14, { TextColor3 = C.Accent })
	end
	if result.Verified == false then
		Kit.Paragraph(body, "This run had connection hiccups, so it wasn't submitted to the leaderboard.", 13, C.Warn)
	end
	local actions = Kit.Row(body, 48, 10)
	local courseId = result.CourseId
	local mode = result.Mode
	if run and run.Context == nil and mode ~= "Tower" then
		local retry = Kit.Button(actions, "↻ Run again", function()
			Overlay.CloseModal()
			task.spawn(CourseClient.Begin, courseId, mode, CourseClient.Assists)
		end, "Primary", { Size = UDim2.fromOffset(150, 44) })
		if Input.Device == "Gamepad" then
			GuiService.SelectedObject = retry
		end
		if mode ~= "Ranked" then
			Kit.Button(actions, "Try ranked", function()
				Overlay.CloseModal()
				task.spawn(CourseClient.Begin, courseId, "Ranked")
			end, "Secondary", { Size = UDim2.fromOffset(130, 44) })
		end
	end
	Kit.Button(actions, "Continue", Overlay.CloseModal, "Secondary", { Size = UDim2.fromOffset(130, 44) })
end

-- Dialogue ---------------------------------------------------------------------------------------------------

function Overlay.Dialogue(npcId: string, response: any)
	local npc = NPCs.ById[npcId]
	local body = openModal(560, if npc then npc.Name else npcId, if npc then npc.Role else nil)
	local lines = response.Lines or {}
	local index = 1
	local text = Kit.Paragraph(body, "", 17, C.Text)
	local continue = Kit.Button(body, "Next ›", nil, "Secondary", { Size = UDim2.fromOffset(120, 38) })
	local after = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = body,
	})
	Kit.List(after, false, 10)

	local function showAfter()
		continue.Visible = false
		after.Visible = true
		for _, done in response.Completed or {} do
			Kit.Paragraph(after, ("✔ %s complete   %s"):format(done.Name, Kit.Rewards(done.Rewards)), 15, C.Good)
		end
		for _, offer in response.Offers or {} do
			local card = Kit.Card(after)
			local tag = if offer.Type == "Main"
				then "STORY"
				elseif offer.Type == "Expert" then "EXPERT TRIAL"
				else "SIDE QUEST"
			Kit.Label(
				card,
				tag .. " · " .. offer.Name,
				16,
				{ Font = Kit.Fonts.Bold, TextColor3 = if offer.Type == "Main" then C.Accent else C.Signal }
			)
			for _, line in offer.Intro or {} do
				Kit.Paragraph(card, "“" .. line .. "”", 14, C.Text)
			end
			Kit.Label(card, "What it takes", 13, { Font = Kit.Fonts.Bold, TextColor3 = C.Muted })
			for i, step in offer.Steps or {} do
				Kit.Paragraph(card, ("%d. %s"):format(i, step), 13, C.Muted)
			end
			Kit.Label(card, "Rewards: " .. Kit.Rewards(offer.Rewards), 13, { TextColor3 = C.Accent })
			local row = Kit.Row(card, 40, 8)
			local note = Kit.Paragraph(card, "", 13, C.Bad)
			Kit.Button(row, "Accept", function()
				task.spawn(function()
					local ok, reason = QuestClient.Accept(offer.Id)
					if ok then
						card:Destroy()
						Sfx.Stinger("Quest")
					else
						note.Text = reason or "Can't accept that right now"
					end
				end)
			end, "Primary", { Size = UDim2.fromOffset(120, 36) })
			Kit.Button(row, "Not now", function()
				card:Destroy()
			end, "Ghost", { Size = UDim2.fromOffset(110, 36) })
		end
		local service = response.Service
		if service then
			local pages = {
				Shop = "Shop",
				Races = "Races",
				Crew = "Crew",
				Tower = "Tower",
				Achievements = "Achievements",
				Mastery = "Mastery",
			}
			if service == "Endless" then
				Kit.Button(after, "Enter the Dreamline", function()
					Overlay.CloseModal()
					Modes.StartEndless()
				end, "Primary", { Size = UDim2.fromOffset(220, 40) })
			elseif pages[service] then
				Kit.Button(after, "Open " .. service, function()
					Overlay.CloseModal()
					Bus.OpenPage:Fire(pages[service], nil)
				end, "Primary", { Size = UDim2.fromOffset(180, 40) })
			end
		end
		Kit.Button(after, "Goodbye", Overlay.CloseModal, "Secondary", { Size = UDim2.fromOffset(140, 38) })
	end
	local function show()
		if index <= #lines then
			text.Text = "“" .. lines[index] .. "”"
		end
		if index >= #lines then
			showAfter()
		end
	end
	continue.Activated:Connect(function()
		index += 1
		show()
	end)
	show()
	-- Face the speaker.
	local folder = workspace:FindFirstChild("SkylineNPCs")
	local model = folder and folder:FindFirstChild(npcId)
	local root = Controller.Info.Root
	if model and model:IsA("Model") and root then
		local head = model:FindFirstChild("Head") :: BasePart?
		local target = if head then head.Position else model:GetPivot().Position
		-- Over the runner's shoulder, looking at the speaker.
		local offset = (root.Position - target) * Vector3.new(1, 0, 1)
		local away = if offset.Magnitude > 0.1 then offset.Unit else Vector3.zAxis
		local from = target + away * 9 + Vector3.new(0, 1.5, 0)
		CameraController.SetOverride(function()
			return CFrame.lookAt(from, target), 50
		end)
		local connection
		connection = RunService.Heartbeat:Connect(function()
			if modal == nil or not body.Parent then
				connection:Disconnect()
				CameraController.SetOverride(nil)
			end
		end)
	end
end

-- Confirmations and mode panels -------------------------------------------------------------------------

function Overlay.Confirm(title: string, text: string, options: { { Text: string, Callback: (() -> ())? } })
	local body = openModal(460, title)
	Kit.Paragraph(body, text, 15, C.Text)
	local row = Kit.Row(body, 46, 10)
	for index, option in options do
		Kit.Button(row, option.Text, function()
			Overlay.CloseModal()
			if option.Callback then
				option.Callback()
			end
		end, if index == 1 then "Primary" else "Secondary", { Size = UDim2.fromOffset(140, 42) })
	end
end

local function towerCleared(data: any)
	local body = openModal(
		480,
		("Floor %d cleared"):format(data.Floor),
		("Highest floor: %d / 25"):format(data.Highest or data.Floor),
		C.Signal
	)
	Kit.Label(
		body,
		Format.Time(data.Seconds),
		40,
		{ Font = Kit.Fonts.Mono, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 50) }
	)
	if data.PreviousBest then
		Kit.Label(
			body,
			"Best " .. Format.Time(data.Best) .. "  (" .. Format.Delta(data.Seconds - data.PreviousBest) .. ")",
			15,
			{ TextXAlignment = Enum.TextXAlignment.Center }
		)
	end
	Kit.Label(body, Kit.Rewards(data), 15, { TextColor3 = C.Accent, TextXAlignment = Enum.TextXAlignment.Center })
	local row = Kit.Row(body, 48, 10)
	if data.Next then
		Kit.Button(row, ("Floor %d ›"):format(data.Next), function()
			Overlay.CloseModal()
			task.spawn(Modes.TowerFloor, data.Next)
		end, "Primary", { Size = UDim2.fromOffset(140, 44) })
	elseif data.Roof then
		Kit.Button(row, "To the roof ›", function()
			Overlay.CloseModal()
			task.spawn(Modes.TowerFloor, 26)
		end, "Primary", { Size = UDim2.fromOffset(160, 44) })
	end
	Kit.Button(row, "Retry floor", function()
		Overlay.CloseModal()
		task.spawn(Modes.TowerFloor, data.Floor)
	end, "Secondary", { Size = UDim2.fromOffset(130, 44) })
	Kit.Button(row, "Leave", function()
		Overlay.CloseModal()
		Modes.LeaveTower()
	end, "Ghost", { Size = UDim2.fromOffset(100, 44) })
end

local function relayResults(data: any)
	local medal = data.Medal or 0
	local body = openModal(
		500,
		if medal > 0 then "Relay · " .. Kit.MedalText(medal) else "Relay complete",
		("Team of %d"):format(data.TeamSize or 1),
		if medal > 0 then C.Medal[medal] else C.Text
	)
	Kit.Label(
		body,
		Format.Time(data.Total),
		40,
		{ Font = Kit.Fonts.Mono, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 50) }
	)
	for _, leg in data.Legs or {} do
		Kit.Label(body, ("Leg %d · %s · %s"):format(leg.Index, leg.Name, Format.Time(leg.Time)), 15)
	end
	Kit.Label(body, Kit.Rewards(data), 15, { TextColor3 = C.Accent })
	Kit.Button(body, "Continue", Overlay.CloseModal, "Primary", { Size = UDim2.fromOffset(140, 42) })
end

local function endlessEnded(data: any)
	if type(data) ~= "table" then
		return
	end
	local body = openModal(
		460,
		if data.Record then "New Dreamline record!" else "Run over",
		tostring(data.Reason),
		rgb(255, 160, 240)
	)
	Kit.Label(
		body,
		("%d gates"):format(data.Cleared or 0),
		40,
		{ Font = Kit.Fonts.Black, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 50) }
	)
	Kit.Label(
		body,
		("Record %d · %s"):format(data.Best or 0, Format.Duration(data.Seconds or 0)),
		15,
		{ TextXAlignment = Enum.TextXAlignment.Center }
	)
	Kit.Label(body, Kit.Rewards(data), 15, { TextColor3 = C.Accent, TextXAlignment = Enum.TextXAlignment.Center })
	local row = Kit.Row(body, 48, 10)
	Kit.Button(row, "Run again", function()
		Overlay.CloseModal()
		Modes.StartEndless()
	end, "Primary", { Size = UDim2.fromOffset(140, 44) })
	Kit.Button(row, "Done", Overlay.CloseModal, "Secondary", { Size = UDim2.fromOffset(120, 44) })
end

function Overlay.IsOpen(): boolean
	return modal ~= nil
end

function Overlay.Start()
	gui = Root.Get("Overlay")
	toastStack = Kit.new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -150),
		Size = UDim2.fromOffset(320, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local layout = Kit.List(toastStack, false, 6)
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	banner = Kit.Label(gui, "", 34, {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.2, 0),
		Size = UDim2.new(0.8, 0, 0, 44),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Kit.Fonts.Black,
		TextStrokeTransparency = 0.5,
		Visible = false,
	})
	bannerSub = Kit.Label(gui, "", 17, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.2, 46),
		Size = UDim2.new(0.8, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Muted,
		TextStrokeTransparency = 0.6,
		Visible = false,
	})
	countdownLabel = Kit.Label(gui, "", 96, {
		Name = "Countdown",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(400, 140),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Kit.Fonts.Black,
		TextStrokeTransparency = 0.3,
		Visible = false,
	})

	Net.Listen("Notify", onNotify)
	Bus.Notify:Connect(onNotify)
	Bus.Banner:Connect(function(title, subtitle, color)
		Overlay.Banner(title, subtitle, color)
	end)
	Bus.Countdown:Connect(function(at: number)
		countdownAt = at
		lastShown = ""
	end)
	Bus.CoursePreview:Connect(Overlay.CoursePreview)
	Bus.CourseResults:Connect(Overlay.Results)
	Bus.Dialogue:Connect(Overlay.Dialogue)
	Bus.Confirm:Connect(Overlay.Confirm)
	Bus.Mode:Connect(function(kind: string, data: any)
		if kind == "TowerCleared" then
			towerCleared(data)
		elseif kind == "RelayResults" then
			relayResults(data)
		elseif kind == "EndlessEnded" then
			endlessEnded(data)
		elseif kind == "RaceReward" and type(data) == "table" then
			Overlay.Banner(
				("Place %d of %d"):format(data.Place, data.Field),
				Kit.Rewards(data),
				if data.Place == 1 then C.Accent else C.Text
			)
		elseif kind == "RelayHandoff" and type(data) == "table" then
			Overlay.Banner(("Leg %d!"):format(data.Leg), "The baton is passed", rgb(255, 120, 220))
		end
	end)
	Net.Listen("Social.Invite", function(data)
		if type(data) ~= "table" then
			return
		end
		Overlay.Confirm(
			"Invite",
			("%s invites you to %s."):format(
				tostring(data.Name),
				if data.Kind == "Race"
					then "a race"
					elseif data.Kind == "Relay" then "their relay team"
					else "run together"
			),
			{
				{
					Text = "Accept",
					Callback = function()
						task.spawn(function()
							local ok, success, info = pcall(Net.Invoke, "Social.Respond", data.From, true)
							if ok and success and type(info) == "table" and typeof(info.Teleport) == "CFrame" then
								Controller.Teleport(info.Teleport)
							elseif ok and not success then
								Overlay.Banner("Couldn't join", tostring(info))
							end
						end)
					end,
				},
				{
					Text = "Decline",
					Callback = function()
						task.spawn(pcall, Net.Invoke, "Social.Respond", data.From, false)
					end,
				},
			}
		)
	end)
	Net.Listen("Crew.Invite", function(data)
		if type(data) ~= "table" then
			return
		end
		Overlay.Confirm(
			"Crew invite",
			("%s invites you to join [%s] %s."):format(tostring(data.From), tostring(data.Tag), tostring(data.Name)),
			{
				{
					Text = "Join",
					Callback = function()
						task.spawn(function()
							local ok, success, info = pcall(Net.Invoke, "Crew.Respond", data.CrewId, true)
							if ok and not success then
								Overlay.Banner("Couldn't join", tostring(info))
							end
						end)
					end,
				},
				{
					Text = "No thanks",
					Callback = function()
						task.spawn(pcall, Net.Invoke, "Crew.Respond", data.CrewId, false)
					end,
				},
			}
		)
	end)
	RunService.RenderStepped:Connect(updateCountdown)
end

return Overlay

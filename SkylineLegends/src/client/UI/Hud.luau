-- The heads-up display. Everything a runner needs mid-move, readable at a
-- glance and never by colour alone:
--   stamina, with a preview of what your next move would cost and a clear
--   TIRED / EXHAUSTED state; air-action pips (double jump, dash charges with
--   cooldown, grapple target); level, XP and currencies; pinned objectives
--   with a waypoint arrow; the run panel (timer, splits, checkpoints, tokens,
--   next medal); the flow meter and chain; contextual input hints; the lesson
--   card and mode panels (race, relay, Spire, Dreamline, timed jobs).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FlowConfig = require(ReplicatedStorage.Shared.Config.Flow)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Leveling = require(ReplicatedStorage.Shared.Logic.Leveling)
local Medals = require(ReplicatedStorage.Shared.Logic.Medals)
local Progression = require(ReplicatedStorage.Shared.Config.Progression)
local Quests = require(ReplicatedStorage.Shared.Config.Quests)

local Bus = require(script.Parent.Parent.Core.Bus)
local Input = require(script.Parent.Parent.Core.Input)
local Settings = require(script.Parent.Parent.Core.Settings)
local State = require(script.Parent.Parent.Core.State)
local Controller = require(script.Parent.Parent.Movement.Controller)
local Stamina = require(script.Parent.Parent.Movement.Stamina)
local CourseClient = require(script.Parent.Parent.Gameplay.CourseClient)
local Flow = require(script.Parent.Parent.Gameplay.Flow)
local QuestClient = require(script.Parent.Parent.Gameplay.QuestClient)
local LessonsClient = require(script.Parent.Parent.Gameplay.Lessons)
local Kit = require(script.Parent.Kit)
local Root = require(script.Parent.Root)

local C = Kit.Colors
local Hud = {}

local ui: { [string]: any } = {}
local splitFlashUntil = 0
local deniedUntil = 0
local timerEnds: number? = nil
local raceProgress: { [number]: number } = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Builders -----------------------------------------------------------------------------------------

local function buildStamina(parent: Instance)
	local holder = Kit.new("Frame", {
		Name = "Stamina",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -28),
		Size = UDim2.fromOffset(360, 74),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	-- Air actions row.
	local pips = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		Parent = holder,
	})
	Kit.List(pips, true, 10, Enum.HorizontalAlignment.Center)
	local function pip(name: string, glyph: string, order: number): TextLabel
		local label = Kit.Label(pips, glyph, 15, {
			Name = name,
			Size = UDim2.fromOffset(78, 28),
			BackgroundTransparency = 0.25,
			BackgroundColor3 = C.Panel,
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Kit.Fonts.Bold,
			LayoutOrder = order,
		})
		Kit.Corner(label, 7)
		return label
	end
	ui.DoublePip = pip("Double", "◆ 2×JUMP", 1)
	ui.DashPip = pip("Dash", "▮ DASH", 2)
	ui.DashPip.Size = UDim2.fromOffset(92, 28)
	ui.DashCooldown = Kit.new("Frame", {
		BackgroundColor3 = C.Signal,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		ZIndex = 0,
		Parent = ui.DashPip,
	})
	Kit.Corner(ui.DashCooldown, 7)
	ui.GrapplePip = pip("Grapple", "⌁ HOOK", 3)

	-- Bar.
	local bar = Kit.Bar(holder, C.Signal, {
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 14),
	})
	ui.StaminaBar = bar
	ui.StaminaCost = Kit.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = bar.Frame,
	})
	ui.StaminaText = Kit.Label(holder, "", 13, {
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Muted,
		Font = Kit.Fonts.Bold,
	})
	ui.StaminaHolder = holder
end

local function buildProfile(parent: Instance)
	local panel = Kit.Panel(parent, {
		Name = "Profile",
		Position = UDim2.fromOffset(16, 56),
		Size = UDim2.fromOffset(250, 66),
		BackgroundTransparency = 0.25,
	})
	Kit.Padding(panel, 8, 12)
	ui.LevelText = Kit.Label(panel, "Lv 1", 16, { Size = UDim2.new(1, 0, 0, 20), Font = Kit.Fonts.Bold })
	ui.RankText = Kit.Label(panel, "", 13, { Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 16), TextColor3 = C.Muted })
	ui.XPBar = Kit.Bar(panel, C.Accent, { Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, 6) })
	ui.Currency = Kit.Label(panel, "", 13, {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Kit.Fonts.Bold,
		TextColor3 = C.Accent,
	})
	ui.Profile = panel
end

local function buildFlow(parent: Instance)
	local panel = Kit.new("Frame", {
		Name = "Flow",
		Position = UDim2.fromOffset(16, 132),
		Size = UDim2.fromOffset(250, 70),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	ui.FlowTier = Kit.Label(panel, "", 15, { Size = UDim2.new(1, 0, 0, 20), Font = Kit.Fonts.Black })
	ui.FlowBar = Kit.Bar(panel, rgb(120, 255, 200), { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 6) })
	ui.FlowChain = Kit.Label(panel, "", 13, { Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 34), TextColor3 = C.Muted, TextYAlignment = Enum.TextYAlignment.Top })
	ui.Flow = panel
end

local function buildObjectives(parent: Instance)
	local panel = Kit.new("Frame", {
		Name = "Objectives",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 56),
		Size = UDim2.fromOffset(300, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = parent,
	})
	Kit.List(panel, false, 6)
	ui.Objectives = panel
	-- Waypoint marker (follows the pinned objective on screen, or points to it from the edge).
	local marker = Kit.Label(parent, "◆", 22, {
		Name = "Waypoint",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(120, 44),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Accent,
		TextStrokeTransparency = 0.3,
		Font = Kit.Fonts.Black,
		Visible = false,
	})
	ui.Waypoint = marker
end

local function buildRun(parent: Instance)
	local panel = Kit.Panel(parent, {
		Name = "Run",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 52),
		Size = UDim2.fromOffset(340, 112),
		BackgroundTransparency = 0.3,
		Visible = false,
	})
	Kit.Padding(panel, 8, 14)
	ui.RunName = Kit.Label(panel, "", 14, { Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Muted, Font = Kit.Fonts.Bold })
	ui.RunTimer = Kit.Label(panel, "0:00.00", 34, {
		Position = UDim2.fromOffset(0, 18),
		Size = UDim2.new(1, 0, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Kit.Fonts.Mono,
	})
	ui.RunSplit = Kit.Label(panel, "", 16, {
		Position = UDim2.fromOffset(0, 58),
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Kit.Fonts.Bold,
	})
	ui.RunInfo = Kit.Label(panel, "", 13, {
		Position = UDim2.fromOffset(0, 78),
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Muted,
	})
	ui.Run = panel
end

local function buildHint(parent: Instance)
	ui.Hint = Kit.Label(parent, "", 14, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -108),
		Size = UDim2.fromOffset(520, 22),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Text,
		TextStrokeTransparency = 0.5,
		Font = Kit.Fonts.Bold,
	})
end

local function buildLesson(parent: Instance)
	local panel = Kit.Panel(parent, {
		Name = "Lesson",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.55, 0),
		Size = UDim2.fromOffset(300, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
	})
	Kit.Padding(panel, 12)
	Kit.List(panel, false, 6)
	ui.Lesson = panel
end

local function buildMode(parent: Instance)
	local panel = Kit.Panel(parent, {
		Name = "Mode",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.55, 0),
		Size = UDim2.fromOffset(260, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
	})
	Kit.Padding(panel, 12)
	Kit.List(panel, false, 4)
	ui.Mode = panel
	ui.Timer = Kit.Label(parent, "", 20, {
		Name = "QuestTimer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 170),
		Size = UDim2.fromOffset(300, 26),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Kit.Fonts.Black,
		TextStrokeTransparency = 0.4,
		Visible = false,
	})
	ui.Carry = Kit.Label(parent, "", 15, {
		Name = "Carry",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -134),
		Size = UDim2.fromOffset(360, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Accent,
		Font = Kit.Fonts.Bold,
		TextStrokeTransparency = 0.5,
		Visible = false,
	})
end

-- Updates --------------------------------------------------------------------------------------------

-- The move whose cost is most relevant right now, and its cost.
local function relevantCost(): (string?, number)
	local info = Controller.Info
	local state = info.State
	local costs = Controller.Stats.Costs or {}
	if state == "Air" then
		if info.DoubleJumpReady and Controller.Has("DoubleJump") then
			return "Double jump", costs.DoubleJump or 0
		elseif Controller.Has("Dash") and info.DashCharges > 0 then
			return "Dash", costs.Dash or 0
		end
	elseif state == "WallRun" then
		return "Wall run /s", costs.WallRun or 0
	elseif state == "Ledge" then
		return "Hang /s", costs.Hang or 0
	elseif state == "Climb" then
		return "Climb /s", costs.Climb or 0
	elseif state == "Ground" and info.Sprinting then
		return "Sprint /s", costs.Sprint or 0
	elseif Controller.Has("Dash") then
		return "Dash", costs.Dash or 0
	end
	return nil, 0
end

local function updateStamina()
	local value, max = Stamina.Value, math.max(Stamina.Max, 1)
	local fraction = value / max
	ui.StaminaBar.Set(fraction)
	local exhausted = Stamina.Exhausted
	local denied = os.clock() < deniedUntil
	local color = if exhausted or denied then C.Bad elseif fraction < 0.3 then C.Warn else C.Signal
	ui.StaminaBar.Color(color)
	local name, cost = relevantCost()
	local costFraction = math.clamp(cost / max, 0, fraction)
	ui.StaminaCost.Size = UDim2.fromScale(costFraction, 1)
	ui.StaminaCost.Position = UDim2.fromScale(fraction - costFraction, 0)
	ui.StaminaCost.Visible = name ~= nil and cost > 0
	local status = if exhausted then "EXHAUSTED — rest on the ground" elseif denied then "NOT ENOUGH STAMINA" elseif fraction < 0.3 then "TIRED" else ""
	local costText = if name and cost > 0 then ("%s −%d"):format(name, math.floor(cost + 0.5)) else ""
	ui.StaminaText.Text = if status ~= "" then status else costText
	ui.StaminaText.TextColor3 = if status ~= "" then color else C.Muted
	-- Hide when full and idle on the ground (clean screen), unless in a run.
	local idle = fraction >= 0.999 and Controller.Info.State == "Ground" and Controller.Info.Speed < 1 and not CourseClient.Run
	ui.StaminaHolder.Visible = not idle or os.clock() < deniedUntil
end

local function updatePips()
	local info = Controller.Info
	local doubleOn = Controller.Has("DoubleJump")
	ui.DoublePip.Visible = doubleOn
	if doubleOn then
		local ready = info.DoubleJumpReady
		ui.DoublePip.Text = if ready then "◆ 2×JUMP" else "◇ used"
		ui.DoublePip.TextColor3 = if ready then C.Text else C.Faint
	end
	local dashOn = Controller.Has("Dash")
	ui.DashPip.Visible = dashOn
	if dashOn then
		local charges = info.DashCharges
		local maxCharges = Controller.Stats.DashCharges or 1
		local marks = string.rep("▮", charges) .. string.rep("▯", math.max(maxCharges - charges, 0))
		ui.DashPip.Text = marks .. " DASH"
		ui.DashPip.TextColor3 = if charges > 0 and info.DashReady >= 1 then C.Text else C.Faint
		ui.DashCooldown.Size = UDim2.fromScale(if info.DashReady < 1 then info.DashReady else 0, 1)
	end
	local grappleOn = Controller.Has("Grapple")
	ui.GrapplePip.Visible = grappleOn
	if grappleOn then
		local target = info.GrappleTarget
		ui.GrapplePip.Text = if target then "⌁ HOOK ✓" else "⌁ HOOK"
		ui.GrapplePip.TextColor3 = if target then C.Signal else C.Faint
	end
end

local function updateProfile()
	local profile = State.Profile
	if not profile then
		return
	end
	local level, into, needed = Leveling.FromXP(profile.XP or 0)
	local rank = Progression.RankFor(level)
	ui.LevelText.Text = ("Lv %d"):format(level)
	ui.RankText.Text = if level >= 100 then rank.Name .. " · MAX" else ("%s · %s / %s XP"):format(rank.Name, Format.Number(into), Format.Number(needed))
	ui.RankText.TextColor3 = rank.Color
	ui.XPBar.Set(if needed > 0 then into / needed else 1)
	ui.Currency.Text = ("¢ %s   ✪ %d"):format(Format.Number(profile.Credits or 0), profile.Prestige or 0)
end

local function objectiveCard(title: string, text: string, color: Color3, order: number)
	local card = Kit.Panel(ui.Objectives, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.3,
		LayoutOrder = order,
	})
	Kit.Padding(card, 8, 10)
	Kit.List(card, false, 2)
	Kit.Label(card, title, 13, { TextColor3 = color, Font = Kit.Fonts.Bold, Size = UDim2.new(1, 0, 0, 16) })
	Kit.Paragraph(card, text, 14, C.Text)
end

local function updateObjectives()
	Kit.Clear(ui.Objectives)
	local profile = State.Profile
	if not profile then
		return
	end
	local order = 0
	for _, questId in profile.Quests.Pinned or {} do
		local quest = Quests.ById[questId]
		local state = profile.Quests.Active[questId]
		if quest and state then
			local step = quest.Steps[state.Step]
			if step then
				order += 1
				local progress = ""
				local done = 0
				for _ in state.Progress or {} do
					done += 1
				end
				local total = if step.Points then #step.Points elseif type(step.To) == "table" then #step.To else step.Count
				if total and total > 1 then
					progress = ("  (%d/%d)"):format(if state.Progress and state.Progress.Count then state.Progress.Count else done, total)
				end
				local tag = if quest.Type == "Main" then "STORY" elseif quest.Type == "Expert" then "EXPERT" else "SIDE"
				objectiveCard(tag .. " · " .. quest.Name, step.Text .. progress, if quest.Type == "Main" then C.Accent else C.Signal, order)
			end
		end
	end
	local contract = profile.Contracts and profile.Contracts.Active
	if contract then
		order += 1
		objectiveCard("CONTRACT · " .. tostring(contract.Name), tostring(contract.Text), C.Good, order)
	end
end

local function updateWaypoint()
	local marker = ui.Waypoint
	local target = QuestClient.PinnedTarget()
	local camera = workspace.CurrentCamera
	local root = Controller.Info.Root
	if not target or not camera or not root or CourseClient.Run then
		marker.Visible = false
		return
	end
	local distance = (target.Position - root.Position).Magnitude
	if distance < 10 then
		marker.Visible = false
		return
	end
	local point, onScreen = camera:WorldToViewportPoint(target.Position)
	local viewport = camera.ViewportSize
	marker.Visible = true
	local text = ("%dm"):format(math.floor(distance * 0.28 + 0.5))
	if onScreen and point.Z > 0 then
		marker.Position = UDim2.fromOffset(point.X, point.Y - 20)
		marker.Text = "◆\n" .. text
	else
		-- Point from the screen edge.
		local center = viewport / 2
		local direction = Vector2.new(point.X, point.Y) - center
		if point.Z < 0 then
			direction = -direction
		end
		if direction.Magnitude < 1 then
			direction = Vector2.new(0, -1)
		end
		local unit = direction.Unit
		local edge = center + unit * math.min(center.X - 60, center.Y - 60) / math.max(math.abs(unit.X), math.abs(unit.Y), 1e-3) * math.max(math.abs(unit.X), math.abs(unit.Y))
		marker.Position = UDim2.fromOffset(edge.X, edge.Y)
		local arrow = if math.abs(unit.X) > math.abs(unit.Y) then (if unit.X > 0 then "▶" else "◀") else (if unit.Y > 0 then "▼" else "▲")
		marker.Text = arrow .. "\n" .. text
	end
	marker.TextColor3 = if Settings.Get("HighContrast") then Color3.new(1, 1, 1) else C.Accent
end

local function updateRun()
	local run = CourseClient.Run
	ui.Run.Visible = run ~= nil
	if not run then
		return
	end
	local elapsed = CourseClient.Elapsed()
	if elapsed < 0 then
		ui.RunTimer.Text = ("%.1f"):format(-elapsed)
	else
		ui.RunTimer.Text = Format.Time(elapsed)
	end
	local tag = if run.Mode == "Ranked" then "RANKED" elseif run.Mode == "Practice" then "PRACTICE" else string.upper(run.Mode)
	ui.RunName.Text = ("%s · %s"):format(run.Name, tag)
	if os.clock() > splitFlashUntil then
		ui.RunSplit.Text = ""
	end
	local tokens = 0
	for _ in run.Tokens do
		tokens += 1
	end
	local info = ("CP %d/%d   ★ %d/%d"):format(run.Checkpoint, run.CheckpointCount, tokens, run.TokenTotal)
	if run.Mode ~= "Practice" and #run.Medals > 0 and run.Context == nil then
		local medal, limit = Medals.Next(math.max(elapsed, 0), run.Medals)
		if medal and limit then
			local current = Medals.For(math.max(elapsed, 0), run.Medals)
			local target = if current > 0 then current else medal
			local targetLimit = run.Medals[target]
			info ..= ("   %s %s"):format(Kit.MedalText(target), Format.Time(targetLimit))
		end
	end
	if run.Mode == "Race" then
		local ahead = 0
		for _, index in raceProgress do
			if index > run.Checkpoint then
				ahead += 1
			end
		end
		info ..= ("   Place ~%d"):format(ahead + 1)
	end
	if run.Mark then
		info ..= "   ⚑ mark set"
	end
	ui.RunInfo.Text = info
end

local function updateFlow()
	local tier = Flow.Tier
	local show = CourseClient.Run ~= nil or Settings.Get("ShowFlow") ~= false
	ui.Flow.Visible = show and (Flow.Meter > 1 or CourseClient.Run ~= nil)
	local info = FlowConfig.Tiers[tier]
	ui.FlowTier.Text = if info then ("%s  ×%.2g"):format(string.upper(info.Name), info.Multiplier) else "FLOW"
	ui.FlowTier.TextColor3 = if tier >= 4 then rgb(255, 150, 230) elseif tier >= 2 then rgb(120, 255, 200) else C.Muted
	ui.FlowBar.Set(Flow.Meter / FlowConfig.MeterMax)
	local chain = table.concat(Flow.Chain, " › ")
	if CourseClient.Run then
		chain = ("Score %d  ·  %s"):format(Flow.RunScore(), chain)
	end
	ui.FlowChain.Text = chain
end

local ACTION_HINTS: { [string]: (any) -> string? } = {
	Ledge = function()
		local text = ("[%s] Climb up   [%s] Drop   [%s] Shimmy"):format(Input.Glyph("Jump"), Input.Glyph("Crouch"), Input.Glyph("Move"))
		if Controller.Has("LedgeLeap") then
			text ..= ("   Hold up + [%s] Leap"):format(Input.Glyph("Jump"))
		end
		return text
	end,
	WallRun = function()
		return ("[%s] Wall jump   [%s] Let go"):format(Input.Glyph("Jump"), Input.Glyph("Crouch"))
	end,
	Climb = function()
		return ("[%s] Climb   [%s] Hop up   [%s] Let go"):format(Input.Glyph("Move"), Input.Glyph("Jump"), Input.Glyph("Crouch"))
	end,
	Zipline = function()
		return ("[%s] Jump off   [%s] Drop"):format(Input.Glyph("Jump"), Input.Glyph("Crouch"))
	end,
	Swing = function()
		return ("Pump with [%s]   Release [%s] at the top of the arc"):format(Input.Glyph("Move"), Input.Glyph("Jump"))
	end,
	Balance = function()
		return ("Steer with [%s] to stay centred"):format(Input.Glyph("Move"))
	end,
	Slide = function()
		return ("[%s] Slide jump keeps your speed"):format(Input.Glyph("Jump"))
	end,
}

local function updateHint()
	if Settings.Get("ShowInputHints") == false then
		ui.Hint.Text = ""
		return
	end
	local info = Controller.Info
	local fn = ACTION_HINTS[info.State]
	local text = if fn then fn(info) else nil
	if not text and info.State == "Air" then
		if info.GrappleTarget and Controller.Has("Grapple") then
			text = ("[%s] Grapple"):format(Input.Glyph("Grapple"))
		elseif info.Velocity.Y < -70 and Controller.Has("Roll") then
			text = ("Press [%s] just before landing to roll"):format(Input.Glyph("Crouch"))
		end
	end
	ui.Hint.Text = text or ""
end

local function renderLesson(lesson: any, step: number, progress: number)
	local panel = ui.Lesson
	Kit.Clear(panel)
	if not lesson then
		panel.Visible = false
		return
	end
	panel.Visible = true
	Kit.Label(panel, "TRAINING · " .. string.upper(lesson.Name), 15, { Font = Kit.Fonts.Black, TextColor3 = C.Accent, Size = UDim2.new(1, 0, 0, 20) })
	local lock = LessonsClient.LockReason(lesson)
	if lock then
		Kit.Paragraph(panel, "🔒 " .. lock, 14, C.Warn)
		return
	end
	Kit.Paragraph(panel, ("Input: [%s]"):format(Input.Glyph(lesson.Input)), 14, C.Signal)
	for index, entry in lesson.Steps do
		local mark = if index < step then "✓" elseif index == step then "▶" else "·"
		local count = ""
		if index == step and entry.Count and entry.Count > 1 then
			count = (" (%d/%d)"):format(progress, entry.Count)
		end
		Kit.Paragraph(panel, ("%s %s%s"):format(mark, entry.Text, count), 14, if index < step then C.Good elseif index == step then C.Text else C.Faint)
	end
	if step > #lesson.Steps then
		Kit.Paragraph(panel, "✓ Lesson complete! Try the next station.", 14, C.Good)
	end
end

local function renderMode(kind: string?, data: any)
	local panel = ui.Mode
	Kit.Clear(panel)
	if kind == "Endless" and data then
		panel.Visible = true
		Kit.Label(panel, "THE DREAMLINE", 15, { Font = Kit.Fonts.Black, TextColor3 = rgb(255, 160, 240) })
		Kit.Label(panel, ("Gates cleared: %d"):format(data.Cleared or 0), 15)
		Kit.Label(panel, ("Lives: %s"):format(string.rep("♥ ", data.Lives or 0)), 15, { TextColor3 = C.Bad })
		Kit.Label(panel, ("Difficulty %.1f"):format(data.Difficulty or 1), 13, { TextColor3 = C.Muted })
		local best = State.Profile and State.Profile.Endless and State.Profile.Endless.Best or 0
		Kit.Label(panel, ("Record: %d"):format(best), 13, { TextColor3 = C.Muted })
	elseif kind == "Race" and data and data.State == "Running" then
		panel.Visible = true
		Kit.Label(panel, "RACE · " .. tostring(data.CourseName), 15, { Font = Kit.Fonts.Black, TextColor3 = rgb(255, 120, 220) })
		for _, member in data.Members or {} do
			local finished = nil
			for _, result in data.Results or {} do
				if result.UserId == member.UserId then
					finished = result
				end
			end
			local text = if finished then ("%d. %s  %s"):format(finished.Place, member.Name, Format.Time(finished.Seconds)) else ("—  %s  CP %d"):format(member.Name, raceProgress[member.UserId] or 0)
			Kit.Label(panel, text, 14)
		end
	elseif kind == "Relay" and data and data.State == "Running" then
		panel.Visible = true
		Kit.Label(panel, "RELAY · " .. tostring(data.CourseName), 15, { Font = Kit.Fonts.Black, TextColor3 = rgb(255, 120, 220) })
		for _, leg in data.Legs or {} do
			local mark = if leg.Index < data.Leg then "✓" elseif leg.Index == data.Leg then "▶" else "·"
			Kit.Label(panel, ("%s Leg %d: %s%s"):format(mark, leg.Index, leg.Name, if leg.Time then "  " .. Format.Time(leg.Time) else ""), 14)
		end
	else
		panel.Visible = false
	end
end

function Hud.Start()
	local gui = Root.Get("Hud")
	buildStamina(gui)
	buildProfile(gui)
	buildFlow(gui)
	buildObjectives(gui)
	buildRun(gui)
	buildHint(gui)
	buildLesson(gui)
	buildMode(gui)

	State.On("XP", updateProfile)
	State.On("Credits", updateProfile)
	State.On("Prestige", updateProfile)
	Bus.Objective:Connect(updateObjectives)
	State.On("Quests", updateObjectives)
	updateObjectives()
	Stamina.Denied:Connect(function()
		deniedUntil = os.clock() + 0.7
	end)
	Bus.Split:Connect(function(index: number, seconds: number, delta: number?)
		splitFlashUntil = os.clock() + 2.5
		if delta then
			ui.RunSplit.Text = ("CP %d  %s  (%s)"):format(index, Format.Time(seconds), Format.Delta(delta))
			ui.RunSplit.TextColor3 = if delta <= 0 then C.Good else C.Bad
		else
			ui.RunSplit.Text = ("CP %d  %s"):format(index, Format.Time(seconds))
			ui.RunSplit.TextColor3 = C.Text
		end
	end)
	Bus.Lesson:Connect(renderLesson)
	local currentMode: string? = nil
	local currentData: any = nil
	Bus.Mode:Connect(function(kind: string, data: any)
		if kind == "RaceProgress" then
			raceProgress[data.UserId] = data.Index
		elseif kind == "Endless" or kind == "Race" or kind == "Relay" then
			currentMode, currentData = kind, data
			if kind == "Race" and data and data.State ~= "Running" then
				table.clear(raceProgress)
			end
		elseif kind == "EndlessEnded" then
			currentMode, currentData = nil, nil
		end
		renderMode(currentMode, currentData)
	end)
	Bus.Timer:Connect(function(seconds: number?)
		timerEnds = if seconds then os.clock() + seconds else nil
	end)
	Bus.Carry:Connect(function(carrying: boolean, fragile: boolean)
		ui.Carry.Visible = carrying
		ui.Carry.Text = if fragile then "📦 Carrying a FRAGILE package: no stumbles or falls" else "📦 Carrying a package"
	end)
	Bus.PageChanged:Connect(function(page)
		gui.Enabled = page == nil
	end)

	local lastSlow = 0
	RunService.RenderStepped:Connect(function()
		updateStamina()
		updatePips()
		updateRun()
		updateFlow()
		updateWaypoint()
		if timerEnds then
			local left = timerEnds - os.clock()
			ui.Timer.Visible = true
			ui.Timer.Text = ("⏱ %s"):format(Format.Time(math.max(left, 0)))
			ui.Timer.TextColor3 = if left < 10 then C.Bad else C.Text
			if left < -2 then
				timerEnds = nil
			end
		else
			ui.Timer.Visible = false
		end
		if os.clock() - lastSlow > 0.2 then
			lastSlow = os.clock()
			updateHint()
		end
	end)
	updateProfile()
end

return Hud

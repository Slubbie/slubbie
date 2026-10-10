-- The comet stabilization minigame.
--
--   Stage 1 · Energy Lock — a light circles the dial; press as it crosses the
--             glowing zone.
--   Stage 2 · Stabilize   — hold to charge, release while the level sits in
--             the drifting band (holding too long overcharges).
--   Stage 3 · Contain     — the core seals; rewards appear.
--
-- Feedback is instant: the client scores each press with the same shared
-- CaptureMath the server uses and moves straight on, while the server
-- re-scores every press and owns the outcome. If they ever disagree (very
-- high lag), the server's answer wins and the player sees why.
--
-- Works with keyboard/mouse (Space, E, click), gamepad (A, R2) and touch
-- (a big on-screen button; tap or hold). Movement is paused while stabilizing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CaptureMath = require(Shared.CaptureMath)
local GameConfig = require(Shared.GameConfig)
local RemoteDefinitions = require(Shared.RemoteDefinitions)
local Signal = require(Shared.Signal)
local UITheme = require(Shared.UITheme)

local CaptureController = {}

-- (result) — the server confirmed a capture: { Rank, Quality, Stardust, XP, CoreId }
CaptureController.Captured = Signal.new()
CaptureController.Active = false

local TICKS = 48
local DIAL = 250
local TICK_RADIUS = 108
local METER_HEIGHT = 230

local REASONS: { [string]: string } = {
	TooFar = "Get a little closer to the comet.",
	Expired = "That comet has faded.",
	StillFalling = "Wait for it to land!",
	AlreadyClaimed = "You've already captured this comet.",
	Cooldown = "The comet is still settling — try again in a moment.",
	CoreStorageFull = "Your core storage is full. Open some cores first!",
	NotYours = "That comet belongs to someone else's guide.",
	Locked = "You haven't unlocked this area yet.",
	ComingSoon = "This area isn't charted yet.",
	NoCharacter = "Respawning — try again in a second.",
	RateLimited = "Slow down a little!",
	NotReady = "Still loading your save…",
	Desync = "The signal dropped. Try again!",
	NoSession = "The signal dropped. Try again!",
	ServerError = "Something went wrong. Try again!",
}

local MISS_TEXT: { [string]: string } = {
	Early = "Too early!",
	Late = "Too late!",
	TooFast = "Too quick!",
	Overcharged = "Overcharged!",
	Undercharged = "Not enough charge!",
	Timeout = "Too slow!",
}

local controllers: { [string]: any } = {}
local Components: any
local gui: ScreenGui
local panel: Frame
local titleLabel: TextLabel
local hintLabel: TextLabel
local feedbackLabel: TextLabel
local stagePips: { Frame } = {}
local missPips: { Frame } = {}
local dial: Frame
local ticks: { Frame } = {}
local orb: Frame
local orbTrail: { Frame } = {}
local centerIcon: TextLabel
local meter: Frame
local band: Frame
local bandCenterLine: Frame
local fill: Frame
local touchButton: TextButton
local touchLabel: TextLabel
local cancelButton: TextButton
local resultCard: Frame
local resultRank: TextLabel
local resultReward: TextLabel
local panelScale: UIScale

-- Session state
type Session = {
	Id: number,
	CometId: string,
	Params: CaptureMath.Params,
	ClientStart: number,
	Stage: number,
	Attempt: number,
	AttemptStart: number,
	Misses: number,
	HoldStart: number?,
	Finished: boolean,
	IsTutorial: boolean,
}
local session: Session? = nil
local unbindInput: (() -> ())? = nil
local renderConnection: RBXScriptConnection? = nil
local zoneAttempt = -1
local lastTickSound = 0
local beam: Beam? = nil

local function clientTime(s: Session): number
	return os.clock() - s.ClientStart
end

-- UI ---------------------------------------------------------------------------------

local function setFeedback(text: string, color: Color3)
	feedbackLabel.Text = text
	feedbackLabel.TextColor3 = color
	feedbackLabel.TextTransparency = 0
	Components.Pop(feedbackLabel, 0.25)
	task.delay(0.9, function()
		if feedbackLabel.Text == text then
			Components.Tween(feedbackLabel, 0.3, { TextTransparency = 1 })
		end
	end)
end

local function shakePanel()
	if Components.ReducedMotion then
		return
	end
	task.spawn(function()
		local origin = UDim2.fromScale(0.5, 0.62)
		for i = 1, 6 do
			panel.Position = origin + UDim2.fromOffset((if i % 2 == 0 then 1 else -1) * (8 - i), 0)
			task.wait(0.03)
		end
		panel.Position = origin
	end)
end

local function setStage(stage: number)
	for i, pip in stagePips do
		pip.BackgroundColor3 = if i < stage
			then UITheme.Colors.Green
			elseif i == stage then UITheme.Colors.Cyan
			else UITheme.Colors.PanelSunken
	end
	dial.Visible = stage == 1
	meter.Visible = stage == 2
	resultCard.Visible = stage == 3
	local input = controllers.InputController
	if stage == 1 then
		hintLabel.Text = `{input.CaptureText()} when the light crosses the glowing zone`
		touchLabel.Text = "TAP"
	elseif stage == 2 then
		hintLabel.Text = `{input.HoldText()} to charge — release inside the band`
		touchLabel.Text = "HOLD"
	else
		hintLabel.Text = ""
	end
	touchButton.Visible = stage < 3 and input.Device == "Touch"
end

local function setMisses(misses: number, allowed: number)
	for i, pip in missPips do
		pip.Visible = allowed < 20 and i <= allowed + 1
		pip.BackgroundColor3 = if i <= (allowed + 1 - misses) then UITheme.Colors.Coral else UITheme.Colors.PanelSunken
	end
end

local function colorTicks(params: CaptureMath.Params, attempt: number)
	local center = CaptureMath.ZoneCenter(params, attempt)
	for i, tick in ticks do
		local angle = (i - 1) / TICKS * 360
		local delta = math.abs((angle - center + 180) % 360 - 180)
		if delta <= params.ZoneHalfWidth then
			local closeness = 1 - delta / params.ZoneHalfWidth
			tick.BackgroundColor3 = UITheme.Colors.Gold:Lerp(UITheme.Colors.Cyan, closeness)
			tick.BackgroundTransparency = 0
			tick.Size = UDim2.fromOffset(6, 14 + closeness * 10)
		else
			tick.BackgroundColor3 = UITheme.Colors.Stroke
			tick.BackgroundTransparency = 0.3
			tick.Size = UDim2.fromOffset(4, 12)
		end
	end
end

local function placeOnDial(object: GuiObject, angle: number, radius: number)
	local a = math.rad(angle)
	object.Position = UDim2.new(0.5, math.sin(a) * radius, 0.5, -math.cos(a) * radius)
end

local function buildUI()
	Components = controllers.Components
	local Make = Components.Make
	gui = Components.Screen("CaptureUI", 20)
	panel = Make("Frame", {
		Name = "Minigame",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromOffset(340, 430),
		BackgroundColor3 = UITheme.Colors.Panel,
		BackgroundTransparency = 0.12,
		Visible = false,
		Parent = gui,
	})
	Components.Corner(26).Parent = panel
	Components.Stroke(UITheme.Colors.Cyan, 2, 0.45).Parent = panel
	Components.Gradient(Color3.fromHex("#1C2652"), UITheme.Colors.Background).Parent = panel
	panelScale = Make("UIScale", { Parent = panel })

	titleLabel = Components.Label({
		Text = "Stabilize the comet",
		Font = UITheme.Fonts.Display,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, -60, 0, 30),
		Position = UDim2.fromOffset(30, 12),
		Parent = panel,
	})
	cancelButton = Make("TextButton", {
		Text = "✕",
		Font = UITheme.Fonts.Heading,
		TextSize = 18,
		TextColor3 = UITheme.Colors.Muted,
		BackgroundColor3 = UITheme.Colors.PanelRaised,
		Size = UDim2.fromOffset(32, 32),
		Position = UDim2.new(1, -12, 0, 12),
		AnchorPoint = Vector2.new(1, 0),
		Parent = panel,
	})
	Components.Round().Parent = cancelButton

	local pips = Make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 10),
		Position = UDim2.fromOffset(0, 48),
		Parent = panel,
	})
	Components.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center).Parent = pips
	for i = 1, 3 do
		local pip = Make("Frame", {
			Size = UDim2.fromOffset(46, 8),
			BackgroundColor3 = UITheme.Colors.PanelSunken,
			LayoutOrder = i,
			Parent = pips,
		})
		Components.Round().Parent = pip
		stagePips[i] = pip
	end

	-- Stage 1 dial
	dial = Make("Frame", {
		Name = "Dial",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(DIAL, DIAL),
		BackgroundColor3 = UITheme.Colors.Background,
		BackgroundTransparency = 0.25,
		Parent = panel,
	})
	Components.Round().Parent = dial
	Components.Stroke(UITheme.Colors.Stroke, 3, 0.1).Parent = dial
	for i = 1, TICKS do
		local tick = Make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(4, 12),
			Rotation = (i - 1) / TICKS * 360,
			BackgroundColor3 = UITheme.Colors.Stroke,
			BorderSizePixel = 0,
			Parent = dial,
		})
		Components.Round().Parent = tick
		placeOnDial(tick, (i - 1) / TICKS * 360, TICK_RADIUS)
		ticks[i] = tick
	end
	for i = 1, 3 do
		local ghost = Make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(18 - i * 3, 18 - i * 3),
			BackgroundColor3 = UITheme.Colors.Cyan,
			BackgroundTransparency = 0.35 + i * 0.18,
			Parent = dial,
		})
		Components.Round().Parent = ghost
		orbTrail[i] = ghost
	end
	orb = Make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(24, 24),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = dial,
	})
	Components.Round().Parent = orb
	Components.Stroke(UITheme.Colors.Cyan, 3, 0).Parent = orb
	centerIcon = Components.Label({
		Text = "☄️",
		TextSize = 54,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(90, 90),
		Parent = dial,
	})

	-- Stage 2 meter
	meter = Make("Frame", {
		Name = "Meter",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 80),
		Size = UDim2.fromOffset(76, METER_HEIGHT),
		BackgroundColor3 = UITheme.Colors.PanelSunken,
		ClipsDescendants = true,
		Visible = false,
		Parent = panel,
	})
	Components.Corner(20).Parent = meter
	Components.Stroke(UITheme.Colors.Stroke, 3, 0.1).Parent = meter
	local over = Make("Frame", {
		BackgroundColor3 = UITheme.Colors.Coral,
		BackgroundTransparency = 0.6,
		Size = UDim2.new(1, 0, 0, 10),
		BorderSizePixel = 0,
		Parent = meter,
	})
	over.ZIndex = 2
	band = Make("Frame", {
		BackgroundColor3 = UITheme.Colors.Green,
		BackgroundTransparency = 0.35,
		Size = UDim2.new(1, 0, 0, 40),
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = meter,
	})
	Components.Gradient(UITheme.Colors.Green, UITheme.Colors.Cyan).Parent = band
	bandCenterLine = Make("Frame", {
		BackgroundColor3 = UITheme.Colors.Gold,
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.new(1, 0, 0, 3),
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = meter,
	})
	fill = Make("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 5,
		BackgroundTransparency = 0.15,
		Parent = meter,
	})
	Components.Gradient(Color3.new(1, 1, 1), UITheme.Colors.Cyan).Parent = fill

	-- Stage 3 result
	resultCard = Make("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 80),
		Size = UDim2.new(1, 0, 0, 220),
		Visible = false,
		Parent = panel,
	})
	Components.Label({
		Text = "CONTAINED!",
		Font = UITheme.Fonts.Display,
		TextSize = 38,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 50),
		Position = UDim2.fromOffset(0, 40),
		TextColor3 = UITheme.Colors.Cyan,
		Parent = resultCard,
	})
	resultRank = Components.Label({
		Text = "",
		Font = UITheme.Fonts.Display,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.fromOffset(0, 96),
		Parent = resultCard,
	})
	resultReward = Components.Label({
		Text = "",
		Font = UITheme.Fonts.Heading,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = UITheme.Colors.Gold,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, 136),
		Parent = resultCard,
	})

	feedbackLabel = Components.Label({
		Text = "",
		Font = UITheme.Fonts.Display,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 32),
		Position = UDim2.new(0, 0, 1, -96),
		Parent = panel,
	})
	hintLabel = Components.Label({
		Text = "",
		Font = UITheme.Fonts.Bold,
		TextSize = 16,
		TextColor3 = UITheme.Colors.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, -30, 0, 40),
		Position = UDim2.new(0, 15, 1, -62),
		Parent = panel,
	})
	local misses = Make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 10),
		Position = UDim2.new(0, 0, 1, -18),
		Parent = panel,
	})
	Components.List(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center).Parent = misses
	for i = 1, 6 do
		local pip = Make("Frame", {
			Size = UDim2.fromOffset(10, 10),
			BackgroundColor3 = UITheme.Colors.Coral,
			LayoutOrder = i,
			Visible = false,
			Parent = misses,
		})
		Components.Round().Parent = pip
		missPips[i] = pip
	end

	-- Big touch button.
	touchButton = Make("TextButton", {
		Name = "TouchAction",
		Text = "",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -40, 1, -50),
		Size = UDim2.fromOffset(140, 140),
		BackgroundColor3 = UITheme.Colors.Cyan,
		Visible = false,
		Parent = gui,
	})
	Components.Round().Parent = touchButton
	Components.Stroke(Color3.new(1, 1, 1), 4, 0.3).Parent = touchButton
	touchLabel = Components.Label({
		Text = "TAP",
		Font = UITheme.Fonts.Display,
		TextSize = 34,
		TextColor3 = UITheme.Colors.Background,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = touchButton,
	})
end

-- Flow ---------------------------------------------------------------------------------

local function clearBeam()
	if beam then
		beam:Destroy()
		beam = nil
	end
end

local function attachBeam(cometId: string)
	clearBeam()
	local view = controllers.CometController.Get(cometId)
	local character = Players.LocalPlayer.Character
	local device = character and character:FindFirstChild("CometTether")
	local tip = device and device:FindFirstChild("Tip", true)
	local target = view and view.Core and view.Core:FindFirstChild("TetherTarget")
	if not tip or not target then
		return
	end
	local b = Instance.new("Beam")
	b.Attachment0 = tip :: Attachment
	b.Attachment1 = target :: Attachment
	b.Width0 = 0.3
	b.Width1 = 1.1
	b.LightEmission = 1
	b.FaceCamera = true
	b.Segments = 16
	b.CurveSize0 = 3
	b.Color = ColorSequence.new(UITheme.Colors.Cyan, UITheme.Colors.Lavender)
	b.Transparency = NumberSequence.new(0.2)
	b.Parent = target
	beam = b
end

local function finish(delay: number?)
	local s = session
	session = nil
	CaptureController.Active = false
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	if unbindInput then
		unbindInput()
		unbindInput = nil
	end
	touchButton.Visible = false
	controllers.InputController.SetMovementEnabled(true)
	clearBeam()
	task.delay(delay or 0, function()
		if session == nil or session ~= s then
			if not CaptureController.Active then
				panel.Visible = false
			end
		end
	end)
end

local function abort(reason: string)
	setFeedback(REASONS[reason] or "Try again!", UITheme.Colors.Coral)
	controllers.AudioController.Play("UIError")
	finish(1.2)
end

local function send(s: Session, action: string, t1: number?, t2: number?, onResult: (any) -> ())
	task.spawn(function()
		local ok, result = pcall(function()
			return RemoteDefinitions.GetFunction("CaptureAction"):InvokeServer(s.Id, action, t1, t2)
		end)
		if session ~= s then
			return
		end
		if not ok or type(result) ~= "table" then
			abort("ServerError")
			return
		end
		onResult(result)
	end)
end

local function failAttempt(s: Session, reasonText: string)
	s.Finished = true
	setFeedback(reasonText, UITheme.Colors.Coral)
	hintLabel.Text = `The comet's energy scattered. Try again in {GameConfig.Capture.FailCooldown}s.`
	controllers.AudioController.Play("Miss")
	shakePanel()
	finish(2)
end

-- Server answer for a miss/hit: keep the local prediction unless the server disagrees.
local function reconcile(s: Session, result: any, predictedHit: boolean)
	if not result.Ok then
		abort(result.Reason or "ServerError")
		return
	end
	if result.Failed then
		failAttempt(s, MISS_TEXT[result.MissReason or result.Reason] or "The comet slipped away!")
		return
	end
	if result.Hit ~= predictedHit then
		-- Very high lag can shift a press; adopt the server's state.
		s.Stage = result.Stage or s.Stage
		s.Attempt = result.Attempt or s.Attempt
		s.AttemptStart = result.AttemptStart or s.AttemptStart
		s.Misses = result.Misses or s.Misses
		setStage(s.Stage)
		setMisses(s.Misses, s.Params.MissesAllowed)
	end
end

local function qualityWord(score: number): (string, Color3)
	if score >= 0.9 then
		return "PERFECT!", UITheme.Colors.Cyan
	elseif score >= 0.75 then
		return "GREAT!", UITheme.Colors.Gold
	end
	return "GOOD", UITheme.Colors.Green
end

local function showResult(s: Session, result: any)
	setStage(3)
	local rankColor = UITheme.Colors.Text
	for _, rank in GameConfig.QualityRanks do
		if rank.Id == result.Rank then
			rankColor = rank.Color
		end
	end
	resultRank.Text = `{string.upper(result.Rank or "")} CAPTURE`
	resultRank.TextColor3 = rankColor
	resultReward.Text = `+{result.Stardust} ✦    +{result.XP} XP`
	Components.Pop(resultCard, 0.2)
	controllers.AudioController.Play("Contain")
	controllers.AudioController.Fanfare(if result.Rank == "Perfect" then 3 elseif result.Rank == "Gold" then 2 else 1)
	local view = controllers.CometController.Get(s.CometId)
	if view and view.Core then
		local position = view.Core.CFrame.Position
		controllers.EffectsController.Burst(position, UITheme.Colors.Cyan, 30, "Stars")
		controllers.EffectsController.Shockwave(view.Data.Position, UITheme.Colors.Cyan, 12, 0.5)
		controllers.EffectsController.FloatingText(
			position + Vector3.new(0, 3, 0),
			`+{result.Stardust} ✦`,
			UITheme.Colors.Gold
		)
	end
	CaptureController.Captured:Fire(result)
	finish(1.6)
	task.delay(1.1, function()
		local settings = controllers.ClientState.Settings()
		if settings.AutoOpenCores ~= false and result.CoreId then
			controllers.RevealController.Open(result.CoreId)
		elseif result.CoreId then
			controllers.NotificationController.Toast("Sealed core stored — open it from your Inventory.", "☄️")
		end
	end)
end

local function press()
	local s = session
	if not s or s.Finished then
		return
	end
	local t = clientTime(s)
	if s.Stage == 1 then
		if t < s.AttemptStart then
			return -- the dial hasn't started yet
		end
		local predicted = CaptureMath.ScoreLock(s.Params, s.Attempt, t - s.AttemptStart)
		if predicted.Hit then
			local word, color = qualityWord(predicted.Score)
			setFeedback(word, color)
			controllers.AudioController.Play("LockHit")
			Components.Pop(dial, 0.08)
			s.Stage = 2
			s.Attempt = 1
			s.AttemptStart = t + s.Params.TransitionTime
			setStage(2)
		else
			s.Misses += 1
			setFeedback(MISS_TEXT[predicted.Reason or "Early"] or "Miss!", UITheme.Colors.Coral)
			controllers.AudioController.Play("Miss")
			shakePanel()
			setMisses(s.Misses, s.Params.MissesAllowed)
			s.Attempt += 1
			s.AttemptStart = t + s.Params.MissPause
		end
		send(s, "Lock", t, nil, function(result)
			reconcile(s, result, predicted.Hit)
		end)
	elseif s.Stage == 2 then
		if t < s.AttemptStart or s.HoldStart then
			return
		end
		s.HoldStart = t
		controllers.AudioController.Play("Charge")
	end
end

local function release()
	local s = session
	if not s or s.Finished or s.Stage ~= 2 or not s.HoldStart then
		return
	end
	local holdStart = s.HoldStart :: number
	s.HoldStart = nil
	local t = clientTime(s)
	local predicted = CaptureMath.ScoreRelease(s.Params, s.Attempt, holdStart - s.AttemptStart, t - s.AttemptStart)
	if predicted.Hit then
		s.Finished = true
		local word, color = qualityWord(predicted.Score)
		setFeedback(word, color)
		hintLabel.Text = "Containing…"
		controllers.AudioController.Play("LockHit", { Pitch = 2.4 })
	else
		s.Misses += 1
		setFeedback(MISS_TEXT[predicted.Reason or "Overcharged"] or "Miss!", UITheme.Colors.Coral)
		controllers.AudioController.Play("Miss")
		shakePanel()
		setMisses(s.Misses, s.Params.MissesAllowed)
		s.Attempt += 1
		s.AttemptStart = t + s.Params.MissPause
		fill.Size = UDim2.fromScale(1, 0)
	end
	send(s, "Release", holdStart, t, function(result)
		if result.Ok and result.Complete then
			showResult(s, result)
		else
			reconcile(s, result, predicted.Hit)
			if predicted.Hit and result.Ok and not result.Complete and not result.Failed then
				s.Finished = false
			end
		end
	end)
end

local function render()
	local s = session
	if not s then
		return
	end
	local t = clientTime(s)
	local rel = t - s.AttemptStart
	if s.Stage == 1 then
		if zoneAttempt ~= s.Attempt then
			zoneAttempt = s.Attempt
			colorTicks(s.Params, s.Attempt)
		end
		local angle = CaptureMath.DialAngle(s.Params, math.max(rel, 0))
		placeOnDial(orb, angle, TICK_RADIUS)
		for i, ghost in orbTrail do
			placeOnDial(ghost, angle - i * 7, TICK_RADIUS)
		end
		orb.Visible = rel >= 0
		for _, ghost in orbTrail do
			ghost.Visible = rel >= 0
		end
		centerIcon.Rotation = math.sin(os.clock() * 3) * 8
		-- A soft tick as the light enters the zone.
		local zone = CaptureMath.ZoneCenter(s.Params, s.Attempt)
		local delta = math.abs((angle - zone + 180) % 360 - 180)
		if rel >= 0 and delta <= s.Params.ZoneHalfWidth and os.clock() - lastTickSound > s.Params.DialPeriod * 0.6 then
			lastTickSound = os.clock()
			controllers.AudioController.Play("DialTick")
		end
		if rel > s.Params.StageTimeout and not s.Finished then
			failAttempt(s, "Too slow!")
		end
	elseif s.Stage == 2 then
		local center = CaptureMath.BandCenter(s.Params, s.Attempt, math.max(rel, 0))
		local half = s.Params.BandHalfWidth
		band.Size = UDim2.new(1, 0, 0, half * 2 * METER_HEIGHT)
		band.Position = UDim2.new(0, 0, 0, (1 - center - half) * METER_HEIGHT)
		bandCenterLine.Position = UDim2.new(0, 0, 0, (1 - center) * METER_HEIGHT)
		local holdStart = s.HoldStart
		if holdStart then
			local level, over = CaptureMath.ChargeLevel(s.Params, t - holdStart)
			fill.Size = UDim2.fromScale(1, level)
			fill.BackgroundColor3 = if over then UITheme.Colors.Coral else Color3.new(1, 1, 1)
			if t - holdStart > s.Params.OverchargeTime then
				release()
			end
		elseif not s.Finished then
			fill.Size = UDim2.fromScale(1, 0)
		end
		if rel > s.Params.StageTimeout and not holdStart and not s.Finished then
			failAttempt(s, "Too slow!")
		end
	end
end

-- Starts capturing a comet (called by the comet's prompt).
function CaptureController.Begin(cometId: string)
	if CaptureController.Active then
		return
	end
	local view = controllers.CometController.Get(cometId)
	if not view or view.Claimed or view.State ~= "Landed" then
		return
	end
	CaptureController.Active = true
	controllers.InputController.SetMovementEnabled(false)
	titleLabel.Text = if view.Data.IsTutorial then "Stabilize your first comet" else `{view.Type.DisplayName} Comet`
	feedbackLabel.Text = ""
	hintLabel.Text = "Locking on…"
	setStage(1)
	setMisses(0, 99)
	panel.Visible = true
	if not Components.ReducedMotion then
		panelScale.Scale = 0.85
		Components.Tween(panelScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	attachBeam(cometId)

	local ok, response = pcall(function()
		return RemoteDefinitions.GetFunction("StartCapture"):InvokeServer(cometId)
	end)
	if not CaptureController.Active then
		return
	end
	if not ok or type(response) ~= "table" or not response.Ok then
		abort(if ok and type(response) == "table" then response.Reason else "ServerError")
		return
	end
	local data = response.Session
	local s: Session = {
		Id = data.Id,
		CometId = cometId,
		Params = data.Params,
		ClientStart = os.clock(),
		Stage = 1,
		Attempt = 1,
		AttemptStart = data.AttemptStart,
		Misses = 0,
		HoldStart = nil,
		Finished = false,
		IsTutorial = data.IsTutorial == true,
	}
	session = s
	zoneAttempt = -1
	setStage(1)
	setMisses(0, s.Params.MissesAllowed)
	unbindInput = controllers.InputController.BindCapture(press, release)
	renderConnection = RunService.RenderStepped:Connect(render)
end

function CaptureController.Cancel()
	local s = session
	if s then
		send(s, "Cancel", nil, nil, function() end)
	end
	if CaptureController.Active then
		finish(0)
	end
end

-- Other players' tethers: everyone can see who is stabilizing what.
local otherBeams: { [Player]: Beam } = {}
local function updateOtherTethers()
	for _, player in Players:GetPlayers() do
		if player == Players.LocalPlayer then
			continue
		end
		local character = player.Character
		local target = character and character:GetAttribute("CaptureTarget")
		local existing = otherBeams[player]
		if typeof(target) == "Vector3" and character then
			local tip = character:FindFirstChild("Tip", true)
			if tip and tip:IsA("Attachment") and not existing then
				local holder = Instance.new("Attachment")
				holder.Name = "OtherTetherTarget"
				holder.WorldPosition = target + Vector3.new(0, 2.8, 0)
				holder.Parent = workspace.Terrain
				local b = Instance.new("Beam")
				b.Attachment0 = tip
				b.Attachment1 = holder
				b.Width0 = 0.25
				b.Width1 = 0.8
				b.LightEmission = 1
				b.FaceCamera = true
				b.Color = ColorSequence.new(UITheme.Colors.Lavender)
				b.Transparency = NumberSequence.new(0.35)
				b.Parent = holder
				otherBeams[player] = b
			end
		elseif existing then
			local holder = existing.Attachment1
			existing:Destroy()
			if holder then
				holder:Destroy()
			end
			otherBeams[player] = nil
		end
	end
end

function CaptureController.Init(registry: { [string]: any })
	controllers = registry
end

function CaptureController.Start()
	buildUI()
	cancelButton.Activated:Connect(CaptureController.Cancel)
	touchButton.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			press()
		end
	end)
	touchButton.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			release()
		end
	end)
	-- Respawning mid-capture cancels cleanly.
	Players.LocalPlayer.CharacterAdded:Connect(function()
		if CaptureController.Active then
			CaptureController.Cancel()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			updateOtherTethers()
		end
	end)
end

return CaptureController

-- The table interface.
--
--   Top        one card per subject: name, Trial wins, Integrity (shaped pips
--              plus a number), effects, whose turn, connection.
--   Chamber    the Load as this viewer knows it: spent cells, then every
--              remaining position (CHARGED diamond, HOLLOW ring, unknown slot,
--              "±" for an inverted unknown), the loaded one bracketed; exact
--              remaining counts (or a range when inversions blur them) and the
--              chance the loaded cell is CHARGED (Probability Readout setting).
--   Bottom     on your turn: fire at yourself / cycle target / fire at the
--              target, and your instruments. Fire uses the chosen confirmation
--              (hold, tap, or press twice). Anything unavailable is greyed out
--              with the reason as its tooltip.
--   Also       turn timer, event log (L), private reveals (Lens, Sonar,
--              Precision, Echo), a context hint line, the versus card, the
--              menu (M): settings, emotes, forfeit.
--
-- Every state it shows comes from MatchClient (what the server sent this
-- viewer). Colour is never the only signal: cells have shapes, Integrity has
-- numbers, disabled controls have reasons.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Instruments = require(ReplicatedStorage.Variance.Core.Instruments)
local Modifiers = require(ReplicatedStorage.Variance.Core.Modifiers)
local Probability = require(ReplicatedStorage.Variance.Core.Probability)
local Cosmetics = require(ReplicatedStorage.Variance.Data.Cosmetics)
local Format = require(ReplicatedStorage.Variance.Util.Format)
local Kit = require(script.Parent.Parent.Kit)
local Motion = require(script.Parent.Parent.Motion)
local Theme = require(script.Parent.Parent.Theme)
local Icons = require(script.Parent.Parent.Icons)

local MatchHUD = {}
MatchHUD.__index = MatchHUD

local HOLD_TIME = 0.45
local CONFIRM_WINDOW = 2.2
local MAX_SLOTS = 8
local RARITY_STROKE = { Common = "LineStrong", Uncommon = "Hollow", Rare = "Accent" }
local EFFECT_LABEL = { Dampener = "DAMPENED", Clamped = "CLAMPED", Capacitor = "CAPACITOR", Overclock = "OVERCLOCK" }

local function clearChildren(frame: Instance)
	for _, child in frame:GetChildren() do
		child:Destroy()
	end
end

function MatchHUD.new(ui, controllers)
	local self = setmetatable({}, MatchHUD)
	self.UI = ui
	self.C = controllers
	self.Main = false
	self.Visible = false
	self.Dirty = true
	self.Target = nil
	self.Cards = {}
	self.Hold = nil
	self.Armed = nil
	self.LogOpen = false
	self.LastEmote = 0
	self.LastTick = -1

	local root = Kit.create("Frame", {
		Name = "MatchHUD",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = ui.Hud,
	}) :: Frame
	self.Frame = root

	-- Cards row.
	local cards = Kit.create("Frame", {
		Name = "Cards",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -32, 0, 96),
		Position = UDim2.fromOffset(16, 12),
		Parent = root,
	}) :: Frame
	local cardsLayout = Kit.list(cards, "X", 10, "Center")
	cardsLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	self.CardsFrame = cards

	-- Timer bar under the cards.
	local timer = Kit.bar(root, { Size = UDim2.fromOffset(420, 4), Value = 1 })
	timer.AnchorPoint = Vector2.new(0.5, 0)
	timer.Position = UDim2.new(0.5, 0, 0, 114)
	timer.Visible = false
	self.TimerBar = timer
	self.TimerText = Kit.label(root, {
		Text = "",
		Font = "Mono",
		TextSize = "Label",
		XAlign = "Center",
		Size = UDim2.fromOffset(420, 16),
		Position = UDim2.new(0.5, 0, 0, 120),
		AnchorPoint = Vector2.new(0.5, 0),
		Color = "Dim",
	})

	-- Trial / modifiers (top-left).
	local info = Kit.create("Frame", {
		Name = "Info",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(260, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.fromOffset(16, 118),
		Parent = root,
	}) :: Frame
	Kit.list(info, "Y", 4)
	self.TrialLabel =
		Kit.label(info, { Text = "", Font = "Mono", TextSize = "Label", Color = "Accent", LayoutOrder = 1 })
	self.ModeLabel = Kit.label(info, { Text = "", Font = "Mono", TextSize = "Tiny", Color = "Dim", LayoutOrder = 2 })
	self.Chips = Kit.create("Frame", {
		Name = "Chips",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3,
		Parent = info,
	}) :: Frame
	local chipGrid = Kit.list(self.Chips, "Y", 3)
	chipGrid.HorizontalAlignment = Enum.HorizontalAlignment.Left
	self.SpectateTag = Kit.label(
		info,
		{ Text = "", Font = "Mono", TextSize = "Tiny", Color = "Warn", LayoutOrder = 4, Wrap = true, AutoY = true }
	)

	-- Chamber panel: low over the table, right above the fire controls, so the
	-- odds sit where you decide and your opponent's face stays in view.
	local chamber = Kit.panel(root, {
		Name = "Chamber",
		Size = UDim2.fromOffset(480, 88),
		Position = UDim2.new(0.5, 0, 1, -208),
		AnchorPoint = Vector2.new(0.5, 1),
		Color = "Panel",
		Transparency = 0.2,
	})
	Kit.padding(chamber, 8, 14)
	self.Chamber = chamber
	local track = Kit.create(
		"Frame",
		{ Name = "Track", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), Parent = chamber }
	) :: Frame
	local trackLayout = Kit.list(track, "X", 4, "Center")
	trackLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	self.Track = track
	self.Counts = Kit.label(chamber, {
		Text = "",
		Font = "Mono",
		TextSize = "Label",
		XAlign = "Center",
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.fromOffset(0, 44),
		Rich = true,
	})
	self.Odds = Kit.label(chamber, {
		Text = "",
		Font = "Bold",
		TextSize = "Body",
		XAlign = "Center",
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.fromOffset(0, 60),
		Rich = true,
	})

	-- Callout (private reveals).
	local callout = Kit.panel(root, {
		Name = "Callout",
		Size = UDim2.fromOffset(360, 70),
		Position = UDim2.new(0.5, 0, 0.5, -60),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		Color = "Bg",
		Transparency = 0.1,
	})
	Kit.stroke(callout, "Accent", 2, 0)
	self.CalloutGlyph = Kit.create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(48, 48),
		Position = UDim2.new(0, 12, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = callout,
	}) :: Frame
	self.CalloutTitle = Kit.label(callout, {
		Text = "",
		Font = "Mono",
		TextSize = "Label",
		Color = "Dim",
		Size = UDim2.new(1, -80, 0, 18),
		Position = UDim2.fromOffset(70, 12),
	})
	self.CalloutText = Kit.label(callout, {
		Text = "",
		Font = "Display",
		TextSize = "Title",
		Color = "Text",
		Size = UDim2.new(1, -80, 0, 28),
		Position = UDim2.fromOffset(70, 30),
	})
	self.Callout = callout

	-- Hint line.
	self.Hint = Kit.label(root, {
		Text = "",
		Font = "Mono",
		TextSize = "Small",
		XAlign = "Center",
		Color = "Dim",
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0, 0, 1, -196),
		Rich = true,
	})

	-- Action bar.
	local actions = Kit.create("Frame", {
		Name = "Actions",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(760, 52),
		Position = UDim2.new(0.5, 0, 1, -128),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = root,
	}) :: Frame
	self.Actions = actions
	self.FireSelf = self:fireButton(actions, "FireSelf", "FIRE AT SELF", UDim2.fromOffset(0, 0))
	self.FireOther = self:fireButton(actions, "FireOther", "FIRE AT OPPONENT", UDim2.new(1, -250, 0, 0))
	local selector = Kit.create("Frame", {
		Name = "Target",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(240, 52),
		Position = UDim2.new(0.5, 0, 0, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = actions,
	}) :: Frame
	self.TargetName = Kit.label(selector, {
		Text = "",
		Font = "Mono",
		TextSize = "Label",
		XAlign = "Center",
		Size = UDim2.new(1, -80, 1, 0),
		Position = UDim2.fromOffset(40, 0),
	})
	self.PrevTarget = Kit.button(selector, {
		Text = "<",
		Size = UDim2.fromOffset(34, 34),
		Position = UDim2.new(0, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Sound = "Tick",
		Tooltip = "Previous target",
		OnClick = function()
			self:cycleTarget(-1)
		end,
	})
	self.NextTarget = Kit.button(selector, {
		Text = ">",
		Size = UDim2.fromOffset(34, 34),
		Position = UDim2.new(1, 0, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Sound = "Tick",
		Tooltip = "Next target",
		OnClick = function()
			self:cycleTarget(1)
		end,
	})
	self.Selector = selector

	-- Instrument bar.
	local slots = Kit.create("Frame", {
		Name = "Slots",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(760, 66),
		Position = UDim2.new(0.5, 0, 1, -40),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = root,
	}) :: Frame
	Kit.list(slots, "X", 6, "Center")
	self.SlotsFrame = slots
	self.Slots = {}
	for i = 1, MAX_SLOTS do
		self.Slots[i] = self:slotButton(slots, i)
	end

	-- Log.
	local log = Kit.panel(root, {
		Name = "Log",
		Size = UDim2.fromOffset(300, 260),
		Position = UDim2.new(1, -16, 0, 118),
		AnchorPoint = Vector2.new(1, 0),
		Color = "Panel",
		Transparency = 0.2,
		Visible = false,
	})
	Kit.padding(log, 8, 10)
	Kit.header(log, "EVENT LOG", 0)
	self.LogList = Kit.create(
		"Frame",
		{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -28), Position = UDim2.fromOffset(0, 28), Parent = log }
	) :: Frame
	Kit.list(self.LogList, "Y", 2)
	self.Log = log

	-- Corner buttons.
	local corner = Kit.create("Frame", {
		Name = "Corner",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.new(1, -16, 1, -16),
		AnchorPoint = Vector2.new(1, 1),
		Parent = root,
	}) :: Frame
	Kit.list(corner, "X", 6, "Right")
	Kit.button(corner, {
		Text = "LOG",
		Size = UDim2.fromOffset(64, 34),
		Style = "Ghost",
		LayoutOrder = 1,
		Hotkey = nil,
		Tooltip = "Event log",
		OnClick = function()
			self:toggleLog()
		end,
	})
	Kit.button(corner, {
		Text = "EMOTE",
		Size = UDim2.fromOffset(80, 34),
		Style = "Ghost",
		LayoutOrder = 2,
		Tooltip = "Table emote",
		OnClick = function()
			self:emoteMenu()
		end,
	})
	Kit.button(corner, {
		Text = "MENU",
		Size = UDim2.fromOffset(74, 34),
		Style = "Ghost",
		LayoutOrder = 3,
		Tooltip = "Settings, leave",
		OnClick = function()
			self:menu()
		end,
	})
	self.Corner = corner

	-- Versus card (match start).
	self.Versus = Kit.create("Frame", {
		Name = "Versus",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 40,
		Parent = root,
	}) :: Frame

	self:wire()
	return self
end

---------------------------------------------------------------------------
-- Building blocks
---------------------------------------------------------------------------

function MatchHUD:fireButton(parent: Frame, actionId: string, text: string, position: UDim2): TextButton
	local button = Kit.button(parent, {
		Name = actionId,
		Text = text,
		Size = UDim2.fromOffset(250, 52),
		Position = position,
		Style = if actionId == "FireOther" then "Danger" else "Default",
		Font = "Bold",
		TextSize = "Body",
		Sound = "Confirm",
	})
	local fill = Kit.create("Frame", {
		Name = "HoldFill",
		BorderSizePixel = 0,
		BackgroundTransparency = 0.55,
		Size = UDim2.fromScale(0, 1),
		ZIndex = 2,
		Parent = button,
	}) :: Frame
	Theme.bind(fill, "BackgroundColor3", if actionId == "FireOther" then "Bad" else "Accent")
	Kit.corner(fill, 3)
	local cap = Kit.keycap(button, "", 0)
	cap.Name = "Key"
	cap.AnchorPoint = Vector2.new(1, 0.5)
	cap.Position = UDim2.new(1, -8, 0.5, 0)
	cap.ZIndex = 4
	-- Pointer / touch: hold semantics live here too.
	button.MouseButton1Down:Connect(function()
		self:pressFire(actionId, "Begin")
	end)
	button.MouseButton1Up:Connect(function()
		self:pressFire(actionId, "End")
	end)
	button.MouseLeave:Connect(function()
		if self.Hold and self.Hold.Action == actionId and self.Hold.Pointer then
			self:cancelHold()
		end
	end)
	button.Activated:Connect(function(input)
		-- Gamepad selection + A (a press with no duration to hold).
		if
			input
			and input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			self:pressFire(actionId, "Begin", true)
		end
	end)
	return button
end

function MatchHUD:slotButton(parent: Frame, index: number)
	local button = Kit.button(parent, {
		Name = "Slot" .. index,
		Text = "",
		Size = UDim2.fromOffset(84, 66),
		LayoutOrder = index,
		Sound = "Click",
		OnClick = function()
			self:useSlot(index)
		end,
	})
	button.Visible = false
	local icon = Kit.create("Frame", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.new(0.5, 0, 0, 6),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 3,
		Parent = button,
	}) :: Frame
	local name = Kit.label(button, {
		Name = "Name",
		Text = "",
		Font = "Mono",
		TextSize = "Tiny",
		XAlign = "Center",
		Size = UDim2.new(1, -4, 0, 14),
		Position = UDim2.new(0, 2, 1, -18),
		ZIndex = 3,
	})
	local cap = Kit.keycap(button, tostring(index), 0)
	cap.Name = "Key"
	cap.Position = UDim2.fromOffset(4, 4)
	cap.ZIndex = 4
	-- Rarity rim (separate from the button's own hover stroke).
	local rim = Kit.create("Frame", {
		Name = "Rim",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -4, 1, -4),
		Position = UDim2.fromOffset(2, 2),
		ZIndex = 2,
		Parent = button,
	}) :: Frame
	Kit.corner(rim, 3)
	local stroke = Kit.stroke(rim, "Line", 1, 0.2)
	button.MouseEnter:Connect(function()
		self:focusSlot(index)
	end)
	button.MouseLeave:Connect(function()
		self:focusSlot(nil)
	end)
	button.SelectionGained:Connect(function()
		self:focusSlot(index)
	end)
	button.SelectionLost:Connect(function()
		self:focusSlot(nil)
	end)
	return { Button = button, Icon = icon, Name = name, Stroke = stroke, Id = nil }
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------

local function scene(self)
	return self.C.MatchClient.Scene
end

local function st(self)
	return self.C.MatchClient.State
end

function MatchHUD:opponents(): { number }
	return self.C.MatchClient:opponents()
end

function MatchHUD:target(): number?
	local opponents = self:opponents()
	if self.Target and table.find(opponents, self.Target) then
		return self.Target
	end
	self.Target = opponents[1]
	return self.Target
end

function MatchHUD:cycleTarget(direction: number)
	local opponents = self:opponents()
	if #opponents < 2 then
		return
	end
	local index = table.find(opponents, self:target() :: number) or 1
	index = ((index - 1 + direction) % #opponents) + 1
	self.Target = opponents[index]
	self.C.AudioController:play("Tick")
	self.Dirty = true
end

-- Whether a fire action is available right now, and why not.
function MatchHUD:canFire(actionId: string): (boolean, string?)
	local client = self.C.MatchClient
	if client:spectating() then
		return false, "Spectating."
	end
	if not client:isMyTurn() then
		return false, "Wait for your turn."
	end
	if client:busy() then
		return false, "Resolving..."
	end
	local tutorial = self.C.TutorialController
	if tutorial:active() and not tutorial:allows(if actionId == "FireSelf" then "FireSelf" else "FireOpponent") then
		return false, "Not in this step of the lesson."
	end
	if actionId == "FireOther" and self:target() == nil then
		return false, "No opponent standing."
	end
	return true
end

function MatchHUD:fire(actionId: string)
	local ok, reason = self:canFire(actionId)
	if not ok then
		self.C.AudioController:play("Deny")
		if reason then
			self.UI:toast("NOT NOW", reason, "Warn")
		end
		return
	end
	local target = if actionId == "FireSelf" then self.C.MatchClient:you() else self:target()
	self.Armed = nil
	self.C.MatchClient:act("Fire", target, nil)
	self.C.AudioController:play("Confirm")
	self.Dirty = true
end

function MatchHUD:cancelHold()
	local hold = self.Hold
	self.Hold = nil
	if hold then
		local button = if hold.Action == "FireSelf" then self.FireSelf else self.FireOther
		local fill = button:FindFirstChild("HoldFill") :: Frame
		Motion.tween(fill, 0.15, { Size = UDim2.fromScale(0, 1) })
	end
end

-- Keyboard / gamepad / pointer presses on a fire control, honouring the
-- player's confirmation setting.
-- `instant` presses can't be held (gamepad A on a focused button), so Hold
-- falls back to press-twice.
function MatchHUD:pressFire(actionId: string, phase: string, instant: boolean?)
	local mode = self.C.SettingsController:get("FireConfirm") or "Hold"
	if instant and mode == "Hold" then
		mode = "Confirm"
	end
	if phase == "End" then
		if self.Hold and self.Hold.Action == actionId then
			self:cancelHold()
		end
		return
	end
	local ok, reason = self:canFire(actionId)
	if not ok then
		self.C.AudioController:play("Deny")
		local button = if actionId == "FireSelf" then self.FireSelf else self.FireOther
		Motion.shake(button, 5, 0.2)
		if reason and self.C.MatchClient:isMyTurn() then
			self.UI:toast("NOT NOW", reason, "Warn")
		end
		return
	end
	if mode == "Tap" then
		self:fire(actionId)
	elseif mode == "Confirm" then
		if self.Armed and self.Armed.Action == actionId and os.clock() - self.Armed.At < CONFIRM_WINDOW then
			self:fire(actionId)
		else
			self.Armed = { Action = actionId, At = os.clock() }
			self.C.AudioController:play("Tick")
			self.Dirty = true
		end
	else
		self.Hold = { Action = actionId, Start = os.clock(), Pointer = true }
		self.C.AudioController:play("Aim", { Volume = 0.5 })
	end
end

function MatchHUD:useSlot(index: number)
	local client = self.C.MatchClient
	local me = client:subject(client:you())
	if me == nil or client:spectating() then
		return
	end
	local id = me.Instruments[index]
	if id == nil then
		return
	end
	local ok, reason = self:slotState(index, id)
	if not ok then
		self.C.AudioController:play("Deny")
		self.UI:toast(string.upper(id), reason or "Unavailable.", "Warn")
		return
	end
	local def = Instruments.get(id)
	task.spawn(function()
		if def and def.Rarity == "Rare" and self.C.SettingsController:get("ConfirmItems") ~= false then
			local sure = Kit.confirm(def.Name, def.Description .. "\n\n" .. def.Visibility, "USE", true)
			if not sure then
				return
			end
		end
		local target = if def and def.Targeted then self:target() else nil
		local sent, why = client:act("Use", target, index)
		if not sent then
			self.UI:toast("NOT NOW", why or "", "Warn")
		end
		self.Dirty = true
	end)
end

-- Whether an instrument can be used, and why not (from the server's legal set).
function MatchHUD:slotState(index: number, id: string): (boolean, string?)
	local client = self.C.MatchClient
	if not client:isMyTurn() then
		return false, "Only on your turn."
	end
	if client:busy() then
		return false, "Resolving..."
	end
	local tutorial = self.C.TutorialController
	if tutorial:active() and not tutorial:allows("Use", id) then
		return false, "Not in this step of the lesson."
	end
	local def = Instruments.get(id)
	local legal = client:legal("Use", index, if def and def.Targeted then self:target() else nil)
	if legal == nil then
		return false, "Unavailable."
	end
	if legal.Id ~= nil and legal.Id ~= id then
		return false, "That instrument moved."
	end
	if legal.Ok == false then
		return false, legal.Reason or "Unavailable."
	end
	return true
end

function MatchHUD:focusSlot(index: number?)
	local presenter = self.C.MatchPresenter
	local view = presenter:tableView()
	if view then
		view:highlight(if index then self.C.MatchClient:you() else nil, index)
	end
end

function MatchHUD:toggleLog()
	self.LogOpen = not self.LogOpen
	self.Log.Visible = self.LogOpen
	self.Dirty = true
end

---------------------------------------------------------------------------
-- Menus
---------------------------------------------------------------------------

function MatchHUD:menu()
	local client = self.C.MatchClient
	task.spawn(function()
		local spectating = client:spectating()
		local tutorial = self.C.TutorialController:active()
		local ranked = scene(self) and scene(self).Rules and scene(self).Rules.Ranked
		local leaveText = if spectating then "STOP WATCHING" elseif tutorial then "QUIT LESSON" else "FORFEIT"
		local choice = Kit.modal(
			"MENU",
			if spectating then "You are watching a live Trial." else "The Trial keeps running while this is open.",
			{
				{ Text = "SETTINGS", Style = "Default", Value = "Settings" },
				{ Text = leaveText, Style = "Danger", Value = "Leave" },
				{ Text = "RESUME", Style = "Primary", Value = "Resume" },
			}
		)
		if choice == "Settings" then
			self.UI:open("Settings")
		elseif choice == "Leave" then
			if spectating then
				self.C.SpectatorController:stop()
			elseif tutorial then
				self.C.TutorialController:quit()
			else
				local warning = "Leaving now counts as a loss."
				if ranked then
					warning ..= " In a ranked Trial it also costs Standing and adds an abandon strike."
				end
				if Kit.confirm("FORFEIT THE TRIAL?", warning, "FORFEIT", true) then
					self.C.NetworkClient:request("Match.Forfeit")
				end
			end
		end
	end)
end

function MatchHUD:emoteMenu()
	local client = self.C.MatchClient
	if client:spectating() or os.clock() - self.LastEmote < 3 then
		return
	end
	local profile = self.C.ProfileController:get()
	local owned = {}
	for id in profile and profile.Cosmetics.Owned or {} do
		local item = Cosmetics.get(id)
		if item and item.Category == "Emote" then
			table.insert(owned, item)
		end
	end
	table.sort(owned, function(a, b)
		return a.Name < b.Name
	end)
	if #owned == 0 then
		return
	end
	task.spawn(function()
		local buttons = {}
		for i = 1, math.min(#owned, 3) do
			table.insert(buttons, { Text = owned[i].Name, Style = "Default", Value = owned[i].Id })
		end
		if #owned > 3 then
			-- Rotate through the rest next time.
			table.insert(owned, table.remove(owned, 1))
		end
		local choice = Kit.modal("TABLE EMOTE", "Everyone at the table sees it.", buttons)
		if type(choice) == "string" then
			self.LastEmote = os.clock()
			self.C.NetworkClient:request("Match.Emote", choice)
		end
	end)
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------

local function glyphKind(cell): string
	if cell.Known then
		return cell.Known
	end
	return if cell.Parity == 1 then "~" else "?"
end

function MatchHUD:buildCards()
	for _, card in self.Cards do
		card.Frame:Destroy()
	end
	self.Cards = {}
	local sc = scene(self)
	if sc == nil then
		return
	end
	local ids = {}
	for id in sc.Subjects do
		table.insert(ids, id)
	end
	local you = sc.You
	table.sort(ids, function(a, b)
		if a == you then
			return true
		elseif b == you then
			return false
		end
		return a < b
	end)
	local count = #ids
	local width = if count > 2 then 250 else 320
	for order, id in ids do
		local info = sc.Subjects[id]
		local card = Kit.panel(self.CardsFrame, {
			Name = "Card" .. id,
			Size = UDim2.fromOffset(width, 90),
			LayoutOrder = order,
			Color = "Panel",
			Transparency = 0.1,
		})
		Kit.padding(card, 8, 12)
		local stroke = card:FindFirstChildOfClass("UIStroke")
		local name = Kit.label(
			card,
			{ Text = string.upper(info.Name or "?"), Font = "Bold", TextSize = "Body", Size = UDim2.new(1, -60, 0, 20) }
		)
		local sub = info.Title or ""
		if info.IsAI then
			sub = string.format("%s  ·  %s", info.Title or "SURROGATE", string.upper(info.Difficulty or ""))
		elseif info.Level then
			sub = string.format("CLEARANCE %d%s", info.Level, if info.Division then "  ·  " .. info.Division else "")
		end
		Kit.label(card, {
			Text = sub,
			Font = "Mono",
			TextSize = "Tiny",
			Color = "Dim",
			Size = UDim2.new(1, -60, 0, 14),
			Position = UDim2.fromOffset(0, 20),
		})
		local wins = Kit.label(card, {
			Text = "",
			Font = "Mono",
			TextSize = "Label",
			XAlign = "Right",
			Color = "Accent",
			Size = UDim2.fromOffset(60, 20),
			Position = UDim2.new(1, -60, 0, 0),
		})
		local pips = Kit.pips(card, 1, 1, Vector2.new(16, 20))
		pips.Position = UDim2.fromOffset(0, 40)
		local integrity = Kit.label(card, {
			Text = "",
			Font = "Mono",
			TextSize = "Label",
			Color = "Text",
			Size = UDim2.fromOffset(60, 20),
			Position = UDim2.new(1, -60, 0, 40),
			XAlign = "Right",
		})
		local status = Kit.label(card, {
			Text = "",
			Font = "Mono",
			TextSize = "Tiny",
			Color = "Warn",
			Size = UDim2.new(1, 0, 0, 14),
			Position = UDim2.fromOffset(0, 64),
			Rich = true,
		})
		local turn = Kit.create("Frame", {
			Name = "Turn",
			BorderSizePixel = 0,
			Size = UDim2.new(1, 24, 0, 3),
			Position = UDim2.new(0, -12, 1, 5),
			Visible = false,
			Parent = card,
		}) :: Frame
		Theme.bind(turn, "BackgroundColor3", "Accent")
		self.Cards[id] = {
			Frame = card,
			Name = name,
			Wins = wins,
			Pips = pips,
			Integrity = integrity,
			Status = status,
			Turn = turn,
			Stroke = stroke,
		}
	end
end

function MatchHUD:renderCards()
	local state = st(self)
	local sc = scene(self)
	if state == nil or sc == nil then
		return
	end
	local owner = state.Turn and state.Turn.Owner
	for id, card in self.Cards do
		local s = state.Subjects[id]
		if s then
			local max = s.MaxIntegrity or 0
			local value = s.Integrity or 0
			Kit.setPips(card.Pips, value, max)
			if value <= 1 and max > 0 then
				for _, pip in card.Pips:GetChildren() do
					if pip:IsA("Frame") and pip.LayoutOrder <= value then
						Theme.bind(pip, "BackgroundColor3", "Bad")
					end
				end
			end
			card.Integrity.Text = string.format("%d/%d", value, max)
			local toWin = state.TrialsToWin or 2
			card.Wins.Text = string.rep("■", s.TrialWins or 0)
				.. string.rep("□", math.max(0, toWin - (s.TrialWins or 0)))
			local tags = {}
			if s.Forfeited then
				table.insert(tags, "FORFEITED")
			elseif s.Eliminated then
				table.insert(tags, '<font color="#e0482f">INTEGRITY LOST</font>')
			end
			if state.Connected and state.Connected[id] == false and not s.Forfeited then
				table.insert(tags, "DISCONNECTED")
			end
			for effect, label in EFFECT_LABEL do
				if s.Effects and s.Effects[effect] then
					table.insert(tags, label)
				end
			end
			if state.Tether then
				table.insert(tags, "TETHERED")
			end
			card.Status.Text = table.concat(tags, "  ·  ")
			local isTurn = owner == id and state.Phase == "AwaitAction"
			card.Turn.Visible = isTurn
			card.Frame.BackgroundTransparency = if s.Eliminated then 0.45 else 0.1
			if card.Stroke then
				Theme.bind(card.Stroke, "Color", if isTurn then "Accent" else "Line")
				card.Stroke.Thickness = if isTurn then 2 else 1
			end
		end
	end
end

function MatchHUD:renderChamber()
	local state = st(self)
	local track = self.Track
	for _, child in track:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	local belief = state and state.Belief
	if belief == nil or #belief.Track == 0 then
		-- Between Loads (and on the Trial and match cards) there is nothing to read.
		self.Chamber.Visible = false
		self.Counts.Text = ""
		self.Odds.Text = ""
		return
	end
	self.Chamber.Visible = true
	local focus = self.C.TutorialController:focus()
	-- Spent cells (small), then the live track.
	for i, kind in state.Spent or {} do
		local g = Kit.glyph(track, kind, 18)
		g.LayoutOrder = i
		for _, d in g:GetDescendants() do
			if d:IsA("GuiObject") then
				d.BackgroundTransparency = math.max(d.BackgroundTransparency, 0.5)
			end
		end
	end
	local divider = Kit.create(
		"Frame",
		{ BorderSizePixel = 0, Size = UDim2.fromOffset(2, 30), LayoutOrder = 100, Parent = track }
	) :: Frame
	Theme.bind(divider, "BackgroundColor3", "LineStrong")
	for i, cell in belief.Track do
		local holder = Kit.create(
			"Frame",
			{ BackgroundTransparency = 1, Size = UDim2.fromOffset(34, 38), LayoutOrder = 100 + i, Parent = track }
		) :: Frame
		local g = Kit.glyph(holder, glyphKind(cell), 30)
		g.Position = UDim2.fromOffset(2, 0)
		if i == 1 then
			local bracket = Kit.create(
				"Frame",
				{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Parent = holder }
			) :: Frame
			Kit.stroke(bracket, "Accent", 2, 0)
			Kit.corner(bracket, 3)
			holder.Size = UDim2.fromOffset(38, 38)
		end
		Kit.tooltip(holder, if i == 1 then "Loaded cell" else string.format("Position %d", i))
	end
	local lo, hi, _ = Probability.range(belief)
	local n = #belief.Track
	if lo == hi then
		self.Counts.Text = string.format("%d CHARGED  ·  %d HOLLOW  REMAIN", lo, n - lo)
	else
		self.Counts.Text = string.format("%d–%d CHARGED  ·  %d CELLS REMAIN", lo, hi, n)
	end
	if belief.PoolCharged == nil and lo ~= hi then
		self.Counts.Text ..= "  ·  MIX WITHHELD"
	end
	if state.Surge then
		self.Counts.Text ..= '  ·  <font color="#e0482f">SURGE</font>'
	end
	local p = Probability.current(belief)
	if self.C.SettingsController:get("ProbabilityAssist") ~= false then
		local certain = Probability.isCertain(p)
		local label = if certain
			then (if p > 0.5 then "LOADED CELL IS CHARGED" else "LOADED CELL IS HOLLOW")
			else string.format("LOADED CELL :: %s CHARGED", Format.percent(p))
		local color = if p > 0.5 then Theme.Colors.Charged else Theme.Colors.Hollow
		self.Odds.Text = string.format('<font color="#%s">%s</font>', color:ToHex(), label)
	else
		self.Odds.Text = ""
	end
	local highlight = focus == "Track" or focus == "Counts" or focus == "Probability"
	local stroke = self.Chamber:FindFirstChildOfClass("UIStroke")
	if stroke then
		Theme.bind(stroke, "Color", if highlight then "Focus" else "Line")
		stroke.Thickness = if highlight then 2 else 1
	end
end

function MatchHUD:renderActions()
	local client = self.C.MatchClient
	local state = st(self)
	local myTurn = client:isMyTurn() and not client:spectating()
	local me = client:subject(client:you())
	self.Actions.Visible = myTurn
	local focus = self.C.TutorialController:focus()
	-- Fire controls.
	local target = self:target()
	local targetInfo = client:info(target)
	local targetName = targetInfo and string.upper(targetInfo.Name or "OPPONENT") or "OPPONENT"
	Kit.setText(
		self.FireOther,
		if self.Armed and self.Armed.Action == "FireOther"
			then "CONFIRM: FIRE AT " .. targetName
			else "FIRE AT " .. targetName
	)
	Kit.setText(
		self.FireSelf,
		if self.Armed and self.Armed.Action == "FireSelf" then "CONFIRM: FIRE AT SELF" else "FIRE AT SELF"
	)
	local input = self.C.InputController
	for actionId, button in { FireSelf = self.FireSelf, FireOther = self.FireOther } do
		local ok, reason = self:canFire(actionId)
		Kit.setEnabled(button, ok, reason)
		local key = button:FindFirstChild("Key")
		local label = key and key:FindFirstChildWhichIsA("TextLabel")
		local keyText = input:keyFor(actionId)
		if key and label then
			local cap = key :: Frame
			cap.Visible = keyText ~= ""
			cap.Size = UDim2.fromOffset(math.max(20, #keyText * 9 + 10), 20)
			label.Text = keyText
		end
		local tip = if actionId == "FireSelf"
			then "Fire at yourself. A HOLLOW cell keeps your turn; a CHARGED one costs you Integrity."
			else "Fire at the selected opponent. Your turn passes either way (unless Overclocked)."
		button:SetAttribute("Tooltip", tip)
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if
			stroke
			and ((focus == "FireSelf" and actionId == "FireSelf") or (focus == "FireOther" and actionId == "FireOther"))
		then
			Theme.bind(stroke, "Color", "Focus")
			stroke.Thickness = 3
		elseif stroke then
			stroke.Thickness = 1
		end
	end
	local opponents = self:opponents()
	self.Selector.Visible = #opponents > 1
	self.TargetName.Text = "TARGET: " .. targetName
	-- Instruments.
	local capacity = state and state.Capacity or 4
	local inventory = me and me.Instruments or {}
	local spectating = client:spectating()
	self.SlotsFrame.Visible = not spectating and me ~= nil
	for i = 1, MAX_SLOTS do
		local slot = self.Slots[i]
		local id = inventory[i]
		local button = slot.Button
		button.Visible = i <= capacity
		if slot.Id ~= id then
			slot.Id = id
			for _, child in slot.Icon:GetChildren() do
				child:Destroy()
			end
			if id then
				Icons.instrument(id, slot.Icon, 30)
			end
		end
		local def = id and Instruments.get(id)
		slot.Name.Text = def and def.Name or ""
		if def then
			local ok, reason = self:slotState(i, id)
			Kit.setEnabled(button, ok, reason)
			button:SetAttribute(
				"Tooltip",
				string.format(
					"<b>%s</b>  ·  %s\n%s\n<i>%s</i>",
					def.Name,
					string.upper(def.Rarity),
					def.Description,
					def.Visibility
				)
			)
			if slot.Stroke then
				Theme.bind(
					slot.Stroke,
					"Color",
					if focus == "Slot:" .. id or focus == "Instruments"
						then "Focus"
						else (RARITY_STROKE[def.Rarity] or "Line")
				)
			end
		else
			Kit.setEnabled(button, false, "Empty slot.")
			button:SetAttribute("Tooltip", "Empty slot.")
			if slot.Stroke then
				Theme.bind(slot.Stroke, "Color", "Line")
			end
		end
		local key = button:FindFirstChild("Key")
		if key then
			key.Visible = input:lastInput() == "Keyboard" and id ~= nil
		end
	end
end

function MatchHUD:renderInfo()
	local state = st(self)
	local sc = scene(self)
	if state == nil or sc == nil then
		return
	end
	local trial = state.Trial or 0
	self.TrialLabel.Text = if trial > 0
		then string.format(
			"TRIAL %s  ·  LOAD %d%s",
			Format.roman(trial),
			state.LoadInTrial or 0,
			if state.SuddenDeath then "  ·  SUDDEN DEATH" else ""
		)
		else "EVALUATION"
	self.ModeLabel.Text = string.upper(sc.ModeName or sc.ModeId or "")
		.. (if sc.Rules and sc.Rules.Ranked then "  ·  RANKED" else "")
	for _, child in self.Chips:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	for i, modId in state.Modifiers or {} do
		local m = Modifiers.get(modId)
		if m then
			local chip = Kit.label(self.Chips, {
				Text = "◆ " .. m.Name,
				Font = "Mono",
				TextSize = "Tiny",
				Color = "Warn",
				LayoutOrder = i,
				Size = UDim2.new(1, 0, 0, 14),
			})
			Kit.tooltip(chip, m.Description or m.Name)
		end
	end
	if sc.Spectating then
		local delay = sc.Rules and sc.Rules.Ranked and "DELAYED" or ""
		self.SpectateTag.Text = "SPECTATING " .. delay .. "  ·  [TAB]/D-PAD CHANGE VIEW  ·  [B] LEAVE"
	else
		self.SpectateTag.Text = ""
	end
end

function MatchHUD:renderHint()
	local client = self.C.MatchClient
	local state = st(self)
	if state == nil or self.C.SettingsController:get("Hints") == false then
		self.Hint.Text = ""
		return
	end
	local owner = state.Turn and state.Turn.Owner
	local text = ""
	if client:spectating() or state.Phase == "Ended" then
		text = ""
	elseif client:isMyTurn() then
		local belief = state.Belief
		local p = belief and #belief.Track > 0 and Probability.current(belief) or nil
		if self.Armed then
			text = "Press again to confirm."
		elseif p and Probability.isCertain(p) then
			text = if p > 0.5
				then "You know the loaded cell is CHARGED."
				else "You know the loaded cell is HOLLOW. Firing at yourself keeps your turn."
		else
			local mode = self.C.SettingsController:get("FireConfirm") or "Hold"
			text = "YOUR TURN  ·  "
				.. (
					if mode == "Hold"
						then "hold a fire control to commit"
						elseif mode == "Confirm" then "press a fire control twice to commit"
						else "choose"
				)
		end
	elseif owner and state.Phase == "AwaitAction" then
		local info = client:info(owner)
		text = string.upper(info and info.Name or "?") .. " IS DECIDING..."
	end
	self.Hint.Text = text
end

function MatchHUD:renderLog()
	if not self.LogOpen then
		return
	end
	local state = st(self)
	local list = self.LogList
	for _, child in list:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	if state == nil then
		return
	end
	local client = self.C.MatchClient
	local function name(id)
		if id == client:you() then
			return "YOU"
		end
		local info = client:info(id)
		return info and string.upper(info.Name or "?") or "?"
	end
	local entries = state.Log or {}
	local first = math.max(1, #entries - 11)
	for i = #entries, first, -1 do
		local e = entries[i]
		local text
		if e.Kind == "Fire" then
			text = string.format(
				"%s → %s  %s%s",
				name(e.Actor),
				if e.Actor == e.Target then "SELF" else name(e.Target),
				if e.Charged then "CHARGED" else "HOLLOW",
				if e.Charged then " −" .. tostring(e.Damage) else ""
			)
		elseif e.Kind == "Use" then
			local def = Instruments.get(e.Id)
			text = string.format(
				"%s used %s%s",
				name(e.Actor),
				def and def.Name or e.Id,
				if e.Target then " on " .. name(e.Target) else ""
			)
			if e.Id == "Ejector" and e.Outcome then
				text ..= if e.Outcome.Charged then " (CHARGED out)" else " (HOLLOW out)"
			end
		elseif e.Kind == "Load" then
			text = if e.Blind
				then string.format("LOAD  %d cells, mix withheld", e.Size or 0)
				else string.format(
					"LOAD  %d CHARGED · %d HOLLOW",
					e.Charged or 0,
					(e.Size or 0) - (e.Charged or 0)
				)
		elseif e.Kind == "Eliminated" then
			text = name(e.Subject) .. " lost all Integrity"
		elseif e.Kind == "Trial" then
			text = "TRIAL " .. Format.roman(e.Trial or 0) .. " ENDS"
		elseif e.Kind == "Skipped" then
			text = name(e.Subject) .. " skipped (Clamp)"
		elseif e.Kind == "Forfeit" then
			text = name(e.Subject) .. " forfeited"
		elseif e.Kind == "Timeout" then
			text = name(e.Subject) .. " ran out of time"
		end
		if text then
			Kit.label(list, {
				Text = text,
				Font = "Mono",
				TextSize = "Tiny",
				Color = if i == #entries then "Text" else "Dim",
				LayoutOrder = #entries - i,
				Size = UDim2.new(1, 0, 0, 16),
			})
		end
	end
end

function MatchHUD:render()
	self.Dirty = false
	self:renderCards()
	self:renderChamber()
	self:renderActions()
	self:renderInfo()
	self:renderHint()
	self:renderLog()
end

---------------------------------------------------------------------------
-- Callouts and cards
---------------------------------------------------------------------------

function MatchHUD:callout(title: string, text: string, kind: string?, duration: number?)
	local callout = self.Callout
	for _, child in self.CalloutGlyph:GetChildren() do
		child:Destroy()
	end
	if kind then
		Kit.glyph(self.CalloutGlyph, kind, 48)
	end
	self.CalloutTitle.Text = title
	self.CalloutText.Text = text
	callout.Visible = true
	callout.Size = UDim2.fromOffset(360, 0)
	Motion.tween(callout, 0.25, { Size = UDim2.fromOffset(360, 70) }, "settle")
	local token = os.clock()
	self.CalloutToken = token
	task.delay(duration or 2, function()
		if self.CalloutToken == token then
			Motion.await(callout, 0.2, { Size = UDim2.fromOffset(360, 0) }, "accel")
			if self.CalloutToken == token then
				callout.Visible = false
			end
		end
	end)
end

function MatchHUD:versusCard()
	local sc = scene(self)
	if sc == nil then
		return
	end
	local frame = self.Versus
	clearChildren(frame)
	frame.Visible = true
	local ids = {}
	for id in sc.Subjects do
		table.insert(ids, id)
	end
	table.sort(ids)
	-- A lower-third strip: the intro shots (everyone walking in and sitting
	-- down) keep the middle of the screen.
	local row = Kit.create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 84),
		Position = UDim2.new(0, 0, 1, 100),
		AnchorPoint = Vector2.new(0, 1),
		ZIndex = 41,
		Parent = frame,
	}) :: Frame
	-- (between the subtitles and the instrument tray)
	local shown = UDim2.new(0, 0, 1, -104)
	local layout = Kit.list(row, "X", 24, "Center")
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	for i, id in ids do
		local info = sc.Subjects[id]
		if i > 1 then
			Kit.label(row, {
				Text = "VS",
				Font = "Display",
				TextSize = "Heading",
				Color = "Accent",
				XAlign = "Center",
				Size = UDim2.fromOffset(60, 40),
				LayoutOrder = i * 2 - 1,
				ZIndex = 42,
			})
		end
		local card =
			Kit.panel(row, { Size = UDim2.fromOffset(300, 78), LayoutOrder = i * 2, Color = "Bg", ZIndex = 42 })
		Kit.padding(card, 10, 14)
		local frameData = info.Card and info.Card.Frame
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke and frameData and frameData.Stroke then
			stroke.Color = Color3.fromRGB(frameData.Stroke[1], frameData.Stroke[2], frameData.Stroke[3])
			stroke.Thickness = 2
		end
		-- Banner: a two-tone backdrop in the subject's chosen pattern.
		local banner = info.Look and info.Look.Banner and info.Look.Banner.Data
		if banner and banner.A and banner.B then
			local a = Color3.fromRGB(banner.A[1], banner.A[2], banner.A[3])
			local b = Color3.fromRGB(banner.B[1], banner.B[2], banner.B[3])
			local gradient = Instance.new("UIGradient")
			if banner.Pattern == "Solid" then
				gradient.Color = ColorSequence.new(b:Lerp(a, 0.35))
			elseif banner.Pattern == "Stripes" or banner.Pattern == "Grid" or banner.Pattern == "Static" then
				local keys = {}
				for i = 0, 8 do
					table.insert(keys, ColorSequenceKeypoint.new(i / 8, if i % 2 == 0 then a else b:Lerp(a, 0.5)))
				end
				gradient.Color = ColorSequence.new(keys)
				gradient.Rotation = if banner.Pattern == "Stripes" then 45 else 90
			else
				gradient.Color = ColorSequence.new(a, b:Lerp(a, 0.4))
				gradient.Rotation = 90
			end
			gradient.Parent = card
			-- The gradient tints a white base.
			Theme.bind(card, "BackgroundColor3", "Text")
			card.BackgroundColor3 = Color3.new(1, 1, 1)
		end
		-- Badge: a glyph in a coloured disc.
		local badgeData = info.Look and info.Look.Badge and info.Look.Badge.Data
		if badgeData and badgeData.Glyph and badgeData.Glyph ~= "" then
			local disc = Kit.create("Frame", {
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(28, 28),
				Position = UDim2.new(1, -28, 0, 0),
				ZIndex = 44,
				Parent = card,
			}) :: Frame
			disc.BackgroundColor3 = Color3.fromRGB(badgeData.Color[1], badgeData.Color[2], badgeData.Color[3])
			Kit.corner(disc, 14)
			Kit.label(disc, {
				Text = badgeData.Glyph,
				Font = "Bold",
				TextSize = "Small",
				XAlign = "Center",
				Size = UDim2.fromScale(1, 1),
				Color = "Bg",
				ZIndex = 45,
			})
		end
		Kit.label(card, {
			Text = string.upper(info.Name or "?"),
			Font = "Display",
			TextSize = "Title",
			Size = UDim2.new(1, -32, 0, 30),
			ZIndex = 43,
		})
		local lines = {}
		if info.IsAI then
			table.insert(lines, info.Title or "SURROGATE")
			table.insert(lines, "DIFFICULTY :: " .. string.upper(info.Difficulty or ""))
		else
			table.insert(lines, string.format("CLEARANCE %d  ·  %s", info.Level or 1, info.Title or ""))
			if info.Division then
				table.insert(lines, "STANDING :: " .. info.Division)
			end
			local banner = info.Card and info.Card.Title
			if banner then
				table.insert(lines, '"' .. banner .. '"')
			end
		end
		Kit.label(card, {
			Text = table.concat(lines, "  ·  "),
			Font = "Mono",
			TextSize = "Tiny",
			Color = "Dim",
			Wrap = true,
			Size = UDim2.new(1, 0, 0, 26),
			Position = UDim2.fromOffset(0, 32),
			YAlign = "Top",
			ZIndex = 43,
		})
	end
	Motion.tween(row, 0.45, { Position = shown }, "slide")
	local preview = sc.RankedPreview
	if preview then
		Kit.label(frame, {
			Text = string.format(
				"RANKED  ·  WIN %s  ·  LOSS %s  ·  EXPECTED %s",
				Format.signed(preview.Win or 0),
				Format.signed(preview.Loss or 0),
				Format.percent(preview.Expected or 0.5)
			),
			Font = "Mono",
			TextSize = "Label",
			XAlign = "Center",
			Color = "Accent",
			Size = UDim2.new(1, 0, 0, 20),
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, -192),
			ZIndex = 42,
		})
	end
	local token = (self.VersusToken or 0) + 1
	self.VersusToken = token
	task.delay(3.4, function()
		if self.VersusToken ~= token then
			return
		end
		Motion.tween(row, 0.35, { Position = UDim2.new(0, 0, 1, 100) }, "accel")
		task.wait(0.4)
		if self.VersusToken == token then
			frame.Visible = false
		end
	end)
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------

function MatchHUD:wire()
	local C = self.C
	local client = C.MatchClient
	client.Began:Connect(function()
		self.Target = nil
		self.Armed = nil
		self:cancelHold()
		self:buildCards()
		self:Open()
		self.Dirty = true
	end)
	client.Ended:Connect(function()
		self:Close()
	end)
	client.Changed:Connect(function()
		self.Dirty = true
	end)
	C.SettingsController.Changed:Connect(function()
		self.Dirty = true
	end)
	C.TutorialController.Changed:Connect(function()
		self.Dirty = true
	end)
	C.InputController.DeviceChanged:Connect(function()
		self.Dirty = true
	end)
	client.Rejected:Connect(function(reason)
		C.AudioController:play("Deny")
		Motion.shake(self.Actions, 6, 0.25)
		self.UI:toast("NOT ACCEPTED", client:rejectText(reason), "Warn")
	end)
	client.Turn:Connect(function(turn)
		self.Armed = nil
		self:cancelHold()
		self.Turn = turn
		self.LastTick = -1
		if client:isMyTurn() then
			local first = self.FireSelf
			self.UI:focus(first)
		end
	end)
	client.Event:Connect(function(kind, data)
		local you = client:you()
		if kind == "MatchStart" then
			self:versusCard()
		elseif kind == "InstrumentUsed" and data.Actor == you and data.Reveal and data.Reveal[1] then
			local r = data.Reveal[1]
			if data.Id == "Lens" then
				self:callout(
					"LENS :: LOADED CELL",
					if r.Charged then "CHARGED" else "HOLLOW",
					if r.Charged then "C" else "H",
					2.2
				)
			elseif data.Id == "Sonar" then
				self:callout(
					string.format("SONAR :: POSITION %d", r.Index),
					if r.Charged then "CHARGED" else "HOLLOW",
					if r.Charged then "C" else "H",
					2.2
				)
			end
		elseif kind == "LoadStart" and data.Reveal and #data.Reveal > 0 then
			local r = data.Reveal[1]
			task.delay(1.2, function()
				self:callout(
					string.format("PRECISION :: POSITION %d", r.Index),
					if r.Charged then "CHARGED" else "HOLLOW",
					if r.Charged then "C" else "H",
					2.4
				)
			end)
		elseif kind == "Echo" and data.Reveal and data.Reveal[1] then
			local r = data.Reveal[1]
			self:callout(
				"ECHO :: NEXT CELL",
				if r.Charged then "CHARGED" else "HOLLOW",
				if r.Charged then "C" else "H",
				2
			)
		end
	end)
	C.InputController.Action:Connect(function(action, phase)
		if not self.Visible then
			return
		end
		if action == "FireSelf" or action == "FireOther" then
			if phase == "Begin" then
				self:pressFire(action, "Begin")
				if self.Hold then
					self.Hold.Pointer = false
				end
			else
				self:pressFire(action, "End")
			end
			return
		end
		if phase ~= "Begin" then
			return
		end
		local slot = string.match(action, "^Slot(%d)$")
		if slot then
			self:useSlot(tonumber(slot) :: number)
		elseif action == "CycleTarget" or action == "NextTarget" then
			if not client:spectating() then
				self:cycleTarget(1)
			end
		elseif action == "PrevTarget" then
			if not client:spectating() then
				self:cycleTarget(-1)
			end
		elseif action == "ToggleLog" then
			self:toggleLog()
		elseif action == "Emote" then
			self:emoteMenu()
		elseif action == "Menu" then
			self:menu()
		elseif action == "NextSlot" or action == "PrevSlot" then
			if client:spectating() then
				return
			end
			local current = 0
			for i, s in self.Slots do
				if GuiService.SelectedObject == s.Button then
					current = i
				end
			end
			local me = client:subject(client:you())
			local count = me and #me.Instruments or 0
			if count > 0 then
				local nextIndex = ((current - 1 + (if action == "NextSlot" then 1 else -1)) % count) + 1
				self.UI:focus(self.Slots[nextIndex].Button)
			end
		end
	end)
	RunService.Heartbeat:Connect(function()
		if not self.Visible then
			return
		end
		-- Hold-to-fire progress.
		local hold = self.Hold
		if hold then
			local t = (os.clock() - hold.Start) / HOLD_TIME
			local button = if hold.Action == "FireSelf" then self.FireSelf else self.FireOther
			local fill = button:FindFirstChild("HoldFill") :: Frame
			fill.Size = UDim2.fromScale(math.clamp(t, 0, 1), 1)
			if t >= 1 then
				self.Hold = nil
				fill.Size = UDim2.fromScale(0, 1)
				self:fire(hold.Action)
			end
		end
		if self.Armed and os.clock() - self.Armed.At > CONFIRM_WINDOW then
			self.Armed = nil
			self.Dirty = true
		end
		-- Turn timer.
		local turn = self.Turn
		local state = st(self)
		if
			turn
			and turn.EndsAt
			and turn.Duration
			and turn.Duration > 0
			and state
			and state.Phase == "AwaitAction"
			and state.Turn.Owner == turn.Owner
		then
			local left = math.max(0, turn.EndsAt - workspace:GetServerTimeNow())
			self.TimerBar.Visible = true
			Kit.setBar(self.TimerBar, left / turn.Duration)
			local fill = self.TimerBar:FindFirstChild("Fill") :: Frame
			if fill then
				Theme.bind(fill, "BackgroundColor3", if left <= 5 then "Bad" else "Accent")
			end
			self.TimerText.Text = string.format("%d", math.ceil(left))
			local whole = math.ceil(left)
			if whole <= 5 and whole ~= self.LastTick and turn.Owner == client:you() then
				self.LastTick = whole
				self.C.AudioController:play(if whole <= 3 then "TimerUrgent" else "TimerTick")
			end
		else
			self.TimerBar.Visible = false
			self.TimerText.Text = ""
		end
		if self.Dirty then
			self:render()
		end
	end)
end

function MatchHUD:Open()
	self.Visible = true
	self.Frame.Visible = true
	self.Dirty = true
end

function MatchHUD:Close()
	self.Visible = false
	self.Frame.Visible = false
	self.Versus.Visible = false
	self:cancelHold()
	self:focusSlot(nil)
end

return MatchHUD

-- Root of the interface.
--
-- Layers (bottom to top): Hud (always-on HUDs), Screens (one main screen at a
-- time), Overlay (banners, subtitles, toasts), then modals. A UIScale adapts to
-- the viewport (phones get a denser layout) times the player's UI scale setting.
--
-- Screens live in client/UI/Screens and share one interface:
--   Screen.new(ui, controllers) -> object with .Frame, :Open(args), :Close()
--   Screen.Main = true for full screens (only one open at a time).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Parent.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)
local Motion = require(script.Parent.Parent.UI.Motion)
local Icons = require(script.Parent.Parent.UI.Icons)

local UIController = {}

local screensFolder = script.Parent.Parent.UI.Screens
local screens: { [string]: any } = {}
local current: string? = nil
local toastList: Frame
local subtitleFrame: Frame
local bannerFrame: Frame
local scale: UIScale
local curtain: Frame
local curtainTitle: TextLabel
local curtainSub: TextLabel
local curtainToken = 0

function UIController:Init(controllers)
	self.Controllers = controllers
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "VarianceUI"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 10
	gui.Parent = player:WaitForChild("PlayerGui")
	self.Root = gui
	Kit.root = gui
	Kit.sound = function(name)
		controllers.AudioController:play(name)
	end
	scale = Instance.new("UIScale")
	scale.Parent = gui
	self.Hud = Kit.create(
		"Frame",
		{ Name = "Hud", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui }
	) :: Frame
	self.Screens = Kit.create(
		"Frame",
		{ Name = "Screens", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui }
	) :: Frame
	self.Overlay = Kit.create(
		"Frame",
		{ Name = "Overlay", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 100, Parent = gui }
	) :: Frame

	toastList = Kit.create("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 64),
		Size = UDim2.fromOffset(340, 400),
		ZIndex = 120,
		Parent = self.Overlay,
	}) :: Frame
	local toastLayout = Kit.list(toastList, "Y", 8, "Right")
	toastLayout.VerticalAlignment = Enum.VerticalAlignment.Top

	-- Above the table HUD's odds panel and fire controls.
	subtitleFrame = Kit.create("Frame", {
		Name = "Subtitles",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -304),
		Size = UDim2.fromOffset(760, 120),
		ZIndex = 110,
		Parent = self.Overlay,
	}) :: Frame
	local subLayout = Kit.list(subtitleFrame, "Y", 4, "Center")
	subLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom

	bannerFrame = Kit.create("Frame", {
		Name = "Banner",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 130,
		Parent = self.Overlay,
	}) :: Frame

	-- The curtain hides trips between the lobby and a table (its own layer,
	-- above everything, so the HUD never flashes through a fade).
	local curtainGui = Instance.new("ScreenGui")
	curtainGui.Name = "VarianceCurtain"
	curtainGui.IgnoreGuiInset = true
	curtainGui.ResetOnSpawn = false
	curtainGui.DisplayOrder = 50
	curtainGui.Parent = gui.Parent
	curtain = Kit.create("Frame", {
		Name = "Curtain",
		BackgroundColor3 = Color3.fromRGB(4, 4, 5),
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = curtainGui,
	}) :: Frame
	curtainTitle = Kit.label(curtain, {
		Name = "Title",
		Text = "",
		Font = "Display",
		TextSize = "Title",
		XAlign = "Center",
		Color = "Text",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(800, 34),
		Transparency = 1,
	})
	curtainSub = Kit.label(curtain, {
		Name = "Sub",
		Text = "",
		Font = "Mono",
		TextSize = "Small",
		XAlign = "Center",
		Color = "Dim",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 30),
		Size = UDim2.fromOffset(800, 20),
		Transparency = 1,
	})
end

-- Fades the screen to black (on) or back (off). opts: Fade (seconds), Title,
-- Sub. A lowered curtain always lifts itself after `Failsafe` seconds.
function UIController:curtain(on: boolean, opts: { [string]: any }?)
	local o = opts or {}
	curtainToken += 1
	local token = curtainToken
	local fade = o.Fade or (if on then 0.25 else 0.5)
	if o.Title ~= nil then
		curtainTitle.Text = o.Title
	end
	if o.Sub ~= nil then
		curtainSub.Text = o.Sub
	end
	if on then
		curtain.Visible = true
		Motion.tween(curtain, fade, { BackgroundTransparency = 0 })
		local textAlpha = if curtainTitle.Text ~= "" then 0 else 1
		Motion.tween(curtainTitle, fade + 0.2, { TextTransparency = textAlpha })
		Motion.tween(curtainSub, fade + 0.3, { TextTransparency = textAlpha })
		task.delay(o.Failsafe or 12, function()
			if curtainToken == token then
				self:curtain(false)
			end
		end)
	else
		if not curtain.Visible then
			return
		end
		Motion.tween(curtainTitle, fade * 0.5, { TextTransparency = 1 })
		Motion.tween(curtainSub, fade * 0.5, { TextTransparency = 1 })
		Motion.tween(curtain, fade, { BackgroundTransparency = 1 })
		task.delay(fade, function()
			if curtainToken == token then
				curtain.Visible = false
				curtainTitle.Text = ""
				curtainSub.Text = ""
			end
		end)
	end
end

-- Sets the caption on a lowered curtain (e.g. the room being entered).
function UIController:curtainText(title: string?, sub: string?)
	curtainTitle.Text = title or ""
	curtainSub.Text = sub or ""
	if curtain.Visible then
		Motion.tween(curtainTitle, 0.3, { TextTransparency = if title and title ~= "" then 0 else 1 })
		Motion.tween(curtainSub, 0.4, { TextTransparency = if sub and sub ~= "" then 0 else 1 })
	end
end

function UIController:curtainDown(): boolean
	return curtain.Visible and curtain.BackgroundTransparency < 0.5
end

function UIController:updateScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local auto = math.clamp(math.min(viewport.X / 1280, viewport.Y / 760), 0.66, 1.25)
	self.Compact = viewport.X < 900 or UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	-- Phones: small print stays at least ~10 px on screen.
	Theme.MinText = if self.Compact then math.ceil(10 / auto) else 0
	scale.Scale = auto * (self.Controllers.SettingsController:get("UIScale") or 1)
end

---------------------------------------------------------------------------
-- Screens
---------------------------------------------------------------------------

function UIController:screen(name: string)
	local s = screens[name]
	if s == nil then
		local module = screensFolder:FindFirstChild(name)
		if module == nil then
			warn("[VARIANCE/UI] no screen " .. name)
			return nil
		end
		local ok, result = pcall(function()
			return require(module).new(self, self.Controllers)
		end)
		if not ok then
			warn("[VARIANCE/UI] screen " .. name .. " failed: " .. tostring(result))
			return nil
		end
		s = result
		screens[name] = s
	end
	return s
end

function UIController:open(name: string, args: any?)
	local s = self:screen(name)
	if s == nil then
		return
	end
	if s.Main and current and current ~= name then
		local previous = screens[current]
		if previous then
			previous:Close()
		end
	end
	if s.Main then
		current = name
		self.Controllers.AudioController:play("Open")
	end
	s:Open(args)
end

function UIController:close(name: string?)
	local target = name or current
	if target == nil then
		return
	end
	local s = screens[target]
	if s then
		s:Close()
		if s.Main then
			self.Controllers.AudioController:play("Close")
		end
	end
	if target == current then
		current = nil
		GuiService.SelectedObject = nil
	end
end

function UIController:isOpen(name: string): boolean
	return current == name
end

function UIController:currentScreen(): string?
	return current
end

-- Gives gamepad focus to a control when a gamepad is in use.
function UIController:focus(object: GuiObject?)
	if object and (UserInputService.GamepadEnabled and self.Controllers.InputController:lastInput() == "Gamepad") then
		GuiService.SelectedObject = object
	end
end

---------------------------------------------------------------------------
-- Toasts, banners, subtitles
---------------------------------------------------------------------------

local KIND_COLOR = { Info = "Accent", Good = "Good", Warn = "Warn", Bad = "Bad" }

function UIController:toast(title: string, text: string?, kind: string?, icon: (Frame) -> ()?)
	local card =
		Kit.panel(toastList, { Name = "Toast", Size = UDim2.fromOffset(340, 0), Color = "Panel", ZIndex = 121 })
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.LayoutOrder = -math.floor(os.clock() * 100)
	Kit.padding(card, 10, 14)
	local stripe = Kit.create("Frame", {
		BorderSizePixel = 0,
		Size = UDim2.new(0, 3, 1, 0),
		Position = UDim2.fromOffset(-14, 0),
		ZIndex = 122,
		Parent = card,
	}) :: Frame
	Theme.bind(stripe, "BackgroundColor3", KIND_COLOR[kind or "Info"] or "Accent")
	local body = Kit.create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 122,
		Parent = card,
	}) :: Frame
	Kit.list(body, "Y", 2)
	if icon then
		local holder = Kit.create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(28, 28),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			ZIndex = 123,
			Parent = card,
		}) :: Frame
		icon(holder)
	end
	Kit.label(body, {
		Text = title,
		Font = "Mono",
		TextSize = "Label",
		Color = KIND_COLOR[kind or "Info"] or "Accent",
		ZIndex = 123,
		LayoutOrder = 1,
		Size = UDim2.new(1, -34, 0, 18),
	})
	if text and text ~= "" then
		Kit.label(body, {
			Text = text,
			Font = "Body",
			TextSize = "Small",
			Wrap = true,
			AutoY = true,
			ZIndex = 123,
			LayoutOrder = 2,
			Size = UDim2.new(1, -34, 0, 0),
		})
	end
	card.Position = UDim2.fromOffset(40, 0)
	card.BackgroundTransparency = 1
	Motion.tween(card, 0.25, { BackgroundTransparency = 0.04 }, "slide")
	self.Controllers.AudioController:play("Toast")
	task.delay(5, function()
		if card.Parent then
			Motion.await(card, 0.3, { BackgroundTransparency = 1 }, "linger")
			card:Destroy()
		end
	end)
	-- Keep the stack short.
	local children = {}
	for _, child in toastList:GetChildren() do
		if child:IsA("Frame") then
			table.insert(children, child)
		end
	end
	if #children > 5 then
		table.sort(children, function(a, b)
			return a.LayoutOrder > b.LayoutOrder
		end)
		children[1]:Destroy()
	end
end

-- Large centred banner (turns, trials, results). Non-blocking.
function UIController:banner(title: string, subtitle: string?, color: string?, duration: number?)
	local holder = Kit.create("Frame", {
		Name = "BannerCard",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(900, 140),
		ZIndex = 131,
		Parent = bannerFrame,
	}) :: Frame
	local bar = Kit.create("Frame", {
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 0, 0, 86),
		BackgroundTransparency = 0.18,
		ZIndex = 131,
		Parent = holder,
	}) :: Frame
	Theme.bind(bar, "BackgroundColor3", "Bg")
	local line = Kit.create("Frame", {
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(1, 0, 0, 2),
		ZIndex = 132,
		Parent = bar,
	}) :: Frame
	Theme.bind(line, "BackgroundColor3", color or "Accent")
	local titleLabel = Kit.label(holder, {
		Text = title,
		Font = "Display",
		TextSize = "Banner",
		XAlign = "Center",
		Color = color or "Text",
		Size = UDim2.new(1, 0, 0, 56),
		Position = UDim2.fromScale(0, 0.22),
		ZIndex = 133,
	})
	titleLabel.TextTransparency = 1
	local sub = nil
	if subtitle then
		sub = Kit.label(holder, {
			Text = subtitle,
			Font = "Mono",
			TextSize = "Small",
			XAlign = "Center",
			Color = "Dim",
			Size = UDim2.new(1, 0, 0, 20),
			Position = UDim2.fromScale(0, 0.64),
			ZIndex = 133,
		})
		sub.TextTransparency = 1
	end
	Motion.tween(bar, 0.28, { Size = UDim2.new(1, 0, 0, 86) }, "slide")
	Motion.tween(titleLabel, 0.3, { TextTransparency = 0 }, "slide")
	if sub then
		Motion.tween(sub, 0.4, { TextTransparency = 0 }, "slide")
	end
	task.delay(duration or 1.8, function()
		Motion.tween(titleLabel, 0.25, { TextTransparency = 1 }, "linger")
		if sub then
			Motion.tween(sub, 0.25, { TextTransparency = 1 }, "linger")
		end
		Motion.await(bar, 0.3, { Size = UDim2.new(0, 0, 0, 86), BackgroundTransparency = 1 }, "accel")
		holder:Destroy()
	end)
end

-- Subtitle line. speaker may be nil (announcer / PA).
function UIController:subtitle(speaker: string?, text: string, duration: number?, colorKey: string?)
	local settings = self.Controllers.SettingsController
	if settings:get("Subtitles") == false and speaker ~= nil then
		return
	end
	local line = Kit.create("Frame", {
		Name = "Line",
		BackgroundTransparency = 0.25,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		LayoutOrder = math.floor(os.clock() * 100),
		ZIndex = 111,
		Parent = subtitleFrame,
	}) :: Frame
	Theme.bind(line, "BackgroundColor3", "Bg")
	Kit.corner(line, 3)
	Kit.padding(line, 6, 12)
	local rich = if speaker
		then string.format('<font color="#%s">%s</font>  %s', Theme.Colors[colorKey or "Accent"]:ToHex(), speaker, text)
		else string.format('<font color="#%s">PA</font>  %s', Theme.Colors.Dim:ToHex(), text)
	local label = Kit.create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		TextSize = Theme.textSize("Body") + 2,
		RichText = true,
		Text = rich,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		ZIndex = 112,
		Parent = line,
	}) :: TextLabel
	Theme.bind(label, "TextColor3", "Text")
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(740, 200)
	constraint.Parent = label
	task.delay(duration or 3.5, function()
		if line.Parent then
			Motion.await(line, 0.3, { BackgroundTransparency = 1 }, "linger")
			line:Destroy()
		end
	end)
	local count = 0
	for _, child in subtitleFrame:GetChildren() do
		if child:IsA("Frame") then
			count += 1
		end
	end
	if count > 3 then
		local oldest, order = nil, math.huge
		for _, child in subtitleFrame:GetChildren() do
			if child:IsA("Frame") and child.LayoutOrder < order then
				oldest, order = child, child.LayoutOrder
			end
		end
		if oldest then
			oldest:Destroy()
		end
	end
end

---------------------------------------------------------------------------
-- Server notices
---------------------------------------------------------------------------

function UIController:Start()
	local controllers = self.Controllers
	local network = controllers.NetworkClient
	local settings = controllers.SettingsController
	Theme.apply(settings:all())
	self:updateScale()
	settings.Changed:Connect(function()
		Theme.apply(settings:all())
		self:updateScale()
	end)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			self:updateScale()
		end)
	end

	network:onPush("Notify", function(data)
		self:toast(data.Title or "", data.Text, data.Kind)
	end)
	network:onPush("Earned", function(data)
		local parts = {}
		if data.XP and data.XP > 0 then
			table.insert(parts, "+" .. data.XP .. " XP")
		end
		if data.Marks and data.Marks > 0 then
			table.insert(parts, "+" .. data.Marks .. " MARKS")
		end
		if #parts > 0 then
			self:toast(string.upper(data.Reason or "EARNED"), table.concat(parts, "   "), "Good")
		end
	end)
	network:onPush("Unlock", function(data)
		controllers.AudioController:play("Unlock")
		if data.Kind == "Achievement" then
			self:toast("ACHIEVEMENT :: " .. data.Name, data.Text, "Good", function(holder)
				Icons.symbol("Trophy", holder, 28)
			end)
		elseif data.Kind == "Lore" then
			self:toast("FILE DECLASSIFIED", data.Name .. " is now in the Archive.", "Info", function(holder)
				Icons.symbol("Archive", holder, 28)
			end)
		else
			self:toast(
				"UNLOCKED :: " .. (data.Name or ""),
				data.Reason and ("From: " .. data.Reason) or "Now in your Locker.",
				"Good"
			)
		end
	end)
	network:onPush("LevelUp", function(data)
		controllers.AudioController:play("WinSting")
		self:banner(
			"CLEARANCE " .. tostring(data.To),
			(data.Title or "") .. (data.Marks and data.Marks > 0 and ("   +" .. data.Marks .. " MARKS") or ""),
			"Accent",
			2.6
		)
	end)
	network:onPush("Broadcast", function(data)
		controllers.AudioController:announce()
		self:subtitle(nil, data.Text, 5)
	end)
	network:onPush("OpenScreen", function(data)
		if data and data.Screen then
			self:open(data.Screen)
		end
	end)
	network:onPush("Endurance", function(data)
		if data.Finished then
			self:banner(
				"ENDURANCE",
				string.format("STAGES CLEARED: %d / %d", data.Reached or 0, data.Total or 5),
				"Accent",
				3
			)
		else
			self:banner(
				"STAGE " .. tostring(data.Next),
				"Integrity carried over: " .. tostring(data.Integrity),
				"Accent",
				3
			)
		end
	end)
	network:onPush("TutorialComplete", function(data)
		self:toast("LESSON COMPLETE", (data.Name or "") .. (data.First and " - rewards granted." or ""), "Good")
	end)
	network:onPush("Curtain", function(data)
		if type(data) == "table" and data.On then
			self:curtain(true, { Title = "", Sub = "" })
			controllers.CameraController:hold()
		end
	end)
	network:onPush("OfferTutorial", function()
		if controllers.MatchClient:active() then
			return -- already at a table; the offer stays in the Play screen
		end
		task.spawn(function()
			local begin = Kit.modal(
				"WELCOME, CANDIDATE",
				"You have been selected for evaluation at Halden Decision Sciences. Orientation takes about five minutes and teaches you the Arbiter, the cells and your first instruments.",
				{
					{ Text = "LATER", Style = "Ghost", Value = false },
					{ Text = "BEGIN ORIENTATION", Style = "Primary", Value = true },
				},
				{ Tag = "Offer" }
			)
			if begin then
				local ok, err = network:request("Tutorial.Start", "Basic")
				if not ok then
					self:toast("ORIENTATION", tostring(err), "Warn")
				end
			end
		end)
	end)
	network:onPush("Reconnect", function(data)
		task.spawn(function()
			local back = Kit.modal(
				"TRIAL IN PROGRESS",
				string.format(
					"You left a Trial that is still running. Return to your seat? It is held for about %d seconds.",
					data.Grace or 45
				),
				{
					{ Text = "ABANDON", Style = "Danger", Value = false },
					{ Text = "RETURN", Style = "Primary", Value = true },
				}
			)
			network:request(back and "Reconnect.Accept" or "Reconnect.Decline")
		end)
	end)
	-- Persistent HUDs: the lobby one is shown now; the table one wires itself
	-- to the match client and appears when a Trial begins.
	self:screen("MatchHUD")
	self:open("LobbyHUD")
end

return UIController

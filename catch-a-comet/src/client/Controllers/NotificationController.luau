-- Feedback that isn't a panel: toasts, centre banners (level ups, big
-- moments), the welcome-back card for offline earnings, the save-status
-- banner, travel fades and server notices. Animation intensity scales with
-- how special the moment is, and respects Reduced Motion.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BiomeDefinitions = require(Shared.BiomeDefinitions)
local Format = require(Shared.Format)
local QuestDefinitions = require(Shared.QuestDefinitions)
local RemoteDefinitions = require(Shared.RemoteDefinitions)
local UITheme = require(Shared.UITheme)
local UpgradeDefinitions = require(Shared.UpgradeDefinitions)

local NotificationController = {}

local controllers: { [string]: any } = {}
local Components: any
local gui: ScreenGui
local toastStack: Frame
local banner: Frame
local bannerTitle: TextLabel
local bannerSub: TextLabel
local saveBanner: TextLabel
local fade: Frame
local bannerToken = 0

function NotificationController.Toast(text: string, icon: string?, color: Color3?)
	local Make = Components.Make
	local toast = Make("Frame", {
		BackgroundColor3 = UITheme.Colors.Panel,
		BackgroundTransparency = 0.05,
		Size = UDim2.fromOffset(330, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = -os.clock() * 1000,
		Parent = toastStack,
	})
	Components.Corner(14).Parent = toast
	Components.Stroke(color or UITheme.Colors.Stroke, 1.5, 0.2).Parent = toast
	Components.Padding(10, 12).Parent = toast
	Components.Label({
		Text = (if icon then icon .. "  " else "") .. text,
		Font = UITheme.Fonts.Bold,
		TextSize = 16,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 20),
		Parent = toast,
	})
	Components.Pop(toast, 0.12)
	local children = {}
	for _, child in toastStack:GetChildren() do
		if child:IsA("Frame") then
			table.insert(children, child)
		end
	end
	if #children > 4 then
		table.sort(children, function(a, b)
			return a.LayoutOrder > b.LayoutOrder
		end)
		children[1]:Destroy()
	end
	task.delay(4, function()
		if toast.Parent then
			Components.Tween(toast, 0.3, { BackgroundTransparency = 1 })
			task.wait(0.3)
			toast:Destroy()
		end
	end)
end

-- A big centred banner. intensity 1 (ordinary) … 3 (extraordinary).
function NotificationController.Banner(title: string, subtitle: string?, color: Color3?, intensity: number?)
	bannerToken += 1
	local token = bannerToken
	bannerTitle.Text = title
	bannerTitle.TextColor3 = color or UITheme.Colors.Gold
	bannerSub.Text = subtitle or ""
	banner.Visible = true
	banner.BackgroundTransparency = 1
	Components.Pop(banner, 0.15 + (intensity or 1) * 0.1)
	task.delay(2.6 + (intensity or 1) * 0.4, function()
		if bannerToken == token then
			banner.Visible = false
		end
	end)
end

function NotificationController.Fade()
	fade.BackgroundTransparency = 0
	Components.Tween(fade, 0.5, { BackgroundTransparency = 1 })
end

local function welcomeBack(payload: any)
	local panelInfo = Components.Panel("Welcome back!", Vector2.new(440, 300), gui)
	local body = panelInfo.Body
	Components.Label({
		Text = `While you were away ({Format.Duration(payload.Away or payload.Seconds)}), your creatures gathered`,
		Font = UITheme.Fonts.Body,
		TextColor3 = UITheme.Colors.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 48),
		Parent = body,
	})
	Components.Label({
		Text = `✦ {Format.Number(payload.Amount)}`,
		Font = UITheme.Fonts.Display,
		TextSize = 44,
		TextColor3 = UITheme.Colors.Gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 56),
		Position = UDim2.fromOffset(0, 52),
		Parent = body,
	})
	Components.Label({
		Text = if payload.Capped
			then "Offline gathering is capped at 2 hours — come back often!"
			else "Sanctuaries gather at 25% speed while you're away.",
		Font = UITheme.Fonts.Body,
		TextSize = 14,
		TextColor3 = UITheme.Colors.Dim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.fromOffset(0, 112),
		Parent = body,
	})
	local collect = Components.Button("Collect", "Gold", UDim2.fromOffset(180, 48), body)
	collect.Instance.AnchorPoint = Vector2.new(0.5, 1)
	collect.Instance.Position = UDim2.new(0.5, 0, 1, -4)
	local function dismiss()
		panelInfo.Root:Destroy()
	end
	collect.Activated:Connect(dismiss)
	panelInfo.Close.Activated:Connect(dismiss)
	Components.ShowPanel(panelInfo.Root, true)
	Components.FocusFirst(collect.Instance)
	controllers.AudioController.Fanfare(1)
end

local function saveStatus(status: string?)
	if status == "Degraded" then
		saveBanner.Visible = true
		saveBanner.Text = "⚠ Saving is delayed — we'll keep retrying. Recent progress isn't saved yet."
		saveBanner.BackgroundColor3 = UITheme.Colors.Coral
	elseif status == "SessionOnly" then
		saveBanner.Visible = true
		saveBanner.Text = "Session-only mode: progress in this session will NOT be saved."
		saveBanner.BackgroundColor3 = UITheme.Colors.Gold
	elseif status == "Locked" then
		saveBanner.Visible = true
		saveBanner.Text = "⚠ Your profile was opened elsewhere. This session is no longer saving."
		saveBanner.BackgroundColor3 = UITheme.Colors.Coral
	else
		saveBanner.Visible = false
	end
end

local handlers: { [string]: (any) -> () } = {
	LevelUp = function(payload)
		local subtitle = `+{Format.Number(payload.Stardust)} Stardust`
		if payload.BiomesReady and #payload.BiomesReady > 0 then
			subtitle ..= `  ·  {table.concat(payload.BiomesReady, ", ")} requirement reached`
		end
		NotificationController.Banner(`LEVEL {payload.Level}!`, subtitle, UITheme.Colors.Gold, 2)
		controllers.AudioController.Fanfare(2)
		controllers.CameraController.FovPunch(-4)
	end,
	QuestCompleted = function(payload)
		if payload.Chain == "Missions" then
			local mission = QuestDefinitions.FindMission(payload.Id)
			NotificationController.Toast(
				`Mission complete: {if mission then mission.Title else payload.Id}! Claim your reward.`,
				"📜",
				UITheme.Colors.Gold
			)
			controllers.AudioController.Fanfare(1)
		elseif payload.Done then
			NotificationController.Banner(
				"Tutorial complete!",
				"Catch more comets in Dawn Commons · reach Level 5 for Prism Cliffs",
				UITheme.Colors.Cyan,
				2
			)
			controllers.AudioController.Fanfare(2)
		else
			controllers.AudioController.Play("Purchase", { Pitch = 1.8 })
		end
		if payload.Reward and payload.Reward.Stardust and payload.Reward.Stardust > 0 then
			NotificationController.Toast(
				`+{Format.Number(payload.Reward.Stardust)} Stardust`,
				"✦",
				UITheme.Colors.Gold
			)
		end
	end,
	OfflineEarnings = welcomeBack,
	SaveStatus = function(payload)
		saveStatus(payload.Status)
		if payload.Status == "OK" then
			NotificationController.Toast("Saving restored.", "✅", UITheme.Colors.Green)
		end
	end,
	Upgraded = function(payload)
		local track = UpgradeDefinitions.Get(payload.Track)
		local level = track and track.Levels[payload.Level]
		local text = `{if track then track.DisplayName else payload.Track} upgraded to Lv {payload.Level}!`
		NotificationController.Banner(text, level and level.FeatureText or nil, UITheme.Colors.Cyan, 1)
		controllers.AudioController.Play("Purchase")
		controllers.AudioController.Fanfare(1)
	end,
	BiomeUnlocked = function(payload)
		local biome = BiomeDefinitions.Get(payload.Biome)
		NotificationController.Banner(
			`{if biome then biome.DisplayName else payload.Biome} unlocked!`,
			"A new region of the sky is open",
			UITheme.Colors.Lavender,
			3
		)
	end,
	PortalLocked = function(payload)
		if payload.Reason == "ComingSoon" then
			NotificationController.Toast(
				`{payload.Name} is still being charted. Requirements: Level {payload.Level} · {payload.Stardust} Stardust.`,
				"🔭"
			)
		else
			NotificationController.Toast(
				`{payload.Name} is locked (Level {payload.Level} · {payload.Stardust} Stardust).`,
				"🔒"
			)
		end
	end,
	NoSanctuary = function()
		NotificationController.Toast(
			"Every sanctuary in this server is taken. You can still catch comets!",
			"🏡",
			UITheme.Colors.Coral
		)
	end,
	CaptureTimeout = function()
		NotificationController.Toast("The comet's energy drifted away. Try again!", "☄️")
	end,
	Travelled = function()
		NotificationController.Fade()
		controllers.AudioController.Play("Portal")
	end,
	Recovered = function()
		NotificationController.Fade()
		NotificationController.Toast("Whoa! Back on solid ground.", "🪂")
	end,
}

function NotificationController.Init(registry: { [string]: any })
	controllers = registry
end

function NotificationController.Start()
	Components = controllers.Components
	local Make = Components.Make
	gui = Components.Screen("Notifications", 30)
	toastStack = Make("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 96),
		Size = UDim2.fromOffset(330, 400),
		Parent = gui,
	})
	Components.List(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right).Parent = toastStack

	banner = Make("Frame", {
		Name = "Banner",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 120),
		Size = UDim2.fromOffset(700, 90),
		Visible = false,
		Parent = gui,
	})
	bannerTitle = Components.Label({
		Text = "",
		Font = UITheme.Fonts.Display,
		TextSize = 48,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 56),
		Parent = banner,
	})
	Make("UIStroke", { Color = UITheme.Colors.Background, Thickness = 3, Parent = bannerTitle })
	bannerSub = Components.Label({
		Text = "",
		Font = UITheme.Fonts.Heading,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.fromOffset(0, 58),
		Parent = banner,
	})
	Make("UIStroke", { Color = UITheme.Colors.Background, Thickness = 2, Parent = bannerSub })

	saveBanner = Make("TextLabel", {
		Name = "SaveStatus",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(620, 30),
		Font = UITheme.Fonts.Bold,
		TextSize = 15,
		TextColor3 = UITheme.Colors.Background,
		Visible = false,
		Parent = gui,
	})
	Components.Round().Parent = saveBanner

	fade = Make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = UITheme.Colors.Background,
		BackgroundTransparency = 1,
		Parent = Components.Screen("Fade", 50, false),
	})

	controllers.ClientState.ObserveSession("SaveStatus", saveStatus)
	RemoteDefinitions.GetEvent("Notification").OnClientEvent:Connect(function(kind, payload)
		local handler = handlers[kind]
		if handler then
			handler(payload or {})
		end
	end)
end

return NotificationController

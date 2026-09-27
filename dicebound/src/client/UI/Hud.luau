-- The always-on HUD: coins, bag capacity, current goal, region, the dice tray, the roll button
-- with its cooldown, auto-roll, and the menu buttons. Kept clear of Roblox's own UI: top-bar
-- buttons (safe-area insets), the mobile thumbstick (bottom-left) and jump button (bottom-right).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Dicebound.Config)
local Format = require(ReplicatedStorage.Dicebound.Format)
local ClientState = require(script.Parent.Parent.ClientState)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)
local DiceTray = require(script.Parent.DiceTray)

local C = Theme.Colors

local Hud = {}

local function pill(parent: Instance, icon: string, order: number): (Frame, TextLabel)
	local frame = Kit.Card({
		Parent = parent,
		Size = UDim2.fromOffset(210, 44),
		LayoutOrder = order,
	})
	Kit.Label({
		Parent = frame,
		Text = icon,
		Size = UDim2.fromOffset(40, 44),
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local value = Kit.Label({
		Parent = frame,
		Position = UDim2.fromOffset(40, 0),
		Size = UDim2.new(1, -48, 1, 0),
		Text = "…",
		Font = Theme.Fonts.Title,
		TextSize = 22,
		TextWrapped = false,
	})
	return frame, value
end

function Hud.new(root: Instance, callbacks: { [string]: () -> () })
	local self = {}

	-- ── Left column: coins, bag, goal ────────────────────────────────────────────
	local left = Kit.new("Frame", {
		Name = "LeftColumn",
		Position = UDim2.fromOffset(14, 10),
		Size = UDim2.fromOffset(270, 300),
		BackgroundTransparency = 1,
		Parent = root,
	})
	Kit.List(left, Enum.FillDirection.Vertical, 8)
	local _, coins = pill(left, "🪙", 1)
	local bagPill, bagText = pill(left, "🎒", 2)
	bagText.Size = UDim2.new(1, -48, 0, 28)
	bagText.TextSize = 18
	local bagBar = Kit.Bar({
		Parent = bagPill,
		Size = UDim2.new(1, -56, 0, 7),
		Position = UDim2.fromOffset(44, 30),
		Color = C.Green,
	})

	local goal = Kit.Card({
		Parent = left,
		Size = UDim2.fromOffset(270, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3,
	})
	Kit.Padding(goal, 10)
	Kit.List(goal, Enum.FillDirection.Vertical, 5)
	local goalTitle = Kit.Label({
		Parent = goal,
		Text = "GOAL",
		Font = Theme.Fonts.Bold,
		TextSize = 12,
		TextColor3 = C.InkSoft,
		Size = UDim2.new(1, 0, 0, 14),
		LayoutOrder = 1,
	})
	local goalText = Kit.Label({
		Parent = goal,
		Text = "",
		Font = Theme.Fonts.Bold,
		TextSize = 15,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		LayoutOrder = 2,
	})
	local goalBar = Kit.Bar({ Parent = goal, Size = UDim2.new(1, 0, 0, 8), LayoutOrder = 3 })
	local goalDetail = Kit.Label({
		Parent = goal,
		Text = "",
		TextSize = 13,
		TextColor3 = C.InkSoft,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		LayoutOrder = 4,
	})
	local skipButton = Kit.Button({
		Parent = goal,
		Text = "Skip tutorial",
		Color = C.InkFaint,
		Size = UDim2.fromOffset(120, 30),
		TextSize = 14,
		LayoutOrder = 5,
		OnClick = callbacks.SkipTutorial,
	})
	skipButton.Instance.Visible = false

	-- ── Top center: region banner + save warning ────────────────────────────────
	local banner = Kit.Label({
		Parent = root,
		Name = "RegionBanner",
		Position = UDim2.new(0.5, 0, 0, 10),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(0, 36),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0.1,
		BackgroundColor3 = C.Panel,
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 20,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	Kit.Corner(banner, 18)
	Kit.Stroke(banner)
	Kit.Padding(banner, 0, 16)
	local saveWarning = Kit.Label({
		Parent = root,
		Position = UDim2.new(0.5, 0, 0, 50),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.fromRGB(255, 226, 220),
		TextColor3 = C.RedDark,
		Text = "Studio test: saving is off. Enable 'Studio Access to API Services' to test saves.",
		TextSize = 13,
		Font = Theme.Fonts.Bold,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
	})
	Kit.Corner(saveWarning, 8)
	Kit.Padding(saveWarning, 0, 10)

	-- ── Right side (middle, away from the jump button): menu buttons ───────────
	local menu = Kit.new("Frame", {
		Name = "Menu",
		Position = UDim2.new(1, -14, 0.42, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(76, 330),
		BackgroundTransparency = 1,
		Parent = root,
	})
	Kit.List(menu, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right)
	local menuButtons = {}
	for i, def in
		{
			{ "Bag", "🎒", "Bag", C.GoldDark },
			{ "Upgrades", "🔧", "Upgrades", C.Blue },
			{ "Odds", "🎯", "Odds", C.Purple },
			{ "Settings", "⚙️", "Settings", C.InkSoft },
		}
	do
		local button = Kit.Button({
			Parent = menu,
			Name = def[1],
			Text = def[2] .. "\n" .. def[3],
			Color = def[4],
			Size = UDim2.fromOffset(76, 68),
			TextSize = 15,
			LayoutOrder = i,
			OnClick = callbacks[def[1]],
		})
		menuButtons[def[1]] = button
	end

	-- ── Bottom center: tray, roll, auto ──────────────────────────────────────────
	local bottom = Kit.new("Frame", {
		Name = "RollArea",
		Position = UDim2.new(0.5, 0, 1, -12),
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(330, 222),
		BackgroundTransparency = 1,
		Parent = root,
	})
	local tray = DiceTray.new(bottom)
	local diceLabel = Kit.Label({
		Parent = tray.Frame,
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -20, 0, 18),
		Text = "",
		TextSize = 13,
		Font = Theme.Fonts.Bold,
		TextColor3 = C.InkSoft,
		ZIndex = 2,
	})

	local roll = Kit.Button({
		Parent = bottom,
		Name = "Roll",
		Text = "🎲 ROLL",
		Color = C.Green,
		Size = UDim2.fromOffset(214, 70),
		Position = UDim2.fromOffset(0, 150),
		TextSize = 30,
		OnClick = callbacks.Roll,
	})
	local cooldownFill = Kit.new("Frame", {
		Name = "Cooldown",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C.Shadow,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = roll.Instance,
	})
	Kit.Corner(cooldownFill, 10)
	roll.Label.ZIndex = 3

	local auto = Kit.Button({
		Parent = bottom,
		Name = "Auto",
		Text = "🔁 Auto\nOFF",
		Color = C.InkFaint,
		Size = UDim2.fromOffset(106, 70),
		Position = UDim2.fromOffset(224, 150),
		TextSize = 16,
		OnClick = callbacks.Auto,
	})

	-- ── Public API ───────────────────────────────────────────────────────────────
	self.Tray = tray
	self.RollButton = roll
	self.AutoButton = auto
	self.MenuButtons = menuButtons
	self.RollArea = bottom
	self.SkipButton = skipButton

	local cooldownToken = 0
	function self.StartCooldown(seconds: number)
		cooldownToken += 1
		local token = cooldownToken
		cooldownFill.Size = UDim2.fromScale(1, 1)
		local tween = TweenService:Create(
			cooldownFill,
			TweenInfo.new(seconds, Enum.EasingStyle.Linear),
			{ Size = UDim2.fromScale(0, 1) }
		)
		tween:Play()
		local endsAt = os.clock() + seconds
		task.spawn(function()
			while token == cooldownToken and os.clock() < endsAt do
				roll:SetText(string.format("%.1fs", endsAt - os.clock()))
				task.wait(0.1)
			end
			if token == cooldownToken then
				self.RefreshRollText()
			end
		end)
	end

	local bagFull = false
	function self.RefreshRollText()
		roll:SetText(if bagFull then "🎒 BAG FULL" else "🎲 ROLL")
		roll:SetColor(if bagFull then C.Red else C.Green)
	end

	function self.SetAuto(unlocked: boolean, on: boolean)
		if not unlocked then
			local cost = Config.Economy.Upgrades.ById.AutoRoll.Levels[2].Cost
			auto:SetText("🔒 Auto\n🪙" .. Format.Coins(cost))
			auto:SetColor(C.InkFaint)
		else
			auto:SetText(if on then "🔁 Auto\nON" else "🔁 Auto\nOFF")
			auto:SetColor(if on then C.Blue else C.InkFaint)
		end
	end

	function self.SetRegion(region)
		if region then
			banner.Text = "📍 " .. region.Name
			banner.Visible = true
			if not Kit.ReducedMotion then
				banner.TextSize = 14
				Kit.Tween(banner, 0.3, { TextSize = 20 }, Enum.EasingStyle.Back)
			end
		else
			banner.Text = "Walk into a region to roll"
		end
	end

	function self.SetGoal(title: string, text: string, fraction: number?, detail: string?, showSkip: boolean?)
		goalTitle.Text = title
		goalText.Text = text
		goalBar.Instance.Visible = fraction ~= nil
		if fraction then
			goalBar:Set(fraction, true)
		end
		goalDetail.Text = detail or ""
		goalDetail.Visible = detail ~= nil and detail ~= ""
		skipButton.Instance.Visible = showSkip == true
	end

	function self.Update(data)
		coins.Text = Format.Coins(data.Coins)
		bagText.Text = string.format("%d / %d items", data.Used, data.Capacity)
		bagBar:Set(data.Used / math.max(data.Capacity, 1), true)
		bagBar.Fill.BackgroundColor3 = if data.Used >= data.Capacity
			then C.Red
			elseif data.Used / data.Capacity > 0.8 then C.Gold
			else C.Green
		bagFull = data.Used >= data.Capacity
		self.RefreshRollText()
		saveWarning.Visible = data.SaveMode == "studio"
		local names = {}
		for _, dieId in data.Dice.Equipped do
			local die = Config.Dice.ById[dieId]
			table.insert(names, die and die.Name or dieId)
		end
		diceLabel.Text = "Equipped: " .. table.concat(names, ", ")
		tray:SetDice(data.Dice.Equipped)
	end

	-- Coin counter pop when coins go up.
	local lastCoins = nil
	ClientState.Changed:Connect(function(data)
		if lastCoins and data.Coins > lastCoins and not Kit.ReducedMotion then
			coins.TextColor3 = C.GoldDark
			coins.TextSize = 26
			Kit.Tween(coins, 0.35, { TextSize = 22, TextColor3 = C.Ink })
		end
		lastCoins = data.Coins
	end)

	return self
end

return Hud

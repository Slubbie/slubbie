-- The heads-up display.
--
--   top-left      clock · date · weather · region · day progress (click → calendar)
--   top-centre    visiting / festival pills
--   top-right     coins & tokens, menu buttons with badges
--   left / right  tracked quests (Settings: QuestTracker, TrackerSide)
--   bottom        hint line, held item + area, buffs, energy & water, XP bar, hotbar
--   touch         action cluster (use, item, area, build, bag)
--
-- Everything reacts to the replicated profile; nothing here decides game rules.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local Stats = require(Shared.Lib.Stats)
local GameTime = require(Shared.Lib.GameTime)
local Format = require(Shared.Lib.Format)
local ItemUtil = require(Shared.Lib.ItemUtil)
local WeatherMath = require(Shared.Lib.WeatherMath)

local C = require(script.Parent)
local UIFolder = script.Parent.Parent:WaitForChild("UI")
local Kit = require(UIFolder.Kit)
local Theme = require(UIFolder.Theme)
local Describe = require(UIFolder.Describe)

local HUD = {}

local player = Players.LocalPlayer
local HOTBAR = 9 -- inventory slots 1-9 (matches the server)
local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII" }
local BUFF_ICONS = { Speed = "🏃", Focus = "🎯", Luck = "🍀", Fishing = "🎣", Mining = "⛏️", Warmth = "🔥", Cool = "❄️", Light = "💡", Friendship = "💞" }

local layer: Frame
local root: Frame
local slots: { any } = {}
local tierLabels: { TextLabel } = {}
local selected = 0
local badges: { [string]: TextLabel } = {}
local manualBadges: { [string]: boolean | number } = {}
local coinsLabel: TextLabel
local tokensLabel: TextLabel
local shownCoins = 0
local energyBar: any
local waterBar: any
local xpBar: any
local xpLabel: TextLabel
local lastSkill = "Farming"
local lastXP: { [string]: number } = {}
local hintLabel: TextLabel
local hintToken = 0
local heldLabel: TextLabel
local buffRow: Frame
local clock: { Time: TextLabel, Date: TextLabel, Weather: TextLabel, Region: TextLabel, Day: Frame, Sun: TextLabel }
local tracker: Frame
local trackerList: Frame
local trackerHeader: TextButton
local topPills: Frame
local visitPill: Frame?
local festivalPill: Frame?
local touchCluster: Frame?
local nodeBars: { [string]: { Gui: BillboardGui, Fill: Frame, Until: number } } = {}

-- Helpers ------------------------------------------------------------------------------------------------------------

local function profile(): any
	return C.State.Data()
end

local function waterCapacity(p: any): number
	local fam = Registry.ToolFamilies.can
	local tier = (p.Tools and p.Tools.can) or 1
	local def = fam and fam.Tiers[math.clamp(tier, 1, #fam.Tiers)]
	return (def and def.Capacity) or 25
end

local function pill(parent: Instance, name: string, width: number): (Frame, TextLabel)
	local frame = Kit.Panel({ Size = UDim2.fromOffset(width, 36), Name = name, Corner = 18 })
	frame.BackgroundTransparency = 0.08
	local label = Kit.Label("", { Size = Theme.Sizes.Body, Font = Theme.Fonts.Number, Align = "Center" })
	label.Size = UDim2.fromScale(1, 1)
	label.Parent = frame
	frame.Parent = parent
	return frame, label
end

-- Clock ----------------------------------------------------------------------------------------------------------------

local function buildClock()
	local panel = Kit.Panel({ Size = UDim2.fromOffset(232, 96), Name = "Clock", Shadow = true })
	panel.Position = UDim2.fromOffset(14, 10)
	panel.BackgroundTransparency = 0.06
	Kit.Padding(panel, 6, 12)
	local button = Kit.new("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = panel })
	button.Activated:Connect(function()
		C.Windows.Toggle("Calendar")
	end)
	local time = Kit.Label("", { Size = 24, Font = Theme.Fonts.Heading })
	time.Size = UDim2.new(1, -40, 0, 28)
	time.Parent = panel
	local sun = Kit.Label("☀️", { Size = 22, Align = "Right" })
	sun.Size = UDim2.new(0, 40, 0, 28)
	sun.Position = UDim2.new(1, -40, 0, 0)
	sun.Parent = panel
	local date = Kit.Label("", { Size = Theme.Sizes.Small, Color = "SubText" })
	date.Position = UDim2.fromOffset(0, 28)
	date.Size = UDim2.new(1, 0, 0, 18)
	date.Parent = panel
	local weather = Kit.Label("", { Size = Theme.Sizes.Small })
	weather.Position = UDim2.fromOffset(0, 46)
	weather.Size = UDim2.new(1, 0, 0, 18)
	weather.Parent = panel
	local region = Kit.Label("", { Size = Theme.Sizes.Tiny, Color = "SubText" })
	region.Position = UDim2.fromOffset(0, 64)
	region.Size = UDim2.new(1, 0, 0, 14)
	region.Parent = panel
	local track = Kit.new("Frame", { BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 3), Position = UDim2.new(0, 0, 1, -2), BackgroundTransparency = 0.3, Parent = panel })
	Kit.Paint(track, "BackgroundColor3", "Inset")
	local day = Kit.new("Frame", { BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = track })
	Kit.Paint(day, "BackgroundColor3", "Accent")
	panel.Parent = root
	clock = { Time = time, Date = date, Weather = weather, Region = region, Day = day, Sun = sun }
	Kit.AttachTooltip(button, function()
		local lines: { Kit.TipLine } = { { Text = "Forecast", Bold = true } }
		for _, entry in WeatherMath.Forecast(4) do
			local def = WeatherMath.Def(entry.Weather)
			local hour = GameTime.HourOf(entry.Start)
			table.insert(lines, { Text = Format.Clock(hour, C.Settings.Get("Clock24")) .. "  " .. (def and (def.Icon .. " " .. def.Name) or entry.Weather), Size = Theme.Sizes.Small })
		end
		table.insert(lines, { Text = "Click for the calendar (U)", Color = "SubText", Size = Theme.Sizes.Tiny })
		return lines
	end)
end

local function updateClock()
	if not clock then
		return
	end
	local visible = C.Settings.Get("ShowClock") ~= false
	local panel = clock.Time.Parent :: Frame
	panel.Visible = visible
	if not visible then
		return
	end
	local info = GameTime.Info()
	clock.Time.Text = Format.Clock(info.Hour, C.Settings.Get("Clock24"))
	clock.Date.Text = string.format("%s %s %d · %s · Year %d", (require(Shared.Config.Seasons) :: any)[info.Season].Icon, info.SeasonName, info.DayOfSeason, GameTime.WEEKDAYS[info.Weekday], info.Year)
	local weatherId = C.Lighting.Weather()
	local def = WeatherMath.Def(weatherId)
	clock.Weather.Text = (if def then def.Icon .. " " .. def.Name else weatherId) .. (if info.FullMoon and info.IsNight then "  🌕 Full moon" else "")
	local region = C.Lighting.Region()
	clock.Region.Text = "📍 " .. (if region then region.Name else "Evergrove")
	clock.Sun.Text = if info.IsNight then (if info.FullMoon then "🌕" else "🌙") elseif info.Hour < 8 then "🌅" elseif info.Hour > 18 then "🌇" else "☀️"
	clock.Day.Size = UDim2.fromScale(info.Hour / 24, 1)
end

-- Currency & menu ---------------------------------------------------------------------------------------------------

local MENU = {
	{ Id = "Inventory", Icon = "🎒", Tip = "Backpack (B)" },
	{ Id = "Quests", Icon = "📜", Tip = "Quests (J)" },
	{ Id = "Map", Icon = "🗺️", Tip = "Map (M)" },
	{ Id = "Collection", Icon = "📖", Tip = "Collection book (C)", Wide = true },
	{ Id = "Crafting", Icon = "🔨", Tip = "Crafting (V)", Wide = true },
	{ Id = "Skills", Icon = "🌟", Tip = "Skills (K)", Wide = true },
	{ Id = "Mail", Icon = "✉️", Tip = "Mailbox (N)", Wide = true },
	{ Id = "Social", Icon = "👥", Tip = "Friends, visits & guild (O)", Wide = true },
	{ Id = "Daily", Icon = "🎁", Tip = "Daily gift", Wide = true },
	{ Id = "Store", Icon = "🛍️", Tip = "Cosmetics store", Wide = true },
	{ Id = "Menu", Icon = "☰", Tip = "Menu (`)" },
}

local function buildTopRight()
	local column = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(620, 100), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 10), Name = "TopRight", Parent = root })
	local money = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), Parent = column })
	Kit.List(money, "X", 8, "Right")
	local coins
	coins, coinsLabel = pill(money, "Coins", 150)
	local tokens
	tokens, tokensLabel = pill(money, "Tokens", 96)
	tokens.LayoutOrder = 1
	Kit.AttachTooltip(coins, function()
		return { { Text = "Coins", Bold = true }, { Text = "Earned by selling, quests and contracts.", Color = "SubText", Size = Theme.Sizes.Small } }
	end)
	Kit.AttachTooltip(tokens, function()
		return { { Text = "Festival tokens", Bold = true }, { Text = "Won at festivals; spent at festival stalls.", Color = "SubText", Size = Theme.Sizes.Small } }
	end)
	local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 46), Position = UDim2.fromOffset(0, 44), Name = "Menu", Parent = column })
	Kit.List(row, "X", 6, "Right")
	local compact = C.UI.IsCompact()
	for i, entry in MENU do
		if compact and entry.Wide then
			continue
		end
		local button = Kit.IconButton(entry.Icon, entry.Tip, function()
			if entry.Id == "Daily" then
				C.Windows.Toggle("Daily")
			else
				C.Windows.Toggle(entry.Id)
			end
		end, 44)
		button.LayoutOrder = i
		button.Name = entry.Id
		button.Parent = row
		local badge = Kit.new("TextLabel", { Name = "Badge", Size = UDim2.fromOffset(20, 20), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -4, 0, 4), Font = Theme.Fonts.Bold, TextSize = 12, Text = "", Visible = false, ZIndex = 4, Parent = button })
		Kit.Paint(badge, "BackgroundColor3", "Bad")
		badge.TextColor3 = Color3.new(1, 1, 1)
		Kit.Corner(badge, 10)
		badges[entry.Id] = badge
	end
end

local function setBadgeValue(name: string, value: boolean | number)
	local badge = badges[name]
	if not badge then
		return
	end
	local was = badge.Visible
	if value == false or value == 0 then
		badge.Visible = false
	else
		badge.Visible = true
		badge.Text = if type(value) == "number" then (if value > 9 then "9+" else tostring(value)) else "!"
		if not was then
			Kit.Pulse(badge)
		end
	end
end

local function computeBadges()
	local p = profile()
	if not p then
		return
	end
	-- Mail: unread letters.
	local unread = 0
	for _, mail in (p.Mail and p.Mail.List) or {} do
		if not mail.Read then
			unread += 1
		end
	end
	-- Quests: ready to turn in.
	local ready = 0
	for _, state in (p.Quests and p.Quests.Active) or {} do
		if state.Ready then
			ready += 1
		end
	end
	-- Skills: unspent points.
	local points = 0
	for _, skill in require(Shared.Config.Skills).List do
		points += math.max(0, Stats.PointsAvailable(p, skill.Id))
	end
	local today = math.floor(workspace:GetServerTimeNow() / 86400)
	local daily = p.Daily and p.Daily.Last ~= today
	setBadgeValue("Mail", manualBadges.Mail or unread)
	setBadgeValue("Quests", manualBadges.Quests or ready)
	setBadgeValue("Skills", manualBadges.Skills or points)
	setBadgeValue("Daily", manualBadges.Daily or daily == true)
	for name, value in manualBadges do
		if name ~= "Mail" and name ~= "Quests" and name ~= "Skills" and name ~= "Daily" then
			setBadgeValue(name, value)
		end
	end
	-- Menu collects everything hidden on compact layouts.
	if C.UI.IsCompact() then
		setBadgeValue("Menu", unread + points + (if daily then 1 else 0))
	end
end

function HUD.SetBadge(name: string, on: boolean | number)
	if on == false or on == 0 then
		manualBadges[name] = nil
	else
		manualBadges[name] = on
	end
	computeBadges()
end

local function updateMoney(animate: boolean)
	local p = profile()
	if not p then
		return
	end
	tokensLabel.Text = "🎟️ " .. Format.Short(p.Tokens or 0)
	local target = p.Coins or 0
	if not animate or Kit.ReducedMotion or math.abs(target - shownCoins) < 2 then
		shownCoins = target
		coinsLabel.Text = "🪙 " .. Format.Commas(target)
		return
	end
	-- Count up/down smoothly.
	local from = shownCoins
	shownCoins = target
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 0.6 do
			if shownCoins ~= target then
				return
			end
			local a = (os.clock() - t0) / 0.6
			coinsLabel.Text = "🪙 " .. Format.Commas(math.floor(from + (target - from) * (1 - (1 - a) ^ 3)))
			RunService.RenderStepped:Wait()
		end
		coinsLabel.Text = "🪙 " .. Format.Commas(target)
	end)
end

function HUD.FlashCoins(amount: number)
	if not coinsLabel then
		return
	end
	local pillFrame = coinsLabel.Parent :: Frame
	Kit.Pulse(pillFrame)
	local float = Kit.Label((if amount >= 0 then "+" else "−") .. Format.Commas(math.abs(amount)), { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold, Color = if amount >= 0 then "Good" else "Bad", Align = "Right" })
	float.Size = UDim2.fromOffset(150, 20)
	float.AnchorPoint = Vector2.new(1, 0)
	float.Position = UDim2.new(1, -14, 0, 48)
	float.ZIndex = 10
	float.Parent = root
	Kit.Tween(float, { Position = UDim2.new(1, -14, 0, 64), TextTransparency = 1 }, 1.4)
	task.delay(1.5, function()
		float:Destroy()
	end)
end

-- Hotbar & dock ---------------------------------------------------------------------------------------------------------

local function refreshHotbar()
	local p = profile()
	if not p then
		return
	end
	local invSlots = p.Inventory and p.Inventory.Slots or {}
	for i = 1, HOTBAR do
		local stack = invSlots[tostring(i)]
		slots[i].Set(stack)
		local def = stack and Registry.Items[stack.Id]
		if def and def.Tool then
			local tier = (p.Tools and p.Tools[def.Tool]) or 1
			tierLabels[i].Text = ROMAN[tier] or tostring(tier)
		else
			tierLabels[i].Text = ""
		end
	end
	HUD.SelectHotbar(p.Hotbar or 0, true)
end

local function refreshHeld()
	local p = profile()
	if not p or not heldLabel then
		return
	end
	local stack = p.Inventory and p.Inventory.Slots and p.Inventory.Slots[tostring(p.Hotbar or 0)]
	if not stack then
		heldLabel.Text = ""
		heldLabel.Visible = false
		return
	end
	local text = (Kit.ItemIcon(stack.Id)) .. " " .. ItemUtil.DisplayName(stack)
	local max = C.Input.MaxArea()
	if max > 1 then
		local size = C.Input.AreaSize()
		text ..= "  ·  ⬛ " .. size .. "×" .. size .. (if C.Settings.PrimaryInput() == "Keyboard" then " (R)" else "")
	end
	local def = Registry.Items[stack.Id]
	if def and def.Tool == "can" then
		text ..= "  ·  💧 " .. math.floor(p.Water or 0) .. "/" .. waterCapacity(p)
	end
	heldLabel.Text = text
	heldLabel.Visible = true
end

function HUD.SelectHotbar(slot: number, quiet: boolean?)
	if slots[selected] then
		slots[selected].SetSelected(false)
	end
	selected = slot
	if slots[slot] then
		slots[slot].SetSelected(true)
		if not quiet then
			C.Audio.PlayUI("UIHover")
		end
	end
	refreshHeld()
end

local function refreshBars()
	local p = profile()
	if not p then
		return
	end
	local maxEnergy = Stats.MaxEnergy(p)
	local energy = p.Energy or 0
	energyBar.Set(energy / maxEnergy, "⚡ " .. math.floor(energy) .. " / " .. maxEnergy)
	energyBar.SetColor(if energy / maxEnergy < 0.15 then "Bad" elseif energy / maxEnergy < 0.35 then "Warn" else "Good")
	local cap = waterCapacity(p)
	waterBar.Set((p.Water or 0) / cap, "💧 " .. math.floor(p.Water or 0) .. " / " .. cap)
	refreshHeld()
end

local function refreshXP()
	local p = profile()
	if not p or not xpBar then
		return
	end
	-- Follow the skill that most recently gained XP.
	for skillId, entry in p.Skills or {} do
		local xp = entry.XP or 0
		if lastXP[skillId] and xp > lastXP[skillId] then
			lastSkill = skillId
		end
		lastXP[skillId] = xp
	end
	local skill = Registry.Skills[lastSkill]
	local entry = p.Skills and p.Skills[lastSkill]
	local level, into, need = Stats.LevelFor(entry and entry.XP or 0)
	local frame = xpBar.Frame :: Frame
	frame.Visible = C.Settings.Get("ShowXPBar") ~= false
	if need > 0 then
		xpBar.Set(into / need)
		xpLabel.Text = (if skill then skill.Icon .. " " .. skill.Name else lastSkill) .. " " .. level .. "  ·  " .. Format.Commas(into) .. " / " .. Format.Commas(need) .. " XP"
	else
		xpBar.Set(1)
		xpLabel.Text = (if skill then skill.Icon .. " " .. skill.Name else lastSkill) .. " " .. level .. "  ·  MAX"
	end
	xpLabel.Visible = frame.Visible
end

local function refreshBuffs()
	local p = profile()
	if not p or not buffRow then
		return
	end
	Kit.Clear(buffRow)
	local now = GameTime.Now()
	local order = 0
	for id, buff in p.Buffs or {} do
		local remaining = (buff.Until or 0) - now
		if remaining > 0 then
			order += 1
			local chip = Kit.Panel({ Size = UDim2.fromOffset(0, 26), Corner = 13, Name = id })
			chip.AutomaticSize = Enum.AutomaticSize.X
			chip.LayoutOrder = order
			Kit.Padding(chip, 0, 8)
			local label = Kit.Label((BUFF_ICONS[id] or "✨") .. " " .. Format.Duration(remaining), { Size = Theme.Sizes.Tiny, Font = Theme.Fonts.Bold })
			label.Size = UDim2.fromOffset(0, 26)
			label.AutomaticSize = Enum.AutomaticSize.X
			label.Parent = chip
			chip.Parent = buffRow
			Kit.AttachTooltip(chip, function()
				return { { Text = (BUFF_ICONS[id] or "✨") .. " " .. id .. " ×" .. string.format("%.2f", buff.Mult or 1), Bold = true }, { Text = Format.Duration(math.max(0, (buff.Until or 0) - GameTime.Now())) .. " left", Color = "SubText" } }
			end)
		end
	end
end

local function buildDock()
	local dock = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(HOTBAR * 62, 150), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Name = "Dock", Parent = root })
	-- Hint line
	hintLabel = Kit.Label("", { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold, Align = "Center" })
	hintLabel.Size = UDim2.new(1, 0, 0, 20)
	hintLabel.Position = UDim2.fromOffset(0, -44)
	hintLabel.TextStrokeTransparency = 0.5
	hintLabel.TextTransparency = 1
	hintLabel.Parent = dock
	-- Held item & buffs
	heldLabel = Kit.Label("", { Size = Theme.Sizes.Small, Align = "Center" })
	heldLabel.Size = UDim2.new(1, 0, 0, 20)
	heldLabel.Position = UDim2.fromOffset(0, -20)
	heldLabel.TextStrokeTransparency = 0.6
	heldLabel.Parent = dock
	buffRow = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 4), Name = "Buffs", Parent = dock })
	Kit.List(buffRow, "X", 6, "Center")
	-- Energy & water
	local bars = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 36), Parent = dock })
	energyBar = Kit.Progress({ Size = UDim2.new(0.5, -4, 1, 0), Color = "Good" })
	energyBar.Frame.Parent = bars
	waterBar = Kit.Progress({ Size = UDim2.new(0.5, -4, 1, 0), Color = "Info" })
	waterBar.Frame.Position = UDim2.new(0.5, 4, 0, 0)
	waterBar.Frame.Parent = bars
	Kit.AttachTooltip(energyBar.Frame, function()
		return { { Text = "Energy", Bold = true }, { Text = "Tools and actions use energy. Eat or drink to restore it; it also refills slowly over time, and grows with your skills and house.", Color = "SubText", Size = Theme.Sizes.Small, } }
	end)
	Kit.AttachTooltip(waterBar.Frame, function()
		return { { Text = "Watering can", Bold = true }, { Text = "Refill at a well, pond or river with the can in hand.", Color = "SubText", Size = Theme.Sizes.Small } }
	end)
	-- XP
	xpBar = Kit.Progress({ Size = UDim2.new(1, 0, 0, 6), Color = "Accent" })
	xpBar.Frame.Position = UDim2.fromOffset(0, 60)
	xpBar.Frame.Parent = dock
	xpLabel = Kit.Label("", { Size = Theme.Sizes.Tiny, Color = "SubText", Align = "Center" })
	xpLabel.Size = UDim2.new(1, 0, 0, 14)
	xpLabel.Position = UDim2.fromOffset(0, 67)
	xpLabel.TextStrokeTransparency = 0.7
	xpLabel.Parent = dock
	-- Slots
	local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 58), Position = UDim2.new(0, 0, 1, -58), Name = "Hotbar", Parent = dock })
	Kit.List(row, "X", 6, "Center")
	for i = 1, HOTBAR do
		local slot = Kit.ItemSlot(56)
		slot.Button.LayoutOrder = i
		slot.Button.Name = "Slot" .. i
		slot.Button.Parent = row
		local key = Kit.new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(14, 12), Position = UDim2.fromOffset(3, 40), Font = Theme.Fonts.Bold, TextSize = 10, Text = tostring(i), TextTransparency = 0.35, Name = "Key", Parent = slot.Button })
		Kit.Paint(key, "TextColor3", "SubText")
		local tier = Kit.new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(26, 12), Position = UDim2.new(1, -28, 0, 2), Font = Theme.Fonts.Bold, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Right, Text = "", Name = "Tier", ZIndex = 3, Parent = slot.Button })
		Kit.Paint(tier, "TextColor3", "Accent")
		tierLabels[i] = tier
		slot.Button.Activated:Connect(function()
			if selected == i then
				C.Input.SelectHotbar(0)
			else
				C.Input.SelectHotbar(i)
			end
		end)
		slot.Button.MouseButton2Click:Connect(function()
			C.Input.SelectHotbar(i)
			C.Input.UseItem()
		end)
		slots[i] = slot
	end
	-- Shift the dock by the player's HotbarLeft setting.
	local function place()
		dock.Position = UDim2.new(0.5, C.Settings.Get("HotbarLeft") or 0, 1, -8)
	end
	place()
	C.Settings.Changed:Connect(function(key)
		if key == "HotbarLeft" then
			place()
		elseif key == "ShowXPBar" then
			refreshXP()
		elseif key == "ShowClock" or key == "Clock24" then
			updateClock()
		elseif key == "QuestTracker" or key == "TrackerSide" then
			HUD.RefreshTracker()
		end
	end)
end

function HUD.Hint(text: string)
	if not hintLabel then
		return
	end
	hintToken += 1
	local token = hintToken
	hintLabel.Text = text
	hintLabel.TextTransparency = 0
	hintLabel.TextStrokeTransparency = 0.5
	task.delay(2.5, function()
		if token == hintToken then
			Kit.Tween(hintLabel, { TextTransparency = 1, TextStrokeTransparency = 1 }, 0.4)
		end
	end)
end

-- Quest tracker ---------------------------------------------------------------------------------------------------------

local trackerCollapsed = false

local function buildTracker()
	tracker = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(260, 0), AutomaticSize = Enum.AutomaticSize.Y, Name = "Tracker", Parent = root })
	Kit.List(tracker, "Y", 4)
	trackerHeader = Kit.new("TextButton", { AutoButtonColor = false, Text = "", Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 0.25, LayoutOrder = 0, Parent = tracker })
	Kit.Paint(trackerHeader, "BackgroundColor3", "HeaderA")
	Kit.Corner(trackerHeader, 8)
	local title = Kit.Label("📜 Quests", { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold, Color = "HeaderText" })
	title.Name = "Title"
	title.Size = UDim2.new(1, -16, 1, 0)
	title.Position = UDim2.fromOffset(8, 0)
	title.Parent = trackerHeader
	trackerHeader.Activated:Connect(function()
		trackerCollapsed = not trackerCollapsed
		C.Audio.PlayUI("UIClick")
		HUD.RefreshTracker()
	end)
	trackerList = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = tracker })
	Kit.List(trackerList, "Y", 4)
end

function HUD.RefreshTracker()
	if not tracker then
		return
	end
	local p = profile()
	local mode = C.Settings.Get("QuestTracker") or "Expanded"
	local side = C.Settings.Get("TrackerSide") or "Left"
	tracker.AnchorPoint = Vector2.new(if side == "Right" then 1 else 0, 0)
	tracker.Position = if side == "Right" then UDim2.new(1, -14, 0, 112) else UDim2.fromOffset(14, 116)
	if mode == "Hidden" or not p then
		tracker.Visible = false
		return
	end
	tracker.Visible = true
	Kit.Clear(trackerList)
	local tracked = (p.Quests and p.Quests.Tracked) or {}
	local title = trackerHeader:FindFirstChild("Title") :: TextLabel
	title.Text = "📜 Quests (" .. #tracked .. ")  " .. (if trackerCollapsed or mode == "Minimized" then "▸" else "▾")
	if trackerCollapsed or mode == "Minimized" then
		return
	end
	if #tracked == 0 then
		local empty = Kit.Label("No tracked quests. Press J to pick some.", { Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true })
		empty.TextStrokeTransparency = 0.7
		empty.Parent = trackerList
		return
	end
	for i, questId in tracked do
		local quest = Registry.Quests[questId]
		local state = p.Quests.Active[questId]
		if quest and state then
			local card = Kit.new("TextButton", { AutoButtonColor = false, Text = "", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 0.3, LayoutOrder = i, Parent = trackerList })
			Kit.Paint(card, "BackgroundColor3", "Panel")
			Kit.Corner(card, 8)
			Kit.Padding(card, 6, 8)
			Kit.List(card, "Y", 2)
			card.Activated:Connect(function()
				C.Windows.Open("Quests", { Quest = questId })
			end)
			local name = Kit.Label((if state.Ready then "✔️ " else "") .. quest.Name, { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold, Color = if state.Ready then "Good" else "Text" })
			name.Parent = card
			if state.Ready then
				local npc = quest.TurnIn and Registry.Npcs[quest.TurnIn]
				local line = Kit.Label("Return to " .. (if npc then npc.Icon .. " " .. npc.Name else "the quest giver"), { Size = Theme.Sizes.Tiny, Color = "SubText" })
				line.LayoutOrder = 1
				line.Parent = card
			else
				for j, objective in quest.Objectives do
					local cur, goal = Describe.Progress(p, objective, state.P and state.P[j])
					local done = cur >= goal
					local line = Kit.Label((if done then "☑ " else "☐ ") .. Describe.Objective(objective) .. (if goal > 1 then "  " .. Format.Short(cur) .. "/" .. Format.Short(goal) else ""), { Size = Theme.Sizes.Tiny, Color = if done then "Good" else "SubText", Wrap = true })
					line.LayoutOrder = j
					line.Parent = card
				end
			end
		end
	end
end

-- Top-centre pills ------------------------------------------------------------------------------------------------------

local function ownerOfLot(lotId: any): Player?
	for _, other in Players:GetPlayers() do
		if other:GetAttribute("Lot") == lotId then
			return other
		end
	end
	return nil
end

local function currentLot(): Instance?
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local farms = workspace:FindFirstChild("Farms")
	if not rootPart or not farms then
		return nil
	end
	for _, lot in farms:GetChildren() do
		local origin = lot:GetAttribute("Origin")
		if typeof(origin) == "Vector3" then
			local rel = rootPart.Position - origin
			if rel.X >= -2 and rel.X <= 242 and rel.Z >= -46 and rel.Z <= 242 then
				return lot
			end
		end
	end
	return nil
end

local function updatePills()
	-- Visiting someone else's farm?
	local lot = currentLot()
	local owner = lot and ownerOfLot(lot:GetAttribute("Lot"))
	local visiting = owner ~= nil and owner ~= player
	if visiting and not visitPill then
		local frame = Kit.Panel({ Size = UDim2.fromOffset(0, 36), Corner = 18, Name = "Visiting" })
		frame.AutomaticSize = Enum.AutomaticSize.X
		frame.LayoutOrder = 1
		Kit.Padding(frame, 4, 12)
		Kit.List(frame, "X", 8, "Center")
		local label = Kit.Label("", { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold })
		label.Name = "Text"
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.fromOffset(0, 28)
		label.Parent = frame
		local home = Kit.Button("Go home", { Style = "Accent", Size = UDim2.fromOffset(90, 28), TextSize = Theme.Sizes.Tiny, OnClick = function()
			local ok, err = Net.Request("GoHome")
			if not ok then
				C.Notify.Toast(tostring(err), "Warning")
			end
		end })
		home.LayoutOrder = 1
		home.Parent = frame
		frame.Parent = topPills
		Kit.Pop(frame)
		visitPill = frame
	elseif not visiting and visitPill then
		visitPill:Destroy()
		visitPill = nil
	end
	if visitPill and owner then
		local label = visitPill:FindFirstChild("Text") :: TextLabel
		local farmName = owner:GetAttribute("FarmName")
		label.Text = "🏡 Visiting " .. (if farmName and farmName ~= "" then tostring(farmName) else owner.DisplayName .. "'s farm")
	end
	-- Festival?
	local festivalId = ReplicatedStorage:GetAttribute("Festival")
	if festivalId and not festivalPill then
		local def = Registry.Festivals[festivalId]
		local frame = Kit.Panel({ Size = UDim2.fromOffset(0, 36), Corner = 18, Name = "Festival", Color = "Accent" })
		frame.AutomaticSize = Enum.AutomaticSize.X
		frame.LayoutOrder = 2
		Kit.Padding(frame, 4, 14)
		local button = Kit.new("TextButton", { BackgroundTransparency = 1, Text = (if def then def.Icon .. " " .. def.Name else "🎪 Festival") .. " — today! ▸", Font = Theme.Fonts.Bold, TextSize = Theme.Text(Theme.Sizes.Small), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 28), Parent = frame })
		Kit.Paint(button, "TextColor3", "AccentText")
		button.Activated:Connect(function()
			C.Windows.Open("Festival")
		end)
		frame.Parent = topPills
		Kit.Pop(frame)
		festivalPill = frame
	elseif not festivalId and festivalPill then
		festivalPill:Destroy()
		festivalPill = nil
	end
end

-- Node health bars ---------------------------------------------------------------------------------------------------------

local function findNode(nid: string): Model?
	for _, folderName in { "ResourceNodes", "Farms" } do
		local folder = workspace:FindFirstChild(folderName)
		local model = folder and folder:FindFirstChild(nid, true)
		if model and model:IsA("Model") then
			return model
		end
	end
	return nil
end

function HUD.NodeHealth(nid: string, hp: number, max: number)
	local model = findNode(nid)
	if not model or max <= 0 then
		return
	end
	local entry = nodeBars[nid]
	if not entry or not entry.Gui.Parent then
		local gui = Instance.new("BillboardGui")
		gui.Name = "NodeHealth"
		gui.Size = UDim2.fromOffset(90, 12)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		local _, size = model:GetBoundingBox()
		gui.StudsOffsetWorldSpace = Vector3.new(0, size.Y / 2 + 1.5, 0)
		gui.Adornee = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		local back = Kit.new("Frame", { BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(30, 30, 30), BackgroundTransparency = 0.3, Parent = gui })
		Kit.Corner(back, 6)
		local fill = Kit.new("Frame", { BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(120, 220, 110), Parent = back })
		Kit.Corner(fill, 6)
		gui.Parent = C.UI.Root()
		entry = { Gui = gui, Fill = fill, Until = 0 }
		nodeBars[nid] = entry
	end
	local e = entry :: { Gui: BillboardGui, Fill: Frame, Until: number }
	local fraction = math.clamp(hp / max, 0, 1)
	Kit.Tween(e.Fill, { Size = UDim2.fromScale(fraction, 1) }, 0.15)
	e.Fill.BackgroundColor3 = Color3.fromRGB(230, 90, 70):Lerp(Color3.fromRGB(120, 220, 110), fraction)
	e.Until = os.clock() + 3
	if hp <= 0 then
		e.Until = os.clock() + 0.4
	end
	task.delay(3.1, function()
		local current = nodeBars[nid]
		if current and os.clock() >= current.Until then
			current.Gui:Destroy()
			nodeBars[nid] = nil
		end
	end)
end

-- Touch controls ---------------------------------------------------------------------------------------------------------

local function buildTouch()
	if touchCluster or not UserInputService.TouchEnabled then
		return
	end
	local cluster = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(210, 210), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -150, 1, -30), Name = "Touch", Parent = root })
	local function button(icon: string, tip: string, size: number, pos: UDim2, fn: () -> ())
		local b = Kit.new("TextButton", { AutoButtonColor = false, Text = icon, Font = Theme.Fonts.Body, TextSize = math.floor(size * 0.45), Size = UDim2.fromOffset(size, size), AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, BackgroundTransparency = 0.25, Name = tip, Parent = cluster })
		Kit.Paint(b, "BackgroundColor3", "Panel")
		Kit.Corner(b, size // 2)
		Kit.Stroke(b, "Stroke", 2)
		b.Activated:Connect(function()
			Kit.Pulse(b)
			fn()
		end)
		return b
	end
	button("✋", "Use", 84, UDim2.new(1, -46, 1, -46), function()
		C.Input.Use()
	end)
	button("🍎", "Item", 54, UDim2.new(1, -130, 1, -30), function()
		C.Input.UseItem()
	end)
	button("⬛", "Area", 50, UDim2.new(1, -118, 1, -100), function()
		C.Input.CycleArea()
	end)
	button("🛠️", "Build", 50, UDim2.new(1, -58, 1, -140), function()
		C.Build.Toggle()
	end)
	button("🎒", "Bag", 50, UDim2.new(1, -170, 1, -150), function()
		C.Windows.Toggle("Inventory")
	end)
	touchCluster = cluster
end

-- Visibility -------------------------------------------------------------------------------------------------------------

-- Hide the HUD while photo mode runs or build mode shows its own panels.
local function updateVisibility()
	local hidden = C.Photo.Active()
	root.Visible = not hidden
	local building = C.Build.Active()
	for _, name in { "Dock", "Tracker", "Touch" } do
		local child = root:FindFirstChild(name)
		if child and child:IsA("GuiObject") then
			child.Visible = not building and (name ~= "Tracker" or (C.Settings.Get("QuestTracker") or "Expanded") ~= "Hidden")
		end
	end
end
HUD.UpdateVisibility = updateVisibility

-- Lifecycle ----------------------------------------------------------------------------------------------------------------

function HUD.Start()
	layer = C.UI.Layer("HUD")
	root = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Name = "HUD", Parent = layer })
	buildClock()
	buildTopRight()
	topPills = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0, 520, 0, 36), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Name = "Pills", Parent = root })
	Kit.List(topPills, "X", 8, "Center")
	buildTracker()
	buildDock()
	buildTouch()
	Kit.RepaintGradients(root)

	C.State.Watch("Coins", function()
		updateMoney(true)
	end)
	C.State.Watch("Tokens", function()
		updateMoney(false)
	end)
	C.State.Watch("Inventory", function()
		refreshHotbar()
		HUD.RefreshTracker()
	end)
	C.State.Watch("Hotbar", function(slot)
		HUD.SelectHotbar(slot or 0, true)
	end)
	C.State.Watch("Tools", refreshHotbar)
	for _, key in { "Energy", "Water", "Skills" } do
		C.State.Watch(key, function()
			refreshBars()
			if key == "Skills" then
				refreshXP()
				computeBadges()
			end
		end)
	end
	C.State.Watch("Buffs", refreshBuffs)
	C.State.Watch("Quests", function()
		HUD.RefreshTracker()
		computeBadges()
	end)
	C.State.Watch("Mail", computeBadges)
	C.State.Watch("Daily", computeBadges)
	C.State.Loaded:Connect(function()
		local p = profile()
		for skillId, entry in (p and p.Skills) or {} do
			lastXP[skillId] = entry.XP or 0
		end
		updateMoney(false)
		refreshHotbar()
		refreshBars()
		refreshXP()
		refreshBuffs()
		HUD.RefreshTracker()
		computeBadges()
	end)
	C.Windows.Opened:Connect(function()
		Kit.HideTooltip()
	end)
	player:GetAttributeChangedSignal("Region"):Connect(function()
		local region = C.Lighting.Region()
		if region then
			C.Notify.Banner(region.Icon .. " " .. region.Name, region.Description, nil, "Region", 3)
		end
		updateClock()
	end)
	ReplicatedStorage:GetAttributeChangedSignal("Festival"):Connect(updatePills)
	-- Slow ticker: clock, buffs countdown, pills, visibility.
	task.spawn(function()
		local n = 0
		while true do
			updateClock()
			updateVisibility()
			n += 1
			if n % 2 == 0 then
				updatePills()
			end
			if n % 4 == 0 then
				refreshBuffs()
				computeBadges()
			end
			task.wait(0.5)
		end
	end)
	-- Gamepad hint for the hotbar bumpers.
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		HUD.Hint("LB / RB to change tools · RT to use · Y to use item")
	end
	GuiService.MenuOpened:Connect(function()
		Kit.HideTooltip()
	end)
end

return HUD

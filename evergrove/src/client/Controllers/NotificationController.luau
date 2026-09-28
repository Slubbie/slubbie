-- Toasts, banners, reward pops, discovery reveals, level-ups, achievements,
-- quest events and sound captions.
--
-- The "Notifications" setting filters noise: All / Important (no item pops or
-- info toasts) / Minimal (only banners, level-ups and errors).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local ItemUtil = require(Shared.Lib.ItemUtil)
local Format = require(Shared.Lib.Format)
local Collections = require(Shared.Lib.Collections)

local C = require(script.Parent)
local UIFolder = script.Parent.Parent:WaitForChild("UI")
local Kit = require(UIFolder.Kit)
local Theme = require(UIFolder.Theme)

local Notify = {}

local toastColumn: Frame
local bannerHost: Frame
local popColumn: Frame
local captionLabel: TextLabel
local bannerQueue: { () -> () } = {}
local bannerBusy = false

local KIND_STYLE = {
	Info = { Icon = "💬", Key = "Info" },
	Success = { Icon = "✅", Key = "Good" },
	Warning = { Icon = "⚠️", Key = "Warn" },
	Error = { Icon = "⛔", Key = "Bad" },
}

local function level(): string
	return C.Settings.Get("Notifications") or "All"
end

-- Toasts --------------------------------------------------------------------------------------------------------------

function Notify.Toast(text: string, kind: string?)
	local k = kind or "Info"
	local lvl = level()
	if (lvl == "Important" and k == "Info") or (lvl == "Minimal" and k ~= "Error") then
		return
	end
	local style = KIND_STYLE[k] or KIND_STYLE.Info
	local card = Kit.Panel({ Size = UDim2.new(1, 0, 0, 0), Shadow = true, Name = "Toast" })
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.LayoutOrder = -os.clock() * 1000
	Kit.Padding(card, 8, 10)
	local accent = Kit.new("Frame", { BorderSizePixel = 0, Size = UDim2.new(0, 4, 1, 0), Position = UDim2.fromOffset(-10, 0), Parent = card })
	Kit.Paint(accent, "BackgroundColor3", style.Key)
	local label = Kit.Label(style.Icon .. "  " .. text, { Wrap = true, Size = Theme.Sizes.Small, Rich = false })
	label.Parent = card
	card.Parent = toastColumn
	Kit.Pop(card, 0.8)
	if k == "Error" then
		C.Audio.PlayUI("UIError")
	elseif k == "Success" then
		C.Audio.PlayUI("Notification")
	end
	-- Keep at most five.
	local cards = {}
	for _, child in toastColumn:GetChildren() do
		if child:IsA("Frame") then
			table.insert(cards, child)
		end
	end
	table.sort(cards, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 6, #cards do
		cards[i]:Destroy()
	end
	task.delay(4 + #text / 40, function()
		if card.Parent then
			Kit.Tween(card, { BackgroundTransparency = 1 }, 0.3)
			Kit.PopOut(card, function()
				card:Destroy()
			end)
			task.delay(0.35, function()
				if card.Parent then
					card:Destroy()
				end
			end)
		end
	end)
end

-- Banners ----------------------------------------------------------------------------------------------------------------

local function runBanner(title: string, subtitle: string?, icon: string?, style: string?, duration: number?)
	bannerBusy = true
	local panel = Kit.Panel({ Size = UDim2.fromOffset(620, 0), Shadow = true, Color = "Panel" })
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 0)
	Kit.Padding(panel, 14, 22)
	Kit.List(panel, "Y", 4, "Center")
	local ribbon = Kit.new("Frame", { BorderSizePixel = 0, Size = UDim2.new(1, 44, 0, 6), Position = UDim2.fromOffset(-22, -14), Parent = panel })
	Kit.Paint(ribbon, "BackgroundColor3", if style == "Legend" or style == "Festival" then "Accent" else "HeaderA")
	Kit.Gradient(ribbon, "HeaderA", "Accent", 0)
	local t = Kit.Label((icon and icon .. "  " or "") .. title, { Size = 28, Font = Theme.Fonts.Heading, Align = "Center", Wrap = true })
	t.Parent = panel
	if subtitle and subtitle ~= "" then
		local s = Kit.Label(subtitle, { Size = Theme.Sizes.Body, Align = "Center", Color = "SubText", Wrap = true })
		s.LayoutOrder = 1
		s.Parent = panel
	end
	panel.Parent = bannerHost
	Kit.Pop(panel, 0.6)
	C.Audio.PlayUI(if style == "Legend" then "LegendaryReveal" else "QuestComplete")
	task.delay(duration or 4.5, function()
		Kit.PopOut(panel, function()
			panel:Destroy()
		end)
		task.delay(0.3, function()
			if panel.Parent then
				panel:Destroy()
			end
			bannerBusy = false
			local nextBanner = table.remove(bannerQueue, 1)
			if nextBanner then
				nextBanner()
			end
		end)
	end)
end

function Notify.Banner(title: string, subtitle: string?, icon: string?, style: string?, duration: number?)
	local run = function()
		runBanner(title, subtitle, icon, style, duration)
	end
	if bannerBusy then
		if #bannerQueue < 6 then
			table.insert(bannerQueue, run)
		end
	else
		run()
	end
end

-- Reward pops ----------------------------------------------------------------------------------------------------------

function Notify.ItemPop(stack: any)
	if level() ~= "All" then
		return
	end
	local def = Registry.Items[stack.Id]
	if not def then
		return
	end
	-- Merge with an existing pop for the same item.
	local key = ItemUtil.Key(stack)
	for _, child in popColumn:GetChildren() do
		if child:GetAttribute("Key") == key then
			local n = (child:GetAttribute("N") or 0) + stack.N
			child:SetAttribute("N", n)
			local label = child:FindFirstChild("Text") :: TextLabel?
			if label then
				label.Text = "+" .. Format.Commas(n) .. "  " .. ItemUtil.DisplayName(stack)
			end
			Kit.Pulse(child :: GuiObject)
			child:SetAttribute("Until", os.clock() + 3)
			return
		end
	end
	local rarity = ItemUtil.Rarity(stack)
	local card = Kit.Panel({ Size = UDim2.fromOffset(250, 40), Corner = 10, Name = "Pop" })
	card:SetAttribute("Key", key)
	card:SetAttribute("N", stack.N)
	card:SetAttribute("Until", os.clock() + 3)
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Theme.RarityColor(rarity)
	end
	Kit.new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(34, 34), Position = UDim2.fromOffset(4, 3), Text = def.Icon or "📦", TextScaled = true, Font = Theme.Fonts.Body, Parent = card })
	local text = Kit.Label("+" .. Format.Commas(stack.N) .. "  " .. ItemUtil.DisplayName(stack), { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold })
	text.Name = "Text"
	text.Size = UDim2.new(1, -46, 1, 0)
	text.Position = UDim2.fromOffset(42, 0)
	text.TextColor3 = if stack.Q and stack.Q > 1 then Theme.QualityColor(stack.Q) else text.TextColor3
	text.Parent = card
	card.Parent = popColumn
	Kit.Pop(card, 0.7)
	C.Audio.PlayUI(if Registry.RarityOrder(rarity) >= 4 then "HarvestRare" else "ItemPickup")
	task.spawn(function()
		while card.Parent and os.clock() < (card:GetAttribute("Until") or 0) do
			task.wait(0.25)
		end
		if card.Parent then
			Kit.PopOut(card, function()
				card:Destroy()
			end)
			task.delay(0.3, function()
				if card.Parent then
					card:Destroy()
				end
			end)
		end
	end)
end

function Notify.Coins(amount: number, _reason: string?)
	if amount == 0 then
		return
	end
	C.Audio.PlayUI("Coins")
	C.HUD.FlashCoins(amount)
end

-- Reveals ---------------------------------------------------------------------------------------------------------------

function Notify.Discovery(payload: any)
	local cat = Collections.Get(payload.Category)
	local rarity = payload.Rarity or "Common"
	local order = Registry.RarityOrder(rarity)
	local dramatic = order >= 5
	Notify.Banner(
		(payload.Icon or "📖") .. " New " .. (if cat then cat.Name else "discovery") .. "!",
		(payload.Name or payload.Id) .. " · " .. Theme.Rarity(rarity).Glyph .. " " .. rarity,
		nil,
		if dramatic then "Legend" else "Discovery",
		if dramatic then 6 else 3
	)
	if dramatic then
		C.FX.ScreenFlash(Theme.RarityColor(rarity))
	else
		C.Audio.PlayUI("Discovery")
	end
end

function Notify.LevelUp(payload: any)
	local skill = Registry.Skills[payload.Skill]
	local name = if skill then skill.Name else payload.Skill
	Notify.Banner((if skill then skill.Icon .. " " else "") .. name .. " level " .. payload.Level .. "!", "You earned a skill point. Open Skills (K) to spend it.", nil, "LevelUp", 4)
	C.Audio.PlayUI("LevelUp")
	C.FX.LevelUpBurst()
end

function Notify.Achievement(id: string)
	local def
	for _, a in require(Shared.Config.Achievements).List do
		if a.Id == id then
			def = a
		end
	end
	if not def then
		return
	end
	local card = Kit.Panel({ Size = UDim2.fromOffset(330, 74), Shadow = true, Name = "Achievement" })
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0.5, 0, 1, -150)
	Kit.Padding(card, 8, 12)
	Kit.new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(52, 52), Text = def.Icon or "🏅", TextScaled = true, Font = Theme.Fonts.Body, Parent = card })
	local title = Kit.Label("Achievement unlocked", { Size = Theme.Sizes.Tiny, Color = "SubText" })
	title.Position = UDim2.fromOffset(62, 2)
	title.Size = UDim2.new(1, -62, 0, 16)
	title.Parent = card
	local name = Kit.Label(def.Name, { Size = Theme.Sizes.Heading, Font = Theme.Fonts.Heading })
	name.Position = UDim2.fromOffset(62, 18)
	name.Size = UDim2.new(1, -62, 0, 26)
	name.Parent = card
	card.Parent = C.UI.Layer("Overlay")
	Kit.Pop(card, 0.6)
	C.Audio.PlayUI("QuestComplete")
	task.delay(4, function()
		Kit.PopOut(card, function()
			card:Destroy()
		end)
		task.delay(0.3, function()
			if card.Parent then
				card:Destroy()
			end
		end)
	end)
end

function Notify.Quest(payload: any)
	local quest = Registry.Quests[payload.Id]
	local name = payload.Name or (quest and quest.Name) or payload.Id
	if payload.Event == "Started" then
		Notify.Toast("📜 New quest: " .. name, "Success")
		C.Audio.PlayUI("Notification")
	elseif payload.Event == "Ready" then
		local npc = payload.TurnIn and Registry.Npcs[payload.TurnIn]
		Notify.Toast("✔️ " .. name .. " is ready to turn in" .. (if npc then " to " .. npc.Name else "") .. "!", "Success")
	elseif payload.Event == "Completed" then
		Notify.Banner("Quest complete!", name, "📜", "Quest", 3.5)
	end
	C.HUD.RefreshTracker()
end

-- Captions -------------------------------------------------------------------------------------------------------------

local captionUntil = 0
local function showCaption(text: string)
	captionLabel.Text = text
	captionLabel.Visible = true
	captionUntil = os.clock() + 2.5
	task.delay(2.6, function()
		if os.clock() >= captionUntil then
			captionLabel.Visible = false
		end
	end)
end

-- Lifecycle ----------------------------------------------------------------------------------------------------------

function Notify.Init()
	local overlay = C.UI.Layer("Overlay")
	toastColumn = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(330, 400), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 70), Name = "Toasts", Parent = overlay })
	Kit.List(toastColumn, "Y", 6)
	bannerHost = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 200), Position = UDim2.fromOffset(0, 70), Name = "Banners", Parent = overlay })
	popColumn = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(260, 320), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -120), Name = "Pops", Parent = overlay })
	local popLayout = Kit.List(popColumn, "Y", 4)
	popLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	captionLabel = Kit.new("TextLabel", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.4,
		TextColor3 = Color3.new(1, 1, 1),
		Font = Theme.Fonts.Bold,
		TextSize = Theme.Text(16),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 28),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -170),
		Visible = false,
		Name = "Caption",
		Parent = overlay,
	})
	Kit.Corner(captionLabel, 6)
	Kit.Padding(captionLabel, 2, 10)
	C.Audio.Caption:Connect(showCaption)

	Net.On("Notify", function(kind: string, payload: any)
		payload = payload or {}
		if kind == "Toast" then
			Notify.Toast(payload.Text, payload.Kind)
		elseif kind == "Banner" then
			Notify.Banner(payload.Title, payload.Subtitle, payload.Icon, payload.Style)
		elseif kind == "Reward" then
			for _, stack in payload.Items or {} do
				Notify.ItemPop(stack)
			end
			if (payload.Coins or 0) > 0 then
				Notify.Coins(payload.Coins, payload.Source)
			end
		elseif kind == "Coins" then
			Notify.Coins(payload.Amount, payload.Reason)
		elseif kind == "Discovery" then
			Notify.Discovery(payload)
		elseif kind == "LevelUp" then
			Notify.LevelUp(payload)
		elseif kind == "Achievement" then
			Notify.Achievement(payload.Id)
		elseif kind == "Quest" then
			Notify.Quest(payload)
		elseif kind == "Tutorial" then
			C.Tutorial.Show(payload.Step)
		end
	end)
end

return Notify

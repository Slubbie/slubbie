-- Quests: merchant orders, daily objectives and milestones in one panel with tabs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Dicebound.Config)
local Format = require(ReplicatedStorage.Dicebound.Format)
local ClientState = require(script.Parent.Parent.ClientState)
local Sound = require(script.Parent.Parent.Sound)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)
local Panels = require(script.Parent.Panels)
local Toasts = require(script.Parent.Toasts)
local ItemIcon = require(script.Parent.ItemIcon)
local Effects = require(script.Parent.Effects)

local C = Theme.Colors

local QuestsPanel = {}

local TABS = { "Orders", "Daily", "Milestones" }

-- Unlocked copies the player could hand over (mirrors the server's rule).
local function available(data, itemId: string, mutation: string?): number
	local n = 0
	for _, stack in data.Bag do
		if stack.Id == itemId and not stack.Locked and (mutation == nil or stack.Mut == mutation) then
			n += stack.Qty
		end
	end
	return n
end

local function statValue(data, stat: string): number
	if data.StatValues[stat] then
		return data.StatValues[stat]
	end
	return data.Stats[stat] or 0
end

local DAILY_TEXT = {}
for _, template in Config.Economy.Dailies.Pool do
	DAILY_TEXT[template.Id] = template.Text
end

function QuestsPanel.new()
	local content = Panels.Create("Quests", "Quests", "📜")
	local tab = "Orders"
	local refresh: () -> ()
	local setTab = Kit.Tabs(content, TABS, function(name)
		tab = name
		refresh()
	end)
	local list = Kit.Scroll(content, { Position = UDim2.fromOffset(0, 48), Size = UDim2.new(1, 0, 1, -48) })
	local busy = false
	local receivedAt = os.clock()

	local function act(name: string, ...)
		if busy then
			return nil
		end
		busy = true
		local result = ClientState.Request(name, ...)
		busy = false
		if not result.ok then
			Sound.Play("Error")
			Toasts.Show(result.err, "error")
		end
		return result
	end

	local function claimed(reward: number, text: string)
		Sound.Play("Purchase")
		Effects.Coins(8)
		Toasts.Show(text .. " +🪙 " .. Format.Coins(reward), "reward")
	end

	local function row(order: number, height: number): Frame
		return Kit.Card({ Parent = list, Size = UDim2.new(1, -12, 0, height), LayoutOrder = order })
	end

	local function ordersTab(data)
		local near = ClientState.NearMerchant() ~= nil
		Kit.Label({
			Parent = list,
			Size = UDim2.new(1, -12, 0, 36),
			Text = "Merchants pay well above sell price for exactly what they ask for. Hand orders in at any merchant stall. Locked items are never used; plain copies go first.",
			TextSize = 13,
			TextColor3 = C.InkSoft,
			LayoutOrder = 0,
		})
		local elapsed = os.clock() - receivedAt
		for i, slot in data.Orders.Slots do
			local card = row(i, 104)
			if slot.ItemId then
				local item = Config.Items.ById[slot.ItemId]
				local icon = ItemIcon.Create(slot.ItemId, slot.Mut, 72)
				icon.Position = UDim2.fromOffset(14, 16)
				icon.Parent = card
				local have = available(data, slot.ItemId, slot.Mut)
				local sells = Config.ItemValue(slot.ItemId, slot.Mut) * slot.Qty
				Kit.Label({
					Parent = card,
					Position = UDim2.fromOffset(100, 10),
					Size = UDim2.new(1, -300, 0, 22),
					Text = (slot.Giver or "A merchant") .. " wants:",
					TextSize = 13,
					TextColor3 = C.InkSoft,
				})
				Kit.Label({
					Parent = card,
					Position = UDim2.fromOffset(100, 30),
					Size = UDim2.new(1, -300, 0, 26),
					Text = string.format("%d× %s", slot.Qty, ItemIcon.Name(slot.ItemId, slot.Mut))
						.. (if slot.Mut then "" else "  (any variant)"),
					Font = Theme.Fonts.Title,
					TextSize = 18,
				})
				Kit.Label({
					Parent = card,
					Position = UDim2.fromOffset(100, 58),
					Size = UDim2.new(1, -300, 0, 40),
					Text = string.format(
						"You have %d/%d  ·  %s  ·  Reward 🪙 %s (selling pays 🪙 %s)",
						math.min(have, slot.Qty),
						slot.Qty,
						Theme.RarityText(item.Rarity),
						Format.Coins(slot.Reward),
						Format.Coins(sells)
					),
					TextSize = 13,
					Font = Theme.Fonts.Bold,
					TextColor3 = if have >= slot.Qty then C.GreenDark else C.InkSoft,
				})
				local deliver = Kit.Button({
					Parent = card,
					Text = "Deliver 🪙 " .. Format.Coins(slot.Reward),
					Color = C.Green,
					Size = UDim2.fromOffset(180, 46),
					Position = UDim2.new(1, -190, 0, 8),
					TextSize = 16,
					OnClick = function()
						local result = act("FulfillOrder", i)
						if result and result.ok then
							claimed(result.Reward, "📜 Order complete!")
						end
					end,
				})
				deliver:SetEnabled(near and have >= slot.Qty)
				local skip = Kit.Button({
					Parent = card,
					Text = if data.Orders.SkipIn - elapsed > 0
						then string.format("Skip in %ds", math.ceil(data.Orders.SkipIn - elapsed))
						else "Skip",
					Color = C.InkFaint,
					Size = UDim2.fromOffset(180, 36),
					Position = UDim2.new(1, -190, 0, 60),
					TextSize = 14,
					OnClick = function()
						act("SkipOrder", i)
					end,
				})
				skip:SetEnabled(data.Orders.SkipIn - elapsed <= 0)
				if not near then
					deliver:SetText("Visit a merchant")
				end
			else
				local wait = math.max(0, slot.ReadyAt - data.Orders.ServerTime - elapsed)
				Kit.Label({
					Parent = card,
					Size = UDim2.fromScale(1, 1),
					Text = string.format("📬 A new order arrives in %s", Format.Seconds(wait)),
					TextSize = 16,
					TextColor3 = C.InkSoft,
					TextXAlignment = Enum.TextXAlignment.Center,
				})
			end
		end
	end

	local function progressRow(
		order: number,
		title: string,
		progress: number,
		goal: number,
		reward: number,
		done: boolean,
		onClaim: () -> ()
	)
		local card = row(order, 76)
		Kit.Label({
			Parent = card,
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.new(1, -220, 0, 24),
			Text = (if done then "✓ " else "") .. title,
			Font = Theme.Fonts.Bold,
			TextSize = 16,
			TextColor3 = if done then C.InkFaint else C.Ink,
		})
		local bar = Kit.Bar({
			Parent = card,
			Position = UDim2.fromOffset(14, 40),
			Size = UDim2.new(1, -240, 0, 12),
			Color = if progress >= goal then C.Green else C.Gold,
		})
		bar:Set(progress / goal)
		Kit.Label({
			Parent = card,
			Position = UDim2.new(1, -220, 0, 34),
			AnchorPoint = Vector2.new(1, 0),
			Size = UDim2.fromOffset(0, 24),
			AutomaticSize = Enum.AutomaticSize.X,
			Text = string.format("%s / %s", Format.Coins(math.min(progress, goal)), Format.Coins(goal)),
			TextSize = 13,
			TextColor3 = C.InkSoft,
			TextWrapped = false,
		})
		local button = Kit.Button({
			Parent = card,
			Text = if done then "Claimed" else "Claim 🪙 " .. Format.Coins(reward),
			Color = C.Gold,
			TextColor = C.Ink,
			Size = UDim2.fromOffset(180, 46),
			Position = UDim2.new(1, -190, 0, 15),
			TextSize = 15,
			OnClick = onClaim,
		})
		button:SetEnabled(not done and progress >= goal)
	end

	local function dailyTab(data)
		local elapsed = os.clock() - receivedAt
		Kit.Label({
			Parent = list,
			Size = UDim2.new(1, -12, 0, 24),
			Text = string.format(
				"Optional daily goals. New ones in %s. Missing a day costs nothing.",
				Format.Seconds(math.max(0, data.Daily.ResetIn - elapsed))
			),
			TextSize = 13,
			TextColor3 = C.InkSoft,
			LayoutOrder = 0,
		})
		for i, entry in data.Daily.List do
			local text = string.format(DAILY_TEXT[entry.Id] or "%d", entry.Goal)
			progressRow(i, text, entry.Progress, entry.Goal, entry.Reward, entry.Claimed, function()
				local result = act("ClaimDaily", i)
				if result and result.ok then
					claimed(result.Reward, "✅ Daily objective!")
				end
			end)
		end
	end

	local function milestonesTab(data)
		local ordered = table.clone(Config.Economy.Milestones)
		table.sort(ordered, function(a, b)
			local ad, bd = data.Milestones[a.Id] == true, data.Milestones[b.Id] == true
			if ad ~= bd then
				return bd
			end
			local ap = statValue(data, a.Stat) / a.Goal
			local bp = statValue(data, b.Stat) / b.Goal
			return ap > bp
		end)
		for i, m in ordered do
			local progress = statValue(data, m.Stat)
			progressRow(i, "🏆 " .. m.Name, progress, m.Goal, m.Reward, data.Milestones[m.Id] == true, function()
				local result = act("ClaimMilestone", m.Id)
				if result and result.ok then
					claimed(result.Reward, "🏆 " .. m.Name .. "!")
				end
			end)
		end
	end

	function refresh()
		local data = ClientState.Data
		if not data or not Panels.IsOpen("Quests") then
			return
		end
		setTab(tab)
		Kit.Clear(list)
		if tab == "Orders" then
			ordersTab(data)
		elseif tab == "Daily" then
			dailyTab(data)
		else
			milestonesTab(data)
		end
	end

	ClientState.Changed:Connect(function()
		receivedAt = os.clock()
		refresh()
	end)
	Panels.Opened:Connect(function(name, options)
		if name == "Quests" then
			if type(options) == "string" and table.find(TABS, options) then
				tab = options
			end
			refresh()
			-- Refresh countdowns now and then (only while an order timer is running, so buttons
			-- aren't rebuilt under the player's finger).
			task.spawn(function()
				while Panels.IsOpen("Quests") do
					task.wait(5)
					local data = ClientState.Data
					local waiting = data and data.Orders.SkipIn > 0
					for _, slot in (data and data.Orders.Slots or {}) do
						if not slot.ItemId then
							waiting = true
						end
					end
					if Panels.IsOpen("Quests") and tab == "Orders" and waiting then
						refresh()
					end
				end
			end)
		end
	end)
end

return QuestsPanel

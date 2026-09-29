-- Player-to-player trading: both offers side by side, coins, a review delay
-- after every change, and two-sided confirmation. The server swaps the
-- goods atomically and saves both players straight away.
--
-- Trade.OnEvent(payload) handles the "Trade" channel: requests, live state,
-- declines and the end of a trade.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local ItemUtil = require(Shared.Lib.ItemUtil)
local Social = require(Shared.Config.Social)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Picker = require(UI.Picker)
local C = require(UI.Parent.Controllers)

local state: any = nil
local handle: any = nil

local Screen = {
	Id = "Trade",
	Title = "Trade",
	Icon = "🤝",
	Size = Vector2.new(900, 560),
}

local function request(action: string, ...: any): (boolean, any)
	local ok, result = Net.Request(action, ...)
	if not ok and result then
		C.Notify.Toast(tostring(result), "Warning")
	end
	return ok, result
end

function Screen.OnEvent(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if payload.Request then
		C.Audio.PlayUI("Notification")
		Kit.Confirm("Trade request", payload.Name .. " would like to trade with you.", function(yes)
			request("TradeRespond", payload.From, yes)
		end, "Trade")
	elseif payload.Declined then
		C.Notify.Toast(payload.Name .. " declined your trade.", "Info")
	elseif payload.Closed then
		state = nil
		if C.Windows.IsOpen("Trade") then
			C.Windows.Close(true)
		end
		C.Notify.Toast(
			"🤝 " .. tostring(payload.Reason or "Trade closed"),
			if payload.Reason == "Trade complete!" then "Success" else "Info"
		)
		if payload.Reason == "Trade complete!" then
			C.Audio.PlayUI("QuestComplete")
		end
	elseif payload.Id then
		state = payload
		if C.Windows.IsOpen("Trade") and handle then
			handle.Refresh()
		else
			C.Windows.Open("Trade")
		end
	end
end

function Screen.Build(win)
	local content = win.Content :: Frame
	local alive = true
	local confirmButton: TextButton? = nil

	local function side(parent: Instance, offer: any, mine: boolean, xScale: number)
		local panel = Kit.Panel({
			Size = UDim2.new(0.5, -6, 1, -56),
			Position = UDim2.new(xScale, if xScale > 0 then 6 else 0, 0, 0),
			Color = "PanelAlt",
		})
		panel.Parent = parent
		Kit.Padding(panel, 10, 12)
		local title = Kit.Heading(
			(if mine then "Your offer" else offer.Name .. "'s offer") .. (if offer.Ready then "  ✔ ready" else ""),
			18
		)
		title.TextColor3 = if offer.Ready then Color3.fromRGB(120, 210, 120) else title.TextColor3
		title.Parent = panel
		local grid = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, -110),
			Position = UDim2.fromOffset(0, 34),
			Parent = panel,
		})
		Kit.Grid(grid, 60, 6)
		for i = 1, Social.Trading.MaxSlots do
			local stack = offer.Items[i]
			local slot = Kit.ItemSlot(60)
			slot.Button.LayoutOrder = i
			slot.Set(if stack and stack.N > 0 then stack else nil)
			slot.Button.Parent = grid
			if mine and stack then
				slot.Button.Activated:Connect(function()
					request("TradeRemove", i)
				end)
			elseif mine and i == #offer.Items + 1 then
				slot.Button.Activated:Connect(function()
					Picker.Open({
						Title = "Offer an item",
						Filter = function(s)
							return ItemUtil.Tradable(s) and not s.L
						end,
						Empty = "Nothing tradable in your bag (tools, locked and bound items can't be traded).",
						OnPick = function(ref, s)
							if s.N > 1 then
								Kit.AskNumber("Offer how many?", s.N, s.N, function(n)
									if n then
										request("TradeOffer", ref, n)
									end
								end)
							else
								request("TradeOffer", ref, 1)
							end
						end,
					})
				end)
				local plus = Kit.new("TextLabel", {
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					Text = "+",
					TextScaled = true,
					Font = Theme.Fonts.Bold,
					TextTransparency = 0.5,
					Parent = slot.Button,
				})
				Kit.Paint(plus, "TextColor3", "SubText")
			end
		end
		local coins = Kit.Label(
			Kit.Money(offer.Coins or 0),
			{ Size = Theme.Sizes.Body, Font = Theme.Fonts.Number, Color = "Accent" }
		)
		coins.Position = UDim2.new(0, 0, 1, -66)
		coins.Size = UDim2.new(1, -130, 0, 28)
		coins.Parent = panel
		if mine then
			local set = Kit.Button("Set coins", {
				Style = "Secondary",
				Size = UDim2.fromOffset(120, 30),
				TextSize = Theme.Sizes.Tiny,
				OnClick = function()
					local wallet = C.State.Get("Coins") or 0
					Kit.AskNumber("Offer how many coins?", math.max(1, wallet), offer.Coins or 0, function(n)
						if n then
							request("TradeCoins", n)
						end
					end)
				end,
			})
			set.Position = UDim2.new(1, -120, 1, -66)
			set.Parent = panel
		end
		local note = Kit.Label(
			if mine then "Click an item to take it back." else "Hover items to inspect them.",
			{ Size = Theme.Sizes.Tiny, Color = "SubText" }
		)
		note.Position = UDim2.new(0, 0, 1, -30)
		note.Size = UDim2.new(1, 0, 0, 20)
		note.Parent = panel
	end

	local function render()
		Kit.Clear(content)
		if not state then
			Kit.Empty("No trade in progress. Ask someone to trade from the Friends menu (O).").Parent = content
			return
		end
		win.Title.Text = "🤝  Trading with " .. state.Them.Name
		side(content, state.Me, true, 0)
		side(content, state.Them, false, 0.5)
		local footer = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 46),
			Position = UDim2.new(0, 0, 1, -46),
			Parent = content,
		})
		Kit.List(footer, "X", 10, "Right")
		Kit.Button("Cancel trade", {
			Style = "Danger",
			Size = UDim2.fromOffset(150, 44),
			OnClick = function()
				request("TradeCancel")
			end,
		}).Parent =
			footer
		local confirm =
			Kit.Button(if state.Me.Ready then "Waiting for " .. state.Them.Name .. "…" else "✔ Confirm", {
				Style = "Good",
				Size = UDim2.fromOffset(240, 44),
				OnClick = function()
					local ok, result = request("TradeConfirm")
					if ok and result and result.Waiting then
						C.Notify.Toast("Waiting for " .. state.Them.Name .. " to confirm", "Info")
					end
				end,
			})
		confirm.LayoutOrder = 1
		confirm.Parent = footer
		confirmButton = confirm
		Kit.SetEnabled(confirm, not state.Me.Ready and (state.ConfirmIn or 0) <= 0)
		state.ReceivedAt = state.ReceivedAt or os.clock()
		Kit.RepaintGradients(content)
	end

	-- Enable Confirm once the review delay passes.
	task.spawn(function()
		while alive do
			if state and confirmButton and confirmButton.Parent then
				local left = (state.ConfirmIn or 0) - (os.clock() - (state.ReceivedAt or os.clock()))
				if not state.Me.Ready then
					if left > 0 then
						confirmButton.Text = string.format("Review… %d", math.ceil(left))
						Kit.SetEnabled(confirmButton, false)
					else
						confirmButton.Text = "✔ Confirm"
						Kit.SetEnabled(confirmButton, true)
					end
				end
			end
			task.wait(0.25)
		end
	end)

	render()
	handle = {
		Refresh = function()
			if state then
				state.ReceivedAt = os.clock()
			end
			render()
		end,
		Destroy = function()
			alive = false
			handle = nil
			-- Closing the window cancels an unfinished trade.
			if state then
				task.spawn(Net.Request, "TradeCancel")
			end
		end,
	}
	return handle
end

return Screen

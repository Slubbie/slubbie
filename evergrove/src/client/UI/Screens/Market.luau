-- The market: live prices with history and demand, bulk contracts from the
-- villagers, and overseas export crates. Everything here is transparent:
-- the same formula the server uses (Prices / MarketMath) drives the numbers.
-- Args: { Tab = "Prices" | "Contracts" | "Export" }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local ItemUtil = require(Shared.Lib.ItemUtil)
local Format = require(Shared.Lib.Format)
local GameTime = require(Shared.Lib.GameTime)
local MarketMath = require(Shared.Lib.MarketMath)
local Economy = require(Shared.Config.Economy)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Prices = require(UI.Prices)
local C = require(UI.Parent.Controllers)

local EXPORT = Economy.Selling.Export

-- A tiny bar chart of price factors.
local function sparkline(values: { number }, forecast: { number }?): Frame
	local frame = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(150, 34) })
	local all = table.clone(values)
	for _, v in ipairs(forecast or {}) do
		table.insert(all, v)
	end
	local lo, hi = math.huge, -math.huge
	for _, v in all do
		lo = math.min(lo, v)
		hi = math.max(hi, v)
	end
	local span = math.max(hi - lo, 0.05)
	local width = 1 / #all
	for i, v in all do
		local bar = Kit.new("Frame", { BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Size = UDim2.new(width, -1, (v - lo) / span * 0.85 + 0.15, 0), Position = UDim2.new((i - 1) * width, 0, 1, 0), Parent = frame })
		local isForecast = i > #values
		Kit.Paint(bar, "BackgroundColor3", if isForecast then "Info" elseif v >= 1 then "Good" else "Warn")
		bar.BackgroundTransparency = if isForecast then 0.5 else 0.1
	end
	return frame
end

return {
	Id = "Market",
	Title = "Market",
	Icon = "📈",
	Size = Vector2.new(940, 620),
	Watch = { "Contracts", "Exports", "Inventory" },
	Build = function(win, ctx)
		local args = ctx.Args or {}
		local content = win.Content :: Frame
		local body = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -46), Position = UDim2.fromOffset(0, 46), Parent = content })
		local current = args.Tab or "Prices"
		local market: any = nil
		local query = ""
		local exportPick: { [string]: boolean } = {}
		local render: () -> ()

		-- Prices ---------------------------------------------------------------------------------------------------
		local function renderPrices()
			local profile = C.State.Data()
			local info = GameTime.Info()
			local header = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 58), Parent = body })
			local hot = {}
			for _, id in MarketMath.HotItems(info.Day) do
				local def = Registry.Items[id]
				table.insert(hot, if def then def.Icon .. " " .. def.Name else id)
			end
			local shortage = MarketMath.Shortage(info.Day)
			local shortDef = shortage and Registry.Items[shortage]
			local news = Kit.Label("🔥 Hot today (×" .. Economy.Market.HotItems.Multiplier .. "): " .. table.concat(hot, ", ") .. (if shortDef then "\n⚠️ Shortage (×" .. Economy.Market.Shortage.Multiplier .. "): " .. shortDef.Icon .. " " .. shortDef.Name else "") .. (if market and market.Event and market.Event > 1 then "\n🌙 Night market: +" .. math.floor((market.Event - 1) * 100) .. "% on everything" else ""), { Size = Theme.Sizes.Small, Wrap = true })
			news.Parent = header
			local search = Kit.TextBox("🔍 Look up any item's price…", { Size = UDim2.new(1, 0, 0, 32), Text = query })
			search.Position = UDim2.fromOffset(0, 62)
			search.Parent = body
			local list = Kit.Scroll({ Size = UDim2.new(1, 0, 1, -100), Position = UDim2.fromOffset(0, 100) })
			list.Parent = body
			Kit.List(list, "Y", 4)
			local function fill()
				Kit.Clear(list)
				local ids: { string } = {}
				local seen = {}
				local function add(id: string)
					if not seen[id] and Registry.Items[id] then
						seen[id] = true
						table.insert(ids, id)
					end
				end
				if query ~= "" then
					local q = string.lower(query)
					for _, id in MarketMath.Tradable do
						local def = Registry.Items[id]
						if string.find(string.lower(def.Name), q, 1, true) then
							add(id)
						end
						if #ids >= 40 then
							break
						end
					end
				else
					for _, id in (market and market.Tracked) or {} do
						add(id)
					end
					for _, id in MarketMath.HotItems(info.Day) do
						add(id)
					end
					if shortage then
						add(shortage)
					end
					for _, stack in (profile and profile.Inventory.Slots) or {} do
						if ItemUtil.Sellable(stack) then
							add(stack.Id)
						end
					end
				end
				if #ids == 0 then
					Kit.Empty("Search for an item, or carry something sellable to see its price.").Parent = list
					return
				end
				local tracked = {}
				for _, id in (market and market.Tracked) or {} do
					tracked[id] = true
				end
				for i, id in ids do
					local def = Registry.Items[id]
					local factor = Prices.Factor(id)
					local label, emoji = MarketMath.DemandLabel(factor)
					local row = Kit.Card(56)
					row.LayoutOrder = i
					row.Parent = list
					local slot = Kit.ItemSlot(40)
					slot.Button.Active = false
					slot.Set({ Id = id, N = 1 })
					slot.Button.Parent = row
					local name = Kit.Label(def.Name, { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold })
					name.Position = UDim2.fromOffset(48, 0)
					name.Size = UDim2.new(0.35, -48, 0, 20)
					name.Parent = row
					local price = Kit.Label(Kit.Money(math.floor(def.Value * factor)) .. "  (base " .. Format.Commas(def.Value) .. ")", { Size = Theme.Sizes.Tiny, Color = "SubText" })
					price.Position = UDim2.fromOffset(48, 20)
					price.Size = UDim2.new(0.35, -48, 0, 16)
					price.Parent = row
					local demand = Kit.Label(emoji .. " " .. label .. string.format("  ×%.2f", factor), { Size = Theme.Sizes.Small, Color = if factor >= 1.12 then "Good" elseif factor < 0.92 then "Bad" else "Text" })
					demand.Position = UDim2.new(0.35, 0, 0, 8)
					demand.Size = UDim2.new(0.25, 0, 0, 20)
					demand.Parent = row
					local history = MarketMath.History(id, GameTime.Now(), 20)
					local forecast = if market and market.Insight then MarketMath.Forecast(id, GameTime.Now(), 6) else nil
					local chart = sparkline(history, forecast)
					chart.Position = UDim2.new(0.6, 0, 0, 2)
					chart.Parent = row
					Kit.AttachTooltip(chart, function()
						return { { Text = "Last 20 in-game hours" .. (if forecast then " + 6-hour forecast (Market Savvy)" else "") }, { Text = "Supply pressure: −" .. math.floor((Prices.Snapshot.Pressure[id] or 0) * 100) .. "%", Color = "SubText", Size = Theme.Sizes.Tiny } }
					end)
					local star = Kit.Button(if tracked[id] then "★" else "☆", { Style = "Ghost", Size = UDim2.fromOffset(40, 34), OnClick = function()
						local ok = Net.Request("MarketTrack", id, not tracked[id])
						if ok then
							local ok2, data = Net.Request("MarketGet")
							if ok2 then
								market = data
								Prices.SetSnapshot(data)
							end
							fill()
						end
					end })
					star.Position = UDim2.new(1, -42, 0, 2)
					star.Parent = row
					Kit.AttachTooltip(star, function()
						return { { Text = if tracked[id] then "Stop watching" else "Watch this price" } }
					end)
				end
				Kit.RepaintGradients(list)
			end
			search:GetPropertyChangedSignal("Text"):Connect(function()
				query = search.Text
				fill()
			end)
			fill()
		end

		-- Contracts ---------------------------------------------------------------------------------------------------
		local function contractCard(contract: any, active: boolean, order: number, parent: Instance)
			local profile = C.State.Data()
			local def = Registry.Items[contract.Item]
			local npc = Registry.Npcs[contract.Npc]
			local card = Kit.Card(88)
			card.LayoutOrder = order
			card.Parent = parent
			local slot = Kit.ItemSlot(52)
			slot.Button.Active = false
			slot.Set({ Id = contract.Item, N = contract.Count, Q = contract.Quality })
			slot.Button.Parent = card
			local kind = if contract.Kind == "Collector" then "🧾 Collector" elseif contract.Kind == "Restaurant" then "🍽️ Restaurant order" else "📋 Bulk order"
			local title = Kit.Label(kind .. " · " .. contract.Count .. " × " .. (if def then def.Name else contract.Item) .. (if contract.Quality then " (" .. Theme.QualityTier(contract.Quality).Name .. "+)" else ""), { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold })
			title.Position = UDim2.fromOffset(62, 0)
			title.Size = UDim2.new(1, -190, 0, 20)
			title.Parent = card
			local have = 0
			for _, stack in (profile and profile.Inventory.Slots) or {} do
				if stack.Id == contract.Item and (stack.Q or 1) >= (contract.Quality or 1) then
					have += stack.N
				end
			end
			local left = contract.Expires - GameTime.Now()
			local sub = Kit.Label((if npc then "for " .. npc.Icon .. " " .. npc.Name .. " · " else "") .. "pays " .. Kit.Money(contract.Pay) .. " · " .. (if left > 0 then Format.Duration(left) .. " left" else "expired"), { Size = Theme.Sizes.Tiny, Color = "SubText" })
			sub.Position = UDim2.fromOffset(62, 22)
			sub.Size = UDim2.new(1, -190, 0, 16)
			sub.Parent = card
			local progress = Kit.Progress({ Size = UDim2.new(1, -190, 0, 12), Color = if have >= contract.Count then "Good" else "Accent" })
			progress.Frame.Position = UDim2.fromOffset(62, 46)
			progress.Frame.Parent = card
			progress.Set(have / contract.Count, have .. " / " .. contract.Count, false)
			local button
			if active then
				button = Kit.Button("Deliver", { Style = if have >= contract.Count then "Good" else "Secondary", Size = UDim2.fromOffset(110, 36), TextSize = Theme.Sizes.Small, OnClick = function()
					local ok, result = Net.Request("ContractDeliver", contract.Id)
					if ok then
						C.Audio.PlayUI("QuestComplete")
						C.Notify.Toast("📋 Contract complete: +" .. Kit.Money(result or contract.Pay), "Success")
					else
						C.Notify.Toast(tostring(result), "Warning")
					end
				end })
			else
				button = Kit.Button("Accept", { Style = "Primary", Size = UDim2.fromOffset(110, 36), TextSize = Theme.Sizes.Small, OnClick = function()
					local ok, err = Net.Request("ContractAccept", contract.Id)
					if not ok then
						C.Notify.Toast(tostring(err), "Warning")
					else
						C.Audio.PlayUI("UIConfirm")
					end
				end })
			end
			button.Position = UDim2.new(1, -112, 0, 18)
			button.Parent = card
		end

		local function renderContracts()
			local profile = C.State.Data()
			local contracts = profile and profile.Contracts or { Board = {}, Active = {} }
			local list = Kit.Scroll({ Size = UDim2.fromScale(1, 1) })
			list.Parent = body
			Kit.List(list, "Y", 6)
			local h1 = Kit.Heading("Your contracts (" .. #contracts.Active .. " / " .. Economy.Contracts.MaxActive .. ")", 18)
			h1.LayoutOrder = 0
			h1.Parent = list
			if #contracts.Active == 0 then
				local e = Kit.Label("No active contracts. Accept one below, gather the goods and deliver them to the villager.", { Size = Theme.Sizes.Small, Color = "SubText", Wrap = true })
				e.LayoutOrder = 1
				e.Parent = list
			end
			for i, contract in contracts.Active do
				contractCard(contract, true, 1 + i, list)
			end
			local h2 = Kit.Heading("Today's board", 18)
			h2.LayoutOrder = 100
			h2.Parent = list
			local note = Kit.Label("New orders every morning. Collector requests unlock with Beatrix; restaurant orders once you know a recipe.", { Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true })
			note.LayoutOrder = 101
			note.Parent = list
			for i, contract in contracts.Board or {} do
				contractCard(contract, false, 101 + i, list)
			end
			Kit.RepaintGradients(list)
		end

		-- Export -------------------------------------------------------------------------------------------------------
		local function renderExport()
			local profile = C.State.Data()
			local left = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.6, -8, 1, 0), Parent = body })
			local right = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.4, -8, 1, 0), Position = UDim2.new(0.6, 8, 0, 0), Parent = body })
			local intro = Kit.Label("Old Wendell ships crates overseas from the harbour. Buyers pay a premium (" .. math.floor(EXPORT.Premium * 100) .. "–" .. math.floor(EXPORT.MaxPremium * 100) .. "%) after " .. EXPORT.DeliveryDays .. " days; storms can delay a boat, never sink it. Preserves and export goods earn extra.", { Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true })
			intro.Parent = left
			local list = Kit.Scroll({ Size = UDim2.new(1, 0, 1, -110), Position = UDim2.fromOffset(0, 50) })
			list.Parent = left
			Kit.List(list, "Y", 4)
			local total = 0
			local order = 0
			for key, stack in (profile and profile.Inventory.Slots) or {} do
				local ref = "inv:" .. key
				if ItemUtil.Sellable(stack) and not stack.L then
					order += 1
					local on = exportPick[ref] == true
					local value = Prices.Unit(profile, stack) * stack.N
					if on then
						total += value
					end
					local row = Kit.new("TextButton", { AutoButtonColor = false, Text = "", Size = UDim2.new(1, -8, 0, 40), LayoutOrder = order, Parent = list })
					Kit.Paint(row, "BackgroundColor3", if on then "SlotHover" else "PanelAlt")
					Kit.Corner(row, 8)
					local label = Kit.Label((if on then "☑  " else "☐  ") .. Kit.ItemIcon(stack.Id) .. " " .. ItemUtil.DisplayName(stack) .. " ×" .. stack.N, { Size = Theme.Sizes.Small })
					label.Size = UDim2.new(1, -120, 1, 0)
					label.Position = UDim2.fromOffset(10, 0)
					label.Parent = row
					local worth = Kit.Label(Kit.Money(value), { Size = Theme.Sizes.Small, Align = "Right", Color = "Accent" })
					worth.Size = UDim2.new(0, 110, 1, 0)
					worth.Position = UDim2.new(1, -116, 0, 0)
					worth.Parent = row
					row.Activated:Connect(function()
						if on then
							exportPick[ref] = nil
						else
							exportPick[ref] = true
						end
						render()
					end)
				end
			end
			if order == 0 then
				Kit.Empty("Nothing to export.").Parent = list
			end
			local premium = math.min(EXPORT.MaxPremium, EXPORT.Premium + math.floor(total / 10000) * EXPORT.BulkPremiumPer10k)
			local summary = Kit.Label("Crate value " .. Kit.Money(total) .. "  →  about " .. Kit.Money(math.floor(total * (1 + premium))) .. " (+" .. math.floor(premium * 100) .. "%)", { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold })
			summary.Position = UDim2.new(0, 0, 1, -54)
			summary.Size = UDim2.new(1, 0, 0, 20)
			summary.Parent = left
			local ship = Kit.Button("🚢 Ship crate", { Style = "Good", Size = UDim2.fromOffset(170, 34), OnClick = function()
				local refs = {}
				for ref in exportPick do
					table.insert(refs, ref)
				end
				local ok, result = Net.Request("ExportShip", refs)
				if ok then
					table.clear(exportPick)
					C.Notify.Toast("🚢 Shipped! About " .. Kit.Money(result.Payout) .. " in " .. result.Days .. " days" .. (if result.Delayed then " (a storm is brewing — expect a delay)" else ""), "Success")
				else
					C.Notify.Toast(tostring(result), "Warning")
				end
				render()
			end })
			ship.Position = UDim2.new(0, 0, 1, -32)
			ship.Parent = left
			Kit.SetEnabled(ship, total >= EXPORT.MinValue)
			if total < EXPORT.MinValue then
				local min = Kit.Label("Minimum crate: " .. Kit.Money(EXPORT.MinValue), { Size = Theme.Sizes.Tiny, Color = "SubText" })
				min.Position = UDim2.new(0, 180, 1, -30)
				min.Size = UDim2.new(1, -180, 0, 28)
				min.Parent = left
			end
			local h = Kit.Heading("At sea (" .. #((profile and profile.Exports) or {}) .. " / " .. EXPORT.MaxActive .. ")", 18)
			h.Parent = right
			local sea = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -34), Position = UDim2.fromOffset(0, 34), Parent = right })
			Kit.List(sea, "Y", 6)
			for i, export in (profile and profile.Exports) or {} do
				local card = Kit.Card(58)
				card.LayoutOrder = i
				card.Parent = sea
				local l = Kit.Label("🚢 " .. export.Count .. " stacks · " .. Kit.Money(export.Payout), { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold })
				l.Parent = card
				local due = export.Due - GameTime.Now()
				local d = Kit.Label((if due > 0 then "arrives in " .. Format.Duration(due) else "arriving — payment by mail") .. (if export.Delayed then " · ⛈️ storm delay" else ""), { Size = Theme.Sizes.Tiny, Color = "SubText" })
				d.Position = UDim2.fromOffset(0, 22)
				d.Parent = card
			end
			Kit.RepaintGradients(body)
		end

		render = function()
			Kit.Clear(body)
			if current == "Prices" then
				renderPrices()
			elseif current == "Contracts" then
				renderContracts()
			else
				renderExport()
			end
		end

		local tabs = Kit.Tabs({ { Id = "Prices", Label = "Prices", Icon = "📈" }, { Id = "Contracts", Label = "Contracts", Icon = "📋" }, { Id = "Export", Label = "Export", Icon = "🚢" } }, function(id)
			current = id
			render()
		end)
		tabs.Frame.Parent = content
		task.spawn(function()
			local ok, data = Net.Request("MarketGet")
			if ok then
				market = data
				Prices.SetSnapshot(data)
				if current == "Prices" then
					render()
				end
			end
			Net.Request("ContractList")
		end)
		tabs.Select(current)
		return {
			Refresh = function()
				if current ~= "Prices" then
					render()
				end
			end,
		}
	end,
}

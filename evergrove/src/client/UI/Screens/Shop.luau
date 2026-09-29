-- A villager's shop: buy (seeds with their growing info, supplies,
-- decorations, festival-token stalls) and sell to the merchant.
-- Args: { Shop = shopId, Npc = npcId, Tab = "Buy" | "Sell" }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local Format = require(Shared.Lib.Format)
local GameTime = require(Shared.Lib.GameTime)
local CropMath = require(Shared.Lib.CropMath)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local SellPanel = require(UI.SellPanel)
local C = require(UI.Parent.Controllers)

local WATER_ICON = { Low = "💧", Medium = "💧💧", High = "💧💧💧" }

local function seedInfo(def: any): { Kit.TipLine }
	local crop = def.Plants and Registry.Crops[def.Plants]
	if not crop then
		return {}
	end
	local info = GameTime.Info()
	local lines: { Kit.TipLine } = {}
	local seasons = table.concat(crop.Seasons, ", ")
	local inSeason = CropMath.InSeason(crop, info.SeasonId)
	table.insert(lines, {
		Text = "🗓️ " .. seasons .. (if inSeason then "  (in season ✓)" else "  (out of season — slow)"),
		Color = if inSeason then "Good" else "Warn",
		Size = Theme.Sizes.Tiny,
	})
	table.insert(lines, {
		Text = "⏱️ Ripe in " .. Format.Duration(crop.Grow) .. (if crop.Regrow
			then " · regrows every " .. Format.Duration(crop.Regrow)
			else ""),
		Size = Theme.Sizes.Tiny,
	})
	table.insert(lines, {
		Text = (WATER_ICON[crop.Water] or "💧")
			.. " "
			.. crop.Water
			.. " water · yields "
			.. crop.Yield[1]
			.. "–"
			.. crop.Yield[2]
			.. " · sells ~"
			.. Kit.Money(crop.Sell),
		Size = Theme.Sizes.Tiny,
	})
	if crop.Night then
		table.insert(lines, { Text = "🌙 Only grows at night", Color = "Info", Size = Theme.Sizes.Tiny })
	end
	if crop.Needs then
		table.insert(
			lines,
			{ Text = "🧪 Needs: " .. string.gsub(crop.Needs, "|", " or "), Color = "Info", Size = Theme.Sizes.Tiny }
		)
	end
	if crop.Special then
		table.insert(lines, { Text = "✨ " .. crop.Special, Color = "Accent", Size = Theme.Sizes.Tiny })
	end
	return lines
end

return {
	Id = "Shop",
	Title = "Shop",
	Icon = "🛒",
	Size = Vector2.new(900, 600),
	Watch = { "Coins", "Tokens", "Inventory" },
	Build = function(win, ctx)
		local args = ctx.Args or {}
		local shopId = args.Shop
		local npcId = args.Npc or (Registry.Shops[shopId] and Registry.Shops[shopId].Owner)
		local content = win.Content :: Frame
		local data: any = nil
		local tab = args.Tab or "Buy"
		local query = ""
		local body = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, -46),
			Position = UDim2.fromOffset(0, 46),
			Parent = content,
		})
		local sellPanel: any = nil
		local renderBuy: () -> ()

		local tabs = Kit.Tabs(
			{ { Id = "Buy", Label = "Buy", Icon = "🛒" }, { Id = "Sell", Label = "Sell", Icon = "💰" } },
			function(id)
				tab = id
				Kit.Clear(body)
				sellPanel = nil
				if id == "Sell" then
					sellPanel = SellPanel.Build(body, "Merchant:" .. tostring(npcId), C)
				else
					renderBuy()
				end
			end
		)
		tabs.Frame.Size = UDim2.new(1, -260, 0, 38)
		tabs.Frame.Parent = content
		local wallet = Kit.Label("", { Size = Theme.Sizes.Small, Font = Theme.Fonts.Number, Align = "Right" })
		wallet.Size = UDim2.new(0, 250, 0, 38)
		wallet.Position = UDim2.new(1, -250, 0, 0)
		wallet.Parent = content
		local function updateWallet()
			wallet.Text = Kit.Money(C.State.Get("Coins") or 0)
				.. "   "
				.. Kit.Money(C.State.Get("Tokens") or 0, "Tokens")
		end

		local function buy(entry: any, def: any)
			local maxByStock = entry.Left or 99
			local wallet2 = if entry.Currency == "Tokens"
				then (C.State.Get("Tokens") or 0)
				else (C.State.Get("Coins") or 0)
			local maxByMoney = math.floor(wallet2 / math.max(entry.Price, 1))
			local max = math.max(1, math.min(maxByStock, maxByMoney, def.Stack or 99))
			local function go(qty: number)
				local ok, err = Net.Request("ShopBuy", shopId, entry.Id, qty)
				if ok then
					C.Audio.PlayUI("Coins")
					C.Notify.ItemPop({ Id = entry.Id, N = qty })
					-- Stock numbers may have changed.
					local ok2, fresh = Net.Request("ShopGet", shopId)
					if ok2 then
						data = fresh
						if tab == "Buy" then
							renderBuy()
						end
					end
				else
					C.Notify.Toast(tostring(err), "Warning")
				end
			end
			if max <= 1 then
				go(1)
			else
				Kit.AskNumber(
					"Buy " .. def.Name .. " (" .. Kit.Money(entry.Price, entry.Currency) .. " each)",
					max,
					if def.Plants then math.min(10, max) else 1,
					function(n)
						if n then
							go(n)
						end
					end
				)
			end
		end

		renderBuy = function()
			Kit.Clear(body)
			if not data then
				Kit.Empty("Opening the shop…").Parent = body
				return
			end
			if not data.Open then
				local hours = data.Hours
				local closed = Kit.Label(
					"🌙 "
						.. data.Name
						.. " is closed right now"
						.. (if hours
							then " (open " .. Format.Clock(hours[1]) .. " – " .. Format.Clock(hours[2]) .. ")"
							else "")
						.. ". You can still look around.",
					{ Size = Theme.Sizes.Small, Color = "Warn", Wrap = true }
				)
				closed.Parent = body
			end
			local search = Kit.TextBox("🔍 Search…", { Size = UDim2.new(1, 0, 0, 32), Text = query })
			search.Position = UDim2.fromOffset(0, if data.Open then 0 else 26)
			search.Parent = body
			local grid = Kit.Scroll({
				Size = UDim2.new(1, 0, 1, if data.Open then -40 else -66),
				Position = UDim2.fromOffset(0, if data.Open then 40 else 66),
			})
			grid.Parent = body
			local layout = Kit.new("UIGridLayout", {
				CellSize = UDim2.new(0.5, -6, 0, 96),
				CellPadding = UDim2.fromOffset(8, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = grid,
			})
			layout.FillDirectionMaxCells = 2
			local function fill()
				for _, child in grid:GetChildren() do
					if child:IsA("GuiObject") then
						child:Destroy()
					end
				end
				local order = 0
				for _, entry in data.Entries do
					local def = Registry.Items[entry.Id]
					if def and (query == "" or string.find(string.lower(def.Name), string.lower(query), 1, true)) then
						order += 1
						local card = Kit.Card(96)
						card.LayoutOrder = order + (if entry.Locked then 1000 else 0)
						card.Parent = grid
						local slot = Kit.ItemSlot(56)
						slot.Button.Active = false
						slot.Set({ Id = entry.Id, N = 1 })
						slot.Button.Parent = card
						local name = Kit.Label(def.Name, { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold })
						name.TextColor3 = Theme.RarityColor(def.Rarity)
						name.Position = UDim2.fromOffset(64, 0)
						name.Size = UDim2.new(1, -64, 0, 20)
						name.Parent = card
						local detail = def.Category
						local crop = def.Plants and Registry.Crops[def.Plants]
						if crop then
							detail = "⏱️ "
								.. Format.Duration(crop.Grow)
								.. (if crop.Regrow then " ♻️" else "")
								.. "  ·  "
								.. table.concat(crop.Seasons, "/")
						elseif def.Placeable then
							local p = Registry.Placeables[entry.Id]
							detail = if p then p.Category .. " · " .. p.Size[1] .. "×" .. p.Size[2] else "Placeable"
						end
						local sub = Kit.Label(detail, { Size = Theme.Sizes.Tiny, Color = "SubText" })
						sub.Position = UDim2.fromOffset(64, 20)
						sub.Size = UDim2.new(1, -64, 0, 16)
						sub.Parent = card
						local price = Kit.Label(
							Kit.Money(entry.Price, entry.Currency)
								.. (if entry.Left then "  ·  " .. entry.Left .. " left today" else ""),
							{ Size = Theme.Sizes.Small, Font = Theme.Fonts.Number, Color = "Accent" }
						)
						price.Position = UDim2.fromOffset(64, 40)
						price.Size = UDim2.new(1, -150, 0, 20)
						price.Parent = card
						if entry.Mats and #entry.Mats > 0 then
							local parts = {}
							for _, mat in entry.Mats do
								local m = Registry.Items[mat.Id]
								table.insert(parts, (if m then m.Icon else "") .. mat.N)
							end
							local mats = Kit.Label(
								"+ " .. table.concat(parts, " "),
								{ Size = Theme.Sizes.Tiny, Color = "SubText" }
							)
							mats.Position = UDim2.fromOffset(64, 60)
							mats.Size = UDim2.new(1, -150, 0, 16)
							mats.Parent = card
						end
						local button = Kit.Button(if entry.Locked then "🔒" else "Buy", {
							Style = if entry.Locked then "Ghost" else "Primary",
							Size = UDim2.fromOffset(78, 34),
							TextSize = Theme.Sizes.Small,
							OnClick = function()
								if entry.Locked then
									C.Notify.Toast("Requires " .. entry.Locked, "Info")
								elseif not data.Open then
									C.Notify.Toast("The shop is closed", "Info")
								elseif entry.Left == 0 then
									C.Notify.Toast("Sold out for today", "Info")
								else
									buy(entry, def)
								end
							end,
						})
						button.Position = UDim2.new(1, -78, 1, -34)
						button.Parent = card
						if entry.Locked or entry.Left == 0 then
							card.BackgroundTransparency = 0.35
						end
						Kit.AttachTooltip(card, function()
							local lines = Kit.ItemTooltip({ Id = entry.Id, N = 1 })
							for _, line in seedInfo(def) do
								table.insert(lines, line)
							end
							if entry.Locked then
								table.insert(lines, { Text = "🔒 Requires " .. entry.Locked, Color = "Warn" })
							end
							return lines
						end)
					end
				end
				if order == 0 then
					Kit.Empty("Nothing matches.").Parent = grid
				end
				Kit.RepaintGradients(grid)
			end
			search:GetPropertyChangedSignal("Text"):Connect(function()
				query = search.Text
				fill()
			end)
			fill()
		end

		updateWallet()
		task.spawn(function()
			local ok, result = Net.Request("ShopGet", shopId)
			if not ok then
				C.Notify.Toast(tostring(result), "Warning")
				ctx.Close()
				return
			end
			data = result
			win.Title.Text = (data.Icon or "🛒") .. "  " .. data.Name
			if tab == "Buy" then
				renderBuy()
			end
		end)
		tabs.Select(tab)
		return {
			Refresh = function()
				updateWallet()
				if sellPanel then
					sellPanel.Refresh()
				end
			end,
		}
	end,
}

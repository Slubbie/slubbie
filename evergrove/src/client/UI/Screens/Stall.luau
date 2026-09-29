-- A farm's market stall. Owners stock the shelves and set prices (within a
-- fair range of the item's value); visitors buy. The town takes a small fee.
-- Args: { Owner = userId }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local ItemUtil = require(Shared.Lib.ItemUtil)
local Economy = require(Shared.Config.Economy)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Picker = require(UI.Picker)
local C = require(UI.Parent.Controllers)

local STALL = Economy.Selling.Stall

return {
	Id = "Stall",
	Title = "Market Stall",
	Icon = "🏪",
	Size = Vector2.new(760, 520),
	Watch = { "Stall", "Coins" },
	Build = function(win, ctx)
		local ownerId = tonumber(ctx.Args and ctx.Args.Owner) or Players.LocalPlayer.UserId
		local mine = ownerId == Players.LocalPlayer.UserId
		local content = win.Content :: Frame
		local listings: { [string]: any } = {}
		local intro = Kit.Label(
			if mine
				then "Stock up to "
					.. STALL.Slots
					.. " shelves. Visitors buy while you play (or while you're away); the town keeps "
					.. math.floor(STALL.Fee * 100)
					.. "% of each sale."
				else "Buy directly from another farmer.",
			{ Size = Theme.Sizes.Small, Color = "SubText", Wrap = true }
		)
		intro.Parent = content
		local grid = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, -40),
			Position = UDim2.fromOffset(0, 40),
			Parent = content,
		})
		local layout = Kit.new("UIGridLayout", {
			CellSize = UDim2.new(0.333, -8, 0, 190),
			CellPadding = UDim2.fromOffset(10, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = grid,
		})
		layout.FillDirectionMaxCells = 3

		local render: () -> ()

		local function load()
			if mine then
				listings = C.State.Get("Stall") or {}
				render()
				return
			end
			task.spawn(function()
				local ok, result = Net.Request("StallGet", ownerId)
				if not ok then
					C.Notify.Toast(tostring(result), "Warning")
					ctx.Close()
					return
				end
				win.Title.Text = "🏪  " .. result.Owner .. "'s stall"
				listings = result.Listings or {}
				render()
			end)
		end

		local function stock(slot: number)
			Picker.Open({
				Title = "Put on shelf " .. slot,
				Filter = function(stack)
					return ItemUtil.Tradable(stack) and ItemUtil.Sellable(stack) and not stack.L
				end,
				Empty = "Nothing you can sell here.",
				OnPick = function(ref, stack)
					local value = ItemUtil.UnitValue(stack)
					local lo, hi = math.max(1, math.floor(value * STALL.MinPrice)), math.ceil(value * STALL.MaxPrice)
					Kit.AskNumber("How many?", stack.N, stack.N, function(count)
						if not count then
							return
						end
						Kit.AskNumber(
							"Price each (" .. lo .. "–" .. hi .. ", value " .. value .. ")",
							hi,
							math.clamp(math.floor(value * 1.2), lo, hi),
							function(price)
								if not price then
									return
								end
								if price < lo then
									C.Notify.Toast("The lowest price allowed is " .. lo, "Warning")
									return
								end
								local ok, err = Net.Request("StallSet", slot, ref, count, price)
								if ok then
									C.Audio.PlayUI("Place")
								else
									C.Notify.Toast(tostring(err), "Warning")
								end
							end
						)
					end)
				end,
			})
		end

		render = function()
			Kit.Clear(grid)
			for slot = 1, STALL.Slots do
				local listing = listings[tostring(slot)]
				local card = Kit.Card(190)
				card.LayoutOrder = slot
				card.Parent = grid
				Kit.List(card, "Y", 4, "Center")
				local itemSlot = Kit.ItemSlot(64)
				itemSlot.Button.Active = false
				itemSlot.Set(listing and listing.Stack)
				itemSlot.Button.Parent = card
				if listing then
					local def = Registry.Items[listing.Stack.Id]
					local name = Kit.Label(
						ItemUtil.DisplayName(listing.Stack) .. " ×" .. listing.Stack.N,
						{ Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold, Align = "Center", Wrap = true }
					)
					name.LayoutOrder = 1
					name.Parent = card
					local price = Kit.Label(
						Kit.Money(listing.Price)
							.. " each"
							.. (if def then "  (value " .. ItemUtil.UnitValue(listing.Stack) .. ")" else ""),
						{ Size = Theme.Sizes.Tiny, Color = "Accent", Align = "Center" }
					)
					price.LayoutOrder = 2
					price.Parent = card
					if mine then
						Kit.Button("Take back", {
							Style = "Secondary",
							Size = UDim2.new(1, 0, 0, 32),
							TextSize = Theme.Sizes.Small,
							LayoutOrder = 3,
							OnClick = function()
								local ok, err = Net.Request("StallClear", slot)
								if not ok then
									C.Notify.Toast(tostring(err), "Warning")
								end
							end,
						}).Parent =
							card
					else
						Kit.Button("Buy", {
							Style = "Primary",
							Size = UDim2.new(1, 0, 0, 32),
							TextSize = Theme.Sizes.Small,
							LayoutOrder = 3,
							OnClick = function()
								local coins = C.State.Get("Coins") or 0
								local max = math.min(listing.Stack.N, math.floor(coins / math.max(1, listing.Price)))
								if max < 1 then
									C.Notify.Toast("Not enough coins", "Warning")
									return
								end
								Kit.AskNumber("Buy how many?", max, 1, function(qty)
									if not qty then
										return
									end
									local ok, err = Net.Request("StallBuy", ownerId, slot, qty)
									if ok then
										C.Audio.PlayUI("Coins")
										load()
									else
										C.Notify.Toast(tostring(err), "Warning")
									end
								end)
							end,
						}).Parent =
							card
					end
					Kit.AttachTooltip(card, function()
						return Kit.ItemTooltip(listing.Stack)
					end)
				else
					local empty =
						Kit.Label("Empty shelf", { Size = Theme.Sizes.Small, Color = "SubText", Align = "Center" })
					empty.LayoutOrder = 1
					empty.Parent = card
					if mine then
						Kit.Button("Stock", {
							Style = "Accent",
							Size = UDim2.new(1, 0, 0, 32),
							TextSize = Theme.Sizes.Small,
							LayoutOrder = 3,
							OnClick = function()
								stock(slot)
							end,
						}).Parent =
							card
					end
				end
			end
			Kit.RepaintGradients(grid)
		end

		load()
		return {
			Refresh = function()
				if mine then
					load()
				end
			end,
		}
	end,
}

-- The store: cosmetic game passes and gifts only. Nothing here sells crops,
-- coins, speed or any competitive edge — everything that matters is earned
-- by playing. Items whose pass/product id isn't configured yet show as
-- "coming soon".
-- Args: { GiftTo = userId, GiftName = string } to send a gift box.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local C = require(UI.Parent.Controllers)

return {
	Id = "Store",
	Title = "Store",
	Icon = "🛍️",
	Size = Vector2.new(940, 600),
	Watch = { "Passes", "Cosmetics" },
	Build = function(win, ctx)
		local args = ctx.Args or {}
		local content = win.Content :: Frame
		local items: { any }? = nil
		local alive = true
		local render: () -> ()

		local function fetch()
			local ok, result = Net.Request("StoreGet")
			if ok then
				items = result
				render()
			end
		end

		render = function()
			Kit.Clear(content)
			local promise = Kit.Label(
				"💚 Fair play promise: the store only sells looks, companions, music and conveniences like layout slots. No crops, coins, growth or luck — ever.",
				{ Size = Theme.Sizes.Small, Color = "Good", Wrap = true }
			)
			promise.Parent = content
			if args.GiftTo then
				local gift = Kit.Label(
					"🎁 Gifting to "
						.. tostring(args.GiftName or "a friend")
						.. " — gift items bought now go to their mailbox.",
					{ Size = Theme.Sizes.Small, Color = "Accent", Wrap = true }
				)
				gift.Position = UDim2.fromOffset(0, 40)
				gift.Parent = content
			end
			local grid = Kit.Scroll({ Size = UDim2.new(1, 0, 1, -76), Position = UDim2.fromOffset(0, 72) })
			grid.Parent = content
			local layout = Kit.new("UIGridLayout", {
				CellSize = UDim2.new(0.333, -8, 0, 170),
				CellPadding = UDim2.fromOffset(10, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = grid,
			})
			layout.FillDirectionMaxCells = 3
			if not items then
				Kit.Empty("Opening the store…").Parent = grid
				return
			end
			for i, item in items do
				local card = Kit.Card(170)
				card.LayoutOrder = i
				card.Parent = grid
				Kit.List(card, "Y", 4)
				local head = Kit.Label(
					item.Icon .. " " .. item.Name,
					{ Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold, Wrap = true }
				)
				head.Parent = card
				local desc =
					Kit.Label(item.Description or "", { Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true })
				desc.LayoutOrder = 1
				desc.Parent = card
				local price = Kit.Label(
					"R$ " .. tostring(item.Price) .. (if item.Kind == "Product" then "  ·  repeatable" else ""),
					{ Size = Theme.Sizes.Small, Font = Theme.Fonts.Number, Color = "Accent" }
				)
				price.LayoutOrder = 2
				price.Parent = card
				local label = if item.Owned then "✔ Owned" elseif not item.Available then "Coming soon" else "Buy"
				local buy = Kit.Button(label, {
					Style = if item.Owned then "Ghost" else "Primary",
					Size = UDim2.new(1, 0, 0, 34),
					TextSize = Theme.Sizes.Small,
					LayoutOrder = 3,
					OnClick = function()
						if item.Owned or not item.Available then
							return
						end
						if item.Kind == "Pass" and item.GamePassId and item.GamePassId > 0 then
							MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, item.GamePassId)
						elseif item.ProductId and item.ProductId > 0 then
							if args.GiftTo then
								Net.Request("StoreGiftTarget", args.GiftTo)
							end
							MarketplaceService:PromptProductPurchase(Players.LocalPlayer, item.ProductId)
						end
					end,
				})
				buy.Parent = card
				Kit.SetEnabled(buy, not item.Owned and item.Available)
			end
			local wardrobe = Kit.Button("👒 Open your wardrobe", {
				Style = "Secondary",
				Size = UDim2.fromOffset(220, 36),
				TextSize = Theme.Sizes.Small,
				LayoutOrder = 999,
				OnClick = function()
					C.Windows.Open("Profile", { Tab = "Wardrobe" })
				end,
			})
			wardrobe.Parent = grid
			Kit.RepaintGradients(content)
		end

		local conns = {
			MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, _, purchased)
				if player == Players.LocalPlayer and purchased and alive then
					task.wait(1.5)
					fetch()
					C.Notify.Toast("💚 Thank you! Your purchase is ready.", "Success")
				end
			end),
			MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, _, purchased)
				if userId == Players.LocalPlayer.UserId and purchased and alive then
					task.wait(1.5)
					fetch()
				end
			end),
		}
		render()
		task.spawn(fetch)
		return {
			Refresh = fetch,
			Destroy = function()
				alive = false
				for _, c in conns do
					c:Disconnect()
				end
			end,
		}
	end,
}

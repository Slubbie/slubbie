-- Selling at the shipping bin (paid next morning) or to a merchant (paid now).
-- Opened by the bin's prompt with { Venue = "Bin" }; merchants use the Shop
-- screen's Sell tab.

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local SellPanel = require(UI.SellPanel)
local C = require(UI.Parent.Controllers)

return {
	Id = "Sell",
	Title = "Shipping Bin",
	Icon = "📦",
	Size = Vector2.new(760, 560),
	Watch = { "Inventory", "Farm" },
	Build = function(win, ctx)
		local venue = (ctx.Args and ctx.Args.Venue) or "Bin"
		if venue ~= "Bin" then
			win.Title.Text = "💰  Sell"
		end
		local intro = Kit.Label(if venue == "Bin" then "Drop goods in the bin: they're sold at the market price when the bin is emptied at 6 AM — even while you're offline." else "Sold right away at this merchant's price.", { Size = Theme.Sizes.Small, Color = "SubText", Wrap = true })
		intro.Parent = win.Content
		local holder = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -30), Position = UDim2.fromOffset(0, 30), Parent = win.Content })
		local panel = SellPanel.Build(holder, venue, C)
		C.Tutorial.Hint("Sell")
		return { Refresh = panel.Refresh }
	end,
}

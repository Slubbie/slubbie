-- The locker (everything you own, equip and the emote wheel) and the shop
-- (what's for sale here, in credits or prestige tokens). Cosmetics never
-- change how you move.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cosmetics = require(ReplicatedStorage.Shared.Config.Cosmetics)
local Districts = require(ReplicatedStorage.Shared.Config.Districts)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)

local State = require(script.Parent.Parent.Parent.Core.State)
local Sfx = require(script.Parent.Parent.Parent.Audio.Sfx)
local Kit = require(script.Parent.Parent.Kit)

local C = Kit.Colors

local Locker = {}

local category = "Outfit"

local function isEquipped(profile: any, item: Cosmetics.Item): boolean
	if item.Category == "Emote" then
		return table.find(profile.Equipped.Emotes or {}, item.Id) ~= nil
	end
	return profile.Equipped[item.Category] == item.Id
end

local function itemCard(parent: Instance, item: Cosmetics.Item, profile: any, shop: boolean, message: TextLabel)
	local owned = profile.Inventory[item.Id] == true
	local card = Kit.Panel(parent, { BackgroundColor3 = C.PanelLight })
	Kit.Padding(card, 10)
	Kit.List(card, false, 4)
	local rarity = Cosmetics.Rarities[item.Rarity] or C.Text
	Kit.Label(card, item.Name, 15, { Font = Kit.Fonts.Bold, TextColor3 = rarity })
	Kit.Label(card, ("%s · %s"):format(item.Rarity, item.Style or ""), 12, { TextColor3 = C.Muted })
	-- Colour swatches.
	if item.Colors and #item.Colors > 0 then
		local swatches = Kit.Row(card, 16, 4)
		for _, color in item.Colors do
			local swatch =
				Kit.new("Frame", { Size = UDim2.fromOffset(16, 16), BackgroundColor3 = color, Parent = swatches })
			Kit.Corner(swatch, 4)
		end
	end
	Kit.Paragraph(card, item.Description, 12, C.Muted)
	if owned then
		local equipped = isEquipped(profile, item)
		Kit.Button(card, if equipped then "✓ Equipped" else "Equip", function()
			task.spawn(function()
				local ok, success, reason = pcall(Net.Invoke, "Shop.Equip", item.Category, item.Id)
				if not (ok and success) then
					message.Text = tostring(reason or "Couldn't equip")
				end
			end)
		end, if equipped then "Primary" else "Secondary", { Size = UDim2.new(1, 0, 0, 32) })
	elseif shop and (item.Source == "Shop" or item.Source == "Prestige") then
		local price = if item.Source == "Prestige"
			then ("✪ %d"):format(item.PrestigePrice or 0)
			else ("¢ %s"):format(Format.Number(item.Price or 0))
		Kit.Button(card, "Buy  " .. price, function()
			task.spawn(function()
				local ok, success, reason = pcall(Net.Invoke, "Shop.Buy", item.Id)
				if ok and success then
					Sfx.Stinger("Unlock")
					message.Text = "Bought " .. item.Name .. "!"
					message.TextColor3 = C.Good
				else
					Sfx.Stinger("Error")
					message.Text = tostring(reason or "Couldn't buy that")
					message.TextColor3 = C.Bad
				end
			end)
		end, "Primary", { Size = UDim2.new(1, 0, 0, 32) })
	else
		local how = if item.Source == "Reward"
			then (item.Unlock or "Earned in play")
			elseif item.District then (
				"Sold in " .. (Districts.ById[item.District] and Districts.ById[item.District].Name or item.District)
			)
			else "Sold at the Outfitters"
		Kit.Paragraph(card, "🔒 " .. how, 12, C.Faint)
	end
end

local function render(container: Frame, shop: boolean, district: string?)
	local profile = State.Profile
	if not profile then
		return
	end
	local header = Kit.Row(container, 40, 8)
	Kit.Label(
		header,
		("¢ %s    ✪ %d"):format(Format.Number(profile.Credits or 0), profile.Prestige or 0),
		18,
		{ Font = Kit.Fonts.Black, Size = UDim2.fromOffset(240, 40), TextColor3 = C.Accent }
	)
	local message = Kit.Label(
		header,
		if shop and district
			then ("Stall stock: %s specials plus Guild staples"):format(
				Districts.ById[district] and Districts.ById[district].Short or district
			)
			else "",
		13,
		{ Size = UDim2.new(1, -250, 1, 0), TextColor3 = C.Muted }
	)
	local tabs = Kit.Scroll(container, {
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 0, 44),
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
	})
	Kit.List(tabs, true, 6)
	for _, name in Cosmetics.Categories do
		Kit.Button(
			tabs,
			Cosmetics.CategoryNames[name] or name,
			function()
				category = name
				Kit.Clear(container)
				render(container, shop, district)
			end,
			"Secondary",
			{
				Size = UDim2.fromOffset(140, 36),
				BackgroundColor3 = if name == category then C.Accent:Lerp(C.PanelLight, 0.5) else C.PanelLight,
			}
		)
	end
	local grid = Kit.Scroll(container, { Position = UDim2.fromOffset(0, 98), Size = UDim2.new(1, 0, 1, -98) })
	Kit.new("UIGridLayout", {
		CellSize = UDim2.new(0.25, -9, 0, 190),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	local items = Cosmetics.OfCategory(category)
	table.sort(items, function(a, b)
		local ownedA, ownedB = profile.Inventory[a.Id] == true, profile.Inventory[b.Id] == true
		if ownedA ~= ownedB then
			return ownedA
		end
		return (a.Price or (a.PrestigePrice or 0) * 1000) < (b.Price or (b.PrestigePrice or 0) * 1000)
	end)
	local shown = 0
	for _, item in items do
		local forSale = item.Source == "Shop" or item.Source == "Prestige"
		local here = not district or item.District == nil or item.District == district
		if (shop and forSale and here) or not shop then
			itemCard(grid, item, profile, shop, message)
			shown += 1
		end
	end
	if shown == 0 then
		Kit.Paragraph(grid, "Nothing here yet.", 14, C.Faint)
	end
	if category == "Emote" and not shop then
		message.Text = ("Emote wheel: %d / %d equipped. Press [Emote] to use them."):format(
			#(profile.Equipped.Emotes or {}),
			Cosmetics.MultiEquip.Emote
		)
	end
end

Locker.Pages = {
	{
		Id = "Locker",
		Title = "Locker",
		Icon = "▣",
		Order = 5,
		Sections = { "Inventory", "Equipped", "Credits", "Prestige" },
		Build = function(container: Frame)
			render(container, false, nil)
		end,
	},
	{
		Id = "Shop",
		Title = "Shop",
		Icon = "¢",
		Order = 6,
		Sections = { "Inventory", "Equipped", "Credits", "Prestige" },
		Build = function(container: Frame, args: any)
			render(
				container,
				true,
				if type(args) == "table" and type(args.District) == "string" then args.District else nil
			)
		end,
	},
}

return Locker

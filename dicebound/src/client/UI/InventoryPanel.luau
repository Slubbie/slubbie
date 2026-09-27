-- The treasure bag: sort, filter, lock favorites, select stacks (and how many) and sell them at
-- a merchant. Capacity counts individual items. The server re-checks every sale and lock.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Dicebound.Config)
local Format = require(ReplicatedStorage.Dicebound.Format)
local ClientState = require(script.Parent.Parent.ClientState)
local Sound = require(script.Parent.Parent.Sound)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)
local ItemIcon = require(script.Parent.ItemIcon)
local Panels = require(script.Parent.Panels)
local Toasts = require(script.Parent.Toasts)
local Confirm = require(script.Parent.Confirm)

local C = Theme.Colors

local InventoryPanel = {}

local SORTS = { "Rarity", "Value", "Newest" }
local rarityFilters = { "All" }
for _, rarity in Config.Rarities.List do
	table.insert(rarityFilters, rarity.Id)
end
local regionFilters = { "All" }
for _, region in Config.Regions.List do
	if Config.IsLive(region) then
		table.insert(regionFilters, region.Id)
	end
end

local function needsConfirm(itemId: string): boolean
	local item = Config.Items.ById[itemId]
	return item ~= nil and Config.Rarities.ById[item.Rarity].ConfirmSell == true
end

local function cycle(list: { string }, current: string): string
	local index = table.find(list, current) or 1
	return list[index % #list + 1]
end

function InventoryPanel.new()
	local content = Panels.Create("Bag", "Treasure Bag", "🎒")
	local sortMode, rarityFilter, regionFilter = "Rarity", "All", "All"
	local selection: { [string]: number } = {}
	local busy = false

	-- Toolbar
	local toolbar = Kit.new("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, Parent = content })
	Kit.List(toolbar, Enum.FillDirection.Horizontal, 8)
	local refresh: () -> ()
	local sortButton, rarityButton, regionButton
	sortButton = Kit.Button({
		Parent = toolbar,
		Text = "Sort: Rarity",
		Color = C.Blue,
		Size = UDim2.fromOffset(140, 36),
		TextSize = 15,
		LayoutOrder = 1,
		OnClick = function()
			sortMode = cycle(SORTS, sortMode)
			sortButton:SetText("Sort: " .. sortMode)
			refresh()
		end,
	})
	rarityButton = Kit.Button({
		Parent = toolbar,
		Text = "Rarity: All",
		Color = C.Purple,
		Size = UDim2.fromOffset(160, 36),
		TextSize = 15,
		LayoutOrder = 2,
		OnClick = function()
			rarityFilter = cycle(rarityFilters, rarityFilter)
			rarityButton:SetText("Rarity: " .. rarityFilter)
			refresh()
		end,
	})
	regionButton = Kit.Button({
		Parent = toolbar,
		Text = "Region: All",
		Color = C.GreenDark,
		Size = UDim2.fromOffset(180, 36),
		TextSize = 15,
		LayoutOrder = 3,
		OnClick = function()
			regionFilter = cycle(regionFilters, regionFilter)
			local region = Config.Regions.ById[regionFilter]
			regionButton:SetText("Region: " .. (if region then region.Name else "All"))
			refresh()
		end,
	})
	local capacity = Kit.Label({
		Parent = toolbar,
		Text = "",
		Size = UDim2.fromOffset(160, 36),
		Font = Theme.Fonts.Title,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Right,
		LayoutOrder = 4,
	})

	-- Grid
	local grid = Kit.new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 1, -48 - 70),
		BackgroundColor3 = C.PanelAlt,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = C.Stroke,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = content,
	})
	Kit.Corner(grid, 10)
	Kit.Padding(grid, 8)
	Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(148, 184),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	local empty = Kit.Label({
		Parent = content,
		Position = UDim2.fromOffset(0, 60),
		Size = UDim2.new(1, 0, 0, 60),
		Text = "Your bag is empty. Roll some dice to find treasure!",
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.InkSoft,
		Visible = false,
		ZIndex = 2,
	})

	-- Footer
	local footer = Kit.new("Frame", {
		Position = UDim2.new(0, 0, 1, -62),
		Size = UDim2.new(1, 0, 0, 62),
		BackgroundTransparency = 1,
		Parent = content,
	})
	local summary = Kit.Label({
		Parent = footer,
		Size = UDim2.new(1, -330, 0, 26),
		Text = "",
		Font = Theme.Fonts.Bold,
		TextSize = 16,
	})
	local hint = Kit.Label({
		Parent = footer,
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, -330, 0, 34),
		Text = "",
		TextSize = 13,
		TextColor3 = C.InkSoft,
	})
	local sellSelected, sellAll

	local function showSale(result)
		Sound.Play("Sell")
		local parts = {}
		table.sort(result.Lines, function(a, b)
			return a.Coins > b.Coins
		end)
		for i, line in result.Lines do
			if i > 3 then
				table.insert(parts, string.format("+%d more", #result.Lines - 3))
				break
			end
			table.insert(parts, string.format("%d× %s", line.Qty, ItemIcon.Name(line.Id, line.Mut)))
		end
		local bonus = if result.Multiplier > 1
			then string.format(" (+%d%% bonus)", math.floor((result.Multiplier - 1) * 100 + 0.5))
			else ""
		Toasts.Show(
			string.format(
				"Sold %d items for 🪙 %s%s\n%s",
				result.Units,
				Format.Coins(result.Total),
				bonus,
				table.concat(parts, " · ")
			),
			"reward",
			4
		)
	end

	local function doSellSelected()
		local data = ClientState.Data
		if busy or not data then
			return
		end
		local request, highValue, units, total = {}, {}, 0, 0
		for key, qty in selection do
			request[key] = qty
			for _, stack in data.Bag do
				if stack.Key == key then
					units += qty
					total += Config.ItemValue(stack.Id, stack.Mut) * qty
					if needsConfirm(stack.Id) then
						table.insert(highValue, string.format("%d× %s", qty, ItemIcon.Name(stack.Id, stack.Mut)))
					end
				end
			end
		end
		if units == 0 then
			return
		end
		local confirmed = false
		if #highValue > 0 then
			local choice = Confirm.Ask(
				"Sell rare treasure?",
				"You're about to sell Legendary-or-better items:\n"
					.. table.concat(highValue, "\n")
					.. "\n\nYour collection book keeps them either way, but this can't be undone.",
				{
					{ Id = "cancel", Text = "Keep them", Color = C.Green },
					{ Id = "sell", Text = "Sell", Color = C.Red },
				}
			)
			if choice ~= "sell" then
				return
			end
			confirmed = true
		end
		busy = true
		local result = ClientState.Request("Sell", request, confirmed)
		busy = false
		if result.ok then
			table.clear(selection)
			showSale(result)
		else
			Sound.Play("Error")
			Toasts.Show(result.err, "error")
		end
		refresh()
	end

	local function doSellAll()
		local data = ClientState.Data
		if busy or not data then
			return
		end
		local normal, high = 0, {}
		for _, stack in data.Bag do
			if not stack.Locked then
				if needsConfirm(stack.Id) then
					table.insert(high, string.format("%d× %s", stack.Qty, ItemIcon.Name(stack.Id, stack.Mut)))
				else
					normal += stack.Qty
				end
			end
		end
		if normal == 0 and #high == 0 then
			Toasts.Show("Nothing to sell: every item is locked.", "info")
			return
		end
		local includeHigh = false
		if #high > 0 then
			local buttons = {}
			if normal > 0 then
				table.insert(buttons, { Id = "normal", Text = "Sell all except these", Color = C.Green })
			else
				table.insert(buttons, { Id = "cancel", Text = "Keep them", Color = C.Green })
			end
			table.insert(buttons, { Id = "all", Text = "Sell everything", Color = C.Red })
			local choice = Confirm.Ask(
				"Include rare treasure?",
				"Your unlocked items include Legendary-or-better finds:\n" .. table.concat(high, "\n"),
				buttons
			)
			if choice == "all" then
				includeHigh = true
			elseif choice ~= "normal" then
				return
			end
		end
		busy = true
		local result = ClientState.Request("SellAll", includeHigh)
		busy = false
		if result.ok then
			table.clear(selection)
			showSale(result)
		else
			Sound.Play("Error")
			Toasts.Show(result.err, "error")
		end
		refresh()
	end

	sellSelected = Kit.Button({
		Parent = footer,
		Text = "Sell Selected",
		Color = C.Gold,
		TextColor = C.Ink,
		Size = UDim2.fromOffset(160, 50),
		Position = UDim2.new(1, -330, 0, 6),
		OnClick = function()
			task.spawn(doSellSelected)
		end,
	})
	sellAll = Kit.Button({
		Parent = footer,
		Text = "Sell All",
		Color = C.Green,
		Size = UDim2.fromOffset(160, 50),
		Position = UDim2.new(1, -160, 0, 6),
		OnClick = function()
			task.spawn(doSellAll)
		end,
	})

	local function buildCard(stack, order: number)
		local item = Config.Items.ById[stack.Id]
		local rarityColor = Theme.Rarity(item.Rarity)
		local selected = selection[stack.Key]
		local card = Kit.new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = if selected then Color3.fromRGB(255, 244, 205) else C.Panel,
			LayoutOrder = order,
			Parent = grid,
		})
		Kit.Corner(card, 10)
		Kit.Stroke(
			card,
			if selected then C.Gold elseif stack.Locked then C.Blue else rarityColor,
			if selected then 4 else 2
		)

		local icon = ItemIcon.Create(stack.Id, stack.Mut, 64)
		icon.Position = UDim2.new(0.5, 0, 0, 10)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Parent = card
		Kit.Label({
			Parent = card,
			Text = "×" .. stack.Qty,
			Position = UDim2.new(1, -6, 0, 6),
			AnchorPoint = Vector2.new(1, 0),
			Size = UDim2.fromOffset(44, 20),
			Font = Theme.Fonts.Title,
			TextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		local lock = Kit.new("TextButton", {
			Text = if stack.Locked then "🔒" else "🔓",
			TextSize = 18,
			Size = UDim2.fromOffset(32, 32),
			Position = UDim2.fromOffset(4, 4),
			BackgroundColor3 = if stack.Locked then C.Blue else C.PanelAlt,
			AutoButtonColor = true,
			ZIndex = 3,
			Parent = card,
		})
		Kit.Corner(lock, 8)
		lock.Activated:Connect(function()
			Sound.Play("Click")
			local result = ClientState.Request("SetLock", stack.Key, not stack.Locked)
			if result.ok then
				selection[stack.Key] = nil
			else
				Toasts.Show(result.err, "error")
			end
		end)

		Kit.Label({
			Parent = card,
			Text = ItemIcon.Name(stack.Id, stack.Mut),
			Position = UDim2.fromOffset(6, 78),
			Size = UDim2.new(1, -12, 0, 34),
			Font = Theme.Fonts.Bold,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
		local chip = Kit.Chip(card, Theme.RarityText(item.Rarity), rarityColor, C.Ink)
		chip.Position = UDim2.new(0.5, 0, 0, 114)
		chip.AnchorPoint = Vector2.new(0.5, 0)
		chip.TextSize = 11

		local value = Config.ItemValue(stack.Id, stack.Mut)
		if selected and stack.Qty > 1 then
			-- Quantity stepper for partially selling a stack.
			local row = Kit.new("Frame", {
				Position = UDim2.new(0.5, 0, 0, 142),
				AnchorPoint = Vector2.new(0.5, 0),
				Size = UDim2.fromOffset(136, 34),
				BackgroundTransparency = 1,
				ZIndex = 3,
				Parent = card,
			})
			local function step(delta: number)
				selection[stack.Key] = math.clamp((selection[stack.Key] or 1) + delta, 1, stack.Qty)
				refresh()
			end
			Kit.Button({
				Parent = row,
				Text = "−",
				Size = UDim2.fromOffset(34, 32),
				Color = C.InkSoft,
				ZIndex = 3,
				OnClick = function()
					step(-1)
				end,
			})
			Kit.Label({
				Parent = row,
				Text = string.format("%d/%d", selected, stack.Qty),
				Position = UDim2.fromOffset(34, 0),
				Size = UDim2.fromOffset(68, 32),
				Font = Theme.Fonts.Title,
				TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Center,
			})
			Kit.Button({
				Parent = row,
				Text = "+",
				Size = UDim2.fromOffset(34, 32),
				Position = UDim2.fromOffset(102, 0),
				Color = C.InkSoft,
				ZIndex = 3,
				OnClick = function()
					step(1)
				end,
			})
		else
			Kit.Label({
				Parent = card,
				Text = (if stack.Mut then ItemIcon.MutationGlyph(stack.Mut) .. " " .. stack.Mut .. "\n" else "")
					.. "🪙 "
					.. Format.Coins(value)
					.. " each",
				Position = UDim2.fromOffset(4, 140),
				Size = UDim2.new(1, -8, 0, 40),
				TextSize = 13,
				Font = Theme.Fonts.Bold,
				TextColor3 = C.InkSoft,
				TextXAlignment = Enum.TextXAlignment.Center,
			})
		end
		if selected then
			Kit.Label({
				Parent = card,
				Text = "✔",
				Position = UDim2.new(0, 38, 0, 6),
				Size = UDim2.fromOffset(24, 24),
				Font = Theme.Fonts.Title,
				TextSize = 20,
				TextColor3 = C.GoldDark,
			})
		end

		card.Activated:Connect(function()
			if stack.Locked then
				Toasts.Show("That stack is locked 🔒. Unlock it to sell.", "info", 2)
				return
			end
			Sound.Play("Click")
			selection[stack.Key] = if selection[stack.Key] then nil else stack.Qty
			refresh()
		end)
	end

	function refresh()
		local data = ClientState.Data
		if not data or not Panels.IsOpen("Bag") then
			return
		end
		for _, child in grid:GetChildren() do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
		capacity.Text = string.format("🎒 %d / %d", data.Used, data.Capacity)
		capacity.TextColor3 = if data.Used >= data.Capacity then C.Red else C.Ink

		-- Drop selections for stacks that changed or vanished.
		local byKey = {}
		for _, stack in data.Bag do
			byKey[stack.Key] = stack
		end
		for key, qty in selection do
			local stack = byKey[key]
			if not stack or stack.Locked then
				selection[key] = nil
			elseif qty > stack.Qty then
				selection[key] = stack.Qty
			end
		end

		local list = {}
		for _, stack in data.Bag do
			local item = Config.Items.ById[stack.Id]
			if
				item
				and (rarityFilter == "All" or item.Rarity == rarityFilter)
				and (regionFilter == "All" or item.Region == regionFilter)
			then
				table.insert(list, stack)
			end
		end
		table.sort(list, function(a, b)
			local ia, ib = Config.Items.ById[a.Id], Config.Items.ById[b.Id]
			local va, vb = Config.ItemValue(a.Id, a.Mut), Config.ItemValue(b.Id, b.Mut)
			if sortMode == "Newest" then
				return a.Seq > b.Seq
			elseif sortMode == "Value" then
				if va ~= vb then
					return va > vb
				end
			else
				local ra, rb = Config.Rarities.Order(ia.Rarity), Config.Rarities.Order(ib.Rarity)
				if ra ~= rb then
					return ra > rb
				end
				if va ~= vb then
					return va > vb
				end
			end
			return a.Key < b.Key
		end)
		for i, stack in list do
			buildCard(stack, i)
		end
		empty.Visible = #data.Bag == 0
		empty.Text = if #data.Bag == 0
			then "Your bag is empty. Roll some dice to find treasure!"
			else "No items match these filters."
		empty.Visible = #list == 0

		local units, total = 0, 0
		for key, qty in selection do
			local stack = byKey[key]
			units += qty
			total += math.floor(Config.ItemValue(stack.Id, stack.Mut) * qty * data.SellMultiplier)
		end
		summary.Text = if units > 0
			then string.format(
				"Selected %d item%s · 🪙 %s",
				units,
				if units == 1 then "" else "s",
				Format.Coins(total)
			)
			else "Tap items to select them. 🔓 locks favorites."

		local merchant = ClientState.NearMerchant()
		sellSelected:SetEnabled(merchant ~= nil and units > 0 and not busy)
		sellAll:SetEnabled(merchant ~= nil and #data.Bag > 0 and not busy)
		if merchant then
			hint.Text = "At " .. merchant.Merchant.Name .. "'s stall. Locked items are never sold."
		else
			local home = Config.Regions.List[1]
			hint.Text = "Selling happens at a merchant stall, like " .. home.Merchant.Name .. " in " .. home.Name .. "."
		end
	end

	ClientState.Changed:Connect(refresh)
	Panels.Opened:Connect(function(name)
		if name == "Bag" then
			refresh()
			-- Re-check merchant distance while open (cheap, twice a second).
			task.spawn(function()
				local wasNear = ClientState.NearMerchant() ~= nil
				while Panels.IsOpen("Bag") do
					task.wait(0.5)
					local near = ClientState.NearMerchant() ~= nil
					if near ~= wasNear then
						wasNear = near
						refresh()
					end
				end
			end)
		end
	end)
	Panels.Closed:Connect(function(name)
		if name == "Bag" then
			table.clear(selection)
		end
	end)
end

return InventoryPanel

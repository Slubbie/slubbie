-- The selling list shared by the shipping bin and merchant shops: every
-- sellable stack in your bag with an estimated price, tick boxes, quick
-- selections ("all crops", "all fish"...), a running total and a confirm step
-- for big sales. Locked items never appear.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local ItemUtil = require(Shared.Lib.ItemUtil)
local Format = require(Shared.Lib.Format)
local Economy = require(Shared.Config.Economy)

local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)
local Prices = require(script.Parent.Prices)

local SellPanel = {}

local QUICK = {
	{ Id = "Crops", Icon = "🥕", Cats = { Crop = true, Forage = true } },
	{ Id = "Animal goods", Icon = "🥚", Cats = { AnimalProduct = true } },
	{ Id = "Fish", Icon = "🐟", Cats = { Fish = true } },
	{ Id = "Artisan", Icon = "🍯", Cats = { Artisan = true, Food = true } },
	{ Id = "Minerals", Icon = "💎", Cats = { Mineral = true, Gem = true } },
}

-- deps: { C = controllers }
function SellPanel.Build(parent: Instance, venue: string, C: any)
	local selected: { [string]: boolean } = {}
	local frame = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = parent })
	local top = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32), Parent = frame })
	Kit.List(top, "X", 6)
	local list = Kit.Scroll({ Size = UDim2.new(1, 0, 1, -96), Position = UDim2.fromOffset(0, 40) })
	list.Parent = frame
	Kit.List(list, "Y", 4)
	local footer = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 48),
		Position = UDim2.new(0, 0, 1, -48),
		Parent = frame,
	})
	local totalLabel = Kit.Label("", { Size = Theme.Sizes.Body, Font = Theme.Fonts.Bold })
	totalLabel.Size = UDim2.new(1, -200, 0, 24)
	totalLabel.Parent = footer
	local noteLabel = Kit.Label("", { Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true })
	noteLabel.Size = UDim2.new(1, -200, 0, 20)
	noteLabel.Position = UDim2.fromOffset(0, 26)
	noteLabel.Parent = footer
	local sellButton = Kit.Button(
		if venue == "Bin" then "📦 Ship selected" else "💰 Sell selected",
		{ Style = "Good", Size = UDim2.fromOffset(190, 44) }
	)
	sellButton.Position = UDim2.new(1, -190, 0, 2)
	sellButton.Parent = footer

	local refresh: () -> ()

	local function sellable(): { { Ref: string, Stack: any, Def: any } }
		local profile = C.State.Data()
		local out = {}
		for key, stack in (profile and profile.Inventory.Slots) or {} do
			local def = Registry.Items[stack.Id]
			if def and ItemUtil.Sellable(stack) and not stack.L then
				table.insert(out, { Ref = "inv:" .. key, Stack = stack, Def = def })
			end
		end
		table.sort(out, function(a, b)
			local va = Prices.Unit(profile, a.Stack, venue) * a.Stack.N
			local vb = Prices.Unit(profile, b.Stack, venue) * b.Stack.N
			return va > vb
		end)
		return out
	end

	for i, quick in QUICK do
		local b = Kit.Button(quick.Icon .. " " .. quick.Id, {
			Style = "Secondary",
			Size = UDim2.fromOffset(0, 30),
			TextSize = Theme.Sizes.Tiny,
			LayoutOrder = i,
			OnClick = function()
				local any = false
				for _, entry in sellable() do
					if quick.Cats[entry.Def.Category] then
						selected[entry.Ref] = true
						any = true
					end
				end
				if not any then
					C.Notify.Toast("Nothing like that to sell", "Info")
				end
				refresh()
			end,
		})
		b.AutomaticSize = Enum.AutomaticSize.X
		Kit.Padding(b, 0, 10)
		b.Parent = top
	end
	local clear = Kit.Button("Clear", {
		Style = "Ghost",
		Size = UDim2.fromOffset(70, 30),
		TextSize = Theme.Sizes.Tiny,
		LayoutOrder = 99,
		OnClick = function()
			table.clear(selected)
			refresh()
		end,
	})
	clear.Parent = top

	refresh = function()
		Kit.Clear(list)
		local profile = C.State.Data()
		local entries = sellable()
		local total = 0
		local count = 0
		-- Drop selections that no longer exist.
		local valid = {}
		for _, entry in entries do
			valid[entry.Ref] = true
		end
		for ref in selected do
			if not valid[ref] then
				selected[ref] = nil
			end
		end
		if #entries == 0 then
			Kit.Empty(
				"Nothing to sell. Harvest crops, collect animal goods, fish or make artisan goods — locked items are kept safe."
			).Parent =
				list
		end
		for i, entry in entries do
			local unit = Prices.Unit(profile, entry.Stack, venue)
			local value = unit * entry.Stack.N
			local on = selected[entry.Ref] == true
			if on then
				total += value
				count += entry.Stack.N
			end
			local row = Kit.new("TextButton", {
				AutoButtonColor = false,
				Text = "",
				Size = UDim2.new(1, -8, 0, 50),
				LayoutOrder = i,
				Selectable = true,
				Parent = list,
			})
			Kit.Paint(row, "BackgroundColor3", if on then "SlotHover" else "PanelAlt")
			Kit.Corner(row, 8)
			local tick = Kit.Label(if on then "☑" else "☐", { Size = 22, Align = "Center" })
			tick.Size = UDim2.fromOffset(30, 50)
			tick.Parent = row
			local slot = Kit.ItemSlot(40)
			slot.Button.Active = false
			slot.Button.Position = UDim2.fromOffset(32, 5)
			slot.Set(entry.Stack)
			slot.Button.Parent = row
			local name = Kit.Label(
				ItemUtil.DisplayName(entry.Stack) .. "  ×" .. entry.Stack.N,
				{ Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold }
			)
			name.TextColor3 = Theme.RarityColor(ItemUtil.Rarity(entry.Stack))
			name.Position = UDim2.fromOffset(80, 6)
			name.Size = UDim2.new(1, -250, 0, 20)
			name.Parent = row
			local trend, key = Prices.TrendText(entry.Stack.Id)
			local sub = Kit.Label(Kit.Money(unit) .. " each  ·  " .. trend, { Size = Theme.Sizes.Tiny, Color = key })
			sub.Position = UDim2.fromOffset(80, 26)
			sub.Size = UDim2.new(1, -250, 0, 16)
			sub.Parent = row
			local worth = Kit.Label(
				Kit.Money(value),
				{ Size = Theme.Sizes.Small, Font = Theme.Fonts.Number, Align = "Right", Color = "Accent" }
			)
			worth.Size = UDim2.fromOffset(150, 50)
			worth.Position = UDim2.new(1, -160, 0, 0)
			worth.Parent = row
			row.Activated:Connect(function()
				if on then
					selected[entry.Ref] = nil
				else
					selected[entry.Ref] = true
				end
				Kit.PlaySound("UIClick")
				refresh()
			end)
			Kit.AttachTooltip(row, function()
				return Kit.ItemTooltip(entry.Stack)
			end)
		end
		totalLabel.Text = if count > 0
			then Format.Commas(count) .. " items  ·  " .. (if venue == "Bin" then "≈ " else "") .. Kit.Money(total)
			else "Select what to sell"
		if venue == "Bin" then
			local binCount = 0
			for _, s in (profile and profile.Farm and profile.Farm.Bin) or {} do
				binCount += s.N
			end
			noteLabel.Text = "Paid at "
				.. Economy.Selling.Bin.PayHour
				.. " AM at that morning's price · bin "
				.. binCount
				.. " / "
				.. Economy.Selling.Bin.Capacity
		else
			noteLabel.Text = "Paid now · selling "
				.. Economy.Selling.Bulk.Threshold
				.. "+ of one item earns a bulk bonus"
		end
		Kit.SetEnabled(sellButton, count > 0)
	end

	sellButton.Activated:Connect(function()
		if not sellButton.Active then
			return
		end
		local refs = {}
		local profile = C.State.Data()
		local total = 0
		for ref in selected do
			table.insert(refs, ref)
			local key = string.match(ref, "^inv:(%d+)$")
			local stack = key and profile.Inventory.Slots[key]
			if stack then
				total += Prices.Unit(profile, stack, venue) * stack.N
			end
		end
		local function go()
			local ok, result = Net.Request("SellMany", refs, venue)
			if ok then
				table.clear(selected)
				if venue == "Bin" then
					C.Notify.Toast(
						"📦 "
							.. result.Sold
							.. " stacks in the bin — paid in the morning (≈ "
							.. Kit.Money(result.Total)
							.. ")",
						"Success"
					)
					C.Audio.PlayUI("Place")
				else
					C.Audio.PlayUI("Coins")
				end
			else
				C.Notify.Toast(tostring(result or "Couldn't sell that"), "Warning")
			end
			refresh()
		end
		if C.Settings.Get("SellConfirm") ~= false and total >= Economy.Selling.ConfirmAbove then
			Kit.Confirm(
				"Sell for " .. Kit.Money(total) .. "?",
				"You're about to sell " .. #refs .. " stacks. Locked items are never sold.",
				function(yes)
					if yes then
						go()
					end
				end,
				"Sell"
			)
		else
			go()
		end
	end)

	-- Fresh market data for accurate estimates.
	task.spawn(function()
		local ok, data = Net.Request("MarketGet")
		if ok then
			Prices.SetSnapshot(data)
			if frame.Parent then
				refresh()
			end
		end
	end)
	refresh()
	return { Frame = frame, Refresh = refresh }
end

return SellPanel

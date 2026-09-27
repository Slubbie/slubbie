-- Collection book: every treasure per region. Undiscovered items show as silhouettes with their
-- rarity; discovered ones show how many you've found and which mutations you've seen.
-- Completing a region pays a one-time reward.

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

local BookPanel = {}

function BookPanel.new()
	local content = Panels.Create("Book", "Collection Book", "📖")
	local regionNames, byName = {}, {}
	for _, region in Config.Regions.List do
		if Config.IsLive(region) then
			local short = region.Name:match("^(%S+)") or region.Name
			table.insert(regionNames, short)
			byName[short] = region
		end
	end
	local selected = regionNames[1]
	local refresh: () -> ()
	local setTab = Kit.Tabs(content, regionNames, function(name)
		selected = name
		refresh()
	end)

	local header = Kit.new("Frame", {
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundTransparency = 1,
		Parent = content,
	})
	local summary = Kit.Label({
		Parent = header,
		Size = UDim2.new(1, -200, 1, 0),
		Font = Theme.Fonts.Bold,
		TextSize = 15,
		Text = "",
	})
	local claim = Kit.Button({
		Parent = header,
		Text = "Claim",
		Color = C.Gold,
		TextColor = C.Ink,
		Size = UDim2.fromOffset(190, 44),
		Position = UDim2.new(1, 0, 0, 3),
		AnchorPoint = Vector2.new(1, 0),
		OnClick = function()
			local region = byName[selected]
			local result = ClientState.Request("ClaimCollection", region.Id)
			if result.ok then
				Sound.Play("Purchase")
				Effects.Coins(10)
				Effects.Confetti(60)
				Toasts.Show(
					"📖 " .. region.Name .. " collection complete! +🪙 " .. Format.Coins(result.Reward),
					"reward",
					4
				)
			else
				Toasts.Show(result.err, "error")
			end
		end,
	})

	local grid = Kit.new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 102),
		Size = UDim2.new(1, 0, 1, -102),
		BackgroundColor3 = C.PanelAlt,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = content,
	})
	Kit.Corner(grid, 10)
	Kit.Padding(grid, 8)
	Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(180, 176),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})

	function refresh()
		local data = ClientState.Data
		if not data or not Panels.IsOpen("Book") then
			return
		end
		setTab(selected)
		Kit.Clear(grid)
		local region = byName[selected]
		local items = Config.ItemsIn(region.Id)
		table.sort(items, function(a, b)
			return Config.Rarities.Order(a.Rarity) < Config.Rarities.Order(b.Rarity)
		end)
		local found = 0
		for i, item in items do
			local count = data.Discovered[item.Id]
			local known = count ~= nil
			if known then
				found += 1
			end
			local card = Kit.Card({ Parent = grid, LayoutOrder = i })
			card.BackgroundColor3 = if known then C.Panel else C.PanelDeep
			local icon = ItemIcon.Create(item.Id, nil, 60, not known)
			icon.Position = UDim2.new(0.5, 0, 0, 8)
			icon.AnchorPoint = Vector2.new(0.5, 0)
			icon.Parent = card
			Kit.Label({
				Parent = card,
				Position = UDim2.fromOffset(6, 72),
				Size = UDim2.new(1, -12, 0, 34),
				Text = if known then item.Name else "???",
				Font = Theme.Fonts.Bold,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Top,
			})
			local chip = Kit.Chip(card, Theme.RarityText(item.Rarity), Theme.Rarity(item.Rarity), C.Ink)
			chip.Position = UDim2.new(0.5, 0, 0, 106)
			chip.AnchorPoint = Vector2.new(0.5, 0)
			chip.TextSize = 11
			local detail
			if known then
				local variants = {}
				for _, m in Config.Economy.Mutations.List do
					if data.MutationsFound[item.Id .. "|" .. m.Id] then
						table.insert(variants, ItemIcon.MutationGlyph(m.Id))
					end
				end
				detail = string.format("Found ×%d", count)
					.. (if #variants > 0 then "\n" .. table.concat(variants, " ") else "\nNo mutations yet")
			else
				detail = if item.Special then "✦ Special: Straights & Jackpots" else "Keep rolling here!"
			end
			Kit.Label({
				Parent = card,
				Position = UDim2.fromOffset(6, 130),
				Size = UDim2.new(1, -12, 0, 40),
				Text = detail,
				TextSize = 12,
				TextColor3 = C.InkSoft,
				TextXAlignment = Enum.TextXAlignment.Center,
			})
		end
		local claimed = data.Collection[region.Id] == true
		summary.Text = string.format(
			"%s: %d / %d discovered   ·   Completion reward 🪙 %s%s",
			region.Name,
			found,
			#items,
			Format.Coins(region.CollectionReward),
			if claimed then " (claimed)" else ""
		)
		claim:SetText(if claimed then "✓ Claimed" else "Claim 🪙 " .. Format.Coins(region.CollectionReward))
		claim:SetEnabled(not claimed and found == #items)
	end

	ClientState.Changed:Connect(refresh)
	Panels.Opened:Connect(function(name)
		if name == "Book" then
			local here = ClientState.CurrentRegion()
			if here then
				selected = here.Name:match("^(%S+)") or here.Name
			end
			refresh()
		end
	end)
end

return BookPanel

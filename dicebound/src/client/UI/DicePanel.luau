-- Dice: see every die's faces, perk and tradeoff; buy dice; choose which dice fill your tray
-- slots and which one leads (the lead die picks the reward tier).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Dicebound.Config)
local Format = require(ReplicatedStorage.Dicebound.Format)
local ClientState = require(script.Parent.Parent.ClientState)
local Sound = require(script.Parent.Parent.Sound)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)
local Panels = require(script.Parent.Panels)
local Toasts = require(script.Parent.Toasts)

local C = Theme.Colors

local DicePanel = {}

local function dieSwatch(parent: Instance, die, size: number): Frame
	local swatch = Kit.new("Frame", {
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Format.Color(die.Color),
		Parent = parent,
	})
	Kit.Corner(swatch, math.floor(size * 0.22))
	Kit.Stroke(swatch, Format.Color(die.PipColor), 2)
	Kit.Label({
		Parent = swatch,
		Size = UDim2.fromScale(1, 1),
		Text = "⚅",
		TextScaled = true,
		TextColor3 = Format.Color(die.PipColor),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	return swatch
end
DicePanel.Swatch = dieSwatch

function DicePanel.new()
	local content = Panels.Create("Dice", "Dice", "🎲")
	local slotsRow = Kit.new("Frame", { Size = UDim2.new(1, 0, 0, 92), BackgroundTransparency = 1, Parent = content })
	Kit.List(slotsRow, Enum.FillDirection.Horizontal, 8)
	local list = Kit.Scroll(content, { Position = UDim2.fromOffset(0, 100), Size = UDim2.new(1, 0, 1, -100) })
	local busy = false

	local function request(name: string, ...)
		if busy then
			return
		end
		busy = true
		local result = ClientState.Request(name, ...)
		busy = false
		if result.ok then
			Sound.Play("Purchase")
		else
			Sound.Play("Error")
			Toasts.Show(result.err, "error")
		end
		return result
	end

	local function refresh()
		local data = ClientState.Data
		if not data or not Panels.IsOpen("Dice") then
			return
		end
		Kit.Clear(slotsRow)
		Kit.Clear(list)
		local equipped = data.Dice.Equipped
		for slot = 1, Config.Economy.MaxDice do
			local card = Kit.Card({ Parent = slotsRow, Size = UDim2.fromOffset(200, 88), LayoutOrder = slot })
			local dieId = equipped[slot]
			if slot > data.DiceSlots then
				card.BackgroundColor3 = C.PanelDeep
				Kit.Label({
					Parent = card,
					Size = UDim2.fromScale(1, 1),
					Text = "🔒 Slot " .. slot .. "\nBuy the Dice Tray upgrade",
					TextSize = 14,
					TextColor3 = C.InkSoft,
					TextXAlignment = Enum.TextXAlignment.Center,
				})
			elseif dieId then
				local die = Config.Dice.ById[dieId]
				local swatch = dieSwatch(card, die, 56)
				swatch.Position = UDim2.fromOffset(12, 16)
				Kit.Label({
					Parent = card,
					Position = UDim2.fromOffset(78, 12),
					Size = UDim2.new(1, -86, 0, 22),
					Text = die.Name,
					Font = Theme.Fonts.Title,
					TextSize = 17,
				})
				Kit.Label({
					Parent = card,
					Position = UDim2.fromOffset(78, 36),
					Size = UDim2.new(1, -86, 0, 40),
					Text = if slot == 1 then "⭐ Lead die: picks the tier" else "Support die: combos & perks",
					TextSize = 12,
					TextColor3 = if slot == 1 then C.GoldDark else C.InkSoft,
				})
			else
				Kit.Label({
					Parent = card,
					Size = UDim2.fromScale(1, 1),
					Text = "Empty slot " .. slot .. "\nEquip a die below",
					TextSize = 14,
					TextColor3 = C.InkSoft,
					TextXAlignment = Enum.TextXAlignment.Center,
				})
			end
		end

		for _, die in Config.Dice.List do
			if Config.IsLive(die) then
				local owned = data.Dice.Owned[die.Id] == true
				local slot = table.find(equipped, die.Id)
				local card = Kit.Card({ Parent = list, Size = UDim2.new(1, -12, 0, 118), LayoutOrder = die.Order })
				local swatch = dieSwatch(card, die, 64)
				swatch.Position = UDim2.fromOffset(12, 14)
				local faces = {}
				for _, f in die.Faces do
					table.insert(faces, tostring(f))
				end
				local extra = ""
				for regionId, list2 in die.RegionFaces or {} do
					local region = Config.Regions.ById[regionId]
					local parts = {}
					for _, f in list2 do
						table.insert(parts, tostring(f))
					end
					extra ..= string.format(
						"  ·  in %s: %s",
						region and region.Name or regionId,
						table.concat(parts, "-")
					)
				end
				Kit.Label({
					Parent = card,
					Position = UDim2.fromOffset(88, 8),
					Size = UDim2.new(1, -280, 0, 24),
					Text = die.Name .. (if slot then "  (slot " .. slot .. ")" else ""),
					Font = Theme.Fonts.Title,
					TextSize = 20,
				})
				Kit.Label({
					Parent = card,
					Position = UDim2.fromOffset(88, 32),
					Size = UDim2.new(1, -280, 0, 18),
					Text = "Faces: " .. table.concat(faces, "-") .. extra,
					TextSize = 13,
					Font = Theme.Fonts.Bold,
					TextColor3 = C.BlueDark,
				})
				Kit.Label({
					Parent = card,
					Position = UDim2.fromOffset(88, 52),
					Size = UDim2.new(1, -280, 0, 60),
					Text = die.Description .. "\n⚖️ " .. die.Tradeoff,
					TextSize = 13,
					TextColor3 = C.InkSoft,
					TextYAlignment = Enum.TextYAlignment.Top,
				})

				local actions = Kit.new("Frame", {
					Position = UDim2.new(1, -180, 0, 10),
					Size = UDim2.fromOffset(170, 100),
					BackgroundTransparency = 1,
					Parent = card,
				})
				Kit.List(actions, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Right)
				if owned then
					if slot then
						if slot ~= 1 then
							Kit.Button({
								Parent = actions,
								Text = "⭐ Make lead",
								Color = C.Gold,
								TextColor = C.Ink,
								Size = UDim2.fromOffset(160, 40),
								TextSize = 15,
								LayoutOrder = 1,
								OnClick = function()
									local newList = table.clone(equipped)
									table.remove(newList, slot)
									table.insert(newList, 1, die.Id)
									request("EquipDice", newList)
								end,
							})
						end
						local unequip = Kit.Button({
							Parent = actions,
							Text = "Unequip",
							Color = C.InkFaint,
							Size = UDim2.fromOffset(160, 40),
							TextSize = 15,
							LayoutOrder = 2,
							OnClick = function()
								local newList = table.clone(equipped)
								table.remove(newList, slot)
								request("EquipDice", newList)
							end,
						})
						unequip:SetEnabled(#equipped > 1)
					else
						Kit.Button({
							Parent = actions,
							Text = "Equip",
							Color = C.Green,
							Size = UDim2.fromOffset(160, 44),
							TextSize = 17,
							OnClick = function()
								local newList = table.clone(equipped)
								if #newList >= data.DiceSlots then
									newList[#newList] = die.Id
									Toasts.Show("Swapped out your last die (tray is full).", "info", 2.5)
								else
									table.insert(newList, die.Id)
								end
								request("EquipDice", newList)
							end,
						})
					end
				elseif die.Source.Kind == "Shop" then
					local region = Config.Regions.ById[die.Source.Region]
					local unlocked = data.Regions[die.Source.Region] == true
					local buy = Kit.Button({
						Parent = actions,
						Text = "🪙 " .. Format.Coins(die.Source.Price),
						Color = C.Green,
						Size = UDim2.fromOffset(160, 44),
						TextSize = 18,
						OnClick = function()
							local result = request("BuyDie", die.Id)
							if result and result.ok then
								Toasts.Show("🎲 You bought the " .. die.Name .. "!", "success")
							end
						end,
					})
					buy:SetEnabled(unlocked and data.Coins >= die.Source.Price)
					Kit.Label({
						Parent = actions,
						Size = UDim2.fromOffset(160, 36),
						Text = if not unlocked
							then "Sold in " .. (region and region.Name or "?") .. " (locked)"
							elseif data.Coins < die.Source.Price then "Need 🪙 " .. Format.Coins(
								die.Source.Price - data.Coins
							) .. " more"
							else "Sold in " .. region.Name,
						TextSize = 12,
						TextColor3 = C.InkSoft,
						TextXAlignment = Enum.TextXAlignment.Right,
					})
				else
					Kit.Label({
						Parent = actions,
						Size = UDim2.fromOffset(160, 60),
						Text = "⚒️ Craft it at a workbench (Craft menu)",
						TextSize = 13,
						TextColor3 = C.Purple,
						TextXAlignment = Enum.TextXAlignment.Right,
					})
				end
			end
		end
	end

	ClientState.Changed:Connect(refresh)
	Panels.Opened:Connect(function(name)
		if name == "Dice" then
			refresh()
		end
	end)
end

return DicePanel

-- Crafting: turn duplicate treasure into the Celestial Die, auras and tray skins. Shows exactly
-- what each recipe needs and what you have (locked items never count), plus your cosmetics.

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

local CraftPanel = {}

local KIND_ICON = { Die = "🎲", Aura = "✨", Tray = "🟩" }

local function available(data, itemId: string): number
	local n = 0
	for _, stack in data.Bag do
		if stack.Id == itemId and not stack.Locked then
			n += stack.Qty
		end
	end
	return n
end

local function ownsResult(data, recipe): boolean
	if recipe.Kind == "Die" then
		return data.Dice.Owned[recipe.Grants] == true
	elseif recipe.Kind == "Aura" then
		return data.Cosmetics.Auras[recipe.Grants] == true
	end
	return data.Cosmetics.Trays[recipe.Grants] == true
end

function CraftPanel.new()
	local content = Panels.Create("Craft", "Crafting", "⚒️")
	local tab = "Recipes"
	local refresh: () -> ()
	local setTab = Kit.Tabs(content, { "Recipes", "Cosmetics" }, function(name)
		tab = name
		refresh()
	end)
	local list = Kit.Scroll(content, { Position = UDim2.fromOffset(0, 48), Size = UDim2.new(1, 0, 1, -48) })
	local busy = false

	local function act(name: string, ...)
		if busy then
			return nil
		end
		busy = true
		local result = ClientState.Request(name, ...)
		busy = false
		if not result.ok then
			Sound.Play("Error")
			Toasts.Show(result.err, "error")
		end
		return result
	end

	local function recipesTab(data)
		for i, recipe in Config.Crafting.Recipes do
			local owned = ownsResult(data, recipe)
			local card = Kit.Card({ Parent = list, Size = UDim2.new(1, -12, 0, 132), LayoutOrder = i })
			if owned then
				card.BackgroundColor3 = C.PanelAlt
			end
			Kit.Label({
				Parent = card,
				Position = UDim2.fromOffset(14, 8),
				Size = UDim2.new(1, -220, 0, 26),
				Text = KIND_ICON[recipe.Kind] .. " " .. recipe.Name .. (if owned then "  ✓ owned" else ""),
				Font = Theme.Fonts.Title,
				TextSize = 19,
			})
			local needs = Kit.new("Frame", {
				Position = UDim2.fromOffset(14, 38),
				Size = UDim2.new(1, -220, 0, 88),
				BackgroundTransparency = 1,
				Parent = card,
			})
			Kit.new("UIGridLayout", {
				CellSize = UDim2.fromOffset(170, 40),
				CellPadding = UDim2.fromOffset(6, 6),
				Parent = needs,
			})
			local ready = true
			for _, need in recipe.Needs do
				local have = available(data, need.Id)
				if have < need.Qty then
					ready = false
				end
				local chip = Kit.new("Frame", {
					BackgroundColor3 = if have >= need.Qty
						then Color3.fromRGB(226, 246, 214)
						else Color3.fromRGB(255, 232, 226),
					Parent = needs,
				})
				Kit.Corner(chip, 8)
				local icon = ItemIcon.Create(need.Id, nil, 32, data.Discovered[need.Id] == nil)
				icon.Position = UDim2.fromOffset(4, 4)
				icon.Parent = chip
				local item = Config.Items.ById[need.Id]
				Kit.Label({
					Parent = chip,
					Position = UDim2.fromOffset(40, 0),
					Size = UDim2.new(1, -44, 1, 0),
					Text = string.format(
						"%s\n%d / %d",
						if data.Discovered[need.Id] then item.Name else "??? (" .. item.Rarity .. ")",
						math.min(have, need.Qty),
						need.Qty
					),
					TextSize = 11,
					Font = Theme.Fonts.Bold,
					TextColor3 = if have >= need.Qty then C.GreenDark else C.RedDark,
				})
			end
			local craft = Kit.Button({
				Parent = card,
				Text = if owned then "Owned" else "Craft  🪙 " .. Format.Coins(recipe.Coins),
				Color = C.Purple,
				Size = UDim2.fromOffset(190, 52),
				Position = UDim2.new(1, -200, 0, 16),
				TextSize = 16,
				OnClick = function()
					local result = act("Craft", recipe.Id)
					if result and result.ok then
						Sound.Play("Purchase")
						Effects.Confetti(50)
						Toasts.Show("⚒️ Crafted " .. recipe.Name .. "!", "success", 3.5)
					end
				end,
			})
			craft:SetEnabled(not owned and ready and data.Coins >= recipe.Coins)
			Kit.Label({
				Parent = card,
				Position = UDim2.new(1, -200, 0, 74),
				Size = UDim2.fromOffset(190, 50),
				Text = if owned
					then "Already in your collection."
					elseif not ready then "Missing ingredients. Locked items don't count."
					elseif data.Coins < recipe.Coins then "Need 🪙 "
						.. Format.Coins(recipe.Coins - data.Coins)
						.. " more"
					else "Ready to craft!",
				TextSize = 12,
				TextColor3 = C.InkSoft,
				TextXAlignment = Enum.TextXAlignment.Center,
			})
		end
	end

	local function cosmeticsTab(data)
		local order = 0
		local function heading(text: string)
			order += 1
			Kit.Label({
				Parent = list,
				Text = text,
				Font = Theme.Fonts.Title,
				TextSize = 20,
				Size = UDim2.new(1, -12, 0, 28),
				LayoutOrder = order,
			})
		end
		local function entry(name: string, color, equipped: boolean, owned: boolean, onEquip: () -> ())
			order += 1
			local card = Kit.Card({ Parent = list, Size = UDim2.new(1, -12, 0, 56), LayoutOrder = order })
			local swatch = Kit.new("Frame", {
				Size = UDim2.fromOffset(36, 36),
				Position = UDim2.fromOffset(12, 10),
				BackgroundColor3 = Format.Color(color),
				Parent = card,
			})
			Kit.Corner(swatch, 18)
			Kit.Label({
				Parent = card,
				Position = UDim2.fromOffset(60, 0),
				Size = UDim2.new(1, -240, 1, 0),
				Text = name .. (if owned then "" else "  (craft to unlock)"),
				Font = Theme.Fonts.Bold,
				TextSize = 16,
				TextColor3 = if owned then C.Ink else C.InkFaint,
			})
			local button = Kit.Button({
				Parent = card,
				Text = if equipped then "Equipped" else "Equip",
				Color = if equipped then C.GreenDark else C.Blue,
				Size = UDim2.fromOffset(160, 40),
				Position = UDim2.new(1, -170, 0, 8),
				TextSize = 15,
				OnClick = onEquip,
			})
			button:SetEnabled(owned and not equipped)
		end
		heading("✨ Auras (everyone can see them)")
		entry("No aura", { 200, 200, 200 }, data.Cosmetics.Aura == "", true, function()
			act("EquipCosmetic", "Aura", "")
		end)
		for id, def in Config.Crafting.Auras do
			entry(def.Name, def.Color, data.Cosmetics.Aura == id, data.Cosmetics.Auras[id] == true, function()
				act("EquipCosmetic", "Aura", id)
			end)
		end
		heading("🟩 Dice tray felts")
		for id, def in Config.Crafting.Trays do
			entry(def.Name, def.Color, data.Cosmetics.Tray == id, data.Cosmetics.Trays[id] == true, function()
				act("EquipCosmetic", "Tray", id)
			end)
		end
	end

	function refresh()
		local data = ClientState.Data
		if not data or not Panels.IsOpen("Craft") then
			return
		end
		setTab(tab)
		Kit.Clear(list)
		if tab == "Recipes" then
			recipesTab(data)
		else
			cosmeticsTab(data)
		end
	end

	ClientState.Changed:Connect(refresh)
	Panels.Opened:Connect(function(name)
		if name == "Craft" then
			refresh()
		end
	end)
end

return CraftPanel

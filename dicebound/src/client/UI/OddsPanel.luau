-- Explains the roll model and shows exact odds from the same tables the server uses.
-- "Base" = a single Wooden Die. "Yours" = your equipped dice. Temporary bonuses (world events,
-- Stage 3) will appear as a third column so base and boosted odds are never mixed up.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Dicebound.Config)
local Odds = require(ReplicatedStorage.Dicebound.Odds)
local ClientState = require(script.Parent.Parent.ClientState)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)
local Panels = require(script.Parent.Panels)

local C = Theme.Colors

local OddsPanel = {}

function OddsPanel.new()
	local content = Panels.Create("Odds", "Odds & Rules", "🎯")
	local scroll = Kit.new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = C.Stroke,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = content,
	})
	Kit.List(scroll, Enum.FillDirection.Vertical, 10)
	Kit.Padding(scroll, 4, 6)

	local order = 0
	local function text(body: string, size: number?, font: Enum.Font?, color: Color3?)
		order += 1
		return Kit.Label({
			Parent = scroll,
			Text = body,
			RichText = true,
			TextSize = size or 15,
			Font = font or Theme.Fonts.Body,
			TextColor3 = color or C.Ink,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, -16, 0, 0),
			LayoutOrder = order,
		})
	end

	local function rebuild()
		for _, child in scroll:GetChildren() do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		order = 0
		local data = ClientState.Data
		local region = ClientState.CurrentRegion() or Config.Regions.List[1]
		local dice = data and data.Dice.Equipped or { Config.Game.StartingDie }
		local base = Odds.Compute(region.Id, { Config.Game.StartingDie })
		local yours = Odds.Compute(region.Id, dice)

		text("How a roll works", 20, Theme.Fonts.Title)
		text(
			"1. Every die lands on one of its 6 faces (1 in 6 each).\n"
				.. "2. Your <b>lead die</b> (slot 1) picks the reward <b>tier</b> from the table below.\n"
				.. "3. A weighted draw picks an item of that tier from this region's loot table.\n"
				.. string.format(
					"4. Each find has a %s chance to be <b>mutated</b> (worth more). Max one mutation.\n",
					Odds.Format(base.MutationChance)
				)
				.. "5. With 2–3 dice, one combo can apply (Stage 2). The server decides every result."
		)

		text("Tier chances by lead-die face", 20, Theme.Fonts.Title)
		local rows = {}
		for face = 1, 6 do
			local row = Config.Economy.FaceTiers[face]
			local total = 0
			for _, w in row do
				total += w
			end
			local parts = {}
			for _, rarity in Config.Rarities.List do
				if row[rarity.Id] then
					table.insert(parts, rarity.Label .. " " .. Odds.Format(row[rarity.Id] / total))
				end
			end
			table.insert(rows, string.format("<b>Face %d:</b> %s", face, table.concat(parts, " · ")))
		end
		text(table.concat(rows, "\n"))

		text("Chance per roll in " .. region.Name, 20, Theme.Fonts.Title)
		local sameDice = #dice == 1 and dice[1] == Config.Game.StartingDie
		local tierLines = {}
		for _, rarity in Config.Rarities.List do
			local b = base.Tiers[rarity.Id] or 0
			local y = yours.Tiers[rarity.Id] or 0
			if b > 0 or y > 0 then
				local color = Theme.Rarity(rarity.Id):ToHex()
				local line = string.format(
					'<font color="#%s"><b>%s</b></font>  %s',
					color,
					Theme.RarityText(rarity.Id),
					Odds.Format(b)
				)
				if not sameDice then
					line ..= "  →  yours " .. Odds.Format(y)
				end
				table.insert(tierLines, line)
			end
		end
		table.insert(
			tierLines,
			"Secret treasures never drop from normal rolls: they come from Straight and Jackpot combos."
		)
		text(table.concat(tierLines, "\n"))
		text(
			if sameDice
				then "Base odds (one Wooden Die). You have no bonuses active."
				else "Left: base odds (one Wooden Die). Right: with your equipped dice.",
			13,
			nil,
			C.InkSoft
		)

		text("Items in " .. region.Name, 20, Theme.Fonts.Title)
		local itemLines = {}
		local items = Config.ItemsIn(region.Id)
		table.sort(items, function(a, b)
			return Config.Rarities.Order(a.Rarity) < Config.Rarities.Order(b.Rarity)
		end)
		for _, item in items do
			local known = data and data.Discovered[item.Id] ~= nil
			local name = if known then item.Glyph .. " " .. item.Name else "❔ Undiscovered"
			local chance = if item.Special then "combos only" else Odds.Format(yours.Items[item.Id] or 0)
			table.insert(itemLines, string.format("%s  <i>(%s)</i>  %s", name, item.Rarity, chance))
		end
		text(table.concat(itemLines, "\n"))

		text("Mutations", 20, Theme.Fonts.Title)
		local mutationLines = { "If a find mutates, which mutation it gets:" }
		for _, mutation in Config.Economy.Mutations.List do
			local p = yours.Mutations[mutation.Id]
			if p then
				table.insert(
					mutationLines,
					string.format(
						"<b>%s</b> ×%d value  ·  %s of mutations",
						mutation.Label,
						mutation.Multiplier,
						Odds.Format(p)
					)
				)
			end
		end
		table.insert(
			mutationLines,
			"Frozen, Overgrown and Cosmic only appear in their home regions (or with certain dice)."
		)
		text(table.concat(mutationLines, "\n"))

		text("Dice combos (Stage 2: needs 2–3 dice)", 20, Theme.Fonts.Title)
		text(
			"Only the <b>single highest</b> combo applies:\n"
				.. "<b>Jackpot</b> (2+ dice, all on their top face): +1 Legendary-or-better find and bonus coins.\n"
				.. "<b>Triple</b> (3 dice, same face): +1 bonus find using the face-6 tier row.\n"
				.. string.format(
					"<b>Straight</b> (3 dice in a run, e.g. 2-3-4): %s chance of the region's special collectible.\n",
					Odds.Format(Config.Economy.Combos.Straight.CollectibleChance)
				)
				.. "<b>Pair</b> (2+ dice share a face): the main find comes in a pair (×2).\n"
				.. "A roll can never give more than 2 items, and the bag reserves room for them before you roll."
		)
		text(
			string.format("Average value per roll here: about 🪙 %.1f", yours.ExpectedCoins),
			14,
			Theme.Fonts.Bold,
			C.InkSoft
		)
	end

	Panels.Opened:Connect(function(name)
		if name == "Odds" then
			rebuild()
		end
	end)
end

return OddsPanel

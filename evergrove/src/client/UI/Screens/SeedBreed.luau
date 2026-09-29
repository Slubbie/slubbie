-- The Genetics Lab: cross two seeds. Same crop → better genes (Vigor,
-- Bounty, Hardiness, Luster); two different crops from the hybrid notes → a
-- chance at a new species, boosted by the right weather or season.
-- "Scan" shows the genes of every seed in your bag.
-- Args: { Tab = "Breed" | "Scan" | "Notes" }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local ItemUtil = require(Shared.Lib.ItemUtil)
local Genetics = require(Shared.Lib.Genetics)
local WeatherMath = require(Shared.Lib.WeatherMath)
local GameTime = require(Shared.Lib.GameTime)
local Crops = require(Shared.Config.Crops)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Picker = require(UI.Picker)
local C = require(UI.Parent.Controllers)

local GENE_NAMES = { "Vigor", "Bounty", "Hardiness", "Luster" }
local GENE_HINTS = { "grows faster", "extra harvests", "shrugs off pests & weather", "better quality" }

local function geneRows(parent: Instance, genes: { number }?, order: number)
	for i, name in GENE_NAMES do
		local value = (genes and genes[i]) or 0
		local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = order + i, Parent = parent })
		local label = Kit.Label(name, { Size = Theme.Sizes.Tiny })
		label.Size = UDim2.fromOffset(80, 20)
		label.Parent = row
		local bar = Kit.Progress({ Size = UDim2.new(1, -130, 0, 10), Color = if value >= 7 then "Good" elseif value >= 4 then "Accent" else "Warn" })
		bar.Frame.Position = UDim2.new(0, 82, 0.5, -5)
		bar.Frame.Parent = row
		bar.Set(value / 10, nil, false)
		local v = Kit.Label(tostring(math.floor(value * 10) / 10), { Size = Theme.Sizes.Tiny, Align = "Right", Color = "SubText" })
		v.Size = UDim2.fromOffset(44, 20)
		v.Position = UDim2.new(1, -44, 0, 0)
		v.Parent = row
	end
end

local function cropOf(stack: any): any?
	local def = stack and Registry.Items[stack.Id]
	return def and def.Plants and Registry.Crops[def.Plants]
end

return {
	Id = "SeedBreed",
	Title = "Genetics Lab",
	Icon = "🧬",
	Size = Vector2.new(900, 600),
	Watch = { "Inventory", "Collection" },
	Build = function(win, ctx)
		local args = ctx.Args or {}
		local content = win.Content :: Frame
		local mode = args.Tab or "Breed"
		local picks: { string? } = { nil, nil }
		local lastResult: any = nil
		local render: () -> ()
		local tabs = Kit.Tabs({ { Id = "Breed", Label = "Cross seeds", Icon = "🧬" }, { Id = "Scan", Label = "Gene scan", Icon = "🔬" }, { Id = "Notes", Label = "Hybrid notes", Icon = "📓" } }, function(id)
			mode = id
			render()
		end)
		tabs.Frame.Parent = content
		local body = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -46), Position = UDim2.fromOffset(0, 46), Parent = content })

		local function stackAt(ref: string?): any?
			local key = ref and string.match(ref, "^inv:(%d+)$")
			return key and C.State.Get("Inventory", "Slots", key)
		end

		local function renderBreed()
			local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 250), Parent = body })
			for side = 1, 2 do
				local panel = Kit.Panel({ Size = UDim2.new(0.4, -10, 1, 0), Position = UDim2.new(if side == 1 then 0 else 0.6, if side == 1 then 0 else 10, 0, 0), Color = "PanelAlt" })
				panel.Parent = row
				Kit.Padding(panel, 10, 12)
				Kit.List(panel, "Y", 6, "Center")
				local stack = stackAt(picks[side])
				local slot = Kit.ItemSlot(72)
				slot.Set(stack)
				slot.Button.Parent = panel
				slot.Button.Activated:Connect(function()
					Picker.Open({
						Title = "Choose seed " .. side,
						Filter = function(s, def)
							return def.Plants ~= nil and not s.L
						end,
						Note = function(s)
							return if s.G then string.format("genes %d%%", Genetics.GeneScore(s.G) * 100) else "shop genes"
						end,
						Empty = "You have no seeds.",
						OnPick = function(ref)
							picks[side] = ref
							lastResult = nil
							render()
						end,
					})
				end)
				local name = Kit.Label(if stack then ItemUtil.DisplayName(stack) else "Click to choose a seed", { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold, Align = "Center" })
				name.LayoutOrder = 1
				name.Parent = panel
				if stack then
					local genes = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = panel })
					Kit.List(genes, "Y", 2)
					geneRows(genes, stack.G, 0)
					if not stack.G then
						local note = Kit.Label("Shop seed: average genes", { Size = Theme.Sizes.Tiny, Color = "SubText", Align = "Center" })
						note.LayoutOrder = 3
						note.Parent = panel
					end
				end
			end
			local middle = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.2, 0, 1, 0), Position = UDim2.fromScale(0.4, 0), Parent = row })
			Kit.List(middle, "Y", 8, "Center")
			local x = Kit.Label("×", { Size = 40, Font = Theme.Fonts.Heading, Align = "Center" })
			x.Size = UDim2.new(1, 0, 0, 60)
			x.Parent = middle
			local a, b = stackAt(picks[1]), stackAt(picks[2])
			local cropA, cropB = cropOf(a), cropOf(b)
			local outlook = ""
			local outlookKey = "SubText"
			if cropA and cropB then
				if cropA.Id == cropB.Id then
					outlook = "Same crop: genes cross — usually better than the average, sometimes a breakthrough."
					if picks[1] == picks[2] and a and a.N < 2 then
						outlook = "You need two of that seed."
						outlookKey = "Warn"
					end
				else
					local hybrid = Genetics.Hybrid(cropA.Id, cropB.Id)
					if hybrid then
						local result = Registry.Crops[hybrid.Result]
						local chance = hybrid.Chance or 0.1
						local weatherNow = WeatherMath.Current()
						local boosted = hybrid.Weather == weatherNow or hybrid.Season == GameTime.Info().SeasonId
						local wdef = hybrid.Weather and WeatherMath.Def(hybrid.Weather)
						outlook = string.format("Hybrid! %s %s — base chance %d%%.", if result then result.Icon else "✨", if result then result.Name else hybrid.Result, math.floor(chance * 100))
						if wdef then
							outlook ..= " ×3 during " .. wdef.Icon .. " " .. wdef.Name .. "."
						end
						if hybrid.Season then
							outlook ..= " ×2 in " .. hybrid.Season .. "."
						end
						if boosted then
							outlook ..= " (Boosted right now!)"
						end
						outlookKey = "Accent"
					else
						outlook = "These two won't cross."
						outlookKey = "Warn"
					end
				end
			end
			local hint = Kit.Label(outlook, { Size = Theme.Sizes.Tiny, Color = outlookKey, Wrap = true, Align = "Center" })
			hint.LayoutOrder = 1
			hint.Parent = middle
			local go = Kit.Button("🧬 Cross", { Style = "Accent", Size = UDim2.new(1, 0, 0, 42), LayoutOrder = 2, OnClick = function()
				local ok, result = Net.Request("SeedBreed", picks[1], picks[2])
				if ok then
					lastResult = result
					picks = { nil, nil }
					C.Audio.PlayUI(if result.Hybrid then "LegendaryReveal" else "Discovery")
				else
					C.Notify.Toast(tostring(result), "Warning")
				end
				render()
			end })
			go.Parent = middle
			Kit.SetEnabled(go, cropA ~= nil and cropB ~= nil and outlookKey ~= "Warn")
			-- Result
			local resultPanel = Kit.Panel({ Size = UDim2.new(1, 0, 1, -262), Position = UDim2.fromOffset(0, 262), Color = "PanelAlt" })
			resultPanel.Parent = body
			Kit.Padding(resultPanel, 10, 14)
			Kit.List(resultPanel, "Y", 6)
			if lastResult then
				local seed = lastResult.Seed
				local title = Kit.Heading((if lastResult.Hybrid then "🎉 Hybrid breakthrough! " else "New seed: ") .. ItemUtil.DisplayName(seed), 18)
				title.Parent = resultPanel
				local score = Kit.Label(string.format("Gene score %d%%", (lastResult.Score or 0) * 100), { Size = Theme.Sizes.Small, Color = "Accent" })
				score.LayoutOrder = 1
				score.Parent = resultPanel
				geneRows(resultPanel, seed.G, 10)
			else
				local info = {}
				for i, name in GENE_NAMES do
					table.insert(info, name .. " — " .. GENE_HINTS[i])
				end
				local intro = Kit.Label("Seed genes: " .. table.concat(info, " · ") .. ". Plant high-gene seeds and their harvests pass good genes on. Cross seeds at your own Genetics Lab, or with Juniper at the Vale Research Lab in town.", { Size = Theme.Sizes.Small, Color = "SubText", Wrap = true })
				intro.Parent = resultPanel
			end
		end

		local function renderScan()
			local profile = C.State.Data()
			local list = Kit.Scroll({ Size = UDim2.fromScale(1, 1) })
			list.Parent = body
			local layout = Kit.new("UIGridLayout", { CellSize = UDim2.new(0.5, -6, 0, 150), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
			layout.FillDirectionMaxCells = 2
			local entries = {}
			for key, stack in (profile and profile.Inventory.Slots) or {} do
				local def = Registry.Items[stack.Id]
				if def and def.Plants then
					table.insert(entries, { Key = key, Stack = stack })
				end
			end
			table.sort(entries, function(x, y)
				return Genetics.GeneScore(x.Stack.G) > Genetics.GeneScore(y.Stack.G)
			end)
			for i, entry in entries do
				local card = Kit.Card(150)
				card.LayoutOrder = i
				card.Parent = list
				Kit.List(card, "Y", 3)
				local head = Kit.Label(Kit.ItemIcon(entry.Stack.Id) .. " " .. ItemUtil.DisplayName(entry.Stack) .. " ×" .. entry.Stack.N .. string.format("   %d%%", Genetics.GeneScore(entry.Stack.G) * 100), { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold })
				head.Parent = card
				geneRows(card, entry.Stack.G, 1)
				if entry.Stack.T then
					local latent = Kit.Label("💤 Latent: " .. entry.Stack.T, { Size = Theme.Sizes.Tiny, Color = "Leaf" })
					latent.LayoutOrder = 10
					latent.Parent = card
				end
			end
			if #entries == 0 then
				Kit.Empty("No seeds in your bag.").Parent = list
			end
		end

		local function renderNotes()
			local profile = C.State.Data()
			local found = (profile and profile.Collection and profile.Collection.Crops) or {}
			local list = Kit.Scroll({ Size = UDim2.fromScale(1, 1) })
			list.Parent = body
			Kit.List(list, "Y", 6)
			local intro = Kit.Label("Rumours of crossings, collected from villagers. Discovered hybrids show their full recipe.", { Size = Theme.Sizes.Small, Color = "SubText", Wrap = true })
			intro.Parent = list
			for i, hybrid in Crops.Hybrids do
				local result = Registry.Crops[hybrid.Result]
				local a, b = Registry.Crops[hybrid.A], Registry.Crops[hybrid.B]
				local known = found[hybrid.Result] ~= nil
				local wdef = hybrid.Weather and WeatherMath.Def(hybrid.Weather)
				local card = Kit.Card(48)
				card.LayoutOrder = i
				card.Parent = list
				local text
				if known then
					text = (if a then a.Icon .. " " .. a.Name else hybrid.A) .. "  ×  " .. (if b then b.Icon .. " " .. b.Name else hybrid.B) .. "   →   " .. (if result then result.Icon .. " " .. result.Name else hybrid.Result)
				else
					text = (if a then a.Icon .. " " .. a.Name else "?") .. "  ×  ❓   →   ❓ " .. (if result then Theme.Rarity(result.Rarity).Glyph .. " " .. result.Rarity .. " crop" else "")
				end
				local label = Kit.Label(text, { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold })
				label.Size = UDim2.new(1, 0, 0, 20)
				label.Parent = card
				local sub = Kit.Label((if wdef then "Loves " .. wdef.Icon .. " " .. wdef.Name .. " weather" else "") .. (if hybrid.Season then (if wdef then " · " else "") .. "best in " .. hybrid.Season else "") .. string.format("  ·  %d%% base", (hybrid.Chance or 0.1) * 100), { Size = Theme.Sizes.Tiny, Color = "SubText" })
				sub.Position = UDim2.fromOffset(0, 20)
				sub.Size = UDim2.new(1, 0, 0, 16)
				sub.Parent = card
			end
		end

		render = function()
			Kit.Clear(body)
			if mode == "Breed" then
				renderBreed()
			elseif mode == "Scan" then
				renderScan()
			else
				renderNotes()
			end
			Kit.RepaintGradients(body)
		end
		tabs.Select(mode)
		return { Refresh = render }
	end,
}

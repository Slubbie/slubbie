-- Crafting & cooking: every recipe you know (and hints for the ones you
-- don't), filtered by station, category and search, with what you have vs.
-- need; batch crafting; and the experiment bench for secret recipes.
-- Args: { Station = "Workbench" | "Kitchen" | ... } when opened at a station.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local Stats = require(Shared.Lib.Stats)
local Recipes = require(Shared.Config.Recipes)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Picker = require(UI.Picker)
local Describe = require(UI.Describe)
local C = require(UI.Parent.Controllers)

local STATION_ORDER = { "Hand", "Workbench", "Workshop", "Kitchen", "Alchemy" }

local function knows(profile: any, recipe: any): boolean
	return recipe.Unlock.Default == true or (profile and profile.Recipes and profile.Recipes[recipe.Id] == true)
end

local function unlockText(recipe: any): string
	local u = recipe.Unlock
	if u.Skill then
		return "Reach " .. u.Skill[1] .. " level " .. u.Skill[2]
	elseif u.Friend then
		local npc = Registry.Npcs[u.Friend[1]]
		return u.Friend[2] .. " ❤ with " .. (if npc then npc.Name else u.Friend[1])
	elseif u.Quest then
		local quest = Registry.Quests[u.Quest]
		return "Quest: " .. (if quest then quest.Name else u.Quest)
	elseif u.Book then
		return "Found in a recipe book"
	elseif u.Festival then
		local festival = Registry.Festivals[u.Festival]
		return "Festival: " .. (if festival then festival.Name else u.Festival)
	elseif u.Secret then
		return "Secret — discover it by experimenting"
	end
	return "Unknown"
end

local function maxCraftable(profile: any, recipe: any): number
	local best = Recipes.MaxBatch
	for _, input in recipe.In do
		local have = Describe.CountInBag(profile, input[1])
		best = math.min(best, math.floor(have / input[2]))
	end
	return best
end

return {
	Id = "Crafting",
	Title = "Crafting",
	Icon = "🔨",
	Size = Vector2.new(980, 620),
	Watch = { "Inventory", "Recipes", "Skills" },
	Build = function(win, ctx)
		local args = ctx.Args or {}
		local here = args.Station
		local content = win.Content :: Frame
		local station = here or "All"
		local category = "All"
		local query = ""
		local onlyCraftable = false
		local selected: string? = nil
		local mode = "Recipes"
		local bench: { string } = {}
		local render: () -> ()

		if here and Recipes.Stations[here] then
			win.Title.Text = Recipes.Stations[here].Icon .. "  " .. Recipes.Stations[here].Name
		end

		local tabs = Kit.Tabs({ { Id = "Recipes", Label = "Recipes", Icon = "📖" }, { Id = "Experiment", Label = "Experiment", Icon = "🧪" } }, function(id)
			mode = id
			render()
		end)
		tabs.Frame.Parent = content
		local body = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -46), Position = UDim2.fromOffset(0, 46), Parent = content })

		local function doCraft(recipe: any, times: number)
			local ok, result = Net.Request("Craft", recipe.Id, times)
			if ok then
				C.Audio.PlayUI(if recipe.Station == "Kitchen" then "Eat" else "Place")
				local out = Registry.Items[recipe.Out]
				C.Notify.Toast("Made " .. tostring(result) .. " × " .. (if out then out.Name else recipe.Out), "Success")
			else
				C.Notify.Toast(tostring(result), "Warning")
			end
		end

		local function renderRecipes()
			local profile = C.State.Data()
			-- Filters
			local filters = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), Parent = body })
			Kit.List(filters, "X", 4)
			local stations = { "All" }
			for _, s in STATION_ORDER do
				table.insert(stations, s)
			end
			for i, s in stations do
				local def = Recipes.Stations[s]
				local b = Kit.Button(if def then def.Icon else "✨", { Style = "Secondary", Size = UDim2.fromOffset(40, 32), TextSize = 16, LayoutOrder = i, OnClick = function()
					station = s
					render()
				end })
				Kit.Paint(b, "BackgroundColor3", if station == s then "HeaderA" else "PanelAlt")
				Kit.AttachTooltip(b, function()
					return { { Text = if def then def.Name else "All stations" } }
				end)
				b.Parent = filters
			end
			local search = Kit.TextBox("🔍 Search recipes…", { Size = UDim2.fromOffset(220, 32), Text = query })
			search.LayoutOrder = 20
			search.Parent = filters
			local canWrap = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(170, 32), LayoutOrder = 21, Parent = filters })
			local canLabel = Kit.Label("Can make", { Size = Theme.Sizes.Small })
			canLabel.Size = UDim2.fromOffset(80, 32)
			canLabel.Parent = canWrap
			local toggle = Kit.Toggle(onlyCraftable, function(v)
				onlyCraftable = v
				render()
			end)
			toggle.Position = UDim2.fromOffset(84, 2)
			toggle.Parent = canWrap
			-- Category chips
			local cats = { "All" }
			for _, recipe in Recipes.List do
				if not table.find(cats, recipe.Category) then
					table.insert(cats, recipe.Category)
				end
			end
			local catBar = Kit.Scroll({ Horizontal = true, Size = UDim2.new(1, 0, 0, 32), Position = UDim2.fromOffset(0, 38) })
			catBar.Parent = body
			Kit.List(catBar, "X", 4)
			for i, cat in cats do
				local b = Kit.Button(cat, { Style = "Secondary", Size = UDim2.fromOffset(0, 28), TextSize = Theme.Sizes.Tiny, LayoutOrder = i, OnClick = function()
					category = cat
					render()
				end })
				b.AutomaticSize = Enum.AutomaticSize.X
				Kit.Padding(b, 0, 10)
				Kit.Paint(b, "BackgroundColor3", if category == cat then "HeaderA" else "PanelAlt")
				Kit.Paint(b, "TextColor3", if category == cat then "HeaderText" else "Text")
				b.Parent = catBar
			end
			local list = Kit.Scroll({ Size = UDim2.new(0.55, -6, 1, -78), Position = UDim2.fromOffset(0, 78) })
			list.Parent = body
			Kit.List(list, "Y", 4)
			local detail = Kit.Panel({ Size = UDim2.new(0.45, -6, 1, -78), Position = UDim2.new(0.55, 6, 0, 78), Color = "PanelAlt" })
			detail.Parent = body
			Kit.Padding(detail, 12, 14)

			local entries = {}
			for _, recipe in Recipes.List do
				local known = knows(profile, recipe)
				local out = Registry.Items[recipe.Out]
				local matchStation = station == "All" or recipe.Station == station
				local matchCat = category == "All" or recipe.Category == category
				local name = if out then out.Name else recipe.Out
				local matchQuery = query == "" or (known and string.find(string.lower(name), string.lower(query), 1, true) ~= nil)
				local craftable = known and maxCraftable(profile, recipe) > 0
				if matchStation and matchCat and matchQuery and (not onlyCraftable or craftable) then
					table.insert(entries, { Recipe = recipe, Known = known, Craftable = craftable, Name = name })
				end
			end
			table.sort(entries, function(a, b)
				if a.Known ~= b.Known then
					return a.Known
				end
				if a.Craftable ~= b.Craftable then
					return a.Craftable
				end
				return a.Name < b.Name
			end)
			local knownCount = 0
			for _, recipe in Recipes.List do
				if knows(profile, recipe) then
					knownCount += 1
				end
			end
			local count = Kit.Label(knownCount .. " / " .. #Recipes.List .. " recipes known", { Size = Theme.Sizes.Tiny, Color = "SubText" })
			count.Parent = list
			for i, entry in entries do
				local recipe = entry.Recipe
				local secretHidden = not entry.Known and recipe.Unlock.Secret
				local row = Kit.new("TextButton", { AutoButtonColor = false, Text = "", Size = UDim2.new(1, -8, 0, 50), LayoutOrder = i, Selectable = true, Parent = list })
				Kit.Paint(row, "BackgroundColor3", if selected == recipe.Id then "SlotHover" else "PanelAlt")
				Kit.Corner(row, 8)
				local slot = Kit.ItemSlot(40)
				slot.Button.Active = false
				slot.Button.Position = UDim2.fromOffset(5, 5)
				slot.Set(if secretHidden then nil else { Id = recipe.Out, N = recipe.N })
				slot.Button.Parent = row
				local stationDef = Recipes.Stations[recipe.Station]
				local name = Kit.Label(if secretHidden then "??? (secret)" else entry.Name, { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold, Color = if not entry.Known then "SubText" elseif entry.Craftable then "Good" else "Text" })
				name.Position = UDim2.fromOffset(52, 5)
				name.Size = UDim2.new(1, -60, 0, 20)
				name.Parent = row
				local inputs = {}
				for _, input in recipe.In do
					local def = Registry.Items[input[1]]
					table.insert(inputs, (if def then def.Icon else "✳️") .. input[2])
				end
				local sub = Kit.Label((if stationDef then stationDef.Icon .. " " else "") .. (if entry.Known then table.concat(inputs, "  ") else "🔒 " .. unlockText(recipe)), { Size = Theme.Sizes.Tiny, Color = "SubText" })
				sub.Position = UDim2.fromOffset(52, 26)
				sub.Size = UDim2.new(1, -60, 0, 16)
				sub.Parent = row
				row.Activated:Connect(function()
					selected = recipe.Id
					Kit.PlaySound("UIClick")
					render()
				end)
			end
			if #entries == 0 then
				Kit.Empty("No recipes match.").Parent = list
			end
			-- Detail
			local recipe = selected and Registry.Recipes[selected]
			if not recipe then
				local tip = Kit.Label("Choose a recipe.\n\nHand recipes work anywhere; others need their station — the Workbench in your yard, or a Kitchen, Workshop or Alchemy Table you build.", { Size = Theme.Sizes.Small, Color = "SubText", Wrap = true })
				tip.Parent = detail
				return
			end
			local known = knows(profile, recipe)
			Kit.List(detail, "Y", 8)
			local out = Registry.Items[recipe.Out]
			if known or not recipe.Unlock.Secret then
				local head = Kit.Heading((if out then out.Icon .. " " .. out.Name else recipe.Out) .. (if recipe.N > 1 then " ×" .. recipe.N else ""), 20)
				head.Parent = detail
				if out and out.Description ~= "" then
					local d = Kit.Label(out.Description, { Size = Theme.Sizes.Small, Color = "SubText", Wrap = true })
					d.LayoutOrder = 1
					d.Parent = detail
				end
			else
				Kit.Heading("??? Secret recipe", 20).Parent = detail
			end
			local stationDef = Recipes.Stations[recipe.Station]
			local where = Kit.Label("📍 " .. (if stationDef then stationDef.Icon .. " " .. stationDef.Name else recipe.Station) .. "   ·   " .. recipe.Skill, { Size = Theme.Sizes.Small })
			where.LayoutOrder = 2
			where.Parent = detail
			if not known then
				local lock = Kit.Label("🔒 " .. unlockText(recipe), { Size = Theme.Sizes.Small, Color = "Warn", Wrap = true })
				lock.LayoutOrder = 3
				lock.Parent = detail
				return
			end
			for i, input in recipe.In do
				local have = Describe.CountInBag(profile, input[1])
				local def = Registry.Items[input[1]]
				local line = Kit.Label((if have >= input[2] then "✔️ " else "✖️ ") .. (if def then def.Icon .. " " else "") .. Registry.SpecName(input[1]) .. "   " .. have .. " / " .. input[2], { Size = Theme.Sizes.Small, Color = if have >= input[2] then "Good" else "Bad" })
				line.LayoutOrder = 10 + i
				line.Parent = detail
			end
			local max = maxCraftable(profile, recipe)
			local buttons = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 50, Parent = detail })
			Kit.List(buttons, "X", 8)
			local one = Kit.Button("Make 1", { Style = "Primary", Size = UDim2.fromOffset(110, 38), OnClick = function()
				doCraft(recipe, 1)
			end })
			one.Parent = buttons
			Kit.SetEnabled(one, max >= 1)
			local many = Kit.Button("Make…", { Style = "Secondary", Size = UDim2.fromOffset(100, 38), LayoutOrder = 1, OnClick = function()
				Kit.AskNumber("How many batches?", max, max, function(n)
					if n then
						doCraft(recipe, n)
					end
				end)
			end })
			many.Parent = buttons
			Kit.SetEnabled(many, max >= 2)
			if out then
				Kit.AttachTooltip(one, function()
					return Kit.ItemTooltip({ Id = recipe.Out, N = recipe.N })
				end)
			end
			if recipe.Station ~= "Hand" and here ~= recipe.Station then
				local note = Kit.Label("You'll need to be at a " .. (if stationDef then stationDef.Name else recipe.Station) .. " to make this.", { Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true })
				note.LayoutOrder = 51
				note.Parent = detail
			end
			search:GetPropertyChangedSignal("Text"):Connect(function()
				query = search.Text
			end)
			search.FocusLost:Connect(function()
				render()
			end)
		end

		local function renderExperiment()
			local profile = C.State.Data()
			local intro = Kit.Label("Some recipes are secrets. Combine 2–" .. Recipes.MaxExperimentItems .. " different items from your bag and see what happens. Nothing is used up unless you discover something — you just learn the recipe.", { Size = Theme.Sizes.Small, Color = "SubText", Wrap = true })
			intro.Parent = body
			local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 96), Position = UDim2.fromOffset(0, 60), Parent = body })
			Kit.List(row, "X", 12, "Center")
			for i = 1, Recipes.MaxExperimentItems do
				local id = bench[i]
				local slot = Kit.ItemSlot(84)
				slot.Button.LayoutOrder = i
				slot.Set(if id then { Id = id, N = 1 } else nil)
				slot.Button.Parent = row
				slot.Button.Activated:Connect(function()
					if bench[i] then
						table.remove(bench, i)
						render()
						return
					end
					Picker.Open({
						Title = "Add an ingredient",
						Filter = function(stack, def)
							return def.Category ~= "Tool" and not table.find(bench, stack.Id)
						end,
						OnPick = function(_, stack)
							if #bench < Recipes.MaxExperimentItems and not table.find(bench, stack.Id) then
								table.insert(bench, stack.Id)
							end
							render()
						end,
					})
				end)
			end
			local go = Kit.Button("🧪 Combine!", { Style = "Accent", Size = UDim2.fromOffset(200, 44), OnClick = function()
				local ok, result = Net.Request("Experiment", bench)
				if ok then
					local recipe = Registry.Recipes[result]
					table.clear(bench)
					mode = "Recipes"
					selected = result
					if recipe then
						C.Audio.PlayUI("LegendaryReveal")
					end
					tabs.Select("Recipes")
				else
					C.Notify.Toast(tostring(result), "Info")
					C.Audio.PlayUI("UIError")
				end
			end })
			go.AnchorPoint = Vector2.new(0.5, 0)
			go.Position = UDim2.new(0.5, 0, 0, 176)
			go.Parent = body
			Kit.SetEnabled(go, #bench >= 2)
			local secrets, found = 0, 0
			for _, recipe in Recipes.List do
				if recipe.Unlock.Secret then
					secrets += 1
					if profile and profile.Recipes[recipe.Id] then
						found += 1
					end
				end
			end
			local tally = Kit.Label("Secret recipes found: " .. found .. " / " .. secrets .. "   ·   Crafting level " .. (if profile then Stats.SkillLevel(profile, "Crafting") else 1), { Size = Theme.Sizes.Small, Align = "Center", Color = "SubText" })
			tally.Position = UDim2.fromOffset(0, 232)
			tally.Parent = body
		end

		render = function()
			Kit.Clear(body)
			if mode == "Recipes" then
				renderRecipes()
			else
				renderExperiment()
			end
			Kit.RepaintGradients(body)
		end

		tabs.Select("Recipes")
		return { Refresh = render }
	end,
}

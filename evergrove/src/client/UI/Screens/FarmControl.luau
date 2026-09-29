-- Farm automation control: your devices and silo at a glance, shipping-dock
-- auto-sell rules, drone replant choices, machine priorities for the
-- logistics network, and what each farmbot plants.
-- Args: { Tab = device kind that opened it, Uid = device uid }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local Format = require(Shared.Lib.Format)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Picker = require(UI.Picker)
local AnimalInfo = require(UI.AnimalInfo)
local C = require(UI.Parent.Controllers)

local SELL_PRESETS = { "#Crop", "#Fruit", "#Vegetable", "#Flower", "#Artisan", "#Egg", "#Fish", "#Mineral" }
local TAB_FOR_KIND = {
	Dock = "Sell",
	Controller = "Overview",
	Farmbot = "Bots",
	Drones = "Replant",
	Harvester = "Replant",
	Logistics = "Priority",
}

-- Placed devices on your farm: { Uid, Def }.
local function devices(): { any }
	local out = {}
	local lot = AnimalInfo.MyLot()
	local placed = lot and lot:FindFirstChild("Placed")
	for _, model in (placed and placed:GetChildren()) or {} do
		local def = Registry.Placeables[model:GetAttribute("Placeable") or ""]
		if def and def.Function then
			table.insert(out, { Uid = model.Name, Def = def })
		end
	end
	return out
end

local function setRules(rules: any)
	local ok, err = Net.Request("AutomationRules", rules)
	if not ok then
		C.Notify.Toast(tostring(err), "Warning")
	end
	return ok
end

return {
	Id = "FarmControl",
	Title = "Farm Automation",
	Icon = "🖥️",
	Size = Vector2.new(940, 620),
	Watch = { "Farm", "Silo" },
	Build = function(win, ctx)
		local args = ctx.Args or {}
		local content = win.Content :: Frame
		local current = TAB_FOR_KIND[args.Tab or ""] or "Overview"
		local render: () -> ()
		local tabs = Kit.Tabs({
			{ Id = "Overview", Label = "Overview", Icon = "🖥️" },
			{ Id = "Sell", Label = "Auto-sell", Icon = "🚢" },
			{ Id = "Replant", Label = "Replanting", Icon = "🛸" },
			{ Id = "Priority", Label = "Machines", Icon = "⚙️" },
			{ Id = "Bots", Label = "Farmbots", Icon = "🤖" },
		}, function(id)
			current = id
			render()
		end)
		tabs.Frame.Parent = content
		local body = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, -46),
			Position = UDim2.fromOffset(0, 46),
			Parent = content,
		})

		local function rules(): any
			return C.State.Get("Farm", "Rules") or { Sell = {}, Replant = {}, Priority = {}, Bots = {} }
		end

		local function renderOverview()
			local profile = C.State.Data()
			local list = Kit.Scroll({ Size = UDim2.fromScale(1, 1) })
			list.Parent = body
			Kit.List(list, "Y", 6)
			local siloTotal = 0
			for _, stack in (profile and profile.Silo and profile.Silo.Items) or {} do
				siloTotal += stack.N
			end
			local capacity = 0
			local counts: { [string]: { Def: any, N: number } } = {}
			for _, device in devices() do
				local fn = device.Def.Function
				if fn.Kind == "Silo" then
					capacity += fn.Capacity
				end
				if fn.Kind ~= "Machine" and fn.Kind ~= "Storage" and fn.Kind ~= "Station" and fn.Kind ~= "Animal" then
					local entry = counts[device.Def.Id] or { Def = device.Def, N = 0 }
					entry.N += 1
					counts[device.Def.Id] = entry
				end
			end
			local silo = Kit.Card(70)
			silo.Parent = list
			Kit.Heading("🛢️ Silo network", 16).Parent = silo
			local bar = Kit.Progress({
				Size = UDim2.new(1, -140, 0, 16),
				Color = if capacity > 0 and siloTotal / capacity > 0.9 then "Warn" else "Good",
			})
			bar.Frame.Position = UDim2.fromOffset(0, 30)
			bar.Frame.Parent = silo
			bar.Set(
				if capacity > 0 then siloTotal / capacity else 0,
				Format.Commas(siloTotal) .. " / " .. Format.Commas(capacity),
				false
			)
			local open = Kit.Button("Open silo", {
				Style = "Secondary",
				Size = UDim2.fromOffset(120, 32),
				TextSize = Theme.Sizes.Small,
				OnClick = function()
					C.Windows.Open("Inventory", { Container = "silo" })
				end,
			})
			open.Position = UDim2.new(1, -120, 0, 22)
			open.Parent = silo
			local ids = {}
			for id in counts do
				table.insert(ids, id)
			end
			table.sort(ids)
			if #ids == 0 then
				Kit.Empty(
					"No automation yet. Sprinklers, silos, feeders, drones and more are sold at Sparks Engineering and Timberline Builders."
				).Parent =
					list
			end
			for i, id in ids do
				local entry = counts[id]
				local card = Kit.Card(56)
				card.LayoutOrder = i + 1
				card.Parent = list
				local label = Kit.Label(
					entry.Def.Icon .. " " .. entry.Def.Name .. "  ×" .. entry.N,
					{ Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold }
				)
				label.Parent = card
				local desc =
					Kit.Label(entry.Def.Description or "", { Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true })
				desc.Position = UDim2.fromOffset(0, 20)
				desc.Parent = card
			end
		end

		local function renderSell()
			local current2 = rules()
			local intro = Kit.Label(
				"Every morning the Shipping Dock sells silo items that match these rules at market price (minus 5%). Tags like #Fruit match whole groups.",
				{ Size = Theme.Sizes.Small, Color = "SubText", Wrap = true }
			)
			intro.Parent = body
			local chips = Kit.new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 34),
				Position = UDim2.fromOffset(0, 48),
				Parent = body,
			})
			Kit.List(chips, "X", 6)
			for i, spec in SELL_PRESETS do
				local on = table.find(current2.Sell or {}, spec) ~= nil
				local b = Kit.Button((if on then "✔ " else "+ ") .. Registry.SpecName(spec), {
					Style = if on then "Good" else "Secondary",
					Size = UDim2.fromOffset(0, 32),
					TextSize = Theme.Sizes.Tiny,
					LayoutOrder = i,
					OnClick = function()
						local list = table.clone(current2.Sell or {})
						local index = table.find(list, spec)
						if index then
							table.remove(list, index)
						else
							table.insert(list, spec)
						end
						setRules({ Sell = list })
					end,
				})
				b.AutomaticSize = Enum.AutomaticSize.X
				Kit.Padding(b, 0, 10)
				b.Parent = chips
			end
			local list = Kit.Scroll({ Size = UDim2.new(1, 0, 1, -140), Position = UDim2.fromOffset(0, 90) })
			list.Parent = body
			Kit.List(list, "Y", 4)
			for i, spec in current2.Sell or {} do
				local row = Kit.Card(40)
				row.LayoutOrder = i
				row.Parent = list
				local def = Registry.Items[spec]
				local label = Kit.Label(
					(if def then def.Icon .. " " else "🏷️ ") .. Registry.SpecName(spec),
					{ Size = Theme.Sizes.Small }
				)
				label.Size = UDim2.new(1, -60, 1, 0)
				label.Parent = row
				local remove = Kit.Button("✕", {
					Style = "Ghost",
					Size = UDim2.fromOffset(32, 28),
					OnClick = function()
						local l = table.clone(current2.Sell)
						table.remove(l, i)
						setRules({ Sell = l })
					end,
				})
				remove.Position = UDim2.new(1, -34, 0, 0)
				remove.Parent = row
			end
			if #(current2.Sell or {}) == 0 then
				Kit.Empty("No rules — the dock sells nothing.").Parent = list
			end
			local add = Kit.Button("+ Add an item from your bag", {
				Style = "Primary",
				Size = UDim2.fromOffset(260, 38),
				TextSize = Theme.Sizes.Small,
				OnClick = function()
					Picker.Open({
						Title = "Auto-sell which item?",
						Filter = function(_, def)
							return not def.NoSell and def.Value > 0
						end,
						OnPick = function(_, stack)
							local l = table.clone(current2.Sell or {})
							if not table.find(l, stack.Id) then
								table.insert(l, stack.Id)
							end
							setRules({ Sell = l })
						end,
					})
				end,
			})
			add.Position = UDim2.new(0, 0, 1, -40)
			add.Parent = body
		end

		local function renderReplant()
			local current2 = rules()
			local intro = Kit.Label(
				"Harvest drones replant from silo seeds after harvesting. Untick crops you want to rotate out.",
				{ Size = Theme.Sizes.Small, Color = "SubText", Wrap = true }
			)
			intro.Parent = body
			local list = Kit.Scroll({ Size = UDim2.new(1, 0, 1, -40), Position = UDim2.fromOffset(0, 40) })
			list.Parent = body
			local layout = Kit.new("UIGridLayout", {
				CellSize = UDim2.new(0.25, -6, 0, 36),
				CellPadding = UDim2.fromOffset(6, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = list,
			})
			layout.FillDirectionMaxCells = 4
			local crops = {}
			for id, crop in Registry.Crops do
				if Registry.Items["seed_" .. id] then
					table.insert(crops, crop)
				end
			end
			table.sort(crops, function(a, b)
				return a.Name < b.Name
			end)
			for i, crop in crops do
				local on = (current2.Replant or {})[crop.Id] ~= false
				local b = Kit.Button((if on then "☑ " else "☐ ") .. crop.Icon .. " " .. crop.Name, {
					Style = if on then "Secondary" else "Ghost",
					TextSize = Theme.Sizes.Tiny,
					LayoutOrder = i,
					OnClick = function()
						local map = table.clone(current2.Replant or {})
						if on then
							map[crop.Id] = false
						else
							map[crop.Id] = nil
						end
						setRules({ Replant = map })
					end,
				})
				b.Parent = list
			end
		end

		local function renderPriority()
			local current2 = rules()
			local intro = Kit.Label(
				"With a Logistics Hub, machines set to Auto pull ingredients from your silos. Higher priority machines get fed first when ingredients are scarce.",
				{ Size = Theme.Sizes.Small, Color = "SubText", Wrap = true }
			)
			intro.Parent = body
			local list = Kit.Scroll({ Size = UDim2.new(1, 0, 1, -48), Position = UDim2.fromOffset(0, 48) })
			list.Parent = body
			Kit.List(list, "Y", 4)
			local n = 0
			for _, device in devices() do
				if device.Def.Function.Kind == "Machine" then
					n += 1
					local priority = (current2.Priority or {})[device.Uid] or 0
					local row = Kit.Card(44)
					row.LayoutOrder = n
					row.Parent = list
					local label = Kit.Label(
						device.Def.Icon .. " " .. device.Def.Name .. "   priority " .. priority,
						{ Size = Theme.Sizes.Small }
					)
					label.Size = UDim2.new(1, -200, 1, 0)
					label.Parent = row
					for j, delta in { -1, 1 } do
						local b = Kit.Button(if delta < 0 then "−" else "+", {
							Style = "Secondary",
							Size = UDim2.fromOffset(40, 30),
							OnClick = function()
								local map = table.clone(current2.Priority or {})
								map[device.Uid] = math.clamp(priority + delta, -10, 10)
								setRules({ Priority = map })
							end,
						})
						b.Position = UDim2.new(1, -140 + (j - 1) * 46, 0, 2)
						b.Parent = row
					end
					local open = Kit.Button("Open", {
						Style = "Ghost",
						Size = UDim2.fromOffset(46, 30),
						TextSize = Theme.Sizes.Tiny,
						OnClick = function()
							C.Windows.Open("Machine", { Uid = device.Uid })
						end,
					})
					open.Position = UDim2.new(1, -48, 0, 2)
					open.Parent = row
				end
			end
			if n == 0 then
				Kit.Empty("No machines on your farm yet.").Parent = list
			end
		end

		local function renderBots()
			local current2 = rules()
			local list = Kit.Scroll({ Size = UDim2.fromScale(1, 1) })
			list.Parent = body
			Kit.List(list, "Y", 6)
			local n = 0
			for _, device in devices() do
				if device.Def.Function.Kind == "Farmbot" then
					n += 1
					local cropId = (current2.Bots or {})[device.Uid]
					local crop = cropId and Registry.Crops[cropId]
					local row = Kit.Card(48)
					row.LayoutOrder = n
					row.Parent = list
					local label = Kit.Label(
						"🤖 Farmbot "
							.. n
							.. " — plants "
							.. (if crop then crop.Icon .. " " .. crop.Name else "nothing (tills & waters only)"),
						{ Size = Theme.Sizes.Small }
					)
					label.Size = UDim2.new(1, -150, 1, 0)
					label.Parent = row
					local choose = Kit.Button("Choose crop", {
						Style = "Secondary",
						Size = UDim2.fromOffset(140, 34),
						TextSize = Theme.Sizes.Small,
						OnClick = function()
							Picker.Open({
								Title = "What should this farmbot plant?",
								Filter = function(_, def)
									return def.Plants ~= nil
								end,
								Empty = "Farmbots plant seeds from your silo — pick a seed you carry to choose its crop.",
								OnPick = function(_, stack)
									local def = Registry.Items[stack.Id]
									setRules({ Bots = { [device.Uid] = def.Plants } })
								end,
							})
						end,
					})
					choose.Position = UDim2.new(1, -140, 0, 2)
					choose.Parent = row
				end
			end
			if n == 0 then
				Kit.Empty("No farmbots yet (Farming level 20, from Sparks Engineering).").Parent = list
			end
		end

		render = function()
			Kit.Clear(body)
			if current == "Overview" then
				renderOverview()
			elseif current == "Sell" then
				renderSell()
			elseif current == "Replant" then
				renderReplant()
			elseif current == "Priority" then
				renderPriority()
			else
				renderBots()
			end
			Kit.RepaintGradients(body)
		end
		tabs.Select(current)
		return { Refresh = render }
	end,
}

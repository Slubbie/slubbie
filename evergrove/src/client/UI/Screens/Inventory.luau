-- Backpack and storage.
--
-- Left: your backpack (slots 1-9 are the hotbar). Right: the open container
-- (a chest, house storage or the silo) or, with none open, details for the
-- selected item with its actions.
--
--   drag & drop            move / swap / merge (drop half with right-drag)
--   shift-click            quick-move to the other side
--   right-click            split a stack
--   double-click           use (eat, open, read...)
--   Move button (touch / gamepad): pick up, then choose the destination slot
--
-- Search and category chips dim everything that doesn't match (slots never
-- move around under you). Sorting keeps the hotbar as it is.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local ItemUtil = require(Shared.Lib.ItemUtil)
local Format = require(Shared.Lib.Format)
local Land = require(Shared.Config.Land)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local C = require(UI.Parent.Controllers)

local HOTBAR = 9

local FILTERS = {
	{ Id = "All", Icon = "✨", Cats = nil },
	{ Id = "Tools", Icon = "🛠️", Cats = { Tool = true } },
	{ Id = "Seeds", Icon = "🌱", Cats = { Seed = true } },
	{ Id = "Produce", Icon = "🥕", Cats = { Crop = true, Forage = true, AnimalProduct = true } },
	{ Id = "Fish & bugs", Icon = "🐟", Cats = { Fish = true, Bug = true, Bait = true } },
	{ Id = "Goods", Icon = "🍯", Cats = { Artisan = true, Food = true, Potion = true, Ingredient = true } },
	{
		Id = "Materials",
		Icon = "🪵",
		Cats = { Material = true, Mineral = true, Gem = true, Fertilizer = true, Supply = true, Feed = true },
	},
	{
		Id = "Special",
		Icon = "🏺",
		Cats = { Artifact = true, Treasure = true, Placeable = true, Book = true, Special = true },
	},
}

local function request(action: string, ...: any): (boolean, any)
	local ok, result = Net.Request(action, ...)
	if not ok and result then
		C.Notify.Toast(tostring(result), "Warning")
		C.Audio.PlayUI("UIError")
	end
	return ok, result
end

-- Container info from the replicated profile.
local function containerData(name: string): (any?, number)
	local profile = C.State.Data()
	if not profile then
		return nil, 0
	end
	if name == "inv" then
		return profile.Inventory, profile.Inventory.Size
	elseif name == "home" then
		local house = Land.House[profile.Farm and profile.Farm.House or 1]
		local data = profile.Storage and profile.Storage.home
		return data, (if house then house.Storage else 0)
	end
	local uid = string.match(name, "^chest:(.+)$")
	if uid then
		local data = profile.Storage and profile.Storage[uid]
		local size = data and data.Size
		if not size then
			-- Not opened before: read the size from the placed model.
			local farms = workspace:FindFirstChild("Farms")
			local model = farms and farms:FindFirstChild(uid, true)
			local def = model and Registry.Placeables[model:GetAttribute("Placeable") or ""]
			size = def and def.Function and def.Function.Slots or 0
		end
		return data, size or 0
	end
	return nil, 0
end

local function containerTitle(name: string): string
	if name == "home" then
		return "🏠 House storage"
	elseif name == "silo" then
		return "🛢️ Silo"
	end
	local uid = string.match(name, "^chest:(.+)$")
	if uid then
		local farms = workspace:FindFirstChild("Farms")
		local model = farms and farms:FindFirstChild(uid, true)
		local def = model and Registry.Placeables[model:GetAttribute("Placeable") or ""]
		return (if def then def.Icon .. " " .. def.Name else "📦 Chest")
	end
	return name
end

return {
	Id = "Inventory",
	Title = "Backpack",
	Icon = "🎒",
	Size = Vector2.new(1000, 620),
	Watch = { "Inventory", "Storage", "Silo", "Hotbar", "Tools", "Coins" },
	Build = function(win, ctx)
		local args = ctx.Args or {}
		local other: string? = args.Container
		local content = win.Content :: Frame
		local filterIndex = 1
		local query = ""
		local selectedRef: string? = nil
		local carry: { Ref: string, Count: number? }? = nil
		local slotWidgets: { [string]: any } = {} -- ref → Kit.ItemSlot
		local refByButton: { [GuiObject]: string } = {}
		local lastClick: { Ref: string, At: number } = { Ref = "", At = 0 }
		local drag: { Ref: string, Half: boolean, Start: Vector2, Ghost: TextLabel?, Active: boolean }? = nil
		local connections: { RBXScriptConnection } = {}

		-- Layout -------------------------------------------------------------------------------------------------
		local left =
			Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.56, -8, 1, 0), Parent = content })
		local right = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(0.44, -8, 1, 0),
			Position = UDim2.new(0.56, 8, 0, 0),
			Parent = content,
		})

		local toolbar = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), Parent = left })
		local search = Kit.TextBox("🔍 Search your bag…", { Size = UDim2.new(1, -170, 1, 0) })
		search.Parent = toolbar
		local sortButton = Kit.Button("Sort", {
			Style = "Secondary",
			Icon = "↕️",
			Size = UDim2.fromOffset(80, 34),
			TextSize = Theme.Sizes.Small,
			OnClick = function()
				request("InvSort", "inv")
			end,
		})
		sortButton.Position = UDim2.new(1, -164, 0, 0)
		sortButton.Parent = toolbar
		Kit.AttachTooltip(sortButton, function()
			return { { Text = "Sort by category, rarity and name. The hotbar and locked items stay put." } }
		end)
		local valueLabel = Kit.Label("", { Size = Theme.Sizes.Tiny, Color = "SubText", Align = "Right" })
		valueLabel.Size = UDim2.new(0, 78, 1, 0)
		valueLabel.Position = UDim2.new(1, -78, 0, 0)
		valueLabel.Parent = toolbar

		local chips = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 30),
			Position = UDim2.fromOffset(0, 40),
			Parent = left,
		})
		Kit.List(chips, "X", 4)
		local chipButtons = {}
		for i, filter in FILTERS do
			local chip = Kit.Button(
				filter.Icon,
				{ Style = "Secondary", Size = UDim2.fromOffset(40, 30), TextSize = 15, LayoutOrder = i }
			)
			chip.Parent = chips
			chipButtons[i] = chip
			Kit.AttachTooltip(chip, function()
				return { { Text = filter.Id } }
			end)
		end

		local bagScroll = Kit.Scroll({ Size = UDim2.new(1, 0, 1, -104), Position = UDim2.fromOffset(0, 76) })
		bagScroll.Parent = left
		Kit.List(bagScroll, "Y", 6)
		local sizeLabel = Kit.Label("", { Size = Theme.Sizes.Tiny, Color = "SubText" })
		sizeLabel.Position = UDim2.new(0, 0, 1, -22)
		sizeLabel.Size = UDim2.new(1, 0, 0, 20)
		sizeLabel.Parent = left

		local carryBanner =
			Kit.Label("", { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold, Color = "Accent", Align = "Center" })
		carryBanner.Size = UDim2.new(1, 0, 0, 22)
		carryBanner.Position = UDim2.new(0, 0, 0, -26)
		carryBanner.Visible = false
		carryBanner.Parent = content

		-- Helpers ------------------------------------------------------------------------------------------------
		local function matches(stack: any): boolean
			local def = Registry.Items[stack.Id]
			if not def then
				return false
			end
			local cats = FILTERS[filterIndex].Cats
			if cats and not cats[def.Category] then
				return false
			end
			if
				query ~= ""
				and not string.find(string.lower(ItemUtil.DisplayName(stack)), query, 1, true)
				and not string.find(string.lower(def.Category), query, 1, true)
			then
				return false
			end
			return true
		end

		local function stackAt(ref: string): any?
			local containerName, slot = string.match(ref, "^(.+):(%d+)$")
			if not containerName then
				return nil
			end
			local data = containerData(containerName)
			return data and data.Slots and data.Slots[slot]
		end

		local function firstEmpty(containerName: string, from: number?, to: number?): number?
			local data, size = containerData(containerName)
			local slots = (data and data.Slots) or {}
			for i = from or 1, math.min(to or size, size) do
				if not slots[tostring(i)] then
					return i
				end
			end
			return nil
		end

		local refresh: () -> ()

		local function setCarry(value: { Ref: string, Count: number? }?)
			carry = value
			if value then
				local stack = stackAt(value.Ref)
				carryBanner.Text = "Moving "
					.. (if stack then ItemUtil.DisplayName(stack) else "item")
					.. (if value.Count then " ×" .. value.Count else "")
					.. " — choose a slot (B / Esc to cancel)"
				carryBanner.Visible = true
			else
				carryBanner.Visible = false
			end
		end

		local function moveTo(from: string, to: string, count: number?)
			if from == to then
				return
			end
			local ok = request("InvMove", from, to, count)
			if ok then
				C.Audio.PlayUI("ItemPickup")
			end
		end

		local function quickMove(ref: string)
			local containerName, slot = string.match(ref, "^(.+):(%d+)$")
			if not containerName then
				return
			end
			if other and other ~= "silo" then
				request("InvQuick", ref, if containerName == "inv" then other else "inv")
				return
			end
			-- No container open: hop between hotbar and backpack.
			local n = tonumber(slot) :: number
			local target = if n <= HOTBAR then firstEmpty("inv", HOTBAR + 1) else firstEmpty("inv", 1, HOTBAR)
			if target then
				moveTo(ref, "inv:" .. target)
			else
				C.Notify.Toast(if n <= HOTBAR then "Your backpack is full" else "Your hotbar is full", "Info")
			end
		end

		local function split(ref: string)
			local stack = stackAt(ref)
			if not stack or stack.N < 2 then
				return
			end
			local containerName = string.match(ref, "^(.+):%d+$") :: string
			Kit.AskNumber("Split " .. ItemUtil.DisplayName(stack), stack.N - 1, math.floor(stack.N / 2), function(n)
				if not n then
					return
				end
				local target = firstEmpty(containerName, if containerName == "inv" then HOTBAR + 1 else 1)
					or firstEmpty(containerName)
				if not target then
					C.Notify.Toast("No empty slot to split into", "Info")
					return
				end
				moveTo(ref, containerName .. ":" .. target, n)
			end)
		end

		local function useItem(ref: string)
			local stack = stackAt(ref)
			local def = stack and Registry.Items[stack.Id]
			if not def then
				return
			end
			if def.Placeable then
				ctx.Close()
				C.Build.Enter(stack.Id)
				return
			end
			local ok, result = request("InvUse", ref)
			if ok and result == "Build" then
				ctx.Close()
				C.Build.Enter(stack.Id)
			elseif ok then
				C.Animation.Play("Eat")
			end
		end

		-- Details panel ------------------------------------------------------------------------------------------
		local function renderDetails(frame: Frame)
			Kit.Clear(frame)
			local stack = selectedRef and stackAt(selectedRef)
			if not stack or not selectedRef then
				local tip = Kit.Label(
					"Select an item to see what it's worth, what it's used for, and what you can do with it.\n\nDrag to move · Shift-click to quick-move · Right-click to split · Double-click to use.",
					{ Wrap = true, Color = "SubText", Size = Theme.Sizes.Small }
				)
				tip.Parent = frame
				return
			end
			local ref = selectedRef :: string
			local def = Registry.Items[stack.Id]
			local header =
				Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 84), Parent = frame })
			local big = Kit.ItemSlot(80)
			big.Button.Active = false
			big.Set(stack)
			big.Button.Parent = header
			local name = Kit.Heading(ItemUtil.DisplayName(stack), 20)
			name.TextColor3 = Theme.RarityColor(ItemUtil.Rarity(stack))
			name.Position = UDim2.fromOffset(92, 4)
			name.Size = UDim2.new(1, -92, 0, 26)
			name.TextWrapped = true
			name.Parent = header
			local sub = Kit.Label(
				Theme.Rarity(ItemUtil.Rarity(stack)).Glyph
					.. " "
					.. ItemUtil.Rarity(stack)
					.. " · "
					.. def.Category
					.. (if stack.N > 1 then " · ×" .. stack.N else ""),
				{ Size = Theme.Sizes.Small, Color = "SubText" }
			)
			sub.Position = UDim2.fromOffset(92, 34)
			sub.Size = UDim2.new(1, -92, 0, 20)
			sub.Parent = header
			if ItemUtil.Sellable(stack) then
				local worth = Kit.Label(
					"Worth about " .. Kit.Money(ItemUtil.UnitValue(stack)) .. " each",
					{ Size = Theme.Sizes.Small, Color = "Accent" }
				)
				worth.Position = UDim2.fromOffset(92, 56)
				worth.Size = UDim2.new(1, -92, 0, 20)
				worth.Parent = header
			end
			local info = Kit.Scroll({ Size = UDim2.new(1, 0, 1, -190), Position = UDim2.fromOffset(0, 90) })
			info.Parent = frame
			Kit.List(info, "Y", 3)
			local lines = Kit.ItemTooltip(stack)
			for i = 3, #lines do
				local line = lines[i]
				local label = Kit.Label(line.Text, {
					Size = line.Size or Theme.Sizes.Small,
					Wrap = true,
					Rich = true,
					Font = if line.Bold then Theme.Fonts.Bold else nil,
				})
				if typeof(line.Color) == "Color3" then
					label.TextColor3 = line.Color :: Color3
				elseif type(line.Color) == "string" then
					Kit.Paint(label, "TextColor3", line.Color :: string)
				end
				label.LayoutOrder = i
				label.Parent = info
			end
			if def.Tool then
				local family = Registry.ToolFamilies[def.Tool]
				local tier = C.State.Get("Tools", def.Tool) or 1
				local tierDef = family and family.Tiers[tier]
				if tierDef then
					local label = Kit.Label(
						"Tier "
							.. tier
							.. " · "
							.. tierDef.Name
							.. " · area up to "
							.. tierDef.MaxArea
							.. "×"
							.. tierDef.MaxArea
							.. (if tierDef.Ability then "\n✨ " .. tierDef.Ability else ""),
						{ Size = Theme.Sizes.Small, Wrap = true, Color = "Info" }
					)
					label.LayoutOrder = 100
					label.Parent = info
				end
			end
			-- Actions
			local actions = Kit.new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 92),
				Position = UDim2.new(0, 0, 1, -92),
				Parent = frame,
			})
			local grid = Kit.new("UIGridLayout", {
				CellSize = UDim2.new(0.333, -6, 0, 40),
				CellPadding = UDim2.fromOffset(6, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = actions,
			})
			grid.FillDirectionMaxCells = 3
			local order = 0
			local function action(text: string, style: string, fn: () -> ())
				order += 1
				Kit.Button(text, { Style = style, TextSize = Theme.Sizes.Small, LayoutOrder = order, OnClick = fn }).Parent =
					actions
			end
			if
				def.Use
				and def.Use ~= "Plant"
				and def.Use ~= "Fertilize"
				and def.Use ~= "Spray"
				and def.Use ~= "Amend"
			then
				local verb = ({
					Eat = "Eat",
					Drink = "Drink",
					Read = "Read",
					Open = "Open",
					Warp = "Warp",
					Totem = "Use",
					Place = "Place",
				})[def.Use] or "Use"
				action(verb, "Primary", function()
					useItem(ref)
				end)
			elseif def.Placeable then
				action("Place", "Primary", function()
					useItem(ref)
				end)
			end
			if def.Category == "Bait" then
				action("Use as bait", "Secondary", function()
					C.Fishing.SetBait(ref)
					C.Notify.Toast("🪱 " .. def.Name .. " will go on your hook", "Success")
				end)
			end
			local containerName, slot = string.match(ref, "^(.+):(%d+)$")
			if containerName == "inv" and tonumber(slot) :: number > HOTBAR then
				action("To hotbar", "Secondary", function()
					quickMove(ref)
				end)
			end
			action("Move", "Secondary", function()
				setCarry({ Ref = ref })
			end)
			if stack.N > 1 then
				action("Split", "Secondary", function()
					split(ref)
				end)
			end
			action(if stack.L then "🔓 Unlock" else "🔒 Lock", "Secondary", function()
				request("InvLock", ref)
			end)
			if not def.NoTrash then
				action("🗑️ Trash", "Danger", function()
					local function confirm(count: number)
						Kit.Confirm(
							"Throw away?",
							"Throw away " .. count .. " × " .. ItemUtil.DisplayName(stack) .. "? This can't be undone.",
							function(yes)
								if yes then
									request("InvTrash", ref, count)
									selectedRef = nil
									refresh()
								end
							end,
							"Trash",
							true
						)
					end
					if stack.N > 1 then
						Kit.AskNumber("How many to trash?", stack.N, stack.N, function(n)
							if n then
								confirm(n)
							end
						end)
					else
						confirm(1)
					end
				end)
			end
		end

		-- Slot interaction ------------------------------------------------------------------------------------------
		local function onSlotActivated(ref: string)
			if carry then
				local from = carry.Ref
				local count = carry.Count
				setCarry(nil)
				moveTo(from, ref, count)
				return
			end
			if
				UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			then
				quickMove(ref)
				return
			end
			local now = os.clock()
			if lastClick.Ref == ref and now - lastClick.At < 0.35 then
				useItem(ref)
				lastClick.At = 0
				return
			end
			lastClick = { Ref = ref, At = now }
			selectedRef = if stackAt(ref) then ref else nil
			C.Audio.PlayUI("UIClick")
			refresh()
		end

		local function makeSlot(ref: string, parent: Instance, order: number): any
			local slot = Kit.ItemSlot(54)
			slot.Button.LayoutOrder = order
			slot.Button.Parent = parent
			slotWidgets[ref] = slot
			refByButton[slot.Button] = ref
			slot.Button.Activated:Connect(function()
				if drag and drag.Active then
					return
				end
				onSlotActivated(ref)
			end)
			slot.Button.MouseButton2Click:Connect(function()
				split(ref)
			end)
			slot.Button.InputBegan:Connect(function(input)
				local isMouse = input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.MouseButton2
				if (isMouse or input.UserInputType == Enum.UserInputType.Touch) and stackAt(ref) then
					drag = {
						Ref = ref,
						Half = input.UserInputType == Enum.UserInputType.MouseButton2,
						Start = Vector2.new(input.Position.X, input.Position.Y),
						Ghost = nil,
						Active = false,
					}
				end
			end)
			return slot
		end

		-- Rendering -----------------------------------------------------------------------------------------------------
		local rightBody: Frame? = nil
		local function renderRight()
			Kit.Clear(right)
			if other == "silo" then
				local title = Kit.Heading("🛢️ Silo", 20)
				title.Parent = right
				local profile = C.State.Data()
				local items = (profile and profile.Silo and profile.Silo.Items) or {}
				local total = 0
				local entries = {}
				for key, stack in items do
					total += stack.N
					table.insert(entries, { Key = key, Stack = stack })
				end
				table.sort(entries, function(a, b)
					return ItemUtil.DisplayName(a.Stack) < ItemUtil.DisplayName(b.Stack)
				end)
				local sub = Kit.Label(
					Format.Commas(total) .. " items stored · automation fills and uses it",
					{ Size = Theme.Sizes.Tiny, Color = "SubText" }
				)
				sub.Position = UDim2.fromOffset(0, 30)
				sub.Parent = right
				local list = Kit.Scroll({ Size = UDim2.new(1, 0, 1, -56), Position = UDim2.fromOffset(0, 56) })
				list.Parent = right
				Kit.List(list, "Y", 4)
				if #entries == 0 then
					Kit.Empty("The silo is empty. Collectors, drones and auto-harvesters store their goods here.").Parent =
						list
				end
				for i, entry in entries do
					local row = Kit.Card(50)
					row.LayoutOrder = i
					row.Parent = list
					local slot = Kit.ItemSlot(36)
					slot.Button.Active = false
					slot.Set(entry.Stack)
					slot.Button.Parent = row
					local name = Kit.Label(
						ItemUtil.DisplayName(entry.Stack) .. "  ×" .. Format.Commas(entry.Stack.N),
						{ Size = Theme.Sizes.Small }
					)
					name.Position = UDim2.fromOffset(44, 6)
					name.Size = UDim2.new(1, -140, 0, 20)
					name.Parent = row
					local take = Kit.Button("Take", {
						Style = "Secondary",
						Size = UDim2.fromOffset(80, 30),
						TextSize = Theme.Sizes.Small,
						OnClick = function()
							request("InvMove", "silo:" .. entry.Key, "inv:0")
						end,
					})
					take.Position = UDim2.new(1, -84, 0, 2)
					take.Parent = row
				end
				rightBody = nil
				return
			end
			if other then
				local containerName = other :: string
				local data, size = containerData(containerName)
				local header =
					Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), Parent = right })
				local title = Kit.Heading(containerTitle(containerName), 20)
				title.Size = UDim2.new(1, -170, 1, 0)
				title.Parent = header
				local deposit = Kit.Button("Deposit matching", {
					Style = "Secondary",
					Size = UDim2.fromOffset(160, 32),
					TextSize = Theme.Sizes.Tiny,
					OnClick = function()
						local ok, moved = request("InvStackAll", "inv", containerName)
						if ok then
							C.Notify.Toast("Stored " .. tostring(moved or 0) .. " items", "Success")
						end
					end,
				})
				deposit.Position = UDim2.new(1, -160, 0, 0)
				deposit.Parent = header
				Kit.AttachTooltip(deposit, function()
					return {
						{
							Text = "Move everything in your backpack that this storage already holds (not the hotbar or locked items).",
						},
					}
				end)
				local toolbar2 = Kit.new("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 30),
					Position = UDim2.fromOffset(0, 40),
					Parent = right,
				})
				Kit.List(toolbar2, "X", 6)
				Kit.Button("Sort", {
					Style = "Secondary",
					Icon = "↕️",
					Size = UDim2.fromOffset(80, 30),
					TextSize = Theme.Sizes.Tiny,
					OnClick = function()
						request("InvSort", containerName)
					end,
				}).Parent =
					toolbar2
				Kit.Button("Take all", {
					Style = "Secondary",
					Size = UDim2.fromOffset(90, 30),
					TextSize = Theme.Sizes.Tiny,
					LayoutOrder = 1,
					OnClick = function()
						local slots = (data and data.Slots) or {}
						for key in slots do
							request("InvQuick", containerName .. ":" .. key, "inv")
						end
					end,
				}).Parent =
					toolbar2
				local used = 0
				for _ in (data and data.Slots) or {} do
					used += 1
				end
				local count =
					Kit.Label(used .. " / " .. size .. " slots", { Size = Theme.Sizes.Tiny, Color = "SubText" })
				count.Size = UDim2.fromOffset(100, 30)
				count.LayoutOrder = 2
				count.Parent = toolbar2
				local scroll = Kit.Scroll({ Size = UDim2.new(1, 0, 1, -78), Position = UDim2.fromOffset(0, 76) })
				scroll.Parent = right
				local gridFrame = Kit.new("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, -8, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Parent = scroll,
				})
				Kit.Grid(gridFrame, 54, 6)
				for i = 1, size do
					makeSlot(containerName .. ":" .. i, gridFrame, i)
				end
				rightBody = nil
				return
			end
			local details =
				Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = right })
			rightBody = details
		end

		local function renderBag()
			Kit.Clear(bagScroll)
			local profile = C.State.Data()
			local size = profile and profile.Inventory.Size or 0
			local hotLabel =
				Kit.Label("Hotbar", { Size = Theme.Sizes.Tiny, Color = "SubText", Font = Theme.Fonts.Bold })
			hotLabel.LayoutOrder = 1
			hotLabel.Parent = bagScroll
			local hot = Kit.new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -8, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = 2,
				Parent = bagScroll,
			})
			Kit.Grid(hot, 54, 6)
			for i = 1, math.min(HOTBAR, size) do
				local slot = makeSlot("inv:" .. i, hot, i)
				local key = Kit.new("TextLabel", {
					BackgroundTransparency = 1,
					Size = UDim2.fromOffset(14, 12),
					Position = UDim2.fromOffset(3, 40),
					Font = Theme.Fonts.Bold,
					TextSize = 10,
					Text = tostring(i),
					TextTransparency = 0.35,
					Parent = slot.Button,
				})
				Kit.Paint(key, "TextColor3", "SubText")
			end
			local packLabel =
				Kit.Label("Backpack", { Size = Theme.Sizes.Tiny, Color = "SubText", Font = Theme.Fonts.Bold })
			packLabel.LayoutOrder = 3
			packLabel.Parent = bagScroll
			local pack = Kit.new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -8, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = 4,
				Parent = bagScroll,
			})
			Kit.Grid(pack, 54, 6)
			for i = HOTBAR + 1, size do
				makeSlot("inv:" .. i, pack, i)
			end
		end

		local function updateSlots()
			local total = 0
			local used = 0
			for ref, slot in slotWidgets do
				local stack = stackAt(ref)
				slot.Set(stack)
				local dim = stack ~= nil and not matches(stack)
				slot.Button.BackgroundTransparency = if dim then 0.6 else 0
				local icon = slot.Button:FindFirstChild("Icon") :: TextLabel?
				if icon then
					icon.TextTransparency = if dim then 0.7 else 0
				end
				slot.SetSelected(ref == selectedRef)
				if stack and string.sub(ref, 1, 4) == "inv:" then
					used += 1
					if ItemUtil.Sellable(stack) then
						total += ItemUtil.UnitValue(stack) * stack.N
					end
				end
			end
			local profile = C.State.Data()
			valueLabel.Text = "≈ " .. Kit.Money(total)
			local size = profile and profile.Inventory.Size or 0
			sizeLabel.Text = used
				.. " / "
				.. size
				.. " slots used"
				.. (if size < 72 then " · bigger backpacks at Pip's General Store" else "")
			for i, chip in chipButtons do
				Kit.Paint(chip, "BackgroundColor3", if i == filterIndex then "HeaderA" else "PanelAlt")
			end
		end

		local builtFor = ""
		refresh = function()
			local profile = C.State.Data()
			local key = tostring(profile and profile.Inventory.Size) .. "|" .. tostring(other)
			local _, otherSize = containerData(other or "inv")
			key ..= "|" .. tostring(otherSize)
			if key ~= builtFor then
				builtFor = key
				table.clear(slotWidgets)
				table.clear(refByButton)
				renderBag()
				renderRight()
			elseif other == "silo" then
				renderRight()
			end
			if selectedRef and not stackAt(selectedRef) then
				selectedRef = nil
			end
			updateSlots()
			if rightBody then
				renderDetails(rightBody)
			end
			Kit.RepaintGradients(content)
		end

		for i, chip in chipButtons do
			chip.Activated:Connect(function()
				filterIndex = i
				updateSlots()
			end)
		end
		search:GetPropertyChangedSignal("Text"):Connect(function()
			query = string.lower(search.Text)
			updateSlots()
		end)

		-- Drag & drop ------------------------------------------------------------------------------------------------
		local function slotUnder(position: Vector2): string?
			local objects = C.UI.Root():FindFirstAncestorOfClass("PlayerGui")
			if not objects then
				return nil
			end
			for _, gui in (objects :: PlayerGui):GetGuiObjectsAtPosition(position.X, position.Y) do
				local ref = refByButton[gui]
				if ref then
					return ref
				end
				local parent = gui.Parent
				if parent and parent:IsA("GuiObject") and refByButton[parent] then
					return refByButton[parent]
				end
			end
			return nil
		end

		table.insert(
			connections,
			UserInputService.InputChanged:Connect(function(input)
				local d = drag
				if not d then
					return
				end
				if
					input.UserInputType ~= Enum.UserInputType.MouseMovement
					and input.UserInputType ~= Enum.UserInputType.Touch
				then
					return
				end
				local position = Vector2.new(input.Position.X, input.Position.Y)
				if not d.Active and (position - d.Start).Magnitude > 8 then
					d.Active = true
					local stack = stackAt(d.Ref)
					local ghost = Kit.new("TextLabel", {
						BackgroundTransparency = 0.3,
						Size = UDim2.fromOffset(50, 50),
						AnchorPoint = Vector2.new(0.5, 0.5),
						Text = if stack then Kit.ItemIcon(stack.Id) else "",
						TextScaled = true,
						Font = Theme.Fonts.Body,
						ZIndex = 90,
						Parent = C.UI.Layer("Modal"),
					})
					Kit.Paint(ghost, "BackgroundColor3", "SlotHover")
					Kit.Corner(ghost, 10)
					d.Ghost = ghost
					Kit.HideTooltip()
				end
				if d.Active and d.Ghost then
					-- Input positions are already relative to the area below the top bar.
					local scale = C.UI.Scale or 1
					d.Ghost.Position = UDim2.fromOffset(position.X / scale, position.Y / scale)
				end
			end)
		)
		table.insert(
			connections,
			UserInputService.InputEnded:Connect(function(input)
				local d = drag
				if not d then
					return
				end
				if
					input.UserInputType ~= Enum.UserInputType.MouseButton1
					and input.UserInputType ~= Enum.UserInputType.MouseButton2
					and input.UserInputType ~= Enum.UserInputType.Touch
				then
					return
				end
				drag = nil
				if d.Ghost then
					d.Ghost:Destroy()
				end
				if not d.Active then
					return
				end
				local target = slotUnder(Vector2.new(input.Position.X, input.Position.Y))
				if target and target ~= d.Ref then
					local count = nil
					if d.Half then
						local stack = stackAt(d.Ref)
						count = if stack then math.max(1, math.floor(stack.N / 2)) else nil
					end
					moveTo(d.Ref, target, count)
				end
				-- Swallow the click that ends a drag.
				task.defer(function()
					if drag == nil then
						lastClick.At = 0
					end
				end)
			end)
		)
		table.insert(
			connections,
			UserInputService.InputBegan:Connect(function(input)
				if carry and (input.KeyCode == Enum.KeyCode.ButtonB or input.KeyCode == Enum.KeyCode.Escape) then
					setCarry(nil)
				end
			end)
		)
		-- Keep the drag ghost responsive between input events.
		table.insert(
			connections,
			RunService.RenderStepped:Connect(function()
				if drag and drag.Active and drag.Ghost and UserInputService.MouseEnabled then
					local mouse = UserInputService:GetMouseLocation()
					local scale = C.UI.Scale or 1
					local inset = GuiService:GetGuiInset()
					drag.Ghost.Position = UDim2.fromOffset(mouse.X / scale, (mouse.Y - inset.Y) / scale)
				end
			end)
		)

		refresh()
		if other and other ~= "silo" then
			win.Title.Text = "🎒  Backpack  ⇄  " .. containerTitle(other)
		end
		return {
			Refresh = refresh,
			Destroy = function()
				for _, c in connections do
					c:Disconnect()
				end
				if drag and drag.Ghost then
					drag.Ghost:Destroy()
				end
			end,
		}
	end,
}

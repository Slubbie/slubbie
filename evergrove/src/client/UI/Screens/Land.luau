-- Your farm's land: the 5×5 parcel map with each parcel's character, what
-- you own, the price of the next parcel, and farm naming. Also lists saved
-- decoration layouts.
-- Args: { Parcel = "row_col" } to pre-select a parcel (from its signpost).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local Stats = require(Shared.Lib.Stats)
local Land = require(Shared.Config.Land)
local Social = require(Shared.Config.Social)
local Placeables = require(Shared.Config.Placeables)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Describe = require(UI.Describe)
local C = require(UI.Parent.Controllers)

local SIZE = #Land.Layout

local function parcelPrice(profile: any): (number, { any })
	local owned = 0
	for _ in profile.Farm.Parcels do
		owned += 1
	end
	local price = math.floor(Land.ParcelBase * Land.ParcelGrowth ^ (owned - 1) / 100) * 100
	price = math.floor(price * (1 - Stats.ShopDiscount(profile, "carpenter")))
	return price, if owned >= 5 then Land.ParcelMats else {}
end

local function adjacent(profile: any, r: number, c: number): boolean
	for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		if profile.Farm.Parcels[(r + d[1]) .. "_" .. (c + d[2])] then
			return true
		end
	end
	return false
end

return {
	Id = "Land",
	Title = "Your Land",
	Icon = "🗺️",
	Size = Vector2.new(920, 620),
	Watch = { "Farm", "Coins", "Inventory" },
	Build = function(win, ctx)
		local content = win.Content :: Frame
		local selected: string? = ctx.Args and ctx.Args.Parcel
		local mode = "Land"
		local layouts: any = nil
		local render: () -> ()
		local tabs = Kit.Tabs({ { Id = "Land", Label = "Parcels", Icon = "🗺️" }, { Id = "Layouts", Label = "Layouts", Icon = "📐" } }, function(id)
			mode = id
			render()
			if id == "Layouts" and not layouts then
				task.spawn(function()
					local ok, result = Net.Request("LayoutList")
					if ok then
						layouts = result
						render()
					end
				end)
			end
		end)
		tabs.Frame.Parent = content
		local body = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -46), Position = UDim2.fromOffset(0, 46), Parent = content })

		local function renderLand()
			local profile = C.State.Data()
			if not profile then
				return
			end
			-- Map: row 1 is the front (next to the yard) → drawn at the bottom.
			local map = Kit.Panel({ Size = UDim2.fromOffset(420, 420), Color = "Inset" })
			map.Parent = body
			Kit.Padding(map, 8, 8)
			local cell = 404 / SIZE
			for r = 1, SIZE do
				for c = 1, SIZE do
					local key = r .. "_" .. c
					local ptype = Land.Types[Land.Layout[r][c]]
					local owned = profile.Farm.Parcels[key] == true
					local buyable = not owned and (not Land.RequireAdjacent or adjacent(profile, r, c))
					local b = Kit.new("TextButton", { AutoButtonColor = false, Text = "", BorderSizePixel = 0, Size = UDim2.fromOffset(cell - 4, cell - 4), Position = UDim2.fromOffset((c - 1) * cell, (SIZE - r) * cell), BackgroundColor3 = ptype.Color, Selectable = true, Parent = map })
					b.BackgroundTransparency = if owned then 0 elseif buyable then 0.45 else 0.75
					Kit.Corner(b, 8)
					if key == selected then
						Kit.new("UIStroke", { Thickness = 3, Color = Color3.fromRGB(255, 225, 90), Parent = b })
					end
					local icon = Kit.new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0.6), Text = ptype.Icon, TextScaled = true, Font = Theme.Fonts.Body, Parent = b })
					icon.TextTransparency = if owned then 0 else 0.4
					local tag = Kit.new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0.4, 0), Position = UDim2.fromScale(0, 0.6), Text = if owned then "✔ owned" elseif buyable then "for sale" else "🔒", TextScaled = true, Font = Theme.Fonts.Bold, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.4, Parent = b })
					Kit.new("UIPadding", { PaddingLeft = UDim.new(0.1, 0), PaddingRight = UDim.new(0.1, 0), PaddingBottom = UDim.new(0.08, 0), Parent = tag })
					b.Activated:Connect(function()
						selected = key
						Kit.PlaySound("UIClick")
						render()
					end)
				end
			end
			local front = Kit.Label("▼ farmhouse & yard ▼", { Size = Theme.Sizes.Tiny, Color = "SubText", Align = "Center" })
			front.Position = UDim2.fromOffset(0, 424)
			front.Size = UDim2.fromOffset(420, 16)
			front.Parent = body
			-- Details
			local right = Kit.Panel({ Size = UDim2.new(1, -432, 1, 0), Position = UDim2.fromOffset(432, 0), Color = "PanelAlt" })
			right.Parent = body
			Kit.Padding(right, 12, 14)
			Kit.List(right, "Y", 8)
			local owned = 0
			for _ in profile.Farm.Parcels do
				owned += 1
			end
			Kit.Heading("🏡 " .. (if profile.Farm.Name ~= "" then profile.Farm.Name else "Your farm") .. "  ·  " .. owned .. " / " .. SIZE * SIZE .. " parcels", 18).Parent = right
			if selected then
				local r, c = string.match(selected, "^(%d+)_(%d+)$")
				local row, col = tonumber(r) :: number, tonumber(c) :: number
				local ptype = Land.Types[Land.Layout[row][col]]
				local isOwned = profile.Farm.Parcels[selected] == true
				local head = Kit.Label(ptype.Icon .. " " .. ptype.Name, { Size = Theme.Sizes.Body, Font = Theme.Fonts.Bold })
				head.LayoutOrder = 1
				head.Parent = right
				local soil = {}
				for k, v in ptype.Soil do
					table.insert(soil, (if v > 0 then "+" else "") .. v .. " " .. (({ Health = "soil health", N = "nitrogen", P = "phosphorus", K = "potassium", Moisture = "moisture" }) :: any)[k])
				end
				local desc = Kit.Label(ptype.Description .. (if #soil > 0 then "\nSoil: " .. table.concat(soil, ", ") else "") .. (if ptype.Water then "\n💧 Has a pond (fish & refill water here)" else "") .. (if ptype.Clear then "\n🪓 Starts with trees/rocks to clear" else ""), { Size = Theme.Sizes.Small, Color = "SubText", Wrap = true })
				desc.LayoutOrder = 2
				desc.Parent = right
				if not isOwned then
					local price, mats = parcelPrice(profile)
					local parts = { Kit.Money(price) }
					local haveMats = true
					for _, mat in mats do
						local def = Registry.Items[mat.Id]
						local have = Describe.CountInBag(profile, mat.Id)
						haveMats = haveMats and have >= mat.N
						table.insert(parts, (if def then def.Icon .. " " .. def.Name else mat.Id) .. " " .. have .. "/" .. mat.N)
					end
					local priceLabel = Kit.Label("Price: " .. table.concat(parts, "  ·  "), { Size = Theme.Sizes.Small, Color = "Accent", Wrap = true })
					priceLabel.LayoutOrder = 3
					priceLabel.Parent = right
					local canReach = not Land.RequireAdjacent or adjacent(profile, row, col)
					local buy = Kit.Button("Buy this land", { Style = "Accent", Size = UDim2.new(1, 0, 0, 42), LayoutOrder = 4, OnClick = function()
						Kit.Confirm("Buy the " .. ptype.Name .. "?", "Your farm grows by one parcel. Prices rise with each parcel you own.", function(yes)
							if yes then
								local ok, err = Net.Request("LandBuy", selected)
								if ok then
									C.Audio.PlayUI("LevelUp")
								else
									C.Notify.Toast(tostring(err), "Warning")
								end
							end
						end, "Buy")
					end })
					buy.Parent = right
					Kit.SetEnabled(buy, canReach and haveMats and profile.Coins >= price)
					if not canReach then
						local note = Kit.Label("Buy a parcel next to land you own first.", { Size = Theme.Sizes.Tiny, Color = "Warn" })
						note.LayoutOrder = 5
						note.Parent = right
					end
				else
					local mine = Kit.Label("✔ This land is yours.", { Size = Theme.Sizes.Small, Color = "Good" })
					mine.LayoutOrder = 3
					mine.Parent = right
				end
			else
				local tip = Kit.Label("Select a parcel on the map. Each type has its own soil, and some come with ponds or woods to clear.", { Size = Theme.Sizes.Small, Color = "SubText", Wrap = true })
				tip.LayoutOrder = 1
				tip.Parent = right
			end
			-- Rename
			local nameRow = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 20, Parent = right })
			local box = Kit.TextBox("Name your farm…", { Size = UDim2.new(1, -96, 1, 0), Text = profile.Farm.Name or "", MaxLength = Social.Names.FarmMax })
			box.Parent = nameRow
			local save = Kit.Button("Rename", { Style = "Secondary", Size = UDim2.fromOffset(90, 36), TextSize = Theme.Sizes.Small, OnClick = function()
				local ok, result = Net.Request("FarmRename", box.Text)
				if ok then
					C.Notify.Toast("🪧 Your farm is now \"" .. tostring(result) .. "\"", "Success")
				else
					C.Notify.Toast(tostring(result), "Warning")
				end
			end })
			save.Position = UDim2.new(1, -90, 0, 0)
			save.Parent = nameRow
		end

		local function renderLayouts()
			local list = Kit.Scroll({ Size = UDim2.fromScale(1, 1) })
			list.Parent = body
			Kit.List(list, "Y", 8)
			local intro = Kit.Label("Save your farm's decoration layout to a slot and restore it later — handy for seasonal makeovers. Loading places saved decorations you still own and returns anything else to your bag.", { Size = Theme.Sizes.Small, Color = "SubText", Wrap = true })
			intro.Parent = list
			local unlocks = C.State.Get("Unlocks") or {}
			local slots = math.max(Placeables.LayoutSlots, tonumber(unlocks.LayoutSlots) or 0)
			for i = 1, slots do
				local saved = (layouts and (layouts[i] or layouts[tostring(i)])) or nil -- false = empty slot
				local card = Kit.Card(56)
				card.LayoutOrder = i
				card.Parent = list
				local label = Kit.Label("📐 Slot " .. i .. ": " .. (if saved then tostring(saved.Name) .. " · " .. tostring(saved.Count or 0) .. " objects" else "(empty)"), { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold })
				label.Size = UDim2.new(1, -240, 1, 0)
				label.Parent = card
				local saveButton = Kit.Button("Save here", { Style = "Secondary", Size = UDim2.fromOffset(110, 34), TextSize = Theme.Sizes.Small, OnClick = function()
					local ok, err = Net.Request("LayoutSave", i, (C.State.Get("Farm", "Name") or "Layout") .. " " .. i)
					if ok then
						C.Notify.Toast("Layout saved", "Success")
						local ok2, result = Net.Request("LayoutList")
						if ok2 then
							layouts = result
							render()
						end
					else
						C.Notify.Toast(tostring(err), "Warning")
					end
				end })
				saveButton.Position = UDim2.new(1, -230, 0, 3)
				saveButton.Parent = card
				local load = Kit.Button("Load", { Style = "Primary", Size = UDim2.fromOffset(110, 34), TextSize = Theme.Sizes.Small, OnClick = function()
					Kit.Confirm("Load layout " .. i .. "?", "Your current decorations are rearranged to match the saved layout.", function(yes)
						if yes then
							local ok, err = Net.Request("LayoutLoad", i)
							if not ok then
								C.Notify.Toast(tostring(err), "Warning")
							end
						end
					end, "Load")
				end })
				load.Position = UDim2.new(1, -112, 0, 3)
				load.Parent = card
				Kit.SetEnabled(load, saved ~= nil)
			end
		end

		render = function()
			Kit.Clear(body)
			if mode == "Land" then
				renderLand()
			else
				renderLayouts()
			end
			Kit.RepaintGradients(body)
		end
		tabs.Select("Land")
		return {
			Refresh = function()
				if mode == "Land" then
					render()
				end
			end,
		}
	end,
}

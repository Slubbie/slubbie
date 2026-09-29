-- The collection book: every crop, fish, bug, mineral, mutation, animal
-- breed, recipe, villager, region, weather and lore page, with your best
-- quality/size records and milestone rewards; the museum (donations to
-- Beatrix); and your showcase (items shown on your profile and farm).
-- Args: { Tab = "Book" | "Museum" | "Showcase", Category = id }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local ItemUtil = require(Shared.Lib.ItemUtil)
local Collections = require(Shared.Lib.Collections)
local Format = require(Shared.Lib.Format)
local Social = require(Shared.Config.Social)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Picker = require(UI.Picker)
local Describe = require(UI.Describe)
local C = require(UI.Parent.Controllers)

local MUSEUM = { Artifact = true, Gem = true, Mineral = true, Fish = true, Bug = true }

return {
	Id = "Collection",
	Title = "Collection Book",
	Icon = "📖",
	Size = Vector2.new(1000, 640),
	Watch = { "Collection", "Claimed", "Museum", "Showcase", "Inventory" },
	Build = function(win, ctx)
		local args = ctx.Args or {}
		local content = win.Content :: Frame
		local mode = args.Tab or "Book"
		local category = args.Category or Collections.Categories[1].Id
		local selectedEntry: string? = nil
		local render: () -> ()
		local tabs = Kit.Tabs({
			{ Id = "Book", Label = "Book", Icon = "📖" },
			{ Id = "Museum", Label = "Museum", Icon = "🏛️" },
			{ Id = "Showcase", Label = "Showcase", Icon = "🏆" },
		}, function(id)
			mode = id
			render()
		end)
		tabs.Frame.Parent = content
		local body = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, -46),
			Position = UDim2.fromOffset(0, 46),
			Parent = content,
		})

		local function renderBook()
			local profile = C.State.Data()
			local collection = (profile and profile.Collection) or {}
			-- Category list
			local cats = Kit.Scroll({ Size = UDim2.new(0, 220, 1, 0) })
			cats.Parent = body
			Kit.List(cats, "Y", 4)
			local total = Kit.Label(
				string.format("%.1f%% complete", Collections.TotalPercent(collection) * 100),
				{ Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold }
			)
			total.Parent = cats
			for i, cat in Collections.Categories do
				local found, count = Collections.Progress(collection, cat.Id)
				local claimable = false
				for index, milestone in cat.Milestones do
					local claimed = profile and profile.Claimed[cat.Id] and profile.Claimed[cat.Id][tostring(index)]
					if not claimed and count > 0 and found / count >= milestone.Percent then
						claimable = true
					end
				end
				local b = Kit.Button(
					cat.Icon .. " " .. cat.Name .. "  " .. found .. "/" .. count .. (if claimable then "  🎁" else ""),
					{
						Style = if category == cat.Id then "Primary" else "Secondary",
						Size = UDim2.new(1, -8, 0, 34),
						TextSize = Theme.Sizes.Tiny,
						LayoutOrder = i,
						OnClick = function()
							category = cat.Id
							selectedEntry = nil
							render()
						end,
					}
				)
				b.TextXAlignment = Enum.TextXAlignment.Left
				Kit.Padding(b, 0, 10)
				b.Parent = cats
			end
			local cat = Collections.Get(category)
			if not cat then
				return
			end
			local records = collection[cat.Id] or {}
			local found, count = Collections.Progress(collection, cat.Id)
			local main = Kit.new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -232, 1, 0),
				Position = UDim2.fromOffset(232, 0),
				Parent = body,
			})
			-- Milestones
			local milestones =
				Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 58), Parent = main })
			local progress = Kit.Progress({ Size = UDim2.new(1, 0, 0, 16), Color = "Accent" })
			progress.Frame.Parent = milestones
			progress.Set(
				if count > 0 then found / count else 0,
				cat.Icon .. " " .. cat.Name .. "  " .. found .. " / " .. count,
				false
			)
			local row = Kit.new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 34),
				Position = UDim2.fromOffset(0, 22),
				Parent = milestones,
			})
			Kit.List(row, "X", 6)
			for index, milestone in cat.Milestones do
				local claimed = profile and profile.Claimed[cat.Id] and profile.Claimed[cat.Id][tostring(index)]
				local ready = count > 0 and found / count >= milestone.Percent
				local b = Kit.Button(
					(if claimed then "✔ " elseif ready then "🎁 " else "🔒 ")
						.. math.floor(milestone.Percent * 100)
						.. "%",
					{
						Style = if ready and not claimed then "Accent" else "Secondary",
						Size = UDim2.fromOffset(96, 32),
						TextSize = Theme.Sizes.Tiny,
						LayoutOrder = index,
						OnClick = function()
							if ready and not claimed then
								local ok, err = Net.Request("CollectionClaim", cat.Id, index)
								if ok then
									C.Audio.PlayUI("QuestComplete")
								else
									C.Notify.Toast(tostring(err), "Warning")
								end
							end
						end,
					}
				)
				Kit.AttachTooltip(b, function()
					return {
						{ Text = math.floor(milestone.Percent * 100) .. "% of " .. cat.Name, Bold = true },
						{ Text = table.concat(Describe.Rewards(milestone.Reward), ", "), Color = "Accent" },
					}
				end)
				b.Parent = row
			end
			-- Entries
			local grid = Kit.Scroll({ Size = UDim2.new(0.62, -6, 1, -64), Position = UDim2.fromOffset(0, 64) })
			grid.Parent = main
			Kit.Grid(grid, 64, 6)
			for i, entry in cat.Entries do
				local record = records[entry.Id]
				local b = Kit.new(
					"TextButton",
					{ AutoButtonColor = false, Text = "", LayoutOrder = i, Selectable = true, Parent = grid }
				)
				Kit.Paint(b, "BackgroundColor3", if selectedEntry == entry.Id then "SlotHover" else "Slot")
				Kit.Corner(b, 8)
				local stroke = Kit.new("UIStroke", {
					Thickness = 2,
					Color = Theme.RarityColor(entry.Rarity),
					Transparency = if record then 0 else 0.85,
					Parent = b,
				})
				stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				local icon = Kit.new("TextLabel", {
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					Text = if record then entry.Icon else "❔",
					TextScaled = true,
					Font = Theme.Fonts.Body,
					Parent = b,
				})
				Kit.new("UIPadding", {
					PaddingTop = UDim.new(0.15, 0),
					PaddingBottom = UDim.new(0.15, 0),
					PaddingLeft = UDim.new(0.15, 0),
					PaddingRight = UDim.new(0.15, 0),
					Parent = icon,
				})
				if not record then
					icon.TextTransparency = 0.5
				end
				b.Activated:Connect(function()
					selectedEntry = entry.Id
					Kit.PlaySound("UIClick")
					render()
				end)
				Kit.AttachTooltip(b, function()
					return {
						{
							Text = if record then entry.Name else "???",
							Bold = true,
							Color = Theme.RarityColor(entry.Rarity),
						},
						{ Text = entry.Rarity, Color = "SubText", Size = Theme.Sizes.Tiny },
					}
				end)
			end
			-- Entry detail
			local detail = Kit.Panel({
				Size = UDim2.new(0.38, -6, 1, -64),
				Position = UDim2.new(0.62, 6, 0, 64),
				Color = "PanelAlt",
			})
			detail.Parent = main
			Kit.Padding(detail, 12, 12)
			Kit.List(detail, "Y", 6)
			local entry = selectedEntry and cat.Index[selectedEntry]
			if not entry then
				Kit.Label(
					"Select an entry. Undiscovered ones show a hint.",
					{ Size = Theme.Sizes.Small, Color = "SubText", Wrap = true }
				).Parent =
					detail
				return
			end
			local record = records[entry.Id]
			local big = Kit.new("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(80, 80),
				Text = if record then entry.Icon else "❔",
				TextScaled = true,
				Font = Theme.Fonts.Body,
				Parent = detail,
			})
			big.LayoutOrder = 0
			local name = Kit.Heading(if record then entry.Name else "Undiscovered", 18)
			name.TextColor3 = Theme.RarityColor(entry.Rarity)
			name.LayoutOrder = 1
			name.Parent = detail
			local rarity = Kit.Label(
				Theme.Rarity(entry.Rarity).Glyph .. " " .. entry.Rarity,
				{ Size = Theme.Sizes.Tiny, Color = "SubText" }
			)
			rarity.LayoutOrder = 2
			rarity.Parent = detail
			if record then
				local lines = {
					"Found " .. Format.Commas(record.N or 1) .. " time" .. (if (record.N or 1) == 1 then "" else "s"),
				}
				if record.Q and record.Q > 1 then
					local tier = Theme.QualityTier(record.Q)
					table.insert(lines, "Best quality: " .. tier.Glyph .. " " .. tier.Name)
				end
				if record.S then
					table.insert(
						lines,
						"Record size: " .. tostring(record.S) .. (if cat.Id == "Fish" then " cm" else " kg")
					)
				end
				local stats = Kit.Label(table.concat(lines, "\n"), { Size = Theme.Sizes.Small, Wrap = true })
				stats.LayoutOrder = 3
				stats.Parent = detail
				local item = Registry.Items[entry.Id]
				if item and item.Description ~= "" then
					local d = Kit.Label(item.Description, { Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true })
					d.LayoutOrder = 4
					d.Parent = detail
				end
			end
			if entry.Hint then
				local hint = Kit.Label("💡 " .. entry.Hint, { Size = Theme.Sizes.Tiny, Color = "Info", Wrap = true })
				hint.LayoutOrder = 5
				hint.Parent = detail
			end
		end

		local function renderMuseum()
			local profile = C.State.Data()
			local museum = (profile and profile.Museum) or {}
			local header =
				Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), Parent = body })
			local donatedCount, totalCount = 0, 0
			for _, item in Registry.ItemList do
				if MUSEUM[item.Category] then
					totalCount += 1
					if museum[item.Id] then
						donatedCount += 1
					end
				end
			end
			local info = Kit.Label(
				"🏛️ "
					.. donatedCount
					.. " / "
					.. totalCount
					.. " donated · Beatrix pays a finder's fee and the museum grows with every piece.",
				{ Size = Theme.Sizes.Small, Wrap = true }
			)
			info.Size = UDim2.new(1, -190, 1, 0)
			info.Parent = header
			local donate = Kit.Button("Donate an item", {
				Style = "Accent",
				Size = UDim2.fromOffset(180, 36),
				TextSize = Theme.Sizes.Small,
				OnClick = function()
					Picker.Open({
						Title = "Donate to the museum",
						Filter = function(stack, def)
							return MUSEUM[def.Category] == true and not museum[stack.Id] and not stack.L
						end,
						Empty = "Nothing new for the museum. Artifacts, gems, minerals, fish and bugs are welcome.",
						OnPick = function(ref)
							local ok, result = Net.Request("MuseumDonate", ref)
							if ok then
								C.Audio.PlayUI("Discovery")
								C.Notify.Toast(
									"🏛️ Donated! Beatrix gave you " .. Kit.Money(result or 0),
									"Success"
								)
							else
								C.Notify.Toast(tostring(result), "Warning")
							end
						end,
					})
				end,
			})
			donate.Position = UDim2.new(1, -180, 0, 2)
			donate.Parent = header
			local grid = Kit.Scroll({ Size = UDim2.new(1, 0, 1, -48), Position = UDim2.fromOffset(0, 48) })
			grid.Parent = body
			Kit.List(grid, "Y", 8)
			local order = 0
			for _, catName in { "Artifact", "Gem", "Mineral", "Fish", "Bug" } do
				order += 1
				local items = {}
				for _, item in Registry.ItemList do
					if item.Category == catName then
						table.insert(items, item)
					end
				end
				table.sort(items, function(a, b)
					return a.Name < b.Name
				end)
				local done = 0
				for _, item in items do
					if museum[item.Id] then
						done += 1
					end
				end
				local h = Kit.Label(
					catName .. "s  " .. done .. "/" .. #items,
					{ Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold }
				)
				h.LayoutOrder = order
				h.Parent = grid
				order += 1
				local shelf = Kit.new("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, -8, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					LayoutOrder = order,
					Parent = grid,
				})
				Kit.Grid(shelf, 46, 4)
				for i, item in items do
					local slot = Kit.ItemSlot(46)
					slot.Button.LayoutOrder = i
					slot.Button.Active = false
					if museum[item.Id] then
						slot.Set({ Id = item.Id, N = 1 })
					end
					slot.Button.Parent = shelf
				end
			end
		end

		local function renderShowcase()
			local profile = C.State.Data()
			local showcase = (profile and profile.Showcase) or {}
			local intro = Kit.Label(
				"Show off your best finds. Your showcase appears on your profile card and on display cases on your farm.",
				{ Size = Theme.Sizes.Small, Color = "SubText", Wrap = true }
			)
			intro.Parent = body
			local grid = Kit.new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, -40),
				Position = UDim2.fromOffset(0, 40),
				Parent = body,
			})
			local layout = Kit.new("UIGridLayout", {
				CellSize = UDim2.new(0.333, -8, 0, 200),
				CellPadding = UDim2.fromOffset(10, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = grid,
			})
			layout.FillDirectionMaxCells = 3
			for i = 1, Social.Profile.ShowcaseSlots do
				local item = showcase[tostring(i)]
				local card = Kit.Card(200)
				card.LayoutOrder = i
				card.Parent = grid
				Kit.List(card, "Y", 6, "Center")
				local slot = Kit.ItemSlot(84)
				slot.Button.Active = false
				slot.Set(if item then { Id = item.Id, N = 1, Q = item.Q, M = item.M, S = item.S } else nil)
				slot.Button.Parent = card
				local name = Kit.Label(
					if item
						then ItemUtil.DisplayName({ Id = item.Id, N = 1, Q = item.Q, M = item.M })
						else "Empty pedestal",
					{ Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold, Align = "Center", Wrap = true }
				)
				name.LayoutOrder = 1
				name.Parent = card
				local buttons = Kit.new(
					"Frame",
					{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 2, Parent = card }
				)
				Kit.List(buttons, "X", 6, "Center")
				Kit.Button(if item then "Change" else "Choose", {
					Style = "Primary",
					Size = UDim2.fromOffset(90, 32),
					TextSize = Theme.Sizes.Tiny,
					OnClick = function()
						Picker.Open({
							Title = "Show off…",
							OnPick = function(ref)
								local ok, err = Net.Request("ShowcaseSet", i, ref)
								if not ok then
									C.Notify.Toast(tostring(err), "Warning")
								end
							end,
						})
					end,
				}).Parent =
					buttons
				if item then
					Kit.Button("Clear", {
						Style = "Secondary",
						Size = UDim2.fromOffset(70, 32),
						TextSize = Theme.Sizes.Tiny,
						LayoutOrder = 1,
						OnClick = function()
							Net.Request("ShowcaseSet", i, nil)
						end,
					}).Parent =
						buttons
				end
			end
			local note = Kit.Label(
				"The item stays in your bag — the showcase shows a copy.",
				{ Size = Theme.Sizes.Tiny, Color = "SubText" }
			)
			note.Position = UDim2.new(0, 0, 1, -18)
			note.Parent = body
		end

		render = function()
			Kit.Clear(body)
			if mode == "Book" then
				renderBook()
			elseif mode == "Museum" then
				renderMuseum()
			else
				renderShowcase()
			end
			Kit.RepaintGradients(body)
		end
		tabs.Select(mode)
		return { Refresh = render }
	end,
}

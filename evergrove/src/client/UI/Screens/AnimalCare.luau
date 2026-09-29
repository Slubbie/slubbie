-- One animal: its portrait, personality, genes, happiness and bond, today's
-- care, and every action (pet, brush, feed, treat, collect, ride, rename,
-- move home, rehome). Works on friends' farms too (with permission), using
-- what the animal's world anchor shows.
-- Args: { Aid = animalId }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local Format = require(Shared.Lib.Format)
local GameTime = require(Shared.Lib.GameTime)
local Animals = require(Shared.Config.Animals)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local AnimalInfo = require(UI.AnimalInfo)
local C = require(UI.Parent.Controllers)

local function anchorFor(aid: string): Instance?
	local farms = workspace:FindFirstChild("Farms")
	local found = farms and farms:FindFirstChild(aid, true)
	return found
end

local function geneBar(parent: Instance, label: string, value: number, order: number)
	local row = Kit.new(
		"Frame",
		{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = order, Parent = parent }
	)
	local l = Kit.Label(label, { Size = Theme.Sizes.Tiny })
	l.Size = UDim2.new(0, 70, 1, 0)
	l.Parent = row
	local bar = Kit.Progress({
		Size = UDim2.new(1, -110, 0, 10),
		Color = if value >= 7 then "Good" elseif value >= 4 then "Accent" else "Warn",
	})
	bar.Frame.Position = UDim2.new(0, 72, 0.5, -5)
	bar.Frame.Parent = row
	bar.Set(value / 10, nil, false)
	local v = Kit.Label(string.format("%.1f", value), { Size = Theme.Sizes.Tiny, Align = "Right", Color = "SubText" })
	v.Size = UDim2.new(0, 34, 1, 0)
	v.Position = UDim2.new(1, -34, 0, 0)
	v.Parent = row
end

return {
	Id = "AnimalCare",
	Title = "Animal",
	Icon = "🐾",
	Size = Vector2.new(780, 560),
	Watch = { "Farm", "Inventory" },
	Build = function(win, ctx)
		local args = ctx.Args or {}
		local aid = tostring(args.Aid)
		local content = win.Content :: Frame

		local function act(action: string)
			local ok, result = Net.Request("AnimalAct", aid, action)
			if ok then
				if action == "Ride" then
					ctx.Close()
					return
				end
				C.Audio.PlayUI(if action == "Collect" then "ItemPickup" else "Pet")
				C.Animation.Play(if action == "Collect" then "Pick" else "Pet")
			else
				C.Notify.Toast(tostring(result), "Warning")
			end
		end

		local function render()
			Kit.Clear(content)
			local profile = C.State.Data()
			local animal = profile and profile.Farm and profile.Farm.Animals and profile.Farm.Animals[aid]
			local anchor = anchorFor(aid)
			if not animal then
				-- Someone else's animal: show what the world shows.
				if not anchor then
					Kit.Empty("That animal wandered off.").Parent = content
					return
				end
				local species = Registry.Species[anchor:GetAttribute("Sp") or ""]
				win.Title.Text = (if species then species.Icon else "🐾")
					.. "  "
					.. tostring(anchor:GetAttribute("Nm") or "Animal")
				local info = Kit.Label(
					"Mood: "
						.. tostring(anchor:GetAttribute("Mood") or "?")
						.. (if anchor:GetAttribute("Ready") then "   ·   🧺 products ready" else ""),
					{ Size = Theme.Sizes.Body }
				)
				info.Parent = content
				local row = Kit.new("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 44),
					Position = UDim2.fromOffset(0, 40),
					Parent = content,
				})
				Kit.List(row, "X", 8)
				for i, entry in
					{
						{ "Pet", "🤚 Pet" },
						{ "Brush", "🪮 Brush" },
						{ "Feed", "🍽️ Feed" },
						{ "Collect", "🧺 Collect" },
					}
				do
					Kit.Button(entry[2], {
						Style = "Secondary",
						Size = UDim2.fromOffset(130, 40),
						TextSize = Theme.Sizes.Small,
						LayoutOrder = i,
						OnClick = function()
							act(entry[1])
						end,
					}).Parent =
						row
				end
				local note = Kit.Label(
					"You're helping on a friend's farm. What you can do depends on the permissions they gave you.",
					{ Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true }
				)
				note.Position = UDim2.fromOffset(0, 96)
				note.Parent = content
				return
			end
			local species = Registry.Species[animal.Sp]
			local pers = AnimalInfo.Personality(animal)
			local rarity = AnimalInfo.Rarity(animal)
			local look, carried = AnimalInfo.LookText(animal)
			local today = AnimalInfo.Today(animal)
			local mood = AnimalInfo.Mood(animal)
			win.Title.Text = species.Icon .. "  " .. animal.Nm

			-- Portrait column
			local left = Kit.Panel({ Size = UDim2.new(0, 260, 1, 0), Color = "PanelAlt" })
			left.Parent = content
			Kit.Padding(left, 12, 12)
			Kit.List(left, "Y", 6, "Center")
			local face = Kit.new("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(100, 100),
				Text = species.Icon,
				TextScaled = true,
				Font = Theme.Fonts.Body,
				Parent = left,
			})
			face.LayoutOrder = 0
			local rarityLabel = Kit.Label(
				Theme.Rarity(rarity).Glyph
					.. " "
					.. rarity
					.. " "
					.. species.Name
					.. (if AnimalInfo.IsBaby(animal) then " (baby)" else ""),
				{ Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold, Align = "Center" }
			)
			rarityLabel.TextColor3 = Theme.RarityColor(rarity)
			rarityLabel.LayoutOrder = 1
			rarityLabel.Parent = left
			local lookLabel = Kit.Label(
				look .. (if carried then "\n(" .. carried .. ")" else ""),
				{ Size = Theme.Sizes.Tiny, Color = "SubText", Align = "Center", Wrap = true }
			)
			lookLabel.LayoutOrder = 2
			lookLabel.Parent = left
			local persLabel = Kit.Label(
				pers.Icon .. " " .. pers.Id .. " — " .. (pers.Note or ""),
				{ Size = Theme.Sizes.Tiny, Align = "Center", Wrap = true }
			)
			persLabel.LayoutOrder = 3
			persLabel.Parent = left
			local genes = Kit.new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = 4,
				Parent = left,
			})
			Kit.List(genes, "Y", 2)
			geneBar(genes, "Size", animal.G.Size, 1)
			geneBar(genes, "Yield", animal.G.Yield, 2)
			geneBar(genes, "Temper", animal.G.Temper, 3)
			geneBar(genes, "Speed", animal.G.Speed, 4)
			local age = os.time() - (animal.Born or os.time())
			local born = Kit.Label(
				"Age "
					.. Format.Duration(age)
					.. (
						if animal.Preg
							then "\n🍼 Expecting (with "
								.. tostring(animal.Preg.Sire)
								.. ") — due in "
								.. Format.Duration(math.max(0, animal.Preg.Due - GameTime.Now()))
							else ""
					),
				{ Size = Theme.Sizes.Tiny, Color = "SubText", Align = "Center", Wrap = true }
			)
			born.LayoutOrder = 5
			born.Parent = left

			-- Status & actions
			local right = Kit.new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -272, 1, 0),
				Position = UDim2.fromOffset(272, 0),
				Parent = content,
			})
			Kit.List(right, "Y", 8)
			local hap = Kit.Progress({
				Size = UDim2.new(1, 0, 0, 18),
				Color = if (animal.Hap or 0) >= 60 then "Good" elseif (animal.Hap or 0) >= 30 then "Warn" else "Bad",
			})
			hap.Frame.Parent = right
			hap.Set(
				(animal.Hap or 0) / 100,
				(AnimalInfo.MOOD_ICON[mood] or "") .. " " .. mood .. " · happiness " .. math.floor(animal.Hap or 0),
				false
			)
			local bond = Kit.Progress({ Size = UDim2.new(1, 0, 0, 18), Color = "Bad" })
			bond.Frame.LayoutOrder = 1
			bond.Frame.Parent = right
			bond.Set(
				(animal.Fr or 0) / Animals.MaxFriendship,
				AnimalInfo.Hearts(animal) .. " bond " .. math.floor(animal.Fr or 0) .. " / " .. Animals.MaxFriendship,
				false
			)
			local product =
				Registry.Items[(species.CoatProducts and species.CoatProducts[AnimalInfo.Phenotype(animal).Coat.Id]) or species.Product]
			local productLine = Kit.Label(
				(if product then product.Icon .. " " .. product.Name else "Products")
					.. " every "
					.. Format.Duration(species.Interval * GameTime.HOUR)
					.. "  ·  "
					.. (if (animal.Rd or 0) > 0 then "🧺 " .. animal.Rd .. " ready!" else "none ready yet"),
				{ Size = Theme.Sizes.Small, Color = if (animal.Rd or 0) > 0 then "Good" else "Text" }
			)
			productLine.LayoutOrder = 2
			productLine.Parent = right
			local todayLine = Kit.Label(
				"Today: "
					.. (if today.Fed then "🍽️ fed ✔" else "🍽️ hungry ✖")
					.. "   "
					.. (if today.Pet then "🤚 petted ✔" else "🤚 not petted")
					.. "   "
					.. (if today.Brushed then "🪮 brushed ✔" else "🪮 not brushed"),
				{ Size = Theme.Sizes.Small }
			)
			todayLine.LayoutOrder = 3
			todayLine.Parent = right
			local feedNames = {}
			for _, id in species.Feed do
				local item = Registry.Items[id]
				table.insert(feedNames, (if item then item.Icon .. " " .. item.Name else id))
			end
			local feedLine = Kit.Label(
				"Eats: " .. table.concat(feedNames, " or ") .. " (feed in your bag is used automatically)",
				{ Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true }
			)
			feedLine.LayoutOrder = 4
			feedLine.Parent = right

			local actions = Kit.new(
				"Frame",
				{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 96), LayoutOrder = 5, Parent = right }
			)
			local grid = Kit.new("UIGridLayout", {
				CellSize = UDim2.new(0.333, -6, 0, 42),
				CellPadding = UDim2.fromOffset(6, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = actions,
			})
			grid.FillDirectionMaxCells = 3
			local list = {
				{ "Pet", "🤚 Pet", not today.Pet },
				{ "Brush", "🪮 Brush", not today.Brushed },
				{ "Feed", "🍽️ Feed", not today.Fed },
				{ "Treat", "🍬 Treat", not today.Treat },
				{ "Collect", "🧺 Collect", (animal.Rd or 0) > 0 },
			}
			if species.Rideable and not AnimalInfo.IsBaby(animal) then
				table.insert(list, { "Ride", "🏇 Ride", true })
			end
			for i, entry in list do
				local b = Kit.Button(entry[2], {
					Style = if entry[3] then "Primary" else "Secondary",
					TextSize = Theme.Sizes.Small,
					LayoutOrder = i,
					OnClick = function()
						act(entry[1])
					end,
				})
				b.Parent = actions
			end

			local manage = Kit.new(
				"Frame",
				{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 6, Parent = right }
			)
			Kit.List(manage, "X", 6)
			Kit.Button("✏️ Rename", {
				Style = "Secondary",
				Size = UDim2.fromOffset(120, 36),
				TextSize = Theme.Sizes.Tiny,
				OnClick = function()
					local layer = Kit.ModalLayer
					if not layer then
						return
					end
					local shade = Kit.new("TextButton", {
						AutoButtonColor = false,
						Text = "",
						BackgroundColor3 = Color3.new(0, 0, 0),
						BackgroundTransparency = 0.45,
						Size = UDim2.fromScale(1, 1),
						ZIndex = 80,
						Parent = layer,
					})
					local panel = Kit.Panel({ Size = UDim2.fromOffset(360, 150), Shadow = true })
					panel.AnchorPoint = Vector2.new(0.5, 0.5)
					panel.Position = UDim2.fromScale(0.5, 0.5)
					panel.Parent = shade
					Kit.Padding(panel, 14, 16)
					Kit.List(panel, "Y", 10)
					Kit.Heading("Rename " .. animal.Nm).Parent = panel
					local box = Kit.TextBox("New name", { Text = animal.Nm, MaxLength = Animals.NameMaxLength })
					box.LayoutOrder = 1
					box.Parent = panel
					local ok = Kit.Button("Save", {
						Style = "Primary",
						Size = UDim2.fromOffset(100, 34),
						OnClick = function()
							local done, result = Net.Request("AnimalName", aid, box.Text)
							shade:Destroy()
							if not done then
								C.Notify.Toast(tostring(result), "Warning")
							end
						end,
					})
					ok.LayoutOrder = 2
					ok.Parent = panel
					box:CaptureFocus()
				end,
			}).Parent =
				manage
			local homes = AnimalInfo.Homes(profile)
			local options, byName = {}, {}
			for _, home in homes do
				if home.Def.Function.Home == species.Home then
					local name = home.Def.Name
						.. " ("
						.. home.Residents
						.. "/"
						.. home.Def.Function.Capacity
						.. ")"
						.. (if home.Uid == animal.Home then " ✓" else "")
					table.insert(options, name)
					byName[name] = home.Uid
				end
			end
			if #options > 1 then
				local currentName = options[1]
				for name, uid in byName do
					if uid == animal.Home then
						currentName = name
					end
				end
				local choice = Kit.Choice(options, currentName, function(name)
					local uid = byName[name]
					if uid and uid ~= animal.Home then
						local done, err = Net.Request("AnimalMove", aid, uid)
						if not done then
							C.Notify.Toast(tostring(err), "Warning")
						end
					end
				end)
				choice.LayoutOrder = 1
				choice.Parent = manage
			end
			Kit.Button("Rehome…", {
				Style = "Danger",
				Size = UDim2.fromOffset(110, 36),
				TextSize = Theme.Sizes.Tiny,
				LayoutOrder = 2,
				OnClick = function()
					Kit.Confirm(
						"Rehome " .. animal.Nm .. "?",
						"Hattie at the ranch will find "
							.. animal.Nm
							.. " a loving new farm, and pay you for them. This can't be undone. (Talk to Hattie to do it.)",
						function(yes)
							if yes then
								local done, result = Net.Request("AnimalSell", aid)
								if done then
									ctx.Close()
								else
									C.Notify.Toast(tostring(result), "Warning")
								end
							end
						end,
						"Rehome",
						true
					)
				end,
			}).Parent =
				manage
			Kit.RepaintGradients(content)
		end

		render()
		return { Refresh = render }
	end,
}

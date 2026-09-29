-- Your animals, by home: everyone's mood, today's care, ready products,
-- feed-all / collect-all, and the breeding planner with exact Punnett odds.
-- Args: { Home = placedUid } (from a coop/barn prompt) or nothing (all homes).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local Genetics = require(Shared.Lib.Genetics)
local Format = require(Shared.Lib.Format)
local GameTime = require(Shared.Lib.GameTime)
local Animals = require(Shared.Config.Animals)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local AnimalInfo = require(UI.AnimalInfo)
local C = require(UI.Parent.Controllers)

return {
	Id = "Animals",
	Title = "Animals",
	Icon = "🐄",
	Size = Vector2.new(960, 620),
	Watch = { "Farm", "Inventory" },
	Build = function(win, ctx)
		local args = ctx.Args or {}
		local content = win.Content :: Frame
		local homeFilter: string? = args.Home
		local mode = "Herd"
		local pair: { string } = {}
		local render: () -> ()

		local tabs = Kit.Tabs({ { Id = "Herd", Label = "Animals", Icon = "🐾" }, { Id = "Breed", Label = "Breeding", Icon = "💞" } }, function(id)
			mode = id
			render()
		end)
		tabs.Frame.Parent = content
		local body = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -46), Position = UDim2.fromOffset(0, 46), Parent = content })

		local function act(aid: string, action: string)
			local ok, result = Net.Request("AnimalAct", aid, action)
			if ok then
				if action == "FeedAll" then
					C.Notify.Toast("🍽️ Fed " .. tostring(result) .. " animals", "Success")
				end
				C.Audio.PlayUI(if action == "CollectAll" then "ItemPickup" else "Pet")
			else
				C.Notify.Toast(tostring(result), "Warning")
			end
		end

		local function animalCard(aid: string, animal: any, order: number, parent: Instance, selectable: boolean)
			local species = Registry.Species[animal.Sp]
			local mood = AnimalInfo.Mood(animal)
			local today = AnimalInfo.Today(animal)
			local rarity = AnimalInfo.Rarity(animal)
			local chosen = table.find(pair, aid) ~= nil
			local card = Kit.new("TextButton", { AutoButtonColor = false, Text = "", Size = UDim2.new(1, -8, 0, 70), LayoutOrder = order, Selectable = true, Parent = parent })
			Kit.Paint(card, "BackgroundColor3", if chosen then "SlotHover" else "PanelAlt")
			Kit.Corner(card, 10)
			local stroke = Kit.new("UIStroke", { Thickness = 2, Color = Theme.RarityColor(rarity), Transparency = if Registry.RarityOrder(rarity) >= 3 then 0 else 0.7, Parent = card })
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			local icon = Kit.new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(52, 52), Position = UDim2.fromOffset(8, 9), Text = species.Icon, TextScaled = true, Font = Theme.Fonts.Body, Parent = card })
			if AnimalInfo.IsBaby(animal) then
				icon.Size = UDim2.fromOffset(38, 38)
				icon.Position = UDim2.fromOffset(15, 16)
			end
			local look = AnimalInfo.LookText(animal)
			local name = Kit.Label(animal.Nm .. "  " .. AnimalInfo.Hearts(animal), { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold })
			name.Position = UDim2.fromOffset(68, 6)
			name.Size = UDim2.new(1, -200, 0, 20)
			name.Parent = card
			local pers = AnimalInfo.Personality(animal)
			local sub = Kit.Label(species.Name .. " · " .. look .. " · " .. pers.Icon .. " " .. pers.Id .. (if animal.Preg then " · 🍼 expecting" else ""), { Size = Theme.Sizes.Tiny, Color = "SubText" })
			sub.Position = UDim2.fromOffset(68, 26)
			sub.Size = UDim2.new(1, -200, 0, 16)
			sub.Parent = card
			local care = Kit.Label((if today.Fed then "🍽️✔ " else "🍽️✖ ") .. (if today.Pet then "🤚✔ " else "🤚✖ ") .. (if today.Brushed then "🪮✔" else "🪮✖") .. "   " .. (AnimalInfo.MOOD_ICON[mood] or "") .. " " .. mood .. " (" .. math.floor(animal.Hap or 0) .. ")", { Size = Theme.Sizes.Tiny, Color = if mood == "Hungry" or mood == "Sad" then "Bad" else "Text" })
			care.Position = UDim2.fromOffset(68, 44)
			care.Size = UDim2.new(1, -200, 0, 16)
			care.Parent = card
			local ready = animal.Rd or 0
			local product = Registry.Items[(species.CoatProducts and species.CoatProducts[AnimalInfo.Phenotype(animal).Coat.Id]) or species.Product]
			local readyLabel = Kit.Label(if ready > 0 then (if product then product.Icon else "📦") .. " ×" .. ready .. " ready" else "", { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold, Color = "Good", Align = "Right" })
			readyLabel.Size = UDim2.fromOffset(120, 20)
			readyLabel.Position = UDim2.new(1, -128, 0, 24)
			readyLabel.Parent = card
			card.Activated:Connect(function()
				if selectable then
					local index = table.find(pair, aid)
					if index then
						table.remove(pair, index)
					else
						if #pair >= 2 then
							table.remove(pair, 1)
						end
						table.insert(pair, aid)
					end
					Kit.PlaySound("UIClick")
					render()
				else
					C.Windows.Open("AnimalCare", { Aid = aid, Back = homeFilter })
				end
			end)
		end

		local function renderHerd()
			local profile = C.State.Data()
			local animals = (profile and profile.Farm and profile.Farm.Animals) or {}
			local homes = AnimalInfo.Homes(profile)
			local list = Kit.Scroll({ Size = UDim2.new(1, 0, 1, -44) })
			list.Parent = body
			Kit.List(list, "Y", 8)
			local order = 0
			local shown = 0
			for _, home in homes do
				if not homeFilter or homeFilter == home.Uid then
					order += 1
					local header = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 36), LayoutOrder = order, Parent = list })
					local title = Kit.Heading(home.Def.Icon .. " " .. home.Def.Name .. "  (" .. home.Residents .. " / " .. home.Def.Function.Capacity .. ")", 18)
					title.Size = UDim2.new(1, -260, 1, 0)
					title.Parent = header
					local residents = {}
					for aid, animal in animals do
						if animal.Home == home.Uid then
							table.insert(residents, { Aid = aid, Animal = animal })
						end
					end
					table.sort(residents, function(a, b)
						return a.Animal.Nm < b.Animal.Nm
					end)
					if #residents > 0 then
						local first = residents[1].Aid
						local feedAll = Kit.Button("🍽️ Feed all", { Style = "Secondary", Size = UDim2.fromOffset(120, 32), TextSize = Theme.Sizes.Tiny, OnClick = function()
							act(first, "FeedAll")
						end })
						feedAll.Position = UDim2.new(1, -250, 0, 2)
						feedAll.Parent = header
						local collectAll = Kit.Button("🧺 Collect all", { Style = "Good", Size = UDim2.fromOffset(124, 32), TextSize = Theme.Sizes.Tiny, OnClick = function()
							act(first, "CollectAll")
						end })
						collectAll.Position = UDim2.new(1, -124, 0, 2)
						collectAll.Parent = header
					end
					for _, r in residents do
						order += 1
						shown += 1
						animalCard(r.Aid, r.Animal, order, list, false)
					end
					if #residents == 0 then
						order += 1
						local empty = Kit.Label("Empty — adopt " .. string.lower(home.Def.Function.Home) .. " animals from Hattie at the ranch.", { Size = Theme.Sizes.Small, Color = "SubText" })
						empty.LayoutOrder = order
						empty.Parent = list
					end
				end
			end
			if #homes == 0 then
				Kit.Empty("You don't have any animal buildings yet. Buy a Coop or Barn from Gus at Timberline Builders, then adopt animals from Hattie.").Parent = list
			end
			local footer = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 38), Position = UDim2.new(0, 0, 1, -38), Parent = body })
			Kit.List(footer, "X", 8)
			if homeFilter then
				Kit.Button("Show all homes", { Style = "Secondary", Size = UDim2.fromOffset(150, 36), TextSize = Theme.Sizes.Small, OnClick = function()
					homeFilter = nil
					render()
				end }).Parent = footer
			end
			local hint = Kit.Label("Animals want food every day, and love being petted and brushed. Happy, trusting animals give better products.", { Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true })
			hint.Size = UDim2.new(1, -170, 1, 0)
			hint.LayoutOrder = 2
			hint.Parent = footer
		end

		local function renderBreed()
			local profile = C.State.Data()
			local animals = (profile and profile.Farm and profile.Farm.Animals) or {}
			local left = Kit.Scroll({ Size = UDim2.new(0.5, -6, 1, 0) })
			left.Parent = body
			Kit.List(left, "Y", 6)
			local intro = Kit.Label("Pick two adults of the same species. Both need happiness 60+ and a good bond. Rare looks are recessive: two carriers can surprise you!", { Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true })
			intro.Parent = left
			local ids = {}
			for aid, animal in animals do
				if not homeFilter or animal.Home == homeFilter then
					table.insert(ids, aid)
				end
			end
			table.sort(ids, function(a, b)
				local x, y = animals[a], animals[b]
				if x.Sp ~= y.Sp then
					return x.Sp < y.Sp
				end
				return x.Nm < y.Nm
			end)
			for i, aid in ids do
				animalCard(aid, animals[aid], i, left, true)
			end
			local right = Kit.Panel({ Size = UDim2.new(0.5, -6, 1, 0), Position = UDim2.new(0.5, 6, 0, 0), Color = "PanelAlt" })
			right.Parent = body
			Kit.Padding(right, 12, 14)
			Kit.List(right, "Y", 8)
			local a = pair[1] and animals[pair[1]]
			local b = pair[2] and animals[pair[2]]
			if not a or not b then
				Kit.Label("Choose two animals on the left.", { Size = Theme.Sizes.Small, Color = "SubText" }).Parent = right
				return
			end
			local species = Registry.Species[a.Sp]
			Kit.Heading(species.Icon .. " " .. a.Nm .. "  ×  " .. b.Nm, 20).Parent = right
			local ok, why = AnimalInfo.BreedCheck(a, b)
			if a.Sp == b.Sp then
				local odds = Genetics.BreedOdds(a.Sp, a.G, b.G)
				local function oddsLines(title: string, map: { [string]: number }, list: { any }, order: number)
					local h = Kit.Label(title, { Size = Theme.Sizes.Small, Font = Theme.Fonts.Bold })
					h.LayoutOrder = order
					h.Parent = right
					local entries = {}
					for id, p in map do
						table.insert(entries, { Id = id, P = p })
					end
					table.sort(entries, function(x, y)
						return x.P > y.P
					end)
					for i, entry in entries do
						local allele
						for _, al in list do
							if al.Id == entry.Id then
								allele = al
							end
						end
						local line = Kit.Label(string.format("%3d%%  %s", math.floor(entry.P * 100 + 0.5), if allele then allele.Name .. " (" .. allele.Rarity .. ")" else entry.Id), { Size = Theme.Sizes.Small })
						if allele then
							line.TextColor3 = Theme.RarityColor(allele.Rarity)
						end
						line.LayoutOrder = order + i
						line.Parent = right
					end
				end
				oddsLines("Coat odds", odds.Coat, species.Coats, 10)
				oddsLines("Pattern odds", odds.Pattern, species.Patterns, 30)
				local stats = Kit.Label(string.format("Stats average the parents (±%.1f): size %.1f · yield %.1f · temper %.1f · speed %.1f", Animals.QuantitativeNoise, (a.G.Size + b.G.Size) / 2, (a.G.Yield + b.G.Yield) / 2, (a.G.Temper + b.G.Temper) / 2, (a.G.Speed + b.G.Speed) / 2), { Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true })
				stats.LayoutOrder = 50
				stats.Parent = right
				local extra = Kit.Label("Plus a " .. math.floor(Animals.MutationChance * 100) .. "% chance of a brand-new rare coat. The baby arrives in about " .. Format.Duration(Animals.GestationHours * GameTime.HOUR) .. ".", { Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true })
				extra.LayoutOrder = 51
				extra.Parent = right
			end
			if not ok then
				local warn = Kit.Label("✋ " .. tostring(why), { Size = Theme.Sizes.Small, Color = "Warn", Wrap = true })
				warn.LayoutOrder = 60
				warn.Parent = right
			end
			local breed = Kit.Button("💞 Breed", { Style = "Accent", Size = UDim2.new(1, 0, 0, 42), LayoutOrder = 70, OnClick = function()
				local done, result = Net.Request("AnimalBreed", pair[1], pair[2])
				if done then
					table.clear(pair)
					C.Audio.PlayUI("Discovery")
				else
					C.Notify.Toast(tostring(result), "Warning")
				end
			end })
			breed.Parent = right
			Kit.SetEnabled(breed, ok)
		end

		render = function()
			Kit.Clear(body)
			if mode == "Herd" then
				renderHerd()
			else
				renderBreed()
			end
			Kit.RepaintGradients(body)
		end

		tabs.Select(args.Tab or "Herd")
		C.Tutorial.Hint("Animals")
		return { Refresh = render }
	end,
}

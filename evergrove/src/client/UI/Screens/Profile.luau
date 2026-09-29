-- Profiles: your (or another farmer's) card — estate, skills, showcase,
-- collection progress and public stats — your statistics dashboard, and the
-- wardrobe for titles, banners, frames, nameplates, companions and farm skins.
-- Args: { UserId = number, Tab = "Card" | "Stats" | "Wardrobe" }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local ItemUtil = require(Shared.Lib.ItemUtil)
local Format = require(Shared.Lib.Format)
local Stats = require(Shared.Lib.Stats)
local Skills = require(Shared.Config.Skills)
local Store = require(Shared.Config.Store)
local Social = require(Shared.Config.Social)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local C = require(UI.Parent.Controllers)

local STAT_GROUPS = {
	{ "🌾 Farming", { { "CropsHarvested", "Crops harvested" }, { "TilesTilled", "Tiles tilled" }, { "TilesWatered", "Tiles watered" }, { "MutationsHarvested", "Mutated crops" }, { "CombosHarvested", "Combo mutations" }, { "PerfectHarvested", "Perfect-quality crops" }, { "MythicHarvested", "Mythic harvests" }, { "LargestCropKg", "Largest crop (kg)" }, { "SeedsBred", "Seeds bred" }, { "HybridsMade", "Hybrids created" } } },
	{ "🐄 Ranching", { { "AnimalProducts", "Animal products" }, { "AnimalsBred", "Animals bred" }, { "AnimalsPetted", "Pets given" }, { "AnimalsOwned", "Animals owned" } } },
	{ "🍯 Crafting", { { "ArtisanMade", "Artisan goods" }, { "ItemsCrafted", "Items crafted" }, { "DishesCooked", "Dishes cooked" }, { "SecretRecipes", "Secret recipes" }, { "MachineUpgrades", "Machine upgrades" } } },
	{ "🎣 Outdoors", { { "FishCaught", "Fish caught" }, { "LegendaryFish", "Legendary fish" }, { "BiggestFish", "Biggest fish (cm)" }, { "BugsCaught", "Bugs caught" }, { "ForageCollected", "Wild finds" }, { "RocksMined", "Rocks mined" }, { "TreesChopped", "Trees chopped" }, { "SpotsDug", "Spots dug" }, { "TreasuresFished", "Treasures fished" }, { "SecretsFound", "Secrets found" }, { "SignpostsFound", "Signposts found" } } },
	{ "💰 Trading", { { "CoinsEarned", "Coins earned" }, { "CoinsSpent", "Coins spent" }, { "ItemsSold", "Items sold" }, { "ItemsShipped", "Items shipped" }, { "HighestSale", "Best single sale (each)" }, { "ContractsDone", "Contracts done" }, { "ExportsShipped", "Exports shipped" }, { "StallSales", "Stall sales" }, { "DockSales", "Dock income" } } },
	{ "🏘️ Village", { { "QuestsCompleted", "Quests completed" }, { "DailiesCompleted", "Daily requests" }, { "GiftsGiven", "Gifts given" }, { "Conversations", "Conversations" }, { "NpcsAtMaxHearts", "Best friends" }, { "Donations", "Museum donations" }, { "ProjectContributions", "Project contributions" }, { "FestivalsAttended", "Festivals attended" }, { "ContestEntries", "Contest entries" } } },
	{ "🤝 Social", { { "FarmVisitors", "Farm visitors" }, { "FarmsVisited", "Farms visited" }, { "CropsHarvestedForOthers", "Crops harvested for friends" }, { "CropsWateredForOthers", "Crops watered for friends" }, { "GuildContributed", "Co-op contributions" } } },
	{ "🏡 Estate", { { "ParcelsOwned", "Parcels owned" }, { "HouseLevel", "House level" }, { "ObjectsOnFarm", "Objects on farm" }, { "FarmAppeal", "Farm appeal" }, { "DailyStreakBest", "Best daily streak" }, { "CollectionPercent", "Collection %" } } },
}

local SLOTS = { "Title", "Banner", "Frame", "Effect", "Nameplate", "Companion", "Music", "House", "Fence", "Path", "Tools" }
local SLOT_ICONS = { Title = "🏷️", Banner = "🚩", Frame = "🖼️", Effect = "✨", Nameplate = "📛", Companion = "🦊", Music = "🎵", House = "🏠", Fence = "🚧", Path = "🛤️", Tools = "🛠️" }

-- Owned options for a cosmetic slot.
local function options(profile: any, slot: string): { string }
	local out = {}
	if slot == "Title" then
		for title in profile.Titles or {} do
			table.insert(out, title)
		end
	else
		for key in (profile.Cosmetics and profile.Cosmetics.Owned) or {} do
			local prefix, id = string.match(key, "^(%a+):(.+)$")
			if prefix == slot then
				table.insert(out, id)
			elseif not prefix then
				local def = Store.Cosmetics[key]
				if def and def.Slot == slot then
					table.insert(out, key)
				end
			end
		end
	end
	table.sort(out)
	return out
end

local function cosmeticName(slot: string, id: string): string
	local def = Store.Cosmetics[id]
	if def then
		return def.Name
	end
	return (string.gsub(id, "_", " "))
end

return {
	Id = "Profile",
	Title = "Profile",
	Icon = "🪪",
	Size = Vector2.new(960, 620),
	Watch = { "Stats", "Cosmetics", "Titles", "Public", "Skills", "Showcase" },
	Build = function(win, ctx)
		local args = ctx.Args or {}
		local me = Players.LocalPlayer
		local userId = tonumber(args.UserId) or me.UserId
		local mine = userId == me.UserId
		local content = win.Content :: Frame
		local current = args.Tab or "Card"
		local card: any = nil
		local render: () -> ()
		local tabList = { { Id = "Card", Label = "Card", Icon = "🪪" } }
		if mine then
			table.insert(tabList, { Id = "Stats", Label = "Statistics", Icon = "📊" })
			table.insert(tabList, { Id = "Wardrobe", Label = "Wardrobe", Icon = "👒" })
		end
		local tabs = Kit.Tabs(tabList, function(id)
			current = id
			render()
		end)
		tabs.Frame.Parent = content
		local body = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -46), Position = UDim2.fromOffset(0, 46), Parent = content })

		local function fetch()
			local ok, result = Net.Request("ProfileGet", userId)
			if ok then
				card = result
				if current == "Card" then
					render()
				end
			else
				C.Notify.Toast(tostring(result), "Warning")
			end
		end

		local function renderCard()
			if not card then
				Kit.Empty("Loading…").Parent = body
				return
			end
			win.Title.Text = "🪪  " .. card.Name
			local left = Kit.Panel({ Size = UDim2.new(0.42, -6, 1, 0), Color = "PanelAlt" })
			left.Parent = body
			Kit.Padding(left, 14, 16)
			Kit.List(left, "Y", 6)
			local banner = Kit.new("Frame", { BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 56), Parent = left })
			Kit.Paint(banner, "BackgroundColor3", "HeaderA")
			Kit.Corner(banner, 10)
			Kit.Gradient(banner, "HeaderA", "HeaderB", 0)
			local bannerText = Kit.Label((if card.Banner then "🚩 " .. tostring(card.Banner) .. "   " else "") .. "Estate " .. card.Estate, { Size = Theme.Sizes.Small, Color = "HeaderText", Align = "Center", Font = Theme.Fonts.Bold })
			bannerText.Size = UDim2.fromScale(1, 1)
			bannerText.Parent = banner
			local name = Kit.Heading(card.Name, 24)
			name.LayoutOrder = 1
			name.Parent = left
			local title = Kit.Label((if card.Title then "🏷️ " .. card.Title .. "   " else "") .. (if card.FarmName ~= "" then "🏡 " .. card.FarmName else ""), { Size = Theme.Sizes.Small, Color = "Accent" })
			title.LayoutOrder = 2
			title.Parent = left
			local bio = Kit.Label(if card.Bio ~= "" then "“" .. card.Bio .. "”" else (if mine then "Add a bio below." else ""), { Size = Theme.Sizes.Small, Wrap = true, Color = "SubText" })
			bio.LayoutOrder = 3
			bio.Parent = left
			local facts = Kit.Label(string.format("📖 %.1f%% of the collection\n🏅 %d achievements\n🗓️ Farming for %d days%s", (card.Collection or 0) * 100, card.Achievements or 0, card.PlayDays or 0, if card.Guild then "\n🤝 " .. card.Guild else ""), { Size = Theme.Sizes.Small, Wrap = true })
			facts.LayoutOrder = 4
			facts.Parent = left
			if mine then
				local box = Kit.TextBox("Write a short bio…", { Text = card.Bio or "", MaxLength = 120 })
				box.LayoutOrder = 5
				box.Parent = left
				local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 6, Parent = left })
				Kit.List(row, "X", 8)
				Kit.Button("Save bio", { Style = "Primary", Size = UDim2.fromOffset(110, 34), TextSize = Theme.Sizes.Small, OnClick = function()
					local ok, err = Net.Request("ProfileSet", "Bio", box.Text)
					if ok then
						fetch()
					else
						C.Notify.Toast(tostring(err), "Warning")
					end
				end }).Parent = row
				local hideWrap = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(170, 34), LayoutOrder = 1, Parent = row })
				local hideLabel = Kit.Label("Hide my stats", { Size = Theme.Sizes.Tiny })
				hideLabel.Size = UDim2.fromOffset(100, 34)
				hideLabel.Parent = hideWrap
				local toggle = Kit.Toggle(C.State.Get("Public", "HideStats") == true, function(on)
					Net.Request("ProfileSet", "HideStats", on)
				end)
				toggle.Position = UDim2.fromOffset(104, 3)
				toggle.Parent = hideWrap
			elseif card.Permission then
				local perm = Social.Permissions.Levels[card.Permission]
				local access = Kit.Label("On their farm you can: " .. (if perm then perm.Icon .. " " .. perm.Name else card.Permission), { Size = Theme.Sizes.Tiny, Color = "SubText", Wrap = true })
				access.LayoutOrder = 5
				access.Parent = left
			end
			local right = Kit.Scroll({ Size = UDim2.new(0.58, -6, 1, 0), Position = UDim2.new(0.42, 6, 0, 0) })
			right.Parent = body
			Kit.List(right, "Y", 8)
			Kit.Heading("Skills", 16).Parent = right
			local skillGrid = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = right })
			local g = Kit.new("UIGridLayout", { CellSize = UDim2.new(0.333, -6, 0, 30), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = skillGrid })
			g.FillDirectionMaxCells = 3
			for i, skill in Skills.List do
				local l = Kit.Label(skill.Icon .. " " .. skill.Name .. " " .. tostring(card.Skills and card.Skills[skill.Id] or 1), { Size = Theme.Sizes.Tiny })
				l.LayoutOrder = i
				l.Parent = skillGrid
			end
			local sh = Kit.Heading("Showcase", 16)
			sh.LayoutOrder = 2
			sh.Parent = right
			local show = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 64), LayoutOrder = 3, Parent = right })
			Kit.List(show, "X", 6)
			for i = 1, Social.Profile.ShowcaseSlots do
				local item = card.Showcase and card.Showcase[tostring(i)]
				local slot = Kit.ItemSlot(60)
				slot.Button.LayoutOrder = i
				slot.Set(if item then { Id = item.Id, N = 1, Q = item.Q, M = item.M, S = item.S } else nil)
				slot.Button.Parent = show
			end
			if card.Stats then
				local st = Kit.Heading("Highlights", 16)
				st.LayoutOrder = 4
				st.Parent = right
				local order = 4
				for key, value in card.Stats do
					order += 1
					local label = Kit.Label(Format.Commas(math.floor(value)) .. "  " .. (string.gsub(key, "(%l)(%u)", "%1 %2")), { Size = Theme.Sizes.Small })
					label.LayoutOrder = order
					label.Parent = right
				end
			else
				local hidden = Kit.Label("🔒 This farmer keeps their stats private.", { Size = Theme.Sizes.Small, Color = "SubText" })
				hidden.LayoutOrder = 4
				hidden.Parent = right
			end
		end

		local function renderStats()
			local profile = C.State.Data()
			local stats = (profile and profile.Stats) or {}
			local scroll = Kit.Scroll({ Size = UDim2.fromScale(1, 1) })
			scroll.Parent = body
			local layout = Kit.new("UIGridLayout", { CellSize = UDim2.new(0.5, -6, 0, 260), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
			layout.FillDirectionMaxCells = 2
			-- Summary card first.
			local summary = Kit.Card(260)
			summary.LayoutOrder = 0
			summary.Parent = scroll
			Kit.List(summary, "Y", 4)
			Kit.Heading("📊 Overview", 16).Parent = summary
			local animals = 0
			for _ in (profile and profile.Farm and profile.Farm.Animals) or {} do
				animals += 1
			end
			local invValue = 0
			for _, stack in (profile and profile.Inventory.Slots) or {} do
				if ItemUtil.Sellable(stack) then
					invValue += ItemUtil.UnitValue(stack) * stack.N
				end
			end
			local lines = {
				"🏡 Estate level " .. (if profile then Stats.EstateLevel(profile) else 1) .. " (total skill levels " .. (if profile then Stats.TotalLevels(profile) else 0) .. ")",
				"🪙 " .. Format.Commas(profile and profile.Coins or 0) .. " coins · bag worth ≈ " .. Format.Commas(invValue),
				"🐾 " .. animals .. " animals",
				"⏱️ " .. Format.Duration(profile and profile.PlayTime or 0) .. " played",
				"📅 Farming since " .. Format.Date(profile and profile.Created or os.time()),
			}
			for i, line in lines do
				local l = Kit.Label(line, { Size = Theme.Sizes.Small, Wrap = true })
				l.LayoutOrder = i
				l.Parent = summary
			end
			for gi, group in STAT_GROUPS do
				local cardFrame = Kit.Card(260)
				cardFrame.LayoutOrder = gi
				cardFrame.Parent = scroll
				Kit.List(cardFrame, "Y", 2)
				Kit.Heading(group[1], 16).Parent = cardFrame
				for i, entry in group[2] do
					local value = stats[entry[1]] or 0
					local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = i, Parent = cardFrame })
					local l = Kit.Label(entry[2], { Size = Theme.Sizes.Tiny, Color = "SubText" })
					l.Size = UDim2.new(0.7, 0, 1, 0)
					l.Parent = row
					local v = Kit.Label(if value == math.floor(value) then Format.Commas(value) else string.format("%.1f", value), { Size = Theme.Sizes.Tiny, Font = Theme.Fonts.Number, Align = "Right" })
					v.Size = UDim2.new(0.3, 0, 1, 0)
					v.Position = UDim2.fromScale(0.7, 0)
					v.Parent = row
				end
			end
		end

		local function renderWardrobe()
			local profile = C.State.Data()
			if not profile then
				return
			end
			local equipped = profile.Cosmetics.Equipped or {}
			local list = Kit.Scroll({ Size = UDim2.fromScale(1, 1) })
			list.Parent = body
			Kit.List(list, "Y", 6)
			local intro = Kit.Label("Everything here is cosmetic. Titles come from skills and achievements; other looks from festivals, achievements and the store.", { Size = Theme.Sizes.Small, Color = "SubText", Wrap = true })
			intro.Parent = list
			for i, slot in SLOTS do
				local owned = options(profile, slot)
				local names = { "(none)" }
				local byName: { [string]: string } = {}
				for _, id in owned do
					local name = cosmeticName(slot, id)
					table.insert(names, name)
					byName[name] = id
				end
				local current2 = equipped[slot]
				local currentName = if current2 then cosmeticName(slot, current2) else "(none)"
				local widget: GuiObject
				if #owned == 0 then
					widget = Kit.Label("none yet", { Size = Theme.Sizes.Tiny, Color = "SubText", Align = "Right" })
				else
					widget = Kit.Choice(names, currentName, function(name)
						local ok, err = Net.Request("CosmeticEquip", slot, byName[name])
						if not ok then
							C.Notify.Toast(tostring(err), "Warning")
						end
					end)
				end
				local row = Kit.Row(SLOT_ICONS[slot] .. " " .. slot, widget, #owned .. " owned")
				row.LayoutOrder = i
				row.Parent = list
			end
			local store = Kit.Button("🛍️ Visit the store", { Style = "Secondary", Size = UDim2.fromOffset(200, 36), TextSize = Theme.Sizes.Small, LayoutOrder = 99, OnClick = function()
				C.Windows.Open("Store")
			end })
			store.Parent = list
		end

		render = function()
			Kit.Clear(body)
			if current == "Card" then
				renderCard()
			elseif current == "Stats" then
				renderStats()
			else
				renderWardrobe()
			end
			Kit.RepaintGradients(body)
		end
		tabs.Select(current)
		task.spawn(fetch)
		return {
			Refresh = function()
				if current ~= "Card" then
					render()
				end
			end,
		}
	end,
}

-- The creature inventory, comet cores, the collection book and the
-- discovery odds, in one tabbed panel.
--
--   Creatures  grid of portraits (rarity frame, mutation tag, production,
--              deployed / locked / favourite marks) with sorting and filters,
--              and a detail view: big turning preview, stats, place/withdraw,
--              favourite, lock and release (with confirmation)
--   Cores      sealed comet cores waiting to be opened
--   Collection every species: discovered ones in colour with counts and
--              mutations seen; undiscovered ones as silhouettes
--   Odds       the exact rarity and mutation probabilities the server uses
--
-- Portraits are created only for cards scrolled into view.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BiomeDefinitions = require(Shared.BiomeDefinitions)
local CreatureDefinitions = require(Shared.CreatureDefinitions)
local EconomyMath = require(Shared.EconomyMath)
local Format = require(Shared.Format)
local GameConfig = require(Shared.GameConfig)
local RarityConfig = require(Shared.RarityConfig)
local RemoteDefinitions = require(Shared.RemoteDefinitions)
local UITheme = require(Shared.UITheme)

local InventoryController = {}

local SORTS = { "Rarity", "Production", "Name", "Newest", "Bond", "Mutation" }
local FILTERS = { "All", "Deployed", "Favorites", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

local controllers: { [string]: any } = {}
local Components: any
local panel: any
local tabSelect: (string) -> ()
local currentTab = "Creatures"
local pages: { [string]: Frame } = {}
local sortIndex = 1
local filterIndex = 1
local selectedId: string? = nil
local dirty = true

-- Creatures tab
local grid: ScrollingFrame
local sortButton: any
local filterButton: any
local countLabel: TextLabel
local detail: Frame
local detailPortraitHolder: Frame
local detailPortrait: any = nil
local stopDetailSpin: (() -> ())? = nil
local detailName: TextLabel
local detailTags: Frame
local detailStats: TextLabel
local detailDesc: TextLabel
local deployButton: any
local favoriteButton: any
local lockButton: any
local releaseButton: any
local releaseArmed = false
local cards: { [string]: GuiObject } = {}
local portraits: { [Frame]: any } = {}

-- Cores / collection / odds
local coreList: ScrollingFrame
local collectionGrid: ScrollingFrame
local collectionLabel: TextLabel
local collectionBuilt = false
local oddsBody: Frame

local function invoke(name: string, ...: any): any
	local args = table.pack(...)
	local ok, result = pcall(function()
		return RemoteDefinitions.GetFunction(name):InvokeServer(table.unpack(args, 1, args.n))
	end)
	if ok and type(result) == "table" then
		return result
	end
	return { Ok = false, Reason = "ServerError" }
end

local function speciesOf(creature: any): CreatureDefinitions.Species?
	return CreatureDefinitions.Get(creature.Species)
end

local function rarityIndex(creature: any): number
	local species = speciesOf(creature)
	return if species then RarityConfig.RarityIndex(species.Rarity) else 0
end

-- Creatures list -------------------------------------------------------------------

local function sortedCreatures(): { any }
	local state = controllers.ClientState
	local list = {}
	local filter = FILTERS[filterIndex]
	for _, creature in state.Creatures() do
		local species = speciesOf(creature)
		local keep = true
		if filter == "Deployed" then
			keep = state.SlotOf(creature.Id) ~= nil
		elseif filter == "Favorites" then
			keep = creature.Favorite == true
		elseif filter ~= "All" then
			keep = species ~= nil and species.Rarity == filter
		end
		if keep then
			table.insert(list, creature)
		end
	end
	local sort = SORTS[sortIndex]
	table.sort(list, function(a, b)
		if sort == "Rarity" then
			local ra, rb = rarityIndex(a), rarityIndex(b)
			if ra ~= rb then
				return ra > rb
			end
		elseif sort == "Production" then
			local pa, pb = EconomyMath.CreatureIncome(a), EconomyMath.CreatureIncome(b)
			if pa ~= pb then
				return pa > pb
			end
		elseif sort == "Name" then
			local na = (speciesOf(a) or { DisplayName = a.Species }).DisplayName
			local nb = (speciesOf(b) or { DisplayName = b.Species }).DisplayName
			if na ~= nb then
				return na < nb
			end
		elseif sort == "Newest" then
			if a.Obtained ~= b.Obtained then
				return a.Obtained > b.Obtained
			end
		elseif sort == "Bond" then
			if a.Bond ~= b.Bond then
				return a.Bond > b.Bond
			end
		elseif sort == "Mutation" then
			local ma = RarityConfig.Mutations[a.Mutation]
			local mb = RarityConfig.Mutations[b.Mutation]
			local ia, ib = if ma then ma.Index else 0, if mb then mb.Index else 0
			if ia ~= ib then
				return ia > ib
			end
		end
		return a.Id < b.Id
	end)
	return list
end

local function releasePortrait(holder: Frame)
	local portrait = portraits[holder]
	if portrait then
		portrait.Destroy()
		portraits[holder] = nil
	end
end

-- Only cards near the visible area get a 3D portrait.
local function updateVisiblePortraits()
	local top = grid.AbsolutePosition.Y - 120
	local bottom = grid.AbsolutePosition.Y + grid.AbsoluteSize.Y + 120
	for _, card in cards do
		local holder = card:FindFirstChild("PortraitHolder") :: Frame
		local y = card.AbsolutePosition.Y
		local visible = card.Visible and y + card.AbsoluteSize.Y >= top and y <= bottom
		if visible and not portraits[holder] then
			local species = card:GetAttribute("Species") :: string
			portraits[holder] =
				controllers.Viewport.Creature(holder, species, { Mutation = card:GetAttribute("Mutation") :: string })
		elseif not visible and portraits[holder] then
			releasePortrait(holder)
		end
	end
end

local function buildCard(creature: any, order: number): GuiObject
	local Make = Components.Make
	local species = speciesOf(creature)
	local rarity = if species then species.Rarity else "Common"
	local color = UITheme.RarityColor(rarity)
	local card = Make("TextButton", {
		Name = creature.Id,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		BackgroundColor3 = UITheme.Colors.PanelRaised,
		Parent = grid,
	})
	card:SetAttribute("Species", creature.Species)
	card:SetAttribute("Mutation", creature.Mutation)
	Components.Corner(14).Parent = card
	local stroke = Components.Stroke(color, 2, 0.35)
	stroke.Parent = card
	Make("UIGradient", {
		Color = ColorSequence.new(color:Lerp(UITheme.Colors.Panel, 0.75), UITheme.Colors.PanelSunken),
		Rotation = 90,
		Parent = card,
	})
	Make(
		"Frame",
		{ Name = "PortraitHolder", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -38), Parent = card }
	)
	Components.Label({
		Text = if species then species.DisplayName else creature.Species,
		Font = UITheme.Fonts.Heading,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, -8, 0, 18),
		Position = UDim2.new(0, 4, 1, -38),
		Parent = card,
	})
	Components.Label({
		Text = `✦ {Format.Rate(EconomyMath.CreatureIncome(creature))}/s`,
		Font = UITheme.Fonts.Bold,
		TextSize = 12,
		TextColor3 = UITheme.Colors.Gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.new(0, 0, 1, -20),
		Parent = card,
	})
	local marks = {}
	if controllers.ClientState.SlotOf(creature.Id) then
		table.insert(marks, "🏡")
	end
	if creature.Favorite then
		table.insert(marks, "★")
	end
	if creature.Locked then
		table.insert(marks, "🔒")
	end
	if #marks > 0 then
		Components.Label({
			Text = table.concat(marks, " "),
			Font = UITheme.Fonts.Heading,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.new(1, -8, 0, 18),
			Position = UDim2.fromOffset(0, 4),
			Parent = card,
		})
	end
	if creature.Mutation ~= "Standard" then
		local tag = Components.Tag(creature.Mutation, UITheme.MutationColor(creature.Mutation), card)
		tag.Position = UDim2.fromOffset(6, 6)
		tag.TextSize = 11
		tag.Size = UDim2.fromOffset(0, 18)
	end
	card.Activated:Connect(function()
		InventoryController.Select(creature.Id)
	end)
	card.SelectionGained:Connect(function()
		stroke.Transparency = 0
	end)
	card.SelectionLost:Connect(function()
		stroke.Transparency = 0.35
	end)
	return card
end

local function rebuildGrid()
	for holder in portraits do
		releasePortrait(holder)
	end
	for _, card in cards do
		card:Destroy()
	end
	cards = {}
	local oldEmpty = grid:FindFirstChild("Empty")
	if oldEmpty then
		oldEmpty:Destroy()
	end
	local list = sortedCreatures()
	for i, creature in list do
		cards[creature.Id] = buildCard(creature, i)
	end
	local total = 0
	for _ in controllers.ClientState.Creatures() do
		total += 1
	end
	countLabel.Text = `{total} / {GameConfig.Inventory.MaxCreatures}`
	countLabel.TextColor3 = if total >= GameConfig.Inventory.MaxCreatures
		then UITheme.Colors.Coral
		else UITheme.Colors.Muted
	task.defer(updateVisiblePortraits)
	if #list == 0 then
		Components.Label({
			Name = "Empty",
			Text = if total == 0
				then "No creatures yet — capture a comet to find your first!"
				else "Nothing matches this filter.",
			TextColor3 = UITheme.Colors.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 60),
			LayoutOrder = 1,
			Parent = grid,
		})
	end
end

local function renderDetail()
	local creature = selectedId and controllers.ClientState.Creatures()[selectedId]
	detail.Visible = creature ~= nil
	if stopDetailSpin then
		stopDetailSpin()
		stopDetailSpin = nil
	end
	if detailPortrait then
		detailPortrait.Destroy()
		detailPortrait = nil
	end
	if not creature then
		return
	end
	local species = speciesOf(creature)
	local rarity = if species then species.Rarity else "Common"
	detailPortrait =
		controllers.Viewport.Creature(detailPortraitHolder, creature.Species, { Mutation = creature.Mutation })
	stopDetailSpin = controllers.Viewport.Spin(detailPortrait, 25)
	detailName.Text = if species then species.DisplayName else creature.Species
	detailName.TextColor3 = if rarity == "Common" then UITheme.Colors.Text else UITheme.RarityColor(rarity)
	for _, child in detailTags:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	Components.Tag(string.upper(rarity), UITheme.RarityColor(rarity), detailTags).LayoutOrder = 1
	if creature.Mutation ~= "Standard" then
		Components.Tag(creature.Mutation, UITheme.MutationColor(creature.Mutation), detailTags).LayoutOrder = 2
	end
	local slot = controllers.ClientState.SlotOf(creature.Id)
	local biome = BiomeDefinitions.Get(creature.Biome)
	detailStats.Text = table.concat({
		`✦ {Format.Rate(EconomyMath.CreatureIncome(creature))}/s when deployed`,
		`Bond Lv {creature.Bond} / {GameConfig.Creatures.MaxBond}`,
		if slot then `In habitat {slot}` else "In storage",
		`Found in {if biome then biome.DisplayName else creature.Biome} · {os.date("!%b %d", creature.Obtained)}`,
	}, "\n")
	detailDesc.Text = if species then species.Description else ""
	deployButton:SetText(if slot then "Withdraw" else "Place in Habitat")
	deployButton:SetStyle(if slot then "Secondary" else "Primary")
	favoriteButton:SetText(if creature.Favorite then "★ Favorited" else "☆ Favorite")
	lockButton:SetText(if creature.Locked then "🔒 Locked" else "🔓 Lock")
	releaseArmed = false
	local protected = creature.Locked or creature.Favorite or slot ~= nil
	releaseButton:SetEnabled(not protected)
	releaseButton:SetText(
		if protected then "Protected" else `Release · +{Format.Short(EconomyMath.ReleaseValue(creature))} ✦`
	)
	releaseButton:SetStyle("Ghost")
end

function InventoryController.Select(creatureId: string?)
	selectedId = creatureId
	renderDetail()
end

local function buildCreaturesPage(page: Frame)
	local Make = Components.Make
	local toolbar = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), Parent = page })
	sortButton = Components.Button("Sort: Rarity", "Secondary", UDim2.fromOffset(170, 38), toolbar)
	filterButton = Components.Button("Show: All", "Secondary", UDim2.fromOffset(170, 38), toolbar)
	filterButton.Instance.Position = UDim2.fromOffset(180, 0)
	countLabel = Components.Label({
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = UITheme.Colors.Muted,
		Size = UDim2.new(0, 120, 1, 0),
		Position = UDim2.new(1, -120, 0, 0),
		Parent = toolbar,
	})
	sortButton.Activated:Connect(function()
		sortIndex = sortIndex % #SORTS + 1
		sortButton:SetText(`Sort: {SORTS[sortIndex]}`)
		rebuildGrid()
	end)
	filterButton.Activated:Connect(function()
		filterIndex = filterIndex % #FILTERS + 1
		filterButton:SetText(`Show: {FILTERS[filterIndex]}`)
		rebuildGrid()
	end)

	grid = Make("ScrollingFrame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(0.58, -8, 1, -48),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = UITheme.Colors.Stroke,
		Parent = page,
	})
	Make("UIGridLayout", {
		CellSize = UDim2.fromOffset(112, 132),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	Components.Padding(4).Parent = grid
	grid:GetPropertyChangedSignal("CanvasPosition"):Connect(updateVisiblePortraits)
	grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateVisiblePortraits)

	detail = Make("Frame", {
		Name = "Detail",
		BackgroundColor3 = UITheme.Colors.PanelSunken,
		Position = UDim2.new(0.58, 4, 0, 48),
		Size = UDim2.new(0.42, -4, 1, -48),
		Visible = false,
		Parent = page,
	})
	Components.Corner(16).Parent = detail
	Components.Padding(12).Parent = detail
	detailPortraitHolder =
		Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0.38, 0), Parent = detail })
	detailName = Components.Label({
		Font = UITheme.Fonts.Display,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromScale(0, 0.38),
		Parent = detail,
	})
	detailTags = Make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 0.38, 32),
		Parent = detail,
	})
	Components.List(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center).Parent = detailTags
	detailStats = Components.Label({
		Font = UITheme.Fonts.Bold,
		TextSize = 14,
		TextColor3 = UITheme.Colors.Text,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 0, 70),
		Position = UDim2.new(0, 0, 0.38, 60),
		Parent = detail,
	})
	detailDesc = Components.Label({
		Font = UITheme.Fonts.Body,
		TextSize = 13,
		TextColor3 = UITheme.Colors.Muted,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 0, 44),
		Position = UDim2.new(0, 0, 0.38, 132),
		Parent = detail,
	})
	local actions = Make("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 132),
		Parent = detail,
	})
	deployButton = Components.Button("Place in Habitat", "Primary", UDim2.new(1, 0, 0, 40), actions)
	favoriteButton = Components.Button("☆ Favorite", "Secondary", UDim2.new(0.5, -4, 0, 38), actions)
	favoriteButton.Instance.Position = UDim2.fromOffset(0, 46)
	lockButton = Components.Button("🔓 Lock", "Secondary", UDim2.new(0.5, -4, 0, 38), actions)
	lockButton.Instance.Position = UDim2.new(0.5, 4, 0, 46)
	releaseButton = Components.Button("Release", "Ghost", UDim2.new(1, 0, 0, 38), actions)
	releaseButton.Instance.Position = UDim2.fromOffset(0, 92)

	deployButton.Activated:Connect(function()
		local id = selectedId
		if not id then
			return
		end
		local slot = controllers.ClientState.SlotOf(id)
		if slot then
			local result = invoke("RemoveCreature", slot)
			if not result.Ok then
				controllers.NotificationController.Toast("Couldn't withdraw that creature.", "⚠️")
			end
		else
			controllers.SanctuaryController.PickSlotFor(id)
		end
	end)
	favoriteButton.Activated:Connect(function()
		local creature = selectedId and controllers.ClientState.Creatures()[selectedId]
		if creature then
			invoke("SetCreatureFlag", creature.Id, "Favorite", not creature.Favorite)
		end
	end)
	lockButton.Activated:Connect(function()
		local creature = selectedId and controllers.ClientState.Creatures()[selectedId]
		if creature then
			invoke("SetCreatureFlag", creature.Id, "Locked", not creature.Locked)
		end
	end)
	releaseButton.Activated:Connect(function()
		local creature = selectedId and controllers.ClientState.Creatures()[selectedId]
		if not creature then
			return
		end
		if not releaseArmed then
			-- Two-step confirmation: the button turns red and asks again.
			releaseArmed = true
			releaseButton:SetStyle("Danger")
			local species = speciesOf(creature)
			releaseButton:SetText(`Release {if species then species.DisplayName else "it"} for good?`)
			task.delay(4, function()
				if releaseArmed and selectedId == creature.Id then
					renderDetail()
				end
			end)
			return
		end
		releaseArmed = false
		local result = invoke("ReleaseCreature", creature.Id)
		if result.Ok then
			controllers.NotificationController.Toast(`Released. +{Format.Number(result.Stardust)} Stardust`, "🌌")
			selectedId = nil
		else
			controllers.NotificationController.Toast("That creature is protected or busy.", "🔒")
		end
	end)
end

-- Cores ---------------------------------------------------------------------------------

local function rebuildCores()
	for _, child in coreList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local cores = {}
	for _, core in controllers.ClientState.Get("Cores") or {} do
		table.insert(cores, core)
	end
	table.sort(cores, function(a, b)
		return a.Obtained < b.Obtained
	end)
	if #cores == 0 then
		Components.Label({
			Text = "No sealed cores. Capture comets to collect them!",
			TextColor3 = UITheme.Colors.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 60),
			Parent = coreList,
		})
		return
	end
	for i, core in cores do
		local row = Components.Make("Frame", {
			BackgroundColor3 = UITheme.Colors.PanelRaised,
			Size = UDim2.new(1, -8, 0, 58),
			LayoutOrder = i,
			Parent = coreList,
		})
		Components.Corner(14).Parent = row
		local cometType = GameConfig.Comets.Types[core.CometType]
		local biome = BiomeDefinitions.Get(core.Biome)
		Components.Label({
			Text = `☄️  {if core.Kind == "Starter"
				then "Guiding"
				else (if cometType then cometType.DisplayName else "")} Comet Core`,
			Font = UITheme.Fonts.Heading,
			Size = UDim2.new(1, -170, 0, 24),
			Position = UDim2.fromOffset(14, 6),
			Parent = row,
		})
		Components.Label({
			Text = `From {if biome then biome.DisplayName else core.Biome} · {math.floor(core.Quality * 100)}% stable`,
			Font = UITheme.Fonts.Body,
			TextSize = 13,
			TextColor3 = UITheme.Colors.Muted,
			Size = UDim2.new(1, -170, 0, 20),
			Position = UDim2.fromOffset(14, 30),
			Parent = row,
		})
		local open = Components.Button("Open", "Gold", UDim2.fromOffset(140, 42), row)
		open.Instance.AnchorPoint = Vector2.new(1, 0.5)
		open.Instance.Position = UDim2.new(1, -8, 0.5, 0)
		open.Activated:Connect(function()
			open:SetLoading(true)
			controllers.RevealController.Open(core.Id)
		end)
	end
end

-- Collection -----------------------------------------------------------------------------

local function rebuildCollection()
	local discovered = controllers.ClientState.Get("DiscoveredSpecies") or {}
	local owned: { [string]: number } = {}
	for _, creature in controllers.ClientState.Creatures() do
		owned[creature.Species] = (owned[creature.Species] or 0) + 1
	end
	local found = 0
	for _ in discovered do
		found += 1
	end
	local total = #CreatureDefinitions.Order
	collectionLabel.Text = `{found} / {total} species discovered · {math.floor(found / total * 100)}% complete`
	if collectionBuilt then
		for _, child in collectionGrid:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end
	collectionBuilt = true
	for i, speciesId in CreatureDefinitions.Order do
		local species = CreatureDefinitions.Species[speciesId]
		local entry = discovered[speciesId]
		local color = UITheme.RarityColor(species.Rarity)
		local card = Components.Make("Frame", {
			Name = speciesId,
			LayoutOrder = i,
			BackgroundColor3 = UITheme.Colors.PanelRaised,
			Parent = collectionGrid,
		})
		Components.Corner(14).Parent = card
		Components.Stroke(if entry then color else UITheme.Colors.Stroke, 2, if entry then 0.3 else 0.6).Parent = card
		local holder =
			Components.Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -40), Parent = card })
		controllers.Viewport.Creature(holder, speciesId, { Silhouette = entry == nil })
		Components.Label({
			Text = if entry then species.DisplayName else "???",
			Font = UITheme.Fonts.Heading,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Size = UDim2.new(1, -6, 0, 18),
			Position = UDim2.new(0, 3, 1, -40),
			Parent = card,
		})
		local mutations = {}
		if entry then
			for _, mutation in RarityConfig.MutationOrder do
				if entry.Mutations and entry.Mutations[mutation] and mutation ~= "Standard" then
					table.insert(mutations, string.sub(mutation, 1, 1))
				end
			end
		end
		Components.Label({
			Text = if entry
				then `{species.Rarity} · owned {owned[speciesId] or 0}{if #mutations > 0
					then " · " .. table.concat(mutations)
					else ""}`
				else species.Rarity,
			Font = UITheme.Fonts.Bold,
			TextSize = 11,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 16),
			Position = UDim2.new(0, 0, 1, -21),
			Parent = card,
		})
	end
end

-- Odds -----------------------------------------------------------------------------------

local function buildOdds(page: Frame)
	oddsBody = Components.Make("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = page,
	})
	Components.List(Enum.FillDirection.Vertical, 6).Parent = oddsBody
	local function line(text: string, color: Color3?, font: Enum.Font?, size: number?)
		Components.Label({
			Text = text,
			Font = font or UITheme.Fonts.Bold,
			TextSize = size or 16,
			TextColor3 = color or UITheme.Colors.Text,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, -10, 0, 20),
			Parent = oddsBody,
		})
	end
	line("Discovery odds", UITheme.Colors.Lavender, UITheme.Fonts.Display, 22)
	line(
		"Every comet core rolls a rarity, then a species from the biome it came from, then a mutation. Capture quality, comet type, equipment and settings never change these odds.",
		UITheme.Colors.Muted,
		UITheme.Fonts.Body,
		14
	)
	for _, odd in RarityConfig.GetRarityOdds() do
		line(
			`{odd.Id}  ·  {Format.Percent(odd.Chance)}  ·  ✦ {RarityConfig.Rarities[odd.Id].BaseRate}/s base`,
			UITheme.RarityColor(odd.Id)
		)
	end
	line("Mutations (independent of rarity)", UITheme.Colors.Lavender, UITheme.Fonts.Display, 20)
	for _, odd in RarityConfig.GetMutationOdds() do
		local def = RarityConfig.Mutations[odd.Id]
		line(
			`{odd.Id}  ·  {Format.Percent(odd.Chance)}  ·  +{math.floor(def.Bonus * 100)}% Stardust  —  {def.Description}`,
			UITheme.MutationColor(odd.Id),
			UITheme.Fonts.Bold,
			14
		)
	end
	line("Dawn Commons species", UITheme.Colors.Lavender, UITheme.Fonts.Display, 20)
	for _, rarity in RarityConfig.Order do
		local names = {}
		for _, id in CreatureDefinitions.Pool("DawnCommons", rarity) do
			table.insert(names, CreatureDefinitions.Species[id].DisplayName)
		end
		line(
			`{rarity}: {table.concat(names, ", ")} (equal chance within the rarity)`,
			UITheme.RarityColor(rarity),
			UITheme.Fonts.Body,
			14
		)
	end
end

-- Panel -----------------------------------------------------------------------------------

local function refresh()
	if not panel or not controllers.PanelManager.IsOpen("Inventory") then
		dirty = true
		return
	end
	dirty = false
	if currentTab == "Creatures" then
		rebuildGrid()
		renderDetail()
	elseif currentTab == "Cores" then
		rebuildCores()
	elseif currentTab == "Collection" then
		rebuildCollection()
	end
end

local function showTab(name: string)
	currentTab = name
	for tabName, page in pages do
		page.Visible = tabName == name
	end
	dirty = true
	refresh()
end

function InventoryController.Open(tab: string?, creatureId: string?)
	controllers.PanelManager.Open("Inventory")
	tabSelect(tab or currentTab)
	if creatureId then
		InventoryController.Select(creatureId)
	end
end

function InventoryController.Toggle(tab: string)
	if controllers.PanelManager.IsOpen("Inventory") and currentTab == tab then
		controllers.PanelManager.Close()
	else
		InventoryController.Open(tab)
	end
end

function InventoryController.Init(registry: { [string]: any })
	controllers = registry
end

function InventoryController.Start()
	Components = controllers.Components
	local Make = Components.Make
	panel = Components.Panel("Creatures", Vector2.new(900, 600), controllers.PanelManager.Gui())
	local body = panel.Body
	local tabs
	tabs, tabSelect = Components.Tabs({ "Creatures", "Cores", "Collection", "Odds" }, showTab, body)
	tabs.Size = UDim2.new(1, 0, 0, 42)
	for _, name in { "Creatures", "Cores", "Collection", "Odds" } do
		pages[name] = Make("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 52),
			Size = UDim2.new(1, 0, 1, -52),
			Visible = false,
			Parent = body,
		})
	end
	buildCreaturesPage(pages.Creatures)
	coreList = Make("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = pages.Cores,
	})
	Components.List(Enum.FillDirection.Vertical, 8).Parent = coreList
	collectionLabel = Components.Label({
		Text = "",
		TextColor3 = UITheme.Colors.Muted,
		Size = UDim2.new(1, 0, 0, 24),
		Parent = pages.Collection,
	})
	collectionGrid = Make("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 1, -30),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = pages.Collection,
	})
	Make("UIGridLayout", {
		CellSize = UDim2.fromOffset(120, 140),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = collectionGrid,
	})
	buildOdds(pages.Odds)

	controllers.PanelManager.Register("Inventory", panel, function()
		panel.Title.Text = "Creatures"
		if dirty then
			refresh()
		end
	end, function()
		for holder in portraits do
			releasePortrait(holder)
		end
		if stopDetailSpin then
			stopDetailSpin()
			stopDetailSpin = nil
		end
		dirty = true
	end)

	local state = controllers.ClientState
	for _, key in { "Creatures", "EquippedCreatures", "Cores", "DiscoveredSpecies" } do
		state.Changed:Connect(function(root, changed)
			if root == "Profile" and changed == key then
				refresh()
			end
		end)
	end
	showTab("Creatures")
	tabSelect("Creatures")
end

return InventoryController

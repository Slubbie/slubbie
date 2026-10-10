-- The player's own sanctuary, on the client: habitat prompts only work on
-- your own plot, pads glow green/amber/grey while you're choosing where to
-- place a creature, and two pickers make placement quick on any device:
--
--   PickSlotFor(creatureId)  "where should this creature live?" — habitat grid
--   OnPadPrompt(prompt)      "who should live here?" — creature list for that pad
--
-- Every choice is confirmed and then sent to the server, which validates it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreatureDefinitions = require(Shared.CreatureDefinitions)
local EconomyMath = require(Shared.EconomyMath)
local Format = require(Shared.Format)
local RemoteDefinitions = require(Shared.RemoteDefinitions)
local UITheme = require(Shared.UITheme)
local UpgradeDefinitions = require(Shared.UpgradeDefinitions)
local WorldLayout = require(Shared.WorldLayout)

local SanctuaryController = {}

local controllers: { [string]: any } = {}
local Components: any
local slotPanel: any
local slotGrid: Frame
local creaturePanel: any
local creatureList: ScrollingFrame
local pendingCreature: string? = nil
local pendingSlot: number? = nil
local highlights: { Highlight } = {}
local beacon: BasePart? = nil

local function myPlot(): number?
	return controllers.ClientState.GetSession("PlotIndex")
end

local function unlockedSlots(): number
	return UpgradeDefinitions.HabitatSlots(controllers.ClientState.Equipment().HabitatLevel or 1)
end

local function speciesName(creature: any): string
	local species = CreatureDefinitions.Get(creature.Species)
	return if species then species.DisplayName else creature.Species
end

-- Only your own plot's prompts are usable on your screen.
local function configurePad(pad: Instance)
	local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		return
	end
	local mine = pad:GetAttribute("PlotIndex") == myPlot()
	prompt:SetAttribute("Mine", mine)
	if not mine then
		prompt.Enabled = false
	end
	if not prompt:GetAttribute("Watched") then
		-- The server re-enables prompts as pads change; keep other plots' prompts off here.
		prompt:SetAttribute("Watched", true)
		prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
			if prompt.Enabled and prompt:GetAttribute("Mine") ~= true then
				prompt.Enabled = false
			end
		end)
	end
end

local function refreshPads()
	for _, pad in CollectionService:GetTagged("HabitatPad") do
		configurePad(pad)
	end
end

local function clearHighlights()
	for _, highlight in highlights do
		highlight:Destroy()
	end
	highlights = {}
end

-- Green: empty and ready. Amber: occupied (placing swaps). Grey: locked.
local function highlightPads()
	clearHighlights()
	local index = myPlot()
	if not index then
		return
	end
	local equipped = controllers.ClientState.Equipped()
	for _, pad in CollectionService:GetTagged("HabitatPad") do
		if pad:GetAttribute("PlotIndex") ~= index then
			continue
		end
		local slot = pad:GetAttribute("Slot") :: number
		local color = if slot > unlockedSlots()
			then UITheme.Colors.Dim
			elseif equipped[tostring(slot)] then UITheme.Colors.Gold
			else UITheme.Colors.Green
		local highlight = Instance.new("Highlight")
		highlight.Adornee = pad
		highlight.FillColor = color
		highlight.OutlineColor = color
		highlight.FillTransparency = 0.55
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = pad
		table.insert(highlights, highlight)
	end
end

local function place(creatureId: string, slot: number)
	local ok, result = pcall(function()
		return RemoteDefinitions.GetFunction("EquipCreature"):InvokeServer(creatureId, slot)
	end)
	if ok and type(result) == "table" and result.Ok then
		controllers.AudioController.Play("Purchase", { Pitch = 1.3 })
		local creature = controllers.ClientState.Creatures()[creatureId]
		if creature then
			controllers.NotificationController.Toast(
				`{speciesName(creature)} moved into habitat {slot}.`,
				"🏡",
				UITheme.Colors.Green
			)
		end
		local index = myPlot()
		if index then
			controllers.EffectsController.Burst(
				WorldLayout.SlotPosition(index, slot) + Vector3.new(0, 2, 0),
				UITheme.Colors.Green,
				20,
				"Stars"
			)
		end
	else
		local reason = if ok and type(result) == "table" then result.Reason else nil
		local messages = {
			SlotLocked = "That habitat is locked. Upgrade Habitats in the Workshop.",
			NoSanctuary = "You don't have a sanctuary in this server.",
			NotOwned = "You don't own that creature anymore.",
		}
		controllers.NotificationController.Toast(messages[reason] or "Couldn't place that creature.", "⚠️")
	end
end

local function withdraw(slot: number)
	local ok, result = pcall(function()
		return RemoteDefinitions.GetFunction("RemoveCreature"):InvokeServer(slot)
	end)
	if not ok or type(result) ~= "table" or not result.Ok then
		controllers.NotificationController.Toast("Couldn't withdraw that creature.", "⚠️")
	end
end

-- Habitat grid for a chosen creature -------------------------------------------------

local function renderSlots()
	for _, child in slotGrid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local creatures = controllers.ClientState.Creatures()
	local equipped = controllers.ClientState.Equipped()
	local unlocked = unlockedSlots()
	local creature = pendingCreature and creatures[pendingCreature]
	slotPanel.Title.Text = if creature then `Place {speciesName(creature)}` else "Choose a habitat"
	for slot = 1, #WorldLayout.SlotOffsets do
		local occupantId = equipped[tostring(slot)]
		local occupant = occupantId and creatures[occupantId]
		local locked = slot > unlocked
		local label = if locked
			then `🔒 Habitat {slot}`
			elseif occupant then `{slot}. {speciesName(occupant)}`
			else `{slot}. Empty`
		local style = if locked then "Ghost" elseif occupant then "Secondary" else "Primary"
		local button = Components.Button(label, style, UDim2.fromOffset(0, 0), slotGrid)
		button.Instance.LayoutOrder = slot
		button:SetEnabled(not locked and occupantId ~= pendingCreature)
		if slot == 1 then
			slotPanel.FirstSelectable = button.Instance
		end
		button.Activated:Connect(function()
			local id = pendingCreature
			if not id then
				return
			end
			if occupant then
				-- Confirm a swap with a second click.
				if button.Instance:GetAttribute("Armed") then
					controllers.PanelManager.Close()
					place(id, slot)
				else
					button.Instance:SetAttribute("Armed", true)
					button:SetStyle("Gold")
					button:SetText(`Swap with {speciesName(occupant)}?`)
				end
			else
				controllers.PanelManager.Close()
				place(id, slot)
			end
		end)
	end
	local hint = Components.Label({
		Text = `{unlocked} of {#WorldLayout.SlotOffsets} habitats unlocked · more with Habitat upgrades`,
		Font = UITheme.Fonts.Body,
		TextSize = 14,
		TextColor3 = UITheme.Colors.Muted,
		LayoutOrder = 100,
		Parent = slotGrid,
	})
	hint.Size = UDim2.fromOffset(0, 0)
end

function SanctuaryController.PickSlotFor(creatureId: string)
	if not myPlot() then
		controllers.NotificationController.Toast("You don't have a sanctuary in this server.", "🏡")
		return
	end
	pendingCreature = creatureId
	controllers.PanelManager.Open("HabitatSlots")
end

-- Creature list for a chosen pad ---------------------------------------------------------

local function renderCreatures()
	for _, child in creatureList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local slot = pendingSlot or 1
	local creatures = controllers.ClientState.Creatures()
	local equipped = controllers.ClientState.Equipped()
	local occupantId = equipped[tostring(slot)]
	creaturePanel.Title.Text = `Habitat {slot}`
	local order = 0
	if occupantId and creatures[occupantId] then
		local occupant = creatures[occupantId]
		order += 1
		local row = Components.Make("Frame", {
			BackgroundColor3 = UITheme.Colors.PanelRaised,
			Size = UDim2.new(1, -8, 0, 56),
			LayoutOrder = order,
			Parent = creatureList,
		})
		Components.Corner(12).Parent = row
		Components.Label({
			Text = `Living here: {speciesName(occupant)} · ✦ {Format.Rate(EconomyMath.CreatureIncome(occupant))}/s`,
			Font = UITheme.Fonts.Heading,
			Size = UDim2.new(1, -170, 1, 0),
			Position = UDim2.fromOffset(12, 0),
			Parent = row,
		})
		local out = Components.Button("Withdraw", "Secondary", UDim2.fromOffset(140, 40), row)
		out.Instance.AnchorPoint = Vector2.new(1, 0.5)
		out.Instance.Position = UDim2.new(1, -8, 0.5, 0)
		out.Activated:Connect(function()
			controllers.PanelManager.Close()
			withdraw(slot)
		end)
	end
	local list = {}
	for _, creature in creatures do
		if creature.Id ~= occupantId and CreatureDefinitions.IsSpecies(creature.Species) then
			table.insert(list, creature)
		end
	end
	table.sort(list, function(a, b)
		local ia, ib = EconomyMath.CreatureIncome(a), EconomyMath.CreatureIncome(b)
		if ia ~= ib then
			return ia > ib
		end
		return a.Id < b.Id
	end)
	if #list == 0 then
		order += 1
		Components.Label({
			Text = "No other creatures to place. Capture comets to find more!",
			TextColor3 = UITheme.Colors.Muted,
			Size = UDim2.new(1, 0, 0, 40),
			LayoutOrder = order,
			Parent = creatureList,
		})
	end
	for _, creature in list do
		order += 1
		local species = CreatureDefinitions.Get(creature.Species)
		local rarity = if species then species.Rarity else "Common"
		local row = Components.Make("Frame", {
			BackgroundColor3 = UITheme.Colors.PanelSunken,
			Size = UDim2.new(1, -8, 0, 64),
			LayoutOrder = order,
			Parent = creatureList,
		})
		Components.Corner(12).Parent = row
		Components.Stroke(UITheme.RarityColor(rarity), 1.5, 0.5).Parent = row
		local holder = Components.Make("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(60, 60),
			Position = UDim2.fromOffset(4, 2),
			Parent = row,
		})
		controllers.Viewport.Creature(holder, creature.Species, { Mutation = creature.Mutation })
		local where = controllers.ClientState.SlotOf(creature.Id)
		Components.Label({
			Text = speciesName(creature) .. (if creature.Mutation ~= "Standard" then `  ({creature.Mutation})` else ""),
			Font = UITheme.Fonts.Heading,
			TextColor3 = if rarity == "Common" then UITheme.Colors.Text else UITheme.RarityColor(rarity),
			Size = UDim2.new(1, -230, 0, 24),
			Position = UDim2.fromOffset(72, 8),
			Parent = row,
		})
		Components.Label({
			Text = `{rarity} · ✦ {Format.Rate(EconomyMath.CreatureIncome(creature))}/s{if where
				then ` · in habitat {where}`
				else ""}`,
			Font = UITheme.Fonts.Body,
			TextSize = 13,
			TextColor3 = UITheme.Colors.Muted,
			Size = UDim2.new(1, -230, 0, 20),
			Position = UDim2.fromOffset(72, 34),
			Parent = row,
		})
		local button =
			Components.Button(if where then "Move here" else "Place here", "Primary", UDim2.fromOffset(140, 42), row)
		button.Instance.AnchorPoint = Vector2.new(1, 0.5)
		button.Instance.Position = UDim2.new(1, -8, 0.5, 0)
		if order == 1 then
			creaturePanel.FirstSelectable = button.Instance
		end
		button.Activated:Connect(function()
			controllers.PanelManager.Close()
			place(creature.Id, slot)
		end)
	end
end

function SanctuaryController.OnPadPrompt(prompt: ProximityPrompt)
	local plot = prompt:GetAttribute("PlotIndex")
	local slot = prompt:GetAttribute("Slot")
	if plot ~= myPlot() or type(slot) ~= "number" then
		return
	end
	if slot > unlockedSlots() then
		controllers.NotificationController.Toast("This habitat is locked. Upgrade Habitats in the Workshop.", "🔒")
		return
	end
	pendingSlot = slot
	controllers.PanelManager.Open("HabitatCreatures")
end

-- A soft beacon over your own plot, visible from anywhere.
local function updateBeacon()
	if beacon then
		beacon:Destroy()
		beacon = nil
	end
	local index = myPlot()
	if not index then
		return
	end
	beacon = controllers.EffectsController.Pillar(
		WorldLayout.Plots[index].Center + Vector3.new(0, 1, 0),
		UITheme.Colors.Lavender,
		260,
		3
	)
end

function SanctuaryController.Init(registry: { [string]: any })
	controllers = registry
end

function SanctuaryController.Start()
	Components = controllers.Components
	local Make = Components.Make
	slotPanel = Components.Panel("Choose a habitat", Vector2.new(600, 470), controllers.PanelManager.Gui())
	slotGrid = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = slotPanel.Body })
	Make("UIGridLayout", {
		CellSize = UDim2.new(1 / 3, -8, 0, 56),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = slotGrid,
	})
	controllers.PanelManager.Register("HabitatSlots", slotPanel, function()
		renderSlots()
		highlightPads()
	end, function()
		pendingCreature = nil
		clearHighlights()
	end)

	creaturePanel = Components.Panel("Habitat", Vector2.new(620, 520), controllers.PanelManager.Gui())
	creatureList = Make("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = creaturePanel.Body,
	})
	Components.List(Enum.FillDirection.Vertical, 8).Parent = creatureList
	controllers.PanelManager.Register("HabitatCreatures", creaturePanel, function()
		renderCreatures()
		highlightPads()
	end, function()
		pendingSlot = nil
		clearHighlights()
	end)

	-- Pads stream in and out; configure each one as it arrives.
	CollectionService:GetInstanceAddedSignal("HabitatPad"):Connect(configurePad)
	controllers.ClientState.ObserveSession("PlotIndex", function()
		refreshPads()
		updateBeacon()
	end)
end

return SanctuaryController

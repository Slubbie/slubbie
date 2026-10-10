-- Personal sanctuaries: plot assignment, habitat slots, the creatures on
-- display, and the visible upgrades each Habitat level brings.
--
-- Placement is slot-based: the client asks to put creature X in slot N and
-- the server checks the player owns X, has a plot, N is unlocked, and the
-- species is valid. Moving a deployed creature to an occupied slot swaps
-- the two; placing an undeployed creature on an occupied slot returns the
-- previous occupant to the inventory. Nothing is ever lost or duplicated:
-- habitats only store creature IDs, never copies.
--
-- Visitors see every sanctuary but can't change one: the server only
-- accepts placement requests for the requester's own plot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreatureDefinitions = require(Shared.CreatureDefinitions)
local CreatureRig = require(Shared.CreatureRig)
local Format = require(Shared.Format)
local Loop = require(Shared.Loop)
local RarityConfig = require(Shared.RarityConfig)
local Signal = require(Shared.Signal)
local UpgradeDefinitions = require(Shared.UpgradeDefinitions)
local WorldLayout = require(Shared.WorldLayout)

local SanctuaryService = { Name = "SanctuaryService" }

-- (player, creatureId, slot)
SanctuaryService.CreatureDeployed = Signal.new()
-- (player, creatureId, slot)
SanctuaryService.CreatureWithdrawn = Signal.new()
-- (player)
SanctuaryService.EnteredOwnSanctuary = Signal.new()

local MAX_HEIGHT = 6.5
local MAX_RADIUS = 4.6

local services: { [string]: any } = {}
local owners: { [number]: Player } = {}
local plotOf: { [Player]: number } = {}
local inside: { [Player]: boolean } = {}
-- Tests run without building models.
SanctuaryService.BuildVisuals = true

function SanctuaryService.GetPlotIndex(player: Player): number?
	return plotOf[player]
end

function SanctuaryService.GetOwner(plotIndex: number): Player?
	return owners[plotIndex]
end

function SanctuaryService.UnlockedSlots(profile: any): number
	return UpgradeDefinitions.HabitatSlots(profile.Equipment.HabitatLevel)
end

local function levelNeededFor(slot: number): number
	local track = UpgradeDefinitions.Tracks.Habitat
	for level, def in track.Levels do
		if (def.Slots or 0) >= slot then
			return level
		end
	end
	return #track.Levels
end

local function countEquipped(profile: any): number
	local n = 0
	for _ in profile.EquippedCreatures do
		n += 1
	end
	return n
end

local function countSpecies(profile: any): number
	local n = 0
	for _ in profile.DiscoveredSpecies do
		n += 1
	end
	return n
end

-- Visuals ----------------------------------------------------------------------

local function buildDisplay(plot: any, pad: any, creature: any, owner: Player): Model?
	local ok, model = pcall(CreatureRig.Build, creature.Species, { Mutation = creature.Mutation })
	if not ok then
		warn(`[Sanctuary] Couldn't build {creature.Species}: {model}`)
		return nil
	end
	local height = model:GetAttribute("Height") or 3
	local radius = model:GetAttribute("Radius") or 2
	CreatureRig.ScaleTo(model, math.min(1, MAX_HEIGHT / height, MAX_RADIUS / radius))
	CreatureRig.Place(model, pad.Anchor)
	model.Name = creature.Species
	model:SetAttribute("CreatureId", creature.Id)
	model:SetAttribute("OwnerUserId", owner.UserId)
	model:SetAttribute("Slot", pad.Slot)
	model:SetAttribute("Bond", creature.Bond)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:AddTag("CreatureDisplay")
	model.Parent = plot.Displays
	return model
end

local function refreshPad(player: Player?, plot: any, slot: number)
	local pad = plot.Pads[slot]
	local existing = plot.Displays:FindFirstChild("Slot" .. slot)
	if existing then
		existing:Destroy()
	end
	for _, child in plot.Displays:GetChildren() do
		if child:GetAttribute("Slot") == slot then
			child:Destroy()
		end
	end
	local profile = player and services.PlayerDataService.GetProfile(player)
	if not player or not profile then
		pad.Glow.Color = Color3.fromRGB(110, 118, 160)
		pad.Glow.Transparency = 0.5
		pad.Prompt.Enabled = false
		pad.Lock.Enabled = false
		return
	end
	local unlocked = slot <= SanctuaryService.UnlockedSlots(profile)
	local creatureId = profile.EquippedCreatures[tostring(slot)]
	local creature = creatureId and profile.Creatures[creatureId]
	if not unlocked then
		pad.Glow.Color = Color3.fromRGB(90, 96, 130)
		pad.Glow.Transparency = 0.6
		pad.Prompt.Enabled = false
		pad.Lock.Enabled = true
		local title = pad.Lock:FindFirstChild("Title")
		if title and title:IsA("TextLabel") then
			title.Text = `🔒 Lv {levelNeededFor(slot)}`
		end
		return
	end
	pad.Lock.Enabled = false
	pad.Prompt.Enabled = true
	if creature then
		local species = CreatureDefinitions.Get(creature.Species)
		pad.Glow.Color = if species then RarityConfig.Rarities[species.Rarity].Color else Color3.fromRGB(116, 229, 254)
		pad.Glow.Transparency = 0
		pad.Prompt.ActionText = "Manage Creature"
		pad.Prompt.ObjectText = if species then species.DisplayName else "Creature"
		local model = buildDisplay(plot, pad, creature, player)
		if model then
			model.Name = "Slot" .. slot
		end
	else
		pad.Glow.Color = Color3.fromRGB(116, 229, 254)
		pad.Glow.Transparency = 0.25
		pad.Prompt.ActionText = "Place Creature"
		pad.Prompt.ObjectText = `Habitat {slot}`
	end
end

function SanctuaryService.UpdateSign(player: Player)
	local index = plotOf[player]
	local profile = services.PlayerDataService.GetProfile(player)
	local plot = index and services.WorldService.GetPlot(index)
	if not plot or not profile or not SanctuaryService.BuildVisuals then
		return
	end
	local rate = services.IncomeService.GetRate(player)
	local title = plot.Sign:FindFirstChild("Title")
	local subtitle = plot.Sign:FindFirstChild("Subtitle")
	if title and title:IsA("TextLabel") then
		title.Text = `{player.DisplayName}'s Sanctuary`
	end
	if subtitle and subtitle:IsA("TextLabel") then
		subtitle.Text = `✦ {Format.Rate(rate)}/s  ·  {countSpecies(profile)} species  ·  Lv {profile.Level}`
	end
	local line = plot.ArchSign:FindFirstChild("Line1")
	if line and line:IsA("TextLabel") then
		line.Text = `{player.DisplayName}'s Sanctuary`
	end
end

function SanctuaryService.RefreshPlot(player: Player)
	local index = plotOf[player]
	local profile = services.PlayerDataService.GetProfile(player)
	if not index or not profile or not SanctuaryService.BuildVisuals then
		return
	end
	local plot = services.WorldService.GetPlot(index)
	if not plot then
		return
	end
	services.WorldService.SetPlotTier(index, profile.Equipment.HabitatLevel)
	for slot = 1, #plot.Pads do
		refreshPad(player, plot, slot)
	end
	plot.Beacon.Color = Color3.fromRGB(182, 156, 255)
	plot.Beacon.Transparency = 0.2
	SanctuaryService.UpdateSign(player)
end

local function resetPlot(index: number)
	local plot = services.WorldService.GetPlot(index)
	if not plot or not SanctuaryService.BuildVisuals then
		return
	end
	plot.Displays:ClearAllChildren()
	services.WorldService.SetPlotTier(index, 1)
	for slot = 1, #plot.Pads do
		refreshPad(nil, plot, slot)
	end
	local title = plot.Sign:FindFirstChild("Title")
	local subtitle = plot.Sign:FindFirstChild("Subtitle")
	if title and title:IsA("TextLabel") then
		title.Text = "Open Sanctuary"
	end
	if subtitle and subtitle:IsA("TextLabel") then
		subtitle.Text = "Unclaimed"
	end
	local line = plot.ArchSign:FindFirstChild("Line1")
	if line and line:IsA("TextLabel") then
		line.Text = "Open Sanctuary"
	end
	plot.Beacon.Color = Color3.fromRGB(110, 118, 160)
	plot.Beacon.Transparency = 0.6
end

-- Plots ------------------------------------------------------------------------

function SanctuaryService.AssignPlot(player: Player): number?
	if plotOf[player] then
		return plotOf[player]
	end
	for index = 1, WorldLayout.Sanctuary.Count do
		if not owners[index] then
			owners[index] = player
			plotOf[player] = index
			services.ReplicationService.SetSession(player, "PlotIndex", index)
			SanctuaryService.RefreshPlot(player)
			return index
		end
	end
	warn(`[Sanctuary] No free plot for {player.Name}`)
	services.ReplicationService.Notify(player, "NoSanctuary", {})
	return nil
end

function SanctuaryService.ReleasePlot(player: Player)
	local index = plotOf[player]
	if not index then
		return
	end
	plotOf[player] = nil
	owners[index] = nil
	inside[player] = nil
	resetPlot(index)
end

-- Placement --------------------------------------------------------------------

function SanctuaryService.Deploy(player: Player, creatureId: string, slot: number): { [string]: any }
	local profile = services.PlayerDataService.GetProfile(player)
	if not profile then
		return { Ok = false, Reason = "NotReady" }
	end
	local index = plotOf[player]
	if not index then
		return { Ok = false, Reason = "NoSanctuary" }
	end
	if slot ~= math.floor(slot) or slot < 1 or slot > SanctuaryService.UnlockedSlots(profile) then
		return { Ok = false, Reason = "SlotLocked" }
	end
	local creature = profile.Creatures[creatureId]
	if not creature then
		return { Ok = false, Reason = "NotOwned" }
	end
	if not CreatureDefinitions.IsSpecies(creature.Species) then
		return { Ok = false, Reason = "UnknownSpecies" }
	end
	local key = tostring(slot)
	local fromKey = services.CreatureService.FindSlot(profile, creatureId)
	if fromKey == key then
		return { Ok = true, Unchanged = true }
	end
	local occupant = profile.EquippedCreatures[key]
	local changed: { string } = { key }

	profile.EquippedCreatures[key] = creatureId
	if fromKey then
		-- Moving: swap with whoever was in the target slot.
		profile.EquippedCreatures[fromKey] = occupant
		table.insert(changed, fromKey)
	end
	for _, changedKey in changed do
		services.ReplicationService.Set(
			player,
			{ "EquippedCreatures", changedKey },
			profile.EquippedCreatures[changedKey]
		)
	end

	local plot = services.WorldService.GetPlot(index)
	if plot and SanctuaryService.BuildVisuals then
		for _, changedKey in changed do
			refreshPad(player, plot, tonumber(changedKey) :: number)
		end
	end
	if occupant and not fromKey then
		SanctuaryService.CreatureWithdrawn:Fire(player, occupant, slot)
	end
	SanctuaryService.CreatureDeployed:Fire(player, creatureId, slot)
	services.AnalyticsService.Milestone(player, "FirstDeploy")
	SanctuaryService.UpdateSign(player)
	return { Ok = true, Swapped = occupant ~= nil }
end

function SanctuaryService.Withdraw(player: Player, slot: number): { [string]: any }
	local profile = services.PlayerDataService.GetProfile(player)
	if not profile then
		return { Ok = false, Reason = "NotReady" }
	end
	local key = tostring(slot)
	local creatureId = profile.EquippedCreatures[key]
	if not creatureId then
		return { Ok = false, Reason = "Empty" }
	end
	profile.EquippedCreatures[key] = nil
	services.ReplicationService.Set(player, { "EquippedCreatures", key }, nil)
	local index = plotOf[player]
	local plot = index and services.WorldService.GetPlot(index)
	if plot and SanctuaryService.BuildVisuals then
		refreshPad(player, plot, slot)
	end
	SanctuaryService.CreatureWithdrawn:Fire(player, creatureId, slot)
	SanctuaryService.UpdateSign(player)
	return { Ok = true }
end

function SanctuaryService.IsInside(player: Player): boolean
	return inside[player] == true
end

function SanctuaryService.DeployedCount(player: Player): number
	local profile = services.PlayerDataService.GetProfile(player)
	return if profile then countEquipped(profile) else 0
end

-- Detects players walking into their own sanctuary.
function SanctuaryService.CheckPresence()
	for player, index in plotOf do
		local position = services.SecurityService.GetRootPosition(player)
		if not position then
			continue
		end
		local center = WorldLayout.Plots[index].Center
		local d = Vector3.new(position.X - center.X, 0, position.Z - center.Z).Magnitude
		local isInside = d <= WorldLayout.Sanctuary.PlotRadius + 2 and math.abs(position.Y - center.Y) < 40
		if isInside and not inside[player] then
			SanctuaryService.EnteredOwnSanctuary:Fire(player)
		end
		inside[player] = isInside
	end
end

function SanctuaryService.Init(registry: { [string]: any })
	services = registry
end

function SanctuaryService.Start()
	local security = services.SecurityService
	security.BindFunction("EquipCreature", SanctuaryService.Deploy)
	security.BindFunction("RemoveCreature", SanctuaryService.Withdraw)

	services.PlayerDataService.ProfileLoaded:Connect(function(player)
		SanctuaryService.AssignPlot(player)
	end)
	services.PlayerDataService.ProfileReleasing:Connect(function(player)
		SanctuaryService.ReleasePlot(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		SanctuaryService.ReleasePlot(player)
	end)
	services.UpgradeService.Upgraded:Connect(function(player, trackId)
		if trackId == "Habitat" then
			SanctuaryService.RefreshPlot(player)
		end
	end)
	services.IncomeService.RateChanged:Connect(function(player)
		SanctuaryService.UpdateSign(player)
	end)
	services.CreatureService.CreatureObtained:Connect(function(player)
		SanctuaryService.UpdateSign(player)
	end)
	services.ProgressionService.LevelUp:Connect(function(player)
		SanctuaryService.UpdateSign(player)
	end)
	Loop.Every(1, "SanctuaryPresence", SanctuaryService.CheckPresence)
end

return SanctuaryService

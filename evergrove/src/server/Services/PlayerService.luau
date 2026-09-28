-- Per-player runtime state: characters, energy, buffs, walk speed, the region
-- you're standing in (access rules, hazards, discovery), fast travel,
-- settings validation and nametag attributes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Regions = require(Shared.Config.Regions)
local World = require(Shared.Config.World)
local Skills = require(Shared.Config.Skills)
local SettingsConfig = require(Shared.Config.Settings)
local Gameplay = require(Shared.Config.Gameplay)
local Net = require(Shared.Lib.Net)
local Signal = require(Shared.Lib.Signal)
local Stats = require(Shared.Lib.Stats)
local GameTime = require(Shared.Lib.GameTime)
local Registry = require(Shared.Lib.Registry)

local S = require(script.Parent)

local BASE_WALK = 18

local PlayerService = {}
PlayerService.RegionChanged = Signal.new() -- (player, regionId, previous)

local currentRegion: { [Player]: string } = {}
local lastLocked: { [Player]: number } = {}
local energyWarnAt: { [Player]: number } = {}

-- Regions -----------------------------------------------------------------------------------------

-- Smallest region containing the position (vertical extent respected).
function PlayerService.RegionAt(position: Vector3): string
	local best, bestRadius = "Homestead", math.huge
	for _, region in Regions.List do
		local flat = Vector3.new(position.X - region.Center.X, 0, position.Z - region.Center.Z).Magnitude
		local height = region.Height or 400
		if flat <= region.Radius and math.abs(position.Y - region.Center.Y) <= height and region.Radius < bestRadius then
			best, bestRadius = region.Id, region.Radius
		end
	end
	return best
end

function PlayerService.Region(player: Player): string
	return currentRegion[player] or "Homestead"
end

-- Is this region open to the player? Returns ok, reason.
function PlayerService.CanAccess(player: Player, regionId: string): (boolean, string?)
	local region = Registry.Regions[regionId]
	local profile = S.Data.Get(player)
	if not region or not profile then
		return false, "Unknown place"
	end
	local unlock = region.Unlock
	if not unlock then
		return true
	end
	if profile.Unlocks["Region_" .. regionId] then
		-- Permanently opened (secrets like the Hidden Pass), but still respect Night gates.
		if not unlock.Night or GameTime.Info().IsNight then
			return true
		end
	end
	if unlock.Quest and not profile.Quests.Done[unlock.Quest] then
		return false, region.UnlockText
	end
	if unlock.Item and S.Inventory.Count(player, unlock.Item) <= 0 and not profile.Unlocks["Item_" .. unlock.Item] then
		return false, region.UnlockText
	end
	if unlock.Skill and Stats.SkillLevel(profile, unlock.Skill[1]) < unlock.Skill[2] then
		return false, region.UnlockText
	end
	if unlock.Project and not (profile.Projects[unlock.Project] and profile.Projects[unlock.Project].Done) then
		return false, region.UnlockText
	end
	if unlock.Estate and Stats.EstateLevel(profile) < unlock.Estate then
		return false, region.UnlockText
	end
	if unlock.Secret and not profile.Secrets[unlock.Secret] then
		return false, region.UnlockText
	end
	if unlock.Night and not GameTime.Info().IsNight then
		return false, "The thorns only part at night."
	end
	return true
end

-- Energy ------------------------------------------------------------------------------------------------

function PlayerService.MaxEnergy(player: Player): number
	local profile = S.Data.Get(player)
	return if profile then Stats.MaxEnergy(profile) else Skills.Energy.Base
end

-- Spend energy. Light actions (harvest/plant) are always allowed.
function PlayerService.SpendEnergy(player: Player, amount: number, light: boolean?): boolean
	local profile = S.Data.Get(player)
	if not profile then
		return false
	end
	if not Gameplay.Energy.Enabled or amount <= 0 then
		return true
	end
	if profile.Energy < amount and not light then
		if os.clock() - (energyWarnAt[player] or 0) > 6 then
			energyWarnAt[player] = os.clock()
			S.Notify.Toast(player, "You're exhausted! Eat something or rest a moment.", "Warning")
		end
		return false
	end
	profile.Energy = math.max(0, profile.Energy - amount)
	S.Data.Changed(player, "Energy")
	return true
end

function PlayerService.RestoreEnergy(player: Player, amount: number)
	local profile = S.Data.Get(player)
	if not profile then
		return
	end
	profile.Energy = math.min(PlayerService.MaxEnergy(player), profile.Energy + amount)
	S.Data.Changed(player, "Energy")
end

-- Buffs -----------------------------------------------------------------------------------------------------

-- Apply a buff { Id, Mult, Minutes } (minutes of in-game time are real minutes here).
function PlayerService.ApplyBuff(player: Player, buff: any)
	local profile = S.Data.Get(player)
	if not profile or not buff then
		return
	end
	local duration = buff.Minutes * 60 * (1 + Stats.Effect(profile, "BuffDuration"))
	local strength = 1 + ((buff.Mult or 1) - 1) * (1 + Stats.Effect(profile, "BuffStrength"))
	local existing = profile.Buffs[buff.Id]
	local now = GameTime.Now()
	local untilTime = math.max(existing and existing.Until or now, now) + duration
	profile.Buffs[buff.Id] = { Mult = math.max(strength, existing and existing.Mult or 0), Until = untilTime }
	S.Data.Changed(player, "Buffs")
	S.Farm.InvalidatePlayerEffects(player)
end

function PlayerService.HasBuff(player: Player, id: string): boolean
	local profile = S.Data.Get(player)
	local buff = profile and profile.Buffs[id]
	return buff ~= nil and buff.Until > GameTime.Now()
end

-- Characters ------------------------------------------------------------------------------------------------

local function applyWalkSpeed(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local profile = S.Data.Get(player)
	if not humanoid or not profile then
		return
	end
	if character:GetAttribute("Riding") then
		return -- AnimalService sets mount speed
	end
	humanoid.WalkSpeed = BASE_WALK * (1 + Stats.Effect(profile, "WalkSpeed", GameTime.Now()))
end

-- Restore the normal walk speed (after dismounting or leaving a vehicle).
function PlayerService.ApplyWalkSpeed(player: Player)
	applyWalkSpeed(player)
end

function PlayerService.Teleport(player: Player, cframe: CFrame)
	local character = player.Character
	if not character then
		return
	end
	S.Security.AllowTeleport(player)
	character:PivotTo(cframe)
end

local function onCharacter(player: Player, character: Model)
	-- Wait for the farm, then drop them at their gate.
	local waited = 0
	while not S.Farm.Get(player) and waited < 20 and player.Parent do
		task.wait(0.25)
		waited += 0.25
	end
	local spawn = S.Farm.SpawnCFrame(player)
	if spawn and character.Parent then
		PlayerService.Teleport(player, spawn)
	end
	applyWalkSpeed(player)
	PlayerService.UpdateNametag(player)
end

function PlayerService.UpdateNametag(player: Player)
	local profile = S.Data.Get(player)
	if not profile then
		return
	end
	player:SetAttribute("Estate", Stats.EstateLevel(profile))
	player:SetAttribute("Title", profile.Cosmetics.Equipped.Title or "Newcomer")
	player:SetAttribute("FarmName", profile.Farm.Name)
	player:SetAttribute("Nameplate", profile.Cosmetics.Equipped.Nameplate)
	player:SetAttribute("Aura", profile.Cosmetics.Equipped.Effect)
	player:SetAttribute("Guild", profile.Guild.Name)
end

-- Settings ------------------------------------------------------------------------------------------------------

function PlayerService.CleanSettings(raw: any): { [string]: any }
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	for _, spec in SettingsConfig.Specs do
		local value = raw[spec.Key]
		if spec.Kind == "Toggle" and type(value) == "boolean" then
			out[spec.Key] = value
		elseif spec.Kind == "Slider" and type(value) == "number" and value == value then
			out[spec.Key] = math.clamp(value, spec.Min :: number, spec.Max :: number)
		elseif spec.Kind == "Choice" and type(value) == "string" and table.find(spec.Options :: { string }, value) then
			out[spec.Key] = value
		end
	end
	return out
end

-- Travel ---------------------------------------------------------------------------------------------------------

local travelById = {}
for _, travel in World.Travel do
	travelById[travel.Id] = travel
end

local function nearSignpost(player: Player, profile: any): boolean
	local root = S.Security.RootPosition(player)
	if not root then
		return false
	end
	for id in profile.Travel do
		local travel = travelById[id]
		if travel and (travel.Position - root).Magnitude <= World.TravelDiscoverRadius + 12 then
			return true
		end
	end
	local farm = S.Farm.Get(player)
	if farm and (farm.Origin - root).Magnitude < 300 then
		return true
	end
	return false
end

local function travel(player: Player, id: string)
	local profile = S.Data.Get(player)
	if not profile then
		return false, "Not ready"
	end
	if id == "home" then
		local spawn = S.Farm.SpawnCFrame(player)
		if not spawn then
			return false, "No farm"
		end
		if not nearSignpost(player, profile) and Stats.Effect(profile, "TravelAnywhere") <= 0 then
			return false, "Travel from a signpost (or use a Farm Warp Totem)"
		end
		PlayerService.Teleport(player, spawn)
		return true
	end
	-- Lifts (mine shaft, sky lift): free, no discovery needed, must stand at the lift.
	local liftId = string.match(id, "^lift:(.+)$")
	if liftId then
		local lift = S.World.LiftNear(S.Security.RootPosition(player), liftId)
		if not lift then
			return false, "Stand at the lift"
		end
		local ok, reason = PlayerService.CanAccess(player, lift.Region)
		if not ok then
			return false, reason
		end
		if lift.Travel and not profile.Travel[lift.Travel] then
			profile.Travel[lift.Travel] = true
			S.Data.Changed(player, "Travel")
		end
		PlayerService.Teleport(player, CFrame.new(lift.Arrive + Vector3.new(0, 4, 0)))
		return true
	end
	local dest = travelById[id]
	if not dest then
		return false, "Unknown destination"
	end
	if not profile.Travel[id] then
		return false, "Discover that signpost first"
	end
	local ok, reason = PlayerService.CanAccess(player, dest.Region)
	if not ok then
		return false, reason
	end
	if not nearSignpost(player, profile) and Stats.Effect(profile, "TravelAnywhere") <= 0 then
		return false, "Travel from a signpost"
	end
	local cost = if Stats.Effect(profile, "FreeTravel") > 0 then 0 else World.TravelCost
	if cost > 0 and not S.Economy.Spend(player, cost, "Travel") then
		return false, "Not enough coins"
	end
	PlayerService.Teleport(player, CFrame.new(dest.Position + Vector3.new(0, 4, 0)))
	return true
end

-- Warp to a named place (warp totems, admin).
function PlayerService.Warp(player: Player, id: string): boolean
	if id == "home" then
		local spawn = S.Farm.SpawnCFrame(player)
		if spawn then
			PlayerService.Teleport(player, spawn)
			return true
		end
		return false
	end
	local dest = travelById[id]
	if dest then
		PlayerService.Teleport(player, CFrame.new(dest.Position + Vector3.new(0, 4, 0)))
		return true
	end
	return false
end

-- Region loop: access, hazards, discovery ---------------------------------------------------------------------------

local function hazardTick(player: Player, profile: any, region: any, dt: number)
	local hazard = region.Hazard
	if not hazard or hazard.EnergyPerMinute <= 0 then
		return false
	end
	if PlayerService.HasBuff(player, hazard.Buff) then
		return false
	end
	if hazard.Kind == "Cold" then
		local root = S.Security.RootPosition(player)
		local lodge = travelById.frostveil
		if root and lodge and (root - lodge.Position).Magnitude < 40 then
			return false
		end
	end
	local resist = math.clamp(Stats.Effect(profile, "HazardResist"), 0, 0.9)
	local drain = hazard.EnergyPerMinute / 60 * dt * (1 - resist)
	profile.Energy = math.max(0, profile.Energy - drain)
	S.Data.Changed(player, "Energy")
	return true
end

local function regionTick(player: Player, dt: number)
	local profile = S.Data.Get(player)
	local root = S.Security.RootPosition(player)
	if not profile or not root then
		return
	end
	local regionId = PlayerService.RegionAt(root)
	local previous = currentRegion[player]
	local ok, reason = PlayerService.CanAccess(player, regionId)
	if not ok then
		-- Walked (or glitched) into a locked region: send them back.
		if os.clock() - (lastLocked[player] or 0) > 2 then
			lastLocked[player] = os.clock()
			S.Notify.Toast(player, "🔒 " .. (reason or "You can't go there yet."), "Warning")
			local target = if previous and previous ~= regionId then previous else "Village"
			local region = Registry.Regions[target]
			local fallback = travelById.town
			local cframe = CFrame.new((if region and target ~= "Homestead" then region.Center else fallback.Position) + Vector3.new(0, 5, 0))
			PlayerService.Teleport(player, cframe)
		end
		return
	end
	if regionId ~= previous then
		currentRegion[player] = regionId
		player:SetAttribute("Region", regionId)
		PlayerService.RegionChanged:Fire(player, regionId, previous)
		if not profile.Regions[regionId] then
			profile.Regions[regionId] = GameTime.Now()
			S.Data.Changed(player, "Regions")
			local visited = 0
			for _ in profile.Regions do
				visited += 1
			end
			S.Data.MaxStat(player, "RegionsVisited", visited)
			S.Collection.Discover(player, "Regions", regionId)
			S.Skill.AddXP(player, "Exploration", 150)
		end
		S.Quest.Progress(player, "Visit", regionId, 1)
	end
	-- Hazards drain energy; otherwise energy regenerates.
	local region = Registry.Regions[regionId]
	local hurting = region and hazardTick(player, profile, region, dt)
	if not hurting then
		local max = Stats.MaxEnergy(profile)
		if profile.Energy < max then
			profile.Energy = math.min(max, profile.Energy + Skills.Energy.RegenPerSecond * dt)
			S.Data.Changed(player, "Energy")
		end
	end
	-- Signpost discovery
	for _, point in World.Travel do
		if not profile.Travel[point.Id] and (point.Position - root).Magnitude <= World.TravelDiscoverRadius then
			profile.Travel[point.Id] = true
			S.Data.Changed(player, "Travel")
			S.Notify.Toast(player, "🪧 Discovered " .. point.Name .. " (fast travel)", "Success")
			S.Data.AddStat(player, "SignpostsFound")
			S.Quest.Progress(player, "Travel", point.Id, 1)
		end
	end
end

local function buffTick()
	local now = GameTime.Now()
	for player, profile in S.Data.All() do
		local changed = false
		for id, buff in profile.Buffs do
			if type(buff) ~= "table" or (buff.Until or 0) <= now then
				profile.Buffs[id] = nil
				changed = true
			end
		end
		if changed then
			S.Data.Changed(player, "Buffs")
			S.Farm.InvalidatePlayerEffects(player)
		end
		applyWalkSpeed(player)
	end
end

function PlayerService.Init()
	Net.Handle("Travel", travel)
	Net.Handle("Pose", function(player, pose)
		local character = player.Character
		if character then
			character:SetAttribute("Pose", pose)
		end
	end)
end

function PlayerService.Start()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		currentRegion[player] = nil
		lastLocked[player] = nil
		energyWarnAt[player] = nil
	end)
	S.Data.Loaded:Connect(function(player)
		PlayerService.UpdateNametag(player)
	end)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(1)
			local now = os.clock()
			local dt = now - last
			last = now
			for _, player in Players:GetPlayers() do
				if S.Data.IsLoaded(player) then
					regionTick(player, dt)
				end
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(2)
			buffTick()
		end
	end)
end

return PlayerService

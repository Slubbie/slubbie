-- XP, levels and biome access.
--
-- XP comes from active play (captures, quests). Passive Stardust never
-- grants XP, so levels reflect what the player actually did.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BiomeDefinitions = require(Shared.BiomeDefinitions)
local EconomyMath = require(Shared.EconomyMath)
local GameConfig = require(Shared.GameConfig)
local Signal = require(Shared.Signal)

local ProgressionService = { Name = "ProgressionService" }

-- (player, newLevel, previousLevel)
ProgressionService.LevelUp = Signal.new()
-- (player, biomeId)
ProgressionService.BiomeUnlocked = Signal.new()

local services: { [string]: any } = {}

-- Adds XP and handles level ups. Returns the number of levels gained.
function ProgressionService.AddXP(player: Player, amount: number, source: string): number
	local profile = services.PlayerDataService.GetProfile(player)
	if not profile or type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount == math.huge then
		return 0
	end
	amount = math.floor(amount)
	local previous = profile.Level
	local level, xp, gained = EconomyMath.AddXP(profile.Level, profile.XP, amount)
	profile.Level, profile.XP = level, xp
	services.ReplicationService.Set(player, { "XP" }, xp)
	if gained > 0 then
		services.ReplicationService.Set(player, { "Level" }, level)
		local reward = 0
		for lvl = previous + 1, level do
			reward += EconomyMath.LevelUpStardust(lvl)
			services.AnalyticsService.Progression(player, lvl)
		end
		services.EconomyService.Grant(player, "Stardust", reward, "LevelUp")
		local ready = {}
		for _, biomeId in BiomeDefinitions.Order do
			local biome = BiomeDefinitions.Biomes[biomeId]
			if biome.Unlock.Level > previous and biome.Unlock.Level <= level then
				table.insert(ready, biome.DisplayName)
			end
		end
		services.ReplicationService.Notify(player, "LevelUp", {
			Level = level,
			Stardust = reward,
			BiomesReady = ready,
		})
		ProgressionService.LevelUp:Fire(player, level, previous)
		services.PlayerDataService.RequestSave(player)
	end
	return gained
end

function ProgressionService.IsBiomeUnlocked(player: Player, biomeId: string): boolean
	local profile = services.PlayerDataService.GetProfile(player)
	return profile ~= nil and profile.UnlockedBiomes[biomeId] == true
end

-- Whether a player can travel to (and capture in) a biome right now.
function ProgressionService.CanEnterBiome(player: Player, biomeId: string): (boolean, string?)
	local biome = BiomeDefinitions.Get(biomeId)
	if not biome then
		return false, "UnknownBiome"
	end
	if not biome.Implemented then
		return false, "ComingSoon"
	end
	if not ProgressionService.IsBiomeUnlocked(player, biomeId) then
		return false, "Locked"
	end
	return true, nil
end

-- Pays a biome's unlock cost. Atomic: level check + Stardust spend + unlock.
function ProgressionService.UnlockBiome(player: Player, biomeId: string): (boolean, string?)
	local profile = services.PlayerDataService.GetProfile(player)
	local biome = BiomeDefinitions.Get(biomeId)
	if not profile or not biome then
		return false, "UnknownBiome"
	end
	if profile.UnlockedBiomes[biomeId] then
		return false, "AlreadyUnlocked"
	end
	if not biome.Implemented then
		return false, "ComingSoon"
	end
	if profile.Level < biome.Unlock.Level then
		return false, "LevelTooLow"
	end
	if not services.EconomyService.Spend(player, "Stardust", biome.Unlock.Stardust, "Biome:" .. biomeId) then
		return false, "NotEnoughStardust"
	end
	profile.UnlockedBiomes[biomeId] = true
	services.ReplicationService.Set(player, { "UnlockedBiomes", biomeId }, true)
	services.ReplicationService.Notify(player, "BiomeUnlocked", { Biome = biomeId })
	services.AnalyticsService.Milestone(player, "FirstBiomeUnlocked")
	ProgressionService.BiomeUnlocked:Fire(player, biomeId)
	services.PlayerDataService.RequestSave(player)
	return true, nil
end

function ProgressionService.Init(registry: { [string]: any })
	services = registry
	assert(GameConfig.Progression.LevelCap >= 1)
end

function ProgressionService.Start() end

return ProgressionService

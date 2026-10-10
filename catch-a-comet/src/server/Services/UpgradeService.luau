-- Equipment upgrades. A purchase is atomic: the Stardust is spent and the
-- level raised in one non-yielding step, or nothing changes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Signal)
local UpgradeDefinitions = require(Shared.UpgradeDefinitions)

local UpgradeService = { Name = "UpgradeService" }

-- (player, trackId, newLevel)
UpgradeService.Upgraded = Signal.new()

local services: { [string]: any } = {}

function UpgradeService.Purchase(player: Player, trackId: string): { [string]: any }
	local profile = services.PlayerDataService.GetProfile(player)
	if not profile then
		return { Ok = false, Reason = "NotReady" }
	end
	local track = UpgradeDefinitions.Get(trackId)
	if not track then
		return { Ok = false, Reason = "UnknownTrack" }
	end
	local key = track.ProfileKey
	local equipment = profile.Equipment :: any
	local level = equipment[key]
	if level >= #track.Levels then
		return { Ok = false, Reason = "MaxLevel" }
	end
	local cost = track.Levels[level + 1].Cost
	if not services.EconomyService.Spend(player, "Stardust", cost, "Upgrade:" .. trackId) then
		return { Ok = false, Reason = "NotEnoughStardust", Cost = cost }
	end
	local newLevel = level + 1
	equipment[key] = newLevel
	services.ReplicationService.Set(player, { "Equipment", key }, newLevel)
	UpgradeService.Upgraded:Fire(player, trackId, newLevel)
	services.ReplicationService.Notify(player, "Upgraded", { Track = trackId, Level = newLevel })
	services.AnalyticsService.Milestone(player, "FirstUpgrade")
	services.AnalyticsService.Custom(player, "Upgrade:" .. trackId, newLevel)
	services.PlayerDataService.RequestSave(player)
	return { Ok = true, Level = newLevel }
end

function UpgradeService.Init(registry: { [string]: any })
	services = registry
end

function UpgradeService.Start()
	services.SecurityService.BindFunction("PurchaseUpgrade", UpgradeService.Purchase)
end

return UpgradeService

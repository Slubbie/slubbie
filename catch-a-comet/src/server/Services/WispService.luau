-- Stardust Wisps: faint motes at fixed spots that only a scanner can see.
-- Each player collects each wisp independently; it returns for them after
-- RespawnSeconds. The server checks the wisp exists, the biome is open to the
-- player, the per-player timer, and the player's distance (larger with the
-- level 5 scanner's Wisp Magnet).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BiomeDefinitions = require(Shared.BiomeDefinitions)
local GameConfig = require(Shared.GameConfig)
local Signal = require(Shared.Signal)
local UpgradeDefinitions = require(Shared.UpgradeDefinitions)

local WispService = { Name = "WispService" }

-- (player, wisp)
WispService.WispCollected = Signal.new()

WispService.Clock = function(): number
	return workspace:GetServerTimeNow()
end

local config = GameConfig.Wisps
local services: { [string]: any } = {}
local wisps: { [string]: { Id: string, Position: Vector3, Biome: string } } = {}
local available: { [Player]: { [string]: number } } = {}

function WispService.Load(points: { { Id: string, Position: Vector3, Biome: string } })
	wisps = {}
	for _, point in points do
		wisps[point.Id] = point
	end
end

function WispService.PickupRadius(player: Player): number
	local profile = services.PlayerDataService.GetProfile(player)
	local level = if profile then profile.Equipment.ScannerLevel else 1
	if UpgradeDefinitions.HasFeature("Scanner", level, "WispMagnet") then
		return config.MagnetRadius
	end
	return config.PickupRadius
end

function WispService.HandleCollect(player: Player, wispId: string): { [string]: any }
	local wisp = wisps[wispId]
	if not wisp then
		return { Ok = false, Reason = "NoSuchWisp" }
	end
	local ok, reason = services.ProgressionService.CanEnterBiome(player, wisp.Biome)
	if not ok then
		return { Ok = false, Reason = reason }
	end
	local now = WispService.Clock()
	local timers = available[player]
	if not timers then
		timers = {}
		available[player] = timers
	end
	if (timers[wispId] or 0) > now then
		return { Ok = false, Reason = "NotYet", AvailableAt = timers[wispId] }
	end
	local position = services.SecurityService.GetRootPosition(player)
	if not position then
		return { Ok = false, Reason = "NoCharacter" }
	end
	if (position - wisp.Position).Magnitude > WispService.PickupRadius(player) + config.PickupLeeway then
		return { Ok = false, Reason = "TooFar" }
	end
	local biome = BiomeDefinitions.Get(wisp.Biome)
	local value = if biome then biome.WispValue else 1
	timers[wispId] = now + config.RespawnSeconds
	services.EconomyService.Grant(player, "Stardust", value, "Wisp")
	local profile = services.PlayerDataService.GetProfile(player)
	if profile then
		profile.Stats.WispsCollected = (profile.Stats.WispsCollected or 0) + 1
	end
	WispService.WispCollected:Fire(player, wisp)
	return { Ok = true, Stardust = value, AvailableAt = timers[wispId] }
end

function WispService.SnapshotFor(player: Player): { [string]: any }
	local list = {}
	for _, wisp in wisps do
		table.insert(list, { Id = wisp.Id, Position = wisp.Position, Biome = wisp.Biome })
	end
	return { List = list, AvailableAt = table.clone(available[player] or {}) }
end

function WispService.Init(registry: { [string]: any })
	services = registry
end

function WispService.Start()
	WispService.Load(services.WorldService.WispPoints)
	services.ReplicationService.RegisterSnapshotProvider("Wisps", WispService.SnapshotFor)
	services.SecurityService.BindFunction("CollectWisp", WispService.HandleCollect)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		available[player] = nil
	end)
end

return WispService

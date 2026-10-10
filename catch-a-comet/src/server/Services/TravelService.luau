-- Moving around the world: walk-in portals and the HUD's quick travel.
-- Destinations are checked on the server (biome unlocked and built, plot
-- owned) and rate limited, so travel can't be used to skip progression.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BiomeDefinitions = require(Shared.BiomeDefinitions)
local Format = require(Shared.Format)
local GameConfig = require(Shared.GameConfig)
local WorldLayout = require(Shared.WorldLayout)

local TravelService = { Name = "TravelService" }

local services: { [string]: any } = {}
local lastTravel: { [Player]: number } = {}
local lastPortalNotice: { [Player]: number } = {}

-- Where a destination puts you, or nil and a reason.
function TravelService.Resolve(player: Player, destination: string): (CFrame?, string?)
	if destination == "Hub" then
		return WorldLayout.Hub.Spawn, nil
	elseif destination == "Sanctuary" then
		local index = services.SanctuaryService.GetPlotIndex(player)
		if not index then
			return nil, "NoSanctuary"
		end
		return WorldLayout.PlotArrival(index), nil
	end
	local biome = BiomeDefinitions.Get(destination)
	local layout = WorldLayout.Biomes[destination]
	if not biome or not layout then
		return nil, "UnknownDestination"
	end
	local ok, reason = services.ProgressionService.CanEnterBiome(player, destination)
	if not ok then
		return nil, reason
	end
	return layout.Arrival, nil
end

function TravelService.Teleport(player: Player, target: CFrame, destination: string): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not root then
		return false
	end
	local jitter = Vector3.new((math.random() - 0.5) * 4, 0, (math.random() - 0.5) * 4)
	services.ReplicationService.Notify(player, "Travelled", { Destination = destination })
	character:PivotTo(target + jitter)
	return true
end

function TravelService.Travel(player: Player, destination: string): { [string]: any }
	local now = os.clock()
	if now - (lastTravel[player] or -math.huge) < GameConfig.Travel.Cooldown then
		return { Ok = false, Reason = "Cooldown" }
	end
	if services.CaptureService.GetSession(player) then
		return { Ok = false, Reason = "Capturing" }
	end
	local target, reason = TravelService.Resolve(player, destination)
	if not target then
		return { Ok = false, Reason = reason }
	end
	if not TravelService.Teleport(player, target, destination) then
		return { Ok = false, Reason = "NoCharacter" }
	end
	lastTravel[player] = now
	return { Ok = true }
end

local function onPortalTouched(portal: any, hit: BasePart)
	local character = hit.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player or not services.PlayerDataService.IsLoaded(player) then
		return
	end
	local destination = portal.Destination
	local now = os.clock()
	if now - (lastTravel[player] or -math.huge) < 1.5 then
		return
	end
	local target, reason = TravelService.Resolve(player, destination)
	if not target then
		if now - (lastPortalNotice[player] or -math.huge) > 4 then
			lastPortalNotice[player] = now
			local biome = BiomeDefinitions.Get(destination)
			services.ReplicationService.Notify(player, "PortalLocked", {
				Biome = destination,
				Reason = reason,
				Name = if biome then biome.DisplayName else destination,
				Level = if biome then biome.Unlock.Level else nil,
				Stardust = if biome then Format.Short(biome.Unlock.Stardust) else nil,
			})
		end
		return
	end
	lastTravel[player] = now
	TravelService.Teleport(player, target, destination)
end

function TravelService.Init(registry: { [string]: any })
	services = registry
end

function TravelService.Start()
	services.SecurityService.BindFunction("Travel", TravelService.Travel)
	for _, portal in services.WorldService.Portals do
		portal.Part.Touched:Connect(function(hit)
			onPortalTouched(portal, hit)
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastTravel[player] = nil
		lastPortalNotice[player] = nil
	end)
end

return TravelService

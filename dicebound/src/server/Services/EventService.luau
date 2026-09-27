-- Server-wide world events. Every few minutes one event starts in a random live region and
-- runs for a few minutes. The current event is published as ReplicatedStorage attributes so
-- every client can show it with a countdown:
--   DB_EventId, DB_EventRegion, DB_EventEnds (workspace:GetServerTimeNow() time)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Dicebound.Config)
local Net = require(ReplicatedStorage.Dicebound.Net)

local EventService = {}

local E = Config.Economy.Events
local current: { Id: string, Region: string, Ends: number }? = nil

-- The running event as { Id, Region } (the shape LootMath expects), or nil.
function EventService.Current(): { Id: string, Region: string }?
	if current and Workspace:GetServerTimeNow() < current.Ends then
		return { Id = current.Id, Region = current.Region }
	end
	return nil
end

-- Sell bonus for a sale at `regionId`'s merchant (Merchant Festival), else 0.
function EventService.SellBonus(regionId: string): number
	local event = EventService.Current()
	if event and event.Region == regionId then
		local def = E.ById[event.Id]
		return def and def.Effects.SellBonus or 0
	end
	return 0
end

local function publish()
	ReplicatedStorage:SetAttribute("DB_EventId", if current then current.Id else "")
	ReplicatedStorage:SetAttribute("DB_EventRegion", if current then current.Region else "")
	ReplicatedStorage:SetAttribute("DB_EventEnds", if current then current.Ends else 0)
end

function EventService.Start()
	publish()
	task.spawn(function()
		local rng = Random.new()
		task.wait(E.FirstDelay)
		while true do
			local regions = {}
			for _, region in Config.Regions.List do
				if Config.IsLive(region) then
					table.insert(regions, region)
				end
			end
			local event = E.List[rng:NextInteger(1, #E.List)]
			local region = regions[rng:NextInteger(1, #regions)]
			current = { Id = event.Id, Region = region.Id, Ends = Workspace:GetServerTimeNow() + E.Duration }
			publish()
			for _, player in Players:GetPlayers() do
				Net.Events.Notify:FireClient(
					player,
					string.format("%s %s in %s: %s!", event.Icon, event.Name, region.Name, event.Text),
					"announce"
				)
			end
			task.wait(E.Duration)
			current = nil
			publish()
			task.wait(math.max(E.Interval - E.Duration, 5))
		end
	end)
end

return EventService

-- District access, fast travel between plazas, and arrival tracking.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Access = require(ReplicatedStorage.Shared.Logic.Access)
local Districts = require(ReplicatedStorage.Shared.Config.Districts)
local Net = require(ReplicatedStorage.Shared.Net)

local DataService = require(script.Parent.Parent.Data.DataService)
local Events = require(script.Parent.Parent.Events)
local MovementGuard = require(script.Parent.MovementGuard)
local Notify = require(script.Parent.Notify)
local PlayerService = require(script.Parent.PlayerService)
local ProgressionService = require(script.Parent.ProgressionService)

local DistrictService = {}

-- Set by CourseService: whether a player is mid-run (travel is blocked).
DistrictService.IsBusy = nil :: ((Player) -> boolean)?

local lastTravel: { [Player]: number } = {}

function DistrictService.CanEnter(player: Player, districtId: string): (boolean, string?)
	local profile = DataService.Get(player)
	if not profile then
		return false, "Not ready"
	end
	return Access.District(ProgressionService.Level(player), profile.Quests.Completed, districtId)
end

function DistrictService.SpawnCFrame(districtId: string): CFrame
	return PlayerService.Spawns[districtId] or CFrame.new(Districts.ById[districtId].Origin + Vector3.new(0, 5, 0))
end

local function onDistrictChanged(player: Player, districtId: string)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	if not profile.Districts.Visited[districtId] then
		profile.Districts.Visited[districtId] = true
		local district = Districts.ById[districtId]
		Notify.Send(player, {
			Kind = "District",
			Title = district.Name,
			Text = district.Tagline,
		})
		Events.StatChanged:Fire(player, "DistrictsVisited")
	end
	profile.Districts.Last = districtId
	DataService.Push(player, "Districts")
	Events.DistrictEntered:Fire(player, districtId)
end

function DistrictService.Start()
	MovementGuard.OnDistrictChanged = onDistrictChanged

	Net.Handle("Travel.Go", function(player, districtId)
		if type(districtId) ~= "string" or not Districts.ById[districtId] then
			return false, "Unknown district"
		end
		if DistrictService.IsBusy and DistrictService.IsBusy(player) then
			return false, "Finish or leave your current run first"
		end
		if os.clock() - (lastTravel[player] or 0) < 2 then
			return false, "Slow down"
		end
		local ok, reason = DistrictService.CanEnter(player, districtId)
		if not ok then
			return false, reason
		end
		lastTravel[player] = os.clock()
		local destination = DistrictService.SpawnCFrame(districtId)
			+ Vector3.new(math.random(-4, 4), 3.5, math.random(-4, 4))
		MovementGuard.AllowTeleport(player, destination.Position, 25)
		local profile = DataService.Get(player)
		if profile then
			profile.Stats.Travels = (profile.Stats.Travels or 0) + 1
			Events.StatChanged:Fire(player, "Travels")
		end
		return true, destination
	end)

	-- "Get me out of here": back to the plaza of the current district.
	Net.Handle("Travel.Spawn", function(player)
		if DistrictService.IsBusy and DistrictService.IsBusy(player) then
			return false, "Use retry during a run"
		end
		local district = MovementGuard.District(player) or "Hub"
		local destination = DistrictService.SpawnCFrame(district) + Vector3.new(0, 3.5, 0)
		MovementGuard.AllowTeleport(player, destination.Position, 25)
		return true, destination
	end)
end

return DistrictService

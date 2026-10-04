-- The Spire: 25 enclosed floors beside the Guildhall, each a short route from
-- the section library that asks for more of your movement kit the higher you
-- climb. Clear a floor to open the next; every fifth floor is a milestone, and
-- clearing the 25th lifts you onto the roof (a secret of its own).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Districts = require(ReplicatedStorage.Shared.Config.Districts)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Config.Progression)

local DataService = require(script.Parent.Parent.Data.DataService)
local Events = require(script.Parent.Parent.Events)
local Spire = require(script.Parent.Parent.World.Spire)
local WorldBuilder = require(script.Parent.Parent.World.WorldBuilder)
local CourseService = require(script.Parent.CourseService)
local MovementGuard = require(script.Parent.MovementGuard)
local Notify = require(script.Parent.Notify)
local ProgressionService = require(script.Parent.ProgressionService)

local TowerService = {}

local inTower: { [Player]: number } = {} -- current floor
local clearedAt: { [Player]: number } = {}

local function lobby(): CFrame
	local hub = Districts.ById.Hub
	local base = hub.Origin + Districts.SpireOffset
	return CFrame.lookAt(base + Vector3.new(0, 3.5, 0), hub.Origin + Vector3.new(0, 3.5, 0))
end

local function kitFor(meta: any): { [string]: boolean }
	local set = {}
	for _, list in { meta.Requires, meta.FastRequires, meta.ExpertRequires } do
		for _, id in list or {} do
			set[id] = true
		end
	end
	return set
end

local function highest(player: Player): number
	local profile = DataService.Get(player)
	return if profile then profile.Tower.Highest or 0 else 0
end

local function enter(player: Player, floor: number): (boolean, any)
	local meta = WorldBuilder.Courses["spire_" .. floor]
	if not meta then
		return false, "No such floor"
	end
	local ok, info = CourseService.Begin(player, "spire_" .. floor, "Tower", {
		NoRewards = true,
		SkipChecks = true,
		Standardized = false,
		Kit = kitFor(meta),
		Context = "Tower",
	})
	if ok then
		inTower[player] = floor
		info.Floor = floor
		info.Highest = highest(player)
	end
	return ok, info
end

local function onEnter(player: Player, floor: any): (boolean, any)
	local top = math.min(highest(player) + 1, Spire.Floors)
	local wanted = if type(floor) == "number" then math.clamp(math.floor(floor), 1, top) else top
	local base = lobby().Position
	local nearLift = MovementGuard.WasNear(player, base, 90, 3)
	if not nearLift and not inTower[player] then
		return false, "Take the Spire lift beside the Guildhall"
	end
	local run = CourseService.Active(player)
	if run and run.Context ~= nil and run.Context ~= "Tower" then
		return false, "Finish your current event first"
	end
	return enter(player, wanted)
end

-- Move on after a clear: the next floor, a retry, or (after the last) the roof.
local function onFloor(player: Player, floor: any): (boolean, any)
	if type(floor) ~= "number" or not inTower[player] then
		return false, "Not in the Spire"
	end
	-- Only from inside a floor (running it, or just after clearing it).
	local run = CourseService.Active(player)
	local running = run ~= nil and run.Context == "Tower"
	if not running and os.clock() - (clearedAt[player] or -math.huge) > 300 then
		inTower[player] = nil
		return false, "Take the Spire lift beside the Guildhall"
	end
	local top = highest(player)
	if floor == Spire.Floors + 1 then
		if top < Spire.Floors or not Spire.Roof then
			return false, "Clear the top floor first"
		end
		local roof = Spire.Roof :: CFrame
		MovementGuard.AllowTeleport(player, roof.Position, 20)
		inTower[player] = nil
		return true, { Roof = roof }
	end
	if floor < 1 or floor > math.min(top + 1, Spire.Floors) then
		return false, "That floor isn't open yet"
	end
	return enter(player, floor)
end

local function onLeave(player: Player): any
	inTower[player] = nil
	local run = CourseService.Active(player)
	if run and run.Context == "Tower" then
		CourseService.End(player, "Left")
	end
	local destination = lobby()
	MovementGuard.AllowTeleport(player, destination.Position, 20)
	return destination
end

local function onFinished(player: Player, run: any, result: any)
	if run.Mode ~= "Tower" or result.Rejected then
		return
	end
	local floor = tonumber(string.match(run.CourseId, "spire_(%d+)")) or 0
	local profile = DataService.Get(player)
	if not profile or floor == 0 then
		return
	end
	local tower = profile.Tower
	tower.Best = tower.Best or {}
	local key = tostring(floor)
	local previousBest = tower.Best[key]
	local first = floor > (tower.Highest or 0)
	if not previousBest or result.Seconds < previousBest then
		tower.Best[key] = result.Seconds
	end
	tower.Highest = math.max(tower.Highest or 0, floor)
	local factor = if first then 1 else 0.3
	local xp = math.floor(Progression.XP.TowerFloor * (1 + floor * 0.12) * factor)
	local credits = math.floor(Progression.Credits.TowerFloor * (1 + floor * 0.1) * factor)
	local prestige = if first and floor % 5 == 0 then Progression.Prestige.TowerMilestone else 0
	ProgressionService.Grant(player, { XP = xp, Credits = credits, Prestige = prestige }, nil, true)
	if prestige > 0 then
		Notify.Send(player, { Kind = "Unlock", Title = ("Spire milestone: floor %d"):format(floor), Prestige = prestige, Sound = "Unlock" })
	end
	DataService.Push(player, "Tower")
	DataService.MarkDirty(player)
	clearedAt[player] = os.clock()
	Events.TowerFloor:Fire(player, floor)
	Events.StatChanged:Fire(player, "TowerFloor")
	Net.Push(player, "Tower.Cleared", {
		Floor = floor,
		Seconds = result.Seconds,
		Best = tower.Best[key],
		PreviousBest = previousBest,
		First = first,
		XP = xp,
		Credits = credits,
		Prestige = prestige,
		Next = if floor < Spire.Floors then floor + 1 else nil,
		Roof = floor >= Spire.Floors,
		Highest = tower.Highest,
	})
end

function TowerService.Start()
	Net.Handle("Tower.Enter", onEnter)
	Net.Handle("Tower.Floor", onFloor)
	Net.Handle("Tower.Leave", onLeave)
	CourseService.Finished:Connect(onFinished)
	CourseService.Ended:Connect(function(player: Player, run: any, reason: string)
		if run.Mode == "Tower" and reason ~= "Replaced" then
			inTower[player] = nil
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		inTower[player] = nil
		clearedAt[player] = nil
	end)
end

return TowerService

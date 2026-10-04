-- Multiplayer races. Anyone can open a lobby for a course at a race board;
-- others join from the board or by invite. When everyone is ready the racers
-- line up on the start, the countdown runs, and every runner uses the same
-- standardized movement and the course's full kit. Places, times and rewards
-- are settled when the last runner finishes or the clock runs out.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Courses = require(ReplicatedStorage.Shared.Config.Courses)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Config.Progression)

local DataService = require(script.Parent.Parent.Data.DataService)
local Events = require(script.Parent.Parent.Events)
local WorldBuilder = require(script.Parent.Parent.World.WorldBuilder)
local CourseService = require(script.Parent.CourseService)
local DistrictService = require(script.Parent.DistrictService)
local Notify = require(script.Parent.Notify)
local ProgressionService = require(script.Parent.ProgressionService)
local RelayService = require(script.Parent.RelayService)

local RaceService = {}

local MAX_RACERS = 8
local COUNTDOWN = 5

type Lobby = {
	Id: string,
	CourseId: string,
	Host: Player,
	Members: { Player },
	Ready: { [Player]: boolean },
	State: string, -- "Lobby" | "Running"
	StartAt: number,
	Results: { { Player: Player, Seconds: number } },
	Racers: { Player },
	Deadline: number?,
	Round: number,
}

local lobbies: { [string]: Lobby } = {}
local memberOf: { [Player]: Lobby } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function summary(lobby: Lobby): { [string]: any }
	local members = {}
	for _, member in lobby.Members do
		table.insert(members, {
			UserId = member.UserId,
			Name = member.DisplayName,
			Level = member:GetAttribute("Level"),
			Ready = lobby.Ready[member] == true,
			Host = member == lobby.Host,
		})
	end
	local results = {}
	for place, entry in lobby.Results do
		table.insert(
			results,
			{ Place = place, UserId = entry.Player.UserId, Name = entry.Player.DisplayName, Seconds = entry.Seconds }
		)
	end
	local course = Courses.ById[lobby.CourseId]
	return {
		Id = lobby.Id,
		CourseId = lobby.CourseId,
		CourseName = if course then course.Name else lobby.CourseId,
		District = if course then course.District else "Hub",
		State = lobby.State,
		Members = members,
		Max = MAX_RACERS,
		StartAt = lobby.StartAt,
		Results = results,
		Round = lobby.Round,
	}
end

local function broadcast(lobby: Lobby)
	local data = summary(lobby)
	for _, member in lobby.Members do
		Net.Push(member, "Race.Lobby", data)
	end
end

local function leave(player: Player)
	local lobby = memberOf[player]
	if not lobby then
		return
	end
	memberOf[player] = nil
	local index = table.find(lobby.Members, player)
	if index then
		table.remove(lobby.Members, index)
	end
	lobby.Ready[player] = nil
	local run = CourseService.Active(player)
	if run and run.Context == lobby.Id then
		CourseService.End(player, "Left race")
	end
	Net.Push(player, "Race.Lobby", nil)
	if #lobby.Members == 0 then
		lobbies[lobby.Id] = nil
		return
	end
	if lobby.Host == player then
		lobby.Host = lobby.Members[1]
	end
	broadcast(lobby)
end

local function settle(lobby: Lobby)
	if lobby.State ~= "Running" then
		return
	end
	lobby.State = "Lobby"
	lobby.Deadline = nil
	local field = #lobby.Racers
	for place, entry in lobby.Results do
		local player = entry.Player
		local profile = DataService.Get(player)
		if profile then
			local win = place == 1 and field >= 2
			profile.Stats.RacesFinished = (profile.Stats.RacesFinished or 0) + 1
			if win then
				profile.Stats.RacesWon = (profile.Stats.RacesWon or 0) + 1
			end
			-- Larger fields pay a little more.
			local scale = 1 + math.min(field - 1, 7) * 0.08
			local xp = math.floor((if win then Progression.XP.RaceWin else Progression.XP.RaceFinish) * scale)
			local credits =
				math.floor((if win then Progression.Credits.RaceWin else Progression.Credits.RaceFinish) * scale)
			if field < 2 then
				xp, credits = math.floor(xp * 0.4), math.floor(credits * 0.4)
			end
			ProgressionService.Grant(player, { XP = xp, Credits = credits }, nil, true)
			DataService.MarkDirty(player)
			Events.RaceFinished:Fire(player, place, field)
			Events.StatChanged:Fire(player, "RacesFinished")
			if win then
				Events.StatChanged:Fire(player, "RacesWon")
			end
			Net.Push(player, "Race.Reward", { Place = place, Field = field, XP = xp, Credits = credits })
		end
	end
	-- Anyone still running didn't finish in time.
	for _, racer in lobby.Racers do
		local run = CourseService.Active(racer)
		if run and run.Context == lobby.Id then
			CourseService.End(racer, "Time")
		end
	end
	for _, member in lobby.Members do
		lobby.Ready[member] = false
	end
	broadcast(lobby)
end

local function begin(lobby: Lobby)
	local meta = WorldBuilder.Courses[lobby.CourseId]
	if not meta then
		return
	end
	lobby.State = "Running"
	lobby.Round += 1
	lobby.Results = {}
	lobby.Racers = table.clone(lobby.Members)
	lobby.StartAt = now() + COUNTDOWN
	-- Line up across the start, centre outwards.
	local slots = { 0, -2.5, 2.5, -5, 5, -1.25, 1.25, -3.75 }
	for index, racer in lobby.Racers do
		local spawn = meta.Spawn * CFrame.new(slots[index] or 0, 0, (index > 5 and 2.5 or 0))
		local ok = CourseService.Begin(racer, lobby.CourseId, "Race", {
			StartAt = lobby.StartAt,
			Context = lobby.Id,
			NoRewards = true,
			SkipChecks = true,
			Spawn = spawn,
		})
		if not ok then
			Notify.Warn(racer, "Couldn't join the start line.")
		end
	end
	-- Generous cut-off: well past the bronze time.
	local bronze = meta.Medals[1] or 120
	local deadline = lobby.StartAt + bronze * 1.5 + 20
	lobby.Deadline = deadline
	broadcast(lobby)
	local round = lobby.Round
	task.delay(deadline - now() + 0.5, function()
		if lobby.State == "Running" and lobby.Round == round then
			settle(lobby)
		end
	end)
end

-- Open races and relay teams in this server (for the race board).
local function onList(_: Player): any
	local list = {}
	for _, lobby in lobbies do
		table.insert(list, summary(lobby))
	end
	return { Races = list, Relays = RelayService.List() }
end

local function onCreate(player: Player, courseId: any): (boolean, any)
	if type(courseId) ~= "string" then
		return false, "Pick a course"
	end
	local course = Courses.ById[courseId]
	if not course or course.Kind ~= "Course" or not WorldBuilder.Courses[courseId] then
		return false, "Races run on district courses"
	end
	local ok, reason = DistrictService.CanEnter(player, course.District)
	if not ok then
		return false, reason
	end
	if CourseService.Active(player) then
		return false, "Finish your current run first"
	end
	leave(player)
	local lobby: Lobby = {
		Id = HttpService:GenerateGUID(false),
		CourseId = courseId,
		Host = player,
		Members = { player },
		Ready = {},
		State = "Lobby",
		StartAt = 0,
		Results = {},
		Racers = {},
		Deadline = nil,
		Round = 0,
	}
	lobbies[lobby.Id] = lobby
	memberOf[player] = lobby
	broadcast(lobby)
	return true, summary(lobby)
end

function RaceService.Join(player: Player, lobbyId: string): (boolean, any)
	local lobby = lobbies[lobbyId]
	if not lobby then
		return false, "That race has closed"
	end
	if memberOf[player] == lobby then
		return true, summary(lobby)
	end
	if #lobby.Members >= MAX_RACERS then
		return false, "The race is full"
	end
	if lobby.State ~= "Lobby" then
		return false, "That race has already started"
	end
	local course = Courses.ById[lobby.CourseId]
	if course then
		local ok, reason = DistrictService.CanEnter(player, course.District)
		if not ok then
			return false, reason
		end
	end
	if CourseService.Active(player) then
		return false, "Finish your current run first"
	end
	leave(player)
	table.insert(lobby.Members, player)
	memberOf[player] = lobby
	broadcast(lobby)
	return true, summary(lobby)
end

local function onJoin(player: Player, lobbyId: any): (boolean, any)
	if type(lobbyId) ~= "string" then
		return false, "Bad request"
	end
	return RaceService.Join(player, lobbyId)
end

local function onReady(player: Player, ready: any)
	local lobby = memberOf[player]
	if not lobby or lobby.State ~= "Lobby" then
		return
	end
	lobby.Ready[player] = ready == true
	local all = #lobby.Members > 0
	for _, member in lobby.Members do
		if not lobby.Ready[member] then
			all = false
		end
	end
	broadcast(lobby)
	if all then
		begin(lobby)
	end
end

function RaceService.LobbyOf(player: Player): string?
	local lobby = memberOf[player]
	return if lobby then lobby.Id else nil
end

function RaceService.Start()
	Net.Handle("Race.List", onList)
	Net.Handle("Race.Create", onCreate)
	Net.Handle("Race.Join", onJoin)
	Net.On("Race.Leave", leave)
	Net.On("Race.Ready", onReady)

	CourseService.Finished:Connect(function(player: Player, run: any, result: any)
		if run.Mode ~= "Race" then
			return
		end
		local lobby = lobbies[run.Context]
		if not lobby or lobby.State ~= "Running" or result.Rejected then
			return
		end
		table.insert(lobby.Results, { Player = player, Seconds = result.Seconds })
		broadcast(lobby)
		if #lobby.Results >= #lobby.Racers then
			settle(lobby)
		end
	end)
	CourseService.CheckpointReached:Connect(function(player: Player, run: any, index: number)
		if run.Mode ~= "Race" then
			return
		end
		local lobby = lobbies[run.Context]
		if lobby then
			for _, member in lobby.Members do
				if member ~= player then
					Net.Push(member, "Race.Progress", player.UserId, index)
				end
			end
		end
	end)
	CourseService.Ended:Connect(function(player: Player, run: any, reason: string)
		if run.Mode == "Race" and reason ~= "Time" then
			local lobby = lobbies[run.Context]
			if lobby and lobby.State == "Running" then
				local index = table.find(lobby.Racers, player)
				if index then
					table.remove(lobby.Racers, index)
				end
				if #lobby.Results >= #lobby.Racers then
					settle(lobby)
				else
					broadcast(lobby)
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(leave)
end

return RaceService

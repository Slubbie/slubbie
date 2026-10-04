-- Co-op relays. A relay course is split into legs at its exchange gates. A
-- team of up to one runner per leg readies up; each runner waits at their
-- exchange, and the baton passes the moment the runner before them crosses
-- it. Fewer runners than legs? Someone runs more than one leg. The team's
-- total time earns a shared medal on the relay course.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Courses = require(ReplicatedStorage.Shared.Config.Courses)
local Medals = require(ReplicatedStorage.Shared.Logic.Medals)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Config.Progression)

local DataService = require(script.Parent.Parent.Data.DataService)
local Events = require(script.Parent.Parent.Events)
local WorldBuilder = require(script.Parent.Parent.World.WorldBuilder)
local CourseService = require(script.Parent.CourseService)
local DistrictService = require(script.Parent.DistrictService)
local MovementGuard = require(script.Parent.MovementGuard)
local ProgressionService = require(script.Parent.ProgressionService)

local RelayService = {}

type Team = {
	Id: string,
	CourseId: string,
	Host: Player,
	Members: { Player },
	Ready: { [Player]: boolean },
	State: string, -- "Lobby" | "Running"
	Legs: { { Runner: Player, From: number, To: number? } },
	Leg: number,
	StartAt: number,
	LegTimes: { number },
}

local teams: { [string]: Team } = {}
local memberOf: { [Player]: Team } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function legCount(team: Team): number
	local meta = WorldBuilder.Courses[team.CourseId]
	return if meta then #meta.Exchanges + 1 else 1
end

local function summary(team: Team): { [string]: any }
	local members = {}
	for _, member in team.Members do
		table.insert(members, { UserId = member.UserId, Name = member.DisplayName, Ready = team.Ready[member] == true, Host = member == team.Host })
	end
	local legs = {}
	for index, leg in team.Legs do
		table.insert(legs, { Index = index, UserId = leg.Runner.UserId, Name = leg.Runner.DisplayName, Time = team.LegTimes[index] })
	end
	local course = Courses.ById[team.CourseId]
	return {
		Id = team.Id,
		CourseId = team.CourseId,
		CourseName = if course then course.Name else team.CourseId,
		State = team.State,
		Members = members,
		Max = legCount(team),
		Legs = legs,
		Leg = team.Leg,
		StartAt = team.StartAt,
	}
end

local function broadcast(team: Team)
	local data = summary(team)
	for _, member in team.Members do
		Net.Push(member, "Relay.Team", data)
	end
end

local function stop(team: Team, reason: string)
	if team.State ~= "Running" then
		return
	end
	team.State = "Lobby"
	for _, member in team.Members do
		team.Ready[member] = false
		local run = CourseService.Active(member)
		if run and run.Context == team.Id then
			CourseService.End(member, reason)
		end
	end
	for _, member in team.Members do
		Net.Push(member, "Relay.Stopped", reason)
	end
	broadcast(team)
end

local function leave(player: Player)
	local team = memberOf[player]
	if not team then
		return
	end
	if team.State == "Running" then
		stop(team, player.DisplayName .. " left the team")
	end
	memberOf[player] = nil
	local index = table.find(team.Members, player)
	if index then
		table.remove(team.Members, index)
	end
	team.Ready[player] = nil
	Net.Push(player, "Relay.Team", nil)
	if #team.Members == 0 then
		teams[team.Id] = nil
		return
	end
	if team.Host == player then
		team.Host = team.Members[1]
	end
	broadcast(team)
end

local function beginLeg(team: Team, index: number, startAt: number, inPlace: boolean)
	local leg = team.Legs[index]
	team.Leg = index
	local ok, reason = CourseService.Begin(leg.Runner, team.CourseId, "Relay", {
		StartAt = startAt,
		FromCheckpoint = leg.From,
		EndAt = leg.To,
		Context = team.Id,
		NoRewards = true,
		SkipChecks = true,
		NoTeleport = inPlace,
	})
	if not ok then
		stop(team, "Couldn't hand over: " .. tostring(reason))
		return
	end
	broadcast(team)
end

local function start(team: Team)
	local meta = WorldBuilder.Courses[team.CourseId]
	if not meta then
		return
	end
	team.State = "Running"
	team.LegTimes = {}
	team.Legs = {}
	local exchanges = meta.Exchanges
	local legs = #exchanges + 1
	for index = 1, legs do
		local runner = team.Members[(index - 1) % #team.Members + 1]
		table.insert(team.Legs, {
			Runner = runner,
			From = if index == 1 then 0 else exchanges[index - 1],
			To = if index <= #exchanges then exchanges[index] else nil,
		})
	end
	team.StartAt = now() + 4
	-- Waiting runners go to their exchange now.
	local placed: { [Player]: boolean } = { [team.Legs[1].Runner] = true }
	for index = 2, legs do
		local leg = team.Legs[index]
		if not placed[leg.Runner] then
			placed[leg.Runner] = true
			local checkpoint = meta.Checkpoints[leg.From]
			if checkpoint then
				MovementGuard.AllowTeleport(leg.Runner, checkpoint.Spawn.Position, 20)
				Net.Push(leg.Runner, "Relay.Wait", { Spawn = checkpoint.Spawn, Leg = index })
			end
		end
	end
	beginLeg(team, 1, team.StartAt, false)
end

local function finishRelay(team: Team, finalSeconds: number)
	local meta = WorldBuilder.Courses[team.CourseId]
	team.State = "Lobby"
	local total = finalSeconds
	local medal = if meta then Medals.For(total, meta.Medals) else 0
	local size = #team.Members
	for _, member in team.Members do
		team.Ready[member] = false
		local profile = DataService.Get(member)
		if profile then
			local record = profile.Courses[team.CourseId] or { Medal = 0, Completions = 0, Distinctions = {}, Tokens = {} }
			profile.Courses[team.CourseId] = record
			local first = (record.Completions or 0) == 0
			record.Completions = (record.Completions or 0) + 1
			record.Medal = math.max(record.Medal or 0, medal)
			if not record.Best or total < record.Best then
				record.Best = total
			end
			profile.Stats.RelaysFinished = (profile.Stats.RelaysFinished or 0) + 1
			local scale = (if first then 1.5 else 1) * (1 + (size - 1) * 0.15)
			local xp = math.floor(Progression.XP.RelayFinish * scale)
			local credits = math.floor(Progression.Credits.RelayFinish * scale)
			ProgressionService.Grant(member, { XP = xp, Credits = credits }, nil, true)
			DataService.Push(member, "Courses")
			DataService.MarkDirty(member)
			Events.RelayFinished:Fire(member, size)
			Events.StatChanged:Fire(member, "RelaysFinished")
			Net.Push(member, "Relay.Results", {
				CourseId = team.CourseId,
				Total = total,
				Medal = medal,
				LegTimes = team.LegTimes,
				Legs = summary(team).Legs,
				XP = xp,
				Credits = credits,
				TeamSize = size,
				Best = record.Best,
			})
		end
	end
	broadcast(team)
end

local function onCreate(player: Player, courseId: any): (boolean, any)
	local course = type(courseId) == "string" and Courses.ById[courseId]
	if not course or course.Kind ~= "Relay" or not WorldBuilder.Courses[courseId] then
		return false, "Pick a relay course"
	end
	local ok, reason = DistrictService.CanEnter(player, course.District)
	if not ok then
		return false, reason
	end
	if CourseService.Active(player) then
		return false, "Finish your current run first"
	end
	leave(player)
	local team: Team = {
		Id = HttpService:GenerateGUID(false),
		CourseId = courseId,
		Host = player,
		Members = { player },
		Ready = {},
		State = "Lobby",
		Legs = {},
		Leg = 0,
		StartAt = 0,
		LegTimes = {},
	}
	teams[team.Id] = team
	memberOf[player] = team
	broadcast(team)
	return true, summary(team)
end

function RelayService.Join(player: Player, teamId: string): (boolean, any)
	local team = teams[teamId]
	if not team then
		return false, "That team has disbanded"
	end
	if memberOf[player] == team then
		return true, summary(team)
	end
	if team.State ~= "Lobby" then
		return false, "They're mid-relay"
	end
	if #team.Members >= legCount(team) then
		return false, "The team is full"
	end
	local course = Courses.ById[team.CourseId]
	if course then
		local ok, reason = DistrictService.CanEnter(player, course.District)
		if not ok then
			return false, reason
		end
	end
	leave(player)
	table.insert(team.Members, player)
	memberOf[player] = team
	broadcast(team)
	return true, summary(team)
end

local function onJoin(player: Player, teamId: any): (boolean, any)
	if type(teamId) ~= "string" then
		return false, "Bad request"
	end
	return RelayService.Join(player, teamId)
end

local function onReady(player: Player, ready: any)
	local team = memberOf[player]
	if not team or team.State ~= "Lobby" then
		return
	end
	team.Ready[player] = ready == true
	local all = true
	for _, member in team.Members do
		if not team.Ready[member] then
			all = false
		end
	end
	broadcast(team)
	if all then
		start(team)
	end
end

function RelayService.TeamOf(player: Player): string?
	local team = memberOf[player]
	return if team then team.Id else nil
end

function RelayService.List(): { any }
	local list = {}
	for _, team in teams do
		table.insert(list, summary(team))
	end
	return list
end

function RelayService.Start()
	Net.Handle("Relay.Create", onCreate)
	Net.Handle("Relay.Join", onJoin)
	Net.On("Relay.Leave", leave)
	Net.On("Relay.Ready", onReady)

	CourseService.Finished:Connect(function(player: Player, run: any, result: any)
		if run.Mode ~= "Relay" then
			return
		end
		local team = teams[run.Context]
		if not team or team.State ~= "Running" or result.Rejected then
			return
		end
		local leg = team.Legs[team.Leg]
		if not leg or leg.Runner ~= player then
			return
		end
		team.LegTimes[team.Leg] = result.Seconds
		if team.Leg >= #team.Legs then
			-- Team time: from the first gun to the final finish.
			finishRelay(team, now() - team.StartAt)
			return
		end
		local nextLeg = team.Legs[team.Leg + 1]
		for _, member in team.Members do
			Net.Push(member, "Relay.Handoff", { From = player.UserId, To = nextLeg.Runner.UserId, Leg = team.Leg + 1 })
		end
		beginLeg(team, team.Leg + 1, now(), nextLeg.Runner == player)
	end)
	CourseService.Ended:Connect(function(player: Player, run: any, reason: string)
		if run.Mode == "Relay" and reason ~= "Replaced" then
			local team = teams[run.Context]
			if team and team.State == "Running" then
				stop(team, player.DisplayName .. " dropped the baton")
			end
		end
	end)
	Players.PlayerRemoving:Connect(leave)
end

return RelayService

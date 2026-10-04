-- Course runs: starting, checkpoints, tokens, shortcuts, retries, finishing,
-- medals, distinctions, rewards, personal records, leaderboards and ghosts.
--
-- Modes:
--   Casual    your own movement (skill tree applies); medals, rewards, records
--   Practice  assists allowed, custom checkpoints, no medals (learn a route)
--   Ranked    standardized attributes and the course's full kit; leaderboards
--             and ghosts. Upgrades never decide who's fastest.
--   Race / Relay / Tower  started by their services, which handle rewards
--
-- The client runs the timer for responsiveness; the server checks every
-- checkpoint against where the character actually was, enforces order,
-- bounds the finish time, and rejects impossible runs from the boards.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Abilities = require(ReplicatedStorage.Shared.Config.Abilities)
local Courses = require(ReplicatedStorage.Shared.Config.Courses)
local FlowConfig = require(ReplicatedStorage.Shared.Config.Flow)
local GhostCodec = require(ReplicatedStorage.Shared.Logic.GhostCodec)
local Medals = require(ReplicatedStorage.Shared.Logic.Medals)
local Net = require(ReplicatedStorage.Shared.Net)
local Rewards = require(ReplicatedStorage.Shared.Logic.Rewards)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local DataService = require(script.Parent.Parent.Data.DataService)
local Events = require(script.Parent.Parent.Events)
local WorldBuilder = require(script.Parent.Parent.World.WorldBuilder)
local DistrictService = require(script.Parent.DistrictService)
local MovementGuard = require(script.Parent.MovementGuard)
local Notify = require(script.Parent.Notify)
local ProgressionService = require(script.Parent.ProgressionService)
local RecordService = require(script.Parent.RecordService)

local CourseService = {}

-- (player, run, result) after every validated finish (any mode).
CourseService.Finished = Signal.new()
-- (player, run, index) after every validated checkpoint.
CourseService.CheckpointReached = Signal.new()
-- (player, run, reason) when a run ends without finishing.
CourseService.Ended = Signal.new()

export type Run = {
	Id: number,
	CourseId: string,
	Meta: any,
	Mode: string,
	StartAt: number, -- server time the clock starts
	StartClock: number, -- os.clock at the same moment (for strike checks)
	Checkpoint: number,
	Splits: { number },
	Tokens: { [number]: boolean },
	Shortcut: boolean,
	Falls: number,
	Retries: number,
	ServerFlow: number,
	FromCheckpoint: number,
	EndAt: number?, -- checkpoint index that ends this run (relay legs)
	NoRewards: boolean,
	Context: any,
	Standardized: boolean,
}

local runs: { [Player]: Run } = {}
local repeats: { [Player]: { [string]: number } } = {}
local pendingGhost: { [Player]: { CourseId: string, Seconds: number, Ranked: boolean, Expires: number } } = {}
local nextRunId = 0

local COUNTDOWN = { Casual = 3, Ranked = 3, Practice = 1.5, Race = 4, Relay = 3, Tower = 2 }

-- Helpers ----------------------------------------------------------------------------------

local function now(): number
	return workspace:GetServerTimeNow()
end

function CourseService.Meta(courseId: string): any?
	return WorldBuilder.Courses[courseId]
end

local function courseInfo(courseId: string, meta: any): (string, string, string, number)
	local course = Courses.ById[courseId]
	local name = if course then course.Name else (meta.Name or courseId)
	local district = meta.District or (course and course.District) or "Hub"
	local kind = meta.Kind or (course and course.Kind) or "Course"
	local difficulty = if course then course.Difficulty else (meta.Difficulty or 1)
	return name, district, kind, difficulty
end

local function recordFor(profile: any, courseId: string): any
	local record = profile.Courses[courseId]
	if not record then
		record = { Medal = 0, Completions = 0, Attempts = 0, Distinctions = {}, Tokens = {} }
		profile.Courses[courseId] = record
	end
	record.Distinctions = record.Distinctions or {}
	record.Tokens = record.Tokens or {}
	return record
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

local function missingAbilities(player: Player, meta: any): { string }
	local have = ProgressionService.Abilities(player)
	local missing = {}
	for _, id in meta.Requires or {} do
		if not have[id] then
			local ability = Abilities.ById[id]
			table.insert(missing, if ability then ability.Name else id)
		end
	end
	return missing
end

local function volumeNear(player: Player, volume: { CFrame: CFrame, Size: Vector3 }, slack: number?): boolean
	local radius = math.max(volume.Size.X, volume.Size.Y, volume.Size.Z) / 2 + (slack or 8)
	return MovementGuard.WasNear(player, volume.CFrame.Position, radius, 1.6)
end

local function spawnFor(run: Run): CFrame
	local meta = run.Meta
	if run.Checkpoint > 0 then
		local checkpoint = meta.Checkpoints[run.Checkpoint]
		if checkpoint then
			return checkpoint.Spawn
		end
	end
	return meta.Spawn
end

local function clearRun(player: Player, reason: string?)
	local run = runs[player]
	if not run then
		return
	end
	runs[player] = nil
	ProgressionService.SetTemporary(player, nil)
	if reason then
		CourseService.Ended:Fire(player, run, reason)
	end
end

-- Public API for other services --------------------------------------------------------------

export type BeginOptions = {
	Countdown: number?,
	StartAt: number?,
	FromCheckpoint: number?,
	EndAt: number?,
	NoRewards: boolean?,
	Context: any?,
	Standardized: boolean?,
	Kit: { [string]: boolean }?,
	SkipChecks: boolean?,
	Spawn: CFrame?,
	NoTeleport: boolean?, -- the runner is already in place (relay handoffs)
}

-- Start a run. Returns (ok, info | reason).
function CourseService.Begin(player: Player, courseId: string, mode: string, options: BeginOptions?): (boolean, any)
	local meta = WorldBuilder.Courses[courseId]
	local profile = DataService.Get(player)
	if not meta or not profile then
		return false, "Unknown course"
	end
	local opts = options or {}
	local _, district = courseInfo(courseId, meta)
	if not opts.SkipChecks then
		local ok, reason = DistrictService.CanEnter(player, district)
		if not ok then
			return false, reason
		end
		local missing = missingAbilities(player, meta)
		if #missing > 0 then
			return false, "Needs " .. table.concat(missing, ", ")
		end
	end
	clearRun(player, "Replaced")

	nextRunId += 1
	local countdown = opts.Countdown or COUNTDOWN[mode] or 3
	local startAt = opts.StartAt or (now() + countdown)
	local standardized = opts.Standardized
	if standardized == nil then
		standardized = mode == "Ranked" or mode == "Race" or mode == "Relay"
	end
	local run: Run = {
		Id = nextRunId,
		CourseId = courseId,
		Meta = meta,
		Mode = mode,
		StartAt = startAt,
		StartClock = os.clock() + (startAt - now()),
		Checkpoint = opts.FromCheckpoint or 0,
		Splits = {},
		Tokens = {},
		Shortcut = false,
		Falls = 0,
		Retries = 0,
		ServerFlow = 0,
		FromCheckpoint = opts.FromCheckpoint or 0,
		EndAt = opts.EndAt,
		NoRewards = opts.NoRewards == true,
		Context = opts.Context,
		Standardized = standardized,
	}
	runs[player] = run

	-- Ranked-style runs lend the full kit for the course so everyone races the same moves.
	local kit = opts.Kit
	if not kit and standardized then
		kit = kitFor(meta)
	end
	ProgressionService.SetTemporary(player, kit)

	local spawn = opts.Spawn or spawnFor(run)
	MovementGuard.AllowTeleport(player, spawn.Position, 20)
	local record = recordFor(profile, courseId)
	if mode ~= "Practice" then
		record.Attempts = (record.Attempts or 0) + 1
		DataService.MarkDirty(player)
	end
	local info = {
		RunId = run.Id,
		CourseId = courseId,
		Mode = mode,
		StartAt = startAt,
		Spawn = spawn,
		Standardized = standardized,
		FromCheckpoint = run.FromCheckpoint,
		EndAt = run.EndAt,
		BestSplits = if mode == "Ranked" then record.RankedSplits else record.Splits,
		Best = if mode == "Ranked" then record.RankedBest else record.Best,
		Context = opts.Context,
		NoTeleport = opts.NoTeleport == true,
		KillY = meta.KillY,
	}
	Net.Push(player, "Course.Run", info)
	return true, info
end

function CourseService.Active(player: Player): Run?
	return runs[player]
end

function CourseService.End(player: Player, reason: string?)
	clearRun(player, reason or "Ended")
	Net.Push(player, "Course.Ended", reason or "Ended")
end

-- Finishing --------------------------------------------------------------------------------------

local function finish(player: Player, run: Run, clientSeconds: any, clientFlow: any): any
	local meta = run.Meta
	local profile = DataService.Get(player)
	if not profile then
		return nil
	end
	local name, district, kind, difficulty = courseInfo(run.CourseId, meta)
	local serverSeconds = now() - run.StartAt
	local seconds = serverSeconds
	-- Trust the client's precise clock when it agrees with ours (latency allowance).
	if type(clientSeconds) == "number" and clientSeconds == clientSeconds then
		if clientSeconds <= serverSeconds + 0.3 and clientSeconds >= serverSeconds - 1.5 then
			seconds = clientSeconds
		end
	end
	seconds = math.floor(seconds * 1000 + 0.5) / 1000

	-- Plausibility: nothing beats the ideal par by this much.
	local par = math.min(meta.Par.A, meta.Par.F, meta.Par.E)
	local partial = run.FromCheckpoint > 0 or run.EndAt ~= nil
	if not partial and seconds < par * 0.45 then
		clearRun(player, "Rejected")
		Notify.Warn(player, "That run couldn't be verified.")
		return { Rejected = true }
	end
	local strikes = MovementGuard.StrikesSince(player, run.StartClock)
	local verified = strikes < 3

	-- Distinctions.
	local distinctions: { [string]: boolean } = {}
	if run.Falls == 0 and run.Retries == 0 then
		distinctions.NoFall = true
	end
	if run.Shortcut then
		distinctions.Shortcut = true
	end
	local tokenCount = 0
	for _ in run.Tokens do
		tokenCount += 1
	end
	if #meta.Tokens > 0 and tokenCount >= #meta.Tokens then
		distinctions.AllTokens = true
	end
	-- Flow: the client's score, capped by what the server's validated moves could earn.
	local flowScore = if type(clientFlow) == "number" and clientFlow == clientFlow then math.max(clientFlow, 0) else 0
	local cap = run.ServerFlow * 2.2 * (1 + FlowConfig.TransitionBonus) + seconds * 10 * 2.2
	flowScore = math.floor(math.min(flowScore, cap))
	if meta.FlowTarget and flowScore >= meta.FlowTarget * FlowConfig.DistinctionFraction then
		distinctions.Flow = true
	end

	local practice = run.Mode == "Practice"
	local medal = if practice or partial then 0 else Medals.For(seconds, meta.Medals)
	local record = recordFor(profile, run.CourseId)
	local previous = { Medal = record.Medal or 0, Best = record.Best, RankedBest = record.RankedBest, Completions = record.Completions or 0 }

	-- Rewards (modes with their own payouts skip these).
	local lines, xp, credits, prestige = {}, 0, 0, 0
	if not run.NoRewards and not partial then
		repeats[player] = repeats[player] or {}
		local count = repeats[player][run.CourseId] or 0
		repeats[player][run.CourseId] = count + 1
		local rewardMode = if practice then "Practice" else run.Mode
		lines, xp, credits, prestige = Rewards.Course(difficulty, meta.Medals, {
			Seconds = seconds,
			Medal = medal,
			Distinctions = distinctions,
			Mode = rewardMode,
		}, {
			Medal = record.Medal or 0,
			Completions = record.Completions or 0,
			Best = record.Best,
			Distinctions = record.Distinctions,
		}, count)
	end

	-- Records.
	local newBest, newRankedBest = false, false
	local newDistinctions = {}
	if not practice and not partial then
		record.Completions = (record.Completions or 0) + 1
		record.Medal = math.max(record.Medal or 0, medal)
		for id, earned in distinctions do
			if earned and not record.Distinctions[id] then
				record.Distinctions[id] = true
				table.insert(newDistinctions, id)
			end
		end
		if not record.Best or seconds < record.Best then
			record.Best = seconds
			record.Splits = run.Splits
			newBest = true
		end
		if run.Mode == "Ranked" and verified then
			if not record.RankedBest or seconds < record.RankedBest then
				record.RankedBest = seconds
				record.RankedSplits = run.Splits
				newRankedBest = true
			end
			RecordService.Submit(run.CourseId, player, seconds)
		end
		record.LastFlow = flowScore
		record.BestFlow = math.max(record.BestFlow or 0, flowScore)
		DataService.MarkDirty(player)
		DataService.Push(player, "Courses")
	end
	if newBest or newRankedBest then
		pendingGhost[player] = { CourseId = run.CourseId, Seconds = seconds, Ranked = newRankedBest, Expires = os.clock() + 60 }
	end
	if xp > 0 or credits > 0 or prestige > 0 then
		ProgressionService.Grant(player, { XP = xp, Credits = credits, Prestige = prestige }, nil, true)
	end

	local result = {
		CourseId = run.CourseId,
		Name = name,
		District = district,
		Kind = kind,
		Mode = run.Mode,
		Seconds = seconds,
		Medal = medal,
		PreviousMedal = previous.Medal,
		PreviousBest = if run.Mode == "Ranked" then previous.RankedBest else previous.Best,
		NewBest = if run.Mode == "Ranked" then newRankedBest else newBest,
		FirstCompletion = previous.Completions == 0 and not practice and not partial,
		Distinctions = distinctions,
		NewDistinctions = newDistinctions,
		Lines = lines,
		XP = xp,
		Credits = credits,
		Prestige = prestige,
		Tokens = tokenCount,
		TokenTotal = #meta.Tokens,
		Falls = run.Falls,
		Retries = run.Retries,
		Splits = run.Splits,
		Flow = flowScore,
		FlowTarget = meta.FlowTarget,
		Medals = meta.Medals,
		Verified = verified,
		Partial = partial,
	}
	clearRun(player, nil)
	if not partial then
		Events.CourseFinished:Fire(player, result)
	end
	CourseService.Finished:Fire(player, run, result)
	return result
end

-- Remote handlers ----------------------------------------------------------------------------------

local function onStart(player: Player, courseId: any, mode: any): (boolean, any)
	if type(courseId) ~= "string" or type(mode) ~= "string" then
		return false, "Bad request"
	end
	if mode ~= "Casual" and mode ~= "Practice" and mode ~= "Ranked" then
		return false, "Unknown mode"
	end
	local meta = WorldBuilder.Courses[courseId]
	local profile = DataService.Get(player)
	if not meta or not profile then
		return false, "Unknown course"
	end
	local _, _, kind = courseInfo(courseId, meta)
	if kind == "Tower" or kind == "Relay" then
		return false, "Use the board for this mode"
	end
	-- Start at the gate, or jump straight to a course you've already finished in this district.
	local nearStart = MovementGuard.WasNear(player, meta.Spawn.Position, 90, 3)
	if not nearStart then
		local record = profile.Courses[courseId]
		local _, district = courseInfo(courseId, meta)
		local here = MovementGuard.District(player)
		if not (record and (record.Completions or 0) > 0 and here == district) then
			return false, "Head to the start gate first"
		end
	end
	local existing = runs[player]
	if existing and existing.Context ~= nil then
		return false, "Finish or leave your current event first"
	end
	return CourseService.Begin(player, courseId, mode)
end

local function onCheckpoint(player: Player, index: any, clientSeconds: any, clientFlow: any): any
	local run = runs[player]
	if not run then
		return nil
	end
	if now() < run.StartAt - 0.25 then
		return nil
	end
	local meta = run.Meta
	if index == "Finish" then
		if run.EndAt then
			return nil
		end
		if run.Checkpoint < #meta.Checkpoints then
			return { Error = "Missed a checkpoint" }
		end
		if not volumeNear(player, meta.Finish, 10) then
			return nil
		end
		return finish(player, run, clientSeconds, clientFlow)
	end
	if type(index) ~= "number" or index ~= math.floor(index) then
		return nil
	end
	local checkpoint = meta.Checkpoints[index]
	if not checkpoint or index <= run.Checkpoint then
		return nil
	end
	if not volumeNear(player, checkpoint.Volume, 8) then
		return nil
	end
	run.Checkpoint = index
	local elapsed = now() - run.StartAt
	if type(clientSeconds) == "number" and clientSeconds <= elapsed + 0.3 and clientSeconds >= elapsed - 1.5 then
		elapsed = clientSeconds
	end
	run.Splits[index] = math.floor(elapsed * 1000 + 0.5) / 1000
	CourseService.CheckpointReached:Fire(player, run, index)
	if run.EndAt and index >= run.EndAt then
		-- A relay leg (or any partial run) ends at its exchange.
		return finish(player, run, clientSeconds, clientFlow)
	end
	return { Index = index, Split = run.Splits[index] }
end

local function onToken(player: Player, index: any)
	local run = runs[player]
	if not run or type(index) ~= "number" or run.Tokens[index] then
		return
	end
	local position = run.Meta.Tokens[index]
	if not position or not MovementGuard.WasNear(player, position, 10, 1.6) then
		return
	end
	run.Tokens[index] = true
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	profile.Stats.TokensCollected = (profile.Stats.TokensCollected or 0) + 1
	local record = recordFor(profile, run.CourseId)
	local first = not record.Tokens[tostring(index)]
	if first and run.Mode ~= "Practice" then
		record.Tokens[tostring(index)] = true
		ProgressionService.Grant(player, { XP = 10, Credits = 6 }, nil, true)
	end
	DataService.MarkDirty(player)
	Events.Token:Fire(player, run.CourseId, index)
	Events.StatChanged:Fire(player, "TokensCollected")
end

local function onShortcut(player: Player)
	local run = runs[player]
	if not run or run.Shortcut then
		return
	end
	for _, volume in run.Meta.Shortcuts or {} do
		if volumeNear(player, volume, 8) then
			run.Shortcut = true
			return
		end
	end
end

-- kind: "Checkpoint" (retry), "Fall", "Start" (restart), "Practice" (custom spot)
local function onRestart(player: Player, kind: any, position: any)
	local run = runs[player]
	if not run then
		return
	end
	if kind == "Start" then
		if run.Context ~= nil then
			return -- events (races, relays) can't be restarted
		end
		CourseService.Begin(player, run.CourseId, run.Mode, { SkipChecks = true })
		return
	end
	if kind == "Practice" then
		if run.Mode == "Practice" and typeof(position) == "Vector3" and MovementGuard.VisitedRecently(player, position, 12) then
			MovementGuard.AllowTeleport(player, position, 15)
		end
		return
	end
	if kind == "Fall" then
		run.Falls += 1
	else
		run.Retries += 1
	end
	MovementGuard.AllowTeleport(player, spawnFor(run).Position, 20)
end

local function onAbort(player: Player)
	local run = runs[player]
	if run and run.Context == nil then
		clearRun(player, "Abort")
	end
end

local function onGhostUpload(player: Player, courseId: any, encoded: any)
	local pending = pendingGhost[player]
	if not pending or pending.CourseId ~= courseId or os.clock() > pending.Expires then
		return
	end
	pendingGhost[player] = nil
	if not GhostCodec.Validate(encoded, pending.Seconds) then
		return
	end
	encoded.Time = pending.Seconds
	encoded.Name = player.DisplayName
	RecordService.SaveGhost(courseId, player.UserId, encoded)
	if pending.Ranked then
		RecordService.SaveGhost(courseId .. "#R", player.UserId, encoded)
	end
end

-- which: "Best" (yours) | "Ranked" (your ranked) | "Top" (board leader) | "Friend" (fastest friend)
local function onGetGhost(player: Player, courseId: any, which: any): any
	if type(courseId) ~= "string" or not WorldBuilder.Courses[courseId] then
		return nil
	end
	if which == "Best" then
		return RecordService.LoadGhost(courseId, player.UserId)
	elseif which == "Ranked" then
		return RecordService.LoadGhost(courseId .. "#R", player.UserId)
	elseif which == "Top" then
		for _, entry in RecordService.Top(courseId, 3) do
			local ghost = RecordService.LoadGhost(courseId .. "#R", entry.UserId)
			if ghost then
				return ghost
			end
		end
	elseif which == "Friend" then
		for _, entry in RecordService.Friends(courseId, player, 15) do
			if entry.UserId ~= player.UserId then
				local ghost = RecordService.LoadGhost(courseId .. "#R", entry.UserId)
				if ghost then
					return ghost
				end
			end
		end
	end
	return nil
end

local function onPreview(player: Player, courseId: any): any
	if type(courseId) ~= "string" then
		return nil
	end
	local meta = WorldBuilder.Courses[courseId]
	local profile = DataService.Get(player)
	if not meta or not profile then
		return nil
	end
	local _, district = courseInfo(courseId, meta)
	local canEnter, reason = DistrictService.CanEnter(player, district)
	local missing = missingAbilities(player, meta)
	local have = ProgressionService.Abilities(player)
	local function lacking(list: { string }): { string }
		local result = {}
		for _, id in list do
			if not have[id] then
				table.insert(result, id)
			end
		end
		return result
	end
	return {
		CourseId = courseId,
		Record = profile.Courses[courseId],
		Locked = if not canEnter then reason elseif #missing > 0 then "Needs " .. table.concat(missing, ", ") else nil,
		MissingFast = lacking(meta.FastRequires or {}),
		MissingExpert = lacking(meta.ExpertRequires or {}),
		Top = RecordService.Top(courseId, 5),
		Friends = RecordService.Friends(courseId, player, 15),
		Online = RecordService.Online(),
	}
end

local function onLeaderboard(player: Player, courseId: any, scope: any): any
	if type(courseId) ~= "string" or not WorldBuilder.Courses[courseId] then
		return nil
	end
	if scope == "Friends" then
		return RecordService.Friends(courseId, player, 40)
	end
	return RecordService.Top(courseId, 25)
end

function CourseService.Start()
	DistrictService.IsBusy = function(player: Player): boolean
		return runs[player] ~= nil
	end
	Net.Handle("Course.Start", onStart)
	Net.Handle("Course.Checkpoint", onCheckpoint)
	Net.On("Course.Token", onToken)
	Net.On("Course.Shortcut", onShortcut)
	Net.On("Course.Restart", onRestart)
	Net.On("Course.Abort", onAbort)
	Net.On("Course.Ghost", onGhostUpload)
	Net.Handle("Course.GetGhost", onGetGhost)
	Net.Handle("Course.Preview", onPreview)
	Net.Handle("Course.Leaderboard", onLeaderboard)

	-- Validated moves during a run bound the flow score it can claim.
	Events.Action:Connect(function(player: Player, action: string)
		local run = runs[player]
		if run then
			run.ServerFlow += FlowConfig.Points[action] or 0
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		clearRun(player, "Left")
		repeats[player] = nil
		pendingGhost[player] = nil
	end)
	-- A new character (death, travel reset) ends any run.
	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			if runs[player] and runs[player].Context == nil then
				clearRun(player, "Respawn")
				Net.Push(player, "Course.Ended", "Respawn")
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return CourseService

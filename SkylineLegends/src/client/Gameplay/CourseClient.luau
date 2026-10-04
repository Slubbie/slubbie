-- Course runs on the client: countdown, the timer, checkpoints and splits,
-- tokens and shortcuts, instant retries (tap Retry for your checkpoint, hold
-- it to restart), practice checkpoints, ghost recording and playback, and the
-- results screen. The server validates everything that matters.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MathUtil = require(ReplicatedStorage.Shared.Util.MathUtil)
local Net = require(ReplicatedStorage.Shared.Net)
local Schedule = require(ReplicatedStorage.Shared.Logic.Schedule)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Tags = require(ReplicatedStorage.Shared.Tags)

local Bus = require(script.Parent.Parent.Core.Bus)
local Input = require(script.Parent.Parent.Core.Input)
local Settings = require(script.Parent.Parent.Core.Settings)
local Controller = require(script.Parent.Parent.Movement.Controller)
local Hazards = require(script.Parent.Parent.World.Hazards)
local Mechanisms = require(script.Parent.Parent.World.Mechanisms)
local Animator = require(script.Parent.Parent.Animation.Animator)
local Music = require(script.Parent.Parent.Audio.Music)
local Sfx = require(script.Parent.Parent.Audio.Sfx)
local Flow = require(script.Parent.Flow)
local Ghosts = require(script.Parent.Ghosts)

local player = Players.LocalPlayer

local CourseClient = {}

CourseClient.Started = Signal.new() -- (run)
CourseClient.Ended = Signal.new() -- (reason)

export type Run = {
	CourseId: string,
	Name: string,
	Mode: string,
	Config: Configuration,
	StartAt: number,
	Checkpoint: number,
	CheckpointCount: number,
	BestSplits: { number }?,
	Best: number?,
	Splits: { number },
	Tokens: { [number]: boolean },
	TokenTotal: number,
	Context: any,
	EndAt: number?,
	Finishing: boolean,
	Mark: CFrame?,
	Medals: { number },
	Standardized: boolean,
	Shortcut: boolean,
}

CourseClient.Run = nil :: Run?
CourseClient.Assists = {} :: { [string]: boolean }

local volumes: { Checkpoints: { [number]: BasePart }, Finish: BasePart?, Shortcuts: { BasePart }, Tokens: { [number]: BasePart } } = {
	Checkpoints = {},
	Finish = nil,
	Shortcuts = {},
	Tokens = {},
}
local retryHeldSince: number? = nil
local tokenStreak = 0
local lastTokenAt = 0

-- Course data ----------------------------------------------------------------------------------------

function CourseClient.Config(courseId: string): Configuration?
	local folder = ReplicatedStorage:FindFirstChild("SkylineCourses")
	local config = folder and folder:FindFirstChild(courseId)
	return if config and config:IsA("Configuration") then config else nil
end

function CourseClient.All(): { Configuration }
	local folder = ReplicatedStorage:FindFirstChild("SkylineCourses")
	local result = {}
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("Configuration") then
				table.insert(result, child)
			end
		end
	end
	return result
end

function CourseClient.Medals(config: Configuration): { number }
	local medals = {}
	for i = 1, 4 do
		local value = config:GetAttribute("Medal" .. i)
		if type(value) == "number" then
			medals[i] = value
		end
	end
	return medals
end

function CourseClient.Elapsed(): number
	local run = CourseClient.Run
	if not run then
		return 0
	end
	return Schedule.Now() - run.StartAt
end

local function checkpointSpawn(run: Run): CFrame?
	if run.Mark then
		return run.Mark
	end
	if run.Checkpoint > 0 then
		local value = run.Config:GetAttribute("CP" .. run.Checkpoint)
		if typeof(value) == "CFrame" then
			return value
		end
	end
	local spawn = run.Config:GetAttribute("Spawn")
	return if typeof(spawn) == "CFrame" then spawn else nil
end

local function gatherVolumes(courseId: string)
	volumes.Checkpoints = {}
	volumes.Finish = nil
	volumes.Shortcuts = {}
	volumes.Tokens = {}
	for _, part in CollectionService:GetTagged(Tags.CourseCheckpoint) do
		if part:IsA("BasePart") and part:GetAttribute("CourseId") == courseId then
			local index = part:GetAttribute("Index")
			if type(index) == "number" then
				volumes.Checkpoints[index] = part
			end
		end
	end
	for _, part in CollectionService:GetTagged(Tags.CourseFinish) do
		if part:IsA("BasePart") and part:GetAttribute("CourseId") == courseId then
			volumes.Finish = part
		end
	end
	for _, part in CollectionService:GetTagged(Tags.CourseShortcut) do
		if part:IsA("BasePart") and part:GetAttribute("CourseId") == courseId then
			table.insert(volumes.Shortcuts, part)
		end
	end
	for _, part in CollectionService:GetTagged(Tags.CourseToken) do
		if part:IsA("BasePart") and part:GetAttribute("CourseId") == courseId then
			local index = part:GetAttribute("Index")
			if type(index) == "number" then
				volumes.Tokens[index] = part
				part.Transparency = 0
			end
		end
	end
end

-- Run lifecycle --------------------------------------------------------------------------------------

local function cleanup(reason: string)
	local run = CourseClient.Run
	if not run then
		return
	end
	CourseClient.Run = nil
	Hazards.PopHandler("Course")
	Hazards.KillY = nil
	Mechanisms.SetCourse(nil, 0)
	Controller.SetMode(false, nil)
	Controller.SetLock("Countdown", false)
	Flow.EndRun()
	Music.SetIntensity(0)
	Ghosts.Clear()
	Ghosts.EndRecording()
	for _, token in volumes.Tokens do
		token.Transparency = 0
	end
	CourseClient.Ended:Fire(reason)
end

local function loadGhosts(run: Run)
	Ghosts.Clear()
	if run.Context ~= nil and run.Mode ~= "Tower" then
		return
	end
	local choice = Settings.Get("DefaultGhost") or "Best"
	if choice == "None" then
		return
	end
	task.spawn(function()
		local mode: string = run.Mode
		local which = if choice == "Best" and mode == "Ranked" then "Ranked" elseif choice == "Last" then "Best" else choice
		local ok = Ghosts.Load(run.CourseId, which)
		if not ok and which ~= "Best" then
			Ghosts.Load(run.CourseId, "Best")
		end
	end)
end

local function onRun(info: any)
	if type(info) ~= "table" or type(info.CourseId) ~= "string" then
		return
	end
	local config = CourseClient.Config(info.CourseId)
	if not config then
		return
	end
	local previous = CourseClient.Run
	if previous then
		cleanup("Replaced")
	end
	local run: Run = {
		CourseId = info.CourseId,
		Name = config:GetAttribute("Name") or info.CourseId,
		Mode = info.Mode,
		Config = config,
		StartAt = info.StartAt,
		Checkpoint = info.FromCheckpoint or 0,
		CheckpointCount = config:GetAttribute("Checkpoints") or 0,
		BestSplits = info.BestSplits,
		Best = info.Best,
		Splits = {},
		Tokens = {},
		TokenTotal = config:GetAttribute("Tokens") or 0,
		Context = info.Context,
		EndAt = info.EndAt,
		Finishing = false,
		Mark = nil,
		Medals = CourseClient.Medals(config),
		Standardized = info.Standardized == true,
		Shortcut = false,
	}
	CourseClient.Run = run
	gatherVolumes(run.CourseId)

	Controller.SetMode(run.Standardized, if run.Mode == "Practice" then CourseClient.Assists else nil)
	if not info.NoTeleport and typeof(info.Spawn) == "CFrame" then
		Controller.Teleport(info.Spawn)
	end
	Mechanisms.ResetCourseState()
	Mechanisms.SetCourse(run.CourseId, run.Checkpoint, true)
	Hazards.KillY = if type(info.KillY) == "number" then info.KillY else config:GetAttribute("KillY")
	Hazards.PushHandler("Course", function(reason: string): CFrame?
		local current = CourseClient.Run
		if not current then
			return nil
		end
		local spawn = checkpointSpawn(current)
		if current.Mark then
			Net.Send("Course.Restart", "Practice", current.Mark.Position)
		else
			Net.Send("Course.Restart", if reason == "Retry" then "Checkpoint" else "Fall")
		end
		Mechanisms.SetCourse(current.CourseId, current.Checkpoint, true)
		Flow.Break("Respawn")
		return spawn
	end)
	Flow.BeginRun()
	Music.SetIntensity(if run.Mode == "Race" then 2 else 1)
	tokenStreak = 0

	-- Countdown: hold still until the gun.
	if Schedule.Now() < run.StartAt - 0.05 then
		Controller.SetLock("Countdown", true)
		Bus.Countdown:Fire(run.StartAt, run.Name)
		task.spawn(function()
			while CourseClient.Run == run and Schedule.Now() < run.StartAt do
				task.wait()
			end
			Controller.SetLock("Countdown", false)
		end)
	end
	Ghosts.BeginRecording()
	loadGhosts(run)
	CourseClient.Started:Fire(run)
end

local function showResults(run: Run, result: any)
	if type(result) ~= "table" then
		return
	end
	-- A new personal best leaves a ghost for next time.
	local encoded = Ghosts.EndRecording(run.Splits, result.Seconds)
	if result.NewBest and encoded then
		Net.Send("Course.Ghost", run.CourseId, encoded)
	end
	-- Celebrate.
	local character = player.Character
	local victory = character and character:GetAttribute("Victory")
	if type(victory) == "string" and (result.Medal or 0) > 0 then
		Animator.PlayEmote(victory)
		Net.Send("Emote.Play", victory)
	end
	if (result.Medal or 0) >= 4 then
		Sfx.Stinger("Platinum")
	elseif (result.Medal or 0) > (result.PreviousMedal or 0) then
		Sfx.Stinger("Medal")
	else
		Sfx.Stinger("Checkpoint")
	end
	Bus.CourseResults:Fire(result, run)
end

local function reachCheckpoint(run: Run, index: number)
	run.Checkpoint = index
	local elapsed = CourseClient.Elapsed()
	run.Splits[index] = elapsed
	local best = run.BestSplits and run.BestSplits[index]
	Bus.Split:Fire(index, elapsed, if type(best) == "number" then elapsed - best else nil)
	Sfx.Stinger("Checkpoint")
	Mechanisms.SetCourse(run.CourseId, index, false)
	if run.Mark then
		run.Mark = nil
	end
	task.spawn(function()
		local ok, response = pcall(Net.Invoke, "Course.Checkpoint", index, elapsed, Flow.RunScore())
		if ok and type(response) == "table" and response.Seconds and CourseClient.Run == run then
			-- A relay leg (partial run) finished here.
			cleanup("Leg")
			showResults(run, response)
		end
	end)
end

local function finish(run: Run)
	run.Finishing = true
	local elapsed = CourseClient.Elapsed()
	local flow = Flow.RunScore()
	task.spawn(function()
		local ok, result = pcall(Net.Invoke, "Course.Checkpoint", "Finish", elapsed, flow)
		if CourseClient.Run ~= run then
			return
		end
		if ok and type(result) == "table" and result.Error then
			run.Finishing = false
			Bus.Banner:Fire(result.Error, "Go back for it, or retry from your checkpoint.")
			return
		end
		cleanup("Finished")
		if ok and type(result) == "table" and not result.Rejected then
			showResults(run, result)
		end
	end)
end

local function step()
	local run = CourseClient.Run
	local root = Controller.Info.Root
	if not run or not root then
		return
	end
	local elapsed = CourseClient.Elapsed()
	Ghosts.Update(elapsed)
	if elapsed < 0 or run.Finishing then
		return
	end
	Ghosts.Sample(elapsed, root, Controller.Info.State)
	local position = root.Position

	-- Checkpoints in order.
	local nextIndex = run.Checkpoint + 1
	local volume = volumes.Checkpoints[nextIndex]
	if volume and MathUtil.InBox(volume.CFrame, volume.Size, position, 1) then
		reachCheckpoint(run, nextIndex)
	end
	-- Finish (only after every checkpoint, and not for relay legs).
	local finishPart = volumes.Finish
	if not run.EndAt and finishPart and run.Checkpoint >= run.CheckpointCount and MathUtil.InBox(finishPart.CFrame, finishPart.Size, position, 1) then
		finish(run)
		return
	end
	-- Shortcuts.
	if not run.Shortcut then
		for _, part in volumes.Shortcuts do
			if MathUtil.InBox(part.CFrame, part.Size, position, 1) then
				run.Shortcut = true
				Net.Send("Course.Shortcut")
				Bus.Banner:Fire("Expert line!", "Shortcut distinction in reach", Color3.fromRGB(255, 190, 90))
				Sfx.Stinger("Discover")
				break
			end
		end
	end
	-- Tokens: a short streak rises in pitch.
	for index, token in volumes.Tokens do
		if not run.Tokens[index] and (token.Position - position).Magnitude < 4.2 then
			run.Tokens[index] = true
			token.Transparency = 1
			Net.Send("Course.Token", index)
			if os.clock() - lastTokenAt < 2.5 then
				tokenStreak += 1
			else
				tokenStreak = 0
			end
			lastTokenAt = os.clock()
			Sfx.Tone(12 + math.min(tokenStreak, 7) * 2, 0.3)
		end
	end
end

-- Retry and practice ---------------------------------------------------------------------------------

local function onRetryPressed()
	if not CourseClient.Run then
		-- Outside courses Retry returns you to your last safe spot.
		Hazards.Respawn("Retry")
		return
	end
	retryHeldSince = os.clock()
end

local function onRetryReleased()
	local since = retryHeldSince
	retryHeldSince = nil
	local run = CourseClient.Run
	if not since or not run then
		return
	end
	if os.clock() - since < 0.55 then
		Hazards.Respawn("Retry")
	end
end

function CourseClient.Restart()
	local run = CourseClient.Run
	if not run or run.Context ~= nil and run.Mode ~= "Tower" then
		return
	end
	if run.Mode == "Tower" then
		task.spawn(pcall, Net.Invoke, "Tower.Floor", tonumber(string.match(run.CourseId, "%d+")))
		return
	end
	Net.Send("Course.Restart", "Start")
end

function CourseClient.Abort()
	local run = CourseClient.Run
	if not run then
		return
	end
	if run.Mode == "Tower" then
		task.spawn(function()
			local ok, destination = pcall(Net.Invoke, "Tower.Leave")
			if ok and typeof(destination) == "CFrame" then
				Controller.Teleport(destination)
			end
		end)
	elseif run.Mode == "Race" then
		Net.Send("Race.Leave")
	elseif run.Mode == "Relay" then
		Net.Send("Relay.Leave")
	else
		Net.Send("Course.Abort")
	end
	cleanup("Abort")
end

-- Start a course from the preview screen.
function CourseClient.Begin(courseId: string, mode: string, assists: { [string]: boolean }?): (boolean, string?)
	CourseClient.Assists = assists or {}
	local ok, success, info = pcall(Net.Invoke, "Course.Start", courseId, mode)
	if not ok then
		return false, "Couldn't reach the Guild"
	end
	if not success then
		return false, if type(info) == "string" then info else "Can't start that course"
	end
	return true, nil
end

function CourseClient.Start()
	Net.Listen("Course.Run", onRun)
	Net.Listen("Course.Ended", function(reason)
		cleanup(if type(reason) == "string" then reason else "Ended")
	end)
	Input.Pressed:Connect(function(action: string)
		if action == "Retry" then
			onRetryPressed()
		elseif action == "Mark" then
			local run = CourseClient.Run
			local root = Controller.Info.Root
			if run and run.Mode == "Practice" and root and Controller.Info.Grounded then
				run.Mark = root.CFrame
				Bus.Banner:Fire("Practice checkpoint set", "Retry brings you back here")
				Sfx.Stinger("Ready")
			end
		end
	end)
	Input.Released:Connect(function(action: string)
		if action == "Retry" then
			onRetryReleased()
		end
	end)
	RunService.Heartbeat:Connect(function()
		step()
		-- Holding Retry restarts the whole course.
		local since = retryHeldSince
		if since and os.clock() - since >= 0.55 then
			retryHeldSince = nil
			CourseClient.Restart()
		end
	end)
	player.CharacterAdded:Connect(function()
		cleanup("Respawn")
	end)
end

return CourseClient

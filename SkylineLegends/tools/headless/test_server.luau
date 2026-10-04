-- Boots the whole server headlessly, joins a simulated player and drives the
-- main loops through the real remote handlers: courses (casual run, tokens,
-- medal, rewards), quests and lessons, shop and skills, crews, races, relays,
-- the Spire, the Dreamline, contracts, dailies and settings.
--
-- Run: python3 tools/headless/run.py <luau> tools/headless/test_server.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local failures = 0
local function check(condition: any, text: string)
	if condition then
		print("ok    " .. text)
	else
		failures += 1
		print("FAIL  " .. text)
	end
end

-- Scheduler: real task semantics (spawn runs now, wait sleeps on a virtual clock).
local virtual = 1000
local sleeping = {}
local deferred = {}
local function resume(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		failures += 1
		print("ERROR in task: " .. tostring(err))
	end
end
Mock.task.spawn = function(fn, ...)
	local co = if type(fn) == "thread" then fn else coroutine.create(fn)
	resume(co, ...)
	return co
end
Mock.task.defer = function(fn, ...)
	table.insert(deferred, { coroutine.create(fn), table.pack(...) })
end
Mock.task.delay = function(t, fn, ...)
	table.insert(sleeping, { Co = coroutine.create(fn), At = virtual + (t or 0), Args = table.pack(...) })
end
Mock.task.wait = function(t)
	table.insert(sleeping, { Co = coroutine.running(), At = virtual + (t or 0.03), Args = table.pack() })
	return coroutine.yield()
end
local function tick(seconds: number?)
	virtual += seconds or 0.1
	local ready = deferred
	deferred = {}
	for _, entry in ready do
		resume(entry[1], table.unpack(entry[2], 1, entry[2].n))
	end
	local still = {}
	local due = {}
	for _, entry in sleeping do
		if entry.At <= virtual then
			table.insert(due, entry)
		else
			table.insert(still, entry)
		end
	end
	sleeping = still
	for _, entry in due do
		if coroutine.status(entry.Co) == "suspended" then
			resume(entry.Co, table.unpack(entry.Args, 1, entry.Args.n))
		end
	end
end
local function run(seconds: number)
	local steps = math.ceil(seconds / 0.1)
	for _ = 1, steps do
		tick(0.1)
	end
end
workspace.GetServerTimeNow = function()
	return virtual
end

-- Engine pieces the world test never needed.
local playerList = {}
Players.GetPlayers = function()
	return table.clone(playerList)
end
Players.GetPlayerByUserId = function(_, id)
	for _, p in playerList do
		if p.UserId == id then
			return p
		end
	end
	return nil
end
Players.GetNameFromUserIdAsync = function(_, id)
	return "User" .. tostring(id)
end
Players.GetFriendsAsync = function()
	error("friends unavailable in tests")
end
Players.GetHumanoidDescriptionFromUserId = function()
	return Instance.new("HumanoidDescription")
end
Players.CreateHumanoidModelFromDescription = function()
	local model = Instance.new("Model")
	local humanoid = Instance.new("Humanoid")
	humanoid.Health = 100
	humanoid.Parent = model
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Parent = model
	for _, name in { "Torso", "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg" } do
		local part = Instance.new("Part")
		part.Name = name
		part.Parent = model
	end
	local torso = model:FindFirstChild("Torso")
	for _, name in { "Neck", "Left Shoulder", "Right Shoulder", "Left Hip", "Right Hip" } do
		local motor = Instance.new("Motor6D")
		motor.Name = name
		motor.C0 = CFrame.new()
		motor.Parent = torso
	end
	local rootJoint = Instance.new("Motor6D")
	rootJoint.Name = "RootJoint"
	rootJoint.C0 = CFrame.new()
	rootJoint.Parent = root
	model.PrimaryPart = root
	return model
end
game:GetService("TextService").FilterStringAsync = function(_, text)
	return {
		GetNonChatStringForBroadcastAsync = function()
			return text
		end,
	}
end

-- Record what the server sends to clients.
local Net = require(ReplicatedStorage.Shared.Net)
local pushes = {}
local folder = ReplicatedStorage:FindFirstChild("SkylineNet")
local s2c = folder:FindFirstChild("S2C")
local c2s = folder:FindFirstChild("C2S")
local rpc = folder:FindFirstChild("RPC")
rawget(s2c, "_props").FireClient = function(_, _player, route, ...)
	table.insert(pushes, { Route = route, Args = table.pack(...) })
end
rawget(s2c, "_props").FireAllClients = function(_, route, ...)
	table.insert(pushes, { Route = route, Args = table.pack(...) })
end
local function lastPush(route: string): any
	for i = #pushes, 1, -1 do
		if pushes[i].Route == route then
			return pushes[i].Args
		end
	end
	return nil
end

-- Boot ------------------------------------------------------------------------------------------------
local serverScript = ServerScriptService:FindFirstChild("Server")
local boot = loadstring(rawget(serverScript, "_props").Source, "=Server")
setfenv(boot, setmetatable({ script = serverScript }, { __index = Mock.Env }))
local booted = coroutine.create(boot)
resume(booted)
run(2)
check(workspace:GetAttribute("SkylineReady") == true, "server finished booting")

local WorldBuilder = require(serverScript.World.WorldBuilder)
local DataService = require(serverScript.Data.DataService)
local Events = require(serverScript.Events)
local EconomyService = require(serverScript.Services.EconomyService)
local ProgressionService = require(serverScript.Services.ProgressionService)
local NPCs = require(ReplicatedStorage.Shared.Config.NPCs)
local Lessons = require(ReplicatedStorage.Shared.Config.Lessons)
local Districts = require(ReplicatedStorage.Shared.Config.Districts)

local npcFolder = workspace:FindFirstChild("SkylineNPCs")
check(
	npcFolder and #npcFolder:GetChildren() == #NPCs.List,
	("all %d NPCs placed (got %d)"):format(#NPCs.List, if npcFolder then #npcFolder:GetChildren() else 0)
)

-- Join -----------------------------------------------------------------------------------------------
local player = Instance.new("Player")
player.Name = "Tester"
player.DisplayName = "Tester"
player.UserId = 4242
player.IsFriendsWithAsync = function()
	return false
end
player.Kick = function() end
player.Parent = Players
table.insert(playerList, player)
Players.PlayerAdded:Fire(player)
run(3)

local profile = DataService.Get(player)
check(profile ~= nil, "profile loaded (in memory)")
check(profile and profile.Quests.Active.p_welcome ~= nil, "prologue quest starts automatically")
local character = player.Character
check(character ~= nil and character:FindFirstChild("HumanoidRootPart") ~= nil, "character spawned")
local root = character and character:FindFirstChild("HumanoidRootPart")

-- Remotes are rate limited on real time, like a real client: pace calls per route.
local lastCall: { [string]: number } = {}
local function pace(route: string)
	local gap = 0.2
	local since = os.clock() - (lastCall[route] or -1)
	if since < gap then
		local untilTime = os.clock() + (gap - since)
		while os.clock() < untilTime do
		end
	end
	lastCall[route] = os.clock()
end
local function invoke(route: string, ...): ...any
	pace(route)
	return rpc.OnServerInvoke(player, route, ...)
end
local function send(route: string, ...)
	pace(route)
	c2s.OnServerEvent:Fire(player, route, ...)
end
local function moveTo(position: Vector3)
	root.CFrame = CFrame.new(position)
	run(0.3)
end

local full = invoke("Profile.Get")
check(type(full) == "table" and full.Credits ~= nil, "Profile.Get returns the profile")

-- A casual course run ----------------------------------------------------------------------------------
local function runCourse(courseId: string, mode: string, seconds: number, collectTokens: boolean?): any
	local meta = WorldBuilder.Courses[courseId]
	moveTo(meta.Spawn.Position)
	local ok, info = invoke("Course.Start", courseId, mode)
	if not ok then
		print("   start failed: " .. tostring(info))
		return nil
	end
	virtual = info.StartAt + 0.5
	if collectTokens then
		for index, position in meta.Tokens do
			moveTo(position)
			send("Course.Token", index)
		end
	end
	for index, checkpoint in meta.Checkpoints do
		moveTo(checkpoint.Volume.CFrame.Position)
		local split = invoke("Course.Checkpoint", index, seconds * index / (#meta.Checkpoints + 1))
		if type(split) ~= "table" then
			print("   checkpoint " .. index .. " rejected")
		end
	end
	moveTo(meta.Finish.CFrame.Position)
	virtual = info.StartAt + seconds
	return invoke("Course.Checkpoint", "Finish", seconds, 50)
end

local graduation = WorldBuilder.Courses.hub_graduation
local preview = invoke("Course.Preview", "hub_graduation")
check(type(preview) == "table" and preview.Locked == nil, "graduation run preview is open to a new player")
local result = runCourse("hub_graduation", "Casual", graduation.Medals[3] - 1, true)
check(
	type(result) == "table" and result.Medal == 3,
	("casual run earns gold (got %s)"):format(tostring(result and result.Medal))
)
check(
	result and result.FirstCompletion == true and result.XP > 0 and result.Credits > 0,
	"first completion pays XP and credits"
)
check(
	result and result.Distinctions and result.Distinctions.AllTokens == true,
	"collecting every token earns the Collector distinction"
)
check(profile.Courses.hub_graduation and profile.Courses.hub_graduation.Medal == 3, "medal saved on the profile")
check(lastPush("Course.Run") ~= nil, "client told about the run")

-- Too fast is rejected.
local cheat = runCourse("hub_graduation", "Casual", 1)
check(type(cheat) == "table" and cheat.Rejected == true, "impossible finish time is rejected")

-- Ranked submission.
local ranked = runCourse("hub_graduation", "Ranked", graduation.Medals[2] - 1)
check(type(ranked) == "table" and ranked.Mode == "Ranked", "ranked run completes")
local board = invoke("Course.Leaderboard", "hub_graduation", "Top")
check(type(board) == "table" and #board == 1 and board[1].UserId == 4242, "ranked time appears on the leaderboard")

-- Quests and lessons -----------------------------------------------------------------------------------
local NPCService = require(serverScript.Services.NPCService)
moveTo(NPCService.Spots.tam.Position)
local talk = invoke("Quest.Talk", "tam")
check(type(talk) == "table" and #talk.Lines > 0, "talking to Coach Tam returns dialogue")
check(profile.Quests.Active.p_welcome and profile.Quests.Active.p_welcome.Step == 2, "talk step advances the prologue")
-- Clear six lessons with validated moves.
local cleared = 0
for _, part in game:GetService("CollectionService"):GetTagged("LessonZone") do
	local lesson = Lessons.ById[part:GetAttribute("LessonId")]
	if lesson and not lesson.Ability or (lesson and ProgressionService.HasAbility(player, lesson.Ability)) then
		for _, step in lesson.Steps do
			for _, action in step.Chain or { step.Action } do
				Events.Action:Fire(player, action, nil, "Hub")
			end
		end
		moveTo(part.Position)
		send("Lesson.Complete", lesson.Id)
		if profile.Lessons[lesson.Id] then
			cleared += 1
		end
	end
	if cleared >= 6 then
		break
	end
end
run(0.5)
check(cleared >= 6, ("six lessons cleared (got %d)"):format(cleared))
check(profile.Quests.Active.p_welcome and profile.Quests.Active.p_welcome.Step == 3, "lesson step completes")
moveTo(NPCService.Spots.orla.Position)
local orla = invoke("Quest.Talk", "orla")
check(profile.Quests.Completed.p_welcome ~= nil, "prologue quest completes")
check(type(orla) == "table" and #orla.Offers > 0, "Orla offers the next story quest")
local accepted = invoke("Quest.Accept", "p_graduation")
check(accepted == true, "graduation quest accepted")
run(0.5)
-- The course was already finished at gold, so the course step is satisfied straight away.
check(
	profile.Quests.Active.p_graduation and profile.Quests.Active.p_graduation.Step == 2,
	"already-finished course step completes on accept"
)
invoke("Quest.Talk", "orla")
check(profile.Flags.Graduated == true, "graduating sets the Graduated flag")

-- Economy, skills, cosmetics ---------------------------------------------------------------------------
ProgressionService.AddXP(player, 20000)
EconomyService.AddCredits(player, 5000)
check(ProgressionService.Level(player) >= 5, "XP raises the level")
local SkillTree = require(ReplicatedStorage.Shared.Config.SkillTree)
local okSkill, why = invoke("Skill.Unlock", SkillTree.Nodes[1].Id)
check(okSkill == true, "skill unlocked (" .. tostring(why) .. ")")
local Cosmetics = require(ReplicatedStorage.Shared.Config.Cosmetics)
local bought = false
for _, item in Cosmetics.List do
	if item.Source == "Shop" and not item.District and (item.Price or 0) <= 2000 then
		bought = invoke("Shop.Buy", item.Id)
		break
	end
end
check(bought == true, "bought a cosmetic in the shop")
send("Emote.Play", "Wave")
check(player.Character:GetAttribute("Emote") == "Wave", "equipped emote plays")
send("Settings.Save", { FieldOfView = 80, MouseSensitivity = 99 }, nil)
check(profile.Settings.FieldOfView == 80 and profile.Settings.MouseSensitivity == 3, "settings saved and clamped")

-- Dailies, contracts, crews ------------------------------------------------------------------------------
local daily = invoke("Quest.Claim")
check(type(daily) == "table" and #daily.Daily.Picks == 3 and #daily.Weekly.Picks == 3, "dailies and weeklies rolled")
local board2 = invoke("Contract.Take", "Hub")
check(type(board2) == "table" and #board2.Offers > 0, "job board has contract offers")
local okCrew, crew = invoke("Crew.Create", "Roof Runners", "rr")
check(okCrew == true and type(crew) == "table" and crew.Tag == "RR", "crew created")
check(player:GetAttribute("CrewTag") == "RR", "crew tag shown on the player")

-- Races ---------------------------------------------------------------------------------------------------
local okRace, lobby = invoke("Race.Create", "hub_graduation")
check(okRace == true, "race lobby opened")
send("Race.Ready", true)
local raceRun = lastPush("Course.Run")
check(raceRun and raceRun[1].Mode == "Race", "race starts when everyone is ready")
if raceRun then
	local info = raceRun[1]
	virtual = info.StartAt + 0.5
	for index, checkpoint in graduation.Checkpoints do
		moveTo(checkpoint.Volume.CFrame.Position)
		invoke("Course.Checkpoint", index, 5 * index)
	end
	moveTo(graduation.Finish.CFrame.Position)
	virtual = info.StartAt + graduation.Medals[3]
	invoke("Course.Checkpoint", "Finish", graduation.Medals[3], 0)
	run(0.5)
	check((profile.Stats.RacesFinished or 0) == 1, "race result recorded")
end
send("Race.Leave")
local _ = lobby

-- Relay -----------------------------------------------------------------------------------------------------
local relayMeta = WorldBuilder.Courses.relay_guild
local okRelay = invoke("Relay.Create", "relay_guild")
check(okRelay == true, "relay team formed")
send("Relay.Ready", true)
local legs = 0
for _ = 1, 6 do
	local leg = lastPush("Course.Run")
	if not leg or leg[1].Mode ~= "Relay" then
		break
	end
	local info = leg[1]
	virtual = math.max(virtual, info.StartAt) + 0.5
	local from = info.FromCheckpoint or 0
	local to = info.EndAt
	local finished = false
	for index = from + 1, #relayMeta.Checkpoints do
		moveTo(relayMeta.Checkpoints[index].Volume.CFrame.Position)
		virtual += 5
		local response = invoke("Course.Checkpoint", index, virtual - info.StartAt)
		if to and index >= to then
			finished = type(response) == "table" and response.Seconds ~= nil
			break
		end
	end
	if not to then
		moveTo(relayMeta.Finish.CFrame.Position)
		virtual += 5
		local response = invoke("Course.Checkpoint", "Finish", virtual - info.StartAt, 0)
		finished = type(response) == "table" and response.Seconds ~= nil
	end
	legs += 1
	if not to then
		break
	end
	check(finished, "relay leg " .. legs .. " handed off")
	table.insert(pushes, { Route = "noop", Args = table.pack() })
end
check((profile.Stats.RelaysFinished or 0) == 1, ("relay completed over %d legs"):format(legs))
send("Relay.Leave")

-- The Spire -------------------------------------------------------------------------------------------------
local base = Districts.ById.Hub.Origin + Districts.SpireOffset
moveTo(base)
local okTower, towerInfo = invoke("Tower.Enter", 1)
check(okTower == true, "Spire floor 1 entered")
if okTower then
	local floor = WorldBuilder.Courses.spire_1
	virtual = towerInfo.StartAt + 0.5
	for index, checkpoint in floor.Checkpoints do
		moveTo(checkpoint.Volume.CFrame.Position)
		invoke("Course.Checkpoint", index, 3 * index)
	end
	moveTo(floor.Finish.CFrame.Position)
	virtual = towerInfo.StartAt + floor.Par.A * 1.2
	invoke("Course.Checkpoint", "Finish", floor.Par.A * 1.2, 0)
	check(profile.Tower.Highest == 1, "Spire floor 1 cleared")
	check(lastPush("Tower.Cleared") ~= nil, "client told the floor is clear")
	local okNext = invoke("Tower.Floor", 2)
	check(okNext == true, "next floor opens")
	invoke("Tower.Leave")
end

-- The Dreamline ------------------------------------------------------------------------------------------------
moveTo(Districts.Dreamline)
local okEndless, lane = invoke("Endless.Start")
check(okEndless == true and type(lane) == "table", "Dreamline run started")
if okEndless then
	local EndlessService = require(serverScript.Services.EndlessService)
	local gates = 0
	for index = 1, 4 do
		local found = nil
		for _, part in game:GetService("CollectionService"):GetTagged("CourseCheckpoint") do
			if part:GetAttribute("CourseId") == lane.CourseId and part:GetAttribute("Index") == index then
				found = part
			end
		end
		if found then
			moveTo(found.Position)
			send("Endless.Gate", index)
			local state = lastPush("Endless.State")
			if state and state[1].Cleared == index then
				gates += 1
			end
		end
	end
	check(gates == 4, ("cleared %d Dreamline gates"):format(gates))
	for _ = 1, 3 do
		send("Endless.Gate", -1)
	end
	check(not EndlessService.Active(player), "three falls end the run")
	check(profile.Endless.Best == 4, "Dreamline record saved")
end

-- Social -----------------------------------------------------------------------------------------------------
local list = invoke("Social.Players")
check(type(list) == "table" and #list == 1 and list[1].You == true, "player list works")

-- Leaving saves and cleans up.
Players.PlayerRemoving:Fire(player)
table.remove(playerList, 1)
run(1)

-- Wrap up ------------------------------------------------------------------------------------------------------
run(5)
local warnings = 0
for _, text in Mock.Warnings do
	if
		not string.find(text, "DataStore")
		and not string.find(text, "No DataStore access")
		and not string.find(text, "API")
	then
		warnings += 1
	end
end
print(("warnings (excluding expected offline-data notes): %d"):format(warnings))
print(("failures: %d"):format(failures))
if failures > 0 then
	error("server test failed")
end

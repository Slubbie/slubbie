-- Boots the whole client headlessly against a fake server: builds the world,
-- spawns a local character, delivers a profile, runs frames of every system
-- (movement, mechanisms, animation, camera, audio, effects, HUD), then opens
-- every menu page and overlay and plays through a course run's client side.
-- Any error in a system, a frame, a page or an overlay fails the test.
--
-- Run: python3 tools/headless/run.py <luau> tools/headless/test_client.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local failures = 0
local function check(condition: any, text: string)
	if condition then
		print("ok    " .. text)
	else
		failures += 1
		print("FAIL  " .. text)
	end
end
local function try(label: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		failures += 1
		print("ERROR " .. label .. ": " .. tostring(err))
	end
end

-- Scheduler -------------------------------------------------------------------------------------------
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
	table.insert(sleeping, { Co = coroutine.running(), At = virtual + (t or 0.016), Args = table.pack() })
	return coroutine.yield()
end
workspace.GetServerTimeNow = function()
	return virtual
end

-- The world, built exactly as the server would.
local WorldBuilder = require(ServerScriptService.Server.World.WorldBuilder)
WorldBuilder.Build()
local Schema = require(ServerScriptService.Server.Data.Schema)

-- Client-side engine ----------------------------------------------------------------------------------
RunService.IsServer = function()
	return false
end
RunService.IsClient = function()
	return true
end
local renderSteps = {}
RunService.BindToRenderStep = function(_, name, _priority, fn)
	renderSteps[name] = fn
end
RunService.UnbindFromRenderStep = function(_, name)
	renderSteps[name] = nil
end

local net = Instance.new("Folder")
net.Name = "SkylineNet"
local c2s = Instance.new("RemoteEvent")
c2s.Name = "C2S"
c2s.Parent = net
local s2c = Instance.new("RemoteEvent")
s2c.Name = "S2C"
s2c.Parent = net
local rpc = Instance.new("RemoteFunction")
rpc.Name = "RPC"
rpc.Parent = net
net.Parent = ReplicatedStorage
local sent = {}
rawget(c2s, "_props").FireServer = function(_, route, ...)
	table.insert(sent, { Route = route, Args = table.pack(...) })
end

local profile = Schema.Default()
profile.XP = 6000
profile.Credits = 2400
-- A fake server answering invokes.
local Courses = require(ReplicatedStorage.Shared.Config.Courses)
local responses = {
	["Profile.Get"] = function()
		return profile, false
	end,
	["Course.Preview"] = function(courseId)
		return {
			CourseId = courseId,
			Record = nil,
			Top = { { UserId = 1, Name = "Vex", Seconds = 41.2, Rank = 1 } },
			Friends = {},
			Online = false,
			MissingFast = { "Dash" },
			MissingExpert = {},
		}
	end,
	["Course.Start"] = function()
		return false, "Head to the start gate first"
	end,
	["Course.Leaderboard"] = function()
		return { { UserId = 1, Name = "Vex", Seconds = 41.2, Rank = 1 } }
	end,
	["Course.GetGhost"] = function()
		return nil
	end,
	["Quest.Claim"] = function()
		return {
			Daily = { Picks = { "d_vault", "d_tokens", "d_flow" }, Progress = { d_vault = 4 }, Done = {} },
			Weekly = { Picks = { "w_tour", "w_gold", "w_spire" }, Progress = {}, Done = {} },
			NextDay = 3600,
			NextWeek = 86400,
		}
	end,
	["Contract.Take"] = function()
		return {
			Offers = {
				{
					Kind = "Course",
					Name = "Route Certification",
					Text = "Earn Silver on something.",
					Reward = { XP = 100, Credits = 80 },
				},
			},
			Refresh = 600,
		}
	end,
	["Race.List"] = function()
		return {
			Races = {
				{
					Id = "r1",
					CourseId = "hub_graduation",
					CourseName = "Graduation Run",
					State = "Lobby",
					Members = { { UserId = 2, Name = "Pria", Ready = false, Host = true } },
					Max = 8,
				},
			},
			Relays = {},
		}
	end,
	["Crew.Get"] = function()
		return {
			Id = "crew_1",
			Name = "Roof Runners",
			Tag = "RR",
			Members = { { UserId = 4242, Name = "Tester", Owner = true, Online = true } },
			Week = 1,
			Points = 70,
			Total = 300,
			Tiers = { 60, 180, 400 },
			Rewards = { { XP = 1 }, { XP = 2 }, { XP = 3 } },
			IsOwner = true,
			ResetIn = 5000,
		}
	end,
	["Social.Players"] = function()
		return {
			{ UserId = 4242, Name = "Tester", Level = 9, You = true, Activity = "Exploring", District = "Hub" },
			{
				UserId = 2,
				Name = "Pria",
				Level = 20,
				Friend = true,
				Crew = "RR",
				Activity = "Racing",
				District = "Tinroof",
			},
		}
	end,
	["Quest.Talk"] = function(npcId)
		return { Npc = npcId, Lines = { "Hello there.", "Second line." }, Offers = {}, Completed = {}, Service = "Shop" }
	end,
}
rawget(rpc, "_props").InvokeServer = function(_, route, ...)
	local fn = responses[route]
	if fn then
		return fn(...)
	end
	return nil
end
local function push(route: string, ...)
	s2c.OnClientEvent:Fire(route, ...)
end

-- Local player and character.
local player = Instance.new("Player")
player.Name = "Tester"
player.DisplayName = "Tester"
player.UserId = 4242
local playerGui = Instance.new("PlayerGui")
playerGui.Name = "PlayerGui"
playerGui.Parent = player
player.Parent = Players
Players.LocalPlayer = player
Players.GetPlayers = function()
	return { player }
end

local function makeCharacter(at: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Tester"
	local humanoid = Instance.new("Humanoid")
	humanoid.Health = 100
	humanoid.MoveDirection = Vector3.zero
	humanoid.FloorMaterial = Enum.Material.Concrete
	humanoid.Parent = model
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = at
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.AssemblyMass = 10
	root.Parent = model
	for _, name in { "Torso", "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg" } do
		local part = Instance.new("Part")
		part.Name = name
		part.Size = Vector3.new(1, 2, 1)
		part.CFrame = at
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
	model.Parent = workspace
	return model
end
local spawnAt = (WorldBuilder.Spawns.Training or WorldBuilder.Spawns.Hub) + Vector3.new(0, 3, 0)
local character = makeCharacter(spawnAt)
player.Character = character

local camera = Instance.new("Camera")
camera.Name = "Camera"
camera.CFrame = CFrame.new(spawnAt.Position + Vector3.new(0, 5, 15), spawnAt.Position)
camera.ViewportSize = Vector2.new(1280, 720)
camera.FieldOfView = 70
camera.WorldToViewportPoint = function(_, point)
	return Vector3.new(640, 360, 10), true
end
camera.Parent = workspace
workspace.CurrentCamera = camera

UserInputService.TouchEnabled = false
UserInputService.KeyboardEnabled = true
UserInputService.MouseBehavior = Enum.MouseBehavior.Default
UserInputService.GetMouseDelta = function()
	return Vector2.zero
end
UserInputService.IsMouseButtonPressed = function()
	return false
end
local cas = game:GetService("ContextActionService")
cas.BindActionAtPriority = function() end
cas.UnbindAction = function() end
local gui = game:GetService("GuiService")
gui.GetGuiInset = function()
	return Vector2.new(0, 36), Vector2.zero
end
game:GetService("StarterGui").SetCoreGuiEnabled = function() end
game:GetService("TweenService").Create = function()
	return { Play = function() end, Cancel = function() end, Completed = Mock.Signal() }
end

-- Frames -----------------------------------------------------------------------------------------------
local function frame(dt: number)
	virtual += dt
	local ready = deferred
	deferred = {}
	for _, entry in ready do
		resume(entry[1], table.unpack(entry[2], 1, entry[2].n))
	end
	local still, due = {}, {}
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
	try("PreSimulation", function()
		RunService.PreSimulation:Fire(dt)
	end)
	try("Heartbeat", function()
		RunService.Heartbeat:Fire(dt)
	end)
	try("RenderStepped", function()
		RunService.RenderStepped:Fire(dt)
	end)
	for name, fn in renderSteps do
		try("RenderStep " .. name, function()
			fn(dt)
		end)
	end
end
local function frames(seconds: number)
	for _ = 1, math.ceil(seconds * 60) do
		frame(1 / 60)
	end
end

-- Boot the client -------------------------------------------------------------------------------------
local clientScript = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client")
local boot = loadstring(rawget(clientScript, "_props").Source, "=Client")
setfenv(boot, setmetatable({ script = clientScript }, { __index = Mock.Env }))
local co = coroutine.create(boot)
resume(co)
-- The profile arrives, then the client finishes starting.
push("Profile.Full", profile, false)
frames(2)
check(coroutine.status(co) == "dead", "client bootstrap ran to completion")

local Client = clientScript
local Controller = require(Client.Movement.Controller)
local Bus = require(Client.Core.Bus)
local State = require(Client.Core.State)
local Menu = require(Client.UI.Menu)
local Overlay = require(Client.UI.Overlay)
local Flow = require(Client.Gameplay.Flow)
check(State.Profile ~= nil, "profile received")
check(Controller.Info.Root ~= nil, "controller attached to the character")
check(playerGui:FindFirstChild("SkylineHud") ~= nil, "HUD built")

-- Movement: walk, jump, run through states.
character.Humanoid.MoveDirection = Vector3.new(0, 0, -1)
frames(1)
try("action signals", function()
	for _, action in
		{
			"Jump",
			"Vault",
			"WallRun",
			"WallJump",
			"DoubleJump",
			"Dash",
			"Slide",
			"Roll",
			"LedgeGrab",
			"Grapple",
			"Zipline",
		}
	do
		Controller.Action:Fire(action)
	end
	Controller.Landed:Fire(80, "Hard")
	Controller.Landed:Fire(30, "Precision")
end)
frames(1)
check(Flow.Meter > 0, "flow meter fills from techniques")
for _, state in
	{
		"Air",
		"WallRun",
		"Ledge",
		"Climb",
		"Balance",
		"Zipline",
		"Swing",
		"Slide",
		"Roll",
		"Vault",
		"Mantle",
		"Dash",
		"Stumble",
		"Crouch",
	}
do
	Controller.Info.State = state
	Controller.Info.Aux = Vector3.new(1, 0, 0)
	Controller.Info.WallNormal = Vector3.new(1, 0, 0)
	Controller.Info.PathKind = if state == "Vault" then "Vault" elseif state == "Mantle" then "Mantle" else nil
	frames(0.2)
end
Controller.Info.State = "Ground"
character.Humanoid.MoveDirection = Vector3.zero

-- Every menu page.
local pages = {
	"Map",
	"Journal",
	"Skills",
	"Mastery",
	"Locker",
	"Shop",
	"Achievements",
	"Courses",
	"Records",
	"Races",
	"Crew",
	"Players",
	"Settings",
	"Travel",
	"Tower",
	"Jobs",
}
local warningsBefore = #Mock.Warnings
for _, page in pages do
	try("page " .. page, function()
		Bus.OpenPage:Fire(page, { District = "Hub" })
		frames(0.1)
	end)
	check(Menu.Current() == page, "menu page " .. page .. " opens")
end
-- Journal tabs and settings sections are separate code paths.
Menu.Close()
local pageErrors = 0
for i = warningsBefore + 1, #Mock.Warnings do
	if string.find(Mock.Warnings[i], "%[Menu%]") then
		pageErrors += 1
		print("   " .. Mock.Warnings[i])
	end
end
check(pageErrors == 0, "no page failed to draw")

-- Overlays.
try("course preview", function()
	Bus.CoursePreview:Fire("hub_graduation")
	frames(0.2)
end)
check(Overlay.IsOpen(), "course preview opens")
Overlay.CloseModal()
local graduation = WorldBuilder.Courses.hub_graduation
try("results", function()
	Bus.CourseResults:Fire({
		CourseId = "hub_graduation",
		Name = "Graduation Run",
		Mode = "Casual",
		Seconds = 42.5,
		Medal = 3,
		PreviousMedal = 1,
		PreviousBest = 50,
		NewBest = true,
		Distinctions = { NoFall = true },
		NewDistinctions = { "NoFall" },
		Lines = { { Label = "Gold medal", XP = 100, Credits = 40, Prestige = 0 } },
		Medals = graduation.Medals,
		Splits = { 10, 20 },
		Tokens = 3,
		TokenTotal = 6,
		Falls = 0,
		Retries = 0,
		Flow = 300,
		FlowTarget = 500,
	}, { Context = nil })
	frames(0.1)
end)
Overlay.CloseModal()
try("dialogue", function()
	Bus.Dialogue:Fire("orla", responses["Quest.Talk"]("orla"))
	frames(0.1)
end)
Overlay.CloseModal()
try("notifications", function()
	push("Notify", { Kind = "Reward", Title = "Test", XP = 10 })
	push("Notify", { Kind = "District", Title = "Tinroof Terraces", Text = "Washing lines" })
	push("Notify", { Kind = "Warning", Title = "Careful" })
	frames(0.2)
end)
try("mode panels", function()
	push(
		"Tower.Cleared",
		{ Floor = 3, Seconds = 30, Best = 30, First = true, XP = 50, Credits = 20, Next = 4, Highest = 3 }
	)
	frames(0.1)
	Overlay.CloseModal()
	push(
		"Endless.Ended",
		{
			Reason = "Out of lives",
			Cleared = 12,
			Best = 12,
			Record = true,
			XP = 70,
			Credits = 30,
			Seconds = 120,
			Lobby = spawnAt,
		}
	)
	frames(0.1)
	Overlay.CloseModal()
	push(
		"Race.Lobby",
		{
			Id = "r1",
			CourseName = "Graduation Run",
			State = "Running",
			Members = { { UserId = 4242, Name = "Tester" } },
			Results = {},
		}
	)
	frames(0.1)
end)

-- A course run on the client: countdown, checkpoints, tokens, finish request.
try("course run", function()
	push("Course.Run", {
		CourseId = "hub_graduation",
		Mode = "Casual",
		StartAt = virtual + 1,
		Spawn = graduation.Spawn,
		Standardized = false,
		FromCheckpoint = 0,
		KillY = graduation.KillY,
	})
	frames(1.5)
	for _, checkpoint in graduation.Checkpoints do
		character.HumanoidRootPart.CFrame = checkpoint.Volume.CFrame
		frames(0.2)
	end
	for _, position in graduation.Tokens do
		character.HumanoidRootPart.CFrame = CFrame.new(position)
		frames(0.05)
	end
end)
local CourseClient = require(Client.Gameplay.CourseClient)
check(
	CourseClient.Run ~= nil and CourseClient.Run.Checkpoint == #graduation.Checkpoints,
	"client tracked every checkpoint"
)
local tokenSends = 0
for _, entry in sent do
	if entry.Route == "Course.Token" then
		tokenSends += 1
	end
end
check(tokenSends == #graduation.Tokens, ("client collected every token (%d/%d)"):format(tokenSends, #graduation.Tokens))
try("course end", function()
	push("Course.Ended", "Abort")
	frames(0.5)
end)
check(CourseClient.Run == nil, "run cleaned up")

-- Falling out of the world respawns at a safe spot.
try("fall respawn", function()
	character.HumanoidRootPart.CFrame = spawnAt
	Controller.Info.Grounded = true
	frames(1)
	character.HumanoidRootPart.CFrame = CFrame.new(0, -5000, 0)
	frames(0.5)
end)

local warnings = 0
for _, text in Mock.Warnings do
	if not string.find(text, "DataStore") then
		warnings += 1
		print("   warning: " .. text)
	end
end
print(("warnings: %d"):format(warnings))
print(("failures: %d"):format(failures))
if failures > 0 then
	error("client test failed")
end

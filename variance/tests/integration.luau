--# selene: allow(global_usage, unused_variable, shadowing)
-- End-to-end integration test on the Roblox runtime mock (tests/mock).
--
-- Boots the real server (all services), joins players who each run the real
-- client (all controllers and screens), and plays the main flows with an
-- autopilot that acts only through the client's own HUD and requests:
-- orientation, solo matches, public PvP with a rematch, disconnect/reconnect,
-- private lobbies (Crossfire and a tournament), spectating, endurance,
-- sandbox, ranked, every lobby screen, malformed input, and a shutdown save.
--
-- Fails on any script error, engine-API misuse (the mock validates members
-- against the API dump), unexpected warning, or remote payload the Roblox
-- serializer would mangle.
--
--   luaurun tests/integration.luau            run everything
--   luaurun tests/integration.luau verbose    also echo game prints

local verbose = arg and arg[1] == "verbose"

---------------------------------------------------------------------------
-- Load the mock (plain file modules with script.Parent requires)
---------------------------------------------------------------------------

local loaded = {}
local function mockModule(name: string)
	if loaded[name] then
		return loaded[name]
	end
	local path = "tests/mock/" .. name .. ".luau"
	local source = __readfile(path)
	assert(source, "missing " .. path)
	local parent = setmetatable({}, {
		__index = function(_, child)
			return { __mock = child }
		end,
	})
	local env = setmetatable({
		script = { Parent = parent },
		require = function(ref)
			return mockModule(ref.__mock)
		end,
	}, { __index = _G })
	local value = __compile(source, "@" .. path, env)()
	loaded[name] = value
	return value
end

local World = mockModule("World")
local Scheduler = World.Scheduler
local Instances = World.Instances

local failures = {}
local passed = 0
local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
		print("PASS  " .. name)
	else
		table.insert(failures, name .. (detail and (": " .. detail) or ""))
		print("FAIL  " .. name .. (detail and ("\n      " .. detail) or ""))
	end
end

Scheduler.onError = function(ctx, err, trace)
	print("ERROR [" .. (ctx and ctx.Name or "?") .. "] " .. tostring(err))
	print(trace)
end

local world = World.new({ Verbose = verbose })
local services = world.Services
local ServerScripts = services.ServerScriptService.VarianceServer

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function serverModule(path: string)
	local cur = ServerScripts
	for part in string.gmatch(path, "[^%.]+") do
		cur = cur[part]
	end
	return world:require(world.Server, cur)
end

local function ctl(ctx, name: string)
	return world:require(ctx, ctx.Player.PlayerScripts.VarianceClient.Controllers[name])
end

local function screen(ctx, name: string)
	return ctl(ctx, "UIController"):screen(name)
end

-- Runs fn inside a context's thread and waits (virtual time) for it.
local function run(ctx, fn, ...)
	local done, results = false, nil
	Scheduler.spawnIn(ctx, function(...)
		results = table.pack(pcall(fn, ...))
		done = true
	end, ...)
	Scheduler.runUntil(function()
		return done
	end, 90)
	if not done then
		error("timed out waiting for " .. ctx.Name)
	end
	if not results[1] then
		error(results[2], 2)
	end
	return table.unpack(results, 2, results.n)
end

local function request(ctx, endpoint: string, ...)
	local args = table.pack(...)
	return run(ctx, function()
		return ctl(ctx, "NetworkClient"):request(endpoint, table.unpack(args, 1, args.n))
	end)
end

local function waitFor(predicate, timeout: number?): boolean
	return Scheduler.runUntil(predicate, timeout or 30)
end

local function inbox(player, kind: string)
	local out = {}
	for _, m in (world.Traffic and world.Traffic[player]) or {} do
		if m.Kind == kind then
			table.insert(out, m)
		end
	end
	return out
end

local function lastMessage(player, kind: string)
	local list = inbox(player, kind)
	return list[#list]
end

-- Presses a visible button by its label text (as a click would).
local function click(ctx, text: string): boolean
	local gui = ctx.Player.PlayerGui
	for _, d in gui:GetDescendants() do
		if d:IsA("TextButton") then
			local label = d:FindFirstChild("Text")
			if label and label:IsA("TextLabel") and label.Text == text then
				local visible = true
				local cur = d
				while cur and cur ~= gui do
					if cur:IsA("GuiObject") and not cur.Visible then
						visible = false
						break
					end
					cur = cur.Parent
				end
				if visible then
					Scheduler.spawnIn(ctx, function()
						Instances.fire(d, "Activated", { UserInputType = World.Enum.UserInputType.MouseButton1 })
					end)
					return true
				end
			end
		end
	end
	return false
end

---------------------------------------------------------------------------
-- Autopilot: plays through each client's own HUD
---------------------------------------------------------------------------

local pilots = {}
local rng = World.Types.Random.new(20260927)

local function enablePilot(ctx, options)
	pilots[ctx] = { Options = options or {}, Acted = nil, Answered = {}, Continued = {} }
end

local function pilotTutorial(ctx, pilot)
	local tutorial = ctl(ctx, "TutorialController")
	local status = tutorial.Status
	if status == nil or status.Done or status.Beat == nil then
		return false
	end
	local beat = status.Beat
	local key = tostring(status.Lesson) .. ":" .. tostring(status.Index) .. ":" .. tostring(status.Version)
	if beat.Advance == "Continue" or beat.Advance == "Finish" then
		if not pilot.Continued[key] then
			pilot.Continued[key] = true
			Scheduler.spawnIn(ctx, function()
				tutorial:continue()
			end)
		end
		return true
	elseif beat.Quiz then
		local tried = pilot.Answered[key] or 0
		if (status.LastAnswer == nil or not status.LastAnswer.Correct) and tried < #beat.Quiz.Options then
			pilot.Answered[key] = tried + 1
			Scheduler.spawnIn(ctx, function()
				tutorial:answer(tried + 1)
			end)
		end
		return true
	end
	return false
end

local function pilotTurn(ctx, pilot)
	local client = ctl(ctx, "MatchClient")
	if not client:isMyTurn() or client:busy() then
		return
	end
	local turn = client.TurnInfo
	if pilot.Acted and pilot.Acted.Token == turn.Token and Scheduler.now - pilot.Acted.At < 3 then
		return
	end
	pilot.Acted = { Token = turn.Token, At = Scheduler.now }
	local hud = screen(ctx, "MatchHUD")
	local tutorial = ctl(ctx, "TutorialController")
	local p = client:probability() or 0.5
	local uses = {}
	for _, a in turn.Legal or {} do
		if a.Kind == "Use" and a.Ok and (not tutorial:active() or tutorial:allows("Use", a.Id)) then
			table.insert(uses, a)
		end
	end
	Scheduler.spawnIn(ctx, function()
		if #uses > 0 and rng:NextNumber() < (pilot.Options.UseRate or 0.5) then
			local a = uses[rng:NextInteger(1, #uses)]
			hud:useSlot(a.Slot)
			return
		end
		local choice
		if pilot.Options.Always then
			choice = pilot.Options.Always
		elseif p <= 1e-6 then
			choice = "FireSelf"
		elseif p >= 0.5 then
			choice = "FireOther"
		else
			choice = if rng:NextNumber() < 0.5 then "FireSelf" else "FireOther"
		end
		if tutorial:active() then
			if choice == "FireSelf" and not tutorial:allows("FireSelf") then
				choice = "FireOther"
			elseif choice == "FireOther" and not tutorial:allows("FireOpponent") then
				choice = "FireSelf"
			end
		end
		hud:pressFire(choice, "Begin")
	end)
end

table.insert(Scheduler.frameHooks, function()
	for ctx, pilot in pilots do
		if ctx.Dead then
			pilots[ctx] = nil
		else
			local ok, err = pcall(function()
				if not pilotTutorial(ctx, pilot) then
					pilotTurn(ctx, pilot)
				end
			end)
			if not ok then
				print("pilot error: " .. tostring(err))
			end
		end
	end
end)

local function matchOf(ctx)
	return ctl(ctx, "MatchClient").Scene
end

local function inMatch(ctx): boolean
	return ctl(ctx, "MatchClient"):active()
end

local function postMatch(player)
	return lastMessage(player, "PostMatch")
end

local function playToEnd(ctx, player, timeout: number?)
	local before = #inbox(player, "PostMatch")
	return waitFor(function()
		return #inbox(player, "PostMatch") > before
	end, timeout or 900)
end

local function leave(ctx)
	request(ctx, "Match.Leave")
	return waitFor(function()
		return not inMatch(ctx)
	end, 20)
end

---------------------------------------------------------------------------
-- Scenarios
---------------------------------------------------------------------------

print("== boot")
world:start()
Scheduler.run(3)
check("server boots without errors", #Scheduler.errors == 0)
check("lobby built", world.Workspace:FindFirstChild("Intake") ~= nil)
check("arenas folder", world.Workspace:FindFirstChild("Arenas") ~= nil)
check("remotes created", services.ReplicatedStorage:FindFirstChild("VarianceNet") ~= nil)

print("== join")
local ada, adaCtx = world:addPlayer(1001, "Ada")
Scheduler.run(6)
local profile = ctl(adaCtx, "ProfileController"):get()
check("client ready", ada:GetAttribute("VarianceClientReady") == true)
check("profile reached the client", profile ~= nil and profile.Level == 1)
check(
	"character spawned in the lobby",
	ada.Character ~= nil and ada.Character:FindFirstChild("HumanoidRootPart") ~= nil
)
check("orientation offered", #inbox(ada, "OfferTutorial") >= 1)
check("lobby HUD open", screen(adaCtx, "LobbyHUD").Visible == true)
-- Dismiss the orientation offer through the modal.
click(adaCtx, "LATER")
Scheduler.run(1)

-- Prefer tap-to-fire and no rare confirmations for the autopilot.
run(adaCtx, function()
	local settings = ctl(adaCtx, "SettingsController")
	settings:set("FireConfirm", "Tap")
	settings:set("ConfirmItems", false)
end)
Scheduler.run(3)

print("== screens")
for _, name in { "Play", "Private", "Ranked", "Locker", "Challenges", "Archive", "Record", "Settings" } do
	local ok, err = pcall(function()
		run(adaCtx, function()
			local ui = ctl(adaCtx, "UIController")
			ui:open(name)
		end)
		Scheduler.run(1.5)
		local s = screen(adaCtx, name)
		if s.Window and s.Window.select then
			for _, tab in s.Window.TabStrip and s.Window.TabStrip:GetChildren() or {} do
				if tab:IsA("TextButton") then
					Scheduler.spawnIn(adaCtx, function()
						Instances.fire(tab, "Activated", { UserInputType = World.Enum.UserInputType.MouseButton1 })
					end)
					Scheduler.run(1.2)
				end
			end
		end
		run(adaCtx, function()
			ctl(adaCtx, "UIController"):close(name)
		end)
	end)
	check(
		"screen " .. name .. " opens and every tab renders",
		ok and #Scheduler.errors == 0,
		ok and nil or tostring(err)
	)
end
-- Read the first archive file.
run(adaCtx, function()
	local ui = ctl(adaCtx, "UIController")
	ui:open("Archive")
	screen(adaCtx, "Archive"):openFile("HDS-001")
end)
Scheduler.run(8)
run(adaCtx, function()
	ctl(adaCtx, "UIController"):close("Archive")
end)

print("== orientation")
enablePilot(adaCtx, { UseRate = 0.6 })
local ok, err = request(adaCtx, "Tutorial.Start", "Basic")
check("orientation starts", ok == true, tostring(err))
waitFor(function()
	return #inbox(ada, "TutorialComplete") > 0
end, 900)
check("orientation completes", #inbox(ada, "TutorialComplete") > 0)
Scheduler.run(8)
if inMatch(adaCtx) then
	leave(adaCtx)
end
Scheduler.run(3)
profile = ctl(adaCtx, "ProfileController"):get()
check("orientation recorded", profile and profile.Tutorial and profile.Tutorial.Basic == true)

print("== solo")
ok, err = request(adaCtx, "Solo.Start", "Volta", "Standard")
check("solo starts", ok == true, tostring(err))
waitFor(function()
	return inMatch(adaCtx)
end, 20)
check("solo scene begins", inMatch(adaCtx) and matchOf(adaCtx).Subjects[2].IsAI == true)
Scheduler.run(3)
local presenter = ctl(adaCtx, "MatchPresenter")
check("arena bound on the client", presenter:arena() ~= nil)
check(
	"rigs registered",
	ctl(adaCtx, "AnimationController"):rigOf(1) ~= nil and ctl(adaCtx, "AnimationController"):rigOf(2) ~= nil
)
check("camera at the seat", ctl(adaCtx, "CameraController"):mode() == "Seat")
check("solo match finishes", playToEnd(adaCtx, ada))
local pm = postMatch(ada)
check("post-match report", pm ~= nil and pm.Payload.Report ~= nil and pm.Payload.Rewards ~= nil)
Scheduler.run(2)
check("results screen open", ctl(adaCtx, "UIController"):currentScreen() == "PostMatch")
leave(adaCtx)
Scheduler.run(3)
profile = ctl(adaCtx, "ProfileController"):get()
check("stats recorded", profile.Stats.Matches >= 1 and profile.XP > 0)
check("back in the lobby", ctl(adaCtx, "CameraController"):mode() == "Lobby" and screen(adaCtx, "LobbyHUD").Visible)

print("== sandbox")
ok, err = request(adaCtx, "Sandbox.Start", {
	Base = "Chaos",
	TrialsToWin = 1,
	Capacity = 8,
	Modifiers = { "Echo", "Glass" },
	Bots = { { Personality = "Magpie", Difficulty = "Casual" } },
})
check("sandbox starts", ok == true, tostring(err))
check("sandbox finishes", playToEnd(adaCtx, ada, 600))
leave(adaCtx)

print("== pvp")
local bex, bexCtx = world:addPlayer(1002, "Bex")
Scheduler.run(6)
click(bexCtx, "LATER")
run(bexCtx, function()
	local settings = ctl(bexCtx, "SettingsController")
	settings:set("FireConfirm", "Confirm")
	settings:set("ConfirmItems", false)
end)
enablePilot(bexCtx, { UseRate = 0.4 })
-- Confirm mode: the pilot presses twice.
local oldPilot = pilotTurn
request(adaCtx, "Queue.Join", "Duel")
request(bexCtx, "Queue.Join", "Duel")
waitFor(function()
	return inMatch(adaCtx) and inMatch(bexCtx)
end, 30)
check("duel matched", inMatch(adaCtx) and inMatch(bexCtx) and matchOf(adaCtx).MatchId == matchOf(bexCtx).MatchId)
-- Bex uses "press twice": nudge a second press whenever armed.
table.insert(Scheduler.frameHooks, function()
	if bexCtx.Dead or not inMatch(bexCtx) then
		return
	end
	local hud = screen(bexCtx, "MatchHUD")
	if hud.Armed and Scheduler.now - (hud.ArmedNudge or 0) > 0.3 then
		hud.ArmedNudge = Scheduler.now
		local action = hud.Armed.Action
		Scheduler.spawnIn(bexCtx, function()
			hud:pressFire(action, "Begin")
		end)
	end
end)
local adaBefore, bexBefore = #inbox(ada, "PostMatch"), #inbox(bex, "PostMatch")
waitFor(function()
	return #inbox(ada, "PostMatch") > adaBefore and #inbox(bex, "PostMatch") > bexBefore
end, 900)
check("duel finishes for both", #inbox(ada, "PostMatch") > adaBefore and #inbox(bex, "PostMatch") > bexBefore)
Scheduler.run(2)
request(adaCtx, "Match.Rematch", true)
request(bexCtx, "Match.Rematch", true)
local matchBefore = matchOf(adaCtx) and matchOf(adaCtx).MatchId
waitFor(function()
	local s = matchOf(adaCtx)
	return s ~= nil and s.MatchId ~= matchBefore
end, 30)
check("rematch starts", matchOf(adaCtx) ~= nil and matchOf(adaCtx).MatchId ~= matchBefore)

print("== disconnect and reconnect")
Scheduler.run(15)
world:removePlayer(bex)
Scheduler.run(5)
local presence = lastMessage(ada, "Match")
check("opponent sees the disconnect", #inbox(ada, "Presence") >= 1)
local bex2, bex2Ctx = world:addPlayer(1002, "Bex")
waitFor(function()
	return inMatch(bex2Ctx)
end, 20)
check(
	"same-server rejoin returns to the seat automatically",
	inMatch(bex2Ctx) and matchOf(bex2Ctx).MatchId == matchOf(adaCtx).MatchId
)
check("opponent told about the return", #inbox(ada, "Presence") >= 2)
enablePilot(bex2Ctx, { UseRate = 0.3 })
run(bex2Ctx, function()
	ctl(bex2Ctx, "SettingsController"):set("FireConfirm", "Tap")
end)
Scheduler.run(10)
-- Bex forfeits through the menu path.
request(bex2Ctx, "Match.Forfeit")
check("forfeit ends the trial", playToEnd(adaCtx, ada, 60))
local forfeitReport = postMatch(ada)
check("forfeit winner", forfeitReport and forfeitReport.Payload.Report.Reason == "Forfeit")
leave(adaCtx)
if inMatch(bex2Ctx) then
	leave(bex2Ctx)
end
Scheduler.run(3)

print("== spectate")
ok, err = request(adaCtx, "Solo.Start", "Ledger", "Casual")
Scheduler.run(8)
local list = run(bex2Ctx, function()
	return ctl(bex2Ctx, "SpectatorController"):list()
end)
check("live trial listed", type(list) == "table" and #list >= 1)
if list and list[1] then
	run(bex2Ctx, function()
		ctl(bex2Ctx, "SpectatorController"):watch(list[1].MatchId)
	end)
	waitFor(function()
		return ctl(bex2Ctx, "MatchClient"):spectating()
	end, 20)
	check("spectating", ctl(bex2Ctx, "MatchClient"):spectating() == true)
	Scheduler.run(20)
	check("spectator camera", ctl(bex2Ctx, "CameraController"):mode() == "Spectate")
	run(bex2Ctx, function()
		ctl(bex2Ctx, "SpectatorController"):cycle(1)
	end)
	Scheduler.run(5)
	request(bex2Ctx, "Spectate.Stop")
	waitFor(function()
		return not inMatch(bex2Ctx)
	end, 20)
	check("spectating stops", not inMatch(bex2Ctx))
end
check("watched solo finishes", playToEnd(adaCtx, ada, 900))
leave(adaCtx)

print("== private lobby: crossfire")
ok, err = request(adaCtx, "Lobby.Create")
check("lobby created", ok == true, tostring(err))
Scheduler.run(1)
local lobbyState = lastMessage(ada, "Lobby")
local code = lobbyState and lobbyState.Payload and lobbyState.Payload.Code
check("invite code", type(code) == "string" and #code >= 4)
run(adaCtx, function()
	ctl(adaCtx, "UIController"):open("Private")
end)
Scheduler.run(1)
ok, err = request(bex2Ctx, "Lobby.Join", code)
check("friend joins by code", ok == true, tostring(err))
request(adaCtx, "Lobby.AddBot", "Kismet", "Standard")
request(adaCtx, "Lobby.SetRules", { TrialsToWin = 1, TurnTimer = 30, Modifiers = { "Surplus" } })
request(bex2Ctx, "Lobby.SetReady", true)
Scheduler.run(2)
ok, err = request(adaCtx, "Lobby.Start")
check("crossfire starts", ok == true, tostring(err))
waitFor(function()
	return inMatch(adaCtx) and inMatch(bex2Ctx)
end, 20)
check("three subjects seated", inMatch(adaCtx) and matchOf(adaCtx) ~= nil and #matchOf(adaCtx).Subjects == 3)
check("crossfire finishes", playToEnd(adaCtx, ada, 900))
leave(adaCtx)
if inMatch(bex2Ctx) then
	leave(bex2Ctx)
end
Scheduler.run(3)

print("== private lobby: tournament")
request(adaCtx, "Lobby.SetFormat", "Tournament")
request(adaCtx, "Lobby.AddBot", "Magpie", "Casual")
request(adaCtx, "Lobby.SetReady", true)
request(bex2Ctx, "Lobby.SetReady", true)
Scheduler.run(2)
ok, err = request(adaCtx, "Lobby.Start")
check("tournament starts", ok == true, tostring(err))
waitFor(function()
	local last = lastMessage(ada, "Lobby")
	local t = last and last.Payload and last.Payload.Tournament
	return t ~= nil and t.Champion ~= nil
end, 2400)
local lastLobby = lastMessage(ada, "Lobby")
check(
	"tournament crowns a champion",
	lastLobby and lastLobby.Payload and lastLobby.Payload.Tournament and lastLobby.Payload.Tournament.Champion ~= nil
)
Scheduler.run(5)
for _, ctx in { adaCtx, bex2Ctx } do
	if inMatch(ctx) then
		leave(ctx)
	end
end
request(adaCtx, "Lobby.Leave")
request(bex2Ctx, "Lobby.Leave")
Scheduler.run(3)

print("== ranked")
request(adaCtx, "Queue.Join", "Ranked")
request(bex2Ctx, "Queue.Join", "Ranked")
waitFor(function()
	return inMatch(adaCtx) and inMatch(bex2Ctx)
end, 60)
check("ranked matched", inMatch(adaCtx) and matchOf(adaCtx).Rules.Ranked == true)
check("ranked preview on the versus card", matchOf(adaCtx) and matchOf(adaCtx).RankedPreview ~= nil)
check("ranked finishes", playToEnd(adaCtx, ada, 900))
local rated = postMatch(ada)
check("rating change reported", rated and rated.Payload.Rating ~= nil and type(rated.Payload.Rating.Delta) == "number")
leave(adaCtx)
if inMatch(bex2Ctx) then
	leave(bex2Ctx)
end

print("== endurance")
pilots[adaCtx].Options.Always = "FireSelf"
ok, err = request(adaCtx, "Endurance.Start")
check("endurance starts", ok == true, tostring(err))
waitFor(function()
	for _, m in inbox(ada, "Endurance") do
		if m.Payload and m.Payload.Finished then
			return true
		end
	end
	return false
end, 3000)
local finished = false
for _, m in inbox(ada, "Endurance") do
	if m.Payload and m.Payload.Finished then
		finished = true
	end
end
check("endurance run ends with a summary", finished)
pilots[adaCtx].Options.Always = nil
Scheduler.run(5)
if inMatch(adaCtx) then
	leave(adaCtx)
end

print("== input, settings and presentation")
-- Keyboard input reaches the action map (fake InputObjects carry what handlers read).
local function key(ctx, name: string, down: boolean)
	local uis = services.UserInputService
	local input = {
		UserInputType = World.Enum.UserInputType.Keyboard,
		KeyCode = World.Enum.KeyCode[name],
		Position = World.Types.Vector3.zero,
		Delta = World.Types.Vector3.zero,
	}
	Scheduler.spawnIn(ctx, function()
		Instances.fire(uis, if down then "InputBegan" else "InputEnded", input, false)
	end)
end
local actions = {}
local actionConn = nil
run(adaCtx, function()
	actionConn = ctl(adaCtx, "InputController").Action:Connect(function(action, phase)
		if phase == "Begin" then
			table.insert(actions, action)
		end
	end)
end)
for _, k in { "Q", "E", "One", "Tab", "L", "G", "M" } do
	key(adaCtx, k, true)
	Scheduler.run(0.1)
	key(adaCtx, k, false)
end
Scheduler.run(1)
check("keyboard maps to actions", #actions >= 7, table.concat(actions, ","))
-- Rebinding moves an action to a new key.
run(adaCtx, function()
	local settings = ctl(adaCtx, "SettingsController")
	local binds = {}
	binds.FireSelf = "Z"
	settings:set("Binds", binds)
end)
Scheduler.run(1)
table.clear(actions)
key(adaCtx, "Z", true)
Scheduler.run(0.2)
check("rebound key fires its action", table.find(actions, "FireSelf") ~= nil)
-- Every palette, contrast, motion and quality setting applies live.
run(adaCtx, function()
	local settings = ctl(adaCtx, "SettingsController")
	for _, palette in { "Deuteranopia", "Protanopia", "Tritanopia", "Monochrome", "Default" } do
		settings:set("Palette", palette)
	end
	settings:set("HighContrast", true)
	settings:set("ReducedMotion", true)
	settings:set("ReducedFlashing", true)
	settings:set("TextScale", 1.3)
	for _, q in { "Low", "Medium", "Ultra", "Auto" } do
		settings:set("GraphicsQuality", q)
	end
	settings:set("HighContrast", false)
	settings:set("ReducedMotion", false)
	settings:set("TextScale", 1)
end)
Scheduler.run(3)
check("settings apply without errors", #Scheduler.errors == 0)

-- A match with emotes, every ambient event and the debug panel.
ok, err = request(adaCtx, "Solo.Start", "Kismet", "Advanced")
waitFor(function()
	return inMatch(adaCtx)
end, 20)
Scheduler.run(10)
local okEmote, whyEmote = request(adaCtx, "Match.Emote", "emote_nod")
check("table emote accepted", okEmote == true, tostring(whyEmote))
Scheduler.run(2)
for _, kind in
	{
		"PowerDip",
		"CameraTurn",
		"Monitor",
		"Vent",
		"Announcement",
		"Silhouette",
		"Warning",
		"ProctorWatching",
		"ObserverSurge",
		"Sublevel7",
	}
do
	request(adaCtx, "Debug.Command", "Ambient", { Kind = kind, Text = "TEST" })
	Scheduler.run(1.5)
end
check("every ambient event plays", #inbox(ada, "Ambient") >= 10)
run(adaCtx, function()
	local panel = ctl(adaCtx, "UIController"):screen("DebugPanel")
	panel:Open()
end)
click(adaCtx, "SPEED (value, 0.1-3)")
Scheduler.run(1)
click(adaCtx, "REVEAL SEQUENCE")
Scheduler.run(1)
run(adaCtx, function()
	ctl(adaCtx, "UIController"):screen("DebugPanel"):Close()
end)
check("solo with emotes and ambience finishes", playToEnd(adaCtx, ada, 900))
leave(adaCtx)

print("== locker")
request(adaCtx, "Debug.Command", "Grant", { XP = 0, Marks = 2000 })
Scheduler.run(2)
local Cosmetics = world:require(adaCtx, services.ReplicatedStorage.Variance.Data.Cosmetics)
local shopItem = nil
for _, item in Cosmetics.List do
	if item.Source.Kind == "Shop" and (item.Price or 0) <= 2000 then
		shopItem = item
		break
	end
end
local okBuy, whyBuy = request(adaCtx, "Cosmetics.Buy", shopItem.Id)
check("buy a shop cosmetic with Marks", okBuy == true, tostring(whyBuy))
local okEquip, whyEquip = request(adaCtx, "Cosmetics.Equip", shopItem.Category, shopItem.Id)
check("equip it", okEquip == true, tostring(whyEquip))
local okLocked = request(adaCtx, "Cosmetics.Equip", "DeviceSkin", "skin_founder")
check("unowned cosmetics can't be equipped", okLocked == false)
Scheduler.run(2)
check("equipped state reached the client", ctl(adaCtx, "ProfileController"):equipped(shopItem.Category) == shopItem.Id)

print("== queue cancel and surrogate backfill")
request(adaCtx, "Queue.Join", "Rapid")
Scheduler.run(2)
request(adaCtx, "Queue.Leave")
Scheduler.run(2)
check("queue cancel", not inMatch(adaCtx) and lastMessage(ada, "Queue").Payload.Cancelled == true)
request(adaCtx, "Queue.Join", "Precision")
waitFor(function()
	return inMatch(adaCtx)
end, 90)
check("a surrogate fills an empty queue", inMatch(adaCtx) and matchOf(adaCtx).Subjects[2].IsAI == true)
check("precision match finishes", playToEnd(adaCtx, ada, 900))
leave(adaCtx)

print("== afk timeouts")
pilots[bex2Ctx] = nil
request(adaCtx, "Queue.Join", "Rapid")
request(bex2Ctx, "Queue.Join", "Rapid")
waitFor(function()
	return inMatch(adaCtx) and inMatch(bex2Ctx)
end, 30)
check("idle subject is removed after repeated timeouts", playToEnd(adaCtx, ada, 900))
local afkReport = postMatch(ada)
check("afk forfeit recorded", afkReport and afkReport.Payload.Report.Reason == "Forfeit")
Scheduler.run(2)
for _, ctx in { adaCtx, bex2Ctx } do
	if inMatch(ctx) then
		leave(ctx)
	end
end
enablePilot(bex2Ctx, { UseRate = 0.3 })

print("== debug tools")
Scheduler.run(5)
local okDebug, result = request(adaCtx, "Debug.Command", "Validation", {})
local allGood = okDebug and type(result) == "table"
if allGood then
	for _, r in result do
		if type(r) == "table" and r.Ok == false then
			allGood = false
		end
	end
end
check("debug validation suite passes", allGood, tostring(result))

print("== cross-server reconnect offer")
local map = world.MemoryMaps.VarianceSessions
World.Instances.data[map].Hidden.Data.active_1003 =
	{ JobId = "another-server", PlaceId = 1818, MatchId = "m_elsewhere" }
local cy, cyCtx = world:addPlayer(1003, "Cy")
Scheduler.run(8)
check("offered a return to the other server", #inbox(cy, "Reconnect") >= 1)
click(cyCtx, "RETURN")
Scheduler.run(3)
check(
	"accepting teleports to that server instance",
	#world.Teleports >= 1 and world.Teleports[#world.Teleports].Options.ServerInstanceId == "another-server"
)

print("== hostile input")
local flagsBefore = #(serverModule("Services.AntiExploitService"):recent(200) or {})
run(adaCtx, function()
	local Net = world:require(adaCtx, services.ReplicatedStorage.Variance.Net)
	Net.Act:FireServer({ Kind = "Fire", Target = 1, Token = 999 })
	Net.Act:FireServer({ Kind = "Nuke" })
	Net.Act:FireServer("not a table")
	Net.Act:FireServer({ Kind = "Use", Slot = 1.5, Token = 1 })
	local okBad = Net.Request:InvokeServer("No.Such.Endpoint")
	local okType = Net.Request:InvokeServer("Solo.Start", 5, {})
	assert(okBad == false and okType == false, "malformed requests must fail")
end)
Scheduler.run(2)
local flagsAfter = #(serverModule("Services.AntiExploitService"):recent(200) or {})
check("malformed input is rejected and flagged", flagsAfter > flagsBefore)
local spam = 0
for _ = 1, 40 do
	local okSpam, why = request(adaCtx, "Profile.Get")
	if not okSpam and why == "Slow down." then
		spam += 1
	end
end
check("request rate limiting", spam > 0)

print("== shutdown")
world:shutdown()
local stored, unlocked, adaRecord = 0, 0, nil
for _, store in world.DataStores do
	for key, value in World.Instances.data[store].Hidden.Data do
		if type(value) == "table" and value.Version then
			stored += 1
			if value.Lock == nil then
				unlocked += 1
			end
			if string.find(tostring(key), "1001") then
				adaRecord = value
			end
		end
	end
end
check("profiles saved on shutdown", stored >= 3)
check("session locks released", unlocked == stored)
check("saved settings persisted", adaRecord ~= nil and adaRecord.Settings and adaRecord.Settings.FireConfirm == "Tap")
check(
	"saved progress persisted",
	adaRecord ~= nil and adaRecord.Stats.Matches >= 5 and adaRecord.Tutorial.Basic == true
)

---------------------------------------------------------------------------
-- Report
---------------------------------------------------------------------------

print("\n== errors: " .. #Scheduler.errors)
for i, e in Scheduler.errors do
	if i <= 20 then
		print("  [" .. e.Context .. "] " .. e.Message)
	end
end
check("no script errors", #Scheduler.errors == 0)

-- Anti-exploit flags are expected from the hostile-input scenario.
local unexpected = {}
for _, w in World.warnings do
	if not string.find(w, "[VARIANCE/AntiExploit]", 1, true) then
		table.insert(unexpected, w)
	end
end
print("== warnings: " .. #unexpected)
for i, w in unexpected do
	if i <= 30 then
		print("  " .. w)
	end
end

local issues = {}
local seen = {}
for _, issue in World.serializationIssues do
	local key = string.gsub(issue, "%d+", "#")
	if not seen[key] then
		seen[key] = true
		table.insert(issues, issue)
	end
end
check("no unexpected warnings", #unexpected == 0)
print("== serialization issues: " .. #issues)
for _, issue in issues do
	print("  " .. issue)
end
check("remote payloads survive Roblox serialization", #issues == 0)

local missing = {}
for id, n in Instances.unimplemented do
	table.insert(missing, id .. " x" .. n)
end
table.sort(missing)
if #missing > 0 then
	print("== engine methods called that the mock doesn't model (returned nil):")
	for _, m in missing do
		print("  " .. m)
	end
end

print(
	string.format(
		"\n%d passed, %d failed, %d warnings, virtual time %.0fs",
		passed,
		#failures,
		#unexpected,
		Scheduler.now
	)
)
if #failures > 0 then
	__exit(1)
end

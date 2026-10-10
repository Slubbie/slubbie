-- Gameplay acceptance tests A, B, C, D, E, H, I and the systems around them,
-- run against the real services through the real security guard.

local roblox = require("@lune/roblox")

local Mock = require("../harness/Mock")
local Server = require("../harness/Server")
local T = require("../harness/T")

local Vector3 = roblox.Vector3

local function countKeys(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

local function onlyCore(profile: any): any
	for _, core in profile.Cores do
		return core
	end
	return nil
end

return function()
	T.Suite("Test A — first-time player, full first loop")

	T.Case("join → guided comet → capture → reveal → deploy → earn → upgrade", function()
		local cloud = Mock.Cloud()
		local server = Server.new({ Cloud = cloud })
		local player, status = server:Join(201, Vector3.new(0, 43, 122))
		T.Equal(status, "New")
		local profile = server:Profile(player)
		T.Equal(profile.TutorialStage, 0)
		T.Equal(server:Get("SanctuaryService").GetPlotIndex(player), 1, "plot assigned")

		-- The guiding comet falls in front of the spawn, only for this player.
		local comet
		for _, c in server:Get("CometService").GetAll() do
			if c.IsTutorial then
				comet = c
			end
		end
		T.True(comet ~= nil, "tutorial comet spawned")
		T.Equal(comet.Owner, player.UserId)
		local stranger = server:Join(299, comet.Position + Vector3.new(0, 3, 4))
		T.Equal(server:Invoke("StartCapture", stranger, comet.Id).Reason, "NotYours", "others can't take it")

		-- Too early: still falling.
		player:MoveTo(comet.Position + Vector3.new(0, 3, 6))
		T.Equal(server:Invoke("StartCapture", player, comet.Id).Reason, "StillFalling")
		server:Advance(server.Config.Comets.TutorialFallDuration + 0.1)
		server:Get("QuestService").CheckTutorialProximity()
		T.Equal(profile.TutorialStage, 1, "reached the comet")

		local result = server:Capture(player, comet.Id, "Edge")
		T.True(result.Ok and result.Complete, `capture completes: {tostring(result.Reason)}`)
		T.Equal(profile.TutorialStage, 2)
		local core = onlyCore(profile)
		T.Equal(core.Kind, "Starter")

		local opened = server:Invoke("OpenComet", player, core.Id)
		T.True(opened.Ok)
		T.Equal(opened.Creature.Species, "Pebblepuff", "guaranteed starter creature")
		T.True(opened.Creature.Locked, "starter is protected")
		T.Equal(profile.TutorialStage, 3)

		-- Walk home.
		local WorldLayout = server.Loader:require("Shared.WorldLayout")
		player:MoveTo(WorldLayout.Plots[1].Center + Vector3.new(0, 3, 0))
		server:Get("SanctuaryService").CheckPresence()
		server:Settle()
		T.Equal(profile.TutorialStage, 4)

		local before = profile.Stardust
		T.True(server:Invoke("EquipCreature", player, opened.Creature.Id, 1).Ok)
		T.Equal(profile.TutorialStage, 5)
		T.Equal(profile.Stardust, before + 250, "welcome gift")
		T.Equal(server:Get("IncomeService").GetRate(player), 1)

		-- Passive income: 1 Stardust/s.
		for _ = 1, 6 do
			server:Get("IncomeService").Tick(1)
		end
		server:Settle()
		T.Equal(profile.TutorialStage, 6)

		local upgrade = server:Invoke("PurchaseUpgrade", player, "Scanner")
		T.True(upgrade.Ok, `upgrade: {tostring(upgrade.Reason)}`)
		T.Equal(profile.Equipment.ScannerLevel, 2)
		T.Equal(profile.TutorialStage, 7, "tutorial complete")

		-- Missions take over.
		T.Equal(profile.QuestProgress.Missions.Index, 1)

		-- Leave and come back: everything is still there.
		server:Leave(player)
		local second = Server.new({ Cloud = cloud, SessionId = "server-B" })
		local again = second:Join(201)
		local restored = second:Profile(again)
		T.Equal(restored.TutorialStage, 7)
		T.Equal(restored.Equipment.ScannerLevel, 2)
		T.Equal(restored.EquippedCreatures["1"], opened.Creature.Id)
		T.Equal(countKeys(restored.Creatures), 1)
	end)

	T.Case("the tutorial resumes where the player left off", function()
		local cloud = Mock.Cloud()
		local server = Server.new({ Cloud = cloud })
		local player = server:Join(202)
		local comet
		for _, c in server:Get("CometService").GetAll() do
			comet = c
		end
		server:Advance(5)
		player:MoveTo(comet.Position + Vector3.new(0, 3, 5))
		T.True(server:Capture(player, comet.Id).Complete)
		-- Leaves with the starter core unopened.
		server:Leave(player)
		local second = Server.new({ Cloud = cloud, SessionId = "server-B" })
		local again = second:Join(202)
		local profile = second:Profile(again)
		T.Equal(profile.TutorialStage, 2, "still on 'open your core'")
		T.Equal(onlyCore(profile).Kind, "Starter")
		local tutorialComets = 0
		for _, c in second:Get("CometService").GetAll() do
			if c.IsTutorial then
				tutorialComets += 1
			end
		end
		T.Equal(tutorialComets, 0, "no second guiding comet")
	end)

	T.Suite("Test B — ordinary capture")

	T.Case("one validated capture → exactly one core, Stardust and XP", function()
		local server = Server.new({})
		local player = server:Join(210)
		server:Profile(player).TutorialStage = 7
		local comet = server:LandComet()
		player:MoveTo(comet.Position + Vector3.new(0, 3, 6))
		local profile = server:Profile(player)
		local stardust, cores = profile.Stardust, countKeys(profile.Cores)
		local result = server:Capture(player, comet.Id)
		T.True(result.Ok and result.Complete)
		T.Equal(result.Rank, "Perfect")
		T.Equal(countKeys(profile.Cores), cores + 1)
		T.Equal(profile.Stardust, stardust + result.Stardust)
		T.True(result.XP > 0)
		T.Equal(profile.Stats.Captures, 1)
		T.True(comet.Claims[player.UserId])
	end)

	T.Case("capture quality never changes creature odds", function()
		local server = Server.new({ Seed = 99 })
		local player = server:Join(211)
		local creatures = server:Get("CreatureService")
		-- Same RNG sequence, cores of very different quality → identical creatures.
		creatures.Random = Mock.Random.new(5)
		local low = creatures.GrantCore(player, "Normal", "DawnCommons", "Spark", 0.1)
		local first = creatures.OpenCore(player, low.Id).Creature
		creatures.Random = Mock.Random.new(5)
		local high = creatures.GrantCore(player, "Normal", "DawnCommons", "Nova", 1)
		local second = creatures.OpenCore(player, high.Id).Creature
		T.Equal(first.Species, second.Species)
		T.Equal(first.Mutation, second.Mutation)
	end)

	T.Suite("Test C — duplicate and replayed requests")

	T.Case("repeating a completed capture gives nothing more", function()
		local server = Server.new({})
		local player = server:Join(220)
		local comet = server:LandComet()
		player:MoveTo(comet.Position + Vector3.new(0, 3, 6))
		local result, start = server:Capture(player, comet.Id)
		T.True(result.Complete)
		local profile = server:Profile(player)
		local stardust, cores, xp = profile.Stardust, countKeys(profile.Cores), profile.XP
		local id = start.Session.Id
		for _ = 1, 5 do
			local replay = server:Invoke("CaptureAction", player, id, "Release", 1, 2)
			T.False(replay.Ok)
		end
		T.Equal(server:Invoke("StartCapture", player, comet.Id).Reason, "AlreadyClaimed")
		T.Equal(profile.Stardust, stardust)
		T.Equal(countKeys(profile.Cores), cores)
		T.Equal(profile.XP, xp)
	end)

	T.Case("a stale session ID is rejected", function()
		local server = Server.new({})
		local player = server:Join(221)
		local comet = server:LandComet()
		player:MoveTo(comet.Position + Vector3.new(0, 3, 6))
		local first = server:Invoke("StartCapture", player, comet.Id)
		local second = server:Invoke("StartCapture", player, comet.Id)
		T.True(first.Ok and second.Ok)
		T.Equal(server:Invoke("CaptureAction", player, first.Session.Id, "Lock", 1).Reason, "NoSession")
	end)

	T.Case("timing reports from the future or far past are rejected", function()
		local server = Server.new({})
		local player = server:Join(222)
		local comet = server:LandComet()
		player:MoveTo(comet.Position + Vector3.new(0, 3, 6))
		local start = server:Invoke("StartCapture", player, comet.Id)
		-- Claims to have pressed 5 seconds from now.
		local future = server:Invoke("CaptureAction", player, start.Session.Id, "Lock", 5)
		T.Equal(future.Reason, "Desync")
		local again = server:Invoke("StartCapture", player, comet.Id)
		server:Advance(10)
		-- Claims an old press that would have been perfect.
		local old = server:Invoke("CaptureAction", player, again.Session.Id, "Lock", 1)
		T.Equal(old.Reason, "Desync")
		T.Equal(countKeys(server:Profile(player).Cores), 0)
	end)

	T.Case("too many misses fail the attempt with a short cooldown", function()
		local server = Server.new({})
		local player = server:Join(223)
		local comet = server:LandComet()
		player:MoveTo(comet.Position + Vector3.new(0, 3, 6))
		local CaptureMath = server.Loader:require("Shared.CaptureMath")
		local start = server:Invoke("StartCapture", player, comet.Id)
		local params = start.Session.Params
		local origin = server.Clock.Os
		local attemptStart = start.Session.AttemptStart
		local result
		for attempt = 1, params.MissesAllowed + 1 do
			-- Press exactly opposite the zone: always a miss.
			local zone = CaptureMath.ZoneCenter(params, attempt)
			local rel = ((zone + 180) % 360) / 360 * params.DialPeriod
			if rel < params.MinReaction then
				rel += params.DialPeriod
			end
			local t = attemptStart + rel
			server.Clock.Os = origin + t + 0.01
			result = server:Invoke("CaptureAction", player, start.Session.Id, "Lock", t)
			T.False(result.Hit)
			attemptStart = result.AttemptStart or attemptStart
		end
		T.True(result.Failed)
		T.Equal(server:Invoke("StartCapture", player, comet.Id).Reason, "Cooldown")
		server:Advance(3)
		T.True(server:Invoke("StartCapture", player, comet.Id).Ok, "can retry after the cooldown")
	end)

	T.Suite("Tests D & E — equipment purchases")

	T.Case("an affordable upgrade deducts once and applies once", function()
		local server = Server.new({})
		local player = server:Join(230)
		local profile = server:Profile(player)
		profile.Stardust = 1300
		local result = server:Invoke("PurchaseUpgrade", player, "Habitat")
		T.True(result.Ok)
		T.Equal(result.Level, 2)
		T.Equal(profile.Stardust, 100)
		T.Equal(profile.Equipment.HabitatLevel, 2)
		T.Equal(server:Get("SanctuaryService").UnlockedSlots(profile), 6)
	end)

	T.Case("an unaffordable upgrade changes nothing", function()
		local server = Server.new({})
		local player = server:Join(231)
		local profile = server:Profile(player)
		profile.Stardust = 249
		local snapshot = Mock.JsonCopy(profile, "profile")
		local result = server:Invoke("PurchaseUpgrade", player, "Scanner")
		T.False(result.Ok)
		T.Equal(result.Reason, "NotEnoughStardust")
		T.DeepEqual(Mock.JsonCopy(profile, "profile"), snapshot, "profile unchanged")
	end)

	T.Case("max level can't be exceeded", function()
		local server = Server.new({})
		local player = server:Join(232)
		local profile = server:Profile(player)
		profile.Stardust = 10 ^ 9
		for _ = 1, 4 do
			server.Clock.Os += 1
			T.True(server:Invoke("PurchaseUpgrade", player, "Tether").Ok)
		end
		server.Clock.Os += 1
		local before = profile.Stardust
		T.Equal(server:Invoke("PurchaseUpgrade", player, "Tether").Reason, "MaxLevel")
		T.Equal(profile.Stardust, before)
		T.Equal(profile.Equipment.TetherLevel, 5)
	end)

	T.Suite("Test H — invalid and malicious requests")

	T.Case("malformed arguments are rejected before any handler runs", function()
		local server = Server.new({})
		local player = server:Join(240)
		local bad = {
			{ "StartCapture", { 42 } },
			{ "StartCapture", { string.rep("x", 500) } },
			{ "StartCapture", { "c1", "extra" } },
			{ "CaptureAction", { 1, "Win", 1 } },
			{ "CaptureAction", { 1, "Lock", 0 / 0 } },
			{ "CaptureAction", { 1.5, "Lock", 1 } },
			{ "EquipCreature", { "x", 13 } },
			{ "EquipCreature", { "x", -1 } },
			{ "PurchaseUpgrade", { "Wings" } },
			{ "PurchaseUpgrade", { { Level = 5 } } },
			{ "SetCreatureFlag", { "x", "Mythic", true } },
			{ "Travel", { "Moon" } },
		}
		local profile = server:Profile(player)
		local snapshot = Mock.JsonCopy(profile, "profile")
		for _, case in bad do
			server.Clock.Os += 1 -- stay under the rate limit
			local result = server:Invoke(case[1], player, table.unpack(case[2]))
			T.Equal(result.Reason, "BadRequest", case[1])
		end
		T.DeepEqual(Mock.JsonCopy(profile, "profile"), snapshot)
		T.True(server:Get("SecurityService").ViolationCount(player) >= #bad)
	end)

	T.Case("settings accept only known keys and values", function()
		local security = Server.new({}):Get("SecurityService")
		T.True((security.ValidateSettings({ MusicVolume = 0.5, ReducedMotion = true })))
		T.False((security.ValidateSettings({ MusicVolume = 2 })))
		T.False((security.ValidateSettings({ Stardust = 1000000 })))
		T.False((security.ValidateSettings({ GraphicsQuality = "Ultra" })))
		T.False((security.ValidateSettings("nope")))
	end)

	T.Case("nobody can touch creatures, cores or habitats they don't own", function()
		local server = Server.new({})
		local owner = server:Join(241)
		local thief = server:Join(242)
		local creatures = server:Get("CreatureService")
		local creature = creatures.AddCreature(owner, "AuroraLynx", "Standard", "Capture", "DawnCommons")
		local core = creatures.GrantCore(owner, "Normal", "DawnCommons", "Ember", 0.5)
		T.Equal(server:Invoke("EquipCreature", thief, creature.Id, 1).Reason, "NotOwned")
		T.Equal(server:Invoke("ReleaseCreature", thief, creature.Id).Reason, "NotOwned")
		T.Equal(server:Invoke("SetCreatureFlag", thief, creature.Id, "Locked", true).Reason, "NotOwned")
		T.Equal(server:Invoke("OpenComet", thief, core.Id).Reason, "NoSuchCore")
		T.Equal(server:Invoke("EquipCreature", owner, "made-up-id", 1).Reason, "NotOwned")
		T.True(server:Profile(owner).Cores[core.Id] ~= nil)
		T.True(server:Profile(owner).Creatures[creature.Id] ~= nil)
	end)

	T.Case("captures from across the map are refused", function()
		local server = Server.new({})
		local player = server:Join(243, Vector3.new(0, 43, 0))
		local comet = server:LandComet()
		T.Equal(server:Invoke("StartCapture", player, comet.Id).Reason, "TooFar")
		player:MoveTo(comet.Position + Vector3.new(0, 3, 6))
		local start = server:Invoke("StartCapture", player, comet.Id)
		T.True(start.Ok)
		-- Teleporting away mid-capture fails the containment.
		local CaptureMath = server.Loader:require("Shared.CaptureMath")
		local params = start.Session.Params
		local t1 = start.Session.AttemptStart + CaptureMath.ZoneCenter(params, 1) / 360 * params.DialPeriod
		server.Clock.Os += t1 + 0.01
		local lock = server:Invoke("CaptureAction", player, start.Session.Id, "Lock", t1)
		T.True(lock.Hit)
		player:MoveTo(Vector3.new(0, 43, 0))
		local holdStart = lock.AttemptStart + 0.1
		local best
		for hold = 0.05, params.OverchargeTime, 0.002 do
			if
				CaptureMath.ScoreRelease(params, 1, holdStart - lock.AttemptStart, holdStart + hold - lock.AttemptStart).Hit
			then
				best = holdStart + hold
				break
			end
		end
		server.Clock.Os = server.Clock.Os - t1 - 0.01 + best + 0.01
		local final = server:Invoke("CaptureAction", player, start.Session.Id, "Release", holdStart, best)
		T.True(final.Failed)
		T.Equal(final.Reason, "TooFar")
		T.Equal(countKeys(server:Profile(player).Cores), 0)
	end)

	T.Case("rate limits stop request floods", function()
		local server = Server.new({})
		local player = server:Join(244)
		local limited = 0
		for _ = 1, 20 do
			if server:Invoke("PurchaseUpgrade", player, "Scanner").Reason == "RateLimited" then
				limited += 1
			end
		end
		T.True(limited >= 15, `rate limited {limited}/20`)
	end)

	T.Case("requests before the profile loads are refused", function()
		local server = Server.new({})
		local stranger = Mock.Player(server.Players, 245, "Loading")
		T.Equal(server:Invoke("PurchaseUpgrade", stranger, "Scanner").Reason, "NotReady")
	end)

	T.Suite("Test I — several players, one comet")

	T.Case("each player captures the same comet once, independently", function()
		local server = Server.new({})
		local comet = server:LandComet()
		local players = {}
		for i = 1, 4 do
			local player = server:Join(250 + i, comet.Position + Vector3.new(i, 3, 6))
			table.insert(players, player)
		end
		for _, player in players do
			local result = server:Capture(player, comet.Id)
			T.True(result.Complete, `player {player.UserId}`)
		end
		for _, player in players do
			T.Equal(countKeys(server:Profile(player).Cores), 1, `one core for {player.UserId}`)
			T.True(comet.Claims[player.UserId])
		end
	end)

	T.Suite("Creatures, sanctuary, wisps and missions")

	T.Case("deploying moves, swaps and withdraws without duplicating", function()
		local server = Server.new({})
		local player = server:Join(260)
		local creatures = server:Get("CreatureService")
		local a = creatures.AddCreature(player, "Pebblepuff", "Standard", "Capture", "DawnCommons")
		local b = creatures.AddCreature(player, "CometFox", "Standard", "Capture", "DawnCommons")
		local profile = server:Profile(player)
		T.True(server:Invoke("EquipCreature", player, a.Id, 1).Ok)
		T.True(server:Invoke("EquipCreature", player, b.Id, 2).Ok)
		-- Move A onto B's slot: they swap.
		T.True(server:Invoke("EquipCreature", player, a.Id, 2).Ok)
		T.Equal(profile.EquippedCreatures["2"], a.Id)
		T.Equal(profile.EquippedCreatures["1"], b.Id)
		T.Equal(server:Get("IncomeService").GetRate(player), 4)
		-- Slot 5 is locked at Habitat level 1.
		T.Equal(server:Invoke("EquipCreature", player, a.Id, 5).Reason, "SlotLocked")
		T.True(server:Invoke("RemoveCreature", player, 1).Ok)
		T.Equal(profile.EquippedCreatures["1"], nil)
		T.Equal(countKeys(profile.Creatures), 2)
		T.Equal(server:Get("IncomeService").GetRate(player), 1)
	end)

	T.Case("locked, favourite and deployed creatures can't be released", function()
		local server = Server.new({})
		local player = server:Join(261)
		local creatures = server:Get("CreatureService")
		local profile = server:Profile(player)
		local starter = creatures.AddCreature(player, "Pebblepuff", "Standard", "Starter", "DawnCommons")
		local fav = creatures.AddCreature(player, "Nebble", "Standard", "Capture", "DawnCommons")
		local deployed = creatures.AddCreature(player, "Crumbtail", "Standard", "Capture", "DawnCommons")
		local spare = creatures.AddCreature(player, "CometFox", "Aurora", "Capture", "DawnCommons")
		server:Invoke("SetCreatureFlag", player, fav.Id, "Favorite", true)
		server:Invoke("EquipCreature", player, deployed.Id, 1)
		T.Equal(server:Invoke("ReleaseCreature", player, starter.Id).Reason, "Protected")
		T.Equal(server:Invoke("ReleaseCreature", player, fav.Id).Reason, "Protected")
		T.Equal(server:Invoke("ReleaseCreature", player, deployed.Id).Reason, "Deployed")
		local before = profile.Stardust
		local result = server:Invoke("ReleaseCreature", player, spare.Id)
		T.True(result.Ok)
		T.Equal(profile.Stardust, before + math.floor(3 * 1.1 * 45))
		T.Equal(profile.Creatures[spare.Id], nil)
		T.Equal(server:Invoke("ReleaseCreature", player, spare.Id).Reason, "NotOwned", "no double release")
	end)

	T.Case("core storage and inventory limits are enforced", function()
		local server = Server.new({})
		local player = server:Join(262)
		local creatures = server:Get("CreatureService")
		local limit = server.Config.Inventory.MaxCores
		for _ = 1, limit do
			T.True(creatures.GrantCore(player, "Normal", "DawnCommons", "Ember", 0.5) ~= nil)
		end
		local _, reason = creatures.GrantCore(player, "Normal", "DawnCommons", "Ember", 0.5)
		T.Equal(reason, "CoreStorageFull")
		local comet = server:LandComet()
		player:MoveTo(comet.Position + Vector3.new(0, 3, 6))
		T.Equal(server:Invoke("StartCapture", player, comet.Id).Reason, "CoreStorageFull")
	end)

	T.Case("wisps: collect nearby, wait to respawn, and never from afar", function()
		local server = Server.new({})
		local player = server:Join(263)
		local wisp = server:Get("WorldService").WispPoints[1]
		T.Equal(server:Invoke("CollectWisp", player, wisp.Id).Reason, "TooFar")
		player:MoveTo(wisp.Position + Vector3.new(2, 0, 0))
		local before = server:Profile(player).Stardust
		local result = server:Invoke("CollectWisp", player, wisp.Id)
		T.True(result.Ok)
		T.Equal(server:Profile(player).Stardust, before + 3)
		server.Clock.Os += 1
		T.Equal(server:Invoke("CollectWisp", player, wisp.Id).Reason, "NotYet")
		server:Advance(server.Config.Wisps.RespawnSeconds + 1)
		T.True(server:Invoke("CollectWisp", player, wisp.Id).Ok)
		T.Equal(server:Invoke("CollectWisp", player, "w999").Reason, "NoSuchWisp")
	end)

	T.Case("missions progress, claim once and advance", function()
		local server = Server.new({})
		local player = server:Join(264)
		local profile = server:Profile(player)
		profile.TutorialStage = 7
		local quests = server:Get("QuestService")
		quests.EvaluateMission(player)
		T.Equal(server:Invoke("ClaimQuest", player, "CometChaser").Reason, "NotComplete")
		for i = 1, 5 do
			local comet = server:LandComet()
			player:MoveTo(comet.Position + Vector3.new(0, 3, 6))
			T.True(server:Capture(player, comet.Id).Complete, `capture {i}`)
			server:Advance(1)
		end
		T.True(profile.QuestProgress.Missions.Complete)
		local before = profile.Stardust
		T.True(server:Invoke("ClaimQuest", player, "CometChaser").Ok)
		T.Equal(profile.Stardust, before + 150)
		server.Clock.Os += 1
		T.Equal(server:Invoke("ClaimQuest", player, "CometChaser").Reason, "NotActive", "no double claim")
		T.Equal(profile.QuestProgress.Missions.Index, 2)
	end)

	T.Case("level ups grant Stardust and are announced", function()
		local server = Server.new({})
		local player = server:Join(265)
		local profile = server:Profile(player)
		local gained = server:Get("ProgressionService").AddXP(player, 100, "Test")
		T.Equal(gained, 1)
		T.Equal(profile.Level, 2)
		T.Equal(profile.Stardust, 80)
		local announced = false
		for _, sent in server:Get("ReplicationService").Sent do
			if sent.Kind == "LevelUp" and sent.Payload.Level == 2 then
				announced = true
			end
		end
		T.True(announced)
	end)

	T.Case("locked and uncharted biomes can't be entered", function()
		local server = Server.new({})
		local player = server:Join(266)
		local progression = server:Get("ProgressionService")
		T.True(progression.CanEnterBiome(player, "DawnCommons"))
		local ok, reason = progression.CanEnterBiome(player, "PrismCliffs")
		T.False(ok)
		T.Equal(reason, "ComingSoon")
		T.Equal(progression.UnlockBiome(player, "PrismCliffs"), false)
		T.Equal(server:Invoke("Travel", player, "PrismCliffs").Reason, "ComingSoon")
		T.True(server:Invoke("Travel", player, "Sanctuary").Ok)
	end)

	T.Case("state changes are replicated as ordered deltas", function()
		local server = Server.new({})
		local player = server:Join(267)
		local replication = server:Get("ReplicationService")
		replication.Sent = {}
		server:Get("EconomyService").Grant(player, "Stardust", 12, "Test")
		replication.Flush()
		local delta = replication.Sent[1]
		T.Equal(delta.Kind, "Delta")
		local found = false
		for _, change in delta.Payload do
			if change.Path[1] == "Profile" and change.Path[2] == "Stardust" then
				found = change.Value == server:Profile(player).Stardust
			end
		end
		T.True(found)
		local snapshot = replication.BuildSnapshot(player)
		T.True(snapshot.Seq >= delta.Seq)
		T.Equal(snapshot.Profile.IncomeRemainder, nil, "private fields stay on the server")
		T.True(type(snapshot.Comets) == "table" and type(snapshot.Wisps) == "table")
	end)

	T.Case("invalid economy amounts are refused", function()
		local server = Server.new({})
		local player = server:Join(268)
		local economy = server:Get("EconomyService")
		T.False(economy.Grant(player, "Stardust", -5, "Test"))
		T.False(economy.Grant(player, "Stardust", 0 / 0, "Test"))
		T.False(economy.Grant(player, "Stardust", 1.5, "Test"))
		T.False(economy.Grant(player, "Gems", 5, "Test"))
		T.False(economy.Spend(player, "Stardust", 1, "Test"))
		T.Equal(server:Profile(player).Stardust, 0)
	end)

	T.Case("comets spawn at free sites and expire on time", function()
		local server = Server.new({})
		server:Join(269)
		local comets = server:Get("CometService")
		local spawned = {}
		for _ = 1, 10 do
			local comet = comets.Spawn("DawnCommons")
			if comet then
				table.insert(spawned, comet)
			end
		end
		T.Equal(#spawned, server.Config.Comets.MaxPerBiome, "capped per biome")
		for i = 1, #spawned do
			for j = i + 1, #spawned do
				T.True((spawned[i].Position - spawned[j].Position).Magnitude >= server.Config.Comets.MinSpacing)
			end
		end
		server:Advance(server.Config.Comets.FallDuration + server.Config.Comets.Lifetime + 1)
		comets.Step()
		T.Equal(#comets.ActiveIn("DawnCommons"), 0, "expired")
	end)
end

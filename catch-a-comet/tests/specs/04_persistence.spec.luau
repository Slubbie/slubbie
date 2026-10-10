-- Persistence: session locking, save/rejoin, failures (acceptance tests F, G, L).

local Mock = require("../harness/Mock")
local Server = require("../harness/Server")
local T = require("../harness/T")

return function()
	T.Suite("Persistence and session locking")

	T.Case("a new player is created, saved on leave and restored on rejoin (Test F)", function()
		local cloud = Mock.Cloud()
		local server = Server.new({ Cloud = cloud })
		local player, status = server:Join(101)
		T.Equal(status, "New")
		local profile = server:Profile(player)
		profile.Stardust = 5000
		local creature =
			server:Get("CreatureService").AddCreature(player, "CometFox", "Charged", "Capture", "DawnCommons")
		T.True(creature ~= nil)
		T.True(server:Get("SanctuaryService").Deploy(player, creature.Id, 1).Ok)
		T.True(server:Get("UpgradeService").Purchase(player, "Scanner").Ok)
		server:Leave(player)

		local record = cloud.Data.Player_101
		T.True(record ~= nil, "saved")
		T.Equal(record.Meta.Session, nil, "lock released on leave")

		local second = Server.new({ Cloud = cloud, SessionId = "server-B" })
		local again, status2 = second:Join(101)
		T.Equal(status2, "Loaded")
		local restored = second:Profile(again)
		T.Equal(restored.Stardust, 5000 - 250)
		T.Equal(restored.Equipment.ScannerLevel, 2)
		T.Equal(restored.EquippedCreatures["1"], creature.Id)
		T.Equal(restored.Creatures[creature.Id].Mutation, "Charged")
		T.Equal(second:Get("SanctuaryService").GetPlotIndex(again), 1)
	end)

	T.Case("a live lock held by another server blocks loading", function()
		local cloud = Mock.Cloud()
		local first = Server.new({ Cloud = cloud, SessionId = "server-A" })
		first:Join(102)
		local second = Server.new({ Cloud = cloud, SessionId = "server-B" })
		local player, status = second:Join(102)
		T.Equal(status, "Locked")
		T.True(player.Kicked ~= nil, "kicked with an explanation")
		T.Equal(second:Profile(player), nil)
	end)

	T.Case("an abandoned lock (crashed server) is taken over after it goes stale", function()
		local cloud = Mock.Cloud()
		local clock = Mock.Clock()
		local first = Server.new({ Cloud = cloud, SessionId = "server-A", Clock = clock })
		local original = first:Join(103)
		first:Profile(original).Stardust = 77
		first:Get("PlayerDataService").SavePlayer(original, false)
		-- server-A "crashes": no release. Time passes beyond the stale window.
		clock:Advance(first.Config.Data.LockStaleSeconds + 5)
		local second = Server.new({ Cloud = cloud, SessionId = "server-B", Clock = clock })
		local player, status = second:Join(103)
		T.Equal(status, "Loaded")
		T.Equal(second:Profile(player).Stardust, 77)
		-- The crashed server's late save must not overwrite the new session.
		local result = first:Get("PlayerDataService").SavePlayer(original, false)
		T.Equal(result, "LockLost")
		T.True(original.Kicked ~= nil)
		T.Equal(cloud.Data.Player_103.Meta.Session, "server-B")
	end)

	T.Case("transient DataStore errors are retried", function()
		local cloud = Mock.Cloud()
		cloud.FailNext = 2
		local server = Server.new({ Cloud = cloud })
		local player, status = server:Join(104)
		T.Equal(status, "New")
		T.Equal(player.Kicked, nil)
	end)

	T.Case("a load that keeps failing kicks safely and writes nothing (Test L)", function()
		local cloud = Mock.Cloud()
		cloud.FailAll = true
		local server = Server.new({ Cloud = cloud })
		local player, status = server:Join(105)
		T.Equal(status, "Error")
		T.True(player.Kicked ~= nil)
		T.Equal(cloud.Data.Player_105, nil)
	end)

	T.Case("save failures mark saving as degraded, then recover (Test L)", function()
		local cloud = Mock.Cloud()
		local server = Server.new({ Cloud = cloud })
		local player = server:Join(106)
		server:Profile(player).Stardust = 10
		cloud.FailAll = true
		local data = server:Get("PlayerDataService")
		T.Equal(data.SavePlayer(player, false), "Error")
		T.Equal(data.GetSaveStatus(player), "Degraded")
		local notices = 0
		for _, sent in server:Get("ReplicationService").Sent do
			if sent.Kind == "SaveStatus" then
				notices += 1
			end
		end
		T.True(notices >= 1, "player told that saving is delayed")
		cloud.FailAll = false
		T.Equal(data.SavePlayer(player, false), "Saved")
		T.Equal(data.GetSaveStatus(player), "OK")
		T.Equal(cloud.Data.Player_106.Data.Stardust, 10)
	end)

	T.Case("Studio without API access runs in session-only mode", function()
		local cloud = Mock.Cloud()
		cloud.FailAll = true
		cloud.FailMessage = "StudioAccessToApisNotAllowed: 403"
		local server = Server.new({ Cloud = cloud, IsStudio = true })
		local player, status = server:Join(107)
		T.Equal(status, "SessionOnly")
		T.Equal(player.Kicked, nil)
		T.Equal(server:Get("PlayerDataService").GetSaveStatus(player), "SessionOnly")
	end)

	T.Case("newer-version data is never overwritten", function()
		local cloud = Mock.Cloud()
		cloud.Data.Player_108 = { Data = { SchemaVersion = 99, Stardust = 123 }, Meta = {} }
		local server = Server.new({ Cloud = cloud })
		local player, status = server:Join(108)
		T.Equal(status, "TooNew")
		T.True(player.Kicked ~= nil)
		server:Settle()
		T.Equal(cloud.Data.Player_108.Data.Stardust, 123)
		T.Equal(cloud.Data.Player_108.Meta.Session, nil, "lock given back")
	end)

	T.Case("rejoining the same server waits for the final save", function()
		local cloud = Mock.Cloud()
		local server = Server.new({ Cloud = cloud })
		local player = server:Join(109)
		server:Profile(player).Stardust = 999
		server:Leave(player)
		local again = server:Join(109)
		T.Equal(server:Profile(again).Stardust, 999)
	end)

	T.Case("leaving during a reveal neither loses nor duplicates the creature (Test G)", function()
		local cloud = Mock.Cloud()
		local server = Server.new({ Cloud = cloud })
		local player = server:Join(110)
		local creatures = server:Get("CreatureService")
		local core = creatures.GrantCore(player, "Normal", "DawnCommons", "Ember", 0.8)
		local opened = server:Invoke("OpenComet", player, core.Id)
		T.True(opened.Ok)
		-- The client is still animating the reveal when the player disconnects.
		server:Leave(player)
		local second = Server.new({ Cloud = cloud, SessionId = "server-B" })
		local again = second:Join(110)
		local profile = second:Profile(again)
		local count = 0
		for _ in profile.Creatures do
			count += 1
		end
		T.Equal(count, 1, "exactly one creature")
		T.Equal(profile.Cores[core.Id], nil, "core consumed")
		T.True(profile.Creatures[opened.Creature.Id] ~= nil)
		-- Opening the same core again does nothing.
		T.Equal(second:Invoke("OpenComet", again, core.Id).Reason, "NoSuchCore")
	end)

	T.Case("offline earnings are granted once, from the server clock", function()
		local cloud = Mock.Cloud()
		local clock = Mock.Clock()
		local server = Server.new({ Cloud = cloud, Clock = clock })
		local player = server:Join(111)
		local creature =
			server:Get("CreatureService").AddCreature(player, "AuroraLynx", "Standard", "Capture", "DawnCommons")
		server:Get("SanctuaryService").Deploy(player, creature.Id, 1)
		server:Leave(player)
		clock:Advance(3600)
		local second = Server.new({ Cloud = cloud, Clock = clock, SessionId = "server-B" })
		local again = second:Join(111)
		T.Equal(second:Profile(again).Stardust, math.floor(9 * 0.25 * 3600))
		second:Leave(again)
		-- Rejoining right away earns nothing more.
		local third = Server.new({ Cloud = cloud, Clock = clock, SessionId = "server-C" })
		local last = third:Join(111)
		T.Equal(third:Profile(last).Stardust, math.floor(9 * 0.25 * 3600))
	end)
end

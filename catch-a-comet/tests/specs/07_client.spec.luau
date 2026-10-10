-- Client boot and UI flows, with scripted server responses.

local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Client = require("../harness/Client")
local Loader = require("../harness/Loader")
local T = require("../harness/T")

local Enum = roblox.Enum
local Vector3 = roblox.Vector3

return function()
	local shared = Loader.new(".")
	local CaptureMath = shared:require("Shared.CaptureMath")
	local NOW = 1_800_000_000
	local params = CaptureMath.BuildParams(7, { ZoneMult = 1.6, BandMult = 1.6 })

	local creatures = {
		["1-1"] = {
			Id = "1-1",
			Species = "Pebblepuff",
			Mutation = "Standard",
			Bond = 1,
			Obtained = NOW,
			Locked = true,
			Favorite = false,
			Origin = "Starter",
			Biome = "DawnCommons",
		},
		["1-2"] = {
			Id = "1-2",
			Species = "AuroraLynx",
			Mutation = "Aurora",
			Bond = 1,
			Obtained = NOW,
			Locked = false,
			Favorite = false,
			Origin = "Capture",
			Biome = "DawnCommons",
		},
		["1-3"] = {
			Id = "1-3",
			Species = "TheFirstStar",
			Mutation = "Prismatic",
			Bond = 1,
			Obtained = NOW,
			Locked = false,
			Favorite = true,
			Origin = "Capture",
			Biome = "DawnCommons",
		},
	}
	local profile = {
		SchemaVersion = 1,
		Stardust = 300,
		MeteorShards = 0,
		Level = 2,
		XP = 40,
		TutorialStage = 4,
		UnlockedBiomes = { DawnCommons = true },
		Equipment = { ScannerLevel = 1, TetherLevel = 1, HabitatLevel = 1 },
		Creatures = creatures,
		NextCreatureSerial = 4,
		Cores = {
			k1 = {
				Id = "k1",
				Kind = "Normal",
				Biome = "DawnCommons",
				CometType = "Nova",
				Quality = 0.8,
				Obtained = NOW,
			},
		},
		NextCoreSerial = 2,
		EquippedCreatures = { ["1"] = "1-1" },
		DiscoveredSpecies = {
			Pebblepuff = { First = NOW, Count = 1, Mutations = { Standard = true } },
			AuroraLynx = { First = NOW, Count = 1, Mutations = { Aurora = true } },
			TheFirstStar = { First = NOW, Count = 1, Mutations = { Prismatic = true } },
		},
		QuestProgress = { Onboarding = { Progress = 0 }, Missions = { Index = 1, Progress = 0, Complete = false } },
		Settings = {
			MusicVolume = 0.7,
			EffectsVolume = 0.8,
			AmbientVolume = 0.6,
			ReducedMotion = false,
			EasyCapture = false,
			AutoOpenCores = true,
			GraphicsQuality = "Auto",
		},
		Stats = {},
		LastSeenTimestamp = NOW,
		CreatedAt = NOW,
		Achievements = {},
		SanctuaryDecorations = {},
		AscensionCount = 0,
	}
	local landed = {
		Id = "c1",
		Biome = "DawnCommons",
		Position = Vector3.new(0, 40, 100),
		Type = "Glacier",
		SpawnTime = 900,
		ImpactTime = 904,
		ExpireTime = 1094,
		Entry = Vector3.new(1, 0, 0),
		IsTutorial = false,
		Claimed = false,
	}
	local snapshot = {
		Seq = 0,
		Profile = profile,
		Session = { PlotIndex = 1, IncomeRate = 1, SaveStatus = "OK" },
		Comets = { landed },
		Wisps = {
			List = { { Id = "w1", Position = Vector3.new(2, 43, 108), Biome = "DawnCommons" } },
			AvailableAt = {},
		},
	}
	local responses = {
		StartCapture = function(cometId)
			return {
				Ok = true,
				Session = {
					Id = 1,
					CometId = cometId,
					Params = params,
					AttemptStart = params.IntroTime,
					IsTutorial = false,
				},
			}
		end,
		CaptureAction = function(_id, action, t1, _t2)
			if action == "Lock" then
				return {
					Ok = true,
					Hit = true,
					Score = 1,
					Stage = 2,
					Attempt = 1,
					AttemptStart = t1 + params.TransitionTime,
				}
			elseif action == "Release" then
				return {
					Ok = true,
					Hit = true,
					Complete = true,
					Score = 1,
					Quality = 0.95,
					Rank = "Perfect",
					Stardust = 52,
					XP = 70,
					CoreId = "k2",
				}
			end
			return { Ok = true, Cancelled = true }
		end,
		OpenComet = function()
			return {
				Ok = true,
				IsNew = true,
				Creature = {
					Id = "1-4",
					Species = "NebulaPhoenix",
					Mutation = "Eclipse",
					Bond = 1,
					Obtained = NOW,
					Locked = false,
					Favorite = false,
					Origin = "Capture",
					Biome = "DawnCommons",
				},
			}
		end,
		PurchaseUpgrade = function()
			return { Ok = true, Level = 2 }
		end,
		EquipCreature = function()
			return { Ok = true }
		end,
		RemoveCreature = function()
			return { Ok = true }
		end,
		ReleaseCreature = function()
			return { Ok = true, Stardust = 10 }
		end,
		SetCreatureFlag = function()
			return { Ok = true }
		end,
		ClaimQuest = function()
			return { Ok = true }
		end,
		CollectWisp = function()
			return { Ok = true, Stardust = 3, AvailableAt = 5000 }
		end,
		Travel = function()
			return { Ok = true }
		end,
	}

	T.Suite("Client boot and UI flows")
	local client = Client.new(responses, snapshot)
	client:SetServerTime(1000)

	T.Case("every controller starts and builds its screens", function()
		client:Boot()
		for _, name in { "HUD", "Panels", "Notifications", "CaptureUI", "RevealUI", "Objectives" } do
			T.True(client.PlayerGui:FindFirstChild(name) ~= nil, `{name} screen`)
		end
		client:Step(5)
	end)

	T.Case("the landed comet from the snapshot has a site, prompt and marker", function()
		local view = client.Registry.CometController.Get("c1")
		T.True(view ~= nil)
		T.Equal(view.State, "Landed")
		T.True(view.Prompt ~= nil and view.Marker ~= nil)
		client:Step(10)
	end)

	T.Case("a new comet falls, impacts and becomes capturable", function()
		client:Receive("CometBroadcast", "Spawn", {
			Id = "c2",
			Biome = "DawnCommons",
			Position = Vector3.new(30, 40, 90),
			Type = "Nova",
			SpawnTime = 1000.2,
			ImpactTime = 1001.2,
			ExpireTime = 1091.2,
			Entry = Vector3.new(0, 0, 1),
			IsTutorial = false,
			Claimed = false,
		})
		local view = client.Registry.CometController.Get("c2")
		T.Equal(view.State, "Falling")
		client:Step(90)
		T.Equal(view.State, "Landed")
		client:Receive("CometBroadcast", "Claimed", { Id = "c2" })
		T.True(view.Claimed)
		client:Receive("CometBroadcast", "Expire", { Id = "c2" })
		T.Equal(client.Registry.CometController.Get("c2"), nil)
	end)

	T.Case("the minigame plays through to the reveal", function()
		local capture = client.Registry.CaptureController
		capture.Begin("c1")
		T.True(capture.Active)
		local action = client.BoundActions.CometCaptureAction
		T.True(action ~= nil, "capture input bound")
		local started = os.clock()
		local function waitUntil(t: number)
			while os.clock() - started < t do
				client:Step(1)
				task.wait()
			end
		end
		local keyboard = { UserInputType = Enum.UserInputType.Keyboard }
		local lockTime = params.IntroTime + CaptureMath.ZoneCenter(params, 1) / 360 * params.DialPeriod
		waitUntil(lockTime)
		action("CometCaptureAction", Enum.UserInputState.Begin, keyboard)
		action("CometCaptureAction", Enum.UserInputState.End, keyboard)
		local stage2 = (os.clock() - started) + params.TransitionTime + 0.05
		waitUntil(stage2)
		action("CometCaptureAction", Enum.UserInputState.Begin, keyboard)
		local pressed = os.clock() - started
		-- Hold until the predicted level sits in the band.
		local best = 0.6
		for hold = 0.1, params.OverchargeTime - 0.05, 0.01 do
			local result =
				CaptureMath.ScoreRelease(params, 1, pressed - (stage2 - 0.05), pressed - (stage2 - 0.05) + hold)
			if result.Hit then
				best = hold
				break
			end
		end
		waitUntil(pressed + best + 0.04)
		action("CometCaptureAction", Enum.UserInputState.End, keyboard)
		client:Settle()
		local names = {}
		for _, call in client.Invocations do
			names[call.Name] = (names[call.Name] or 0) + 1
		end
		T.True((names.CaptureAction or 0) >= 2, "lock and release reported")
		-- Wait for the auto-open and the reveal.
		local deadline = os.clock() + 6
		while
			os.clock() < deadline and not ((names.OpenComet or 0) >= 1 and not client.Registry.RevealController.Busy)
		do
			client:Step(1)
			task.wait(0.05)
			names.OpenComet = 0
			for _, call in client.Invocations do
				if call.Name == "OpenComet" then
					names.OpenComet += 1
				end
			end
		end
		T.True((names.OpenComet or 0) >= 1, "core opened automatically")
		T.False(capture.Active)
	end)

	T.Case("every panel opens, renders and closes", function()
		local panels = client.Registry.PanelManager
		for _, name in { "Inventory", "Workshop", "Quests", "Settings", "Travel" } do
			panels.Open(name)
			T.Equal(panels.Current(), name)
			client:Settle()
			panels.Close()
		end
		local inventory = client.Registry.InventoryController
		for _, tab in { "Creatures", "Cores", "Collection", "Odds" } do
			inventory.Open(tab)
			client:Settle()
		end
		inventory.Open("Creatures", "1-2")
		client:Settle()
		panels.Close()
	end)

	T.Case("habitat pickers work from inventory and from a pad", function()
		local sanctuary = client.Registry.SanctuaryController
		sanctuary.PickSlotFor("1-2")
		T.Equal(client.Registry.PanelManager.Current(), "HabitatSlots")
		client.Registry.PanelManager.Close()
		local prompt = roblox.Instance.new("ProximityPrompt")
		prompt:SetAttribute("PlotIndex", 1)
		prompt:SetAttribute("Slot", 2)
		sanctuary.OnPadPrompt(prompt)
		T.Equal(client.Registry.PanelManager.Current(), "HabitatCreatures")
		client.Registry.PanelManager.Close()
	end)

	T.Case("state deltas update the HUD and trackers", function()
		client:Receive("StateDelta", 1, {
			{ Path = { "Profile", "Stardust" }, Value = 1234 },
			{ Path = { "Profile", "TutorialStage" }, Value = 7 },
			{ Path = { "Profile", "QuestProgress", "Missions" }, Value = { Index = 1, Progress = 5, Complete = true } },
			{ Path = { "Session", "IncomeRate" }, Value = 12.5 },
			{ Path = { "Profile", "Creatures", "1-9" }, Value = creatures["1-2"] },
		})
		T.Equal(client.Registry.ClientState.Get("Stardust"), 1234)
		T.Equal(client.Registry.ClientState.GetSession("IncomeRate"), 12.5)
		client:Receive("StateDelta", 1, { { Path = { "Profile", "Stardust" }, Value = 1 } })
		T.Equal(client.Registry.ClientState.Get("Stardust"), 1234, "old sequence ignored")
		client:Step(30)
	end)

	T.Case("every notification kind renders", function()
		local kinds = {
			{ "LevelUp", { Level = 3, Stardust = 120, BiomesReady = {} } },
			{ "QuestCompleted", { Chain = "Missions", Id = "CometChaser", Reward = { Stardust = 150 } } },
			{ "QuestCompleted", { Chain = "Onboarding", Id = "Deploy", Reward = { Stardust = 250 }, Done = true } },
			{ "OfflineEarnings", { Amount = 900, Seconds = 3600, Away = 3600, Capped = false } },
			{ "SaveStatus", { Status = "Degraded" } },
			{ "SaveStatus", { Status = "OK" } },
			{ "Upgraded", { Track = "Scanner", Level = 2 } },
			{ "BiomeUnlocked", { Biome = "PrismCliffs" } },
			{
				"PortalLocked",
				{ Biome = "PrismCliffs", Reason = "ComingSoon", Name = "Prism Cliffs", Level = 5, Stardust = "2.5K" },
			},
			{ "NoSanctuary", {} },
			{ "CaptureTimeout", {} },
			{ "Travelled", { Destination = "Hub" } },
			{ "Recovered", {} },
		}
		for _, kind in kinds do
			client:Receive("Notification", kind[1], kind[2])
		end
		client:Settle()
	end)

	T.Case("wisps in scanner range appear and are collected", function()
		client:Step(12, 0.1)
		client:Settle()
		local collected = false
		for _, call in client.Invocations do
			if call.Name == "CollectWisp" then
				collected = true
			end
		end
		T.True(collected)
	end)

	T.Case("settings changes are saved to the server", function()
		client.Registry.SettingsController.Set("ReducedMotion", true)
		client.Registry.SettingsController.Set("GraphicsQuality", "Low")
		task.wait(1.2)
		local sent = nil
		for _, fired in client.Fired do
			if fired.Name == "UpdateSettings" then
				sent = fired.Args[1]
			end
		end
		T.True(sent ~= nil)
		T.Equal(sent.ReducedMotion, true)
		T.Equal(sent.GraphicsQuality, "Low")
		T.Equal(client.Registry.SettingsController.QualityName(), "Low")
	end)
end

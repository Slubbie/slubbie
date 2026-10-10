-- Profile schema: defaults, migration, reconciliation and integrity repair.

local Loader = require("../harness/Loader")
local Mock = require("../harness/Mock")
local T = require("../harness/T")

return function()
	local loader = Loader.new(".")
	local ProfileSchema = loader:require("Server.Data.ProfileSchema")
	local NOW = 1_800_000_000

	T.Suite("Profile schema")

	T.Case("a new player gets a complete, DataStore-safe default profile", function()
		local profile, status, fixes = ProfileSchema.Prepare(nil, NOW, 1)
		T.Equal(status, "New")
		T.Equal(#fixes, 0)
		T.Equal(profile.SchemaVersion, ProfileSchema.CurrentVersion)
		T.Equal(profile.Stardust, 0)
		T.Equal(profile.Level, 1)
		T.True(profile.UnlockedBiomes.DawnCommons)
		T.Equal(profile.Equipment.HabitatLevel, 1)
		-- Survives a JSON round trip exactly.
		T.DeepEqual(Mock.JsonCopy(profile, "profile"), profile)
	end)

	T.Case("missing fields are filled without touching existing values", function()
		local raw = { SchemaVersion = 1, Stardust = 500, Settings = { MusicVolume = 0.2 } }
		local profile, status = ProfileSchema.Prepare(raw, NOW, 1)
		T.Equal(status, "Loaded")
		T.Equal(profile.Stardust, 500)
		T.Equal(profile.Settings.MusicVolume, 0.2)
		T.Equal(profile.Settings.EffectsVolume, 0.8)
		T.Equal(profile.Equipment.ScannerLevel, 1)
		T.True(type(profile.QuestProgress.Missions) == "table")
	end)

	T.Case("impossible values are repaired", function()
		local raw = ProfileSchema.Default(NOW)
		raw.Stardust = -50
		raw.MeteorShards = 0 / 0
		raw.Level = 999
		raw.XP = -3
		raw.Equipment.ScannerLevel = 42
		raw.Equipment.TetherLevel = 0
		raw.TutorialStage = 99
		raw.Settings.MusicVolume = 7
		raw.Settings.GraphicsQuality = "Ultra"
		local profile = ProfileSchema.Prepare(raw, NOW, 1)
		T.Equal(profile.Stardust, 0)
		T.Equal(profile.MeteorShards, 0)
		T.Equal(profile.Level, 50)
		T.Equal(profile.XP, 0)
		T.Equal(profile.Equipment.ScannerLevel, 5)
		T.Equal(profile.Equipment.TetherLevel, 1)
		T.Equal(profile.Settings.MusicVolume, 0.7)
		T.Equal(profile.Settings.GraphicsQuality, "Auto")
	end)

	T.Case("XP above the level threshold is clamped", function()
		local raw = ProfileSchema.Default(NOW)
		raw.Level = 3
		raw.XP = 100000
		local profile = ProfileSchema.Prepare(raw, NOW, 1)
		T.True(profile.XP < 210, "XP below level 3's threshold")
	end)

	T.Case("habitat assignments are validated", function()
		local raw = ProfileSchema.Default(NOW)
		raw.Creatures = {
			["1-1"] = { Id = "1-1", Species = "Pebblepuff", Mutation = "Standard", Bond = 1, Obtained = NOW },
			["1-2"] = { Id = "1-2", Species = "CometFox", Mutation = "Glittery", Bond = 9, Obtained = NOW },
		}
		raw.EquippedCreatures = {
			["1"] = "1-1",
			["2"] = "1-1", -- the same creature twice
			["3"] = "ghost", -- not owned
			["9"] = "1-2", -- slot 9 is locked at Habitat level 1
			["x"] = "1-2", -- not a slot
		}
		local profile = ProfileSchema.Prepare(raw, NOW, 1)
		local count = 0
		for _ in profile.EquippedCreatures do
			count += 1
		end
		T.Equal(count, 1)
		T.Equal(profile.EquippedCreatures["1"], "1-1")
		T.Equal(profile.Creatures["1-2"].Mutation, "Standard", "unknown mutation reset")
		T.Equal(profile.Creatures["1-2"].Bond, 5, "bond clamped")
		T.True(profile.DiscoveredSpecies.CometFox ~= nil, "owned species marked discovered")
	end)

	T.Case("creature IDs stay unique after repairs", function()
		local raw = ProfileSchema.Default(NOW)
		local id = ProfileSchema.CreatureId(77, 40)
		raw.Creatures[id] = { Id = id, Species = "Nebble", Mutation = "Standard", Bond = 1, Obtained = NOW }
		raw.NextCreatureSerial = 3
		local profile = ProfileSchema.Prepare(raw, NOW, 77)
		T.Equal(profile.NextCreatureSerial, 41)
	end)

	T.Case("unknown species are kept, never deleted", function()
		local raw = ProfileSchema.Default(NOW)
		raw.Creatures["5-1"] =
			{ Id = "5-1", Species = "RetiredCritter", Mutation = "Standard", Bond = 1, Obtained = NOW }
		raw.EquippedCreatures["1"] = "5-1"
		local profile = ProfileSchema.Prepare(raw, NOW, 5)
		T.True(profile.Creatures["5-1"] ~= nil)
		T.Equal(profile.EquippedCreatures["1"], nil, "but they can't sit in a habitat")
	end)

	T.Case("data from a newer game version is refused untouched", function()
		local raw = { SchemaVersion = ProfileSchema.CurrentVersion + 1, Stardust = 10 }
		local profile, status = ProfileSchema.Prepare(raw, NOW, 1)
		T.Equal(profile, nil)
		T.Equal(status, "TooNew")
		T.Equal(raw.Stardust, 10)
	end)

	T.Case("migrations run in order and bump the version", function()
		local fresh = Loader.new(".")
		local Schema = fresh:require("Server.Data.ProfileSchema")
		Schema.CurrentVersion = 2
		Schema.Migrations[1] = function(data)
			data.Stardust = (data.Stardust or 0) + 1
			data.Renamed = true
		end
		local raw = { SchemaVersion = 1, Stardust = 9 }
		local profile, status = Schema.Prepare(raw, NOW, 1)
		T.Equal(status, "Loaded")
		T.Equal(profile.SchemaVersion, 2)
		T.Equal(profile.Stardust, 10)
	end)

	T.Case("the client view hides private fields", function()
		local view = ProfileSchema.ClientView(ProfileSchema.Default(NOW))
		T.Equal(view.ProcessedReceipts, nil)
		T.Equal(view.IncomeRemainder, nil)
		T.Equal(view.Stardust, 0)
	end)

	T.Case("base36 IDs round-trip", function()
		for _, n in { 0, 1, 35, 36, 123456789, 9007199254 } do
			T.Equal(ProfileSchema.FromBase36(ProfileSchema.ToBase36(n)), n)
		end
		T.Equal(ProfileSchema.FromBase36("!!"), nil)
	end)
end

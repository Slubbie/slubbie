-- The saved profile: defaults and migrations.
--
-- Bump VERSION and add a step to MIGRATIONS whenever the shape changes, so old
-- saves upgrade cleanly instead of losing progress.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cosmetics = require(ReplicatedStorage.Shared.Config.Cosmetics)
local SettingsConfig = require(ReplicatedStorage.Shared.Config.Settings)

local Schema = {}

Schema.VERSION = 1

function Schema.Default(): { [string]: any }
	local inventory = {}
	for _, id in Cosmetics.StarterItems() do
		inventory[id] = true
	end
	local equipped = {}
	for category, id in Cosmetics.Defaults do
		equipped[category] = id
	end
	equipped.Emote = nil
	equipped.Emotes = { "emote_wave", "emote_salute", "emote_stretch" }

	return {
		Version = Schema.VERSION,
		Created = os.time(),
		LastJoin = os.time(),
		PlaySeconds = 0,
		XP = 0,
		Credits = 250,
		Prestige = 0,
		Skills = {},
		Mastery = { Points = {}, Challenges = {}, Claimed = {} },
		Courses = {},
		Quests = { Active = {}, Completed = {}, Pinned = {} },
		Daily = { Day = 0, Picks = {}, Progress = {}, Done = {}, Bonus = false },
		Weekly = { Week = 0, Picks = {}, Progress = {}, Done = {}, Seen = {} },
		Contracts = { Offers = {}, Active = nil, Completed = 0, Refresh = 0 },
		Discoveries = {},
		Lessons = {},
		Districts = { Visited = { Hub = true }, Last = "Hub" },
		Achievements = {},
		Stats = {},
		Inventory = inventory,
		Equipped = equipped,
		Settings = SettingsConfig.Defaults(),
		Bindings = {},
		Tower = { Highest = 0, Best = {} },
		Endless = { Best = 0 },
		Crew = nil,
		Flags = {},
	}
end

local MIGRATIONS: { [number]: (any) -> () } = {
	-- [2] = function(profile) ... end,
}

-- Fill any missing keys from the defaults (recursively for plain tables).
local function fill(target: { [any]: any }, defaults: { [any]: any })
	for key, value in defaults do
		if target[key] == nil then
			target[key] = if type(value) == "table" then table.clone(value) else value
		elseif type(value) == "table" and type(target[key]) == "table" and next(value) ~= nil then
			-- Only recurse into record-like defaults (string keys).
			local first = next(value)
			if type(first) == "string" then
				fill(target[key], value)
			end
		end
	end
end

function Schema.Migrate(profile: any): { [string]: any }
	if type(profile) ~= "table" then
		return Schema.Default()
	end
	local version = profile.Version or 1
	while version < Schema.VERSION do
		version += 1
		local step = MIGRATIONS[version]
		if step then
			step(profile)
		end
	end
	profile.Version = Schema.VERSION
	fill(profile, Schema.Default())
	-- Settings may gain new options between versions.
	for key, value in SettingsConfig.Defaults() do
		if SettingsConfig.Sanitize(key, profile.Settings[key]) == nil then
			profile.Settings[key] = value
		end
	end
	-- Starter items are always owned.
	for _, id in Cosmetics.StarterItems() do
		profile.Inventory[id] = true
	end
	return profile
end

return Schema

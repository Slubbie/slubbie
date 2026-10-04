-- Who can go where: district access milestones and course ability requirements.

local Abilities = require(script.Parent.Parent.Config.Abilities)
local Districts = require(script.Parent.Parent.Config.Districts)
local Quests = require(script.Parent.Parent.Config.Quests)

local Access = {}

-- Main story quest that must be finished before each district opens.
Access.Gates = {
	Hub = nil,
	Tinroof = "p_graduation",
	Ironworks = "c1_bell",
	Verdant = "c2_titan",
	Gilded = "c3_starfall",
	Frostreach = "c4_signal",
	Citadel = "c5_mast",
} :: { [string]: string? }

export type ProfileLike = { Level: number?, Quests: { Completed: { [string]: any } }? }

-- (allowed, reason)
function Access.District(level: number, completed: { [string]: any }, districtId: string): (boolean, string?)
	local district = Districts.ById[districtId]
	if not district then
		return false, "Unknown district"
	end
	if districtId == "Hub" then
		return true, nil
	end
	if level < district.Level then
		return false, ("Reach level %d"):format(district.Level)
	end
	local gate = Access.Gates[districtId]
	if gate and not completed[gate] then
		local quest = Quests.ById[gate]
		return false, ("Complete \"%s\""):format(if quest then quest.Name else gate)
	end
	return true, nil
end

-- Abilities a player has at a level.
function Access.Abilities(level: number): { [string]: boolean }
	return Abilities.ForLevel(level)
end

-- Which required abilities are missing. `requires` is a list of ability ids.
function Access.Missing(level: number, requires: { string }): { string }
	local have = Abilities.ForLevel(level)
	local missing = {}
	for _, id in requires do
		if not have[id] then
			table.insert(missing, id)
		end
	end
	return missing
end

-- Human-readable requirement line, e.g. "Needs Grapple Swing (level 16)".
function Access.MissingText(missing: { string }): string?
	if #missing == 0 then
		return nil
	end
	local parts = {}
	for _, id in missing do
		local ability = Abilities.ById[id]
		if ability then
			table.insert(parts, ("%s (level %d)"):format(ability.Name, ability.Level))
		end
	end
	return "Needs " .. table.concat(parts, ", ")
end

return Access

-- Level maths from total experience.

local Progression = require(script.Parent.Parent.Config.Progression)

local Leveling = {}

-- cumulative[L] = total XP needed to reach level L.
local cumulative = { [1] = 0 }
for level = 1, Progression.MaxLevel - 1 do
	cumulative[level + 1] = cumulative[level] + Progression.XPToNext(level)
end

function Leveling.TotalFor(level: number): number
	return cumulative[math.clamp(level, 1, Progression.MaxLevel)]
end

-- (level, xp into this level, xp needed for the next level)
function Leveling.FromXP(totalXP: number): (number, number, number)
	local level = 1
	-- Binary search the cumulative table.
	local lo, hi = 1, Progression.MaxLevel
	while lo <= hi do
		local mid = (lo + hi) // 2
		if cumulative[mid] <= totalXP then
			level = mid
			lo = mid + 1
		else
			hi = mid - 1
		end
	end
	if level >= Progression.MaxLevel then
		return Progression.MaxLevel, 0, 0
	end
	return level, totalXP - cumulative[level], Progression.XPToNext(level)
end

-- Total skill points earned by a level.
function Leveling.SkillPoints(level: number): number
	local total = 0
	for l = 2, level do
		total += Progression.SkillPointsFor(l)
	end
	return total
end

return Leveling

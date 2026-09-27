-- Clearance levels, titles and the XP / Marks formulas.
-- Progression is purely cosmetic: nothing here changes odds, health or tools.

local Levels = {}

Levels.Max = 100

-- XP needed to go from `level` to `level + 1`.
function Levels.toNext(level: number): number
	if level >= Levels.Max then
		return math.huge
	end
	return 180 + 45 * (level - 1) + math.floor(((level - 1) ^ 1.35) * 4)
end

-- Level, XP into the level and XP needed for the next, from lifetime XP.
function Levels.fromXP(totalXP: number): (number, number, number)
	local level = 1
	local remaining = math.max(0, math.floor(totalXP))
	while level < Levels.Max do
		local need = Levels.toNext(level)
		if remaining < need then
			return level, remaining, need
		end
		remaining -= need
		level += 1
	end
	return Levels.Max, 0, 0
end

Levels.Titles = {
	{ Level = 1, Title = "CANDIDATE" },
	{ Level = 5, Title = "SUBJECT" },
	{ Level = 10, Title = "PARTICIPANT" },
	{ Level = 15, Title = "ANALYST" },
	{ Level = 20, Title = "CALCULATOR" },
	{ Level = 30, Title = "STRATEGIST" },
	{ Level = 40, Title = "ACTUARY" },
	{ Level = 50, Title = "ARBITER" },
	{ Level = 65, Title = "AUDITOR" },
	{ Level = 75, Title = "ORACLE" },
	{ Level = 90, Title = "CONSTANT" },
	{ Level = 100, Title = "VARIANCE" },
}

function Levels.titleFor(level: number): string
	local title = Levels.Titles[1].Title
	for _, entry in Levels.Titles do
		if level >= entry.Level then
			title = entry.Title
		end
	end
	return title
end

-- Marks awarded on reaching a level (milestones pay more).
function Levels.marksForLevel(level: number): number
	if level % 10 == 0 then
		return 250
	elseif level % 5 == 0 then
		return 120
	end
	return 40
end

-- XP breakdown for a finished match. `outcome` comes from Core/Report.outcome.
function Levels.matchXP(outcome, modeScale: number, difficultyScale: number)
	local lines = {}
	local function add(label: string, amount: number)
		if amount > 0 then
			table.insert(lines, { Label = label, Amount = math.floor(amount + 0.5) })
		end
	end
	if outcome.Forfeited then
		return lines, 0
	end
	add("Trial completed", 60)
	if outcome.Won then
		add("Victory", 45)
	end
	add("Trials taken", 12 * outcome.TrialsWon)
	add("Correct reads", 3 * outcome.Reads)
	add("Self-shots survived", 4 * outcome.SelfSurvived)
	if outcome.ClutchTrials > 0 then
		add("Clutch", 20)
	end
	local total = 0
	for _, line in lines do
		line.Amount = math.floor(line.Amount * modeScale * difficultyScale + 0.5)
		total += line.Amount
	end
	return lines, total
end

function Levels.matchMarks(outcome, modeScale: number, difficultyScale: number): number
	if outcome.Forfeited then
		return 0
	end
	local marks = 12 + (outcome.Won and 18 or 0) + 2 * outcome.TrialsWon
	return math.floor(marks * modeScale * difficultyScale + 0.5)
end

return Levels

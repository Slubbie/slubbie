-- Course reward maths: first completions, medal upgrades, distinctions and
-- repeat runs scaled by difficulty and performance.

local Progression = require(script.Parent.Parent.Config.Progression)

local Rewards = {}

export type Breakdown = { Label: string, XP: number, Credits: number, Prestige: number }
export type Result = {
	Seconds: number,
	Medal: number,
	Distinctions: { [string]: boolean },
	Mode: string, -- "Casual" | "Practice" | "Ranked" | "Race" | "Relay"
}
export type Record = {
	Medal: number,
	Completions: number,
	Best: number?,
	Distinctions: { [string]: boolean },
}

function Rewards.DifficultyFactor(difficulty: number): number
	return 0.6 + 0.2 * math.clamp(difficulty, 1, 10)
end

-- Repeat runs pay full value for the first few runs of a course each session.
Rewards.RepeatFullRuns = 8
Rewards.RepeatTailFactor = 0.25

function Rewards.Course(
	difficulty: number,
	thresholds: { number },
	result: Result,
	record: Record,
	repeatsThisSession: number
): ({ Breakdown }, number, number, number)
	local factor = Rewards.DifficultyFactor(difficulty)
	local lines: { Breakdown } = {}
	local function add(label: string, xp: number, credits: number, prestige: number?)
		table.insert(lines, {
			Label = label,
			XP = math.floor(xp + 0.5),
			Credits = math.floor(credits + 0.5),
			Prestige = prestige or 0,
		})
	end

	if result.Mode == "Practice" then
		-- Practice is for learning: a small token amount only.
		add("Practice run", 10, 0)
	else
		if (record.Completions or 0) == 0 then
			add("First completion", Progression.XP.FirstCompletion * factor, Progression.Credits.FirstCompletion * factor)
		else
			local performance = math.clamp(thresholds[1] / math.max(result.Seconds, 1), 0.5, 1.6)
			local scale = if repeatsThisSession < Rewards.RepeatFullRuns then 1 else Rewards.RepeatTailFactor
			add(
				"Repeat run",
				Progression.XP.Repeat * factor * performance * scale,
				Progression.Credits.Repeat * factor * performance * scale
			)
		end
		local names = { "Bronze", "Silver", "Gold", "Platinum" }
		for medal = (record.Medal or 0) + 1, result.Medal do
			add(
				names[medal] .. " medal",
				Progression.XP.MedalUpgrade[medal] * factor,
				Progression.Credits.MedalUpgrade[medal] * factor,
				if medal == 4 then Progression.Prestige.Platinum else 0
			)
		end
		for id, earned in result.Distinctions do
			if earned and not (record.Distinctions or {})[id] then
				add("Distinction: " .. id, Progression.XP.Distinction * factor, 25 * factor)
			end
		end
		if record.Best and result.Seconds < record.Best then
			add("Personal best", Progression.XP.PersonalBest * factor, 0)
		end
	end

	local xp, credits, prestige = 0, 0, 0
	for _, line in lines do
		xp += line.XP
		credits += line.Credits
		prestige += line.Prestige
	end
	return lines, xp, credits, prestige
end

return Rewards

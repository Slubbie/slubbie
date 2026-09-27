-- Daily and weekly challenges.
--
-- Every player gets 3 dailies (easy / medium / hard) and 3 weeklies, picked
-- deterministically from their UserId and the day/week number, so a rejoin
-- never rerolls them. Metric(ctx) returns how much one finished match advances
-- the challenge (ctx is the same shape as in Achievements). Distinct challenges
-- count different values of Distinct(ctx) instead of summing.

local Challenges = {}

local DIFFICULTY_RANK = { Casual = 1, Standard = 2, Advanced = 3, Expert = 4, Adaptive = 3 }

local function finished(ctx): boolean
	return ctx.Outcome ~= nil and not ctx.Outcome.Forfeited
end

local function won(ctx): boolean
	return finished(ctx) and ctx.Outcome.Won
end

export type Challenge = {
	Id: string,
	Tier: string, -- Easy | Medium | Hard | Weekly
	Text: string, -- "{n}" is replaced by the goal
	Goal: { number }, -- {min, max}
	Metric: ((ctx: any) -> number)?,
	Distinct: ((ctx: any) -> string?)?,
}

local pool: { Challenge } = {
	-- Easy
	{
		Id = "d_finish",
		Tier = "Easy",
		Text = "Finish {n} matches",
		Goal = { 2, 3 },
		Metric = function(ctx)
			return finished(ctx) and 1 or 0
		end,
	},
	{
		Id = "d_reads",
		Tier = "Easy",
		Text = "Make {n} correct reads",
		Goal = { 6, 10 },
		Metric = function(ctx)
			return finished(ctx) and ctx.Outcome.Reads or 0
		end,
	},
	{
		Id = "d_instruments",
		Tier = "Easy",
		Text = "Use {n} instruments",
		Goal = { 5, 8 },
		Metric = function(ctx)
			return finished(ctx) and ctx.Outcome.InstrumentCount or 0
		end,
	},
	{
		Id = "d_selfsurvive",
		Tier = "Easy",
		Text = "Survive {n} shots at yourself",
		Goal = { 3, 5 },
		Metric = function(ctx)
			return finished(ctx) and ctx.Outcome.SelfSurvived or 0
		end,
	},
	-- Medium
	{
		Id = "d_wins",
		Tier = "Medium",
		Text = "Win {n} matches",
		Goal = { 1, 2 },
		Metric = function(ctx)
			return won(ctx) and 1 or 0
		end,
	},
	{
		Id = "d_damage",
		Tier = "Medium",
		Text = "Deal {n} damage",
		Goal = { 8, 12 },
		Metric = function(ctx)
			return finished(ctx) and ctx.Outcome.DamageDealt or 0
		end,
	},
	{
		Id = "d_standard",
		Tier = "Medium",
		Text = "Defeat a surrogate on Standard or harder",
		Goal = { 1, 1 },
		Metric = function(ctx)
			return (won(ctx) and ctx.Match.Solo and (DIFFICULTY_RANK[ctx.Match.Difficulty or ""] or 0) >= 2) and 1 or 0
		end,
	},
	{
		Id = "d_noheal",
		Tier = "Medium",
		Text = "Win a match without healing",
		Goal = { 1, 1 },
		Metric = function(ctx)
			return (won(ctx) and not ctx.Outcome.HealUsed and ctx.Outcome.Trials >= 2) and 1 or 0
		end,
	},
	{
		Id = "d_combo",
		Tier = "Medium",
		Text = "Use a Lens and a Capacitor in one turn and land the shot",
		Goal = { 1, 1 },
		Metric = function(ctx)
			return finished(ctx) and (ctx.Outcome.Combos.LensCapacitor or 0) or 0
		end,
	},
	{
		Id = "d_friend",
		Tier = "Medium",
		Text = "Finish a match with a friend",
		Goal = { 1, 1 },
		Metric = function(ctx)
			return (finished(ctx) and ctx.Match.WithFriend) and 1 or 0
		end,
	},
	-- Hard
	{
		Id = "d_clutch",
		Tier = "Hard",
		Text = "Take a Trial with a single point of Integrity",
		Goal = { 1, 1 },
		Metric = function(ctx)
			return finished(ctx) and ctx.Outcome.ClutchTrials or 0
		end,
	},
	{
		Id = "d_risky",
		Tier = "Hard",
		Text = "Survive {n} self-shots at 50% odds or worse",
		Goal = { 2, 3 },
		Metric = function(ctx)
			return finished(ctx) and ctx.Outcome.RiskySurvived or 0
		end,
	},
	{
		Id = "d_advanced",
		Tier = "Hard",
		Text = "Defeat a surrogate on Advanced or harder",
		Goal = { 1, 1 },
		Metric = function(ctx)
			return (won(ctx) and ctx.Match.Solo and (DIFFICULTY_RANK[ctx.Match.Difficulty or ""] or 0) >= 3) and 1 or 0
		end,
	},
	{
		Id = "d_modifier",
		Tier = "Hard",
		Text = "Win a match with a modifier active",
		Goal = { 1, 1 },
		Metric = function(ctx)
			return (won(ctx) and ctx.Outcome.Modifiers > 0) and 1 or 0
		end,
	},
	{
		Id = "d_hits",
		Tier = "Hard",
		Text = "Correctly call {n} CHARGED cells at an opponent",
		Goal = { 5, 8 },
		Metric = function(ctx)
			if not finished(ctx) then
				return 0
			end
			return math.max(0, ctx.Outcome.Reads - ctx.Outcome.SelfSurvived)
		end,
	},
	-- Weekly
	{
		Id = "w_wins",
		Tier = "Weekly",
		Text = "Win {n} matches",
		Goal = { 8, 12 },
		Metric = function(ctx)
			return won(ctx) and 1 or 0
		end,
	},
	{
		Id = "w_ranked",
		Tier = "Weekly",
		Text = "Win {n} ranked matches",
		Goal = { 3, 5 },
		Metric = function(ctx)
			return (won(ctx) and ctx.Match.Ranked) and 1 or 0
		end,
	},
	{
		Id = "w_endurance",
		Tier = "Weekly",
		Text = "Reach Endurance stage 3",
		Goal = { 3, 3 },
		Metric = function(ctx)
			return (ctx.Match and ctx.Match.EnduranceStage) or 0
		end,
	},
	{
		Id = "w_environments",
		Tier = "Weekly",
		Text = "Win in {n} different environments",
		Goal = { 3, 4 },
		Distinct = function(ctx)
			if won(ctx) then
				return ctx.Match.Environment
			end
			return nil
		end,
	},
	{
		Id = "w_surrogates",
		Tier = "Weekly",
		Text = "Defeat {n} different surrogates",
		Goal = { 3, 4 },
		Distinct = function(ctx)
			if won(ctx) and ctx.Match.Solo and ctx.Match.Personality ~= "Proxy" then
				return ctx.Match.Personality
			end
			return nil
		end,
	},
	{
		Id = "w_reads",
		Tier = "Weekly",
		Text = "Make {n} correct reads",
		Goal = { 50, 70 },
		Metric = function(ctx)
			return finished(ctx) and ctx.Outcome.Reads or 0
		end,
	},
	{
		Id = "w_rare",
		Tier = "Weekly",
		Text = "Use {n} Rare instruments",
		Goal = { 5, 8 },
		Metric = function(ctx)
			if not finished(ctx) then
				return 0
			end
			local n = 0
			for _, id in { "Overclock", "Serum", "PowerTap", "Tether", "Scrambler" } do
				n += ctx.Outcome.Instruments[id] or 0
			end
			return n
		end,
	},
}

Challenges.Pool = pool
Challenges.ById = {} :: { [string]: Challenge }
for _, c in pool do
	Challenges.ById[c.Id] = c
end

Challenges.Rewards = {
	Easy = { XP = 60, Marks = 30 },
	Medium = { XP = 110, Marks = 55 },
	Hard = { XP = 180, Marks = 90 },
	Weekly = { XP = 420, Marks = 220 },
}

-- Deterministic small hash so selection is stable per player per period.
-- (Lehmer-style steps kept below 2^53 so doubles stay exact.)
local function mix(a: number, b: number): number
	local h = (math.floor(a) % 2147483647) * 16807 + (math.floor(b) % 2147483647) * 48271 + 12345
	h %= 2147483647
	h = (h * 48271) % 2147483647
	return h
end

local function pick(tier: string, seed: number, count: number): { Challenge }
	local candidates = {}
	for _, c in pool do
		if c.Tier == tier then
			table.insert(candidates, c)
		end
	end
	table.sort(candidates, function(a, b)
		return a.Id < b.Id
	end)
	local out = {}
	local s = seed
	while #out < count and #candidates > 0 do
		s = mix(s, #candidates + #out)
		local index = (s % #candidates) + 1
		table.insert(out, table.remove(candidates, index))
	end
	return out
end

local function goalFor(c: Challenge, seed: number): number
	local lo, hi = c.Goal[1], c.Goal[2]
	if hi <= lo then
		return lo
	end
	return lo + (mix(seed, #c.Id) % (hi - lo + 1))
end

-- The day number (UTC) and week number used for rotation.
function Challenges.day(unixTime: number): number
	return math.floor(unixTime / 86400)
end

function Challenges.week(unixTime: number): number
	-- Weeks start on Monday (the Unix epoch was a Thursday).
	return math.floor((unixTime / 86400 + 3) / 7)
end

function Challenges.dailyFor(userId: number, day: number)
	local list = {}
	for i, tier in { "Easy", "Medium", "Hard" } do
		local seed = mix(math.abs(userId) % 1000003 + i * 7919, day)
		local c = pick(tier, seed, 1)[1]
		if c then
			table.insert(list, { Id = c.Id, Goal = goalFor(c, seed), Progress = 0, Done = false, Claimed = false, Seen = {} })
		end
	end
	return list
end

function Challenges.weeklyFor(userId: number, week: number)
	local list = {}
	local seed = mix(math.abs(userId) % 1000003 + 104729, week)
	for i, c in pick("Weekly", seed, 3) do
		table.insert(list, {
			Id = c.Id,
			Goal = goalFor(c, seed + i),
			Progress = 0,
			Done = false,
			Claimed = false,
			Seen = {},
		})
	end
	return list
end

function Challenges.text(entry): string
	local def = Challenges.ById[entry.Id]
	if def == nil then
		return "Unknown challenge"
	end
	return (string.gsub(def.Text, "{n}", tostring(entry.Goal)))
end

-- Applies one finished match to a challenge entry. Returns true if it just completed.
function Challenges.apply(entry, ctx): boolean
	if entry.Done then
		return false
	end
	local def = Challenges.ById[entry.Id]
	if def == nil then
		return false
	end
	if def.Distinct then
		local value = def.Distinct(ctx)
		if value ~= nil and not entry.Seen[value] then
			entry.Seen[value] = true
			entry.Progress += 1
		end
	elseif def.Metric then
		local amount = def.Metric(ctx)
		if def.Id == "w_endurance" then
			entry.Progress = math.max(entry.Progress, amount)
		else
			entry.Progress += math.max(0, math.floor(amount))
		end
	end
	if entry.Progress >= entry.Goal then
		entry.Progress = entry.Goal
		entry.Done = true
		return true
	end
	return false
end

return Challenges

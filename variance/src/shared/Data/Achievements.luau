-- Achievements: milestones and hidden mastery challenges.
--
-- Each Check(ctx) runs on the server after a match (and after level-ups,
-- cosmetic unlocks, lore reads, etc.) with:
--   ctx.Event    "MatchEnd" | "Level" | "Cosmetic" | "Lore" | "Tutorial" | "Ranked" | "Witness"
--   ctx.Profile  the saved profile (already updated with this match)
--   ctx.Outcome  Core/Report.outcome for this player (MatchEnd only)
--   ctx.Match    { ModeId, Solo, Difficulty, Personality, WithFriend, Ranked,
--                  Tournament, TournamentWon, EnduranceStage, Environment }
-- Progress(profile) (optional) returns current, goal for progress bars.
-- Hidden achievements show as "???" until unlocked.

local Instruments = require(script.Parent.Parent.Core.Instruments)

local Achievements = {}

local DIFFICULTY_RANK = { Casual = 1, Standard = 2, Advanced = 3, Expert = 4, Adaptive = 3 }

local function stat(profile, key: string): number
	return profile.Stats[key] or 0
end

local function won(ctx): boolean
	return ctx.Event == "MatchEnd" and ctx.Outcome ~= nil and ctx.Outcome.Won
end

local function soloWinAtLeast(ctx, tier: string): boolean
	if not won(ctx) or not ctx.Match.Solo then
		return false
	end
	return (DIFFICULTY_RANK[ctx.Match.Difficulty or ""] or 0) >= DIFFICULTY_RANK[tier]
end

local function surrogateWins(profile, personality: string, minTier: string): boolean
	local record = profile.SurrogateWins[personality]
	if record == nil then
		return false
	end
	for tier, count in record do
		if count > 0 and (DIFFICULTY_RANK[tier] or 0) >= DIFFICULTY_RANK[minTier] then
			return true
		end
	end
	return false
end

export type Achievement = {
	Id: string,
	Name: string,
	Description: string,
	Hidden: boolean,
	Marks: number,
	XP: number,
	Check: (ctx: any) -> boolean,
	Progress: ((profile: any) -> (number, number))?,
}

local list: { Achievement } = {
	{
		Id = "ach_first",
		Name = "FIRST TRIAL",
		Description = "Win a match.",
		Hidden = false,
		Marks = 50,
		XP = 50,
		Check = function(ctx)
			return stat(ctx.Profile, "Wins") >= 1
		end,
		Progress = function(p)
			return math.min(stat(p, "Wins"), 1), 1
		end,
	},
	{
		Id = "ach_wins10",
		Name = "TEN DOWN",
		Description = "Win 10 matches.",
		Hidden = false,
		Marks = 150,
		XP = 150,
		Check = function(ctx)
			return stat(ctx.Profile, "Wins") >= 10
		end,
		Progress = function(p)
			return math.min(stat(p, "Wins"), 10), 10
		end,
	},
	{
		Id = "ach_wins50",
		Name = "FIFTY DOWN",
		Description = "Win 50 matches.",
		Hidden = false,
		Marks = 400,
		XP = 400,
		Check = function(ctx)
			return stat(ctx.Profile, "Wins") >= 50
		end,
		Progress = function(p)
			return math.min(stat(p, "Wins"), 50), 50
		end,
	},
	{
		Id = "ach_matches100",
		Name = "VETERAN",
		Description = "Finish 100 matches.",
		Hidden = false,
		Marks = 400,
		XP = 400,
		Check = function(ctx)
			return stat(ctx.Profile, "Matches") >= 100
		end,
		Progress = function(p)
			return math.min(stat(p, "Matches"), 100), 100
		end,
	},
	{
		Id = "ach_reads100",
		Name = "ANALYST",
		Description = "Make 100 correct reads (CHARGED at an opponent, or HOLLOW at yourself).",
		Hidden = false,
		Marks = 200,
		XP = 200,
		Check = function(ctx)
			return stat(ctx.Profile, "Reads") >= 100
		end,
		Progress = function(p)
			return math.min(stat(p, "Reads"), 100), 100
		end,
	},
	{
		Id = "ach_instrumentalist",
		Name = "INSTRUMENTALIST",
		Description = "Use every instrument at least once.",
		Hidden = false,
		Marks = 200,
		XP = 200,
		Check = function(ctx)
			for _, def in Instruments.List do
				if (ctx.Profile.InstrumentUse[def.Id] or 0) < 1 then
					return false
				end
			end
			return true
		end,
		Progress = function(p)
			local n = 0
			for _, def in Instruments.List do
				if (p.InstrumentUse[def.Id] or 0) > 0 then
					n += 1
				end
			end
			return n, #Instruments.List
		end,
	},
	{
		Id = "ach_surgeon",
		Name = "FIELD SURGEON",
		Description = "Restore 50 Integrity in total.",
		Hidden = false,
		Marks = 150,
		XP = 150,
		Check = function(ctx)
			return stat(ctx.Profile, "Healed") >= 50
		end,
		Progress = function(p)
			return math.min(stat(p, "Healed"), 50), 50
		end,
	},
	{
		Id = "ach_collector",
		Name = "COLLECTOR",
		Description = "Own 25 cosmetics.",
		Hidden = false,
		Marks = 200,
		XP = 100,
		Check = function(ctx)
			local n = 0
			for _ in ctx.Profile.Cosmetics.Owned do
				n += 1
			end
			return n >= 25
		end,
		Progress = function(p)
			local n = 0
			for _ in p.Cosmetics.Owned do
				n += 1
			end
			return math.min(n, 25), 25
		end,
	},
	{
		Id = "ach_level10",
		Name = "CLEARED",
		Description = "Reach Clearance Level 10.",
		Hidden = false,
		Marks = 100,
		XP = 0,
		Check = function(ctx)
			return (ctx.Profile.Level or 1) >= 10
		end,
	},
	{
		Id = "ach_level25",
		Name = "SENIOR STAFF",
		Description = "Reach Clearance Level 25.",
		Hidden = false,
		Marks = 250,
		XP = 0,
		Check = function(ctx)
			return (ctx.Profile.Level or 1) >= 25
		end,
	},
	{
		Id = "ach_level50",
		Name = "TENURED",
		Description = "Reach Clearance Level 50.",
		Hidden = false,
		Marks = 500,
		XP = 0,
		Check = function(ctx)
			return (ctx.Profile.Level or 1) >= 50
		end,
	},
	{
		Id = "ach_tutorial",
		Name = "ORIENTED",
		Description = "Complete Orientation.",
		Hidden = false,
		Marks = 75,
		XP = 100,
		Check = function(ctx)
			return ctx.Profile.Tutorial.Basic == true
		end,
	},
	{
		Id = "ach_seminars",
		Name = "POSTGRADUATE",
		Description = "Complete every advanced seminar.",
		Hidden = false,
		Marks = 200,
		XP = 200,
		Check = function(ctx)
			local seminars = ctx.Profile.Tutorial.Seminars
			for _, id in { "Conditional", "Information", "TurnEconomy", "Sequencing", "Mistakes" } do
				if not seminars[id] then
					return false
				end
			end
			return true
		end,
	},
	{
		Id = "ach_ledger",
		Name = "BALANCED BOOKS",
		Description = "Defeat LEDGER on Standard or higher.",
		Hidden = false,
		Marks = 100,
		XP = 100,
		Check = function(ctx)
			return surrogateWins(ctx.Profile, "Ledger", "Standard")
		end,
	},
	{
		Id = "ach_volta",
		Name = "GROUNDED",
		Description = "Defeat VOLTA on Standard or higher.",
		Hidden = false,
		Marks = 100,
		XP = 100,
		Check = function(ctx)
			return surrogateWins(ctx.Profile, "Volta", "Standard")
		end,
	},
	{
		Id = "ach_magpie",
		Name = "FILED AWAY",
		Description = "Defeat MAGPIE on Standard or higher.",
		Hidden = false,
		Marks = 100,
		XP = 100,
		Check = function(ctx)
			return surrogateWins(ctx.Profile, "Magpie", "Standard")
		end,
	},
	{
		Id = "ach_kismet",
		Name = "HOUSE EDGE",
		Description = "Defeat KISMET on Standard or higher.",
		Hidden = false,
		Marks = 100,
		XP = 100,
		Check = function(ctx)
			return surrogateWins(ctx.Profile, "Kismet", "Standard")
		end,
	},
	{
		Id = "ach_expert",
		Name = "EXPERT WITNESS",
		Description = "Defeat any surrogate on Expert.",
		Hidden = false,
		Marks = 200,
		XP = 200,
		Check = function(ctx)
			return soloWinAtLeast(ctx, "Expert")
		end,
	},
	{
		Id = "ach_allexpert",
		Name = "SURROGATE SWEEP",
		Description = "Defeat LEDGER, VOLTA, MAGPIE and KISMET on Expert.",
		Hidden = false,
		Marks = 600,
		XP = 500,
		Check = function(ctx)
			for _, id in { "Ledger", "Volta", "Magpie", "Kismet" } do
				if not surrogateWins(ctx.Profile, id, "Expert") then
					return false
				end
			end
			return true
		end,
		Progress = function(p)
			local n = 0
			for _, id in { "Ledger", "Volta", "Magpie", "Kismet" } do
				if surrogateWins(p, id, "Expert") then
					n += 1
				end
			end
			return n, 4
		end,
	},
	{
		Id = "ach_placement",
		Name = "PLACED",
		Description = "Complete your ranked placement matches.",
		Hidden = false,
		Marks = 150,
		XP = 150,
		Check = function(ctx)
			return (ctx.Profile.Ranked.Games or 0) >= 5
		end,
	},
	{
		Id = "ach_strategist",
		Name = "STRATEGIST",
		Description = "Reach the Strategist division.",
		Hidden = false,
		Marks = 250,
		XP = 250,
		Check = function(ctx)
			return (ctx.Profile.Ranked.Peak or 0) >= 1100 and (ctx.Profile.Ranked.Games or 0) >= 5
		end,
	},
	{
		Id = "ach_oracle",
		Name = "ORACLE",
		Description = "Reach the Oracle division.",
		Hidden = false,
		Marks = 1000,
		XP = 800,
		Check = function(ctx)
			return (ctx.Profile.Ranked.Peak or 0) >= 1500 and (ctx.Profile.Ranked.Games or 0) >= 5
		end,
	},
	{
		Id = "ach_friend",
		Name = "COMPANY",
		Description = "Finish a match against or alongside a friend.",
		Hidden = false,
		Marks = 75,
		XP = 75,
		Check = function(ctx)
			return ctx.Event == "MatchEnd" and ctx.Match.WithFriend == true
		end,
	},
	{
		Id = "ach_tournament",
		Name = "CHAMPION",
		Description = "Win a tournament.",
		Hidden = false,
		Marks = 500,
		XP = 400,
		Check = function(ctx)
			return ctx.Event == "MatchEnd" and ctx.Match.TournamentWon == true
		end,
	},
	{
		Id = "ach_endurance",
		Name = "ENDURANCE",
		Description = "Complete all five Endurance stages.",
		Hidden = false,
		Marks = 500,
		XP = 400,
		Check = function(ctx)
			return (ctx.Profile.Stats.EnduranceBest or 0) >= 5
		end,
		Progress = function(p)
			return math.min(p.Stats.EnduranceBest or 0, 5), 5
		end,
	},
	{
		Id = "ach_chaos",
		Name = "AGENT OF CHAOS",
		Description = "Win a Chaos match.",
		Hidden = false,
		Marks = 100,
		XP = 100,
		Check = function(ctx)
			return won(ctx) and ctx.Match.ModeId == "Chaos"
		end,
	},
	{
		Id = "ach_precision",
		Name = "PRECISION INSTRUMENT",
		Description = "Win a Precision match.",
		Hidden = false,
		Marks = 100,
		XP = 100,
		Check = function(ctx)
			return won(ctx) and ctx.Match.ModeId == "Precision"
		end,
	},
	{
		Id = "ach_rapid",
		Name = "QUICK STUDY",
		Description = "Win a Rapid match.",
		Hidden = false,
		Marks = 100,
		XP = 100,
		Check = function(ctx)
			return won(ctx) and ctx.Match.ModeId == "Rapid"
		end,
	},
	{
		Id = "ach_archive",
		Name = "ARCHIVIST",
		Description = "Read every file in the Halden archive.",
		Hidden = false,
		Marks = 250,
		XP = 250,
		Check = function(ctx)
			return ctx.Profile.Lore.AllRead == true
		end,
	},
	-- Hidden ------------------------------------------------------------------
	{
		Id = "ach_ironnerve",
		Name = "IRON NERVE",
		Description = "Survive four self-shots in a row at 50% odds of CHARGED or worse, in one match.",
		Hidden = true,
		Marks = 300,
		XP = 300,
		Check = function(ctx)
			return ctx.Event == "MatchEnd" and ctx.Outcome.MaxRiskyStreak >= 4
		end,
	},
	{
		Id = "ach_lastfilament",
		Name = "LAST FILAMENT",
		Description = "Win a match after being reduced to a single point of Integrity.",
		Hidden = true,
		Marks = 250,
		XP = 250,
		Check = function(ctx)
			return won(ctx) and ctx.Outcome.MinIntegrity == 1
		end,
	},
	{
		Id = "ach_nocrutches",
		Name = "NO CRUTCHES",
		Description = "Defeat an Expert surrogate without healing.",
		Hidden = true,
		Marks = 400,
		XP = 300,
		Check = function(ctx)
			return soloWinAtLeast(ctx, "Expert") and not ctx.Outcome.HealUsed
		end,
	},
	{
		Id = "ach_chemistry",
		Name = "UNUSUAL CHEMISTRY",
		Description = "Win a match in which you used a Tether and a Power Tap in the same turn.",
		Hidden = true,
		Marks = 300,
		XP = 250,
		Check = function(ctx)
			return won(ctx) and (ctx.Outcome.Combos.TetherTap or 0) > 0
		end,
	},
	{
		Id = "ach_perfect",
		Name = "PERFECT LEDGER",
		Description = "Win a match without a single mistake on a certain cell (at least three certain decisions).",
		Hidden = true,
		Marks = 400,
		XP = 300,
		Check = function(ctx)
			return won(ctx) and ctx.Outcome.PerfectTracking
		end,
	},
	{
		Id = "ach_barehands",
		Name = "BARE HANDS",
		Description = "Win a full match without using any instrument, against Advanced or better or another subject.",
		Hidden = true,
		Marks = 350,
		XP = 300,
		Check = function(ctx)
			if not won(ctx) or ctx.Outcome.InstrumentCount > 0 or ctx.Outcome.Trials < 2 then
				return false
			end
			if ctx.Match.Solo then
				return soloWinAtLeast(ctx, "Advanced")
			end
			return true
		end,
	},
	{
		Id = "ach_collapse",
		Name = "MUTUAL COLLAPSE",
		Description = "Win a sudden-death Load.",
		Hidden = true,
		Marks = 250,
		XP = 200,
		Check = function(ctx)
			return ctx.Event == "MatchEnd" and ctx.Outcome.SuddenDeathWon
		end,
	},
	{
		Id = "ach_longshot",
		Name = "AGAINST THE ODDS",
		Description = "Eliminate an opponent with a shot you had 25% odds or less of being CHARGED.",
		Hidden = true,
		Marks = 200,
		XP = 200,
		Check = function(ctx)
			return ctx.Event == "MatchEnd" and ctx.Outcome.LethalLowShot
		end,
	},
	{
		Id = "ach_volatile",
		Name = "SURGE PROTECTOR",
		Description = "Land a primed Capacitor on a Surge cell.",
		Hidden = true,
		Marks = 200,
		XP = 150,
		Check = function(ctx)
			return ctx.Event == "MatchEnd" and (ctx.Outcome.Combos.SurgeCapacitor or 0) > 0
		end,
	},
	{
		Id = "ach_proctor",
		Name = "THE ADMINISTRATOR",
		Description = "Defeat the Proctor.",
		Hidden = true,
		Marks = 1000,
		XP = 800,
		Check = function(ctx)
			return won(ctx) and ctx.Match.Solo and ctx.Match.Personality == "Proctor"
		end,
	},
	{
		Id = "ach_witness",
		Name = "WITNESS",
		Description = "See the Proctor watching a Trial it was not part of.",
		Hidden = true,
		Marks = 150,
		XP = 100,
		Check = function(ctx)
			return ctx.Event == "Witness"
		end,
	},
}

Achievements.List = list
Achievements.ById = {} :: { [string]: Achievement }
for _, a in list do
	Achievements.ById[a.Id] = a
end

function Achievements.get(id: string): Achievement?
	return Achievements.ById[id]
end

return Achievements

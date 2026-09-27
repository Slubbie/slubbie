-- Post-match report: the summary screen, key moments, round history and the
-- per-subject outcome that progression, statistics, challenges and achievements
-- are computed from.
--
-- Built only once the match has ended, which is the first moment the full cell
-- sequences may be revealed. Every probability quoted in it is the one the acting
-- subject could actually compute at the time.

local Instruments = require(script.Parent.Instruments)
local Format = require(script.Parent.Parent.Util.Format)

local Report = {}

local function favourite(instruments: { [string]: number }): string?
	local best, count = nil, 0
	for id, n in instruments do
		if n > count or (n == count and best ~= nil and id < best) then
			best, count = id, n
		end
	end
	return best
end

-- Per-subject outcome used by server-side progression systems.
function Report.outcome(state, subject)
	local stats = subject.Stats
	local won = state.WinnerTeam ~= nil and subject.TeamId == state.WinnerTeam and not subject.Forfeited
	return {
		Won = won,
		Forfeited = subject.Forfeited,
		TrialsWon = stats.TrialsWon,
		Trials = state.Trial,
		Shots = stats.Shots,
		ShotsSelf = stats.ShotsSelf,
		ShotsOther = stats.ShotsOther,
		Reads = stats.Reads,
		SelfSurvived = stats.SelfSurvived,
		RiskySurvived = stats.RiskySurvived,
		MaxRiskyStreak = stats.MaxRiskyStreak,
		DamageDealt = stats.DamageDealt,
		DamageTaken = stats.DamageTaken,
		ChargedTaken = stats.ChargedTaken,
		Healed = stats.Healed,
		HealUsed = stats.HealUsed,
		Instruments = table.clone(stats.Instruments),
		InstrumentCount = stats.InstrumentCount,
		MinIntegrity = stats.MinIntegrity == math.huge and 0 or stats.MinIntegrity,
		FinalIntegrity = subject.Integrity,
		ClutchTrials = stats.ClutchTrials,
		Combos = table.clone(stats.Combos),
		PerfectTracking = stats.CertainDecisions >= 3 and stats.CertainMistakes == 0,
		CertainDecisions = stats.CertainDecisions,
		LowShotHits = stats.LowShotHits,
		LethalLowShot = stats.LethalLowShot,
		SuddenDeaths = stats.SuddenDeaths,
		SuddenDeathWon = stats.SuddenDeaths > 0 and won,
		WonAtOne = won and subject.Integrity == 1,
		Timeouts = stats.Timeouts,
		BestRisk = stats.BestRisk,
		Eliminations = stats.Eliminations,
		Favourite = favourite(stats.Instruments),
		ModeId = state.Rules.ModeId,
		Modifiers = (function()
			local n = 0
			for _ in state.Rules.Modifiers do
				n += 1
			end
			return n + (state.Rules.ChaosPerTrial > 0 and 1 or 0)
		end)(),
	}
end

local function nameOf(state, id)
	local s = state.Subjects[id]
	return s and s.Name or "?"
end

function Report.keyMoments(state)
	local moments = {}
	local riskiest, decisive, biggest, longShot = nil, nil, nil, nil
	for _, entry in state.Log do
		if entry.Kind == "Fire" then
			local selfShot = entry.Actor == entry.Target
			if selfShot and not entry.Charged and entry.ActorP > 0 then
				if riskiest == nil or entry.ActorP > riskiest.ActorP then
					riskiest = entry
				end
			end
			if entry.Lethal then
				decisive = entry
			end
			if entry.Charged and entry.Damage > 0 and (biggest == nil or entry.Damage > biggest.Damage) then
				biggest = entry
			end
			if not selfShot and entry.Charged and entry.ActorP <= 0.25 then
				if longShot == nil or entry.ActorP < longShot.ActorP then
					longShot = entry
				end
			end
		end
	end
	if riskiest then
		table.insert(moments, {
			Kind = "Riskiest",
			Title = "HIGHEST-RISK SURVIVAL",
			Subject = riskiest.Actor,
			Trial = riskiest.Trial,
			Load = riskiest.Load,
			P = riskiest.ActorP,
			Text = string.format(
				"%s fired at themselves at %s odds of CHARGED and walked away.",
				nameOf(state, riskiest.Actor),
				Format.percent(riskiest.ActorP)
			),
		})
	end
	if longShot then
		table.insert(moments, {
			Kind = "LongShot",
			Title = "AGAINST THE ODDS",
			Subject = longShot.Actor,
			Trial = longShot.Trial,
			Load = longShot.Load,
			P = longShot.ActorP,
			Text = string.format(
				"%s fired at %s with only %s odds of CHARGED, and it landed.",
				nameOf(state, longShot.Actor),
				nameOf(state, longShot.Target),
				Format.percent(longShot.ActorP)
			),
		})
	end
	if biggest and biggest.Damage >= 2 then
		table.insert(moments, {
			Kind = "Biggest",
			Title = "HEAVIEST DISCHARGE",
			Subject = biggest.Actor,
			Trial = biggest.Trial,
			Load = biggest.Load,
			Text = string.format("%s dealt %d damage in a single shot.", nameOf(state, biggest.Actor), biggest.Damage),
		})
	end
	if decisive then
		local used = #decisive.Used > 0 and (" after " .. table.concat(decisive.Used, ", ")) or ""
		table.insert(moments, {
			Kind = "Decisive",
			Title = "DECISIVE ACTION",
			Subject = decisive.Actor,
			Trial = decisive.Trial,
			Load = decisive.Load,
			P = decisive.ActorP,
			Text = string.format(
				"%s ended Trial %s%s, at %s odds.",
				nameOf(state, decisive.Actor),
				Format.roman(decisive.Trial),
				used,
				Format.percent(decisive.ActorP)
			),
		})
	end
	for _, subject in state.Subjects do
		if subject.Stats.ClutchTrials > 0 then
			table.insert(moments, {
				Kind = "Clutch",
				Title = "ONE POINT LEFT",
				Subject = subject.Id,
				Text = string.format("%s took a Trial with a single point of Integrity remaining.", subject.Name),
			})
		end
		if subject.Stats.SuddenDeaths > 0 then
			table.insert(moments, {
				Kind = "SuddenDeath",
				Title = "MUTUAL COLLAPSE",
				Subject = subject.Id,
				Text = string.format("%s went through a sudden-death Load.", subject.Name),
			})
			break
		end
	end
	return moments
end

-- Full, revealed history of every Load (safe: the match is over).
function Report.history(state)
	local loads = {}
	for _, record in state.LoadRecords do
		table.insert(loads, {
			Trial = record.Trial,
			Load = record.Load,
			Pattern = record.Pattern,
			Recast = record.Recast,
		})
	end
	local actions = {}
	for _, entry in state.Log do
		if entry.Kind == "Fire" then
			table.insert(actions, {
				Kind = "Fire",
				Trial = entry.Trial,
				Load = entry.Load,
				Actor = entry.Actor,
				Target = entry.Target,
				Charged = entry.Charged,
				Damage = entry.Damage,
				P = entry.ActorP,
				PublicP = entry.PublicP,
				Timeout = entry.Timeout,
			})
		else
			local def = Instruments.get(entry.Id)
			table.insert(actions, {
				Kind = "Use",
				Trial = entry.Trial,
				Load = entry.Load,
				Actor = entry.Actor,
				Target = entry.Target,
				Id = entry.Id,
				Name = def and def.Name or entry.Id,
			})
		end
	end
	return loads, actions
end

function Report.build(state)
	local subjects = {}
	for _, subject in state.Subjects do
		local outcome = Report.outcome(state, subject)
		subjects[subject.Id] = {
			Id = subject.Id,
			Name = subject.Name,
			TeamId = subject.TeamId,
			IsAI = subject.IsAI,
			UserId = subject.UserId,
			Personality = subject.Personality,
			Won = outcome.Won,
			TrialWins = subject.TrialWins,
			FinalIntegrity = subject.Integrity,
			Shots = outcome.Shots,
			Reads = outcome.Reads,
			Accuracy = outcome.Shots > 0 and outcome.Reads / outcome.Shots or 0,
			DamageDealt = outcome.DamageDealt,
			DamageTaken = outcome.DamageTaken,
			ChargedTaken = outcome.ChargedTaken,
			SelfSurvived = outcome.SelfSurvived,
			Healed = outcome.Healed,
			InstrumentCount = outcome.InstrumentCount,
			Instruments = outcome.Instruments,
			Favourite = outcome.Favourite,
			BestRisk = outcome.BestRisk,
			Forfeited = subject.Forfeited,
		}
	end
	local loads, actions = Report.history(state)
	return {
		MatchId = state.MatchId,
		ModeId = state.Rules.ModeId,
		ModeName = state.Rules.ModeName,
		WinnerTeam = state.WinnerTeam,
		Reason = state.EndReason or "Trials",
		Trials = state.Trial,
		Subjects = subjects,
		KeyMoments = Report.keyMoments(state),
		Loads = loads,
		Actions = actions,
	}
end

return Report

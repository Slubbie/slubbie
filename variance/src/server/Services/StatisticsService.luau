-- Lifetime statistics and match history.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Variance.Config)
local TableUtil = require(ReplicatedStorage.Variance.Util.TableUtil)
local Difficulty = require(ReplicatedStorage.Variance.Core.AI.Difficulty)

local StatisticsService = {}

function StatisticsService:Init(services)
	self.Services = services
end

function StatisticsService:record(player: Player, outcome, info)
	self.Services.DataService:update(player, function(data)
		local s = data.Stats
		s.Matches += 1
		if outcome.Won then
			s.Wins += 1
			s.Streak += 1
			s.BestStreak = math.max(s.BestStreak, s.Streak)
		else
			s.Losses += 1
			s.Streak = 0
		end
		if outcome.Forfeited then
			s.Forfeits += 1
		end
		s.Reads += outcome.Reads
		s.Shots += outcome.Shots
		s.SelfShots += outcome.ShotsSelf
		s.SelfSurvived += outcome.SelfSurvived
		s.RiskySurvived += outcome.RiskySurvived
		s.DamageDealt += outcome.DamageDealt
		s.DamageTaken += outcome.DamageTaken
		s.Healed += outcome.Healed
		s.Instruments += outcome.InstrumentCount
		s.TrialsWon += outcome.TrialsWon
		s.BestRisk = math.max(s.BestRisk, math.floor(outcome.BestRisk * 100 + 0.5))
		if outcome.Won and (outcome.WonAtOne or outcome.ClutchTrials > 0) then
			s.ClutchWins += 1
		end
		if outcome.SuddenDeathWon then
			s.SuddenDeathWins += 1
		end
		if info.Solo then
			s.SoloMatches += 1
			if outcome.Won then
				s.SoloWins += 1
			end
		else
			s.PvPMatches += 1
			if outcome.Won then
				s.PvPWins += 1
			end
		end
		if info.EnduranceStage then
			s.EnduranceBest = math.max(s.EnduranceBest, info.EnduranceStage)
		end
		if info.TournamentWon then
			s.TournamentsWon += 1
		end
		if outcome.Won and info.Environment then
			data.EnvironmentWins[info.Environment] = (data.EnvironmentWins[info.Environment] or 0) + 1
		end
		for id, n in outcome.Instruments do
			data.InstrumentUse[id] = (data.InstrumentUse[id] or 0) + n
		end
		if info.Solo and outcome.Won and info.Difficulty then
			data.AIWins[info.Difficulty] = (data.AIWins[info.Difficulty] or 0) + 1
			if info.Personality then
				local record = data.SurrogateWins[info.Personality] or {}
				local tier = info.Difficulty
				if tier == "Adaptive" then
					-- Credit the tier the adaptive opponent was effectively playing at.
					local skill = data.AdaptiveSkill
					tier = skill >= 0.75 and "Expert" or skill >= 0.4 and "Advanced" or "Standard"
				end
				record[tier] = (record[tier] or 0) + 1
				data.SurrogateWins[info.Personality] = record
			end
			-- The Proctor opens up once all four surrogates have fallen on Expert.
			local sweep = true
			for _, id in { "Ledger", "Volta", "Magpie", "Kismet" } do
				local r = data.SurrogateWins[id]
				if r == nil or (r.Expert or 0) < 1 then
					sweep = false
				end
			end
			if sweep and not data.Flags.ProctorUnlocked then
				data.Flags.ProctorUnlocked = true
				task.defer(function()
					self.Services.NetworkService:notify(
						player,
						"NEW OPPONENT",
						"THE PROCTOR has asked to evaluate you personally.",
						"Good"
					)
				end)
			end
		end
		if info.Solo and info.Difficulty == "Adaptive" and not info.EnduranceStage then
			data.AdaptiveSkill =
				Difficulty.updateSkill(data.AdaptiveSkill, outcome.Won, outcome.TrialsWon / math.max(outcome.Trials, 1))
		end
		table.insert(data.History, {
			Time = os.time(),
			Mode = info.ModeId,
			Result = outcome.Forfeited and "FORFEIT" or (outcome.Won and "WIN" or "LOSS"),
			Opponent = info.OpponentName or "?",
			Score = info.Score or "",
			Delta = info.RatingDelta,
			Env = info.Environment,
			Difficulty = info.Difficulty,
		})
		TableUtil.trimFront(data.History, Config.Data.MatchHistoryLimit)
	end)
end

-- Unlocks the Proctor once all four surrogates have fallen on Expert.
function StatisticsService:proctorUnlocked(player: Player): boolean
	local profile = self.Services.DataService:get(player)
	if profile == nil then
		return false
	end
	local data = profile.Data
	if data.Flags.ProctorUnlocked then
		return true
	end
	for _, id in { "Ledger", "Volta", "Magpie", "Kismet" } do
		local record = data.SurrogateWins[id]
		if record == nil or (record.Expert or 0) < 1 then
			return false
		end
	end
	return true
end

function StatisticsService:Start()
	self.Services.NetworkService:handle("History.Get", function(player)
		local profile = self.Services.DataService:get(player)
		if profile == nil then
			return false, "Profile not ready."
		end
		return true, profile.Data.History
	end)
end

return StatisticsService

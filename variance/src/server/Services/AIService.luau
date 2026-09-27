-- Surrogate decision-making on the server: builds a Brain per AI subject,
-- applies adaptive difficulty, and guarantees an action even if something
-- goes wrong (errors, timeouts or an illegal choice all fall back to a safe,
-- sensible shot based only on public information).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Variance.Config)
local Engine = require(ReplicatedStorage.Variance.Core.Engine)
local Probability = require(ReplicatedStorage.Variance.Core.Probability)
local Brain = require(ReplicatedStorage.Variance.Core.AI.Brain)
local Difficulty = require(ReplicatedStorage.Variance.Core.AI.Difficulty)
local Tendencies = require(ReplicatedStorage.Variance.Core.AI.Tendencies)

local AIService = {}

function AIService:Init(services)
	self.Services = services
end

-- Resolves a difficulty id to a tier table (Adaptive uses the human's skill).
function AIService:tier(difficultyId: string, skill: number?): any
	if difficultyId == "Adaptive" then
		return Difficulty.adaptive(skill or 0.35)
	end
	return Difficulty.get(difficultyId)
end

-- Creates the brain for an AI participant.
function AIService:createBrain(personality: string, difficultyId: string, skill: number?)
	local participantSkill = skill or 0.35
	local brain = Brain.new({
		Personality = personality,
		Difficulty = self:tier(difficultyId, participantSkill),
		Rng = Random.new(),
		Tendencies = Tendencies.new(),
	})
	return {
		Brain = brain,
		DifficultyId = difficultyId,
		Skill = participantSkill,
		MatchAdjust = 0,
	}
end

-- Called at each Trial start: opponents sharpen as the match escalates, and
-- the adaptive tier nudges toward a close contest.
function AIService:onTrialStart(ai, trial: number, humanTrialLead: number)
	if ai.DifficultyId == "Adaptive" then
		ai.MatchAdjust = math.clamp(ai.MatchAdjust + humanTrialLead * 0.12, -0.3, 0.3)
		local tier = Difficulty.adaptive(math.clamp(ai.Skill + ai.MatchAdjust, 0, 1))
		ai.Brain:setDifficulty(Difficulty.forTrial(tier, trial))
	else
		ai.Brain:setDifficulty(Difficulty.forTrial(Difficulty.get(ai.DifficultyId), trial))
	end
end

-- A safe action from public information only.
function AIService:fallback(state, subjectId: number)
	local belief = Engine.belief(state, subjectId)
	local p = Probability.current(belief)
	local me = state.Subjects[subjectId]
	if p < 0.5 then
		return { Kind = "Fire", Target = subjectId }
	end
	for _, other in state.Subjects do
		if other ~= me and not other.Eliminated and Engine.isOpponent(state, me, other) then
			return { Kind = "Fire", Target = other.Id }
		end
	end
	return { Kind = "Fire", Target = subjectId }
end

-- Developer override of a surrogate's behaviour (DebugService).
local function overridden(self, ai, state, subjectId: number)
	local mode = ai.Override
	if mode == "AlwaysSelf" then
		return { Kind = "Fire", Target = subjectId }
	elseif mode == "AlwaysOther" then
		local fallback = self:fallback(state, subjectId)
		for _, other in state.Subjects do
			if
				other.Id ~= subjectId
				and not other.Eliminated
				and Engine.isOpponent(state, state.Subjects[subjectId], other)
			then
				return { Kind = "Fire", Target = other.Id }
			end
		end
		return fallback
	elseif mode == "Random" then
		local legal = {}
		for _, a in Engine.legal(state, subjectId) do
			if a.Ok ~= false then
				table.insert(legal, a)
			end
		end
		if #legal > 0 then
			local a = legal[math.random(1, #legal)]
			return { Kind = a.Kind, Target = a.Target, Slot = a.Slot }
		end
	elseif mode == "Stall" then
		return "stall"
	end
	return nil
end

-- Decides for an AI subject. Returns (action, thinkSeconds, info).
function AIService:decide(ai, state, subjectId: number)
	if ai.Override then
		local forced = overridden(self, ai, state, subjectId)
		if forced == "stall" then
			-- Simulates an AI that never answers: the hard timeout must rescue the turn.
			return self:fallback(state, subjectId), Config.Match.AIThinkTimeout, { Reason = "stall" }
		elseif forced then
			return forced, 0.6, { Reason = "override" }
		end
	end
	local started = os.clock()
	local ok, action, info = pcall(function()
		return ai.Brain:decide(Engine.aiView(state, subjectId))
	end)
	if not ok or type(action) ~= "table" then
		warn("[VARIANCE/AI] decision failed, using fallback: " .. tostring(action))
		return self:fallback(state, subjectId), 1.2, nil
	end
	if os.clock() - started > Config.Match.AIThinkTimeout then
		return self:fallback(state, subjectId), 0.5, nil
	end
	local think = ai.Brain:thinkTime(info)
	return action, think, info
end

return AIService

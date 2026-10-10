--!strict
-- The comet capture minigame as pure, deterministic math.
--
-- The server builds the parameters (from a random seed plus biome, comet
-- type, tether and accessibility modifiers) and sends them to the client.
-- The client draws the dial and meter from these functions and shows
-- predicted feedback instantly; the server re-scores every reported press
-- with the same functions and is the only one that awards anything.
--
-- Stage 1 — Energy Lock: an indicator circles the dial. Press while it's in
--   the highlighted zone.
-- Stage 2 — Stabilize: hold to charge the meter, release while the level is
--   inside a slowly drifting band. Holding too long overcharges.
-- Stage 3 — Containment: an animation; no input.
--
-- Times passed to Score* are seconds since the current attempt started.

local GameConfig = require(script.Parent.GameConfig)

local CaptureMath = {}

export type Modifiers = {
	SpeedMult: number?,
	ZoneMult: number?,
	BandMult: number?,
	DriftMult: number?,
	QualityBonus: number?,
	QualityCap: number?,
	MissesAllowed: number?,
}

export type Params = {
	Seed: number,
	DialPeriod: number,
	ZoneHalfWidth: number,
	ChargeTime: number,
	OverchargeTime: number,
	BandHalfWidth: number,
	BandDrift: number,
	BandPeriod: number,
	EdgeScore: number,
	MissesAllowed: number,
	MissPenalty: number,
	MissPause: number,
	IntroTime: number,
	TransitionTime: number,
	MinReaction: number,
	StageTimeout: number,
	QualityBonus: number,
	QualityCap: number,
}

export type StageResult = {
	Hit: boolean,
	Score: number,
	-- Why a press missed: "Early", "Late", "Overcharged", "Undercharged", "TooFast", "Timeout"
	Reason: string?,
}

local MODULUS = 2147483647

-- Park–Miller style generator: exact in double precision, identical on every machine.
local function unitNoise(seed: number, attempt: number, salt: number): number
	local state = (math.floor(seed) + attempt * 7919 + salt * 104729) % (MODULUS - 1) + 1
	for _ = 1, 3 do
		state = (state * 48271) % MODULUS
	end
	return state / MODULUS
end
CaptureMath.UnitNoise = unitNoise

function CaptureMath.BuildParams(seed: number, modifiers: Modifiers?): Params
	local c = GameConfig.Capture
	local m: Modifiers = modifiers or ({} :: Modifiers)
	local speed = m.SpeedMult or 1
	return {
		Seed = seed,
		DialPeriod = c.DialPeriod / math.max(speed, 0.05),
		ZoneHalfWidth = math.clamp(c.ZoneHalfWidth * (m.ZoneMult or 1), 6, 120),
		ChargeTime = c.ChargeTime / math.max(speed, 0.05) ^ 0.5,
		OverchargeTime = c.OverchargeTime / math.max(speed, 0.05) ^ 0.5,
		BandHalfWidth = math.clamp(c.BandHalfWidth * (m.BandMult or 1), 0.04, 0.35),
		BandDrift = c.BandDrift * (m.DriftMult or 1),
		BandPeriod = c.BandPeriod,
		EdgeScore = c.EdgeScore,
		MissesAllowed = m.MissesAllowed or c.MissesAllowed,
		MissPenalty = c.MissPenalty,
		MissPause = c.MissPause,
		IntroTime = c.IntroTime,
		TransitionTime = c.TransitionTime,
		MinReaction = c.MinReaction,
		StageTimeout = c.StageTimeout,
		QualityBonus = m.QualityBonus or 0,
		QualityCap = m.QualityCap or 1,
	}
end

-- Stage 1 ------------------------------------------------------------------

-- Degrees clockwise from the top of the dial. Every attempt starts at the top.
function CaptureMath.DialAngle(params: Params, t: number): number
	return (360 * t / params.DialPeriod) % 360
end

-- Centre of the lock zone for an attempt, 120°–300° from the start so there
-- is always time to react on the first pass.
function CaptureMath.ZoneCenter(params: Params, attempt: number): number
	return 120 + unitNoise(params.Seed, attempt, 1) * 180
end

-- Signed shortest difference a - b in degrees, in (-180, 180].
local function angleDelta(a: number, b: number): number
	local d = (a - b) % 360
	if d > 180 then
		d -= 360
	end
	return d
end

local function zoneScore(params: Params, distance: number, halfWidth: number): number
	return 1 - (1 - params.EdgeScore) * math.clamp(distance / halfWidth, 0, 1)
end

function CaptureMath.ScoreLock(params: Params, attempt: number, t: number): StageResult
	if t < params.MinReaction then
		return { Hit = false, Score = 0, Reason = "TooFast" }
	end
	if t > params.StageTimeout then
		return { Hit = false, Score = 0, Reason = "Timeout" }
	end
	local delta = angleDelta(CaptureMath.DialAngle(params, t), CaptureMath.ZoneCenter(params, attempt))
	local distance = math.abs(delta)
	if distance <= params.ZoneHalfWidth then
		return { Hit = true, Score = zoneScore(params, distance, params.ZoneHalfWidth) }
	end
	return { Hit = false, Score = 0, Reason = if delta < 0 then "Early" else "Late" }
end

-- Stage 2 ------------------------------------------------------------------

-- Meter level (0–1) after holding for `hold` seconds, and whether it overcharged.
function CaptureMath.ChargeLevel(params: Params, hold: number): (number, boolean)
	if hold <= 0 then
		return 0, false
	end
	if hold > params.OverchargeTime then
		return 1, true
	end
	return math.clamp(hold / params.ChargeTime, 0, 1) ^ 1.15, false
end

-- Where the band's centre is `t` seconds into an attempt.
function CaptureMath.BandCenter(params: Params, attempt: number, t: number): number
	local base = 0.45 + unitNoise(params.Seed, attempt, 2) * 0.25
	local phase = unitNoise(params.Seed, attempt, 3) * math.pi * 2
	local center = base + params.BandDrift * math.sin(2 * math.pi * t / params.BandPeriod + phase)
	local margin = params.BandHalfWidth + 0.02
	return math.clamp(center, margin, 1 - margin)
end

-- holdStart/holdEnd are seconds since the attempt started.
function CaptureMath.ScoreRelease(params: Params, attempt: number, holdStart: number, holdEnd: number): StageResult
	if holdStart < 0 or holdEnd <= holdStart then
		return { Hit = false, Score = 0, Reason = "TooFast" }
	end
	if holdEnd > params.StageTimeout + params.OverchargeTime then
		return { Hit = false, Score = 0, Reason = "Timeout" }
	end
	local level, overcharged = CaptureMath.ChargeLevel(params, holdEnd - holdStart)
	if overcharged then
		return { Hit = false, Score = 0, Reason = "Overcharged" }
	end
	local center = CaptureMath.BandCenter(params, attempt, holdEnd)
	local distance = math.abs(level - center)
	if distance <= params.BandHalfWidth then
		return { Hit = true, Score = zoneScore(params, distance, params.BandHalfWidth) }
	end
	return { Hit = false, Score = 0, Reason = if level < center then "Undercharged" else "Overcharged" }
end

-- Result ---------------------------------------------------------------

function CaptureMath.FinalQuality(params: Params, lockScore: number, releaseScore: number, misses: number): number
	local quality = 0.5 * lockScore + 0.5 * releaseScore - misses * params.MissPenalty + params.QualityBonus
	return math.clamp(quality, 0, params.QualityCap)
end

-- How far behind the server's clock a reported press may be (network lag).
function CaptureMath.LatencyTolerance(ping: number): number
	local c = GameConfig.Capture
	return math.clamp(ping * c.LatencyPingFactor + c.LatencyBase, c.LatencyBase, c.LatencyMax)
end

return CaptureMath

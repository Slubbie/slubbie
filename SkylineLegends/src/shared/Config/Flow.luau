-- The flow system: rewards varied, well-executed, connected movement.
--
-- Each technique adds points. Repeating the same move in a short window is
-- worth less (variety), linking a move quickly after the last one is worth
-- more (clean transition), and controlled landings keep the chain alive while
-- stumbles and falls break it. Flow drains when you stop moving with purpose.
--
-- In free exploration the meter is a quiet visual; in course runs the points
-- earned become the run's flow score (for the "In the Flow" distinction,
-- score challenges and cosmetic milestones).

local Flow = {
	Points = {
		Jump = 2,
		Vault = 14,
		Slide = 6,
		SlideJump = 10,
		Mantle = 8,
		LedgeGrab = 6,
		LedgeLeap = 14,
		ClimbHop = 6,
		WallRun = 16,
		WallJump = 18,
		WallKick = 12,
		WallClimb = 12,
		DoubleJump = 9,
		Dash = 10,
		Grapple = 16,
		GrappleRelease = 8,
		Pull = 14,
		RopeSwing = 14,
		Zipline = 10,
		Balance = 8,
		BalanceCatch = 6,
		Roll = 18,
		PrecisionLand = 16,
		Bounce = 8,
		Launch = 8,
		Land = 3,
	},
	-- Moves that sustain flow while you're doing them (points per second).
	Sustain = { WallRun = 10, Climb = 3, Balance = 5, Zipline = 6, Swing = 7, Slide = 4 },
	-- The same move this many times among your last N moves loses value.
	VarietyWindow = 5,
	VarietyFalloff = { 1, 0.6, 0.35, 0.2, 0.1 },
	-- A move this soon after the previous one counts as a clean transition.
	TransitionWindow = 0.7,
	TransitionBonus = 0.35,
	-- Speed that counts as "moving with purpose".
	MomentumSpeed = 20,
	IdleGrace = 1.4, -- seconds before the meter starts draining
	DrainPerSecond = 90,
	MeterMax = 1000,
	-- Meter thresholds for each tier, with names and score multipliers.
	Tiers = {
		{ Name = "Rhythm", Threshold = 80, Multiplier = 1.1 },
		{ Name = "Flow", Threshold = 250, Multiplier = 1.25 },
		{ Name = "Surge", Threshold = 480, Multiplier = 1.5 },
		{ Name = "Seamless", Threshold = 720, Multiplier = 1.8 },
		{ Name = "Legendary", Threshold = 920, Multiplier = 2.2 },
	},
	-- Course runs: the "In the Flow" distinction needs this fraction of the
	-- course's flow target (set per course from its length and techniques).
	DistinctionFraction = 1,
	-- Chain bookkeeping shared with the server: a chain breaks after this long
	-- without a move, or on any breaker action.
	ChainGap = 1.8,
	ChainBreakers = { Stumble = true, Fall = true, Respawn = true },
}

function Flow.TierFor(meter: number): number
	local tier = 0
	for index, info in Flow.Tiers do
		if meter >= info.Threshold then
			tier = index
		end
	end
	return tier
end

return Flow

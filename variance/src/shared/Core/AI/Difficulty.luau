-- Difficulty tiers. Each tier is a genuinely different way of thinking, not a
-- health bonus:
--
--   Casual    "Gut" play: a noisy read of the odds, random instrument use,
--             forgets what it saw, occasionally blunders.
--   Standard  Basic probability: reads the odds correctly from the counts and
--             the loaded cell, and follows sensible rules of thumb for
--             instruments, but never looks ahead (no turn economy, lethal
--             lines, health disparity or value of information).
--   Advanced  Full conditional probability from everything it has learned, exact
--             win-probability evaluation of every shot (lethal lines, turn
--             retention, health disparity), value-of-information for Lens/Sonar,
--             and conserves instruments it expects to need later.
--   Expert    Everything above plus two-step instrument sequencing (Lens then
--             Capacitor, Inverter then self-shot), a model of how *you* play that
--             it blends into its predictions, and reading your instrument
--             patterns. Still a little noisy so it feels human.
--   Adaptive  Interpolates between Standard and Expert from a skill estimate the
--             server tracks for each player, and shifts within a match.

local Difficulty = {}

export type Tier = {
	Id: string,
	Name: string,
	Description: string,
	Mode: string, -- "Gut", "Heuristic" or "Utility"
	Depth: number, -- instrument lookahead
	UseFutureKnowledge: boolean, -- conditions on known later cells
	InfoValue: boolean, -- values information (Lens/Sonar) by what it would change
	Noise: number, -- std-dev added to its probability estimate
	Retention: number, -- chance per turn to remember an older observation
	Blunder: number, -- chance to pick among its top three instead of the best
	Temperature: number, -- softmax temperature over win-probability values
	HoldScale: number, -- how much it values keeping instruments for later
	ModelWeight: number, -- trust in its model of your behaviour
	Inference: boolean, -- reads your instrument sequences for hidden knowledge
	ItemChance: number, -- Gut only: chance to fiddle with a random instrument
	Think: { number }, -- seconds {min, max} before acting
	XPScale: number,
	MarksScale: number,
}

local tiers: { [string]: Tier } = {
	Casual = {
		Id = "Casual",
		Name = "CASUAL",
		Description = "Plays on instinct. Misreads the odds and forgets things.",
		Mode = "Gut",
		Depth = 0,
		UseFutureKnowledge = false,
		InfoValue = false,
		Noise = 0.22,
		Retention = 0.55,
		Blunder = 0.14,
		Temperature = 0.05,
		HoldScale = 0,
		ModelWeight = 0,
		Inference = false,
		ItemChance = 0.35,
		Think = { 0.9, 2.1 },
		XPScale = 0.6,
		MarksScale = 0.6,
	},
	Standard = {
		Id = "Standard",
		Name = "STANDARD",
		Description = "Counts the cells. Trusts what it sees. Spends freely.",
		Mode = "Heuristic",
		Depth = 1,
		UseFutureKnowledge = false,
		InfoValue = false,
		Noise = 0.07,
		Retention = 0.8,
		Blunder = 0.05,
		Temperature = 0.012,
		HoldScale = 0.2,
		ModelWeight = 0,
		Inference = false,
		ItemChance = 0,
		Think = { 1.1, 2.5 },
		XPScale = 1,
		MarksScale = 1,
	},
	Advanced = {
		Id = "Advanced",
		Name = "ADVANCED",
		Description = "Conditional odds, lethal lines and patient instrument use.",
		Mode = "Utility",
		Depth = 1,
		UseFutureKnowledge = true,
		InfoValue = true,
		Noise = 0.03,
		Retention = 0.95,
		Blunder = 0.02,
		Temperature = 0.005,
		HoldScale = 0.8,
		ModelWeight = 0,
		Inference = false,
		ItemChance = 0,
		Think = { 1.3, 3.0 },
		XPScale = 1.25,
		MarksScale = 1.2,
	},
	Expert = {
		Id = "Expert",
		Name = "EXPERT",
		Description = "Sequences instruments, models your habits and reads your tells.",
		Mode = "Utility",
		Depth = 2,
		UseFutureKnowledge = true,
		InfoValue = true,
		Noise = 0.012,
		Retention = 1,
		Blunder = 0.01,
		Temperature = 0.002,
		HoldScale = 1,
		ModelWeight = 0.35,
		Inference = true,
		ItemChance = 0,
		Think = { 1.4, 3.6 },
		XPScale = 1.5,
		MarksScale = 1.4,
	},
}

Difficulty.Order = { "Casual", "Standard", "Advanced", "Expert" }
Difficulty.Tiers = tiers
Difficulty.Adaptive = {
	Id = "Adaptive",
	Name = "ADAPTIVE",
	Description = "Matches your skill, and adjusts between Trials.",
}

function Difficulty.get(id: string): Tier
	return tiers[id] or tiers.Standard
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Adaptive: skill 0 plays like Standard, 1 like Expert. Booleans switch at thresholds.
function Difficulty.adaptive(skill: number): Tier
	skill = math.clamp(skill, 0, 1)
	local lo, hi = tiers.Standard, tiers.Expert
	return {
		Id = "Adaptive",
		Name = "ADAPTIVE",
		Description = Difficulty.Adaptive.Description,
		Mode = skill < 0.25 and "Heuristic" or "Utility",
		Depth = skill >= 0.75 and 2 or 1,
		UseFutureKnowledge = skill >= 0.3,
		InfoValue = skill >= 0.4,
		Noise = lerp(lo.Noise, hi.Noise, skill),
		Retention = lerp(lo.Retention, hi.Retention, skill),
		Blunder = lerp(lo.Blunder, hi.Blunder, skill),
		Temperature = lerp(lo.Temperature, hi.Temperature, skill),
		HoldScale = lerp(lo.HoldScale, hi.HoldScale, skill),
		ModelWeight = lerp(0, hi.ModelWeight, skill),
		Inference = skill >= 0.85,
		ItemChance = 0,
		Think = { lerp(lo.Think[1], hi.Think[1], skill), lerp(lo.Think[2], hi.Think[2], skill) },
		XPScale = lerp(lo.XPScale, hi.XPScale, skill),
		MarksScale = lerp(lo.MarksScale, hi.MarksScale, skill),
	}
end

-- Opponents sharpen as a match escalates: less noise and fewer blunders each Trial.
function Difficulty.forTrial(tier: Tier, trial: number): Tier
	local sharpen = math.clamp(1 - 0.12 * (trial - 1), 0.6, 1)
	local copy = table.clone(tier)
	copy.Noise = tier.Noise * sharpen
	copy.Blunder = tier.Blunder * sharpen
	return copy
end

-- Adaptive skill update after a match: moves toward challenging the player.
function Difficulty.updateSkill(skill: number, playerWon: boolean, margin: number?): number
	local step = 0.08 + 0.04 * math.clamp(margin or 0, 0, 1)
	if playerWon then
		return math.clamp(skill + step, 0, 1)
	end
	return math.clamp(skill - step * 0.75, 0, 1)
end

return Difficulty

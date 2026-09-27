-- Turns care factors into a quality score and tier (see Config/Quality).

local Quality = require(script.Parent.Parent.Config.Quality)

local QualityMath = {}

export type Factors = {
	Water: number,
	Soil: number,
	Nutrients: number,
	Fertilizer: number,
	Climate: number,
	Genes: number,
	Timing: number,
}

-- Weighted score in [0,1] (bonus is added after weighting, e.g. skills and tools).
function QualityMath.Score(factors: Factors, bonus: number?): number
	local score = 0
	for key, weight in Quality.Weights do
		score += weight * math.clamp((factors :: any)[key] or 0, 0, 1)
	end
	return math.clamp(score + (bonus or 0), 0, 1)
end

function QualityMath.TierFor(score: number, maxTier: number?): number
	local tier = 1
	for _, def in Quality.Tiers do
		if score >= def.Threshold then
			tier = def.Tier
		end
	end
	return math.clamp(tier, 1, maxTier or #Quality.Tiers)
end

function QualityMath.Def(tier: number)
	return Quality.Tiers[math.clamp(tier, 1, #Quality.Tiers)]
end

-- Fraction of the way from this tier's threshold to the next (for progress bars).
function QualityMath.Progress(score: number): number
	local tier = QualityMath.TierFor(score)
	local current = Quality.Tiers[tier].Threshold
	local nextTier = Quality.Tiers[tier + 1]
	if not nextTier then
		return 1
	end
	return math.clamp((score - current) / (nextTier.Threshold - current), 0, 1)
end

-- Freshness factor: 1 while fresh, then linear decay to 0.
function QualityMath.Timing(hoursSinceRipe: number): number
	if hoursSinceRipe <= Quality.FreshHours then
		return 1
	end
	return math.clamp(1 - (hoursSinceRipe - Quality.FreshHours) / Quality.DecayHours, 0, 1)
end

-- Advice for the factor holding a crop back the most (for the tile tooltip).
local ADVICE = {
	Water = "Keep the soil inside the crop's water band.",
	Soil = "Improve soil health with compost and crop rotation.",
	Nutrients = "Balance nutrients with Nitro Mix, Bone Meal or Potash.",
	Fertilizer = "Use a better fertilizer.",
	Climate = "Grow it in season, or in a greenhouse.",
	Genes = "Breed seeds with higher Luster.",
	Timing = "Harvest while it's fresh.",
}

function QualityMath.Weakest(factors: Factors): (string, string)
	local worst, worstLoss = "Water", -1
	for key, weight in Quality.Weights do
		local loss = weight * (1 - math.clamp((factors :: any)[key] or 0, 0, 1))
		if loss > worstLoss then
			worst, worstLoss = key, loss
		end
	end
	return worst, ADVICE[worst]
end

return QualityMath

-- Ranked Standing: a transparent Elo rating with placements and divisions.
--
-- Everything here is shown to players: the expected result before a match, the
-- K-factor in use, and the exact change afterwards. Ranked rewards are cosmetic.

local Rating = {}

Rating.Start = 1000
Rating.Floor = 0
Rating.Placements = 5

-- K-factor: large while placing, then settling as a subject plays more.
function Rating.kFactor(gamesPlayed: number): number
	if gamesPlayed < Rating.Placements then
		return 48
	elseif gamesPlayed < 30 then
		return 32
	end
	return 24
end

function Rating.expected(ratingA: number, ratingB: number): number
	return 1 / (1 + 10 ^ ((ratingB - ratingA) / 400))
end

-- score: 1 win, 0 loss (0.5 is supported for future draw rules).
-- Returns the new rating and the rounded delta.
function Rating.update(rating: number, opponentRating: number, score: number, k: number): (number, number)
	local expected = Rating.expected(rating, opponentRating)
	local delta = math.floor(k * (score - expected) + 0.5)
	if score == 1 and delta < 1 then
		delta = 1
	elseif score == 0 and delta > -1 then
		delta = -1
	end
	local new = math.max(Rating.Floor, rating + delta)
	return new, new - rating
end

-- Rating for a player who left: always a full-K loss.
function Rating.abandon(rating: number, opponentRating: number, gamesPlayed: number): (number, number)
	local k = math.max(Rating.kFactor(gamesPlayed), 32)
	return Rating.update(rating, opponentRating, 0, k)
end

-- New season: halfway back toward the starting rating.
function Rating.softReset(rating: number): number
	return math.floor(Rating.Start + (rating - Rating.Start) * 0.5 + 0.5)
end

Rating.Divisions = {
	{ Id = "Probationer", Name = "PROBATIONER", Min = 0, Color = { 140, 140, 140 } },
	{ Id = "Analyst", Name = "ANALYST", Min = 900, Color = { 170, 150, 110 } },
	{ Id = "Strategist", Name = "STRATEGIST", Min = 1100, Color = { 120, 170, 190 } },
	{ Id = "Arbiter", Name = "ARBITER", Min = 1300, Color = { 225, 165, 70 } },
	{ Id = "Oracle", Name = "ORACLE", Min = 1500, Color = { 235, 90, 70 } },
}

-- Division, tier (III, II, I; Oracle has none) and progress to the next tier.
function Rating.division(rating: number)
	local index = 1
	for i, div in Rating.Divisions do
		if rating >= div.Min then
			index = i
		end
	end
	local div = Rating.Divisions[index]
	local nextDiv = Rating.Divisions[index + 1]
	if nextDiv == nil then
		return {
			Id = div.Id,
			Name = div.Name,
			Tier = nil,
			Label = div.Name,
			Color = div.Color,
			Progress = 1,
			Index = index,
		}
	end
	local span = nextDiv.Min - div.Min
	local step = span / 3
	local into = rating - div.Min
	local tier = 3 - math.clamp(math.floor(into / step), 0, 2)
	local tierMin = div.Min + (3 - tier) * step
	local progress = math.clamp((rating - tierMin) / step, 0, 1)
	local roman = ({ "I", "II", "III" })[tier]
	return {
		Id = div.Id,
		Name = div.Name,
		Tier = tier,
		Label = div.Name .. " " .. roman,
		Color = div.Color,
		Progress = progress,
		Index = index,
	}
end

-- Queue matching window: widens the longer a subject waits.
function Rating.window(waitSeconds: number): number
	return math.min(100 + 25 * math.floor(waitSeconds / 5), 600)
end

-- Abandon penalty ladder (queue lockout in seconds) by active strikes.
Rating.Lockouts = { 0, 5 * 60, 15 * 60, 60 * 60, 4 * 60 * 60 }

function Rating.lockoutFor(strikes: number): number
	return Rating.Lockouts[math.clamp(strikes + 1, 1, #Rating.Lockouts)]
end

return Rating

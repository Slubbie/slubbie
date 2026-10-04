-- Medal maths. Thresholds are { bronze, silver, gold, platinum } in seconds
-- (lower is better). Medal values: 0 none, 1 bronze ... 4 platinum.

local Medals = {}

function Medals.For(seconds: number, thresholds: { number }): number
	local medal = 0
	for index, limit in thresholds do
		if seconds <= limit then
			medal = index
		end
	end
	return medal
end

-- The next medal above the one this time earns, and its time limit.
function Medals.Next(seconds: number?, thresholds: { number }): (number?, number?)
	local current = if seconds then Medals.For(seconds, thresholds) else 0
	if current >= #thresholds then
		return nil, nil
	end
	return current + 1, thresholds[current + 1]
end

-- 0..1 position of a time on the medal bar (bronze at 0, platinum at 1).
function Medals.BarPosition(seconds: number, thresholds: { number }): number
	local bronze, platinum = thresholds[1], thresholds[#thresholds]
	if bronze <= platinum then
		return 1
	end
	return math.clamp((bronze - seconds) / (bronze - platinum), 0, 1)
end

-- Build thresholds from route par times (seconds of ideal play per route).
-- Platinum demands the best route executed well; bronze is a relaxed finish.
function Medals.FromPar(accessible: number, fast: number, expert: number): { number }
	-- Par times assume ideal lines, so thresholds leave room for real runs.
	local best = math.min(accessible, fast, expert)
	local platinum = best * 1.12 + 1
	local gold = math.max(math.min(accessible, fast) * 1.3 + 1.5, platinum + 1)
	local silver = math.max(accessible * 1.55 + 3, gold + 2)
	local bronze = math.max(accessible * 2.4 + 8, silver + 6)
	local function round(x: number): number
		return math.floor(x * 2 + 0.5) / 2
	end
	return { round(bronze), round(silver), round(gold), round(platinum) }
end

return Medals

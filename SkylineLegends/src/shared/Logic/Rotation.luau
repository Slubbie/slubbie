-- Day/week numbers and deterministic picks for rotating objectives.

local Rotation = {}

local DAY = 86400
local WEEK = DAY * 7
-- The Unix epoch was a Thursday; shift so weeks start on Monday (UTC).
local WEEK_OFFSET = DAY * 3

function Rotation.Day(now: number?): number
	return math.floor((now or os.time()) / DAY)
end

function Rotation.Week(now: number?): number
	return math.floor(((now or os.time()) + WEEK_OFFSET) / WEEK)
end

function Rotation.SecondsUntilNextDay(now: number?): number
	local t = now or os.time()
	return DAY - (t % DAY)
end

function Rotation.SecondsUntilNextWeek(now: number?): number
	local t = (now or os.time()) + WEEK_OFFSET
	return WEEK - (t % WEEK)
end

-- Small deterministic hash (FNV-1a style) for seeding.
function Rotation.Hash(...: any): number
	local h = 2166136261
	for _, part in { ... } do
		local text = tostring(part)
		for i = 1, #text do
			h = bit32.bxor(h, string.byte(text, i))
			h = (h * 16777619) % 4294967296
		end
	end
	return h
end

-- A small LCG so picks are identical on every machine (and in tests).
export type Rng = { Next: (Rng) -> number, Int: (Rng, number, number) -> number, Pick: (Rng, { any }) -> any }

function Rotation.Rng(seed: number): Rng
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	local rng = {}
	function rng.Next(_self): number
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
	function rng.Int(self, lo: number, hi: number): number
		return lo + math.floor(self:Next() * (hi - lo + 1))
	end
	function rng.Pick(self, list: { any }): any
		return list[self:Int(1, #list)]
	end
	return rng :: any
end

-- Pick `count` distinct entries from `list` using `seed`.
function Rotation.PickDistinct(list: { any }, count: number, seed: number): { any }
	local pool = table.clone(list)
	local rng = Rotation.Rng(seed)
	local result = {}
	while #result < count and #pool > 0 do
		local index = rng:Int(1, #pool)
		table.insert(result, table.remove(pool, index))
	end
	return result
end

return Rotation

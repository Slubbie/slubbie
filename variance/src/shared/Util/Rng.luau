-- Random number source used by the game core.
--
-- The core never calls Roblox's `Random` directly so it can run headless in tests.
-- Anything that exposes :NextNumber() and :NextInteger(min, max) works; on the
-- server we pass a real `Random` (PCG32, seeded from entropy the client never sees).
-- `Rng.pure(seed)` is a small xorshift generator for tests and simulations.

export type RngLike = {
	NextNumber: (self: any, min: number?, max: number?) -> number,
	NextInteger: (self: any, min: number, max: number) -> number,
}

local Rng = {}

local Pure = {}
Pure.__index = Pure

function Pure:NextNumber(min: number?, max: number?): number
	-- xorshift32
	local x = self._state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	if x == 0 then
		x = 0x9E3779B9
	end
	self._state = x
	local unit = x / 4294967296
	if min ~= nil and max ~= nil then
		return min + (max - min) * unit
	end
	return unit
end

function Pure:NextInteger(min: number, max: number): number
	if max < min then
		min, max = max, min
	end
	local span = max - min + 1
	local value = min + math.floor(self:NextNumber() * span)
	if value > max then
		value = max
	end
	return value
end

-- A deterministic generator (tests, simulations, replays).
function Rng.pure(seed: number?): RngLike
	local s = math.floor(math.abs(seed or 12345)) % 4294967296
	if s == 0 then
		s = 0x1234567
	end
	local self = setmetatable({ _state = s }, Pure)
	-- Warm up so nearby seeds diverge quickly.
	for _ = 1, 8 do
		self:NextNumber()
	end
	return (self :: any) :: RngLike
end

-- Returns a Roblox Random when available, otherwise a pure generator.
function Rng.new(seed: number?): RngLike
	local RandomClass: any = Random
	if RandomClass ~= nil then
		local ok, r = pcall(function()
			if seed then
				return RandomClass.new(seed)
			end
			return RandomClass.new()
		end)
		if ok and r then
			return r :: any
		end
	end
	return Rng.pure(seed or math.floor((os.clock() * 1e6) % 4294967295))
end

-- Fisher-Yates shuffle, in place.
function Rng.shuffle<T>(rng: RngLike, list: { T }): { T }
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

-- Picks a key from { key = weight } using the generator. Keys are sorted first so
-- the result only depends on the generator, never on table iteration order.
function Rng.weighted(rng: RngLike, weights: { [string]: number }): string?
	local keys = {}
	local total = 0
	for key, weight in weights do
		if weight > 0 then
			table.insert(keys, key)
			total += weight
		end
	end
	if total <= 0 then
		return nil
	end
	table.sort(keys)
	local roll = rng:NextNumber() * total
	for _, key in keys do
		roll -= weights[key]
		if roll <= 0 then
			return key
		end
	end
	return keys[#keys]
end

-- Standard normal sample (Box-Muller).
function Rng.gaussian(rng: RngLike): number
	local u1 = math.max(rng:NextNumber(), 1e-9)
	local u2 = rng:NextNumber()
	return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
end

return Rng

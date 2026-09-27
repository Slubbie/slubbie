-- Deterministic hashing and random helpers.
--
-- Hash() lets every server and client agree on the same "random" outcome for a
-- given input (weather for a time slot, market trend for an hour, forage spawns
-- for a day) without talking to each other. Anything that grants rewards still
-- rolls on the server with a normal Random.

local RNG = {}

-- 32-bit multiply without losing precision in doubles (products stay < 2^53).
local function imul(a: number, b: number): number
	local aLo = bit32.band(a, 0xFFFF)
	local aHi = bit32.rshift(a, 16)
	return bit32.band(aLo * b + bit32.lshift(bit32.band(aHi * b, 0xFFFF), 16), 0xFFFFFFFF)
end

local function mix(h: number, v: number): number
	-- FNV-1a style step followed by a murmur-like avalanche.
	h = bit32.bxor(h, bit32.band(v, 0xFFFFFFFF))
	h = imul(h, 16777619)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = imul(h, 0x5bd1e995)
	h = bit32.bxor(h, bit32.rshift(h, 15))
	return h
end

local function toInt(value: any): number
	if type(value) == "number" then
		return math.floor(value) % 4294967296
	elseif type(value) == "string" then
		local h = 2166136261
		for i = 1, #value do
			h = mix(h, string.byte(value, i))
		end
		return h
	elseif type(value) == "boolean" then
		return if value then 1 else 0
	end
	return 0
end

-- Stable hash of any mix of numbers/strings → integer in [0, 2^32).
function RNG.HashInt(...: any): number
	local h = 2166136261
	for i = 1, select("#", ...) do
		h = mix(h, toInt((select(i, ...))))
	end
	return h
end

-- Stable hash → float in [0, 1).
function RNG.Hash(...: any): number
	return RNG.HashInt(...) / 4294967296
end

-- Weighted pick from { [key] = weight } or an array of { weight = n, ... }.
-- `roll` is a number in [0,1): pass RNG.Hash(...) for deterministic picks or
-- Random:NextNumber() for server rolls. Keys are sorted so results are stable.
function RNG.WeightedKey(weights: { [any]: number }, roll: number): any
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
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	local target = roll * total
	for _, key in keys do
		target -= weights[key]
		if target < 0 then
			return key
		end
	end
	return keys[#keys]
end

function RNG.WeightedEntry<T>(entries: { T }, weightOf: (T) -> number, roll: number): T?
	local total = 0
	for _, entry in entries do
		total += math.max(0, weightOf(entry))
	end
	if total <= 0 then
		return nil
	end
	local target = roll * total
	for _, entry in entries do
		target -= math.max(0, weightOf(entry))
		if target < 0 then
			return entry
		end
	end
	return entries[#entries]
end

-- Approximately normal value (mean 0, sd 1) from a Random, via Box-Muller.
function RNG.Gaussian(random: Random): number
	local u1 = math.max(random:NextNumber(), 1e-9)
	local u2 = random:NextNumber()
	return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
end

-- Unique-ish id for saved objects (placed items, animals, mail).
local counter = 0
function RNG.Uid(prefix: string?): string
	counter = (counter + 1) % 1679616
	local timePart = string.format("%x", math.floor(os.time()) % 0xFFFFFF)
	local randPart = string.format("%x", math.random(0, 0xFFFFF))
	return (prefix or "") .. timePart .. randPart .. string.format("%x", counter)
end

return RNG

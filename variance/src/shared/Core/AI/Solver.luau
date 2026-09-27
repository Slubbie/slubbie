-- Win-probability solver for the surrogates.
--
-- W(c, h, a, b, t, s, tether) is the probability that "me" wins the current
-- Trial when the Arbiter holds c CHARGED and h HOLLOW unknown cells, I have a
-- Integrity and my opponent b, t says whose turn it is (0 = mine), s who started
-- this Load (the next Load starts with the other subject), and tether whether a
-- Tether is mirroring damage for the rest of this Load.
--
-- Both sides pick the better of "fire at self" and "fire at opponent" (the
-- opponent minimizes my value, optionally blended with a behavioural model of
-- how that opponent actually plays). When the Load runs dry, F(a, b, s) averages
-- W over every composition the current Trial's profile can deal. Every Load
-- removes at least one Integrity point, so the recursion always terminates.
--
-- Instruments are not modelled inside the recursion: Brain.luau evaluates them as
-- one- or two-step lookaheads on top of these exact values.

local Solver = {}
Solver.__index = Solver

export type Params = {
	Damage: number, -- damage of a CHARGED cell (base + modifiers)
	Surge: boolean, -- last cell of each Load deals +1
	Cells: { number }, -- {min, max} cells per Load for this Trial
	Charged: { number }, -- {min, max} CHARGED fraction
	OpponentSelfRate: ((p: number) -> number)?, -- behavioural model of the opponent
	ModelWeight: number?, -- 0 = assume a perfect opponent, 1 = trust the model fully
}

function Solver.new(params: Params)
	local self = setmetatable({}, Solver)
	self.params = params
	self.memo = {}
	self.fmemo = {}
	self.compositions = Solver.compositions(params.Cells, params.Charged)
	return self
end

-- Every (size, charged) the profile can deal, equally weighted per size.
function Solver.compositions(cells: { number }, charged: { number })
	local out = {}
	local sizes = cells[2] - cells[1] + 1
	for size = cells[1], cells[2] do
		local lo, hi
		if size <= 1 then
			lo, hi = 1, 1
		else
			lo = math.clamp(math.floor(size * charged[1] + 0.5), 1, size - 1)
			hi = math.clamp(math.floor(size * charged[2] + 0.5), 1, size - 1)
		end
		local options = hi - lo + 1
		for c = lo, hi do
			table.insert(out, { Size = size, Charged = c, Weight = 1 / (sizes * options) })
		end
	end
	return out
end

local function key(c, h, a, b, t, s, tether)
	a = math.clamp(a, -1, 12) + 1
	b = math.clamp(b, -1, 12) + 1
	return ((((((c * 17 + h) * 14 + a) * 14 + b) * 2 + t) * 2 + s) * 2) + (tether and 1 or 0)
end

local function terminal(a: number, b: number): number?
	if a <= 0 and b <= 0 then
		return 0.5
	elseif a <= 0 then
		return 0
	elseif b <= 0 then
		return 1
	end
	return nil
end

-- Value after the Load runs out: a fresh Load dealt by the profile.
function Solver:F(a: number, b: number, s: number): number
	local done = terminal(a, b)
	if done then
		return done
	end
	local k = (math.clamp(a, 0, 12) * 13 + math.clamp(b, 0, 12)) * 2 + s
	local cached = self.fmemo[k]
	if cached then
		return cached
	end
	local total = 0
	for _, comp in self.compositions do
		total += comp.Weight * self:W(comp.Charged, comp.Size - comp.Charged, a, b, s, s, false)
	end
	self.fmemo[k] = total
	return total
end

-- The two options for whoever holds the turn, as values for "me".
function Solver:options(c: number, h: number, a: number, b: number, t: number, s: number, tether: boolean): (number, number, number)
	local n = c + h
	local p = c / n
	local last = n == 1
	local dmg = self.params.Damage + ((self.params.Surge and last) and 1 or 0)
	local other = 1 - t
	local selfVal, oppVal = 0, 0
	-- Damage bookkeeping from the shooter's point of view.
	local function hit(shooterTakes: boolean)
		local na, nb = a, b
		local victimIsMe = (t == 0) == shooterTakes
		if victimIsMe then
			na -= dmg
			if tether then
				nb -= dmg
			end
		else
			nb -= dmg
			if tether then
				na -= dmg
			end
		end
		return na, nb
	end
	-- Fire at opponent.
	if c > 0 then
		local na, nb = hit(false)
		oppVal += p * self:W(c - 1, h, na, nb, other, s, tether)
	end
	if h > 0 then
		oppVal += (1 - p) * self:W(c, h - 1, a, b, other, s, tether)
	end
	-- Fire at self.
	if c > 0 then
		local na, nb = hit(true)
		selfVal += p * self:W(c - 1, h, na, nb, other, s, tether)
	end
	if h > 0 then
		selfVal += (1 - p) * self:W(c, h - 1, a, b, t, s, tether)
	end
	return selfVal, oppVal, p
end

function Solver:W(c: number, h: number, a: number, b: number, t: number, s: number, tether: boolean): number
	local done = terminal(a, b)
	if done then
		return done
	end
	if c + h == 0 then
		return self:F(a, b, 1 - s)
	end
	local k = key(c, h, a, b, t, s, tether)
	local cached = self.memo[k]
	if cached then
		return cached
	end
	local selfVal, oppVal, p = self:options(c, h, a, b, t, s, tether)
	local value
	if t == 0 then
		value = math.max(selfVal, oppVal)
	else
		local optimal = math.min(selfVal, oppVal)
		local model = self.params.OpponentSelfRate
		local weight = self.params.ModelWeight or 0
		if model and weight > 0 then
			local q = math.clamp(model(p), 0, 1)
			local modeled = q * selfVal + (1 - q) * oppVal
			value = optimal * (1 - weight) + modeled * weight
		else
			value = optimal
		end
	end
	self.memo[k] = value
	return value
end

-- Clears cached values (call when the opponent model changes meaningfully).
function Solver:reset()
	self.memo = {}
	self.fmemo = {}
end

return Solver

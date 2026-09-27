-- The belief model: what one viewer can legitimately know about the Arbiter's
-- remaining cells, and the exact probabilities that follow from it.
--
-- The same function answers "what is P(CHARGED)?" for the HUD's probability
-- readout, for every AI opponent, and for the post-match analysis. The AI is
-- handed exactly the belief a human in its seat would have, so it can never
-- cheat by reading the hidden sequence.
--
-- Model
--   Every cell in a pool (one Load, or one re-cast after a Scrambler) was drawn
--   from a public composition: PoolSize cells, PoolCharged of them CHARGED.
--   Each cell has an ORIGINAL type (hidden) and a public inversion Parity (an
--   Inverter flips parity; everyone sees that it happened). Its CURRENT type is
--   original XOR parity.
--   Cells removed from the pool (fired or ejected) are always revealed, so the
--   number of CHARGED originals that left the pool is public.
--   Unknown cells are exchangeable, so the unknown originals are a uniformly
--   random subset: P(unknown original is CHARGED) = R / U, where U is the number
--   of unknown cells and R the CHARGED originals not yet accounted for.

export type TrackCell = {
	Parity: number, -- 0 or 1 (inverted an odd number of times)
	Known: string?, -- "C" or "H": the CURRENT type, if this viewer knows it
}

export type Belief = {
	PoolSize: number,
	PoolCharged: number?, -- nil when the composition was hidden (Blind Load modifier)
	RemovedCharged: number, -- ORIGINAL types of cells removed from this pool
	RemovedHollow: number,
	Track: { TrackCell }, -- remaining cells; [1] is the loaded cell (fires next)
}

local Probability = {}

local function originalCharged(cell: TrackCell): boolean?
	if cell.Known == nil then
		return nil
	end
	local currentCharged = cell.Known == "C"
	if cell.Parity == 1 then
		return not currentCharged
	end
	return currentCharged
end
Probability.originalCharged = originalCharged

-- Unknown cell count and the CHARGED originals left among them.
function Probability.unknownStats(belief: Belief): (number, number?)
	local unknown = 0
	local knownOriginalCharged = 0
	for _, cell in belief.Track do
		local orig = originalCharged(cell)
		if orig == nil then
			unknown += 1
		elseif orig then
			knownOriginalCharged += 1
		end
	end
	if belief.PoolCharged == nil then
		return unknown, nil
	end
	local left = (belief.PoolCharged :: number) - belief.RemovedCharged - knownOriginalCharged
	return unknown, math.clamp(left, 0, unknown)
end

-- P(an unknown cell's ORIGINAL type is CHARGED).
function Probability.baseRate(belief: Belief): number
	local unknown, left = Probability.unknownStats(belief)
	if unknown == 0 then
		return 0
	end
	if left == nil then
		-- Blind composition: Laplace's rule of succession over everything seen.
		local seenCharged = belief.RemovedCharged
		local seen = belief.RemovedCharged + belief.RemovedHollow
		for _, cell in belief.Track do
			local orig = originalCharged(cell)
			if orig ~= nil then
				seen += 1
				if orig then
					seenCharged += 1
				end
			end
		end
		return (seenCharged + 1) / (seen + 2)
	end
	return (left :: number) / unknown
end

-- P(the cell at `index` is currently CHARGED).
function Probability.chargedAt(belief: Belief, index: number): number
	local cell = belief.Track[index]
	if cell == nil then
		return 0
	end
	if cell.Known ~= nil then
		return cell.Known == "C" and 1 or 0
	end
	local q = Probability.baseRate(belief)
	if cell.Parity == 1 then
		return 1 - q
	end
	return q
end

function Probability.current(belief: Belief): number
	return Probability.chargedAt(belief, 1)
end

function Probability.isCertain(p: number): boolean
	return p <= 1e-9 or p >= 1 - 1e-9
end

function Probability.remaining(belief: Belief): number
	return #belief.Track
end

-- Bounds and expectation of how many remaining cells are currently CHARGED.
-- Exact counts are shown whenever min == max; otherwise the HUD shows a range.
function Probability.range(belief: Belief): (number, number, number)
	local knownCharged = 0
	local u0, u1 = 0, 0 -- unknown cells with parity 0 / 1
	local expected = 0
	for i, cell in belief.Track do
		if cell.Known ~= nil then
			if cell.Known == "C" then
				knownCharged += 1
			end
		elseif cell.Parity == 1 then
			u1 += 1
		else
			u0 += 1
		end
		expected += Probability.chargedAt(belief, i)
	end
	local _, left = Probability.unknownStats(belief)
	if left == nil then
		return knownCharged, knownCharged + u0 + u1, expected
	end
	local r = left :: number
	-- k of the r CHARGED originals sit in inverted cells (becoming HOLLOW).
	local kMin = math.max(0, r - u0)
	local kMax = math.min(r, u1)
	local minCharged = knownCharged + r + u1 - 2 * kMax
	local maxCharged = knownCharged + r + u1 - 2 * kMin
	return minCharged, maxCharged, expected
end

function Probability.copy(belief: Belief): Belief
	local track = table.create(#belief.Track)
	for i, cell in belief.Track do
		track[i] = { Parity = cell.Parity, Known = cell.Known }
	end
	return {
		PoolSize = belief.PoolSize,
		PoolCharged = belief.PoolCharged,
		RemovedCharged = belief.RemovedCharged,
		RemovedHollow = belief.RemovedHollow,
		Track = track,
	}
end

-- A copy of the belief with the cell at `index` known to be CHARGED/HOLLOW.
function Probability.condition(belief: Belief, index: number, charged: boolean): Belief
	local copy = Probability.copy(belief)
	local cell = copy.Track[index]
	if cell then
		cell.Known = charged and "C" or "H"
	end
	return copy
end

-- Removes the cell at `index` (its type must be known: removed cells are revealed).
function Probability.remove(belief: Belief, index: number, charged: boolean): Belief
	local copy = Probability.condition(belief, index, charged)
	local cell = table.remove(copy.Track, index)
	if cell then
		if originalCharged(cell) then
			copy.RemovedCharged += 1
		else
			copy.RemovedHollow += 1
		end
	end
	return copy
end

-- Rotor: the loaded cell moves to position `span` (default 3); the rest shift forward.
function Probability.rotate(belief: Belief, span: number?): Belief
	local copy = Probability.copy(belief)
	local n = math.min(span or 3, #copy.Track)
	if n >= 2 then
		local first = table.remove(copy.Track, 1)
		table.insert(copy.Track, n, first)
	end
	return copy
end

-- Inverter: flips the loaded cell. Whoever knew it still knows it (flipped).
function Probability.invert(belief: Belief, index: number?): Belief
	local copy = Probability.copy(belief)
	local cell = copy.Track[index or 1]
	if cell then
		cell.Parity = 1 - cell.Parity
		if cell.Known == "C" then
			cell.Known = "H"
		elseif cell.Known == "H" then
			cell.Known = "C"
		end
	end
	return copy
end

-- A fresh belief for a brand-new pool (used by the AI to reason about re-casts).
function Probability.fresh(size: number, charged: number?): Belief
	local track = table.create(size)
	for i = 1, size do
		track[i] = { Parity = 0 }
	end
	return {
		PoolSize = size,
		PoolCharged = charged,
		RemovedCharged = 0,
		RemovedHollow = 0,
		Track = track,
	}
end

-- Expected CHARGED / HOLLOW counts among the cells after the loaded one, given
-- the loaded cell turns out `currentCharged`. Rounded for the AI's count-based solver.
function Probability.restCounts(belief: Belief, currentCharged: boolean): (number, number)
	local n = #belief.Track
	if n <= 1 then
		return 0, 0
	end
	local conditioned = Probability.remove(belief, 1, currentCharged)
	local expected = 0
	for i = 1, #conditioned.Track do
		expected += Probability.chargedAt(conditioned, i)
	end
	local c = math.clamp(math.floor(expected + 0.5), 0, n - 1)
	return c, (n - 1) - c
end

return Probability

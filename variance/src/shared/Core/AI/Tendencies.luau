-- A running model of how one opponent plays, built only from public events.
--
-- The surrogates use it two ways: Expert and the Proctor blend it into their
-- win-probability solver ("this subject fires at themselves 70% of the time
-- at even odds"), and the dialogue system uses it for pointed remarks.
-- Estimates are Beta-smoothed so a few decisions don't swing them wildly.

local Tendencies = {}
Tendencies.__index = Tendencies

-- Probability bins for the public P(CHARGED) at decision time.
local BIN_EDGES = { 0.25, 0.45, 0.55, 0.75 }

local function binOf(p: number): number
	for i, edge in BIN_EDGES do
		if p < edge then
			return i
		end
	end
	return #BIN_EDGES + 1
end

-- Prior: a sensible player self-targets when the odds favour HOLLOW.
local PRIOR_SELF = { 0.85, 0.6, 0.45, 0.25, 0.1 }
local PRIOR_WEIGHT = 3

function Tendencies.new()
	local bins = {}
	for i = 1, #BIN_EDGES + 1 do
		bins[i] = { Self = 0, Total = 0 }
	end
	return setmetatable({
		Bins = bins,
		Shots = 0,
		SelfShots = 0,
		Items = {},
		ItemsBeforeFire = 0,
		Hesitations = 0,
		SelfStreak = 0,
		MaxSelfStreak = 0,
		LastSequence = {},
	}, Tendencies)
end

function Tendencies:recordFire(publicP: number, selfShot: boolean, usedThisTurn: { string }?)
	local bin = self.Bins[binOf(publicP)]
	bin.Total += 1
	self.Shots += 1
	if selfShot then
		bin.Self += 1
		self.SelfShots += 1
		self.SelfStreak += 1
		self.MaxSelfStreak = math.max(self.MaxSelfStreak, self.SelfStreak)
	else
		self.SelfStreak = 0
	end
	if usedThisTurn and #usedThisTurn > 0 then
		self.ItemsBeforeFire += 1
		self.LastSequence = table.clone(usedThisTurn)
	end
end

function Tendencies:recordItem(id: string)
	self.Items[id] = (self.Items[id] or 0) + 1
end

function Tendencies:recordHesitation()
	self.Hesitations += 1
end

-- Estimated chance this opponent fires at themselves at public odds p.
function Tendencies:selfRate(p: number): number
	local i = binOf(p)
	local bin = self.Bins[i]
	return (bin.Self + PRIOR_SELF[i] * PRIOR_WEIGHT) / (bin.Total + PRIOR_WEIGHT)
end

-- How far this player's habits deviate from the prior (0 = textbook, 1 = very unusual).
function Tendencies:deviation(): number
	local total, weighted = 0, 0
	for i, bin in self.Bins do
		if bin.Total > 0 then
			local observed = bin.Self / bin.Total
			weighted += math.abs(observed - PRIOR_SELF[i]) * bin.Total
			total += bin.Total
		end
	end
	if total == 0 then
		return 0
	end
	return math.clamp(weighted / total, 0, 1)
end

function Tendencies:selfShotShare(): number
	if self.Shots == 0 then
		return 0
	end
	return self.SelfShots / self.Shots
end

function Tendencies:favouriteItem(): string?
	local best, count = nil, 0
	for id, n in self.Items do
		if n > count or (n == count and best and id < best) then
			best, count = id, n
		end
	end
	return best
end

-- A plain summary the Proctor can quote back at the player.
function Tendencies:summary()
	local midBin = self.Bins[3]
	local midRate = midBin.Total > 0 and midBin.Self / midBin.Total or nil
	return {
		Shots = self.Shots,
		SelfShare = self:selfShotShare(),
		EvenOddsSelfRate = midRate,
		EvenOddsSamples = midBin.Total,
		Favourite = self:favouriteItem(),
		Deviation = self:deviation(),
		MaxSelfStreak = self.MaxSelfStreak,
		Hesitations = self.Hesitations,
	}
end

return Tendencies

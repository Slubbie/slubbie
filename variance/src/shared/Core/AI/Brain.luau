-- The surrogate decision maker: a utility scorer over every legal action.
--
-- Each action is valued as "probability I win this Trial afterwards", using the
-- exact solver in Solver.luau for shots and simulated outcomes for instruments:
--
--   Fire (self / opponent)   expectation over CHARGED/HOLLOW of the solver's W
--                            after damage, Dampeners, Capacitor, Surge, Tether,
--                            Overclock and Clamp are applied to the first shot.
--   Instruments              simulate the instrument's possible outcomes on the
--                            belief, then take the best follow-up (a shot, or on
--                            Expert another instrument). Lens and Sonar therefore
--                            earn exactly their value of information.
--
-- On top of that sit a conservation cost (the value of keeping an instrument for
-- later), personality biases, a difficulty-dependent amount of noise and
-- forgetfulness, and softmax sampling so play stays believable. The brain only
-- ever sees Engine.aiView(): the same information a human in its seat would have.

local Probability = require(script.Parent.Parent.Probability)
local Instruments = require(script.Parent.Parent.Instruments)
local Solver = require(script.Parent.Solver)
local Difficulty = require(script.Parent.Difficulty)
local Personalities = require(script.Parent.Personalities)
local Tendencies = require(script.Parent.Tendencies)

local Brain = {}
Brain.__index = Brain

-- Rough worth of one random instrument draw (Power Tap), in win probability.
local AVERAGE_DRAW_VALUE = 0.025
-- Option value of keeping the turn after a HOLLOW self-shot (see decide()).
local TURN_KEEP_VALUE = 0.008
local TURN_KEEP_PER_ITEM = 0.003

export type BrainOptions = {
	Personality: string?,
	Difficulty: any, -- a Difficulty tier table
	Rng: any,
	Tendencies: any?, -- Tendencies of the opponent(s) it faces
}

function Brain.new(opts: BrainOptions)
	local self = setmetatable({}, Brain)
	self.personality = Personalities.get(opts.Personality)
	self.tier = opts.Difficulty or Difficulty.get("Standard")
	self.rng = opts.Rng
	self.tendencies = opts.Tendencies or Tendencies.new()
	self.solvers = {}
	self.memory = { length = -1, lapses = {} }
	self.hints = {}
	self.opponentTurnUsed = {}
	return self
end

function Brain:setDifficulty(tier)
	self.tier = tier
	self.solvers = {}
end

local function gaussian(rng): number
	local u1 = math.max(rng:NextNumber(), 1e-9)
	local u2 = rng:NextNumber()
	return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
end

---------------------------------------------------------------------------
-- Observation (called by the server's AI driver with public events only)
---------------------------------------------------------------------------

local function shiftHints(hints)
	table.remove(hints, 1)
end

-- Tracks public events to (a) keep inference hints aligned with the cylinder and
-- (b) read the opponent's instrument sequences.
function Brain:observe(event, mySubjectId: number)
	local kind = event.Type
	local data = event.Public
	if kind == "LoadStart" or kind == "LoadEnd" or kind == "TrialStart" or kind == "SuddenDeath" then
		self.hints = {}
		self.opponentTurnUsed = {}
	elseif kind == "TurnStart" then
		self.opponentTurnUsed = {}
	elseif kind == "FireResult" then
		shiftHints(self.hints)
		self.opponentTurnUsed = {}
	elseif kind == "InstrumentUsed" then
		local id = data.Id
		local isOpponent = data.Actor ~= mySubjectId
		if isOpponent then
			self.tendencies:recordItem(id)
		end
		if id == "Ejector" then
			shiftHints(self.hints)
		elseif id == "Inverter" then
			if self.hints[1] then
				self.hints[1] = 1 - self.hints[1]
			end
		elseif id == "Scrambler" then
			self.hints = {}
		elseif id == "Rotor" then
			-- Reading a tell: an opponent who looks through a Lens and then rotates
			-- the loaded cell away most likely saw it was CHARGED.
			if isOpponent and self.tier.Inference and table.find(self.opponentTurnUsed, "Lens") then
				if self.hints[1] == nil then
					self.hints[1] = 0.8
				end
			end
			local span = (data.Outcome and data.Outcome.Span) or 3
			if span >= 2 then
				local first = self.hints[1]
				table.remove(self.hints, 1)
				-- Keep the array dense so indices stay aligned.
				for i = 1, span - 1 do
					if self.hints[i] == nil then
						self.hints[i] = false
					end
				end
				table.insert(self.hints, span, first == nil and false or first)
			end
		end
		if isOpponent then
			table.insert(self.opponentTurnUsed, id)
		end
	end
end

---------------------------------------------------------------------------
-- Belief preparation: memory lapses, deduction depth, inference and noise
---------------------------------------------------------------------------

function Brain:prepareBelief(view)
	local belief = Probability.copy(view.Belief)
	local tier = self.tier
	local track = belief.Track

	-- Memory lapses are rolled once per turn for observations made before it.
	local startOfTurn = #view.Used == 0
	if startOfTurn or self.memory.length ~= #track then
		self.memory = { length = #track, lapses = {} }
		if startOfTurn and tier.Retention < 1 then
			for i, cell in track do
				if cell.Known and self.rng:NextNumber() > tier.Retention then
					self.memory.lapses[i] = cell.Known
				end
			end
		end
	end
	for i, known in self.memory.lapses do
		if track[i] and track[i].Known == known then
			track[i].Known = nil
		end
	end

	-- Standard reasons from the counts and the loaded cell only.
	if not tier.UseFutureKnowledge then
		for i = 2, #track do
			track[i].Known = nil
		end
	end
	return belief
end

function Brain:estimate(belief): (number, number)
	local p = Probability.current(belief)
	local truth = p
	local hint = self.hints[1]
	if self.tier.Inference and type(hint) == "number" and belief.Track[1] and belief.Track[1].Known == nil then
		p = 0.5 * p + 0.5 * hint
	end
	if not Probability.isCertain(p) and self.tier.Noise > 0 then
		p = math.clamp(p + gaussian(self.rng) * self.tier.Noise, 0.01, 0.99)
	end
	return p, truth
end

---------------------------------------------------------------------------
-- Solver access
---------------------------------------------------------------------------

function Brain:solverFor(view)
	local profile = view.Profile
	local cells, charged = profile.Cells, profile.Charged
	if view.SuddenDeath then
		cells, charged = { 3, 3 }, { 1 / 3, 1 / 3 }
	end
	local weight = self.tier.ModelWeight + (self.tier.ModelWeight > 0 and self.personality.ModelBoost or 0)
	local modelShots = weight > 0 and self.tendencies.Shots or 0
	local key = table.concat({
		view.Trial,
		view.CellDamage,
		tostring(view.Surge),
		cells[1],
		cells[2],
		charged[1],
		charged[2],
		modelShots,
	}, ":")
	local solver = self.solvers[key]
	if solver == nil then
		local tendencies = self.tendencies
		solver = Solver.new({
			Damage = view.CellDamage,
			Surge = view.Surge,
			Cells = cells,
			Charged = charged,
			OpponentSelfRate = if weight > 0
				then function(p)
					return tendencies:selfRate(p)
				end
				else nil,
			ModelWeight = math.clamp(weight, 0, 0.9),
		})
		self.solvers = { [key] = solver } -- keep only the current one
	end
	return solver
end

---------------------------------------------------------------------------
-- Valuation
---------------------------------------------------------------------------

local function makeContext(view, opponent)
	local me = view.Me
	local inventory = table.clone(me.Instruments)
	return {
		a = me.Integrity,
		b = opponent.Integrity,
		maxA = me.MaxIntegrity,
		cap = me.Effects.Capacitor,
		myDamp = me.Effects.Dampener,
		oppDamp = opponent.Effects.Dampener,
		over = me.Effects.Overclock,
		oppClamped = opponent.Effects.Clamped,
		oppImmune = opponent.Effects.ClampImmune,
		tether = view.Tether,
		s = (view.LoadStarter == me.Id) and 0 or 1,
		inventory = inventory,
		used = table.clone(view.UseCounts),
		capacity = view.Capacity,
		draws = view.Draws,
	}
end

local function copyContext(ctx)
	local c = table.clone(ctx)
	c.inventory = table.clone(ctx.inventory)
	c.used = table.clone(ctx.used)
	return c
end

-- Values of firing at self / at the opponent, for win probability of "me".
function Brain:fireValues(solver, belief, ctx, pOverride: number?): (number, number)
	local n = #belief.Track
	if n == 0 then
		local v = solver:F(ctx.a, ctx.b, 1 - ctx.s)
		return v, v
	end
	local p = pOverride or Probability.current(belief)
	local surgeHit = solver.params.Surge and n == 1
	local d = solver.params.Damage * (ctx.cap and 2 or 1) + (surgeHit and 1 or 0)
	local passTo = (ctx.over or ctx.oppClamped) and 0 or 1
	local cC, hC = Probability.restCounts(belief, true)
	local cH, hH = Probability.restCounts(belief, false)
	local dmgToMe = math.max(0, d - (ctx.myDamp and 1 or 0))
	local dmgToOpp = math.max(0, d - (ctx.oppDamp and 1 or 0))

	-- At the opponent.
	local oppA = ctx.tether and (ctx.a - dmgToMe) or ctx.a
	local vOppC = solver:W(cC, hC, oppA, ctx.b - dmgToOpp, passTo, ctx.s, ctx.tether)
	local vOppH = solver:W(cH, hH, ctx.a, ctx.b, passTo, ctx.s, ctx.tether)
	local vOpp = p * vOppC + (1 - p) * vOppH

	-- At myself: a HOLLOW keeps the turn.
	local selfB = ctx.tether and (ctx.b - dmgToOpp) or ctx.b
	local vSelfC = solver:W(cC, hC, ctx.a - dmgToMe, selfB, passTo, ctx.s, ctx.tether)
	local vSelfH = solver:W(cH, hH, ctx.a, ctx.b, 0, ctx.s, ctx.tether)
	local vSelf = p * vSelfC + (1 - p) * vSelfH
	return vSelf, vOpp
end

-- Whether an instrument could be used in a simulated state.
local function simCanUse(id: string, belief, ctx): boolean
	local def = Instruments.get(id)
	if def == nil then
		return false
	end
	if (ctx.used[id] or 0) >= def.PerTurnLimit then
		return false
	end
	local track = belief.Track
	local n = #track
	if id == "Lens" then
		return n >= 1 and track[1].Known == nil
	elseif id == "Sonar" then
		for i = 2, n do
			if track[i].Known == nil then
				return true
			end
		end
		return false
	elseif id == "Ejector" or id == "Inverter" then
		return n >= 1
	elseif id == "Rotor" or id == "Scrambler" then
		return n >= 2
	elseif id == "Suture" then
		return ctx.a < ctx.maxA
	elseif id == "Capacitor" then
		return not ctx.cap
	elseif id == "Clamp" then
		return not ctx.oppClamped and not ctx.oppImmune
	elseif id == "Dampener" then
		return not ctx.myDamp
	elseif id == "Overclock" then
		return not ctx.over
	elseif id == "PowerTap" then
		return ctx.a >= 2
	elseif id == "Tether" then
		return not ctx.tether
	end
	return true
end

-- Possible outcomes of using an instrument: { {w, belief, ctx, terminal?} }
function Brain:simulate(id: string, belief, ctx, solver)
	local out = {}
	local n = #belief.Track
	local function consumed()
		local c = copyContext(ctx)
		local index = table.find(c.inventory, id)
		if index then
			table.remove(c.inventory, index)
		end
		c.used[id] = (c.used[id] or 0) + 1
		return c
	end
	if id == "Lens" then
		local p = Probability.current(belief)
		local c = consumed()
		if p > 0 then
			table.insert(out, { w = p, belief = Probability.condition(belief, 1, true), ctx = c })
		end
		if p < 1 then
			table.insert(out, { w = 1 - p, belief = Probability.condition(belief, 1, false), ctx = c })
		end
	elseif id == "Sonar" then
		local unknown = {}
		for i = 2, n do
			if belief.Track[i].Known == nil then
				table.insert(unknown, i)
			end
		end
		local c = consumed()
		for _, i in unknown do
			local pk = Probability.chargedAt(belief, i)
			local w = 1 / #unknown
			if pk > 0 then
				table.insert(out, { w = w * pk, belief = Probability.condition(belief, i, true), ctx = c })
			end
			if pk < 1 then
				table.insert(out, { w = w * (1 - pk), belief = Probability.condition(belief, i, false), ctx = c })
			end
		end
	elseif id == "Ejector" then
		local p = Probability.current(belief)
		local c = consumed()
		for _, charged in { true, false } do
			local w = charged and p or (1 - p)
			if w > 0 then
				local nb = Probability.remove(belief, 1, charged)
				if #nb.Track == 0 then
					table.insert(out, { w = w, terminal = solver:F(ctx.a, ctx.b, 1 - ctx.s) })
				else
					table.insert(out, { w = w, belief = nb, ctx = c })
				end
			end
		end
	elseif id == "Inverter" then
		table.insert(out, { w = 1, belief = Probability.invert(belief, 1), ctx = consumed() })
	elseif id == "Rotor" then
		table.insert(out, { w = 1, belief = Probability.rotate(belief, 3), ctx = consumed() })
	elseif id == "Suture" then
		local c = consumed()
		c.a = math.min(c.maxA, c.a + 1)
		table.insert(out, { w = 1, belief = belief, ctx = c })
	elseif id == "Capacitor" then
		local c = consumed()
		c.cap = true
		table.insert(out, { w = 1, belief = belief, ctx = c })
	elseif id == "Clamp" then
		local c = consumed()
		c.oppClamped = true
		table.insert(out, { w = 1, belief = belief, ctx = c })
	elseif id == "Dampener" then
		local c = consumed()
		c.myDamp = true
		table.insert(out, { w = 1, belief = belief, ctx = c })
	elseif id == "Overclock" then
		local c = consumed()
		c.over = true
		table.insert(out, { w = 1, belief = belief, ctx = c })
	elseif id == "Serum" then
		local good = consumed()
		good.a = math.min(good.maxA, good.a + 2)
		table.insert(out, { w = 0.6, belief = belief, ctx = good })
		local bad = consumed()
		bad.a -= 1
		if bad.tether then
			bad.b -= 1
		end
		if bad.a <= 0 or bad.b <= 0 then
			local v = (bad.a <= 0 and bad.b <= 0) and 0.5 or (bad.a <= 0 and 0 or 1)
			table.insert(out, { w = 0.4, terminal = v })
		else
			table.insert(out, { w = 0.4, belief = belief, ctx = bad })
		end
	elseif id == "PowerTap" then
		local c = consumed()
		c.a -= 1
		if c.tether then
			c.b -= 1
		end
		local room = math.max(0, c.capacity - #c.inventory)
		c.bonus = (c.bonus or 0) + AVERAGE_DRAW_VALUE * math.min(2, room)
		if c.b <= 0 then
			table.insert(out, { w = 1, terminal = 1 })
		else
			table.insert(out, { w = 1, belief = belief, ctx = c })
		end
	elseif id == "Tether" then
		local c = consumed()
		c.tether = true
		table.insert(out, { w = 1, belief = belief, ctx = c })
	elseif id == "Scrambler" then
		local c = consumed()
		local comps = Solver.compositions({ n, n }, solver.params.Charged)
		for _, comp in comps do
			table.insert(out, { w = comp.Weight, belief = Probability.fresh(n, comp.Charged), ctx = c })
		end
	end
	return out
end

function Brain:holdValue(id: string, ctx): number
	local def = Instruments.get(id)
	if def == nil then
		return 0
	end
	local hold = def.HoldValue * self.tier.HoldScale * self.personality.Conservation
	if self.personality.Info > 0.5 and def.Category == "Information" then
		hold *= 0.6
	end
	-- Use it or lose it: overflow at the next Load, or a Trial about to end.
	local overflow = (#ctx.inventory + ctx.draws) - ctx.capacity
	if overflow > 0 then
		hold *= math.clamp(1 - overflow / math.max(ctx.draws, 1), 0, 1)
	end
	hold *= math.clamp((math.min(ctx.a, ctx.b) - 1) / 2, 0.25, 1)
	return hold
end

-- Personality-flavoured adjustment for an instrument, in win-probability units.
function Brain:itemBias(id: string): number
	local def = Instruments.get(id)
	if def == nil then
		return 0
	end
	local p = self.personality
	local bias = p.Affinity[id] or 0
	local cat = def.Category
	if cat == "Offense" or cat == "Tempo" or cat == "Control" then
		bias += p.Aggression * 0.006
	elseif cat == "Defense" or cat == "Recovery" then
		bias += p.Caution * 0.006
	elseif cat == "HighRisk" then
		bias += p.Risk * 0.012
	end
	return bias
end

-- Best value reachable from a state: a shot, or (depth > 0) another instrument first.
function Brain:bestAfter(solver, belief, ctx, depth: number): number
	local vSelf, vOpp = self:fireValues(solver, belief, ctx, nil)
	local best = math.max(vSelf, vOpp)
	if depth > 0 then
		local seen = {}
		for _, id in ctx.inventory do
			if not seen[id] and simCanUse(id, belief, ctx) then
				seen[id] = true
				local v = self:instrumentValue(solver, id, belief, ctx, depth - 1) - self:holdValue(id, ctx)
				if v > best then
					best = v
				end
			end
		end
	end
	return best + (ctx.bonus or 0)
end

function Brain:instrumentValue(solver, id: string, belief, ctx, depth: number): number
	local total = 0
	for _, outcome in self:simulate(id, belief, ctx, solver) do
		if outcome.terminal ~= nil then
			total += outcome.w * outcome.terminal
		else
			total += outcome.w * self:bestAfter(solver, outcome.belief, outcome.ctx, depth)
		end
	end
	return total
end

---------------------------------------------------------------------------
-- Choice
---------------------------------------------------------------------------

function Brain:choose(candidates)
	table.sort(candidates, function(x, y)
		return x.Score > y.Score
	end)
	local tier = self.tier
	local temperature = math.max(tier.Temperature * self.personality.Temperature, 1e-5)
	if #candidates > 1 and self.rng:NextNumber() < tier.Blunder then
		return candidates[self.rng:NextInteger(1, math.min(3, #candidates))], "blunder"
	end
	local top = candidates[1].Score
	local weights, total = {}, 0
	for i, c in candidates do
		local w = math.exp((c.Score - top) / temperature)
		weights[i] = w
		total += w
	end
	local roll = self.rng:NextNumber() * total
	for i, c in candidates do
		roll -= weights[i]
		if roll <= 0 then
			return c, i == 1 and "best" or "sampled"
		end
	end
	return candidates[1], "best"
end

-- Casual play: instinct over arithmetic.
function Brain:gut(view, belief)
	local me = view.Me
	local p = Probability.current(belief)
	local noisy = math.clamp(p + gaussian(self.rng) * self.tier.Noise * (Probability.isCertain(p) and 0.3 or 1), 0, 1)
	local usedCount = 0
	for _, n in view.UseCounts do
		usedCount += n
	end
	local usable = {}
	for _, action in view.Legal do
		if action.Kind == "Use" and action.Ok then
			table.insert(usable, action)
		end
	end
	if #usable > 0 and usedCount < 2 then
		for _, action in usable do
			if action.Id == "Suture" and me.Integrity < me.MaxIntegrity and self.rng:NextNumber() < 0.7 then
				return { Kind = "Use", Slot = action.Slot, Target = action.Target }, { P = noisy, Reason = "gut-heal" }
			end
		end
		if self.rng:NextNumber() < self.tier.ItemChance then
			local action = usable[self.rng:NextInteger(1, #usable)]
			return { Kind = "Use", Slot = action.Slot, Target = action.Target }, { P = noisy, Reason = "gut-item" }
		end
	end
	local opponents = view.Opponents
	local target = opponents[self.rng:NextInteger(1, #opponents)]
	local atOpponent = noisy >= 0.5
	if self.rng:NextNumber() < self.tier.Blunder then
		atOpponent = not atOpponent
	end
	if atOpponent then
		return { Kind = "Fire", Target = target.Id }, { P = noisy, Reason = "gut-fire" }
	end
	return { Kind = "Fire", Target = me.Id }, { P = noisy, Reason = "gut-self" }
end

-- Standard play: "basic probability reasoning". It reads the odds correctly from
-- the counts and anything it sees in the loaded cell, and follows sensible
-- rules of thumb for instruments, but it never looks ahead: it doesn't weigh
-- turn economy, lethal lines, health disparity or what information is worth.
function Brain:heuristic(view, belief)
	local me = view.Me
	local p = Probability.current(belief)
	local noisy = p
	if not Probability.isCertain(p) then
		noisy = math.clamp(p + gaussian(self.rng) * self.tier.Noise, 0.01, 0.99)
	end
	local opponents = view.Opponents
	local target = opponents[1]
	for _, o in opponents do
		if o.Integrity < target.Integrity then
			target = o
		end
	end
	local n = #belief.Track
	local known = belief.Track[1] and belief.Track[1].Known
	local usable = {}
	for _, action in view.Legal do
		if action.Kind == "Use" and action.Ok and (action.Target == nil or action.Target == target.Id) then
			usable[action.Id] = usable[action.Id] or action
		end
	end
	local function use(id: string, reason: string)
		local action = usable[id]
		return { Kind = "Use", Slot = action.Slot, Target = action.Target }, { P = noisy, Reason = reason, Margin = 0.1 }
	end
	-- Rules of thumb, in priority order.
	if usable.Suture and me.Integrity < me.MaxIntegrity then
		return use("Suture", "rule-heal")
	end
	if usable.Serum and me.Integrity <= me.MaxIntegrity - 2 and me.Integrity > 1 then
		return use("Serum", "rule-serum")
	end
	if usable.Lens and known == nil and noisy > 0.3 and noisy < 0.7 then
		return use("Lens", "rule-lens")
	end
	if usable.Inverter and known == "H" then
		return use("Inverter", "rule-invert")
	end
	if usable.Capacitor and noisy >= 0.75 then
		return use("Capacitor", "rule-capacitor")
	end
	if usable.Overclock and noisy >= 0.7 then
		return use("Overclock", "rule-overclock")
	end
	if usable.Dampener and noisy >= 0.5 then
		return use("Dampener", "rule-dampener")
	end
	if usable.Clamp and n >= 3 and self.rng:NextNumber() < 0.5 then
		return use("Clamp", "rule-clamp")
	end
	if usable.Sonar and n >= 3 and noisy > 0.3 and noisy < 0.7 then
		return use("Sonar", "rule-sonar")
	end
	if usable.Ejector and noisy > 0.6 and me.Integrity <= 2 then
		return use("Ejector", "rule-eject")
	end
	if usable.Tether and me.Integrity >= target.Integrity + 2 then
		return use("Tether", "rule-tether")
	end
	if usable.PowerTap and me.Integrity >= 3 and #me.Instruments <= view.Capacity - 2 then
		return use("PowerTap", "rule-powertap")
	end
	local atOpponent = noisy >= 0.5
	if self.rng:NextNumber() < self.tier.Blunder then
		atOpponent = not atOpponent
	end
	if atOpponent then
		return { Kind = "Fire", Target = target.Id }, { P = noisy, Reason = "rule-fire", Margin = math.abs(noisy - 0.5) }
	end
	return { Kind = "Fire", Target = me.Id }, { P = noisy, Reason = "rule-self", Margin = math.abs(noisy - 0.5) }
end

-- Decides the next action. Returns (action, info) where info carries the scored
-- candidates for the debug overlay and the decision margin (used for think time).
function Brain:decide(view)
	local belief = self:prepareBelief(view)
	if self.tier.Mode == "Gut" then
		local action, info = self:gut(view, belief)
		info.Margin = 0.5
		return action, info
	elseif self.tier.Mode == "Heuristic" then
		return self:heuristic(view, belief)
	end

	local me = view.Me
	local p, truth = self:estimate(belief)
	local personality = self.personality
	local solver = self:solverFor(view)
	local candidates = {}
	local legalUse = {}
	for _, action in view.Legal do
		if action.Kind == "Use" and action.Ok then
			table.insert(legalUse, action)
		end
	end

	for _, opponent in view.Opponents do
		local ctx = makeContext(view, opponent)
		local vSelf, vOpp = self:fireValues(solver, belief, ctx, p)
		local spread = math.sqrt(math.max(p * (1 - p), 0))
		-- Keeping the turn has option value the solver doesn't model: another chance to
		-- use instruments before the opponent can. Worth more with a fuller tray.
		local keepValue = (TURN_KEEP_VALUE + TURN_KEEP_PER_ITEM * #me.Instruments) * (1 - p)
		local selfScore = vSelf - personality.Caution * 0.03 * p + personality.Risk * 0.04 * spread + keepValue
		local oppScore = vOpp + personality.Aggression * 0.03 * p
		table.insert(candidates, {
			Action = { Kind = "Fire", Target = me.Id },
			Score = selfScore,
			Value = vSelf,
			Label = "Fire: self",
		})
		table.insert(candidates, {
			Action = { Kind = "Fire", Target = opponent.Id },
			Score = oppScore,
			Value = vOpp,
			Label = "Fire: " .. opponent.Name,
		})

		local baseline = math.max(vSelf, vOpp)
		local seen = {}
		for _, action in legalUse do
			local id = action.Id
			local keyed = id .. ":" .. tostring(action.Target)
			local relevantTarget = action.Target == nil or action.Target == opponent.Id
			if not seen[keyed] and relevantTarget then
				seen[keyed] = true
				local value
				local def = Instruments.get(id)
				if def and def.Category == "Information" and not self.tier.InfoValue then
					-- Standard: glance through a Lens only when the odds look even.
					if id == "Lens" and p > 0.33 and p < 0.67 then
						value = baseline + 0.02
					else
						value = baseline - 0.01
					end
				else
					value = self:instrumentValue(solver, id, belief, ctx, math.max(self.tier.Depth - 1, 0))
					if def and def.Category == "Information" then
						value = baseline + (value - baseline) * (1 + personality.Info)
					end
				end
				local score = value - self:holdValue(id, ctx) + self:itemBias(id)
				table.insert(candidates, {
					Action = { Kind = "Use", Slot = action.Slot, Target = action.Target },
					Score = score,
					Value = value,
					Label = "Use: " .. id,
				})
			end
		end
	end

	local chosen, how = self:choose(candidates)
	local second = candidates[2] and candidates[2].Score or candidates[1].Score
	local scores = {}
	for i = 1, math.min(6, #candidates) do
		local c = candidates[i]
		table.insert(scores, { Label = c.Label, Score = c.Score, Value = c.Value })
	end
	return chosen.Action,
		{
			P = p,
			TrueP = truth,
			Margin = math.abs(candidates[1].Score - second),
			Scores = scores,
			Reason = how,
			Chosen = chosen.Label,
		}
end

-- Seconds to "think" before acting: longer on close calls, shorter when obvious.
function Brain:thinkTime(info): number
	local range = self.tier.Think
	local base = range[1] + (range[2] - range[1]) * self.rng:NextNumber()
	local margin = info and info.Margin or 0.5
	if margin < 0.02 then
		base += 0.9
	elseif margin > 0.2 then
		base *= 0.75
	end
	return base
end

return Brain

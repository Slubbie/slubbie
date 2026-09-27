-- Unit tests for the pure game core: probability model, engine rules,
-- instruments, and edge cases called out in the design (double collapse,
-- over-healing, inventory overflow, stale/duplicate actions, forfeits).

return function(H)
	local Probability = H.require("Core/Probability")
	local Engine = H.require("Core/Engine")
	local Rules = H.require("Core/Rules")
	local Rng = H.require("Util/Rng")
	local Instruments = H.require("Core/Instruments")

	local function belief(poolSize, poolCharged, track, removedC, removedH)
		return {
			PoolSize = poolSize,
			PoolCharged = poolCharged,
			RemovedCharged = removedC or 0,
			RemovedHollow = removedH or 0,
			Track = track,
		}
	end
	local function cells(n)
		local t = {}
		for i = 1, n do
			t[i] = { Parity = 0 }
		end
		return t
	end

	H.test("probability: fresh load uses the announced ratio", function()
		local b = belief(5, 2, cells(5))
		H.near(Probability.current(b), 0.4)
		local lo, hi, exp = Probability.range(b)
		H.eq(lo, 2)
		H.eq(hi, 2)
		H.near(exp, 2)
	end)

	H.test("probability: conditional on a known later cell", function()
		local track = cells(4)
		track[3].Known = "C"
		-- 2 CHARGED of 4, one known CHARGED at #3 -> 1 CHARGED among 3 unknown.
		H.near(Probability.current(belief(4, 2, track)), 1 / 3)
	end)

	H.test("probability: removed cells update the odds", function()
		-- 3 CHARGED of 5, two CHARGED already fired -> 1 of 3 left.
		H.near(Probability.current(belief(5, 3, cells(3), 2, 0)), 1 / 3)
	end)

	H.test("probability: inverted unknown cell flips its own odds only", function()
		local b = Probability.invert(belief(4, 1, cells(4)), 1)
		H.near(Probability.chargedAt(b, 1), 0.75)
		H.near(Probability.chargedAt(b, 2), 0.25)
		local lo, hi = Probability.range(b)
		H.eq(lo, 0, "min charged")
		H.eq(hi, 2, "max charged")
	end)

	H.test("probability: inverting a known cell keeps it known", function()
		local track = cells(3)
		track[1].Known = "H"
		local b = Probability.invert(belief(3, 1, track), 1)
		H.eq(b.Track[1].Known, "C")
		H.near(Probability.chargedAt(b, 2), 0.5) -- original of #1 was HOLLOW -> 1 C among 2
	end)

	H.test("probability: removing an inverted cell counts its ORIGINAL type", function()
		local b = Probability.invert(belief(3, 1, cells(3)), 1)
		b = Probability.remove(b, 1, true) -- fired CHARGED, so it was HOLLOW originally
		H.eq(b.RemovedHollow, 1)
		H.eq(b.RemovedCharged, 0)
		H.near(Probability.current(b), 0.5)
	end)

	H.test("probability: rotor moves knowledge with the cell", function()
		local track = cells(4)
		track[1].Known = "C"
		local b = Probability.rotate(belief(4, 2, track), 3)
		H.eq(b.Track[3].Known, "C")
		H.near(Probability.current(b), 1 / 3)
	end)

	H.test("probability: blind load uses rule of succession", function()
		local b = belief(4, nil, cells(2), 1, 1)
		H.near(Probability.current(b), 0.5)
	end)

	-- Engine helpers ---------------------------------------------------------

	local function newMatch(modeId, opts)
		opts = opts or {}
		local rules = Rules.build(modeId or "Standard", opts.Custom, opts.Overrides)
		local state = Engine.new({
			MatchId = "test",
			Rules = rules,
			Rng = Rng.pure(opts.Seed or 7),
			Subjects = opts.Subjects or { { Name = "A" }, { Name = "B" } },
		})
		return state
	end

	local function advanceUntilInput(state, limit)
		local all = {}
		for _ = 1, limit or 50 do
			if state.Phase == Engine.Phase.AwaitAction or state.Phase == Engine.Phase.Ended then
				break
			end
			for _, e in Engine.advance(state) do
				table.insert(all, e)
			end
		end
		return all
	end

	local function find(events, kind)
		for _, e in events do
			if e.Type == kind then
				return e
			end
		end
		return nil
	end

	H.test("engine: match starts and awaits the first subject", function()
		local state = newMatch("Standard")
		local events = advanceUntilInput(state)
		H.eq(state.Phase, "AwaitAction")
		H.truthy(find(events, "MatchStart"))
		H.truthy(find(events, "TrialStart"))
		local load = find(events, "LoadStart")
		H.truthy(load)
		H.eq(load.Public.PoolSize, #state.Load.Cells)
		H.eq(state.Subjects[1].Integrity, 2)
	end)

	H.test("engine: public payloads never contain the sequence", function()
		local state = newMatch("Standard", { Overrides = { PrecisionReveal = 1 } })
		local events = advanceUntilInput(state)
		local load = find(events, "LoadStart")
		for _, cell in load.Public.Belief.Track do
			H.eq(cell.Known, nil, "public belief must not know cells")
		end
		-- Private precision reveal only for its owner.
		H.truthy(load.Private[1].Reveal and #load.Private[1].Reveal == 1)
	end)

	H.test("engine: self-shot on HOLLOW keeps the turn, CHARGED passes it", function()
		local state = newMatch("Standard", { Overrides = { Forced = { Loads = { "HCC" } } } })
		advanceUntilInput(state)
		local owner = state.Turn.Owner
		local ok, _, events = Engine.act(state, owner, { Kind = "Fire", Target = owner }, state.Turn.Token)
		H.truthy(ok)
		H.eq(find(events, "FireResult").Public.Kept, true)
		H.eq(state.Turn.Owner, owner)
		H.eq(state.Phase, "AwaitAction")
		ok = Engine.act(state, owner, { Kind = "Fire", Target = owner }, state.Turn.Token)
		H.truthy(ok)
		H.eq(state.Subjects[owner].Integrity, 1)
		H.eq(state.Phase, "TurnSetup")
	end)

	H.test("engine: stale tokens and wrong subjects are rejected", function()
		local state = newMatch("Standard")
		advanceUntilInput(state)
		local owner = state.Turn.Owner
		local other = owner == 1 and 2 or 1
		local token = state.Turn.Token
		local ok, reason = Engine.act(state, other, { Kind = "Fire", Target = owner }, token)
		H.eq(ok, false)
		H.eq(reason, "not_your_turn")
		ok, reason = Engine.act(state, owner, { Kind = "Fire", Target = other }, token - 1)
		H.eq(ok, false)
		H.eq(reason, "stale")
		-- Duplicate: the same token twice only works once.
		ok = Engine.act(state, owner, { Kind = "Fire", Target = owner }, token)
		H.truthy(ok)
		ok, reason = Engine.act(state, owner, { Kind = "Fire", Target = owner }, token)
		H.eq(ok, false)
	end)

	H.test("engine: malformed actions are rejected safely", function()
		local state = newMatch("Standard")
		advanceUntilInput(state)
		local owner = state.Turn.Owner
		local token = state.Turn.Token
		for _, bad in
			{
				"fire",
				{ Kind = "Fire", Target = 99 },
				{ Kind = "Fire", Target = "1" },
				{ Kind = "Use", Slot = 1 },
				{ Kind = "Use", Slot = 1.5 },
				{ Kind = "Use", Slot = -1 },
				{ Kind = "Dance" },
			}
		do
			local ok = Engine.act(state, owner, bad, token)
			H.eq(ok, false)
		end
		H.eq(state.Phase, "AwaitAction")
	end)

	H.test("engine: suture cannot exceed maximum integrity", function()
		local state = newMatch("Standard")
		advanceUntilInput(state)
		local owner = state.Subjects[state.Turn.Owner]
		Engine.giveInstrument(state, owner, "Suture")
		local ok, reason = Engine.act(state, owner.Id, { Kind = "Use", Slot = 1 }, state.Turn.Token)
		H.eq(ok, false)
		H.eq(reason, "Integrity is already full.")
		owner.Integrity = owner.MaxIntegrity - 1
		ok = Engine.act(state, owner.Id, { Kind = "Use", Slot = 1 }, state.Turn.Token)
		H.truthy(ok)
		H.eq(owner.Integrity, owner.MaxIntegrity)
	end)

	H.test("engine: draws beyond capacity are lost, not stored", function()
		local state = newMatch("Standard", { Custom = Rules.sanitizeCustom({ Capacity = 2, Draws = 4 }) })
		local events = advanceUntilInput(state)
		local dealt = find(events, "Dealt")
		H.truthy(dealt)
		for id = 1, 2 do
			H.eq(#state.Subjects[id].Instruments, 2)
			H.eq(#dealt.Public.Lost[id], 2)
		end
	end)

	H.test("engine: capacitor doubles and surge adds on the last cell", function()
		local state = newMatch("Standard", {
			Overrides = { Forced = { Loads = { "C" } }, FixedIntegrity = 6, StartingInstruments = 0 },
		})
		state.Rules.Profiles[1].Surge = true
		advanceUntilInput(state)
		local owner = state.Subjects[state.Turn.Owner]
		local other = state.Subjects[owner.Id == 1 and 2 or 1]
		Engine.giveInstrument(state, owner, "Capacitor")
		H.truthy(Engine.act(state, owner.Id, { Kind = "Use", Slot = 1 }, state.Turn.Token))
		local ok, _, events = Engine.act(state, owner.Id, { Kind = "Fire", Target = other.Id }, state.Turn.Token)
		H.truthy(ok)
		H.eq(find(events, "FireResult").Public.Damage, 3) -- 1 x2 +1 surge
		H.eq(other.Integrity, 3)
	end)

	H.test("engine: dampener absorbs one point", function()
		local state = newMatch("Standard", { Overrides = { Forced = { Loads = { "CH" } }, FixedIntegrity = 3 } })
		advanceUntilInput(state)
		local owner = state.Subjects[state.Turn.Owner]
		local other = state.Subjects[owner.Id == 1 and 2 or 1]
		other.Effects.Dampener = true
		Engine.act(state, owner.Id, { Kind = "Fire", Target = other.Id }, state.Turn.Token)
		H.eq(other.Integrity, 3)
		H.eq(other.Effects.Dampener, false)
	end)

	H.test("engine: clamp skips exactly one turn and grants immunity", function()
		local state = newMatch("Standard", { Overrides = { Forced = { Loads = { "HHHHH" } }, FixedIntegrity = 3 } })
		advanceUntilInput(state)
		local a = state.Subjects[state.Turn.Owner]
		local b = state.Subjects[a.Id == 1 and 2 or 1]
		Engine.giveInstrument(state, a, "Clamp")
		Engine.giveInstrument(state, a, "Clamp")
		H.truthy(Engine.act(state, a.Id, { Kind = "Use", Slot = 1 }, state.Turn.Token))
		H.eq(b.Effects.Clamped, true)
		-- Fire at B (HOLLOW) -> turn passes to B, who is clamped -> back to A.
		Engine.act(state, a.Id, { Kind = "Fire", Target = b.Id }, state.Turn.Token)
		local events = advanceUntilInput(state)
		H.truthy(find(events, "TurnSkipped"))
		H.eq(state.Turn.Owner, a.Id)
		-- B is immune now.
		local ok, reason = Engine.act(state, a.Id, { Kind = "Use", Slot = 1 }, state.Turn.Token)
		H.eq(ok, false)
		H.eq(reason, "They must play a turn before being clamped again.")
	end)

	H.test("engine: tether double collapse triggers sudden death", function()
		local state = newMatch("Standard", { Overrides = { Forced = { Loads = { "CH" } }, FixedIntegrity = 1 } })
		advanceUntilInput(state)
		local a = state.Subjects[state.Turn.Owner]
		local b = state.Subjects[a.Id == 1 and 2 or 1]
		Engine.giveInstrument(state, a, "Tether")
		H.truthy(Engine.act(state, a.Id, { Kind = "Use", Slot = 1 }, state.Turn.Token))
		Engine.act(state, a.Id, { Kind = "Fire", Target = b.Id }, state.Turn.Token)
		H.eq(a.Integrity, 0)
		H.eq(b.Integrity, 0)
		H.eq(state.Phase, "TrialEnd")
		local events = advanceUntilInput(state)
		H.truthy(find(events, "SuddenDeath"))
		H.eq(a.Integrity, 1)
		H.eq(b.Integrity, 1)
		H.eq(#state.Load.Cells, 3)
		H.eq(state.Load.PoolCharged, 1)
	end)

	H.test("engine: serum can eliminate its user", function()
		local state = newMatch("Standard", { Seed = 3, Overrides = { FixedIntegrity = 1 } })
		advanceUntilInput(state)
		local a = state.Subjects[state.Turn.Owner]
		-- Find a seed position where the serum fails.
		local failed = false
		for _ = 1, 40 do
			if state.Phase ~= "AwaitAction" or state.Turn.Owner ~= a.Id then
				break
			end
			Engine.giveInstrument(state, a, "Serum")
			Engine.act(state, a.Id, { Kind = "Use", Slot = #a.Instruments }, state.Turn.Token)
			if a.Eliminated then
				failed = true
				break
			end
		end
		H.truthy(failed, "serum should eventually fail")
		H.eq(state.Phase, "TrialEnd")
	end)

	H.test("engine: ejecting the last cell ends the load", function()
		local state = newMatch("Standard", { Overrides = { Forced = { Loads = { "C" } } } })
		advanceUntilInput(state)
		local a = state.Subjects[state.Turn.Owner]
		Engine.giveInstrument(state, a, "Ejector")
		local ok, _, events = Engine.act(state, a.Id, { Kind = "Use", Slot = 1 }, state.Turn.Token)
		H.truthy(ok)
		H.eq(find(events, "InstrumentUsed").Public.Outcome.Charged, true)
		H.eq(state.Phase, "LoadEnd")
	end)

	H.test("engine: lens result is private to its user", function()
		local state = newMatch("Standard", { Overrides = { Forced = { Loads = { "CH" } } } })
		advanceUntilInput(state)
		local a = state.Subjects[state.Turn.Owner]
		local b = a.Id == 1 and 2 or 1
		Engine.giveInstrument(state, a, "Lens")
		local _, _, events = Engine.act(state, a.Id, { Kind = "Use", Slot = 1 }, state.Turn.Token)
		local used = find(events, "InstrumentUsed")
		H.eq(used.Public.Belief.Track[1].Known, nil)
		H.eq(used.Private[a.Id].Belief.Track[1].Known, "C")
		H.eq(used.Private[b].Belief.Track[1].Known, nil)
		H.eq(used.Private[a.Id].Reveal[1].Charged, true)
		-- Lens twice is refused.
		Engine.giveInstrument(state, a, "Lens")
		local ok = Engine.act(state, a.Id, { Kind = "Use", Slot = 1 }, state.Turn.Token)
		H.eq(ok, false)
	end)

	H.test("engine: inverter flips knowledge for whoever knew", function()
		local state = newMatch("Standard", { Overrides = { Forced = { Loads = { "CH" } } } })
		advanceUntilInput(state)
		local a = state.Subjects[state.Turn.Owner]
		Engine.giveInstrument(state, a, "Lens")
		Engine.giveInstrument(state, a, "Inverter")
		Engine.act(state, a.Id, { Kind = "Use", Slot = 1 }, state.Turn.Token)
		local _, _, events = Engine.act(state, a.Id, { Kind = "Use", Slot = 1 }, state.Turn.Token)
		local used = find(events, "InstrumentUsed")
		H.eq(used.Private[a.Id].Belief.Track[1].Known, "H")
		H.eq(used.Public.Belief.Track[1].Parity, 1)
	end)

	H.test("engine: scrambler re-casts and wipes knowledge", function()
		local state = newMatch("Standard", { Overrides = { Forced = { Loads = { "CHCH" } } } })
		advanceUntilInput(state)
		local a = state.Subjects[state.Turn.Owner]
		Engine.giveInstrument(state, a, "Lens")
		Engine.giveInstrument(state, a, "Scrambler")
		Engine.act(state, a.Id, { Kind = "Use", Slot = 1 }, state.Turn.Token)
		local _, _, events = Engine.act(state, a.Id, { Kind = "Use", Slot = 1 }, state.Turn.Token)
		local used = find(events, "InstrumentUsed")
		H.eq(used.Public.Outcome.PoolSize, 4)
		H.eq(used.Private[a.Id].Belief.Track[1].Known, nil)
		H.eq(state.Load.RemovedCharged + state.Load.RemovedHollow, 0)
	end)

	H.test("engine: forfeit during a turn ends a duel", function()
		local state = newMatch("Standard")
		advanceUntilInput(state)
		local owner = state.Turn.Owner
		local events = Engine.forfeit(state, owner, "Left")
		H.truthy(find(events, "Forfeit"))
		H.eq(state.Phase, "MatchEnd")
		H.truthy(state.WinnerTeam ~= state.Subjects[owner].TeamId)
		-- Actions after the match are refused.
		local ok, reason = Engine.act(state, owner == 1 and 2 or 1, { Kind = "Fire", Target = owner }, state.Turn.Token)
		H.eq(ok, false)
		H.eq(reason, "not_accepting")
	end)

	H.test("engine: forfeit in crossfire passes the turn and continues", function()
		local state = newMatch("Crossfire", {
			Subjects = { { Name = "A" }, { Name = "B" }, { Name = "C" } },
		})
		advanceUntilInput(state)
		local owner = state.Turn.Owner
		Engine.forfeit(state, owner, "Left")
		H.eq(state.Phase, "TurnSetup")
		advanceUntilInput(state)
		H.truthy(state.Turn.Owner ~= owner)
		H.eq(state.Phase, "AwaitAction")
	end)

	H.test("engine: timeout fires at the undecided subject", function()
		local state = newMatch("Standard", { Overrides = { Forced = { Loads = { "CH" } } } })
		advanceUntilInput(state)
		local owner = state.Subjects[state.Turn.Owner]
		local events = Engine.timeout(state)
		H.eq(events[1].Type, "Timeout")
		H.eq(owner.Integrity, 1)
		H.eq(owner.Stats.Timeouts, 1)
	end)

	H.test("engine: teammates cannot be targeted in team games", function()
		local state = newMatch("Crossfire", {
			Subjects = {
				{ Name = "A", TeamId = 1 },
				{ Name = "B", TeamId = 2 },
				{ Name = "C", TeamId = 1 },
				{ Name = "D", TeamId = 2 },
			},
		})
		advanceUntilInput(state)
		local owner = state.Subjects[state.Turn.Owner]
		local mate
		for _, s in state.Subjects do
			if s ~= owner and s.TeamId == owner.TeamId then
				mate = s
			end
		end
		local ok, reason = Engine.act(state, owner.Id, { Kind = "Fire", Target = mate.Id }, state.Turn.Token)
		H.eq(ok, false)
		H.eq(reason, "bad_target")
	end)

	H.test("rules: custom settings are sanitized", function()
		local clean = Rules.sanitizeCustom({
			MaxIntegrity = 99,
			TrialsToWin = -4,
			Capacity = "lots",
			Enabled = { "Lens", "Nope", "Lens", 5 },
			TurnTimer = 3,
			Modifiers = { "Volatile", "Blind", "Echo", "Glass", "Surplus", "Bogus" },
			Environment = "Moon",
			Evil = true,
		})
		H.eq(clean.MaxIntegrity, 8)
		H.eq(clean.TrialsToWin, 1)
		H.eq(clean.Capacity, 6)
		H.eq(#clean.Enabled, 1)
		H.eq(clean.TurnTimer, 10)
		H.eq(#clean.Modifiers, 4)
		H.eq(clean.Environment, "Rotate")
		H.eq(clean.Evil, nil)
	end)

	H.test("instruments: every definition is complete", function()
		for _, def in Instruments.List do
			H.truthy(type(def.CanUse) == "function", def.Id .. " CanUse")
			H.truthy(type(def.Apply) == "function", def.Id .. " Apply")
			H.truthy(Instruments.Rarities[def.Rarity], def.Id .. " rarity")
			H.truthy(#def.Description > 10, def.Id .. " description")
			H.truthy(def.Duration > 0, def.Id .. " duration")
		end
	end)
end

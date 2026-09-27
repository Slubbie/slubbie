-- Randomized engine fuzzing: thousands of matches driven by random legal and
-- illegal actions across every mode and modifier. Checks invariants after every
-- step so any rule bug surfaces as a precise failure instead of a stuck match.

return function(H)
	local Engine = H.require("Core/Engine")
	local Rules = H.require("Core/Rules")
	local Rng = H.require("Util/Rng")
	local Modifiers = H.require("Core/Modifiers")
	local Probability = H.require("Core/Probability")

	local function invariants(state)
		for _, s in state.Subjects do
			assert(s.Integrity >= 0, "negative integrity")
			assert(s.Integrity <= math.max(s.MaxIntegrity, 0), "integrity above max")
			assert(#s.Instruments <= Engine.capacity(state) or state.Rules.InfiniteInstruments, "over capacity")
			if s.Integrity == 0 and state.Trial > 0 then
				assert(s.Eliminated, "zero integrity but not eliminated")
			end
		end
		local load = state.Load
		if load then
			local charged, parity1 = 0, 0
			for _, c in load.Cells do
				if c.Charged then
					charged += 1
				end
				if c.Parity == 1 then
					parity1 += 1
				end
			end
			-- Public accounting: originals remaining must be consistent with pool.
			local origCharged = 0
			for _, c in load.Cells do
				local orig = c.Charged
				if c.Parity == 1 then
					orig = not orig
				end
				if orig then
					origCharged += 1
				end
			end
			assert(
				origCharged + load.RemovedCharged == load.PoolCharged,
				"pool accounting broken: " .. origCharged .. "+" .. load.RemovedCharged .. "~=" .. load.PoolCharged
			)
			assert(#load.Cells + load.RemovedCharged + load.RemovedHollow == load.PoolSize, "pool size broken")
			-- Probability sanity for every viewer.
			for _, s in state.Subjects do
				local b = Engine.belief(state, s.Id)
				for i = 1, #b.Track do
					local p = Probability.chargedAt(b, i)
					assert(p >= -1e-9 and p <= 1 + 1e-9, "probability out of range")
					if b.Track[i].Known then
						local truth = load.Cells[i].Charged
						assert((b.Track[i].Known == "C") == truth, "knowledge disagrees with truth")
					end
				end
				local lo, hi = Probability.range(b)
				if not load.Blind then
					assert(charged >= lo and charged <= hi, "true count outside public range")
				end
			end
		end
	end

	local function randomAction(rng, state)
		local owner = state.Turn.Owner
		local legal = Engine.legal(state, owner)
		local roll = rng:NextNumber()
		if roll < 0.05 then
			-- Junk input: must be rejected without changing anything.
			local junk = {
				{ Kind = "Use", Slot = 0 },
				{ Kind = "Fire", Target = 0 },
				{ Kind = "Use", Slot = 99 },
				{ Kind = "Fire" },
			}
			return junk[rng:NextInteger(1, #junk)], true
		end
		local usable = {}
		local fires = {}
		for _, a in legal do
			if a.Kind == "Use" and a.Ok then
				table.insert(usable, a)
			elseif a.Kind == "Fire" then
				table.insert(fires, a)
			end
		end
		if #usable > 0 and roll < 0.45 then
			local a = usable[rng:NextInteger(1, #usable)]
			return { Kind = "Use", Slot = a.Slot, Target = a.Target }, false
		end
		local a = fires[rng:NextInteger(1, #fires)]
		return { Kind = "Fire", Target = a.Target }, false
	end

	local function play(modeId, seed, subjects, custom, overrides)
		local rules = Rules.build(modeId, custom, overrides)
		local state = Engine.new({ Rules = rules, Rng = Rng.pure(seed), Subjects = subjects })
		local rng = Rng.pure(seed * 31 + 7)
		local steps = 0
		while state.Phase ~= "Ended" do
			steps += 1
			assert(steps < 5000, "match did not finish (phase " .. state.Phase .. ")")
			if state.Phase == "AwaitAction" then
				local r = rng:NextNumber()
				if r < 0.01 then
					Engine.timeout(state)
				elseif r < 0.012 then
					-- Random forfeit of a random non-forfeited subject.
					local candidates = {}
					for _, s in state.Subjects do
						if not s.Forfeited then
							table.insert(candidates, s.Id)
						end
					end
					Engine.forfeit(state, candidates[rng:NextInteger(1, #candidates)], "Fuzz")
				else
					local action, junk = randomAction(rng, state)
					local before = state.Turn.Token
					local ok = Engine.act(state, state.Turn.Owner, action, state.Turn.Token)
					if junk then
						assert(not ok, "junk accepted")
						assert(state.Turn.Token == before, "junk changed token")
					else
						assert(ok, "legal action rejected")
					end
				end
			else
				Engine.advance(state)
			end
			invariants(state)
		end
		return state
	end

	H.test("fuzz: 400 standard duels finish with a winner", function()
		local winners = { 0, 0 }
		for seed = 1, 400 do
			local state = play("Standard", seed, { { Name = "A" }, { Name = "B" } })
			if state.WinnerTeam then
				winners[state.WinnerTeam] += 1
			end
		end
		assert(winners[1] + winners[2] >= 390, "too many matches without winners")
	end)

	H.test("fuzz: every mode survives random play", function()
		for _, modeId in { "Rapid", "Chaos", "Precision", "Ranked", "Endurance", "Sandbox", "Solo" } do
			for seed = 1, 60 do
				play(modeId, seed * 13, { { Name = "A" }, { Name = "B" } })
			end
		end
	end)

	H.test("fuzz: crossfire and team games with 3-4 subjects", function()
		for seed = 1, 120 do
			play("Crossfire", seed, { { Name = "A" }, { Name = "B" }, { Name = "C" } })
			play("Crossfire", seed + 500, { { Name = "A" }, { Name = "B" }, { Name = "C" }, { Name = "D" } })
			play("Crossfire", seed + 900, {
				{ Name = "A", TeamId = 1 },
				{ Name = "B", TeamId = 2 },
				{ Name = "C", TeamId = 1 },
				{ Name = "D", TeamId = 2 },
			})
		end
	end)

	H.test("fuzz: every modifier individually and extreme custom rules", function()
		for _, mod in Modifiers.List do
			for seed = 1, 25 do
				local custom = Rules.sanitizeCustom({ Modifiers = { mod.Id }, Draws = 3, StartingInstruments = 2 })
				play("Standard", seed * 7 + #mod.Id, { { Name = "A" }, { Name = "B" } }, custom)
			end
		end
		for seed = 1, 60 do
			local custom = Rules.sanitizeCustom({
				MaxIntegrity = (seed % 8) + 1,
				Damage = (seed % 3) + 1,
				Capacity = (seed % 7) + 2,
				Draws = seed % 7,
				TrialsToWin = (seed % 3) + 1,
				Rarity = "Chaos",
			})
			play("Standard", seed * 3, { { Name = "A" }, { Name = "B" } }, custom)
		end
	end)

	H.test("fuzz: infinite instruments debug rule", function()
		for seed = 1, 30 do
			play(
				"Standard",
				seed,
				{ { Name = "A" }, { Name = "B" } },
				nil,
				{ InfiniteInstruments = true, StartingInstruments = 4 }
			)
		end
	end)
end

-- Surrogate AI tests: tactical sanity, honesty (only public/own knowledge), and
-- difficulty ordering via AI-vs-AI matches.

return function(H)
	local Engine = H.require("Core/Engine")
	local Rules = H.require("Core/Rules")
	local Rng = H.require("Util/Rng")
	local Brain = H.require("Core/AI/Brain")
	local Solver = H.require("Core/AI/Solver")
	local Difficulty = H.require("Core/AI/Difficulty")
	local Personalities = H.require("Core/AI/Personalities")

	local function setup(pattern, integrityA, integrityB, overrides)
		local o = overrides or {}
		o.Forced = { Loads = { pattern } }
		o.FixedIntegrity = math.max(integrityA, integrityB)
		local state = Engine.new({
			Rules = Rules.build("Standard", nil, o),
			Rng = Rng.pure(11),
			Subjects = { { Name = "AI", IsAI = true }, { Name = "Human" } },
		})
		while state.Phase ~= "AwaitAction" do
			Engine.advance(state)
		end
		-- Make sure subject 1 holds the turn.
		state.Turn.Owner = 1
		state.Subjects[1].Integrity = integrityA
		state.Subjects[2].Integrity = integrityB
		return state
	end

	local function brain(tier, personality, seed)
		return Brain.new({
			Personality = personality or "Ledger",
			Difficulty = Difficulty.get(tier or "Expert"),
			Rng = Rng.pure(seed or 5),
		})
	end

	H.test("solver: certain lethal shot is a guaranteed win", function()
		local s = Solver.new({ Damage = 1, Surge = false, Cells = { 2, 4 }, Charged = { 0.34, 0.67 } })
		local selfVal, oppVal = s:options(1, 0, 2, 1, 0, 0, false)
		H.near(oppVal, 1)
		H.truthy(selfVal < 1)
	end)

	H.test("solver: values stay within [0, 1]", function()
		local s = Solver.new({ Damage = 1, Surge = true, Cells = { 4, 8 }, Charged = { 0.3, 0.65 } })
		for c = 0, 6 do
			for h = 0, 6 do
				for a = 1, 5 do
					for b = 1, 5 do
						local v = s:W(c, h, a, b, 0, 0, false)
						H.truthy(v >= 0 and v <= 1, "out of range")
					end
				end
			end
		end
	end)

	H.test("brain: fires at the opponent when the loaded cell is known CHARGED", function()
		local state = setup("CHH", 3, 3)
		state.Subjects[1].Knows[state.Load.Cells[1].Uid] = true
		for seed = 1, 20 do
			local action = brain("Expert", "Ledger", seed):decide(Engine.aiView(state, 1))
			H.eq(action.Kind, "Fire")
			H.eq(action.Target, 2)
		end
	end)

	H.test("brain: fires at itself when the loaded cell is known HOLLOW", function()
		local state = setup("HCC", 3, 3)
		state.Subjects[1].Knows[state.Load.Cells[1].Uid] = true
		-- Advanced keeps 95% of what it saw, so allow the odd designed memory lapse.
		local correct = 0
		for seed = 1, 20 do
			local action = brain("Advanced", "Ledger", seed):decide(Engine.aiView(state, 1))
			if action.Kind == "Fire" and action.Target == 1 then
				correct += 1
			end
		end
		H.truthy(correct >= 18, "self-shots " .. correct .. "/20")
	end)

	H.test("brain: takes a lethal line with Capacitor when it knows", function()
		local state = setup("CHH", 4, 2)
		state.Subjects[1].Knows[state.Load.Cells[1].Uid] = true
		Engine.giveInstrument(state, state.Subjects[1], "Capacitor")
		local action = brain("Expert", "Ledger", 1):decide(Engine.aiView(state, 1))
		H.eq(action.Kind, "Use")
		H.eq(state.Subjects[1].Instruments[action.Slot], "Capacitor")
	end)

	H.test("brain: values a Lens at even odds (Advanced)", function()
		local state = setup("CHCH", 3, 3)
		Engine.giveInstrument(state, state.Subjects[1], "Lens")
		local used = 0
		for seed = 1, 20 do
			local action = brain("Advanced", "Ledger", seed):decide(Engine.aiView(state, 1))
			if action.Kind == "Use" then
				used += 1
			end
		end
		H.truthy(used >= 15, "lens used " .. used .. "/20")
	end)

	H.test("brain: heals when hurt and no better play exists", function()
		local state = setup("HHC", 1, 3, { FixedIntegrity = 4 })
		state.Subjects[1].MaxIntegrity = 4
		Engine.giveInstrument(state, state.Subjects[1], "Suture")
		local action = brain("Expert", "Ledger", 3):decide(Engine.aiView(state, 1))
		H.eq(action.Kind, "Use")
	end)

	H.test("brain: honesty - decisions never depend on hidden cells", function()
		-- Two states identical in public info but different hidden sequences.
		local a = setup("CHCH", 3, 3)
		local b = setup("HCHC", 3, 3)
		for seed = 1, 10 do
			local actA = brain("Expert", "Ledger", seed):decide(Engine.aiView(a, 1))
			local actB = brain("Expert", "Ledger", seed):decide(Engine.aiView(b, 1))
			H.eq(actA.Kind, actB.Kind)
			H.eq(actA.Target, actB.Target)
		end
	end)

	-- AI vs AI -------------------------------------------------------------

	local function duel(tierA, tierB, personaA, personaB, seed, modeId)
		local rules = Rules.build(modeId or "Standard", nil, { TurnTimer = 0 })
		local state = Engine.new({
			Rules = rules,
			Rng = Rng.pure(seed),
			Subjects = { { Name = "A", IsAI = true }, { Name = "B", IsAI = true } },
		})
		local brains = {
			Brain.new({ Personality = personaA, Difficulty = Difficulty.get(tierA), Rng = Rng.pure(seed * 3 + 1) }),
			Brain.new({ Personality = personaB, Difficulty = Difficulty.get(tierB), Rng = Rng.pure(seed * 5 + 2) }),
		}
		local steps = 0
		while state.Phase ~= "Ended" do
			steps += 1
			assert(steps < 4000, "AI duel stuck")
			local events
			if state.Phase == "AwaitAction" then
				local owner = state.Turn.Owner
				local view = Engine.aiView(state, owner)
				brains[owner].tier = Difficulty.forTrial(Difficulty.get(owner == 1 and tierA or tierB), state.Trial)
				local action = brains[owner]:decide(view)
				local ok, reason
				ok, reason, events = Engine.act(state, owner, action, state.Turn.Token)
				assert(ok, "AI chose an illegal action: " .. tostring(reason))
			else
				events = Engine.advance(state)
			end
			for _, e in events do
				brains[1]:observe(e, 1)
				brains[2]:observe(e, 2)
				if e.Type == "FireResult" and state.Log[#state.Log] then
					local entry = state.Log[#state.Log]
					local watcher = entry.Actor == 1 and brains[2] or brains[1]
					watcher.tendencies:recordFire(entry.PublicP, entry.Actor == entry.Target, entry.Used)
				end
			end
		end
		return state.WinnerTeam
	end
	H.duel = duel

	H.test("ai: every personality and tier plays legal full matches", function()
		for _, p in Personalities.List do
			for _, tier in Difficulty.Order do
				duel(tier, "Standard", p.Id, "Ledger", #p.Id * 17 + #tier, "Standard")
			end
		end
		duel("Expert", "Expert", "Proctor", "Kismet", 99, "Chaos")
		duel("Advanced", "Casual", "Magpie", "Volta", 98, "Precision")
		duel("Expert", "Advanced", "Volta", "Magpie", 97, "Rapid")
	end)

	H.test("ai: Expert beats Casual clearly (60 matches, seats alternated)", function()
		local wins = 0
		local n = 60
		for seed = 1, n do
			if seed % 2 == 0 then
				if duel("Expert", "Casual", "Ledger", "Ledger", seed) == 1 then
					wins += 1
				end
			else
				if duel("Casual", "Expert", "Ledger", "Ledger", seed) == 2 then
					wins += 1
				end
			end
		end
		print(string.format("   Expert vs Casual: %d/%d", wins, n))
		H.truthy(wins / n >= 0.65, "expert should dominate casual")
	end)
end

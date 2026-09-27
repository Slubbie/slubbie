-- Tutorial scripts, data integrity and progression math.

return function(H)
	local Engine = H.require("Core/Engine")
	local Rules = H.require("Core/Rules")
	local Rng = H.require("Util/Rng")
	local Director = H.require("Core/TutorialDirector")
	local Tutorials = H.require("Data/Tutorials")
	local Brain = H.require("Core/AI/Brain")
	local Difficulty = H.require("Core/AI/Difficulty")
	local Probability = H.require("Core/Probability")
	local Cosmetics = H.require("Data/Cosmetics")
	local Achievements = H.require("Data/Achievements")
	local Challenges = H.require("Data/Challenges")
	local Lore = H.require("Data/Lore")
	local Levels = H.require("Data/Levels")
	local Rating = H.require("Core/Rating")
	local SettingsSchema = H.require("Data/SettingsSchema")
	local Dialogue = H.require("Data/Dialogue")
	local Personalities = H.require("Core/AI/Personalities")
	local Surrogates = H.require("Data/Surrogates")
	local Environments = H.require("Data/Environments")
	local Instruments = H.require("Core/Instruments")
	local Report = H.require("Core/Report")
	local Timeline = H.require("Core/Timeline")

	-- Plays a lesson the way a cooperative player would. Returns the director.
	local function playLesson(lesson, seed)
		local director
		local rules = Rules.build("Tutorial", nil, lesson.Rules)
		local state = Engine.new({
			Rules = rules,
			Rng = Rng.pure(seed or 1),
			Subjects = { { Name = "Player" }, { Name = "PROXY", IsAI = true, Personality = "Proxy" } },
			Filter = function(s, subject, action)
				return director:filter(s, subject, action)
			end,
		})
		director = Director.new(lesson, 1, 2)
		director:start(state, Engine)
		local brain = Brain.new({ Personality = "Proxy", Difficulty = Difficulty.get("Casual"), Rng = Rng.pure(3) })
		local steps = 0
		while not director.done do
			steps += 1
			assert(steps < 3000, "lesson stuck at beat " .. director.index .. " (" .. state.Phase .. ")")
			local beat = director:beat()
			local events = {}
			if state.Phase == "Ended" then
				-- Match over: only Continue / Finish beats can remain.
				if not director:continue(state, Engine) then
					error("match ended with a beat waiting on " .. tostring(beat and beat.Advance))
				end
			elseif state.Phase == "AwaitAction" then
				local owner = state.Turn.Owner
				if owner == 2 then
					local action = director:proxyAction(state)
					if action == "brain" then
						action = brain:decide(Engine.aiView(state, 2))
					end
					if action == "wait" then
						-- PROXY waits for the player to read on.
						assert(beat.Advance == "Continue" or beat.Advance == "Quiz" or beat.Advance == "Finish", "proxy waiting forever at beat " .. director.index)
						if beat.Advance == "Quiz" then
							director:answer(state, Engine, beat.Quiz.Answer)
						else
							director:continue(state, Engine)
						end
					else
						local ok, reason
						ok, reason, events = Engine.act(state, 2, action, state.Turn.Token)
						assert(ok, "proxy script illegal at beat " .. director.index .. ": " .. tostring(reason))
					end
				else
					if beat.Advance == "Continue" or beat.Advance == "Finish" then
						director:continue(state, Engine)
					elseif beat.Advance == "Quiz" then
						local wrong = beat.Quiz.Answer == 1 and 2 or 1
						local ok = director:answer(state, Engine, wrong)
						assert(not ok, "wrong quiz answer accepted")
						ok = director:answer(state, Engine, beat.Quiz.Answer)
						assert(ok, "right quiz answer rejected")
					else
						-- Find the allowed action and take it.
						local chosen = nil
						if beat.Free then
							chosen = brain:decide(Engine.aiView(state, 1))
						else
							for _, legal in Engine.legal(state, 1) do
								if legal.Ok ~= false then
									chosen = { Kind = legal.Kind, Target = legal.Target, Slot = legal.Slot }
									break
								end
							end
						end
						assert(chosen, "no allowed action at beat " .. director.index .. ": " .. tostring(beat.Say))
						local ok, reason
						ok, reason, events = Engine.act(state, 1, chosen, state.Turn.Token)
						assert(ok, "allowed action rejected at beat " .. director.index .. ": " .. tostring(reason))
						director:onAccepted(1, chosen)
					end
				end
			else
				events = Engine.advance(state)
			end
			for _, e in events do
				director:onEvent(e)
			end
			director:onPresented(state, Engine)
		end
		return director, state
	end

	H.test("tutorial: orientation plays start to finish", function()
		for seed = 1, 12 do
			local director, state = playLesson(Tutorials.Basic, seed)
			H.truthy(director.done)
			H.truthy(state.Trial >= 3, "orientation should reach Trial III")
		end
	end)

	H.test("tutorial: orientation hits the scripted outcomes", function()
		-- The scripted Loads must produce the story the coach text tells.
		local director, state = playLesson(Tutorials.Basic, 5)
		H.eq(state.LoadRecords[1].Pattern, "CH")
		H.eq(state.LoadRecords[4].Pattern, "HCC")
		H.truthy(state.Subjects[1].TrialWins >= 2)
		H.truthy(director.done)
	end)

	H.test("tutorial: every seminar completes", function()
		for _, seminar in Tutorials.Seminars do
			local director = playLesson(seminar, 7)
			H.truthy(director.done, seminar.Id)
		end
	end)

	H.test("tutorial: quiz answers match the real probability", function()
		-- Conditional seminar, beat 3: 2C/2H with cell 3 known CHARGED -> 1/3.
		local b = {
			PoolSize = 4,
			PoolCharged = 2,
			RemovedCharged = 0,
			RemovedHollow = 0,
			Track = { { Parity = 0 }, { Parity = 0 }, { Parity = 0, Known = "C" }, { Parity = 0 } },
		}
		H.near(Probability.current(b), 1 / 3)
		b = Probability.remove(b, 1, false)
		H.near(Probability.current(b), 0.5)
	end)

	H.test("tutorial: filter blocks everything but the prompt", function()
		local lesson = Tutorials.Basic
		local director
		local state = Engine.new({
			Rules = Rules.build("Tutorial", nil, lesson.Rules),
			Rng = Rng.pure(1),
			Subjects = { { Name = "P" }, { Name = "X", IsAI = true } },
			Filter = function(s, subject, action)
				return director:filter(s, subject, action)
			end,
		})
		director = Director.new(lesson, 1, 2)
		director:start(state, Engine)
		while state.Phase ~= "AwaitAction" do
			Engine.advance(state)
		end
		local ok = Engine.act(state, 1, { Kind = "Fire", Target = 2 }, state.Turn.Token)
		H.eq(ok, false, "firing during an intro beat must be blocked")
	end)

	-- Data integrity ---------------------------------------------------------

	H.test("data: cosmetic sources reference real content", function()
		local seen = {}
		for _, item in Cosmetics.List do
			H.truthy(not seen[item.Id], "duplicate cosmetic " .. item.Id)
			seen[item.Id] = true
			if item.Source.Kind == "Achievement" then
				H.truthy(Achievements.get(item.Source.Value), item.Id .. " -> missing achievement " .. tostring(item.Source.Value))
			elseif item.Source.Kind == "Shop" then
				H.truthy(type(item.Price) == "number" and item.Price > 0, item.Id .. " needs a price")
			elseif item.Source.Kind == "Level" then
				H.truthy(item.Source.Value >= 1 and item.Source.Value <= Levels.Max, item.Id .. " level")
			end
		end
		for _, cat in Cosmetics.Categories do
			H.truthy(Cosmetics.Defaults[cat.Id], "no default for " .. cat.Id)
		end
	end)

	H.test("data: lore unlocks reference real content", function()
		for _, file in Lore.Files do
			local u = file.Unlock
			if u.Kind == "Defeat" then
				H.truthy(Personalities.ById[u.Value], file.Id)
			elseif u.Kind == "Environment" then
				H.truthy(Environments.ById[u.Value], file.Id)
			elseif u.Kind == "Achievement" then
				H.truthy(Achievements.get(u.Value), file.Id)
			end
		end
	end)

	H.test("data: every personality has visuals and dialogue", function()
		for _, p in Personalities.List do
			H.truthy(Surrogates.ById[p.Id], "visuals for " .. p.Id)
			H.truthy(Dialogue.Lines[p.Id], "dialogue for " .. p.Id)
			H.truthy(Dialogue.Lines[p.Id].Intro, "intro for " .. p.Id)
		end
	end)

	H.test("data: challenges are deterministic per player and period", function()
		local a = Challenges.dailyFor(123456, 20000)
		local b = Challenges.dailyFor(123456, 20000)
		H.eq(#a, 3)
		for i = 1, 3 do
			H.eq(a[i].Id, b[i].Id)
			H.eq(a[i].Goal, b[i].Goal)
		end
		local w = Challenges.weeklyFor(987, 2900)
		H.eq(#w, 3)
		local ids = {}
		for _, e in w do
			H.truthy(not ids[e.Id], "duplicate weekly")
			ids[e.Id] = true
		end
		-- Rotation actually varies.
		local distinct = {}
		for day = 1, 30 do
			distinct[Challenges.dailyFor(55, day)[2].Id] = true
		end
		local n = 0
		for _ in distinct do
			n += 1
		end
		H.truthy(n >= 3, "daily rotation too narrow")
	end)

	H.test("data: challenge progress and distinct counting", function()
		local entry = { Id = "w_environments", Goal = 2, Progress = 0, Done = false, Claimed = false, Seen = {} }
		local ctx = { Outcome = { Won = true, Forfeited = false }, Match = { Environment = "TestChamber" } }
		H.eq(Challenges.apply(entry, ctx), false)
		H.eq(Challenges.apply(entry, ctx), false)
		ctx.Match.Environment = "CasinoBackroom"
		H.eq(Challenges.apply(entry, ctx), true)
		H.eq(entry.Progress, 2)
	end)

	H.test("levels: XP curve is monotonic and invertible", function()
		local total = 0
		for level = 1, 60 do
			local l, into = Levels.fromXP(total)
			H.eq(l, level)
			H.eq(into, 0)
			total += Levels.toNext(level)
			H.truthy(Levels.toNext(level + 1) >= Levels.toNext(level))
		end
		H.eq(Levels.titleFor(1), "CANDIDATE")
		H.eq(Levels.titleFor(100), "VARIANCE")
	end)

	H.test("rating: elo is zero-sum-ish and divisions are ordered", function()
		local a, da = Rating.update(1000, 1000, 1, 32)
		local b, db = Rating.update(1000, 1000, 0, 32)
		H.eq(da, 16)
		H.eq(db, -16)
		H.eq(a, 1016)
		H.eq(b, 984)
		H.eq(Rating.division(850).Id, "Probationer")
		H.eq(Rating.division(1100).Label, "STRATEGIST III")
		H.eq(Rating.division(1299).Label, "STRATEGIST I")
		H.eq(Rating.division(1700).Id, "Oracle")
		H.eq(Rating.softReset(1400), 1200)
		H.truthy(Rating.lockoutFor(0) == 0 and Rating.lockoutFor(1) > 0)
	end)

	H.test("settings: schema cleans hostile input", function()
		local clean = SettingsSchema.cleanAll({
			MasterVolume = 7,
			Palette = "Neon",
			Cinematics = "Minimal",
			FieldOfView = 0 / 0,
			Binds = { FireSelf = "Escape", FireOther = "F", Slot1 = "F", Menu = string.rep("x", 40) },
			Hacked = true,
		})
		H.eq(clean.MasterVolume, 1)
		H.eq(clean.Palette, "Default")
		H.eq(clean.Cinematics, "Minimal")
		H.eq(clean.FieldOfView, 68)
		H.eq(clean.Binds.FireSelf, nil)
		H.eq(clean.Binds.FireOther, "F")
		H.eq(clean.Binds.Slot1, nil) -- duplicate key rejected
		H.eq(clean.Binds.Menu, nil)
		H.eq(clean.Hacked, nil)
	end)

	H.test("report: built after a match without errors", function()
		local state = Engine.new({
			Rules = Rules.build("Standard"),
			Rng = Rng.pure(4),
			Subjects = { { Name = "A" }, { Name = "B" } },
		})
		local brains = {
			Brain.new({ Difficulty = Difficulty.get("Advanced"), Rng = Rng.pure(1) }),
			Brain.new({ Difficulty = Difficulty.get("Standard"), Rng = Rng.pure(2) }),
		}
		local total = 0
		while state.Phase ~= "Ended" do
			local events
			if state.Phase == "AwaitAction" then
				local o = state.Turn.Owner
				local _
				_, _, events = Engine.act(state, o, brains[o]:decide(Engine.aiView(state, o)), state.Turn.Token)
			else
				events = Engine.advance(state)
			end
			total += Timeline.total(events)
		end
		local report = Report.build(state)
		H.truthy(report.WinnerTeam)
		H.truthy(#report.Loads >= 3)
		H.truthy(#report.Actions > 0)
		H.truthy(total > 30, "a match should take real time to present")
		for _, s in report.Subjects do
			H.truthy(s.Accuracy >= 0 and s.Accuracy <= 1)
		end
	end)

	H.test("instruments: every instrument has a unique name", function()
		local names = {}
		for _, def in Instruments.List do
			H.truthy(not names[def.Name], "duplicate name " .. def.Name)
			names[def.Name] = true
		end
	end)
end

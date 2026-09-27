-- The match engine: the authoritative rules of VARIANCE as a pure state machine.
--
-- It runs only on the server (MatchRunner owns one per match) and in headless
-- tests/simulations. It never touches Roblox APIs and never waits: it moves the
-- state forward one step at a time and returns the events that step produced.
-- Pacing (how long to wait between events) lives in Core/Timeline.luau and
-- routing (who may see what) in server/Match/Dispatcher.luau.
--
-- Hidden information
--   The true cell sequence exists only in `state.Load.Cells`. Events carry a
--   `Public` payload every viewer may see and an optional `Private` payload per
--   subject id (e.g. what a Lens revealed). Nothing hidden is ever put in Public.
--
-- Phases (see Engine.Phase)
--   Created → TrialSetup → LoadSetup → TurnSetup → AwaitAction ⟲
--   AwaitAction --act()--> AwaitAction (turn kept) | TurnSetup | LoadEnd | TrialEnd
--   LoadEnd → LoadSetup ; TrialEnd → TrialSetup | LoadSetup (sudden death) | MatchEnd → Ended
--
-- Public API
--   Engine.new(opts)                          -> state
--   Engine.advance(state)                     -> events    (automatic phases only)
--   Engine.act(state, subjectId, action, tok) -> ok, reason, events
--   Engine.timeout(state)                     -> events    (turn timer expired)
--   Engine.forfeit(state, subjectId, reason)  -> events    (left / abandoned / AFK)
--   Engine.legal(state, subjectId)            -> legal actions with reasons
--   Engine.belief(state, viewerId?)           -> Probability.Belief for that viewer
--   Engine.snapshot(state, viewerId?)         -> redacted full state for (re)sync
--   Engine.aiView(state, subjectId)           -> everything an AI in that seat may know

local Instruments = require(script.Parent.Instruments)
local Modifiers = require(script.Parent.Modifiers)
local Rules = require(script.Parent.Rules)
local Probability = require(script.Parent.Probability)

local Engine = {}

local Phase = {
	Created = "Created",
	TrialSetup = "TrialSetup",
	LoadSetup = "LoadSetup",
	TurnSetup = "TurnSetup",
	AwaitAction = "AwaitAction",
	LoadEnd = "LoadEnd",
	TrialEnd = "TrialEnd",
	MatchEnd = "MatchEnd",
	Ended = "Ended",
}
Engine.Phase = Phase

-- Reasons returned by act(). The client maps these to short messages.
Engine.Reject = {
	NotAccepting = "not_accepting",
	NotYourTurn = "not_your_turn",
	Stale = "stale",
	BadAction = "bad_action",
	BadTarget = "bad_target",
	BadSlot = "bad_slot",
	Disabled = "disabled",
	Limit = "limit",
	Blocked = "blocked",
}

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

local function newEffects()
	return {
		Capacitor = false,
		Dampener = false,
		Overclock = false,
		Clamped = false,
		ClampImmune = false,
	}
end

local function newStats()
	return {
		Shots = 0,
		ShotsSelf = 0,
		ShotsOther = 0,
		Reads = 0,
		SelfSurvived = 0,
		RiskySurvived = 0,
		RiskyStreak = 0,
		MaxRiskyStreak = 0,
		DamageDealt = 0,
		DamageTaken = 0,
		ChargedTaken = 0,
		Healed = 0,
		HealUsed = false,
		Instruments = {},
		InstrumentCount = 0,
		MinIntegrity = math.huge,
		CertainDecisions = 0,
		CertainMistakes = 0,
		Timeouts = 0,
		BestRisk = 0,
		Combos = {},
		ClutchTrials = 0,
		TrialsWon = 0,
		SuddenDeaths = 0,
		LowShotHits = 0,
		LethalLowShot = false,
		Eliminations = 0,
	}
end

export type SubjectSpec = {
	Name: string,
	TeamId: number?,
	IsAI: boolean?,
	UserId: number?,
	Personality: string?,
	Difficulty: string?,
}

export type EngineOptions = {
	MatchId: string?,
	Rules: { [string]: any },
	Subjects: { SubjectSpec },
	Rng: any,
	Filter: ((state: any, subject: any, action: any) -> (boolean, string?))?,
}

function Engine.new(opts: EngineOptions)
	assert(opts.Rules, "Engine.new needs Rules")
	assert(opts.Rng, "Engine.new needs an Rng")
	assert(#opts.Subjects >= 2, "Engine.new needs at least two subjects")
	local state = {
		MatchId = opts.MatchId or "local",
		Rules = opts.Rules,
		Rng = opts.Rng,
		Phase = Phase.Created,
		Trial = 0,
		LoadNumber = 0,
		LoadInTrial = 0,
		Subjects = {},
		Order = {},
		Turn = { Owner = 0, Token = 0, Used = {}, UseCounts = {}, Actions = 0 },
		LoadStarter = nil,
		NextStarter = nil,
		Load = nil,
		NextUid = 1,
		Tether = nil,
		TrialModifiers = {},
		Log = {},
		LoadRecords = {},
		WinnerTeam = nil,
		EndReason = nil,
		SuddenDeath = false,
		PendingSuddenDeath = nil,
		TrialWinnerTeam = nil,
		JustEliminated = {},
		ForcedNext = nil,
		Filter = opts.Filter,
		_events = {},
	}
	for index, spec in opts.Subjects do
		state.Subjects[index] = {
			Id = index,
			Name = spec.Name,
			TeamId = spec.TeamId or index,
			IsAI = spec.IsAI == true,
			UserId = spec.UserId,
			Personality = spec.Personality,
			Difficulty = spec.Difficulty,
			Integrity = 0,
			MaxIntegrity = 0,
			Instruments = {},
			Effects = newEffects(),
			Eliminated = false,
			Forfeited = false,
			TrialWins = 0,
			Knows = {},
			Stats = newStats(),
			Connected = true,
		}
		table.insert(state.Order, index)
	end
	return state
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local function emit(state, kind: string, public: { [string]: any }?, private: { [number]: { [string]: any } }?)
	table.insert(state._events, { Type = kind, Public = public or {}, Private = private })
end

local function flush(state)
	local events = state._events
	state._events = {}
	return events
end

-- Attaches the current belief (public + one per subject) to an event payload.
local function withBeliefs(state, public, private)
	public = public or {}
	private = private or {}
	public.Belief = Engine.belief(state, nil)
	for _, subject in state.Subjects do
		local entry = private[subject.Id] or {}
		entry.Belief = Engine.belief(state, subject.Id)
		private[subject.Id] = entry
	end
	return public, private
end

---------------------------------------------------------------------------
-- Rule helpers
---------------------------------------------------------------------------

function Engine.flag(state, name: string): boolean
	for id in state.Rules.Modifiers do
		local mod = Modifiers.get(id)
		if mod and mod.Flags and mod.Flags[name] then
			return true
		end
	end
	for id in state.TrialModifiers do
		local mod = Modifiers.get(id)
		if mod and mod.Flags and mod.Flags[name] then
			return true
		end
	end
	return false
end

function Engine.number(state, name: string): number
	local total = 0
	for id in state.Rules.Modifiers do
		local mod = Modifiers.get(id)
		if mod and mod.Numbers and mod.Numbers[name] then
			total += mod.Numbers[name]
		end
	end
	for id in state.TrialModifiers do
		local mod = Modifiers.get(id)
		if mod and mod.Numbers and mod.Numbers[name] then
			total += mod.Numbers[name]
		end
	end
	return total
end

function Engine.activeModifiers(state): { string }
	local ids = {}
	for id in state.Rules.Modifiers do
		table.insert(ids, id)
	end
	for id in state.TrialModifiers do
		if not table.find(ids, id) then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

function Engine.profile(state)
	return Rules.profile(state.Rules, math.max(state.Trial, 1))
end

function Engine.capacity(state): number
	return math.max(1, state.Rules.Capacity + Engine.number(state, "ExtraCapacity"))
end

function Engine.surgeActive(state): boolean
	if state.SuddenDeath then
		return false
	end
	return Engine.profile(state).Surge == true or Engine.flag(state, "SurgeAll")
end

function Engine.cellDamage(state): number
	return math.max(1, state.Rules.BaseDamage + Engine.number(state, "BonusDamage"))
end

local function drawsPerLoad(state): number
	if state.SuddenDeath then
		return 0
	end
	local draws = state.Rules.DrawsOverride or Engine.profile(state).Draws
	draws += Engine.number(state, "ExtraDraws")
	if Engine.flag(state, "Scarcity") and draws > 0 then
		draws = math.max(1, math.floor(draws / 2))
	end
	return math.max(0, draws)
end

local function drawPool(state): { [string]: boolean }
	local pool = table.clone(state.Rules.Pool)
	if Engine.flag(state, "Lockdown") then
		pool.Clamp = nil
		pool.Overclock = nil
	end
	return pool
end

local function rareAllowed(state): boolean
	return Engine.profile(state).Rare == true or state.Rules.ChaosPerTrial > 0
end

---------------------------------------------------------------------------
-- Subjects and turn order
---------------------------------------------------------------------------

function Engine.subject(state, id: number?)
	if id == nil then
		return nil
	end
	return state.Subjects[id]
end

function Engine.nextAlive(state, fromId: number): number
	local order = state.Order
	local n = #order
	local index = table.find(order, fromId) or 0
	for step = 1, n do
		local id = order[((index + step - 1) % n) + 1]
		if not state.Subjects[id].Eliminated then
			return id
		end
	end
	return fromId
end

-- First alive subject at or after `fromId` in seat order.
local function firstAliveFrom(state, fromId: number): number
	local s = state.Subjects[fromId]
	if s and not s.Eliminated then
		return fromId
	end
	return Engine.nextAlive(state, fromId)
end

function Engine.aliveTeams(state): { [number]: boolean }
	local teams = {}
	for _, s in state.Subjects do
		if not s.Eliminated then
			teams[s.TeamId] = true
		end
	end
	return teams
end

local function countKeys(t): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

local function isOpponent(state, a, b): boolean
	if a == b then
		return false
	end
	if state.Rules.FriendlyFire then
		return true
	end
	return a.TeamId ~= b.TeamId
end
Engine.isOpponent = isOpponent

local function onlyOpponent(state, subject)
	local found = nil
	for _, other in state.Subjects do
		if not other.Eliminated and isOpponent(state, subject, other) then
			if found then
				return nil
			end
			found = other
		end
	end
	return found
end

---------------------------------------------------------------------------
-- Cells and knowledge (also used by Instruments through `E`)
---------------------------------------------------------------------------

local function newCells(state, pattern: { boolean })
	local cells = table.create(#pattern)
	for i, charged in pattern do
		cells[i] = { Uid = state.NextUid, Charged = charged, Parity = 0 }
		state.NextUid += 1
	end
	return cells
end

local function patternString(cells): string
	local chars = table.create(#cells)
	for i, cell in cells do
		chars[i] = cell.Charged and "C" or "H"
	end
	return table.concat(chars)
end

local function parsePattern(pattern: string): { boolean }?
	if type(pattern) ~= "string" or #pattern == 0 or #pattern > 16 then
		return nil
	end
	local out = {}
	for i = 1, #pattern do
		local ch = string.upper(string.sub(pattern, i, i))
		if ch == "C" then
			table.insert(out, true)
		elseif ch == "H" then
			table.insert(out, false)
		else
			return nil
		end
	end
	return out
end
Engine.parsePattern = parsePattern

-- Rolls a load composition for the current profile and modifiers.
local function rollComposition(state, size: number?): (number, number)
	local profile = Engine.profile(state)
	local rng = state.Rng
	size = size or rng:NextInteger(profile.Cells[1], profile.Cells[2])
	local lo, hi = profile.Charged[1], profile.Charged[2]
	if Engine.flag(state, "HeavyCells") then
		lo, hi = 0.55, 0.8
	elseif Engine.flag(state, "LightCells") then
		lo, hi = 0.2, 0.45
	end
	local charged
	if size <= 1 then
		charged = 1
	else
		local ratio = lo + (hi - lo) * rng:NextNumber()
		charged = math.clamp(math.floor(size * ratio + 0.5), 1, size - 1)
	end
	return size :: number, charged
end

local function shuffledPattern(rng, size: number, charged: number): { boolean }
	local pattern = table.create(size)
	for i = 1, size do
		pattern[i] = i <= charged
	end
	for i = size, 2, -1 do
		local j = rng:NextInteger(1, i)
		pattern[i], pattern[j] = pattern[j], pattern[i]
	end
	return pattern
end

function Engine.loadedCell(state)
	local load = state.Load
	if load == nil then
		return nil
	end
	return load.Cells[1]
end

function Engine.learn(_state, subject, cell)
	if cell then
		subject.Knows[cell.Uid] = true
	end
end

local function noteRemoved(load, cell)
	local original = cell.Charged
	if cell.Parity == 1 then
		original = not original
	end
	if original then
		load.RemovedCharged += 1
	else
		load.RemovedHollow += 1
	end
end

local function forgetUid(state, uid)
	for _, s in state.Subjects do
		s.Knows[uid] = nil
	end
end

-- Removes and returns the loaded cell (it becomes public knowledge).
function Engine.removeLoaded(state)
	local load = state.Load
	local cell = table.remove(load.Cells, 1)
	if cell then
		noteRemoved(load, cell)
		forgetUid(state, cell.Uid)
	end
	return cell
end

function Engine.invertLoaded(state)
	local cell = Engine.loadedCell(state)
	if cell then
		cell.Charged = not cell.Charged
		cell.Parity = 1 - cell.Parity
	end
end

function Engine.rotate(state, span: number): number
	local cells = state.Load.Cells
	local n = math.min(span, #cells)
	if n >= 2 then
		local first = table.remove(cells, 1)
		table.insert(cells, n, first)
	end
	return n
end

-- Scrambler: replaces the remaining cells with a fresh random mix of the same size.
function Engine.recast(state): (number, number)
	local load = state.Load
	local size = #load.Cells
	for _, cell in load.Cells do
		forgetUid(state, cell.Uid)
	end
	local _, charged = rollComposition(state, size)
	load.Cells = newCells(state, shuffledPattern(state.Rng, size, charged))
	load.PoolSize = size
	load.PoolCharged = charged
	load.RemovedCharged = 0
	load.RemovedHollow = 0
	load.Recasts += 1
	table.insert(state.LoadRecords, {
		Trial = state.Trial,
		Load = state.LoadNumber,
		Pattern = patternString(load.Cells),
		Recast = true,
	})
	return size, charged
end

---------------------------------------------------------------------------
-- Effects, health and instruments (also used by Instruments through `E`)
---------------------------------------------------------------------------

function Engine.setEffect(state, subject, effect: string, active: boolean)
	if subject.Effects[effect] == active then
		return
	end
	subject.Effects[effect] = active
	emit(state, "EffectChanged", { Subject = subject.Id, Effect = effect, Active = active })
end

function Engine.setTether(state, owner)
	state.Tether = { Owner = owner.Id }
	emit(state, "EffectChanged", { Subject = owner.Id, Effect = "Tether", Active = true })
end

local function clearTether(state)
	if state.Tether then
		local owner = state.Tether.Owner
		state.Tether = nil
		emit(state, "EffectChanged", { Subject = owner, Effect = "Tether", Active = false })
	end
end

function Engine.heal(state, subject, amount: number, source: string)
	if subject.Eliminated then
		return 0
	end
	local before = subject.Integrity
	subject.Integrity = math.min(subject.MaxIntegrity, subject.Integrity + amount)
	local healed = subject.Integrity - before
	subject.Stats.Healed += healed
	subject.Stats.HealUsed = true
	emit(state, "Heal", {
		Subject = subject.Id,
		Amount = healed,
		Integrity = subject.Integrity,
		Source = source,
	})
	return healed
end

local function applyDamage(state, subject, amount: number, source: string, actor, noDampen: boolean, mirrored: boolean)
	if subject.Eliminated or amount <= 0 then
		return 0
	end
	local absorbed = 0
	if not noDampen and subject.Effects.Dampener then
		absorbed = math.min(1, amount)
		amount -= absorbed
		Engine.setEffect(state, subject, "Dampener", false)
	end
	local before = subject.Integrity
	subject.Integrity = math.max(0, subject.Integrity - amount)
	local dealt = before - subject.Integrity
	subject.Stats.DamageTaken += dealt
	if source == "Shot" or source == "Tether" then
		subject.Stats.ChargedTaken += 1
	end
	if subject.Integrity > 0 then
		subject.Stats.MinIntegrity = math.min(subject.Stats.MinIntegrity, subject.Integrity)
	end
	if actor and actor ~= subject and isOpponent(state, actor, subject) then
		actor.Stats.DamageDealt += dealt
	end
	emit(state, "Damage", {
		Subject = subject.Id,
		Amount = dealt,
		Absorbed = absorbed,
		Integrity = subject.Integrity,
		Source = source,
		Mirrored = mirrored,
		Actor = actor and actor.Id or nil,
	})
	return dealt
end

local function markEliminations(state, actor)
	for _, subject in state.Subjects do
		if not subject.Eliminated and subject.Integrity <= 0 then
			subject.Eliminated = true
			table.insert(state.JustEliminated, subject.Id)
			if actor and actor ~= subject and isOpponent(state, actor, subject) then
				actor.Stats.Eliminations += 1
			end
			emit(state, "Eliminated", { Subject = subject.Id })
		end
	end
end

-- Deals damage, mirroring it through an active Tether, then resolves eliminations.
function Engine.damage(state, subject, amount: number, source: string, actor, noDampen: boolean?)
	local dealt = applyDamage(state, subject, amount, source, actor, noDampen == true, false)
	if state.Tether and amount > 0 then
		for _, other in state.Subjects do
			if other ~= subject and not other.Eliminated then
				applyDamage(state, other, amount, "Tether", actor, noDampen == true, true)
			end
		end
	end
	markEliminations(state, actor)
	return dealt
end

local function giveInstrument(state, subject, id: string): boolean
	if #subject.Instruments >= Engine.capacity(state) then
		return false
	end
	table.insert(subject.Instruments, id)
	return true
end
Engine.giveInstrument = giveInstrument

-- Deals `count` instruments to each subject in `subjects`, honouring capacity,
-- Mirror Draw and forced draws. Emits one "Dealt" event.
local function deal(state, subjects, count: number, source: string, forced)
	if count <= 0 then
		return
	end
	local pool = drawPool(state)
	local weights = state.Rules.RarityWeights
	local allowRare = rareAllowed(state)
	local draws, lost, inventories = {}, {}, {}
	local mirror = nil
	if Engine.flag(state, "MirrorDraw") then
		mirror = {}
		for i = 1, count do
			mirror[i] = Instruments.roll(state.Rng, pool, weights, allowRare)
		end
	end
	for _, subject in subjects do
		local got, dropped = {}, {}
		for i = 1, count do
			local id
			if forced and forced[subject.Id] then
				id = forced[subject.Id][i]
			elseif mirror then
				id = mirror[i]
			else
				id = Instruments.roll(state.Rng, pool, weights, allowRare)
			end
			if id then
				if giveInstrument(state, subject, id) then
					table.insert(got, id)
				else
					table.insert(dropped, id)
				end
			end
		end
		draws[subject.Id] = got
		lost[subject.Id] = dropped
		inventories[subject.Id] = table.clone(subject.Instruments)
	end
	-- Every subject gets an entry (empty if not dealt to) so the maps stay
	-- dense arrays keyed 1..n, which survive remote serialization intact.
	for _, subject in state.Subjects do
		if draws[subject.Id] == nil then
			draws[subject.Id] = {}
			lost[subject.Id] = {}
			inventories[subject.Id] = table.clone(subject.Instruments)
		end
	end
	emit(state, "Dealt", { Draws = draws, Lost = lost, Inventories = inventories, Source = source })
end

function Engine.draw(state, subject, count: number, source: string)
	deal(state, { subject }, count, source, nil)
end

function Engine.emitUse(state, user, id: string, target, outcome: { [string]: any }, private)
	local public, priv = withBeliefs(state, {
		Actor = user.Id,
		Id = id,
		Target = target and target.Id or nil,
		Outcome = outcome,
		Inventory = table.clone(user.Instruments),
	}, private)
	emit(state, "InstrumentUsed", public, priv)
end

---------------------------------------------------------------------------
-- Beliefs and views
---------------------------------------------------------------------------

function Engine.belief(state, viewerId: number?)
	local load = state.Load
	if load == nil then
		return Probability.fresh(0, 0)
	end
	local viewer = viewerId and state.Subjects[viewerId] or nil
	local track = table.create(#load.Cells)
	for i, cell in load.Cells do
		local known = nil
		if viewer and viewer.Knows[cell.Uid] then
			known = cell.Charged and "C" or "H"
		end
		track[i] = { Parity = cell.Parity, Known = known }
	end
	return {
		PoolSize = load.PoolSize,
		PoolCharged = if load.Blind then nil else load.PoolCharged,
		RemovedCharged = load.RemovedCharged,
		RemovedHollow = load.RemovedHollow,
		Track = track,
	}
end

local function publicSubject(subject)
	return {
		Id = subject.Id,
		Name = subject.Name,
		TeamId = subject.TeamId,
		IsAI = subject.IsAI,
		UserId = subject.UserId,
		Personality = subject.Personality,
		Integrity = subject.Integrity,
		MaxIntegrity = subject.MaxIntegrity,
		Instruments = table.clone(subject.Instruments),
		Effects = table.clone(subject.Effects),
		Eliminated = subject.Eliminated,
		Forfeited = subject.Forfeited,
		TrialWins = subject.TrialWins,
		Connected = subject.Connected,
	}
end
Engine.publicSubject = publicSubject

function Engine.snapshot(state, viewerId: number?)
	local subjects = {}
	for i, subject in state.Subjects do
		subjects[i] = publicSubject(subject)
	end
	return {
		MatchId = state.MatchId,
		ModeId = state.Rules.ModeId,
		Phase = state.Phase,
		Trial = state.Trial,
		TrialsToWin = state.Rules.TrialsToWin,
		LoadNumber = state.LoadNumber,
		LoadInTrial = state.LoadInTrial,
		Turn = { Owner = state.Turn.Owner, Token = state.Turn.Token },
		Subjects = subjects,
		Order = table.clone(state.Order),
		Belief = Engine.belief(state, viewerId),
		Surge = Engine.surgeActive(state),
		Blind = state.Load ~= nil and state.Load.Blind or false,
		CellDamage = Engine.cellDamage(state),
		Tether = state.Tether and state.Tether.Owner or nil,
		Modifiers = Engine.activeModifiers(state),
		Capacity = Engine.capacity(state),
		SuddenDeath = state.SuddenDeath,
		You = viewerId,
	}
end

---------------------------------------------------------------------------
-- Legal actions
---------------------------------------------------------------------------

local function checkUse(state, subject, slot: number, target)
	local id = subject.Instruments[slot]
	if id == nil then
		return false, "Empty slot.", nil
	end
	local def = Instruments.get(id)
	if def == nil then
		return false, "Unknown instrument.", nil
	end
	local used = state.Turn.UseCounts[id] or 0
	if used >= def.PerTurnLimit then
		return false, "Already used this turn.", def
	end
	if state.Turn.Actions >= state.Rules.PerTurnCap then
		return false, "Instrument limit reached this turn.", def
	end
	if def.Targeted then
		if target == nil then
			target = onlyOpponent(state, subject)
		end
		if target == nil or not isOpponent(state, subject, target) or target.Eliminated then
			return false, "Choose an opponent.", def
		end
	end
	local ok, reason = def.CanUse(state, subject, target, Engine)
	if not ok then
		return false, reason, def
	end
	return true, nil, def, target
end

-- All actions for a subject, each with Ok and a Reason when not allowed.
function Engine.legal(state, subjectId: number)
	local subject = state.Subjects[subjectId]
	local actions = {}
	if subject == nil or state.Phase ~= Phase.AwaitAction or state.Turn.Owner ~= subjectId then
		return actions
	end
	table.insert(actions, { Kind = "Fire", Target = subjectId, Ok = true })
	for _, other in state.Subjects do
		if not other.Eliminated and isOpponent(state, subject, other) then
			table.insert(actions, { Kind = "Fire", Target = other.Id, Ok = true })
		end
	end
	for slot, id in subject.Instruments do
		local def = Instruments.get(id)
		if def and def.Targeted then
			for _, other in state.Subjects do
				if not other.Eliminated and isOpponent(state, subject, other) then
					local ok, reason = checkUse(state, subject, slot, other)
					table.insert(
						actions,
						{ Kind = "Use", Slot = slot, Id = id, Target = other.Id, Ok = ok, Reason = reason }
					)
				end
			end
		else
			local ok, reason = checkUse(state, subject, slot, nil)
			table.insert(actions, { Kind = "Use", Slot = slot, Id = id, Ok = ok, Reason = reason })
		end
	end
	if state.Filter then
		for _, action in actions do
			if action.Ok ~= false then
				local ok, reason = state.Filter(state, subject, action)
				if not ok then
					action.Ok = false
					action.Reason = reason
				end
			end
		end
	end
	return actions
end

---------------------------------------------------------------------------
-- Automatic phases
---------------------------------------------------------------------------

local function beginMatch(state)
	local subjects = {}
	for i, subject in state.Subjects do
		subjects[i] = publicSubject(subject)
	end
	emit(state, "MatchStart", {
		MatchId = state.MatchId,
		ModeId = state.Rules.ModeId,
		ModeName = state.Rules.ModeName,
		TrialsToWin = state.Rules.TrialsToWin,
		Subjects = subjects,
		Order = table.clone(state.Order),
	})
	state.Phase = Phase.TrialSetup
end

local function beginTrial(state)
	state.Trial += 1
	state.SuddenDeath = false
	state.LoadInTrial = 0
	state.Load = nil
	state.TrialWinnerTeam = nil
	clearTether(state)
	state.TrialModifiers = {}
	if state.Rules.ChaosPerTrial > 0 then
		for _, id in Modifiers.rollChaos(state.Rng, state.Rules.ChaosPerTrial, state.Rules.Modifiers) do
			state.TrialModifiers[id] = true
		end
	end
	local profile = Engine.profile(state)
	local maxIntegrity = state.Rules.FixedIntegrity or profile.MaxIntegrity
	maxIntegrity = math.max(1, maxIntegrity + Engine.number(state, "IntegrityDelta"))
	local integrity, maxes = {}, {}
	for _, subject in state.Subjects do
		if not subject.Forfeited then
			subject.Eliminated = false
			subject.MaxIntegrity = maxIntegrity
			subject.Integrity = maxIntegrity
			subject.Instruments = {}
			subject.Effects = newEffects()
			subject.Knows = {}
			local carry = state.Trial == 1 and state.Rules.StartIntegrity and state.Rules.StartIntegrity[subject.Id]
			if carry then
				subject.Integrity = math.clamp(carry, 1, maxIntegrity)
			end
			local carriedTools = state.Trial == 1
				and state.Rules.StartInstruments
				and state.Rules.StartInstruments[subject.Id]
			if carriedTools then
				for _, id in carriedTools do
					if Instruments.isValid(id) then
						giveInstrument(state, subject, id)
					end
				end
			end
			subject.Stats.MinIntegrity = math.min(subject.Stats.MinIntegrity, subject.Integrity)
		end
		integrity[subject.Id] = subject.Integrity
		maxes[subject.Id] = subject.MaxIntegrity
	end
	local n = #state.Order
	state.NextStarter = firstAliveFrom(state, state.Order[((state.Trial - 1) % n) + 1])
	local inventories = {}
	for _, subject in state.Subjects do
		inventories[subject.Id] = table.clone(subject.Instruments)
	end
	emit(state, "TrialStart", {
		Trial = state.Trial,
		MaxIntegrity = maxes,
		Integrity = integrity,
		Draws = drawsPerLoad(state),
		Surge = Engine.surgeActive(state),
		Rare = rareAllowed(state),
		Modifiers = Engine.activeModifiers(state),
		TrialModifiers = (function()
			local ids = {}
			for id in state.TrialModifiers do
				table.insert(ids, id)
			end
			table.sort(ids)
			return ids
		end)(),
		Inventories = inventories,
		Starter = state.NextStarter,
		CellDamage = Engine.cellDamage(state),
		Capacity = Engine.capacity(state),
	})
	if state.Rules.StartingInstruments > 0 then
		local alive = {}
		for _, subject in state.Subjects do
			if not subject.Eliminated then
				table.insert(alive, subject)
			end
		end
		deal(state, alive, state.Rules.StartingInstruments, "TrialStart", nil)
	end
	state.Phase = Phase.LoadSetup
end

local function beginLoad(state)
	state.LoadNumber += 1
	state.LoadInTrial += 1
	local forced = state.Rules.Forced
	local pattern = nil
	if state.ForcedNext then
		pattern = parsePattern(state.ForcedNext)
		state.ForcedNext = nil
	elseif forced and forced.Loads and forced.Loads[state.LoadNumber] then
		pattern = parsePattern(forced.Loads[state.LoadNumber])
	end
	local size, charged
	if pattern then
		size = #pattern
		charged = 0
		for _, c in pattern do
			if c then
				charged += 1
			end
		end
	else
		if state.SuddenDeath then
			size, charged = 3, 1
		else
			size, charged = rollComposition(state, nil)
		end
		pattern = shuffledPattern(state.Rng, size, charged)
	end
	local cells = newCells(state, pattern)
	state.Load = {
		Number = state.LoadNumber,
		Cells = cells,
		PoolSize = size,
		PoolCharged = charged,
		RemovedCharged = 0,
		RemovedHollow = 0,
		Blind = Engine.flag(state, "Blind"),
		Recasts = 0,
	}
	table.insert(state.LoadRecords, {
		Trial = state.Trial,
		Load = state.LoadNumber,
		Pattern = patternString(cells),
		Recast = false,
	})
	for _, subject in state.Subjects do
		subject.Knows = {}
	end
	state.LoadStarter = state.NextStarter or firstAliveFrom(state, state.Order[1])
	local forcedStarter = forced and forced.Starters and forced.Starters[state.LoadNumber]
	if forcedStarter and state.Subjects[forcedStarter] and not state.Subjects[forcedStarter].Eliminated then
		state.LoadStarter = forcedStarter
	end
	state.Turn.Owner = state.LoadStarter

	-- Precision: each subject privately learns one random cell.
	local private = nil
	local reveal = state.Rules.PrecisionReveal or 0
	if reveal > 0 and not state.SuddenDeath then
		private = {}
		for _, subject in state.Subjects do
			if not subject.Eliminated then
				local options = {}
				for i = 1, #cells do
					table.insert(options, i)
				end
				local revealed = {}
				for _ = 1, math.min(reveal, #options) do
					local pick = table.remove(options, state.Rng:NextInteger(1, #options))
					subject.Knows[cells[pick].Uid] = true
					table.insert(revealed, { Index = pick, Charged = cells[pick].Charged })
				end
				private[subject.Id] = { Reveal = revealed }
			end
		end
	end
	local public, priv = withBeliefs(state, {
		Load = state.LoadNumber,
		LoadInTrial = state.LoadInTrial,
		Trial = state.Trial,
		PoolSize = size,
		PoolCharged = if state.Load.Blind then nil else charged,
		Blind = state.Load.Blind,
		Surge = Engine.surgeActive(state),
		Starter = state.LoadStarter,
		SuddenDeath = state.SuddenDeath,
	}, private)
	emit(state, "LoadStart", public, priv)

	local count = drawsPerLoad(state)
	if count > 0 then
		local alive = {}
		for _, subject in state.Subjects do
			if not subject.Eliminated then
				table.insert(alive, subject)
			end
		end
		local forcedDraws = forced and forced.Draws and forced.Draws[state.LoadNumber] or nil
		deal(state, alive, count, "Load", forcedDraws)
	elseif forced and forced.Draws and forced.Draws[state.LoadNumber] then
		local forcedDraws = forced.Draws[state.LoadNumber]
		local alive, most = {}, 0
		for _, subject in state.Subjects do
			if not subject.Eliminated and forcedDraws[subject.Id] then
				table.insert(alive, subject)
				most = math.max(most, #forcedDraws[subject.Id])
			end
		end
		deal(state, alive, most, "Load", forcedDraws)
	end
	state.Phase = Phase.TurnSetup
end

local function beginTurn(state)
	local owner = state.Subjects[state.Turn.Owner]
	if owner == nil or owner.Eliminated then
		owner = state.Subjects[Engine.nextAlive(state, state.Turn.Owner)]
	end
	if owner.Effects.Clamped then
		Engine.setEffect(state, owner, "Clamped", false)
		owner.Effects.ClampImmune = true
		emit(state, "TurnSkipped", { Subject = owner.Id, Reason = "Clamp" })
		state.Turn.Owner = Engine.nextAlive(state, owner.Id)
		return -- stay in TurnSetup; the next advance() starts the following turn
	end
	owner.Effects.ClampImmune = false
	state.Turn = {
		Owner = owner.Id,
		Token = state.Turn.Token + 1,
		Used = {},
		UseCounts = {},
		Actions = 0,
	}
	emit(state, "TurnStart", { Owner = owner.Id, Token = state.Turn.Token })
	state.Phase = Phase.AwaitAction
end

local function endLoad(state)
	emit(state, "LoadEnd", { Load = state.LoadNumber })
	for _, subject in state.Subjects do
		if subject.Effects.Dampener then
			Engine.setEffect(state, subject, "Dampener", false)
		end
		subject.Knows = {}
	end
	clearTether(state)
	state.Load = nil
	state.NextStarter = Engine.nextAlive(state, state.LoadStarter or state.Order[1])
	state.Phase = Phase.LoadSetup
end

local function endTrial(state)
	if state.PendingSuddenDeath then
		local ids = state.PendingSuddenDeath
		state.PendingSuddenDeath = nil
		for _, id in ids do
			local subject = state.Subjects[id]
			subject.Eliminated = false
			subject.MaxIntegrity = 1
			subject.Integrity = 1
			subject.Instruments = {}
			subject.Effects = newEffects()
			subject.Knows = {}
			subject.Stats.SuddenDeaths += 1
		end
		clearTether(state)
		state.SuddenDeath = true
		state.Load = nil
		state.NextStarter = Engine.nextAlive(state, state.LoadStarter or state.Order[1])
		emit(state, "SuddenDeath", { Subjects = ids, Trial = state.Trial })
		state.Phase = Phase.LoadSetup
		return
	end
	local team = state.TrialWinnerTeam
	local wins = {}
	for _, subject in state.Subjects do
		if team ~= nil and subject.TeamId == team and not subject.Forfeited then
			subject.TrialWins += 1
			subject.Stats.TrialsWon += 1
			if subject.Integrity == 1 then
				subject.Stats.ClutchTrials += 1
			end
		end
		wins[subject.Id] = subject.TrialWins
	end
	emit(state, "TrialEnd", {
		Trial = state.Trial,
		WinnerTeam = team,
		Wins = wins,
		SuddenDeath = state.SuddenDeath,
	})
	clearTether(state)
	state.Load = nil
	local matchWinner = nil
	for _, subject in state.Subjects do
		if subject.TrialWins >= state.Rules.TrialsToWin and not subject.Forfeited then
			matchWinner = subject.TeamId
		end
	end
	if matchWinner ~= nil then
		state.WinnerTeam = matchWinner
		state.EndReason = "Trials"
		state.Phase = Phase.MatchEnd
	else
		state.Phase = Phase.TrialSetup
	end
end

local function endMatch(state)
	local winners = {}
	for _, subject in state.Subjects do
		if state.WinnerTeam ~= nil and subject.TeamId == state.WinnerTeam then
			table.insert(winners, subject.Id)
		end
	end
	emit(state, "MatchEnd", {
		WinnerTeam = state.WinnerTeam,
		Winners = winners,
		Reason = state.EndReason or "Trials",
		Trials = state.Trial,
	})
	state.Phase = Phase.Ended
end

-- Performs one automatic step. Does nothing while waiting for a subject.
function Engine.advance(state)
	local phase = state.Phase
	if phase == Phase.Created then
		beginMatch(state)
	elseif phase == Phase.TrialSetup then
		beginTrial(state)
	elseif phase == Phase.LoadSetup then
		beginLoad(state)
	elseif phase == Phase.TurnSetup then
		beginTurn(state)
	elseif phase == Phase.LoadEnd then
		endLoad(state)
	elseif phase == Phase.TrialEnd then
		endTrial(state)
	elseif phase == Phase.MatchEnd then
		endMatch(state)
	end
	return flush(state)
end

---------------------------------------------------------------------------
-- Resolution after an action
---------------------------------------------------------------------------

local function resolve(state, actor, keepTurn: boolean)
	local teams = Engine.aliveTeams(state)
	local teamCount = countKeys(teams)
	if teamCount == 0 then
		-- Everyone left standing fell at once (only possible through a Tether).
		if state.Rules.SuddenDeath and #state.JustEliminated >= 2 then
			state.PendingSuddenDeath = table.clone(state.JustEliminated)
			state.TrialWinnerTeam = nil
		else
			state.TrialWinnerTeam = actor.TeamId
		end
		state.Phase = Phase.TrialEnd
		return
	end
	if teamCount == 1 then
		state.TrialWinnerTeam = next(teams)
		state.Phase = Phase.TrialEnd
		return
	end
	if state.Load == nil or #state.Load.Cells == 0 then
		state.Phase = Phase.LoadEnd
		return
	end
	if keepTurn and not actor.Eliminated then
		state.Turn.Token += 1
		emit(state, "TurnContinue", { Owner = actor.Id, Token = state.Turn.Token })
		state.Phase = Phase.AwaitAction
		return
	end
	state.Turn.Owner = Engine.nextAlive(state, actor.Id)
	state.Phase = Phase.TurnSetup
end

local function tension(state, actor, target, publicP: number): number
	local t = 0.25 + 0.45 * (1 - math.abs(2 * publicP - 1))
	local damage = Engine.cellDamage(state) * (actor.Effects.Capacitor and 2 or 1)
	if target.Integrity <= damage then
		t += 0.25
	end
	for _, subject in state.Subjects do
		if subject.TrialWins == state.Rules.TrialsToWin - 1 then
			t += 0.1
			break
		end
	end
	return math.clamp(t, 0, 1)
end

local function hasUsed(state, id: string): boolean
	return table.find(state.Turn.Used, id) ~= nil
end

local function countUsed(state, id: string): number
	local n = 0
	for _, used in state.Turn.Used do
		if used == id then
			n += 1
		end
	end
	return n
end

local function addCombo(subject, name: string)
	subject.Stats.Combos[name] = (subject.Stats.Combos[name] or 0) + 1
end

local function fire(state, actor, target, isTimeout: boolean)
	local load = state.Load
	local actorP = Probability.current(Engine.belief(state, actor.Id))
	local publicP = Probability.current(Engine.belief(state, nil))
	emit(state, "FireCommit", {
		Actor = actor.Id,
		Target = target.Id,
		Tension = tension(state, actor, target, publicP),
		Timeout = isTimeout,
	})

	local cell = Engine.removeLoaded(state)
	local isLast = #load.Cells == 0
	local surge = isLast and Engine.surgeActive(state)
	local capacitor = actor.Effects.Capacitor
	local overclock = actor.Effects.Overclock
	local damage = 0
	if cell.Charged then
		damage = Engine.cellDamage(state)
		if capacitor then
			damage *= 2
		end
		if surge then
			damage += 1
		end
	end
	if capacitor then
		Engine.setEffect(state, actor, "Capacitor", false)
	end
	if overclock then
		Engine.setEffect(state, actor, "Overclock", false)
	end
	local selfShot = target == actor
	local keep = (selfShot and not cell.Charged) or overclock

	local public, private = withBeliefs(state, {
		Actor = actor.Id,
		Target = target.Id,
		Charged = cell.Charged,
		Damage = damage,
		Kept = keep,
		Surge = surge and cell.Charged,
		Capacitor = capacitor,
		Overclock = overclock,
		Remaining = #load.Cells,
	}, nil)
	emit(state, "FireResult", public, private)

	local targetIntegrityBefore = target.Integrity
	if cell.Charged then
		Engine.damage(state, target, damage, "Shot", actor, false)
	end

	-- Echo modifier: surviving a shot at yourself reveals the next loaded cell.
	if selfShot and not cell.Charged and Engine.flag(state, "Echo") and #load.Cells > 0 and not actor.Eliminated then
		local nextCell = load.Cells[1]
		Engine.learn(state, actor, nextCell)
		local pub, priv = withBeliefs(state, { Subject = actor.Id }, {
			[actor.Id] = { Reveal = { { Index = 1, Charged = nextCell.Charged } } },
		})
		emit(state, "Echo", pub, priv)
	end

	-- Statistics
	local stats = actor.Stats
	stats.Shots += 1
	if selfShot then
		stats.ShotsSelf += 1
	else
		stats.ShotsOther += 1
	end
	local read = (selfShot and not cell.Charged) or (not selfShot and cell.Charged)
	if read then
		stats.Reads += 1
	end
	if selfShot then
		if not cell.Charged then
			stats.SelfSurvived += 1
			stats.BestRisk = math.max(stats.BestRisk, actorP)
			if actorP >= 0.5 then
				stats.RiskySurvived += 1
				stats.RiskyStreak += 1
				stats.MaxRiskyStreak = math.max(stats.MaxRiskyStreak, stats.RiskyStreak)
			end
		else
			stats.RiskyStreak = 0
		end
	end
	if Probability.isCertain(actorP) then
		stats.CertainDecisions += 1
		if (actorP >= 0.5 and selfShot) or (actorP < 0.5 and not selfShot and not overclock) then
			stats.CertainMistakes += 1
		end
	end
	if not selfShot and cell.Charged and actorP <= 0.25 then
		stats.LowShotHits += 1
		if targetIntegrityBefore > 0 and target.Integrity <= 0 then
			stats.LethalLowShot = true
		end
	end
	if not selfShot and cell.Charged and hasUsed(state, "Lens") and hasUsed(state, "Capacitor") then
		addCombo(actor, "LensCapacitor")
	end
	if selfShot and not cell.Charged and hasUsed(state, "Inverter") then
		addCombo(actor, "InverterSelf")
	end
	if read and hasUsed(state, "Sonar") and hasUsed(state, "Rotor") then
		addCombo(actor, "SonarRotor")
	end
	if countUsed(state, "Ejector") >= 2 then
		addCombo(actor, "EjectorChain")
	end
	if not selfShot and cell.Charged and capacitor and surge then
		addCombo(actor, "SurgeCapacitor")
	end
	if isTimeout then
		stats.Timeouts += 1
	end

	table.insert(state.Log, {
		Kind = "Fire",
		Trial = state.Trial,
		Load = state.LoadNumber,
		Actor = actor.Id,
		Target = target.Id,
		PublicP = publicP,
		ActorP = actorP,
		Charged = cell.Charged,
		Damage = if cell.Charged then damage else 0,
		Kept = keep,
		Timeout = isTimeout,
		Used = table.clone(state.Turn.Used),
		Lethal = cell.Charged and targetIntegrityBefore > 0 and target.Integrity <= 0,
	})
	resolve(state, actor, keep)
end

local function use(state, actor, slot: number, def, target)
	local id = def.Id
	if not state.Rules.InfiniteInstruments then
		table.remove(actor.Instruments, slot)
	end
	state.Turn.UseCounts[id] = (state.Turn.UseCounts[id] or 0) + 1
	state.Turn.Actions += 1
	table.insert(state.Turn.Used, id)
	local stats = actor.Stats
	stats.Instruments[id] = (stats.Instruments[id] or 0) + 1
	stats.InstrumentCount += 1
	if hasUsed(state, "Tether") and hasUsed(state, "PowerTap") and (id == "Tether" or id == "PowerTap") then
		addCombo(actor, "TetherTap")
	end
	def.Apply(state, actor, target, Engine)
	table.insert(state.Log, {
		Kind = "Use",
		Trial = state.Trial,
		Load = state.LoadNumber,
		Actor = actor.Id,
		Id = id,
		Target = target and target.Id or nil,
	})
	resolve(state, actor, true)
end

---------------------------------------------------------------------------
-- Subject input
---------------------------------------------------------------------------

-- Validates and applies one action from `subjectId`. `token` must match the
-- current turn token (it changes after every accepted action), which rejects
-- duplicate clicks and anything sent against a state the client hadn't seen.
function Engine.act(state, subjectId: number, action: any, token: number?, bypassFilter: boolean?)
	state._events = {}
	state.JustEliminated = {}
	if state.Phase ~= Phase.AwaitAction then
		return false, Engine.Reject.NotAccepting, {}
	end
	local actor = state.Subjects[subjectId]
	if actor == nil or state.Turn.Owner ~= subjectId or actor.Eliminated then
		return false, Engine.Reject.NotYourTurn, {}
	end
	if token ~= nil and token ~= state.Turn.Token then
		return false, Engine.Reject.Stale, {}
	end
	if type(action) ~= "table" then
		return false, Engine.Reject.BadAction, {}
	end
	if state.Filter and not bypassFilter then
		local ok, reason = state.Filter(state, actor, action)
		if not ok then
			return false, reason or Engine.Reject.Blocked, {}
		end
	end
	if action.Kind == "Fire" then
		local target = state.Subjects[action.Target]
		if target == nil or target.Eliminated then
			return false, Engine.Reject.BadTarget, {}
		end
		if target ~= actor and not isOpponent(state, actor, target) then
			return false, Engine.Reject.BadTarget, {}
		end
		fire(state, actor, target, action.Timeout == true)
		return true, nil, flush(state)
	elseif action.Kind == "Use" then
		local slot = action.Slot
		if type(slot) ~= "number" or slot ~= math.floor(slot) or slot < 1 or slot > #actor.Instruments then
			return false, Engine.Reject.BadSlot, {}
		end
		local target = action.Target and state.Subjects[action.Target] or nil
		if action.Target ~= nil and target == nil then
			return false, Engine.Reject.BadTarget, {}
		end
		local ok, reason, def, resolvedTarget = checkUse(state, actor, slot, target)
		if not ok then
			return false, reason or Engine.Reject.Disabled, {}
		end
		use(state, actor, slot, def, resolvedTarget)
		return true, nil, flush(state)
	end
	return false, Engine.Reject.BadAction, {}
end

-- The turn timer ran out: the Arbiter fires at the undecided subject.
function Engine.timeout(state)
	if state.Phase ~= Phase.AwaitAction then
		return {}
	end
	local owner = state.Turn.Owner
	local subject = state.Subjects[owner]
	local target = owner
	if state.Rules.TimeoutAction == "Opponent" then
		local opp = onlyOpponent(state, subject)
		if opp then
			target = opp.Id
		end
	end
	local _, _, events = Engine.act(state, owner, { Kind = "Fire", Target = target, Timeout = true }, nil, true)
	table.insert(events, 1, { Type = "Timeout", Public = { Subject = owner } })
	return events
end

-- Removes a subject from the match (left, abandoned, AFK). Safe in any phase.
function Engine.forfeit(state, subjectId: number, reason: string?)
	state._events = {}
	local subject = state.Subjects[subjectId]
	if subject == nil or subject.Forfeited or state.Phase == Phase.Ended or state.Phase == Phase.MatchEnd then
		return {}
	end
	subject.Forfeited = true
	subject.Eliminated = true
	subject.Integrity = 0
	subject.Connected = false
	emit(state, "Forfeit", { Subject = subjectId, Reason = reason or "Left" })

	local remaining = {}
	for _, s in state.Subjects do
		if not s.Forfeited then
			remaining[s.TeamId] = true
		end
	end
	local count = countKeys(remaining)
	if count <= 1 then
		state.WinnerTeam = next(remaining)
		state.EndReason = "Forfeit"
		state.Phase = Phase.MatchEnd
		return flush(state)
	end
	local alive = Engine.aliveTeams(state)
	if countKeys(alive) == 1 and state.Phase ~= Phase.TrialEnd then
		state.TrialWinnerTeam = next(alive)
		state.Phase = Phase.TrialEnd
	elseif state.Turn.Owner == subjectId and (state.Phase == Phase.AwaitAction or state.Phase == Phase.TurnSetup) then
		state.Turn.Owner = Engine.nextAlive(state, subjectId)
		state.Phase = Phase.TurnSetup
	end
	return flush(state)
end

---------------------------------------------------------------------------
-- AI view: everything a subject in this seat may legitimately know.
---------------------------------------------------------------------------

function Engine.aiView(state, subjectId: number)
	local me = state.Subjects[subjectId]
	local opponents = {}
	for _, other in state.Subjects do
		if other ~= me and not other.Eliminated and isOpponent(state, me, other) then
			table.insert(opponents, publicSubject(other))
		end
	end
	local profile = Engine.profile(state)
	return {
		Me = publicSubject(me),
		Opponents = opponents,
		Belief = Engine.belief(state, subjectId),
		Trial = state.Trial,
		TrialsToWin = state.Rules.TrialsToWin,
		Profile = profile,
		Capacity = Engine.capacity(state),
		CellDamage = Engine.cellDamage(state),
		Surge = Engine.surgeActive(state),
		Tether = state.Tether ~= nil,
		Draws = drawsPerLoad(state),
		Used = table.clone(state.Turn.Used),
		UseCounts = table.clone(state.Turn.UseCounts),
		LoadStarter = state.LoadStarter,
		NextStarter = Engine.nextAlive(state, state.LoadStarter or subjectId),
		SuddenDeath = state.SuddenDeath,
		Legal = Engine.legal(state, subjectId),
		Rules = {
			BaseDamage = state.Rules.BaseDamage,
			Profiles = state.Rules.Profiles,
			TrialsToWin = state.Rules.TrialsToWin,
			FixedIntegrity = state.Rules.FixedIntegrity,
		},
	}
end

---------------------------------------------------------------------------
-- Developer hooks (only reachable through DebugService permission checks)
---------------------------------------------------------------------------

-- Replaces the remaining cells with a pattern like "CHHC" (charged/hollow).
function Engine.debugSetSequence(state, pattern: string): boolean
	local parsed = parsePattern(pattern)
	if parsed == nil or state.Load == nil then
		return false
	end
	for _, cell in state.Load.Cells do
		forgetUid(state, cell.Uid)
	end
	local charged = 0
	for _, c in parsed do
		if c then
			charged += 1
		end
	end
	state.Load.Cells = newCells(state, parsed)
	state.Load.PoolSize = #parsed
	state.Load.PoolCharged = charged
	state.Load.RemovedCharged = 0
	state.Load.RemovedHollow = 0
	return true
end

function Engine.debugSetIntegrity(state, subjectId: number, value: number): boolean
	local subject = state.Subjects[subjectId]
	if subject == nil then
		return false
	end
	subject.MaxIntegrity = math.max(subject.MaxIntegrity, value)
	subject.Integrity = math.clamp(value, 0, subject.MaxIntegrity)
	return true
end

function Engine.debugGive(state, subjectId: number, id: string): boolean
	local subject = state.Subjects[subjectId]
	if subject == nil or not Instruments.isValid(id) then
		return false
	end
	return giveInstrument(state, subject, id)
end

-- Ends the current Trial in favour of `teamId` at the next safe step.
function Engine.debugEndTrial(state, teamId: number): boolean
	if state.Phase == Phase.Ended or state.Phase == Phase.MatchEnd then
		return false
	end
	state.TrialWinnerTeam = teamId
	state.Phase = Phase.TrialEnd
	return true
end

function Engine.debugEndLoad(state): boolean
	if state.Load == nil then
		return false
	end
	state.Load.Cells = {}
	state.Phase = Phase.LoadEnd
	return true
end

return Engine

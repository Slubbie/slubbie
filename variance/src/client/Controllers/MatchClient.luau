-- The client's view of the match it is in (or watching).
--
-- Holds the scene (who is at the table, rules, room) and a live state that is
-- rebuilt from snapshots and advanced by each engine event, exactly as the
-- server sent it for this viewer (public data plus our own private knowledge).
-- Events carry sequence numbers: a gap triggers a full resync through
-- Match.Sync, and duplicates (e.g. spectator events that arrive after a fresh
-- snapshot) are ignored.
--
-- Acting: act() attaches the current turn token and, for instruments, the id
-- the HUD showed, so the server can reject anything sent against a stale view.
-- Only one action is in flight at a time; the lock clears on the next turn
-- message or a rejection.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Probability = require(ReplicatedStorage.Variance.Core.Probability)
local Signal = require(ReplicatedStorage.Variance.Util.Signal)

local MatchClient = {}

MatchClient.Began = Signal.new() -- (scene)
MatchClient.Event = Signal.new() -- (type, data)
MatchClient.Resynced = Signal.new() -- (state)
MatchClient.Turn = Signal.new() -- (turn)
MatchClient.Rejected = Signal.new() -- (reason)
MatchClient.Presence = Signal.new()
MatchClient.Dialogue = Signal.new()
MatchClient.Ambient = Signal.new()
MatchClient.Emote = Signal.new()
MatchClient.PostMatch = Signal.new()
MatchClient.Rematch = Signal.new()
MatchClient.Ended = Signal.new() -- (data)
MatchClient.Changed = Signal.new() -- any state change (HUD refresh)

MatchClient.Scene = nil :: { [string]: any }?
MatchClient.State = nil :: { [string]: any }?
MatchClient.TurnInfo = nil :: { [string]: any }?
MatchClient.PostData = nil :: { [string]: any }?

local lastSeq = 0
local syncing = false
local pending: { [string]: any }? = nil
local pendingSince = 0

local REJECT_TEXT = {
	busy = "Wait for the Arbiter to settle.",
	stale = "That changed a moment ago. Try again.",
	not_your_turn = "It isn't your turn.",
	not_accepting = "Not now.",
	ended = "The Trial has ended.",
	bad_target = "Choose a valid target.",
	bad_slot = "That instrument is gone.",
	bad_action = "Not a valid action.",
	disabled = "You can't use that now.",
	limit = "Instrument limit reached this turn.",
	blocked = "Not allowed right now.",
}

function MatchClient:Init(controllers)
	self.Controllers = controllers
end

function MatchClient:active(): boolean
	return MatchClient.Scene ~= nil
end

function MatchClient:you(): number?
	local scene = MatchClient.Scene
	return scene and scene.You or nil
end

function MatchClient:spectating(): boolean
	local scene = MatchClient.Scene
	return scene ~= nil and scene.Spectating == true
end

function MatchClient:subject(id: number?): { [string]: any }?
	local state = MatchClient.State
	return state and id and state.Subjects[id] or nil
end

-- Static info for a subject (name, look, surrogate, seat).
function MatchClient:info(id: number?): { [string]: any }?
	local scene = MatchClient.Scene
	return scene and id and scene.Subjects[id] or nil
end

function MatchClient:isMyTurn(): boolean
	local state, turn = MatchClient.State, MatchClient.TurnInfo
	local you = self:you()
	return state ~= nil and turn ~= nil and you ~= nil and turn.Owner == you and state.Phase == "AwaitAction"
end

-- Chance the loaded cell is CHARGED from this viewer's knowledge (nil if no load).
function MatchClient:probability(): number?
	local state = MatchClient.State
	if state == nil or state.Belief == nil or #state.Belief.Track == 0 then
		return nil
	end
	return Probability.current(state.Belief)
end

function MatchClient:opponents(): { number }
	local state = MatchClient.State
	local you = self:you()
	local out = {}
	if state == nil then
		return out
	end
	local myTeam = you and state.Subjects[you] and state.Subjects[you].TeamId
	for id, s in state.Subjects do
		if id ~= you and not s.Eliminated and (myTeam == nil or s.TeamId ~= myTeam) then
			table.insert(out, id)
		end
	end
	table.sort(out)
	return out
end

-- The legal-action entry for an action, if the server sent our legal set.
function MatchClient:legal(kind: string, slot: number?, target: number?): { [string]: any }?
	local turn = MatchClient.TurnInfo
	if turn == nil or turn.Legal == nil then
		return nil
	end
	for _, action in turn.Legal do
		if action.Kind == kind and (slot == nil or action.Slot == slot) and (target == nil or action.Target == nil or action.Target == target) then
			return action
		end
	end
	return nil
end

function MatchClient:busy(): boolean
	return pending ~= nil and os.clock() - pendingSince < 6
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local function fromSnapshot(snap)
	local subjects = {}
	for i, s in snap.Subjects do
		local copy = table.clone(s)
		copy.Instruments = table.clone(s.Instruments or {})
		copy.Effects = table.clone(s.Effects or {})
		subjects[i] = copy
	end
	return {
		Phase = snap.Phase,
		Trial = snap.Trial,
		TrialsToWin = snap.TrialsToWin,
		LoadNumber = snap.LoadNumber,
		LoadInTrial = snap.LoadInTrial,
		Turn = table.clone(snap.Turn or {}),
		Subjects = subjects,
		Order = snap.Order,
		Belief = snap.Belief,
		Surge = snap.Surge,
		Blind = snap.Blind,
		CellDamage = snap.CellDamage or 1,
		Tether = snap.Tether,
		Modifiers = snap.Modifiers or {},
		Capacity = snap.Capacity,
		SuddenDeath = snap.SuddenDeath,
		Connected = snap.Connected or {},
		Spent = {},
		Log = {},
	}
end

local function log(state, entry)
	table.insert(state.Log, entry)
	if #state.Log > 60 then
		table.remove(state.Log, 1)
	end
end

-- Advances the local state by one event.
local function apply(state, kind: string, data)
	if data.Belief then
		state.Belief = data.Belief
	end
	local subjects = state.Subjects
	if kind == "MatchStart" then
		for i, s in data.Subjects or {} do
			local copy = table.clone(s)
			copy.Instruments = table.clone(s.Instruments or {})
			copy.Effects = table.clone(s.Effects or {})
			subjects[i] = copy
		end
		state.Order = data.Order
		state.Phase = "TrialSetup"
	elseif kind == "TrialStart" then
		state.Trial = data.Trial
		state.Surge = data.Surge
		state.CellDamage = data.CellDamage or 1
		state.Capacity = data.Capacity
		state.Modifiers = data.Modifiers or state.Modifiers
		state.TrialModifiers = data.TrialModifiers
		state.SuddenDeath = false
		state.Tether = nil
		state.Belief = nil
		state.Spent = {}
		for id, s in subjects do
			if not s.Forfeited then
				s.Eliminated = false
				s.MaxIntegrity = data.MaxIntegrity[id] or s.MaxIntegrity
				s.Integrity = data.Integrity[id] or s.MaxIntegrity
				s.Effects = {}
			end
			s.Instruments = data.Inventories and data.Inventories[id] or {}
		end
		state.Phase = "LoadSetup"
	elseif kind == "LoadStart" then
		state.LoadNumber = data.Load
		state.LoadInTrial = data.LoadInTrial
		state.Blind = data.Blind
		state.Surge = data.Surge
		state.SuddenDeath = data.SuddenDeath
		state.Spent = {}
		state.Phase = "TurnSetup"
		log(state, { Kind = "Load", Size = data.PoolSize, Charged = data.PoolCharged, Blind = data.Blind })
	elseif kind == "Dealt" then
		for id, list in data.Inventories or {} do
			if subjects[id] then
				subjects[id].Instruments = table.clone(list)
			end
		end
	elseif kind == "TurnStart" or kind == "TurnContinue" then
		state.Turn = { Owner = data.Owner, Token = data.Token }
		state.Phase = "AwaitAction"
	elseif kind == "TurnSkipped" then
		log(state, { Kind = "Skipped", Subject = data.Subject })
	elseif kind == "InstrumentUsed" then
		local actor = subjects[data.Actor]
		if actor and data.Inventory then
			actor.Instruments = table.clone(data.Inventory)
		end
		if data.Id == "Ejector" and data.Outcome then
			table.insert(state.Spent, data.Outcome.Charged and "C" or "H")
		end
		log(state, { Kind = "Use", Actor = data.Actor, Id = data.Id, Target = data.Target, Outcome = data.Outcome })
		state.Phase = "Resolving"
	elseif kind == "FireCommit" then
		state.Phase = "Resolving"
		state.Firing = { Actor = data.Actor, Target = data.Target, Tension = data.Tension }
	elseif kind == "FireResult" then
		state.Firing = nil
		table.insert(state.Spent, data.Charged and "C" or "H")
		log(state, { Kind = "Fire", Actor = data.Actor, Target = data.Target, Charged = data.Charged, Damage = data.Damage })
	elseif kind == "Damage" or kind == "Heal" then
		local s = subjects[data.Subject]
		if s then
			s.Integrity = data.Integrity
		end
	elseif kind == "Eliminated" then
		local s = subjects[data.Subject]
		if s then
			s.Eliminated = true
		end
		log(state, { Kind = "Eliminated", Subject = data.Subject })
	elseif kind == "EffectChanged" then
		local s = subjects[data.Subject]
		if data.Effect == "Tether" then
			state.Tether = if data.Active then data.Subject else nil
		elseif s then
			s.Effects[data.Effect] = data.Active or nil
		end
	elseif kind == "LoadEnd" then
		state.Belief = nil
		state.Tether = nil
		state.Phase = "LoadSetup"
	elseif kind == "TrialEnd" then
		for id, wins in data.Wins or {} do
			if subjects[id] then
				subjects[id].TrialWins = wins
			end
		end
		state.Belief = nil
		state.Phase = "TrialSetup"
		log(state, { Kind = "Trial", Trial = data.Trial, WinnerTeam = data.WinnerTeam })
	elseif kind == "SuddenDeath" then
		for _, id in data.Subjects or {} do
			local s = subjects[id]
			if s then
				s.Eliminated = false
				s.MaxIntegrity = 1
				s.Integrity = 1
				s.Instruments = {}
				s.Effects = {}
			end
		end
		state.SuddenDeath = true
		state.Tether = nil
		state.Phase = "LoadSetup"
	elseif kind == "MatchEnd" then
		state.Phase = "Ended"
		state.WinnerTeam = data.WinnerTeam
		state.Winners = data.Winners
	elseif kind == "Forfeit" then
		local s = subjects[data.Subject]
		if s then
			s.Forfeited = true
			s.Eliminated = true
		end
		log(state, { Kind = "Forfeit", Subject = data.Subject, Reason = data.Reason })
	elseif kind == "Timeout" then
		log(state, { Kind = "Timeout", Subject = data.Subject })
	end
end

---------------------------------------------------------------------------
-- Protocol
---------------------------------------------------------------------------

function MatchClient:begin(payload)
	MatchClient.Scene = {
		MatchId = payload.MatchId,
		ModeId = payload.ModeId,
		ModeName = payload.ModeName,
		Arena = payload.Arena,
		Environment = payload.Environment,
		Origin = payload.Origin,
		You = payload.You,
		Subjects = payload.Subjects,
		Rules = payload.Rules,
		Info = payload.Info or {},
		Spectating = payload.Spectating == true,
		RankedPreview = payload.RankedPreview,
	}
	MatchClient.State = fromSnapshot(payload.Snapshot)
	MatchClient.TurnInfo = nil
	MatchClient.PostData = nil
	lastSeq = payload.Snapshot.Seq or 0
	pending = nil
	MatchClient.Began:Fire(MatchClient.Scene)
	MatchClient.Changed:Fire()
end

function MatchClient:resync()
	if syncing then
		return
	end
	syncing = true
	task.spawn(function()
		local ok, payload = self.Controllers.NetworkClient:request("Match.Sync")
		syncing = false
		if ok and type(payload) == "table" and payload.Snapshot then
			if MatchClient.Scene and MatchClient.Scene.MatchId == payload.MatchId then
				MatchClient.State = fromSnapshot(payload.Snapshot)
				lastSeq = payload.Snapshot.Seq or lastSeq
				MatchClient.Resynced:Fire(MatchClient.State)
				MatchClient.Changed:Fire()
			else
				self:begin(payload)
			end
		end
	end)
end

local function onEvent(self, message)
	local state = MatchClient.State
	if state == nil or type(message) ~= "table" then
		return
	end
	local seq = message.Seq or 0
	if seq <= lastSeq then
		return -- already reflected in our snapshot
	end
	if seq > lastSeq + 1 and lastSeq > 0 then
		warn(string.format("[VARIANCE/Match] event gap %d -> %d; resyncing", lastSeq, seq))
		lastSeq = seq
		self:resync()
		return
	end
	lastSeq = seq
	local data = message.Data or {}
	apply(state, message.Type, data)
	MatchClient.Event:Fire(message.Type, data)
	MatchClient.Changed:Fire()
end

-- Sends a gameplay action. kind "Fire" (target) or "Use" (slot, optional target).
function MatchClient:act(kind: string, target: number?, slot: number?): (boolean, string?)
	local turn = MatchClient.TurnInfo
	local state = MatchClient.State
	if turn == nil or state == nil or not self:isMyTurn() then
		return false, "It isn't your turn."
	end
	if self:busy() then
		return false, "Wait for the Arbiter to settle."
	end
	local payload = { Kind = kind, Target = target, Slot = slot, Token = turn.Token }
	if kind == "Use" and slot then
		local me = state.Subjects[self:you() :: number]
		payload.Id = me and me.Instruments[slot]
	end
	pending = payload
	pendingSince = os.clock()
	self.Controllers.NetworkClient:act(payload)
	MatchClient.Changed:Fire()
	return true
end

function MatchClient:rejectText(reason: string?): string
	return REJECT_TEXT[reason or ""] or tostring(reason or "Not allowed.")
end

function MatchClient:clear()
	MatchClient.Scene = nil
	MatchClient.State = nil
	MatchClient.TurnInfo = nil
	pending = nil
	lastSeq = 0
	MatchClient.Changed:Fire()
end

function MatchClient:Start()
	local network = self.Controllers.NetworkClient
	network:onMatch("Begin", function(payload)
		self:begin(payload)
	end)
	network:onMatch("Event", function(message)
		onEvent(self, message)
	end)
	network:onMatch("Snapshot", function(snap)
		if MatchClient.Scene == nil or type(snap) ~= "table" then
			return
		end
		if (snap.Seq or 0) < lastSeq then
			return -- older than what we've already applied (spectator delay)
		end
		local log = MatchClient.State and MatchClient.State.Log or {}
		local spent = MatchClient.State and MatchClient.State.Spent or {}
		MatchClient.State = fromSnapshot(snap)
		MatchClient.State.Log = log
		MatchClient.State.Spent = spent
		lastSeq = snap.Seq or lastSeq
		MatchClient.Changed:Fire()
	end)
	network:onMatch("Turn", function(turn)
		MatchClient.TurnInfo = turn
		pending = nil
		local state = MatchClient.State
		if state then
			state.Turn = { Owner = turn.Owner, Token = turn.Token }
			state.Phase = "AwaitAction"
		end
		MatchClient.Turn:Fire(turn)
		MatchClient.Changed:Fire()
	end)
	network:onMatch("Rejected", function(data)
		pending = nil
		MatchClient.Rejected:Fire(data and data.Reason)
		MatchClient.Changed:Fire()
	end)
	network:onMatch("Presence", function(data)
		local state = MatchClient.State
		if state and data.Subject then
			state.Connected[data.Subject] = data.Connected
		end
		MatchClient.Presence:Fire(data)
		MatchClient.Changed:Fire()
	end)
	network:onMatch("Dialogue", function(data)
		MatchClient.Dialogue:Fire(data)
	end)
	network:onMatch("Ambient", function(data)
		MatchClient.Ambient:Fire(data)
	end)
	network:onMatch("Emote", function(data)
		MatchClient.Emote:Fire(data)
	end)
	network:onMatch("PostMatch", function(data)
		MatchClient.PostData = data
		MatchClient.PostMatch:Fire(data)
	end)
	network:onMatch("Rematch", function(data)
		MatchClient.Rematch:Fire(data)
	end)
	network:onMatch("End", function(data)
		local scene = MatchClient.Scene
		if scene and data and data.MatchId and data.MatchId ~= scene.MatchId then
			return -- a stale end for a match we've already left (rematch handover)
		end
		MatchClient.Ended:Fire(data)
		self:clear()
	end)
end

return MatchClient

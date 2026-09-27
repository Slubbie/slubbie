-- Per-recipient routing of match traffic.
--
-- Engine events carry a Public payload and optional Private payloads keyed by
-- subject id. Each participant receives Public merged with their own Private
-- entry and nothing else; spectators receive Public only, delayed in
-- competitive matches so a watcher can't relay anything useful in real time.
-- Engine events are numbered (Seq) so a client can detect a gap and resync.
--
-- Match remote kinds sent to clients:
--   Begin     scene + first snapshot (also on rejoin / spectate)
--   Event     one engine event            { Seq, Type, Data, Time }
--   Snapshot  full redacted state for this viewer
--   Turn      whose turn, token, timer    { Owner, Token, Duration, EndsAt, Legal? }
--   Dialogue, Ambient, Presence, Emote, Rejected, PostMatch, Rematch, End

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Engine = require(ReplicatedStorage.Variance.Core.Engine)

local Dispatcher = {}
Dispatcher.__index = Dispatcher

function Dispatcher.new(match, network)
	return setmetatable({
		match = match,
		network = network,
		seq = 0,
	}, Dispatcher)
end

local function merge(public: { [string]: any }, private: { [string]: any }?): { [string]: any }
	local out = table.clone(public)
	if private then
		for k, v in private do
			out[k] = v
		end
	end
	return out
end

function Dispatcher:spectatorDelay(): number
	return self.match.State.Rules.SpectatorDelay or 0
end

-- Sends to spectators, honouring the competitive delay.
function Dispatcher:toSpectators(kind: string, data: any)
	local delay = self:spectatorDelay()
	local function send()
		for player in self.match.Spectators do
			if player.Parent then
				self.network:match(player, kind, data)
			end
		end
	end
	if delay > 0 then
		task.delay(delay, send)
	else
		send()
	end
end

-- Connected human participants: { {Player, SubjectId} }.
function Dispatcher:recipients()
	local out = {}
	for id, p in self.match.Participants do
		if p.Kind == "Player" and p.Player and p.Connected and p.Player.Parent then
			table.insert(out, { Player = p.Player, Subject = id })
		end
	end
	return out
end

-- Sends one engine event.
function Dispatcher:send(event)
	self.seq += 1
	local time = workspace:GetServerTimeNow()
	for _, r in self:recipients() do
		local private = event.Private and event.Private[r.Subject] or nil
		self.network:match(r.Player, "Event", {
			Seq = self.seq,
			Type = event.Type,
			Data = merge(event.Public, private),
			Time = time,
		})
	end
	if next(self.match.Spectators) then
		self:toSpectators("Event", { Seq = self.seq, Type = event.Type, Data = event.Public, Time = time })
	end
end

-- Sends a non-engine message to every participant and spectator.
function Dispatcher:broadcast(kind: string, data: any, skipDelay: boolean?)
	for _, r in self:recipients() do
		self.network:match(r.Player, kind, data)
	end
	if next(self.match.Spectators) then
		if skipDelay then
			for player in self.match.Spectators do
				if player.Parent then
					self.network:match(player, kind, data)
				end
			end
		else
			self:toSpectators(kind, data)
		end
	end
end

-- Announces whose turn it is. The acting subject also receives their legal
-- actions (with the reason each unavailable one is disabled), so the HUD never
-- has to guess at rules it can't see.
function Dispatcher:turn(data: { [string]: any })
	local state = self.match.State
	for _, r in self:recipients() do
		if r.Subject == data.Owner then
			local mine = table.clone(data)
			mine.Legal = Engine.legal(state, r.Subject)
			self.network:match(r.Player, "Turn", mine)
		else
			self.network:match(r.Player, "Turn", data)
		end
	end
	if next(self.match.Spectators) then
		-- Delayed like their events, so a spectator's turn marker stays in step.
		self:toSpectators("Turn", data)
	end
end

function Dispatcher:sendTo(player: Player, kind: string, data: any)
	self.network:match(player, kind, data)
end

-- Full redacted state for one viewer (subjectId nil = spectator).
function Dispatcher:snapshot(subjectId: number?)
	local snap = Engine.snapshot(self.match.State, subjectId)
	snap.Seq = self.seq
	snap.Connected = {}
	for id, p in self.match.Participants do
		snap.Connected[id] = p.Kind == "AI" or p.Connected == true
	end
	return snap
end

function Dispatcher:sendSnapshots()
	for _, r in self:recipients() do
		self.network:match(r.Player, "Snapshot", self:snapshot(r.Subject))
	end
	if next(self.match.Spectators) then
		self:toSpectators("Snapshot", self:snapshot(nil))
	end
end

return Dispatcher

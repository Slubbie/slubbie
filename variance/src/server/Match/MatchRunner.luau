-- Drives one match: advances the engine, paces every event with Core/Timeline,
-- waits for the acting subject (human or surrogate) with a turn timer, and
-- applies forfeits only between presentation batches.
--
-- Concurrency model (Roblox runs Lua on one thread, but handlers interleave at
-- yields):
--   * submit() is called from the remote handler. It validates through the
--     engine immediately, but the resulting events are only *queued*; the runner
--     thread presents them. While a batch is presenting, `busy` is true and every
--     other submission is rejected ("busy"), so nothing can act while an outcome
--     is still on screen, and two actions arriving together can never both apply.
--   * The engine's turn token changes after every accepted action, so a stale or
--     duplicate click is rejected even if it slips in between batches.
--   * Forfeits (leaving, AFK, abandoned) are queued and applied at safe points.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Variance.Config)
local Engine = require(ReplicatedStorage.Variance.Core.Engine)
local Timeline = require(ReplicatedStorage.Variance.Core.Timeline)
local Signal = require(ReplicatedStorage.Variance.Util.Signal)

local MatchRunner = {}
MatchRunner.__index = MatchRunner

function MatchRunner.new(match, services)
	return setmetatable({
		match = match,
		services = services,
		busy = false,
		pending = nil,
		forfeits = {},
		critical = false,
		afk = {},
		wake = Signal.new(),
		stopped = false,
		turnStartedAt = 0,
	}, MatchRunner)
end

function MatchRunner:scale(): number
	return (self.match.State.Rules.TimingScale or 1) * (self.match.DebugSpeed or 1)
end

-- Validates and queues an action. Returns (ok, reason).
function MatchRunner:submit(subjectId: number, action, token: number?): (boolean, string?)
	if self.stopped or self.match.Closed then
		return false, "ended"
	end
	if self.busy or self.pending ~= nil then
		return false, "busy"
	end
	local ok, reason, events = Engine.act(self.match.State, subjectId, action, token)
	if not ok then
		return false, reason
	end
	self.pending = { Events = events, Actor = subjectId, Action = action }
	local hooks = self.match.Hooks
	if hooks and hooks.OnAccepted then
		hooks.OnAccepted(subjectId, action)
	end
	self.wake:Fire()
	return true
end

function MatchRunner:queueForfeit(subjectId: number, reason: string)
	table.insert(self.forfeits, { subjectId, reason })
	self.wake:Fire()
end

-- Feeds public events to every surrogate brain and updates their models of opponents.
function MatchRunner:observe(events)
	local match = self.match
	local state = match.State
	for _, event in events do
		for aiId, participant in match.Participants do
			if participant.Kind == "AI" and participant.AI then
				participant.AI.Brain:observe({ Type = event.Type, Public = event.Public }, aiId)
			end
		end
		if event.Type == "FireResult" then
			local entry = state.Log[#state.Log]
			if entry and entry.Kind == "Fire" then
				for aiId, participant in match.Participants do
					if participant.Kind == "AI" and participant.AI and aiId ~= entry.Actor then
						participant.AI.Brain.tendencies:recordFire(entry.PublicP, entry.Actor == entry.Target, entry.Used)
					end
				end
			end
		elseif event.Type == "TrialStart" then
			local humanWins, aiWins = 0, 0
			for id, p in match.Participants do
				if p.Kind == "Player" then
					humanWins += state.Subjects[id].TrialWins
				else
					aiWins += state.Subjects[id].TrialWins
				end
			end
			local lead = math.sign(humanWins - aiWins)
			for _, participant in match.Participants do
				if participant.Kind == "AI" and participant.AI then
					self.services.AIService:onTrialStart(participant.AI, state.Trial, lead)
				end
			end
		end
	end
end

-- Presents a batch of events with their timings. Holds the action lock.
function MatchRunner:present(events)
	if #events == 0 then
		return
	end
	local match = self.match
	self.busy = true
	local hooks = match.Hooks
	local scale = self:scale()
	for _, event in events do
		if match.Closed then
			break
		end
		match.Dispatcher:send(event)
		if hooks and hooks.OnEvent then
			hooks.OnEvent(event)
		end
		if event.Type == "FireCommit" then
			self.critical = true
		elseif event.Type == "FireResult" then
			self.critical = false
		elseif event.Type == "TurnStart" or event.Type == "LoadStart" or event.Type == "TrialStart" then
			match.Dispatcher:sendSnapshots()
		end
		local wait = Timeline.after(event, scale)
		if wait > 0 then
			task.wait(wait)
		end
	end
	self.critical = false
	self:observe(events)
	local ok, err = pcall(self.services.DialogueService.onEvents, self.services.DialogueService, match, events)
	if not ok then
		warn("[VARIANCE/Match] dialogue failed: " .. tostring(err))
	end
	if hooks and hooks.OnPresented then
		hooks.OnPresented(events)
	end
	self.busy = false
end

function MatchRunner:processForfeits()
	while #self.forfeits > 0 do
		local entry = table.remove(self.forfeits, 1)
		local events = Engine.forfeit(self.match.State, entry[1], entry[2])
		self:present(events)
	end
end

-- Schedules a surrogate's decision for the current turn.
function MatchRunner:scheduleAI(owner: number, token: number)
	local match = self.match
	local state = match.State
	local participant = match.Participants[owner]
	task.spawn(function()
		local action, think = nil, 1.2
		local hooks = match.Hooks
		if hooks and hooks.ProxyAction then
			while not match.Closed do
				if state.Phase ~= "AwaitAction" or state.Turn.Token ~= token then
					return
				end
				local scripted = hooks.ProxyAction(state)
				if scripted == "wait" then
					task.wait(0.3)
				elseif scripted == "brain" then
					break
				else
					action, think = scripted, 1.3
					break
				end
			end
		end
		if action == nil then
			if participant.AI == nil then
				action = self.services.AIService:fallback(state, owner)
			else
				action, think = self.services.AIService:decide(participant.AI, state, owner)
			end
		end
		task.wait(think * math.clamp(self:scale(), 0.4, 1))
		if match.Closed or state.Phase ~= "AwaitAction" or state.Turn.Token ~= token then
			return
		end
		-- Wait out any presentation still running (e.g. a dialogue-triggered batch).
		local guard = 0
		while (self.busy or self.pending) and guard < 100 do
			task.wait(0.1)
			guard += 1
		end
		local ok = self:submit(owner, action, state.Turn.Token)
		if not ok then
			self:submit(owner, self.services.AIService:fallback(state, owner), state.Turn.Token)
		end
	end)
end

function MatchRunner:turnTimer(): number
	local state = self.match.State
	local timer = state.Rules.TurnTimer or 0
	if timer > 0 and Engine.flag(state, "ShortFuse") then
		timer = math.max(8, math.floor(timer / 2))
	end
	return timer
end

function MatchRunner:awaitAction()
	local match = self.match
	local state = match.State
	local owner = state.Turn.Owner
	local token = state.Turn.Token
	local participant = match.Participants[owner]
	local timer = self:turnTimer()
	local started = os.clock()
	self.turnStartedAt = started
	local deadline = timer > 0 and started + timer or nil
	match.Dispatcher:broadcast("Turn", {
		Owner = owner,
		Token = token,
		Duration = timer,
		EndsAt = timer > 0 and workspace:GetServerTimeNow() + timer or nil,
	}, true)
	if participant.Kind == "AI" then
		self:scheduleAI(owner, token)
	end
	local hesitated = false
	while not match.Closed do
		if self.pending then
			local batch = self.pending
			self.pending = nil
			self.afk[batch.Actor] = 0
			self:present(batch.Events)
			return
		end
		if #self.forfeits > 0 then
			self:processForfeits()
			return
		end
		if state.Phase ~= "AwaitAction" or state.Turn.Token ~= token then
			return
		end
		local now = os.clock()
		if participant.Kind == "Player" and not hesitated and now - started > Config.Match.HesitationSeconds then
			hesitated = true
			for _, p in match.Participants do
				if p.Kind == "AI" and p.AI then
					p.AI.Brain.tendencies:recordHesitation()
				end
			end
			self.services.DialogueService:hesitation(match, owner)
		end
		if deadline and now >= deadline then
			if participant.Kind == "Player" and not participant.Connected and Config.Match.DisconnectPause then
				-- Hold the seat while they try to reconnect; the grace timer forfeits.
				deadline = now + 1
			else
				local events = Engine.timeout(state)
				self.afk[owner] = (self.afk[owner] or 0) + 1
				self:present(events)
				if participant.Kind == "Player" and match.Info.PvP and self.afk[owner] >= Config.Match.AfkTimeoutsToForfeit then
					self:queueForfeit(owner, "AFK")
				end
				return
			end
		end
		self.wake:Wait(0.25)
	end
end

function MatchRunner:run()
	local match = self.match
	local ok, err = pcall(function()
		while not match.Closed do
			self:processForfeits()
			local state = match.State
			if state.Phase == Engine.Phase.Ended then
				break
			end
			if state.Phase == Engine.Phase.AwaitAction then
				self:awaitAction()
			else
				self:present(Engine.advance(state))
			end
		end
	end)
	if not ok then
		warn("[VARIANCE/Match] runner error in " .. tostring(match.Id) .. ": " .. tostring(err))
		match.Aborted = true
	end
	self.stopped = true
	self.wake:Destroy()
	self.services.MatchService:finish(match)
end

return MatchRunner

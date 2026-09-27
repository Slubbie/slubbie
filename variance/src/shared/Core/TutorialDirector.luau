-- Runs a tutorial lesson (Data/Tutorials.luau) on top of a real engine match.
--
-- Pure logic, so the whole scripted path is verified headlessly by the tests.
-- The server's TutorialService owns one Director per lesson and wires it in:
--   * Engine filter  -> Director:filter (only the prompted action is allowed)
--   * after actions  -> Director:onAccepted
--   * after the runner finishes presenting events -> Director:onPresented
--   * PROXY's turn   -> Director:proxyAction ("wait", "brain", or a scripted action)
--   * client input   -> Director:continue / Director:answer

local Director = {}
Director.__index = Director

function Director.new(lesson, playerId: number, proxyId: number)
	local self = setmetatable({}, Director)
	self.lesson = lesson
	self.playerId = playerId
	self.proxyId = proxyId
	self.index = 0
	self.done = false
	self.proxyQueue = {}
	self.pendingAction = false
	self.setupPending = nil
	self.trialEnded = false
	self.matchEnded = false
	self.version = 0
	return self
end

function Director:beat()
	return self.lesson.Beats[self.index]
end

-- What the client needs to draw the coach panel (never the quiz answer).
function Director:status()
	local beat = self:beat()
	local info = nil
	if beat then
		info = {
			Title = beat.Title,
			Say = beat.Say,
			Focus = beat.Focus,
			Allow = beat.Allow,
			Advance = beat.Advance,
			Free = beat.Free == true,
			Quiz = beat.Quiz and { Question = beat.Quiz.Question, Options = beat.Quiz.Options } or nil,
		}
	end
	return {
		Lesson = self.lesson.Id,
		Name = self.lesson.Name,
		Index = self.index,
		Count = #self.lesson.Beats,
		Beat = info,
		Done = self.done,
		Version = self.version,
	}
end

local function applySetup(self, state, E)
	local setup = self.setupPending
	if setup == nil or state.Load == nil then
		return false
	end
	self.setupPending = nil
	local player = state.Subjects[self.playerId]
	if setup.Reveal then
		for _, index in setup.Reveal do
			local cell = state.Load.Cells[index]
			if cell then
				E.learn(state, player, cell)
			end
		end
	end
	return true
end

function Director:start(state, E)
	self.index = 0
	self:advance(state, E)
end

function Director:advance(state, E)
	self.index += 1
	self.pendingAction = false
	self.trialEnded = false
	self.version += 1
	local beat = self:beat()
	if beat == nil then
		self.done = true
		return
	end
	if beat.Proxy then
		for _, a in beat.Proxy do
			table.insert(self.proxyQueue, a)
		end
	end
	self.setupPending = beat.Setup
	applySetup(self, state, E)
end

local function matches(token: string, action, subject): boolean
	if token == "Any" then
		return true
	elseif token == "FireSelf" then
		return action.Kind == "Fire" and action.Target == subject.Id
	elseif token == "FireOpponent" then
		return action.Kind == "Fire" and action.Target ~= nil and action.Target ~= subject.Id
	end
	local id = string.match(token, "^Use:(%w+)$")
	if id then
		return action.Kind == "Use" and type(action.Slot) == "number" and subject.Instruments[action.Slot] == id
	end
	return false
end

-- Engine action filter.
function Director:filter(_state, subject, action)
	if subject.Id ~= self.playerId then
		return true
	end
	local beat = self:beat()
	if beat == nil or self.done then
		return true
	end
	if beat.Free then
		return true
	end
	if beat.Allow == nil then
		return false, "Follow the prompt first."
	end
	for _, token in beat.Allow do
		if matches(token, action, subject) then
			return true
		end
	end
	return false, "Not yet: follow the prompt."
end

function Director:onAccepted(subjectId: number, _action)
	if subjectId == self.playerId then
		local beat = self:beat()
		if beat and beat.Advance == "Action" then
			self.pendingAction = true
		end
	end
end

function Director:onEvent(event)
	if event.Type == "TrialEnd" or event.Type == "SuddenDeath" then
		self.trialEnded = event.Type == "TrialEnd"
	elseif event.Type == "MatchEnd" then
		self.matchEnded = true
	end
end

-- Called whenever the runner has finished presenting a batch of events.
-- Returns true if the beat changed (the service then re-sends the status).
function Director:onPresented(state, E): boolean
	if self.done then
		return false
	end
	local changed = applySetup(self, state, E)
	local beat = self:beat()
	if beat == nil then
		return changed
	end
	local advance = beat.Advance
	local playerTurn = state.Phase == "AwaitAction" and state.Turn.Owner == self.playerId and #self.proxyQueue == 0
	local ready = (advance == "Action" and self.pendingAction)
		or (advance == "PlayerTurn" and playerTurn)
		or (advance == "TrialEnd" and self.trialEnded)
		or (advance == "MatchEnd" and self.matchEnded)
	if ready then
		self:advance(state, E)
		return true
	end
	return changed
end

function Director:continue(state, E): boolean
	local beat = self:beat()
	if beat == nil then
		return false
	end
	if beat.Advance == "Continue" then
		self:advance(state, E)
		return true
	elseif beat.Advance == "Finish" then
		self.index += 1
		self.done = true
		self.version += 1
		return true
	end
	return false
end

-- Returns (correct, explanation).
function Director:answer(state, E, option: number): (boolean, string?)
	local beat = self:beat()
	if beat == nil or beat.Advance ~= "Quiz" or beat.Quiz == nil then
		return false, nil
	end
	local correct = option == beat.Quiz.Answer
	if correct then
		local explain = beat.Quiz.Explain
		self:advance(state, E)
		return true, explain
	end
	return false, beat.Quiz.Explain
end

-- PROXY's next action: a scripted action, "brain" (free play) or "wait".
function Director:proxyAction(state)
	local proxy = state.Subjects[self.proxyId]
	local token = self.proxyQueue[1]
	if token then
		table.remove(self.proxyQueue, 1)
		if token == "FireSelf" then
			return { Kind = "Fire", Target = self.proxyId }
		elseif token == "FireOpponent" then
			return { Kind = "Fire", Target = self.playerId }
		end
		local id = string.match(token, "^Use:(%w+)$")
		if id then
			local slot = table.find(proxy.Instruments, id)
			if slot then
				return { Kind = "Use", Slot = slot }
			end
		end
		return { Kind = "Fire", Target = self.playerId }
	end
	local beat = self:beat()
	if self.done or (beat and beat.Free) then
		return "brain"
	end
	return "wait"
end

return Director

-- Orientation and the advanced seminars.
--
-- Each lesson is a real match against PROXY with forced Loads, forced draws and
-- an action filter supplied by Core/TutorialDirector, so the player learns on
-- exactly the systems they will play with. Coach text, highlights and quizzes
-- are pushed to the client as "Tutorial" status updates.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Engine = require(ReplicatedStorage.Variance.Core.Engine)
local Director = require(ReplicatedStorage.Variance.Core.TutorialDirector)
local Tutorials = require(ReplicatedStorage.Variance.Data.Tutorials)

local TutorialService = {}

local sessions: { [Player]: { Director: any, Match: any, Lesson: any, Completed: boolean } } = {}

function TutorialService:Init(services)
	self.Services = services
end

local function push(self, player: Player, extra: { [string]: any }?)
	local session = sessions[player]
	if session == nil then
		self.Services.NetworkService:push(player, "Tutorial", nil)
		return
	end
	local status = session.Director:status()
	if extra then
		for k, v in extra do
			status[k] = v
		end
	end
	self.Services.NetworkService:push(player, "Tutorial", status)
end

local function complete(self, player: Player)
	local session = sessions[player]
	if session == nil or session.Completed then
		return
	end
	session.Completed = true
	local lesson = session.Lesson
	local first = false
	self.Services.DataService:update(player, function(data)
		if lesson.Id == "Basic" then
			first = not data.Tutorial.Basic
			data.Tutorial.Basic = true
		else
			first = not data.Tutorial.Seminars[lesson.Id]
			data.Tutorial.Seminars[lesson.Id] = true
		end
	end)
	if first and lesson.Reward then
		self.Services.ProgressionService:award(player, lesson.Reward.XP, lesson.Reward.Marks, lesson.Name)
	end
	self.Services.AchievementService:evaluate(player, { Event = "Tutorial" })
	self.Services.ProgressionService:changed(player)
	self.Services.NetworkService:push(player, "TutorialComplete", { Lesson = lesson.Id, Name = lesson.Name, First = first })
	-- Wrap up the lesson's match and send the player back to the lobby.
	local match = session.Match
	task.delay(2.5, function()
		sessions[player] = nil
		push(self, player)
		if match and not match.ClosedFully then
			self.Services.MatchService:close(match)
		end
	end)
end

function TutorialService:start(player: Player, lessonId: string): (boolean, string?)
	local lesson = Tutorials.get(lessonId)
	if lesson == nil then
		return false, "Unknown lesson."
	end
	if sessions[player] or self.Services.MatchService:isBusy(player) then
		return false, "Finish what you're doing first."
	end
	self.Services.MatchmakingService:leave(player)
	local director = Director.new(lesson, 1, 2)
	local session = { Director = director, Lesson = lesson, Match = nil, Completed = false }
	sessions[player] = session
	local match, err = self.Services.MatchService:create({
		ModeId = "Tutorial",
		Overrides = lesson.Rules,
		Environment = "TestChamber",
		Subjects = {
			{ Kind = "Player", Player = player },
			{ Kind = "AI", Personality = "Proxy", Difficulty = "Casual" },
		},
		Info = { Tutorial = true, Solo = true, Lesson = lesson.Id },
		NoRematch = true,
		Hooks = {
			Filter = function(state, subject, action)
				return director:filter(state, subject, action)
			end,
			OnAccepted = function(subjectId, action)
				director:onAccepted(subjectId, action)
			end,
			OnEvent = function(event)
				director:onEvent(event)
			end,
			OnPresented = function()
				local m = session.Match
				if m == nil then
					return
				end
				if director:onPresented(m.State, Engine) then
					push(self, player)
					m.Dispatcher:sendSnapshots()
				end
				if director.done then
					complete(self, player)
				end
			end,
			ProxyAction = function(state)
				return director:proxyAction(state)
			end,
		},
		OnEnd = function()
			if director.done then
				complete(self, player)
			elseif sessions[player] == session then
				-- The lesson's match ended early (e.g. PROXY won the free Trial).
				sessions[player] = nil
				push(self, player)
			end
			return false
		end,
	})
	if match == nil then
		sessions[player] = nil
		return false, err
	end
	session.Match = match
	director:start(match.State, Engine)
	push(self, player)
	return true
end

function TutorialService:Start()
	local network = self.Services.NetworkService
	network:handle("Tutorial.Start", function(player, lessonId)
		return self:start(player, lessonId)
	end)
	network:handle("Tutorial.Continue", function(player)
		local session = sessions[player]
		if session == nil or session.Match == nil then
			return false, "No lesson running."
		end
		local changed = session.Director:continue(session.Match.State, Engine)
		if changed then
			push(self, player)
			session.Match.Dispatcher:sendSnapshots()
		end
		if session.Director.done then
			complete(self, player)
		end
		return changed
	end)
	network:handle("Tutorial.Answer", function(player, option)
		local session = sessions[player]
		if session == nil or session.Match == nil then
			return false, "No lesson running."
		end
		if option ~= math.floor(option) or option < 1 or option > 8 then
			return false, "Invalid answer."
		end
		local correct, explain = session.Director:answer(session.Match.State, Engine, option)
		push(self, player, { LastAnswer = { Correct = correct, Explain = explain } })
		if correct then
			session.Match.Dispatcher:sendSnapshots()
		end
		return true, { Correct = correct, Explain = explain }
	end)
	network:handle("Tutorial.Quit", function(player)
		local session = sessions[player]
		if session == nil then
			return true
		end
		sessions[player] = nil
		push(self, player)
		if session.Match and not session.Match.ClosedFully then
			self.Services.MatchService:close(session.Match)
		end
		return true
	end)
	-- New subjects are offered Orientation once.
	self.Services.DataService.Loaded:Connect(function(player, profile)
		if not profile.Data.Tutorial.Offered and not profile.Data.Tutorial.Basic then
			self.Services.DataService:update(player, function(d)
				d.Tutorial.Offered = true
			end)
			task.delay(4, function()
				if player.Parent then
					network:push(player, "OfferTutorial", {})
				end
			end)
		end
	end)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)
end

return TutorialService

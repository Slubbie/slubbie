-- Single-elimination tournaments from a private lobby (3-8 subjects, humans
-- and surrogates). Matches of a round run in parallel on separate tables;
-- surrogate-vs-surrogate pairings are resolved instantly with the real engine
-- and brains (no table needed). Byes go to the first seeds. The champion earns
-- the Tournament cosmetics through normal progression.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Variance.Config)
local Engine = require(ReplicatedStorage.Variance.Core.Engine)
local Rules = require(ReplicatedStorage.Variance.Core.Rules)
local Brain = require(ReplicatedStorage.Variance.Core.AI.Brain)
local Difficulty = require(ReplicatedStorage.Variance.Core.AI.Difficulty)

local TournamentService = {}

local rng = Random.new()

function TournamentService:Init(services)
	self.Services = services
end

local function entrantName(e)
	return e.Player and e.Player.DisplayName or e.Name
end

local function publicState(t)
	local rounds = {}
	for r, round in t.Rounds do
		rounds[r] = {}
		for i, pair in round do
			rounds[r][i] = {
				A = pair.A and entrantName(pair.A) or "BYE",
				B = pair.B and entrantName(pair.B) or "BYE",
				Winner = pair.Winner and entrantName(pair.Winner) or nil,
				Live = pair.MatchId ~= nil and pair.Winner == nil,
				MatchId = pair.MatchId,
			}
		end
	end
	return {
		Id = t.Id,
		Round = t.Round,
		Rounds = rounds,
		Status = t.Status,
		Champion = t.Champion and entrantName(t.Champion) or nil,
	}
end

function TournamentService:broadcast(t)
	t.Lobby.TournamentState = publicState(t)
	self.Services.LobbyService:broadcast(t.Lobby)
end

-- Resolves a surrogate-vs-surrogate pairing instantly.
local function simulate(a, b, custom)
	local rules = Rules.build("Standard", custom, { TurnTimer = 0 })
	local state = Engine.new({
		Rules = rules,
		Rng = Random.new(),
		Subjects = { { Name = a.Name, IsAI = true }, { Name = b.Name, IsAI = true } },
	})
	local brains = {
		Brain.new({
			Personality = a.Personality,
			Difficulty = Difficulty.get(a.Difficulty == "Adaptive" and "Advanced" or a.Difficulty),
			Rng = Random.new(),
		}),
		Brain.new({
			Personality = b.Personality,
			Difficulty = Difficulty.get(b.Difficulty == "Adaptive" and "Advanced" or b.Difficulty),
			Rng = Random.new(),
		}),
	}
	local guard = 0
	while state.Phase ~= "Ended" and guard < 5000 do
		guard += 1
		if state.Phase == "AwaitAction" then
			local owner = state.Turn.Owner
			local ok = Engine.act(state, owner, brains[owner]:decide(Engine.aiView(state, owner)), state.Turn.Token)
			if not ok then
				Engine.act(state, owner, { Kind = "Fire", Target = owner }, state.Turn.Token)
			end
		else
			Engine.advance(state)
		end
	end
	return state.WinnerTeam == 2 and b or a
end

function TournamentService:start(lobby): (boolean, string?)
	local entrants = {}
	for _, p in lobby.Members do
		table.insert(entrants, { Player = p, UserId = p.UserId })
	end
	for _, bot in lobby.Bots do
		table.insert(entrants, { Name = bot.Name, Personality = bot.Personality, Difficulty = bot.Difficulty })
	end
	if #entrants < Config.Tournament.MinPlayers then
		return false, "Not enough subjects."
	end
	-- Random seeding.
	for i = #entrants, 2, -1 do
		local j = rng:NextInteger(1, i)
		entrants[i], entrants[j] = entrants[j], entrants[i]
	end
	local size = 1
	while size < #entrants do
		size *= 2
	end
	local byes = size - #entrants
	local first = {}
	local index = 1
	for _ = 1, size / 2 do
		local a = entrants[index]
		index += 1
		local b = nil
		if byes > 0 then
			byes -= 1
		else
			b = entrants[index]
			index += 1
		end
		table.insert(first, { A = a, B = b })
	end
	local t = {
		Id = self.Services.DataService.newId("t"),
		Lobby = lobby,
		Rounds = { first },
		Round = 1,
		Status = "Running",
	}
	lobby.InMatch = true
	lobby.Tournament = t
	for _, p in lobby.Members do
		self.Services.MatchmakingService:leave(p)
	end
	self:broadcast(t)
	task.spawn(function()
		self:runRound(t)
	end)
	return true
end

function TournamentService:finishPair(t, pair, winner)
	if pair.Winner then
		return
	end
	pair.Winner = winner
	self:broadcast(t)
	local round = t.Rounds[t.Round]
	for _, p in round do
		if p.Winner == nil then
			return
		end
	end
	task.delay(Config.Tournament.BetweenRounds, function()
		self:advance(t)
	end)
end

function TournamentService:runRound(t)
	local round = t.Rounds[t.Round]
	local isFinal = #round == 1
	for _, pair in round do
		if pair.B == nil then
			self:finishPair(t, pair, pair.A)
		elseif pair.A.Player == nil and pair.B.Player == nil then
			self:finishPair(t, pair, simulate(pair.A, pair.B, t.Lobby.Rules))
		else
			-- A human who left forfeits their pairing.
			local aGone = pair.A.Player and not pair.A.Player.Parent
			local bGone = pair.B.Player and not pair.B.Player.Parent
			if aGone or bGone then
				self:finishPair(t, pair, aGone and pair.B or pair.A)
			else
				-- Winners of the last round may still be on their results screen.
				for _, e in { pair.A, pair.B } do
					if e.Player then
						self.Services.MatchService:releaseFinished(e.Player)
					end
				end
				local subjects = {}
				for _, e in { pair.A, pair.B } do
					if e.Player then
						table.insert(subjects, { Kind = "Player", Player = e.Player })
					else
						table.insert(subjects, { Kind = "AI", Personality = e.Personality, Difficulty = e.Difficulty })
					end
				end
				local match, err = self.Services.MatchService:create({
					ModeId = "Standard",
					Custom = t.Lobby.Rules,
					Overrides = { SpectatorDelay = Config.Spectate.CompetitiveDelay },
					Subjects = subjects,
					Environment = t.Lobby.Rules.Environment,
					Info = {
						Private = true,
						Tournament = true,
						TournamentId = t.Id,
						Solo = pair.A.Player == nil or pair.B.Player == nil,
					},
					NoRematch = true,
					OnEnd = function(m)
						local state = m.State
						local winner = state.WinnerTeam == 2 and pair.B or pair.A
						if isFinal then
							m.Info.TournamentWon = true
							m.Info.TournamentWinner = state.WinnerTeam
						end
						self:finishPair(t, pair, winner)
						return false
					end,
				})
				if match == nil then
					warn("[VARIANCE/Tournament] match failed: " .. tostring(err))
					-- No room: decide by a coin flip rather than stall the bracket.
					self:finishPair(t, pair, rng:NextNumber() < 0.5 and pair.A or pair.B)
				else
					pair.MatchId = match.Id
					self:broadcast(t)
				end
			end
		end
	end
end

function TournamentService:advance(t)
	local round = t.Rounds[t.Round]
	if #round == 1 then
		t.Status = "Finished"
		t.Champion = round[1].Winner
		t.Lobby.InMatch = false
		t.Lobby.Tournament = nil
		self:broadcast(t)
		local name = entrantName(t.Champion)
		for _, p in t.Lobby.Members do
			self.Services.NetworkService:notify(p, "TOURNAMENT CHAMPION", name .. " won the tournament.", "Good")
		end
		return
	end
	local nextRound = {}
	for i = 1, #round, 2 do
		table.insert(nextRound, { A = round[i].Winner, B = round[i + 1] and round[i + 1].Winner or nil })
	end
	table.insert(t.Rounds, nextRound)
	t.Round += 1
	self:broadcast(t)
	self:runRound(t)
end

return TournamentService

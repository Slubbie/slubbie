-- Owns every live match: creation, player actions, disconnects and reconnects,
-- forfeits, the post-match flow (report, ranked, progression), rematches,
-- Endurance chaining and cleanup.
--
-- A match record:
--   Id, ModeId, State (engine), Arena, Runner, Dispatcher
--   Participants[subjectId] = { Kind = "Player"|"AI", Player?, UserId?, Name, Seat,
--                               Connected, Personality?, Difficulty?, AI?, Look }
--   Spectators[Player] = true
--   Info   { Solo, PvP, Private, Ranked, Tournament, Endurance, Tutorial, Sandbox, ... }
--   Hooks  optional engine/runner hooks (tutorial)
--   OnEnd  optional callback(match, report) -> handled

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Variance.Config)
local Engine = require(ReplicatedStorage.Variance.Core.Engine)
local Rules = require(ReplicatedStorage.Variance.Core.Rules)
local Modes = require(ReplicatedStorage.Variance.Core.Modes)
local Report = require(ReplicatedStorage.Variance.Core.Report)
local Personalities = require(ReplicatedStorage.Variance.Core.AI.Personalities)
local Difficulty = require(ReplicatedStorage.Variance.Core.AI.Difficulty)
local Instruments = require(ReplicatedStorage.Variance.Core.Instruments)
local Cosmetics = require(ReplicatedStorage.Variance.Data.Cosmetics)
local Levels = require(ReplicatedStorage.Variance.Data.Levels)
local Surrogates = require(ReplicatedStorage.Variance.Data.Surrogates)

local MatchRunner = require(script.Parent.Parent.Match.MatchRunner)
local Dispatcher = require(script.Parent.Parent.Match.Dispatcher)

local MatchService = {}

local matches: { [string]: any } = {}
local byPlayer: { [Player]: any } = {}
local byUser: { [number]: any } = {}

function MatchService:Init(services)
	self.Services = services
end

---------------------------------------------------------------------------
-- Lookup
---------------------------------------------------------------------------

function MatchService:matchOf(player: Player)
	return byPlayer[player]
end

function MatchService:subjectOf(match, player: Player): number?
	for id, p in match.Participants do
		if p.Kind == "Player" and p.Player == player then
			return id
		end
	end
	return nil
end

function MatchService:get(id: string)
	return matches[id]
end

function MatchService:all()
	return matches
end

function MatchService:isBusy(player: Player): boolean
	return byPlayer[player] ~= nil
end

---------------------------------------------------------------------------
-- Scene payloads
---------------------------------------------------------------------------

local function cardFor(look)
	return {
		Frame = look.CardFrame and look.CardFrame.Data,
		Banner = look.Banner and look.Banner.Data,
		Badge = look.Badge and look.Badge.Data,
		Title = look.Title and look.Title.Data and look.Title.Data.Text,
	}
end

function MatchService:beginPayload(match, subjectId: number?)
	local state = match.State
	local subjects = {}
	for id, p in match.Participants do
		subjects[id] = {
			Name = p.Name,
			IsAI = p.Kind == "AI",
			UserId = p.UserId,
			Personality = p.Personality,
			Difficulty = p.Difficulty,
			Seat = p.Seat,
			Look = p.Look,
			Card = p.Card,
			Level = p.Level,
			Title = p.Title,
			Division = p.Division,
			TeamId = state.Subjects[id].TeamId,
		}
	end
	local rules = state.Rules
	local payload = {
		MatchId = match.Id,
		ModeId = rules.ModeId,
		ModeName = rules.ModeName,
		Arena = match.Arena.Model.Name,
		Environment = match.Arena.Environment,
		Origin = match.Arena.Origin,
		You = subjectId,
		Subjects = subjects,
		Rules = {
			TrialsToWin = rules.TrialsToWin,
			Capacity = Engine.capacity(state),
			TurnTimer = rules.TurnTimer,
			Modifiers = Engine.activeModifiers(state),
			Ranked = rules.Ranked,
			PrecisionReveal = rules.PrecisionReveal,
			ChaosPerTrial = rules.ChaosPerTrial,
			TimingScale = rules.TimingScale,
			Describe = Rules.describe(rules),
		},
		Info = {
			Solo = match.Info.Solo,
			Private = match.Info.Private,
			Ranked = match.Info.Ranked,
			Tournament = match.Info.Tournament,
			Endurance = match.Info.Endurance,
			Tutorial = match.Info.Tutorial,
			Sandbox = match.Info.Sandbox,
		},
		Snapshot = match.Dispatcher:snapshot(subjectId),
		Spectating = subjectId == nil,
	}
	if subjectId and rules.Ranked then
		local p = match.Participants[subjectId]
		for id, other in match.Participants do
			if id ~= subjectId and other.Kind == "Player" and other.Player then
				payload.RankedPreview = self.Services.RankedService:preview(p.Player, other.RatingBefore or 1000)
			end
		end
	end
	return payload
end

---------------------------------------------------------------------------
-- Creation
---------------------------------------------------------------------------

local function surrogateLook(personality: string)
	local look = {}
	for _, category in Cosmetics.Categories do
		local item = Cosmetics.get(Cosmetics.Defaults[category.Id])
		look[category.Id] = item and { Id = item.Id, Name = item.Name, Data = item.Data } or nil
	end
	look.Surrogate = Surrogates.get(personality)
	return look
end

-- Creates and starts a match. Returns (match, nil) or (nil, reason).
function MatchService:create(spec)
	local services = self.Services
	local humans = {}
	for _, s in spec.Subjects do
		if s.Kind == "Player" then
			if s.Player == nil or not s.Player.Parent then
				return nil, "A subject is no longer here."
			end
			local current = byPlayer[s.Player]
			if current and current ~= spec.Replaces then
				return nil, s.Player.DisplayName .. " is already in a Trial."
			end
			table.insert(humans, s.Player)
		end
	end
	if #spec.Subjects < 2 then
		return nil, "A Trial needs at least two subjects."
	end
	local mode = Modes.get(spec.ModeId)
	if mode == nil then
		return nil, "Unknown mode."
	end
	local rules = Rules.build(spec.ModeId, spec.Custom, spec.Overrides)
	if spec.Speed then
		rules.TimingScale *= spec.Speed
	end

	local firstLook = humans[1] and services.CosmeticService:look(humans[1]) or nil
	local arena = spec.Arena
	if arena == nil then
		arena = services.ArenaService:acquire(
			spec.Environment or rules.Environment,
			#spec.Subjects,
			firstLook and firstLook.TableTheme.Data
		)
		if arena == nil then
			return nil, "Every evaluation room is in use. Try again in a moment."
		end
	else
		services.ArenaService:clearPuppets(arena)
	end

	local engineSubjects = {}
	for i, s in spec.Subjects do
		if s.Kind == "Player" then
			engineSubjects[i] = { Name = s.Player.DisplayName, UserId = s.Player.UserId, TeamId = s.TeamId }
		else
			local persona = Personalities.get(s.Personality)
			engineSubjects[i] = {
				Name = s.Name or persona.Name,
				IsAI = true,
				Personality = persona.Id,
				Difficulty = s.Difficulty,
				TeamId = s.TeamId,
			}
		end
	end

	local hooks = spec.Hooks or {}
	local id = services.DataService.newId("m")
	local match = {
		Id = id,
		ModeId = rules.ModeId,
		State = Engine.new({
			MatchId = id,
			Rules = rules,
			Subjects = engineSubjects,
			Rng = Random.new(),
			Filter = hooks.Filter,
		}),
		Arena = arena,
		Participants = {},
		Spectators = {},
		Info = table.clone(spec.Info or {}),
		Hooks = hooks,
		OnEnd = spec.OnEnd,
		Spec = spec,
		Closed = false,
		Finished = false,
		Phase = "Intro",
	}
	match.Info.PvP = #humans >= 2
	match.Info.Environment = arena.Environment
	match.Info.StartTime = os.clock()
	match.Info.StartUnix = os.time()
	match.Info.Friends = {}
	match.Dispatcher = Dispatcher.new(match, services.NetworkService)

	-- The previous match in this arena (Endurance / rematch) hands its seats over.
	if spec.Replaces then
		local old = spec.Replaces
		old.Closed = true
		old.KeepArena = true
		matches[old.Id] = nil
		for _, p in old.Participants do
			if p.Kind == "Player" and p.Player and byPlayer[p.Player] == old then
				byPlayer[p.Player] = nil
				byUser[p.UserId] = nil
			end
		end
		for player in old.Spectators do
			match.Spectators[player] = true
		end
	end

	for i, s in spec.Subjects do
		local seat = services.ArenaService:seatOf(arena, i)
		if s.Kind == "Player" then
			local player = s.Player
			local look = services.CosmeticService:look(player)
			local profile = services.DataService:get(player)
			local level = profile and profile.Data.Level or 1
			local ranked = services.RankedService:info(player)
			match.Participants[i] = {
				Kind = "Player",
				Player = player,
				UserId = player.UserId,
				Name = player.DisplayName,
				Seat = seat,
				Connected = true,
				Look = look,
				Card = cardFor(look),
				Level = level,
				Title = Levels.titleFor(level),
				Division = ranked and ranked.Placed and ranked.Division.Label or nil,
				RatingBefore = services.RankedService:rating(player),
			}
			byPlayer[player] = match
			byUser[player.UserId] = match
			services.CharacterService:seat(player, arena.Model, seat, services.ArenaService:rootCFrame(arena, seat))
		else
			local persona = Personalities.get(s.Personality)
			local skill = nil
			if s.Difficulty == "Adaptive" and humans[1] then
				local profile = services.DataService:get(humans[1])
				skill = profile and profile.Data.AdaptiveSkill or 0.35
			end
			match.Participants[i] = {
				Kind = "AI",
				Name = s.Name or persona.Name,
				Personality = persona.Id,
				Difficulty = s.Difficulty or "Standard",
				Seat = seat,
				Connected = true,
				AI = services.AIService:createBrain(persona.Id, s.Difficulty or "Standard", skill),
				Look = surrogateLook(persona.Id),
				Card = { Title = string.upper(persona.Epithet) },
				Level = nil,
				Title = string.upper(persona.Epithet),
			}
			services.ArenaService:addPuppet(arena, i, seat, persona.Id)
		end
	end
	if firstLook then
		services.ArenaService:applyTableTheme(arena, firstLook.TableTheme.Data)
	end
	matches[id] = match

	-- Friends at the same table (for challenges and achievements).
	task.spawn(function()
		for _, a in humans do
			for _, b in humans do
				if a ~= b and a.Parent and b.Parent then
					local ok, friends = pcall(a.IsFriendsWith, a, b.UserId)
					if ok and friends then
						match.Info.Friends[a.UserId] = true
					end
				end
			end
		end
	end)

	for sid, p in match.Participants do
		if p.Kind == "Player" then
			services.NetworkService:match(p.Player, "Begin", self:beginPayload(match, sid))
		end
	end
	for player in match.Spectators do
		services.NetworkService:match(player, "Begin", self:beginPayload(match, nil))
	end
	services.ReconnectService:track(match)
	services.AmbientEventService:start(match)
	services.LobbyWorldService:refreshLive()

	match.Runner = MatchRunner.new(match, services)
	task.delay(0.9, function()
		match.Phase = "Playing"
		match.Runner:run()
	end)
	return match
end

---------------------------------------------------------------------------
-- Player input
---------------------------------------------------------------------------

local function severityFor(reason: string?): string
	if reason == "busy" or reason == "stale" or reason == "not_accepting" or reason == "ended" then
		return "Minor"
	elseif reason == "not_your_turn" then
		return "Low"
	elseif reason == "bad_action" or reason == "bad_target" or reason == "bad_slot" then
		return "Moderate"
	end
	return "Minor" -- an instrument's own "can't use that now" reason
end

function MatchService:handleAct(player: Player, payload)
	local match = byPlayer[player]
	if match == nil or match.Closed then
		self.Services.AntiExploitService:flag(player, "act outside match", "Low")
		return
	end
	local subjectId = self:subjectOf(match, player)
	if subjectId == nil then
		return
	end
	local kind = payload.Kind
	if kind ~= "Fire" and kind ~= "Use" then
		self.Services.AntiExploitService:flag(player, "bad act kind", "Moderate", kind)
		return
	end
	local function int(v)
		return type(v) == "number" and v == math.floor(v) and v >= -1e6 and v <= 1e6
	end
	if payload.Target ~= nil and not int(payload.Target) then
		self.Services.AntiExploitService:flag(player, "bad target type", "Moderate")
		return
	end
	if payload.Slot ~= nil and not int(payload.Slot) then
		self.Services.AntiExploitService:flag(player, "bad slot type", "Moderate")
		return
	end
	if not int(payload.Token) then
		self.Services.AntiExploitService:flag(player, "missing token", "Moderate")
		return
	end
	local latency = self.Services.DebugService:latencyFor(player)
	if latency > 0 then
		task.wait(latency)
	end
	local action = { Kind = kind, Target = payload.Target, Slot = payload.Slot }
	if kind == "Use" and action.Slot then
		-- Confirm-before-use for rare instruments happens on the client; the server
		-- only needs the slot to still hold the instrument the client saw.
		local subject = match.State.Subjects[subjectId]
		local expected = payload.Id
		if type(expected) == "string" and subject.Instruments[action.Slot] ~= expected then
			self.Services.NetworkService:match(player, "Rejected", { Reason = "stale", Token = payload.Token })
			return
		end
		if type(expected) == "string" and not Instruments.isValid(expected) then
			self.Services.AntiExploitService:flag(player, "unknown instrument", "High", expected)
			return
		end
	end
	local ok, reason = match.Runner:submit(subjectId, action, payload.Token)
	if not ok then
		self.Services.AntiExploitService:flag(player, "rejected: " .. tostring(reason), severityFor(reason))
		self.Services.NetworkService:match(player, "Rejected", { Reason = reason, Token = payload.Token })
	end
end

function MatchService:handleLook(player: Player, payload)
	local match = byPlayer[player]
	if match == nil or match.Closed then
		return
	end
	local subjectId = self:subjectOf(match, player)
	local yaw, pitch = payload.Yaw, payload.Pitch
	if subjectId == nil or type(yaw) ~= "number" or type(pitch) ~= "number" then
		return
	end
	local data = { Subject = subjectId, Yaw = math.clamp(yaw, -1.4, 1.4), Pitch = math.clamp(pitch, -0.9, 0.7) }
	for id, p in match.Participants do
		if id ~= subjectId and p.Kind == "Player" and p.Connected and p.Player then
			self.Services.NetworkService:look(p.Player, data)
		end
	end
	for spectator in match.Spectators do
		self.Services.NetworkService:look(spectator, data)
	end
end

---------------------------------------------------------------------------
-- Leaving, disconnecting, reconnecting
---------------------------------------------------------------------------

-- Removes a player from their match. `reason`: "Left" (voluntary), "Disconnected".
function MatchService:forfeit(player: Player, reason: string)
	local match = byPlayer[player]
	if match == nil then
		return
	end
	local subjectId = self:subjectOf(match, player)
	if subjectId == nil then
		return
	end
	local participant = match.Participants[subjectId]
	if match.Phase == "PostMatch" or match.Finished then
		self:detach(match, subjectId)
		return
	end
	if match.State.Rules.Ranked and not participant.Abandoned then
		participant.Abandoned = true
		participant.Refund = self.Services.RankedService:applyAbandon(player, self:opponentRating(match, subjectId))
		local profile = self.Services.DataService:get(player)
		participant.AbandonDelta = profile
				and profile.Data.Ranked.History[#profile.Data.Ranked.History]
				and profile.Data.Ranked.History[#profile.Data.Ranked.History].Delta
			or 0
	end
	match.Runner:queueForfeit(subjectId, reason)
	self:detach(match, subjectId)
end

function MatchService:opponentRating(match, subjectId: number): number
	for id, p in match.Participants do
		if id ~= subjectId and p.Kind == "Player" then
			return p.RatingBefore or 1000
		end
	end
	return 1000
end

-- Detaches a player from a match without ending it (they return to the lobby).
function MatchService:detach(match, subjectId: number)
	local participant = match.Participants[subjectId]
	if participant == nil or participant.Kind ~= "Player" then
		return
	end
	participant.Detached = true
	participant.Connected = false
	local player = participant.Player
	if player and byPlayer[player] == match then
		byPlayer[player] = nil
	end
	if participant.UserId and byUser[participant.UserId] == match then
		byUser[participant.UserId] = nil
	end
	if player and player.Parent then
		self.Services.CharacterService:unseat(player)
		self.Services.NetworkService:match(player, "End", { MatchId = match.Id })
	end
	match.Dispatcher:broadcast("Presence", { Subject = subjectId, Connected = false, Left = true }, true)
end

-- The DataService is about to save a leaving player: apply ranked abandon now,
-- while the profile is still loaded (refunded if they reconnect in time).
function MatchService:onReleasing(player: Player)
	-- Looked up by UserId: PlayerRemoving handlers run in no guaranteed order, so
	-- onLeave may already have cleared byPlayer.
	local match = byUser[player.UserId] or byPlayer[player]
	if match == nil or match.Finished or not match.State.Rules.Ranked then
		return
	end
	for id, participant in match.Participants do
		if
			participant.Kind == "Player"
			and participant.UserId == player.UserId
			and not participant.Abandoned
			and not participant.Detached
		then
			participant.Abandoned = true
			participant.Refund = self.Services.RankedService:applyAbandon(player, self:opponentRating(match, id))
		end
	end
end

function MatchService:onLeave(player: Player)
	self.Services.SpectatorService:stop(player)
	local match = byPlayer[player]
	if match == nil then
		return
	end
	local subjectId = self:subjectOf(match, player)
	if subjectId == nil then
		return
	end
	byPlayer[player] = nil
	local participant = match.Participants[subjectId]
	participant.Connected = false
	participant.DisconnectedAt = os.clock()
	match.State.Subjects[subjectId].Connected = false
	if match.Finished then
		return
	end
	match.Dispatcher:broadcast(
		"Presence",
		{ Subject = subjectId, Connected = false, Grace = Config.Match.ReconnectGrace },
		true
	)
	-- Solo modes have nobody to wait for.
	if not match.Info.PvP then
		match.Runner:queueForfeit(subjectId, "Left")
		return
	end
	local disconnectedAt = participant.DisconnectedAt
	task.delay(Config.Match.ReconnectGrace, function()
		if not match.Finished and not participant.Connected and participant.DisconnectedAt == disconnectedAt then
			participant.Detached = true
			byUser[participant.UserId] = nil
			match.Runner:queueForfeit(subjectId, "Abandoned")
		end
	end)
end

-- A player joined this server: are they returning to a match here?
function MatchService:onJoin(player: Player)
	local match = byUser[player.UserId]
	if match == nil or match.Finished or match.Closed then
		return false
	end
	local subjectId = nil
	for id, p in match.Participants do
		if p.Kind == "Player" and p.UserId == player.UserId and not p.Detached then
			subjectId = id
		end
	end
	if subjectId == nil then
		return false
	end
	local participant = match.Participants[subjectId]
	participant.Player = player
	participant.Connected = true
	participant.DisconnectedAt = nil
	match.State.Subjects[subjectId].Connected = true
	byPlayer[player] = match
	task.spawn(function()
		self.Services.DataService:waitFor(player, 20)
		if participant.Abandoned and participant.Refund then
			self.Services.RankedService:refundAbandon(player, participant.Refund)
			participant.Abandoned = false
			participant.Refund = nil
		end
		task.wait(1.5)
		if not player.Parent or match.Finished then
			return
		end
		self.Services.CharacterService:seat(
			player,
			match.Arena.Model,
			participant.Seat,
			self.Services.ArenaService:rootCFrame(match.Arena, participant.Seat)
		)
		self.Services.NetworkService:match(player, "Begin", self:beginPayload(match, subjectId))
		match.Dispatcher:broadcast("Presence", { Subject = subjectId, Connected = true }, true)
	end)
	return true
end

---------------------------------------------------------------------------
-- End of match
---------------------------------------------------------------------------

local function scoreLine(state, subjectId: number): string
	local mine = state.Subjects[subjectId].TrialWins
	local best = 0
	for _, s in state.Subjects do
		if s.Id ~= subjectId then
			best = math.max(best, s.TrialWins)
		end
	end
	return string.format("%d-%d", mine, best)
end

function MatchService:matchInfoFor(match, subjectId: number)
	local state = match.State
	local info = {
		ModeId = state.Rules.ModeId,
		Solo = match.Info.Solo == true,
		Private = match.Info.Private == true,
		Ranked = state.Rules.Ranked == true,
		Sandbox = match.Info.Sandbox == true,
		Tutorial = match.Info.Tutorial == true,
		Environment = match.Arena.Environment,
		Score = scoreLine(state, subjectId),
		RepeatFactor = match.Info.RepeatFactor,
		EnduranceStage = match.Info.EnduranceReached,
		TournamentWon = match.Info.TournamentWon and match.Info.TournamentWinner == subjectId or nil,
	}
	local participant = match.Participants[subjectId]
	info.WithFriend = participant.UserId ~= nil and match.Info.Friends[participant.UserId] == true
	local names = {}
	for id, p in match.Participants do
		if id ~= subjectId then
			table.insert(names, p.Name)
			if p.Kind == "AI" then
				info.Personality = p.Personality
				info.Difficulty = p.Difficulty
			end
		end
	end
	info.OpponentName = #names == 1 and names[1] or string.format("%d subjects", #names)
	return info
end

function MatchService:finish(match)
	if match.Finished then
		return
	end
	match.Finished = true
	match.Phase = "PostMatch"
	local services = self.Services
	local state = match.State
	services.ReconnectService:clear(match)
	services.AmbientEventService:stop(match)
	if match.KeepArena then
		return -- replaced by a follow-up match (Endurance / rematch)
	end

	local report = Report.build(state)
	local duration = os.clock() - match.Info.StartTime

	local ratings = {}
	if state.Rules.Ranked and not match.Aborted then
		local results = {}
		for id, p in match.Participants do
			if p.Kind == "Player" then
				table.insert(results, {
					Player = p.Player,
					UserId = p.UserId,
					Won = state.WinnerTeam ~= nil and state.Subjects[id].TeamId == state.WinnerTeam,
					Abandoned = p.Abandoned == true,
					AbandonDelta = p.AbandonDelta,
					RatingBefore = p.RatingBefore or 1000,
				})
			end
		end
		local ok, result = pcall(
			services.RankedService.rateMatch,
			services.RankedService,
			results,
			duration,
			state.EndReason == "Forfeit"
		)
		if ok then
			ratings = result
		else
			warn("[VARIANCE/Match] rating failed: " .. tostring(result))
		end
	end

	local handled = false
	if match.OnEnd then
		local ok, result = pcall(match.OnEnd, match, report)
		if ok then
			handled = result == true
		else
			warn("[VARIANCE/Match] OnEnd failed: " .. tostring(result))
		end
	end
	if handled then
		return
	end

	local eligibleRematch = not match.Spec.NoRematch
		and not match.Info.Tournament
		and not match.Info.Tutorial
		and not match.Info.Endurance
		and not match.Aborted

	for id, p in match.Participants do
		if p.Kind == "Player" and p.Player and p.Player.Parent and not p.Detached then
			local outcome = Report.outcome(state, state.Subjects[id])
			local info = self:matchInfoFor(match, id)
			info.RatingDelta = ratings[p.UserId] and ratings[p.UserId].Delta or nil
			local summary = nil
			if not match.Aborted and not match.Info.Tutorial then
				local ok, result = pcall(
					services.ProgressionService.matchCompleted,
					services.ProgressionService,
					p.Player,
					outcome,
					info
				)
				if ok then
					summary = result
				else
					warn("[VARIANCE/Match] progression failed: " .. tostring(result))
				end
			end
			services.NetworkService:match(p.Player, "PostMatch", {
				MatchId = match.Id,
				Report = report,
				You = id,
				Rewards = summary,
				Rating = ratings[p.UserId],
				CanRematch = eligibleRematch,
				Aborted = match.Aborted == true,
				Linger = Config.Match.PostMatchLinger,
			})
		end
	end
	for spectator in match.Spectators do
		services.NetworkService:match(
			spectator,
			"PostMatch",
			{ MatchId = match.Id, Report = report, Spectating = true, Linger = 12 }
		)
	end
	services.LobbyWorldService:refreshLive()

	if eligibleRematch then
		self:rematchWindow(match)
	else
		task.delay(Config.Match.PostMatchLinger, function()
			self:close(match)
		end)
	end
end

-- Votes keyed by subject id as strings: a table like {[2] = true} is a sparse
-- array, which Roblox's remote serializer would mangle.
local function publicVotes(votes)
	local out = {}
	for id, v in votes do
		out[tostring(id)] = v
	end
	return out
end

-- Rematch voting: every human still at the table must accept.
function MatchService:rematchWindow(match)
	local votes = {}
	match.Rematch = votes
	local humans = {}
	for id, p in match.Participants do
		if p.Kind == "Player" and p.Player and p.Player.Parent and not p.Detached then
			humans[id] = p
		end
	end
	local deadline = os.clock() + Config.Match.RematchWindow
	local needed = 0
	for _ in humans do
		needed += 1
	end
	match.Dispatcher:broadcast(
		"Rematch",
		{ Votes = publicVotes(votes), Needed = needed, EndsIn = Config.Match.RematchWindow },
		true
	)
	task.spawn(function()
		while os.clock() < deadline and not match.Closed do
			local allYes, anyNo, present = true, false, 0
			for id, p in humans do
				if p.Detached or not p.Player.Parent then
					anyNo = true
				else
					present += 1
					if votes[id] == false then
						anyNo = true
					elseif votes[id] ~= true then
						allYes = false
					end
				end
			end
			if anyNo or present == 0 then
				break
			end
			if allYes then
				self:startRematch(match)
				return
			end
			task.wait(0.25)
		end
		-- No rematch (declined, left, or time ran out). Ties count as "no".
		match.Dispatcher:broadcast("Rematch", { Votes = publicVotes(votes), Closed = true }, true)
		task.delay(3, function()
			self:close(match)
		end)
	end)
end

function MatchService:vote(player: Player, accept: boolean)
	local match = byPlayer[player]
	if match == nil or match.Rematch == nil or match.Closed then
		return false, "No rematch pending."
	end
	local subjectId = self:subjectOf(match, player)
	if subjectId == nil then
		return false, "Not in this match."
	end
	match.Rematch[subjectId] = accept
	match.Dispatcher:broadcast("Rematch", { Votes = publicVotes(match.Rematch) }, true)
	if not accept then
		self:detach(match, subjectId)
	end
	return true
end

function MatchService:startRematch(match)
	local spec = table.clone(match.Spec)
	local subjects = {}
	-- Swap seats so nobody always starts first.
	for i = #spec.Subjects, 1, -1 do
		local s = table.clone(spec.Subjects[i])
		if s.Kind == "Player" then
			local p = nil
			for _, part in match.Participants do
				if part.Kind == "Player" and part.UserId == s.Player.UserId then
					p = part
				end
			end
			if p == nil or p.Player == nil or not p.Player.Parent then
				self:close(match)
				return
			end
			s.Player = p.Player
		end
		table.insert(subjects, s)
	end
	spec.Subjects = subjects
	spec.Arena = match.Arena
	spec.Replaces = match
	match.KeepArena = true
	local created, err = self:create(spec)
	if created == nil then
		match.KeepArena = false
		for _, p in match.Participants do
			if p.Player then
				self.Services.NetworkService:notify(
					p.Player,
					"REMATCH FAILED",
					err or "Try again from the lobby.",
					"Warn"
				)
			end
		end
		self:close(match)
	end
end

-- Frees a player still sitting in a finished match (on its results screen)
-- so they can be seated elsewhere, e.g. the next tournament round. Returns
-- false if they are in a match that is still being played.
function MatchService:releaseFinished(player: Player): boolean
	local match = byPlayer[player]
	if match == nil then
		return true
	end
	if not match.Finished then
		return false
	end
	local subjectId = self:subjectOf(match, player)
	if subjectId then
		if match.Rematch then
			match.Rematch[subjectId] = false
		end
		self:detach(match, subjectId)
	end
	return true
end

-- Returns everyone to the lobby and frees the room.
function MatchService:close(match)
	if match.ClosedFully then
		return
	end
	match.ClosedFully = true
	match.Closed = true
	matches[match.Id] = nil
	for id, p in match.Participants do
		if p.Kind == "Player" and p.Player and byPlayer[p.Player] == match then
			self:detach(match, id)
		end
		if p.UserId and byUser[p.UserId] == match then
			byUser[p.UserId] = nil
		end
	end
	for spectator in match.Spectators do
		self.Services.SpectatorService:stop(spectator)
	end
	if not match.KeepArena then
		self.Services.ArenaService:release(match.Arena)
	end
	self.Services.LobbyWorldService:refreshLive()
end

---------------------------------------------------------------------------
-- Solo, Endurance and Sandbox entry points
---------------------------------------------------------------------------

function MatchService:startSolo(player: Player, personality: string, difficulty: string)
	local persona = Personalities.ById[personality]
	if persona == nil or persona.Id == "Proxy" then
		return false, "Unknown opponent."
	end
	if difficulty ~= "Adaptive" and Difficulty.Tiers[difficulty] == nil then
		return false, "Unknown difficulty."
	end
	if persona.Secret and not self.Services.StatisticsService:proctorUnlocked(player) then
		return false, "ACCESS RESTRICTED. Defeat all four surrogates on Expert."
	end
	if self.Services.MatchmakingService:isQueued(player) then
		self.Services.MatchmakingService:leave(player)
	end
	local match, err = self:create({
		ModeId = "Solo",
		Subjects = {
			{ Kind = "Player", Player = player },
			{ Kind = "AI", Personality = persona.Id, Difficulty = difficulty },
		},
		Info = { Solo = true },
	})
	if match == nil then
		return false, err
	end
	return true, match.Id
end

function MatchService:startEndurance(player: Player)
	if self.Services.MatchmakingService:isQueued(player) then
		self.Services.MatchmakingService:leave(player)
	end
	local stages = Config.Endurance.Stages
	local function stageSpec(stage: number, carryIntegrity: number?, carryTools: { string }?, arena, replaces)
		local def = stages[stage]
		return {
			ModeId = "Endurance",
			Subjects = {
				{ Kind = "Player", Player = player },
				{ Kind = "AI", Personality = def.Personality, Difficulty = def.Difficulty },
			},
			Overrides = {
				Profiles = { Modes.Profiles.Endurance[stage] },
				StartIntegrity = carryIntegrity and { [1] = carryIntegrity } or nil,
				StartInstruments = carryTools and { [1] = carryTools } or nil,
			},
			Info = { Solo = true, Endurance = stage, EnduranceReached = stage - 1 },
			Arena = arena,
			Replaces = replaces,
			NoRematch = true,
			OnEnd = nil,
		}
	end
	local function attach(spec, stage)
		spec.OnEnd = function(match, _report)
			local state = match.State
			local me = state.Subjects[1]
			local won = state.WinnerTeam == me.TeamId and not me.Forfeited
			match.Info.EnduranceReached = won and stage or stage - 1
			if won and stage < #stages and player.Parent then
				local nextIntegrity = me.Integrity + Config.Endurance.RecoveryBetweenStages
				local tools = Config.Endurance.CarryInstruments and table.clone(me.Instruments) or nil
				self.Services.NetworkService:push(
					player,
					"Endurance",
					{ Stage = stage, Next = stage + 1, Total = #stages, Integrity = nextIntegrity }
				)
				-- Record this stage's progression before moving on.
				local outcome = Report.outcome(state, me)
				local info = self:matchInfoFor(match, 1)
				pcall(
					self.Services.ProgressionService.matchCompleted,
					self.Services.ProgressionService,
					player,
					outcome,
					info
				)
				task.delay(4, function()
					if not player.Parent then
						self:close(match)
						return
					end
					local nextSpec = stageSpec(stage + 1, nextIntegrity, tools, match.Arena, match)
					attach(nextSpec, stage + 1)
					match.KeepArena = true
					local created = self:create(nextSpec)
					if created == nil then
						match.KeepArena = false
						self:close(match)
					end
				end)
				return true
			end
			self.Services.NetworkService:push(
				player,
				"Endurance",
				{ Stage = stage, Total = #stages, Finished = true, Reached = match.Info.EnduranceReached }
			)
			return false
		end
	end
	local spec = stageSpec(1, nil, nil, nil, nil)
	attach(spec, 1)
	local match, err = self:create(spec)
	if match == nil then
		return false, err
	end
	return true, match.Id
end

function MatchService:startSandbox(player: Player, custom)
	local clean = Rules.sanitizeCustom(custom)
	local bots = type(custom) == "table" and custom.Bots or nil
	local subjects = { { Kind = "Player", Player = player } }
	local botList = type(bots) == "table" and bots or { { Personality = "Ledger", Difficulty = "Standard" } }
	for _, bot in botList do
		if #subjects >= 4 then
			break
		end
		local persona = type(bot) == "table" and Personalities.ById[bot.Personality or ""] or nil
		local difficulty = type(bot) == "table" and bot.Difficulty or "Standard"
		if persona and persona.Selectable and (Difficulty.Tiers[difficulty] or difficulty == "Adaptive") then
			table.insert(subjects, { Kind = "AI", Personality = persona.Id, Difficulty = difficulty })
		end
	end
	if #subjects < 2 then
		table.insert(subjects, { Kind = "AI", Personality = "Ledger", Difficulty = "Standard" })
	end
	local match, err = self:create({
		ModeId = "Sandbox",
		Custom = clean,
		Subjects = subjects,
		Environment = clean.Environment,
		Info = { Solo = true, Sandbox = true },
	})
	if match == nil then
		return false, err
	end
	return true, match.Id
end

---------------------------------------------------------------------------
-- Service start
---------------------------------------------------------------------------

function MatchService:Start()
	local network = self.Services.NetworkService
	network:onAct(function(player, payload)
		self:handleAct(player, payload)
	end)
	network:onLook(function(player, payload)
		self:handleLook(player, payload)
	end)
	network:handle("Match.Sync", function(player)
		local match = byPlayer[player]
		if match == nil then
			local spectating = self.Services.SpectatorService:matchOf(player)
			if spectating then
				return true, self:beginPayload(spectating, nil)
			end
			return false, "Not in a match."
		end
		return true, self:beginPayload(match, self:subjectOf(match, player))
	end)
	network:handle("Match.Forfeit", function(player)
		if byPlayer[player] == nil then
			return false, "Not in a match."
		end
		self:forfeit(player, "Left")
		return true
	end)
	network:handle("Match.Leave", function(player)
		local match = byPlayer[player]
		if match == nil then
			return true
		end
		if match.Finished then
			local subjectId = self:subjectOf(match, player)
			if subjectId then
				if match.Rematch then
					match.Rematch[subjectId] = false
				end
				self:detach(match, subjectId)
			end
			return true
		end
		self:forfeit(player, "Left")
		return true
	end)
	network:handle("Match.Rematch", function(player, accept)
		return self:vote(player, accept)
	end)
	network:handle("Match.Emote", function(player, emoteId)
		local match = byPlayer[player]
		local item = Cosmetics.get(emoteId)
		if match == nil or item == nil or item.Category ~= "Emote" then
			return false, "Can't emote now."
		end
		if not self.Services.CosmeticService:owns(player, emoteId) then
			self.Services.AntiExploitService:flag(player, "unowned emote", "Moderate", emoteId)
			return false, "Not owned."
		end
		local subjectId = self:subjectOf(match, player)
		match.Dispatcher:broadcast("Emote", { Subject = subjectId, Anim = item.Data.Anim }, true)
		return true
	end)
	network:handle("Solo.Start", function(player, personality, difficulty)
		return self:startSolo(player, personality, difficulty)
	end)
	network:handle("Endurance.Start", function(player)
		return self:startEndurance(player)
	end)
	network:handle("Sandbox.Start", function(player, custom)
		return self:startSandbox(player, custom)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:onLeave(player)
	end)
	self.Services.DataService.Releasing:Connect(function(player)
		self:onReleasing(player)
	end)
	-- Rejoins are detected by ReconnectService, which calls onJoin first.
end

return MatchService

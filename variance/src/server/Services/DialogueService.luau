-- Surrogate remarks and announcer lines, chosen from Data/Dialogue.luau when
-- match events happen. Everything is a non-blocking subtitle: dialogue never
-- delays the game.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Dialogue = require(ReplicatedStorage.Variance.Data.Dialogue)
local Instruments = require(ReplicatedStorage.Variance.Core.Instruments)
local Format = require(ReplicatedStorage.Variance.Util.Format)

local DialogueService = {}

function DialogueService:Init(services)
	self.Services = services
end

local rng = Random.new()

local function pick(list: { string }?): string?
	if list == nil or #list == 0 then
		return nil
	end
	return list[rng:NextInteger(1, #list)]
end

-- Tries to have AI subject `speakerId` say something for `trigger`.
function DialogueService:say(match, speakerId: number, trigger: string, values: { [string]: any }?)
	local participant = match.Participants[speakerId]
	if participant == nil or participant.Kind ~= "AI" then
		return
	end
	local spec = Dialogue.Triggers[trigger]
	if spec == nil then
		return
	end
	match.DialogueCooldowns = match.DialogueCooldowns or {}
	local key = speakerId .. ":" .. trigger
	local now = os.clock()
	if (match.DialogueCooldowns[key] or 0) > now then
		return
	end
	if rng:NextNumber() > spec.Chance then
		return
	end
	local lines = Dialogue.Lines[participant.Personality or ""]
	local line = pick(lines and lines[trigger])
	if line == nil then
		return
	end
	match.DialogueCooldowns[key] = now + spec.Cooldown
	local text = Dialogue.fill(line, values or {})
	match.Dispatcher:broadcast("Dialogue", {
		Speaker = speakerId,
		Trigger = trigger,
		Text = text,
		Personality = participant.Personality,
		Duration = math.clamp(#text / 14, 1.8, 5),
	})
end

local function humanOpponentName(match, aiId: number): string
	for id, p in match.Participants do
		if id ~= aiId and p.Kind == "Player" then
			return p.Name
		end
	end
	return "Candidate"
end

-- Reacts to a presented batch of engine events.
function DialogueService:onEvents(match, events)
	local state = match.State
	for _, event in events do
		local data = event.Public
		local kind = event.Type
		for aiId, participant in match.Participants do
			if participant.Kind == "AI" and not state.Subjects[aiId].Forfeited then
				local name = humanOpponentName(match, aiId)
				if kind == "MatchStart" then
					self:say(match, aiId, "Intro", { name = name })
				elseif kind == "TrialEnd" then
					local won = data.WinnerTeam == state.Subjects[aiId].TeamId
					self:say(match, aiId, won and "TrialWin" or "TrialLose", { name = name })
				elseif kind == "MatchEnd" then
					local won = data.WinnerTeam == state.Subjects[aiId].TeamId
					self:say(match, aiId, won and "MatchWin" or "MatchLose", { name = name })
				elseif kind == "SuddenDeath" then
					self:say(match, aiId, "SuddenDeath", { name = name })
				elseif kind == "TrialStart" then
					for _, s in state.Subjects do
						if s.TrialWins == state.Rules.TrialsToWin - 1 then
							self:say(match, aiId, "MatchPoint", { name = name })
							break
						end
					end
				elseif kind == "FireResult" then
					local entry = state.Log[#state.Log]
					if entry and entry.Kind == "Fire" and entry.Actor ~= aiId then
						local selfShot = entry.Actor == entry.Target
						if selfShot and not entry.Charged and entry.PublicP >= 0.6 then
							self:say(match, aiId, "LuckyEscape", { name = name })
						elseif (not selfShot and entry.PublicP <= 0.25) or (selfShot and entry.PublicP >= 0.75) then
							self:say(match, aiId, "Unusual", { name = name })
						end
						local streak = participant.AI and participant.AI.Brain.tendencies.SelfStreak or 0
						if streak >= 3 then
							self:say(match, aiId, "SelfStreak", { name = name, n = streak })
						end
					end
				elseif kind == "Damage" and data.Amount > 0 then
					if data.Subject == aiId then
						if state.Subjects[aiId].Integrity == 1 then
							self:say(match, aiId, "LowSelf", { name = name })
						else
							self:say(match, aiId, "Hurt", { name = name })
						end
					elseif data.Actor == aiId then
						if state.Subjects[data.Subject] and state.Subjects[data.Subject].Integrity == 1 then
							self:say(match, aiId, "LowOpponent", { name = name })
						else
							self:say(match, aiId, "Hit", { name = name })
						end
					end
				elseif kind == "InstrumentUsed" then
					if data.Actor == aiId then
						self:say(match, aiId, "OwnItem", { name = name })
					else
						local used = state.Turn.Used
						if table.find(used, "Lens") and table.find(used, "Capacitor") then
							self:say(match, aiId, "OpponentCombo", { name = name })
						end
					end
				end
				-- The Proctor comments on your habits once it has a model of them.
				if participant.Personality == "Proctor" and kind == "FireResult" and participant.AI then
					local summary = participant.AI.Brain.tendencies:summary()
					if summary.Shots >= 4 then
						local lines = Dialogue.Lines.Proctor.Read
						local choice = lines[rng:NextInteger(1, #lines)]
						local values = { name = name }
						if string.find(choice, "{item}") then
							local fav = summary.Favourite and Instruments.get(summary.Favourite)
							if fav == nil then
								choice = nil
							else
								values.item = fav.Name
							end
						elseif string.find(choice, "{n}") then
							if summary.MaxSelfStreak < 2 then
								choice = nil
							else
								values.n = summary.MaxSelfStreak
							end
						elseif string.find(choice, "even odds") then
							if summary.EvenOddsSamples < 2 then
								choice = nil
							else
								values.rate = Format.percent(summary.EvenOddsSelfRate or 0)
							end
						else
							values.rate = Format.percent(summary.Deviation)
						end
						if choice then
							local spec = Dialogue.Triggers.Read
							local key = aiId .. ":Read"
							match.DialogueCooldowns = match.DialogueCooldowns or {}
							if (match.DialogueCooldowns[key] or 0) <= os.clock() and rng:NextNumber() <= spec.Chance then
								match.DialogueCooldowns[key] = os.clock() + spec.Cooldown
								local text = Dialogue.fill(choice, values)
								match.Dispatcher:broadcast("Dialogue", {
									Speaker = aiId,
									Trigger = "Read",
									Text = text,
									Personality = "Proctor",
									Duration = math.clamp(#text / 14, 2, 5),
								})
							end
						end
					end
				end
			end
		end
	end
end

-- A subject has been deciding for a long time.
function DialogueService:hesitation(match, humanId: number)
	for aiId, participant in match.Participants do
		if participant.Kind == "AI" then
			self:say(match, aiId, "Hesitation", { name = match.Participants[humanId] and match.Participants[humanId].Name or "" })
		end
	end
end

return DialogueService

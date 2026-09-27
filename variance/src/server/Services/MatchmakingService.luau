-- Public matchmaking queues (in-server).
--
-- Entries are groups (a solo player, or a private-lobby party for Crossfire).
-- Every tick each queue is scanned oldest-first:
--   * Duel queues pair two solo entries. Ranked pairs within a Standing window
--     that widens with waiting time (Core/Rating.window) and avoids rematching
--     the same two subjects back to back unless they've waited a while.
--   * Crossfire fills 4 seats, or starts with 3 after FillWait seconds.
--   * Casual queues backfill with a surrogate after BotAfter seconds. The
--     surrogate is always announced as one; it never pretends to be a player.
-- Matched entries are removed before the match is created, and re-queued at the
-- front if creation fails (e.g. every room is busy), so a cancel can never race
-- a match start.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Variance.Config)
local Rating = require(ReplicatedStorage.Variance.Core.Rating)
local Personalities = require(ReplicatedStorage.Variance.Core.AI.Personalities)

local MatchmakingService = {}

type Entry = { Players: { Player }, Joined: number, Rating: number, Party: boolean }

local queues: { [string]: { Entry } } = {}
local queuedIn: { [Player]: string } = {}
local recentPairs: { [string]: number } = {}
local rng = Random.new()

function MatchmakingService:Init(services)
	self.Services = services
	for id in Config.Matchmaking.Queues do
		queues[id] = {}
	end
end

function MatchmakingService:isQueued(player: Player): boolean
	return queuedIn[player] ~= nil
end

local function pushState(self, player: Player, queueId: string?, extra: { [string]: any }?)
	local payload = extra or {}
	payload.Queue = queueId
	if queueId then
		local def = Config.Matchmaking.Queues[queueId]
		payload.Name = def.Name
		payload.Waiting = #queues[queueId]
	end
	self.Services.NetworkService:push(player, "Queue", payload)
end

local function removeEntry(queueId: string, entry: Entry)
	local list = queues[queueId]
	local index = table.find(list, entry)
	if index then
		table.remove(list, index)
	end
	for _, player in entry.Players do
		if queuedIn[player] == queueId then
			queuedIn[player] = nil
		end
	end
end

local function entryOf(player: Player): (string?, Entry?)
	local queueId = queuedIn[player]
	if queueId == nil then
		return nil, nil
	end
	for _, entry in queues[queueId] do
		if table.find(entry.Players, player) then
			return queueId, entry
		end
	end
	return queueId, nil
end

function MatchmakingService:join(player: Player, queueId: string): (boolean, string?)
	local def = Config.Matchmaking.Queues[queueId]
	if def == nil then
		return false, "Unknown queue."
	end
	if queuedIn[player] then
		return false, "Already searching."
	end
	if self.Services.MatchService:isBusy(player) then
		return false, "Finish your current Trial first."
	end
	if self.Services.DataService:get(player) == nil then
		return false, "Profile still loading."
	end
	local members = { player }
	local lobby = self.Services.LobbyService:lobbyOf(player)
	if lobby then
		if queueId ~= "Crossfire" then
			return false, "Leave your private lobby to queue alone."
		end
		if lobby.Host ~= player then
			return false, "Only the lobby host can queue the party."
		end
		members = table.clone(lobby.Members)
		if #members > def.Size then
			return false, "Party too large for this queue."
		end
		for _, m in members do
			if queuedIn[m] or self.Services.MatchService:isBusy(m) then
				return false, m.DisplayName .. " is busy."
			end
		end
	end
	if def.Ranked then
		local ok, reason = self.Services.RankedService:canQueue(player)
		if not ok then
			return false, reason
		end
	end
	local entry: Entry = {
		Players = members,
		Joined = os.clock(),
		Rating = self.Services.RankedService:rating(player),
		Party = #members > 1,
	}
	table.insert(queues[queueId], entry)
	for _, m in members do
		queuedIn[m] = queueId
		pushState(self, m, queueId, { Joined = workspace:GetServerTimeNow() })
	end
	return true
end

function MatchmakingService:leave(player: Player)
	local queueId, entry = entryOf(player)
	if queueId and entry then
		removeEntry(queueId, entry)
		for _, m in entry.Players do
			if m.Parent then
				pushState(self, m, nil, { Cancelled = true })
			end
		end
	elseif queueId then
		queuedIn[player] = nil
	end
end

local function pairKey(a: Player, b: Player): string
	local x, y = a.UserId, b.UserId
	if x > y then
		x, y = y, x
	end
	return tostring(x) .. ":" .. tostring(y)
end

local function valid(self, entry: Entry): boolean
	for _, p in entry.Players do
		if not p.Parent or self.Services.MatchService:isBusy(p) then
			return false
		end
	end
	return true
end

local function subjectsFor(entries: { Entry })
	local subjects = {}
	for _, entry in entries do
		for _, p in entry.Players do
			table.insert(subjects, { Kind = "Player", Player = p })
		end
	end
	return subjects
end

local function randomSurrogate()
	local list = Personalities.selectable(false)
	return list[rng:NextInteger(1, #list)]
end

function MatchmakingService:launch(queueId: string, entries: { Entry }, bots: number)
	local def = Config.Matchmaking.Queues[queueId]
	for _, entry in entries do
		removeEntry(queueId, entry)
	end
	local subjects = subjectsFor(entries)
	for _ = 1, bots do
		local persona = randomSurrogate()
		table.insert(subjects, { Kind = "AI", Personality = persona.Id, Difficulty = Config.Matchmaking.BotDifficulty })
	end
	local match, err = self.Services.MatchService:create({
		ModeId = def.Mode,
		Subjects = subjects,
		Info = { Ranked = def.Ranked == true, Queue = queueId, Backfill = bots > 0, Solo = #subjects - bots == 1 },
	})
	if match == nil then
		-- Put them back at the front and tell them why.
		for i = #entries, 1, -1 do
			local entry = entries[i]
			table.insert(queues[queueId], 1, entry)
			for _, p in entry.Players do
				queuedIn[p] = queueId
				self.Services.NetworkService:notify(p, "STILL SEARCHING", err or "Waiting for a free room.", "Warn")
			end
		end
		return false
	end
	for _, entry in entries do
		for _, p in entry.Players do
			pushState(self, p, nil, { Matched = true, Backfill = bots > 0 })
		end
	end
	if #entries == 2 and #entries[1].Players == 1 and #entries[2].Players == 1 then
		recentPairs[pairKey(entries[1].Players[1], entries[2].Players[1])] = os.clock()
	end
	return true
end

function MatchmakingService:tickQueue(queueId: string)
	local def = Config.Matchmaking.Queues[queueId]
	local list = queues[queueId]
	-- Drop entries whose players left or got busy.
	for i = #list, 1, -1 do
		if not valid(self, list[i]) then
			local entry = list[i]
			removeEntry(queueId, entry)
			for _, p in entry.Players do
				if p.Parent then
					pushState(self, p, nil, { Cancelled = true })
				end
			end
		end
	end
	local now = os.clock()
	if def.Size == 2 then
		local i = 1
		while i <= #list do
			local a = list[i]
			local partner = nil
			if #a.Players == 1 then
				for j = i + 1, #list do
					local b = list[j]
					if #b.Players == 1 then
						local waited = math.max(now - a.Joined, now - b.Joined)
						local ok = true
						if def.Ranked then
							ok = math.abs(a.Rating - b.Rating) <= Rating.window(waited)
						end
						local last = recentPairs[pairKey(a.Players[1], b.Players[1])]
						if last and now - last < 600 and waited < 30 then
							ok = false
						end
						if ok then
							partner = b
							break
						end
					end
				end
			end
			if partner then
				if self:launch(queueId, { a, partner }, 0) then
					i = 1
				else
					return
				end
			elseif def.BotAfter and now - a.Joined >= def.BotAfter then
				if not self:launch(queueId, { a }, 1) then
					return
				end
				i = 1
			else
				i += 1
			end
		end
	else
		-- Group queue (Crossfire).
		local seats = 0
		local picked = {}
		for _, entry in list do
			if seats + #entry.Players <= def.Size then
				table.insert(picked, entry)
				seats += #entry.Players
			end
		end
		if #picked == 0 then
			return
		end
		local oldest = now - picked[1].Joined
		local full = seats >= def.Size
		local enough = seats >= def.MinSize and oldest >= (def.FillWait or 25)
		if full or enough then
			self:launch(queueId, picked, 0)
		elseif def.BotAfter and oldest >= def.BotAfter then
			self:launch(queueId, picked, math.max(def.MinSize - seats, 0))
		end
	end
end

function MatchmakingService:Start()
	local network = self.Services.NetworkService
	network:handle("Queue.Join", function(player, queueId)
		return self:join(player, queueId)
	end)
	network:handle("Queue.Leave", function(player)
		self:leave(player)
		return true
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:leave(player)
	end)
	task.spawn(function()
		while true do
			task.wait(Config.Matchmaking.TickInterval)
			for queueId in queues do
				local ok, err = pcall(self.tickQueue, self, queueId)
				if not ok then
					warn("[VARIANCE/Matchmaking] " .. queueId .. ": " .. tostring(err))
				end
			end
			-- Forget old pairings.
			local now = os.clock()
			for key, t in recentPairs do
				if now - t > 900 then
					recentPairs[key] = nil
				end
			end
		end
	end)
end

return MatchmakingService

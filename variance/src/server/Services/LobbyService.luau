-- Private lobbies ("Private Trials") and parties.
--
-- * A host creates a lobby and gets a short invite code. Friends join by code
--   (same server, or across servers: the code is registered in MemoryStore with
--   this server's JobId and joiners are teleported here with the code in their
--   teleport data) or through a Roblox game invite whose LaunchData carries it.
-- * The host configures custom rules (sanitized by Core/Rules), adds surrogate
--   bots, chooses a single match or a tournament, and starts once everyone else
--   is ready. If the host leaves, the longest-standing member takes over; an
--   empty or long-idle lobby closes.

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Variance.Config)
local Rules = require(ReplicatedStorage.Variance.Core.Rules)
local Personalities = require(ReplicatedStorage.Variance.Core.AI.Personalities)
local Difficulty = require(ReplicatedStorage.Variance.Core.AI.Difficulty)

local LobbyService = {}

local lobbies: { [string]: any } = {}
local memberOf: { [Player]: any } = {}
local recentGroups: { [string]: { Count: number, Since: number } } = {}
local map = nil
local rng = Random.new()

function LobbyService:Init(services)
	self.Services = services
	local ok, result = pcall(function()
		return MemoryStoreService:GetHashMap(Config.Data.MemoryStoreMap)
	end)
	if ok then
		map = result
	end
end

function LobbyService:lobbyOf(player: Player)
	return memberOf[player]
end

local function normalize(code: string): string
	return string.upper((string.gsub(code, "[^%w]", "")))
end

local function newCode(): string
	local alphabet = Config.Lobby.CodeAlphabet
	for _ = 1, 50 do
		local chars = {}
		for i = 1, Config.Lobby.CodeLength do
			local k = rng:NextInteger(1, #alphabet)
			chars[i] = string.sub(alphabet, k, k)
		end
		local code = table.concat(chars)
		if lobbies[code] == nil then
			return code
		end
	end
	return tostring(rng:NextInteger(100000, 999999))
end

function LobbyService:state(lobby)
	local members = {}
	for _, p in lobby.Members do
		local profile = self.Services.DataService:get(p)
		table.insert(members, {
			UserId = p.UserId,
			Name = p.DisplayName,
			Ready = lobby.Ready[p] == true or p == lobby.Host,
			Level = profile and profile.Data.Level or 1,
			Host = p == lobby.Host,
		})
	end
	local total = #lobby.Members + #lobby.Bots
	local canStart, why = self:canStart(lobby)
	return {
		Code = lobby.Code,
		Host = lobby.Host.UserId,
		Members = members,
		Bots = lobby.Bots,
		Rules = lobby.Rules,
		Format = lobby.Format,
		Total = total,
		CanStart = canStart,
		StartBlocked = why,
		Describe = Rules.describe(Rules.build(total > 2 and "Crossfire" or "Standard", lobby.Rules)),
		InMatch = lobby.InMatch,
		Tournament = lobby.TournamentState,
	}
end

function LobbyService:broadcast(lobby)
	local state = self:state(lobby)
	for _, p in lobby.Members do
		self.Services.NetworkService:push(p, "Lobby", state)
	end
end

local function touch(lobby)
	lobby.LastActive = os.clock()
end

local function register(lobby)
	if map == nil then
		return
	end
	task.spawn(function()
		pcall(function()
			map:SetAsync("lobby_" .. lobby.Code, { JobId = game.JobId, PlaceId = game.PlaceId }, Config.Lobby.CodeTTL)
		end)
	end)
end

local function unregister(code: string)
	if map == nil then
		return
	end
	task.spawn(function()
		pcall(function()
			map:RemoveAsync("lobby_" .. code)
		end)
	end)
end

function LobbyService:canStart(lobby): (boolean, string?)
	if lobby.InMatch then
		return false, "A Trial is in progress."
	end
	local total = #lobby.Members + #lobby.Bots
	if lobby.Format == "Tournament" then
		if total < Config.Tournament.MinPlayers then
			return false, string.format("Tournaments need %d subjects.", Config.Tournament.MinPlayers)
		end
		if total > Config.Tournament.MaxPlayers then
			return false, "Too many subjects for a tournament."
		end
	else
		if total < 2 then
			return false, "Add a subject or a surrogate."
		end
		if total > 4 then
			return false, "A single table seats four."
		end
	end
	for _, p in lobby.Members do
		if p ~= lobby.Host and not lobby.Ready[p] then
			return false, "Waiting for everyone to be ready."
		end
		if self.Services.MatchService:isBusy(p) then
			return false, p.DisplayName .. " is in another Trial."
		end
	end
	return true
end

function LobbyService:create(player: Player): (boolean, any)
	if memberOf[player] then
		return true, self:state(memberOf[player])
	end
	if self.Services.MatchService:isBusy(player) then
		return false, "Finish your current Trial first."
	end
	self.Services.MatchmakingService:leave(player)
	local code = newCode()
	local lobby = {
		Code = code,
		Host = player,
		Members = { player },
		Ready = {},
		Bots = {},
		Rules = Rules.defaultCustom(),
		Format = "Match",
		Created = os.clock(),
		LastActive = os.clock(),
		InMatch = false,
	}
	lobbies[code] = lobby
	memberOf[player] = lobby
	register(lobby)
	self:broadcast(lobby)
	return true, self:state(lobby)
end

function LobbyService:join(player: Player, rawCode: string): (boolean, any)
	local code = normalize(rawCode)
	if #code < 4 or #code > 10 then
		return false, "That code isn't valid."
	end
	if memberOf[player] then
		if memberOf[player].Code == code then
			return true, self:state(memberOf[player])
		end
		self:leave(player)
	end
	if self.Services.MatchService:isBusy(player) then
		return false, "Finish your current Trial first."
	end
	local lobby = lobbies[code]
	if lobby then
		if #lobby.Members >= Config.Lobby.MaxMembers then
			return false, "That lobby is full."
		end
		self.Services.MatchmakingService:leave(player)
		table.insert(lobby.Members, player)
		memberOf[player] = lobby
		touch(lobby)
		self:broadcast(lobby)
		return true, self:state(lobby)
	end
	-- Another server?
	if map == nil then
		return false, "No lobby with that code."
	end
	local ok, entry = pcall(function()
		return map:GetAsync("lobby_" .. code)
	end)
	if not ok or type(entry) ~= "table" or type(entry.JobId) ~= "string" then
		return false, "No lobby with that code."
	end
	if entry.JobId == game.JobId then
		return false, "That lobby has closed."
	end
	local options = Instance.new("TeleportOptions")
	options.ServerInstanceId = entry.JobId
	options:SetTeleportData({ LobbyCode = code })
	local sent, err =
		pcall(TeleportService.TeleportAsync, TeleportService, entry.PlaceId or game.PlaceId, { player }, options)
	if not sent then
		return false, "Couldn't reach that lobby: " .. tostring(err)
	end
	return true, { Teleporting = true }
end

function LobbyService:leave(player: Player)
	local lobby = memberOf[player]
	if lobby == nil then
		return
	end
	memberOf[player] = nil
	local index = table.find(lobby.Members, player)
	if index then
		table.remove(lobby.Members, index)
	end
	lobby.Ready[player] = nil
	if player.Parent then
		self.Services.NetworkService:push(player, "Lobby", nil)
	end
	if #lobby.Members == 0 then
		lobbies[lobby.Code] = nil
		unregister(lobby.Code)
		return
	end
	if lobby.Host == player then
		lobby.Host = lobby.Members[1]
		lobby.Ready[lobby.Host] = nil
		self.Services.NetworkService:notify(lobby.Host, "YOU ARE THE HOST", "The previous host left the lobby.", "Info")
	end
	touch(lobby)
	self:broadcast(lobby)
end

local function requireHost(lobby, player: Player): boolean
	return lobby ~= nil and lobby.Host == player
end

-- XP decay for playing the same private group repeatedly (anti-farming).
local function repeatFactor(players: { Player }): number
	local ids = {}
	for _, p in players do
		table.insert(ids, p.UserId)
	end
	table.sort(ids)
	local key = table.concat(ids, ":")
	local record = recentGroups[key]
	if record == nil or os.clock() - record.Since > 86400 then
		record = { Count = 0, Since = os.clock() }
	end
	record.Count += 1
	recentGroups[key] = record
	return math.max(0.25, 1 - Config.Economy.RepeatOpponentDecay * (record.Count - 1))
end

function LobbyService:start(player: Player): (boolean, string?)
	local lobby = memberOf[player]
	if not requireHost(lobby, player) then
		return false, "Only the host can start."
	end
	local ok, why = self:canStart(lobby)
	if not ok then
		return false, why
	end
	if lobby.Format == "Tournament" then
		return self.Services.TournamentService:start(lobby)
	end
	local subjects = {}
	for _, p in lobby.Members do
		self.Services.MatchmakingService:leave(p)
		table.insert(subjects, { Kind = "Player", Player = p })
	end
	for _, bot in lobby.Bots do
		table.insert(subjects, { Kind = "AI", Personality = bot.Personality, Difficulty = bot.Difficulty })
	end
	local modeId = #subjects > 2 and "Crossfire" or "Standard"
	local match, err = self.Services.MatchService:create({
		ModeId = modeId,
		Custom = lobby.Rules,
		Subjects = subjects,
		Environment = lobby.Rules.Environment,
		Info = {
			Private = true,
			LobbyCode = lobby.Code,
			RepeatFactor = repeatFactor(lobby.Members),
			Solo = #lobby.Members == 1,
		},
		OnEnd = function()
			lobby.InMatch = false
			for p in lobby.Ready do
				lobby.Ready[p] = nil
			end
			task.delay(1, function()
				if lobbies[lobby.Code] == lobby then
					self:broadcast(lobby)
				end
			end)
			return false
		end,
	})
	if match == nil then
		return false, err
	end
	lobby.InMatch = true
	touch(lobby)
	self:broadcast(lobby)
	return true
end

function LobbyService:Start()
	local network = self.Services.NetworkService
	network:handle("Lobby.Create", function(player)
		return self:create(player)
	end)
	network:handle("Lobby.Join", function(player, code)
		return self:join(player, code)
	end)
	network:handle("Lobby.Leave", function(player)
		self:leave(player)
		return true
	end)
	network:handle("Lobby.SetRules", function(player, custom)
		local lobby = memberOf[player]
		if not requireHost(lobby, player) then
			return false, "Only the host can change the rules."
		end
		lobby.Rules = Rules.sanitizeCustom(custom)
		for p in lobby.Ready do
			lobby.Ready[p] = nil -- rules changed: everyone re-confirms
		end
		touch(lobby)
		self:broadcast(lobby)
		return true, lobby.Rules
	end)
	network:handle("Lobby.SetReady", function(player, ready)
		local lobby = memberOf[player]
		if lobby == nil then
			return false, "Not in a lobby."
		end
		lobby.Ready[player] = ready or nil
		touch(lobby)
		self:broadcast(lobby)
		return true
	end)
	network:handle("Lobby.SetFormat", function(player, format)
		local lobby = memberOf[player]
		if not requireHost(lobby, player) then
			return false, "Only the host can change the format."
		end
		if format ~= "Match" and format ~= "Tournament" then
			return false, "Unknown format."
		end
		lobby.Format = format
		touch(lobby)
		self:broadcast(lobby)
		return true
	end)
	network:handle("Lobby.Start", function(player)
		return self:start(player)
	end)
	network:handle("Lobby.Kick", function(player, userId)
		local lobby = memberOf[player]
		if not requireHost(lobby, player) then
			return false, "Only the host can remove subjects."
		end
		for _, p in lobby.Members do
			if p.UserId == userId and p ~= player then
				self:leave(p)
				self.Services.NetworkService:notify(p, "REMOVED", "The host removed you from the lobby.", "Warn")
				return true
			end
		end
		return false, "Not in this lobby."
	end)
	network:handle("Lobby.AddBot", function(player, personality, difficulty)
		local lobby = memberOf[player]
		if not requireHost(lobby, player) then
			return false, "Only the host can add surrogates."
		end
		local persona = Personalities.ById[personality]
		if persona == nil or not persona.Selectable then
			return false, "Unknown surrogate."
		end
		if difficulty ~= "Adaptive" and Difficulty.Tiers[difficulty] == nil then
			return false, "Unknown difficulty."
		end
		if #lobby.Bots >= Config.Lobby.MaxBots and lobby.Format ~= "Tournament" then
			return false, "Too many surrogates."
		end
		if #lobby.Bots + #lobby.Members >= (lobby.Format == "Tournament" and Config.Tournament.MaxPlayers or 4) then
			return false, "No seats left."
		end
		table.insert(lobby.Bots, { Personality = persona.Id, Difficulty = difficulty, Name = persona.Name })
		touch(lobby)
		self:broadcast(lobby)
		return true
	end)
	network:handle("Lobby.RemoveBot", function(player, index)
		local lobby = memberOf[player]
		if not requireHost(lobby, player) then
			return false, "Only the host can remove surrogates."
		end
		if lobby.Bots[index] == nil then
			return false, "No such surrogate."
		end
		table.remove(lobby.Bots, index)
		touch(lobby)
		self:broadcast(lobby)
		return true
	end)

	-- Join through teleport data (cross-server code) or a friend invite's LaunchData.
	local function autoJoin(player: Player)
		local ok, joinData = pcall(player.GetJoinData, player)
		if not ok or type(joinData) ~= "table" then
			return
		end
		local code = nil
		if type(joinData.TeleportData) == "table" and type(joinData.TeleportData.LobbyCode) == "string" then
			code = joinData.TeleportData.LobbyCode
		elseif type(joinData.LaunchData) == "string" and #joinData.LaunchData <= 12 then
			code = joinData.LaunchData
		end
		if code then
			self.Services.DataService:waitFor(player, 30)
			if player.Parent then
				local joined, result = self:join(player, code)
				if joined then
					self.Services.NetworkService:push(player, "OpenScreen", { Screen = "Private" })
				else
					self.Services.NetworkService:notify(player, "INVITE", tostring(result), "Warn")
				end
			end
		end
	end
	Players.PlayerAdded:Connect(function(player)
		task.spawn(autoJoin, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:leave(player)
	end)
	-- Idle lobbies close; live ones refresh their code registration.
	task.spawn(function()
		while true do
			task.wait(60)
			for code, lobby in lobbies do
				if not lobby.InMatch and os.clock() - lobby.LastActive > Config.Lobby.IdleTimeout then
					for _, p in table.clone(lobby.Members) do
						self.Services.NetworkService:notify(
							p,
							"LOBBY CLOSED",
							"Closed after a long period of inactivity.",
							"Info"
						)
						self:leave(p)
					end
					lobbies[code] = nil
					unregister(code)
				elseif os.clock() - lobby.Created > Config.Lobby.CodeTTL * 0.8 then
					register(lobby)
					lobby.Created = os.clock()
				end
			end
		end
	end)
end

return LobbyService

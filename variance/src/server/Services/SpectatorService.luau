-- Watching live Trials from the lobby.
--
-- A spectator's character stays in the lobby; their Player.ReplicationFocus
-- moves to the arena so the room streams in, and their camera flies there.
-- Spectators only ever receive public information (the Dispatcher never sends
-- them private payloads), delayed in competitive matches.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Variance.Config)
local Modes = require(ReplicatedStorage.Variance.Core.Modes)

local SpectatorService = {}

local watching: { [Player]: any } = {}

function SpectatorService:Init(services)
	self.Services = services
end

function SpectatorService:matchOf(player: Player)
	return watching[player]
end

local function spectatable(match): boolean
	return not match.Closed and not match.Info.Tutorial and match.State.Rules.AllowSpectators ~= false
end

function SpectatorService:list()
	local out = {}
	for id, match in self.Services.MatchService:all() do
		if spectatable(match) then
			local names, score = {}, {}
			for sid, p in match.Participants do
				table.insert(names, p.Name)
				table.insert(score, tostring(match.State.Subjects[sid].TrialWins))
			end
			local mode = Modes.get(match.State.Rules.ModeId)
			local count = 0
			for _ in match.Spectators do
				count += 1
			end
			table.insert(out, {
				MatchId = id,
				Mode = mode and mode.Name or match.State.Rules.ModeId,
				Names = names,
				Score = table.concat(score, "-"),
				Trial = match.State.Trial,
				Environment = match.Arena.Environment,
				Spectators = count,
				Competitive = (match.State.Rules.SpectatorDelay or 0) > 0,
				Phase = match.Phase,
			})
		end
	end
	return out
end

function SpectatorService:start(player: Player, matchId: string): (boolean, any)
	if self.Services.MatchService:isBusy(player) then
		return false, "You're in a Trial."
	end
	local match = self.Services.MatchService:get(matchId)
	if match == nil or not spectatable(match) then
		return false, "That Trial has ended."
	end
	local count = 0
	for _ in match.Spectators do
		count += 1
	end
	if count >= Config.Spectate.MaxPerMatch then
		return false, "The gallery is full."
	end
	self:stop(player, true)
	self.Services.MatchmakingService:leave(player)
	match.Spectators[player] = true
	watching[player] = match
	local focus = match.Arena.Model:FindFirstChild("KeyMount")
	player.ReplicationFocus = focus
	task.spawn(function()
		pcall(player.RequestStreamAroundAsync, player, self.Services.ArenaService:centre(match.Arena), 5)
		if watching[player] == match then
			self.Services.NetworkService:match(player, "Begin", self.Services.MatchService:beginPayload(match, nil))
		end
	end)
	self.Services.LobbyWorldService:refreshLive()
	return true
end

function SpectatorService:stop(player: Player, quiet: boolean?)
	local match = watching[player]
	if match == nil then
		return
	end
	watching[player] = nil
	match.Spectators[player] = nil
	if player.Parent then
		player.ReplicationFocus = nil
		if not quiet then
			self.Services.NetworkService:match(player, "End", { MatchId = match.Id, Spectating = true })
		end
	end
end

function SpectatorService:Start()
	local network = self.Services.NetworkService
	network:handle("Spectate.List", function()
		return true, self:list()
	end)
	network:handle("Spectate.Start", function(player, matchId)
		return self:start(player, matchId)
	end)
	network:handle("Spectate.Stop", function(player)
		self:stop(player)
		return true
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:stop(player, true)
	end)
end

return SpectatorService

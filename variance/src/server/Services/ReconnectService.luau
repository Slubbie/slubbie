-- Getting a disconnected subject back to their match.
--
-- Same server: MatchService.onJoin rebinds them to their seat automatically.
-- Other server (Roblox usually sends a rejoin elsewhere): while a PvP match is
-- live, each subject's entry in MemoryStore points at this server. When they
-- join any server, we look it up and offer to take them back; accepting
-- teleports them to that exact server instance within the reconnect grace.

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Variance.Config)

local ReconnectService = {}

local map = nil
local offers: { [Player]: { JobId: string, PlaceId: number } } = {}

function ReconnectService:Init(services)
	self.Services = services
	local ok, result = pcall(function()
		return MemoryStoreService:GetHashMap(Config.Data.MemoryStoreMap)
	end)
	if ok then
		map = result
	end
end

local function key(userId: number): string
	return "active_" .. tostring(userId)
end

function ReconnectService:track(match)
	if map == nil or not match.Info.PvP then
		return
	end
	for _, p in match.Participants do
		if p.Kind == "Player" and p.UserId then
			task.spawn(function()
				pcall(function()
					map:SetAsync(key(p.UserId), { JobId = game.JobId, PlaceId = game.PlaceId, MatchId = match.Id }, 3600)
				end)
			end)
		end
	end
end

function ReconnectService:clear(match)
	if map == nil then
		return
	end
	for _, p in match.Participants do
		if p.Kind == "Player" and p.UserId then
			task.spawn(function()
				pcall(function()
					map:RemoveAsync(key(p.UserId))
				end)
			end)
		end
	end
end

local function check(self, player: Player)
	if map == nil or self.Services.MatchService:onJoin(player) then
		return
	end
	local ok, entry = pcall(function()
		return map:GetAsync(key(player.UserId))
	end)
	if not ok or type(entry) ~= "table" or entry.JobId == game.JobId or type(entry.JobId) ~= "string" or entry.JobId == "" then
		return
	end
	offers[player] = { JobId = entry.JobId, PlaceId = entry.PlaceId or game.PlaceId }
	self.Services.DataService:waitFor(player, 20)
	if player.Parent then
		self.Services.NetworkService:push(player, "Reconnect", { MatchId = entry.MatchId, Grace = Config.Match.ReconnectGrace })
	end
end

function ReconnectService:Start()
	local network = self.Services.NetworkService
	network:handle("Reconnect.Accept", function(player)
		local offer = offers[player]
		if offer == nil then
			return false, "Nothing to return to."
		end
		offers[player] = nil
		local options = Instance.new("TeleportOptions")
		options.ServerInstanceId = offer.JobId
		local ok, err = pcall(TeleportService.TeleportAsync, TeleportService, offer.PlaceId, { player }, options)
		if not ok then
			return false, "Couldn't return: " .. tostring(err)
		end
		return true
	end)
	network:handle("Reconnect.Decline", function(player)
		offers[player] = nil
		if map then
			task.spawn(function()
				pcall(function()
					map:RemoveAsync(key(player.UserId))
				end)
			end)
		end
		return true
	end)
	Players.PlayerAdded:Connect(function(player)
		task.spawn(check, self, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		offers[player] = nil
	end)
end

return ReconnectService

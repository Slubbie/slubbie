-- Global leaderboards (ranked Standing, lifetime wins) on OrderedDataStores.
-- Writes are batched per user and flushed periodically; reads are cached and
-- refreshed on a timer so the lobby boards and menus never hit the store directly.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Variance.Config)
local Signal = require(ReplicatedStorage.Variance.Util.Signal)

local LeaderboardService = {}
LeaderboardService.Updated = Signal.new() -- (board, entries)

local stores: { [string]: OrderedDataStore } = {}
local pending: { [string]: { [number]: number } } = {}
local cache: { [string]: { Updated: number, Entries: { any } } } = {}
local names: { [number]: string } = {}

local TOP = 50

function LeaderboardService:Init(services)
	self.Services = services
	for board, storeName in Config.Data.Leaderboards do
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(storeName)
		end)
		if ok then
			stores[board] = store
		end
		pending[board] = {}
		cache[board] = { Updated = 0, Entries = {} }
	end
end

function LeaderboardService:submit(board: string, userId: number, value: number)
	if pending[board] == nil or userId <= 0 then
		return
	end
	pending[board][userId] = math.max(0, math.floor(value))
end

local function nameOf(userId: number): string
	if names[userId] then
		return names[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		names[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	names[userId] = ok and name or ("Subject " .. tostring(userId))
	return names[userId]
end

local function flush()
	for board, entries in pending do
		local store = stores[board]
		if store then
			for userId, value in entries do
				entries[userId] = nil
				local ok, err = pcall(store.SetAsync, store, tostring(userId), value)
				if not ok then
					warn("[VARIANCE/Leaderboard] write failed: " .. tostring(err))
					if string.find(tostring(err), "StudioAccessToApisNotAllowed") then
						stores[board] = nil
						break
					end
				end
				task.wait(0.2)
			end
		end
	end
end

local function refresh(board: string)
	local store = stores[board]
	if store == nil then
		return
	end
	local ok, pages = pcall(store.GetSortedAsync, store, false, TOP)
	if not ok then
		return
	end
	local entries = {}
	local okPage, page = pcall(pages.GetCurrentPage, pages)
	if not okPage then
		return
	end
	for rank, item in page do
		local userId = tonumber(item.key) or 0
		table.insert(entries, { Rank = rank, UserId = userId, Name = nameOf(userId), Value = item.value })
	end
	cache[board] = { Updated = os.time(), Entries = entries }
	LeaderboardService.Updated:Fire(board, entries)
end

function LeaderboardService:get(board: string)
	return cache[board]
end

function LeaderboardService:Start()
	self.Services.NetworkService:handle("Leaderboard.Get", function(_player, board)
		local entry = cache[board]
		if entry == nil then
			return false, "Unknown board."
		end
		return true, entry
	end)
	task.spawn(function()
		while true do
			flush()
			for board in stores do
				refresh(board)
			end
			task.wait(Config.Data.LeaderboardRefresh)
		end
	end)
	game:BindToClose(flush)
end

return LeaderboardService

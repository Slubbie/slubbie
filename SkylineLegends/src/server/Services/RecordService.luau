-- Course records: global leaderboards, friends' times and ghost replays.
--
-- Only standardized runs (ranked time trials) go on the boards, so upgrades
-- from the skill tree never decide who's fastest. Times are stored in
-- OrderedDataStores (centiseconds, lower is better); ghosts in a DataStore
-- keyed by course and runner. Without DataStore access (Studio), records are
-- kept in memory for the session.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local RecordService = {}

local BOARD_PREFIX = "SkylineLegends_Board_v1_"
local GHOST_STORE = "SkylineLegends_Ghosts_v1"
local CACHE_SECONDS = 60

export type Entry = { UserId: number, Name: string, Seconds: number, Rank: number }

local online = true
local ghostStore: DataStore? = nil
local boards: { [string]: OrderedDataStore } = {}
local memoryBoards: { [string]: { [number]: number } } = {}
local memoryGhosts: { [string]: any } = {}
local names: { [number]: string } = {}
local topCache: { [string]: { Time: number, Entries: { Entry } } } = {}
local friendCache: { [number]: { Time: number, Ids: { number } } } = {}

local function boardFor(courseId: string): OrderedDataStore?
	if not online then
		return nil
	end
	local existing = boards[courseId]
	if existing then
		return existing
	end
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(BOARD_PREFIX .. courseId)
	end)
	if ok then
		boards[courseId] = result
		return result
	end
	online = false
	return nil
end

local function nameFor(userId: number): string
	local cached = names[userId]
	if cached then
		return cached
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		names[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local name = if ok and type(result) == "string" then result else ("Runner " .. userId)
	names[userId] = name
	return name
end

local function failed(err: any)
	local text = tostring(err)
	if string.find(text, "403") or string.find(text, "API") or string.find(text, "Studio") then
		online = false
	end
end

-- Leaderboards ------------------------------------------------------------------------------------

-- Submit a ranked time. Keeps the best; returns true if it improved.
function RecordService.Submit(courseId: string, player: Player, seconds: number): boolean
	local centis = math.floor(seconds * 100 + 0.5)
	local userId = player.UserId
	names[userId] = player.DisplayName
	topCache[courseId] = nil
	-- Always mirrored in memory, so this server's boards work even if the store hiccups.
	local memory = memoryBoards[courseId] or {}
	memoryBoards[courseId] = memory
	local memoryImproved = not memory[userId] or centis < memory[userId]
	if memoryImproved then
		memory[userId] = centis
	end
	local board = boardFor(courseId)
	if not board then
		return memoryImproved
	end
	local improved = false
	local ok, err = pcall(function()
		board:UpdateAsync(tostring(userId), function(old)
			if type(old) == "number" and old <= centis then
				return nil
			end
			improved = true
			return centis
		end)
	end)
	if not ok then
		failed(err)
		return memoryImproved
	end
	return improved
end

-- Top `count` times on a course.
function RecordService.Top(courseId: string, count: number?): { Entry }
	local wanted = math.clamp(count or 10, 1, 50)
	local cached = topCache[courseId]
	if cached and os.clock() - cached.Time < CACHE_SECONDS and #cached.Entries >= math.min(wanted, #cached.Entries) then
		return cached.Entries
	end
	local entries: { Entry } = {}
	local board = boardFor(courseId)
	if board then
		local ok, err = pcall(function()
			local pages = board:GetSortedAsync(true, wanted)
			for rank, item in pages:GetCurrentPage() do
				local userId = tonumber(item.key) or 0
				table.insert(entries, { UserId = userId, Name = nameFor(userId), Seconds = item.value / 100, Rank = rank })
			end
		end)
		if not ok then
			failed(err)
		end
	end
	if not board or not online then
		local memory = memoryBoards[courseId] or {}
		local list = {}
		for userId, centis in memory do
			table.insert(list, { UserId = userId, Centis = centis })
		end
		table.sort(list, function(a, b)
			return a.Centis < b.Centis
		end)
		entries = {}
		for rank = 1, math.min(wanted, #list) do
			local item = list[rank]
			table.insert(entries, { UserId = item.UserId, Name = nameFor(item.UserId), Seconds = item.Centis / 100, Rank = rank })
		end
	end
	topCache[courseId] = { Time = os.clock(), Entries = entries }
	return entries
end

-- A single runner's ranked best (seconds) or nil.
function RecordService.Best(courseId: string, userId: number): number?
	local board = boardFor(courseId)
	if board then
		local ok, result = pcall(function()
			return board:GetAsync(tostring(userId))
		end)
		if ok then
			return if type(result) == "number" then result / 100 else nil
		end
		failed(result)
	end
	local memory = memoryBoards[courseId]
	local centis = memory and memory[userId]
	return if centis then centis / 100 else nil
end

local function friendIds(player: Player): { number }
	local cached = friendCache[player.UserId]
	if cached and os.clock() - cached.Time < 300 then
		return cached.Ids
	end
	local ids = {}
	local ok = pcall(function()
		local pages = Players:GetFriendsAsync(player.UserId)
		local scanned = 0
		while scanned < 3 do
			for _, friend in pages:GetCurrentPage() do
				table.insert(ids, friend.Id)
				names[friend.Id] = friend.DisplayName or friend.Username
			end
			scanned += 1
			if pages.IsFinished or #ids >= 60 then
				break
			end
			pages:AdvanceToNextPageAsync()
		end
	end)
	if not ok then
		-- Fall back to friends in this server.
		for _, other in Players:GetPlayers() do
			if other ~= player then
				local isFriend = false
				pcall(function()
					isFriend = (player :: any):IsFriendsWithAsync(other.UserId)
				end)
				if isFriend then
					table.insert(ids, other.UserId)
				end
			end
		end
	end
	friendCache[player.UserId] = { Time = os.clock(), Ids = ids }
	return ids
end

-- Ranked bests of a player's friends (fastest first), including the player.
function RecordService.Friends(courseId: string, player: Player, limit: number?): { Entry }
	local result: { Entry } = {}
	local ids = friendIds(player)
	table.insert(ids, 1, player.UserId)
	for index, userId in ids do
		if index > (limit or 25) then
			break
		end
		local seconds = RecordService.Best(courseId, userId)
		if seconds then
			table.insert(result, { UserId = userId, Name = nameFor(userId), Seconds = seconds, Rank = 0 })
		end
	end
	table.sort(result, function(a, b)
		return a.Seconds < b.Seconds
	end)
	for rank, entry in result do
		entry.Rank = rank
	end
	return result
end

-- Ghosts ---------------------------------------------------------------------------------------------

local function ghostKey(courseId: string, userId: number): string
	return courseId .. "_" .. userId
end

function RecordService.SaveGhost(courseId: string, userId: number, encoded: any)
	local key = ghostKey(courseId, userId)
	memoryGhosts[key] = encoded
	if not online or not ghostStore then
		return
	end
	local ok, err = pcall(function()
		(ghostStore :: DataStore):SetAsync(key, encoded, { userId })
	end)
	if not ok then
		failed(err)
	end
end

function RecordService.LoadGhost(courseId: string, userId: number): any?
	local key = ghostKey(courseId, userId)
	local cached = memoryGhosts[key]
	if cached then
		return cached
	end
	if not online or not ghostStore then
		return nil
	end
	local ok, result = pcall(function()
		return (ghostStore :: DataStore):GetAsync(key)
	end)
	if ok and type(result) == "table" then
		memoryGhosts[key] = result
		return result
	elseif not ok then
		failed(result)
	end
	return nil
end

function RecordService.Online(): boolean
	return online
end

function RecordService.Start()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(GHOST_STORE)
	end)
	if ok then
		ghostStore = result
	else
		online = false
	end
end

return RecordService

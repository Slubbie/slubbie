-- Farming cooperatives (guilds), shared across every server.
--
-- Storage: DataStore "Evergrove_Guilds_v1"
--   g_<id>  { Id, Name, Owner, Created, Open, Members = { [userId] = { Name, Role, Joined, Points } },
--            Points, Bank, Upgrades = { [id] = true }, Weekly = { Week, Progress, Done } }
--   index   { { Id, Name, Members, Points } ... }   (search list, capped)
-- Every write is an UpdateAsync; after a change the server publishes the guild
-- id on MessagingService so other servers refresh their cached copy.
--
-- profile.Guild = { Id, Name, Synced = { [stat] = value } } on each member.
-- Weekly goals (Config/Social.Guilds.Weekly) add up members' stat gains: each
-- server periodically sends its online members' deltas in one batched update.

local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Social = require(Shared.Config.Social)
local Net = require(Shared.Lib.Net)
local ItemUtil = require(Shared.Lib.ItemUtil)
local RNG = require(Shared.Lib.RNG)
local Format = require(Shared.Lib.Format)

local S = require(script.Parent)

local CFG = Social.Guilds
local TOPIC = "EvergroveGuilds"
local CACHE_SECONDS = 60
local SYNC_EVERY = 300
local INDEX_MAX = 400
local WEEK = 7 * 86400

local GuildService = {}

local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore("Evergrove_Guilds_v1")
end)

local memory: { [string]: any } = {} -- fallback when DataStores are unavailable (Studio)
local cache: { [string]: { Data: any, At: number } } = {}

-- Storage ------------------------------------------------------------------------------------------------------

local function update(key: string, fn: (any) -> any): (boolean, any)
	if not store then
		local ok, result = pcall(fn, memory[key])
		if ok and result ~= nil then
			memory[key] = result
		end
		return ok, if ok then (if result ~= nil then result else memory[key]) else nil
	end
	local ok, result = pcall(function()
		return (store :: DataStore):UpdateAsync(key, fn)
	end)
	if not ok then
		warn("[Evergrove] Guild store update failed:", key, result)
	end
	return ok, result
end

local function load(id: string, fresh: boolean?): any?
	local cached = cache[id]
	if cached and not fresh and os.clock() - cached.At < CACHE_SECONDS then
		return cached.Data
	end
	local data
	if store then
		local ok, result = pcall(function()
			return (store :: DataStore):GetAsync("g_" .. id)
		end)
		data = if ok then result else (cached and cached.Data)
	else
		data = memory["g_" .. id]
	end
	cache[id] = { Data = data, At = os.clock() }
	return data
end

local function publish(id: string)
	cache[id] = nil
	task.spawn(pcall, function()
		MessagingService:PublishAsync(TOPIC, id)
	end)
end

local function week(): number
	return os.time() // WEEK
end

local function memberCount(guild: any): number
	local n = 0
	for _ in guild.Members do
		n += 1
	end
	return n
end

local function updateIndex(guild: any?, removeId: string?)
	update("index", function(old)
		local list = if type(old) == "table" then old else {}
		for i = #list, 1, -1 do
			if list[i].Id == removeId or (guild and list[i].Id == guild.Id) then
				table.remove(list, i)
			end
		end
		if guild then
			table.insert(list, 1, {
				Id = guild.Id,
				Name = guild.Name,
				Members = memberCount(guild),
				Points = guild.Points or 0,
				Open = guild.Open,
			})
		end
		while #list > INDEX_MAX do
			table.remove(list)
		end
		return list
	end)
end

-- Refresh a member's profile + nametag from a guild record.
local function applyToMember(player: Player, guild: any?)
	local profile = S.Data.Get(player)
	if not profile then
		return
	end
	if guild and guild.Members[tostring(player.UserId)] then
		profile.Guild.Id = guild.Id
		profile.Guild.Name = guild.Name
		player:SetAttribute("GuildEmblem", if guild.Upgrades and guild.Upgrades.emblem then true else nil)
	else
		profile.Guild = {}
		player:SetAttribute("GuildEmblem", nil)
	end
	S.Data.Changed(player, "Guild")
	S.Player.UpdateNametag(player)
end

-- Actions --------------------------------------------------------------------------------------------------------

local function create(player: Player, name: string)
	local profile = S.Data.Get(player)
	if not profile then
		return false, "Not ready"
	end
	if profile.Guild.Id then
		return false, "Leave your co-op first"
	end
	if not S.Town.IsDone(profile, "guild_hall") then
		return false, "The Cooperative Hall town project must be finished first"
	end
	local clean = Format.CleanName(name, CFG.NameMax)
	if #clean < CFG.NameMin then
		return false, "Name is too short"
	end
	local filtered = S.Multiplayer.FilterText(player, clean)
	if not filtered or string.find(filtered, "#", 1, true) then
		return false, "That name isn't allowed"
	end
	-- Unique names (case-insensitive) via the index.
	local index = if store then nil else memory.index
	if store then
		local ok, result = pcall(function()
			return (store :: DataStore):GetAsync("index")
		end)
		index = if ok then result else nil
	end
	for _, entry in (if type(index) == "table" then index else {}) do
		if string.lower(entry.Name) == string.lower(filtered) then
			return false, "That name is taken"
		end
	end
	if profile.Coins < CFG.CreateCost then
		return false, "Founding a co-op costs " .. Format.Coins(CFG.CreateCost)
	end
	local id = RNG.Uid("g")
	local uid = tostring(player.UserId)
	local guild = {
		Id = id,
		Name = filtered,
		Owner = player.UserId,
		Created = os.time(),
		Open = true,
		Members = { [uid] = { Name = player.DisplayName, Role = "Leader", Joined = os.time(), Points = 0 } },
		Points = 0,
		Bank = 0,
		Upgrades = {},
		Weekly = { Week = week(), Progress = {}, Done = {} },
	}
	local ok = update("g_" .. id, function(old)
		if old ~= nil then
			return nil
		end
		return guild
	end)
	if not ok then
		return false, "Couldn't create the co-op right now. Try again soon."
	end
	S.Economy.Spend(player, CFG.CreateCost, "Co-op founded")
	updateIndex(guild)
	cache[id] = { Data = guild, At = os.clock() }
	profile.Guild.Synced = table.clone(profile.Stats)
	applyToMember(player, guild)
	S.Notify.Banner(player, "Co-op founded!", filtered .. " is ready for members.", "Guild", "🤝")
	return true, guild
end

local function join(player: Player, id: string)
	local profile = S.Data.Get(player)
	if not profile then
		return false, "Not ready"
	end
	if profile.Guild.Id then
		return false, "Leave your co-op first"
	end
	local reason = nil
	local ok, result = update("g_" .. id, function(guild)
		if type(guild) ~= "table" then
			reason = "That co-op no longer exists"
			return nil
		end
		if not guild.Open then
			reason = "That co-op is invite-only"
			return nil
		end
		if memberCount(guild) >= CFG.MaxMembers then
			reason = "That co-op is full"
			return nil
		end
		guild.Members[tostring(player.UserId)] =
			{ Name = player.DisplayName, Role = "Member", Joined = os.time(), Points = 0 }
		return guild
	end)
	if not ok or reason or type(result) ~= "table" then
		return false, reason or "Couldn't join right now"
	end
	updateIndex(result)
	publish(id)
	profile.Guild.Synced = table.clone(profile.Stats)
	applyToMember(player, result)
	S.Notify.Toast(player, "🤝 You joined " .. result.Name .. "!", "Success")
	return true, result
end

local function leave(player: Player)
	local profile = S.Data.Get(player)
	local id = profile and profile.Guild.Id
	if not id then
		return false, "You're not in a co-op"
	end
	local uid = tostring(player.UserId)
	local deleted = false
	local ok, result = update("g_" .. id, function(guild)
		if type(guild) ~= "table" then
			return nil
		end
		guild.Members[uid] = nil
		if memberCount(guild) == 0 then
			deleted = true
			guild.Deleted = true
			return guild
		end
		if guild.Owner == player.UserId then
			-- Hand leadership to the longest-serving member.
			local nextLeader, since = nil, math.huge
			for memberId, member in guild.Members do
				if member.Joined < since then
					nextLeader, since = memberId, member.Joined
				end
			end
			guild.Owner = tonumber(nextLeader)
			guild.Members[nextLeader].Role = "Leader"
		end
		return guild
	end)
	if not ok then
		return false, "Couldn't leave right now"
	end
	if deleted then
		updateIndex(nil, id)
	elseif type(result) == "table" then
		updateIndex(result)
	end
	publish(id)
	applyToMember(player, nil)
	return true
end

local function info(player: Player)
	local profile = S.Data.Get(player)
	local id = profile and profile.Guild.Id
	if not id then
		return true, nil
	end
	local guild = load(id)
	if type(guild) ~= "table" or guild.Deleted or not guild.Members[tostring(player.UserId)] then
		applyToMember(player, nil)
		return true, nil
	end
	return true, { Guild = guild, Weekly = CFG.Weekly, Upgrades = CFG.Upgrades, Week = week() }
end

local function search(_player: Player, query: string?)
	local index
	if store then
		local ok, result = pcall(function()
			return (store :: DataStore):GetAsync("index")
		end)
		index = if ok then result else nil
	else
		index = memory.index
	end
	local out = {}
	local q = string.lower(query or "")
	for _, entry in (if type(index) == "table" then index else {}) do
		if (q == "" or string.find(string.lower(entry.Name), q, 1, true)) and #out < 30 then
			table.insert(out, entry)
		end
	end
	return true, out
end

-- Contribute coins/items to the bank, or (leaders/officers) buy an upgrade: source = "upgrade:<id>".
local function contribute(player: Player, source: string, count: number)
	local profile = S.Data.Get(player)
	local id = profile and profile.Guild.Id
	if not id then
		return false, "You're not in a co-op"
	end
	local uid = tostring(player.UserId)
	local upgradeId = string.match(source, "^upgrade:(.+)$")
	if upgradeId then
		local upgrade
		for _, u in CFG.Upgrades do
			if u.Id == upgradeId then
				upgrade = u
			end
		end
		if not upgrade then
			return false, "Unknown upgrade"
		end
		local reason = nil
		local ok, result = update("g_" .. id, function(guild)
			local member = type(guild) == "table" and guild.Members[uid]
			if not member or (member.Role ~= "Leader" and member.Role ~= "Officer") then
				reason = "Only leaders and officers can spend the bank"
				return nil
			end
			if guild.Upgrades[upgradeId] then
				reason = "Already bought"
				return nil
			end
			if (guild.Bank or 0) < upgrade.Cost then
				reason = "The bank needs " .. Format.Coins(upgrade.Cost)
				return nil
			end
			guild.Bank -= upgrade.Cost
			guild.Upgrades[upgradeId] = true
			return guild
		end)
		if not ok or reason then
			return false, reason or "Try again soon"
		end
		publish(id)
		applyToMember(player, result)
		return true, result
	end
	-- Coins or items → bank and points.
	local value = 0
	if source == "coins" then
		count = math.clamp(count, 1, profile.Coins)
		if not S.Economy.Spend(player, count, "Co-op bank") then
			return false, "Not enough coins"
		end
		value = count
	else
		local stack = S.Inventory.Slot(player, source)
		if not stack or not ItemUtil.Sellable(stack) then
			return false, "The co-op can't use that"
		end
		local taken = S.Inventory.TakeFromSlot(player, source, math.clamp(count, 1, stack.N))
		if not taken then
			return false, "Can't give that"
		end
		value = ItemUtil.UnitValue(taken) * taken.N
	end
	local points = math.max(1, math.floor(value / 1000 * CFG.ContributionPoints))
	local bankAdd = if source == "coins" then value else math.floor(value * 0.5)
	local ok, result = update("g_" .. id, function(guild)
		if type(guild) ~= "table" or not guild.Members[uid] then
			return nil
		end
		guild.Bank = (guild.Bank or 0) + bankAdd
		guild.Points = (guild.Points or 0) + points
		guild.Members[uid].Points = (guild.Members[uid].Points or 0) + points
		return guild
	end)
	if not ok or type(result) ~= "table" then
		-- Refund on failure.
		if source == "coins" then
			S.Economy.AddCoins(player, value, "Co-op refund")
		end
		return false, "Couldn't reach the co-op right now"
	end
	publish(id)
	S.Data.AddStat(player, "GuildContributed", value)
	return true, { Bank = result.Bank, Points = result.Points }
end

-- Weekly goals ---------------------------------------------------------------------------------------------------

local function syncWeekly()
	local byGuild: { [string]: { [string]: number } } = {}
	local members: { [string]: { Player } } = {}
	for _, player in Players:GetPlayers() do
		local profile = S.Data.Get(player)
		local id = profile and profile.Guild.Id
		if id then
			profile.Guild.Synced = profile.Guild.Synced or table.clone(profile.Stats)
			local deltas = byGuild[id] or {}
			for _, goal in CFG.Weekly do
				local now = profile.Stats[goal.Stat] or 0
				local before = profile.Guild.Synced[goal.Stat] or now
				if now > before then
					deltas[goal.Id] = (deltas[goal.Id] or 0) + (now - before)
				end
				profile.Guild.Synced[goal.Stat] = now
			end
			byGuild[id] = deltas
			members[id] = members[id] or {}
			table.insert(members[id], player)
		end
	end
	for id, deltas in byGuild do
		if next(deltas) then
			local completed = {}
			local ok, result = update("g_" .. id, function(guild)
				if type(guild) ~= "table" then
					return nil
				end
				if not guild.Weekly or guild.Weekly.Week ~= week() then
					guild.Weekly = { Week = week(), Progress = {}, Done = {} }
				end
				for _, goal in CFG.Weekly do
					local add = deltas[goal.Id]
					if add and not guild.Weekly.Done[goal.Id] then
						guild.Weekly.Progress[goal.Id] = (guild.Weekly.Progress[goal.Id] or 0) + add
						if guild.Weekly.Progress[goal.Id] >= goal.Goal then
							guild.Weekly.Done[goal.Id] = true
							guild.Bank = (guild.Bank or 0) + (goal.Reward.Coins or 0)
							guild.Points = (guild.Points or 0) + (goal.Reward.GuildPoints or 0)
							table.insert(completed, goal)
						end
					end
				end
				return guild
			end)
			if ok and type(result) == "table" then
				publish(id)
				for _, goal in completed do
					for _, player in members[id] do
						S.Notify.Banner(player, "Co-op goal complete!", goal.Text, "Guild", "🤝")
						S.Economy.AddTokens(player, 5)
					end
				end
			end
		end
	end
end

-- Lifecycle ---------------------------------------------------------------------------------------------------------

function GuildService.Init()
	Net.Handle("GuildCreate", create)
	Net.Handle("GuildJoin", join)
	Net.Handle("GuildLeave", leave)
	Net.Handle("GuildInfo", info)
	Net.Handle("GuildSearch", search)
	Net.Handle("GuildContribute", contribute)
end

function GuildService.Start()
	pcall(function()
		MessagingService:SubscribeAsync(TOPIC, function(message)
			local id = message.Data
			if type(id) ~= "string" then
				return
			end
			cache[id] = nil
			for _, player in Players:GetPlayers() do
				local profile = S.Data.Get(player)
				if profile and profile.Guild.Id == id then
					task.spawn(function()
						local guild = load(id, true)
						applyToMember(player, if type(guild) == "table" and not guild.Deleted then guild else nil)
					end)
				end
			end
		end)
	end)
	S.Data.Loaded:Connect(function(player, profile)
		if profile.Guild.Id then
			task.spawn(function()
				local guild = load(profile.Guild.Id, true)
				applyToMember(player, if type(guild) == "table" and not guild.Deleted then guild else nil)
			end)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(SYNC_EVERY)
			local ok, err = pcall(syncWeekly)
			if not ok then
				warn("[Evergrove] Guild weekly sync failed:", err)
			end
		end
	end)
end

return GuildService

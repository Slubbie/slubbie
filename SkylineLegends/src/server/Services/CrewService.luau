-- Runner crews: small persistent groups with a name, a tag shown on
-- nametags, and a weekly crew goal everyone contributes to by finishing
-- courses, races, relays and Spire floors. Reaching each goal tier pays every
-- member (claimed automatically the next time they're online).
--
-- Crews live in their own DataStore so they work across servers; invites go
-- to players in the same server.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Net = require(ReplicatedStorage.Shared.Net)
local Rotation = require(ReplicatedStorage.Shared.Logic.Rotation)

local DataService = require(script.Parent.Parent.Data.DataService)
local Events = require(script.Parent.Parent.Events)
local Notify = require(script.Parent.Notify)
local ProgressionService = require(script.Parent.ProgressionService)

local CrewService = {}

local STORE = "SkylineLegends_Crews_v1"
local MAX_MEMBERS = 20
local GOAL_TIERS = { 60, 180, 400 }
local GOAL_REWARDS = {
	{ XP = 400, Credits = 250 },
	{ XP = 800, Credits = 500 },
	{ XP = 1500, Credits = 900, Prestige = 1 },
}

type Crew = {
	Id: string,
	Name: string,
	Tag: string,
	Owner: number,
	Members: { [string]: { Name: string, Joined: number } },
	Created: number,
	Week: number,
	Points: number,
	Total: number,
}

local store: DataStore? = nil
local cache: { [string]: Crew } = {}
local pendingPoints: { [string]: number } = {}
local invites: { [Player]: { [string]: number } } = {} -- crewId → expiry

local function load(crewId: string): Crew?
	local cached = cache[crewId]
	if cached then
		return cached
	end
	if not store then
		return nil
	end
	local ok, result = pcall(function()
		return (store :: DataStore):GetAsync(crewId)
	end)
	if ok and type(result) == "table" then
		cache[crewId] = result
		return result
	end
	return nil
end

-- Atomically change a crew (and keep the cache in step).
local function update(crewId: string, fn: (Crew) -> boolean): Crew?
	local crew = cache[crewId]
	if store then
		local result: Crew? = nil
		local ok = pcall(function()
			(store :: DataStore):UpdateAsync(crewId, function(old)
				if type(old) ~= "table" then
					return nil
				end
				if not fn(old) then
					return nil
				end
				result = old
				return old
			end)
		end)
		if ok and result then
			cache[crewId] = result
			return result
		end
		if ok then
			return cache[crewId]
		end
	end
	-- Memory only (Studio without API access).
	if crew and fn(crew) then
		return crew
	end
	return crew
end

local function filter(text: string, player: Player): string?
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, player.UserId)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if ok and type(result) == "string" then
		return result
	end
	return nil
end

local function memberCount(crew: Crew): number
	local n = 0
	for _ in crew.Members do
		n += 1
	end
	return n
end

local function rollWeek(crew: Crew)
	local week = Rotation.Week()
	if crew.Week ~= week then
		crew.Week = week
		crew.Points = 0
	end
end

local function setTag(player: Player, crew: Crew?)
	player:SetAttribute("CrewTag", if crew then crew.Tag else nil)
	player:SetAttribute("CrewName", if crew then crew.Name else nil)
end

local function view(player: Player, crew: Crew): { [string]: any }
	local members = {}
	for userId, entry in crew.Members do
		local id = tonumber(userId) or 0
		table.insert(members, {
			UserId = id,
			Name = entry.Name,
			Owner = id == crew.Owner,
			Online = Players:GetPlayerByUserId(id) ~= nil,
		})
	end
	table.sort(members, function(a, b)
		if a.Owner ~= b.Owner then
			return a.Owner
		end
		return a.Name < b.Name
	end)
	return {
		Id = crew.Id,
		Name = crew.Name,
		Tag = crew.Tag,
		Members = members,
		Week = crew.Week,
		Points = crew.Points,
		Total = crew.Total,
		Tiers = GOAL_TIERS,
		Rewards = GOAL_REWARDS,
		IsOwner = player.UserId == crew.Owner,
		ResetIn = Rotation.SecondsUntilNextWeek(),
	}
end

-- Pay any goal tiers reached this week that this member hasn't claimed yet.
local function claim(player: Player, crew: Crew)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	rollWeek(crew)
	local claims = profile.Flags.CrewClaims
	if type(claims) ~= "table" or claims.Week ~= crew.Week or claims.Crew ~= crew.Id then
		claims = { Week = crew.Week, Crew = crew.Id, Tier = 0 }
		profile.Flags.CrewClaims = claims
	end
	for tier = claims.Tier + 1, #GOAL_TIERS do
		if crew.Points >= GOAL_TIERS[tier] then
			claims.Tier = tier
			ProgressionService.Grant(player, GOAL_REWARDS[tier], nil, true)
			profile.Stats.CrewGoals = (profile.Stats.CrewGoals or 0) + 1
			Notify.Send(player, {
				Kind = "Reward",
				Title = ("Crew goal %d reached"):format(tier),
				Text = crew.Name,
				XP = GOAL_REWARDS[tier].XP,
				Credits = GOAL_REWARDS[tier].Credits,
				Prestige = GOAL_REWARDS[tier].Prestige,
			})
			Events.StatChanged:Fire(player, "CrewGoals")
		end
	end
	DataService.MarkDirty(player)
end

local function addPoints(player: Player, amount: number)
	local profile = DataService.Get(player)
	local crewId = profile and profile.Crew
	if type(crewId) ~= "string" then
		return
	end
	pendingPoints[crewId] = (pendingPoints[crewId] or 0) + amount
	local crew = cache[crewId]
	if crew then
		rollWeek(crew)
		crew.Points += amount
		crew.Total = (crew.Total or 0) + amount
		-- Online members claim tiers as soon as they're reached.
		for userId in crew.Members do
			local member = Players:GetPlayerByUserId(tonumber(userId) or 0)
			if member then
				claim(member, crew)
			end
		end
	end
end

-- Remote handlers -------------------------------------------------------------------------------

local function onCreate(player: Player, name: any, tag: any): (boolean, any)
	local profile = DataService.Get(player)
	if not profile then
		return false, "Not ready"
	end
	if profile.Crew then
		return false, "Leave your crew first"
	end
	if type(name) ~= "string" or type(tag) ~= "string" then
		return false, "Give your crew a name and a tag"
	end
	name = string.sub((string.gsub(name, "^%s+", "")), 1, 24)
	tag = string.upper(string.sub((string.gsub(tag, "[^%w]", "")), 1, 4))
	if #name < 3 or #tag < 2 then
		return false, "Names need 3+ characters, tags 2-4 letters"
	end
	local cleanName = filter(name, player)
	local cleanTag = filter(tag, player)
	if not cleanName or not cleanTag or string.find(cleanName, "#") or string.find(cleanTag, "#") then
		return false, "Try a different name"
	end
	local crew: Crew = {
		Id = "crew_" .. HttpService:GenerateGUID(false):sub(1, 13),
		Name = cleanName,
		Tag = cleanTag,
		Owner = player.UserId,
		Members = { [tostring(player.UserId)] = { Name = player.DisplayName, Joined = os.time() } },
		Created = os.time(),
		Week = Rotation.Week(),
		Points = 0,
		Total = 0,
	}
	if store then
		local ok = pcall(function()
			(store :: DataStore):SetAsync(crew.Id, crew)
		end)
		if not ok then
			store = nil
		end
	end
	cache[crew.Id] = crew
	profile.Crew = crew.Id
	profile.Stats.CrewJoined = 1
	DataService.Push(player, "Crew")
	DataService.MarkDirty(player)
	setTag(player, crew)
	Events.CrewJoined:Fire(player, crew.Id)
	Events.StatChanged:Fire(player, "CrewJoined")
	return true, view(player, crew)
end

local function onInvite(player: Player, userId: any)
	local profile = DataService.Get(player)
	local crew = profile and type(profile.Crew) == "string" and load(profile.Crew)
	local target = type(userId) == "number" and Players:GetPlayerByUserId(userId)
	if not crew or not target or target == player then
		return
	end
	if memberCount(crew) >= MAX_MEMBERS then
		Notify.Warn(player, "Your crew is full.")
		return
	end
	invites[target] = invites[target] or {}
	invites[target][crew.Id] = os.clock() + 300
	Net.Push(target, "Crew.Invite", { CrewId = crew.Id, Name = crew.Name, Tag = crew.Tag, From = player.DisplayName })
	Notify.Toast(player, "Invite sent", target.DisplayName)
end

local function onRespond(player: Player, crewId: any, accept: any): (boolean, any)
	local pending = invites[player]
	if type(crewId) ~= "string" or not pending or not pending[crewId] or os.clock() > pending[crewId] then
		return false, "That invite has expired"
	end
	pending[crewId] = nil
	if not accept then
		return true, nil
	end
	local profile = DataService.Get(player)
	if not profile then
		return false, "Not ready"
	end
	if profile.Crew then
		return false, "Leave your crew first"
	end
	local full = false
	local crew = update(crewId, function(c)
		if memberCount(c) >= MAX_MEMBERS then
			full = true
			return false
		end
		c.Members[tostring(player.UserId)] = { Name = player.DisplayName, Joined = os.time() }
		return true
	end)
	if not crew or full then
		return false, "That crew is full"
	end
	profile.Crew = crewId
	profile.Stats.CrewJoined = 1
	DataService.Push(player, "Crew")
	DataService.MarkDirty(player)
	setTag(player, crew)
	Events.CrewJoined:Fire(player, crewId)
	Events.StatChanged:Fire(player, "CrewJoined")
	claim(player, crew)
	return true, view(player, crew)
end

local function onLeave(player: Player)
	local profile = DataService.Get(player)
	local crewId = profile and profile.Crew
	if not profile or type(crewId) ~= "string" then
		return
	end
	update(crewId, function(c)
		c.Members[tostring(player.UserId)] = nil
		if c.Owner == player.UserId then
			-- Hand the crew to the longest-standing member.
			local best, joined = nil, math.huge
			for userId, entry in c.Members do
				if entry.Joined < joined then
					best, joined = tonumber(userId), entry.Joined
				end
			end
			c.Owner = best or 0
		end
		return true
	end)
	profile.Crew = nil
	DataService.Push(player, "Crew")
	DataService.MarkDirty(player)
	setTag(player, nil)
end

local function onKick(player: Player, userId: any)
	local profile = DataService.Get(player)
	local crewId = profile and profile.Crew
	if type(crewId) ~= "string" or type(userId) ~= "number" or userId == player.UserId then
		return
	end
	local crew = load(crewId)
	if not crew or crew.Owner ~= player.UserId then
		return
	end
	update(crewId, function(c)
		c.Members[tostring(userId)] = nil
		return true
	end)
	local target = Players:GetPlayerByUserId(userId)
	if target then
		local targetProfile = DataService.Get(target)
		if targetProfile and targetProfile.Crew == crewId then
			targetProfile.Crew = nil
			DataService.Push(target, "Crew")
			setTag(target, nil)
			Notify.Warn(target, "You were removed from " .. crew.Name)
		end
	end
end

local function onGet(player: Player): any
	local profile = DataService.Get(player)
	local crewId = profile and profile.Crew
	if type(crewId) ~= "string" then
		return nil
	end
	local crew = load(crewId)
	if not crew or not crew.Members[tostring(player.UserId)] then
		-- Removed while away.
		if profile then
			profile.Crew = nil
			DataService.Push(player, "Crew")
		end
		setTag(player, nil)
		return nil
	end
	claim(player, crew)
	return view(player, crew)
end

function CrewService.Start()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE)
	end)
	store = if ok then result else nil

	Net.Handle("Crew.Create", onCreate)
	Net.On("Crew.Invite", onInvite)
	Net.Handle("Crew.Respond", onRespond)
	Net.On("Crew.Leave", onLeave)
	Net.On("Crew.Kick", onKick)
	Net.Handle("Crew.Get", onGet)

	DataService.Loaded:Connect(function(player, profile)
		if type(profile.Crew) == "string" then
			task.spawn(function()
				local crew = load(profile.Crew)
				if crew and crew.Members[tostring(player.UserId)] then
					setTag(player, crew)
					claim(player, crew)
				end
			end)
		end
	end)
	-- Contributions.
	Events.CourseFinished:Connect(function(player: Player, result: any)
		if result.Mode ~= "Practice" then
			addPoints(player, 1 + math.max((result.Medal or 0) - (result.PreviousMedal or 0), 0))
		end
	end)
	Events.RaceFinished:Connect(function(player: Player)
		addPoints(player, 3)
	end)
	Events.RelayFinished:Connect(function(player: Player)
		addPoints(player, 4)
	end)
	Events.TowerFloor:Connect(function(player: Player)
		addPoints(player, 1)
	end)
	Players.PlayerRemoving:Connect(function(player)
		invites[player] = nil
	end)
	-- Flush crew points to the store every minute.
	task.spawn(function()
		while true do
			task.wait(60)
			for crewId, amount in pendingPoints do
				pendingPoints[crewId] = nil
				task.spawn(function()
					if store then
						pcall(function()
							(store :: DataStore):UpdateAsync(crewId, function(old)
								if type(old) ~= "table" then
									return nil
								end
								rollWeek(old)
								old.Points += amount
								old.Total = (old.Total or 0) + amount
								cache[crewId] = old
								return old
							end)
						end)
					end
				end)
			end
		end
	end)
end

return CrewService

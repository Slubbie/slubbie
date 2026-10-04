-- Networking for every system in Skyline Legends, through four remotes.
--
-- Messages are addressed by route ("Course.Checkpoint", "Shop.Buy", ...). Every
-- client→server route must be declared in ROUTES with a rate limit, so new
-- features plug in by adding a line here and a handler on the server.
--
--   Server:  Net.On(route, fn(player, ...))          fire-and-forget from a client
--            Net.Handle(route, fn(player, ...) → ...) request/response
--            Net.Push(player, route, ...)             server → one client
--            Net.PushAll(route, ...) / Net.PushOthers(player, route, ...)
--   Client:  Net.Send(route, ...) / Net.Invoke(route, ...) / Net.Listen(route, fn)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Allowed client→server routes: { per-second rate, burst }.
local ROUTES: { [string]: { number } } = {
	-- Movement relay and validation
	["Move.State"] = { 20, 40 },
	["Move.Action"] = { 25, 50 },
	["Move.Fall"] = { 4, 8 },
	["Move.Flow"] = { 2, 4 },
	-- Courses
	["Course.Start"] = { 2, 4 },
	["Course.Checkpoint"] = { 6, 12 },
	["Course.Token"] = { 10, 20 },
	["Course.Shortcut"] = { 4, 8 },
	["Course.Abort"] = { 2, 4 },
	["Course.Restart"] = { 2, 4 },
	["Course.Ghost"] = { 1, 2 },
	["Course.Preview"] = { 4, 8 },
	["Course.Leaderboard"] = { 2, 6 },
	["Course.GetGhost"] = { 1, 4 },
	-- Progress
	["Profile.Get"] = { 1, 4 },
	["Settings.Save"] = { 1, 4 },
	["Skill.Unlock"] = { 4, 8 },
	["Skill.Respec"] = { 1, 2 },
	["Shop.Buy"] = { 3, 6 },
	["Shop.Equip"] = { 6, 12 },
	["Achievement.Claim"] = { 4, 8 },
	["Mastery.Claim"] = { 4, 8 },
	-- World
	["Travel.Go"] = { 1, 3 },
	["Travel.Spawn"] = { 1, 3 },
	["Discover.Touch"] = { 6, 12 },
	["Lesson.Complete"] = { 4, 8 },
	["Lesson.Reset"] = { 1, 3 },
	-- Quests and NPCs
	["Quest.Talk"] = { 3, 6 },
	["Quest.Accept"] = { 3, 6 },
	["Quest.Abandon"] = { 2, 4 },
	["Quest.Pin"] = { 4, 8 },
	["Quest.Point"] = { 6, 12 },
	["Quest.Claim"] = { 4, 8 },
	["Contract.Take"] = { 2, 4 },
	-- Modes
	["Race.List"] = { 2, 4 },
	["Race.Create"] = { 1, 3 },
	["Race.Join"] = { 2, 4 },
	["Race.Leave"] = { 2, 4 },
	["Race.Ready"] = { 2, 4 },
	["Relay.Create"] = { 1, 3 },
	["Relay.Join"] = { 2, 4 },
	["Relay.Leave"] = { 2, 4 },
	["Relay.Ready"] = { 2, 4 },
	["Tower.Enter"] = { 1, 3 },
	["Tower.Floor"] = { 4, 8 },
	["Tower.Leave"] = { 1, 3 },
	["Endless.Start"] = { 1, 2 },
	["Endless.Gate"] = { 6, 12 },
	["Endless.End"] = { 1, 3 },
	["Switch.Press"] = { 6, 12 },
	-- Social
	["Crew.Create"] = { 1, 2 },
	["Crew.Invite"] = { 2, 4 },
	["Crew.Respond"] = { 2, 4 },
	["Crew.Leave"] = { 1, 2 },
	["Crew.Kick"] = { 2, 4 },
	["Crew.Get"] = { 2, 4 },
	["Social.Invite"] = { 2, 4 },
	["Social.Respond"] = { 2, 4 },
	["Social.Players"] = { 2, 4 },
	["Emote.Play"] = { 3, 6 },
}

type Bucket = { Tokens: number, Updated: number }

local Net = {}

local isServer = RunService:IsServer()
local folder: Folder
local c2s: RemoteEvent
local s2c: RemoteEvent
local rpc: RemoteFunction

if isServer then
	folder = Instance.new("Folder")
	folder.Name = "SkylineNet"
	c2s = Instance.new("RemoteEvent")
	c2s.Name = "C2S"
	c2s.Parent = folder
	s2c = Instance.new("RemoteEvent")
	s2c.Name = "S2C"
	s2c.Parent = folder
	rpc = Instance.new("RemoteFunction")
	rpc.Name = "RPC"
	rpc.Parent = folder
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild("SkylineNet") :: Folder
	c2s = folder:WaitForChild("C2S") :: RemoteEvent
	s2c = folder:WaitForChild("S2C") :: RemoteEvent
	rpc = folder:WaitForChild("RPC") :: RemoteFunction
end

-- Server ------------------------------------------------------------------------

local eventHandlers: { [string]: (Player, ...any) -> () } = {}
local requestHandlers: { [string]: (Player, ...any) -> ...any } = {}
local buckets: { [Player]: { [string]: Bucket } } = {}

local function allow(player: Player, route: string): boolean
	local limit = ROUTES[route]
	if not limit then
		return false
	end
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local now = os.clock()
	local bucket = perPlayer[route]
	if not bucket then
		bucket = { Tokens = limit[2], Updated = now }
		perPlayer[route] = bucket
	end
	bucket.Tokens = math.min(limit[2], bucket.Tokens + (now - bucket.Updated) * limit[1])
	bucket.Updated = now
	if bucket.Tokens < 1 then
		return false
	end
	bucket.Tokens -= 1
	return true
end

if isServer then
	c2s.OnServerEvent:Connect(function(player: Player, route: any, ...)
		if type(route) ~= "string" or not allow(player, route) then
			return
		end
		local handler = eventHandlers[route]
		if handler then
			local ok, err = pcall(handler, player, ...)
			if not ok then
				warn(("[Net] %s from %s failed: %s"):format(route, player.Name, tostring(err)))
			end
		end
	end)
	rpc.OnServerInvoke = function(player: Player, route: any, ...)
		if type(route) ~= "string" or not allow(player, route) then
			return nil
		end
		local handler = requestHandlers[route]
		if not handler then
			return nil
		end
		local results = table.pack(pcall(handler, player, ...))
		if not results[1] then
			warn(("[Net] %s from %s failed: %s"):format(route, player.Name, tostring(results[2])))
			return nil
		end
		return table.unpack(results, 2, results.n)
	end
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
end

function Net.On(route: string, handler: (Player, ...any) -> ())
	assert(isServer, "Net.On is server-only")
	assert(ROUTES[route], "Undeclared route " .. route)
	eventHandlers[route] = handler
end

function Net.Handle(route: string, handler: (Player, ...any) -> ...any)
	assert(isServer, "Net.Handle is server-only")
	assert(ROUTES[route], "Undeclared route " .. route)
	requestHandlers[route] = handler
end

function Net.Push(player: Player, route: string, ...)
	s2c:FireClient(player, route, ...)
end

function Net.PushAll(route: string, ...)
	s2c:FireAllClients(route, ...)
end

function Net.PushOthers(except: Player, route: string, ...)
	for _, player in Players:GetPlayers() do
		if player ~= except then
			s2c:FireClient(player, route, ...)
		end
	end
end

-- Client ------------------------------------------------------------------------

local listeners: { [string]: { (...any) -> () } } = {}
local pending: { [string]: { { any } } } = {}

if not isServer then
	s2c.OnClientEvent:Connect(function(route: string, ...)
		local list = listeners[route]
		if list then
			for _, fn in list do
				task.spawn(fn, ...)
			end
		else
			-- Nobody is listening yet (scripts still starting): keep it for them.
			local queue = pending[route]
			if not queue then
				queue = {}
				pending[route] = queue
			end
			if #queue < 64 then
				table.insert(queue, table.pack(...))
			end
		end
	end)
end

function Net.Send(route: string, ...)
	c2s:FireServer(route, ...)
end

function Net.Invoke(route: string, ...): ...any
	return rpc:InvokeServer(route, ...)
end

function Net.Listen(route: string, fn: (...any) -> ())
	local list = listeners[route]
	if not list then
		list = {}
		listeners[route] = list
	end
	table.insert(list, fn)
	local queue = pending[route]
	if queue then
		pending[route] = nil
		for _, args in queue do
			task.spawn(fn, table.unpack(args, 1, args.n))
		end
	end
end

return Net

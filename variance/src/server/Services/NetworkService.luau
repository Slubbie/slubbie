-- The single gateway for client traffic.
--
-- * Rate limits every remote with per-player token buckets.
-- * Validates every Request against the argument schema in shared/Net.luau
--   (types, string lengths, finite numbers, table shape) before any handler runs.
-- * Routes Requests by endpoint name to handlers registered by services, and
--   wraps them in pcall so a handler error returns a clean failure.
-- * Reports every rejection to AntiExploitService.
-- * Sends server -> client traffic (Match, Push, Look).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Variance.Config)
local Net = require(ReplicatedStorage.Variance.Net)

local NetworkService = {}

local handlers: { [string]: (Player, ...any) -> (boolean, any) } = {}
local actHandler: ((Player, any) -> ())? = nil
local lookHandler: ((Player, any) -> ())? = nil
local buckets: { [Player]: { [string]: { Tokens: number, Last: number } } } = {}

local MAX_STRING = 200
local MAX_TABLE_ENTRIES = 256
local MAX_TABLE_DEPTH = 4

function NetworkService:Init(services)
	self.Services = services
end

-- Token bucket. Returns true if the request may proceed.
function NetworkService:take(player: Player, key: string, rate: number, burst: number): boolean
	local now = os.clock()
	local perPlayer = buckets[player]
	if perPlayer == nil then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local bucket = perPlayer[key]
	if bucket == nil then
		bucket = { Tokens = burst, Last = now }
		perPlayer[key] = bucket
	end
	bucket.Tokens = math.min(burst, bucket.Tokens + (now - bucket.Last) * rate)
	bucket.Last = now
	if bucket.Tokens < 1 then
		return false
	end
	bucket.Tokens -= 1
	return true
end

-- Deep-validates a client table: only plain data, bounded size and depth.
local function cleanTable(value: any, depth: number, budget: { n: number }): boolean
	if depth > MAX_TABLE_DEPTH then
		return false
	end
	for k, v in value do
		budget.n += 1
		if budget.n > MAX_TABLE_ENTRIES then
			return false
		end
		local kt, vt = type(k), type(v)
		if kt ~= "string" and kt ~= "number" then
			return false
		end
		if kt == "string" and #k > MAX_STRING then
			return false
		end
		if kt == "number" and (k ~= k or k == math.huge or k == -math.huge) then
			return false
		end
		if vt == "string" then
			if #v > MAX_STRING then
				return false
			end
		elseif vt == "number" then
			if v ~= v or v == math.huge or v == -math.huge then
				return false
			end
		elseif vt == "table" then
			if not cleanTable(v, depth + 1, budget) then
				return false
			end
		elseif vt ~= "boolean" then
			return false
		end
	end
	return true
end

local function checkArg(expected: string, value: any): boolean
	local optional = string.sub(expected, -1) == "?"
	local kind = optional and string.sub(expected, 1, -2) or expected
	if value == nil then
		return optional
	end
	if kind == "any" then
		return true
	elseif kind == "string" then
		return type(value) == "string" and #value <= MAX_STRING and utf8.len(value) ~= nil
	elseif kind == "number" then
		return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
	elseif kind == "boolean" then
		return type(value) == "boolean"
	elseif kind == "table" then
		return type(value) == "table" and cleanTable(value, 1, { n = 0 })
	end
	return false
end
NetworkService.checkArg = checkArg

function NetworkService:handle(endpoint: string, handler: (Player, ...any) -> (boolean, any))
	assert(Net.Endpoints[endpoint], "unknown endpoint " .. endpoint)
	handlers[endpoint] = handler
end

function NetworkService:onAct(handler: (Player, any) -> ())
	actHandler = handler
end

function NetworkService:onLook(handler: (Player, any) -> ())
	lookHandler = handler
end

local function flag(player: Player, reason: string, severity: string, detail: any?)
	local anti = NetworkService.Services and NetworkService.Services.AntiExploitService
	if anti then
		anti:flag(player, reason, severity, detail)
	end
end
NetworkService.flag = function(_self, player, reason, severity, detail)
	flag(player, reason, severity, detail)
end

function NetworkService:_request(player: Player, endpoint: any, ...: any): (boolean, any)
	if type(endpoint) ~= "string" or Net.Endpoints[endpoint] == nil then
		flag(player, "unknown endpoint", "Moderate", endpoint)
		return false, "Unknown request."
	end
	local limits = Config.Net.Buckets.Request
	if not self:take(player, "Request", limits.Rate, limits.Burst) then
		flag(player, "request rate", "Minor", endpoint)
		return false, "Slow down."
	end
	local specific = Config.Net.EndpointBuckets[endpoint]
	if specific and not self:take(player, endpoint, specific.Rate, specific.Burst) then
		flag(player, "endpoint rate", "Minor", endpoint)
		return false, "Slow down."
	end
	local schema = Net.Endpoints[endpoint]
	local args = table.pack(...)
	if args.n > #schema then
		flag(player, "extra arguments", "Moderate", endpoint)
		return false, "Invalid request."
	end
	for i, expected in schema do
		if not checkArg(expected, args[i]) then
			flag(player, "bad argument " .. i, "Moderate", endpoint)
			return false, "Invalid request."
		end
	end
	local handler = handlers[endpoint]
	if handler == nil then
		return false, "Not available."
	end
	local ok, success, result = pcall(handler, player, table.unpack(args, 1, args.n))
	if not ok then
		warn("[VARIANCE/Network] " .. endpoint .. " failed: " .. tostring(success))
		return false, "Something went wrong. Try again."
	end
	return success == true, result
end

function NetworkService:match(player: Player, kind: string, payload: any)
	if player.Parent then
		Net.Match:FireClient(player, kind, payload)
	end
end

function NetworkService:push(player: Player, kind: string, payload: any)
	if player.Parent then
		Net.Push:FireClient(player, kind, payload)
	end
end

function NetworkService:pushAll(kind: string, payload: any)
	Net.Push:FireAllClients(kind, payload)
end

function NetworkService:look(player: Player, payload: any)
	if player.Parent then
		Net.Look:FireClient(player, payload)
	end
end

-- Sends a notification toast to one player.
function NetworkService:notify(player: Player, title: string, text: string?, kind: string?)
	self:push(player, "Notify", { Title = title, Text = text, Kind = kind or "Info" })
end

function NetworkService:Start()
	Net.Request.OnServerInvoke = function(player, endpoint, ...)
		return self:_request(player, endpoint, ...)
	end
	Net.Act.OnServerEvent:Connect(function(player, payload)
		local limits = Config.Net.Buckets.Act
		if not self:take(player, "Act", limits.Rate, limits.Burst) then
			flag(player, "act rate", "Minor")
			return
		end
		if not checkArg("table", payload) then
			flag(player, "bad act payload", "Moderate")
			return
		end
		if actHandler then
			local ok, err = pcall(actHandler, player, payload)
			if not ok then
				warn("[VARIANCE/Network] act handler failed: " .. tostring(err))
			end
		end
	end)
	Net.Look.OnServerEvent:Connect(function(player, payload)
		local limits = Config.Net.Buckets.Look
		if not self:take(player, "Look", limits.Rate, limits.Burst) then
			return -- unreliable presence data: just drop, no flag
		end
		if type(payload) ~= "table" or not checkArg("table", payload) then
			return
		end
		if lookHandler then
			lookHandler(player, payload)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
end

return NetworkService

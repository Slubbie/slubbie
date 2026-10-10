-- The gate every client request passes through.
--
--  * Validates arguments against the schema in RemoteDefinitions (type,
--    length, range, allowed values, argument count). Anything else is
--    rejected before a handler runs.
--  * Rate limits each remote per player with a token bucket.
--  * Refuses gameplay requests until the player's profile has loaded.
--  * Wraps handlers in pcall so a bug returns a clean failure instead of
--    leaving the client's RemoteFunction hanging.
--  * Counts violations; a flood of invalid requests gets the player removed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteDefinitions = require(Shared.RemoteDefinitions)

local SecurityService = { Name = "SecurityService" }

local VIOLATION_WINDOW = 60
local VIOLATION_KICK = 250

local services: { [string]: any } = {}

type Bucket = { Tokens: number, Last: number }
local buckets: { [Player]: { [string]: Bucket } } = {}
local violations: { [Player]: { Count: number, Since: number, Logged: number } } = {}

SecurityService.Clock = os.clock
-- Every bound handler, already wrapped in validation + rate limiting. Tests
-- call these directly; in the game they are attached to the remotes.
SecurityService.Handlers = {} :: { [string]: (Player, ...any) -> any }
SecurityService.AttachRemotes = true

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Validates one argument. Returns (ok, cleanedValue | reason).
function SecurityService.ValidateArg(spec: RemoteDefinitions.ArgSpec, value: any): (boolean, any)
	if value == nil then
		if spec.Optional then
			return true, nil
		end
		return false, "missing argument"
	end
	local kind = spec.Type
	if kind == "string" then
		if type(value) ~= "string" then
			return false, "expected string"
		end
		if #value == 0 or #value > (spec.MaxLength or 64) or utf8.len(value) == nil then
			return false, "string length or encoding"
		end
		return true, value
	elseif kind == "integer" or kind == "number" then
		if not isFinite(value) then
			return false, "expected finite number"
		end
		if kind == "integer" and value ~= math.floor(value) then
			return false, "expected integer"
		end
		if (spec.Min and value < spec.Min) or (spec.Max and value > spec.Max) then
			return false, "number out of range"
		end
		return true, value
	elseif kind == "boolean" then
		if type(value) ~= "boolean" then
			return false, "expected boolean"
		end
		return true, value
	elseif kind == "enum" then
		if type(value) ~= "string" or not spec.Values or not table.find(spec.Values, value) then
			return false, "value not allowed"
		end
		return true, value
	elseif kind == "settings" then
		return SecurityService.ValidateSettings(value)
	end
	return false, "unknown spec type"
end

-- Settings: a flat table of known keys only. Returns a cleaned copy.
function SecurityService.ValidateSettings(value: any): (boolean, any)
	if type(value) ~= "table" then
		return false, "expected settings table"
	end
	local clean = {}
	local count = 0
	for key, item in value do
		count += 1
		if count > 16 or type(key) ~= "string" then
			return false, "too many or invalid keys"
		end
		local spec = RemoteDefinitions.SettingsSchema[key]
		if not spec then
			return false, `unknown setting '{key}'`
		end
		local ok, cleaned = SecurityService.ValidateArg(spec, item)
		if not ok or cleaned == nil then
			return false, `invalid value for '{key}'`
		end
		clean[key] = cleaned
	end
	return true, clean
end

-- Validates a whole argument list. Returns (ok, cleanedArgs | reason).
function SecurityService.ValidateArgs(specs: { RemoteDefinitions.ArgSpec }, ...: any): (boolean, any)
	local count = select("#", ...)
	if count > #specs then
		return false, "too many arguments"
	end
	local args = { ... }
	local cleaned = table.create(#specs)
	for i, spec in specs do
		local ok, result = SecurityService.ValidateArg(spec, args[i])
		if not ok then
			return false, `argument {i}: {result}`
		end
		cleaned[i] = result
	end
	return true, cleaned
end

-- Token bucket per player per remote. Returns false when the player is over the limit.
function SecurityService.Consume(player: Player, remoteName: string): boolean
	local spec = RemoteDefinitions.Remotes[remoteName]
	local rate = spec and spec.Rate
	if not rate then
		return true
	end
	local now = SecurityService.Clock()
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local bucket = perPlayer[remoteName]
	if not bucket then
		bucket = { Tokens = rate.Burst, Last = now }
		perPlayer[remoteName] = bucket
	end
	bucket.Tokens = math.min(rate.Burst, bucket.Tokens + (now - bucket.Last) * rate.PerSecond)
	bucket.Last = now
	if bucket.Tokens < 1 then
		return false
	end
	bucket.Tokens -= 1
	return true
end

-- Records a rejected request. Logs at most once every 10 seconds per player.
function SecurityService.Flag(player: Player, remoteName: string, reason: string)
	local now = SecurityService.Clock()
	local record = violations[player]
	if not record or now - record.Since > VIOLATION_WINDOW then
		record = { Count = 0, Since = now, Logged = -math.huge }
		violations[player] = record
	end
	record.Count += 1
	if now - record.Logged > 10 then
		record.Logged = now
		warn(`[Security] {player.Name} ({player.UserId}) {remoteName}: {reason} ({record.Count} in window)`)
	end
	if record.Count >= VIOLATION_KICK and player.Parent then
		player:Kick("Too many invalid requests. Please rejoin.")
	end
end

function SecurityService.ViolationCount(player: Player): number
	local record = violations[player]
	return if record then record.Count else 0
end

-- Position of a player's character root, or nil if they have no live character.
function SecurityService.GetRootPosition(player: Player): Vector3?
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 0 then
		return nil
	end
	return root.Position
end

type BindOptions = { RequireProfile: boolean? }

local function guard(
	player: Player,
	name: string,
	spec: RemoteDefinitions.RemoteSpec,
	options: BindOptions?,
	...: any
): (boolean, any)
	if not SecurityService.Consume(player, name) then
		SecurityService.Flag(player, name, "rate limited")
		return false, "RateLimited"
	end
	local ok, args = SecurityService.ValidateArgs(spec.Args or {}, ...)
	if not ok then
		SecurityService.Flag(player, name, args)
		return false, "BadRequest"
	end
	local requireProfile = if options and options.RequireProfile ~= nil then options.RequireProfile else true
	if requireProfile and not services.PlayerDataService.IsLoaded(player) then
		return false, "NotReady"
	end
	return true, args
end

-- Binds a RemoteFunction. The handler receives validated args and returns a result table.
function SecurityService.BindFunction(name: string, handler: (Player, ...any) -> any, options: BindOptions?)
	local spec = RemoteDefinitions.Remotes[name]
	assert(
		spec and spec.Kind == "Function" and spec.Direction == "ToServer",
		`{name} is not a client→server function`
	)
	local function guarded(player: Player, ...: any): any
		local ok, args = guard(player, name, spec, options, ...)
		if not ok then
			return { Ok = false, Reason = args }
		end
		local success, result = pcall(handler, player, table.unpack(args, 1, #(spec.Args or {})))
		if not success then
			warn(`[Security] {name} handler error for {player.Name}: {result}`)
			return { Ok = false, Reason = "ServerError" }
		end
		return result
	end
	SecurityService.Handlers[name] = guarded
	if SecurityService.AttachRemotes then
		RemoteDefinitions.GetFunction(name).OnServerInvoke = guarded
	end
end

-- Binds a RemoteEvent (fire-and-forget).
function SecurityService.BindEvent(name: string, handler: (Player, ...any) -> (), options: BindOptions?)
	local spec = RemoteDefinitions.Remotes[name]
	assert(spec and spec.Kind == "Event" and spec.Direction == "ToServer", `{name} is not a client→server event`)
	local function guarded(player: Player, ...: any): any
		local ok, args = guard(player, name, spec, options, ...)
		if not ok then
			return nil
		end
		local success, err = pcall(handler, player, table.unpack(args, 1, #(spec.Args or {})))
		if not success then
			warn(`[Security] {name} handler error for {player.Name}: {err}`)
		end
		return nil
	end
	SecurityService.Handlers[name] = guarded
	if SecurityService.AttachRemotes then
		RemoteDefinitions.GetEvent(name).OnServerEvent:Connect(guarded)
	end
end

function SecurityService.Init(registry: { [string]: any })
	services = registry
end

function SecurityService.Start()
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
		violations[player] = nil
	end)
end

return SecurityService

-- Client side of the network contract (shared/Net.luau).
--   request(endpoint, ...) -> ok, result      (never hangs: times out after 15s)
--   onPush(kind, fn), onMatch(kind, fn)       subscribe to server messages
--   act(payload)                              send a gameplay action
--   look(yaw, pitch)                          seated head direction (throttled)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Variance.Net)
local Signal = require(ReplicatedStorage.Variance.Util.Signal)

local NetworkClient = {}

local pushSignals: { [string]: any } = {}
local matchSignals: { [string]: any } = {}
local lookSignal = Signal.new()
local lastLook = 0
local REQUEST_TIMEOUT = 15

local function signalFor(map, kind: string)
	local s = map[kind]
	if s == nil then
		s = Signal.new()
		map[kind] = s
	end
	return s
end

function NetworkClient:Init(controllers)
	self.Controllers = controllers
end

function NetworkClient:onPush(kind: string, fn: (any) -> ())
	return signalFor(pushSignals, kind):Connect(fn)
end

function NetworkClient:onMatch(kind: string, fn: (any) -> ())
	return signalFor(matchSignals, kind):Connect(fn)
end

function NetworkClient:onLook(fn: (any) -> ())
	return lookSignal:Connect(fn)
end

-- Invokes a server endpoint. Returns (ok, result); never errors.
function NetworkClient:request(endpoint: string, ...: any): (boolean, any)
	local args = table.pack(...)
	local done = false
	local okResult, result = false, "Timed out."
	local thread = coroutine.running()
	task.spawn(function()
		local ok, success, value = pcall(function()
			return Net.Request:InvokeServer(endpoint, table.unpack(args, 1, args.n))
		end)
		if done then
			return
		end
		done = true
		if ok then
			okResult, result = success == true, value
		else
			okResult, result = false, "Connection problem."
		end
		task.spawn(thread)
	end)
	task.delay(REQUEST_TIMEOUT, function()
		if not done then
			done = true
			task.spawn(thread)
		end
	end)
	coroutine.yield()
	return okResult, result
end

function NetworkClient:act(payload: { [string]: any })
	Net.Act:FireServer(payload)
end

function NetworkClient:look(yaw: number, pitch: number)
	local now = os.clock()
	if now - lastLook < 0.15 then
		return
	end
	lastLook = now
	Net.Look:FireServer({ Yaw = yaw, Pitch = pitch })
end

function NetworkClient:Start()
	Net.Push.OnClientEvent:Connect(function(kind, payload)
		if type(kind) == "string" then
			signalFor(pushSignals, kind):Fire(payload)
		end
	end)
	Net.Match.OnClientEvent:Connect(function(kind, payload)
		if type(kind) == "string" then
			signalFor(matchSignals, kind):Fire(payload)
		end
	end)
	Net.Look.OnClientEvent:Connect(function(payload)
		lookSignal:Fire(payload)
	end)
end

return NetworkClient

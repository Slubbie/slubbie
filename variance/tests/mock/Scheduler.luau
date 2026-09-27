--# selene: allow(global_usage, unused_variable, shadowing)
-- Virtual time, threads, contexts and signals for the runtime mock.
--
-- Everything runs on coroutines driven by a virtual clock, so a five-minute
-- match simulates in seconds. Each thread belongs to a context (the server or
-- one client): a thread inherits its creator's context, and a signal handler
-- runs in the context of the code that connected it. Context-dependent APIs
-- (Players.LocalPlayer, RunService:IsServer, workspace.CurrentCamera, remote
-- routing) read the current thread's context.

local Scheduler = {}

Scheduler.now = 0
Scheduler.errors = {} -- { { Context, Message, Trace } }
Scheduler.frame = 0

local heap = {}
local seq = 0
local contextOf = setmetatable({}, { __mode = "k" })
local cancelled = setmetatable({}, { __mode = "k" })
local mainContext = nil

function Scheduler.setDefaultContext(ctx)
	mainContext = ctx
end

function Scheduler.context()
	local co = coroutine.running()
	return (co and contextOf[co]) or mainContext
end

function Scheduler.contextOf(thread)
	return contextOf[thread]
end

-- Binary heap keyed by (time, seq).
local function less(a, b)
	if a.Time ~= b.Time then
		return a.Time < b.Time
	end
	return a.Seq < b.Seq
end

local function push(item)
	seq += 1
	item.Seq = seq
	table.insert(heap, item)
	local i = #heap
	while i > 1 do
		local p = i // 2
		if less(heap[i], heap[p]) then
			heap[i], heap[p] = heap[p], heap[i]
			i = p
		else
			break
		end
	end
end

local function pop()
	local top = heap[1]
	local last = table.remove(heap)
	if #heap > 0 then
		heap[1] = last
		local i = 1
		while true do
			local l, r = i * 2, i * 2 + 1
			local m = i
			if l <= #heap and less(heap[l], heap[m]) then
				m = l
			end
			if r <= #heap and less(heap[r], heap[m]) then
				m = r
			end
			if m == i then
				break
			end
			heap[i], heap[m] = heap[m], heap[i]
			i = m
		end
	end
	return top
end

local function report(thread, err)
	local ctx = contextOf[thread]
	local trace = debug.traceback(thread, tostring(err))
	table.insert(Scheduler.errors, { Context = ctx and ctx.Name or "?", Message = tostring(err), Trace = trace })
	if Scheduler.onError then
		Scheduler.onError(ctx, err, trace)
	end
end

function Scheduler.resume(thread, ...)
	if cancelled[thread] or coroutine.status(thread) ~= "suspended" then
		return
	end
	local ok, err = coroutine.resume(thread, ...)
	if not ok then
		report(thread, err)
	end
end

function Scheduler.newThread(fn, ctx)
	local co = coroutine.create(fn)
	contextOf[co] = ctx or Scheduler.context()
	return co
end

-- Runs `fn` now on a new thread in `ctx` (default: the caller's).
function Scheduler.spawnIn(ctx, fn, ...)
	local co = Scheduler.newThread(fn, ctx)
	Scheduler.resume(co, ...)
	return co
end

function Scheduler.schedule(delay: number, thread, ...)
	push({ Time = Scheduler.now + math.max(delay, 0), Thread = thread, Args = table.pack(...) })
end

---------------------------------------------------------------------------
-- task library
---------------------------------------------------------------------------

local task = {}

function task.spawn(fnOrThread, ...)
	if type(fnOrThread) == "thread" then
		Scheduler.resume(fnOrThread, ...)
		return fnOrThread
	end
	return Scheduler.spawnIn(nil, fnOrThread, ...)
end

function task.defer(fnOrThread, ...)
	local thread = if type(fnOrThread) == "thread" then fnOrThread else Scheduler.newThread(fnOrThread)
	Scheduler.schedule(0, thread, ...)
	return thread
end

function task.delay(t, fnOrThread, ...)
	local thread = if type(fnOrThread) == "thread" then fnOrThread else Scheduler.newThread(fnOrThread)
	Scheduler.schedule(t or 0, thread, ...)
	return thread
end

function task.wait(t)
	local co = coroutine.running()
	if co == nil or not coroutine.isyieldable() then
		error("task.wait called outside a yieldable thread", 2)
	end
	local start = Scheduler.now
	Scheduler.schedule(math.max(t or 0, 1 / 60), co)
	coroutine.yield()
	return Scheduler.now - start
end

function task.cancel(thread)
	cancelled[thread] = true
end

function task.synchronize() end
function task.desynchronize() end

Scheduler.task = task

-- One network hop (remote delivery and each direction of an invoke).
Scheduler.LATENCY = 0.03

-- For request/response across contexts: returns (handle, await). await()
-- always yields at least one network hop, like a real round trip, even if the
-- other side answered synchronously.
function Scheduler.suspend()
	local co = coroutine.running()
	local state = { Done = false, Waiting = false, Results = nil }
	local handle = {}
	function handle.resume(...)
		if state.Done then
			return
		end
		state.Done = true
		state.Results = table.pack(...)
		if state.Waiting then
			Scheduler.schedule(Scheduler.LATENCY, co)
		end
	end
	local function await()
		if not state.Done then
			state.Waiting = true
			while not state.Done do
				coroutine.yield()
			end
		else
			Scheduler.schedule(Scheduler.LATENCY, co)
			coroutine.yield()
		end
		return table.unpack(state.Results, 1, state.Results.n)
	end
	return handle, await
end

-- Runs fn later (after one network hop) on a fresh thread.
function Scheduler.deliver(fn)
	local thread = coroutine.create(fn)
	contextOf[thread] = mainContext
	Scheduler.schedule(Scheduler.LATENCY, thread)
end

---------------------------------------------------------------------------
-- Signals (RBXScriptSignal / RBXScriptConnection)
---------------------------------------------------------------------------

local Signal = {}
Signal.__index = Signal

local ConnectionMt = { __type = "RBXScriptConnection" }
ConnectionMt.__index = function(self, key)
	if key == "Disconnect" then
		return function(c)
			rawset(c, "Connected", false)
		end
	end
	error(tostring(key) .. " is not a valid member of RBXScriptConnection", 2)
end

local SignalMt = { __type = "RBXScriptSignal" }

function Scheduler.signal(name: string?)
	local s = setmetatable({ Name = name or "Signal", Connections = {}, Waiting = {} }, SignalMt)
	return s
end

SignalMt.__index = function(self, key)
	if key == "Connect" then
		return function(s, fn)
			if type(fn) ~= "function" then
				error("Attempt to connect failed: Passed value is not a function", 2)
			end
			local c = setmetatable({ Connected = true, Fn = fn, Context = Scheduler.context() }, ConnectionMt)
			table.insert(s.Connections, c)
			return c
		end
	elseif key == "Once" then
		return function(s, fn)
			local c
			c = setmetatable({
				Connected = true,
				Context = Scheduler.context(),
				Fn = function(...)
					rawset(c, "Connected", false)
					fn(...)
				end,
			}, ConnectionMt)
			table.insert(s.Connections, c)
			return c
		end
	elseif key == "Wait" then
		return function(s)
			local co = coroutine.running()
			table.insert(s.Waiting, { Thread = co, Context = Scheduler.context() })
			return coroutine.yield()
		end
	elseif key == "ConnectParallel" then
		return SignalMt.__index(self, "Connect")
	end
	error(tostring(key) .. " is not a valid member of RBXScriptSignal", 2)
end

-- Fires to every connection (optionally only those whose context passes `filter`).
function Scheduler.fire(s, filter, ...)
	local list = s.Connections
	local keep = {}
	local toRun = {}
	for _, c in list do
		if rawget(c, "Connected") and not (c.Context and c.Context.Dead) then
			table.insert(keep, c)
			if filter == nil or filter(c.Context) then
				table.insert(toRun, c)
			end
		end
	end
	s.Connections = keep
	local waiting = s.Waiting
	s.Waiting = {}
	for _, c in toRun do
		if rawget(c, "Connected") then
			Scheduler.spawnIn(c.Context, c.Fn, ...)
		end
	end
	for _, w in waiting do
		if filter == nil or filter(w.Context) then
			Scheduler.resume(w.Thread, ...)
		else
			table.insert(s.Waiting, w)
		end
	end
end

function Scheduler.hasListeners(s): boolean
	for _, c in s.Connections do
		if rawget(c, "Connected") then
			return true
		end
	end
	return #s.Waiting > 0
end

---------------------------------------------------------------------------
-- Running
---------------------------------------------------------------------------

Scheduler.frameHooks = {} -- functions(dt) called once per frame

-- Advances virtual time by dt, resuming everything due, then runs a frame.
function Scheduler.step(dt: number)
	local target = Scheduler.now + dt
	while #heap > 0 and heap[1].Time <= target do
		local item = pop()
		if item.Time > Scheduler.now then
			Scheduler.now = item.Time
		end
		Scheduler.resume(item.Thread, table.unpack(item.Args, 1, item.Args.n))
	end
	Scheduler.now = target
	Scheduler.frame += 1
	for _, hook in Scheduler.frameHooks do
		hook(dt)
	end
end

-- Steps frames until `predicate()` is true or `timeout` virtual seconds pass.
function Scheduler.runUntil(predicate: () -> boolean, timeout: number, fps: number?): boolean
	local dt = 1 / (fps or 30)
	local deadline = Scheduler.now + timeout
	while Scheduler.now < deadline do
		if predicate() then
			return true
		end
		Scheduler.step(dt)
	end
	return predicate()
end

function Scheduler.run(seconds: number, fps: number?)
	Scheduler.runUntil(function()
		return false
	end, seconds, fps)
end

return Scheduler

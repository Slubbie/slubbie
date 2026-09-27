-- Minimal synchronous signal used by services and controllers to talk to each
-- other without RemoteEvents or BindableEvents (no serialization, no yielding).
--
--   local changed = Signal.new()
--   local conn = changed:Connect(function(a, b) ... end)
--   changed:Fire(1, 2)
--   conn:Disconnect()

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal = {
	Connect: (self: Signal, fn: (...any) -> ()) -> Connection,
	Once: (self: Signal, fn: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
	Wait: (self: Signal) -> ...any,
	DisconnectAll: (self: Signal) -> (),
}

local Signal = {}
Signal.__index = Signal

function Signal.new(): Signal
	return setmetatable({ _handlers = {} }, Signal) :: any
end

function Signal:Connect(fn)
	local handlers = self._handlers
	local connection
	connection = {
		Connected = true,
		Disconnect = function(c)
			if not c.Connected then
				return
			end
			c.Connected = false
			local index = table.find(handlers, connection)
			if index then
				table.remove(handlers, index)
			end
		end,
		_fn = fn,
	}
	table.insert(handlers, connection)
	return connection
end

function Signal:Once(fn)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

function Signal:Fire(...)
	-- Copy so handlers can disconnect themselves while we iterate.
	local snapshot = table.clone(self._handlers)
	for _, connection in snapshot do
		if connection.Connected then
			local ok, err = pcall(connection._fn, ...)
			if not ok then
				warn("[Signal] handler error:", err, debug.traceback())
			end
		end
	end
end

function Signal:Wait()
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:DisconnectAll()
	for _, connection in table.clone(self._handlers) do
		connection:Disconnect()
	end
end

return Signal

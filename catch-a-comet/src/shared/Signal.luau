--!strict
-- Minimal signal used for communication between services (server) and
-- controllers (client). Each handler runs in its own thread, so a handler
-- that errors or yields can never break the code that fired the signal.
-- Handlers that don't yield finish before Fire returns.

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

type Handler = {
	Fn: (...any) -> (),
	Connection: Connection,
}

local Signal = {}
Signal.__index = Signal

export type Signal = typeof(setmetatable({} :: { _handlers: { Handler } }, Signal))

function Signal.new(): Signal
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal.Connect(self: Signal, fn: (...any) -> ()): Connection
	local handlers = self._handlers
	local handler: Handler
	local connection = {
		Connected = true,
		Disconnect = function(connection: Connection)
			if not connection.Connected then
				return
			end
			connection.Connected = false
			local index = table.find(handlers, handler)
			if index then
				table.remove(handlers, index)
			end
		end,
	}
	handler = { Fn = fn, Connection = connection }
	table.insert(handlers, handler)
	return connection
end

function Signal.Once(self: Signal, fn: (...any) -> ()): Connection
	local connection: Connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

function Signal.Fire(self: Signal, ...: any)
	-- Iterate over a copy so handlers may disconnect while we fire.
	for _, handler in table.clone(self._handlers) do
		if handler.Connection.Connected then
			task.spawn(handler.Fn, ...)
		end
	end
end

-- Yields the current thread until the signal fires; returns the fired values.
function Signal.Wait(self: Signal): ...any
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal.DisconnectAll(self: Signal)
	for _, handler in table.clone(self._handlers) do
		handler.Connection:Disconnect()
	end
end

return Signal

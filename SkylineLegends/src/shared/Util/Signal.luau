-- Minimal synchronous signal for in-process events between modules.

export type Connection = { Disconnect: (Connection) -> (), Connected: boolean }
export type Signal = {
	Connect: (Signal, (...any) -> ()) -> Connection,
	Once: (Signal, (...any) -> ()) -> Connection,
	Fire: (Signal, ...any) -> (),
	DisconnectAll: (Signal) -> (),
}

local Signal = {}
Signal.__index = Signal

function Signal.new(): Signal
	return setmetatable({ _handlers = {} }, Signal) :: any
end

function Signal:Connect(fn: (...any) -> ())
	local handlers = self._handlers
	local connection = { Connected = true }
	function connection.Disconnect(conn)
		if not conn.Connected then
			return
		end
		conn.Connected = false
		local index = table.find(handlers, fn)
		if index then
			table.remove(handlers, index)
		end
	end
	table.insert(handlers, fn)
	return connection
end

function Signal:Once(fn: (...any) -> ())
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

function Signal:Fire(...)
	-- Copy so handlers can disconnect while we iterate.
	for _, fn in table.clone(self._handlers) do
		local ok, err = pcall(fn, ...)
		if not ok then
			warn("[Signal] handler error: " .. tostring(err))
		end
	end
end

function Signal:DisconnectAll()
	table.clear(self._handlers)
end

return Signal

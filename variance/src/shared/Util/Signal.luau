-- Lightweight signal (event) object used by services and controllers.
--
-- Handlers run in their own thread via task.spawn so a yielding or erroring
-- handler never blocks the others. :Wait(timeout) returns nil on timeout.

local Signal = {}
Signal.__index = Signal

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal = typeof(setmetatable(
	{} :: { _handlers: { [any]: (...any) -> () }, _order: { any }, _waiting: { thread } },
	Signal
))

local Connection = {}
Connection.__index = Connection

function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false
	local signal = self._signal
	signal._handlers[self] = nil
	local index = table.find(signal._order, self)
	if index then
		table.remove(signal._order, index)
	end
end
Connection.Destroy = Connection.Disconnect

function Signal.new(): Signal
	return setmetatable({ _handlers = {}, _order = {}, _waiting = {} }, Signal) :: any
end

function Signal:Connect(handler: (...any) -> ()): Connection
	local connection = setmetatable({ Connected = true, _signal = self }, Connection)
	self._handlers[connection] = handler
	table.insert(self._order, connection)
	return connection :: any
end

function Signal:Once(handler: (...any) -> ()): Connection
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

function Signal:Fire(...: any)
	-- Copy so handlers can disconnect while we iterate.
	local order = table.clone(self._order)
	for _, connection in order do
		local handler = self._handlers[connection]
		if handler then
			task.spawn(handler, ...)
		end
	end
	if #self._waiting > 0 then
		local waiting = self._waiting
		self._waiting = {}
		for _, thread in waiting do
			if coroutine.status(thread) == "suspended" then
				task.spawn(thread, true, ...)
			end
		end
	end
end

-- Yields until the signal fires. With a timeout, returns nil if it expires.
function Signal:Wait(timeout: number?): ...any
	local thread = coroutine.running()
	table.insert(self._waiting, thread)
	local timer
	if timeout then
		timer = task.delay(timeout, function()
			local index = table.find(self._waiting, thread)
			if index then
				table.remove(self._waiting, index)
				task.spawn(thread, false)
			end
		end)
	end
	local results = table.pack(coroutine.yield())
	if timer then
		pcall(task.cancel, timer)
	end
	if not results[1] then
		return nil
	end
	return table.unpack(results, 2, results.n)
end

function Signal:DisconnectAll()
	for _, connection in table.clone(self._order) do
		connection:Disconnect()
	end
end

function Signal:Destroy()
	self:DisconnectAll()
	local waiting = self._waiting
	self._waiting = {}
	for _, thread in waiting do
		if coroutine.status(thread) == "suspended" then
			task.spawn(thread, false)
		end
	end
end

return Signal

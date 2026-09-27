-- Tiny signal: Connect(fn) returns a connection with Disconnect(); Fire(...) calls every listener.

local Signal = {}
Signal.__index = Signal

export type Connection = { Disconnect: (Connection) -> () }

function Signal.new()
	return setmetatable({ listeners = {} :: { [any]: (...any) -> () } }, Signal)
end

function Signal:Connect(fn: (...any) -> ()): Connection
	local key = {}
	self.listeners[key] = fn
	local listeners = self.listeners
	return {
		Disconnect = function()
			listeners[key] = nil
		end,
	} :: any
end

function Signal:Fire(...: any)
	for _, fn in self.listeners do
		task.spawn(fn, ...)
	end
end

return Signal

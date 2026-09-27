-- Collects things that need cleaning up (connections, instances, threads,
-- callbacks, objects with :Destroy()) and releases them all at once.
-- Every match, screen and presenter owns a Trove so nothing leaks between matches.

local Trove = {}
Trove.__index = Trove

export type Trove = typeof(setmetatable({} :: { _items: { any }, _cleaning: boolean }, Trove))

function Trove.new(): Trove
	return setmetatable({ _items = {}, _cleaning = false }, Trove) :: any
end

function Trove:Add<T>(item: T): T
	if self._cleaning then
		-- Adding while cleaning: release immediately so nothing is orphaned.
		Trove._release(item)
		return item
	end
	table.insert(self._items, item)
	return item
end

-- Convenience: connect and track in one call.
function Trove:Connect(signal: any, handler: (...any) -> ()): any
	return self:Add(signal:Connect(handler))
end

-- Creates an Instance and tracks it.
function Trove:Instance(className: string, props: { [string]: any }?): Instance
	local instance = Instance.new(className)
	if props then
		local parent = props.Parent
		for key, value in props do
			if key ~= "Parent" then
				(instance :: any)[key] = value
			end
		end
		if parent then
			instance.Parent = parent
		end
	end
	return self:Add(instance)
end

-- Creates a child trove that is cleaned with this one.
function Trove:Extend(): Trove
	return self:Add(Trove.new())
end

function Trove:Remove(item: any)
	local index = table.find(self._items, item)
	if index then
		table.remove(self._items, index)
		Trove._release(item)
	end
end

function Trove._release(item: any)
	local kind = typeof(item)
	if kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		item:Destroy()
	elseif kind == "function" then
		local ok, err = pcall(item)
		if not ok then
			warn("[Trove] cleanup callback failed:", err)
		end
	elseif kind == "thread" then
		if coroutine.status(item) ~= "dead" then
			pcall(task.cancel, item)
		end
	elseif kind == "table" then
		if type(item.Destroy) == "function" then
			item:Destroy()
		elseif type(item.Disconnect) == "function" then
			item:Disconnect()
		elseif type(item.Clean) == "function" then
			item:Clean()
		end
	end
end

function Trove:Clean()
	if self._cleaning then
		return
	end
	self._cleaning = true
	local items = self._items
	self._items = {}
	for i = #items, 1, -1 do
		Trove._release(items[i])
	end
	self._cleaning = false
end
Trove.Destroy = Trove.Clean

return Trove

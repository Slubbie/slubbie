-- Collects connections, instances, threads and cleanup functions so a screen,
-- model or session can tear everything down in one call.
--
--   local maid = Maid.new()
--   maid:Add(part.Touched:Connect(...))
--   maid:Add(someInstance)
--   maid:Add(function() ... end)
--   maid:Clean()

export type Maid = {
	Add: <T>(self: Maid, item: T) -> T,
	Clean: (self: Maid) -> (),
	Destroy: (self: Maid) -> (),
}

local Maid = {}
Maid.__index = Maid

function Maid.new(): Maid
	return setmetatable({ _items = {} }, Maid) :: any
end

function Maid:Add(item)
	table.insert(self._items, item)
	return item
end

local function cleanup(item: any)
	local kind = typeof(item)
	if kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		item:Destroy()
	elseif kind == "function" then
		item()
	elseif kind == "thread" then
		pcall(task.cancel, item)
	elseif kind == "table" then
		if type(item.Disconnect) == "function" then
			item:Disconnect()
		elseif type(item.Destroy) == "function" then
			item:Destroy()
		elseif type(item.Clean) == "function" then
			item:Clean()
		end
	end
end

function Maid:Clean()
	local items = self._items
	self._items = {}
	-- Reverse order: things created last are usually children of things created first.
	for i = #items, 1, -1 do
		local ok, err = pcall(cleanup, items[i])
		if not ok then
			warn("[Maid] cleanup error:", err)
		end
	end
end

Maid.Destroy = Maid.Clean

return Maid

-- Table helpers used by data migration, replication and configs.

local TableUtil = {}

function TableUtil.DeepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value :: any do
		copy[key] = TableUtil.DeepCopy(item)
	end
	return copy :: any
end

-- Fill in any keys missing from `target` with copies from `template` (recursively
-- for nested dictionaries). Existing values are kept, even if their type differs
-- from the template, unless `fixTypes` is set.
function TableUtil.Reconcile(target: { [any]: any }, template: { [any]: any }, fixTypes: boolean?)
	for key, default in template do
		local current = target[key]
		if current == nil then
			target[key] = TableUtil.DeepCopy(default)
		elseif fixTypes and type(current) ~= type(default) then
			target[key] = TableUtil.DeepCopy(default)
		elseif type(current) == "table" and type(default) == "table" and next(default) ~= nil then
			-- Only recurse into dictionaries that define a shape (non-empty templates).
			TableUtil.Reconcile(current, default, fixTypes)
		end
	end
end

function TableUtil.Count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

function TableUtil.Keys<K>(t: { [K]: any }): { K }
	local keys = {}
	for key in t do
		table.insert(keys, key)
	end
	return keys
end

function TableUtil.Map<T, U>(list: { T }, fn: (T) -> U): { U }
	local out = table.create(#list)
	for i, item in list do
		out[i] = fn(item)
	end
	return out
end

function TableUtil.Filter<T>(list: { T }, fn: (T) -> boolean): { T }
	local out = {}
	for _, item in list do
		if fn(item) then
			table.insert(out, item)
		end
	end
	return out
end

function TableUtil.Find<T>(list: { T }, fn: (T) -> boolean): T?
	for _, item in list do
		if fn(item) then
			return item
		end
	end
	return nil
end

function TableUtil.Set(list: { any }): { [any]: boolean }
	local set = {}
	for _, item in list do
		set[item] = true
	end
	return set
end

function TableUtil.Shuffle<T>(list: { T }, random: Random): { T }
	for i = #list, 2, -1 do
		local j = random:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

-- Read a nested value: Get(t, {"A", "B"}) == t.A.B (nil-safe).
function TableUtil.Get(t: any, path: { any }): any
	local node = t
	for _, key in path do
		if type(node) ~= "table" then
			return nil
		end
		node = node[key]
	end
	return node
end

-- Write a nested value, creating intermediate tables.
function TableUtil.SetPath(t: any, path: { any }, value: any)
	local node = t
	for i = 1, #path - 1 do
		local key = path[i]
		if type(node[key]) ~= "table" then
			node[key] = {}
		end
		node = node[key]
	end
	node[path[#path]] = value
end

-- Recursively freeze a config table so accidental writes error loudly.
function TableUtil.DeepFreeze<T>(t: T): T
	if type(t) == "table" and not table.isfrozen(t :: any) then
		for _, value in t :: any do
			TableUtil.DeepFreeze(value)
		end
		table.freeze(t :: any)
	end
	return t
end

-- Approximate serialized size (for DataStore budget warnings).
function TableUtil.ApproxSize(value: any): number
	local kind = type(value)
	if kind == "table" then
		local size = 2
		for key, item in value do
			size += TableUtil.ApproxSize(key) + TableUtil.ApproxSize(item) + 2
		end
		return size
	elseif kind == "string" then
		return #value + 2
	elseif kind == "number" then
		return 8
	end
	return 5
end

return TableUtil

-- Small table helpers (pure Luau).

local TableUtil = {}

function TableUtil.deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value :: any do
		copy[TableUtil.deepCopy(k)] = TableUtil.deepCopy(v)
	end
	return copy :: any
end

-- Fills in any keys missing from `target` using `template`, recursively.
-- Existing values of the wrong type are replaced by the template's value.
function TableUtil.reconcile(target: { [any]: any }, template: { [any]: any }): { [any]: any }
	for key, default in template do
		local current = target[key]
		if type(default) == "table" and type(current) == "table" then
			TableUtil.reconcile(current, default)
		elseif current == nil or type(default) ~= type(current) then
			target[key] = TableUtil.deepCopy(default)
		end
	end
	return target
end

function TableUtil.count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

function TableUtil.keys(t: { [any]: any }): { any }
	local keys = {}
	for key in t do
		table.insert(keys, key)
	end
	return keys
end

function TableUtil.sortedKeys(t: { [any]: any }): { any }
	local keys = TableUtil.keys(t)
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	return keys
end

function TableUtil.map<T, U>(list: { T }, fn: (T, number) -> U): { U }
	local out = table.create(#list)
	for i, v in list do
		out[i] = fn(v, i)
	end
	return out
end

function TableUtil.filter<T>(list: { T }, fn: (T) -> boolean): { T }
	local out = {}
	for _, v in list do
		if fn(v) then
			table.insert(out, v)
		end
	end
	return out
end

function TableUtil.sum(list: { number }): number
	local total = 0
	for _, v in list do
		total += v
	end
	return total
end

-- Keeps at most `limit` items, dropping from the front (oldest first).
function TableUtil.trimFront<T>(list: { T }, limit: number)
	while #list > limit do
		table.remove(list, 1)
	end
end

function TableUtil.freezeDeep<T>(t: T): T
	if type(t) == "table" and not table.isfrozen(t :: any) then
		for _, v in t :: any do
			TableUtil.freezeDeep(v)
		end
		table.freeze(t :: any)
	end
	return t
end

return TableUtil

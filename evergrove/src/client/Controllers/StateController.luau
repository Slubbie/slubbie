-- Mirror of the player's replicated profile.
--
-- The server sends one full snapshot after loading ({ Full = profile }), then
-- batched patches ({ Patches = { { path, value } } }). Every UI reads from here
-- and subscribes to changes by top-level key or full path:
--
--   State.Get("Inventory", "Slots")
--   State.Changed:Connect(function(path) ... end)      -- path = { "Inventory", ... }
--   State.Watch("Coins", fn)                            -- fn(value) now and on change

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Signal = require(Shared.Lib.Signal)

local State = {}
State.Changed = Signal.new() -- (path)
State.Loaded = Signal.new() -- ()
State.ReadOnly = false

local data: any = nil
local watchers: { [string]: { (any) -> () } } = {}

function State.IsLoaded(): boolean
	return data ~= nil
end

function State.Data(): any
	return data
end

function State.Get(...: any): any
	local node = data
	for i = 1, select("#", ...) do
		if type(node) ~= "table" then
			return nil
		end
		node = node[(select(i, ...))]
	end
	return node
end

-- Call fn(value) immediately (if loaded) and whenever that top-level key changes.
function State.Watch(key: string, fn: (any) -> ()): () -> ()
	watchers[key] = watchers[key] or {}
	table.insert(watchers[key], fn)
	if data then
		task.spawn(fn, data[key])
	end
	return function()
		local list = watchers[key]
		local i = list and table.find(list, fn)
		if i then
			table.remove(list, i)
		end
	end
end

-- Wait until the first snapshot arrives.
function State.Wait(): any
	while not data do
		State.Loaded:Wait()
	end
	return data
end

local function notify(key: string, path: { any })
	for _, fn in ipairs(watchers[key] or {}) do
		task.spawn(fn, data[key])
	end
	State.Changed:Fire(path)
end

local function apply(path: { any }, value: any)
	local node = data
	for i = 1, #path - 1 do
		local k = path[i]
		if type(node[k]) ~= "table" then
			node[k] = {}
		end
		node = node[k]
	end
	node[path[#path]] = value
end

function State.Init()
	Net.On("Sync", function(payload)
		if type(payload) ~= "table" then
			return
		end
		if payload.Full then
			data = payload.Full
			State.ReadOnly = payload.ReadOnly == true
			State.Loaded:Fire()
			for key in watchers do
				notify(key, { key })
			end
			return
		end
		if not data or type(payload.Patches) ~= "table" then
			return
		end
		local touched: { [string]: { any } } = {}
		for _, patch in payload.Patches do
			local path, value = patch[1], patch[2]
			if type(path) == "table" and #path > 0 then
				apply(path, value)
				touched[tostring(path[1])] = path
			end
		end
		for key, path in touched do
			notify(key, path)
		end
	end)
end

return State

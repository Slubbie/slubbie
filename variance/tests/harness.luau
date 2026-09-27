--# selene: allow(global_usage, unused_variable)
-- Headless test harness for VARIANCE's pure modules.
--
-- Emulates just enough of Roblox's instance-based `require(script.Parent.X)` to
-- load ModuleScripts straight from the Rojo source tree, plus the handful of
-- globals the pure core touches (task.spawn/delay are stubbed synchronously).
--
-- Run with any Luau runtime that provides __readfile/__compile, e.g. the
-- `luaurun` helper described in tests/README.md:
--   luaurun tests/run.luau

local Harness = {}

local SRC = "src/shared"

local function exists(path: string): boolean
	return __readfile(path) ~= nil
end

-- A fake Instance standing for a file or folder in the source tree.
local nodeCache = {}
local function node(path: string, name: string, parent: any?)
	local key = path
	if nodeCache[key] then
		return nodeCache[key]
	end
	local proxy = setmetatable({}, {
		__index = function(self, childName)
			if childName == "Name" then
				return name
			elseif childName == "Parent" then
				return parent
			elseif childName == "__path" then
				return path
			elseif childName == "FindFirstChild" or childName == "WaitForChild" then
				return function(_, n)
					return self[n]
				end
			end
			local dir = path
			local filePath = dir .. "/" .. childName .. ".luau"
			local initPath = dir .. "/" .. childName .. "/init.luau"
			if exists(filePath) then
				return node(filePath, childName, self)
			elseif exists(initPath) then
				return node(dir .. "/" .. childName, childName, self)
			end
			-- Folder without init: still addressable.
			return node(dir .. "/" .. childName, childName, self)
		end,
		__tostring = function()
			return "Instance(" .. path .. ")"
		end,
	})
	nodeCache[key] = proxy
	return proxy
end

local moduleCache = {}
local requireInstance

local function modulePathOf(inst): string
	local path = inst.__path
	if string.sub(path, -5) == ".luau" then
		return path, string.match(path, "^(.*)/[^/]+$")
	end
	return path .. "/init.luau", path
end

requireInstance = function(inst)
	if type(inst) ~= "table" then
		error("harness require expects a fake instance, got " .. typeof(inst), 2)
	end
	local filePath, dirPath = modulePathOf(inst)
	if moduleCache[filePath] ~= nil then
		return moduleCache[filePath]
	end
	local source = __readfile(filePath)
	if source == nil then
		error("module not found: " .. filePath, 2)
	end
	-- `script` inside a module is the module itself; its Parent is the folder.
	local scriptInstance = inst
	if string.sub(inst.__path, -5) ~= ".luau" then
		-- init.luau: the folder is the script; children are relative to the folder.
		scriptInstance = node(dirPath, inst.Name, inst.Parent)
	end
	local env = setmetatable({ script = scriptInstance, require = requireInstance }, { __index = _G })
	local fn = __compile(source, "@" .. filePath, env)
	local result = fn()
	moduleCache[filePath] = result
	return result
end

-- Globals the core may touch.
_G.task = {
	spawn = function(fn, ...)
		if type(fn) == "thread" then
			return coroutine.resume(fn, ...)
		end
		return fn(...)
	end,
	defer = function(fn, ...)
		return fn(...)
	end,
	delay = function(_t, fn, ...)
		return nil
	end,
	wait = function()
		return 0
	end,
	cancel = function() end,
}
_G.warn = function(...)
	print("[warn]", ...)
end
_G.typeof = function(v)
	return type(v)
end

local root = node(SRC, "Variance", nil)
Harness.Shared = root

function Harness.require(relative: string)
	local current = root
	for part in string.gmatch(relative, "[^/%.]+") do
		current = current[part]
	end
	return requireInstance(current)
end

-- Tiny assertion + reporting framework.
local results = { passed = 0, failed = 0, failures = {} }
Harness.results = results

function Harness.test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		results.passed += 1
	else
		results.failed += 1
		table.insert(results.failures, name .. ": " .. tostring(err))
		print("FAIL  " .. name .. "\n      " .. tostring(err))
	end
end

function Harness.eq(actual, expected, message: string?)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", message or "eq", tostring(expected), tostring(actual)), 2)
	end
end

function Harness.near(actual: number, expected: number, eps: number?, message: string?)
	if math.abs(actual - expected) > (eps or 1e-9) then
		error(string.format("%s: expected %.6f, got %.6f", message or "near", expected, actual), 2)
	end
end

function Harness.truthy(value, message: string?)
	if not value then
		error(message or "expected truthy value", 2)
	end
end

function Harness.report(): boolean
	print(string.format("\n%d passed, %d failed", results.passed, results.failed))
	return results.failed == 0
end

return Harness

-- A tiny test framework: suites, cases, assertions and a summary.

local T = {}

local results = { Passed = 0, Failed = 0, Failures = {} }
local currentSuite = ""

function T.Suite(name: string)
	currentSuite = name
	print(`\n▸ {name}`)
end

function T.Case(name: string, fn: () -> ())
	local ok, err = xpcall(fn, function(message)
		return debug.traceback(tostring(message), 2)
	end)
	if ok then
		results.Passed += 1
		print(`  ✓ {name}`)
	else
		results.Failed += 1
		table.insert(results.Failures, `{currentSuite} › {name}\n{err}`)
		print(`  ✗ {name}\n      {(tostring(err):gsub("\n", "\n      "))}`)
	end
end

local function describe(value: any): string
	if type(value) == "string" then
		return `"{value}"`
	end
	return tostring(value)
end

function T.Equal(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(`{label or "values differ"}: expected {describe(expected)}, got {describe(actual)}`, 2)
	end
end

function T.Near(actual: number, expected: number, tolerance: number, label: string?)
	if math.abs(actual - expected) > tolerance then
		error(`{label or "numbers differ"}: expected {expected} ± {tolerance}, got {actual}`, 2)
	end
end

function T.True(value: any, label: string?)
	if not value then
		error(label or "expected a truthy value", 2)
	end
end

function T.False(value: any, label: string?)
	if value then
		error(label or "expected a falsy value", 2)
	end
end

function T.DeepEqual(a: any, b: any, label: string?, path: string?)
	path = path or "value"
	if type(a) ~= type(b) then
		error(`{label or "tables differ"} at {path}: {describe(a)} vs {describe(b)}`, 2)
	end
	if type(a) ~= "table" then
		if a ~= b then
			error(`{label or "tables differ"} at {path}: {describe(a)} vs {describe(b)}`, 2)
		end
		return
	end
	for key, value in a do
		T.DeepEqual(value, b[key], label, `{path}.{tostring(key)}`)
	end
	for key in b do
		if a[key] == nil then
			error(`{label or "tables differ"} at {path}.{tostring(key)}: missing on the left`, 2)
		end
	end
end

function T.Results()
	return results
end

return T

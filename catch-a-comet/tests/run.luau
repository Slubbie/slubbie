-- Runs every spec in tests/specs. From the project root:
--   lune run tests/run.luau            (all specs)
--   lune run tests/run.luau capture    (specs whose file name contains "capture")

local fs = require("@lune/fs")
local process = require("@lune/process")

local T = require("./harness/T")

local filter = process.args[1]
local files = fs.readDir("tests/specs")
table.sort(files)
for _, file in files do
	if file:match("%.spec%.luau$") and (not filter or file:find(filter, 1, true)) then
		local spec = require(`./specs/{file:gsub("%.luau$", "")}`)
		local ok, err = pcall(spec)
		if not ok then
			print(`\n✗ {file} crashed: {err}`)
			T.Results().Failed += 1
		end
	end
end

local results = T.Results()
print(`\n{results.Passed} passed, {results.Failed} failed`)
if results.Failed > 0 then
	process.exit(1)
end
process.exit(0)

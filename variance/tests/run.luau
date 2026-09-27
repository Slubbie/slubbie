--# selene: allow(global_usage, unused_variable)
-- Entry point: runs every *.spec.luau suite (and optionally the AI simulation).
--   luaurun tests/run.luau            unit + fuzz tests
--   luaurun tests/run.luau sim        also runs the AI-vs-AI balance simulation

local harnessSource = __readfile("tests/harness.luau")
local H = __compile(harnessSource, "@tests/harness.luau", _G)()

local suites = { "tests/core.spec.luau", "tests/fuzz.spec.luau", "tests/ai.spec.luau", "tests/meta.spec.luau" }
for _, path in suites do
	local source = __readfile(path)
	if source then
		local started = __clock()
		print("== " .. path)
		local suite = __compile(source, "@" .. path, _G)()
		suite(H)
		print(string.format("   (%.2fs)", __clock() - started))
	end
end

if arg[1] == "sim" then
	local source = __readfile("tests/simulate.luau")
	__compile(source, "@tests/simulate.luau", _G)()(H, arg)
end

if not H.report() then
	error("tests failed")
end

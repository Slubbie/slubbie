-- Minimal test helpers for tests/run.py.

local T = { passed = 0, failed = 0 }

function T.test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		T.passed += 1
		print("  ok   " .. name)
	else
		T.failed += 1
		print("  FAIL " .. name .. "\n       " .. tostring(err))
	end
end

function T.eq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", label or "value", tostring(expected), tostring(actual)), 2)
	end
end

function T.near(actual: number, expected: number, tolerance: number, label: string?)
	if math.abs(actual - expected) > tolerance then
		error(string.format("%s: expected %.5f ± %.5f, got %.5f", label or "value", expected, tolerance, actual), 2)
	end
end

function T.truthy(value: any, label: string?)
	if not value then
		error((label or "value") .. " should be truthy", 2)
	end
end

-- Deterministic RNG with the same interface as Roblox's Random (xorshift-style LCG).
function T.Rng(seed: number)
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	local rng = {}
	function rng:NextNumber(): number
		state = (state * 48271) % 2147483647
		return (state - 1) / 2147483646
	end
	function rng:NextInteger(min: number, max: number): number
		return min + math.floor(self:NextNumber() * (max - min + 1))
	end
	return rng
end

function T.Finish()
	print(string.format("\n%d passed, %d failed", T.passed, T.failed))
	if T.failed > 0 then
		error("tests failed")
	end
end

return T

--!strict
-- Background loops for services. Each loop runs in its own thread and keeps
-- going if one iteration errors. Tests set Loop.Disabled so they can drive
-- time by hand instead of waiting on real loops.

local Loop = {}

Loop.Disabled = false

function Loop.Every(seconds: number, name: string, fn: () -> ())
	if Loop.Disabled then
		return
	end
	task.spawn(function()
		while true do
			task.wait(seconds)
			local ok, err = pcall(function()
				fn()
			end)
			if not ok then
				warn(`[Loop] {name} failed: {err}`)
			end
		end
	end)
end

return Loop

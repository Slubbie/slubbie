-- Tweening helpers with the game's easing vocabulary.
--   snap     quick mechanical settle (buttons, toggles)
--   slide    panels and banners entering
--   settle   heavy things landing (integrity, banners)
--   linger   slow fades

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local Motion = {}

Motion.Styles = {
	snap = { Enum.EasingStyle.Quint, Enum.EasingDirection.Out },
	slide = { Enum.EasingStyle.Quart, Enum.EasingDirection.Out },
	settle = { Enum.EasingStyle.Back, Enum.EasingDirection.Out },
	linger = { Enum.EasingStyle.Sine, Enum.EasingDirection.InOut },
	accel = { Enum.EasingStyle.Quad, Enum.EasingDirection.In },
	linear = { Enum.EasingStyle.Linear, Enum.EasingDirection.InOut },
}

function Motion.tween(instance: Instance, duration: number, props: { [string]: any }, style: string?): Tween
	local s = Motion.Styles[style or "slide"] or Motion.Styles.slide
	local tween = TweenService:Create(instance, TweenInfo.new(Theme.duration(duration), s[1], s[2]), props)
	tween:Play()
	return tween
end

-- Tweens and yields until done.
function Motion.await(instance: Instance, duration: number, props: { [string]: any }, style: string?)
	local tween = Motion.tween(instance, duration, props, style)
	if tween.PlaybackState ~= Enum.PlaybackState.Completed then
		tween.Completed:Wait()
	end
end

-- Brief scale punch on a GuiObject (adds a UIScale if needed).
function Motion.punch(gui: GuiObject, amount: number?, duration: number?)
	if Theme.ReducedMotion then
		return
	end
	local scale = gui:FindFirstChild("PunchScale") :: UIScale?
	if scale == nil then
		scale = Instance.new("UIScale")
		scale.Name = "PunchScale"
		scale.Parent = gui
	end
	local s = scale :: UIScale
	s.Scale = 1 + (amount or 0.08)
	Motion.tween(s, duration or 0.25, { Scale = 1 }, "settle")
end

-- Horizontal shake of a GuiObject (damage, errors).
function Motion.shake(gui: GuiObject, strength: number?, duration: number?)
	if Theme.ReducedMotion then
		return
	end
	local origin = gui:GetAttribute("ShakeOrigin")
	if typeof(origin) ~= "UDim2" then
		origin = gui.Position
		gui:SetAttribute("ShakeOrigin", origin)
	end
	local base = origin :: UDim2
	local s = strength or 8
	local d = duration or 0.3
	task.spawn(function()
		local started = os.clock()
		while os.clock() - started < d do
			local k = 1 - (os.clock() - started) / d
			gui.Position = base + UDim2.fromOffset((math.random() * 2 - 1) * s * k, 0)
			task.wait(1 / 60)
		end
		gui.Position = base
	end)
end

-- Counts a TextLabel up from one number to another.
function Motion.count(label: TextLabel, from: number, to: number, duration: number, format: ((number) -> string)?)
	local fmt = format or function(n)
		return tostring(math.floor(n + 0.5))
	end
	task.spawn(function()
		local started = os.clock()
		local d = Theme.duration(duration)
		while os.clock() - started < d do
			local t = (os.clock() - started) / d
			local eased = 1 - (1 - t) ^ 3
			label.Text = fmt(from + (to - from) * eased)
			task.wait(1 / 30)
		end
		label.Text = fmt(to)
	end)
end

-- Critically damped spring step (for per-frame smoothing).
function Motion.damp(current: number, target: number, speed: number, dt: number): number
	return target + (current - target) * math.exp(-speed * dt)
end

return Motion

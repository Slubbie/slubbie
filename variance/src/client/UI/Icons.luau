-- Icons drawn from frames (no image assets). Each instrument has a distinct
-- silhouette so it reads at 32px and without colour.
--   Icons.instrument(id, parent, size) -> Frame
--   Icons.symbol(name, parent, size)   -> Frame   (gear, lock, target, self, ...)

local Theme = require(script.Parent.Theme)

local Icons = {}

local function frame(parent: Instance, props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	for k, v in props do
		if k ~= "Color" and k ~= "Round" and k ~= "Stroke" then
			(f :: any)[k] = v
		end
	end
	if props.Color then
		Theme.bind(f, "BackgroundColor3", props.Color)
	end
	if props.Round then
		local c = Instance.new("UICorner")
		c.CornerRadius = props.Round == true and UDim.new(1, 0) or UDim.new(0, props.Round)
		c.Parent = f
	end
	if props.Stroke then
		f.BackgroundTransparency = 1
		local s = Instance.new("UIStroke")
		s.Thickness = props.Stroke
		Theme.bind(s, "Color", props.Color or "Text")
		s.Parent = f
	end
	f.Parent = parent
	return f
end

-- Shorthand: box at (x, y) centre with (w, h) as fractions of the icon.
local function box(p, x, y, w, h, color, extra)
	local props = {
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromScale(w, h),
		Color = color or "Text",
	}
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return frame(p, props)
end

local builders: { [string]: (Frame) -> () } = {
	Lens = function(p)
		box(p, 0.42, 0.42, 0.5, 0.5, "Text", { Stroke = 3, Round = true })
		box(p, 0.42, 0.42, 0.3, 0.3, "Hollow", { Round = true, BackgroundTransparency = 0.6 })
		box(p, 0.74, 0.74, 0.12, 0.34, "Text", { Rotation = -45, Round = 2 })
	end,
	Ejector = function(p)
		box(p, 0.5, 0.66, 0.66, 0.28, "Text", { Round = 2 })
		box(p, 0.5, 0.4, 0.12, 0.3, "Accent")
		box(p, 0.5, 0.2, 0.28, 0.28, "Accent", { Rotation = 45 })
	end,
	Suture = function(p)
		box(p, 0.5, 0.5, 0.7, 0.5, "Text", { Round = 3 })
		box(p, 0.5, 0.5, 0.36, 0.1, "Hollow")
		box(p, 0.5, 0.5, 0.1, 0.32, "Hollow")
	end,
	Capacitor = function(p)
		box(p, 0.5, 0.2, 0.66, 0.1, "Text")
		box(p, 0.5, 0.8, 0.66, 0.1, "Text")
		box(p, 0.5, 0.5, 0.3, 0.44, "Accent", { Round = 3 })
	end,
	Clamp = function(p)
		box(p, 0.3, 0.5, 0.36, 0.36, "Text", { Stroke = 3, Round = true })
		box(p, 0.7, 0.5, 0.36, 0.36, "Text", { Stroke = 3, Round = true })
		box(p, 0.5, 0.5, 0.2, 0.08, "Text")
	end,
	Inverter = function(p)
		box(p, 0.3, 0.5, 0.28, 0.28, "Charged", { Rotation = 45 })
		box(p, 0.7, 0.5, 0.3, 0.3, "Hollow", { Stroke = 3, Round = true })
		box(p, 0.5, 0.18, 0.5, 0.07, "Accent")
		box(p, 0.5, 0.82, 0.5, 0.07, "Accent")
	end,
	Sonar = function(p)
		box(p, 0.5, 0.5, 0.2, 0.2, "Accent", { Round = true })
		box(p, 0.5, 0.5, 0.5, 0.5, "Text", { Stroke = 2, Round = true })
		box(p, 0.5, 0.5, 0.82, 0.82, "Faint", { Stroke = 2, Round = true })
	end,
	Dampener = function(p)
		box(p, 0.5, 0.42, 0.56, 0.5, "Text", { Round = 3 })
		box(p, 0.5, 0.72, 0.38, 0.38, "Text", { Rotation = 45 })
		box(p, 0.5, 0.48, 0.3, 0.08, "Hollow")
	end,
	Rotor = function(p)
		box(p, 0.5, 0.5, 0.72, 0.72, "Text", { Stroke = 3, Round = true })
		for i = 0, 2 do
			local a = i * math.pi * 2 / 3 - math.pi / 2
			box(p, 0.5 + math.cos(a) * 0.2, 0.5 + math.sin(a) * 0.2, 0.14, 0.14, "Accent", { Round = true })
		end
	end,
	Overclock = function(p)
		box(p, 0.5, 0.56, 0.7, 0.7, "Text", { Stroke = 3, Round = true })
		box(p, 0.58, 0.46, 0.06, 0.32, "Charged", { Rotation = 40 })
		box(p, 0.5, 0.14, 0.2, 0.08, "Text")
	end,
	Serum = function(p)
		box(p, 0.5, 0.56, 0.34, 0.62, "Text", { Stroke = 2, Round = 4 })
		box(p, 0.5, 0.66, 0.26, 0.36, "Good", { Round = 3 })
		box(p, 0.5, 0.18, 0.4, 0.1, "Text")
	end,
	PowerTap = function(p)
		box(p, 0.5, 0.58, 0.5, 0.4, "Text", { Round = 3 })
		box(p, 0.38, 0.26, 0.08, 0.24, "Text")
		box(p, 0.62, 0.26, 0.08, 0.24, "Text")
		box(p, 0.5, 0.86, 0.1, 0.2, "Accent")
	end,
	Tether = function(p)
		box(p, 0.24, 0.5, 0.3, 0.3, "Text", { Stroke = 3, Round = true })
		box(p, 0.76, 0.5, 0.3, 0.3, "Text", { Stroke = 3, Round = true })
		box(p, 0.5, 0.5, 0.36, 0.08, "Accent")
	end,
	Scrambler = function(p)
		box(p, 0.5, 0.5, 0.62, 0.62, "Text", { Stroke = 3, Round = 2 })
		box(p, 0.5, 0.5, 0.7, 0.07, "Charged", { Rotation = 35 })
		box(p, 0.5, 0.5, 0.7, 0.07, "Accent", { Rotation = -35 })
	end,
}

local symbols: { [string]: (Frame) -> () } = {
	Gear = function(p)
		box(p, 0.5, 0.5, 0.56, 0.56, "Text", { Stroke = 3, Round = true })
		for i = 0, 3 do
			box(p, 0.5, 0.5, 0.86, 0.12, "Text", { Rotation = i * 45 })
		end
		box(p, 0.5, 0.5, 0.36, 0.36, "Panel", { Round = true })
	end,
	Lock = function(p)
		box(p, 0.5, 0.64, 0.6, 0.44, "Dim", { Round = 3 })
		box(p, 0.5, 0.34, 0.4, 0.4, "Dim", { Stroke = 3, Round = true })
	end,
	Target = function(p)
		box(p, 0.5, 0.5, 0.74, 0.74, "Text", { Stroke = 2, Round = true })
		box(p, 0.5, 0.5, 0.2, 0.2, "Charged", { Round = true })
		box(p, 0.5, 0.5, 0.06, 0.96, "Text")
		box(p, 0.5, 0.5, 0.96, 0.06, "Text")
	end,
	Self = function(p)
		box(p, 0.5, 0.34, 0.32, 0.32, "Text", { Round = true })
		box(p, 0.5, 0.78, 0.6, 0.34, "Text", { Round = 6 })
	end,
	Trophy = function(p)
		box(p, 0.5, 0.36, 0.52, 0.44, "Accent", { Round = 4 })
		box(p, 0.5, 0.7, 0.12, 0.24, "Accent")
		box(p, 0.5, 0.86, 0.44, 0.1, "Accent")
	end,
	Archive = function(p)
		box(p, 0.5, 0.52, 0.64, 0.72, "Text", { Stroke = 2, Round = 2 })
		for i = 0, 2 do
			box(p, 0.5, 0.36 + i * 0.16, 0.4, 0.06, "Dim")
		end
	end,
	Play = function(p)
		box(p, 0.5, 0.5, 0.5, 0.5, "Accent", { Rotation = 45, Round = 2 })
	end,
	Close = function(p)
		box(p, 0.5, 0.5, 0.8, 0.1, "Text", { Rotation = 45 })
		box(p, 0.5, 0.5, 0.8, 0.1, "Text", { Rotation = -45 })
	end,
	Eye = function(p)
		box(p, 0.5, 0.5, 0.86, 0.46, "Text", { Stroke = 2, Round = true })
		box(p, 0.5, 0.5, 0.26, 0.26, "Text", { Round = true })
	end,
	Warning = function(p)
		box(p, 0.5, 0.5, 0.64, 0.64, "Warn", { Rotation = 45, Round = 3 })
		box(p, 0.5, 0.44, 0.08, 0.28, "Bg")
		box(p, 0.5, 0.68, 0.08, 0.08, "Bg")
	end,
}

local function container(parent: Instance?, size: number): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Icon"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(size, size)
	holder.Parent = parent
	return holder
end

function Icons.instrument(id: string, parent: Instance?, size: number): Frame
	local holder = container(parent, size)
	local builder = builders[id]
	if builder then
		builder(holder)
	else
		box(holder, 0.5, 0.5, 0.6, 0.6, "Dim", { Stroke = 2 })
	end
	return holder
end

function Icons.symbol(name: string, parent: Instance?, size: number): Frame
	local holder = container(parent, size)
	local builder = symbols[name]
	if builder then
		builder(holder)
	end
	return holder
end

return Icons

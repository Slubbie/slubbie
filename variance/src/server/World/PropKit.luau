-- Reusable set dressing for arenas and the lobby. Every function builds into
-- `parent` at CFrame `at` and tags anything the client animates with an "Fx"
-- attribute (see client/Controllers/EnvironmentController.luau):
--   Flicker   lights that stutter as tension rises       (PointLight/SpotLight inside)
--   Key       the main table light (never fully dims)
--   Warning   rotating beacons that switch on at match point
--   Monitor   screens whose text the client drives (SurfaceGui "Screen")
--   Spin      fans / rotors (attribute Speed, Axis)
--   Camera    CCTV heads that can turn toward subjects (attribute Pivot)
--   Silhouette figures behind glass that can move during ambient events
--   Vent      particle emitters for ventilation events
--   Speaker   positional source for announcements

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(ReplicatedStorage.Variance.Visual.Build)

local PropKit = {}

local DARK = Color3.fromRGB(30, 31, 34)
local STEEL = Color3.fromRGB(120, 122, 124)

-- Caged industrial lamp hanging from `at` (the ceiling mount).
function PropKit.cageLamp(parent: Instance, at: CFrame, color: Color3, brightness: number, range: number, key: boolean?)
	local model = Build.model("CageLamp", parent)
	Build.cylinder(model, 2.2, 0.12, at * CFrame.new(0, -1.1, 0) * CFrame.Angles(0, 0, math.pi / 2), DARK, "Metal", "Cord")
	local shade = Build.cylinder(model, 0.6, 1.6, at * CFrame.new(0, -2.4, 0) * CFrame.Angles(0, 0, math.pi / 2), STEEL, "Metal", "Shade")
	local bulb = Build.ball(model, 0.6, at * CFrame.new(0, -2.8, 0), color, "Neon", "Bulb")
	bulb.CastShadow = false
	for i = 0, 3 do
		local a = i * math.pi / 2
		Build.box(model, Vector3.new(0.06, 0.7, 0.06), at * CFrame.new(math.cos(a) * 0.45, -2.95, math.sin(a) * 0.45), DARK, "Metal", "Cage")
	end
	local light = Build.spotLight(bulb, color, brightness, range, 70, Enum.NormalId.Bottom, true)
	light.Name = "Light"
	Build.fx(bulb, key and "Key" or "Flicker", { BaseBrightness = brightness })
	return model, shade
end

-- A straight pipe between two points, with flanges.
function PropKit.pipe(parent: Instance, a: Vector3, b: Vector3, diameter: number, color: Color3)
	local length = (b - a).Magnitude
	local mid = (a + b) / 2
	local cf = CFrame.lookAt(mid, b) * CFrame.Angles(0, math.pi / 2, 0)
	Build.cylinder(parent, length, diameter, cf, color, "Metal", "Pipe")
	for _, p in { a, b } do
		Build.cylinder(parent, 0.2, diameter + 0.25, CFrame.lookAt(p, mid) * CFrame.Angles(0, math.pi / 2, 0), STEEL, "Metal", "Flange")
	end
end

-- Wall-mounted CCTV camera that can pan (client rotates "Head" around its mount).
function PropKit.cctv(parent: Instance, at: CFrame)
	local model = Build.model("CCTV", parent)
	Build.box(model, Vector3.new(0.3, 0.3, 0.6), at * CFrame.new(0, 0, 0.3), DARK, "Metal", "Arm")
	local head = Build.box(model, Vector3.new(0.5, 0.45, 1.1), at * CFrame.new(0, -0.3, -0.35), Color3.fromRGB(200, 200, 196), "SmoothPlastic", "Head")
	local lens = Build.cylinder(model, 0.12, 0.34, at * CFrame.new(0, -0.3, -0.92) * CFrame.Angles(0, math.pi / 2, 0), DARK, "Glass", "Lens")
	lens.Parent = model
	local led = Build.ball(model, 0.1, at * CFrame.new(0.18, -0.12, -0.9), Color3.fromRGB(255, 40, 40), "Neon", "Led")
	led.CastShadow = false
	Build.fx(model, "Camera", { Pivot = at })
	head:SetAttribute("Rest", at:ToObjectSpace(head.CFrame))
	lens:SetAttribute("Rest", at:ToObjectSpace(lens.CFrame))
	led:SetAttribute("Rest", at:ToObjectSpace(led.CFrame))
	return model
end

-- A CRT-style monitor whose "Screen" SurfaceGui the client drives.
function PropKit.monitor(parent: Instance, at: CFrame, size: Vector3?, text: string?, color: Color3?)
	local s = size or Vector3.new(2.2, 1.7, 1.6)
	local model = Build.model("Monitor", parent)
	Build.box(model, s, at, Color3.fromRGB(44, 44, 42), "SmoothPlastic", "Casing")
	local screen = Build.box(model, Vector3.new(s.X * 0.82, s.Y * 0.74, 0.05), at * CFrame.new(0, 0.02, -s.Z / 2 - 0.02), Color3.fromRGB(8, 14, 12), "Glass", "Screen")
	local label = Build.label(screen, Enum.NormalId.Front, text or "EVALUATION IN PROGRESS", color or Color3.fromRGB(140, 255, 170), {
		PixelsPerStud = 60,
		Font = Enum.Font.Code,
	})
	label.Parent.Name = "Screen"
	Build.fx(screen, "Monitor")
	local glow = Build.pointLight(screen, color or Color3.fromRGB(140, 255, 170), 0.6, 6, false)
	glow.Name = "Glow"
	return model
end

-- A stack of monitors (broadcast walls, control desks).
function PropKit.monitorStack(parent: Instance, at: CFrame, cols: number, rows: number, color: Color3?)
	for r = 0, rows - 1 do
		for c = 0, cols - 1 do
			local x = (c - (cols - 1) / 2) * 2.35
			PropKit.monitor(parent, at * CFrame.new(x, 0.9 + r * 1.8, 0), nil, nil, color)
		end
	end
end

-- Ceiling / wall fan that spins (client-driven).
function PropKit.fan(parent: Instance, at: CFrame, diameter: number, speed: number)
	local model = Build.model("Fan", parent)
	Build.cylinder(model, 0.3, diameter + 0.4, at * CFrame.Angles(0, math.pi / 2, 0), DARK, "Metal", "Housing")
	local hub = Build.cylinder(model, 0.35, 0.5, at * CFrame.Angles(0, math.pi / 2, 0), STEEL, "Metal", "Hub")
	for i = 0, 3 do
		local blade = Build.box(model, Vector3.new(0.35, diameter * 0.45, 0.08), at * CFrame.Angles(0, 0, i * math.pi / 2) * CFrame.new(0, diameter * 0.24, 0) * CFrame.Angles(0, 0.4, 0), STEEL, "Metal", "Blade")
		blade:SetAttribute("Rest", at:ToObjectSpace(blade.CFrame))
	end
	hub:SetAttribute("Rest", at:ToObjectSpace(hub.CFrame))
	Build.fx(model, "Spin", { Speed = speed, Pivot = at })
	return model
end

-- Rotating warning beacon (off until the client switches it on).
function PropKit.beacon(parent: Instance, at: CFrame, color: Color3)
	local model = Build.model("Beacon", parent)
	Build.cylinder(model, 0.3, 0.8, at * CFrame.new(0, 0.15, 0) * CFrame.Angles(0, 0, math.pi / 2), DARK, "Metal", "Base")
	local dome = Build.ball(model, 0.7, at * CFrame.new(0, 0.5, 0), color, "Glass", "Dome")
	dome.Transparency = 0.3
	dome.CastShadow = false
	local light = Build.spotLight(dome, color, 0, 26, 40, Enum.NormalId.Front, false)
	light.Name = "Light"
	Build.fx(dome, "Warning", { Color = color })
	return model
end

-- A figure standing behind glass (observers, board members).
function PropKit.silhouette(parent: Instance, at: CFrame, color: Color3?)
	local model = Build.model("Silhouette", parent)
	local c = color or Color3.fromRGB(8, 8, 10)
	local torso = Build.box(model, Vector3.new(1.9, 2.1, 0.9), at * CFrame.new(0, 3.1, 0), c, "SmoothPlastic", "Torso")
	Build.ball(model, 1.25, at * CFrame.new(0, 4.75, 0), c, "SmoothPlastic", "Head")
	Build.box(model, Vector3.new(0.8, 2.0, 0.8), at * CFrame.new(-0.5, 1.0, 0), c, "SmoothPlastic", "LegL")
	Build.box(model, Vector3.new(0.8, 2.0, 0.8), at * CFrame.new(0.5, 1.0, 0), c, "SmoothPlastic", "LegR")
	Build.box(model, Vector3.new(0.7, 2.0, 0.7), at * CFrame.new(-1.3, 3.0, 0), c, "SmoothPlastic", "ArmL")
	Build.box(model, Vector3.new(0.7, 2.0, 0.7), at * CFrame.new(1.3, 3.0, 0), c, "SmoothPlastic", "ArmR")
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			d.CastShadow = false
			d:SetAttribute("Rest", at:ToObjectSpace(d.CFrame))
		end
	end
	Build.fx(model, "Silhouette", { Pivot = at })
	torso.Name = "Torso"
	return model
end

-- A pane of glass with a frame (observation windows, two-way mirrors).
function PropKit.window(parent: Instance, at: CFrame, size: Vector2, frameColor: Color3, tint: Color3, transparency: number)
	local model = Build.model("Window", parent)
	local glass = Build.box(model, Vector3.new(size.X, size.Y, 0.15), at, tint, "Glass", "Glass")
	glass.Transparency = transparency
	glass.CastShadow = false
	local t = 0.3
	Build.box(model, Vector3.new(size.X + t * 2, t, 0.4), at * CFrame.new(0, size.Y / 2 + t / 2, 0), frameColor, "Metal", "Frame")
	Build.box(model, Vector3.new(size.X + t * 2, t, 0.4), at * CFrame.new(0, -size.Y / 2 - t / 2, 0), frameColor, "Metal", "Frame")
	Build.box(model, Vector3.new(t, size.Y, 0.4), at * CFrame.new(size.X / 2 + t / 2, 0, 0), frameColor, "Metal", "Frame")
	Build.box(model, Vector3.new(t, size.Y, 0.4), at * CFrame.new(-size.X / 2 - t / 2, 0, 0), frameColor, "Metal", "Frame")
	return model
end

function PropKit.crate(parent: Instance, at: CFrame, size: Vector3, color: Color3)
	local model = Build.model("Crate", parent)
	Build.solid(model, size, at, color, "WoodPlanks", "Body")
	local trim = Color3.new(color.R * 0.6, color.G * 0.6, color.B * 0.6)
	Build.box(model, Vector3.new(size.X + 0.05, 0.25, size.Z + 0.05), at * CFrame.new(0, size.Y / 2 - 0.3, 0), trim, "WoodPlanks", "Band")
	Build.box(model, Vector3.new(size.X + 0.05, 0.25, size.Z + 0.05), at * CFrame.new(0, -size.Y / 2 + 0.3, 0), trim, "WoodPlanks", "Band")
	return model
end

-- Server rack with blinking LEDs (client blinks parts tagged "Blink").
function PropKit.serverRack(parent: Instance, at: CFrame, ledColor: Color3)
	local model = Build.model("ServerRack", parent)
	Build.solid(model, Vector3.new(2.4, 7, 2), at * CFrame.new(0, 3.5, 0), Color3.fromRGB(26, 28, 30), "Metal", "Cabinet")
	for i = 1, 10 do
		local y = 0.8 + i * 0.58
		Build.box(model, Vector3.new(2.1, 0.42, 0.05), at * CFrame.new(0, y, -1.02), Color3.fromRGB(40, 42, 46), "Metal", "Unit")
		for j = 1, 3 do
			local led = Build.box(model, Vector3.new(0.08, 0.08, 0.04), at * CFrame.new(0.55 + j * 0.16, y, -1.06), ledColor, "Neon", "Led")
			led.CastShadow = false
			Build.fx(led, "Blink", { Rate = 0.6 + ((i * 7 + j * 3) % 10) / 6 })
		end
	end
	return model
end

-- Glass specimen tank with a glowing liquid.
function PropKit.tank(parent: Instance, at: CFrame, height: number, color: Color3)
	local model = Build.model("Tank", parent)
	Build.column(model, 0.6, 3.2, at * CFrame.new(0, 0.3, 0), DARK, "Metal", "Base")
	local glass = Build.column(model, height, 2.8, at * CFrame.new(0, 0.6 + height / 2, 0), Color3.fromRGB(170, 210, 220), "Glass", "Glass")
	glass.Transparency = 0.7
	glass.CastShadow = false
	local fluid = Build.column(model, height * 0.8, 2.5, at * CFrame.new(0, 0.6 + height * 0.4, 0), color, "Neon", "Fluid")
	fluid.Transparency = 0.55
	fluid.CastShadow = false
	Build.column(model, 0.5, 3.2, at * CFrame.new(0, 0.85 + height, 0), DARK, "Metal", "Cap")
	local light = Build.pointLight(fluid, color, 0.8, 10, false)
	light.Name = "Light"
	Build.fx(fluid, "Flicker", { BaseBrightness = 0.8, Soft = true })
	return model
end

-- Wall speaker (announcements play from here).
function PropKit.speaker(parent: Instance, at: CFrame)
	local model = Build.model("Speaker", parent)
	local box = Build.box(model, Vector3.new(1.2, 0.9, 0.6), at, Color3.fromRGB(56, 58, 58), "Metal", "Box")
	Build.box(model, Vector3.new(1.0, 0.7, 0.05), at * CFrame.new(0, 0, -0.32), Color3.fromRGB(20, 20, 22), "Fabric", "Grille")
	Build.fx(box, "Speaker")
	return model
end

-- Ventilation grate with a (disabled) mist emitter for ventilation events.
function PropKit.vent(parent: Instance, at: CFrame, size: Vector2)
	local model = Build.model("Vent", parent)
	local frame = Build.box(model, Vector3.new(size.X, size.Y, 0.3), at, Color3.fromRGB(70, 72, 74), "Metal", "Frame")
	for i = 1, 5 do
		local y = (i - 3) * size.Y / 6
		Build.box(model, Vector3.new(size.X * 0.9, 0.08, 0.35), at * CFrame.new(0, y, -0.02) * CFrame.Angles(0.5, 0, 0), Color3.fromRGB(40, 42, 44), "Metal", "Slat")
	end
	local attachment = Build.attachment(frame, "Emit", CFrame.new(0, 0, -0.3))
	local mist = Instance.new("ParticleEmitter")
	mist.Name = "Mist"
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Rate = 0
	mist.Enabled = false
	mist.Lifetime = NumberRange.new(2, 3.5)
	mist.Speed = NumberRange.new(2, 4)
	mist.SpreadAngle = Vector2.new(25, 25)
	mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 5) })
	mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.75), NumberSequenceKeypoint.new(1, 1) })
	mist.Color = ColorSequence.new(Color3.fromRGB(200, 205, 210))
	mist.LightInfluence = 0.6
	mist.EmissionDirection = Enum.NormalId.Front
	mist.Parent = attachment
	Build.fx(frame, "Vent")
	return model
end

-- Poster / sign plate with text.
function PropKit.sign(parent: Instance, at: CFrame, size: Vector2, text: string, bg: Color3, fg: Color3, font: Enum.Font?)
	local plate = Build.box(parent, Vector3.new(size.X, size.Y, 0.08), at, bg, "SmoothPlastic", "Sign")
	Build.label(plate, Enum.NormalId.Front, text, fg, { Font = font or Enum.Font.Michroma, PixelsPerStud = 50, LightInfluence = 0.8, Brightness = 1 })
	return plate
end

-- Hazard-striped floor band (alternating wedge-free stripes).
function PropKit.hazardBand(parent: Instance, at: CFrame, length: number, width: number, a: Color3, b: Color3)
	local count = math.floor(length / 1.2)
	for i = 0, count - 1 do
		local x = (i - (count - 1) / 2) * 1.2
		Build.box(parent, Vector3.new(1.2, 0.02, width), at * CFrame.new(x, 0, 0), (i % 2 == 0) and a or b, "SmoothPlastic", "Stripe")
	end
end

-- Stage light on a stand or truss (spot aimed at `target`).
function PropKit.stageLight(parent: Instance, at: Vector3, target: Vector3, color: Color3, brightness: number, flicker: boolean?)
	local model = Build.model("StageLight", parent)
	local cf = CFrame.lookAt(at, target)
	local can = Build.cylinder(model, 1.3, 0.9, cf * CFrame.Angles(0, math.pi / 2, 0), DARK, "Metal", "Can")
	local lens = Build.cylinder(model, 0.1, 0.8, cf * CFrame.new(0, 0, -0.66) * CFrame.Angles(0, math.pi / 2, 0), color, "Neon", "Lens")
	lens.CastShadow = false
	local light = Build.spotLight(lens, color, brightness, 60, 30, Enum.NormalId.Right, true)
	light.Name = "Light"
	-- A cylinder's +X is its Right face; we rotated so +X points along the beam.
	Build.fx(lens, flicker and "Flicker" or "Key", { BaseBrightness = brightness })
	return model, can
end

return PropKit

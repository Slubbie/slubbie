-- STUDIO 9 ("DEAD AIR"): an abandoned broadcast studio.
-- Lighting trusses, two pedestal cameras that turn by themselves, empty
-- audience bleachers (spectator space), an ON AIR sign and a dead monitor wall.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(ReplicatedStorage.Variance.Visual.Build)
local PropKit = require(script.Parent.Parent.PropKit)

local Dresser = {}

local function truss(m: Instance, a: CFrame, length: number, color: Color3)
	local model = Build.model("Truss", m)
	for _, off in { Vector3.new(0, 0.5, 0.5), Vector3.new(0, -0.5, 0.5), Vector3.new(0, 0.5, -0.5), Vector3.new(0, -0.5, -0.5) } do
		Build.cylinder(model, length, 0.16, a * CFrame.new(off), color, "Metal", "Chord")
	end
	local steps = math.floor(length / 1.2)
	for i = 0, steps do
		local x = -length / 2 + i * (length / steps)
		Build.box(model, Vector3.new(0.08, 1.0, 0.08), a * CFrame.new(x, 0, 0.5), color, "Metal", "Rung")
		Build.box(model, Vector3.new(0.08, 1.0, 0.08), a * CFrame.new(x, 0, -0.5), color, "Metal", "Rung")
		Build.box(model, Vector3.new(0.08, 0.08, 1.0), a * CFrame.new(x, 0.5, 0), color, "Metal", "Rung")
	end
	return model
end

local function pedestalCamera(m: Instance, at: CFrame)
	local model = Build.model("StudioCamera", m)
	Build.column(model, 0.4, 3, at * CFrame.new(0, 0.2, 0), Color3.fromRGB(30, 30, 32), "Metal", "Base")
	Build.column(model, 3.6, 0.5, at * CFrame.new(0, 2.2, 0), Color3.fromRGB(60, 60, 64), "Metal", "Column")
	local pivot = at * CFrame.new(0, 4.3, 0)
	local body = Build.box(model, Vector3.new(1.2, 1.3, 2.6), pivot, Color3.fromRGB(46, 46, 50), "SmoothPlastic", "Head")
	local lens = Build.cylinder(model, 1.0, 0.9, pivot * CFrame.new(0, 0, -1.7) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(20, 20, 22), "Glass", "Lens")
	local tally = Build.box(model, Vector3.new(0.3, 0.2, 0.1), pivot * CFrame.new(0, 0.75, -1.1), Color3.fromRGB(255, 40, 40), "Neon", "Led")
	tally.CastShadow = false
	for _, p in { body, lens, tally } do
		p:SetAttribute("Rest", pivot:ToObjectSpace(p.CFrame))
	end
	Build.fx(model, "Camera", { Pivot = pivot })
	return model
end

function Dresser.dress(ctx)
	local m = ctx.Model
	local c = ctx.Colors
	local at = ctx.at
	local centre = at(0, 2.5, 0).Position

	-- Curtains: vertical folds along the north and south walls.
	for _, z in { -23.3, 23.3 } do
		for i = -11, 11 do
			Build.box(m, Vector3.new(1.9, 17.5, 0.6), at(i * 2.05, 8.75, z + (i % 2 == 0 and 0.2 or -0.2) * math.sign(z)), Color3.fromRGB(28, 14, 18), "Fabric", "Curtain")
		end
	end
	-- Stage platform and a glowing edge.
	Build.solid(m, Vector3.new(22, 0.4, 22), at(0, 0.2, 0), Color3.fromRGB(26, 24, 26), "WoodPlanks", "Stage")
	for _, spec in {
		{ Vector3.new(22, 0.08, 0.15), at(0, 0.42, 11) },
		{ Vector3.new(22, 0.08, 0.15), at(0, 0.42, -11) },
		{ Vector3.new(0.15, 0.08, 22), at(11, 0.42, 0) },
		{ Vector3.new(0.15, 0.08, 22), at(-11, 0.42, 0) },
	} do
		Build.neon(m, spec[1], spec[2], c.Accent, "StageEdge")
	end

	-- Two lighting trusses with stage lights aimed at the table.
	truss(m, at(0, 15.5, -8), 36, Color3.fromRGB(70, 70, 74))
	truss(m, at(0, 15.5, 8), 36, Color3.fromRGB(70, 70, 74))
	for i, x in { -12, -4, 4, 12 } do
		PropKit.stageLight(m, at(x, 14.6, -8).Position, centre, i % 2 == 0 and Color3.fromRGB(255, 240, 225) or Color3.fromRGB(255, 120, 130), 1.4, true)
		PropKit.stageLight(m, at(x, 14.6, 8).Position, centre, i % 2 == 1 and Color3.fromRGB(255, 240, 225) or Color3.fromRGB(150, 170, 255), 1.4, true)
	end

	-- Pedestal cameras.
	pedestalCamera(m, at(10, 0, 14, CFrame.Angles(0, math.rad(35), 0)))
	pedestalCamera(m, at(-12, 0, -13, CFrame.Angles(0, math.rad(215), 0)))

	-- Audience bleachers on the east side (spectator space).
	for tier = 0, 4 do
		local x = 15 + tier * 1.8
		local y = 0.6 + tier * 1.1
		Build.solid(m, Vector3.new(1.8, 1.2, 30), at(x, y - 0.6 + 0.6, 0), Color3.fromRGB(40, 36, 40), "Wood", "Bleacher")
		for s = -6, 6 do
			Build.box(m, Vector3.new(1.2, 0.4, 1.6), at(x, y + 0.8, s * 2.2), Color3.fromRGB(90, 24, 30), "Fabric", "Cushion")
		end
	end
	for i, spec in { { 16.8, 2.2, -6 }, { 18.6, 3.3, 3 }, { 20.4, 4.4, -2 }, { 16.8, 2.2, 8 } } do
		local s = PropKit.silhouette(m, at(spec[1], spec[2], spec[3], CFrame.Angles(0, math.pi / 2, 0)), Color3.fromRGB(10, 9, 12))
		s.Name = "Audience" .. i
	end

	-- ON AIR sign and applause sign over the curtain.
	local onAir = PropKit.sign(m, at(0, 13.5, -22.8, CFrame.Angles(0, math.pi, 0)), Vector2.new(6, 1.6), "ON AIR", Color3.fromRGB(60, 8, 8), Color3.fromRGB(255, 70, 60), Enum.Font.Michroma)
	onAir.Material = Enum.Material.Neon
	Build.fx(onAir, "Warning", { Color = Color3.fromRGB(255, 60, 50) })
	local applause = PropKit.sign(m, at(16, 11, -22.8, CFrame.Angles(0, math.pi, 0)), Vector2.new(5, 1.2), "APPLAUSE", Color3.fromRGB(30, 30, 30), Color3.fromRGB(230, 220, 200), Enum.Font.Michroma)
	Build.fx(applause, "Flicker", { BaseBrightness = 0 })
	PropKit.sign(m, at(-14, 13.5, -22.8, CFrame.Angles(0, math.pi, 0)), Vector2.new(6, 1.4), "STUDIO 9", Color3.fromRGB(20, 20, 24), Color3.fromRGB(230, 220, 200))

	-- Monitor wall behind the north curtain line.
	PropKit.monitorStack(m, at(-12, 1.5, -21, CFrame.Angles(0, 0, 0)) * CFrame.Angles(0, math.pi, 0), 3, 2, Color3.fromRGB(200, 210, 255))
	-- Director's desk and a clapperboard.
	Build.box(m, Vector3.new(6, 2.6, 2.4), at(-16, 1.3, 16), Color3.fromRGB(40, 40, 44), "Wood", "Desk")
	PropKit.monitor(m, at(-16, 3.5, 16), Vector3.new(1.8, 1.3, 1.2), "SIGNAL LOST", Color3.fromRGB(200, 210, 255))
	Build.box(m, Vector3.new(1.4, 1.0, 0.1), at(-18, 2.7, 15.4, CFrame.Angles(0, 0, 0.1)), Color3.fromRGB(20, 20, 20), "SmoothPlastic", "Clapper")

	PropKit.cctv(m, at(-22.5, 15, 22.5, CFrame.Angles(0, math.rad(-45), 0) * CFrame.Angles(math.rad(-25), 0, 0)))
	PropKit.speaker(m, at(22.8, 13, 0, CFrame.Angles(0, math.pi / 2, 0)))
	PropKit.speaker(m, at(-22.8, 13, 0, CFrame.Angles(0, -math.pi / 2, 0)))
	PropKit.vent(m, at(0, 17.6, 18, CFrame.Angles(-math.pi / 2, 0, 0)), Vector2.new(4, 2))
	PropKit.beacon(m, at(22.8, 15, -18, CFrame.Angles(0, 0, math.pi / 2)), Color3.fromRGB(255, 50, 60))
	-- Cable snakes across the floor.
	for i = 0, 5 do
		PropKit.pipe(m, at(-20 + i * 2, 0.12, -14 + i).Position, at(-8 + i, 0.12, -6 - i).Position, 0.16, Color3.fromRGB(18, 18, 20))
	end
end

return Dresser

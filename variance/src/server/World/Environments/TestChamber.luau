-- TEST CHAMBER 04 ("THE CRUCIBLE"): a sealed industrial test chamber.
-- Blast door, hazard paint, pipes, one caged lamp over the table, a high
-- observation booth where the Observers sit (spectator space), a wall fan,
-- ceiling vents, CCTV and warning beacons.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(ReplicatedStorage.Variance.Visual.Build)
local PropKit = require(script.Parent.Parent.PropKit)

local Dresser = {}

function Dresser.dress(ctx)
	local m = ctx.Model
	local c = ctx.Colors
	local at = ctx.at
	local yellow = c.Trim
	local black = Color3.fromRGB(24, 24, 24)

	-- Hazard band framing the table area.
	for _, spec in
		{
			{ at(0, 0.01, 9.5), 20 },
			{ at(0, 0.01, -9.5), 20 },
			{ at(9.5, 0.01, 0, CFrame.Angles(0, math.pi / 2, 0)), 20 },
			{ at(-9.5, 0.01, 0, CFrame.Angles(0, math.pi / 2, 0)), 20 },
		}
	do
		PropKit.hazardBand(m, spec[1], spec[2], 0.9, yellow, black)
	end
	-- Floor drain and bolted plates.
	Build.cylinder(
		m,
		0.05,
		1.6,
		at(6, 0.02, -6) * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(30, 30, 30),
		"DiamondPlate",
		"Drain"
	)
	for i = -2, 2 do
		Build.box(
			m,
			Vector3.new(3.8, 0.05, 3.8),
			at(i * 4.2, 0.02, 15),
			Color3.fromRGB(58, 58, 56),
			"DiamondPlate",
			"Plate"
		)
	end

	-- Blast door on the north wall.
	local door = at(0, 5.5, -23.3)
	Build.box(m, Vector3.new(11, 11, 0.8), door, Color3.fromRGB(78, 80, 78), "DiamondPlate", "BlastDoor")
	Build.box(m, Vector3.new(11.6, 0.6, 1), door * CFrame.new(0, 5.7, 0), yellow, "Metal", "DoorFrame")
	Build.box(m, Vector3.new(0.6, 11.6, 1), door * CFrame.new(-5.8, 0, 0), yellow, "Metal", "DoorFrame")
	Build.box(m, Vector3.new(0.6, 11.6, 1), door * CFrame.new(5.8, 0, 0), yellow, "Metal", "DoorFrame")
	Build.cylinder(
		m,
		0.3,
		3.2,
		door * CFrame.new(0, 0, 0.5) * CFrame.Angles(0, math.pi / 2, 0),
		Color3.fromRGB(150, 40, 30),
		"Metal",
		"Wheel"
	)
	for i = 0, 3 do
		Build.box(
			m,
			Vector3.new(3.0, 0.2, 0.2),
			door * CFrame.new(0, 0, 0.62) * CFrame.Angles(0, 0, i * math.pi / 4),
			Color3.fromRGB(150, 40, 30),
			"Metal",
			"Spoke"
		)
	end
	PropKit.sign(
		m,
		door * CFrame.new(0, 3.6, 0.45) * CFrame.Angles(0, math.pi, 0),
		Vector2.new(5.5, 1.2),
		"TEST CHAMBER 04",
		black,
		yellow
	)
	PropKit.sign(
		m,
		at(-14, 7, -23.4, CFrame.Angles(0, math.pi, 0)),
		Vector2.new(6, 1.4),
		"KEEP BOTH HANDS ON THE TABLE",
		Color3.fromRGB(200, 200, 196),
		black
	)

	-- Pipe runs along the east and west walls.
	for i, y in { 13, 14.6, 16 } do
		local d = 0.6 + i * 0.12
		PropKit.pipe(m, at(23, y, -22).Position, at(23, y, 22).Position, d, Color3.fromRGB(96 + i * 10, 90, 80))
		PropKit.pipe(
			m,
			at(-23, y + 0.4, -22).Position,
			at(-23, y + 0.4, 22).Position,
			d * 0.8,
			Color3.fromRGB(80, 90, 96)
		)
	end
	PropKit.pipe(m, at(22.6, 13, 14).Position, at(22.6, 0.2, 14).Position, 0.9, Color3.fromRGB(110, 90, 70))

	-- The single caged lamp (the key light itself is the arena's KeyMount).
	PropKit.cageLamp(m, at(0, 18, 0), Color3.fromRGB(255, 220, 170), 1.2, 16, false)
	PropKit.cageLamp(m, at(-15, 18, 12), Color3.fromRGB(255, 210, 150), 1.4, 20, false)
	PropKit.cageLamp(m, at(15, 18, -12), Color3.fromRGB(255, 210, 150), 1.4, 20, false)

	-- Observation booth high on the west wall (spectator space).
	ctx.cut("W", 0, 11.5, 14, 4)
	local booth = at(-24.5, 11.5, 0, CFrame.Angles(0, math.pi / 2, 0))
	PropKit.window(m, booth, Vector2.new(14, 4), Color3.fromRGB(50, 52, 52), c.Glass, 0.35)
	Build.box(m, Vector3.new(16, 0.6, 3), at(-22.5, 9.2, 0), Color3.fromRGB(60, 62, 60), "Concrete", "BoothLedge")
	for i, z in { -4.5, 0, 4.5 } do
		local s = PropKit.silhouette(m, at(-26.5, 9.5, z, CFrame.Angles(0, -math.pi / 2, 0)))
		s.Name = "Observer" .. i
	end
	local boothLight =
		Build.part({ Name = "BoothLight", Size = Vector3.one, CFrame = at(-26, 13, 0), Transparency = 1, Parent = m })
	Build.pointLight(boothLight, Color3.fromRGB(90, 110, 120), 0.8, 14, false)
	-- The room behind the booth glass.
	Build.box(m, Vector3.new(0.5, 6, 16), at(-29, 11.5, 0), Color3.fromRGB(34, 36, 36), "Concrete", "BoothBack")
	Build.box(m, Vector3.new(6, 0.5, 16), at(-26, 8.6, 0), Color3.fromRGB(40, 40, 40), "Concrete", "BoothFloor")
	Build.box(m, Vector3.new(6, 0.5, 16), at(-26, 14.4, 0), Color3.fromRGB(30, 30, 30), "Concrete", "BoothRoof")

	-- Wall fan (east), vents, cameras, beacons, speaker.
	PropKit.fan(m, at(23.2, 8, -12, CFrame.Angles(0, -math.pi / 2, 0)), 4.5, 2.2)
	PropKit.vent(m, at(10, 17.6, 10, CFrame.Angles(-math.pi / 2, 0, 0)), Vector2.new(3, 3))
	PropKit.vent(m, at(-10, 17.6, -10, CFrame.Angles(-math.pi / 2, 0, 0)), Vector2.new(3, 3))
	PropKit.cctv(m, at(22.5, 15, 22.5, CFrame.Angles(0, math.rad(45), 0) * CFrame.Angles(math.rad(-25), 0, 0)))
	PropKit.cctv(m, at(-22.5, 15, -22.5, CFrame.Angles(0, math.rad(-135), 0) * CFrame.Angles(math.rad(-25), 0, 0)))
	PropKit.beacon(m, at(-7.5, 12.2, -23.2, CFrame.Angles(math.pi / 2, 0, 0)), Color3.fromRGB(255, 70, 40))
	PropKit.beacon(m, at(7.5, 12.2, -23.2, CFrame.Angles(math.pi / 2, 0, 0)), Color3.fromRGB(255, 70, 40))
	PropKit.speaker(m, at(0, 15.5, 23.2))

	-- Control console on the south wall.
	local console = at(12, 0, 21.5) -- local -Z faces into the room
	Build.box(
		m,
		Vector3.new(8, 3, 2.2),
		console * CFrame.new(0, 1.5, 0),
		Color3.fromRGB(64, 66, 64),
		"Metal",
		"Console"
	)
	PropKit.monitor(m, console * CFrame.new(-2, 4, 0.2), nil, "HARNESS NOMINAL", Color3.fromRGB(150, 255, 170))
	PropKit.monitor(m, console * CFrame.new(2, 4, 0.2), nil, "RECORDING", Color3.fromRGB(255, 190, 110))
	for i = 1, 6 do
		Build.box(
			m,
			Vector3.new(0.3, 0.1, 0.3),
			console * CFrame.new(-3 + i, 3.05, -0.4),
			i % 2 == 0 and yellow or Color3.fromRGB(200, 40, 30),
			"Neon",
			"Button"
		)
	end

	-- Stacked gas cylinders and cable coils for clutter.
	for i = 0, 3 do
		Build.column(
			m,
			4.5,
			1.1,
			at(-20 + i * 1.3, 2.25, 20),
			i % 2 == 0 and Color3.fromRGB(70, 110, 80) or Color3.fromRGB(150, 60, 50),
			"Metal",
			"GasCylinder"
		)
	end
	for i = 0, 2 do
		Build.cylinder(
			m,
			0.6,
			2.6 - i * 0.4,
			at(19, 0.3 + i * 0.6, -19) * CFrame.Angles(0, 0, math.pi / 2),
			Color3.fromRGB(30, 30, 32),
			"Rubber",
			"Coil"
		)
	end
end

return Dresser

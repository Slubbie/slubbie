-- SUBLEVEL C ("THE VAULT"): an underground research floor.
-- Server racks with blinking LEDs, glowing specimen tanks, a large terminal,
-- cable trays overhead and a catwalk above the west wall (spectator space).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(ReplicatedStorage.Variance.Visual.Build)
local PropKit = require(script.Parent.Parent.PropKit)

local Dresser = {}

function Dresser.dress(ctx)
	local m = ctx.Model
	local c = ctx.Colors
	local at = ctx.at
	local cyan = c.Accent

	-- Floor grating panels and neon trim lines.
	for x = -3, 3 do
		for z = -3, 3 do
			if math.abs(x) >= 2 or math.abs(z) >= 2 then
				Build.box(
					m,
					Vector3.new(5.8, 0.05, 5.8),
					at(x * 6.2, 0.03, z * 6.2),
					Color3.fromRGB(46, 52, 56),
					"DiamondPlate",
					"Grate"
				)
			end
		end
	end
	for _, z in { -23.3, 23.3 } do
		Build.neon(m, Vector3.new(46, 0.12, 0.12), at(0, 9, z), cyan, "Trim")
		Build.neon(m, Vector3.new(46, 0.12, 0.12), at(0, 3, z), cyan, "Trim")
	end

	-- Server racks along north and south walls.
	for i = -4, 4 do
		if math.abs(i) ~= 0 then
			PropKit.serverRack(m, at(i * 4.4, 0, -21.5, CFrame.Angles(0, math.pi, 0)), Color3.fromRGB(120, 255, 170))
			PropKit.serverRack(
				m,
				at(i * 4.4, 0, 21.5),
				i % 2 == 0 and Color3.fromRGB(255, 190, 90) or Color3.fromRGB(120, 200, 255)
			)
		end
	end

	-- Specimen tanks along the east wall.
	for i, z in { -10, 0, 10 } do
		PropKit.tank(m, at(19.5, 0, z), 7, i == 2 and Color3.fromRGB(120, 255, 190) or Color3.fromRGB(90, 200, 255))
	end
	-- Something indistinct floats in the middle tank.
	local shape = Build.ball(m, 1.6, at(19.5, 4.5, 0), Color3.fromRGB(30, 50, 55), "SmoothPlastic", "Specimen")
	shape.Size = Vector3.new(1.4, 2.4, 1.2)
	Build.fx(shape, "Silhouette", { Pivot = at(19.5, 4.5, 0), Drift = true })
	shape:SetAttribute("Rest", CFrame.identity)

	-- Main terminal on the north wall above the racks.
	-- Screens face local -Z; on the north wall that must point into the room (+Z).
	PropKit.monitor(
		m,
		at(0, 13, -23, CFrame.Angles(0, math.pi, 0)),
		Vector3.new(12, 5, 0.8),
		"SUBLEVEL C :: EVALUATION ARRAY",
		Color3.fromRGB(140, 220, 255)
	)

	-- Catwalk on the west side, with a rail (spectator space).
	Build.solid(m, Vector3.new(5, 0.4, 44), at(-21.3, 8.5, 0), Color3.fromRGB(60, 66, 70), "DiamondPlate", "Catwalk")
	for z = -21, 21, 3 do
		Build.box(m, Vector3.new(0.15, 1.8, 0.15), at(-18.9, 9.6, z), Color3.fromRGB(90, 96, 100), "Metal", "Post")
		Build.box(m, Vector3.new(0.4, 8.3, 0.4), at(-18.9, 4.2, z), Color3.fromRGB(50, 54, 58), "Metal", "Strut")
	end
	Build.box(m, Vector3.new(0.12, 0.12, 44), at(-18.9, 10.5, 0), Color3.fromRGB(110, 116, 120), "Metal", "Rail")
	Build.box(m, Vector3.new(0.1, 0.1, 44), at(-18.9, 9.8, 0), Color3.fromRGB(110, 116, 120), "Metal", "Rail")
	local watcher =
		PropKit.silhouette(m, at(-21.5, 8.7, 6, CFrame.Angles(0, -math.pi / 2, 0)), Color3.fromRGB(12, 14, 16))
	watcher.Name = "Watcher"

	-- Cable trays overhead with hanging cables.
	for _, x in { -8, 8 } do
		Build.box(m, Vector3.new(1.6, 0.3, 44), at(x, 16, 0), Color3.fromRGB(70, 76, 80), "Metal", "CableTray")
		for z = -20, 20, 5 do
			local drop = 1.5 + ((z + 20) % 7) * 0.4
			Build.cylinder(
				m,
				drop,
				0.14,
				at(x + 0.4, 16 - drop / 2, z) * CFrame.Angles(0, 0, math.pi / 2),
				Color3.fromRGB(20, 20, 24),
				"Rubber",
				"Cable"
			)
		end
	end
	PropKit.cageLamp(m, at(-12, 18, -8), Color3.fromRGB(200, 230, 255), 1.2, 18, false)
	PropKit.cageLamp(m, at(12, 18, 8), Color3.fromRGB(200, 230, 255), 1.2, 18, false)

	-- Lab bench with glassware.
	local bench = at(10, 0, -14)
	Build.box(
		m,
		Vector3.new(8, 3, 2.6),
		bench * CFrame.new(0, 1.5, 0),
		Color3.fromRGB(200, 204, 206),
		"SmoothPlastic",
		"Bench"
	)
	for i = 0, 4 do
		local flask = Build.column(
			m,
			0.9,
			0.5,
			bench * CFrame.new(-3 + i * 1.4, 3.45, 0),
			Color3.fromRGB(180, 230, 240),
			"Glass",
			"Flask"
		)
		flask.Transparency = 0.5
	end

	PropKit.cctv(m, at(22.5, 15, -22.5, CFrame.Angles(0, math.rad(135), 0) * CFrame.Angles(math.rad(-25), 0, 0)))
	PropKit.cctv(m, at(-22.5, 15, 22.5, CFrame.Angles(0, math.rad(-45), 0) * CFrame.Angles(math.rad(-25), 0, 0)))
	PropKit.vent(m, at(0, 17.6, -12, CFrame.Angles(-math.pi / 2, 0, 0)), Vector2.new(4, 4))
	PropKit.fan(m, at(0, 17.6, 12, CFrame.Angles(math.pi / 2, 0, 0)), 3.6, 3.5)
	PropKit.beacon(m, at(-22.8, 14, -12, CFrame.Angles(0, 0, -math.pi / 2)), Color3.fromRGB(255, 60, 60))
	PropKit.beacon(m, at(22.8, 14, 12, CFrame.Angles(0, 0, math.pi / 2)), Color3.fromRGB(255, 60, 60))
	PropKit.speaker(m, at(0, 15, 23))
	PropKit.sign(
		m,
		at(-10, 12, 23.3),
		Vector2.new(8, 1.2),
		"BIOHAZARD LEVEL 2 :: AUTHORISED ONLY",
		Color3.fromRGB(230, 230, 225),
		Color3.fromRGB(30, 30, 30)
	)
end

return Dresser

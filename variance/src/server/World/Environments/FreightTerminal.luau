-- CUSTOMS 77-C ("THE CONTAINER"): an interrogation room in a freight terminal.
-- One bare bulb, a two-way mirror with figures behind it (spectator space), a
-- rain-streaked window onto the container yard, chains, crates and a clock.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(ReplicatedStorage.Variance.Visual.Build)
local PropKit = require(script.Parent.Parent.PropKit)

local Dresser = {}

local function container(m: Instance, at: CFrame, color: Color3)
	local model = Build.model("ShippingContainer", m)
	Build.box(model, Vector3.new(8, 8.6, 20), at * CFrame.new(0, 4.3, 0), color, "CorrodedMetal", "Body")
	for i = -9, 9 do
		Build.box(
			model,
			Vector3.new(8.1, 8.2, 0.25),
			at * CFrame.new(0, 4.3, i),
			Color3.new(color.R * 0.8, color.G * 0.8, color.B * 0.8),
			"CorrodedMetal",
			"Rib"
		)
	end
	return model
end

function Dresser.dress(ctx)
	local m = ctx.Model
	local c = ctx.Colors
	local at = ctx.at

	-- Corrugated wall ribs.
	for i = -11, 11 do
		Build.box(
			m,
			Vector3.new(0.3, 17, 0.3),
			at(i * 2, 8.5, 23.6),
			Color3.fromRGB(80, 84, 80),
			"CorrodedMetal",
			"Rib"
		)
		Build.box(
			m,
			Vector3.new(0.3, 17, 0.3),
			at(23.6, 8.5, i * 2),
			Color3.fromRGB(80, 84, 80),
			"CorrodedMetal",
			"Rib"
		)
	end

	-- The bare bulb over the table.
	local cord = at(0, 18, 0)
	Build.cylinder(
		m,
		4.5,
		0.08,
		cord * CFrame.new(0, -2.25, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(20, 20, 20),
		"Rubber",
		"Cord"
	)
	local bulb = Build.ball(m, 0.7, cord * CFrame.new(0, -4.8, 0), Color3.fromRGB(255, 220, 160), "Neon", "Bulb")
	bulb.CastShadow = false
	local glow = Build.pointLight(bulb, Color3.fromRGB(255, 210, 150), 1.2, 16, true)
	glow.Name = "Light"
	Build.fx(bulb, "Flicker", { BaseBrightness = 1.2 })

	-- Two-way mirror on the east wall, with the observation room behind it.
	ctx.cut("E", 0, 7.5, 16, 7)
	local mirror = at(24.5, 7.5, 0, CFrame.Angles(0, -math.pi / 2, 0))
	PropKit.window(m, mirror, Vector2.new(16, 7), Color3.fromRGB(46, 48, 46), Color3.fromRGB(40, 44, 46), 0.25)
	Build.box(m, Vector3.new(10, 0.5, 20), at(30, -0.25, 0), Color3.fromRGB(30, 30, 30), "Concrete", "ObsFloor")
	Build.box(m, Vector3.new(10, 0.5, 20), at(30, 12, 0), Color3.fromRGB(26, 26, 26), "Concrete", "ObsRoof")
	Build.box(m, Vector3.new(0.5, 12, 20), at(35, 6, 0), Color3.fromRGB(34, 34, 34), "Concrete", "ObsBack")
	Build.box(m, Vector3.new(10, 12, 0.5), at(30, 6, 10), Color3.fromRGB(34, 34, 34), "Concrete", "ObsSide")
	Build.box(m, Vector3.new(10, 12, 0.5), at(30, 6, -10), Color3.fromRGB(34, 34, 34), "Concrete", "ObsSide")
	for i, z in { -5, 0.5, 5.5 } do
		local s =
			PropKit.silhouette(m, at(28 + (i % 2), 0, z, CFrame.Angles(0, math.pi / 2, 0)), Color3.fromRGB(6, 6, 7))
		s.Name = "Interrogator" .. i
	end
	local obsLight =
		Build.part({ Name = "ObsLight", Size = Vector3.one, CFrame = at(31, 10, 0), Transparency = 1, Parent = m })
	Build.pointLight(obsLight, Color3.fromRGB(60, 70, 90), 0.5, 14, false)

	-- Rain window on the north wall onto the container yard.
	ctx.cut("N", -8, 9, 14, 6)
	PropKit.window(
		m,
		at(-8, 9, -24.5),
		Vector2.new(14, 6),
		Color3.fromRGB(60, 60, 58),
		Color3.fromRGB(120, 140, 160),
		0.8
	)
	for i = -2, 2 do
		Build.box(m, Vector3.new(0.12, 6, 0.3), at(-8 + i * 3, 9, -24.4), Color3.fromRGB(60, 60, 58), "Metal", "Bar")
	end
	container(m, at(-14, 0, -40, CFrame.Angles(0, math.pi / 2, 0)), Color3.fromRGB(150, 60, 40))
	container(m, at(-2, 0, -38, CFrame.Angles(0, math.pi / 2, 0)), Color3.fromRGB(40, 80, 120))
	container(m, at(-8, 8.6, -39, CFrame.Angles(0, math.pi / 2, 0)), Color3.fromRGB(70, 100, 60))
	Build.box(m, Vector3.new(60, 0.5, 40), at(-8, -0.25, -44), Color3.fromRGB(34, 36, 38), "Asphalt", "Yard")
	local yardLight =
		Build.part({ Name = "YardLamp", Size = Vector3.one, CFrame = at(-2, 16, -32), Transparency = 1, Parent = m })
	Build.spotLight(yardLight, Color3.fromRGB(255, 180, 110), 1.5, 30, 70, Enum.NormalId.Bottom, false)
	-- Rain falls outside the window.
	local rainPart = Build.part({
		Name = "Rain",
		Size = Vector3.new(24, 1, 10),
		CFrame = at(-8, 17, -30),
		Transparency = 1,
		Parent = m,
	})
	local rain = Instance.new("ParticleEmitter")
	rain.Name = "Rain"
	rain.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	rain.Rate = 160
	rain.Lifetime = NumberRange.new(0.8, 1.1)
	rain.Speed = NumberRange.new(45, 55)
	rain.EmissionDirection = Enum.NormalId.Bottom
	rain.Size = NumberSequence.new(0.08)
	rain.Squash = NumberSequence.new(4)
	rain.Transparency = NumberSequence.new(0.55)
	rain.Color = ColorSequence.new(Color3.fromRGB(170, 190, 210))
	rain.LightInfluence = 1
	rain.Parent = rainPart
	Build.fx(rainPart, "Rain")

	-- Chains, crates, filing cabinet, clock.
	for _, x in { -18, -15 } do
		for i = 0, 10 do
			Build.cylinder(
				m,
				0.5,
				0.18,
				at(x, 17.5 - i * 0.55, 18) * CFrame.Angles(0, (i % 2) * math.pi / 2, math.pi / 2),
				Color3.fromRGB(90, 88, 84),
				"Metal",
				"Link"
			)
		end
	end
	PropKit.crate(m, at(18, 1.5, 18), Vector3.new(3, 3, 3), Color3.fromRGB(110, 80, 50))
	PropKit.crate(
		m,
		at(18, 4.25, 18.3, CFrame.Angles(0, 0.2, 0)),
		Vector3.new(2.5, 2.5, 2.5),
		Color3.fromRGB(96, 70, 44)
	)
	PropKit.crate(m, at(14.5, 1.25, 20), Vector3.new(2.5, 2.5, 2.5), Color3.fromRGB(120, 88, 54))
	local cabinet = at(-20, 0, 8, CFrame.Angles(0, -math.pi / 2, 0))
	Build.box(
		m,
		Vector3.new(2.2, 5.5, 2.4),
		cabinet * CFrame.new(0, 2.75, 0),
		Color3.fromRGB(80, 90, 84),
		"Metal",
		"Cabinet"
	)
	for i = 0, 3 do
		Build.box(
			m,
			Vector3.new(1.8, 1.1, 0.1),
			cabinet * CFrame.new(0, 0.8 + i * 1.3, -1.22),
			Color3.fromRGB(70, 80, 74),
			"Metal",
			"Drawer"
		)
	end
	local clock = at(0, 13, 23.4)
	Build.cylinder(
		m,
		0.2,
		2.2,
		clock * CFrame.Angles(0, math.pi / 2, 0),
		Color3.fromRGB(230, 226, 214),
		"SmoothPlastic",
		"ClockFace"
	)
	local hand = Build.box(
		m,
		Vector3.new(0.08, 0.9, 0.05),
		clock * CFrame.new(0, 0.35, -0.12),
		Color3.fromRGB(20, 20, 20),
		"SmoothPlastic",
		"ClockHand"
	)
	Build.fx(hand, "Spin", { Speed = 0.1, Pivot = clock * CFrame.new(0, 0, -0.12), Axis = "Z" })
	hand:SetAttribute("Rest", (clock * CFrame.new(0, 0, -0.12)):ToObjectSpace(hand.CFrame))

	PropKit.cctv(m, at(-22.5, 15, 22.5, CFrame.Angles(0, math.rad(-45), 0) * CFrame.Angles(math.rad(-25), 0, 0)))
	PropKit.speaker(m, at(-22.8, 14, -10, CFrame.Angles(0, -math.pi / 2, 0)))
	PropKit.vent(m, at(12, 17.6, -12, CFrame.Angles(-math.pi / 2, 0, 0)), Vector2.new(3, 3))
	PropKit.beacon(m, at(22.8, 15, 16, CFrame.Angles(0, 0, math.pi / 2)), Color3.fromRGB(255, 120, 40))
	PropKit.sign(m, at(12, 12, 23.4), Vector2.new(7, 1.2), "CUSTOMS HOLD 77-C", Color3.fromRGB(40, 40, 38), c.Accent)
end

return Dresser

-- Automation placeables: sprinklers, towers, rods, drones, bots and logistics.

local Kit = require(script.Parent.Kit)
local C = Kit.C

local A = {}

local SPRINKLER_TIER = {
	Color3.fromRGB(200, 120, 70),
	Color3.fromRGB(200, 205, 210),
	Color3.fromRGB(120, 220, 255),
}

A.Sprinkler = function(model, w, _d, h, params)
	local color = SPRINKLER_TIER[params.Tier or 1] or SPRINKLER_TIER[1]
	Kit.Cyl(model, 0.4, w * 0.45, CFrame.new(0, 0.2, 0), C.DarkMetal)
	Kit.Cyl(model, h * 0.6, 0.35, CFrame.new(0, h * 0.35, 0), color, { Material = Enum.Material.Metal })
	local head = Kit.Ball(
		model,
		Vector3.new(0.9, 0.5, 0.9),
		CFrame.new(0, h * 0.7, 0),
		color,
		{ Material = Enum.Material.Metal, Collide = false }
	)
	head.Name = "Head"
	head:SetAttribute("Anim", "Sprinkle")
	local spray = Kit.Particles(head, "Water", nil, 30)
	spray.Enabled = false
	if params.Tier == 3 then
		Kit.Light(head, Color3.fromRGB(140, 230, 255), 6, 0.5)
	end
end

A.MistTower = function(model, w, _d, h)
	Kit.Cyl(
		model,
		h * 0.9,
		w * 0.35,
		CFrame.new(0, h * 0.45, 0),
		Color3.fromRGB(220, 230, 240),
		{ Material = Enum.Material.Metal }
	)
	for i = 1, 3 do
		Kit.Cyl(
			model,
			0.25,
			w * 0.5,
			CFrame.new(0, i * h * 0.25, 0),
			Color3.fromRGB(120, 200, 240),
			{ Collide = false }
		)
	end
	local top = Kit.Ball(
		model,
		Vector3.new(1.4, 1.4, 1.4),
		CFrame.new(0, h, 0),
		Color3.fromRGB(170, 230, 255),
		{ Material = Enum.Material.Glass, Collide = false }
	)
	top.Name = "Head"
	local mist = Kit.Particles(top, "Smoke", Color3.fromRGB(220, 240, 255), 6)
	mist.Speed = NumberRange.new(1, 2)
	mist.Acceleration = Vector3.new(0, -0.4, 0)
end

A.WaterTower = function(model, w, d, h)
	for _, x in { -w * 0.35, w * 0.35 } do
		for _, z in { -d * 0.35, d * 0.35 } do
			Kit.Box(model, Vector3.new(0.5, h * 0.6, 0.5), CFrame.new(x, h * 0.3, z), C.DarkWood)
		end
	end
	local tank = Kit.Cyl(model, h * 0.35, w * 0.95, CFrame.new(0, h * 0.78, 0), C.Wood, { Mat = true })
	tank.Name = "Tank"
	Kit.Wedge(
		model,
		Vector3.new(w, h * 0.12, d * 0.5),
		CFrame.new(0, h * 1.01, -d * 0.25) * CFrame.Angles(0, math.rad(180), 0),
		C.DarkWood
	)
	Kit.Wedge(model, Vector3.new(w, h * 0.12, d * 0.5), CFrame.new(0, h * 1.01, d * 0.25), C.DarkWood)
end

A.Scarecrow = function(model, _w, _d, h, params)
	Kit.Box(model, Vector3.new(0.4, h * 0.9, 0.4), CFrame.new(0, h * 0.45, 0), C.DarkWood)
	Kit.Box(model, Vector3.new(h * 0.6, 0.35, 0.35), CFrame.new(0, h * 0.65, 0), C.DarkWood)
	Kit.Box(
		model,
		Vector3.new(1.6, 2.2, 1),
		CFrame.new(0, h * 0.62, 0),
		Color3.fromRGB(80, 110, 170),
		{ Paint = true, Collide = false }
	)
	Kit.Ball(model, Vector3.new(1.4, 1.4, 1.4), CFrame.new(0, h * 0.85, 0), C.Straw, { Collide = false })
	Kit.Cyl(model, 0.2, 2.6, CFrame.new(0, h * 0.95, 0), Color3.fromRGB(170, 120, 60), { Collide = false })
	Kit.Box(
		model,
		Vector3.new(1, 0.7, 1),
		CFrame.new(0, h * 1.02, 0),
		Color3.fromRGB(170, 120, 60),
		{ Collide = false }
	)
	for _, side in { -1, 1 } do
		Kit.Box(model, Vector3.new(0.5, 0.6, 0.5), CFrame.new(side * h * 0.3, h * 0.6, 0), C.Straw, { Collide = false })
	end
	if params.Fancy then
		Kit.Ball(
			model,
			Vector3.new(1.2, 1, 1.2),
			CFrame.new(0.9, h * 0.35, -0.5),
			Color3.fromRGB(240, 130, 30),
			{ Collide = false }
		)
		Kit.Box(
			model,
			Vector3.new(0.3, 0.3, 0.1),
			CFrame.new(0, h * 0.62, -0.55),
			Color3.fromRGB(200, 50, 50),
			{ Collide = false }
		)
	end
end

A.LightningRod = function(model, w, _d, h)
	Kit.Box(model, Vector3.new(w * 0.6, 1, w * 0.6), CFrame.new(0, 0.5, 0), C.Stone)
	Kit.Cyl(model, h * 0.95, 0.3, CFrame.new(0, h * 0.5, 0), C.Copper, { Material = Enum.Material.Metal })
	local tip = Kit.Ball(
		model,
		Vector3.new(0.7, 0.7, 0.7),
		CFrame.new(0, h, 0),
		C.Copper,
		{ Material = Enum.Material.Metal, Collide = false }
	)
	tip.Name = "Tip"
	local coil = Kit.Box(
		model,
		Vector3.new(0.8, 1.2, 0.8),
		CFrame.new(0, 1.6, 0),
		Color3.fromRGB(255, 240, 120),
		{ Material = Enum.Material.Neon, Collide = false }
	)
	coil:SetAttribute("Anim", "Glow")
end

A.HailNet = function(model, w, d, h)
	for _, x in { -w / 2 + 0.2, w / 2 - 0.2 } do
		for _, z in { -d / 2 + 0.2, d / 2 - 0.2 } do
			Kit.Box(model, Vector3.new(0.25, h, 0.25), CFrame.new(x, h / 2, z), C.DarkWood, { Collide = false })
		end
	end
	Kit.Box(
		model,
		Vector3.new(w, 0.1, d),
		CFrame.new(0, h, 0),
		C.White,
		{ Transparency = 0.5, Material = Enum.Material.Fabric, Collide = false }
	)
end

A.ShadeSail = function(model, w, d, h)
	for i, pos in { Vector3.new(-w / 2, 0, -d / 2), Vector3.new(w / 2, 0, -d / 2), Vector3.new(0, 0, d / 2) } do
		Kit.Box(
			model,
			Vector3.new(0.3, h - (i - 1) * 0.6, 0.3),
			CFrame.new(pos + Vector3.new(0, (h - (i - 1) * 0.6) / 2, 0)),
			C.Metal,
			{ Collide = false }
		)
	end
	Kit.Wedge(
		model,
		Vector3.new(w, 0.15, d),
		CFrame.new(0, h - 0.3, 0) * CFrame.Angles(math.rad(5), 0, 0),
		Color3.fromRGB(240, 180, 90),
		{ Paint = true, Material = Enum.Material.Fabric, Collide = false }
	)
end

A.Beacon = function(model, w, _d, h)
	Kit.Cyl(model, 1, w * 0.8, CFrame.new(0, 0.5, 0), Color3.fromRGB(60, 50, 110))
	for i = 1, 4 do
		local ring = Kit.Cyl(
			model,
			0.2,
			w * 0.7 - i * 0.1,
			CFrame.new(0, 1 + i * h * 0.18, 0),
			Color3.fromRGB(180, 160, 255),
			{ Material = Enum.Material.Neon, Collide = false }
		)
		ring:SetAttribute("Anim", "Float")
	end
	local star = Kit.Ball(
		model,
		Vector3.new(1.6, 1.6, 1.6),
		CFrame.new(0, h, 0),
		Color3.fromRGB(240, 230, 255),
		{ Material = Enum.Material.Neon, Collide = false }
	)
	star.Name = "Star"
	Kit.Light(star, Color3.fromRGB(190, 170, 255), 30, 1.5)
	Kit.Particles(star, "Sparkle", Color3.fromRGB(220, 210, 255), 8)
end

A.Windmill = function(model, w, d, h, params)
	local scale = if params.Small then 0.5 else 1
	local body = Kit.Cyl(model, h * 0.75, w * 0.6, CFrame.new(0, h * 0.375, 0), C.Cream, { Paint = true, Mat = true })
	body.Material = Enum.Material.Plaster
	Kit.Ball(model, Vector3.new(w * 0.65, h * 0.2, w * 0.65), CFrame.new(0, h * 0.75, 0), Color3.fromRGB(150, 70, 55))
	local hub = Kit.Cyl(
		model,
		0.8,
		1.2 * scale,
		CFrame.new(0, h * 0.72, -d * 0.35) * CFrame.Angles(math.rad(90), 0, 0),
		C.DarkWood,
		{ Collide = false }
	)
	hub.Name = "Hub"
	hub:SetAttribute("Anim", "Spinner")
	for i = 0, 3 do
		local blade = Kit.Box(
			model,
			Vector3.new(1.4 * scale, h * 0.42, 0.15),
			CFrame.new(0, h * 0.72, -d * 0.4) * CFrame.Angles(0, 0, i * math.pi / 2) * CFrame.new(0, h * 0.22, 0),
			C.White,
			{ Collide = false }
		)
		blade:SetAttribute("Anim", "SpinnerChild")
	end
	Kit.Box(model, Vector3.new(1.8 * scale, 3 * scale, 0.3), CFrame.new(0, 1.5 * scale, -w * 0.3), C.DarkWood)
end

A.Solar = function(model, w, d)
	for i = -1, 1 do
		Kit.Box(model, Vector3.new(0.3, 2, 0.3), CFrame.new(i * w * 0.35, 1, 0), C.Metal)
		local panel = Kit.Box(
			model,
			Vector3.new(w * 0.3, 0.15, d * 0.9),
			CFrame.new(i * w * 0.33, 2.3, 0) * CFrame.Angles(math.rad(25), 0, 0),
			Color3.fromRGB(40, 70, 140),
			{ Reflectance = 0.3 }
		)
		panel.Material = Enum.Material.Glass
	end
end

A.Feeder = function(model, w, _d, h)
	Kit.Box(model, Vector3.new(w * 0.8, h * 0.3, w * 0.8), CFrame.new(0, h * 0.15, 0), C.DarkMetal)
	Kit.Cyl(
		model,
		h * 0.6,
		w * 0.6,
		CFrame.new(0, h * 0.6, 0),
		Color3.fromRGB(230, 200, 90),
		{ Material = Enum.Material.Metal }
	)
	Kit.Box(model, Vector3.new(w * 0.9, 0.3, 0.8), CFrame.new(0, 0.5, -w * 0.45), C.Straw, { Collide = false })
end

A.Collector = function(model, w, _d, h)
	Kit.Box(model, Vector3.new(w * 0.8, h * 0.5, w * 0.8), CFrame.new(0, h * 0.25, 0), Color3.fromRGB(90, 160, 110))
	local arm = Kit.Box(model, Vector3.new(0.3, h * 0.5, 0.3), CFrame.new(0, h * 0.75, 0), C.Metal, { Collide = false })
	arm:SetAttribute("Anim", "Spinner")
	Kit.Box(
		model,
		Vector3.new(w * 0.7, 0.4, w * 0.5),
		CFrame.new(0, h * 0.55, 0),
		C.Wood,
		{ Collide = false, Name = "Basket" }
	)
end

A.DroneHub = function(model, w, d, h)
	Kit.Box(model, Vector3.new(w, 0.8, d), CFrame.new(0, 0.4, 0), C.DarkMetal)
	local pad = Kit.Cyl(model, 0.2, w * 0.8, CFrame.new(0, 0.9, 0), Color3.fromRGB(240, 200, 60), { Collide = false })
	pad.Name = "Pad"
	Kit.Box(model, Vector3.new(0.4, h, 0.4), CFrame.new(w / 2 - 0.5, h / 2, d / 2 - 0.5), C.Metal)
	local light = Kit.Ball(
		model,
		Vector3.new(0.6, 0.6, 0.6),
		CFrame.new(w / 2 - 0.5, h, d / 2 - 0.5),
		Color3.fromRGB(80, 255, 120),
		{ Material = Enum.Material.Neon, Collide = false }
	)
	light:SetAttribute("Anim", "Glow")
	-- The drone itself (animated by the client when working).
	local drone = Kit.Box(
		model,
		Vector3.new(1.6, 0.4, 1.6),
		CFrame.new(0, 1.4, 0),
		Color3.fromRGB(220, 225, 230),
		{ Collide = false, Name = "Drone" }
	)
	drone:SetAttribute("Anim", "Drone")
	for _, x in { -0.9, 0.9 } do
		for _, z in { -0.9, 0.9 } do
			Kit.Cyl(model, 0.08, 0.9, CFrame.new(x, 1.7, z), C.DarkMetal, { Collide = false, Name = "Rotor" })
				:SetAttribute("Anim", "DroneChild")
		end
	end
end

A.Farmbot = function(model, w, _d, h)
	local body = Kit.Box(
		model,
		Vector3.new(w * 0.7, h * 0.45, w * 0.7),
		CFrame.new(0, h * 0.4, 0),
		Color3.fromRGB(240, 240, 235),
		{ Paint = true }
	)
	body.Name = "Body"
	Kit.Ball(model, Vector3.new(w * 0.5, w * 0.5, w * 0.5), CFrame.new(0, h * 0.78, 0), Color3.fromRGB(240, 240, 235))
	for _, x in { -0.45, 0.45 } do
		local eye = Kit.Ball(
			model,
			Vector3.new(0.3, 0.3, 0.3),
			CFrame.new(x * w * 0.4, h * 0.82, -w * 0.22),
			Color3.fromRGB(80, 220, 255),
			{ Material = Enum.Material.Neon, Collide = false }
		)
		eye.Name = "Eye"
	end
	for _, x in { -1, 1 } do
		Kit.CylFlat(model, 0.4, 1.1, CFrame.new(x * w * 0.38, 0.55, 0), C.DarkMetal, "X")
	end
	Kit.Box(model, Vector3.new(0.2, h * 0.3, 0.2), CFrame.new(0, h * 1.05, 0), C.Metal, { Collide = false })
end

A.Hub = function(model, w, d, h)
	Kit.Box(
		model,
		Vector3.new(w * 0.9, h * 0.6, d * 0.9),
		CFrame.new(0, h * 0.3, 0),
		Color3.fromRGB(70, 80, 95),
		{ Paint = true }
	)
	local dish = Kit.Cyl(
		model,
		0.3,
		w * 0.8,
		CFrame.new(0, h * 0.8, 0) * CFrame.Angles(math.rad(30), 0, 0),
		C.Metal,
		{ Collide = false }
	)
	dish:SetAttribute("Anim", "Spinner")
	local screen = Kit.Box(
		model,
		Vector3.new(w * 0.5, h * 0.25, 0.1),
		CFrame.new(0, h * 0.35, -d * 0.46),
		Color3.fromRGB(90, 220, 170),
		{ Material = Enum.Material.Neon, Collide = false }
	)
	Kit.Light(screen, Color3.fromRGB(90, 220, 170), 8, 0.5)
end

A.Controller = function(model, w, _d, h)
	Kit.Box(model, Vector3.new(w * 0.7, h * 0.7, w * 0.5), CFrame.new(0, h * 0.35, 0), Color3.fromRGB(60, 60, 70))
	local screen = Kit.Box(
		model,
		Vector3.new(w * 0.6, h * 0.35, 0.1),
		CFrame.new(0, h * 0.8, -w * 0.1) * CFrame.Angles(math.rad(-20), 0, 0),
		Color3.fromRGB(80, 200, 255),
		{ Material = Enum.Material.Neon, Collide = false }
	)
	screen.Name = "Screen"
	Kit.Light(screen, Color3.fromRGB(100, 200, 255), 8, 0.6)
end

A.Conveyor = function(model, w, d)
	Kit.Box(model, Vector3.new(w * 0.95, 0.6, d * 0.7), CFrame.new(0, 0.3, 0), C.DarkMetal)
	local belt = Kit.Box(
		model,
		Vector3.new(w, 0.1, d * 0.6),
		CFrame.new(0, 0.65, 0),
		Color3.fromRGB(40, 40, 40),
		{ Collide = false, Name = "Belt" }
	)
	belt:SetAttribute("Anim", "Belt")
	for _, z in { -d * 0.36, d * 0.36 } do
		Kit.Box(
			model,
			Vector3.new(w, 0.4, 0.15),
			CFrame.new(0, 0.8, z),
			Color3.fromRGB(240, 200, 60),
			{ Collide = false }
		)
	end
end

return A

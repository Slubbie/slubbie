-- Builders for farm buildings, storage and utilities.
-- Signature: (model, w, d, h, params, def) with w/d in studs; pivot at ground centre.

local Kit = require(script.Parent.Kit)
local C = Kit.C

local B = {}

local function walls(
	model: Model,
	w: number,
	d: number,
	h: number,
	color: Color3,
	doorWidth: number?,
	doorColor: Color3?
)
	local t = 0.6
	Kit.Box(model, Vector3.new(w, h, t), CFrame.new(0, h / 2, d / 2 - t / 2), color, { Paint = true, Mat = true })
	Kit.Box(model, Vector3.new(t, h, d), CFrame.new(-w / 2 + t / 2, h / 2, 0), color, { Paint = true, Mat = true })
	Kit.Box(model, Vector3.new(t, h, d), CFrame.new(w / 2 - t / 2, h / 2, 0), color, { Paint = true, Mat = true })
	local door = doorWidth or math.min(6, w * 0.35)
	local side = (w - door) / 2
	Kit.Box(
		model,
		Vector3.new(side, h, t),
		CFrame.new(-w / 2 + side / 2, h / 2, -d / 2 + t / 2),
		color,
		{ Paint = true, Mat = true }
	)
	Kit.Box(
		model,
		Vector3.new(side, h, t),
		CFrame.new(w / 2 - side / 2, h / 2, -d / 2 + t / 2),
		color,
		{ Paint = true, Mat = true }
	)
	local lintel = h - 5.5
	if lintel > 0 then
		Kit.Box(
			model,
			Vector3.new(door, lintel, t),
			CFrame.new(0, h - lintel / 2, -d / 2 + t / 2),
			color,
			{ Paint = true, Mat = true }
		)
	end
	-- Open barn doors swung outward.
	local dc = doorColor or C.DarkWood
	Kit.Box(
		model,
		Vector3.new(0.3, 5.4, door / 2),
		CFrame.new(-door / 2 - 0.2, 2.7, -d / 2 - door / 4),
		dc,
		{ Collide = false }
	)
	Kit.Box(
		model,
		Vector3.new(0.3, 5.4, door / 2),
		CFrame.new(door / 2 + 0.2, 2.7, -d / 2 - door / 4),
		dc,
		{ Collide = false }
	)
	Kit.Box(model, Vector3.new(w, 0.3, d), CFrame.new(0, 0.15, 0), C.Plank, { Collide = true })
end

B.Coop = function(model, w, d, h, params)
	local wallH = h * 0.55
	walls(model, w, d, wallH, Color3.fromRGB(200, 70, 55), 4)
	Kit.Roof(model, w, d, wallH, h - wallH, C.DarkWood, 1)
	-- Ramp and nest boxes
	Kit.Wedge(
		model,
		Vector3.new(3, 1.2, 3),
		CFrame.new(0, 0.6, -d / 2 - 1.5) * CFrame.Angles(0, math.rad(180), 0),
		C.Plank
	)
	for i = -1, 1 do
		Kit.Box(model, Vector3.new(2, 1.5, 1.6), CFrame.new(i * 2.4, 1.2, d / 2 - 1.4), C.Straw, { Collide = false })
	end
	if params.Big then
		Kit.Box(model, Vector3.new(3, 2, 3), CFrame.new(w / 2 - 2.5, 1, d / 2 - 2.5), C.Metal, { Name = "Incubator" })
	end
	Kit.Box(model, Vector3.new(1.2, 1.2, 0.3), CFrame.new(0, wallH + (h - wallH) * 0.4, -d / 2 - 0.4), C.Cream)
end

B.Barn = function(model, w, d, h, params)
	local wallH = h * 0.5
	local color = if params.Storage then Color3.fromRGB(170, 120, 70) else Color3.fromRGB(175, 45, 40)
	walls(model, w, d, wallH, color, math.min(8, w * 0.4))
	Kit.Roof(model, w, d, wallH, h - wallH, Color3.fromRGB(80, 80, 85), 1.2)
	-- White trim X on the doors
	Kit.Box(
		model,
		Vector3.new(0.4, 5.5, 0.35),
		CFrame.new(-2.2, 2.8, -d / 2 - 0.1) * CFrame.Angles(0, 0, math.rad(35)),
		C.White,
		{ Collide = false }
	)
	Kit.Box(
		model,
		Vector3.new(0.4, 5.5, 0.35),
		CFrame.new(2.2, 2.8, -d / 2 - 0.1) * CFrame.Angles(0, 0, math.rad(-35)),
		C.White,
		{ Collide = false }
	)
	-- Hay loft window
	Kit.Box(model, Vector3.new(3, 2.2, 0.35), CFrame.new(0, wallH + 1.6, -d / 2 - 0.2), C.DarkWood)
	for i = 1, 3 do
		Kit.Box(
			model,
			Vector3.new(2.4, 1.6, 1.8),
			CFrame.new(-w / 2 + 2.2, 0.8 + (i - 1) * 1.6, d / 2 - 2 - (i % 2)),
			C.Straw,
			{ Collide = false }
		)
	end
	if params.Big then
		Kit.Box(model, Vector3.new(w * 0.35, 1.2, 0.3), CFrame.new(w * 0.3, 0.9, 0), C.Wood, { Name = "Pen" })
	end
end

B.Stable = function(model, w, d, h)
	local wallH = h * 0.6
	walls(model, w, d, wallH, Color3.fromRGB(140, 95, 60), w * 0.5)
	Kit.Roof(model, w, d, wallH, h - wallH, C.DarkWood, 1)
	Kit.Box(
		model,
		Vector3.new(0.3, wallH * 0.7, d * 0.8),
		CFrame.new(0, wallH * 0.35, 0),
		C.DarkWood,
		{ Name = "Divider" }
	)
	Kit.Box(model, Vector3.new(w * 0.8, 0.8, 1), CFrame.new(0, 2, d / 2 - 1.2), C.Wood, { Name = "Trough" })
end

B.Apiary = function(model, w, d)
	Kit.Box(model, Vector3.new(w, 0.3, d), CFrame.new(0, 0.15, 0), Color3.fromRGB(120, 170, 90), { Collide = false })
	for i = 0, 3 do
		local x = (i % 2 - 0.5) * w * 0.45
		local z = (math.floor(i / 2) - 0.5) * d * 0.45
		Kit.Box(model, Vector3.new(0.4, 0.8, 0.4), CFrame.new(x, 0.4, z), C.DarkWood)
		for level = 0, 2 do
			Kit.Box(
				model,
				Vector3.new(2.2, 0.9, 2.2),
				CFrame.new(x, 1.3 + level * 0.95, z),
				if level % 2 == 0 then C.Cream else Color3.fromRGB(245, 205, 90),
				{ Paint = level == 1 }
			)
		end
		Kit.Box(model, Vector3.new(2.6, 0.3, 2.6), CFrame.new(x, 4.15, z), C.DarkWood)
	end
	Kit.Particles(model.PrimaryPart :: BasePart, "Sparkle", Color3.fromRGB(255, 220, 80), 2)
end

B.Sanctuary = function(model, w, d, h)
	Kit.Cyl(model, 0.6, w, CFrame.new(0, 0.3, 0), C.Stone, { Mat = true })
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local pillar = Kit.Cyl(
			model,
			h * 0.7,
			1.2,
			CFrame.new(math.cos(a) * w * 0.42, h * 0.35, math.sin(a) * d * 0.42),
			C.Cream,
			{ Mat = true }
		)
		pillar.Material = Enum.Material.Marble
	end
	local dome = Kit.Ball(
		model,
		Vector3.new(w * 0.95, h * 0.55, d * 0.95),
		CFrame.new(0, h * 0.72, 0),
		Color3.fromRGB(170, 140, 240),
		{ Transparency = 0.45, Material = Enum.Material.Glass, Collide = false }
	)
	Kit.Light(dome, Color3.fromRGB(190, 160, 255), 30, 1.5)
	local orb = Kit.Ball(
		model,
		Vector3.new(2, 2, 2),
		CFrame.new(0, h * 0.95, 0),
		Color3.fromRGB(200, 180, 255),
		{ Material = Enum.Material.Neon, Collide = false }
	)
	Kit.Particles(orb, "Sparkle", Color3.fromRGB(210, 190, 255), 6)
end

B.Greenhouse = function(model, w, d, h, params)
	local glass = C.Glass
	-- Frame posts and ribs; walls are glass you can walk through (the floor is farmland).
	local frame = if params.Dome then Color3.fromRGB(240, 240, 245) else Color3.fromRGB(245, 245, 240)
	for _, x in { -w / 2, w / 2 } do
		for _, z in { -d / 2, d / 2 } do
			Kit.Box(model, Vector3.new(0.5, h * 0.6, 0.5), CFrame.new(x, h * 0.3, z), frame, { Paint = true })
		end
	end
	local wallH = h * 0.6
	for _, z in { -d / 2, d / 2 } do
		Kit.Box(
			model,
			Vector3.new(w, wallH, 0.2),
			CFrame.new(0, wallH / 2, z),
			glass,
			{ Transparency = 0.7, Material = Enum.Material.Glass, Collide = false }
		)
	end
	for _, x in { -w / 2, w / 2 } do
		Kit.Box(
			model,
			Vector3.new(0.2, wallH, d),
			CFrame.new(x, wallH / 2, 0),
			glass,
			{ Transparency = 0.7, Material = Enum.Material.Glass, Collide = false }
		)
	end
	if params.Dome then
		Kit.Ball(
			model,
			Vector3.new(w, (h - wallH) * 2, d),
			CFrame.new(0, wallH, 0),
			glass,
			{ Transparency = 0.75, Material = Enum.Material.Glass, Collide = false }
		)
		local core = Kit.Box(
			model,
			Vector3.new(1.4, 1.4, 1.4),
			CFrame.new(0, h - 1.5, 0),
			Color3.fromRGB(255, 240, 200),
			{ Material = Enum.Material.Neon, Collide = false }
		)
		Kit.Light(core, Color3.fromRGB(255, 240, 210), 40, 1)
	else
		Kit.Roof(
			model,
			w,
			d,
			wallH,
			h - wallH,
			glass,
			0.3,
			{ Transparency = 0.65, Material = Enum.Material.Glass, Collide = false }
		)
	end
	for i = -2, 2 do
		Kit.Box(model, Vector3.new(0.3, 0.3, d), CFrame.new(i * w / 5, wallH, 0), frame, { Collide = false })
	end
end

B.Hydroponics = function(model, w, d, h)
	Kit.Box(model, Vector3.new(w, 0.4, d), CFrame.new(0, 0.2, 0), Color3.fromRGB(210, 215, 220))
	for i = -1, 1 do
		Kit.Box(
			model,
			Vector3.new(w * 0.9, 0.4, 1.2),
			CFrame.new(0, 1.2 + (i + 1) * 1.8, i * d * 0.25),
			Color3.fromRGB(80, 170, 220),
			{ Transparency = 0.2, Collide = false }
		)
	end
	Kit.Box(
		model,
		Vector3.new(w, 0.3, d),
		CFrame.new(0, h, 0),
		C.Glass,
		{ Transparency = 0.6, Material = Enum.Material.Glass, Collide = false }
	)
	for _, x in { -w / 2, w / 2 } do
		Kit.Box(model, Vector3.new(0.4, h, 0.4), CFrame.new(x, h / 2, -d / 2), C.Metal)
		Kit.Box(model, Vector3.new(0.4, h, 0.4), CFrame.new(x, h / 2, d / 2), C.Metal)
	end
	local lamp = Kit.Box(
		model,
		Vector3.new(w * 0.8, 0.2, 0.6),
		CFrame.new(0, h - 0.4, 0),
		Color3.fromRGB(230, 120, 255),
		{ Material = Enum.Material.Neon, Collide = false }
	)
	Kit.Light(lamp, Color3.fromRGB(230, 150, 255), 18, 1)
end

B.Cellar = function(model, w, d, h)
	-- A sunken stone room with a sod roof; the floor is dark soil.
	Kit.Box(model, Vector3.new(w, 0.3, d), CFrame.new(0, 0.15, 0), Color3.fromRGB(60, 45, 35), { Collide = false })
	for _, x in { -w / 2, w / 2 } do
		Kit.Box(model, Vector3.new(1, h, d), CFrame.new(x, h / 2, 0), C.DarkStone, { Mat = true })
	end
	Kit.Box(
		model,
		Vector3.new(w + 2, 1, d + 2),
		CFrame.new(0, h + 0.5, 0),
		Color3.fromRGB(90, 140, 70),
		{ Material = Enum.Material.Grass }
	)
	Kit.Box(model, Vector3.new(w, h, 1), CFrame.new(0, h / 2, d / 2), C.DarkStone, { Mat = true })
	local lantern = Kit.Box(
		model,
		Vector3.new(0.6, 0.8, 0.6),
		CFrame.new(0, h - 1, 0),
		Color3.fromRGB(255, 180, 90),
		{ Material = Enum.Material.Neon, Collide = false }
	)
	Kit.Light(lantern, Color3.fromRGB(255, 170, 90), 14, 0.6)
end

B.Planter = function(model, w, d, h)
	local pot = Kit.Cyl(
		model,
		h * 0.6,
		w * 0.85,
		CFrame.new(0, h * 0.3, 0),
		Color3.fromRGB(140, 90, 200),
		{ Paint = true, Mat = true }
	)
	pot.Material = Enum.Material.Marble
	Kit.Cyl(model, 0.2, w * 0.75, CFrame.new(0, h * 0.6, 0), C.Soil, { Collide = false })
	local rune = Kit.Cyl(
		model,
		0.2,
		w * 0.95,
		CFrame.new(0, h * 0.25, 0),
		Color3.fromRGB(190, 160, 255),
		{ Material = Enum.Material.Neon, Collide = false }
	)
	Kit.Particles(rune, "Sparkle", Color3.fromRGB(210, 180, 255), 2)
end

local function simpleHouse(model: Model, w: number, d: number, h: number, wall: Color3, roof: Color3)
	local wallH = h * 0.6
	walls(model, w, d, wallH, wall, 4)
	Kit.Roof(model, w, d, wallH, h - wallH, roof, 1)
end

B.Workshop = function(model, w, d, h)
	simpleHouse(model, w, d, h, Color3.fromRGB(170, 130, 90), C.DarkStone)
	Kit.Box(model, Vector3.new(w * 0.5, 1, 2), CFrame.new(0, 1.5, d / 2 - 1.8), C.Wood, { Name = "Bench" })
	Kit.Box(model, Vector3.new(1.2, 1.4, 1.2), CFrame.new(w * 0.3, 0.7, 0), C.DarkMetal, { Name = "Anvil" })
	local chimney = Kit.Box(model, Vector3.new(1.4, 3, 1.4), CFrame.new(w * 0.3, h + 0.5, d * 0.2), C.DarkStone)
	Kit.Particles(chimney, "Smoke", Color3.fromRGB(200, 200, 200), 2)
end

B.Kitchen = function(model, w, d, h)
	simpleHouse(model, w, d, h, C.Cream, Color3.fromRGB(190, 80, 60))
	Kit.Box(model, Vector3.new(w * 0.6, 3, 1.6), CFrame.new(0, 1.5, d / 2 - 1.4), C.DarkStone, { Name = "Stove" })
	local fire = Kit.Box(
		model,
		Vector3.new(1.2, 0.6, 0.3),
		CFrame.new(0, 1, d / 2 - 2.25),
		Color3.fromRGB(255, 140, 60),
		{ Material = Enum.Material.Neon, Collide = false }
	)
	Kit.Light(fire, Color3.fromRGB(255, 150, 70), 10, 1)
	local chimney = Kit.Box(model, Vector3.new(1.2, 3, 1.2), CFrame.new(-w * 0.25, h + 0.3, d * 0.2), C.Stone)
	Kit.Particles(chimney, "Smoke", Color3.fromRGB(230, 230, 230), 1.5)
end

B.Lab = function(model, w, d, h)
	simpleHouse(model, w, d, h, Color3.fromRGB(235, 240, 245), Color3.fromRGB(90, 150, 170))
	for i = -1, 1 do
		local tube = Kit.Cyl(
			model,
			2.2,
			0.8,
			CFrame.new(i * 1.6, 1.6, d / 2 - 1.5),
			Color3.fromRGB(120, 230, 170),
			{ Material = Enum.Material.Glass, Transparency = 0.3, Collide = false }
		)
		Kit.Particles(tube, "Bubbles", Color3.fromRGB(160, 255, 200), 3)
	end
	local dish = Kit.Cyl(model, 0.3, 2.4, CFrame.new(w * 0.3, h + 0.6, 0) * CFrame.Angles(math.rad(30), 0, 0), C.Metal)
	dish.Name = "Dish"
end

B.AlchemyTable = function(model, w, d)
	Kit.Box(model, Vector3.new(w, 0.4, d), CFrame.new(0, 2.6, 0), C.DarkWood, { Mat = true })
	for _, x in { -w / 2 + 0.4, w / 2 - 0.4 } do
		for _, z in { -d / 2 + 0.4, d / 2 - 0.4 } do
			Kit.Box(model, Vector3.new(0.4, 2.4, 0.4), CFrame.new(x, 1.2, z), C.DarkWood)
		end
	end
	local cauldron = Kit.Ball(model, Vector3.new(2, 1.6, 2), CFrame.new(0, 3.5, 0), C.DarkMetal)
	local brew = Kit.Cyl(
		model,
		0.1,
		1.6,
		CFrame.new(0, 4.2, 0),
		Color3.fromRGB(140, 255, 160),
		{ Material = Enum.Material.Neon, Collide = false }
	)
	Kit.Particles(brew, "Bubbles", Color3.fromRGB(150, 255, 170), 5)
	Kit.Light(cauldron, Color3.fromRGB(140, 255, 160), 10, 0.8)
end

B.Chest = function(model, w, d, _h, params)
	local width = if params.Big then w * 0.9 else w * 0.8
	Kit.Box(model, Vector3.new(width, 1.8, d * 0.7), CFrame.new(0, 0.9, 0), C.Wood, { Paint = true, Mat = true })
	Kit.Box(
		model,
		Vector3.new(width + 0.1, 0.7, d * 0.72),
		CFrame.new(0, 2.1, 0),
		Kit.Shade(C.Wood, -0.15),
		{ Paint = true, Mat = true }
	)
	Kit.Box(model, Vector3.new(0.5, 0.6, 0.2), CFrame.new(0, 1.7, -d * 0.36), C.Gold, { Collide = false })
	for _, x in { -width / 2 + 0.3, width / 2 - 0.3 } do
		Kit.Box(model, Vector3.new(0.2, 2.5, d * 0.73), CFrame.new(x, 1.25, 0), C.DarkMetal, { Collide = false })
	end
end

B.Silo = function(model, w, _d, h, params)
	local body = Kit.Cyl(
		model,
		h * 0.85,
		w * 0.9,
		CFrame.new(0, h * 0.425, 0),
		if params.Smart then Color3.fromRGB(220, 225, 230) else Color3.fromRGB(170, 60, 50),
		{ Paint = true, Mat = true }
	)
	body.Material = if params.Smart then Enum.Material.Metal else Enum.Material.SmoothPlastic
	Kit.Ball(
		model,
		Vector3.new(w * 0.9, h * 0.25, w * 0.9),
		CFrame.new(0, h * 0.85, 0),
		C.Metal,
		{ Material = Enum.Material.Metal }
	)
	for i = 1, 4 do
		Kit.Cyl(model, 0.3, w * 0.92, CFrame.new(0, i * h * 0.18, 0), C.DarkMetal, { Collide = false })
	end
	if params.Smart then
		local screen = Kit.Box(
			model,
			Vector3.new(1.6, 1, 0.2),
			CFrame.new(0, 3, -w * 0.46),
			Color3.fromRGB(80, 220, 255),
			{ Material = Enum.Material.Neon, Collide = false }
		)
		Kit.Light(screen, Color3.fromRGB(100, 220, 255), 8, 0.6)
	end
end

B.Dock = function(model, w, d)
	for i = 0, math.floor(w / 1.5) - 1 do
		Kit.Box(model, Vector3.new(1.3, 0.35, d), CFrame.new(-w / 2 + 0.75 + i * 1.5, 1.2, 0), C.Plank)
	end
	for _, x in { -w / 2 + 0.5, w / 2 - 0.5 } do
		for _, z in { -d / 2 + 0.5, d / 2 - 0.5 } do
			Kit.Cyl(model, 2.4, 0.6, CFrame.new(x, 0.9, z), C.DarkWood)
		end
	end
	for i = 0, 2 do
		Kit.Box(
			model,
			Vector3.new(1.8, 1.8, 1.8),
			CFrame.new(-w / 4 + i * 1.2, 2.3 + (i % 2) * 1.8, 0),
			C.Wood,
			{ Name = "Crate" }
		)
	end
	Kit.Box(model, Vector3.new(0.3, 5, 0.3), CFrame.new(w / 2 - 1, 3.8, d / 2 - 1), C.DarkWood)
	Kit.Box(model, Vector3.new(2, 1.2, 0.2), CFrame.new(w / 2 - 1, 5.6, d / 2 - 1), C.Cream)
end

B.Stall = function(model, w, d, h)
	Kit.Box(model, Vector3.new(w, 2.6, d * 0.5), CFrame.new(0, 1.3, d * 0.2), C.Wood, { Mat = true })
	for _, x in { -w / 2 + 0.3, w / 2 - 0.3 } do
		Kit.Box(model, Vector3.new(0.3, h, 0.3), CFrame.new(x, h / 2, -d / 2 + 0.3), C.DarkWood)
		Kit.Box(model, Vector3.new(0.3, h, 0.3), CFrame.new(x, h / 2, d / 2 - 0.3), C.DarkWood)
	end
	-- Striped awning
	for i = 0, 5 do
		Kit.Box(
			model,
			Vector3.new(w / 6, 0.2, d + 0.6),
			CFrame.new(-w / 2 + w / 12 + i * w / 6, h, 0) * CFrame.Angles(math.rad(8), 0, 0),
			if i % 2 == 0 then C.Red else C.Cream,
			{ Paint = i % 2 == 0, Collide = false }
		)
	end
	for i = -1, 1 do
		Kit.Box(
			model,
			Vector3.new(1.2, 0.8, 1),
			CFrame.new(i * 1.6, 3, d * 0.1),
			C.Straw,
			{ Name = "Basket", Collide = false }
		)
	end
end

B.Sign = function(model, w, _d, h, params)
	local board = Kit.Box(
		model,
		Vector3.new(w * 0.9, if params.Big then h * 0.45 else h * 0.4, 0.3),
		CFrame.new(0, h * 0.72, 0),
		C.Plank,
		{ Paint = true, Name = "Board" }
	)
	Kit.Label(board, "", Enum.NormalId.Front)
	Kit.Label(board, "", Enum.NormalId.Back)
	if params.Big then
		Kit.Box(model, Vector3.new(0.4, h, 0.4), CFrame.new(-w * 0.4, h / 2, 0), C.DarkWood)
		Kit.Box(model, Vector3.new(0.4, h, 0.4), CFrame.new(w * 0.4, h / 2, 0), C.DarkWood)
	else
		Kit.Box(model, Vector3.new(0.4, h * 0.8, 0.4), CFrame.new(0, h * 0.4, 0), C.DarkWood)
	end
end

B.Pedestal = function(model, w, _d, h)
	Kit.Box(
		model,
		Vector3.new(w * 0.7, h * 0.7, w * 0.7),
		CFrame.new(0, h * 0.35, 0),
		C.Cream,
		{ Paint = true, Mat = true }
	)
	Kit.Box(model, Vector3.new(w * 0.85, 0.3, w * 0.85), CFrame.new(0, h * 0.72, 0), C.Gold)
	local case = Kit.Box(
		model,
		Vector3.new(w * 0.6, h * 0.3, w * 0.6),
		CFrame.new(0, h * 0.9, 0),
		C.Glass,
		{ Transparency = 0.8, Material = Enum.Material.Glass, Collide = false, Name = "Case" }
	)
	case:SetAttribute("DisplaySlot", 1)
end

B.TrophyCase = function(model, w, d, h)
	Kit.Box(
		model,
		Vector3.new(w, h, d * 0.8),
		CFrame.new(0, h / 2, 0),
		C.DarkWood,
		{ Paint = true, Mat = true, Transparency = 0 }
	)
	Kit.Box(
		model,
		Vector3.new(w * 0.9, h * 0.9, 0.2),
		CFrame.new(0, h / 2, -d * 0.41),
		C.Glass,
		{ Transparency = 0.75, Material = Enum.Material.Glass, Collide = false }
	)
	for i = 1, 4 do
		local shelf = Kit.Box(
			model,
			Vector3.new(w * 0.85, 0.2, d * 0.6),
			CFrame.new(0, i * h / 5, 0),
			C.Wood,
			{ Collide = false, Name = "Shelf" }
		)
		shelf:SetAttribute("DisplaySlot", i)
	end
end

B.Pond = function(model, w, d, _h, params)
	Kit.Box(model, Vector3.new(w + 1, 0.5, d + 1), CFrame.new(0, 0.1, 0), C.Stone, { Mat = true, Collide = false })
	local water = Kit.Box(
		model,
		Vector3.new(w - 0.4, 0.3, d - 0.4),
		CFrame.new(0, 0.35, 0),
		C.Water,
		{ Material = Enum.Material.Glass, Transparency = 0.25, Collide = false, Name = "Water", Reflectance = 0.2 }
	)
	water:SetAttribute("Water", "Pond")
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		Kit.Ball(
			model,
			Vector3.new(1.4, 0.9, 1.2),
			CFrame.new(math.cos(a) * w * 0.5, 0.45, math.sin(a) * d * 0.5),
			C.DarkStone
		)
	end
	if params.Koi then
		for i = 1, 3 do
			local fish = Kit.Box(
				model,
				Vector3.new(0.8, 0.2, 0.3),
				CFrame.new(-1 + i, 0.45, -0.5 + i * 0.3),
				if i == 2 then C.White else Color3.fromRGB(250, 130, 40),
				{ Collide = false, Name = "Koi" }
			)
			fish:SetAttribute("Swim", true)
		end
		Kit.Cyl(model, 0.1, 1.4, CFrame.new(w * 0.2, 0.52, d * 0.2), Color3.fromRGB(80, 170, 80), { Collide = false })
	else
		Kit.Cyl(
			model,
			0.1,
			1.6,
			CFrame.new(-w * 0.25, 0.52, d * 0.15),
			Color3.fromRGB(80, 170, 80),
			{ Collide = false }
		)
	end
end

B.Well = function(model, w, _d, h)
	local ring = Kit.Cyl(model, 2.4, w * 0.95, CFrame.new(0, 1.2, 0), C.Stone, { Paint = true, Mat = true })
	ring.Material = Enum.Material.Cobblestone
	local water = Kit.Cyl(model, 0.1, w * 0.7, CFrame.new(0, 2, 0), C.Water, { Collide = false, Name = "Water" })
	water:SetAttribute("Water", "Well")
	for _, x in { -w * 0.45, w * 0.45 } do
		Kit.Box(model, Vector3.new(0.3, h - 1, 0.3), CFrame.new(x, h / 2, 0), C.DarkWood)
	end
	Kit.Roof(model, w * 0.9, w * 0.6, h - 1, 1.2, C.Wood, 0.3)
	Kit.CylFlat(model, w * 0.8, 0.4, CFrame.new(0, h - 1.5, 0), C.Wood, "X")
	Kit.Box(model, Vector3.new(0.6, 0.6, 0.6), CFrame.new(0.3, h - 2.7, 0), C.DarkWood, { Name = "Bucket" })
end

return B

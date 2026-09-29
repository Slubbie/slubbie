-- Procedural crop models, built on the client from tile attributes.
--
-- Crops.Build(cropDef, stage, opts) → Model, pivot at the tile surface centre.
--   stage  1 Seed · 2 Sprout · 3 Young · 4 Budding · 5 Ripe
--   opts   { Mutations = { ids }, Dry = bool, Seed = number (per-tile variety), Dormant = bool }
--
-- Shapes come from the crop's Visual { Arch, Leaf, Fruit, Shape, Count, Height,
-- Glow, Accent, Material }. Parts stay few (performance: a full farm can show
-- thousands of crops) and never collide or cast small shadows.
-- Parts named "Fruit" appear on ripe crops; parts with attribute "Sway" are
-- animated by the renderer.

local Kit = require(script.Parent.Kit)

local Crops = {}

local MATERIALS: { [string]: Enum.Material } = {
	Glass = Enum.Material.Glass,
	Foil = Enum.Material.Foil,
	Neon = Enum.Material.Neon,
	Ice = Enum.Material.Ice,
	Slate = Enum.Material.Slate,
	Metal = Enum.Material.Metal,
}

local STAGE_SCALE = { 0.12, 0.35, 0.6, 0.85, 1 }

local function part(
	model: Model,
	kind: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	name: string?,
	material: Enum.Material?
): BasePart
	local p
	if kind == "Ball" then
		p = Kit.Ball(model, size, cf, color, { Collide = false, Shadow = false, Name = name })
	elseif kind == "Cyl" then
		p = Kit.Cyl(model, size.Y, size.X, cf, color, { Collide = false, Shadow = false, Name = name })
	elseif kind == "Wedge" then
		p = Kit.Wedge(model, size, cf, color, { Collide = false, Shadow = false, Name = name })
	else
		p = Kit.Box(model, size, cf, color, { Collide = false, Shadow = false, Name = name })
	end
	p.CanQuery = false
	p.Material = material or Enum.Material.SmoothPlastic
	return p
end

local function leaf(model: Model, cf: CFrame, length: number, width: number, color: Color3): BasePart
	local p = part(model, "Wedge", Vector3.new(0.12, width, length), cf, color, "Leaf", Enum.Material.Grass)
	p:SetAttribute("Sway", true)
	return p
end

-- Fruit in the crop's shape.
local function fruit(
	model: Model,
	shape: string?,
	cf: CFrame,
	size: number,
	color: Color3,
	accent: Color3?,
	material: Enum.Material?
): BasePart
	local s = shape or "Ball"
	local p: BasePart
	if s == "Cone" then
		p = part(
			model,
			"Wedge",
			Vector3.new(size * 0.7, size * 1.6, size * 0.7),
			cf * CFrame.Angles(math.pi, 0, 0),
			color,
			"Fruit",
			material
		)
	elseif s == "Cylinder" then
		p = part(model, "Cyl", Vector3.new(size * 0.6, size * 1.8, 0), cf, color, "Fruit", material)
	elseif s == "Egg" then
		p = part(model, "Ball", Vector3.new(size, size * 1.35, size), cf, color, "Fruit", material)
	elseif s == "Cup" then
		p = part(model, "Cyl", Vector3.new(size * 1.1, size * 0.7, 0), cf, color, "Fruit", material)
		part(
			model,
			"Ball",
			Vector3.new(size * 0.4, size * 0.4, size * 0.4),
			cf * CFrame.new(0, size * 0.25, 0),
			accent or Color3.fromRGB(255, 220, 90),
			"Fruit"
		)
	elseif s == "Pumpkin" then
		p = part(model, "Ball", Vector3.new(size * 1.4, size, size * 1.4), cf, color, "Fruit", material)
		part(
			model,
			"Cyl",
			Vector3.new(size * 0.15, size * 0.35, 0),
			cf * CFrame.new(0, size * 0.55, 0),
			Color3.fromRGB(90, 110, 50),
			"Stem"
		)
	elseif s == "Puff" then
		p = part(model, "Ball", Vector3.new(size * 1.2, size * 1.2, size * 1.2), cf, color, "Fruit", material)
		p.Transparency = 0.15
	elseif s == "Star" then
		p = part(
			model,
			"Box",
			Vector3.new(size * 0.35, size * 1.2, size * 0.35),
			cf * CFrame.Angles(0, 0, math.rad(45)),
			color,
			"Fruit",
			material
		)
		part(
			model,
			"Box",
			Vector3.new(size * 0.35, size * 1.2, size * 0.35),
			cf * CFrame.Angles(0, 0, math.rad(-45)),
			color,
			"Fruit",
			material
		)
	elseif s == "Shard" then
		p = part(
			model,
			"Box",
			Vector3.new(size * 0.5, size * 1.6, size * 0.5),
			cf * CFrame.Angles(0.2, math.pi / 4, 0.15),
			color,
			"Fruit",
			material or Enum.Material.Glass
		)
	elseif s == "Spike" then
		p = part(model, "Wedge", Vector3.new(size * 0.3, size * 1.4, size * 0.3), cf, color, "Fruit", material)
	elseif s == "Leaf" then
		p = part(model, "Wedge", Vector3.new(0.15, size, size * 1.3), cf, color, "Fruit", material)
	elseif s == "Cluster" then
		p = part(model, "Ball", Vector3.new(size * 0.6, size * 0.6, size * 0.6), cf, color, "Fruit", material)
		for i = 1, 3 do
			local a = i * 2.1
			part(
				model,
				"Ball",
				Vector3.new(size * 0.55, size * 0.55, size * 0.55),
				cf * CFrame.new(math.cos(a) * size * 0.35, -size * 0.3, math.sin(a) * size * 0.35),
				color,
				"Fruit",
				material
			)
		end
	else
		p = part(model, "Ball", Vector3.new(size, size, size), cf, color, "Fruit", material)
	end
	return p
end

local builders: { [string]: (Model, any, number, boolean, Random) -> () } = {}

-- s = stage scale, ripe = shows fruit
builders.Root = function(m, v, s, ripe, r)
	for i = 1, 5 do
		leaf(
			m,
			CFrame.new(0, 0.9 * s, 0)
				* CFrame.Angles(0, i * 1.26 + r:NextNumber(), 0)
				* CFrame.Angles(math.rad(-55), 0, 0)
				* CFrame.new(0, 0, -0.6 * s),
			1.6 * s,
			0.9 * s,
			v.Leaf
		)
	end
	if ripe then
		fruit(m, v.Shape, CFrame.new(0, 0.1, 0), 1.3, v.Fruit, v.Accent, v.Mat)
	end
end

builders.Leafy = function(m, v, s, ripe, r)
	local rings = if ripe then 3 else 2
	for ring = 1, rings do
		for i = 1, 5 do
			local a = i * 1.26 + ring * 0.6 + r:NextNumber(-0.2, 0.2)
			leaf(
				m,
				CFrame.new(0, 0.3 * s + ring * 0.12, 0)
					* CFrame.Angles(0, a, 0)
					* CFrame.Angles(math.rad(-30 - ring * 15), 0, 0)
					* CFrame.new(0, 0, -0.5 * s),
				(1.4 - ring * 0.2) * s * 1.2,
				1.2 * s,
				if ring == rings then v.Fruit else v.Leaf
			)
		end
	end
	if ripe then
		part(m, "Ball", Vector3.new(1.3, 1.1, 1.3), CFrame.new(0, 0.6, 0), v.Fruit, "Fruit", Enum.Material.Grass)
	end
end

builders.Stalk = function(m, v, s, ripe, r)
	local h = (v.Height or 3) * s
	for i = 1, 5 do
		local off = Vector3.new(r:NextNumber(-0.9, 0.9), 0, r:NextNumber(-0.9, 0.9))
		local stalk = part(
			m,
			"Box",
			Vector3.new(0.12, h, 0.12),
			CFrame.new(off + Vector3.new(0, h / 2, 0))
				* CFrame.Angles(r:NextNumber(-0.1, 0.1), 0, r:NextNumber(-0.1, 0.1)),
			v.Leaf,
			"Stalk",
			Enum.Material.Grass
		)
		stalk:SetAttribute("Sway", true)
		if ripe or s > 0.8 then
			fruit(
				m,
				v.Shape or "Cylinder",
				CFrame.new(off + Vector3.new(0, h + 0.3, 0)),
				0.5,
				if ripe then v.Fruit else v.Leaf,
				nil,
				v.Mat
			)
		end
	end
end

builders.Corn = function(m, v, s, ripe, r)
	local h = (v.Height or 5) * s
	part(m, "Cyl", Vector3.new(0.3, h, 0), CFrame.new(0, h / 2, 0), v.Leaf, "Stalk", Enum.Material.Grass):SetAttribute(
		"Sway",
		true
	)
	for i = 1, 4 do
		leaf(
			m,
			CFrame.new(0, h * (0.25 + i * 0.15), 0)
				* CFrame.Angles(0, i * 1.7 + r:NextNumber(), 0)
				* CFrame.Angles(math.rad(-50), 0, 0)
				* CFrame.new(0, 0, -0.7),
			1.8 * s,
			0.4,
			v.Leaf
		)
	end
	if ripe then
		for i = 1, 2 do
			local a = i * math.pi
			fruit(
				m,
				"Cylinder",
				CFrame.new(math.cos(a) * 0.35, h * 0.55, math.sin(a) * 0.35) * CFrame.Angles(0, 0, math.rad(20)),
				0.55,
				v.Fruit,
				nil,
				v.Mat
			)
		end
	end
end

builders.Bush = function(m, v, s, ripe, r)
	local h = (v.Height or 1) * 1.6 * s
	part(m, "Ball", Vector3.new(2.2 * s, h, 2.2 * s), CFrame.new(0, h * 0.5, 0), v.Leaf, "Leaves", Enum.Material.Grass):SetAttribute(
		"Sway",
		true
	)
	part(
		m,
		"Ball",
		Vector3.new(1.6 * s, h * 0.8, 1.6 * s),
		CFrame.new(0.5 * s, h * 0.65, 0.3 * s),
		v.Leaf:Lerp(Color3.new(0, 0, 0), 0.1),
		"Leaves",
		Enum.Material.Grass
	)
	if ripe then
		for i = 1, v.Count or 4 do
			local a = i / (v.Count or 4) * math.pi * 2 + r:NextNumber()
			fruit(
				m,
				v.Shape,
				CFrame.new(math.cos(a) * 0.95 * s, h * r:NextNumber(0.35, 0.8), math.sin(a) * 0.95 * s),
				0.5,
				v.Fruit,
				v.Accent,
				v.Mat
			)
		end
	end
end

builders.Vine = function(m, v, s, ripe, r)
	local h = (v.Height or 2) * 1.2 * s + 0.4
	for _, x in { -0.9, 0.9 } do
		part(
			m,
			"Box",
			Vector3.new(0.15, h + 0.4, 0.15),
			CFrame.new(x, (h + 0.4) / 2, 0),
			Color3.fromRGB(140, 110, 70),
			"Trellis",
			Enum.Material.Wood
		)
	end
	part(
		m,
		"Box",
		Vector3.new(2, 0.12, 0.12),
		CFrame.new(0, h + 0.3, 0),
		Color3.fromRGB(140, 110, 70),
		"Trellis",
		Enum.Material.Wood
	)
	for i = 1, 4 do
		leaf(
			m,
			CFrame.new(r:NextNumber(-0.8, 0.8), h * (i / 4), 0.1)
				* CFrame.Angles(0, r:NextNumber(-0.5, 0.5), math.rad(90)),
			0.9,
			0.8,
			v.Leaf
		)
	end
	if ripe then
		for i = 1, v.Count or 4 do
			fruit(
				m,
				v.Shape,
				CFrame.new(r:NextNumber(-0.8, 0.8), h * r:NextNumber(0.3, 0.9), 0.3),
				0.45,
				v.Fruit,
				v.Accent,
				v.Mat
			)
		end
	end
end

builders.Gourd = function(m, v, s, ripe, r)
	for i = 1, 5 do
		leaf(
			m,
			CFrame.new(0, 0.35 * s, 0)
				* CFrame.Angles(0, i * 1.26 + r:NextNumber(), 0)
				* CFrame.Angles(math.rad(-75), 0, 0)
				* CFrame.new(0, 0, -0.9 * s),
			1.6 * s,
			1.5 * s,
			v.Leaf
		)
	end
	part(
		m,
		"Box",
		Vector3.new(1.8 * s, 0.1, 0.1),
		CFrame.new(0, 0.12, 0) * CFrame.Angles(0, r:NextNumber(0, 3), 0),
		v.Leaf,
		"Vine"
	)
	if ripe then
		fruit(m, v.Shape or "Ball", CFrame.new(0.5, 0.75, 0.4), 1.5, v.Fruit, v.Accent, v.Mat)
	elseif s > 0.8 then
		fruit(m, v.Shape or "Ball", CFrame.new(0.5, 0.4, 0.4), 0.7, v.Leaf:Lerp(v.Fruit, 0.4), nil, nil)
	end
end

builders.Tree = function(m, v, s, ripe, r)
	local h = (v.Height or 5) * s + 0.5
	part(
		m,
		"Cyl",
		Vector3.new(0.45 * math.max(s, 0.3), h, 0),
		CFrame.new(0, h / 2, 0),
		Color3.fromRGB(120, 85, 55),
		"Trunk",
		Enum.Material.Wood
	)
	local canopy = part(
		m,
		"Ball",
		Vector3.new(3 * s, 2.4 * s, 3 * s),
		CFrame.new(0, h + 0.6 * s, 0),
		v.Leaf,
		"Leaves",
		Enum.Material.Grass
	)
	canopy:SetAttribute("Sway", true)
	part(
		m,
		"Ball",
		Vector3.new(2.2 * s, 1.8 * s, 2.2 * s),
		CFrame.new(0.7 * s, h + 1.1 * s, -0.3 * s),
		v.Leaf:Lerp(Color3.new(1, 1, 1), 0.08),
		"Leaves",
		Enum.Material.Grass
	)
	if ripe then
		for i = 1, v.Count or 5 do
			local a = i / (v.Count or 5) * math.pi * 2 + r:NextNumber()
			fruit(
				m,
				v.Shape,
				CFrame.new(math.cos(a) * 1.3, h + r:NextNumber(0, 0.9), math.sin(a) * 1.3),
				0.5,
				v.Fruit,
				v.Accent,
				v.Mat
			)
		end
	end
end

builders.Flower = function(m, v, s, ripe, r)
	local h = 1.6 * s + 0.2
	for i = 1, 3 do
		local off = Vector3.new(r:NextNumber(-0.7, 0.7), 0, r:NextNumber(-0.7, 0.7))
		local stem = part(
			m,
			"Box",
			Vector3.new(0.1, h, 0.1),
			CFrame.new(off + Vector3.new(0, h / 2, 0)),
			v.Leaf,
			"Stem",
			Enum.Material.Grass
		)
		stem:SetAttribute("Sway", true)
		leaf(
			m,
			CFrame.new(off + Vector3.new(0, h * 0.4, 0)) * CFrame.Angles(0, r:NextNumber(0, 6), math.rad(60)),
			0.6,
			0.4,
			v.Leaf
		)
		if ripe or s >= 0.85 then
			local bloom = if ripe then v.Fruit else v.Leaf:Lerp(v.Fruit, 0.5)
			local size = if ripe then 0.75 else 0.4
			fruit(m, v.Shape or "Cup", CFrame.new(off + Vector3.new(0, h + 0.15, 0)), size, bloom, v.Accent, v.Mat)
		end
	end
end

builders.TallFlower = function(m, v, s, ripe, r)
	local h = (v.Height or 4) * s + 0.3
	part(m, "Cyl", Vector3.new(0.22, h, 0), CFrame.new(0, h / 2, 0), v.Leaf, "Stem", Enum.Material.Grass):SetAttribute(
		"Sway",
		true
	)
	for i = 1, 3 do
		leaf(
			m,
			CFrame.new(0, h * (0.3 + i * 0.15), 0)
				* CFrame.Angles(0, i * 2.1 + r:NextNumber(), 0)
				* CFrame.Angles(math.rad(-60), 0, 0)
				* CFrame.new(0, 0, -0.4),
			0.9,
			0.7,
			v.Leaf
		)
	end
	if ripe then
		local head = part(
			m,
			"Cyl",
			Vector3.new(1.8, 0.3, 0),
			CFrame.new(0, h + 0.3, 0.2) * CFrame.Angles(math.rad(70), 0, 0),
			v.Fruit,
			"Fruit",
			v.Mat
		)
		head:SetAttribute("Sway", true)
		part(
			m,
			"Cyl",
			Vector3.new(0.9, 0.35, 0),
			CFrame.new(0, h + 0.32, 0.12) * CFrame.Angles(math.rad(70), 0, 0),
			v.Accent or Color3.fromRGB(110, 70, 40),
			"Fruit"
		)
	end
end

builders.Herb = function(m, v, s, ripe, r)
	for i = 1, 7 do
		local off = Vector3.new(r:NextNumber(-0.6, 0.6), 0, r:NextNumber(-0.6, 0.6))
		local sprig = part(
			m,
			"Wedge",
			Vector3.new(0.1, 1.2 * s + 0.2, 0.3),
			CFrame.new(off + Vector3.new(0, (1.2 * s + 0.2) / 2, 0))
				* CFrame.Angles(0, r:NextNumber(0, 6), r:NextNumber(-0.3, 0.3)),
			v.Leaf,
			"Sprig",
			Enum.Material.Grass
		)
		sprig:SetAttribute("Sway", true)
	end
	if ripe then
		for i = 1, 3 do
			fruit(
				m,
				v.Shape or "Spike",
				CFrame.new(r:NextNumber(-0.5, 0.5), 1.4, r:NextNumber(-0.5, 0.5)),
				0.35,
				v.Fruit,
				nil,
				v.Mat
			)
		end
	end
end

builders.Pepper = function(m, v, s, ripe, r)
	local h = 1.8 * s + 0.2
	part(m, "Box", Vector3.new(0.15, h, 0.15), CFrame.new(0, h / 2, 0), v.Leaf, "Stem", Enum.Material.Grass)
	part(
		m,
		"Ball",
		Vector3.new(1.8 * s, 1.2 * s, 1.8 * s),
		CFrame.new(0, h * 0.8, 0),
		v.Leaf,
		"Leaves",
		Enum.Material.Grass
	):SetAttribute("Sway", true)
	if ripe then
		for i = 1, v.Count or 4 do
			local a = i / (v.Count or 4) * math.pi * 2
			fruit(
				m,
				v.Shape or "Cone",
				CFrame.new(math.cos(a) * 0.7, h * 0.55, math.sin(a) * 0.7),
				0.4,
				v.Fruit,
				nil,
				v.Mat
			)
		end
	end
end

builders.Mushroom = function(m, v, s, ripe, r)
	for i = 1, (if ripe then 4 else 2) do
		local off = Vector3.new(r:NextNumber(-0.8, 0.8), 0, r:NextNumber(-0.8, 0.8))
		local size = (if i == 1 then 1 else 0.6) * (0.4 + s * 0.8)
		part(
			m,
			"Cyl",
			Vector3.new(0.25 * size, 0.8 * size, 0),
			CFrame.new(off + Vector3.new(0, 0.4 * size, 0)),
			Color3.fromRGB(240, 232, 214),
			"Stem"
		)
		part(
			m,
			"Ball",
			Vector3.new(1.1 * size, 0.55 * size, 1.1 * size),
			CFrame.new(off + Vector3.new(0, 0.85 * size, 0)),
			if ripe then v.Fruit else v.Fruit:Lerp(Color3.new(1, 1, 1), 0.4),
			if ripe then "Fruit" else "Cap",
			v.Mat
		)
	end
end

builders.Crystal = function(m, v, s, ripe, r)
	local count = if ripe then 5 else 3
	for i = 1, count do
		local h = (0.6 + r:NextNumber(0, 1.2)) * (0.3 + s)
		fruit(
			m,
			"Shard",
			CFrame.new(r:NextNumber(-0.8, 0.8), h * 0.4, r:NextNumber(-0.8, 0.8)),
			h,
			if ripe then v.Fruit else v.Leaf,
			nil,
			Enum.Material.Glass
		)
	end
end

builders.Cloud = function(m, v, s, ripe, r)
	part(m, "Box", Vector3.new(0.1, 1.2 * s, 0.1), CFrame.new(0, 0.6 * s, 0), v.Leaf, "Stem")
	for i = 1, (if ripe then 5 else 3) do
		local a = i * 1.3
		local puff = part(
			m,
			"Ball",
			Vector3.new(1, 0.8, 1) * (0.5 + s * 0.6),
			CFrame.new(math.cos(a) * 0.6, 1.4 * s + 0.4 + (i % 2) * 0.3, math.sin(a) * 0.6),
			if ripe then v.Fruit else Color3.new(1, 1, 1),
			if ripe then "Fruit" else "Puff"
		)
		puff:SetAttribute("Sway", true)
		puff.Transparency = 0.1
	end
end

builders.Cactus = function(m, v, s, ripe, r)
	local h = 2.2 * s + 0.3
	part(
		m,
		"Cyl",
		Vector3.new(0.8 * math.max(s, 0.4), h, 0),
		CFrame.new(0, h / 2, 0),
		v.Leaf,
		"Body",
		Enum.Material.Grass
	)
	if s > 0.6 then
		part(m, "Cyl", Vector3.new(0.45, h * 0.4, 0), CFrame.new(0.55, h * 0.55, 0), v.Leaf, "Arm", Enum.Material.Grass)
	end
	if ripe then
		fruit(m, v.Shape or "Egg", CFrame.new(0, h + 0.3, 0), 0.6, v.Fruit, v.Accent, v.Mat)
		fruit(m, v.Shape or "Egg", CFrame.new(0.55, h * 0.8 + 0.2, 0), 0.45, v.Fruit, v.Accent, v.Mat)
	end
end

builders.Orchid = function(m, v, s, ripe, r)
	for i = 1, 3 do
		leaf(
			m,
			CFrame.new(0, 0.25, 0)
				* CFrame.Angles(0, i * 2.1, 0)
				* CFrame.Angles(math.rad(-70), 0, 0)
				* CFrame.new(0, 0, -0.5),
			1.2 * s + 0.2,
			0.6,
			v.Leaf
		)
	end
	local h = 2 * s
	part(m, "Box", Vector3.new(0.08, h, 0.08), CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, 0.2), v.Leaf, "Stem"):SetAttribute(
		"Sway",
		true
	)
	if ripe then
		for i = 1, 4 do
			fruit(m, v.Shape or "Star", CFrame.new(0.2 + i * 0.18, h - i * 0.2, 0), 0.4, v.Fruit, v.Accent, v.Mat)
		end
	end
end

builders.Spiky = function(m, v, s, ripe, r)
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		part(
			m,
			"Wedge",
			Vector3.new(0.1, 1.4 * s + 0.2, 0.35),
			CFrame.new(math.cos(a) * 0.3, (1.4 * s + 0.2) / 2, math.sin(a) * 0.3) * CFrame.Angles(0, -a, math.rad(20)),
			v.Leaf,
			"Spike",
			Enum.Material.Grass
		)
	end
	if ripe then
		fruit(m, v.Shape or "Egg", CFrame.new(0, 1.5 * s + 0.4, 0), 0.9, v.Fruit, v.Accent, v.Mat)
	end
end

-- Mutation dressing ------------------------------------------------------------------------------------------------

local PARTICLE_COLORS: { [string]: Color3 } = {
	Sparkle = Color3.fromRGB(255, 230, 120),
	Shine = Color3.fromRGB(220, 240, 255),
	Snow = Color3.fromRGB(240, 250, 255),
	Embers = Color3.fromRGB(255, 140, 60),
	Sparks = Color3.fromRGB(255, 250, 150),
	Rainbow = Color3.fromRGB(255, 150, 220),
	Hearts = Color3.fromRGB(255, 120, 160),
	Dust = Color3.fromRGB(210, 190, 150),
	Stars = Color3.fromRGB(190, 170, 255),
	Pollen = Color3.fromRGB(255, 235, 120),
	Galaxy = Color3.fromRGB(160, 120, 255),
	Prism = Color3.fromRGB(255, 255, 255),
	Wisps = Color3.fromRGB(180, 255, 230),
}

function Crops.ApplyMutations(model: Model, visuals: { any })
	local fruitParts = {}
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and (d.Name == "Fruit" or d.Name == "Leaves" or d.Name == "Cap") then
			table.insert(fruitParts, d)
		end
	end
	local scale = 1
	local emitterPart: BasePart? = fruitParts[1]
	for _, v in visuals do
		for _, p in fruitParts do
			if v.Color and p.Name ~= "Leaves" then
				p.Color = p.Color:Lerp(v.Color, 0.75)
			end
			if v.Material and MATERIALS[v.Material] and p.Name ~= "Leaves" then
				p.Material = MATERIALS[v.Material]
			end
			if v.Neon and p.Name ~= "Leaves" then
				p.Material = Enum.Material.Neon
			end
			if v.Transparency then
				p.Transparency = v.Transparency
			end
			if v.Hue then
				p:SetAttribute("HueCycle", true)
			end
		end
		if v.Scale then
			scale *= v.Scale
		end
		if emitterPart then
			if v.Light then
				Kit.Light(emitterPart, v.Light, 8, 0.8)
			end
			if v.Particles then
				local e = Kit.Particles(emitterPart, "Sparkle", PARTICLE_COLORS[v.Particles] or Color3.new(1, 1, 1), 3)
				e.Name = "Mutation_" .. v.Particles
				if v.Particles == "Snow" or v.Particles == "Dust" then
					e.Acceleration = Vector3.new(0, -2, 0)
				elseif v.Particles == "Embers" or v.Particles == "Wisps" then
					e.Acceleration = Vector3.new(0, 2, 0)
				end
			end
		end
	end
	if scale ~= 1 then
		pcall(function()
			model:ScaleTo(scale)
		end)
	end
end

-- Build ------------------------------------------------------------------------------------------------------------

export type Opts = { Mutations: { any }?, Dry: boolean?, Seed: number?, Dormant: boolean? }

function Crops.Build(crop: any, stage: number, opts: Opts?): Model
	local o = opts or {}
	local model = Kit.Model(crop.Id)
	local base = model.PrimaryPart :: BasePart
	base.CanQuery = false
	local r = Random.new(o.Seed or 1)
	local v = crop.Visual
	local visual = {
		Leaf = v.Leaf,
		Fruit = v.Fruit,
		Accent = v.Accent,
		Shape = v.Shape,
		Count = v.Count,
		Height = v.Height,
		Mat = if v.Material then MATERIALS[v.Material] else nil,
	}
	if o.Dry then
		visual.Leaf = visual.Leaf:Lerp(Color3.fromRGB(170, 150, 90), 0.45)
	end
	if o.Dormant then
		visual.Leaf = visual.Leaf:Lerp(Color3.fromRGB(150, 140, 120), 0.5)
	end
	if stage <= 1 then
		-- A seed mound with a tiny sprout marker.
		part(
			model,
			"Ball",
			Vector3.new(1.2, 0.35, 1.2),
			CFrame.new(0, 0.05, 0),
			Color3.fromRGB(95, 70, 48),
			"Mound",
			Enum.Material.Ground
		)
		part(
			model,
			"Ball",
			Vector3.new(0.25, 0.25, 0.25),
			CFrame.new(0, 0.25, 0),
			Color3.fromRGB(200, 180, 120),
			"Seed"
		)
	else
		local builder = builders[v.Arch] or builders.Bush
		local s = STAGE_SCALE[math.clamp(stage, 1, 5)]
		builder(model, visual, s, stage >= 5, r)
	end
	if v.Glow and stage >= 3 then
		local target = model:FindFirstChild("Fruit")
			or model:FindFirstChild("Leaves")
			or model:FindFirstChildWhichIsA("BasePart")
		if target and target:IsA("BasePart") and target ~= base then
			Kit.Light(target, visual.Fruit, 10, 0.7)
			if stage >= 5 then
				target.Material = Enum.Material.Neon
			end
		end
	end
	if o.Mutations and #o.Mutations > 0 and stage >= 3 then
		Crops.ApplyMutations(model, o.Mutations)
	end
	-- Slight random turn so fields don't look copy-pasted.
	model:PivotTo(CFrame.Angles(0, r:NextNumber(0, math.pi * 2), 0))
	return model
end

return Crops

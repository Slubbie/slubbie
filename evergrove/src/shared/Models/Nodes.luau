-- Resource node models: trees, rocks, ore veins, crystals, dig mounds.
-- Built from Config/Gathering node Visual { Color, Accent, Size, Shape, Material, Glow }.
-- The part named "Hit" is what tools aim at; "Body" parts shake/flash on hits.

local Kit = require(script.Parent.Kit)
local C = Kit.C

local Nodes = {}

local MATERIALS = {
	Glass = Enum.Material.Glass,
	Ice = Enum.Material.Ice,
	Neon = Enum.Material.Neon,
	Foil = Enum.Material.Foil,
}

local function body(part: BasePart): BasePart
	part:SetAttribute("Body", true)
	return part
end

local function trunk(model: Model, height: number, width: number, color: Color3)
	local t = Kit.Cyl(model, height, width, CFrame.new(0, height / 2, 0), color, { Material = Enum.Material.Wood })
	t.Name = "Trunk"
	return body(t)
end

local shapes: { [string]: (Model, any, number, any) -> () } = {}

shapes.Round = function(model, v, s, rng)
	local h = 9 * s
	trunk(model, h * 0.55, 1.4 * s, v.Accent or C.DarkWood)
	for i = 1, 4 do
		local a = i * math.pi / 2 + rng:NextNumber(0, 0.6)
		local r = rng:NextNumber(1.2, 2.2) * s
		local size = rng:NextNumber(4.2, 5.6) * s
		body(Kit.Ball(model, Vector3.new(size, size * 0.9, size), CFrame.new(math.cos(a) * r, h * 0.62 + rng:NextNumber(0, 1.4) * s, math.sin(a) * r), Kit.Shade(v.Color, rng:NextNumber(-0.08, 0.08)), { Material = Enum.Material.Grass, Collide = false, Name = "Leaves" }))
	end
	body(Kit.Ball(model, Vector3.new(5.5, 5, 5.5) * s, CFrame.new(0, h * 0.85, 0), v.Color, { Material = Enum.Material.Grass, Collide = false, Name = "Leaves" }))
end

shapes.Cone = function(model, v, s, rng)
	local h = 12 * s
	trunk(model, h * 0.35, 1.2 * s, v.Accent or C.DarkWood)
	for i = 0, 3 do
		local width = (6.5 - i * 1.4) * s
		local y = h * 0.28 + i * 2.2 * s
		local tier = Kit.Cyl(model, 2.6 * s, width, CFrame.new(0, y, 0) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), Kit.Shade(v.Color, -0.05 * i), { Material = Enum.Material.Grass, Collide = false, Name = "Leaves" })
		body(tier)
		-- Cone taper
		body(Kit.Wedge(model, Vector3.new(width * 0.7, 1.4 * s, width * 0.35), CFrame.new(0, y + 1.6 * s, width * 0.17), Kit.Shade(v.Color, -0.05 * i), { Collide = false, Material = Enum.Material.Grass, Name = "Leaves" }))
		body(Kit.Wedge(model, Vector3.new(width * 0.7, 1.4 * s, width * 0.35), CFrame.new(0, y + 1.6 * s, -width * 0.17) * CFrame.Angles(0, math.pi, 0), Kit.Shade(v.Color, -0.05 * i), { Collide = false, Material = Enum.Material.Grass, Name = "Leaves" }))
	end
end

shapes.Palm = function(model, v, s, rng)
	local h = 11 * s
	local lean = rng:NextNumber(-0.18, 0.18)
	for i = 0, 5 do
		local seg = Kit.Cyl(model, h / 6 + 0.1, (1.1 - i * 0.07) * s, CFrame.new(math.sin(lean) * i * 0.8 * s, h / 12 + i * h / 6, 0) * CFrame.Angles(0, 0, lean), v.Accent or C.Wood, { Material = Enum.Material.Wood })
		body(seg)
	end
	local top = Vector3.new(math.sin(lean) * 5 * 0.8 * s, h, 0)
	for i = 1, 6 do
		local a = i * math.pi / 3
		local frond = Kit.Box(model, Vector3.new(0.3, 0.2, 5 * s), CFrame.new(top) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -2.2 * s) * CFrame.Angles(math.rad(-25), 0, 0), v.Color, { Material = Enum.Material.Grass, Collide = false, Name = "Leaves" })
		frond.Size = Vector3.new(1.4 * s, 0.2, 5 * s)
		body(frond)
	end
	for i = 1, 3 do
		Kit.Ball(model, Vector3.new(0.8, 0.8, 0.8) * s, CFrame.new(top + Vector3.new(math.cos(i * 2) * 0.6, -0.6, math.sin(i * 2) * 0.6) * s), Color3.fromRGB(120, 85, 50), { Collide = false, Name = "Fruit" })
	end
end

shapes.Dead = function(model, v, s, rng)
	local h = 8 * s
	trunk(model, h, 1.1 * s, v.Color)
	for i = 1, 3 do
		local a = i * 2.1 + rng:NextNumber(0, 0.5)
		body(Kit.Box(model, Vector3.new(0.5, 3.2, 0.5) * s, CFrame.new(0, h * (0.45 + i * 0.13), 0) * CFrame.Angles(0, a, math.rad(50)) * CFrame.new(0, 1.4 * s, 0), v.Color, { Material = Enum.Material.Wood, Collide = false }))
	end
end

shapes.Crystal = function(model, v, s, rng)
	local material = MATERIALS[v.Material or ""] or Enum.Material.Glass
	for i = 1, 5 do
		local tall = rng:NextNumber(2.5, 6) * s
		local a = i * 1.26
		local r = if i == 1 then 0 else rng:NextNumber(0.9, 1.8) * s
		local shard = Kit.Box(model, Vector3.new(1.3 * s, tall, 1.3 * s), CFrame.new(math.cos(a) * r, tall * 0.42, math.sin(a) * r) * CFrame.Angles(rng:NextNumber(-0.35, 0.35), a, rng:NextNumber(-0.35, 0.35)), if i % 2 == 0 then (v.Accent or v.Color) else v.Color, { Material = material, Transparency = 0.15, Name = "Shard" })
		body(shard)
		if v.Glow and i == 1 then
			Kit.Light(shard, v.Color, 14, 1.4)
		end
	end
	Kit.Ball(model, Vector3.new(3.2, 1.2, 3.2) * s, CFrame.new(0, 0.3, 0), C.DarkStone, { Material = Enum.Material.Rock })
end

shapes.Cloud = function(model, v, s, rng)
	trunk(model, 6 * s, 0.9 * s, v.Accent or C.Metal)
	for i = 1, 5 do
		local a = i * 1.25
		body(Kit.Ball(model, Vector3.new(3.8, 3, 3.8) * s * rng:NextNumber(0.85, 1.15), CFrame.new(math.cos(a) * 1.8 * s, 7 * s + rng:NextNumber(-0.5, 0.8) * s, math.sin(a) * 1.8 * s), v.Color, { Material = Enum.Material.SmoothPlastic, Collide = false, Transparency = 0.1, Name = "Leaves" }))
	end
end

shapes.Boulder = function(model, v, s, rng)
	for i = 1, 3 do
		local size = rng:NextNumber(2.4, 3.6) * s * (if i == 1 then 1.3 else 0.8)
		local rock = Kit.Ball(model, Vector3.new(size * 1.2, size * 0.85, size), CFrame.new((i - 2) * 1.2 * s, size * 0.35, rng:NextNumber(-0.6, 0.6) * s) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), Kit.Shade(v.Color, rng:NextNumber(-0.1, 0.05)), { Material = Enum.Material.Rock, Name = "Rock" })
		body(rock)
		if v.Glow and i == 1 and v.Accent then
			Kit.Particles(rock, "Sparkle", v.Accent, 3)
		end
	end
end

shapes.Ore = function(model, v, s, rng)
	local main = Kit.Ball(model, Vector3.new(4.4, 3.2, 3.8) * s, CFrame.new(0, 1.2 * s, 0), v.Color, { Material = Enum.Material.Rock, Name = "Rock" })
	body(main)
	for i = 1, 6 do
		local a = i * 1.05 + rng:NextNumber(0, 0.4)
		local gem = Kit.Box(model, Vector3.new(0.8, 0.8, 0.8) * s * rng:NextNumber(0.8, 1.3), CFrame.new(math.cos(a) * 1.8 * s, (1 + rng:NextNumber(0, 1.2)) * s, math.sin(a) * 1.6 * s) * CFrame.Angles(a, a * 2, 0), v.Accent or C.Copper, { Material = if v.Glow then Enum.Material.Neon else Enum.Material.Metal, Collide = false, Name = "Vein" })
		body(gem)
	end
	if v.Glow then
		Kit.Light(main, v.Accent or v.Color, 10, 0.8)
	end
end

shapes.Mound = function(model, v, s, rng)
	local m = Kit.Ball(model, Vector3.new(3.4, 1.2, 3.4) * s, CFrame.new(0, 0.2, 0), v.Color, { Material = Enum.Material.Ground, Collide = false, Name = "Mound" })
	body(m)
	for i = 1, 3 do
		Kit.Box(model, Vector3.new(0.15, 0.9, 0.15), CFrame.new(math.cos(i * 2) * 0.6, 0.8, math.sin(i * 2) * 0.6) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), 0, rng:NextNumber(-0.4, 0.4)), C.DarkWood, { Collide = false })
	end
end

-- Build a node model. seed makes each instance look slightly different.
function Nodes.Build(def: any, seed: number?): Model
	local v = def.Visual
	local model = Kit.Model(def.Id)
	local rng = Random.new(seed or 1)
	local s = (v.Size or 1) * rng:NextNumber(0.9, 1.1)
	local shape = shapes[v.Shape] or shapes.Boulder
	shape(model, v, s, rng)
	-- Invisible hit volume for targeting.
	local extents = model:GetExtentsSize()
	local hit = Kit.Box(model, Vector3.new(math.max(3, extents.X * 0.7), math.max(3, extents.Y), math.max(3, extents.Z * 0.7)), CFrame.new(0, math.max(3, extents.Y) / 2, 0), C.White, { Transparency = 1, Collide = false, Name = "Hit", Shadow = false })
	hit.CanQuery = true
	model:SetAttribute("Node", def.Id)
	model:SetAttribute("Kind", def.Kind)
	return model
end

-- A stump/rubble left behind while a node respawns.
function Nodes.Remains(def: any): Model
	local model = Kit.Model(def.Id .. "_remains")
	if def.Kind == "Tree" then
		Kit.Cyl(model, 1, 1.6 * (def.Visual.Size or 1), CFrame.new(0, 0.5, 0), def.Visual.Accent or C.DarkWood, { Material = Enum.Material.Wood })
	else
		for i = 1, 3 do
			Kit.Ball(model, Vector3.new(0.9, 0.6, 0.9), CFrame.new((i - 2) * 0.9, 0.2, (i % 2) * 0.5), def.Visual.Color, { Material = Enum.Material.Rock, Collide = false })
		end
	end
	return model
end

return Nodes

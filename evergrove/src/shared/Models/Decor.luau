-- Decoration builders: fences, paths, lights, nature, water, furniture,
-- structures, statues and seasonal pieces.

local Kit = require(script.Parent.Kit)
local C = Kit.C

local D = {}

-- Fences & gates -----------------------------------------------------------------------------

local FENCE = {
	Wood = { C.Wood, Enum.Material.Wood },
	Picket = { C.White, Enum.Material.SmoothPlastic },
	Stone = { C.Stone, Enum.Material.Cobblestone },
	Iron = { C.Black, Enum.Material.Metal },
	Hedge = { C.DarkLeaf, Enum.Material.Grass },
	Bamboo = { Color3.fromRGB(170, 190, 100), Enum.Material.Wood },
	Crystal = { Color3.fromRGB(160, 220, 255), Enum.Material.Glass },
}

D.Fence = function(model, w, _d, h, params)
	local style = params.Style or "Wood"
	local look = FENCE[style] or FENCE.Wood
	local color, material = look[1], look[2]
	if style == "Hedge" or style == "Stone" then
		local wall = Kit.Box(model, Vector3.new(w, h * 0.85, 1.4), CFrame.new(0, h * 0.425, 0), color, { Paint = true, Mat = true, Material = material })
		wall.Name = "Wall"
		if style == "Hedge" then
			Kit.Ball(model, Vector3.new(w * 0.5, 1.4, 1.6), CFrame.new(-w * 0.2, h * 0.85, 0), color, { Material = material, Collide = false })
			Kit.Ball(model, Vector3.new(w * 0.5, 1.4, 1.6), CFrame.new(w * 0.2, h * 0.85, 0), color, { Material = material, Collide = false })
		end
		return
	end
	for _, x in { -w / 2 + 0.25, w / 2 - 0.25 } do
		local post = Kit.Box(model, Vector3.new(0.5, h, 0.5), CFrame.new(x, h / 2, 0), color, { Paint = true, Mat = true, Material = material })
		if style == "Crystal" then
			post.Transparency = 0.2
			Kit.Ball(model, Vector3.new(0.7, 0.7, 0.7), CFrame.new(x, h + 0.2, 0), Color3.fromRGB(200, 240, 255), { Material = Enum.Material.Neon, Collide = false })
		end
	end
	if style == "Picket" then
		for i = 0, 4 do
			local x = -w / 2 + 0.4 + i * (w - 0.8) / 4
			Kit.Box(model, Vector3.new(0.35, h * 0.9, 0.2), CFrame.new(x, h * 0.45, 0), color, { Paint = true })
			Kit.Wedge(model, Vector3.new(0.35, 0.3, 0.2), CFrame.new(x, h * 0.9 + 0.15, 0), color, { Paint = true, Collide = false })
		end
		Kit.Box(model, Vector3.new(w, 0.25, 0.15), CFrame.new(0, h * 0.65, 0.12), color, { Paint = true })
	elseif style == "Bamboo" then
		for i = 0, 5 do
			Kit.Cyl(model, h * (0.8 + (i % 2) * 0.15), 0.35, CFrame.new(-w / 2 + 0.35 + i * (w - 0.7) / 5, h * 0.45, 0), color, { Paint = true })
		end
	else
		for _, y in { h * 0.35, h * 0.75 } do
			Kit.Box(model, Vector3.new(w, 0.3, 0.25), CFrame.new(0, y, 0), color, { Paint = true, Mat = true, Material = material })
		end
		if style == "Iron" then
			for i = 1, 5 do
				Kit.Box(model, Vector3.new(0.12, h * 0.9, 0.12), CFrame.new(-w / 2 + i * w / 6, h * 0.45, 0), color, { Paint = true })
			end
		end
	end
end

D.Gate = function(model, w, _d, h)
	for _, x in { -w / 2 + 0.25, w / 2 - 0.25 } do
		Kit.Box(model, Vector3.new(0.5, h + 0.5, 0.5), CFrame.new(x, (h + 0.5) / 2, 0), C.DarkWood, { Paint = true })
	end
	local door = Kit.Box(model, Vector3.new(w * 0.8, h * 0.7, 0.2), CFrame.new(0, h * 0.45, 0), C.Wood, { Paint = true, Collide = false, Name = "Door" })
	door.Transparency = 0
	Kit.Box(model, Vector3.new(w * 0.8, 0.2, 0.25), CFrame.new(0, h * 0.45, 0) * CFrame.Angles(0, 0, math.rad(35)), C.DarkWood, { Collide = false })
end

-- Paths ----------------------------------------------------------------------------------------

local PATH = {
	Dirt = { Color3.fromRGB(140, 105, 70), Enum.Material.Ground },
	Gravel = { Color3.fromRGB(170, 165, 155), Enum.Material.Pebble },
	Cobble = { Color3.fromRGB(135, 135, 130), Enum.Material.Cobblestone },
	Brick = { Color3.fromRGB(170, 85, 65), Enum.Material.Brick },
	Plank = { C.Plank, Enum.Material.WoodPlanks },
	Sand = { Color3.fromRGB(230, 215, 175), Enum.Material.Sand },
	Crystal = { Color3.fromRGB(150, 210, 245), Enum.Material.Glass },
	Flowers = { Color3.fromRGB(110, 170, 80), Enum.Material.Grass },
}

D.Path = function(model, w, d, h, params)
	local style = params.Style or "Dirt"
	if style == "Stepping" then
		for i = 0, 2 do
			Kit.Cyl(model, 0.3, 1.4, CFrame.new(-w * 0.25 + (i % 2) * w * 0.4, 0.15, -d * 0.3 + i * d * 0.3), C.Stone, { Collide = false })
		end
		return
	end
	local look = PATH[style] or PATH.Dirt
	local tile = Kit.Box(model, Vector3.new(w, h, d), CFrame.new(0, h / 2, 0), look[1], { Paint = true, Material = look[2], Collide = false })
	tile.Name = "Tile"
	if style == "Crystal" then
		tile.Transparency = 0.1
		Kit.Light(tile, Color3.fromRGB(150, 220, 255), 6, 0.3)
	elseif style == "Flowers" then
		for i = 1, 5 do
			Kit.Ball(model, Vector3.new(0.35, 0.35, 0.35), CFrame.new((i % 3 - 1) * 1.1, h + 0.1, (i - 3) * 0.6), Color3.fromHSV((i * 0.17) % 1, 0.6, 1), { Collide = false })
		end
	elseif style == "Sand" then
		for i = -1, 1 do
			Kit.Box(model, Vector3.new(w * 0.9, 0.05, 0.15), CFrame.new(0, h + 0.02, i * d * 0.25), Kit.Shade(look[1], -0.08), { Collide = false })
		end
	end
end

-- Lighting --------------------------------------------------------------------------------------

D.Lamp = function(model, _w, _d, h, params)
	local style = params.Style or "Lantern"
	local warm = Color3.fromRGB(255, 200, 120)
	if style == "Torch" then
		Kit.Cyl(model, h * 0.85, 0.35, CFrame.new(0, h * 0.42, 0), C.DarkWood)
		local flame = Kit.Ball(model, Vector3.new(0.6, 0.8, 0.6), CFrame.new(0, h * 0.9, 0), Color3.fromRGB(255, 160, 60), { Material = Enum.Material.Neon, Collide = false, Name = "Bulb" })
		Kit.Particles(flame, "Fire", nil, 8)
		Kit.Light(flame, Color3.fromRGB(255, 160, 80), 14, 1.4)
		return
	elseif style == "Jar" then
		local jar = Kit.Cyl(model, h * 0.7, 1, CFrame.new(0, h * 0.35, 0), C.Glass, { Material = Enum.Material.Glass, Transparency = 0.3, Name = "Bulb" })
		Kit.Particles(jar, "Sparkle", Color3.fromRGB(255, 240, 120), 5)
		Kit.Light(jar, Color3.fromRGB(255, 240, 140), 10, 0.8)
		return
	elseif style == "Stone" then
		Kit.Box(model, Vector3.new(1.4, h * 0.4, 1.4), CFrame.new(0, h * 0.2, 0), C.Stone, { Material = Enum.Material.Slate })
		local box = Kit.Box(model, Vector3.new(1.2, h * 0.3, 1.2), CFrame.new(0, h * 0.55, 0), warm, { Material = Enum.Material.Neon, Name = "Bulb" })
		Kit.Wedge(model, Vector3.new(1.8, 0.6, 0.9), CFrame.new(0, h * 0.8, -0.45) * CFrame.Angles(0, math.rad(180), 0), C.Stone, { Material = Enum.Material.Slate })
		Kit.Wedge(model, Vector3.new(1.8, 0.6, 0.9), CFrame.new(0, h * 0.8, 0.45), C.Stone, { Material = Enum.Material.Slate })
		Kit.Light(box, warm, 12, 1)
		return
	elseif style == "Paper" then
		Kit.Box(model, Vector3.new(0.25, h * 0.7, 0.25), CFrame.new(0, h * 0.35, 0), C.DarkWood)
		local lantern = Kit.Ball(model, Vector3.new(1.3, 1.6, 1.3), CFrame.new(0, h * 0.82, 0), Color3.fromRGB(230, 70, 60), { Paint = true, Material = Enum.Material.Neon, Collide = false, Name = "Bulb" })
		Kit.Light(lantern, Color3.fromRGB(255, 150, 120), 12, 1)
		return
	end
	-- Post lamps: Lantern, Street, Crystal, Star, Winter
	local postColor = if style == "Street" then C.Black else C.DarkWood
	Kit.Box(model, Vector3.new(0.4, h * 0.85, 0.4), CFrame.new(0, h * 0.42, 0), postColor, { Paint = true })
	Kit.Box(model, Vector3.new(1, 0.4, 1), CFrame.new(0, 0.2, 0), postColor)
	local bulbColor = warm
	if style == "Crystal" then
		bulbColor = Color3.fromRGB(150, 220, 255)
	elseif style == "Star" then
		bulbColor = Color3.fromRGB(220, 200, 255)
	elseif style == "Winter" then
		bulbColor = Color3.fromRGB(180, 220, 255)
	end
	local bulb
	if style == "Star" or style == "Crystal" then
		bulb = Kit.Box(model, Vector3.new(1, 1, 1), CFrame.new(0, h * 0.95, 0) * CFrame.Angles(math.rad(45), math.rad(45), 0), bulbColor, { Material = Enum.Material.Neon, Collide = false, Name = "Bulb" })
		Kit.Particles(bulb, "Sparkle", bulbColor, 3)
	else
		bulb = Kit.Box(model, Vector3.new(1.1, 1.3, 1.1), CFrame.new(0, h * 0.92, 0), bulbColor, { Material = Enum.Material.Neon, Transparency = 0.1, Collide = false, Name = "Bulb" })
		Kit.Box(model, Vector3.new(1.4, 0.25, 1.4), CFrame.new(0, h * 0.92 + 0.8, 0), postColor, { Collide = false })
	end
	Kit.Light(bulb, bulbColor, 18, 1.2, style == "Street")
end

D.StringLights = function(model, w, _d, h, params)
	for _, x in { -w / 2 + 0.2, w / 2 - 0.2 } do
		Kit.Box(model, Vector3.new(0.3, h, 0.3), CFrame.new(x, h / 2, 0), C.DarkWood)
	end
	local count = 8
	for i = 0, count do
		local t = i / count
		local x = -w / 2 + t * w
		local sag = math.sin(t * math.pi) * 1.2
		local color = if params.Lanterns then Color3.fromRGB(230, 70, 50) else Color3.fromHSV((i * 0.13) % 1, 0.45, 1)
		local bulb = Kit.Ball(model, Vector3.new(if params.Lanterns then 0.8 else 0.4, if params.Lanterns then 1 else 0.4, if params.Lanterns then 0.8 else 0.4), CFrame.new(x, h - 0.2 - sag, 0), color, { Material = Enum.Material.Neon, Collide = false, Name = "Bulb", Paint = params.Lanterns })
		if i % 2 == 0 then
			Kit.Light(bulb, color, 7, 0.5)
		end
	end
end

D.Campfire = function(model, w)
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		Kit.Ball(model, Vector3.new(0.8, 0.6, 0.8), CFrame.new(math.cos(a) * w * 0.35, 0.3, math.sin(a) * w * 0.35), C.DarkStone)
	end
	for i = 0, 2 do
		Kit.CylFlat(model, w * 0.55, 0.35, CFrame.new(0, 0.35, 0) * CFrame.Angles(0, i * math.pi / 3, math.rad(12)), C.DarkWood, "X", { Collide = false })
	end
	local fire = Kit.Ball(model, Vector3.new(0.9, 1, 0.9), CFrame.new(0, 0.8, 0), Color3.fromRGB(255, 140, 50), { Material = Enum.Material.Neon, Collide = false, Transparency = 0.3, Name = "Bulb" })
	Kit.Particles(fire, "Fire", nil, 16)
	Kit.Particles(fire, "Smoke", Color3.fromRGB(120, 120, 120), 2)
	Kit.Light(fire, Color3.fromRGB(255, 150, 70), 18, 1.6, true)
end

-- Nature -------------------------------------------------------------------------------------------

local TREE = {
	Round = { C.Wood, Color3.fromRGB(80, 150, 70) },
	Blossom = { C.DarkWood, Color3.fromRGB(245, 175, 200) },
	Cone = { C.DarkWood, Color3.fromRGB(45, 110, 60) },
	Palm = { Color3.fromRGB(170, 135, 90), Color3.fromRGB(90, 170, 80) },
	Maple = { C.DarkWood, Color3.fromRGB(220, 100, 40) },
	Bonsai = { C.DarkWood, Color3.fromRGB(70, 130, 70) },
}

D.DecorTree = function(model, w, _d, h, params)
	local style = params.Style or "Round"
	local look = TREE[style] or TREE.Round
	if style == "Bonsai" then
		Kit.Box(model, Vector3.new(w * 0.7, 0.6, w * 0.5), CFrame.new(0, 0.3, 0), Color3.fromRGB(120, 70, 50))
		Kit.Box(model, Vector3.new(0.3, 1.2, 0.3), CFrame.new(0.1, 1, 0) * CFrame.Angles(0, 0, math.rad(20)), look[1])
		Kit.Ball(model, Vector3.new(1.6, 0.8, 1.4), CFrame.new(-0.3, 1.8, 0), look[2], { Material = Enum.Material.Grass, Collide = false, Name = "Leaves" }):SetAttribute("Foliage", true)
		Kit.Ball(model, Vector3.new(1, 0.6, 1), CFrame.new(0.6, 1.5, 0.2), look[2], { Material = Enum.Material.Grass, Collide = false, Name = "Leaves" }):SetAttribute("Foliage", true)
		return
	end
	local trunkH = if style == "Palm" then h * 0.85 else h * 0.45
	local trunk = Kit.Cyl(model, trunkH, if style == "Palm" then 0.9 else 1.3, CFrame.new(0, trunkH / 2, 0), look[1], { Material = Enum.Material.Wood })
	trunk.Name = "Trunk"
	if style == "Cone" then
		for i = 0, 2 do
			local size = w * (1.1 - i * 0.28)
			local leaf = Kit.Wedge(model, Vector3.new(size, h * 0.3, size / 2), CFrame.new(0, trunkH * 0.6 + i * h * 0.2 + h * 0.15, -size / 4), look[2], { Material = Enum.Material.Grass, Collide = false, Name = "Leaves" })
			leaf:SetAttribute("Foliage", true)
			local back = Kit.Wedge(model, Vector3.new(size, h * 0.3, size / 2), CFrame.new(0, trunkH * 0.6 + i * h * 0.2 + h * 0.15, size / 4) * CFrame.Angles(0, math.rad(180), 0), look[2], { Material = Enum.Material.Grass, Collide = false, Name = "Leaves" })
			back:SetAttribute("Foliage", true)
		end
	elseif style == "Palm" then
		for i = 0, 5 do
			local frond = Kit.Box(model, Vector3.new(w * 0.7, 0.2, 1.2), CFrame.new(0, trunkH, 0) * CFrame.Angles(0, i * math.pi / 3, math.rad(-20)) * CFrame.new(w * 0.3, 0, 0), look[2], { Material = Enum.Material.Grass, Collide = false, Name = "Leaves" })
			frond:SetAttribute("Foliage", true)
		end
		for i = 0, 2 do
			Kit.Ball(model, Vector3.new(0.7, 0.7, 0.7), CFrame.new(math.cos(i * 2) * 0.5, trunkH - 0.5, math.sin(i * 2) * 0.5), Color3.fromRGB(110, 80, 50), { Collide = false })
		end
	else
		local crown = Kit.Ball(model, Vector3.new(w * 1.1, h * 0.55, w * 1.1), CFrame.new(0, trunkH + h * 0.2, 0), look[2], { Material = Enum.Material.Grass, Collide = false, Name = "Leaves" })
		crown:SetAttribute("Foliage", true)
		local side = Kit.Ball(model, Vector3.new(w * 0.7, h * 0.4, w * 0.7), CFrame.new(w * 0.35, trunkH + h * 0.1, w * 0.1), look[2], { Material = Enum.Material.Grass, Collide = false, Name = "Leaves" })
		side:SetAttribute("Foliage", true)
		if style == "Blossom" then
			Kit.Particles(crown, "Sparkle", Color3.fromRGB(255, 200, 220), 2)
		end
	end
end

D.Bush = function(model, w, _d, h)
	for i = 0, 2 do
		local ball = Kit.Ball(model, Vector3.new(w * (0.8 - i * 0.1), h * 0.8, w * (0.8 - i * 0.1)), CFrame.new((i - 1) * 0.5, h * 0.4 + i * 0.2, (i % 2) * 0.3), C.Leaf, { Paint = true, Material = Enum.Material.Grass, Collide = false })
		ball:SetAttribute("Foliage", true)
	end
end

D.FlowerBed = function(model, w, d, h, params)
	if not params.Tall then
		Kit.Box(model, Vector3.new(w, 0.6, d), CFrame.new(0, 0.3, 0), C.Soil, { Material = Enum.Material.Ground })
		Kit.Box(model, Vector3.new(w + 0.3, 0.7, 0.3), CFrame.new(0, 0.35, -d / 2), C.Wood, { Collide = false })
		Kit.Box(model, Vector3.new(w + 0.3, 0.7, 0.3), CFrame.new(0, 0.35, d / 2), C.Wood, { Collide = false })
	end
	local count = if params.Tall then 3 else 10
	for i = 1, count do
		local x = (((i * 37) % 100) / 100 - 0.5) * (w - 0.8)
		local z = (((i * 53) % 100) / 100 - 0.5) * (d - 0.8)
		local stem = if params.Tall then h * 0.9 else 1
		Kit.Box(model, Vector3.new(0.15, stem, 0.15), CFrame.new(x, 0.5 + stem / 2, z), C.DarkLeaf, { Collide = false })
		local bloom = Kit.Ball(model, Vector3.new(if params.Tall then 1.4 else 0.6, if params.Tall then 0.4 else 0.5, if params.Tall then 1.4 else 0.6), CFrame.new(x, 0.5 + stem + 0.2, z), if params.Tall then Color3.fromRGB(250, 200, 40) else Color3.fromRGB(230, 90, 120), { Paint = not params.Tall, Collide = false })
		bloom.Name = "Bloom"
	end
end

D.Rocks = function(model, w)
	Kit.Ball(model, Vector3.new(w * 0.8, w * 0.5, w * 0.7), CFrame.new(-0.3, w * 0.2, 0), C.Stone, { Paint = true, Mat = true, Material = Enum.Material.Slate })
	Kit.Ball(model, Vector3.new(w * 0.5, w * 0.35, w * 0.5), CFrame.new(w * 0.3, w * 0.15, 0.4), C.Stone, { Paint = true, Mat = true, Material = Enum.Material.Slate })
end

D.MushroomRing = function(model, w, _d, _h, params)
	local count = if params.Small then 3 else 8
	for i = 0, count - 1 do
		local a = i / count * math.pi * 2
		local r = if params.Small then 0.8 else w * 0.38
		local x, z = math.cos(a) * r, math.sin(a) * r
		Kit.Cyl(model, 0.8, 0.3, CFrame.new(x, 0.4, z), C.Cream, { Collide = false })
		local cap = Kit.Ball(model, Vector3.new(1, 0.5, 1), CFrame.new(x, 0.85, z), if params.Glow then Color3.fromRGB(100, 230, 255) else Color3.fromRGB(210, 50, 50), { Collide = false, Name = "Cap" })
		if params.Glow then
			cap.Material = Enum.Material.Neon
			if i == 0 then
				Kit.Light(cap, Color3.fromRGB(100, 230, 255), 10, 0.8)
			end
		end
	end
end

D.HayBale = function(model, w, _d, h)
	Kit.CylFlat(model, w * 0.9, h * 0.95, CFrame.new(0, h * 0.47, 0), C.Straw, "X", { Material = Enum.Material.Fabric })
end

D.LogPile = function(model, w)
	for i = 0, 2 do
		Kit.CylFlat(model, w * 0.95, 0.9, CFrame.new(0, 0.45, (i - 1) * 0.9), C.DarkWood, "X", { Material = Enum.Material.Wood })
	end
	for i = 0, 1 do
		Kit.CylFlat(model, w * 0.95, 0.9, CFrame.new(0, 1.2, (i - 0.5) * 0.9), C.Wood, "X", { Material = Enum.Material.Wood })
	end
end

D.Grass = function(model, w, _d, h)
	for i = 1, 6 do
		local blade = Kit.Wedge(model, Vector3.new(0.15, h * (0.6 + (i % 3) * 0.2), 0.5), CFrame.new((i - 3.5) * w * 0.12, h * 0.4, ((i * 7) % 5 - 2) * 0.3) * CFrame.Angles(0, i, 0), Color3.fromRGB(110, 170, 70), { Collide = false })
		blade:SetAttribute("Foliage", true)
	end
end

-- Water features ---------------------------------------------------------------------------------------

D.Fountain = function(model, w, _d, h, params)
	local basin = Kit.Cyl(model, 1.4, w, CFrame.new(0, 0.7, 0), C.Stone, { Paint = true, Mat = true, Material = Enum.Material.Marble })
	basin.Name = "Basin"
	local water = Kit.Cyl(model, 0.1, w * 0.85, CFrame.new(0, 1.3, 0), C.Water, { Material = Enum.Material.Glass, Transparency = 0.2, Collide = false })
	water:SetAttribute("Water", "Decor")
	Kit.Cyl(model, h * 0.55, 1, CFrame.new(0, h * 0.28, 0), C.Stone, { Paint = true, Mat = true, Material = Enum.Material.Marble })
	Kit.Cyl(model, 0.5, w * 0.45, CFrame.new(0, h * 0.58, 0), C.Stone, { Paint = true, Mat = true, Material = Enum.Material.Marble })
	local spout = Kit.Ball(model, Vector3.new(0.6, 0.6, 0.6), CFrame.new(0, h * 0.75, 0), C.Stone, { Collide = false })
	local spray = Kit.Particles(spout, "Water", nil, if params.Big then 40 else 20)
	spray.SpreadAngle = Vector2.new(20, 20)
end

D.Birdbath = function(model, w, _d, h)
	Kit.Cyl(model, h * 0.7, 0.6, CFrame.new(0, h * 0.35, 0), C.Stone, { Paint = true, Mat = true })
	Kit.Cyl(model, 0.4, w * 0.8, CFrame.new(0, h * 0.75, 0), C.Stone, { Paint = true, Mat = true })
	Kit.Cyl(model, 0.1, w * 0.65, CFrame.new(0, h * 0.8, 0), C.Water, { Material = Enum.Material.Glass, Transparency = 0.2, Collide = false })
end

D.Waterfall = function(model, w, d, h)
	Kit.Ball(model, Vector3.new(w, h, d * 0.7), CFrame.new(0, h * 0.4, d * 0.2), C.DarkStone, { Material = Enum.Material.Slate })
	local fall = Kit.Box(model, Vector3.new(w * 0.35, h * 0.8, 0.3), CFrame.new(0, h * 0.4, -d * 0.12), C.Water, { Material = Enum.Material.Glass, Transparency = 0.3, Collide = false, Name = "Fall" })
	fall:SetAttribute("Anim", "Belt")
	Kit.Cyl(model, 0.4, w * 0.9, CFrame.new(0, 0.2, -d * 0.2), C.Water, { Material = Enum.Material.Glass, Transparency = 0.25, Collide = false })
	Kit.Particles(fall, "Smoke", Color3.fromRGB(230, 240, 255), 4)
end

-- Furniture ---------------------------------------------------------------------------------------------

D.Bench = function(model, w, d, _h, params)
	if params.Log then
		Kit.CylFlat(model, w * 0.95, 1, CFrame.new(0, 0.6, 0), C.Wood, "X", { Material = Enum.Material.Wood })
		return
	end
	local color = if params.Moon then Color3.fromRGB(70, 80, 160) else C.Plank
	Kit.Box(model, Vector3.new(w * 0.9, 0.3, d * 0.45), CFrame.new(0, 1.6, 0), color, { Paint = true, Mat = true })
	Kit.Box(model, Vector3.new(w * 0.9, 1.2, 0.25), CFrame.new(0, 2.4, d * 0.22), color, { Paint = true, Mat = true })
	for _, x in { -w * 0.4, w * 0.4 } do
		Kit.Box(model, Vector3.new(0.3, 1.6, d * 0.45), CFrame.new(x, 0.8, 0), if params.Moon then C.Gold else C.Black)
	end
	if params.Moon then
		local moon = Kit.Ball(model, Vector3.new(1.2, 1.2, 0.3), CFrame.new(0, 3.3, d * 0.22), Color3.fromRGB(240, 235, 200), { Material = Enum.Material.Neon, Collide = false })
		Kit.Light(moon, Color3.fromRGB(220, 220, 255), 10, 0.6)
	end
end

D.Table = function(model, w, d, _h, params)
	if params.Picnic then
		Kit.Box(model, Vector3.new(w * 0.9, 0.3, d * 0.4), CFrame.new(0, 2.4, 0), C.Plank, { Paint = true })
		for _, z in { -d * 0.38, d * 0.38 } do
			Kit.Box(model, Vector3.new(w * 0.9, 0.25, d * 0.18), CFrame.new(0, 1.4, z), C.Plank, { Paint = true })
		end
		for _, x in { -w * 0.35, w * 0.35 } do
			Kit.Box(model, Vector3.new(0.3, 2.4, d * 0.9), CFrame.new(x, 1.2, 0), C.Wood)
		end
		Kit.Box(model, Vector3.new(w * 0.5, 0.05, d * 0.35), CFrame.new(0, 2.56, 0), C.Red, { Collide = false })
		return
	end
	Kit.Cyl(model, 0.25, w * 0.8, CFrame.new(0, 2.4, 0), C.White, { Paint = true })
	Kit.Cyl(model, 2.2, 0.3, CFrame.new(0, 1.2, 0), C.Black)
	Kit.Cyl(model, 0.2, 1.2, CFrame.new(0, 0.1, 0), C.Black)
end

D.Swing = function(model, w, d, h)
	for _, x in { -w / 2 + 0.3, w / 2 - 0.3 } do
		Kit.Box(model, Vector3.new(0.35, h, 0.35), CFrame.new(x, h / 2, 0), C.Wood, { Paint = true })
	end
	Kit.Box(model, Vector3.new(w, 0.4, 0.4), CFrame.new(0, h, 0), C.Wood, { Paint = true })
	local seat = Kit.Box(model, Vector3.new(w * 0.6, 0.3, d * 0.6), CFrame.new(0, 1.8, 0), C.Plank, { Collide = false, Name = "Seat" })
	seat:SetAttribute("Anim", "Swing")
	for _, x in { -w * 0.28, w * 0.28 } do
		Kit.Box(model, Vector3.new(0.1, h - 2, 0.1), CFrame.new(x, 1.8 + (h - 2) / 2, 0), C.DarkWood, { Collide = false })
	end
end

D.Hammock = function(model, w, _d, h)
	for _, x in { -w / 2 + 0.4, w / 2 - 0.4 } do
		Kit.Cyl(model, h, 0.6, CFrame.new(x, h / 2, 0), C.Wood)
	end
	Kit.Box(model, Vector3.new(w * 0.7, 0.2, 2), CFrame.new(0, h * 0.4, 0), Color3.fromRGB(220, 110, 90), { Paint = true, Material = Enum.Material.Fabric, Collide = false })
end

D.Chair = function(model, w, d, _h, params)
	Kit.Box(model, Vector3.new(w * 0.7, 0.3, d * 0.7), CFrame.new(0, 1.6, 0), C.Wood, { Paint = true })
	Kit.Box(model, Vector3.new(w * 0.7, 1.8, 0.25), CFrame.new(0, 2.6, d * 0.33), C.Wood, { Paint = true })
	if params.Rocking then
		for _, x in { -w * 0.3, w * 0.3 } do
			Kit.Box(model, Vector3.new(0.2, 0.25, d * 0.95), CFrame.new(x, 0.2, 0), C.DarkWood)
			Kit.Box(model, Vector3.new(0.2, 1.4, 0.2), CFrame.new(x, 0.9, 0), C.DarkWood)
		end
	else
		for _, x in { -w * 0.3, w * 0.3 } do
			for _, z in { -d * 0.3, d * 0.3 } do
				Kit.Box(model, Vector3.new(0.2, 1.5, 0.2), CFrame.new(x, 0.75, z), C.DarkWood)
			end
		end
	end
end

D.Parasol = function(model, w, _d, h, params)
	Kit.Cyl(model, h, 0.25, CFrame.new(0, h / 2, 0), C.White)
	local count = 8
	for i = 0, count - 1 do
		local color = if params.Stripes and i % 2 == 0 then C.White else Color3.fromRGB(230, 80, 70)
		local panel = Kit.Wedge(model, Vector3.new(1.3, 0.8, w * 0.7), CFrame.new(0, h - 0.2, 0) * CFrame.Angles(0, i / count * math.pi * 2, 0) * CFrame.new(0, 0, -w * 0.35), color, { Paint = not (params.Stripes and i % 2 == 0), Material = Enum.Material.Fabric, Collide = false })
		panel.Name = "Canopy"
	end
end

D.Grill = function(model, w, _d, h)
	Kit.Ball(model, Vector3.new(w * 0.8, h * 0.4, w * 0.8), CFrame.new(0, h * 0.65, 0), C.Black)
	for i = 0, 2 do
		local a = i / 3 * math.pi * 2
		Kit.Box(model, Vector3.new(0.2, h * 0.6, 0.2), CFrame.new(math.cos(a) * w * 0.25, h * 0.3, math.sin(a) * w * 0.25), C.DarkMetal)
	end
	local coals = Kit.Cyl(model, 0.1, w * 0.6, CFrame.new(0, h * 0.8, 0), Color3.fromRGB(255, 90, 30), { Material = Enum.Material.Neon, Collide = false })
	Kit.Particles(coals, "Smoke", Color3.fromRGB(200, 200, 200), 1)
end

D.Barrel = function(model, w, _d, h)
	Kit.Cyl(model, h * 0.9, w * 0.7, CFrame.new(0, h * 0.45, 0), C.Wood, { Paint = true, Material = Enum.Material.Wood })
	for _, y in { h * 0.2, h * 0.7 } do
		Kit.Cyl(model, 0.2, w * 0.72, CFrame.new(0, y, 0), C.DarkMetal, { Collide = false })
	end
end

D.Crates = function(model, w, _d, h)
	Kit.Box(model, Vector3.new(w * 0.7, h * 0.45, w * 0.7), CFrame.new(-0.2, h * 0.225, 0), C.Plank, { Paint = true, Material = Enum.Material.WoodPlanks })
	Kit.Box(model, Vector3.new(w * 0.5, h * 0.4, w * 0.5), CFrame.new(0.3, h * 0.65, 0.1) * CFrame.Angles(0, math.rad(20), 0), C.Plank, { Paint = true, Material = Enum.Material.WoodPlanks })
end

D.Wagon = function(model, w, d, h)
	Kit.Box(model, Vector3.new(w * 0.9, h * 0.35, d * 0.8), CFrame.new(0, h * 0.5, 0), C.Wood, { Paint = true, Mat = true })
	for _, x in { -w * 0.3, w * 0.3 } do
		for _, z in { -d * 0.45, d * 0.45 } do
			Kit.CylFlat(model, 0.3, h * 0.55, CFrame.new(x, h * 0.28, z), C.DarkWood, "Z", { Collide = false })
		end
	end
	Kit.Box(model, Vector3.new(w * 0.5, 0.2, 0.2), CFrame.new(-w * 0.65, h * 0.4, 0), C.DarkWood)
	for i = 0, 2 do
		Kit.Ball(model, Vector3.new(1, 1, 1), CFrame.new(-0.8 + i * 0.8, h * 0.8, 0), Color3.fromRGB(240, 130, 30), { Collide = false })
	end
end

D.MilkCans = function(model, w)
	for i = 0, 2 do
		local x = (i - 1) * w * 0.28
		Kit.Cyl(model, 1.6, 0.8, CFrame.new(x, 0.8, (i % 2) * 0.3), C.Metal, { Material = Enum.Material.Metal })
		Kit.Cyl(model, 0.3, 0.5, CFrame.new(x, 1.75, (i % 2) * 0.3), C.Metal, { Material = Enum.Material.Metal })
	end
end

D.Birdhouse = function(model, _w, _d, h)
	Kit.Box(model, Vector3.new(0.3, h * 0.7, 0.3), CFrame.new(0, h * 0.35, 0), C.DarkWood)
	Kit.Box(model, Vector3.new(1.4, 1.4, 1.4), CFrame.new(0, h * 0.8, 0), Color3.fromRGB(90, 160, 200), { Paint = true })
	Kit.Roof(model, 1.4, 1.4, h * 0.8 + 0.7, 0.7, C.Red, 0.2)
	Kit.Cyl(model, 0.1, 0.5, CFrame.new(0, h * 0.82, -0.72) * CFrame.Angles(math.rad(90), 0, 0), C.Black, { Collide = false })
end

-- Structures --------------------------------------------------------------------------------------------

D.Gazebo = function(model, w, d, h)
	Kit.Cyl(model, 0.6, w, CFrame.new(0, 0.3, 0), C.Plank, { Mat = true })
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		Kit.Box(model, Vector3.new(0.5, h * 0.6, 0.5), CFrame.new(math.cos(a) * w * 0.44, h * 0.3 + 0.3, math.sin(a) * d * 0.44), C.White, { Paint = true })
	end
	for i = 0, 5 do
		local panel = Kit.Wedge(model, Vector3.new(w * 0.52, h * 0.35, w * 0.46), CFrame.new(0, h * 0.78, 0) * CFrame.Angles(0, i / 6 * math.pi * 2, 0) * CFrame.new(0, 0, -w * 0.23), Color3.fromRGB(110, 150, 120), { Collide = false })
		panel.Name = "Roof"
	end
end

D.Pergola = function(model, w, d, h)
	for _, x in { -w / 2 + 0.3, w / 2 - 0.3 } do
		for _, z in { -d / 2 + 0.3, d / 2 - 0.3 } do
			Kit.Box(model, Vector3.new(0.45, h, 0.45), CFrame.new(x, h / 2, z), C.Wood, { Paint = true, Collide = false })
		end
	end
	for i = 0, 5 do
		Kit.Box(model, Vector3.new(0.25, 0.4, d + 1), CFrame.new(-w / 2 + i * w / 5, h, 0), C.Wood, { Paint = true, Collide = false })
	end
	for i = 0, 7 do
		local leaf = Kit.Ball(model, Vector3.new(1.4, 0.6, 1.4), CFrame.new(((i * 31) % 10 / 10 - 0.5) * w, h + 0.3, ((i * 17) % 10 / 10 - 0.5) * d), C.Leaf, { Material = Enum.Material.Grass, Collide = false })
		leaf:SetAttribute("Foliage", true)
	end
end

D.Arch = function(model, w, _d, h, params)
	local color = if params.Torii then Color3.fromRGB(200, 50, 40) elseif params.Stars then Color3.fromRGB(60, 60, 130) else C.White
	for _, x in { -w / 2 + 0.3, w / 2 - 0.3 } do
		Kit.Box(model, Vector3.new(0.5, h, 0.5), CFrame.new(x, h / 2, 0), color, { Paint = true, Collide = false })
	end
	if params.Torii then
		Kit.Box(model, Vector3.new(w + 1.5, 0.6, 0.7), CFrame.new(0, h, 0), C.Black, { Collide = false })
		Kit.Box(model, Vector3.new(w, 0.4, 0.5), CFrame.new(0, h - 1.2, 0), color, { Collide = false })
		return
	end
	for i = 0, 8 do
		local a = i / 8 * math.pi
		local seg = Kit.Box(model, Vector3.new(0.5, 0.5, 0.5), CFrame.new(-math.cos(a) * (w / 2 - 0.3), h + math.sin(a) * w * 0.35, 0), color, { Paint = true, Collide = false })
		if params.Flowers then
			Kit.Ball(model, Vector3.new(0.6, 0.6, 0.6), seg.CFrame * CFrame.new(0, 0, -0.3), if params.Blossom then Color3.fromRGB(250, 180, 205) else Color3.fromHSV((i * 0.11) % 1, 0.5, 1), { Collide = false })
		elseif params.Stars then
			local star = Kit.Ball(model, Vector3.new(0.4, 0.4, 0.4), seg.CFrame * CFrame.new(0, 0.4, 0), Color3.fromRGB(240, 230, 150), { Material = Enum.Material.Neon, Collide = false })
			if i == 4 then
				Kit.Light(star, Color3.fromRGB(200, 190, 255), 16, 1)
			end
		end
	end
end

D.Bridge = function(model, w, d)
	for i = 0, 5 do
		local t = i / 5
		local y = 0.4 + math.sin(t * math.pi) * 1.4
		Kit.Box(model, Vector3.new(w / 6 + 0.1, 0.35, d * 0.8), CFrame.new(-w / 2 + (i + 0.5) * w / 6, y, 0), C.Plank, { Paint = true, Mat = true })
	end
	for _, z in { -d * 0.42, d * 0.42 } do
		for i = 0, 3 do
			local t = i / 3
			local y = 0.4 + math.sin(t * math.pi) * 1.4
			Kit.Box(model, Vector3.new(0.25, 1.8, 0.25), CFrame.new(-w / 2 + t * w, y + 0.9, z), C.DarkWood, { Collide = false })
		end
		Kit.Box(model, Vector3.new(w, 0.2, 0.2), CFrame.new(0, 2.9, z), C.DarkWood, { Collide = false })
	end
end

D.Shed = function(model, w, d, h)
	Kit.Box(model, Vector3.new(w, h * 0.6, d), CFrame.new(0, h * 0.3, 0), C.Wood, { Paint = true, Mat = true })
	Kit.Roof(model, w, d, h * 0.6, h * 0.4, C.DarkStone, 0.5)
	Kit.Box(model, Vector3.new(w * 0.4, h * 0.5, 0.2), CFrame.new(0, h * 0.25, -d / 2 - 0.05), C.DarkWood)
end

D.Doghouse = function(model, w, d, h)
	Kit.Box(model, Vector3.new(w * 0.9, h * 0.55, d * 0.9), CFrame.new(0, h * 0.28, 0), Color3.fromRGB(190, 60, 50), { Paint = true })
	Kit.Roof(model, w * 0.9, d * 0.9, h * 0.55, h * 0.45, C.DarkWood, 0.2)
	Kit.Box(model, Vector3.new(w * 0.4, h * 0.35, 0.1), CFrame.new(0, h * 0.18, -d * 0.46), C.Black)
end

D.Treehouse = function(model, w, d, h)
	local trunk = Kit.Cyl(model, h * 0.9, 2.5, CFrame.new(0, h * 0.45, 0), C.Wood, { Material = Enum.Material.Wood })
	trunk.Name = "Trunk"
	Kit.Box(model, Vector3.new(w * 0.8, 0.5, d * 0.8), CFrame.new(0, h * 0.5, 0), C.Plank, { Paint = true })
	Kit.Box(model, Vector3.new(w * 0.6, h * 0.2, d * 0.6), CFrame.new(0, h * 0.6, 0), C.Plank, { Paint = true, Mat = true })
	Kit.Roof(model, w * 0.6, d * 0.6, h * 0.7, h * 0.15, C.Red, 0.4)
	local crown = Kit.Ball(model, Vector3.new(w * 1.2, h * 0.35, d * 1.2), CFrame.new(0, h * 0.92, 0), C.Leaf, { Material = Enum.Material.Grass, Collide = false, Name = "Leaves" })
	crown:SetAttribute("Foliage", true)
	for i = 0, math.floor(h * 0.5 / 1.5) do
		Kit.Box(model, Vector3.new(1.6, 0.2, 0.3), CFrame.new(0, 1 + i * 1.5, -1.4), C.DarkWood, { Name = "Rung" })
	end
end

D.MushroomHouse = function(model, w, _d, h)
	Kit.Cyl(model, h * 0.5, w * 0.55, CFrame.new(0, h * 0.25, 0), C.Cream, { Material = Enum.Material.Plaster })
	local cap = Kit.Ball(model, Vector3.new(w * 1.05, h * 0.6, w * 1.05), CFrame.new(0, h * 0.62, 0), Color3.fromRGB(210, 60, 60), { Paint = true })
	cap.Name = "Cap"
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		Kit.Ball(model, Vector3.new(0.9, 0.5, 0.9), CFrame.new(math.cos(a) * w * 0.3, h * 0.82, math.sin(a) * w * 0.3), C.White, { Collide = false })
	end
	Kit.Box(model, Vector3.new(1.4, 2.4, 0.2), CFrame.new(0, 1.2, -w * 0.28), C.DarkWood)
	local window = Kit.Cyl(model, 0.2, 0.9, CFrame.new(w * 0.2, h * 0.35, -w * 0.26) * CFrame.Angles(math.rad(90), 0, 0), Color3.fromRGB(255, 220, 140), { Material = Enum.Material.Neon, Collide = false })
	Kit.Light(window, Color3.fromRGB(255, 210, 140), 10, 0.6)
end

D.GearSculpture = function(model, w, _d, h)
	for i = 0, 1 do
		local gear = Kit.CylFlat(model, 0.6, h * (0.7 - i * 0.25), CFrame.new(i * w * 0.3 - w * 0.1, h * (0.4 + i * 0.25), 0), C.Copper, "Z", { Material = Enum.Material.Metal })
		gear:SetAttribute("Anim", "Spinner")
		for t = 0, 7 do
			Kit.Box(model, Vector3.new(0.5, 0.8, 0.6), gear.CFrame * CFrame.Angles(t / 8 * math.pi * 2, 0, 0) * CFrame.new(0, h * (0.35 - i * 0.125), 0), C.Copper, { Collide = false })
		end
	end
end

D.Pipes = function(model, w, d, h)
	Kit.CylFlat(model, w, 0.8, CFrame.new(0, h * 0.3, 0), C.Metal, "X", { Paint = true, Material = Enum.Material.Metal })
	Kit.Cyl(model, h * 0.7, 0.8, CFrame.new(w * 0.4, h * 0.35, 0), C.Metal, { Paint = true, Material = Enum.Material.Metal })
	Kit.Cyl(model, 0.4, 1.2, CFrame.new(w * 0.4, h * 0.7, 0), C.Copper, { Collide = false })
	local valve = Kit.CylFlat(model, 0.2, 1, CFrame.new(-w * 0.1, h * 0.3, -d * 0.3), C.Red, "Z", { Collide = false })
	valve.Name = "Valve"
end

D.OrbPedestal = function(model, w, _d, h)
	Kit.Cyl(model, h * 0.6, w * 0.5, CFrame.new(0, h * 0.3, 0), Color3.fromRGB(50, 50, 90), { Material = Enum.Material.Marble })
	local orb = Kit.Ball(model, Vector3.new(1.6, 1.6, 1.6), CFrame.new(0, h * 0.8, 0), Color3.fromRGB(170, 140, 255), { Material = Enum.Material.Neon, Collide = false, Name = "Orb" })
	orb:SetAttribute("Anim", "Float")
	Kit.Light(orb, Color3.fromRGB(170, 140, 255), 16, 1)
	Kit.Particles(orb, "Sparkle", Color3.fromRGB(200, 180, 255), 4)
end

-- Statues & trophies ---------------------------------------------------------------------------------

D.Statue = function(model, w, d, h, params)
	local shape = params.Shape or "Gnome"
	local gold = params.Gold == true
	local base = if gold then C.Gold else C.Stone
	local mat = if gold then Enum.Material.Foil else Enum.Material.Marble
	Kit.Box(model, Vector3.new(w * 0.8, h * 0.15, d * 0.8), CFrame.new(0, h * 0.075, 0), C.DarkStone, { Mat = true })
	local function p(size: Vector3, cf: CFrame, color: Color3?, ball: boolean?)
		local part = if ball then Kit.Ball(model, size, cf, color or base, { Paint = not gold, Mat = not gold, Material = mat }) else Kit.Box(model, size, cf, color or base, { Paint = not gold, Mat = not gold, Material = mat })
		return part
	end
	local y0 = h * 0.15
	if shape == "Gnome" then
		p(Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, y0 + 0.7, 0), Color3.fromRGB(60, 110, 200), true)
		p(Vector3.new(0.8, 0.8, 0.8), CFrame.new(0, y0 + 1.5, 0), Color3.fromRGB(240, 200, 170), true)
		Kit.Wedge(model, Vector3.new(0.9, 1.2, 0.9), CFrame.new(0, y0 + 2.3, 0), Color3.fromRGB(200, 40, 40), { Collide = false })
		p(Vector3.new(0.7, 0.5, 0.3), CFrame.new(0, y0 + 1.25, -0.35), C.White, true)
	elseif shape == "Chicken" then
		p(Vector3.new(1.6, 1.4, 2), CFrame.new(0, y0 + 0.9, 0), nil, true)
		p(Vector3.new(0.9, 0.9, 0.9), CFrame.new(0, y0 + 1.9, -0.7), nil, true)
		p(Vector3.new(0.3, 0.3, 0.5), CFrame.new(0, y0 + 1.8, -1.2), C.Gold)
	elseif shape == "Cow" then
		p(Vector3.new(w * 0.4, h * 0.35, h * 0.55), CFrame.new(0, y0 + h * 0.4, 0) * CFrame.Angles(0, math.rad(90), 0))
		p(Vector3.new(1.2, 1.2, 1.2), CFrame.new(-w * 0.35, y0 + h * 0.55, 0))
		for _, x in { -w * 0.15, w * 0.15 } do
			for _, z in { -0.5, 0.5 } do
				p(Vector3.new(0.4, h * 0.25, 0.4), CFrame.new(x, y0 + h * 0.12, z))
			end
		end
	elseif shape == "Angel" then
		p(Vector3.new(1.2, h * 0.45, 1), CFrame.new(0, y0 + h * 0.3, 0))
		p(Vector3.new(0.9, 0.9, 0.9), CFrame.new(0, y0 + h * 0.62, 0), nil, true)
		for _, side in { -1, 1 } do
			p(Vector3.new(0.2, h * 0.35, 1.2), CFrame.new(side * 0.8, y0 + h * 0.45, 0.3) * CFrame.Angles(0, 0, side * math.rad(-20)))
		end
	elseif shape == "Lion" then
		p(Vector3.new(1.2, 1.4, 1.8), CFrame.new(0, y0 + 0.9, 0.2))
		p(Vector3.new(1.4, 1.4, 1.2), CFrame.new(0, y0 + 1.9, -0.5), nil, true)
	elseif shape == "Pumpkin" then
		local pumpkin = p(Vector3.new(w * 0.7, h * 0.45, w * 0.7), CFrame.new(0, y0 + h * 0.3, 0), if gold then C.Gold else Color3.fromRGB(240, 130, 30), true)
		pumpkin.Name = "Pumpkin"
		p(Vector3.new(0.3, 0.6, 0.3), CFrame.new(0, y0 + h * 0.58, 0), Color3.fromRGB(100, 140, 60))
	elseif shape == "Fish" then
		p(Vector3.new(0.3, h * 0.4, 0.3), CFrame.new(0, y0 + h * 0.2, 0))
		p(Vector3.new(w * 0.7, h * 0.3, 0.4), CFrame.new(0, y0 + h * 0.55, 0) * CFrame.Angles(0, 0, math.rad(15)), nil, true)
		Kit.Wedge(model, Vector3.new(0.3, 0.9, 0.9), CFrame.new(w * 0.4, y0 + h * 0.6, 0) * CFrame.Angles(0, math.rad(90), 0), base, { Material = mat, Collide = false })
	elseif shape == "Farmer" then
		p(Vector3.new(w * 0.3, h * 0.35, w * 0.2), CFrame.new(0, y0 + h * 0.35, 0))
		p(Vector3.new(w * 0.2, w * 0.2, w * 0.2), CFrame.new(0, y0 + h * 0.62, 0), nil, true)
		Kit.Cyl(model, 0.2, w * 0.45, CFrame.new(0, y0 + h * 0.72, 0), base, { Material = mat, Collide = false })
		p(Vector3.new(0.3, h * 0.55, 0.3), CFrame.new(w * 0.22, y0 + h * 0.4, 0))
	end
	if gold then
		Kit.Particles(model.PrimaryPart :: BasePart, "Sparkle", Color3.fromRGB(255, 220, 100), 2)
	end
end

D.Plaque = function(model, w, _d, h)
	Kit.Box(model, Vector3.new(0.3, h * 0.6, 0.3), CFrame.new(0, h * 0.3, 0), C.DarkWood)
	local plaque = Kit.Box(model, Vector3.new(w * 0.7, h * 0.35, 0.2), CFrame.new(0, h * 0.75, 0), C.DarkWood)
	Kit.Ball(model, Vector3.new(1, 1, 0.2), CFrame.new(0, h * 0.78, -0.12), Color3.fromRGB(60, 110, 220), { Collide = false })
	Kit.Label(plaque, "1st", Enum.NormalId.Back, C.Gold)
end

-- Seasonal -----------------------------------------------------------------------------------------------

D.Snowman = function(model, _w, _d, h)
	local snow = Color3.fromRGB(250, 252, 255)
	Kit.Ball(model, Vector3.new(2.4, 2.2, 2.4), CFrame.new(0, 1.1, 0), snow, { Material = Enum.Material.Snow })
	Kit.Ball(model, Vector3.new(1.8, 1.6, 1.8), CFrame.new(0, 2.7, 0), snow, { Material = Enum.Material.Snow })
	Kit.Ball(model, Vector3.new(1.3, 1.2, 1.3), CFrame.new(0, 3.9, 0), snow, { Material = Enum.Material.Snow })
	Kit.Wedge(model, Vector3.new(0.2, 0.2, 0.7), CFrame.new(0, 3.9, -0.8) * CFrame.Angles(0, math.rad(180), 0), Color3.fromRGB(240, 120, 30), { Collide = false })
	Kit.Cyl(model, 0.8, 1, CFrame.new(0, h * 0.95, 0), C.Black, { Collide = false })
	Kit.Box(model, Vector3.new(1.8, 0.35, 1.8), CFrame.new(0, 3.3, 0), Color3.fromRGB(200, 40, 40), { Collide = false })
end

D.WinterPine = function(model, w, d, h)
	D.DecorTree(model, w, d, h, { Style = "Cone" })
	for i = 0, 11 do
		local a = i * 2.3
		local y = h * 0.3 + (i / 12) * h * 0.55
		local r = w * 0.45 * (1 - i / 14)
		local light = Kit.Ball(model, Vector3.new(0.35, 0.35, 0.35), CFrame.new(math.cos(a) * r, y, math.sin(a) * r), Color3.fromHSV((i * 0.19) % 1, 0.6, 1), { Material = Enum.Material.Neon, Collide = false, Paint = i % 3 == 0 })
		light.Name = "Bulb"
	end
	local star = Kit.Ball(model, Vector3.new(0.9, 0.9, 0.9), CFrame.new(0, h + 0.2, 0), C.Gold, { Material = Enum.Material.Neon, Collide = false })
	Kit.Light(star, Color3.fromRGB(255, 230, 150), 16, 1)
end

D.PumpkinPile = function(model, w)
	for i, size in { 1.6, 1.2, 1 } do
		local a = i * 2.1
		local pumpkin = Kit.Ball(model, Vector3.new(size * 1.2, size, size * 1.2), CFrame.new(math.cos(a) * w * 0.2, size / 2 + (if i == 3 then 1 else 0), math.sin(a) * w * 0.2), Color3.fromRGB(240, 130, 30))
		Kit.Box(model, Vector3.new(0.15, 0.4, 0.15), pumpkin.CFrame * CFrame.new(0, size / 2, 0), Color3.fromRGB(100, 140, 60), { Collide = false })
	end
end

D.EggBasket = function(model, w)
	Kit.Cyl(model, 0.8, w * 0.7, CFrame.new(0, 0.4, 0), C.Straw, { Material = Enum.Material.Fabric })
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		Kit.Ball(model, Vector3.new(0.45, 0.6, 0.45), CFrame.new(math.cos(a) * 0.5, 0.95, math.sin(a) * 0.5), Color3.fromHSV(i / 6, 0.35, 1), { Collide = false })
	end
end

return D

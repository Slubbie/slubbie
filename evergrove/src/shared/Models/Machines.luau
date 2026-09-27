-- Artisan machine models. Each machine has a recognisable silhouette and a few
-- tagged parts the client animates while it's working:
--   Spinner  rotates (mill sails, juicer blades, drums)
--   Bubbler  emits bubbles/steam
--   Glow     brightens when working
--   Press    bobs up and down

local Kit = require(script.Parent.Kit)
local C = Kit.C

local M = {}

local function tag(part: BasePart, name: string)
	part:SetAttribute("Anim", name)
	return part
end

local function legs(model: Model, w: number, d: number, height: number, color: Color3)
	for _, x in { -w / 2 + 0.3, w / 2 - 0.3 } do
		for _, z in { -d / 2 + 0.3, d / 2 - 0.3 } do
			Kit.Box(model, Vector3.new(0.35, height, 0.35), CFrame.new(x, height / 2, z), color)
		end
	end
end

local styles = {}

styles.preserves_jar = function(model, w, _d, h)
	local jar = Kit.Cyl(model, h * 0.7, w * 0.6, CFrame.new(0, h * 0.35, 0), C.Glass, { Material = Enum.Material.Glass, Transparency = 0.35 })
	jar.Name = "Jar"
	tag(Kit.Cyl(model, h * 0.45, w * 0.5, CFrame.new(0, h * 0.25, 0), Color3.fromRGB(200, 60, 80), { Collide = false }), "Glow")
	Kit.Cyl(model, 0.4, w * 0.66, CFrame.new(0, h * 0.72, 0), C.Gold)
	tag(Kit.Cyl(model, 0.2, w * 0.3, CFrame.new(0, h * 0.8, 0), C.Metal, { Collide = false }), "Bubbler")
end

styles.fermenter = function(model, w, d, h)
	Kit.CylFlat(model, d * 0.8, h * 0.6, CFrame.new(0, h * 0.4, 0), C.Wood, "Z")
	for _, z in { -d * 0.3, 0, d * 0.3 } do
		Kit.CylFlat(model, 0.2, h * 0.62, CFrame.new(0, h * 0.4, z), C.DarkMetal, "Z", { Collide = false })
	end
	legs(model, w * 0.7, d * 0.6, h * 0.12, C.DarkWood)
	tag(Kit.CylFlat(model, 0.4, 0.3, CFrame.new(0, h * 0.25, -d * 0.42), C.Copper, "Z", { Collide = false }), "Bubbler")
end

styles.juicer = function(model, w, _d, h)
	Kit.Box(model, Vector3.new(w * 0.7, h * 0.4, w * 0.7), CFrame.new(0, h * 0.2, 0), C.White, { Paint = true })
	Kit.Cyl(model, h * 0.45, w * 0.55, CFrame.new(0, h * 0.62, 0), Color3.fromRGB(255, 180, 60), { Material = Enum.Material.Glass, Transparency = 0.3 })
	tag(Kit.Box(model, Vector3.new(w * 0.4, 0.15, 0.3), CFrame.new(0, h * 0.5, 0), C.Metal, { Collide = false }), "Spinner")
end

styles.dehydrator = function(model, w, d, h)
	Kit.Box(model, Vector3.new(w * 0.85, h * 0.8, d * 0.85), CFrame.new(0, h * 0.4, 0), C.Cream, { Paint = true })
	for i = 1, 4 do
		Kit.Box(model, Vector3.new(w * 0.7, 0.12, 0.2), CFrame.new(0, i * h * 0.16, -d * 0.43), C.DarkMetal, { Collide = false })
	end
	tag(Kit.Box(model, Vector3.new(w * 0.3, 0.2, 0.1), CFrame.new(0, h * 0.75, -d * 0.44), Color3.fromRGB(255, 120, 40), { Material = Enum.Material.Neon, Collide = false }), "Glow")
end

styles.mill = function(model, w, d, h)
	local body = Kit.Cyl(model, h * 0.7, w * 0.7, CFrame.new(0, h * 0.35, 0), C.Stone, { Paint = true, Mat = true })
	body.Material = Enum.Material.Cobblestone
	Kit.Ball(model, Vector3.new(w * 0.75, h * 0.3, w * 0.75), CFrame.new(0, h * 0.7, 0), C.DarkWood)
	local hub = tag(Kit.Cyl(model, 0.6, 1, CFrame.new(0, h * 0.62, -d * 0.42) * CFrame.Angles(math.rad(90), 0, 0), C.DarkWood), "Spinner")
	for i = 0, 3 do
		local sail = Kit.Box(model, Vector3.new(0.8, h * 0.45, 0.1), CFrame.new(0, h * 0.62, -d * 0.46) * CFrame.Angles(0, 0, i * math.pi / 2) * CFrame.new(0, h * 0.24, 0), C.Cream, { Collide = false })
		sail:SetAttribute("Anim", "SpinnerChild")
	end
	hub.Name = "Hub"
end

styles.cheese_press = function(model, w, _d, h)
	Kit.Box(model, Vector3.new(w * 0.8, h * 0.25, w * 0.8), CFrame.new(0, h * 0.125, 0), C.Wood)
	Kit.Cyl(model, h * 0.25, w * 0.55, CFrame.new(0, h * 0.37, 0), Color3.fromRGB(250, 220, 120))
	for _, x in { -w * 0.35, w * 0.35 } do
		Kit.Box(model, Vector3.new(0.3, h * 0.9, 0.3), CFrame.new(x, h * 0.45, 0), C.DarkWood)
	end
	Kit.Box(model, Vector3.new(w * 0.8, 0.3, 0.4), CFrame.new(0, h * 0.9, 0), C.DarkWood)
	tag(Kit.Box(model, Vector3.new(w * 0.5, 0.35, w * 0.5), CFrame.new(0, h * 0.62, 0), C.Metal), "Press")
end

styles.butter_churn = function(model, w, _d, h)
	Kit.Cyl(model, h * 0.65, w * 0.5, CFrame.new(0, h * 0.33, 0), C.Wood, { Paint = true })
	for i = 1, 3 do
		Kit.Cyl(model, 0.15, w * 0.52, CFrame.new(0, i * h * 0.18, 0), C.DarkMetal, { Collide = false })
	end
	tag(Kit.Cyl(model, h * 0.5, 0.25, CFrame.new(0, h * 0.85, 0), C.Plank, { Collide = false }), "Press")
end

styles.mayo_mixer = function(model, w, _d, h)
	Kit.Box(model, Vector3.new(w * 0.7, h * 0.3, w * 0.7), CFrame.new(0, h * 0.15, 0), C.White, { Paint = true })
	Kit.Ball(model, Vector3.new(w * 0.6, h * 0.45, w * 0.6), CFrame.new(0, h * 0.5, 0), C.Metal, { Material = Enum.Material.Metal })
	tag(Kit.Cyl(model, h * 0.4, 0.2, CFrame.new(0, h * 0.75, 0), C.DarkMetal, { Collide = false }), "Spinner")
end

styles.loom = function(model, w, d, h)
	for _, x in { -w * 0.45, w * 0.45 } do
		Kit.Box(model, Vector3.new(0.4, h * 0.9, 0.4), CFrame.new(x, h * 0.45, -d * 0.3), C.Wood)
		Kit.Box(model, Vector3.new(0.4, h * 0.6, 0.4), CFrame.new(x, h * 0.3, d * 0.3), C.Wood)
	end
	Kit.Box(model, Vector3.new(w * 0.9, 0.3, 0.3), CFrame.new(0, h * 0.88, -d * 0.3), C.DarkWood)
	Kit.Box(model, Vector3.new(w * 0.8, h * 0.5, 0.05), CFrame.new(0, h * 0.55, -d * 0.1), Color3.fromRGB(200, 120, 160), { Collide = false, Paint = true })
	tag(Kit.Box(model, Vector3.new(w * 0.85, 0.35, 0.35), CFrame.new(0, h * 0.4, d * 0.1), C.DarkWood, { Collide = false }), "Press")
end

styles.oil_press = function(model, w, _d, h)
	Kit.Cyl(model, h * 0.35, w * 0.75, CFrame.new(0, h * 0.18, 0), C.DarkStone)
	Kit.Cyl(model, h * 0.6, 0.5, CFrame.new(0, h * 0.6, 0), C.DarkWood)
	tag(Kit.CylFlat(model, w * 0.9, 0.35, CFrame.new(0, h * 0.85, 0), C.Wood, "X", { Collide = false }), "Spinner")
	Kit.Cyl(model, 0.4, 0.8, CFrame.new(w * 0.35, h * 0.1, -w * 0.3), Color3.fromRGB(220, 190, 60), { Collide = false })
end

styles.smoker = function(model, w, d, h)
	Kit.Box(model, Vector3.new(w * 0.8, h * 0.6, d * 0.8), CFrame.new(0, h * 0.3, 0), C.DarkMetal, { Paint = true })
	Kit.Wedge(model, Vector3.new(w * 0.8, h * 0.2, d * 0.8), CFrame.new(0, h * 0.7, 0), C.DarkMetal)
	local stack = tag(Kit.Cyl(model, h * 0.4, 0.6, CFrame.new(w * 0.2, h * 0.9, d * 0.2), C.Black), "Bubbler")
	Kit.Particles(stack, "Smoke", Color3.fromRGB(180, 180, 180), 1).Enabled = false
	tag(Kit.Box(model, Vector3.new(w * 0.4, 0.3, 0.1), CFrame.new(0, h * 0.2, -d * 0.41), Color3.fromRGB(255, 100, 30), { Material = Enum.Material.Neon, Collide = false }), "Glow")
end

styles.syrup_boiler = function(model, w, _d, h)
	Kit.Box(model, Vector3.new(w * 0.8, h * 0.35, w * 0.8), CFrame.new(0, h * 0.18, 0), C.Stone, { Material = Enum.Material.Brick })
	Kit.Cyl(model, h * 0.35, w * 0.7, CFrame.new(0, h * 0.52, 0), C.Copper, { Material = Enum.Material.Metal })
	tag(Kit.Cyl(model, 0.1, w * 0.6, CFrame.new(0, h * 0.7, 0), Color3.fromRGB(180, 110, 40), { Collide = false }), "Bubbler")
	tag(Kit.Box(model, Vector3.new(w * 0.3, 0.3, 0.1), CFrame.new(0, h * 0.12, -w * 0.41), Color3.fromRGB(255, 120, 40), { Material = Enum.Material.Neon, Collide = false }), "Glow")
end

styles.canning_station = function(model, w, d, h)
	Kit.Box(model, Vector3.new(w * 0.95, 0.4, d * 0.8), CFrame.new(0, h * 0.5, 0), C.Metal, { Material = Enum.Material.Metal })
	legs(model, w * 0.9, d * 0.7, h * 0.5, C.DarkMetal)
	for i = -2, 2 do
		Kit.Cyl(model, 1, 0.7, CFrame.new(i * 0.9, h * 0.5 + 0.7, 0), Color3.fromRGB(200, 200, 205), { Collide = false })
	end
	tag(Kit.Box(model, Vector3.new(1, 1.2, 1), CFrame.new(-w * 0.35, h * 0.9, 0), C.DarkMetal, { Collide = false }), "Press")
end

styles.perfumery = function(model, w, _d, h)
	Kit.Box(model, Vector3.new(w * 0.8, h * 0.2, w * 0.8), CFrame.new(0, h * 0.1, 0), C.DarkWood)
	local flask = Kit.Ball(model, Vector3.new(w * 0.55, w * 0.55, w * 0.55), CFrame.new(0, h * 0.4, 0), Color3.fromRGB(240, 170, 220), { Material = Enum.Material.Glass, Transparency = 0.3 })
	tag(flask, "Glow")
	Kit.Cyl(model, h * 0.35, 0.3, CFrame.new(0, h * 0.75, 0), C.Glass, { Material = Enum.Material.Glass, Transparency = 0.2, Collide = false })
	Kit.CylFlat(model, w * 0.5, 0.2, CFrame.new(w * 0.2, h * 0.9, 0) * CFrame.Angles(0, 0, math.rad(-25)), C.Copper, "X", { Collide = false })
	tag(Kit.Box(model, Vector3.new(0.3, 0.3, 0.3), CFrame.new(w * 0.4, h * 0.75, 0), C.Glass, { Collide = false }), "Bubbler")
end

styles.flower_press = function(model, w, _d, h)
	Kit.Box(model, Vector3.new(w * 0.8, h * 0.3, w * 0.8), CFrame.new(0, h * 0.15, 0), C.Plank, { Paint = true })
	tag(Kit.Box(model, Vector3.new(w * 0.8, h * 0.2, w * 0.8), CFrame.new(0, h * 0.45, 0), C.Wood), "Press")
	Kit.Cyl(model, h * 0.5, 0.25, CFrame.new(0, h * 0.75, 0), C.DarkMetal, { Collide = false })
	Kit.Box(model, Vector3.new(w * 0.5, 0.05, w * 0.5), CFrame.new(0, h * 0.32, 0), Color3.fromRGB(240, 130, 170), { Collide = false })
end

styles.furnace = function(model, w, _d, h)
	local body = Kit.Box(model, Vector3.new(w * 0.85, h * 0.75, w * 0.85), CFrame.new(0, h * 0.375, 0), C.DarkStone, { Mat = true })
	body.Material = Enum.Material.Brick
	Kit.Wedge(model, Vector3.new(w * 0.85, h * 0.15, w * 0.85), CFrame.new(0, h * 0.82, 0), C.DarkStone)
	local mouth = tag(Kit.Box(model, Vector3.new(w * 0.4, h * 0.25, 0.1), CFrame.new(0, h * 0.3, -w * 0.43), Color3.fromRGB(255, 110, 30), { Material = Enum.Material.Neon, Collide = false }), "Glow")
	Kit.Light(mouth, Color3.fromRGB(255, 130, 60), 12, 0).Name = "WorkLight"
	local chimney = tag(Kit.Box(model, Vector3.new(0.8, h * 0.3, 0.8), CFrame.new(w * 0.2, h * 0.95, w * 0.2), C.Stone), "Bubbler")
	Kit.Particles(chimney, "Smoke", Color3.fromRGB(150, 150, 150), 2).Enabled = false
end

styles.crystal_refinery = function(model, w, d, h)
	Kit.Box(model, Vector3.new(w * 0.9, h * 0.25, d * 0.9), CFrame.new(0, h * 0.12, 0), C.DarkMetal)
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2 + math.pi / 4
		Kit.Box(model, Vector3.new(0.4, h * 0.6, 0.4), CFrame.new(math.cos(a) * w * 0.35, h * 0.55, math.sin(a) * d * 0.35), C.Metal)
	end
	local crystal = tag(Kit.Box(model, Vector3.new(1.2, h * 0.45, 1.2), CFrame.new(0, h * 0.6, 0) * CFrame.Angles(0, math.rad(45), 0), Color3.fromRGB(120, 220, 255), { Material = Enum.Material.Glass, Transparency = 0.1, Collide = false }), "Spinner")
	Kit.Light(crystal, Color3.fromRGB(120, 220, 255), 14, 1)
	Kit.Particles(crystal, "Sparkle", Color3.fromRGB(170, 240, 255), 3)
end

styles.seed_maker = function(model, w, _d, h)
	Kit.Box(model, Vector3.new(w * 0.8, h * 0.55, w * 0.8), CFrame.new(0, h * 0.28, 0), Color3.fromRGB(110, 160, 80), { Paint = true })
	Kit.Wedge(model, Vector3.new(w * 0.6, h * 0.3, w * 0.5), CFrame.new(0, h * 0.7, 0), C.Metal)
	tag(Kit.CylFlat(model, 0.3, w * 0.4, CFrame.new(w * 0.42, h * 0.35, 0), C.DarkMetal, "X", { Collide = false }), "Spinner")
	Kit.Box(model, Vector3.new(w * 0.3, 0.2, 0.1), CFrame.new(0, h * 0.4, -w * 0.41), Color3.fromRGB(120, 255, 120), { Material = Enum.Material.Neon, Collide = false })
end

styles.honey_extractor = function(model, w, _d, h)
	Kit.Cyl(model, h * 0.7, w * 0.7, CFrame.new(0, h * 0.35, 0), C.Metal, { Material = Enum.Material.Metal })
	Kit.Cyl(model, 0.2, w * 0.72, CFrame.new(0, h * 0.72, 0), C.DarkMetal)
	tag(Kit.CylFlat(model, 0.5, 0.2, CFrame.new(w * 0.4, h * 0.85, 0), C.DarkMetal, "X", { Collide = false }), "Spinner")
	Kit.Cyl(model, 0.4, 0.6, CFrame.new(0, h * 0.12, -w * 0.42), Color3.fromRGB(240, 180, 40), { Collide = false })
end

styles.alchemy_still = function(model, w, _d, h)
	Kit.Box(model, Vector3.new(w * 0.8, h * 0.15, w * 0.8), CFrame.new(0, h * 0.08, 0), C.DarkWood)
	local bulb = tag(Kit.Ball(model, Vector3.new(w * 0.6, w * 0.6, w * 0.6), CFrame.new(0, h * 0.4, 0), Color3.fromRGB(180, 120, 255), { Material = Enum.Material.Glass, Transparency = 0.25 }), "Glow")
	Kit.Light(bulb, Color3.fromRGB(190, 140, 255), 12, 0.8)
	Kit.Cyl(model, h * 0.4, 0.3, CFrame.new(0, h * 0.8, 0), C.Glass, { Material = Enum.Material.Glass, Collide = false })
	tag(Kit.Ball(model, Vector3.new(0.6, 0.6, 0.6), CFrame.new(0, h, 0), Color3.fromRGB(220, 180, 255), { Material = Enum.Material.Neon, Collide = false }), "Bubbler")
end

styles.grand_kitchen = function(model, w, d, h)
	local body = Kit.Box(model, Vector3.new(w * 0.95, h * 0.6, d * 0.9), CFrame.new(0, h * 0.3, 0), Color3.fromRGB(210, 215, 220), { Paint = true, Mat = true })
	body.Material = Enum.Material.DiamondPlate
	Kit.Box(model, Vector3.new(w * 0.95, 0.4, d * 0.9), CFrame.new(0, h * 0.62, 0), C.DarkMetal)
	for i = -1, 1 do
		local stack = tag(Kit.Cyl(model, h * 0.4, 0.9, CFrame.new(i * w * 0.3, h * 0.82, d * 0.2), C.Metal), "Bubbler")
		Kit.Particles(stack, "Smoke", Color3.fromRGB(235, 235, 235), 2).Enabled = false
	end
	for i = 0, 5 do
		Kit.Box(model, Vector3.new(0.9, 0.9, 0.9), CFrame.new(-w * 0.4 + i * w * 0.16, h * 0.62 + 0.65, -d * 0.3), Color3.fromRGB(190, 140, 90), { Collide = false, Name = "Box" }):SetAttribute("Anim", "Conveyor")
	end
	tag(Kit.Box(model, Vector3.new(w * 0.4, 0.3, 0.1), CFrame.new(0, h * 0.45, -d * 0.46), Color3.fromRGB(120, 220, 255), { Material = Enum.Material.Neon, Collide = false }), "Glow")
end

M.Machine = function(model, w, d, h, params)
	local style = styles[params.Style]
	if style then
		style(model, w, d, h)
	else
		Kit.Box(model, Vector3.new(w * 0.8, h * 0.8, d * 0.8), CFrame.new(0, h * 0.4, 0), C.Metal)
	end
end

return M

-- Builds every region beyond the village: terrain by biome, water bodies,
-- landmarks, decorations, secret spots and lifts.
--
-- Resource nodes, forage, bugs and dig spots are placed later by their
-- services through WorldService.SpawnPoint, which avoids the exclusion areas
-- registered here (landmarks, lakes, lifts).
--
-- Build(root) returns { Lifts = { {Id, From, To, Arrive} }, Exclusions = { {Center, Radius} },
--                       RayTop = { [regionId] = y } }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Regions = require(Shared.Config.Regions)
local Secrets = require(Shared.Config.Secrets)
local Kit = require(Shared.Models.Kit)
local Models = require(Shared.Models)
local TerrainKit = require(script.Parent.TerrainKit)

local C = Kit.C
local V = Vector3.new
local M = Enum.Material

local RegionBuilder = {}

local byId: { [string]: any } = {}
for _, region in Regions.List do
	byId[region.Id] = region
end

-- Surface material per biome (painted over the base grass).
local BIOME_GROUND: { [string]: Enum.Material } = {
	Village = M.Grass,
	Farmland = M.Grass,
	Forest = M.LeafyGrass,
	Grove = M.Mud,
	Glade = M.LeafyGrass,
	Mountain = M.Rock,
	Wetlands = M.Mud,
	Beach = M.Sand,
	Desert = M.Sand,
	Snow = M.Snow,
	Ruins = M.Ground,
	Hollow = M.Ground,
	Valley = M.LeafyGrass,
}

-- Decoration helpers --------------------------------------------------------------------------------------------

local function decor(parent: Instance, name: string, cf: CFrame, build: (Model) -> ()): Model
	local model = Kit.Model(name)
	build(model)
	model:PivotTo(cf)
	model.Parent = parent
	return model
end

local function rock(parent: Instance, p: Vector3, size: number, color: Color3?)
	decor(parent, "Rock", CFrame.new(p) * CFrame.Angles(0, size, 0), function(m)
		Kit.Ball(m, V(size * 1.3, size * 0.8, size), CFrame.new(0, size * 0.25, 0), color or C.Stone, { Material = M.Rock })
	end)
end

local function giantMushroom(parent: Instance, p: Vector3, h: number, cap: Color3)
	decor(parent, "GiantMushroom", CFrame.new(p), function(m)
		Kit.Cyl(m, h, h * 0.18, CFrame.new(0, h / 2, 0), C.Cream, { Material = M.SmoothPlastic })
		local top = Kit.Ball(m, V(h * 0.9, h * 0.35, h * 0.9), CFrame.new(0, h, 0), cap, { Material = M.SmoothPlastic })
		for i = 1, 5 do
			local a = i * 1.25
			local spot = Kit.Ball(m, V(h * 0.12, h * 0.05, h * 0.12), CFrame.new(math.cos(a) * h * 0.25, h + h * 0.14, math.sin(a) * h * 0.25), C.White, { Collide = false })
			spot.Material = M.Neon
		end
		Kit.Light(top, cap, h * 1.5, 0.8)
	end)
end

local function crystal(parent: Instance, p: Vector3, h: number, color: Color3)
	decor(parent, "Crystal", CFrame.new(p) * CFrame.Angles(0.2, h, 0.15), function(m)
		local c = Kit.Box(m, V(h * 0.3, h, h * 0.3), CFrame.new(0, h * 0.45, 0) * CFrame.Angles(0, math.pi / 4, 0), color, { Material = M.Glass, Transparency = 0.2 })
		Kit.Light(c, color, h * 2.5, 1.2)
		Kit.Box(m, V(h * 0.18, h * 0.6, h * 0.18), CFrame.new(h * 0.25, h * 0.25, 0) * CFrame.Angles(0, 0, -0.4), color, { Material = M.Neon, Collide = false })
	end)
end

local function pillar(parent: Instance, p: Vector3, h: number, broken: boolean)
	decor(parent, "Pillar", CFrame.new(p) * CFrame.Angles(0, h, 0), function(m)
		Kit.Box(m, V(4, 1, 4), CFrame.new(0, 0.5, 0), Color3.fromRGB(200, 190, 165), { Material = M.Limestone })
		local height = if broken then h * 0.55 else h
		Kit.Cyl(m, height, 2.6, CFrame.new(0, 1 + height / 2, 0), Color3.fromRGB(215, 205, 180), { Material = M.Limestone })
		if not broken then
			Kit.Box(m, V(4, 1, 4), CFrame.new(0, 1.5 + height, 0), Color3.fromRGB(200, 190, 165), { Material = M.Limestone })
		else
			Kit.Box(m, V(2.4, 1.2, 1.4), CFrame.new(3, 0.6, 1), Color3.fromRGB(215, 205, 180), { Material = M.Limestone })
		end
	end)
end

local function cactus(parent: Instance, p: Vector3, h: number)
	decor(parent, "Cactus", CFrame.new(p) * CFrame.Angles(0, h, 0), function(m)
		local green = Color3.fromRGB(80, 140, 70)
		Kit.Cyl(m, h, 1.6, CFrame.new(0, h / 2, 0), green, { Material = M.Grass })
		Kit.Cyl(m, h * 0.35, 1.1, CFrame.new(1.4, h * 0.55, 0), green, { Material = M.Grass })
		Kit.Cyl(m, 1.4, 1.1, CFrame.new(0.8, h * 0.4, 0) * CFrame.Angles(0, 0, math.pi / 2), green, { Material = M.Grass })
	end)
end

local function reeds(parent: Instance, p: Vector3, seed: number)
	decor(parent, "Reeds", CFrame.new(p), function(m)
		local rng = Random.new(seed)
		for _ = 1, 6 do
			local h = rng:NextNumber(3, 5)
			local reed = Kit.Box(m, V(0.2, h, 0.2), CFrame.new(rng:NextNumber(-1.5, 1.5), h / 2, rng:NextNumber(-1.5, 1.5)) * CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, rng:NextNumber(-0.15, 0.15)), Color3.fromRGB(120, 140, 70), { Collide = false })
			reed:SetAttribute("Foliage", true)
			Kit.Cyl(m, 0.8, 0.35, CFrame.new(reed.Position.X, h - 0.3, reed.Position.Z), Color3.fromRGB(100, 70, 45), { Collide = false })
		end
	end)
end

local function bigTree(parent: Instance, p: Vector3, scale: number, leaves: Color3)
	decor(parent, "AncientTree", CFrame.new(p), function(m)
		Kit.Cyl(m, 30 * scale, 8 * scale, CFrame.new(0, 15 * scale, 0), C.DarkWood, { Material = M.Wood })
		for i = 1, 6 do
			local a = i * math.pi / 3
			Kit.Box(m, V(2.5 * scale, 2.5 * scale, 14 * scale), CFrame.new(math.cos(a) * 5 * scale, 1.2 * scale, math.sin(a) * 5 * scale) * CFrame.Angles(0, -a + math.pi / 2, 0.3), C.DarkWood, { Material = M.Wood, Name = "Root" })
		end
		for i = 1, 7 do
			local a = i * 0.9
			Kit.Ball(m, V(18, 14, 18) * scale, CFrame.new(math.cos(a) * 8 * scale, (30 + (i % 3) * 4) * scale, math.sin(a) * 8 * scale), leaves, { Material = M.Grass, Collide = false, Name = "Leaves" })
		end
	end)
end

-- A lift platform. `id` is the lift's name ("mine_down"); `region` gates access
-- (checked by PlayerService); `travel` marks a signpost as discovered on arrival.
local function liftModel(parent: Instance, position: Vector3, label: string, id: string, lifts: { any }, arrive: Vector3, region: string, travel: string?)
	decor(parent, "Lift_" .. id, CFrame.new(position), function(m)
		Kit.Box(m, V(10, 1, 10), CFrame.new(0, 0.5, 0), C.DarkMetal, { Material = M.DiamondPlate })
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				Kit.Box(m, V(0.8, 14, 0.8), CFrame.new(sx * 4.6, 7, sz * 4.6), C.Copper, { Material = M.Metal })
			end
		end
		Kit.Box(m, V(10.5, 1, 10.5), CFrame.new(0, 14, 0), C.DarkMetal, { Material = M.Metal })
		local wheel = Kit.Cyl(m, 0.8, 4, CFrame.new(0, 15.5, 0) * CFrame.Angles(math.pi / 2, 0, 0), C.Copper, { Material = M.Metal, Name = "Wheel" })
		wheel:SetAttribute("Anim", "Spinner")
		local panel = Kit.Box(m, V(2, 3, 0.5), CFrame.new(4, 2.5, -4.9), C.Wood, { Name = "Panel" })
		local prompt = Kit.Prompt(panel, "Lift", label, "Lift", 12)
		prompt:SetAttribute("Target", "lift:" .. id)
	end)
	table.insert(lifts, { Id = id, From = position, Arrive = arrive, Region = region, Travel = travel })
end

-- Biome builders ---------------------------------------------------------------------------------------------------

local builders: { [string]: (Folder, any, any) -> () } = {}

builders.Forest = function(f, r, ctx)
	TerrainKit.Lake(V(-600, 0, 160), 36, 8, M.Mud)
	bigTree(f, V(-700, 0, 140), 1, Color3.fromRGB(70, 120, 60))
	table.insert(ctx.Exclusions, { Center = V(-700, 0, 140), Radius = 26 })
	local rng = Random.new(11)
	for _ = 1, 40 do
		local a, d = rng:NextNumber(0, math.pi * 2), math.sqrt(rng:NextNumber()) * r.Radius * 0.9
		local p = r.Center + V(math.cos(a) * d, 0, math.sin(a) * d)
		if rng:NextNumber() < 0.5 then
			rock(f, p, rng:NextNumber(1.5, 3))
		else
			decor(f, "Log", CFrame.new(p + V(0, 0.8, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), function(m)
				Kit.CylFlat(m, rng:NextNumber(6, 10), 1.6, CFrame.new(), C.DarkWood, "X", { Material = M.Wood })
			end)
		end
	end
	-- Secret fern path marker far west.
	for i = 1, 6 do
		reeds(f, V(-1120 + i * 4, 0, -300 + (i % 2) * 6), i)
	end
end

builders.Grove = function(f, r, ctx)
	TerrainKit.Lake(V(-990, 0, -260), 20, 5, M.Mud)
	local rng = Random.new(21)
	local colors = { Color3.fromRGB(170, 90, 220), Color3.fromRGB(90, 200, 220), Color3.fromRGB(230, 120, 160) }
	for i = 1, 14 do
		local a = i / 14 * math.pi * 2
		local d = rng:NextNumber(40, r.Radius * 0.85)
		local p = r.Center + V(math.cos(a) * d, 0, math.sin(a) * d)
		giantMushroom(f, p, rng:NextNumber(10, 22), colors[i % 3 + 1])
		table.insert(ctx.Exclusions, { Center = p, Radius = 8 })
	end
end

builders.Glade = function(f, r, ctx)
	TerrainKit.Lake(V(-900, 0, 330), 26, 6, M.Grass)
	for i = 1, 9 do
		local a = i / 9 * math.pi * 2
		rock(f, V(-900 + math.cos(a) * 12, 0, 300 + math.sin(a) * 12), 1.8, Color3.fromRGB(200, 205, 215))
	end
	local fireflies = Kit.Box(f :: any, V(1, 1, 1), CFrame.new(r.Center + V(0, 6, 0)), C.White, { Transparency = 1, Collide = false, Name = "Fireflies" })
	local e = Kit.Particles(fireflies, "Sparkle", Color3.fromRGB(230, 255, 150), 30)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Speed = NumberRange.new(0.5, 2)
	e.Lifetime = NumberRange.new(3, 6)
	e:SetAttribute("NightOnly", true)
	table.insert(ctx.Exclusions, { Center = V(-900, 0, 300), Radius = 16 })
end

builders.Mountain = function(f, r, ctx)
	local rng = Random.new(31)
	-- Peaks around the edges, leaving the trail and lake clear.
	for i = 1, 14 do
		local a = i / 14 * math.pi * 2
		local d = r.Radius * rng:NextNumber(0.55, 0.95)
		local p = r.Center + V(math.cos(a) * d, 0, math.sin(a) * d)
		if (p - V(0, 0, -520)).Magnitude > 90 and (p - V(-200, 0, -780)).Magnitude > 150 and (p - V(150, 0, -640)).Magnitude > 60 then
			TerrainKit.Hill(p, rng:NextNumber(50, 90), rng:NextNumber(40, 110), M.Rock, M.Snow)
			table.insert(ctx.Exclusions, { Center = p, Radius = 60 })
		end
	end
	-- Lake plateau with a waterfall
	TerrainKit.Plateau(V(-200, 0, -780), 130, 20, M.Rock, M.Grass)
	TerrainKit.Lake(V(-200, 20, -780), 90, 12, M.Sand, 20)
	-- A cliff on the lake shore with a waterfall (and a cave behind it).
	decor(f, "Waterfall", CFrame.new(-268, 20, -872) * CFrame.Angles(0, math.rad(35), 0), function(m)
		Kit.Box(m, V(26, 22, 8), CFrame.new(0, 11, -6), C.DarkStone, { Material = M.Rock, Name = "Cliff" })
		local sheet = Kit.Box(m, V(10, 20, 0.6), CFrame.new(0, 10, -1.6), C.Water, { Material = M.Glass, Transparency = 0.35, Collide = false, Name = "Falls" })
		Kit.Particles(sheet, "Water", nil, 40).EmissionDirection = Enum.NormalId.Bottom
		Kit.Box(m, V(6, 7, 3), CFrame.new(0, 3.5, -3.5), C.Black, { Collide = false, Name = "CaveMouth" })
	end)
	-- Ramp up to the lake plateau (from the trail side).
	local rampFrom, rampTo = V(-68, -0.5, -648), V(-111, 19.5, -691)
	local ramp = Instance.new("Part")
	ramp.Size = V(16, 1, (rampTo - rampFrom).Magnitude + 2)
	ramp.CFrame = CFrame.lookAt((rampFrom + rampTo) / 2, rampTo)
	ramp.Anchored = true
	ramp.Material = M.Slate
	ramp.Color = C.DarkStone
	ramp.Name = "PlateauRamp"
	ramp.Parent = f
	-- Observatory hill with the sky lift and Luna's observatory
	TerrainKit.Plateau(V(-150, 0, -520), 44, 30, M.Rock, M.Grass)
	decor(f, "Observatory", CFrame.new(-150, 30, -536), function(m)
		Kit.Cyl(m, 12, 20, CFrame.new(0, 6, 0), C.Cream, { Material = M.Brick })
		local dome = Kit.Ball(m, V(21, 21, 21), CFrame.new(0, 12, 0), Color3.fromRGB(150, 160, 190), { Material = M.Metal })
		dome.Name = "Dome"
		local scope = Kit.Cyl(m, 10, 2, CFrame.new(3, 20, 0) * CFrame.Angles(0, 0, math.rad(-35)), C.DarkMetal, { Material = M.Metal })
		scope:SetAttribute("Anim", "Telescope")
		Kit.Box(m, V(4, 7, 0.5), CFrame.new(0, 3.5, 10.2), C.DarkWood, { Name = "Door", Collide = false })
	end)
	local stairFrom, stairTo = V(-150, -0.5, -418), V(-150, 29.5, -477)
	local stairs = Instance.new("Part")
	stairs.Size = V(10, 1, (stairTo - stairFrom).Magnitude + 2)
	stairs.CFrame = CFrame.lookAt((stairFrom + stairTo) / 2, stairTo)
	stairs.Anchored = true
	stairs.Material = M.Cobblestone
	stairs.Color = C.Stone
	stairs.Name = "ObservatoryPath"
	stairs.Parent = f
	liftModel(f, V(-128, 30, -505), "Sky Lift", "sky_up", ctx.Lifts, V(0, 640, -1080), "Skyreach", "skyreach")
	table.insert(ctx.Exclusions, { Center = V(-150, 0, -520), Radius = 60 })
	table.insert(ctx.Exclusions, { Center = V(-200, 0, -780), Radius = 140 })
	-- Mine entrance: a rocky mouth with the lift
	TerrainKit.Hill(V(150, 0, -680), 50, 40, M.Rock)
	decor(f, "MineMouth", CFrame.new(150, 0, -640), function(m)
		for _, x in { -7, 7 } do
			Kit.Box(m, V(1.5, 12, 1.5), CFrame.new(x, 6, 0), C.DarkWood, { Material = M.Wood })
		end
		Kit.Box(m, V(16, 1.5, 1.5), CFrame.new(0, 12, 0), C.DarkWood, { Material = M.Wood })
		local sign = Kit.Box(m, V(7, 2, 0.3), CFrame.new(0, 13.6, 0.2), C.Plank, { Collide = false })
		Kit.Label(sign, "EMBERSTONE MINE", Enum.NormalId.Back)
		local lantern = Kit.Ball(m, V(1, 1, 1), CFrame.new(-7, 10, 1), Color3.fromRGB(255, 190, 110), { Collide = false })
		Kit.Glow(lantern, Color3.fromRGB(255, 190, 110))
		Kit.Light(lantern, Color3.fromRGB(255, 190, 110), 18, 1.4)
	end)
	liftModel(f, V(150, 0, -626), "Descend", "mine_down", ctx.Lifts, V(150, -310, -600), "Mine")
	table.insert(ctx.Exclusions, { Center = V(150, 0, -650), Radius = 60 })
end

builders.Cave = function(f, r, ctx)
	local floor = r.Center.Y - 10
	TerrainKit.Cave(r.Center, r.Radius, floor, 50, M.Rock, M.Slate, 41)
	for _, water in r.Waters do
		TerrainKit.Lake(V(water.Center.X, floor, water.Center.Z), water.Radius, 6, M.Rock, floor)
	end
	-- Lanterns along the chamber
	for i = 1, 12 do
		local a = i / 12 * math.pi * 2
		local p = V(r.Center.X + math.cos(a) * r.Radius * 0.7, floor, r.Center.Z + math.sin(a) * r.Radius * 0.7)
		decor(f, "MineLamp", CFrame.new(p), function(m)
			Kit.Box(m, V(0.8, 7, 0.8), CFrame.new(0, 3.5, 0), C.DarkWood)
			local l = Kit.Ball(m, V(1, 1, 1), CFrame.new(0, 7.2, 0), Color3.fromRGB(255, 190, 110), { Collide = false })
			Kit.Glow(l, Color3.fromRGB(255, 190, 110))
			Kit.Light(l, Color3.fromRGB(255, 180, 100), 26, 1.3, true)
		end)
	end
	-- Rails for flavour
	decor(f, "Rails", CFrame.new(r.Center.X, floor + 0.2, r.Center.Z + 40), function(m)
		for _, x in { -1.6, 1.6 } do
			Kit.Box(m, V(0.3, 0.3, 120), CFrame.new(x, 0, 0), C.DarkMetal, { Material = M.Metal })
		end
		for z = -58, 58, 4 do
			Kit.Box(m, V(4.6, 0.3, 0.8), CFrame.new(0, -0.2, z), C.DarkWood)
		end
	end)
	liftModel(f, V(150, floor, -610), "Ascend", "mine_up", ctx.Lifts, V(150, 0, -612), "Mountains", "mine")
	liftModel(f, V(200, floor, -560), "Deep Lift", "caverns_down", ctx.Lifts, V(150, -510, -600), "CrystalCaverns", "caverns")
	table.insert(ctx.Exclusions, { Center = V(150, floor, -610), Radius = 14 })
	table.insert(ctx.Exclusions, { Center = V(200, floor, -560), Radius = 14 })
	ctx.RayTop[r.Id] = floor + 30
end

builders.Crystal = function(f, r, ctx)
	local floor = r.Center.Y - 10
	TerrainKit.Cave(r.Center, r.Radius, floor, 60, M.Basalt, M.Glacier, 51)
	for _, water in r.Waters do
		TerrainKit.Lake(V(water.Center.X, floor, water.Center.Z), water.Radius, 8, M.Glacier, floor)
	end
	local rng = Random.new(52)
	local colors = { Color3.fromRGB(140, 220, 255), Color3.fromRGB(200, 140, 255), Color3.fromRGB(140, 255, 200) }
	for i = 1, 26 do
		local a, d = rng:NextNumber(0, math.pi * 2), rng:NextNumber(20, r.Radius * 0.95)
		local p = V(r.Center.X + math.cos(a) * d, floor, r.Center.Z + math.sin(a) * d)
		crystal(f, p, rng:NextNumber(4, 12), colors[i % 3 + 1])
	end
	liftModel(f, V(150, floor, -620), "Ascend", "caverns_up", ctx.Lifts, V(200, -310, -570), "Mine")
	table.insert(ctx.Exclusions, { Center = V(150, floor, -620), Radius = 14 })
	ctx.RayTop[r.Id] = floor + 35
end

builders.Beach = function(f, r, ctx)
	TerrainKit.Lake(V(1100, 0, 1100), 420, 30, M.Sand)
	-- Lighthouse island
	workspace.Terrain:FillCylinder(CFrame.new(1020, -8, 1010), 16, 60, M.Rock)
	workspace.Terrain:FillCylinder(CFrame.new(1020, -2, 1010), 4, 58, M.Sand)
	decor(f, "Lighthouse", CFrame.new(1040, 0, 980), function(m)
		for i = 0, 5 do
			local color = if i % 2 == 0 then C.White else C.Red
			Kit.Cyl(m, 6, 9 - i * 0.6, CFrame.new(0, 3 + i * 6, 0), color, { Material = M.Concrete })
		end
		local lamp = Kit.Ball(m, V(5, 5, 5), CFrame.new(0, 39, 0), Color3.fromRGB(255, 240, 180), { Material = M.Glass, Transparency = 0.2 })
		lamp:SetAttribute("NightGlow", true)
		local beam = Instance.new("SpotLight")
		beam.Range = 60
		beam.Angle = 25
		beam.Brightness = 3
		beam.Color = Color3.fromRGB(255, 240, 200)
		beam:SetAttribute("NightLight", true)
		beam.Parent = lamp
		lamp:SetAttribute("Anim", "Spinner")
		Kit.Cyl(m, 3, 8, CFrame.new(0, 42.5, 0), C.Red)
	end)
	-- Causeway to the island
	local shore, isle = V(815, 0.4, 780), V(985, 0.4, 970)
	local causeway = Instance.new("Part")
	causeway.Size = V(10, 1, (isle - shore).Magnitude + 6)
	causeway.CFrame = CFrame.lookAt((shore + isle) / 2, isle)
	causeway.Anchored = true
	causeway.Material = M.WoodPlanks
	causeway.Color = C.Plank
	causeway.Name = "Causeway"
	causeway.Parent = f
	-- Harbor pier
	decor(f, "Pier", CFrame.new(720, 0, 900) * CFrame.Angles(0, math.rad(45), 0), function(m)
		Kit.Box(m, V(10, 1, 70), CFrame.new(0, 0.8, 35), C.Plank, { Material = M.WoodPlanks })
		for z = 0, 70, 10 do
			for _, x in { -4.6, 4.6 } do
				Kit.Cyl(m, 8, 1, CFrame.new(x, -3, z), C.DarkWood, { Material = M.Wood })
			end
		end
		local boat = Kit.Box(m, V(8, 3, 16), CFrame.new(10, 0.5, 50), Color3.fromRGB(200, 90, 60), { Material = M.Wood, Name = "Boat" })
		boat:SetAttribute("Anim", "Bob")
	end)
	table.insert(ctx.Exclusions, { Center = V(1100, 0, 1100), Radius = 430 })
	table.insert(ctx.Exclusions, { Center = V(720, 0, 900), Radius = 20 })
	local rng = Random.new(61)
	for _ = 1, 20 do
		local a, d = rng:NextNumber(0, math.pi * 2), rng:NextNumber(0, r.Radius)
		local p = r.Center + V(math.cos(a) * d, 0, math.sin(a) * d)
		if (p - V(1100, 0, 1100)).Magnitude > 440 then
			decor(f, "Shell", CFrame.new(p + V(0, 0.2, 0)) * CFrame.Angles(0, a, 0), function(m)
				Kit.Wedge(m, V(0.8, 0.5, 1), CFrame.new(), Color3.fromHSV(rng:NextNumber(0, 0.1), 0.3, 1), { Collide = false })
			end)
		end
	end
end

builders.Desert = function(f, r, ctx)
	local rng = Random.new(71)
	for _ = 1, 12 do
		local a, d = rng:NextNumber(0, math.pi * 2), rng:NextNumber(80, r.Radius * 0.95)
		local p = r.Center + V(math.cos(a) * d, 0, math.sin(a) * d)
		TerrainKit.Hill(p, rng:NextNumber(30, 60), rng:NextNumber(8, 22), M.Sand)
	end
	TerrainKit.Lake(V(1300, 0, -200), 45, 8, M.Sand)
	for i = 1, 30 do
		local a, d = rng:NextNumber(0, math.pi * 2), rng:NextNumber(60, r.Radius * 0.9)
		local p = r.Center + V(math.cos(a) * d, 0, math.sin(a) * d)
		if i % 3 == 0 then
			rock(f, p, rng:NextNumber(2, 5), Color3.fromRGB(205, 160, 110))
		else
			cactus(f, p, rng:NextNumber(4, 9))
		end
	end
	-- Giant skeleton landmark
	decor(f, "Skeleton", CFrame.new(1450, 0, -380), function(m)
		for i = 0, 9 do
			Kit.Box(m, V(1.2, 8 - math.abs(i - 5), 1.2), CFrame.new(i * 3 - 14, 3, 0) * CFrame.Angles(0, 0, 0.15), C.Cream, { Material = M.Marble })
		end
		Kit.Ball(m, V(8, 6, 10), CFrame.new(-18, 3, 0), C.Cream, { Material = M.Marble, Name = "Skull" })
	end)
	table.insert(ctx.Exclusions, { Center = V(1300, 0, -200), Radius = 55 })
	table.insert(ctx.Exclusions, { Center = V(1450, 0, -380), Radius = 26 })
end

builders.Snow = function(f, r, ctx)
	local rng = Random.new(81)
	for i = 1, 10 do
		local a = i / 10 * math.pi * 2
		local p = r.Center + V(math.cos(a) * r.Radius * 0.8, 0, math.sin(a) * r.Radius * 0.8)
		TerrainKit.Hill(p, rng:NextNumber(40, 70), rng:NextNumber(30, 70), M.Rock, M.Snow)
		table.insert(ctx.Exclusions, { Center = p, Radius = 50 })
	end
	TerrainKit.Lake(V(-940, 0, -940), 80, 12, M.Snow)
	-- Thin ice ring around the fishing holes
	workspace.Terrain:FillCylinder(CFrame.new(-940, -1, -940), 2, 80, M.Glacier)
	for i = 1, 5 do
		local a = i / 5 * math.pi * 2
		workspace.Terrain:FillCylinder(CFrame.new(-940 + math.cos(a) * 40, -1, -940 + math.sin(a) * 40), 2, 7, M.Water)
	end
	decor(f, "Lodge", CFrame.new(-860, 0, -840) * CFrame.Angles(0, math.rad(-135), 0), function(m)
		local builder = Models.Builder("Shed")
		if builder then
			builder(m, 20, 16, 14, {}, {})
		end
		local fire = Kit.Box(m, V(2, 1, 2), CFrame.new(0, 0.5, 11), Color3.fromRGB(255, 140, 50), { Collide = false, Name = "Campfire" })
		Kit.Particles(fire, "Fire", nil, 20)
		Kit.Light(fire, Color3.fromRGB(255, 160, 80), 24, 2)
		fire:SetAttribute("Warmth", 18)
	end)
	decor(f, "FrozenShrine", CFrame.new(-1020, 0, -1000), function(m)
		for i = 1, 6 do
			local a = i / 6 * math.pi * 2
			Kit.Box(m, V(2, 10, 2), CFrame.new(math.cos(a) * 8, 5, math.sin(a) * 8) * CFrame.Angles(0, a, 0.1), Color3.fromRGB(180, 225, 255), { Material = M.Ice, Transparency = 0.2 })
		end
	end)
	table.insert(ctx.Exclusions, { Center = V(-940, 0, -940), Radius = 90 })
	table.insert(ctx.Exclusions, { Center = V(-860, 0, -840), Radius = 26 })
	table.insert(ctx.Exclusions, { Center = V(-1020, 0, -1000), Radius = 16 })
end

builders.Ruins = function(f, r, ctx)
	TerrainKit.Plateau(V(800, 0, -760), 60, 6, M.Ground, M.Cobblestone)
	TerrainKit.Lake(V(820, 6, -800), 18, 5, M.Cobblestone, 6)
	local rng = Random.new(91)
	for i = 1, 24 do
		local a = i / 24 * math.pi * 2
		local d = if i % 2 == 0 then 70 else 110
		pillar(f, r.Center + V(math.cos(a) * d, 0, math.sin(a) * d), rng:NextNumber(10, 18), rng:NextNumber() < 0.5)
	end
	decor(f, "Altar", CFrame.new(820, 0, -640), function(m)
		Kit.Box(m, V(8, 3, 5), CFrame.new(0, 1.5, 0), Color3.fromRGB(190, 180, 160), { Material = M.Limestone })
		Kit.Box(m, V(9, 0.6, 6), CFrame.new(0, 3.3, 0), Color3.fromRGB(170, 160, 140), { Material = M.Limestone })
	end)
	decor(f, "VaultDoor", CFrame.new(800, 6, -760), function(m)
		Kit.Box(m, V(12, 14, 3), CFrame.new(0, 7, 0), Color3.fromRGB(150, 140, 120), { Material = M.Limestone })
		Kit.Box(m, V(7, 10, 0.5), CFrame.new(0, 5, -1.6), Color3.fromRGB(120, 110, 90), { Material = M.Slate, Name = "Door" })
		for i = 1, 4 do
			local rune = Kit.Box(m, V(1.2, 1.2, 0.1), CFrame.new(-3 + (i - 1) * 2, 11.5, -1.6), Color3.fromRGB(120, 230, 255), { Collide = false, Name = "Rune" .. i })
			rune.Material = M.Neon
			rune.Transparency = 0.7
		end
	end)
	table.insert(ctx.Exclusions, { Center = V(800, 0, -760), Radius = 70 })
end

builders.Hollow = function(f, r, ctx)
	TerrainKit.Lake(V(-820, 0, 860), 30, 5, M.Mud)
	decor(f, "OldBarn", CFrame.new(-760, 0, 760) * CFrame.Angles(0, math.rad(30), 0.03), function(m)
		local builder = Models.Builder("Barn")
		if builder then
			builder(m, 24, 20, 16, {}, {})
		end
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.Color = d.Color:Lerp(Color3.fromRGB(90, 90, 90), 0.5)
			end
		end
	end)
	local rng = Random.new(101)
	for row = 0, 5 do
		for col = 0, 8 do
			local p = V(-860 + col * 6, 0, 740 + row * 6)
			decor(f, "DeadCrop", CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, 6), 0.2), function(m)
				Kit.Box(m, V(0.3, rng:NextNumber(1.5, 3), 0.3), CFrame.new(0, 1, 0), Color3.fromRGB(120, 100, 70), { Collide = false })
			end)
		end
	end
	decor(f, "Scarecrow", CFrame.new(-820, 0, 780), function(m)
		local builder = Models.Builder("Scarecrow")
		if builder then
			builder(m, 4, 4, 8, { Fancy = true }, {})
		end
	end)
	table.insert(ctx.Exclusions, { Center = V(-760, 0, 760), Radius = 22 })
	table.insert(ctx.Exclusions, { Center = V(-835, 0, 755), Radius = 30 })
end

builders.Sky = function(f, r, ctx)
	local c = r.Center
	TerrainKit.Island(c, 80, M.Grass, M.Rock)
	TerrainKit.Lake(V(40, c.Y, -1120), 24, 6, M.Sand, c.Y)
	local islands = {
		{ V(-160, 700, -1240), 34 },
		{ V(170, 660, -1180), 40 },
		{ V(-120, 620, -960), 36 },
		{ V(140, 610, -990), 30 },
		{ V(0, 680, -1300), 44 },
	}
	for _, isl in islands do
		TerrainKit.Island(isl[1], isl[2], M.Grass, M.Rock)
	end
	-- Rope bridges from the main island to each smaller one.
	for _, isl in islands do
		local a = c + V(0, 0.5, 0)
		local b = isl[1] + V(0, 0.5, 0)
		local dir = (b - a)
		local flat = V(dir.X, 0, dir.Z).Unit
		local from = a + flat * 72
		local to = b - flat * (isl[2] - 4)
		local bridge = Instance.new("Part")
		bridge.Anchored = true
		bridge.Size = V(6, 0.6, (to - from).Magnitude)
		bridge.CFrame = CFrame.lookAt((from + to) / 2, to)
		bridge.Material = M.WoodPlanks
		bridge.Color = C.Plank
		bridge.Name = "SkyBridge"
		bridge.Parent = f
	end
	-- Clouds drifting below
	for i = 1, 16 do
		local a = i / 16 * math.pi * 2
		decor(f, "Cloud", CFrame.new(c + V(math.cos(a) * 220, -60 - (i % 4) * 20, math.sin(a) * 220)), function(m)
			for j = 1, 4 do
				Kit.Ball(m, V(30, 16, 24), CFrame.new(j * 14 - 30, (j % 2) * 4, 0), C.White, { Transparency = 0.2, Collide = false })
			end
		end)
	end
	liftModel(f, V(0, c.Y, -1060), "Descend", "sky_down", ctx.Lifts, V(-140, 30, -500), "Mountains", "observatory")
	table.insert(ctx.Exclusions, { Center = V(0, c.Y, -1060), Radius = 14 })
	ctx.RayTop[r.Id] = c.Y + 160
end

builders.Valley = function(f, r, ctx)
	local rng = Random.new(121)
	-- A ring of cliffs hides the valley.
	for i = 1, 16 do
		local a = i / 16 * math.pi * 2
		local p = r.Center + V(math.cos(a) * (r.Radius + 20), 0, math.sin(a) * (r.Radius + 20))
		if math.abs(math.deg(a) - 0) > 20 then -- the hidden pass faces east (toward the forest)
			TerrainKit.Hill(p, rng:NextNumber(40, 60), rng:NextNumber(50, 80), M.Rock, M.Grass)
		end
	end
	TerrainKit.Lake(V(-1420, 0, -320), 40, 8, M.Grass)
	bigTree(f, V(-1440, 0, -260), 1.6, Color3.fromRGB(120, 200, 140))
	table.insert(ctx.Exclusions, { Center = V(-1440, 0, -260), Radius = 40 })
end

builders.Wetlands = function(f, r, ctx)
	-- The Mossback river winds from the mountains past the village into the marsh.
	local river = { V(330, 0, -520), V(290, 0, -300), V(262, 0, -150), V(250, 0, 40), V(300, 0, 200), V(420, 0, 290), V(560, 0, 320), V(660, 0, 260) }
	TerrainKit.River(river, 36, 10, M.Sand)
	ctx.River = river
	local rng = Random.new(131)
	for i = 1, 8 do
		local a, d = rng:NextNumber(0, math.pi * 2), rng:NextNumber(20, 140)
		TerrainKit.Lake(V(640, 0, 220) + V(math.cos(a) * d, 0, math.sin(a) * d), rng:NextNumber(10, 22), 4, M.Mud)
	end
	for i = 1, 40 do
		local a, d = rng:NextNumber(0, math.pi * 2), rng:NextNumber(10, 170)
		reeds(f, V(640, 0, 220) + V(math.cos(a) * d, 0, math.sin(a) * d), i)
	end
	-- Boardwalk through the marsh
	for i = 0, 9 do
		local p = V(560 + i * 12, 0.6, 180 + math.sin(i) * 8)
		local plank = Instance.new("Part")
		plank.Anchored = true
		plank.Size = V(12.5, 0.6, 6)
		plank.CFrame = CFrame.new(p)
		plank.Material = M.WoodPlanks
		plank.Color = C.Plank
		plank.Name = "Boardwalk"
		plank.Parent = f
	end
	-- The dock by Finn's shop
	decor(f, "Dock", CFrame.new(236, 0, 122), function(m)
		Kit.Box(m, V(40, 1, 8), CFrame.new(0, 0.8, 0), C.Plank, { Material = M.WoodPlanks })
		for x = -18, 18, 6 do
			Kit.Cyl(m, 8, 1, CFrame.new(x, -3, 3.4), C.DarkWood, { Material = M.Wood })
		end
	end)
	table.insert(ctx.Exclusions, { Center = V(640, 0, 220), Radius = 180 })
end

-- Secrets: invisible trigger volumes (the client reports entering them).
local function buildSecrets(root: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Secrets"
	folder.Parent = root
	for _, secret in Secrets.List do
		local part = Instance.new("Part")
		part.Name = secret.Id
		part.Shape = Enum.PartType.Ball
		part.Size = V(secret.Radius * 2, secret.Radius * 2, secret.Radius * 2)
		part.Position = secret.Position + V(0, 2, 0)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part:SetAttribute("Secret", secret.Id)
		part:SetAttribute("Visible", secret.Visible or "None")
		part.Parent = folder
	end
end

-- Build ----------------------------------------------------------------------------------------------------------------

function RegionBuilder.Build(root: Instance): any
	local ctx = { Lifts = {}, Exclusions = {}, RayTop = {}, River = nil }
	local folder = Instance.new("Folder")
	folder.Name = "Regions"
	folder.Parent = root
	-- Paint larger regions first so smaller ones sit on top.
	local ordered = table.clone(Regions.List)
	table.sort(ordered, function(a, b)
		return a.Radius > b.Radius
	end)
	for _, region in ordered do
		local ground = BIOME_GROUND[region.Biome]
		if ground and region.Center.Y == 0 and region.Biome ~= "Village" and region.Biome ~= "Farmland" then
			TerrainKit.PaintDisc(region.Center, region.Radius * 0.92, ground)
		end
	end
	for _, region in Regions.List do
		local builder = builders[region.Biome]
		if builder then
			local sub = Instance.new("Folder")
			sub.Name = region.Id
			sub.Parent = folder
			local ok, err = pcall(builder, sub, region, ctx)
			if not ok then
				warn("[Evergrove] Region builder failed:", region.Id, err)
			end
		end
	end
	buildSecrets(root)
	return ctx
end

return RegionBuilder

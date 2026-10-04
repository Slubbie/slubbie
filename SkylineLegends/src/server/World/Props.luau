-- Reusable set dressing shared by the district builders: rooftop clutter,
-- industrial kit, foliage, city furniture and floating architecture.
--
-- Every prop takes a CFrame on the surface it stands on (Y up) and returns the
-- interesting positions it creates (tops to stand on, hidden nooks), so district
-- builders can hang caches, letters and quest objectives on them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tags = require(ReplicatedStorage.Shared.Tags)

local Kit = require(script.Parent.Kit)

type Builder = Kit.Builder

local Props = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- A climbable ladder against a face. `face` sits on the surface, looking away from it.
function Props.Ladder(B: Builder, face: CFrame, height: number, width: number?)
	local w = width or 2.6
	local surface = B:Box(face * CFrame.new(0, height / 2, -0.3), Vector3.new(w, height, 0.5), rgb(80, 82, 90), Enum.Material.Metal, {
		Name = "Ladder",
		Transparency = 0.7,
		Tag = Tags.Climbable,
		Attrs = { Kind = "Ladder" },
	})
	for _, x in { -w / 2 + 0.2, w / 2 - 0.2 } do
		B:Detail(face * CFrame.new(x, height / 2, -0.75), Vector3.new(0.3, height, 0.3), rgb(70, 72, 80), Enum.Material.Metal)
	end
	for y = 1, math.floor(height) - 1, 2 do
		B:Detail(face * CFrame.new(0, y, -0.75), Vector3.new(w - 0.4, 0.2, 0.2), rgb(95, 97, 105), Enum.Material.Metal)
	end
	B:Icon(surface, "#", rgb(150, 230, 140), Vector3.new(0, height / 2 + 1, 0))
	return surface
end

-- Rooftops -----------------------------------------------------------------------------

function Props.WaterTower(B: Builder, base: CFrame, scale: number?, color: Color3?): (Vector3, Vector3)
	local s = scale or 1
	local legH = 9 * s
	local tankH = 8 * s
	local radius = 4.5 * s
	for _, offset in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) } do
		B:Box(base * CFrame.new(offset * radius * 0.7) * CFrame.new(0, legH / 2, 0), Vector3.new(0.6, legH, 0.6) * Vector3.new(s, 1, s), rgb(70, 60, 50), Enum.Material.Wood)
	end
	B:Box(base * CFrame.new(0, legH, 0), Vector3.new(radius * 2.1, 0.6, radius * 2.1), rgb(90, 75, 60), Enum.Material.WoodPlanks)
	local tank = B:Cylinder(base * CFrame.new(0, legH + tankH / 2 + 0.3, 0) * CFrame.Angles(0, 0, math.rad(90)), tankH, radius * 2, color or rgb(130, 95, 70), Enum.Material.WoodPlanks)
	tank.Name = "WaterTank"
	-- Conical roof built from a wedge ring approximation.
	local roofTop = legH + tankH + 0.3
	B:Box(base * CFrame.new(0, roofTop + 0.6, 0), Vector3.new(radius * 1.9, 1.2, radius * 1.9), rgb(80, 85, 90), Enum.Material.CorrodedMetal)
	B:Box(base * CFrame.new(0, roofTop + 1.6, 0), Vector3.new(radius * 1.2, 1, radius * 1.2), rgb(80, 85, 90), Enum.Material.CorrodedMetal)
	for i = 0, 2 do
		B:Detail(base * CFrame.new(0, legH + 1.8 + i * (tankH / 3), 0) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.25, radius * 2.06, radius * 2.06), rgb(50, 50, 55), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	end
	Props.Ladder(B, base * CFrame.new(0, 0, radius * 0.7 + 0.4), legH + tankH + 0.6, 2.2)
	local top = (base * CFrame.new(0, roofTop + 2.2, 0)).Position
	local nook = (base * CFrame.new(0, 0.2, 0)).Position
	return top, nook
end

function Props.Chimney(B: Builder, base: CFrame, color: Color3, height: number?): Vector3
	local h = height or 5
	B:Box(base * CFrame.new(0, h / 2, 0), Vector3.new(2.6, h, 2.6), color, Enum.Material.Brick)
	B:Box(base * CFrame.new(0, h + 0.3, 0), Vector3.new(3, 0.6, 3), rgb(90, 90, 95), Enum.Material.Concrete)
	B:Detail(base * CFrame.new(0, h + 0.62, 0), Vector3.new(1.8, 0.06, 1.8), rgb(20, 20, 20), Enum.Material.SmoothPlastic)
	return (base * CFrame.new(0, h + 0.6, 0)).Position
end

function Props.ACUnit(B: Builder, base: CFrame)
	B:Detail(base * CFrame.new(0, 1, 0), Vector3.new(3, 2, 2.4), rgb(180, 185, 190), Enum.Material.Metal, { CanCollide = true })
	B:Detail(base * CFrame.new(0, 2.05, 0) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.1, 1.8, 1.8), rgb(60, 62, 70), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
end

function Props.Skylight(B: Builder, base: CFrame)
	B:Box(base * CFrame.new(0, 0.6, 0), Vector3.new(5, 1.2, 4), rgb(110, 100, 90), Enum.Material.Wood)
	B:Detail(base * CFrame.new(0, 1.25, 0), Vector3.new(4.4, 0.1, 3.4), rgb(170, 210, 230), Enum.Material.Glass, { Transparency = 0.4 })
end

function Props.Planter(B: Builder, base: CFrame, flower: Color3)
	B:Box(base * CFrame.new(0, 0.6, 0), Vector3.new(4, 1.2, 1.6), rgb(120, 80, 55), Enum.Material.WoodPlanks)
	B:Detail(base * CFrame.new(0, 1.25, 0), Vector3.new(3.8, 0.1, 1.4), rgb(80, 55, 40), Enum.Material.Ground)
	for i = -1, 1 do
		B:Detail(base * CFrame.new(i * 1.2, 1.7, 0), Vector3.new(0.9, 0.9, 0.9), rgb(80, 150, 70), Enum.Material.LeafyGrass, { Shape = Enum.PartType.Ball })
		B:Detail(base * CFrame.new(i * 1.2 + 0.2, 2.1, 0.1), Vector3.new(0.35, 0.35, 0.35), flower, Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball })
	end
end

-- Washing line between two posts, with sheets.
function Props.Clothesline(B: Builder, a: Vector3, b: Vector3, colors: { Color3 })
	local height = 5.5
	for _, p in { a, b } do
		B:Box(CFrame.new(p + Vector3.new(0, height / 2, 0)), Vector3.new(0.4, height, 0.4), rgb(90, 70, 50), Enum.Material.Wood)
	end
	local top = Vector3.new(0, height - 0.3, 0)
	B:Rod(a + top, b + top, 0.1, rgb(230, 230, 230), Enum.Material.SmoothPlastic, { Decor = true, CanCollide = false })
	local count = math.floor((b - a).Magnitude / 3)
	for i = 1, count - 1 do
		local p = a:Lerp(b, i / count) + top - Vector3.new(0, 1.1, 0)
		local cloth = B:Detail(CFrame.lookAt(p, p + (b - a)), Vector3.new(0.05, 2, 1.8), colors[(i % #colors) + 1], Enum.Material.Fabric)
		cloth.CanCollide = false
	end
end

function Props.StringLights(B: Builder, a: Vector3, b: Vector3, color: Color3)
	B:Rod(a, b, 0.08, rgb(30, 30, 30), Enum.Material.SmoothPlastic, { Decor = true, CanCollide = false })
	local count = math.max(2, math.floor((b - a).Magnitude / 4))
	for i = 1, count - 1 do
		local p = a:Lerp(b, i / count) - Vector3.new(0, math.sin(i / count * math.pi) * 0.8, 0)
		local bulb = B:Detail(CFrame.new(p), Vector3.new(0.4, 0.4, 0.4), color, Enum.Material.Neon, { Shape = Enum.PartType.Ball })
		if i % 3 == 0 then
			B:Light(bulb, color, 8, 0.5)
		end
	end
end

function Props.Bench(B: Builder, base: CFrame, color: Color3?)
	local c = color or rgb(120, 85, 55)
	B:Box(base * CFrame.new(0, 1.1, 0), Vector3.new(5, 0.3, 1.6), c, Enum.Material.WoodPlanks)
	B:Box(base * CFrame.new(0, 1.9, 0.7), Vector3.new(5, 1.4, 0.2), c, Enum.Material.WoodPlanks)
	for _, x in { -2, 2 } do
		B:Detail(base * CFrame.new(x, 0.5, 0), Vector3.new(0.3, 1, 1.4), rgb(50, 50, 55), Enum.Material.Metal)
	end
end

function Props.Lamp(B: Builder, base: CFrame, color: Color3, height: number?)
	local h = height or 9
	B:Box(base * CFrame.new(0, h / 2, 0), Vector3.new(0.5, h, 0.5), rgb(40, 42, 48), Enum.Material.Metal)
	local head = B:Detail(base * CFrame.new(0, h + 0.4, 0), Vector3.new(1.2, 0.8, 1.2), color, Enum.Material.Neon)
	B:Light(head, color, 22, 1.1)
	return head
end

-- Industry -------------------------------------------------------------------------------

function Props.Crate(B: Builder, base: CFrame, size: number, color: Color3)
	B:Box(base * CFrame.new(0, size / 2, 0), Vector3.new(size, size, size), color, Enum.Material.WoodPlanks)
	B:Detail(base * CFrame.new(0, size / 2, -size / 2 - 0.02), Vector3.new(size * 0.9, 0.2, 0.05), rgb(60, 45, 30), Enum.Material.Wood)
end

function Props.Container(B: Builder, base: CFrame, color: Color3): Vector3
	B:Box(base * CFrame.new(0, 4.25, 0), Vector3.new(8.5, 8.5, 20), color, Enum.Material.CorrodedMetal)
	for z = -9, 9, 2 do
		B:Detail(base * CFrame.new(4.3, 4.25, z), Vector3.new(0.12, 8, 0.4), color:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Metal)
	end
	return (base * CFrame.new(0, 8.6, 0)).Position
end

function Props.Barrel(B: Builder, base: CFrame, color: Color3)
	B:Cylinder(base * CFrame.new(0, 1.6, 0) * CFrame.Angles(0, 0, math.rad(90)), 3.2, 2.2, color, Enum.Material.Metal)
end

function Props.Pipe(B: Builder, a: Vector3, b: Vector3, color: Color3, diameter: number?)
	return B:Rod(a, b, diameter or 1.6, color, Enum.Material.Metal)
end

-- Smokestack with a climbing mesh up one side. Returns the top position.
function Props.Smokestack(B: Builder, base: CFrame, height: number, color: Color3, smoke: boolean?): (Vector3, Vector3)
	local stack = B:Cylinder(base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), height, 7, color, Enum.Material.Brick)
	stack.Name = "Smokestack"
	B:Box(base * CFrame.new(0, height + 0.5, 0), Vector3.new(8.2, 1, 8.2), rgb(60, 60, 64), Enum.Material.Metal)
	for y = 6, height - 4, 10 do
		B:Detail(base * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.6, 7.2, 7.2), rgb(240, 180, 40), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	end
	Props.Ladder(B, base * CFrame.new(0, 0, 3.6), height + 1, 2.4)
	if smoke then
		local vent = B:Detail(base * CFrame.new(0, height + 1.2, 0), Vector3.new(4, 0.2, 4), rgb(20, 20, 20), Enum.Material.SmoothPlastic)
		local attachment = Instance.new("Attachment")
		attachment.Parent = vent
		B:Emitter(attachment, "Smoke", rgb(120, 115, 110))
	end
	return (base * CFrame.new(0, height + 1.2, 0)).Position, (base * CFrame.new(4.6, 0.3, 0)).Position
end

function Props.Crane(B: Builder, base: CFrame, height: number, jib: number, color: Color3): (Vector3, Vector3)
	-- Lattice tower.
	for _, offset in { Vector3.new(-2, 0, -2), Vector3.new(2, 0, -2), Vector3.new(-2, 0, 2), Vector3.new(2, 0, 2) } do
		B:Box(base * CFrame.new(offset) * CFrame.new(0, height / 2, 0), Vector3.new(0.8, height, 0.8), color, Enum.Material.Metal)
	end
	for y = 4, height - 2, 6 do
		for _, rotation in { 0, 90, 180, 270 } do
			B:Detail(base * CFrame.Angles(0, math.rad(rotation), 0) * CFrame.new(0, y, 2) * CFrame.Angles(0, 0, math.rad(45)), Vector3.new(5.5, 0.35, 0.35), color, Enum.Material.Metal, { CanCollide = true })
		end
	end
	Props.Ladder(B, base * CFrame.new(0, 0, 2.6), height, 2.2)
	-- Cab and jib.
	B:Box(base * CFrame.new(0, height + 2, 0), Vector3.new(6, 4, 6), color, Enum.Material.Metal)
	local cab = B:Detail(base * CFrame.new(0, height + 2.5, -3.05), Vector3.new(4, 2, 0.1), rgb(150, 200, 230), Enum.Material.Glass)
	cab.Transparency = 0.3
	B:Box(base * CFrame.new(0, height + 4.6, -jib / 2 + 4), Vector3.new(2.4, 1.2, jib), color, Enum.Material.Metal, { Name = "CraneJib" })
	B:Box(base * CFrame.new(0, height + 4.6, 9), Vector3.new(2.4, 1.2, 14), color, Enum.Material.Metal)
	B:Box(base * CFrame.new(0, height + 3, 14), Vector3.new(5, 4, 4), rgb(80, 80, 86), Enum.Material.Concrete)
	local hookPoint = base * CFrame.new(0, height + 4, -jib + 6)
	B:Rod(hookPoint.Position, (hookPoint * CFrame.new(0, -12, 0)).Position, 0.2, rgb(40, 40, 40), Enum.Material.Metal, { Decor = true, CanCollide = false })
	B:Box(hookPoint * CFrame.new(0, -12.6, 0), Vector3.new(1.2, 1.2, 1.2), rgb(240, 180, 40), Enum.Material.Metal)
	return (base * CFrame.new(0, height + 5.4, 0)).Position, (base * CFrame.new(0, height + 5.4, -jib + 8)).Position
end

function Props.HazardStripes(B: Builder, cframe: CFrame, length: number)
	for i = 0, math.floor(length / 2) - 1 do
		B:Detail(cframe * CFrame.new(-length / 2 + i * 2 + 1, 0, 0), Vector3.new(1, 0.06, 0.6), if i % 2 == 0 then rgb(240, 190, 30) else rgb(25, 25, 25), Enum.Material.SmoothPlastic)
	end
end

-- Nature -----------------------------------------------------------------------------------

function Props.Tree(B: Builder, base: CFrame, height: number, leaf: Color3, bark: Color3?): Vector3
	local trunk = B:Cylinder(base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), height, height * 0.12 + 0.6, bark or rgb(110, 80, 58), Enum.Material.Wood)
	trunk.Name = "Trunk"
	local crown = height * 0.42
	B:Detail(base * CFrame.new(0, height, 0), Vector3.new(crown, crown * 0.8, crown), leaf, Enum.Material.LeafyGrass, { Shape = Enum.PartType.Ball, CanCollide = true })
	B:Detail(base * CFrame.new(crown * 0.35, height - crown * 0.2, crown * 0.2), Vector3.new(crown * 0.7, crown * 0.6, crown * 0.7), leaf:Lerp(Color3.new(1, 1, 0.6), 0.1), Enum.Material.LeafyGrass, { Shape = Enum.PartType.Ball })
	return (base * CFrame.new(0, height + crown * 0.4, 0)).Position
end

-- A giant climbable tree with a platform in its canopy.
function Props.GiantTree(B: Builder, base: CFrame, height: number, leaf: Color3): (Vector3, Vector3)
	local width = 9
	B:Cylinder(base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), height, width, rgb(100, 72, 52), Enum.Material.Wood)
	-- Vines on one side make the trunk climbable.
	local vines = B:Box(base * CFrame.new(0, height / 2, -width / 2 + 0.2), Vector3.new(4, height, 0.6), rgb(60, 110, 55), Enum.Material.LeafyGrass, {
		Name = "TrunkVines",
		Tag = Tags.Climbable,
		Attrs = { Kind = "Vines" },
	})
	B:Icon(vines, "#", rgb(150, 230, 140), Vector3.new(0, height / 2 + 1, 0))
	for i = 1, 5 do
		local angle = i * 1.3
		local root = base * CFrame.Angles(0, angle, 0) * CFrame.new(0, 1.2, width * 0.55)
		B:Detail(root * CFrame.Angles(math.rad(35), 0, 0), Vector3.new(1.6, 1.6, 6), rgb(95, 68, 48), Enum.Material.Wood, { CanCollide = true })
	end
	local deck = base * CFrame.new(0, height, 0)
	B:Box(deck * CFrame.new(0, -0.5, 0), Vector3.new(16, 1, 16), rgb(120, 90, 60), Enum.Material.WoodPlanks, { Name = "CanopyDeck" })
	B:Detail(deck * CFrame.new(0, 9, 0), Vector3.new(34, 14, 34), leaf, Enum.Material.LeafyGrass, { Shape = Enum.PartType.Ball, CanCollide = false })
	B:Detail(deck * CFrame.new(12, 5, 6), Vector3.new(18, 10, 18), leaf:Lerp(Color3.new(1, 1, 0.5), 0.12), Enum.Material.LeafyGrass, { Shape = Enum.PartType.Ball, CanCollide = false })
	return deck.Position + Vector3.new(0, 0.2, 0), (base * CFrame.new(width * 0.9, 0.4, 0)).Position
end

function Props.Rock(B: Builder, position: Vector3, size: Vector3, color: Color3)
	B:Box(CFrame.new(position) * CFrame.Angles(B:Rand(-0.3, 0.3), B:Rand(0, math.pi), B:Rand(-0.3, 0.3)), size, color, Enum.Material.Rock)
end

function Props.Pine(B: Builder, base: CFrame, height: number, snow: boolean?)
	B:Cylinder(base * CFrame.new(0, height * 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)), height * 0.4, 1.2, rgb(90, 65, 45), Enum.Material.Wood, { Decor = true })
	for i = 0, 2 do
		local tier = height * (0.3 + i * 0.22)
		local size = height * (0.55 - i * 0.14)
		B:Detail(base * CFrame.new(0, tier, 0) * CFrame.Angles(0, math.rad(45 * i), 0), Vector3.new(size, height * 0.28, size), rgb(40, 85, 60), Enum.Material.LeafyGrass, { CanCollide = false })
		if snow then
			B:Detail(base * CFrame.new(0, tier + height * 0.14, 0) * CFrame.Angles(0, math.rad(45 * i), 0), Vector3.new(size * 0.8, 0.5, size * 0.8), rgb(240, 245, 250), Enum.Material.Snow, { CanCollide = false })
		end
	end
end

function Props.Flowers(B: Builder, center: Vector3, radius: number, colors: { Color3 }, count: number)
	for _ = 1, count do
		local p = center + Vector3.new(B:Rand(-radius, radius), 0.4, B:Rand(-radius, radius))
		B:Detail(CFrame.new(p), Vector3.new(0.6, 0.6, 0.6), B:Pick(colors), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball, CanCollide = false })
	end
end

function Props.Column(B: Builder, base: CFrame, height: number, color: Color3, broken: boolean?): Vector3
	local h = if broken then height * B:Rand(0.4, 0.8) else height
	B:Cylinder(base * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), h, 2.4, color, Enum.Material.Marble)
	B:Box(base * CFrame.new(0, 0.4, 0), Vector3.new(3.2, 0.8, 3.2), color, Enum.Material.Marble)
	if not broken then
		B:Box(base * CFrame.new(0, h + 0.4, 0), Vector3.new(3.4, 0.8, 3.4), color, Enum.Material.Marble)
	end
	return (base * CFrame.new(0, h + 0.8, 0)).Position
end

function Props.Arch(B: Builder, base: CFrame, width: number, height: number, color: Color3, material: Enum.Material?)
	local m = material or Enum.Material.Marble
	for _, x in { -width / 2, width / 2 } do
		B:Box(base * CFrame.new(x, height / 2, 0), Vector3.new(2, height, 2), color, m)
	end
	B:Box(base * CFrame.new(0, height + 0.75, 0), Vector3.new(width + 2, 1.5, 2.2), color, m)
end

-- Floating rock underside for sky islands.
function Props.FloatingRock(B: Builder, top: CFrame, width: number, depth: number, color: Color3)
	local layers = 4
	for i = 1, layers do
		local f = 1 - (i - 1) / layers
		B:Box(top * CFrame.new(0, -i * depth / layers + depth / layers / 2 - 0.5, 0) * CFrame.Angles(0, i * 0.4, 0), Vector3.new(width * f, depth / layers, width * f), color:Lerp(Color3.new(0, 0, 0), i * 0.06), Enum.Material.Rock, { Decor = i > 1 })
	end
end

function Props.Crystal(B: Builder, position: Vector3, height: number, color: Color3)
	local crystal = B:Detail(CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(B:Rand(-0.2, 0.2), B:Rand(0, 1), B:Rand(-0.2, 0.2)), Vector3.new(height * 0.35, height, height * 0.35), color, Enum.Material.Neon)
	crystal.CanCollide = false
	if height > 4 then
		B:Light(crystal, color, height * 2, 0.7)
	end
end

-- City -------------------------------------------------------------------------------------

function Props.Billboard(B: Builder, base: CFrame, text: string, color: Color3, width: number?): BasePart
	local w = width or 14
	for _, x in { -w / 3, w / 3 } do
		B:Box(base * CFrame.new(x, 3, 0), Vector3.new(0.5, 6, 0.5), rgb(50, 52, 60), Enum.Material.Metal)
	end
	local panel = B:Box(base * CFrame.new(0, 8, 0), Vector3.new(w, w * 0.4, 0.6), rgb(20, 22, 30), Enum.Material.SmoothPlastic, { Name = "Billboard" })
	B:Text(panel, Enum.NormalId.Front, text, { Color = color, Padding = 6 })
	B:Text(panel, Enum.NormalId.Back, text, { Color = color, Padding = 6 })
	B:Light(panel, color, 20, 1, "Surface", Enum.NormalId.Front)
	return panel
end

function Props.Antenna(B: Builder, base: CFrame, height: number): Vector3
	B:Box(base * CFrame.new(0, height / 2, 0), Vector3.new(0.6, height, 0.6), rgb(150, 150, 160), Enum.Material.Metal)
	for y = 3, height - 2, 4 do
		B:Detail(base * CFrame.new(0, y, 0), Vector3.new(3 - y / height * 2, 0.15, 0.15), rgb(150, 150, 160), Enum.Material.Metal)
	end
	local light = B:Detail(base * CFrame.new(0, height + 0.3, 0), Vector3.new(0.6, 0.6, 0.6), rgb(255, 40, 40), Enum.Material.Neon, { Shape = Enum.PartType.Ball })
	B:Light(light, rgb(255, 40, 40), 10, 0.8)
	return (base * CFrame.new(0, height, 0)).Position
end

function Props.Hologram(B: Builder, base: CFrame, size: number, color: Color3)
	local holo = B:Detail(base * CFrame.new(0, size, 0) * CFrame.Angles(0, B:Rand(0, 1), math.rad(45)), Vector3.one * size, color, Enum.Material.ForceField)
	holo.CanCollide = false
	local core = B:Detail(base * CFrame.new(0, size, 0), Vector3.one * size * 0.3, color, Enum.Material.Neon, { Shape = Enum.PartType.Ball })
	B:Light(core, color, size * 4, 1)
	B:Detail(base * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.6, size * 0.8, size * 0.8), rgb(40, 44, 60), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, CanCollide = true })
end

-- Windows on a building face: rows of lit or dark panes (decor).
function Props.Windows(B: Builder, face: CFrame, width: number, height: number, lit: Color3, dark: Color3, chance: number)
	local cols = math.max(1, math.floor(width / 5))
	local rows = math.max(1, math.floor(height / 6))
	if rows * cols > 40 then
		rows = math.max(1, math.floor(40 / cols))
	end
	for r = 0, rows - 1 do
		for c = 0, cols - 1 do
			local x = -width / 2 + (c + 0.5) * (width / cols)
			local y = -(r + 0.5) * (height / rows) - 2
			local isLit = B:Rand(0, 1) < chance
			B:Detail(face * CFrame.new(x, y, -0.06), Vector3.new(2.2, 2.6, 0.1), if isLit then lit else dark, if isLit then Enum.Material.Neon else Enum.Material.Glass)
		end
	end
end

return Props

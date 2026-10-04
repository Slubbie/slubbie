-- Ironworks Quarter: the foundries that built the skyways. Steel gantries on
-- lattice legs, conveyors, steam vents, cranes swinging cargo, smokestacks and
-- the Titan Crane towering over everything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Districts = require(ReplicatedStorage.Shared.Config.Districts)
local Tags = require(ReplicatedStorage.Shared.Tags)

local DistrictBuilder = require(script.Parent.Parent.DistrictBuilder)
local Props = require(script.Parent.Parent.Props)

local P = Districts.ById.Ironworks.Palette

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local CONTAINERS = { rgb(170, 70, 50), rgb(60, 110, 150), rgb(200, 150, 40), rgb(70, 120, 80), rgb(120, 120, 130) }

local Ironworks = {}

local function legs(B, top: CFrame, width: number, length: number, depth: number)
	-- Lattice legs at the corners with a cross brace: gantries, not buildings.
	local hx, hz = width / 2 - 1, length / 2 - 1
	for _, corner in { Vector3.new(-hx, 0, -hz), Vector3.new(hx, 0, -hz), Vector3.new(-hx, 0, hz), Vector3.new(hx, 0, hz) } do
		B:Box(top * CFrame.new(corner) * CFrame.new(0, -depth / 2, 0), Vector3.new(1.4, depth, 1.4), P.SteelDark, Enum.Material.Metal, { Name = "Leg" })
	end
	if length >= 12 then
		for _, side in { -1, 1 } do
			B:Detail(top * CFrame.new(side * hx, -depth * 0.3, 0) * CFrame.Angles(math.atan2(depth * 0.4, length - 2), 0, 0), Vector3.new(0.5, 0.5, math.sqrt((length - 2) ^ 2 + (depth * 0.4) ^ 2)), P.SteelDark, Enum.Material.Metal)
		end
	end
end

Ironworks.CourseTheme = {
	Id = "Ironworks",
	Surface = P.SteelDark,
	SurfaceMaterial = Enum.Material.DiamondPlate,
	Trim = P.Hazard,
	Wall = P.Rust,
	WallMaterial = Enum.Material.CorrodedMetal,
	Accent = P.Accent,
	Signal = P.Signal,
	Beam = P.Steel,
	BeamMaterial = Enum.Material.Metal,
	Rope = rgb(60, 60, 60),
	Climb = "Mesh",
	BodyDepth = 34,
	Platform = function(B, top, width, length, role)
		B:Box(top * CFrame.new(0, -0.75, 0), Vector3.new(width, 1.5, length), if role == "Checkpoint" then P.Concrete else B:Vary(P.SteelDark, 0.05), if role == "Checkpoint" then Enum.Material.Concrete else Enum.Material.DiamondPlate, { Name = "Gantry" })
		if role ~= "Floating" and role ~= "Recovery" and length >= 10 then
			-- Yellow-black edge stripes.
			B:Detail(top * CFrame.new(width / 2 - 0.3, 0.03, 0), Vector3.new(0.6, 0.06, length), P.Hazard, Enum.Material.SmoothPlastic)
		end
	end,
	Body = legs,
	WallStyle = function(B, cframe, size)
		local wall = B:Box(cframe, size, B:Pick(CONTAINERS), Enum.Material.CorrodedMetal, { Name = "ContainerWall" })
		return wall
	end,
}

Ironworks.RoomTheme = {
	Id = "IronworksRoom",
	Surface = P.SteelDark,
	SurfaceMaterial = Enum.Material.DiamondPlate,
	Trim = P.Hazard,
	Wall = P.Steel,
	WallMaterial = Enum.Material.Metal,
	Accent = P.Accent,
	Signal = P.Signal,
	Beam = P.Steel,
	BeamMaterial = Enum.Material.Metal,
	Rope = rgb(60, 60, 60),
	Climb = "Mesh",
	BodyDepth = 0,
}

function Ironworks.Plaza(B, ctx)
	local origin = ctx.Origin
	local R = DistrictBuilder.PlazaRadius
	B:Box(origin * CFrame.new(0, -1, 0), Vector3.new(R * 2, 2, R * 2), P.Concrete, Enum.Material.Concrete, { Name = "FoundryYard" })
	B:Box(origin * CFrame.new(0, -30, 0), Vector3.new(R * 2 - 4, 56, R * 2 - 4), P.Steel, Enum.Material.CorrodedMetal)
	for i = 0, 3 do
		Props.HazardStripes(B, origin * CFrame.Angles(0, i * math.pi / 2, 0) * CFrame.new(0, 0.03, -R + 1.2), R * 2 - 4)
	end
	-- The furnace: a glowing kiln that lights the whole yard.
	local side = ctx.HubDir:Cross(Vector3.yAxis)
	local furnaceCF = CFrame.lookAt(ctx.Origin.Position - ctx.HubDir * 30, ctx.Origin.Position)
	B:Box(furnaceCF * CFrame.new(0, 7, 0), Vector3.new(16, 14, 10), P.Rust, Enum.Material.Brick, { Name = "Furnace" })
	local mouth = B:Detail(furnaceCF * CFrame.new(0, 4, -5.05), Vector3.new(6, 5, 0.2), P.Glow, Enum.Material.Neon)
	B:Light(mouth, P.Glow, 40, 2.5, "Surface", Enum.NormalId.Front)
	local fireAttachment = Instance.new("Attachment")
	fireAttachment.Parent = mouth
	B:Emitter(fireAttachment, "Sparks", P.Glow)
	Props.Smokestack(B, furnaceCF * CFrame.new(5, 14, 2), 22, P.Rust, true)
	-- Workbench, containers, crates: places to sit and wait for your crew.
	Props.Container(B, CFrame.lookAt(ctx.Origin.Position + side * 32, ctx.Origin.Position + side * 32 + ctx.HubDir), CONTAINERS[2])
	for i = 0, 2 do
		Props.Crate(B, CFrame.new(ctx.Origin.Position - side * 30 + ctx.HubDir * (i * 3 - 3)), 2.6, rgb(150, 110, 70))
		Props.Barrel(B, CFrame.new(ctx.Origin.Position - side * 36 + ctx.HubDir * (i * 3 - 3)), CONTAINERS[i + 1])
	end
	for i = 0, 3 do
		local corner = origin * CFrame.Angles(0, i * math.pi / 2 + math.pi / 4, 0) * CFrame.new(0, 0, -R + 4)
		Props.Lamp(B, corner, rgb(255, 180, 110), 11)
	end
	-- An overhead gantry crane spanning the yard.
	for _, s in { -1, 1 } do
		B:Box(origin * CFrame.new(s * (R - 3), 11, 0), Vector3.new(2, 22, 2), P.Hazard, Enum.Material.Metal)
	end
	B:Box(origin * CFrame.new(0, 22.5, 0), Vector3.new(R * 2 - 4, 2, 3), P.Hazard, Enum.Material.Metal, { Name = "GantryBeam" })
	DistrictBuilder.NPCSpot(ctx, "iron_sadie", CFrame.lookAt(ctx.Origin.Position - ctx.HubDir * 20 + side * 8 + Vector3.new(0, 3, 0), ctx.Origin.Position + Vector3.new(0, 3, 0)))
	DistrictBuilder.NPCSpot(ctx, "iron_brak", CFrame.lookAt(ctx.Origin.Position + side * 24 + Vector3.new(0, 3, 0), ctx.Origin.Position + Vector3.new(0, 3, 0)))
	DistrictBuilder.NPCSpot(ctx, "iron_rook", CFrame.lookAt(ctx.Origin.Position - side * 26 + Vector3.new(0, 3, 0), ctx.Origin.Position + Vector3.new(0, 3, 0)))
	-- Tool crib (district shop).
	local crib = CFrame.lookAt(ctx.Origin.Position - ctx.HubDir * 30 - side * 18, ctx.Origin.Position)
	B:Box(crib * CFrame.new(0, 1.5, 0), Vector3.new(8, 3, 3), P.Steel, Enum.Material.Metal, { Name = "ToolCrib" })
	local cage = B:Box(crib * CFrame.new(0, 6, 1.5), Vector3.new(9, 0.4, 5), P.Hazard, Enum.Material.Metal)
	B:Prompt(cage, "Browse", "Tool Crib", { Name = "ShopPrompt", Distance = 12, Attrs = { Board = "Shop", District = "Ironworks" } })
end

function Ironworks.Building(B, ctx, top: CFrame, size: Vector3)
	local w, d = size.X, size.Z
	local depth = 70
	B:Box(top * CFrame.new(0, -depth / 2 - 1, 0), Vector3.new(w, depth, d), B:Pick({ P.Steel, P.Rust, P.Concrete }), Enum.Material.CorrodedMetal, { Name = "Factory" })
	B:Box(top * CFrame.new(0, -1, 0), Vector3.new(w + 0.4, 2, d + 0.4), P.SteelDark, Enum.Material.DiamondPlate, { Name = "FactoryRoof" })
	-- Sawtooth skylights.
	for i = -1, 1 do
		B:Wedge(top * CFrame.new(0, 1.2, i * d / 3) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(w * 0.7, 2.4, 3), rgb(150, 190, 210), Enum.Material.Glass, { Decor = true })
	end
	local spots = { Roof = (top * CFrame.new(-w / 4, 0.2, -d / 4)).Position, High = {}, Nooks = {} }
	local roll = B:Rand(0, 1)
	if roll < 0.45 then
		local high, nook = Props.Smokestack(B, top * CFrame.new(w / 4, 0, d / 4), B:Rand(16, 30), P.Rust, B:Rand(0, 1) < 0.5)
		table.insert(spots.High, high)
		table.insert(spots.Nooks, nook)
	elseif roll < 0.75 then
		local high = Props.Container(B, top * CFrame.new(0, 0, d / 6), B:Pick(CONTAINERS))
		table.insert(spots.High, high)
		table.insert(spots.Nooks, (top * CFrame.new(w / 2 - 1.5, 0.2, -d / 2 + 1.5)).Position)
	else
		-- Pipe run with a steam vent.
		local a = (top * CFrame.new(-w / 2 + 2, 2, 0)).Position
		local b = (top * CFrame.new(w / 2 - 2, 2, 0)).Position
		Props.Pipe(B, a, b, P.Pipe, 1.8)
		local vent = B:Detail(top * CFrame.new(0, 3, 0), Vector3.new(1.2, 1.2, 1.2), P.SteelDark, Enum.Material.Metal)
		local attachment = Instance.new("Attachment")
		attachment.Parent = vent
		B:Emitter(attachment, "Smoke", rgb(220, 220, 220)).Rate = 1
		table.insert(spots.Nooks, (top * CFrame.new(1.5, 0.2, 1.5)).Position)
	end
	Props.Crate(B, top * CFrame.new(-w / 2 + 2, 0, d / 2 - 2), 2.4, rgb(150, 110, 70))
	-- Catwalk along one side to hang from.
	local walk = top * CFrame.new(w / 2 + 1.2, -6, 0)
	B:Box(walk, Vector3.new(2.4, 0.4, d - 2), P.SteelDark, Enum.Material.DiamondPlate, { Name = "Catwalk" })
	B:Detail(walk * CFrame.new(1.1, 1, 0), Vector3.new(0.2, 1.8, d - 2), P.Hazard, Enum.Material.Metal, { CanCollide = true })
	table.insert(spots.Nooks, (walk * CFrame.new(0, 0.5, d / 3)).Position)
	return spots
end

function Ironworks.Connector(B, ctx, a: Vector3, b: Vector3)
	-- I-beams between gantries (balance), or a cable run downhill.
	if a.Y - b.Y > 5 then
		local start = a + Vector3.new(0, 7.5, 0)
		local finish = b + Vector3.new(0, 5.5, 0)
		B:Box(CFrame.new(a + Vector3.new(0, 4, 0)), Vector3.new(0.6, 8, 0.6), P.Hazard, Enum.Material.Metal)
		B:Box(CFrame.new(b + Vector3.new(0, 3, 0)), Vector3.new(0.6, 6, 0.6), P.Hazard, Enum.Material.Metal)
		local cable = B:Rod(start, finish, 0.22, rgb(40, 40, 40), Enum.Material.Metal, { Name = "CableRun", CanCollide = false, Tag = Tags.Zipline, Attrs = { A = start, B = finish } })
		B:Icon(cable, "~", P.Signal, Vector3.new(0, 1.5, 0))
	else
		local beam = B:Beam(a - Vector3.new(0, 0.5, 0), b - Vector3.new(0, 0.5, 0), 1.3, 1, P.Steel, Enum.Material.Metal, { Name = "IBeam", Tag = Tags.Balance })
		B:Icon(beam, "=", rgb(255, 255, 255), Vector3.new(0, 2, 0))
	end
end

function Ironworks.Landmarks(B, ctx)
	-- The Titan Crane.
	local basePos = DistrictBuilder.FindClear(ctx, 560, 30)
	local base = CFrame.lookAt(basePos, ctx.Origin.Position)
	B:Box(base * CFrame.new(0, -1, 0), Vector3.new(26, 2, 26), P.Concrete, Enum.Material.Concrete, { Name = "TitanBase" })
	B:Box(base * CFrame.new(0, -40, 0), Vector3.new(24, 76, 24), P.Concrete, Enum.Material.Concrete)
	local cabTop, jibEnd = Props.Crane(B, base, 70, 60, P.Hazard)
	DistrictBuilder.QuestPoint(ctx, "iron_master", cabTop + Vector3.new(0, 0.5, 0))
	DistrictBuilder.QuestPoint(ctx, "iron_relay_1", jibEnd + Vector3.new(0, 0.5, 0))
	DistrictBuilder.Landmark(ctx, "titan", "The Titan Crane", CFrame.new(cabTop + Vector3.new(0, 2, 0)), Vector3.new(14, 6, 14))
	B:FarBox(base * CFrame.new(0, 35, 0), Vector3.new(5, 70, 5), P.Hazard)
	B:FarBox(base * CFrame.new(0, 74.6, -26), Vector3.new(2.4, 1.2, 60), P.Hazard)
	-- Swinging cargo on the Titan's hook, for spectacle.
	B:Box(CFrame.new(jibEnd + Vector3.new(0, -16, 0)), Vector3.new(8, 8, 16), CONTAINERS[1], Enum.Material.CorrodedMetal, {
		Name = "TitanCargo",
		Tag = Tags.Mover,
		Attrs = { Kind = "Pendulum", Pivot = jibEnd + Vector3.new(0, -2, 0), Axis = base.RightVector, Amplitude = math.rad(8), Period = 7, Phase = 0, Origin = CFrame.new(jibEnd + Vector3.new(0, -16, 0)) },
	})

	-- The Great Furnace: a stepped hall with three smokestacks.
	local hallPos = DistrictBuilder.FindClear(ctx, 520, 30) + Vector3.new(0, 6, 0)
	local hall = CFrame.lookAt(hallPos, ctx.Origin.Position + Vector3.new(0, 6, 0))
	B:Box(hall * CFrame.new(0, -40, 0), Vector3.new(40, 80, 30), P.Rust, Enum.Material.Brick, { Name = "GreatFurnace" })
	B:Box(hall * CFrame.new(0, -1, 0), Vector3.new(40.4, 2, 30.4), P.SteelDark, Enum.Material.DiamondPlate)
	local glow = B:Detail(hall * CFrame.new(0, -12, -15.1), Vector3.new(20, 10, 0.2), P.Glow, Enum.Material.Neon)
	B:Light(glow, P.Glow, 60, 3, "Surface", Enum.NormalId.Front)
	local tops = {}
	for i = -1, 1 do
		local top = Props.Smokestack(B, hall * CFrame.new(i * 12, 0, 6), 34 + i * 4, P.Rust, true)
		table.insert(tops, top)
	end
	DistrictBuilder.QuestPoint(ctx, "iron_relay_2", tops[1] + Vector3.new(0, 0.5, 0))
	DistrictBuilder.QuestPoint(ctx, "iron_relay_3", tops[3] + Vector3.new(0, 0.5, 0))
	DistrictBuilder.Landmark(ctx, "furnace", "The Great Furnace", hall * CFrame.new(0, 4, 0), Vector3.new(40, 8, 30))
	B:FarBox(hall * CFrame.new(0, -30, 0), Vector3.new(40, 60, 30), P.Rust)
end

function Ironworks.QuestPoints(B, ctx)
	DistrictBuilder.QuestPoint(ctx, "iron_relay_4", DistrictBuilder.TakeHigh(ctx) + Vector3.new(0, 1, 0))
	DistrictBuilder.QuestPoint(ctx, "iron_relay_5", DistrictBuilder.TakeHigh(ctx) + Vector3.new(0, 1, 0))
	for i = 1, 6 do
		local spot = if i % 2 == 0 then DistrictBuilder.TakeNook(ctx) else DistrictBuilder.TakeHigh(ctx)
		DistrictBuilder.QuestPoint(ctx, "iron_scrap_" .. i, spot + Vector3.new(0, 1, 0))
	end
end

function Ironworks.Skyline(B, ctx)
	for i = 0, 9 do
		local angle = i * math.pi / 5 + 0.2
		local p = ctx.Origin.Position + DistrictBuilder.Dir(angle) * (680 + B:Rand(-40, 40))
		local h = B:Rand(70, 140)
		B:FarBox(CFrame.new(p + Vector3.new(0, -60 + h / 2, 0)), Vector3.new(8, h, 8), P.Rust)
		B:FarBox(CFrame.new(p + Vector3.new(14, -80 + h / 4, 0)), Vector3.new(50, h / 2, 40), P.Steel)
		local top = B:Detail(CFrame.new(p + Vector3.new(0, -60 + h, 0)), Vector3.new(10, 1, 10), P.SteelDark, Enum.Material.Metal)
		local attachment = Instance.new("Attachment")
		attachment.Parent = top
		B:Emitter(attachment, "Smoke", rgb(110, 100, 95))
	end
	-- Molten glow from the foundry floor far below.
	for i = 1, 12 do
		local p = ctx.Origin.Position + DistrictBuilder.Dir(B:Rand(0, math.pi * 2)) * B:Rand(160, 520) + Vector3.new(0, -90, 0)
		local pool = B:Detail(CFrame.new(p), Vector3.new(B:Rand(20, 40), 1, B:Rand(20, 40)), P.Glow, Enum.Material.Neon)
		pool.CanCollide = false
		B:Light(pool, P.Glow, 60, 2)
	end
	B:Volume(ctx.Origin * CFrame.new(0, -ctx.District.KillDepth, 0), Vector3.new(1600, 10, 1600), Tags.KillZone, { District = "Ironworks" })
end

return Ironworks

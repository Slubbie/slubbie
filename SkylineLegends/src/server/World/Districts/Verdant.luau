-- Verdant Hollow: the old botanical tier, swallowed by its gardens. Mossy
-- stone ruins on root-wrapped pillars, giant climbable trees, vine swings,
-- crumbling terraces, the Great Falls and the Starfall Observatory.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Districts = require(ReplicatedStorage.Shared.Config.Districts)
local Tags = require(ReplicatedStorage.Shared.Tags)

local DistrictBuilder = require(script.Parent.Parent.DistrictBuilder)
local Props = require(script.Parent.Parent.Props)

local P = Districts.ById.Verdant.Palette

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local FLOWERS = { P.Flower, rgb(255, 220, 120), rgb(180, 140, 255), rgb(255, 255, 255) }

local Verdant = {}

local function ruinBody(B, top: CFrame, width: number, length: number, depth: number)
	-- A stone pillar wrapped in roots, narrower than the platform it holds up.
	B:Box(
		top * CFrame.new(0, -depth / 2, 0),
		Vector3.new(width * 0.7, depth, length * 0.7),
		B:Vary(P.StoneDark, 0.08),
		Enum.Material.Slate,
		{ Name = "Pillar" }
	)
	if length >= 12 then
		for _, side in { -1, 1 } do
			B:Detail(
				top * CFrame.new(side * width * 0.36, -depth * 0.35, 0) * CFrame.Angles(0, 0, math.rad(side * 8)),
				Vector3.new(1.4, depth * 0.7, 1.4),
				P.Bark,
				Enum.Material.Wood
			)
		end
	end
	B:Detail(
		top * CFrame.new(0, -1.3, 0),
		Vector3.new(width + 0.4, 0.6, length + 0.4),
		P.Moss,
		Enum.Material.LeafyGrass
	)
end

Verdant.CourseTheme = {
	Id = "Verdant",
	Surface = P.Stone,
	SurfaceMaterial = Enum.Material.Slate,
	Trim = P.Bark,
	Wall = P.StoneDark,
	WallMaterial = Enum.Material.Cobblestone,
	Accent = P.Accent,
	Signal = P.Signal,
	Beam = P.Bark,
	BeamMaterial = Enum.Material.Wood,
	Rope = rgb(80, 130, 60),
	Climb = "Vines",
	BodyDepth = 40,
	Platform = function(B, top, width, length, role)
		B:Box(
			top * CFrame.new(0, -1, 0),
			Vector3.new(width, 2, length),
			B:Vary(P.Stone, 0.06),
			Enum.Material.Slate,
			{ Name = "Terrace" }
		)
		if role ~= "Recovery" and length >= 12 and B:Rand(0, 1) < 0.5 then
			B:Detail(
				top * CFrame.new(width / 2 - 1, 0.25, B:Rand(-length / 3, length / 3)),
				Vector3.new(2, 0.5, 3),
				P.Moss,
				Enum.Material.LeafyGrass
			)
		end
	end,
	Body = ruinBody,
	AnchorMount = function(B, position)
		B:Beam(
			position + Vector3.new(-8, 4, 0),
			position + Vector3.new(8, 3, 0),
			1.6,
			1.6,
			P.Bark,
			Enum.Material.Wood,
			{ Decor = true }
		)
		B:Detail(
			CFrame.new(position + Vector3.new(0, 7, 0)),
			Vector3.new(14, 6, 10),
			P.Leaf,
			Enum.Material.LeafyGrass,
			{ Shape = Enum.PartType.Ball, CanCollide = false }
		)
	end,
}

Verdant.RoomTheme = {
	Id = "VerdantRoom",
	Surface = P.Stone,
	SurfaceMaterial = Enum.Material.Slate,
	Trim = P.Bark,
	Wall = P.StoneDark,
	WallMaterial = Enum.Material.Cobblestone,
	Accent = P.Accent,
	Signal = P.Signal,
	Beam = P.Bark,
	BeamMaterial = Enum.Material.Wood,
	Rope = rgb(80, 130, 60),
	Climb = "Vines",
	BodyDepth = 0,
}

function Verdant.Plaza(B, ctx)
	local origin = ctx.Origin
	local R = DistrictBuilder.PlazaRadius
	B:Cylinder(
		origin * CFrame.new(0, -1, 0) * CFrame.Angles(0, 0, math.rad(90)),
		2,
		R * 2,
		P.Stone,
		Enum.Material.Cobblestone,
		{ Name = "Glade" }
	)
	B:Cylinder(
		origin * CFrame.new(0, -34, 0) * CFrame.Angles(0, 0, math.rad(90)),
		64,
		R * 2 - 8,
		P.StoneDark,
		Enum.Material.Slate
	)
	-- The Glade tree at the centre: its vines are climbable, and its canopy is a lookout.
	local deck, nook = Props.GiantTree(B, origin * CFrame.new(0, 0, 0), 46, P.Leaf)
	DistrictBuilder.QuestPoint(ctx, "ver_seeds", ctx.Origin.Position + ctx.HubDir * 16 + Vector3.new(0, 2, 0))
	table.insert(ctx.High, deck)
	table.insert(ctx.Nooks, nook)
	-- Flowerbeds and glowing mushrooms.
	for i = 0, 5 do
		local angle = i * math.pi / 3 + 0.3
		local p = origin * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -R + 10)
		B:Box(p * CFrame.new(0, 0.4, 0), Vector3.new(8, 0.8, 5), P.Bark, Enum.Material.Wood)
		Props.Flowers(B, (p * CFrame.new(0, 0.8, 0)).Position, 3, FLOWERS, 6)
		local shroom = B:Detail(
			p * CFrame.new(5, 1.2, 0),
			Vector3.new(1.6, 0.6, 1.6),
			P.Signal,
			Enum.Material.Neon,
			{ Shape = Enum.PartType.Ball }
		)
		B:Light(shroom, P.Signal, 12, 0.7)
	end
	-- A pond.
	B:Cylinder(
		origin * CFrame.new(-18, 0.05, 18) * CFrame.Angles(0, 0, math.rad(90)),
		0.2,
		14,
		P.Water,
		Enum.Material.Glass,
		{ Decor = true, Transparency = 0.2 }
	)
	for i = 0, 4 do
		Props.Bench(B, origin * CFrame.Angles(0, i * 1.25 + 0.6, 0) * CFrame.new(0, 0, -20), P.Bark)
	end
	local side = ctx.HubDir:Cross(Vector3.yAxis)
	DistrictBuilder.NPCSpot(
		ctx,
		"ver_wren",
		CFrame.lookAt(
			ctx.Origin.Position + ctx.HubDir * 20 + side * 10 + Vector3.new(0, 3, 0),
			ctx.Origin.Position + Vector3.new(0, 3, 0)
		)
	)
	DistrictBuilder.NPCSpot(
		ctx,
		"ver_fern",
		CFrame.lookAt(
			ctx.Origin.Position - side * 24 + Vector3.new(0, 3, 0),
			ctx.Origin.Position + Vector3.new(0, 3, 0)
		)
	)
	-- Old Moss sits up on the tree deck, of course.
	DistrictBuilder.NPCSpot(ctx, "ver_moss", CFrame.lookAt(deck + Vector3.new(4, 3, 0), deck + Vector3.new(10, 3, 0)))
	-- Seed swap stall (district shop).
	local stall = CFrame.lookAt(ctx.Origin.Position - ctx.HubDir * 28 + side * 18, ctx.Origin.Position)
	B:Box(stall * CFrame.new(0, 1.5, 0), Vector3.new(8, 3, 3), P.Bark, Enum.Material.Wood, { Name = "SeedStall" })
	local canopy = B:Box(stall * CFrame.new(0, 7, 0.5), Vector3.new(10, 0.5, 6), P.Leaf, Enum.Material.LeafyGrass)
	for _, x in { -4, 4 } do
		B:Box(stall * CFrame.new(x, 3.5, 2), Vector3.new(0.5, 7, 0.5), P.Bark, Enum.Material.Wood)
	end
	B:Prompt(
		canopy,
		"Browse",
		"Seed Swap",
		{ Name = "ShopPrompt", Distance = 12, Attrs = { Board = "Shop", District = "Verdant" } }
	)
end

function Verdant.Building(B, ctx, top: CFrame, size: Vector3)
	local w, d = size.X, size.Z
	local spots = { Roof = (top * CFrame.new(0, 0.2, 0)).Position, High = {}, Nooks = {} }
	if B:Rand(0, 1) < 0.4 then
		-- A giant tree whose canopy deck is the "roof".
		local height = B:Rand(22, 34)
		local base = top * CFrame.new(0, -height, 0)
		B:Box(base * CFrame.new(0, -30, 0), Vector3.new(w * 0.6, 60, d * 0.6), P.StoneDark, Enum.Material.Slate)
		B:Box(base * CFrame.new(0, -1, 0), Vector3.new(w, 2, d), P.Stone, Enum.Material.Slate, { Name = "RootTerrace" })
		local deck, nook = Props.GiantTree(B, base, height, B:Vary(P.Leaf, 0.12))
		spots.Roof = base.Position + Vector3.new(w / 3, 0.2, 0)
		table.insert(spots.High, deck)
		table.insert(spots.Nooks, nook)
	else
		-- A ruined terrace with broken columns.
		ruinBody(B, top, w, d, 60)
		B:Box(
			top * CFrame.new(0, -1, 0),
			Vector3.new(w, 2, d),
			B:Vary(P.Stone, 0.06),
			Enum.Material.Slate,
			{ Name = "Ruin" }
		)
		for i = 0, 3 do
			local corner = top
				* CFrame.new((if i % 2 == 0 then -1 else 1) * (w / 2 - 2), 0, (if i < 2 then -1 else 1) * (d / 2 - 2))
			local columnTop = Props.Column(B, corner, B:Rand(8, 14), P.Stone, B:Rand(0, 1) < 0.5)
			if i == 0 then
				table.insert(spots.High, columnTop)
			end
		end
		Props.Flowers(B, (top * CFrame.new(0, 0.2, 0)).Position, w / 3, FLOWERS, 5)
		-- A collapsed lintel leaves a sheltered nook.
		B:Box(
			top * CFrame.new(-w / 4, 2, d / 4) * CFrame.Angles(0, 0, math.rad(20)),
			Vector3.new(10, 1.6, 3),
			P.StoneDark,
			Enum.Material.Slate
		)
		table.insert(spots.Nooks, (top * CFrame.new(-w / 4 - 2, 0.2, d / 4)).Position)
	end
	return spots
end

function Verdant.Connector(B, ctx, a: Vector3, b: Vector3)
	-- Fallen trunks to balance across, or a vine to swing.
	local dist = (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
	if dist > 18 and dist < 34 and math.abs(a.Y - b.Y) < 4 then
		local mid = (a + b) / 2 + Vector3.new(0, 14, 0)
		B:Beam(a + Vector3.new(0, 15, 0), b + Vector3.new(0, 15, 0), 1.4, 1.4, P.Bark, Enum.Material.Wood)
		local pivot = mid
		local rope = B:Rod(pivot, pivot - Vector3.new(0, 11, 0), 0.4, rgb(80, 130, 60), Enum.Material.Fabric, {
			Name = "Vine",
			CanCollide = false,
			Tag = Tags.SwingRope,
			Attrs = { Pivot = pivot, Length = 11 },
		})
		B:Icon(rope, "Y", P.Signal, Vector3.new(0, -2, 0))
		for _, p in { a, b } do
			B:Box(CFrame.new(p + Vector3.new(0, 8, 0)), Vector3.new(1.2, 16, 1.2), P.Bark, Enum.Material.Wood)
		end
	else
		local trunk = B:Beam(
			a - Vector3.new(0, 0.6, 0),
			b - Vector3.new(0, 0.6, 0),
			1.4,
			1.2,
			P.Bark,
			Enum.Material.Wood,
			{ Name = "FallenTrunk", Tag = Tags.Balance }
		)
		B:Icon(trunk, "=", rgb(255, 255, 255), Vector3.new(0, 2, 0))
	end
end

function Verdant.Landmarks(B, ctx)
	-- Starfall Observatory: a cracked dome on a tall ruined drum.
	local obsPos = DistrictBuilder.FindClear(ctx, 560, 30) + Vector3.new(0, 10, 0)
	local obs = CFrame.lookAt(obsPos, ctx.Origin.Position + Vector3.new(0, 10, 0))
	B:Cylinder(
		obs * CFrame.new(0, -40, 0) * CFrame.Angles(0, 0, math.rad(90)),
		80,
		34,
		P.StoneDark,
		Enum.Material.Slate,
		{ Name = "ObservatoryDrum" }
	)
	B:Cylinder(
		obs * CFrame.new(0, -1, 0) * CFrame.Angles(0, 0, math.rad(90)),
		2,
		36,
		P.Stone,
		Enum.Material.Slate,
		{ Name = "ObservatoryFloor" }
	)
	B:Box(obs * CFrame.new(0, -40, -17.3), Vector3.new(4, 80, 0.6), rgb(60, 110, 55), Enum.Material.LeafyGrass, {
		Name = "ObservatoryVines",
		Tag = Tags.Climbable,
		Attrs = { Kind = "Vines" },
	})
	-- Half dome (a ring of tilted slabs).
	for i = 0, 7 do
		local angle = i * math.pi / 8
		local slab = obs * CFrame.Angles(0, angle, 0) * CFrame.new(0, 9, -15) * CFrame.Angles(math.rad(-35), 0, 0)
		B:Box(slab, Vector3.new(11, 18, 1.4), rgb(220, 220, 210), Enum.Material.Marble)
	end
	local scope = obs * CFrame.new(0, 4, 4) * CFrame.Angles(math.rad(-40), 0, 0)
	B:Cylinder(
		scope * CFrame.Angles(0, math.rad(90), 0),
		16,
		3.4,
		rgb(180, 150, 90),
		Enum.Material.Metal,
		{ Name = "Telescope" }
	)
	B:Box(obs * CFrame.new(0, 1.5, 4), Vector3.new(3, 3, 3), P.StoneDark, Enum.Material.Slate)
	DistrictBuilder.QuestPoint(ctx, "ver_telescope", (obs * CFrame.new(0, 2, 0)).Position)
	DistrictBuilder.Landmark(
		ctx,
		"observatory",
		"Starfall Observatory",
		obs * CFrame.new(0, 4, 0),
		Vector3.new(34, 8, 34)
	)
	B:FarBox(obs * CFrame.new(0, -30, 0), Vector3.new(34, 60, 34), P.StoneDark)

	-- The Great Falls: a cliff with a waterfall and a hidden cave behind it.
	local fallsPos = DistrictBuilder.FindClear(ctx, 520, 34)
	local falls = CFrame.lookAt(fallsPos, ctx.Origin.Position)
	B:Box(falls * CFrame.new(0, -10, 8), Vector3.new(50, 100, 16), P.StoneDark, Enum.Material.Rock, { Name = "Cliff" })
	B:Box(
		falls * CFrame.new(0, 40.5, 4),
		Vector3.new(50, 1, 24),
		P.Moss,
		Enum.Material.LeafyGrass,
		{ Name = "ClifftopGrass" }
	)
	-- A ledge path up the cliff face.
	for i = 0, 5 do
		local ledge = falls * CFrame.new((if i % 2 == 0 then -1 else 1) * 16, i * 7 - 4, -1.5)
		B:Box(ledge, Vector3.new(10, 1, 3), P.Stone, Enum.Material.Slate, { Name = "CliffLedge" })
	end
	-- The water itself (no collision), its spray, and the pool.
	local water = B:Box(
		falls * CFrame.new(0, 10, -1),
		Vector3.new(14, 60, 1.6),
		P.Water,
		Enum.Material.Glass,
		{ Name = "Waterfall", CanCollide = false, Transparency = 0.25 }
	)
	water.CanQuery = false
	local spray = Instance.new("Attachment")
	spray.Position = Vector3.new(0, 28, 0)
	spray.Parent = water
	B:Emitter(spray, "Falls", rgb(220, 240, 255))
	local mist = Instance.new("Attachment")
	mist.Position = Vector3.new(0, -30, -2)
	mist.Parent = water
	B:Emitter(mist, "Mist", rgb(230, 245, 255))
	B:Box(falls * CFrame.new(0, -21, -10), Vector3.new(34, 2, 20), P.Stone, Enum.Material.Slate, { Name = "FallsPool" })
	B:Box(
		falls * CFrame.new(0, -19.9, -10),
		Vector3.new(30, 0.2, 16),
		P.Water,
		Enum.Material.Glass,
		{ Decor = true, Transparency = 0.2 }
	)
	-- The cave behind the curtain.
	B:Box(falls * CFrame.new(0, -14, 1.5), Vector3.new(12, 1, 6), P.Stone, Enum.Material.Slate, { Name = "CaveFloor" })
	local glow = B:Detail(falls * CFrame.new(0, -12, 3.5), Vector3.new(1, 1, 1), P.Signal, Enum.Material.Neon)
	B:Light(glow, P.Signal, 12, 1)
	DistrictBuilder.Secret(
		ctx,
		"waterfall",
		"Behind the Curtain",
		"A dry cave behind the falls. Someone left a bedroll and a very old map.",
		falls * CFrame.new(0, -11, 2),
		Vector3.new(12, 6, 6)
	)
	DistrictBuilder.Cache(ctx, 7, (falls * CFrame.new(3, -13.5, 2)).Position)
	DistrictBuilder.Landmark(ctx, "falls", "The Great Falls", falls * CFrame.new(0, 44, 4), Vector3.new(50, 8, 24))
	B:FarBox(falls * CFrame.new(0, -10, 8), Vector3.new(50, 100, 16), P.StoneDark)
end

function Verdant.QuestPoints(B, ctx)
	for i = 1, 5 do
		local spot = DistrictBuilder.TakeHigh(ctx)
		local page = B:Detail(
			CFrame.new(spot + Vector3.new(0, 0.6, 0)),
			Vector3.new(1, 0.05, 1.3),
			rgb(240, 235, 215),
			Enum.Material.Neon
		)
		page.CanCollide = false
		DistrictBuilder.QuestPoint(ctx, "ver_page_" .. i, spot + Vector3.new(0, 1, 0))
	end
	for _, id in { "ver_ruin_a", "ver_ruin_b", "ver_ruin_c" } do
		DistrictBuilder.QuestPoint(ctx, id, DistrictBuilder.TakeRoof(ctx) + Vector3.new(0, 1.5, 0))
	end
end

function Verdant.Skyline(B, ctx)
	for i = 0, 13 do
		local angle = i * math.pi / 7
		local p = ctx.Origin.Position + DistrictBuilder.Dir(angle) * (640 + B:Rand(-50, 50))
		local h = B:Rand(60, 120)
		B:FarBox(CFrame.new(p + Vector3.new(0, -70 + h / 2, 0)), Vector3.new(12, h, 12), P.Bark)
		B:FarBox(CFrame.new(p + Vector3.new(0, -70 + h, 0)), Vector3.new(60, 30, 60), P.Leaf)
	end
	-- Mist rolling over the drowned lower gardens.
	for i = 1, 10 do
		local p = ctx.Origin.Position
			+ DistrictBuilder.Dir(B:Rand(0, math.pi * 2)) * B:Rand(150, 500)
			+ Vector3.new(0, -70, 0)
		local pad = B:Detail(CFrame.new(p), Vector3.new(4, 1, 4), P.Water, Enum.Material.Glass)
		pad.Transparency = 1
		local attachment = Instance.new("Attachment")
		attachment.Parent = pad
		B:Emitter(attachment, "Mist", rgb(220, 240, 230))
	end
	B:Detail(
		ctx.Origin * CFrame.new(0, -100, 0),
		Vector3.new(1400, 1, 1400),
		rgb(60, 110, 100),
		Enum.Material.Glass,
		{ Transparency = 0.3, CanCollide = false }
	)
	B:Volume(
		ctx.Origin * CFrame.new(0, -ctx.District.KillDepth, 0),
		Vector3.new(1600, 10, 1600),
		Tags.KillZone,
		{ District = "Verdant" }
	)
end

return Verdant

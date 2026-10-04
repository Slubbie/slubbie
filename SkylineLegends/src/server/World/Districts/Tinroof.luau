-- Tinroof Terraces: the approachable residential rooftops. Brick terraces
-- separated by narrow alleys, water towers, washing lines, rooftop gardens
-- and the Old Bell, the tallest water tower in the Terraces.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Districts = require(ReplicatedStorage.Shared.Config.Districts)
local Tags = require(ReplicatedStorage.Shared.Tags)

local DistrictBuilder = require(script.Parent.Parent.DistrictBuilder)
local Props = require(script.Parent.Parent.Props)

local P = Districts.ById.Tinroof.Palette

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local BRICKS = { P.Brick, P.BrickDark, rgb(160, 110, 80), rgb(190, 140, 100), P.Plaster }
local SHEETS = { rgb(240, 240, 235), rgb(120, 180, 230), rgb(240, 150, 150), rgb(250, 220, 120), rgb(160, 210, 160) }
local LIT = rgb(255, 214, 150)
local DARK = rgb(40, 50, 60)

local Tinroof = {}

local function body(B, top: CFrame, width: number, length: number, depth: number)
	local color = B:Pick(BRICKS)
	B:Box(
		top * CFrame.new(0, -depth / 2, 0),
		Vector3.new(width, depth, length),
		color,
		if color == P.Plaster then Enum.Material.Plaster else Enum.Material.Brick,
		{ Name = "Terrace" }
	)
	-- A band of windows below the roofline on long terraces.
	if length >= 12 then
		for _, side in { -1, 1 } do
			local lit = B:Rand(0, 1) < 0.4
			B:Detail(
				top * CFrame.new(side * (width / 2 + 0.05), -5, 0),
				Vector3.new(0.12, 2.6, length * 0.8),
				if lit then LIT else DARK,
				if lit then Enum.Material.Neon else Enum.Material.Glass
			)
		end
	end
	-- Cornice under the roofline.
	B:Detail(
		top * CFrame.new(0, -0.6, 0),
		Vector3.new(width + 0.6, 0.6, length + 0.6),
		P.Plaster,
		Enum.Material.Concrete
	)
end

Tinroof.CourseTheme = {
	Id = "Tinroof",
	Surface = P.Roof,
	SurfaceMaterial = Enum.Material.Slate,
	Trim = P.Wood,
	Wall = P.Brick,
	WallMaterial = Enum.Material.Brick,
	Accent = P.Accent,
	Signal = P.Signal,
	Beam = P.Wood,
	BeamMaterial = Enum.Material.WoodPlanks,
	Rope = rgb(210, 190, 140),
	Climb = "Ladder",
	BodyDepth = 46,
	Platform = function(B, top, width, length, role)
		local material = if role == "Checkpoint"
				or role == "Start"
				or role == "Finish"
			then Enum.Material.WoodPlanks
			else Enum.Material.Slate
		local color = if material == Enum.Material.WoodPlanks then P.Wood else B:Vary(P.Roof, 0.08)
		B:Box(top * CFrame.new(0, -1, 0), Vector3.new(width, 2, length), color, material, { Name = "Roof" })
	end,
	Body = body,
	Deco = function(B, top, width, length)
		if B:Rand(0, 1) < 0.5 then
			local side = if B:Rand(0, 1) < 0.5 then -1 else 1
			local vent = B:Detail(
				top * CFrame.new(side * (width / 2 - 0.6), 1, B:Rand(-length / 3, length / 3)),
				Vector3.new(0.8, 2, 0.8),
				P.Tin,
				Enum.Material.Metal
			)
			vent.CanCollide = false
		end
	end,
}

Tinroof.RoomTheme = {
	Id = "TinroofRoom",
	Surface = P.Wood,
	SurfaceMaterial = Enum.Material.WoodPlanks,
	Trim = P.BrickDark,
	Wall = P.Plaster,
	WallMaterial = Enum.Material.Plaster,
	Accent = P.Accent,
	Signal = P.Signal,
	Beam = P.Wood,
	BeamMaterial = Enum.Material.WoodPlanks,
	Rope = rgb(210, 190, 140),
	Climb = "Ladder",
	BodyDepth = 0,
}

function Tinroof.Plaza(B, ctx)
	local origin = ctx.Origin
	local R = DistrictBuilder.PlazaRadius
	-- A big flat roof deck with a brick rim.
	B:Box(
		origin * CFrame.new(0, -1, 0),
		Vector3.new(R * 2, 2, R * 2),
		P.Wood,
		Enum.Material.WoodPlanks,
		{ Name = "PlazaDeck" }
	)
	B:Box(
		origin * CFrame.new(0, -24, 0),
		Vector3.new(R * 2 - 2, 44, R * 2 - 2),
		P.Brick,
		Enum.Material.Brick,
		{ Name = "PlazaBuilding" }
	)
	for _, side in { -1, 1 } do
		for _, axis in { "X", "Z" } do
			local offset = if axis == "X"
				then Vector3.new(side * (R - 0.5), 0.6, 0)
				else Vector3.new(0, 0.6, side * (R - 0.5))
			local size = if axis == "X" then Vector3.new(1, 1.2, R * 2) else Vector3.new(R * 2, 1.2, 1)
			B:Detail(origin * CFrame.new(offset), size, P.BrickDark, Enum.Material.Brick)
		end
	end
	-- Rooftop garden (Gran Petra) on one side, pigeon loft (Milo) on the other.
	local side = ctx.HubDir:Cross(Vector3.yAxis)
	local gardenCenter = ctx.Origin.Position - side * 26 - ctx.HubDir * 8
	for i = -1, 1 do
		Props.Planter(
			B,
			CFrame.lookAt(
				gardenCenter + side * 0 + ctx.HubDir * (i * 5),
				gardenCenter + side * 4 + ctx.HubDir * (i * 5)
			),
			B:Pick({ rgb(240, 90, 90), rgb(250, 210, 90), rgb(240, 140, 200) })
		)
	end
	B:Box(
		CFrame.new(gardenCenter + side * 4 + Vector3.new(0, 1.5, 0)),
		Vector3.new(3, 3, 3),
		rgb(120, 140, 160),
		Enum.Material.Metal,
		{ Name = "RainBarrel" }
	)
	DistrictBuilder.NPCSpot(
		ctx,
		"tin_petra",
		CFrame.lookAt(gardenCenter - side * 3 + Vector3.new(0, 3, 0), ctx.Origin.Position + Vector3.new(0, 3, 0))
	)
	DistrictBuilder.QuestPoint(ctx, "tin_seedlings", gardenCenter + Vector3.new(0, 2, 0))

	local loft = CFrame.lookAt(ctx.Origin.Position + side * 28 - ctx.HubDir * 6, ctx.Origin.Position)
	B:Box(loft * CFrame.new(0, 3, 0), Vector3.new(8, 6, 6), P.Wood, Enum.Material.WoodPlanks, { Name = "PigeonLoft" })
	B:Wedge(loft * CFrame.new(0, 7, 0), Vector3.new(8.4, 2, 6.4), P.Roof, Enum.Material.Slate)
	for i = -2, 2 do
		B:Detail(
			loft * CFrame.new(i * 1.4, 4, -3.05),
			Vector3.new(0.9, 0.9, 0.1),
			rgb(30, 25, 20),
			Enum.Material.SmoothPlastic
		)
	end
	DistrictBuilder.NPCSpot(ctx, "tin_milo", loft * CFrame.new(0, 3, -6) * CFrame.Angles(0, math.rad(180), 0))

	-- Mrs. Okafor by the noticeboard near the gate.
	DistrictBuilder.NPCSpot(
		ctx,
		"tin_okafor",
		CFrame.lookAt(
			ctx.Origin.Position + ctx.HubDir * 18 - side * 8 + Vector3.new(0, 3, 0),
			ctx.Origin.Position + Vector3.new(0, 3, 0)
		)
	)

	-- Washing lines and string lights over the square.
	Props.Clothesline(
		B,
		ctx.Origin.Position + Vector3.new(-30, 0, -30),
		ctx.Origin.Position + Vector3.new(-10, 0, -36),
		SHEETS
	)
	Props.Clothesline(
		B,
		ctx.Origin.Position + Vector3.new(30, 0, 30),
		ctx.Origin.Position + Vector3.new(36, 0, 10),
		SHEETS
	)
	for i = 0, 3 do
		local a = origin * CFrame.Angles(0, i * math.pi / 2, 0) * CFrame.new(0, 9, -R + 2)
		local b = origin * CFrame.Angles(0, (i + 1) * math.pi / 2, 0) * CFrame.new(0, 9, -R + 2)
		Props.StringLights(B, a.Position, b.Position, rgb(255, 210, 140))
		Props.Lamp(B, a * CFrame.new(0, -9, 0), rgb(255, 200, 130), 9)
	end
	-- Benches around a little fountain: somewhere to gather before a run.
	local fountain = origin * CFrame.new(0, 0, 0)
	B:Cylinder(
		fountain * CFrame.new(0, 0.8, 0) * CFrame.Angles(0, 0, math.rad(90)),
		1.6,
		12,
		P.Plaster,
		Enum.Material.Concrete
	)
	B:Cylinder(
		fountain * CFrame.new(0, 1.65, 0) * CFrame.Angles(0, 0, math.rad(90)),
		0.2,
		10.5,
		rgb(90, 170, 210),
		Enum.Material.Glass,
		{ Decor = true }
	)
	B:Cylinder(
		fountain * CFrame.new(0, 3, 0) * CFrame.Angles(0, 0, math.rad(90)),
		3,
		1.4,
		P.Plaster,
		Enum.Material.Concrete
	)
	for i = 0, 5 do
		local angle = i * math.pi / 3
		Props.Bench(
			B,
			origin * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, 12) * CFrame.Angles(0, math.rad(180), 0),
			P.Wood
		)
	end
	-- Market stall (district shop).
	local stall = CFrame.lookAt(ctx.Origin.Position - ctx.HubDir * 30 + side * 16, ctx.Origin.Position)
	B:Box(
		stall * CFrame.new(0, 1.5, 0),
		Vector3.new(8, 3, 3),
		P.Wood,
		Enum.Material.WoodPlanks,
		{ Name = "StallCounter" }
	)
	for _, x in { -3.8, 3.8 } do
		B:Box(stall * CFrame.new(x, 3.5, 1.2), Vector3.new(0.3, 7, 0.3), P.Wood, Enum.Material.Wood)
	end
	local awning = B:Box(
		stall * CFrame.new(0, 7.2, 0) * CFrame.Angles(math.rad(-12), 0, 0),
		Vector3.new(9, 0.3, 5),
		P.Fabric,
		Enum.Material.Fabric,
		{ Name = "StallAwning" }
	)
	B:Prompt(
		awning,
		"Browse",
		"Terrace Stall",
		{ Name = "ShopPrompt", Distance = 12, Attrs = { Board = "Shop", District = "Tinroof" } }
	)
end

function Tinroof.Building(B, ctx, top: CFrame, size: Vector3)
	local w, d = size.X, size.Z
	local depth = 60
	body(B, top, w, d, depth)
	local color = B:Vary(P.Roof, 0.1)
	B:Box(top * CFrame.new(0, -1, 0), Vector3.new(w, 2, d), color, Enum.Material.Slate, { Name = "Rooftop" })
	-- Parapet with gaps so you can still run off the edges.
	for _, side in { -1, 1 } do
		B:Detail(
			top * CFrame.new(side * (w / 2 - 0.3), 0.5, -d / 4),
			Vector3.new(0.6, 1, d / 2 - 2),
			P.BrickDark,
			Enum.Material.Brick,
			{ CanCollide = true }
		)
	end
	local spots = { Roof = (top * CFrame.new(0, 0.2, 0)).Position, High = {}, Nooks = {} }
	local roll = B:Rand(0, 1)
	if roll < 0.45 then
		local high, nook = Props.WaterTower(
			B,
			top * CFrame.new(w / 4, 0, d / 4),
			B:Rand(0.8, 1.1),
			B:Pick({ rgb(130, 95, 70), rgb(110, 120, 130), rgb(150, 110, 80) })
		)
		table.insert(spots.High, high)
		table.insert(spots.Nooks, nook)
	elseif roll < 0.75 then
		Props.Clothesline(
			B,
			(top * CFrame.new(-w / 2 + 2, 0, -d / 2 + 3)).Position,
			(top * CFrame.new(w / 2 - 2, 0, -d / 2 + 5)).Position,
			SHEETS
		)
		Props.Planter(B, top * CFrame.new(-w / 4, 0, d / 4), B:Pick({ rgb(240, 90, 90), rgb(250, 210, 90) }))
		table.insert(spots.Nooks, (top * CFrame.new(w / 2 - 1.5, 0.2, d / 2 - 1.5)).Position)
	else
		Props.Skylight(B, top * CFrame.new(0, 0, 0))
		Props.ACUnit(B, top * CFrame.new(w / 3, 0, -d / 3))
		table.insert(spots.Nooks, (top * CFrame.new(w / 3 + 2.2, 0.2, -d / 3)).Position)
	end
	local chimneyTop = Props.Chimney(B, top * CFrame.new(-w / 2 + 2.5, 0, d / 2 - 2.5), B:Pick(BRICKS), B:Rand(4, 7))
	table.insert(spots.High, chimneyTop)
	-- Balcony on the face toward the plaza: a ledge you can hang from.
	local balcony = top * CFrame.new(0, -7, -d / 2 - 1.4)
	B:Box(balcony, Vector3.new(8, 0.6, 2.8), P.Wood, Enum.Material.WoodPlanks, { Name = "Balcony" })
	B:Detail(
		balcony * CFrame.new(0, 1.2, -1.3),
		Vector3.new(8, 1.8, 0.2),
		P.Tin,
		Enum.Material.Metal,
		{ CanCollide = true }
	)
	table.insert(spots.Nooks, (balcony * CFrame.new(2.5, 0.5, 0.3)).Position)
	return spots
end

-- Wider rooftop gaps get a washing line to ride (downhill) or a plank to walk.
function Tinroof.Connector(B, ctx, a: Vector3, b: Vector3)
	if a.Y - b.Y > 4 then
		local start = a + Vector3.new(0, 7.5, 0)
		local finish = b + Vector3.new(0, 5.5, 0)
		Props.Clothesline(B, a, a + (b - a).Unit * 0.5, SHEETS)
		B:Box(CFrame.new(b + Vector3.new(0, 3, 0)), Vector3.new(0.5, 6, 0.5), P.Wood, Enum.Material.Wood)
		local cable = B:Rod(start, finish, 0.18, rgb(230, 230, 230), Enum.Material.SmoothPlastic, {
			Name = "WashLine",
			CanCollide = false,
			Tag = Tags.Zipline,
			Attrs = { A = start, B = finish },
		})
		B:Icon(cable, "~", P.Signal, Vector3.new(0, 1.5, 0))
	else
		local plank = B:Beam(
			a - Vector3.new(0, 0.5, 0),
			b - Vector3.new(0, 0.5, 0),
			1.3,
			1,
			P.Wood,
			Enum.Material.WoodPlanks,
			{ Name = "Plank", Tag = Tags.Balance }
		)
		B:Icon(plank, "=", rgb(255, 255, 255), Vector3.new(0, 2, 0))
	end
end

function Tinroof.Landmarks(B, ctx)
	-- The Old Bell: a giant water tower on a tall terrace, with the relay on top.
	local basePos = DistrictBuilder.FindClear(ctx, 560, 26) + Vector3.new(0, 18, 0)
	local base = CFrame.lookAt(basePos, ctx.Origin.Position + Vector3.new(0, 18, 0))
	body(B, base, 30, 30, 80)
	B:Box(base * CFrame.new(0, -1, 0), Vector3.new(30, 2, 30), P.Roof, Enum.Material.Slate, { Name = "BellRoof" })
	Props.Ladder(B, base * CFrame.new(0, -40, -15.1) * CFrame.Angles(0, math.rad(180), 0), 40, 3)
	local legH, tankH = 22, 18
	for _, offset in { Vector3.new(-6, 0, -6), Vector3.new(6, 0, -6), Vector3.new(-6, 0, 6), Vector3.new(6, 0, 6) } do
		B:Box(
			base * CFrame.new(offset) * CFrame.new(0, legH / 2, 0),
			Vector3.new(1.2, legH, 1.2),
			rgb(70, 60, 50),
			Enum.Material.Wood
		)
	end
	B:Box(
		base * CFrame.new(0, legH, 0),
		Vector3.new(20, 1, 20),
		rgb(90, 75, 60),
		Enum.Material.WoodPlanks,
		{ Name = "BellDeck" }
	)
	B:Cylinder(
		base * CFrame.new(0, legH + tankH / 2 + 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
		tankH,
		18,
		rgb(120, 90, 66),
		Enum.Material.WoodPlanks
	)
	B:Box(
		base * CFrame.new(0, legH + tankH + 1, 0),
		Vector3.new(19, 1, 19),
		rgb(80, 85, 90),
		Enum.Material.CorrodedMetal,
		{ Name = "BellTop" }
	)
	Props.Ladder(B, base * CFrame.new(0, 0, 9.4), legH + tankH + 1, 3)
	-- The bell itself, with its frame.
	local bellBase = base * CFrame.new(0, legH + tankH + 1.5, 0)
	Props.Arch(B, bellBase, 8, 7, rgb(90, 75, 60), Enum.Material.Wood)
	local bell = B:Box(
		bellBase * CFrame.new(0, 5, 0),
		Vector3.new(4, 4, 4),
		rgb(200, 160, 70),
		Enum.Material.Metal,
		{ Name = "OldBell" }
	)
	B:Light(bell, rgb(255, 210, 120), 30, 0.8)
	local relay = bellBase * CFrame.new(5, 0, 5)
	B:Box(
		relay * CFrame.new(0, 3, 0),
		Vector3.new(0.5, 6, 0.5),
		rgb(150, 150, 160),
		Enum.Material.Metal,
		{ Name = "RelayMast" }
	)
	DistrictBuilder.QuestPoint(ctx, "tin_relay", (relay * CFrame.new(0, 1.5, -2)).Position)
	DistrictBuilder.Landmark(ctx, "bell", "The Old Bell", bellBase * CFrame.new(0, 2, 0), Vector3.new(20, 6, 20))
	DistrictBuilder.Secret(
		ctx,
		"bell",
		"Ring the Bell",
		"You stood on the Old Bell itself. Somewhere below, a pigeon is very impressed.",
		bellBase * CFrame.new(0, 8.5, 0),
		Vector3.new(5, 4, 5)
	)
	B:FarBox(base * CFrame.new(0, legH / 2, 0), Vector3.new(18, legH + tankH, 18), rgb(120, 90, 66))

	-- Okafor House: the tallest terrace, balconies and awnings stepping up its face.
	local housePos = DistrictBuilder.FindClear(ctx, 520, 26) + Vector3.new(0, 26, 0)
	local house = CFrame.lookAt(housePos, ctx.Origin.Position + Vector3.new(0, 26, 0))
	body(B, house, 36, 26, 90)
	B:Box(house * CFrame.new(0, -1, 0), Vector3.new(36, 2, 26), P.Roof, Enum.Material.Slate, { Name = "OkaforRoof" })
	for i = 1, 6 do
		local y = -6 - i * 9
		local x = (if i % 2 == 0 then -1 else 1) * 9
		B:Box(
			house * CFrame.new(x, y, -14.5) * CFrame.Angles(math.rad(-15), 0, 0),
			Vector3.new(10, 0.4, 4),
			B:Pick(SHEETS),
			Enum.Material.Fabric,
			{ Name = "Awning" }
		)
		B:Box(
			house * CFrame.new(x, y - 3, -14),
			Vector3.new(9, 0.6, 3),
			P.Wood,
			Enum.Material.WoodPlanks,
			{ Name = "Balcony" }
		)
	end
	Props.Ladder(B, house * CFrame.new(0, -60, -13.1) * CFrame.Angles(0, math.rad(180), 0), 60, 3)
	Props.WaterTower(B, house * CFrame.new(-10, 0, 6), 1.1)
	DistrictBuilder.Landmark(ctx, "okafor", "Okafor House", house * CFrame.new(0, 4, 0), Vector3.new(36, 8, 26))
	B:FarBox(house * CFrame.new(0, -45, 0), Vector3.new(36, 90, 26), P.Brick)
end

function Tinroof.QuestPoints(B, ctx)
	-- Gran Petra's three gardens on three different roofs.
	for _, id in { "tin_garden_a", "tin_garden_b", "tin_garden_c" } do
		local roof = DistrictBuilder.TakeRoof(ctx)
		Props.Planter(B, CFrame.new(roof + Vector3.new(3, -0.2, 0)), rgb(250, 210, 90))
		DistrictBuilder.QuestPoint(ctx, id, roof + Vector3.new(0, 1.5, 0))
	end
	for i = 1, 5 do
		DistrictBuilder.QuestPoint(ctx, "tin_pigeon_" .. i, DistrictBuilder.TakeHigh(ctx) + Vector3.new(0, 1, 0))
	end
	DistrictBuilder.QuestPoint(ctx, "tin_party", DistrictBuilder.TakeRoof(ctx) + Vector3.new(0, 1.5, 0))
end

function Tinroof.Skyline(B, ctx)
	-- Far silhouettes of terraces ringing the district, and the lit streets below.
	for i = 0, 11 do
		local angle = i * math.pi / 6
		local r = 660 + B:Rand(-40, 40)
		local p = ctx.Origin.Position + DistrictBuilder.Dir(angle) * r
		local h = B:Rand(50, 110)
		B:FarBox(
			CFrame.new(p + Vector3.new(0, -60 + h / 2, 0)),
			Vector3.new(B:Rand(40, 70), h, B:Rand(40, 70)),
			B:Pick(BRICKS)
		)
		B:Detail(
			CFrame.new(p + Vector3.new(0, -70 + h / 2, 0)),
			Vector3.new(50, h, 50),
			B:Pick(BRICKS),
			Enum.Material.Brick,
			{ CanCollide = false }
		)
	end
	-- Street lamps far below, glimpsed through the alleys.
	for i = 1, 24 do
		local angle = B:Rand(0, math.pi * 2)
		local r = B:Rand(150, 520)
		local p = ctx.Origin.Position + DistrictBuilder.Dir(angle) * r + Vector3.new(0, -70, 0)
		local lamp = B:Detail(CFrame.new(p), Vector3.new(1, 1, 1), rgb(255, 190, 110), Enum.Material.Neon)
		lamp.CanCollide = false
		B:Light(lamp, rgb(255, 180, 100), 40, 1.5)
	end
	-- Kill zone well below the roofs: falling here returns you to safety.
	B:Volume(
		ctx.Origin * CFrame.new(0, -ctx.District.KillDepth, 0),
		Vector3.new(1600, 10, 1600),
		Tags.KillZone,
		{ District = "Tinroof" }
	)
end

return Tinroof

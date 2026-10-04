-- Frostreach: a mountain settlement of timber lodges on rock pillars, linked by
-- rope bridges and exposed ridges. Snow, ice, gusting wind, and the Hollowpeak
-- signal mast at the top of the world.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Districts = require(ReplicatedStorage.Shared.Config.Districts)
local Tags = require(ReplicatedStorage.Shared.Tags)

local DistrictBuilder = require(script.Parent.Parent.DistrictBuilder)
local Props = require(script.Parent.Parent.Props)

local P = Districts.ById.Frostreach.Palette

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local Frostreach = {}

Frostreach.HeightRange = { -4, 24 }

local function crag(B, top: CFrame, width: number, length: number, depth: number)
	-- A tapering rock pillar under every platform.
	local layers = 3
	for i = 1, layers do
		local f = 1 - (i - 1) * 0.18
		B:Box(
			top * CFrame.new(0, -(i - 0.5) * depth / layers, 0) * CFrame.Angles(0, (i - 1) * 0.3, 0),
			Vector3.new(width * f, depth / layers, length * f),
			B:Vary(P.Rock, 0.06),
			Enum.Material.Rock,
			{ Name = "Crag" }
		)
	end
end

Frostreach.CourseTheme = {
	Id = "Frostreach",
	Surface = P.Snow,
	SurfaceMaterial = Enum.Material.Snow,
	Trim = P.Wood,
	Wall = P.RockDark,
	WallMaterial = Enum.Material.Rock,
	Accent = P.Accent,
	Signal = P.Signal,
	Beam = P.Wood,
	BeamMaterial = Enum.Material.WoodPlanks,
	Rope = rgb(200, 180, 140),
	Climb = "Mesh",
	BodyDepth = 42,
	Platform = function(B, top, width, length, role)
		local material = if role == "Checkpoint"
				or role == "Start"
				or role == "Finish"
			then Enum.Material.WoodPlanks
			else Enum.Material.Snow
		B:Box(
			top * CFrame.new(0, -1, 0),
			Vector3.new(width, 2, length),
			if material == Enum.Material.WoodPlanks then P.Wood else P.Snow,
			material,
			{ Name = "Ledge" }
		)
		if role ~= "Recovery" and length >= 14 and B:Rand(0, 1) < 0.35 then
			Props.Pine(
				B,
				top
					* CFrame.new(
						(width / 2 - 1.5) * (if B:Rand(0, 1) < 0.5 then -1 else 1),
						0,
						B:Rand(-length / 3, length / 3)
					),
				B:Rand(5, 8),
				true
			)
		end
	end,
	Body = crag,
	WallStyle = function(B, cframe, size)
		return B:Box(cframe, size, P.Ice, Enum.Material.Ice, { Name = "IceWall", Transparency = 0.1 })
	end,
}

Frostreach.RoomTheme = {
	Id = "FrostRoom",
	Surface = P.Wood,
	SurfaceMaterial = Enum.Material.WoodPlanks,
	Trim = P.Wood,
	Wall = rgb(150, 120, 95),
	WallMaterial = Enum.Material.WoodPlanks,
	Accent = P.Accent,
	Signal = P.Signal,
	Beam = P.Wood,
	BeamMaterial = Enum.Material.WoodPlanks,
	Rope = rgb(200, 180, 140),
	Climb = "Ladder",
	BodyDepth = 0,
}

local function lodge(B, base: CFrame, width: number, depth: number, height: number): Vector3
	B:Box(
		base * CFrame.new(0, height / 2, 0),
		Vector3.new(width, height, depth),
		P.Wood,
		Enum.Material.WoodPlanks,
		{ Name = "Lodge" }
	)
	-- Steep roof from two wedges, capped with snow.
	for _, side in { -1, 1 } do
		B:Wedge(
			base * CFrame.new(side * width / 4, height + 2.5, 0) * CFrame.Angles(0, math.rad(90 * side), 0),
			Vector3.new(depth + 1, 5, width / 2 + 0.5),
			P.Fabric,
			Enum.Material.Slate
		)
		B:Wedge(
			base * CFrame.new(side * width / 4, height + 2.7, 0) * CFrame.Angles(0, math.rad(90 * side), 0),
			Vector3.new(depth + 1.2, 4.8, width / 2),
			P.Snow,
			Enum.Material.Snow,
			{ Decor = true }
		)
	end
	local window = B:Detail(
		base * CFrame.new(0, height / 2, -depth / 2 - 0.05),
		Vector3.new(3, 2.4, 0.1),
		P.Lamp,
		Enum.Material.Neon
	)
	B:Light(window, P.Lamp, 16, 0.8, "Surface", Enum.NormalId.Front)
	local chimney = Props.Chimney(B, base * CFrame.new(width / 3, height + 1, depth / 4), P.RockDark, 4)
	return chimney
end

function Frostreach.Plaza(B, ctx)
	local origin = ctx.Origin
	local R = DistrictBuilder.PlazaRadius
	B:Cylinder(
		origin * CFrame.new(0, -1, 0) * CFrame.Angles(0, 0, math.rad(90)),
		2,
		R * 2,
		rgb(150, 150, 160),
		Enum.Material.Slate,
		{ Name = "HearthSquare" }
	)
	crag(B, origin * CFrame.new(0, -2, 0), R * 2 - 6, R * 2 - 6, 70)
	-- The hearth: a big fire everyone gathers around.
	local hearth = B:Box(
		origin * CFrame.new(0, 0.6, 0),
		Vector3.new(6, 1.2, 6),
		P.RockDark,
		Enum.Material.Cobblestone,
		{ Name = "Hearth" }
	)
	local flame = Instance.new("Attachment")
	flame.Position = Vector3.new(0, 0.8, 0)
	flame.Parent = hearth
	B:Emitter(flame, "Fire", rgb(255, 170, 80))
	B:Light(hearth, rgb(255, 150, 70), 40, 2)
	for i = 0, 5 do
		Props.Bench(
			B,
			origin * CFrame.Angles(0, i * math.pi / 3, 0) * CFrame.new(0, 0, -9) * CFrame.Angles(0, math.rad(180), 0),
			P.Wood
		)
	end
	-- Lodges around the square (clear of the gate, boards and stall), prayer flags between them.
	local side = ctx.HubDir:Cross(Vector3.yAxis)
	local hubAngle = math.atan2(ctx.HubDir.Z, ctx.HubDir.X)
	local previous: Vector3? = nil
	for _, offset in { 1.2, 2.0, -2.0, -1.2 } do
		local p = ctx.Origin.Position + DistrictBuilder.Dir(hubAngle + offset) * (R - 10)
		local lodgeCF = CFrame.lookAt(p, ctx.Origin.Position)
		lodge(B, lodgeCF, 12, 9, 7)
		local flagPoint = p + Vector3.new(0, 10, 0)
		if previous then
			Props.StringLights(B, previous, flagPoint, P.Fabric)
		end
		previous = flagPoint
	end
	DistrictBuilder.NPCSpot(
		ctx,
		"fro_sigrun",
		CFrame.lookAt(
			ctx.Origin.Position + ctx.HubDir * 12 + Vector3.new(0, 3, 0),
			ctx.Origin.Position + Vector3.new(0, 3, 0)
		)
	)
	DistrictBuilder.NPCSpot(
		ctx,
		"fro_kesh",
		CFrame.lookAt(
			ctx.Origin.Position + side * 20 + Vector3.new(0, 3, 0),
			ctx.Origin.Position + Vector3.new(0, 3, 0)
		)
	)
	DistrictBuilder.QuestPoint(
		ctx,
		"fro_supplies",
		ctx.Origin.Position + side * 16 + ctx.HubDir * 4 + Vector3.new(0, 2, 0)
	)
	Props.Crate(B, CFrame.new(ctx.Origin.Position + side * 16 + ctx.HubDir * 7), 2.4, rgb(150, 110, 70))
	-- Outfitter's sled (district shop).
	local sled = CFrame.lookAt(ctx.Origin.Position - ctx.HubDir * 26 - side * 16, ctx.Origin.Position)
	B:Box(sled * CFrame.new(0, 1.2, 0), Vector3.new(8, 2.4, 4), P.Wood, Enum.Material.WoodPlanks, { Name = "Sled" })
	local tarp = B:Box(sled * CFrame.new(0, 3, 0), Vector3.new(7, 1.2, 3.6), P.Fabric, Enum.Material.Fabric)
	B:Prompt(
		tarp,
		"Browse",
		"Mountain Outfitter",
		{ Name = "ShopPrompt", Distance = 12, Attrs = { Board = "Shop", District = "Frostreach" } }
	)
end

function Frostreach.Building(B, ctx, top: CFrame, size: Vector3)
	local w, d = size.X, size.Z
	crag(B, top * CFrame.new(0, -2, 0), w, d, 70)
	B:Box(top * CFrame.new(0, -1, 0), Vector3.new(w, 2, d), P.Snow, Enum.Material.Snow, { Name = "SnowCap" })
	local spots = { Roof = (top * CFrame.new(-w / 4, 0.2, -d / 4)).Position, High = {}, Nooks = {} }
	if B:Rand(0, 1) < 0.5 then
		local chimney = lodge(B, top * CFrame.new(w / 5, 0, d / 5), math.min(w - 6, 12), math.min(d - 6, 9), 6)
		table.insert(spots.High, chimney)
		table.insert(spots.Nooks, (top * CFrame.new(w / 5 + math.min(w - 6, 12) / 2 + 1.2, 0.2, d / 5)).Position)
	else
		for _ = 1, 3 do
			Props.Pine(B, top * CFrame.new(B:Rand(-w / 3, w / 3), 0, B:Rand(-d / 3, d / 3)), B:Rand(6, 11), true)
		end
		local cairnTop = (top * CFrame.new(0, 0, 0)).Position
		for i = 0, 3 do
			Props.Rock(
				B,
				cairnTop + Vector3.new(0, 0.8 + i * 1.3, 0),
				Vector3.new(3 - i * 0.6, 1.4, 3 - i * 0.6),
				P.RockDark
			)
		end
		table.insert(spots.High, cairnTop + Vector3.new(0, 5.6, 0))
		table.insert(spots.Nooks, (top * CFrame.new(w / 2 - 1.5, 0.2, d / 2 - 1.5)).Position)
	end
	-- Icicles hang under the edges.
	for i = -1, 1 do
		local icicle = B:Detail(
			top * CFrame.new(i * w / 3, -3, -d / 2 + 0.4) * CFrame.Angles(math.rad(180), 0, 0),
			Vector3.new(0.6, 3, 0.6),
			P.Ice,
			Enum.Material.Ice
		)
		icicle.CanCollide = false
	end
	return spots
end

function Frostreach.Connector(B, ctx, a: Vector3, b: Vector3)
	-- Rope bridges: a plank walkway (balance) with rope rails that sway in the wind.
	local plank = B:Beam(
		a - Vector3.new(0, 0.5, 0),
		b - Vector3.new(0, 0.5, 0),
		1.6,
		1,
		P.Wood,
		Enum.Material.WoodPlanks,
		{ Name = "RopeBridge", Tag = Tags.Balance }
	)
	B:Icon(plank, "=", rgb(255, 255, 255), Vector3.new(0, 2, 0))
	local across = (b - a)
	local side = Vector3.new(-across.Z, 0, across.X).Unit * 1.4
	for _, s in { -1, 1 } do
		B:Rod(
			a + side * s + Vector3.new(0, 2.4, 0),
			b + side * s + Vector3.new(0, 2.4, 0),
			0.15,
			rgb(200, 180, 140),
			Enum.Material.Fabric,
			{ Decor = true, CanCollide = false }
		)
		for _, p in { a, b } do
			B:Box(
				CFrame.new(p + side * s + Vector3.new(0, 1.5, 0)),
				Vector3.new(0.4, 3, 0.4),
				P.Wood,
				Enum.Material.Wood
			)
		end
	end
end

function Frostreach.Landmarks(B, ctx)
	-- Hollowpeak Mast: a rock spire with a lattice mast and the great lamp.
	local peakPos = DistrictBuilder.FindClear(ctx, 560, 30)
	local peak = CFrame.lookAt(peakPos, ctx.Origin.Position)
	for i = 0, 4 do
		local f = 1 - i * 0.16
		B:Box(
			peak * CFrame.new(0, -40 + i * 16, 0) * CFrame.Angles(0, i * 0.4, 0),
			Vector3.new(44 * f, 16, 44 * f),
			P.RockDark,
			Enum.Material.Rock,
			{ Name = "Hollowpeak" }
		)
	end
	local summit = peak * CFrame.new(0, 40, 0)
	B:Box(summit * CFrame.new(0, -1, 0), Vector3.new(18, 2, 18), P.Snow, Enum.Material.Snow, { Name = "Summit" })
	-- The climb: ledges spiralling up the peak.
	for i = 0, 9 do
		local ledge = peak * CFrame.Angles(0, i * 1.1, 0) * CFrame.new(0, -30 + i * 7, -(22 - i * 1.4))
		B:Box(ledge, Vector3.new(9, 1, 4), P.Wood, Enum.Material.WoodPlanks, { Name = "PeakLedge" })
	end
	-- Lattice mast and lamp.
	for _, offset in { Vector3.new(-2, 0, -2), Vector3.new(2, 0, -2), Vector3.new(-2, 0, 2), Vector3.new(2, 0, 2) } do
		B:Box(
			summit * CFrame.new(offset) * CFrame.new(0, 14, 0),
			Vector3.new(0.6, 28, 0.6),
			rgb(150, 150, 160),
			Enum.Material.Metal
		)
	end
	Props.Ladder(B, summit * CFrame.new(0, 0, 2.4), 28, 2.4)
	B:Box(
		summit * CFrame.new(0, 28.5, 0),
		Vector3.new(7, 1, 7),
		P.Wood,
		Enum.Material.WoodPlanks,
		{ Name = "LampDeck" }
	)
	local lamp = B:Ball(
		summit.Position + Vector3.new(0, 31, 0),
		3.4,
		P.Lamp,
		Enum.Material.Neon,
		{ Name = "MastLamp", CanCollide = false }
	)
	B:Light(lamp, P.Lamp, 60, 2)
	DistrictBuilder.QuestPoint(ctx, "fro_beacon", (summit * CFrame.new(1.5, 30.5, 1.5)).Position)
	DistrictBuilder.NPCSpot(
		ctx,
		"fro_bram",
		CFrame.lookAt(summit.Position + Vector3.new(6, 3, 0), ctx.Origin.Position + Vector3.new(0, 43, 0))
	)
	DistrictBuilder.Landmark(ctx, "mast", "Hollowpeak Mast", summit * CFrame.new(0, 30, 0), Vector3.new(8, 6, 8))
	B:FarBox(peak * CFrame.new(0, 0, 0), Vector3.new(40, 80, 40), P.RockDark, Enum.Material.Rock)
	B:FarBox(summit * CFrame.new(0, 14, 0), Vector3.new(4, 28, 4), rgb(150, 150, 160))
	B:FarBox(CFrame.new(summit.Position + Vector3.new(0, 31, 0)), Vector3.new(3, 3, 3), P.Lamp, Enum.Material.Neon)

	-- The Frozen Falls: a cascade of ice down a cliff.
	local fallsPos = DistrictBuilder.FindClear(ctx, 520, 30)
	local falls = CFrame.lookAt(fallsPos, ctx.Origin.Position)
	B:Box(falls * CFrame.new(0, -20, 8), Vector3.new(44, 90, 16), P.RockDark, Enum.Material.Rock, { Name = "IceCliff" })
	B:Box(falls * CFrame.new(0, 25.5, 4), Vector3.new(44, 1, 24), P.Snow, Enum.Material.Snow)
	for i = 0, 5 do
		local column = B:Box(
			falls * CFrame.new(-10 + i * 4, -10, -0.5),
			Vector3.new(3.4, 70 - i * 6, 2),
			P.Ice,
			Enum.Material.Glacier,
			{ Name = "Icefall" }
		)
		column.Transparency = 0.15
	end
	B:Box(falls * CFrame.new(-16, 0, -1.4), Vector3.new(4, 50, 0.6), rgb(150, 155, 160), Enum.Material.DiamondPlate, {
		Name = "IceNet",
		Tag = Tags.Climbable,
		Attrs = { Kind = "Mesh" },
	})
	DistrictBuilder.Landmark(ctx, "falls", "The Frozen Falls", falls * CFrame.new(0, 29, 4), Vector3.new(44, 8, 24))
	B:FarBox(falls * CFrame.new(0, -20, 8), Vector3.new(44, 90, 16), P.Ice, Enum.Material.Glacier)
end

function Frostreach.QuestPoints(B, ctx)
	for _, id in { "fro_house_a", "fro_house_b", "fro_house_c" } do
		local roof = DistrictBuilder.TakeRoof(ctx)
		lodge(B, CFrame.new(roof + Vector3.new(4, -0.2, 4)), 8, 7, 5)
		DistrictBuilder.QuestPoint(ctx, id, roof + Vector3.new(0, 1.5, 0))
	end
	for i = 1, 5 do
		local spot = DistrictBuilder.TakeHigh(ctx)
		local post = B:Box(
			CFrame.new(spot + Vector3.new(0, 1.5, 0)),
			Vector3.new(0.4, 3, 0.4),
			P.Wood,
			Enum.Material.Wood,
			{ Name = "LanternPost" }
		)
		B:Detail(post.CFrame * CFrame.new(0, 1.8, 0), Vector3.new(0.9, 0.9, 0.9), rgb(80, 70, 60), Enum.Material.Glass)
		DistrictBuilder.QuestPoint(ctx, "fro_lantern_" .. i, spot + Vector3.new(0, 1, 0))
	end
end

function Frostreach.Skyline(B, ctx)
	for i = 0, 11 do
		local angle = i * math.pi / 6 + 0.1
		local p = ctx.Origin.Position + DistrictBuilder.Dir(angle) * (700 + B:Rand(-60, 60))
		local h = B:Rand(120, 260)
		B:FarBox(
			CFrame.new(p + Vector3.new(0, -140 + h / 2, 0)) * CFrame.Angles(0, B:Rand(0, 1), 0),
			Vector3.new(h * 0.6, h, h * 0.6),
			P.Rock,
			Enum.Material.Rock
		)
		B:FarBox(
			CFrame.new(p + Vector3.new(0, -140 + h, 0)) * CFrame.Angles(0, B:Rand(0, 1), 0),
			Vector3.new(h * 0.3, h * 0.15, h * 0.3),
			P.Snow,
			Enum.Material.Snow
		)
	end
	B:Detail(
		ctx.Origin * CFrame.new(0, -110, 0),
		Vector3.new(1400, 1, 1400),
		rgb(230, 238, 248),
		Enum.Material.Snow,
		{ CanCollide = false }
	)
	B:Volume(
		ctx.Origin * CFrame.new(0, -ctx.District.KillDepth, 0),
		Vector3.new(1600, 10, 1600),
		Tags.KillZone,
		{ District = "Frostreach" }
	)
end

return Frostreach

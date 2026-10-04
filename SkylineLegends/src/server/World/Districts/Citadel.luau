-- Aether Citadel: floating marble architecture held aloft by the Aether Keel.
-- Every platform floats on a rock keel of its own; golden rings orbit
-- overhead, currents rise between the terraces, and gravity bends near the Keel.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Districts = require(ReplicatedStorage.Shared.Config.Districts)
local Tags = require(ReplicatedStorage.Shared.Tags)

local DistrictBuilder = require(script.Parent.Parent.DistrictBuilder)
local Props = require(script.Parent.Parent.Props)

local P = Districts.ById.Citadel.Palette

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local Citadel = {}

Citadel.HeightRange = { -10, 22 }

local function keel(B, top: CFrame, width: number, length: number, depth: number)
	-- An inverted rock spire under each floating slab, with a glowing crystal tip.
	local d = math.min(depth, 6 + (width + length) * 0.35)
	for i = 1, 3 do
		local f = 1 - (i - 1) * 0.3
		B:Box(
			top * CFrame.new(0, -(i - 0.5) * d / 3, 0) * CFrame.Angles(0, i * 0.5, 0),
			Vector3.new(width * f * 0.9, d / 3, length * f * 0.9),
			B:Vary(P.Stone, 0.06),
			Enum.Material.Rock,
			{ Name = "Keel", Decor = i > 1 }
		)
	end
	if width * length > 150 then
		Props.Crystal(B, (top * CFrame.new(0, -d - 2, 0)).Position, 4, P.Aether)
	end
end

Citadel.CourseTheme = {
	Id = "Citadel",
	Surface = P.Marble,
	SurfaceMaterial = Enum.Material.Marble,
	Trim = P.Gold,
	Wall = P.MarbleDark,
	WallMaterial = Enum.Material.Marble,
	Accent = P.Accent,
	Signal = P.Signal,
	Beam = P.Gold,
	BeamMaterial = Enum.Material.Metal,
	Rope = P.Gold,
	Climb = "Ladder",
	BodyDepth = 26,
	Floating = true,
	Platform = function(B, top, width, length, role)
		B:Box(
			top * CFrame.new(0, -1, 0),
			Vector3.new(width, 2, length),
			B:Vary(P.Marble, 0.04),
			Enum.Material.Marble,
			{ Name = "Terrace" }
		)
		if role ~= "Recovery" and length >= 10 then
			for _, side in { -1, 1 } do
				B:Detail(
					top * CFrame.new(side * (width / 2 + 0.1), -0.6, 0),
					Vector3.new(0.2, 0.8, length),
					P.Gold,
					Enum.Material.Metal
				)
			end
		end
	end,
	Body = keel,
	AnchorMount = function(B, position)
		local ring = B:Detail(
			CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
			Vector3.new(0.3, 6, 6),
			P.Gold,
			Enum.Material.Metal,
			{ Shape = Enum.PartType.Cylinder }
		)
		ring.CanCollide = false
	end,
}

Citadel.RoomTheme = {
	Id = "CitadelRoom",
	Surface = P.Marble,
	SurfaceMaterial = Enum.Material.Marble,
	Trim = P.Gold,
	Wall = P.MarbleDark,
	WallMaterial = Enum.Material.Marble,
	Accent = P.Accent,
	Signal = P.Signal,
	Beam = P.Gold,
	BeamMaterial = Enum.Material.Metal,
	Rope = P.Gold,
	Climb = "Ladder",
	BodyDepth = 0,
}

local function ring(B, center: CFrame, radius: number, color: Color3, segments: number?)
	local n = segments or 16
	for i = 0, n - 1 do
		local angle = i / n * math.pi * 2
		local piece = B:Detail(
			center * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -radius),
			Vector3.new(2 * math.pi * radius / n + 0.3, 0.8, 1.2),
			color,
			Enum.Material.Metal
		)
		piece.CanCollide = false
	end
end

function Citadel.Plaza(B, ctx)
	local origin = ctx.Origin
	local R = DistrictBuilder.PlazaRadius
	B:Cylinder(
		origin * CFrame.new(0, -1, 0) * CFrame.Angles(0, 0, math.rad(90)),
		2,
		R * 2,
		P.Marble,
		Enum.Material.Marble,
		{ Name = "KeelTerrace" }
	)
	B:Cylinder(
		origin * CFrame.new(0, -0.95, 0) * CFrame.Angles(0, 0, math.rad(90)),
		2,
		R * 2 - 12,
		P.MarbleDark,
		Enum.Material.Marble,
		{ Decor = true }
	)
	Props.FloatingRock(B, origin * CFrame.new(0, -2, 0), R * 1.9, 60, P.Stone)
	-- Golden rings orbit slowly overhead.
	for index, radius in { 30, 38 } do
		local center = origin * CFrame.new(0, 24 + index * 6, 0) * CFrame.Angles(math.rad(12 * index), 0, 0)
		ring(B, center, radius, P.Gold, 20)
	end
	-- Statue plinths for the Warden and the Skywright memorial.
	local side = ctx.HubDir:Cross(Vector3.yAxis)
	local plinth = CFrame.lookAt(ctx.Origin.Position - ctx.HubDir * 22, ctx.Origin.Position)
	B:Box(
		plinth * CFrame.new(0, 1, 0),
		Vector3.new(8, 2, 8),
		P.MarbleDark,
		Enum.Material.Marble,
		{ Name = "WardenPlinth" }
	)
	DistrictBuilder.NPCSpot(ctx, "cit_warden", plinth * CFrame.new(0, 5, 0))
	DistrictBuilder.NPCSpot(
		ctx,
		"cit_ilse",
		CFrame.lookAt(
			ctx.Origin.Position + side * 24 + Vector3.new(0, 3, 0),
			ctx.Origin.Position + Vector3.new(0, 3, 0)
		)
	)
	DistrictBuilder.NPCSpot(
		ctx,
		"cit_echo",
		CFrame.lookAt(
			ctx.Origin.Position - side * 24 + Vector3.new(0, 3, 0),
			ctx.Origin.Position + Vector3.new(0, 3, 0)
		)
	)
	-- Ilse's camp: a tent and her map table.
	local camp = CFrame.lookAt(ctx.Origin.Position + side * 30, ctx.Origin.Position)
	B:Wedge(camp * CFrame.new(-2, 2, 4), Vector3.new(6, 4, 5), rgb(150, 110, 255), Enum.Material.Fabric)
	B:Wedge(
		camp * CFrame.new(2, 2, 4) * CFrame.Angles(0, math.rad(180), 0),
		Vector3.new(6, 4, 5),
		rgb(150, 110, 255),
		Enum.Material.Fabric
	)
	B:Box(camp * CFrame.new(0, 1.4, -2), Vector3.new(5, 0.3, 3), P.Gold, Enum.Material.Wood)
	for i = 0, 7 do
		Props.Column(
			B,
			origin * CFrame.Angles(0, i * math.pi / 4 + 0.39, 0) * CFrame.new(0, 0, -(R - 4)),
			14,
			P.Marble,
			i % 3 == 0
		)
	end
	local crystal = B:Ball(
		ctx.Origin.Position + Vector3.new(0, 4, 0),
		3,
		P.Aether2,
		Enum.Material.Neon,
		{ Name = "TerraceCrystal", CanCollide = false }
	)
	B:Light(crystal, P.Aether2, 30, 1.5)
	-- Skywright reliquary (district shop).
	local reliquary = CFrame.lookAt(ctx.Origin.Position - ctx.HubDir * 30 - side * 16, ctx.Origin.Position)
	B:Box(
		reliquary * CFrame.new(0, 1.5, 0),
		Vector3.new(8, 3, 3),
		P.MarbleDark,
		Enum.Material.Marble,
		{ Name = "Reliquary" }
	)
	local glow = B:Box(
		reliquary * CFrame.new(0, 4, 0),
		Vector3.new(2, 2, 2),
		P.Aether,
		Enum.Material.Neon,
		{ CanCollide = false }
	)
	B:Prompt(
		glow,
		"Browse",
		"Skywright Reliquary",
		{ Name = "ShopPrompt", Distance = 12, Attrs = { Board = "Shop", District = "Citadel" } }
	)
end

function Citadel.Building(B, ctx, top: CFrame, size: Vector3)
	local w, d = size.X, size.Z
	B:Box(
		top * CFrame.new(0, -1, 0),
		Vector3.new(w, 2, d),
		B:Vary(P.Marble, 0.05),
		Enum.Material.Marble,
		{ Name = "Island" }
	)
	Props.FloatingRock(B, top * CFrame.new(0, -2, 0), math.max(w, d) * 0.95, 30, P.Stone)
	local spots = { Roof = (top * CFrame.new(0, 0.2, 0)).Position, High = {}, Nooks = {} }
	if B:Rand(0, 1) < 0.5 then
		-- A colonnade with an arch: the arch top is a perch, its shadow a nook.
		Props.Arch(B, top * CFrame.new(0, 0, d / 4), math.min(w - 6, 12), 10, P.MarbleDark, Enum.Material.Marble)
		table.insert(spots.High, (top * CFrame.new(0, 11.7, d / 4)).Position)
		table.insert(spots.Nooks, (top * CFrame.new(-w / 2 + 2, 0.2, -d / 2 + 2)).Position)
		for i = -1, 1, 2 do
			Props.Column(B, top * CFrame.new(i * (w / 2 - 2), 0, -d / 4), 9, P.Marble, true)
		end
	else
		-- A reading pavilion of the Skywright Archive.
		local roofTop = (top * CFrame.new(0, 9, 0)).Position
		for i = 0, 3 do
			Props.Column(
				B,
				top * CFrame.new((if i % 2 == 0 then -1 else 1) * 4, 0, (if i < 2 then -1 else 1) * 4),
				8,
				P.Marble,
				false
			)
		end
		B:Box(top * CFrame.new(0, 9, 0), Vector3.new(12, 1, 12), P.Gold, Enum.Material.Metal, { Name = "PavilionRoof" })
		Props.Crystal(B, (top * CFrame.new(0, 0.2, 0)).Position, 3, P.Aether2)
		table.insert(spots.High, roofTop + Vector3.new(0, 0.7, 0))
		table.insert(spots.Nooks, (top * CFrame.new(w / 2 - 1.5, 0.2, d / 2 - 1.5)).Position)
	end
	return spots
end

function Citadel.Connector(B, ctx, a: Vector3, b: Vector3)
	-- Aether currents carry you up; golden chains bridge level gaps.
	if b.Y - a.Y > 4 then
		local column = a + (b - a) * 0.5
		local height = b.Y - a.Y + 16
		local zone = B:Box(
			CFrame.new(Vector3.new(column.X, a.Y + height / 2, column.Z)),
			Vector3.new(8, height, 8),
			rgb(255, 255, 255),
			Enum.Material.SmoothPlastic,
			{
				Name = "Current",
				Transparency = 1,
				CanCollide = false,
				CanQuery = false,
				Tag = Tags.GravityZone,
				Attrs = { Scale = 1, Lift = 260, MaxRise = 30 },
			}
		)
		local attachment = Instance.new("Attachment")
		attachment.Position = Vector3.new(0, -height / 2, 0)
		attachment.Parent = zone
		B:Emitter(attachment, "Updraft", P.Aether2)
		B:Icon(zone, "⇧", P.Signal, Vector3.new(0, -height / 2 + 2, 0))
	else
		local chain = B:Beam(
			a - Vector3.new(0, 0.5, 0),
			b - Vector3.new(0, 0.5, 0),
			1.2,
			1,
			P.Gold,
			Enum.Material.Metal,
			{ Name = "GoldChain", Tag = Tags.Balance }
		)
		B:Icon(chain, "=", rgb(255, 255, 255), Vector3.new(0, 2, 0))
	end
end

function Citadel.Landmarks(B, ctx)
	-- The Aether Keel: a colossal crystal hanging in rings, with a chamber beneath.
	local keelPos = DistrictBuilder.FindClear(ctx, 560, 40) + Vector3.new(0, 30, 0)
	local keelCF = CFrame.lookAt(keelPos, ctx.Origin.Position + Vector3.new(0, 30, 0))
	B:Box(
		keelCF * CFrame.new(0, -1, 0),
		Vector3.new(34, 2, 34),
		P.Marble,
		Enum.Material.Marble,
		{ Name = "KeelPlatform" }
	)
	Props.FloatingRock(B, keelCF * CFrame.new(0, -2, 0), 34, 40, P.Stone)
	local crystal = B:Box(
		keelCF * CFrame.new(0, 26, 0) * CFrame.Angles(0, math.rad(45), 0),
		Vector3.new(10, 44, 10),
		P.Aether,
		Enum.Material.Neon,
		{ Name = "AetherKeel", CanCollide = false }
	)
	B:Light(crystal, P.Aether, 80, 3)
	for index, radius in { 12, 16, 20 } do
		ring(
			B,
			keelCF * CFrame.new(0, 20 + index * 6, 0) * CFrame.Angles(math.rad(index * 20), math.rad(index * 30), 0),
			radius,
			P.Gold,
			18
		)
	end
	-- A stair of floating steps up to the relay ring.
	for i = 0, 7 do
		local step = keelCF * CFrame.Angles(0, i * 0.8, 0) * CFrame.new(0, 2 + i * 4.5, -13)
		B:Box(step, Vector3.new(6, 1, 4), P.MarbleDark, Enum.Material.Marble, { Name = "KeelStep" })
	end
	local relayDeck = keelCF * CFrame.new(0, 38, -13)
	B:Box(relayDeck, Vector3.new(10, 1, 6), P.Gold, Enum.Material.Metal, { Name = "RelayDeck" })
	DistrictBuilder.QuestPoint(ctx, "cit_keel_relay", (relayDeck * CFrame.new(0, 2, 0)).Position)
	DistrictBuilder.Landmark(ctx, "keel", "The Aether Keel", keelCF * CFrame.new(0, 4, 0), Vector3.new(34, 8, 34))
	-- The chamber beneath, reached by dropping through the gap at the platform's edge.
	local chamber = keelCF * CFrame.new(0, -28, 0)
	B:Box(
		chamber * CFrame.new(0, -1, 0),
		Vector3.new(16, 2, 16),
		P.MarbleDark,
		Enum.Material.Marble,
		{ Name = "KeelChamber" }
	)
	Props.Ladder(B, chamber * CFrame.new(0, 0, 8.6), 26, 2.6)
	local core =
		B:Ball(chamber.Position + Vector3.new(0, 4, 0), 3, P.Aether2, Enum.Material.Neon, { CanCollide = false })
	B:Light(core, P.Aether2, 20, 1.5)
	DistrictBuilder.Secret(
		ctx,
		"keel",
		"Under the Keel",
		"The Keel's control chamber. Every dial reads STABLE, and has for ten years.",
		chamber * CFrame.new(0, 3, 0),
		Vector3.new(16, 6, 16)
	)
	B:FarBox(keelCF * CFrame.new(0, 26, 0), Vector3.new(10, 44, 10), P.Aether, Enum.Material.Neon)

	-- The Skywright Archive: tiers of floating shelves around a reading dome.
	local archivePos = DistrictBuilder.FindClear(ctx, 520, 34)
	local archive = CFrame.lookAt(archivePos, ctx.Origin.Position)
	for tier = 0, 2 do
		local t = archive * CFrame.new(0, tier * 14, 0)
		local size = 30 - tier * 8
		B:Box(
			t * CFrame.new(0, -1, 0),
			Vector3.new(size, 2, size),
			P.Marble,
			Enum.Material.Marble,
			{ Name = "ArchiveTier" }
		)
		if tier == 0 then
			Props.FloatingRock(B, t * CFrame.new(0, -2, 0), size, 30, P.Stone)
		end
		for i = 0, 3 do
			Props.Column(
				B,
				t * CFrame.Angles(0, i * math.pi / 2 + math.pi / 4, 0) * CFrame.new(0, 0, -(size / 2 - 2)),
				12,
				P.MarbleDark,
				false
			)
		end
		Props.Ladder(
			B,
			t * CFrame.new(size / 2 - 3, 0, -(size / 2) - 0.1) * CFrame.Angles(0, math.rad(180), 0),
			14,
			2.4
		)
	end
	DistrictBuilder.Landmark(
		ctx,
		"archive",
		"Skywright Archive",
		archive * CFrame.new(0, 32, 0),
		Vector3.new(14, 6, 14)
	)
	B:FarBox(archive * CFrame.new(0, 14, 0), Vector3.new(30, 30, 30), P.Marble)
end

function Citadel.QuestPoints(B, ctx)
	for i = 1, 5 do
		local spot = DistrictBuilder.TakeHigh(ctx)
		local scroll = B:Detail(
			CFrame.new(spot + Vector3.new(0, 0.6, 0)),
			Vector3.new(1.4, 0.3, 0.3),
			rgb(245, 235, 210),
			Enum.Material.SmoothPlastic,
			{ Shape = Enum.PartType.Cylinder }
		)
		scroll.CanCollide = false
		DistrictBuilder.QuestPoint(ctx, "cit_map_" .. i, spot + Vector3.new(0, 1, 0))
	end
	for i = 1, 4 do
		local spot = DistrictBuilder.TakeNook(ctx)
		Props.Crystal(B, spot, 2.2, P.Aether)
		DistrictBuilder.QuestPoint(ctx, "cit_echo_" .. i, spot + Vector3.new(0, 1, 0))
	end
end

function Citadel.Skyline(B, ctx)
	-- Distant floating islands and drifting crystals.
	for i = 0, 15 do
		local angle = i * math.pi / 8 + 0.15
		local p = ctx.Origin.Position
			+ DistrictBuilder.Dir(angle) * (640 + B:Rand(-80, 80))
			+ Vector3.new(0, B:Rand(-60, 80), 0)
		local size = B:Rand(30, 70)
		B:FarBox(CFrame.new(p), Vector3.new(size, 4, size), P.Marble)
		B:FarBox(
			CFrame.new(p - Vector3.new(0, size * 0.3, 0)) * CFrame.Angles(0, 0.6, 0),
			Vector3.new(size * 0.6, size * 0.6, size * 0.6),
			P.Stone,
			Enum.Material.Rock
		)
	end
	for _ = 1, 20 do
		local p = ctx.Origin.Position
			+ DistrictBuilder.Dir(B:Rand(0, math.pi * 2)) * B:Rand(140, 560)
			+ Vector3.new(0, B:Rand(-60, 60), 0)
		Props.Crystal(B, p, B:Rand(2, 6), B:Pick({ P.Aether, P.Aether2, P.Glow }))
	end
	-- A sea of cloud far below.
	B:Detail(
		ctx.Origin * CFrame.new(0, -150, 0),
		Vector3.new(1600, 2, 1600),
		rgb(240, 225, 245),
		Enum.Material.Snow,
		{ CanCollide = false, Transparency = 0.2 }
	)
	B:Volume(
		ctx.Origin * CFrame.new(0, -ctx.District.KillDepth, 0),
		Vector3.new(1600, 10, 1600),
		Tags.KillZone,
		{ District = "Citadel" }
	)
end

return Citadel

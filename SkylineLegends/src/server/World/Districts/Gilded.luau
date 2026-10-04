-- Gilded Exchange: the neon financial heights. Glass towers with lit window
-- bands, rooftop helipads and antennas, holographic adverts, maintenance rigs,
-- security lasers, and the Exchange Spire crowned with its ticker ring.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Districts = require(ReplicatedStorage.Shared.Config.Districts)
local Tags = require(ReplicatedStorage.Shared.Tags)

local DistrictBuilder = require(script.Parent.Parent.DistrictBuilder)
local Props = require(script.Parent.Parent.Props)

local P = Districts.ById.Gilded.Palette

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local NEONS = { P.Neon, P.Neon2, P.Gold, rgb(150, 255, 120) }
local ADS = {
	"BUY HIGH",
	"MERIDIAN EXCHANGE",
	"SKYWAY BONDS ▲",
	"TRADE NOW",
	"NIGHT MARKET",
	"GOLD +3.2%",
	"FUTURES",
	"LUMEN SYSTEMS",
}

local Gilded = {}

-- Towers here are taller and more varied than elsewhere.
Gilded.HeightRange = { -6, 28 }

local function tower(B, top: CFrame, width: number, length: number, depth: number)
	B:Box(
		top * CFrame.new(0, -depth / 2, 0),
		Vector3.new(width, depth, length),
		B:Vary(P.GlassDark, 0.05),
		Enum.Material.Glass,
		{ Name = "Tower", Reflectance = 0.15 }
	)
	if length >= 12 then
		local accent = B:Pick(NEONS)
		for _, side in { -1, 1 } do
			B:Detail(
				top * CFrame.new(side * (width / 2 + 0.05), -3, 0),
				Vector3.new(0.1, 0.4, length),
				accent,
				Enum.Material.Neon
			)
			B:Detail(
				top * CFrame.new(side * (width / 2 + 0.05), -10, 0),
				Vector3.new(0.1, 3, length * 0.85),
				if B:Rand(0, 1) < 0.6 then rgb(255, 230, 190) else rgb(40, 60, 90),
				Enum.Material.Neon
			)
		end
	end
end

Gilded.CourseTheme = {
	Id = "Gilded",
	Surface = P.Night,
	SurfaceMaterial = Enum.Material.Marble,
	Trim = P.Gold,
	Wall = P.Glass,
	WallMaterial = Enum.Material.Glass,
	Accent = P.Accent,
	Signal = P.Signal,
	Beam = P.Steel,
	BeamMaterial = Enum.Material.Metal,
	Rope = rgb(80, 80, 90),
	Climb = "Mesh",
	BodyDepth = 60,
	Platform = function(B, top, width, length, role)
		B:Box(
			top * CFrame.new(0, -1, 0),
			Vector3.new(width, 2, length),
			if role == "Checkpoint" then rgb(50, 52, 70) else B:Vary(P.Night, 0.05),
			Enum.Material.Marble,
			{ Name = "Roof" }
		)
		if role ~= "Recovery" and length >= 10 then
			B:Detail(
				top * CFrame.new(-width / 2 + 0.2, 0.03, 0),
				Vector3.new(0.3, 0.06, length),
				P.Gold,
				Enum.Material.Neon
			)
		end
	end,
	Body = tower,
	WallStyle = function(B, cframe, size)
		local wall = B:Box(cframe, size, P.Glass, Enum.Material.Glass, { Name = "GlassWall", Reflectance = 0.25 })
		return wall
	end,
	AnchorMount = function(B, position)
		-- Anchors hang from hovering maintenance drones.
		B:Detail(CFrame.new(position + Vector3.new(0, 3, 0)), Vector3.new(4, 1, 4), P.Steel, Enum.Material.Metal)
		local light = B:Detail(
			CFrame.new(position + Vector3.new(0, 2.4, 0)),
			Vector3.new(0.6, 0.3, 0.6),
			P.Neon2,
			Enum.Material.Neon
		)
		B:Light(light, P.Neon2, 10, 0.6)
	end,
}

Gilded.RoomTheme = {
	Id = "GildedRoom",
	Surface = P.Night,
	SurfaceMaterial = Enum.Material.Marble,
	Trim = P.Gold,
	Wall = rgb(30, 32, 46),
	WallMaterial = Enum.Material.Metal,
	Accent = P.Accent,
	Signal = P.Signal,
	Beam = P.Steel,
	BeamMaterial = Enum.Material.Metal,
	Rope = rgb(80, 80, 90),
	Climb = "Mesh",
	BodyDepth = 0,
}

function Gilded.Plaza(B, ctx)
	local origin = ctx.Origin
	local R = DistrictBuilder.PlazaRadius
	B:Box(
		origin * CFrame.new(0, -1, 0),
		Vector3.new(R * 2, 2, R * 2),
		rgb(40, 42, 58),
		Enum.Material.Marble,
		{ Name = "ExchangePlaza" }
	)
	tower(B, origin * CFrame.new(0, -2, 0), R * 2 - 4, R * 2 - 4, 120)
	for i = 0, 3 do
		B:Detail(
			origin * CFrame.Angles(0, i * math.pi / 2, 0) * CFrame.new(0, 0.04, -R + 1),
			Vector3.new(R * 2 - 2, 0.08, 0.6),
			P.Gold,
			Enum.Material.Neon
		)
	end
	-- The holographic ticker: a ring of scrolling prices over the plaza.
	for i = 0, 7 do
		local angle = i * math.pi / 4
		local panel = B:Detail(
			origin * CFrame.Angles(0, angle, 0) * CFrame.new(0, 18, -16),
			Vector3.new(12.5, 3, 0.2),
			rgb(20, 24, 40),
			Enum.Material.Glass
		)
		B:Text(
			panel,
			Enum.NormalId.Back,
			ADS[i + 1] .. "  ▲" .. (i * 3 + 1) .. "." .. (i * 7 % 10),
			{ Color = NEONS[(i % #NEONS) + 1] }
		)
	end
	Props.Hologram(B, origin * CFrame.new(0, 0, 0), 6, P.Neon2)
	for i = 0, 5 do
		local p = origin * CFrame.Angles(0, i * math.pi / 3 + 0.5, 0)
		Props.Lamp(B, p * CFrame.new(0, 0, -(R - 5)), B:Pick(NEONS), 10)
		if i % 2 == 0 then
			Props.Bench(B, p * CFrame.new(0, 0, -24), rgb(60, 62, 80))
		end
	end
	local side = ctx.HubDir:Cross(Vector3.yAxis)
	DistrictBuilder.NPCSpot(
		ctx,
		"gil_vex",
		CFrame.lookAt(
			ctx.Origin.Position + side * 26 + Vector3.new(0, 3, 0),
			ctx.Origin.Position + Vector3.new(0, 3, 0)
		)
	)
	DistrictBuilder.NPCSpot(
		ctx,
		"gil_pria",
		CFrame.lookAt(
			ctx.Origin.Position - side * 24 - ctx.HubDir * 6 + Vector3.new(0, 3, 0),
			ctx.Origin.Position + Vector3.new(0, 3, 0)
		)
	)
	DistrictBuilder.NPCSpot(
		ctx,
		"gil_lumen",
		CFrame.lookAt(
			ctx.Origin.Position - ctx.HubDir * 26 + Vector3.new(0, 3, 0),
			ctx.Origin.Position + Vector3.new(0, 3, 0)
		)
	)
	-- Boutique kiosk (district shop).
	local kiosk = CFrame.lookAt(ctx.Origin.Position - ctx.HubDir * 30 + side * 18, ctx.Origin.Position)
	B:Box(
		kiosk * CFrame.new(0, 1.5, 0),
		Vector3.new(8, 3, 3),
		rgb(30, 32, 46),
		Enum.Material.Marble,
		{ Name = "Boutique" }
	)
	local sign = B:Box(kiosk * CFrame.new(0, 7, 0.5), Vector3.new(9, 1.5, 0.4), P.Neon, Enum.Material.Neon)
	B:Prompt(
		sign,
		"Browse",
		"Exchange Boutique",
		{ Name = "ShopPrompt", Distance = 12, Attrs = { Board = "Shop", District = "Gilded" } }
	)
end

function Gilded.Building(B, ctx, top: CFrame, size: Vector3)
	local w, d = size.X, size.Z
	local t = top
	tower(B, t, w, d, 140)
	B:Box(t * CFrame.new(0, -1, 0), Vector3.new(w, 2, d), P.Night, Enum.Material.Marble, { Name = "Rooftop" })
	local spots = { Roof = (t * CFrame.new(0, 0.2, 0)).Position, High = {}, Nooks = {} }
	local roll = B:Rand(0, 1)
	if roll < 0.35 then
		-- Helipad.
		B:Cylinder(
			t * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)),
			0.2,
			math.min(w, d) - 4,
			rgb(60, 62, 76),
			Enum.Material.Concrete,
			{ Decor = true }
		)
		local h = B:Detail(t * CFrame.new(0, 0.25, 0), Vector3.new(4, 0.1, 1), P.Gold, Enum.Material.Neon)
		h.CanCollide = false
		local antenna = Props.Antenna(B, t * CFrame.new(w / 2 - 2, 0, d / 2 - 2), B:Rand(12, 22))
		table.insert(spots.High, antenna)
		table.insert(spots.Nooks, (t * CFrame.new(-w / 2 + 1.5, 0.2, d / 2 - 1.5)).Position)
	elseif roll < 0.7 then
		local panel = Props.Billboard(B, t * CFrame.new(0, 0, d / 4), B:Pick(ADS), B:Pick(NEONS), math.min(w - 4, 16))
		table.insert(spots.High, panel.Position + Vector3.new(0, panel.Size.Y / 2 + 0.2, 0))
		table.insert(spots.Nooks, (t * CFrame.new(0, 0.2, d / 4 + 2)).Position)
	else
		Props.Hologram(B, t * CFrame.new(0, 0, 0), B:Rand(3, 6), B:Pick(NEONS))
		Props.ACUnit(B, t * CFrame.new(w / 3, 0, -d / 3))
		table.insert(spots.Nooks, (t * CFrame.new(w / 3 + 2.2, 0.2, -d / 3)).Position)
	end
	-- Window-washer rig hanging off one face: a ledge to catch.
	local rig = t * CFrame.new(0, -9, -d / 2 - 1.4)
	B:Box(rig, Vector3.new(10, 0.5, 2.6), P.Steel, Enum.Material.Metal, { Name = "WasherRig" })
	B:Detail(
		rig * CFrame.new(0, 1.2, -1.2),
		Vector3.new(10, 1.8, 0.2),
		P.Gold,
		Enum.Material.Metal,
		{ CanCollide = true }
	)
	table.insert(spots.Nooks, (rig * CFrame.new(3, 0.5, 0)).Position)
	return spots
end

function Gilded.Connector(B, ctx, a: Vector3, b: Vector3)
	-- Light-bridges (blinking) between towers, or cables to slide down.
	if math.abs(a.Y - b.Y) > 4 then
		local high, low = if a.Y > b.Y then a else b, if a.Y > b.Y then b else a
		local start = high + Vector3.new(0, 7.5, 0)
		local finish = low + Vector3.new(0, 5.5, 0)
		B:Box(CFrame.new(high + Vector3.new(0, 4, 0)), Vector3.new(0.6, 8, 0.6), P.Steel, Enum.Material.Metal)
		B:Box(CFrame.new(low + Vector3.new(0, 3, 0)), Vector3.new(0.6, 6, 0.6), P.Steel, Enum.Material.Metal)
		local cable = B:Rod(
			start,
			finish,
			0.22,
			rgb(40, 40, 50),
			Enum.Material.Metal,
			{ Name = "Cable", CanCollide = false, Tag = Tags.Zipline, Attrs = { A = start, B = finish } }
		)
		B:Icon(cable, "~", P.Signal, Vector3.new(0, 1.5, 0))
	else
		local bridge =
			B:Beam(a - Vector3.new(0, 0.5, 0), b - Vector3.new(0, 0.5, 0), 3, 1, P.Neon2, Enum.Material.ForceField, {
				Name = "LightBridge",
				Tag = Tags.Timed,
				Attrs = { Kind = "Blink", Period = 6, OnFraction = 0.75, Phase = B:Rand(0, 1), Warn = 1 },
			})
		B:Icon(bridge, "◇", P.Signal, Vector3.new(0, 2, 0))
	end
end

function Gilded.Landmarks(B, ctx)
	-- The Exchange Spire.
	local spirePos = DistrictBuilder.FindClear(ctx, 560, 30)
	local spire = CFrame.lookAt(spirePos, ctx.Origin.Position) * CFrame.new(0, 60, 0)
	tower(B, spire, 30, 30, 200)
	B:Box(spire * CFrame.new(0, -1, 0), Vector3.new(30, 2, 30), P.Night, Enum.Material.Marble, { Name = "SpireRoof" })
	for i = 1, 8 do
		local y = -i * 12
		local s = if i % 2 == 0 then 1 else -1
		B:Box(
			spire * CFrame.new(s * 9, y, -16.4),
			Vector3.new(10, 0.6, 2.8),
			P.Steel,
			Enum.Material.Metal,
			{ Name = "WasherRig" }
		)
	end
	Props.Ladder(B, spire * CFrame.new(0, -100, -15.1) * CFrame.Angles(0, math.rad(180), 0), 100, 3)
	local crown = spire * CFrame.new(0, 0, 0)
	for i = 0, 11 do
		local angle = i * math.pi / 6
		B:Detail(
			crown * CFrame.Angles(0, angle, 0) * CFrame.new(0, 14, -13),
			Vector3.new(7, 2.2, 0.2),
			NEONS[(i % #NEONS) + 1],
			Enum.Material.Neon
		)
	end
	local top = Props.Antenna(B, crown, 26)
	DistrictBuilder.QuestPoint(ctx, "gil_transmitter", (crown * CFrame.new(4, 1.5, 4)).Position)
	DistrictBuilder.QuestPoint(ctx, "gil_roof", (crown * CFrame.new(-4, 1.5, -4)).Position)
	DistrictBuilder.Landmark(ctx, "spire", "Exchange Spire", crown * CFrame.new(0, 4, 0), Vector3.new(30, 8, 30))
	B:FarBox(spire * CFrame.new(0, -100, 0), Vector3.new(30, 200, 30), P.GlassDark, Enum.Material.Glass)
	B:FarBox(CFrame.new(top), Vector3.new(1, 1, 1), rgb(255, 40, 40), Enum.Material.Neon)

	-- The Gold Vault: a squat golden strongroom tower.
	local vaultPos = DistrictBuilder.FindClear(ctx, 520, 30) + Vector3.new(0, 8, 0)
	local vault = CFrame.lookAt(vaultPos, ctx.Origin.Position + Vector3.new(0, 8, 0))
	B:Box(
		vault * CFrame.new(0, -60, 0),
		Vector3.new(36, 120, 36),
		P.Gold,
		Enum.Material.Metal,
		{ Name = "GoldVault", Reflectance = 0.2 }
	)
	B:Box(vault * CFrame.new(0, -1, 0), Vector3.new(36, 2, 36), P.Night, Enum.Material.Marble)
	local door = B:Cylinder(
		vault * CFrame.new(0, -10, -18.2) * CFrame.Angles(0, math.rad(90), 0),
		1,
		14,
		rgb(200, 170, 90),
		Enum.Material.Metal
	)
	door.Name = "VaultDoor"
	Props.Ladder(B, vault * CFrame.new(10, -40, -18.1) * CFrame.Angles(0, math.rad(180), 0), 40, 3)
	DistrictBuilder.Landmark(ctx, "vault", "The Gold Vault", vault * CFrame.new(0, 4, 0), Vector3.new(36, 8, 36))
	B:FarBox(vault * CFrame.new(0, -50, 0), Vector3.new(36, 100, 36), P.Gold)
end

function Gilded.QuestPoints(B, ctx)
	for i = 1, 4 do
		local spot = DistrictBuilder.TakeHigh(ctx)
		local terminal = B:Box(
			CFrame.new(spot + Vector3.new(0, 1.2, 0)),
			Vector3.new(1.4, 2.4, 0.8),
			rgb(30, 34, 50),
			Enum.Material.Metal,
			{ Name = "DataTerminal" }
		)
		B:Detail(terminal.CFrame * CFrame.new(0, 0.4, -0.41), Vector3.new(1.1, 1, 0.02), P.Neon2, Enum.Material.Neon)
		DistrictBuilder.QuestPoint(ctx, "gil_terminal_" .. i, spot + Vector3.new(0, 1, 0))
	end
	for i = 1, 4 do
		DistrictBuilder.QuestPoint(ctx, "gil_holo_" .. i, DistrictBuilder.TakeRoof(ctx) + Vector3.new(0, 1.5, 0))
	end
end

function Gilded.Skyline(B, ctx)
	for i = 0, 17 do
		local angle = i * math.pi / 9
		local p = ctx.Origin.Position + DistrictBuilder.Dir(angle) * (650 + B:Rand(-60, 60))
		local h = B:Rand(120, 300)
		B:FarBox(
			CFrame.new(p + Vector3.new(0, -120 + h / 2, 0)),
			Vector3.new(B:Rand(40, 70), h, B:Rand(40, 70)),
			P.GlassDark,
			Enum.Material.Glass
		)
		local band = B:Detail(
			CFrame.new(p + Vector3.new(0, -120 + h, 0)),
			Vector3.new(52, 1.5, 52),
			B:Pick(NEONS),
			Enum.Material.Neon
		)
		band.CanCollide = false
	end
	-- Traffic glow far below.
	for i = 1, 16 do
		local p = ctx.Origin.Position
			+ DistrictBuilder.Dir(B:Rand(0, math.pi * 2)) * B:Rand(160, 520)
			+ Vector3.new(0, -110, 0)
		local glow = B:Detail(
			CFrame.new(p),
			Vector3.new(30, 0.4, 3),
			B:Pick({ rgb(255, 80, 80), rgb(255, 230, 180) }),
			Enum.Material.Neon
		)
		glow.CanCollide = false
	end
	B:Volume(
		ctx.Origin * CFrame.new(0, -ctx.District.KillDepth, 0),
		Vector3.new(1600, 10, 1600),
		Tags.KillZone,
		{ District = "Gilded" }
	)
end

return Gilded

-- Guildhall Commons: the central hub. The Guild's signal tower rises from a
-- ring plaza with a lift gate to every district. Around it: the Training Yard
-- (one station per lesson), a free practice playground, the outfitter, the
-- race board, a crew lounge, the Spire and the Dreamline gate.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Courses = require(ReplicatedStorage.Shared.Config.Courses)
local Districts = require(ReplicatedStorage.Shared.Config.Districts)
local Lessons = require(ReplicatedStorage.Shared.Config.Lessons)
local Lore = require(ReplicatedStorage.Shared.Config.Lore)
local Tags = require(ReplicatedStorage.Shared.Tags)

local CourseBuilder = require(script.Parent.Parent.CourseBuilder)
local DistrictBuilder = require(script.Parent.Parent.DistrictBuilder)
local Kit = require(script.Parent.Parent.Kit)
local Props = require(script.Parent.Parent.Props)

local D = Districts.ById.Hub
local P = D.Palette

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local Hub = {}

local THEME: CourseBuilder.Theme = {
	Id = "Hub",
	Surface = P.Stone,
	SurfaceMaterial = Enum.Material.Limestone,
	Trim = P.Trim,
	Wall = rgb(190, 180, 165),
	WallMaterial = Enum.Material.Limestone,
	Accent = P.Accent,
	Signal = P.Signal,
	Beam = P.Wood,
	BeamMaterial = Enum.Material.WoodPlanks,
	Rope = rgb(210, 190, 140),
	Climb = "Ladder",
	BodyDepth = 30,
	Platform = function(B, top, width, length, role)
		local material = if role == "Checkpoint" or role == "Start" or role == "Finish" then Enum.Material.WoodPlanks else Enum.Material.Limestone
		B:Box(top * CFrame.new(0, -1, 0), Vector3.new(width, 2, length), if material == Enum.Material.WoodPlanks then P.Wood else B:Vary(P.Stone, 0.05), material, { Name = "Platform" })
		if role ~= "Floating" and role ~= "Recovery" then
			for _, side in { -1, 1 } do
				B:Detail(top * CFrame.new(side * (width / 2 - 0.2), 0.04, 0), Vector3.new(0.4, 0.08, length), P.Trim, Enum.Material.Wood)
			end
		end
	end,
	Body = function(B, top, width, length, depth)
		B:Box(top * CFrame.new(0, -depth / 2, 0), Vector3.new(width - 1, depth, length - 1), rgb(170, 160, 145), Enum.Material.Limestone, { Name = "Pillar" })
	end,
}

local function dir(angleDegrees: number): Vector3
	return DistrictBuilder.Dir(math.rad(angleDegrees))
end

-- Lesson stations: each is a small route built from the same segments as courses.
local STATIONS: { [string]: { any } } = {
	l_sprint = { { "Run", 12 }, { "Gap", 0.45 }, { "Gap", 0.5 }, { "Gap", 0.55 }, { "Run", 10 } },
	l_vault = { { "Run", 14 }, { "Vault", 2 }, { "Run", 8 } },
	l_slide = { { "Run", 16 }, { "Slide", 2 }, { "Run", 8 } },
	l_ledge = { { "Run", 8 }, { "Ledge", 8 }, { "Run", 4 }, { "Shimmy", 10 }, { "Run", 6 } },
	l_climb = { { "Run", 8 }, { "Climb", 12, Type = "Ladder" }, { "Run", 8 } },
	l_wallrun = { { "Run", 18 }, { "WallRun", 0.8, Side = "R" }, { "Run", 8 } },
	l_walljump = { { "Run", 8 }, { "Shaft", 14 }, { "Run", 8 } },
	l_balance = { { "Run", 8 }, { "Balance", 26 }, { "Run", 8 } },
	l_roll = { { "Run", 8 }, { "Climb", 14, Type = "Ladder" }, { "Drop", 14 }, { "Run", 10 } },
	l_zip = { { "Run", 8 }, { "Zip", 40, Drop = 8 }, { "Rope", 2 }, { "Run", 8 } },
	l_double = { { "Run", 14 }, { "DoubleGap", 0.6 }, { "Run", 8 }, { "WallRun", 0.8, Side = "R" }, { "Run", 10 } },
	l_dash = { { "Run", 14 }, { "DashGap", 0.6 }, { "Run", 8 }, { "DashGap", 0.7 }, { "Run", 10 } },
	l_grapple = { { "Run", 12 }, { "Grapple", 2 }, { "Run", 8 } },
	l_pull = { { "Run", 10 }, { "Pull", 16 }, { "Run", 4 }, { "WallRun", 0.8, Side = "L" }, { "Run", 8 } },
}

-- Stacked ledges for Ledge Leap (no segment does this, so it's built by hand).
local function stackedLedges(B: Kit.Builder, origin: CFrame)
	B:Box(origin * CFrame.new(0, -1, -8), Vector3.new(12, 2, 16), P.Stone, Enum.Material.Limestone)
	local wall = origin * CFrame.new(0, 0, -18)
	B:Box(wall * CFrame.new(0, 12, -2), Vector3.new(12, 24, 4), rgb(190, 180, 165), Enum.Material.Limestone, { Name = "LeapWall" })
	for i, height in { 7, 14, 21 } do
		local lip = B:Box(wall * CFrame.new(0, height - 0.3, 0.6), Vector3.new(10, 0.6, 1.2), P.Signal, Enum.Material.Neon, { Name = "LeapLip" })
		if i == 1 then
			B:Icon(lip, "^[]", P.Signal, Vector3.new(0, 2, 0))
		end
	end
	B:Box(wall * CFrame.new(0, 23, -10), Vector3.new(14, 2, 16), P.Stone, Enum.Material.Limestone, { Name = "LeapTop" })
	return wall * CFrame.new(0, 24, -18)
end

local function lessonStation(B: Kit.Builder, lesson: any, origin: CFrame, spawns: { [string]: CFrame })
	local folder = B:Group("Lesson_" .. lesson.Id)
	B:Within(folder, function()
		-- Start pad with an information sign.
		B:Box(origin * CFrame.new(0, -1, 6), Vector3.new(14, 2, 12), P.Wood, Enum.Material.WoodPlanks, { Name = "LessonPad" })
		local pad = B:Detail(origin * CFrame.new(0, 0.06, 6), Vector3.new(8, 0.12, 6), if lesson.Advanced then rgb(190, 110, 255) else P.Signal, Enum.Material.Neon)
		pad.Transparency = 0.4
		local sign = B:Box(origin * CFrame.new(-7, 4, 6), Vector3.new(0.4, 4, 8), rgb(30, 32, 42), Enum.Material.SmoothPlastic)
		B:Text(sign, Enum.NormalId.Left, (if lesson.Advanced then "ADVANCED\n" else "LESSON\n") .. string.upper(lesson.Name), { Color = if lesson.Advanced then rgb(210, 160, 255) else P.Signal })
		B:Text(sign, Enum.NormalId.Right, (if lesson.Advanced then "ADVANCED\n" else "LESSON\n") .. string.upper(lesson.Name), { Color = if lesson.Advanced then rgb(210, 160, 255) else P.Signal })
		local finish: CFrame
		if lesson.Layout == "Stacked" then
			finish = stackedLedges(B, origin)
		else
			local ctx = CourseBuilder.NewContext(B, THEME, lesson.Id, 1, origin, folder)
			ctx.NoRecovery = true
			finish = CourseBuilder.Segments(ctx, origin, STATIONS[lesson.Id] or { { "Run", 20 } })
		end
		-- The zone covers the whole station so lesson progress is tracked anywhere on it.
		local localEnd = origin:PointToObjectSpace(finish.Position)
		local length = math.abs(localEnd.Z) + 16
		local zone = B:Volume(
			origin * CFrame.new(localEnd.X / 2, 10, (localEnd.Z + 12) / 2),
			Vector3.new(math.abs(localEnd.X) + 48, 60, length + 8),
			Tags.LessonZone,
			{ LessonId = lesson.Id, Spawn = origin * CFrame.new(0, 3.5, 6), KillY = origin.Y - 16 }
		)
		zone.Name = "LessonZone"
		spawns["Lesson_" .. lesson.Id] = origin * CFrame.new(0, 3.5, 6)
	end)
end

local function travelGateFor(B: Kit.Builder, district: any, cframe: CFrame)
	local accent = district.Palette.Signal or P.Signal
	for _, x in { -5, 5 } do
		B:Box(cframe * CFrame.new(x, 7, 0), Vector3.new(1.8, 14, 1.8), rgb(60, 62, 70), Enum.Material.Metal)
	end
	B:Box(cframe * CFrame.new(0, 14.6, 0), Vector3.new(12.4, 1.4, 2), rgb(60, 62, 70), Enum.Material.Metal)
	local field = B:Box(cframe * CFrame.new(0, 7, 0), Vector3.new(8.4, 13, 0.4), accent, Enum.Material.ForceField, {
		Name = "TravelGate",
		CanCollide = false,
		Tag = Tags.TravelGate,
		Attrs = { District = district.Id },
	})
	B:Light(field, accent, 20, 1)
	local sign = B:Detail(cframe * CFrame.new(0, 16.6, 0), Vector3.new(12, 2.4, 0.3), rgb(25, 28, 36), Enum.Material.SmoothPlastic)
	local label = string.upper(district.Name) .. "\nLevel " .. district.Level .. "+"
	B:Text(sign, Enum.NormalId.Front, label, { Color = accent })
	B:Text(sign, Enum.NormalId.Back, label, { Color = accent })
	B:Prompt(field, "Travel", district.Name, { Name = "TravelPrompt", Attrs = { Board = "Travel", Destination = district.Id } })
	B:Icon(field, "⇆", accent, Vector3.new(0, 8, 0))
end

local function board(B: Kit.Builder, kind: string, title: string, cframe: CFrame, color: Color3)
	for _, x in { -2.8, 2.8 } do
		B:Box(cframe * CFrame.new(x, 2.5, 0), Vector3.new(0.4, 5, 0.4), rgb(60, 50, 40), Enum.Material.Wood)
	end
	local panel = B:Box(cframe * CFrame.new(0, 4.2, 0), Vector3.new(6, 3.4, 0.3), rgb(35, 38, 48), Enum.Material.SmoothPlastic, {
		Name = kind .. "Board",
		Tag = Tags.Board,
		Attrs = { Kind = kind, District = "Hub" },
	})
	B:Text(panel, Enum.NormalId.Front, title, { Color = color, Padding = 6 })
	B:Text(panel, Enum.NormalId.Back, title, { Color = color, Padding = 6 })
	B:Light(panel, color, 10, 0.6, "Surface", Enum.NormalId.Front)
	B:Prompt(panel, "Open", title, { Name = "BoardPrompt", Attrs = { Board = kind, District = "Hub" } })
end

local function npcSpot(B: Kit.Builder, id: string, cframe: CFrame)
	local part = B:Point(Tags.NPCSpot, id, cframe.Position)
	part.CFrame = cframe
end

function Hub.Build(world: Instance): (any, { [string]: any }, { [string]: CFrame })
	local B = Kit.new(world, "Hub", P)
	local O = D.Origin
	local origin = CFrame.new(O)
	local spawns: { [string]: CFrame } = {}
	local metas: { [string]: any } = {}
	local R = 64

	-- Ring plaza around the Guild tower ---------------------------------------------------
	B:Cylinder(origin * CFrame.new(0, -1, 0) * CFrame.Angles(0, 0, math.rad(90)), 2, R * 2, P.Stone, Enum.Material.Limestone, { Name = "GuildPlaza" })
	B:Cylinder(origin * CFrame.new(0, -0.95, 0) * CFrame.Angles(0, 0, math.rad(90)), 2, R * 2 - 16, rgb(200, 190, 175), Enum.Material.Limestone, { Decor = true })
	B:Cylinder(origin * CFrame.new(0, -40, 0) * CFrame.Angles(0, 0, math.rad(90)), 76, R * 2 - 6, rgb(170, 160, 145), Enum.Material.Limestone, { Name = "PlazaFoundation" })
	for i = 0, 23 do
		local angle = i * math.pi / 12
		local p = origin * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0.6, -R + 0.8)
		B:Detail(p, Vector3.new(16, 1.2, 1.2), P.Trim, Enum.Material.Wood)
	end

	-- The Guild signal tower: the last tower that never lost its signal.
	local towerHeight = 120
	B:Cylinder(origin * CFrame.new(0, towerHeight / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), towerHeight, 26, rgb(200, 190, 175), Enum.Material.Limestone, { Name = "GuildTower" })
	for y = 12, towerHeight - 6, 18 do
		B:Detail(origin * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(1.4, 27.4, 27.4), P.Trim, Enum.Material.Wood, { Shape = Enum.PartType.Cylinder })
		for k = 0, 5 do
			B:Detail(origin * CFrame.Angles(0, k * math.pi / 3, 0) * CFrame.new(0, y + 7, -13.05), Vector3.new(2.4, 4, 0.2), rgb(255, 214, 150), Enum.Material.Neon)
		end
	end
	-- Climbable route up the tower: a ladder spiral of platforms.
	for i = 0, 9 do
		local angle = i * 0.9
		local y = 10 + i * 11
		local ledge = origin * CFrame.Angles(0, angle, 0) * CFrame.new(0, y, -15)
		B:Box(ledge * CFrame.new(0, -0.5, 0), Vector3.new(8, 1, 6), P.Wood, Enum.Material.WoodPlanks, { Name = "TowerLedge" })
		Props.Ladder(B, origin * CFrame.Angles(0, angle, 0) * CFrame.new(0, y - 11, -13.3), 11, 2.4)
	end
	local crown = origin * CFrame.new(0, towerHeight, 0)
	B:Cylinder(crown * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)), 1, 34, P.Trim, Enum.Material.Wood, { Name = "TowerCrown" })
	local beacon = B:Ball(crown.Position + Vector3.new(0, 10, 0), 6, P.Signal, Enum.Material.Neon, { Name = "GuildBeacon", CanCollide = false })
	B:Light(beacon, P.Signal, 60, 2)
	for i = 0, 3 do
		B:Box(crown * CFrame.Angles(0, i * math.pi / 2, 0) * CFrame.new(0, 4, -12), Vector3.new(1, 8, 1), P.Trim, Enum.Material.Wood)
	end
	B:Volume(crown * CFrame.new(0, 4, 0), Vector3.new(34, 8, 34), Tags.Discovery, {
		Id = "landmark_hub_tower",
		Kind = "Landmark",
		District = "Hub",
		Title = "Guild Signal Tower",
		Text = "Landmark discovered",
	})
	B:FarBox(origin * CFrame.new(0, towerHeight / 2, 0), Vector3.new(26, towerHeight, 26), rgb(200, 190, 175))
	B:FarBox(crown * CFrame.new(0, 10, 0), Vector3.new(6, 6, 6), P.Signal, Enum.Material.Neon)
	npcSpot(B, "hub_orla", CFrame.lookAt(O + Vector3.new(0, 3, 17), O + Vector3.new(0, 3, 40)))
	B:Detail(origin * CFrame.new(0, 5, 13.2), Vector3.new(6, 10, 0.4), rgb(80, 50, 30), Enum.Material.Wood)

	-- Lift gates to every district, each facing its destination.
	for _, district in Districts.Ordered() do
		local offset = district.Origin - O
		local direction = Vector3.new(offset.X, 0, offset.Z).Unit
		local position = O + direction * (R - 8)
		travelGateFor(B, district, CFrame.lookAt(position, position + direction))
	end
	spawns.Hub = CFrame.lookAt(O + Vector3.new(30, 3, 30), O + Vector3.new(0, 3, 0))

	-- Benches and lamps around the ring.
	for i = 0, 11 do
		local angle = i * math.pi / 6 + math.pi / 12
		local p = origin * CFrame.Angles(0, angle, 0)
		Props.Lamp(B, p * CFrame.new(0, 0, -(R - 4)), rgb(255, 214, 150), 10)
		if i % 2 == 0 then
			Props.Bench(B, p * CFrame.new(0, 0, -(R - 14)) * CFrame.Angles(0, math.rad(180), 0), P.Wood)
		end
	end

	-- Services on the plaza: outfitter, archive, race board, courses board.
	local function at(angle: number, radius: number, y: number?): Vector3
		return O + dir(angle) * radius + Vector3.new(0, y or 0, 0)
	end
	local bixPos = at(20, 40)
	local booth = CFrame.lookAt(bixPos, O)
	B:Box(booth * CFrame.new(0, 1.6, 0), Vector3.new(10, 3.2, 3), P.Wood, Enum.Material.WoodPlanks, { Name = "OutfitterCounter" })
	B:Box(booth * CFrame.new(0, 8, 1), Vector3.new(12, 0.4, 6), P.Fabric, Enum.Material.Fabric)
	for _, x in { -5.5, 5.5 } do
		B:Box(booth * CFrame.new(x, 4, 2.5), Vector3.new(0.4, 8, 0.4), P.Trim, Enum.Material.Wood)
	end
	local shopSign = B:Detail(booth * CFrame.new(0, 9, -1.6), Vector3.new(10, 1.6, 0.2), rgb(30, 32, 42), Enum.Material.SmoothPlastic)
	B:Text(shopSign, Enum.NormalId.Front, "BIX'S OUTFITTERS", { Color = P.Accent })
	B:Prompt(shopSign, "Browse", "Outfitters", { Name = "ShopPrompt", Distance = 14, Attrs = { Board = "Shop", District = "Hub" } })
	npcSpot(B, "hub_bix", booth * CFrame.new(0, 3, 3) * CFrame.Angles(0, math.rad(180), 0))

	local nellPos = at(85, 40)
	local archive = CFrame.lookAt(nellPos, O)
	B:Box(archive * CFrame.new(0, 5, 3), Vector3.new(12, 10, 6), rgb(110, 90, 130), Enum.Material.Brick, { Name = "Archive" })
	for i = -2, 2 do
		B:Detail(archive * CFrame.new(i * 2.2, 4, -0.05), Vector3.new(1.8, 7, 0.2), rgb(120, 80, 50), Enum.Material.WoodPlanks)
	end
	board(B, "Achievements", "ACHIEVEMENT JOURNAL", archive * CFrame.new(-8, 0, -2), rgb(210, 180, 255))
	npcSpot(B, "hub_nell", archive * CFrame.new(0, 3, -3) * CFrame.Angles(0, math.rad(180), 0))

	local dexPos = at(140, 40)
	board(B, "Race", "RACE BOARD", CFrame.lookAt(dexPos, O), rgb(255, 120, 220))
	board(B, "Leaderboard", "RECORDS", CFrame.lookAt(at(150, 44), O), rgb(120, 230, 255))
	npcSpot(B, "hub_dex", CFrame.lookAt(at(132, 36, 3), O + Vector3.new(0, 3, 0)))

	board(B, "Courses", "COURSES", CFrame.lookAt(at(200, 40), O), rgb(120, 230, 255))

	-- Crew lounge: an amphitheatre of steps for gathering before runs.
	local loungeCenter = at(320, 104)
	local lounge = CFrame.lookAt(loungeCenter, O)
	B:Box(lounge * CFrame.new(0, -1, 0), Vector3.new(44, 2, 40), P.Stone, Enum.Material.Limestone, { Name = "LoungeFloor" })
	B:Beam(at(320, R - 2) - Vector3.new(0, 0.6, 0), loungeCenter + dir(320) * -20 - Vector3.new(0, 0.6, 0), 10, 1.2, P.Stone, Enum.Material.Limestone, { Name = "LoungeBridge" })
	for step = 0, 3 do
		B:Box(lounge * CFrame.new(0, 0.8 + step * 1.6, 8 + step * 3), Vector3.new(40 - step * 4, 1.6, 3), rgb(190, 180, 165), Enum.Material.Limestone, { Name = "LoungeStep" })
	end
	Props.StringLights(B, (lounge * CFrame.new(-20, 10, -18)).Position, (lounge * CFrame.new(20, 10, -18)).Position, rgb(255, 210, 140))
	Props.StringLights(B, (lounge * CFrame.new(-20, 10, -18)).Position, (lounge * CFrame.new(-20, 10, 18)).Position, rgb(255, 210, 140))
	board(B, "Crew", "CREW BOARD", lounge * CFrame.new(-12, 0, -14), rgb(110, 230, 170))
	npcSpot(B, "hub_juno", lounge * CFrame.new(0, 3, -10) * CFrame.Angles(0, math.rad(180), 0))
	local fire = B:Detail(lounge * CFrame.new(0, 0.6, -4), Vector3.new(3, 1.2, 3), rgb(80, 60, 50), Enum.Material.Cobblestone)
	local flame = Instance.new("Attachment")
	flame.Parent = fire
	B:Emitter(flame, "Fire", rgb(255, 170, 80))
	B:Light(fire, rgb(255, 160, 80), 24, 1.2)

	-- Training Yard ----------------------------------------------------------------------------
	local yardDir = dir(30)
	local yardNear = 150
	local yardDepth = 350
	local yardCenter = O + yardDir * (yardNear + yardDepth / 2)
	local yardCF = CFrame.lookAt(yardCenter, yardCenter + yardDir)
	B:Beam(O + yardDir * (R - 2) - Vector3.new(0, 1, 0), O + yardDir * (yardNear + 1) - Vector3.new(0, 1, 0), 14, 2, P.Stone, Enum.Material.Limestone, { Name = "YardBridge" })
	B:Box(yardCF * CFrame.new(0, -1, 0), Vector3.new(180, 2, yardDepth), rgb(120, 140, 110), Enum.Material.Grass, { Name = "YardGround" })
	B:Box(yardCF * CFrame.new(0, -26, 0), Vector3.new(176, 48, yardDepth - 4), rgb(170, 160, 145), Enum.Material.Limestone, { Name = "YardFoundation" })
	local yardSign = B:Detail(CFrame.lookAt(O + yardDir * (yardNear + 2) + Vector3.new(0, 12, 0), O + Vector3.new(0, 12, 0)), Vector3.new(30, 4, 0.5), rgb(30, 32, 42), Enum.Material.SmoothPlastic)
	B:Text(yardSign, Enum.NormalId.Front, "TRAINING YARD", { Color = P.Signal })
	spawns.Training = CFrame.lookAt(O + yardDir * (yardNear + 8) + Vector3.new(0, 3, 0), yardCenter + Vector3.new(0, 3, 0))
	npcSpot(B, "hub_tam", CFrame.lookAt(O + yardDir * (yardNear + 12) + yardCF.RightVector * 10 + Vector3.new(0, 3, 0), O + Vector3.new(0, 3, 0)))

	-- Three rows of five stations; each runs outward across the yard.
	local basic, advanced = {}, {}
	for _, lesson in Lessons.List do
		table.insert(if lesson.Advanced then advanced else basic, lesson)
	end
	local rows = { {}, {}, advanced }
	for index, lesson in basic do
		table.insert(rows[if index <= 5 then 1 else 2], lesson)
	end
	for rowIndex, row in rows do
		local rowZ = yardDepth / 2 - 14 - (rowIndex - 1) * 116
		for index, lesson in row do
			local lateral = (index - (#row + 1) / 2) * 32
			lessonStation(B, lesson, yardCF * CFrame.new(lateral, 4, rowZ), spawns)
		end
	end
	local advancedSign = B:Detail(yardCF * CFrame.new(0, 14, yardDepth / 2 - 14 - 2 * 116 + 16), Vector3.new(36, 3, 0.4), rgb(30, 32, 42), Enum.Material.SmoothPlastic)
	B:Text(advancedSign, Enum.NormalId.Back, "ADVANCED STATIONS: they open as you unlock new tools", { Color = rgb(210, 160, 255) })

	-- Practice playground: free-form obstacles to experiment on ------------------------------------
	local playDir = dir(120)
	local playCenter = O + playDir * 220
	local playCF = CFrame.lookAt(playCenter, playCenter + playDir)
	B:Beam(O + playDir * (R - 2) - Vector3.new(0, 1, 0), playCenter - playDir * 69 - Vector3.new(0, 1, 0), 12, 2, P.Stone, Enum.Material.Limestone, { Name = "PlaygroundBridge" })
	B:Box(playCF * CFrame.new(0, -1, 0), Vector3.new(170, 2, 140), rgb(180, 170, 155), Enum.Material.Limestone, { Name = "PlaygroundFloor" })
	B:Box(playCF * CFrame.new(0, -25, 0), Vector3.new(166, 46, 136), rgb(170, 160, 145), Enum.Material.Limestone)
	local playSign = B:Detail(CFrame.lookAt(playCenter - playDir * 68 + Vector3.new(0, 10, 0), O + Vector3.new(0, 10, 0)), Vector3.new(26, 3.4, 0.4), rgb(30, 32, 42), Enum.Material.SmoothPlastic)
	B:Text(playSign, Enum.NormalId.Front, "PRACTICE PLAYGROUND", { Color = P.Accent })
	local playFolder = B:Group("Playground")
	B:Within(playFolder, function()
		local ctx = CourseBuilder.NewContext(B, THEME, "playground", 1, playCF, playFolder)
		ctx.NoRecovery = true
		local lanes = {
			{ { "Run", 6 }, { "WallRun", 1, Side = "L" }, { "TicTac", 3 } },
			{ { "Run", 6 }, { "Shaft", 18 }, { "Balance", 20 } },
			{ { "Run", 6 }, { "Vault", 3 }, { "Slide", 2 } },
			{ { "Run", 6 }, { "Climb", 14, Type = "Mesh" }, { "Zip", 40, Drop = 14 } },
			{ { "Run", 6 }, { "Rope", 3 } },
			{ { "Run", 6 }, { "Grapple", 2 } },
			{ { "Run", 6 }, { "Bounce", 16 }, { "Pull", 16 } },
		}
		for index, lane in lanes do
			local lateral = (index - (#lanes + 1) / 2) * 22
			CourseBuilder.Segments(ctx, playCF * CFrame.new(lateral, 0, 60), lane)
		end
	end)

	-- Dreamline gate --------------------------------------------------------------------------------
	local gatePos = at(250, 112)
	local gate = CFrame.lookAt(gatePos, O)
	B:Beam(at(250, R - 2) - Vector3.new(0, 1, 0), gatePos - Vector3.new(0, 1, 0), 10, 2, P.Stone, Enum.Material.Limestone, { Name = "DreamBridge" })
	B:Box(gate * CFrame.new(0, -1, 0), Vector3.new(30, 2, 24), rgb(60, 50, 90), Enum.Material.Marble, { Name = "DreamPad" })
	Props.Arch(B, gate * CFrame.new(0, 0, 6), 12, 14, rgb(170, 150, 220), Enum.Material.Marble)
	local portal = B:Box(gate * CFrame.new(0, 7, 6), Vector3.new(11, 13, 0.6), rgb(255, 160, 240), Enum.Material.ForceField, { Name = "DreamPortal", CanCollide = false })
	B:Light(portal, rgb(255, 160, 240), 30, 1.5)
	B:Prompt(portal, "Enter", "The Dreamline", { Name = "DreamPrompt", Distance = 14, Attrs = { Board = "Endless" } })
	local dreamSign = B:Detail(gate * CFrame.new(0, 16.5, 6), Vector3.new(14, 2, 0.3), rgb(30, 24, 50), Enum.Material.SmoothPlastic)
	B:Text(dreamSign, Enum.NormalId.Front, "THE DREAMLINE", { Color = rgb(255, 180, 245) })
	B:Text(dreamSign, Enum.NormalId.Back, "THE DREAMLINE", { Color = rgb(255, 180, 245) })
	npcSpot(B, "hub_iris", gate * CFrame.new(-8, 3, -2))

	-- Spire approach (the tower itself is built by World/Spire) ----------------------------------------
	local spireBase = O + Districts.SpireOffset
	B:Beam(O + (spireBase - O).Unit * (R - 2) - Vector3.new(0, 1, 0), spireBase + (O - spireBase).Unit * 62 - Vector3.new(0, 1, 0), 14, 2, P.Stone, Enum.Material.Limestone, { Name = "SpireBridge" })
	npcSpot(B, "hub_aldous", CFrame.lookAt(spireBase + (O - spireBase).Unit * 66 + Vector3.new(8, 3, 0), O + Vector3.new(0, 3, 0)))
	B:Volume(CFrame.new(spireBase + (O - spireBase).Unit * 70 + Vector3.new(0, 6, 0)), Vector3.new(30, 12, 30), Tags.Discovery, {
		Id = "landmark_hub_spire",
		Kind = "Landmark",
		District = "Hub",
		Title = "The Spire",
		Text = "Landmark discovered",
	})

	-- Hub courses on their own spokes ----------------------------------------------------------------------
	local hubCourses = Courses.ByDistrict.Hub or {}
	local courseAngles = { hub_graduation = 165, relay_guild = 205 }
	for _, course in hubCourses do
		local angle = courseAngles[course.Id] or 180
		local d = dir(angle)
		local start = O + d * 100
		local startCF = CFrame.lookAt(start, start + d)
		B:Beam(O + d * (R - 2) - Vector3.new(0, 1, 0), start - Vector3.new(0, 1, 0), 8, 2, THEME.Trim, Enum.Material.WoodPlanks, { Name = "Approach" })
		local sign = B:Box(startCF * CFrame.new(5.5, 4.6, -1), Vector3.new(6, 3.2, 0.3), rgb(28, 30, 40), Enum.Material.SmoothPlastic, { Name = "CourseSign" })
		B:Text(sign, Enum.NormalId.Back, string.upper(course.Name), { Color = P.Signal })
		B:Prompt(sign, "View Course", course.Name, { Name = "CoursePrompt", Distance = 14, Attrs = { CourseId = course.Id } })
		local meta = CourseBuilder.Build(B, course, THEME, startCF)
		meta.District = "Hub"
		metas[course.Id] = meta
	end

	-- Lost letters around the hub.
	local letterSpots = {
		crown.Position + Vector3.new(6, 1, 6),
		at(320, 104, 7.2),
		at(120, 250, 0.4),
	}
	for index, entry in Lore.Letters.Hub do
		local position = letterSpots[index]
		if position then
			local paper = B:Box(CFrame.new(position + Vector3.new(0, 0.6, 0)), Vector3.new(1.2, 0.08, 0.9), rgb(245, 235, 210), Enum.Material.SmoothPlastic, {
				Name = "LostLetter",
				CanCollide = false,
				Tag = Tags.Discovery,
				Attrs = { Id = "letter_hub_" .. index, Kind = "Letter", District = "Hub", Title = entry.Title, Text = entry.Text },
			})
			B:Icon(paper, "✉", rgb(255, 240, 210), Vector3.new(0, 2, 0))
		end
	end

	-- Clouds of distant city below and the kill floor.
	for i = 0, 15 do
		local angle = i * math.pi / 8
		local p = O + DistrictBuilder.Dir(angle) * B:Rand(380, 700) + Vector3.new(0, -150, 0)
		B:Detail(CFrame.new(p), Vector3.new(B:Rand(60, 120), B:Rand(80, 200), B:Rand(60, 120)), rgb(150, 150, 165), Enum.Material.Concrete, { CanCollide = false })
	end
	B:Volume(origin * CFrame.new(0, -D.KillDepth, 0), Vector3.new(1600, 10, 1600), Tags.KillZone, { District = "Hub" })

	local ctx = { B = B, Spawn = spawns.Hub }
	return ctx, metas, spawns
end

return Hub

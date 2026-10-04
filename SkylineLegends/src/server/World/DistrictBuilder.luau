-- Lays out a district: a social plaza at the centre, course start gates on
-- spokes around it, a challenge-room annex toward the Guildhall, and pockets
-- of free-roam rooftops between the spokes holding caches, letters, quest
-- spots and contract drop-offs.
--
-- Each district module supplies the look (themes, buildings, plaza dressing,
-- landmarks, secrets); this module supplies the structure, so every district
-- plays by the same rules and new districts slot in the same way.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Courses = require(ReplicatedStorage.Shared.Config.Courses)
local Districts = require(ReplicatedStorage.Shared.Config.Districts)
local Lore = require(ReplicatedStorage.Shared.Config.Lore)
local Reach = require(ReplicatedStorage.Shared.Logic.Reach)
local Tags = require(ReplicatedStorage.Shared.Tags)

local CourseBuilder = require(script.Parent.CourseBuilder)
local Kit = require(script.Parent.Kit)

local DistrictBuilder = {}

DistrictBuilder.PlazaRadius = 48
DistrictBuilder.StartRadius = 112
DistrictBuilder.CorridorHalfWidth = 46
DistrictBuilder.HubSector = math.rad(36)
DistrictBuilder.Prefix = {
	Hub = "hub",
	Tinroof = "tin",
	Ironworks = "iron",
	Verdant = "ver",
	Gilded = "gil",
	Frostreach = "fro",
	Citadel = "cit",
}

export type Spots = { Roof: Vector3, High: { Vector3 }, Nooks: { Vector3 } }
export type Building = { Center: Vector3, Top: number, Size: Vector3, Spots: Spots }

export type Context = {
	B: Kit.Builder,
	District: any,
	Origin: CFrame,
	Y: number,
	HubDir: Vector3,
	Spokes: { { Angle: number, Course: any, Length: number, Dir: Vector3 } },
	Buildings: { Building },
	CourseMetas: { any },
	High: { Vector3 },
	Roofs: { Vector3 },
	Nooks: { Vector3 },
	Spawn: CFrame,
	UsedHigh: number,
	UsedRoof: number,
	UsedNook: number,
	Annex: CFrame?,
	Taken: { Vector3 },
}

export type DistrictModule = {
	CourseTheme: CourseBuilder.Theme,
	RoomTheme: CourseBuilder.Theme,
	Plaza: (Kit.Builder, Context) -> (),
	Building: (Kit.Builder, Context, CFrame, Vector3) -> Spots,
	Connector: ((Kit.Builder, Context, Vector3, Vector3) -> ())?,
	Landmarks: (Kit.Builder, Context) -> (),
	QuestPoints: (Kit.Builder, Context) -> (),
	Skyline: (Kit.Builder, Context) -> (),
	Annex: ((Kit.Builder, Context, CFrame) -> ())?,
	HeightRange: { number }?,
}

-- Context helpers -------------------------------------------------------------------------

function DistrictBuilder.Dir(angle: number): Vector3
	return Vector3.new(math.cos(angle), 0, math.sin(angle))
end

-- Next unused high spot / roof spot / nook (wrapping if a district runs out).
function DistrictBuilder.TakeHigh(ctx: Context): Vector3
	ctx.UsedHigh += 1
	local list = if #ctx.High > 0 then ctx.High else ctx.Roofs
	return list[((ctx.UsedHigh - 1) % #list) + 1]
end

function DistrictBuilder.TakeRoof(ctx: Context): Vector3
	ctx.UsedRoof += 1
	return ctx.Roofs[((ctx.UsedRoof - 1) % #ctx.Roofs) + 1]
end

function DistrictBuilder.TakeNook(ctx: Context): Vector3
	ctx.UsedNook += 1
	local list = if #ctx.Nooks > 0 then ctx.Nooks else ctx.Roofs
	return list[((ctx.UsedNook - 1) % #list) + 1]
end

-- The most open spot on a ring around the plaza: as far as possible from every
-- course corridor, pocket building and previously placed landmark. Used to
-- place landmarks so they never collide with a route.
function DistrictBuilder.FindClear(ctx: Context, radius: number, footprint: number): Vector3
	local origin = ctx.District.Origin
	local hubAngle = math.atan2(ctx.HubDir.Z, ctx.HubDir.X)
	local bestPosition, bestClearance = origin + DistrictBuilder.Dir(hubAngle + math.pi) * radius, -math.huge
	for step = 0, 119 do
		local angle = step * math.pi / 60
		local d = (angle - hubAngle) % (math.pi * 2)
		if d > math.pi then
			d -= math.pi * 2
		end
		if math.abs(d) > DistrictBuilder.HubSector + math.rad(10) then
			local position = origin + DistrictBuilder.Dir(angle) * radius
			local clearance = math.huge
			for _, spoke in ctx.Spokes do
				local a = origin + spoke.Dir * DistrictBuilder.StartRadius
				local b = origin + spoke.Dir * (DistrictBuilder.StartRadius + spoke.Length)
				local ab = b - a
				local t = math.clamp((position - a):Dot(ab) / math.max(ab:Dot(ab), 1e-6), 0, 1)
				local closest = a + ab * t
				clearance = math.min(clearance, Vector3.new(position.X - closest.X, 0, position.Z - closest.Z).Magnitude - DistrictBuilder.CorridorHalfWidth)
			end
			for _, building in ctx.Buildings do
				local offset = Vector3.new(position.X - building.Center.X, 0, position.Z - building.Center.Z)
				clearance = math.min(clearance, offset.Magnitude - building.Size.X / 2 - 4)
			end
			for _, taken in ctx.Taken do
				clearance = math.min(clearance, (Vector3.new(position.X, 0, position.Z) - Vector3.new(taken.X, 0, taken.Z)).Magnitude - 60)
			end
			if clearance > bestClearance then
				bestPosition, bestClearance = position, clearance
			end
		end
	end
	if bestClearance < footprint then
		warn(("[World] %s landmark at radius %d has only %.0f studs clearance"):format(ctx.District.Id, radius, bestClearance))
	end
	table.insert(ctx.Taken, bestPosition)
	-- Clear pocket buildings that would overlap the landmark.
	for index = #ctx.Buildings, 1, -1 do
		local building = ctx.Buildings[index]
		local offset = Vector3.new(bestPosition.X - building.Center.X, 0, bestPosition.Z - building.Center.Z)
		if offset.Magnitude < footprint + building.Size.X / 2 then
			warn("[World] landmark overlaps a pocket building in " .. ctx.District.Id)
		end
	end
	return bestPosition
end

-- Discoveries -----------------------------------------------------------------------------

function DistrictBuilder.Cache(ctx: Context, index: number, position: Vector3)
	local B = ctx.B
	local id = ("cache_%s_%d"):format(string.lower(ctx.District.Id), index)
	local crate = B:Box(CFrame.new(position + Vector3.new(0, 0.9, 0)) * CFrame.Angles(0, B:Rand(0, math.pi), 0), Vector3.new(2.2, 1.8, 1.6), Color3.fromRGB(196, 66, 58), Enum.Material.Fabric, {
		Name = "CourierCache",
		CanCollide = false,
		Tag = Tags.Discovery,
		Attrs = { Id = id, Kind = "Cache", District = ctx.District.Id, Title = "Courier Cache" },
	})
	B:Detail(crate.CFrame * CFrame.new(0, 0.95, 0), Vector3.new(2.3, 0.15, 1.7), Color3.fromRGB(255, 196, 92), Enum.Material.Metal)
	local light = B:Detail(crate.CFrame * CFrame.new(0, 1.2, 0), Vector3.new(0.3, 0.3, 0.3), Color3.fromRGB(255, 220, 120), Enum.Material.Neon)
	B:Light(light, Color3.fromRGB(255, 200, 120), 7, 0.6)
	B:Icon(crate, "▣", Color3.fromRGB(255, 210, 120), Vector3.new(0, 2.5, 0))
end

function DistrictBuilder.Letter(ctx: Context, index: number, position: Vector3)
	local letters = Lore.Letters[ctx.District.Id]
	local entry = letters and letters[index]
	if not entry then
		return
	end
	local B = ctx.B
	local id = ("letter_%s_%d"):format(string.lower(ctx.District.Id), index)
	local paper = B:Box(CFrame.new(position + Vector3.new(0, 0.6, 0)) * CFrame.Angles(math.rad(-20), B:Rand(0, math.pi), 0), Vector3.new(1.2, 0.08, 0.9), Color3.fromRGB(245, 235, 210), Enum.Material.SmoothPlastic, {
		Name = "LostLetter",
		CanCollide = false,
		Tag = Tags.Discovery,
		Attrs = { Id = id, Kind = "Letter", District = ctx.District.Id, Title = entry.Title, Text = entry.Text },
	})
	B:Detail(paper.CFrame * CFrame.new(0, 0.05, 0), Vector3.new(0.3, 0.02, 0.3), Color3.fromRGB(196, 66, 58), Enum.Material.SmoothPlastic)
	B:Icon(paper, "✉", Color3.fromRGB(255, 240, 210), Vector3.new(0, 2, 0))
end

function DistrictBuilder.Landmark(ctx: Context, key: string, title: string, cframe: CFrame, size: Vector3)
	ctx.B:Volume(cframe, size, Tags.Discovery, {
		Id = ("landmark_%s_%s"):format(string.lower(ctx.District.Id), key),
		Kind = "Landmark",
		District = ctx.District.Id,
		Title = title,
		Text = "Landmark discovered",
	})
end

function DistrictBuilder.Secret(ctx: Context, key: string, title: string, text: string, cframe: CFrame, size: Vector3)
	ctx.B:Volume(cframe, size, Tags.Discovery, {
		Id = "secret_" .. key,
		Kind = "Secret",
		District = ctx.District.Id,
		Title = title,
		Text = text,
	})
end

function DistrictBuilder.QuestPoint(ctx: Context, id: string, position: Vector3)
	ctx.B:Point(Tags.QuestPoint, id, position)
end

function DistrictBuilder.NPCSpot(ctx: Context, id: string, cframe: CFrame)
	local part = ctx.B:Point(Tags.NPCSpot, id, cframe.Position)
	part.CFrame = cframe
end

-- Plaza fixtures (shared by every district) ----------------------------------------------------

local function board(ctx: Context, kind: string, title: string, cframe: CFrame, color: Color3)
	local B = ctx.B
	for _, x in { -2.6, 2.6 } do
		B:Box(cframe * CFrame.new(x, 2.5, 0), Vector3.new(0.4, 5, 0.4), Color3.fromRGB(60, 50, 40), Enum.Material.Wood)
	end
	local panel = B:Box(cframe * CFrame.new(0, 4, 0), Vector3.new(5.6, 3, 0.3), Color3.fromRGB(35, 38, 48), Enum.Material.SmoothPlastic, {
		Name = kind .. "Board",
		Tag = Tags.Board,
		Attrs = { Kind = kind, District = ctx.District.Id },
	})
	B:Text(panel, Enum.NormalId.Front, title, { Color = color, Padding = 6 })
	B:Text(panel, Enum.NormalId.Back, title, { Color = color, Padding = 6 })
	B:Light(panel, color, 10, 0.6, "Surface", Enum.NormalId.Front)
	local prompt = B:Prompt(panel, "Open", title, { Name = "BoardPrompt", Attrs = { Board = kind, District = ctx.District.Id } })
	prompt.MaxActivationDistance = 10
end

function DistrictBuilder.TravelGate(ctx: Context, cframe: CFrame)
	local B = ctx.B
	local palette = ctx.District.Palette
	local accent = palette.Signal or Color3.fromRGB(80, 200, 255)
	for _, x in { -5, 5 } do
		B:Box(cframe * CFrame.new(x, 6, 0), Vector3.new(1.6, 12, 1.6), Color3.fromRGB(60, 62, 70), Enum.Material.Metal)
	end
	B:Box(cframe * CFrame.new(0, 12.5, 0), Vector3.new(12, 1.4, 1.8), Color3.fromRGB(60, 62, 70), Enum.Material.Metal)
	local field = B:Box(cframe * CFrame.new(0, 6, 0), Vector3.new(8.4, 11, 0.4), accent, Enum.Material.ForceField, {
		Name = "TravelGate",
		CanCollide = false,
		Tag = Tags.TravelGate,
		Attrs = { District = ctx.District.Id },
	})
	field.Transparency = 0.3
	B:Light(field, accent, 18, 1)
	local sign = B:Detail(cframe * CFrame.new(0, 14.2, 0), Vector3.new(10, 2, 0.3), Color3.fromRGB(25, 28, 36), Enum.Material.SmoothPlastic)
	B:Text(sign, Enum.NormalId.Front, "LIFT GATE", { Color = accent })
	B:Text(sign, Enum.NormalId.Back, "LIFT GATE", { Color = accent })
	B:Prompt(field, "Travel", "Lift Gate", { Name = "TravelPrompt", Attrs = { Board = "Travel" } })
	B:Icon(field, "⇆", accent, Vector3.new(0, 7, 0))
end

local function startSign(ctx: Context, course: any, cframe: CFrame)
	local B = ctx.B
	local accent = ctx.District.Palette.Signal or Color3.new(1, 1, 1)
	B:Box(cframe * CFrame.new(0, 2, 0), Vector3.new(0.5, 4, 0.5), Color3.fromRGB(60, 60, 66), Enum.Material.Metal)
	local panel = B:Box(cframe * CFrame.new(0, 4.6, 0), Vector3.new(6, 3.2, 0.3), Color3.fromRGB(28, 30, 40), Enum.Material.SmoothPlastic, { Name = "CourseSign" })
	local difficulty = string.rep("■", course.Difficulty) .. string.rep("□", 10 - course.Difficulty)
	local kind = if course.Kind == "Room" then "CHALLENGE ROOM" elseif course.Kind == "Relay" then "RELAY" else "COURSE"
	local text = ("<font size=\"34\"><b>%s</b></font>\n<font size=\"18\">%s · %s</font>\n<font size=\"18\">%s</font>"):format(
		string.upper(course.Name),
		kind,
		Courses.DifficultyNames[course.Difficulty],
		difficulty
	)
	B:Text(panel, Enum.NormalId.Front, text, { Color = accent, Rich = true, Padding = 8 })
	B:Text(panel, Enum.NormalId.Back, text, { Color = accent, Rich = true, Padding = 8 })
	B:Prompt(panel, "View Course", course.Name, {
		Name = "CoursePrompt",
		Distance = 14,
		Attrs = { CourseId = course.Id },
	})
end

-- Layout ----------------------------------------------------------------------------------------

local function angleDiff(a: number, b: number): number
	local d = (a - b) % (math.pi * 2)
	if d > math.pi then
		d -= math.pi * 2
	end
	return math.abs(d)
end

local function distanceToSegment(p: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local t = math.clamp((p - a):Dot(ab) / math.max(ab:Dot(ab), 1e-6), 0, 1)
	local closest = a + ab * t
	return Vector3.new(p.X - closest.X, 0, p.Z - closest.Z).Magnitude
end

-- Estimated forward length of a course recipe (for keeping pockets clear of it).
local function estimateLength(course: any): number
	local total = 40
	local function walk(segments: { any })
		for _, seg in segments do
			local kind = seg[1]
			if kind == "Split" then
				local longest = 0
				for _, lane in { seg.A, seg.F, seg.E } do
					if lane then
						local before = total
						walk(lane)
						longest = math.max(longest, total - before)
						total = before
					end
				end
				total += longest + 26
			elseif kind == "Run" then
				total += seg[2] or 16
			elseif kind == "Zip" then
				total += (seg[2] or 50) + 12
			elseif kind == "Balance" or kind == "Collapse" or kind == "Retract" or kind == "Conveyor" or kind == "Wind" or kind == "Ice" or kind == "LowGrav" then
				total += (seg[2] or 24) + 14
			elseif kind == "Grapple" then
				total += 32 + ((seg[2] or 1) - 1) * 30 + 14
			elseif kind == "TicTac" then
				total += 8 + (seg[2] or 2) * 16 + 14
			elseif kind == "Rope" then
				total += 19 + ((seg[2] or 2) - 1) * 15 + 14
			elseif kind == "Movers" then
				total += (seg[2] or 1) * 36
			else
				total += 30
			end
		end
	end
	walk(course.Segments)
	return total
end

function DistrictBuilder.Build(worldFolder: Instance, districtId: string, module: DistrictModule): (Context, { any })
	local district = Districts.ById[districtId]
	local B = Kit.new(worldFolder, districtId, district.Palette)
	local origin = CFrame.new(district.Origin)
	local hubOffset = Districts.ById.Hub.Origin - district.Origin
	local hubDir = Vector3.new(hubOffset.X, 0, hubOffset.Z).Unit
	local hubAngle = math.atan2(hubDir.Z, hubDir.X)

	local ctx: Context = {
		B = B,
		District = district,
		Origin = origin,
		Y = district.Origin.Y,
		HubDir = hubDir,
		Spokes = {},
		Buildings = {},
		CourseMetas = {},
		High = {},
		Roofs = {},
		Nooks = {},
		Spawn = CFrame.lookAt(district.Origin + hubDir * 26 + Vector3.new(0, 3, 0), district.Origin + Vector3.new(0, 3, 0)),
		UsedHigh = 0,
		UsedRoof = 0,
		UsedNook = 0,
		Annex = nil,
		Taken = {},
	}

	-- Plaza and its shared fixtures.
	module.Plaza(B, ctx)
	local gateCF = CFrame.lookAt(district.Origin + hubDir * (DistrictBuilder.PlazaRadius - 6), district.Origin)
	DistrictBuilder.TravelGate(ctx, gateCF)
	local side = hubDir:Cross(Vector3.yAxis)
	board(ctx, "Race", "RACE BOARD", CFrame.lookAt(district.Origin + hubDir * 30 + side * 16, district.Origin), Color3.fromRGB(255, 120, 220))
	board(ctx, "Jobs", "JOB BOARD", CFrame.lookAt(district.Origin + hubDir * 30 - side * 16, district.Origin), Color3.fromRGB(255, 210, 90))
	board(ctx, "Courses", "COURSES", CFrame.lookAt(district.Origin - hubDir * 18, district.Origin), Color3.fromRGB(120, 230, 255))

	-- Course spokes, skipping the sector toward the hub (that's where the annex goes).
	local spokeCourses = {}
	local rooms = {}
	for _, course in Courses.ByDistrict[districtId] or {} do
		if course.Kind == "Room" then
			table.insert(rooms, course)
		else
			table.insert(spokeCourses, course)
		end
	end
	local usable = math.pi * 2 - DistrictBuilder.HubSector * 2
	local count = #spokeCourses
	for index, course in spokeCourses do
		local angle = hubAngle + DistrictBuilder.HubSector + usable * ((index - 0.5) / count)
		local dir = DistrictBuilder.Dir(angle)
		table.insert(ctx.Spokes, { Angle = angle, Course = course, Length = estimateLength(course), Dir = dir })
	end

	local metas = {}
	for _, spoke in ctx.Spokes do
		local course = spoke.Course
		local dir = spoke.Dir
		local startY = ctx.Y + (course.Y or 0)
		local start = Vector3.new(district.Origin.X, startY, district.Origin.Z) + dir * DistrictBuilder.StartRadius
		local startCF = CFrame.lookAt(start, start + dir)
		-- Approach walkway from the plaza.
		local plazaEdge = district.Origin + dir * (DistrictBuilder.PlazaRadius - 2)
		local walkStart = Vector3.new(plazaEdge.X, ctx.Y, plazaEdge.Z)
		local walkEnd = start + dir * 0.5
		local mid = (walkStart + walkEnd) / 2
		local walkLength = (Vector3.new(walkEnd.X, 0, walkEnd.Z) - Vector3.new(walkStart.X, 0, walkStart.Z)).Magnitude
		if math.abs(startY - ctx.Y) < 1 then
			B:Box(CFrame.lookAt(mid, mid + dir) * CFrame.new(0, -1, 0), Vector3.new(8, 2, walkLength), module.CourseTheme.Trim, module.CourseTheme.SurfaceMaterial, { Name = "Approach" })
		else
			local slopeCF = CFrame.lookAt(mid, walkEnd + (walkEnd - walkStart).Unit)
			B:Box(slopeCF * CFrame.new(0, -1, 0), Vector3.new(8, 2, (walkEnd - walkStart).Magnitude), module.CourseTheme.Trim, module.CourseTheme.SurfaceMaterial, { Name = "Approach" })
		end
		startSign(ctx, course, startCF * CFrame.new(5.5, 0, -1) * CFrame.Angles(0, math.rad(180), 0))
		local meta = CourseBuilder.Build(B, course, module.CourseTheme, startCF)
		meta.District = districtId
		table.insert(metas, meta)
		spoke.Length = math.max(spoke.Length, meta.Length + 20)
	end

	-- Challenge rooms in the annex toward the hub.
	if #rooms > 0 then
		local annexStart = district.Origin + hubDir * (DistrictBuilder.PlazaRadius - 2)
		local annexCenter = district.Origin + hubDir * 138
		ctx.Annex = CFrame.lookAt(annexCenter, annexCenter + hubDir)
		local mid = (annexStart + annexCenter) / 2
		-- A covered walkway leading out to the annex hall (the travel gate sits beside it).
		local walkway = CFrame.lookAt(mid, mid + hubDir) * CFrame.new(-14, -1, 0)
		B:Box(walkway, Vector3.new(10, 2, (annexCenter - annexStart).Magnitude), module.CourseTheme.Trim, module.CourseTheme.SurfaceMaterial, { Name = "AnnexWalk" })
		local hallCF = CFrame.lookAt(annexCenter - hubDir * 6, annexCenter) * CFrame.new(0, -1, 0)
		B:Box(hallCF, Vector3.new(190, 2, 22), module.CourseTheme.Trim, module.CourseTheme.SurfaceMaterial, { Name = "AnnexHall" })
		if module.Annex then
			module.Annex(B, ctx, CFrame.lookAt(annexCenter, annexCenter + hubDir))
		end
		local hallSign = B:Detail(CFrame.lookAt(annexCenter - hubDir * 16 + Vector3.new(0, 12, 0), annexCenter - hubDir * 40 + Vector3.new(0, 12, 0)), Vector3.new(30, 4, 0.4), Color3.fromRGB(25, 28, 36), Enum.Material.SmoothPlastic)
		B:Text(hallSign, Enum.NormalId.Front, "CHALLENGE ROOMS", { Color = district.Palette.Signal })
		for index, course in rooms do
			local lateral = (index - (#rooms + 1) / 2) * 62
			local roomOrigin = CFrame.lookAt(annexCenter, annexCenter + hubDir) * CFrame.new(-14 + lateral, 0, -4)
			local walkway2 = roomOrigin * CFrame.new(0, -1, 6)
			B:Box(walkway2, Vector3.new(8, 2, 14), module.CourseTheme.Trim, module.CourseTheme.SurfaceMaterial)
			startSign(ctx, course, roomOrigin * CFrame.new(5.5, 0, 4) * CFrame.Angles(0, math.rad(180), 0))
			local meta = CourseBuilder.Build(B, course, module.RoomTheme, roomOrigin)
			meta.District = districtId
			table.insert(metas, meta)
			-- Enclose the room.
			local min, max = meta.LocalMin, meta.LocalMax
			local margin = 6
			local sizeX = (max.X - min.X) + margin * 2
			local sizeZ = (max.Z - min.Z) + margin * 2
			local floorY = min.Y - 2
			local height = (max.Y - floorY) + 8
			local center = roomOrigin * CFrame.new((min.X + max.X) / 2, floorY + height / 2, (min.Z + max.Z) / 2)
			local wallColor = module.RoomTheme.Wall
			local wallMat = module.RoomTheme.WallMaterial
			for _, sx in { -1, 1 } do
				B:Box(center * CFrame.new(sx * sizeX / 2, 0, 0), Vector3.new(2, height, sizeZ), wallColor, wallMat, { Name = "RoomWall" })
			end
			-- Far wall, and the near wall with a doorway level with the start platform.
			B:Box(center * CFrame.new(0, 0, (min.Z - max.Z) / 2 - margin), Vector3.new(sizeX, height, 2), wallColor, wallMat, { Name = "RoomWall" })
			local nearZ = max.Z + margin
			local left, right = min.X - margin, max.X + margin
			local top = floorY + height
			local function nearPiece(x0: number, x1: number, y0: number, y1: number)
				if x1 - x0 > 0.2 and y1 - y0 > 0.2 then
					B:Box(roomOrigin * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, nearZ), Vector3.new(x1 - x0, y1 - y0, 2), wallColor, wallMat, { Name = "RoomWall" })
				end
			end
			nearPiece(left, -5, floorY, top)
			nearPiece(5, right, floorY, top)
			nearPiece(-5, 5, 11, top)
			nearPiece(-5, 5, floorY, -2)
			B:Box(center * CFrame.new(0, height / 2 + 1, 0), Vector3.new(sizeX + 2, 2, sizeZ + 4), wallColor, wallMat, { Name = "RoomRoof" })
			-- Light strips along the ceiling.
			for k = -1, 1 do
				local strip = B:Detail(center * CFrame.new(k * sizeX / 4, height / 2 - 0.3, 0), Vector3.new(1, 0.3, sizeZ - 6), Color3.fromRGB(255, 245, 225), Enum.Material.Neon)
				B:Light(strip, Color3.fromRGB(255, 240, 220), 40, 1.2, "Spot", Enum.NormalId.Bottom)
			end
		end
	end

	-- Exploration pockets between the spokes.
	local angles = {}
	for _, spoke in ctx.Spokes do
		table.insert(angles, spoke)
	end
	table.sort(angles, function(a, b)
		return (a.Angle - hubAngle) % (math.pi * 2) < (b.Angle - hubAngle) % (math.pi * 2)
	end)
	local function clearOfCourses(position: Vector3, radius: number): boolean
		local flat = Vector3.new(position.X - district.Origin.X, 0, position.Z - district.Origin.Z)
		if flat.Magnitude < DistrictBuilder.StartRadius + 50 then
			return false
		end
		local angle = math.atan2(flat.Z, flat.X)
		if angleDiff(angle, hubAngle) < DistrictBuilder.HubSector + math.rad(8) and flat.Magnitude < 380 then
			return false
		end
		for _, spoke in ctx.Spokes do
			local a = district.Origin + spoke.Dir * DistrictBuilder.StartRadius
			local b = district.Origin + spoke.Dir * (DistrictBuilder.StartRadius + spoke.Length)
			if distanceToSegment(position, a, b) < DistrictBuilder.CorridorHalfWidth + radius then
				return false
			end
		end
		for _, building in ctx.Buildings do
			local offset = Vector3.new(position.X - building.Center.X, 0, position.Z - building.Center.Z)
			if offset.Magnitude < radius + building.Size.X / 2 + 7 then
				return false
			end
		end
		return true
	end

	for _, radius in { 200, 255, 310, 365, 420, 480 } do
		local circumference = math.pi * 2 * radius
		local steps = math.floor(circumference / 48)
		for step = 0, steps - 1 do
			local angle = hubAngle + (step / steps) * math.pi * 2 + B:Rand(-0.02, 0.02)
			local r = radius + B:Rand(-10, 10)
			local position = district.Origin + DistrictBuilder.Dir(angle) * r
			local width = B:Rand(20, 32)
			if clearOfCourses(position, width * 0.75) then
				local range = module.HeightRange or { -8, 14 }
				local top = ctx.Y + math.floor(B:Rand(range[1], range[2]) / 2) * 2
				local size = Vector3.new(width, 0, B:Rand(20, 32))
				local cf = CFrame.lookAt(Vector3.new(position.X, top, position.Z), Vector3.new(district.Origin.X, top, district.Origin.Z))
				local spots = module.Building(B, ctx, cf, size)
				table.insert(ctx.Buildings, { Center = Vector3.new(position.X, top, position.Z), Top = top, Size = size, Spots = spots })
				table.insert(ctx.Roofs, spots.Roof)
				for _, p in spots.High do
					table.insert(ctx.High, p)
				end
				for _, p in spots.Nooks do
					table.insert(ctx.Nooks, p)
				end
			end
		end
	end

	-- Connect neighbouring rooftops: jumpable gaps are left as they are, wider ones get
	-- a plank or a zipline so every pocket is traversable.
	for i, a in ctx.Buildings do
		local best, bestDistance = nil, math.huge
		for j, b in ctx.Buildings do
			if j ~= i then
				local d = Vector3.new(a.Center.X - b.Center.X, 0, a.Center.Z - b.Center.Z).Magnitude
				if d < bestDistance then
					best, bestDistance = b, d
				end
			end
		end
		if best and bestDistance < 75 then
			local edgeGap = bestDistance - (a.Size.X + best.Size.X) / 2
			local dy = best.Top - a.Top
			if edgeGap > Reach.JumpDistance(dy) * 0.6 then
				local from = Vector3.new(a.Center.X, a.Top, a.Center.Z)
				local to = Vector3.new(best.Center.X, best.Top, best.Center.Z)
				local dir = Vector3.new(to.X - from.X, 0, to.Z - from.Z).Unit
				local p0 = from + dir * (a.Size.X / 2 - 1)
				local p1 = to - dir * (best.Size.X / 2 - 1)
				if module.Connector then
					module.Connector(B, ctx, p0, p1)
				else
					local beam = B:Beam(p0 - Vector3.new(0, 0.5, 0), p1 - Vector3.new(0, 0.5, 0), 1.3, 1, module.CourseTheme.Beam, module.CourseTheme.BeamMaterial, { Name = "Plank", Tag = Tags.Balance })
					B:Icon(beam, "=", Color3.new(1, 1, 1), Vector3.new(0, 2, 0))
				end
			end
		end
	end

	-- A walkway from the plaza out to each pocket's nearest rooftop.
	local linked = {}
	for _, building in ctx.Buildings do
		local flat = Vector3.new(building.Center.X - district.Origin.X, 0, building.Center.Z - district.Origin.Z)
		local angle = math.atan2(flat.Z, flat.X)
		local bucket = math.floor(((angle - hubAngle) % (math.pi * 2)) / (math.pi * 2 / math.max(count, 1)))
		local current = linked[bucket]
		if not current or flat.Magnitude < current.Distance then
			linked[bucket] = { Building = building, Distance = flat.Magnitude }
		end
	end
	for _, entry in linked do
		local building = entry.Building
		local dir = Vector3.new(building.Center.X - district.Origin.X, 0, building.Center.Z - district.Origin.Z).Unit
		local a = Vector3.new(district.Origin.X, ctx.Y, district.Origin.Z) + dir * (DistrictBuilder.PlazaRadius - 2)
		local b = Vector3.new(building.Center.X, building.Top, building.Center.Z) - dir * (building.Size.X / 2 - 1)
		B:Beam(a - Vector3.new(0, 0.6, 0), b - Vector3.new(0, 0.6, 0), 4, 1.2, module.CourseTheme.Trim, module.CourseTheme.SurfaceMaterial, { Name = "Skybridge" })
		for _, s in { -1, 1 } do
			local side2 = dir:Cross(Vector3.yAxis) * s * 2.2
			B:Beam(a + side2 + Vector3.new(0, 1.6, 0), b + side2 + Vector3.new(0, 1.6, 0), 0.2, 0.2, module.CourseTheme.Trim, Enum.Material.Metal, { Decor = true, CanCollide = true })
		end
	end

	-- Discoveries spread through the pockets.
	for index = 1, 6 do
		DistrictBuilder.Cache(ctx, index, DistrictBuilder.TakeNook(ctx))
	end
	for index = 1, #(Lore.Letters[districtId] or {}) do
		DistrictBuilder.Letter(ctx, index, DistrictBuilder.TakeRoof(ctx) + Vector3.new(B:Rand(-3, 3), 0, B:Rand(-3, 3)))
	end
	-- Contract drop-off points on rooftops.
	for index = 1, 8 do
		local roof = DistrictBuilder.TakeRoof(ctx)
		B:Point(Tags.ContractPoint, ("%s_contract_%d"):format(string.lower(districtId), index), roof + Vector3.new(0, 1, 0))
	end

	module.Landmarks(B, ctx)
	module.QuestPoints(B, ctx)
	module.Skyline(B, ctx)
	DistrictBuilder.QuestPoint(ctx, DistrictBuilder.Prefix[districtId] .. "_plaza", district.Origin + Vector3.new(0, 2, 0))
	return ctx, metas
end

return DistrictBuilder

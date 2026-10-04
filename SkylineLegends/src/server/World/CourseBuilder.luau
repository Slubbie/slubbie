-- Turns course recipes (Config/Courses) into geometry.
--
-- A course is built by walking a cursor: a CFrame on the top surface at the
-- end of the last platform, facing along the course. Each segment builds its
-- geometry relative to the cursor and returns the new cursor. Gap sizes and
-- wall heights come from Logic/Reach, so routes stay achievable.
--
-- While building, the context records everything the game needs at runtime:
-- checkpoints, tokens, shortcuts, rising water, par time and required
-- abilities per route, which become the course's medal thresholds.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Medals = require(ReplicatedStorage.Shared.Logic.Medals)
local MovementConfig = require(ReplicatedStorage.Shared.Config.Movement)
local Reach = require(ReplicatedStorage.Shared.Logic.Reach)
local Tags = require(ReplicatedStorage.Shared.Tags)

local Kit = require(script.Parent.Kit)

local M = MovementConfig
local LANE_SPACING = 26
local PLATFORM_THICKNESS = 2

local CourseBuilder = {}
CourseBuilder.LaneSpacing = LANE_SPACING

export type Theme = {
	Id: string,
	Surface: Color3,
	SurfaceMaterial: Enum.Material,
	Trim: Color3,
	Wall: Color3,
	WallMaterial: Enum.Material,
	Accent: Color3,
	Signal: Color3,
	Beam: Color3,
	BeamMaterial: Enum.Material,
	Rope: Color3,
	Climb: string,
	BodyDepth: number,
	Platform: ((Kit.Builder, CFrame, number, number, string?) -> ())?,
	Body: ((Kit.Builder, CFrame, number, number, number) -> ())?,
	WallStyle: ((Kit.Builder, CFrame, Vector3) -> BasePart)?,
	Deco: ((Kit.Builder, CFrame, number, number) -> ())?,
	AnchorMount: ((Kit.Builder, Vector3) -> ())?,
	Floating: boolean?,
}

export type Volume = { CFrame: CFrame, Size: Vector3 }
export type Meta = {
	Id: string,
	Spawn: CFrame,
	Checkpoints: { { Spawn: CFrame, Volume: Volume, Exchange: boolean } },
	Finish: Volume,
	Tokens: { Vector3 },
	Shortcuts: { Volume },
	KillY: number,
	Par: { A: number, F: number, E: number },
	Medals: { number },
	Requires: { string },
	FastRequires: { string },
	ExpertRequires: { string },
	Length: number,
	Folder: Folder,
	LocalMin: Vector3,
	LocalMax: Vector3,
	Origin: CFrame,
	FlowTarget: number,
	Exchanges: { number },
}

type Ctx = {
	B: Kit.Builder,
	Theme: Theme,
	Id: string,
	Difficulty: number,
	Width: number,
	Origin: CFrame,
	Folder: Folder,
	Lane: string?,
	LaneSign: number,
	Par: { [string]: number },
	Requires: { [string]: { [string]: boolean } },
	TokenSpots: { { Position: Vector3, Priority: number, Lane: string? } },
	Checkpoints: { { Spawn: CFrame, Volume: Volume, Exchange: boolean } },
	Shortcuts: { Volume },
	Water: { StartCP: number, Rate: number }?,
	SectionMin: Vector3,
	SectionMax: Vector3,
	Techniques: number,
	MinY: number,
	Safe: boolean,
	NoRecovery: boolean?,
}

-- Small geometry helpers --------------------------------------------------------------

local function fwd(c: CFrame, distance: number): CFrame
	return c * CFrame.new(0, 0, -distance)
end

local function track(ctx: Ctx, position: Vector3)
	ctx.MinY = math.min(ctx.MinY, position.Y)
	local p = ctx.Origin:PointToObjectSpace(position)
	ctx.SectionMin = ctx.SectionMin:Min(p)
	ctx.SectionMax = ctx.SectionMax:Max(p)
end

local function addPar(ctx: Ctx, seconds: number)
	local lane = ctx.Lane
	if lane then
		ctx.Par[lane] += seconds
	else
		ctx.Par.A += seconds
		ctx.Par.F += seconds
		ctx.Par.E += seconds
	end
end

local function require_(ctx: Ctx, ability: string)
	local lane = ctx.Lane
	if lane then
		ctx.Requires[lane][ability] = true
	else
		for _, name in { "A", "F", "E" } do
			ctx.Requires[name][ability] = true
		end
	end
	ctx.Techniques += 1
end

local function token(ctx: Ctx, position: Vector3, priority: number)
	table.insert(ctx.TokenSpots, { Position = position, Priority = priority, Lane = ctx.Lane })
end

-- A platform from the cursor forward. Returns the cursor at its far end.
local function platform(ctx: Ctx, c: CFrame, length: number, width: number?, role: string?): CFrame
	local w = width or ctx.Width
	local topCenter = c * CFrame.new(0, 0, -length / 2)
	local theme = ctx.Theme
	if theme.Platform then
		theme.Platform(ctx.B, topCenter, w, length, role)
	else
		ctx.B:Box(topCenter * CFrame.new(0, -PLATFORM_THICKNESS / 2, 0), Vector3.new(w, PLATFORM_THICKNESS, length), theme.Surface, theme.SurfaceMaterial)
	end
	if theme.Body and role ~= "Floating" and role ~= "Recovery" and role ~= "Mover" then
		theme.Body(ctx.B, topCenter * CFrame.new(0, -PLATFORM_THICKNESS, 0), w, length, theme.BodyDepth)
	end
	if theme.Deco and role == nil and length >= 14 then
		theme.Deco(ctx.B, topCenter, w, length)
	end
	if length >= 8 and role ~= "Start" and role ~= "Finish" and role ~= "Recovery" then
		token(ctx, (topCenter * CFrame.new(0, 3.5, 0)).Position, 0)
	end
	track(ctx, topCenter.Position)
	track(ctx, (c * CFrame.new(w / 2, 0, 0)).Position)
	track(ctx, (c * CFrame.new(-w / 2, 0, -length)).Position)
	return fwd(c, length)
end

-- A solid block whose top is `height` above the cursor, starting `ahead` studs forward.
local function block(ctx: Ctx, c: CFrame, ahead: number, height: number, depth: number, width: number?): BasePart
	local w = width or ctx.Width
	local below = 6
	local size = Vector3.new(w, height + below, depth)
	local cframe = c * CFrame.new(0, (height - below) / 2, -(ahead + depth / 2))
	local part = ctx.B:Box(cframe, size, ctx.Theme.Wall, ctx.Theme.WallMaterial)
	track(ctx, cframe.Position + Vector3.new(0, height / 2, 0))
	return part
end

local function signalStrip(ctx: Ctx, cframe: CFrame, size: Vector3)
	ctx.B:Detail(cframe, size, ctx.Theme.Signal, Enum.Material.Neon)
end

-- Climbable surface (ladder, vines or mesh) against a face, from y0 to y1.
-- `face` is a CFrame on the wall surface, looking away from the wall.
local function climbSurface(ctx: Ctx, face: CFrame, width: number, height: number, kind: string)
	local B, theme = ctx.B, ctx.Theme
	local surface = B:Box(
		face * CFrame.new(0, height / 2, -0.3),
		Vector3.new(width, height, 0.6),
		if kind == "Vines" then Color3.fromRGB(60, 110, 55) else theme.Wall,
		if kind == "Vines" then Enum.Material.LeafyGrass else theme.WallMaterial,
		{ Name = "ClimbSurface", Tag = Tags.Climbable, Attrs = { Kind = kind } }
	)
	if kind == "Ladder" then
		surface.Transparency = 0.6
		for _, x in { -width / 2 + 0.3, width / 2 - 0.3 } do
			B:Detail(face * CFrame.new(x, height / 2, -0.9), Vector3.new(0.35, height, 0.35), Color3.fromRGB(70, 72, 80), Enum.Material.Metal)
		end
		for y = 1, math.floor(height) - 1, 2 do
			B:Detail(face * CFrame.new(0, y, -0.9), Vector3.new(width - 0.6, 0.22, 0.22), Color3.fromRGB(90, 92, 100), Enum.Material.Metal)
		end
	elseif kind == "Vines" then
		for i = 1, math.max(2, math.floor(width / 1.5)) do
			local x = -width / 2 + (i - 0.5) * (width / math.max(2, math.floor(width / 1.5)))
			B:Detail(face * CFrame.new(x, height / 2, -0.75), Vector3.new(0.3, height, 0.3), Color3.fromRGB(80, 120, 60), Enum.Material.Grass)
		end
		for _ = 1, math.floor(height / 3) do
			B:Detail(
				face * CFrame.new(B:Rand(-width / 2, width / 2), B:Rand(0.5, height), -0.9),
				Vector3.new(1.4, 1.1, 0.4),
				Color3.fromRGB(70, B:RandInt(130, 170), 70),
				Enum.Material.LeafyGrass
			)
		end
	else -- Mesh
		surface.Transparency = 0.35
		surface.Material = Enum.Material.DiamondPlate
		for y = 0, math.floor(height), 2 do
			B:Detail(face * CFrame.new(0, y, -0.7), Vector3.new(width, 0.15, 0.15), Color3.fromRGB(150, 155, 160), Enum.Material.Metal)
		end
		for x = -width / 2, width / 2, 2 do
			B:Detail(face * CFrame.new(x, height / 2, -0.7), Vector3.new(0.15, height, 0.15), Color3.fromRGB(150, 155, 160), Enum.Material.Metal)
		end
	end
	B:Icon(surface, "#", Color3.fromRGB(150, 230, 140), Vector3.new(0, height / 2 + 1, 0))
	track(ctx, (face * CFrame.new(0, height, 0)).Position)
end

-- Safe landing below a gap, with a ladder back up the far side.
local function recovery(ctx: Ctx, startC: CFrame, gap: number, landY: number)
	if ctx.NoRecovery or gap < 5 then
		return
	end
	if not (ctx.Lane == "A" or (ctx.Lane == nil and ctx.Safe)) then
		return
	end
	local drop = 11
	local y = math.min(0, landY) - drop
	local top = startC * CFrame.new(0, y, -gap / 2)
	ctx.B:Box(
		top * CFrame.new(0, -0.75, 0),
		Vector3.new(ctx.Width + 2, 1.5, gap + 2),
		Color3.fromRGB(70, 130, 180),
		Enum.Material.Fabric,
		{ Name = "RecoveryPad" }
	)
	local mat = ctx.B:Detail(top * CFrame.new(0, 0.05, 0), Vector3.new(ctx.Width - 1, 0.1, gap - 1), Color3.fromRGB(110, 170, 220), Enum.Material.Fabric)
	ctx.B:Icon(mat, "↺", Color3.fromRGB(150, 210, 255), Vector3.new(0, 2, 0))
	-- Ladder up the front face of the landing platform.
	local face = startC * CFrame.new(0, y, -gap + 0.05) * CFrame.Angles(0, math.rad(180), 0)
	climbSurface(ctx, face, 3, landY - y + 0.2, "Ladder")
	track(ctx, top.Position)
end

local function wallStyle(ctx: Ctx, cframe: CFrame, size: Vector3): BasePart
	if ctx.Theme.WallStyle then
		return ctx.Theme.WallStyle(ctx.B, cframe, size)
	end
	return ctx.B:Box(cframe, size, ctx.Theme.Wall, ctx.Theme.WallMaterial)
end

-- Chevrons painted on a designed wall-run surface.
local function chevrons(ctx: Ctx, wall: BasePart, face: Enum.NormalId, vertical: boolean?)
	ctx.B:Text(wall, face, if vertical then "▲\n▲\n▲" else "»    »    »    »", {
		Color = ctx.Theme.Signal,
		PixelsPerStud = 10,
		LightInfluence = 0,
	})
	ctx.B:Icon(wall, if vertical then "▲" else "»", ctx.Theme.Signal, Vector3.new(0, wall.Size.Y / 2 + 1, 0))
end

local function lowBeam(ctx: Ctx, cframe: CFrame, width: number)
	local beam = ctx.B:Box(cframe, Vector3.new(width, 2, 1.4), Color3.fromRGB(240, 196, 40), Enum.Material.SmoothPlastic, {
		Name = "SlideBeam",
		Tag = Tags.LowClearance,
		Group = Tags.Groups.LowClearance,
	})
	for i = -2, 2 do
		ctx.B:Detail(cframe * CFrame.new(i * (width / 5), 0, -0.71), Vector3.new(width / 10, 2, 0.05), Color3.fromRGB(30, 30, 30), Enum.Material.SmoothPlastic, { CanCollide = false })
	end
	ctx.B:Icon(beam, "▼", Color3.fromRGB(255, 220, 80), Vector3.new(0, 2.2, 0))
	return beam
end

-- Segments -----------------------------------------------------------------------------------

local S: { [string]: (Ctx, CFrame, { [any]: any }) -> CFrame } = {}

S.Run = function(ctx, c, seg)
	local length = seg[2] or 16
	addPar(ctx, length / M.SprintSpeed)
	return platform(ctx, c, length, seg.W)
end

S.Gap = function(ctx, c, seg)
	local fraction = math.clamp(seg[2] or 0.5, 0.2, 0.95)
	local dy = seg.Rise or 0
	local speed = if seg.Walk then M.WalkSpeed else M.SprintSpeed
	local gap = math.max(fraction * Reach.JumpDistance(dy, speed), 3)
	local landing = seg.L or 14
	token(ctx, (c * CFrame.new(0, Reach.JumpApex() * 0.7 + 2 + math.max(dy, 0) * 0.5, -gap / 2)).Position, if fraction > 0.75 then 3 else 2)
	recovery(ctx, c, gap, dy)
	addPar(ctx, gap / speed + 0.1 + landing / M.SprintSpeed)
	return platform(ctx, c * CFrame.new(0, dy, -gap), landing)
end

S.Steps = function(ctx, c, seg)
	local count = seg[2] or 3
	local rise = seg.Rise or 2.5
	for _ = 1, count do
		local gap = math.max(0.42 * Reach.JumpDistance(rise), 2.5)
		c = platform(ctx, c * CFrame.new(0, rise, -gap), 7)
		addPar(ctx, gap / M.SprintSpeed + 0.35)
	end
	return c
end

S.Drop = function(ctx, c, seg)
	local height = seg[2] or 8
	-- A short gap, then a padded landing well below.
	local landC = c * CFrame.new(0, -height, -3)
	local after = platform(ctx, landC, 18, nil, "Landing")
	local pad = ctx.B:Detail(landC * CFrame.new(0, 0.06, -6), Vector3.new(ctx.Width - 2, 0.12, 8), ctx.Theme.Accent, Enum.Material.Fabric)
	ctx.B:Text(pad, Enum.NormalId.Top, "ROLL", { Color = Color3.new(1, 1, 1), PixelsPerStud = 8 })
	ctx.B:Icon(pad, "@", ctx.Theme.Signal, Vector3.new(0, 1.5, 0))
	token(ctx, (landC * CFrame.new(0, height * 0.5, -3)).Position, 1)
	addPar(ctx, math.sqrt(2 * height / (M.Gravity * M.FallGravityMultiplier)) + 0.15 + 18 / M.SprintSpeed)
	return after
end

S.Vault = function(ctx, c, seg)
	local count = seg[2] or 1
	local length = 10 + count * 10
	local after = platform(ctx, c, length, nil, "Course")
	for i = 1, count do
		local z = 8 + (i - 1) * 10
		local wall = ctx.B:Box(c * CFrame.new(0, 1.5, -z), Vector3.new(ctx.Width, 3, 1.6), ctx.Theme.Trim, ctx.Theme.WallMaterial, { Name = "VaultWall" })
		ctx.B:Icon(wall, "^", ctx.Theme.Signal, Vector3.new(0, 2.5, 0))
	end
	require_(ctx, "Vault")
	addPar(ctx, length / M.SprintSpeed + 0.05 * count)
	return after
end

S.Slide = function(ctx, c, seg)
	local count = seg[2] or 1
	local length = 10 + count * 12
	local after = platform(ctx, c, length, nil, "Course")
	for i = 1, count do
		local z = 8 + (i - 1) * 12
		lowBeam(ctx, c * CFrame.new(0, 3.6, -z), ctx.Width)
		-- Solid wall above the beam so it can't be jumped.
		wallStyle(ctx, c * CFrame.new(0, 4.6 + 4, -z), Vector3.new(ctx.Width, 8, 1.4))
	end
	require_(ctx, "Slide")
	addPar(ctx, length / 30)
	return after
end

S.Tunnel = function(ctx, c, seg)
	local length = seg[2] or 14
	local entry = platform(ctx, c, 4, nil, "Course")
	local after = platform(ctx, entry, length, nil, "Course")
	local center = entry * CFrame.new(0, 0, -length / 2)
	-- Low ceiling (crouch or slide), solid sides and roof.
	ctx.B:Box(center * CFrame.new(0, 3.3, 0), Vector3.new(ctx.Width, 1.4, length), Color3.fromRGB(240, 196, 40), Enum.Material.SmoothPlastic, {
		Name = "TunnelCeiling",
		Tag = Tags.LowClearance,
		Group = Tags.Groups.LowClearance,
	})
	ctx.B:Box(center * CFrame.new(0, 5.5, 0), Vector3.new(ctx.Width + 2, 3, length), ctx.Theme.Wall, ctx.Theme.WallMaterial)
	for _, side in { -1, 1 } do
		ctx.B:Box(center * CFrame.new(side * (ctx.Width / 2 + 0.5), 2.5, 0), Vector3.new(1, 5, length), ctx.Theme.Wall, ctx.Theme.WallMaterial)
	end
	local sign = ctx.B:Detail(entry * CFrame.new(0, 7.6, 0.2), Vector3.new(4, 1.2, 0.2), Color3.fromRGB(240, 196, 40), Enum.Material.SmoothPlastic)
	ctx.B:Text(sign, Enum.NormalId.Back, "CROUCH", { Color = Color3.fromRGB(30, 30, 30) })
	local light = ctx.B:Detail(center * CFrame.new(0, 2.5, 0), Vector3.new(0.4, 0.2, 0.4), ctx.Theme.Signal, Enum.Material.Neon)
	ctx.B:Light(light, ctx.Theme.Signal, 14, 0.8)
	require_(ctx, "Slide")
	addPar(ctx, 4 / M.SprintSpeed + length / 16)
	return after
end

S.Ledge = function(ctx, c, seg)
	local height = math.clamp(seg[2] or 8, 4, Reach.LedgeHeight() - 1.4)
	local approach = platform(ctx, c, 6, nil, "Course")
	block(ctx, approach, 0, height, 14)
	local topC = approach * CFrame.new(0, height, 0)
	signalStrip(ctx, topC * CFrame.new(0, -0.15, 0.05), Vector3.new(ctx.Width, 0.3, 0.12))
	local after = platform(ctx, topC, 14, nil, "Course")
	token(ctx, (topC * CFrame.new(0, 2.5, -7)).Position, 1)
	require_(ctx, "LedgeGrab")
	addPar(ctx, 6 / M.SprintSpeed + 0.85 + height * 0.025 + 14 / M.SprintSpeed)
	return after
end

S.WallClimb = function(ctx, c, seg)
	local height = math.clamp(seg[2] or 13, Reach.LedgeHeight() - 1, Reach.WallClimbHeight() - 1.2)
	local approach = platform(ctx, c, 14, nil, "Course")
	local wall = block(ctx, approach, 0, height, 14)
	chevrons(ctx, wall, Enum.NormalId.Back, true)
	local topC = approach * CFrame.new(0, height, 0)
	signalStrip(ctx, topC * CFrame.new(0, -0.15, 0.05), Vector3.new(ctx.Width, 0.3, 0.12))
	local after = platform(ctx, topC, 14, nil, "Course")
	require_(ctx, "WallRun")
	require_(ctx, "LedgeGrab")
	addPar(ctx, 14 / M.SprintSpeed + 1.1 + 14 / M.SprintSpeed)
	return after
end

S.Shimmy = function(ctx, c, seg)
	local length = seg[2] or 14
	-- Shift sideways away from the centre lane.
	local side = if ctx.LaneSign ~= 0 then ctx.LaneSign else (seg.Side == "L" and -1 or 1)
	local B, theme = ctx.B, ctx.Theme
	local lipTop = 2.5
	-- The wall ahead, across the void, with a lip to hang from.
	local wallCenter = c * CFrame.new(side * (length / 2 + 1), lipTop - 7, -3.2)
	B:Box(wallCenter, Vector3.new(length + 8, 14, 2), theme.Wall, theme.WallMaterial, { Name = "ShimmyWall" })
	signalStrip(ctx, c * CFrame.new(side * (length / 2 + 1), lipTop - 0.15, -2.15), Vector3.new(length + 8, 0.3, 0.1))
	-- An overhang above the lip stops you climbing up until the far end.
	B:Box(c * CFrame.new(side * (length / 2 - 2), lipTop + 2.4, -3.6), Vector3.new(length + 2, 1.2, 4), theme.Trim, theme.WallMaterial, { Name = "Overhang", Attrs = { NoLedge = true } })
	-- Exit platform at the far end, flush with the lip.
	local exitC = c * CFrame.new(side * (length + 2), lipTop, -2.2)
	local after = platform(ctx, exitC, 12, nil, "Course")
	recovery(ctx, c * CFrame.new(side * (length / 2), 0, 0), 4, lipTop)
	token(ctx, (c * CFrame.new(side * (length / 2), lipTop - 2, -1.5)).Position, 2)
	require_(ctx, "LedgeGrab")
	addPar(ctx, 0.8 + length / M.ShimmySpeed + 0.5 + 12 / M.SprintSpeed)
	return after
end

S.Climb = function(ctx, c, seg)
	local height = math.clamp(seg[2] or 12, 4, 24)
	local kind = seg.Type or ctx.Theme.Climb
	local approach = platform(ctx, c, 6, nil, "Course")
	block(ctx, approach, 0, height, 14)
	local face = approach * CFrame.Angles(0, math.rad(180), 0) * CFrame.new(0, 0, 0.05)
	-- `face` looks back toward the player; the climb surface sits on the block's front face.
	climbSurface(ctx, face * CFrame.Angles(0, 0, 0), 4, height + 0.4, kind)
	local topC = approach * CFrame.new(0, height, 0)
	local after = platform(ctx, topC, 14, nil, "Course")
	require_(ctx, "Climb")
	addPar(ctx, 6 / M.SprintSpeed + height / M.ClimbUpSpeed + 0.7 + 14 / M.SprintSpeed)
	return after
end

S.WallRun = function(ctx, c, seg)
	local seconds = math.clamp(seg[2] or 0.8, 0.4, 1.25)
	local side = if seg.Side == "L" then -1 else 1
	local run, drop = Reach.WallRun(seconds * 1.1)
	local gap = 6 + run * 0.86
	local landY = -(drop + 1.5)
	local B = ctx.B
	local wallLength = gap + 4
	local wall = wallStyle(
		ctx,
		c * CFrame.new(side * 5, (12 + landY - 8) / 2, -(gap / 2 + 0)),
		Vector3.new(2, 12 - (landY - 8), wallLength)
	)
	wall.Name = "RunWall"
	chevrons(ctx, wall, if side > 0 then Enum.NormalId.Left else Enum.NormalId.Right)
	B:Detail(c * CFrame.new(side * 3.95, 4, -gap / 2), Vector3.new(0.1, 0.4, wallLength), ctx.Theme.Signal, Enum.Material.Neon)
	token(ctx, (c * CFrame.new(side * 2.6, 3.5, -gap * 0.55)).Position, 2)
	track(ctx, wall.Position)
	recovery(ctx, c, gap, landY)
	require_(ctx, "WallRun")
	addPar(ctx, gap / M.WallRunSpeed + 0.2 + 14 / M.SprintSpeed)
	return platform(ctx, c * CFrame.new(0, landY, -gap), 14)
end

S.TicTac = function(ctx, c, seg)
	local count = math.clamp(seg[2] or 2, 2, 4)
	local side = if seg.Side == "R" then 1 else -1
	local stride = 16
	local gap = 6 + count * stride + 2
	for i = 0, count - 1 do
		local s = if i % 2 == 0 then side else -side
		local z0 = 4 + i * stride
		local wall = wallStyle(ctx, c * CFrame.new(s * 5, 2, -(z0 + stride / 2)), Vector3.new(2, 20, stride + 6))
		wall.Name = "RunWall"
		chevrons(ctx, wall, if s > 0 then Enum.NormalId.Left else Enum.NormalId.Right)
		track(ctx, wall.Position)
	end
	token(ctx, (c * CFrame.new(0, 5, -gap / 2)).Position, 3)
	recovery(ctx, c, gap, -2)
	require_(ctx, "WallRun")
	require_(ctx, "WallJump")
	addPar(ctx, gap / 24 + 14 / M.SprintSpeed)
	return platform(ctx, c * CFrame.new(0, -2, -gap), 14)
end

S.Shaft = function(ctx, c, seg)
	local height = math.clamp(seg[2] or 16, 8, 24)
	local B = ctx.B
	local floor = platform(ctx, c, 12, nil, "Course")
	for _, side in { -1, 1 } do
		local wall = wallStyle(ctx, c * CFrame.new(side * 5, height / 2 + 2, -8), Vector3.new(2, height + 4, 12))
		wall.Name = "ShaftWall"
		B:Text(wall, if side > 0 then Enum.NormalId.Left else Enum.NormalId.Right, "<>", { Color = ctx.Theme.Signal, PixelsPerStud = 6 })
		track(ctx, wall.Position + Vector3.new(0, height / 2, 0))
	end
	block(ctx, floor, 0, height, 14)
	local topC = floor * CFrame.new(0, height, 0)
	signalStrip(ctx, topC * CFrame.new(0, -0.15, 0.05), Vector3.new(ctx.Width, 0.3, 0.12))
	token(ctx, (c * CFrame.new(0, height * 0.6, -7)).Position, 2)
	require_(ctx, "WallJump")
	local kicks = math.max(1, math.ceil((height - Reach.LedgeHeight() + 3) / Reach.ShaftKickRise(8)))
	addPar(ctx, 12 / M.SprintSpeed + 0.4 + kicks * 0.3 + 0.6 + 14 / M.SprintSpeed)
	return platform(ctx, topC, 14, nil, "Course")
end

S.Balance = function(ctx, c, seg)
	local length = seg[2] or 20
	local rise = seg.Rise or 0
	local B, theme = ctx.B, ctx.Theme
	local a = c.Position + Vector3.new(0, -0.5, 0)
	local endC = c * CFrame.new(0, rise, -length)
	local b = endC.Position + Vector3.new(0, -0.5, 0)
	local beam = B:Beam(a, b, 1.3, 1, theme.Beam, theme.BeamMaterial, { Name = "BalanceBeam", Tag = Tags.Balance })
	-- Dashed centre line marks a balance surface.
	local dashes = math.clamp(math.floor(length / 3), 2, 7)
	for i = 1, dashes - 1 do
		local t = i / dashes
		local p = a:Lerp(b, t) + Vector3.new(0, 0.52, 0)
		B:Detail(CFrame.lookAt(p, p + (b - a)), Vector3.new(0.18, 0.04, 1.2), Color3.new(1, 1, 1), Enum.Material.Neon)
	end
	B:Icon(beam, "=", Color3.fromRGB(240, 240, 255), Vector3.new(0, 2, 0))
	track(ctx, a)
	track(ctx, b)
	recovery(ctx, c, length, rise)
	token(ctx, (c * CFrame.new(0, rise / 2 + 2.5, -length / 2)).Position, 1)
	require_(ctx, "Balance")
	addPar(ctx, length / M.BalanceSpeed + 14 / M.SprintSpeed)
	return platform(ctx, endC, 14)
end

S.Zip = function(ctx, c, seg)
	local length = seg[2] or 50
	local drop = seg.Drop or 10
	local B = ctx.B
	local cableHeight = 7.8
	local a = (c * CFrame.new(0, cableHeight, -3)).Position
	local b = (c * CFrame.new(0, cableHeight - drop + 1.5, -length)).Position
	-- Posts at both ends.
	B:Box(c * CFrame.new(1.6, cableHeight / 2 + 0.5, -3), Vector3.new(0.8, cableHeight + 1, 0.8), Color3.fromRGB(80, 80, 90), Enum.Material.Metal)
	local endC = c * CFrame.new(0, -drop, -(length - 6))
	B:Box(endC * CFrame.new(1.6, (cableHeight + 1.5) / 2 + 0.5, -6), Vector3.new(0.8, cableHeight + 2.5, 0.8), Color3.fromRGB(80, 80, 90), Enum.Material.Metal)
	local cable = B:Rod(a, b, 0.25, Color3.fromRGB(40, 40, 45), Enum.Material.Metal, {
		Name = "ZiplineCable",
		CanCollide = false,
		Tag = Tags.Zipline,
		Attrs = { A = a, B = b },
	})
	B:Icon(cable, "~", ctx.Theme.Signal, Vector3.new(0, 1.5, 0))
	-- A step up to reach the cable comfortably.
	B:Box(c * CFrame.new(0, 0.6, -1.5), Vector3.new(4, 1.2, 3), ctx.Theme.Trim, ctx.Theme.SurfaceMaterial, { Name = "ZipStep" })
	track(ctx, a)
	track(ctx, b)
	token(ctx, (a:Lerp(b, 0.55)) - Vector3.new(0, 3.5, 0), 1)
	require_(ctx, "Zipline")
	local avg = math.clamp(M.ZipMinSpeed + drop * 1.2, M.ZipFlatSpeed, M.ZipMaxSpeed * 0.8)
	addPar(ctx, 0.6 + length / avg + 16 / M.SprintSpeed)
	return platform(ctx, endC, 16)
end

S.Rope = function(ctx, c, seg)
	local count = math.clamp(seg[2] or 2, 1, 4)
	local B, theme = ctx.B, ctx.Theme
	local spacing = 15
	local first = 7
	local gap = first + (count - 1) * spacing + 12
	local pivotY = 15
	-- Overhead support beam with end posts.
	B:Box(c * CFrame.new(0, pivotY + 0.6, -gap / 2), Vector3.new(1.2, 1.2, gap + 2), theme.Trim, theme.WallMaterial, { Name = "RopeBeam" })
	for _, z in { -1, -(gap + 1) } do
		B:Box(c * CFrame.new(ctx.Width / 2 - 1, pivotY / 2 - 3, z), Vector3.new(1.2, pivotY + 6, 1.2), theme.Trim, theme.WallMaterial)
	end
	for i = 0, count - 1 do
		local pivot = (c * CFrame.new(0, pivotY, -(first + i * spacing))).Position
		local ropeLength = 11
		local bottom = pivot - Vector3.new(0, ropeLength, 0)
		local rope = B:Rod(pivot, bottom, 0.4, theme.Rope, Enum.Material.Fabric, {
			Name = "SwingRope",
			CanCollide = false,
			Tag = Tags.SwingRope,
			Attrs = { Pivot = pivot, Length = ropeLength },
		})
		B:Ball(bottom, 0.9, theme.Rope, Enum.Material.Fabric, { Decor = true, CanCollide = false, Name = "RopeKnot" })
		B:Icon(rope, "Y", ctx.Theme.Signal, Vector3.new(0, -2, 0))
		token(ctx, bottom + Vector3.new(0, -1, -spacing / 2), 1)
	end
	track(ctx, (c * CFrame.new(0, pivotY + 1, 0)).Position)
	recovery(ctx, c, gap, 0)
	require_(ctx, "RopeSwing")
	addPar(ctx, count * 1.15 + 0.6 + 14 / M.SprintSpeed)
	return platform(ctx, fwd(c, gap), 14)
end

local function anchorPart(ctx: Ctx, position: Vector3, pull: boolean)
	local B = ctx.B
	if ctx.Theme.AnchorMount then
		ctx.Theme.AnchorMount(B, position)
	end
	if pull then
		local part = B:Box(CFrame.new(position) * CFrame.Angles(math.rad(45), 0, math.rad(45)), Vector3.new(2.2, 2.2, 2.2), Color3.fromRGB(255, 150, 50), Enum.Material.Neon, {
			Name = "PullAnchor",
			Tag = Tags.PullAnchor,
			CanCollide = false,
		})
		B:Icon(part, "◆", Color3.fromRGB(255, 170, 70), Vector3.new(0, 2.6, 0))
		B:Light(part, Color3.fromRGB(255, 150, 50), 12, 0.8)
	else
		local part = B:Ball(position, 2.4, Color3.fromRGB(90, 230, 255), Enum.Material.Neon, {
			Name = "GrappleAnchor",
			Tag = Tags.GrappleAnchor,
			CanCollide = false,
		})
		B:Cylinder(CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)), 0.4, 4.2, Color3.fromRGB(220, 250, 255), Enum.Material.Neon, { Decor = true, CanCollide = false })
		B:Icon(part, "◎", Color3.fromRGB(120, 235, 255), Vector3.new(0, 2.8, 0))
		B:Light(part, Color3.fromRGB(90, 230, 255), 12, 0.8)
	end
	track(ctx, position)
end

S.Grapple = function(ctx, c, seg)
	local count = math.clamp(seg[2] or 1, 1, 4)
	local spacing = 30
	local gap = 12 + (count - 1) * spacing + 20
	for i = 0, count - 1 do
		anchorPart(ctx, (c * CFrame.new(0, 19, -(14 + i * spacing))).Position, false)
	end
	token(ctx, (c * CFrame.new(0, 6, -gap * 0.5)).Position, 2)
	recovery(ctx, c, gap, 0)
	require_(ctx, "Grapple")
	addPar(ctx, count * 1.35 + 0.5 + 14 / M.SprintSpeed)
	return platform(ctx, fwd(c, gap), 14)
end

S.Pull = function(ctx, c, seg)
	local height = math.clamp(seg[2] or 16, 12, 26)
	local approach = platform(ctx, c, 10, nil, "Course")
	block(ctx, approach, 0, height, 14)
	local topC = approach * CFrame.new(0, height, 0)
	anchorPart(ctx, (topC * CFrame.new(0, 2.5, -1.5)).Position, true)
	require_(ctx, "GrapplePull")
	addPar(ctx, 10 / M.SprintSpeed + height / M.PullSpeed + 0.7 + 14 / M.SprintSpeed)
	return platform(ctx, topC, 14, nil, "Course")
end

S.DoubleGap = function(ctx, c, seg)
	local fraction = math.clamp(seg[2] or 0.75, 0.3, 0.97)
	local dy = seg.Rise or 0
	local single = Reach.JumpDistance(dy)
	local double = Reach.DoubleJumpDistance(dy)
	local gap = single + 2 + (double - single - 2) * fraction
	token(ctx, (c * CFrame.new(0, Reach.DoubleJumpApex() * 0.75 + math.max(dy, 0) * 0.3, -gap / 2)).Position, 3)
	recovery(ctx, c, gap, dy)
	require_(ctx, "DoubleJump")
	addPar(ctx, gap / M.SprintSpeed + 0.2 + 14 / M.SprintSpeed)
	return platform(ctx, c * CFrame.new(0, dy, -gap), 14)
end

S.DashGap = function(ctx, c, seg)
	local fraction = math.clamp(seg[2] or 0.75, 0.3, 0.97)
	local dy = seg.Rise or 0
	local single = Reach.JumpDistance(dy)
	local dash = Reach.DashJumpDistance(dy)
	local gap = single + 2 + (dash - single - 2) * fraction
	token(ctx, (c * CFrame.new(0, Reach.JumpApex() + 1, -gap / 2)).Position, 3)
	recovery(ctx, c, gap, dy)
	require_(ctx, "Dash")
	addPar(ctx, gap / (M.SprintSpeed + 6) + 0.1 + 14 / M.SprintSpeed)
	return platform(ctx, c * CFrame.new(0, dy, -gap), 14)
end

S.Bounce = function(ctx, c, seg)
	local height = math.clamp(seg[2] or 12, 6, 30)
	local B = ctx.B
	local approach = platform(ctx, c, 10, nil, "Course")
	local padCF = fwd(c, 5) * CFrame.new(0, 0.25, 0)
	local pad = B:Cylinder(padCF * CFrame.Angles(0, 0, math.rad(90)), 0.5, 6, Color3.fromRGB(120, 255, 170), Enum.Material.Neon, {
		Name = "BouncePad",
		Tag = Tags.BouncePad,
		Attrs = { Power = Reach.LaunchSpeedFor(height + 2) },
	})
	B:Icon(pad, "⇈", Color3.fromRGB(150, 255, 190), Vector3.new(0, 2, 0))
	block(ctx, approach, 1, height, 14)
	local topC = approach * CFrame.new(0, height, -1)
	token(ctx, (fwd(c, 5) * CFrame.new(0, height * 0.7, 0)).Position, 2)
	addPar(ctx, 10 / M.SprintSpeed + 0.9 + 14 / M.SprintSpeed)
	return platform(ctx, topC, 14, nil, "Course")
end

S.Vent = function(ctx, c, seg)
	local height = math.clamp(seg[2] or 12, 6, 30)
	local period = seg.Period or 3.4
	local B = ctx.B
	local approach = platform(ctx, c, 10, nil, "Course")
	local ventCF = fwd(c, 5)
	B:Box(ventCF * CFrame.new(0, 0.15, 0), Vector3.new(5, 0.3, 5), Color3.fromRGB(60, 62, 68), Enum.Material.DiamondPlate, { Name = "VentGrate" })
	local zone = B:Box(ventCF * CFrame.new(0, 2.5, 0), Vector3.new(5, 5, 5), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, {
		Name = "LaunchVent",
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		Tag = Tags.LaunchVent,
		Attrs = {
			Power = Reach.LaunchSpeedFor(height + 2),
			Period = period,
			OnFraction = 0.38,
			Phase = (ctx.B:Rand(0, 1)),
			Warn = 0.8,
		},
	})
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, -2.3, 0)
	attachment.Parent = zone
	B:Emitter(attachment, "Steam", Color3.fromRGB(235, 235, 240))
	B:Icon(zone, "⇈", Color3.fromRGB(255, 200, 120), Vector3.new(0, 2, 0))
	block(ctx, approach, 1, height, 14)
	local topC = approach * CFrame.new(0, height, -1)
	addPar(ctx, 10 / M.SprintSpeed + period * 0.4 + 0.9 + 14 / M.SprintSpeed)
	return platform(ctx, topC, 14, nil, "Course")
end

S.Movers = function(ctx, c, seg)
	local count = math.clamp(seg[2] or 1, 1, 3)
	local mode = seg.Mode or "Linear"
	local B = ctx.B
	local cursor = c
	for i = 1, count do
		local phase = (i - 1) * 0.37
		if mode == "Linear" then
			local gap = 26
			local start = cursor * CFrame.new(0, -0.5, -4.5)
			local part = B:Box(start, Vector3.new(8, 1, 8), ctx.Theme.Accent, Enum.Material.DiamondPlate, {
				Name = "MovingPlatform",
				Tag = Tags.Mover,
				Attrs = {
					Kind = "Shuttle",
					Origin = start,
					Offset = (cursor * CFrame.new(0, 0, -(gap - 4.5))).Position - (cursor * CFrame.new(0, 0, -4.5)).Position,
					Period = 6,
					Phase = phase,
					Hold = 0.35,
				},
			})
			B:Icon(part, "↔", ctx.Theme.Signal, Vector3.new(0, 2, 0))
			track(ctx, (cursor * CFrame.new(0, 0, -gap)).Position)
			recovery(ctx, cursor, gap, 0)
			cursor = platform(ctx, fwd(cursor, gap), 9)
			addPar(ctx, 3.2)
		elseif mode == "Pendulum" then
			local gap = 24
			local pivot = (cursor * CFrame.new(0, 16, -gap / 2)).Position
			local rest = cursor * CFrame.new(0, -1, -gap / 2)
			local axis = cursor.RightVector
			B:Box(CFrame.new(pivot), Vector3.new(3, 1, 3), Color3.fromRGB(70, 70, 76), Enum.Material.Metal, { Name = "Pivot" })
			B:Box(CFrame.new((pivot + rest.Position) / 2), Vector3.new(0.4, 16.5, 0.4), Color3.fromRGB(60, 60, 64), Enum.Material.Metal, {
				Name = "SwingChain",
				CanCollide = false,
				Tag = Tags.Mover,
				Attrs = { Kind = "PendulumRod", Pivot = pivot, Axis = axis, Amplitude = math.rad(24), Period = 4.2, Phase = phase, Origin = CFrame.new((pivot + rest.Position) / 2) },
			})
			local cargo = B:Box(rest, Vector3.new(9, 2, 9), Color3.fromRGB(196, 120, 60), Enum.Material.WoodPlanks, {
				Name = "SwingCargo",
				Tag = Tags.Mover,
				Attrs = { Kind = "Pendulum", Pivot = pivot, Axis = axis, Amplitude = math.rad(24), Period = 4.2, Phase = phase, Origin = rest },
			})
			B:Icon(cargo, "≈", ctx.Theme.Signal, Vector3.new(0, 2.5, 0))
			track(ctx, pivot)
			recovery(ctx, cursor, gap, 0)
			cursor = platform(ctx, fwd(cursor, gap), 9)
			addPar(ctx, 2.8)
		elseif mode == "Orbit" then
			local gap = 30
			local center = (cursor * CFrame.new(0, -0.5, -gap / 2)).Position
			for k = 0, 1 do
				local part = B:Box(CFrame.new(center + Vector3.new(9, 0, 0)), Vector3.new(7, 1, 7), ctx.Theme.Accent, Enum.Material.Marble, {
					Name = "OrbitPlatform",
					Tag = Tags.Mover,
					Attrs = { Kind = "Orbit", Center = center, Radius = 10, Period = 9, Phase = phase + k * 0.5, Origin = CFrame.new(center) },
				})
				B:Icon(part, "○", ctx.Theme.Signal, Vector3.new(0, 2, 0))
			end
			local core = B:Ball(center + Vector3.new(0, -4, 0), 3, ctx.Theme.Signal, Enum.Material.Neon, { Decor = true, CanCollide = false })
			B:Light(core, ctx.Theme.Signal, 20, 1)
			track(ctx, center + Vector3.new(14, 0, 14))
			track(ctx, center - Vector3.new(14, 0, 14))
			cursor = platform(ctx, fwd(cursor, gap), 9)
			addPar(ctx, 4)
		else -- Elevator
			local rise = 16
			local start = cursor * CFrame.new(0, -0.5, -5)
			local part = B:Box(start, Vector3.new(8, 1, 8), ctx.Theme.Accent, Enum.Material.DiamondPlate, {
				Name = "Elevator",
				Tag = Tags.Mover,
				Attrs = { Kind = "Shuttle", Origin = start, Offset = Vector3.new(0, rise, 0), Period = 7, Phase = phase, Hold = 0.4 },
			})
			B:Icon(part, "↕", ctx.Theme.Signal, Vector3.new(0, 2, 0))
			-- Guide rails.
			for _, x in { -4.6, 4.6 } do
				B:Detail(cursor * CFrame.new(x, rise / 2, -5), Vector3.new(0.4, rise + 4, 0.4), Color3.fromRGB(90, 90, 96), Enum.Material.Metal)
			end
			local topC = cursor * CFrame.new(0, rise, -9)
			block(ctx, cursor, 9, rise, 12)
			cursor = platform(ctx, topC, 12, nil, "Course")
			addPar(ctx, 4.5)
		end
	end
	return cursor
end

S.Collapse = function(ctx, c, seg)
	local length = seg[2] or 20
	local B = ctx.B
	local plank = 4
	local count = math.max(2, math.floor(length / plank))
	for i = 0, count - 1 do
		local cf = c * CFrame.new(0, -0.6, -(i + 0.5) * plank)
		local part = B:Box(cf, Vector3.new(ctx.Width - 2, 1.2, plank - 0.25), ctx.Theme.Beam, Enum.Material.WoodPlanks, {
			Name = "CollapsePlank",
			Tag = Tags.Collapse,
			Attrs = { Delay = 0.45, Respawn = 3.5, Origin = cf },
		})
		-- Cracks make it read as fragile.
		B:Detail(cf * CFrame.new(B:Rand(-2, 2), 0.61, 0), Vector3.new(0.15, 0.04, plank * 0.8), Color3.fromRGB(40, 30, 25), Enum.Material.SmoothPlastic)
		if i % 3 == 0 then
			B:Icon(part, "!", Color3.fromRGB(255, 190, 90), Vector3.new(0, 2, 0))
		end
		track(ctx, cf.Position)
	end
	recovery(ctx, c, count * plank, 0)
	require_(ctx, "Sprint")
	addPar(ctx, length / M.SprintSpeed + 0.2 + 12 / M.SprintSpeed)
	return platform(ctx, fwd(c, count * plank), 12)
end

S.Retract = function(ctx, c, seg)
	local length = seg[2] or 28
	local B = ctx.B
	local section = 8
	local count = math.max(2, math.floor(length / section))
	for i = 0, count - 1 do
		local side = if i % 2 == 0 then 1 else -1
		local cf = c * CFrame.new(0, -0.6, -(i + 0.5) * section)
		local part = B:Box(cf, Vector3.new(ctx.Width, 1.2, section - 0.3), Color3.fromRGB(120, 125, 135), Enum.Material.DiamondPlate, {
			Name = "RetractBridge",
			Tag = Tags.Timed,
			Attrs = {
				Kind = "Retract",
				Origin = cf,
				Offset = c.RightVector * side * (ctx.Width + 1),
				Period = 5,
				OnFraction = 0.6,
				Phase = i * 0.09,
				Warn = 0.8,
			},
		})
		-- Housing the bridge slides into, with warning lamps.
		local housing = B:Box(c * CFrame.new(side * (ctx.Width + 1.5), -0.6, -(i + 0.5) * section), Vector3.new(ctx.Width, 2.4, section), Color3.fromRGB(70, 72, 80), Enum.Material.Metal)
		local lamp = B:Detail(housing.CFrame * CFrame.new(-side * (ctx.Width / 2), 1.4, 0), Vector3.new(0.6, 0.6, 0.6), Color3.fromRGB(255, 170, 40), Enum.Material.Neon, {
			Tag = Tags.Timed,
			Attrs = { Kind = "Lamp", Period = 5, OnFraction = 0.6, Phase = i * 0.09, Warn = 0.8 },
		})
		lamp.Name = "WarnLamp"
		B:Icon(part, "⇄", Color3.fromRGB(255, 190, 90), Vector3.new(0, 2, 0))
		track(ctx, housing.Position)
	end
	recovery(ctx, c, count * section, 0)
	addPar(ctx, length / M.SprintSpeed + 1.5 + 12 / M.SprintSpeed)
	return platform(ctx, fwd(c, count * section), 12)
end

S.Spinner = function(ctx, c, seg)
	local mode = seg.Mode or "Platform"
	local B = ctx.B
	if mode == "Platform" then
		local gap = 32
		local center = c * CFrame.new(0, -0.6, -gap / 2)
		local hub = B:Column((center * CFrame.new(0, -12, 0)).Position, 11.4, 3, Color3.fromRGB(80, 82, 90), Enum.Material.Metal)
		hub.Name = "SpinnerHub"
		local bar = B:Box(center, Vector3.new(4, 1.2, 30), ctx.Theme.Accent, Enum.Material.DiamondPlate, {
			Name = "SpinnerBeam",
			Tag = Tags.Mover,
			Attrs = { Kind = "Spin", Origin = center, Speed = 34 },
		})
		B:Icon(bar, "⟳", ctx.Theme.Signal, Vector3.new(0, 2, 0))
		track(ctx, center.Position + Vector3.new(16, 0, 16))
		track(ctx, center.Position - Vector3.new(16, 0, 16))
		recovery(ctx, c, gap, 0)
		addPar(ctx, 3.5)
		return platform(ctx, fwd(c, gap), 12)
	end
	-- Sweeper: a round floor with a rotating bar to jump over.
	local radius = 13
	local center = c * CFrame.new(0, 0, -radius - 1)
	B:Cylinder(center * CFrame.new(0, -1, 0) * CFrame.Angles(0, 0, math.rad(90)), 2, radius * 2, ctx.Theme.Surface, ctx.Theme.SurfaceMaterial, { Name = "SweeperFloor" })
	local sweeper = B:Box(center * CFrame.new(0, 1.3, 0), Vector3.new(1.2, 1.4, radius * 2 - 1), Color3.fromRGB(240, 80, 60), Enum.Material.Neon, {
		Name = "Sweeper",
		CanCollide = false,
		Tag = Tags.Mover,
		Attrs = { Kind = "Spin", Origin = center * CFrame.new(0, 1.3, 0), Speed = 75, Sweeper = true },
	})
	B:Icon(sweeper, "⚠", Color3.fromRGB(255, 120, 90), Vector3.new(0, 2, 0))
	B:Column((center * CFrame.new(0, 0, 0)).Position, 2.2, 1.6, Color3.fromRGB(70, 70, 76), Enum.Material.Metal)
	track(ctx, center.Position + Vector3.new(radius, 0, radius))
	track(ctx, center.Position - Vector3.new(radius, 0, radius))
	addPar(ctx, radius * 2 / M.SprintSpeed + 0.8)
	return platform(ctx, fwd(c, radius * 2 + 2), 12)
end

S.Doors = function(ctx, c, seg)
	local count = math.clamp(seg[2] or 2, 1, 4)
	local B, theme = ctx.B, ctx.Theme
	local spacing = 11
	local length = 8 + count * spacing
	local after = platform(ctx, c, length, nil, "Course")
	local center = fwd(c, length / 2)
	for _, side in { -1, 1 } do
		B:Box(center * CFrame.new(side * (ctx.Width / 2 + 0.6), 5, 0), Vector3.new(1.2, 10, length), theme.Wall, theme.WallMaterial)
	end
	B:Box(center * CFrame.new(0, 10.6, 0), Vector3.new(ctx.Width + 2.4, 1.2, length), theme.Wall, theme.WallMaterial)
	for i = 1, count do
		local z = 6 + (i - 1) * spacing
		local closed = c * CFrame.new(0, 4.6, -z)
		local phase = -(i - 1) * 0.16
		local door = B:Box(closed, Vector3.new(ctx.Width, 9.2, 1.2), Color3.fromRGB(150, 60, 50), Enum.Material.DiamondPlate, {
			Name = "TimedDoor",
			Tag = Tags.Timed,
			Attrs = { Kind = "Door", Origin = closed, Offset = Vector3.new(0, 9, 0), Period = 4.4, OnFraction = 0.5, Phase = phase, Warn = 0.7 },
		})
		B:Icon(door, "▮", Color3.fromRGB(255, 150, 120), Vector3.new(0, 5.4, 0))
		local lamp = B:Detail(c * CFrame.new(0, 10, -(z - 0.8)), Vector3.new(2, 0.5, 0.3), Color3.fromRGB(80, 255, 120), Enum.Material.Neon, {
			Tag = Tags.Timed,
			Attrs = { Kind = "Lamp", Period = 4.4, OnFraction = 0.5, Phase = phase, Warn = 0.7, Traffic = true },
		})
		lamp.Name = "DoorLamp"
	end
	addPar(ctx, length / M.SprintSpeed + 1.6)
	return after
end

S.Switch = function(ctx, c, seg)
	local B = ctx.B
	local length = 26
	local id = ("%s_switch_%d"):format(ctx.Id, B:RandInt(1000, 9999))
	local after = platform(ctx, c, length, nil, "Course")
	local plateCF = c * CFrame.new(0, 0.15, -4)
	local plate = B:Box(plateCF, Vector3.new(5, 0.3, 5), Color3.fromRGB(80, 200, 255), Enum.Material.Neon, {
		Name = "PressurePlate",
		Tag = Tags.Switch,
		Attrs = { SwitchId = id, Duration = seg.Duration or 5.5 },
	})
	B:Icon(plate, "⊙", Color3.fromRGB(120, 220, 255), Vector3.new(0, 2, 0))
	B:Box(c * CFrame.new(0, 1, -12), Vector3.new(ctx.Width, 2.4, 1.4), ctx.Theme.Trim, ctx.Theme.WallMaterial, { Name = "VaultWall" })
	local gateCF = c * CFrame.new(0, 5, -(length - 1))
	local gate = B:Box(gateCF, Vector3.new(ctx.Width, 10, 1), Color3.fromRGB(80, 200, 255), Enum.Material.ForceField, {
		Name = "SwitchGate",
		Tag = Tags.SwitchGate,
		Attrs = { SwitchId = id, Origin = gateCF, Offset = Vector3.new(0, -10.5, 0) },
	})
	B:Text(gate, Enum.NormalId.Back, "STEP ON THE PLATE", { Color = Color3.new(1, 1, 1), PixelsPerStud = 8 })
	for _, side in { -1, 1 } do
		B:Box(c * CFrame.new(side * (ctx.Width / 2 + 0.5), 5, -(length - 1)), Vector3.new(1, 10, 1.4), ctx.Theme.Wall, ctx.Theme.WallMaterial)
	end
	addPar(ctx, length / M.SprintSpeed + 0.4)
	return after
end

S.Lasers = function(ctx, c, seg)
	local count = math.clamp(seg[2] or 3, 1, 5)
	local pattern = seg.Pattern or "Alternate"
	local B = ctx.B
	local spacing = 8
	local length = 8 + count * spacing
	local after = platform(ctx, c, length, nil, "Course")
	local red = Color3.fromRGB(255, 50, 70)
	for i = 1, count do
		local z = 5 + (i - 1) * spacing
		for _, side in { -1, 1 } do
			B:Box(c * CFrame.new(side * (ctx.Width / 2 + 0.4), 3.5, -z), Vector3.new(0.8, 7, 0.8), Color3.fromRGB(40, 40, 46), Enum.Material.Metal, { Name = "LaserPost" })
		end
		local function beam(y: number, attrs: { [string]: any }?)
			local cf = c * CFrame.new(0, y, -z)
			local options = {
				Name = "Laser",
				CanCollide = false,
				CanQuery = false,
				CastShadow = false,
				Tag = Tags.Hazard,
				Attrs = attrs,
			}
			local part = B:Box(cf, Vector3.new(ctx.Width, 0.3, 0.3), red, Enum.Material.Neon, options)
			part.CanTouch = true
			if attrs then
				B:Tag(part, Tags.Timed)
			end
			B:Icon(part, "⚠", Color3.fromRGB(255, 120, 120), Vector3.new(0, 1.2, 0), 26)
			return part
		end
		if pattern == "Sweep" then
			local cf = c * CFrame.new(0, 0.9, -z)
			beam(0.9, { Kind = "LaserSweep", Origin = cf, Offset = Vector3.new(0, 4.6, 0), Period = 3.2, Phase = i * 0.21 })
		elseif pattern == "Grid" then
			-- Fixed: low beams to jump, high beams to slide under.
			if i % 2 == 1 then
				beam(0.9, nil)
			else
				beam(3.4, nil)
				B:Box(c * CFrame.new(0, 7, -z), Vector3.new(ctx.Width, 6, 0.6), ctx.Theme.Wall, ctx.Theme.WallMaterial)
			end
		else -- Alternate
			beam(1.2, { Kind = "Laser", Period = 2.6, OnFraction = 0.5, Phase = (i % 2) * 0.5, Warn = 0.45 })
			beam(3.2, { Kind = "Laser", Period = 2.6, OnFraction = 0.5, Phase = (i % 2) * 0.5, Warn = 0.45 })
		end
	end
	addPar(ctx, length / M.SprintSpeed + count * 0.35)
	return after
end

S.Water = function(ctx, c, seg)
	ctx.Water = { StartCP = #ctx.Checkpoints, Rate = seg.Rate or 1.8 }
	return c
end

S.Conveyor = function(ctx, c, seg)
	local length = seg[2] or 30
	local dir = seg.Dir or 1
	local speed = 14
	local B = ctx.B
	local center = c * CFrame.new(0, -0.6, -length / 2)
	local belt = B:Box(center, Vector3.new(ctx.Width - 1, 1.2, length), Color3.fromRGB(45, 46, 50), Enum.Material.Rubber, {
		Name = "Conveyor",
		Tag = Tags.Conveyor,
		Attrs = { Speed = speed * dir },
	})
	belt.AssemblyLinearVelocity = c.LookVector * speed * dir
	B:Text(belt, Enum.NormalId.Top, if dir > 0 then "▲  ▲  ▲  ▲" else "▼  ▼  ▼  ▼", { Color = Color3.fromRGB(240, 196, 40), PixelsPerStud = 4 })
	for _, z in { 0, length } do
		B:Cylinder(c * CFrame.new(0, -0.6, -z), ctx.Width - 1, 1.4, Color3.fromRGB(90, 90, 96), Enum.Material.Metal, { Decor = true })
	end
	for _, side in { -1, 1 } do
		B:Box(center * CFrame.new(side * (ctx.Width / 2), 0.2, 0), Vector3.new(1, 1.6, length), Color3.fromRGB(240, 180, 40), Enum.Material.Metal)
	end
	track(ctx, center.Position)
	addPar(ctx, length / math.max(M.SprintSpeed + speed * dir * 0.7, 10) + 12 / M.SprintSpeed)
	return platform(ctx, fwd(c, length), 12)
end

S.Wind = function(ctx, c, seg)
	local length = seg[2] or 30
	local B = ctx.B
	local side = if B:Rand(0, 1) > 0.5 then 1 else -1
	local width = 6
	local after = platform(ctx, c, length, width, "Course")
	local zone = B:Box(fwd(c, length / 2) * CFrame.new(0, 6, 0), Vector3.new(width + 14, 14, length), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, {
		Name = "WindZone",
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		Tag = Tags.WindZone,
		Attrs = { Force = c.RightVector * side * 70, Period = 4.2, OnFraction = 0.42, Phase = B:Rand(0, 1), Warn = 0.9 },
	})
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(-side * (width / 2 + 6), 0, 0)
	attachment.Parent = zone
	local streams = B:Emitter(attachment, "Mist", Color3.fromRGB(240, 248, 255))
	streams.Name = "GustStreams"
	B:Icon(zone, if side > 0 then "→" else "←", Color3.fromRGB(220, 235, 255), Vector3.new(0, 0, 0))
	addPar(ctx, length / M.WalkSpeed + 0.8)
	return after
end

S.Ice = function(ctx, c, seg)
	local length = seg[2] or 30
	local slope = seg.Slope or 0
	local B = ctx.B
	local a = c.Position
	local endC = c * CFrame.new(0, -slope, -length)
	local mid = (a + endC.Position) / 2
	local look = CFrame.lookAt(mid, endC.Position)
	B:Box(look * CFrame.new(0, -1, 0), Vector3.new(ctx.Width, 2, (endC.Position - a).Magnitude + 0.5), Color3.fromRGB(170, 215, 240), Enum.Material.Ice, {
		Name = "IceSlope",
		Tag = Tags.Ice,
	})
	track(ctx, a)
	track(ctx, endC.Position)
	addPar(ctx, length / (M.SprintSpeed + 6) + 12 / M.SprintSpeed)
	return platform(ctx, endC, 12)
end

S.LowGrav = function(ctx, c, seg)
	local length = seg[2] or 50
	local B, theme = ctx.B, ctx.Theme
	local scale = 0.42
	-- Gaps sized for reduced gravity.
	local stats = table.clone(MovementConfig) :: any
	stats.Gravity *= scale
	local hop = Reach.JumpDistance(0, M.SprintSpeed, stats) * 0.62
	local zoneCenter = fwd(c, length / 2 + 4)
	local zone = B:Box(zoneCenter * CFrame.new(0, 10, 0), Vector3.new(ctx.Width + 12, 30, length + 10), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, {
		Name = "GravityZone",
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		Tag = Tags.GravityZone,
		Attrs = { Scale = scale },
	})
	local attachment = Instance.new("Attachment")
	attachment.Parent = zone
	B:Emitter(attachment, "Motes", theme.Signal)
	-- Glass chamber walls.
	for _, side in { -1, 1 } do
		B:Box(zoneCenter * CFrame.new(side * (ctx.Width / 2 + 6), 10, 0), Vector3.new(1, 30, length + 10), theme.Signal, Enum.Material.Glass, { Transparency = 0.7 })
	end
	local cursor = c
	local travelled = 0
	local index = 0
	while travelled < length - 4 do
		index += 1
		local dy = if index % 2 == 0 then 3 else -2
		cursor = platform(ctx, cursor * CFrame.new(0, dy, -hop), 6, 8, "Floating")
		travelled += hop + 6
		token(ctx, (cursor * CFrame.new(0, 6, hop / 2)).Position, 1)
	end
	addPar(ctx, travelled / (M.SprintSpeed * 0.75))
	return platform(ctx, cursor, 12, nil, "Course")
end

S.Current = function(ctx, c, seg)
	local height = math.clamp(seg[2] or 18, 8, 40)
	local B = ctx.B
	local approach = platform(ctx, c, 8, nil, "Course")
	local column = fwd(c, 13) * CFrame.new(0, height / 2 + 3, 0)
	local zone = B:Box(column, Vector3.new(8, height + 10, 8), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, {
		Name = "AetherCurrent",
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		Tag = Tags.GravityZone,
		Attrs = { Scale = 1, Lift = M.Gravity * 1.45, MaxRise = 34 },
	})
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, -(height + 10) / 2, 0)
	attachment.Parent = zone
	B:Emitter(attachment, "Updraft", ctx.Theme.Signal)
	B:Cylinder(fwd(c, 13) * CFrame.new(0, -0.2, 0) * CFrame.Angles(0, 0, math.rad(90)), 0.4, 8, ctx.Theme.Signal, Enum.Material.Neon, { Decor = true })
	B:Icon(zone, "⇧", ctx.Theme.Signal, Vector3.new(0, -height / 2, 0))
	block(ctx, approach, 10, height, 14)
	local topC = approach * CFrame.new(0, height, -10)
	track(ctx, column.Position + Vector3.new(0, height / 2, 0))
	addPar(ctx, 8 / M.SprintSpeed + height / 30 + 1 + 14 / M.SprintSpeed)
	return platform(ctx, topC, 14, nil, "Course")
end

S.Holo = function(ctx, c, seg)
	local count = math.clamp(seg[2] or 3, 1, 6)
	local B = ctx.B
	local cursor = c
	for i = 1, count do
		local gap = math.max(Reach.JumpDistance(0) * 0.5, 5)
		local cf = cursor * CFrame.new(0, -0.5, -(gap + 3.5))
		local holo = B:Box(cf, Vector3.new(7, 1, 7), ctx.Theme.Signal, Enum.Material.ForceField, {
			Name = "HoloPlatform",
			Tag = Tags.Timed,
			Attrs = { Kind = "Blink", Period = 3.8, OnFraction = 0.62, Phase = -(i - 1) * 0.2, Warn = 0.8 },
		})
		B:Icon(holo, "◇", ctx.Theme.Signal, Vector3.new(0, 2, 0))
		local base = B:Detail(cf * CFrame.new(0, -0.7, 0), Vector3.new(7.2, 0.3, 7.2), Color3.fromRGB(40, 44, 60), Enum.Material.Metal, { CanCollide = false })
		base.Transparency = 0.6
		cursor = fwd(cursor, gap + 7)
		track(ctx, cf.Position)
		addPar(ctx, 1.1)
	end
	local gap = math.max(Reach.JumpDistance(0) * 0.5, 5)
	recovery(ctx, c, (cursor.Position - c.Position).Magnitude + gap, 0)
	addPar(ctx, 12 / M.SprintSpeed)
	return platform(ctx, fwd(cursor, gap), 12)
end

S.Turn = function(ctx, c, seg)
	local degrees = seg[2] or 90
	local size = ctx.Width + 4
	platform(ctx, c, size, size, "Course")
	local center = fwd(c, size / 2)
	local turned = center * CFrame.Angles(0, math.rad(-degrees), 0)
	addPar(ctx, 0.5)
	return fwd(turned, size / 2)
end

-- Checkpoints and finish -----------------------------------------------------------------------

local function finishWater(ctx: Ctx)
	local water = ctx.Water
	if not water then
		return
	end
	ctx.Water = nil
	local min, max = ctx.SectionMin, ctx.SectionMax
	local baseY = min.Y - 8
	local size = Vector3.new(max.X - min.X + 40, (max.Y - baseY) + 16, max.Z - min.Z + 20)
	local localCenter = Vector3.new((min.X + max.X) / 2, baseY - size.Y / 2, (min.Z + max.Z) / 2)
	local cf = ctx.Origin * CFrame.new(localCenter)
	local part = ctx.B:Box(cf, size, Color3.fromRGB(70, 160, 200), Enum.Material.Glass, {
		Name = "RisingWater",
		Transparency = 0.35,
		CanCollide = false,
		CanQuery = false,
		Tag = Tags.Water,
		Attrs = {
			CourseId = ctx.Id,
			StartCP = water.StartCP,
			Rate = water.Rate,
			BaseY = baseY,
			MaxY = max.Y + 1,
			Origin = cf,
		},
	})
	part.CanTouch = true
	ctx.B:Tag(part, Tags.Hazard, { Active = false })
end

local function gateArch(ctx: Ctx, c: CFrame, color: Color3, label: string, checkered: boolean?)
	local B = ctx.B
	local w = ctx.Width
	for _, side in { -1, 1 } do
		B:Box(c * CFrame.new(side * (w / 2 + 0.4), 4.5, 0), Vector3.new(0.8, 9, 0.8), ctx.Theme.Trim, Enum.Material.Metal)
	end
	local top = B:Box(c * CFrame.new(0, 9.3, 0), Vector3.new(w + 1.6, 1.2, 0.8), color, Enum.Material.Neon)
	if checkered then
		for i = 0, 7 do
			B:Detail(c * CFrame.new(-w / 2 + (i + 0.5) * (w / 8), 10.3, 0), Vector3.new(w / 8, 0.8, 0.85), if i % 2 == 0 then Color3.new(0.05, 0.05, 0.05) else Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
		end
	end
	local sign = B:Detail(c * CFrame.new(0, 11.4, 0), Vector3.new(w * 0.7, 1.4, 0.2), Color3.fromRGB(25, 28, 36), Enum.Material.SmoothPlastic)
	B:Text(sign, Enum.NormalId.Back, label, { Color = color })
	B:Text(sign, Enum.NormalId.Front, label, { Color = color })
	B:Light(top, color, 14, 0.7)
end

S.CP = function(ctx, c, seg)
	finishWater(ctx)
	local length = 12
	local after = platform(ctx, c, length, nil, "Checkpoint")
	local index = #ctx.Checkpoints + 1
	local center = fwd(c, length / 2)
	local volumeCF = center * CFrame.new(0, 5, 0)
	local volumeSize = Vector3.new(ctx.Width + 4, 12, length)
	ctx.B:Volume(volumeCF, volumeSize, Tags.CourseCheckpoint, { CourseId = ctx.Id, Index = index })
	local exchange = seg.Exchange == true
	gateArch(ctx, fwd(c, 2), if exchange then Color3.fromRGB(255, 120, 220) else ctx.Theme.Signal, if exchange then "EXCHANGE" else ("CHECKPOINT %d"):format(index))
	local pad = ctx.B:Detail(center * CFrame.new(0, 0.05, 0), Vector3.new(ctx.Width - 2, 0.1, 6), ctx.Theme.Signal, Enum.Material.Neon)
	pad.Transparency = 0.4
	table.insert(ctx.Checkpoints, {
		Spawn = center * CFrame.new(0, 3.5, 0),
		Volume = { CFrame = volumeCF, Size = volumeSize },
		Exchange = exchange,
	})
	-- Each section between checkpoints tracks its own bounds (for rising water).
	ctx.SectionMin = ctx.Origin:PointToObjectSpace(center.Position)
	ctx.SectionMax = ctx.SectionMin
	addPar(ctx, length / M.SprintSpeed)
	return after
end

S.Finish = function(ctx, c, seg)
	finishWater(ctx)
	local length = 16
	local after = platform(ctx, c, length, ctx.Width + 6, "Finish")
	gateArch(ctx, fwd(c, 3), Color3.fromRGB(255, 255, 255), "FINISH", true)
	addPar(ctx, 3 / M.SprintSpeed)
	return after
end

-- Splits ------------------------------------------------------------------------------------------

local LANES = { A = -1, F = 0, E = 1 }

S.Split = function(ctx, c, seg)
	local B = ctx.B
	local lanes = {}
	for name in LANES do
		if seg[name] then
			table.insert(lanes, name)
		end
	end
	table.sort(lanes, function(x, y)
		return LANES[x] < LANES[y]
	end)
	-- Fork platform spanning every lane, with route signs.
	local span = LANE_SPACING * 2 + ctx.Width
	local fork = platform(ctx, c, 10, span, "Course")
	local parBefore = { A = ctx.Par.A, F = ctx.Par.F, E = ctx.Par.E }
	local ends: { [string]: CFrame } = {}
	local laneParA, laneParF, laneParE = 0, 0, 0
	for _, name in lanes do
		local sign = LANES[name]
		local laneStart = fwd(fork, 0) * CFrame.new(sign * LANE_SPACING, 0, 0)
		-- Route marker at the start of each lane.
		local post = B:Detail(laneStart * CFrame.new(ctx.Width / 2 - 0.6, 2.5, 1.5), Vector3.new(0.4, 5, 0.4), ctx.Theme.Trim, Enum.Material.Metal)
		local plate = B:Detail(post.CFrame * CFrame.new(-1.6, 2.6, 0), Vector3.new(3.2, 1.6, 0.15), Color3.fromRGB(25, 28, 36), Enum.Material.SmoothPlastic)
		local label = if name == "A" then "● STEADY" elseif name == "F" then "▲ FAST" else "★ EXPERT"
		B:Text(plate, Enum.NormalId.Back, label, { Color = if name == "E" then Color3.fromRGB(255, 210, 90) elseif name == "F" then Color3.fromRGB(120, 220, 255) else Color3.fromRGB(150, 255, 160) })
		-- Bridge from fork to lane start for side lanes.
		ctx.Lane = name
		ctx.LaneSign = sign
		local startPar = ctx.Par[name]
		local cursor = laneStart
		for index, sub in seg[name] do
			local builder = S[sub[1]]
			if builder then
				cursor = builder(ctx, cursor, sub)
			else
				warn("[CourseBuilder] Unknown segment " .. tostring(sub[1]) .. " in " .. ctx.Id)
			end
			if name == "E" and index == 1 then
				-- The expert shortcut: passing through here earns the distinction.
				local volumeCF = cursor * CFrame.new(0, 5, 3)
				local size = Vector3.new(ctx.Width + 4, 14, 8)
				B:Volume(volumeCF, size, Tags.CourseShortcut, { CourseId = ctx.Id })
				table.insert(ctx.Shortcuts, { CFrame = volumeCF, Size = size })
			end
		end
		ends[name] = cursor
		local spent = ctx.Par[name] - startPar
		if name == "A" then
			laneParA = spent
		elseif name == "F" then
			laneParF = spent
		else
			laneParE = spent
		end
	end
	ctx.Lane = nil
	ctx.LaneSign = 0

	-- Merge: bring every lane level and to the same forward distance.
	local maxForward, maxY = -math.huge, -math.huge
	local minLateral, maxLateral = math.huge, -math.huge
	for _, cursor in ends do
		local p = fork:PointToObjectSpace(cursor.Position)
		maxForward = math.max(maxForward, -p.Z)
		maxY = math.max(maxY, p.Y)
		minLateral = math.min(minLateral, p.X)
		maxLateral = math.max(maxLateral, p.X)
	end
	for name, cursor in ends do
		local p = fork:PointToObjectSpace(cursor.Position)
		local lift = maxY - p.Y
		local extraPar = 0
		ctx.Lane = name
		if lift > 0.5 then
			if lift <= 4 then
				cursor = S.Steps(ctx, cursor, { "Steps", 1, Rise = lift })
			elseif lift <= Reach.LedgeHeight() - 1.5 then
				cursor = S.Ledge(ctx, cursor, { "Ledge", lift })
			else
				cursor = S.Climb(ctx, cursor, { "Climb", lift, Type = "Ladder" })
			end
			extraPar += 1.5
		end
		ctx.Lane = nil
		p = fork:PointToObjectSpace(cursor.Position)
		local remaining = maxForward - (-p.Z)
		if remaining > 0.5 then
			cursor = platform(ctx, cursor, remaining)
			extraPar += remaining / M.SprintSpeed
		end
		if name == "A" then
			laneParA += extraPar
		elseif name == "F" then
			laneParF += extraPar
		else
			laneParE += extraPar
		end
	end
	-- Lanes that a split doesn't define fall back to the nearest one.
	if not seg.A then
		laneParA = if seg.F then laneParF else laneParE
	end
	if not seg.F then
		laneParF = if seg.A then laneParA else laneParE
	end
	if not seg.E then
		laneParE = laneParF
	end
	ctx.Par.A = parBefore.A + laneParA
	ctx.Par.F = parBefore.F + laneParF
	ctx.Par.E = parBefore.E + laneParE
	-- Lanes with no requirements of their own inherit the accessible route's.
	local mergeStart = fork * CFrame.new((minLateral + maxLateral) / 2, maxY, -maxForward)
	local mergeWidth = (maxLateral - minLateral) + ctx.Width
	local merged = platform(ctx, mergeStart, 12, mergeWidth, "Course")
	addPar(ctx, 12 / M.SprintSpeed)
	-- Recentre on the main line.
	local centre = fork:PointToObjectSpace(merged.Position)
	return merged * CFrame.new(-centre.X, 0, 0)
end

-- Build -------------------------------------------------------------------------------------------

local function newContext(B: Kit.Builder, theme: Theme, id: string, difficulty: number, width: number, origin: CFrame, folder: Folder): Ctx
	return {
		B = B,
		Theme = theme,
		Id = id,
		Difficulty = difficulty,
		Width = width,
		Origin = origin,
		Folder = folder,
		Lane = nil,
		LaneSign = 0,
		Par = { A = 0, F = 0, E = 0 },
		Requires = { A = {}, F = {}, E = {} },
		TokenSpots = {},
		Checkpoints = {},
		Shortcuts = {},
		Water = nil,
		SectionMin = Vector3.zero,
		SectionMax = Vector3.zero,
		Techniques = 0,
		MinY = origin.Y,
		Safe = difficulty <= 4,
	}
end

function CourseBuilder.NewContext(B: Kit.Builder, theme: Theme, id: string, difficulty: number, origin: CFrame, folder: Folder)
	return newContext(B, theme, id, difficulty, 10, origin, folder)
end

-- Run a list of segments from a cursor (used by the tower and endless modes too).
function CourseBuilder.Segments(ctx: Ctx, cursor: CFrame, segments: { any }): CFrame
	for _, seg in segments do
		local builder = S[seg[1]]
		if builder then
			cursor = builder(ctx, cursor, seg)
		else
			warn("[CourseBuilder] Unknown segment " .. tostring(seg[1]) .. " in " .. ctx.Id)
		end
	end
	return cursor
end

function CourseBuilder.Has(kind: string): boolean
	return S[kind] ~= nil
end

local function sortedKeys(set: { [string]: boolean }): { string }
	local list = {}
	for key in set do
		table.insert(list, key)
	end
	table.sort(list)
	return list
end

-- Choose tokens spread through the course, favouring harder spots. Only the
-- shared path and expert lanes hold tokens, so a single run can collect them all.
local function pickTokens(all: { { Position: Vector3, Priority: number, Lane: string? } }, wanted: number): { Vector3 }
	local spots = {}
	for _, spot in all do
		if spot.Lane == nil or spot.Lane == "E" then
			table.insert(spots, spot)
		end
	end
	local result = {}
	if #spots == 0 then
		return result
	end
	wanted = math.min(wanted, #spots)
	local chosen = {}
	local count = 0
	-- Always include one expert-lane spot if any exist.
	for index, spot in spots do
		if spot.Lane == "E" then
			chosen[index] = true
			count += 1
			break
		end
	end
	-- Evenly spaced picks, each nudged to the best spot nearby.
	local step = #spots / math.max(wanted, 1)
	local cursor = step / 2
	while count < wanted and cursor <= #spots + 0.5 do
		local index = math.clamp(math.floor(cursor + 0.5), 1, #spots)
		local best = index
		for j = math.max(1, index - 1), math.min(#spots, index + 1) do
			if not chosen[j] and (chosen[best] or spots[j].Priority > spots[best].Priority) then
				best = j
			end
		end
		if not chosen[best] then
			chosen[best] = true
			count += 1
		end
		cursor += step
	end
	-- Top up with the highest-priority leftovers.
	if count < wanted then
		local rest = {}
		for index in spots do
			if not chosen[index] then
				table.insert(rest, index)
			end
		end
		table.sort(rest, function(a, b)
			return spots[a].Priority > spots[b].Priority
		end)
		for _, index in rest do
			if count >= wanted then
				break
			end
			chosen[index] = true
			count += 1
		end
	end
	for index, spot in spots do
		if chosen[index] then
			table.insert(result, spot.Position)
		end
	end
	return result
end

-- Build a full course. `origin` is the top-surface point at the start, facing along the course.
function CourseBuilder.Build(B: Kit.Builder, course: any, theme: Theme, origin: CFrame, parent: Instance?): Meta
	local folder = B:Group(course.Id, parent)
	local meta: Meta
	B:Within(folder, function()
		local ctx = newContext(B, theme, course.Id, course.Difficulty, course.Width or 10, origin, folder)
		-- Start platform with gate and spawn pad.
		local cursor = platform(ctx, origin, 18, ctx.Width + 4, "Start")
		local spawn = origin * CFrame.new(0, 3.5, -10)
		gateArch(ctx, origin * CFrame.new(0, 0, -4), theme.Signal, string.upper(course.Name))
		local startPad = B:Box(origin * CFrame.new(0, 0.1, -10), Vector3.new(6, 0.2, 6), theme.Signal, Enum.Material.Neon, {
			Name = "StartPad",
			CanCollide = false,
			Tag = Tags.CourseStart,
			Attrs = { CourseId = course.Id, Spawn = spawn },
		})
		startPad.Transparency = 0.3
		addPar(ctx, -0.3) -- countdown starts you on the pad

		cursor = CourseBuilder.Segments(ctx, cursor, course.Segments)

		-- The finish volume is the last platform built by the Finish segment.
		local finishCF = cursor * CFrame.new(0, 5, 8)
		local finishSize = Vector3.new(ctx.Width + 8, 12, 14)
		B:Volume(finishCF, finishSize, Tags.CourseFinish, { CourseId = course.Id })

		-- Tokens.
		local tokenCount = math.clamp(4 + math.floor(#ctx.TokenSpots / 4), 5, 8)
		local tokens = pickTokens(ctx.TokenSpots, tokenCount)
		for index, position in tokens do
			local coin = B:Cylinder(CFrame.new(position) * CFrame.Angles(0, 0, 0), 0.3, 2.2, Color3.fromRGB(255, 205, 70), Enum.Material.Neon, {
				Name = "Token",
				CanCollide = false,
				CanQuery = false,
				Tag = Tags.CourseToken,
				Attrs = { CourseId = course.Id, Index = index },
			})
			coin.CastShadow = false
		end

		-- Bounds in course space (for rooms and kill height).
		local min, max = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
		for _, part in folder:GetDescendants() do
			if part:IsA("BasePart") and part.Transparency < 1 then
				local p = origin:PointToObjectSpace(part.Position)
				local half = part.Size.Magnitude / 2
				min = min:Min(p - Vector3.new(half, half, half))
				max = max:Max(p + Vector3.new(half, half, half))
			end
		end

		local par = { A = math.max(ctx.Par.A, 5), F = math.max(ctx.Par.F, 5), E = math.max(ctx.Par.E, 5) }
		local medals = course.Medals or Medals.FromPar(par.A, par.F, par.E)
		local exchanges = {}
		for index, checkpoint in ctx.Checkpoints do
			if checkpoint.Exchange then
				table.insert(exchanges, index)
			end
		end
		local length = (origin:PointToObjectSpace(cursor.Position)).Magnitude
		meta = {
			Id = course.Id,
			Spawn = spawn,
			Checkpoints = ctx.Checkpoints,
			Finish = { CFrame = finishCF, Size = finishSize },
			Tokens = tokens,
			Shortcuts = ctx.Shortcuts,
			KillY = ctx.MinY - 22,
			Par = par,
			Medals = medals,
			Requires = sortedKeys(ctx.Requires.A),
			FastRequires = sortedKeys(ctx.Requires.F),
			ExpertRequires = sortedKeys(ctx.Requires.E),
			Length = length,
			Folder = folder,
			LocalMin = min,
			LocalMax = max,
			Origin = origin,
			FlowTarget = math.floor((ctx.Techniques * 16 + par.F * 12) * 1.15),
			Exchanges = exchanges,
		}
	end)
	return meta
end

return CourseBuilder

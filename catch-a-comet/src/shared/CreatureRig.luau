-- Builds celestial creature models from parts. Used by the server for
-- sanctuary displays (visible to everyone) and by the client for previews
-- and reveals.
--
-- Every model shares one structure:
--   Model "Creature"  (attributes: SpeciesId, Mutation, Height, Radius, Idle)
--   ├─ Root   invisible anchored part at the creature's feet, facing -Z
--   └─ parts  welded (Weld "RigWeld") to Root or to an invisible pivot part
--
-- Secondary motion is data: a part (or pivot) with a `Motion` attribute is
-- animated by the client's CreatureAnimator by changing its RigWeld.C0.
--   Spin  (MotionAxis, MotionSpeed rad/s)
--   Flap  (MotionAxis, MotionAmount degrees, MotionSpeed, MotionPhase)
--   Bob   (MotionAmount studs, MotionSpeed, MotionPhase)
--   Pulse (mesh scale; MotionAmount, MotionSpeed)
--   Blink (eyes)
--
-- Artist override: a Model named after the species Id inside
-- ReplicatedStorage.Assets.CreatureModels is cloned instead of the procedural
-- build. It needs a PrimaryPart at its feet, facing -Z.
--
-- All 24 species are procedural part-built models. Handcrafted meshes are
-- still to be made (see docs/ROADMAP.md).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreatureDefinitions = require(script.Parent.CreatureDefinitions)

local CreatureRig = {}

export type Options = {
	Mutation: string?,
	-- Particles/lights are skipped (they don't render in ViewportFrames).
	ForViewport: boolean?,
	-- All-black silhouette for undiscovered collection entries.
	Silhouette: boolean?,
	-- Workspace displays: skip particles to save performance (quality setting).
	NoEffects: boolean?,
}

type Ctx = {
	Model: Model,
	Root: BasePart,
	Scale: number,
	Palette: CreatureDefinitions.Palette,
	Options: Options,
	MaxY: number,
	MaxR: number,
	Count: number,
}

local DARK = Color3.fromRGB(26, 26, 44)
local WHITE = Color3.fromRGB(246, 247, 255)
local CHEEK = Color3.fromRGB(255, 150, 190)
local STORM = Color3.fromRGB(122, 130, 156)
local SILHOUETTE = Color3.fromRGB(18, 18, 32)

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

local function deg(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

-- Role → colour and material. Mutations and colour cycling recolour by role.
local function styleFor(ctx: Ctx, role: string): (Color3, Enum.Material, number)
	local p = ctx.Palette
	if role == "Primary" then
		return p.Primary, Enum.Material.SmoothPlastic, 0
	elseif role == "Secondary" then
		return p.Secondary, Enum.Material.SmoothPlastic, 0
	elseif role == "Accent" then
		return p.Accent, Enum.Material.SmoothPlastic, 0
	elseif role == "Glow" then
		return p.Glow, Enum.Material.Neon, 0
	elseif role == "AccentGlow" then
		return p.Accent, Enum.Material.Neon, 0
	elseif role == "Crystal" then
		return p.Accent, Enum.Material.Glass, 0.2
	elseif role == "Glass" then
		return p.Primary, Enum.Material.Glass, 0.35
	elseif role == "Aura" then
		return p.Glow, Enum.Material.Glass, 0.7
	elseif role == "Metal" then
		return p.Primary, Enum.Material.Metal, 0
	elseif role == "MetalDark" then
		return p.Secondary, Enum.Material.Metal, 0
	elseif role == "Eye" then
		return DARK, Enum.Material.SmoothPlastic, 0
	elseif role == "EyeShine" then
		return WHITE, Enum.Material.Neon, 0
	elseif role == "EyeGlow" then
		return p.Glow, Enum.Material.Neon, 0
	elseif role == "White" then
		return WHITE, Enum.Material.SmoothPlastic, 0
	elseif role == "Dark" then
		return DARK, Enum.Material.SmoothPlastic, 0
	elseif role == "Cheek" then
		return CHEEK, Enum.Material.SmoothPlastic, 0.15
	elseif role == "Storm" then
		return STORM, Enum.Material.SmoothPlastic, 0
	end
	return p.Primary, Enum.Material.SmoothPlastic, 0
end

local function track(ctx: Ctx, cf: CFrame, size: Vector3)
	local reach = size.Magnitude * 0.5
	ctx.MaxY = math.max(ctx.MaxY, cf.Position.Y + reach * 0.7)
	local flat = Vector3.new(cf.Position.X, 0, cf.Position.Z).Magnitude
	ctx.MaxR = math.max(ctx.MaxR, flat + reach * 0.7)
end

local function weld(part: BasePart, to: BasePart, c0: CFrame)
	local w = Instance.new("Weld")
	w.Name = "RigWeld"
	w.Part0 = to
	w.Part1 = part
	w.C0 = c0
	w.Parent = part
	part.CFrame = to.CFrame * c0
end

-- `cf` is relative to `attach` (the Root by default), in unscaled studs.
local function add(ctx: Ctx, kind: string, size: Vector3, cf: CFrame, role: string, attach: BasePart?): BasePart
	local s = ctx.Scale
	local part: BasePart
	if kind == "Wedge" then
		part = Instance.new("WedgePart")
	else
		local p = Instance.new("Part")
		if kind == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
		end
		part = p
	end
	part.Name = role
	part.Size = size * s
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = size.Magnitude * s > 1.6
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	local color, material, transparency = styleFor(ctx, role)
	if ctx.Options.Silhouette then
		color, material, transparency = SILHOUETTE, Enum.Material.SmoothPlastic, if transparency > 0.5 then 1 else 0
	end
	part.Color = color
	part.Material = material
	part.Transparency = transparency
	part:SetAttribute("Role", role)

	if kind == "Ellipsoid" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	end

	local scaled = CFrame.new(cf.Position * s) * cf.Rotation
	weld(part, attach or ctx.Root, scaled)
	ctx.Count += 1
	part:SetAttribute("Order", ctx.Count)
	part.Parent = ctx.Model
	track(ctx, part.CFrame, size)
	return part
end

local function ellipsoid(ctx: Ctx, size: Vector3, cf: CFrame, role: string, attach: BasePart?): BasePart
	return add(ctx, "Ellipsoid", size, cf, role, attach)
end

local function ball(ctx: Ctx, diameter: number, cf: CFrame, role: string, attach: BasePart?): BasePart
	return add(ctx, "Ellipsoid", Vector3.new(diameter, diameter, diameter), cf, role, attach)
end

local function block(ctx: Ctx, size: Vector3, cf: CFrame, role: string, attach: BasePart?): BasePart
	return add(ctx, "Block", size, cf, role, attach)
end

local function wedge(ctx: Ctx, size: Vector3, cf: CFrame, role: string, attach: BasePart?): BasePart
	return add(ctx, "Wedge", size, cf, role, attach)
end

-- Vertical cylinder (Roblox cylinders run along X, so rotate onto Y).
local function column(ctx: Ctx, diameter: number, height: number, cf: CFrame, role: string, attach: BasePart?): BasePart
	return add(ctx, "Cylinder", Vector3.new(height, diameter, diameter), cf * deg(0, 0, 90), role, attach)
end

-- Disc facing along the cf's look vector.
local function disc(
	ctx: Ctx,
	diameter: number,
	thickness: number,
	cf: CFrame,
	role: string,
	attach: BasePart?
): BasePart
	return add(ctx, "Cylinder", Vector3.new(thickness, diameter, diameter), cf * deg(0, 90, 0), role, attach)
end

-- An invisible part that other parts weld to, so a whole group can move together.
local function pivot(ctx: Ctx, cf: CFrame, attach: BasePart?): BasePart
	local s = ctx.Scale
	local p = Instance.new("Part")
	p.Name = "Pivot"
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Transparency = 1
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	weld(p, attach or ctx.Root, CFrame.new(cf.Position * s) * cf.Rotation)
	ctx.Count += 1
	p:SetAttribute("Order", ctx.Count)
	p.Parent = ctx.Model
	return p
end

local function motion(part: BasePart, kind: string, props: { [string]: any }?)
	part:SetAttribute("Motion", kind)
	if props then
		for key, value in props do
			part:SetAttribute("Motion" .. key, value)
		end
	end
end

-- A ring of short blocks in the pivot's XZ plane.
local function ring(
	ctx: Ctx,
	attach: BasePart,
	radius: number,
	thickness: number,
	segments: number,
	role: string,
	fromDeg: number?,
	toDeg: number?
)
	local a0 = math.rad(fromDeg or 0)
	local a1 = math.rad(toDeg or 360)
	local full = (toDeg or 360) - (fromDeg or 0) >= 360
	local count = if full then segments else segments + 1
	local step = (a1 - a0) / segments
	local length = 2 * radius * math.sin(math.abs(step) / 2) * 1.08
	for i = 0, count - 1 do
		local a = a0 + step * i
		local pos = Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
		local cf = CFrame.new(pos) * CFrame.Angles(0, -a, 0)
		block(ctx, Vector3.new(thickness, thickness, length), cf, role, attach)
	end
end

-- Eyes placed on the front of an ellipsoid head.
-- center/radii: the head ellipsoid (unscaled). spacing: half distance between eyes.
local function eyes(
	ctx: Ctx,
	center: Vector3,
	radii: Vector3,
	spacing: number,
	height: number,
	size: number,
	style: string?,
	attach: BasePart?
)
	style = style or "Round"
	for _, side in { -1, 1 } do
		local x, y = side * spacing, height
		local inside = 1 - (x / radii.X) ^ 2 - (y / radii.Y) ^ 2
		local z = -radii.Z * math.sqrt(math.max(inside, 0.05))
		local surface = center + Vector3.new(x, y, z)
		local normal = Vector3.new(x / radii.X ^ 2, y / radii.Y ^ 2, z / radii.Z ^ 2).Unit
		local cf = CFrame.lookAt(surface, surface + normal)
		if style == "Sleepy" then
			local eye =
				ellipsoid(ctx, Vector3.new(size, size * 0.42, size * 0.4), cf * at(0, -size * 0.08, 0), "Eye", attach)
			motion(eye, "Blink")
			ellipsoid(
				ctx,
				Vector3.new(size * 1.2, size * 0.36, size * 0.45),
				cf * at(0, size * 0.16, -0.02),
				"Primary",
				attach
			)
		elseif style == "Happy" then
			for _, k in { -1, 1 } do
				block(
					ctx,
					Vector3.new(size * 0.55, size * 0.16, size * 0.2),
					cf * at(k * size * 0.18, 0, 0) * deg(0, 0, -k * 35),
					"Eye",
					attach
				)
			end
		elseif style == "Glow" then
			local eye = ellipsoid(ctx, Vector3.new(size, size * 1.1, size * 0.45), cf, "EyeGlow", attach)
			motion(eye, "Blink")
		elseif style == "Bright" then
			local white = ellipsoid(ctx, Vector3.new(size * 1.2, size * 1.3, size * 0.4), cf, "White", attach)
			motion(white, "Blink")
			local pupil = ellipsoid(
				ctx,
				Vector3.new(size * 0.75, size * 0.85, size * 0.4),
				cf * at(0, -size * 0.05, -size * 0.08),
				"Eye",
				attach
			)
			motion(pupil, "Blink")
			ball(ctx, size * 0.28, cf * at(size * 0.15, size * 0.18, -size * 0.2), "EyeShine", attach)
		else
			local eye = ellipsoid(ctx, Vector3.new(size, size * 1.15, size * 0.45), cf, "Eye", attach)
			motion(eye, "Blink")
			local shine = ball(ctx, size * 0.32, cf * at(size * 0.18, size * 0.24, -size * 0.18), "EyeShine", attach)
			motion(shine, "Blink")
		end
	end
end

-- A point on an ellipsoid's surface, for freckles, cheeks and markings.
local function onSurface(center: Vector3, radii: Vector3, x: number, y: number, front: boolean?): CFrame
	local inside = 1 - (x / radii.X) ^ 2 - (y / radii.Y) ^ 2
	local z = radii.Z * math.sqrt(math.max(inside, 0.02)) * (if front == false then 1 else -1)
	local surface = center + Vector3.new(x, y, z)
	local normal = Vector3.new(x / radii.X ^ 2, y / radii.Y ^ 2, z / radii.Z ^ 2).Unit
	return CFrame.lookAt(surface, surface + normal)
end

local function legs(ctx: Ctx, positions: { Vector3 }, diameter: number, height: number, role: string, pawRole: string?)
	for _, pos in positions do
		column(ctx, diameter, height, at(pos.X, height / 2, pos.Z), role)
		if pawRole then
			ellipsoid(
				ctx,
				Vector3.new(diameter * 1.25, diameter * 0.7, diameter * 1.4),
				at(pos.X, diameter * 0.3, pos.Z - diameter * 0.15),
				pawRole
			)
		end
	end
end

-- Species builders ------------------------------------------------------------
-- Units are studs at scale 1; +Y up, the creature faces -Z.

local Builders: { [string]: (Ctx) -> () } = {}

Builders.Pebblepuff = function(c)
	local body = Vector3.new(0, 2.4, 0)
	ellipsoid(c, Vector3.new(2.6, 2.3, 2.5), at(0, 2.4, 0), "Primary")
	ellipsoid(c, Vector3.new(2.1, 1.1, 2.1), at(0, 1.6, 0.1), "Secondary")
	wedge(c, Vector3.new(0.45, 0.95, 0.45), at(0.25, 3.7, 0.1) * deg(0, 0, -14), "Crystal")
	wedge(c, Vector3.new(0.32, 0.65, 0.32), at(-0.25, 3.55, 0.2) * deg(0, 180, 18), "Crystal")
	for _, side in { -1, 1 } do
		for _, offset in { Vector2.new(0.78, -0.3), Vector2.new(0.95, -0.12), Vector2.new(0.62, -0.1) } do
			ball(c, 0.13, onSurface(body, Vector3.new(1.3, 1.15, 1.25), side * offset.X, offset.Y), "Glow")
		end
	end
	eyes(c, body, Vector3.new(1.3, 1.15, 1.25), 0.48, 0.12, 0.42, "Sleepy")
	ellipsoid(c, Vector3.new(0.22, 0.1, 0.1), onSurface(body, Vector3.new(1.3, 1.15, 1.25), 0, -0.25), "Dark")
end

Builders.OrbitOtter = function(c)
	ellipsoid(c, Vector3.new(1.8, 1.7, 2.8), at(0, 1.5, 0.3), "Primary")
	ellipsoid(c, Vector3.new(1.3, 1.2, 2.0), at(0, 1.3, -0.15), "Secondary")
	local head = Vector3.new(0, 2.6, -1)
	ellipsoid(c, Vector3.new(1.6, 1.45, 1.5), at(0, 2.6, -1), "Primary")
	ellipsoid(c, Vector3.new(0.95, 0.6, 0.6), at(0, 2.32, -1.62), "Secondary")
	ball(c, 0.24, at(0, 2.5, -1.92), "Dark")
	for _, side in { -1, 1 } do
		ball(c, 0.42, at(side * 0.62, 3.25, -0.9), "Primary")
		ellipsoid(c, Vector3.new(0.36, 0.62, 0.36), at(side * 0.55, 1.65, -0.95) * deg(20, 0, side * 10), "Secondary")
	end
	eyes(c, head, Vector3.new(0.8, 0.725, 0.75), 0.34, 0.16, 0.3)
	local tail = pivot(c, at(0, 1.25, 1.4))
	motion(tail, "Flap", { Axis = "Y", Amount = 22, Speed = 2.4 })
	ellipsoid(c, Vector3.new(0.65, 0.5, 1.8), at(0, -0.1, 0.8) * deg(-15, 0, 0), "Primary", tail)
	local orbit = pivot(c, at(0, 1.9, 0.2) * deg(10, 0, 0))
	motion(orbit, "Spin", { Axis = "Y", Speed = 1.4 })
	for i = 0, 2 do
		local a = i * math.pi * 2 / 3
		ball(c, 0.42, at(math.cos(a) * 1.9, 0, math.sin(a) * 1.9), "Accent", orbit)
	end
end

Builders.SparkMoth = function(c)
	ellipsoid(c, Vector3.new(0.95, 1.45, 0.95), at(0, 2.9, 0), "Primary")
	ellipsoid(c, Vector3.new(1.15, 0.45, 1.05), at(0, 3.45, -0.05), "Secondary")
	local head = Vector3.new(0, 3.95, -0.12)
	ball(c, 0.9, at(head.X, head.Y, head.Z), "Primary")
	eyes(c, head, Vector3.new(0.45, 0.45, 0.45), 0.2, 0.02, 0.24)
	for _, side in { -1, 1 } do
		local wing = pivot(c, at(side * 0.3, 3.25, 0.32))
		motion(wing, "Flap", { Axis = "Y", Amount = side * 32, Speed = 8 })
		ellipsoid(c, Vector3.new(2.1, 1.7, 0.08), at(side * 1.05, 0.45, 0) * deg(0, 0, side * 14), "Secondary", wing)
		ellipsoid(
			c,
			Vector3.new(1.35, 1.05, 0.08),
			at(side * 0.75, -0.6, 0.04) * deg(0, 0, -side * 22),
			"Primary",
			wing
		)
		ball(c, 0.32, at(side * 1.35, 0.6, -0.06), "AccentGlow", wing)
		ball(c, 0.2, at(side * 0.9, 0.95, -0.06), "Glow", wing)
		ball(c, 0.18, at(side * 0.85, -0.65, -0.06), "Glow", wing)
		column(c, 0.08, 1.0, at(side * 0.22, 4.55, -0.2) * deg(0, 0, -side * 25), "Secondary")
		ball(c, 0.24, at(side * 0.45, 5.0, -0.2), "Glow")
	end
end

Builders.Nebble = function(c)
	local body = Vector3.new(0, 2.4, 0)
	local radii = Vector3.new(1.2, 0.9, 1.0)
	ellipsoid(c, Vector3.new(2.4, 1.8, 2.0), at(0, 2.4, 0), "Primary")
	ellipsoid(c, Vector3.new(1.4, 1.3, 1.4), at(-1.0, 2.2, 0.25), "Primary")
	ellipsoid(c, Vector3.new(1.4, 1.3, 1.4), at(1.0, 2.2, 0.25), "Primary")
	ellipsoid(c, Vector3.new(1.25, 1.1, 1.2), at(0, 3.25, 0.15), "Primary")
	ellipsoid(c, Vector3.new(1.1, 1.0, 1.1), at(-0.62, 3.0, 0.45), "Secondary")
	ellipsoid(c, Vector3.new(1.0, 0.9, 1.0), at(0.66, 3.05, 0.45), "Secondary")
	ellipsoid(c, Vector3.new(2.0, 0.8, 1.6), at(0, 1.6, 0.1), "Secondary")
	for _, side in { -1, 1 } do
		ellipsoid(c, Vector3.new(0.42, 0.24, 0.12), onSurface(body, radii, side * 0.66, -0.2), "Cheek")
	end
	eyes(c, body, radii, 0.38, 0.12, 0.3)
	ellipsoid(c, Vector3.new(0.24, 0.12, 0.1), onSurface(body, radii, 0, -0.18), "Dark")
end

Builders.Crumbtail = function(c)
	local body = Vector3.new(0, 1.15, 0)
	local radii = Vector3.new(0.95, 0.9, 0.95)
	ellipsoid(c, Vector3.new(1.9, 1.8, 1.9), at(0, 1.15, 0), "Primary")
	ellipsoid(c, Vector3.new(1.2, 1.1, 0.5), onSurface(body, radii, 0, -0.25), "Secondary")
	for _, side in { -1, 1 } do
		wedge(c, Vector3.new(0.26, 0.85, 0.5), at(side * 0.48, 2.12, 0) * deg(0, 0, -side * 14), "Primary")
		wedge(c, Vector3.new(0.12, 0.5, 0.26), at(side * 0.48, 2.05, -0.15) * deg(0, 0, -side * 14), "Accent")
		ellipsoid(c, Vector3.new(0.5, 0.3, 0.72), at(side * 0.45, 0.15, -0.22), "Secondary")
	end
	eyes(c, body, radii, 0.34, 0.2, 0.32)
	local tail = pivot(c, at(0, 1.3, 0.85))
	motion(tail, "Flap", { Axis = "Y", Amount = 18, Speed = 3 })
	ball(c, 0.9, at(0, 0.45, 0.35), "AccentGlow", tail)
	ball(c, 0.7, at(0, 0.95, 0.85), "Glow", tail)
	ball(c, 0.5, at(0, 1.3, 1.35), "Glow", tail)
	ball(c, 0.32, at(0, 1.5, 1.8), "Glow", tail)
end

Builders.Flickerfin = function(c)
	local body = Vector3.new(0, 2.6, 0)
	ellipsoid(c, Vector3.new(1.3, 1.6, 2.6), at(0, 2.6, 0), "Glass")
	ellipsoid(c, Vector3.new(0.7, 0.95, 1.6), at(0, 2.6, 0.1), "Glow")
	local tail = pivot(c, at(0, 2.6, 1.25))
	motion(tail, "Flap", { Axis = "Y", Amount = 24, Speed = 5 })
	ellipsoid(c, Vector3.new(0.12, 1.7, 1.0), at(0, 0, 0.55), "Secondary", tail)
	wedge(c, Vector3.new(0.12, 0.85, 1.0), at(0, 3.62, 0.25), "Secondary")
	for _, side in { -1, 1 } do
		local fin = pivot(c, at(side * 0.6, 2.35, -0.2))
		motion(fin, "Flap", { Axis = "Z", Amount = side * 20, Speed = 4 })
		ellipsoid(c, Vector3.new(0.9, 0.1, 0.6), at(side * 0.42, 0, 0), "Accent", fin)
	end
	eyes(c, body, Vector3.new(0.65, 0.8, 1.3), 0.28, 0.25, 0.28)
end

Builders.CometFox = function(c)
	ellipsoid(c, Vector3.new(1.6, 1.5, 2.8), at(0, 1.8, 0.3), "Primary")
	ellipsoid(c, Vector3.new(1.2, 1.2, 1.0), at(0, 1.75, -0.8), "Secondary")
	local head = Vector3.new(0, 2.95, -1.2)
	ellipsoid(c, Vector3.new(1.6, 1.4, 1.4), at(0, 2.95, -1.2), "Primary")
	ellipsoid(c, Vector3.new(1.45, 0.75, 1.0), at(0, 2.7, -1.45), "Secondary")
	ellipsoid(c, Vector3.new(0.6, 0.5, 0.8), at(0, 2.72, -1.95), "Secondary")
	ball(c, 0.22, at(0, 2.84, -2.33), "Dark")
	for _, side in { -1, 1 } do
		wedge(c, Vector3.new(0.22, 1.0, 0.6), at(side * 0.45, 3.82, -1.15) * deg(0, 0, -side * 12), "Primary")
		wedge(c, Vector3.new(0.1, 0.6, 0.32), at(side * 0.45, 3.72, -1.32) * deg(0, 0, -side * 12), "Secondary")
	end
	eyes(c, head, Vector3.new(0.8, 0.7, 0.7), 0.3, 0.18, 0.28)
	legs(c, {
		Vector3.new(-0.45, 0, -0.6),
		Vector3.new(0.45, 0, -0.6),
		Vector3.new(-0.45, 0, 1.1),
		Vector3.new(0.45, 0, 1.1),
	}, 0.38, 1.15, "Primary", "Glow")
	local tail = pivot(c, at(0, 2.05, 1.55))
	motion(tail, "Flap", { Axis = "Y", Amount = 18, Speed = 2.2 })
	ellipsoid(c, Vector3.new(0.8, 0.8, 1.4), at(0, 0.3, 0.6) * deg(-30, 0, 0), "Primary", tail)
	ellipsoid(c, Vector3.new(0.7, 0.7, 1.0), at(0, 0.85, 1.25), "Secondary", tail)
	block(c, Vector3.new(0.52, 0.52, 0.16), at(0, 1.3, 1.75) * deg(0, 0, 45), "Glow", tail)
	block(c, Vector3.new(0.3, 0.3, 0.2), at(0, 1.3, 1.75) * deg(0, 0, 45), "AccentGlow", tail)
end

Builders.HaloHare = function(c)
	ellipsoid(c, Vector3.new(1.9, 1.8, 2.0), at(0, 1.2, 0.2), "Primary")
	ball(c, 0.62, at(0, 1.1, 1.25), "White")
	local head = Vector3.new(0, 2.45, -0.5)
	local radii = Vector3.new(0.75, 0.675, 0.7)
	ellipsoid(c, Vector3.new(1.5, 1.35, 1.4), at(0, 2.45, -0.5), "Primary")
	for _, side in { -1, 1 } do
		local ear = pivot(c, at(side * 0.33, 2.95, -0.4))
		motion(ear, "Flap", { Axis = "X", Amount = 8, Speed = 1.6, Phase = side * 0.6 })
		ellipsoid(c, Vector3.new(0.45, 1.9, 0.32), at(side * 0.15, 0.9, 0) * deg(0, 0, -side * 10), "Primary", ear)
		ellipsoid(
			c,
			Vector3.new(0.24, 1.4, 0.1),
			at(side * 0.15, 0.85, -0.12) * deg(0, 0, -side * 10),
			"Secondary",
			ear
		)
		ellipsoid(c, Vector3.new(0.55, 0.3, 0.9), at(side * 0.45, 0.15, -0.35), "Secondary")
		ellipsoid(c, Vector3.new(0.3, 0.18, 0.1), onSurface(head, radii, side * 0.45, -0.2), "Cheek")
	end
	eyes(c, head, radii, 0.3, 0.1, 0.28)
	ball(c, 0.16, onSurface(head, radii, 0, -0.12), "Accent")
	local halo = pivot(c, at(0, 4.45, -0.4) * deg(8, 0, 0))
	motion(halo, "Spin", { Axis = "Y", Speed = 1.2 })
	ring(c, halo, 0.75, 0.14, 14, "AccentGlow")
end

Builders.MoondropFrog = function(c)
	ellipsoid(c, Vector3.new(2.4, 1.6, 2.2), at(0, 1.0, 0), "Glass")
	ellipsoid(c, Vector3.new(1.6, 1.0, 1.5), at(0, 0.95, 0), "Secondary")
	local crescent = pivot(c, at(0, 1.8, 0.25))
	ring(c, crescent, 0.45, 0.12, 5, "Glow", 200, 340)
	for _, side in { -1, 1 } do
		local eyeCenter = Vector3.new(side * 0.55, 1.85, -0.5)
		ball(c, 0.72, at(eyeCenter.X, eyeCenter.Y, eyeCenter.Z), "White")
		local pupil = ellipsoid(c, Vector3.new(0.38, 0.42, 0.2), at(eyeCenter.X, eyeCenter.Y, eyeCenter.Z - 0.3), "Eye")
		motion(pupil, "Blink")
		ball(c, 0.12, at(eyeCenter.X + 0.08, eyeCenter.Y + 0.1, eyeCenter.Z - 0.38), "EyeShine")
		ellipsoid(c, Vector3.new(0.62, 0.5, 1.0), at(side * 0.95, 0.35, 0.4), "Primary")
		ellipsoid(c, Vector3.new(0.45, 0.2, 0.5), at(side * 0.6, 0.1, -0.8), "Primary")
	end
	ellipsoid(c, Vector3.new(1.1, 0.08, 0.1), at(0, 0.95, -1.08), "Dark")
end

Builders.PolarityPup = function(c)
	ellipsoid(c, Vector3.new(1.5, 1.4, 2.2), at(0, 1.4, 0.2), "Primary")
	ellipsoid(c, Vector3.new(0.7, 0.5, 0.8), at(0.45, 1.85, 0.5), "Secondary")
	local head = Vector3.new(0, 2.5, -0.8)
	local radii = Vector3.new(0.8, 0.725, 0.7)
	ellipsoid(c, Vector3.new(1.6, 1.45, 1.4), at(0, 2.5, -0.8), "Primary")
	ellipsoid(c, Vector3.new(0.8, 0.55, 0.55), at(0, 2.25, -1.38), "White")
	ball(c, 0.24, at(0, 2.38, -1.66), "Dark")
	for _, side in { -1, 1 } do
		local ear = pivot(c, at(side * 0.68, 3.0, -0.7))
		motion(ear, "Flap", { Axis = "Z", Amount = side * 12, Speed = 3 })
		ellipsoid(c, Vector3.new(0.42, 1.0, 0.6), at(side * 0.15, -0.45, 0) * deg(0, 0, side * 15), "Secondary", ear)
	end
	eyes(c, head, radii, 0.32, 0.15, 0.3)
	legs(c, {
		Vector3.new(-0.42, 0, -0.35),
		Vector3.new(0.42, 0, -0.35),
		Vector3.new(-0.42, 0, 0.85),
		Vector3.new(0.42, 0, 0.85),
	}, 0.35, 0.9, "Primary", "Secondary")
	local tail = pivot(c, at(0, 1.8, 1.2))
	motion(tail, "Flap", { Axis = "Y", Amount = 30, Speed = 6 })
	ellipsoid(c, Vector3.new(0.3, 0.3, 0.9), at(0, 0.25, 0.3) * deg(-40, 0, 0), "Secondary", tail)
	local magnets = pivot(c, at(0, 2.0, 0) * deg(15, 0, 0))
	motion(magnets, "Spin", { Axis = "Y", Speed = 1.8 })
	for i = 0, 3 do
		local a = i * math.pi / 2
		block(
			c,
			Vector3.new(0.32, 0.32, 0.32),
			at(math.cos(a) * 1.6, 0, math.sin(a) * 1.6) * deg(45, 45, 0),
			if i % 2 == 0 then "AccentGlow" else "Glow",
			magnets
		)
	end
end

Builders.StardriftGecko = function(c)
	ellipsoid(c, Vector3.new(1.2, 0.8, 2.2), at(0, 0.9, 0.2), "Primary")
	local head = Vector3.new(0, 1.1, -1.3)
	ellipsoid(c, Vector3.new(1.25, 0.82, 1.15), at(0, 1.1, -1.3), "Primary")
	for _, spot in
		{
			Vector3.new(0.25, 1.27, -0.3),
			Vector3.new(-0.3, 1.25, 0.25),
			Vector3.new(0.2, 1.22, 0.8),
			Vector3.new(-0.1, 1.45, -1.35),
		}
	do
		ball(c, 0.24, at(spot.X, spot.Y, spot.Z), "Glow")
	end
	for _, side in { -1, 1 } do
		ellipsoid(c, Vector3.new(0.95, 0.25, 0.3), at(side * 0.75, 0.45, -0.5) * deg(0, side * 30, 0), "Secondary")
		ellipsoid(c, Vector3.new(0.95, 0.25, 0.3), at(side * 0.75, 0.45, 0.85) * deg(0, -side * 30, 0), "Secondary")
		ball(c, 0.3, at(side * 1.15, 0.3, -0.75), "AccentGlow")
		ball(c, 0.3, at(side * 1.15, 0.3, 1.1), "AccentGlow")
	end
	eyes(c, head, Vector3.new(0.625, 0.41, 0.575), 0.32, 0.12, 0.34, "Bright")
	local tail = pivot(c, at(0, 0.85, 1.25))
	motion(tail, "Flap", { Axis = "Y", Amount = 20, Speed = 2.6 })
	ellipsoid(c, Vector3.new(0.6, 0.45, 1.0), at(0, 0, 0.5), "Primary", tail)
	ellipsoid(c, Vector3.new(0.4, 0.3, 0.9), at(0, 0.02, 1.3), "Primary", tail)
	ellipsoid(c, Vector3.new(0.25, 0.22, 0.6), at(0, 0.15, 1.95) * deg(30, 0, 0), "Glow", tail)
end

Builders.AuroraLynx = function(c)
	ellipsoid(c, Vector3.new(1.8, 1.7, 3.2), at(0, 2.1, 0.3), "Primary")
	ellipsoid(c, Vector3.new(1.3, 1.2, 0.9), at(0, 2.0, -1.1), "White")
	local head = Vector3.new(0, 3.3, -1.35)
	local radii = Vector3.new(0.9, 0.775, 0.75)
	ellipsoid(c, Vector3.new(1.8, 1.55, 1.5), at(0, 3.3, -1.35), "Primary")
	for _, side in { -1, 1 } do
		ellipsoid(c, Vector3.new(0.9, 0.7, 0.7), at(side * 0.72, 3.0, -1.4) * deg(0, 0, side * 20), "White")
		wedge(c, Vector3.new(0.25, 1.1, 0.6), at(side * 0.5, 4.25, -1.25) * deg(0, 0, -side * 8), "Primary")
		block(c, Vector3.new(0.08, 0.5, 0.08), at(side * 0.55, 5.0, -1.25), "Glow")
	end
	eyes(c, head, radii, 0.36, 0.15, 0.3)
	ball(c, 0.2, onSurface(head, radii, 0, -0.12), "Cheek")
	legs(c, {
		Vector3.new(-0.5, 0, -0.75),
		Vector3.new(0.5, 0, -0.75),
		Vector3.new(-0.5, 0, 1.25),
		Vector3.new(0.5, 0, 1.25),
	}, 0.45, 1.4, "Primary", "Secondary")
	ellipsoid(c, Vector3.new(0.5, 0.5, 1.3), at(0, 2.55, 2.0) * deg(-35, 0, 0), "Secondary")
	ball(c, 0.45, at(0, 3.0, 2.5), "Glow")
	for i, z in { -0.5, 0.3, 1.1 } do
		local ribbon = pivot(c, at(0, 3.25, z))
		motion(ribbon, "Flap", { Axis = "X", Amount = 14, Speed = 1.5, Phase = i * 0.9 })
		block(
			c,
			Vector3.new(0.08, 0.35, 2.2),
			at((i - 2) * 0.35, 0.6, 0.6) * deg(15, 0, 0),
			if i % 2 == 0 then "Glow" else "AccentGlow",
			ribbon
		)
	end
end

Builders.CrystalWisp = function(c)
	local core = Vector3.new(0, 3, 0)
	ball(c, 1.4, at(0, 3, 0), "Glow")
	ball(c, 2.1, at(0, 3, 0), "Aura")
	eyes(c, core, Vector3.new(0.7, 0.7, 0.7), 0.22, 0.05, 0.22)
	local shards = pivot(c, at(0, 3, 0))
	motion(shards, "Spin", { Axis = "Y", Speed = 0.6 })
	for i = 0, 5 do
		local a = i * math.pi / 3
		local y = if i % 2 == 0 then 0.35 else -0.35
		local pos = Vector3.new(math.cos(a) * 1.55, y, math.sin(a) * 1.55)
		local cf = CFrame.lookAt(pos, pos * 2) * deg(90, 0, 0)
		block(c, Vector3.new(0.34, 1.15, 0.34), cf * deg(0, 45, 0), "Crystal", shards)
	end
	local trail = pivot(c, at(0, 2.2, 0.1))
	motion(trail, "Bob", { Amount = 0.12, Speed = 2 })
	ball(c, 0.6, at(0, -0.3, 0.1), "Glow", trail)
	ball(c, 0.4, at(0, -0.8, 0.2), "Glow", trail)
	ball(c, 0.25, at(0, -1.2, 0.3), "Glow", trail)
end

Builders.SatelliteTurtle = function(c)
	ellipsoid(c, Vector3.new(3.0, 1.9, 3.3), at(0, 1.7, 0.2), "Secondary")
	ellipsoid(c, Vector3.new(3.25, 0.5, 3.55), at(0, 1.0, 0.2), "Primary")
	for _, p in
		{
			Vector3.new(0, 2.6, 0.2),
			Vector3.new(-0.8, 2.35, -0.4),
			Vector3.new(0.8, 2.35, 0.8),
			Vector3.new(0.8, 2.35, -0.4),
			Vector3.new(-0.8, 2.35, 0.8),
		}
	do
		ellipsoid(c, Vector3.new(0.75, 0.2, 0.75), at(p.X, p.Y, p.Z), "Primary")
	end
	local head = Vector3.new(0, 1.5, -1.95)
	ellipsoid(c, Vector3.new(1.2, 1.0, 1.2), at(0, 1.5, -1.95), "Primary")
	eyes(c, head, Vector3.new(0.6, 0.5, 0.6), 0.25, 0.1, 0.24)
	for _, side in { -1, 1 } do
		local front = pivot(c, at(side * 1.25, 0.7, -1.0))
		motion(front, "Flap", { Axis = "Z", Amount = side * 10, Speed = 1.4 })
		ellipsoid(c, Vector3.new(1.0, 0.25, 0.6), at(side * 0.3, 0, 0) * deg(0, side * 25, 0), "Primary", front)
		ellipsoid(c, Vector3.new(0.85, 0.25, 0.55), at(side * 1.2, 0.6, 1.3) * deg(0, -side * 25, 0), "Primary")
	end
	column(c, 0.12, 0.8, at(0, 3.0, 0.2), "MetalDark")
	ball(c, 0.25, at(0, 3.45, 0.2), "Glow")
	disc(c, 0.9, 0.12, at(0.35, 2.85, -0.1) * deg(-30, 20, 0), "Accent")
	block(c, Vector3.new(2.2, 0.08, 0.08), at(0, 2.8, 0.55), "MetalDark")
	for _, side in { -1, 1 } do
		block(c, Vector3.new(0.75, 0.06, 0.5), at(side * 1.05, 2.8, 0.55), "Glow")
	end
	local orbit = pivot(c, at(0, 2.0, 0.2) * deg(18, 0, 10))
	motion(orbit, "Spin", { Axis = "Y", Speed = 0.9 })
	ring(c, orbit, 2.35, 0.08, 22, "Glow")
	block(c, Vector3.new(0.32, 0.32, 0.32), at(2.35, 0, 0), "Accent", orbit)
end

Builders.CelestialStingray = function(c)
	ellipsoid(c, Vector3.new(1.6, 0.65, 2.4), at(0, 2.6, 0), "Primary")
	for _, side in { -1, 1 } do
		local wing = pivot(c, at(side * 0.6, 2.6, 0))
		motion(wing, "Flap", { Axis = "Z", Amount = side * 14, Speed = 1.8 })
		ellipsoid(c, Vector3.new(3.0, 0.3, 2.2), at(side * 1.35, 0, 0.2), "Primary", wing)
		ellipsoid(c, Vector3.new(2.6, 0.2, 1.8), at(side * 1.25, -0.12, 0.25), "Secondary", wing)
		for _, spot in
			{
				Vector3.new(1.0, 0.16, -0.2),
				Vector3.new(1.7, 0.12, 0.3),
				Vector3.new(2.2, 0.1, 0.0),
				Vector3.new(1.3, 0.14, 0.7),
			}
		do
			ball(c, 0.2, at(side * spot.X, spot.Y, spot.Z), "Glow", wing)
		end
	end
	local tail = pivot(c, at(0, 2.6, 1.1))
	motion(tail, "Flap", { Axis = "Y", Amount = 12, Speed = 1.2 })
	add(c, "Cylinder", Vector3.new(3.0, 0.14, 0.14), at(0, 0, 1.5) * deg(0, 90, 0), "Secondary", tail)
	ball(c, 0.32, at(0, 0, 3.05), "AccentGlow", tail)
	for _, side in { -1, 1 } do
		local eye = ellipsoid(c, Vector3.new(0.26, 0.22, 0.2), at(side * 0.38, 2.88, -0.95), "Eye")
		motion(eye, "Blink")
		ball(c, 0.09, at(side * 0.38 + 0.05, 2.95, -1.03), "EyeShine")
	end
end

Builders.PulsarPenguin = function(c)
	ellipsoid(c, Vector3.new(1.9, 2.6, 1.8), at(0, 1.5, 0), "Primary")
	ellipsoid(c, Vector3.new(1.4, 2.0, 1.0), at(0, 1.35, -0.48), "Secondary")
	local head = Vector3.new(0, 2.85, -0.05)
	ellipsoid(c, Vector3.new(1.5, 1.3, 1.4), at(0, 2.85, -0.05), "Primary")
	wedge(c, Vector3.new(0.32, 0.22, 0.5), at(0, 2.72, -0.86) * deg(0, 180, 0), "Accent")
	eyes(c, head, Vector3.new(0.75, 0.65, 0.7), 0.28, 0.12, 0.24, "Bright")
	for _, side in { -1, 1 } do
		local flipper = pivot(c, at(side * 0.88, 2.0, 0))
		motion(flipper, "Flap", { Axis = "Z", Amount = side * 15, Speed = 3 })
		ellipsoid(c, Vector3.new(0.25, 1.2, 0.6), at(side * 0.12, -0.5, 0) * deg(0, 0, side * 12), "Primary", flipper)
		ellipsoid(c, Vector3.new(0.5, 0.2, 0.72), at(side * 0.4, 0.1, -0.3), "Accent")
	end
	local pulse = ellipsoid(c, Vector3.new(2.8, 0.12, 2.8), at(0, 1.35, 0), "Aura")
	motion(pulse, "Pulse", { Amount = 0.25, Speed = 6.28 })
	ring(c, pivot(c, at(0, 1.35, 0)), 1.05, 0.1, 16, "Glow")
end

Builders.NebulaPhoenix = function(c)
	ellipsoid(c, Vector3.new(1.5, 1.8, 2.0), at(0, 3.2, 0.1), "Primary")
	ellipsoid(c, Vector3.new(1.1, 1.3, 0.8), at(0, 3.1, -0.6), "Secondary")
	local head = Vector3.new(0, 4.35, -0.55)
	ball(c, 1.3, at(0, 4.35, -0.55), "Primary")
	wedge(c, Vector3.new(0.3, 0.3, 0.6), at(0, 4.22, -1.35) * deg(0, 180, 0), "Secondary")
	eyes(c, head, Vector3.new(0.65, 0.65, 0.65), 0.25, 0.08, 0.24)
	for i, tilt in { -30, -8, 14 } do
		wedge(c, Vector3.new(0.12, 0.9, 0.5), at(0, 5.0 - i * 0.05, -0.35 + i * 0.12) * deg(tilt, 0, 0), "Glow")
	end
	for _, side in { -1, 1 } do
		local wing = pivot(c, at(side * 0.6, 3.6, 0.2))
		motion(wing, "Flap", { Axis = "Z", Amount = side * 22, Speed = 2.5 })
		ellipsoid(c, Vector3.new(2.4, 0.2, 1.1), at(side * 1.3, 0.3, 0) * deg(0, 0, side * 20), "Primary", wing)
		ellipsoid(c, Vector3.new(2.0, 0.18, 0.9), at(side * 1.2, -0.05, 0.35) * deg(0, 0, side * 5), "Secondary", wing)
		ellipsoid(
			c,
			Vector3.new(1.4, 0.16, 0.7),
			at(side * 1.0, -0.35, 0.6) * deg(0, 0, -side * 10),
			"AccentGlow",
			wing
		)
	end
	local tail = pivot(c, at(0, 2.6, 0.9))
	motion(tail, "Flap", { Axis = "X", Amount = 8, Speed = 1.2 })
	for k, role in { "Glow", "Secondary", "AccentGlow" } do
		local x = (k - 2) * 0.35
		ellipsoid(c, Vector3.new(0.3, 0.12, 2.4), at(x, -0.3, 1.2) * deg(25, (k - 2) * 15, 0), role, tail)
	end
end

Builders.PrismStag = function(c)
	ellipsoid(c, Vector3.new(1.8, 1.8, 3.4), at(0, 2.9, 0.3), "Primary")
	ellipsoid(c, Vector3.new(0.9, 1.6, 0.9), at(0, 3.9, -1.2) * deg(25, 0, 0), "Primary")
	local head = Vector3.new(0, 4.7, -1.75)
	ellipsoid(c, Vector3.new(1.0, 1.0, 1.4), at(0, 4.7, -1.75), "Primary")
	ellipsoid(c, Vector3.new(0.7, 0.6, 0.8), at(0, 4.5, -2.35), "Secondary")
	ball(c, 0.2, at(0, 4.6, -2.75), "Dark")
	eyes(c, head, Vector3.new(0.5, 0.5, 0.7), 0.3, 0.05, 0.22)
	block(c, Vector3.new(0.4, 0.4, 0.2), at(0, 3.2, -1.3) * deg(0, 0, 45), "Glow")
	legs(c, {
		Vector3.new(-0.5, 0, -0.9),
		Vector3.new(0.5, 0, -0.9),
		Vector3.new(-0.5, 0, 1.3),
		Vector3.new(0.5, 0, 1.3),
	}, 0.32, 2.2, "Primary", "Secondary")
	ellipsoid(c, Vector3.new(0.4, 0.5, 0.4), at(0, 3.5, 2.05), "Secondary")
	for _, side in { -1, 1 } do
		ellipsoid(c, Vector3.new(0.25, 0.7, 0.45), at(side * 0.55, 5.0, -1.6) * deg(0, 0, side * 60), "Secondary")
		block(c, Vector3.new(0.18, 1.4, 0.18), at(side * 0.42, 5.6, -1.6) * deg(0, 0, -side * 25), "Crystal")
		block(c, Vector3.new(0.14, 0.8, 0.14), at(side * 0.78, 6.15, -1.55) * deg(0, 0, -side * 55), "Crystal")
		block(c, Vector3.new(0.14, 0.75, 0.14), at(side * 0.6, 6.4, -1.45) * deg(0, 0, side * 10), "Crystal")
		block(c, Vector3.new(0.2, 0.2, 0.2), at(side * 1.08, 6.35, -1.55) * deg(45, 0, 45), "Glow")
		block(c, Vector3.new(0.2, 0.2, 0.2), at(side * 0.66, 6.8, -1.45) * deg(45, 0, 45), "Glow")
	end
end

Builders.TempestDragonling = function(c)
	ellipsoid(c, Vector3.new(1.5, 1.6, 1.9), at(0, 2.6, 0.2), "Primary")
	ellipsoid(c, Vector3.new(1.0, 1.2, 0.6), at(0, 2.5, -0.55), "Secondary")
	local head = Vector3.new(0, 3.7, -0.6)
	ellipsoid(c, Vector3.new(1.5, 1.3, 1.5), at(0, 3.7, -0.6), "Primary")
	ellipsoid(c, Vector3.new(0.9, 0.6, 0.8), at(0, 3.5, -1.35), "Primary")
	for _, side in { -1, 1 } do
		ball(c, 0.1, at(side * 0.18, 3.6, -1.75), "Dark")
		wedge(c, Vector3.new(0.18, 0.6, 0.3), at(side * 0.4, 4.4, -0.4) * deg(-20, 0, 0), "Secondary")
		local wing = pivot(c, at(side * 0.6, 3.0, 0.4))
		motion(wing, "Flap", { Axis = "Z", Amount = side * 30, Speed = 7 })
		ellipsoid(c, Vector3.new(1.6, 0.12, 1.0), at(side * 0.85, 0.3, 0.2) * deg(0, 0, side * 25), "Secondary", wing)
	end
	eyes(c, head, Vector3.new(0.75, 0.65, 0.75), 0.3, 0.15, 0.28)
	local tail = pivot(c, at(0, 2.2, 1.0))
	motion(tail, "Flap", { Axis = "Y", Amount = 20, Speed = 2 })
	ellipsoid(c, Vector3.new(0.7, 0.6, 1.0), at(0, -0.1, 0.5), "Primary", tail)
	ellipsoid(c, Vector3.new(0.5, 0.45, 0.9), at(0, -0.15, 1.25), "Primary", tail)
	block(c, Vector3.new(0.45, 0.12, 0.45), at(0, -0.15, 1.85) * deg(0, 45, 0), "AccentGlow", tail)
	local storms = pivot(c, at(0, 3.4, 0))
	motion(storms, "Spin", { Axis = "Y", Speed = 1 })
	for _, a in { 0, math.pi } do
		local x, z = math.cos(a) * 1.9, math.sin(a) * 1.9
		ball(c, 0.6, at(x, 0.1, z), "Storm", storms)
		ball(c, 0.45, at(x - 0.32, 0, z + 0.1), "Storm", storms)
		ball(c, 0.45, at(x + 0.32, 0.02, z - 0.05), "Storm", storms)
		wedge(c, Vector3.new(0.1, 0.45, 0.18), at(x, -0.45, z) * deg(0, 0, 20), "AccentGlow", storms)
	end
end

Builders.ClockworkStarling = function(c)
	local body = Vector3.new(0, 3.1, 0)
	ball(c, 1.5, at(0, 3.1, 0), "Metal")
	local head = Vector3.new(0, 4.15, -0.3)
	ball(c, 1.05, at(0, 4.15, -0.3), "Metal")
	wedge(c, Vector3.new(0.22, 0.2, 0.55), at(0, 4.05, -0.98) * deg(0, 180, 0), "MetalDark")
	eyes(c, head, Vector3.new(0.525, 0.525, 0.525), 0.22, 0.06, 0.24, "Glow")
	disc(c, 0.6, 0.12, CFrame.lookAt(body + Vector3.new(0, 0, -0.74), body + Vector3.new(0, 0, -2)), "AccentGlow")
	for _, side in { -1, 1 } do
		local wing = pivot(c, at(side * 0.6, 3.3, 0.1))
		motion(wing, "Flap", { Axis = "Z", Amount = side * 25, Speed = 4 })
		for k = 0, 2 do
			block(
				c,
				Vector3.new(1.1 - k * 0.15, 0.08, 0.35),
				at(side * 0.6, 0.15 - k * 0.2, k * 0.25) * deg(0, 0, side * 15),
				"MetalDark",
				wing
			)
		end
		column(c, 0.1, 0.6, at(side * 0.25, 2.1, 0), "MetalDark")
		ellipsoid(c, Vector3.new(0.3, 0.12, 0.4), at(side * 0.25, 1.8, -0.1), "MetalDark")
	end
	for k = -1, 1 do
		block(c, Vector3.new(0.25, 0.06, 1.0), at(k * 0.22, 2.8, 0.95) * deg(20, k * 15, 0), "MetalDark")
	end
	local ringA = pivot(c, at(0, 3.1, 0) * deg(70, 0, 0))
	motion(ringA, "Spin", { Axis = "Y", Speed = 1.5 })
	ring(c, ringA, 1.25, 0.08, 16, "AccentGlow")
	local ringB = pivot(c, at(0, 3.1, 0) * deg(0, 0, 60))
	motion(ringB, "Spin", { Axis = "Y", Speed = -1.1 })
	ring(c, ringB, 1.45, 0.08, 18, "Metal")
end

Builders.EclipseSerpent = function(c)
	local segments = 10
	local lastPos = Vector3.zero
	for i = 1, segments do
		local t = i / segments
		local angle = t * math.pi * 1.6
		local radius = 1.5 * (1 - t * 0.55)
		local pos = Vector3.new(math.cos(angle) * radius, 0.9 + t * 3.5, math.sin(angle) * radius + 0.3)
		local size = 0.55 + 0.75 * math.sin(math.pi * (0.15 + 0.7 * t))
		local seg = ball(c, size, at(pos.X, pos.Y, pos.Z), "Primary")
		motion(seg, "Bob", { Amount = 0.1, Speed = 1.8, Phase = i * 0.55 })
		local outward = Vector3.new(pos.X, 0, pos.Z - 0.3)
		if outward.Magnitude > 0.1 then
			local markPos = Vector3.new(0, size * 0.18, 0) + outward.Unit * size * 0.42
			ball(c, size * 0.32, at(markPos.X, markPos.Y, markPos.Z), if i % 2 == 0 then "AccentGlow" else "Glow", seg)
		end
		lastPos = pos
	end
	local headPos = lastPos + Vector3.new(0, 0.55, -0.55)
	local headPivot = pivot(c, at(headPos.X, headPos.Y, headPos.Z))
	motion(headPivot, "Bob", { Amount = 0.1, Speed = 1.8, Phase = (segments + 1) * 0.55 })
	ellipsoid(c, Vector3.new(1.3, 1.0, 1.7), at(0, 0, 0), "Primary", headPivot)
	ellipsoid(c, Vector3.new(0.9, 0.5, 0.9), at(0, -0.2, -0.6), "Secondary", headPivot)
	eyes(c, Vector3.zero, Vector3.new(0.65, 0.5, 0.85), 0.32, 0.12, 0.26, "Glow", headPivot)
	for _, side in { -1, 1 } do
		wedge(c, Vector3.new(0.12, 0.7, 0.8), at(side * 0.3, 0.55, 0.2) * deg(-25, 0, side * 10), "Glow", headPivot)
	end
	local eclipse = pivot(c, at(0, 0.5, 1.0), headPivot)
	motion(eclipse, "Spin", { Axis = "Z", Speed = 0.5 })
	disc(c, 1.4, 0.1, CFrame.identity, "Dark", eclipse)
	local corona = pivot(c, CFrame.identity * deg(90, 0, 0), eclipse)
	ring(c, corona, 0.82, 0.12, 18, "AccentGlow")
end

Builders.SolarLeviathan = function(c)
	ellipsoid(c, Vector3.new(3.2, 2.6, 6.0), at(0, 3.6, 0.4), "Primary")
	ellipsoid(c, Vector3.new(2.4, 1.6, 4.6), at(0, 3.05, 0.1), "Secondary")
	local head = Vector3.new(0, 3.8, -2.4)
	ellipsoid(c, Vector3.new(2.8, 2.3, 2.4), at(0, 3.8, -2.4), "Primary")
	eyes(c, head, Vector3.new(1.4, 1.15, 1.2), 0.75, 0.25, 0.34)
	ellipsoid(c, Vector3.new(1.0, 0.08, 0.1), onSurface(head, Vector3.new(1.4, 1.15, 1.2), 0, -0.3), "Dark")
	for k = -1.5, 1.5, 1 do
		ellipsoid(c, Vector3.new(2.0, 0.1, 0.35), at(0, 2.32, k), "Glow")
	end
	for _, spot in { Vector3.new(0.6, 4.85, -0.5), Vector3.new(-0.7, 4.8, 0.6), Vector3.new(0.4, 4.7, 1.6) } do
		ball(c, 0.32, at(spot.X, spot.Y, spot.Z), "Glow")
	end
	wedge(c, Vector3.new(0.25, 1.3, 1.8), at(0, 5.15, 0.8), "AccentGlow")
	for _, side in { -1, 1 } do
		local fin = pivot(c, at(side * 1.4, 3.2, -0.6))
		motion(fin, "Flap", { Axis = "Z", Amount = side * 18, Speed = 1.2 })
		ellipsoid(c, Vector3.new(2.6, 0.22, 1.4), at(side * 1.3, -0.1, 0.2) * deg(0, 0, -side * 15), "AccentGlow", fin)
	end
	local tail = pivot(c, at(0, 3.7, 3.2))
	motion(tail, "Flap", { Axis = "X", Amount = 10, Speed = 1 })
	ellipsoid(c, Vector3.new(1.2, 1.0, 2.2), at(0, 0, 0.9), "Primary", tail)
	for _, side in { -1, 1 } do
		ellipsoid(c, Vector3.new(1.8, 0.2, 1.0), at(side * 0.9, 0, 2.0) * deg(0, side * 25, 0), "AccentGlow", tail)
	end
end

Builders.AstralGryphon = function(c)
	ellipsoid(c, Vector3.new(2.0, 1.9, 3.4), at(0, 2.5, 0.5), "Primary")
	legs(c, { Vector3.new(-0.6, 0, -0.6), Vector3.new(0.6, 0, -0.6) }, 0.5, 1.6, "White", "Accent")
	legs(c, { Vector3.new(-0.6, 0, 1.6), Vector3.new(0.6, 0, 1.6) }, 0.55, 1.6, "Primary", "Primary")
	ellipsoid(c, Vector3.new(1.6, 1.6, 1.2), at(0, 3.0, -0.9), "White")
	local head = Vector3.new(0, 4.3, -1.5)
	ellipsoid(c, Vector3.new(1.4, 1.3, 1.4), at(0, 4.3, -1.5), "White")
	wedge(c, Vector3.new(0.4, 0.45, 0.7), at(0, 4.12, -2.3) * deg(-10, 180, 0), "Accent")
	eyes(c, head, Vector3.new(0.7, 0.65, 0.7), 0.32, 0.12, 0.26)
	for _, side in { -1, 1 } do
		wedge(c, Vector3.new(0.18, 0.7, 0.5), at(side * 0.45, 4.95, -1.3) * deg(-30, 0, 0), "Secondary")
	end
	local mane = pivot(c, at(0, 4.0, -1.15))
	motion(mane, "Spin", { Axis = "Z", Speed = 0.3 })
	for i = 0, 9 do
		local a = i * math.pi * 2 / 10
		local pos = Vector3.new(math.cos(a) * 1.0, math.sin(a) * 1.0, 0.1)
		block(c, Vector3.new(0.25, 0.9, 0.2), CFrame.new(pos) * CFrame.Angles(0, 0, a - math.pi / 2), "Glow", mane)
	end
	for _, side in { -1, 1 } do
		local wing = pivot(c, at(side * 0.8, 3.4, 0.2))
		motion(wing, "Flap", { Axis = "Z", Amount = side * 20, Speed = 1.6 })
		ellipsoid(c, Vector3.new(2.8, 0.22, 1.2), at(side * 1.4, 0.8, 0.3) * deg(0, 0, side * 35), "Primary", wing)
		ellipsoid(c, Vector3.new(2.3, 0.2, 1.0), at(side * 1.3, 0.45, 0.75) * deg(0, 0, side * 25), "Secondary", wing)
		ellipsoid(c, Vector3.new(1.6, 0.18, 0.8), at(side * 1.1, 0.15, 1.1) * deg(0, 0, side * 15), "AccentGlow", wing)
	end
	local tail = pivot(c, at(0, 2.9, 2.1))
	motion(tail, "Flap", { Axis = "Y", Amount = 15, Speed = 1.5 })
	ellipsoid(c, Vector3.new(0.3, 0.3, 1.6), at(0, 0.2, 0.7) * deg(-30, 0, 0), "Primary", tail)
	ball(c, 0.5, at(0, 0.75, 1.4), "Glow", tail)
end

Builders.TheFirstStar = function(c)
	local core = Vector3.new(0, 4, 0)
	ball(c, 1.6, at(0, 4, 0), "Glow")
	ball(c, 2.5, at(0, 4, 0), "Aura")
	local points = pivot(c, at(0, 4, 0))
	motion(points, "Spin", { Axis = "Z", Speed = 0.25 })
	for i = 0, 3 do
		ellipsoid(
			c,
			Vector3.new(0.55, 3.9, 0.3),
			CFrame.Angles(0, 0, i * math.pi / 4),
			if i % 2 == 0 then "AccentGlow" else "Glow",
			points
		)
	end
	eyes(c, core, Vector3.new(0.8, 0.8, 0.8), 0.28, 0.1, 0.24)
	ellipsoid(c, Vector3.new(0.3, 0.1, 0.1), onSurface(core, Vector3.new(0.8, 0.8, 0.8), 0, -0.22), "Dark")
	local rings = {
		{ Tilt = deg(65, 0, 0), Speed = 0.8, Radius = 2.4, Role = "AccentGlow" },
		{ Tilt = deg(-55, 0, 35), Speed = -0.6, Radius = 2.9, Role = "Glow" },
		{ Tilt = deg(20, 0, -70), Speed = 1.1, Radius = 3.3, Role = "AccentGlow" },
	}
	for i, spec in rings do
		local holder = pivot(c, at(0, 4, 0) * spec.Tilt)
		motion(holder, "Spin", { Axis = "Y", Speed = spec.Speed })
		ring(c, holder, spec.Radius, 0.1, 22 + i * 4, spec.Role)
		ball(c, 0.38, at(spec.Radius, 0, 0), "Secondary", holder)
		ball(c, 0.26, at(-spec.Radius, 0, 0), "Accent", holder)
	end
end

-- Shown if a species has no builder and no override model.
local function buildMystery(c: Ctx)
	local core = Vector3.new(0, 2.2, 0)
	ball(c, 2, at(0, 2.2, 0), "Primary")
	ball(c, 2.6, at(0, 2.2, 0), "Aura")
	eyes(c, core, Vector3.new(1, 1, 1), 0.35, 0.1, 0.3)
end

-- Effects --------------------------------------------------------------------

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARKLE
	e.LightEmission = 1
	e.Rate = 3
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Speed = NumberRange.new(0.5, 1.5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	for key, value in props do
		(e :: any)[key] = value
	end
	e:AddTag("CreatureFX")
	e.Parent = parent
	return e
end

local function recolor(ctx: Ctx, roles: { [string]: (Color3) -> Color3 }, material: { [string]: Enum.Material }?)
	for _, part in ctx.Model:GetChildren() do
		if part:IsA("BasePart") then
			local role = part:GetAttribute("Role")
			local fn = role and roles[role]
			if fn then
				part.Color = fn(part.Color)
			end
			if material and role and material[role] then
				part.Material = material[role]
			end
		end
	end
end

local function applyMutation(ctx: Ctx, mutation: string)
	local wantEffects = not ctx.Options.ForViewport and not ctx.Options.NoEffects
	local body = ctx.Model:FindFirstChild("Primary") :: BasePart?
	if mutation == "Charged" then
		local spark = Color3.fromRGB(150, 240, 255)
		recolor(ctx, {
			Accent = function()
				return spark
			end,
			Glow = function(c)
				return c:Lerp(spark, 0.6)
			end,
		}, { Accent = Enum.Material.Neon })
		if wantEffects and body then
			emitter(body, {
				Color = ColorSequence.new(spark),
				Rate = 4,
				Speed = NumberRange.new(2, 4),
				Lifetime = NumberRange.new(0.2, 0.4),
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
			})
		end
	elseif mutation == "Aurora" then
		local mint = Color3.fromRGB(156, 245, 216)
		local lilac = Color3.fromRGB(232, 166, 255)
		recolor(ctx, {
			Primary = function(c)
				return c:Lerp(mint, 0.35)
			end,
			Secondary = function(c)
				return c:Lerp(lilac, 0.35)
			end,
			Glow = function()
				return lilac
			end,
		})
		ctx.Model:SetAttribute("ColorCycle", "Aurora")
		if wantEffects and body then
			emitter(body, {
				Color = ColorSequence.new(mint, lilac),
				Rate = 2,
				Lifetime = NumberRange.new(1.5, 2.5),
				Speed = NumberRange.new(0.3, 0.8),
				Acceleration = Vector3.new(0, 1, 0),
			})
		end
	elseif mutation == "Eclipse" then
		local night = Color3.fromRGB(34, 26, 58)
		local corona = Color3.fromRGB(255, 231, 160)
		recolor(ctx, {
			Primary = function(c)
				return c:Lerp(night, 0.78)
			end,
			Secondary = function(c)
				return c:Lerp(night, 0.6)
			end,
			Accent = function()
				return corona
			end,
			Glow = function()
				return corona
			end,
			Metal = function(c)
				return c:Lerp(night, 0.7)
			end,
		}, { Accent = Enum.Material.Neon })
		if wantEffects and body then
			emitter(body, {
				Texture = SMOKE,
				LightEmission = 0.3,
				Color = ColorSequence.new(Color3.fromRGB(90, 60, 150), night),
				Rate = 2,
				Lifetime = NumberRange.new(1.2, 2),
				Speed = NumberRange.new(0.2, 0.6),
			})
		end
	elseif mutation == "Prismatic" then
		ctx.Model:SetAttribute("ColorCycle", "Prismatic")
		recolor(ctx, {}, { Accent = Enum.Material.Neon })
		if wantEffects and body then
			emitter(body, {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 126, 152)),
					ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 207, 112)),
					ColorSequenceKeypoint.new(0.66, Color3.fromRGB(116, 229, 254)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(182, 156, 255)),
				}),
				Rate = 6,
			})
		end
	end
end

local function applyRarityEffects(ctx: Ctx, rarity: string)
	if ctx.Options.ForViewport or ctx.Options.NoEffects or ctx.Options.Silhouette then
		return
	end
	local body = ctx.Model:FindFirstChild("Primary") or ctx.Model:FindFirstChild("Glow")
	if not body then
		return
	end
	local palette = ctx.Palette
	if rarity == "Epic" or rarity == "Legendary" or rarity == "Mythic" then
		emitter(body, {
			Color = ColorSequence.new(palette.Glow),
			Rate = if rarity == "Epic" then 2 else 4,
		})
	end
	if ctx.Model:GetAttribute("SpeciesId") == "NebulaPhoenix" then
		emitter(body, {
			Texture = FIRE,
			Color = ColorSequence.new(palette.Secondary, palette.Primary),
			Rate = 6,
			Lifetime = NumberRange.new(0.5, 0.9),
			Speed = NumberRange.new(0.5, 1),
			Acceleration = Vector3.new(0, 2, 0),
		})
	end
	if rarity == "Legendary" or rarity == "Mythic" then
		local light = Instance.new("PointLight")
		light.Color = palette.Glow
		light.Range = 12
		light.Brightness = 1.2
		light.Shadows = false
		light.Parent = body
	end
end

-- Public API -------------------------------------------------------------------

local function overrideModel(speciesId: string): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("CreatureModels")
	local template = folder and folder:FindFirstChild(speciesId)
	if template and template:IsA("Model") and template.PrimaryPart then
		return template:Clone()
	end
	return nil
end

function CreatureRig.HasBuilder(speciesId: string): boolean
	return Builders[speciesId] ~= nil
end

-- Builds a creature at the origin (feet at 0,0,0 facing -Z).
function CreatureRig.Build(speciesId: string, options: Options?): Model
	local opts = options or {}
	local species = CreatureDefinitions.Get(speciesId)
	local mutation = opts.Mutation or "Standard"

	local override = overrideModel(speciesId)
	if override then
		override:SetAttribute("SpeciesId", speciesId)
		override:SetAttribute("Mutation", mutation)
		override:SetAttribute("Idle", if species then species.Idle else "Float")
		local _, size = override:GetBoundingBox()
		override:SetAttribute("Height", size.Y)
		override:SetAttribute("Radius", math.max(size.X, size.Z) / 2)
		return override
	end

	local model = Instance.new("Model")
	model.Name = "Creature"
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.4, 0.4, 0.4)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = CFrame.identity
	root.Parent = model
	model.PrimaryPart = root

	local palette = if species
		then species.Palette
		else {
			Primary = Color3.fromRGB(180, 180, 200),
			Secondary = Color3.fromRGB(140, 140, 170),
			Accent = Color3.fromRGB(116, 229, 254),
			Glow = Color3.fromRGB(200, 240, 255),
		}
	local ctx: Ctx = {
		Model = model,
		Root = root,
		Scale = 1,
		Palette = palette,
		Options = opts,
		MaxY = 0.5,
		MaxR = 0.5,
		Count = 0,
	}
	model:SetAttribute("SpeciesId", speciesId)
	model:SetAttribute("Mutation", mutation)
	model:SetAttribute("Idle", if species then species.Idle else "Float")
	model:SetAttribute("Rarity", if species then species.Rarity else "Common")

	local builder = Builders[speciesId]
	if builder then
		builder(ctx)
	else
		warn(`[CreatureRig] No builder or override model for '{speciesId}' — showing a placeholder orb`)
		buildMystery(ctx)
	end
	if not opts.Silhouette then
		applyMutation(ctx, mutation)
		applyRarityEffects(ctx, if species then species.Rarity else "Common")
	end
	model:SetAttribute("Height", ctx.MaxY)
	model:SetAttribute("Radius", ctx.MaxR)
	return model
end

-- Moves a creature so its feet sit at `cframe`. Works in the workspace and in
-- ViewportFrames (where welds aren't solved), by updating every part directly.
function CreatureRig.Place(model: Model, cframe: CFrame)
	local root = model.PrimaryPart
	if not root then
		return
	end
	root.CFrame = cframe
	local parts = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child ~= root then
			table.insert(parts, child)
		end
	end
	table.sort(parts, function(a, b)
		return ((a:GetAttribute("Order") :: number?) or 0) < ((b:GetAttribute("Order") :: number?) or 0)
	end)
	for _, part in parts do
		local w = part:FindFirstChild("RigWeld")
		if w and w:IsA("Weld") and w.Part0 then
			part.CFrame = w.Part0.CFrame * w.C0 * w.C1:Inverse()
		end
	end
end

-- Uniformly rescales a built model around its Root (used to fit pads).
function CreatureRig.ScaleTo(model: Model, factor: number)
	if math.abs(factor - 1) < 1e-3 then
		return
	end
	local root = model.PrimaryPart
	for _, child in model:GetDescendants() do
		if child:IsA("BasePart") and child ~= root then
			child.Size *= factor
		elseif child:IsA("Weld") and child.Name == "RigWeld" then
			child.C0 = CFrame.new(child.C0.Position * factor) * child.C0.Rotation
		elseif child:IsA("ParticleEmitter") then
			local keypoints = {}
			for _, k in child.Size.Keypoints do
				table.insert(keypoints, NumberSequenceKeypoint.new(k.Time, k.Value * factor, k.Envelope * factor))
			end
			child.Size = NumberSequence.new(keypoints)
		end
	end
	model:SetAttribute("Height", ((model:GetAttribute("Height") :: number?) or 1) * factor)
	model:SetAttribute("Radius", ((model:GetAttribute("Radius") :: number?) or 1) * factor)
	if root then
		CreatureRig.Place(model, root.CFrame)
	end
end

return CreatureRig

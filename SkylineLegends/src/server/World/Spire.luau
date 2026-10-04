-- The Spire: a 25-floor challenge tower rising beside the Guildhall. Each floor
-- is a short enclosed route assembled from the section library, getting harder
-- (and needing more of the movement kit) the higher you go. The roof is a secret.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Districts = require(ReplicatedStorage.Shared.Config.Districts)
local Rotation = require(ReplicatedStorage.Shared.Logic.Rotation)
local Tags = require(ReplicatedStorage.Shared.Tags)

local CourseBuilder = require(script.Parent.CourseBuilder)
local Kit = require(script.Parent.Kit)
local Sections = require(script.Parent.Sections)

local Spire = {}

Spire.Floors = 25
Spire.Roof = nil :: CFrame?

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Abilities each band of floors may use.
local function abilitiesFor(floor: number): { [string]: boolean }
	local set = {}
	if floor >= 6 then
		set.DoubleJump = true
	end
	if floor >= 11 then
		set.Dash = true
	end
	if floor >= 16 then
		set.Grapple = true
	end
	if floor >= 21 then
		set.GrapplePull = true
	end
	return set
end

local THEME: CourseBuilder.Theme = {
	Id = "Spire",
	Surface = rgb(70, 74, 90),
	SurfaceMaterial = Enum.Material.Slate,
	Trim = rgb(255, 196, 92),
	Wall = rgb(120, 126, 150),
	WallMaterial = Enum.Material.Concrete,
	Accent = rgb(255, 196, 92),
	Signal = rgb(80, 200, 255),
	Beam = rgb(150, 105, 70),
	BeamMaterial = Enum.Material.WoodPlanks,
	Rope = rgb(210, 190, 140),
	Climb = "Mesh",
	BodyDepth = 0,
}

-- Returns metas keyed "spire_<n>".
function Spire.Build(world: Instance): { [string]: any }
	local hub = Districts.ById.Hub
	local B = Kit.new(world, "Spire", hub.Palette, Rotation.Hash("Spire"))
	local base = hub.Origin + Districts.SpireOffset
	local toHub = (hub.Origin - base) * Vector3.new(1, 0, 1)
	local facing = CFrame.lookAt(base, base - toHub.Unit)
	local metas = {}

	-- Lobby at hub level.
	B:Box(
		facing * CFrame.new(0, -1, 0),
		Vector3.new(70, 2, 70),
		rgb(70, 74, 90),
		Enum.Material.Slate,
		{ Name = "SpireLobby" }
	)
	B:Box(facing * CFrame.new(0, -40, 0), Vector3.new(66, 76, 66), rgb(110, 116, 140), Enum.Material.Concrete)
	local lift = B:Box(
		facing * CFrame.new(0, 6, 20),
		Vector3.new(10, 12, 2),
		rgb(80, 200, 255),
		Enum.Material.ForceField,
		{ Name = "SpireLift", CanCollide = false }
	)
	B:Prompt(lift, "Ride", "Spire Lift", { Name = "SpirePrompt", Distance = 14, Attrs = { Board = "Tower" } })
	local liftSign = B:Detail(
		facing * CFrame.new(0, 14, 20),
		Vector3.new(14, 2.2, 0.3),
		rgb(25, 28, 36),
		Enum.Material.SmoothPlastic
	)
	B:Text(liftSign, Enum.NormalId.Back, "THE SPIRE · 25 FLOORS", { Color = rgb(80, 200, 255) })

	local floorY = base.Y + 30
	local length = 150
	for floor = 1, Spire.Floors do
		local rng = Rotation.Rng(Rotation.Hash("spire", floor))
		local difficulty = 1 + (floor - 1) * 9 / (Spire.Floors - 1)
		local segments = Sections.Fill(rng, difficulty, abilitiesFor(floor), length - 44, 16)
		table.insert(segments, { "Finish" })
		local direction = if floor % 2 == 1 then 1 else -1
		local start = facing * CFrame.new(0, floorY - base.Y, direction * (length / 2 - 4))
		start = CFrame.lookAt(start.Position, start.Position + facing.LookVector * -direction)
		local course = {
			Id = "spire_" .. floor,
			Name = "Spire Floor " .. floor,
			Kind = "Tower",
			Difficulty = math.clamp(math.floor(difficulty + 0.5), 1, 10),
			Segments = segments,
		}
		local meta = CourseBuilder.Build(B, course, THEME, start)
		meta.District = "Hub"
		meta.Kind = "Tower"
		meta.Difficulty = course.Difficulty
		meta.Floor = floor
		metas[course.Id] = meta

		-- Enclose the floor: glass walls on a steel frame.
		local min, max = meta.LocalMin, meta.LocalMax
		local floorBottom = math.min(min.Y, -4) - 2
		local top = math.max(max.Y, 20) + 6
		local height = top - floorBottom
		local center = start * CFrame.new((min.X + max.X) / 2, floorBottom + height / 2, (min.Z + max.Z) / 2)
		local sizeX = math.max(max.X - min.X, 40) + 12
		local sizeZ = (max.Z - min.Z) + 14
		B:Box(
			center * CFrame.new(0, -height / 2 - 1, 0),
			Vector3.new(sizeX, 2, sizeZ),
			rgb(60, 64, 80),
			Enum.Material.Slate,
			{ Name = "FloorSlab" }
		)
		for _, s in { -1, 1 } do
			B:Box(
				center * CFrame.new(s * sizeX / 2, 0, 0),
				Vector3.new(1, height, sizeZ),
				rgb(150, 200, 230),
				Enum.Material.Glass,
				{ Transparency = 0.55, Name = "SpireGlass" }
			)
			B:Box(
				center * CFrame.new(0, 0, s * sizeZ / 2),
				Vector3.new(sizeX, height, 1),
				rgb(150, 200, 230),
				Enum.Material.Glass,
				{ Transparency = 0.55, Name = "SpireGlass" }
			)
			for _, t in { -1, 1 } do
				B:Detail(
					center * CFrame.new(s * sizeX / 2, 0, t * sizeZ / 2),
					Vector3.new(2, height, 2),
					rgb(60, 64, 80),
					Enum.Material.Metal,
					{ CanCollide = true }
				)
			end
		end
		B:Box(
			center * CFrame.new(0, height / 2 + 1, 0),
			Vector3.new(sizeX + 2, 2, sizeZ + 2),
			rgb(60, 64, 80),
			Enum.Material.Slate,
			{ Name = "FloorCeiling" }
		)
		local band = B:Detail(
			center * CFrame.new(0, height / 2 - 0.6, sizeZ / 2 + 0.6),
			Vector3.new(sizeX, 1, 0.2),
			if floor % 5 == 0 then rgb(255, 196, 92) else rgb(80, 200, 255),
			Enum.Material.Neon
		)
		B:Light(band, rgb(200, 230, 255), 50, 1, "Spot", Enum.NormalId.Bottom)
		local label = B:Detail(
			start * CFrame.new(-7, 7, -6),
			Vector3.new(0.3, 3, 6),
			rgb(25, 28, 36),
			Enum.Material.SmoothPlastic
		)
		B:Text(label, Enum.NormalId.Right, "FLOOR " .. floor, { Color = rgb(80, 200, 255) })
		B:Text(label, Enum.NormalId.Left, "FLOOR " .. floor, { Color = rgb(80, 200, 255) })
		B:FarBox(center, Vector3.new(sizeX, height, sizeZ), rgb(150, 200, 230), Enum.Material.Glass)
		floorY = start.Y + top + 10
	end

	-- The roof: a ladder out of the last floor's ceiling, and the secret above it all.
	local roofCF = facing * CFrame.new(0, floorY - base.Y, 0)
	B:Box(
		roofCF * CFrame.new(0, -1, 0),
		Vector3.new(40, 2, 40),
		rgb(60, 64, 80),
		Enum.Material.Slate,
		{ Name = "SpireRoof" }
	)
	local beacon = B:Ball(
		roofCF.Position + Vector3.new(0, 12, 0),
		5,
		rgb(255, 196, 92),
		Enum.Material.Neon,
		{ Name = "SpireBeacon", CanCollide = false }
	)
	B:Light(beacon, rgb(255, 196, 92), 60, 2)
	B:FarBox(
		CFrame.new(roofCF.Position + Vector3.new(0, 12, 0)),
		Vector3.new(5, 5, 5),
		rgb(255, 196, 92),
		Enum.Material.Neon
	)
	B:Volume(roofCF * CFrame.new(0, 4, 0), Vector3.new(40, 8, 40), Tags.Discovery, {
		Id = "secret_spire",
		Kind = "Secret",
		District = "Hub",
		Title = "Roof of the Spire",
		Text = "The highest point in Meridian. The whole city is laid out below you.",
	})
	Spire.Roof = roofCF * CFrame.new(0, 3.5, 0)
	return metas
end

return Spire

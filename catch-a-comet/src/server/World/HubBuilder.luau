-- Celestial Crossing: the central hub island.
--
-- The ancient observatory with its turning armillary sphere sits in the
-- middle. Around it: the spawn plaza and promenade (south), the guiding
-- comet's landing spot and the examination station, the Equipment Workshop
-- (west), the mission board and leaderboard (by the spawn), the Dawn Commons
-- gate (east), sealed portals to future biomes (north), radial paths to the
-- twelve sanctuary bridges, crystal sculptures, banners, trees and waterfalls.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BiomeDefinitions = require(Shared.BiomeDefinitions)
local Format = require(Shared.Format)
local WorldLayout = require(Shared.WorldLayout)

local Kit = require(script.Parent.Kit)

local HubBuilder = {}

local C = Kit.Colors
local M = Enum.Material
local HUB = WorldLayout.Hub
local GROUND = WorldLayout.GroundY

export type PortalInfo = { Part: BasePart, Destination: string, Biome: string }

export type HubInfo = {
	Spawn: SpawnLocation,
	Portals: { PortalInfo },
	LeaderboardRows: { TextLabel },
	Model: Model,
}

local function flat(angleDeg: number, radius: number, y: number?): Vector3
	return WorldLayout.Polar(angleDeg, radius, y or GROUND)
end

-- Distance from point p to the radial path at `angleDeg` between radii r0 and r1.
local function distanceToRadial(p: Vector3, angleDeg: number, r0: number, r1: number): number
	local dir = Vector3.new(math.cos(math.rad(angleDeg)), 0, math.sin(math.rad(angleDeg)))
	local flatP = Vector3.new(p.X, 0, p.Z)
	local t = math.clamp(flatP:Dot(dir), r0, r1)
	return (flatP - dir * t).Magnitude
end

local function pathAngles(): { number }
	local angles = { 0, 90, 180 }
	for i = 1, WorldLayout.Sanctuary.Count do
		table.insert(angles, WorldLayout.Plots[i].Angle)
	end
	return angles
end

local function buildPaths(model: Model)
	local paths = Kit.Folder("Paths", model)
	for _, angle in pathAngles() do
		local r0, r1, width = 48, WorldLayout.Hub.Radius - 1, 9
		if angle == 90 then
			r0, r1, width = 48, 112, 12 -- the promenade to the spawn plaza
		elseif angle == 0 then
			r1 = 128
		elseif angle == 180 then
			r1 = 104
		end
		local a = flat(angle, r0, GROUND + 0.3)
		local b = flat(angle, r1, GROUND + 0.3)
		local mid = (a + b) / 2
		Kit.Part(paths, Vector3.new(width, 0.8, (b - a).Magnitude), CFrame.lookAt(mid, b) * CFrame.new(0, -0.1, 0), {
			Name = "Path",
			Color = Color3.fromRGB(214, 206, 236),
			Material = M.Pavement,
			CastShadow = false,
		})
		-- Lanterns where each path leaves the plaza.
		local side = CFrame.lookAt(a, b).RightVector
		Kit.Lantern(paths, flat(angle, 58) + side * (width / 2 + 1.5), C.Gold, angle % 60 == 15 or angle == 90)
	end
end

local function buildObservatory(model: Model)
	local obs = Kit.Model("Observatory", model)
	obs.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local base = Vector3.new(0, GROUND, 0)
	Kit.Disc(obs, 100, 1.2, base + Vector3.new(0, 0.6, 0), C.Marble, M.Marble)
	Kit.Ring(obs, CFrame.new(base + Vector3.new(0, 0.65, 0)), 46, Vector2.new(0.7, 0.2), 56, C.Gold, M.Neon)
	Kit.Ring(obs, CFrame.new(base + Vector3.new(0, 0.65, 0)), 40, Vector2.new(0.35, 0.2), 48, C.Lavender, M.Neon)
	Kit.Disc(obs, 70, 1, base + Vector3.new(0, 1.6, 0), C.MarbleShade, M.Marble)
	Kit.Disc(obs, 62, 1, base + Vector3.new(0, 2.6, 0), C.Marble, M.Marble)

	local pillarTop = GROUND + 2.6 + 24
	for i = 0, 9 do
		local angle = i * 36 + 18
		local p = flat(angle, 28, GROUND + 2.6)
		Kit.Block(obs, Vector3.new(4, 1, 4), CFrame.new(p + Vector3.new(0, 0.5, 0)), C.MarbleShade, M.Marble)
		local pillar = Kit.Column(obs, 3.2, 24, p, C.Marble, M.Marble)
		pillar.CastShadow = true
		Kit.Block(obs, Vector3.new(4.4, 1.2, 4.4), CFrame.new(p.X, pillarTop + 0.6, p.Z), C.MarbleShade, M.Marble)
		-- Rib arcing from the pillar to the apex.
		local previous = Vector3.new(p.X, pillarTop + 1.2, p.Z)
		for k = 1, 7 do
			local phi = math.rad(k / 7 * 90)
			local r = 28 * math.cos(phi)
			local point = flat(angle, r, pillarTop + 1.2 + 22 * math.sin(phi))
			local mid = (previous + point) / 2
			Kit.Part(obs, Vector3.new(1.3, 1.3, (point - previous).Magnitude + 0.3), CFrame.lookAt(mid, point), {
				Color = C.MarbleShade,
				Material = M.Marble,
				Decor = true,
			})
			previous = point
		end
	end
	Kit.Ring(obs, CFrame.new(0, pillarTop + 1.6, 0), 28, Vector2.new(3, 2), 40, C.Marble, M.Marble, false)
	local apex = Kit.Ball(obs, 3.2, Vector3.new(0, pillarTop + 24, 0), C.Gold, M.Neon)
	Kit.Light(apex, C.Gold, 30, 1.2)

	-- Pedestal and the armillary sphere.
	Kit.Column(obs, 9, 2, base + Vector3.new(0, 2.6, 0), C.MarbleShade, M.Marble)
	Kit.Column(obs, 5, 4, base + Vector3.new(0, 4.6, 0), C.Marble, M.Marble)
	Kit.Column(obs, 2.4, 4.5, base + Vector3.new(0, 8.6, 0), C.Gold, M.Metal)
	local center = CFrame.new(0, GROUND + 18, 0)
	local core = Kit.Ball(obs, 6, center.Position, Color3.fromRGB(240, 232, 255), M.Neon)
	Kit.Light(core, C.Lavender, 46, 2)
	Kit.Emitter(core, {
		Color = ColorSequence.new(C.Lavender, C.Cyan),
		Rate = 6,
		Speed = NumberRange.new(2, 4),
		Lifetime = NumberRange.new(1.5, 2.5),
	})
	local rings = {
		{ Tilt = CFrame.identity, Radius = 9, Speed = 0.25, Color = C.Gold },
		{ Tilt = CFrame.Angles(math.rad(90), 0, 0), Radius = 10.5, Speed = -0.18, Color = C.Gold },
		{ Tilt = CFrame.Angles(math.rad(35), 0, math.rad(60)), Radius = 12.5, Speed = 0.12, Color = C.Cyan },
	}
	for i, spec in rings do
		local ringModel, root = Kit.Animated(obs, "ArmillaryRing" .. i, center * spec.Tilt, "Spinner", {
			SpinAxis = "Y",
			SpinSpeed = spec.Speed,
		})
		for _, part in Kit.Ring(ringModel, root.CFrame, spec.Radius, Vector2.new(0.7, 0.7), 36, spec.Color, M.Neon) do
			Kit.WeldTo(part, root)
		end
	end
end

local function buildCrystals(model: Model, rng: Random)
	local folder = Kit.Folder("Crystals", model)
	for _, angle in { 30, 150, 210, 270, 330 } do
		local base = flat(angle, 64)
		Kit.Column(folder, 6, 2.5, base, C.MarbleShade, M.Marble)
		local center = CFrame.new(base + Vector3.new(0, 8, 0))
		local crystalModel, root = Kit.Animated(folder, "Crystal", center, "Bobber", {
			BobAmount = 1.1,
			BobSpeed = 0.7 + rng:NextNumber() * 0.4,
			SpinSpeed = 0.25,
		})
		local color = if rng:NextNumber() > 0.5 then C.Cyan else C.Lavender
		for k = 1, 4 do
			local h = 5 - k * 0.8
			local tilt = CFrame.Angles(
				math.rad((rng:NextNumber() - 0.5) * 40),
				rng:NextNumber() * 6,
				math.rad((rng:NextNumber() - 0.5) * 40)
			)
			local part = Kit.Block(
				crystalModel,
				Vector3.new(1.4, h, 1.4),
				center * tilt * CFrame.new(0, (k - 2) * 0.4, 0) * CFrame.Angles(0, math.rad(45), 0),
				color,
				if k == 1 then M.Neon else M.Glass,
				true
			)
			part.Transparency = if k == 1 then 0 else 0.25
			Kit.WeldTo(part, root)
		end
	end
end

local function buildSpawn(model: Model): SpawnLocation
	local folder = Kit.Model("SpawnPlaza", model)
	local center = HUB.Spawn.Position - Vector3.new(0, 3, 0)
	Kit.Disc(folder, 28, 1, center + Vector3.new(0, 0.8, 0), C.Marble, M.Marble)
	Kit.Ring(folder, CFrame.new(center + Vector3.new(0, 0.85, 0)), 12.5, Vector2.new(0.6, 0.2), 32, C.Gold, M.Neon)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.lookAt(center + Vector3.new(0, 1.3, 0), center + Vector3.new(0, 1.3, -10))
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 1
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Enabled = true
	spawn.Parent = folder
	for _, side in { -1, 1 } do
		Kit.Lantern(folder, center + Vector3.new(side * 16, 0, -4), C.Gold, true)
	end
	return spawn
end

local function buildExaminationStation(model: Model)
	local folder = Kit.Model("ExaminationStation", model)
	local base = HUB.ExaminationStation
	Kit.Disc(folder, 14, 1, base + Vector3.new(0, 0.8, 0), C.MarbleShade, M.Marble)
	local desk = Kit.Block(folder, Vector3.new(6, 3, 3), CFrame.new(base + Vector3.new(0, 2.3, 0)), C.WoodDark, M.Wood)
	Kit.Ball(folder, 2.2, base + Vector3.new(0, 4.7, 0), Color3.fromRGB(70, 60, 100), M.Slate)
	Kit.Ball(folder, 0.6, base + Vector3.new(0.5, 5.3, -0.6), C.Cyan, M.Neon)
	local dome = Kit.Ball(folder, 3.4, base + Vector3.new(0, 4.8, 0), Color3.fromRGB(220, 240, 255), M.Glass)
	dome.Transparency = 0.6
	local scopeBase = base + Vector3.new(4.5, 0.8, 1.5)
	Kit.Column(folder, 0.4, 4, scopeBase, C.StoneDark, M.Metal)
	Kit.Part(
		folder,
		Vector3.new(4, 0.9, 0.9),
		CFrame.new(scopeBase + Vector3.new(0, 4.6, 0)) * CFrame.Angles(0, math.rad(30), math.rad(35)),
		{
			Shape = Enum.PartType.Cylinder,
			Color = C.Gold,
			Material = M.Metal,
			Decor = true,
		}
	)
	Kit.Billboard(
		desk,
		"Comet Examination",
		"Open sealed cores here — or anywhere",
		{ Offset = Vector3.new(0, 6, 0), MaxDistance = 70 }
	)
	Kit.Prompt(desk, "OpenCores", "Examine Cores", "Comet Examination", 12)
end

local function buildWorkshop(model: Model)
	local folder = Kit.Model("Workshop", model)
	folder.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local base = HUB.Workshop
	-- Faces east, toward the observatory.
	local frame = CFrame.lookAt(base, base + Vector3.new(1, 0, 0))
	Kit.Part(folder, Vector3.new(28, 1, 26), frame * CFrame.new(0, 0.3, 0), { Color = C.Wood, Material = M.WoodPlanks })
	for _, corner in { Vector2.new(-12, -11), Vector2.new(12, -11), Vector2.new(-12, 11), Vector2.new(12, 11) } do
		local p = (frame * CFrame.new(corner.X, 0.8, corner.Y)).Position
		Kit.Column(folder, 2, 14, p, C.MarbleShade, M.Marble)
	end
	Kit.Part(
		folder,
		Vector3.new(30, 1.4, 28),
		frame * CFrame.new(0, 15.5, 0),
		{ Color = C.StoneDark, Material = M.Slate }
	)
	Kit.Part(
		folder,
		Vector3.new(22, 1, 20),
		frame * CFrame.new(0, 16.7, 0),
		{ Color = C.Lavender, Material = M.SmoothPlastic, Decor = true }
	)
	for _, z in { -14.2, 14.2 } do
		Kit.Part(
			folder,
			Vector3.new(30.4, 0.4, 0.4),
			frame * CFrame.new(0, 14.8, z),
			{ Color = C.Cyan, Material = M.Neon, Decor = true }
		)
	end
	local back = Kit.Part(
		folder,
		Vector3.new(26, 13, 1),
		frame * CFrame.new(0, 7.3, 12.5),
		{ Color = C.Marble, Material = M.Marble }
	)
	Kit.Sign(back, Enum.NormalId.Front, { "EQUIPMENT WORKSHOP", "Scanner · Tether · Habitats" })
	local bench = Kit.Part(
		folder,
		Vector3.new(12, 3, 4),
		frame * CFrame.new(0, 2.3, 4),
		{ Color = C.WoodDark, Material = M.Wood }
	)
	Kit.Part(
		folder,
		Vector3.new(12.6, 0.4, 4.6),
		frame * CFrame.new(0, 3.95, 4),
		{ Color = C.Gold, Material = M.Metal }
	)
	Kit.Prompt(bench, "OpenWorkshop", "Upgrade Equipment", "Workshop", 16)
	Kit.Billboard(bench, "Workshop", "Upgrade your equipment", { Offset = Vector3.new(0, 9, 0), MaxDistance = 120 })
	-- A big spinning tether ring above the bench.
	local ringModel, root = Kit.Animated(
		folder,
		"TetherSculpture",
		frame * CFrame.new(0, 9, 4) * CFrame.Angles(math.rad(90), 0, 0),
		"Spinner",
		{
			SpinAxis = "Y",
			SpinSpeed = 0.6,
		}
	)
	for _, part in Kit.Ring(ringModel, root.CFrame, 3.5, Vector2.new(0.5, 0.5), 20, C.Cyan, M.Neon) do
		Kit.WeldTo(part, root)
	end
	local orb = Kit.Ball(ringModel, 1.6, root.CFrame.Position, Color3.new(1, 1, 1), M.Neon)
	Kit.WeldTo(orb, root)
	Kit.Light(orb, C.Cyan, 18, 1)
end

local function buildBoards(model: Model): { TextLabel }
	-- Mission board: faces the promenade (west).
	local missions = Kit.Model("MissionBoard", model)
	local mBase = HUB.MissionBoard
	local mFrame = CFrame.lookAt(mBase, mBase + Vector3.new(-1, 0, 0))
	for _, x in { -5.5, 5.5 } do
		Kit.Part(
			missions,
			Vector3.new(0.8, 9, 0.8),
			mFrame * CFrame.new(x, 4.5, 0),
			{ Color = C.WoodDark, Material = M.Wood }
		)
	end
	local board = Kit.Part(
		missions,
		Vector3.new(11, 7, 0.6),
		mFrame * CFrame.new(0, 6, 0),
		{ Color = C.Wood, Material = M.WoodPlanks }
	)
	Kit.Sign(board, Enum.NormalId.Front, { "MISSIONS", "New goals for explorers" })
	Kit.Part(
		missions,
		Vector3.new(12, 0.8, 1.6),
		mFrame * CFrame.new(0, 9.9, 0),
		{ Color = C.StoneDark, Material = M.Slate }
	)
	Kit.Prompt(board, "OpenQuests", "View Missions", "Mission Board", 14)

	-- Leaderboard monument: faces the promenade (east).
	local leaders = Kit.Model("Leaderboard", model)
	local lBase = HUB.Leaderboard
	local lFrame = CFrame.lookAt(lBase, lBase + Vector3.new(1, 0, 0))
	Kit.Part(
		leaders,
		Vector3.new(11, 1.5, 4),
		lFrame * CFrame.new(0, 0.75, 0),
		{ Color = C.MarbleShade, Material = M.Marble }
	)
	local slab = Kit.Part(
		leaders,
		Vector3.new(9, 14, 1.6),
		lFrame * CFrame.new(0, 8.5, 0),
		{ Color = Color3.fromRGB(40, 44, 84), Material = M.Slate }
	)
	Kit.Ball(leaders, 2, (lFrame * CFrame.new(0, 16.6, 0)).Position, C.Gold, M.Neon)

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Leaderboard"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Adornee = slab
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0.12)
	title.Position = UDim2.fromScale(0, 0.03)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.Text = "TOP COLLECTORS"
	title.TextColor3 = C.Gold
	title.Parent = gui
	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Size = UDim2.fromScale(1, 0.06)
	sub.Position = UDim2.fromScale(0, 0.15)
	sub.Font = Enum.Font.BuilderSansBold
	sub.TextScaled = true
	sub.Text = "species discovered · this server"
	sub.TextColor3 = Color3.fromRGB(169, 178, 214)
	sub.Parent = gui
	local rows = {}
	for i = 1, 8 do
		local row = Instance.new("TextLabel")
		row.Name = "Row" .. i
		row.BackgroundTransparency = 1
		row.Size = UDim2.fromScale(0.9, 0.08)
		row.Position = UDim2.fromScale(0.05, 0.23 + (i - 1) * 0.095)
		row.Font = Enum.Font.BuilderSansBold
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = Color3.fromRGB(245, 247, 255)
		row.Text = ""
		row.Parent = gui
		table.insert(rows, row)
	end
	gui.Parent = slab
	return rows
end

local function buildPortal(
	model: Model,
	position: Vector3,
	color: Color3,
	title: string,
	subtitle: string,
	destination: string,
	biomeId: string,
	sealed: boolean
): PortalInfo
	local folder = Kit.Model("Portal_" .. biomeId, model)
	folder.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local frame = CFrame.lookAt(position, Vector3.new(0, position.Y, 0))
	for _, side in { -1, 1 } do
		local p = (frame * CFrame.new(side * 7.5, 0, 0)).Position
		Kit.Column(folder, 2.6, 16, p, C.Marble, M.Marble)
		Kit.Ball(folder, 1.6, p + Vector3.new(0, 16.8, 0), color, M.Neon)
	end
	for k = 0, 10 do
		local a = math.rad(k / 10 * 180)
		local point = (frame * CFrame.new(math.cos(a) * 7.5, 16 + math.sin(a) * 5, 0)).Position
		Kit.Block(
			folder,
			Vector3.new(2, 2, 2),
			CFrame.new(point) * frame.Rotation * CFrame.Angles(0, 0, a),
			C.MarbleShade,
			M.Marble,
			true
		)
	end
	local plane = Kit.Part(folder, Vector3.new(13, 15, 0.6), frame * CFrame.new(0, 8.6, 0), {
		Name = "PortalPlane",
		Color = color,
		Material = M.Glass,
		Transparency = if sealed then 0.65 else 0.35,
		CanCollide = false,
		CastShadow = false,
	})
	plane.CanQuery = false
	plane.CanTouch = true
	plane:SetAttribute("Destination", destination)
	plane:SetAttribute("Biome", biomeId)
	Kit.Emitter(plane, {
		Color = ColorSequence.new(color),
		Rate = if sealed then 2 else 10,
		Speed = NumberRange.new(0.5, 2),
		Lifetime = NumberRange.new(1, 2),
	})
	if not sealed then
		Kit.Light(plane, color, 20, 1.2)
	end
	Kit.Billboard(plane, title, subtitle, {
		Offset = Vector3.new(0, 13, 0),
		MaxDistance = 180,
		Width = 300,
		SubColor = if sealed then Color3.fromRGB(169, 178, 214) else C.Gold,
	})
	return { Part = plane, Destination = destination, Biome = biomeId }
end

local function buildPortals(model: Model): { PortalInfo }
	local portals = {}
	local dawn = BiomeDefinitions.Biomes.DawnCommons
	table.insert(
		portals,
		buildPortal(
			model,
			HUB.DawnGate,
			dawn.Color,
			dawn.DisplayName,
			dawn.Tagline,
			"DawnCommons",
			"DawnCommons",
			false
		)
	)
	for biomeId, angle in HUB.PortalAngles do
		local biome = BiomeDefinitions.Biomes[biomeId]
		local subtitle =
			`Lv {biome.Unlock.Level} · {Format.Short(biome.Unlock.Stardust)} Stardust · Charting in progress`
		table.insert(
			portals,
			buildPortal(
				model,
				flat(angle, HUB.PortalRadius),
				biome.Color,
				biome.DisplayName,
				subtitle,
				biomeId,
				biomeId,
				true
			)
		)
	end
	return portals
end

local function buildWaterfall(model: Model, angle: number)
	local folder = Kit.Model("Waterfall", model)
	local edge = flat(angle, WorldLayout.Hub.Radius + 1.5, GROUND - 1)
	local outward = Vector3.new(edge.X, 0, edge.Z).Unit
	Kit.Terrain.Block(
		CFrame.lookAt(edge - outward * 10, edge) * CFrame.new(0, 0, 0),
		Vector3.new(10, 3, 18),
		Enum.Material.Water
	)
	local frame = CFrame.lookAt(edge, edge + outward)
	local fall = Kit.Part(folder, Vector3.new(9, 90, 1), frame * CFrame.new(0, -45, -1.5), {
		Name = "Fall",
		Color = Color3.fromRGB(170, 230, 255),
		Material = M.Glass,
		Transparency = 0.35,
		Decor = true,
		CastShadow = false,
	})
	Kit.Emitter(fall, {
		Texture = Kit.Textures.Smoke,
		LightEmission = 0.3,
		Color = ColorSequence.new(Color3.fromRGB(230, 245, 255)),
		Rate = 6,
		Lifetime = NumberRange.new(2, 3),
		Speed = NumberRange.new(4, 8),
		Acceleration = Vector3.new(0, -6, 0),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 8) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) }),
	})
end

local function buildBanners(model: Model)
	local folder = Kit.Folder("Banners", model)
	local colors = { C.Lavender, C.Cyan, C.Gold, C.Coral }
	for i, angle in { 60, 120, 240, 300 } do
		local base = flat(angle, 53)
		Kit.Column(folder, 0.6, 15, base, C.StoneDark, M.Metal)
		local top = CFrame.lookAt(base + Vector3.new(0, 14.5, 0), Vector3.new(0, base.Y + 14.5, 0))
		local bannerModel, root =
			Kit.Animated(folder, "Banner", top, "Sway", { SwayAmount = 6, SwaySpeed = 1.1 + (i % 3) * 0.2 })
		local cloth = Kit.Block(
			bannerModel,
			Vector3.new(3.4, 7, 0.15),
			top * CFrame.new(0, -3.6, -0.4),
			colors[i % #colors + 1],
			M.Fabric,
			true
		)
		Kit.WeldTo(cloth, root)
		local star = Kit.Block(
			bannerModel,
			Vector3.new(1, 1, 0.2),
			top * CFrame.new(0, -3, -0.55) * CFrame.Angles(0, 0, math.rad(45)),
			Color3.new(1, 1, 1),
			M.Neon,
			true
		)
		Kit.WeldTo(star, root)
	end
end

local function decorate(model: Model, rng: Random)
	local folder = Kit.Folder("Decor", model)
	local blocked = {
		{ Position = Vector3.zero, Radius = 56 },
		{ Position = HUB.Spawn.Position, Radius = 20 },
		{ Position = HUB.TutorialImpact, Radius = 16 },
		{ Position = HUB.ExaminationStation, Radius = 12 },
		{ Position = HUB.Workshop, Radius = 24 },
		{ Position = HUB.MissionBoard, Radius = 12 },
		{ Position = HUB.Leaderboard, Radius = 12 },
		{ Position = HUB.DawnGate, Radius = 14 },
	}
	for _, angle in HUB.PortalAngles do
		table.insert(blocked, { Position = flat(angle, HUB.PortalRadius), Radius = 14 })
	end
	for _, angle in { 30, 150, 210, 270, 330 } do
		table.insert(blocked, { Position = flat(angle, 64), Radius = 8 })
	end
	local function clearOfPaths(p: Vector3): boolean
		for _, angle in pathAngles() do
			if distanceToRadial(p, angle, 40, 170) < 9 then
				return false
			end
		end
		return true
	end
	local candidates = Kit.ScatterPoints(rng, Vector3.new(0, GROUND, 0), 150, 80, 14, blocked)
	local trees, flowers = 0, 0
	for _, p in candidates do
		if Vector3.new(p.X, 0, p.Z).Magnitude < 70 or not clearOfPaths(p) then
			continue
		end
		if trees < 24 then
			Kit.Tree(folder, rng, p, 0.9 + rng:NextNumber() * 0.4)
			trees += 1
		elseif flowers < 16 then
			Kit.Flowers(folder, rng, p, 4, 10)
			flowers += 1
		end
	end
end

function HubBuilder.Build(parent: Instance, rng: Random): HubInfo
	local model = Kit.Model("Hub", parent)
	Kit.Island(rng, Vector3.new(0, GROUND, 0), WorldLayout.Hub.Radius)
	buildPaths(model)
	buildObservatory(model)
	buildCrystals(model, rng)
	local spawn = buildSpawn(model)
	buildExaminationStation(model)
	buildWorkshop(model)
	local rows = buildBoards(model)
	local portals = buildPortals(model)
	buildWaterfall(model, 150)
	buildWaterfall(model, 300)
	buildBanners(model)
	decorate(model, rng)
	return {
		Spawn = spawn,
		Portals = portals,
		LeaderboardRows = rows,
		Model = model,
	}
end

return HubBuilder

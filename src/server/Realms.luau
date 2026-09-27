-- Extra realms, reached through portals at the spawn plaza:
--
--   Neon City   — floating skyscrapers with glowing trim, billboards and rooftop
--                 launch pads over a synthwave grid. Wall-run the alleys.
--   Ember Isles — volcanic basalt islands, lava pools and lavafalls, obsidian
--                 spires and an erupting volcano, over a sea of glowing lava.
--
-- Each realm is built far from the Sky Islands (see Config.Realms). Portals
-- check the player's level before letting them through.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MathUtil = require(ReplicatedStorage.Shared.MathUtil)
local Net = require(ReplicatedStorage.Shared.Net)
local PlayerData = require(script.Parent.PlayerData)
local Progression = require(script.Parent.Progression)
local WorldBuilder = require(script.Parent.WorldBuilder)

local Kit = WorldBuilder.Kit
local Flat = MathUtil.Flat
local Terrain = workspace.Terrain
local M = Enum.Material
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local NEON_PALETTE = {
	Color3.fromRGB(255, 60, 220),
	Color3.fromRGB(60, 240, 255),
	Color3.fromRGB(150, 80, 255),
	Color3.fromRGB(255, 150, 60),
}
local BILLBOARD_TEXT = { "SKYBOUND", "RUN THE WALLS", "NEON", "HOOK IT", "FLY", "NO GROUND", "ZOOM", "SPEED" }
local LAVA = Color3.fromRGB(255, 110, 30)
local OBSIDIAN = Color3.fromRGB(24, 20, 30)

local Realms = {}

-- Where a portal drops you in each realm.
local arrivals: { [string]: CFrame } = {
	sky = CFrame.new(0, 106, -16),
}
local portalCooldown: { [Player]: number } = {}

-- Portals -----------------------------------------------------------------------------

local function travel(player: Player, realmId: string)
	local realm = Config.GetRealm(realmId)
	local arrival = arrivals[realmId]
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not realm or not arrival or not character or not humanoid or humanoid.Health <= 0 then
		return
	end
	local now = os.clock()
	if now - (portalCooldown[player] or 0) < 2 then
		return
	end
	portalCooldown[player] = now
	local notify = Net.Event("Notify")
	if (player:GetAttribute("Level") or 1) < realm.Level then
		notify:FireClient(player, "Locked", { Name = realm.Name, Level = realm.Level })
		return
	end
	character:PivotTo(arrival)
	Progression.Record(player, "RealmVisit")
	local data = PlayerData.Get(player)
	if data and not data.RealmsVisited[realmId] then
		data.RealmsVisited[realmId] = true
		local count = 0
		for _ in data.RealmsVisited do
			count += 1
		end
		Progression.Record(player, "Realms", count)
	end
	notify:FireClient(player, "Realm", { Id = realmId, Name = realm.Name })
end

local function portal(parent: Instance, center: Vector3, facing: Vector3, target: string)
	local realm = Config.GetRealm(target)
	if not realm then
		return
	end
	local model = Instance.new("Model")
	model.Name = "Portal_" .. target
	local look = CFrame.lookAt(center, center + Flat(facing).Unit)
	-- Standing ring, turning slowly.
	Kit.SpinnerRing(model, center, 7.5, look.Rotation * CFrame.Angles(math.pi / 2, 0, 0), 0.25, realm.Color)
	local disc = Kit.Part({
		Name = "PortalDisc",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 13, 13),
		CFrame = look * CFrame.Angles(0, math.pi / 2, 0),
		Material = M.Neon,
		Color = realm.Color,
		Transparency = 0.35,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	}, model)
	Kit.Emitter(disc, {
		Texture = SPARKLE,
		Color = ColorSequence.new(realm.Color),
		LightEmission = 1,
		Rate = 18,
		Lifetime = NumberRange.new(0.6, 1.2),
		Speed = NumberRange.new(2, 5),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
	})
	local light = Instance.new("PointLight")
	light.Color = realm.Color
	light.Range = 22
	light.Brightness = 2
	light.Parent = disc

	local label = Instance.new("BillboardGui")
	label.Size = UDim2.fromOffset(240, 60)
	label.StudsOffset = Vector3.new(0, 10, 0)
	label.MaxDistance = 250
	label.LightInfluence = 0
	label.Parent = disc
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBlack
	text.TextScaled = true
	text.RichText = true
	text.TextColor3 = realm.Color
	text.TextStrokeTransparency = 0.3
	text.Text = string.upper(realm.Name)
		.. (if realm.Level > 1 then "\n<font size='16'>UNLOCKS AT LV " .. realm.Level .. "</font>" else "")
	text.Parent = label

	disc.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if player then
			travel(player, target)
		end
	end)
	model.Parent = parent
end

-- Neon City ---------------------------------------------------------------------------

local function billboard(parent: Instance, tower: BasePart, rng: Random)
	local size = tower.Size
	local face = rng:NextInteger(1, 4)
	local offsets = {
		CFrame.new(0, 0, -size.Z / 2 - 0.6),
		CFrame.new(0, 0, size.Z / 2 + 0.6) * CFrame.Angles(0, math.pi, 0),
		CFrame.new(size.X / 2 + 0.6, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0),
		CFrame.new(-size.X / 2 - 0.6, 0, 0) * CFrame.Angles(0, math.pi / 2, 0),
	}
	local width = (if face <= 2 then size.X else size.Z) * 0.7
	local height = rng:NextNumber(10, 18)
	local y = size.Y / 2 - rng:NextNumber(30, 80)
	local panel = Kit.Decor({
		Name = "Billboard",
		Size = Vector3.new(width, height, 0.5),
		CFrame = tower.CFrame * CFrame.new(0, y, 0) * offsets[face],
		Color = Color3.fromRGB(10, 8, 20),
	}, parent)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.Brightness = 2
	gui.PixelsPerStud = 20
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.Parent = panel
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBlack
	text.TextScaled = true
	text.TextColor3 = NEON_PALETTE[rng:NextInteger(1, #NEON_PALETTE)]
	text.Text = BILLBOARD_TEXT[rng:NextInteger(1, #BILLBOARD_TEXT)]
	text.Parent = gui
end

local function tower(parent: Instance, base: Vector3, rng: Random)
	local width, depth = rng:NextNumber(28, 55), rng:NextNumber(28, 55)
	local top = rng:NextNumber(130, 420)
	local bottom = -140
	local height = top - bottom
	local accent = NEON_PALETTE[rng:NextInteger(1, #NEON_PALETTE)]
	local model = Instance.new("Model")
	model.Name = "Tower"
	local body = Kit.Part({
		Name = "Tower",
		Size = Vector3.new(width, height, depth),
		Position = Vector3.new(base.X, bottom + height / 2, base.Z),
		Color = Color3.fromRGB(rng:NextInteger(16, 30), rng:NextInteger(16, 28), rng:NextInteger(32, 50)),
		Material = M.SmoothPlastic,
		Reflectance = 0.08,
	}, model)
	-- Glowing bands down the building (decor, so they don't catch wall-runs).
	for i = 0, 3 do
		Kit.Decor({
			Name = "Band",
			Size = Vector3.new(width + 0.6, 0.8, depth + 0.6),
			Position = Vector3.new(base.X, top - 6 - i * rng:NextNumber(28, 45), base.Z),
			Material = M.Neon,
			Color = accent,
			CastShadow = false,
		}, model)
	end
	-- Corner light strips.
	for _, corner in { Vector3.new(1, 0, 1), Vector3.new(-1, 0, -1) } do
		Kit.Decor({
			Name = "Edge",
			Size = Vector3.new(0.7, height, 0.7),
			Position = Vector3.new(base.X + corner.X * width / 2, bottom + height / 2, base.Z + corner.Z * depth / 2),
			Material = M.Neon,
			Color = accent,
			CastShadow = false,
		}, model)
	end
	-- Roof: a rim, an antenna with a beacon light, maybe a launch pad and shards.
	Kit.Part({
		Name = "Roof",
		Size = Vector3.new(width + 2, 1.5, depth + 2),
		Position = Vector3.new(base.X, top + 0.75, base.Z),
		Material = M.DiamondPlate,
		Color = Color3.fromRGB(45, 45, 60),
	}, model)
	local antennaBase = Vector3.new(base.X + width * 0.3, top + 1.5, base.Z - depth * 0.3)
	Kit.Cylinder(
		model,
		antennaBase + Vector3.new(0, 10, 0),
		20,
		0.4,
		{ Name = "Antenna", Color = Color3.fromRGB(80, 80, 95) }
	)
	local tip = Kit.Part({
		Name = "Beacon",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1.6,
		Position = antennaBase + Vector3.new(0, 20.5, 0),
		Material = M.Neon,
		Color = Color3.fromRGB(255, 50, 60),
		CastShadow = false,
	}, model)
	local light = Instance.new("PointLight")
	light.Color = tip.Color
	light.Range = 14
	light.Parent = tip
	if rng:NextNumber() < 0.3 then
		local angle = rng:NextNumber(0, math.pi * 2)
		Kit.LaunchPad(model, Vector3.new(base.X, top + 1.5, base.Z), Vector3.new(math.cos(angle), 0, math.sin(angle)))
	end
	for _ = 1, rng:NextInteger(1, 2) do
		Kit.Shard(
			model,
			Vector3.new(
				base.X + rng:NextNumber(-width / 3, width / 3),
				top + 4,
				base.Z + rng:NextNumber(-depth / 3, depth / 3)
			)
		)
	end
	if rng:NextNumber() < 0.35 then
		billboard(model, body, rng)
	end
	model.Parent = parent
	return top
end

local function buildNeonCity(root: Instance, realm, rng: Random)
	local origin = realm.Origin
	local folder = Instance.new("Folder")
	folder.Name = "NeonCity"
	folder.Parent = root

	-- Arrival plaza with a glowing rim.
	local plaza = origin + Vector3.new(0, 160, 0)
	Kit.Cylinder(folder, plaza - Vector3.new(0, 1.5, 0), 3, 46, {
		Name = "Plaza",
		Material = M.DiamondPlate,
		Color = Color3.fromRGB(40, 40, 56),
	})
	Kit.Cylinder(folder, plaza - Vector3.new(0, 1.6, 0), 2.6, 47, {
		Name = "PlazaRim",
		Material = M.Neon,
		Color = realm.Color,
		CastShadow = false,
	})
	for i = 0, 3 do
		local angle = i * math.pi / 2 + math.pi / 4
		local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
		Kit.LaunchPad(folder, plaza + outward * 28, outward)
	end
	arrivals.neon = CFrame.new(plaza + Vector3.new(0, 4, 0))
	portal(folder, plaza + Vector3.new(0, 7, 38), Vector3.new(0, 0, -1), "sky")

	-- Towers on a loose grid, leaving the plaza clear.
	local tops = {}
	for gx = -5, 5 do
		for gz = -5, 5 do
			if (math.abs(gx) > 0 or math.abs(gz) > 0) and rng:NextNumber() < 0.72 then
				local base = origin
					+ Vector3.new(gx * 115 + rng:NextNumber(-20, 20), 0, gz * 115 + rng:NextNumber(-20, 20))
				local top = tower(folder, base, rng)
				table.insert(tops, Vector3.new(base.X, top, base.Z))
			end
		end
	end
	-- Grapple crystals floating between rooftops.
	for _ = 1, 30 do
		local a = tops[rng:NextInteger(1, #tops)]
		local b = tops[rng:NextInteger(1, #tops)]
		if (Flat(a) - Flat(b)).Magnitude < 260 and a ~= b then
			local mid = (a + b) / 2
			Kit.Anchor(folder, Vector3.new(mid.X, math.max(a.Y, b.Y) + rng:NextNumber(35, 60), mid.Z), rng, realm.Color)
		end
	end

	-- Synthwave grid far below, and a striped sun on the horizon.
	for i = -15, 15 do
		for _, axis in { "X", "Z" } do
			local offset = i * 80
			Kit.Decor({
				Name = "GridLine",
				Size = if axis == "X" then Vector3.new(2000, 0.6, 0.6) else Vector3.new(0.6, 0.6, 2000),
				Position = origin
					+ (if axis == "X" then Vector3.new(0, -110, offset) else Vector3.new(offset, -110, 0)),
				Material = M.Neon,
				Color = if i % 2 == 0 then NEON_PALETTE[1] else NEON_PALETTE[2],
				CastShadow = false,
			}, folder)
		end
	end
	local sun = origin + Vector3.new(0, 260, -1500)
	Kit.Decor({
		Name = "Sun",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, 460, 460),
		CFrame = CFrame.new(sun) * CFrame.Angles(0, math.pi / 2, 0),
		Material = M.Neon,
		Color = Color3.fromRGB(255, 120, 150),
		CastShadow = false,
	}, folder)
	for i = 1, 5 do
		Kit.Decor({
			Name = "SunStripe",
			Size = Vector3.new(470, 6 + i * 3, 3),
			Position = sun + Vector3.new(0, -20 - i * 34, 3),
			Color = Color3.fromRGB(12, 6, 24),
			CastShadow = false,
		}, folder)
	end
end

-- Ember Isles ---------------------------------------------------------------------------

local function deadTree(parent: Instance, base: Vector3, rng: Random)
	local height = rng:NextNumber(8, 14)
	local trunk = CFrame.new(base) * CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, rng:NextNumber(-0.15, 0.15))
	Kit.Cylinder(parent, Vector3.zero, height, 0.7, {
		Name = "DeadTree",
		CFrame = trunk * CFrame.new(0, height / 2 - 1, 0),
		Material = M.Wood,
		Color = Color3.fromRGB(36, 28, 26),
	})
	for i = 1, 2 do
		local branch = trunk
			* CFrame.new(0, height * (0.55 + i * 0.15), 0)
			* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		Kit.Part({
			Name = "Branch",
			Size = Vector3.new(0.5, 0.5, rng:NextNumber(3, 5)),
			CFrame = branch * CFrame.Angles(0.6, 0, 0) * CFrame.new(0, 0, -2),
			Material = M.Wood,
			Color = Color3.fromRGB(36, 28, 26),
		}, parent)
	end
end

local function obsidianSpire(parent: Instance, base: Vector3, rng: Random)
	local height = rng:NextNumber(10, 26)
	Kit.Part({
		Name = "ObsidianSpire",
		Size = Vector3.new(rng:NextNumber(3, 6), height, rng:NextNumber(3, 6)),
		CFrame = CFrame.new(base + Vector3.new(0, height / 2 - 2, 0))
			* CFrame.Angles(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0, math.pi), rng:NextNumber(-0.25, 0.25)),
		Material = M.Glass,
		Color = OBSIDIAN,
		Reflectance = 0.25,
	}, parent)
end

local function lavafall(parent: Instance, edge: Vector3, outward: Vector3)
	local fall = 60
	local sheet = Kit.Decor({
		Name = "Lavafall",
		Size = Vector3.new(8, fall, 0.6),
		CFrame = CFrame.lookAt(
			edge - Vector3.new(0, fall / 2 - 1, 0),
			edge - Vector3.new(0, fall / 2 - 1, 0) + outward
		),
		Material = M.Neon,
		Color = LAVA,
		Transparency = 0.15,
		CastShadow = false,
	}, parent)
	Kit.Emitter(sheet, {
		Texture = FIRE,
		Color = ColorSequence.new(Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 70, 20)),
		LightEmission = 1,
		Rate = 20,
		Lifetime = NumberRange.new(0.6, 1),
		Speed = NumberRange.new(3, 6),
		EmissionDirection = Enum.NormalId.Front,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 0) }),
	})
	local light = Instance.new("PointLight")
	light.Color = LAVA
	light.Range = 30
	light.Brightness = 2
	light.Parent = sheet
end

local function decorateEmber(parent: Instance, center: Vector3, radius: number, rng: Random)
	local model = Instance.new("Model")
	model.Name = "EmberIsland"
	local surface = center.Y + 2
	-- Lava pools cracked into the basalt.
	for _ = 1, rng:NextInteger(1, 3) do
		local x, z = Kit.RandomSpot(center, 0, radius * 0.6, rng)
		Terrain:FillCylinder(CFrame.new(x, surface - 0.6, z), 1.4, rng:NextNumber(4, radius * 0.22), M.CrackedLava)
	end
	for _ = 1, math.floor(radius / 14) do
		local x, z = Kit.RandomSpot(center, radius * 0.15, radius * 0.8, rng)
		local base = Kit.GroundAt(x, z, surface)
		if base then
			if rng:NextNumber() < 0.5 then
				deadTree(model, base, rng)
			else
				obsidianSpire(model, base, rng)
			end
		end
	end
	-- Smouldering vent.
	local vx, vz = Kit.RandomSpot(center, 0, radius * 0.5, rng)
	local vent = Kit.GroundAt(vx, vz, surface)
	if vent then
		local holder = Kit.Decor({ Name = "Vent", Transparency = 1, Size = Vector3.one, Position = vent }, model)
		Kit.Emitter(holder, {
			Texture = SMOKE,
			Color = ColorSequence.new(Color3.fromRGB(70, 60, 60)),
			Rate = 6,
			Lifetime = NumberRange.new(3, 5),
			Speed = NumberRange.new(4, 8),
			SpreadAngle = Vector2.new(15, 15),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 9) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) }),
		})
	end
	if radius > 30 and rng:NextNumber() < 0.4 then
		local angle = rng:NextNumber(0, math.pi * 2)
		local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
		lavafall(model, Flat(center) + outward * (radius + 1) + Vector3.new(0, surface, 0), outward)
	end
	for _ = 1, rng:NextInteger(1, 3) do
		local x, z = Kit.RandomSpot(center, 0, radius * 0.6, rng)
		local base = Kit.GroundAt(x, z, surface)
		if base then
			Kit.Shard(model, base + Vector3.new(0, 3, 0))
		end
	end
	model.Parent = parent
end

local function buildEmberIsles(root: Instance, realm, rng: Random)
	local origin = realm.Origin
	local folder = Instance.new("Folder")
	folder.Name = "EmberIsles"
	folder.Parent = root

	local plazaCenter = origin + Vector3.new(0, 120, 0)
	local islands = { { Position = plazaCenter, Radius = 55 } }
	-- The volcano, far side of the realm.
	local volcano = { Position = origin + Vector3.new(0, 180, -620), Radius = 120 }
	table.insert(islands, volcano)
	local attempts = 0
	while #islands < 20 and attempts < 3000 do
		attempts += 1
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = math.sqrt(rng:NextNumber()) * 1000
		local radius = rng:NextNumber(20, 45)
		local height = math.floor((100 + rng:NextNumber(0, 160)) / 4 + 0.5) * 4
		local pos = origin + Vector3.new(math.cos(angle) * dist, height, math.sin(angle) * dist)
		local fits = true
		for _, other in islands do
			if (Flat(pos) - Flat(other.Position)).Magnitude < radius + other.Radius + 50 then
				fits = false
				break
			end
		end
		if fits then
			table.insert(islands, { Position = pos, Radius = radius })
		end
	end
	for _, island in islands do
		Kit.SculptIsland(island.Position, island.Radius, "Volcanic", rng)
	end

	-- Arrival: obsidian platform, braziers, a portal home.
	local surface = plazaCenter + Vector3.new(0, 2, 0)
	Kit.Cylinder(folder, surface + Vector3.new(0, 0.5, 0), 1, 18, {
		Name = "ArrivalPlatform",
		Material = M.Glass,
		Color = OBSIDIAN,
		Reflectance = 0.3,
	})
	for i = 0, 5 do
		local angle = i / 6 * math.pi * 2
		Kit.Lantern(folder, surface + Vector3.new(math.cos(angle) * 24, 0, math.sin(angle) * 24))
	end
	arrivals.ember = CFrame.new(surface + Vector3.new(0, 4, 0))
	portal(folder, surface + Vector3.new(0, 7, 34), Vector3.new(0, 0, -1), "sky")
	for i = 0, 1 do
		local angle = i * math.pi + math.pi / 2
		local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
		Kit.LaunchPad(folder, surface + outward * 36, outward)
	end

	-- The volcano: a basalt cone with a lava-filled crater and a plume.
	local peak = volcano.Position + Vector3.new(0, 2, 0)
	for i = 0, 12 do
		Terrain:FillBall(peak + Vector3.new(0, i * 10, 0), volcano.Radius * 0.7 * (1 - i / 15), M.Basalt)
	end
	local crater = peak + Vector3.new(0, 128, 0)
	Terrain:FillBall(crater + Vector3.new(0, 12, 0), 24, M.Air)
	Terrain:FillCylinder(CFrame.new(crater - Vector3.new(0, 6, 0)), 4, 18, M.CrackedLava)
	local plume =
		Kit.Decor({ Name = "Plume", Transparency = 1, Size = Vector3.new(20, 1, 20), Position = crater }, folder)
	Kit.Emitter(plume, {
		Texture = FIRE,
		Color = ColorSequence.new(Color3.fromRGB(255, 210, 90), Color3.fromRGB(255, 60, 20)),
		LightEmission = 1,
		Rate = 40,
		Lifetime = NumberRange.new(1, 2),
		Speed = NumberRange.new(20, 40),
		SpreadAngle = Vector2.new(20, 20),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 1) }),
	})
	Kit.Emitter(plume, {
		Texture = SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(60, 50, 50)),
		Rate = 10,
		Lifetime = NumberRange.new(6, 9),
		Speed = NumberRange.new(15, 25),
		SpreadAngle = Vector2.new(25, 25),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 10), NumberSequenceKeypoint.new(1, 40) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
	})
	local glow = Instance.new("PointLight")
	glow.Color = LAVA
	glow.Range = 60
	glow.Brightness = 3
	glow.Parent = plume
	for i = 1, 8 do
		local angle = i / 8 * math.pi * 2
		Kit.Anchor(folder, crater + Vector3.new(math.cos(angle) * 60, -30 + i * 6, math.sin(angle) * 60), rng, LAVA)
	end

	for i = 3, #islands do
		decorateEmber(folder, islands[i].Position, islands[i].Radius, rng)
	end
	-- Link each island to its nearest neighbour with a glowing anchor.
	for i, a in islands do
		local nearest, nearestDist = nil, math.huge
		for j, b in islands do
			local dist = (a.Position - b.Position).Magnitude
			if i ~= j and dist < nearestDist then
				nearest, nearestDist = b, dist
			end
		end
		if nearest and nearestDist - a.Radius - nearest.Radius > 35 then
			local mid = (a.Position + nearest.Position) / 2
			Kit.Anchor(folder, mid + Vector3.new(0, rng:NextNumber(40, 60), 0), rng, LAVA)
		end
	end

	-- A sea of lava far below, with embers drifting up from it.
	Kit.Decor({
		Name = "LavaSea",
		Size = Vector3.new(2048, 2, 2048),
		Position = origin + Vector3.new(0, -95, 0),
		Material = M.Neon,
		Color = Color3.fromRGB(150, 40, 10),
		Transparency = 0.2,
		CastShadow = false,
	}, folder)
	for _ = 1, 12 do
		local x, z = Kit.RandomSpot(origin, 0, 1100, rng)
		local holder = Kit.Decor({
			Name = "Embers",
			Transparency = 1,
			Size = Vector3.new(200, 4, 200),
			Position = Vector3.new(x, -60, z),
		}, folder)
		Kit.Emitter(holder, {
			Texture = SPARKLE,
			Color = ColorSequence.new(Color3.fromRGB(255, 180, 60), Color3.fromRGB(255, 60, 20)),
			LightEmission = 1,
			Rate = 8,
			Lifetime = NumberRange.new(8, 14),
			Speed = NumberRange.new(10, 20),
			SpreadAngle = Vector2.new(15, 15),
			Shape = Enum.ParticleEmitterShape.Box,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) }),
		})
	end
end

-- Start ---------------------------------------------------------------------------------

function Realms.Build(hasGeneratedMap: boolean)
	local rng = Random.new(Config.World.Seed + 7)
	local root = Instance.new("Folder")
	root.Name = "Realms"
	root.Parent = workspace

	buildNeonCity(root, Config.GetRealm("neon"), rng)
	buildEmberIsles(root, Config.GetRealm("ember"), rng)

	-- Portals at the Sky Islands spawn plaza.
	if hasGeneratedMap then
		local plaza = Vector3.new(0, 102, 0)
		for _, spec in { { Target = "neon", Degrees = 200 }, { Target = "ember", Degrees = 340 } } do
			local angle = math.rad(spec.Degrees)
			local position = plaza + Vector3.new(math.cos(angle) * 60, 7, math.sin(angle) * 60)
			portal(root, position, plaza - position, spec.Target)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		portalCooldown[player] = nil
	end)
	CollectionService:AddTag(root, "Realms")
end

return Realms

-- Builds the world once at server start and answers questions about it:
-- comet impact sites, wisp spots, sanctuary plots and portals.
--
-- Impact sites come from the biome builders (chosen away from props) plus
-- any hand-placed parts tagged "ImpactLocation" (attribute Biome). Every site
-- is then validated against the real geometry: there must be ground under
-- it within reach and no solid part occupying the impact volume. Invalid
-- sites are dropped with a warning instead of letting comets fall into
-- terrain, buildings or the void.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldLayout = require(Shared.WorldLayout)

local World = script.Parent.Parent.World
local Atmosphere = require(World.Atmosphere)
local DawnCommonsBuilder = require(World.DawnCommonsBuilder)
local HubBuilder = require(World.HubBuilder)
local Kit = require(World.Kit)
local PlotBuilder = require(World.PlotBuilder)

local WorldService = { Name = "WorldService" }

export type Point = DawnCommonsBuilder.Point

WorldService.Root = nil :: Folder?
WorldService.Hub = nil :: HubBuilder.HubInfo?
WorldService.Plots = {} :: { PlotBuilder.Plot }
WorldService.ImpactPoints = {} :: { [string]: { Point } }
WorldService.WispPoints = {} :: { Point }
WorldService.Portals = {} :: { HubBuilder.PortalInfo }
WorldService.TutorialImpact = WorldLayout.Hub.TutorialImpact
-- Tests turn this off: they have no physics world to raycast against.
WorldService.ValidateWithPhysics = true

local SEED = 20261010

-- Finds the ground under a point and checks the impact volume is clear.
local function validate(position: Vector3, ignore: { Instance }): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(position + Vector3.new(0, 30, 0), Vector3.new(0, -70, 0), params)
	if not hit then
		return nil
	end
	local ground = hit.Position
	if math.abs(ground.Y - position.Y) > 12 then
		return nil
	end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = ignore
	local blockers =
		workspace:GetPartBoundsInBox(CFrame.new(ground + Vector3.new(0, 5, 0)), Vector3.new(9, 8, 9), overlap)
	for _, part in blockers do
		if not part:IsA("Terrain") then
			return nil
		end
	end
	return ground
end

local function validatePoints(points: { Point }, kind: string): { Point }
	if not WorldService.ValidateWithPhysics then
		return points
	end
	local kept = {}
	local ignore = {}
	for _, player in game:GetService("Players"):GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	for _, point in points do
		local ok, ground = pcall(validate, point.Position, ignore)
		if ok and ground then
			table.insert(kept, {
				Id = point.Id,
				Position = if kind == "Wisp" then ground + Vector3.new(0, 2.5, 0) else ground,
				Biome = point.Biome,
			})
		else
			warn(`[World] Dropped invalid {kind} site {point.Id} at {point.Position}`)
		end
	end
	return kept
end

function WorldService.Build()
	local rng = Random.new(SEED)
	local root = Instance.new("Folder")
	root.Name = "World"
	root.Parent = workspace
	WorldService.Root = root

	-- Remove a Baseplate template if the place started from one.
	for _, name in { "Baseplate", "SpawnLocation" } do
		local leftover = workspace:FindFirstChild(name)
		if leftover and leftover ~= root then
			leftover:Destroy()
		end
	end

	Atmosphere.Apply()
	Atmosphere.BuildSkyscape(Kit.Folder("Sky", root), rng)
	local hub = HubBuilder.Build(root, rng)
	WorldService.Hub = hub
	local dawn = DawnCommonsBuilder.Build(Kit.Folder("Biomes", root), rng)

	local sanctuaries = Kit.Folder("Sanctuaries", root)
	for index = 1, WorldLayout.Sanctuary.Count do
		local plot = PlotBuilder.Build(sanctuaries, index, rng)
		PlotBuilder.SetTier(plot, 1)
		WorldService.Plots[index] = plot
		-- A bridge from the hub's edge to the plot's entrance.
		local layout = WorldLayout.Plots[index]
		local from = WorldLayout.Polar(layout.Angle, WorldLayout.Hub.Radius - 3)
		local to =
			WorldLayout.Polar(layout.Angle, WorldLayout.Sanctuary.RingRadius - WorldLayout.Sanctuary.PlotRadius + 2)
		Kit.Bridge(
			plot.Model,
			from,
			to,
			WorldLayout.Sanctuary.BridgeWidth,
			{ Name = "Bridge", LanternColor = Kit.Colors.Lavender }
		)
	end

	for _, portal in hub.Portals do
		table.insert(WorldService.Portals, portal)
	end
	for _, portal in dawn.Portals do
		table.insert(WorldService.Portals, portal)
	end

	-- Hand-placed impact sites and wisp spots (optional).
	local extraImpacts: { Point } = {}
	for i, part in CollectionService:GetTagged("ImpactLocation") do
		if part:IsA("BasePart") and type(part:GetAttribute("Biome")) == "string" then
			table.insert(
				extraImpacts,
				{ Id = `hand{i}`, Position = part.Position, Biome = part:GetAttribute("Biome") :: string }
			)
		end
	end

	local impacts = validatePoints(dawn.ImpactPoints, "Impact")
	for _, point in validatePoints(extraImpacts, "Impact") do
		table.insert(impacts, point)
	end
	WorldService.ImpactPoints = {}
	for _, point in impacts do
		local list = WorldService.ImpactPoints[point.Biome]
		if not list then
			list = {}
			WorldService.ImpactPoints[point.Biome] = list
		end
		table.insert(list, point)
	end
	WorldService.WispPoints = validatePoints(dawn.WispPoints, "Wisp")

	local tutorial =
		validatePoints({ { Id = "tutorial", Position = WorldLayout.Hub.TutorialImpact, Biome = "Hub" } }, "Impact")
	WorldService.TutorialImpact = if tutorial[1] then tutorial[1].Position else WorldLayout.Hub.TutorialImpact

	local count = 0
	for biomeId, list in WorldService.ImpactPoints do
		count += #list
		if #list < 6 then
			warn(`[World] Only {#list} impact sites in {biomeId}; comets may repeat locations`)
		end
	end
	print(
		`[World] Built. {count} impact sites, {#WorldService.WispPoints} wisp spots, {#WorldService.Plots} sanctuaries.`
	)
end

function WorldService.GetPlot(index: number): PlotBuilder.Plot?
	return WorldService.Plots[index]
end

function WorldService.SetPlotTier(index: number, habitatLevel: number)
	local plot = WorldService.Plots[index]
	if plot then
		PlotBuilder.SetTier(plot, habitatLevel)
	end
end

function WorldService.Init(_registry: { [string]: any })
	WorldService.Build()
end

function WorldService.Start() end

return WorldService

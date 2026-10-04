-- Builds the whole of Meridian: the Guildhall hub, the six districts, the
-- Spire challenge tower and the Dreamline. Publishes every course's runtime
-- data (checkpoints, medals, requirements) for the client and services.
--
-- The world is generated on server start from seeded data, so it is identical
-- on every server. To preview it in Studio edit mode, run in the command bar:
--   require(game.ServerScriptService.Server.World.WorldBuilder).Build()

local Lighting = game:GetService("Lighting")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Courses = require(ReplicatedStorage.Shared.Config.Courses)
local Districts = require(ReplicatedStorage.Shared.Config.Districts)
local MovementConfig = require(ReplicatedStorage.Shared.Config.Movement)
local Tags = require(ReplicatedStorage.Shared.Tags)

local DistrictBuilder = require(script.Parent.DistrictBuilder)

local WorldBuilder = {}

-- course id -> CourseBuilder.Meta (with District)
WorldBuilder.Courses = {} :: { [string]: any }
WorldBuilder.Spawns = {} :: { [string]: CFrame }
WorldBuilder.Contexts = {} :: { [string]: any }
WorldBuilder.Folder = nil :: Folder?
WorldBuilder.Built = false

local DISTRICT_MODULES = {
	Tinroof = "Tinroof",
	Ironworks = "Ironworks",
	Verdant = "Verdant",
	Gilded = "Gilded",
	Frostreach = "Frostreach",
	Citadel = "Citadel",
}

function WorldBuilder.CollisionGroups()
	local G = Tags.Groups
	for _, name in { G.Players, G.PlayersLow, G.PlayersPhase, G.LowClearance, G.Ghosts, G.Cosmetic } do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	local function set(a: string, b: string, collide: boolean)
		PhysicsService:CollisionGroupSetCollidable(a, b, collide)
	end
	-- Runners pass through each other.
	set(G.Players, G.Players, false)
	set(G.Players, G.PlayersLow, false)
	set(G.Players, G.PlayersPhase, false)
	set(G.PlayersLow, G.PlayersLow, false)
	set(G.PlayersLow, G.PlayersPhase, false)
	set(G.PlayersPhase, G.PlayersPhase, false)
	-- Crouching and sliding runners fit under low clearance.
	set(G.PlayersLow, G.LowClearance, false)
	-- Scripted moves (vaults, mantles, pulls) pass through scenery.
	set(G.PlayersPhase, G.World, false)
	set(G.PlayersPhase, G.LowClearance, false)
	-- Ghosts and cosmetics never collide with anything.
	for _, group in { G.World, G.Players, G.PlayersLow, G.PlayersPhase, G.LowClearance, G.Ghosts, G.Cosmetic } do
		set(G.Ghosts, group, false)
		set(G.Cosmetic, group, false)
	end
end

-- Publish course data where clients can read it (attributes on Configurations).
local function publish(metas: { [string]: any })
	local folder = ReplicatedStorage:FindFirstChild("SkylineCourses")
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "SkylineCourses"
	for id, meta in metas do
		local course = Courses.ById[id]
		local config = Instance.new("Configuration")
		config.Name = id
		config:SetAttribute("Name", if course then course.Name else id)
		config:SetAttribute("District", meta.District or (course and course.District) or "Hub")
		config:SetAttribute("Kind", meta.Kind or (course and course.Kind) or "Course")
		config:SetAttribute("Difficulty", if course then course.Difficulty else (meta.Difficulty or 1))
		for index, seconds in meta.Medals do
			config:SetAttribute("Medal" .. index, seconds)
		end
		config:SetAttribute("Expected", math.floor(meta.Par.A * 1.5 + 0.5))
		config:SetAttribute("ParA", meta.Par.A)
		config:SetAttribute("ParF", meta.Par.F)
		config:SetAttribute("ParE", meta.Par.E)
		config:SetAttribute("Checkpoints", #meta.Checkpoints)
		config:SetAttribute("Tokens", #meta.Tokens)
		config:SetAttribute("Length", math.floor(meta.Length))
		config:SetAttribute("KillY", meta.KillY)
		config:SetAttribute("Spawn", meta.Spawn)
		config:SetAttribute("FlowTarget", meta.FlowTarget)
		config:SetAttribute("Requires", table.concat(meta.Requires, ","))
		config:SetAttribute("FastRequires", table.concat(meta.FastRequires, ","))
		config:SetAttribute("ExpertRequires", table.concat(meta.ExpertRequires, ","))
		config:SetAttribute("HasShortcut", #meta.Shortcuts > 0)
		config:SetAttribute("Exchanges", table.concat(meta.Exchanges, ","))
		config:SetAttribute("Legs", if course and course.Legs then course.Legs else 1)
		for index, checkpoint in meta.Checkpoints do
			config:SetAttribute("CP" .. index, checkpoint.Spawn)
		end
		config.Parent = folder
	end
	folder.Parent = ReplicatedStorage
end

function WorldBuilder.Build(): { [string]: any }
	if WorldBuilder.Built then
		return WorldBuilder.Courses
	end
	local started = os.clock()
	workspace.Gravity = MovementConfig.Gravity
	WorldBuilder.CollisionGroups()

	-- Remove any template baseplate.
	for _, name in { "Baseplate", "SpawnLocation" } do
		local existing = workspace:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end
	local old = workspace:FindFirstChild("SkylineWorld")
	if old then
		old:Destroy()
	end
	local world = Instance.new("Folder")
	world.Name = "SkylineWorld"
	WorldBuilder.Folder = world

	local Hub = require(script.Parent.Districts.Hub)
	local hubCtx, hubMetas, hubSpawns = Hub.Build(world)
	WorldBuilder.Contexts.Hub = hubCtx
	for id, meta in hubMetas do
		WorldBuilder.Courses[id] = meta
	end
	for name, cframe in hubSpawns do
		WorldBuilder.Spawns[name] = cframe
	end

	for _, district in Districts.Ordered() do
		local moduleName = DISTRICT_MODULES[district.Id]
		local moduleScript = moduleName and script.Parent.Districts:FindFirstChild(moduleName)
		if moduleScript then
			local module = require(moduleScript) :: any
			local ctx, metas = DistrictBuilder.Build(world, district.Id, module)
			WorldBuilder.Contexts[district.Id] = ctx
			WorldBuilder.Spawns[district.Id] = ctx.Spawn
			for _, meta in metas do
				WorldBuilder.Courses[meta.Id] = meta
			end
		end
	end

	local Spire = require(script.Parent.Spire)
	local spireMetas = Spire.Build(world)
	for id, meta in spireMetas do
		WorldBuilder.Courses[id] = meta
	end

	local Dreamline = require(script.Parent.Dreamline)
	WorldBuilder.Spawns.Dreamline = Dreamline.BuildGate(world)

	publish(WorldBuilder.Courses)
	world.Parent = workspace

	-- Baseline lighting; each client adjusts it per district.
	Lighting.Brightness = 2.4
	Lighting.ClockTime = 14
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	WorldBuilder.Built = true

	local parts = 0
	for _, descendant in world:GetDescendants() do
		if descendant:IsA("BasePart") then
			parts += 1
		end
	end
	print(("[World] Built Meridian: %d parts, %d courses in %.2fs"):format(
		parts,
		(function()
			local n = 0
			for _ in WorldBuilder.Courses do
				n += 1
			end
			return n
		end)(),
		os.clock() - started
	))
	return WorldBuilder.Courses
end

return WorldBuilder

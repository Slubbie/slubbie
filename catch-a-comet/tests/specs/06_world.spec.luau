-- Build smoke tests: the world, every creature model and every equipment
-- level are constructed with Lune's Roblox DOM, which rejects unknown
-- classes, properties and wrong value types. Also checks layout invariants
-- and reports part budgets.

local roblox = require("@lune/roblox")

local Loader = require("../harness/Loader")
local Mock = require("../harness/Mock")
local T = require("../harness/T")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3

local function countParts(root: any): number
	local n = 0
	for _, child in root:GetDescendants() do
		if child:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

return function()
	local loader = Loader.new(".")
	local Kit = loader:require("Server.World.Kit")
	local terrainCalls = 0
	for name in Kit.Terrain do
		Kit.Terrain[name] = function()
			terrainCalls += 1
		end
	end
	local Atmosphere = loader:require("Server.World.Atmosphere")
	local HubBuilder = loader:require("Server.World.HubBuilder")
	local DawnCommonsBuilder = loader:require("Server.World.DawnCommonsBuilder")
	local PlotBuilder = loader:require("Server.World.PlotBuilder")
	local WorldLayout = loader:require("Shared.WorldLayout")
	local CreatureRig = loader:require("Shared.CreatureRig")
	local CreatureDefinitions = loader:require("Shared.CreatureDefinitions")
	local RarityConfig = loader:require("Shared.RarityConfig")
	local EquipmentRig = loader:require("Shared.EquipmentRig")

	T.Suite("World build")
	local root = Instance.new("Folder")
	local rng = Mock.Random.new(20261010)

	T.Case("lighting, sky and skyscape build", function()
		Atmosphere.Apply()
		local lighting = loader.Services.Lighting
		T.True(lighting:FindFirstChild("Atmosphere") ~= nil)
		T.True(lighting:FindFirstChild("Bloom") ~= nil)
		Atmosphere.BuildSkyscape(Kit.Folder("Sky", root), rng)
	end)

	local hub
	T.Case("the hub builds with spawn, portals, stations and leaderboard", function()
		hub = HubBuilder.Build(root, rng)
		T.True(hub.Spawn:IsA("SpawnLocation"))
		T.Equal(#hub.Portals, 5, "Dawn Commons + four sealed portals")
		T.Equal(#hub.LeaderboardRows, 8)
		local prompts = {}
		for _, child in hub.Model:GetDescendants() do
			if child:IsA("ProximityPrompt") then
				prompts[child:GetAttribute("Action")] = true
			end
		end
		T.True(prompts.OpenWorkshop and prompts.OpenQuests and prompts.OpenCores, "station prompts")
		print(`      hub parts: {countParts(hub.Model)}`)
	end)

	local dawn
	T.Case("Dawn Commons builds with well-spaced impact sites and wisps", function()
		dawn = DawnCommonsBuilder.Build(root, rng)
		T.True(#dawn.ImpactPoints >= 22, `impact sites: {#dawn.ImpactPoints}`)
		T.True(#dawn.WispPoints >= 15, `wisp spots: {#dawn.WispPoints}`)
		for _, point in dawn.ImpactPoints do
			local inside = false
			for _, island in DawnCommonsBuilder.Islands do
				local d =
					Vector3.new(point.Position.X - island.Center.X, 0, point.Position.Z - island.Center.Z).Magnitude
				if d <= island.Radius * 0.8 and math.abs(point.Position.Y - island.Center.Y) < 1 then
					inside = true
				end
			end
			T.True(inside, `{point.Id} sits on an island`)
			T.Equal(WorldLayout.GetArea(point.Position).Id, "DawnCommons", `{point.Id} area`)
		end
		for i, a in dawn.ImpactPoints do
			for j = i + 1, #dawn.ImpactPoints do
				local b = dawn.ImpactPoints[j]
				T.True((a.Position - b.Position).Magnitude >= 30, `{a.Id}/{b.Id} spacing`)
			end
		end
		T.Equal(#dawn.Portals, 1, "return portal")
		print(
			`      Dawn Commons parts: {countParts(dawn.Model)}, {#dawn.ImpactPoints} impact sites, {#dawn.WispPoints} wisps`
		)
	end)

	T.Case("twelve sanctuary plots with non-overlapping pads and all habitat tiers", function()
		local folder = Kit.Folder("Sanctuaries", root)
		local total = 0
		for index = 1, WorldLayout.Sanctuary.Count do
			local plot = PlotBuilder.Build(folder, index, rng)
			T.Equal(#plot.Pads, 12)
			for level = 1, 5 do
				PlotBuilder.SetTier(plot, level)
			end
			total += countParts(plot.Model)
			for s = 1, 12 do
				local p = WorldLayout.SlotPosition(index, s)
				local center = WorldLayout.Plots[index].Center
				T.True(
					Vector3.new(p.X - center.X, 0, p.Z - center.Z).Magnitude + 5.5 <= WorldLayout.Sanctuary.PlotRadius,
					`slot {s} inside plot`
				)
				for t = s + 1, 12 do
					T.True((p - WorldLayout.SlotPosition(index, t)).Magnitude >= 11.5, `pads {s}/{t} don't overlap`)
				end
				T.Equal(WorldLayout.GetArea(p).Kind, "Sanctuary")
			end
		end
		print(`      sanctuary parts (all tiers): {total}`)
	end)

	T.Case("key locations are in the right areas", function()
		T.Equal(WorldLayout.GetArea(WorldLayout.Hub.Spawn.Position).Id, "Hub")
		T.Equal(WorldLayout.GetArea(WorldLayout.Hub.TutorialImpact).Id, "Hub")
		T.Equal(WorldLayout.GetArea(WorldLayout.Biomes.DawnCommons.Arrival.Position).Id, "DawnCommons")
		for index = 1, 12 do
			T.Equal(WorldLayout.GetArea(WorldLayout.PlotArrival(index).Position).PlotIndex, index)
		end
		print(`      terrain operations: {terrainCalls}`)
	end)

	T.Suite("Creature and equipment models")

	T.Case("all 24 species build in every mutation, plus silhouettes", function()
		local largest, largestName = 0, ""
		for _, speciesId in CreatureDefinitions.Order do
			for _, mutation in RarityConfig.MutationOrder do
				local model = CreatureRig.Build(speciesId, { Mutation = mutation })
				T.Equal(model:GetAttribute("SpeciesId"), speciesId)
				T.True(model.PrimaryPart ~= nil)
				local height = model:GetAttribute("Height")
				T.True(height > 0.5 and height < 12, `{speciesId} height {height}`)
				local parts = countParts(model)
				if parts > largest then
					largest, largestName = parts, speciesId
				end
			end
			local silhouette = CreatureRig.Build(speciesId, { Silhouette = true, ForViewport = true })
			T.True(countParts(silhouette) > 3)
			local display = CreatureRig.Build(speciesId, {})
			CreatureRig.ScaleTo(display, 0.8)
			CreatureRig.Place(display, roblox.CFrame.new(10, 41.4, 5))
		end
		print(`      most detailed creature: {largestName} ({largest} parts)`)
	end)

	T.Case("every creature has blinking eyes and at least one moving part or idle", function()
		for _, speciesId in CreatureDefinitions.Order do
			local model = CreatureRig.Build(speciesId, {})
			local blink, motion = false, false
			for _, part in model:GetChildren() do
				local kind = part:GetAttribute("Motion")
				if kind == "Blink" then
					blink = true
				elseif kind then
					motion = true
				end
			end
			T.True(blink, `{speciesId} blinks`)
			T.True(motion or model:GetAttribute("Idle") ~= nil, `{speciesId} moves`)
		end
	end)

	T.Case("the comet tether builds at every scanner/tether level", function()
		for scanner = 1, 5 do
			for tether = 1, 5 do
				local device = EquipmentRig.BuildDevice(scanner, tether)
				T.True(device:FindFirstChild("Tip", true) ~= nil)
			end
		end
	end)
end

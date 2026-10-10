-- Dawn Commons: the first biome. A cluster of pastel islands east of the hub
-- with flower fields, luminous streams, observation decks, old craters and
-- puffy trees. Comet impact sites and Stardust Wisp spots are chosen here,
-- away from props, then validated against the real geometry by WorldService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldLayout = require(Shared.WorldLayout)

local Kit = require(script.Parent.Kit)
local HubBuilder = require(script.Parent.HubBuilder)

local DawnCommonsBuilder = {}

local C = Kit.Colors
local M = Enum.Material
local BIOME = WorldLayout.Biomes.DawnCommons

type Island = { Name: string, Center: Vector3, Radius: number, Impacts: number, Wisps: number }

DawnCommonsBuilder.Islands = {
	{ Name = "Meadow", Center = Vector3.new(640, 40, 0), Radius = 150, Impacts = 12, Wisps = 9 },
	{ Name = "North", Center = Vector3.new(610, 48, -250), Radius = 72, Impacts = 4, Wisps = 3 },
	{ Name = "South", Center = Vector3.new(600, 44, 245), Radius = 76, Impacts = 4, Wisps = 3 },
	{ Name = "East", Center = Vector3.new(870, 52, -30), Radius = 84, Impacts = 5, Wisps = 4 },
	{ Name = "Islet", Center = Vector3.new(860, 56, 190), Radius = 46, Impacts = 2, Wisps = 3 },
} :: { Island }

local STREAM = {
	Vector3.new(565, 40, -112),
	Vector3.new(610, 40, -52),
	Vector3.new(642, 40, 8),
	Vector3.new(700, 40, 58),
	Vector3.new(728, 40, 98),
}

export type Point = { Id: string, Position: Vector3, Biome: string }

export type Info = {
	ImpactPoints: { Point },
	WispPoints: { Point },
	Portals: { HubBuilder.PortalInfo },
	Model: Model,
}

local function edgePoint(from: Island, to: Island, inset: number): Vector3
	local dir = Vector3.new(to.Center.X - from.Center.X, 0, to.Center.Z - from.Center.Z).Unit
	local p = from.Center + dir * (from.Radius - inset)
	return Vector3.new(p.X, from.Center.Y, p.Z)
end

local function buildStream(model: Model, blocked: { { Position: Vector3, Radius: number } })
	local folder = Kit.Folder("Stream", model)
	for i = 1, #STREAM - 1 do
		local a, b = STREAM[i], STREAM[i + 1]
		local mid = (a + b) / 2
		local length = (b - a).Magnitude + 6
		local frame = CFrame.lookAt(mid, b)
		Kit.Terrain.Block(frame * CFrame.new(0, -1.6, 0), Vector3.new(8, 3.2, length), M.Air)
		Kit.Terrain.Block(frame * CFrame.new(0, -2.2, 0), Vector3.new(8, 2.2, length), M.Water)
		Kit.Terrain.Block(frame * CFrame.new(0, -4.2, 0), Vector3.new(10, 2, length), M.Sand)
		local steps = math.floor(length / 7)
		for k = 0, steps do
			local t = k / math.max(steps, 1)
			local p = a:Lerp(b, t)
			for _, side in { -1, 1 } do
				local bank = (frame * CFrame.new(side * 4.6, 0, 0)).Position - frame.Position + p
				local pebble = Kit.Ball(
					folder,
					0.6 + (k % 3) * 0.2,
					bank + Vector3.new(0, 0.1, 0),
					if k % 2 == 0 then C.Cyan else C.Lavender,
					M.Neon
				)
				pebble.CastShadow = false
			end
			table.insert(blocked, { Position = p, Radius = 9 })
		end
		local glow = Kit.Ball(folder, 0.4, mid + Vector3.new(0, -0.8, 0), C.Cyan, M.Neon)
		Kit.Light(glow, C.Cyan, 18, 0.7)
	end
	-- Little footbridges where the main paths cross the water.
	for _, i in { 2, 4 } do
		local a, b = STREAM[i], STREAM[i + 1]
		local mid = (a + b) / 2
		local across = CFrame.lookAt(mid, b).RightVector
		Kit.Bridge(folder, mid - across * 7 + Vector3.new(0, 0.6, 0), mid + across * 7 + Vector3.new(0, 0.6, 0), 6, {
			Name = "Footbridge",
			PostSpacing = 6,
		})
	end
end

local function buildDeck(model: Model, island: Island, angle: number)
	local folder = Kit.Model("ObservationDeck", model)
	local center = island.Center
		+ Vector3.new(math.cos(math.rad(angle)), 0, math.sin(math.rad(angle))) * (island.Radius - 16)
	local outward = Vector3.new(math.cos(math.rad(angle)), 0, math.sin(math.rad(angle)))
	local frame = CFrame.lookAt(center, center + outward)
	Kit.Part(folder, Vector3.new(16, 1, 16), frame * CFrame.new(0, 3, 0), { Color = C.Wood, Material = M.WoodPlanks })
	for _, corner in { Vector2.new(-7.5, -7.5), Vector2.new(7.5, -7.5), Vector2.new(-7.5, 7.5), Vector2.new(7.5, 7.5) } do
		Kit.Part(
			folder,
			Vector3.new(1, 7, 1),
			frame * CFrame.new(corner.X, 2.5, corner.Y),
			{ Color = C.WoodDark, Material = M.Wood }
		)
	end
	for _, side in { -1, 1 } do
		Kit.Part(
			folder,
			Vector3.new(0.4, 0.4, 16),
			frame * CFrame.new(side * 7.8, 6, 0),
			{ Color = C.WoodDark, Material = M.Wood }
		)
	end
	Kit.Part(
		folder,
		Vector3.new(16, 0.4, 0.4),
		frame * CFrame.new(0, 6, -7.8),
		{ Color = C.WoodDark, Material = M.Wood }
	)
	-- Ramp up from the island side.
	Kit.Wedge(
		folder,
		Vector3.new(6, 3.5, 10),
		frame * CFrame.new(0, 1.75, 13) * CFrame.Angles(0, math.rad(180), 0),
		C.Wood,
		M.WoodPlanks
	)
	local scopeBase = (frame * CFrame.new(0, 3.5, -4)).Position
	Kit.Column(folder, 0.5, 3.5, scopeBase, C.StoneDark, M.Metal)
	local scope = Kit.Part(
		folder,
		Vector3.new(4.5, 1, 1),
		CFrame.lookAt(scopeBase + Vector3.new(0, 4, 0), scopeBase + Vector3.new(0, 6, 0) + outward * 4)
			* CFrame.Angles(0, math.rad(90), 0),
		{
			Shape = Enum.PartType.Cylinder,
			Color = C.Gold,
			Material = M.Metal,
			Decor = true,
		}
	)
	Kit.Billboard(
		scope,
		"Observation Deck",
		"Watch the comets fall",
		{ Offset = Vector3.new(0, 5, 0), MaxDistance = 90 }
	)
	return center
end

local function buildCrater(model: Model, rng: Random, center: Vector3)
	local folder = Kit.Model("OldCrater", model)
	Kit.Disc(folder, 12, 0.3, center + Vector3.new(0, 0.15, 0), Color3.fromRGB(96, 84, 120), M.Slate, true)
	for i = 0, 8 do
		local a = i / 9 * math.pi * 2
		local rock = Kit.Ball(
			folder,
			1.6 + rng:NextNumber() * 1.4,
			center + Vector3.new(math.cos(a) * 6.5, 0.4, math.sin(a) * 6.5),
			Color3.fromRGB(128, 116, 156),
			M.Slate
		)
		rock.CastShadow = true
	end
	Kit.Ball(folder, 1.2, center + Vector3.new(0, 0.4, 0), C.Lavender, M.Neon)
end

function DawnCommonsBuilder.Build(parent: Instance, rng: Random): Info
	local model = Kit.Model("DawnCommons", parent)
	local islands = DawnCommonsBuilder.Islands
	local byName: { [string]: Island } = {}
	for _, island in islands do
		byName[island.Name] = island
		Kit.Island(rng, island.Center, island.Radius)
		-- Lavender flower-field patches.
		for _ = 1, math.floor(island.Radius / 30) do
			local a = rng:NextNumber() * math.pi * 2
			local d = rng:NextNumber() * island.Radius * 0.6
			local p = island.Center + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
			Kit.Terrain.Cylinder(CFrame.new(p.X, island.Center.Y - 1, p.Z), 2, 10 + rng:NextNumber() * 14, M.LeafyGrass)
		end
	end

	local blocked: { { Position: Vector3, Radius: number } } = {}
	local function block(position: Vector3, radius: number)
		table.insert(blocked, { Position = position, Radius = radius })
	end

	-- Bridges: from the hub, between islands.
	local bridges = Kit.Folder("Bridges", model)
	local meadow = byName.Meadow
	local midIslet = Vector3.new(330, WorldLayout.GroundY, 0)
	Kit.Island(rng, midIslet, 20)
	Kit.Lantern(model, midIslet + Vector3.new(0, 0, 8), C.Gold, true)
	Kit.Bridge(
		bridges,
		Vector3.new(WorldLayout.Hub.Radius - 2, WorldLayout.GroundY, 0),
		midIslet - Vector3.new(17, 0, 0),
		12,
		{ Name = "HubBridge" }
	)
	Kit.Bridge(
		bridges,
		midIslet + Vector3.new(17, 0, 0),
		Vector3.new(meadow.Center.X - meadow.Radius + 4, meadow.Center.Y, 0),
		12,
		{ Name = "HubBridge" }
	)
	block(Vector3.new(meadow.Center.X - meadow.Radius + 8, 0, 0), 12)
	for _, pair in { { "Meadow", "North" }, { "Meadow", "South" }, { "Meadow", "East" }, { "East", "Islet" } } do
		local a, b = byName[pair[1]], byName[pair[2]]
		local from, to = edgePoint(a, b, 5), edgePoint(b, a, 5)
		Kit.Bridge(bridges, from, to, 10, { Name = `{pair[1]}To{pair[2]}` })
		block(edgePoint(a, b, 10), 10)
		block(edgePoint(b, a, 10), 10)
	end

	-- Return portal and arrival area.
	local returnPortal = BIOME.ReturnPortal
	block(BIOME.Arrival.Position, 18)
	block(returnPortal, 14)
	local portals = {}
	do
		local folder = Kit.Model("ReturnPortal", model)
		folder.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		local frame = CFrame.lookAt(returnPortal, returnPortal + Vector3.new(1, 0, 0))
		for _, side in { -1, 1 } do
			Kit.Column(folder, 2.4, 14, (frame * CFrame.new(side * 6.5, 0, 0)).Position, C.Marble, M.Marble)
		end
		Kit.Part(
			folder,
			Vector3.new(16, 2, 2.6),
			frame * CFrame.new(0, 15, 0),
			{ Color = C.MarbleShade, Material = M.Marble }
		)
		local plane = Kit.Part(folder, Vector3.new(11, 13, 0.6), frame * CFrame.new(0, 7.6, 0), {
			Name = "PortalPlane",
			Color = C.Lavender,
			Material = M.Glass,
			Transparency = 0.35,
			CanCollide = false,
			CastShadow = false,
		})
		plane.CanQuery = false
		plane:SetAttribute("Destination", "Hub")
		plane:SetAttribute("Biome", "Hub")
		Kit.Emitter(plane, { Color = ColorSequence.new(C.Lavender), Rate = 10 })
		Kit.Light(plane, C.Lavender, 18, 1)
		Kit.Billboard(
			plane,
			"Celestial Crossing",
			"Return to the hub",
			{ Offset = Vector3.new(0, 11, 0), MaxDistance = 160 }
		)
		table.insert(portals, { Part = plane, Destination = "Hub", Biome = "Hub" })
	end
	do
		local sign = Kit.Part(
			model,
			Vector3.new(8, 5, 0.6),
			CFrame.lookAt(
				BIOME.Arrival.Position + Vector3.new(10, 0.5, -14),
				BIOME.Arrival.Position + Vector3.new(0, 0.5, 0)
			),
			{
				Color = C.Wood,
				Material = M.WoodPlanks,
			}
		)
		Kit.Sign(sign, Enum.NormalId.Front, { "DAWN COMMONS", "Comets land here all the time" })
	end

	buildStream(model, blocked)
	block(buildDeck(model, byName.North, 250), 16)
	block(buildDeck(model, byName.East, 10), 16)

	-- Impact sites, then wisps, then props that keep clear of both.
	local impacts: { Point } = {}
	local wisps: { Point } = {}
	for _, island in islands do
		local points = Kit.ScatterPoints(rng, island.Center, island.Radius * 0.76, island.Impacts, 32, blocked)
		for _, p in points do
			table.insert(impacts, { Id = `dc{#impacts + 1}`, Position = p, Biome = "DawnCommons" })
		end
	end
	for _, impact in impacts do
		block(impact.Position, 12)
	end
	for _, island in islands do
		local points = Kit.ScatterPoints(rng, island.Center, island.Radius * 0.85, island.Wisps, 18, blocked)
		for _, p in points do
			table.insert(wisps, { Id = `w{#wisps + 1}`, Position = p + Vector3.new(0, 2.5, 0), Biome = "DawnCommons" })
		end
	end
	for _, wisp in wisps do
		block(wisp.Position, 5)
	end

	local decor = Kit.Folder("Decor", model)
	for _, island in islands do
		local count = math.floor(island.Radius / 12)
		local spots = Kit.ScatterPoints(rng, island.Center, island.Radius * 0.88, count + 6, 11, blocked)
		for i, p in spots do
			if i <= count then
				Kit.Tree(decor, rng, p, 0.9 + rng:NextNumber() * 0.5)
			elseif i == count + 1 and island.Radius > 60 then
				buildCrater(decor, rng, p)
			else
				Kit.Flowers(decor, rng, p, 5, 14)
			end
			block(p, 6)
		end
		for _, p in Kit.ScatterPoints(rng, island.Center, island.Radius * 0.9, 4, 20, blocked) do
			local boulder = Kit.Ball(
				decor,
				3 + rng:NextNumber() * 3,
				p + Vector3.new(0, 0.8, 0),
				Color3.fromRGB(176, 166, 204),
				M.Slate,
				false
			)
			boulder.CastShadow = true
		end
	end

	return {
		ImpactPoints = impacts,
		WispPoints = wisps,
		Portals = portals,
		Model = model,
	}
end

return DawnCommonsBuilder

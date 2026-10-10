--!strict
-- The world's fixed layout, shared by the server (which builds it) and the
-- client (which uses it for waypoints, area names and travel). Positions are
-- data, so client guidance never depends on a streamed-in part existing.
--
-- Angles are measured in the XZ plane: 0° = +X (east), 90° = +Z (south),
-- 270° = -Z (north).

local WorldLayout = {}

WorldLayout.GroundY = 40

local function polar(angleDeg: number, radius: number, y: number?): Vector3
	local a = math.rad(angleDeg)
	return Vector3.new(math.cos(a) * radius, y or WorldLayout.GroundY, math.sin(a) * radius)
end
WorldLayout.Polar = polar

local ground = WorldLayout.GroundY

WorldLayout.Hub = {
	Center = Vector3.new(0, ground, 0),
	Radius = 165,
	-- Players spawn on the south plaza, facing the observatory.
	Spawn = CFrame.lookAt(Vector3.new(0, ground + 3, 122), Vector3.new(0, ground + 3, 0)),
	-- The guiding comet lands straight ahead of the spawn.
	TutorialImpact = Vector3.new(0, ground, 66),
	ExaminationStation = Vector3.new(-30, ground, 72),
	Observatory = Vector3.new(0, ground, 0),
	ObservatoryRadius = 34,
	Workshop = Vector3.new(-118, ground, -6),
	MissionBoard = Vector3.new(54, ground, 100),
	Leaderboard = Vector3.new(-54, ground, 100),
	DawnGate = Vector3.new(132, ground, 0),
	-- Portals to later biomes stand in an arc on the north side.
	PortalAngles = { PrismCliffs = 240, ThunderReef = 270, ShadowCrater = 300, AstralExpanse = 330 },
	PortalRadius = 126,
}

-- Personal sanctuaries ring the hub. Plot i sits at angle 15 + 30*(i-1), so
-- the bridge east to Dawn Commons (0°) runs between plots 1 and 12.
WorldLayout.Sanctuary = {
	Count = 12,
	RingRadius = 300,
	PlotRadius = 44,
	FirstAngle = 15,
	AngleStep = 30,
	BridgeWidth = 12,
}

export type PlotLayout = {
	Index: number,
	Angle: number,
	Center: Vector3,
	-- Faces the hub: -LookVector points away from it, toward the back of the plot.
	CFrame: CFrame,
}

local plots: { PlotLayout } = {}
for i = 1, WorldLayout.Sanctuary.Count do
	local angle = WorldLayout.Sanctuary.FirstAngle + WorldLayout.Sanctuary.AngleStep * (i - 1)
	local center = polar(angle, WorldLayout.Sanctuary.RingRadius)
	plots[i] = {
		Index = i,
		Angle = angle,
		Center = center,
		CFrame = CFrame.lookAt(center, Vector3.new(0, ground, 0)),
	}
end
WorldLayout.Plots = plots

-- Habitat slots in plot space (X right, Z toward the back, away from the hub),
-- laid out as two arcs around a courtyard so they face the entrance.
-- Slots 1-4 are the inner arc, 5-12 the outer arc.
local slotOffsets: { Vector3 } = {}
WorldLayout.CourtyardOffset = Vector3.new(0, 0, -6)
do
	local courtyard = WorldLayout.CourtyardOffset
	local function arc(radius: number, deg: number): Vector3
		local a = math.rad(deg)
		return courtyard + Vector3.new(math.sin(a) * radius, 0, math.cos(a) * radius)
	end
	for _, deg in { -20, 20, -60, 60 } do
		table.insert(slotOffsets, arc(19.5, deg))
	end
	for _, deg in { -14, 14, -42, 42, -70, 70, -98, 98 } do
		table.insert(slotOffsets, arc(33, deg))
	end
end
WorldLayout.SlotOffsets = slotOffsets
WorldLayout.PadRadius = 5.5

-- World position of a habitat slot's pad top.
function WorldLayout.SlotPosition(plotIndex: number, slot: number): Vector3
	local plot = plots[plotIndex]
	local offset = slotOffsets[slot]
	-- The plot CFrame looks at the hub, so the back of the plot is -LookVector.
	local cf = plot.CFrame
	return plot.Center + cf.RightVector * offset.X - cf.LookVector * offset.Z + Vector3.new(0, 1.4, 0)
end

-- Arrival point when travelling home: the plot's front entrance.
function WorldLayout.PlotArrival(plotIndex: number): CFrame
	local plot = plots[plotIndex]
	local pos = plot.Center + plot.CFrame.LookVector * (WorldLayout.Sanctuary.PlotRadius - 8) + Vector3.new(0, 3, 0)
	return CFrame.lookAt(pos, Vector3.new(plot.Center.X, pos.Y, plot.Center.Z))
end

export type BiomeLayout = {
	Center: Vector3,
	Radius: number,
	Arrival: CFrame,
	ReturnPortal: Vector3,
}

WorldLayout.Biomes = {
	DawnCommons = {
		Center = Vector3.new(690, ground, 0),
		Radius = 380,
		Arrival = CFrame.lookAt(Vector3.new(530, ground + 3, 6), Vector3.new(640, ground + 3, 6)),
		ReturnPortal = Vector3.new(508, ground, -26),
	},
	-- Reserved space for Phase 2 biomes (not built yet).
	PrismCliffs = {
		Center = Vector3.new(-120, ground + 30, -760),
		Radius = 360,
		Arrival = CFrame.new(-120, ground + 33, -520),
		ReturnPortal = Vector3.new(-100, ground + 30, -500),
	},
	ThunderReef = {
		Center = Vector3.new(-760, ground, 120),
		Radius = 380,
		Arrival = CFrame.new(-520, ground + 3, 120),
		ReturnPortal = Vector3.new(-500, ground, 100),
	},
	ShadowCrater = {
		Center = Vector3.new(160, ground - 40, 820),
		Radius = 380,
		Arrival = CFrame.new(160, ground - 37, 560),
		ReturnPortal = Vector3.new(140, ground - 40, 540),
	},
	AstralExpanse = {
		Center = Vector3.new(0, ground + 220, 0),
		Radius = 420,
		Arrival = CFrame.new(0, ground + 223, 300),
		ReturnPortal = Vector3.new(20, ground + 220, 300),
	},
} :: { [string]: BiomeLayout }

export type Area = {
	Kind: "Hub" | "Sanctuary" | "Biome" | "Wilds",
	Id: string,
	PlotIndex: number?,
}

-- Which named area a position is in. Cheap enough to call every frame.
function WorldLayout.GetArea(position: Vector3): Area
	local flat = Vector3.new(position.X, 0, position.Z)
	if flat.Magnitude <= WorldLayout.Hub.Radius + 12 then
		return { Kind = "Hub", Id = "Hub" }
	end
	local plotRadius = WorldLayout.Sanctuary.PlotRadius + 4
	for _, plot in plots do
		local d = Vector3.new(plot.Center.X - position.X, 0, plot.Center.Z - position.Z).Magnitude
		if d <= plotRadius then
			return { Kind = "Sanctuary", Id = "Sanctuary", PlotIndex = plot.Index }
		end
	end
	for id, biome in WorldLayout.Biomes do
		local d = Vector3.new(biome.Center.X - position.X, 0, biome.Center.Z - position.Z).Magnitude
		if d <= biome.Radius and math.abs(position.Y - biome.Center.Y) < 260 then
			return { Kind = "Biome", Id = id }
		end
	end
	return { Kind = "Wilds", Id = "Wilds" }
end

return WorldLayout

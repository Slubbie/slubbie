-- Terrain helpers for the world builders. The ground surface is Y = 0 unless
-- a builder raises hills or carves caves. Terrain voxels are 4 studs, so
-- painting a surface means filling the top 4-stud layer (Y -4..0).

local TerrainKit = {}

local terrain = workspace.Terrain

local function fill(fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn("[Evergrove] Terrain fill failed:", err)
	end
end

-- A solid slab of `material` whose top surface is at `top`.
function TerrainKit.Slab(center: Vector3, sizeX: number, sizeZ: number, depth: number, material: Enum.Material, top: number?)
	local y = (top or 0) - depth / 2
	fill(function()
		terrain:FillBlock(CFrame.new(center.X, y, center.Z), Vector3.new(sizeX, depth, sizeZ), material)
	end)
end

-- Repaint the surface layer of a disc.
function TerrainKit.PaintDisc(center: Vector3, radius: number, material: Enum.Material, top: number?)
	local surface = top or 0
	fill(function()
		terrain:FillCylinder(CFrame.new(center.X, surface - 2, center.Z), 4, radius, material)
	end)
end

-- Repaint the surface along a straight strip (roads, paths).
function TerrainKit.PaintStrip(a: Vector3, b: Vector3, width: number, material: Enum.Material, top: number?)
	local flatA = Vector3.new(a.X, 0, a.Z)
	local flatB = Vector3.new(b.X, 0, b.Z)
	local length = (flatB - flatA).Magnitude
	if length < 0.5 then
		return
	end
	local mid = (flatA + flatB) / 2
	local surface = top or 0
	fill(function()
		local cf = CFrame.lookAt(Vector3.new(mid.X, surface - 2, mid.Z), Vector3.new(flatB.X, surface - 2, flatB.Z))
		terrain:FillBlock(cf, Vector3.new(width, 4, length + width * 0.5), material)
	end)
end

-- A water body (disc) with a shelving bank of `bank` material around it.
function TerrainKit.Lake(center: Vector3, radius: number, depth: number, bank: Enum.Material?, surface: number?)
	local top = surface or center.Y
	fill(function()
		if bank then
			terrain:FillCylinder(CFrame.new(center.X, top - 2, center.Z), 4, radius + 8, bank)
		end
		-- Clear anything above the waterline, then fill water down to the bed.
		terrain:FillCylinder(CFrame.new(center.X, top + 10, center.Z), 20, radius, Enum.Material.Air)
		terrain:FillCylinder(CFrame.new(center.X, top - depth / 2, center.Z), depth, radius, Enum.Material.Water)
		terrain:FillCylinder(CFrame.new(center.X, top - depth - 2, center.Z), 4, radius, bank or Enum.Material.Mud)
	end)
end

-- A water channel following a polyline (rivers, streams).
function TerrainKit.River(points: { Vector3 }, width: number, depth: number, bank: Enum.Material?)
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local flatA = Vector3.new(a.X, 0, a.Z)
		local flatB = Vector3.new(b.X, 0, b.Z)
		local length = (flatB - flatA).Magnitude
		local mid = (flatA + flatB) / 2
		fill(function()
			local look = CFrame.lookAt(Vector3.new(mid.X, 0, mid.Z), Vector3.new(flatB.X, 0, flatB.Z))
			if bank then
				terrain:FillBlock(look * CFrame.new(0, -2, 0), Vector3.new(width + 12, 4, length + width), bank)
			end
			terrain:FillBlock(look * CFrame.new(0, 10, 0), Vector3.new(width, 20, length + width), Enum.Material.Air)
			terrain:FillBlock(look * CFrame.new(0, -depth / 2, 0), Vector3.new(width, depth, length + width), Enum.Material.Water)
		end)
		-- Round joints so bends don't leave gaps.
		fill(function()
			terrain:FillCylinder(CFrame.new(b.X, -depth / 2, b.Z), depth, width / 2, Enum.Material.Water)
		end)
	end
end

-- A rounded hill; `height` above the ground.
function TerrainKit.Hill(center: Vector3, radius: number, height: number, material: Enum.Material, cap: Enum.Material?)
	fill(function()
		local r = radius
		-- Ellipsoid approximated with stacked balls.
		local steps = math.max(2, math.floor(height / 8))
		for i = 0, steps do
			local t = i / steps
			local layerRadius = r * math.sqrt(1 - t * t * 0.9)
			local y = center.Y + height * t - layerRadius * 0.6
			terrain:FillBall(Vector3.new(center.X, y, center.Z), layerRadius, material)
		end
		if cap then
			terrain:FillBall(Vector3.new(center.X, center.Y + height - radius * 0.25, center.Z), radius * 0.45, cap)
		end
	end)
end

-- A flat raised plateau (observatory hill, ruins terraces).
function TerrainKit.Plateau(center: Vector3, radius: number, height: number, material: Enum.Material, top: Enum.Material?)
	fill(function()
		terrain:FillCylinder(CFrame.new(center.X, height / 2 - 2, center.Z), height + 4, radius, material)
		terrain:FillCylinder(CFrame.new(center.X, height - 2, center.Z), 4, radius, top or material)
	end)
end

-- A hollow cave level: solid rock block with a carved chamber whose floor is at `floor`.
function TerrainKit.Cave(center: Vector3, radius: number, floor: number, height: number, rock: Enum.Material, ground: Enum.Material, seed: number)
	fill(function()
		terrain:FillBlock(CFrame.new(center.X, floor + height / 2, center.Z), Vector3.new(radius * 2 + 40, height + 40, radius * 2 + 40), rock)
		terrain:FillCylinder(CFrame.new(center.X, floor + height / 2, center.Z), height, radius, Enum.Material.Air)
		terrain:FillCylinder(CFrame.new(center.X, floor - 2, center.Z), 4, radius, ground)
		local rng = Random.new(seed)
		-- Side chambers and pillars for shape.
		for _ = 1, 10 do
			local a = rng:NextNumber(0, math.pi * 2)
			local d = rng:NextNumber(radius * 0.7, radius * 1.05)
			terrain:FillBall(Vector3.new(center.X + math.cos(a) * d, floor + height * 0.45, center.Z + math.sin(a) * d), rng:NextNumber(20, 34), Enum.Material.Air)
			terrain:FillCylinder(CFrame.new(center.X + math.cos(a) * d, floor - 2, center.Z + math.sin(a) * d), 4, 24, ground)
		end
		for _ = 1, 7 do
			local a = rng:NextNumber(0, math.pi * 2)
			local d = rng:NextNumber(radius * 0.25, radius * 0.8)
			terrain:FillCylinder(CFrame.new(center.X + math.cos(a) * d, floor + height / 2, center.Z + math.sin(a) * d), height, rng:NextNumber(5, 10), rock)
		end
	end)
end

-- A floating island (grass top, rocky underside).
function TerrainKit.Island(center: Vector3, radius: number, top: Enum.Material, under: Enum.Material)
	fill(function()
		-- Rocky underside (kept below the surface), then an 8-stud grass cap.
		terrain:FillBall(Vector3.new(center.X, center.Y - radius * 0.85, center.Z), radius * 0.8, under)
		terrain:FillBall(Vector3.new(center.X, center.Y - radius * 1.3, center.Z), radius * 0.45, under)
		terrain:FillCylinder(CFrame.new(center.X, center.Y - 4, center.Z), 8, radius, top)
	end)
end

return TerrainKit

-- Environment queries for the movement controller: ground, walls, ledges,
-- vaultable cover, climbable surfaces, ziplines, ropes and grapple anchors.
--
-- Everything here is a pure query (raycasts and maths); the controller decides
-- what to do with the results. Heights are measured from the root part, which
-- sits Movement.RootHeight (3) studs above the floor.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MathUtil = require(ReplicatedStorage.Shared.Util.MathUtil)
local Tags = require(ReplicatedStorage.Shared.Tags)

local Sensors = {}

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.CollisionGroup = Tags.Groups.Players
params.RespectCanCollide = true

-- Ignore the character, ghosts and (optionally) more instances.
function Sensors.SetIgnore(list: { Instance })
	params.FilterDescendantsInstances = list
end

function Sensors.Params(): RaycastParams
	return params
end

local function cast(origin: Vector3, direction: Vector3): RaycastResult?
	return workspace:Raycast(origin, direction, params)
end
Sensors.Cast = cast

local function flagged(instance: Instance, tag: string): boolean
	return CollectionService:HasTag(instance, tag) or instance:GetAttribute(tag) == true
end

local function isWall(hit: RaycastResult?): boolean
	return hit ~= nil and math.abs(hit.Normal.Y) < 0.35
end

-- Ground ---------------------------------------------------------------------------------

export type Ground = { Part: BasePart, Position: Vector3, Normal: Vector3, Material: Enum.Material, Distance: number }

-- What's under the character (from the root, down to just below the feet).
function Sensors.Ground(root: BasePart, reach: number?): Ground?
	local origin = root.Position
	local hit = cast(origin, Vector3.new(0, -(reach or 3.6), 0))
	if not hit then
		-- Edges: probe a ring of points so standing on a corner still counts.
		for _, offset in { Vector3.new(0.8, 0, 0), Vector3.new(-0.8, 0, 0), Vector3.new(0, 0, 0.5), Vector3.new(0, 0, -0.5) } do
			hit = cast(origin + root.CFrame:VectorToWorldSpace(offset), Vector3.new(0, -(reach or 3.6), 0))
			if hit then
				break
			end
		end
	end
	if not hit or hit.Normal.Y < 0.55 then
		return nil
	end
	local part = hit.Instance :: BasePart
	return { Part = part, Position = hit.Position, Normal = hit.Normal, Material = hit.Material, Distance = origin.Y - hit.Position.Y }
end

-- Is there room above to stand up (after crouching or sliding)?
function Sensors.Headroom(root: BasePart): boolean
	local origin = root.Position - Vector3.new(0, 1, 0)
	for _, offset in { Vector3.zero, Vector3.new(0.6, 0, 0), Vector3.new(-0.6, 0, 0) } do
		local p = origin + root.CFrame:VectorToWorldSpace(offset)
		local hit = cast(p, Vector3.new(0, 3.6, 0))
		if hit then
			return false
		end
		-- Low clearance parts don't collide while crouched, so check them explicitly.
		local parts = workspace:GetPartBoundsInRadius(p + Vector3.new(0, 2.6, 0), 0.9)
		for _, part in parts do
			if CollectionService:HasTag(part, Tags.LowClearance) then
				return false
			end
		end
	end
	return true
end

-- Walls -----------------------------------------------------------------------------------

export type Wall = { Part: BasePart, Normal: Vector3, Position: Vector3, Distance: number }

-- A runnable wall beside the character, roughly parallel to the direction of travel.
function Sensors.WallSide(root: BasePart, direction: Vector3, reach: number): Wall?
	local dir = MathUtil.FlatUnit(direction)
	local right = dir:Cross(Vector3.yAxis)
	local best: Wall? = nil
	for _, side in { right, -right } do
		for _, dy in { 0, 1.2 } do
			local hit = cast(root.Position + Vector3.new(0, dy, 0), side * reach)
			if isWall(hit) and not flagged((hit :: RaycastResult).Instance, Tags.NoWallRun) then
				local h = hit :: RaycastResult
				local normal = MathUtil.FlatUnit(h.Normal)
				if math.abs(normal:Dot(dir)) < 0.62 then
					local distance = (h.Position - root.Position).Magnitude
					if not best or distance < best.Distance then
						best = { Part = h.Instance :: BasePart, Normal = normal, Position = h.Position, Distance = distance }
					end
				end
			end
		end
	end
	return best
end

-- The nearest wall in any horizontal direction (for wall kicks).
function Sensors.WallNear(root: BasePart, reach: number): Wall?
	local best: Wall? = nil
	for i = 0, 7 do
		local angle = i * math.pi / 4
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local hit = cast(root.Position, dir * reach)
		if isWall(hit) and not flagged((hit :: RaycastResult).Instance, Tags.NoWallRun) then
			local h = hit :: RaycastResult
			local distance = (h.Position - root.Position).Magnitude
			if not best or distance < best.Distance then
				best = { Part = h.Instance :: BasePart, Normal = MathUtil.FlatUnit(h.Normal), Position = h.Position, Distance = distance }
			end
		end
	end
	return best
end

-- A wall straight ahead (for wall climbs and climbing surfaces).
function Sensors.WallAhead(root: BasePart, direction: Vector3, reach: number): Wall?
	local dir = MathUtil.FlatUnit(direction)
	for _, dy in { 0.5, -0.8, 1.6 } do
		local hit = cast(root.Position + Vector3.new(0, dy, 0), dir * reach)
		if isWall(hit) then
			local h = hit :: RaycastResult
			return { Part = h.Instance :: BasePart, Normal = MathUtil.FlatUnit(h.Normal), Position = h.Position, Distance = (h.Position - root.Position).Magnitude }
		end
	end
	return nil
end

-- A climbable surface ahead.
function Sensors.Climbable(root: BasePart, direction: Vector3, reach: number): Wall?
	local dir = MathUtil.FlatUnit(direction)
	for _, dy in { 0.6, -0.6, 1.6 } do
		local hit = cast(root.Position + Vector3.new(0, dy, 0), dir * reach)
		if hit and CollectionService:HasTag(hit.Instance, Tags.Climbable) and math.abs(hit.Normal.Y) < 0.5 then
			return { Part = hit.Instance :: BasePart, Normal = MathUtil.FlatUnit(hit.Normal), Position = hit.Position, Distance = (hit.Position - root.Position).Magnitude }
		end
	end
	return nil
end

-- Does a climbable surface continue at this root position (facing -normal)?
function Sensors.ClimbAt(position: Vector3, normal: Vector3, reach: number): (BasePart?, Vector3?)
	for _, dy in { 0, 1.2 } do
		local hit = cast(position + Vector3.new(0, dy, 0), -normal * (reach + 0.6))
		if hit and CollectionService:HasTag(hit.Instance, Tags.Climbable) then
			return hit.Instance :: BasePart, MathUtil.FlatUnit(hit.Normal)
		end
	end
	return nil, nil
end

-- Ledges ------------------------------------------------------------------------------------

export type Ledge = {
	Part: BasePart,
	Point: Vector3, -- on the top edge, at the face
	Normal: Vector3, -- out of the wall (horizontal)
	TopY: number,
	CanMantle: boolean,
}

-- A grabbable ledge ahead of the root within the height window.
function Sensors.Ledge(root: BasePart, direction: Vector3, reach: number, minAbove: number, maxAbove: number): Ledge?
	return Sensors.LedgeFrom(root.Position, direction, reach, minAbove, maxAbove)
end

-- Same as Ledge, probing from an arbitrary point (used to look for the next ledge from a hang).
function Sensors.LedgeFrom(origin: Vector3, direction: Vector3, reach: number, minAbove: number, maxAbove: number): Ledge?
	local dir = MathUtil.FlatUnit(direction)
	local wallHit: RaycastResult? = nil
	for _, dy in { 0.6, 1.6, -0.4 } do
		local hit = cast(origin + Vector3.new(0, dy, 0), dir * reach)
		if isWall(hit) then
			wallHit = hit
			break
		end
	end
	if not wallHit then
		return nil
	end
	local normal = MathUtil.FlatUnit(wallHit.Normal)
	if flagged(wallHit.Instance, Tags.NoLedge) then
		return nil
	end
	-- Probe down just inside the wall face for the top surface.
	local probe = Vector3.new(wallHit.Position.X, origin.Y + maxAbove + 1.5, wallHit.Position.Z) - normal * 0.4
	local top = cast(probe, Vector3.new(0, -(maxAbove - minAbove + 1.5), 0))
	if not top or top.Normal.Y < 0.7 or flagged(top.Instance, Tags.NoLedge) then
		return nil
	end
	local topY = top.Position.Y
	local above = topY - origin.Y
	if above < minAbove or above > maxAbove then
		return nil
	end
	-- Something solid right above the ledge means it's a slot, not a ledge.
	local lip = Vector3.new(wallHit.Position.X, topY, wallHit.Position.Z) + normal * 0.05
	if cast(lip + normal * 0.6 + Vector3.new(0, 0.3, 0), Vector3.new(0, 1.2, 0)) then
		return nil
	end
	-- Room to climb up and stand?
	local standPoint = lip - normal * 1.6 + Vector3.new(0, 0.2, 0)
	local headroom = cast(standPoint, Vector3.new(0, 4.6, 0))
	local depth = cast(lip + Vector3.new(0, 2.5, 0) + normal * 0.4, -normal * 2.2)
	local canMantle = headroom == nil and depth == nil
	return { Part = top.Instance :: BasePart, Point = lip, Normal = normal, TopY = topY, CanMantle = canMantle }
end

-- Is there still a ledge at this hang point (used for shimmying)?
function Sensors.LedgeAt(point: Vector3, normal: Vector3): (BasePart?, number?)
	local probe = point - normal * 0.4 + Vector3.new(0, 1.2, 0)
	local top = cast(probe, Vector3.new(0, -2, 0))
	if not top or top.Normal.Y < 0.7 or math.abs(top.Position.Y - point.Y) > 0.6 then
		return nil, nil
	end
	-- The wall face must still be there below the lip.
	local face = cast(point + normal * 1.2 - Vector3.new(0, 0.8, 0), -normal * 2)
	if not face then
		return nil, nil
	end
	return top.Instance :: BasePart, top.Position.Y
end

-- Vaulting ------------------------------------------------------------------------------------

export type Vault = {
	Kind: string, -- "Vault" (over) | "Step" (up onto a low block)
	Front: Vector3,
	TopY: number,
	Depth: number,
	Landing: Vector3,
	Normal: Vector3,
}

-- Low cover ahead: something between knee and chest height that can be vaulted
-- (thin) or stepped onto (deep).
function Sensors.Vault(root: BasePart, direction: Vector3, reach: number, minHeight: number, maxHeight: number, maxDepth: number, rootHeight: number): Vault?
	local dir = MathUtil.FlatUnit(direction)
	local feet = root.Position.Y - rootHeight
	local knee = cast(Vector3.new(root.Position.X, feet + 1.1, root.Position.Z), dir * reach)
	if not isWall(knee) then
		return nil
	end
	local hit = knee :: RaycastResult
	-- Nothing at head height: it's low cover, not a wall.
	if cast(Vector3.new(root.Position.X, feet + maxHeight + 0.7, root.Position.Z), dir * (reach + 1)) then
		return nil
	end
	local normal = MathUtil.FlatUnit(hit.Normal)
	local front = hit.Position
	local top = cast(Vector3.new(front.X, feet + maxHeight + 0.5, front.Z) - normal * 0.4, Vector3.new(0, -(maxHeight + 0.5), 0))
	if not top or top.Normal.Y < 0.7 then
		return nil
	end
	local height = top.Position.Y - feet
	if height < minHeight or height > maxHeight then
		return nil
	end
	-- How deep is it?
	local depth = maxDepth + 1
	for d = 1, maxDepth + 1, 0.75 do
		local p = Vector3.new(front.X, top.Position.Y + 0.6, front.Z) - normal * d
		local down = cast(p, Vector3.new(0, -1.4, 0))
		if not down then
			depth = d
			break
		end
	end
	if depth <= maxDepth then
		local landing = Vector3.new(front.X, feet, front.Z) - normal * (depth + 1.6)
		-- Land on whatever is behind (or keep falling if nothing is).
		local floor = cast(landing + Vector3.new(0, top.Position.Y - feet + 1, 0), Vector3.new(0, -(top.Position.Y - feet + 6), 0))
		if floor then
			landing = floor.Position
		end
		return { Kind = "Vault", Front = front, TopY = top.Position.Y, Depth = depth, Landing = landing, Normal = normal }
	end
	-- Deep low block: step up onto it if there's room.
	local standPoint = Vector3.new(front.X, top.Position.Y, front.Z) - normal * 1.6
	if cast(standPoint + Vector3.new(0, 0.2, 0), Vector3.new(0, 4.6, 0)) then
		return nil
	end
	return { Kind = "Step", Front = front, TopY = top.Position.Y, Depth = depth, Landing = standPoint, Normal = normal }
end

-- Lines, ropes and anchors ------------------------------------------------------------------

export type ZipCandidate = { Part: BasePart, A: Vector3, B: Vector3, Point: Vector3, T: number }

function Sensors.Zipline(root: BasePart, list: { BasePart }, range: number, hang: number): ZipCandidate?
	local best: ZipCandidate? = nil
	local bestDistance = range
	local hand = root.Position + Vector3.new(0, hang, 0)
	for _, part in list do
		local a, b = part:GetAttribute("A"), part:GetAttribute("B")
		if typeof(a) == "Vector3" and typeof(b) == "Vector3" then
			local point, t = MathUtil.ClosestOnSegment(a, b, hand)
			local distance = (point - hand).Magnitude
			if distance < bestDistance and t > 0.02 and t < 0.97 and point.Y > root.Position.Y then
				best, bestDistance = { Part = part, A = a, B = b, Point = point, T = t }, distance
			end
		end
	end
	return best
end

export type RopeCandidate = { Part: BasePart, Pivot: Vector3, Length: number, Grab: Vector3 }

function Sensors.Rope(root: BasePart, list: { BasePart }, range: number): RopeCandidate?
	local best: RopeCandidate? = nil
	local bestDistance = range
	local hand = root.Position + Vector3.new(0, 1.5, 0)
	for _, part in list do
		local pivot, length = part:GetAttribute("Pivot"), part:GetAttribute("Length")
		if typeof(pivot) == "Vector3" and type(length) == "number" then
			local bottom = pivot - Vector3.new(0, length, 0)
			local point = MathUtil.ClosestOnSegment(pivot, bottom, hand)
			local distance = (point - hand).Magnitude
			if distance < bestDistance then
				best, bestDistance = { Part = part, Pivot = pivot, Length = length, Grab = point }, distance
			end
		end
	end
	return best
end

-- Best grapple anchor near the centre of view and in range, with line of sight.
function Sensors.Anchor(root: BasePart, list: { BasePart }, look: Vector3, range: number, cone: number): BasePart?
	local best, bestScore = nil, math.huge
	local cosCone = math.cos(math.rad(cone))
	for _, part in list do
		local offset = part.Position - root.Position
		local distance = offset.Magnitude
		if distance <= range and distance > 4 then
			local alignment = offset.Unit:Dot(look)
			if alignment >= cosCone then
				local hit = cast(root.Position + Vector3.new(0, 1.5, 0), offset - offset.Unit * 2)
				if not hit or hit.Instance == part then
					local score = (1 - alignment) * 4 + distance / range
					if score < bestScore then
						best, bestScore = part, score
					end
				end
			end
		end
	end
	return best
end

-- Tagged parts inside a box-shaped zone part.
function Sensors.Inside(zone: BasePart, position: Vector3): boolean
	return MathUtil.InBox(zone.CFrame, zone.Size, position)
end

-- Is the floor part a narrow surface (for precision landings)?
function Sensors.IsNarrow(part: BasePart, maxWidth: number): boolean
	local size = part.Size
	local horizontal = math.min(size.X, size.Z)
	if part:IsA("Part") and part.Shape == Enum.PartType.Cylinder then
		horizontal = math.min(size.Y, size.Z)
	end
	return horizontal <= maxWidth or CollectionService:HasTag(part, Tags.Precision)
end

return Sensors

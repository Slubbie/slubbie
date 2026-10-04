-- Builds the entire world headlessly and validates it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")

local Courses = require(ReplicatedStorage.Shared.Config.Courses)
local Quests = require(ReplicatedStorage.Shared.Config.Quests)
local NPCs = require(ReplicatedStorage.Shared.Config.NPCs)
local Lessons = require(ReplicatedStorage.Shared.Config.Lessons)
local Achievements = require(ReplicatedStorage.Shared.Config.Achievements)
local Tags = require(ReplicatedStorage.Shared.Tags)
local WorldBuilder = require(ServerScriptService.Server.World.WorldBuilder)

local started = os.clock()
local metas = WorldBuilder.Build()
print(("build time %.2fs"):format(os.clock() - started))

local problems = 0
local function problem(text)
	problems += 1
	print("PROBLEM: " .. text)
end

-- Every configured course was built.
for _, course in Courses.List do
	if not metas[course.Id] then
		problem("course not built: " .. course.Id)
	end
end

-- Parts per district.
local world = workspace:FindFirstChild("SkylineWorld")
local total = 0
for _, district in world:GetChildren() do
	local count = 0
	for _, d in district:GetDescendants() do
		if d:IsA("BasePart") then count += 1 end
	end
	total += count
	print(("%-12s %6d parts"):format(district.Name, count))
end
print("total parts", total)

-- Quest points referenced by quests exist.
local points = {}
for _, part in CollectionService:GetTagged(Tags.QuestPoint) do
	points[part:GetAttribute("Id")] = part
end
for _, quest in Quests.List do
	for _, step in quest.Steps do
		local ids = {}
		if step.Point then table.insert(ids, step.Point) end
		if step.From then table.insert(ids, step.From) end
		if step.To then
			if type(step.To) == "table" then for _, id in step.To do table.insert(ids, id) end else table.insert(ids, step.To) end
		end
		for _, id in step.Points or {} do table.insert(ids, id) end
		for _, id in ids do
			if not points[id] then problem(("quest %s needs point %s"):format(quest.Id, id)) end
		end
		if step.Course and not metas[step.Course] then problem("quest course missing " .. step.Course) end
	end
end

-- NPC spots.
local spots = {}
for _, part in CollectionService:GetTagged(Tags.NPCSpot) do
	spots[part:GetAttribute("Id")] = true
end
for _, npc in NPCs.List do
	if not spots[npc.Spot] then problem("missing NPC spot " .. npc.Spot) end
end

-- Lessons.
local lessonZones = {}
for _, part in CollectionService:GetTagged(Tags.LessonZone) do
	lessonZones[part:GetAttribute("LessonId")] = true
end
for _, lesson in Lessons.List do
	if not lessonZones[lesson.Id] then problem("missing lesson zone " .. lesson.Id) end
end

-- Discoveries.
local kinds = {}
local ids = {}
for _, part in CollectionService:GetTagged(Tags.Discovery) do
	local kind = part:GetAttribute("Kind")
	kinds[kind] = (kinds[kind] or 0) + 1
	local id = part:GetAttribute("Id")
	if ids[id] then problem("duplicate discovery id " .. id) end
	ids[id] = true
end
for kind, n in kinds do print("discoveries", kind, n) end
for _, a in Achievements.List do
	if a.Stat == "Landmarks" and a.Target > (kinds.Landmark or 0) then problem("landmark achievement unreachable: " .. a.Id) end
	if a.Stat == "Letters" and a.Target > (kinds.Letter or 0) then problem("letter achievement unreachable: " .. a.Id) end
	if string.sub(a.Stat, 1, 7) == "Secret_" and not ids["secret_" .. string.lower(string.sub(a.Stat, 8))] then problem("secret missing for " .. a.Id) end
end

-- Course data sanity.
for id, meta in metas do
	local m = meta.Medals
	if not (m[1] > m[2] and m[2] > m[3] and m[3] > m[4]) then problem("medals out of order " .. id) end
	if #meta.Tokens == 0 and meta.Kind ~= "Tower" then print("note: no tokens on " .. id) end
end

-- Overlaps between different courses (coarse: platform-like parts only).
local cell = 40
local grid = {}
local function key(x, z) return x .. ":" .. z end
local overlapCount = 0
local reported = {}
for id, meta in metas do
	for _, part in meta.Folder:GetDescendants() do
		if part:IsA("BasePart") and part.CanCollide and part.Transparency < 1 then
			local p = part.Position
			local half = part.Size.Magnitude / 2
			for gx = math.floor((p.X - half) / cell), math.floor((p.X + half) / cell) do
				for gz = math.floor((p.Z - half) / cell), math.floor((p.Z + half) / cell) do
					local k = key(gx, gz)
					grid[k] = grid[k] or {}
					table.insert(grid[k], { id = id, part = part })
				end
			end
		end
	end
end
local function aabb(part)
	local c = part.CFrame
	local s = part.Size / 2
	local r = c.RightVector * s.X
	local u = c.UpVector * s.Y
	local l = c.LookVector * s.Z
	local ext = Vector3.new(math.abs(r.X) + math.abs(u.X) + math.abs(l.X), math.abs(r.Y) + math.abs(u.Y) + math.abs(l.Y), math.abs(r.Z) + math.abs(u.Z) + math.abs(l.Z))
	return c.Position - ext, c.Position + ext
end
for _, list in grid do
	for i = 1, #list do
		for j = i + 1, #list do
			local a, b = list[i], list[j]
			if a.id ~= b.id then
				local pair = if a.id < b.id then a.id .. "|" .. b.id else b.id .. "|" .. a.id
				if not reported[pair] then
					local amin, amax = aabb(a.part)
					local bmin, bmax = aabb(b.part)
					if amin.X < bmax.X - 0.5 and amax.X > bmin.X + 0.5 and amin.Y < bmax.Y - 0.5 and amax.Y > bmin.Y + 0.5 and amin.Z < bmax.Z - 0.5 and amax.Z > bmin.Z + 0.5 then
						reported[pair] = true
						overlapCount += 1
						print(("OVERLAP %s (%s) <-> %s (%s) at %s"):format(a.id, a.part.Name, b.id, b.part.Name, tostring(a.part.Position)))
					end
				end
			end
		end
	end
end
print("course overlaps:", overlapCount)
print("warnings:", #Mock.Warnings)
print(("problems: %d"):format(problems))

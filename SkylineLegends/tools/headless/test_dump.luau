-- Dumps the parts of selected courses for tools/headless/render.py.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local Courses = require(ReplicatedStorage.Shared.Config.Courses)
local Kit = require(ServerScriptService.Server.World.Kit)
local CourseBuilder = require(ServerScriptService.Server.World.CourseBuilder)
local theme = {
	Id = "Test", Surface = Color3.fromRGB(150, 150, 150), SurfaceMaterial = Enum.Material.Concrete,
	Trim = Color3.fromRGB(90, 90, 90), Wall = Color3.fromRGB(120, 110, 100), WallMaterial = Enum.Material.Brick,
	Accent = Color3.fromRGB(255, 140, 0), Signal = Color3.fromRGB(255, 230, 0), Beam = Color3.fromRGB(140, 90, 50),
	BeamMaterial = Enum.Material.Wood, Rope = Color3.fromRGB(200, 180, 130), Climb = "Ladder", BodyDepth = 0,
}
local world = Instance.new("Folder")
world.Parent = workspace
local B = Kit.new(world, "Test", {})
for _, id in string.split(DUMP_IDS, ",") do
	local course = Courses.ById[id]
	local origin = CFrame.new(0, 100, 0)
	local meta = CourseBuilder.Build(B, course, theme, origin)
	print("COURSE|" .. id)
	local function dump(part)
		if not part:IsA("BasePart") then return end
		local c = part.CFrame
		local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = c:GetComponents()
		local col = part.Color
		print(("PART|%s|%f|%f|%f|%f|%f|%f|%f|%f|%f|%f|%f|%f|%f|%f|%f|%d|%d|%d|%f|%s"):format(
			part.Name, x, y - 100, z, r00, r01, r02, r10, r11, r12, r20, r21, r22, part.Size.X, part.Size.Y, part.Size.Z,
			math.floor(col.R * 255), math.floor(col.G * 255), math.floor(col.B * 255), part.Transparency,
			table.concat(CollectionService:GetTags(part), ";")))
	end
	for _, part in meta.Folder:GetDescendants() do dump(part) end
	for _, cp in meta.Checkpoints do
		print(("CP|%f|%f|%f"):format(cp.Spawn.X, cp.Spawn.Y - 100, cp.Spawn.Z))
	end
	for _, t in meta.Tokens do
		print(("TOKEN|%f|%f|%f"):format(t.X, t.Y - 100, t.Z))
	end
	world:ClearAllChildren()
	B = Kit.new(world, "Test", {})
end

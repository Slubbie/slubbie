-- Builds every course recipe with a plain theme and checks the results.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Courses = require(ReplicatedStorage.Shared.Config.Courses)
local Kit = require(ServerScriptService.Server.World.Kit)
local CourseBuilder = require(ServerScriptService.Server.World.CourseBuilder)

local theme = {
	Id = "Test", Surface = Color3.new(0.5, 0.5, 0.5), SurfaceMaterial = Enum.Material.Concrete,
	Trim = Color3.new(0.3, 0.3, 0.3), Wall = Color3.new(0.6, 0.6, 0.6), WallMaterial = Enum.Material.Brick,
	Accent = Color3.new(1, 0.5, 0), Signal = Color3.new(1, 1, 0), Beam = Color3.new(0.5, 0.3, 0.2),
	BeamMaterial = Enum.Material.Wood, Rope = Color3.new(0.8, 0.7, 0.5), Climb = "Ladder", BodyDepth = 30,
}
local world = Instance.new("Folder")
world.Parent = workspace
local B = Kit.new(world, "Test", {})
local failures = 0
for index, course in Courses.List do
	local origin = CFrame.new(index * 400, 100, 0)
	local ok, meta = pcall(CourseBuilder.Build, B, course, theme, origin)
	if not ok then
		failures += 1
		print("FAIL " .. course.Id .. ": " .. tostring(meta))
	else
		local m = meta.Medals
		assert(m[1] > m[2] and m[2] > m[3] and m[3] > m[4], course.Id .. " medals not ordered")
		local cps = 0
		for _, line in course.Segments do if line[1] == "CP" then cps += 1 end end
		assert(#meta.Checkpoints == cps, course.Id .. " checkpoint count")
		print(("%-22s par A %5.1f F %5.1f E %5.1f  medals %5.1f/%5.1f/%5.1f/%5.1f  len %4d  tokens %d  req {%s} fast {%s} exp {%s} killY %.0f"):format(
			course.Id, meta.Par.A, meta.Par.F, meta.Par.E, m[1], m[2], m[3], m[4], math.floor(meta.Length), #meta.Tokens,
			table.concat(meta.Requires, ","), table.concat(meta.FastRequires, ","), table.concat(meta.ExpertRequires, ","), meta.KillY - origin.Y))
	end
end
print(("parts: %d, failures: %d"):format(B.Parts, failures))

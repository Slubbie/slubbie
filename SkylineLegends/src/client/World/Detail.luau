-- Level of detail for a city of tens of thousands of parts.
--
-- Every district is built as Core (everything you can touch), Decor (windows,
-- railings, plants, lights) and Far (large silhouettes that are always shown).
-- Decor is only kept for districts near the camera, and on Low quality the
-- Core of distant districts is dropped too; their Far silhouettes still give
-- the skyline its shape. Changes happen locally on this client only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Districts = require(ReplicatedStorage.Shared.Config.Districts)

local Settings = require(script.Parent.Parent.Core.Settings)
local Controller = require(script.Parent.Parent.Movement.Controller)

local Detail = {}

type Entry = {
	Root: Instance,
	Center: Vector3,
	Core: Instance?,
	Decor: Instance?,
	CoreShown: boolean,
	DecorShown: boolean,
}

local entries: { Entry } = {}
local stash = Instance.new("Folder")
stash.Name = "SkylineHiddenDetail"

local function centerFor(root: Instance): Vector3
	local id = root:GetAttribute("District") or root.Name
	if id == "Dreamline" then
		return Districts.Dreamline
	elseif id == "Spire" then
		return Districts.ById.Hub.Origin + Districts.SpireOffset
	end
	local district = Districts.ById[id]
	if district then
		return district.Origin
	end
	if root:IsA("Model") then
		return root:GetPivot().Position
	end
	return Vector3.zero
end

local function scan(world: Instance)
	table.clear(entries)
	for _, root in world:GetChildren() do
		local core = root:FindFirstChild("Core")
		local decor = root:FindFirstChild("Decor")
		if core or decor then
			table.insert(entries, {
				Root = root,
				Center = centerFor(root),
				Core = core,
				Decor = decor,
				CoreShown = true,
				DecorShown = true,
			})
		end
	end
end

-- Distances (flat, studs) within which detail is kept, by quality.
local RANGES = {
	High = { Decor = 1300, Core = math.huge },
	Medium = { Decor = 950, Core = math.huge },
	Low = { Decor = 650, Core = 1500 },
}

function Detail.Update(position: Vector3)
	local range = RANGES[Settings.Quality()] or RANGES.High
	for _, entry in entries do
		local offset = entry.Center - position
		local distance = Vector3.new(offset.X, offset.Y * 0.5, offset.Z).Magnitude
		local wantDecor = distance < range.Decor
		local wantCore = distance < range.Core
		if entry.Decor and wantDecor ~= entry.DecorShown then
			entry.DecorShown = wantDecor
			entry.Decor.Parent = if wantDecor then entry.Root else stash
		end
		if entry.Core and wantCore ~= entry.CoreShown then
			entry.CoreShown = wantCore
			entry.Core.Parent = if wantCore then entry.Root else stash
		end
	end
end

function Detail.Start()
	local world = workspace:WaitForChild("SkylineWorld", 60)
	if not world then
		return
	end
	-- Give replication a moment to deliver the district folders.
	task.wait(1)
	scan(world)
	world.ChildAdded:Connect(function()
		task.defer(scan, world)
	end)
	local last = 0
	local function update()
		local root = Controller.Info.Root
		local camera = workspace.CurrentCamera
		local position = if root then root.Position elseif camera then camera.CFrame.Position else nil
		if position then
			Detail.Update(position)
		end
	end
	RunService.Heartbeat:Connect(function()
		if os.clock() - last > 0.75 then
			last = os.clock()
			update()
		end
	end)
	-- Teleports must arrive in a fully built district.
	Controller.Teleported:Connect(function(cframe: CFrame)
		Detail.Update(cframe.Position)
	end)
	Settings.Changed:Connect(function(id)
		if id == "Quality" then
			update()
		end
	end)
end

return Detail

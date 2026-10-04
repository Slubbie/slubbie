-- Ghost replays: translucent runners that retrace a recorded run in step with
-- your own clock, so you can see exactly where a better line gains time.
-- Ghosts are local R6 rigs animated by the same Animator as players.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GhostCodec = require(ReplicatedStorage.Shared.Logic.GhostCodec)
local Net = require(ReplicatedStorage.Shared.Net)
local Tags = require(ReplicatedStorage.Shared.Tags)

local Ghosts = {}

type Ghost = { Model: Model, Frames: { GhostCodec.Frame }, Label: string, Color: Color3, Time: number? }

local active: { Ghost } = {}
local folder = Instance.new("Folder")
folder.Name = "SkylineGhosts"

local COLORS = {
	Best = Color3.fromRGB(120, 220, 255),
	Ranked = Color3.fromRGB(120, 220, 255),
	Top = Color3.fromRGB(255, 205, 80),
	Friend = Color3.fromRGB(150, 255, 160),
	Last = Color3.fromRGB(220, 220, 230),
}

local function part(model: Model, name: string, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.ForceField
	p.Transparency = 0.35
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.CollisionGroup = Tags.Groups.Ghosts
	p.Parent = model
	return p
end

local function motor(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = c0
	m.C1 = c1
	m.Parent = part0
end

-- A standard R6 rig built from parts (no assets needed).
local function buildRig(color: Color3, label: string): Model
	local model = Instance.new("Model")
	model.Name = "Ghost_" .. label
	local root = part(model, "HumanoidRootPart", Vector3.new(2, 2, 1), color)
	root.Transparency = 1
	root.Anchored = true
	local torso = part(model, "Torso", Vector3.new(2, 2, 1), color)
	local head = part(model, "Head", Vector3.new(2, 1, 1), color)
	local leftArm = part(model, "Left Arm", Vector3.new(1, 2, 1), color)
	local rightArm = part(model, "Right Arm", Vector3.new(1, 2, 1), color)
	local leftLeg = part(model, "Left Leg", Vector3.new(1, 2, 1), color)
	local rightLeg = part(model, "Right Leg", Vector3.new(1, 2, 1), color)
	local rootC = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
	motor("RootJoint", root, torso, rootC, rootC)
	motor("Neck", torso, head, CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
	motor("Right Shoulder", torso, rightArm, CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	motor("Left Shoulder", torso, leftArm, CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))
	motor("Right Hip", torso, rightLeg, CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	motor("Left Hip", torso, leftLeg, CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))
	model.PrimaryPart = root

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(140, 26)
	gui.StudsOffset = Vector3.new(0, 3, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 140
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = color
	text.TextStrokeTransparency = 0.4
	text.Text = label
	text.Parent = gui
	gui.Parent = head

	model:SetAttribute("RigKind", "Ghost")
	model:SetAttribute("MS", "Ground")
	return model
end

-- Fetch and spawn a ghost. which: "Best" | "Ranked" | "Top" | "Friend".
function Ghosts.Load(courseId: string, which: string): boolean
	local ok, encoded = pcall(Net.Invoke, "Course.GetGhost", courseId, which)
	if not ok or type(encoded) ~= "table" then
		return false
	end
	return Ghosts.Add(encoded, which)
end

-- Spawn a ghost from encoded data (e.g. your own last run).
function Ghosts.Add(encoded: any, kind: string): boolean
	local frames = GhostCodec.Decode(encoded)
	if not frames or #frames < 2 then
		return false
	end
	local color = COLORS[kind] or COLORS.Best
	local name = if type(encoded.Name) == "string" then encoded.Name else kind
	local label = if kind == "Top" then "★ " .. name elseif kind == "Friend" then name else "Your best"
	if type(encoded.Time) == "number" then
		label ..= ("  %.2f"):format(encoded.Time)
	end
	local model = buildRig(color, label)
	model.Parent = folder
	CollectionService:AddTag(model, Tags.Rig)
	table.insert(active, { Model = model, Frames = frames, Label = label, Color = color, Time = encoded.Time })
	return true
end

function Ghosts.Clear()
	for _, ghost in active do
		ghost.Model:Destroy()
	end
	table.clear(active)
end

function Ghosts.Count(): number
	return #active
end

-- Place every ghost at `elapsed` seconds into its run.
function Ghosts.Update(elapsed: number)
	for _, ghost in active do
		local frames = ghost.Frames
		local position = math.max(elapsed, 0) * GhostCodec.Rate + 1
		local index = math.clamp(math.floor(position), 1, #frames)
		local nextIndex = math.min(index + 1, #frames)
		local alpha = math.clamp(position - index, 0, 1)
		local a, b = frames[index], frames[nextIndex]
		local p = Vector3.new(a.X, a.Y, a.Z):Lerp(Vector3.new(b.X, b.Y, b.Z), alpha)
		local yawA, yawB = math.rad(a.Yaw), math.rad(b.Yaw)
		local delta = (yawB - yawA + math.pi) % (math.pi * 2) - math.pi
		local yaw = yawA + delta * alpha
		local model = ghost.Model
		model:PivotTo(CFrame.new(p) * CFrame.Angles(0, yaw, 0))
		model:SetAttribute("MS", a.State)
		model:SetAttribute("GV", (Vector3.new(b.X, b.Y, b.Z) - Vector3.new(a.X, a.Y, a.Z)) * GhostCodec.Rate)
		-- Finished ghosts fade out.
		local finished = index >= #frames
		for _, child in model:GetChildren() do
			if child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" then
				child.Transparency = if finished then 0.85 else 0.35
			end
		end
	end
end

-- Recording -----------------------------------------------------------------------------------------

local recording: { GhostCodec.Frame }? = nil
local nextSample = 0

function Ghosts.BeginRecording()
	recording = {}
	nextSample = 0
end

function Ghosts.Sample(elapsed: number, root: BasePart, state: string)
	local frames = recording
	if not frames or elapsed < 0 then
		return
	end
	while elapsed >= nextSample do
		local look = root.CFrame.LookVector
		local p = root.Position
		table.insert(frames, {
			X = p.X,
			Y = p.Y,
			Z = p.Z,
			Yaw = math.deg(math.atan2(-look.X, -look.Z)),
			State = state,
		})
		nextSample += 1 / GhostCodec.Rate
		if #frames > GhostCodec.MaxSeconds * GhostCodec.Rate then
			recording = nil
			return
		end
	end
end

function Ghosts.EndRecording(splits: { number }?, seconds: number?): any?
	local frames = recording
	recording = nil
	if not frames or #frames < 2 then
		return nil
	end
	return GhostCodec.Encode(frames, splits, seconds)
end

function Ghosts.Start()
	folder.Parent = workspace
end

return Ghosts

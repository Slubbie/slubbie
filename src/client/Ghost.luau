-- Ghost replays for time trials.
--
-- While you run a course your path is sampled 10 times a second. Set a record
-- and the recording is saved; next time you run that course a shimmering ghost
-- of your best run races alongside you, and every ring shows how far ahead or
-- behind you are.
--
-- Format: "1|split2,split3,...|t,x,y,z,yaw;t,x,y,z,yaw;..."

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local SAMPLE_INTERVAL = 0.1
local MAX_SAMPLES = 3000

type Sample = { T: number, Position: Vector3, Yaw: number }

local Ghost = {}

local recording: { string } = {}
local recordedSplits: { [number]: number } = {}
local lastSample = -math.huge

local playback: { Sample } = {}
local playbackSplits: { [number]: number } = {}
local cursor = 1
local figure: Model? = nil
-- Bumped on every hide so a slow load can't resurrect a finished run's ghost.
local loadToken = 0
local parts: { [string]: BasePart } = {}

-- Recording ----------------------------------------------------------------------

function Ghost.StartRecording()
	recording = {}
	recordedSplits = {}
	lastSample = -math.huge
end

function Ghost.Record(root: BasePart, elapsed: number)
	if elapsed - lastSample < SAMPLE_INTERVAL or #recording >= MAX_SAMPLES then
		return
	end
	lastSample = elapsed
	local position = root.Position
	local look = root.CFrame.LookVector
	table.insert(
		recording,
		string.format(
			"%.2f,%.1f,%.1f,%.1f,%.2f",
			elapsed,
			position.X,
			position.Y,
			position.Z,
			math.atan2(-look.X, -look.Z)
		)
	)
end

function Ghost.MarkSplit(ringIndex: number, elapsed: number)
	recordedSplits[ringIndex] = elapsed
end

function Ghost.Encode(): string
	local splits = {}
	local index = 2
	while recordedSplits[index] do
		table.insert(splits, string.format("%.2f", recordedSplits[index]))
		index += 1
	end
	return "1|" .. table.concat(splits, ",") .. "|" .. table.concat(recording, ";")
end

-- Playback -----------------------------------------------------------------------

local function decode(data: string)
	local samples, splits = {}, {}
	local version, splitText, sampleText = string.match(data, "^(%d+)|([^|]*)|(.*)$")
	if version ~= "1" then
		return samples, splits
	end
	local index = 2
	for value in string.gmatch(splitText, "[^,]+") do
		splits[index] = tonumber(value)
		index += 1
	end
	for entry in string.gmatch(sampleText, "[^;]+") do
		local t, x, y, z, yaw = string.match(entry, "^([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)$")
		if t then
			table.insert(samples, {
				T = tonumber(t) :: number,
				Position = Vector3.new(tonumber(x) :: number, tonumber(y) :: number, tonumber(z) :: number),
				Yaw = tonumber(yaw) :: number,
			})
		end
	end
	return samples, splits
end

local function buildFigure(color: Color3)
	local model = Instance.new("Model")
	model.Name = "Ghost"
	local specs = {
		Torso = Vector3.new(2, 2, 1),
		Head = Vector3.new(1.2, 1.2, 1.2),
		LeftArm = Vector3.new(1, 2, 1),
		RightArm = Vector3.new(1, 2, 1),
		LeftLeg = Vector3.new(1, 2, 1),
		RightLeg = Vector3.new(1, 2, 1),
	}
	parts = {}
	for name, size in specs do
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.ForceField
		part.Color = color
		part.Parent = model
		parts[name] = part
	end
	model.Parent = workspace.CurrentCamera
	figure = model
end

function Ghost.Hide()
	loadToken += 1
	if figure then
		figure:Destroy()
		figure = nil
	end
	playback = {}
	playbackSplits = {}
end

-- Fetch and show the saved ghost for a course (yields briefly).
function Ghost.Load(courseId: string, color: Color3)
	Ghost.Hide()
	local token = loadToken
	local ok, data = pcall(function()
		return Net.Function("GetGhost"):InvokeServer(courseId)
	end)
	if token ~= loadToken or not ok or type(data) ~= "string" then
		return
	end
	playback, playbackSplits = decode(data)
	cursor = 1
	if #playback > 1 then
		buildFigure(color)
	end
end

-- Your best time at this ring, if you have a ghost.
function Ghost.GetSplit(ringIndex: number): number?
	return playbackSplits[ringIndex]
end

function Ghost.Update(elapsed: number)
	if not figure or #playback < 2 then
		return
	end
	while cursor < #playback - 1 and playback[cursor + 1].T < elapsed do
		cursor += 1
	end
	local a, b = playback[cursor], playback[math.min(cursor + 1, #playback)]
	local alpha = if b.T > a.T then math.clamp((elapsed - a.T) / (b.T - a.T), 0, 1) else 1
	local position = a.Position:Lerp(b.Position, alpha)
	local yaw = a.Yaw + (b.Yaw - a.Yaw) * alpha
	local root = CFrame.new(position) * CFrame.Angles(0, yaw, 0)

	-- A simple running pose so the ghost reads as a runner.
	local swing = math.sin(elapsed * 12) * 0.8
	local function limb(offset: Vector3, angle: number): CFrame
		return root * CFrame.new(offset + Vector3.new(0, 1, 0)) * CFrame.Angles(angle, 0, 0) * CFrame.new(0, -1, 0)
	end
	parts.Torso.CFrame = root
	parts.Head.CFrame = root * CFrame.new(0, 1.6, 0)
	parts.LeftArm.CFrame = limb(Vector3.new(-1.5, 0, 0), swing)
	parts.RightArm.CFrame = limb(Vector3.new(1.5, 0, 0), -swing)
	parts.LeftLeg.CFrame = limb(Vector3.new(-0.5, -2, 0), -swing)
	parts.RightLeg.CFrame = limb(Vector3.new(0.5, -2, 0), swing)
	-- Fade out once the ghost has finished.
	local done = elapsed > playback[#playback].T + 1
	for _, part in parts do
		part.Transparency = if done then 1 else 0.35
	end
end

return Ghost

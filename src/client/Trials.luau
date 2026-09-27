-- Time trials, client side: detects rings, highlights the next one, shows the
-- timer and the results. The server has the final say on times.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Ghost = require(script.Parent.Ghost)
local Sounds = require(script.Parent.Sounds)
local UI = require(script.Parent.UI)
local VFX = require(script.Parent.VFX)

local T = Config.Trials

type Course = {
	Id: string,
	Name: string,
	Color: Color3,
	Folder: Folder,
	Rings: { { Position: Vector3, Look: Vector3 } },
}

local Trials = {}

local courses: { Course } = {}
local running: Course? = nil
local nextIndex = 1
local startedAt = 0
local lastStartRequest = 0

local function loadCourses(root: Instance)
	for _, folder in root:GetChildren() do
		if folder:IsA("Folder") then
			local count = folder:GetAttribute("RingCount") or 0
			local rings = {}
			for i = 1, count do
				rings[i] = { Position = folder:GetAttribute("Ring" .. i), Look = folder:GetAttribute("Look" .. i) }
			end
			table.insert(courses, {
				Id = folder.Name,
				Name = folder:GetAttribute("DisplayName") or folder.Name,
				Color = folder:GetAttribute("Color") or UI.Colors.Accent,
				Folder = folder,
				Rings = rings,
			})
		end
	end
end

local function setRingLook(course: Course, index: number, transparency: number)
	local model = course.Folder:FindFirstChild("Ring" .. index)
	if not model then
		return
	end
	for _, segment in model:GetChildren() do
		if segment:IsA("BasePart") then
			segment.Transparency = transparency
		end
	end
end

-- Idle: all rings visible. Running: next ring bright, the rest faded.
local function refreshRings()
	for _, course in courses do
		for i = 1, #course.Rings do
			local transparency = 0.25
			if running then
				if course ~= running then
					transparency = 0.9
				elseif i < nextIndex then
					transparency = 0.95
				elseif i == nextIndex then
					transparency = 0
				else
					transparency = 0.6
				end
			end
			setRingLook(course, i, transparency)
		end
	end
end

function Trials.Start(Movement)
	local root = workspace:WaitForChild("Trials", 15)
	if not root then
		return
	end
	loadCourses(root)
	local checkpointRemote = Net.Event("TrialCheckpoint")

	-- Timer UI ------------------------------------------------------------------
	local gui = UI.gui("Trials", 4)
	local timerFrame = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(300, 96),
		BackgroundColor3 = UI.Colors.Panel,
		BackgroundTransparency = 0.25,
		Visible = false,
	}, gui)
	UI.corner(timerFrame, 14)
	local courseLabel = UI.label(timerFrame, {
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = 14,
		Text = "",
	})
	local timeLabel = UI.label(timerFrame, {
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 34),
		Font = UI.Fonts.Title,
		TextSize = 32,
		Text = "0:00.00",
	})
	local ringsLabel = UI.label(timerFrame, {
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(1, 0, 0, 16),
		TextSize = 12,
		TextColor3 = UI.Colors.Muted,
		Text = "",
	})
	-- Ahead/behind your ghost at the last ring.
	local deltaLabel = UI.label(timerFrame, {
		Position = UDim2.fromOffset(0, 72),
		Size = UDim2.new(1, 0, 0, 20),
		Font = UI.Fonts.Title,
		TextSize = 18,
		Text = "",
	})

	-- Marker floating on the next ring.
	local markerPart = Instance.new("Part")
	markerPart.Anchored = true
	markerPart.CanCollide = false
	markerPart.CanQuery = false
	markerPart.CanTouch = false
	markerPart.Transparency = 1
	markerPart.Size = Vector3.one
	local marker = UI.new("BillboardGui", {
		Size = UDim2.fromOffset(120, 44),
		AlwaysOnTop = true,
		Enabled = false,
	}, markerPart)
	local markerLabel = UI.label(marker, {
		Size = UDim2.fromScale(1, 1),
		Font = UI.Fonts.Title,
		TextSize = 20,
		TextStrokeTransparency = 0.3,
		Text = "",
	})

	-- Results card --------------------------------------------------------------
	local results = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(380, 210),
		BackgroundColor3 = UI.Colors.Panel,
		BackgroundTransparency = 0.1,
		Visible = false,
	}, gui)
	UI.corner(results, 18)
	local resultTitle = UI.label(results, {
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 40),
		Font = UI.Fonts.Title,
		TextSize = 36,
		Text = "FINISH!",
	})
	local resultTime = UI.label(results, {
		Position = UDim2.fromOffset(0, 60),
		Size = UDim2.new(1, 0, 0, 56),
		Font = UI.Fonts.Title,
		TextSize = 54,
		Text = "",
	})
	local resultInfo = UI.label(results, {
		Position = UDim2.fromOffset(0, 124),
		Size = UDim2.new(1, 0, 0, 70),
		TextSize = 18,
		TextColor3 = UI.Colors.Muted,
		Text = "",
	})

	local function stopRun()
		Ghost.Hide()
		deltaLabel.Text = ""
		running = nil
		nextIndex = 1
		timerFrame.Visible = false
		marker.Enabled = false
		refreshRings()
	end

	Net.Event("TrialEvent").OnClientEvent:Connect(function(kind: string, data)
		if kind == "Started" then
			for _, course in courses do
				if course.Id == data.Course then
					running = course
				end
			end
			if not running then
				return
			end
			nextIndex = 2
			startedAt = os.clock()
			deltaLabel.Text = ""
			Ghost.StartRecording()
			local course = running
			task.spawn(Ghost.Load, course.Id, course.Color)
			timerFrame.Visible = true
			courseLabel.Text = string.upper(running.Name)
			courseLabel.TextColor3 = running.Color
			marker.Enabled = true
			UI.pop(timerFrame, 0.2)
			UI.toast("GO!", running.Color)
			Sounds.Play(Config.Sounds.Ping, 0.6, 1)
			refreshRings()
		elseif kind == "Checkpoint" then
			timeLabel.Text = UI.formatTime(data.Split)
			UI.pop(timeLabel, 0.15)
		elseif kind == "Finished" then
			local course = running
			if data.Record and course then
				Net.Event("SubmitGhost"):FireServer(course.Id, Ghost.Encode())
			end
			stopRun()
			results.Visible = true
			resultTitle.Text = if data.Record then "NEW RECORD!" else "FINISH!"
			resultTitle.TextColor3 = if data.Record
				then UI.Colors.Gold
				else (if course then course.Color else UI.Colors.Text)
			resultTime.Text = UI.formatTime(data.Time)
			resultInfo.Text = string.format(
				"%s\nBest %s   ·   +%d ◆",
				if course then course.Name else "",
				UI.formatTime(data.Best or data.Time),
				data.Reward or 0
			)
			UI.pop(results, 0.3)
			for i = 0, 3 do
				task.delay(i * 0.1, function()
					Sounds.Play(Config.Sounds.Ping, 0.5, 1 + i * 0.26)
				end)
			end
			task.delay(4.5, function()
				results.Visible = false
			end)
		elseif kind == "Cancelled" then
			stopRun()
			if data.Reason ~= "Died" then
				UI.toast("Trial cancelled" .. (if data.Reason == "Timeout" then " (too slow)" else ""), UI.Colors.Bad)
			end
		end
	end)

	ContextActionService:BindAction("SkyboundCancelTrial", function(_, inputState)
		if inputState == Enum.UserInputState.Begin and running then
			checkpointRemote:FireServer(running.Id, 0)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.R)

	RunService.Heartbeat:Connect(function()
		local rootPart = Movement.Info.Root
		if not rootPart or not rootPart.Parent then
			return
		end
		local position = rootPart.Position
		local reach = T.RingRadius + 2

		local course = running
		if course then
			local elapsed = os.clock() - startedAt
			timeLabel.Text = UI.formatTime(elapsed)
			Ghost.Record(rootPart, elapsed)
			Ghost.Update(elapsed)
			ringsLabel.Text = string.format("RING %d / %d   ·   R TO CANCEL", nextIndex - 1, #course.Rings)
			local ring = course.Rings[nextIndex]
			if ring then
				markerPart.Position = ring.Position + Vector3.new(0, T.RingRadius + 4, 0)
				markerPart.Parent = workspace.CurrentCamera
				markerLabel.TextColor3 = course.Color
				markerLabel.Text = string.format(
					"%d / %d\n%dm",
					nextIndex,
					#course.Rings,
					math.floor((ring.Position - position).Magnitude)
				)
				if (ring.Position - position).Magnitude < reach then
					checkpointRemote:FireServer(course.Id, nextIndex)
					Ghost.MarkSplit(nextIndex, elapsed)
					local best = Ghost.GetSplit(nextIndex)
					if best then
						local delta = elapsed - best
						deltaLabel.Text = string.format("%s%.2f", if delta < 0 then "-" else "+", math.abs(delta))
						deltaLabel.TextColor3 = if delta < 0 then UI.Colors.Good else UI.Colors.Bad
						UI.pop(deltaLabel, 0.25)
					end
					VFX.Flash(ring.Position, course.Color, T.RingRadius * 2.4)
					Sounds.Play(Config.Sounds.Ping, 0.45, 1.1 + nextIndex * 0.03)
					nextIndex += 1
					refreshRings()
				end
			end
		elseif os.clock() - lastStartRequest > 1 then
			for _, candidate in courses do
				local gate = candidate.Rings[1]
				if gate and (gate.Position - position).Magnitude < reach then
					lastStartRequest = os.clock()
					checkpointRemote:FireServer(candidate.Id, 1)
					VFX.Flash(gate.Position, candidate.Color, T.RingRadius * 2.4)
				end
			end
		end
	end)
end

function Trials.GetCourses()
	return courses
end

return Trials

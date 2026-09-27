-- Time trials: ring courses laid across the islands.
--
-- Fly through the start gate to begin, hit every ring in order, and the server
-- times you. The client reports rings; the server checks you were actually there
-- and couldn't have got there impossibly fast, so times can't simply be faked.
--
-- Best times are saved per player and ranked on global OrderedDataStore
-- leaderboards (with a per-server fallback when DataStores are unavailable).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MathUtil = require(ReplicatedStorage.Shared.MathUtil)
local Net = require(ReplicatedStorage.Shared.Net)
local PlayerData = require(script.Parent.PlayerData)

local T = Config.Trials
local Flat = MathUtil.Flat
local SEGMENTS = 20
local LEADERBOARD_SIZE = 10
local REFRESH_INTERVAL = 60

type Ring = { Position: Vector3, Look: Vector3 }
type Course = {
	Id: string,
	Name: string,
	Color: Color3,
	Rings: { Ring },
	Start: CFrame,
	Store: OrderedDataStore?,
}
type Entry = { UserId: number, Name: string, Time: number }

local TimeTrials = {}

local courses: { [string]: Course } = {}
local courseOrder: { Course } = {}
local runs: { [Player]: { Course: Course, Next: number, Start: number, Last: number, LastPos: Vector3 } } = {}
local boards: { [string]: { Entry } } = {}
local sessionBests: { [string]: { [number]: Entry } } = {}
local nameCache: { [number]: string } = {}
local boardLabels: { [string]: TextLabel } = {}

local trialEvent: RemoteEvent

-- Course layout -----------------------------------------------------------------

local function planRoute(islands, hops: number, angle: number)
	local heading = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local route = { islands[1] }
	local used = { [1] = true }
	local current = islands[1]
	for _ = 1, hops do
		local bestIndex, bestScore = nil, math.huge
		for i, island in islands do
			if not used[i] then
				local offset = Flat(island.Position - current.Position)
				local dist = offset.Magnitude
				if dist > 90 and dist < 380 then
					-- Prefer close islands in roughly the direction we're heading.
					local score = dist - offset.Unit:Dot(heading) * 160
					if score < bestScore then
						bestIndex, bestScore = i, score
					end
				end
			end
		end
		if not bestIndex then
			break
		end
		used[bestIndex] = true
		local nextIsland = islands[bestIndex]
		heading = (heading + Flat(nextIsland.Position - current.Position).Unit * 0.6).Unit
		current = nextIsland
		table.insert(route, current)
	end
	return route
end

local function buildRing(parent: Instance, index: number, ring: Ring, color: Color3)
	local model = Instance.new("Model")
	model.Name = "Ring" .. index
	local frame = CFrame.lookAt(ring.Position, ring.Position + ring.Look)
	local chord = 2 * math.pi * T.RingRadius / SEGMENTS * 1.08
	for i = 1, SEGMENTS do
		local segment = Instance.new("Part")
		segment.Anchored = true
		segment.CanCollide = false
		segment.CanQuery = false
		segment.CanTouch = false
		segment.CastShadow = false
		segment.Material = Enum.Material.Neon
		segment.Color = color
		segment.Transparency = 0.25
		segment.Size = Vector3.new(chord, 1.2, 1.2)
		segment.CFrame = frame * CFrame.Angles(0, 0, i / SEGMENTS * math.pi * 2) * CFrame.new(0, T.RingRadius, 0)
		segment.Parent = model
	end
	model.Parent = parent
end

local function buildCourse(root: Instance, definition, islands, angle: number)
	local route = planRoute(islands, definition.Hops, angle)
	if #route < 3 then
		return
	end
	local spawnIsland = route[1]
	local firstDir = Flat(route[2].Position - spawnIsland.Position).Unit
	local surface = spawnIsland.Position.Y + 2

	local rings: { Ring } = {
		{
			Position = Flat(spawnIsland.Position)
				+ firstDir * spawnIsland.Radius * 0.75
				+ Vector3.new(0, surface + 9, 0),
			Look = firstDir,
		},
	}
	for i = 1, #route - 1 do
		local a, b = route[i], route[i + 1]
		local dir = Flat(b.Position - a.Position).Unit
		local mid = (a.Position + b.Position) / 2
		table.insert(rings, {
			Position = Vector3.new(mid.X, math.max(a.Position.Y, b.Position.Y) + 28, mid.Z),
			Look = dir,
		})
		table.insert(rings, { Position = b.Position + Vector3.new(0, 14, 0), Look = dir })
	end

	local folder = Instance.new("Folder")
	folder.Name = definition.Id
	folder:SetAttribute("DisplayName", definition.Name)
	folder:SetAttribute("Color", definition.Color)
	folder:SetAttribute("RingCount", #rings)
	for i, ring in rings do
		folder:SetAttribute("Ring" .. i, ring.Position)
		folder:SetAttribute("Look" .. i, ring.Look)
		buildRing(folder, i, ring, definition.Color)
	end

	-- Start pad just behind the gate.
	local padPos = rings[1].Position - firstDir * 22
	padPos = Vector3.new(padPos.X, surface + 0.3, padPos.Z)
	local pad = Instance.new("Part")
	pad.Name = "StartPad"
	pad.Anchored = true
	pad.CanQuery = false
	pad.Size = Vector3.new(10, 0.6, 10)
	pad.Material = Enum.Material.Neon
	pad.Color = definition.Color
	pad.CFrame = CFrame.lookAt(padPos, padPos + firstDir)
	pad.Parent = folder
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(220, 60)
	billboard.StudsOffset = Vector3.new(0, 7, 0)
	billboard.MaxDistance = 160
	billboard.Parent = pad
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = definition.Color
	label.TextStrokeTransparency = 0.4
	label.Text = string.upper(definition.Name) .. "\n<font size='14'>fly through the gate to start</font>"
	label.RichText = true
	label.Parent = billboard

	folder.Parent = root

	local course: Course = {
		Id = definition.Id,
		Name = definition.Name,
		Color = definition.Color,
		Rings = rings,
		Start = CFrame.lookAt(padPos + Vector3.new(0, 4, 0), padPos + Vector3.new(0, 4, 0) + firstDir),
	}
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore("SkyboundTrial_" .. definition.Id)
	end)
	if ok then
		course.Store = store
	end
	courses[course.Id] = course
	table.insert(courseOrder, course)
	boards[course.Id] = {}
	sessionBests[course.Id] = {}
end

-- Leaderboards --------------------------------------------------------------------

local function formatTime(seconds: number): string
	return string.format("%d:%05.2f", math.floor(seconds / 60), seconds % 60)
end

local function getName(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	nameCache[userId] = if ok and name then name else "Player"
	return nameCache[userId]
end

local function rebuildBoard(course: Course, stored: { Entry }?)
	local merged: { [number]: Entry } = {}
	for _, entry in stored or boards[course.Id] do
		merged[entry.UserId] = entry
	end
	for userId, entry in sessionBests[course.Id] do
		local existing = merged[userId]
		if not existing or entry.Time < existing.Time then
			merged[userId] = entry
		end
	end
	local list = {}
	for _, entry in merged do
		table.insert(list, entry)
	end
	table.sort(list, function(a, b)
		return a.Time < b.Time
	end)
	while #list > LEADERBOARD_SIZE do
		table.remove(list)
	end
	boards[course.Id] = list

	local label = boardLabels[course.Id]
	if label then
		local lines = { string.upper(course.Name) }
		for i = 1, 5 do
			local entry = list[i]
			table.insert(
				lines,
				if entry
					then string.format("%d. %s  %s", i, entry.Name, formatTime(entry.Time))
					else string.format("%d. ---", i)
			)
		end
		label.Text = table.concat(lines, "\n")
	end
end

local function refreshBoard(course: Course)
	local store = course.Store
	if not store then
		rebuildBoard(course)
		return
	end
	local ok, pages = pcall(function()
		return store:GetSortedAsync(true, LEADERBOARD_SIZE)
	end)
	if not ok then
		rebuildBoard(course)
		return
	end
	local stored = {}
	for _, row in pages:GetCurrentPage() do
		local userId = tonumber(row.key)
		if userId then
			table.insert(stored, { UserId = userId, Name = getName(userId), Time = row.value / 1000 })
		end
	end
	rebuildBoard(course, stored)
end

local function buildWorldBoard(parent: Instance)
	local board = Instance.new("Part")
	board.Name = "Leaderboard"
	board.Anchored = true
	board.Size = Vector3.new(36, 16, 1.5)
	board.Material = Enum.Material.Limestone
	board.Color = Color3.fromRGB(226, 214, 190)
	board.CFrame = CFrame.lookAt(Vector3.new(0, 112, 42), Vector3.new(0, 112, 0))
	board.Parent = parent

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.PixelsPerStud = 30
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.LightInfluence = 0
	gui.Parent = board
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 20)
	layout.Parent = gui
	for _, course in courseOrder do
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1 / #courseOrder, -20, 1, -20)
		label.BackgroundColor3 = Color3.fromRGB(20, 24, 40)
		label.BackgroundTransparency = 0.15
		label.Font = Enum.Font.GothamBold
		label.TextSize = 34
		label.TextColor3 = course.Color
		label.TextYAlignment = Enum.TextYAlignment.Top
		label.Text = string.upper(course.Name)
		label.Parent = gui
		boardLabels[course.Id] = label
	end
end

-- Runs --------------------------------------------------------------------------

local function cancel(player: Player, reason: string)
	if runs[player] then
		runs[player] = nil
		trialEvent:FireClient(player, "Cancelled", { Reason = reason })
	end
end

local function finish(player: Player, course: Course, time: number)
	runs[player] = nil
	time = math.floor(time * 1000 + 0.5) / 1000
	local data = PlayerData.Get(player)
	local previous = data and data.Best[course.Id]
	local record = previous == nil or time < previous
	if record then
		PlayerData.Update(player, function(d)
			d.Best[course.Id] = time
		end)
		sessionBests[course.Id][player.UserId] = { UserId = player.UserId, Name = player.Name, Time = time }
		rebuildBoard(course)
		task.spawn(function()
			PlayerData.Save(player)
			if course.Store and player.UserId > 0 then
				pcall(function()
					(course.Store :: OrderedDataStore):SetAsync(tostring(player.UserId), math.floor(time * 1000))
				end)
			end
		end)
	end
	-- Shards for finishing, more for the longer courses.
	local reward = #course.Rings
	PlayerData.AddShards(player, reward)
	trialEvent:FireClient(player, "Finished", {
		Course = course.Id,
		Time = time,
		Best = if record then time else previous,
		Record = record,
		Reward = reward,
	})
end

local function onCheckpoint(player: Player, courseId: any, index: any)
	if index == 0 then
		cancel(player, "Cancelled")
		return
	end
	local course = type(courseId) == "string" and courses[courseId]
	if not course or type(index) ~= "number" then
		return
	end
	local ring = course.Rings[index]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not ring or not root then
		return
	end
	-- Generous: the server sees fast players a little behind where they really are.
	if (root.Position - ring.Position).Magnitude > T.RingRadius + 45 then
		return
	end

	local now = os.clock()
	if index == 1 then
		runs[player] = { Course = course, Next = 2, Start = now, Last = now, LastPos = ring.Position }
		trialEvent:FireClient(player, "Started", { Course = course.Id })
		return
	end

	local run = runs[player]
	if not run or run.Course ~= course or index ~= run.Next then
		return
	end
	local fastest = (ring.Position - run.LastPos).Magnitude / (Config.Movement.MaxSpeed * 1.6)
	if now - run.Last < fastest then
		cancel(player, "Invalid")
		return
	end
	run.Next += 1
	run.Last = now
	run.LastPos = ring.Position
	if index == #course.Rings then
		finish(player, course, now - run.Start)
	else
		trialEvent:FireClient(player, "Checkpoint", { Course = course.Id, Index = index, Split = now - run.Start })
	end
end

function TimeTrials.Start(islands)
	trialEvent = Net.Event("TrialEvent")
	if not islands then
		return
	end

	local root = Instance.new("Folder")
	root.Name = "Trials"
	for i, definition in T.Courses do
		buildCourse(root, definition, islands, (i - 1) / #T.Courses * math.pi * 2 + math.pi / 6)
	end
	root.Parent = workspace
	buildWorldBoard(root)

	Net.Event("TrialCheckpoint").OnServerEvent:Connect(onCheckpoint)
	Net.Function("GetLeaderboards").OnServerInvoke = function()
		local result = {}
		for _, course in courseOrder do
			result[course.Id] = { Name = course.Name, Color = course.Color, Entries = boards[course.Id] }
		end
		return result
	end
	Net.Function("GoToTrial").OnServerInvoke = function(player, courseId)
		local course = type(courseId) == "string" and courses[courseId]
		local character = player.Character
		if not course or not character then
			return false
		end
		cancel(player, "Cancelled")
		character:PivotTo(course.Start)
		return true
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterRemoving:Connect(function()
			cancel(player, "Died")
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterRemoving:Connect(function()
			cancel(player, "Died")
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		runs[player] = nil
	end)

	task.spawn(function()
		while true do
			for _, course in courseOrder do
				refreshBoard(course)
			end
			task.wait(REFRESH_INTERVAL)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for player, run in runs do
				if now - run.Start > T.Timeout then
					cancel(player, "Timeout")
				end
			end
		end
	end)
end

return TimeTrials

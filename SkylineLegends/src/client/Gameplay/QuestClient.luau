-- Quests on the client: talking to people, beacons on the places your active
-- objectives need, the waypoint for your pinned objective, "!" and "?"
-- markers over characters with work or news for you, and reaching points.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Districts = require(ReplicatedStorage.Shared.Config.Districts)
local Net = require(ReplicatedStorage.Shared.Net)
local NPCs = require(ReplicatedStorage.Shared.Config.NPCs)
local Quests = require(ReplicatedStorage.Shared.Config.Quests)
local Tags = require(ReplicatedStorage.Shared.Tags)

local Bus = require(script.Parent.Parent.Core.Bus)
local Settings = require(script.Parent.Parent.Core.Settings)
local State = require(script.Parent.Parent.Core.State)
local Controller = require(script.Parent.Parent.Movement.Controller)

local QuestClient = {}

local PREFIX = { Hub = "hub", Tinroof = "tin", Ironworks = "iron", Verdant = "ver", Gilded = "gil", Frostreach = "fro", Citadel = "cit" }

local pointParts: { [string]: BasePart } = {}
local npcModels: { [string]: Model } = {}
local carrying = false
local beacons: { [string]: { Part: Part, Gui: BillboardGui } } = {}
local markers: { [string]: BillboardGui } = {}
local sentAt: { [string]: number } = {}
local beaconFolder = Instance.new("Folder")
beaconFolder.Name = "SkylineBeacons"

export type Target = { Position: Vector3, Label: string, Quest: string? }

-- World lookups ----------------------------------------------------------------------------------------

local function indexPoints()
	for _, tag in { Tags.QuestPoint, Tags.ContractPoint } do
		for _, part in CollectionService:GetTagged(tag) do
			if part:IsA("BasePart") then
				local id = part:GetAttribute("Id")
				if type(id) == "string" then
					pointParts[id] = part
				end
			end
		end
	end
end

local function npcPosition(npcId: string): Vector3?
	local model = npcModels[npcId]
	if model and model.Parent then
		return model:GetPivot().Position
	end
	local folder = workspace:FindFirstChild("SkylineNPCs")
	local found = folder and folder:FindFirstChild(npcId)
	if found and found:IsA("Model") then
		npcModels[npcId] = found
		return found:GetPivot().Position
	end
	return nil
end

local function pointPosition(id: string): Vector3?
	local part = pointParts[id]
	return if part then part.Position else nil
end

local function districtPosition(id: string?): Vector3?
	if not id then
		return nil
	end
	local plaza = PREFIX[id] and pointPosition(PREFIX[id] .. "_plaza")
	if plaza then
		return plaza
	end
	local district = Districts.ById[id]
	return if district then district.Origin else nil
end

local function nearestTagged(tag: string, filter: ((BasePart) -> boolean)?): Vector3?
	local root = Controller.Info.Root
	local best, bestDistance = nil, math.huge
	for _, part in CollectionService:GetTagged(tag) do
		if part:IsA("BasePart") and (not filter or filter(part)) then
			local distance = if root then (part.Position - root.Position).Magnitude else 0
			if distance < bestDistance then
				best, bestDistance = part.Position, distance
			end
		end
	end
	return best
end

local function nearestOf(ids: { string }, skip: { [string]: any }?): Vector3?
	local root = Controller.Info.Root
	local best, bestDistance = nil, math.huge
	for _, id in ids do
		if not (skip and skip[id]) then
			local position = pointPosition(id)
			if position then
				local distance = if root then (position - root.Position).Magnitude else 0
				if distance < bestDistance then
					best, bestDistance = position, distance
				end
			end
		end
	end
	return best
end

-- Quest state ----------------------------------------------------------------------------------------

local function profileQuests(): any
	local profile = State.Profile
	return if profile then profile.Quests else nil
end

function QuestClient.IsAvailable(quest: Quests.Quest): boolean
	local data = profileQuests()
	if not data or data.Completed[quest.Id] or data.Active[quest.Id] then
		return false
	end
	local requires = quest.Requires or {}
	if requires.Level and State.Level() < requires.Level then
		return false
	end
	for _, id in requires.Quests or {} do
		if not data.Completed[id] then
			return false
		end
	end
	return true
end

function QuestClient.Step(questId: string): (Quests.Step?, any)
	local data = profileQuests()
	local quest = Quests.ById[questId]
	local state = data and data.Active[questId]
	if not quest or not state then
		return nil, nil
	end
	return quest.Steps[state.Step], state
end

-- Points the current step of an active quest still needs.
local function wantedPoints(questId: string): { string }
	local step, state = QuestClient.Step(questId)
	if not step or not state then
		return {}
	end
	local kind = step.Kind
	local progress = state.Progress or {}
	if kind == "Reach" then
		return { step.Point }
	elseif kind == "Collect" or kind == "Activate" then
		local list = {}
		for _, id in step.Points do
			if not progress[id] then
				table.insert(list, id)
			end
		end
		return list
	elseif kind == "Deliver" then
		if not carrying then
			return { step.From }
		end
		local list = {}
		for _, id in step.To do
			if not progress[id] then
				table.insert(list, id)
			end
		end
		return list
	elseif kind == "Timed" then
		return if progress.Started then { step.To } else { step.From }
	end
	return {}
end

local function contractPoints(): { string }
	local profile = State.Profile
	local contract = profile and profile.Contracts and profile.Contracts.Active
	if not contract then
		return {}
	end
	if contract.Kind == "Delivery" then
		return if contract.Picked then { contract.To } else { contract.From }
	elseif contract.Kind == "Relays" then
		local list = {}
		for _, id in contract.Points or {} do
			if not (contract.Done and contract.Done[id]) then
				table.insert(list, id)
			end
		end
		return list
	end
	return {}
end

-- Where the pinned objective wants you to go.
function QuestClient.TargetFor(questId: string): Target?
	local step, state = QuestClient.Step(questId)
	if not step or not state then
		return nil
	end
	local kind = step.Kind
	local position: Vector3? = nil
	if kind == "Talk" then
		position = npcPosition(step.Npc)
	elseif kind == "Reach" or kind == "Collect" or kind == "Activate" or kind == "Deliver" or kind == "Timed" then
		position = nearestOf(wantedPoints(questId))
	elseif kind == "Course" then
		local config = ReplicatedStorage:FindFirstChild("SkylineCourses")
		local course = config and config:FindFirstChild(step.Course)
		local spawn = course and course:GetAttribute("Spawn")
		position = if typeof(spawn) == "CFrame" then spawn.Position else nil
	elseif kind == "Courses" or kind == "Technique" or kind == "Chain" or kind == "Flow" or kind == "Discover" then
		position = districtPosition(step.District)
	elseif kind == "Lessons" then
		local lessons = State.Profile and State.Profile.Lessons or {}
		position = nearestTagged(Tags.LessonZone, function(part)
			return not lessons[part:GetAttribute("LessonId")]
		end)
	elseif kind == "Race" or kind == "Relay" then
		position = nearestTagged(Tags.Board, function(part)
			return part:GetAttribute("Kind") == "Race"
		end)
	elseif kind == "Crew" then
		position = nearestTagged(Tags.Board, function(part)
			return part:GetAttribute("Kind") == "Crew"
		end)
	elseif kind == "Tower" then
		local hub = Districts.ById.Hub
		position = hub.Origin + Districts.SpireOffset
	end
	if not position then
		return nil
	end
	return { Position = position, Label = step.Text, Quest = questId }
end

function QuestClient.PinnedTarget(): Target?
	local data = profileQuests()
	if data then
		for _, questId in data.Pinned or {} do
			local target = QuestClient.TargetFor(questId)
			if target then
				return target
			end
		end
	end
	local points = contractPoints()
	local position = nearestOf(points)
	if position then
		return { Position = position, Label = "Contract", Quest = nil }
	end
	return nil
end

-- Actions -----------------------------------------------------------------------------------------------

function QuestClient.Talk(npcId: string)
	task.spawn(function()
		local ok, response = pcall(Net.Invoke, "Quest.Talk", npcId)
		if ok and type(response) == "table" then
			Bus.Dialogue:Fire(npcId, response)
		end
	end)
end

function QuestClient.Accept(questId: string): (boolean, string?)
	local ok, success, reason = pcall(Net.Invoke, "Quest.Accept", questId)
	if not ok then
		return false, "Couldn't reach the Guild"
	end
	return success == true, reason
end

function QuestClient.Pin(questId: string, pinned: boolean)
	Net.Send("Quest.Pin", questId, pinned)
end

function QuestClient.Abandon(questId: string)
	Net.Send("Quest.Abandon", questId)
end

-- Beacons and markers -------------------------------------------------------------------------------------

local function beaconFor(id: string, position: Vector3, color: Color3)
	local existing = beacons[id]
	if existing then
		existing.Part.Position = position
		return
	end
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = 0.55
	part.Size = Vector3.new(1.2, 60, 1.2)
	part.Position = position + Vector3.new(0, 30, 0)
	part.Parent = beaconFolder
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(46, 46)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.StudsOffset = Vector3.new(0, -27, 0)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.Text = "◆"
	label.Parent = gui
	gui.Parent = part
	beacons[id] = { Part = part, Gui = gui }
end

local function updateBeacons()
	local wanted: { [string]: Color3 } = {}
	local data = profileQuests()
	if data then
		for questId in data.Active do
			local quest = Quests.ById[questId]
			local color = if quest and quest.Type == "Main" then Color3.fromRGB(255, 200, 80) else Color3.fromRGB(120, 220, 255)
			for _, id in wantedPoints(questId) do
				wanted[id] = color
			end
		end
	end
	for _, id in contractPoints() do
		wanted[id] = Color3.fromRGB(150, 255, 170)
	end
	for id, color in wanted do
		local position = pointPosition(id)
		if position then
			beaconFor(id, position, color)
		end
	end
	for id, beacon in beacons do
		if not wanted[id] then
			beacon.Part:Destroy()
			beacons[id] = nil
		end
	end
end

local function updateMarkers()
	local data = profileQuests()
	if not data then
		return
	end
	local status: { [string]: string } = {}
	for _, quest in Quests.List do
		if quest.Type ~= "Expert" and QuestClient.IsAvailable(quest) then
			status[quest.Giver] = if quest.Type == "Main" then "!" else (status[quest.Giver] or "+")
		end
	end
	for questId in data.Active do
		local step = QuestClient.Step(questId)
		if step and step.Kind == "Talk" then
			status[step.Npc] = "?"
		end
	end
	for _, npc in NPCs.List do
		local model = npcModels[npc.Id]
		if not model then
			npcPosition(npc.Id)
			model = npcModels[npc.Id]
		end
		local head = model and model:FindFirstChild("Head")
		local mark = status[npc.Id]
		local gui = markers[npc.Id]
		if head and mark then
			if not gui then
				gui = Instance.new("BillboardGui")
				gui.Name = "QuestMarker"
				gui.Size = UDim2.fromOffset(40, 40)
				gui.StudsOffset = Vector3.new(0, 4.6, 0)
				gui.AlwaysOnTop = true
				gui.LightInfluence = 0
				gui.MaxDistance = 220
				local label = Instance.new("TextLabel")
				label.Name = "Mark"
				label.Size = UDim2.fromScale(1, 1)
				label.BackgroundTransparency = 1
				label.Font = Enum.Font.GothamBlack
				label.TextScaled = true
				label.TextStrokeTransparency = 0
				label.Parent = gui
				gui.Parent = head
				markers[npc.Id] = gui
			end
			local label = gui:FindFirstChild("Mark") :: TextLabel?
			if label then
				label.Text = mark
				label.TextColor3 = if mark == "!" then Color3.fromRGB(255, 205, 70) elseif mark == "?" then Color3.fromRGB(120, 230, 255) else Color3.fromRGB(200, 255, 200)
			end
		elseif gui then
			gui:Destroy()
			markers[npc.Id] = nil
		end
	end
end

local function checkPoints()
	local root = Controller.Info.Root
	if not root then
		return
	end
	local now = os.clock()
	for id, beacon in beacons do
		local position = beacon.Part.Position - Vector3.new(0, 30, 0)
		if (position - root.Position).Magnitude < 8 and now - (sentAt[id] or 0) > 2 then
			sentAt[id] = now
			Net.Send("Quest.Point", id)
		end
	end
end

function QuestClient.Start()
	beaconFolder.Parent = workspace
	indexPoints()
	CollectionService:GetInstanceAddedSignal(Tags.QuestPoint):Connect(function()
		task.defer(indexPoints)
	end)
	Net.Listen("Quest.Carry", function(questId, fragile)
		carrying = questId ~= nil
		Bus.Carry:Fire(carrying, fragile == true)
		updateBeacons()
	end)
	Net.Listen("Quest.Timer", function(seconds)
		Bus.Timer:Fire(if type(seconds) == "number" then seconds else nil)
	end)
	State.On("Quests", function()
		updateBeacons()
		updateMarkers()
		Bus.Objective:Fire()
	end)
	State.On("Contracts", function()
		updateBeacons()
		Bus.Objective:Fire()
	end)
	State.On("XP", updateMarkers)
	local last = 0
	RunService.Heartbeat:Connect(function()
		checkPoints()
		if os.clock() - last > 3 then
			last = os.clock()
			updateMarkers()
			updateBeacons()
		end
		local high = Settings.Get("HighContrast")
		for _, beacon in beacons do
			beacon.Part.Transparency = if high then 0.25 else 0.55
		end
	end)
end

return QuestClient

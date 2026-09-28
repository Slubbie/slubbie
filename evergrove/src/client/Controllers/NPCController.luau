-- Villagers on the client: nameplates (name, role, hearts, quest and birthday
-- markers), per-player visibility (villagers you haven't met yet stay hidden),
-- and conversations (NpcTalk → the Dialogue window, with a gentle camera
-- close-up). Server-initiated lines (gift reactions, events) arrive on the
-- "Dialogue" channel.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local Stats = require(Shared.Lib.Stats)
local GameTime = require(Shared.Lib.GameTime)

local C = require(script.Parent)

local NPCController = {}

local player = Players.LocalPlayer
local plates: { [Model]: BillboardGui } = {}
local talking: string? = nil
local releaseCamera: (() -> ())? = nil

local function npcModel(npcId: string): Model?
	local folder = workspace:FindFirstChild("NPCs")
	if not folder then
		return nil
	end
	for _, m in folder:GetChildren() do
		if m:GetAttribute("NpcId") == npcId then
			return m :: Model
		end
	end
	return nil
end
NPCController.Model = npcModel

local function heartsText(npcId: string): string
	local profile = C.State.Data()
	if not profile then
		return ""
	end
	local hearts = Stats.Hearts(profile, npcId)
	local full = math.floor(hearts)
	return string.rep("❤", math.min(full, 10)) .. string.rep("♡", math.max(0, math.min(10, 10 - full)))
end

local function questMarker(npcId: string): string
	local quests = C.State.Get("Quests", "Active") or {}
	for questId, state in quests do
		local quest = Registry.Quests[questId]
		if quest and state.Ready and (quest.TurnIn or quest.Giver) == npcId then
			return "✔️"
		end
	end
	return ""
end

local function isBirthday(npcId: string): boolean
	local npc = Registry.Npcs[npcId]
	local info = GameTime.Info()
	return npc ~= nil and npc.Birthday[1] == info.Season and npc.Birthday[2] == info.DayOfSeason
end

local function updatePlate(model: Model)
	local gui = plates[model]
	local npcId = model:GetAttribute("NpcId")
	local npc = npcId and Registry.Npcs[npcId]
	if not gui or not npc then
		return
	end
	local profile = C.State.Data()
	local unlocked = profile == nil or Stats.NpcUnlocked(profile, npc)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = if unlocked then 0 else 1
		elseif d:IsA("ProximityPrompt") then
			d.Enabled = unlocked
		elseif d:IsA("Decal") then
			d.Transparency = if unlocked then 0 else 1
		end
	end
	gui.Enabled = unlocked
	local name = gui:FindFirstChild("Name") :: TextLabel
	local sub = gui:FindFirstChild("Sub") :: TextLabel
	local marker = gui:FindFirstChild("Marker") :: TextLabel
	name.Text = npc.Name
	sub.Text = npc.Role .. "  " .. heartsText(npc.Id)
	marker.Text = questMarker(npc.Id) .. (if isBirthday(npc.Id) then "🎂" else "")
end

local function addPlate(model: Instance)
	if not model:IsA("Model") or plates[model] or not model:GetAttribute("NpcId") then
		return
	end
	local head = model:WaitForChild("Head", 10) :: BasePart?
	if not head then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Nameplate"
	gui.Size = UDim2.fromOffset(200, 64)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	gui.Adornee = head
	local marker = Instance.new("TextLabel")
	marker.Name = "Marker"
	marker.BackgroundTransparency = 1
	marker.Size = UDim2.new(1, 0, 0, 24)
	marker.TextScaled = true
	marker.Font = Enum.Font.GothamBold
	marker.Text = ""
	marker.Parent = gui
	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromOffset(0, 22)
	name.Size = UDim2.new(1, 0, 0, 22)
	name.TextScaled = true
	name.Font = Enum.Font.FredokaOne
	name.TextColor3 = Color3.fromRGB(255, 250, 235)
	name.TextStrokeTransparency = 0.35
	name.Parent = gui
	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromOffset(0, 44)
	sub.Size = UDim2.new(1, 0, 0, 16)
	sub.TextScaled = true
	sub.Font = Enum.Font.GothamMedium
	sub.TextColor3 = Color3.fromRGB(255, 200, 210)
	sub.TextStrokeTransparency = 0.5
	sub.Parent = gui
	gui.Parent = model
	plates[model :: Model] = gui
	updatePlate(model :: Model)
	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			plates[model :: Model] = nil
		end
	end)
end

local function refreshAll()
	for model in plates do
		updatePlate(model)
	end
end

-- Conversations -------------------------------------------------------------------------------------------------

function NPCController.Talk(npcId: string)
	if talking then
		return
	end
	talking = npcId
	local ok, payload = Net.Request("NpcTalk", npcId)
	if not ok then
		talking = nil
		C.Notify.Toast(tostring(payload), "Warning")
		return
	end
	-- Close-up: camera over the player's shoulder toward the villager.
	local model = npcModel(npcId)
	local head = model and model:FindFirstChild("Head") :: BasePart?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if head and root and not C.Settings.Get("ReducedMotion") then
		local mid = (head.Position + root.Position) / 2
		local side = (head.Position - root.Position):Cross(Vector3.yAxis)
		side = if side.Magnitude > 0.01 then side.Unit else Vector3.xAxis
		local eye = mid + side * 9 + Vector3.new(0, 3, 0)
		releaseCamera = C.Camera.Focus(CFrame.lookAt(eye, head.Position - Vector3.new(0, 0.5, 0)), 0.7)
	end
	C.Windows.Open("Dialogue", payload)
	C.Audio.PlayUI("UIOpen")
end

function NPCController.EndTalk()
	talking = nil
	if releaseCamera then
		releaseCamera()
		releaseCamera = nil
	end
end

function NPCController.Talking(): string?
	return talking
end

function NPCController.Start()
	local folder = workspace:WaitForChild("NPCs")
	for _, m in folder:GetChildren() do
		task.spawn(addPlate, m)
	end
	folder.ChildAdded:Connect(function(m)
		task.spawn(addPlate, m)
	end)
	for _, key in { "Friendship", "Quests", "Projects", "Unlocks", "Skills" } do
		C.State.Watch(key, refreshAll)
	end
	C.Windows.Closed:Connect(function(id)
		if id == "Dialogue" then
			NPCController.EndTalk()
		end
	end)
	Net.On("Dialogue", function(npcId: string, payload: any)
		if type(payload) ~= "table" then
			return
		end
		if payload.Visibility then
			refreshAll()
			return
		end
		if C.Windows.IsOpen("Dialogue") then
			local screen = require(script.Parent.Parent.UI.Screens.Dialogue)
			if screen.Push then
				screen.Push(npcId, payload)
			end
		else
			local npc = Registry.Npcs[npcId]
			if npc and payload.Lines and payload.Lines[1] then
				C.Notify.Toast(npc.Icon .. " " .. npc.Name .. ": " .. payload.Lines[1], "Info")
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(30)
			refreshAll()
		end
	end)
end

return NPCController

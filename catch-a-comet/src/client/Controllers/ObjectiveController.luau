-- The objective tracker, waypoints and the Quests panel.
--
-- The tracker always shows the one thing to do next: the current tutorial
-- step, then the current Explorer mission (with progress and a Claim button).
-- Steps with a destination get a world marker plus an edge-of-screen arrow
-- when the target is off screen. All progress comes from the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreatureDefinitions = require(Shared.CreatureDefinitions)
local Format = require(Shared.Format)
local QuestDefinitions = require(Shared.QuestDefinitions)
local RemoteDefinitions = require(Shared.RemoteDefinitions)
local UITheme = require(Shared.UITheme)
local WorldLayout = require(Shared.WorldLayout)

local ObjectiveController = {}

local controllers: { [string]: any } = {}
local Components: any
local gui: ScreenGui
local tracker: Frame
local trackerHeader: TextLabel
local trackerTitle: TextLabel
local trackerText: TextLabel
local trackerProgress: Frame
local setProgress: (number, boolean?) -> ()
local progressLabel: TextLabel
local claimButton: any
local arrow: TextLabel
local markerPart: Part
local markerGui: BillboardGui
local markerLabel: TextLabel
local currentWaypoint: string? = nil
local panel: any
local panelList: ScrollingFrame

local function firstCreatureName(): string
	local oldest, name = math.huge, "your creature"
	for _, creature in controllers.ClientState.Creatures() do
		if creature.Obtained < oldest then
			oldest = creature.Obtained
			local species = CreatureDefinitions.Get(creature.Species)
			name = if species then species.DisplayName else name
		end
	end
	return name
end

local function fill(text: string, quest: QuestDefinitions.Quest): string
	local result = text:gsub("{target}", tostring(quest.Objective.Target))
	result = result:gsub("{creature}", firstCreatureName())
	result = result:gsub("{action}", controllers.InputController.InteractText())
	return result
end

local function rewardText(reward: QuestDefinitions.Reward): string
	local parts = {}
	if reward.Stardust and reward.Stardust > 0 then
		table.insert(parts, `{Format.Number(reward.Stardust)} ✦`)
	end
	if reward.XP and reward.XP > 0 then
		table.insert(parts, `{reward.XP} XP`)
	end
	if reward.MeteorShards and reward.MeteorShards > 0 then
		table.insert(parts, `{reward.MeteorShards} ◆`)
	end
	return table.concat(parts, " · ")
end

-- The active quest, which chain it belongs to, and its progress.
function ObjectiveController.Current(): (QuestDefinitions.Quest?, string, number, boolean)
	local profile = controllers.ClientState.Profile
	local stage = profile.TutorialStage or 0
	local progress = profile.QuestProgress or {}
	if stage < #QuestDefinitions.Onboarding then
		local step = QuestDefinitions.Onboarding[stage + 1]
		return step, "Onboarding", (progress.Onboarding and progress.Onboarding.Progress) or 0, false
	end
	local missions = progress.Missions or { Index = 1, Progress = 0, Complete = false }
	local mission = QuestDefinitions.Missions[missions.Index]
	return mission, "Missions", missions.Progress or 0, missions.Complete == true
end

local function plotIndex(): number?
	return controllers.ClientState.GetSession("PlotIndex")
end

local function waypointPosition(kind: string?): Vector3?
	if not kind then
		return nil
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local here = if root and root:IsA("BasePart") then root.Position else nil
	if kind == "TutorialComet" then
		local view = controllers.CometController.TutorialComet()
		return if view and not view.Claimed then view.Data.Position + Vector3.new(0, 3, 0) else nil
	elseif kind == "Sanctuary" then
		local index = plotIndex()
		return if index then WorldLayout.Plots[index].Center + Vector3.new(0, 4, 0) else nil
	elseif kind == "HabitatSlot1" then
		local index = plotIndex()
		return if index then WorldLayout.SlotPosition(index, 1) + Vector3.new(0, 2, 0) else nil
	elseif kind == "Workshop" then
		return WorldLayout.Hub.Workshop + Vector3.new(0, 4, 0)
	elseif kind == "DawnCommons" then
		if here and WorldLayout.GetArea(here).Id == "DawnCommons" then
			local view = controllers.CometController.Nearest(here, true)
			return if view then view.Data.Position + Vector3.new(0, 3, 0) else nil
		end
		return WorldLayout.Hub.DawnGate + Vector3.new(0, 6, 0)
	end
	return nil
end

local function renderTracker()
	local quest, chain, progress, complete = ObjectiveController.Current()
	if not quest then
		trackerHeader.Text = "EXPLORER MISSIONS"
		trackerTitle.Text = "All missions complete!"
		trackerText.Text = "New missions arrive with Prism Cliffs. Keep collecting!"
		trackerProgress.Visible = false
		progressLabel.Text = ""
		claimButton.Instance.Visible = false
		currentWaypoint = nil
		return
	end
	local stage = controllers.ClientState.Get("TutorialStage") or 0
	local missionIndex = ((controllers.ClientState.Profile.QuestProgress or {}).Missions or {}).Index or 1
	trackerHeader.Text = if chain == "Onboarding"
		then `GETTING STARTED · {stage + 1}/{#QuestDefinitions.Onboarding}`
		else `MISSION {missionIndex}/{#QuestDefinitions.Missions}`
	trackerTitle.Text = fill(quest.Title, quest)
	trackerText.Text = fill(quest.Text, quest)
	local target = quest.Objective.Target
	local def = QuestDefinitions.ObjectiveTypes[quest.Objective.Type]
	local showBar = target > 1 and def and def.Kind == "Event" or (chain == "Missions" and target > 1)
	trackerProgress.Visible = showBar
	setProgress(math.clamp(progress / target, 0, 1), true)
	progressLabel.Text = if showBar then `{Format.Short(math.min(progress, target))} / {Format.Short(target)}` else ""
	local reward = rewardText(quest.Reward)
	if chain == "Missions" and complete then
		claimButton.Instance.Visible = true
		claimButton:SetText(`Claim · {reward}`)
		controllers.HUDController.SetBadge("Quests", 1)
	else
		claimButton.Instance.Visible = false
		controllers.HUDController.SetBadge("Quests", nil)
		if reward ~= "" then
			trackerText.Text ..= `\nReward: {reward}`
		end
	end
	currentWaypoint = if complete then nil else quest.Waypoint
	Components.Pop(tracker, 0.04)
end

local function claimCurrent()
	local quest, chain = ObjectiveController.Current()
	if not quest or chain ~= "Missions" then
		return
	end
	claimButton:SetLoading(true)
	local ok, result = pcall(function()
		return RemoteDefinitions.GetFunction("ClaimQuest"):InvokeServer(quest.Id)
	end)
	claimButton:SetLoading(false)
	if ok and type(result) == "table" and result.Ok then
		controllers.AudioController.Fanfare(2)
		controllers.NotificationController.Banner("Mission complete!", rewardText(quest.Reward), UITheme.Colors.Gold, 2)
	else
		controllers.NotificationController.Toast("Couldn't claim that reward yet.", "📜")
	end
end

local function renderPanel()
	for _, child in panelList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local order = 0
	local function add(instance: GuiObject)
		order += 1
		instance.LayoutOrder = order
		instance.Parent = panelList
	end
	local function heading(text: string)
		add(Components.Label({
			Text = text,
			Font = UITheme.Fonts.Display,
			TextSize = 22,
			TextColor3 = UITheme.Colors.Lavender,
			Size = UDim2.new(1, 0, 0, 30),
		}))
	end
	local function row(title: string, subtitle: string, state: string)
		local frame = Components.Make("Frame", {
			BackgroundColor3 = if state == "current" then UITheme.Colors.PanelRaised else UITheme.Colors.PanelSunken,
			Size = UDim2.new(1, -8, 0, 54),
		})
		Components.Corner(12).Parent = frame
		if state == "current" then
			Components.Stroke(UITheme.Colors.Cyan, 1.5, 0.3).Parent = frame
		end
		local icon = if state == "done" then "✅" elseif state == "current" then "➤" else "○"
		Components.Label({
			Text = `{icon}  {title}`,
			Font = UITheme.Fonts.Heading,
			TextSize = 16,
			TextColor3 = if state == "upcoming" then UITheme.Colors.Dim else UITheme.Colors.Text,
			Size = UDim2.new(1, -20, 0, 22),
			Position = UDim2.fromOffset(12, 6),
			Parent = frame,
		})
		Components.Label({
			Text = subtitle,
			Font = UITheme.Fonts.Body,
			TextSize = 13,
			TextColor3 = UITheme.Colors.Muted,
			Size = UDim2.new(1, -40, 0, 20),
			Position = UDim2.fromOffset(36, 28),
			Parent = frame,
		})
		add(frame)
	end
	local profile = controllers.ClientState.Profile
	local stage = profile.TutorialStage or 0
	if stage < #QuestDefinitions.Onboarding then
		heading("Getting Started")
		for i, step in QuestDefinitions.Onboarding do
			row(
				fill(step.Title, step),
				fill(step.Text, step),
				if i <= stage then "done" elseif i == stage + 1 then "current" else "upcoming"
			)
		end
	end
	heading("Explorer Missions")
	local missions = (profile.QuestProgress or {}).Missions or { Index = 1, Progress = 0 }
	if stage < #QuestDefinitions.Onboarding then
		add(Components.Label({
			Text = "Unlocks after the Getting Started guide.",
			TextColor3 = UITheme.Colors.Muted,
			Font = UITheme.Fonts.Body,
			Size = UDim2.new(1, 0, 0, 24),
		}))
	end
	for i, mission in QuestDefinitions.Missions do
		local state = if i < missions.Index then "done" elseif i == missions.Index then "current" else "upcoming"
		local subtitle = fill(mission.Text, mission) .. `  ·  {rewardText(mission.Reward)}`
		if state == "current" and stage >= #QuestDefinitions.Onboarding then
			subtitle = `{math.min(missions.Progress or 0, mission.Objective.Target)}/{mission.Objective.Target}  ·  `
				.. subtitle
		end
		row(mission.Title, subtitle, state)
	end
end

local function updateWaypoint()
	local position = waypointPosition(currentWaypoint)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not position or not root or not root:IsA("BasePart") then
		markerGui.Enabled = false
		arrow.Visible = false
		return
	end
	local distance = (root.Position - position).Magnitude
	if distance < 10 then
		markerGui.Enabled = false
		arrow.Visible = false
		return
	end
	markerPart.Position = position
	markerGui.Enabled = true
	markerLabel.Text = `⬇\n{math.floor(distance)}m`
	markerGui.StudsOffsetWorldSpace = Vector3.new(0, 3 + math.sin(os.clock() * 4) * 0.6, 0)
	local camera = Workspace.CurrentCamera
	local screen, onScreen = camera:WorldToViewportPoint(position)
	if onScreen and screen.Z > 0 then
		arrow.Visible = false
		return
	end
	-- Off screen: point an arrow from the screen centre toward the target.
	local viewport = camera.ViewportSize
	local center = viewport / 2
	local direction = Vector2.new(screen.X, screen.Y) - center
	if screen.Z < 0 then
		direction = -direction
	end
	if direction.Magnitude < 1 then
		direction = Vector2.new(0, -1)
	end
	direction = direction.Unit
	local inset = math.min(viewport.X, viewport.Y) * 0.4
	local scale = controllers.Components.GetScale()
	arrow.Position =
		UDim2.fromOffset((center.X + direction.X * inset) / scale, (center.Y + direction.Y * inset) / scale)
	arrow.Rotation = math.deg(math.atan2(direction.Y, direction.X)) + 90
	arrow.Visible = true
end

function ObjectiveController.Init(registry: { [string]: any })
	controllers = registry
end

function ObjectiveController.Start()
	Components = controllers.Components
	local Make = Components.Make
	gui = Components.Screen("Objectives", 4)
	tracker = Make("Frame", {
		Name = "Tracker",
		BackgroundColor3 = UITheme.Colors.Panel,
		BackgroundTransparency = 0.1,
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.fromOffset(310, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = gui,
	})
	Components.Corner(16).Parent = tracker
	Components.Stroke(UITheme.Colors.Lavender, 1.5, 0.45).Parent = tracker
	Components.Padding(12, 14).Parent = tracker
	Components.List(Enum.FillDirection.Vertical, 4).Parent = tracker
	trackerHeader = Components.Label({
		Text = "",
		Font = UITheme.Fonts.Heading,
		TextSize = 12,
		TextColor3 = UITheme.Colors.Lavender,
		Size = UDim2.new(1, 0, 0, 14),
		LayoutOrder = 1,
		Parent = tracker,
	})
	trackerTitle = Components.Label({
		Text = "",
		Font = UITheme.Fonts.Display,
		TextSize = 20,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = 2,
		Parent = tracker,
	})
	trackerText = Components.Label({
		Text = "",
		Font = UITheme.Fonts.Body,
		TextSize = 15,
		TextColor3 = UITheme.Colors.Muted,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 3,
		Parent = tracker,
	})
	local progressRow =
		Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 4, Parent = tracker })
	trackerProgress, setProgress = Components.ProgressBar(UITheme.Colors.Lavender, 8, progressRow)
	trackerProgress.Size = UDim2.new(1, -70, 0, 8)
	trackerProgress.Position = UDim2.fromOffset(0, 3)
	progressLabel = Components.Label({
		Text = "",
		Font = UITheme.Fonts.Bold,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(0, 64, 1, 0),
		Position = UDim2.new(1, -64, 0, 0),
		Parent = progressRow,
	})
	claimButton = Components.Button("Claim", "Gold", UDim2.new(1, 0, 0, 40), tracker)
	claimButton.Instance.LayoutOrder = 5
	claimButton.Instance.Visible = false
	claimButton.Activated:Connect(claimCurrent)

	arrow = Components.Label({
		Text = "▲",
		Font = UITheme.Fonts.Heading,
		TextSize = 40,
		TextColor3 = UITheme.Colors.Gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(50, 50),
		Visible = false,
		Parent = gui,
	})
	Make("UIStroke", { Color = UITheme.Colors.Background, Thickness = 3, Parent = arrow })

	markerPart = Make("Part", {
		Name = "WaypointAnchor",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.new(0.2, 0.2, 0.2),
		Parent = workspace,
	})
	markerGui = Make("BillboardGui", {
		AlwaysOnTop = true,
		LightInfluence = 0,
		Size = UDim2.fromOffset(90, 70),
		MaxDistance = 5000,
		Enabled = false,
		Adornee = markerPart,
		Parent = markerPart,
	})
	markerLabel = Components.Label({
		Text = "",
		Font = UITheme.Fonts.Display,
		TextScaled = true,
		TextColor3 = UITheme.Colors.Gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = markerGui,
	})
	Make("UIStroke", { Color = UITheme.Colors.Background, Thickness = 2.5, Parent = markerLabel })

	panel = Components.Panel("Quests", Vector2.new(640, 560), controllers.PanelManager.Gui())
	panelList = Make("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = panel.Body,
	})
	Components.List(Enum.FillDirection.Vertical, 8).Parent = panelList
	controllers.PanelManager.Register("Quests", panel, renderPanel)

	local function placeTracker()
		if controllers.InputController.Device == "Touch" then
			tracker.Position = UDim2.fromOffset(12, 112)
			tracker.Size = UDim2.fromOffset(280, 0)
		else
			tracker.Position = UDim2.fromOffset(16, 12)
			tracker.Size = UDim2.fromOffset(310, 0)
		end
	end
	placeTracker()
	controllers.InputController.DeviceChanged:Connect(function()
		placeTracker()
		renderTracker()
	end)

	local state = controllers.ClientState
	for _, key in { "TutorialStage", "QuestProgress", "Creatures" } do
		state.Changed:Connect(function(root, changed)
			if root == "Profile" and changed == key then
				renderTracker()
				if controllers.PanelManager.IsOpen("Quests") then
					renderPanel()
				end
			end
		end)
	end
	state.ObserveSession("PlotIndex", function()
		renderTracker()
	end)
	renderTracker()
	local clock = 0
	RunService.RenderStepped:Connect(function(dt)
		clock += dt
		if clock > 0.05 then
			clock = 0
			updateWaypoint()
		end
	end)
end

return ObjectiveController

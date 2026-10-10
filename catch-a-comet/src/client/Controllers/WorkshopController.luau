-- The Equipment Workshop panel. Each track shows its current level, exactly
-- what the next level changes (current → next), any new feature it unlocks,
-- and the precise cost. Buying sends one request; the server spends the
-- Stardust and raises the level together, or does neither.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EquipmentRig = require(Shared.EquipmentRig)
local Format = require(Shared.Format)
local RemoteDefinitions = require(Shared.RemoteDefinitions)
local UITheme = require(Shared.UITheme)
local UpgradeDefinitions = require(Shared.UpgradeDefinitions)

local WorkshopController = {}

local controllers: { [string]: any } = {}
local Components: any
local panel: any
local cards: { [string]: { Level: TextLabel, Stats: Frame, Feature: TextLabel, Button: any } } = {}
local preview: ViewportFrame
local previewCamera: Camera
local previewModel: Model? = nil
local spinConnection: RBXScriptConnection? = nil

local REASONS = {
	NotEnoughStardust = "Not enough Stardust yet.",
	MaxLevel = "Already at the highest level.",
	RateLimited = "One moment…",
}

local function rebuildPreview()
	if previewModel then
		previewModel:Destroy()
	end
	local equipment = controllers.ClientState.Equipment()
	local model = EquipmentRig.BuildDevice(equipment.ScannerLevel, equipment.TetherLevel)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	model.Parent = preview
	previewModel = model
end

local function render(rebuildDevice: boolean?)
	local equipment = controllers.ClientState.Equipment()
	local stardust = controllers.ClientState.Get("Stardust") or 0
	for _, trackId in UpgradeDefinitions.Order do
		local track = UpgradeDefinitions.Tracks[trackId]
		local card = cards[trackId]
		local level = equipment[track.ProfileKey] or 1
		local max = #track.Levels
		card.Level.Text = `Level {level} / {max}`
		for _, child in card.Stats:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for i, line in UpgradeDefinitions.Describe(trackId, level) do
			local row = Components.Make(
				"Frame",
				{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = i, Parent = card.Stats }
			)
			Components.Label({
				Text = line.Label,
				Font = UITheme.Fonts.Body,
				TextSize = 14,
				TextColor3 = UITheme.Colors.Muted,
				Size = UDim2.new(0.5, 0, 1, 0),
				Parent = row,
			})
			Components.Label({
				Text = if line.Next then `{line.Current}  →  {line.Next}` else line.Current,
				Font = UITheme.Fonts.Heading,
				TextSize = 14,
				TextColor3 = if line.Next then UITheme.Colors.Cyan else UITheme.Colors.Text,
				TextXAlignment = Enum.TextXAlignment.Right,
				Size = UDim2.new(0.5, 0, 1, 0),
				Position = UDim2.fromScale(0.5, 0),
				Parent = row,
			})
		end
		local nextLevel = if level < max then track.Levels[level + 1] else nil
		card.Feature.Text = if nextLevel and nextLevel.FeatureText then `NEW: {nextLevel.FeatureText}` else ""
		if not nextLevel then
			card.Button:SetText("MAX LEVEL")
			card.Button:SetStyle("Success")
			card.Button:SetEnabled(false)
		elseif stardust >= nextLevel.Cost then
			card.Button:SetText(
				if nextLevel.Cost == 0 then "Upgrade · Free" else `Upgrade · {Format.Number(nextLevel.Cost)} ✦`
			)
			card.Button:SetStyle("Gold")
			card.Button:SetEnabled(true)
		else
			card.Button:SetText(`Need {Format.Short(nextLevel.Cost - stardust)} more ✦`)
			card.Button:SetStyle("Secondary")
			card.Button:SetEnabled(false)
		end
	end
	if rebuildDevice or not previewModel then
		rebuildPreview()
	end
end

local function buildCard(parent: Frame, trackId: string, order: number)
	local track = UpgradeDefinitions.Tracks[trackId]
	local Make = Components.Make
	local card = Make("Frame", {
		Name = trackId,
		LayoutOrder = order,
		BackgroundColor3 = UITheme.Colors.PanelRaised,
		Size = UDim2.new(1 / 3, -8, 1, 0),
		Parent = parent,
	})
	Components.Corner(16).Parent = card
	Components.Stroke(UITheme.Colors.Stroke, 1.5, 0.2).Parent = card
	Components.Padding(14).Parent = card
	Components.Label({ Text = track.Icon, TextSize = 34, Size = UDim2.fromOffset(44, 44), Parent = card })
	Components.Label({
		Text = track.DisplayName,
		Font = UITheme.Fonts.Display,
		TextSize = 20,
		Size = UDim2.new(1, -50, 0, 24),
		Position = UDim2.fromOffset(50, 0),
		Parent = card,
	})
	local level = Components.Label({
		Text = "",
		Font = UITheme.Fonts.Bold,
		TextSize = 14,
		TextColor3 = UITheme.Colors.Gold,
		Size = UDim2.new(1, -50, 0, 18),
		Position = UDim2.fromOffset(50, 24),
		Parent = card,
	})
	Components.Label({
		Text = track.Summary,
		Font = UITheme.Fonts.Body,
		TextSize = 14,
		TextColor3 = UITheme.Colors.Muted,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.fromOffset(0, 52),
		Parent = card,
	})
	local stats = Make(
		"Frame",
		{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 72), Position = UDim2.fromOffset(0, 98), Parent = card }
	)
	Components.List(Enum.FillDirection.Vertical, 2).Parent = stats
	local feature = Components.Label({
		Text = "",
		Font = UITheme.Fonts.Heading,
		TextSize = 13,
		TextColor3 = UITheme.Colors.Green,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.fromOffset(0, 172),
		Parent = card,
	})
	local button = Components.Button("Upgrade", "Gold", UDim2.new(1, 0, 0, 46), card)
	button.Instance.AnchorPoint = Vector2.new(0, 1)
	button.Instance.Position = UDim2.fromScale(0, 1)
	button.Activated:Connect(function()
		button:SetLoading(true)
		local ok, result = pcall(function()
			return RemoteDefinitions.GetFunction("PurchaseUpgrade"):InvokeServer(trackId)
		end)
		button:SetLoading(false)
		if not ok or type(result) ~= "table" or not result.Ok then
			local reason = if ok and type(result) == "table" then result.Reason else nil
			controllers.NotificationController.Toast(REASONS[reason or ""] or "Couldn't upgrade right now.", "🔧")
			controllers.AudioController.Play("UIError")
		end
		render(true)
	end)
	cards[trackId] = { Level = level, Stats = stats, Feature = feature, Button = button }
	if order == 1 then
		panel.FirstSelectable = button.Instance
	end
end

function WorkshopController.Init(registry: { [string]: any })
	controllers = registry
end

function WorkshopController.Start()
	Components = controllers.Components
	local Make = Components.Make
	panel = Components.Panel("Equipment Workshop", Vector2.new(900, 560), controllers.PanelManager.Gui())
	local body = panel.Body

	local header = Make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 150), Parent = body })
	local previewFrame = Make("Frame", {
		BackgroundColor3 = UITheme.Colors.PanelSunken,
		Size = UDim2.fromOffset(220, 150),
		Parent = header,
	})
	Components.Corner(16).Parent = previewFrame
	preview = Make("ViewportFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(170, 160, 210),
		LightColor = Color3.fromRGB(255, 248, 240),
		LightDirection = Vector3.new(-0.5, -1, -0.6),
		Parent = previewFrame,
	})
	previewCamera = Make("Camera", { FieldOfView = 30, Parent = preview })
	preview.CurrentCamera = previewCamera
	Components.Label({
		Text = "Your Comet Tether",
		Font = UITheme.Fonts.Display,
		TextSize = 24,
		Size = UDim2.new(1, -240, 0, 30),
		Position = UDim2.fromOffset(240, 8),
		Parent = header,
	})
	Components.Label({
		Text = "Upgrades change how you play: a stronger Scanner finds comets and wisps from farther away, a better Tether makes stabilizing more forgiving, and more Habitats let more creatures gather Stardust. Everyone can see your device change.",
		Font = UITheme.Fonts.Body,
		TextSize = 15,
		TextColor3 = UITheme.Colors.Muted,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -240, 0, 100),
		Position = UDim2.fromOffset(240, 44),
		Parent = header,
	})
	local row = Make("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 162),
		Size = UDim2.new(1, 0, 1, -162),
		Parent = body,
	})
	Components.List(Enum.FillDirection.Horizontal, 12).Parent = row
	for i, trackId in UpgradeDefinitions.Order do
		buildCard(row, trackId, i)
	end

	controllers.PanelManager.Register("Workshop", panel, function()
		render(true)
		if spinConnection then
			spinConnection:Disconnect()
		end
		local yaw = 0
		spinConnection = RunService.RenderStepped:Connect(function(dt)
			yaw += dt * 0.6
			previewCamera.CFrame = CFrame.lookAt(
				Vector3.new(math.sin(yaw) * 4.2, 1.6, math.cos(yaw) * 4.2) + Vector3.new(0, 0.2, -0.6),
				Vector3.new(0, 0.2, -0.6)
			)
		end)
	end, function()
		if spinConnection then
			spinConnection:Disconnect()
			spinConnection = nil
		end
	end)
	local state = controllers.ClientState
	state.Changed:Connect(function(root, key)
		if
			root == "Profile"
			and (key == "Equipment" or key == "Stardust")
			and controllers.PanelManager.IsOpen("Workshop")
		then
			render(key == "Equipment")
		end
	end)
end

return WorkshopController

-- Opening a sealed comet core.
--
-- The server rolls and grants the creature the moment OpenComet is called;
-- this controller only presents the result. Common finds pop quickly; rarer
-- finds get light rays, a longer build-up, a fanfare and a world flash. Every
-- reveal can be skipped, and leaving mid-reveal loses nothing because the
-- creature already exists in the profile.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreatureDefinitions = require(Shared.CreatureDefinitions)
local EconomyMath = require(Shared.EconomyMath)
local Format = require(Shared.Format)
local RarityConfig = require(Shared.RarityConfig)
local RemoteDefinitions = require(Shared.RemoteDefinitions)
local Signal = require(Shared.Signal)
local UITheme = require(Shared.UITheme)

local RevealController = {}

-- (creature, isNew)
RevealController.Revealed = Signal.new()
RevealController.Busy = false

local FAILURES: { [string]: string } = {
	InventoryFull = "Your creature storage is full. Release a few creatures to make room.",
	NoSuchCore = "That core was already opened.",
	NotReady = "Still loading your save…",
	RateLimited = "One at a time!",
}

local controllers: { [string]: any } = {}
local Components: any
local gui: ScreenGui
local overlay: Frame
local stage: Frame
local coreOrb: Frame
local rays: Frame
local portraitHolder: Frame
local nameLabel: TextLabel
local tagRow: Frame
local descLabel: TextLabel
local statLabel: TextLabel
local newBadge: TextLabel
local buttons: Frame
local skipButton: TextButton
local flash: Frame
local queue: { string } = {}
local skipRequested = false
local cleanup: { () -> () } = {}

local function runCleanup()
	for _, fn in cleanup do
		fn()
	end
	cleanup = {}
end

local function buildUI()
	Components = controllers.Components
	local Make = Components.Make
	gui = Components.Screen("RevealUI", 40, false)
	overlay = Make("Frame", {
		Name = "Overlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = UITheme.Colors.Background,
		BackgroundTransparency = 0.25,
		Visible = false,
		Parent = gui,
	})
	stage = Make("Frame", {
		Name = "Stage",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.fromOffset(520, 620),
		BackgroundTransparency = 1,
		Parent = overlay,
	})
	rays = Make("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 200),
		Size = UDim2.fromOffset(560, 560),
		BackgroundTransparency = 1,
		Parent = stage,
	})
	for i = 0, 11 do
		local ray = Make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(26, 560),
			Rotation = i * 15,
			BackgroundColor3 = UITheme.Colors.Gold,
			BackgroundTransparency = 0.82,
			BorderSizePixel = 0,
			Parent = rays,
		})
		Make("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Rotation = 90,
			Parent = ray,
		})
	end
	portraitHolder = Make("Frame", {
		Name = "Portrait",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 200),
		Size = UDim2.fromOffset(340, 340),
		BackgroundTransparency = 1,
		Parent = stage,
	})
	Make("UIScale", { Name = "Scale", Parent = portraitHolder })
	coreOrb = Make("Frame", {
		Name = "Core",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 200),
		Size = UDim2.fromOffset(150, 150),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = stage,
	})
	Components.Round().Parent = coreOrb
	Components.Stroke(UITheme.Colors.Cyan, 6, 0.2).Parent = coreOrb
	Components.Gradient(Color3.new(1, 1, 1), UITheme.Colors.Cyan).Parent = coreOrb
	Make("UIScale", { Name = "Scale", Parent = coreOrb })
	Components.Label({
		Text = "☄️",
		TextSize = 64,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = coreOrb,
	})

	newBadge = Components.Tag("NEW SPECIES!", UITheme.Colors.Gold, stage)
	newBadge.AnchorPoint = Vector2.new(0.5, 0)
	newBadge.Position = UDim2.new(0.5, 0, 0, 360)
	newBadge.TextSize = 16
	newBadge.Size = UDim2.fromOffset(0, 26)

	nameLabel = Components.Label({
		Text = "",
		Font = UITheme.Fonts.Display,
		TextSize = 46,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 54),
		Position = UDim2.fromOffset(0, 392),
		Parent = stage,
	})
	Make("UIStroke", { Color = UITheme.Colors.Background, Thickness = 3, Parent = nameLabel })
	tagRow = Make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 450),
		Parent = stage,
	})
	Components.List(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center).Parent = tagRow
	descLabel = Components.Label({
		Text = "",
		Font = UITheme.Fonts.Body,
		TextSize = 17,
		TextColor3 = UITheme.Colors.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, -40, 0, 44),
		Position = UDim2.fromOffset(20, 480),
		Parent = stage,
	})
	statLabel = Components.Label({
		Text = "",
		Font = UITheme.Fonts.Heading,
		TextSize = 18,
		TextColor3 = UITheme.Colors.Gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 526),
		Parent = stage,
	})
	buttons = Make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 50),
		Position = UDim2.fromOffset(0, 562),
		Parent = stage,
	})
	Components.List(Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Center).Parent = buttons

	skipButton = Make("TextButton", {
		Text = "Skip ▸",
		Font = UITheme.Fonts.Heading,
		TextSize = 16,
		TextColor3 = UITheme.Colors.Muted,
		BackgroundColor3 = UITheme.Colors.Panel,
		BackgroundTransparency = 0.2,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -24),
		Size = UDim2.fromOffset(96, 40),
		Parent = overlay,
	})
	Components.Round().Parent = skipButton
	skipButton.Activated:Connect(function()
		skipRequested = true
	end)

	flash = Make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	})
end

local function close()
	runCleanup()
	overlay.Visible = false
	RevealController.Busy = false
	controllers.InputController.SetMovementEnabled(true)
	local nextCore = table.remove(queue, 1)
	if nextCore then
		task.defer(RevealController.Open, nextCore)
	end
end

local function wait(seconds: number)
	local deadline = os.clock() + seconds
	while os.clock() < deadline and not skipRequested do
		task.wait()
	end
end

local function addButtons(creature: any)
	for _, child in buttons:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local deploy = Components.Button("Place in Habitat", "Primary", UDim2.fromOffset(190, 46), buttons)
	deploy.Instance.LayoutOrder = 1
	deploy.Activated:Connect(function()
		close()
		controllers.SanctuaryController.PickSlotFor(creature.Id)
	end)
	local inventory = Components.Button("Inventory", "Secondary", UDim2.fromOffset(140, 46), buttons)
	inventory.Instance.LayoutOrder = 2
	inventory.Activated:Connect(function()
		close()
		controllers.InventoryController.Open("Creatures", creature.Id)
	end)
	local done = Components.Button("Continue", "Ghost", UDim2.fromOffset(120, 46), buttons)
	done.Instance.LayoutOrder = 3
	done.Activated:Connect(close)
	Components.FocusFirst(deploy.Instance)
end

local function present(creature: any, isNew: boolean)
	local species = CreatureDefinitions.Get(creature.Species)
	local rarity = if species then species.Rarity else "Common"
	local tier = RarityConfig.Rarities[rarity].RevealTier
	local rarityColor = UITheme.RarityColor(rarity)
	local reduced = Components.ReducedMotion
	skipRequested = false

	overlay.Visible = true
	stage.Visible = true
	for _, child in tagRow:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for _, child in buttons:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	nameLabel.Text = ""
	descLabel.Text = ""
	statLabel.Text = ""
	newBadge.Visible = false
	skipButton.Visible = true
	coreOrb.Visible = true
	portraitHolder.Visible = false
	rays.Visible = tier >= 2
	for _, ray in rays:GetChildren() do
		if ray:IsA("Frame") then
			ray.BackgroundColor3 = rarityColor
		end
	end
	local coreStroke = coreOrb:FindFirstChildOfClass("UIStroke")
	if coreStroke then
		coreStroke.Color = if tier >= 3 then rarityColor else UITheme.Colors.Cyan
	end

	-- Rays turn (and shimmer through colours for Mythic) while the reveal is open.
	local spin = RunService.RenderStepped:Connect(function(dt)
		rays.Rotation += dt * (if reduced then 4 else 18)
		if rarity == "Mythic" then
			local hue = (os.clock() * 0.15) % 1
			for _, ray in rays:GetChildren() do
				if ray:IsA("Frame") then
					ray.BackgroundColor3 = Color3.fromHSV(hue, 0.45, 1)
				end
			end
		end
	end)
	table.insert(cleanup, function()
		spin:Disconnect()
	end)

	-- Build-up: the core pulses longer for rarer finds.
	local coreScale = coreOrb:FindFirstChild("Scale") :: UIScale
	local pulses = if tier >= 4 then 4 elseif tier == 3 then 3 elseif tier == 2 then 2 else 1
	controllers.AudioController.Play("Contain", { Pitch = 0.7 + tier * 0.08 })
	for i = 1, pulses do
		if skipRequested then
			break
		end
		coreScale.Scale = 1
		Components.Tween(coreScale, 0.18, { Scale = 1.12 + i * 0.05 }, Enum.EasingStyle.Back)
		controllers.AudioController.Play("Chime", { Pitch = 0.8 + i * 0.12, Volume = 0.8 })
		wait(0.32)
	end

	-- Burst.
	coreOrb.Visible = false
	if not reduced and tier >= 3 then
		flash.BackgroundTransparency = 0.2
		Components.Tween(flash, 0.5, { BackgroundTransparency = 1 })
		controllers.CameraController.FovPunch(-6)
	end
	if tier >= 3 then
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			controllers.EffectsController.Burst(root.Position + Vector3.new(0, 2, 0), rarityColor, 50, "Stars")
			controllers.EffectsController.Flash(root.Position + Vector3.new(0, 4, 0), rarityColor, 6, 40, 1.2)
		end
	end
	controllers.AudioController.Fanfare(tier)

	for _, child in portraitHolder:GetChildren() do
		if child:IsA("ViewportFrame") then
			child:Destroy()
		end
	end
	local portrait = controllers.Viewport.Creature(
		portraitHolder,
		creature.Species,
		{ Mutation = creature.Mutation, Yaw = 20, Zoom = 0.95 }
	)
	table.insert(cleanup, controllers.Viewport.Spin(portrait, 35))
	portraitHolder.Visible = true
	local portraitScale = portraitHolder:FindFirstChild("Scale") :: UIScale
	portraitScale.Scale = if reduced then 1 else 0.4
	Components.Tween(portraitScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)

	nameLabel.Text = if species then species.DisplayName else creature.Species
	nameLabel.TextColor3 = if rarity == "Common" then UITheme.Colors.Text else rarityColor
	Components.Pop(nameLabel, 0.2)
	local rarityTag = Components.Tag(string.upper(rarity), rarityColor, tagRow)
	rarityTag.LayoutOrder = 1
	if creature.Mutation ~= "Standard" then
		local mutationTag = Components.Tag(
			`{string.upper(creature.Mutation)} MUTATION`,
			UITheme.MutationColor(creature.Mutation),
			tagRow
		)
		mutationTag.LayoutOrder = 2
	end
	newBadge.Visible = isNew
	if isNew then
		Components.Pop(newBadge, 0.3)
	end
	descLabel.Text = if species then species.Description else ""
	statLabel.Text = `Produces ✦ {Format.Rate(EconomyMath.CreatureIncome(creature))}/s in a habitat`
	skipButton.Visible = false
	addButtons(creature)
	RevealController.Revealed:Fire(creature, isNew)
end

-- Opens a core (server roll) and plays the reveal. Queues if one is already showing.
function RevealController.Open(coreId: string)
	if RevealController.Busy then
		if not table.find(queue, coreId) then
			table.insert(queue, coreId)
		end
		return
	end
	RevealController.Busy = true
	local ok, result = pcall(function()
		return RemoteDefinitions.GetFunction("OpenComet"):InvokeServer(coreId)
	end)
	if not ok or type(result) ~= "table" or not result.Ok then
		RevealController.Busy = false
		local reason = if ok and type(result) == "table" then result.Reason else nil
		controllers.NotificationController.Toast(
			FAILURES[reason or ""] or "Couldn't open that core. Try again!",
			"⚠️"
		)
		return
	end
	controllers.InputController.SetMovementEnabled(false)
	controllers.PanelManager.Close()
	present(result.Creature, result.IsNew == true)
end

function RevealController.Init(registry: { [string]: any })
	controllers = registry
end

function RevealController.Start()
	buildUI()
end

return RevealController

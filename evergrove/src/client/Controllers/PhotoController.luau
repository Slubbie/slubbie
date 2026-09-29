-- Photo mode (F2, or from the menu).
--
-- A free camera that flies around your character: WASD / left stick to move,
-- Q/E (or the triggers) for down/up, right-drag or right stick to look, scroll
-- to zoom (field of view), Z/X to tilt. The HUD hides; a slim toolbar offers
-- filters, depth of field, a vignette, emotes and a "hide toolbar" key (H)
-- for clean shots, then use Roblox's own screenshot button.
--
-- Emote(id) is also used by the menu's emote row outside photo mode; moving
-- clears a pose.

local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Social = require(Shared.Config.Social)
local Net = require(Shared.Lib.Net)

local C = require(script.Parent)
local UIFolder = script.Parent.Parent:WaitForChild("UI")
local Kit = require(UIFolder.Kit)
local Theme = require(UIFolder.Theme)

local PhotoController = {}

local player = Players.LocalPlayer
local MAX_DISTANCE = 60 -- how far the camera may fly from your character

local FILTERS = {
	{ Id = "Natural", Icon = "🌿" },
	{ Id = "Warm", Icon = "🌅", Tint = Color3.fromRGB(255, 232, 205), Saturation = 0.1, Contrast = 0.05 },
	{ Id = "Cool", Icon = "❄️", Tint = Color3.fromRGB(215, 232, 255), Saturation = -0.05, Contrast = 0.05 },
	{ Id = "Vivid", Icon = "🌈", Saturation = 0.35, Contrast = 0.12 },
	{
		Id = "Dreamy",
		Icon = "☁️",
		Tint = Color3.fromRGB(255, 235, 250),
		Saturation = -0.1,
		Contrast = -0.1,
		Brightness = 0.06,
		Bloom = true,
	},
	{ Id = "Vintage", Icon = "📜", Tint = Color3.fromRGB(240, 220, 180), Saturation = -0.35, Contrast = 0.08 },
	{ Id = "Noir", Icon = "🎞️", Saturation = -1, Contrast = 0.25 },
}

local active = false
local releaseCamera: (() -> ())? = nil
local toolbar: Frame? = nil
local toolbarHidden = false
local camPosition = Vector3.zero
local yaw, pitch, roll = 0, 0, 0
local fov = 70
local savedFov = 70
local filterIndex = 1
local correction: ColorCorrectionEffect? = nil
local bloom: BloomEffect? = nil
local dof: DepthOfFieldEffect? = nil
local vignette: Frame? = nil
local looking = false
local emoteButtons: { [string]: TextButton } = {}

function PhotoController.Active(): boolean
	return active
end

-- Emotes -----------------------------------------------------------------------------------------------------------------

local function ownsEmote(emote: any): boolean
	if not emote.Pack then
		return true
	end
	local owned = C.State.Get("Cosmetics", "Owned") or {}
	return owned["Emote:" .. emote.Id] == true
end

function PhotoController.Emote(id: string?)
	local character = player.Character
	if not character then
		return
	end
	if id and character:GetAttribute("Pose") == id then
		id = nil
	end
	if id then
		for _, emote in Social.Emotes do
			if emote.Id == id and not ownsEmote(emote) then
				C.Notify.Toast(emote.Icon .. " " .. emote.Name .. " comes with the Farmer's Emote Pack", "Info")
				C.Windows.Open("Store")
				return
			end
		end
	end
	Net.Send("Pose", id)
	for emoteId, button in emoteButtons do
		Kit.Paint(button, "BackgroundColor3", if emoteId == id then "Accent" else "PanelAlt")
	end
end

-- Effects ----------------------------------------------------------------------------------------------------------------

local function applyFilter()
	local filter = FILTERS[filterIndex]
	if not correction then
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "PhotoFilter"
		cc.Parent = Lighting
		correction = cc
	end
	local cc = correction :: ColorCorrectionEffect
	cc.TintColor = filter.Tint or Color3.new(1, 1, 1)
	cc.Saturation = filter.Saturation or 0
	cc.Contrast = filter.Contrast or 0
	cc.Brightness = filter.Brightness or 0
	if filter.Bloom and not bloom then
		local b = Instance.new("BloomEffect")
		b.Name = "PhotoBloom"
		b.Intensity = 0.6
		b.Size = 40
		b.Threshold = 0.85
		b.Parent = Lighting
		bloom = b
	elseif not filter.Bloom and bloom then
		bloom:Destroy()
		bloom = nil
	end
end

local function setDof(on: boolean)
	if on and not dof then
		local effect = Instance.new("DepthOfFieldEffect")
		effect.Name = "PhotoDOF"
		effect.FarIntensity = 0.6
		effect.NearIntensity = 0.4
		effect.InFocusRadius = 12
		effect.Parent = Lighting
		dof = effect
	elseif not on and dof then
		dof:Destroy()
		dof = nil
	end
end

local function clearEffects()
	for _, effect in { correction, bloom, dof } do
		if effect then
			effect:Destroy()
		end
	end
	correction, bloom, dof = nil, nil, nil
	if vignette then
		vignette:Destroy()
		vignette = nil
	end
end

local function setVignette(on: boolean)
	if on and not vignette then
		-- Four soft black edges fading toward the centre.
		local frame = Instance.new("Frame")
		frame.Name = "Vignette"
		frame.BackgroundTransparency = 1
		frame.Size = UDim2.fromScale(1, 1)
		local edges = {
			{ Size = UDim2.fromScale(1, 0.3), Position = UDim2.fromScale(0, 0), Rotation = 90 },
			{ Size = UDim2.fromScale(1, 0.3), Position = UDim2.fromScale(0, 0.7), Rotation = -90 },
			{ Size = UDim2.fromScale(0.25, 1), Position = UDim2.fromScale(0, 0), Rotation = 0 },
			{ Size = UDim2.fromScale(0.25, 1), Position = UDim2.fromScale(0.75, 0), Rotation = 180 },
		}
		for _, edge in edges do
			local e = Instance.new("Frame")
			e.BorderSizePixel = 0
			e.BackgroundColor3 = Color3.new(0, 0, 0)
			e.Size = edge.Size
			e.Position = edge.Position
			local gradient = Instance.new("UIGradient")
			gradient.Rotation = edge.Rotation
			gradient.Transparency = NumberSequence.new(0.35, 1)
			gradient.Parent = e
			e.Parent = frame
		end
		frame.Parent = C.UI.Layer("World")
		vignette = frame
	elseif not on and vignette then
		vignette:Destroy()
		vignette = nil
	end
end

-- Toolbar ----------------------------------------------------------------------------------------------------------------

local function buildToolbar()
	local bar = Kit.Panel({ Size = UDim2.fromOffset(0, 0), Shadow = true, Name = "PhotoBar" })
	bar.AutomaticSize = Enum.AutomaticSize.XY
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -14)
	Kit.Padding(bar, 8, 12)
	Kit.List(bar, "Y", 6, "Center")
	local title = Kit.Label(
		"📷 Photo mode  ·  H hides this bar  ·  use Roblox's screenshot button to save",
		{ Size = Theme.Sizes.Tiny, Color = "SubText", Align = "Center" }
	)
	title.AutomaticSize = Enum.AutomaticSize.X
	title.Size = UDim2.fromOffset(0, 16)
	title.Parent = bar
	local row = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 1,
		Parent = bar,
	})
	Kit.List(row, "X", 6, "Center")
	-- Filters
	local filterButton: TextButton
	filterButton = Kit.Button(FILTERS[filterIndex].Icon .. " " .. FILTERS[filterIndex].Id, {
		Style = "Secondary",
		Size = UDim2.fromOffset(130, 38),
		TextSize = Theme.Sizes.Small,
		OnClick = function()
			filterIndex = filterIndex % #FILTERS + 1
			applyFilter()
			filterButton.Text = FILTERS[filterIndex].Icon .. " " .. FILTERS[filterIndex].Id
		end,
	})
	filterButton.Parent = row
	local dofButton, _ = Kit.Toggle(false, function(on)
		setDof(on)
	end)
	local dofWrap = Kit.new(
		"Frame",
		{ BackgroundTransparency = 1, Size = UDim2.fromOffset(110, 38), LayoutOrder = 1, Parent = row }
	)
	local dofLabel = Kit.Label("Focus", { Size = Theme.Sizes.Tiny })
	dofLabel.Size = UDim2.fromOffset(50, 38)
	dofLabel.Parent = dofWrap
	dofButton.Position = UDim2.fromOffset(54, 5)
	dofButton.Parent = dofWrap
	local vigButton, _ = Kit.Toggle(false, function(on)
		setVignette(on)
	end)
	local vigWrap = Kit.new(
		"Frame",
		{ BackgroundTransparency = 1, Size = UDim2.fromOffset(130, 38), LayoutOrder = 2, Parent = row }
	)
	local vigLabel = Kit.Label("Vignette", { Size = Theme.Sizes.Tiny })
	vigLabel.Size = UDim2.fromOffset(70, 38)
	vigLabel.Parent = vigWrap
	vigButton.Position = UDim2.fromOffset(72, 5)
	vigButton.Parent = vigWrap
	local reset = Kit.IconButton("🎯", "Back to your character", function()
		local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if rootPart then
			camPosition = rootPart.Position + rootPart.CFrame.LookVector * 10 + Vector3.new(0, 3, 0)
			yaw = math.atan2(rootPart.CFrame.LookVector.X, rootPart.CFrame.LookVector.Z)
			pitch, roll, fov = -0.1, 0, 70
		end
	end)
	reset.LayoutOrder = 3
	reset.Parent = row
	local exit = Kit.Button("Done", {
		Style = "Accent",
		Size = UDim2.fromOffset(80, 38),
		TextSize = Theme.Sizes.Small,
		OnClick = function()
			PhotoController.Toggle()
		end,
	})
	exit.LayoutOrder = 4
	exit.Parent = row
	-- Emotes
	local emotes = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 36),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		Parent = bar,
	})
	Kit.List(emotes, "X", 4, "Center")
	table.clear(emoteButtons)
	for i, emote in Social.Emotes do
		local b = Kit.IconButton(
			emote.Icon,
			emote.Name .. (if emote.Pack and not ownsEmote(emote) then " (emote pack)" else ""),
			function()
				PhotoController.Emote(emote.Id)
			end,
			34
		)
		b.LayoutOrder = i
		if not ownsEmote(emote) then
			b.TextTransparency = 0.5
		end
		b.Parent = emotes
		emoteButtons[emote.Id] = b
	end
	bar.Parent = C.UI.Layer("Modal")
	Kit.Pop(bar)
	toolbar = bar
end

-- Enter / exit -------------------------------------------------------------------------------------------------------------

local function sink()
	return Enum.ContextActionResult.Sink
end

function PhotoController.Toggle()
	local camera = workspace.CurrentCamera
	if active then
		active = false
		if toolbar then
			toolbar:Destroy()
			toolbar = nil
		end
		clearEffects()
		camera.FieldOfView = savedFov
		if releaseCamera then
			releaseCamera()
			releaseCamera = nil
		end
		ContextActionService:UnbindAction("EvergrovePhoto")
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		for _, name in { "Windows", "Overlay" } do
			C.UI.Layer(name).Visible = true
		end
		C.HUD.UpdateVisibility()
		return
	end
	if C.Build.Active() then
		C.Build.Exit()
	end
	if C.Windows.IsOpen() then
		C.Windows.Close(true)
	end
	local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end
	active = true
	savedFov = camera.FieldOfView
	fov = savedFov
	local cf = camera.CFrame
	camPosition = cf.Position
	local look = cf.LookVector
	yaw = math.atan2(-look.X, -look.Z)
	pitch = math.asin(math.clamp(look.Y, -1, 1))
	roll = 0
	releaseCamera = C.Camera.Take("Photo")
	ContextActionService:BindActionAtPriority(
		"EvergrovePhoto",
		sink,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.PlayerActions.CharacterForward,
		Enum.PlayerActions.CharacterBackward,
		Enum.PlayerActions.CharacterLeft,
		Enum.PlayerActions.CharacterRight,
		Enum.PlayerActions.CharacterJump
	)
	for _, name in { "Windows", "Overlay" } do
		C.UI.Layer(name).Visible = false
	end
	toolbarHidden = false
	buildToolbar()
	applyFilter()
	C.HUD.UpdateVisibility()
	C.Audio.PlayUI("UIOpen")
end

-- Loop ---------------------------------------------------------------------------------------------------------------------

function PhotoController.Start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if not active then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			looking = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		elseif processed then
			return
		elseif input.KeyCode == Enum.KeyCode.H then
			toolbarHidden = not toolbarHidden
			if toolbar then
				toolbar.Visible = not toolbarHidden
			end
		elseif input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			PhotoController.Toggle()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			looking = false
			if active then
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			end
		end
	end)
	UserInputService.InputChanged:Connect(function(input, processed)
		if not active then
			return
		end
		local sensitivity = C.Settings.Get("Sensitivity") or 1
		local invert = if C.Settings.Get("InvertY") then -1 else 1
		if input.UserInputType == Enum.UserInputType.MouseMovement and looking then
			yaw -= input.Delta.X * 0.004 * sensitivity
			pitch = math.clamp(pitch - input.Delta.Y * 0.004 * sensitivity * invert, -1.4, 1.4)
		elseif input.UserInputType == Enum.UserInputType.Touch and not processed then
			yaw -= input.Delta.X * 0.006 * sensitivity
			pitch = math.clamp(pitch - input.Delta.Y * 0.006 * sensitivity * invert, -1.4, 1.4)
		elseif input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
			fov = math.clamp(fov - input.Position.Z * 4, 15, 100)
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		if not active then
			return
		end
		local move = Vector3.zero
		local focused = UserInputService:GetFocusedTextBox() ~= nil
		if not focused then
			local function key(code: Enum.KeyCode): number
				return if UserInputService:IsKeyDown(code) then 1 else 0
			end
			move = Vector3.new(
				key(Enum.KeyCode.D) - key(Enum.KeyCode.A),
				key(Enum.KeyCode.E) - key(Enum.KeyCode.Q),
				key(Enum.KeyCode.S) - key(Enum.KeyCode.W)
			)
			roll += (key(Enum.KeyCode.Z) - key(Enum.KeyCode.X)) * dt * 0.8
		end
		for _, state in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
			if state.KeyCode == Enum.KeyCode.Thumbstick1 and state.Position.Magnitude > 0.15 then
				move += Vector3.new(state.Position.X, 0, -state.Position.Y)
			elseif state.KeyCode == Enum.KeyCode.Thumbstick2 and state.Position.Magnitude > 0.15 then
				yaw -= state.Position.X * dt * 2.2
				pitch = math.clamp(pitch + state.Position.Y * dt * 1.8, -1.4, 1.4)
			elseif state.KeyCode == Enum.KeyCode.ButtonR2 then
				move += Vector3.new(0, state.Position.Z, 0)
			elseif state.KeyCode == Enum.KeyCode.ButtonL2 then
				move -= Vector3.new(0, state.Position.Z, 0)
			end
		end
		local rotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
		if move.Magnitude > 0 then
			local speed = if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then 40 else 16
			camPosition += rotation:VectorToWorldSpace(move) * speed * dt
		end
		-- Stay near your character.
		local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if rootPart then
			local offset = camPosition - rootPart.Position
			if offset.Magnitude > MAX_DISTANCE then
				camPosition = rootPart.Position + offset.Unit * MAX_DISTANCE
			end
		end
		local camera = workspace.CurrentCamera
		camera.CFrame = CFrame.new(camPosition) * rotation * CFrame.Angles(0, 0, roll)
		camera.FieldOfView = camera.FieldOfView + (fov - camera.FieldOfView) * math.min(1, dt * 10)
		if dof and rootPart then
			(dof :: DepthOfFieldEffect).FocusDistance = (rootPart.Position - camPosition).Magnitude
		end
	end)
	-- Walking away ends an emote.
	local function watchCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if not humanoid then
			return
		end
		humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(function()
			if humanoid.MoveDirection.Magnitude > 0.1 and character:GetAttribute("Pose") and not active then
				Net.Send("Pose", nil)
			end
		end)
	end
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)
end

return PhotoController

-- In-game HUD: crosshair that locks on to grapple targets, speedometer, dash
-- charges, shard counter and a controls hint that fades out.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local MathUtil = require(ReplicatedStorage.Shared.MathUtil)
local Grapple = require(script.Parent.Grapple)
local Settings = require(script.Parent.Settings)
local UI = require(script.Parent.UI)

local Damp = MathUtil.Damp
local IDLE = Color3.fromRGB(210, 215, 225)

local HUD = {}

local gui: ScreenGui? = nil

function HUD.SetVisible(visible: boolean)
	if gui then
		gui.Enabled = visible
	end
end

function HUD.Start(Movement)
	local localPlayer = Players.LocalPlayer
	gui = UI.gui("SkyboundHUD", 2)
	local screen = gui :: ScreenGui

	local function ropeColor(): Color3
		local color = localPlayer:GetAttribute("RopeColor")
		return if typeof(color) == "Color3" then color else Config.Grapple.RopeColor
	end

	-- Crosshair ---------------------------------------------------------------
	local dot = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(4, 4),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, screen)
	UI.corner(dot)
	local ring = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(22, 22),
		BackgroundTransparency = 1,
	}, screen)
	UI.corner(ring)
	local ringStroke = UI.stroke(ring, IDLE, 2, 0.5)
	local distanceLabel = UI.label(screen, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, 24, 0.5, 0),
		Size = UDim2.fromOffset(80, 20),
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 0.6,
		Text = "",
	})

	-- Speedometer ---------------------------------------------------------------
	local speedLabel = UI.label(screen, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -58),
		Size = UDim2.fromOffset(220, 48),
		Font = UI.Fonts.Title,
		TextSize = 44,
		TextStrokeTransparency = 0.55,
		Text = "0",
	})
	local unitLabel = UI.label(screen, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -42),
		Size = UDim2.fromOffset(220, 16),
		TextSize = 12,
		TextTransparency = 0.35,
		Text = "STUDS / SEC",
	})
	Settings.Watch("ShowSpeedometer", function(show)
		speedLabel.Visible = show
		unitLabel.Visible = show
	end)

	-- Grapple target: outline on the part, and a marker pinned to the hook point.
	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 0.85
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = false
	local markerAnchor = Instance.new("Attachment")
	markerAnchor.Parent = workspace.Terrain
	local marker = UI.new("BillboardGui", {
		Size = UDim2.fromOffset(28, 28),
		AlwaysOnTop = true,
		Adornee = markerAnchor,
		Enabled = false,
	}, screen)
	local markerRing = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.7, 0.7),
		BackgroundTransparency = 1,
	}, marker)
	UI.corner(markerRing)
	local markerStroke = UI.stroke(markerRing, IDLE, 2)
	local markerDot = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(5, 5),
		BorderSizePixel = 0,
	}, marker)
	UI.corner(markerDot)

	-- Dash charges ----------------------------------------------------------------
	local pipRow = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -28),
		Size = UDim2.fromOffset(120, 6),
		BackgroundTransparency = 1,
	}, screen)
	UI.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6),
	}, pipRow)
	local pips = {}
	for i = 1, Config.Dash.Charges do
		local pip = UI.new("Frame", { Size = UDim2.fromOffset(28, 6), BorderSizePixel = 0 }, pipRow)
		UI.corner(pip)
		pips[i] = pip
	end

	-- Shards ------------------------------------------------------------------------
	local shardLabel = UI.label(screen, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 104),
		Size = UDim2.fromOffset(160, 34),
		Font = UI.Fonts.Title,
		TextSize = 28,
		TextColor3 = UI.Colors.Gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextStrokeTransparency = 0.5,
		Text = "◆ 0",
	})
	local lastShards = nil
	local function updateShards()
		local shards = localPlayer:GetAttribute("Shards") or 0
		shardLabel.Text = "◆ " .. tostring(shards)
		if lastShards and shards > lastShards then
			UI.pop(shardLabel, 0.3)
		end
		lastShards = shards
	end
	localPlayer:GetAttributeChangedSignal("Shards"):Connect(updateShards)
	updateShards()

	-- Controls hint ---------------------------------------------------------------
	local hintText = if UserInputService.TouchEnabled
		then "HOOK to grapple  ·  SPRINT  ·  JUMP off walls  ·  SLIDE at speed  ·  DASH in the air"
		else "HOLD LMB grapple  ·  SHIFT sprint  ·  HOLD SPACE reel in  ·  CTRL slide  ·  Q dash  ·  M menu"
	local hint = UI.label(screen, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -118),
		Size = UDim2.fromOffset(700, 24),
		TextSize = 16,
		TextStrokeTransparency = 0.5,
		Text = hintText,
	})
	local hintShownAt: number? = nil
	screen:GetPropertyChangedSignal("Enabled"):Connect(function()
		if screen.Enabled and not hintShownAt then
			hintShownAt = os.clock()
			task.delay(18, function()
				UI.tween(hint, 1.5, { TextTransparency = 1, TextStrokeTransparency = 1 })
			end)
		end
	end)

	local ringSize = 22
	local shownSpeed = 0

	RunService.RenderStepped:Connect(function(dt)
		if not screen.Enabled then
			return
		end
		local info = Movement.Info
		local accent = ropeColor()

		local target = Grapple.GetAimTarget()
		local locked = target ~= nil
		ringSize = Damp(ringSize, if locked then 30 else 22, 18, dt)
		ring.Size = UDim2.fromOffset(ringSize, ringSize)
		ringStroke.Color = if locked then accent else IDLE
		ringStroke.Transparency = if locked then 0 else 0.5
		distanceLabel.TextColor3 = accent
		if target and info.Root then
			distanceLabel.Text = string.format("%d", math.floor((target.Position - info.Root.Position).Magnitude))
		else
			distanceLabel.Text = ""
		end

		-- Target highlight and hook-point marker.
		local targetPart = target and target.Instance
		local hookable = targetPart and not targetPart:IsA("Terrain") and Grapple.GetHookPosition() == nil
		highlight.Enabled = hookable == true
		if hookable then
			highlight.Adornee = targetPart
			highlight.Parent = workspace.CurrentCamera
			highlight.OutlineColor = accent
			highlight.FillColor = accent
		end
		marker.Enabled = target ~= nil and Grapple.GetHookPosition() == nil
		if target then
			markerAnchor.WorldPosition = if marker.Enabled and markerAnchor.WorldPosition.Magnitude > 0
				then markerAnchor.WorldPosition:Lerp(target.Position, math.min(dt * 25, 1))
				else target.Position
			markerStroke.Color = accent
			markerDot.BackgroundColor3 = accent
		end

		shownSpeed = Damp(shownSpeed, info.Speed, 12, dt)
		speedLabel.Text = string.format("%d", math.floor(shownSpeed + 0.5))
		local heat = math.clamp((shownSpeed - 30) / 90, 0, 1)
		speedLabel.TextColor3 = if heat < 0.5
			then Color3.new(1, 1, 1):Lerp(accent, heat * 2)
			else accent:Lerp(UI.Colors.Hot, (heat - 0.5) * 2)

		for i, pip in pips do
			pip.BackgroundColor3 = accent
			pip.BackgroundTransparency = if i <= info.DashCharges then 0 else 0.75
		end
	end)
end

return HUD

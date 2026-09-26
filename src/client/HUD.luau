-- Minimal HUD: crosshair that locks on to grapple targets, speedometer,
-- dash charges and a controls hint that fades out.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local MathUtil = require(ReplicatedStorage.Shared.MathUtil)
local Grapple = require(script.Parent.Grapple)

local Damp = MathUtil.Damp
local ROPE = Config.Grapple.RopeColor
local IDLE = Color3.fromRGB(210, 215, 225)
local HOT = Color3.fromRGB(255, 160, 70)

local HUD = {}

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local function round(parent: Instance)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, parent)
end

function HUD.Start(Movement)
	local gui = new("ScreenGui", {
		Name = "SkyboundHUD",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
	}, Players.LocalPlayer:WaitForChild("PlayerGui"))

	-- Crosshair ---------------------------------------------------------------
	local dot = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(4, 4),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, gui)
	round(dot)

	local ring = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(22, 22),
		BackgroundTransparency = 1,
	}, gui)
	round(ring)
	local ringStroke = new("UIStroke", { Thickness = 2, Color = IDLE, Transparency = 0.5 }, ring)

	local distanceLabel = new("TextLabel", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, 24, 0.5, 0),
		Size = UDim2.fromOffset(80, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = ROPE,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 0.6,
		Text = "",
	}, gui)

	-- Speedometer ---------------------------------------------------------------
	local speedLabel = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -58),
		Size = UDim2.fromOffset(220, 48),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextSize = 44,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.55,
		Text = "0",
	}, gui)
	new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -42),
		Size = UDim2.fromOffset(220, 16),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = Color3.new(1, 1, 1),
		TextTransparency = 0.35,
		Text = "STUDS / SEC",
	}, gui)

	-- Dash charges ----------------------------------------------------------------
	local pipRow = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -28),
		Size = UDim2.fromOffset(120, 6),
		BackgroundTransparency = 1,
	}, gui)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6),
	}, pipRow)
	local pips = {}
	for i = 1, Config.Dash.Charges do
		local pip =
			new("Frame", { Size = UDim2.fromOffset(28, 6), BorderSizePixel = 0, BackgroundColor3 = ROPE }, pipRow)
		round(pip)
		pips[i] = pip
	end

	-- Controls hint ---------------------------------------------------------------
	local hintText = if UserInputService.TouchEnabled
		then "HOOK to grapple  ·  JUMP off walls  ·  SLIDE at speed  ·  DASH in the air"
		else "LMB grapple (hold)  ·  SPACE wall-jump  ·  CTRL slide  ·  Q / SHIFT air dash"
	local hint = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56),
		Size = UDim2.fromOffset(640, 24),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.5,
		Text = hintText,
	}, gui)
	task.delay(20, function()
		local fade = TweenInfo.new(1.5)
		TweenService:Create(hint, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)

	local ringSize = 22
	local shownSpeed = 0

	RunService.RenderStepped:Connect(function(dt)
		local info = Movement.Info

		local target = Grapple.GetAimTarget()
		local locked = target ~= nil
		ringSize = Damp(ringSize, if locked then 30 else 22, 18, dt)
		ring.Size = UDim2.fromOffset(ringSize, ringSize)
		ringStroke.Color = if locked then ROPE else IDLE
		ringStroke.Transparency = if locked then 0 else 0.5
		if target and info.Root then
			distanceLabel.Text = string.format("%d", math.floor((target.Position - info.Root.Position).Magnitude))
		else
			distanceLabel.Text = ""
		end

		shownSpeed = Damp(shownSpeed, info.Speed, 12, dt)
		speedLabel.Text = string.format("%d", math.floor(shownSpeed + 0.5))
		local heat = math.clamp((shownSpeed - 30) / 90, 0, 1)
		speedLabel.TextColor3 = if heat < 0.5
			then Color3.new(1, 1, 1):Lerp(ROPE, heat * 2)
			else ROPE:Lerp(HOT, (heat - 0.5) * 2)

		for i, pip in pips do
			pip.BackgroundTransparency = if i <= info.DashCharges then 0 else 0.75
		end
	end)
end

return HUD

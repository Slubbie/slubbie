-- First-time tutorial: walks new players through each move with live checks.
-- Finishing (or skipping with ENTER) saves it as done and pays out shards.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Sounds = require(script.Parent.Sounds)
local UI = require(script.Parent.UI)

local Tutorial = {}

type Step = { Text: string, Touch: string?, Action: string?, Check: ((any) -> boolean)?, Timeout: number? }

local STEPS: { Step } = {
	{
		Text = "Hold SHIFT to sprint",
		Touch = "Tap SPRINT and run",
		Check = function(info)
			return info.Sprinting and info.Speed > 28
		end,
	},
	{
		Text = "Press SPACE to jump",
		Touch = "Tap JUMP",
		Check = function(info)
			return info.State == "Air"
		end,
	},
	{
		Text = "Aim at a glowing crystal and HOLD LEFT MOUSE to grapple",
		Touch = "Aim at a glowing crystal and hold HOOK",
		Action = "Grapple",
	},
	{
		Text = "Swing with WASD, then LET GO to fling yourself",
		Touch = "Let go of HOOK to fling yourself",
		Check = function(info)
			return info.State == "Air"
		end,
	},
	{ Text = "While in the air, press CTRL to dash", Touch = "Tap DASH in the air", Action = "Dash" },
	{
		Text = "Run along a wall fast to wall-run, SPACE to kick off",
		Touch = "Run along a wall fast to wall-run",
		Action = "WallRun",
		Timeout = 45,
	},
	{ Text = "While sprinting, hold C to slide", Touch = "While sprinting, hold SLIDE", Action = "Slide" },
	{
		Text = "Chain moves without touching the ground to build a COMBO",
		Action = "ComboBanked",
		Timeout = 40,
	},
}

function Tutorial.Start(Movement, Menu)
	local player = Players.LocalPlayer
	-- Wait for saved data to arrive.
	while player:GetAttribute("TutorialDone") == nil do
		task.wait(0.5)
	end
	if player:GetAttribute("TutorialDone") then
		return
	end
	while Menu.IsOpen() do
		task.wait(0.25)
	end

	local touch = UserInputService.TouchEnabled
	local gui = UI.gui("Tutorial", 6)
	local card = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 120),
		Size = UDim2.fromOffset(560, 92),
		BackgroundColor3 = UI.Colors.Panel,
		BackgroundTransparency = 0.15,
	}, gui)
	UI.corner(card, 16)
	UI.stroke(card, UI.Colors.Accent, 2, 0.3)
	local stepLabel = UI.label(card, {
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 0, 18),
		Font = UI.Fonts.Title,
		TextSize = 13,
		TextColor3 = UI.Colors.Accent,
		Text = "",
	})
	local textLabel = UI.label(card, {
		Position = UDim2.fromOffset(20, 28),
		Size = UDim2.new(1, -40, 0, 34),
		Font = UI.Fonts.Title,
		TextSize = 22,
		TextWrapped = true,
		Text = "",
	})
	UI.label(card, {
		Position = UDim2.fromOffset(0, 66),
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = 12,
		TextColor3 = UI.Colors.Muted,
		Text = if touch then "" else "ENTER to skip the tutorial",
	})

	local index = 0
	local stepStarted = 0
	local finished = false
	local connections = {}

	local function finish(skipped: boolean)
		if finished then
			return
		end
		finished = true
		for _, connection in connections do
			connection:Disconnect()
		end
		ContextActionService:UnbindAction("SkyboundSkipTutorial")
		Net.Event("CompleteTutorial"):FireServer()
		gui:Destroy()
		UI.toast(
			if skipped
				then "Tutorial skipped  ·  +25 ◆"
				else "You're ready!  ·  +25 ◆  ·  Press M for trials & the shop",
			UI.Colors.Gold
		)
	end

	local function advance()
		index += 1
		if index > #STEPS then
			finish(false)
			return
		end
		local step = STEPS[index]
		stepStarted = os.clock()
		stepLabel.Text = string.format("TUTORIAL  %d / %d", index, #STEPS)
		textLabel.Text = if touch and step.Touch then step.Touch else step.Text
		UI.pop(card, 0.15)
		if index > 1 then
			Sounds.Play(Config.Sounds.Ping, 0.4, 1.4)
		end
	end

	table.insert(
		connections,
		Movement.Action.Event:Connect(function(action: string)
			local step = STEPS[index]
			if step and step.Action == action then
				advance()
			end
		end)
	)
	table.insert(
		connections,
		Net.Event("BankCombo").OnClientEvent:Connect(function()
			local step = STEPS[index]
			if step and step.Action == "ComboBanked" then
				advance()
			end
		end)
	)
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function()
			local step = STEPS[index]
			if not step then
				return
			end
			card.Visible = Movement.Enabled
			-- Small delay so one input can't clear two steps at once.
			if os.clock() - stepStarted < 0.6 then
				return
			end
			local passed = step.Check ~= nil and step.Check(Movement.Info)
			local timedOut = step.Timeout ~= nil and os.clock() - stepStarted > step.Timeout
			if passed or timedOut then
				advance()
			end
		end)
	)
	ContextActionService:BindAction("SkyboundSkipTutorial", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			finish(true)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Return)

	advance()
end

return Tutorial

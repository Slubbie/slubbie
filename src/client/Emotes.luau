-- Emotes: an emote wheel on G (or the EMOTE button), and quick keys 1-9 / 0 for
-- the first ten. Only while standing on the ground; moving or jumping cancels.
-- Other players see them through the MoveAction relay; R6Animator does the
-- posing using EmoteLibrary.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local EmoteLibrary = require(script.Parent.EmoteLibrary)
local PhotoMode = require(script.Parent.PhotoMode)
local Sounds = require(script.Parent.Sounds)
local UI = require(script.Parent.UI)

local KEYS = {
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.Five,
	Enum.KeyCode.Six,
	Enum.KeyCode.Seven,
	Enum.KeyCode.Eight,
	Enum.KeyCode.Nine,
	Enum.KeyCode.Zero,
}
local WHEEL_RADIUS = 225
local SLOT_SIZE = 78

local Emotes = {}

-- The emote we're currently doing, read by R6Animator: { Name, Start } or nil.
Emotes.Current = nil :: { Name: string, Start: number }?
Emotes.WheelOpen = false

function Emotes.Start(Movement)
	local remote = Net.Event("MoveAction")

	local function stop()
		if Emotes.Current then
			Emotes.Current = nil
			Movement.SetFacing(nil)
			remote:FireServer("Emote_Stop")
		end
	end

	local function canEmote(): boolean
		local info = Movement.Info
		return info.State == "Ground" and info.Speed < 3
	end

	local function play(name: string)
		if not canEmote() then
			UI.toast("Stand still on the ground to emote", UI.Colors.Muted)
			return
		end
		if Emotes.Current and Emotes.Current.Name == name then
			stop()
			return
		end
		Emotes.Current = { Name = name, Start = os.clock() }
		remote:FireServer("Emote_" .. name)
		-- Turn to face the camera so you can see your emote.
		local root = Movement.Info.Root
		if root then
			Movement.SetFacing(workspace.CurrentCamera.CFrame.Position - root.Position)
		end
	end

	-- Wheel ------------------------------------------------------------------------
	local gui = UI.gui("EmoteWheel", 12)
	gui.Enabled = false
	UI.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
	}, gui)
	local center = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(150, 150),
		BackgroundColor3 = UI.Colors.Panel,
		BackgroundTransparency = 0.1,
	}, gui)
	UI.corner(center)
	UI.stroke(center, UI.Colors.Accent, 2, 0.3)
	local centerTitle = UI.label(center, {
		Size = UDim2.fromScale(1, 0.55),
		Font = UI.Fonts.Title,
		TextSize = 22,
		Text = "EMOTES",
	})
	UI.label(center, {
		Position = UDim2.fromScale(0, 0.52),
		Size = UDim2.fromScale(1, 0.3),
		TextSize = 12,
		TextColor3 = UI.Colors.Muted,
		Text = "G to close",
	})

	local closeWheel
	for index, name in Config.Emotes do
		local emote = EmoteLibrary.Get(name)
		if emote then
			local angle = (index - 1) / #Config.Emotes * math.pi * 2 - math.pi / 2
			local slot = UI.button(gui, emote.Icon, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, math.cos(angle) * WHEEL_RADIUS, 0.5, math.sin(angle) * WHEEL_RADIUS),
				Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE),
				TextSize = 34,
				BackgroundColor3 = UI.Colors.Panel,
				BackgroundTransparency = 0.1,
			})
			UI.corner(slot)
			UI.label(slot, {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 1, 2),
				Size = UDim2.fromOffset(100, 16),
				TextSize = 13,
				TextStrokeTransparency = 0.5,
				Text = string.upper(if name == "AirGuitar" then "Air Guitar" else name),
			})
			if index <= #KEYS then
				UI.label(slot, {
					Position = UDim2.fromOffset(6, 4),
					Size = UDim2.fromOffset(16, 14),
					TextSize = 12,
					TextColor3 = UI.Colors.Muted,
					Text = tostring(index % 10),
				})
			end
			slot.MouseEnter:Connect(function()
				centerTitle.Text = string.upper(name)
			end)
			slot.Activated:Connect(function()
				Sounds.Play(Config.Sounds.Ping, 0.25, 2)
				closeWheel()
				play(name)
			end)
		end
	end

	local function openWheel()
		if Emotes.WheelOpen or not Movement.Enabled then
			return
		end
		Emotes.WheelOpen = true
		gui.Enabled = true
		centerTitle.Text = "EMOTES"
		Movement.SetEnabled(false)
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		UI.pop(center, 0.2)
	end
	function closeWheel()
		if not Emotes.WheelOpen then
			return
		end
		Emotes.WheelOpen = false
		gui.Enabled = false
		Movement.SetEnabled(true)
	end

	ContextActionService:BindAction("SkyboundEmoteWheel", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			if Emotes.WheelOpen then
				closeWheel()
			else
				openWheel()
			end
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.G, Enum.KeyCode.DPadUp)
	ContextActionService:SetTitle("SkyboundEmoteWheel", "Emote")
	ContextActionService:SetPosition("SkyboundEmoteWheel", UDim2.new(1, -290, 1, -195))

	-- Quick keys.
	for index, key in KEYS do
		local name = Config.Emotes[index]
		if name then
			ContextActionService:BindAction("SkyboundEmote" .. name, function(_, inputState)
				if inputState ~= Enum.UserInputState.Begin or not Movement.Enabled then
					return Enum.ContextActionResult.Pass
				end
				play(name)
				return Enum.ContextActionResult.Sink
			end, false, key)
		end
	end

	RunService.Heartbeat:Connect(function()
		local current = Emotes.Current
		if not current then
			return
		end
		local info = Movement.Info
		local humanoid = info.Humanoid
		local moving = humanoid and humanoid.MoveDirection.Magnitude > 0.1
		local emote = EmoteLibrary.Get(current.Name)
		local finished = emote and not emote.Loop and os.clock() - current.Start > emote.Length
		if
			moving
			or info.State ~= "Ground"
			or finished
			or (not Movement.Enabled and not Emotes.WheelOpen and not PhotoMode.Active)
		then
			stop()
		end
	end)
end

return Emotes

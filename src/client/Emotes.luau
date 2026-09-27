-- Emotes on keys 1-4 (wave, dance, flex, sit). Only while standing still; moving
-- or jumping cancels. Other players see them through the MoveAction relay, and
-- R6Animator does the posing.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }

local Emotes = {}

-- The emote we're currently doing, read by R6Animator: { Name, Start } or nil.
Emotes.Current = nil :: { Name: string, Start: number }?

function Emotes.Start(Movement)
	local remote = Net.Event("MoveAction")

	local function stop()
		if Emotes.Current then
			Emotes.Current = nil
			remote:FireServer("Emote_Stop")
		end
	end

	for index, key in KEYS do
		local name = Config.Emotes[index]
		if name then
			ContextActionService:BindAction("SkyboundEmote" .. name, function(_, inputState)
				if inputState ~= Enum.UserInputState.Begin then
					return Enum.ContextActionResult.Pass
				end
				if not Movement.Enabled or Movement.Info.State ~= "Ground" or Movement.Info.Speed > 3 then
					return Enum.ContextActionResult.Pass
				end
				if Emotes.Current and Emotes.Current.Name == name then
					stop()
				else
					Emotes.Current = { Name = name, Start = os.clock() }
					remote:FireServer("Emote_" .. name)
				end
				return Enum.ContextActionResult.Sink
			end, false, key)
		end
	end

	RunService.Heartbeat:Connect(function()
		if not Emotes.Current then
			return
		end
		local info = Movement.Info
		local humanoid = info.Humanoid
		local moving = humanoid and humanoid.MoveDirection.Magnitude > 0.1
		if moving or info.State ~= "Ground" or not Movement.Enabled then
			stop()
		end
	end)
end

return Emotes

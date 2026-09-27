-- Sound design: wind that roars with speed, wall-run footsteps, and a sound for
-- every move. Sound IDs live in Config.Sounds so they're easy to swap.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)
local MathUtil = require(ReplicatedStorage.Shared.MathUtil)
local Grapple = require(script.Parent.Grapple)
local Settings = require(script.Parent.Settings)

local SOUNDS = Config.Sounds

local Sounds = {}

-- Volume groups so the settings sliders control everything at once.
local effectsGroup = Instance.new("SoundGroup")
effectsGroup.Name = "Effects"
effectsGroup.Parent = SoundService
local windGroup = Instance.new("SoundGroup")
windGroup.Name = "Wind"
windGroup.Parent = SoundService

local function makeSound(id: string, props: { [string]: any }?): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.SoundGroup = effectsGroup
	for key, value in props or {} do
		(sound :: any)[key] = value
	end
	sound.Parent = SoundService
	return sound
end

-- Plays a one-shot copy so overlapping sounds don't cut each other off.
function Sounds.Play(id: string, volume: number?, pitch: number?)
	local sound = makeSound(id, { Volume = volume or 0.5, PlaybackSpeed = pitch or 1 })
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	sound:Play()
	task.delay(6, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

local function jitter(pitch: number): number
	return pitch * (0.93 + math.random() * 0.14)
end

function Sounds.Start(Movement)
	local wind = makeSound(SOUNDS.Wind, { Looped = true, Volume = 0, SoundGroup = windGroup })
	Settings.Watch("EffectsVolume", function(value)
		effectsGroup.Volume = value
	end)
	Settings.Watch("WindVolume", function(value)
		windGroup.Volume = value
	end)
	local steps = makeSound(SOUNDS.Footsteps, { Looped = true, Volume = 0, PlaybackSpeed = 1.6 })
	wind:Play()
	steps:Play()

	local actionSounds = {
		Dash = function()
			Sounds.Play(SOUNDS.Whoosh, 0.7, jitter(0.8))
		end,
		WallJump = function()
			Sounds.Play(SOUNDS.Jump, 0.5, jitter(1.2))
			Sounds.Play(SOUNDS.Whoosh, 0.35, jitter(1.3))
		end,
		Launch = function()
			Sounds.Play(SOUNDS.Whoosh, 0.8, 0.6)
			Sounds.Play(SOUNDS.Jump, 0.6, 0.8)
		end,
		Slingshot = function()
			Sounds.Play(SOUNDS.Whoosh, 0.7, 1.5)
		end,
		Roll = function()
			Sounds.Play(SOUNDS.Land, 0.7, 0.8)
		end,
		HardLand = function()
			Sounds.Play(SOUNDS.Land, 0.8, 0.7)
		end,
		BunnyHop = function()
			Sounds.Play(SOUNDS.Jump, 0.4, jitter(1.4))
		end,
		SlideJump = function()
			Sounds.Play(SOUNDS.Jump, 0.5, jitter(1.1))
		end,
		Slide = function()
			Sounds.Play(SOUNDS.Whoosh, 0.3, 0.5)
		end,
	}
	Movement.Action.Event:Connect(function(action: string)
		local play = actionSounds[action]
		if play then
			play()
		end
	end)
	Movement.Landed.Event:Connect(function(impact: number)
		if impact > 25 and impact <= Config.Movement.HardLandingSpeed then
			Sounds.Play(SOUNDS.Land, math.clamp(impact / 120, 0.15, 0.5), jitter(1))
		end
	end)

	Grapple.Fired.Event:Connect(function()
		Sounds.Play(SOUNDS.Whoosh, 0.45, jitter(1.8))
	end)
	Grapple.Attached.Event:Connect(function()
		Sounds.Play(SOUNDS.Land, 0.55, jitter(1.7))
	end)

	-- Shard chime when *we* pick one up.
	local localPlayer = Players.LocalPlayer
	local function watchShard(part: Instance)
		part:GetAttributeChangedSignal("Collected"):Connect(function()
			if part:GetAttribute("Collected") and part:GetAttribute("CollectedBy") == localPlayer.UserId then
				Sounds.Play(SOUNDS.Ping, 0.5, 1.2 + math.random() * 0.3)
			end
		end)
	end
	local CollectionService = game:GetService("CollectionService")
	for _, part in CollectionService:GetTagged("Shard") do
		watchShard(part)
	end
	CollectionService:GetInstanceAddedSignal("Shard"):Connect(watchShard)

	RunService.RenderStepped:Connect(function(dt)
		local info = Movement.Info
		local speed = info.Velocity.Magnitude
		local airborne = info.State ~= "Ground" and info.State ~= "Slide"
		local windTarget = math.clamp((speed - 25) / 130, 0, 1) * (if airborne then 0.9 else 0.45)
		wind.Volume = MathUtil.Damp(wind.Volume, windTarget, 6, dt)
		wind.PlaybackSpeed = 0.7 + math.clamp(speed / 150, 0, 1) * 0.9
		steps.Volume = MathUtil.Damp(steps.Volume, if info.State == "WallRun" then 0.6 else 0, 20, dt)
	end)
end

return Sounds

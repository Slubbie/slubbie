-- Sound effects: material-aware footsteps for every runner, movement cues,
-- wind that rises with speed, ability-ready and stamina cues, and UI tones.
--
-- Every sound ships with the Roblox client (Config/Sounds), shaped per
-- surface with pitch and an equaliser, routed through sound groups that the
-- volume settings control.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)
local Tags = require(ReplicatedStorage.Shared.Tags)

local Settings = require(script.Parent.Parent.Core.Settings)
local Controller = require(script.Parent.Parent.Movement.Controller)
local Stamina = require(script.Parent.Parent.Movement.Stamina)
local Animator = require(script.Parent.Parent.Animation.Animator)

local player = Players.LocalPlayer

local Sfx = {}

local groups: { [string]: SoundGroup } = {}
local GROUP_SETTING = { Sfx = "SfxVolume", Music = "MusicVolume", Ambient = "AmbientVolume", Cues = "CueVolume" }

local function group(name: string): SoundGroup
	local existing = groups[name]
	if existing then
		return existing
	end
	local g = Instance.new("SoundGroup")
	g.Name = "Skyline" .. name
	g.Parent = SoundService
	groups[name] = g
	return g
end

function Sfx.Group(name: string): SoundGroup
	return group(name)
end

local function applyVolumes()
	local master = Settings.Get("MasterVolume") or 1
	for name, setting in GROUP_SETTING do
		group(name).Volume = master * (Settings.Get(setting) or 1)
	end
end

-- Pools ------------------------------------------------------------------------------------------

type Pool = { Sounds: { Sound }, Index: number }
local pools: { [string]: Pool } = {}
local holder = Instance.new("Folder")
holder.Name = "SkylineSfx"

local function pool(key: string, id: string, size: number, groupName: string, configure: ((Sound) -> ())?): Pool
	local existing = pools[key]
	if existing then
		return existing
	end
	local list = {}
	for i = 1, size do
		local sound = Instance.new("Sound")
		sound.Name = key .. i
		sound.SoundId = id
		sound.SoundGroup = group(groupName)
		if configure then
			configure(sound)
		end
		sound.Parent = holder
		list[i] = sound
	end
	local p = { Sounds = list, Index = 0 }
	pools[key] = p
	return p
end

local function nextSound(p: Pool): Sound
	p.Index = p.Index % #p.Sounds + 1
	return p.Sounds[p.Index]
end

export type PlayOptions = { Volume: number?, Pitch: number?, Parent: Instance?, Group: string?, Spread: number? }

-- Play a named sound from Config/Sounds. 2D unless `Parent` is a part.
function Sfx.Play(name: string, options: PlayOptions?)
	local id = (Sounds :: any)[name]
	if type(id) ~= "string" then
		return
	end
	local opts = options or {}
	local groupName = opts.Group or "Sfx"
	local p = pool(name .. ":" .. groupName, id, 6, groupName)
	local sound = nextSound(p)
	local spread = opts.Spread or 0.06
	sound.Volume = opts.Volume or 0.5
	sound.PlaybackSpeed = (opts.Pitch or 1) * (1 + (math.random() * 2 - 1) * spread)
	sound.Parent = opts.Parent or holder
	sound.TimePosition = 0
	sound:Play()
end

-- A pitched tone (semitones from the base ping), for cues and stingers.
function Sfx.Tone(semitones: number, volume: number?, delay: number?, groupName: string?)
	local function play()
		Sfx.Play("Tone", { Pitch = 2 ^ (semitones / 12), Volume = volume or 0.35, Group = groupName or "Cues", Spread = 0 })
	end
	if delay and delay > 0 then
		task.delay(delay, play)
	else
		play()
	end
end

-- Short melodic stingers.
local STINGERS: { [string]: { { number } } } = {
	Checkpoint = { { 0, 0 }, { 7, 0.07 } },
	Token = { { 12, 0 } },
	Medal = { { 0, 0 }, { 4, 0.1 }, { 7, 0.2 }, { 12, 0.32 } },
	Platinum = { { 0, 0 }, { 4, 0.08 }, { 7, 0.16 }, { 11, 0.24 }, { 14, 0.32 }, { 19, 0.44 } },
	LevelUp = { { 0, 0 }, { 5, 0.09 }, { 9, 0.18 }, { 12, 0.27 }, { 17, 0.4 } },
	Quest = { { 7, 0 }, { 12, 0.12 } },
	Unlock = { { 0, 0 }, { 7, 0.1 }, { 12, 0.2 }, { 19, 0.3 } },
	Error = { { -5, 0 }, { -8, 0.1 } },
	Discover = { { 9, 0 }, { 14, 0.1 }, { 21, 0.2 } },
	Countdown = { { 0, 0 } },
	Go = { { 12, 0 }, { 19, 0.05 } },
	Ready = { { 14, 0 } },
	Open = { { 5, 0 } },
	Close = { { 0, 0 } },
	Hover = { { 19, 0 } },
}

function Sfx.Stinger(name: string, volume: number?)
	local notes = STINGERS[name]
	if not notes then
		return
	end
	for _, note in notes do
		Sfx.Tone(note[1], volume, note[2])
	end
end

-- Footsteps --------------------------------------------------------------------------------------

local stepParams = RaycastParams.new()
stepParams.FilterType = Enum.RaycastFilterType.Exclude
stepParams.CollisionGroup = Tags.Groups.Players
stepParams.RespectCanCollide = true

local function surfaceFor(material: Enum.Material?): { [string]: any }
	local name = if material then material.Name else "Default"
	return (Sounds.Surfaces :: any)[name] or Sounds.Surfaces.Default
end

local function footPool(surfaceName: string, surface: { [string]: any }): Pool
	return pool("Step:" .. surfaceName, Sounds.Footstep, 8, "Sfx", function(sound)
		local eq = Instance.new("EqualizerSoundEffect")
		eq.LowGain = surface.Low or 0
		eq.MidGain = 0
		eq.HighGain = surface.High or 0
		eq.Parent = sound
		sound.RollOffMaxDistance = 90
		sound.RollOffMinDistance = 6
	end)
end

local function footstep(model: Model, side: number, speed: number)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local isLocal = model == player.Character
	local material: Enum.Material? = nil
	if isLocal then
		material = Controller.Info.FloorMaterial
		if material == Enum.Material.Air then
			material = nil
		end
	end
	if not material then
		local camera = workspace.CurrentCamera
		if not isLocal and camera and (camera.CFrame.Position - root.Position).Magnitude > 110 then
			return
		end
		stepParams.FilterDescendantsInstances = { model }
		local hit = workspace:Raycast(root.Position, Vector3.new(0, -4.5, 0), stepParams)
		if not hit then
			return
		end
		material = hit.Material
	end
	local surface = surfaceFor(material)
	local name = if material then material.Name else "Default"
	local p = footPool(name, surface)
	local sound = nextSound(p)
	local pace = math.clamp(speed / 28, 0.4, 1.3)
	sound.Volume = (surface.Volume or 0.45) * (0.55 + 0.45 * pace) * (if isLocal then 1 else 0.8)
	sound.PlaybackSpeed = (surface.Pitch or 1) * (0.94 + math.random() * 0.12) * (if side > 0 then 1 else 0.97)
	sound.Parent = root
	sound.TimePosition = 0
	sound:Play()
	if surface.Splash and math.random() < 0.6 then
		Sfx.Play("Splash", { Volume = 0.2, Pitch = 1.4, Parent = root })
	end
end

-- Loops ------------------------------------------------------------------------------------------

local windLoop: Sound? = nil
local slideLoop: Sound? = nil
local zipLoop: Sound? = nil
local ambience: Sound? = nil

local function loop(id: string, groupName: string): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Looped = true
	sound.Volume = 0
	sound.SoundGroup = group(groupName)
	sound.Parent = holder
	sound:Play()
	return sound
end

local function updateLoops(dt: number)
	local info = Controller.Info
	local speed = info.Velocity.Magnitude
	local wind = windLoop
	if wind then
		local target = math.clamp((speed - 30) / 90, 0, 1) * 0.5
		if info.State == "Air" and info.Velocity.Y < -60 then
			target = math.max(target, math.clamp((-info.Velocity.Y - 60) / 120, 0, 0.6))
		end
		wind.Volume += (target - wind.Volume) * math.min(dt * 4, 1)
		wind.PlaybackSpeed = 0.8 + math.clamp(speed / 160, 0, 0.6)
	end
	local slide = slideLoop
	if slide then
		local target = if info.State == "Slide" then 0.32 else 0
		slide.Volume += (target - slide.Volume) * math.min(dt * 12, 1)
		slide.PlaybackSpeed = 0.55 + math.clamp(info.Speed / 80, 0, 0.4)
	end
	local zip = zipLoop
	if zip then
		local target = if info.State == "Zipline" then 0.35 else 0
		zip.Volume += (target - zip.Volume) * math.min(dt * 10, 1)
		zip.PlaybackSpeed = 1.3 + math.clamp(speed / 90, 0, 0.8)
	end
end

-- District ambience tone (wind pitch and level per district).
local AMBIENCE = {
	Plaza = { Volume = 0.08, Pitch = 0.7 },
	Rooftops = { Volume = 0.1, Pitch = 0.75 },
	Industrial = { Volume = 0.12, Pitch = 0.55 },
	Forest = { Volume = 0.07, Pitch = 0.9 },
	City = { Volume = 0.1, Pitch = 0.65 },
	Wind = { Volume = 0.22, Pitch = 0.6 },
	Aether = { Volume = 0.16, Pitch = 0.95 },
}

function Sfx.SetAmbience(kind: string?)
	local sound = ambience
	if not sound then
		return
	end
	local entry = AMBIENCE[kind or ""] or AMBIENCE.Plaza
	sound:SetAttribute("Target", entry.Volume)
	sound.PlaybackSpeed = entry.Pitch
end

-- Hooks ------------------------------------------------------------------------------------------

local ACTION_SOUNDS: { [string]: { Name: string, Volume: number, Pitch: number } } = {
	Jump = { Name = "Jump", Volume = 0.22, Pitch = 1.05 },
	DoubleJump = { Name = "Swoosh", Volume = 0.4, Pitch = 1.35 },
	WallJump = { Name = "Jump", Volume = 0.35, Pitch = 1.2 },
	WallKick = { Name = "Jump", Volume = 0.3, Pitch = 1.1 },
	SlideJump = { Name = "Swoosh", Volume = 0.3, Pitch = 1.1 },
	Dash = { Name = "Swoosh", Volume = 0.5, Pitch = 1.6 },
	Vault = { Name = "Swoosh", Volume = 0.25, Pitch = 0.9 },
	Mantle = { Name = "GetUp", Volume = 0.25, Pitch = 1.3 },
	LedgeGrab = { Name = "Land", Volume = 0.3, Pitch = 1.5 },
	LedgeLeap = { Name = "Swoosh", Volume = 0.35, Pitch = 1.2 },
	Grapple = { Name = "Ping", Volume = 0.35, Pitch = 0.6 },
	GrappleRelease = { Name = "Swoosh", Volume = 0.45, Pitch = 1 },
	Pull = { Name = "Ping", Volume = 0.35, Pitch = 0.5 },
	RopeSwing = { Name = "Swoosh", Volume = 0.3, Pitch = 0.8 },
	ZiplineStart = { Name = "Ping", Volume = 0.25, Pitch = 1.8 },
	Bounce = { Name = "Jump", Volume = 0.5, Pitch = 0.7 },
	Launch = { Name = "Swoosh", Volume = 0.5, Pitch = 0.7 },
	Roll = { Name = "Swoosh", Volume = 0.35, Pitch = 0.75 },
	Stumble = { Name = "GetUp", Volume = 0.3, Pitch = 0.9 },
	Knocked = { Name = "Land", Volume = 0.5, Pitch = 0.8 },
	ClimbStart = { Name = "Land", Volume = 0.2, Pitch = 1.6 },
	BalanceCatch = { Name = "Swoosh", Volume = 0.25, Pitch = 1.4 },
	PrecisionLand = { Name = "Ping", Volume = 0.2, Pitch = 1.5 },
}

function Sfx.Start()
	holder.Parent = SoundService
	applyVolumes()
	Settings.Changed:Connect(applyVolumes)
	windLoop = loop(Sounds.Wind, "Sfx")
	slideLoop = loop(Sounds.Swim, "Sfx")
	zipLoop = loop(Sounds.Wind, "Sfx")
	ambience = loop(Sounds.Wind, "Ambient")
	Sfx.SetAmbience("Plaza")

	Animator.Footstep:Connect(footstep)
	Controller.Action:Connect(function(action: string)
		local entry = ACTION_SOUNDS[action]
		if entry then
			Sfx.Play(entry.Name, { Volume = entry.Volume, Pitch = entry.Pitch })
		end
		if action == "WallRunStart" then
			Sfx.Play("Footstep", { Volume = 0.3, Pitch = 1.3 })
		end
	end)
	Controller.Landed:Connect(function(impact: number, kind: string)
		local volume = math.clamp(impact / 120, 0.12, 0.7)
		local pitch = if kind == "Heavy" then 0.75 elseif kind == "Hard" then 0.85 else 1
		Sfx.Play("Land", { Volume = volume, Pitch = pitch })
		if kind == "Precision" then
			Sfx.Tone(19, 0.18)
		end
	end)
	-- Resource feedback: can't afford, ran dry, refilled, dash recharged.
	Stamina.Denied:Connect(function()
		Sfx.Tone(-7, 0.25)
	end)
	Stamina.Emptied:Connect(function()
		Sfx.Tone(-12, 0.3)
		Sfx.Tone(-15, 0.25, 0.09)
	end)
	Stamina.Refilled:Connect(function()
		Sfx.Tone(14, 0.12)
	end)
	local lastCharges = 0
	RunService.Heartbeat:Connect(function(dt)
		updateLoops(dt)
		local sound = ambience
		if sound then
			local target = sound:GetAttribute("Target")
			if type(target) == "number" then
				sound.Volume += (target - sound.Volume) * math.min(dt, 1)
			end
		end
		local charges = Controller.Info.DashCharges
		if Controller.Info.DashReady >= 1 and charges > lastCharges and lastCharges >= 0 then
			Sfx.Tone(17, 0.14)
		end
		lastCharges = if Controller.Info.DashReady >= 1 then charges else -1
	end)
end

return Sfx

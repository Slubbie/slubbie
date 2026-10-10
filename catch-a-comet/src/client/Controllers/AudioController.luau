-- Sound: UI feedback, 3D world sounds, rarity fanfares, and the ambience
-- (wind plus soft generative chimes; optional music tracks from GameConfig).
-- Three volume groups — Music, Effects, Ambient — follow the player's settings.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)

local AudioController = {}

local SOUNDS = GameConfig.Audio.Sounds
local PENTATONIC = { 0, 2, 4, 7, 9, 12, 14, 16, 19 }

local groups: { [string]: SoundGroup } = {}
local pools: { [string]: { Sound } } = {}
local emitterPool: { BasePart } = {}
local ambienceArea = "Hub"
local controllers: { [string]: any } = {}

local function group(name: string): SoundGroup
	local existing = groups[name]
	if existing then
		return existing
	end
	local g = Instance.new("SoundGroup")
	g.Name = "CatchAComet" .. name
	g.Volume = 0.7
	g.Parent = SoundService
	groups[name] = g
	return g
end

local function pooled(name: string, groupName: string): Sound?
	local def = SOUNDS[name]
	if not def then
		return nil
	end
	local pool = pools[name]
	if not pool then
		pool = {}
		pools[name] = pool
	end
	for _, sound in pool do
		if not sound.IsPlaying then
			return sound
		end
	end
	if #pool >= 6 then
		return pool[1]
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = def.Id
	sound.SoundGroup = group(groupName)
	sound.Parent = SoundService
	table.insert(pool, sound)
	return sound
end

export type PlayOptions = { Pitch: number?, Volume: number?, Group: string? }

-- Plays a 2D sound (UI, stingers).
function AudioController.Play(name: string, options: PlayOptions?)
	local def = SOUNDS[name]
	local sound = pooled(name, options and options.Group or "Effects")
	if not def or not sound then
		return
	end
	sound.PlaybackSpeed = (options and options.Pitch) or def.Pitch
	sound.Volume = def.Volume * ((options and options.Volume) or 1)
	sound.TimePosition = 0
	sound:Play()
end

-- Plays a sound in the world at a position.
function AudioController.PlayAt(name: string, position: Vector3, options: PlayOptions?)
	local def = SOUNDS[name]
	if not def then
		return
	end
	local emitter: BasePart? = nil
	for _, part in emitterPool do
		local sound = part:FindFirstChildOfClass("Sound")
		if sound and not sound.IsPlaying then
			emitter = part
			break
		end
	end
	if not emitter then
		if #emitterPool >= 10 then
			emitter = emitterPool[1]
		else
			local part = Instance.new("Part")
			part.Name = "SoundEmitter"
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Transparency = 1
			part.Size = Vector3.new(0.2, 0.2, 0.2)
			local sound = Instance.new("Sound")
			sound.RollOffMode = Enum.RollOffMode.InverseTapered
			sound.RollOffMinDistance = 12
			sound.RollOffMaxDistance = 260
			sound.SoundGroup = group("Effects")
			sound.Parent = part
			part.Parent = workspace
			table.insert(emitterPool, part)
			emitter = part
		end
	end
	assert(emitter)
	emitter.Position = position
	local sound = emitter:FindFirstChildOfClass("Sound") :: Sound
	sound.SoundId = def.Id
	sound.PlaybackSpeed = (options and options.Pitch) or def.Pitch
	sound.Volume = def.Volume * ((options and options.Volume) or 1)
	sound.TimePosition = 0
	sound:Play()
end

-- A rising arpeggio for discoveries; longer and brighter for rarer finds.
function AudioController.Fanfare(tier: number)
	local notes = math.clamp(2 + tier, 3, 7)
	local base = 0.9 + tier * 0.05
	task.spawn(function()
		for i = 1, notes do
			local semitone = PENTATONIC[math.min(i + tier - 1, #PENTATONIC)]
			AudioController.Play("Chime", { Pitch = base * 2 ^ (semitone / 12), Volume = 1 + tier * 0.15 })
			task.wait(0.09 - tier * 0.008)
		end
	end)
end

function AudioController.Click()
	AudioController.Play("UIClick")
end

function AudioController.SetVolumes(settings: { [string]: any })
	group("Music").Volume = settings.MusicVolume or 0.7
	group("Effects").Volume = settings.EffectsVolume or 0.8
	group("Ambient").Volume = settings.AmbientVolume or 0.6
end

function AudioController.SetArea(area: string)
	ambienceArea = area
end

local function startAmbience()
	local wind = Instance.new("Sound")
	wind.Name = "Wind"
	wind.SoundId = SOUNDS.Wind.Id
	wind.Looped = true
	wind.Volume = SOUNDS.Wind.Volume
	wind.PlaybackSpeed = SOUNDS.Wind.Pitch
	wind.SoundGroup = group("Ambient")
	wind.Parent = SoundService
	wind:Play()

	-- Soft pentatonic chimes drifting in the background.
	task.spawn(function()
		local rng = Random.new()
		while true do
			task.wait(2.5 + rng:NextNumber() * 4)
			local tracks = GameConfig.Audio.Music[ambienceArea]
			if tracks and #tracks > 0 then
				continue
			end
			local root = if ambienceArea == "DawnCommons" then 1.05 elseif ambienceArea == "Sanctuary" then 0.95 else 1
			local count = rng:NextInteger(1, 3)
			for _ = 1, count do
				local semitone = PENTATONIC[rng:NextInteger(1, 6)]
				AudioController.Play("Chime", { Pitch = root * 2 ^ (semitone / 12), Volume = 0.35, Group = "Ambient" })
				task.wait(0.25 + rng:NextNumber() * 0.4)
			end
		end
	end)

	-- Optional real music, per area.
	task.spawn(function()
		local music = Instance.new("Sound")
		music.Name = "Music"
		music.SoundGroup = group("Music")
		music.Parent = SoundService
		local playingArea: string? = nil
		while true do
			task.wait(1)
			local tracks = GameConfig.Audio.Music[ambienceArea]
			if tracks and #tracks > 0 then
				if playingArea ~= ambienceArea or not music.IsPlaying then
					playingArea = ambienceArea
					local track = tracks[math.random(1, #tracks)]
					music.SoundId = track.Id
					music.Volume = track.Volume or 0.5
					music:Play()
				end
			elseif music.IsPlaying then
				music:Stop()
				playingArea = nil
			end
		end
	end)
end

function AudioController.Init(registry: { [string]: any })
	controllers = registry
end

function AudioController.Start()
	local ClientState = controllers.ClientState
	ClientState.Observe("Settings", function(settings)
		AudioController.SetVolumes(settings or {})
	end)
	controllers.Components.OnClick = AudioController.Click
	startAmbience()
end

return AudioController

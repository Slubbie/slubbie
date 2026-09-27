-- Soundtrack.
--
-- If Config.Music.Playlist has track IDs, those play shuffled with crossfades.
-- Otherwise a generative score is composed live from pitched built-in sounds:
-- a bassline, chord arpeggios and sparkling melody notes on a pentatonic scale
-- (so nothing ever clashes). It speeds up and adds drums the faster you move,
-- calms down in menus, and turns minor and moody at night.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local MathUtil = require(ReplicatedStorage.Shared.MathUtil)
local Settings = require(script.Parent.Settings)
local UI = require(script.Parent.UI)

local MUSIC = Config.Music
local POOL_SIZE = 24

local Music = {}

local group = Instance.new("SoundGroup")
group.Name = "Music"
group.Parent = SoundService

local function applyVolume()
	group.Volume = if Settings.Get("MusicEnabled") then Settings.Get("MusicVolume") else 0
end

-- Playlist mode ------------------------------------------------------------------

local function playPlaylist(tracks)
	local order = table.clone(tracks)
	local rng = Random.new()
	for i = #order, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	local index = 0
	local current: Sound? = nil

	local function playNext()
		index = index % #order + 1
		local track = order[index]
		local sound = Instance.new("Sound")
		sound.SoundId = track.Id
		sound.Volume = 0
		sound.SoundGroup = group
		sound.Parent = SoundService
		local previous = current
		current = sound
		sound:Play()
		TweenService:Create(sound, TweenInfo.new(3), { Volume = track.Volume or 0.6 }):Play()
		if previous then
			local fade = TweenService:Create(previous, TweenInfo.new(3), { Volume = 0 })
			fade:Play()
			fade.Completed:Connect(function()
				previous:Destroy()
			end)
		end
		if track.Name then
			UI.toast("♪  " .. track.Name, UI.Colors.Muted)
		end
		sound.Ended:Connect(function()
			if current == sound then
				playNext()
			end
		end)
	end
	playNext()
end

-- Generative mode ----------------------------------------------------------------

local MAJOR = { 0, 2, 4, 7, 9 }
local MINOR = { 0, 3, 5, 7, 10 }
local DAY_CHORDS = { 0, -3, 5, 7 } -- I  vi  IV  V
local NIGHT_CHORDS = { 0, -4, -2, 5 } -- i  VI  VII  iv

local function playGenerative(Movement)
	local pool: { Sound } = {}
	local nextVoice = 1
	for i = 1, POOL_SIZE do
		local sound = Instance.new("Sound")
		sound.SoundGroup = group
		sound.Parent = SoundService
		pool[i] = sound
	end

	local function note(soundId: string, semitones: number, volume: number)
		local voice = pool[nextVoice]
		nextVoice = nextVoice % POOL_SIZE + 1
		voice:Stop()
		voice.SoundId = soundId
		voice.PlaybackSpeed = 2 ^ (semitones / 12)
		voice.Volume = volume
		voice:Play()
	end

	local rng = Random.new()
	local key = MUSIC.Key
	local step = 0
	local bar = 0
	local clock = 0
	local intensity = 0
	local melody = 0

	RunService.Heartbeat:Connect(function(dt)
		if group.Volume <= 0 then
			return
		end
		local speed = if Movement.Enabled then Movement.Info.Velocity.Magnitude else 0
		intensity = MathUtil.Damp(intensity, math.clamp(speed / 120, 0, 1), 0.8, dt)
		local bpm = MUSIC.BaseTempo + intensity * MUSIC.TempoBoost
		local stepLength = 60 / bpm / 2 -- eighth notes

		clock += dt
		while clock >= stepLength do
			clock -= stepLength
			local night = Settings.Get("TimeOfDay") == "Night"
			local scale = if night then MINOR else MAJOR
			local chords = if night then NIGHT_CHORDS else DAY_CHORDS
			local root = key + chords[bar % #chords + 1]
			local tones = { 0, scale[3], 7, 12 }

			-- Bass on the downbeats.
			if step == 0 or step == 4 then
				note(MUSIC.Tone, root - 24, 0.45)
			end
			-- Arpeggio: every eighth when moving fast, every quarter when calm.
			if intensity > 0.3 or step % 2 == 0 then
				local tone = tones[step % 4 + 1] + (if step >= 4 then 12 else 0)
				note(MUSIC.Tone, root + tone - 12, 0.2 + intensity * 0.1)
			end
			-- Melody: a gentle random walk up and down the scale.
			if rng:NextNumber() < 0.18 + intensity * 0.3 then
				melody = math.clamp(melody + rng:NextInteger(-2, 2), 0, #scale * 2 - 1)
				local octave = math.floor(melody / #scale)
				local degree = scale[melody % #scale + 1]
				note(MUSIC.Tone, key + degree + octave * 12 + 12, 0.14)
			end
			-- Drums join in at speed.
			if intensity > 0.45 then
				if step == 0 or step == 4 then
					note(MUSIC.Kick, -8, 0.35 * intensity)
				elseif step % 2 == 1 then
					note(MUSIC.Hat, 26, 0.05 * intensity)
				end
			end

			step = (step + 1) % 8
			if step == 0 then
				bar += 1
			end
		end
	end)
end

function Music.Start(Movement)
	Settings.Watch("MusicVolume", applyVolume)
	Settings.Watch("MusicEnabled", applyVolume)
	if #MUSIC.Playlist > 0 then
		playPlaylist(MUSIC.Playlist)
	else
		playGenerative(Movement)
	end
end

return Music

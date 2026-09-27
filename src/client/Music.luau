-- Soundtrack.
--
-- If Config.Music.Playlist has track IDs, those play shuffled with crossfades.
-- Otherwise a generative score is composed live from pitched built-in sounds,
-- run through a small mixing chain (reverb, tempo-synced echo, chorus, EQ):
--
--   * Song structure: Intro → Verse → Chorus → Verse → Chorus → Break, 8 bars each.
--   * Layers: sustained pad chords, a bassline, arpeggios, a melody built from a
--     repeating 2-bar motif, and drums that come in with the chorus and with speed.
--   * Each time of day has its own mood (key, scale, tempo, chord progressions);
--     night is minor and slow.
--   * It builds with your speed and your combo, and goes muffled in menus.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local MathUtil = require(ReplicatedStorage.Shared.MathUtil)
local Settings = require(script.Parent.Settings)
local UI = require(script.Parent.UI)

local MUSIC = Config.Music
local POOL_SIZE = 32
local STEPS_PER_BAR = 8 -- eighth notes
local BARS_PER_SECTION = 8

local Music = {}

local realmMood: string? = nil

local function moodName(): string
	return realmMood or Settings.Get("TimeOfDay")
end

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

type Mood = { Scale: { number }, Minor: boolean, Key: number, Tempo: number, Progressions: { { number } } }

local MOODS: { [string]: Mood } = {
	Sunrise = { Scale = MAJOR, Minor = false, Key = 2, Tempo = 72, Progressions = { { 0, 7, -3, 5 }, { 5, 0, 7, -3 } } },
	["Golden Hour"] = {
		Scale = MAJOR,
		Minor = false,
		Key = 0,
		Tempo = 80,
		Progressions = { { 0, -3, 5, 7 }, { -3, 5, 0, 7 } },
	},
	Sunset = { Scale = MAJOR, Minor = false, Key = -2, Tempo = 74, Progressions = { { -3, 5, 0, 7 }, { 5, 7, -3, 0 } } },
	Night = { Scale = MINOR, Minor = true, Key = -3, Tempo = 66, Progressions = { { 0, -4, 3, -2 }, { -4, -2, 0, 0 } } },
	-- Realm moods: driving synthwave in Neon City, slow and heavy in Ember Isles.
	neon = {
		Scale = MINOR,
		Minor = true,
		Key = 2,
		Tempo = 100,
		Progressions = { { 0, -4, -2, -5 }, { -4, -2, 0, -5 } },
	},
	ember = { Scale = MINOR, Minor = true, Key = -5, Tempo = 70, Progressions = { { 0, 1, 0, -2 }, { 0, -4, 1, -2 } } },
}

-- Section plan: which layers play in each part of the song.
local SECTIONS = {
	{ Name = "Intro", Arp = 0, Melody = 0.25, Drums = 0, Progression = 1 },
	{ Name = "Verse", Arp = 1, Melody = 0.45, Drums = 0.3, Progression = 1 },
	{ Name = "Chorus", Arp = 2, Melody = 0.65, Drums = 1, Progression = 2 },
	{ Name = "Verse", Arp = 1, Melody = 0.45, Drums = 0.3, Progression = 1 },
	{ Name = "Chorus", Arp = 2, Melody = 0.7, Drums = 1, Progression = 2 },
	{ Name = "Break", Arp = 0, Melody = 0.15, Drums = 0, Progression = 2 },
}

local function addEffects(): EqualizerSoundEffect
	local reverb = Instance.new("ReverbSoundEffect")
	reverb.DecayTime = 3
	reverb.Density = 1
	reverb.Diffusion = 1
	reverb.DryLevel = -2
	reverb.WetLevel = -7
	reverb.Priority = 1
	reverb.Parent = group
	local chorus = Instance.new("ChorusSoundEffect")
	chorus.Depth = 0.25
	chorus.Mix = 0.35
	chorus.Rate = 0.6
	chorus.Priority = 3
	chorus.Parent = group
	local eq = Instance.new("EqualizerSoundEffect")
	eq.LowGain = 2
	eq.MidGain = 0
	eq.HighGain = 0
	eq.Priority = 0
	eq.Parent = group
	return eq
end

local function playGenerative(Movement)
	local eq = addEffects()
	local echo = Instance.new("EchoSoundEffect")
	echo.Feedback = 0.3
	echo.DryLevel = 0
	echo.WetLevel = -14
	echo.Priority = 2
	echo.Parent = group

	local pool: { Sound } = {}
	local nextVoice = 1
	for i = 1, POOL_SIZE do
		local sound = Instance.new("Sound")
		sound.SoundGroup = group
		sound.Parent = SoundService
		pool[i] = sound
	end

	local rng = Random.new()
	local function note(soundId: string, semitones: number, volume: number)
		local voice = pool[nextVoice]
		nextVoice = nextVoice % POOL_SIZE + 1
		voice:Stop()
		voice.SoundId = soundId
		voice.PlaybackSpeed = 2 ^ (math.clamp(semitones, -30, 30) / 12)
		-- Slight humanised dynamics.
		voice.Volume = volume * rng:NextNumber(0.88, 1.08)
		voice:Play()
	end

	local mood = MOODS[moodName()] or MOODS["Golden Hour"]
	Music.MoodChanged = function()
		mood = MOODS[moodName()] or mood
	end
	local step, bar, sectionIndex = 0, 0, 1
	local clock = 0
	local intensity, excitement = 0, 0
	local motif: { number | false } = {}

	-- A 2-bar melody: scale degrees (or rests), walking up and down.
	local function newMotif(density: number)
		motif = {}
		local degree = rng:NextInteger(2, 6)
		for i = 1, STEPS_PER_BAR * 2 do
			if rng:NextNumber() < density then
				degree = math.clamp(degree + rng:NextInteger(-2, 2), 0, #mood.Scale * 2 - 1)
				motif[i] = degree
			else
				motif[i] = false
			end
		end
	end
	newMotif(SECTIONS[1].Melody)

	-- Combos and big moves make the music swell.
	Movement.Action.Event:Connect(function(action: string)
		if action ~= "Slide" then
			excitement = math.min(excitement + 0.12, 1)
		end
	end)

	local function playStep()
		local section = SECTIONS[sectionIndex]
		local progression = mood.Progressions[section.Progression]
		local chordRoot = progression[bar % #progression + 1]
		local root = mood.Key + MUSIC.Key + chordRoot
		-- Minor chords: vi in major moods; i, iv and v in minor moods.
		local isMinor = if mood.Minor then (chordRoot == 0 or chordRoot == 5 or chordRoot == 7) else chordRoot == -3
		local third = if isMinor then 3 else 4
		local chord = { 0, third, 7, 12 }
		local energy = math.max(intensity, excitement)

		-- Pad: soft chord swells on beats 1 and 3.
		if step == 0 or step == 4 then
			local swell = if step == 0 then 0.11 else 0.07
			for _, tone in { 0, third, 7 } do
				note(MUSIC.Tone, root + tone - 12, swell)
			end
		end

		-- Bass.
		if step == 0 then
			note(MUSIC.Tone, root - 24, 0.45)
		elseif step == 3 and section.Arp > 0 then
			note(MUSIC.Tone, root + 7 - 24, 0.28)
		elseif step == 6 and section.Arp > 1 then
			note(MUSIC.Tone, root - 12, 0.22)
		end

		-- Arpeggios: quarters in verses, eighths in choruses (or when flying fast).
		local arpLevel = section.Arp + (if energy > 0.5 then 1 else 0)
		if arpLevel >= 2 or (arpLevel == 1 and step % 2 == 0) then
			local pattern = { 1, 2, 3, 4, 3, 2, 3, 4 }
			note(MUSIC.Tone, root + chord[pattern[step + 1]], 0.16 + energy * 0.08)
		end

		-- Melody from the motif, with the last bar varied each time around.
		local motifStep = (bar % 2) * STEPS_PER_BAR + step + 1
		local degree = motif[motifStep]
		if bar % BARS_PER_SECTION >= BARS_PER_SECTION - 2 and rng:NextNumber() < 0.3 then
			degree = if rng:NextNumber() < 0.5 then false else rng:NextInteger(0, #mood.Scale * 2 - 1)
		end
		if degree then
			local octave = math.floor(degree / #mood.Scale)
			note(MUSIC.Tone, mood.Key + MUSIC.Key + mood.Scale[degree % #mood.Scale + 1] + octave * 12 + 12, 0.17)
		end

		-- Drums come in with the chorus, or when you're really moving.
		-- Realms always have a beat.
		local drums = math.max(section.Drums, energy, if realmMood then 0.5 else 0)
		if Movement.Enabled and drums > 0.35 then
			if step == 0 or step == 4 or (drums > 0.8 and step == 5) then
				note(MUSIC.Kick, -8, 0.35 * drums)
			elseif step == 2 or step == 6 then
				note(MUSIC.Snare, 3, 0.16 * drums)
			end
			if step % 2 == 1 then
				note(MUSIC.Hat, 26, 0.045 * drums)
			end
		end

		step += 1
		if step >= STEPS_PER_BAR then
			step = 0
			bar += 1
			if bar % BARS_PER_SECTION == 0 then
				sectionIndex = sectionIndex % #SECTIONS + 1
				-- Pick up time-of-day changes between sections.
				mood = MOODS[moodName()] or mood
				newMotif(SECTIONS[sectionIndex].Melody)
			end
		end
	end

	local muffled = false
	RunService.Heartbeat:Connect(function(dt)
		-- Muffle the music while menus are open.
		if muffled ~= not Movement.Enabled then
			muffled = not Movement.Enabled
			TweenService:Create(
				eq,
				TweenInfo.new(0.6),
				{ HighGain = if muffled then -24 else 0, MidGain = if muffled then -6 else 0 }
			):Play()
		end
		if group.Volume <= 0 then
			return
		end
		local speed = if Movement.Enabled then Movement.Info.Velocity.Magnitude else 0
		intensity = MathUtil.Damp(intensity, math.clamp(speed / 120, 0, 1), 0.8, dt)
		excitement = math.max(excitement - dt * 0.08, 0)
		local bpm = mood.Tempo + math.max(intensity, excitement) * MUSIC.TempoBoost
		local stepLength = 60 / bpm / 2
		-- Dotted-quarter echo, locked to the tempo.
		echo.Delay = math.clamp(stepLength * 3, 0.01, 1)

		clock += dt
		while clock >= stepLength do
			clock -= stepLength
			playStep()
		end
	end)
end

-- Realms other than the Sky Islands have their own mood; "sky" goes back to
-- the time-of-day one.
function Music.SetRealm(realmId: string)
	realmMood = if realmId == "sky" then nil else realmId
	if Music.MoodChanged then
		Music.MoodChanged()
	end
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

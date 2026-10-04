-- Adaptive generative music.
--
-- Each district has a key, tempo and mood (Config/Districts). A small
-- sequencer turns that into a looping progression played on pitched built-in
-- voices: bass and a soft arpeggio while exploring; drums, a busier arpeggio
-- and melody during runs; extra octaves and a driving hat at high flow or in
-- races. Patterns are seeded by district and bar, so they're consistent but
-- never a short loop. A district with a licensed track (Config/Sounds.Tracks)
-- plays that instead.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Districts = require(ReplicatedStorage.Shared.Config.Districts)
local Rotation = require(ReplicatedStorage.Shared.Logic.Rotation)
local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)

local Sfx = require(script.Parent.Sfx)

local Music = {}

local SCALES: { [string]: { number } } = {
	Bright = { 0, 2, 4, 7, 9 },
	Warm = { 0, 2, 4, 5, 7, 9, 11 },
	Driving = { 0, 2, 3, 5, 7, 9, 10 },
	Mystic = { 0, 2, 4, 6, 7, 9, 11 },
	Pulse = { 0, 2, 3, 5, 7, 8, 10 },
	Cold = { 0, 2, 3, 7, 8 },
	Epic = { 0, 2, 4, 5, 7, 9, 10 },
}
-- Chord roots as scale steps, one per bar.
local PROGRESSIONS: { [string]: { number } } = {
	Bright = { 0, 3, 1, 4 },
	Warm = { 0, 5, 3, 4 },
	Driving = { 0, 6, 5, 4 },
	Mystic = { 0, 1, 4, 2 },
	Pulse = { 0, 5, 2, 6 },
	Cold = { 0, 3, 2, 4 },
	Epic = { 0, 6, 3, 4 },
}

type Voice = { Sounds: { Sound }, Index: number }
local voices: { [string]: Voice } = {}
local holder = Instance.new("Folder")
holder.Name = "SkylineMusic"

local district = "Hub"
local intensity = 0 -- 0 explore, 1 run, 2 race / high flow
local flowTier = 0
local enabled = true
local step = 0
local nextTick = 0
local track: Sound? = nil
local trackId: string? = nil
local fade = 0 -- generative mix level 0..1 (fades around district changes)

local function voice(name: string, id: string, count: number): Voice
	local existing = voices[name]
	if existing then
		return existing
	end
	local list = {}
	for i = 1, count do
		local sound = Instance.new("Sound")
		sound.Name = name .. i
		sound.SoundId = id
		sound.SoundGroup = Sfx.Group("Music")
		sound.Parent = holder
		list[i] = sound
	end
	local v = { Sounds = list, Index = 0 }
	voices[name] = v
	return v
end

local function play(name: string, id: string, semitones: number, volume: number)
	if volume <= 0.001 then
		return
	end
	local v = voice(name, id, 12)
	v.Index = v.Index % #v.Sounds + 1
	local sound = v.Sounds[v.Index]
	sound.PlaybackSpeed = 2 ^ (semitones / 12)
	sound.Volume = volume * fade
	sound.TimePosition = 0
	sound:Play()
end

local function scaleNote(scale: { number }, degree: number): number
	local n = #scale
	local octave = math.floor(degree / n)
	return scale[degree % n + 1] + octave * 12
end

local function tick()
	local info = Districts.ById[district] or Districts.ById.Hub
	local mood = info.Music.Mood
	local scale = SCALES[mood] or SCALES.Bright
	local progression = PROGRESSIONS[mood] or PROGRESSIONS.Bright
	local root = info.Music.Root - 12
	local sixteenth = step % 16
	local bar = math.floor(step / 16)
	local chordRoot = progression[bar % #progression + 1]
	local rng = Rotation.Rng(Rotation.Hash(district, bar, sixteenth))
	local level = intensity + (if flowTier >= 3 then 1 else 0)

	-- Bass on beats 1 and 3 (plus pickups when running).
	if
		sixteenth == 0
		or sixteenth == 8
		or (level >= 1 and (sixteenth == 14 or sixteenth == 6) and rng:Next() < 0.5)
	then
		play("Bass", Sounds.Tone, root - 12 + scaleNote(scale, chordRoot), 0.32)
	end

	-- Arpeggio through the chord: eighths while exploring, sixteenths when running.
	local arpEvery = if level >= 1 then 1 else 2
	if sixteenth % arpEvery == 0 then
		local position = (sixteenth // arpEvery) % 4
		local tones = { 0, 2, 4, 2 }
		local degree = chordRoot + tones[position + 1]
		local octaveUp = if level >= 2 and sixteenth % 4 == 2 then 12 else 0
		play("Arp", Sounds.Tone, root + 12 + scaleNote(scale, degree) + octaveUp, if level >= 1 then 0.11 else 0.08)
	end

	-- Melody: sparse while exploring, phrases when running.
	local density = if level == 0 then 0.12 elseif level == 1 then 0.28 else 0.42
	if sixteenth % 2 == 0 and rng:Next() < density then
		local degree = chordRoot + rng:Int(0, 6)
		play("Lead", Sounds.Tone, root + 24 + scaleNote(scale, degree), 0.12)
	end

	-- Drums.
	if level >= 1 then
		if sixteenth % 4 == 0 then
			play("Kick", Sounds.Kick, -10, 0.45)
		end
		if sixteenth == 4 or sixteenth == 12 then
			play("Snare", Sounds.Snare, 2, 0.22)
		end
		if sixteenth % 4 == 2 or (level >= 2 and sixteenth % 2 == 1) then
			play("Hat", Sounds.Hat, 14, if sixteenth % 4 == 2 then 0.08 else 0.05)
		end
	elseif sixteenth == 0 and bar % 2 == 0 then
		play("Kick", Sounds.Kick, -12, 0.18)
	end
	step += 1
end

local function updateTrack()
	local entry = Sounds.Tracks[district]
	local id = if entry then entry.Id else nil
	if id == trackId then
		return
	end
	trackId = id
	if track then
		track:Destroy()
		track = nil
	end
	if entry then
		local sound = Instance.new("Sound")
		sound.SoundId = entry.Id
		sound.Looped = true
		sound.Volume = entry.Volume
		sound.SoundGroup = Sfx.Group("Music")
		sound.Parent = holder
		sound:Play()
		track = sound
	end
end

function Music.SetDistrict(id: string)
	if id == district then
		return
	end
	district = id
	fade = 0
	step = 0
	updateTrack()
end

-- 0 exploring, 1 running a course, 2 racing / final stretch.
function Music.SetIntensity(level: number)
	intensity = math.clamp(level, 0, 2)
end

function Music.SetFlowTier(tier: number)
	flowTier = tier
end

function Music.SetEnabled(on: boolean)
	enabled = on
end

function Music.Start()
	holder.Parent = SoundService
	updateTrack()
	RunService.Heartbeat:Connect(function(dt)
		fade = math.min(fade + dt * 0.5, 1)
		if not enabled or track then
			return
		end
		local info = Districts.ById[district] or Districts.ById.Hub
		local tempo = info.Music.Tempo * (if intensity >= 2 then 1.08 else 1)
		local interval = 60 / tempo / 4
		local now = os.clock()
		if nextTick == 0 or now - nextTick > 1 then
			nextTick = now
		end
		while now >= nextTick do
			tick()
			nextTick += interval
		end
	end)
end

return Music

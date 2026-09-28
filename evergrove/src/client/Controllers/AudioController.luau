-- Sound: interface clicks, 3D effects, weather/ambience loops, procedural
-- wildlife voices and an adaptive generative soundtrack.
--
-- Every sound is named in Config/Audio (swap Ids for Creator Store audio).
-- Volumes follow the Master/Music/SFX/Ambient/Weather/UI settings. Captions
-- are shown for sounds that have one when Subtitles are on.
--
-- Music: if Config/Audio.Music.Tracks has an asset for the current mood it is
-- played; otherwise a gentle generative score is composed live from the
-- season's key/mode/tempo and the region's mood (tempo, brightness, mode).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AudioConfig = require(Shared.Config.Audio)
local Seasons = require(Shared.Config.Seasons)
local Regions = require(Shared.Config.Regions)
local GameTime = require(Shared.Lib.GameTime)
local WeatherMath = require(Shared.Lib.WeatherMath)
local Signal = require(Shared.Lib.Signal)

local C = require(script.Parent)

local Audio = {}
Audio.Caption = Signal.new() -- (text)

local GROUP_SETTING = { SFX = "SFX", UI = "UIVolume", Ambient = "Ambient", Weather = "WeatherVolume", Music = "Music" }

local groups: { [string]: SoundGroup } = {}
local pools: { [string]: { Sound } } = {}
local poolIndex: { [string]: number } = {}
local loops: { [string]: Sound } = {}
local random = Random.new()

-- Mixer ----------------------------------------------------------------------------------------------------------------

local function applyVolumes()
	local master = C.Settings.Get("Master") or 0.8
	for name, group in groups do
		group.Volume = master * (C.Settings.Get(GROUP_SETTING[name]) or 1)
	end
end

local function pitchOf(def: any): number
	local p = def.Pitch
	if type(p) == "table" then
		return random:NextNumber(p[1], p[2])
	end
	return p or 1
end

local function newSound(def: any, parent: Instance): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = def.Id
	sound.Volume = def.Volume
	sound.PlaybackSpeed = pitchOf(def)
	sound.Looped = def.Loop == true
	sound.SoundGroup = groups[def.Group] or groups.SFX
	if def.Rolloff then
		sound.RollOffMaxDistance = def.Rolloff
		sound.RollOffMinDistance = 8
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
	end
	sound.Parent = parent
	return sound
end

local function caption(def: any)
	if def.Caption and C.Settings.Get("Subtitles") then
		Audio.Caption:Fire(def.Caption)
	end
end

-- 2D sound (interface and personal feedback).
function Audio.PlayUI(name: string)
	local def = AudioConfig.Sounds[name]
	if not def then
		return
	end
	local pool = pools[name]
	if not pool then
		pool = {}
		for _ = 1, 4 do
			table.insert(pool, newSound(def, SoundService))
		end
		pools[name] = pool
		poolIndex[name] = 0
	end
	poolIndex[name] = poolIndex[name] % #pool + 1
	local sound = pool[poolIndex[name]]
	sound.PlaybackSpeed = pitchOf(def)
	sound.TimePosition = 0
	sound:Play()
	caption(def)
end
Audio.Play = Audio.PlayUI

-- 3D sound at a world position.
local emitters: { Attachment } = {}
local emitterIndex = 0
function Audio.PlayAt(name: string, position: Vector3, pitchMult: number?)
	local def = AudioConfig.Sounds[name]
	if not def then
		return
	end
	local camera = workspace.CurrentCamera
	if (camera.CFrame.Position - position).Magnitude > (def.Rolloff or 80) + 20 then
		return
	end
	emitterIndex = emitterIndex % 16 + 1
	local att = emitters[emitterIndex]
	if not att then
		att = Instance.new("Attachment")
		att.Name = "SoundEmitter"
		att.Parent = workspace.Terrain
		emitters[emitterIndex] = att
	end
	att.WorldPosition = position
	local sound = newSound(def, att)
	sound.PlaybackSpeed *= pitchMult or 1
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(8, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
	caption(def)
end

-- Looping sound with a volume target (crossfaded).
function Audio.Loop(name: string, target: number)
	local def = AudioConfig.Sounds[name]
	if not def then
		return
	end
	local sound = loops[name]
	if not sound then
		if target <= 0 then
			return
		end
		sound = newSound(def, SoundService)
		sound.Looped = true
		sound.Volume = 0
		sound:Play()
		loops[name] = sound
	end
	sound:SetAttribute("Target", def.Volume * target)
end

-- Ambience & weather ---------------------------------------------------------------------------------------------------

local AMBIENCE_BY_BIOME = {
	Farmland = { Breeze = 0.8 },
	Village = { Breeze = 0.5 },
	Forest = { Breeze = 1 },
	Wetlands = { River = 1 },
	Beach = { Waves = 1 },
	Cave = { Cave = 1 },
	Crystal = { Cave = 0.8 },
	Mountain = { WindLoop = 0.5 },
	Snow = { WindLoop = 0.6 },
	Desert = { WindLoop = 0.4 },
	Sky = { WindLoop = 0.7 },
}

local WEATHER_LOOPS = {
	Rain = { Rain = 1 },
	Thunderstorm = { Rain = 1, Storm = 0.8 },
	Windy = { WindLoop = 1 },
	Hail = { Hail = 1, Rain = 0.4 },
	Snow = { Snow = 1 },
	Blizzard = { Snow = 1, Storm = 0.9 },
	Sandstorm = { WindLoop = 1, Storm = 0.5 },
	ArcaneStorm = { Arcane = 1, Storm = 0.4 },
}

local function currentRegion()
	local id = Players.LocalPlayer:GetAttribute("Region")
	for _, region in Regions.List do
		if region.Id == id then
			return region
		end
	end
	return Regions.List[2]
end

local function updateLoops()
	local region = currentRegion()
	local wanted: { [string]: number } = {}
	for name, v in AMBIENCE_BY_BIOME[region.Biome] or {} do
		wanted[name] = v
	end
	local indoorsUnderground = region.Biome == "Cave" or region.Biome == "Crystal"
	if not indoorsUnderground then
		local weather = C.Lighting.Weather()
		local intensity = C.Settings.Get("WeatherIntensity") or 1
		for name, v in WEATHER_LOOPS[weather] or {} do
			wanted[name] = math.max(wanted[name] or 0, v * intensity)
		end
	end
	for name in AudioConfig.Sounds do
		local def = AudioConfig.Sounds[name]
		if def.Loop and (wanted[name] or loops[name]) then
			Audio.Loop(name, wanted[name] or 0)
		end
	end
end

-- Procedural wildlife voices by biome and time of day.
local VOICES_BY_BIOME = {
	Farmland = { Day = { "Bird", "Livestock" }, Night = { "Insect", "Owl" } },
	Village = { Day = { "Bird", "Chatter" }, Night = { "Insect" } },
	Forest = { Day = { "Bird", "Bird" }, Night = { "Owl", "Insect" } },
	Wetlands = { Day = { "Frog", "Bird" }, Night = { "Frog", "Insect" } },
	Beach = { Day = { "Gull" }, Night = {} },
	Cave = { Day = { "Drip" }, Night = { "Drip" } },
	Crystal = { Day = { "Chimes", "Drip" }, Night = { "Chimes" } },
	Glade = { Day = { "Chimes" }, Night = { "Chimes", "Insect" } },
	Grove = { Day = { "Drip", "Chimes" }, Night = { "Chimes" } },
	Valley = { Day = { "Bird", "Chimes" }, Night = { "Insect" } },
}

local function playVoice(name: string)
	local voice = AudioConfig.Voices[name]
	if not voice then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = voice.Id
	sound.Volume = voice.Volume
	sound.PlaybackSpeed = random:NextNumber(voice.Pitch[1], voice.Pitch[2])
	sound.SoundGroup = groups.Ambient
	sound.Parent = SoundService
	sound:Play()
	if voice.Glide then
		task.spawn(function()
			for _ = 1, 8 do
				task.wait(0.03)
				sound.PlaybackSpeed += voice.Glide * 0.05
			end
		end)
	end
	task.delay(3, function()
		sound:Destroy()
	end)
end

-- Generative music -------------------------------------------------------------------------------------------------------

local MODES = {
	Major = { 0, 2, 4, 5, 7, 9, 11 },
	Minor = { 0, 2, 3, 5, 7, 8, 10 },
	Dorian = { 0, 2, 3, 5, 7, 9, 10 },
	Lydian = { 0, 2, 4, 6, 7, 9, 11 },
	Phrygian = { 0, 1, 3, 5, 7, 8, 10 },
	Mixolydian = { 0, 2, 4, 5, 7, 9, 10 },
	Pentatonic = { 0, 2, 4, 7, 9 },
}

local MOOD_BY_BIOME = {
	Farmland = "Farm", Village = "Village", Forest = "Forest", Wetlands = "River", Mountain = "Mountain",
	Cave = "Cave", Crystal = "Crystal", Beach = "Beach", Desert = "Desert", Snow = "Snow", Ruins = "Ruins",
	Hollow = "Hollow", Sky = "Sky", Valley = "Valley", Grove = "Grove", Glade = "Glade",
}

local tonePool: { Sound } = {}
local toneIndex = 0
local musicTrack: Sound? = nil
local musicMood = ""

local function tone(semitone: number, volume: number, id: string?)
	toneIndex = toneIndex % #tonePool + 1
	local s = tonePool[toneIndex]
	s.SoundId = id or AudioConfig.Music.Tone
	s.PlaybackSpeed = 2 ^ (semitone / 12)
	s.Volume = volume
	s.TimePosition = 0
	s:Play()
end

function Audio.Mood(): string
	local region = currentRegion()
	if ReplicatedStorage:GetAttribute("Festival") and region.Biome == "Village" then
		return "Festival"
	end
	local info = GameTime.Info()
	local mood = MOOD_BY_BIOME[region.Biome] or "Farm"
	if info.IsNight and (mood == "Farm" or mood == "Village" or mood == "Forest") then
		return "Night"
	end
	if info.SeasonId == "Winter" and mood == "Farm" then
		return "Winter"
	end
	return mood
end

local function musicLoop()
	local step = 0
	local chordRoot = 0
	while true do
		local mood = Audio.Mood()
		local tracks = AudioConfig.Music.Tracks
		local trackId = tracks[mood] or tracks[GameTime.Info().SeasonId]
		if trackId then
			-- A real track: loop it, crossfade on mood change.
			if musicMood ~= mood or not musicTrack then
				musicMood = mood
				if musicTrack then
					musicTrack:Destroy()
				end
				local s = Instance.new("Sound")
				s.SoundId = trackId
				s.Looped = true
				s.Volume = 0.5
				s.SoundGroup = groups.Music
				s.Parent = SoundService
				s:Play()
				musicTrack = s
			end
			task.wait(2)
		else
			if musicTrack then
				musicTrack:Destroy()
				musicTrack = nil
			end
			musicMood = mood
			local info = GameTime.Info()
			local season = Seasons[info.Season] or Seasons[1]
			local moodDef = AudioConfig.Music.Moods[mood] or {}
			local modeName = moodDef.Mode or (if moodDef.Minor then "Minor" else season.Music.Mode)
			local scale = MODES[modeName] or MODES.Major
			local tempo = math.max(50, season.Music.Tempo + (moodDef.Tempo or 0))
			local beat = 60 / tempo / 2 -- eighth notes
			local bright = moodDef.Bright or 1
			local root = season.Music.Root - 12
			-- Chord changes every 8 steps through a gentle I–vi–IV–V style walk.
			if step % 8 == 0 then
				local walk = { 0, 5, 3, 4, 0, 3, 5, 4 }
				chordRoot = walk[(step // 8) % #walk + 1]
				local bassNote = scale[(chordRoot % #scale) + 1] + root - 12
				tone(bassNote, 0.18)
				tone(scale[((chordRoot + 2) % #scale) + 1] + root, 0.07)
				tone(scale[((chordRoot + 4) % #scale) + 1] + root, 0.07)
			end
			-- Melody: sparse, stepwise, brighter moods climb higher.
			if random:NextNumber() < 0.55 then
				local degree = chordRoot + random:NextInteger(0, 6)
				local octave = if bright > 1.15 then 12 elseif bright < 0.8 then 0 else 12 * random:NextInteger(0, 1)
				local note = scale[(degree % #scale) + 1] + root + 12 + octave
				tone(note, 0.11 * bright)
			end
			if mood == "Festival" or mood == "Village" then
				if step % 4 == 0 then
					tone(-24, 0.06, AudioConfig.Music.Kick)
				elseif step % 4 == 2 then
					tone(0, 0.03, AudioConfig.Music.Hat)
				end
			end
			step += 1
			task.wait(beat)
		end
	end
end

-- Lifecycle -------------------------------------------------------------------------------------------------------------

function Audio.Init()
	for name in GROUP_SETTING do
		local group = Instance.new("SoundGroup")
		group.Name = name
		group.Parent = SoundService
		groups[name] = group
	end
	for _ = 1, 12 do
		local s = Instance.new("Sound")
		s.SoundGroup = groups.Music
		s.Parent = SoundService
		table.insert(tonePool, s)
	end
	applyVolumes()
	C.Settings.Changed:Connect(function(key)
		if key == "Master" or GROUP_SETTING.SFX == key or key == "Music" or key == "Ambient" or key == "WeatherVolume" or key == "UIVolume" then
			applyVolumes()
		end
	end)
end

function Audio.Start()
	-- Loop crossfades
	task.spawn(function()
		while true do
			for _, sound in loops do
				local target = sound:GetAttribute("Target") or 0
				sound.Volume += (target - sound.Volume) * 0.15
			end
			task.wait(0.1)
		end
	end)
	task.spawn(function()
		while true do
			pcall(updateLoops)
			task.wait(2)
		end
	end)
	-- Wildlife voices
	task.spawn(function()
		while true do
			task.wait(random:NextNumber(1.5, 5))
			local region = currentRegion()
			local set = VOICES_BY_BIOME[region.Biome]
			local weather = WeatherMath.Def(C.Lighting.Weather()) or {}
			if set and not weather.Hazard then
				local list = if GameTime.Info().IsNight then set.Night else set.Day
				if #list > 0 then
					playVoice(list[random:NextInteger(1, #list)])
				end
			end
		end
	end)
	task.spawn(musicLoop)
end

return Audio

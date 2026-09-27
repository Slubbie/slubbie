-- Sound for VARIANCE.
--
-- Mixer: SoundGroups Master > {Music, Effects, Ambience, Voice, Interface},
-- driven by the volume settings. Music and Ambience carry a "Duck" equalizer so
-- the room can drop away right before an outcome (duck / unduck).
--
-- play(name, opts) plays a recipe from Data/SoundLibrary: pooled Sounds, 2D or
-- positional (opts.At = Vector3 | BasePart), with the recipe's pitch, variance
-- and effects. Assets that fail to load are detected with PreloadAsync and
-- replaced by their Fallback recipe automatically.
--
-- Also: environment beds (looping room tone), a heartbeat that quickens with
-- low Integrity, surrogate voice blips, and a generative tension score whose
-- layers rise with match intensity (replaceable with licensed tracks).

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local SoundLibrary = require(ReplicatedStorage.Variance.Data.SoundLibrary)

local AudioController = {}

local groups: { [string]: SoundGroup } = {}
local duckers: { EqualizerSoundEffect } = {}
local failed: { [string]: boolean } = {}
local pools: { [string]: { Sound } } = {}
local anchor: Attachment? = nil
local bedLoops: { [string]: Sound } = {}
local currentBed: string? = nil
local heartbeatRate = 0
local musicIntensity = 0
local musicContext = "Lobby"
local musicLayers: { [string]: Sound } = {}
local licensed: { [string]: Sound } = {}
local rng = Random.new()

local PENTATONIC = { 1, 1.189, 1.335, 1.498, 1.782, 2 }

function AudioController:Init(controllers)
	self.Controllers = controllers
	local master = Instance.new("SoundGroup")
	master.Name = "VarianceMaster"
	master.Volume = 0.8
	master.Parent = SoundService
	groups.Master = master
	for _, name in { "Music", "Effects", "Ambience", "Voice", "Interface" } do
		local g = Instance.new("SoundGroup")
		g.Name = name
		g.Volume = 1
		g.Parent = master
		groups[name] = g
		if name == "Music" or name == "Ambience" then
			local eq = Instance.new("EqualizerSoundEffect")
			eq.Name = "Duck"
			eq.LowGain = 0
			eq.MidGain = 0
			eq.HighGain = 0
			eq.Parent = g
			table.insert(duckers, eq)
		end
	end
end

local function resolve(name: string, depth: number?): SoundLibrary.Recipe?
	local recipe = SoundLibrary.get(name)
	local d = depth or 0
	if recipe == nil or d > 4 then
		return nil
	end
	if failed[recipe.Id] and recipe.Fallback then
		return resolve(recipe.Fallback, d + 1)
	end
	return recipe
end

local function addEffects(sound: Sound, recipe)
	if recipe.Reverb then
		local r = Instance.new("ReverbSoundEffect")
		r.DecayTime = 2.2
		r.Density = 0.8
		r.DryLevel = -2
		r.WetLevel = -8
		r.Parent = sound
	end
	if recipe.LowPass then
		local eq = Instance.new("EqualizerSoundEffect")
		eq.HighGain = -40 * recipe.LowPass
		eq.MidGain = -12 * recipe.LowPass
		eq.LowGain = 2
		eq.Parent = sound
	end
	if recipe.Distort then
		local dist = Instance.new("DistortionSoundEffect")
		dist.Level = recipe.Distort
		dist.Parent = sound
	end
	if recipe.Echo then
		local echo = Instance.new("EchoSoundEffect")
		echo.Delay = 0.18
		echo.Feedback = recipe.Echo * 0.6
		echo.WetLevel = -6
		echo.Parent = sound
	end
end

local function makeSound(recipe): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = recipe.Id
	sound.Volume = recipe.Volume or 0.5
	sound.PlaybackSpeed = recipe.Pitch or 1
	sound.Looped = recipe.Looped == true
	sound.SoundGroup = groups[recipe.Group or "Effects"] or groups.Effects
	sound.RollOffMaxDistance = recipe.Rolloff or 60
	sound.RollOffMinDistance = 6
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	addEffects(sound, recipe)
	return sound
end

local function positionalParent(at: any): Instance
	if typeof(at) == "Instance" then
		if at:IsA("BasePart") or at:IsA("Attachment") then
			return at
		end
	elseif typeof(at) == "Vector3" then
		local a = Instance.new("Attachment")
		a.Name = "VarianceSound"
		a.WorldPosition = at
		a.Parent = workspace.Terrain
		task.delay(8, function()
			a:Destroy()
		end)
		return a
	end
	return anchor or SoundService
end

export type PlayOptions = {
	At: any?,
	Volume: number?,
	Pitch: number?,
	Delay: number?,
}

-- Plays a one-shot recipe. Returns the Sound (or nil if unavailable).
function AudioController:play(name: string, opts: PlayOptions?): Sound?
	local recipe = resolve(name)
	if recipe == nil then
		return nil
	end
	local o = opts or {}
	local pool = pools[name]
	if pool == nil then
		pool = {}
		pools[name] = pool
	end
	local sound = nil
	for _, s in pool do
		if not s.IsPlaying and s:GetAttribute("Busy") ~= true then
			sound = s
			break
		end
	end
	if sound == nil then
		if #pool >= 6 then
			sound = pool[1]
			sound:Stop()
		else
			sound = makeSound(recipe)
			sound.Name = name
			table.insert(pool, sound)
		end
	end
	local s = sound :: Sound
	if s.SoundId ~= recipe.Id then
		s.SoundId = recipe.Id
	end
	local var = recipe.PitchVar or 0
	s.PlaybackSpeed = (recipe.Pitch or 1) * (o.Pitch or 1) * (1 + (rng:NextNumber() * 2 - 1) * var)
	s.Volume = (recipe.Volume or 0.5) * (o.Volume or 1)
	s.Parent = if o.At then positionalParent(o.At) else SoundService
	s:SetAttribute("Busy", true)
	local function go()
		s.TimePosition = 0
		s:Play()
		task.delay(math.max(s.TimeLength / math.max(s.PlaybackSpeed, 0.05), 0.5) + 0.2, function()
			s:SetAttribute("Busy", false)
		end)
	end
	if o.Delay and o.Delay > 0 then
		task.delay(o.Delay, go)
	else
		go()
	end
	return s
end

-- A looping sound handle: { Sound, stop(fade), volume(v, fade) }.
function AudioController:loop(name: string, at: any?)
	local recipe = resolve(name)
	if recipe == nil then
		return nil
	end
	local sound = makeSound(recipe)
	sound.Looped = true
	sound.Name = "Loop_" .. name
	sound.Parent = if at then positionalParent(at) else SoundService
	local base = sound.Volume
	sound.Volume = 0
	sound:Play()
	local handle = { Sound = sound, Base = base }
	local TweenService = game:GetService("TweenService")
	function handle.volume(v: number, fade: number?)
		TweenService:Create(sound, TweenInfo.new(fade or 1), { Volume = base * v }):Play()
	end
	function handle.pitch(p: number, fade: number?)
		TweenService:Create(sound, TweenInfo.new(fade or 1), { PlaybackSpeed = (recipe.Pitch or 1) * p }):Play()
	end
	function handle.stop(fade: number?)
		local t = TweenService:Create(sound, TweenInfo.new(fade or 1), { Volume = 0 })
		t:Play()
		task.delay((fade or 1) + 0.05, function()
			sound:Destroy()
		end)
	end
	handle.volume(1, 1.5)
	return handle
end

-- Pulls music and ambience down before an outcome ("the silence before the shot").
function AudioController:duck(depth: number, time: number?)
	local TweenService = game:GetService("TweenService")
	for _, eq in duckers do
		TweenService:Create(eq, TweenInfo.new(time or 0.4), { HighGain = -30 * depth, MidGain = -14 * depth, LowGain = -6 * depth }):Play()
	end
	for _, name in { "Music", "Ambience" } do
		local base = groups[name]:GetAttribute("Base") or 1
		TweenService:Create(groups[name], TweenInfo.new(time or 0.4), { Volume = base * (1 - 0.7 * depth) }):Play()
	end
end

function AudioController:unduck(time: number?)
	self:duck(0, time or 1.2)
end

-- Environment room tone.
function AudioController:setBed(name: string?)
	if name == currentBed then
		return
	end
	currentBed = name
	for key, handle in bedLoops do
		handle.stop(2)
		bedLoops[key] = nil
	end
	local bed = name and SoundLibrary.Beds[name]
	if bed then
		for _, recipeName in bed do
			bedLoops[recipeName] = self:loop(recipeName)
		end
	end
end

function AudioController:setHumPitch(pitch: number)
	local hum = bedLoops.Hum
	if hum then
		hum.pitch(pitch, 2)
	end
end

-- 0 = off; 1 = racing. Driven by the local subject's Integrity.
function AudioController:setHeartbeat(rate: number)
	heartbeatRate = math.clamp(rate, 0, 1)
end

-- Surrogate voice: a short burst of pitched blips while a line is shown.
function AudioController:voice(tone: string?, pitch: number?, rate: number?, duration: number)
	local recipe = tone or "Blip"
	local count = math.clamp(math.floor(duration * (rate or 10) * 0.5), 2, 30)
	task.spawn(function()
		for _ = 1, count do
			self:play(recipe, { Pitch = (pitch or 1) * (0.85 + rng:NextNumber() * 0.3) })
			task.wait(1 / (rate or 10) + rng:NextNumber() * 0.05)
		end
	end)
end

function AudioController:announce()
	self:play("Chime")
	self:play("ChimeLow", { Delay = 0.28 })
end

---------------------------------------------------------------------------
-- Score
---------------------------------------------------------------------------

function AudioController:setMusic(context: string, intensity: number?)
	musicContext = context
	if intensity then
		musicIntensity = math.clamp(intensity, 0, 1)
	end
end

function AudioController:setIntensity(intensity: number)
	musicIntensity = math.clamp(intensity, 0, 1)
end

local function licensedTrack(key: string): Sound?
	local def = SoundLibrary.Music[key]
	if def == nil or def.Id == "" or failed[def.Id] then
		return nil
	end
	local s = licensed[key]
	if s == nil then
		s = Instance.new("Sound")
		s.Name = "Music_" .. key
		s.SoundId = def.Id
		s.Looped = true
		s.Volume = 0
		s.SoundGroup = groups.Music
		s.Parent = SoundService
		s:Play()
		licensed[key] = s
	end
	return s
end

local function runScore(self)
	-- Generative layers.
	local drone = makeSound({ Id = "rbxasset://sounds/action_falling.mp3", Pitch = 0.18, Volume = 0, Looped = true, Group = "Music", LowPass = 0.9 })
	drone.Name = "ScoreDrone"
	drone.Parent = SoundService
	drone:Play()
	local tension = makeSound({ Id = "rbxasset://sounds/electronicpingshort.wav", Pitch = 0.25, Volume = 0, Looped = true, Group = "Music", Reverb = true })
	tension.Name = "ScoreTension"
	tension.Parent = SoundService
	tension:Play()
	musicLayers.Drone = drone
	musicLayers.Tension = tension
	local beat = 0
	while true do
		local intensity = musicIntensity
		local inMatch = musicContext == "Match"
		local off = musicContext == "Off"
		local key = off and nil or (not inMatch and "Lobby" or (intensity < 0.35 and "Low" or (intensity < 0.7 and "Mid" or "High")))
		local usingLicensed = false
		for k, def in SoundLibrary.Music do
			local track = licensedTrack(k)
			if track then
				local target = (k == key) and def.Volume or 0
				track.Volume = track.Volume + (target - track.Volume) * 0.08
				if k == key then
					usingLicensed = true
				end
			end
		end
		local droneTarget = (off or usingLicensed) and 0 or (inMatch and 0.18 + intensity * 0.12 or 0.1)
		drone.Volume = drone.Volume + (droneTarget - drone.Volume) * 0.1
		local tensionTarget = (off or usingLicensed or not inMatch) and 0 or math.max(0, intensity - 0.45) * 0.12
		-- Tremolo on the tension tone.
		tension.Volume = tensionTarget * (0.6 + 0.4 * math.sin(os.clock() * (3 + intensity * 6)))
		-- Pulse and arpeggio on a tempo that climbs with intensity.
		local bpm = 52 + intensity * 58
		beat += 1
		if not off and not usingLicensed and inMatch and intensity > 0.25 then
			self:play("BaseThump", { Volume = 0.12 + intensity * 0.18, Pitch = 0.45 })
		end
		if not off and not usingLicensed and inMatch and intensity > 0.72 and beat % 2 == 0 then
			local note = PENTATONIC[rng:NextInteger(1, #PENTATONIC)]
			self:play("BasePing", { Volume = 0.08, Pitch = 0.5 * note })
		end
		task.wait(60 / bpm)
	end
end

local function runHeartbeat(self)
	while true do
		local rate = heartbeatRate
		local settings = self.Controllers.SettingsController
		if rate > 0 and settings:get("Heartbeat") ~= false then
			local bpm = 62 + rate * 70
			self:play("Heartbeat", { Volume = 0.35 + rate * 0.65 })
			task.wait(0.28)
			self:play("Heartbeat", { Volume = (0.35 + rate * 0.65) * 0.7, Pitch = 0.92 })
			task.wait(math.max(60 / bpm - 0.28, 0.2))
		else
			task.wait(0.5)
		end
	end
end

local function applyVolumes(self)
	local s = self.Controllers.SettingsController
	groups.Master.Volume = s:get("MasterVolume") or 0.8
	local map = {
		Music = "MusicVolume",
		Effects = "EffectsVolume",
		Ambience = "AmbienceVolume",
		Voice = "VoiceVolume",
		Interface = "InterfaceVolume",
	}
	for group, key in map do
		local v = s:get(key) or 1
		groups[group]:SetAttribute("Base", v)
		groups[group].Volume = v
	end
end

function AudioController:Start()
	local anchorPart = workspace.Terrain
	local a = Instance.new("Attachment")
	a.Name = "VarianceListener"
	a.Parent = anchorPart
	anchor = a
	applyVolumes(self)
	self.Controllers.SettingsController.Changed:Connect(function()
		applyVolumes(self)
	end)
	-- Detect missing assets so recipes fall back cleanly.
	task.spawn(function()
		local probes = {}
		local seen = {}
		for _, recipe in SoundLibrary.Recipes do
			if not seen[recipe.Id] then
				seen[recipe.Id] = true
				local s = Instance.new("Sound")
				s.SoundId = recipe.Id
				table.insert(probes, s)
			end
		end
		for _, def in SoundLibrary.Music do
			if def.Id ~= "" and not seen[def.Id] then
				seen[def.Id] = true
				local s = Instance.new("Sound")
				s.SoundId = def.Id
				table.insert(probes, s)
			end
		end
		pcall(function()
			ContentProvider:PreloadAsync(probes, function(assetId, status)
				if status == Enum.AssetFetchStatus.Failure then
					failed[assetId] = true
					warn("[VARIANCE/Audio] missing sound " .. tostring(assetId) .. "; using fallback")
				end
			end)
		end)
		for _, s in probes do
			s:Destroy()
		end
	end)
	self:setBed("Lobby")
	task.spawn(runScore, self)
	task.spawn(runHeartbeat, self)
end

return AudioController

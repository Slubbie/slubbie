-- Plays configured sound effects and music. Missing or empty asset ids are skipped silently,
-- so the game works with no audio uploaded at all.

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Dicebound.Config)
local ClientState = require(script.Parent.ClientState)

local Sound = {}

local folder = Instance.new("Folder")
folder.Name = "DiceboundSounds"
folder.Parent = SoundService

local cache: { [string]: Sound } = {}

local function get(name: string): Sound?
	local def = Config.Sounds.Effects[name]
	if not def or not def.Id or def.Id == "" then
		return nil
	end
	local sound = cache[name]
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = def.Id
		sound.PlaybackSpeed = def.Pitch or 1
		sound.Parent = folder
		cache[name] = sound
	end
	return sound
end

function Sound.Play(name: string)
	local sound = get(name)
	if sound then
		local def = Config.Sounds.Effects[name]
		sound.Volume = (def.Volume or 0.5) * (ClientState.Settings.Sfx or 0.8)
		if sound.Volume > 0 then
			SoundService:PlayLocalSound(sound)
		end
	end
end

-- Music: loops through Config.Sounds.Music, if any tracks are configured.
local music = Instance.new("Sound")
music.Name = "Music"
music.Parent = folder
local trackIndex = 0

local function trackVolume(): number
	local track = Config.Sounds.Music[trackIndex]
	return (track and track.Volume or 0.5) * (ClientState.Settings.Music or 0.5)
end

local function nextTrack()
	local tracks = Config.Sounds.Music
	if #tracks == 0 then
		return
	end
	trackIndex = trackIndex % #tracks + 1
	music.SoundId = tracks[trackIndex].Id
	music.Volume = trackVolume()
	music:Play()
end
music.Ended:Connect(nextTrack)

function Sound.Start()
	nextTrack()
	ClientState.SettingsChanged:Connect(function()
		music.Volume = trackVolume()
	end)
end

return Sound

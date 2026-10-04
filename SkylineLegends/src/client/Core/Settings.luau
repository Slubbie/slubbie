-- Player preferences: read from the saved profile, applied live, saved back.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local SettingsConfig = require(ReplicatedStorage.Shared.Config.Settings)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local State = require(script.Parent.State)

local Settings = {}

Settings.Changed = Signal.new() -- (id, value)

local values: { [string]: any } = SettingsConfig.Defaults()
local saveQueued = false

function Settings.Get(id: string): any
	local value = values[id]
	if value == nil then
		local def = SettingsConfig.ById[id]
		return def and def.Default
	end
	return value
end

-- Motion effects respect the master Reduced Motion switch.
function Settings.Motion(id: string): boolean
	if values.ReducedMotion then
		return false
	end
	return Settings.Get(id) == true
end

local function queueSave()
	if saveQueued then
		return
	end
	saveQueued = true
	task.delay(1.5, function()
		saveQueued = false
		Net.Send("Settings.Save", values)
	end)
end

function Settings.Set(id: string, value: any)
	local clean = SettingsConfig.Sanitize(id, value)
	if clean == nil or values[id] == clean then
		return
	end
	values[id] = clean
	Settings.Changed:Fire(id, clean)
	queueSave()
end

-- "Auto" quality picks a sensible default per device.
function Settings.Quality(): string
	local quality = Settings.Get("Quality")
	if quality ~= "Auto" then
		return quality
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Low"
	end
	return "High"
end

function Settings.Start()
	State.On("Settings", function(saved)
		if type(saved) ~= "table" then
			return
		end
		for id, value in saved do
			local clean = SettingsConfig.Sanitize(id, value)
			if clean ~= nil and values[id] ~= clean then
				values[id] = clean
				Settings.Changed:Fire(id, clean)
			end
		end
	end)
end

return Settings

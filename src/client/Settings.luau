-- Player settings: graphics, camera, controls and audio.
--
-- Loaded from the server on join (saved with your progress), changed from the
-- Settings menu. Anything can react to changes through Settings.Changed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local S = Config.Settings
local SAVE_DELAY = 1.5

local Settings = {}
Settings.Changed = Instance.new("BindableEvent") -- (key: string, value: any)

local values: { [string]: any } = table.clone(S.Defaults)
local saveQueued = false

local function isValid(key: string, value: any): boolean
	local default = S.Defaults[key]
	if default == nil or type(value) ~= type(default) then
		return false
	end
	if S.Choices[key] then
		return table.find(S.Choices[key], value) ~= nil
	end
	return true
end

local function queueSave()
	if saveQueued then
		return
	end
	saveQueued = true
	task.delay(SAVE_DELAY, function()
		saveQueued = false
		Net.Event("SaveSettings"):FireServer(values)
	end)
end

function Settings.Get(key: string): any
	return values[key]
end

function Settings.Set(key: string, value: any)
	if not isValid(key, value) then
		return
	end
	local range = S.Ranges[key]
	if range and type(value) == "number" then
		value = math.clamp(value, range[1], range[2])
	end
	if values[key] == value then
		return
	end
	values[key] = value
	Settings.Changed:Fire(key, value)
	queueSave()
end

-- Step a multiple-choice setting forward (or backward with -1).
function Settings.Cycle(key: string, direction: number?)
	local choices = S.Choices[key]
	if not choices then
		return
	end
	local index = table.find(choices, values[key]) or 1
	index = (index - 1 + (direction or 1)) % #choices + 1
	Settings.Set(key, choices[index])
end

-- Calls `callback(value)` now and whenever `key` changes.
function Settings.Watch(key: string, callback: (any) -> ())
	callback(values[key])
	Settings.Changed.Event:Connect(function(changedKey, value)
		if changedKey == key then
			callback(value)
		end
	end)
end

function Settings.Load()
	local ok, saved = pcall(function()
		return Net.Function("GetSettings"):InvokeServer()
	end)
	if not ok or type(saved) ~= "table" then
		return
	end
	for key, value in saved do
		if isValid(key, value) and values[key] ~= value then
			values[key] = value
			Settings.Changed:Fire(key, value)
		end
	end
end

return Settings

-- Player settings: defaults from Config/Settings, saved values from the
-- profile, live changes applied immediately and saved (debounced).
--
--   Settings.Get("Music") → 0.6
--   Settings.Set("Music", 0.4)
--   Settings.Changed:Connect(function(key, value) ... end)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SettingsConfig = require(Shared.Config.Settings)
local Net = require(Shared.Lib.Net)
local Signal = require(Shared.Lib.Signal)

local C = require(script.Parent)

local Settings = {}
Settings.Changed = Signal.new() -- (key, value)

local SAVE_DELAY = 2

local specByKey: { [string]: any } = {}
for _, spec in SettingsConfig.Specs do
	specByKey[spec.Key] = spec
end
Settings.Specs = SettingsConfig.Specs
Settings.Tabs = SettingsConfig.Tabs

local values: { [string]: any } = {}
local saveQueued = false

function Settings.Spec(key: string)
	return specByKey[key]
end

function Settings.Get(key: string): any
	local v = values[key]
	if v == nil then
		local spec = specByKey[key]
		return spec and spec.Default
	end
	return v
end

local function clean(spec: any, value: any): any
	if spec.Kind == "Toggle" then
		return value == true
	elseif spec.Kind == "Slider" then
		local n = tonumber(value) or spec.Default
		local step = spec.Step or 0
		if step > 0 then
			n = math.round(n / step) * step
		end
		return math.clamp(n, spec.Min, spec.Max)
	elseif spec.Kind == "Choice" then
		return if table.find(spec.Options, value) then value else spec.Default
	end
	return spec.Default
end

function Settings.Set(key: string, value: any)
	local spec = specByKey[key]
	if not spec then
		return
	end
	local v = clean(spec, value)
	if values[key] == v then
		return
	end
	values[key] = v
	Settings.Changed:Fire(key, v)
	if not saveQueued then
		saveQueued = true
		task.delay(SAVE_DELAY, function()
			saveQueued = false
			Net.Send("SaveSettings", values)
		end)
	end
end

function Settings.ResetTab(tab: string)
	for _, spec in SettingsConfig.Specs do
		if spec.Tab == tab then
			Settings.Set(spec.Key, spec.Default)
		end
	end
end

-- Touch or gamepad as the main input (for defaults like auto-targeting).
function Settings.PrimaryInput(): string
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "Gamepad"
	elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	end
	return "Keyboard"
end

function Settings.Init()
	C.State.Watch("Settings", function(saved)
		if type(saved) ~= "table" then
			return
		end
		for key, value in saved do
			local spec = specByKey[key]
			if spec and values[key] ~= value then
				values[key] = clean(spec, value)
				Settings.Changed:Fire(key, values[key])
			end
		end
	end)
end

return Settings

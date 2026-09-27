-- Player settings on the client: holds the current values, applies changes
-- immediately (Changed signal), and saves them to the server (debounced).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SettingsSchema = require(ReplicatedStorage.Variance.Data.SettingsSchema)
local Signal = require(ReplicatedStorage.Variance.Util.Signal)

local SettingsController = {}
SettingsController.Changed = Signal.new() -- (key, value) ; key "*" for a full reload

local values = SettingsSchema.defaults()
local dirty = false
local saveScheduled = false

function SettingsController:Init(controllers)
	self.Controllers = controllers
end

function SettingsController:get(key: string): any
	return values[key]
end

function SettingsController:all(): { [string]: any }
	return values
end

-- Binding for a rebindable action (falls back to the schema default).
function SettingsController:bind(actionId: string): string?
	local binds = values.Binds or {}
	if binds[actionId] then
		return binds[actionId]
	end
	for _, action in SettingsSchema.Actions do
		if action.Id == actionId then
			return action.Default
		end
	end
	return nil
end

function SettingsController:set(key: string, value: any)
	local cleaned = SettingsSchema.clean(key, value, nil)
	if cleaned == nil then
		return
	end
	values[key] = cleaned
	dirty = true
	SettingsController.Changed:Fire(key, cleaned)
	if not saveScheduled then
		saveScheduled = true
		task.delay(1.5, function()
			saveScheduled = false
			if dirty then
				dirty = false
				self.Controllers.NetworkClient:request("Settings.Save", values)
			end
		end)
	end
end

function SettingsController:reset(category: string?)
	local defaults = SettingsSchema.defaults()
	for _, field in SettingsSchema.Fields do
		if category == nil or field.Category == category then
			self:set(field.Key, defaults[field.Key])
		end
	end
end

function SettingsController:Start()
	self.Controllers.NetworkClient:onPush("Settings", function(data)
		values = SettingsSchema.cleanAll(data)
		SettingsController.Changed:Fire("*", nil)
	end)
end

return SettingsController

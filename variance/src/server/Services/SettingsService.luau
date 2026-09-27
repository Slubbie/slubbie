-- Saves player settings (validated against Data/SettingsSchema) and sends them
-- to the client when the profile loads. Settings are cosmetic/comfort only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SettingsSchema = require(ReplicatedStorage.Variance.Data.SettingsSchema)

local SettingsService = {}

local validKeys: { [string]: boolean } = {}
for _, item in Enum.KeyCode:GetEnumItems() do
	validKeys[item.Name] = true
end

function SettingsService:Init(services)
	self.Services = services
end

function SettingsService:get(player: Player): { [string]: any }
	local profile = self.Services.DataService:get(player)
	if profile == nil then
		return SettingsSchema.defaults()
	end
	return profile.Data.Settings
end

function SettingsService:Start()
	local data = self.Services.DataService
	local network = self.Services.NetworkService
	data.Loaded:Connect(function(player, profile)
		network:push(player, "Settings", profile.Data.Settings)
	end)
	network:handle("Settings.Save", function(player, input)
		local cleaned = SettingsSchema.cleanAll(input, validKeys)
		local ok = data:update(player, function(d)
			d.Settings = cleaned
			return true
		end)
		return ok == true, cleaned
	end)
end

return SettingsService

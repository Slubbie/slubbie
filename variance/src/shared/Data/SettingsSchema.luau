-- Player settings: one schema drives the settings screen, the server's
-- validation and the defaults for new players.
-- Types: "slider" (Min/Max/Step), "toggle", "choice" (Options), "binds".

local SettingsSchema = {}

SettingsSchema.Categories = {
	{ Id = "Audio", Name = "AUDIO" },
	{ Id = "Video", Name = "VIDEO" },
	{ Id = "Gameplay", Name = "GAMEPLAY" },
	{ Id = "Accessibility", Name = "ACCESSIBILITY" },
	{ Id = "Controls", Name = "CONTROLS" },
}

-- Keyboard actions that can be rebound (gamepad and touch layouts are fixed so
-- every platform has the same actions in the same places).
SettingsSchema.Actions = {
	{ Id = "FireSelf", Label = "Fire at yourself", Default = "Q" },
	{ Id = "FireOther", Label = "Fire at opponent", Default = "E" },
	{ Id = "CycleTarget", Label = "Cycle target", Default = "Tab" },
	{ Id = "Slot1", Label = "Instrument 1", Default = "One" },
	{ Id = "Slot2", Label = "Instrument 2", Default = "Two" },
	{ Id = "Slot3", Label = "Instrument 3", Default = "Three" },
	{ Id = "Slot4", Label = "Instrument 4", Default = "Four" },
	{ Id = "Slot5", Label = "Instrument 5", Default = "Five" },
	{ Id = "Slot6", Label = "Instrument 6", Default = "Six" },
	{ Id = "Slot7", Label = "Instrument 7", Default = "Seven" },
	{ Id = "Slot8", Label = "Instrument 8", Default = "Eight" },
	{ Id = "ToggleLog", Label = "Toggle event log", Default = "L" },
	{ Id = "Emote", Label = "Table emote", Default = "G" },
	{ Id = "Menu", Label = "Menu", Default = "M" },
}

-- Keys that may never be bound (system / chat / dev console).
SettingsSchema.ReservedKeys = {
	Escape = true,
	Slash = true,
	F9 = true,
	F11 = true,
	F12 = true,
	Backquote = true,
	Return = true,
	Unknown = true,
}

SettingsSchema.Fields = {
	-- Audio
	{ Key = "MasterVolume", Category = "Audio", Label = "MASTER", Type = "slider", Min = 0, Max = 1, Step = 0.05, Default = 0.8 },
	{ Key = "MusicVolume", Category = "Audio", Label = "MUSIC", Type = "slider", Min = 0, Max = 1, Step = 0.05, Default = 0.55 },
	{ Key = "EffectsVolume", Category = "Audio", Label = "EFFECTS", Type = "slider", Min = 0, Max = 1, Step = 0.05, Default = 0.9 },
	{ Key = "AmbienceVolume", Category = "Audio", Label = "AMBIENCE", Type = "slider", Min = 0, Max = 1, Step = 0.05, Default = 0.7 },
	{ Key = "VoiceVolume", Category = "Audio", Label = "VOICE & ANNOUNCER", Type = "slider", Min = 0, Max = 1, Step = 0.05, Default = 0.75 },
	{ Key = "InterfaceVolume", Category = "Audio", Label = "INTERFACE", Type = "slider", Min = 0, Max = 1, Step = 0.05, Default = 0.6 },
	{ Key = "Heartbeat", Category = "Audio", Label = "LOW-INTEGRITY HEARTBEAT", Type = "toggle", Default = true },
	-- Video
	{
		Key = "GraphicsQuality",
		Category = "Video",
		Label = "ENVIRONMENT QUALITY",
		Type = "choice",
		Options = { "Auto", "Low", "Medium", "High", "Ultra" },
		Default = "Auto",
	},
	{ Key = "FieldOfView", Category = "Video", Label = "FIELD OF VIEW", Type = "slider", Min = 55, Max = 85, Step = 1, Default = 68 },
	{ Key = "CameraShake", Category = "Video", Label = "CAMERA SHAKE", Type = "slider", Min = 0, Max = 1, Step = 0.05, Default = 0.7 },
	{
		Key = "Cinematics",
		Category = "Video",
		Label = "CINEMATIC CAMERA",
		Type = "choice",
		Options = { "Full", "Reduced", "Minimal" },
		Default = "Full",
	},
	{ Key = "Scanlines", Category = "Video", Label = "SCANLINES", Type = "toggle", Default = true },
	{ Key = "Vibration", Category = "Video", Label = "CONTROLLER VIBRATION", Type = "toggle", Default = true },
	-- Gameplay
	{ Key = "ProbabilityAssist", Category = "Gameplay", Label = "PROBABILITY READOUT", Type = "toggle", Default = true },
	{
		Key = "FireConfirm",
		Category = "Gameplay",
		Label = "FIRE CONFIRMATION",
		Type = "choice",
		Options = { "Hold", "Tap", "Confirm" },
		Default = "Hold",
	},
	{
		Key = "Dialogue",
		Category = "Gameplay",
		Label = "OPPONENT DIALOGUE",
		Type = "choice",
		Options = { "Full", "Brief", "Off" },
		Default = "Full",
	},
	{ Key = "Hints", Category = "Gameplay", Label = "CONTEXT HINTS", Type = "toggle", Default = true },
	{ Key = "ConfirmItems", Category = "Gameplay", Label = "CONFIRM RARE INSTRUMENTS", Type = "toggle", Default = true },
	-- Accessibility
	{ Key = "Subtitles", Category = "Accessibility", Label = "SUBTITLES", Type = "toggle", Default = true },
	{ Key = "ReducedFlashing", Category = "Accessibility", Label = "REDUCED FLASHING", Type = "toggle", Default = false },
	{ Key = "ReducedMotion", Category = "Accessibility", Label = "REDUCED MOTION", Type = "toggle", Default = false },
	{ Key = "HighContrast", Category = "Accessibility", Label = "HIGH-CONTRAST INTERFACE", Type = "toggle", Default = false },
	{
		Key = "Palette",
		Category = "Accessibility",
		Label = "CELL COLOURS",
		Type = "choice",
		Options = { "Default", "Deuteranopia", "Protanopia", "Tritanopia", "Monochrome" },
		Default = "Default",
	},
	{ Key = "UIScale", Category = "Accessibility", Label = "INTERFACE SCALE", Type = "slider", Min = 0.8, Max = 1.3, Step = 0.05, Default = 1 },
	{ Key = "TextScale", Category = "Accessibility", Label = "TEXT SIZE", Type = "slider", Min = 0.9, Max = 1.35, Step = 0.05, Default = 1 },
	-- Controls
	{ Key = "Sensitivity", Category = "Controls", Label = "LOOK SENSITIVITY", Type = "slider", Min = 0.2, Max = 2, Step = 0.05, Default = 1 },
	{ Key = "InvertY", Category = "Controls", Label = "INVERT LOOK Y", Type = "toggle", Default = false },
	{ Key = "Binds", Category = "Controls", Label = "KEY BINDINGS", Type = "binds", Default = {} },
}

SettingsSchema.ByKey = {}
for _, field in SettingsSchema.Fields do
	SettingsSchema.ByKey[field.Key] = field
end

function SettingsSchema.defaults(): { [string]: any }
	local out = {}
	for _, field in SettingsSchema.Fields do
		if type(field.Default) == "table" then
			out[field.Key] = table.clone(field.Default)
		else
			out[field.Key] = field.Default
		end
	end
	return out
end

-- Validates one value; returns the cleaned value or nil if it is invalid.
function SettingsSchema.clean(key: string, value: any, validKeyNames: { [string]: boolean }?): any
	local field = SettingsSchema.ByKey[key]
	if field == nil then
		return nil
	end
	if field.Type == "slider" then
		if type(value) ~= "number" or value ~= value then
			return nil
		end
		local stepped = math.floor((value - field.Min) / field.Step + 0.5) * field.Step + field.Min
		return math.clamp(stepped, field.Min, field.Max)
	elseif field.Type == "toggle" then
		if type(value) ~= "boolean" then
			return nil
		end
		return value
	elseif field.Type == "choice" then
		if type(value) ~= "string" or not table.find(field.Options, value) then
			return nil
		end
		return value
	elseif field.Type == "binds" then
		if type(value) ~= "table" then
			return nil
		end
		local out = {}
		local used = {}
		for _, action in SettingsSchema.Actions do
			local key = value[action.Id]
			if
				type(key) == "string"
				and #key <= 24
				and not SettingsSchema.ReservedKeys[key]
				and (validKeyNames == nil or validKeyNames[key])
				and not used[key]
			then
				out[action.Id] = key
				used[key] = true
			end
		end
		return out
	end
	return nil
end

-- Cleans a whole settings table (unknown keys dropped, invalid values defaulted).
function SettingsSchema.cleanAll(input: any, validKeyNames: { [string]: boolean }?): { [string]: any }
	local out = SettingsSchema.defaults()
	if type(input) ~= "table" then
		return out
	end
	for key in out do
		if input[key] ~= nil then
			local cleaned = SettingsSchema.clean(key, input[key], validKeyNames)
			if cleaned ~= nil then
				out[key] = cleaned
			end
		end
	end
	return out
end

return SettingsSchema

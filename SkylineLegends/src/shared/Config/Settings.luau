-- Player preferences: defaults, allowed ranges and input bindings.
-- The server validates saved settings against these definitions.

export type SettingDef = {
	Id: string,
	Name: string,
	Section: string,
	Kind: string, -- "Toggle" | "Slider" | "Choice"
	Default: any,
	Min: number?,
	Max: number?,
	Step: number?,
	Choices: { string }?,
	Hint: string?,
}

local defs: { SettingDef } = {
	-- Controls
	{
		Id = "SprintMode",
		Name = "Sprint",
		Section = "Controls",
		Kind = "Choice",
		Default = "Hold",
		Choices = { "Hold", "Toggle", "Auto" },
		Hint = "Auto sprints whenever you move (stamina still applies).",
	},
	{ Id = "CrouchToggle", Name = "Toggle Crouch", Section = "Controls", Kind = "Toggle", Default = false },
	{
		Id = "AutoVault",
		Name = "Auto Vault",
		Section = "Controls",
		Kind = "Toggle",
		Default = true,
		Hint = "Sprinting into low cover vaults it without pressing jump.",
	},
	{ Id = "MouseSensitivity", Name = "Mouse Sensitivity", Section = "Controls", Kind = "Slider", Default = 1, Min = 0.2, Max = 3, Step = 0.05 },
	{ Id = "PadSensitivity", Name = "Controller Sensitivity", Section = "Controls", Kind = "Slider", Default = 1, Min = 0.3, Max = 2.5, Step = 0.05 },
	{ Id = "TouchSensitivity", Name = "Touch Sensitivity", Section = "Controls", Kind = "Slider", Default = 1, Min = 0.3, Max = 2.5, Step = 0.05 },
	{ Id = "InvertY", Name = "Invert Camera Y", Section = "Controls", Kind = "Toggle", Default = false },
	{ Id = "TouchButtonScale", Name = "Touch Button Size", Section = "Controls", Kind = "Slider", Default = 1, Min = 0.7, Max = 1.5, Step = 0.05 },
	-- Camera and motion
	{ Id = "FieldOfView", Name = "Field of View", Section = "Camera", Kind = "Slider", Default = 72, Min = 60, Max = 95, Step = 1 },
	{
		Id = "ReducedMotion",
		Name = "Reduced Motion",
		Section = "Camera",
		Kind = "Toggle",
		Default = false,
		Hint = "Turns off every effect below at once.",
	},
	{ Id = "FovKick", Name = "Speed FOV", Section = "Camera", Kind = "Toggle", Default = true },
	{ Id = "CameraTilt", Name = "Wall Run Tilt", Section = "Camera", Kind = "Toggle", Default = true },
	{ Id = "CameraShake", Name = "Camera Shake", Section = "Camera", Kind = "Toggle", Default = true },
	{ Id = "SpeedLines", Name = "Speed Lines", Section = "Camera", Kind = "Toggle", Default = true },
	{ Id = "FlowEffects", Name = "Flow Screen Effects", Section = "Camera", Kind = "Toggle", Default = true },
	-- Interface and accessibility
	{ Id = "TextScale", Name = "Text Size", Section = "Interface", Kind = "Slider", Default = 1, Min = 0.8, Max = 1.5, Step = 0.05 },
	{ Id = "HudScale", Name = "HUD Size", Section = "Interface", Kind = "Slider", Default = 1, Min = 0.75, Max = 1.4, Step = 0.05 },
	{
		Id = "SurfaceIcons",
		Name = "Surface Icons",
		Section = "Interface",
		Kind = "Choice",
		Default = "Nearby",
		Choices = { "Off", "Nearby", "Always" },
		Hint = "Shape icons on climbable walls, beams, anchors and hazards, so nothing relies on colour.",
	},
	{ Id = "HighContrast", Name = "High Contrast Markers", Section = "Interface", Kind = "Toggle", Default = false },
	{ Id = "ShowFlow", Name = "Flow Meter While Exploring", Section = "Interface", Kind = "Toggle", Default = true },
	{ Id = "ShowSplits", Name = "Live Split Times", Section = "Interface", Kind = "Toggle", Default = true },
	{ Id = "ShowInputHints", Name = "Input Hints", Section = "Interface", Kind = "Toggle", Default = true },
	{
		Id = "DefaultGhost",
		Name = "Default Ghost",
		Section = "Interface",
		Kind = "Choice",
		Default = "Best",
		Choices = { "None", "Best", "Last", "Friend", "Top" },
	},
	-- Graphics
	{
		Id = "Quality",
		Name = "Detail Level",
		Section = "Graphics",
		Kind = "Choice",
		Default = "Auto",
		Choices = { "Auto", "Low", "Medium", "High" },
		Hint = "Scales decorations, particles and distant districts. Gameplay surfaces are never hidden.",
	},
	{ Id = "Weather", Name = "Weather Effects", Section = "Graphics", Kind = "Toggle", Default = true },
	{ Id = "DayCycle", Name = "Time of Day Cycle", Section = "Graphics", Kind = "Toggle", Default = true },
	{ Id = "Shadows", Name = "Shadows", Section = "Graphics", Kind = "Toggle", Default = true },
	{ Id = "Trails", Name = "Show Trails", Section = "Graphics", Kind = "Choice", Default = "All", Choices = { "All", "Mine", "None" } },
	-- Audio
	{ Id = "MasterVolume", Name = "Master Volume", Section = "Audio", Kind = "Slider", Default = 1, Min = 0, Max = 1, Step = 0.05 },
	{ Id = "MusicVolume", Name = "Music", Section = "Audio", Kind = "Slider", Default = 0.6, Min = 0, Max = 1, Step = 0.05 },
	{ Id = "SfxVolume", Name = "Effects", Section = "Audio", Kind = "Slider", Default = 0.85, Min = 0, Max = 1, Step = 0.05 },
	{ Id = "AmbientVolume", Name = "Ambience", Section = "Audio", Kind = "Slider", Default = 0.6, Min = 0, Max = 1, Step = 0.05 },
	{ Id = "CueVolume", Name = "Ability Cues", Section = "Audio", Kind = "Slider", Default = 0.7, Min = 0, Max = 1, Step = 0.05 },
}

-- Remappable actions. Default keys are KeyCode names; mouse buttons use
-- "MouseButton1"/"MouseButton2".
local actions = {
	{ Id = "Jump", Name = "Jump / Wall Jump", Keyboard = { "Space" }, Gamepad = { "ButtonA" } },
	{ Id = "Sprint", Name = "Sprint", Keyboard = { "LeftShift" }, Gamepad = { "ButtonL3", "ButtonL2" } },
	{ Id = "Crouch", Name = "Crouch / Slide / Roll", Keyboard = { "C", "LeftControl" }, Gamepad = { "ButtonB" } },
	{ Id = "Dash", Name = "Dash", Keyboard = { "Q" }, Gamepad = { "ButtonX" } },
	{ Id = "Grapple", Name = "Grapple", Keyboard = { "F", "MouseButton1" }, Gamepad = { "ButtonR2" } },
	{ Id = "Retry", Name = "Retry Checkpoint (hold: restart)", Keyboard = { "R" }, Gamepad = { "DPadDown" } },
	{ Id = "Menu", Name = "Menu", Keyboard = { "M" }, Gamepad = { "DPadUp" } },
	{ Id = "Map", Name = "Map", Keyboard = { "Tab" }, Gamepad = { "DPadRight" } },
	{ Id = "Journal", Name = "Quest Journal", Keyboard = { "J" }, Gamepad = {} },
	{ Id = "Emote", Name = "Emotes", Keyboard = { "G" }, Gamepad = { "DPadLeft" } },
	{ Id = "Pin", Name = "Cycle Pinned Objective", Keyboard = { "T" }, Gamepad = { "ButtonR3" } },
}

local Settings = {}
Settings.Definitions = defs
Settings.ById = {} :: { [string]: SettingDef }
for _, def in defs do
	Settings.ById[def.Id] = def
end
Settings.Actions = actions
Settings.ActionById = {}
for _, action in actions do
	Settings.ActionById[action.Id] = action
end
Settings.Sections = { "Controls", "Camera", "Interface", "Graphics", "Audio" }

function Settings.Defaults(): { [string]: any }
	local result = {}
	for _, def in defs do
		result[def.Id] = def.Default
	end
	return result
end

-- Clamp/validate one value; returns nil if invalid.
function Settings.Sanitize(id: string, value: any): any
	local def = Settings.ById[id]
	if not def then
		return nil
	end
	if def.Kind == "Toggle" then
		return if type(value) == "boolean" then value else nil
	elseif def.Kind == "Slider" then
		if type(value) ~= "number" or value ~= value then
			return nil
		end
		return math.clamp(value, def.Min or 0, def.Max or 1)
	elseif def.Kind == "Choice" then
		if type(value) == "string" and def.Choices and table.find(def.Choices, value) then
			return value
		end
		return nil
	end
	return nil
end

-- Validate a bindings table: { [actionId] = { Keyboard = {names}, Gamepad = {names} } }.
function Settings.SanitizeBindings(bindings: any): { [string]: any }?
	if type(bindings) ~= "table" then
		return nil
	end
	local result = {}
	for actionId, entry in bindings do
		if Settings.ActionById[actionId] and type(entry) == "table" then
			local clean = { Keyboard = {}, Gamepad = {} }
			for _, device in { "Keyboard", "Gamepad" } do
				local list = entry[device]
				if type(list) == "table" then
					for i = 1, math.min(#list, 3) do
						local name = list[i]
						if type(name) == "string" and #name <= 24 and string.match(name, "^%w+$") then
							table.insert(clean[device], name)
						end
					end
				end
			end
			result[actionId] = clean
		end
	end
	return result
end

return Settings

-- Player settings: graphics quality, reduced motion, Easy Capture, auto-open
-- cores and volumes. Changes apply instantly on this client and are sent to
-- the server (debounced), which validates and saves them with the profile.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local RemoteDefinitions = require(Shared.RemoteDefinitions)
local Signal = require(Shared.Signal)

local SettingsController = {}

SettingsController.QualityChanged = Signal.new()

local controllers: { [string]: any } = {}
local local_: { [string]: any } = {}
local saveScheduled = false
local presetName = "High"

function SettingsController.Get(key: string): any
	return local_[key]
end

-- The active graphics preset table (Low / Medium / High).
function SettingsController.Quality(): { [string]: any }
	return GameConfig.Graphics.Presets[presetName]
end

function SettingsController.QualityName(): string
	return presetName
end

function SettingsController.ReducedMotion(): boolean
	return local_.ReducedMotion == true
end

local function resolvePreset(choice: string?): string
	if choice == "Low" or choice == "Medium" or choice == "High" then
		return choice
	end
	-- Auto: phones and tablets start on Medium, computers on High.
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Medium"
	end
	return "High"
end

local function apply()
	controllers.Components.ReducedMotion = local_.ReducedMotion == true
	local previous = presetName
	presetName = resolvePreset(local_.GraphicsQuality)
	local preset = GameConfig.Graphics.Presets[presetName]
	for _, name in { "Bloom", "SunRays" } do
		local effect = Lighting:FindFirstChild(name)
		if effect and effect:IsA("PostEffect") then
			effect.Enabled = preset.PostProcessing
		end
	end
	if previous ~= presetName then
		SettingsController.QualityChanged:Fire(presetName)
	end
end

function SettingsController.Set(key: string, value: any)
	local_[key] = value
	apply()
	controllers.AudioController.SetVolumes(local_)
	if saveScheduled then
		return
	end
	saveScheduled = true
	task.delay(1, function()
		saveScheduled = false
		local payload = {}
		for name in RemoteDefinitions.SettingsSchema do
			if local_[name] ~= nil then
				payload[name] = local_[name]
			end
		end
		RemoteDefinitions.GetEvent("UpdateSettings"):FireServer(payload)
	end)
end

-- Builds the settings panel inside a Components.Panel body.
function SettingsController.BuildPanel(body: Frame)
	local Components = controllers.Components
	local scroll = Components.Make("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Components.Colors.Stroke,
		Parent = body,
	})
	Components.List(Enum.FillDirection.Vertical, 10).Parent = scroll
	Components.Padding(4, 8).Parent = scroll

	local function heading(text: string, order: number)
		Components.Label({
			Text = text,
			Font = Components.Fonts.Display,
			TextSize = 20,
			TextColor3 = Components.Colors.Lavender,
			LayoutOrder = order,
			Parent = scroll,
		})
	end
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	heading("Audio", nextOrder())
	for _, spec in { { "MusicVolume", "Music" }, { "EffectsVolume", "Effects" }, { "AmbientVolume", "Ambience" } } do
		local row = Components.Stepper(spec[2], local_[spec[1]] or 0.7, 0.1, function(value)
			SettingsController.Set(spec[1], value)
		end, scroll)
		row.LayoutOrder = nextOrder()
	end

	heading("Gameplay", nextOrder())
	Components.Toggle(
		"Easy Capture",
		"Wider, slower stabilization zones. Perfect rank isn't available in this mode. Creature odds are never affected.",
		local_.EasyCapture == true,
		function(value)
			SettingsController.Set("EasyCapture", value)
		end,
		scroll
	).LayoutOrder =
		nextOrder()
	Components.Toggle(
		"Open cores automatically",
		"Reveal what's inside right after a capture.",
		local_.AutoOpenCores ~= false,
		function(value)
			SettingsController.Set("AutoOpenCores", value)
		end,
		scroll
	).LayoutOrder =
		nextOrder()

	heading("Comfort & Graphics", nextOrder())
	Components.Toggle(
		"Reduced motion",
		"Less camera shake, fewer flashes and shorter animations.",
		local_.ReducedMotion == true,
		function(value)
			SettingsController.Set("ReducedMotion", value)
		end,
		scroll
	).LayoutOrder =
		nextOrder()

	local qualityRow = Components.Make(
		"Frame",
		{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = nextOrder(), Parent = scroll }
	)
	Components.Label({ Text = "Graphics quality", Size = UDim2.new(0.42, 0, 1, 0), Parent = qualityRow })
	local options = { "Auto", "Low", "Medium", "High" }
	local holder = Components.Make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0.58, 0, 1, 0),
		Position = UDim2.fromScale(0.42, 0),
		Parent = qualityRow,
	})
	Components.List(Enum.FillDirection.Horizontal, 6).Parent = holder
	local buttons = {}
	local function render()
		for name, button in buttons do
			button:SetStyle(if (local_.GraphicsQuality or "Auto") == name then "Primary" else "Secondary")
		end
	end
	for i, name in options do
		local button = Components.Button(name, "Secondary", UDim2.new(0.25, -5, 0, 38), holder)
		button.Instance.LayoutOrder = i
		buttons[name] = button
		button.Activated:Connect(function()
			SettingsController.Set("GraphicsQuality", name)
			render()
		end)
	end
	render()

	Components.Label({
		Text = `Catch a Comet! v{GameConfig.Version}`,
		Font = Components.Fonts.Body,
		TextSize = 13,
		TextColor3 = Components.Colors.Dim,
		LayoutOrder = nextOrder(),
		Parent = scroll,
	})
end

function SettingsController.Init(registry: { [string]: any })
	controllers = registry
end

function SettingsController.Start()
	local settings = controllers.ClientState.Settings()
	for key, value in settings do
		local_[key] = value
	end
	apply()
end

return SettingsController

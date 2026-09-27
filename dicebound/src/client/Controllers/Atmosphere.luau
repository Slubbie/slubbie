-- Re-tints the (local) lighting to match the region you're standing in. Purely visual.

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local ClientState = require(script.Parent.Parent.ClientState)

local Atmosphere = {}

local rgb = Color3.fromRGB

local PRESETS = {
	meadow = {
		Lighting = {
			ClockTime = 15.2,
			Brightness = 2.4,
			Ambient = rgb(90, 80, 70),
			OutdoorAmbient = rgb(150, 140, 125),
		},
		Air = { Density = 0.28, Color = rgb(255, 236, 205), Decay = rgb(150, 180, 230), Haze = 1.2 },
		Tint = rgb(255, 250, 240),
	},
	crystal = {
		Lighting = { ClockTime = 20.5, Brightness = 1.2, Ambient = rgb(90, 70, 130), OutdoorAmbient = rgb(90, 80, 140) },
		Air = { Density = 0.42, Color = rgb(150, 120, 220), Decay = rgb(60, 40, 110), Haze = 2 },
		Tint = rgb(235, 225, 255),
	},
	frost = {
		Lighting = {
			ClockTime = 17.4,
			Brightness = 2,
			Ambient = rgb(110, 125, 150),
			OutdoorAmbient = rgb(160, 180, 210),
		},
		Air = { Density = 0.36, Color = rgb(215, 230, 255), Decay = rgb(120, 150, 200), Haze = 2.2 },
		Tint = rgb(235, 245, 255),
	},
	ember = {
		Lighting = { ClockTime = 18.3, Brightness = 1.6, Ambient = rgb(120, 70, 50), OutdoorAmbient = rgb(150, 90, 70) },
		Air = { Density = 0.4, Color = rgb(255, 170, 120), Decay = rgb(120, 50, 30), Haze = 2.4 },
		Tint = rgb(255, 235, 220),
	},
	astral = {
		Lighting = {
			ClockTime = 0.2,
			Brightness = 1.4,
			Ambient = rgb(90, 80, 150),
			OutdoorAmbient = rgb(120, 110, 190),
		},
		Air = { Density = 0.2, Color = rgb(170, 150, 255), Decay = rgb(40, 30, 90), Haze = 0.8 },
		Tint = rgb(240, 235, 255),
	},
}

function Atmosphere.Apply(regionId: string?)
	local preset = PRESETS[regionId or "meadow"] or PRESETS.meadow
	local info = TweenInfo.new(1.5, Enum.EasingStyle.Sine)
	TweenService:Create(Lighting, info, preset.Lighting):Play()
	local air = Lighting:FindFirstChildOfClass("Atmosphere")
	if air then
		TweenService:Create(air, info, preset.Air):Play()
	end
	local grade = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if grade then
		TweenService:Create(grade, info, { TintColor = preset.Tint }):Play()
	end
end

function Atmosphere.Start()
	task.spawn(function()
		local current = nil
		while true do
			local region = ClientState.CurrentRegion()
			local id = region and region.Id
			if id and id ~= current then
				current = id
				Atmosphere.Apply(id)
			end
			task.wait(0.5)
		end
	end)
end

return Atmosphere

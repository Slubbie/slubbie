-- Client controller locator (mirrors the server's service locator).
--
-- Controllers are ModuleScripts in this folder returning a table with optional
-- Init() and Start(). They reach each other at call time through this table
-- (C.State.Get(...)), so require order never matters and there are no cycles.
--
--   local C = require(script.Parent)

local Controllers = {}

local NAMES = {
	State = "StateController",
	Settings = "SettingsController",
	Audio = "AudioController",
	UI = "UIController",
	Windows = "WindowController",
	Notify = "NotificationController",
	HUD = "HUDController",
	Input = "InputController",
	Camera = "CameraController",
	Lighting = "LightingController",
	Crops = "CropRenderer",
	Animals = "AnimalRenderer",
	Gather = "GatherRenderer",
	FX = "FXController",
	Animation = "AnimationController",
	NPC = "NPCController",
	Fishing = "FishingController",
	Build = "BuildController",
	Prompts = "PromptController",
	Tutorial = "TutorialController",
	Photo = "PhotoController",
}

Controllers.Order = {
	"State",
	"Settings",
	"UI",
	"Audio",
	"Windows",
	"Notify",
	"Lighting",
	"Camera",
	"Animation",
	"Crops",
	"Animals",
	"Gather",
	"FX",
	"NPC",
	"Prompts",
	"Input",
	"Fishing",
	"Build",
	"HUD",
	"Tutorial",
	"Photo",
}

local loaded: { [string]: any } = {}

setmetatable(Controllers, {
	__index = function(_, key)
		local cached = loaded[key]
		if cached then
			return cached
		end
		local moduleName = NAMES[key]
		if not moduleName then
			error("Unknown controller '" .. tostring(key) .. "'", 2)
		end
		local module = script:FindFirstChild(moduleName)
		assert(module and module:IsA("ModuleScript"), "Missing controller module " .. moduleName)
		local controller = (require :: any)(module)
		loaded[key] = controller
		return controller
	end,
})

function Controllers.Boot()
	for _, phase in { "Init", "Start" } do
		for _, key in Controllers.Order do
			local controller = Controllers[key]
			if type(controller[phase]) == "function" then
				local ok, err = pcall(controller[phase])
				if not ok then
					warn(string.format("[Evergrove] %s.%s failed: %s", key, phase, tostring(err)))
				end
			end
		end
	end
end

return Controllers

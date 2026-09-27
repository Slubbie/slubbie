-- VARIANCE client bootstrap.
--
-- Loads every ModuleScript in Controllers/, calls Init(controllers) on each in
-- a fixed order (no yielding), then Start() on each in its own thread.
-- Controllers reach each other through the shared table at call time.

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local ORDER = {
	"NetworkClient",
	"SettingsController",
	"ProfileController",
	"InputController",
	"AudioController",
	"UIController",
	"EnvironmentController",
	"VFXController",
	"AnimationController",
	"WeaponController",
	"CameraController",
	"MatchClient",
	"MatchPresenter",
	"LobbyController",
	"TutorialController",
	"SpectatorController",
	"DebugController",
}

-- The default health bar and backpack have no place in the Institute.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local folder = script:WaitForChild("Controllers")
local controllers = {}
for _, module in folder:GetChildren() do
	if module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok then
			controllers[module.Name] = result
		else
			warn("[VARIANCE] failed to load " .. module.Name .. ": " .. tostring(result))
		end
	end
end

for _, name in ORDER do
	local controller = controllers[name]
	if controller and controller.Init then
		local ok, err = pcall(controller.Init, controller, controllers)
		if not ok then
			warn("[VARIANCE] " .. name .. ".Init failed: " .. tostring(err))
		end
	elseif controller == nil then
		warn("[VARIANCE] missing controller " .. name)
	end
end

for _, name in ORDER do
	local controller = controllers[name]
	if controller and controller.Start then
		task.spawn(function()
			local ok, err = pcall(controller.Start, controller)
			if not ok then
				warn("[VARIANCE] " .. name .. ".Start failed: " .. tostring(err))
			end
		end)
	end
end

Players.LocalPlayer:SetAttribute("VarianceClientReady", true)

-- The screen layers every interface module draws into.

local Players = game:GetService("Players")

local Settings = require(script.Parent.Parent.Core.Settings)

local Root = {}

Root.Hud = nil :: ScreenGui?
Root.Menu = nil :: ScreenGui?
Root.Overlay = nil :: ScreenGui?
Root.Touch = nil :: ScreenGui?

local function gui(name: string, order: number, inset: boolean): ScreenGui
	local screen = Instance.new("ScreenGui")
	screen.Name = name
	screen.DisplayOrder = order
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = inset
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return screen
end

function Root.Get(name: string): ScreenGui
	local screen = (Root :: any)[name]
	assert(screen, "UI layer " .. name .. " not started")
	return screen
end

function Root.Start()
	Root.Touch = gui("SkylineTouch", 4, true)
	Root.Hud = gui("SkylineHud", 5, true)
	Root.Menu = gui("SkylineMenu", 10, true)
	Root.Overlay = gui("SkylineOverlay", 20, true)
	-- HUD size follows its setting.
	local scale = Instance.new("UIScale")
	scale.Scale = Settings.Get("HudScale") or 1
	scale.Parent = Root.Hud
	Settings.Changed:Connect(function(id, value)
		if id == "HudScale" and type(value) == "number" then
			scale.Scale = value
		end
	end)
end

return Root

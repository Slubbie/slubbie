-- The interface root: one ScreenGui with layers (World → HUD → Windows →
-- Overlay → Modal), responsive scaling for phones, tablets, PCs and TVs, and
-- live theme / accessibility settings.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local C = require(script.Parent)
local UIFolder = script.Parent.Parent:WaitForChild("UI")
local Kit = require(UIFolder.Kit)
local Theme = require(UIFolder.Theme)

local UI = {}
UI.Kit = Kit
UI.Theme = Theme

local gui: ScreenGui
local layers: { [string]: Frame } = {}
local scales: { UIScale } = {}

local LAYERS = { "World", "HUD", "Windows", "Overlay", "Modal" }

function UI.Layer(name: string): Frame
	return layers[name]
end

function UI.Root(): ScreenGui
	return gui
end

-- Device class for layout decisions.
function UI.Device(): string
	local viewport = workspace.CurrentCamera.ViewportSize
	if GuiService:IsTenFootInterface() then
		return "Console"
	elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return if math.min(viewport.X, viewport.Y) < 500 then "Phone" else "Tablet"
	end
	return "Desktop"
end

function UI.IsCompact(): boolean
	local device = UI.Device()
	return device == "Phone"
end

-- Scale so a 1280×720 layout fits, then apply the player's Interface Scale.
local function rescale()
	local viewport = workspace.CurrentCamera.ViewportSize
	local base = math.min(viewport.X / 1280, viewport.Y / 720)
	local device = UI.Device()
	if device == "Phone" then
		base = math.max(base, 0.55) * 1.1
	elseif device == "Console" then
		base *= 1.15
	end
	local scale = math.clamp(base, 0.5, 1.6) * (C.Settings.Get("UIScale") or 1)
	for _, s in scales do
		s.Scale = scale
	end
	UI.Scale = scale
end

-- Size of the usable area in layout units (after scaling).
function UI.LayoutSize(): Vector2
	local viewport = workspace.CurrentCamera.ViewportSize
	return viewport / (UI.Scale or 1)
end

local function applyTheme()
	local S = C.Settings
	local name = S.Get("UITheme")
	-- Cosmetic themes must be owned; Grove is always available.
	local owned = C.State.Get("Cosmetics", "Owned") or {}
	local cosmeticId = "ui_" .. string.lower(name or "grove")
	if name ~= "Grove" and not owned[cosmeticId] then
		name = "Grove"
	end
	Theme.Set(name, S.Get("HighContrast"), S.Get("Colorblind"), S.Get("TextScale"))
	Kit.ReducedMotion = S.Get("ReducedMotion") == true
	Kit.SimpleUI = S.Get("SimpleUI") == true
	Kit.Retheme()
	if gui then
		Kit.RepaintGradients(gui)
	end
end
UI.ApplyTheme = applyTheme

function UI.Init()
	local player = Players.LocalPlayer
	gui = Instance.new("ScreenGui")
	gui.Name = "Evergrove"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 5
	for i, name in LAYERS do
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.BackgroundTransparency = 1
		frame.Size = UDim2.fromScale(1, 1)
		frame.ZIndex = i * 10
		frame.Parent = gui
		local s = Instance.new("UIScale")
		s.Parent = frame
		table.insert(scales, s)
		-- Children are laid out in unscaled units: grow the frame to compensate.
		s:GetPropertyChangedSignal("Scale"):Connect(function()
			frame.Size = UDim2.fromScale(1 / s.Scale, 1 / s.Scale)
		end)
		layers[name] = frame
	end
	gui.Parent = player:WaitForChild("PlayerGui")
	Kit.TooltipLayer = layers.Overlay
	Kit.ModalLayer = layers.Modal
	Kit.PlaySound = function(name: string)
		C.Audio.PlayUI(name)
	end
	require(UIFolder.Picker).GetProfile = function()
		return C.State.Data()
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	C.Settings.Changed:Connect(function(key)
		if key == "UIScale" then
			rescale()
		elseif key == "UITheme" or key == "HighContrast" or key == "Colorblind" or key == "TextScale" or key == "ReducedMotion" or key == "SimpleUI" then
			applyTheme()
		end
	end)
	applyTheme()
end

function UI.Start()
	C.State.Watch("Cosmetics", function()
		applyTheme()
	end)
end

return UI

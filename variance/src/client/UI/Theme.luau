-- Visual language of the interface: an industrial, analog-digital test lab.
-- Restrained charcoal panels, bone text, a single amber accent, and signal
-- colours reserved for the two cell types. Cell types are never shown by colour
-- alone: CHARGED is a filled diamond, HOLLOW an open ring (see Kit.glyph).
--
-- Palettes swap the cell colours for colour-vision needs; High Contrast
-- brightens text and outlines. Components register themed properties with
-- Theme.bind so a settings change recolours live UI without rebuilding it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Variance.Util.Signal)

local Theme = {}
Theme.Changed = Signal.new()

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

local BASE = {
	Bg = hex("0b0c0e"),
	Panel = hex("121417"),
	PanelAlt = hex("191c20"),
	Raised = hex("22262b"),
	Line = hex("2d3237"),
	LineStrong = hex("454c53"),
	Text = hex("e7e3d6"),
	Dim = hex("8e9397"),
	Faint = hex("5a6065"),
	Accent = hex("e8a33d"),
	AccentDim = hex("7a5a26"),
	Good = hex("7fd1ae"),
	Warn = hex("e8a33d"),
	Bad = hex("e0482f"),
	Focus = hex("f2c14e"),
	Shadow = hex("000000"),
}

Theme.Palettes = {
	Default = { Charged = hex("e0482f"), Hollow = hex("cfe3de"), ChargedText = hex("ffd9cf"), HollowText = hex("0e1413") },
	Deuteranopia = { Charged = hex("f2a03d"), Hollow = hex("5aa9e6"), ChargedText = hex("1a1206"), HollowText = hex("06121a") },
	Protanopia = { Charged = hex("f5c542"), Hollow = hex("4f8fd6"), ChargedText = hex("1a1506"), HollowText = hex("06101a") },
	Tritanopia = { Charged = hex("e8407a"), Hollow = hex("62d0c4"), ChargedText = hex("1a0610"), HollowText = hex("061a17") },
	Monochrome = { Charged = hex("f4f4f4"), Hollow = hex("7c7c7c"), ChargedText = hex("111111"), HollowText = hex("f4f4f4") },
}

Theme.Colors = table.clone(BASE)
for k, v in Theme.Palettes.Default do
	Theme.Colors[k] = v
end

local function font(name: string, fallback: Enum.Font): Enum.Font
	local ok, value = pcall(function()
		return (Enum.Font :: any)[name]
	end)
	if ok and value then
		return value
	end
	return fallback
end

Theme.Fonts = {
	Display = font("Michroma", Enum.Font.GothamBlack),
	Mono = font("RobotoMono", Enum.Font.Code),
	Body = font("GothamMedium", Enum.Font.SourceSans),
	Bold = font("GothamBold", Enum.Font.SourceSansBold),
	Type = font("SpecialElite", Enum.Font.Code),
}

Theme.TextScale = 1
Theme.HighContrast = false
Theme.ReducedMotion = false
Theme.PaletteName = "Default"

-- Text sizes (pixels, before UIScale).
Theme.Size = {
	Tiny = 12,
	Small = 14,
	Body = 16,
	Label = 13,
	Title = 22,
	Heading = 30,
	Banner = 48,
}

function Theme.textSize(key: string): number
	return math.floor((Theme.Size[key] or 16) * Theme.TextScale + 0.5)
end

-- Live binding of an instance property to a colour key.
local bindings = setmetatable({}, { __mode = "k" })

function Theme.bind(instance: Instance, property: string, key: string)
	bindings[instance] = bindings[instance] or {}
	bindings[instance][property] = key
	;(instance :: any)[property] = Theme.Colors[key]
	return instance
end

function Theme.apply(settings: { [string]: any })
	local palette = Theme.Palettes[settings.Palette or "Default"] or Theme.Palettes.Default
	Theme.PaletteName = settings.Palette or "Default"
	Theme.HighContrast = settings.HighContrast == true
	Theme.TextScale = settings.TextScale or 1
	Theme.ReducedMotion = settings.ReducedMotion == true
	local colors = table.clone(BASE)
	for k, v in palette do
		colors[k] = v
	end
	if Theme.HighContrast then
		colors.Text = hex("ffffff")
		colors.Dim = hex("c9ccce")
		colors.Faint = hex("9aa0a5")
		colors.Line = hex("7a8288")
		colors.LineStrong = hex("d0d4d6")
		colors.Panel = hex("050506")
		colors.PanelAlt = hex("0c0d0f")
		colors.Accent = hex("ffc04d")
	end
	Theme.Colors = colors
	for instance, props in bindings do
		if instance.Parent ~= nil then
			for property, key in props do
				pcall(function()
					(instance :: any)[property] = colors[key]
				end)
			end
		end
	end
	Theme.Changed:Fire()
end

-- Tween durations shrink to near-instant with reduced motion.
function Theme.duration(seconds: number): number
	if Theme.ReducedMotion then
		return math.min(seconds, 0.08)
	end
	return seconds
end

return Theme

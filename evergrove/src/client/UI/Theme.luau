-- Interface palettes, fonts and sizes. The active palette follows the
-- "UITheme" setting (extra themes are cosmetics) and High Contrast mode.
-- Rarity/quality colours follow Colour-blind mode; every rarity and quality
-- also has a glyph/star count so nothing relies on colour alone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Quality = require(Shared.Config.Quality)

local Theme = {}

local rgb = Color3.fromRGB

export type Palette = {
	Panel: Color3,
	PanelAlt: Color3,
	Inset: Color3,
	HeaderA: Color3,
	HeaderB: Color3,
	HeaderText: Color3,
	Text: Color3,
	SubText: Color3,
	Stroke: Color3,
	Accent: Color3,
	AccentText: Color3,
	Good: Color3,
	Bad: Color3,
	Warn: Color3,
	Info: Color3,
	Shadow: Color3,
	Slot: Color3,
	SlotHover: Color3,
	Leaf: Color3,
}

Theme.Palettes = {
	Grove = {
		Panel = rgb(250, 245, 232),
		PanelAlt = rgb(240, 232, 212),
		Inset = rgb(228, 218, 194),
		HeaderA = rgb(112, 170, 98),
		HeaderB = rgb(72, 128, 74),
		HeaderText = rgb(255, 252, 240),
		Text = rgb(62, 48, 34),
		SubText = rgb(120, 102, 82),
		Stroke = rgb(196, 176, 136),
		Accent = rgb(232, 178, 66),
		AccentText = rgb(70, 48, 20),
		Good = rgb(92, 170, 88),
		Bad = rgb(206, 84, 70),
		Warn = rgb(228, 156, 56),
		Info = rgb(86, 150, 206),
		Shadow = rgb(30, 24, 16),
		Slot = rgb(236, 226, 202),
		SlotHover = rgb(246, 238, 216),
		Leaf = rgb(96, 150, 80),
	},
	Cottage = {
		Panel = rgb(253, 246, 240),
		PanelAlt = rgb(246, 232, 226),
		Inset = rgb(236, 218, 212),
		HeaderA = rgb(226, 150, 160),
		HeaderB = rgb(190, 112, 130),
		HeaderText = rgb(255, 250, 246),
		Text = rgb(84, 52, 56),
		SubText = rgb(140, 104, 108),
		Stroke = rgb(222, 184, 180),
		Accent = rgb(150, 196, 150),
		AccentText = rgb(40, 70, 40),
		Good = rgb(110, 176, 110),
		Bad = rgb(206, 90, 90),
		Warn = rgb(226, 160, 80),
		Info = rgb(120, 150, 210),
		Shadow = rgb(50, 30, 30),
		Slot = rgb(244, 228, 222),
		SlotHover = rgb(250, 238, 232),
		Leaf = rgb(150, 190, 140),
	},
	Celestial = {
		Panel = rgb(30, 34, 64),
		PanelAlt = rgb(40, 46, 84),
		Inset = rgb(22, 26, 50),
		HeaderA = rgb(80, 70, 150),
		HeaderB = rgb(44, 40, 100),
		HeaderText = rgb(255, 236, 180),
		Text = rgb(232, 230, 255),
		SubText = rgb(170, 170, 210),
		Stroke = rgb(120, 110, 190),
		Accent = rgb(250, 210, 110),
		AccentText = rgb(40, 30, 10),
		Good = rgb(120, 220, 170),
		Bad = rgb(250, 110, 130),
		Warn = rgb(250, 190, 90),
		Info = rgb(140, 190, 255),
		Shadow = rgb(4, 4, 14),
		Slot = rgb(46, 52, 94),
		SlotHover = rgb(60, 68, 116),
		Leaf = rgb(150, 140, 240),
	},
	Parchment = {
		Panel = rgb(243, 230, 200),
		PanelAlt = rgb(232, 214, 176),
		Inset = rgb(218, 196, 154),
		HeaderA = rgb(160, 120, 76),
		HeaderB = rgb(120, 86, 52),
		HeaderText = rgb(255, 246, 222),
		Text = rgb(70, 50, 28),
		SubText = rgb(126, 96, 62),
		Stroke = rgb(170, 132, 88),
		Accent = rgb(176, 70, 50),
		AccentText = rgb(255, 240, 220),
		Good = rgb(96, 140, 70),
		Bad = rgb(170, 60, 40),
		Warn = rgb(200, 130, 40),
		Info = rgb(80, 120, 160),
		Shadow = rgb(40, 24, 10),
		Slot = rgb(230, 212, 172),
		SlotHover = rgb(240, 224, 190),
		Leaf = rgb(120, 130, 70),
	},
	Midnight = {
		Panel = rgb(34, 38, 44),
		PanelAlt = rgb(44, 49, 57),
		Inset = rgb(26, 29, 34),
		HeaderA = rgb(60, 110, 90),
		HeaderB = rgb(36, 72, 60),
		HeaderText = rgb(236, 250, 240),
		Text = rgb(230, 234, 236),
		SubText = rgb(160, 170, 176),
		Stroke = rgb(80, 90, 98),
		Accent = rgb(110, 210, 170),
		AccentText = rgb(10, 40, 30),
		Good = rgb(110, 210, 140),
		Bad = rgb(240, 110, 100),
		Warn = rgb(240, 180, 80),
		Info = rgb(110, 170, 240),
		Shadow = rgb(0, 0, 0),
		Slot = rgb(48, 54, 62),
		SlotHover = rgb(60, 67, 77),
		Leaf = rgb(110, 190, 150),
	},
	Sakura = {
		Panel = rgb(255, 245, 248),
		PanelAlt = rgb(252, 230, 238),
		Inset = rgb(246, 214, 226),
		HeaderA = rgb(240, 150, 186),
		HeaderB = rgb(208, 100, 150),
		HeaderText = rgb(255, 250, 252),
		Text = rgb(90, 44, 66),
		SubText = rgb(150, 100, 124),
		Stroke = rgb(236, 180, 204),
		Accent = rgb(120, 170, 110),
		AccentText = rgb(30, 60, 30),
		Good = rgb(110, 176, 110),
		Bad = rgb(210, 80, 100),
		Warn = rgb(230, 150, 80),
		Info = rgb(130, 140, 220),
		Shadow = rgb(60, 20, 40),
		Slot = rgb(250, 226, 236),
		SlotHover = rgb(255, 238, 244),
		Leaf = rgb(240, 160, 190),
	},
}

local HIGH_CONTRAST: Palette = {
	Panel = rgb(255, 255, 255),
	PanelAlt = rgb(240, 240, 240),
	Inset = rgb(225, 225, 225),
	HeaderA = rgb(0, 0, 0),
	HeaderB = rgb(0, 0, 0),
	HeaderText = rgb(255, 255, 255),
	Text = rgb(0, 0, 0),
	SubText = rgb(40, 40, 40),
	Stroke = rgb(0, 0, 0),
	Accent = rgb(255, 210, 0),
	AccentText = rgb(0, 0, 0),
	Good = rgb(0, 130, 0),
	Bad = rgb(190, 0, 0),
	Warn = rgb(180, 100, 0),
	Info = rgb(0, 80, 200),
	Shadow = rgb(0, 0, 0),
	Slot = rgb(235, 235, 235),
	SlotHover = rgb(255, 255, 200),
	Leaf = rgb(0, 110, 0),
}

Theme.Fonts = {
	Heading = Enum.Font.FredokaOne,
	Body = Enum.Font.GothamMedium,
	Bold = Enum.Font.GothamBold,
	Number = Enum.Font.GothamBold,
}

Theme.Sizes = {
	Corner = 12,
	SmallCorner = 8,
	Stroke = 2,
	Title = 26,
	Heading = 20,
	Body = 16,
	Small = 13,
	Tiny = 11,
	Slot = 64,
	Pad = 10,
}

Theme.Current = Theme.Palettes.Grove :: Palette
Theme.Name = "Grove"
Theme.TextScale = 1
Theme.Colorblind = "Off"
Theme.HighContrast = false

function Theme.Set(name: string?, highContrast: boolean?, colorblind: string?, textScale: number?)
	if name and Theme.Palettes[name] then
		Theme.Name = name
	end
	if highContrast ~= nil then
		Theme.HighContrast = highContrast
	end
	if colorblind then
		Theme.Colorblind = colorblind
	end
	if textScale then
		Theme.TextScale = textScale
	end
	Theme.Current = if Theme.HighContrast then HIGH_CONTRAST else Theme.Palettes[Theme.Name]
end

function Theme.Text(size: number): number
	return math.floor(size * Theme.TextScale + 0.5)
end

function Theme.Rarity(id: string?)
	return Quality.Rarities[id or "Common"] or Quality.Rarities.Common
end

function Theme.RarityColor(id: string?): Color3
	if Theme.Colorblind ~= "Off" then
		return Quality.ColorblindRarity[id or "Common"] or Quality.ColorblindRarity.Common
	end
	return Theme.Rarity(id).Color
end

function Theme.QualityTier(tier: number?)
	return Quality.Tiers[math.clamp(tier or 1, 1, #Quality.Tiers)]
end

function Theme.QualityColor(tier: number?): Color3
	return Theme.QualityTier(tier).Color
end

return Theme

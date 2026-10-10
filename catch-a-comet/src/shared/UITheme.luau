--!strict
-- The interface design system: palette, type, radii and motion. Every screen
-- styles itself from these tokens so the game reads as one product.

local RarityConfig = require(script.Parent.RarityConfig)

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

local UITheme = {}

UITheme.Colors = {
	Background = hex("#0B1028"),
	Panel = hex("#18203E"),
	PanelRaised = hex("#212B52"),
	PanelSunken = hex("#121933"),
	Stroke = hex("#34407A"),
	Cyan = hex("#74E5FE"),
	Lavender = hex("#B69CFF"),
	Gold = hex("#FFCF70"),
	Green = hex("#7DE3AA"),
	Coral = hex("#FF7E98"),
	Text = hex("#F5F7FF"),
	Muted = hex("#A9B2D6"),
	Dim = hex("#6B76A6"),
	Black = hex("#05070F"),
	White = hex("#FFFFFF"),
}

UITheme.Fonts = {
	Display = Enum.Font.FredokaOne, -- playful headings and big numbers
	Heading = Enum.Font.BuilderSansExtraBold,
	Bold = Enum.Font.BuilderSansBold,
	Body = Enum.Font.BuilderSansMedium,
}

UITheme.TextSize = {
	Hero = 44,
	Title = 30,
	Heading = 22,
	Body = 18,
	Small = 15,
	Tiny = 13,
}

UITheme.Radius = {
	Small = 8,
	Medium = 14,
	Large = 20,
	Pill = 999,
}

UITheme.Motion = {
	Fast = 0.12,
	Normal = 0.22,
	Slow = 0.4,
}

-- Minimum touch target in pixels at UI scale 1.
UITheme.TouchTarget = 48

function UITheme.RarityColor(rarity: string): Color3
	local def = RarityConfig.Rarities[rarity]
	return if def then def.Color else UITheme.Colors.Muted
end

function UITheme.MutationColor(mutation: string): Color3
	local def = RarityConfig.Mutations[mutation]
	return if def then def.Color else UITheme.Colors.Muted
end

-- A ColorSequence for gradient strokes and fills.
function UITheme.Gradient(...: Color3): ColorSequence
	local colors = { ... }
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local keypoints = {}
	for i, color in colors do
		table.insert(keypoints, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), color))
	end
	return ColorSequence.new(keypoints)
end

function UITheme.RarityGradient(rarity: string): ColorSequence
	if rarity == "Mythic" then
		return UITheme.Gradient(table.unpack(RarityConfig.MythicGradient))
	end
	local base = UITheme.RarityColor(rarity)
	return UITheme.Gradient(base, base:Lerp(UITheme.Colors.White, 0.35))
end

return UITheme

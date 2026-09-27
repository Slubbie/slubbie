-- Visual tokens for the whole interface: one place to restyle the game.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Dicebound.Config)

local Theme = {}

local rgb = Color3.fromRGB

Theme.Colors = {
	Panel = rgb(253, 246, 232),
	PanelAlt = rgb(243, 230, 205),
	PanelDeep = rgb(228, 210, 178),
	Ink = rgb(66, 44, 30),
	InkSoft = rgb(128, 102, 80),
	InkFaint = rgb(170, 150, 128),
	Stroke = rgb(120, 82, 52),
	Shadow = rgb(40, 25, 15),
	Gold = rgb(255, 184, 48),
	GoldDark = rgb(200, 130, 20),
	Green = rgb(88, 176, 84),
	GreenDark = rgb(60, 130, 58),
	Blue = rgb(78, 142, 230),
	BlueDark = rgb(50, 100, 180),
	Red = rgb(222, 84, 70),
	RedDark = rgb(170, 55, 45),
	Purple = rgb(150, 100, 230),
	Disabled = rgb(190, 180, 168),
	DisabledInk = rgb(120, 112, 104),
	White = rgb(255, 255, 255),
	Dim = rgb(15, 10, 25),
}

Theme.Fonts = {
	Title = Enum.Font.FredokaOne,
	Body = Enum.Font.GothamMedium,
	Bold = Enum.Font.GothamBold,
}

Theme.Radius = 12
Theme.StrokeWidth = 2

function Theme.Rarity(id: string): Color3
	local rarity = Config.Rarities.ById[id]
	local c = rarity and rarity.Color or { 200, 200, 200 }
	return rgb(c[1], c[2], c[3])
end

-- Text that identifies a rarity without relying on color: "★★★ RARE".
function Theme.RarityText(id: string): string
	local rarity = Config.Rarities.ById[id]
	return if rarity then rarity.Stars .. " " .. rarity.Label else id
end

function Theme.Mutation(id: string): Color3
	local mutation = Config.Economy.Mutations.ById[id]
	local c = mutation and mutation.Color or { 255, 255, 255 }
	return rgb(c[1], c[2], c[3])
end

return Theme

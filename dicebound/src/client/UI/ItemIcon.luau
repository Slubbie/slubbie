-- Item visuals: a 2D icon (uploaded image, or a clean placeholder built from the item's glyph and
-- rarity color) and a small 3D model for reveals. Mutations change both.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Dicebound.Config)
local Format = require(ReplicatedStorage.Dicebound.Format)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local ItemIcon = {}

local MUTATION_GLYPH = {
	Shiny = "✨",
	Golden = "👑",
	Frozen = "❄",
	Overgrown = "🌿",
	Cosmic = "🌌",
}

-- Square icon. `hidden` draws an undiscovered silhouette ("?").
function ItemIcon.Create(itemId: string, mutation: string?, size: number, hidden: boolean?): Frame
	local item = Config.Items.ById[itemId]
	local rarityColor = if item then Theme.Rarity(item.Rarity) else Theme.Colors.InkFaint
	local frame = Kit.new("Frame", {
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = if hidden then Theme.Colors.PanelDeep else rarityColor:Lerp(Color3.new(1, 1, 1), 0.55),
		BorderSizePixel = 0,
		Name = "Icon",
	})
	Kit.Corner(frame, math.floor(size * 0.2))
	local stroke = Kit.Stroke(frame, if hidden then Theme.Colors.InkFaint else rarityColor, math.max(2, size // 28))
	if not hidden then
		Kit.new("UIGradient", {
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0.85, 0.85, 0.85)),
			Rotation = 90,
			Parent = frame,
		})
	end

	if hidden or not item then
		Kit.Label({
			Parent = frame,
			Size = UDim2.fromScale(1, 1),
			Text = "?",
			TextScaled = true,
			Font = Theme.Fonts.Title,
			TextColor3 = Theme.Colors.InkFaint,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		return frame
	end

	if item.Icon ~= "" then
		Kit.new("ImageLabel", {
			Size = UDim2.fromScale(0.86, 0.86),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Image = item.Icon,
			ScaleType = Enum.ScaleType.Fit,
			Parent = frame,
		})
	else
		Kit.Label({
			Parent = frame,
			Size = UDim2.fromScale(0.8, 0.8),
			Position = UDim2.fromScale(0.5, 0.52),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Text = item.Glyph,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
	end

	if mutation then
		local color = Theme.Mutation(mutation)
		stroke.Color = color
		stroke.Thickness += 1
		frame.BackgroundColor3 = frame.BackgroundColor3:Lerp(color, 0.45)
		Kit.Label({
			Parent = frame,
			Size = UDim2.fromScale(0.42, 0.42),
			Position = UDim2.fromScale(1, 0),
			AnchorPoint = Vector2.new(0.75, 0.25),
			Text = MUTATION_GLYPH[mutation] or "✦",
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 3,
		})
	end
	return frame
end

function ItemIcon.MutationGlyph(mutation: string): string
	return MUTATION_GLYPH[mutation] or "✦"
end

-- Display name including mutation, e.g. "Golden Jar of Sunhoney".
function ItemIcon.Name(itemId: string, mutation: string?): string
	local item = Config.Items.ById[itemId]
	local name = if item then item.Name else itemId
	return if mutation then mutation .. " " .. name else name
end

-- A small 3D model (centered on the origin, about 3 studs) for ViewportFrames.
function ItemIcon.Model(itemId: string, mutation: string?): Model
	local item = Config.Items.ById[itemId]
	local visual = item and item.Visual or { Shape = "Block", Color = { 200, 200, 200 }, Material = "SmoothPlastic" }
	local model = Instance.new("Model")

	local function makePart(shape: string, colorRgb: { number }, material: string, scale: number): Part
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.Color = Format.Color(colorRgb)
		part.Material = (Enum.Material :: any)[material] or Enum.Material.SmoothPlastic
		local s = 2.4 * scale
		if shape == "Ball" then
			part.Shape = Enum.PartType.Ball
			part.Size = Vector3.one * s
		elseif shape == "Egg" then
			part.Shape = Enum.PartType.Ball
			part.Size = Vector3.new(s * 0.85, s * 1.15, s * 0.85)
		elseif shape == "Cylinder" then
			part.Shape = Enum.PartType.Cylinder
			part.Size = Vector3.new(s * 1.1, s * 0.9, s * 0.9)
			part.CFrame = CFrame.Angles(0, 0, math.rad(90))
		elseif shape == "Coin" then
			part.Shape = Enum.PartType.Cylinder
			part.Size = Vector3.new(s * 0.25, s * 1.2, s * 1.2)
		elseif shape == "Gem" then
			part.Size = Vector3.one * s * 0.85
			part.CFrame = CFrame.Angles(math.rad(45), 0, math.rad(45))
		elseif shape == "Wedge" then
			local wedge = Instance.new("WedgePart")
			wedge.Anchored = true
			wedge.CanCollide = false
			wedge.Color = part.Color
			wedge.Material = part.Material
			wedge.Size = Vector3.new(s * 0.8, s, s)
			part:Destroy()
			return wedge :: any
		else
			part.Size = Vector3.one * s * 0.9
		end
		return part
	end

	local body = makePart(visual.Shape, visual.Color, visual.Material, 1)
	body.Name = "Body"
	body.Parent = model
	model.PrimaryPart = body
	if visual.Accent then
		local accent = makePart(visual.Accent.Shape, visual.Accent.Color, visual.Material, visual.Accent.Scale or 0.5)
		local o = visual.Accent.Offset or { 0, 1, 0 }
		accent.CFrame = CFrame.new(o[1] * 2.4, o[2] * 2.4, o[3] * 2.4) * accent.CFrame.Rotation
		accent.Parent = model
	end

	if mutation then
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") then
				if mutation == "Golden" then
					part.Color = Color3.fromRGB(255, 200, 60)
					part.Material = Enum.Material.Foil
					part.Reflectance = 0.25
				elseif mutation == "Frozen" then
					part.Color = part.Color:Lerp(Color3.fromRGB(170, 220, 255), 0.6)
					part.Material = Enum.Material.Ice
				elseif mutation == "Overgrown" then
					part.Color = part.Color:Lerp(Color3.fromRGB(80, 170, 70), 0.4)
					part.Material = Enum.Material.Grass
				elseif mutation == "Cosmic" then
					part.Color = Color3.fromRGB(150, 90, 255)
					part.Material = Enum.Material.ForceField
				elseif mutation == "Shiny" then
					part.Reflectance = 0.35
				end
			end
		end
	end
	return model
end

return ItemIcon

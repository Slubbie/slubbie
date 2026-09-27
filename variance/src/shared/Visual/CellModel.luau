-- The cells loaded into the Arbiter, built client-side only (the server never
-- creates cell objects, so nothing about the sequence can replicate).
--
-- The two types differ in silhouette as well as colour, so they read without
-- colour vision: CHARGED cells have two bright bands and a pointed tip;
-- HOLLOW cells have one wide matte band and an open, dark end.

local Build = require(script.Parent.Build)

local CellModel = {}

CellModel.Length = 0.62
CellModel.Diameter = 0.26

-- colors: { Charged = Color3, Hollow = Color3 } from the client's palette.
function CellModel.build(charged: boolean, colors: { [string]: Color3 }?, known: boolean?): Model
	local model = Build.model(charged and "CellCharged" or "CellHollow")
	local chargedColor = colors and colors.Charged or Color3.fromRGB(224, 72, 47)
	local hollowColor = colors and colors.Hollow or Color3.fromRGB(207, 227, 222)
	local axis = CFrame.Angles(0, 0, math.pi / 2) -- cylinder along Y (upright)
	local casingColor = charged and Color3.fromRGB(58, 34, 30) or Color3.fromRGB(200, 196, 184)
	local casing = Build.cylinder(model, CellModel.Length, CellModel.Diameter, axis, casingColor, "Metal", "Casing")
	casing.CastShadow = false
	if charged then
		for _, y in { 0.12, -0.08 } do
			local band = Build.cylinder(
				model,
				0.06,
				CellModel.Diameter + 0.02,
				CFrame.new(0, y, 0) * axis,
				chargedColor,
				"Neon",
				"Band"
			)
			band.CastShadow = false
		end
		local tip = Build.ball(model, 0.2, CFrame.new(0, CellModel.Length / 2, 0), chargedColor, "Neon", "Tip")
		tip.Size = Vector3.new(0.2, 0.16, 0.2)
		tip.CastShadow = false
	else
		local band = Build.cylinder(
			model,
			0.18,
			CellModel.Diameter + 0.015,
			CFrame.new(0, 0.05, 0) * axis,
			hollowColor,
			"SmoothPlastic",
			"Band"
		)
		band.CastShadow = false
		local hole = Build.cylinder(
			model,
			0.02,
			0.14,
			CFrame.new(0, CellModel.Length / 2 + 0.005, 0) * axis,
			Color3.fromRGB(12, 12, 14),
			"SmoothPlastic",
			"Hole"
		)
		hole.CastShadow = false
	end
	if known == false then
		-- An unrevealed cell: uniform grey so it gives nothing away.
		for _, d in model:GetChildren() do
			if d:IsA("BasePart") then
				d.Color = Color3.fromRGB(90, 92, 94)
				d.Material = Enum.Material.Metal
			end
		end
	end
	model.PrimaryPart = casing
	return model
end

-- A neutral cell (type unknown to this viewer).
function CellModel.blank(): Model
	local model = Build.model("CellBlank")
	local casing = Build.cylinder(
		model,
		CellModel.Length,
		CellModel.Diameter,
		CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(96, 98, 100),
		"Metal",
		"Casing"
	)
	casing.CastShadow = false
	local cap = Build.cylinder(
		model,
		0.04,
		CellModel.Diameter + 0.01,
		CFrame.new(0, CellModel.Length / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(150, 150, 150),
		"Metal",
		"Cap"
	)
	cap.CastShadow = false
	model.PrimaryPart = casing
	return model
end

function CellModel.place(model: Model, cf: CFrame)
	local primary = model.PrimaryPart
	if primary == nil then
		return
	end
	local base = primary.CFrame
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			d.CFrame = cf * base:ToObjectSpace(d.CFrame)
		end
	end
end

return CellModel

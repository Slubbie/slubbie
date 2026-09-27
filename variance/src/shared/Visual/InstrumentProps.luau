-- Small 3D props for each instrument, shown in each subject's tray and picked up
-- during activation animations. Built client-side from primitives.
-- Every prop fits in roughly a 0.9 x 0.7 x 0.9 box, origin at its base centre.

local Build = require(script.Parent.Build)

local InstrumentProps = {}

local STEEL = Color3.fromRGB(150, 152, 150)
local DARK = Color3.fromRGB(38, 40, 44)
local BONE = Color3.fromRGB(215, 210, 196)
local AMBER = Color3.fromRGB(232, 163, 61)
local CYAN = Color3.fromRGB(150, 220, 215)
local RED = Color3.fromRGB(224, 72, 47)
local GREEN = Color3.fromRGB(140, 230, 120)
local VIOLET = Color3.fromRGB(180, 130, 255)

local UP = CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis vertical

local builders: { [string]: (Model) -> () } = {
	Lens = function(m)
		Build.cylinder(m, 0.06, 0.52, CFrame.new(0, 0.42, 0) * CFrame.Angles(0, 0, 1.2), STEEL, "Metal", "Ring")
		local glass = Build.cylinder(m, 0.03, 0.44, CFrame.new(0, 0.42, 0) * CFrame.Angles(0, 0, 1.2), CYAN, "Glass", "Glass")
		glass.Transparency = 0.35
		Build.box(m, Vector3.new(0.1, 0.36, 0.1), CFrame.new(0.18, 0.14, 0) * CFrame.Angles(0, 0, 0.35), DARK, "SmoothPlastic", "Handle")
	end,
	Ejector = function(m)
		Build.box(m, Vector3.new(0.5, 0.3, 0.36), CFrame.new(0, 0.15, 0), DARK, "Metal", "Housing")
		Build.box(m, Vector3.new(0.3, 0.04, 0.2), CFrame.new(0, 0.31, 0), Color3.fromRGB(10, 10, 12), "SmoothPlastic", "Slot")
		Build.cylinder(m, 0.3, 0.1, CFrame.new(0, 0.46, 0) * UP, STEEL, "Metal", "Spring")
		Build.wedge(m, Vector3.new(0.08, 0.16, 0.2), CFrame.new(0, 0.66, 0) * CFrame.Angles(0, math.pi / 2, 0), AMBER, "Neon", "Arrow")
	end,
	Suture = function(m)
		Build.box(m, Vector3.new(0.56, 0.18, 0.42), CFrame.new(0, 0.09, 0), BONE, "SmoothPlastic", "Kit")
		Build.neon(m, Vector3.new(0.3, 0.02, 0.08), CFrame.new(0, 0.19, 0), CYAN, "Plus1")
		Build.neon(m, Vector3.new(0.08, 0.02, 0.3), CFrame.new(0, 0.19, 0), CYAN, "Plus2")
	end,
	Capacitor = function(m)
		Build.cylinder(m, 0.08, 0.44, CFrame.new(0, 0.1, 0) * UP, STEEL, "Metal", "PlateA")
		Build.cylinder(m, 0.08, 0.44, CFrame.new(0, 0.5, 0) * UP, STEEL, "Metal", "PlateB")
		Build.cylinder(m, 0.32, 0.22, CFrame.new(0, 0.3, 0) * UP, AMBER, "Neon", "Core")
	end,
	Clamp = function(m)
		for _, x in { -0.18, 0.18 } do
			Build.cylinder(m, 0.1, 0.34, CFrame.new(x, 0.22, 0) * CFrame.Angles(0, math.pi / 2, 0), STEEL, "Metal", "Cuff")
			Build.cylinder(m, 0.11, 0.2, CFrame.new(x, 0.22, 0) * CFrame.Angles(0, math.pi / 2, 0), DARK, "SmoothPlastic", "Hole")
		end
		for i = -1, 1 do
			Build.ball(m, 0.07, CFrame.new(i * 0.06, 0.32, 0), STEEL, "Metal", "Link")
		end
	end,
	Inverter = function(m)
		Build.cylinder(m, 0.34, 0.14, CFrame.new(-0.14, 0.2, 0) * UP, RED, "Neon", "Charged")
		Build.cylinder(m, 0.34, 0.14, CFrame.new(0.14, 0.2, 0) * UP, BONE, "SmoothPlastic", "Hollow")
		Build.cylinder(m, 0.05, 0.56, CFrame.new(0, 0.2, 0) * UP, STEEL, "Metal", "Ring")
		Build.box(m, Vector3.new(0.34, 0.05, 0.05), CFrame.new(0, 0.42, 0) * CFrame.Angles(0, 0, 0.4), VIOLET, "Neon", "Swap")
	end,
	Sonar = function(m)
		Build.cylinder(m, 0.06, 0.5, CFrame.new(0, 0.34, 0) * CFrame.Angles(0, 0, 1.0), STEEL, "Metal", "Dish")
		Build.box(m, Vector3.new(0.08, 0.3, 0.08), CFrame.new(0, 0.15, 0), DARK, "Metal", "Stand")
		Build.cylinder(m, 0.02, 0.7, CFrame.new(0, 0.34, 0) * CFrame.Angles(0, 0, 1.0), CYAN, "Neon", "Ping").Transparency = 0.4
		Build.ball(m, 0.08, CFrame.new(0.12, 0.44, 0), CYAN, "Neon", "Emitter")
	end,
	Dampener = function(m)
		Build.box(m, Vector3.new(0.46, 0.5, 0.08), CFrame.new(0, 0.28, 0), STEEL, "DiamondPlate", "Plate")
		Build.box(m, Vector3.new(0.3, 0.06, 0.1), CFrame.new(0, 0.28, 0), CYAN, "Neon", "Bar")
		local field = Build.ball(m, 0.72, CFrame.new(0, 0.3, 0), CYAN, "ForceField", "Field")
		field.Transparency = 0.6
		field.CastShadow = false
	end,
	Rotor = function(m)
		Build.cylinder(m, 0.34, 0.5, CFrame.new(0, 0.18, 0) * UP, STEEL, "Metal", "Drum")
		for i = 0, 2 do
			local a = i * (math.pi * 2 / 3)
			Build.cylinder(m, 0.02, 0.12, CFrame.new(math.cos(a) * 0.14, 0.355, math.sin(a) * 0.14) * UP, DARK, "SmoothPlastic", "Hole")
		end
		Build.box(m, Vector3.new(0.06, 0.2, 0.06), CFrame.new(0.28, 0.3, 0), AMBER, "Metal", "Crank")
	end,
	Overclock = function(m)
		local barrel = Build.cylinder(m, 0.46, 0.14, CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, 0.2), BONE, "Glass", "Barrel")
		barrel.Transparency = 0.4
		Build.cylinder(m, 0.34, 0.09, CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, 0.2), RED, "Neon", "Fluid")
		Build.box(m, Vector3.new(0.03, 0.03, 0.18), CFrame.new(-0.3, 0.16, 0), STEEL, "Metal", "Needle")
		Build.box(m, Vector3.new(0.06, 0.18, 0.18), CFrame.new(0.28, 0.24, 0), DARK, "SmoothPlastic", "Plunger")
	end,
	Serum = function(m)
		local vial = Build.cylinder(m, 0.5, 0.2, CFrame.new(0, 0.26, 0) * UP, BONE, "Glass", "Vial")
		vial.Transparency = 0.45
		Build.cylinder(m, 0.34, 0.15, CFrame.new(0, 0.2, 0) * UP, GREEN, "Neon", "Fluid")
		Build.cylinder(m, 0.08, 0.22, CFrame.new(0, 0.54, 0) * UP, DARK, "SmoothPlastic", "Cap")
		Build.box(m, Vector3.new(0.02, 0.14, 0.12), CFrame.new(0.105, 0.28, 0), AMBER, "SmoothPlastic", "Label")
	end,
	PowerTap = function(m)
		Build.box(m, Vector3.new(0.36, 0.3, 0.3), CFrame.new(0, 0.15, 0), DARK, "SmoothPlastic", "Plug")
		for _, x in { -0.08, 0.08 } do
			Build.box(m, Vector3.new(0.04, 0.2, 0.08), CFrame.new(x, 0.4, 0), STEEL, "Metal", "Prong")
		end
		Build.cylinder(m, 0.4, 0.08, CFrame.new(0.34, 0.1, 0), AMBER, "SmoothPlastic", "Cable")
	end,
	Tether = function(m)
		for _, x in { -0.2, 0.2 } do
			Build.cylinder(m, 0.06, 0.3, CFrame.new(x, 0.26, 0) * CFrame.Angles(0, math.pi / 2, 0), STEEL, "Metal", "Ring")
		end
		Build.box(m, Vector3.new(0.4, 0.05, 0.05), CFrame.new(0, 0.26, 0), VIOLET, "Neon", "Link")
	end,
	Scrambler = function(m)
		Build.box(m, Vector3.new(0.42, 0.42, 0.42), CFrame.new(0, 0.24, 0) * CFrame.Angles(0, 0.4, 0), DARK, "Metal", "Cube")
		Build.neon(m, Vector3.new(0.44, 0.03, 0.03), CFrame.new(0, 0.3, 0) * CFrame.Angles(0.5, 0.4, 0.7), VIOLET, "CrackA")
		Build.neon(m, Vector3.new(0.03, 0.44, 0.03), CFrame.new(0, 0.2, 0) * CFrame.Angles(0.3, 0.4, 0.2), RED, "CrackB")
	end,
}

-- Builds a prop for `id` with its base centre at the origin.
function InstrumentProps.build(id: string): Model
	local model = Build.model("Prop_" .. id)
	local base = Build.box(model, Vector3.new(0.7, 0.04, 0.7), CFrame.new(0, 0.02, 0), Color3.fromRGB(30, 31, 33), "SmoothPlastic", "Base")
	base.Transparency = 1
	local builder = builders[id]
	if builder then
		builder(model)
	else
		Build.box(model, Vector3.new(0.4, 0.4, 0.4), CFrame.new(0, 0.2, 0), STEEL, "Metal", "Unknown")
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CastShadow = false
			d:SetAttribute("Rest", base.CFrame:ToObjectSpace(d.CFrame))
		end
	end
	model.PrimaryPart = base
	model:SetAttribute("Instrument", id)
	return model
end

function InstrumentProps.place(model: Model, cf: CFrame)
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			local rest = d:GetAttribute("Rest")
			if typeof(rest) == "CFrame" then
				d.CFrame = cf * rest
			end
		end
	end
end

return InstrumentProps

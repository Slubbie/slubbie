-- Builds the handheld Comet Tether device. Its look follows the player's
-- equipment: the emitter ring colour and size come from the Tether level, and
-- the scanner dish, antennas, orbit ring and hologram from the Scanner level.
-- The server welds it to every character (visible to everyone); the
-- workshop shows it in a preview.

local EquipmentRig = {}

EquipmentRig.TetherColors = {
	Color3.fromRGB(116, 229, 254),
	Color3.fromRGB(125, 227, 170),
	Color3.fromRGB(182, 156, 255),
	Color3.fromRGB(255, 207, 112),
	Color3.fromRGB(255, 126, 152),
}

local SHELL = Color3.fromRGB(232, 228, 250)
local FRAME = Color3.fromRGB(52, 58, 96)

local function part(
	model: Model,
	root: BasePart,
	kind: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material?
): BasePart
	local p: BasePart
	if kind == "Wedge" then
		p = Instance.new("WedgePart")
	else
		local basic = Instance.new("Part")
		if kind == "Cylinder" then
			basic.Shape = Enum.PartType.Cylinder
		end
		p = basic
	end
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	if kind == "Ellipsoid" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.CFrame = root.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = p
	w.Parent = p
	p.Parent = model
	return p
end

-- Builds the device around a "Grip" part (the hand position). The device
-- points along the grip's -Z. A "Tip" attachment marks the emitter.
function EquipmentRig.BuildDevice(scannerLevel: number, tetherLevel: number): Model
	local model = Instance.new("Model")
	model.Name = "CometTether"
	local grip = Instance.new("Part")
	grip.Name = "Grip"
	grip.Size = Vector3.new(0.3, 0.3, 0.3)
	grip.Transparency = 1
	grip.CanCollide = false
	grip.CanQuery = false
	grip.CanTouch = false
	grip.Massless = true
	grip.CFrame = CFrame.identity
	grip.Parent = model
	model.PrimaryPart = grip

	local tether = math.clamp(tetherLevel, 1, #EquipmentRig.TetherColors)
	local glow = EquipmentRig.TetherColors[tether]

	part(
		model,
		grip,
		"Cylinder",
		Vector3.new(0.9, 0.32, 0.32),
		CFrame.Angles(0, math.rad(90), 0) * CFrame.new(-0.05, 0, 0),
		FRAME
	)
	part(model, grip, "Ellipsoid", Vector3.new(0.62, 0.55, 1.25), CFrame.new(0, 0.18, -0.55), SHELL)
	part(model, grip, "Ellipsoid", Vector3.new(0.4, 0.2, 0.7), CFrame.new(0, 0.42, -0.45), glow, Enum.Material.Neon)

	-- Emitter ring: bigger and more segmented at higher tether levels.
	local ringRadius = 0.32 + tether * 0.035
	local segments = 8 + tether * 2
	for i = 0, segments - 1 do
		local a = i * math.pi * 2 / segments
		local pos = Vector3.new(math.cos(a) * ringRadius, 0.18 + math.sin(a) * ringRadius, -1.22)
		part(
			model,
			grip,
			"Block",
			Vector3.new(0.09, 0.09, 2 * ringRadius * math.sin(math.pi / segments) * 1.15),
			CFrame.new(pos) * CFrame.Angles(0, 0, a) * CFrame.Angles(math.rad(90), 0, 0),
			glow,
			Enum.Material.Neon
		)
	end
	local core = part(
		model,
		grip,
		"Ellipsoid",
		Vector3.new(0.22, 0.22, 0.22),
		CFrame.new(0, 0.18, -1.22),
		Color3.new(1, 1, 1),
		Enum.Material.Neon
	)
	local tip = Instance.new("Attachment")
	tip.Name = "Tip"
	tip.Parent = core
	if tether >= 3 then
		local light = Instance.new("PointLight")
		light.Color = glow
		light.Range = 6
		light.Brightness = 0.8
		light.Parent = core
	end

	-- Scanner dish on top.
	local scanner = math.clamp(scannerLevel, 1, 5)
	local dishSize = 0.45 + scanner * 0.08
	local dish = part(
		model,
		grip,
		"Cylinder",
		Vector3.new(0.08, dishSize, dishSize),
		CFrame.new(0, 0.62, -0.3) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(math.rad(-25), 0, 0),
		if scanner >= 5 then glow else SHELL,
		if scanner >= 5 then Enum.Material.Glass else Enum.Material.SmoothPlastic
	)
	dish.Transparency = if scanner >= 5 then 0.3 else 0
	if scanner >= 2 then
		part(
			model,
			grip,
			"Cylinder",
			Vector3.new(0.55, 0.05, 0.05),
			CFrame.new(0.18, 0.85, -0.15) * CFrame.Angles(0, 0, math.rad(75)),
			FRAME
		)
		part(
			model,
			grip,
			"Ellipsoid",
			Vector3.new(0.1, 0.1, 0.1),
			CFrame.new(0.25, 1.1, -0.15),
			glow,
			Enum.Material.Neon
		)
	end
	if scanner >= 4 then
		part(
			model,
			grip,
			"Cylinder",
			Vector3.new(0.55, 0.05, 0.05),
			CFrame.new(-0.18, 0.85, -0.15) * CFrame.Angles(0, 0, math.rad(105)),
			FRAME
		)
		part(
			model,
			grip,
			"Ellipsoid",
			Vector3.new(0.1, 0.1, 0.1),
			CFrame.new(-0.25, 1.1, -0.15),
			glow,
			Enum.Material.Neon
		)
	end
	if scanner >= 3 then
		local holo = part(
			model,
			grip,
			"Cylinder",
			Vector3.new(0.04, 0.95, 0.95),
			CFrame.new(0, 0.18, -0.55) * CFrame.Angles(0, math.rad(90), 0),
			glow,
			Enum.Material.Neon
		)
		holo.Transparency = 0.55
	end
	return model
end

return EquipmentRig

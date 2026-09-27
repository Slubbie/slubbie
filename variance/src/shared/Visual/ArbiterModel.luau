-- The Arbiter: a heavy, bolt-action capacitor device built from primitives.
--
-- Local frame: the grip is the origin, the muzzle points down -Z, +Y is up and
-- the chamber window faces +X. Named attachments on the "Body" part:
--   Muzzle, Chamber, Port (cell insertion), Eject, GripR, GripL
-- Parts carry a "Paint" attribute (Body, Metal, Accent, Glow, Glass) so a
-- cosmetic finish can repaint the whole thing with ArbiterModel.applySkin.
-- The bolt ("Bolt", "BoltKnob") and dial needle ("Needle") are animated by the
-- client's WeaponController relative to their rest offsets (attribute "Rest").

local Build = require(script.Parent.Build)

local ArbiterModel = {}

local DEFAULT = {
	Body = Color3.fromRGB(62, 66, 70),
	Metal = Color3.fromRGB(150, 150, 145),
	Accent = Color3.fromRGB(225, 160, 60),
	Glow = Color3.fromRGB(255, 190, 110),
	Glass = Color3.fromRGB(22, 28, 30),
}

local function tag(part: BasePart, paint: string, root: CFrame): BasePart
	part:SetAttribute("Paint", paint)
	part:SetAttribute("Rest", root:ToObjectSpace(part.CFrame))
	return part
end

-- Builds the device at `at` (the grip CFrame). Returns the model.
function ArbiterModel.build(at: CFrame?): Model
	local root = at or CFrame.identity
	local model = Build.model("Arbiter")
	local function box(name, size, offset, paint, mat)
		local p = Build.box(model, size, root * offset, DEFAULT[paint] or DEFAULT.Body, mat or "Metal", name)
		return tag(p, paint, root)
	end
	local function cyl(name, length, dia, offset, paint, mat)
		local p =
			Build.cylinder(model, length, dia, root * offset, DEFAULT[paint] or DEFAULT.Metal, mat or "Metal", name)
		return tag(p, paint, root)
	end
	local alongZ = CFrame.Angles(0, math.pi / 2, 0) -- cylinder axis (X) -> Z

	local body = box("Body", Vector3.new(0.56, 0.6, 1.7), CFrame.new(0, 0.12, -0.25), "Body")
	box("Chamber", Vector3.new(0.72, 0.74, 0.82), CFrame.new(0, 0.14, 0.36), "Body")
	local window = box("Window", Vector3.new(0.06, 0.32, 0.46), CFrame.new(0.37, 0.2, 0.36), "Glass", "Glass")
	window.Transparency = 0.15
	box("Port", Vector3.new(0.32, 0.08, 0.38), CFrame.new(0, 0.53, 0.36), "Metal", "DiamondPlate")
	cyl("Barrel", 1.7, 0.34, CFrame.new(0, 0.2, -1.6) * alongZ, "Metal")
	for i, z in { -1.0, -1.32, -1.64 } do
		local ring = cyl("Coil" .. i, 0.1, 0.48, CFrame.new(0, 0.2, z) * alongZ, "Glow", "Neon")
		ring.CastShadow = false
	end
	cyl("Muzzle", 0.18, 0.44, CFrame.new(0, 0.2, -2.42) * alongZ, "Metal")
	box(
		"Grip",
		Vector3.new(0.3, 0.78, 0.36),
		CFrame.new(0, -0.36, 0.58) * CFrame.Angles(-0.35, 0, 0),
		"Body",
		"SmoothPlastic"
	)
	box("Foregrip", Vector3.new(0.28, 0.42, 0.3), CFrame.new(0, -0.26, -0.78), "Body", "SmoothPlastic")
	box("Stock", Vector3.new(0.46, 0.56, 0.95), CFrame.new(0, 0.04, 1.3), "Body")
	box("StockPlate", Vector3.new(0.5, 0.62, 0.08), CFrame.new(0, 0.04, 1.8), "Metal")
	for _, side in { -1, 1 } do
		local strip =
			box("Strip", Vector3.new(0.02, 0.05, 1.25), CFrame.new(0.29 * side, 0.28, -0.25), "Accent", "Neon")
		strip.CastShadow = false
	end
	cyl("Bolt", 0.42, 0.12, CFrame.new(0.47, 0.28, 0.58), "Metal")
	local knob = Build.ball(model, 0.22, root * CFrame.new(0.7, 0.28, 0.58), DEFAULT.Metal, "Metal", "BoltKnob")
	tag(knob, "Metal", root)
	cyl("Dial", 0.06, 0.3, CFrame.new(-0.37, 0.22, 0.36), "Metal")
	local needle = box("Needle", Vector3.new(0.02, 0.12, 0.02), CFrame.new(-0.405, 0.26, 0.36), "Accent", "Neon")
	needle.CastShadow = false

	Build.attachment(body, "Muzzle", body.CFrame:ToObjectSpace(root * CFrame.new(0, 0.2, -2.55)))
	Build.attachment(body, "Chamber", body.CFrame:ToObjectSpace(root * CFrame.new(0, 0.2, 0.36)))
	Build.attachment(body, "Port", body.CFrame:ToObjectSpace(root * CFrame.new(0, 0.6, 0.36)))
	Build.attachment(body, "Eject", body.CFrame:ToObjectSpace(root * CFrame.new(0.42, 0.28, 0.36)))
	Build.attachment(body, "GripR", body.CFrame:ToObjectSpace(root * CFrame.new(0, -0.62, 0.66)))
	Build.attachment(body, "GripL", body.CFrame:ToObjectSpace(root * CFrame.new(0, -0.44, -0.78)))

	local glow = Build.pointLight(body, DEFAULT.Glow, 0, 6, false)
	glow.Name = "ChamberGlow"

	model.PrimaryPart = body
	model.WorldPivot = root
	model:SetAttribute("Device", "Arbiter")
	return model
end

-- Repaints the device with a DeviceSkin cosmetic's data.
function ArbiterModel.applySkin(model: Model, data: { [string]: any }?)
	if model == nil then
		return
	end
	data = data or {}
	local colors = {
		Body = Build.rgb(data.Body, DEFAULT.Body),
		Metal = Build.rgb(data.Metal, DEFAULT.Metal),
		Accent = Build.rgb(data.Accent, DEFAULT.Accent),
		Glow = Build.rgb(data.Glow, DEFAULT.Glow),
		Glass = DEFAULT.Glass,
	}
	local mat = Build.material(data.Material or "Metal")
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local paint = d:GetAttribute("Paint")
			if paint and colors[paint] then
				d.Color = colors[paint]
				if paint == "Body" and d.Name ~= "Grip" and d.Name ~= "Foregrip" then
					d.Material = mat
				end
			end
		elseif d:IsA("PointLight") and d.Name == "ChamberGlow" then
			d.Color = colors.Glow
		end
	end
end

-- Moves the whole device so its grip sits at `cf`, using the stored rest offsets
-- (cheaper and more stable than PivotTo every frame).
function ArbiterModel.place(model: Model, cf: CFrame, boltOffset: number?, needleAngle: number?)
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			local rest = d:GetAttribute("Rest")
			if typeof(rest) == "CFrame" then
				local offset = rest
				if boltOffset and (d.Name == "Bolt" or d.Name == "BoltKnob") then
					offset = CFrame.new(0, 0, boltOffset) * rest
				elseif needleAngle and d.Name == "Needle" then
					local pivot = CFrame.new(-0.405, 0.2, 0.36)
					offset = pivot * CFrame.Angles(needleAngle, 0, 0) * pivot:Inverse() * rest
				end
				d.CFrame = cf * offset
			end
		end
	end
end

return ArbiterModel

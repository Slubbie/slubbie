-- Held tool and vehicle models. Tier colours/materials come from
-- Config/Tools.TierLook; the Heirloom cosmetic swaps metal for brass and wood.
--
-- Tools.Held(familyId, tier, skin?) → Model whose origin is the grip (the
-- renderer welds it to the character's hand, pointing along -Z).
-- Tools.Vehicle(id) → Model placed under the character when driving.
-- Tools.Mount(coatColor) → a horse body for riding.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(script.Parent.Kit)
local Tools = require(ReplicatedStorage:WaitForChild("Shared").Config.Tools)

local Models = {}

local WOOD = Color3.fromRGB(150, 105, 65)
local MATERIALS = {
	CorrodedMetal = Enum.Material.CorrodedMetal,
	Metal = Enum.Material.Metal,
	Foil = Enum.Material.Foil,
	Glass = Enum.Material.Glass,
	Neon = Enum.Material.Neon,
}

local function b(
	model: Model,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	name: string?
): BasePart
	local p = Kit.Box(model, size, cf, color, { Collide = false, Shadow = false, Name = name })
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanQuery = false
	p.Massless = true
	return p
end

local function handle(model: Model, length: number, color: Color3)
	b(model, Vector3.new(0.25, 0.25, length), CFrame.new(0, 0, -length / 2 + 0.6), color, Enum.Material.Wood, "Handle")
end

local builders: { [string]: (Model, Color3, Enum.Material, Color3) -> () } = {}

builders.hoe = function(m, metal, mat, wood)
	handle(m, 4.2, wood)
	b(
		m,
		Vector3.new(1.2, 0.12, 0.6),
		CFrame.new(0, -0.25, -3.5) * CFrame.Angles(math.rad(-70), 0, 0),
		metal,
		mat,
		"Head"
	)
end

builders.can = function(m, metal, mat)
	local body =
		Kit.Cyl(m, 1.1, 1.1, CFrame.new(0, -0.3, -0.3), metal, { Collide = false, Shadow = false, Name = "Body" })
	body.Material = mat
	body.Massless = true
	b(
		m,
		Vector3.new(0.18, 0.18, 1.2),
		CFrame.new(0, -0.1, -1.2) * CFrame.Angles(math.rad(-30), 0, 0),
		metal,
		mat,
		"Spout"
	)
	b(m, Vector3.new(0.15, 0.6, 0.15), CFrame.new(0, 0.35, 0), metal:Lerp(Color3.new(0, 0, 0), 0.2), mat, "Grip")
end

builders.sickle = function(m, metal, mat, wood)
	handle(m, 1.4, wood)
	for i = 0, 4 do
		local a = math.rad(-20 + i * 30)
		b(
			m,
			Vector3.new(0.1, 0.18, 0.5),
			CFrame.new(0, 0, -1) * CFrame.Angles(a, 0, 0) * CFrame.new(0, 0.5, -0.1),
			metal,
			mat,
			"Blade"
		)
	end
end

builders.axe = function(m, metal, mat, wood)
	handle(m, 3, wood)
	b(m, Vector3.new(0.2, 1, 0.9), CFrame.new(0, 0.35, -2.2), metal, mat, "Head")
	b(m, Vector3.new(0.1, 1.1, 0.2), CFrame.new(0, 0.35, -2.7), metal:Lerp(Color3.new(1, 1, 1), 0.3), mat, "Edge")
end

builders.pickaxe = function(m, metal, mat, wood)
	handle(m, 3, wood)
	b(
		m,
		Vector3.new(0.22, 0.22, 2.2),
		CFrame.new(0, 0.1, -2.3) * CFrame.Angles(0, math.pi / 2, math.rad(10)),
		metal,
		mat,
		"Head"
	)
end

builders.shovel = function(m, metal, mat, wood)
	handle(m, 3.6, wood)
	b(m, Vector3.new(0.9, 0.08, 1.1), CFrame.new(0, 0, -3.4), metal, mat, "Blade")
end

builders.rod = function(m, metal, mat, wood)
	b(
		m,
		Vector3.new(0.14, 0.14, 6),
		CFrame.new(0, 0.2, -2.6) * CFrame.Angles(math.rad(25), 0, 0),
		wood,
		Enum.Material.Wood,
		"Rod"
	)
	local reel =
		Kit.Cyl(m, 0.3, 0.45, CFrame.new(0.25, -0.1, -0.2), metal, { Collide = false, Shadow = false, Name = "Reel" })
	reel.Material = mat
	reel.Massless = true
	local tip = b(m, Vector3.new(0.1, 0.1, 0.1), CFrame.new(0, 1.45, -5.3), metal, mat, "Tip")
	local att = Instance.new("Attachment")
	att.Name = "LineOrigin"
	att.Parent = tip
end

builders.net = function(m, metal, mat, wood)
	handle(m, 3.2, wood)
	local ring = Kit.Cyl(
		m,
		0.1,
		1.5,
		CFrame.new(0, 0, -3.3) * CFrame.Angles(math.rad(90), 0, 0),
		metal,
		{ Collide = false, Shadow = false, Name = "Ring" }
	)
	ring.Material = mat
	ring.Massless = true
	local mesh = b(
		m,
		Vector3.new(1.3, 0.8, 1.3),
		CFrame.new(0, -0.4, -3.3),
		Color3.fromRGB(240, 240, 235),
		Enum.Material.Fabric,
		"Mesh"
	)
	mesh.Transparency = 0.4
end

builders.pruners = function(m, metal, mat)
	b(m, Vector3.new(0.18, 0.18, 0.9), CFrame.new(0.12, 0, -0.3), Color3.fromRGB(200, 60, 50), nil, "Grip")
	b(m, Vector3.new(0.18, 0.18, 0.9), CFrame.new(-0.12, 0, -0.3), Color3.fromRGB(200, 60, 50), nil, "Grip")
	b(m, Vector3.new(0.06, 0.2, 0.7), CFrame.new(0.05, 0, -1) * CFrame.Angles(0, 0.2, 0), metal, mat, "Blade")
	b(m, Vector3.new(0.06, 0.2, 0.7), CFrame.new(-0.05, 0, -1) * CFrame.Angles(0, -0.2, 0), metal, mat, "Blade")
end

builders.seeder = function(m, metal, mat)
	local box = b(m, Vector3.new(0.9, 0.9, 0.9), CFrame.new(0, -0.3, -0.5), metal, mat, "Hopper")
	box.Color = metal:Lerp(Color3.fromRGB(120, 90, 60), 0.5)
	b(m, Vector3.new(0.2, 0.2, 0.9), CFrame.new(0, -0.6, -1.2), metal, mat, "Chute")
end

function Models.Held(familyId: string, tier: number, skin: string?): Model
	local model = Kit.Model("Held_" .. familyId)
	local look = Tools.TierLook[math.clamp(tier or 1, 1, #Tools.TierLook)]
	local metal = look.Color
	local material = MATERIALS[look.Material] or Enum.Material.Metal
	local wood = WOOD
	if skin == "tools_heirloom" then
		metal = Color3.fromRGB(196, 150, 80)
		material = Enum.Material.Metal
		wood = Color3.fromRGB(110, 60, 35)
	end
	local builder = builders[familyId]
	if builder then
		builder(model, metal, material, wood)
	end
	if tier >= 5 then
		local head = model:FindFirstChild("Head") or model:FindFirstChild("Blade") or model:FindFirstChild("Body")
		if head and head:IsA("BasePart") then
			Kit.Particles(head, "Sparkle", metal, 2)
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
		end
	end
	return model
end

-- Vehicles ------------------------------------------------------------------------------------------------------

function Models.Vehicle(id: string): Model
	local model = Kit.Model("Vehicle_" .. id)
	if id == "hover_tractor" then
		b(
			model,
			Vector3.new(5, 1.4, 7),
			CFrame.new(0, 1.6, 0),
			Color3.fromRGB(90, 110, 200),
			Enum.Material.Metal,
			"Chassis"
		)
		for _, x in { -2.6, 2.6 } do
			local pad = b(
				model,
				Vector3.new(1, 0.4, 6),
				CFrame.new(x, 0.6, 0),
				Color3.fromRGB(120, 230, 255),
				Enum.Material.Neon,
				"Hover"
			)
			Kit.Particles(pad, "Sparkle", Color3.fromRGB(120, 230, 255), 8)
		end
	elseif id == "drone_remote" then
		b(model, Vector3.new(0.6, 0.3, 0.9), CFrame.new(0.9, 0, -0.4), Color3.fromRGB(60, 60, 70), nil, "Remote")
		local drone = b(
			model,
			Vector3.new(1.6, 0.4, 1.6),
			CFrame.new(0, 7, 0),
			Color3.fromRGB(230, 230, 235),
			Enum.Material.Metal,
			"Drone"
		)
		drone:SetAttribute("Hover", true)
		for _, x in { -1, 1 } do
			for _, z in { -1, 1 } do
				local rotor = Kit.Cyl(
					model,
					0.1,
					1.2,
					CFrame.new(x, 7.3, z),
					Color3.fromRGB(40, 40, 45),
					{ Collide = false, Shadow = false, Name = "Rotor" }
				)
				rotor:SetAttribute("Anim", "Spinner")
			end
		end
	else
		-- Tractor
		b(
			model,
			Vector3.new(4.4, 2.2, 7),
			CFrame.new(0, 2.4, 0),
			Color3.fromRGB(200, 50, 45),
			Enum.Material.Metal,
			"Chassis"
		)
		b(
			model,
			Vector3.new(3, 2, 3),
			CFrame.new(0, 4.3, 1.6),
			Color3.fromRGB(220, 220, 225),
			Enum.Material.Glass,
			"Cab"
		).Transparency =
			0.4
		local stack = b(
			model,
			Vector3.new(0.4, 2, 0.4),
			CFrame.new(1.4, 4.4, -2.4),
			Color3.fromRGB(60, 60, 60),
			Enum.Material.Metal,
			"Exhaust"
		)
		Kit.Particles(stack, "Smoke", Color3.fromRGB(140, 140, 140), 4)
		for _, pos in
			{ { -2.4, 1.4, 2.2, 2.8 }, { 2.4, 1.4, 2.2, 2.8 }, { -2.2, 0.9, -2.4, 1.8 }, { 2.2, 0.9, -2.4, 1.8 } }
		do
			local wheel = Kit.CylFlat(
				model,
				0.9,
				pos[4],
				CFrame.new(pos[1], pos[2], pos[3]),
				Color3.fromRGB(35, 35, 35),
				"X",
				{ Collide = false, Shadow = false, Name = "Wheel" }
			)
			wheel:SetAttribute("Anim", "Roll")
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.Massless = true
			d.CanCollide = false
			d.CanQuery = false
		end
	end
	return model
end

-- A rideable horse body (the rider sits on top).
function Models.Mount(coat: Color3): Model
	local model = Kit.Model("Mount")
	local dark = coat:Lerp(Color3.new(0, 0, 0), 0.3)
	b(model, Vector3.new(2.4, 2.4, 5), CFrame.new(0, 3.6, 0), coat, nil, "Body")
	b(model, Vector3.new(1, 2.6, 1.2), CFrame.new(0, 5, -2.6) * CFrame.Angles(math.rad(-30), 0, 0), coat, nil, "Neck")
	b(model, Vector3.new(1.1, 1.2, 2.2), CFrame.new(0, 6, -3.6), coat, nil, "Head")
	b(model, Vector3.new(0.3, 1.8, 2.8), CFrame.new(0, 5.4, -2.2), dark, Enum.Material.Fabric, "Mane")
	for i, pos in { { -0.8, -1.8 }, { 0.8, -1.8 }, { -0.8, 1.8 }, { 0.8, 1.8 } } do
		local leg = b(model, Vector3.new(0.5, 2.6, 0.5), CFrame.new(pos[1], 1.3, pos[2]), dark, nil, "Leg")
		leg:SetAttribute("Index", i)
	end
	b(
		model,
		Vector3.new(0.3, 2, 0.6),
		CFrame.new(0, 3.6, 2.8) * CFrame.Angles(math.rad(30), 0, 0),
		dark,
		Enum.Material.Fabric,
		"Tail"
	)
	b(
		model,
		Vector3.new(2.5, 0.4, 2),
		CFrame.new(0, 4.9, 0.3),
		Color3.fromRGB(120, 70, 40),
		Enum.Material.Fabric,
		"Saddle"
	)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.Massless = true
			d.CanCollide = false
			d.CanQuery = false
		end
	end
	return model
end

return Models

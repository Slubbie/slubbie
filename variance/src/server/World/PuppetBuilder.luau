-- Builds the surrogates' bodies: real R6 rigs (standard part names and Motor6D
-- joints) so the client's RigAnimator animates them exactly like seated
-- players. Each surrogate gets its own head and costume from Data/Surrogates.
-- The root is anchored at the seat; every other part hangs off the joints.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(ReplicatedStorage.Variance.Visual.Build)
local Surrogates = require(ReplicatedStorage.Variance.Data.Surrogates)

local PuppetBuilder = {}

-- Standard R6 joint frames.
local ROOT_C = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, -0)
local NECK_C0 = CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, -0)
local NECK_C1 = CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, -0)
local LS_C0 = CFrame.new(-1, 0.5, 0, -0, -0, -1, 0, 1, 0, 1, 0, 0)
local LS_C1 = CFrame.new(0.5, 0.5, 0, -0, -0, -1, 0, 1, 0, 1, 0, 0)
local RS_C0 = CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, -0, -0)
local RS_C1 = CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, -0, -0)
local LH_C0 = CFrame.new(-1, -1, 0, -0, -0, -1, 0, 1, 0, 1, 0, 0)
local LH_C1 = CFrame.new(-0.5, 1, 0, -0, -0, -1, 0, 1, 0, 1, 0, 0)
local RH_C0 = CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, -0, -0)
local RH_C1 = CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, -0, -0)

local function limb(model: Model, name: string, size: Vector3, color: Color3, mat: string?): BasePart
	local p = Build.part({
		Name = name,
		Size = size,
		Color = color,
		Material = mat or "SmoothPlastic",
		Anchored = false,
		CastShadow = true,
		Parent = model,
	})
	p.Massless = true
	return p
end

local function motor(name: string, parent: BasePart, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame): Motor6D
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = c0
	m.C1 = c1
	m.Parent = parent
	return m
end

-- Attaches a decorative part to `to` at an offset (welded, unanchored).
local function deco(model: Model, to: BasePart, size: Vector3, offset: CFrame, color: Color3, mat: string?, name: string?, shape: Enum.PartType?): BasePart
	local p = Build.part({
		Name = name or "Deco",
		Size = size,
		CFrame = to.CFrame * offset,
		Color = color,
		Material = mat or "SmoothPlastic",
		Shape = shape,
		Anchored = false,
		Parent = model,
	})
	p.Massless = true
	p.CastShadow = false
	Build.weld(p, to)
	return p
end

local heads = {}

function heads.Monitor(model, head, look)
	head.Transparency = 1
	deco(model, head, Vector3.new(1.35, 1.15, 1.2), CFrame.new(0, 0.05, 0), Build.rgb(look.Body), "SmoothPlastic", "Casing")
	local screen = deco(model, head, Vector3.new(1.1, 0.85, 0.05), CFrame.new(0, 0.07, -0.61), Color3.fromRGB(8, 20, 12), "Glass", "Screen")
	Build.label(screen, Enum.NormalId.Front, "0114", Build.rgb(look.Eye), { Font = Enum.Font.Code, PixelsPerStud = 80, Brightness = 2 })
	deco(model, head, Vector3.new(0.06, 0.6, 0.06), CFrame.new(0.4, 0.9, 0.1), Build.rgb(look.Limbs), "Metal", "Antenna")
end

function heads.Coil(model, head, look)
	head.Transparency = 1
	deco(model, head, Vector3.new(1.25, 1.25, 1.25), CFrame.identity, Build.rgb(look.Body), "Metal", "Dome", Enum.PartType.Ball)
	deco(model, head, Vector3.new(1.05, 0.22, 0.2), CFrame.new(0, 0.1, -0.55), Build.rgb(look.Eye), "Neon", "Visor")
	for _, x in { -0.35, 0.35 } do
		deco(model, head, Vector3.new(0.08, 0.9, 0.08), CFrame.new(x, 0.95, 0) * CFrame.Angles(0, 0, x * 0.6), Build.rgb(look.Limbs), "Metal", "Antenna")
		deco(model, head, Vector3.new(0.2, 0.2, 0.2), CFrame.new(x * 1.45, 1.38, 0), Build.rgb(look.Accent), "Neon", "Spark", Enum.PartType.Ball)
	end
	for i = 0, 2 do
		deco(model, head, Vector3.new(0.08, 1.3, 1.3), CFrame.new(-0.3 + i * 0.3, 0, 0), Build.rgb(look.Accent), "Neon", "Coil", Enum.PartType.Cylinder)
	end
end

function heads.Beak(model, head, look)
	head.Transparency = 1
	deco(model, head, Vector3.new(1.15, 1.2, 1.2), CFrame.identity, Build.rgb(look.Body), "Fabric", "Hood", Enum.PartType.Ball)
	local beak = Instance.new("WedgePart")
	beak.Name = "Beak"
	beak.Size = Vector3.new(0.35, 0.4, 0.9)
	beak.CFrame = head.CFrame * CFrame.new(0, -0.15, -0.8) * CFrame.Angles(math.pi, 0, 0)
	beak.Color = Build.rgb(look.Accent)
	beak.Material = Enum.Material.Metal
	beak.Anchored = false
	beak.Massless = true
	beak.CanCollide = false
	beak.CanQuery = false
	beak.CanTouch = false
	beak.Parent = model
	Build.weld(beak, head)
	for _, x in { -0.28, 0.28 } do
		deco(model, head, Vector3.new(0.12, 0.34, 0.34), CFrame.new(x, 0.18, -0.55) * CFrame.Angles(0, math.pi / 2, 0), Build.rgb(look.Eye), "Neon", "Lens", Enum.PartType.Cylinder)
	end
end

function heads.Die(model, head, look)
	head.Transparency = 1
	local cube = deco(model, head, Vector3.new(1.2, 1.2, 1.2), CFrame.identity, Color3.fromRGB(235, 232, 222), "SmoothPlastic", "Die")
	local pips = { { 0, 0 }, { -0.3, 0.3 }, { 0.3, -0.3 }, { -0.3, -0.3 }, { 0.3, 0.3 } }
	for _, p in pips do
		deco(model, cube, Vector3.new(0.18, 0.18, 0.06), CFrame.new(p[1], p[2], -0.6), Color3.fromRGB(20, 20, 20), "SmoothPlastic", "Pip", Enum.PartType.Ball)
	end
	deco(model, cube, Vector3.new(1.3, 0.2, 1.3), CFrame.new(0, 0.66, 0), Build.rgb(look.Accent), "Foil", "Band")
end

function heads.Aperture(model, head, look)
	head.Transparency = 1
	local shell = deco(model, head, Vector3.new(1.1, 1.6, 1.15), CFrame.new(0, 0.25, 0), Build.rgb(look.Body), "SmoothPlastic", "Shell", Enum.PartType.Ball)
	deco(model, shell, Vector3.new(0.08, 0.5, 0.5), CFrame.new(0, 0.05, -0.54) * CFrame.Angles(0, math.pi / 2, 0), Build.rgb(look.Eye), "Neon", "Aperture", Enum.PartType.Cylinder)
	deco(model, shell, Vector3.new(0.06, 0.26, 0.26), CFrame.new(0, 0.05, -0.59) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(10, 10, 10), "SmoothPlastic", "Pupil", Enum.PartType.Cylinder)
end

function heads.Dummy(model, head, look)
	head.Transparency = 1
	local ball = deco(model, head, Vector3.new(1.2, 1.25, 1.2), CFrame.identity, Build.rgb(look.Body), "SmoothPlastic", "Head", Enum.PartType.Ball)
	for _, x in { -0.62, 0.62 } do
		deco(model, ball, Vector3.new(0.05, 0.45, 0.45), CFrame.new(x, 0.1, 0), Color3.fromRGB(25, 25, 25), "SmoothPlastic", "Marker", Enum.PartType.Cylinder)
	end
	deco(model, ball, Vector3.new(0.9, 0.06, 0.1), CFrame.new(0, 0.1, -0.58), Color3.fromRGB(25, 25, 25), "SmoothPlastic", "Stripe")
end

local extras = {}

function extras.Tie(model, parts, look)
	deco(model, parts.Torso, Vector3.new(0.3, 1.3, 0.06), CFrame.new(0, 0.2, -0.53), Build.rgb(look.Accent), "Fabric", "Tie")
	deco(model, parts.Torso, Vector3.new(1.2, 0.3, 0.08), CFrame.new(0, 0.9, -0.5), Build.rgb(look.Shirt), "Fabric", "Collar")
end

function extras.Visor(model, parts, look)
	deco(model, parts.Head, Vector3.new(1.45, 0.08, 0.7), CFrame.new(0, 0.62, -0.5), Build.rgb(look.Accent), "Glass", "Visor").Transparency = 0.3
end

function extras.Antennae() end

function extras.Harness(model, parts, look)
	for _, x in { -0.5, 0.5 } do
		deco(model, parts.Torso, Vector3.new(0.25, 2.05, 1.06), CFrame.new(x, 0, 0), Build.rgb(look.Shirt), "Fabric", "Strap")
	end
	deco(model, parts.Torso, Vector3.new(0.5, 0.5, 0.2), CFrame.new(0, 0.2, -0.55), Build.rgb(look.Accent), "Neon", "Core")
end

function extras.Cloak(model, parts, look)
	deco(model, parts.Torso, Vector3.new(2.3, 2.1, 0.3), CFrame.new(0, -0.1, 0.62), Build.rgb(look.Body), "Fabric", "Cloak")
	for _, x in { -1, 1 } do
		deco(model, parts.Torso, Vector3.new(1.1, 0.4, 1.3), CFrame.new(x * 0.7, 1.05, 0) * CFrame.Angles(0, 0, -x * 0.35), Build.rgb(look.Body), "Fabric", "Mantle")
	end
end

function extras.Trinkets(model, parts, look)
	for i = 0, 3 do
		deco(model, parts.Torso, Vector3.new(0.14, 0.14, 0.14), CFrame.new(-0.6 + i * 0.4, -0.5 - (i % 2) * 0.2, -0.54), Build.rgb(look.Accent), "Foil", "Trinket", Enum.PartType.Ball)
	end
end

function extras.Vest(model, parts, look)
	deco(model, parts.Torso, Vector3.new(2.06, 1.9, 1.06), CFrame.new(0, -0.02, 0), Build.rgb(look.Body), "Fabric", "Vest")
	deco(model, parts.Torso, Vector3.new(0.7, 1.6, 0.08), CFrame.new(0, 0.1, -0.54), Build.rgb(look.Shirt), "Fabric", "Shirt")
	for i = 0, 2 do
		deco(model, parts.Torso, Vector3.new(0.12, 0.12, 0.06), CFrame.new(0, 0.5 - i * 0.45, -0.58), Build.rgb(look.Accent), "Foil", "Button", Enum.PartType.Ball)
	end
end

function extras.Halo(model, parts, look)
	deco(model, parts.Head, Vector3.new(0.1, 1.9, 1.9), CFrame.new(0, 1.35, 0) * CFrame.Angles(0, 0, math.pi / 2), Build.rgb(look.Accent), "Neon", "Halo", Enum.PartType.Cylinder).Transparency = 0.2
end

function extras.Markers(model, parts)
	for _, limbName in { "Left Arm", "Right Arm", "Left Leg", "Right Leg" } do
		deco(model, parts[limbName], Vector3.new(1.02, 0.22, 1.02), CFrame.new(0, 0.2, 0), Color3.fromRGB(25, 25, 25), "SmoothPlastic", "Band")
	end
end

-- Builds a seated-ready surrogate rig with its root at `rootCFrame`.
function PuppetBuilder.build(personality: string, rootCFrame: CFrame, name: string?): Model
	local look = Surrogates.get(personality)
	local model = Instance.new("Model")
	model.Name = name or ("Puppet_" .. personality)
	model:SetAttribute("Surrogate", personality)

	local root = Build.part({ Name = "HumanoidRootPart", Size = Vector3.new(2, 2, 1), CFrame = rootCFrame, Transparency = 1, Parent = model })
	root.Anchored = true
	local torso = limb(model, "Torso", Vector3.new(2, 2, 1), Build.rgb(look.Body))
	local head = limb(model, "Head", Vector3.new(2, 1, 1), Build.rgb(look.Limbs))
	local la = limb(model, "Left Arm", Vector3.new(1, 2, 1), Build.rgb(look.Limbs))
	local ra = limb(model, "Right Arm", Vector3.new(1, 2, 1), Build.rgb(look.Limbs))
	local ll = limb(model, "Left Leg", Vector3.new(1, 2, 1), Build.rgb(look.Limbs))
	local rl = limb(model, "Right Leg", Vector3.new(1, 2, 1), Build.rgb(look.Limbs))

	-- Place parts at their rest pose so decorations weld in the right spots.
	torso.CFrame = rootCFrame
	head.CFrame = rootCFrame * CFrame.new(0, 1.5, 0)
	la.CFrame = rootCFrame * CFrame.new(-1.5, 0, 0)
	ra.CFrame = rootCFrame * CFrame.new(1.5, 0, 0)
	ll.CFrame = rootCFrame * CFrame.new(-0.5, -2, 0)
	rl.CFrame = rootCFrame * CFrame.new(0.5, -2, 0)

	motor("RootJoint", root, root, torso, ROOT_C, ROOT_C)
	motor("Neck", torso, torso, head, NECK_C0, NECK_C1)
	motor("Left Shoulder", torso, torso, la, LS_C0, LS_C1)
	motor("Right Shoulder", torso, torso, ra, RS_C0, RS_C1)
	motor("Left Hip", torso, torso, ll, LH_C0, LH_C1)
	motor("Right Hip", torso, torso, rl, RH_C0, RH_C1)

	local parts = { Torso = torso, Head = head, ["Left Arm"] = la, ["Right Arm"] = ra, ["Left Leg"] = ll, ["Right Leg"] = rl }
	local headBuilder = heads[look.Head]
	if headBuilder then
		headBuilder(model, head, look)
	end
	for _, extra in look.Extras do
		local builder = extras[extra]
		if builder then
			builder(model, parts, look)
		end
	end
	-- Hands: slightly darker cuffs so reach animations read well.
	for _, arm in { la, ra } do
		deco(model, arm, Vector3.new(1.04, 0.4, 1.04), CFrame.new(0, -0.8, 0), Color3.new(0.1, 0.1, 0.11), "SmoothPlastic", "Glove")
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	model.PrimaryPart = root
	return model
end

return PuppetBuilder

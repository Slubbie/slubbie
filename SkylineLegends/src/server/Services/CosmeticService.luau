-- Builds equipped cosmetics onto characters out of parts, so they replicate to
-- everyone and need no uploaded meshes. Effects that play on events (landing
-- effects, victory animations, trail emission) are driven by each client from
-- character attributes set here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cosmetics = require(ReplicatedStorage.Shared.Config.Cosmetics)
local Tags = require(ReplicatedStorage.Shared.Tags)

local DataService = require(script.Parent.Parent.Data.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PlayerService = require(script.Parent.PlayerService)

local CosmeticService = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local function piece(
	parent: Instance,
	limb: BasePart,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Name = "Cosmetic"
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Shape = shape or Enum.PartType.Block
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.CollisionGroup = Tags.Groups.Cosmetic
	part.CFrame = limb.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = limb
	weld.Part1 = part
	weld.Parent = part
	part.Parent = parent
	return part
end

local function c(colors: { Color3 }?, index: number, fallback: Color3): Color3
	return (colors and colors[index]) or fallback
end

-- Outfits -------------------------------------------------------------------------------

local function sleeves(folder: Folder, character: Model, color: Color3, full: boolean, stripe: Color3?)
	for _, name in { "Left Arm", "Right Arm" } do
		local arm = character:FindFirstChild(name) :: BasePart?
		if arm then
			local height = if full then 1.62 else 1.05
			local y = if full then 0.2 else 0.48
			piece(folder, arm, Vector3.new(1.08, height, 1.08), CFrame.new(0, y, 0), color)
			if stripe then
				local side = if name == "Left Arm" then -0.55 else 0.55
				piece(folder, arm, Vector3.new(0.06, height, 0.3), CFrame.new(side, y, 0), stripe, Enum.Material.Neon)
			end
		end
	end
end

local function pants(folder: Folder, character: Model, color: Color3, stripe: Color3?)
	for _, name in { "Left Leg", "Right Leg" } do
		local leg = character:FindFirstChild(name) :: BasePart?
		if leg then
			piece(folder, leg, Vector3.new(1.07, 1.55, 1.07), CFrame.new(0, 0.22, 0), color)
			if stripe then
				local side = if name == "Left Leg" then -0.55 else 0.55
				piece(folder, leg, Vector3.new(0.06, 1.55, 0.25), CFrame.new(side, 0.22, 0), stripe)
			end
		end
	end
end

local function buildOutfit(folder: Folder, character: Model, item: Cosmetics.Item)
	local torso = character:FindFirstChild("Torso") :: BasePart?
	local head = character:FindFirstChild("Head") :: BasePart?
	if not torso or not head then
		return
	end
	local primary = c(item.Colors, 1, Color3.new(0.3, 0.3, 0.3))
	local secondary = c(item.Colors, 2, Color3.new(0.8, 0.8, 0.8))
	local accent = c(item.Colors, 3, Color3.new(1, 0.8, 0.3))
	local style = item.Style

	-- Every outfit has a body shell.
	piece(folder, torso, Vector3.new(2.1, 2.06, 1.12), CFrame.new(), primary)

	if style == "Hoodie" then
		piece(folder, head, Vector3.new(1.45, 1.15, 0.45), CFrame.new(0, 0.05, 0.62), primary)
		piece(folder, head, Vector3.new(1.55, 0.3, 1.25), CFrame.new(0, 0.62, 0.15), primary)
		piece(folder, torso, Vector3.new(1.2, 0.5, 0.08), CFrame.new(0, -0.55, -0.6), secondary)
		piece(folder, torso, Vector3.new(0.08, 0.6, 0.06), CFrame.new(-0.25, 0.55, -0.6), accent)
		piece(folder, torso, Vector3.new(0.08, 0.6, 0.06), CFrame.new(0.25, 0.55, -0.6), accent)
		sleeves(folder, character, primary, true, nil)
	elseif style == "Jacket" then
		piece(folder, torso, Vector3.new(2.16, 0.35, 1.2), CFrame.new(0, 0.95, 0), secondary)
		piece(folder, torso, Vector3.new(0.1, 2.06, 0.06), CFrame.new(0, 0, -0.6), accent, Enum.Material.Neon)
		piece(folder, torso, Vector3.new(2.14, 0.12, 1.16), CFrame.new(0, -0.3, 0), accent)
		sleeves(folder, character, primary, true, accent)
	elseif style == "Vest" then
		piece(folder, torso, Vector3.new(0.6, 0.45, 0.08), CFrame.new(-0.5, -0.3, -0.6), secondary)
		piece(folder, torso, Vector3.new(0.6, 0.45, 0.08), CFrame.new(0.5, -0.3, -0.6), secondary)
		piece(folder, torso, Vector3.new(2.14, 0.15, 1.16), CFrame.new(0, 0.9, 0), accent)
	elseif style == "Coat" then
		piece(folder, torso, Vector3.new(2.1, 1.0, 0.18), CFrame.new(0, -1.45, 0.5), primary)
		piece(folder, torso, Vector3.new(2.18, 0.45, 1.24), CFrame.new(0, 0.95, 0), secondary)
		piece(folder, torso, Vector3.new(2.14, 0.14, 1.16), CFrame.new(0, -0.75, 0), accent)
		sleeves(folder, character, primary, true, nil)
	elseif style == "Suit" then
		piece(folder, torso, Vector3.new(0.3, 1.2, 0.06), CFrame.new(0, 0.25, -0.6), accent)
		piece(folder, torso, Vector3.new(0.9, 0.5, 0.06), CFrame.new(0, 0.8, -0.59), secondary)
		sleeves(folder, character, primary, true, nil)
		pants(folder, character, secondary, nil)
	elseif style == "Robe" then
		piece(folder, torso, Vector3.new(2.14, 1.3, 1.16), CFrame.new(0, -1.55, 0), primary)
		piece(folder, torso, Vector3.new(2.16, 0.2, 1.18), CFrame.new(0, -0.5, 0), accent, Enum.Material.Neon)
		piece(folder, torso, Vector3.new(0.5, 2.06, 0.08), CFrame.new(0, 0, -0.6), secondary)
		sleeves(folder, character, primary, true, nil)
	elseif style == "Tracksuit" then
		sleeves(folder, character, primary, true, secondary)
		pants(folder, character, primary, secondary)
		piece(folder, torso, Vector3.new(0.06, 2.06, 0.06), CFrame.new(0, 0, -0.6), accent)
	end
end

-- Gloves, shoes, packs --------------------------------------------------------------------

local function buildGloves(folder: Folder, character: Model, item: Cosmetics.Item)
	for _, name in { "Left Arm", "Right Arm" } do
		local arm = character:FindFirstChild(name) :: BasePart?
		if arm then
			local primary = c(item.Colors, 1, Color3.new(0.3, 0.3, 0.3))
			local secondary = c(item.Colors, 2, Color3.new(0.1, 0.1, 0.1))
			local height = if item.Style == "Gauntlet" then 0.75 else 0.45
			piece(folder, arm, Vector3.new(1.1, height, 1.1), CFrame.new(0, -1 + height / 2, 0), primary)
			if item.Style == "Wrap" then
				piece(folder, arm, Vector3.new(1.12, 0.1, 1.12), CFrame.new(0, -0.6, 0), secondary)
				piece(folder, arm, Vector3.new(1.12, 0.1, 1.12), CFrame.new(0, -0.82, 0), secondary)
			else
				piece(folder, arm, Vector3.new(0.9, 0.22, 0.1), CFrame.new(0, -0.85, -0.56), secondary, Enum.Material.Neon)
			end
		end
	end
end

local function buildShoes(folder: Folder, character: Model, item: Cosmetics.Item)
	for _, name in { "Left Leg", "Right Leg" } do
		local leg = character:FindFirstChild(name) :: BasePart?
		if leg then
			local primary = c(item.Colors, 1, Color3.new(1, 1, 1))
			local secondary = c(item.Colors, 2, Color3.new(0.2, 0.2, 0.2))
			local height = if item.Style == "Boot" then 0.8 elseif item.Style == "HighTop" then 0.65 else 0.45
			piece(folder, leg, Vector3.new(1.08, height, 1.14), CFrame.new(0, -1 + height / 2, -0.05), primary)
			piece(folder, leg, Vector3.new(1.1, 0.14, 1.22), CFrame.new(0, -0.95, -0.06), secondary)
			piece(folder, leg, Vector3.new(0.08, 0.2, 0.7), CFrame.new(0.55, -0.78, -0.05), secondary, Enum.Material.Neon)
		end
	end
end

local function buildPack(folder: Folder, character: Model, item: Cosmetics.Item)
	local torso = character:FindFirstChild("Torso") :: BasePart?
	if not torso then
		return
	end
	local primary = c(item.Colors, 1, Color3.new(0.4, 0.3, 0.2))
	local secondary = c(item.Colors, 2, Color3.new(1, 0.8, 0.3))
	local style = item.Style
	if style == "Satchel" then
		piece(folder, torso, Vector3.new(1.2, 1.0, 0.45), CFrame.new(0.35, -0.25, 0.75), primary)
		piece(folder, torso, Vector3.new(0.2, 2.5, 0.12), CFrame.new(0, 0.1, -0.6) * CFrame.Angles(0, 0, math.rad(40)), secondary)
	elseif style == "Courier" then
		piece(folder, torso, Vector3.new(1.7, 1.3, 0.6), CFrame.new(0, 0, 0.82), primary)
		piece(folder, torso, Vector3.new(1.74, 0.45, 0.64), CFrame.new(0, 0.48, 0.82), secondary)
	elseif style == "Tank" then
		for _, x in { -0.45, 0.45 } do
			piece(folder, torso, Vector3.new(1.6, 0.7, 0.7), CFrame.new(x, 0, 0.85) * CFrame.Angles(0, 0, math.rad(90)), primary, Enum.Material.Metal, Enum.PartType.Cylinder)
		end
		piece(folder, torso, Vector3.new(0.3, 0.3, 0.3), CFrame.new(0, 0.9, 0.85), secondary, Enum.Material.Neon, Enum.PartType.Ball)
	elseif style == "Planter" then
		piece(folder, torso, Vector3.new(1.5, 0.9, 0.7), CFrame.new(0, -0.3, 0.85), primary, Enum.Material.Wood)
		for i, offset in { Vector3.new(-0.4, 0.4, 0.85), Vector3.new(0.35, 0.55, 0.8), Vector3.new(0, 0.75, 0.95) } do
			local leaf = Color3.fromRGB(70, 150 + i * 15, 80)
			piece(folder, torso, Vector3.new(0.55, 0.55, 0.55), CFrame.new(offset), leaf, Enum.Material.Grass, Enum.PartType.Ball)
		end
		piece(folder, torso, Vector3.new(0.3, 0.3, 0.3), CFrame.new(0.1, 1.05, 0.9), secondary, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	elseif style == "Cube" then
		piece(folder, torso, Vector3.new(1, 1, 1), CFrame.new(0, 0.5, 1.4) * CFrame.Angles(math.rad(45), math.rad(45), 0), primary, Enum.Material.Neon)
		piece(folder, torso, Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 0.5, 1.4) * CFrame.Angles(math.rad(45), math.rad(45), 0), secondary, Enum.Material.ForceField)
	elseif style == "Frame" then
		for _, x in { -0.6, 0.6 } do
			piece(folder, torso, Vector3.new(0.15, 2.6, 0.15), CFrame.new(x, 0.2, 0.75), primary)
		end
		piece(folder, torso, Vector3.new(1.4, 1.2, 0.6), CFrame.new(0, -0.1, 0.95), secondary)
		piece(folder, torso, Vector3.new(0.6, 1.0, 1.0), CFrame.new(0, 1.0, 0.9) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(200, 180, 140), Enum.Material.Fabric, Enum.PartType.Cylinder)
	elseif style == "Wings" then
		for _, side in { -1, 1 } do
			local wing = piece(folder, torso, Vector3.new(0.12, 2.2, 1.4), CFrame.new(side * 0.9, 0.5, 0.9) * CFrame.Angles(0, side * math.rad(35), side * math.rad(-25)), primary)
			wing.Shape = Enum.PartType.Block
			piece(folder, torso, Vector3.new(0.14, 0.25, 1.5), CFrame.new(side * 1.05, 1.35, 1.0) * CFrame.Angles(0, side * math.rad(35), side * math.rad(-25)), secondary, Enum.Material.Neon)
		end
	elseif style == "Beacon" then
		piece(folder, torso, Vector3.new(1.2, 1.2, 0.6), CFrame.new(0, -0.1, 0.8), primary)
		piece(folder, torso, Vector3.new(0.12, 2.4, 0.12), CFrame.new(0.4, 1.3, 0.8), Color3.fromRGB(80, 80, 90), Enum.Material.Metal)
		local tip = piece(folder, torso, Vector3.new(0.35, 0.35, 0.35), CFrame.new(0.4, 2.55, 0.8), secondary, Enum.Material.Neon, Enum.PartType.Ball)
		local light = Instance.new("PointLight")
		light.Color = secondary
		light.Range = 8
		light.Brightness = 1.2
		light.Parent = tip
	elseif style == "Crystal" then
		local crystal = piece(folder, torso, Vector3.new(0.9, 1.6, 0.9), CFrame.new(0, 0.6, 1.3) * CFrame.Angles(0, math.rad(45), math.rad(12)), primary, Enum.Material.Neon)
		local attachment = Instance.new("Attachment")
		attachment.Parent = crystal
		local motes = Instance.new("ParticleEmitter")
		motes.Texture = SPARKLE
		motes.Color = ColorSequence.new(secondary)
		motes.LightEmission = 1
		motes.Rate = 6
		motes.Lifetime = NumberRange.new(0.8, 1.4)
		motes.Speed = NumberRange.new(0.5, 1.5)
		motes.SpreadAngle = Vector2.new(180, 180)
		motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
		motes.Parent = attachment
	elseif style == "Banner" then
		piece(folder, torso, Vector3.new(0.14, 4.2, 0.14), CFrame.new(-0.6, 1.4, 0.75), Color3.fromRGB(90, 70, 50), Enum.Material.Wood)
		piece(folder, torso, Vector3.new(0.06, 1.3, 1.6), CFrame.new(-0.6, 2.7, 1.55), primary, Enum.Material.Fabric)
		piece(folder, torso, Vector3.new(0.07, 0.3, 1.6), CFrame.new(-0.6, 2.3, 1.55), secondary, Enum.Material.Fabric)
	end
end

local function buildTrail(folder: Folder, character: Model, item: Cosmetics.Item)
	local torso = character:FindFirstChild("Torso") :: BasePart?
	if not torso then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailTop"
	a0.Position = Vector3.new(0, 0.8, 0.3)
	a0.Parent = torso
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailBottom"
	a1.Position = Vector3.new(0, -0.9, 0.3)
	a1.Parent = torso
	local first = c(item.Colors, 1, Color3.new(1, 1, 1))
	local second = c(item.Colors, 2, first)
	local trail = Instance.new("Trail")
	trail.Name = "SkylineTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(first, second)
	trail.Lifetime = if item.Style == "Ribbon" then 0.35 else 0.22
	trail.LightEmission = if item.Style == "Aether" or item.Style == "Ribbon" then 0.7 else 0.3
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
	trail.MinLength = 0.2
	trail.FaceCamera = true
	trail.Enabled = false -- clients enable it at speed
	trail.Parent = folder
	if item.Style ~= "Ribbon" then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "SkylineTrailParticles"
		emitter.Texture = SPARKLE
		emitter.Color = ColorSequence.new(first, second)
		emitter.LightEmission = 0.8
		emitter.Rate = 0 -- clients raise it at speed
		emitter.Lifetime = NumberRange.new(0.4, 0.9)
		emitter.Speed = NumberRange.new(0.5, 2)
		emitter.SpreadAngle = Vector2.new(60, 60)
		emitter.Drag = 2
		if item.Style == "Leaves" then
			emitter.Acceleration = Vector3.new(0, -6, 0)
			emitter.RotSpeed = NumberRange.new(-180, 180)
			emitter.Size = NumberSequence.new(0.35)
		elseif item.Style == "Frost" then
			emitter.Acceleration = Vector3.new(0, -2, 0)
			emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
		elseif item.Style == "Sparks" then
			emitter.Acceleration = Vector3.new(0, -30, 0)
			emitter.Speed = NumberRange.new(3, 6)
			emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
		else
			emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
		end
		emitter.Parent = a1
	end
end

-- Apply ---------------------------------------------------------------------------------

function CosmeticService.Apply(player: Player)
	local character = player.Character
	local profile = DataService.Get(player)
	if not character or not profile then
		return
	end
	local old = character:FindFirstChild("SkylineCosmetics")
	if old then
		old:Destroy()
	end
	for _, name in { "TrailTop", "TrailBottom" } do
		local torso = character:FindFirstChild("Torso")
		local attachment = torso and torso:FindFirstChild(name)
		if attachment then
			attachment:Destroy()
		end
	end
	local folder = Instance.new("Folder")
	folder.Name = "SkylineCosmetics"
	folder.Parent = character

	local equipped = profile.Equipped
	local function get(category: string): Cosmetics.Item?
		local id = equipped[category]
		local item = id and Cosmetics.ById[id]
		if item and item.Category == category and profile.Inventory[id] then
			return item
		end
		return nil
	end

	local outfit = get("Outfit")
	if outfit and outfit.Style ~= "None" then
		buildOutfit(folder, character, outfit)
	end
	local gloves = get("Gloves")
	if gloves and gloves.Style ~= "None" then
		buildGloves(folder, character, gloves)
	end
	local shoes = get("Shoes")
	if shoes and shoes.Style ~= "None" then
		buildShoes(folder, character, shoes)
	end
	local pack = get("Backpack")
	if pack and pack.Style ~= "None" then
		buildPack(folder, character, pack)
	end
	local trail = get("Trail")
	if trail and trail.Style ~= "None" then
		buildTrail(folder, character, trail)
	end

	local landing = get("Landing")
	character:SetAttribute("LandingFx", if landing then landing.Style else "Dust")
	character:SetAttribute("LandingColor", if landing and landing.Colors and landing.Colors[1] then landing.Colors[1] else nil)
	local victory = get("Victory")
	character:SetAttribute("Victory", if victory then victory.Style else "FistPump")
	local title = get("Title")
	player:SetAttribute("Title", if title and title.Text and title.Text ~= "" then title.Text else nil)
end

function CosmeticService.Start()
	EconomyService.OnEquipChanged = CosmeticService.Apply
	table.insert(PlayerService.CharacterAdded, function(player, character)
		character:WaitForChild("Torso", 10)
		CosmeticService.Apply(player)
	end)
end

return CosmeticService

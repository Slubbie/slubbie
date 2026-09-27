-- Builds villager characters: an R6 rig coloured from the NPC's Look, with
-- hair, hats and accessories modelled from parts, default walk/idle
-- animations, a talk prompt and attributes the client uses for nameplates.

local Players = game:GetService("Players")

local NpcBuilder = {}

local ANIMS = {
	Idle = "rbxassetid://180435571",
	Walk = "rbxassetid://180426354",
}

local function part(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

local function weld(a: BasePart, b: BasePart, offset: CFrame)
	b.CFrame = a.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

local function addHair(head: BasePart, look: any, model: Model)
	local color = look.Hair
	local style = look.HairStyle
	local folder = Instance.new("Folder")
	folder.Name = "Hair"
	folder.Parent = model
	if style == "Hood" then
		local hood = part(folder, { Name = "Hood", Size = Vector3.new(2.3, 1.6, 2.3), Color = look.Shirt, Material = Enum.Material.Fabric, Shape = Enum.PartType.Ball })
		weld(head, hood, CFrame.new(0, 0.35, 0.15))
		return
	end
	local cap = part(folder, { Name = "Top", Size = Vector3.new(2.1, 0.7, 2.1), Color = color, Material = Enum.Material.SmoothPlastic })
	weld(head, cap, CFrame.new(0, 0.6, 0.05))
	if style == "Long" or style == "Pigtails" or style == "Braids" then
		local back = part(folder, { Name = "Back", Size = Vector3.new(2, 1.8, 0.4), Color = color, Material = Enum.Material.SmoothPlastic })
		weld(head, back, CFrame.new(0, -0.3, 0.9))
		if style ~= "Long" then
			for _, side in { -1, 1 } do
				local tail = part(folder, { Name = "Tail", Size = Vector3.new(0.5, 1.4, 0.5), Color = color, Material = Enum.Material.SmoothPlastic })
				weld(head, tail, CFrame.new(side * 1.05, -0.5, 0.4))
			end
		end
	elseif style == "Bun" then
		local bun = part(folder, { Name = "Bun", Size = Vector3.new(0.9, 0.9, 0.9), Color = color, Shape = Enum.PartType.Ball })
		weld(head, bun, CFrame.new(0, 0.9, 0.6))
	elseif style == "Ponytail" then
		local tail = part(folder, { Name = "Tail", Size = Vector3.new(0.5, 1.5, 0.5), Color = color })
		weld(head, tail, CFrame.new(0, -0.1, 1.1) * CFrame.Angles(math.rad(-20), 0, 0))
	elseif style == "Beard" then
		local beard = part(folder, { Name = "Beard", Size = Vector3.new(1.6, 0.8, 0.4), Color = color })
		weld(head, beard, CFrame.new(0, -0.55, -0.55))
	elseif style == "Messy" then
		for i = 1, 4 do
			local tuft = part(folder, { Name = "Tuft", Size = Vector3.new(0.5, 0.5, 0.5), Color = color, Shape = Enum.PartType.Ball })
			weld(head, tuft, CFrame.new(-0.7 + i * 0.35, 0.95, -0.2 + (i % 2) * 0.4))
		end
	elseif style == "Bob" then
		local sides = part(folder, { Name = "Sides", Size = Vector3.new(2.2, 1.1, 2), Color = color })
		weld(head, sides, CFrame.new(0, 0.1, 0.2))
	elseif style == "Slick" then
		cap.Size = Vector3.new(2.05, 0.45, 2.05)
	end
end

local HATS = {
	Straw = function(folder, head, color)
		local brim = part(folder, { Name = "Brim", Size = Vector3.new(3.2, 0.15, 3.2), Color = color, Material = Enum.Material.Fabric, Shape = Enum.PartType.Cylinder })
		weld(head, brim, CFrame.new(0, 0.95, 0) * CFrame.Angles(0, 0, math.rad(90)))
		local crown = part(folder, { Name = "Crown", Size = Vector3.new(0.7, 1.7, 1.7), Color = color, Material = Enum.Material.Fabric, Shape = Enum.PartType.Cylinder })
		weld(head, crown, CFrame.new(0, 1.25, 0) * CFrame.Angles(0, 0, math.rad(90)))
	end,
	Cap = function(folder, head, color)
		local crown = part(folder, { Name = "Crown", Size = Vector3.new(2.15, 0.7, 2.15), Color = color })
		weld(head, crown, CFrame.new(0, 0.85, 0))
		local bill = part(folder, { Name = "Bill", Size = Vector3.new(1.6, 0.12, 1.1), Color = color })
		weld(head, bill, CFrame.new(0, 0.55, -1.3))
	end,
	Cowboy = function(folder, head, color)
		local brim = part(folder, { Name = "Brim", Size = Vector3.new(0.15, 3.4, 3.4), Color = color, Material = Enum.Material.Leather, Shape = Enum.PartType.Cylinder })
		weld(head, brim, CFrame.new(0, 0.9, 0) * CFrame.Angles(0, 0, math.rad(90)))
		local crown = part(folder, { Name = "Crown", Size = Vector3.new(1.9, 1, 1.7), Color = color, Material = Enum.Material.Leather })
		weld(head, crown, CFrame.new(0, 1.4, 0))
	end,
	Chef = function(folder, head, color)
		local band = part(folder, { Name = "Band", Size = Vector3.new(0.6, 2.1, 2.1), Color = color, Shape = Enum.PartType.Cylinder })
		weld(head, band, CFrame.new(0, 1, 0) * CFrame.Angles(0, 0, math.rad(90)))
		local puff = part(folder, { Name = "Puff", Size = Vector3.new(2.4, 1.6, 2.4), Color = color, Shape = Enum.PartType.Ball })
		weld(head, puff, CFrame.new(0, 1.9, 0))
	end,
	Beanie = function(folder, head, color)
		local b = part(folder, { Name = "Beanie", Size = Vector3.new(2.2, 1.3, 2.2), Color = color, Material = Enum.Material.Fabric, Shape = Enum.PartType.Ball })
		weld(head, b, CFrame.new(0, 0.75, 0))
	end,
	HardHat = function(folder, head, color)
		local b = part(folder, { Name = "Dome", Size = Vector3.new(2.3, 1.2, 2.4), Color = color, Shape = Enum.PartType.Ball })
		weld(head, b, CFrame.new(0, 0.85, 0))
	end,
	Explorer = function(folder, head, color)
		local brim = part(folder, { Name = "Brim", Size = Vector3.new(0.12, 3, 3), Color = color, Shape = Enum.PartType.Cylinder })
		weld(head, brim, CFrame.new(0, 0.9, 0) * CFrame.Angles(0, 0, math.rad(90)))
		local dome = part(folder, { Name = "Dome", Size = Vector3.new(2, 1.2, 2), Color = color, Shape = Enum.PartType.Ball })
		weld(head, dome, CFrame.new(0, 1.2, 0))
	end,
	Wide = function(folder, head, color)
		local brim = part(folder, { Name = "Brim", Size = Vector3.new(0.12, 4, 4), Color = color, Shape = Enum.PartType.Cylinder })
		weld(head, brim, CFrame.new(0, 0.95, 0) * CFrame.Angles(0, 0, math.rad(90)))
		local cone = part(folder, { Name = "Cone", Size = Vector3.new(1.6, 1.4, 1.6), Color = color })
		weld(head, cone, CFrame.new(0, 1.55, 0))
	end,
	TopHat = function(folder, head, color)
		local brim = part(folder, { Name = "Brim", Size = Vector3.new(0.12, 2.8, 2.8), Color = color, Shape = Enum.PartType.Cylinder })
		weld(head, brim, CFrame.new(0, 0.9, 0) * CFrame.Angles(0, 0, math.rad(90)))
		local tube = part(folder, { Name = "Tube", Size = Vector3.new(2, 1.7, 1.7), Color = color, Shape = Enum.PartType.Cylinder })
		weld(head, tube, CFrame.new(0, 1.8, 0) * CFrame.Angles(0, 0, math.rad(90)))
	end,
	Captain = function(folder, head, color)
		local crown = part(folder, { Name = "Crown", Size = Vector3.new(2.3, 0.7, 2.3), Color = color })
		weld(head, crown, CFrame.new(0, 0.95, 0))
		local bill = part(folder, { Name = "Bill", Size = Vector3.new(1.6, 0.12, 0.8), Color = Color3.fromRGB(30, 30, 40) })
		weld(head, bill, CFrame.new(0, 0.65, -1.2))
	end,
	Flower = function(folder, head, color)
		for i = 0, 4 do
			local petal = part(folder, { Name = "Petal", Size = Vector3.new(0.45, 0.45, 0.45), Color = color, Shape = Enum.PartType.Ball })
			local angle = i / 5 * math.pi * 2
			weld(head, petal, CFrame.new(0.8 + math.cos(angle) * 0.3, 0.8 + math.sin(angle) * 0.3, -0.3))
		end
	end,
	Goggles = function(folder, head, color)
		local band = part(folder, { Name = "Band", Size = Vector3.new(2.15, 0.35, 2.15), Color = Color3.fromRGB(40, 40, 40) })
		weld(head, band, CFrame.new(0, 0.45, 0))
		for _, side in { -1, 1 } do
			local lens = part(folder, { Name = "Lens", Size = Vector3.new(0.5, 0.2, 0.5), Color = color, Material = Enum.Material.Glass, Shape = Enum.PartType.Cylinder })
			weld(head, lens, CFrame.new(side * 0.4, 0.45, -1.05) * CFrame.Angles(0, math.rad(90), 0))
		end
	end,
	Stars = function(folder, head, color)
		local hat = part(folder, { Name = "Cone", Size = Vector3.new(1.5, 2.2, 1.5), Color = Color3.fromRGB(40, 40, 110) })
		weld(head, hat, CFrame.new(0, 1.8, 0))
		local star = part(folder, { Name = "Star", Size = Vector3.new(0.5, 0.5, 0.5), Color = color, Material = Enum.Material.Neon, Shape = Enum.PartType.Ball })
		weld(head, star, CFrame.new(0, 3, 0))
	end,
}

local function accessory(model: Model, look: any)
	local torso = model:FindFirstChild("Torso") :: BasePart?
	local head = model:FindFirstChild("Head") :: BasePart?
	if not torso or not head then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Accessories"
	folder.Parent = model
	local kind = look.Accessory
	if kind == "Apron" then
		local apron = part(folder, { Name = "Apron", Size = Vector3.new(1.8, 1.9, 0.1), Color = Color3.fromRGB(245, 240, 225), Material = Enum.Material.Fabric })
		weld(torso, apron, CFrame.new(0, -0.3, -0.55))
	elseif kind == "Glasses" then
		for _, side in { -1, 1 } do
			local lens = part(folder, { Name = "Lens", Size = Vector3.new(0.45, 0.35, 0.05), Color = Color3.fromRGB(30, 30, 30), Transparency = 0.2 })
			weld(head, lens, CFrame.new(side * 0.35, 0.15, -0.62))
		end
	elseif kind == "Backpack" then
		local pack = part(folder, { Name = "Pack", Size = Vector3.new(1.6, 1.6, 0.8), Color = Color3.fromRGB(120, 90, 60), Material = Enum.Material.Leather })
		weld(torso, pack, CFrame.new(0, 0.1, 0.8))
	elseif kind == "Cloak" then
		local cloak = part(folder, { Name = "Cloak", Size = Vector3.new(2.2, 3.4, 0.15), Color = look.Shirt, Material = Enum.Material.Fabric })
		weld(torso, cloak, CFrame.new(0, -0.6, 0.6))
	elseif kind == "Scarf" then
		local scarf = part(folder, { Name = "Scarf", Size = Vector3.new(1.3, 0.4, 1.3), Color = look.Pants, Material = Enum.Material.Fabric, Shape = Enum.PartType.Cylinder })
		weld(torso, scarf, CFrame.new(0, 1, 0) * CFrame.Angles(0, 0, math.rad(90)))
	elseif kind == "Toolbelt" then
		local belt = part(folder, { Name = "Belt", Size = Vector3.new(2.1, 0.35, 1.1), Color = Color3.fromRGB(90, 60, 40), Material = Enum.Material.Leather })
		weld(torso, belt, CFrame.new(0, -0.85, 0))
	elseif kind == "Mustache" then
		local stache = part(folder, { Name = "Mustache", Size = Vector3.new(0.9, 0.2, 0.15), Color = look.Hair })
		weld(head, stache, CFrame.new(0, -0.25, -0.62))
	elseif kind == "Goggles" then
		HATS.Goggles(folder, head, Color3.fromRGB(150, 200, 230))
	end
	if look.Hat and HATS[look.Hat] then
		HATS[look.Hat](folder, head, look.HatColor or look.Hair)
	end
end

-- Build an NPC model (not parented).
function NpcBuilder.Build(npc: any): Model
	local look = npc.Look
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = look.Skin
	description.TorsoColor = look.Shirt
	description.LeftArmColor = look.Shirt
	description.RightArmColor = look.Shirt
	description.LeftLegColor = look.Pants
	description.RightLegColor = look.Pants
	local model: Model
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R6)
	end)
	if ok and result then
		model = result
	else
		-- Offline fallback (e.g. Studio without internet): a simple blocky rig.
		model = Instance.new("Model")
		local root = part(model, { Name = "HumanoidRootPart", Size = Vector3.new(2, 2, 1), Transparency = 1, Anchored = false })
		local torso = part(model, { Name = "Torso", Size = Vector3.new(2, 2, 1), Color = look.Shirt })
		weld(root, torso, CFrame.new())
		local head = part(model, { Name = "Head", Size = Vector3.new(2, 1, 1), Color = look.Skin })
		weld(torso, head, CFrame.new(0, 1.5, 0))
		for _, side in { -1, 1 } do
			local arm = part(model, { Name = if side < 0 then "Left Arm" else "Right Arm", Size = Vector3.new(1, 2, 1), Color = look.Shirt })
			weld(torso, arm, CFrame.new(side * 1.5, 0, 0))
			local leg = part(model, { Name = if side < 0 then "Left Leg" else "Right Leg", Size = Vector3.new(1, 2, 1), Color = look.Pants })
			weld(torso, leg, CFrame.new(side * 0.5, -2, 0))
		end
		local humanoid = Instance.new("Humanoid")
		humanoid.Parent = model
		model.PrimaryPart = root
	end
	model.Name = npc.Id
	local animate = model:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.WalkSpeed = 9
	humanoid.AutoRotate = true
	local head = model:FindFirstChild("Head") :: BasePart?
	if head then
		local face = head:FindFirstChildOfClass("Decal")
		if not face then
			local decal = Instance.new("Decal")
			decal.Name = "face"
			decal.Texture = "rbxasset://textures/face.png"
			decal.Face = Enum.NormalId.Front
			decal.Parent = head
		end
		addHair(head, look, model)
	end
	accessory(model, look)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanTouch = false
		end
	end
	if look.Height and look.Height ~= 1 then
		pcall(function()
			model:ScaleTo(look.Height)
		end)
	end
	model:SetAttribute("NpcId", npc.Id)
	model:SetAttribute("NpcName", npc.Name)
	model:SetAttribute("Role", npc.Role)

	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TalkPrompt"
	prompt.ActionText = "Talk"
	prompt.ObjectText = npc.Name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute("Kind", "Npc")
	prompt:SetAttribute("Target", npc.Id)
	prompt.Parent = root

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		local newAnimator = Instance.new("Animator")
		newAnimator.Parent = humanoid
	end
	return model
end

-- Load idle/walk tracks for a built NPC.
function NpcBuilder.Tracks(model: Model): { [string]: AnimationTrack }
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local tracks = {}
	if not animator then
		return tracks
	end
	for name, id in ANIMS do
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if ok and track then
			track.Looped = true
			tracks[name] = track
		end
	end
	return tracks
end

return NpcBuilder

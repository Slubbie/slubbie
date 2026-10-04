-- The people of Meridian: builds each character at their spot as an R6 rig
-- with a hand-made look (hair and hats from parts), a name card and a talk
-- prompt. Clients animate them (Animation/Animator) and run the dialogue.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NPCs = require(ReplicatedStorage.Shared.Config.NPCs)
local Tags = require(ReplicatedStorage.Shared.Tags)

local NPCService = {}

NPCService.Spots = {} :: { [string]: CFrame }

local folder: Folder

local function weld(part: BasePart, to: BasePart, offset: CFrame)
	part.CFrame = to.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = to
	w.Part1 = part
	w.Parent = part
end

local function piece(
	model: Model,
	head: BasePart,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Shape = shape or Enum.PartType.Block
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CollisionGroup = Tags.Groups.Cosmetic
	weld(part, head, offset)
	part.Parent = model
	return part
end

local function dress(model: Model, npc: NPCs.NPC)
	local head = model:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local look = npc.Look
	local hair = look.Hair
	local hat = look.Hat or "None"
	-- Hair cap (skipped under full hoods/helmets).
	if hat ~= "Hood" and hat ~= "Hardhat" and hat ~= "Wrap" and hat ~= "Fur" then
		piece(model, head, Vector3.new(2.1, 0.5, 1.15), CFrame.new(0, 0.55, 0.05), hair, Enum.Material.Fabric)
		piece(model, head, Vector3.new(2.1, 0.9, 0.3), CFrame.new(0, 0.2, 0.5), hair, Enum.Material.Fabric)
	end
	local accent = look.Shirt
	if hat == "Cap" then
		piece(model, head, Vector3.new(2.15, 0.45, 1.2), CFrame.new(0, 0.75, 0), accent)
		piece(model, head, Vector3.new(1.4, 0.12, 0.8), CFrame.new(0, 0.6, -0.85), accent)
	elseif hat == "Bun" then
		piece(
			model,
			head,
			Vector3.new(0.8, 0.8, 0.8),
			CFrame.new(0, 0.7, 0.55),
			hair,
			Enum.Material.Fabric,
			Enum.PartType.Ball
		)
	elseif hat == "Beanie" then
		piece(model, head, Vector3.new(2.2, 0.7, 1.25), CFrame.new(0, 0.8, 0), accent, Enum.Material.Fabric)
	elseif hat == "Hood" then
		piece(model, head, Vector3.new(2.3, 1.4, 1.35), CFrame.new(0, 0.35, 0.12), accent, Enum.Material.Fabric)
	elseif hat == "Hardhat" then
		piece(model, head, Vector3.new(2.3, 0.6, 1.4), CFrame.new(0, 0.8, 0), Color3.fromRGB(240, 196, 40))
		piece(model, head, Vector3.new(2.6, 0.1, 1.7), CFrame.new(0, 0.55, 0), Color3.fromRGB(240, 196, 40))
	elseif hat == "Goggles" or hat == "Glasses" or hat == "Shades" or hat == "Visor" then
		local color = if hat == "Shades"
			then Color3.fromRGB(20, 20, 24)
			elseif hat == "Visor" then Color3.fromRGB(120, 230, 255)
			else Color3.fromRGB(60, 60, 70)
		piece(
			model,
			head,
			Vector3.new(1.9, 0.35, 0.15),
			CFrame.new(0, 0.15, -0.6),
			color,
			if hat == "Visor" then Enum.Material.Neon else Enum.Material.Glass
		)
		if hat == "Goggles" then
			piece(
				model,
				head,
				Vector3.new(2.15, 0.2, 1.25),
				CFrame.new(0, 0.15, 0),
				Color3.fromRGB(80, 60, 40),
				Enum.Material.Leather
			)
		end
	elseif hat == "Crown" then
		piece(
			model,
			head,
			Vector3.new(1.6, 0.4, 1.0),
			CFrame.new(0, 0.9, 0),
			Color3.fromRGB(255, 205, 70),
			Enum.Material.Neon
		)
	elseif hat == "Halo" then
		local ring = piece(
			model,
			head,
			Vector3.new(0.12, 1.6, 1.6),
			CFrame.new(0, 1.3, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(255, 235, 150),
			Enum.Material.Neon,
			Enum.PartType.Cylinder
		)
		ring.Transparency = 0.2
	elseif hat == "Antenna" then
		piece(
			model,
			head,
			Vector3.new(0.1, 1.2, 0.1),
			CFrame.new(0.5, 1.1, 0),
			Color3.fromRGB(60, 60, 70),
			Enum.Material.Metal
		)
		piece(
			model,
			head,
			Vector3.new(0.3, 0.3, 0.3),
			CFrame.new(0.5, 1.75, 0),
			Color3.fromRGB(255, 80, 80),
			Enum.Material.Neon,
			Enum.PartType.Ball
		)
	elseif hat == "Bandana" or hat == "Wrap" then
		piece(
			model,
			head,
			Vector3.new(2.15, if hat == "Wrap" then 1.0 else 0.35, 1.2),
			CFrame.new(0, if hat == "Wrap" then 0.5 else 0.45, 0),
			accent,
			Enum.Material.Fabric
		)
	elseif hat == "Straw" or hat == "Ranger" then
		local color = if hat == "Straw" then Color3.fromRGB(225, 196, 120) else Color3.fromRGB(120, 90, 60)
		piece(
			model,
			head,
			Vector3.new(0.15, 3.2, 3.2),
			CFrame.new(0, 0.62, 0) * CFrame.Angles(0, 0, math.rad(90)),
			color,
			Enum.Material.Fabric,
			Enum.PartType.Cylinder
		)
		piece(
			model,
			head,
			Vector3.new(0.8, 1.6, 1.6),
			CFrame.new(0, 0.95, 0) * CFrame.Angles(0, 0, math.rad(90)),
			color,
			Enum.Material.Fabric,
			Enum.PartType.Cylinder
		)
	elseif hat == "Fur" then
		piece(
			model,
			head,
			Vector3.new(2.4, 1.0, 1.45),
			CFrame.new(0, 0.6, 0.05),
			Color3.fromRGB(150, 120, 90),
			Enum.Material.Fabric
		)
	elseif hat == "Headset" then
		piece(
			model,
			head,
			Vector3.new(2.3, 0.15, 0.3),
			CFrame.new(0, 0.85, 0),
			Color3.fromRGB(40, 40, 46),
			Enum.Material.Metal
		)
		for _, x in { -1.1, 1.1 } do
			piece(
				model,
				head,
				Vector3.new(0.3, 0.6, 0.6),
				CFrame.new(x, 0, 0),
				Color3.fromRGB(40, 40, 46),
				Enum.Material.Metal
			)
		end
	elseif hat == "Leaves" then
		for i = 1, 5 do
			local angle = i * math.pi * 2 / 5
			piece(
				model,
				head,
				Vector3.new(0.6, 0.15, 0.9),
				CFrame.new(math.cos(angle) * 0.6, 0.8, math.sin(angle) * 0.5) * CFrame.Angles(0, angle, math.rad(20)),
				Color3.fromRGB(100, 170, 70),
				Enum.Material.Grass
			)
		end
	end
end

local function build(npc: NPCs.NPC, spot: CFrame)
	local description = Instance.new("HumanoidDescription")
	local look = npc.Look
	description.HeadColor = look.Skin
	description.LeftArmColor = look.Shirt
	description.RightArmColor = look.Shirt
	description.TorsoColor = look.Shirt
	description.LeftLegColor = look.Pants
	description.RightLegColor = look.Pants
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R6)
	end)
	if not ok or not model then
		warn("[NPC] Could not build " .. npc.Id .. ": " .. tostring(model))
		return
	end
	model.Name = npc.Id
	local animate = model:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.BreakJointsOnDeath = false
	end
	-- NPCs never block runners or cameras.
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = Tags.Groups.Cosmetic
			part.CanQuery = false
		end
	end
	dress(model, npc)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.Anchored = true
	end
	model:PivotTo(spot + Vector3.new(0, 3, 0))

	-- Name card.
	local head = model:FindFirstChild("Head") :: BasePart?
	if head then
		local gui = Instance.new("BillboardGui")
		gui.Name = "NameCard"
		gui.Size = UDim2.fromOffset(220, 52)
		gui.StudsOffset = Vector3.new(0, 2.6, 0)
		gui.MaxDistance = 70
		gui.LightInfluence = 0
		gui.Parent = head
		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(1, 0, 0.58, 0)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.GothamBold
		name.TextScaled = true
		name.TextColor3 = Color3.new(1, 1, 1)
		name.TextStrokeTransparency = 0.4
		name.Text = npc.Name
		name.Parent = gui
		local role = Instance.new("TextLabel")
		role.Size = UDim2.new(1, 0, 0.4, 0)
		role.Position = UDim2.fromScale(0, 0.6)
		role.BackgroundTransparency = 1
		role.Font = Enum.Font.Gotham
		role.TextScaled = true
		role.TextColor3 = Color3.fromRGB(255, 220, 150)
		role.TextStrokeTransparency = 0.5
		role.Text = npc.Role
		role.Parent = gui

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "TalkPrompt"
		prompt.ActionText = "Talk"
		prompt.ObjectText = npc.Name
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("Npc", npc.Id)
		prompt.Parent = head
	end

	model:SetAttribute("Npc", npc.Id)
	model:SetAttribute("RigKind", "NPC")
	model:SetAttribute("MS", "Ground")
	if npc.Pose then
		model:SetAttribute("Emote", npc.Pose)
		model:SetAttribute("EmoteAt", 1)
	end
	CollectionService:AddTag(model, Tags.Rig)
	model.Parent = folder
end

function NPCService.Start()
	folder = Instance.new("Folder")
	folder.Name = "SkylineNPCs"
	folder.Parent = workspace
	local spots: { [string]: CFrame } = {}
	for _, part in CollectionService:GetTagged(Tags.NPCSpot) do
		if part:IsA("BasePart") then
			local id = part:GetAttribute("Id")
			if type(id) == "string" then
				spots[id] = part.CFrame
			end
		end
	end
	for _, npc in NPCs.List do
		local spot = spots[npc.Spot]
		if spot then
			NPCService.Spots[npc.Id] = spot
			task.spawn(build, npc, spot)
		else
			warn("[NPC] No spot for " .. npc.Id .. " (" .. npc.Spot .. ")")
		end
	end
end

return NPCService

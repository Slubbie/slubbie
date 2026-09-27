-- Client-side world visuals: spinning shards with a pickup burst, spinning
-- beacon rings and crystals, drifting light motes in the air, and other
-- players' grapple ropes (from their relayed GrapplePoint attribute).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local VFX = require(script.Parent.VFX)

local WorldFX = {}

local shards: { [BasePart]: CFrame } = {}
local spinners: { [Instance]: CFrame } = {}

local function addSpinner(instance: Instance)
	if instance:IsA("BasePart") then
		spinners[instance] = instance.CFrame
	elseif instance:IsA("Model") then
		spinners[instance] = instance:GetPivot()
	end
end

-- Soft glowing specks drifting through the air around the camera.
local function createMotes()
	local box = Instance.new("Part")
	box.Name = "AmbientMotes"
	box.Anchored = true
	box.CanCollide = false
	box.CanQuery = false
	box.CanTouch = false
	box.Transparency = 1
	box.Size = Vector3.new(140, 70, 140)
	local motes = Instance.new("ParticleEmitter")
	motes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	motes.Shape = Enum.ParticleEmitterShape.Box
	motes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	motes.Color = ColorSequence.new(Color3.fromRGB(255, 240, 210))
	motes.LightEmission = 1
	motes.Rate = 14
	motes.Lifetime = NumberRange.new(6, 10)
	motes.Speed = NumberRange.new(0.3, 1.2)
	motes.SpreadAngle = Vector2.new(180, 180)
	motes.Acceleration = Vector3.new(0.4, 0.15, 0.2)
	motes.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, 0.25),
		NumberSequenceKeypoint.new(0.8, 0.25),
		NumberSequenceKeypoint.new(1, 0),
	})
	motes.Parent = box
	return box
end

local function addShard(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	shards[part] = part.CFrame
	part:GetAttributeChangedSignal("Collected"):Connect(function()
		if part:GetAttribute("Collected") then
			VFX.Flash(part.Position, part.Color, 9)
			VFX.Sparks(part.Position, part.Color, 16)
		end
	end)
end

-- Other players' ropes ---------------------------------------------------------

type Rope = { Beam: Beam, Hand: Attachment, Anchor: Attachment }
local ropes: { [Player]: Rope } = {}

local function clearRope(player: Player)
	local rope = ropes[player]
	if rope then
		rope.Beam:Destroy()
		rope.Hand:Destroy()
		rope.Anchor:Destroy()
		ropes[player] = nil
	end
end

local function updateRope(player: Player)
	local character = player.Character
	local point = character and character:GetAttribute("GrapplePoint")
	local arm = character and character:FindFirstChild("Right Arm")
	if typeof(point) ~= "Vector3" or not arm or not arm:IsA("BasePart") then
		clearRope(player)
		return
	end
	local rope = ropes[player]
	if not rope or rope.Hand.Parent ~= arm then
		clearRope(player)
		local hand = Instance.new("Attachment")
		hand.Position = Vector3.new(0, -arm.Size.Y / 2, 0)
		hand.Parent = arm
		local anchor = Instance.new("Attachment")
		anchor.Parent = workspace.Terrain
		local beam = Instance.new("Beam")
		beam.Attachment0 = hand
		beam.Attachment1 = anchor
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Width0 = 0.2
		beam.Width1 = 0.12
		beam.FaceCamera = true
		beam.Parent = arm
		rope = { Beam = beam, Hand = hand, Anchor = anchor }
		ropes[player] = rope
	end
	rope.Anchor.WorldPosition = point
	rope.Beam.Color = ColorSequence.new(VFX.PlayerColor(player))
end

function WorldFX.Start()
	for _, part in CollectionService:GetTagged("Shard") do
		addShard(part)
	end
	CollectionService:GetInstanceAddedSignal("Shard"):Connect(addShard)
	CollectionService:GetInstanceRemovedSignal("Shard"):Connect(function(part)
		shards[part] = nil
	end)
	for _, instance in CollectionService:GetTagged("Spinner") do
		addSpinner(instance)
	end
	CollectionService:GetInstanceAddedSignal("Spinner"):Connect(addSpinner)
	CollectionService:GetInstanceRemovedSignal("Spinner"):Connect(function(instance)
		spinners[instance] = nil
	end)
	local motes = createMotes()
	Players.PlayerRemoving:Connect(clearRope)

	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for part, base in shards do
			local bob = math.sin(t * 2 + base.X * 0.1) * 0.4
			part.CFrame = base * CFrame.new(0, bob, 0) * CFrame.Angles(0, t * 2, 0)
		end
		for instance, base in spinners do
			local speed = instance:GetAttribute("SpinSpeed") or 0.5
			-- Spin around world-up through the object's centre, keeping its tilt.
			local spun = CFrame.new(base.Position) * CFrame.Angles(0, t * speed, 0) * base.Rotation
			if instance:IsA("Model") then
				instance:PivotTo(spun)
			elseif instance:IsA("BasePart") then
				instance.CFrame = spun
			end
		end
		local camera = workspace.CurrentCamera
		motes.Parent = camera
		motes.Position = camera.CFrame.Position
		for _, player in Players:GetPlayers() do
			if player ~= Players.LocalPlayer then
				updateRope(player)
			end
		end
	end)
end

return WorldFX

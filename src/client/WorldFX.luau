-- Client-side world visuals: spinning shards with a pickup burst, and other
-- players' grapple ropes (from their relayed GrapplePoint attribute).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local VFX = require(script.Parent.VFX)

local WorldFX = {}

local shards: { [BasePart]: CFrame } = {}

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
	Players.PlayerRemoving:Connect(clearRope)

	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for part, base in shards do
			local bob = math.sin(t * 2 + base.X * 0.1) * 0.4
			part.CFrame = base * CFrame.new(0, bob, 0) * CFrame.Angles(0, t * 2, 0)
		end
		for _, player in Players:GetPlayers() do
			if player ~= Players.LocalPlayer then
				updateRope(player)
			end
		end
	end)
end

return WorldFX

-- Client-side world visuals: spinning shards with a pickup burst, and other
-- players' grapple ropes (relayed through the server).

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)

local WorldFX = {}

local shards: { [BasePart]: CFrame } = {}

local function burst(position: Vector3, color: Color3)
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Material = Enum.Material.Neon
	ball.Color = color
	ball.Size = Vector3.one
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = false
	ball.Position = position
	ball.Parent = workspace.CurrentCamera
	TweenService:Create(ball, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * 9,
		Transparency = 1,
	}):Play()
	Debris:AddItem(ball, 0.4)
end

local function addShard(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	shards[part] = part.CFrame
	part:GetAttributeChangedSignal("Collected"):Connect(function()
		if part:GetAttribute("Collected") then
			burst(part.Position, part.Color)
		end
	end)
end

-- Other players' ropes ---------------------------------------------------------

local ropes: { [Player]: { Beam: Beam, Anchor: Attachment, Hand: Attachment } } = {}

local function clearRope(player: Player)
	local rope = ropes[player]
	if rope then
		rope.Beam:Destroy()
		rope.Anchor:Destroy()
		rope.Hand:Destroy()
		ropes[player] = nil
	end
end

local function showRope(player: Player, anchorPart: Instance?, offset: Vector3?)
	clearRope(player)
	if player == Players.LocalPlayer or not anchorPart or not offset or not player.Character then
		return
	end
	local hand = player.Character:FindFirstChild("RightHand") or player.Character:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then
		return
	end
	local handAttachment = Instance.new("Attachment")
	handAttachment.Position = Vector3.new(0, -hand.Size.Y / 2, 0)
	handAttachment.Parent = hand
	local anchor = Instance.new("Attachment")
	anchor.Position = offset
	anchor.Parent = anchorPart
	local beam = Instance.new("Beam")
	beam.Attachment0 = handAttachment
	beam.Attachment1 = anchor
	beam.Color = ColorSequence.new(Config.Grapple.RopeColor)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Width0 = 0.2
	beam.Width1 = 0.12
	beam.FaceCamera = true
	beam.Parent = hand
	ropes[player] = { Beam = beam, Anchor = anchor, Hand = handAttachment }
end

function WorldFX.Start()
	for _, part in CollectionService:GetTagged("Shard") do
		addShard(part)
	end
	CollectionService:GetInstanceAddedSignal("Shard"):Connect(addShard)
	CollectionService:GetInstanceRemovedSignal("Shard"):Connect(function(part)
		shards[part] = nil
	end)

	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for part, base in shards do
			local bob = math.sin(t * 2 + base.X * 0.1) * 0.4
			part.CFrame = base * CFrame.new(0, bob, 0) * CFrame.Angles(0, t * 2, 0)
		end
	end)

	local ropeRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Rope")
	ropeRemote.OnClientEvent:Connect(showRope)
	Players.PlayerRemoving:Connect(clearRope)
end

return WorldFX

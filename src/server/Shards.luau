-- Collectible shards: touch one to bank it, it respawns after a while.
-- Tracked in leaderstats so they show on the player list.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Shards = {}

local function onPlayerAdded(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local count = Instance.new("IntValue")
	count.Name = "Shards"
	count.Parent = leaderstats
	leaderstats.Parent = player
end

local function setup(shard: Instance)
	if not shard:IsA("BasePart") then
		return
	end
	shard.Touched:Connect(function(hit)
		if shard:GetAttribute("Collected") then
			return
		end
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not player or not humanoid or humanoid.Health <= 0 then
			return
		end

		shard:SetAttribute("Collected", true)
		shard.Transparency = 1
		local light = shard:FindFirstChildOfClass("PointLight")
		if light then
			light.Enabled = false
		end
		local stats = player:FindFirstChild("leaderstats")
		local count = stats and stats:FindFirstChild("Shards")
		if count and count:IsA("IntValue") then
			count.Value += 1
		end

		task.delay(Config.World.ShardRespawnTime, function()
			shard.Transparency = 0
			if light then
				light.Enabled = true
			end
			shard:SetAttribute("Collected", false)
		end)
	end)
end

function Shards.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	for _, shard in CollectionService:GetTagged("Shard") do
		setup(shard)
	end
	CollectionService:GetInstanceAddedSignal("Shard"):Connect(setup)
end

return Shards

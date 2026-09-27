-- Collectible shards: touch one to bank it, it respawns after a while.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerData = require(script.Parent.PlayerData)
local Progression = require(script.Parent.Progression)

local Shards = {}

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
		shard:SetAttribute("CollectedBy", player.UserId)
		shard.Transparency = 1
		local light = shard:FindFirstChildOfClass("PointLight")
		if light then
			light.Enabled = false
		end
		PlayerData.AddShards(player, 1)
		Progression.AddXP(player, Config.Progression.XP.Shard)
		Progression.Record(player, "Shard")

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
	for _, shard in CollectionService:GetTagged("Shard") do
		setup(shard)
	end
	CollectionService:GetInstanceAddedSignal("Shard"):Connect(setup)
end

return Shards

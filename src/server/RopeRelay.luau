-- Grapple ropes are drawn locally for speed. This relays "I'm attached to X" to
-- everyone else so they can see your rope too, after a basic sanity check.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local RopeRelay = {}

local MIN_INTERVAL = 0.05
local lastMessage: { [Player]: number } = {}

function RopeRelay.Start(ropeRemote: RemoteEvent)
	ropeRemote.OnServerEvent:Connect(function(player: Player, anchorPart: any, offset: any)
		local now = os.clock()
		if now - (lastMessage[player] or 0) < MIN_INTERVAL then
			return
		end
		lastMessage[player] = now

		if anchorPart == nil then
			ropeRemote:FireAllClients(player, nil, nil)
			return
		end
		if typeof(anchorPart) ~= "Instance" or not anchorPart:IsA("BasePart") or typeof(offset) ~= "Vector3" then
			return
		end
		if not anchorPart:IsDescendantOf(workspace) then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		local anchorWorld = anchorPart.CFrame:PointToWorldSpace(offset)
		if (anchorWorld - root.Position).Magnitude > Config.Grapple.Range + 60 then
			return
		end
		ropeRemote:FireAllClients(player, anchorPart, offset)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastMessage[player] = nil
	end)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterRemoving:Connect(function()
			ropeRemote:FireAllClients(player, nil, nil)
		end)
	end)
end

return RopeRelay

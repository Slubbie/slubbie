-- Where players are: which region they stand in and whether they're at a merchant.
-- Positions come from Config.Regions, the same numbers the world builder uses.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Dicebound.Config)

local RegionService = {}

function RegionService.WorldPosition(region, relative: { number }): Vector3
	local o = region.Origin
	return Vector3.new(o[1] + relative[1], o[2] + relative[2], o[3] + relative[3])
end

local function rootPosition(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return root.Position
end

-- The live region the player's character is standing in, or nil.
function RegionService.RegionAt(player: Player)
	local pos = rootPosition(player)
	if not pos then
		return nil
	end
	for _, region in Config.Regions.List do
		if Config.IsLive(region) and Config.Regions.Contains(region, pos.X, pos.Y, pos.Z) then
			return region
		end
	end
	return nil
end

-- The region whose merchant the player is standing next to, or nil.
function RegionService.MerchantNear(player: Player)
	local pos = rootPosition(player)
	if not pos then
		return nil
	end
	for _, region in Config.Regions.List do
		if Config.IsLive(region) and region.Merchant then
			local merchant = RegionService.WorldPosition(region, region.Merchant.Position)
			if (pos - merchant).Magnitude <= Config.Game.MerchantRange then
				return region
			end
		end
	end
	return nil
end

return RegionService

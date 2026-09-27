-- Forces every player to spawn as an R6 character (keeping their avatar's look),
-- whatever the place's avatar settings say.
--
-- Default animations are removed: R6Animator on each client animates every
-- character procedurally instead.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local CharacterSpawner = {}

local descriptions: { [Player]: HumanoidDescription } = {}

local function getDescription(player: Player): HumanoidDescription
	local cached = descriptions[player]
	if cached then
		return cached
	end
	local ok, description = false, nil
	if player.UserId > 0 then
		ok, description = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(player.UserId)
		end)
	end
	if not ok or not description then
		-- Studio test players (negative ids) get a plain default avatar.
		description = Instance.new("HumanoidDescription")
	end
	descriptions[player] = description
	return description
end

local function findSpawn(): CFrame
	local spawnLocation = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawnLocation then
		return spawnLocation.CFrame + Vector3.new(0, spawnLocation.Size.Y / 2 + 3, 0)
	end
	return CFrame.new(0, 110, 0)
end

local function spawnCharacter(player: Player)
	if not player.Parent then
		return
	end
	-- A character the engine auto-loaded before we took over.
	if player.Character then
		player.Character:Destroy()
	end
	local character = Players:CreateHumanoidModelFromDescription(getDescription(player), Enum.HumanoidRigType.R6)
	character.Name = player.Name

	local animate = character:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayName = player.DisplayName

	local offset = Vector3.new(math.random(-4, 4), 0, math.random(-4, 4))
	character:PivotTo(findSpawn() + offset)
	player.Character = character
	character.Parent = workspace

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	root:SetNetworkOwner(player)

	-- Respawn after dying, or after falling out of the world (which can
	-- destroy the body without a clean death).
	local respawning = false
	local function respawn()
		if respawning then
			return
		end
		respawning = true
		task.wait(Config.RespawnTime)
		if player.Parent and player.Character == character then
			character:Destroy()
			spawnCharacter(player)
		end
	end
	humanoid.Died:Connect(respawn)
	root.AncestryChanged:Connect(function()
		if not root:IsDescendantOf(workspace) then
			task.spawn(respawn)
		end
	end)
end

function CharacterSpawner.Start()
	Players.CharacterAutoLoads = false
	Players.PlayerAdded:Connect(spawnCharacter)
	for _, player in Players:GetPlayers() do
		task.spawn(spawnCharacter, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		descriptions[player] = nil
	end)
end

return CharacterSpawner

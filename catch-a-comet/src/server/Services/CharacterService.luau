-- Characters: spawning once the world exists, respawning, walk speed, the
-- Comet Tether device every player carries (it changes with their upgrades
-- and everyone can see it), and fall recovery — dropping off an island puts
-- you back on safe ground nearby. Falling never costs anything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EquipmentRig = require(Shared.EquipmentRig)
local GameConfig = require(Shared.GameConfig)
local WorldLayout = require(Shared.WorldLayout)

local CharacterService = { Name = "CharacterService" }

local services: { [string]: any } = {}
local lastSafe: { [Player]: CFrame } = {}

local function handPart(character: Model): BasePart?
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	return if hand and hand:IsA("BasePart") then hand else nil
end

function CharacterService.RefreshEquipment(player: Player)
	local character = player.Character
	local profile = services.PlayerDataService.GetProfile(player)
	if not character or not profile then
		return
	end
	local hand = handPart(character)
	if not hand then
		return
	end
	local old = character:FindFirstChild("CometTether")
	if old then
		old:Destroy()
	end
	local device = EquipmentRig.BuildDevice(profile.Equipment.ScannerLevel, profile.Equipment.TetherLevel)
	local grip = device.PrimaryPart :: BasePart
	-- Held in the right hand, pointing forward.
	local offset = if hand.Name == "RightHand" then CFrame.new(0, -0.2, -0.25) else CFrame.new(0, -1, -0.35)
	local base = hand.CFrame * offset
	for _, part in device:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.Massless = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	-- Move the whole device to the hand (parts are welded to the grip).
	local delta = base * grip.CFrame:Inverse()
	for _, part in device:GetDescendants() do
		if part:IsA("BasePart") then
			part.CFrame = delta * part.CFrame
		end
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = grip
	weld.Parent = grip
	device.Parent = character
end

local function safePointFor(player: Player, position: Vector3): CFrame
	local area = WorldLayout.GetArea(position)
	if area.Kind == "Sanctuary" and area.PlotIndex then
		return WorldLayout.PlotArrival(area.PlotIndex)
	elseif area.Kind == "Biome" then
		local biome = WorldLayout.Biomes[area.Id]
		if biome then
			return biome.Arrival
		end
	elseif area.Kind == "Wilds" and position.X > WorldLayout.Hub.Radius + 40 and math.abs(position.Z) < 60 then
		return WorldLayout.Biomes.DawnCommons.Arrival
	end
	return lastSafe[player] or WorldLayout.Hub.Spawn
end

function CharacterService.CheckFalls()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not root or not root:IsA("BasePart") then
			continue
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if
			humanoid
			and humanoid.FloorMaterial ~= Enum.Material.Air
			and root.Position.Y > GameConfig.Character.VoidY + 40
		then
			lastSafe[player] = root.CFrame
		end
		if root.Position.Y < GameConfig.Character.VoidY then
			local target = safePointFor(player, root.Position)
			root.AssemblyLinearVelocity = Vector3.zero
			character:PivotTo(target + Vector3.new(0, 2, 0))
			services.ReplicationService.Notify(player, "Recovered", {})
		end
	end
end

-- LoadCharacterAsync is the current API; fall back for older engines.
local function loadCharacter(player: Player)
	local ok = pcall(function()
		player:LoadCharacterAsync()
	end)
	if not ok and player.Parent then
		(player :: any):LoadCharacter()
	end
end

local function onCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.WalkSpeed = GameConfig.Character.WalkSpeed
	character:SetAttribute("CaptureTarget", nil)
	task.defer(CharacterService.RefreshEquipment, player)
	humanoid.Died:Connect(function()
		task.delay(GameConfig.Character.RespawnDelay, function()
			if player.Parent and player.Character == character then
				loadCharacter(player)
			end
		end)
	end)
end

local function spawnPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	-- Wait briefly for the profile so the device shows the right levels, but never block spawning.
	services.PlayerDataService.WaitForProfile(player, 8)
	if player.Parent and not player.Character then
		loadCharacter(player)
	end
end

function CharacterService.Init(registry: { [string]: any })
	services = registry
	Players.CharacterAutoLoads = false
end

function CharacterService.Start()
	Players.PlayerAdded:Connect(spawnPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(spawnPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastSafe[player] = nil
	end)
	services.UpgradeService.Upgraded:Connect(function(player, trackId)
		if trackId == "Scanner" or trackId == "Tether" then
			CharacterService.RefreshEquipment(player)
		end
	end)
	services.PlayerDataService.ProfileLoaded:Connect(function(player)
		task.defer(CharacterService.RefreshEquipment, player)
	end)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.25 then
			accumulator = 0
			CharacterService.CheckFalls()
		end
	end)
end

return CharacterService

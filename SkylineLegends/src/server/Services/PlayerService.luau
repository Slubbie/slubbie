-- Characters: R6 spawning (keeping each player's avatar look), collision
-- groups, nametags with rank, title and crew tag, and spawn locations.
--
-- Falls never kill: clients respawn themselves at their checkpoint or last
-- safe rooftop. A character only dies if the player resets, and then it
-- respawns at the plaza of the district they were in.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cosmetics = require(ReplicatedStorage.Shared.Config.Cosmetics)
local Districts = require(ReplicatedStorage.Shared.Config.Districts)
local Tags = require(ReplicatedStorage.Shared.Tags)

local DataService = require(script.Parent.Parent.Data.DataService)

local PlayerService = {}

-- District spawn CFrames, registered by the world builder.
PlayerService.Spawns = {} :: { [string]: CFrame }
-- Called with each new character (set by other services).
PlayerService.CharacterAdded = {} :: { (Player, Model) -> () }

local descriptions: { [Player]: HumanoidDescription } = {}

local function getDescription(player: Player): HumanoidDescription
	local cached = descriptions[player]
	if cached then
		return cached:Clone()
	end
	local description: HumanoidDescription? = nil
	if player.UserId > 0 then
		local ok, result = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(player.UserId)
		end)
		if ok then
			description = result
		end
	end
	if not description then
		-- Studio test players get a tidy default runner.
		local fallback = Instance.new("HumanoidDescription")
		fallback.HeadColor = Color3.fromRGB(234, 184, 146)
		fallback.TorsoColor = Color3.fromRGB(70, 110, 140)
		fallback.LeftArmColor = Color3.fromRGB(234, 184, 146)
		fallback.RightArmColor = Color3.fromRGB(234, 184, 146)
		fallback.LeftLegColor = Color3.fromRGB(40, 44, 52)
		fallback.RightLegColor = Color3.fromRGB(40, 44, 52)
		description = fallback
	end
	descriptions[player] = description :: HumanoidDescription
	return (description :: HumanoidDescription):Clone()
end

function PlayerService.SpawnFor(player: Player): CFrame
	local profile = DataService.Get(player)
	local last = if profile then profile.Districts.Last else "Hub"
	if profile and last == "Hub" and not profile.Flags.Graduated then
		-- New runners start in the Training Yard.
		return PlayerService.Spawns.Training or PlayerService.Spawns.Hub or CFrame.new(Districts.ById.Hub.Origin)
	end
	return PlayerService.Spawns[last]
		or PlayerService.Spawns.Hub
		or CFrame.new(Districts.ById.Hub.Origin + Vector3.new(0, 5, 0))
end

-- Nametag ------------------------------------------------------------------------

local function buildNametag(player: Player, character: Model)
	local head = character:FindFirstChild("Head")
	if not head then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "SkylineNametag"
	gui.Size = UDim2.fromOffset(220, 58)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.Adornee = head
	gui.ResetOnSpawn = false

	local name = Instance.new("TextLabel")
	name.Name = "PlayerName"
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 24)
	name.Font = Enum.Font.GothamBold
	name.TextSize = 18
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextStrokeTransparency = 0.5
	name.Parent = gui

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(0, 24)
	title.Size = UDim2.new(1, 0, 0, 18)
	title.Font = Enum.Font.GothamMedium
	title.TextSize = 14
	title.TextStrokeTransparency = 0.6
	title.Parent = gui

	local function refresh()
		local crew = player:GetAttribute("CrewTag")
		local prefix = if type(crew) == "string" and crew ~= "" then "[" .. crew .. "] " else ""
		name.Text = prefix .. player.DisplayName
		local level = player:GetAttribute("Level") or 1
		local equippedTitle = player:GetAttribute("Title")
		local rank = player:GetAttribute("Rank") or "Newcomer"
		local label = if type(equippedTitle) == "string" and equippedTitle ~= "" then equippedTitle else rank
		title.Text = ("Lv %d  ·  %s"):format(level, label)
		local color = player:GetAttribute("RankColor")
		title.TextColor3 = if typeof(color) == "Color3" then color else Color3.fromRGB(200, 205, 215)
	end
	refresh()
	for _, attribute in { "Level", "Rank", "Title", "CrewTag", "RankColor" } do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	gui.Parent = head
end

-- Spawning ----------------------------------------------------------------------------

local function setCollisionGroups(character: Model)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = Tags.Groups.Players
		end
	end
	character.DescendantAdded:Connect(function(part)
		if part:IsA("BasePart") and part.CollisionGroup == Tags.Groups.World then
			part.CollisionGroup = Tags.Groups.Players
		end
	end)
end

local function spawnCharacter(player: Player)
	if not player.Parent then
		return
	end
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
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.UseJumpPower = true

	setCollisionGroups(character)
	buildNametag(player, character)

	local spawnCFrame = PlayerService.SpawnFor(player)
	local offset = Vector3.new(math.random(-3, 3), 3.5, math.random(-3, 3))
	character:PivotTo(spawnCFrame + offset)
	player.Character = character
	character.Parent = workspace

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	root:SetNetworkOwner(player)

	for _, callback in PlayerService.CharacterAdded do
		task.spawn(callback, player, character)
	end

	local respawning = false
	local function respawn()
		if respawning then
			return
		end
		respawning = true
		task.wait(2)
		if player.Parent and player.Character == character then
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

function PlayerService.Respawn(player: Player)
	task.spawn(spawnCharacter, player)
end

local function onPlayerAdded(player: Player)
	-- Wait for the profile so we spawn in the right district.
	DataService.Await(player, 20)
	if player.Parent then
		spawnCharacter(player)
	end
end

function PlayerService.Start()
	Players.CharacterAutoLoads = false
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		descriptions[player] = nil
	end)
	-- Keep the equipped title attribute in sync for nametags.
	DataService.Loaded:Connect(function(player, profile)
		local item = Cosmetics.ById[profile.Equipped.Title or ""]
		player:SetAttribute("Title", if item and item.Text and item.Text ~= "" then item.Text else nil)
	end)
end

return PlayerService

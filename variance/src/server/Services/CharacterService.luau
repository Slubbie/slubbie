-- Player characters: R6 bodies (the avatar's look is kept), lobby spawning,
-- nameplates, and seating subjects at an evaluation table.
--
-- At the table the HumanoidRootPart is anchored at the seat and movement is
-- disabled; the client's AnimationController poses every seated rig (players
-- and surrogates alike) each frame, overriding the default Animate tracks.
--
-- Going to a table is hidden behind a curtain: the player's screen fades out
-- first, then the body is moved, so nobody watches their character pop across
-- the map, stand inside a chair or wait for the room to stream in.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(ReplicatedStorage.Variance.Visual.Build)
local Levels = require(ReplicatedStorage.Variance.Data.Levels)

local CharacterService = {}

local descriptions: { [Player]: HumanoidDescription } = {}
local seated: { [Player]: { Arena: Model, Seat: number, Cosmetics: { Instance }, Token: number } } = {}
local seatTokens: { [Player]: number } = {}

local CURTAIN_LEAD = 0.3 -- seconds the screen has to fade out before the move

function CharacterService:Init(services)
	self.Services = services
end

local function description(player: Player): HumanoidDescription
	local cached = descriptions[player]
	if cached then
		return cached
	end
	local ok, desc = false, nil
	if player.UserId > 0 then
		ok, desc = pcall(Players.GetHumanoidDescriptionFromUserId, Players, player.UserId)
	end
	if not ok or desc == nil then
		desc = Instance.new("HumanoidDescription")
	end
	descriptions[player] = desc
	return desc
end

local function lobbySpawn(): CFrame
	local spawn = workspace:FindFirstChild("IntakeSpawn", true)
	if spawn and spawn:IsA("BasePart") then
		return spawn.CFrame + Vector3.new(math.random(-5, 5), 3.5, math.random(-3, 3))
	end
	return CFrame.new(0, 5, 40)
end

-- Builds the lobby nameplate: name, clearance title and level, ranked division.
function CharacterService:refreshNameplate(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if head == nil then
		return
	end
	local existing = head:FindFirstChild("Nameplate")
	if existing then
		existing:Destroy()
	end
	local profile = self.Services.DataService:get(player)
	local level = profile and profile.Data.Level or 1
	local look = self.Services.CosmeticService:look(player)
	local plate = look.Nameplate and look.Nameplate.Data or {}
	local titleItem = look.Title and look.Title.Data or {}
	local title = titleItem.Text or Levels.titleFor(level)
	if look.Title and look.Title.Id == "title_level" then
		title = Levels.titleFor(level)
	end
	local ranked = self.Services.RankedService:info(player)

	local gui = Instance.new("BillboardGui")
	gui.Name = "Nameplate"
	gui.Size = UDim2.fromOffset(220, 58)
	gui.StudsOffset = Vector3.new(0, 2.4, 0)
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ResetOnSpawn = false
	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0.55, 0)
	name.Font = Enum.Font.GothamBold
	name.TextScaled = true
	name.Text = player.DisplayName
	name.TextColor3 = Build.rgb(plate.Color, Color3.fromRGB(230, 226, 214))
	name.TextStrokeTransparency = 0.6
	name.Parent = gui
	if plate.Style == "Glitch" then
		name:SetAttribute("Fx", "Glitch")
	elseif plate.Style == "Glow" then
		name.TextStrokeColor3 = Build.rgb(plate.Color, Color3.new(1, 1, 1))
		name.TextStrokeTransparency = 0.2
	end
	local sub = Instance.new("TextLabel")
	sub.Name = "Title"
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromScale(0, 0.55)
	sub.Size = UDim2.new(1, 0, 0.45, 0)
	sub.Font = Enum.Font.Code
	sub.TextScaled = true
	local division = ""
	if ranked and ranked.Placed then
		division = "  //  " .. ranked.Division.Label
	end
	sub.Text = string.format("LV %d  %s%s", level, title, division)
	sub.TextColor3 = Color3.fromRGB(232, 163, 61)
	sub.TextStrokeTransparency = 0.7
	sub.Parent = gui
	gui.Parent = head
	character:SetAttribute("Level", level)
end

local function disableAnimateSounds(character: Model)
	-- Keep the default walk animations in the lobby; remove footstep spam at the table.
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.NameDisplayDistance = 0
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
	end
end

function CharacterService:spawn(player: Player, at: CFrame?)
	if not player.Parent then
		return nil
	end
	if player.Character then
		player.Character:Destroy()
	end
	local ok, character =
		pcall(Players.CreateHumanoidModelFromDescription, Players, description(player), Enum.HumanoidRigType.R6)
	if not ok or character == nil then
		warn("[VARIANCE/Character] could not build character: " .. tostring(character))
		player:LoadCharacter()
		return player.Character
	end
	character.Name = player.Name
	disableAnimateSounds(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayName = player.DisplayName
		humanoid.WalkSpeed = 14
		humanoid.JumpPower = 0
		humanoid.UseJumpPower = true
	end
	character:PivotTo(at or lobbySpawn())
	player.Character = character
	character.Parent = workspace
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		pcall(root.SetNetworkOwner, root, player)
	end
	if humanoid then
		humanoid.Died:Connect(function()
			task.wait(1.5)
			if player.Parent and player.Character == character and not seated[player] then
				self:spawn(player)
			end
		end)
	end
	task.defer(function()
		self:refreshNameplate(player)
	end)
	return character
end

local function characterParts(player: Player)
	local character = player.Character
	if character == nil then
		return nil
	end
	return character,
		character:FindFirstChild("HumanoidRootPart") :: BasePart?,
		character:FindFirstChildOfClass("Humanoid")
end

-- Adds match-only cosmetics (gloves, headwear) to a seated character.
local function dressForMatch(self, player: Player, character: Model): { Instance }
	local added = {}
	local look = self.Services.CosmeticService:look(player)
	local gloves = look.Gloves and look.Gloves.Data
	if gloves and not gloves.None then
		for _, armName in { "Left Arm", "Right Arm" } do
			local arm = character:FindFirstChild(armName)
			if arm and arm:IsA("BasePart") then
				local glove = Build.part({
					Name = "VarianceGlove",
					Size = Vector3.new(1.06, 0.62, 1.06),
					CFrame = arm.CFrame * CFrame.new(0, -0.72, 0),
					Color = Build.rgb(gloves.Color),
					Material = gloves.Material,
					Anchored = false,
					Parent = character,
				})
				glove.Massless = true
				Build.weld(glove, arm)
				table.insert(added, glove)
			end
		end
	end
	local acc = look.Accessory and look.Accessory.Data
	local head = character:FindFirstChild("Head")
	if acc and acc.Kind ~= "None" and head and head:IsA("BasePart") then
		local color = Build.rgb(acc.Color)
		local function piece(size: Vector3, offset: CFrame, mat: string, shape: Enum.PartType?)
			local p = Build.part({
				Name = "VarianceHeadwear",
				Size = size,
				CFrame = head.CFrame * offset,
				Color = color,
				Material = mat,
				Shape = shape,
				Anchored = false,
				Parent = character,
			})
			p.Massless = true
			Build.weld(p, head)
			table.insert(added, p)
			return p
		end
		if acc.Kind == "Headset" then
			piece(Vector3.new(1.5, 0.15, 0.25), CFrame.new(0, 0.62, 0), "SmoothPlastic")
			piece(Vector3.new(0.2, 0.45, 0.45), CFrame.new(0.72, 0.05, 0), "SmoothPlastic")
			piece(Vector3.new(0.2, 0.45, 0.45), CFrame.new(-0.72, 0.05, 0), "SmoothPlastic")
			piece(Vector3.new(0.08, 0.08, 0.5), CFrame.new(0.62, -0.25, -0.35), "SmoothPlastic")
		elseif acc.Kind == "Goggles" or acc.Kind == "Visor" then
			local lens = piece(
				Vector3.new(1.25, 0.32, 0.2),
				CFrame.new(0, 0.18, -0.55),
				acc.Kind == "Goggles" and "Glass" or "SmoothPlastic"
			)
			lens.Transparency = acc.Kind == "Goggles" and 0.35 or 0.15
			piece(Vector3.new(1.3, 0.12, 1.15), CFrame.new(0, 0.2, 0), "Fabric")
		elseif acc.Kind == "Fedora" then
			piece(
				Vector3.new(0.12, 2.0, 2.0),
				CFrame.new(0, 0.55, 0) * CFrame.Angles(0, 0, math.pi / 2),
				"Fabric",
				Enum.PartType.Cylinder
			)
			piece(
				Vector3.new(0.7, 1.2, 1.2),
				CFrame.new(0, 0.9, 0) * CFrame.Angles(0, 0, math.pi / 2),
				"Fabric",
				Enum.PartType.Cylinder
			)
		elseif acc.Kind == "Monocle" then
			piece(
				Vector3.new(0.06, 0.34, 0.34),
				CFrame.new(0.25, 0.15, -0.58) * CFrame.Angles(0, math.pi / 2, 0),
				"Foil",
				Enum.PartType.Cylinder
			)
		elseif acc.Kind == "Mask" then
			piece(Vector3.new(1.15, 0.9, 0.2), CFrame.new(0, 0, -0.55), "SmoothPlastic")
		elseif acc.Kind == "Halo" then
			local ring = piece(
				Vector3.new(0.08, 1.7, 1.7),
				CFrame.new(0, 1.2, 0) * CFrame.Angles(0, 0, math.pi / 2),
				"Neon",
				Enum.PartType.Cylinder
			)
			ring.Transparency = 0.2
		elseif acc.Kind == "Earpiece" then
			piece(Vector3.new(0.18, 0.3, 0.18), CFrame.new(-0.6, 0, 0), "SmoothPlastic")
			piece(Vector3.new(0.05, 0.05, 0.4), CFrame.new(-0.6, -0.3, -0.2), "SmoothPlastic")
		end
	end
	return added
end

-- Moves the (frozen) body to its seat and dresses it for the table.
local function placeAtSeat(self, player: Player, arena: Model, seat: number, rootCFrame: CFrame, token: number)
	local character, root, humanoid = characterParts(player)
	if character == nil or root == nil then
		character = self:spawn(player, rootCFrame)
		if character == nil then
			return
		end
		root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		humanoid = character:FindFirstChildOfClass("Humanoid")
	end
	if root == nil or seatTokens[player] ~= token then
		return
	end
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.AutoRotate = false
		humanoid.Sit = false
	end
	root.Anchored = true
	character:PivotTo(rootCFrame)
	character:SetAttribute("Seated", true)
	character:SetAttribute("Seat", seat)
	character:SetAttribute("Arena", arena.Name)
	local plate = character:FindFirstChild("Head") and character.Head:FindFirstChild("Nameplate")
	if plate then
		plate.Enabled = false
	end
	local info = seated[player]
	if info and info.Token == token then
		for _, item in info.Cosmetics do
			item:Destroy()
		end
		info.Cosmetics = dressForMatch(self, player, character)
	end
end

-- Seats a player at a table. `rootCFrame` is the world CFrame for the root.
-- The player is frozen at once and moved after their screen has faded out
-- (immediately if they are already sitting at this seat, e.g. a rematch).
function CharacterService:seat(player: Player, arena: Model, seat: number, rootCFrame: CFrame)
	local token = (seatTokens[player] or 0) + 1
	seatTokens[player] = token
	local previous = seated[player]
	local same = previous ~= nil and previous.Arena == arena and previous.Seat == seat
	if previous then
		for _, item in previous.Cosmetics do
			item:Destroy()
		end
	end
	seated[player] = { Arena = arena, Seat = seat, Cosmetics = {}, Token = token }
	local _, root, humanoid = characterParts(player)
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid:Move(Vector3.zero)
	end
	if root and not same then
		root.AssemblyLinearVelocity = Vector3.zero
	end
	-- Stream the room around the seat while the screen fades.
	task.spawn(function()
		pcall(player.RequestStreamAroundAsync, player, rootCFrame.Position, 5)
	end)
	if same then
		placeAtSeat(self, player, arena, seat, rootCFrame, token)
		return true
	end
	self.Services.NetworkService:push(player, "Curtain", { On = true })
	task.delay(CURTAIN_LEAD, function()
		if player.Parent and seatTokens[player] == token and seated[player] and seated[player].Token == token then
			placeAtSeat(self, player, arena, seat, rootCFrame, token)
		end
	end)
	return true
end

-- Returns a player from a table to the lobby (behind the curtain).
function CharacterService:unseat(player: Player)
	local info = seated[player]
	seated[player] = nil
	local token = (seatTokens[player] or 0) + 1
	seatTokens[player] = token
	local spawnAt = lobbySpawn()
	if info == nil then
		-- Not at a table as far as we know; only fix up a body left frozen.
		local character, root = characterParts(player)
		if character == nil or (root and root.Anchored) then
			self:_release(player, nil, spawnAt)
		end
		return
	end
	self.Services.NetworkService:push(player, "Curtain", { On = true })
	-- Stream the lobby in while the screen fades.
	task.spawn(function()
		pcall(player.RequestStreamAroundAsync, player, spawnAt.Position, 5)
	end)
	task.delay(CURTAIN_LEAD, function()
		-- Seated somewhere else in the meantime (queue popped): stay there.
		if player.Parent and seatTokens[player] == token then
			self:_release(player, info, spawnAt)
		end
	end)
end

function CharacterService:_release(player: Player, info, spawnAt: CFrame)
	if info then
		for _, item in info.Cosmetics do
			if item.Parent then
				item:Destroy()
			end
		end
	end
	local character, root, humanoid = characterParts(player)
	if character == nil or root == nil then
		if player.Parent then
			self:spawn(player)
		end
		return
	end
	character:SetAttribute("Seated", nil)
	character:SetAttribute("Seat", nil)
	character:SetAttribute("Arena", nil)
	root.Anchored = false
	if humanoid then
		humanoid.WalkSpeed = 14
		humanoid.AutoRotate = true
	end
	character:PivotTo(spawnAt)
	-- Anchoring handed the body to the server; give the player their physics back.
	pcall(root.SetNetworkOwner, root, player)
	local plate = character:FindFirstChild("Head") and character.Head:FindFirstChild("Nameplate")
	if plate then
		plate.Enabled = true
	end
end

function CharacterService:isSeated(player: Player): boolean
	return seated[player] ~= nil
end

function CharacterService:Start()
	Players.CharacterAutoLoads = false
	local function added(player: Player)
		self:spawn(player)
	end
	Players.PlayerAdded:Connect(added)
	for _, player in Players:GetPlayers() do
		task.spawn(added, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		descriptions[player] = nil
		seated[player] = nil
		seatTokens[player] = nil
	end)
	self.Services.DataService.Loaded:Connect(function(player)
		self:refreshNameplate(player)
	end)
end

return CharacterService

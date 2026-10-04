-- Hazards, falls and instant recovery.
--
-- Touching a live hazard (lasers, sweepers' red cousins, rising water) or
-- falling out of the world sends you back. In a course that's your last
-- checkpoint (handled by whoever registered a handler, e.g. the course or
-- lesson client); while exploring it's the most recent safe ground you stood
-- on, so a missed jump costs a second, never a long walk back.
--
-- The hurtbox follows posture: sliding really does pass under a high laser.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local MathUtil = require(ReplicatedStorage.Shared.Util.MathUtil)
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Tags = require(ReplicatedStorage.Shared.Tags)

local Controller = require(script.Parent.Parent.Movement.Controller)
local Mechanisms = require(script.Parent.Mechanisms)

local player = Players.LocalPlayer

local Hazards = {}

-- (reason, destination) after every respawn.
Hazards.Respawned = Signal.new()
-- (reason) just before a respawn, for sounds and effects.
Hazards.Hit = Signal.new()
-- Extra kill height set by courses/lessons (below it counts as a fall).
Hazards.KillY = nil :: number?

-- Handlers get first say over where a respawn goes. Return a CFrame to use it,
-- or nil to pass. The most recently pushed handler is asked first.
type Handler = (reason: string) -> CFrame?
local handlers: { { Id: string, Fn: Handler } } = {}

local SAFE_INTERVAL = 0.25
local SAFE_SPACING = 3
local SAFE_KEEP = 12

local safeSpots: { { Position: Vector3, Look: Vector3, Time: number } } = {}
local lastSafeCheck = 0
local busyUntil = 0
local hazardCache: { BasePart } = {}
local hazardCacheTime = 0
local worldFloor = -math.huge

-- Fade -------------------------------------------------------------------------------------------

local fadeGui = Instance.new("ScreenGui")
fadeGui.Name = "SkylineFade"
fadeGui.DisplayOrder = 50
fadeGui.IgnoreGuiInset = true
fadeGui.ResetOnSpawn = false
local fade = Instance.new("Frame")
fade.Size = UDim2.fromScale(1, 1)
fade.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
fade.BackgroundTransparency = 1
fade.BorderSizePixel = 0
fade.Parent = fadeGui

local function fadeTo(transparency: number, seconds: number)
	TweenService:Create(fade, TweenInfo.new(seconds, Enum.EasingStyle.Quad), { BackgroundTransparency = transparency })
		:Play()
end

-- Safe ground ------------------------------------------------------------------------------------

local UNSAFE_TAGS =
	{ Tags.Mover, Tags.Timed, Tags.Collapse, Tags.Hazard, Tags.BouncePad, Tags.Conveyor, Tags.Balance, Tags.SwitchGate }

local function isSafeFloor(part: BasePart): boolean
	if not part.Anchored or not part.CanCollide then
		return false
	end
	for _, tag in UNSAFE_TAGS do
		if CollectionService:HasTag(part, tag) then
			return false
		end
	end
	-- Ledge-thin surfaces make poor respawn spots.
	local size = part.Size
	return math.min(size.X, size.Z) >= 3 or (part:IsA("Part") and part.Shape == Enum.PartType.Cylinder)
end

local function recordSafeSpot()
	local info = Controller.Info
	local root = info.Root
	local floor = info.Floor
	if not root or not floor or not info.Grounded then
		return
	end
	if info.State ~= "Ground" and info.State ~= "Crouch" then
		return
	end
	if not isSafeFloor(floor) then
		return
	end
	local position = root.Position
	local last = safeSpots[#safeSpots]
	if last and (last.Position - position).Magnitude < SAFE_SPACING then
		last.Time = os.clock()
		return
	end
	table.insert(
		safeSpots,
		{ Position = position, Look = MathUtil.FlatUnit(root.CFrame.LookVector), Time = os.clock() }
	)
	if #safeSpots > SAFE_KEEP then
		table.remove(safeSpots, 1)
	end
end

-- The latest safe spot that isn't the edge you just fell from.
local function bestSafeSpot(): CFrame?
	local now = os.clock()
	for i = #safeSpots, 1, -1 do
		local spot = safeSpots[i]
		-- Spots from the last instant before a fall are often right on the lip.
		if now - spot.Time > 0.4 or i == 1 then
			return CFrame.lookAt(
				spot.Position + Vector3.new(0, 0.5, 0),
				spot.Position + Vector3.new(0, 0.5, 0) + spot.Look
			)
		end
	end
	return nil
end

-- Respawning --------------------------------------------------------------------------------------

function Hazards.PushHandler(id: string, fn: Handler)
	Hazards.PopHandler(id)
	table.insert(handlers, { Id = id, Fn = fn })
end

function Hazards.PopHandler(id: string)
	for i = #handlers, 1, -1 do
		if handlers[i].Id == id then
			table.remove(handlers, i)
		end
	end
end

function Hazards.ClearSafeSpots()
	table.clear(safeSpots)
end

-- Send the runner back. `reason`: "Fall" | "Hazard" | "Water" | "Retry".
function Hazards.Respawn(reason: string)
	local now = os.clock()
	if now < busyUntil then
		return
	end
	local root = Controller.Info.Root
	local humanoid = Controller.Info.Humanoid
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	busyUntil = now + 0.5
	Hazards.Hit:Fire(reason)

	local destination: CFrame? = nil
	local handled = false
	for i = #handlers, 1, -1 do
		local result = handlers[i].Fn(reason)
		if result then
			destination = result
			handled = true
			break
		end
	end
	if not destination then
		destination = bestSafeSpot()
	end
	if not destination then
		-- Nothing safe recorded: the district's arrival point via the server.
		Net.Send("Move.Fall", reason, nil)
		local ok, allowed, target = pcall(Net.Invoke, "Travel.Spawn")
		if ok and allowed and typeof(target) == "CFrame" then
			destination = target
		end
	elseif not handled then
		Net.Send("Move.Fall", reason, destination.Position)
	end
	if not destination then
		busyUntil = 0
		return
	end

	local quick = reason == "Retry"
	fade.BackgroundTransparency = if quick then 0.4 else 0.15
	Controller.Teleport(destination)
	fadeTo(1, if quick then 0.18 else 0.3)
	Hazards.Respawned:Fire(reason, destination)
end

-- Hazard contact -----------------------------------------------------------------------------------

local function refreshHazards(position: Vector3)
	hazardCacheTime = os.clock()
	table.clear(hazardCache)
	for _, instance in CollectionService:GetTagged(Tags.Hazard) do
		if instance:IsA("BasePart") and instance.Parent then
			local reach = instance.Size.Magnitude / 2 + 120
			if (instance.Position - position).Magnitude < reach then
				table.insert(hazardCache, instance)
			end
		end
	end
	-- Lowest kill volume: anything far below it is out of the world.
	local lowest = math.huge
	for _, instance in CollectionService:GetTagged(Tags.KillZone) do
		if instance:IsA("BasePart") then
			lowest = math.min(lowest, instance.Position.Y - instance.Size.Y / 2)
		end
	end
	worldFloor = if lowest < math.huge then lowest - 40 else -1500
end

-- Points along the body that count for hits, by posture.
local function hurtPoints(root: BasePart): { Vector3 }
	local feet = root.Position - Vector3.new(0, 3, 0)
	local low = Controller.Info.Posture == "Low"
	local top = if low then 2.2 else 4.8
	local points = {}
	local y = 0.4
	while y <= top do
		table.insert(points, feet + Vector3.new(0, y, 0))
		y += 0.8
	end
	return points
end

local function checkHazards()
	local info = Controller.Info
	local root = info.Root
	if not root or os.clock() < busyUntil then
		return
	end
	if os.clock() - hazardCacheTime > 1 then
		refreshHazards(root.Position)
	end
	local points: { Vector3 }? = nil
	for _, part in hazardCache do
		if not part.Parent or not Mechanisms.IsLive(part) then
			continue
		end
		if (part.Position - root.Position).Magnitude > part.Size.Magnitude / 2 + 8 then
			continue
		end
		points = points or hurtPoints(root)
		local isWater = CollectionService:HasTag(part, Tags.Water)
		for _, point in points :: { Vector3 } do
			if MathUtil.InBox(part.CFrame, part.Size, point, if isWater then 0 else 0.25) then
				Hazards.Respawn(if isWater then "Water" else "Hazard")
				return
			end
		end
	end
end

function Hazards.Start()
	fadeGui.Parent = player:WaitForChild("PlayerGui")
	Controller.KillCheck = function(position: Vector3): boolean
		local killY = Hazards.KillY
		return position.Y < worldFloor or (killY ~= nil and position.Y < killY)
	end
	Controller.Fell:Connect(function(reason: string)
		Hazards.Respawn(reason)
	end)
	Controller.Teleported:Connect(function()
		-- A teleport that wasn't a respawn (travel, course start): old spots are stale.
		if os.clock() >= busyUntil then
			Hazards.ClearSafeSpots()
		end
	end)
	player.CharacterAdded:Connect(function()
		Hazards.ClearSafeSpots()
	end)
	RunService.Heartbeat:Connect(function()
		checkHazards()
		if os.clock() - lastSafeCheck >= SAFE_INTERVAL then
			lastSafeCheck = os.clock()
			recordSafeSpot()
		end
	end)
end

return Hazards

-- Client-side movement: the heart of SKYBOUND.
--
-- Owns the player's horizontal momentum and runs a small state machine:
--   Ground ⇄ Air ⇄ Grapple
--   Air → WallRun → Air (wall jump)
--   Ground ⇄ Slide → Air (slide jump)
--
-- The local character is simulated on this client (network ownership), so
-- velocities set here replicate to everyone automatically.

local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local MathUtil = require(ReplicatedStorage.Shared.MathUtil)
local Grapple = require(script.Parent.Grapple)

local M = Config.Movement
local W = Config.WallRun
local S = Config.Slide
local D = Config.Dash

local Flat = MathUtil.Flat
local RotateToward = MathUtil.RotateToward

local player = Players.LocalPlayer

type State = "Ground" | "Air" | "Grapple" | "WallRun" | "Slide"

local Movement = {}

-- Read-only snapshot for camera, animation and HUD effects.
Movement.Info = {
	Character = nil :: Model?,
	Humanoid = nil :: Humanoid?,
	Root = nil :: BasePart?,
	State = "Ground" :: State,
	Velocity = Vector3.zero,
	Speed = 0, -- horizontal speed
	WallNormal = nil :: Vector3?,
	DashCharges = D.Charges,
}

Movement.Landed = Instance.new("BindableEvent") -- (impactSpeed: number)
Movement.Dashed = Instance.new("BindableEvent")
Movement.WallJumped = Instance.new("BindableEvent")
Movement.Launched = Instance.new("BindableEvent")

local humanoid: Humanoid? = nil
local root: BasePart? = nil
local state: State = "Ground"

local airSpeed = 0
local groundSpeed = M.WalkSpeed
local dashCharges = D.Charges
local lastDash = -math.huge
local lastLaunch = -math.huge

local jumpPressedAt = -math.huge
local lastTouchJump = -math.huge

local slideHeld = false
local slideDir = Vector3.zAxis
local slideSpeed = 0
local slideAirTime = 0
local lastSlideBoost = -math.huge

local wallNormal = Vector3.xAxis
local wallTangent = Vector3.zAxis
local wallSpeed = 0
local wallVy = 0
local wallRunStart = 0
local lastWallNormal: Vector3? = nil
local lastWallTangent = Vector3.zAxis
local lastWallRunEnd = -math.huge
local coyoteUsed = true

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function setState(newState: State)
	state = newState
	Movement.Info.State = newState
	if newState ~= "WallRun" then
		Movement.Info.WallNormal = nil
	end
end

local function refillDash()
	dashCharges = D.Charges
end

local function enterAir()
	local h = humanoid :: Humanoid
	airSpeed = Flat((root :: BasePart).AssemblyLinearVelocity).Magnitude
	h.WalkSpeed = M.WalkSpeed
	setState("Air")
end

-- Wall running ---------------------------------------------------------------

local function endWallRun()
	lastWallNormal = wallNormal
	lastWallTangent = wallTangent
	lastWallRunEnd = os.clock()
	coyoteUsed = false
	airSpeed = wallSpeed
	setState("Air")
end

local function isRunnableWall(hit: RaycastResult?): boolean
	return hit ~= nil and math.abs(hit.Normal.Y) < 0.3 and not hit.Instance:GetAttribute("NoWallRun")
end

local function tryStartWallRun(v: Vector3): boolean
	local flat = Flat(v)
	local speed = flat.Magnitude
	if speed < W.MinSpeed or v.Y < -80 then
		return false
	end
	local dir = flat.Unit
	local right = dir:Cross(Vector3.yAxis)
	for _, side in { right, -right } do
		local hit = workspace:Raycast((root :: BasePart).Position, side * W.CheckDistance, rayParams)
		if isRunnableWall(hit) then
			local normal = Flat((hit :: RaycastResult).Normal).Unit
			local sameWall = lastWallNormal ~= nil
				and os.clock() - lastWallRunEnd < W.SameWallCooldown
				and normal:Dot(lastWallNormal) > 0.9
			if not sameWall then
				wallNormal = normal
				wallTangent = (dir - normal * dir:Dot(normal)).Unit
				wallSpeed = math.min(speed * W.EntryBoost, M.MaxSpeed)
				wallVy = math.max(math.min(v.Y, 25), W.EntryLift)
				wallRunStart = os.clock()
				refillDash()
				setState("WallRun")
				Movement.Info.WallNormal = normal
				return true
			end
		end
	end
	return false
end

local function stepWallRun(dt: number, v: Vector3)
	local r = root :: BasePart
	local hit = workspace:Raycast(r.Position, -wallNormal * (W.CheckDistance + 0.5), rayParams)
	local elapsed = os.clock() - wallRunStart
	local move = (humanoid :: Humanoid).MoveDirection
	local pullingAway = move.Magnitude > 0.1 and move:Dot(wallNormal) > 0.7
	if not isRunnableWall(hit) or elapsed > W.MaxDuration or pullingAway then
		endWallRun()
		return
	end
	-- Follow curved walls.
	wallNormal = Flat((hit :: RaycastResult).Normal).Unit
	Movement.Info.WallNormal = wallNormal
	local flat = Flat(v)
	local along = flat - wallNormal * flat:Dot(wallNormal)
	if along.Magnitude > 1 then
		wallTangent = along.Unit
	else
		wallTangent = (wallTangent - wallNormal * wallTangent:Dot(wallNormal)).Unit
	end

	-- Gravity ramps up the longer you ride, so you can't wall-run forever.
	wallVy -= W.Gravity * (1 + elapsed) * dt
	wallSpeed -= W.Friction * dt
	if wallSpeed < W.MinSpeed * 0.7 then
		endWallRun()
		return
	end
	r.AssemblyLinearVelocity = wallTangent * wallSpeed + Vector3.new(0, wallVy, 0) - wallNormal * W.Stick
end

local function wallJump(normal: Vector3, tangent: Vector3, speed: number)
	local r = root :: BasePart
	local velocity = tangent * speed * W.JumpSpeedKeep + normal * W.JumpOut + Vector3.new(0, W.JumpUp, 0)
	r.AssemblyLinearVelocity = velocity
	airSpeed = Flat(velocity).Magnitude
	lastWallNormal = normal
	lastWallRunEnd = os.clock()
	coyoteUsed = true
	setState("Air")
	Movement.WallJumped:Fire()
end

-- Sliding --------------------------------------------------------------------

local function tryStartSlide(v: Vector3)
	local flat = Flat(v)
	if flat.Magnitude < S.MinSpeed then
		return
	end
	slideDir = flat.Unit
	slideSpeed = flat.Magnitude
	if os.clock() - lastSlideBoost > S.BoostCooldown then
		slideSpeed += S.Boost
		lastSlideBoost = os.clock()
	end
	slideSpeed = math.min(slideSpeed, M.MaxSpeed)
	slideAirTime = 0
	setState("Slide")
end

local function endSlide()
	groundSpeed = math.max(slideSpeed, M.WalkSpeed)
	setState("Ground")
end

local function stepSlide(dt: number, v: Vector3, grounded: boolean)
	local r = root :: BasePart
	local h = humanoid :: Humanoid
	if not slideHeld then
		endSlide()
		return
	end
	if not grounded then
		-- Small grace period so bumps don't cancel the slide.
		slideAirTime += dt
		if slideAirTime > 0.2 then
			airSpeed = slideSpeed
			setState("Air")
			return
		end
	else
		slideAirTime = 0
	end

	-- Slopes: the part of gravity along the floor speeds you up downhill.
	local floor = workspace:Raycast(r.Position, Vector3.new(0, -6, 0), rayParams)
	if floor then
		local n = floor.Normal
		local gravity = Vector3.new(0, -workspace.Gravity, 0)
		local downhill = Flat(gravity - n * gravity:Dot(n))
		slideSpeed += downhill:Dot(slideDir) * S.SlopeFactor * dt
	end

	local move = h.MoveDirection
	if move.Magnitude > 0.1 and move:Dot(slideDir) > -0.3 then
		slideDir = RotateToward(slideDir, move.Unit, S.Steer * dt)
	end
	slideSpeed = math.min(slideSpeed - S.Friction * dt, M.MaxSpeed)
	if slideSpeed < S.EndSpeed then
		endSlide()
		return
	end
	h.WalkSpeed = slideSpeed
	r.AssemblyLinearVelocity = slideDir * slideSpeed + Vector3.new(0, v.Y, 0)
end

-- Ground and air -------------------------------------------------------------

local function land(v: Vector3, impact: number)
	groundSpeed = math.clamp(Flat(v).Magnitude, M.WalkSpeed, M.MaxSpeed)
	refillDash()
	setState("Ground")
	Movement.Landed:Fire(impact)
end

local function stepGround(dt: number, v: Vector3)
	local h = humanoid :: Humanoid
	-- Landing speed carries into your run, then bleeds off. Jump right as you
	-- land (bunny-hop) to keep it.
	local friction = if h.MoveDirection.Magnitude > 0.1 then M.GroundFriction else M.IdleFriction
	groundSpeed = M.WalkSpeed + (groundSpeed - M.WalkSpeed) * math.exp(-friction * dt)
	h.WalkSpeed = groundSpeed
	if slideHeld then
		tryStartSlide(v)
	end
end

local function stepAir(dt: number, v: Vector3)
	local r = root :: BasePart
	local flat = Flat(v)
	local actual = flat.Magnitude

	if tryStartWallRun(v) then
		return
	end

	if airSpeed > M.WalkSpeed and actual < airSpeed * M.CollisionSpeedLoss then
		airSpeed = actual -- we hit something; respect it
	end
	if airSpeed <= M.WalkSpeed + 0.5 then
		-- Slow enough that the Humanoid's own air control feels right.
		airSpeed = actual
		return
	end

	-- Fast: we own horizontal velocity so the Humanoid can't eat our momentum.
	local dir = if actual > 0.1 then flat.Unit else Flat(workspace.CurrentCamera.CFrame.LookVector).Unit
	local move = (humanoid :: Humanoid).MoveDirection
	if move.Magnitude > 0.1 then
		local wish = move.Unit
		if wish:Dot(dir) < -0.5 then
			airSpeed -= M.AirBrake * dt
		else
			dir = RotateToward(dir, wish, M.AirSteer * dt)
		end
	end
	airSpeed = math.min(airSpeed * (1 - M.AirDrag * dt), M.MaxSpeed)
	r.AssemblyLinearVelocity = dir * airSpeed + Vector3.new(0, v.Y, 0)
end

-- Actions ----------------------------------------------------------------------

local function processJump(v: Vector3)
	if os.clock() - jumpPressedAt > M.JumpBuffer then
		return
	end
	if state == "WallRun" then
		-- Only presses made while on the wall count, so a buffered ground jump
		-- doesn't instantly kick you off a wall you just touched.
		if jumpPressedAt < wallRunStart then
			return
		end
		jumpPressedAt = -math.huge
		wallJump(wallNormal, wallTangent, wallSpeed)
	elseif state == "Slide" then
		jumpPressedAt = -math.huge
		local r = root :: BasePart
		local h = humanoid :: Humanoid
		local speed = math.min(slideSpeed * S.JumpBoost, M.MaxSpeed)
		local jumpVelocity = math.max(v.Y, h.JumpPower)
		r.AssemblyLinearVelocity = slideDir * speed + Vector3.new(0, jumpVelocity, 0)
		h:ChangeState(Enum.HumanoidStateType.Jumping)
		airSpeed = speed
		setState("Air")
	elseif state == "Air" and not coyoteUsed and lastWallNormal and os.clock() - lastWallRunEnd < W.CoyoteTime then
		jumpPressedAt = -math.huge
		wallJump(lastWallNormal, lastWallTangent, math.max(airSpeed, W.MinSpeed))
	end
end

local function dash()
	local r, h = root, humanoid
	if not r or not h or h.Health <= 0 then
		return
	end
	if dashCharges <= 0 or os.clock() - lastDash < D.Cooldown then
		return
	end
	if state == "Ground" or state == "Slide" then
		return
	end
	if state == "Grapple" then
		Grapple.Release(false)
	elseif state == "WallRun" then
		endWallRun()
	end
	local move = h.MoveDirection
	local dir = if move.Magnitude > 0.1 then move.Unit else Flat(workspace.CurrentCamera.CFrame.LookVector).Unit
	local v = r.AssemblyLinearVelocity
	local speed = math.min(math.max(Flat(v).Magnitude, M.WalkSpeed) + D.Speed, M.MaxSpeed)
	r.AssemblyLinearVelocity = dir * speed + Vector3.new(0, math.max(v.Y, D.Lift), 0)
	airSpeed = speed
	dashCharges -= 1
	lastDash = os.clock()
	setState("Air")
	Movement.Dashed:Fire()
end

local function onTouched(hit: BasePart)
	local r, h = root, humanoid
	if not r or not h or not CollectionService:HasTag(hit, "LaunchPad") then
		return
	end
	if os.clock() - lastLaunch < 0.5 then
		return
	end
	local launch = hit:GetAttribute("LaunchVelocity")
	if typeof(launch) ~= "Vector3" then
		return
	end
	lastLaunch = os.clock()
	if state == "Grapple" then
		Grapple.Release(false)
	end
	h:ChangeState(Enum.HumanoidStateType.Jumping)
	r.AssemblyLinearVelocity = launch
	airSpeed = Flat(launch).Magnitude
	refillDash()
	setState("Air")
	Movement.Launched:Fire()
end

-- Main loop --------------------------------------------------------------------

local lastVy = 0

local function onHeartbeat(dt: number)
	local r, h = root, humanoid
	if not r or not h or h.Health <= 0 then
		return
	end
	local grounded = h.FloorMaterial ~= Enum.Material.Air

	processJump(r.AssemblyLinearVelocity)
	local v = r.AssemblyLinearVelocity

	if state == "Grapple" then
		if Grapple.IsAttached() then
			Grapple.Step(dt, h.MoveDirection)
		else
			enterAir()
		end
	elseif state == "WallRun" then
		if grounded then
			land(v, 0)
		else
			stepWallRun(dt, v)
		end
	elseif state == "Slide" then
		stepSlide(dt, v, grounded)
	elseif grounded then
		if state == "Air" then
			land(v, math.max(-lastVy, 0))
		end
		stepGround(dt, v)
	else
		if state == "Ground" then
			enterAir()
		end
		stepAir(dt, v)
	end

	local finalVelocity = r.AssemblyLinearVelocity
	lastVy = finalVelocity.Y
	Movement.Info.Velocity = finalVelocity
	Movement.Info.Speed = Flat(finalVelocity).Magnitude
	Movement.Info.DashCharges = dashCharges
end

local function onGrappleAttached()
	local h, r = humanoid, root
	if not h or not r then
		return
	end
	if h.FloorMaterial ~= Enum.Material.Air then
		-- Pop off the ground so the rope can swing us.
		h:ChangeState(Enum.HumanoidStateType.Jumping)
		r.AssemblyLinearVelocity += Vector3.new(0, 20, 0)
	end
	refillDash()
	setState("Grapple")
end

local function onCharacterAdded(character: Model)
	local h = character:WaitForChild("Humanoid") :: Humanoid
	local r = character:WaitForChild("HumanoidRootPart") :: BasePart
	humanoid, root = h, r
	rayParams.FilterDescendantsInstances = { character }

	h.UseJumpPower = true
	h.JumpPower = M.JumpPower
	h.WalkSpeed = M.WalkSpeed
	-- Fast movement shouldn't trip the character over.
	h:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	h:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)

	groundSpeed, airSpeed = M.WalkSpeed, 0
	refillDash()
	setState("Ground")
	Movement.Info.Character = character
	Movement.Info.Humanoid = h
	Movement.Info.Root = r

	Grapple.SetCharacter(character)
	h.Touched:Connect(onTouched)
	h.Died:Connect(function()
		Grapple.SetCharacter(nil)
	end)
end

-- Input ------------------------------------------------------------------------

local function handleGrapple(_, inputState: Enum.UserInputState)
	if inputState == Enum.UserInputState.Begin then
		Grapple.Fire()
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		Grapple.Release()
	end
	return Enum.ContextActionResult.Sink
end

local function handleSlide(_, inputState: Enum.UserInputState)
	slideHeld = inputState == Enum.UserInputState.Begin
	return Enum.ContextActionResult.Sink
end

local function handleDash(_, inputState: Enum.UserInputState)
	if inputState == Enum.UserInputState.Begin then
		dash()
	end
	return Enum.ContextActionResult.Sink
end

local function handleJump(_, inputState: Enum.UserInputState)
	if inputState == Enum.UserInputState.Begin then
		jumpPressedAt = os.clock()
	end
	-- Let the default jump still happen.
	return Enum.ContextActionResult.Pass
end

function Movement.Start()
	ContextActionService:BindAction(
		"SkyboundGrapple",
		handleGrapple,
		true,
		Enum.UserInputType.MouseButton1,
		Enum.KeyCode.ButtonR2
	)
	ContextActionService:BindAction(
		"SkyboundSlide",
		handleSlide,
		true,
		Enum.KeyCode.LeftControl,
		Enum.KeyCode.C,
		Enum.KeyCode.ButtonB
	)
	ContextActionService:BindAction(
		"SkyboundDash",
		handleDash,
		true,
		Enum.KeyCode.Q,
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.ButtonX
	)
	ContextActionService:BindAction("SkyboundJump", handleJump, false, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)

	ContextActionService:SetTitle("SkyboundGrapple", "Hook")
	ContextActionService:SetTitle("SkyboundSlide", "Slide")
	ContextActionService:SetTitle("SkyboundDash", "Dash")
	ContextActionService:SetPosition("SkyboundGrapple", UDim2.new(1, -150, 1, -150))
	ContextActionService:SetPosition("SkyboundSlide", UDim2.new(1, -220, 1, -90))
	ContextActionService:SetPosition("SkyboundDash", UDim2.new(1, -220, 1, -160))

	-- The mobile jump button doesn't go through ContextActionService.
	UserInputService.JumpRequest:Connect(function()
		if UserInputService.TouchEnabled and os.clock() - lastTouchJump > 0.25 then
			lastTouchJump = os.clock()
			jumpPressedAt = os.clock()
		end
	end)

	Grapple.Attached.Event:Connect(onGrappleAttached)
	RunService.Heartbeat:Connect(onHeartbeat)

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end
end

return Movement

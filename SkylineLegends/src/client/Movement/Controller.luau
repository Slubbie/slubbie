-- The movement controller: the heart of Skyline Legends.
--
-- A state machine that owns the local character's momentum:
--
--   Ground ⇄ Crouch ⇄ Slide            Roll / Stumble (after landings)
--     ↕                                  Vault / Mantle (scripted paths)
--   Air ── WallRun ── WallClimb ── Ledge ── Climb
--     ├── Balance (beams)    ├── Zipline    ├── Swing (ropes, grapple)
--     └── Dash               └── Pull (pull anchors)
--
-- Rules every move follows:
--   • Momentum is tracked by the controller, not the Humanoid: landing speed
--     carries into the run, air control is limited, collisions are respected.
--   • Jumps are buffered (JumpBuffer) and allowed briefly after leaving an edge
--     (CoyoteTime), off a wall you just left (WallCoyote) and from ledges.
--   • Aerial resources (double jump, dash charges) refresh on the ground, on
--     walls, ledges, ropes and anchors, and the HUD shows what's available.
--   • Stamina gates sprinting, wall running, climbing, hanging and the
--     powerful moves, with a visible cost for each.
--
-- All numbers come from the effective stats (Config/Movement + skills, or the
-- standard set in ranked runs). The character is simulated on this client and
-- replicates to everyone; the server validates what we report.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MathUtil = require(ReplicatedStorage.Shared.Util.MathUtil)
local MoveStats = require(ReplicatedStorage.Shared.Logic.MoveStats)
local Net = require(ReplicatedStorage.Shared.Net)
local Schedule = require(ReplicatedStorage.Shared.Logic.Schedule)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Tags = require(ReplicatedStorage.Shared.Tags)

local Input = require(script.Parent.Parent.Core.Input)
local Settings = require(script.Parent.Parent.Core.Settings)
local State = require(script.Parent.Parent.Core.State)
local Body = require(script.Parent.Body)
local Sensors = require(script.Parent.Sensors)
local Stamina = require(script.Parent.Stamina)
local Swing = require(script.Parent.Swing)

local Flat = MathUtil.Flat
local FlatUnit = MathUtil.FlatUnit
local UP = Vector3.yAxis

local player = Players.LocalPlayer

local Controller = {}

-- Public read-only snapshot for animation, camera, HUD, audio and effects.
Controller.Info = {
	Character = nil :: Model?,
	Humanoid = nil :: Humanoid?,
	Root = nil :: BasePart?,
	State = "Ground",
	Velocity = Vector3.zero,
	Speed = 0,
	Grounded = true,
	Posture = "Stand", -- "Stand" | "Low"
	Sprinting = false,
	WallNormal = nil :: Vector3?,
	Aux = nil :: Vector3?, -- anchor / ledge normal / cable direction depending on state
	Sway = 0,
	AirTime = 0,
	DoubleJumpReady = false,
	DashCharges = 0,
	DashReady = 0, -- 0..1 cooldown progress
	GrappleTarget = nil :: BasePart?,
	Floor = nil :: BasePart?,
	FloorMaterial = Enum.Material.Air,
	PathKind = nil :: string?,
	PathAlpha = 0,
	LastLandImpact = 0,
}

Controller.Action = Signal.new() -- (name, value?)
Controller.Landed = Signal.new() -- (impact, kind)
Controller.StateChanged = Signal.new() -- (new, old)
Controller.Teleported = Signal.new() -- (cframe)
Controller.Fell = Signal.new() -- (reason) fell out of the world / into a kill zone
Controller.Stats = MoveStats.Standard()
Controller.Perks = {} :: { [string]: number }
Controller.Enabled = true
-- Set by the course/respawn systems: returns true if this position is "out".
Controller.KillCheck = nil :: ((Vector3) -> boolean)?

-- Moves the server hears about (counted for mastery, quests and achievements).
local REPORT = {
	Vault = true,
	Mantle = true,
	LedgeGrab = true,
	LedgeLeap = true,
	Slide = true,
	SlideJump = true,
	Climb = true,
	ClimbHop = true,
	WallRun = true,
	WallJump = true,
	WallKick = true,
	WallClimb = true,
	DoubleJump = true,
	Dash = true,
	Grapple = true,
	GrappleRelease = true,
	Pull = true,
	RopeSwing = true,
	Zipline = true,
	Balance = true,
	BalanceCatch = true,
	Roll = true,
	PrecisionLand = true,
	Bounce = true,
	Launch = true,
	Stumble = true,
}

local stats = Controller.Stats
local abilities: { [string]: boolean } = {}
local mode = { Standardized = false, Assists = {} :: { [string]: boolean }, Extra = nil :: { [string]: boolean }? }

local humanoid: Humanoid? = nil
local root: BasePart? = nil
local facing: AlignOrientation? = nil

local state = "Ground"
local stateStart = 0

-- Momentum.
local groundSpeed = 0
local airVel = Vector3.zero
local airStart = 0
local lastVy = 0
local lastGroundTime = 0
local jumpedSinceGround = false
local lastJumpTime = -math.huge
local jumpCut = false
local platformVelocity = Vector3.zero
local lastFloor: BasePart? = nil

-- Aerial resources.
local doubleJumpUsed = false
local dashCharges = 1
local lastDash = -math.huge
local dashUntil = 0
local dashDir = Vector3.zAxis
local dashSpeed = 0
local dashGround = false

-- Walls.
local wallNormal = Vector3.xAxis
local wallTangent = Vector3.zAxis
local wallSpeed = 0
local wallVy = 0
local wallStart = 0
local lastWallNormal: Vector3? = nil
local lastWallTangent = Vector3.zAxis
local lastWallSpeed = 0
local lastWallEnd = -math.huge
local wallCoyoteUsed = true
local wallClimbUsed = false
local climbVy = 0
local lastKickNormal: Vector3? = nil
local lastKickPosition = Vector3.zero

-- Ledges and climbing.
local ledge: Sensors.Ledge? = nil
local ledgeOffset = Vector3.zero
local ledgeNormal = Vector3.zAxis
local lastDrop = -math.huge
local climbPart: BasePart? = nil
local climbNormal = Vector3.zAxis
local climbPosition = Vector3.zero
local climbStart = 0

-- Ground moves.
local slideDir = Vector3.zAxis
local slideSpeed = 0
local slideAirTime = 0
local lastSlideBoost = -math.huge
local rollUntil = 0
local rollDir = Vector3.zAxis
local rollSpeed = 0
local stumbleUntil = 0
local stumbleLand = 0

-- Traversal objects.
local balancePart: BasePart? = nil
local balanceAxis = Vector3.zAxis
local balanceStart = 0
local balanceTravel = 0
local sway = 0
local swayVel = 0
local offBeam = 0
local zipPart: BasePart? = nil
local zipA, zipB = Vector3.zero, Vector3.zero
local zipDir = Vector3.zAxis
local zipPoint = Vector3.zero
local zipSpeed = 0
local zipStart = 0
local lastZip = -math.huge
local lastZipPart: BasePart? = nil
local lastRope = -math.huge
local lastRopePart: BasePart? = nil
local lastBounce = -math.huge
local pullTarget: Vector3? = nil

-- Cached world objects near the player.
local cache = {
	Ziplines = {} :: { BasePart },
	Ropes = {} :: { BasePart },
	Anchors = {} :: { BasePart },
	Pulls = {} :: { BasePart },
	Wind = {} :: { BasePart },
	Gravity = {} :: { BasePart },
	Vents = {} :: { BasePart },
	Kill = {} :: { BasePart },
	Refreshed = 0,
}

local lastSent = { State = "", Aux = nil :: Vector3?, Time = 0 }
-- Toggle-mode latches for sprint and crouch (accessibility settings).
local sprintLatched = false
local crouchLatched = false
local stillSince = 0
local grappleScan = 0

-- Helpers --------------------------------------------------------------------------------------

local function now(): number
	return os.clock()
end

local function fire(name: string, value: number?)
	Controller.Action:Fire(name, value)
	if REPORT[name] then
		Net.Send("Move.Action", name, value)
	end
end

local function has(ability: string): boolean
	return abilities[ability] == true
end

local function setState(newState: string)
	if newState == state then
		return
	end
	local old = state
	state = newState
	stateStart = now()
	if newState ~= "Ground" and newState ~= "Crouch" and newState ~= "Slide" then
		crouchLatched = false
	end
	Controller.Info.State = newState
	if newState ~= "WallRun" and newState ~= "WallClimb" then
		Controller.Info.WallNormal = nil
	end
	Controller.StateChanged:Fire(newState, old)
end

local function refreshAir()
	doubleJumpUsed = false
	dashCharges = stats.DashCharges
	wallClimbUsed = false
end

local function lookDirection(): Vector3
	local h, r = humanoid, root
	if h and h.MoveDirection.Magnitude > 0.1 then
		return FlatUnit(h.MoveDirection)
	end
	if r then
		local flat = Flat(r.AssemblyLinearVelocity)
		if flat.Magnitude > 3 then
			return flat.Unit
		end
		return FlatUnit(r.CFrame.LookVector)
	end
	return Vector3.zAxis
end

local function cameraFlat(): Vector3
	return FlatUnit(workspace.CurrentCamera.CFrame.LookVector)
end

local function setPosture(low: boolean)
	Controller.Info.Posture = if low then "Low" else "Stand"
	if Body.Group() ~= Tags.Groups.PlayersPhase then
		Body.SetGroup(if low then Tags.Groups.PlayersLow else Tags.Groups.Players)
	end
end

local function sprintWanted(): boolean
	local setting = Settings.Get("SprintMode")
	if setting == "Auto" then
		return true
	elseif setting == "Toggle" then
		return sprintLatched
	end
	return Input.Held("Sprint")
end

-- Crouch input, honouring the toggle setting.
local function crouchHeld(): boolean
	if Settings.Get("CrouchToggle") then
		return crouchLatched
	end
	return Input.Held("Crouch")
end

local function runTarget(moving: boolean): number
	local sprinting = moving and sprintWanted() and not Stamina.Exhausted and Stamina.Value > 0
	Controller.Info.Sprinting = sprinting
	return if sprinting then stats.SprintSpeed else stats.WalkSpeed
end

local function inZone(list: { BasePart }, position: Vector3): BasePart?
	for _, zone in list do
		if zone.Parent and Sensors.Inside(zone, position) then
			return zone
		end
	end
	return nil
end

local function refreshCache()
	local r = root
	if not r then
		return
	end
	cache.Refreshed = now()
	local position = r.Position
	local function near(tag: string, range: number): { BasePart }
		local result = {}
		for _, instance in CollectionService:GetTagged(tag) do
			if
				instance:IsA("BasePart")
				and (instance.Position - position).Magnitude < range + instance.Size.Magnitude / 2
			then
				table.insert(result, instance)
			end
		end
		return result
	end
	cache.Ziplines = near(Tags.Zipline, 250)
	cache.Ropes = near(Tags.SwingRope, 200)
	cache.Anchors = near(Tags.GrappleAnchor, 220)
	cache.Pulls = near(Tags.PullAnchor, 220)
	cache.Wind = near(Tags.WindZone, 200)
	cache.Gravity = near(Tags.GravityZone, 200)
	cache.Vents = near(Tags.LaunchVent, 200)
	cache.Kill = near(Tags.KillZone, 2000)
end

-- State transitions -------------------------------------------------------------------------------

local enterAir, land, enterGround

function enterGround(speed: number?)
	local h = humanoid
	if speed then
		groundSpeed = speed
	end
	setPosture(false)
	setState("Ground")
	if h then
		h.WalkSpeed = math.max(groundSpeed, stats.WalkSpeed * 0.5)
	end
end

function enterAir(velocity: Vector3?)
	local r = root
	if not r then
		return
	end
	local v = velocity or r.AssemblyLinearVelocity
	if velocity then
		r.AssemblyLinearVelocity = velocity
	end
	airVel = Flat(v)
	airStart = now()
	setPosture(false)
	setState("Air")
end

local function jump(verticalSpeed: number?)
	local h, r = humanoid, root
	if not h or not r then
		return
	end
	local flat = Flat(r.AssemblyLinearVelocity)
	local move = h.MoveDirection
	if move.Magnitude > 0.1 then
		-- Take off in the direction you're steering, at your current running speed.
		local speed = math.max(flat.Magnitude, math.min(groundSpeed, stats.MaxSpeed))
		flat = move.Unit * speed
	end
	flat += Flat(platformVelocity)
	h:ChangeState(Enum.HumanoidStateType.Jumping)
	local velocity = flat + UP * ((verticalSpeed or stats.JumpVelocity) + math.max(platformVelocity.Y, 0))
	jumpedSinceGround = true
	lastJumpTime = now()
	jumpCut = false
	enterAir(velocity)
	fire("Jump")
end

-- Wall run ----------------------------------------------------------------------------------------

local function endWallRun()
	lastWallNormal = wallNormal
	lastWallTangent = wallTangent
	lastWallSpeed = wallSpeed
	lastWallEnd = now()
	wallCoyoteUsed = false
	local duration = now() - wallStart
	fire("WallRun", duration)
	enterAir(wallTangent * wallSpeed + UP * wallVy)
end

local function wallJump(normal: Vector3, tangent: Vector3, speed: number)
	if not Stamina.Spend("WallJump") then
		return
	end
	local velocity = tangent * speed * stats.WallJumpKeep + normal * stats.WallJumpOut + UP * stats.WallJumpUp
	lastKickNormal = normal
	lastKickPosition = if root then root.Position else Vector3.zero
	wallCoyoteUsed = true
	jumpedSinceGround = true
	lastJumpTime = now()
	jumpCut = true
	enterAir(velocity)
	Controller.Info.WallNormal = normal
	fire("WallJump")
end

local function tryWallRun(v: Vector3): boolean
	local r, h = root, humanoid
	if not r or not h or not has("WallRun") then
		return false
	end
	local flat = Flat(v)
	local speed = flat.Magnitude
	if speed < stats.WallRunMinSpeed or v.Y < -45 or Stamina.Value < 4 then
		return false
	end
	-- Must be steering along the wall, not away from it.
	local move = h.MoveDirection
	if move.Magnitude < 0.1 or move:Dot(flat.Unit) < 0.2 then
		return false
	end
	-- Not right above the floor.
	if Sensors.Cast(r.Position, Vector3.new(0, -(stats.RootHeight + stats.WallRunMinHeight), 0)) then
		return false
	end
	local wall = Sensors.WallSide(r, flat, stats.WallRunCheck)
	if not wall then
		return false
	end
	if move:Dot(wall.Normal) > 0.5 then
		return false
	end
	local sameWall = lastWallNormal ~= nil
		and now() - lastWallEnd < stats.WallRunSameWallCooldown
		and wall.Normal:Dot(lastWallNormal :: Vector3) > 0.9
	if sameWall then
		return false
	end
	local dir = flat.Unit
	wallNormal = wall.Normal
	wallTangent = (dir - wallNormal * dir:Dot(wallNormal)).Unit
	wallSpeed = math.min(math.max(speed, stats.WallRunSpeed), stats.MaxSpeed)
	wallVy = math.clamp(v.Y * 0.4, stats.WallRunStartLift * 0.4, stats.WallRunStartLift + 4)
	if v.Y > 0 then
		wallVy = math.max(wallVy, stats.WallRunStartLift)
	end
	wallStart = now()
	refreshAir()
	Controller.Info.WallNormal = wallNormal
	setState("WallRun")
	Controller.Action:Fire("WallRunStart")
	return true
end

local function stepWallRun(dt: number)
	local r, h = root, humanoid
	if not r or not h then
		return
	end
	local hit = Sensors.Cast(r.Position, -wallNormal * (stats.WallRunCheck + 0.8))
	local elapsed = now() - wallStart
	local move = h.MoveDirection
	local pullingAway = move.Magnitude > 0.1 and move:Dot(wallNormal) > 0.6
	if Input.Buffered("Jump", stats.JumpBuffer) and Input.PressedAt("Jump") > wallStart then
		Input.Consume("Jump")
		wallJump(wallNormal, wallTangent, wallSpeed)
		return
	end
	if
		not hit
		or math.abs(hit.Normal.Y) > 0.35
		or elapsed > stats.WallRunMaxTime
		or pullingAway
		or Input.Held("Crouch")
	then
		endWallRun()
		return
	end
	if not Stamina.Drain("WallRun", dt) then
		endWallRun()
		return
	end
	-- Follow curved walls.
	wallNormal = FlatUnit(hit.Normal, wallNormal)
	Controller.Info.WallNormal = wallNormal
	local flat = Flat(r.AssemblyLinearVelocity)
	local along = flat - wallNormal * flat:Dot(wallNormal)
	if along.Magnitude > 1 then
		wallTangent = along.Unit
	else
		wallTangent = (wallTangent - wallNormal * wallTangent:Dot(wallNormal)).Unit
	end
	local gravity = stats.WallRunGravity
		+ (stats.WallRunGravityEnd - stats.WallRunGravity) * math.clamp(elapsed / stats.WallRunMaxTime, 0, 1)
	wallVy -= gravity * dt
	wallSpeed = math.max(wallSpeed - 2 * dt, stats.WallRunMinSpeed)
	if h.FloorMaterial ~= Enum.Material.Air and wallVy < 0 then
		endWallRun()
		return
	end
	r.AssemblyLinearVelocity = wallTangent * wallSpeed + UP * wallVy - wallNormal * 2
end

-- Ledges --------------------------------------------------------------------------------------------

local function ledgeWorldPoint(): Vector3
	local current = ledge
	if current and current.Part and current.Part.Parent then
		return current.Part.CFrame:PointToWorldSpace(ledgeOffset)
	end
	return if current then current.Point else Vector3.zero
end

local function hangCFrame(point: Vector3, normal: Vector3): CFrame
	local position = point + normal * stats.LedgeWallGap - UP * stats.LedgeHangDrop
	return CFrame.lookAt(position, position - normal)
end

local function enterLedge(found: Sensors.Ledge)
	ledge = found
	ledgeNormal = found.Normal
	ledgeOffset = found.Part.CFrame:PointToObjectSpace(found.Point)
	refreshAir()
	Swing.Detach(false)
	Body.BeginHold()
	setPosture(false)
	Controller.Info.Aux = ledgeNormal
	setState("Ledge")
	fire("LedgeGrab")
end

local function mantle(found: Sensors.Ledge)
	local r = root
	if not r then
		return
	end
	local point = if ledge == found then ledgeWorldPoint() else found.Point
	local normal = found.Normal
	local stand = point - normal * 1.6 + UP * (stats.RootHeight + 0.05)
	local from = r.CFrame
	local control = Vector3.new(from.Position.X, math.max(stand.Y + 0.8, from.Position.Y), from.Position.Z)
		- normal * 0.3
	local to = CFrame.lookAt(stand, stand - normal)
	Body.StartPath("Mantle", from, control, to, stats.MantleDuration, -normal * 8, true)
	ledge = nil
	setState("Mantle")
	fire("Mantle")
end

local function dropFromLedge(push: Vector3)
	ledge = nil
	lastDrop = now()
	Body.EndHold(push)
	enterAir(push)
end

local function tryLedge(v: Vector3, direction: Vector3?): boolean
	local r = root
	if not r or not has("LedgeGrab") or now() - lastDrop < stats.LedgeRegrabDelay then
		return false
	end
	if v.Y > stats.LedgeMaxRiseSpeed then
		return false
	end
	local found =
		Sensors.Ledge(r, direction or lookDirection(), stats.LedgeReach, stats.LedgeMinAbove, stats.LedgeMaxAbove)
	if not found then
		return false
	end
	-- Pushing forward onto a ledge you can stand on: go straight over.
	local h = humanoid
	if found.CanMantle and h and h.MoveDirection:Dot(-found.Normal) > 0.75 and found.TopY - r.Position.Y < 1.2 then
		mantle(found)
		return true
	end
	enterLedge(found)
	return true
end

local function stepLedge(dt: number)
	local r, h = root, humanoid
	local current = ledge
	if not r or not h or not current then
		enterAir()
		return
	end
	if not current.Part.Parent then
		dropFromLedge(Vector3.zero)
		return
	end
	if not Stamina.Drain("Hang", dt) then
		dropFromLedge(ledgeNormal * 3)
		return
	end
	local move = h.MoveDirection
	local tangent = ledgeNormal:Cross(UP)
	local forward = move:Dot(-ledgeNormal)
	local back = move:Dot(ledgeNormal)
	local lateral = move:Dot(tangent)

	if Input.Buffered("Jump", stats.JumpBuffer) then
		Input.Consume("Jump")
		if back > 0.5 and has("WallJump") then
			-- Kick away from the wall.
			ledge = nil
			lastDrop = now()
			Body.EndHold()
			local velocity = ledgeNormal * stats.LedgeJumpOut + UP * stats.LedgeJumpUp
			lastKickNormal = ledgeNormal
			lastKickPosition = r.Position
			enterAir(velocity)
			fire("WallKick")
			return
		end
		if has("LedgeLeap") and Stamina.CanAfford("LedgeLeap") then
			-- Look for a ledge above to leap to.
			local probe = Sensors.LedgeFrom(
				r.Position + UP * stats.LedgeLeapHeight,
				-ledgeNormal,
				stats.LedgeReach + 0.4,
				stats.LedgeMinAbove - 1,
				stats.LedgeMaxAbove
			)
			if probe and probe.TopY > current.TopY + 2 then
				Stamina.Spend("LedgeLeap")
				local target = hangCFrame(probe.Point, probe.Normal)
				Body.StartPath(
					"Leap",
					r.CFrame,
					r.Position + UP * (target.Y - r.Position.Y + 1.5),
					target,
					0.32,
					Vector3.zero,
					false
				)
				ledge = probe
				ledgeNormal = probe.Normal
				ledgeOffset = probe.Part.CFrame:PointToObjectSpace(probe.Point)
				setState("Mantle")
				fire("LedgeLeap")
				return
			end
		end
		if current.CanMantle then
			mantle(current)
			return
		end
	end
	if forward > 0.7 and current.CanMantle and now() - stateStart > 0.12 then
		mantle(current)
		return
	end
	if Input.Held("Crouch") and now() - stateStart > 0.15 then
		dropFromLedge(ledgeNormal * 4)
		return
	end

	local point = ledgeWorldPoint()
	local velocity = Vector3.zero
	if math.abs(lateral) > 0.3 then
		local candidate = point + tangent * math.sign(lateral) * stats.ShimmySpeed * dt
		local part, topY = Sensors.LedgeAt(candidate, ledgeNormal)
		if part and topY then
			point = Vector3.new(candidate.X, topY, candidate.Z)
			current.Part = part
			current.Point = point
			current.TopY = topY
			ledgeOffset = part.CFrame:PointToObjectSpace(point)
			velocity = tangent * math.sign(lateral) * stats.ShimmySpeed
			-- Re-check whether this stretch can be climbed.
			local again = Sensors.Ledge(
				r,
				-ledgeNormal,
				stats.LedgeReach + 0.6,
				stats.LedgeMinAbove - 0.5,
				stats.LedgeMaxAbove + 0.5
			)
			current.CanMantle = again ~= nil and again.CanMantle
		end
	end
	Body.Place(hangCFrame(point, ledgeNormal), velocity)
	Controller.Info.Aux = ledgeNormal
end

-- Vaults ---------------------------------------------------------------------------------------------

local function tryVault(direction: Vector3, speed: number): boolean
	local r = root
	if not r or not has("Vault") then
		return false
	end
	local found = Sensors.Vault(
		r,
		direction,
		stats.VaultReach + speed * 0.06,
		stats.VaultMinHeight,
		stats.VaultMaxHeight,
		stats.VaultMaxDepth,
		stats.RootHeight
	)
	if not found then
		return false
	end
	local from = r.CFrame
	local forward = -found.Normal
	if found.Kind == "Vault" then
		local exitSpeed = math.max(speed * stats.VaultExitBoost, stats.VaultExitMin)
		local landing = found.Landing + UP * stats.RootHeight
		local over = found.Front
			+ forward * (found.Depth / 2)
			+ UP * (found.TopY - found.Front.Y + stats.RootHeight * 0.75)
		local control = Vector3.new(over.X, found.TopY + stats.RootHeight * 0.9, over.Z)
		local duration = stats.VaultDuration * math.clamp(20 / math.max(speed, 8), 0.75, 1.3)
		local to = CFrame.lookAt(landing, landing + forward)
		Body.StartPath("Vault", from, control, to, duration, forward * exitSpeed, true)
		setState("Vault")
		fire("Vault")
	else
		local stand = found.Landing + UP * (stats.RootHeight + 0.05)
		local control = Vector3.new(from.Position.X, stand.Y + 0.5, from.Position.Z)
		local to = CFrame.lookAt(stand, stand + forward)
		Body.StartPath(
			"Step",
			from,
			control,
			to,
			stats.LowMantleDuration,
			forward * math.max(speed * 0.8, stats.WalkSpeed),
			true
		)
		setState("Mantle")
		fire("Mantle")
	end
	return true
end

local function finishPath()
	local kind, exit = Body.Finished()
	Body.SetGroup(Tags.Groups.Players)
	if kind == "Leap" then
		-- Ledge leaps end hanging from the new ledge.
		Body.Place(hangCFrame(ledgeWorldPoint(), ledgeNormal))
		setState("Ledge")
		return
	end
	Body.EndHold(exit, Enum.HumanoidStateType.Freefall)
	local r = root
	if r and Sensors.Ground(r) then
		enterGround(math.max(Flat(exit).Magnitude, stats.WalkSpeed))
		if humanoid then
			humanoid:ChangeState(Enum.HumanoidStateType.Running)
		end
	else
		enterAir(exit)
	end
end

-- Climbing ---------------------------------------------------------------------------------------------

local function enterClimb(surface: Sensors.Wall)
	local r = root
	if not r then
		return
	end
	climbPart = surface.Part
	climbNormal = surface.Normal
	climbPosition = Vector3.new(surface.Position.X, r.Position.Y, surface.Position.Z) + climbNormal * 1.05
	climbStart = now()
	refreshAir()
	Swing.Detach(false)
	Body.BeginHold()
	setPosture(false)
	Controller.Info.Aux = climbNormal
	setState("Climb")
	Controller.Action:Fire("ClimbStart")
end

local function leaveClimb(velocity: Vector3)
	fire("Climb", now() - climbStart)
	climbPart = nil
	Body.EndHold(velocity)
	enterAir(velocity)
end

local function stepClimb(dt: number)
	local r, h = root, humanoid
	if not r or not h then
		return
	end
	local move = h.MoveDirection
	local tangent = climbNormal:Cross(UP)
	local upward = move:Dot(-climbNormal)
	local lateral = move:Dot(tangent)
	local back = move:Dot(climbNormal)

	if Input.Buffered("Jump", stats.JumpBuffer) then
		Input.Consume("Jump")
		if back > 0.5 then
			lastKickNormal = climbNormal
			lastKickPosition = r.Position
			leaveClimb(climbNormal * stats.WallKickOut + UP * stats.WallKickUp)
			fire("WallKick")
			return
		elseif Stamina.Spend("ClimbHop") then
			climbPosition += UP * stats.ClimbHop * 0.5
			local part = Sensors.ClimbAt(climbPosition + UP * stats.ClimbHop * 0.5, climbNormal, stats.ClimbReach)
			if part then
				climbPosition += UP * stats.ClimbHop * 0.5
			end
			fire("ClimbHop")
		end
	end
	if Input.Held("Crouch") and now() - stateStart > 0.15 then
		leaveClimb(climbNormal * 3)
		return
	end

	local vertical = 0
	if upward > 0.25 then
		vertical = stats.ClimbUpSpeed * upward
	elseif upward < -0.25 then
		vertical = stats.ClimbDownSpeed * upward
	end
	local side = if math.abs(lateral) > 0.3 then stats.ClimbSideSpeed * lateral else 0
	local moving = vertical ~= 0 or side ~= 0
	if not Stamina.Drain(if moving then "Climb" else "ClimbIdle", dt) then
		leaveClimb(climbNormal * 3)
		return
	end

	local candidate = climbPosition + UP * vertical * dt + tangent * side * dt
	local part, normal = Sensors.ClimbAt(candidate, climbNormal, stats.ClimbReach)
	if part and normal then
		climbPosition = candidate
		climbPart = part
		climbNormal = normal
	elseif vertical > 0 then
		-- Top of the climb: catch the ledge and go over.
		local found =
			Sensors.Ledge(r, -climbNormal, stats.ClimbReach + 1, stats.LedgeMinAbove - 1.5, stats.LedgeMaxAbove + 1)
		if found then
			fire("Climb", now() - climbStart)
			climbPart = nil
			if found.CanMantle then
				ledge = found
				mantle(found)
			else
				enterLedge(found)
			end
			return
		end
	elseif vertical < 0 then
		-- Bottom: step off onto the floor if there is one.
		if Sensors.Cast(r.Position, Vector3.new(0, -(stats.RootHeight + 0.6), 0)) then
			fire("Climb", now() - climbStart)
			climbPart = nil
			Body.EndHold(Vector3.zero, Enum.HumanoidStateType.Running)
			enterGround(0)
			return
		end
	end
	Body.Place(CFrame.lookAt(climbPosition, climbPosition - climbNormal), UP * vertical + tangent * side)
	Controller.Info.Aux = climbNormal
end

local function tryClimb(direction: Vector3): boolean
	local r, h = root, humanoid
	if not r or not h or not has("Climb") or now() - lastDrop < 0.4 then
		return false
	end
	local surface = Sensors.Climbable(r, direction, stats.ClimbReach)
	if surface and h.MoveDirection:Dot(-surface.Normal) > 0.5 then
		enterClimb(surface)
		return true
	end
	return false
end

-- Wall climb (running up a wall) ---------------------------------------------------------------

local function enterWallClimb(wall: Sensors.Wall)
	if not Stamina.Spend("WallClimb") then
		return false
	end
	wallClimbUsed = true
	wallNormal = wall.Normal
	climbVy = stats.WallClimbSpeed
	Controller.Info.WallNormal = wallNormal
	setState("WallClimb")
	fire("WallClimb")
	return true
end

local function stepWallClimb(dt: number)
	local r = root
	if not r then
		return
	end
	if Input.Buffered("Jump", stats.JumpBuffer) and Input.PressedAt("Jump") > stateStart then
		Input.Consume("Jump")
		-- Turn and kick off the wall.
		lastKickNormal = wallNormal
		lastKickPosition = r.Position
		jumpCut = true
		enterAir(wallNormal * stats.WallJumpOut + UP * stats.WallJumpUp)
		fire("WallJump")
		return
	end
	local found = Sensors.Ledge(r, -wallNormal, stats.LedgeReach + 0.6, stats.LedgeMinAbove, stats.LedgeMaxAbove)
	if found and now() - stateStart > 0.08 then
		local h = humanoid
		if found.CanMantle and h and h.MoveDirection:Dot(-found.Normal) > 0.8 and found.TopY - r.Position.Y < 0.5 then
			ledge = found
			mantle(found)
		else
			enterLedge(found)
		end
		return
	end
	climbVy -= stats.WallClimbGravity * dt
	local hit = Sensors.Cast(r.Position, -wallNormal * 2.6)
	if climbVy <= 0 or now() - stateStart > stats.WallClimbTime or not hit then
		enterAir(wallNormal * 4 + UP * math.max(climbVy, 0))
		return
	end
	r.AssemblyLinearVelocity = -wallNormal * 1.5 + UP * climbVy
end

-- Balance -----------------------------------------------------------------------------------------------

local function beamAxis(part: BasePart): Vector3
	local axis = if part.Size.X > part.Size.Z then part.CFrame.RightVector else part.CFrame.LookVector
	return axis
end

local function enterBalance(part: BasePart)
	balancePart = part
	balanceAxis = beamAxis(part)
	balanceStart = now()
	balanceTravel = 0
	sway = 0
	swayVel = 0
	offBeam = 0
	setState("Balance")
	Controller.Action:Fire("BalanceStart")
end

local function leaveBalance()
	if balanceTravel > 8 then
		fire("Balance", balanceTravel)
	end
	balancePart = nil
end

local function stepBalance(dt: number, ground: Sensors.Ground?)
	local r, h, part = root, humanoid, balancePart
	if not r or not h or not part then
		enterGround()
		return
	end
	if not ground or ground.Part ~= part then
		offBeam += dt
		if offBeam > 0.12 then
			leaveBalance()
			if ground then
				enterGround(stats.WalkSpeed)
			else
				enterAir()
			end
			return
		end
	else
		offBeam = 0
	end
	if Input.Buffered("Jump", stats.JumpBuffer) then
		Input.Consume("Jump")
		leaveBalance()
		jump()
		return
	end
	local axisFlat = FlatUnit(balanceAxis)
	local side = axisFlat:Cross(UP)
	local move = h.MoveDirection
	local along = move:Dot(axisFlat)
	local lateral = move:Dot(side)
	local speed = stats.BalanceSpeed * math.clamp(math.abs(along) * 1.2, 0, 1)

	-- Wobble that grows with speed; wind pushes too.
	local t = now() - balanceStart
	local noise = math.sin(t * 1.7) * 0.6 + math.sin(t * 3.1 + 1.3) * 0.4
	local disturbance = noise * stats.BalanceSway * (0.35 + speed / stats.BalanceSpeed)
	local wind = inZone(cache.Wind, r.Position)
	if wind then
		local force = wind:GetAttribute("Force")
		local on = Schedule.Cycle(
			Schedule.Now(),
			wind:GetAttribute("Period") or 4,
			wind:GetAttribute("OnFraction") or 0.4,
			wind:GetAttribute("Phase") or 0
		)
		if on and typeof(force) == "Vector3" then
			disturbance += force:Dot(side) * stats.BalanceWind
		end
	end
	swayVel += (disturbance + lateral * stats.BalanceCorrect - sway * 0.8) * dt
	swayVel *= math.exp(-stats.BalanceDamping * dt)
	sway = math.clamp(sway + swayVel * dt, -1.2, 1.2)
	Controller.Info.Sway = sway

	if math.abs(sway) >= 1 then
		-- Slipped off: catch the beam if you have the stamina for it.
		local fallSide = side * math.sign(sway)
		local center = part.CFrame:PointToObjectSpace(r.Position)
		local onAxis = part.CFrame
			* Vector3.new(
				if part.Size.X > part.Size.Z then center.X else 0,
				part.Size.Y / 2,
				if part.Size.X > part.Size.Z then 0 else center.Z
			)
		leaveBalance()
		if Stamina.Value > 12 and has("LedgeGrab") then
			local width = math.min(part.Size.X, part.Size.Z)
			local point = onAxis + fallSide * (width / 2)
			enterLedge({ Part = part, Point = point, Normal = fallSide, TopY = point.Y, CanMantle = true })
			fire("BalanceCatch")
		else
			enterAir(fallSide * 8 + UP * 4)
		end
		return
	end

	-- Stay on the centre line.
	local rel = r.Position - part.Position
	local onLine = part.Position + balanceAxis * rel:Dot(balanceAxis)
	local direction = if math.abs(along) > 0.1 then axisFlat * math.sign(along) else FlatUnit(r.CFrame.LookVector)
	local position = Vector3.new(onLine.X, r.Position.Y, onLine.Z)
	r.CFrame = CFrame.lookAt(position, position + direction)
	local v = r.AssemblyLinearVelocity
	r.AssemblyLinearVelocity = axisFlat * math.sign(along) * speed + UP * v.Y
	h.WalkSpeed = math.max(speed, 1)
	balanceTravel += speed * dt
	Controller.Info.Aux = balanceAxis
end

-- Ziplines --------------------------------------------------------------------------------------------

local function enterZip(candidate: Sensors.ZipCandidate, v: Vector3)
	if not has("Zipline") then
		return
	end
	zipPart = candidate.Part
	zipA, zipB = candidate.A, candidate.B
	local along = (zipB - zipA).Unit
	local slope = along.Y
	if math.abs(slope) > 0.05 then
		zipDir = if slope < 0 then along else -along
	else
		zipDir = if v:Dot(along) >= 0 then along else -along
	end
	zipPoint = candidate.Point
	zipSpeed = math.max(v:Dot(zipDir), stats.ZipMinSpeed)
	zipStart = now()
	refreshAir()
	Body.BeginHold()
	setPosture(false)
	Controller.Info.Aux = zipDir
	setState("Zipline")
	Controller.Action:Fire("ZiplineStart")
end

local function leaveZip(velocity: Vector3)
	fire("Zipline", now() - zipStart)
	lastZip = now()
	lastZipPart = zipPart
	zipPart = nil
	Body.EndHold(velocity)
	enterAir(velocity)
end

local function stepZip(dt: number)
	if Input.Buffered("Jump", stats.JumpBuffer) and Input.PressedAt("Jump") > zipStart then
		Input.Consume("Jump")
		leaveZip(zipDir * zipSpeed + UP * stats.ZipJumpUp)
		return
	end
	if Input.Held("Crouch") and now() - stateStart > 0.2 then
		leaveZip(zipDir * zipSpeed * 0.6)
		return
	end
	local downhill = -zipDir.Y
	if math.abs(zipDir.Y) > 0.05 then
		zipSpeed += stats.Gravity * downhill * stats.ZipSlopeAccel * dt
	else
		zipSpeed = MathUtil.Damp(zipSpeed, stats.ZipFlatSpeed, 1.5, dt)
	end
	zipSpeed = math.clamp(zipSpeed, stats.ZipMinSpeed, stats.ZipMaxSpeed)
	zipPoint += zipDir * zipSpeed * dt
	local _, t = MathUtil.ClosestOnSegment(zipA, zipB, zipPoint)
	local towardB = zipDir:Dot(zipB - zipA) > 0
	if (towardB and t >= 0.985) or (not towardB and t <= 0.015) then
		leaveZip(zipDir * zipSpeed + UP * 4)
		return
	end
	local position = zipPoint - UP * stats.ZipHang
	Body.Place(CFrame.lookAt(position, position + FlatUnit(zipDir)), zipDir * zipSpeed)
end

-- Swinging, grappling, pulling ---------------------------------------------------------------------------

local function grabRope(candidate: Sensors.RopeCandidate)
	local r = root
	if not r or not has("RopeSwing") then
		return
	end
	refreshAir()
	local length = (candidate.Pivot - (r.Position + UP * 1.2)).Magnitude
	Swing.Attach("Rope", candidate.Pivot, nil, length, 3)
	lastRopePart = candidate.Part
	Controller.Info.Aux = candidate.Pivot
	-- Bend the visual rope toward our hand.
	Swing.Detach(false)
	Swing.Attach("Rope", candidate.Pivot, candidate.Part, length, 3)
	setState("Swing")
	fire("RopeSwing")
end

local function startPull(anchor: BasePart)
	local r = root
	if not r or not Stamina.Spend("Pull") then
		return
	end
	local target = anchor.Position - UP * 1.2
	local distance = (target - r.Position).Magnitude
	local flatDir = FlatUnit(target - r.Position, FlatUnit(r.CFrame.LookVector))
	local exit = flatDir * stats.PullPopForward + UP * stats.PullPopUp
	local to = CFrame.lookAt(target, target + flatDir)
	Body.StartPath("Pull", r.CFrame, (r.Position + target) / 2, to, distance / stats.PullSpeed, exit, true)
	pullTarget = anchor.Position
	Swing.ShowLine(anchor.Position)
	refreshAir()
	setState("Pull")
	Controller.Info.Aux = anchor.Position
	fire("Pull")
end

local function tryGrapple(): boolean
	local r = root
	if not r or not has("Grapple") then
		return false
	end
	local target = Controller.Info.GrappleTarget
	if not target or not target.Parent then
		return false
	end
	if CollectionService:HasTag(target, Tags.PullAnchor) then
		if not has("GrapplePull") then
			return false
		end
		startPull(target)
		return true
	end
	if not Stamina.Spend("Grapple") then
		return false
	end
	if Controller.Info.Grounded then
		r.AssemblyLinearVelocity += UP * 22
	end
	refreshAir()
	Swing.Attach("Grapple", target.Position, target, nil, stats.GrappleMinLength)
	Controller.Info.Aux = target.Position
	setState("Swing")
	fire("Grapple")
	return true
end

local function releaseSwing(boost: boolean)
	local kind = Swing.Kind()
	local velocity = Swing.Detach(boost, stats)
	if kind == "Grapple" then
		fire("GrappleRelease", velocity.Magnitude)
	end
	lastRope = now()
	enterAir(velocity)
end

local function stepSwing(dt: number)
	local h = humanoid
	if not h then
		return
	end
	local kind = Swing.Kind()
	if not kind then
		enterAir()
		return
	end
	if kind == "Grapple" and not Input.Held("Grapple") then
		releaseSwing(true)
		return
	end
	if kind == "Rope" and Input.Buffered("Jump", stats.JumpBuffer) and Input.PressedAt("Jump") > stateStart then
		Input.Consume("Jump")
		releaseSwing(true)
		return
	end
	local reel = 0
	if kind == "Grapple" then
		reel = if Input.Held("Jump") then stats.GrappleFastReel else stats.GrappleReel
	end
	if not Swing.Step(dt, h.MoveDirection, reel, stats) then
		releaseSwing(false)
		return
	end
	Controller.Info.Aux = Swing.Anchor()
	-- Touching down ends the swing.
	if h.FloorMaterial ~= Enum.Material.Air and now() - stateStart > 0.3 then
		releaseSwing(false)
	end
end

-- Dash --------------------------------------------------------------------------------------------------

local function tryDash(): boolean
	local r, h = root, humanoid
	if not r or not h or not has("Dash") then
		return false
	end
	if dashCharges <= 0 or now() - lastDash < stats.DashCooldown then
		return false
	end
	if not Stamina.Spend("Dash") then
		return false
	end
	if state == "Swing" then
		Swing.Detach(false)
	elseif state == "WallRun" then
		fire("WallRun", now() - wallStart)
	end
	local move = h.MoveDirection
	dashDir = if move.Magnitude > 0.1 then move.Unit else cameraFlat()
	local v = r.AssemblyLinearVelocity
	dashSpeed = math.min(math.max(Flat(v).Magnitude, stats.DashSpeed), stats.MaxSpeed)
	dashGround = Controller.Info.Grounded
	dashCharges -= 1
	lastDash = now()
	dashUntil = now() + stats.DashTime
	setPosture(false)
	setState("Dash")
	fire("Dash")
	return true
end

local function stepDash()
	local r = root
	if not r then
		return
	end
	if now() >= dashUntil then
		local exitSpeed = math.max(stats.DashSpeed * 0.6, airVel.Magnitude, stats.SprintSpeed)
		if dashGround and Controller.Info.Grounded then
			enterGround(exitSpeed)
		else
			enterAir(dashDir * exitSpeed + UP * stats.DashLift * 0.5)
		end
		return
	end
	local vy = if dashGround then math.min(r.AssemblyLinearVelocity.Y, 0) else stats.DashLift
	r.AssemblyLinearVelocity = dashDir * dashSpeed + UP * vy
end

-- Landing and ground moves -------------------------------------------------------------------------------

local function enterSlide(speed: number, direction: Vector3)
	slideDir = direction
	slideSpeed = speed
	if now() - lastSlideBoost > stats.SlideBoostCooldown then
		slideSpeed += stats.SlideBoost
		lastSlideBoost = now()
	end
	slideSpeed = math.min(slideSpeed, stats.MaxSpeed)
	slideAirTime = 0
	setPosture(true)
	setState("Slide")
	fire("Slide")
end

local function enterRoll(speed: number, direction: Vector3)
	rollDir = direction
	rollSpeed = math.min(math.max(speed * stats.RollBoost, stats.WalkSpeed), stats.MaxSpeed)
	rollUntil = now() + stats.RollDuration
	setPosture(true)
	setState("Roll")
	fire("Roll")
end

local function enterStumble(heavy: boolean)
	stumbleUntil = now() + (if heavy then stats.HeavyStumbleTime else stats.StumbleTime)
	stumbleLand = now()
	groundSpeed = stats.StumbleSpeed
	setState("Stumble")
	fire("Stumble")
end

function land(v: Vector3)
	local r = root
	if not r then
		return
	end
	local impact = math.max(-lastVy, 0)
	local flat = Flat(v)
	if airVel.Magnitude > flat.Magnitude then
		flat = airVel
	end
	local speed = flat.Magnitude
	local direction = if speed > 1 then flat.Unit else FlatUnit(r.CFrame.LookVector)
	local airTime = now() - airStart
	Controller.Info.LastLandImpact = impact
	lastGroundTime = now()
	jumpedSinceGround = false
	lastKickNormal = nil
	refreshAir()
	local ground = Sensors.Ground(r)
	local rollPressed = now() - Input.PressedAt("Crouch") <= stats.RollWindow
	local kind = "Soft"
	if impact >= stats.RollMinImpact and rollPressed and has("Roll") then
		Input.Consume("Crouch")
		enterRoll(speed, direction)
		kind = "Roll"
	elseif impact >= stats.HardLandImpact then
		local heavy = impact >= stats.HeavyLandImpact
		enterStumble(heavy)
		kind = if heavy then "Heavy" else "Hard"
	else
		local keep = if impact > stats.SoftLandImpact then stats.SoftLandKeep else 1
		groundSpeed = math.min(speed * keep, stats.MaxSpeed)
		if Input.Held("Crouch") and groundSpeed >= stats.SlideMinSpeed and has("Slide") then
			enterSlide(groundSpeed, direction)
		else
			enterGround(groundSpeed)
		end
	end
	if
		ground
		and kind ~= "Heavy"
		and kind ~= "Hard"
		and airTime >= stats.PrecisionMinAir
		and Sensors.IsNarrow(ground.Part, stats.PrecisionMaxWidth)
	then
		fire("PrecisionLand")
		kind = if kind == "Roll" then kind else "Precision"
	end
	if ground and ground.Part:HasTag(Tags.Balance) and kind ~= "Roll" and state == "Ground" then
		enterBalance(ground.Part)
	end
	Controller.Landed:Fire(impact, kind)
	fire("Land")
end

local function airActions(v: Vector3)
	local r, h = root, humanoid
	if not r or not h then
		return
	end
	-- Jump presses in the air, in priority order.
	if Input.Buffered("Jump", stats.JumpBuffer) then
		local t = now()
		if not jumpedSinceGround and t - lastGroundTime <= stats.CoyoteTime then
			Input.Consume("Jump")
			jump()
			return
		end
		if not wallCoyoteUsed and lastWallNormal and t - lastWallEnd <= stats.WallCoyote and has("WallJump") then
			Input.Consume("Jump")
			wallJump(lastWallNormal, lastWallTangent, math.max(lastWallSpeed, stats.WallRunMinSpeed))
			return
		end
		local move = h.MoveDirection
		local ahead = Sensors.WallAhead(r, lookDirection(), 2.4)
		if
			ahead
			and not wallClimbUsed
			and has("WallRun")
			and move:Dot(-ahead.Normal) > 0.7
			and Flat(v):Dot(-ahead.Normal) >= stats.WallClimbMinSpeed
		then
			Input.Consume("Jump")
			if enterWallClimb(ahead) then
				return
			end
		end
		local near = Sensors.WallNear(r, stats.WallKickReach)
		if near and has("WallJump") then
			local same = lastKickNormal ~= nil
				and near.Normal:Dot(lastKickNormal :: Vector3) > 0.9
				and (near.Position - lastKickPosition).Magnitude < 12
			if not same and Stamina.CanAfford("WallKick") then
				Input.Consume("Jump")
				Stamina.Spend("WallKick")
				local tangential = Flat(v) - near.Normal * Flat(v):Dot(near.Normal)
				lastKickNormal = near.Normal
				lastKickPosition = r.Position
				jumpCut = true
				enterAir(near.Normal * stats.WallKickOut + tangential * 0.5 + UP * stats.WallKickUp)
				fire("WallKick")
				return
			end
		end
		if has("DoubleJump") and not doubleJumpUsed and Stamina.CanAfford("DoubleJump") then
			Input.Consume("Jump")
			Stamina.Spend("DoubleJump")
			doubleJumpUsed = true
			local flat = Flat(v)
			if move.Magnitude > 0.1 then
				-- A double jump can bend your direction a little.
				local speed = flat.Magnitude
				local blended = flat:Lerp(move.Unit * math.max(speed, stats.WalkSpeed), stats.DoubleJumpRedirect)
				flat = if blended.Magnitude > 0.1 then blended.Unit * math.max(speed, blended.Magnitude) else flat
			end
			jumpCut = true
			enterAir(flat + UP * stats.DoubleJumpVelocity)
			fire("DoubleJump")
			return
		end
	end
	if Input.Buffered("Dash", 0.1) then
		if tryDash() then
			Input.Consume("Dash")
			return
		end
	end
	if Input.Buffered("Grapple", 0.15) and Input.Held("Grapple") then
		if tryGrapple() then
			Input.Consume("Grapple")
			return
		end
	end
	-- Automatic grabs: lines, ropes, ledges, climbable surfaces, walls.
	if has("Zipline") and now() - lastZip > stats.ZipRegrab then
		local zip = Sensors.Zipline(r, cache.Ziplines, stats.ZipGrabRange, stats.ZipHang)
		if zip and (zip.Part ~= lastZipPart or now() - lastZip > 1.2) then
			enterZip(zip, v)
			return
		end
	end
	if has("RopeSwing") and now() - lastRope > stats.RopeRegrab then
		local rope = Sensors.Rope(r, cache.Ropes, stats.RopeGrabRange)
		if rope and (rope.Part ~= lastRopePart or now() - lastRope > 1) then
			grabRope(rope)
			return
		end
	end
	if tryLedge(v) then
		return
	end
	if h.MoveDirection.Magnitude > 0.1 and tryClimb(h.MoveDirection) then
		return
	end
	tryWallRun(v)
end

local function stepAir(dt: number, v: Vector3, grounded: boolean)
	local r, h = root, humanoid
	if not r or not h then
		return
	end
	if grounded and v.Y <= 2 then
		land(v)
		return
	end
	local vy = v.Y
	if vy < 0 then
		vy -= stats.Gravity * (stats.FallGravityMultiplier - 1) * dt
	end
	if not jumpCut and vy > 0 and now() - lastJumpTime <= stats.JumpCutWindow and not Input.Held("Jump") then
		vy *= stats.JumpCutMultiplier
		jumpCut = true
	end
	-- Zones.
	local gravityZone = inZone(cache.Gravity, r.Position)
	if gravityZone then
		local scale = gravityZone:GetAttribute("Scale") or 1
		local lift = gravityZone:GetAttribute("Lift") or 0
		local maxRise = gravityZone:GetAttribute("MaxRise") or 40
		vy += stats.Gravity * (1 - scale) * dt
		if lift > 0 then
			vy = math.min(vy + lift * dt, maxRise)
		end
	end
	local wind = inZone(cache.Wind, r.Position)
	if wind then
		local force = wind:GetAttribute("Force")
		local on = Schedule.Cycle(
			Schedule.Now(),
			wind:GetAttribute("Period") or 4,
			wind:GetAttribute("OnFraction") or 0.4,
			wind:GetAttribute("Phase") or 0
		)
		if on and typeof(force) == "Vector3" then
			airVel += Flat(force) * dt
		end
	end
	vy = math.max(vy, -stats.MaxFallSpeed)

	-- Horizontal control (momentum is ours; collisions are respected).
	local flat = Flat(v)
	if airVel.Magnitude > 6 and flat:Dot(airVel.Unit) < airVel.Magnitude * 0.55 then
		airVel = flat
	end
	local move = h.MoveDirection
	local speed = airVel.Magnitude
	if move.Magnitude > 0.1 then
		local wish = move.Unit
		if speed > stats.WalkSpeed + 0.5 then
			local dir = airVel.Unit
			if wish:Dot(dir) < -0.5 then
				speed = math.max(speed - stats.AirBrake * dt, 0)
			else
				dir = MathUtil.RotateToward(dir, wish, stats.AirTurnRate * dt)
			end
			airVel = dir * speed
		else
			airVel += wish * stats.AirAccel * dt
			local cap = math.max(stats.WalkSpeed, speed)
			if airVel.Magnitude > cap then
				airVel = airVel.Unit * cap
			end
		end
	end
	airVel *= (1 - stats.AirDrag * dt)
	if airVel.Magnitude > stats.MaxSpeed then
		airVel = airVel.Unit * stats.MaxSpeed
	end
	r.AssemblyLinearVelocity = airVel + UP * vy
	airActions(r.AssemblyLinearVelocity)
end

local function stepGround(dt: number, v: Vector3, ground: Sensors.Ground?)
	local r, h = root, humanoid
	if not r or not h then
		return
	end
	if not ground or h.FloorMaterial == Enum.Material.Air then
		if now() - lastGroundTime > 0.06 then
			enterAir()
		end
		return
	end
	lastGroundTime = now()
	jumpedSinceGround = false
	if lastKickNormal then
		lastKickNormal = nil
	end
	refreshAir()
	local part = ground.Part

	-- Surfaces with behaviour.
	if part:HasTag(Tags.BouncePad) and now() - lastBounce > 0.4 then
		lastBounce = now()
		local power = part:GetAttribute("Power") or 80
		jumpedSinceGround = true
		lastJumpTime = now()
		jumpCut = true
		h:ChangeState(Enum.HumanoidStateType.Jumping)
		enterAir(Flat(v) + UP * power)
		fire("Bounce")
		return
	end
	if part:HasTag(Tags.Balance) and has("Balance") then
		enterBalance(part)
		return
	end

	local move = h.MoveDirection
	local moving = move.Magnitude > 0.1
	local flat = Flat(v)
	local speed = flat.Magnitude

	if Input.Buffered("Jump", stats.JumpBuffer) then
		Input.Consume("Jump")
		if moving and tryVault(move, math.max(speed, groundSpeed)) then
			return
		end
		-- Running at a wall and jumping into it runs you up it.
		local ahead = if moving then Sensors.WallAhead(r, move, 2.2) else nil
		jump()
		if
			ahead
			and has("WallRun")
			and move:Dot(-ahead.Normal) > 0.75
			and math.max(speed, groundSpeed) >= stats.WallClimbMinSpeed
		then
			enterWallClimb(ahead)
		end
		return
	end
	if moving and Settings.Get("AutoVault") and Controller.Info.Sprinting and speed > 16 then
		if tryVault(move, speed) then
			return
		end
	end
	if crouchHeld() and has("Slide") then
		if math.max(speed, groundSpeed) >= stats.SlideMinSpeed then
			enterSlide(math.max(speed, groundSpeed), if speed > 1 then flat.Unit else FlatUnit(r.CFrame.LookVector))
		else
			setPosture(true)
			setState("Crouch")
		end
		return
	end
	if moving and tryClimb(move) then
		return
	end
	if Input.Buffered("Dash", 0.1) and tryDash() then
		Input.Consume("Dash")
		return
	end
	if Input.Buffered("Grapple", 0.15) and Input.Held("Grapple") and tryGrapple() then
		Input.Consume("Grapple")
		return
	end

	-- Toggle sprint switches itself off once you stop.
	if moving then
		stillSince = now()
	elseif sprintLatched and now() - stillSince > 0.4 then
		sprintLatched = false
	end

	-- Speed: accelerate toward the target, keep extra momentum for a while.
	local target = runTarget(moving)
	if Controller.Info.Sprinting then
		Stamina.Drain("Sprint", dt)
	end
	local rate
	if not moving then
		rate = stats.IdleDecel
	elseif groundSpeed < target then
		rate = stats.GroundAccel
	else
		rate = stats.GroundDecel
	end
	groundSpeed = target + (groundSpeed - target) * math.exp(-rate * dt)
	if not moving then
		groundSpeed = math.max(groundSpeed, 0)
	end
	-- Skids: reversing hard at speed costs momentum.
	if moving and speed > stats.SkidMinSpeed and flat.Unit:Dot(move.Unit) < math.cos(math.rad(stats.SkidAngle)) then
		groundSpeed *= stats.SkidKeep
		fire("Skid")
	end
	h.WalkSpeed = math.max(groundSpeed, 0.1)

	-- Ice keeps your momentum and only slowly follows your steering.
	if part:HasTag(Tags.Ice) or ground.Material == Enum.Material.Ice or ground.Material == Enum.Material.Glacier then
		local wish = if moving then move.Unit * math.max(groundSpeed, stats.WalkSpeed) else Vector3.zero
		local slide = flat:Lerp(wish, 1 - math.exp(-1.1 * dt))
		local n = ground.Normal
		local g = Vector3.new(0, -stats.Gravity, 0)
		slide += Flat(g - n * g:Dot(n)) * 0.55 * dt
		if slide.Magnitude > stats.MaxSpeed then
			slide = slide.Unit * stats.MaxSpeed
		end
		groundSpeed = slide.Magnitude
		r.AssemblyLinearVelocity = slide + UP * v.Y
		h.WalkSpeed = math.max(groundSpeed, 0.1)
	end

	-- Ground wind pushes you sideways a little.
	local wind = inZone(cache.Wind, r.Position)
	if wind then
		local force = wind:GetAttribute("Force")
		local on = Schedule.Cycle(
			Schedule.Now(),
			wind:GetAttribute("Period") or 4,
			wind:GetAttribute("OnFraction") or 0.4,
			wind:GetAttribute("Phase") or 0
		)
		if on and typeof(force) == "Vector3" then
			r.AssemblyLinearVelocity += Flat(force) * dt * 0.6
		end
	end
end

local function stepCrouch(dt: number, v: Vector3, ground: Sensors.Ground?)
	local r, h = root, humanoid
	if not r or not h then
		return
	end
	if not ground then
		enterAir()
		return
	end
	lastGroundTime = now()
	local headroom = Sensors.Headroom(r)
	local held = crouchHeld()
	if Input.Buffered("Jump", stats.JumpBuffer) and headroom then
		Input.Consume("Jump")
		setPosture(false)
		jump()
		return
	end
	if not held and headroom then
		enterGround(groundSpeed)
		return
	end
	local speed = Flat(v).Magnitude
	if held and speed >= stats.SlideMinSpeed + 4 then
		enterSlide(speed, Flat(v).Unit)
		return
	end
	groundSpeed = MathUtil.Damp(groundSpeed, stats.CrouchSpeed, 10, dt)
	h.WalkSpeed = groundSpeed
end

local function stepSlide(dt: number, v: Vector3, ground: Sensors.Ground?)
	local r, h = root, humanoid
	if not r or not h then
		return
	end
	local headroom = Sensors.Headroom(r)
	if Input.Buffered("Jump", stats.JumpBuffer) and headroom then
		Input.Consume("Jump")
		if tryVault(slideDir, slideSpeed) then
			setPosture(false)
			return
		end
		local speed = math.min(slideSpeed * stats.SlideJumpBoost, stats.MaxSpeed)
		setPosture(false)
		jumpedSinceGround = true
		lastJumpTime = now()
		jumpCut = false
		h:ChangeState(Enum.HumanoidStateType.Jumping)
		enterAir(slideDir * speed + UP * stats.JumpVelocity)
		fire("SlideJump")
		return
	end
	if not ground then
		slideAirTime += dt
		if slideAirTime > stats.SlideGrace then
			enterAir(slideDir * slideSpeed + UP * v.Y)
			return
		end
	else
		slideAirTime = 0
		lastGroundTime = now()
		-- Slopes speed you up downhill.
		local n = ground.Normal
		local g = Vector3.new(0, -stats.Gravity, 0)
		local downhill = Flat(g - n * g:Dot(n))
		slideSpeed += downhill:Dot(slideDir) * stats.SlideSlopeAccel * dt
	end
	local move = h.MoveDirection
	if move.Magnitude > 0.1 and move:Dot(slideDir) > -0.3 then
		slideDir = MathUtil.RotateToward(slideDir, move.Unit, stats.SlideSteer * dt)
	end
	slideSpeed = math.min(slideSpeed - stats.SlideFriction * dt, stats.MaxSpeed)
	local released = not crouchHeld()
	if slideSpeed < stats.SlideEndSpeed or (released and headroom and now() - stateStart > 0.25) then
		if headroom and released then
			enterGround(math.max(slideSpeed, stats.WalkSpeed * 0.6))
		else
			groundSpeed = math.max(slideSpeed, stats.CrouchSpeed)
			setState("Crouch")
		end
		return
	end
	h.WalkSpeed = slideSpeed
	r.AssemblyLinearVelocity = slideDir * slideSpeed + UP * v.Y
end

local function stepRoll(_: number, v: Vector3, ground: Sensors.Ground?)
	local r, h = root, humanoid
	if not r or not h then
		return
	end
	if now() >= rollUntil then
		local headroom = Sensors.Headroom(r)
		if Input.Held("Crouch") and rollSpeed >= stats.SlideMinSpeed and has("Slide") then
			enterSlide(rollSpeed, rollDir)
		elseif headroom then
			enterGround(rollSpeed)
		else
			groundSpeed = stats.CrouchSpeed
			setState("Crouch")
		end
		return
	end
	if not ground then
		enterAir(rollDir * rollSpeed + UP * v.Y)
		return
	end
	if Input.Buffered("Jump", stats.JumpBuffer) and now() - stateStart > 0.15 and Sensors.Headroom(r) then
		Input.Consume("Jump")
		groundSpeed = rollSpeed
		setPosture(false)
		jump()
		return
	end
	h.WalkSpeed = rollSpeed
	r.AssemblyLinearVelocity = rollDir * rollSpeed + UP * v.Y
end

local function stepStumble(_: number, _v: Vector3, ground: Sensors.Ground?)
	local r, h = root, humanoid
	if not r or not h then
		return
	end
	-- A late roll press still saves you.
	if Input.PressedAt("Crouch") > stumbleLand and now() - stumbleLand <= stats.RollLateWindow and has("Roll") then
		Input.Consume("Crouch")
		enterRoll(math.max(Flat(airVel).Magnitude, stats.WalkSpeed), FlatUnit(airVel, FlatUnit(r.CFrame.LookVector)))
		return
	end
	if not ground then
		enterAir()
		return
	end
	h.WalkSpeed = stats.StumbleSpeed
	if now() >= stumbleUntil then
		enterGround(stats.StumbleSpeed)
	end
end

-- Facing -------------------------------------------------------------------------------------------------

local function updateFacing()
	local h, r, align = humanoid, root, facing
	if not h or not r or not align then
		return
	end
	local direction: Vector3? = nil
	if state == "WallRun" then
		direction = wallTangent
	elseif state == "Slide" then
		direction = slideDir
	elseif state == "Roll" then
		direction = rollDir
	elseif state == "Dash" then
		direction = dashDir
	elseif state == "WallClimb" then
		direction = -wallNormal
	elseif state == "Air" then
		local flat = Flat(r.AssemblyLinearVelocity)
		if flat.Magnitude > stats.WalkSpeed * 0.8 then
			direction = flat.Unit
		end
	end
	if direction and not Body.IsHolding() then
		h.AutoRotate = false
		align.Enabled = true
		align.CFrame = CFrame.lookAt(Vector3.zero, direction)
	else
		if not Body.IsHolding() then
			h.AutoRotate = true
		end
		align.Enabled = false
	end
end

-- Main loop ----------------------------------------------------------------------------------------------

local function replicate()
	local aux: Vector3? = nil
	local auxNumber: number? = nil
	if state == "WallRun" or state == "WallClimb" then
		aux = wallNormal
	elseif state == "Ledge" then
		aux = ledgeNormal
	elseif state == "Climb" then
		aux = climbNormal
	elseif state == "Swing" then
		aux = Swing.Anchor()
	elseif state == "Pull" then
		aux = pullTarget
	elseif state == "Zipline" then
		aux = zipDir
	elseif state == "Balance" then
		aux = balanceAxis
		auxNumber = math.floor(sway * 20) / 20
	end
	Controller.Info.Aux = aux or Controller.Info.Aux
	local t = now()
	local changed = state ~= lastSent.State
	local auxChanged = (aux and lastSent.Aux and (aux - lastSent.Aux).Magnitude > 0.5)
		or ((aux == nil) ~= (lastSent.Aux == nil))
	if changed or (auxChanged and t - lastSent.Time > 0.25) or (state == "Balance" and t - lastSent.Time > 0.3) then
		lastSent.State = state
		lastSent.Aux = aux
		lastSent.Time = t
		Net.Send("Move.State", state, aux, auxNumber)
	end
end

local function onHeartbeat(dt: number)
	local r, h = root, humanoid
	if not r or not h or h.Health <= 0 or not r.Parent then
		return
	end
	dt = math.min(dt, 1 / 20)
	if now() - cache.Refreshed > 1.5 then
		refreshCache()
	end

	local v = r.AssemblyLinearVelocity
	local holding = Body.IsHolding() or Swing.IsAttached()
	local ground = if holding then nil else Sensors.Ground(r)
	local grounded = ground ~= nil and h.FloorMaterial ~= Enum.Material.Air
	Controller.Info.Grounded = grounded
	Controller.Info.Floor = if ground then ground.Part else nil
	Controller.Info.FloorMaterial = if ground then ground.Material else Enum.Material.Air
	lastFloor = if ground then ground.Part else nil

	if not Controller.Enabled then
		-- Menus open: stand still, keep gravity.
		if state ~= "Ground" and state ~= "Air" and not holding then
			enterAir()
		end
		h.WalkSpeed = 0
	end

	-- Steam vents launch you when active.
	local vent = inZone(cache.Vents, r.Position)
	if vent and now() - lastBounce > 0.5 then
		local on = Schedule.Cycle(
			Schedule.Now(),
			vent:GetAttribute("Period") or 3.4,
			vent:GetAttribute("OnFraction") or 0.38,
			vent:GetAttribute("Phase") or 0
		)
		if on and not holding then
			lastBounce = now()
			jumpedSinceGround = true
			jumpCut = true
			h:ChangeState(Enum.HumanoidStateType.Jumping)
			enterAir(Flat(v) + UP * (vent:GetAttribute("Power") or 80))
			fire("Launch")
		end
	end

	if state == "Ground" then
		stepGround(dt, v, ground)
	elseif state == "Air" then
		stepAir(dt, v, grounded)
	elseif state == "Crouch" then
		stepCrouch(dt, v, ground)
	elseif state == "Slide" then
		stepSlide(dt, v, ground)
	elseif state == "Roll" then
		stepRoll(dt, v, ground)
	elseif state == "Stumble" then
		stepStumble(dt, v, ground)
	elseif state == "WallRun" then
		stepWallRun(dt)
	elseif state == "WallClimb" then
		stepWallClimb(dt)
	elseif state == "Ledge" then
		stepLedge(dt)
	elseif state == "Climb" then
		stepClimb(dt)
	elseif state == "Balance" then
		stepBalance(dt, ground)
	elseif state == "Zipline" then
		stepZip(dt)
	elseif state == "Swing" then
		stepSwing(dt)
	elseif state == "Dash" then
		stepDash()
	elseif state == "Vault" or state == "Mantle" or state == "Pull" then
		if Body.StepPath(dt) then
			if state == "Pull" then
				Swing.ShowLine(nil)
				pullTarget = nil
			end
			finishPath()
		end
	end

	-- Stamina regenerates on the ground, slowly in the air, never while holding on.
	local staminaMode = "Air"
	if state == "Ground" or state == "Crouch" or state == "Roll" or state == "Stumble" or state == "Balance" then
		staminaMode = if Controller.Info.Sprinting and state == "Ground" then "None" else "Ground"
	elseif state == "Ledge" or state == "Climb" or state == "WallRun" or state == "WallClimb" then
		staminaMode = "None"
	end
	Stamina.Update(dt, staminaMode)

	updateFacing()

	-- Grapple targeting (a few times a second).
	if has("Grapple") and now() - grappleScan > 0.08 then
		grappleScan = now()
		local list = cache.Anchors
		if has("GrapplePull") and #cache.Pulls > 0 then
			list = table.clone(cache.Anchors)
			for _, part in cache.Pulls do
				table.insert(list, part)
			end
		end
		Controller.Info.GrappleTarget =
			Sensors.Anchor(r, list, workspace.CurrentCamera.CFrame.LookVector, stats.GrappleRange, stats.GrappleCone)
	elseif not has("Grapple") then
		Controller.Info.GrappleTarget = nil
	end

	local finalVelocity = r.AssemblyLinearVelocity
	lastVy = finalVelocity.Y
	Controller.Info.Velocity = finalVelocity
	Controller.Info.Speed = Flat(finalVelocity).Magnitude
	Controller.Info.AirTime = if state == "Air" then now() - airStart else 0
	Controller.Info.DoubleJumpReady = has("DoubleJump") and not doubleJumpUsed
	Controller.Info.DashCharges = if has("Dash") then dashCharges else 0
	Controller.Info.DashReady = if has("Dash") then math.clamp((now() - lastDash) / stats.DashCooldown, 0, 1) else 0
	Controller.Info.PathKind = Body.PathKind()
	Controller.Info.PathAlpha = Body.PathAlpha()
	if state ~= "Balance" then
		Controller.Info.Sway = MathUtil.Damp(Controller.Info.Sway, 0, 6, dt)
	end
	replicate()

	-- Out of the world?
	local position = r.Position
	if (Controller.KillCheck and Controller.KillCheck(position)) or inZone(cache.Kill, position) then
		Controller.Fell:Fire("Fall")
	end
end

-- Platform carry, called by the mechanism system right after it moves parts.
function Controller.Carry(part: BasePart, delta: CFrame, dt: number)
	local r = root
	if not r then
		return
	end
	-- Climbing a moving surface: the hold point rides along with it.
	if state == "Climb" and climbPart == part then
		climbPosition = delta * climbPosition
		return
	end
	if Body.IsHolding() or Swing.IsAttached() then
		return
	end
	if lastFloor ~= part then
		return
	end
	if state == "Air" or state == "WallRun" or state == "Dash" then
		return
	end
	local before = r.Position
	r.CFrame = delta * r.CFrame
	platformVelocity = (r.Position - before) / math.max(dt, 1e-3)
end

function Controller.PlatformCheck()
	-- Called once per frame before carry; decays inherited platform velocity.
	platformVelocity *= 0.85
end

-- Public control -------------------------------------------------------------------------------------------

function Controller.State(): string
	return state
end

-- Movement is frozen while any lock is held (menus, dialogue, countdowns...),
-- so one system can never undo another's freeze.
local locks: { [string]: boolean } = {}

local function applyLocks()
	local enabled = next(locks) == nil
	if enabled == Controller.Enabled then
		return
	end
	Controller.Enabled = enabled
	Input.GameplayEnabled = enabled
	if not enabled then
		Input.ReleaseAll()
		if Swing.IsAttached() then
			releaseSwing(false)
		end
	end
end

function Controller.SetLock(name: string, locked: boolean)
	if locked then
		locks[name] = true
	else
		locks[name] = nil
	end
	applyLocks()
end

function Controller.SetEnabled(enabled: boolean)
	Controller.SetLock("Default", not enabled)
end

-- Recompute effective stats (skills, ranked standardization, practice assists).
function Controller.ApplyStats()
	local profile = State.Profile
	local newStats, perks = MoveStats.Compute(if profile then profile.Skills else nil, mode.Standardized, mode.Assists)
	stats = newStats
	Controller.Stats = newStats
	Controller.Perks = perks
	Stamina.SetStats(newStats)
	abilities = State.Abilities()
	for id, on in mode.Extra or {} do
		if on then
			abilities[id] = true
		end
	end
	if humanoid then
		humanoid.JumpPower = newStats.JumpVelocity
	end
end

function Controller.SetMode(standardized: boolean, assists: { [string]: boolean }?)
	mode.Standardized = standardized
	mode.Assists = assists or {}
	Controller.ApplyStats()
end

function Controller.Mode(): { Standardized: boolean, Assists: { [string]: boolean }, Extra: { [string]: boolean }? }
	return mode
end

-- Abilities lent by the server for a mode (see ProgressionService.SetTemporary).
function Controller.SetExtraAbilities(set: { [string]: boolean }?)
	mode.Extra = set
	Controller.ApplyStats()
end

function Controller.Has(ability: string): boolean
	return has(ability)
end

-- Instantly move the character (checkpoint retries, travel, course starts).
function Controller.Teleport(cframe: CFrame, keepVelocity: boolean?)
	local r, h = root, humanoid
	if not r or not h then
		return
	end
	if Swing.IsAttached() then
		Swing.Detach(false)
	end
	Body.EndHold()
	Body.SetGroup(Tags.Groups.Players)
	ledge, climbPart, zipPart, balancePart, pullTarget = nil, nil, nil, nil, nil
	Swing.ShowLine(nil)
	r.CFrame = cframe
	r.AssemblyAngularVelocity = Vector3.zero
	if not keepVelocity then
		r.AssemblyLinearVelocity = Vector3.zero
		airVel = Vector3.zero
		groundSpeed = 0
	end
	platformVelocity = Vector3.zero
	lastVy = 0
	refreshAir()
	Stamina.Refill()
	h:ChangeState(Enum.HumanoidStateType.Freefall)
	setPosture(false)
	setState("Air")
	airStart = now()
	refreshCache()
	Controller.Teleported:Fire(cframe)
end

-- Knock the character into the air (sweeper arms, gusts). Lets go of anything held.
function Controller.Impulse(velocity: Vector3, reason: string?)
	local r, h = root, humanoid
	if not r or not h or h.Health <= 0 then
		return
	end
	if Swing.IsAttached() then
		Swing.Detach(false)
		Swing.ShowLine(nil)
	end
	if Body.IsHolding() then
		Body.EndHold()
	end
	Body.SetGroup(Tags.Groups.Players)
	ledge, climbPart, zipPart, balancePart, pullTarget = nil, nil, nil, nil, nil
	jumpedSinceGround = true
	jumpCut = true
	h:ChangeState(Enum.HumanoidStateType.Freefall)
	enterAir(velocity)
	fire(reason or "Knocked")
end

local function onCharacterAdded(newCharacter: Model)
	local h = newCharacter:WaitForChild("Humanoid") :: Humanoid
	local r = newCharacter:WaitForChild("HumanoidRootPart") :: BasePart
	newCharacter:WaitForChild("Torso", 5)
	humanoid, root = h, r
	Sensors.SetIgnore({ newCharacter, workspace.CurrentCamera })
	Body.Attach(newCharacter)
	Swing.SetCharacter(newCharacter)

	h.UseJumpPower = true
	h.JumpPower = stats.JumpVelocity
	h.WalkSpeed = stats.WalkSpeed
	h.AutoJumpEnabled = false
	for _, stateType in
		{
			Enum.HumanoidStateType.FallingDown,
			Enum.HumanoidStateType.Ragdoll,
			Enum.HumanoidStateType.Climbing,
			Enum.HumanoidStateType.Swimming,
		}
	do
		h:SetStateEnabled(stateType, false)
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "FacingAttachment"
	attachment.Parent = r
	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.Responsiveness = 30
	align.MaxTorque = math.huge
	align.Enabled = false
	align.Parent = r
	facing = align

	groundSpeed, airVel = 0, Vector3.zero
	refreshAir()
	Stamina.Refill()
	state = "Air"
	setState("Ground")
	Controller.Info.Character = newCharacter
	Controller.Info.Humanoid = h
	Controller.Info.Root = r
	refreshCache()
	h.Died:Connect(function()
		Swing.SetCharacter(nil)
	end)
end

function Controller.Start()
	Net.Listen("Abilities.Temp", function(set)
		Controller.SetExtraAbilities(if type(set) == "table" then set else nil)
	end)
	Input.Pressed:Connect(function(action)
		if action == "Sprint" and Settings.Get("SprintMode") == "Toggle" then
			sprintLatched = not sprintLatched
			stillSince = now()
		elseif action == "Crouch" and Settings.Get("CrouchToggle") then
			if state == "Ground" or state == "Crouch" or state == "Slide" then
				crouchLatched = not crouchLatched
			end
		end
	end)
	Controller.ApplyStats()
	State.On("Skills", function()
		Controller.ApplyStats()
	end)
	State.On("XP", function()
		Controller.ApplyStats()
	end)
	RunService.Heartbeat:Connect(onHeartbeat)
	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end
end

return Controller

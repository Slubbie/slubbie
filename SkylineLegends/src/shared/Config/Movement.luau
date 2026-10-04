-- Standard movement attributes.
--
-- These are the exact values used in ranked runs, races and leaderboards. Skill
-- tree perks (Config/SkillTree) and practice assists modify a copy of this table
-- through Logic/MoveStats; nothing else should read or change it directly.
--
-- Units: studs, seconds. Root height above the floor is 3 studs (R6).

local Movement = {
	-- World -------------------------------------------------------------------
	Gravity = 180, -- workspace.Gravity (set by the server on start)
	FallGravityMultiplier = 1.3, -- extra gravity while falling: crisp, readable arcs
	MaxFallSpeed = 170,
	RootHeight = 3,

	-- Ground ------------------------------------------------------------------
	WalkSpeed = 18, -- default running pace
	SprintSpeed = 28,
	CrouchSpeed = 8,
	GroundAccel = 7.5, -- exponential rate toward target speed while speeding up
	GroundDecel = 4.5, -- rate while carrying extra momentum (landings, slides)
	IdleDecel = 16, -- rate when there's no input
	MaxSpeed = 72, -- hard cap on any horizontal speed
	SkidAngle = 115, -- degrees; reversing harder than this at speed skids
	SkidMinSpeed = 24,
	SkidKeep = 0.5,

	-- Jumping -----------------------------------------------------------------
	JumpVelocity = 54,
	JumpCutMultiplier = 0.55, -- let go of jump early for a short hop
	JumpCutWindow = 0.2,
	JumpBuffer = 0.12, -- a press this early still jumps on landing
	CoyoteTime = 0.1, -- you can still jump this long after leaving a ledge
	AirAccel = 34,
	AirTurnRate = 2.4, -- radians/second of steering above running speed
	AirBrake = 26,
	AirDrag = 0.05,
	DoubleJumpVelocity = 47,
	DoubleJumpRedirect = 0.45, -- how much a double jump can bend your direction (0..1)

	-- Landing -----------------------------------------------------------------
	RollWindow = 0.3, -- press crouch up to this long before touchdown
	RollLateWindow = 0.08, -- ...or this long after
	RollMinImpact = 40,
	RollDuration = 0.42,
	RollBoost = 1.04,
	SoftLandImpact = 50,
	HardLandImpact = 82,
	HeavyLandImpact = 125,
	SoftLandKeep = 0.9,
	StumbleTime = 0.42,
	HeavyStumbleTime = 0.8,
	StumbleSpeed = 6,
	PrecisionMaxWidth = 3.2, -- landing on anything this narrow counts as precise
	PrecisionMinAir = 0.45,

	-- Slide -------------------------------------------------------------------
	SlideMinSpeed = 15,
	SlideBoost = 7,
	SlideBoostCooldown = 1.2,
	SlideFriction = 11,
	SlideSlopeAccel = 0.75,
	SlideSteer = 1.6,
	SlideEndSpeed = 9,
	SlideJumpBoost = 1.06,
	SlideGrace = 0.18, -- airtime allowed before a slide becomes a fall

	-- Vault and mantle --------------------------------------------------------
	VaultMinHeight = 1.2,
	VaultMaxHeight = 4.6,
	VaultMaxDepth = 5.5,
	VaultReach = 3.2,
	VaultDuration = 0.3,
	VaultExitMin = 22,
	VaultExitBoost = 1.05,
	MantleDuration = 0.36,
	LowMantleDuration = 0.24,

	-- Ledges ------------------------------------------------------------------
	LedgeReach = 2.4,
	LedgeMinAbove = -0.8, -- ledge top relative to the root
	LedgeMaxAbove = 2.8,
	LedgeMaxRiseSpeed = 24,
	LedgeHangDrop = 2.6, -- root sits this far below the ledge top while hanging
	LedgeWallGap = 1.15,
	ShimmySpeed = 6.5,
	LedgeRegrabDelay = 0.35,
	LedgeLeapHeight = 7.5,
	LedgeJumpOut = 26,
	LedgeJumpUp = 44,

	-- Climbing ----------------------------------------------------------------
	ClimbUpSpeed = 9,
	ClimbSideSpeed = 7,
	ClimbDownSpeed = 13,
	ClimbHop = 6.5,
	ClimbReach = 2.3,

	-- Wall running ------------------------------------------------------------
	WallRunMinSpeed = 17,
	WallRunSpeed = 26,
	WallRunMaxTime = 1.45,
	WallRunStartLift = 11,
	WallRunGravity = 18, -- grows to WallRunGravityEnd over the run
	WallRunGravityEnd = 70,
	WallRunCheck = 2.6,
	WallRunMinHeight = 2.4,
	WallRunSameWallCooldown = 0.6,
	WallJumpOut = 27,
	WallJumpUp = 47,
	WallJumpKeep = 0.9,
	WallKickOut = 30,
	WallKickUp = 46,
	WallKickReach = 2.5,
	WallClimbSpeed = 30,
	WallClimbTime = 0.55,
	WallClimbGravity = 42,
	WallClimbMinSpeed = 8,
	WallCoyote = 0.14,

	-- Dash --------------------------------------------------------------------
	DashSpeed = 54,
	DashTime = 0.16,
	DashCooldown = 0.55,
	DashCharges = 1,
	DashLift = 6,

	-- Grapple -----------------------------------------------------------------
	GrappleRange = 90,
	GrappleCone = 42, -- degrees from the camera's view direction
	GrappleMinLength = 8,
	GrappleReel = 9,
	GrappleFastReel = 40,
	GrappleSwingAccel = 52,
	GrapplePull = 16,
	GrappleReleaseBoost = 1.08,
	GrappleReleasePop = 12,
	GrappleMaxSpeed = 95,
	GrappleCooldown = 0.35,
	PullSpeed = 78,
	PullPopUp = 42,
	PullPopForward = 24,

	-- Rope swings -------------------------------------------------------------
	RopeGrabRange = 3.4,
	RopeReleaseBoost = 1.1,
	RopeReleasePop = 20,
	RopeRegrab = 0.5,
	RopePump = 46,

	-- Ziplines ----------------------------------------------------------------
	ZipGrabRange = 3.8,
	ZipHang = 3.1,
	ZipMinSpeed = 18,
	ZipMaxSpeed = 64,
	ZipSlopeAccel = 0.75,
	ZipFlatSpeed = 26,
	ZipJumpUp = 34,
	ZipRegrab = 0.5,

	-- Balance -----------------------------------------------------------------
	BalanceSpeed = 12,
	BalanceSway = 1.25, -- how strongly the beam pushes you off balance
	BalanceCorrect = 3.4, -- how strongly steering corrects it
	BalanceDamping = 2.6,
	BalanceWind = 0.035,

	-- Stamina -----------------------------------------------------------------
	StaminaMax = 100,
	StaminaRegenGround = 34,
	StaminaRegenAir = 10,
	StaminaRegenDelay = 0.65,
	StaminaExhaustedUntil = 25, -- sprint is locked until stamina refills this far
	Costs = {
		Sprint = 5, -- per second
		WallRun = 16, -- per second
		Climb = 9, -- per second while moving
		ClimbIdle = 4,
		Hang = 5,
		DoubleJump = 15,
		Dash = 20,
		WallJump = 8,
		WallKick = 10,
		WallClimb = 12,
		Grapple = 8,
		Pull = 10,
		LedgeLeap = 12,
		ClimbHop = 10,
	},
}

return Movement

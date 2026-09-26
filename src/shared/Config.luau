-- Every number that shapes how SKYBOUND feels lives here.
-- Speeds are studs/second, accelerations studs/second², times seconds, angles degrees.
-- Tune these first: the game feel is almost entirely in this file.

local Config = {}

Config.Movement = {
	WalkSpeed = 22,
	JumpPower = 55,
	-- Hard cap on horizontal speed from any source.
	MaxSpeed = 170,
	-- Extra ground speed (above WalkSpeed) bleeds off exponentially at this rate.
	GroundFriction = 1.4,
	-- Same, when no movement key is held.
	IdleFriction = 8,
	-- Fraction of air speed lost per second. Keep tiny so swings carry.
	AirDrag = 0.04,
	-- How fast air velocity turns toward your input, in radians/second.
	AirSteer = 2.4,
	-- Speed lost per second when holding the opposite direction in the air.
	AirBrake = 45,
	-- If physics cuts air speed below this fraction in one step, we hit something: accept it.
	CollisionSpeedLoss = 0.6,
	-- Jump presses are remembered this long, so early presses still count.
	JumpBuffer = 0.15,
	-- Landing faster than this (vertical) shakes the camera and squashes the body.
	HardLandingSpeed = 75,
}

Config.Grapple = {
	Range = 200,
	-- If the exact crosshair ray misses, a sphere this wide is swept to be forgiving.
	AimAssistRadius = 4,
	-- How fast the hook flies out.
	HookSpeed = 1100,
	RetractTime = 0.12,
	-- Constant pull toward the anchor while attached.
	PullAccel = 38,
	-- The rope shortens by this much per second while attached.
	ReelSpeed = 14,
	MinLength = 10,
	-- Push from movement keys while swinging (perpendicular to the rope).
	SwingAccel = 50,
	-- How hard a stretched rope snaps back.
	Stiffness = 9,
	-- Horizontal speed multiplier and upward pop applied when you let go.
	ReleaseBoost = 1.1,
	ReleasePop = 20,
	Cooldown = 0.2,
	MaxSpeed = 170,
	RopeColor = Color3.fromRGB(120, 230, 255),
	RopeWobble = 2.5,
}

Config.WallRun = {
	MinSpeed = 28,
	-- How far from the character's centre a wall is detected.
	CheckDistance = 3.2,
	MaxDuration = 1.8,
	-- Downward acceleration while wall-running (ramps up the longer you run).
	Gravity = 22,
	-- Small upward lift when you first touch the wall.
	EntryLift = 6,
	EntryBoost = 1.05,
	Friction = 6,
	-- Velocity pushing into the wall so you stay on it.
	Stick = 4,
	JumpOut = 42,
	JumpUp = 50,
	JumpSpeedKeep = 1.05,
	-- You can still wall-jump this long after leaving the wall.
	CoyoteTime = 0.15,
	-- You can't immediately re-run the same wall you just left.
	SameWallCooldown = 0.6,
}

Config.Slide = {
	MinSpeed = 26,
	-- Speed bonus when a slide starts. Only granted once per BoostCooldown so it can't be spammed.
	Boost = 10,
	BoostCooldown = 1.2,
	Friction = 14,
	-- How much slopes speed you up (downhill) or slow you down (uphill). 1 = full gravity.
	SlopeFactor = 0.9,
	Steer = 1.2,
	EndSpeed = 14,
	JumpBoost = 1.08,
}

Config.Dash = {
	Speed = 38,
	Lift = 10,
	-- Charges refill when you land, touch a wall, or attach a grapple.
	Charges = 1,
	Cooldown = 0.35,
}

Config.Camera = {
	BaseFOV = 70,
	MaxFOV = 98,
	FOVSpeedMin = 30,
	FOVSpeedMax = 150,
	ShoulderOffset = Vector3.new(1.8, 0.6, 0),
	WallRunRoll = 11,
	SwingRoll = 9,
	ShakeAngle = 2.5,
	SpeedLinesStart = 60,
	SpeedLinesFull = 140,
	SpeedLineCount = 28,
}

Config.World = {
	Seed = 1337,
	IslandCount = 42,
	WorldRadius = 1000,
	ShardRespawnTime = 25,
	KillHeight = -150,
}

return Config

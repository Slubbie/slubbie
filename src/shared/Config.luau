-- Every number that shapes how SKYBOUND feels lives here.
-- Speeds are studs/second, accelerations studs/second², times seconds, angles degrees.
-- Tune these first: the game feel is almost entirely in this file.

local Config = {}

Config.Movement = {
	WalkSpeed = 22,
	-- Holding sprint (Shift) runs at this speed. Fast enough to slide from.
	SprintSpeed = 34,
	-- How quickly you reach sprint speed from a walk.
	SprintAccel = 6,
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
	-- The rope starts this much longer than the distance, so it catches you softly.
	CatchSlack = 1.04,
	-- Gentle constant pull toward the anchor while attached.
	PullAccel = 22,
	-- The rope reels in at this speed; hold jump for the fast reel.
	ReelSpeed = 12,
	FastReelSpeed = 55,
	MinLength = 10,
	-- Push from movement keys while swinging (perpendicular to the rope).
	SwingAccel = 55,
	-- Horizontal speed multiplier and upward pop applied when you let go.
	ReleaseBoost = 1.1,
	ReleasePop = 18,
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
	-- Fall below this and you respawn. Set as Workspace.FallenPartsDestroyHeight
	-- in default.project.json (scripts can't change it at runtime).
	KillHeight = -150,
}

Config.Animation = {
	-- How quickly joints blend toward their target pose. Higher = snappier.
	Smoothing = 16,
	-- Above this ground speed the arms sweep back into a ninja run.
	NinjaRunSpeed = 45,
	-- Above this air speed you dive forward superman-style.
	SupermanSpeed = 70,
	FlipTime = 0.45,
	RollTime = 0.5,
	-- Landing faster than this (vertical) while moving turns into a forward roll.
	RollImpactSpeed = 95,
}

Config.Combo = {
	-- Seconds you can stand on the ground before your combo is banked.
	GroundGrace = 0.4,
	MinScoreToBank = 4,
	MaxScore = 200,
	-- Jumping within this long after landing counts as a bunny hop.
	BunnyHopWindow = 0.2,
	BunnyHopMinSpeed = 35,
	-- Letting go of the grapple faster than this is a slingshot.
	SlingshotSpeed = 95,
	Points = {
		Grapple = 1,
		WallRun = 1,
		WallJump = 2,
		Dash = 1,
		Launch = 1,
		Slingshot = 3,
		BunnyHop = 2,
		SlideJump = 2,
	},
	Names = {
		Grapple = "HOOK",
		WallRun = "WALL RUN",
		WallJump = "WALL JUMP",
		Dash = "DASH",
		Launch = "LAUNCH",
		Slingshot = "SLINGSHOT!",
		BunnyHop = "BUNNY HOP",
		SlideJump = "SLIDE JUMP",
	},
}

-- Shards earned for banking a combo worth `score` points.
function Config.ComboReward(score: number): number
	return math.floor(score ^ 1.3 / 2)
end

Config.Trials = {
	RingRadius = 11,
	-- Give up on a run after this many seconds.
	Timeout = 300,
	Courses = {
		{ Id = "warmup", Name = "Warm-Up", Hops = 4, Color = Color3.fromRGB(120, 255, 170) },
		{ Id = "skyloop", Name = "Sky Loop", Hops = 7, Color = Color3.fromRGB(255, 170, 60) },
		{ Id = "summit", Name = "Summit Rush", Hops = 10, Color = Color3.fromRGB(255, 80, 120) },
	},
}

Config.Shop = {
	-- Rope and trail colours. Cosmetic only: nothing in the shop changes how you move.
	Items = {
		{ Id = "sky", Name = "Sky", Price = 0, Color = Color3.fromRGB(120, 230, 255) },
		{ Id = "bubblegum", Name = "Bubblegum", Price = 25, Color = Color3.fromRGB(255, 120, 210) },
		{ Id = "solar", Name = "Solar", Price = 60, Color = Color3.fromRGB(255, 205, 70) },
		{ Id = "toxic", Name = "Toxic", Price = 100, Color = Color3.fromRGB(150, 255, 80) },
		{ Id = "crimson", Name = "Crimson", Price = 150, Color = Color3.fromRGB(255, 60, 70) },
		{ Id = "void", Name = "Void", Price = 250, Color = Color3.fromRGB(140, 70, 255) },
		{ Id = "prism", Name = "Prism", Price = 500, Color = Color3.fromRGB(255, 255, 255), Rainbow = true },
	},
	Default = "sky",
}

function Config.GetShopItem(id: string?)
	for _, item in Config.Shop.Items do
		if item.Id == id then
			return item
		end
	end
	return nil
end

-- Built-in engine sounds so everything works out of the box.
-- Swap any of these for your own uploads ("rbxassetid://123...").
Config.Sounds = {
	Wind = "rbxasset://sounds/action_falling.mp3",
	Footsteps = "rbxasset://sounds/action_footsteps_plastic.mp3",
	Whoosh = "rbxasset://sounds/swoosh.wav",
	Jump = "rbxasset://sounds/action_jump.mp3",
	Land = "rbxasset://sounds/action_jump_land.mp3",
	Ping = "rbxasset://sounds/electronicpingshort.wav",
}

Config.RespawnTime = 2
-- Respawn where you last landed instead of back at the spawn plaza.
Config.RespawnAtLastLanding = true

Config.Progression = {
	-- XP rewards.
	XP = {
		Move = 2, -- per trick (grapple, wall jump...)
		Shard = 5,
		ComboPerPoint = 2,
		TrialFinish = 50,
		TrialRecord = 50,
	},
	-- Level titles, shown on nametags.
	Titles = {
		{ Level = 1, Title = "Drifter" },
		{ Level = 5, Title = "Glider" },
		{ Level = 10, Title = "Skyrunner" },
		{ Level = 20, Title = "Stormchaser" },
		{ Level = 35, Title = "Cloudbreaker" },
		{ Level = 50, Title = "Sky Legend" },
	},
	-- Shards granted per level on level up.
	ShardsPerLevel = 5,
}

-- Total XP needed to reach `level`.
function Config.XPForLevel(level: number): number
	return math.floor(100 * (level - 1) ^ 1.6)
end

function Config.LevelForXP(xp: number): number
	local level = 1
	while Config.XPForLevel(level + 1) <= xp do
		level += 1
	end
	return level
end

function Config.TitleForLevel(level: number): string
	local title = Config.Progression.Titles[1].Title
	for _, entry in Config.Progression.Titles do
		if level >= entry.Level then
			title = entry.Title
		end
	end
	return title
end

-- Daily quests: three are picked each day (same for everyone, UTC).
-- Stat names match move actions, plus Shard, ComboScore (best single combo)
-- and TrialFinish.
Config.Quests = {
	PerDay = 3,
	RewardShards = { 20, 30, 45 },
	RewardXP = { 120, 180, 260 },
	Pool = {
		{ Id = "grapple", Stat = "Grapple", Goals = { 30, 60, 100 }, Text = "Hook %d grapple points" },
		{ Id = "walljump", Stat = "WallJump", Goals = { 15, 30, 50 }, Text = "Wall jump %d times" },
		{ Id = "dash", Stat = "Dash", Goals = { 20, 40, 70 }, Text = "Air dash %d times" },
		{ Id = "slingshot", Stat = "Slingshot", Goals = { 5, 12, 20 }, Text = "Slingshot off the rope %d times" },
		{ Id = "bunnyhop", Stat = "BunnyHop", Goals = { 10, 25, 40 }, Text = "Bunny hop %d times" },
		{ Id = "slidejump", Stat = "SlideJump", Goals = { 8, 16, 30 }, Text = "Slide jump %d times" },
		{ Id = "launch", Stat = "Launch", Goals = { 3, 6, 10 }, Text = "Use launch pads %d times" },
		{ Id = "shards", Stat = "Shard", Goals = { 25, 50, 90 }, Text = "Collect %d shards" },
		{ Id = "combo", Stat = "ComboScore", Goals = { 15, 30, 50 }, Text = "Bank a %d style combo", Best = true },
		{ Id = "trial", Stat = "TrialFinish", Goals = { 1, 2, 3 }, Text = "Finish %d time trials" },
	},
}

-- Emotes (keys 1-4). Names match R6Animator poses.
Config.Emotes = { "Wave", "Dance", "Flex", "Sit" }

-- Player settings and their defaults. Saved per player.
Config.Settings = {
	Defaults = {
		Quality = "High", -- Low | Medium | High | Ultra
		TimeOfDay = "Golden Hour", -- Sunrise | Golden Hour | Sunset | Night
		FieldOfView = 70,
		MouseSensitivity = 1,
		CameraShake = true,
		SpeedLines = true,
		SprintMode = "Hold", -- Hold | Toggle
		ShowSpeedometer = true,
		EffectsVolume = 0.8,
		WindVolume = 0.8,
	},
	Choices = {
		Quality = { "Low", "Medium", "High", "Ultra" },
		TimeOfDay = { "Sunrise", "Golden Hour", "Sunset", "Night" },
		SprintMode = { "Hold", "Toggle" },
	},
	Ranges = {
		FieldOfView = { 60, 95 },
		MouseSensitivity = { 0.2, 2.5 },
		EffectsVolume = { 0, 1 },
		WindVolume = { 0, 1 },
	},
}

return Config

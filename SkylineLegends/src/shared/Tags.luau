-- World tagging conventions shared by the world builder (server) and the
-- movement, mechanism and course systems (client).
--
-- Gameplay surfaces are identified by CollectionService tags plus attributes,
-- so a hand-built map (or a new district) works with every system as long as
-- it follows these conventions.

local Tags = {
	-- Surfaces --------------------------------------------------------------
	Climbable = "Climbable", -- ladders, vines, mesh: climb in any direction
	Balance = "Balance", -- narrow beams: balance traversal along the part's longest axis
	LowClearance = "LowClearance", -- slide/crouch under (collision group LowClearance)
	Ice = "Ice", -- slippery ground that keeps momentum
	NoWallRun = "NoWallRun", -- attribute or tag: not runnable
	NoLedge = "NoLedge", -- attribute or tag: not grabbable
	Precision = "PrecisionPad", -- small landing targets

	-- Traversal objects -------------------------------------------------------
	Zipline = "Zipline", -- attributes A, B (Vector3 endpoints of the cable)
	SwingRope = "SwingRope", -- attributes Pivot (Vector3), Length (number)
	GrappleAnchor = "GrappleAnchor", -- swing anchor (ring)
	PullAnchor = "PullAnchor", -- pull anchor (diamond); attribute Exit (Vector3) optional
	BouncePad = "BouncePad", -- attribute Power (vertical speed)
	LaunchVent = "LaunchVent", -- attributes Power, Period, OnFraction, Phase, Warn
	WindZone = "WindZone", -- attributes Force (Vector3 accel), Period, OnFraction, Phase, Warn
	GravityZone = "GravityZone", -- attributes Scale (0..1), Lift (accel)
	Conveyor = "Conveyor", -- anchored part with AssemblyLinearVelocity

	-- Mechanisms (animated on each client from shared time) -------------------
	Mover = "Mover", -- attribute Kind = Linear | Orbit | Spin | Pendulum | Shuttle
	Timed = "Timed", -- attribute Kind = Retract | Blink | Door | Laser | Vent | Gust
	Collapse = "Collapse", -- falls a moment after you land on it, then resets
	Hazard = "Hazard", -- touching it sends you back to your checkpoint (attribute Active)
	KillZone = "KillZone", -- volume: falling into it respawns you
	Switch = "PressureSwitch", -- attributes SwitchId, Duration, Coop
	SwitchGate = "SwitchGate", -- attribute SwitchId
	Water = "RisingWater", -- attributes CourseId, StartCP, Rate, BaseY, MaxY

	-- Courses -------------------------------------------------------------------
	CourseStart = "CourseStart", -- attributes CourseId
	CourseCheckpoint = "CourseCheckpoint", -- attributes CourseId, Index (volume)
	CourseFinish = "CourseFinish", -- attributes CourseId (volume)
	CourseToken = "CourseToken", -- attributes CourseId, Index
	CourseShortcut = "CourseShortcut", -- attributes CourseId (volume)

	-- World ----------------------------------------------------------------------
	Discovery = "Discovery", -- attributes Id, Kind (Cache | Letter | Landmark | Secret)
	QuestPoint = "QuestPoint", -- attributes Id
	ContractPoint = "ContractPoint", -- attributes District
	TravelGate = "TravelGate", -- attributes District
	NPCSpot = "NPCSpot", -- attributes Id
	LessonZone = "LessonZone", -- attributes LessonId
	Board = "Board", -- attributes Kind (Race | Jobs | Courses | Leaderboard), District
	Decor = "Decor",
	-- Animated R6 rigs that aren't player characters (ghosts, NPCs). Attributes:
	-- MS (movement state), MA (aux Vector3), MB (aux number), GV (velocity), Emote
	Rig = "SkylineRig",
	SurfaceIcon = "SurfaceIcon", -- billboard icons shown per accessibility setting
}

-- Collision groups (registered by the server at start).
Tags.Groups = {
	World = "Default",
	Players = "Players",
	PlayersLow = "PlayersLow", -- crouching/sliding: passes LowClearance
	PlayersPhase = "PlayersPhase", -- scripted moves (vault/mantle): passes world geometry
	LowClearance = "LowClearance",
	Ghosts = "Ghosts",
	Cosmetic = "Cosmetic",
}

return Tags

-- Runs the stabilization minigame on the server.
--
-- StartCapture checks the comet (landed, not expired, visible, unclaimed by
-- this player, biome unlocked), the player's distance, core storage and any
-- fail cooldown, then opens a session with a random seed and the capture
-- parameters (biome, comet type, tether level, Easy Capture, tutorial).
--
-- The client reports *when* it pressed, in seconds since the session began.
-- Each report must fit the server's own clock: never ahead of it, and no
-- further behind than the player's measured latency allows. The server
-- re-scores the press with the shared CaptureMath and is the only one that
-- grants the core, Stardust and XP — once per comet per player. Sessions are
-- identified by ID, so repeated or stale reports are rejected.
--
-- Capture quality affects Stardust, XP and the Perfect stat. It never
-- affects which creature is inside the core.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BiomeDefinitions = require(Shared.BiomeDefinitions)
local CaptureMath = require(Shared.CaptureMath)
local EconomyMath = require(Shared.EconomyMath)
local GameConfig = require(Shared.GameConfig)
local Loop = require(Shared.Loop)
local Signal = require(Shared.Signal)
local UpgradeDefinitions = require(Shared.UpgradeDefinitions)

local CaptureService = { Name = "CaptureService" }

-- (player, comet)
CaptureService.CaptureStarted = Signal.new()
-- (player, result) — result: { Comet, Quality, Rank, CoreId, Stardust, XP, IsTutorial }
CaptureService.CaptureSucceeded = Signal.new()
-- (player, comet, reason)
CaptureService.CaptureFailed = Signal.new()

CaptureService.Clock = os.clock

export type Session = {
	Id: number,
	Player: Player,
	Comet: any,
	Params: CaptureMath.Params,
	StartClock: number,
	Stage: number,
	Attempt: number,
	AttemptStart: number,
	Misses: number,
	LockScore: number,
	LastT: number,
	Ping: number,
}

local capture = GameConfig.Capture
local services: { [string]: any } = {}
local sessions: { [Player]: Session } = {}
local cooldowns: { [Player]: { [string]: number } } = {}
local nextSessionId = 0
local rng = Random.new()

function CaptureService.GetSession(player: Player): Session?
	return sessions[player]
end

-- Combined capture modifiers for this player and comet.
function CaptureService.BuildModifiers(player: Player, comet: any): CaptureMath.Modifiers
	local profile = services.PlayerDataService.GetProfile(player)
	local biome = BiomeDefinitions.Get(comet.Biome)
	local biomeMods = if biome then biome.Capture else { SpeedMult = 1, ZoneMult = 1, BandMult = 1, DriftMult = 1 }
	local cometType = GameConfig.Comets.Types[comet.Type] or GameConfig.Comets.Types.Ember
	local tether = UpgradeDefinitions.GetLevel("Tether", if profile then profile.Equipment.TetherLevel else 1)
	local mods: CaptureMath.Modifiers = {
		SpeedMult = biomeMods.SpeedMult * cometType.SpeedMult * (tether.SpeedMult or 1),
		ZoneMult = biomeMods.ZoneMult * cometType.ZoneMult * (tether.ZoneMult or 1),
		BandMult = biomeMods.BandMult * (tether.ZoneMult or 1),
		DriftMult = biomeMods.DriftMult,
		QualityBonus = tether.QualityBonus or 0,
		QualityCap = 1,
	}
	if profile and profile.Settings.EasyCapture then
		mods.ZoneMult = (mods.ZoneMult :: number) * capture.EasyZoneMult
		mods.SpeedMult = (mods.SpeedMult :: number) * capture.EasySpeedMult
		mods.BandMult = (mods.BandMult :: number) * capture.EasyBandMult
		mods.QualityCap = capture.EasyQualityCap
	end
	if comet.IsTutorial then
		mods.ZoneMult = (mods.ZoneMult :: number) * capture.TutorialZoneMult
		mods.SpeedMult = (mods.SpeedMult :: number) * capture.TutorialSpeedMult
		mods.BandMult = (mods.BandMult :: number) * capture.TutorialBandMult
		mods.MissesAllowed = 99
	end
	return mods
end

local function setCaptureTarget(player: Player, position: Vector3?)
	local character = player.Character
	if character and character.Parent then
		character:SetAttribute("CaptureTarget", position)
	end
end

local function endSession(session: Session)
	if sessions[session.Player] == session then
		sessions[session.Player] = nil
	end
	setCaptureTarget(session.Player, nil)
end

local function distanceOk(player: Player, comet: any, leewayMultiplier: number): (boolean, string?)
	local position = services.SecurityService.GetRootPosition(player)
	if not position then
		return false, "NoCharacter"
	end
	local limit = GameConfig.Comets.CaptureDistance + GameConfig.Comets.DistanceLeeway * leewayMultiplier
	if (position - comet.Position).Magnitude > limit then
		return false, "TooFar"
	end
	return true, nil
end

local function fail(session: Session, reason: string): { [string]: any }
	endSession(session)
	local perPlayer = cooldowns[session.Player]
	if not perPlayer then
		perPlayer = {}
		cooldowns[session.Player] = perPlayer
	end
	perPlayer[session.Comet.Id] = CaptureService.Clock() + capture.FailCooldown
	CaptureService.CaptureFailed:Fire(session.Player, session.Comet, reason)
	return { Ok = true, Hit = false, Failed = true, Reason = reason, Cooldown = capture.FailCooldown }
end

local function miss(session: Session, t: number, reason: string?): { [string]: any }
	session.Misses += 1
	if session.Misses > session.Params.MissesAllowed then
		local result = fail(session, "TooManyMisses")
		result.MissReason = reason
		return result
	end
	session.Attempt += 1
	session.AttemptStart = t + session.Params.MissPause
	return {
		Ok = true,
		Hit = false,
		Reason = reason,
		Misses = session.Misses,
		Stage = session.Stage,
		Attempt = session.Attempt,
		AttemptStart = session.AttemptStart,
	}
end

local function complete(session: Session, releaseScore: number): { [string]: any }
	local player = session.Player
	local comet = session.Comet
	local nearby, reason = distanceOk(player, comet, 2)
	if not nearby then
		return fail(session, reason or "TooFar")
	end
	if comet.Claims[player.UserId] then
		endSession(session)
		return { Ok = false, Reason = "AlreadyClaimed" }
	end
	local profile = services.PlayerDataService.GetProfile(player)
	if not profile then
		endSession(session)
		return { Ok = false, Reason = "NotReady" }
	end

	local quality = CaptureMath.FinalQuality(session.Params, session.LockScore, releaseScore, session.Misses)
	local stardust, xp, rank = EconomyMath.CaptureReward(comet.Biome, comet.Type, quality)
	local core, coreReason = services.CreatureService.GrantCore(
		player,
		if comet.IsTutorial then "Starter" else "Normal",
		comet.Biome,
		comet.Type,
		quality
	)
	if not core then
		-- Comet stays unclaimed so the player can come back after making room.
		endSession(session)
		return { Ok = false, Reason = coreReason }
	end

	-- Claim, then pay out. Nothing here yields, so it all happens together.
	services.CometService.MarkClaimed(comet, player)
	endSession(session)
	services.EconomyService.Grant(player, "Stardust", stardust, "Capture")
	services.ProgressionService.AddXP(player, xp, "Capture")
	local stats = profile.Stats
	stats.Captures = (stats.Captures or 0) + 1
	if rank == "Perfect" then
		stats.PerfectCaptures = (stats.PerfectCaptures or 0) + 1
	end
	stats.BestQuality = math.max(stats.BestQuality or 0, quality)
	services.ReplicationService.Set(player, { "Stats" }, stats)

	local result = {
		Comet = comet,
		Quality = quality,
		Rank = rank,
		CoreId = core.Id,
		Stardust = stardust,
		XP = xp,
		IsTutorial = comet.IsTutorial,
	}
	CaptureService.CaptureSucceeded:Fire(player, result)
	services.AnalyticsService.Milestone(player, "FirstCapture")
	services.AnalyticsService.Custom(player, "CaptureQuality", math.floor(quality * 100))
	return {
		Ok = true,
		Hit = true,
		Complete = true,
		Score = releaseScore,
		Quality = quality,
		Rank = rank,
		Stardust = stardust,
		XP = xp,
		CoreId = core.Id,
	}
end

function CaptureService.HandleStart(player: Player, cometId: string): { [string]: any }
	local profile = services.PlayerDataService.GetProfile(player)
	if not profile then
		return { Ok = false, Reason = "NotReady" }
	end
	local existing = sessions[player]
	if existing then
		-- The client lost track (respawn, UI reset): drop the old session.
		endSession(existing)
	end
	local comet = services.CometService.Get(cometId)
	if not comet then
		return { Ok = false, Reason = "Expired" }
	end
	local capturable, reason = services.CometService.CheckCapturable(comet, player)
	if not capturable then
		return { Ok = false, Reason = reason }
	end
	local perPlayer = cooldowns[player]
	if perPlayer and (perPlayer[cometId] or 0) > CaptureService.Clock() then
		return { Ok = false, Reason = "Cooldown", Wait = perPlayer[cometId] - CaptureService.Clock() }
	end
	if services.CreatureService.CountCores(profile) >= GameConfig.Inventory.MaxCores then
		return { Ok = false, Reason = "CoreStorageFull" }
	end
	local nearby, distanceReason = distanceOk(player, comet, 1)
	if not nearby then
		return { Ok = false, Reason = distanceReason }
	end

	nextSessionId += 1
	local params = CaptureMath.BuildParams(rng:NextInteger(1, 2 ^ 31 - 2), CaptureService.BuildModifiers(player, comet))
	local ping = 0.1
	pcall(function()
		ping = player:GetNetworkPing()
	end)
	local session: Session = {
		Id = nextSessionId,
		Player = player,
		Comet = comet,
		Params = params,
		StartClock = CaptureService.Clock(),
		Stage = 1,
		Attempt = 1,
		AttemptStart = params.IntroTime,
		Misses = 0,
		LockScore = 0,
		LastT = 0,
		Ping = ping,
	}
	sessions[player] = session
	setCaptureTarget(player, comet.Position)
	CaptureService.CaptureStarted:Fire(player, comet)
	return {
		Ok = true,
		Session = {
			Id = session.Id,
			CometId = comet.Id,
			Params = params,
			AttemptStart = session.AttemptStart,
			IsTutorial = comet.IsTutorial,
		},
	}
end

-- Checks a reported time against the server's clock for this session.
local function timeFits(session: Session, t: number): boolean
	local elapsed = CaptureService.Clock() - session.StartClock
	local tolerance = CaptureMath.LatencyTolerance(session.Ping)
	return t <= elapsed + capture.FutureTolerance and t >= elapsed - tolerance and t >= session.LastT
end

function CaptureService.HandleAction(
	player: Player,
	sessionId: number,
	action: string,
	t1: number?,
	t2: number?
): { [string]: any }
	local session = sessions[player]
	if not session or session.Id ~= sessionId then
		return { Ok = false, Reason = "NoSession" }
	end
	if action == "Cancel" then
		endSession(session)
		return { Ok = true, Cancelled = true }
	end

	if action == "Lock" then
		if session.Stage ~= 1 or t1 == nil then
			return { Ok = false, Reason = "WrongStage" }
		end
		if not timeFits(session, t1) then
			endSession(session)
			return { Ok = false, Reason = "Desync" }
		end
		session.LastT = t1
		local result = CaptureMath.ScoreLock(session.Params, session.Attempt, t1 - session.AttemptStart)
		if not result.Hit then
			return miss(session, t1, result.Reason)
		end
		session.LockScore = result.Score
		session.Stage = 2
		session.Attempt = 1
		session.AttemptStart = t1 + session.Params.TransitionTime
		return {
			Ok = true,
			Hit = true,
			Score = result.Score,
			Stage = 2,
			Attempt = 1,
			AttemptStart = session.AttemptStart,
		}
	elseif action == "Release" then
		if session.Stage ~= 2 or t1 == nil or t2 == nil then
			return { Ok = false, Reason = "WrongStage" }
		end
		if t2 <= t1 or t1 < session.AttemptStart - 0.05 or not timeFits(session, t2) then
			endSession(session)
			return { Ok = false, Reason = "Desync" }
		end
		session.LastT = t2
		local holdStart = math.max(t1 - session.AttemptStart, 0)
		local result = CaptureMath.ScoreRelease(session.Params, session.Attempt, holdStart, t2 - session.AttemptStart)
		if not result.Hit then
			return miss(session, t2, result.Reason)
		end
		return complete(session, result.Score)
	end
	return { Ok = false, Reason = "BadAction" }
end

-- Ends sessions the client abandoned.
function CaptureService.Sweep()
	local now = CaptureService.Clock()
	for _, session in table.clone(sessions) do
		local elapsed = now - session.StartClock
		local limit = session.AttemptStart
			+ session.Params.StageTimeout
			+ session.Params.OverchargeTime
			+ CaptureMath.LatencyTolerance(session.Ping)
			+ 1
		if elapsed > limit then
			fail(session, "Timeout")
			services.ReplicationService.Notify(session.Player, "CaptureTimeout", { CometId = session.Comet.Id })
		end
	end
end

function CaptureService.Init(registry: { [string]: any })
	services = registry
end

function CaptureService.Start()
	services.SecurityService.BindFunction("StartCapture", CaptureService.HandleStart)
	services.SecurityService.BindFunction("CaptureAction", CaptureService.HandleAction)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		local session = sessions[player]
		if session then
			endSession(session)
		end
		cooldowns[player] = nil
	end)
	Loop.Every(0.5, "CaptureSweep", CaptureService.Sweep)
end

return CaptureService

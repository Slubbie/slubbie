-- A simulated game server: the real services, loaded fresh, wired the same
-- way the bootstrap wires them, but with mocked engine services, a
-- controllable clock, an in-memory DataStore ("cloud") that several servers
-- can share, and remotes replaced by direct calls through the real
-- SecurityService guard (validation + rate limiting).

local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Loader = require("./Loader")
local Mock = require("./Mock")

local Vector3 = roblox.Vector3

local Server = {}
Server.__index = Server

Server.Order = {
	"SecurityService",
	"AnalyticsService",
	"PlayerDataService",
	"ReplicationService",
	"EconomyService",
	"ProgressionService",
	"CreatureService",
	"UpgradeService",
	"IncomeService",
	"SanctuaryService",
	"CometService",
	"CaptureService",
	"WispService",
	"QuestService",
	"TravelService",
}

local ROOT = "."

-- Impact sites and wisp spots on a flat test island around (640, 40, 0).
local function fakeWorld()
	local impacts = {}
	for i = 1, 10 do
		local a = i / 10 * math.pi * 2
		table.insert(impacts, {
			Id = `dc{i}`,
			Position = Vector3.new(640 + math.cos(a) * 100, 40, math.sin(a) * 100),
			Biome = "DawnCommons",
		})
	end
	local wisps = {}
	for i = 1, 4 do
		table.insert(wisps, { Id = `w{i}`, Position = Vector3.new(600 + i * 20, 42.5, 50), Biome = "DawnCommons" })
	end
	local noop = function() end
	return {
		Name = "WorldService",
		ImpactPoints = { DawnCommons = impacts },
		WispPoints = wisps,
		TutorialImpact = Vector3.new(0, 40, 66),
		Portals = {},
		Plots = {},
		Init = noop,
		Start = noop,
		GetPlot = function()
			return nil
		end,
		SetPlotTier = noop,
	}
end

export type Options = {
	Cloud: any?,
	Clock: any?,
	SessionId: string?,
	IsStudio: boolean?,
	SessionOnly: boolean?,
	Seed: number?,
	Quiet: boolean?,
}

function Server.new(options: Options?)
	local o = options or {}
	local clock = o.Clock or Mock.Clock()
	local loader = Loader.new(ROOT, { Clock = clock, Cloud = o.Cloud, IsStudio = o.IsStudio, Quiet = o.Quiet })
	local self = setmetatable({
		Loader = loader,
		Clock = clock,
		Players = loader.Services.Players,
		Registry = {},
		Cloud = o.Cloud,
	}, Server)

	loader:require("Shared.Loop").Disabled = true
	local GameConfig = loader:require("Shared.GameConfig")
	GameConfig.Tutorial.CometDelay = 0
	GameConfig.Data.PrioritySaveDelay = 0.01
	self.Config = GameConfig

	local registry = self.Registry
	registry.WorldService = fakeWorld()
	for _, name in Server.Order do
		registry[name] = loader:require(`Server.Services.{name}`)
	end
	registry.SecurityService.AttachRemotes = false
	registry.SecurityService.Clock = function()
		return clock.Os
	end
	registry.AnalyticsService.Enabled = false
	registry.ReplicationService.Sent = {}
	registry.CometService.Sent = {}
	registry.CometService.Clock = function()
		return clock.Server
	end
	registry.CaptureService.Clock = function()
		return clock.Os
	end
	registry.WispService.Clock = function()
		return clock.Server
	end
	registry.IncomeService.Clock = function()
		return clock.Os
	end
	registry.SanctuaryService.BuildVisuals = false
	registry.PlayerDataService.Configure({
		Backend = if o.Cloud then o.Cloud.Store else nil,
		SessionId = o.SessionId or "server-A",
		Clock = function()
			return clock.Unix
		end,
		Wait = function() end,
		IsStudio = o.IsStudio == true,
		SessionOnly = o.SessionOnly,
	})
	registry.CreatureService.Random = Mock.Random.new(o.Seed or 1234)
	registry.CometService.Random = Mock.Random.new((o.Seed or 1234) + 1)

	for _, name in Server.Order do
		registry[name].Init(registry)
	end
	for _, name in Server.Order do
		registry[name].Start()
	end
	return self
end

function Server:Get(name: string): any
	return self.Registry[name]
end

function Server:Settle()
	for _ = 1, 3 do
		task.wait()
	end
end

function Server:Join(userId: number, position: Vector3?): (any, string)
	local player = Mock.Player(self.Players, userId, `Player{userId}`, position)
	table.insert(self.Players.List, player)
	local status = self.Registry.PlayerDataService.LoadPlayer(player)
	self:Settle()
	return player, status
end

function Server:Leave(player: any)
	self.Players.PlayerRemoving:Fire(player)
	local index = table.find(self.Players.List, player)
	if index then
		table.remove(self.Players.List, index)
	end
	player.Parent = nil
	self:Settle()
end

function Server:Shutdown()
	for _, player in table.clone(self.Players.List) do
		self:Leave(player)
	end
end

function Server:Profile(player: any): any
	return self.Registry.PlayerDataService.GetProfile(player)
end

-- Calls a client→server remote handler through the real security guard.
function Server:Invoke(remote: string, player: any, ...: any): any
	local handler = self.Registry.SecurityService.Handlers[remote]
	assert(handler, `no handler bound for {remote}`)
	return handler(player, ...)
end

function Server:Advance(seconds: number)
	self.Clock:Advance(seconds)
end

-- Spawns a regular comet and moves time past its impact.
function Server:LandComet(biome: string?): any
	local comet = self.Registry.CometService.Spawn(biome or "DawnCommons")
	assert(comet, "no comet spawned")
	self:Advance(self.Config.Comets.FallDuration + 0.1)
	return comet
end

-- Plays the minigame for a comet. quality: "Perfect" (default) or "Edge"
-- (barely inside the zones). Returns the final result and the start response.
function Server:Capture(player: any, cometId: string, quality: string?): (any, any)
	local CaptureMath = self.Loader:require("Shared.CaptureMath")
	local start = self:Invoke("StartCapture", player, cometId)
	if not start.Ok then
		return start, start
	end
	local session = start.Session
	local params = session.Params
	local origin = self.Clock.Os
	local function at(t: number)
		self.Clock.Os = origin + t + 0.02
	end

	-- Stage 1: press at the zone centre (or near its edge).
	local zone = CaptureMath.ZoneCenter(params, 1)
	local offset = if quality == "Edge" then params.ZoneHalfWidth * 0.95 else 0
	local rel = (zone + offset) / 360 * params.DialPeriod
	local t1 = session.AttemptStart + rel
	at(t1)
	local lock = self:Invoke("CaptureAction", player, session.Id, "Lock", t1)
	if not lock.Ok or not lock.Hit then
		return lock, start
	end

	-- Stage 2: find the hold that lands closest to (or near the edge of) the band.
	local stage2 = lock.AttemptStart
	local holdStart = stage2 + 0.2
	local bestEnd, bestScore = nil, -1
	local target = if quality == "Edge" then 0.57 else 1
	local hold = 0.05
	while hold < params.OverchargeTime do
		local result = CaptureMath.ScoreRelease(params, 1, holdStart - stage2, holdStart + hold - stage2)
		if result.Hit then
			local fit = -math.abs(result.Score - target)
			if fit > bestScore then
				bestScore = fit
				bestEnd = holdStart + hold
			end
		end
		hold += 0.002
	end
	assert(bestEnd, "no winning release time found")
	at(bestEnd)
	local final = self:Invoke("CaptureAction", player, session.Id, "Release", holdStart, bestEnd)
	return final, start
end

return Server

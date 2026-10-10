-- The authoritative registry of comet impact sites.
--
-- Each implemented biome gets a comet every SpawnIntervalMin–Max seconds
-- (capped per biome and in total), at a validated impact site that isn't on
-- cooldown or too close to another active comet. Comets are shared world
-- events, but every player may capture each one once (per-player claims), so
-- discovering one with friends never turns into a race.
--
-- The tutorial comet is private: only its owner sees and can capture it.
-- Clients only receive data (position, timings, type) and draw everything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BiomeDefinitions = require(Shared.BiomeDefinitions)
local GameConfig = require(Shared.GameConfig)
local Loop = require(Shared.Loop)
local RarityConfig = require(Shared.RarityConfig)
local RemoteDefinitions = require(Shared.RemoteDefinitions)
local Signal = require(Shared.Signal)

local CometService = { Name = "CometService" }

export type Comet = {
	Id: string,
	Biome: string,
	LocationId: string,
	Position: Vector3,
	Type: string,
	SpawnTime: number,
	ImpactTime: number,
	ExpireTime: number,
	Entry: Vector3,
	Claims: { [number]: boolean },
	Owner: number?,
	IsTutorial: boolean,
	Expired: boolean,
}

-- (comet)
CometService.Spawned = Signal.new()
-- (comet)
CometService.ExpiredSignal = Signal.new()

CometService.Clock = function(): number
	return workspace:GetServerTimeNow()
end
CometService.Random = Random.new()

local config = GameConfig.Comets
local services: { [string]: any } = {}
local comets: { [string]: Comet } = {}
local nextSpawn: { [string]: number } = {}
local locationCooldown: { [string]: number } = {}
local serial = 0
local broadcast: RemoteEvent? = nil

-- Test hook: capture broadcasts instead of firing remotes.
CometService.Sent = nil :: { any }?

function CometService.Serialize(comet: Comet, player: Player?): { [string]: any }
	return {
		Id = comet.Id,
		Biome = comet.Biome,
		Position = comet.Position,
		Type = comet.Type,
		SpawnTime = comet.SpawnTime,
		ImpactTime = comet.ImpactTime,
		ExpireTime = comet.ExpireTime,
		Entry = comet.Entry,
		IsTutorial = comet.IsTutorial,
		Claimed = if player then comet.Claims[player.UserId] == true else false,
	}
end

local function send(player: Player?, kind: string, payload: any)
	if CometService.Sent then
		table.insert(CometService.Sent, { Player = player, Kind = kind, Payload = payload })
		return
	end
	if not broadcast then
		return
	end
	if player then
		if player.Parent then
			broadcast:FireClient(player, kind, payload)
		end
	else
		broadcast:FireAllClients(kind, payload)
	end
end

function CometService.IsVisibleTo(comet: Comet, player: Player): boolean
	return comet.Owner == nil or comet.Owner == player.UserId
end

function CometService.Get(id: string): Comet?
	return comets[id]
end

function CometService.GetAll(): { [string]: Comet }
	return comets
end

function CometService.ActiveIn(biomeId: string): { Comet }
	local list = {}
	for _, comet in comets do
		if comet.Biome == biomeId and not comet.IsTutorial then
			table.insert(list, comet)
		end
	end
	return list
end

local function countActive(): number
	local n = 0
	for _, comet in comets do
		if not comet.IsTutorial then
			n += 1
		end
	end
	return n
end

local function pickType(rng: Random): string
	local weights = {}
	for i, id in config.TypeOrder do
		weights[i] = config.Types[id].Weight
	end
	return config.TypeOrder[RarityConfig.PickWeighted(weights, rng)]
end

local function randomEntry(rng: Random): Vector3
	local a = rng:NextNumber() * math.pi * 2
	return Vector3.new(math.cos(a), 0, math.sin(a))
end

local function register(comet: Comet)
	comets[comet.Id] = comet
	CometService.Spawned:Fire(comet)
	if comet.Owner then
		local owner = Players:GetPlayerByUserId(comet.Owner)
		if owner then
			send(owner, "Spawn", CometService.Serialize(comet, owner))
		end
	else
		send(nil, "Spawn", CometService.Serialize(comet))
	end
end

-- Spawns a comet in a biome at a free impact site. Returns nil if none is free.
function CometService.Spawn(biomeId: string): Comet?
	local points = services.WorldService.ImpactPoints[biomeId]
	if not points or #points == 0 then
		return nil
	end
	local now = CometService.Clock()
	local active = CometService.ActiveIn(biomeId)
	if #active >= config.MaxPerBiome or countActive() >= config.MaxTotal then
		return nil
	end
	local candidates = {}
	for _, point in points do
		if (locationCooldown[point.Id] or -math.huge) > now then
			continue
		end
		local clear = true
		for _, other in active do
			if (other.Position - point.Position).Magnitude < config.MinSpacing then
				clear = false
				break
			end
		end
		if clear then
			table.insert(candidates, point)
		end
	end
	if #candidates == 0 then
		return nil
	end
	local rng = CometService.Random
	local point = candidates[rng:NextInteger(1, #candidates)]
	serial += 1
	local comet: Comet = {
		Id = `c{serial}`,
		Biome = biomeId,
		LocationId = point.Id,
		Position = point.Position,
		Type = pickType(rng),
		SpawnTime = now,
		ImpactTime = now + config.FallDuration,
		ExpireTime = now + config.FallDuration + config.Lifetime,
		Entry = randomEntry(rng),
		Claims = {},
		Owner = nil,
		IsTutorial = false,
		Expired = false,
	}
	locationCooldown[point.Id] = comet.ExpireTime + config.LocationCooldown
	register(comet)
	return comet
end

-- The private onboarding comet that lands in front of a new player.
function CometService.SpawnTutorial(player: Player): Comet
	for _, comet in comets do
		if comet.IsTutorial and comet.Owner == player.UserId and not comet.Claims[player.UserId] then
			return comet
		end
	end
	local now = CometService.Clock()
	serial += 1
	local comet: Comet = {
		Id = `t{serial}`,
		-- Rewards and the core come from the first biome.
		Biome = BiomeDefinitions.Order[1],
		LocationId = "tutorial",
		Position = services.WorldService.TutorialImpact,
		Type = "Starter",
		SpawnTime = now,
		ImpactTime = now + config.TutorialFallDuration,
		ExpireTime = now + 3600,
		-- Falls from behind the observatory so the player sees it come in.
		Entry = Vector3.new(0, 0, -1),
		Claims = {},
		Owner = player.UserId,
		IsTutorial = true,
		Expired = false,
	}
	register(comet)
	return comet
end

-- Whether `player` may start capturing `comet` right now (distance is checked by CaptureService).
function CometService.CheckCapturable(comet: Comet, player: Player): (boolean, string?)
	-- Visibility first: a private comet reveals nothing to anyone else.
	if not CometService.IsVisibleTo(comet, player) then
		return false, "NotYours"
	end
	local now = CometService.Clock()
	if comet.Expired or now >= comet.ExpireTime then
		return false, "Expired"
	end
	if now < comet.ImpactTime then
		return false, "StillFalling"
	end
	if comet.Claims[player.UserId] then
		return false, "AlreadyClaimed"
	end
	if not comet.IsTutorial then
		local ok, reason = services.ProgressionService.CanEnterBiome(player, comet.Biome)
		if not ok then
			return false, reason
		end
	end
	return true, nil
end

function CometService.MarkClaimed(comet: Comet, player: Player)
	comet.Claims[player.UserId] = true
	send(player, "Claimed", { Id = comet.Id })
	if comet.IsTutorial then
		-- Leave it on screen for the containment animation, then clear it.
		task.delay(4, function()
			if comets[comet.Id] == comet then
				CometService.Expire(comet)
			end
		end)
	end
end

function CometService.Expire(comet: Comet)
	if comet.Expired then
		return
	end
	comet.Expired = true
	comets[comet.Id] = nil
	CometService.ExpiredSignal:Fire(comet)
	if comet.Owner then
		local owner = Players:GetPlayerByUserId(comet.Owner)
		if owner then
			send(owner, "Expire", { Id = comet.Id })
		end
	else
		send(nil, "Expire", { Id = comet.Id })
	end
end

-- One scheduler step: expire old comets and spawn new ones when due.
function CometService.Step()
	local now = CometService.Clock()
	for _, comet in comets do
		if now >= comet.ExpireTime then
			CometService.Expire(comet)
		end
	end
	if #Players:GetPlayers() == 0 and not CometService.Sent then
		return
	end
	for _, biomeId in BiomeDefinitions.Order do
		local biome = BiomeDefinitions.Biomes[biomeId]
		if not biome.Implemented then
			continue
		end
		local due = nextSpawn[biomeId]
		if not due then
			nextSpawn[biomeId] = now + config.FirstSpawnDelay
		elseif now >= due then
			CometService.Spawn(biomeId)
			local rng = CometService.Random
			nextSpawn[biomeId] = now
				+ config.SpawnIntervalMin
				+ rng:NextNumber() * (config.SpawnIntervalMax - config.SpawnIntervalMin)
		end
	end
end

function CometService.SnapshotFor(player: Player): { { [string]: any } }
	local list = {}
	for _, comet in comets do
		if CometService.IsVisibleTo(comet, player) then
			table.insert(list, CometService.Serialize(comet, player))
		end
	end
	return list
end

function CometService.Init(registry: { [string]: any })
	services = registry
end

function CometService.Start()
	if not CometService.Sent then
		broadcast = RemoteDefinitions.GetEvent("CometBroadcast")
	end
	services.ReplicationService.RegisterSnapshotProvider("Comets", CometService.SnapshotFor)
	Players.PlayerRemoving:Connect(function(player)
		for _, comet in comets do
			if comet.Owner == player.UserId then
				CometService.Expire(comet)
			end
		end
	end)
	Loop.Every(0.5, "CometStep", CometService.Step)
end

return CometService

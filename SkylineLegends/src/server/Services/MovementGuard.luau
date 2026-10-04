-- Server-side movement relay and validation.
--
-- Movement is simulated on each player's own client for responsiveness. The
-- server relays it to everyone else for animation and only counts what it can
-- check: every reported technique must be plausible where the character
-- actually is (a wall run needs a wall nearby, a grapple needs an anchor in
-- range, double jumps need the ability...). Positions are sampled to catch
-- impossible speeds, and every teleport must have been announced first.
--
-- Validated actions feed flow chains, mastery, quests, dailies and
-- achievements through Events.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Abilities = require(ReplicatedStorage.Shared.Config.Abilities)
local Districts = require(ReplicatedStorage.Shared.Config.Districts)
local Flow = require(ReplicatedStorage.Shared.Config.Flow)
local GhostCodec = require(ReplicatedStorage.Shared.Logic.GhostCodec)
local MathUtil = require(ReplicatedStorage.Shared.Util.MathUtil)
local MovementConfig = require(ReplicatedStorage.Shared.Config.Movement)
local Net = require(ReplicatedStorage.Shared.Net)
local Tags = require(ReplicatedStorage.Shared.Tags)

local DataService = require(script.Parent.Parent.Data.DataService)
local Events = require(script.Parent.Parent.Events)
local ProgressionService = require(script.Parent.ProgressionService)

local SAMPLE_INTERVAL = 0.2
local HISTORY_SECONDS = 120
local MAX_PLAUSIBLE_SPEED = MovementConfig.MaxSpeed * 1.5 + 40
local MAX_FALL_SPEED = MovementConfig.MaxFallSpeed * 1.4 + 40

local MovementGuard = {}

type Sample = { T: number, P: Vector3 }
type Chain = { Actions: { string }, Last: number, Seen: { [string]: boolean }, Variety: number }
type PlayerState = {
	Samples: { Sample },
	Allowance: { Position: Vector3, Radius: number, Expires: number }?,
	Strikes: { number },
	Chain: Chain,
	District: string?,
}

local states: { [Player]: PlayerState } = {}

-- Every action the client may report, the ability it needs, and its check.
local VALID_ACTIONS: { [string]: { Ability: string?, Check: string? } } = {
	Jump = {},
	Land = {},
	Vault = { Ability = "Vault", Check = "Geometry" },
	Mantle = { Ability = "LedgeGrab", Check = "Geometry" },
	LedgeGrab = { Ability = "LedgeGrab", Check = "Geometry" },
	LedgeLeap = { Ability = "LedgeLeap", Check = "Geometry" },
	Slide = { Ability = "Slide" },
	SlideJump = { Ability = "Slide" },
	Climb = { Ability = "Climb", Check = "Climbable" },
	ClimbHop = { Ability = "Climb", Check = "Climbable" },
	WallRun = { Ability = "WallRun", Check = "Wall" },
	WallJump = { Ability = "WallJump", Check = "Wall" },
	WallKick = { Ability = "WallJump", Check = "Wall" },
	WallClimb = { Ability = "WallRun", Check = "Wall" },
	DoubleJump = { Ability = "DoubleJump" },
	Dash = { Ability = "Dash" },
	Grapple = { Ability = "Grapple", Check = "Anchor" },
	GrappleRelease = { Ability = "Grapple", Check = "Anchor" },
	Pull = { Ability = "GrapplePull", Check = "PullAnchor" },
	RopeSwing = { Ability = "RopeSwing", Check = "Rope" },
	Zipline = { Ability = "Zipline", Check = "Zipline" },
	Balance = { Ability = "Balance", Check = "Beam" },
	BalanceCatch = { Ability = "Balance", Check = "Beam" },
	Roll = { Ability = "Roll" },
	PrecisionLand = {},
	Bounce = { Check = "Bounce" },
	Launch = {},
	Stumble = {},
	Skid = {},
}

-- Moves that count toward stats/mastery (Jump/Land/Skid are too common to matter).
local COUNTED = {
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
	Pull = true,
	RopeSwing = true,
	Zipline = true,
	Balance = true,
	BalanceCatch = true,
	Roll = true,
	PrecisionLand = true,
	Bounce = true,
}

local VALID_STATES = {}
for _, name in GhostCodec.States do
	VALID_STATES[name] = true
end

-- Tagged world objects, cached once the world is built.
local cache: { [string]: { BasePart } } = {}

local function tagged(tag: string): { BasePart }
	local list = cache[tag]
	if not list then
		list = {}
		for _, instance in CollectionService:GetTagged(tag) do
			if instance:IsA("BasePart") then
				table.insert(list, instance)
			end
		end
		cache[tag] = list
	end
	return list
end

function MovementGuard.RefreshCache()
	table.clear(cache)
end

local function nearTagged(tag: string, position: Vector3, range: number): boolean
	for _, part in tagged(tag) do
		if part.Parent then
			local offset = part.CFrame:PointToObjectSpace(position)
			local half = part.Size / 2
			local clamped = Vector3.new(
				math.clamp(offset.X, -half.X, half.X),
				math.clamp(offset.Y, -half.Y, half.Y),
				math.clamp(offset.Z, -half.Z, half.Z)
			)
			if (offset - clamped).Magnitude <= range then
				return true
			end
		end
	end
	return false
end

local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude

local function nearWall(position: Vector3, character: Model): boolean
	wallParams.FilterDescendantsInstances = { character }
	for i = 0, 7 do
		local angle = i * math.pi / 4
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle)) * 7
		for _, dy in { 0, 1.5, -1.5 } do
			local hit = workspace:Raycast(position + Vector3.new(0, dy, 0), direction, wallParams)
			if hit and math.abs(hit.Normal.Y) < 0.45 then
				return true
			end
		end
	end
	return false
end

local function nearGeometry(position: Vector3, character: Model): boolean
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local parts = workspace:GetPartBoundsInRadius(position, 8, params)
	for _, part in parts do
		if part.CanCollide then
			return true
		end
	end
	return false
end

local function nearZipline(position: Vector3): boolean
	for _, part in tagged(Tags.Zipline) do
		local a, b = part:GetAttribute("A"), part:GetAttribute("B")
		if typeof(a) == "Vector3" and typeof(b) == "Vector3" then
			local closest = MathUtil.ClosestOnSegment(a, b, position)
			if (closest - position).Magnitude < 14 then
				return true
			end
		end
	end
	return false
end

local function nearRope(position: Vector3): boolean
	for _, part in tagged(Tags.SwingRope) do
		local pivot = part:GetAttribute("Pivot")
		local length = part:GetAttribute("Length")
		if typeof(pivot) == "Vector3" and type(length) == "number" then
			if (pivot - position).Magnitude < length + 18 then
				return true
			end
		end
	end
	return false
end

-- Positions the character has had in the last few seconds (latency tolerance).
local function recentPositions(state: PlayerState, seconds: number): { Vector3 }
	local now = os.clock()
	local result = {}
	for i = #state.Samples, 1, -1 do
		local sample = state.Samples[i]
		if now - sample.T > seconds then
			break
		end
		table.insert(result, sample.P)
	end
	return result
end

local function plausible(player: Player, state: PlayerState, check: string?): boolean
	if not check then
		return true
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not root then
		return false
	end
	local positions = recentPositions(state, 1.2)
	table.insert(positions, 1, root.Position)
	for _, position in positions do
		local ok = false
		if check == "Wall" then
			ok = nearWall(position, character)
		elseif check == "Geometry" then
			ok = nearGeometry(position, character)
		elseif check == "Climbable" then
			ok = nearTagged(Tags.Climbable, position, 9)
		elseif check == "Beam" then
			ok = nearTagged(Tags.Balance, position, 9)
		elseif check == "Anchor" then
			ok = nearTagged(Tags.GrappleAnchor, position, MovementConfig.GrappleRange + 40)
		elseif check == "PullAnchor" then
			ok = nearTagged(Tags.PullAnchor, position, MovementConfig.GrappleRange + 40)
		elseif check == "Zipline" then
			ok = nearZipline(position)
		elseif check == "Rope" then
			ok = nearRope(position)
		elseif check == "Bounce" then
			ok = nearTagged(Tags.BouncePad, position, 12)
		end
		if ok then
			return true
		end
	end
	return false
end

-- Chains --------------------------------------------------------------------------------

local function endChain(player: Player, state: PlayerState)
	local chain = state.Chain
	if #chain.Actions >= 2 then
		Events.ChainEnded:Fire(player, #chain.Actions, chain.Variety)
		local profile = DataService.Get(player)
		if profile and #chain.Actions > (profile.Stats.LongestChain or 0) then
			profile.Stats.LongestChain = #chain.Actions
			Events.StatChanged:Fire(player, "LongestChain")
		end
	end
	state.Chain = { Actions = {}, Last = 0, Seen = {}, Variety = 0 }
end

local function pushChain(player: Player, state: PlayerState, action: string)
	local now = os.clock()
	if now - state.Chain.Last > Flow.ChainGap then
		endChain(player, state)
	end
	local chain = state.Chain
	chain.Last = now
	if action == "Jump" or action == "Land" then
		return -- glue, not content
	end
	table.insert(chain.Actions, action)
	if #chain.Actions > 120 then
		table.remove(chain.Actions, 1)
	end
	if not chain.Seen[action] then
		chain.Seen[action] = true
		chain.Variety += 1
	end
	Events.Chain:Fire(player, chain.Actions)
end

function MovementGuard.CurrentChain(player: Player): { string }
	local state = states[player]
	return if state then state.Chain.Actions else {}
end

-- Teleports and sampling -------------------------------------------------------------------

-- Allow the next large jump in position if it lands near `position`.
function MovementGuard.AllowTeleport(player: Player, position: Vector3, radius: number?)
	local state = states[player]
	if state then
		state.Allowance = { Position = position, Radius = radius or 20, Expires = os.clock() + 4 }
	end
end

-- Whether the player was somewhere near `position` in the last two minutes.
function MovementGuard.VisitedRecently(player: Player, position: Vector3, radius: number): boolean
	local state = states[player]
	if not state then
		return false
	end
	for _, sample in state.Samples do
		if (sample.P - position).Magnitude <= radius then
			return true
		end
	end
	return false
end

-- Number of speed violations since `since` (os.clock time).
function MovementGuard.StrikesSince(player: Player, since: number): number
	local state = states[player]
	if not state then
		return 0
	end
	local n = 0
	for _, t in state.Strikes do
		if t >= since then
			n += 1
		end
	end
	return n
end

function MovementGuard.Position(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if root then root.Position else nil
end

-- Was the character within `radius` of `position` at any point in the last `seconds`?
function MovementGuard.WasNear(player: Player, position: Vector3, radius: number, seconds: number?): boolean
	local state = states[player]
	local current = MovementGuard.Position(player)
	if current and (current - position).Magnitude <= radius then
		return true
	end
	if not state then
		return false
	end
	for _, p in recentPositions(state, seconds or 1.5) do
		if (p - position).Magnitude <= radius then
			return true
		end
	end
	return false
end

function MovementGuard.District(player: Player): string?
	local state = states[player]
	return state and state.District
end

-- Called when the player enters a new district (set by DistrictService).
MovementGuard.OnDistrictChanged = nil :: ((Player, string) -> ())?

local function sample(player: Player, state: PlayerState)
	local position = MovementGuard.Position(player)
	if not position then
		return
	end
	local now = os.clock()
	local last = state.Samples[#state.Samples]
	if last then
		local dt = now - last.T
		local delta = position - last.P
		local horizontal = MathUtil.Flat(delta).Magnitude / math.max(dt, 0.05)
		local vertical = math.abs(delta.Y) / math.max(dt, 0.05)
		if horizontal > MAX_PLAUSIBLE_SPEED or vertical > MAX_FALL_SPEED then
			local allowance = state.Allowance
			if allowance and now < allowance.Expires and (position - allowance.Position).Magnitude <= allowance.Radius then
				state.Allowance = nil
			else
				table.insert(state.Strikes, now)
				if #state.Strikes > 50 then
					table.remove(state.Strikes, 1)
				end
			end
		end
	end
	table.insert(state.Samples, { T = now, P = position })
	while #state.Samples > 0 and now - state.Samples[1].T > HISTORY_SECONDS do
		table.remove(state.Samples, 1)
	end

	local district = Districts.At(position)
	local id = district and district.Id
	if id and id ~= state.District then
		state.District = id
		if MovementGuard.OnDistrictChanged then
			MovementGuard.OnDistrictChanged(player, id)
		end
	end
end

-- Remote handlers ----------------------------------------------------------------------------

local function onState(player: Player, stateName: any, aux: any, auxNumber: any)
	if type(stateName) ~= "string" or not VALID_STATES[stateName] then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	character:SetAttribute("MS", stateName)
	character:SetAttribute("MA", if typeof(aux) == "Vector3" and aux.Magnitude < 1e5 then aux else nil)
	character:SetAttribute("MB", if type(auxNumber) == "number" and auxNumber == auxNumber then math.clamp(auxNumber, -1e4, 1e4) else nil)
end

local function onAction(player: Player, action: any, value: any)
	local state = states[player]
	if not state or type(action) ~= "string" then
		return
	end
	local rule = VALID_ACTIONS[action]
	if not rule then
		return
	end
	if rule.Ability and not Abilities.IsBasic(rule.Ability) and not ProgressionService.HasAbility(player, rule.Ability) then
		return
	end
	if not plausible(player, state, rule.Check) then
		return
	end
	local number = if type(value) == "number" and value == value then math.clamp(value, 0, 1000) else nil
	-- Relay for animation and effects on other clients.
	Net.PushOthers(player, "Move.Action", player, action)

	if action == "Stumble" then
		Events.Break:Fire(player, "Stumble")
		endChain(player, state)
		return
	end
	pushChain(player, state, action)

	if COUNTED[action] then
		local profile = DataService.Get(player)
		if profile then
			profile.Stats[action] = (profile.Stats[action] or 0) + 1
			DataService.MarkDirty(player)
		end
		Events.Action:Fire(player, action, number, state.District)
		Events.StatChanged:Fire(player, action)
	elseif action == "GrappleRelease" then
		Events.Action:Fire(player, action, number, state.District)
	end
end

local function onFall(player: Player, reason: any, target: any)
	local state = states[player]
	if not state then
		return
	end
	endChain(player, state)
	Events.Break:Fire(player, if type(reason) == "string" then reason else "Fall")
	-- Respawning to a recent safe spot is a legitimate teleport.
	if typeof(target) == "Vector3" and MovementGuard.VisitedRecently(player, target, 12) then
		MovementGuard.AllowTeleport(player, target, 15)
	end
end

local function onFlow(player: Player, tier: any)
	local state = states[player]
	if not state or type(tier) ~= "number" then
		return
	end
	tier = math.clamp(math.floor(tier), 0, #Flow.Tiers)
	-- A tier needs a real chain behind it.
	if #state.Chain.Actions < tier * 2 or state.Chain.Variety < math.min(tier, 4) then
		return
	end
	local profile = DataService.Get(player)
	if profile and tier > (profile.Stats.BestFlowTier or 0) then
		profile.Stats.BestFlowTier = tier
		Events.StatChanged:Fire(player, "BestFlowTier")
	end
	Events.FlowTier:Fire(player, tier, state.District)
end

function MovementGuard.Start()
	Net.On("Move.State", onState)
	Net.On("Move.Action", onAction)
	Net.On("Move.Fall", onFall)
	Net.On("Move.Flow", onFlow)

	local function add(player: Player)
		states[player] = {
			Samples = {},
			Allowance = nil,
			Strikes = {},
			Chain = { Actions = {}, Last = 0, Seen = {}, Variety = 0 },
			District = nil,
		}
		player.CharacterAdded:Connect(function(character)
			local root = character:WaitForChild("HumanoidRootPart", 10)
			if root and states[player] then
				MovementGuard.AllowTeleport(player, (root :: BasePart).Position, 30)
			end
		end)
	end
	Players.PlayerAdded:Connect(add)
	for _, player in Players:GetPlayers() do
		add(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(SAMPLE_INTERVAL)
			for player, state in states do
				sample(player, state)
			end
		end
	end)
end

return MovementGuard

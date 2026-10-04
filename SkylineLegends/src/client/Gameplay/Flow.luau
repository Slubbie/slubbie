-- The flow meter: rewards varied, connected, well-executed movement.
--
-- Points come from techniques (Config/Flow), worth less when repeated and
-- more when linked quickly to the previous move. Sustained techniques (wall
-- runs, swings, ziplines...) trickle points while you hold them. Stopping
-- drains the meter; stumbles and falls break the chain outright.
--
-- During course runs the multiplied points become the run's flow score. Tier
-- changes are reported to the server, which checks them against the chain of
-- validated moves it has seen before awarding anything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FlowConfig = require(ReplicatedStorage.Shared.Config.Flow)
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local Controller = require(script.Parent.Parent.Movement.Controller)

local Flow = {}

Flow.Meter = 0
Flow.Tier = 0
Flow.Chain = {} :: { string } -- recent moves, newest last (for the HUD)
Flow.ChainCount = 0
Flow.TierChanged = Signal.new() -- (tier, previous)
Flow.Gained = Signal.new() -- (points, action, transition)
Flow.Broken = Signal.new() -- (reason, chainCount)

local recent: { string } = {}
local lastAction = -math.huge
local lastMomentum = os.clock()
local runScore = 0
local runActive = false
local bestTierThisRun = 0
local lastReportedTier = 0

local SUSTAIN_STATES: { [string]: string } = {
	WallRun = "WallRun",
	WallClimb = "WallRun",
	Climb = "Climb",
	Balance = "Balance",
	Zipline = "Zipline",
	Swing = "Swing",
	Slide = "Slide",
}

local function multiplier(): number
	local tier = FlowConfig.Tiers[Flow.Tier]
	return if tier then tier.Multiplier else 1
end

local function setTier(tier: number)
	if tier == Flow.Tier then
		return
	end
	local previous = Flow.Tier
	Flow.Tier = tier
	if runActive then
		bestTierThisRun = math.max(bestTierThisRun, tier)
	end
	Flow.TierChanged:Fire(tier, previous)
	if tier > lastReportedTier then
		lastReportedTier = tier
		Net.Send("Move.Flow", tier)
	end
end

local function add(points: number, action: string?, transition: boolean)
	Flow.Meter = math.min(Flow.Meter + points, FlowConfig.MeterMax)
	if runActive then
		runScore += points * multiplier()
	end
	setTier(FlowConfig.TierFor(Flow.Meter))
	if action then
		Flow.Gained:Fire(points, action, transition)
	end
end

function Flow.Break(reason: string)
	local count = Flow.ChainCount
	Flow.Meter = 0
	Flow.ChainCount = 0
	table.clear(recent)
	table.clear(Flow.Chain)
	lastReportedTier = 0
	setTier(0)
	if count > 0 then
		Flow.Broken:Fire(reason, count)
	end
end

local function onAction(action: string)
	local base = FlowConfig.Points[action]
	if action == "Stumble" then
		Flow.Break("Stumble")
		return
	end
	if not base then
		return
	end
	local now = os.clock()
	-- Variety: the same move again and again is worth less.
	local repeats = 0
	for i = math.max(#recent - FlowConfig.VarietyWindow + 1, 1), #recent do
		if recent[i] == action then
			repeats += 1
		end
	end
	local falloff = FlowConfig.VarietyFalloff[math.min(repeats + 1, #FlowConfig.VarietyFalloff)]
	-- Transitions: linking straight into the next move earns a bonus.
	local transition = now - lastAction <= FlowConfig.TransitionWindow and #recent > 0 and action ~= "Land" and action ~= "Jump"
	local points = base * falloff * (if transition then 1 + FlowConfig.TransitionBonus else 1)
	lastAction = now
	if action ~= "Land" and action ~= "Jump" then
		table.insert(recent, action)
		if #recent > 12 then
			table.remove(recent, 1)
		end
		table.insert(Flow.Chain, action)
		if #Flow.Chain > 6 then
			table.remove(Flow.Chain, 1)
		end
		Flow.ChainCount += 1
	end
	add(points, action, transition)
end

-- Course runs ----------------------------------------------------------------------------------

function Flow.BeginRun()
	runActive = true
	runScore = 0
	bestTierThisRun = Flow.Tier
end

function Flow.EndRun(): (number, number)
	runActive = false
	return math.floor(runScore), bestTierThisRun
end

function Flow.RunScore(): number
	return math.floor(runScore)
end

function Flow.Multiplier(): number
	return multiplier()
end

function Flow.Start()
	Controller.Action:Connect(onAction)
	Controller.Fell:Connect(function()
		Flow.Break("Fall")
	end)
	Controller.Landed:Connect(function(_, kind: string)
		if kind == "Heavy" then
			Flow.Break("Stumble")
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		local info = Controller.Info
		local now = os.clock()
		local sustain = SUSTAIN_STATES[info.State]
		if sustain then
			local rate = FlowConfig.Sustain[sustain]
			if rate then
				add(rate * dt, nil, false)
			end
			lastMomentum = now
		elseif info.Speed >= FlowConfig.MomentumSpeed or info.State == "Air" or info.State == "Vault" or info.State == "Mantle" then
			lastMomentum = now
		end
		if now - lastMomentum > FlowConfig.IdleGrace and Flow.Meter > 0 then
			Flow.Meter = math.max(Flow.Meter - FlowConfig.DrainPerSecond * dt, 0)
			setTier(FlowConfig.TierFor(Flow.Meter))
			if Flow.Meter <= 0 and Flow.ChainCount > 0 then
				Flow.ChainCount = 0
				table.clear(recent)
				table.clear(Flow.Chain)
				lastReportedTier = 0
			end
		end
		-- The chain itself lapses after a long gap between moves.
		if Flow.ChainCount > 0 and now - lastAction > FlowConfig.ChainGap * 2.5 and now - lastMomentum > FlowConfig.IdleGrace then
			Flow.ChainCount = 0
			table.clear(Flow.Chain)
		end
	end)
end

return Flow

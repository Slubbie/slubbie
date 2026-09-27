-- Presentation timing contract between server and clients.
--
-- The server dispatches each engine event, then waits Timeline.after(event)
-- seconds before sending the next one. Clients choreograph their animations to
-- fit inside the same windows, so every player sees the same beats at the same
-- time and the server never advances while an outcome is still on screen.
-- Durations never depend on hidden information (e.g. FireCommit's pause depends
-- on public tension, not on whether the cell is CHARGED).

local Instruments = require(script.Parent.Instruments)

local Timeline = {}

Timeline.Base = {
	MatchStart = 5.2,
	TrialStart = 3.0,
	LoadStartBase = 1.6,
	LoadStartPerCell = 0.34,
	DealtBase = 0.8,
	DealtPerItem = 0.22,
	TurnStart = 0.35,
	TurnContinue = 0.15,
	TurnSkipped = 1.7,
	EffectChanged = 0,
	FireLift = 1.05, -- reach, grip and aim
	FireHoldMin = 0.3, -- silence before the outcome (scaled by tension)
	FireHoldMax = 1.15,
	FireCharged = 1.35,
	FireHollow = 0.95,
	Damage = 0.45,
	DamageMirrored = 0.35,
	Heal = 0.55,
	Eliminated = 1.3,
	Echo = 0.5,
	LoadEnd = 0.9,
	TrialEnd = 4.2,
	SuddenDeath = 3.2,
	MatchEnd = 0.5,
	Forfeit = 1.4,
	Timeout = 0.7,
}

-- Seconds between FireCommit and FireResult (the silence before the outcome).
function Timeline.hold(tension: number, scale: number?): number
	local b = Timeline.Base
	return (b.FireLift + b.FireHoldMin + (b.FireHoldMax - b.FireHoldMin) * math.clamp(tension, 0, 1)) * (scale or 1)
end

-- Seconds to wait after dispatching `event` before the next one.
function Timeline.after(event, scale: number?): number
	local b = Timeline.Base
	local s = scale or 1
	local kind = event.Type
	local data = event.Public or {}
	local t
	if kind == "MatchStart" then
		t = b.MatchStart
	elseif kind == "TrialStart" then
		t = b.TrialStart
	elseif kind == "LoadStart" then
		t = b.LoadStartBase + b.LoadStartPerCell * (data.PoolSize or 4)
	elseif kind == "Dealt" then
		local most = 0
		for _, list in data.Draws or {} do
			most = math.max(most, #list)
		end
		t = most > 0 and (b.DealtBase + b.DealtPerItem * most) or 0
	elseif kind == "TurnStart" then
		t = b.TurnStart
	elseif kind == "TurnContinue" then
		t = b.TurnContinue
	elseif kind == "TurnSkipped" then
		t = b.TurnSkipped
	elseif kind == "InstrumentUsed" then
		local def = Instruments.get(data.Id)
		t = def and def.Duration or 1.5
	elseif kind == "FireCommit" then
		t = Timeline.hold(data.Tension or 0.5, 1)
	elseif kind == "FireResult" then
		t = data.Charged and b.FireCharged or b.FireHollow
	elseif kind == "Damage" then
		t = data.Mirrored and b.DamageMirrored or b.Damage
	elseif kind == "Heal" then
		t = b.Heal
	elseif kind == "Eliminated" then
		t = b.Eliminated
	elseif kind == "Echo" then
		t = b.Echo
	elseif kind == "LoadEnd" then
		t = b.LoadEnd
	elseif kind == "TrialEnd" then
		t = b.TrialEnd
	elseif kind == "SuddenDeath" then
		t = b.SuddenDeath
	elseif kind == "MatchEnd" then
		t = b.MatchEnd
	elseif kind == "Forfeit" then
		t = b.Forfeit
	elseif kind == "Timeout" then
		t = b.Timeout
	else
		t = 0
	end
	return t * s
end

-- Total time a list of events will take to present.
function Timeline.total(events, scale: number?): number
	local total = 0
	for _, e in events do
		total += Timeline.after(e, scale)
	end
	return total
end

return Timeline

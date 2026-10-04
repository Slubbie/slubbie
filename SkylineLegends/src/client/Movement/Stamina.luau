-- Stamina: the budget for sprinting, wall running, climbing, hanging and the
-- powerful aerial moves. It refills quickly on the ground once you stop
-- spending it, slowly in the air, and never while hanging or climbing.
-- Running out locks sprinting until it recovers to a threshold.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local Stamina = {}

Stamina.Value = 100
Stamina.Max = 100
Stamina.Exhausted = false
Stamina.LastSpent = -math.huge
Stamina.Refilled = Signal.new() -- () when it reaches full again
Stamina.Emptied = Signal.new() -- ()
Stamina.Denied = Signal.new() -- (cost) when a move can't be afforded

local stats: { [string]: any } = {}
local wasFull = true

function Stamina.SetStats(newStats: { [string]: any })
	stats = newStats
	local old = Stamina.Max
	Stamina.Max = stats.StaminaMax or 100
	if old ~= Stamina.Max then
		Stamina.Value = math.min(Stamina.Value + (Stamina.Max - old), Stamina.Max)
	end
end

function Stamina.Cost(name: string): number
	return (stats.Costs and stats.Costs[name]) or 0
end

function Stamina.CanAfford(name: string): boolean
	return Stamina.Value >= Stamina.Cost(name) - 0.01
end

-- Spend a one-off cost. Returns false (and spends nothing) if unaffordable.
function Stamina.Spend(name: string): boolean
	local cost = Stamina.Cost(name)
	if cost <= 0 then
		return true
	end
	if Stamina.Value < cost - 0.01 then
		Stamina.Denied:Fire(cost)
		return false
	end
	Stamina.Value -= cost
	Stamina.LastSpent = os.clock()
	wasFull = false
	return true
end

-- Continuous drain (per-second rate). Returns false once empty.
function Stamina.Drain(name: string, dt: number): boolean
	local rate = Stamina.Cost(name)
	if rate <= 0 then
		return true
	end
	Stamina.Value = math.max(Stamina.Value - rate * dt, 0)
	Stamina.LastSpent = os.clock()
	wasFull = false
	if Stamina.Value <= 0 then
		if not Stamina.Exhausted then
			Stamina.Exhausted = true
			Stamina.Emptied:Fire()
		end
		return false
	end
	return true
end

function Stamina.Refill()
	Stamina.Value = Stamina.Max
	Stamina.Exhausted = false
	wasFull = true
end

-- `mode`: "Ground" | "Air" | "None" (no regeneration while hanging/climbing).
function Stamina.Update(dt: number, mode: string)
	if mode ~= "None" and os.clock() - Stamina.LastSpent >= (stats.StaminaRegenDelay or 0.65) then
		local rate = if mode == "Ground" then (stats.StaminaRegenGround or 34) else (stats.StaminaRegenAir or 10)
		Stamina.Value = math.min(Stamina.Value + rate * dt, Stamina.Max)
	end
	if Stamina.Exhausted and Stamina.Value >= (stats.StaminaExhaustedUntil or 25) then
		Stamina.Exhausted = false
	end
	if Stamina.Value >= Stamina.Max - 0.01 then
		if not wasFull then
			wasFull = true
			Stamina.Refilled:Fire()
		end
	end
end

return Stamina

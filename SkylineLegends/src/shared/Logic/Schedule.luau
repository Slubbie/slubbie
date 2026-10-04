-- Deterministic timelines for every timed mechanism (doors, vents, lasers,
-- retracting bridges, blinking holograms, gusts, moving platforms).
--
-- Everything is a pure function of shared server time, so every client sees
-- the same door open at the same moment, and courses behave identically on
-- every server.

local Schedule = {}

-- 0..1 position through a repeating cycle.
function Schedule.Fraction(t: number, period: number, phase: number?): number
	if period <= 0 then
		return 0
	end
	return ((t / period) + (phase or 0)) % 1
end

-- Smooth there-and-back motion: 0 → 1 → 0 over one period.
function Schedule.PingPong(t: number, period: number, phase: number?): number
	local f = Schedule.Fraction(t, period, phase)
	return 0.5 - 0.5 * math.cos(f * math.pi * 2)
end

-- Move, pause at each end, move back. `hold` is the fraction of the period
-- spent paused (split between both ends), giving players a beat to board.
function Schedule.Shuttle(t: number, period: number, phase: number?, hold: number?): number
	local f = Schedule.Fraction(t, period, phase)
	local pause = math.clamp(hold or 0.3, 0, 0.9) / 2
	local travel = 0.5 - pause
	if f < pause then
		return 0
	elseif f < pause + travel then
		local a = (f - pause) / travel
		return a * a * (3 - 2 * a)
	elseif f < pause * 2 + travel then
		return 1
	else
		local a = (f - pause * 2 - travel) / travel
		return 1 - a * a * (3 - 2 * a)
	end
end

-- On/off cycle with a warning period before each switch.
-- Returns (on, warning, secondsUntilChange).
function Schedule.Cycle(
	t: number,
	period: number,
	onFraction: number,
	phase: number?,
	warn: number?
): (boolean, boolean, number)
	local f = Schedule.Fraction(t, period, phase)
	local onTime = period * onFraction
	local now = f * period
	local on = now < onTime
	local untilChange = if on then onTime - now else period - now
	local warning = untilChange <= (warn or 0.6)
	return on, warning, untilChange
end

-- Angle (radians) of a pendulum swing.
function Schedule.Pendulum(t: number, period: number, amplitude: number, phase: number?): number
	local f = Schedule.Fraction(t, period, phase)
	return math.sin(f * math.pi * 2) * amplitude
end

-- Shared clock. workspace:GetServerTimeNow() is synchronised across clients.
function Schedule.Now(): number
	return workspace:GetServerTimeNow()
end

return Schedule

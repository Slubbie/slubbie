-- The movement envelope: how far and how high the standard attributes can go.
--
-- Course segments, tower floors and endless sections size every gap and wall
-- from these numbers (never from hand-typed distances), so every obstacle in the
-- game stays physically achievable. Values are conservative: they assume
-- reasonable, not frame-perfect, execution.

local MovementConfig = require(script.Parent.Parent.Config.Movement)

type Stats = typeof(MovementConfig)

local Reach = {}

-- Edge allowance: you take off a little before the edge and need your feet
-- over the far platform to land.
Reach.EdgeMargin = 1.2

local function stats(s: Stats?): Stats
	return s or MovementConfig
end

-- Seconds of flight after leaving the ground at vertical speed `vy`, landing
-- `dy` studs higher (negative = lower). nil if the height can't be reached.
function Reach.AirTime(vy: number, dy: number, s: Stats?): number?
	local m = stats(s)
	local up = m.Gravity
	local down = m.Gravity * m.FallGravityMultiplier
	local apex = vy * vy / (2 * up)
	if dy > apex then
		return nil
	end
	return vy / up + math.sqrt(2 * (apex - dy) / down)
end

function Reach.JumpApex(s: Stats?): number
	local m = stats(s)
	return m.JumpVelocity ^ 2 / (2 * m.Gravity)
end

function Reach.DoubleJumpApex(s: Stats?): number
	local m = stats(s)
	return Reach.JumpApex(m) + m.DoubleJumpVelocity ^ 2 / (2 * m.Gravity)
end

-- Longest edge-to-edge gap clearable with a plain jump at `speed`.
function Reach.JumpDistance(dy: number, speed: number?, s: Stats?): number
	local m = stats(s)
	local t = Reach.AirTime(m.JumpVelocity, dy, m)
	if not t then
		return 0
	end
	return math.max((speed or m.SprintSpeed) * t - Reach.EdgeMargin, 0)
end

-- With a double jump at the top of the first jump.
function Reach.DoubleJumpDistance(dy: number, speed: number?, s: Stats?): number
	local m = stats(s)
	local first = m.JumpVelocity / m.Gravity
	local apex = Reach.JumpApex(m)
	local rest = Reach.AirTime(m.DoubleJumpVelocity, dy - apex, m)
	if not rest then
		return 0
	end
	return math.max((speed or m.SprintSpeed) * (first + rest) - Reach.EdgeMargin, 0)
end

-- Jump, then dash at the apex.
function Reach.DashJumpDistance(dy: number, speed: number?, s: Stats?): number
	local m = stats(s)
	local v = speed or m.SprintSpeed
	local first = m.JumpVelocity / m.Gravity
	local apex = Reach.JumpApex(m) + m.DashLift * m.DashTime
	local rest = Reach.AirTime(m.DashLift, dy - apex, m)
	if not rest then
		return 0
	end
	local exitSpeed = math.max(v, m.DashSpeed * 0.6)
	return math.max(v * first + m.DashSpeed * m.DashTime + exitSpeed * rest - Reach.EdgeMargin, 0)
end

-- Highest ledge (above the floor you jump from) a jump can catch.
function Reach.LedgeHeight(s: Stats?): number
	local m = stats(s)
	return m.RootHeight + Reach.JumpApex(m) + m.LedgeMaxAbove
end

-- Highest ledge reachable by running up a wall and catching the top.
function Reach.WallClimbHeight(s: Stats?): number
	local m = stats(s)
	local t = m.WallClimbTime
	local rise = m.WallClimbSpeed * t - 0.5 * m.WallClimbGravity * t * t
	local vy = math.max(m.WallClimbSpeed - m.WallClimbGravity * t, 0)
	rise += vy * vy / (2 * m.Gravity)
	return m.RootHeight + rise + m.LedgeMaxAbove
end

-- Height gained per kick when alternating between two walls `width` apart.
function Reach.ShaftKickRise(width: number, s: Stats?): number
	local m = stats(s)
	local travel = math.max(width - 2, 1) / m.WallKickOut
	return m.WallKickUp * travel - 0.5 * m.Gravity * travel * travel
end

-- Distance along the wall and height lost after wall running for `seconds`.
function Reach.WallRun(seconds: number, s: Stats?): (number, number)
	local m = stats(s)
	local dt = 1 / 120
	local t, y, vy = 0, 0, m.WallRunStartLift
	while t < seconds do
		local g = m.WallRunGravity + (m.WallRunGravityEnd - m.WallRunGravity) * math.min(t / m.WallRunMaxTime, 1)
		vy -= g * dt
		y += vy * dt
		t += dt
	end
	return m.WallRunSpeed * seconds, -y
end

-- Root rise from a bounce or vent launch of vertical speed `vy`.
function Reach.LaunchHeight(vy: number, s: Stats?): number
	local m = stats(s)
	return vy * vy / (2 * m.Gravity)
end

-- Launch speed needed to rise `height` studs (with a safety margin).
function Reach.LaunchSpeedFor(height: number, s: Stats?): number
	local m = stats(s)
	return math.sqrt(2 * m.Gravity * (height + 3))
end

return Reach

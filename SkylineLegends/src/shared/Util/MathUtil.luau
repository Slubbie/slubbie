-- Small vector and number helpers shared by client and server.

local MathUtil = {}

function MathUtil.Flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function MathUtil.FlatUnit(v: Vector3, fallback: Vector3?): Vector3
	local flat = Vector3.new(v.X, 0, v.Z)
	if flat.Magnitude < 1e-4 then
		return fallback or Vector3.zAxis
	end
	return flat.Unit
end

-- Frame-rate independent smoothing toward a target (numbers, Vector3s, CFrames via Lerp).
function MathUtil.Damp(current: any, target: any, rate: number, dt: number): any
	local alpha = 1 - math.exp(-rate * dt)
	if type(current) == "number" then
		return current + (target - current) * alpha
	end
	return current:Lerp(target, alpha)
end

-- Move a number toward a target by at most `step`.
function MathUtil.Approach(current: number, target: number, step: number): number
	if current < target then
		return math.min(current + step, target)
	end
	return math.max(current - step, target)
end

-- Turns unit vector `from` toward unit vector `to` by at most `maxAngle` radians.
function MathUtil.RotateToward(from: Vector3, to: Vector3, maxAngle: number): Vector3
	local angle = math.acos(math.clamp(from:Dot(to), -1, 1))
	if angle <= maxAngle then
		return to
	end
	local axis = from:Cross(to)
	if axis.Magnitude < 1e-5 then
		axis = Vector3.yAxis
	end
	return CFrame.fromAxisAngle(axis.Unit, maxAngle):VectorToWorldSpace(from)
end

-- Rotation that turns unit vector `a` into unit vector `b`.
function MathUtil.RotationBetween(a: Vector3, b: Vector3): CFrame
	local dot = math.clamp(a:Dot(b), -1, 1)
	local axis = a:Cross(b)
	if axis.Magnitude < 1e-5 then
		if dot > 0 then
			return CFrame.identity
		end
		return CFrame.Angles(math.pi, 0, 0)
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
end

-- Closest point on segment AB to P, plus the 0..1 parameter along it.
function MathUtil.ClosestOnSegment(a: Vector3, b: Vector3, p: Vector3): (Vector3, number)
	local ab = b - a
	local lengthSquared = ab:Dot(ab)
	if lengthSquared < 1e-6 then
		return a, 0
	end
	local t = math.clamp((p - a):Dot(ab) / lengthSquared, 0, 1)
	return a + ab * t, t
end

-- Smoothstep easing.
function MathUtil.Smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

function MathUtil.EaseOutCubic(t: number): number
	t = math.clamp(t, 0, 1)
	return 1 - (1 - t) ^ 3
end

-- Quadratic Bezier.
function MathUtil.Bezier(a: Vector3, control: Vector3, b: Vector3, t: number): Vector3
	local u = 1 - t
	return a * (u * u) + control * (2 * u * t) + b * (t * t)
end

-- Yaw-only CFrame looking along a direction from a position.
function MathUtil.FlatLook(position: Vector3, direction: Vector3): CFrame
	local flat = MathUtil.FlatUnit(direction)
	return CFrame.lookAt(position, position + flat)
end

-- Whether `point` lies inside a part-shaped box (cframe + size), with padding.
function MathUtil.InBox(cframe: CFrame, size: Vector3, point: Vector3, pad: number?): boolean
	local p = cframe:PointToObjectSpace(point)
	local half = size / 2 + Vector3.one * (pad or 0)
	return math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z
end

return MathUtil

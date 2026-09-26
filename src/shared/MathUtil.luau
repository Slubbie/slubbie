local MathUtil = {}

-- Drops the vertical component.
function MathUtil.Flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Frame-rate independent smoothing toward a target. Works on numbers and Vector3s.
-- Higher rate = snappier.
function MathUtil.Damp(current, target, rate: number, dt: number)
	return current + (target - current) * (1 - math.exp(-rate * dt))
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

return MathUtil

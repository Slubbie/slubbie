--# selene: allow(global_usage, unused_variable, shadowing)
-- Roblox datatypes for the headless runtime mock: Vector3, Vector2, CFrame,
-- Color3, UDim, UDim2, NumberSequence(+Keypoint), ColorSequence(+Keypoint),
-- NumberRange, TweenInfo, Random, Rect, Font, Enum and typeof.
--
-- Values are immutable tables with a metatable carrying __type (read by
-- typeof). The maths follows the engine's conventions (column-vector CFrames,
-- Angles = X then Y then Z, LookVector = -Z column).

local Types = {}

local sqrt, abs, sin, cos, atan2, floor = math.sqrt, math.abs, math.sin, math.cos, math.atan2, math.floor

local function typeName(v): string
	local t = type(v)
	if t == "table" then
		local mt = getmetatable(v)
		if type(mt) == "table" and mt.__type then
			return mt.__type
		end
	end
	return t
end
Types.typeof = typeName

---------------------------------------------------------------------------
-- Vector3
---------------------------------------------------------------------------

local V3 = {}
local V3mt = { __type = "Vector3" }
local function v3(x, y, z)
	return setmetatable({ X = x, Y = y, Z = z }, V3mt)
end
local v3computed = {
	Magnitude = function(a)
		return sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z)
	end,
	Unit = function(a)
		local m = sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z)
		if m == 0 then
			return v3(0 / 0, 0 / 0, 0 / 0)
		end
		return v3(a.X / m, a.Y / m, a.Z / m)
	end,
	x = function(a)
		return a.X
	end,
	y = function(a)
		return a.Y
	end,
	z = function(a)
		return a.Z
	end,
}
local v3methods = {
	Dot = function(a, b)
		return a.X * b.X + a.Y * b.Y + a.Z * b.Z
	end,
	Cross = function(a, b)
		return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
	end,
	Lerp = function(a, b, t)
		return v3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t)
	end,
	FuzzyEq = function(a, b, eps)
		eps = eps or 1e-5
		return abs(a.X - b.X) <= eps and abs(a.Y - b.Y) <= eps and abs(a.Z - b.Z) <= eps
	end,
	Abs = function(a)
		return v3(abs(a.X), abs(a.Y), abs(a.Z))
	end,
	Min = function(a, b)
		return v3(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
	end,
	Max = function(a, b)
		return v3(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
	end,
	Angle = function(a, b)
		local d = (a.X * b.X + a.Y * b.Y + a.Z * b.Z) / (a.Magnitude * b.Magnitude)
		return math.acos(math.clamp(d, -1, 1))
	end,
}
V3mt.__index = function(self, key)
	local c = v3computed[key]
	if c then
		return c(self)
	end
	local m = v3methods[key]
	if m then
		return m
	end
	error(tostring(key) .. " is not a valid member of Vector3", 2)
end
V3mt.__newindex = function()
	error("Vector3 is immutable", 2)
end
V3mt.__add = function(a, b)
	if typeName(a) ~= "Vector3" or typeName(b) ~= "Vector3" then
		error(
			"attempt to perform arithmetic (add) on Vector3 and " .. typeName(if typeName(a) == "Vector3" then b else a),
			2
		)
	end
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3mt.__sub = function(a, b)
	if typeName(a) ~= "Vector3" or typeName(b) ~= "Vector3" then
		error(
			"attempt to perform arithmetic (sub) on Vector3 and " .. typeName(if typeName(a) == "Vector3" then b else a),
			2
		)
	end
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3mt.__mul = function(a, b)
	if type(a) == "number" then
		return v3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	elseif typeName(a) == "Vector3" and typeName(b) == "Vector3" then
		return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
	end
	error("attempt to perform arithmetic (mul) on Vector3 and " .. typeName(b), 2)
end
V3mt.__div = function(a, b)
	if type(b) == "number" then
		return v3(a.X / b, a.Y / b, a.Z / b)
	elseif typeName(b) == "Vector3" then
		return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
	end
	error("attempt to perform arithmetic (div) on Vector3 and " .. typeName(b), 2)
end
V3mt.__idiv = function(a, b)
	return v3(floor(a.X / b), floor(a.Y / b), floor(a.Z / b))
end
V3mt.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3mt.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3mt.__tostring = function(a)
	return string.format("%g, %g, %g", a.X, a.Y, a.Z)
end
V3.new = function(x, y, z)
	return v3(x or 0, y or 0, z or 0)
end
V3.zero = v3(0, 0, 0)
V3.one = v3(1, 1, 1)
V3.xAxis = v3(1, 0, 0)
V3.yAxis = v3(0, 1, 0)
V3.zAxis = v3(0, 0, 1)
V3.FromNormalId = function(normal)
	local map = {
		Top = v3(0, 1, 0),
		Bottom = v3(0, -1, 0),
		Front = v3(0, 0, -1),
		Back = v3(0, 0, 1),
		Left = v3(-1, 0, 0),
		Right = v3(1, 0, 0),
	}
	return map[normal.Name]
end
Types.Vector3 = V3
Types.v3 = v3

---------------------------------------------------------------------------
-- Vector2
---------------------------------------------------------------------------

local V2 = {}
local V2mt = { __type = "Vector2" }
local function v2(x, y)
	return setmetatable({ X = x, Y = y }, V2mt)
end
V2mt.__index = function(self, key)
	if key == "Magnitude" then
		return sqrt(self.X * self.X + self.Y * self.Y)
	elseif key == "Unit" then
		local m = sqrt(self.X * self.X + self.Y * self.Y)
		return v2(self.X / m, self.Y / m)
	elseif key == "Dot" then
		return function(a, b)
			return a.X * b.X + a.Y * b.Y
		end
	elseif key == "Lerp" then
		return function(a, b, t)
			return v2(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t)
		end
	elseif key == "Cross" then
		return function(a, b)
			return a.X * b.Y - a.Y * b.X
		end
	elseif key == "Min" then
		return function(a, b)
			return v2(math.min(a.X, b.X), math.min(a.Y, b.Y))
		end
	elseif key == "Max" then
		return function(a, b)
			return v2(math.max(a.X, b.X), math.max(a.Y, b.Y))
		end
	end
	error(tostring(key) .. " is not a valid member of Vector2", 2)
end
V2mt.__add = function(a, b)
	return v2(a.X + b.X, a.Y + b.Y)
end
V2mt.__sub = function(a, b)
	return v2(a.X - b.X, a.Y - b.Y)
end
V2mt.__mul = function(a, b)
	if type(a) == "number" then
		return v2(a * b.X, a * b.Y)
	elseif type(b) == "number" then
		return v2(a.X * b, a.Y * b)
	end
	return v2(a.X * b.X, a.Y * b.Y)
end
V2mt.__div = function(a, b)
	if type(b) == "number" then
		return v2(a.X / b, a.Y / b)
	end
	return v2(a.X / b.X, a.Y / b.Y)
end
V2mt.__unm = function(a)
	return v2(-a.X, -a.Y)
end
V2mt.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
V2mt.__tostring = function(a)
	return string.format("%g, %g", a.X, a.Y)
end
V2.new = function(x, y)
	return v2(x or 0, y or 0)
end
V2.zero = v2(0, 0)
V2.one = v2(1, 1)
V2.xAxis = v2(1, 0)
V2.yAxis = v2(0, 1)
Types.Vector2 = V2

---------------------------------------------------------------------------
-- CFrame (position + 3x3 rotation, row-major r[1..9])
---------------------------------------------------------------------------

local CF = {}
local CFmt = { __type = "CFrame" }
local function cf(x, y, z, r)
	return setmetatable({ x = x, y = y, z = z, r = r }, CFmt)
end
local IDR = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }

local function mulR(a, b)
	return {
		a[1] * b[1] + a[2] * b[4] + a[3] * b[7],
		a[1] * b[2] + a[2] * b[5] + a[3] * b[8],
		a[1] * b[3] + a[2] * b[6] + a[3] * b[9],
		a[4] * b[1] + a[5] * b[4] + a[6] * b[7],
		a[4] * b[2] + a[5] * b[5] + a[6] * b[8],
		a[4] * b[3] + a[5] * b[6] + a[6] * b[9],
		a[7] * b[1] + a[8] * b[4] + a[9] * b[7],
		a[7] * b[2] + a[8] * b[5] + a[9] * b[8],
		a[7] * b[3] + a[8] * b[6] + a[9] * b[9],
	}
end

local function transpose(r)
	return { r[1], r[4], r[7], r[2], r[5], r[8], r[3], r[6], r[9] }
end

local function rotX(a)
	local c, s = cos(a), sin(a)
	return { 1, 0, 0, 0, c, -s, 0, s, c }
end
local function rotY(a)
	local c, s = cos(a), sin(a)
	return { c, 0, s, 0, 1, 0, -s, 0, c }
end
local function rotZ(a)
	local c, s = cos(a), sin(a)
	return { c, -s, 0, s, c, 0, 0, 0, 1 }
end

local function toQuat(r)
	local trace = r[1] + r[5] + r[9]
	local w, x, y, z
	if trace > 0 then
		local s = sqrt(trace + 1) * 2
		w = 0.25 * s
		x = (r[8] - r[6]) / s
		y = (r[3] - r[7]) / s
		z = (r[4] - r[2]) / s
	elseif r[1] > r[5] and r[1] > r[9] then
		local s = sqrt(1 + r[1] - r[5] - r[9]) * 2
		w = (r[8] - r[6]) / s
		x = 0.25 * s
		y = (r[2] + r[4]) / s
		z = (r[3] + r[7]) / s
	elseif r[5] > r[9] then
		local s = sqrt(1 + r[5] - r[1] - r[9]) * 2
		w = (r[3] - r[7]) / s
		x = (r[2] + r[4]) / s
		y = 0.25 * s
		z = (r[6] + r[8]) / s
	else
		local s = sqrt(1 + r[9] - r[1] - r[5]) * 2
		w = (r[4] - r[2]) / s
		x = (r[3] + r[7]) / s
		y = (r[6] + r[8]) / s
		z = 0.25 * s
	end
	return w, x, y, z
end

local function fromQuat(w, x, y, z)
	local n = sqrt(w * w + x * x + y * y + z * z)
	if n == 0 then
		return table.clone(IDR)
	end
	w, x, y, z = w / n, x / n, y / n, z / n
	return {
		1 - 2 * (y * y + z * z),
		2 * (x * y - z * w),
		2 * (x * z + y * w),
		2 * (x * y + z * w),
		1 - 2 * (x * x + z * z),
		2 * (y * z - x * w),
		2 * (x * z - y * w),
		2 * (y * z + x * w),
		1 - 2 * (x * x + y * y),
	}
end

local function cfMul(a, b)
	local ra = a.r
	local bx, by, bz = b.x, b.y, b.z
	return cf(
		a.x + ra[1] * bx + ra[2] * by + ra[3] * bz,
		a.y + ra[4] * bx + ra[5] * by + ra[6] * bz,
		a.z + ra[7] * bx + ra[8] * by + ra[9] * bz,
		mulR(ra, b.r)
	)
end

local function cfInverse(a)
	local rt = transpose(a.r)
	return cf(
		-(rt[1] * a.x + rt[2] * a.y + rt[3] * a.z),
		-(rt[4] * a.x + rt[5] * a.y + rt[6] * a.z),
		-(rt[7] * a.x + rt[8] * a.y + rt[9] * a.z),
		rt
	)
end

local function pointToWorld(a, v)
	local r = a.r
	return v3(
		a.x + r[1] * v.X + r[2] * v.Y + r[3] * v.Z,
		a.y + r[4] * v.X + r[5] * v.Y + r[6] * v.Z,
		a.z + r[7] * v.X + r[8] * v.Y + r[9] * v.Z
	)
end
local function vectorToWorld(a, v)
	local r = a.r
	return v3(
		r[1] * v.X + r[2] * v.Y + r[3] * v.Z,
		r[4] * v.X + r[5] * v.Y + r[6] * v.Z,
		r[7] * v.X + r[8] * v.Y + r[9] * v.Z
	)
end
local function vectorToObject(a, v)
	local r = a.r
	return v3(
		r[1] * v.X + r[4] * v.Y + r[7] * v.Z,
		r[2] * v.X + r[5] * v.Y + r[8] * v.Z,
		r[3] * v.X + r[6] * v.Y + r[9] * v.Z
	)
end

local function checkFinite(a)
	for _, n in { a.x, a.y, a.z } do
		if n ~= n then
			error("CFrame has a NaN component", 3)
		end
	end
	return a
end

local cfmethods
cfmethods = {
	Inverse = function(a)
		return cfInverse(a)
	end,
	Lerp = function(a, b, t)
		local w1, x1, y1, z1 = toQuat(a.r)
		local w2, x2, y2, z2 = toQuat(b.r)
		local d = w1 * w2 + x1 * x2 + y1 * y2 + z1 * z2
		if d < 0 then
			w2, x2, y2, z2 = -w2, -x2, -y2, -z2
			d = -d
		end
		local w, x, y, z
		if d > 0.9995 then
			w, x, y, z = w1 + (w2 - w1) * t, x1 + (x2 - x1) * t, y1 + (y2 - y1) * t, z1 + (z2 - z1) * t
		else
			local theta = math.acos(math.clamp(d, -1, 1))
			local s = sin(theta)
			local k1, k2 = sin((1 - t) * theta) / s, sin(t * theta) / s
			w, x, y, z = w1 * k1 + w2 * k2, x1 * k1 + x2 * k2, y1 * k1 + y2 * k2, z1 * k1 + z2 * k2
		end
		return checkFinite(
			cf(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t, fromQuat(w, x, y, z))
		)
	end,
	ToObjectSpace = function(a, b)
		return cfMul(cfInverse(a), b)
	end,
	ToWorldSpace = function(a, b)
		return cfMul(a, b)
	end,
	PointToObjectSpace = function(a, v)
		return vectorToObject(a, v3(v.X - a.x, v.Y - a.y, v.Z - a.z))
	end,
	PointToWorldSpace = function(a, v)
		return pointToWorld(a, v)
	end,
	VectorToWorldSpace = function(a, v)
		return vectorToWorld(a, v)
	end,
	VectorToObjectSpace = function(a, v)
		return vectorToObject(a, v)
	end,
	GetComponents = function(a)
		local r = a.r
		return a.x, a.y, a.z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]
	end,
	ToEulerAnglesXYZ = function(a)
		local r = a.r
		local y = math.asin(math.clamp(r[3], -1, 1))
		local x = atan2(-r[6], r[9])
		local z = atan2(-r[2], r[1])
		return x, y, z
	end,
	ToEulerAnglesYXZ = function(a)
		local r = a.r
		local x = math.asin(math.clamp(-r[6], -1, 1))
		local y = atan2(r[3], r[9])
		local z = atan2(r[4], r[5])
		return x, y, z
	end,
	ToOrientation = function(a)
		return cfmethods.ToEulerAnglesYXZ(a)
	end,
	ToAxisAngle = function(a)
		local w, x, y, z = toQuat(a.r)
		local angle = 2 * math.acos(math.clamp(w, -1, 1))
		local s = sqrt(math.max(1 - w * w, 0))
		if s < 1e-6 then
			return v3(1, 0, 0), 0
		end
		return v3(x / s, y / s, z / s), angle
	end,
	Orthonormalize = function(a)
		return a
	end,
	FuzzyEq = function(a, b, eps)
		eps = eps or 1e-5
		for i = 1, 9 do
			if abs(a.r[i] - b.r[i]) > eps then
				return false
			end
		end
		return abs(a.x - b.x) <= eps and abs(a.y - b.y) <= eps and abs(a.z - b.z) <= eps
	end,
}
cfmethods.components = cfmethods.GetComponents
cfmethods.inverse = cfmethods.Inverse
cfmethods.lerp = cfmethods.Lerp
cfmethods.toObjectSpace = cfmethods.ToObjectSpace
cfmethods.pointToObjectSpace = cfmethods.PointToObjectSpace

CFmt.__index = function(a, key)
	if key == "Position" or key == "p" then
		return v3(a.x, a.y, a.z)
	elseif key == "X" then
		return a.x
	elseif key == "Y" then
		return a.y
	elseif key == "Z" then
		return a.z
	elseif key == "Rotation" then
		return cf(0, 0, 0, a.r)
	elseif key == "LookVector" then
		return v3(-a.r[3], -a.r[6], -a.r[9])
	elseif key == "RightVector" or key == "XVector" then
		return v3(a.r[1], a.r[4], a.r[7])
	elseif key == "UpVector" or key == "YVector" then
		return v3(a.r[2], a.r[5], a.r[8])
	elseif key == "ZVector" then
		return v3(a.r[3], a.r[6], a.r[9])
	end
	local m = cfmethods[key]
	if m then
		return m
	end
	error(tostring(key) .. " is not a valid member of CFrame", 2)
end
CFmt.__newindex = function()
	error("CFrame is immutable", 2)
end
CFmt.__mul = function(a, b)
	local tb = typeName(b)
	if tb == "CFrame" then
		return checkFinite(cfMul(a, b))
	elseif tb == "Vector3" then
		return pointToWorld(a, b)
	end
	error("attempt to perform arithmetic (mul) on CFrame and " .. tb, 2)
end
CFmt.__add = function(a, b)
	if typeName(b) ~= "Vector3" then
		error("attempt to perform arithmetic (add) on CFrame and " .. typeName(b), 2)
	end
	return cf(a.x + b.X, a.y + b.Y, a.z + b.Z, a.r)
end
CFmt.__sub = function(a, b)
	if typeName(b) ~= "Vector3" then
		error("attempt to perform arithmetic (sub) on CFrame and " .. typeName(b), 2)
	end
	return cf(a.x - b.X, a.y - b.Y, a.z - b.Z, a.r)
end
CFmt.__eq = function(a, b)
	if a.x ~= b.x or a.y ~= b.y or a.z ~= b.z then
		return false
	end
	for i = 1, 9 do
		if a.r[i] ~= b.r[i] then
			return false
		end
	end
	return true
end
CFmt.__tostring = function(a)
	local r = a.r
	return string.format(
		"%g, %g, %g, %g, %g, %g, %g, %g, %g, %g, %g, %g",
		a.x,
		a.y,
		a.z,
		r[1],
		r[2],
		r[3],
		r[4],
		r[5],
		r[6],
		r[7],
		r[8],
		r[9]
	)
end

CF.new = function(...)
	local n = select("#", ...)
	local a = { ... }
	if n == 0 then
		return cf(0, 0, 0, IDR)
	elseif n == 1 then
		local p = a[1]
		return cf(p.X, p.Y, p.Z, IDR)
	elseif n == 2 then
		return CF.lookAt(a[1], a[2])
	elseif n == 3 then
		return cf(a[1], a[2], a[3], IDR)
	elseif n == 7 then
		return cf(a[1], a[2], a[3], fromQuat(a[7], a[4], a[5], a[6]))
	elseif n == 12 then
		return cf(a[1], a[2], a[3], { a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12] })
	end
	error("Invalid number of arguments to CFrame.new: " .. n, 2)
end
CF.identity = cf(0, 0, 0, IDR)
CF.Angles = function(x, y, z)
	return cf(0, 0, 0, mulR(mulR(rotX(x or 0), rotY(y or 0)), rotZ(z or 0)))
end
CF.fromEulerAnglesXYZ = CF.Angles
CF.fromEulerAnglesYXZ = function(x, y, z)
	return cf(0, 0, 0, mulR(mulR(rotY(y or 0), rotX(x or 0)), rotZ(z or 0)))
end
CF.fromOrientation = CF.fromEulerAnglesYXZ
CF.fromAxisAngle = function(axis, angle)
	local u = axis.Unit
	local half = angle / 2
	local s = sin(half)
	return cf(0, 0, 0, fromQuat(cos(half), u.X * s, u.Y * s, u.Z * s))
end
CF.lookAt = function(at, target, up)
	up = up or V3.yAxis
	local look = target - at
	if look.Magnitude < 1e-9 then
		return cf(at.X, at.Y, at.Z, IDR)
	end
	look = look.Unit
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		right = look:Cross(V3.zAxis)
		if right.Magnitude < 1e-6 then
			right = look:Cross(V3.xAxis)
		end
	end
	right = right.Unit
	local upv = right:Cross(look)
	return cf(at.X, at.Y, at.Z, { right.X, upv.X, -look.X, right.Y, upv.Y, -look.Y, right.Z, upv.Z, -look.Z })
end
CF.fromMatrix = function(pos, vx, vy, vz)
	vz = vz or vx:Cross(vy).Unit
	return cf(pos.X, pos.Y, pos.Z, { vx.X, vy.X, vz.X, vx.Y, vy.Y, vz.Y, vx.Z, vy.Z, vz.Z })
end
Types.CFrame = CF

---------------------------------------------------------------------------
-- Color3
---------------------------------------------------------------------------

local C3 = {}
local C3mt = { __type = "Color3" }
local function c3(r, g, b)
	return setmetatable({ R = r, G = g, B = b }, C3mt)
end
C3mt.__index = function(self, key)
	if key == "Lerp" then
		return function(a, b, t)
			return c3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
		end
	elseif key == "ToHex" then
		return function(a)
			local function h(v)
				return string.format("%02x", math.clamp(floor(v * 255 + 0.5), 0, 255))
			end
			return h(a.R) .. h(a.G) .. h(a.B)
		end
	elseif key == "ToHSV" then
		return function(a)
			local mx, mn = math.max(a.R, a.G, a.B), math.min(a.R, a.G, a.B)
			local d = mx - mn
			local h = 0
			if d > 0 then
				if mx == a.R then
					h = ((a.G - a.B) / d) % 6
				elseif mx == a.G then
					h = (a.B - a.R) / d + 2
				else
					h = (a.R - a.G) / d + 4
				end
				h /= 6
			end
			return h, if mx == 0 then 0 else d / mx, mx
		end
	end
	error(tostring(key) .. " is not a valid member of Color3", 2)
end
C3mt.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
C3mt.__tostring = function(a)
	return string.format("%g, %g, %g", a.R, a.G, a.B)
end
C3.new = function(r, g, b)
	return c3(r or 0, g or 0, b or 0)
end
C3.fromRGB = function(r, g, b)
	return c3((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end
C3.fromHSV = function(h, s, v)
	local i = floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	i %= 6
	if i == 0 then
		return c3(v, t, p)
	elseif i == 1 then
		return c3(q, v, p)
	elseif i == 2 then
		return c3(p, v, t)
	elseif i == 3 then
		return c3(p, q, v)
	elseif i == 4 then
		return c3(t, p, v)
	end
	return c3(v, p, q)
end
C3.fromHex = function(hex)
	hex = string.gsub(hex, "#", "")
	if #hex ~= 6 then
		error("Unable to convert characters to hex value", 2)
	end
	return C3.fromRGB(
		tonumber(string.sub(hex, 1, 2), 16),
		tonumber(string.sub(hex, 3, 4), 16),
		tonumber(string.sub(hex, 5, 6), 16)
	)
end
Types.Color3 = C3

---------------------------------------------------------------------------
-- UDim / UDim2
---------------------------------------------------------------------------

local UD = {}
local UDmt = { __type = "UDim" }
local function udim(s, o)
	return setmetatable({ Scale = s, Offset = o }, UDmt)
end
UDmt.__index = function(_, key)
	error(tostring(key) .. " is not a valid member of UDim", 2)
end
UDmt.__add = function(a, b)
	return udim(a.Scale + b.Scale, a.Offset + b.Offset)
end
UDmt.__sub = function(a, b)
	return udim(a.Scale - b.Scale, a.Offset - b.Offset)
end
UDmt.__eq = function(a, b)
	return a.Scale == b.Scale and a.Offset == b.Offset
end
UD.new = function(s, o)
	return udim(s or 0, o or 0)
end
Types.UDim = UD

local U2 = {}
local U2mt = { __type = "UDim2" }
local function udim2(xs, xo, ys, yo)
	return setmetatable({ X = udim(xs, xo), Y = udim(ys, yo) }, U2mt)
end
U2mt.__index = function(self, key)
	if key == "Width" then
		return self.X
	elseif key == "Height" then
		return self.Y
	elseif key == "Lerp" then
		return function(a, b, t)
			return udim2(
				a.X.Scale + (b.X.Scale - a.X.Scale) * t,
				a.X.Offset + (b.X.Offset - a.X.Offset) * t,
				a.Y.Scale + (b.Y.Scale - a.Y.Scale) * t,
				a.Y.Offset + (b.Y.Offset - a.Y.Offset) * t
			)
		end
	end
	error(tostring(key) .. " is not a valid member of UDim2", 2)
end
U2mt.__add = function(a, b)
	return udim2(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset)
end
U2mt.__sub = function(a, b)
	return udim2(a.X.Scale - b.X.Scale, a.X.Offset - b.X.Offset, a.Y.Scale - b.Y.Scale, a.Y.Offset - b.Y.Offset)
end
U2mt.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
U2mt.__tostring = function(a)
	return string.format("{%g, %g}, {%g, %g}", a.X.Scale, a.X.Offset, a.Y.Scale, a.Y.Offset)
end
U2.new = function(xs, xo, ys, yo)
	if typeName(xs) == "UDim" then
		return udim2(xs.Scale, xs.Offset, xo.Scale, xo.Offset)
	end
	return udim2(xs or 0, xo or 0, ys or 0, yo or 0)
end
U2.fromScale = function(x, y)
	return udim2(x or 0, 0, y or 0, 0)
end
U2.fromOffset = function(x, y)
	return udim2(0, x or 0, 0, y or 0)
end
Types.UDim2 = U2

---------------------------------------------------------------------------
-- Sequences, ranges, tween info, rect, font
---------------------------------------------------------------------------

local function record(typename: string, fields)
	return setmetatable(fields, {
		__type = typename,
		__index = function(_, key)
			error(tostring(key) .. " is not a valid member of " .. typename, 2)
		end,
	})
end

Types.NumberSequenceKeypoint = {
	new = function(time, value, envelope)
		return record("NumberSequenceKeypoint", { Time = time, Value = value, Envelope = envelope or 0 })
	end,
}
Types.NumberSequence = {
	new = function(a, b)
		local keypoints
		if type(a) == "number" then
			keypoints = { Types.NumberSequenceKeypoint.new(0, a), Types.NumberSequenceKeypoint.new(1, b or a) }
		elseif type(a) == "table" then
			keypoints = a
			if #a < 2 or a[1].Time ~= 0 or a[#a].Time ~= 1 then
				error("NumberSequence: requires at least 2 keypoints, starting at 0 and ending at 1", 2)
			end
		else
			error("NumberSequence.new: invalid arguments", 2)
		end
		return record("NumberSequence", { Keypoints = keypoints })
	end,
}
Types.ColorSequenceKeypoint = {
	new = function(time, value)
		return record("ColorSequenceKeypoint", { Time = time, Value = value })
	end,
}
Types.ColorSequence = {
	new = function(a, b)
		local keypoints
		if typeName(a) == "Color3" then
			keypoints = { Types.ColorSequenceKeypoint.new(0, a), Types.ColorSequenceKeypoint.new(1, b or a) }
		elseif type(a) == "table" then
			keypoints = a
			if #a < 2 or a[1].Time ~= 0 or a[#a].Time ~= 1 then
				error("ColorSequence: requires keypoints starting at 0 and ending at 1", 2)
			end
		else
			error("ColorSequence.new: invalid arguments", 2)
		end
		return record("ColorSequence", { Keypoints = keypoints })
	end,
}
Types.NumberRange = {
	new = function(min, max)
		max = max or min
		if max < min then
			error("NumberRange: invalid range", 2)
		end
		return record("NumberRange", { Min = min, Max = max })
	end,
}
Types.TweenInfo = {
	new = function(time, style, direction, repeatCount, reverses, delay)
		return record("TweenInfo", {
			Time = time or 1,
			EasingStyle = style,
			EasingDirection = direction,
			RepeatCount = repeatCount or 0,
			Reverses = reverses or false,
			DelayTime = delay or 0,
		})
	end,
}
Types.Rect = {
	new = function(a, b, c, d)
		return record(
			"Rect",
			{ Min = V2.new(a, b), Max = V2.new(c, d), Width = (c or 0) - (a or 0), Height = (d or 0) - (b or 0) }
		)
	end,
}

---------------------------------------------------------------------------
-- Random
---------------------------------------------------------------------------

local RandomType = {}
local RandomMt = { __type = "Random" }
RandomMt.__index = {
	NextNumber = function(self, min, max)
		self.state = (self.state * 1103515245 + 12345) % 2147483648
		local u = self.state / 2147483648
		if min then
			return min + (max - min) * u
		end
		return u
	end,
	NextInteger = function(self, min, max)
		if max < min then
			error("NextInteger: max must be >= min", 2)
		end
		self.state = (self.state * 1103515245 + 12345) % 2147483648
		return min + floor(self.state / 2147483648 * (max - min + 1))
	end,
	Clone = function(self)
		return setmetatable({ state = self.state }, RandomMt)
	end,
	Shuffle = function(self, t)
		for i = #t, 2, -1 do
			local j = self:NextInteger(1, i)
			t[i], t[j] = t[j], t[i]
		end
	end,
}
local seedCounter = 1
RandomType.new = function(seed)
	seedCounter += 7919
	return setmetatable({ state = floor(seed or seedCounter) % 2147483648 }, RandomMt)
end
Types.Random = RandomType

---------------------------------------------------------------------------
-- Enum (validated against the API dump)
---------------------------------------------------------------------------

function Types.makeEnum(dump)
	local enumTypes = {}
	local itemsByType = {}
	local root = setmetatable({}, {
		__index = function(_, typeName_)
			local cached = enumTypes[typeName_]
			if cached then
				return cached
			end
			local names = dump.Enums[typeName_]
			if names == nil then
				error(tostring(typeName_) .. " is not a valid member of Enums", 2)
			end
			local items = {}
			local list = {}
			local enumType
			for i, name in names do
				local item = setmetatable({ Name = name, Value = i - 1 }, {
					__type = "EnumItem",
					__tostring = function()
						return "Enum." .. typeName_ .. "." .. name
					end,
					__index = function(self, key)
						if key == "EnumType" then
							return enumType
						elseif key == "IsA" then
							return function(_, n)
								return n == typeName_
							end
						end
						error(tostring(key) .. " is not a valid member of EnumItem", 2)
					end,
				})
				items[name] = item
				table.insert(list, item)
			end
			enumType = setmetatable({}, {
				__type = "Enum",
				__tostring = function()
					return typeName_
				end,
				__index = function(_, itemName)
					if itemName == "GetEnumItems" then
						return function()
							return table.clone(list)
						end
					elseif itemName == "FromName" then
						return function(_, n)
							return items[n]
						end
					elseif itemName == "FromValue" then
						return function(_, v)
							return list[v + 1]
						end
					end
					local item = items[itemName]
					if item == nil then
						error(tostring(itemName) .. ' is not a valid member of "Enum.' .. typeName_ .. '"', 2)
					end
					return item
				end,
			})
			enumTypes[typeName_] = enumType
			itemsByType[typeName_] = items
			return enumType
		end,
	})
	return root
end

return Types

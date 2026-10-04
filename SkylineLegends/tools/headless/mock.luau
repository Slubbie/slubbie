--!nocheck
-- A small mock of the Roblox engine API so server-side modules (the world
-- builder above all) can be executed and validated with the standalone Luau
-- CLI. It implements real Vector3/CFrame/Color3 maths, a basic Instance tree,
-- CollectionService tags and inert services. It is a test tool, not an engine.

local Mock = {}
local nativeTypeof = typeof

local KIND = {} -- metatable -> type name

-- Vector3 -----------------------------------------------------------------------------
local V3 = {}
V3.__index = function(v, key)
	if key == "X" then
		return rawget(v, 1)
	elseif key == "Y" then
		return rawget(v, 2)
	elseif key == "Z" then
		return rawget(v, 3)
	elseif key == "Magnitude" then
		return math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
	elseif key == "Unit" then
		local m = math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
		if m == 0 then
			return Mock.Vector3.new(0 / 0, 0 / 0, 0 / 0)
		end
		return Mock.Vector3.new(v[1] / m, v[2] / m, v[3] / m)
	end
	return V3[key]
end
KIND[V3] = "Vector3"

local function v3(x, y, z)
	return setmetatable({ x or 0, y or 0, z or 0 }, V3)
end
V3.__add = function(a, b)
	return v3(a[1] + b[1], a[2] + b[2], a[3] + b[3])
end
V3.__sub = function(a, b)
	return v3(a[1] - b[1], a[2] - b[2], a[3] - b[3])
end
V3.__mul = function(a, b)
	if type(a) == "number" then
		return v3(a * b[1], a * b[2], a * b[3])
	elseif type(b) == "number" then
		return v3(a[1] * b, a[2] * b, a[3] * b)
	end
	return v3(a[1] * b[1], a[2] * b[2], a[3] * b[3])
end
V3.__div = function(a, b)
	if type(b) == "number" then
		return v3(a[1] / b, a[2] / b, a[3] / b)
	end
	return v3(a[1] / b[1], a[2] / b[2], a[3] / b[3])
end
V3.__unm = function(a)
	return v3(-a[1], -a[2], -a[3])
end
V3.__eq = function(a, b)
	return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end
V3.__tostring = function(a)
	return ("%.3f, %.3f, %.3f"):format(a[1], a[2], a[3])
end
function V3.Dot(a, b)
	return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end
function V3.Cross(a, b)
	return v3(a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1])
end
function V3.Lerp(a, b, t)
	return a + (b - a) * t
end
function V3.Min(a, b)
	return v3(math.min(a[1], b[1]), math.min(a[2], b[2]), math.min(a[3], b[3]))
end
function V3.Max(a, b)
	return v3(math.max(a[1], b[1]), math.max(a[2], b[2]), math.max(a[3], b[3]))
end
function V3.Abs(a)
	return v3(math.abs(a[1]), math.abs(a[2]), math.abs(a[3]))
end
function V3.FuzzyEq(a, b, eps)
	return (a - b).Magnitude <= (eps or 1e-5)
end

Mock.Vector3 = {
	new = v3,
	zero = v3(0, 0, 0),
	one = v3(1, 1, 1),
	xAxis = v3(1, 0, 0),
	yAxis = v3(0, 1, 0),
	zAxis = v3(0, 0, 1),
}

-- CFrame ----------------------------------------------------------------------------------
-- p = position, m = row-major rotation {r00,r01,r02,r10,r11,r12,r20,r21,r22}
local CF = {}
KIND[CF] = "CFrame"

local function cf(p, m)
	return setmetatable({ p = p, m = m }, CF)
end
local IDENT = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }

local function mulRot(a, b)
	local r = {}
	for i = 0, 2 do
		for j = 0, 2 do
			r[i * 3 + j + 1] = a[i * 3 + 1] * b[j + 1] + a[i * 3 + 2] * b[3 + j + 1] + a[i * 3 + 3] * b[6 + j + 1]
		end
	end
	return r
end
local function rotVec(m, v)
	return v3(m[1] * v[1] + m[2] * v[2] + m[3] * v[3], m[4] * v[1] + m[5] * v[2] + m[6] * v[3], m[7] * v[1] + m[8] * v[2] + m[9] * v[3])
end
local function transpose(m)
	return { m[1], m[4], m[7], m[2], m[5], m[8], m[3], m[6], m[9] }
end
local function fromColumns(x, y, z)
	return { x[1], y[1], z[1], x[2], y[2], z[2], x[3], y[3], z[3] }
end

CF.__index = function(c, key)
	if key == "Position" or key == "p" then
		return rawget(c, "p")
	elseif key == "X" then
		return rawget(c, "p")[1]
	elseif key == "Y" then
		return rawget(c, "p")[2]
	elseif key == "Z" then
		return rawget(c, "p")[3]
	end
	local m = rawget(c, "m")
	if key == "RightVector" or key == "XVector" then
		return v3(m[1], m[4], m[7])
	elseif key == "UpVector" or key == "YVector" then
		return v3(m[2], m[5], m[8])
	elseif key == "LookVector" then
		return v3(-m[3], -m[6], -m[9])
	elseif key == "ZVector" then
		return v3(m[3], m[6], m[9])
	elseif key == "Rotation" then
		return cf(v3(0, 0, 0), m)
	end
	return CF[key]
end
CF.__mul = function(a, b)
	if getmetatable(b) == CF then
		return cf(a.p + rotVec(a.m, b.p), mulRot(a.m, b.m))
	end
	return a.p + rotVec(a.m, b)
end
CF.__add = function(a, v)
	return cf(a.p + v, a.m)
end
CF.__sub = function(a, v)
	return cf(a.p - v, a.m)
end
CF.__tostring = function(c)
	return "CFrame(" .. tostring(c.p) .. ")"
end
CF.__eq = function(a, b)
	if a.p ~= b.p then
		return false
	end
	for i = 1, 9 do
		if a.m[i] ~= b.m[i] then
			return false
		end
	end
	return true
end
function CF.Inverse(c)
	local t = transpose(c.m)
	return cf(-rotVec(t, c.p), t)
end
function CF.PointToObjectSpace(c, p)
	return rotVec(transpose(c.m), p - c.p)
end
function CF.PointToWorldSpace(c, p)
	return c.p + rotVec(c.m, p)
end
function CF.VectorToObjectSpace(c, v)
	return rotVec(transpose(c.m), v)
end
function CF.VectorToWorldSpace(c, v)
	return rotVec(c.m, v)
end
function CF.ToObjectSpace(c, other)
	return c:Inverse() * other
end
function CF.ToWorldSpace(c, other)
	return c * other
end
function CF.GetComponents(c)
	local m = c.m
	return c.p[1], c.p[2], c.p[3], m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9]
end

local function toQuat(m)
	local trace = m[1] + m[5] + m[9]
	local w, x, y, z
	if trace > 0 then
		local s = math.sqrt(trace + 1) * 2
		w = 0.25 * s
		x = (m[8] - m[6]) / s
		y = (m[3] - m[7]) / s
		z = (m[4] - m[2]) / s
	elseif m[1] > m[5] and m[1] > m[9] then
		local s = math.sqrt(1 + m[1] - m[5] - m[9]) * 2
		w = (m[8] - m[6]) / s
		x = 0.25 * s
		y = (m[2] + m[4]) / s
		z = (m[3] + m[7]) / s
	elseif m[5] > m[9] then
		local s = math.sqrt(1 + m[5] - m[1] - m[9]) * 2
		w = (m[3] - m[7]) / s
		x = (m[2] + m[4]) / s
		y = 0.25 * s
		z = (m[6] + m[8]) / s
	else
		local s = math.sqrt(1 + m[9] - m[1] - m[5]) * 2
		w = (m[4] - m[2]) / s
		x = (m[3] + m[7]) / s
		y = (m[6] + m[8]) / s
		z = 0.25 * s
	end
	return w, x, y, z
end
local function fromQuat(w, x, y, z)
	local n = math.sqrt(w * w + x * x + y * y + z * z)
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
function CF.Lerp(a, b, t)
	local aw, ax, ay, az = toQuat(a.m)
	local bw, bx, by, bz = toQuat(b.m)
	if aw * bw + ax * bx + ay * by + az * bz < 0 then
		bw, bx, by, bz = -bw, -bx, -by, -bz
	end
	local m = fromQuat(aw + (bw - aw) * t, ax + (bx - ax) * t, ay + (by - ay) * t, az + (bz - az) * t)
	return cf(a.p:Lerp(b.p, t), m)
end
function CF.ToAxisAngle(c)
	local w, x, y, z = toQuat(c.m)
	local angle = 2 * math.acos(math.clamp(w, -1, 1))
	local s = math.sqrt(1 - w * w)
	if s < 1e-6 then
		return v3(1, 0, 0), 0
	end
	return v3(x / s, y / s, z / s), angle
end
function CF.ToEulerAnglesXYZ(c)
	local m = c.m
	local y = math.asin(math.clamp(m[3], -1, 1))
	local x = math.atan2(-m[6], m[9])
	local z = math.atan2(-m[2], m[1])
	return x, y, z
end
function CF.ToOrientation(c)
	return c:ToEulerAnglesXYZ()
end

local function rx(a)
	local c, s = math.cos(a), math.sin(a)
	return { 1, 0, 0, 0, c, -s, 0, s, c }
end
local function ry(a)
	local c, s = math.cos(a), math.sin(a)
	return { c, 0, s, 0, 1, 0, -s, 0, c }
end
local function rz(a)
	local c, s = math.cos(a), math.sin(a)
	return { c, -s, 0, s, c, 0, 0, 0, 1 }
end

local function lookAt(at, target, up)
	up = up or v3(0, 1, 0)
	local look = (target - at)
	if look.Magnitude < 1e-9 then
		return cf(at, IDENT)
	end
	look = look.Unit
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		right = look:Cross(v3(0, 0, 1))
		if right.Magnitude < 1e-6 then
			right = look:Cross(v3(1, 0, 0))
		end
	end
	right = right.Unit
	local upv = right:Cross(look).Unit
	return cf(at, fromColumns(right, upv, -look))
end

Mock.CFrame = {
	new = function(a, b, c, ...)
		if a == nil then
			return cf(v3(0, 0, 0), IDENT)
		elseif type(a) == "number" then
			local extra = { ... }
			if #extra == 9 then
				return cf(v3(a, b, c), extra)
			end
			return cf(v3(a, b, c), IDENT)
		elseif b ~= nil then
			return lookAt(a, b)
		end
		return cf(a, IDENT)
	end,
	lookAt = lookAt,
	Angles = function(x, y, z)
		return cf(v3(0, 0, 0), mulRot(mulRot(rx(x), ry(y)), rz(z)))
	end,
	fromEulerAnglesXYZ = function(x, y, z)
		return cf(v3(0, 0, 0), mulRot(mulRot(rx(x), ry(y)), rz(z)))
	end,
	fromEulerAnglesYXZ = function(x, y, z)
		return cf(v3(0, 0, 0), mulRot(mulRot(ry(y), rx(x)), rz(z)))
	end,
	fromOrientation = function(x, y, z)
		return cf(v3(0, 0, 0), mulRot(mulRot(ry(y), rx(x)), rz(z)))
	end,
	fromAxisAngle = function(axis, angle)
		axis = axis.Unit
		local c, s = math.cos(angle), math.sin(angle)
		local t = 1 - c
		local x, y, z = axis[1], axis[2], axis[3]
		return cf(v3(0, 0, 0), {
			t * x * x + c,
			t * x * y - s * z,
			t * x * z + s * y,
			t * x * y + s * z,
			t * y * y + c,
			t * y * z - s * x,
			t * x * z - s * y,
			t * y * z + s * x,
			t * z * z + c,
		})
	end,
	fromMatrix = function(pos, vx, vy, vz)
		vz = vz or vx:Cross(vy)
		return cf(pos, fromColumns(vx, vy, vz))
	end,
	identity = cf(v3(0, 0, 0), IDENT),
}

-- Color3 -----------------------------------------------------------------------------------
local C3 = {}
KIND[C3] = "Color3"
C3.__index = function(c, key)
	if key == "R" then
		return c[1]
	elseif key == "G" then
		return c[2]
	elseif key == "B" then
		return c[3]
	end
	return C3[key]
end
local function color(r, g, b)
	return setmetatable({ r or 0, g or 0, b or 0 }, C3)
end
C3.__eq = function(a, b)
	return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end
function C3.Lerp(a, b, t)
	return color(a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t)
end
function C3.ToHSV(c)
	local r, g, b = c[1], c[2], c[3]
	local max, min = math.max(r, g, b), math.min(r, g, b)
	local h, s, v = 0, 0, max
	local d = max - min
	s = if max == 0 then 0 else d / max
	if d ~= 0 then
		if max == r then
			h = (g - b) / d % 6
		elseif max == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h /= 6
	end
	return h, s, v
end
function C3.ToHex(c)
	return ("%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end
Mock.Color3 = {
	new = color,
	fromRGB = function(r, g, b)
		return color(r / 255, g / 255, b / 255)
	end,
	fromHSV = function(h, s, v)
		local i = math.floor(h * 6)
		local f = h * 6 - i
		local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
		i %= 6
		if i == 0 then
			return color(v, t, p)
		elseif i == 1 then
			return color(q, v, p)
		elseif i == 2 then
			return color(p, v, t)
		elseif i == 3 then
			return color(p, q, v)
		elseif i == 4 then
			return color(t, p, v)
		end
		return color(v, p, q)
	end,
	fromHex = function()
		return color(1, 1, 1)
	end,
}

-- Simple value types -------------------------------------------------------------------------
local function valueType(name, fields)
	local mt = {}
	KIND[mt] = name
	mt.__index = mt
	return function(...)
		local values = { ... }
		local obj = {}
		for i, field in fields do
			obj[field] = values[i]
		end
		return setmetatable(obj, mt)
	end
end
Mock.Vector2 = { new = valueType("Vector2", { "X", "Y" }), zero = nil }
Mock.Vector2.zero = Mock.Vector2.new(0, 0)
Mock.UDim = { new = valueType("UDim", { "Scale", "Offset" }) }
local udim2 = valueType("UDim2", { "XScale", "XOffset", "YScale", "YOffset" })
Mock.UDim2 = {
	new = udim2,
	fromOffset = function(x, y)
		return udim2(0, x or 0, 0, y or 0)
	end,
	fromScale = function(x, y)
		return udim2(x or 0, 0, y or 0, 0)
	end,
}
Mock.NumberRange = { new = valueType("NumberRange", { "Min", "Max" }) }
Mock.NumberSequenceKeypoint = { new = valueType("NumberSequenceKeypoint", { "Time", "Value", "Envelope" }) }
Mock.NumberSequence = { new = valueType("NumberSequence", { "Keypoints" }) }
Mock.ColorSequenceKeypoint = { new = valueType("ColorSequenceKeypoint", { "Time", "Value" }) }
Mock.ColorSequence = { new = valueType("ColorSequence", { "Keypoints" }) }
Mock.Rect = { new = valueType("Rect", { "Min", "Max" }) }
Mock.TweenInfo = { new = valueType("TweenInfo", { "Time" }) }
Mock.PhysicalProperties = { new = valueType("PhysicalProperties", { "Density" }) }
Mock.Font = { new = valueType("Font", { "Family", "Weight" }), fromEnum = valueType("Font", { "Enum" }) }
Mock.BrickColor = { new = valueType("BrickColor", { "Name" }) }
Mock.Ray = { new = valueType("Ray", { "Origin", "Direction" }) }

-- Enum ---------------------------------------------------------------------------------------
local enumItemMt = {}
KIND[enumItemMt] = "EnumItem"
enumItemMt.__index = enumItemMt
enumItemMt.__tostring = function(item)
	return "Enum." .. item.EnumType .. "." .. item.Name
end
local enumCache = {}
Mock.Enum = setmetatable({}, {
	__index = function(_, enumName)
		local cached = enumCache[enumName]
		if cached then
			return cached
		end
		local items = {}
		local value = 0
		local enumObj = setmetatable({}, {
			__index = function(_, itemName)
				local item = items[itemName]
				if not item then
					value += 1
					item = setmetatable({ Name = itemName, EnumType = enumName, Value = value }, enumItemMt)
					items[itemName] = item
				end
				return item
			end,
		})
		enumCache[enumName] = enumObj
		return enumObj
	end,
})

-- Signals --------------------------------------------------------------------------------------
local function signal()
	local s = { handlers = {} }
	function s:Connect(fn)
		table.insert(self.handlers, fn)
		return {
			Connected = true,
			Disconnect = function() end,
		}
	end
	function s:Once(fn)
		return self:Connect(fn)
	end
	function s:Wait()
		return nil
	end
	function s:Fire(...)
		for _, fn in self.handlers do
			fn(...)
		end
	end
	return s
end
Mock.Signal = signal

-- Instances ------------------------------------------------------------------------------------
local CLASS_PARENT = {
	Part = "BasePart",
	WedgePart = "BasePart",
	CornerWedgePart = "BasePart",
	TrussPart = "BasePart",
	MeshPart = "BasePart",
	SpawnLocation = "Part",
	Seat = "Part",
	BasePart = "PVInstance",
	Model = "PVInstance",
	PVInstance = "Instance",
	Folder = "Instance",
	Configuration = "Instance",
	ModuleScript = "LuaSourceContainer",
	Script = "LuaSourceContainer",
	LocalScript = "LuaSourceContainer",
	LuaSourceContainer = "Instance",
	PointLight = "Light",
	SpotLight = "Light",
	SurfaceLight = "Light",
	Light = "Instance",
	Attachment = "Instance",
	ParticleEmitter = "Instance",
	Beam = "Instance",
	Trail = "Instance",
	ScreenGui = "LayerCollector",
	SurfaceGui = "LayerCollector",
	BillboardGui = "LayerCollector",
	LayerCollector = "GuiBase2d",
	Frame = "GuiObject",
	TextLabel = "GuiObject",
	TextButton = "GuiObject",
	ImageLabel = "GuiObject",
	ImageButton = "GuiObject",
	ScrollingFrame = "GuiObject",
	GuiObject = "GuiBase2d",
	GuiBase2d = "Instance",
	RemoteEvent = "Instance",
	RemoteFunction = "Instance",
	UnreliableRemoteEvent = "Instance",
	BindableEvent = "Instance",
	Sound = "Instance",
	Humanoid = "Instance",
}

local INSTANCE = {}
local instanceMt = {}
KIND[instanceMt] = "Instance"
local tags = {} -- instance -> { tag = true }
local tagged = {} -- tag -> { instance = true }

local PART_DEFAULTS = {
	Anchored = false,
	CanCollide = true,
	CanQuery = true,
	CanTouch = true,
	CastShadow = true,
	Transparency = 0,
	Reflectance = 0,
	Massless = false,
	CollisionGroup = "Default",
}

local function isA(className, wanted)
	local current = className
	while current do
		if current == wanted then
			return true
		end
		current = CLASS_PARENT[current]
	end
	return wanted == "Instance"
end

instanceMt.__index = function(inst, key)
	local props = rawget(inst, "_props")
	local value = props[key]
	if value ~= nil then
		return value
	end
	if key == "Position" then
		local c = props.CFrame
		return c and c.Position or v3(0, 0, 0)
	elseif key == "Parent" then
		return rawget(inst, "_parent")
	elseif key == "ClassName" then
		return rawget(inst, "_class")
	elseif key == "Orientation" then
		return v3(0, 0, 0)
	end
	local method = INSTANCE[key]
	if method then
		return method
	end
	-- Child lookup by name (like Roblox's inst.ChildName).
	for _, child in rawget(inst, "_children") do
		if child.Name == key then
			return child
		end
	end
	if isA(rawget(inst, "_class"), "BasePart") and PART_DEFAULTS[key] ~= nil then
		return PART_DEFAULTS[key]
	end
	-- Unknown signal-like properties return inert signals.
	if
		string.sub(key, -5) == "Added"
		or string.sub(key, -7) == "Removed"
		or string.sub(key, -7) == "Changed"
		or key == "Touched"
		or key == "Triggered"
		or key == "Destroying"
		or key == "Died"
		or key == "Event"
		or key == "OnServerEvent"
		or key == "OnClientEvent"
		or key == "Heartbeat"
		or key == "TriggerEnded"
		or key == "PromptShown"
		or key == "MouseButton1Click"
	then
		local s = signal()
		props[key] = s
		return s
	end
	return nil
end
instanceMt.__newindex = function(inst, key, value)
	if key == "Parent" then
		local old = rawget(inst, "_parent")
		if old then
			local list = rawget(old, "_children")
			local index = table.find(list, inst)
			if index then
				table.remove(list, index)
			end
		end
		rawset(inst, "_parent", value)
		if value then
			table.insert(rawget(value, "_children"), inst)
		end
		return
	elseif key == "Position" then
		local props = rawget(inst, "_props")
		local c = props.CFrame or Mock.CFrame.identity
		props.CFrame = cf(value, c.m)
		return
	end
	rawget(inst, "_props")[key] = value
end
instanceMt.__tostring = function(inst)
	return inst.Name
end

local instanceCount = 0
local function newInstance(className)
	instanceCount += 1
	local inst = setmetatable({ _class = className, _props = { Name = className }, _children = {}, _parent = nil }, instanceMt)
	if isA(className, "BasePart") then
		rawget(inst, "_props").Size = v3(4, 1, 2)
		rawget(inst, "_props").CFrame = Mock.CFrame.identity
		rawget(inst, "_props").AssemblyLinearVelocity = v3(0, 0, 0)
	end
	return inst
end

function INSTANCE.IsA(inst, className)
	return isA(rawget(inst, "_class"), className)
end
function INSTANCE.GetChildren(inst)
	return table.clone(rawget(inst, "_children"))
end
function INSTANCE.GetDescendants(inst)
	local result = {}
	local function walk(node)
		for _, child in rawget(node, "_children") do
			table.insert(result, child)
			walk(child)
		end
	end
	walk(inst)
	return result
end
function INSTANCE.FindFirstChild(inst, name, recursive)
	for _, child in rawget(inst, "_children") do
		if child.Name == name then
			return child
		end
	end
	if recursive then
		for _, child in rawget(inst, "_children") do
			local found = child:FindFirstChild(name, true)
			if found then
				return found
			end
		end
	end
	return nil
end
function INSTANCE.WaitForChild(inst, name)
	return inst:FindFirstChild(name)
end
function INSTANCE.FindFirstChildOfClass(inst, className)
	for _, child in rawget(inst, "_children") do
		if rawget(child, "_class") == className then
			return child
		end
	end
	return nil
end
function INSTANCE.FindFirstChildWhichIsA(inst, className, recursive)
	for _, child in (if recursive then inst:GetDescendants() else rawget(inst, "_children")) do
		if child:IsA(className) then
			return child
		end
	end
	return nil
end
function INSTANCE.FindFirstAncestorWhichIsA(inst, className)
	local node = rawget(inst, "_parent")
	while node do
		if node:IsA(className) then
			return node
		end
		node = rawget(node, "_parent")
	end
	return nil
end
function INSTANCE.IsDescendantOf(inst, ancestor)
	local node = rawget(inst, "_parent")
	while node do
		if node == ancestor then
			return true
		end
		node = rawget(node, "_parent")
	end
	return false
end
function INSTANCE.GetFullName(inst)
	local names = {}
	local node = inst
	while node and rawget(node, "_class") ~= "DataModel" do
		table.insert(names, 1, node.Name)
		node = rawget(node, "_parent")
	end
	return table.concat(names, ".")
end
function INSTANCE.Destroy(inst)
	inst.Parent = nil
	for tag in tags[inst] or {} do
		tagged[tag][inst] = nil
	end
	tags[inst] = nil
end
function INSTANCE.ClearAllChildren(inst)
	for _, child in inst:GetChildren() do
		child:Destroy()
	end
end
function INSTANCE.Clone(inst)
	local copy = newInstance(rawget(inst, "_class"))
	for key, value in rawget(inst, "_props") do
		rawget(copy, "_props")[key] = value
	end
	for _, child in rawget(inst, "_children") do
		child:Clone().Parent = copy
	end
	return copy
end
function INSTANCE.SetAttribute(inst, key, value)
	local attrs = rawget(inst, "_attrs")
	if not attrs then
		attrs = {}
		rawset(inst, "_attrs", attrs)
	end
	local kind = nativeTypeof(value)
	if value ~= nil and kind == "table" then
		local mt = getmetatable(value)
		if not KIND[mt] then
			error("SetAttribute: unsupported table value for " .. key)
		end
	elseif value ~= nil and kind ~= "string" and kind ~= "number" and kind ~= "boolean" then
		error("SetAttribute: unsupported type " .. kind .. " for " .. key)
	end
	attrs[key] = value
end
function INSTANCE.GetAttribute(inst, key)
	local attrs = rawget(inst, "_attrs")
	return attrs and attrs[key]
end
function INSTANCE.GetAttributes(inst)
	return table.clone(rawget(inst, "_attrs") or {})
end
function INSTANCE.GetAttributeChangedSignal()
	return signal()
end
function INSTANCE.GetPropertyChangedSignal()
	return signal()
end
function INSTANCE.PivotTo(inst, c)
	inst.CFrame = c
end
function INSTANCE.GetPivot(inst)
	return inst.CFrame or Mock.CFrame.identity
end
function INSTANCE.SetNetworkOwner() end
function INSTANCE.GetTouchingParts()
	return {}
end
function INSTANCE.SetPrimaryPartCFrame(inst, c)
	inst.CFrame = c
end
function INSTANCE.GetBoundingBox(inst)
	return Mock.CFrame.identity, v3(1, 1, 1)
end
function INSTANCE.Emit() end
function INSTANCE.FireServer() end
function INSTANCE.FireClient() end
function INSTANCE.FireAllClients() end
function INSTANCE.InvokeServer() end
function INSTANCE.Play() end
function INSTANCE.Stop() end
function INSTANCE.SetStateEnabled() end
function INSTANCE.ChangeState() end

Mock.Instance = {
	new = function(className, parent)
		local inst = newInstance(className)
		if parent then
			inst.Parent = parent
		end
		return inst
	end,
}
Mock.InstanceCount = function()
	return instanceCount
end

-- Services ---------------------------------------------------------------------------------------
local game = newInstance("DataModel")
rawget(game, "_props").Name = "Game"
rawget(game, "_props").JobId = ""
rawget(game, "_props").PlaceId = 0
local services = {}

local workspace = newInstance("Workspace")
rawget(workspace, "_props").Name = "Workspace"
rawget(workspace, "_props").Gravity = 196.2
workspace.Parent = game
services.Workspace = workspace
function workspace.Raycast()
	return nil
end
function workspace.Spherecast()
	return nil
end
function workspace.Blockcast()
	return nil
end
function workspace.GetPartBoundsInRadius()
	return {}
end
function workspace.GetPartBoundsInBox()
	return {}
end
function workspace.GetPartsInPart()
	return {}
end
function workspace.GetServerTimeNow()
	return os.clock()
end

local CollectionService = newInstance("CollectionService")
function CollectionService.AddTag(_, inst, tag)
	tags[inst] = tags[inst] or {}
	tags[inst][tag] = true
	tagged[tag] = tagged[tag] or {}
	tagged[tag][inst] = true
end
function CollectionService.RemoveTag(_, inst, tag)
	if tags[inst] then
		tags[inst][tag] = nil
	end
	if tagged[tag] then
		tagged[tag][inst] = nil
	end
end
function CollectionService.HasTag(_, inst, tag)
	return tags[inst] ~= nil and tags[inst][tag] == true
end
function CollectionService.GetTagged(_, tag)
	local result = {}
	for inst in tagged[tag] or {} do
		if inst:IsDescendantOf(game) then
			table.insert(result, inst)
		end
	end
	return result
end
function CollectionService.GetTags(_, inst)
	local result = {}
	for tag in tags[inst] or {} do
		table.insert(result, tag)
	end
	return result
end
function CollectionService.GetInstanceAddedSignal()
	return signal()
end
function CollectionService.GetInstanceRemovedSignal()
	return signal()
end
services.CollectionService = CollectionService

local PhysicsService = newInstance("PhysicsService")
local groups = { Default = true }
function PhysicsService.RegisterCollisionGroup(_, name)
	groups[name] = true
end
function PhysicsService.CollisionGroupSetCollidable(_, a, b)
	assert(groups[a] and groups[b], "unregistered collision group")
end
function PhysicsService.IsCollisionGroupRegistered(_, name)
	return groups[name] == true
end
services.PhysicsService = PhysicsService

local Players = newInstance("Players")
function Players.GetPlayers()
	return {}
end
function Players.GetPlayerByUserId()
	return nil
end
services.Players = Players

local RunService = newInstance("RunService")
function RunService.IsServer()
	return true
end
function RunService.IsClient()
	return false
end
function RunService.IsStudio()
	return true
end
services.RunService = RunService

local DataStoreService = newInstance("DataStoreService")
function DataStoreService.GetDataStore()
	error("HTTP 403 (API access disabled in headless tests)")
end
function DataStoreService.GetOrderedDataStore()
	error("HTTP 403 (API access disabled in headless tests)")
end
services.DataStoreService = DataStoreService

local HttpService = newInstance("HttpService")
local guid = 0
function HttpService.GenerateGUID()
	guid += 1
	return ("GUID-%d"):format(guid)
end
function HttpService.JSONEncode(_, value)
	return tostring(value)
end
services.HttpService = HttpService

for _, name in
	{
		"ReplicatedStorage",
		"ServerScriptService",
		"ServerStorage",
		"StarterPlayer",
		"StarterGui",
		"Lighting",
		"SoundService",
		"TweenService",
		"MessagingService",
		"MemoryStoreService",
		"MarketplaceService",
		"TextService",
		"UserInputService",
		"ContextActionService",
		"GuiService",
		"TeleportService",
		"SocialService",
		"Teams",
		"Debris",
		"TextChatService",
	}
do
	local service = newInstance(name)
	rawget(service, "_props").Name = name
	service.Parent = game
	services[name] = service
end
CollectionService.Parent = game
PhysicsService.Parent = game
Players.Parent = game
RunService.Parent = game
DataStoreService.Parent = game
HttpService.Parent = game
local spsFolder = newInstance("StarterPlayerScripts")
rawget(spsFolder, "_props").Name = "StarterPlayerScripts"
spsFolder.Parent = services.StarterPlayer
function services.Debris.AddItem() end

function game.GetService(_, name)
	local service = services[name]
	if not service then
		error("Mock has no service " .. tostring(name))
	end
	return service
end
function game.BindToClose() end
game.Workspace = workspace

Mock.game = game
Mock.workspace = workspace

-- Globals ------------------------------------------------------------------------------------------
Mock.typeof = function(value)
	local kind = nativeTypeof(value)
	if kind == "table" then
		local mt = getmetatable(value)
		if mt and KIND[mt] then
			return KIND[mt]
		end
	end
	return kind
end

local deferred = {}
Mock.task = {
	spawn = function(fn, ...)
		if type(fn) == "function" then
			table.insert(deferred, { fn, table.pack(...) })
		end
	end,
	defer = function(fn, ...)
		if type(fn) == "function" then
			table.insert(deferred, { fn, table.pack(...) })
		end
	end,
	delay = function() end,
	wait = function()
		-- Background loops would run forever; stop them here.
		coroutine.yield()
	end,
	cancel = function() end,
}
Mock.RunDeferred = function()
	local pending = deferred
	deferred = {}
	for _, entry in pending do
		local co = coroutine.create(entry[1])
		local ok, err = coroutine.resume(co, table.unpack(entry[2], 1, entry[2].n))
		if not ok then
			error(err)
		end
	end
end

local warnings = {}
Mock.warn = function(...)
	local parts = {}
	for _, v in { ... } do
		table.insert(parts, tostring(v))
	end
	local text = table.concat(parts, " ")
	table.insert(warnings, text)
	print("WARN: " .. text)
end
Mock.Warnings = warnings
Mock.tick = os.clock
Mock.time = os.clock
Mock.wait = function() end
Mock.delay = function() end
Mock.spawn = function() end
Mock.Random = {
	new = function(seed)
		local state = (seed or 1) % 2147483647
		if state <= 0 then
			state += 2147483646
		end
		local r = {}
		function r:NextNumber(lo, hi)
			state = (state * 48271) % 2147483647
			local x = state / 2147483647
			if lo then
				return lo + (hi - lo) * x
			end
			return x
		end
		function r:NextInteger(lo, hi)
			return lo + math.floor(self:NextNumber() * (hi - lo + 1))
		end
		return r
	end,
}
Mock.DateTime = { now = function() return { UnixTimestamp = os.time() } end }

-- Module loader ---------------------------------------------------------------------------------------
local moduleCache = {}
local loading = {}
local env

function Mock.require(target)
	if type(target) ~= "table" or not rawget(target, "_props") then
		error("require expects a ModuleScript instance, got " .. tostring(target))
	end
	if moduleCache[target] ~= nil then
		return moduleCache[target]
	end
	if loading[target] then
		error("Cyclic require of " .. target:GetFullName())
	end
	local source = rawget(target, "_props").Source
	if not source then
		error("No source for " .. target:GetFullName())
	end
	loading[target] = true
	local fn, err = loadstring(source, "=" .. target:GetFullName())
	if not fn then
		error(err)
	end
	setfenv(fn, setmetatable({ script = target }, { __index = env }))
	local result = fn()
	loading[target] = nil
	moduleCache[target] = result
	return result
end

env = setmetatable({
	game = game,
	workspace = workspace,
	Instance = Mock.Instance,
	Vector3 = Mock.Vector3,
	Vector2 = Mock.Vector2,
	CFrame = Mock.CFrame,
	Color3 = Mock.Color3,
	UDim = Mock.UDim,
	UDim2 = Mock.UDim2,
	NumberRange = Mock.NumberRange,
	NumberSequence = Mock.NumberSequence,
	NumberSequenceKeypoint = Mock.NumberSequenceKeypoint,
	ColorSequence = Mock.ColorSequence,
	ColorSequenceKeypoint = Mock.ColorSequenceKeypoint,
	Rect = Mock.Rect,
	TweenInfo = Mock.TweenInfo,
	PhysicalProperties = Mock.PhysicalProperties,
	Font = Mock.Font,
	BrickColor = Mock.BrickColor,
	Ray = Mock.Ray,
	Enum = Mock.Enum,
	RaycastParams = { new = function() return {} end },
	OverlapParams = { new = function() return {} end },
	typeof = Mock.typeof,
	task = Mock.task,
	warn = Mock.warn,
	tick = Mock.tick,
	time = Mock.time,
	wait = Mock.wait,
	delay = Mock.delay,
	spawn = Mock.spawn,
	Random = Mock.Random,
	DateTime = Mock.DateTime,
	require = Mock.require,
}, { __index = getfenv(0) })
Mock.Env = env

-- Build the place tree from bundled sources.
function Mock.Mount(entries)
	local nodes = {}
	for _, entry in entries do
		local parentPath, name = string.match(entry.path, "^(.*)/([^/]+)$")
		local parent
		if parentPath == "ReplicatedStorage" or parentPath == "ServerScriptService" then
			parent = services[parentPath]
		elseif parentPath == "StarterPlayer/StarterPlayerScripts" then
			parent = spsFolder
		else
			parent = nodes[parentPath]
		end
		assert(parent, "no parent for " .. entry.path)
		local inst = newInstance(entry.class)
		rawget(inst, "_props").Name = name
		if entry.source then
			rawget(inst, "_props").Source = entry.source
		end
		inst.Parent = parent
		nodes[entry.path] = inst
	end
	return nodes
end

return Mock

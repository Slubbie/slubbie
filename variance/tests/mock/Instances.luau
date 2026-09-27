--# selene: allow(global_usage, unused_variable, shadowing)
-- Instances for the runtime mock.
--
-- Every member access is checked against the Roblox API dump (ApiDump.luau):
-- reading or writing a member the engine doesn't have raises the same kind of
-- error the engine would ("X is not a valid member of Class"), and property
-- writes are type-checked. Methods the mock doesn't model return nil and are
-- logged (Instances.unimplemented) so a test can tell what it didn't cover.
--
-- Behaviour modelled: parenting with Child/Descendant/Ancestry events,
-- property and attribute change signals, Destroy/Clone, part CFrame/Position,
-- models' pivots, attachments' world frames, GUI absolute sizes, sounds,
-- particle emitters, tweens (instant, with Completed after the duration).

local Types = require(script.Parent.Types)
local Scheduler = require(script.Parent.Scheduler)
local Dump = require(script.Parent.ApiDump)

local Instances = {}
Instances.unimplemented = {} -- ["Class:Method"] = count

local typeof = Types.typeof
local V3, CF, V2 = Types.Vector3, Types.CFrame, Types.Vector2

local D = setmetatable({}, { __mode = "k" }) -- proxy -> data
Instances.data = D

---------------------------------------------------------------------------
-- API lookups
---------------------------------------------------------------------------

local memberCache = {}

local function classInfo(className: string)
	local cached = memberCache[className]
	if cached then
		return cached
	end
	local info = { Props = {}, Methods = {}, Events = {}, Chain = {} }
	local cur = className
	while cur do
		local c = Dump.Classes[cur]
		if c == nil then
			break
		end
		table.insert(info.Chain, cur)
		for k, v in c.P do
			if info.Props[k] == nil then
				info.Props[k] = v
			end
		end
		for _, m in c.M do
			info.Methods[m] = true
		end
		for _, e in c.E do
			info.Events[e] = true
		end
		cur = c.S
	end
	if #info.Chain == 0 then
		error("mock: unknown class " .. className, 3)
	end
	memberCache[className] = info
	return info
end
Instances.classInfo = classInfo

local function isA(className: string, other: string): boolean
	for _, c in classInfo(className).Chain do
		if c == other then
			return true
		end
	end
	return false
end
Instances.isA = isA

local ENUM_DEFAULTS = {
	Material = "Plastic",
	Font = "Legacy",
}

local function defaultFor(code: string, key: string)
	if code == "n" then
		return 0
	elseif code == "b" then
		return false
	elseif code == "s" then
		return ""
	elseif code == "V3" then
		return V3.zero
	elseif code == "V2" then
		return V2.zero
	elseif code == "CF" then
		return CF.identity
	elseif code == "C3" then
		return Types.Color3.new(0.64, 0.64, 0.64)
	elseif code == "U2" then
		return Types.UDim2.new()
	elseif code == "U" then
		return Types.UDim.new()
	elseif string.sub(code, 1, 2) == "E:" then
		local enumName = string.sub(code, 3)
		local names = Dump.Enums[enumName]
		if names and #names > 0 then
			local pick = ENUM_DEFAULTS[enumName]
			if pick and table.find(names, pick) then
				return Instances.Enum[enumName][pick]
			end
			return Instances.Enum[enumName][names[1]]
		end
	end
	return nil
end

local function checkType(className: string, key: string, code: string, value)
	if value == nil then
		return value
	end
	local t = typeof(value)
	local ok = true
	if code == "n" then
		if t == "string" and tonumber(value) then
			return tonumber(value)
		end
		ok = t == "number"
	elseif code == "b" then
		ok = t == "boolean"
	elseif code == "s" then
		if t == "number" then
			return tostring(value)
		end
		ok = t == "string"
	elseif code == "V3" then
		ok = t == "Vector3"
	elseif code == "V2" then
		ok = t == "Vector2"
	elseif code == "CF" then
		ok = t == "CFrame"
	elseif code == "C3" then
		ok = t == "Color3"
	elseif code == "U2" then
		ok = t == "UDim2"
	elseif code == "U" then
		ok = t == "UDim"
	elseif code == "NS" then
		if t == "number" then
			return Types.NumberSequence.new(value)
		end
		ok = t == "NumberSequence"
	elseif code == "CS" then
		if t == "Color3" then
			return Types.ColorSequence.new(value)
		end
		ok = t == "ColorSequence"
	elseif code == "NR" then
		if t == "number" then
			return Types.NumberRange.new(value)
		end
		ok = t == "NumberRange"
	elseif code == "fn" then
		ok = t == "function"
	elseif string.sub(code, 1, 2) == "E:" then
		local enumName = string.sub(code, 3)
		if t == "EnumItem" then
			ok = tostring(value):match("^Enum%.(%w+)%.") == enumName
		elseif t == "string" then
			local names = Dump.Enums[enumName]
			ok = names ~= nil and table.find(names, value) ~= nil
			if ok then
				return Instances.Enum[enumName][value]
			end
		elseif t == "number" then
			return Instances.Enum[enumName]:FromValue(value) or value
		else
			ok = false
		end
	end
	if not ok then
		error(string.format("Unable to assign property %s. %s expected, got %s (%s)", key, code, t, className), 4)
	end
	return value
end

---------------------------------------------------------------------------
-- Core object
---------------------------------------------------------------------------

local Proxy = {}
local special = {} -- className -> { get = {prop = fn}, set = {prop = fn}, methods = {name = fn} }
Instances.special = special

local function specialFor(className: string)
	local get, set, methods = {}, {}, {}
	local chain = classInfo(className).Chain
	for i = #chain, 1, -1 do
		local s = special[chain[i]]
		if s then
			for k, v in s.get or {} do
				get[k] = v
			end
			for k, v in s.set or {} do
				set[k] = v
			end
			for k, v in s.methods or {} do
				methods[k] = v
			end
		end
	end
	return get, set, methods
end

local resolvedCache = {}
local function resolved(className: string)
	local r = resolvedCache[className]
	if r == nil then
		local get, set, methods = specialFor(className)
		r = { Get = get, Set = set, Methods = methods, Info = classInfo(className) }
		resolvedCache[className] = r
	end
	return r
end

local function fullName(self): string
	local parts = {}
	local cur = self
	while cur do
		local d = D[cur]
		if d == nil or d.ClassName == "DataModel" then
			break
		end
		table.insert(parts, 1, d.Name)
		cur = d.Parent
	end
	return table.concat(parts, ".")
end

local function signalOf(self, name: string)
	local d = D[self]
	local s = d.Signals[name]
	if s == nil then
		s = Scheduler.signal(d.ClassName .. "." .. name)
		s.Immediate = name == "Destroying" or d.ClassName == "RunService"
		d.Signals[name] = s
	end
	return s
end
Instances.signalOf = signalOf

function Instances.fire(self, eventName: string, ...)
	local d = D[self]
	local s = d and d.Signals[eventName]
	if s then
		Scheduler.fire(s, nil, ...)
	end
end

local function firePropChanged(self, key: string)
	local d = D[self]
	local ps = d.PropSignals[key]
	if ps then
		Scheduler.fire(ps, nil)
	end
	local changed = d.Signals.Changed
	if changed then
		Scheduler.fire(changed, nil, key)
	end
end
Instances.propChanged = firePropChanged

local function descendants(self, out)
	for _, child in D[self].Children do
		table.insert(out, child)
		descendants(child, out)
	end
	return out
end

local function setParent(self, parent)
	local d = D[self]
	if d.Destroyed and parent ~= nil then
		error(
			"The Parent property of "
				.. fullName(self)
				.. " is locked, current parent: NULL, new parent "
				.. (parent and D[parent].Name or "NULL"),
			3
		)
	end
	if parent == d.Parent then
		return
	end
	if parent ~= nil then
		if D[parent] == nil then
			error("Unable to assign property Parent. Instance expected, got " .. typeof(parent), 3)
		end
		local cur = parent
		while cur do
			if cur == self then
				error("Attempt to set " .. fullName(self) .. " as its own ancestor", 3)
			end
			cur = D[cur].Parent
		end
	end
	local old = d.Parent
	local moving = descendants(self, {})
	if old then
		local od = D[old]
		local index = table.find(od.Children, self)
		if index then
			table.remove(od.Children, index)
		end
		-- DescendantRemoving on old ancestors.
		local cur = old
		while cur do
			local s = D[cur].Signals.DescendantRemoving
			if s then
				Scheduler.fire(s, nil, self)
				for _, m in moving do
					Scheduler.fire(s, nil, m)
				end
			end
			cur = D[cur].Parent
		end
		Instances.fire(old, "ChildRemoved", self)
	end
	d.Parent = parent
	if parent then
		table.insert(D[parent].Children, self)
		Instances.fire(parent, "ChildAdded", self)
		local cur = parent
		while cur do
			local s = D[cur].Signals.DescendantAdded
			if s then
				Scheduler.fire(s, nil, self)
				for _, m in moving do
					Scheduler.fire(s, nil, m)
				end
			end
			cur = D[cur].Parent
		end
	end
	Instances.fire(self, "AncestryChanged", self, parent)
	for _, m in moving do
		Instances.fire(m, "AncestryChanged", self, parent)
	end
	firePropChanged(self, "Parent")
end

local generic = {}
Instances.generic = generic

function generic.IsA(self, className)
	return isA(D[self].ClassName, className)
end
function generic.GetChildren(self)
	return table.clone(D[self].Children)
end
function generic.GetDescendants(self)
	return descendants(self, {})
end
function generic.FindFirstChild(self, name, recursive)
	for _, child in D[self].Children do
		if D[child].Name == name then
			return child
		end
	end
	if recursive then
		for _, child in D[self].Children do
			local found = generic.FindFirstChild(child, name, true)
			if found then
				return found
			end
		end
	end
	return nil
end
function generic.FindFirstChildOfClass(self, className)
	for _, child in D[self].Children do
		if D[child].ClassName == className then
			return child
		end
	end
	return nil
end
function generic.FindFirstChildWhichIsA(self, className, recursive)
	for _, child in D[self].Children do
		if isA(D[child].ClassName, className) then
			return child
		end
	end
	if recursive then
		for _, child in D[self].Children do
			local found = generic.FindFirstChildWhichIsA(child, className, true)
			if found then
				return found
			end
		end
	end
	return nil
end
function generic.FindFirstAncestor(self, name)
	local cur = D[self].Parent
	while cur do
		if D[cur].Name == name then
			return cur
		end
		cur = D[cur].Parent
	end
	return nil
end
function generic.FindFirstAncestorOfClass(self, className)
	local cur = D[self].Parent
	while cur do
		if D[cur].ClassName == className then
			return cur
		end
		cur = D[cur].Parent
	end
	return nil
end
function generic.FindFirstAncestorWhichIsA(self, className)
	local cur = D[self].Parent
	while cur do
		if isA(D[cur].ClassName, className) then
			return cur
		end
		cur = D[cur].Parent
	end
	return nil
end
function generic.WaitForChild(self, name, timeout)
	local found = generic.FindFirstChild(self, name)
	if found then
		return found
	end
	local deadline = Scheduler.now + (timeout or 5)
	while Scheduler.now < deadline do
		Scheduler.task.wait(0.1)
		found = generic.FindFirstChild(self, name)
		if found then
			return found
		end
	end
	if timeout == nil then
		warn("Infinite yield possible on '" .. fullName(self) .. ':WaitForChild("' .. tostring(name) .. "\")'")
	end
	return nil
end
function generic.IsDescendantOf(self, ancestor)
	local cur = D[self].Parent
	while cur do
		if cur == ancestor then
			return true
		end
		cur = D[cur].Parent
	end
	return false
end
function generic.IsAncestorOf(self, descendant)
	return generic.IsDescendantOf(descendant, self)
end
function generic.GetFullName(self)
	return fullName(self)
end
function generic.ClearAllChildren(self)
	for _, child in table.clone(D[self].Children) do
		generic.Destroy(child)
	end
end
function generic.Destroy(self)
	local d = D[self]
	if d.Destroyed then
		return
	end
	Instances.fire(self, "Destroying")
	for _, child in table.clone(d.Children) do
		generic.Destroy(child)
	end
	if d.Parent then
		setParent(self, nil)
	end
	d.Destroyed = true
	for _, s in d.Signals do
		s.Connections = {}
	end
	for _, s in d.PropSignals do
		s.Connections = {}
	end
end
function generic.Remove(self)
	setParent(self, nil)
end
function generic.SetAttribute(self, name, value)
	if type(name) ~= "string" then
		error("SetAttribute: attribute name must be a string", 2)
	end
	local t = typeof(value)
	local allowed = {
		["nil"] = true,
		string = true,
		boolean = true,
		number = true,
		UDim = true,
		UDim2 = true,
		BrickColor = true,
		Color3 = true,
		Vector2 = true,
		Vector3 = true,
		CFrame = true,
		NumberSequence = true,
		ColorSequence = true,
		NumberRange = true,
		Rect = true,
		Font = true,
		EnumItem = true,
	}
	if not allowed[t] then
		error("SetAttribute: " .. t .. " is not a supported attribute type", 2)
	end
	local d = D[self]
	if d.Attributes[name] == value then
		return
	end
	d.Attributes[name] = value
	local s = d.AttrSignals[name]
	if s then
		Scheduler.fire(s, nil)
	end
	local changed = d.Signals.AttributeChanged
	if changed then
		Scheduler.fire(changed, nil, name)
	end
end
function generic.GetAttribute(self, name)
	return D[self].Attributes[name]
end
function generic.GetAttributes(self)
	return table.clone(D[self].Attributes)
end
function generic.GetAttributeChangedSignal(self, name)
	local d = D[self]
	local s = d.AttrSignals[name]
	if s == nil then
		s = Scheduler.signal("Attribute:" .. name)
		d.AttrSignals[name] = s
	end
	return s
end
function generic.GetPropertyChangedSignal(self, name)
	local d = D[self]
	local info = resolved(d.ClassName)
	if info.Info.Props[name] == nil and name ~= "Parent" and name ~= "Name" and not info.Get[name] then
		error(tostring(name) .. " is not a valid property name.", 2)
	end
	local s = d.PropSignals[name]
	if s == nil then
		s = Scheduler.signal("Changed:" .. name)
		d.PropSignals[name] = s
	end
	return s
end
function generic.AddTag(self, tag)
	D[self].Tags[tag] = true
end
function generic.RemoveTag(self, tag)
	D[self].Tags[tag] = nil
end
function generic.HasTag(self, tag)
	return D[self].Tags[tag] == true
end
function generic.GetTags(self)
	local out = {}
	for tag in D[self].Tags do
		table.insert(out, tag)
	end
	return out
end
function generic.Clone(self)
	local d = D[self]
	local copy = Instances.new(d.ClassName)
	local cd = D[copy]
	cd.Name = d.Name
	for k, v in d.Props do
		cd.Props[k] = v
	end
	for k, v in d.Attributes do
		cd.Attributes[k] = v
	end
	for k, v in d.Tags do
		cd.Tags[k] = v
	end
	cd.SourcePath = d.SourcePath
	cd.Hidden = table.clone(d.Hidden)
	for _, child in d.Children do
		local c = generic.Clone(child)
		setParent(c, copy)
	end
	return copy
end

local ProxyMt = { __type = "Instance" }

ProxyMt.__tostring = function(self)
	local d = D[self]
	return d and d.Name or "Instance"
end

ProxyMt.__index = function(self, key)
	local d = D[self]
	if key == "Name" then
		return d.Name
	elseif key == "Parent" then
		return d.Parent
	elseif key == "ClassName" then
		return d.ClassName
	end
	local r = resolved(d.ClassName)
	local getter = r.Get[key]
	if getter then
		return getter(self, d)
	end
	local method = r.Methods[key] or generic[key]
	if method then
		return method
	end
	local v = d.Props[key]
	if v ~= nil then
		return v
	end
	local code = r.Info.Props[key]
	if code ~= nil then
		return defaultFor(code, key)
	end
	if r.Info.Events[key] then
		return signalOf(self, key)
	end
	if r.Info.Methods[key] then
		return function(...)
			local id = d.ClassName .. ":" .. key
			Instances.unimplemented[id] = (Instances.unimplemented[id] or 0) + 1
			return nil
		end
	end
	local child = generic.FindFirstChild(self, key)
	if child then
		return child
	end
	error(string.format('%s is not a valid member of %s "%s"', tostring(key), d.ClassName, fullName(self)), 2)
end

ProxyMt.__newindex = function(self, key, value)
	local d = D[self]
	if key == "Parent" then
		setParent(self, value)
		return
	elseif key == "Name" then
		if type(value) ~= "string" then
			value = tostring(value)
		end
		if d.Name ~= value then
			d.Name = value
			firePropChanged(self, "Name")
		end
		return
	elseif key == "ClassName" then
		error("ClassName is read-only", 2)
	end
	local r = resolved(d.ClassName)
	local setter = r.Set[key]
	if setter then
		setter(self, d, value)
		firePropChanged(self, key)
		return
	end
	local code = r.Info.Props[key]
	if code == nil then
		error(string.format('%s is not a valid member of %s "%s"', tostring(key), d.ClassName, fullName(self)), 2)
	end
	value = checkType(d.ClassName, key, code, value)
	if d.Props[key] ~= value then
		d.Props[key] = value
		firePropChanged(self, key)
	end
end

ProxyMt.__eq = rawequal

function Instances.new(className: string, parent)
	if Dump.Classes[className] == nil then
		error('Unable to create an Instance of type "' .. tostring(className) .. '"', 2)
	end
	local proxy = setmetatable({}, ProxyMt)
	D[proxy] = {
		ClassName = className,
		Name = className,
		Parent = nil,
		Children = {},
		Props = {},
		Attributes = {},
		Tags = {},
		Signals = {},
		PropSignals = {},
		AttrSignals = {},
		Hidden = {},
	}
	local init = Instances.initializers[className]
	if init then
		init(proxy, D[proxy])
	end
	if parent then
		proxy.Parent = parent
	end
	return proxy
end
Instances.initializers = {}

function Instances.isInstance(v): boolean
	return type(v) == "table" and D[v] ~= nil
end

function Instances.setProp(self, key, value)
	D[self].Props[key] = value
end

---------------------------------------------------------------------------
-- Class behaviour
---------------------------------------------------------------------------

local function partCF(d)
	return d.Props.CFrame or CF.identity
end

special.BasePart = {
	get = {
		Position = function(_, d)
			return partCF(d).Position
		end,
		Orientation = function(_, d)
			local x, y, z = partCF(d):ToEulerAnglesYXZ()
			return V3.new(math.deg(x), math.deg(y), math.deg(z))
		end,
		CFrame = function(_, d)
			return partCF(d)
		end,
		Size = function(_, d)
			return d.Props.Size or V3.new(4, 1, 2)
		end,
		Transparency = function(_, d)
			return d.Props.Transparency or 0
		end,
		Anchored = function(_, d)
			return d.Props.Anchored or false
		end,
		CanCollide = function(_, d)
			if d.Props.CanCollide == nil then
				return true
			end
			return d.Props.CanCollide
		end,
		Color = function(_, d)
			return d.Props.Color or Types.Color3.fromRGB(163, 162, 165)
		end,
	},
	set = {
		Position = function(_, d, v)
			d.Props.CFrame = partCF(d).Rotation + v
		end,
		CFrame = function(_, d, v)
			if typeof(v) ~= "CFrame" then
				error("Unable to assign property CFrame. CFrame expected, got " .. typeof(v), 3)
			end
			d.Props.CFrame = v
		end,
		Orientation = function(_, d, v)
			d.Props.CFrame = CF.new(partCF(d).Position)
				* CF.fromEulerAnglesYXZ(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
		end,
		Size = function(_, d, v)
			if typeof(v) ~= "Vector3" then
				error("Unable to assign property Size. Vector3 expected, got " .. typeof(v), 3)
			end
			d.Props.Size = v
		end,
	},
	methods = {
		GetPivot = function(self)
			return D[self].Props.CFrame or CF.identity
		end,
		PivotTo = function(self, cf)
			self.CFrame = cf
		end,
		GetMass = function()
			return 1
		end,
		SetNetworkOwner = function() end,
		GetNetworkOwner = function()
			return nil
		end,
		CanSetNetworkOwnership = function()
			return true
		end,
	},
}

local function modelParts(self)
	local out = {}
	for _, dsc in descendants(self, {}) do
		if isA(D[dsc].ClassName, "BasePart") then
			table.insert(out, dsc)
		end
	end
	return out
end

local function modelPivot(self, d)
	local primary = d.Props.PrimaryPart
	if primary and D[primary] and not D[primary].Destroyed then
		return primary.CFrame
	end
	if d.Props.WorldPivot then
		return d.Props.WorldPivot
	end
	local parts = modelParts(self)
	if #parts == 0 then
		return CF.identity
	end
	local sum = V3.zero
	for _, p in parts do
		sum += p.Position
	end
	return CF.new(sum / #parts)
end

special.Model = {
	get = {
		WorldPivot = function(self, d)
			return modelPivot(self, d)
		end,
	},
	methods = {
		GetPivot = function(self)
			return modelPivot(self, D[self])
		end,
		PivotTo = function(self, target)
			local d = D[self]
			local current = modelPivot(self, d)
			local delta = target * current:Inverse()
			for _, p in modelParts(self) do
				p.CFrame = delta * p.CFrame
			end
			if d.Props.WorldPivot and not d.Props.PrimaryPart then
				d.Props.WorldPivot = target
			end
		end,
		GetBoundingBox = function(self)
			return modelPivot(self, D[self]), V3.new(4, 4, 4)
		end,
		GetExtentsSize = function()
			return V3.new(4, 4, 4)
		end,
		MoveTo = function(self, pos)
			self:PivotTo(CF.new(pos))
		end,
	},
}

special.Attachment = {
	get = {
		WorldCFrame = function(self, d)
			local parent = d.Parent
			local base = if parent and isA(D[parent].ClassName, "BasePart") then parent.CFrame else CF.identity
			return base * (d.Props.CFrame or CF.identity)
		end,
		WorldPosition = function(self, d)
			return self.WorldCFrame.Position
		end,
		Position = function(_, d)
			return (d.Props.CFrame or CF.identity).Position
		end,
	},
	set = {
		WorldCFrame = function(self, d, v)
			local parent = d.Parent
			local base = if parent and isA(D[parent].ClassName, "BasePart") then parent.CFrame else CF.identity
			d.Props.CFrame = base:Inverse() * v
		end,
		WorldPosition = function(self, d, v)
			local parent = d.Parent
			local base = if parent and isA(D[parent].ClassName, "BasePart") then parent.CFrame else CF.identity
			d.Props.CFrame = CF.new(base:PointToObjectSpace(v))
		end,
		Position = function(_, d, v)
			d.Props.CFrame = (d.Props.CFrame or CF.identity).Rotation + v
		end,
	},
}

special.Sound = {
	get = {
		TimeLength = function(_, d)
			return d.Props.TimeLength or 1.2
		end,
		Volume = function(_, d)
			return d.Props.Volume or 0.5
		end,
		PlaybackSpeed = function(_, d)
			return d.Props.PlaybackSpeed or 1
		end,
	},
	methods = {
		Play = function(self)
			local d = D[self]
			d.Props.IsPlaying = true
			d.Props.Playing = true
			Instances.plays = (Instances.plays or 0) + 1
			local token = {}
			d.Hidden.PlayToken = token
			if not d.Props.Looped then
				Scheduler.task.delay(1.2, function()
					if d.Hidden.PlayToken == token then
						d.Props.IsPlaying = false
						d.Props.Playing = false
						Instances.fire(self, "Ended", d.Props.SoundId)
					end
				end)
			end
		end,
		Stop = function(self)
			local d = D[self]
			d.Props.IsPlaying = false
			d.Props.Playing = false
			d.Hidden.PlayToken = nil
		end,
		Pause = function(self)
			D[self].Props.IsPlaying = false
		end,
		Resume = function(self)
			D[self].Props.IsPlaying = true
		end,
	},
}

special.ParticleEmitter = {
	methods = {
		Emit = function(self, n)
			if type(n) ~= "number" then
				error("Emit expects a number", 2)
			end
			Instances.emitted = (Instances.emitted or 0) + n
		end,
		Clear = function() end,
	},
}

-- GUI geometry: an approximate layout (scale of parent + offset), enough for
-- code that positions tooltips or reads sizes.
local VIEWPORT = V2.new(1280, 720)
Instances.viewport = VIEWPORT

local function guiAbsolute(self, d)
	local parent = d.Parent
	local parentSize, parentPos = VIEWPORT, V2.zero
	if parent and isA(D[parent].ClassName, "GuiObject") then
		parentSize = parent.AbsoluteSize
		parentPos = parent.AbsolutePosition
	end
	local size = d.Props.Size or Types.UDim2.new()
	local pos = d.Props.Position or Types.UDim2.new()
	local anchor = d.Props.AnchorPoint or V2.zero
	local abs = V2.new(parentSize.X * size.X.Scale + size.X.Offset, parentSize.Y * size.Y.Scale + size.Y.Offset)
	local p = V2.new(
		parentPos.X + parentSize.X * pos.X.Scale + pos.X.Offset - abs.X * anchor.X,
		parentPos.Y + parentSize.Y * pos.Y.Scale + pos.Y.Offset - abs.Y * anchor.Y
	)
	return abs, p
end

special.GuiObject = {
	get = {
		AbsoluteSize = function(self, d)
			local s = guiAbsolute(self, d)
			return s
		end,
		AbsolutePosition = function(self, d)
			local _, p = guiAbsolute(self, d)
			return p
		end,
		Visible = function(_, d)
			if d.Props.Visible == nil then
				return true
			end
			return d.Props.Visible
		end,
	},
	methods = {
		TweenPosition = function(self, pos)
			self.Position = pos
			return true
		end,
		TweenSize = function(self, size)
			self.Size = size
			return true
		end,
		TweenSizeAndPosition = function(self, size, pos)
			self.Size = size
			self.Position = pos
			return true
		end,
	},
}

special.LayerCollector = {
	get = {
		AbsoluteSize = function()
			return VIEWPORT
		end,
		AbsolutePosition = function()
			return V2.zero
		end,
	},
}

special.TextLabel = {
	get = {
		TextBounds = function(_, d)
			return V2.new(#(d.Props.Text or "") * 7, d.Props.TextSize or 14)
		end,
		TextFits = function()
			return true
		end,
	},
}
special.TextButton = { get = { TextBounds = special.TextLabel.get.TextBounds } }
special.TextBox = {
	get = { TextBounds = special.TextLabel.get.TextBounds },
	methods = {
		CaptureFocus = function() end,
		ReleaseFocus = function() end,
		IsFocused = function()
			return false
		end,
	},
}

special.UIGridStyleLayout = {
	get = {
		AbsoluteContentSize = function()
			return V2.new(100, 100)
		end,
	},
}

special.ScrollingFrame = {
	get = {
		AbsoluteCanvasSize = function(self)
			return self.AbsoluteSize
		end,
		AbsoluteWindowSize = function(self)
			return self.AbsoluteSize
		end,
	},
}

special.Camera = {
	get = {
		ViewportSize = function()
			return VIEWPORT
		end,
		FieldOfView = function(_, d)
			return d.Props.FieldOfView or 70
		end,
		Focus = function(_, d)
			return d.Props.Focus or CF.identity
		end,
	},
	methods = {
		WorldToViewportPoint = function(self, p)
			return V3.new(640, 360, 10), true
		end,
		WorldToScreenPoint = function(self, p)
			return V3.new(640, 360, 10), true
		end,
		ViewportPointToRay = function(self)
			return { Origin = self.CFrame.Position, Direction = self.CFrame.LookVector }
		end,
		ScreenPointToRay = function(self)
			return { Origin = self.CFrame.Position, Direction = self.CFrame.LookVector }
		end,
	},
}

special.Humanoid = {
	get = {
		Health = function(_, d)
			return d.Props.Health or 100
		end,
		MaxHealth = function(_, d)
			return d.Props.MaxHealth or 100
		end,
		WalkSpeed = function(_, d)
			return d.Props.WalkSpeed or 16
		end,
		RigType = function(_, d)
			return d.Props.RigType or Instances.Enum.HumanoidRigType.R6
		end,
	},
	methods = {
		MoveTo = function() end,
		ChangeState = function() end,
		GetState = function()
			return Instances.Enum.HumanoidStateType.Running
		end,
		TakeDamage = function(self, n)
			self.Health = math.max(0, self.Health - n)
		end,
		ApplyDescription = function() end,
		GetAppliedDescription = function()
			return Instances.new("HumanoidDescription")
		end,
		SetStateEnabled = function() end,
	},
}

special.Animator = {
	methods = {
		GetPlayingAnimationTracks = function()
			return {}
		end,
		LoadAnimation = function()
			error("mock: LoadAnimation not modelled", 2)
		end,
	},
}

-- Tweens complete instantly (properties applied at Play) and fire Completed
-- after their duration, which is what the codebase's awaits rely on.
special.TweenBase = {
	methods = {
		Play = function(self)
			local d = D[self]
			if d.Hidden.Played then
				return
			end
			d.Hidden.Played = true
			local target = d.Hidden.Target
			if target and D[target] and not D[target].Destroyed then
				for k, v in d.Hidden.Goals do
					target[k] = v
				end
			end
			d.Props.PlaybackState = Instances.Enum.PlaybackState.Playing
			Scheduler.task.delay(d.Hidden.Duration or 0, function()
				d.Props.PlaybackState = Instances.Enum.PlaybackState.Completed
				Instances.fire(self, "Completed", Instances.Enum.PlaybackState.Completed)
			end)
		end,
		Cancel = function(self)
			D[self].Props.PlaybackState = Instances.Enum.PlaybackState.Cancelled
		end,
		Pause = function() end,
	},
}

special.ProximityPrompt = {
	methods = {
		InputHoldBegin = function() end,
		InputHoldEnd = function() end,
	},
}

return Instances

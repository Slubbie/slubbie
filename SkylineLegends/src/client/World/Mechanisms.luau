-- Animates every mechanism in the world on this client.
--
-- Moving platforms, swinging cargo, spinners, timed doors, retracting bridges,
-- blinking holograms, lasers, collapsing planks, pressure-plate gates and
-- rising water are all pure functions of shared server time (Logic/Schedule),
-- so every player sees the same door open at the same instant without the
-- server streaming a single CFrame. Parts are moved before physics each step
-- and the local runner is carried by whatever it stands on.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MathUtil = require(ReplicatedStorage.Shared.Util.MathUtil)
local Net = require(ReplicatedStorage.Shared.Net)
local Schedule = require(ReplicatedStorage.Shared.Logic.Schedule)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Tags = require(ReplicatedStorage.Shared.Tags)

local Settings = require(script.Parent.Parent.Core.Settings)
local Controller = require(script.Parent.Parent.Movement.Controller)

local Mechanisms = {}

-- (switchId, secondsRemaining) whenever a gate the runner opened changes.
Mechanisms.SwitchChanged = Signal.new()
-- (part) when a collapsing plank starts to give way under the runner.
Mechanisms.Cracking = Signal.new()

type Entry = {
	Part: BasePart,
	Tag: string,
	Kind: string,
	Home: Vector3,
	Origin: CFrame,
	Last: CFrame,
	Base: { Transparency: number, Color: Color3, CanCollide: boolean },
	Emitters: { { Emitter: ParticleEmitter, Rate: number } }?,
	-- Collapse
	TriggeredAt: number?,
	FallAt: number?,
	-- Switch gates
	Open: number?,
	-- Water
	RiseStart: number?,
	Top: number?,
	-- Lasers: last visual mode, so sizes only change when it does
	Mode: string?,
}

local entries: { [BasePart]: Entry } = {}
local list: { Entry } = {}
local dirty = false
local live: { [BasePart]: boolean } = {}

local switchUntil: { [string]: number } = {} -- server time each gate stays open until
local lastPress: { [string]: number } = {}
local course: { Id: string?, Checkpoint: number, Restarted: number } = { Id = nil, Checkpoint = 0, Restarted = 0 }

local frame = 0
local WARN_COLOR = Color3.fromRGB(255, 176, 40)
local STOP_COLOR = Color3.fromRGB(235, 60, 60)
local GO_COLOR = Color3.fromRGB(80, 255, 120)

local function attr(part: Instance, name: string, default: any): any
	local value = part:GetAttribute(name)
	if value == nil then
		return default
	end
	return value
end

local function vector(part: Instance, name: string): Vector3
	local value = part:GetAttribute(name)
	return if typeof(value) == "Vector3" then value else Vector3.zero
end

-- Registration ----------------------------------------------------------------------------------

local function register(instance: Instance, tag: string)
	if not instance:IsA("BasePart") then
		return
	end
	local part = instance
	if entries[part] then
		return
	end
	local origin = part:GetAttribute("Origin")
	local originCF = if typeof(origin) == "CFrame" then origin else part.CFrame
	local kind = attr(part, "Kind", tag)
	local home = originCF.Position
	local center = part:GetAttribute("Center")
	local pivot = part:GetAttribute("Pivot")
	if typeof(center) == "Vector3" then
		home = center
	elseif typeof(pivot) == "Vector3" then
		home = pivot
	end
	local entry: Entry = {
		Part = part,
		Tag = tag,
		Kind = kind,
		Home = home,
		Origin = originCF,
		Last = part.CFrame,
		Base = { Transparency = part.Transparency, Color = part.Color, CanCollide = part.CanCollide },
	}
	if tag == Tags.WindZone or tag == Tags.LaunchVent then
		local emitters = {}
		for _, descendant in part:GetDescendants() do
			if descendant:IsA("ParticleEmitter") then
				table.insert(emitters, { Emitter = descendant, Rate = descendant.Rate })
			end
		end
		entry.Emitters = emitters
	end
	if tag == Tags.SwitchGate then
		entry.Open = 0
	end
	entries[part] = entry
	dirty = true
end

local function unregister(instance: Instance)
	if instance:IsA("BasePart") and entries[instance] then
		entries[instance] = nil
		live[instance] = nil
		dirty = true
	end
end

local MANAGED = { Tags.Mover, Tags.Timed, Tags.Collapse, Tags.Switch, Tags.SwitchGate, Tags.Water, Tags.WindZone, Tags.LaunchVent }

-- Behaviour ---------------------------------------------------------------------------------------

-- 0..1 openness of a timed part with a short ease at each change.
local function timedOpenness(t: number, part: BasePart): (number, boolean, boolean)
	local period = attr(part, "Period", 4)
	local onFraction = attr(part, "OnFraction", 0.5)
	local phase = attr(part, "Phase", 0)
	local warn = attr(part, "Warn", 0.6)
	local on, warning = Schedule.Cycle(t, period, onFraction, phase, warn)
	local into = Schedule.Fraction(t, period, phase) * period
	local onTime = period * onFraction
	local ease = 0.35
	local a
	if into < onTime then
		a = math.clamp(into / ease, 0, 1)
	else
		a = 1 - math.clamp((into - onTime) / ease, 0, 1)
	end
	return MathUtil.Smooth(a), on, warning
end

local function blinkOn(t: number, hz: number): boolean
	return (t * hz) % 1 < 0.5
end

local function stepMover(entry: Entry, t: number): CFrame?
	local part = entry.Part
	local kind = entry.Kind
	if kind == "Shuttle" or kind == "Linear" then
		local a = Schedule.Shuttle(t, attr(part, "Period", 6), attr(part, "Phase", 0), attr(part, "Hold", 0.3))
		return entry.Origin + vector(part, "Offset") * a
	elseif kind == "Orbit" then
		local angle = Schedule.Fraction(t, attr(part, "Period", 9), attr(part, "Phase", 0)) * math.pi * 2
		local radius = attr(part, "Radius", 10)
		local center = vector(part, "Center")
		return CFrame.new(center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)) * entry.Origin.Rotation
	elseif kind == "Pendulum" or kind == "PendulumRod" then
		local angle = Schedule.Pendulum(t, attr(part, "Period", 4), attr(part, "Amplitude", 0.4), attr(part, "Phase", 0))
		local pivot = vector(part, "Pivot")
		local axis = vector(part, "Axis")
		if axis.Magnitude < 0.5 then
			axis = Vector3.xAxis
		end
		local swing = CFrame.new(pivot) * CFrame.fromAxisAngle(axis.Unit, angle) * CFrame.new(-pivot)
		if kind == "PendulumRod" then
			return swing * entry.Origin
		end
		-- Cargo hangs level from parallel chains, so it's always safe to land on.
		return CFrame.new((swing * entry.Origin).Position) * entry.Origin.Rotation
	elseif kind == "Spin" then
		return entry.Origin * CFrame.Angles(0, math.rad(attr(part, "Speed", 30)) * t % (math.pi * 2), 0)
	end
	return nil
end

local function stepTimed(entry: Entry, t: number): CFrame?
	local part = entry.Part
	local kind = entry.Kind
	if kind == "Door" then
		local a = timedOpenness(t, part)
		return entry.Origin + vector(part, "Offset") * a
	elseif kind == "Retract" then
		local a, on, warning = timedOpenness(t, part)
		local cf = entry.Origin + vector(part, "Offset") * (1 - a)
		if on and warning and not Settings.Get("ReducedMotion") then
			-- A shudder before it pulls away.
			cf *= CFrame.new(math.sin(t * 60) * 0.06, 0, 0)
		end
		return cf
	elseif kind == "Blink" then
		local _, on, warning = timedOpenness(t, part)
		local base = entry.Base.Transparency
		if on then
			part.CanCollide = true
			part.Transparency = if warning and blinkOn(t, 7) then math.max(base, 0.55) else base
		else
			part.CanCollide = false
			part.Transparency = if warning and blinkOn(t, 5) then 0.6 else 0.88
		end
		live[part] = on
	elseif kind == "Laser" then
		local _, on, warning = timedOpenness(t, part)
		local mode = if on then "On" else "Off"
		if mode ~= entry.Mode then
			entry.Mode = mode
			local thickness = if on then 0.3 else 0.08
			part.Size = Vector3.new(part.Size.X, thickness, thickness)
		end
		if on then
			part.Transparency = entry.Base.Transparency
		elseif warning then
			-- About to fire: a thin flickering sighting line.
			part.Transparency = if blinkOn(t, 9) then 0.35 else 0.85
		else
			part.Transparency = 0.94
		end
		live[part] = on
	elseif kind == "LaserSweep" then
		local a = Schedule.PingPong(t, attr(part, "Period", 3), attr(part, "Phase", 0))
		live[part] = true
		return entry.Origin + vector(part, "Offset") * a
	elseif kind == "Lamp" then
		local _, on, warning = timedOpenness(t, part)
		-- Steady = safe, blinking = about to change, dim = closed. Readable without colour.
		if attr(part, "Traffic", false) then
			if warning then
				part.Color = WARN_COLOR
				part.Transparency = if blinkOn(t, 4) then 0 else 0.7
			elseif on then
				part.Color = GO_COLOR
				part.Transparency = 0
			else
				part.Color = STOP_COLOR
				part.Transparency = 0.45
			end
		else
			if warning and on then
				part.Color = WARN_COLOR
				part.Transparency = if blinkOn(t, 5) then 0 else 0.8
			elseif on then
				part.Color = WARN_COLOR
				part.Transparency = 0.5
			else
				part.Color = STOP_COLOR
				part.Transparency = 0.2
			end
		end
	end
	return nil
end

local function stepCollapse(entry: Entry, t: number, floor: BasePart?): CFrame?
	local part = entry.Part
	local clock = os.clock()
	if not entry.TriggeredAt then
		if floor == part then
			entry.TriggeredAt = clock
			entry.FallAt = clock + attr(part, "Delay", 0.45)
			Mechanisms.Cracking:Fire(part)
		end
		return nil
	end
	local fallAt = entry.FallAt or clock
	if clock < fallAt then
		-- Shake while it gives way.
		if Settings.Get("ReducedMotion") then
			return nil
		end
		local strength = 0.08 + 0.12 * (1 - (fallAt - clock) / attr(part, "Delay", 0.45))
		return entry.Origin * CFrame.new(math.sin(t * 71) * strength, 0, math.cos(t * 53) * strength) * CFrame.Angles(0, 0, math.sin(t * 40) * strength * 0.2)
	end
	local fallen = clock - fallAt
	if fallen < 0.01 + attr(part, "Respawn", 3.5) then
		part.CanCollide = false
		local drop = 0.5 * 90 * math.min(fallen, 1.4) ^ 2
		part.Transparency = math.clamp(entry.Base.Transparency + fallen * 0.8, 0, 1)
		return entry.Origin * CFrame.new(0, -drop, 0) * CFrame.Angles(fallen * 0.6, 0, fallen * 0.3)
	end
	-- Rebuilt.
	entry.TriggeredAt, entry.FallAt = nil, nil
	part.CanCollide = entry.Base.CanCollide
	part.Transparency = entry.Base.Transparency
	return entry.Origin
end

local function pressSwitch(entry: Entry, t: number)
	local part = entry.Part
	local id = attr(part, "SwitchId", "")
	local duration = attr(part, "Duration", 5)
	local wasOpen = (switchUntil[id] or 0) > t
	switchUntil[id] = math.max(switchUntil[id] or 0, t + duration)
	if not wasOpen then
		Mechanisms.SwitchChanged:Fire(id, duration)
	end
	-- Tell the server (co-op partners see the gate open too), at most once a second.
	if os.clock() - (lastPress[id] or 0) > 1 then
		lastPress[id] = os.clock()
		Net.Send("Switch.Press", id)
	end
end

local function stepSwitch(entry: Entry, t: number, root: BasePart?, floor: BasePart?)
	local part = entry.Part
	local id = attr(part, "SwitchId", "")
	if root and (floor == part or MathUtil.InBox(part.CFrame * CFrame.new(0, 2.5, 0), part.Size + Vector3.new(0.5, 5, 0.5), root.Position)) then
		pressSwitch(entry, t)
	end
	local remaining = (switchUntil[id] or 0) - t
	if remaining > 0 then
		part.Color = if remaining < 1.5 and blinkOn(t, 4) then WARN_COLOR else GO_COLOR
	else
		part.Color = entry.Base.Color
	end
end

local function stepGate(entry: Entry, t: number, dt: number): CFrame?
	local part = entry.Part
	local id = attr(part, "SwitchId", "")
	local open = (switchUntil[id] or 0) > t
	local current = entry.Open or 0
	local target = if open then 1 else 0
	current = MathUtil.Approach(current, target, dt * 3)
	entry.Open = current
	part.CanCollide = current < 0.7 and entry.Base.CanCollide
	part.Transparency = entry.Base.Transparency + (1 - entry.Base.Transparency) * current * 0.6
	return entry.Origin + vector(part, "Offset") * MathUtil.Smooth(current)
end

local function stepWater(entry: Entry, t: number): CFrame?
	local part = entry.Part
	local baseY = attr(part, "BaseY", entry.Origin.Y)
	local active = course.Id == attr(part, "CourseId", "") and course.Checkpoint >= attr(part, "StartCP", 1)
	if not active then
		entry.RiseStart = nil
		live[part] = false
		entry.Top = baseY
		return entry.Origin
	end
	if not entry.RiseStart or entry.RiseStart < course.Restarted then
		entry.RiseStart = math.max(t, course.Restarted)
	end
	local riseStart = entry.RiseStart :: number
	-- A short grace before the water starts to climb.
	local rise = math.max(t - riseStart - 1.5, 0) * attr(part, "Rate", 1.8)
	local top = math.min(baseY + rise, attr(part, "MaxY", baseY + 60))
	entry.Top = top
	live[part] = top > baseY + 0.5
	return entry.Origin + Vector3.new(0, top - baseY, 0)
end

local function stepCycleFx(entry: Entry, t: number)
	local emitters = entry.Emitters
	if not emitters or #emitters == 0 then
		return
	end
	local part = entry.Part
	local on, warning = Schedule.Cycle(t, attr(part, "Period", 4), attr(part, "OnFraction", 0.4), attr(part, "Phase", 0), attr(part, "Warn", 0.8))
	local scale = if on then 1 elseif warning then 0.25 else 0.04
	for _, item in emitters do
		item.Emitter.Rate = item.Rate * scale
	end
end

-- Frame step ------------------------------------------------------------------------------------

local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}

local function step(dt: number)
	frame += 1
	if dirty then
		dirty = false
		list = {}
		for _, entry in entries do
			table.insert(list, entry)
		end
	end
	local t = Schedule.Now()
	local camera = workspace.CurrentCamera
	local focus = if camera then camera.CFrame.Position else Vector3.zero
	local info = Controller.Info
	local root = info.Root
	local floor = info.Floor
	local near = if root then root.Position else focus
	local climbing = root ~= nil and info.State == "Climb"

	table.clear(moveParts)
	table.clear(moveFrames)
	local carried: { { Part: BasePart, Delta: CFrame } } = {}

	for index, entry in list do
		local part = entry.Part
		if not part.Parent then
			continue
		end
		local distance = math.min((entry.Home - focus).Magnitude, (entry.Home - near).Magnitude)
		-- Far mechanisms update rarely; very far ones not at all (they're pure functions of time).
		if distance > 1100 then
			continue
		elseif distance > 450 and (frame + index) % 4 ~= 0 then
			continue
		end
		local tag = entry.Tag
		local target: CFrame? = nil
		if tag == Tags.Mover then
			target = stepMover(entry, t)
		elseif tag == Tags.Timed then
			target = stepTimed(entry, t)
		elseif tag == Tags.Collapse then
			target = stepCollapse(entry, t, floor)
		elseif tag == Tags.Switch then
			stepSwitch(entry, t, root, floor)
		elseif tag == Tags.SwitchGate then
			target = stepGate(entry, t, dt)
		elseif tag == Tags.Water then
			target = stepWater(entry, t)
		elseif tag == Tags.WindZone or tag == Tags.LaunchVent then
			stepCycleFx(entry, t)
		end
		if target and target ~= entry.Last then
			if part == floor or (climbing and (part.Position - near).Magnitude < part.Size.Magnitude / 2 + 6) then
				table.insert(carried, { Part = part, Delta = target * entry.Last:Inverse() })
			end
			entry.Last = target
			table.insert(moveParts, part)
			table.insert(moveFrames, target)
		end
	end

	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	Controller.PlatformCheck()
	-- Carry ignores parts that aren't what the runner stands on or climbs.
	for _, item in carried do
		Controller.Carry(item.Part, item.Delta, dt)
	end
end

-- Public -------------------------------------------------------------------------------------------

-- Is a hazard part currently dangerous? (lasers off, water not rising → false)
function Mechanisms.IsLive(part: BasePart): boolean
	local value = live[part]
	if value ~= nil then
		return value
	end
	return part:GetAttribute("Active") ~= false
end

-- The course system reports progress so rising water knows when to climb.
-- `restarted` resets the water (a checkpoint retry gives you a fair go).
function Mechanisms.SetCourse(courseId: string?, checkpoint: number, restarted: boolean?)
	course.Id = courseId
	course.Checkpoint = checkpoint
	if restarted then
		course.Restarted = Schedule.Now()
	end
end

-- Rebuild every collapsed plank and close every gate (fresh attempt).
function Mechanisms.ResetCourseState()
	for _, entry in entries do
		if entry.Tag == Tags.Collapse and entry.TriggeredAt then
			entry.TriggeredAt, entry.FallAt = nil, nil
			entry.Part.CanCollide = entry.Base.CanCollide
			entry.Part.Transparency = entry.Base.Transparency
			entry.Part.CFrame = entry.Origin
			entry.Last = entry.Origin
		end
	end
	table.clear(switchUntil)
end

-- Height of the rising water on a course (nil when it isn't rising).
function Mechanisms.WaterLevel(courseId: string): number?
	for _, entry in entries do
		if entry.Tag == Tags.Water and entry.Part:GetAttribute("CourseId") == courseId and live[entry.Part] then
			return entry.Top
		end
	end
	return nil
end

-- Sweeper arms: where they'd knock the runner, if they're touching.
local function checkSweepers()
	local info = Controller.Info
	local root = info.Root
	if not root then
		return
	end
	local feet = root.Position - Vector3.new(0, 3, 0)
	for _, entry in list do
		if entry.Tag == Tags.Mover and entry.Kind == "Spin" and entry.Part:GetAttribute("Sweeper") then
			local part = entry.Part
			if (entry.Home - root.Position).Magnitude < part.Size.Magnitude then
				local hit = false
				for _, y in { 0.4, 1.4, 2.4 } do
					if MathUtil.InBox(part.CFrame, part.Size, feet + Vector3.new(0, y, 0), 0.6) then
						hit = true
						break
					end
				end
				if hit then
					local speed = math.rad(attr(part, "Speed", 60))
					local offset = MathUtil.Flat(root.Position - entry.Home)
					local tangent = Vector3.yAxis:Cross(offset) * speed
					local push = if tangent.Magnitude > 0.1 then tangent.Unit else MathUtil.FlatUnit(offset)
					Controller.Impulse(push * 38 + Vector3.yAxis * 34, "Knocked")
				end
			end
		end
	end
end

function Mechanisms.Start()
	for _, tag in MANAGED do
		for _, instance in CollectionService:GetTagged(tag) do
			register(instance, tag)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance)
			register(instance, tag)
		end)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(unregister)
	end
	Net.Listen("Switch.Opened", function(id: string, untilTime: number)
		if type(id) == "string" and type(untilTime) == "number" then
			local was = switchUntil[id] or 0
			switchUntil[id] = math.max(was, untilTime)
			if was < Schedule.Now() then
				Mechanisms.SwitchChanged:Fire(id, untilTime - Schedule.Now())
			end
		end
	end)
	RunService.PreSimulation:Connect(step)
	RunService.Heartbeat:Connect(checkSweepers)
end

return Mechanisms

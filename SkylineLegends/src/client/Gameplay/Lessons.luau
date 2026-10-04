-- Interactive lessons in the Training Yard. Stepping onto a station shows its
-- card: the technique, the input for your device, and two short steps that
-- track your real moves. Falling off a station puts you back on its pad.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Abilities = require(ReplicatedStorage.Shared.Config.Abilities)
local Lessons = require(ReplicatedStorage.Shared.Config.Lessons)
local MathUtil = require(ReplicatedStorage.Shared.Util.MathUtil)
local Net = require(ReplicatedStorage.Shared.Net)
local Tags = require(ReplicatedStorage.Shared.Tags)

local Bus = require(script.Parent.Parent.Core.Bus)
local State = require(script.Parent.Parent.Core.State)
local Controller = require(script.Parent.Parent.Movement.Controller)
local Hazards = require(script.Parent.Parent.World.Hazards)
local Sfx = require(script.Parent.Parent.Audio.Sfx)

local LessonsClient = {}

type Active = { Lesson: Lessons.Lesson, Zone: BasePart, Step: number, Count: number, Recent: { { Action: string, Time: number } }, Sent: boolean }

local zones: { BasePart } = {}
local active: Active? = nil

local function indexZones()
	table.clear(zones)
	for _, part in CollectionService:GetTagged(Tags.LessonZone) do
		if part:IsA("BasePart") then
			table.insert(zones, part)
		end
	end
end

local function done(lessonId: string): boolean
	local profile = State.Profile
	return profile ~= nil and profile.Lessons ~= nil and profile.Lessons[lessonId] ~= nil
end

local function publish()
	local a = active
	if not a then
		Bus.Lesson:Fire(nil, 0, 0)
		return
	end
	Bus.Lesson:Fire(a.Lesson, a.Step, a.Count)
end

local function leave()
	if active then
		active = nil
		Hazards.PopHandler("Lesson")
		Hazards.KillY = nil
		publish()
	end
end

local function enter(zone: BasePart, lesson: Lessons.Lesson)
	local state: Active = { Lesson = lesson, Zone = zone, Step = 1, Count = 0, Recent = {}, Sent = false }
	if done(lesson.Id) then
		state.Step = #lesson.Steps + 1
	end
	active = state
	local killY = zone:GetAttribute("KillY")
	Hazards.KillY = if type(killY) == "number" then killY else nil
	Hazards.PushHandler("Lesson", function(): CFrame?
		local spawn = zone:GetAttribute("Spawn")
		if typeof(spawn) == "CFrame" then
			Net.Send("Lesson.Reset", lesson.Id)
			return spawn
		end
		return nil
	end)
	publish()
end

local function chainMatches(recent: { { Action: string, Time: number } }, chain: { string }): boolean
	local index = 1
	local now = os.clock()
	for _, entry in recent do
		if now - entry.Time < 4 and entry.Action == chain[index] then
			index += 1
			if index > #chain then
				return true
			end
		end
	end
	return false
end

local function onAction(action: string)
	local a = active
	if not a or a.Step > #a.Lesson.Steps then
		return
	end
	if a.Lesson.Ability and not State.Has(a.Lesson.Ability) then
		return
	end
	table.insert(a.Recent, { Action = action, Time = os.clock() })
	if #a.Recent > 10 then
		table.remove(a.Recent, 1)
	end
	local step = a.Lesson.Steps[a.Step]
	local advanced = false
	if step.Chain then
		if chainMatches(a.Recent, step.Chain) then
			advanced = true
		end
	elseif step.Action == action then
		a.Count += 1
		if a.Count >= (step.Count or 1) then
			advanced = true
		end
	end
	if advanced then
		a.Step += 1
		a.Count = 0
		table.clear(a.Recent)
		Sfx.Stinger(if a.Step > #a.Lesson.Steps then "Unlock" else "Checkpoint")
		if a.Step > #a.Lesson.Steps and not a.Sent and not done(a.Lesson.Id) then
			a.Sent = true
			Net.Send("Lesson.Complete", a.Lesson.Id)
		end
	end
	publish()
end

-- Why a station is closed, if it is.
function LessonsClient.LockReason(lesson: Lessons.Lesson): string?
	if lesson.Ability and not State.Has(lesson.Ability) then
		local ability = Abilities.ById[lesson.Ability]
		return if ability then ("Unlocks at level %d (%s)"):format(ability.Level, ability.Name) else "Locked"
	end
	return nil
end

function LessonsClient.Active(): Active?
	return active
end

function LessonsClient.Start()
	indexZones()
	CollectionService:GetInstanceAddedSignal(Tags.LessonZone):Connect(function()
		task.defer(indexZones)
	end)
	Controller.Action:Connect(onAction)
	local last = 0
	RunService.Heartbeat:Connect(function()
		if os.clock() - last < 0.25 then
			return
		end
		last = os.clock()
		local root = Controller.Info.Root
		if not root then
			return
		end
		local position = root.Position
		local a = active
		if a then
			if not MathUtil.InBox(a.Zone.CFrame, a.Zone.Size, position, 6) then
				leave()
			end
			return
		end
		for _, zone in zones do
			if MathUtil.InBox(zone.CFrame, zone.Size, position, 0) then
				local lesson = Lessons.ById[zone:GetAttribute("LessonId")]
				if lesson then
					enter(zone, lesson)
				end
				break
			end
		end
	end)
	State.On("Lessons", function()
		publish()
	end)
end

return LessonsClient

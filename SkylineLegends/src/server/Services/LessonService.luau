-- Training Yard lessons. The client walks the player through each station's
-- steps; the server checks they were really at the station, that the lesson's
-- technique is unlocked, and that the moves it teaches were actually performed
-- (validated by the movement guard) before paying out.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lessons = require(ReplicatedStorage.Shared.Config.Lessons)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Config.Progression)
local Tags = require(ReplicatedStorage.Shared.Tags)

local DataService = require(script.Parent.Parent.Data.DataService)
local Events = require(script.Parent.Parent.Events)
local MovementGuard = require(script.Parent.MovementGuard)
local Notify = require(script.Parent.Notify)
local ProgressionService = require(script.Parent.ProgressionService)

local LessonService = {}

local zones: { [string]: BasePart } = {}
local byId: { [string]: Lessons.Lesson } = {}
-- Recent validated actions per player: { [player] = { [action] = lastTime } }
local recent: { [Player]: { [string]: number } } = {}

local function onComplete(player: Player, lessonId: any)
	if type(lessonId) ~= "string" then
		return
	end
	local lesson = byId[lessonId]
	local zone = zones[lessonId]
	local profile = DataService.Get(player)
	if not lesson or not zone or not profile or profile.Lessons[lessonId] then
		return
	end
	if lesson.Ability and not ProgressionService.HasAbility(player, lesson.Ability) then
		return
	end
	local radius = zone.Size.Magnitude / 2 + 10
	if not MovementGuard.WasNear(player, zone.Position, radius, 4) then
		return
	end
	-- Every move the lesson asks for must have been seen recently (basic jumps aren't reported).
	local seen = recent[player] or {}
	for _, step in lesson.Steps do
		local wanted = step.Chain or { step.Action }
		for _, action in wanted do
			if action and action ~= "Jump" and action ~= "Land" and os.clock() - (seen[action] or -math.huge) > 120 then
				return
			end
		end
	end
	profile.Lessons[lessonId] = os.time()
	ProgressionService.Grant(player, { XP = Progression.XP.Lesson, Credits = 20 }, nil, true)
	Notify.Send(player, {
		Kind = "Lesson",
		Title = "Lesson complete: " .. lesson.Name,
		XP = Progression.XP.Lesson,
		Credits = 20,
		Sound = "Unlock",
	})
	DataService.Push(player, "Lessons")
	DataService.MarkDirty(player)
	Events.Lesson:Fire(player, lessonId)
end

local function onReset(player: Player, lessonId: any)
	local zone = type(lessonId) == "string" and zones[lessonId]
	if not zone then
		return
	end
	local spawn = zone:GetAttribute("Spawn")
	if typeof(spawn) == "CFrame" and MovementGuard.WasNear(player, zone.Position, zone.Size.Magnitude / 2 + 40, 3) then
		MovementGuard.AllowTeleport(player, spawn.Position, 15)
	end
end

function LessonService.Start()
	for _, lesson in Lessons.List do
		byId[lesson.Id] = lesson
	end
	for _, part in CollectionService:GetTagged(Tags.LessonZone) do
		if part:IsA("BasePart") then
			local id = part:GetAttribute("LessonId")
			if type(id) == "string" then
				zones[id] = part
			end
		end
	end
	Events.Action:Connect(function(player: Player, action: string)
		local seen = recent[player]
		if not seen then
			seen = {}
			recent[player] = seen
		end
		seen[action] = os.clock()
	end)
	Players.PlayerRemoving:Connect(function(player)
		recent[player] = nil
	end)
	Net.On("Lesson.Complete", onComplete)
	Net.On("Lesson.Reset", onReset)
end

return LessonService

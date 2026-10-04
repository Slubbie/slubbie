-- Server-side event bus. Gameplay services announce validated events here and
-- progression systems (quests, achievements, mastery, dailies, crews) listen,
-- so adding a new system never means editing the systems that feed it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local Events = {
	-- (player, action: string, value: number?, district: string?)
	Action = Signal.new(),
	-- (player, chain: { string }) every time a validated chain grows
	Chain = Signal.new(),
	-- (player, chainLength: number, variety: number) when a chain ends
	ChainEnded = Signal.new(),
	-- (player, breaker: string) stumble / fall / respawn
	Break = Signal.new(),
	-- (player, tier: number, district: string?)
	FlowTier = Signal.new(),
	-- (player, result) after a validated course/room/relay finish
	CourseFinished = Signal.new(),
	-- (player, courseId, tokenIndex)
	Token = Signal.new(),
	-- (player, discoveryId, kind, district)
	Discovery = Signal.new(),
	-- (player, districtId) arrival in a district
	DistrictEntered = Signal.new(),
	-- (player, questId, quest)
	QuestCompleted = Signal.new(),
	-- (player, kind: "Contract" | "Daily" | "Weekly")
	ObjectiveCompleted = Signal.new(),
	-- (player, lessonId)
	Lesson = Signal.new(),
	-- (player, newLevel, oldLevel)
	LevelUp = Signal.new(),
	-- (player, place: number, racers: number)
	RaceFinished = Signal.new(),
	-- (player, teamSize: number)
	RelayFinished = Signal.new(),
	-- (player, floor: number)
	TowerFloor = Signal.new(),
	-- (player, sectionsThisRun: number)
	EndlessSection = Signal.new(),
	-- (player, sectionsTotal: number) when an endless run ends
	EndlessEnded = Signal.new(),
	-- (player)
	CoopSwitch = Signal.new(),
	-- (player, crewId)
	CrewJoined = Signal.new(),
	-- (player, categoryId, tier)
	MasteryTier = Signal.new(),
	-- (player, itemId)
	ItemGranted = Signal.new(),
	-- (player, statKey) a stat changed; achievements re-check it
	StatChanged = Signal.new(),
	-- (player, npcId)
	Talk = Signal.new(),
}

return Events

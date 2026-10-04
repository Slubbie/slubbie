-- Levels, reputation ranks and where experience comes from.

local Progression = {}

Progression.MaxLevel = 100

-- XP needed to go from `level` to `level + 1`.
function Progression.XPToNext(level: number): number
	if level >= Progression.MaxLevel then
		return math.huge
	end
	return math.floor(120 + 28 * level + 1.6 * level * level)
end

-- Skill points granted on reaching a level (more at rank milestones).
function Progression.SkillPointsFor(level: number): number
	if level <= 1 then
		return 0
	end
	if level % 10 == 0 then
		return 2
	end
	return 1
end

-- Credits granted on reaching a level.
function Progression.LevelCredits(level: number): number
	return 50 + level * 10
end

export type Rank = { Level: number, Name: string, Color: Color3, Blurb: string }

-- Reputation ranks, earned by level.
Progression.Ranks = {
	{ Level = 1, Name = "Newcomer", Color = Color3.fromRGB(200, 205, 215), Blurb = "Fresh boots, big city." },
	{
		Level = 5,
		Name = "Errand Runner",
		Color = Color3.fromRGB(150, 210, 255),
		Blurb = "The terraces know your face.",
	},
	{ Level = 10, Name = "Courier", Color = Color3.fromRGB(110, 230, 170), Blurb = "Trusted with real deliveries." },
	{
		Level = 15,
		Name = "Rooftop Regular",
		Color = Color3.fromRGB(120, 240, 120),
		Blurb = "You take the high road. Always.",
	},
	{
		Level = 20,
		Name = "Pathfinder",
		Color = Color3.fromRGB(240, 220, 90),
		Blurb = "You see lines other runners miss.",
	},
	{ Level = 30, Name = "Free Runner", Color = Color3.fromRGB(255, 180, 70), Blurb = "No route is closed to you." },
	{
		Level = 40,
		Name = "Trailblazer",
		Color = Color3.fromRGB(255, 130, 70),
		Blurb = "Other runners follow your lines.",
	},
	{
		Level = 50,
		Name = "Skyline Runner",
		Color = Color3.fromRGB(255, 100, 120),
		Blurb = "A name chalked on rooftops.",
	},
	{
		Level = 60,
		Name = "Vanguard",
		Color = Color3.fromRGB(240, 90, 200),
		Blurb = "First into every forgotten tower.",
	},
	{ Level = 70, Name = "Ace", Color = Color3.fromRGB(190, 110, 255), Blurb = "Your splits are guild legend." },
	{
		Level = 80,
		Name = "Paragon",
		Color = Color3.fromRGB(140, 130, 255),
		Blurb = "Movement as language. You're fluent.",
	},
	{
		Level = 90,
		Name = "Legend of the Guild",
		Color = Color3.fromRGB(110, 200, 255),
		Blurb = "Recruits study your ghost.",
	},
	{
		Level = 100,
		Name = "Skyline Legend",
		Color = Color3.fromRGB(255, 225, 120),
		Blurb = "The city is one again, and it runs on your lines.",
	},
} :: { Rank }

function Progression.RankFor(level: number): (Rank, number)
	local best, index = Progression.Ranks[1], 1
	for i, rank in Progression.Ranks do
		if level >= rank.Level then
			best, index = rank, i
		end
	end
	return best, index
end

-- Base XP and credit amounts. Course rewards scale with course difficulty
-- (see Logic/Rewards).
Progression.XP = {
	FirstCompletion = 160, -- × difficulty factor
	MedalUpgrade = { 60, 90, 140, 220 }, -- bronze → platinum, × difficulty factor
	Distinction = 70,
	Repeat = 24, -- × difficulty × performance
	PersonalBest = 30,
	Discovery = 60,
	Landmark = 120,
	Letter = 45,
	Lesson = 40,
	MasteryTier = 250,
	Achievement = 0, -- achievements list their own rewards
	RaceFinish = 80,
	RaceWin = 160,
	RelayFinish = 150,
	TowerFloor = 45,
	EndlessSection = 6,
}

Progression.Credits = {
	FirstCompletion = 60,
	MedalUpgrade = { 20, 35, 60, 100 },
	Repeat = 12,
	Discovery = 25,
	Cache = 120,
	RaceFinish = 40,
	RaceWin = 120,
	RelayFinish = 80,
	TowerFloor = 20,
	EndlessSection = 3,
}

-- Prestige tokens are only awarded for significant achievements.
Progression.Prestige = {
	Platinum = 1,
	ChapterComplete = 3,
	ExpertTrial = 2,
	WeeklyExpedition = 1,
	MasteryTier = 1, -- tiers 3+
	TowerMilestone = 2,
}

return Progression

--!strict
-- Quest content. Every quest is data: an objective type, a target and a
-- reward. The server's QuestService knows how each objective type counts
-- progress; nothing here needs custom code per quest.
--
-- Text placeholders: {target}, {creature} (your first creature's name) and
-- {action} (the capture input for the player's device) are filled in by the client.

export type Objective = {
	Type: string,
	Target: number,
	Rank: string?, -- CaptureRank: minimum capture rank
	Rarity: string?, -- DiscoverRarity: minimum rarity
	Track: string?, -- UpgradeLevel / PurchaseUpgrade: upgrade track
}

export type Reward = {
	Stardust: number?,
	XP: number?,
	MeteorShards: number?,
}

export type Quest = {
	Id: string,
	Title: string,
	Text: string,
	Objective: Objective,
	Reward: Reward,
	-- Where the objective marker points: "TutorialComet", "Sanctuary",
	-- "HabitatSlot1", "Workshop", "DawnCommons" or nil for no marker.
	Waypoint: string?,
}

export type ObjectiveType = {
	-- "Event" objectives count matching events; "State" objectives read the profile.
	Kind: "Event" | "State",
	Event: string?,
	Unit: string?,
}

local QuestDefinitions = {}

QuestDefinitions.ObjectiveTypes = {
	CaptureComets = { Kind = "Event", Event = "CaptureSucceeded" },
	CaptureRank = { Kind = "Event", Event = "CaptureSucceeded" },
	CollectWisps = { Kind = "Event", Event = "WispCollected" },
	OpenCores = { Kind = "Event", Event = "CoreOpened" },
	EarnPassive = { Kind = "Event", Event = "PassiveIncome", Unit = "Stardust" },
	ReachTutorialComet = { Kind = "Event", Event = "NearTutorialComet" },
	EnterSanctuary = { Kind = "Event", Event = "EnteredOwnSanctuary" },
	PurchaseUpgrade = { Kind = "Event", Event = "UpgradePurchased" },
	DeployedCount = { Kind = "State" },
	UpgradeLevel = { Kind = "State" },
	SpeciesDiscovered = { Kind = "State" },
	DiscoverRarity = { Kind = "State" },
	ReachLevel = { Kind = "State" },
} :: { [string]: ObjectiveType }

-- The first-five-minutes guide. TutorialStage in the profile = number of
-- steps completed. Rewards are granted automatically.
QuestDefinitions.Onboarding = {
	{
		Id = "FollowComet",
		Title = "A comet just landed!",
		Text = "Follow its trail to the crash site.",
		Objective = { Type = "ReachTutorialComet", Target = 1 },
		Reward = {},
		Waypoint = "TutorialComet",
	},
	{
		Id = "CaptureComet",
		Title = "Stabilize the comet",
		Text = "{action} at the comet, then match the timing.",
		Objective = { Type = "CaptureComets", Target = 1 },
		Reward = {},
		Waypoint = "TutorialComet",
	},
	{
		Id = "OpenCore",
		Title = "Open your comet core",
		Text = "Something is sealed inside. Let's see!",
		Objective = { Type = "OpenCores", Target = 1 },
		Reward = {},
	},
	{
		Id = "GoHome",
		Title = "Bring {creature} home",
		Text = "Follow the marker to your sanctuary, or use 🏠 Home.",
		Objective = { Type = "EnterSanctuary", Target = 1 },
		Reward = {},
		Waypoint = "Sanctuary",
	},
	{
		Id = "Deploy",
		Title = "Give {creature} a habitat",
		Text = "Use a glowing habitat pad to place your creature.",
		Objective = { Type = "DeployedCount", Target = 1 },
		Reward = { Stardust = 250 },
		Waypoint = "HabitatSlot1",
	},
	{
		Id = "Earn",
		Title = "Watch your sanctuary work",
		Text = "Deployed creatures gather Stardust every second, even while you explore.",
		Objective = { Type = "EarnPassive", Target = 5 },
		Reward = {},
	},
	{
		Id = "UpgradeScanner",
		Title = "Upgrade your Scanner",
		Text = "Visit the Workshop in the hub and buy Scanner Lv 2.",
		Objective = { Type = "UpgradeLevel", Target = 2, Track = "Scanner" },
		Reward = { XP = 60 },
		Waypoint = "Workshop",
	},
} :: { Quest }

-- Explorer missions follow the tutorial, one at a time, and are claimed by hand.
QuestDefinitions.Missions = {
	{
		Id = "CometChaser",
		Title = "Comet Chaser",
		Text = "Capture {target} comets in Dawn Commons.",
		Objective = { Type = "CaptureComets", Target = 5 },
		Reward = { Stardust = 150, XP = 60 },
		Waypoint = "DawnCommons",
	},
	{
		Id = "FullHouse",
		Title = "Full House",
		Text = "Fill {target} habitats in your sanctuary.",
		Objective = { Type = "DeployedCount", Target = 4 },
		Reward = { Stardust = 200, XP = 40 },
		Waypoint = "Sanctuary",
	},
	{
		Id = "SteadyHands",
		Title = "Steady Hands",
		Text = "Make a Gold or Perfect capture.",
		Objective = { Type = "CaptureRank", Target = 1, Rank = "Gold" },
		Reward = { Stardust = 250, XP = 80 },
	},
	{
		Id = "WispWatcher",
		Title = "Wisp Watcher",
		Text = "Collect {target} Stardust Wisps. Your scanner reveals them.",
		Objective = { Type = "CollectWisps", Target = 15 },
		Reward = { Stardust = 300, XP = 60 },
		Waypoint = "DawnCommons",
	},
	{
		Id = "GrowingSanctuary",
		Title = "Growing Sanctuary",
		Text = "Upgrade your Habitats to Lv 2.",
		Objective = { Type = "UpgradeLevel", Target = 2, Track = "Habitat" },
		Reward = { Stardust = 500, XP = 100 },
		Waypoint = "Workshop",
	},
	{
		Id = "FieldResearcher",
		Title = "Field Researcher",
		Text = "Discover {target} different species.",
		Objective = { Type = "SpeciesDiscovered", Target = 6 },
		Reward = { Stardust = 800, XP = 120 },
	},
	{
		Id = "RareFind",
		Title = "Rare Find",
		Text = "Discover a Rare (or rarer) creature.",
		Objective = { Type = "DiscoverRarity", Target = 1, Rarity = "Rare" },
		Reward = { Stardust = 1000, XP = 150 },
	},
	{
		Id = "SharperTether",
		Title = "Sharper Tether",
		Text = "Upgrade your Tether to Lv 2.",
		Objective = { Type = "UpgradeLevel", Target = 2, Track = "Tether" },
		Reward = { Stardust = 600, XP = 100 },
		Waypoint = "Workshop",
	},
	{
		Id = "SeasonedExplorer",
		Title = "Seasoned Explorer",
		Text = "Reach Level {target}.",
		Objective = { Type = "ReachLevel", Target = 5 },
		Reward = { Stardust = 1500, XP = 0 },
	},
	{
		Id = "Perfectionist",
		Title = "Perfectionist",
		Text = "Make a Perfect capture.",
		Objective = { Type = "CaptureRank", Target = 1, Rank = "Perfect" },
		Reward = { Stardust = 1200, XP = 200 },
	},
	{
		Id = "CometVeteran",
		Title = "Comet Veteran",
		Text = "Capture {target} comets.",
		Objective = { Type = "CaptureComets", Target = 50 },
		Reward = { Stardust = 4000, XP = 300 },
	},
} :: { Quest }

function QuestDefinitions.FindMission(id: string): (Quest?, number?)
	for index, quest in QuestDefinitions.Missions do
		if quest.Id == id then
			return quest, index
		end
	end
	return nil, nil
end

function QuestDefinitions.Validate(): { string }
	local problems = {}
	local ids = {}
	local function check(chain: string, list: { Quest })
		for _, quest in list do
			if ids[quest.Id] then
				table.insert(problems, `Quest id '{quest.Id}' is used twice`)
			end
			ids[quest.Id] = true
			local objectiveType = QuestDefinitions.ObjectiveTypes[quest.Objective.Type]
			if not objectiveType then
				table.insert(problems, `{chain} quest '{quest.Id}' has unknown objective '{quest.Objective.Type}'`)
			end
			if quest.Objective.Target < 1 then
				table.insert(problems, `{chain} quest '{quest.Id}' needs a positive target`)
			end
		end
	end
	check("Onboarding", QuestDefinitions.Onboarding)
	check("Missions", QuestDefinitions.Missions)
	return problems
end

return QuestDefinitions

-- Movement mastery: eight technique categories, each with five tiers.
--
-- A tier needs BOTH enough mastery points (earned by using the techniques in
-- validated play) AND its proficiency challenge, which proves real control
-- rather than repetition. Points per action are capped per minute so they
-- can't be farmed by spamming one move.
--
-- Challenge kinds (checked by MasteryService on the server):
--   Count         perform Action N times (lifetime)
--   Chain         perform Actions in order inside one unbroken movement chain
--   ChainLength   a chain of at least Count moves
--   ChainVariety  a chain with at least Count different techniques
--   Feat          one action whose reported Value reaches Value (e.g. wall-run seconds)
--   Streak        Count of Action in a row without any Breaks action in between
--   Medal         Medal (1-4) or better on Count courses whose Focus includes Focus

export type Challenge = {
	Id: string,
	Category: string,
	Tier: number,
	Name: string,
	Text: string,
	Kind: string,
	Action: string?,
	Actions: { string }?,
	Breaks: { string }?,
	Count: number?,
	Value: number?,
	Focus: string?,
	Medal: number?,
}

local Mastery = {}

Mastery.TierNames = { "Novice", "Adept", "Expert", "Master", "Grandmaster" }
Mastery.TierPoints = { 150, 600, 1500, 3200, 6000 }

Mastery.Categories = {
	{
		Id = "WallRunning",
		Name = "Wall Running",
		Icon = "//",
		Color = Color3.fromRGB(110, 190, 255),
		Blurb = "Runs, kicks and climbs along vertical surfaces.",
		Actions = { WallRun = 6, WallJump = 5, WallKick = 4, WallClimb = 4 },
	},
	{
		Id = "PrecisionLanding",
		Name = "Precision Landing",
		Icon = "+",
		Color = Color3.fromRGB(255, 210, 100),
		Blurb = "Sticking narrow landings and rolling out of big drops.",
		Actions = { PrecisionLand = 8, Roll = 6 },
	},
	{
		Id = "Grappling",
		Name = "Grappling",
		Icon = "(o)",
		Color = Color3.fromRGB(80, 230, 220),
		Blurb = "Swings, pulls and well-timed releases.",
		Actions = { Grapple = 6, GrappleRelease = 3, Pull = 6 },
	},
	{
		Id = "FlowChains",
		Name = "Movement Chains",
		Icon = "~>",
		Color = Color3.fromRGB(240, 120, 220),
		Blurb = "Long, varied chains of techniques without stopping.",
		Actions = { ChainBonus = 1 },
	},
	{
		Id = "Groundwork",
		Name = "Groundwork",
		Icon = "^_",
		Color = Color3.fromRGB(140, 230, 120),
		Blurb = "Vaults, slides and keeping speed through clutter.",
		Actions = { Vault = 5, Slide = 3, SlideJump = 4 },
	},
	{
		Id = "Climbing",
		Name = "Climbing",
		Icon = "#",
		Color = Color3.fromRGB(230, 160, 100),
		Blurb = "Ledges, mantles, climbs and leaps.",
		Actions = { LedgeGrab = 4, Mantle = 3, Climb = 3, LedgeLeap = 6, ClimbHop = 3 },
	},
	{
		Id = "Aerial",
		Name = "Aerial",
		Icon = "^^",
		Color = Color3.fromRGB(170, 150, 255),
		Blurb = "Double jumps and dashes that land where you meant.",
		Actions = { DoubleJump = 4, Dash = 5 },
	},
	{
		Id = "Traverse",
		Name = "Traverse",
		Icon = "=~",
		Color = Color3.fromRGB(200, 220, 230),
		Blurb = "Beams, ziplines and rope swings.",
		Actions = { Balance = 4, BalanceCatch = 5, Zipline = 4, RopeSwing = 5 },
	},
}

Mastery.ById = {}
for _, category in Mastery.Categories do
	Mastery.ById[category.Id] = category
end

-- Most points a single action type can award per minute.
Mastery.PointsPerMinuteCap = 120

local challenges: { Challenge } = {
	-- Wall running
	{
		Id = "wr1",
		Category = "WallRunning",
		Tier = 1,
		Name = "Wall Walker",
		Text = "Wall run 10 times.",
		Kind = "Count",
		Action = "WallRun",
		Count = 10,
	},
	{
		Id = "wr2",
		Category = "WallRunning",
		Tier = 2,
		Name = "Tic-Tac",
		Text = "Wall run, wall jump, then wall run again in one chain.",
		Kind = "Chain",
		Actions = { "WallRun", "WallJump", "WallRun" },
	},
	{
		Id = "wr3",
		Category = "WallRunning",
		Tier = 3,
		Name = "Long Stride",
		Text = "Hold a single wall run for 1.3 seconds.",
		Kind = "Feat",
		Action = "WallRun",
		Value = 1.3,
	},
	{
		Id = "wr4",
		Category = "WallRunning",
		Tier = 4,
		Name = "Corridor King",
		Text = "Four wall runs in one chain.",
		Kind = "Chain",
		Actions = { "WallRun", "WallRun", "WallRun", "WallRun" },
	},
	{
		Id = "wr5",
		Category = "WallRunning",
		Tier = 5,
		Name = "Vertical Virtuoso",
		Text = "Earn gold or better on 4 courses that focus on wall running.",
		Kind = "Medal",
		Focus = "WallRun",
		Medal = 3,
		Count = 4,
	},
	-- Precision landing
	{
		Id = "pl1",
		Category = "PrecisionLanding",
		Tier = 1,
		Name = "Soft Feet",
		Text = "Perform 5 landing rolls.",
		Kind = "Count",
		Action = "Roll",
		Count = 5,
	},
	{
		Id = "pl2",
		Category = "PrecisionLanding",
		Tier = 2,
		Name = "Pinpoint",
		Text = "Stick 3 precision landings in a row without stumbling.",
		Kind = "Streak",
		Action = "PrecisionLand",
		Count = 3,
		Breaks = { "Stumble", "Fall" },
	},
	{
		Id = "pl3",
		Category = "PrecisionLanding",
		Tier = 3,
		Name = "Cat Landing",
		Text = "Roll out of 8 big drops in a row without a single stumble.",
		Kind = "Streak",
		Action = "Roll",
		Count = 8,
		Breaks = { "Stumble", "Fall" },
	},
	{
		Id = "pl4",
		Category = "PrecisionLanding",
		Tier = 4,
		Name = "Needle Point",
		Text = "Stick 8 precision landings in a row.",
		Kind = "Streak",
		Action = "PrecisionLand",
		Count = 8,
		Breaks = { "Stumble", "Fall" },
	},
	{
		Id = "pl5",
		Category = "PrecisionLanding",
		Tier = 5,
		Name = "Surgeon",
		Text = "Earn gold or better on 4 courses that focus on precision.",
		Kind = "Medal",
		Focus = "Precision",
		Medal = 3,
		Count = 4,
	},
	-- Grappling
	{
		Id = "gr1",
		Category = "Grappling",
		Tier = 1,
		Name = "Hooked",
		Text = "Grapple 15 times.",
		Kind = "Count",
		Action = "Grapple",
		Count = 15,
	},
	{
		Id = "gr2",
		Category = "Grappling",
		Tier = 2,
		Name = "Swing Set",
		Text = "Chain three grapples without landing.",
		Kind = "Chain",
		Actions = { "Grapple", "Grapple", "Grapple" },
	},
	{
		Id = "gr3",
		Category = "Grappling",
		Tier = 3,
		Name = "Slingshot",
		Text = "Release a grapple at 70 speed or more.",
		Kind = "Feat",
		Action = "GrappleRelease",
		Value = 70,
	},
	{
		Id = "gr4",
		Category = "Grappling",
		Tier = 4,
		Name = "Push and Pull",
		Text = "Grapple swing, pull anchor, then grapple swing in one chain.",
		Kind = "Chain",
		Actions = { "Grapple", "Pull", "Grapple" },
	},
	{
		Id = "gr5",
		Category = "Grappling",
		Tier = 5,
		Name = "Spider",
		Text = "Earn gold or better on 4 courses that focus on grappling.",
		Kind = "Medal",
		Focus = "Grapple",
		Medal = 3,
		Count = 4,
	},
	-- Chains
	{
		Id = "fc1",
		Category = "FlowChains",
		Tier = 1,
		Name = "Linked Up",
		Text = "Perform a chain of 6 moves.",
		Kind = "ChainLength",
		Count = 6,
	},
	{
		Id = "fc2",
		Category = "FlowChains",
		Tier = 2,
		Name = "Mixed Bag",
		Text = "Use 5 different techniques in one chain.",
		Kind = "ChainVariety",
		Count = 5,
	},
	{
		Id = "fc3",
		Category = "FlowChains",
		Tier = 3,
		Name = "Momentum",
		Text = "Perform a chain of 18 moves.",
		Kind = "ChainLength",
		Count = 18,
	},
	{
		Id = "fc4",
		Category = "FlowChains",
		Tier = 4,
		Name = "Repertoire",
		Text = "Use 8 different techniques in one chain.",
		Kind = "ChainVariety",
		Count = 8,
	},
	{
		Id = "fc5",
		Category = "FlowChains",
		Tier = 5,
		Name = "Seamless",
		Text = "Perform a chain of 40 moves.",
		Kind = "ChainLength",
		Count = 40,
	},
	-- Groundwork
	{
		Id = "gw1",
		Category = "Groundwork",
		Tier = 1,
		Name = "Hurdler",
		Text = "Vault 10 obstacles.",
		Kind = "Count",
		Action = "Vault",
		Count = 10,
	},
	{
		Id = "gw2",
		Category = "Groundwork",
		Tier = 2,
		Name = "Under and Over",
		Text = "Slide, then vault, in one chain.",
		Kind = "Chain",
		Actions = { "Slide", "Vault" },
	},
	{
		Id = "gw3",
		Category = "Groundwork",
		Tier = 3,
		Name = "Slide Jumper",
		Text = "Slide jump 25 times.",
		Kind = "Count",
		Action = "SlideJump",
		Count = 25,
	},
	{
		Id = "gw4",
		Category = "Groundwork",
		Tier = 4,
		Name = "Parkour Line",
		Text = "Slide, vault, then wall run in one chain.",
		Kind = "Chain",
		Actions = { "Slide", "Vault", "WallRun" },
	},
	{
		Id = "gw5",
		Category = "Groundwork",
		Tier = 5,
		Name = "Street Legend",
		Text = "Earn gold or better on 4 courses that focus on groundwork.",
		Kind = "Medal",
		Focus = "Vault",
		Medal = 3,
		Count = 4,
	},
	-- Climbing
	{
		Id = "cl1",
		Category = "Climbing",
		Tier = 1,
		Name = "Handholds",
		Text = "Grab 10 ledges.",
		Kind = "Count",
		Action = "LedgeGrab",
		Count = 10,
	},
	{
		Id = "cl2",
		Category = "Climbing",
		Tier = 2,
		Name = "Up and Over",
		Text = "Wall climb, catch the ledge, then mantle in one chain.",
		Kind = "Chain",
		Actions = { "WallClimb", "LedgeGrab", "Mantle" },
	},
	{
		Id = "cl3",
		Category = "Climbing",
		Tier = 3,
		Name = "Rope Burns",
		Text = "Climb hop 20 times.",
		Kind = "Count",
		Action = "ClimbHop",
		Count = 20,
	},
	{
		Id = "cl4",
		Category = "Climbing",
		Tier = 4,
		Name = "Stacked",
		Text = "Ledge leap twice in one chain.",
		Kind = "Chain",
		Actions = { "LedgeLeap", "LedgeLeap" },
	},
	{
		Id = "cl5",
		Category = "Climbing",
		Tier = 5,
		Name = "Summit",
		Text = "Earn gold or better on 4 courses that focus on climbing.",
		Kind = "Medal",
		Focus = "Climb",
		Medal = 3,
		Count = 4,
	},
	-- Aerial
	{
		Id = "ae1",
		Category = "Aerial",
		Tier = 1,
		Name = "Liftoff",
		Text = "Double jump 15 times.",
		Kind = "Count",
		Action = "DoubleJump",
		Count = 15,
	},
	{
		Id = "ae2",
		Category = "Aerial",
		Tier = 2,
		Name = "Air Step",
		Text = "Double jump then dash in one chain.",
		Kind = "Chain",
		Actions = { "DoubleJump", "Dash" },
	},
	{
		Id = "ae3",
		Category = "Aerial",
		Tier = 3,
		Name = "Kick Dash",
		Text = "Wall jump, dash, then wall run in one chain.",
		Kind = "Chain",
		Actions = { "WallJump", "Dash", "WallRun" },
	},
	{
		Id = "ae4",
		Category = "Aerial",
		Tier = 4,
		Name = "No Ground Needed",
		Text = "Double jump, dash and grapple in one chain.",
		Kind = "Chain",
		Actions = { "DoubleJump", "Dash", "Grapple" },
	},
	{
		Id = "ae5",
		Category = "Aerial",
		Tier = 5,
		Name = "Aviator",
		Text = "Earn gold or better on 4 courses that focus on aerial moves.",
		Kind = "Medal",
		Focus = "Aerial",
		Medal = 3,
		Count = 4,
	},
	-- Traverse
	{
		Id = "tv1",
		Category = "Traverse",
		Tier = 1,
		Name = "Tightrope",
		Text = "Cross 8 balance beams.",
		Kind = "Count",
		Action = "Balance",
		Count = 8,
	},
	{
		Id = "tv2",
		Category = "Traverse",
		Tier = 2,
		Name = "Line Rider",
		Text = "Zipline straight into a rope swing in one chain.",
		Kind = "Chain",
		Actions = { "Zipline", "RopeSwing" },
	},
	{
		Id = "tv3",
		Category = "Traverse",
		Tier = 3,
		Name = "Steady Hands",
		Text = "Catch a beam after slipping 3 times.",
		Kind = "Count",
		Action = "BalanceCatch",
		Count = 3,
	},
	{
		Id = "tv4",
		Category = "Traverse",
		Tier = 4,
		Name = "Vine Line",
		Text = "Three rope swings in one chain.",
		Kind = "Chain",
		Actions = { "RopeSwing", "RopeSwing", "RopeSwing" },
	},
	{
		Id = "tv5",
		Category = "Traverse",
		Tier = 5,
		Name = "High Wire",
		Text = "Earn gold or better on 4 courses that focus on balance or lines.",
		Kind = "Medal",
		Focus = "Balance",
		Medal = 3,
		Count = 4,
	},
}

Mastery.Challenges = challenges
Mastery.ChallengeById = {} :: { [string]: Challenge }
Mastery.ChallengeFor = {} :: { [string]: { [number]: Challenge } }
for _, challenge in challenges do
	Mastery.ChallengeById[challenge.Id] = challenge
	local byTier = Mastery.ChallengeFor[challenge.Category]
	if not byTier then
		byTier = {}
		Mastery.ChallengeFor[challenge.Category] = byTier
	end
	byTier[challenge.Tier] = challenge
end

-- Current tier (0..5) given points and completed challenges.
function Mastery.TierOf(categoryId: string, points: number, completed: { [string]: boolean }): number
	local tier = 0
	for index, needed in Mastery.TierPoints do
		local challenge = Mastery.ChallengeFor[categoryId] and Mastery.ChallengeFor[categoryId][index]
		if points >= needed and (not challenge or completed[challenge.Id]) then
			tier = index
		else
			break
		end
	end
	return tier
end

-- Rewards for reaching each tier (cosmetics are granted by id).
Mastery.TierRewards = {
	[1] = { Credits = 150, XP = 250 },
	[2] = { Credits = 300, XP = 400 },
	[3] = { Credits = 500, XP = 600, Prestige = 1 },
	[4] = { Credits = 800, XP = 900, Prestige = 2 },
	[5] = { Credits = 1500, XP = 1500, Prestige = 3, Title = true },
}

return Mastery

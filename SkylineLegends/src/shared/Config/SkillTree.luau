-- The branching skill tree: Endurance, Agility, Aerial Control and Exploration.
--
-- Effects are applied by Logic/MoveStats:
--   { Stat, "Add", amountPerRank }      e.g. { "StaminaMax", "Add", 8 }
--   { Stat, "Mul", fractionPerRank }    e.g. { "Costs.Hang", "Mul", -0.12 } (12% cheaper per rank)
--   { "Perk", name, valuePerRank }      non-movement perks (exploration helpers)
--
-- Movement effects are switched off in ranked runs and races, so leaderboards
-- compare execution on standard attributes. Exploration perks always apply.

export type Node = {
	Id: string,
	Branch: string,
	Name: string,
	Description: string,
	MaxRank: number,
	Cost: number,
	Requires: { string },
	Tier: number,
	Column: number,
	Effects: { { any } },
	Capstone: boolean?,
}

local Branches = {
	{
		Id = "Endurance",
		Name = "Endurance",
		Color = Color3.fromRGB(255, 140, 90),
		Blurb = "Bigger lungs, steadier grip, longer sprints.",
	},
	{
		Id = "Agility",
		Name = "Agility",
		Color = Color3.fromRGB(110, 220, 140),
		Blurb = "Cleaner footwork and momentum that sticks.",
	},
	{
		Id = "Aerial",
		Name = "Aerial Control",
		Color = Color3.fromRGB(110, 180, 255),
		Blurb = "Own the space between rooftops.",
	},
	{
		Id = "Exploration",
		Name = "Exploration",
		Color = Color3.fromRGB(230, 200, 90),
		Blurb = "Find what the city hides.",
	},
}

local nodes: { Node } = {
	-- Endurance ----------------------------------------------------------------
	{
		Id = "DeepLungs",
		Branch = "Endurance",
		Name = "Deep Lungs",
		Description = "+8 maximum stamina per rank.",
		MaxRank = 3,
		Cost = 1,
		Requires = {},
		Tier = 1,
		Column = 1,
		Effects = { { "StaminaMax", "Add", 8 } },
	},
	{
		Id = "SecondWind",
		Branch = "Endurance",
		Name = "Second Wind",
		Description = "Stamina starts refilling 0.12s sooner per rank.",
		MaxRank = 2,
		Cost = 1,
		Requires = {},
		Tier = 1,
		Column = 2,
		Effects = { { "StaminaRegenDelay", "Add", -0.12 } },
	},
	{
		Id = "Marathon",
		Branch = "Endurance",
		Name = "Marathon",
		Description = "Sprinting costs 15% less stamina per rank.",
		MaxRank = 2,
		Cost = 1,
		Requires = { "DeepLungs" },
		Tier = 2,
		Column = 1,
		Effects = { { "Costs.Sprint", "Mul", -0.15 } },
	},
	{
		Id = "IronGrip",
		Branch = "Endurance",
		Name = "Iron Grip",
		Description = "Hanging and climbing drain 12% less stamina per rank.",
		MaxRank = 3,
		Cost = 1,
		Requires = { "SecondWind" },
		Tier = 2,
		Column = 2,
		Effects = {
			{ "Costs.Hang", "Mul", -0.12 },
			{ "Costs.Climb", "Mul", -0.12 },
			{ "Costs.ClimbIdle", "Mul", -0.12 },
		},
	},
	{
		Id = "SteadyAnkles",
		Branch = "Endurance",
		Name = "Steady Ankles",
		Description = "Stumbles from hard landings are 20% shorter per rank.",
		MaxRank = 2,
		Cost = 1,
		Requires = { "Marathon" },
		Tier = 3,
		Column = 1,
		Effects = { { "StumbleTime", "Mul", -0.2 }, { "HeavyStumbleTime", "Mul", -0.2 } },
	},
	{
		Id = "QuickRecovery",
		Branch = "Endurance",
		Name = "Quick Recovery",
		Description = "+12% stamina regeneration per rank.",
		MaxRank = 3,
		Cost = 1,
		Requires = { "IronGrip" },
		Tier = 3,
		Column = 2,
		Effects = { { "StaminaRegenGround", "Mul", 0.12 }, { "StaminaRegenAir", "Mul", 0.12 } },
	},
	{
		Id = "Unbreakable",
		Branch = "Endurance",
		Name = "Unbreakable",
		Description = "Capstone: +20 stamina and every powerful move costs 10% less.",
		MaxRank = 1,
		Cost = 3,
		Requires = { "SteadyAnkles", "QuickRecovery" },
		Tier = 4,
		Column = 1.5,
		Capstone = true,
		Effects = {
			{ "StaminaMax", "Add", 20 },
			{ "Costs.DoubleJump", "Mul", -0.1 },
			{ "Costs.Dash", "Mul", -0.1 },
			{ "Costs.WallKick", "Mul", -0.1 },
			{ "Costs.WallClimb", "Mul", -0.1 },
		},
	},

	-- Agility ------------------------------------------------------------------
	{
		Id = "QuickFeet",
		Branch = "Agility",
		Name = "Quick Feet",
		Description = "Reach full running speed 12% faster per rank.",
		MaxRank = 3,
		Cost = 1,
		Requires = {},
		Tier = 1,
		Column = 1,
		Effects = { { "GroundAccel", "Mul", 0.12 } },
	},
	{
		Id = "SlickSlide",
		Branch = "Agility",
		Name = "Slick Slide",
		Description = "Slides lose 10% less speed per rank.",
		MaxRank = 2,
		Cost = 1,
		Requires = {},
		Tier = 1,
		Column = 2,
		Effects = { { "SlideFriction", "Mul", -0.1 } },
	},
	{
		Id = "SpringVault",
		Branch = "Agility",
		Name = "Spring Vault",
		Description = "Vaults launch you out 3% faster per rank.",
		MaxRank = 2,
		Cost = 1,
		Requires = { "QuickFeet" },
		Tier = 2,
		Column = 1,
		Effects = { { "VaultExitBoost", "Add", 0.03 } },
	},
	{
		Id = "SoftTouch",
		Branch = "Agility",
		Name = "Soft Touch",
		Description = "Landing roll timing window +0.06s per rank.",
		MaxRank = 2,
		Cost = 1,
		Requires = { "SlickSlide" },
		Tier = 2,
		Column = 2,
		Effects = { { "RollWindow", "Add", 0.06 } },
	},
	{
		Id = "WallStrider",
		Branch = "Agility",
		Name = "Wall Strider",
		Description = "Wall runs last 0.12s longer per rank.",
		MaxRank = 3,
		Cost = 1,
		Requires = { "SpringVault" },
		Tier = 3,
		Column = 1,
		Effects = { { "WallRunMaxTime", "Add", 0.12 } },
	},
	{
		Id = "SureFooted",
		Branch = "Agility",
		Name = "Sure-Footed",
		Description = "Balance beams sway 15% less per rank.",
		MaxRank = 2,
		Cost = 1,
		Requires = { "SoftTouch" },
		Tier = 3,
		Column = 2,
		Effects = { { "BalanceSway", "Mul", -0.15 } },
	},
	{
		Id = "MomentumKeeper",
		Branch = "Agility",
		Name = "Momentum Keeper",
		Description = "Capstone: extra speed from landings and slides bleeds away 25% slower.",
		MaxRank = 1,
		Cost = 3,
		Requires = { "WallStrider", "SureFooted" },
		Tier = 4,
		Column = 1.5,
		Capstone = true,
		Effects = { { "GroundDecel", "Mul", -0.25 } },
	},

	-- Aerial -------------------------------------------------------------------
	{
		Id = "AirSense",
		Branch = "Aerial",
		Name = "Air Sense",
		Description = "+10% air steering per rank.",
		MaxRank = 3,
		Cost = 1,
		Requires = {},
		Tier = 1,
		Column = 1,
		Effects = { { "AirAccel", "Mul", 0.1 }, { "AirTurnRate", "Mul", 0.1 } },
	},
	{
		Id = "LongReach",
		Branch = "Aerial",
		Name = "Long Reach",
		Description = "Grapple range +8 studs per rank.",
		MaxRank = 2,
		Cost = 1,
		Requires = {},
		Tier = 1,
		Column = 2,
		Effects = { { "GrappleRange", "Add", 8 } },
	},
	{
		Id = "FeatherLanding",
		Branch = "Aerial",
		Name = "Feather Landing",
		Description = "Hard landings need 8% more impact per rank.",
		MaxRank = 2,
		Cost = 1,
		Requires = { "AirSense" },
		Tier = 2,
		Column = 1,
		Effects = { { "HardLandImpact", "Mul", 0.08 }, { "HeavyLandImpact", "Mul", 0.08 } },
	},
	{
		Id = "QuickReel",
		Branch = "Aerial",
		Name = "Quick Reel",
		Description = "Reel in 15% faster and swing 8% harder per rank.",
		MaxRank = 2,
		Cost = 1,
		Requires = { "LongReach" },
		Tier = 2,
		Column = 2,
		Effects = { { "GrappleFastReel", "Mul", 0.15 }, { "GrappleSwingAccel", "Mul", 0.08 } },
	},
	{
		Id = "DashRecovery",
		Branch = "Aerial",
		Name = "Dash Recovery",
		Description = "Dash cooldown 15% shorter per rank.",
		MaxRank = 2,
		Cost = 1,
		Requires = { "FeatherLanding" },
		Tier = 3,
		Column = 1,
		Effects = { { "DashCooldown", "Mul", -0.15 } },
	},
	{
		Id = "Updraft",
		Branch = "Aerial",
		Name = "Updraft",
		Description = "Double jumps are 4% higher per rank.",
		MaxRank = 2,
		Cost = 1,
		Requires = { "QuickReel" },
		Tier = 3,
		Column = 2,
		Effects = { { "DoubleJumpVelocity", "Mul", 0.04 } },
	},
	{
		Id = "SkyDancer",
		Branch = "Aerial",
		Name = "Sky Dancer",
		Description = "Capstone: a second dash charge.",
		MaxRank = 1,
		Cost = 3,
		Requires = { "DashRecovery", "Updraft" },
		Tier = 4,
		Column = 1.5,
		Capstone = true,
		Effects = { { "DashCharges", "Add", 1 } },
	},

	-- Exploration --------------------------------------------------------------
	{
		Id = "KeenEye",
		Branch = "Exploration",
		Name = "Keen Eye",
		Description = "Hidden caches and letters shimmer when you're within 30 studs per rank.",
		MaxRank = 2,
		Cost = 1,
		Requires = {},
		Tier = 1,
		Column = 1,
		Effects = { { "Perk", "SecretSense", 30 } },
	},
	{
		Id = "Scavenger",
		Branch = "Exploration",
		Name = "Scavenger",
		Description = "Caches and contracts pay 10% more credits per rank.",
		MaxRank = 3,
		Cost = 1,
		Requires = {},
		Tier = 1,
		Column = 2,
		Effects = { { "Perk", "CreditBonus", 0.1 } },
	},
	{
		Id = "Cartographer",
		Branch = "Exploration",
		Name = "Cartographer",
		Description = "The map shows how many secrets remain in each district.",
		MaxRank = 1,
		Cost = 1,
		Requires = { "KeenEye" },
		Tier = 2,
		Column = 1,
		Effects = { { "Perk", "MapSecrets", 1 } },
	},
	{
		Id = "TokenCompass",
		Branch = "Exploration",
		Name = "Token Compass",
		Description = "Uncollected course tokens glow brighter and show through walls nearby.",
		MaxRank = 1,
		Cost = 1,
		Requires = { "Scavenger" },
		Tier = 2,
		Column = 2,
		Effects = { { "Perk", "TokenCompass", 1 } },
	},
	{
		Id = "Pathfinder",
		Branch = "Exploration",
		Name = "Pathfinder",
		Description = "After your first clear, course previews show where each route splits.",
		MaxRank = 1,
		Cost = 2,
		Requires = { "Cartographer" },
		Tier = 3,
		Column = 1,
		Effects = { { "Perk", "RouteHints", 1 } },
	},
	{
		Id = "StudyHall",
		Branch = "Exploration",
		Name = "Study Hall",
		Description = "+5% experience from every source per rank.",
		MaxRank = 3,
		Cost = 1,
		Requires = { "TokenCompass" },
		Tier = 3,
		Column = 2,
		Effects = { { "Perk", "XPBonus", 0.05 } },
	},
	{
		Id = "LegendsInstinct",
		Branch = "Exploration",
		Name = "Legend's Instinct",
		Description = "Capstone: expert shortcuts glow faintly once you've cleared their course.",
		MaxRank = 1,
		Cost = 3,
		Requires = { "Pathfinder", "StudyHall" },
		Tier = 4,
		Column = 1.5,
		Capstone = true,
		Effects = { { "Perk", "ShortcutSense", 1 } },
	},
}

local SkillTree = {}
SkillTree.Branches = Branches
SkillTree.Nodes = nodes
SkillTree.ById = {} :: { [string]: Node }
for _, node in nodes do
	SkillTree.ById[node.Id] = node
end

SkillTree.RespecCost = 500 -- credits

-- Whether `node` can take another rank given current ranks and free points.
function SkillTree.CanUnlock(ranks: { [string]: number }, freePoints: number, nodeId: string): (boolean, string?)
	local node = SkillTree.ById[nodeId]
	if not node then
		return false, "Unknown skill"
	end
	local current = ranks[nodeId] or 0
	if current >= node.MaxRank then
		return false, "Already maxed"
	end
	if freePoints < node.Cost then
		return false, ("Needs %d skill point%s"):format(node.Cost, if node.Cost == 1 then "" else "s")
	end
	for _, requirement in node.Requires do
		if (ranks[requirement] or 0) < 1 then
			local required = SkillTree.ById[requirement]
			return false, "Requires " .. (if required then required.Name else requirement)
		end
	end
	return true, nil
end

function SkillTree.SpentPoints(ranks: { [string]: number }): number
	local total = 0
	for id, rank in ranks do
		local node = SkillTree.ById[id]
		if node then
			total += node.Cost * rank
		end
	end
	return total
end

return SkillTree

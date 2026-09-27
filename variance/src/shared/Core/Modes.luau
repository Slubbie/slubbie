-- Game modes. A mode is metadata (who can play it, how it is queued, how it
-- rewards progression) plus a base rule set that Core/Rules.luau expands.
--
-- Adding a mode: add an entry here. Queued modes also need an entry in
-- Config.Matchmaking.Queues; solo modes are started through MatchService.startSolo.

local Modes = {}

-- Escalation profiles. Index = Trial number; Trials beyond the list reuse the last.
--   MaxIntegrity  starting and maximum Integrity for the Trial
--   Cells         {min, max} cells per Load
--   Charged       {min, max} fraction of cells that are CHARGED (always at least 1 of each)
--   Draws         instruments dealt to each subject at the start of every Load
--   Rare          whether Rare instruments can be drawn
--   Surge         the last cell of each Load deals +1 damage
local STANDARD_PROFILES = {
	{ MaxIntegrity = 2, Cells = { 2, 4 }, Charged = { 0.34, 0.67 }, Draws = 0, Rare = false, Surge = false },
	{ MaxIntegrity = 4, Cells = { 3, 6 }, Charged = { 0.3, 0.65 }, Draws = 2, Rare = false, Surge = false },
	{ MaxIntegrity = 5, Cells = { 4, 8 }, Charged = { 0.3, 0.65 }, Draws = 3, Rare = true, Surge = true },
}

local RAPID_PROFILES = {
	{ MaxIntegrity = 2, Cells = { 2, 3 }, Charged = { 0.34, 0.67 }, Draws = 0, Rare = false, Surge = false },
	{ MaxIntegrity = 3, Cells = { 3, 5 }, Charged = { 0.3, 0.65 }, Draws = 1, Rare = false, Surge = false },
	{ MaxIntegrity = 4, Cells = { 4, 6 }, Charged = { 0.3, 0.65 }, Draws = 2, Rare = true, Surge = true },
}

local PRECISION_PROFILES = {
	{ MaxIntegrity = 3, Cells = { 3, 5 }, Charged = { 0.34, 0.67 }, Draws = 0, Rare = false, Surge = false },
	{ MaxIntegrity = 4, Cells = { 4, 6 }, Charged = { 0.3, 0.65 }, Draws = 1, Rare = false, Surge = false },
	{ MaxIntegrity = 5, Cells = { 5, 8 }, Charged = { 0.3, 0.65 }, Draws = 1, Rare = true, Surge = true },
}

local CHAOS_PROFILES = {
	{ MaxIntegrity = 3, Cells = { 3, 5 }, Charged = { 0.3, 0.7 }, Draws = 2, Rare = true, Surge = false },
	{ MaxIntegrity = 4, Cells = { 4, 7 }, Charged = { 0.3, 0.7 }, Draws = 3, Rare = true, Surge = false },
	{ MaxIntegrity = 5, Cells = { 5, 8 }, Charged = { 0.3, 0.7 }, Draws = 4, Rare = true, Surge = true },
}

local CROSSFIRE_PROFILES = {
	{ MaxIntegrity = 3, Cells = { 3, 5 }, Charged = { 0.34, 0.67 }, Draws = 0, Rare = false, Surge = false },
	{ MaxIntegrity = 4, Cells = { 4, 7 }, Charged = { 0.3, 0.65 }, Draws = 2, Rare = false, Surge = false },
	{ MaxIntegrity = 5, Cells = { 5, 8 }, Charged = { 0.3, 0.65 }, Draws = 2, Rare = true, Surge = true },
}

-- The five Endurance stages: one Trial each against a harder surrogate.
local ENDURANCE_PROFILES = {
	{ MaxIntegrity = 4, Cells = { 3, 5 }, Charged = { 0.3, 0.6 }, Draws = 2, Rare = false, Surge = false },
	{ MaxIntegrity = 4, Cells = { 3, 6 }, Charged = { 0.3, 0.65 }, Draws = 2, Rare = false, Surge = false },
	{ MaxIntegrity = 5, Cells = { 4, 7 }, Charged = { 0.3, 0.65 }, Draws = 3, Rare = true, Surge = false },
	{ MaxIntegrity = 5, Cells = { 4, 8 }, Charged = { 0.35, 0.65 }, Draws = 3, Rare = true, Surge = true },
	{ MaxIntegrity = 6, Cells = { 5, 8 }, Charged = { 0.35, 0.7 }, Draws = 3, Rare = true, Surge = true },
}

local TUTORIAL_PROFILES = {
	{ MaxIntegrity = 2, Cells = { 2, 2 }, Charged = { 0.5, 0.5 }, Draws = 0, Rare = false, Surge = false },
	{ MaxIntegrity = 4, Cells = { 3, 5 }, Charged = { 0.3, 0.6 }, Draws = 2, Rare = false, Surge = false },
	{ MaxIntegrity = 4, Cells = { 3, 5 }, Charged = { 0.3, 0.6 }, Draws = 2, Rare = false, Surge = false },
}

Modes.Profiles = {
	Standard = STANDARD_PROFILES,
	Rapid = RAPID_PROFILES,
	Precision = PRECISION_PROFILES,
	Chaos = CHAOS_PROFILES,
	Crossfire = CROSSFIRE_PROFILES,
	Endurance = ENDURANCE_PROFILES,
	Tutorial = TUTORIAL_PROFILES,
}

export type Mode = {
	Id: string,
	Name: string,
	Tagline: string,
	Description: string,
	MinPlayers: number,
	MaxPlayers: number,
	Solo: boolean, -- played against surrogates only
	Queue: string?, -- public matchmaking queue id
	Ranked: boolean,
	Customizable: boolean, -- private lobby hosts may change its rules
	XPScale: number,
	Progression: boolean, -- awards XP, Marks, statistics and challenge progress
	Base: { [string]: any },
}

local list: { Mode } = {
	{
		Id = "Standard",
		Name = "STANDARD TRIAL",
		Tagline = "Best of three Trials.",
		Description = "The full evaluation. Integrity, cell counts and instruments escalate each Trial. Take two Trials to win.",
		MinPlayers = 2,
		MaxPlayers = 2,
		Solo = false,
		Queue = "Duel",
		Ranked = false,
		Customizable = true,
		XPScale = 1,
		Progression = true,
		Base = { Profiles = "Standard", Capacity = 6, TurnTimer = 40, TrialsToWin = 2 },
	},
	{
		Id = "Ranked",
		Name = "RANKED TRIAL",
		Tagline = "Standing is on the line.",
		Description = "Standard rules, locked. Wins and losses move your Standing. Rewards are cosmetic only.",
		MinPlayers = 2,
		MaxPlayers = 2,
		Solo = false,
		Queue = "Ranked",
		Ranked = true,
		Customizable = false,
		XPScale = 1.15,
		Progression = true,
		Base = { Profiles = "Standard", Capacity = 6, TurnTimer = 35, TrialsToWin = 2, SpectatorDelay = 6 },
	},
	{
		Id = "Rapid",
		Name = "RAPID",
		Tagline = "Fifteen seconds to decide.",
		Description = "Short timers, smaller Loads, a four-slot tray and faster pacing.",
		MinPlayers = 2,
		MaxPlayers = 2,
		Solo = false,
		Queue = "Rapid",
		Ranked = false,
		Customizable = true,
		XPScale = 0.8,
		Progression = true,
		Base = { Profiles = "Rapid", Capacity = 4, TurnTimer = 15, TrialsToWin = 2, TimingScale = 0.75 },
	},
	{
		Id = "Chaos",
		Name = "CHAOS",
		Tagline = "Two new rules every Trial.",
		Description = "Every Trial rolls two random modifiers. Rare instruments are common. Eight-slot trays.",
		MinPlayers = 2,
		MaxPlayers = 2,
		Solo = false,
		Queue = "Chaos",
		Ranked = false,
		Customizable = true,
		XPScale = 1,
		Progression = true,
		Base = {
			Profiles = "Chaos",
			Capacity = 8,
			TurnTimer = 45,
			TrialsToWin = 2,
			ChaosPerTrial = 2,
			Rarity = "Chaos",
		},
	},
	{
		Id = "Precision",
		Name = "PRECISION",
		Tagline = "More information. Fewer tools.",
		Description = "At the start of every Load you privately learn one random cell. Trays hold three instruments and draws are scarce.",
		MinPlayers = 2,
		MaxPlayers = 2,
		Solo = false,
		Queue = "Precision",
		Ranked = false,
		Customizable = true,
		XPScale = 1,
		Progression = true,
		Base = { Profiles = "Precision", Capacity = 3, TurnTimer = 45, TrialsToWin = 2, PrecisionReveal = 1 },
	},
	{
		Id = "Crossfire",
		Name = "CROSSFIRE",
		Tagline = "Three or four subjects. One table.",
		Description = "Free-for-all. Choose any opponent as your target. Last subject standing takes the Trial.",
		MinPlayers = 3,
		MaxPlayers = 4,
		Solo = false,
		Queue = "Crossfire",
		Ranked = false,
		Customizable = true,
		XPScale = 1,
		Progression = true,
		Base = { Profiles = "Crossfire", Capacity = 5, TurnTimer = 35, TrialsToWin = 2 },
	},
	{
		Id = "Solo",
		Name = "SURROGATE TRIAL",
		Tagline = "Face a Halden surrogate.",
		Description = "Standard rules against an AI opponent of your choice.",
		MinPlayers = 1,
		MaxPlayers = 1,
		Solo = true,
		Queue = nil,
		Ranked = false,
		Customizable = false,
		XPScale = 1,
		Progression = true,
		Base = { Profiles = "Standard", Capacity = 6, TurnTimer = 90, TrialsToWin = 2 },
	},
	{
		Id = "Endurance",
		Name = "ENDURANCE",
		Tagline = "Five surrogates. One life.",
		Description = "Face five surrogates in a row, each harder than the last. Integrity and instruments carry over between stages, with a small recovery.",
		MinPlayers = 1,
		MaxPlayers = 1,
		Solo = true,
		Queue = nil,
		Ranked = false,
		Customizable = false,
		XPScale = 1.2,
		Progression = true,
		Base = { Profiles = "Endurance", Capacity = 6, TurnTimer = 90, TrialsToWin = 1 },
	},
	{
		Id = "Sandbox",
		Name = "CUSTOM SANDBOX",
		Tagline = "Your rules.",
		Description = "Configure everything and practice against surrogates or friends. Earns reduced XP and no challenge progress.",
		MinPlayers = 1,
		MaxPlayers = 4,
		Solo = false,
		Queue = nil,
		Ranked = false,
		Customizable = true,
		XPScale = 0.25,
		Progression = false,
		Base = { Profiles = "Standard", Capacity = 6, TurnTimer = 0, TrialsToWin = 2 },
	},
	{
		Id = "Tutorial",
		Name = "ORIENTATION",
		Tagline = "Learn the Arbiter.",
		Description = "An interactive walkthrough with a training unit.",
		MinPlayers = 1,
		MaxPlayers = 1,
		Solo = true,
		Queue = nil,
		Ranked = false,
		Customizable = false,
		XPScale = 0,
		Progression = false,
		Base = { Profiles = "Tutorial", Capacity = 6, TurnTimer = 0, TrialsToWin = 1 },
	},
}

Modes.List = list
Modes.ById = {} :: { [string]: Mode }
for _, mode in list do
	Modes.ById[mode.Id] = mode
end

function Modes.get(id: string): Mode?
	return Modes.ById[id]
end

-- Modes a private lobby host may pick as the base for a custom match.
Modes.CustomBases = { "Standard", "Rapid", "Precision", "Chaos", "Crossfire" }

return Modes

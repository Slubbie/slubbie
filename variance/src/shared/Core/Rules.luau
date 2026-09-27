-- Builds the immutable rule set a match runs under, from a mode plus optional
-- host customization. Also owns the schema for custom rules, so the server
-- can sanitize anything a private-lobby host sends and the client can draw
-- the matching controls from the same definition.

local Modes = require(script.Parent.Modes)
local Modifiers = require(script.Parent.Modifiers)
local Instruments = require(script.Parent.Instruments)

local Rules = {}

Rules.RarityPresets = {
	Standard = { Common = 55, Uncommon = 33, Rare = 12 },
	Generous = { Common = 40, Uncommon = 38, Rare = 22 },
	Scarce = { Common = 70, Uncommon = 26, Rare = 4 },
	Chaos = { Common = 35, Uncommon = 37, Rare = 28 },
}

-- Custom rule schema. Types: "enum" (Options), "int" (Min/Max), "bool", "set" (Of = id list).
Rules.CustomSchema = {
	{
		Key = "Base",
		Label = "BASE MODE",
		Type = "enum",
		Options = Modes.CustomBases,
		Default = "Standard",
		Help = "The rule set your changes start from.",
	},
	{
		Key = "MaxIntegrity",
		Label = "MAX INTEGRITY",
		Type = "int",
		Min = 0,
		Max = 8,
		Default = 0,
		Help = "0 keeps the escalating default (2 / 4 / 5). Otherwise every Trial uses this value.",
	},
	{
		Key = "TrialsToWin",
		Label = "TRIALS TO WIN",
		Type = "int",
		Min = 1,
		Max = 3,
		Default = 2,
		Help = "How many Trials a subject must take to win the match.",
	},
	{
		Key = "Draws",
		Label = "INSTRUMENTS PER LOAD",
		Type = "int",
		Min = -1,
		Max = 6,
		Default = -1,
		Help = "-1 keeps the escalating default.",
	},
	{
		Key = "StartingInstruments",
		Label = "STARTING INSTRUMENTS",
		Type = "int",
		Min = 0,
		Max = 4,
		Default = 0,
		Help = "Extra instruments dealt at the start of every Trial.",
	},
	{
		Key = "Capacity",
		Label = "TRAY CAPACITY",
		Type = "int",
		Min = 2,
		Max = 8,
		Default = 6,
		Help = "How many instruments a subject can hold. Extra draws are lost.",
	},
	{
		Key = "Damage",
		Label = "CELL DAMAGE",
		Type = "int",
		Min = 1,
		Max = 3,
		Default = 1,
		Help = "Damage dealt by a CHARGED cell before instruments.",
	},
	{
		Key = "Rarity",
		Label = "RARITY",
		Type = "enum",
		Options = { "Standard", "Generous", "Scarce", "Chaos" },
		Default = "Standard",
		Help = "How often Uncommon and Rare instruments appear.",
	},
	{
		Key = "Enabled",
		Label = "ENABLED INSTRUMENTS",
		Type = "set",
		Of = Instruments.ids(),
		Default = Instruments.ids(),
		Help = "Instruments that can be drawn.",
	},
	{
		Key = "TurnTimer",
		Label = "TURN TIMER",
		Type = "int",
		Min = 0,
		Max = 90,
		Step = 5,
		MinNonZero = 10,
		Default = 40,
		Help = "Seconds per decision. 0 turns the timer off. When it runs out, the Arbiter fires at the undecided subject.",
	},
	{
		Key = "Modifiers",
		Label = "MODIFIERS",
		Type = "set",
		Of = (function()
			local ids = {}
			for _, mod in Modifiers.List do
				table.insert(ids, mod.Id)
			end
			return ids
		end)(),
		Default = {},
		MaxCount = 4,
		Help = "Experimental rules, active for the whole match.",
	},
	{
		Key = "Environment",
		Label = "ENVIRONMENT",
		Type = "enum",
		Options = { "Rotate", "TestChamber", "BroadcastStudio", "ResearchVault", "FreightTerminal", "CasinoBackroom", "EvaluationSuite" },
		Default = "Rotate",
		Help = "The room the match is played in.",
	},
	{
		Key = "Spectators",
		Label = "ALLOW SPECTATORS",
		Type = "bool",
		Default = true,
		Help = "Whether other subjects can watch this match.",
	},
}

Rules.SchemaByKey = {}
for _, field in Rules.CustomSchema do
	Rules.SchemaByKey[field.Key] = field
end

-- Returns a clean copy of a host's custom settings. Unknown keys are dropped,
-- numbers are clamped and rounded, enums and sets are checked against their options.
function Rules.sanitizeCustom(input: any): { [string]: any }
	local clean = {}
	local source = if type(input) == "table" then input else {}
	for _, field in Rules.CustomSchema do
		local value = source[field.Key]
		if field.Type == "int" then
			if type(value) ~= "number" or value ~= value then
				value = field.Default
			end
			value = math.clamp(math.floor(value + 0.5), field.Min, field.Max)
			if field.Step and value ~= 0 then
				local stepped = math.floor(value / field.Step + 0.5) * field.Step
				value = math.clamp(stepped, field.MinNonZero or math.max(field.Min, field.Step), field.Max)
			end
		elseif field.Type == "enum" then
			if type(value) ~= "string" or not table.find(field.Options, value) then
				value = field.Default
			end
		elseif field.Type == "bool" then
			if type(value) ~= "boolean" then
				value = field.Default
			end
		elseif field.Type == "set" then
			local out = {}
			if type(value) == "table" then
				local seen = {}
				for _, id in value do
					if type(id) == "string" and table.find(field.Of, id) and not seen[id] then
						seen[id] = true
						table.insert(out, id)
					end
					if field.MaxCount and #out >= field.MaxCount then
						break
					end
				end
			else
				for _, id in field.Default do
					table.insert(out, id)
				end
			end
			table.sort(out)
			value = out
		end
		clean[field.Key] = value
	end
	return clean
end

function Rules.defaultCustom(): { [string]: any }
	return Rules.sanitizeCustom({})
end

local function copyProfiles(name: string): { any }
	local source = Modes.Profiles[name] or Modes.Profiles.Standard
	local out = {}
	for i, profile in source do
		out[i] = {
			MaxIntegrity = profile.MaxIntegrity,
			Cells = { profile.Cells[1], profile.Cells[2] },
			Charged = { profile.Charged[1], profile.Charged[2] },
			Draws = profile.Draws,
			Rare = profile.Rare,
			Surge = profile.Surge,
		}
	end
	return out
end

export type RuleSet = { [string]: any }

-- Builds the rule set for a mode. `custom` (already sanitized) is only applied
-- to customizable modes; `overrides` is for server-side systems (tutorial,
-- endurance carry-over, debug) and is applied last.
function Rules.build(modeId: string, custom: { [string]: any }?, overrides: { [string]: any }?): RuleSet
	local mode = Modes.get(modeId) or Modes.ById.Standard
	local base = mode.Base
	local profileName = base.Profiles
	if custom and mode.Customizable and custom.Base then
		local baseMode = Modes.get(custom.Base)
		if baseMode then
			base = baseMode.Base
			profileName = base.Profiles
		end
	end

	local pool = {}
	for _, id in Instruments.ids() do
		pool[id] = true
	end

	local rules: RuleSet = {
		ModeId = mode.Id,
		ModeName = mode.Name,
		Ranked = mode.Ranked,
		Progression = mode.Progression,
		XPScale = mode.XPScale,
		TrialsToWin = base.TrialsToWin or 2,
		Capacity = base.Capacity or 6,
		BaseDamage = 1,
		TurnTimer = base.TurnTimer or 40,
		TimeoutAction = "Self",
		TimingScale = base.TimingScale or 1,
		Profiles = copyProfiles(profileName),
		Pool = pool,
		RarityWeights = table.clone(Rules.RarityPresets[base.Rarity or "Standard"]),
		Modifiers = {},
		ChaosPerTrial = base.ChaosPerTrial or 0,
		PrecisionReveal = base.PrecisionReveal or 0,
		StartingInstruments = 0,
		FixedIntegrity = nil,
		DrawsOverride = nil,
		FriendlyFire = false,
		SuddenDeath = true,
		PerTurnCap = 8,
		InfiniteInstruments = false,
		Forced = nil,
		AllowSpectators = true,
		SpectatorDelay = base.SpectatorDelay or 0,
		Environment = "Rotate",
	}

	if custom and mode.Customizable then
		rules.TrialsToWin = custom.TrialsToWin
		rules.Capacity = custom.Capacity
		rules.BaseDamage = custom.Damage
		rules.TurnTimer = custom.TurnTimer
		rules.StartingInstruments = custom.StartingInstruments
		rules.RarityWeights = table.clone(Rules.RarityPresets[custom.Rarity] or Rules.RarityPresets.Standard)
		if custom.MaxIntegrity and custom.MaxIntegrity > 0 then
			rules.FixedIntegrity = custom.MaxIntegrity
		end
		if custom.Draws and custom.Draws >= 0 then
			rules.DrawsOverride = custom.Draws
		end
		local enabled = {}
		for _, id in custom.Enabled or {} do
			enabled[id] = true
		end
		rules.Pool = enabled
		for _, id in custom.Modifiers or {} do
			rules.Modifiers[id] = true
		end
		rules.Environment = custom.Environment or "Rotate"
		rules.AllowSpectators = custom.Spectators ~= false
	end

	if overrides then
		for key, value in overrides do
			rules[key] = value
		end
	end
	return rules
end

-- The escalation profile for a Trial (Trials past the list reuse the last one).
function Rules.profile(rules: RuleSet, trial: number): { [string]: any }
	local profiles = rules.Profiles
	return profiles[math.clamp(trial, 1, #profiles)]
end

-- A short human-readable summary of a rule set, for lobby cards and tooltips.
function Rules.describe(rules: RuleSet): { string }
	local lines = {}
	table.insert(lines, string.format("First to %d Trial%s", rules.TrialsToWin, rules.TrialsToWin == 1 and "" or "s"))
	if rules.FixedIntegrity then
		table.insert(lines, string.format("%d Integrity every Trial", rules.FixedIntegrity))
	end
	table.insert(lines, string.format("Tray capacity %d", rules.Capacity))
	if rules.BaseDamage ~= 1 then
		table.insert(lines, string.format("Cells deal %d damage", rules.BaseDamage))
	end
	if rules.TurnTimer > 0 then
		table.insert(lines, string.format("%ds turn timer", rules.TurnTimer))
	else
		table.insert(lines, "No turn timer")
	end
	for id in rules.Modifiers do
		local mod = Modifiers.get(id)
		if mod then
			table.insert(lines, mod.Name)
		end
	end
	if rules.ChaosPerTrial > 0 then
		table.insert(lines, string.format("%d random modifiers per Trial", rules.ChaosPerTrial))
	end
	if rules.PrecisionReveal > 0 then
		table.insert(lines, "One cell revealed privately each Load")
	end
	return lines
end

return Rules

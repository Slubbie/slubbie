-- The Halden surrogates: AI opponents built from the recorded behaviour of former
-- subjects. A personality is a set of biases layered on top of a difficulty
-- tier's reasoning, so LEDGER on Expert and VOLTA on Expert are equally sharp
-- but make different choices at the margins.
--
--   Aggression    extra value on firing at opponents and offensive instruments
--   Caution       penalty on risking itself, extra value on defense/recovery
--   Risk          appetite for variance (Serum, Tether, coin-flip self-shots)
--   Info          multiplier on the value of information instruments
--   Conservation  multiplier on how much it prefers keeping instruments
--   Temperature   multiplier on randomness
--   Affinity      flat bonus per instrument id
--   ModelBoost    extra trust in its model of your habits (the Proctor)
--
-- Presentation (look, voice, animation style) lives in Data/Surrogates.luau and
-- lines in Data/Dialogue.luau, both keyed by the same Id.

local Personalities = {}

export type Personality = {
	Id: string,
	Name: string,
	Epithet: string,
	Bio: string,
	Style: string,
	Aggression: number,
	Caution: number,
	Risk: number,
	Info: number,
	Conservation: number,
	Temperature: number,
	Affinity: { [string]: number },
	ModelBoost: number,
	Secret: boolean,
	Selectable: boolean,
	Order: number,
}

local list: { Personality } = {
	{
		Id = "Ledger",
		Name = "LEDGER",
		Epithet = "The Actuary",
		Bio = "Modelled on Subject 0114, a claims assessor who never once fired without doing the arithmetic first.",
		Style = "Conservative. Pure expected value. Rarely gambles, never wastes.",
		Aggression = -0.1,
		Caution = 0.6,
		Risk = -0.5,
		Info = 0.3,
		Conservation = 1.35,
		Temperature = 0.7,
		Affinity = { Lens = 0.008, Dampener = 0.008, Suture = 0.004 },
		ModelBoost = 0,
		Secret = false,
		Selectable = true,
		Order = 1,
	},
	{
		Id = "Volta",
		Name = "VOLTA",
		Epithet = "The Live Wire",
		Bio = "Built from Subject 0388, a linesman who treated every Trial like a race to the last spark.",
		Style = "Aggressive. Maximizes damage and tempo. Loves a primed Capacitor.",
		Aggression = 0.7,
		Caution = -0.3,
		Risk = 0.15,
		Info = -0.3,
		Conservation = 0.6,
		Temperature = 1.1,
		Affinity = { Capacitor = 0.014, Overclock = 0.012, Clamp = 0.008 },
		ModelBoost = 0,
		Secret = false,
		Selectable = true,
		Order = 2,
	},
	{
		Id = "Magpie",
		Name = "MAGPIE",
		Epithet = "The Archivist",
		Bio = "Assembled from Subject 0502, a records clerk who hoarded every scrap of information and acted only when certain.",
		Style = "Information-hungry. Collects readings, hoards tools, strikes on certainty.",
		Aggression = 0,
		Caution = 0.25,
		Risk = -0.2,
		Info = 0.9,
		Conservation = 1.6,
		Temperature = 0.8,
		Affinity = { Lens = 0.012, Sonar = 0.014, Rotor = 0.006 },
		ModelBoost = 0,
		Secret = false,
		Selectable = true,
		Order = 3,
	},
	{
		Id = "Kismet",
		Name = "KISMET",
		Epithet = "The Gambler",
		Bio = "Distilled from Subject 0777, who lost everything at the tables upstairs and asked to keep playing downstairs.",
		Style = "Reckless. Seeks variance, trusts luck, reaches for anything unstable.",
		Aggression = 0.2,
		Caution = -0.45,
		Risk = 0.85,
		Info = -0.2,
		Conservation = 0.7,
		Temperature = 2.2,
		Affinity = { Serum = 0.016, Scrambler = 0.014, Tether = 0.012, PowerTap = 0.01 },
		ModelBoost = 0,
		Secret = false,
		Selectable = true,
		Order = 4,
	},
	{
		Id = "Proctor",
		Name = "THE PROCTOR",
		Epithet = "The Administrator",
		Bio = "Not a surrogate. The Institute's own evaluator, trained on forty years of Trials. It is studying you.",
		Style = "Adaptive. Builds a model of your habits during the match and plays against them.",
		Aggression = 0.1,
		Caution = 0.1,
		Risk = 0,
		Info = 0.4,
		Conservation = 1.1,
		Temperature = 0.5,
		Affinity = {},
		ModelBoost = 0.35,
		Secret = true,
		Selectable = false,
		Order = 5,
	},
	{
		Id = "Proxy",
		Name = "PROXY",
		Epithet = "Training Unit",
		Bio = "A calibration dummy used for orientation. It does exactly what it is told.",
		Style = "Scripted.",
		Aggression = 0,
		Caution = 0,
		Risk = 0,
		Info = 0,
		Conservation = 1,
		Temperature = 1,
		Affinity = {},
		ModelBoost = 0,
		Secret = false,
		Selectable = false,
		Order = 99,
	},
}

Personalities.List = list
Personalities.ById = {} :: { [string]: Personality }
for _, p in list do
	Personalities.ById[p.Id] = p
end

function Personalities.get(id: string?): Personality
	return Personalities.ById[id or ""] or Personalities.ById.Ledger
end

-- Surrogates offered in the challenge terminal, in display order.
function Personalities.selectable(includeSecret: boolean): { Personality }
	local out = {}
	for _, p in list do
		if p.Selectable or (includeSecret and p.Secret) then
			table.insert(out, p)
		end
	end
	table.sort(out, function(a, b)
		return a.Order < b.Order
	end)
	return out
end

return Personalities

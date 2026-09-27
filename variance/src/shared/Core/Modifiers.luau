-- Rule modifiers: optional twists used by Chaos mode, private lobbies and events.
--
-- A modifier is data: `Flags` are switched on while it is active, and `Numbers`
-- are added to numeric rule values. The Engine reads everything through
-- Engine.flag(state, name) / Engine.number(state, name), which merge the
-- match's permanent modifiers with the ones rolled for the current Trial, so a
-- new modifier usually needs no engine change at all.

local Modifiers = {}

export type Modifier = {
	Id: string,
	Name: string,
	Description: string,
	Flags: { [string]: boolean }?,
	Numbers: { [string]: number }?,
	Chaos: boolean, -- can be rolled by Chaos mode
	Ranked: boolean, -- allowed in competitive rule sets (none are, by default)
}

local list: { Modifier } = {
	{
		Id = "Volatile",
		Name = "VOLATILE CELLS",
		Description = "CHARGED cells deal +1 damage.",
		Numbers = { BonusDamage = 1 },
		Chaos = true,
		Ranked = false,
	},
	{
		Id = "Blind",
		Name = "BLIND LOAD",
		Description = "Only the total number of cells is announced, not the mix.",
		Flags = { Blind = true },
		Chaos = true,
		Ranked = false,
	},
	{
		Id = "Scarcity",
		Name = "SCARCITY",
		Description = "Half as many instruments are dealt each Load.",
		Flags = { Scarcity = true },
		Chaos = true,
		Ranked = false,
	},
	{
		Id = "Surplus",
		Name = "SURPLUS",
		Description = "+2 instruments each Load and +2 tray capacity.",
		Numbers = { ExtraDraws = 2, ExtraCapacity = 2 },
		Chaos = true,
		Ranked = false,
	},
	{
		Id = "MirrorDraw",
		Name = "MIRROR DRAW",
		Description = "Every subject is dealt the same instruments.",
		Flags = { MirrorDraw = true },
		Chaos = true,
		Ranked = false,
	},
	{
		Id = "HeavyCells",
		Name = "HEAVY LOADS",
		Description = "Loads skew CHARGED (55-80% of cells).",
		Flags = { HeavyCells = true },
		Chaos = true,
		Ranked = false,
	},
	{
		Id = "LightCells",
		Name = "LIGHT LOADS",
		Description = "Loads skew HOLLOW (20-45% CHARGED).",
		Flags = { LightCells = true },
		Chaos = true,
		Ranked = false,
	},
	{
		Id = "SurgeAll",
		Name = "SURGE",
		Description = "The last cell of every Load deals +1 damage, in every Trial.",
		Flags = { SurgeAll = true },
		Chaos = true,
		Ranked = false,
	},
	{
		Id = "ShortFuse",
		Name = "SHORT FUSE",
		Description = "Turn timers are halved.",
		Flags = { ShortFuse = true },
		Chaos = true,
		Ranked = false,
	},
	{
		Id = "Glass",
		Name = "GLASS",
		Description = "Maximum Integrity is 1 lower in every Trial (minimum 1).",
		Numbers = { IntegrityDelta = -1 },
		Chaos = true,
		Ranked = false,
	},
	{
		Id = "Echo",
		Name = "ECHO",
		Description = "Survive a shot at yourself and you privately learn the next loaded cell.",
		Flags = { Echo = true },
		Chaos = true,
		Ranked = false,
	},
	{
		Id = "Lockdown",
		Name = "LOCKDOWN",
		Description = "Tempo instruments (Clamp, Overclock) are removed from the pool.",
		Flags = { Lockdown = true },
		Chaos = true,
		Ranked = false,
	},
}

-- Pairs that make no sense together; Chaos never rolls both.
Modifiers.Exclusive = {
	HeavyCells = "LightCells",
	LightCells = "HeavyCells",
	Scarcity = "Surplus",
	Surplus = "Scarcity",
}

Modifiers.List = list
Modifiers.ById = {} :: { [string]: Modifier }
for _, mod in list do
	Modifiers.ById[mod.Id] = mod
end

function Modifiers.get(id: string): Modifier?
	return Modifiers.ById[id]
end

-- Rolls `count` distinct Chaos modifiers.
function Modifiers.rollChaos(rng: any, count: number, exclude: { [string]: boolean }?): { string }
	local pool = {}
	for _, mod in list do
		if mod.Chaos and not (exclude and exclude[mod.Id]) then
			table.insert(pool, mod.Id)
		end
	end
	local chosen = {}
	local taken = {}
	while #chosen < count and #pool > 0 do
		local index = rng:NextInteger(1, #pool)
		local id = table.remove(pool, index) :: string
		local clash = Modifiers.Exclusive[id]
		if not (clash and taken[clash]) then
			table.insert(chosen, id)
			taken[id] = true
		end
	end
	table.sort(chosen)
	return chosen
end

return Modifiers

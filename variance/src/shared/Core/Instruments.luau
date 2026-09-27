-- Instruments: the equipment subjects draw between Loads.
--
-- Each definition is plain data (names, tooltips, rarity, pacing) plus two pure
-- functions the Engine calls on the server:
--   CanUse(state, user, target, E) -> (ok, reason?)   reason is shown to the player
--   Apply(state, user, target, E)                      mutates state through `E`
-- `E` is the Engine module, passed in to avoid a require cycle. Instruments only
-- touch state through its helpers (E.emitUse, E.reveal, E.damage, ...), so every
-- change is validated, logged and replicated the same way.
--
-- Adding an instrument: add an entry below, give it an icon in
-- client/UI/Icons.luau and a prop in shared/Visual/InstrumentProps.luau. The AI
-- values it automatically if you also add a case to Core/AI/Brain.luau's simulate().

local Instruments = {}

Instruments.Rarities = {
	Common = { Order = 1, Weight = 55, Label = "COMMON" },
	Uncommon = { Order = 2, Weight = 33, Label = "UNCOMMON" },
	Rare = { Order = 3, Weight = 12, Label = "RARE" },
}

Instruments.Categories = {
	Information = "INFORMATION",
	Manipulation = "MANIPULATION",
	Recovery = "RECOVERY",
	Offense = "OFFENSE",
	Defense = "DEFENSE",
	Control = "CONTROL",
	Tempo = "TEMPO",
	HighRisk = "HIGH RISK",
}

export type Definition = {
	Id: string,
	Name: string,
	Rarity: string,
	Weight: number,
	Category: string,
	Short: string,
	Description: string,
	Visibility: string, -- what opponents learn: shown in the tooltip
	Targeted: boolean,
	PerTurnLimit: number,
	HoldValue: number, -- AI conservation baseline, in win-probability units
	Duration: number, -- seconds the server waits for the activation to play out
	CanUse: (state: any, user: any, target: any, E: any) -> (boolean, string?),
	Apply: (state: any, user: any, target: any, E: any) -> (),
}

local list: { Definition } = {
	{
		Id = "Lens",
		Name = "LENS",
		Rarity = "Common",
		Weight = 1,
		Category = "Information",
		Short = "Privately see the loaded cell.",
		Description = "Peer through the chamber window. You learn whether the loaded cell is CHARGED or HOLLOW.",
		Visibility = "Opponents see you use it, not what you saw.",
		Targeted = false,
		PerTurnLimit = 1,
		HoldValue = 0.035,
		Duration = 1.7,
		CanUse = function(state, user, _target, E)
			local cell = E.loadedCell(state)
			if cell == nil then
				return false, "The chamber is empty."
			end
			if user.Knows[cell.Uid] then
				return false, "You already know the loaded cell."
			end
			return true
		end,
		Apply = function(state, user, _target, E)
			local cell = E.loadedCell(state)
			E.learn(state, user, cell)
			E.emitUse(state, user, "Lens", nil, {}, {
				[user.Id] = { Reveal = { { Index = 1, Charged = cell.Charged } } },
			})
		end,
	},
	{
		Id = "Ejector",
		Name = "EJECTOR",
		Rarity = "Common",
		Weight = 1,
		Category = "Manipulation",
		Short = "Remove the loaded cell unfired.",
		Description = "Cycle the action and throw the loaded cell out without firing it. Everyone sees what it was. Your turn continues.",
		Visibility = "The ejected cell is revealed to everyone.",
		Targeted = false,
		PerTurnLimit = 99,
		HoldValue = 0.03,
		Duration = 1.6,
		CanUse = function(state, _user, _target, E)
			if E.loadedCell(state) == nil then
				return false, "The chamber is empty."
			end
			return true
		end,
		Apply = function(state, user, _target, E)
			local cell = E.removeLoaded(state)
			E.emitUse(state, user, "Ejector", nil, { Charged = cell.Charged }, nil)
		end,
	},
	{
		Id = "Suture",
		Name = "SUTURE",
		Rarity = "Common",
		Weight = 1,
		Category = "Recovery",
		Short = "Restore 1 Integrity.",
		Description = "A field patch. Restores 1 Integrity, up to your maximum for this Trial.",
		Visibility = "Public.",
		Targeted = false,
		PerTurnLimit = 2,
		HoldValue = 0.04,
		Duration = 1.5,
		CanUse = function(_state, user)
			if user.Integrity >= user.MaxIntegrity then
				return false, "Integrity is already full."
			end
			return true
		end,
		Apply = function(state, user, _target, E)
			E.emitUse(state, user, "Suture", nil, {}, nil)
			E.heal(state, user, 1, "Suture")
		end,
	},
	{
		Id = "Capacitor",
		Name = "CAPACITOR",
		Rarity = "Common",
		Weight = 1,
		Category = "Offense",
		Short = "Next CHARGED shot deals double damage.",
		Description = "Bank extra charge into the coils. If your next shot is CHARGED it deals double damage. It is spent on your next shot either way.",
		Visibility = "Public: the coils glow while it is primed.",
		Targeted = false,
		PerTurnLimit = 1,
		HoldValue = 0.035,
		Duration = 1.4,
		CanUse = function(_state, user)
			if user.Effects.Capacitor then
				return false, "The Capacitor is already primed."
			end
			return true
		end,
		Apply = function(state, user, _target, E)
			E.setEffect(state, user, "Capacitor", true)
			E.emitUse(state, user, "Capacitor", nil, {}, nil)
		end,
	},
	{
		Id = "Clamp",
		Name = "CLAMP",
		Rarity = "Uncommon",
		Weight = 1,
		Category = "Control",
		Short = "Your opponent loses their next turn.",
		Description = "Restrain an opponent's hands. They skip their next turn. A subject cannot be clamped again until they have played a turn.",
		Visibility = "Public.",
		Targeted = true,
		PerTurnLimit = 1,
		HoldValue = 0.04,
		Duration = 1.6,
		CanUse = function(_state, user, target)
			if target == nil or target == user then
				return false, "Choose an opponent."
			end
			if target.Eliminated then
				return false, "That subject is out."
			end
			if target.Effects.Clamped then
				return false, "Already restrained."
			end
			if target.Effects.ClampImmune then
				return false, "They must play a turn before being clamped again."
			end
			return true
		end,
		Apply = function(state, user, target, E)
			E.setEffect(state, target, "Clamped", true)
			E.emitUse(state, user, "Clamp", target, {}, nil)
		end,
	},
	{
		Id = "Inverter",
		Name = "INVERTER",
		Rarity = "Uncommon",
		Weight = 1,
		Category = "Manipulation",
		Short = "Flip the loaded cell's polarity.",
		Description = "Reverse the loaded cell: CHARGED becomes HOLLOW and HOLLOW becomes CHARGED. Nobody learns which it is now unless they already knew.",
		Visibility = "Public, but the cell's new type stays hidden.",
		Targeted = false,
		PerTurnLimit = 2,
		HoldValue = 0.045,
		Duration = 1.5,
		CanUse = function(state, _user, _target, E)
			if E.loadedCell(state) == nil then
				return false, "The chamber is empty."
			end
			return true
		end,
		Apply = function(state, user, _target, E)
			E.invertLoaded(state)
			E.emitUse(state, user, "Inverter", nil, {}, nil)
		end,
	},
	{
		Id = "Sonar",
		Name = "SONAR",
		Rarity = "Uncommon",
		Weight = 1,
		Category = "Information",
		Short = "Privately learn one later cell.",
		Description = "Ping the chamber. You learn the type and position of one random cell you don't already know, after the loaded one.",
		Visibility = "Opponents see you use it, not what you learned.",
		Targeted = false,
		PerTurnLimit = 2,
		HoldValue = 0.03,
		Duration = 1.8,
		CanUse = function(state, user, _target, _E)
			local load = state.Load
			if load == nil then
				return false, "The chamber is empty."
			end
			for i = 2, #load.Cells do
				if not user.Knows[load.Cells[i].Uid] then
					return true
				end
			end
			return false, "No unknown cells after the loaded one."
		end,
		Apply = function(state, user, _target, E)
			local load = state.Load
			local options = {}
			for i = 2, #load.Cells do
				if not user.Knows[load.Cells[i].Uid] then
					table.insert(options, i)
				end
			end
			local index = options[state.Rng:NextInteger(1, #options)]
			local cell = load.Cells[index]
			E.learn(state, user, cell)
			E.emitUse(state, user, "Sonar", nil, {}, {
				[user.Id] = { Reveal = { { Index = index, Charged = cell.Charged } } },
			})
		end,
	},
	{
		Id = "Dampener",
		Name = "DAMPENER",
		Rarity = "Uncommon",
		Weight = 1,
		Category = "Defense",
		Short = "Absorb 1 damage from the next hit.",
		Description = "An insulating field. The next CHARGED cell that hits you this Load deals 1 less damage. Fades when the Load ends.",
		Visibility = "Public: the field is visible.",
		Targeted = false,
		PerTurnLimit = 1,
		HoldValue = 0.03,
		Duration = 1.4,
		CanUse = function(_state, user)
			if user.Effects.Dampener then
				return false, "A Dampener is already active."
			end
			return true
		end,
		Apply = function(state, user, _target, E)
			E.setEffect(state, user, "Dampener", true)
			E.emitUse(state, user, "Dampener", nil, {}, nil)
		end,
	},
	{
		Id = "Rotor",
		Name = "ROTOR",
		Rarity = "Uncommon",
		Weight = 1,
		Category = "Manipulation",
		Short = "Rotate the next three cells.",
		Description = "Turn the cylinder: the loaded cell moves to third position and the next two move up. Anything you knew about them moves with them.",
		Visibility = "Public.",
		Targeted = false,
		PerTurnLimit = 2,
		HoldValue = 0.03,
		Duration = 1.6,
		CanUse = function(state, _user, _target, _E)
			if state.Load == nil or #state.Load.Cells < 2 then
				return false, "Needs at least two cells."
			end
			return true
		end,
		Apply = function(state, user, _target, E)
			local span = E.rotate(state, 3)
			E.emitUse(state, user, "Rotor", nil, { Span = span }, nil)
		end,
	},
	{
		Id = "Overclock",
		Name = "OVERCLOCK",
		Rarity = "Rare",
		Weight = 1,
		Category = "Tempo",
		Short = "Your next shot doesn't end your turn.",
		Description = "A stimulant for the hands. After your next shot you act again, whatever the cell was.",
		Visibility = "Public.",
		Targeted = false,
		PerTurnLimit = 1,
		HoldValue = 0.05,
		Duration = 1.5,
		CanUse = function(_state, user)
			if user.Effects.Overclock then
				return false, "Already overclocked."
			end
			return true
		end,
		Apply = function(state, user, _target, E)
			E.setEffect(state, user, "Overclock", true)
			E.emitUse(state, user, "Overclock", nil, {}, nil)
		end,
	},
	{
		Id = "Serum",
		Name = "UNSTABLE SERUM",
		Rarity = "Rare",
		Weight = 1,
		Category = "HighRisk",
		Short = "60%: +2 Integrity. 40%: -1 Integrity.",
		Description = "An unlicensed compound. 60% chance to restore 2 Integrity, 40% chance to lose 1. It can take your last point.",
		Visibility = "Public, including the result.",
		Targeted = false,
		PerTurnLimit = 1,
		HoldValue = 0.02,
		Duration = 2.2,
		CanUse = function()
			return true
		end,
		Apply = function(state, user, _target, E)
			local good = state.Rng:NextNumber() < 0.6
			E.emitUse(state, user, "Serum", nil, { Good = good }, nil)
			if good then
				E.heal(state, user, 2, "Serum")
			else
				E.damage(state, user, 1, "Serum", user, true)
			end
		end,
	},
	{
		Id = "PowerTap",
		Name = "POWER TAP",
		Rarity = "Rare",
		Weight = 1,
		Category = "HighRisk",
		Short = "Pay 1 Integrity, draw 2 instruments.",
		Description = "Route your own current into the dispenser. Lose 1 Integrity and draw 2 new instruments. Needs at least 2 Integrity. Draws beyond capacity are lost.",
		Visibility = "Public, including what you draw.",
		Targeted = false,
		PerTurnLimit = 1,
		HoldValue = 0.02,
		Duration = 2.0,
		CanUse = function(_state, user)
			if user.Integrity < 2 then
				return false, "Needs at least 2 Integrity."
			end
			return true
		end,
		Apply = function(state, user, _target, E)
			E.emitUse(state, user, "PowerTap", nil, {}, nil)
			E.damage(state, user, 1, "PowerTap", user, true)
			E.draw(state, user, 2, "PowerTap")
		end,
	},
	{
		Id = "Tether",
		Name = "TETHER",
		Rarity = "Rare",
		Weight = 1,
		Category = "HighRisk",
		Short = "Until the Load ends, all damage hits everyone.",
		Description = "Link every subject to the same circuit. Until this Load ends, damage dealt to anyone is also dealt to everyone else. Everyone can fall at once.",
		Visibility = "Public: the link is visible.",
		Targeted = false,
		PerTurnLimit = 1,
		HoldValue = 0.02,
		Duration = 1.9,
		CanUse = function(state)
			if state.Tether then
				return false, "A Tether is already active."
			end
			return true
		end,
		Apply = function(state, user, _target, E)
			E.setTether(state, user)
			E.emitUse(state, user, "Tether", nil, {}, nil)
		end,
	},
	{
		Id = "Scrambler",
		Name = "SCRAMBLER",
		Rarity = "Rare",
		Weight = 1,
		Category = "HighRisk",
		Short = "Re-cast the remaining cells at random.",
		Description = "Dump every remaining cell and load the same number again with a brand-new random mix. All knowledge is wiped. The new counts are announced.",
		Visibility = "Public: the new counts are announced to everyone.",
		Targeted = false,
		PerTurnLimit = 1,
		HoldValue = 0.02,
		Duration = 2.4,
		CanUse = function(state)
			if state.Load == nil or #state.Load.Cells < 2 then
				return false, "Needs at least two cells."
			end
			return true
		end,
		Apply = function(state, user, _target, E)
			local size, charged = E.recast(state)
			E.emitUse(state, user, "Scrambler", nil, {
				PoolSize = size,
				PoolCharged = if E.flag(state, "Blind") then nil else charged,
			}, nil)
		end,
	},
}

Instruments.List = list
Instruments.ById = {} :: { [string]: Definition }
Instruments.Order = {} :: { [string]: number }
for index, def in list do
	Instruments.ById[def.Id] = def
	Instruments.Order[def.Id] = index
end

function Instruments.get(id: string): Definition?
	return Instruments.ById[id]
end

function Instruments.isValid(id: any): boolean
	return type(id) == "string" and Instruments.ById[id] ~= nil
end

-- Every id, in catalog order.
function Instruments.ids(): { string }
	local ids = {}
	for _, def in list do
		table.insert(ids, def.Id)
	end
	return ids
end

-- Weighted pick from the enabled pool. `allowRare` is false in early Trials.
function Instruments.roll(rng: any, pool: { [string]: boolean }, rarityWeights: { [string]: number }, allowRare: boolean): string?
	local byRarity: { [string]: { string } } = {}
	for _, def in list do
		if pool[def.Id] and (allowRare or def.Rarity ~= "Rare") then
			byRarity[def.Rarity] = byRarity[def.Rarity] or {}
			for _ = 1, def.Weight do
				table.insert(byRarity[def.Rarity], def.Id)
			end
		end
	end
	local weights = {}
	for rarity, entries in byRarity do
		if #entries > 0 then
			weights[rarity] = rarityWeights[rarity] or 0
		end
	end
	local total = 0
	local rarities = {}
	for rarity, weight in weights do
		if weight > 0 then
			total += weight
			table.insert(rarities, rarity)
		end
	end
	if total <= 0 then
		return nil
	end
	table.sort(rarities, function(a, b)
		return Instruments.Rarities[a].Order < Instruments.Rarities[b].Order
	end)
	local roll = rng:NextNumber() * total
	local chosen = rarities[#rarities]
	for _, rarity in rarities do
		roll -= weights[rarity]
		if roll <= 0 then
			chosen = rarity
			break
		end
	end
	local entries = byRarity[chosen]
	return entries[rng:NextInteger(1, #entries)]
end

return Instruments

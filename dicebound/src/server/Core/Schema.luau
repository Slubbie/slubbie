-- Player save format: defaults, migrations and validation. Pure logic (no Roblox services).
--
-- To change the format in a future update:
--   1. Bump Schema.Version.
--   2. Add Migrations[oldVersion] = function(data) ... end that upgrades data in place by one version.
--   3. Update Defaults() and Sanitize() for the new fields.
-- Old saves are migrated step by step when they load, then sanitized, so they never lose progress.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Dicebound.Config)

local Schema = {}

Schema.Version = 2

export type Stack = { Id: string, Mut: string?, Qty: number, Locked: boolean, Seq: number }

export type Data = {
	Version: number,
	Coins: number,
	Bag: { [string]: Stack },
	Seq: number,
	Upgrades: { [string]: number },
	Dice: { Owned: { [string]: boolean }, Equipped: { string } },
	Regions: { [string]: boolean },
	Discovered: { [string]: { N: number, T: number } },
	MutationsFound: { [string]: boolean },
	Stats: { [string]: number },
	Tutorial: { Step: number, Done: boolean },
	Settings: { [string]: any },
	Orphans: { any },
	-- v2
	Orders: { Slots: { any }, NextId: number, SkipAt: number },
	Daily: { Day: number, List: { any } },
	Milestones: { [string]: boolean },
	Collection: { [string]: boolean },
	Cosmetics: { Auras: { [string]: boolean }, Trays: { [string]: boolean }, Aura: string, Tray: string },
}

Schema.StatNames = {
	"Rolls",
	"Found",
	"Sold",
	"CoinsEarned",
	"Combos",
	"Jackpots",
	"Upgrades",
	-- v2
	"Rares",
	"Mutated",
	"SaleCoins",
	"Orders",
	"Crafts",
}

Schema.SettingDefaults = {
	Music = 0.5,
	Sfx = 0.8,
	ReducedMotion = false,
	SkipReveals = false,
}

function Schema.Defaults(): Data
	local upgrades = {}
	for _, upgrade in Config.Economy.Upgrades.List do
		upgrades[upgrade.Id] = 0
	end
	local stats = {}
	for _, name in Schema.StatNames do
		stats[name] = 0
	end
	return {
		Version = Schema.Version,
		Coins = Config.Game.StartingCoins,
		Bag = {},
		Seq = 0,
		Upgrades = upgrades,
		Dice = { Owned = { [Config.Game.StartingDie] = true }, Equipped = { Config.Game.StartingDie } },
		Regions = { [Config.Regions.List[1].Id] = true },
		Discovered = {},
		MutationsFound = {},
		Stats = stats,
		Tutorial = { Step = 1, Done = false },
		Settings = table.clone(Schema.SettingDefaults),
		Orphans = {},
		Orders = { Slots = {}, NextId = 0, SkipAt = 0 },
		Daily = { Day = 0, List = {} },
		Milestones = {},
		Collection = {},
		Cosmetics = { Auras = {}, Trays = { classic = true }, Aura = "", Tray = "classic" },
	}
end

-- Migrations[v] upgrades a version-v save to version v + 1.
local Migrations: { [number]: (any) -> () } = {
	-- v1 -> v2: orders, dailies, milestones, collection rewards and cosmetics were added (Sanitize
	-- fills their defaults). Backfill the new "Mutated" stat from the mutation variants found.
	[1] = function(data)
		if type(data.Stats) ~= "table" then
			data.Stats = {}
		end
		local count = 0
		if type(data.MutationsFound) == "table" then
			for _ in data.MutationsFound do
				count += 1
			end
		end
		data.Stats.Mutated = count
	end,
}

local function isInt(value: any, min: number?): boolean
	return type(value) == "number" and value == value and value % 1 == 0 and value >= (min or 0) and value < 2 ^ 53
end

-- Turns whatever came out of the DataStore into a valid Data table. Unknown or broken entries
-- are dropped, except treasure with an unknown item id, which is parked in Orphans so a config
-- mistake can never delete someone's items.
function Schema.Sanitize(raw: any): Data
	local data = Schema.Defaults()
	if type(raw) ~= "table" then
		return data
	end

	if isInt(raw.Coins) then
		data.Coins = raw.Coins
	end
	if isInt(raw.Seq) then
		data.Seq = raw.Seq
	end

	if type(raw.Bag) == "table" then
		for key, stack in raw.Bag do
			if
				type(key) == "string"
				and type(stack) == "table"
				and type(stack.Id) == "string"
				and isInt(stack.Qty, 1)
			then
				local mut = if type(stack.Mut) == "string" then stack.Mut else nil
				local known = Config.Items.ById[stack.Id] ~= nil
					and (mut == nil or Config.Economy.Mutations.ById[mut] ~= nil)
				if known then
					data.Bag[key] = {
						Id = stack.Id,
						Mut = mut,
						Qty = stack.Qty,
						Locked = stack.Locked == true,
						Seq = if isInt(stack.Seq) then stack.Seq else 0,
					}
				else
					table.insert(data.Orphans, stack)
				end
			end
		end
	end
	if type(raw.Orphans) == "table" then
		for _, orphan in raw.Orphans do
			table.insert(data.Orphans, orphan)
		end
	end

	if type(raw.Upgrades) == "table" then
		for id in data.Upgrades do
			local level = raw.Upgrades[id]
			if isInt(level) then
				data.Upgrades[id] = math.min(level, Config.UpgradeMaxLevel(id))
			end
		end
	end

	if type(raw.Dice) == "table" then
		if type(raw.Dice.Owned) == "table" then
			for id, owned in raw.Dice.Owned do
				if Config.Dice.ById[id] and owned == true then
					data.Dice.Owned[id] = true
				end
			end
		end
		if type(raw.Dice.Equipped) == "table" then
			local equipped, seen = {}, {}
			for _, id in raw.Dice.Equipped do
				if
					type(id) == "string"
					and data.Dice.Owned[id]
					and not seen[id]
					and #equipped < Config.Economy.MaxDice
				then
					seen[id] = true
					table.insert(equipped, id)
				end
			end
			if #equipped > 0 then
				data.Dice.Equipped = equipped
			end
		end
	end

	if type(raw.Regions) == "table" then
		for id, unlocked in raw.Regions do
			if Config.Regions.ById[id] and unlocked == true then
				data.Regions[id] = true
			end
		end
	end

	if type(raw.Discovered) == "table" then
		for id, entry in raw.Discovered do
			if type(id) == "string" and type(entry) == "table" and isInt(entry.N) then
				data.Discovered[id] = { N = entry.N, T = if isInt(entry.T) then entry.T else 0 }
			end
		end
	end
	if type(raw.MutationsFound) == "table" then
		for key, found in raw.MutationsFound do
			if type(key) == "string" and found == true then
				data.MutationsFound[key] = true
			end
		end
	end

	if type(raw.Stats) == "table" then
		for name in data.Stats do
			if isInt(raw.Stats[name]) then
				data.Stats[name] = raw.Stats[name]
			end
		end
	end

	if type(raw.Tutorial) == "table" then
		data.Tutorial.Done = raw.Tutorial.Done == true
		if isInt(raw.Tutorial.Step, 1) then
			data.Tutorial.Step = raw.Tutorial.Step
		end
	end

	if type(raw.Settings) == "table" then
		for name, default in Schema.SettingDefaults do
			local value = raw.Settings[name]
			if type(value) == type(default) then
				data.Settings[name] = if type(value) == "number" then math.clamp(value, 0, 1) else value
			end
		end
	end

	-- v2 fields ---------------------------------------------------------------------------
	if type(raw.Orders) == "table" then
		if isInt(raw.Orders.NextId) then
			data.Orders.NextId = raw.Orders.NextId
		end
		if isInt(raw.Orders.SkipAt) then
			data.Orders.SkipAt = raw.Orders.SkipAt
		end
		if type(raw.Orders.Slots) == "table" then
			for i = 1, Config.Economy.Orders.Slots do
				local slot = raw.Orders.Slots[i]
				if type(slot) == "table" and isInt(slot.ReadyAt) then
					local valid = slot.ItemId == nil
						or (
							Config.Items.ById[slot.ItemId] ~= nil
							and isInt(slot.Qty, 1)
							and isInt(slot.Reward, 1)
							and isInt(slot.Id)
							and (slot.Mut == nil or Config.Economy.Mutations.ById[slot.Mut] ~= nil)
						)
					if valid then
						data.Orders.Slots[i] = {
							Id = slot.Id,
							ItemId = slot.ItemId,
							Mut = slot.Mut,
							Qty = slot.Qty,
							Reward = slot.Reward,
							Giver = if type(slot.Giver) == "string" then slot.Giver else nil,
							ReadyAt = slot.ReadyAt,
						}
					end
				end
			end
		end
	end
	if type(raw.Daily) == "table" and isInt(raw.Daily.Day) and type(raw.Daily.List) == "table" then
		local list = {}
		for _, entry in raw.Daily.List do
			if
				type(entry) == "table"
				and type(entry.Id) == "string"
				and isInt(entry.Goal, 1)
				and isInt(entry.Reward)
				and isInt(entry.Progress)
			then
				table.insert(list, {
					Id = entry.Id,
					Stat = if type(entry.Stat) == "string" then entry.Stat else "Rolls",
					Goal = entry.Goal,
					Reward = entry.Reward,
					Progress = entry.Progress,
					Claimed = entry.Claimed == true,
				})
			end
		end
		data.Daily = { Day = raw.Daily.Day, List = list }
	end
	local milestoneIds = {}
	for _, m in Config.Economy.Milestones do
		milestoneIds[m.Id] = true
	end
	if type(raw.Milestones) == "table" then
		for id, claimed in raw.Milestones do
			if milestoneIds[id] and claimed == true then
				data.Milestones[id] = true
			end
		end
	end
	if type(raw.Collection) == "table" then
		for id, claimed in raw.Collection do
			if Config.Regions.ById[id] and claimed == true then
				data.Collection[id] = true
			end
		end
	end
	if type(raw.Cosmetics) == "table" then
		local cosmetics = raw.Cosmetics
		for _, kind in { "Auras", "Trays" } do
			local catalog = Config.Crafting[kind]
			if type(cosmetics[kind]) == "table" then
				for id, owned in cosmetics[kind] do
					if catalog[id] and owned == true then
						data.Cosmetics[kind][id] = true
					end
				end
			end
		end
		if type(cosmetics.Aura) == "string" and data.Cosmetics.Auras[cosmetics.Aura] then
			data.Cosmetics.Aura = cosmetics.Aura
		end
		if type(cosmetics.Tray) == "string" and data.Cosmetics.Trays[cosmetics.Tray] then
			data.Cosmetics.Tray = cosmetics.Tray
		end
	end

	return data
end

-- Loads a raw saved table of any known version. Returns nil + reason if the save is from a
-- NEWER version than this server understands (so an old server never overwrites it).
function Schema.Load(raw: any): (Data?, string?)
	if raw == nil then
		return Schema.Defaults(), nil
	end
	if type(raw) ~= "table" then
		return nil, "corrupt save"
	end
	local version = if isInt(raw.Version, 1) then raw.Version else 1
	if version > Schema.Version then
		return nil, "save is from a newer game version"
	end
	while version < Schema.Version do
		local migrate = Migrations[version]
		if migrate then
			migrate(raw)
		end
		version += 1
		raw.Version = version
	end
	return Schema.Sanitize(raw), nil
end

return Schema

-- All game configuration in one place. Everything here is plain data shared by server and client.
-- Edit the individual modules (Items, Dice, Regions, Economy, ...) to tune the game.

local Game = require(script.Game)

local Config = {
	Game = Game,
	Rarities = require(script.Rarities),
	Items = require(script.Items),
	Dice = require(script.Dice),
	Regions = require(script.Regions),
	Economy = require(script.Economy),
	Sounds = require(script.Sounds),
}

-- Content (dice, regions, upgrades) tagged with a Stage above Game.Stage is not live yet.
function Config.IsLive(def: { [string]: any }?): boolean
	return def ~= nil and (def.Stage or 1) <= Game.Stage
end

-- Level value of an upgrade (level 0 = base).
function Config.UpgradeValue(upgradeId: string, level: number): any
	local upgrade = Config.Economy.Upgrades.ById[upgradeId]
	local entry = upgrade.Levels[math.clamp(level, 0, #upgrade.Levels - 1) + 1]
	return entry.Value
end

function Config.UpgradeMaxLevel(upgradeId: string): number
	return #Config.Economy.Upgrades.ById[upgradeId].Levels - 1
end

-- Items of a region, optionally only one rarity. Special collectibles are included.
function Config.ItemsIn(regionId: string, rarity: string?): { { [string]: any } }
	local result = {}
	for _, item in Config.Items.List do
		if item.Region == regionId and (rarity == nil or item.Rarity == rarity) then
			table.insert(result, item)
		end
	end
	return result
end

-- Sell value of one item with an optional mutation, before sell bonuses.
function Config.ItemValue(itemId: string, mutation: string?): number
	local item = Config.Items.ById[itemId]
	if not item then
		return 0
	end
	local mult = 1
	if mutation then
		local def = Config.Economy.Mutations.ById[mutation]
		mult = if def then def.Multiplier else 1
	end
	return math.floor(item.Value * mult)
end

return Config

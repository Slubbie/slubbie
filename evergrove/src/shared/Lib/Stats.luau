-- Derived player numbers from a profile: skill levels, estate level, energy
-- cap and the sum of every effect (skill tree ranks, per-level passives, NPC
-- perks and active buffs). Pure functions over profile data, so the server
-- uses them for rules and the client for display.

local Config = script.Parent.Parent.Config
local Skills = require(Config.Skills)
local Land = require(Config.Land)
local Registry = require(script.Parent.Registry)

local Stats = {}

-- Level for an amount of XP in one skill.
function Stats.LevelFor(xp: number): (number, number, number)
	local level = 1
	local remaining = xp
	while level < Skills.MaxLevel do
		local need = Skills.XPForNext(level)
		if remaining < need then
			return level, remaining, need
		end
		remaining -= need
		level += 1
	end
	return Skills.MaxLevel, 0, 0
end

function Stats.SkillLevel(profile: any, skillId: string): number
	local entry = profile.Skills and profile.Skills[skillId]
	if not entry then
		return 1
	end
	return (Stats.LevelFor(entry.XP or 0))
end

function Stats.TotalLevels(profile: any): number
	local total = 0
	for _, skill in Skills.List do
		total += Stats.SkillLevel(profile, skill.Id)
	end
	return total
end

function Stats.EstateLevel(profile: any): number
	return 1 + math.floor((Stats.TotalLevels(profile) - #Skills.List) / Skills.EstateDivisor)
end

-- Skill points: one per level above 1, minus what's spent.
function Stats.PointsAvailable(profile: any, skillId: string): number
	local entry = profile.Skills and profile.Skills[skillId]
	local level = Stats.SkillLevel(profile, skillId)
	local spent = 0
	local nodes = Registry.SkillNodes[skillId]
	for nodeId, rank in (entry and entry.Nodes) or {} do
		local node = nodes and nodes[nodeId]
		if node then
			spent += node.Cost * rank
		end
	end
	return (level - 1) - spent
end

-- Sum of an effect key across skills, passives, perks and buffs.
function Stats.Effect(profile: any, key: string, now: number?): number
	local total = 0
	for _, skill in Skills.List do
		local entry = profile.Skills and profile.Skills[skill.Id]
		local level = Stats.SkillLevel(profile, skill.Id)
		if skill.Passive.Key == key then
			total += skill.Passive.PerLevel * (level - 1)
		end
		if entry and entry.Nodes then
			local nodes = Registry.SkillNodes[skill.Id]
			for nodeId, rank in entry.Nodes do
				local node = nodes[nodeId]
				if node and node.Effects[key] then
					total += node.Effects[key] * rank
				end
			end
		end
	end
	-- Active buffs (Buffs = { [id] = { Mult, Until } }): "Farming" buff counts as GrowthSpeed etc.
	local buffs = profile.Buffs
	if buffs and now then
		local map = {
			GrowthSpeed = "Farming",
			FishZone = "Fishing",
			OreChance = "Mining",
			ForageDouble = "Foraging",
			WalkSpeed = "Speed",
			MutationChance = "Luck",
			FriendshipGain = "Friendship",
			AnimalQuality = "Ranching",
			ArtifactChance = "Explore",
		}
		local buffId = map[key]
		for id, buff in buffs do
			if (id == buffId or id == "All") and type(buff) == "table" and (buff.Until or 0) > now then
				total += (buff.Mult or 1) - 1
			end
		end
	end
	return total
end

function Stats.MaxEnergy(profile: any): number
	local energy = Skills.Energy.Base + Stats.TotalLevels(profile) * Skills.Energy.PerTotalLevels
	energy += Stats.Effect(profile, "MaxEnergy")
	local house = Land.House[(profile.Farm and profile.Farm.House) or 1]
	if house then
		energy += house.Energy
	end
	return math.min(math.floor(energy), Skills.Energy.Max)
end

-- Hearts with an NPC (0-10).
function Stats.Hearts(profile: any, npcId: string): number
	local entry = profile.Friendship and profile.Friendship[npcId]
	local points = if entry then entry.Pts or 0 else 0
	return math.clamp(math.floor(points / 250), 0, 10)
end

-- NPC perk effects unlocked by hearts, e.g. discounts.
function Stats.Perks(profile: any): { any }
	local out = {}
	for _, npc in Registry.Npcs do
		local hearts = Stats.Hearts(profile, npc.Id)
		for _, perk in npc.Perks or {} do
			if hearts >= perk.Hearts then
				table.insert(out, perk.Effect)
			end
		end
	end
	return out
end

function Stats.ShopDiscount(profile: any, shopId: string, itemDef: any?): number
	local discount = Stats.Effect(profile, "ShopDiscount")
	for _, effect in Stats.Perks(profile) do
		local d = effect.Discount
		if d and d.Shop == shopId and (not d.Tag or (itemDef and itemDef.Tags[d.Tag])) then
			discount = math.max(discount, d.Amount)
		end
	end
	return math.clamp(discount, 0, 0.6)
end

-- Has this villager arrived in town for this player? (NPC Unlock conditions)
function Stats.NpcUnlocked(profile: any, npc: any): boolean
	local unlock = npc.Unlock
	if not unlock then
		return true
	end
	if profile.Unlocks and profile.Unlocks["Npc_" .. npc.Id] then
		return true
	end
	if unlock.Quest and profile.Quests and profile.Quests.Done[unlock.Quest] then
		return true
	end
	if unlock.Region and profile.Regions and profile.Regions[unlock.Region] then
		return true
	end
	if unlock.EstateLevel and Stats.EstateLevel(profile) >= unlock.EstateLevel then
		return true
	end
	return false
end

function Stats.HasPerk(profile: any, key: string): boolean
	for _, effect in Stats.Perks(profile) do
		if effect[key] then
			return true
		end
	end
	return false
end

return Stats

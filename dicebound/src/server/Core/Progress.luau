-- Stats, daily objectives, milestones and collection rewards. Pure logic over a Data table.
-- Every claim re-checks its condition and marks itself claimed in the same step, so a repeated
-- claim request can never pay twice.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Dicebound.Config)

local Progress = {}

local Economy = Config.Economy

-- Tiny deterministic RNG so a player's dailies for a given day are stable.
local function seeded(seed: number)
	local state = math.abs(math.floor(seed)) % 2147483646 + 1
	return function(): number
		state = (state * 48271) % 2147483647
		return (state - 1) / 2147483646
	end
end

function Progress.Day(now: number): number
	return now // 86400
end

-- Highest unlocked region order (1-5).
function Progress.BestRegionOrder(data): number
	local best = 1
	for id in data.Regions do
		local region = Config.Regions.ById[id]
		if region then
			best = math.max(best, region.Order)
		end
	end
	return best
end

-- A stat by name, including derived ones.
function Progress.StatValue(data, stat: string): number
	if stat == "Unique" then
		local n = 0
		for id in data.Discovered do
			if Config.Items.ById[id] then
				n += 1
			end
		end
		return n
	elseif stat == "Regions" then
		local n = 0
		for _ in data.Regions do
			n += 1
		end
		return n
	end
	return data.Stats[stat] or 0
end

-- Adds to a stat and to any of today's objectives that track it.
function Progress.Track(data, stat: string, amount: number)
	if amount <= 0 then
		return
	end
	if data.Stats[stat] ~= nil then
		data.Stats[stat] += amount
	end
	for _, entry in data.Daily.List do
		if entry.Stat == stat and not entry.Claimed then
			entry.Progress = math.min(entry.Goal, entry.Progress + amount)
		end
	end
end

-- Makes sure today's objectives exist. Missing days costs nothing: you just get a fresh set.
function Progress.EnsureDaily(data, now: number, userId: number): boolean
	local day = Progress.Day(now)
	if data.Daily.Day == day and #data.Daily.List > 0 then
		return false
	end
	local random = seeded(userId * 7919 + day * 104729)
	local slots = Config.UpgradeValue("DiceSlots", data.Upgrades.DiceSlots)
	local pool = {}
	for _, template in Economy.Dailies.Pool do
		if (template.NeedsDice or 1) <= slots then
			table.insert(pool, template)
		end
	end
	local scale = Economy.Dailies.RegionScale[Progress.BestRegionOrder(data)] or 1
	local list, usedStats = {}, {}
	while #list < Economy.Dailies.Count and #pool > 0 do
		local index = math.floor(random() * #pool) + 1
		local template = table.remove(pool, index)
		if not usedStats[template.Stat] then
			usedStats[template.Stat] = true
			table.insert(list, {
				Id = template.Id,
				Stat = template.Stat,
				Goal = if template.Scales then math.floor(template.Goal * scale) else template.Goal,
				Reward = math.floor(template.Reward * scale),
				Progress = 0,
				Claimed = false,
			})
		end
	end
	data.Daily = { Day = day, List = list }
	return true
end

function Progress.ClaimDaily(data, index: any): (number?, string?)
	local entry = type(index) == "number" and data.Daily.List[index]
	if not entry then
		return nil, "That objective doesn't exist."
	end
	if entry.Claimed then
		return nil, "Already claimed."
	end
	if entry.Progress < entry.Goal then
		return nil, "Not finished yet."
	end
	entry.Claimed = true
	data.Coins += entry.Reward
	data.Stats.CoinsEarned += entry.Reward
	return entry.Reward, nil
end

function Progress.ClaimMilestone(data, id: any): (number?, string?)
	local milestone
	for _, m in Economy.Milestones do
		if m.Id == id then
			milestone = m
		end
	end
	if not milestone then
		return nil, "That milestone doesn't exist."
	end
	if data.Milestones[milestone.Id] then
		return nil, "Already claimed."
	end
	if Progress.StatValue(data, milestone.Stat) < milestone.Goal then
		return nil, "Not reached yet."
	end
	data.Milestones[milestone.Id] = true
	data.Coins += milestone.Reward
	data.Stats.CoinsEarned += milestone.Reward
	return milestone.Reward, nil
end

-- (found, total) unique items discovered in a region.
function Progress.CollectionCount(data, regionId: string): (number, number)
	local found, total = 0, 0
	for _, item in Config.ItemsIn(regionId) do
		total += 1
		if data.Discovered[item.Id] then
			found += 1
		end
	end
	return found, total
end

function Progress.ClaimCollection(data, regionId: any): (number?, string?)
	local region = type(regionId) == "string" and Config.Regions.ById[regionId]
	if not region or not Config.IsLive(region) then
		return nil, "That region doesn't exist."
	end
	if data.Collection[region.Id] then
		return nil, "Already claimed."
	end
	local found, total = Progress.CollectionCount(data, region.Id)
	if found < total then
		return nil, string.format("Discover every item first (%d/%d).", found, total)
	end
	data.Collection[region.Id] = true
	data.Coins += region.CollectionReward
	data.Stats.CoinsEarned += region.CollectionReward
	return region.CollectionReward, nil
end

-- Number of rewards waiting to be claimed (for notification badges).
function Progress.Claimable(data): { Daily: number, Milestones: number, Collection: number }
	local result = { Daily = 0, Milestones = 0, Collection = 0 }
	for _, entry in data.Daily.List do
		if not entry.Claimed and entry.Progress >= entry.Goal then
			result.Daily += 1
		end
	end
	for _, m in Economy.Milestones do
		if not data.Milestones[m.Id] and Progress.StatValue(data, m.Stat) >= m.Goal then
			result.Milestones += 1
		end
	end
	for _, region in Config.Regions.List do
		if Config.IsLive(region) and not data.Collection[region.Id] then
			local found, total = Progress.CollectionCount(data, region.Id)
			if found == total then
				result.Collection += 1
			end
		end
	end
	return result
end

return Progress

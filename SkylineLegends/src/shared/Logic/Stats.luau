-- Statistic lookup for achievements, the journal and quests.
--
-- Counters (moves performed, races won...) live in profile.Stats. Everything
-- else is derived from the rest of the profile so it can never drift out of
-- sync. Discovery ids encode their kind as a prefix: cache_, letter_,
-- landmark_, secret_.

local Courses = require(script.Parent.Parent.Config.Courses)
local Mastery = require(script.Parent.Parent.Config.Mastery)
local Quests = require(script.Parent.Parent.Config.Quests)
local Leveling = require(script.Parent.Leveling)

local Stats = {}

local function count(t: { [any]: any }?): number
	local n = 0
	for _ in (t or {}) :: { [any]: any } do
		n += 1
	end
	return n
end

local function countPrefix(t: { [string]: any }?, prefix: string): number
	local n = 0
	for id in (t or {}) :: { [string]: any } do
		if string.sub(id, 1, #prefix) == prefix then
			n += 1
		end
	end
	return n
end

local function courseCount(profile: any, predicate: (any, any) -> boolean): number
	local n = 0
	for id, record in profile.Courses or {} do
		local course = Courses.ById[id]
		if course and predicate(course, record) then
			n += 1
		end
	end
	return n
end

local function masteryTiers(profile: any): { number }
	local tiers = {}
	local data = profile.Mastery or {}
	for _, category in Mastery.Categories do
		local points = (data.Points or {})[category.Id] or 0
		table.insert(tiers, Mastery.TierOf(category.Id, points, data.Challenges or {}))
	end
	return tiers
end

local function chaptersCompleted(profile: any): number
	local done = (profile.Quests or {}).Completed or {}
	local chapters: { [number]: boolean } = {}
	for _, quest in Quests.List do
		if quest.Type == "Main" and quest.Chapter then
			if chapters[quest.Chapter] == nil then
				chapters[quest.Chapter] = true
			end
			if not done[quest.Id] then
				chapters[quest.Chapter] = false
			end
		end
	end
	local n = 0
	for _, complete in chapters do
		if complete then
			n += 1
		end
	end
	return n
end

local derived: { [string]: (any, any) -> number } = {
	Level = function(profile)
		return (Leveling.FromXP(profile.XP or 0))
	end,
	CoursesCleared = function(profile)
		return courseCount(profile, function(course, record)
			return (course.Kind == "Course" or course.Kind == "Room") and (record.Completions or 0) > 0
		end)
	end,
	RoomsCleared = function(profile)
		return courseCount(profile, function(course, record)
			return course.Kind == "Room" and (record.Completions or 0) > 0
		end)
	end,
	Bronze = function(profile)
		return courseCount(profile, function(_, record)
			return (record.Medal or 0) >= 1
		end)
	end,
	Silver = function(profile)
		return courseCount(profile, function(_, record)
			return (record.Medal or 0) >= 2
		end)
	end,
	Gold = function(profile)
		return courseCount(profile, function(_, record)
			return (record.Medal or 0) >= 3
		end)
	end,
	Platinum = function(profile)
		return courseCount(profile, function(_, record)
			return (record.Medal or 0) >= 4
		end)
	end,
	NoFallCourses = function(profile)
		return courseCount(profile, function(_, record)
			return (record.Distinctions or {}).NoFall == true
		end)
	end,
	ShortcutCourses = function(profile)
		return courseCount(profile, function(_, record)
			return (record.Distinctions or {}).Shortcut == true
		end)
	end,
	AllTokenCourses = function(profile)
		return courseCount(profile, function(_, record)
			return (record.Distinctions or {}).AllTokens == true
		end)
	end,
	FlowCourses = function(profile)
		return courseCount(profile, function(_, record)
			return (record.Distinctions or {}).Flow == true
		end)
	end,
	Discoveries = function(profile)
		return count(profile.Discoveries)
	end,
	Caches = function(profile)
		return countPrefix(profile.Discoveries, "cache_")
	end,
	Letters = function(profile)
		return countPrefix(profile.Discoveries, "letter_")
	end,
	Landmarks = function(profile)
		return countPrefix(profile.Discoveries, "landmark_")
	end,
	DistrictsVisited = function(profile)
		return count((profile.Districts or {}).Visited)
	end,
	ItemsOwned = function(profile)
		return count(profile.Inventory)
	end,
	BestMasteryTier = function(profile)
		local best = 0
		for _, tier in masteryTiers(profile) do
			best = math.max(best, tier)
		end
		return best
	end,
	LowestMasteryTier = function(profile)
		local lowest = math.huge
		for _, tier in masteryTiers(profile) do
			lowest = math.min(lowest, tier)
		end
		return if lowest == math.huge then 0 else lowest
	end,
	MasteryTiers = function(profile)
		local total = 0
		for _, tier in masteryTiers(profile) do
			total += tier
		end
		return total
	end,
	ChaptersCompleted = chaptersCompleted,
	QuestsCompleted = function(profile)
		return count((profile.Quests or {}).Completed)
	end,
	TowerFloor = function(profile)
		return (profile.Tower or {}).Highest or 0
	end,
	EndlessBest = function(profile)
		return (profile.Endless or {}).Best or 0
	end,
	DistrictCachesComplete = function(profile, context)
		local totals = context and context.CacheTotals
		if not totals then
			return 0
		end
		local n = 0
		for district, total in totals do
			local found = countPrefix(profile.Discoveries, "cache_" .. string.lower(district) .. "_")
			if total > 0 and found >= total then
				n += 1
			end
		end
		return n
	end,
}

function Stats.Get(profile: any, key: string, context: any?): number
	local fn = derived[key]
	if fn then
		return fn(profile, context)
	end
	if string.sub(key, 1, 7) == "Secret_" then
		return if (profile.Discoveries or {})["secret_" .. string.lower(string.sub(key, 8))] then 1 else 0
	end
	return (profile.Stats or {})[key] or 0
end

function Stats.IsDerived(key: string): boolean
	return derived[key] ~= nil or string.sub(key, 1, 7) == "Secret_"
end

-- Mastery tier for every category, keyed by id.
function Stats.MasteryTiers(profile: any): { [string]: number }
	local result = {}
	local data = profile.Mastery or {}
	for _, category in Mastery.Categories do
		local points = (data.Points or {})[category.Id] or 0
		result[category.Id] = Mastery.TierOf(category.Id, points, data.Challenges or {})
	end
	return result
end

return Stats

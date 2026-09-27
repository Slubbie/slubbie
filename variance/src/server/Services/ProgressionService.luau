-- XP, Clearance Levels, Marks, titles, and the end-of-match progression flow.
--
-- matchCompleted() is called once per human subject when a match ends. It
-- records statistics, advances challenges, awards XP and Marks, then lets
-- achievements, lore and cosmetics catch up, and returns a summary for the
-- post-match screen. Also owns the "Profile" snapshot pushed to clients.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Variance.Config)
local Levels = require(ReplicatedStorage.Variance.Data.Levels)
local Challenges = require(ReplicatedStorage.Variance.Data.Challenges)
local Cosmetics = require(ReplicatedStorage.Variance.Data.Cosmetics)
local Difficulty = require(ReplicatedStorage.Variance.Core.AI.Difficulty)
local Modes = require(ReplicatedStorage.Variance.Core.Modes)

local ProgressionService = {}

local pendingPush: { [Player]: boolean } = {}

function ProgressionService:Init(services)
	self.Services = services
end

-- Full client-facing profile view (no locks, receipts or internal flags).
function ProgressionService:snapshot(player: Player)
	local profile = self.Services.DataService:get(player)
	if profile == nil then
		return nil
	end
	local d = profile.Data
	local level, into, need = Levels.fromXP(d.XP)
	local daily, weekly = {}, {}
	for i, entry in d.Challenges.Daily do
		daily[i] = {
			Id = entry.Id,
			Text = Challenges.text(entry),
			Tier = Challenges.ById[entry.Id] and Challenges.ById[entry.Id].Tier or "Easy",
			Goal = entry.Goal,
			Progress = entry.Progress,
			Done = entry.Done,
			Claimed = entry.Claimed,
		}
	end
	for i, entry in d.Challenges.Weekly do
		weekly[i] = {
			Id = entry.Id,
			Text = Challenges.text(entry),
			Tier = "Weekly",
			Goal = entry.Goal,
			Progress = entry.Progress,
			Done = entry.Done,
			Claimed = entry.Claimed,
		}
	end
	return {
		UserId = player.UserId,
		Guest = profile.Guest,
		Marks = d.Marks,
		XP = d.XP,
		Level = level,
		LevelInto = into,
		LevelNeed = need,
		Title = Levels.titleFor(level),
		Stats = d.Stats,
		EnvironmentWins = d.EnvironmentWins,
		AIWins = d.AIWins,
		SurrogateWins = d.SurrogateWins,
		InstrumentUse = d.InstrumentUse,
		Cosmetics = { Owned = d.Cosmetics.Owned, Equipped = d.Cosmetics.Equipped },
		Achievements = d.Achievements,
		Challenges = {
			Daily = daily,
			Weekly = weekly,
			DayEndsIn = 86400 - (os.time() % 86400),
			WeekEndsIn = (Challenges.week(os.time()) + 1) * 7 * 86400 - 3 * 86400 - os.time(),
		},
		Lore = { Unlocked = d.Lore.Unlocked, Read = d.Lore.Read },
		Tutorial = d.Tutorial,
		Ranked = self.Services.RankedService:info(player),
		History = d.History,
		Flags = { ProctorUnlocked = d.Flags.ProctorUnlocked },
		AdaptiveSkill = d.AdaptiveSkill,
	}
end

-- Schedules a (debounced) profile push to the client.
function ProgressionService:changed(player: Player)
	if pendingPush[player] then
		return
	end
	pendingPush[player] = true
	task.delay(0.25, function()
		pendingPush[player] = nil
		if player.Parent then
			local snap = self:snapshot(player)
			if snap then
				self.Services.NetworkService:push(player, "Profile", snap)
			end
		end
	end)
end

-- Adds XP and Marks, handling level-ups. Returns levels gained.
function ProgressionService:award(player: Player, xp: number, marks: number, reason: string?): number
	xp = math.max(0, math.floor(xp))
	marks = math.max(0, math.floor(marks))
	local before, after, bonus = 0, 0, 0
	self.Services.DataService:update(player, function(data)
		before = data.Level
		data.XP += xp
		after = Levels.fromXP(data.XP)
		for level = before + 1, after do
			bonus += Levels.marksForLevel(level)
		end
		data.Level = after
		data.Marks = math.min(Config.Economy.MaxMarks, data.Marks + marks + bonus)
	end)
	self.Services.DataService:noteEarnings(player, xp, marks + bonus)
	if after > before then
		self.Services.NetworkService:push(player, "LevelUp", {
			From = before,
			To = after,
			Title = Levels.titleFor(after),
			Marks = bonus,
			Unlocks = Cosmetics.forLevels(before + 1, after),
		})
		self.Services.CharacterService:refreshNameplate(player)
		self.Services.CosmeticService:syncGrants(player)
		self.Services.LoreService:sync(player)
		self.Services.AchievementService:evaluate(player, { Event = "Level" })
	end
	if reason and (xp > 0 or marks > 0) then
		self.Services.NetworkService:push(player, "Earned", { XP = xp, Marks = marks, Reason = reason })
	end
	self:changed(player)
	return after - before
end

-- End-of-match processing for one human subject.
--   outcome: Core/Report.outcome
--   info:    { ModeId, Solo, Difficulty, Personality, WithFriend, Ranked, Private,
--              Environment, OpponentUserIds, TournamentWon, EnduranceStage, Sandbox }
function ProgressionService:matchCompleted(player: Player, outcome, info)
	local profile = self.Services.DataService:get(player)
	if profile == nil then
		return nil
	end
	local mode = Modes.get(info.ModeId)
	local levelBefore = profile.Data.Level
	local summary = {
		XPLines = {},
		XP = 0,
		Marks = 0,
		LevelBefore = levelBefore,
		LevelAfter = levelBefore,
		Challenges = {},
		Achievements = {},
		Cosmetics = {},
		Lore = {},
	}
	local progression = mode ~= nil and mode.Progression and not info.Sandbox
	local ctx = { Event = "MatchEnd", Outcome = outcome, Match = info, Profile = profile.Data, Collector = summary }

	if progression then
		self.Services.StatisticsService:record(player, outcome, info)
		summary.Challenges = self.Services.ChallengeService:apply(player, ctx)
	end

	-- XP and Marks.
	local modeScale = mode and mode.XPScale or 1
	local difficultyScale, marksScale = 1, 1
	if info.Solo and info.Difficulty then
		local tier = info.Difficulty == "Adaptive" and Difficulty.adaptive(profile.Data.AdaptiveSkill)
			or Difficulty.get(info.Difficulty)
		difficultyScale = tier.XPScale
		marksScale = tier.MarksScale
	end
	if info.Private then
		modeScale *= Config.Economy.PrivateLobbyXPScale * (info.RepeatFactor or 1)
	end
	if info.Sandbox then
		modeScale = mode and mode.XPScale or 0.25
		marksScale = 0
	end
	local lines, xp = Levels.matchXP(outcome, modeScale, difficultyScale)
	local marks = Levels.matchMarks(outcome, modeScale, marksScale)
	if info.Sandbox then
		marks = 0
	end
	summary.XPLines = lines
	summary.XP = xp
	summary.Marks = marks
	self:award(player, xp, marks, nil)

	if progression or info.Sandbox then
		ctx.Profile = profile.Data
		self.Services.LoreService:sync(player, summary.Lore)
		self.Services.AchievementService:evaluate(player, ctx)
		self.Services.CosmeticService:syncGrants(player, summary.Cosmetics)
	end
	local level, into, need = Levels.fromXP(profile.Data.XP)
	summary.LevelAfter = level
	summary.LevelInto = into
	summary.LevelNeed = need
	summary.Title = Levels.titleFor(level)
	summary.MarksTotal = profile.Data.Marks
	self:changed(player)
	return summary
end

function ProgressionService:Start()
	local network = self.Services.NetworkService
	network:handle("Profile.Get", function(player)
		local profile = self.Services.DataService:waitFor(player, 20)
		if profile == nil then
			return false, "Profile not ready."
		end
		return true, self:snapshot(player)
	end)
	self.Services.DataService.Loaded:Connect(function(player)
		self:changed(player)
	end)
end

return ProgressionService

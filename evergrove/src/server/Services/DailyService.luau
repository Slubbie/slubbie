-- Daily login rewards: a 28-day cycle of useful rewards. Missing days never
-- resets your place in the cycle — it just continues next time (streaks are
-- tracked separately, for fun and an achievement).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Social = require(Shared.Config.Social)
local Net = require(Shared.Lib.Net)

local S = require(script.Parent)

local DailyService = {}

local function today(): number
	return math.floor(os.time() / 86400)
end

function DailyService.Available(profile: any): boolean
	return profile.Daily.Last ~= today()
end

local function claim(player: Player)
	local profile = S.Data.Get(player)
	if not profile then
		return false, "Not ready"
	end
	if not DailyService.Available(profile) then
		return false, "Come back tomorrow!"
	end
	local daily = profile.Daily
	local day = today()
	daily.Streak = if daily.Last == day - 1 then daily.Streak + 1 else 1
	daily.Best = math.max(daily.Best or 0, daily.Streak)
	daily.Last = day
	local index = (daily.Index % #Social.Daily) + 1
	daily.Index += 1
	S.Data.Changed(player, "Daily")
	S.Data.MaxStat(player, "DailyStreakBest", daily.Best)
	S.Economy.GrantReward(player, Social.Daily[index], "Daily reward")
	return true, { Day = index, Streak = daily.Streak }
end

function DailyService.Init()
	Net.Handle("DailyClaim", claim)
end

function DailyService.Start()
	S.Data.Loaded:Connect(function(player, profile)
		if DailyService.Available(profile) then
			S.Notify.FXPlayer(player, "DailyAvailable", { Index = (profile.Daily.Index % #Social.Daily) + 1 })
		end
	end)
end

return DailyService

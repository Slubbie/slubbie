-- Daily login rewards: claim once per UTC day. Claiming on consecutive days
-- builds a streak through a 7-day calendar (day 7 unlocks the Golden trail),
-- then loops. Missing a day restarts the streak at day 1.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local PlayerData = require(script.Parent.PlayerData)
local Progression = require(script.Parent.Progression)

local REWARDS = Config.DailyRewards

local DailyRewards = {}

local function today(): number
	return math.floor(os.time() / 86400)
end

-- Streak length if the player claimed today.
local function nextStreak(daily): number
	return if daily.Last == today() - 1 then daily.Streak + 1 else 1
end

local function status(player: Player)
	local data = PlayerData.Get(player)
	if not data then
		return nil
	end
	local daily = data.Daily
	local available = daily.Last < today()
	local streak = if available then nextStreak(daily) else daily.Streak
	return {
		Available = available,
		Streak = streak,
		-- Which calendar day (1-7) is today's (or was the last claimed) reward.
		Day = (streak - 1) % #REWARDS + 1,
		Rewards = REWARDS,
	}
end

local function claim(player: Player)
	local data = PlayerData.Get(player)
	if not data or data.Daily.Last >= today() then
		return false, nil
	end
	local streak = nextStreak(data.Daily)
	local reward = REWARDS[(streak - 1) % #REWARDS + 1]
	PlayerData.Update(player, function(d)
		d.Daily = { Last = today(), Streak = streak }
		d.Shards += reward.Shards or 0
		if reward.Trail then
			d.OwnedTrails[reward.Trail] = true
		end
	end)
	if reward.XP then
		Progression.AddXP(player, reward.XP)
	end
	Progression.Record(player, "LoginStreak", streak)
	task.spawn(PlayerData.Save, player)
	return true, reward
end

function DailyRewards.Start()
	Net.Function("GetDaily").OnServerInvoke = function(player)
		-- Data may still be loading when the client asks.
		for _ = 1, 40 do
			local result = status(player)
			if result then
				return result
			end
			task.wait(0.25)
		end
		return nil
	end
	Net.Function("ClaimDaily").OnServerInvoke = claim
end

return DailyRewards

-- Achievements: unlock from stat thresholds or special grants, pay rewards
-- (coins, items, titles, banners, frames, auras) and award Roblox badges.

local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Achievements = require(Shared.Config.Achievements)
local Net = require(Shared.Lib.Net)
local GameTime = require(Shared.Lib.GameTime)

local S = require(script.Parent)

local AchievementService = {}

local byStat: { [string]: { any } } = {}
for _, def in Achievements.List do
	if def.Stat then
		byStat[def.Stat] = byStat[def.Stat] or {}
		table.insert(byStat[def.Stat], def)
	end
end
local byId = {}
for _, def in Achievements.List do
	byId[def.Id] = def
end

function AchievementService.Grant(player: Player, id: string)
	local profile = S.Data.Get(player)
	local def = byId[id]
	if not profile or not def or profile.Achievements[id] then
		return
	end
	profile.Achievements[id] = GameTime.Now()
	S.Data.Changed(player, "Achievements", id)
	local reward = def.Reward or {}
	if reward.Title then
		profile.Titles[reward.Title] = true
		S.Data.Changed(player, "Titles")
	end
	for _, key in { "Banner", "Frame", "Effect" } do
		if reward[key] then
			profile.Cosmetics.Owned[key .. ":" .. reward[key]] = true
			S.Data.Changed(player, "Cosmetics")
		end
	end
	S.Economy.GrantReward(player, { Coins = reward.Coins, Items = reward.Items }, "Achievement")
	S.Notify.Achievement(player, id)
	if def.BadgeId and def.BadgeId > 0 then
		task.spawn(function()
			pcall(function()
				BadgeService:AwardBadge(player.UserId, def.BadgeId)
			end)
		end)
	end
end

function AchievementService.OnStat(player: Player, stat: string, value: number)
	local list = byStat[stat]
	if not list then
		return
	end
	local profile = S.Data.Get(player)
	if not profile then
		return
	end
	for _, def in list do
		if not profile.Achievements[def.Id] and value >= def.Goal then
			AchievementService.Grant(player, def.Id)
		end
	end
end

local function recheck(player: Player, profile: any)
	for stat, value in profile.Stats do
		if type(value) == "number" then
			AchievementService.OnStat(player, stat, value)
		end
	end
end

function AchievementService.Init()
	Net.Handle("AchievementsGet", function()
		return true -- progress is computed on the client from replicated Stats/Achievements
	end)
end

function AchievementService.Start()
	S.Data.Loaded:Connect(recheck)
end

return AchievementService

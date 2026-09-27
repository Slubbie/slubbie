-- Daily (3) and weekly (3) challenges: rotation, progress and claiming.
-- Rotation is deterministic per player and UTC day/week (Data/Challenges.luau),
-- so rejoining never rerolls. Rewards are XP and Marks; weekly claims can also
-- grant a Challenge-exclusive cosmetic.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Challenges = require(ReplicatedStorage.Variance.Data.Challenges)
local Cosmetics = require(ReplicatedStorage.Variance.Data.Cosmetics)

local ChallengeService = {}

local WEEKLY_COSMETIC_CHANCE = 0.35

function ChallengeService:Init(services)
	self.Services = services
end

-- Rolls new challenges if the day or week has changed.
function ChallengeService:refresh(player: Player)
	local now = os.time()
	local day = Challenges.day(now)
	local week = Challenges.week(now)
	local changed = false
	self.Services.DataService:update(player, function(data)
		local c = data.Challenges
		if c.Day ~= day then
			c.Day = day
			c.Daily = Challenges.dailyFor(player.UserId, day)
			changed = true
		end
		if c.Week ~= week then
			c.Week = week
			c.Weekly = Challenges.weeklyFor(player.UserId, week)
			changed = true
		end
	end)
	if changed then
		self.Services.ProgressionService:changed(player)
	end
end

-- Applies a finished match. Returns the entries that progressed (for the summary).
function ChallengeService:apply(player: Player, ctx)
	self:refresh(player)
	local progressed = {}
	local completed = {}
	self.Services.DataService:update(player, function(data)
		for _, list in { data.Challenges.Daily, data.Challenges.Weekly } do
			for _, entry in list do
				local before = entry.Progress
				local ok, done = pcall(Challenges.apply, entry, ctx)
				if not ok then
					warn("[VARIANCE/Challenges] " .. entry.Id .. ": " .. tostring(done))
				elseif entry.Progress ~= before then
					table.insert(progressed, {
						Text = Challenges.text(entry),
						Progress = entry.Progress,
						Goal = entry.Goal,
						Done = entry.Done,
					})
					if done then
						table.insert(completed, Challenges.text(entry))
					end
				end
			end
		end
	end)
	for _, text in completed do
		self.Services.NetworkService:notify(player, "CHALLENGE COMPLETE", text .. " - claim your reward.", "Good")
	end
	if #progressed > 0 then
		self.Services.ProgressionService:changed(player)
	end
	return progressed
end

function ChallengeService:claim(player: Player, period: string, index: number): (boolean, any)
	if period ~= "Daily" and period ~= "Weekly" then
		return false, "Unknown challenge."
	end
	if index ~= math.floor(index) or index < 1 or index > 3 then
		return false, "Unknown challenge."
	end
	local reward = nil
	local tier = nil
	self.Services.DataService:update(player, function(data)
		local entry = data.Challenges[period][index]
		if entry == nil or not entry.Done or entry.Claimed then
			return
		end
		entry.Claimed = true
		local def = Challenges.ById[entry.Id]
		tier = def and def.Tier or "Easy"
		reward = Challenges.Rewards[tier]
	end)
	if reward == nil then
		return false, "Nothing to claim."
	end
	self.Services.ProgressionService:award(player, reward.XP, reward.Marks, "Challenge")
	local cosmetic = nil
	if tier == "Weekly" and math.random() < WEEKLY_COSMETIC_CHANCE then
		local options = {}
		for _, id in Cosmetics.forSource("Challenge") do
			if not self.Services.CosmeticService:owns(player, id) then
				table.insert(options, id)
			end
		end
		if #options > 0 then
			cosmetic = options[math.random(1, #options)]
			self.Services.CosmeticService:grant(player, cosmetic, "Weekly challenge")
		end
	end
	return true, { XP = reward.XP, Marks = reward.Marks, Cosmetic = cosmetic }
end

function ChallengeService:Start()
	self.Services.NetworkService:handle("Challenges.Claim", function(player, period, index)
		return self:claim(player, period, index)
	end)
	self.Services.DataService.Loaded:Connect(function(player)
		self:refresh(player)
	end)
	-- Roll over at UTC midnight for everyone online.
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in game:GetService("Players"):GetPlayers() do
				if self.Services.DataService:get(player) then
					self:refresh(player)
				end
			end
		end
	end)
end

return ChallengeService

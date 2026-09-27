-- Evaluates achievements after matches and other milestones, grants their
-- Marks/XP rewards, and lets cosmetics and lore that depend on them unlock.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Achievements = require(ReplicatedStorage.Variance.Data.Achievements)

local AchievementService = {}

local evaluating: { [Player]: number } = {}

function AchievementService:Init(services)
	self.Services = services
end

-- ctx: { Event, Outcome?, Match?, Collector? }. Profile is filled in here.
function AchievementService:evaluate(player: Player, ctx)
	local profile = self.Services.DataService:get(player)
	if profile == nil then
		return {}
	end
	-- Rewards can cause level-ups that evaluate again; cap the recursion.
	local depth = (evaluating[player] or 0) + 1
	if depth > 3 then
		return {}
	end
	evaluating[player] = depth
	ctx.Profile = profile.Data
	ctx.Match = ctx.Match or {}
	local unlocked = {}
	for _, def in Achievements.List do
		if profile.Data.Achievements[def.Id] == nil then
			local ok, result = pcall(def.Check, ctx)
			if not ok then
				warn("[VARIANCE/Achievements] " .. def.Id .. " check failed: " .. tostring(result))
			elseif result then
				profile.Data.Achievements[def.Id] = os.time()
				profile.Dirty = true
				table.insert(unlocked, def)
			end
		end
	end
	for _, def in unlocked do
		self.Services.NetworkService:push(player, "Unlock", {
			Kind = "Achievement",
			Id = def.Id,
			Name = def.Name,
			Text = def.Description,
			Hidden = def.Hidden,
			Marks = def.Marks,
			XP = def.XP,
		})
		if ctx.Collector and ctx.Collector.Achievements then
			table.insert(ctx.Collector.Achievements, { Id = def.Id, Name = def.Name, Hidden = def.Hidden })
		end
	end
	if #unlocked > 0 then
		local xp, marks = 0, 0
		for _, def in unlocked do
			xp += def.XP
			marks += def.Marks
		end
		self.Services.ProgressionService:award(player, xp, marks, "Achievement")
		self.Services.CosmeticService:syncGrants(player, ctx.Collector and ctx.Collector.Cosmetics)
		self.Services.LoreService:sync(player, ctx.Collector and ctx.Collector.Lore)
	end
	evaluating[player] = depth - 1
	if evaluating[player] <= 0 then
		evaluating[player] = nil
	end
	return unlocked
end

function AchievementService:Start()
	self.Services.DataService.Loaded:Connect(function(player)
		-- Catch up on anything earned before an achievement existed.
		self:evaluate(player, { Event = "Login" })
	end)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		evaluating[player] = nil
	end)
end

return AchievementService

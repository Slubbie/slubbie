-- Skills: XP, levels, skill-tree ranks and respecs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Skills = require(Shared.Config.Skills)
local Recipes = require(Shared.Config.Recipes)
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local Stats = require(Shared.Lib.Stats)
local Signal = require(Shared.Lib.Signal)

local S = require(script.Parent)

local SkillService = {}
SkillService.LevelUp = Signal.new() -- (player, skillId, level)

-- Add XP to a skill. Handles level-ups and their rewards.
function SkillService.AddXP(player: Player, skillId: string, amount: number)
	local profile = S.Data.Get(player)
	local skill = Registry.Skills[skillId]
	if not profile or not skill or amount <= 0 then
		return
	end
	local entry = profile.Skills[skillId]
	if not entry then
		entry = { XP = 0, Nodes = {}, Respecs = 0 }
		profile.Skills[skillId] = entry
	end
	local before = Stats.SkillLevel(profile, skillId)
	local estateBefore = Stats.EstateLevel(profile)
	entry.XP += math.floor(amount + 0.5)
	S.Data.Changed(player, "Skills", skillId)
	local after = Stats.SkillLevel(profile, skillId)
	if after > before then
		for level = before + 1, after do
			local rewards = { Points = 1 }
			local title = skill.Titles[level]
			if title then
				profile.Titles[title] = true
				S.Data.Changed(player, "Titles")
				rewards.Title = title
			end
			local newRecipes = {}
			for _, recipe in Recipes.List do
				local u = recipe.Unlock
				if u.Skill and u.Skill[1] == skillId and u.Skill[2] == level then
					if S.Crafting.Learn(player, recipe.Id, false) then
						table.insert(newRecipes, recipe.Id)
					end
				end
			end
			rewards.Recipes = newRecipes
			for i, tierLevel in Skills.TierLevels do
				if tierLevel == level then
					rewards.Tier = i
				end
			end
			S.Notify.LevelUp(player, skillId, level, rewards)
			SkillService.LevelUp:Fire(player, skillId, level)
		end
		-- A level up tops your energy off a little.
		S.Player.RestoreEnergy(player, 20)
		S.Farm.InvalidatePlayerEffects(player)
		S.Quest.Progress(player, "Reach", skillId, 0)
		local estateAfter = Stats.EstateLevel(profile)
		if estateAfter > estateBefore then
			S.Notify.Banner(
				player,
				"Estate level " .. estateAfter,
				"New buildings and land are available.",
				"Estate",
				"🏡"
			)
			S.Player.UpdateNametag(player)
			S.Quest.Refresh(player)
		end
	end
end

local function unlock(player: Player, skillId: string, nodeId: string)
	local profile = S.Data.Get(player)
	local skill = Registry.Skills[skillId]
	local node = Registry.SkillNodes[skillId] and Registry.SkillNodes[skillId][nodeId]
	if not profile or not skill or not node then
		return false, "Unknown skill"
	end
	local entry = profile.Skills[skillId]
	local level = Stats.SkillLevel(profile, skillId)
	if level < Skills.TierLevels[node.Tier] then
		return false, string.format("Reach %s level %d first", skill.Name, Skills.TierLevels[node.Tier])
	end
	local rank = entry.Nodes[nodeId] or 0
	if rank >= node.MaxRank then
		return false, "Already maxed"
	end
	-- One branch per tier.
	if node.Branch then
		for _, other in skill.Tree do
			if
				other.Tier == node.Tier
				and other.Branch
				and other.Branch ~= node.Branch
				and (entry.Nodes[other.Id] or 0) > 0
			then
				return false, "You chose the other path for this tier (respec to change)"
			end
		end
	end
	if Stats.PointsAvailable(profile, skillId) < node.Cost then
		return false, "Not enough skill points"
	end
	entry.Nodes[nodeId] = rank + 1
	S.Data.Changed(player, "Skills", skillId)
	S.Farm.InvalidatePlayerEffects(player)
	return true, rank + 1
end

function SkillService.RespecCost(profile: any, skillId: string): number
	local entry = profile.Skills[skillId]
	local level = Stats.SkillLevel(profile, skillId)
	local cost = Skills.Respec.Base * level * Skills.Respec.Growth ^ (entry and entry.Respecs or 0)
	return math.min(math.floor(cost / 100) * 100, Skills.Respec.Max)
end

local function respec(player: Player, skillId: string)
	local profile = S.Data.Get(player)
	local entry = profile and profile.Skills[skillId]
	if not profile or not entry then
		return false, "Unknown skill"
	end
	if next(entry.Nodes) == nil then
		return false, "Nothing to reset"
	end
	local cost = SkillService.RespecCost(profile, skillId)
	if not S.Economy.Spend(player, cost, "Respec") then
		return false, "Respec costs " .. cost .. " coins"
	end
	entry.Nodes = {}
	entry.Respecs = (entry.Respecs or 0) + 1
	S.Data.Changed(player, "Skills", skillId)
	S.Farm.InvalidatePlayerEffects(player)
	return true
end

function SkillService.Init()
	Net.Handle("SkillUnlock", unlock)
	Net.Handle("SkillRespec", respec)
end

return SkillService

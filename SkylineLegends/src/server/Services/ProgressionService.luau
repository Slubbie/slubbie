-- Experience, levels, reputation ranks, skill points, the skill tree and
-- ability unlocks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Abilities = require(ReplicatedStorage.Shared.Config.Abilities)
local Leveling = require(ReplicatedStorage.Shared.Logic.Leveling)
local MoveStats = require(ReplicatedStorage.Shared.Logic.MoveStats)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Config.Progression)
local SkillTree = require(ReplicatedStorage.Shared.Config.SkillTree)

local DataService = require(script.Parent.Parent.Data.DataService)
local Events = require(script.Parent.Parent.Events)
local Notify = require(script.Parent.Notify)

local ProgressionService = {}

-- Set by EconomyService to avoid a require cycle.
ProgressionService.AddCredits = nil :: ((Player, number, string?) -> ())?
ProgressionService.AddPrestige = nil :: ((Player, number, string?) -> ())?
ProgressionService.GrantItem = nil :: ((Player, string, boolean?) -> ())?

function ProgressionService.Level(player: Player): number
	local profile = DataService.Get(player)
	if not profile then
		return 1
	end
	return (Leveling.FromXP(profile.XP))
end

-- Abilities lent for the duration of a mode (ranked kits, Spire floors, Dreamline lanes).
local temporary: { [Player]: { [string]: boolean } } = {}

function ProgressionService.Abilities(player: Player): { [string]: boolean }
	local set = Abilities.ForLevel(ProgressionService.Level(player))
	local extra = temporary[player]
	if extra then
		for id, on in extra do
			if on then
				set[id] = true
			end
		end
	end
	return set
end

-- Lend abilities (or clear the loan with nil). The client is told so its movement matches.
function ProgressionService.SetTemporary(player: Player, set: { [string]: boolean }?)
	temporary[player] = set :: any
	Net.Push(player, "Abilities.Temp", set)
end

function ProgressionService.HasAbility(player: Player, id: string): boolean
	return ProgressionService.Abilities(player)[id] == true
end

function ProgressionService.Perks(player: Player): { [string]: number }
	local profile = DataService.Get(player)
	local _, perks = MoveStats.Compute(if profile then profile.Skills else nil, true, nil)
	return perks
end

function ProgressionService.FreePoints(player: Player): number
	local profile = DataService.Get(player)
	if not profile then
		return 0
	end
	local level = ProgressionService.Level(player)
	return Leveling.SkillPoints(level) - SkillTree.SpentPoints(profile.Skills)
end

local function updateAttributes(player: Player)
	local level = ProgressionService.Level(player)
	local rank = Progression.RankFor(level)
	player:SetAttribute("Level", level)
	player:SetAttribute("Rank", rank.Name)
	player:SetAttribute("RankColor", rank.Color)
end

local function onLevelUp(player: Player, oldLevel: number, newLevel: number)
	local credits = 0
	for level = oldLevel + 1, newLevel do
		credits += Progression.LevelCredits(level)
	end
	if ProgressionService.AddCredits then
		ProgressionService.AddCredits(player, credits, "Level up")
	end
	local _, oldIndex = Progression.RankFor(oldLevel)
	local newRank, newIndex = Progression.RankFor(newLevel)
	Notify.Send(player, {
		Kind = "LevelUp",
		Title = ("Level %d"):format(newLevel),
		Text = ("+%d skill point%s"):format(
			Leveling.SkillPoints(newLevel) - Leveling.SkillPoints(oldLevel),
			if Leveling.SkillPoints(newLevel) - Leveling.SkillPoints(oldLevel) == 1 then "" else "s"
		),
		Credits = credits,
		Sound = "LevelUp",
	})
	if newIndex > oldIndex then
		Notify.Send(player, {
			Kind = "Rank",
			Title = newRank.Name,
			Text = newRank.Blurb,
			Color = newRank.Color,
			Sound = "Rank",
		})
	end
	for _, ability in Abilities.List do
		if ability.Level > oldLevel and ability.Level <= newLevel then
			Notify.Send(player, {
				Kind = "Ability",
				Title = ability.Name .. " unlocked",
				Text = (if ability.Gear then ability.Gear .. ": " else "") .. ability.Summary,
				Icon = ability.Icon,
				Sound = "Unlock",
			})
		end
	end
	updateAttributes(player)
	DataService.Push(player, "Skills")
	Events.LevelUp:Fire(player, newLevel, oldLevel)
	Events.StatChanged:Fire(player, "Level")
end

-- Add experience (XP bonus perks apply). Returns the amount actually added.
function ProgressionService.AddXP(player: Player, amount: number, _reason: string?): number
	local profile = DataService.Get(player)
	if not profile or amount <= 0 then
		return 0
	end
	local bonus = ProgressionService.Perks(player).XPBonus or 0
	local gained = math.floor(amount * (1 + bonus) + 0.5)
	local oldLevel = (Leveling.FromXP(profile.XP))
	profile.XP += gained
	local newLevel = (Leveling.FromXP(profile.XP))
	DataService.Push(player, "XP")
	if newLevel > oldLevel then
		onLevelUp(player, oldLevel, newLevel)
	end
	return gained
end

-- Give a reward bundle: { XP, Credits, Prestige, Items }.
function ProgressionService.Grant(player: Player, rewards: { [string]: any }, reason: string?, silent: boolean?)
	local xp = 0
	if rewards.XP and rewards.XP > 0 then
		xp = ProgressionService.AddXP(player, rewards.XP, reason)
	end
	if rewards.Credits and rewards.Credits > 0 and ProgressionService.AddCredits then
		ProgressionService.AddCredits(player, rewards.Credits, reason)
	end
	if rewards.Prestige and rewards.Prestige > 0 and ProgressionService.AddPrestige then
		ProgressionService.AddPrestige(player, rewards.Prestige, reason)
	end
	for _, itemId in rewards.Items or {} do
		if ProgressionService.GrantItem then
			ProgressionService.GrantItem(player, itemId, false)
		end
	end
	if not silent and reason then
		Notify.Send(player, {
			Kind = "Reward",
			Title = reason,
			XP = xp,
			Credits = rewards.Credits,
			Prestige = rewards.Prestige,
		})
	end
end

function ProgressionService.Start()
	DataService.Loaded:Connect(function(player)
		updateAttributes(player)
	end)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		temporary[player] = nil
	end)

	Net.Handle("Skill.Unlock", function(player, nodeId)
		local profile = DataService.Get(player)
		if not profile or type(nodeId) ~= "string" then
			return false, "Not ready"
		end
		local ok, reason = SkillTree.CanUnlock(profile.Skills, ProgressionService.FreePoints(player), nodeId)
		if not ok then
			return false, reason
		end
		profile.Skills[nodeId] = (profile.Skills[nodeId] or 0) + 1
		DataService.Push(player, "Skills")
		return true, nil
	end)

	Net.Handle("Skill.Respec", function(player)
		local profile = DataService.Get(player)
		if not profile then
			return false, "Not ready"
		end
		if next(profile.Skills) == nil then
			return false, "Nothing to refund"
		end
		if profile.Credits < SkillTree.RespecCost then
			return false, ("Needs %d credits"):format(SkillTree.RespecCost)
		end
		profile.Credits -= SkillTree.RespecCost
		profile.Skills = {}
		DataService.Push(player, "Credits")
		DataService.Push(player, "Skills")
		return true, nil
	end)

end

return ProgressionService

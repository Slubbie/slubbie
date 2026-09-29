-- Human-readable text for game data shown in several screens: quest
-- objectives and their progress, reward bundles, requirements, item
-- counts in the bag. Pure functions over config + the replicated profile.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Registry = require(Shared.Lib.Registry)
local Stats = require(Shared.Lib.Stats)
local Format = require(Shared.Lib.Format)
local World = require(Shared.Config.World)

local Theme = require(script.Parent.Theme)

local Describe = {}

local travelNames: { [string]: string } = {}
for _, point in World.Travel do
	travelNames[point.Id] = point.Name
end

local function spec(target: string?): string
	if target == nil or target == "*" then
		return ""
	end
	return Registry.SpecName(target)
end

local function things(target: string?, fallback: string): string
	local name = spec(target)
	return if name == "" then fallback else name
end

local function npcName(id: string?): string?
	local npc = id and Registry.Npcs[id]
	return npc and npc.Name
end

local function qualityText(q: number?): string
	if not q or q <= 1 then
		return ""
	end
	local tier = Theme.QualityTier(q)
	return " (" .. tier.Glyph .. " " .. tier.Name .. "+)"
end

-- "Harvest 12 Carrots (★★ Silver+)"
function Describe.Objective(o: any): string
	if o.Text then
		return o.Text
	end
	local n = o.Count or 1
	local t = o.Type
	if t == "Till" then
		return "Till " .. Format.Plural(n, "tile")
	elseif t == "Plant" then
		return "Plant " .. n .. " " .. things(o.Target, "seeds")
	elseif t == "Water" then
		return "Water " .. Format.Plural(n, "crop")
	elseif t == "Harvest" then
		return "Harvest " .. n .. " " .. things(o.Target, "crops") .. qualityText(o.Quality)
	elseif t == "Sell" then
		return "Sell goods worth " .. Format.Coins(n)
	elseif t == "Earn" then
		return "Earn " .. Format.Coins(n)
	elseif t == "Ship" then
		return "Ship " .. n .. " " .. things(o.Target, "items") .. " in the bin"
	elseif t == "Craft" then
		return "Craft " .. n .. " " .. things(o.Target, "items")
	elseif t == "Process" then
		return "Make " .. n .. " " .. things(o.Target, "artisan goods")
	elseif t == "Cook" then
		return "Cook " .. n .. " " .. things(o.Target, "dishes")
	elseif t == "Catch" then
		return "Catch " .. n .. " " .. things(o.Target, "fish")
	elseif t == "Mine" then
		return "Mine " .. n .. " " .. things(o.Target, "rocks")
	elseif t == "Chop" then
		return "Chop " .. Format.Plural(n, "tree")
	elseif t == "Forage" then
		return "Forage " .. n .. " " .. things(o.Target, "wild finds")
	elseif t == "Bug" then
		return "Catch " .. n .. " " .. things(o.Target, "bugs")
	elseif t == "Dig" then
		return "Dig up " .. Format.Plural(n, "spot")
	elseif t == "Visit" then
		return "Visit "
			.. (
				if o.Target and o.Target ~= "*"
					then (
						travelNames[o.Target]
						or (Registry.Regions[o.Target] and Registry.Regions[o.Target].Name)
						or o.Target
					)
					else Format.Plural(n, "friend's farm", "friends' farms")
			)
	elseif t == "Talk" then
		local name = npcName(o.Target)
		return if name then "Talk to " .. name else "Chat with " .. Format.Plural(n, "villager")
	elseif t == "Gift" then
		local name = npcName(o.Target)
		return "Give " .. Format.Plural(n, "gift") .. (if name then " to " .. name else "")
	elseif t == "Pet" then
		return "Pet " .. Format.Plural(n, "animal")
	elseif t == "Collect" then
		return "Collect " .. n .. " " .. things(o.Target, "animal products")
	elseif t == "BuyAnimal" then
		local species = o.Target and Registry.Species[o.Target]
		return "Adopt " .. n .. " " .. (if species then species.Name else "animal" .. (if n > 1 then "s" else ""))
	elseif t == "Breed" then
		return "Breed " .. Format.Plural(n, "animal")
	elseif t == "SeedBreed" then
		return "Cross-breed " .. Format.Plural(n, "seed")
	elseif t == "Place" then
		return "Place " .. n .. " " .. things(o.Target, "decorations")
	elseif t == "BuyLand" then
		return "Buy " .. Format.Plural(n, "land parcel")
	elseif t == "Deliver" then
		return "Bring " .. n .. " " .. things(o.Target, "items") .. qualityText(o.Quality)
	elseif t == "Reach" then
		local npcId = string.match(o.Target or "", "^Hearts:(.+)$")
		if npcId then
			return "Reach " .. n .. " ❤ with " .. (npcName(npcId) or npcId)
		end
		local skill = o.Target and Registry.Skills[o.Target]
		return "Reach " .. (if skill then skill.Name else tostring(o.Target)) .. " level " .. n
	elseif t == "Discover" then
		return "Discover " .. Format.Plural(n, "new collection entry", "new collection entries")
	elseif t == "Donate" then
		return "Donate " .. Format.Plural(n, "item") .. " to the museum"
	elseif t == "Project" then
		local project = o.Target and Registry.Projects[o.Target]
		return "Complete the " .. (if project then project.Name else "town") .. " project"
	elseif t == "Festival" then
		return "Take part in " .. Format.Plural(n, "festival activity", "festival activities")
	elseif t == "Export" then
		return "Send " .. Format.Plural(n, "export crate")
	elseif t == "Upgrade" then
		local family = o.Target and Registry.ToolFamilies[o.Target]
		return "Upgrade your " .. (if family then family.Name else "tools")
	elseif t == "Travel" then
		return "Discover "
			.. (
				if o.Target and o.Target ~= "*"
					then (travelNames[o.Target] or o.Target)
					else Format.Plural(n, "signpost")
			)
	elseif t == "Secret" then
		local secret = o.Target and Registry.Secrets[o.Target]
		return if secret then "Uncover: " .. secret.Name else "Find " .. Format.Plural(n, "secret")
	elseif t == "Mutation" then
		local mutation = o.Target and o.Target ~= "*" and (Registry.Mutations[o.Target] or Registry.Combos[o.Target])
		return "Harvest "
			.. n
			.. " "
			.. (
				if mutation
					then mutation.Name .. " crop" .. (if n > 1 then "s" else "")
					else "mutated crop" .. (if n > 1 then "s" else "")
			)
	elseif t == "Daily" then
		return "Complete " .. Format.Plural(n, "daily request")
	end
	return t .. " ×" .. n
end

-- How many matching items the player carries (bag only).
function Describe.CountInBag(profile: any, target: string?, quality: number?): number
	local total = 0
	local slots = profile and profile.Inventory and profile.Inventory.Slots
	for _, stack in slots or {} do
		if Registry.Matches(stack.Id, target) and (stack.Q or 1) >= (quality or 1) then
			total += stack.N
		end
	end
	return total
end

-- Current / goal for an objective given its stored progress.
function Describe.Progress(profile: any, o: any, stored: number?): (number, number)
	local goal = o.Count or 1
	if o.Type == "Deliver" then
		return math.min(goal, Describe.CountInBag(profile, o.Target, o.Quality)), goal
	elseif o.Type == "Reach" then
		local npcId = string.match(o.Target or "", "^Hearts:(.+)$")
		if npcId then
			return math.min(goal, math.floor(Stats.Hearts(profile, npcId))), goal
		end
		return math.min(goal, Stats.SkillLevel(profile, o.Target)), goal
	end
	return math.min(goal, stored or 0), goal
end

-- Reward bundle → short lines ("🪙 1,000", "🌾 +120 Farming XP", "🥕 Carrot Seeds ×6").
function Describe.Rewards(rewards: any): { string }
	local out = {}
	if not rewards then
		return out
	end
	if rewards.Coins and rewards.Coins > 0 then
		table.insert(out, "🪙 " .. Format.Commas(rewards.Coins))
	end
	if rewards.Tokens and rewards.Tokens > 0 then
		table.insert(out, "🎟️ " .. rewards.Tokens .. " tokens")
	end
	for skillId, amount in rewards.XP or {} do
		local skill = Registry.Skills[skillId]
		table.insert(
			out,
			(if skill then skill.Icon .. " " else "")
				.. "+"
				.. amount
				.. " "
				.. (if skill then skill.Name else skillId)
				.. " XP"
		)
	end
	for _, entry in rewards.Items or {} do
		local item = Registry.Items[entry[1]]
		table.insert(out, (if item then item.Icon .. " " .. item.Name else entry[1]) .. " ×" .. (entry[2] or 1))
	end
	if rewards.Recipe then
		local item = Registry.Items[rewards.Recipe]
		table.insert(out, "📖 Recipe: " .. (if item then item.Name else rewards.Recipe))
	end
	if rewards.Title then
		table.insert(out, "🏷️ Title: " .. rewards.Title)
	end
	for npcId, points in rewards.Friendship or {} do
		table.insert(out, "❤ +" .. points .. " with " .. (npcName(npcId) or npcId))
	end
	if rewards.Unlock then
		table.insert(out, "🔓 Unlocks " .. (npcName(rewards.Unlock) or rewards.Unlock))
	end
	if rewards.Cosmetic then
		table.insert(out, "🎀 Cosmetic: " .. tostring(rewards.Cosmetic))
	end
	return out
end

-- Requirement table → lines, each with a met flag.
function Describe.Requires(profile: any, requires: any): { { Text: string, Met: boolean } }
	local out = {}
	if not requires then
		return out
	end
	if requires.Quest then
		local quest = Registry.Quests[requires.Quest]
		local done = profile and profile.Quests and profile.Quests.Done[requires.Quest] ~= nil
		table.insert(
			out,
			{ Text = 'Finish "' .. (if quest then quest.Name else requires.Quest) .. '"', Met = done == true }
		)
	end
	if requires.Hearts then
		local npcId, n = requires.Hearts[1], requires.Hearts[2]
		table.insert(out, {
			Text = n .. " ❤ with " .. (npcName(npcId) or npcId),
			Met = profile ~= nil and Stats.Hearts(profile, npcId) >= n,
		})
	end
	if requires.Estate then
		table.insert(out, {
			Text = "Estate level " .. requires.Estate,
			Met = profile ~= nil and Stats.EstateLevel(profile) >= requires.Estate,
		})
	end
	if requires.Skill then
		local skillId, n = requires.Skill[1], requires.Skill[2]
		local skill = Registry.Skills[skillId]
		table.insert(out, {
			Text = (if skill then skill.Name else skillId) .. " level " .. n,
			Met = profile ~= nil and Stats.SkillLevel(profile, skillId) >= n,
		})
	end
	if requires.Project then
		local project = Registry.Projects[requires.Project]
		table.insert(out, {
			Text = "Town project: " .. (if project then project.Name else requires.Project),
			Met = profile ~= nil
				and profile.Projects[requires.Project] ~= nil
				and profile.Projects[requires.Project].Done == true,
		})
	end
	if requires.Item then
		local item = Registry.Items[requires.Item]
		table.insert(out, {
			Text = "Carry " .. (if item then item.Name else requires.Item),
			Met = Describe.CountInBag(profile, requires.Item) > 0,
		})
	end
	return out
end

-- "Spring 12" style date for a quest/festival date pair.
function Describe.SeasonDay(seasonIndex: number, day: number): string
	local Seasons = require(Shared.Config.Seasons)
	local season = Seasons[seasonIndex]
	return (if season then season.Icon .. " " .. season.Name else "Season " .. seasonIndex) .. " " .. day
end

return Describe

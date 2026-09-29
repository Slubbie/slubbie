-- The evolving town: community-funded projects, secrets and lore.
--
-- Projects (Config/Land.Projects) are funded at the Town Hall with coins and
-- items, a little at a time. Progress is per player (your valley grows with
-- you): profile.Projects[id] = { Coins, Items = { [index] = n }, Done }.
-- Finished projects unlock regions, shops and village buildings; the client
-- shows scaffolding for buildings whose project you haven't finished.
--
-- Secrets (Config/Secrets) are hidden spots. The client reports when you step
-- into one; the server re-checks position, region and every condition
-- (items, time, weather, season, moon, quests, hearts, buffs) before paying out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local World = require(Shared.Config.World)
local Net = require(Shared.Lib.Net)
local Signal = require(Shared.Lib.Signal)
local Registry = require(Shared.Lib.Registry)
local Stats = require(Shared.Lib.Stats)
local GameTime = require(Shared.Lib.GameTime)

local S = require(script.Parent)

local HALL_RANGE = 45
local SECRET_SLACK = 6

local TownService = {}
TownService.ProjectDone = Signal.new() -- (player, projectId)
TownService.SecretFound = Signal.new() -- (player, secretId)

local hallPosition = Vector3.new(0, 0, -100)
for _, building in World.Buildings do
	if building.Id == "TownHall" then
		hallPosition = building.Position
	end
end

-- Projects ------------------------------------------------------------------------------------------------

local function state(profile: any, id: string): any
	local entry = profile.Projects[id]
	if not entry then
		entry = { Coins = 0, Items = {}, Done = false }
		profile.Projects[id] = entry
	end
	entry.Items = entry.Items or {}
	return entry
end

function TownService.IsDone(profile: any, id: string): boolean
	local entry = profile.Projects[id]
	return entry ~= nil and entry.Done == true
end

function TownService.Available(profile: any, project: any): (boolean, string?)
	if Stats.EstateLevel(profile) < (project.Estate or 1) then
		return false, "Requires Estate level " .. project.Estate
	end
	if project.Requires and not TownService.IsDone(profile, project.Requires) then
		local req = Registry.Projects[project.Requires]
		return false, "Finish " .. (if req then req.Name else project.Requires) .. " first"
	end
	return true
end

local function isComplete(project: any, entry: any): boolean
	if (entry.Coins or 0) < project.Cost then
		return false
	end
	for i, need in project.Items do
		if (entry.Items[tostring(i)] or 0) < need[2] then
			return false
		end
	end
	return true
end

local function complete(player: Player, profile: any, project: any)
	local entry = state(profile, project.Id)
	entry.Done = true
	entry.At = os.time()
	S.Data.Changed(player, "Projects")
	S.Data.AddStat(player, "ProjectsDone")
	S.Quest.Progress(player, "Project", project.Id, 1)
	S.Skill.AddXP(player, "Trading", 200)
	S.Notify.Banner(
		player,
		project.Icon .. " " .. project.Name .. " complete!",
		"Unlocked: " .. table.concat(project.Unlocks, ", "),
		"Town",
		project.Icon
	)
	S.NPC.RefreshVisibility(player)
	TownService.ProjectDone:Fire(player, project.Id)
end

-- Contribute to a project. `source` is "coins" or an inventory slot ref.
local function contribute(player: Player, projectId: string, source: string, count: number)
	local profile = S.Data.Get(player)
	local project = Registry.Projects[projectId]
	if not profile or not project then
		return false, "Unknown project"
	end
	if not S.Security.InReach(player, hallPosition, HALL_RANGE) then
		return false, "Contribute at the Town Hall"
	end
	local ok, why = TownService.Available(profile, project)
	if not ok then
		return false, why
	end
	local entry = state(profile, projectId)
	if entry.Done then
		return false, "Already finished"
	end
	if count < 1 then
		return false, "Nothing to give"
	end
	if source == "coins" then
		local need = project.Cost - (entry.Coins or 0)
		local amount = math.min(count, need)
		if amount <= 0 then
			return false, "The coin goal is already met"
		end
		if not S.Economy.Spend(player, amount, "Town project") then
			return false, "Not enough coins"
		end
		entry.Coins = (entry.Coins or 0) + amount
	else
		local stack = S.Inventory.Slot(player, source)
		if not stack then
			return false, "Pick an item"
		end
		-- Find the first unmet item requirement this stack satisfies.
		local index = nil
		for i, need in project.Items do
			local key = tostring(i)
			if (entry.Items[key] or 0) < need[2] and Registry.Matches(stack.Id, need[1]) then
				index = i
				break
			end
		end
		if not index then
			return false, "The project doesn't need that"
		end
		local key = tostring(index)
		local amount = math.min(count, stack.N, project.Items[index][2] - (entry.Items[key] or 0))
		local taken = S.Inventory.TakeFromSlot(player, source, amount)
		if not taken then
			return false, "Can't give that"
		end
		entry.Items[key] = (entry.Items[key] or 0) + taken.N
	end
	S.Data.Changed(player, "Projects")
	S.Data.AddStat(player, "ProjectContributions")
	if isComplete(project, entry) then
		complete(player, profile, project)
	end
	return true, entry
end

-- Secrets ---------------------------------------------------------------------------------------------------------

local function hasItem(player: Player, spec: string, n: number): boolean
	return S.Inventory.Count(player, spec) >= n
end

local function inHours(range: { number }, hour: number): boolean
	local from, to = range[1], range[2]
	if from <= to then
		return hour >= from and hour < to
	end
	return hour >= from or hour < to
end

-- Are this secret's conditions met right now? Returns ok, hint.
function TownService.SecretReady(player: Player, secret: any): (boolean, string?)
	local profile = S.Data.Get(player)
	if not profile then
		return false, nil
	end
	local needs = secret.Needs or {}
	local info = GameTime.Info()
	if needs.Item and not hasItem(player, needs.Item, 1) then
		return false, secret.Hint
	end
	for _, entry in needs.Items or {} do
		if not hasItem(player, entry[1], entry[2] or 1) then
			return false, secret.Hint
		end
	end
	for _, other in needs.Secrets or {} do
		if not profile.Secrets[other] then
			return false, secret.Hint
		end
	end
	if needs.Night and not info.IsNight then
		return false, secret.Hint
	end
	if needs.Hours and not inHours(needs.Hours, info.Hour) then
		return false, secret.Hint
	end
	if needs.FullMoon and not info.FullMoon then
		return false, secret.Hint
	end
	if needs.Season and needs.Season ~= info.SeasonId then
		return false, secret.Hint
	end
	if needs.Weather then
		local weather = S.Weather.InRegion(secret.Region)
		if not table.find(needs.Weather, weather) then
			return false, secret.Hint
		end
	end
	if needs.Quest and not (profile.Quests.Done[needs.Quest] or profile.Quests.Active[needs.Quest]) then
		return false, secret.Hint
	end
	if needs.Hearts and Stats.Hearts(profile, needs.Hearts[1]) < needs.Hearts[2] then
		return false, secret.Hint
	end
	if needs.Buff and not S.Player.HasBuff(player, needs.Buff) then
		return false, secret.Hint
	end
	return true, nil
end

function TownService.DiscoverLore(player: Player, loreId: string)
	local profile = S.Data.Get(player)
	local lore = Registry.Lore[loreId]
	if not profile or not lore or profile.Lore[loreId] then
		return
	end
	profile.Lore[loreId] = true
	S.Data.Changed(player, "Lore", loreId)
	S.Collection.Discover(player, "Lore", loreId)
	S.Notify.FXPlayer(player, "Lore", { Id = loreId, Title = lore.Title, Text = lore.Text })
end

local function trigger(player: Player, secretId: string)
	local profile = S.Data.Get(player)
	local secret = Registry.Secrets[secretId]
	if not profile or not secret then
		return false, nil
	end
	if profile.Secrets[secretId] then
		return false, "You've already found this"
	end
	if not S.Security.InReach(player, secret.Position, secret.Radius + SECRET_SLACK) then
		return false, nil
	end
	local ok, why = S.Player.CanAccess(player, secret.Region)
	if not ok then
		return false, why
	end
	local ready, hint = TownService.SecretReady(player, secret)
	if not ready then
		return false, hint
	end
	for _, entry in secret.Consume or {} do
		if not S.Inventory.Remove(player, entry[1], entry[2] or 1) then
			return false, secret.Hint
		end
	end
	profile.Secrets[secretId] = os.time()
	S.Data.Changed(player, "Secrets")
	local reward = secret.Reward or {}
	S.Economy.GrantReward(player, { Coins = reward.Coins, Items = reward.Items }, secret.Name)
	if reward.Lore then
		TownService.DiscoverLore(player, reward.Lore)
	end
	if reward.Unlock then
		profile.Unlocks["Region_" .. reward.Unlock] = true
		S.Data.Changed(player, "Unlocks")
		local region = Registry.Regions[reward.Unlock]
		if region then
			S.Notify.Toast(player, "🗺️ A new place opened up: " .. region.Name, "Success")
		end
	end
	if reward.Achievement then
		S.Achievement.Grant(player, reward.Achievement)
	end
	S.Data.AddStat(player, "SecretsFound")
	S.Quest.Progress(player, "Secret", secretId, 1)
	S.Skill.AddXP(player, "Exploration", 120)
	S.Notify.Banner(player, "Secret found: " .. secret.Name, secret.Hint, "Secret", "🔍")
	S.Notify.FX(secret.Position, "Secret", { Id = secretId, By = player.UserId }, 100)
	TownService.SecretFound:Fire(player, secretId)
	return true, secretId
end

-- Lifecycle -------------------------------------------------------------------------------------------------------

function TownService.Init()
	Net.Handle("TownContribute", contribute)
	Net.Handle("SecretTrigger", trigger)
end

function TownService.Start()
	-- Older saves: projects list may reference removed ids; keep them harmlessly.
	S.Data.Loaded:Connect(function(_player, profile)
		for id, entry in profile.Projects do
			if type(entry) ~= "table" then
				profile.Projects[id] = nil
			end
		end
	end)
end

return TownService

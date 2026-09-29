-- Developer tools. The client admin panel (F8) sends Net "Admin" commands;
-- only admins can use them: Studio always, live servers only for UserIds in
-- Config/Gameplay.Debug.Admins, the game's creator, or a group rank.
--
-- Every command is logged to the output and echoed to the admin's panel.
--
-- Commands (args table in brackets):
--   give {Id, N, Q?, M?}      coins {N}        tokens {N}       energy
--   weather {Id, Hours?}      hour {Hour}      season {Season}  skip {Hours}   clock (reset)
--   xp {Skill, N}             grow {Fraction}  mutate {Key, Mutation}         ripen
--   animal {Species}          machines (finish all jobs)        festival {Id}
--   quest {Id, Action=reset|complete}          unlock {Region}  tp {Region|Waypoint}
--   inspect {UserId}          log              save             help

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Gameplay = require(Shared.Config.Gameplay)
local Festivals = require(Shared.Config.Festivals)
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local ItemUtil = require(Shared.Lib.ItemUtil)
local GameTime = require(Shared.Lib.GameTime)
local Stats = require(Shared.Lib.Stats)

local S = require(script.Parent)

local AdminDebugService = {}

local adminCache: { [Player]: boolean } = {}

function AdminDebugService.IsAdmin(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	local cached = adminCache[player]
	if cached ~= nil then
		return cached
	end
	local allowed = table.find(Gameplay.Debug.Admins, player.UserId) ~= nil
	if not allowed and game.CreatorType == Enum.CreatorType.User and game.CreatorId == player.UserId then
		allowed = true
	end
	local group = Gameplay.Debug.Group
	if not allowed and group then
		local ok, groups = pcall(function()
			return GroupService:GetGroupsAsync(player.UserId)
		end)
		if ok and type(groups) == "table" then
			for _, g in groups do
				if g.Id == group.GroupId and (g.Rank or 0) >= group.MinRank then
					allowed = true
				end
			end
		end
	end
	adminCache[player] = allowed
	player:SetAttribute("Admin", allowed or nil)
	return allowed
end

local function log(player: Player, text: string)
	print("[Evergrove Admin] " .. player.Name .. ": " .. text)
	Net.Fire(player, "AdminLog", text)
end

local function num(value: any, default: number): number
	local n = tonumber(value)
	if n == nil or n ~= n then
		return default
	end
	return n
end

-- Commands -----------------------------------------------------------------------------------------------------

local commands: { [string]: (Player, any) -> string } = {}

commands.help = function()
	local names = {}
	for name in commands do
		table.insert(names, name)
	end
	table.sort(names)
	return "Commands: " .. table.concat(names, ", ")
end

commands.give = function(player, a)
	local id = tostring(a.Id or "")
	if not Registry.Items[id] then
		return "Unknown item " .. id
	end
	local stack = ItemUtil.New(
		id,
		math.clamp(math.floor(num(a.N, 1)), 1, 9999),
		if a.Q then math.clamp(num(a.Q, 1), 1, 6) else nil
	)
	if type(a.M) == "table" then
		local mutations = {}
		for _, m in a.M do
			if Registry.Mutations[m] or Registry.Combos[m] then
				table.insert(mutations, m)
			end
		end
		stack.M = if #mutations > 0 then mutations else nil
	end
	S.Inventory.Add(player, stack, { Source = "Admin" })
	return "Gave " .. stack.N .. "× " .. ItemUtil.DisplayName(stack)
end

commands.coins = function(player, a)
	local n = math.floor(num(a.N, 10000))
	if n >= 0 then
		S.Economy.AddCoins(player, n, "Admin")
	else
		S.Economy.Spend(player, -n, "Admin")
	end
	return "Coins " .. n
end

commands.tokens = function(player, a)
	S.Economy.AddTokens(player, math.floor(num(a.N, 100)))
	return "Tokens +" .. math.floor(num(a.N, 100))
end

commands.energy = function(player)
	S.Player.RestoreEnergy(player, 9999)
	return "Energy restored"
end

commands.weather = function(_player, a)
	local id = a.Id and tostring(a.Id)
	if id and not Registry.Weather[id] then
		return "Unknown weather " .. tostring(id)
	end
	S.Weather.Force(id, num(a.Hours, 6) * GameTime.HOUR)
	return "Weather → " .. tostring(id or "natural")
end

commands.hour = function(_player, a)
	S.Time.SetHour(num(a.Hour, 6))
	return "Hour → " .. num(a.Hour, 6)
end

commands.season = function(_player, a)
	S.Time.SetSeason(math.floor(num(a.Season, 1)))
	return "Season → " .. GameTime.Info().SeasonName
end

commands.skip = function(_player, a)
	S.Time.Skip(num(a.Hours, 1) * GameTime.HOUR)
	return "Skipped " .. num(a.Hours, 1) .. " hours"
end

commands.clock = function()
	S.Time.ResetToGlobal()
	return "Clock reset to the global calendar"
end

commands.xp = function(player, a)
	local skill = tostring(a.Skill or "Farming")
	if not Registry.Skills[skill] then
		return "Unknown skill " .. skill
	end
	S.Skill.AddXP(player, skill, math.floor(num(a.N, 1000)))
	return skill .. " +" .. math.floor(num(a.N, 1000)) .. " XP"
end

commands.grow = function(player, a)
	local n = S.Crop.GrowAll(player, math.clamp(num(a.Fraction, 1), 0, 1))
	return "Grew " .. n .. " crops"
end

commands.ripen = function(player)
	local n = S.Crop.GrowAll(player, 1)
	return "Ripened " .. n .. " crops"
end

commands.mutate = function(player, a)
	local ok = S.Crop.ForceMutation(player, tostring(a.Key or ""), tostring(a.Mutation or ""))
	return if ok then "Mutation applied" else "Couldn't mutate that tile"
end

commands.animal = function(player, a)
	local aid, why = S.Animal.Grant(player, tostring(a.Species or "chicken"))
	return if aid then "Granted animal " .. aid else ("Failed: " .. tostring(why))
end

commands.machines = function(player)
	local n = 0
	S.Machine.Each(player, function(uid, record)
		local state = record.M
		if state.S then
			state.S -= 86400
			state.B = nil
			n += 1
		end
		S.Machine.Advance(player, uid)
		S.Machine.Publish(player, uid)
	end)
	return "Finished jobs in " .. n .. " machines"
end

commands.festival = function(_player, a)
	for _, def in Festivals.List do
		if def.Id == a.Id then
			S.Time.SetSeason(def.Season)
			S.Time.Skip((def.Day - 1) * GameTime.DAY)
			S.Time.SetHour(def.Hours[1] + 0.5)
			return "Jumped to " .. def.Name
		end
	end
	return "Unknown festival"
end

commands.quest = function(player, a)
	local profile = S.Data.Get(player)
	local id = tostring(a.Id or "")
	if not profile or not Registry.Quests[id] then
		return "Unknown quest"
	end
	if a.Action == "complete" then
		profile.Quests.Active[id] = nil
		profile.Quests.Done[id] = os.time()
	else
		profile.Quests.Active[id] = nil
		profile.Quests.Done[id] = nil
	end
	S.Data.Changed(player, "Quests")
	S.Quest.Refresh(player)
	return "Quest " .. id .. " " .. (a.Action or "reset")
end

commands.unlock = function(player, a)
	local profile = S.Data.Get(player)
	local id = tostring(a.Region or "")
	if not profile or not Registry.Regions[id] then
		return "Unknown region"
	end
	profile.Unlocks["Region_" .. id] = true
	S.Data.Changed(player, "Unlocks")
	return "Unlocked " .. id
end

commands.tp = function(player, a)
	local target = tostring(a.Region or a.Waypoint or "")
	local region = Registry.Regions[target]
	local position = if region then region.Center else S.World.Waypoint(target)
	if not position then
		return "Unknown place"
	end
	local ground = S.World.GroundAt(position, 300) or position
	S.Player.Teleport(player, CFrame.new(ground + Vector3.new(0, 4, 0)))
	return "Teleported to " .. target
end

commands.inspect = function(_player, a)
	local target = Players:GetPlayerByUserId(math.floor(num(a.UserId, 0)))
	local profile = target and S.Data.Get(target)
	if not target or not profile then
		return "Player not found"
	end
	local placed, animals, tiles = 0, 0, 0
	for _ in profile.Farm.Placed do
		placed += 1
	end
	for _ in profile.Farm.Animals do
		animals += 1
	end
	for _ in profile.Farm.Tiles do
		tiles += 1
	end
	return string.format(
		"%s: %s coins, Estate %d, %d tiles, %d placed, %d animals, schema v%d, read-only=%s",
		target.Name,
		tostring(profile.Coins),
		Stats.EstateLevel(profile),
		tiles,
		placed,
		animals,
		profile.Version or 0,
		tostring(S.Data.IsReadOnly(target))
	)
end

commands.log = function()
	local lines = S.Security.Log()
	local last = {}
	for i = math.max(1, #lines - 20), #lines do
		table.insert(last, lines[i])
	end
	return if #last > 0 then table.concat(last, "\n") else "No security events"
end

commands.save = function(player)
	return if S.Data.SaveNow(player) then "Saved" else "Save failed (see output)"
end

-- Lifecycle ---------------------------------------------------------------------------------------------------------

function AdminDebugService.Init()
	Net.Handle("Admin", function(player, command, args)
		if not AdminDebugService.IsAdmin(player) then
			S.Security.Flag(player, "Admin command without permission", 5)
			return false, "Not allowed"
		end
		local fn = commands[command]
		if not fn then
			return false, "Unknown command (try help)"
		end
		local ok, result = pcall(fn, player, if type(args) == "table" then args else {})
		local text = if ok then tostring(result) else ("Error: " .. tostring(result))
		log(player, command .. " → " .. text)
		return ok, text
	end)
end

function AdminDebugService.Start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(AdminDebugService.IsAdmin, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(AdminDebugService.IsAdmin, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		adminCache[player] = nil
	end)
end

return AdminDebugService

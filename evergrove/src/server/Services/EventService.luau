-- Festivals and competitions (Config/Festivals).
--
-- A festival runs on its calendar day between its Hours on every server at
-- once (the calendar is global). While it runs:
--   * the village is decorated (ReplicatedStorage attributes Festival/FestivalKey
--     tell clients which theme to show), NPCs gather at the stage, the
--     soundtrack switches and the festival's weather is forced
--   * Scavenger collectibles appear around the village; each player finds
--     their own copies
--   * Contests take one entry per player, scored by Lib/ContestMath with the
--     breakdown shown to the player; Derby records your biggest catch; Race
--     times checkpoint runs (validated for plausible speed)
--   * challenges pay tokens; the token shop opens
-- Leaderboards are cross-server (MemoryStore sorted maps, local fallback).
-- When the festival ends each server posts prizes for the top three by mail,
-- guarded so a winner is only paid once across servers.
--
-- profile.Festival = { Key, Entries, Found, Ch, Done, Bought, Best, Attended }

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Festivals = require(Shared.Config.Festivals)
local Net = require(Shared.Lib.Net)
local Signal = require(Shared.Lib.Signal)
local Registry = require(Shared.Lib.Registry)
local ItemUtil = require(Shared.Lib.ItemUtil)
local GameTime = require(Shared.Lib.GameTime)
local RNG = require(Shared.Lib.RNG)
local ContestMath = require(Shared.Lib.ContestMath)
local Format = require(Shared.Lib.Format)

local S = require(script.Parent)

local TICK = 5
local BOARD_TTL = 3 * 86400
local RACE_CHECKPOINT_RANGE = 22
local RACE_MAX_SPEED = 75 -- studs/second (a fast horse with a speed potion)
local ATTEND_TOKENS = 10
local PLACES = { "First", "Second", "Third" }

local EventService = {}
EventService.Started = Signal.new() -- (def, key)
EventService.Ended = Signal.new() -- (def, key)

type Active = { Def: any, Key: string, Folder: Folder, Ends: number }
local active: Active? = nil
local races: { [Player]: { Activity: string, Start: number, Next: number, Last: Vector3 } } = {}

-- Calendar ------------------------------------------------------------------------------------------------

local function festivalAt(t: number): (any?, string?)
	local info = GameTime.Info(t)
	for _, def in Festivals.List do
		if
			info.Season == def.Season
			and info.DayOfSeason == def.Day
			and info.Hour >= def.Hours[1]
			and info.Hour < def.Hours[2]
		then
			return def, def.Id .. "_" .. info.Day
		end
	end
	return nil, nil
end

function EventService.Active(): any?
	return if active then active.Def else nil
end

function EventService.ActiveKey(): string?
	return if active then active.Key else nil
end

-- Next festival from now (for the calendar UI and "coming up" banners).
function EventService.Next(): (any?, number?)
	local info = GameTime.Info()
	local best, bestDays = nil, math.huge
	for _, def in Festivals.List do
		local dayOfYear = (def.Season - 1) * GameTime.SEASON_DAYS + def.Day - 1
		local today = (info.Season - 1) * GameTime.SEASON_DAYS + info.DayOfSeason - 1
		local days = (dayOfYear - today) % GameTime.YEAR_DAYS
		if days == 0 and info.Hour >= def.Hours[2] then
			days = GameTime.YEAR_DAYS
		end
		if days < bestDays then
			best, bestDays = def, days
		end
	end
	return best, bestDays
end

local function activity(def: any, id: string): any?
	for _, a in def.Activities do
		if a.Id == id then
			return a
		end
	end
	return nil
end

-- Player festival state -------------------------------------------------------------------------------------

local function stateFor(profile: any): any?
	if not active then
		return nil
	end
	local st = profile.Festival
	if type(st) ~= "table" or st.Key ~= active.Key then
		st =
			{ Key = active.Key, Entries = {}, Found = {}, Ch = {}, Done = {}, Bought = {}, Best = {}, Attended = false }
		profile.Festival = st
	end
	return st
end

-- Leaderboards ---------------------------------------------------------------------------------------------------

local localBoards: { [string]: { [string]: { V: number, Meta: any } } } = {}

local function sortedMap(name: string): MemoryStoreSortedMap?
	local ok, map = pcall(function()
		return MemoryStoreService:GetSortedMap(name)
	end)
	return if ok then map else nil
end

local function submit(boardKey: string, userId: number, value: number, meta: any)
	localBoards[boardKey] = localBoards[boardKey] or {}
	localBoards[boardKey][tostring(userId)] = { V = value, Meta = meta }
	local map = sortedMap("Festival_" .. boardKey)
	if map then
		task.spawn(pcall, function()
			(map :: MemoryStoreSortedMap):SetAsync(tostring(userId), meta, BOARD_TTL, value)
		end)
	end
end

local function top(boardKey: string, n: number, ascending: boolean): { { UserId: number, Value: number, Meta: any } }
	local out = {}
	local map = sortedMap("Festival_" .. boardKey)
	if map then
		local ok, range = pcall(function()
			return (map :: MemoryStoreSortedMap):GetRangeAsync(
				if ascending then Enum.SortDirection.Ascending else Enum.SortDirection.Descending,
				n
			)
		end)
		if ok and type(range) == "table" and #range > 0 then
			for _, entry in range do
				table.insert(
					out,
					{ UserId = tonumber(entry.key) or 0, Value = tonumber(entry.sortKey) or 0, Meta = entry.value }
				)
			end
			return out
		end
	end
	for userId, entry in pairs(localBoards[boardKey] or {}) do
		table.insert(out, { UserId = tonumber(userId) or 0, Value = entry.V, Meta = entry.Meta })
	end
	table.sort(out, function(a, b)
		if ascending then
			return a.Value < b.Value
		end
		return a.Value > b.Value
	end)
	while #out > n do
		table.remove(out)
	end
	return out
end

-- Pay each placement once across all servers.
local awardedLocal: { [string]: boolean } = {}
local function claimAward(awardKey: string): boolean
	if awardedLocal[awardKey] then
		return false
	end
	awardedLocal[awardKey] = true
	local map = sortedMap("FestivalAwards")
	if not map then
		return true
	end
	local won = true
	local ok = pcall(function()
		(map :: MemoryStoreSortedMap):UpdateAsync(awardKey, function(old)
			if old ~= nil then
				won = false
				return nil
			end
			return true
		end, BOARD_TTL)
	end)
	return won or not ok
end

-- Challenges -------------------------------------------------------------------------------------------------------

function EventService.Progress(player: Player, kind: string, target: string?, count: number, meta: any?)
	if not active or count <= 0 then
		return
	end
	local profile = S.Data.Get(player)
	if not profile then
		return
	end
	local st = stateFor(profile)
	if not st then
		return
	end
	local changed = false
	for _, ch in active.Def.Challenges do
		if ch.Type == kind and not st.Done[ch.Id] then
			local targetOk = not ch.Target or (target ~= nil and target ~= "*" and Registry.Matches(target, ch.Target))
			local qualityOk = not ch.Quality or (meta and (meta.Quality or 0) >= ch.Quality)
			if targetOk and qualityOk then
				st.Ch[ch.Id] = math.min(ch.Count, (st.Ch[ch.Id] or 0) + count)
				changed = true
				if st.Ch[ch.Id] >= ch.Count then
					st.Done[ch.Id] = true
					S.Economy.AddTokens(player, ch.Tokens)
					S.Notify.Toast(
						player,
						string.format("🎟️ Challenge complete: %s (+%d tokens)", ch.Text, ch.Tokens),
						"Success"
					)
				end
			end
		end
	end
	if changed then
		S.Data.Changed(player, "Festival")
	end
end

-- Hooks from other services ------------------------------------------------------------------------------------

-- Harvests are counted through QuestService.Progress; this only marks the
-- harvest as a festival-day harvest for stats.
function EventService.OnHarvest(player: Player, _cropId: string, _roll: any)
	if active then
		S.Data.AddStat(player, "FestivalHarvests")
	end
end

function EventService.OnCatch(player: Player, fishId: string, size: number, quality: number)
	if not active then
		return
	end
	for _, a in active.Def.Activities do
		if a.Kind == "Derby" then
			local profile = S.Data.Get(player)
			local st = profile and stateFor(profile)
			if st and size > (st.Best[a.Id] or 0) then
				st.Best[a.Id] = math.floor(size * 10) / 10
				S.Data.Changed(player, "Festival")
				submit(
					active.Key .. "_" .. a.Id,
					player.UserId,
					st.Best[a.Id],
					{ Name = player.DisplayName, Item = fishId, Q = quality }
				)
				S.Notify.Toast(
					player,
					string.format("🐟 New derby best: %s (%.1f cm)!", Registry.Items[fishId].Name, size),
					"Success"
				)
			end
		end
	end
end

-- Actions ------------------------------------------------------------------------------------------------------------

local function find(player: Player, st: any, a: any, index: number)
	if a.Kind ~= "Scavenger" or type(index) ~= "number" or index < 1 or index > a.Count then
		return false, "Nothing there"
	end
	local part = active and active.Folder:FindFirstChild(a.Id .. "_" .. index) :: BasePart?
	if not part then
		return false, "Nothing there"
	end
	if not S.Security.InReach(player, part.Position, Festivals.ScavengerReach + 4) then
		return false, "Too far away"
	end
	st.Found[a.Id] = st.Found[a.Id] or {}
	local key = tostring(index)
	if st.Found[a.Id][key] then
		return false, "Already found"
	end
	if a.Dig and player.Character and player.Character:GetAttribute("Held") ~= "tool_shovel" then
		return false, "Dig it up with your shovel"
	end
	st.Found[a.Id][key] = true
	S.Economy.AddTokens(player, a.Tokens)
	S.Data.Changed(player, "Festival")
	S.Notify.FX(part.Position, "FestivalFind", { Activity = a.Id, Index = index, By = player.UserId }, 60)
	EventService.Progress(player, "Scavenger", a.Id, 1)
	if a.Dig and Registry.Items.treasure_chest and math.random() < 0.35 then
		S.Inventory.Give(player, "treasure_chest", 1, nil, nil, { Source = a.Name })
	end
	local found = 0
	for _ in st.Found[a.Id] do
		found += 1
	end
	return true, { Found = found, Count = a.Count }
end

local function entryFrom(player: Player, payload: any): any?
	if type(payload.Aid) == "string" then
		local profile = S.Data.Get(player)
		local animal = profile and profile.Farm.Animals[payload.Aid]
		if animal then
			return { Kind = "Animal", Animal = animal, Aid = payload.Aid }
		end
	elseif type(payload.Ref) == "string" then
		local stack = S.Inventory.Slot(player, payload.Ref)
		if stack then
			return { Kind = "Item", Stack = stack }
		end
	end
	return nil
end

local function enter(player: Player, st: any, a: any, payload: any, previewOnly: boolean)
	if a.Kind ~= "Contest" then
		return false, "That isn't a contest"
	end
	local entry = entryFrom(player, payload)
	if not entry then
		return false, "Choose an entry"
	end
	if not ContestMath.Accepts(a, entry) then
		return false, "The judges won't accept that for " .. a.Name
	end
	local score, points = ContestMath.Score(a, entry)
	if previewOnly then
		return true, { Score = score, Points = points, Weights = a.Scoring }
	end
	if st.Entries[a.Id] then
		return false, "You've already entered " .. a.Name
	end
	local label
	if entry.Kind == "Animal" then
		label = { Name = player.DisplayName, Animal = entry.Animal.Nm, Sp = entry.Animal.Sp }
	else
		label = {
			Name = player.DisplayName,
			Item = entry.Stack.Id,
			Q = entry.Stack.Q,
			M = entry.Stack.M,
			S = entry.Stack.S,
		}
	end
	local current = active :: Active
	st.Entries[a.Id] = { Score = score, Points = points, Label = label }
	S.Data.Changed(player, "Festival")
	submit(current.Key .. "_" .. a.Id, player.UserId, score, label)
	local entryPrize = current.Def.Prizes.Entry
	if entryPrize and entryPrize.Tokens then
		S.Economy.AddTokens(player, entryPrize.Tokens)
	end
	S.Data.AddStat(player, "ContestEntries")
	S.Notify.Toast(
		player,
		string.format("Entered %s with a score of %.1f / 100. Results when the festival ends!", a.Name, score),
		"Success"
	)
	return true, { Score = score, Points = points }
end

local function raceStart(player: Player, a: any)
	if a.Kind ~= "Race" then
		return false, "Not a race"
	end
	local first = a.Checkpoints[1]
	if not S.Security.InReach(player, first, RACE_CHECKPOINT_RANGE) then
		return false, "Go to the starting line"
	end
	races[player] = { Activity = a.Id, Start = os.clock(), Next = 2, Last = first }
	return true, { Next = 2, Checkpoints = a.Checkpoints }
end

local function checkpoint(player: Player, st: any, a: any, index: number)
	local run = races[player]
	if not run or run.Activity ~= a.Id or index ~= run.Next then
		return false, "Wrong checkpoint"
	end
	local point = a.Checkpoints[index]
	if not point or not S.Security.InReach(player, point, RACE_CHECKPOINT_RANGE) then
		return false, "Missed it"
	end
	-- Plausibility: can't cover the leg faster than the fastest mount.
	local elapsed = os.clock() - run.Start
	local legDistance = 0
	for i = 2, index do
		legDistance += (a.Checkpoints[i] - a.Checkpoints[i - 1]).Magnitude
	end
	if elapsed < legDistance / RACE_MAX_SPEED then
		races[player] = nil
		S.Security.Flag(player, "Impossible race time", 2)
		return false, "Race voided"
	end
	run.Next = index + 1
	run.Last = point
	if index < #a.Checkpoints then
		return true, { Next = run.Next }
	end
	races[player] = nil
	local time = math.floor(elapsed * 100) / 100
	EventService.Progress(player, "Race", a.Id, 1)
	local best = st.Best[a.Id]
	if not best or time < best then
		st.Best[a.Id] = time
		S.Data.Changed(player, "Festival")
		submit((active :: Active).Key .. "_" .. a.Id, player.UserId, time, { Name = player.DisplayName })
	end
	return true, { Finished = true, Time = time, Best = st.Best[a.Id] }
end

local function buy(player: Player, st: any, payload: any)
	local id = type(payload.Id) == "string" and payload.Id
	local qty = math.clamp(math.floor(tonumber(payload.N) or 1), 1, 99)
	local current = active :: Active
	local entry
	for _, e in current.Def.Shop do
		if e.Id == id then
			entry = e
		end
	end
	if not entry or not Registry.Items[entry.Id] then
		return false, "Not for sale"
	end
	local bought = st.Bought[entry.Id] or 0
	if entry.Stock and bought + qty > entry.Stock then
		return false, "Only " .. (entry.Stock - bought) .. " left"
	end
	if not S.Economy.SpendTokens(player, entry.Price * qty) then
		return false, "Not enough tokens"
	end
	st.Bought[entry.Id] = bought + qty
	S.Data.Changed(player, "Festival")
	S.Inventory.Give(player, entry.Id, qty, nil, nil, { Source = current.Def.Name })
	return true
end

local function snapshot(player: Player): any
	local profile = S.Data.Get(player)
	local nextDef, inDays = EventService.Next()
	if not active or not profile then
		return { Active = false, Next = nextDef and nextDef.Id, NextInDays = inDays }
	end
	local st = stateFor(profile)
	local boards = {}
	for _, a in active.Def.Activities do
		if a.Kind == "Contest" or a.Kind == "Derby" or a.Kind == "Race" then
			boards[a.Id] = top(active.Key .. "_" .. a.Id, 10, a.Kind == "Race")
		end
	end
	return {
		Active = true,
		Id = active.Def.Id,
		Key = active.Key,
		Ends = active.Ends,
		State = st,
		Boards = boards,
		Tokens = profile.Tokens,
	}
end

local function action(player: Player, kind: string, payload: any?)
	if kind == "Get" then
		return true, snapshot(player)
	end
	if not active then
		return false, "There's no festival right now"
	end
	local profile = S.Data.Get(player)
	local st = profile and stateFor(profile)
	if not st then
		return false, "Not ready"
	end
	local p = if type(payload) == "table" then payload else {}
	if kind == "Buy" then
		return buy(player, st, p)
	end
	local a = type(p.Activity) == "string" and activity(active.Def, p.Activity)
	if not a then
		return false, "Unknown activity"
	end
	if kind == "Find" then
		return find(player, st, a, tonumber(p.Index) or 0)
	elseif kind == "Enter" then
		return enter(player, st, a, p, false)
	elseif kind == "Preview" then
		return enter(player, st, a, p, true)
	elseif kind == "RaceStart" then
		return raceStart(player, a)
	elseif kind == "Checkpoint" then
		return checkpoint(player, st, a, tonumber(p.Index) or 0)
	elseif kind == "Board" then
		return true, top(active.Key .. "_" .. a.Id, 10, a.Kind == "Race")
	end
	return false, "Unknown action"
end

-- Start / end -----------------------------------------------------------------------------------------------------

local function spawnScavengers(def: any, key: string, folder: Folder)
	for _, a in def.Activities do
		if a.Kind == "Scavenger" then
			for i = 1, a.Count do
				local point = S.World.SpawnPoint("Village", RNG.HashInt(key, a.Id, i), 2)
				if point then
					local part = Instance.new("Part")
					part.Name = a.Id .. "_" .. i
					part.Size = Vector3.new(2, 2, 2)
					part.Transparency = 1
					part.Anchored = true
					part.CanCollide = false
					part.CanTouch = false
					part.Position = point + Vector3.new(0, 1, 0)
					part:SetAttribute("Kind", "Festival")
					part:SetAttribute("Activity", a.Id)
					part:SetAttribute("Index", i)
					part:SetAttribute("Model", a.Model or "Star")
					part:SetAttribute("Dig", a.Dig == true)
					part.Parent = folder
				end
			end
		end
	end
end

local function start(def: any, key: string)
	local folder = Instance.new("Folder")
	folder.Name = "Festival"
	folder.Parent = workspace
	local info = GameTime.Info()
	local hoursLeft = def.Hours[2] - info.Hour
	local ends = math.floor(GameTime.Now() + hoursLeft * GameTime.HOUR)
	active = { Def = def, Key = key, Folder = folder, Ends = ends }
	spawnScavengers(def, key, folder)
	if def.Weather then
		S.Weather.Force(def.Weather, hoursLeft * GameTime.HOUR)
	end
	ReplicatedStorage:SetAttribute("Festival", def.Id)
	ReplicatedStorage:SetAttribute("FestivalKey", key)
	ReplicatedStorage:SetAttribute("FestivalDecor", def.Decor)
	S.Notify.BannerAll(def.Icon .. " " .. def.Name .. " has begun!", def.Description, "Festival", def.Icon)
	Net.FireAll("Festival", "Start", { Id = def.Id, Key = key, Ends = ends })
	EventService.Started:Fire(def, key)
end

local function finalize(def: any, key: string)
	for _, a in def.Activities do
		if a.Kind == "Contest" or a.Kind == "Derby" or a.Kind == "Race" then
			local boardKey = key .. "_" .. a.Id
			local winners = top(boardKey, 3, a.Kind == "Race")
			for rank, winner in winners do
				local prize = def.Prizes[PLACES[rank]]
				if prize and winner.UserId > 0 and claimAward(boardKey .. "_" .. winner.UserId) then
					local items = {}
					for _, entry in prize.Items or {} do
						table.insert(items, ItemUtil.New(entry[1], entry[2] or 1))
					end
					S.Mail.SendTo(winner.UserId, {
						From = "Festival Committee",
						Subject = string.format("%s — %s place in %s!", def.Name, PLACES[rank], a.Name),
						Body = string.format(
							"Congratulations! Your entry placed %s in the %s. Here are your prizes.",
							string.lower(PLACES[rank]),
							a.Name
						),
						Coins = prize.Coins,
						Tokens = prize.Tokens,
						Items = if #items > 0 then items else nil,
						Title = prize.Title,
					})
					local winnerPlayer = Players:GetPlayerByUserId(winner.UserId)
					if winnerPlayer then
						S.Data.AddStat(winnerPlayer, "ContestPodiums")
						if rank == 1 then
							S.Data.AddStat(winnerPlayer, "ContestWins")
						end
						S.Quest.Progress(winnerPlayer, "Festival", "Podium", 1)
					end
				end
			end
			-- Announce the results to everyone here.
			if #winners > 0 then
				local names = {}
				for rank, winner in winners do
					local name = (type(winner.Meta) == "table" and winner.Meta.Name) or ("#" .. winner.UserId)
					local value = if a.Kind == "Race"
						then Format.Duration(winner.Value)
						elseif a.Kind == "Derby" then string.format("%.1f cm", winner.Value)
						else string.format("%.1f pts", winner.Value)
					table.insert(names, string.format("%s %s (%s)", ({ "🥇", "🥈", "🥉" })[rank], name, value))
				end
				S.Notify.BannerAll(a.Icon .. " " .. a.Name .. " results", table.concat(names, "   "), "Festival")
			end
		end
	end
end

local function stop()
	local current = active
	if not current then
		return
	end
	active = nil
	table.clear(races)
	current.Folder:Destroy()
	ReplicatedStorage:SetAttribute("Festival", nil)
	ReplicatedStorage:SetAttribute("FestivalKey", nil)
	ReplicatedStorage:SetAttribute("FestivalDecor", nil)
	Net.FireAll("Festival", "End", { Id = current.Def.Id })
	task.spawn(finalize, current.Def, current.Key)
	EventService.Ended:Fire(current.Def, current.Key)
end

-- Servers that start after today's festival ended still settle its results
-- (claimAward makes sure nobody is paid twice).
local settled: { [string]: boolean } = {}
local function settleEarlierToday()
	local info = GameTime.Info()
	for _, def in Festivals.List do
		if info.Season == def.Season and info.DayOfSeason == def.Day and info.Hour >= def.Hours[2] then
			local key = def.Id .. "_" .. info.Day
			if not settled[key] then
				settled[key] = true
				task.spawn(finalize, def, key)
			end
		end
	end
end

local function tick()
	local def, key = festivalAt(GameTime.Now())
	if active and active.Key ~= key then
		settled[active.Key] = true
		stop()
	end
	if def and key and not active then
		start(def, key)
	end
	if not active then
		settleEarlierToday()
	end
	-- Attendance: being in the village during a festival.
	if active then
		for _, player in Players:GetPlayers() do
			local profile = S.Data.Get(player)
			local st = profile and stateFor(profile)
			if st and not st.Attended and S.Player.Region(player) == "Village" then
				st.Attended = true
				S.Data.Changed(player, "Festival")
				S.Data.AddStat(player, "FestivalsAttended")
				S.Economy.AddTokens(player, ATTEND_TOKENS)
				S.Notify.Toast(
					player,
					"🎟️ Welcome to the " .. active.Def.Name .. "! Here are " .. ATTEND_TOKENS .. " tokens.",
					"Success"
				)
			end
		end
	end
end

function EventService.Init()
	Net.Handle("FestivalGet", function(player)
		return true, snapshot(player)
	end)
	Net.Handle("FestivalAction", action)
end

function EventService.Start()
	Players.PlayerRemoving:Connect(function(player)
		races[player] = nil
	end)
	task.spawn(function()
		while true do
			local ok, err = pcall(tick)
			if not ok then
				warn("[Evergrove] Festival tick failed:", err)
			end
			task.wait(TICK)
		end
	end)
end

return EventService

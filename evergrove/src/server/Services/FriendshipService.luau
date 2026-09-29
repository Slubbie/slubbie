-- Friendship with villagers: daily chats, gifts (with loves/likes/hates and
-- birthdays), heart levels, gentle decay, perks and heart-event story scenes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local NPCs = require(Shared.Config.NPCs)
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local Stats = require(Shared.Lib.Stats)
local GameTime = require(Shared.Lib.GameTime)
local ItemUtil = require(Shared.Lib.ItemUtil)

local S = require(script.Parent)

local MAX_POINTS = NPCs.PointsPerHeart * NPCs.MaxHearts

local FriendshipService = {}

local random = Random.new()

function FriendshipService.Entry(profile: any, npcId: string): any
	local entry = profile.Friendship[npcId]
	if not entry then
		entry = { Pts = 0, Ev = {} }
		profile.Friendship[npcId] = entry
	end
	entry.Ev = entry.Ev or {}
	return entry
end

local function countMaxHearts(profile: any): number
	local n = 0
	for npcId in profile.Friendship do
		if Stats.Hearts(profile, npcId) >= NPCs.MaxHearts then
			n += 1
		end
	end
	return n
end

-- Change friendship points (buffs amplify gains).
function FriendshipService.Add(player: Player, npcId: string, points: number)
	local profile = S.Data.Get(player)
	if not profile or not Registry.Npcs[npcId] or points == 0 then
		return
	end
	local entry = FriendshipService.Entry(profile, npcId)
	if points > 0 then
		points *= 1 + Stats.Effect(profile, "FriendshipGain", GameTime.Now())
	end
	local before = Stats.Hearts(profile, npcId)
	entry.Pts = math.clamp(math.floor((entry.Pts or 0) + points), 0, MAX_POINTS)
	local after = Stats.Hearts(profile, npcId)
	S.Data.Changed(player, "Friendship", npcId)
	if after > before then
		local npc = Registry.Npcs[npcId]
		S.Notify.FXPlayer(player, "Hearts", { Npc = npcId, Hearts = after })
		for _, perk in npc.Perks or {} do
			if perk.Hearts > before and perk.Hearts <= after then
				S.Notify.Toast(player, "💝 " .. npc.Name .. ": " .. perk.Text, "Success")
			end
		end
		S.Data.MaxStat(player, "NpcsAtMaxHearts", countMaxHearts(profile))
		S.Crafting.Sync(player)
		S.Quest.Refresh(player)
		S.Quest.Progress(player, "Reach", "Hearts:" .. npcId, 0)
	end
end

function FriendshipService.IsBirthday(npcId: string): boolean
	local npc = Registry.Npcs[npcId]
	local info = GameTime.Info()
	return npc ~= nil and npc.Birthday[1] == info.Season and npc.Birthday[2] == info.DayOfSeason
end

-- Once-per-day chat bonus. Returns true the first time today.
function FriendshipService.Talk(player: Player, npcId: string): boolean
	local profile = S.Data.Get(player)
	if not profile then
		return false
	end
	local entry = FriendshipService.Entry(profile, npcId)
	local day = GameTime.Info().Day
	if not entry.Met then
		entry.Met = true
		S.Collection.Discover(player, "Villagers", npcId)
	end
	if entry.Talk == day then
		return false
	end
	entry.Talk = day
	FriendshipService.Add(player, npcId, NPCs.TalkPoints)
	return true
end

-- How much an NPC likes an item: "Love" | "Like" | "Neutral" | "Dislike" | "Hate"
function FriendshipService.Preference(npcId: string, stack: ItemUtil.Stack): string
	local npc = Registry.Npcs[npcId]
	if not npc then
		return "Neutral"
	end
	-- Mutations like Golden count as tags for gifting (#Golden).
	local function matches(spec: string): boolean
		if Registry.Matches(stack.Id, spec) then
			return true
		end
		if string.sub(spec, 1, 1) == "#" and stack.M then
			return table.find(stack.M, string.sub(spec, 2)) ~= nil
		end
		return false
	end
	for _, pref in { "Love", "Hate", "Like", "Dislike" } do
		for _, spec in npc.Gifts[pref] do
			if matches(spec) then
				return pref
			end
		end
	end
	for pref, list in NPCs.Universal do
		for _, spec in list do
			if matches(spec) then
				return pref
			end
		end
	end
	return "Neutral"
end

local function gift(player: Player, npcId: string, ref: string)
	local profile = S.Data.Get(player)
	local npc = Registry.Npcs[npcId]
	if not profile or not npc then
		return false, "Unknown villager"
	end
	if not S.NPC.Near(player, npcId) then
		return false, "Get closer to " .. npc.Name
	end
	local stack = S.Inventory.Slot(player, ref)
	if not stack then
		return false, "Nothing there"
	end
	local def = Registry.Items[stack.Id]
	if not def or def.Category == "Tool" or def.Category == "Special" then
		return false, "You can't give that"
	end
	local entry = FriendshipService.Entry(profile, npcId)
	local week = math.floor(GameTime.Info().Day / 7)
	if entry.GW ~= week then
		entry.GW = week
		entry.GC = 0
	end
	local birthday = FriendshipService.IsBirthday(npcId)
	if (entry.GC or 0) >= NPCs.GiftsPerWeek and not birthday then
		return false, npc.Name .. " has had enough gifts this week"
	end
	local taken = S.Inventory.TakeFromSlot(player, ref, 1)
	if not taken then
		return false, "Unlock it first"
	end
	entry.GC = (entry.GC or 0) + 1
	local pref = FriendshipService.Preference(npcId, taken)
	-- Remember what you've learned about their taste (shown in the gift picker).
	entry.Known = entry.Known or {}
	entry.Known[taken.Id] = pref
	local points = NPCs.GiftPoints[pref]
	if points > 0 then
		points *= 1 + ((taken.Q or 1) - 1) * NPCs.QualityGiftBonus
		if birthday then
			points *= NPCs.BirthdayMultiplier
		end
	end
	FriendshipService.Add(player, npcId, points)
	S.Data.AddStat(player, "GiftsGiven")
	S.Quest.Progress(player, "Gift", npcId, 1)
	local lines = if birthday and pref ~= "Hate" and pref ~= "Dislike" then npc.Lines.Birthday else npc.Lines[pref]
	local line = lines[random:NextInteger(1, #lines)]
	S.NPC.Say(player, npcId, { line }, { Reaction = pref })
	return true, { Reaction = pref, Points = math.floor(points) }
end

-- Heart events (story scenes) unlocked but not yet seen.
function FriendshipService.PendingEvent(profile: any, npcId: string): any?
	local npc = Registry.Npcs[npcId]
	local hearts = Stats.Hearts(profile, npcId)
	local entry = profile.Friendship[npcId]
	for _, event in npc.Events or {} do
		if hearts >= event.Hearts and not (entry and entry.Ev and entry.Ev[tostring(event.Hearts)]) then
			return event
		end
	end
	return nil
end

function FriendshipService.PlayEvent(player: Player, npcId: string, event: any)
	local profile = S.Data.Get(player)
	if not profile then
		return
	end
	local entry = FriendshipService.Entry(profile, npcId)
	entry.Ev[tostring(event.Hearts)] = true
	S.Data.Changed(player, "Friendship", npcId)
	S.Economy.GrantReward(player, event.Reward, Registry.Npcs[npcId].Name)
end

-- Gentle decay for people you haven't talked to (never below the floor).
local function decay()
	local day = GameTime.Info().Day
	local floorPoints = NPCs.DecayFloorHearts * NPCs.PointsPerHeart
	for player, profile in S.Data.All() do
		for npcId, entry in profile.Friendship do
			if entry.Talk and entry.Talk < day - 1 and (entry.Pts or 0) > floorPoints then
				entry.Pts = math.max(floorPoints, entry.Pts - NPCs.DecayPerDay)
				S.Data.Changed(player, "Friendship", npcId)
			end
		end
	end
end

function FriendshipService.Init()
	Net.Handle("NpcGift", gift)
end

function FriendshipService.Start()
	S.Time.NewDay:Connect(decay)
end

return FriendshipService

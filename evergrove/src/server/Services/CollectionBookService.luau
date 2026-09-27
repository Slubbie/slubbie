-- The collection book, museum donations and profile showcases.
--
-- Services report discoveries (Discover / OnItem). The first time an entry is
-- found the player gets a reveal (dramatic for Legendary/Mythic finds); every
-- time, personal bests (quality, size) and counts are kept. Milestones per
-- category (25/50/75/100%) pay out when claimed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Lib.Net)
local Collections = require(Shared.Lib.Collections)
local Registry = require(Shared.Lib.Registry)
local ItemUtil = require(Shared.Lib.ItemUtil)
local GameTime = require(Shared.Lib.GameTime)
local Social = require(Shared.Config.Social)

local S = require(script.Parent)

local CollectionBookService = {}

local MUSEUM_CATEGORIES = { Artifact = true, Gem = true, Mineral = true, Fish = true, Bug = true }

local function updatePercent(player: Player, profile: any)
	local percent = math.floor(Collections.TotalPercent(profile.Collection) * 1000) / 10
	S.Data.MaxStat(player, "CollectionPercent", percent)
end

-- Record a discovery. meta: { Quality, Size, Crop }
function CollectionBookService.Discover(player: Player, categoryId: string, entryId: string, meta: { [string]: any }?)
	local profile = S.Data.Get(player)
	local cat = Collections.Get(categoryId)
	if not profile or not cat then
		return
	end
	local entry = cat.Index[entryId]
	if not entry then
		return
	end
	profile.Collection[categoryId] = profile.Collection[categoryId] or {}
	local records = profile.Collection[categoryId]
	local record = records[entryId]
	local first = record == nil
	if first then
		record = { F = GameTime.Now(), N = 0 }
		records[entryId] = record
	end
	record.N = (record.N or 0) + 1
	if meta then
		if meta.Quality and meta.Quality > (record.Q or 0) then
			record.Q = meta.Quality
		end
		if meta.Size and meta.Size > (record.S or 0) then
			record.S = math.floor(meta.Size * 100) / 100
		end
	end
	S.Data.Changed(player, "Collection", categoryId, entryId)
	if first then
		S.Notify.Discovery(player, categoryId, entryId, { Name = entry.Name, Icon = entry.Icon, Rarity = entry.Rarity })
		S.Quest.Progress(player, "Discover", categoryId, 1)
		updatePercent(player, profile)
	end
end

-- Categorise an obtained item and record it.
function CollectionBookService.OnItem(player: Player, stack: ItemUtil.Stack)
	local categoryId, entryId = Collections.CategoryForItem(stack.Id)
	if categoryId and entryId then
		CollectionBookService.Discover(player, categoryId, entryId, { Quality = stack.Q or 1, Size = stack.S })
		local def = Registry.Items[stack.Id]
		if def and def.Tags.Flower and categoryId == "Forage" then
			CollectionBookService.Discover(player, "Flowers", stack.Id, { Quality = stack.Q or 1 })
		end
	end
end

local function claim(player: Player, categoryId: string, index: number)
	local profile = S.Data.Get(player)
	local cat = Collections.Get(categoryId)
	if not profile or not cat then
		return false, "Unknown category"
	end
	local milestone = cat.Milestones[index]
	if not milestone then
		return false, "Unknown milestone"
	end
	profile.Claimed[categoryId] = profile.Claimed[categoryId] or {}
	local key = tostring(index)
	if profile.Claimed[categoryId][key] then
		return false, "Already claimed"
	end
	local found, total = Collections.Progress(profile.Collection, categoryId)
	if total == 0 or found / total < milestone.Percent then
		return false, "Keep collecting!"
	end
	profile.Claimed[categoryId][key] = true
	S.Data.Changed(player, "Claimed")
	S.Economy.GrantReward(player, milestone.Reward, cat.Name .. " milestone")
	return true
end

local function donate(player: Player, ref: string)
	local profile = S.Data.Get(player)
	local stack = S.Inventory.Slot(player, ref)
	if not profile or not stack then
		return false, "Nothing there"
	end
	if not S.NPC.Near(player, "beatrix") then
		return false, "Bring it to Beatrix at the museum"
	end
	local def = Registry.Items[stack.Id]
	if not def or not MUSEUM_CATEGORIES[def.Category] then
		return false, "The museum doesn't collect that"
	end
	if profile.Museum[stack.Id] then
		return false, "Already donated"
	end
	local taken = S.Inventory.TakeFromSlot(player, ref, 1)
	if not taken then
		return false, "Unlock it first"
	end
	profile.Museum[stack.Id] = GameTime.Now()
	S.Data.Changed(player, "Museum")
	S.Data.AddStat(player, "Donations")
	local reward = math.floor(def.Value * 0.5 + 50)
	S.Economy.AddCoins(player, reward, "Museum reward")
	S.Friendship.Add(player, "beatrix", 15)
	S.Quest.Progress(player, "Donate", stack.Id, 1)
	for _, drop in S.Quest.DropsFor(player, "Donate") do
		S.Inventory.Give(player, drop, 1, nil, nil, { Source = "Beatrix" })
		S.Notify.Toast(player, "Beatrix found something in the archives for you!", "Success")
	end
	CollectionBookService.OnItem(player, taken)
	return true, reward
end

local function showcase(player: Player, index: number, ref: string?)
	local profile = S.Data.Get(player)
	if not profile or index < 1 or index > Social.Profile.ShowcaseSlots then
		return false, "Bad slot"
	end
	local key = tostring(index)
	if not ref then
		profile.Showcase[key] = nil
	else
		local stack = S.Inventory.Slot(player, ref)
		if not stack then
			return false, "Nothing there"
		end
		profile.Showcase[key] = { Id = stack.Id, Q = stack.Q, M = stack.M, S = stack.S }
	end
	S.Data.Changed(player, "Showcase")
	S.Building.RefreshDisplays(player)
	return true
end

function CollectionBookService.Init()
	Net.Handle("CollectionClaim", claim)
	Net.Handle("MuseumDonate", donate)
	Net.Handle("ShowcaseSet", showcase)
end

function CollectionBookService.Start()
	S.Data.Loaded:Connect(function(player, profile)
		-- Always know the people you've met and the recipes you know.
		for recipeId in profile.Recipes do
			CollectionBookService.Discover(player, "Recipes", recipeId)
		end
		updatePercent(player, profile)
	end)
end

return CollectionBookService

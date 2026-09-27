-- Handles every client request. Each handler:
--   1. is rate limited,
--   2. refuses until the player's data has loaded,
--   3. validates every argument's type and range,
--   4. runs synchronously (check + apply in the same frame, so nothing can double-apply),
--   5. returns { ok = true, ... } or { ok = false, err = "..." }.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Dicebound.Config)
local LootMath = require(ReplicatedStorage.Dicebound.LootMath)
local Net = require(ReplicatedStorage.Dicebound.Net)
local Format = require(ReplicatedStorage.Dicebound.Format)

local Services = script.Parent
local PlayerData = require(Services.PlayerData)
local StateSync = require(Services.StateSync)
local ActionState = require(Services.ActionState)
local RateLimiter = require(Services.RateLimiter)
local RegionService = require(Services.RegionService)

local Core = Services.Parent.Core
local Bag = require(Core.Bag)
local Shop = require(Core.Shop)
local RollEngine = require(Core.RollEngine)
local Schema = require(Core.Schema)
local Tutorial = require(Core.Tutorial)

-- Accept a roll this much before the cooldown ends, to absorb network jitter.
local ROLL_TOLERANCE = 0.15

local rng = Random.new()

local Requests = {}

local function fail(err: string, code: string?)
	return { ok = false, err = err, code = code }
end

local function bind(name: string, limiter: RateLimiter.Limiter, handler: (Player, PlayerData.Profile, ...any) -> any)
	Net.Functions[name].OnServerInvoke = function(player: Player, ...)
		if not limiter:Allow(player) then
			return fail("Slow down a little!", "RateLimited")
		end
		local profile = PlayerData.Get(player)
		if not profile then
			return fail("Still loading your treasure...", "Loading")
		end
		local state = ActionState.Get(player)
		if state.Busy then
			return fail("Still working on your last action.", "Busy")
		end
		state.Busy = true
		local ok, result = pcall(handler, player, profile, ...)
		state.Busy = false
		if not ok then
			warn("[Dicebound] " .. name .. " failed for " .. player.Name .. ": " .. tostring(result))
			return fail("Something went wrong. Please try again.", "Error")
		end
		StateSync.Push(player)
		return result
	end
end

local function tutorialStep(player: Player, data, action: string)
	local reward = Tutorial.OnAction(data, action)
	if reward then
		StateSync.Notify(player, "Tutorial complete! +" .. Format.Coins(reward) .. " coins", "success")
	end
end

-- Dice the player actually rolls: owned, live, no duplicates, limited by their slots.
local function activeDice(data): { string }
	local slots = Config.UpgradeValue("DiceSlots", data.Upgrades.DiceSlots)
	local dice, seen = {}, {}
	for _, dieId in data.Dice.Equipped do
		if #dice >= slots then
			break
		end
		if data.Dice.Owned[dieId] and Config.IsLive(Config.Dice.ById[dieId]) and not seen[dieId] then
			seen[dieId] = true
			table.insert(dice, dieId)
		end
	end
	if #dice == 0 then
		dice = { Config.Game.StartingDie }
	end
	return dice
end

local function handleRoll(player: Player, profile: PlayerData.Profile, auto: any)
	local data = profile.Data
	local state = ActionState.Get(player)
	local now = os.clock()
	if now < state.NextRollAt - ROLL_TOLERANCE then
		return fail("Your dice are still settling.", "Cooldown")
	end
	if auto == true and data.Upgrades.AutoRoll < 1 then
		return fail("Unlock the Auto-Roller upgrade first.", "NoAuto")
	end
	-- The region is captured now: walking away mid-animation can't change this roll.
	local region = RegionService.RegionAt(player)
	if not region then
		return fail("Walk into a region to roll.", "NoRegion")
	end
	if not data.Regions[region.Id] then
		return fail(region.Name .. " is still locked.", "RegionLocked")
	end
	local dice = activeDice(data)
	local needed = LootMath.MaxRewardUnits(#dice)
	if Bag.Free(data) < needed then
		return fail(
			string.format("Your bag is full (%d/%d). Sell some treasure first!", Bag.Used(data), Bag.Capacity(data)),
			"BagFull"
		)
	end

	local outcome = RollEngine.Roll(rng, region.Id, dice, data.Discovered)

	-- Apply atomically: space was checked above for the largest possible bundle.
	local nowTime = os.time()
	local rewards = {}
	for _, reward in outcome.Rewards do
		local key = Bag.Add(data, reward.Id, reward.Mut, reward.Qty)
		assert(key, "reserved space missing")
		local isNew, newMutation = Bag.Discover(data, reward.Id, reward.Mut, reward.Qty, nowTime)
		table.insert(rewards, {
			Id = reward.Id,
			Mut = reward.Mut,
			Qty = reward.Qty,
			Source = reward.Source,
			Key = key,
			New = isNew,
			NewMutation = newMutation,
			Value = Config.ItemValue(reward.Id, reward.Mut),
		})
		data.Stats.Found += reward.Qty
		local rarity = Config.Rarities.ById[Config.Items.ById[reward.Id].Rarity]
		if rarity.ConfirmSell then
			Net.Events.Announce:FireAllClients(player.DisplayName, reward.Id, reward.Mut)
		end
	end
	if outcome.Coins > 0 then
		data.Coins += outcome.Coins
		data.Stats.CoinsEarned += outcome.Coins
	end
	data.Stats.Rolls += 1
	if outcome.Combo then
		data.Stats.Combos += 1
		if outcome.Combo == "Jackpot" then
			data.Stats.Jackpots += 1
		end
	end

	local cooldown = math.max(Config.UpgradeValue("Speed", data.Upgrades.Speed), Config.Economy.MinRollCooldown)
	state.NextRollAt = now + cooldown
	state.RollId += 1
	tutorialStep(player, data, "Roll")

	return {
		ok = true,
		RollId = state.RollId,
		Region = region.Id,
		DiceIds = outcome.DiceIds,
		Faces = outcome.Faces,
		Combo = outcome.Combo,
		Rewards = rewards,
		Coins = outcome.Coins,
		Cooldown = cooldown,
	}
end

local function saleResult(player: Player, data, plan: Shop.SalePlan)
	local earned = Shop.ApplySale(data, plan)
	tutorialStep(player, data, "Sell")
	local lines = {}
	for _, l in plan.Lines do
		table.insert(lines, { Id = l.Id, Mut = l.Mut, Qty = l.Qty, Coins = l.Coins })
	end
	return { ok = true, Total = earned, Units = plan.Units, Multiplier = plan.Multiplier, Lines = lines }
end

local function handleSell(player: Player, profile: PlayerData.Profile, selection: any, confirm: any)
	if not RegionService.MerchantNear(player) then
		return fail("Visit a merchant stall to sell.", "NoMerchant")
	end
	local plan, err = Shop.PlanSale(profile.Data, selection, confirm == true)
	if not plan then
		if err == "CONFIRM" then
			return fail("Please confirm selling Legendary or better items.", "Confirm")
		end
		return fail(err or "Couldn't sell that.", "Invalid")
	end
	return saleResult(player, profile.Data, plan)
end

local function handleSellAll(player: Player, profile: PlayerData.Profile, includeHighValue: any)
	if not RegionService.MerchantNear(player) then
		return fail("Visit a merchant stall to sell.", "NoMerchant")
	end
	local plan, err = Shop.PlanSellAll(profile.Data, includeHighValue == true)
	if not plan then
		return fail(err or "Nothing to sell.", "Empty")
	end
	return saleResult(player, profile.Data, plan)
end

local function handleSetLock(_player: Player, profile: PlayerData.Profile, key: any, locked: any)
	if type(key) ~= "string" or #key > 100 or type(locked) ~= "boolean" then
		return fail("Invalid request.", "Invalid")
	end
	local ok, err = Bag.SetLocked(profile.Data, key, locked)
	if not ok then
		return fail(err or "Couldn't change that lock.", "Invalid")
	end
	return { ok = true, Key = key, Locked = locked }
end

local function handleBuyUpgrade(player: Player, profile: PlayerData.Profile, upgradeId: any, expectedLevel: any)
	local ok, err = Shop.BuyUpgrade(profile.Data, upgradeId, expectedLevel)
	if not ok then
		return fail(err or "Couldn't buy that.", "Invalid")
	end
	tutorialStep(player, profile.Data, "Upgrade")
	return { ok = true, Id = upgradeId, Level = profile.Data.Upgrades[upgradeId] }
end

local function handleSkipTutorial(_player: Player, profile: PlayerData.Profile)
	Tutorial.Skip(profile.Data)
	return { ok = true }
end

local function handleSaveSettings(_player: Player, profile: PlayerData.Profile, settings: any)
	if type(settings) ~= "table" then
		return fail("Invalid settings.", "Invalid")
	end
	for name, default in Schema.SettingDefaults do
		local value = settings[name]
		if type(value) == type(default) then
			profile.Data.Settings[name] = if type(value) == "number" then math.clamp(value, 0, 1) else value
		end
	end
	return { ok = true }
end

function Requests.Start()
	-- Rolls are also limited by the cooldown; the bucket only stops floods.
	bind("Roll", RateLimiter.new(4, 2), handleRoll)
	bind("Sell", RateLimiter.new(4, 1), handleSell)
	bind("SellAll", RateLimiter.new(4, 1), handleSellAll)
	bind("SetLock", RateLimiter.new(10, 5), handleSetLock)
	bind("BuyUpgrade", RateLimiter.new(5, 2), handleBuyUpgrade)
	bind("SkipTutorial", RateLimiter.new(2, 0.2), handleSkipTutorial)
	bind("SaveSettings", RateLimiter.new(3, 0.5), handleSaveSettings)

	PlayerData.Loaded:Connect(function(player: Player)
		StateSync.Push(player)
	end)
	-- Players whose data loaded before this ran.
	for _, player in Players:GetPlayers() do
		if PlayerData.Get(player) then
			StateSync.Push(player)
		end
	end
end

return Requests

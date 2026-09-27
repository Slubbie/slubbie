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
local EventService = require(Services.EventService)
local AuraService = require(Services.AuraService)

local Core = Services.Parent.Core
local Bag = require(Core.Bag)
local Shop = require(Core.Shop)
local RollEngine = require(Core.RollEngine)
local Schema = require(Core.Schema)
local Tutorial = require(Core.Tutorial)
local Progress = require(Core.Progress)
local Orders = require(Core.Orders)
local Workshop = require(Core.Workshop)

-- Accept a roll this much before the cooldown ends, to absorb network jitter.
local ROLL_TOLERANCE = 0.15
local UPKEEP_INTERVAL = 10

local rng = Random.new()
local lastTravel: { [Player]: number } = {}

local Requests = {}

local function fail(err: string, code: string?)
	return { ok = false, err = err, code = code }
end

local function ok(extra: { [string]: any }?)
	local result = extra or {}
	result.ok = true
	return result
end

-- Daily objectives roll over and finished orders get replaced. Returns true if anything changed.
local function upkeep(player: Player, data): boolean
	local now = os.time()
	local a = Progress.EnsureDaily(data, now, player.UserId)
	local b = Orders.Refresh(data, rng, now)
	return a or b
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
		upkeep(player, profile.Data)
		local success, result = pcall(handler, player, profile, ...)
		state.Busy = false
		if not success then
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

-- ── Rolling ─────────────────────────────────────────────────────────────────────

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
			string.format(
				"Your bag needs %d free space%s (%d/%d). Sell some treasure first!",
				needed,
				if needed == 1 then "" else "s",
				Bag.Used(data),
				Bag.Capacity(data)
			),
			"BagFull"
		)
	end

	local event = EventService.Current()
	local outcome = RollEngine.Roll(rng, region.Id, dice, data.Discovered, event)

	-- Apply atomically: space was checked above for the largest possible bundle.
	local nowTime = os.time()
	local rewards = {}
	for _, reward in outcome.Rewards do
		local key = Bag.Add(data, reward.Id, reward.Mut, reward.Qty)
		assert(key, "reserved space missing")
		local isNew, newMutation = Bag.Discover(data, reward.Id, reward.Mut, reward.Qty, nowTime)
		local rarity = Config.Rarities.ById[Config.Items.ById[reward.Id].Rarity]
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
		if rarity.Order >= 3 then
			Progress.Track(data, "Rares", reward.Qty)
		end
		if reward.Mut then
			Progress.Track(data, "Mutated", reward.Qty)
		end
		if rarity.ConfirmSell then
			Net.Events.Announce:FireAllClients("find", player.DisplayName, reward.Id, reward.Mut)
		end
	end
	if outcome.Coins > 0 then
		data.Coins += outcome.Coins
		data.Stats.CoinsEarned += outcome.Coins
	end
	Progress.Track(data, "Rolls", 1)
	if outcome.Combo then
		Progress.Track(data, "Combos", 1)
		if outcome.Combo == "Jackpot" then
			Progress.Track(data, "Jackpots", 1)
		end
	end

	local cooldown = math.max(Config.UpgradeValue("Speed", data.Upgrades.Speed), Config.Economy.MinRollCooldown)
	state.NextRollAt = now + cooldown
	state.RollId += 1
	tutorialStep(player, data, "Roll")

	return ok({
		RollId = state.RollId,
		Region = region.Id,
		DiceIds = outcome.DiceIds,
		Faces = outcome.Faces,
		Combo = outcome.Combo,
		Rewards = rewards,
		Coins = outcome.Coins,
		Cooldown = cooldown,
		Event = if event and event.Region == region.Id then event.Id else nil,
	})
end

-- ── Selling ─────────────────────────────────────────────────────────────────────

local function saleResult(player: Player, data, plan: Shop.SalePlan)
	local earned = Shop.ApplySale(data, plan)
	Progress.Track(data, "SaleCoins", earned)
	tutorialStep(player, data, "Sell")
	local lines = {}
	for _, l in plan.Lines do
		table.insert(lines, { Id = l.Id, Mut = l.Mut, Qty = l.Qty, Coins = l.Coins })
	end
	return ok({ Total = earned, Units = plan.Units, Multiplier = plan.Multiplier, Lines = lines })
end

local function handleSell(player: Player, profile: PlayerData.Profile, selection: any, confirm: any)
	local merchant = RegionService.MerchantNear(player)
	if not merchant then
		return fail("Visit a merchant stall to sell.", "NoMerchant")
	end
	local plan, err = Shop.PlanSale(profile.Data, selection, confirm == true, EventService.SellBonus(merchant.Id))
	if not plan then
		if err == "CONFIRM" then
			return fail("Please confirm selling Legendary or better items.", "Confirm")
		end
		return fail(err or "Couldn't sell that.", "Invalid")
	end
	return saleResult(player, profile.Data, plan)
end

local function handleSellAll(player: Player, profile: PlayerData.Profile, includeHighValue: any)
	local merchant = RegionService.MerchantNear(player)
	if not merchant then
		return fail("Visit a merchant stall to sell.", "NoMerchant")
	end
	local plan, err = Shop.PlanSellAll(profile.Data, includeHighValue == true, EventService.SellBonus(merchant.Id))
	if not plan then
		return fail(err or "Nothing to sell.", "Empty")
	end
	return saleResult(player, profile.Data, plan)
end

local function handleSetLock(_player: Player, profile: PlayerData.Profile, key: any, locked: any)
	if type(key) ~= "string" or #key > 100 or type(locked) ~= "boolean" then
		return fail("Invalid request.", "Invalid")
	end
	local success, err = Bag.SetLocked(profile.Data, key, locked)
	if not success then
		return fail(err or "Couldn't change that lock.", "Invalid")
	end
	return ok({ Key = key, Locked = locked })
end

-- ── Upgrades, dice, regions ─────────────────────────────────────────────────────

local function handleBuyUpgrade(player: Player, profile: PlayerData.Profile, upgradeId: any, expectedLevel: any)
	local success, err = Shop.BuyUpgrade(profile.Data, upgradeId, expectedLevel)
	if not success then
		return fail(err or "Couldn't buy that.", "Invalid")
	end
	tutorialStep(player, profile.Data, "Upgrade")
	return ok({ Id = upgradeId, Level = profile.Data.Upgrades[upgradeId] })
end

local function handleBuyDie(_player: Player, profile: PlayerData.Profile, dieId: any)
	local success, err = Workshop.BuyDie(profile.Data, dieId)
	if not success then
		return fail(err or "Couldn't buy that die.", "Invalid")
	end
	-- Put a newly bought die straight into a free slot.
	local data = profile.Data
	local slots = Config.UpgradeValue("DiceSlots", data.Upgrades.DiceSlots)
	if #data.Dice.Equipped < slots then
		local list = table.clone(data.Dice.Equipped)
		table.insert(list, dieId)
		Workshop.Equip(data, list)
	end
	return ok({ Id = dieId })
end

local function handleEquipDice(_player: Player, profile: PlayerData.Profile, list: any)
	if type(list) == "table" and #list > Config.Economy.MaxDice then
		return fail("Too many dice.", "Invalid")
	end
	local success, err = Workshop.Equip(profile.Data, list)
	if not success then
		return fail(err or "Couldn't equip those dice.", "Invalid")
	end
	return ok()
end

local function handleUnlockRegion(player: Player, profile: PlayerData.Profile, regionId: any)
	local success, err = Workshop.UnlockRegion(profile.Data, regionId)
	if not success then
		return fail(err or "Couldn't unlock that region.", "Invalid")
	end
	Net.Events.Announce:FireAllClients("unlock", player.DisplayName, regionId)
	return ok({ Id = regionId })
end

local function handleTravel(player: Player, profile: PlayerData.Profile, regionId: any)
	local region = type(regionId) == "string" and Config.Regions.ById[regionId]
	if not region or not Config.IsLive(region) then
		return fail("That region doesn't exist.", "Invalid")
	end
	if not profile.Data.Regions[region.Id] then
		return fail(region.Name .. " is still locked.", "RegionLocked")
	end
	local now = os.clock()
	if now - (lastTravel[player] or 0) < Config.Economy.TravelCooldown then
		return fail("The travel stones are recharging...", "Cooldown")
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return fail("Your character isn't ready.", "NoCharacter")
	end
	lastTravel[player] = now
	local spawn = RegionService.WorldPosition(region, region.SpawnPosition)
	local origin = RegionService.WorldPosition(region, { 0, 0, 0 })
	character:PivotTo(CFrame.lookAt(spawn + Vector3.new(0, 4, 0), Vector3.new(origin.X, spawn.Y + 4, origin.Z)))
	return ok({ Id = region.Id })
end

-- ── Orders, crafting, cosmetics ─────────────────────────────────────────────────

local function handleFulfillOrder(player: Player, profile: PlayerData.Profile, index: any)
	if not RegionService.MerchantNear(player) then
		return fail("Hand orders in at any merchant stall.", "NoMerchant")
	end
	local reward, err = Orders.Fulfill(profile.Data, index, os.time())
	if not reward then
		return fail(err or "Couldn't complete that order.", "Invalid")
	end
	Progress.Track(profile.Data, "Orders", 1)
	return ok({ Reward = reward })
end

local function handleSkipOrder(_player: Player, profile: PlayerData.Profile, index: any)
	local success, err = Orders.Skip(profile.Data, index, os.time())
	if not success then
		return fail(err or "Couldn't skip that order.", "Invalid")
	end
	return ok()
end

local function handleCraft(player: Player, profile: PlayerData.Profile, recipeId: any)
	local success, err = Workshop.Craft(profile.Data, recipeId)
	if not success then
		return fail(err or "Couldn't craft that.", "Invalid")
	end
	AuraService.Apply(player, profile.Data.Cosmetics.Aura)
	return ok({ Id = recipeId })
end

local function handleEquipCosmetic(player: Player, profile: PlayerData.Profile, kind: any, id: any)
	local success, err = Workshop.EquipCosmetic(profile.Data, kind, id)
	if not success then
		return fail(err or "Couldn't equip that.", "Invalid")
	end
	AuraService.Apply(player, profile.Data.Cosmetics.Aura)
	return ok()
end

-- ── Claims ──────────────────────────────────────────────────────────────────────

local function claim(reward: number?, err: string?)
	if not reward then
		return fail(err or "Nothing to claim.", "Invalid")
	end
	return ok({ Reward = reward })
end

local function handleClaimDaily(_player: Player, profile: PlayerData.Profile, index: any)
	return claim(Progress.ClaimDaily(profile.Data, index))
end

local function handleClaimMilestone(_player: Player, profile: PlayerData.Profile, id: any)
	return claim(Progress.ClaimMilestone(profile.Data, id))
end

local function handleClaimCollection(_player: Player, profile: PlayerData.Profile, regionId: any)
	return claim(Progress.ClaimCollection(profile.Data, regionId))
end

-- ── Misc ────────────────────────────────────────────────────────────────────────

local function handleSkipTutorial(_player: Player, profile: PlayerData.Profile)
	Tutorial.Skip(profile.Data)
	return ok()
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
	return ok()
end

function Requests.Start()
	-- Rolls are also limited by the cooldown; the buckets only stop floods.
	bind("Roll", RateLimiter.new(4, 2), handleRoll)
	bind("Sell", RateLimiter.new(4, 1), handleSell)
	bind("SellAll", RateLimiter.new(4, 1), handleSellAll)
	bind("SetLock", RateLimiter.new(10, 5), handleSetLock)
	bind("BuyUpgrade", RateLimiter.new(5, 2), handleBuyUpgrade)
	bind("SkipTutorial", RateLimiter.new(2, 0.2), handleSkipTutorial)
	bind("SaveSettings", RateLimiter.new(3, 0.5), handleSaveSettings)
	bind("BuyDie", RateLimiter.new(3, 1), handleBuyDie)
	bind("EquipDice", RateLimiter.new(6, 2), handleEquipDice)
	bind("UnlockRegion", RateLimiter.new(3, 0.5), handleUnlockRegion)
	bind("Travel", RateLimiter.new(3, 0.5), handleTravel)
	bind("ClaimCollection", RateLimiter.new(4, 1), handleClaimCollection)
	bind("FulfillOrder", RateLimiter.new(4, 1), handleFulfillOrder)
	bind("SkipOrder", RateLimiter.new(3, 0.5), handleSkipOrder)
	bind("Craft", RateLimiter.new(3, 1), handleCraft)
	bind("EquipCosmetic", RateLimiter.new(6, 2), handleEquipCosmetic)
	bind("ClaimDaily", RateLimiter.new(6, 2), handleClaimDaily)
	bind("ClaimMilestone", RateLimiter.new(6, 2), handleClaimMilestone)

	local function onLoaded(player: Player, profile: PlayerData.Profile)
		upkeep(player, profile.Data)
		StateSync.Push(player)
		player.CharacterAdded:Connect(function()
			task.wait(0.5)
			local current = PlayerData.Get(player)
			if current then
				AuraService.Apply(player, current.Data.Cosmetics.Aura)
			end
		end)
		if player.Character then
			AuraService.Apply(player, profile.Data.Cosmetics.Aura)
		end
	end
	PlayerData.Loaded:Connect(onLoaded)
	for _, player in Players:GetPlayers() do
		local profile = PlayerData.Get(player)
		if profile then
			onLoaded(player, profile)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		lastTravel[player] = nil
	end)

	-- Periodic upkeep so new orders and a new day's objectives appear without any action.
	task.spawn(function()
		while true do
			task.wait(UPKEEP_INTERVAL)
			for player, profile in PlayerData.All() do
				if not profile.Released and upkeep(player, profile.Data) then
					StateSync.Push(player)
				end
			end
		end
	end)
end

return Requests

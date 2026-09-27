-- Sends each player a snapshot of their own public state after anything changes.
-- Pushes are coalesced: many changes in one frame produce one send.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Dicebound.Config)
local Net = require(ReplicatedStorage.Dicebound.Net)
local PlayerData = require(script.Parent.PlayerData)
local ActionState = require(script.Parent.ActionState)
local Core = script.Parent.Parent.Core
local Bag = require(Core.Bag)
local Shop = require(Core.Shop)
local Progress = require(Core.Progress)

local StateSync = {}

local pending: { [Player]: boolean } = {}

local function build(player: Player, profile: PlayerData.Profile)
	local data = profile.Data
	local stacks = {}
	for key, stack in data.Bag do
		table.insert(stacks, {
			Key = key,
			Id = stack.Id,
			Mut = stack.Mut,
			Qty = stack.Qty,
			Locked = stack.Locked,
			Seq = stack.Seq,
		})
	end
	local discovered = {}
	local uniqueCount = 0
	for id, entry in data.Discovered do
		discovered[id] = entry.N
		uniqueCount += 1
	end
	local state = ActionState.Get(player)
	return {
		Coins = data.Coins,
		Bag = stacks,
		Used = Bag.Used(data),
		Capacity = Bag.Capacity(data),
		Upgrades = table.clone(data.Upgrades),
		Dice = { Owned = table.clone(data.Dice.Owned), Equipped = table.clone(data.Dice.Equipped) },
		DiceSlots = Config.UpgradeValue("DiceSlots", data.Upgrades.DiceSlots),
		Regions = table.clone(data.Regions),
		Discovered = discovered,
		UniqueDiscovered = uniqueCount,
		MutationsFound = table.clone(data.MutationsFound),
		Stats = table.clone(data.Stats),
		Tutorial = table.clone(data.Tutorial),
		Settings = table.clone(data.Settings),
		SellMultiplier = Shop.SellMultiplier(data),
		Cooldown = Config.UpgradeValue("Speed", data.Upgrades.Speed),
		NextRollIn = math.max(0, state.NextRollAt - os.clock()),
		SaveMode = profile.SaveMode,
		-- Stage 2/3
		Orders = {
			Slots = table.clone(data.Orders.Slots),
			SkipIn = math.max(0, data.Orders.SkipAt - os.time()),
			ServerTime = os.time(),
		},
		Daily = { Day = data.Daily.Day, List = data.Daily.List, ResetIn = 86400 - os.time() % 86400 },
		Milestones = table.clone(data.Milestones),
		Collection = table.clone(data.Collection),
		Cosmetics = {
			Auras = table.clone(data.Cosmetics.Auras),
			Trays = table.clone(data.Cosmetics.Trays),
			Aura = data.Cosmetics.Aura,
			Tray = data.Cosmetics.Tray,
		},
		StatValues = {
			Unique = Progress.StatValue(data, "Unique"),
			Regions = Progress.StatValue(data, "Regions"),
		},
		Claimable = Progress.Claimable(data),
	}
end

local function updateLeaderstats(player: Player, profile: PlayerData.Profile)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		for _, name in { "Coins", "Found" } do
			local value = Instance.new("IntValue")
			value.Name = name
			value.Parent = stats
		end
		stats.Parent = player
	end
	local found = 0
	for _ in profile.Data.Discovered do
		found += 1
	end
	(stats:FindFirstChild("Coins") :: IntValue).Value = profile.Data.Coins;
	(stats:FindFirstChild("Found") :: IntValue).Value = found
end

-- Schedule a state push for this player (end of frame).
function StateSync.Push(player: Player)
	if pending[player] then
		return
	end
	pending[player] = true
	task.defer(function()
		pending[player] = nil
		local profile = PlayerData.Get(player)
		if profile and player.Parent then
			updateLeaderstats(player, profile)
			Net.Events.State:FireClient(player, build(player, profile))
		end
	end)
end

function StateSync.Notify(player: Player, text: string, kind: string?)
	Net.Events.Notify:FireClient(player, text, kind or "info")
end

Players.PlayerRemoving:Connect(function(player)
	pending[player] = nil
end)

return StateSync

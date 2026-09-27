-- Shop purchases and combo rewards.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local PlayerData = require(script.Parent.PlayerData)
local Progression = require(script.Parent.Progression)

local Economy = {}

local lastBank: { [Player]: number } = {}

-- Trails: bought with shards; exclusive ones only come from rewards.
local function handleTrail(player: Player, action: any, itemId: any): (boolean, string)
	local trail = Config.GetTrail(if type(itemId) == "string" then itemId else nil)
	local data = PlayerData.Get(player)
	if not trail or not data then
		return false, "Not available"
	end
	if action == "Buy" then
		if data.OwnedTrails[trail.Id] then
			return false, "Already owned"
		end
		if trail.Exclusive then
			return false, "Unlock with a " .. trail.Exclusive
		end
		if data.Shards < trail.Price then
			return false, "Not enough shards"
		end
		PlayerData.Update(player, function(d)
			d.Shards -= trail.Price
			d.OwnedTrails[trail.Id] = true
			d.EquippedTrail = trail.Id
		end)
		local owned = 0
		for _ in data.OwnedTrails do
			owned += 1
		end
		Progression.Record(player, "TrailsOwned", owned)
		task.spawn(PlayerData.Save, player)
		return true, "Unlocked the " .. trail.Name .. " trail!"
	elseif action == "Equip" then
		if not data.OwnedTrails[trail.Id] then
			return false, "Not owned"
		end
		PlayerData.Update(player, function(d)
			d.EquippedTrail = trail.Id
		end)
		return true, "Equipped " .. trail.Name
	end
	return false, "Unknown action"
end

local function handleShop(player: Player, action: any, itemId: any, category: any): (boolean, string)
	if category == "Trail" then
		return handleTrail(player, action, itemId)
	end
	local item = Config.GetShopItem(if type(itemId) == "string" then itemId else nil)
	local data = PlayerData.Get(player)
	if not item or not data then
		return false, "Not available"
	end
	if action == "Buy" then
		if data.Owned[item.Id] then
			return false, "Already owned"
		end
		if data.Shards < item.Price then
			return false, "Not enough shards"
		end
		PlayerData.Update(player, function(d)
			d.Shards -= item.Price
			d.Owned[item.Id] = true
			d.Equipped = item.Id
		end)
		task.spawn(PlayerData.Save, player)
		return true, "Unlocked " .. item.Name .. "!"
	elseif action == "Equip" then
		if not data.Owned[item.Id] then
			return false, "Not owned"
		end
		PlayerData.Update(player, function(d)
			d.Equipped = item.Id
		end)
		return true, "Equipped " .. item.Name
	end
	return false, "Unknown action"
end

local function handleBank(player: Player, score: any)
	if type(score) ~= "number" or score ~= score then
		return
	end
	local now = os.clock()
	local elapsed = now - (lastBank[player] or 0)
	lastBank[player] = now
	-- A combo can't be worth more than a few points per second of air time.
	score = math.clamp(math.floor(score), 0, math.min(Config.Combo.MaxScore, elapsed * 6 + 4))
	if score < Config.Combo.MinScoreToBank then
		return
	end
	local reward = Config.ComboReward(score)
	if reward > 0 then
		PlayerData.AddShards(player, reward)
		Net.Event("BankCombo"):FireClient(player, reward)
	end
	Progression.AddXP(player, score * Config.Progression.XP.ComboPerPoint)
	Progression.Record(player, "ComboScore", score)
end

function Economy.Start()
	Net.Function("Shop").OnServerInvoke = handleShop
	Net.Event("BankCombo").OnServerEvent:Connect(handleBank)
	Players.PlayerRemoving:Connect(function(player)
		lastBank[player] = nil
	end)
end

return Economy

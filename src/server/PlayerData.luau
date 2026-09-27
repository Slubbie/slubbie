-- Saves shards, owned cosmetics and best trial times with DataStores.
--
-- Values the client needs are mirrored onto Player attributes:
--   Shards (number), Equipped (string), Owned (comma list), Best_<courseId> (seconds)
--
-- In Studio, turn on Game Settings → Security → "Enable Studio Access to API
-- Services" to test saving. Without it, data just lives for the session.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local STORE_NAME = "SkyboundPlayers_v1"
local AUTOSAVE_INTERVAL = 90

type Data = {
	Shards: number,
	Owned: { [string]: boolean },
	Equipped: string,
	Best: { [string]: number },
}

local PlayerData = {}
PlayerData.Loaded = Instance.new("BindableEvent") -- (player)

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[Skybound] DataStores unavailable, progress won't save:", result)
	end
end

local profiles: { [Player]: Data } = {}
-- Players whose saved data failed to load: never overwrite their real save with defaults.
local readOnly: { [Player]: boolean } = {}

local function defaults(): Data
	return {
		Shards = 0,
		Owned = { [Config.Shop.Default] = true },
		Equipped = Config.Shop.Default,
		Best = {},
	}
end

local function key(player: Player): string
	return "player_" .. player.UserId
end

local function mirror(player: Player)
	local data = profiles[player]
	if not data then
		return
	end
	player:SetAttribute("Shards", data.Shards)
	player:SetAttribute("Equipped", data.Equipped)
	local owned = {}
	for id in data.Owned do
		table.insert(owned, id)
	end
	player:SetAttribute("Owned", table.concat(owned, ","))
	for courseId, time in data.Best do
		player:SetAttribute("Best_" .. courseId, time)
	end

	local item = Config.GetShopItem(data.Equipped) or Config.GetShopItem(Config.Shop.Default)
	player:SetAttribute("RopeColor", item.Color)
	player:SetAttribute("Rainbow", item.Rainbow == true)

	local stats = player:FindFirstChild("leaderstats")
	local shards = stats and stats:FindFirstChild("Shards")
	if shards and shards:IsA("IntValue") then
		shards.Value = data.Shards
	end
end

local function load(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local shards = Instance.new("IntValue")
	shards.Name = "Shards"
	shards.Parent = leaderstats
	leaderstats.Parent = player

	local data = defaults()
	if store and player.UserId > 0 then
		local ok, saved
		for attempt = 1, 3 do
			ok, saved = pcall(function()
				return (store :: DataStore):GetAsync(key(player))
			end)
			-- In Studio a failure usually means API access is off: don't wait around.
			if ok or RunService:IsStudio() then
				break
			end
			task.wait(attempt)
		end
		if not ok then
			warn("[Skybound] Couldn't load data for", player.Name, "- progress this session won't save.")
			readOnly[player] = true
		elseif type(saved) == "table" then
			data.Shards = tonumber(saved.Shards) or 0
			data.Equipped = if type(saved.Equipped) == "string" then saved.Equipped else data.Equipped
			if type(saved.Owned) == "table" then
				for id, owned in saved.Owned do
					data.Owned[id] = owned == true
				end
			end
			if type(saved.Best) == "table" then
				for courseId, time in saved.Best do
					data.Best[courseId] = tonumber(time)
				end
			end
		end
	end
	if not player.Parent then
		return
	end
	profiles[player] = data
	mirror(player)
	PlayerData.Loaded:Fire(player)
end

function PlayerData.Save(player: Player)
	local data = profiles[player]
	if not data or not store or readOnly[player] or player.UserId <= 0 then
		return
	end
	local ok, err = pcall(function()
		(store :: DataStore):SetAsync(key(player), data)
	end)
	if not ok then
		warn("[Skybound] Save failed for", player.Name, err)
	end
end

function PlayerData.Get(player: Player): Data?
	return profiles[player]
end

function PlayerData.AddShards(player: Player, amount: number)
	local data = profiles[player]
	if data then
		data.Shards = math.max(data.Shards + amount, 0)
		mirror(player)
	end
end

function PlayerData.Update(player: Player, change: (Data) -> ())
	local data = profiles[player]
	if data then
		change(data)
		mirror(player)
	end
end

function PlayerData.Start()
	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		PlayerData.Save(player)
		profiles[player] = nil
		readOnly[player] = nil
	end)
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			task.spawn(PlayerData.Save, player)
		end
		task.wait(2)
	end)
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for _, player in Players:GetPlayers() do
				task.spawn(PlayerData.Save, player)
			end
		end
	end)
end

return PlayerData

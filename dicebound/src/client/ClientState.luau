-- The client's copy of its own state (sent by the server) plus local UI preferences.
-- The server is the authority: this only mirrors what it sends.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Dicebound.Config)
local Net = require(ReplicatedStorage.Dicebound.Net)
local Signal = require(ReplicatedStorage.Dicebound.Signal)

local ClientState = {}

ClientState.Data = nil :: any
ClientState.Changed = Signal.new() -- (data)
ClientState.SettingsChanged = Signal.new() -- (settings)
ClientState.Ready = false

-- Local settings: start from the saved ones, then the player's edits win.
ClientState.Settings = { Music = 0.5, Sfx = 0.8, ReducedMotion = false, SkipReveals = false }
local settingsLoaded = false

Net.Events.State.OnClientEvent:Connect(function(data)
	ClientState.Data = data
	if not settingsLoaded and type(data.Settings) == "table" then
		settingsLoaded = true
		for k, v in data.Settings do
			ClientState.Settings[k] = v
		end
		ClientState.SettingsChanged:Fire(ClientState.Settings)
	end
	ClientState.Ready = true
	ClientState.Changed:Fire(data)
end)

-- Change a setting locally now; save to the server after a short pause (debounced).
local saveToken = 0
function ClientState.SetSetting(name: string, value: any)
	ClientState.Settings[name] = value
	ClientState.SettingsChanged:Fire(ClientState.Settings)
	saveToken += 1
	local token = saveToken
	task.delay(1.5, function()
		if token == saveToken then
			Net.Functions.SaveSettings:InvokeServer(ClientState.Settings)
		end
	end)
end

-- Invoke a request safely: always returns a result table, even if the call errors.
function ClientState.Request(name: string, ...: any): { [string]: any }
	local ok, result = pcall(Net.Functions[name].InvokeServer, Net.Functions[name], ...)
	if not ok or type(result) ~= "table" then
		return { ok = false, err = "Connection problem. Please try again." }
	end
	return result
end

-- Helpers derived from the current state ------------------------------------------------------

function ClientState.UpgradeLevel(id: string): number
	local data = ClientState.Data
	return data and data.Upgrades[id] or 0
end

-- Cheapest next upgrade level that isn't maxed (for goals and the tutorial).
function ClientState.CheapestUpgrade(): ({ [string]: any }?, number?)
	local best, bestCost
	for _, upgrade in Config.Economy.Upgrades.List do
		if Config.IsLive(upgrade) then
			local nextLevel = upgrade.Levels[ClientState.UpgradeLevel(upgrade.Id) + 2]
			if nextLevel and (not bestCost or nextLevel.Cost < bestCost) then
				best, bestCost = upgrade, nextLevel.Cost
			end
		end
	end
	return best, bestCost
end

function ClientState.DiscoveredIn(regionId: string): (number, number)
	local data = ClientState.Data
	local found, total = 0, 0
	for _, item in Config.ItemsIn(regionId) do
		total += 1
		if data and data.Discovered[item.Id] then
			found += 1
		end
	end
	return found, total
end

local Players = game:GetService("Players")

local function rootPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function worldPos(region, rel: { number }): Vector3
	local o = region.Origin
	return Vector3.new(o[1] + rel[1], o[2] + rel[2], o[3] + rel[3])
end
ClientState.WorldPosition = worldPos

-- The live region the character stands in (display only; the server decides for real).
function ClientState.CurrentRegion()
	local pos = rootPosition()
	if not pos then
		return nil
	end
	for _, region in Config.Regions.List do
		if Config.IsLive(region) and Config.Regions.Contains(region, pos.X, pos.Y, pos.Z) then
			return region
		end
	end
	return nil
end

-- The region whose merchant is close enough to sell (slightly stricter than the server check).
function ClientState.NearMerchant()
	local pos = rootPosition()
	if not pos then
		return nil
	end
	for _, region in Config.Regions.List do
		if Config.IsLive(region) and region.Merchant then
			if (pos - worldPos(region, region.Merchant.Position)).Magnitude <= Config.Game.MerchantRange - 2 then
				return region
			end
		end
	end
	return nil
end

-- The running world event (published by the server as ReplicatedStorage attributes), or nil.
function ClientState.Event(): { Id: string, Region: string, EndsIn: number }?
	local id = ReplicatedStorage:GetAttribute("DB_EventId")
	local region = ReplicatedStorage:GetAttribute("DB_EventRegion")
	local ends = ReplicatedStorage:GetAttribute("DB_EventEnds")
	if type(id) ~= "string" or id == "" or type(ends) ~= "number" then
		return nil
	end
	local left = ends - workspace:GetServerTimeNow()
	if left <= 0 then
		return nil
	end
	return { Id = id, Region = region, EndsIn = left }
end

return ClientState

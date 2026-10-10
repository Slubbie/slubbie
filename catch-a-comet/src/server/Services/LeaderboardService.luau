-- Player-list stats (Stardust, Species) and the hub's "Top Collectors"
-- monument for the current server. Global leaderboards (OrderedDataStore)
-- are planned with the social update.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Loop = require(Shared.Loop)

local LeaderboardService = { Name = "LeaderboardService" }

local services: { [string]: any } = {}
local stats: { [Player]: { Stardust: StringValue, Species: IntValue } } = {}

local function speciesCount(profile: any): number
	local n = 0
	for _ in profile.DiscoveredSpecies do
		n += 1
	end
	return n
end

local function update(player: Player)
	local profile = services.PlayerDataService.GetProfile(player)
	local values = stats[player]
	if not profile or not values then
		return
	end
	values.Stardust.Value = Format.Short(profile.Stardust)
	values.Species.Value = speciesCount(profile)
end

local function create(player: Player)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local stardust = Instance.new("StringValue")
	stardust.Name = "Stardust"
	stardust.Parent = folder
	local species = Instance.new("IntValue")
	species.Name = "Species"
	species.Parent = folder
	folder.Parent = player
	stats[player] = { Stardust = stardust, Species = species }
	update(player)
end

function LeaderboardService.RefreshMonument()
	local hub = services.WorldService.Hub
	if not hub then
		return
	end
	local entries = {}
	for _, player in Players:GetPlayers() do
		local profile = services.PlayerDataService.GetProfile(player)
		if profile then
			table.insert(entries, {
				Name = player.DisplayName,
				Species = speciesCount(profile),
				Earned = profile.Stats.StardustEarned or 0,
			})
		end
	end
	table.sort(entries, function(a, b)
		if a.Species ~= b.Species then
			return a.Species > b.Species
		end
		return a.Earned > b.Earned
	end)
	for i, row in hub.LeaderboardRows do
		local entry = entries[i]
		row.Text = if entry
			then `{i}. {entry.Name}  ·  {entry.Species} species  ·  {Format.Short(entry.Earned)} ✦`
			else ""
	end
end

function LeaderboardService.Init(registry: { [string]: any })
	services = registry
end

function LeaderboardService.Start()
	services.PlayerDataService.ProfileLoaded:Connect(create)
	Players.PlayerRemoving:Connect(function(player)
		stats[player] = nil
	end)
	services.EconomyService.Granted:Connect(update)
	services.EconomyService.Spent:Connect(update)
	services.CreatureService.CreatureObtained:Connect(update)
	LeaderboardService.RefreshMonument()
	Loop.Every(10, "Leaderboard", LeaderboardService.RefreshMonument)
end

return LeaderboardService

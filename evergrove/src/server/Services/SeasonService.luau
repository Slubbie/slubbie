-- Season changes: announcements, dormancy notices and seasonal hooks.
--
-- Crops never die when the season turns (Config.Crops.OffSeasonGrowth keeps
-- them alive but dormant outdoors), so this only informs players and lets
-- other systems (shops, NPC schedules, decorations) react via SeasonChanged.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Seasons = require(Shared.Config.Seasons)
local GameTime = require(Shared.Lib.GameTime)
local Registry = require(Shared.Lib.Registry)
local CropMath = require(Shared.Lib.CropMath)

local S = require(script.Parent)

local SeasonService = {}

function SeasonService.Current()
	return Seasons[GameTime.Info().Season]
end

local function dormantCount(player: Player, seasonId: string): number
	local profile = S.Data.Get(player)
	if not profile then
		return 0
	end
	local count = 0
	for key, tile in profile.Farm.Tiles do
		local cs = tile.C
		if cs then
			local crop = Registry.Crops[cs.Id]
			local env = S.Farm.EnvFor(player, key)
			if crop and not CropMath.InSeason(crop, seasonId) and not (env and env.Indoor) then
				count += 1
			end
		end
	end
	return count
end

local function announce(info)
	local season = Seasons[info.Season]
	S.Notify.BannerAll(season.Icon .. "  " .. season.Name .. " has arrived", season.Flavor, "Season")
	for player in S.Data.All() do
		local dormant = dormantCount(player, season.Id)
		if dormant > 0 then
			S.Notify.Toast(
				player,
				string.format(
					"%d of your crops are out of season and have gone dormant. A greenhouse keeps them growing.",
					dormant
				),
				"Warning"
			)
		end
	end
	ReplicatedStorage:SetAttribute("Season", season.Id)
end

function SeasonService.Init()
	ReplicatedStorage:SetAttribute("Season", SeasonService.Current().Id)
end

function SeasonService.Start()
	S.Time.SeasonChanged:Connect(announce)
	S.Time.Anchored:Connect(function()
		ReplicatedStorage:SetAttribute("Season", SeasonService.Current().Id)
	end)
end

return SeasonService

-- Passive Stardust from deployed creatures, and offline earnings.
--
-- One loop for the whole server: every tick each player earns
-- rate × elapsed, with the fractional part carried over so nothing is lost
-- to rounding. Rates are cached and recalculated only when habitats change.
-- The client never reports earnings; it only animates the number between
-- server updates.
--
-- Offline: on join, a share of the sanctuary rate for the time away (server
-- clock only, capped), granted once per absence.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyMath = require(Shared.EconomyMath)
local GameConfig = require(Shared.GameConfig)
local Loop = require(Shared.Loop)
local Signal = require(Shared.Signal)

local IncomeService = { Name = "IncomeService" }

-- (player, ratePerSecond)
IncomeService.RateChanged = Signal.new()
-- (player, amount)
IncomeService.PassiveIncome = Signal.new()

IncomeService.Clock = os.clock

local services: { [string]: any } = {}
local rates: { [Player]: number } = {}

-- Phase 4 (Ascension) adds a capped permanent bonus here.
local function progressionBonus(_profile: any): number
	return 1
end

function IncomeService.GetRate(player: Player): number
	return rates[player] or 0
end

function IncomeService.Recalculate(player: Player): number
	local profile = services.PlayerDataService.GetProfile(player)
	if not profile then
		return 0
	end
	local rate = EconomyMath.SanctuaryIncome(profile.Creatures, profile.EquippedCreatures, progressionBonus(profile))
	if rates[player] ~= rate then
		rates[player] = rate
		services.ReplicationService.SetSession(player, "IncomeRate", rate)
		IncomeService.RateChanged:Fire(player, rate)
	end
	return rate
end

-- Pays every player for `dt` seconds of production.
function IncomeService.Tick(dt: number)
	for player, rate in rates do
		if rate <= 0 then
			continue
		end
		local profile = services.PlayerDataService.GetProfile(player)
		if not profile then
			continue
		end
		local total = profile.IncomeRemainder + rate * dt
		local whole = math.floor(total)
		profile.IncomeRemainder = total - whole
		if whole > 0 then
			services.EconomyService.Grant(player, "Stardust", whole, "Passive")
			IncomeService.PassiveIncome:Fire(player, whole)
		end
	end
end

-- Grants offline earnings for the absence before this session. Returns (amount, seconds counted).
function IncomeService.ApplyOffline(player: Player, session: any): (number, number)
	if session.IsNew or not session.Persistent or session.PreviousLastSeen <= 0 then
		return 0, 0
	end
	local away = services.PlayerDataService.Now() - session.PreviousLastSeen
	if away <= 0 then
		return 0, 0
	end
	local rate = IncomeService.Recalculate(player)
	local amount, counted = EconomyMath.OfflineEarnings(rate, away)
	if amount > 0 then
		services.EconomyService.Grant(player, "Stardust", amount, "Offline")
		services.ReplicationService.Notify(player, "OfflineEarnings", {
			Amount = amount,
			Seconds = counted,
			Away = away,
			Capped = away > GameConfig.Income.OfflineMaxSeconds,
		})
	end
	return amount, counted
end

function IncomeService.Init(registry: { [string]: any })
	services = registry
end

function IncomeService.Start()
	services.PlayerDataService.ProfileLoaded:Connect(function(player, _profile, session)
		IncomeService.Recalculate(player)
		IncomeService.ApplyOffline(player, session)
	end)
	local function recalc(player)
		IncomeService.Recalculate(player)
	end
	services.SanctuaryService.CreatureDeployed:Connect(recalc)
	services.SanctuaryService.CreatureWithdrawn:Connect(recalc)
	services.CreatureService.CreatureReleased:Connect(recalc)
	Players.PlayerRemoving:Connect(function(player)
		rates[player] = nil
	end)
	local last = IncomeService.Clock()
	Loop.Every(GameConfig.Income.TickInterval, "Income", function()
		local now = IncomeService.Clock()
		IncomeService.Tick(math.min(now - last, 5))
		last = now
	end)
end

return IncomeService

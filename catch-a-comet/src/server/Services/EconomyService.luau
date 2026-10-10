-- The only code that changes currency balances.
--
-- Grant and Spend never yield, so each call is atomic: a Spend either
-- deducts the full amount or changes nothing. Amounts must be whole,
-- finite and non-negative; anything else is refused and logged.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Signal)

local EconomyService = { Name = "EconomyService" }

-- (player, currency, amount, source)
EconomyService.Granted = Signal.new()
-- (player, currency, amount, sink)
EconomyService.Spent = Signal.new()

local CURRENCIES = { Stardust = true, MeteorShards = true }

local services: { [string]: any } = {}

local function validAmount(amount: any): boolean
	return type(amount) == "number"
		and amount == amount
		and amount >= 0
		and amount < math.huge
		and amount == math.floor(amount)
end

function EconomyService.Get(player: Player, currency: string): number
	local profile = services.PlayerDataService.GetProfile(player)
	if not profile or not CURRENCIES[currency] then
		return 0
	end
	return (profile :: any)[currency]
end

function EconomyService.CanAfford(player: Player, currency: string, amount: number): boolean
	return validAmount(amount) and EconomyService.Get(player, currency) >= amount
end

-- Adds currency. `source` is a short label for analytics ("Capture", "Passive"…).
function EconomyService.Grant(player: Player, currency: string, amount: number, source: string): boolean
	local profile = services.PlayerDataService.GetProfile(player)
	if not profile or not CURRENCIES[currency] then
		return false
	end
	if not validAmount(amount) then
		warn(`[Economy] Refused grant of {tostring(amount)} {currency} to {player.Name} ({source})`)
		return false
	end
	if amount == 0 then
		return true
	end
	local p = profile :: any
	p[currency] += amount
	if currency == "Stardust" then
		p.Stats.StardustEarned = (p.Stats.StardustEarned or 0) + amount
	end
	services.ReplicationService.Set(player, { currency }, p[currency])
	EconomyService.Granted:Fire(player, currency, amount, source)
	if source == "Passive" then
		services.AnalyticsService.AccumulatePassive(player, amount)
	else
		services.AnalyticsService.Economy(player, "Source", currency, amount, p[currency], "Gameplay", source)
	end
	return true
end

-- Deducts currency if the player can afford it. Returns false (and changes nothing) otherwise.
function EconomyService.Spend(player: Player, currency: string, amount: number, sink: string): boolean
	local profile = services.PlayerDataService.GetProfile(player)
	if not profile or not CURRENCIES[currency] or not validAmount(amount) then
		return false
	end
	local p = profile :: any
	if p[currency] < amount then
		return false
	end
	if amount == 0 then
		return true
	end
	p[currency] -= amount
	services.ReplicationService.Set(player, { currency }, p[currency])
	EconomyService.Spent:Fire(player, currency, amount, sink)
	services.AnalyticsService.Economy(player, "Sink", currency, amount, p[currency], "Gameplay", sink)
	return true
end

function EconomyService.Init(registry: { [string]: any })
	services = registry
end

function EconomyService.Start() end

return EconomyService

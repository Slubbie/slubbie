-- Telemetry, through Roblox's AnalyticsService. Every call is wrapped so a
-- telemetry failure can never break gameplay. Records only gameplay events:
-- no chat, no personal information.
--
-- Onboarding funnel steps mirror the tutorial: 1 = joined … 8 = tutorial done.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loop = require(ReplicatedStorage:WaitForChild("Shared").Loop)

local AnalyticsService = { Name = "AnalyticsService" }

AnalyticsService.Enabled = true

local roblox: any = nil
local passive: { [Player]: number } = {}
local milestones: { [Player]: { [string]: boolean } } = {}

local function call(method: string, ...: any)
	if not AnalyticsService.Enabled or not roblox then
		return
	end
	local args = table.pack(...)
	task.spawn(function()
		local ok, err = pcall(function()
			roblox[method](roblox, table.unpack(args, 1, args.n))
		end)
		if not ok then
			warn(`[Analytics] {method} failed: {err}`)
		end
	end)
end

function AnalyticsService.Funnel(player: Player, step: number, stepName: string)
	call("LogOnboardingFunnelStepEvent", player, step, stepName)
end

-- flow: "Source" | "Sink"
function AnalyticsService.Economy(
	player: Player,
	flow: string,
	currency: string,
	amount: number,
	balance: number,
	transactionType: string,
	sku: string?
)
	if amount <= 0 or not roblox then
		return
	end
	local ok, flowType = pcall(function()
		return (Enum.AnalyticsEconomyFlowType :: any)[flow]
	end)
	if ok and flowType then
		call("LogEconomyEvent", player, flowType, currency, amount, balance, transactionType, sku)
	end
end

-- Passive income ticks every second; report it once a minute instead.
function AnalyticsService.AccumulatePassive(player: Player, amount: number)
	passive[player] = (passive[player] or 0) + amount
end

function AnalyticsService.Progression(player: Player, level: number)
	call("LogProgressionCompleteEvent", player, "PlayerLevel", level)
end

function AnalyticsService.Custom(player: Player, eventName: string, value: number?)
	call("LogCustomEvent", player, eventName, value or 1)
end

-- Logs a once-per-session milestone like "FirstCapture".
function AnalyticsService.Milestone(player: Player, name: string)
	local seen = milestones[player]
	if not seen then
		seen = {}
		milestones[player] = seen
	end
	if seen[name] then
		return
	end
	seen[name] = true
	AnalyticsService.Custom(player, name)
end

local services: { [string]: any } = {}

function AnalyticsService.Init(registry: { [string]: any })
	services = registry
	local ok, result = pcall(function()
		return game:GetService("AnalyticsService")
	end)
	roblox = if ok then result else nil
end

function AnalyticsService.Start()
	Players.PlayerRemoving:Connect(function(player)
		local profile = services.PlayerDataService and services.PlayerDataService.GetProfile(player)
		local pending = passive[player]
		if pending and pending > 0 and profile then
			AnalyticsService.Economy(player, "Source", "Stardust", pending, profile.Stardust, "Gameplay", "Passive")
		end
		AnalyticsService.Custom(player, "SessionEnded")
		passive[player] = nil
		milestones[player] = nil
	end)
	Loop.Every(60, "PassiveAnalytics", function()
		for player, amount in passive do
			local profile = services.PlayerDataService.GetProfile(player)
			if profile and amount > 0 then
				AnalyticsService.Economy(player, "Source", "Stardust", amount, profile.Stardust, "Gameplay", "Passive")
			end
			passive[player] = 0
		end
	end)
end

return AnalyticsService

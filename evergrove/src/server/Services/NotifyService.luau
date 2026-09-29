-- Sends player-facing notifications (the client NotificationController decides
-- how each kind looks: toasts, banners, reward pops, reveals).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Lib.Net)

local NotifyService = {}

-- kind: "Info" | "Success" | "Warning" | "Error"
function NotifyService.Toast(player: Player, text: string, kind: string?)
	Net.Fire(player, "Notify", "Toast", { Text = text, Kind = kind or "Info" })
end

function NotifyService.Error(player: Player, text: string)
	NotifyService.Toast(player, text, "Error")
end

-- Big centred banner (quest complete, festival start...).
function NotifyService.Banner(player: Player, title: string, subtitle: string?, style: string?, icon: string?)
	Net.Fire(
		player,
		"Notify",
		"Banner",
		{ Title = title, Subtitle = subtitle, Style = style or "Default", Icon = icon }
	)
end

function NotifyService.BannerAll(title: string, subtitle: string?, style: string?, icon: string?)
	Net.FireAll("Notify", "Banner", { Title = title, Subtitle = subtitle, Style = style or "Default", Icon = icon })
end

-- Items/coins gained: animated pops that fly to the inventory/currency.
-- items: { { Id, N, Q?, M? } }
function NotifyService.Reward(player: Player, items: { any }?, coins: number?, source: string?, position: Vector3?)
	Net.Fire(
		player,
		"Notify",
		"Reward",
		{ Items = items or {}, Coins = coins or 0, Source = source, Position = position }
	)
end

function NotifyService.Coins(player: Player, amount: number, reason: string?)
	Net.Fire(player, "Notify", "Coins", { Amount = amount, Reason = reason })
end

-- First-time discovery (collection book): brief reveal; Legendary = dramatic.
function NotifyService.Discovery(player: Player, category: string, id: string, extra: { [string]: any }?)
	local payload = { Category = category, Id = id }
	for k, v in pairs(extra or {}) do
		payload[k] = v
	end
	Net.Fire(player, "Notify", "Discovery", payload)
end

function NotifyService.LevelUp(player: Player, skill: string, level: number, rewards: { [string]: any }?)
	Net.Fire(player, "Notify", "LevelUp", { Skill = skill, Level = level, Rewards = rewards })
end

function NotifyService.Achievement(player: Player, id: string)
	Net.Fire(player, "Notify", "Achievement", { Id = id })
end

function NotifyService.Quest(player: Player, event: string, questId: string, extra: { [string]: any }?)
	local payload = { Event = event, Id = questId }
	for k, v in pairs(extra or {}) do
		payload[k] = v
	end
	Net.Fire(player, "Notify", "Quest", payload)
end

-- World feedback at a position (harvest popups, sparkles...), sent to players nearby.
function NotifyService.FX(position: Vector3, kind: string, payload: { [string]: any }, radius: number?)
	payload.Position = position
	Net.FireNearby(position, radius or 180, "FX", kind, payload)
end

function NotifyService.FXPlayer(player: Player, kind: string, payload: { [string]: any })
	Net.Fire(player, "FX", kind, payload)
end

return NotifyService

-- Player-facing notifications (toasts, banners, unlock cards).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local Notify = {}

export type Payload = {
	Kind: string, -- Toast | LevelUp | Rank | Ability | Item | Achievement | Mastery | Quest | Reward | Discovery | Warning | Unlock
	Title: string,
	Text: string?,
	Icon: string?,
	Color: Color3?,
	XP: number?,
	Credits: number?,
	Prestige: number?,
	Item: string?,
	Sound: string?,
}

function Notify.Send(player: Player, payload: Payload)
	Net.Push(player, "Notify", payload)
end

function Notify.Toast(player: Player, title: string, text: string?, icon: string?)
	Net.Push(player, "Notify", { Kind = "Toast", Title = title, Text = text, Icon = icon })
end

function Notify.Warn(player: Player, text: string)
	Net.Push(player, "Notify", { Kind = "Warning", Title = text })
end

return Notify

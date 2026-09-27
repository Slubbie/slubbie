-- Manual and auto rolling. The client asks; the server decides and returns the result; the
-- client then animates exactly that result. Auto-roll uses the very same request, so it obeys
-- the same cooldown, bag space and validation (and needs the Auto-Roller upgrade server-side).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Dicebound.Config)
local Format = require(ReplicatedStorage.Dicebound.Format)
local LootMath = require(ReplicatedStorage.Dicebound.LootMath)
local ClientState = require(script.Parent.Parent.ClientState)
local Sound = require(script.Parent.Parent.Sound)
local Toasts = require(script.Parent.Parent.UI.Toasts)

local RollController = {}

local hud
local reveal
local rolling = false
local readyAt = 0
local autoOn = false
local autoToken = 0

local function bagHasRoom(): boolean
	local data = ClientState.Data
	if not data then
		return false
	end
	return data.Capacity - data.Used >= LootMath.MaxRewardUnits(#data.Dice.Equipped)
end

function RollController.SetAuto(on: boolean)
	local data = ClientState.Data
	local unlocked = data ~= nil and data.Upgrades.AutoRoll > 0
	if on and not unlocked then
		Toasts.Show("Unlock the Auto-Roller in 🔧 Upgrades first.", "info")
		on = false
	end
	autoOn = on
	autoToken += 1
	hud.SetAuto(unlocked, autoOn)
	if autoOn then
		local token = autoToken
		task.spawn(function()
			while autoOn and token == autoToken do
				if not rolling and os.clock() >= readyAt then
					RollController.Roll(true)
				end
				task.wait(0.1)
			end
		end)
	end
end

function RollController.Roll(auto: boolean?)
	if rolling or not ClientState.Ready then
		return
	end
	if os.clock() < readyAt then
		return
	end
	if not bagHasRoom() then
		Sound.Play("Error")
		Toasts.Show("Your bag is full! Sell treasure at a merchant stall.", "error")
		if autoOn then
			RollController.SetAuto(false)
			Toasts.Show("Auto-roll paused: bag full.", "info")
		end
		return
	end

	rolling = true
	local tray = hud.Tray
	tray:Windup()
	Sound.Play("Windup")
	local sentAt = os.clock()
	local result = ClientState.Request("Roll", auto == true)
	if not result.ok then
		tray:Settle()
		rolling = false
		if result.code == "Cooldown" then
			readyAt = os.clock() + 0.2
			return
		end
		Sound.Play("Error")
		Toasts.Show(result.err or "Couldn't roll.", "error")
		if autoOn then
			RollController.SetAuto(false)
		end
		return
	end

	-- The server started the cooldown when it accepted the roll (about half a round trip ago).
	local halfTrip = (os.clock() - sentAt) / 2
	readyAt = os.clock() + result.Cooldown - halfTrip
	hud.StartCooldown(math.max(result.Cooldown - halfTrip, 0))
	tray:SetDice(result.DiceIds)
	tray:Throw(result.Faces, function()
		Sound.Play("Land")
	end)
	if result.Combo then
		local rule = Config.Economy.Combos[result.Combo]
		tray:ShowCombo(rule and rule.Label or result.Combo)
		Sound.Play("Combo")
	end
	if result.Coins and result.Coins > 0 then
		Toasts.Show("Jackpot bonus: 🪙 " .. Format.Coins(result.Coins), "reward")
	end
	for _, reward in result.Rewards do
		reveal:Show(reward)
	end
	rolling = false
end

function RollController.Start(hudObject, revealObject)
	hud = hudObject
	reveal = revealObject
	ClientState.Changed:Connect(function(data)
		hud.SetAuto(data.Upgrades.AutoRoll > 0, autoOn)
	end)
end

function RollController.ToggleAuto()
	RollController.SetAuto(not autoOn)
end

return RollController

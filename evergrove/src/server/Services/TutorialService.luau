-- The guided tutorial (Config/Tutorial).
--
-- Each step waits for a real, server-confirmed game event (Till, Plant, Water,
-- Refill, Fertilize, Ripe, Harvest, Store, Sell, Buy) or an acknowledgement
-- ("Ack" steps, TutorialAck). Services report events with
-- TutorialService.Event(player, name, count?). Players can skip at any time
-- and still receive the starter reward.
--
-- New farms get a starter chest next to the house (for the Storage step), and
-- while the tutorial waits for the first harvest to ripen, Mabel's "magic
-- compost" speeds the player's crops up by the step's Boost.
--
-- profile.Tutorial = { Step, Count, Done, Skipped? }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tutorial = require(Shared.Config.Tutorial)
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local ItemUtil = require(Shared.Lib.ItemUtil)

local S = require(script.Parent)

local BOOST_TICK = 3
local STARTER_CHEST = { X = 90, Z = -30, R = 0 } -- lot-local studs, beside the farmhouse

local TutorialService = {}

local function current(profile: any): any?
	local t = profile.Tutorial
	if t.Done then
		return nil
	end
	return Tutorial.Steps[t.Step]
end

local function finish(player: Player, profile: any, skipped: boolean)
	local t = profile.Tutorial
	if t.Done then
		return
	end
	t.Done = true
	t.Skipped = skipped or nil
	S.Data.Changed(player, "Tutorial")
	local items = {}
	for _, entry in Tutorial.RewardItems do
		table.insert(items, entry)
	end
	S.Economy.GrantReward(player, { Coins = Tutorial.RewardCoins, Items = items }, "Tutorial")
	S.Quest.Refresh(player)
	if not skipped then
		S.Notify.Banner(
			player,
			"Tutorial complete!",
			"The valley is yours to explore. Mabel left you a little gift.",
			"Tutorial",
			"🌱"
		)
	end
end

local function advance(player: Player, profile: any)
	local t = profile.Tutorial
	t.Step += 1
	t.Count = 0
	if t.Step > #Tutorial.Steps then
		finish(player, profile, false)
		return
	end
	S.Data.Changed(player, "Tutorial")
	local step = Tutorial.Steps[t.Step]
	Net.Fire(player, "Notify", "Tutorial", { Step = t.Step, Id = step.Id })
	-- Some steps may already be satisfied (e.g. crops already ripe).
	if step.Wait == "Ripe" then
		for _, tile in profile.Farm.Tiles do
			if tile.C and (tile.C.P or 0) >= 1 then
				TutorialService.Event(player, "Ripe")
				break
			end
		end
	end
end

-- Report a gameplay event for the tutorial.
function TutorialService.Event(player: Player, name: string, count: number?)
	local profile = S.Data.Get(player)
	if not profile then
		return
	end
	local step = current(profile)
	if not step or step.Wait ~= name then
		return
	end
	local t = profile.Tutorial
	t.Count = (t.Count or 0) + (count or 1)
	if t.Count >= (step.Count or 1) then
		advance(player, profile)
	else
		S.Data.Changed(player, "Tutorial")
	end
end

local function ack(player: Player, stepId: string)
	local profile = S.Data.Get(player)
	local step = profile and current(profile)
	if not step or step.Id ~= stepId then
		return false
	end
	if step.Wait ~= "Ack" then
		return false, "Finish this step first"
	end
	advance(player, profile)
	return true
end

local function skip(player: Player)
	local profile = S.Data.Get(player)
	if not profile or profile.Tutorial.Done then
		return false
	end
	finish(player, profile, true)
	return true
end

-- The starter chest for the Storage step.
local function ensureStarterChest(player: Player, profile: any)
	if profile.Unlocks.StarterChest then
		return
	end
	for _, record in profile.Farm.Placed do
		if record.Id == "chest" then
			profile.Unlocks.StarterChest = true
			return
		end
	end
	local uid = S.Building.Grant(player, "chest", STARTER_CHEST)
	if uid then
		profile.Unlocks.StarterChest = true
		S.Data.Changed(player, "Unlocks")
		-- A few carrots in it to make storage obvious.
		S.Inventory.AddTo(player, "chest:" .. uid, ItemUtil.New("seed_carrot", 4))
	end
end

function TutorialService.Init()
	Net.Handle("TutorialAck", ack)
	Net.Handle("TutorialSkip", skip)
end

function TutorialService.Start()
	S.Farm.Ready:Connect(function(player)
		local profile = S.Data.Get(player)
		if profile and not profile.Tutorial.Done then
			ensureStarterChest(player, profile)
			local step = current(profile)
			if step then
				Net.Fire(player, "Notify", "Tutorial", { Step = profile.Tutorial.Step, Id = step.Id })
			end
		end
	end)
	-- Mabel's magic compost: speed crops up while waiting for the first harvest.
	local carrot = Registry.Crops.carrot
	local baseGrow = if carrot then carrot.Grow else 180
	task.spawn(function()
		while true do
			task.wait(BOOST_TICK)
			for _, player in Players:GetPlayers() do
				local profile = S.Data.Get(player)
				local step = profile and current(profile)
				if step and step.Boost and step.Wait == "Ripe" then
					S.Crop.GrowAll(player, BOOST_TICK * step.Boost / baseGrow)
					for _, tile in profile.Farm.Tiles do
						if tile.C and (tile.C.P or 0) >= 1 then
							TutorialService.Event(player, "Ripe")
							break
						end
					end
				end
			end
		end
	end)
end

return TutorialService

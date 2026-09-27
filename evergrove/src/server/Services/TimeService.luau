-- The world clock (see Lib/GameTime). Publishes the clock anchor on
-- ReplicatedStorage and fires signals at hour, dawn, day, weather-slot and
-- season boundaries that other services schedule work on.
--
-- Private servers with a single player can slow time while that player has
-- a blocking menu open (Config.Time.SoloSlowdown + the player's setting).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local TimeConfig = require(Shared.Config.Time)
local GameTime = require(Shared.Lib.GameTime)
local Signal = require(Shared.Lib.Signal)
local Net = require(Shared.Lib.Net)

local S = require(script.Parent)

local TimeService = {}
TimeService.Hour = Signal.new() -- (info)
TimeService.Dawn = Signal.new() -- (info) 06:00 every day
TimeService.NewDay = Signal.new() -- (info) midnight
TimeService.Slot = Signal.new() -- (slot, info) weather slot changed
TimeService.SeasonChanged = Signal.new() -- (info)
TimeService.Anchored = Signal.new() -- () clock was re-anchored (debug/slowdown)

local menuOpen: { [Player]: boolean } = {}

local function anchor(base: number, scale: number)
	ReplicatedStorage:SetAttribute("ClockBase", base)
	ReplicatedStorage:SetAttribute("ClockAnchor", GameTime.ServerNow())
	ReplicatedStorage:SetAttribute("ClockScale", scale)
	TimeService.Anchored:Fire()
end

function TimeService.Now(): number
	return GameTime.Now()
end

function TimeService.Info()
	return GameTime.Info()
end

-- Debug: jump the clock by `seconds` of game time (can be negative).
function TimeService.Skip(seconds: number)
	anchor(GameTime.Now() + seconds, GameTime.Scale())
end

-- Debug: set the clock to an hour today (0-24).
function TimeService.SetHour(hour: number)
	local now = GameTime.Now()
	local dayStart = GameTime.DayIndex(now) * GameTime.DAY
	anchor(dayStart + (hour % 24) * GameTime.HOUR, GameTime.Scale())
end

-- Debug: jump to day 1 of a season (1-4), keeping the hour.
function TimeService.SetSeason(seasonIndex: number)
	local now = GameTime.Now()
	local info = GameTime.Info(now)
	local yearStart = info.Day - info.Day % GameTime.YEAR_DAYS
	local day = yearStart + (math.clamp(seasonIndex, 1, 4) - 1) * GameTime.SEASON_DAYS
	anchor(day * GameTime.DAY + info.Hour * GameTime.HOUR, GameTime.Scale())
end

-- Back to the global clock (public servers only use this).
function TimeService.ResetToGlobal()
	anchor(GameTime.FromReal(GameTime.ServerNow()), 1)
end

local function isSoloPrivate(): boolean
	return game.PrivateServerId ~= "" and #Players:GetPlayers() == 1
end

local function updateScale()
	local wanted = 1
	if TimeConfig.SoloSlowdown.Enabled and isSoloPrivate() then
		local player = Players:GetPlayers()[1]
		local profile = player and S.Data.Get(player)
		local allowed = not profile or profile.Settings.SlowTimeInMenus ~= false
		if player and menuOpen[player] and allowed then
			wanted = TimeConfig.SoloSlowdown.MenuScale
		end
	end
	if math.abs(GameTime.Scale() - wanted) > 1e-6 then
		anchor(GameTime.Now(), wanted)
	end
end

function TimeService.Init()
	anchor(GameTime.FromReal(GameTime.ServerNow()), 1)
	Net.Handle("MenuState", function(player, open)
		menuOpen[player] = open
		updateScale()
	end)
	Players.PlayerRemoving:Connect(function(player)
		menuOpen[player] = nil
		task.defer(updateScale)
	end)
end

function TimeService.Start()
	task.spawn(function()
		local last = GameTime.Info()
		while true do
			task.wait(0.25)
			local info = GameTime.Info()
			if math.floor(info.Hour) ~= math.floor(last.Hour) or info.Day ~= last.Day then
				TimeService.Hour:Fire(info)
				if math.floor(info.Hour) == TimeConfig.MorningHour then
					TimeService.Dawn:Fire(info)
				end
			end
			if info.Day ~= last.Day then
				TimeService.NewDay:Fire(info)
				if info.Season ~= last.Season then
					TimeService.SeasonChanged:Fire(info)
				end
			end
			if info.Slot ~= last.Slot then
				TimeService.Slot:Fire(info.Slot, info)
			end
			last = info
		end
	end)
end

return TimeService

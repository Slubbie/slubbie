-- Weather: publishes the current weather, runs outdoor hazards (lightning,
-- hail, scorch), meteor showers, debug overrides and "weather seen" stats.
--
-- The weather itself is deterministic (Lib/WeatherMath), so clients compute
-- visuals and forecasts locally; this service only does what has gameplay
-- consequences.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local WeatherConfig = require(Shared.Config.Weather)
local WeatherMath = require(Shared.Lib.WeatherMath)
local GameTime = require(Shared.Lib.GameTime)
local Signal = require(Shared.Lib.Signal)
local Registry = require(Shared.Lib.Registry)

local S = require(script.Parent)

local WeatherService = {}
WeatherService.Changed = Signal.new() -- (weatherId, previousId)

local random = Random.new()
local current = "Sunny"

function WeatherService.Current(): string
	return current
end

function WeatherService.Def()
	return WeatherMath.Def(current)
end

-- Weather in a region (desert sandstorms, snowy valley...).
function WeatherService.InRegion(regionId: string?): string
	local region = regionId and Registry.Regions[regionId]
	return WeatherMath.ForRegion(current, region)
end

-- Debug/festival override for `seconds` of game time.
function WeatherService.Force(weatherId: string?, seconds: number?)
	if weatherId and WeatherConfig.Types[weatherId] then
		ReplicatedStorage:SetAttribute("WeatherOverride", weatherId)
		ReplicatedStorage:SetAttribute(
			"WeatherOverrideUntil",
			GameTime.Now() + (seconds or WeatherConfig.OverrideDuration)
		)
	else
		ReplicatedStorage:SetAttribute("WeatherOverride", nil)
		ReplicatedStorage:SetAttribute("WeatherOverrideUntil", nil)
	end
end

local function recordSeen(weatherId: string)
	for player, profile in S.Data.All() do
		local key = "Seen_" .. weatherId
		if not profile.Stats[key] then
			profile.Stats[key] = 1
			local seen = 0
			for _, id in WeatherConfig.Order do
				if profile.Stats["Seen_" .. id] then
					seen += 1
				end
			end
			S.Data.MaxStat(player, "WeatherSeen", seen)
			S.Collection.Discover(player, "Weather", weatherId)
		end
	end
end

-- Hazards --------------------------------------------------------------------------------------

local function protected(player: Player, key: string, tag: string): boolean
	local env = S.Farm.EnvFor(player, key)
	return env ~= nil and (env.Indoor or env.Tags[tag] == true)
end

local function lightningRods(player: Player): { any }
	local profile = S.Data.Get(player)
	local rods = {}
	if profile then
		for uid, placed in profile.Farm.Placed do
			if placed.Id == "lightning_rod" then
				table.insert(rods, uid)
			end
		end
	end
	return rods
end

local function runHazards(weatherId: string)
	local def = WeatherMath.Def(weatherId)
	local hazard = def.Hazard
	if not hazard then
		return
	end
	for player in S.Farm.All() do
		local profile = S.Data.Get(player)
		if profile then
			local outdoor = {}
			for key, tile in profile.Farm.Tiles do
				if tile.C then
					table.insert(outdoor, key)
				end
			end
			local strikes = 0
			for _ = 1, #outdoor do
				if random:NextNumber() < hazard.ChancePerHour / 6 then
					strikes += 1
				end
			end
			strikes = math.min(strikes, 6)
			local rods = if hazard.Kind == "Lightning" then lightningRods(player) else {}
			for i = 1, strikes do
				local key = outdoor[random:NextInteger(1, #outdoor)]
				local farm = S.Farm.Get(player)
				if hazard.Kind == "Lightning" and #rods > 0 and random:NextNumber() < 0.75 then
					-- The rod takes the hit and banks a battery.
					local uid = rods[((i - 1) % #rods) + 1]
					local position = S.Building.WorldPosition(player, uid)
					if position then
						S.Notify.FX(position, "Lightning", { Rod = true }, 600)
					end
					S.Inventory.Give(player, "battery", 1, nil, nil, { Source = "Lightning Rod" })
					S.Data.AddStat(player, "LightningCaught")
				elseif not protected(player, key, hazard.Protect) then
					if farm then
						local gx, gz = S.Farm.ParseKey(key)
						S.Notify.FX(S.Farm.TileCenter(farm, gx, gz), hazard.Kind, {}, 600)
					end
					S.Crop.Hazard(player, key, hazard.Kind)
				end
			end
		end
	end
end

-- Meteor showers drop meteorites around the valley.
local function meteors()
	local candidates = { "Homestead", "Mountains", "Forest", "Beach", "Mossback" }
	local count = random:NextInteger(1, 3)
	for _ = 1, count do
		local region = Registry.Regions[candidates[random:NextInteger(1, #candidates)]]
		local angle = random:NextNumber() * math.pi * 2
		local distance = random:NextNumber() * region.Radius * 0.7
		local position = region.Center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local placed = S.Mining.SpawnTemporary("meteorite_rock", position, 1800)
		if placed then
			S.Notify.FX(placed, "Meteor", {}, 3000)
		end
	end
end

local function onChanged(new: string, old: string)
	ReplicatedStorage:SetAttribute("Weather", new)
	WeatherService.Changed:Fire(new, old)
	recordSeen(new)
	local def = WeatherMath.Def(new)
	if def.Rare then
		S.Notify.BannerAll(def.Icon .. "  " .. def.Name, def.Description, "Weather")
	end
	if new == "MeteorShower" then
		meteors()
	end
end

function WeatherService.Init()
	current = WeatherMath.Current()
	ReplicatedStorage:SetAttribute("Weather", current)
end

function WeatherService.Start()
	task.spawn(function()
		while true do
			task.wait(1)
			local now = WeatherMath.Current()
			if now ~= current then
				local old = current
				current = now
				onChanged(now, old)
			end
		end
	end)
	S.Time.Hour:Connect(function()
		runHazards(current)
		if current == "MeteorShower" then
			meteors()
		end
	end)
	S.Data.Loaded:Connect(function()
		recordSeen(current)
	end)
end

return WeatherService

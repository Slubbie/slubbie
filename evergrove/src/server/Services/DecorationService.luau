-- Farm appeal: a friendly score for how lovingly a farm is decorated.
--
-- Placement, styling and layouts live in BuildingService; this service
-- scores the result so decorating is its own little progression:
--   * every decoration adds points by rarity
--   * variety: distinct decorations add a bonus
--   * theme sets (Config/Placeables.Themes): 5+ pieces of one theme = a set bonus
--   * lighting, water features and custom paint add small bonuses (capped)
-- Tiers unlock titles, and the score + tier + completed themes are shown to
-- visitors (farm model attributes Appeal / AppealTier / Themes).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Placeables = require(Shared.Config.Placeables)
local Registry = require(Shared.Lib.Registry)

local S = require(script.Parent)

local DecorationService = {}

local RARITY_POINTS = { Common = 1, Uncommon = 2, Rare = 4, Epic = 8, Legendary = 12, Mythic = 20 }
local THEME_SET = 5
local THEME_BONUS = 20
local VARIETY_POINTS, VARIETY_CAP = 2, 120
local LIGHT_POINTS, LIGHT_CAP = 1, 30
local WATER_POINTS, WATER_CAP = 5, 25
local PAINT_POINTS, PAINT_CAP = 0.5, 20
local DEBOUNCE = 1.5

DecorationService.Tiers = {
	{ Min = 0, Name = "Tidy", Icon = "🌱" },
	{ Min = 50, Name = "Charming", Icon = "🌷" },
	{ Min = 150, Name = "Picturesque", Icon = "🌸", Title = "Picturesque Farmer" },
	{ Min = 300, Name = "Enchanting", Icon = "✨", Title = "Enchanting Gardener" },
	{ Min = 500, Name = "Legendary", Icon = "🏵️", Title = "Legend of the Valley" },
}

-- Score a profile's farm. Returns score, tier, completed themes.
function DecorationService.Score(profile: any): (number, any, { string })
	local points = 0
	local variety = {}
	local themes: { [string]: number } = {}
	local lights, water, painted = 0, 0, 0
	for _, record in profile.Farm.Placed do
		local def = Registry.Placeables[record.Id]
		if def and Registry.HasTag(def.Id, "Decor") then
			points += RARITY_POINTS[def.Rarity] or 1
			variety[def.Id] = true
			if def.Theme then
				themes[def.Theme] = (themes[def.Theme] or 0) + 1
			end
			if def.Category == "Lighting" then
				lights += 1
			elseif def.Category == "Water" then
				water += 1
			end
			if record.C then
				painted += 1
			end
		end
	end
	local distinct = 0
	for _ in variety do
		distinct += 1
	end
	points += math.min(VARIETY_CAP, distinct * VARIETY_POINTS)
	points += math.min(LIGHT_CAP, lights * LIGHT_POINTS)
	points += math.min(WATER_CAP, water * WATER_POINTS)
	points += math.min(PAINT_CAP, painted * PAINT_POINTS)
	local complete = {}
	for _, theme in Placeables.Themes do
		if (themes[theme] or 0) >= THEME_SET then
			points += THEME_BONUS
			table.insert(complete, theme)
		end
	end
	local score = math.floor(points)
	local tier = DecorationService.Tiers[1]
	for _, t in DecorationService.Tiers do
		if score >= t.Min then
			tier = t
		end
	end
	return score, tier, complete
end

local pending: { [Player]: boolean } = {}

function DecorationService.Refresh(player: Player)
	local profile = S.Data.Get(player)
	local farm = S.Farm.Get(player)
	if not profile or not farm then
		return
	end
	local score, tier, themes = DecorationService.Score(profile)
	farm.Model:SetAttribute("Appeal", score)
	farm.Model:SetAttribute("AppealTier", tier.Name)
	farm.Model:SetAttribute("Themes", if #themes > 0 then table.concat(themes, ",") else nil)
	local before = profile.Stats.FarmAppeal or 0
	S.Data.MaxStat(player, "FarmAppeal", score)
	if tier.Title and not profile.Titles[tier.Title] then
		profile.Titles[tier.Title] = true
		S.Data.Changed(player, "Titles")
		S.Notify.Banner(
			player,
			tier.Icon .. " Your farm is " .. tier.Name .. "!",
			"New title: " .. tier.Title,
			"Decor",
			tier.Icon
		)
	elseif score > before and before > 0 then
		-- Crossing into a new tier without a title still deserves a note.
		for _, t in DecorationService.Tiers do
			if before < t.Min and score >= t.Min and not t.Title then
				S.Notify.Toast(player, t.Icon .. " Your farm is now " .. t.Name .. "!", "Success")
			end
		end
	end
	for _, theme in themes do
		local key = "Theme_" .. theme
		if not profile.Unlocks[key] then
			profile.Unlocks[key] = true
			S.Data.Changed(player, "Unlocks")
			S.Notify.Toast(
				player,
				"🎨 Theme set complete: " .. theme .. " (+" .. THEME_BONUS .. " appeal)",
				"Success"
			)
		end
	end
end

local function schedule(player: Player)
	if pending[player] then
		return
	end
	pending[player] = true
	task.delay(DEBOUNCE, function()
		pending[player] = nil
		if player.Parent then
			DecorationService.Refresh(player)
		end
	end)
end

function DecorationService.Start()
	S.Farm.Ready:Connect(schedule)
	S.Building.Placed:Connect(schedule)
	S.Building.Removed:Connect(schedule)
	S.Building.Moved:Connect(schedule)
	S.Building.Styled:Connect(schedule)
end

return DecorationService

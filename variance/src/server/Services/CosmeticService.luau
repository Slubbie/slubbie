-- Ownership, unlocking, purchasing and equipping of cosmetics.
--
-- syncGrants() is the single source of unlock truth: it re-derives everything a
-- profile qualifies for (levels, achievements, ranked peaks, lore, tournaments)
-- and grants whatever is missing, so unlocks can never be lost to a crash
-- between "earned" and "saved". Purchases with Marks are validated here;
-- premium grants arrive through MonetizationService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cosmetics = require(ReplicatedStorage.Variance.Data.Cosmetics)
local Rating = require(ReplicatedStorage.Variance.Core.Rating)

local CosmeticService = {}

function CosmeticService:Init(services)
	self.Services = services
end

local function divisionMin(id: string): number?
	for _, div in Rating.Divisions do
		if div.Id == id then
			return div.Min
		end
	end
	return nil
end

local function qualifies(item, data): boolean
	local source = item.Source
	local kind = source.Kind
	if kind == "Default" then
		return true
	elseif kind == "Level" then
		return (data.Level or 1) >= source.Value
	elseif kind == "Achievement" then
		return data.Achievements[source.Value] ~= nil
	elseif kind == "Ranked" then
		local min = divisionMin(source.Value)
		if min == nil or (data.Ranked.Games or 0) < Rating.Placements then
			return false
		end
		local best = data.Ranked.Peak or 0
		for _, peak in data.Ranked.SeasonPeaks do
			best = math.max(best, peak)
		end
		return best >= min
	elseif kind == "Season" then
		local season, division = string.match(source.Value, "^(%w+):(%w+)$")
		local peak = season and data.Ranked.SeasonPeaks[season]
		local min = division and divisionMin(division)
		return peak ~= nil and min ~= nil and peak >= min
	elseif kind == "Lore" then
		return data.Lore.AllRead == true
	elseif kind == "Tournament" then
		return (data.Stats.TournamentsWon or 0) >= 1
	end
	return false
end

-- Grants every cosmetic the profile qualifies for. Returns the new ids.
function CosmeticService:syncGrants(player: Player, collector: { any }?): { string }
	local granted = {}
	self.Services.DataService:update(player, function(data)
		for _, item in Cosmetics.List do
			if not data.Cosmetics.Owned[item.Id] and qualifies(item, data) then
				data.Cosmetics.Owned[item.Id] = true
				table.insert(granted, item.Id)
			end
		end
	end)
	for _, id in granted do
		local item = Cosmetics.get(id)
		if item and item.Source.Kind ~= "Default" then
			self.Services.NetworkService:push(player, "Unlock", { Kind = "Cosmetic", Id = id, Name = item.Name, Category = item.Category })
			if collector then
				table.insert(collector, id)
			end
		end
	end
	if #granted > 0 then
		self.Services.ProgressionService:changed(player)
		self.Services.AchievementService:evaluate(player, { Event = "Cosmetic" })
	end
	return granted
end

function CosmeticService:owns(player: Player, id: string): boolean
	local profile = self.Services.DataService:get(player)
	return profile ~= nil and profile.Data.Cosmetics.Owned[id] == true
end

-- Direct grant (challenge rewards, purchases). Returns true if newly owned.
function CosmeticService:grant(player: Player, id: string, reason: string?): boolean
	local item = Cosmetics.get(id)
	if item == nil then
		return false
	end
	local fresh = self.Services.DataService:update(player, function(data)
		if data.Cosmetics.Owned[id] then
			return false
		end
		data.Cosmetics.Owned[id] = true
		return true
	end)
	if fresh then
		self.Services.NetworkService:push(player, "Unlock", {
			Kind = "Cosmetic",
			Id = id,
			Name = item.Name,
			Category = item.Category,
			Reason = reason,
		})
		self.Services.ProgressionService:changed(player)
		self.Services.AchievementService:evaluate(player, { Event = "Cosmetic" })
	end
	return fresh == true
end

function CosmeticService:equip(player: Player, category: string, id: string): (boolean, string?)
	local item = Cosmetics.get(id)
	if item == nil or item.Category ~= category then
		self.Services.AntiExploitService:flag(player, "equip mismatch", "Moderate", id)
		return false, "Unknown item."
	end
	local ok = self.Services.DataService:update(player, function(data)
		if not data.Cosmetics.Owned[id] then
			return false
		end
		data.Cosmetics.Equipped[category] = id
		return true
	end)
	if not ok then
		return false, "You don't own that yet."
	end
	self.Services.ProgressionService:changed(player)
	self.Services.CharacterService:refreshNameplate(player)
	return true
end

function CosmeticService:buy(player: Player, id: string): (boolean, string?)
	local item = Cosmetics.get(id)
	if item == nil or item.Source.Kind ~= "Shop" or type(item.Price) ~= "number" then
		self.Services.AntiExploitService:flag(player, "buy invalid", "Moderate", id)
		return false, "That item isn't for sale."
	end
	local result = self.Services.DataService:update(player, function(data)
		if data.Cosmetics.Owned[id] then
			return "owned"
		end
		if data.Marks < item.Price then
			return "funds"
		end
		data.Marks -= item.Price
		data.Cosmetics.Owned[id] = true
		return "ok"
	end)
	if result == "owned" then
		return false, "Already owned."
	elseif result == "funds" then
		return false, "Not enough Marks."
	elseif result ~= "ok" then
		return false, "Profile not ready."
	end
	self.Services.NetworkService:push(player, "Unlock", { Kind = "Cosmetic", Id = id, Name = item.Name, Category = item.Category, Reason = "Purchased" })
	self.Services.ProgressionService:changed(player)
	self.Services.AchievementService:evaluate(player, { Event = "Cosmetic" })
	return true
end

-- The equipped look of a player, resolved to item data (safe to share publicly).
function CosmeticService:look(player: Player?): { [string]: any }
	local equipped = nil
	if player then
		local profile = self.Services.DataService:get(player)
		equipped = profile and profile.Data.Cosmetics.Equipped
	end
	local out = {}
	for _, category in Cosmetics.Categories do
		local id = (equipped and equipped[category.Id]) or Cosmetics.Defaults[category.Id]
		local item = Cosmetics.get(id) or Cosmetics.get(Cosmetics.Defaults[category.Id])
		out[category.Id] = { Id = item.Id, Name = item.Name, Data = item.Data }
	end
	return out
end

function CosmeticService:Start()
	local network = self.Services.NetworkService
	network:handle("Cosmetics.Equip", function(player, category, id)
		return self:equip(player, category, id)
	end)
	network:handle("Cosmetics.Buy", function(player, id)
		return self:buy(player, id)
	end)
	self.Services.DataService.Loaded:Connect(function(player)
		self:syncGrants(player)
	end)
end

return CosmeticService

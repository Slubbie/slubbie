-- The Halden archive: unlocks lore files from play and serves them to the
-- Archive terminal. Personal placeholders in files are filled per player.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lore = require(ReplicatedStorage.Variance.Data.Lore)
local Instruments = require(ReplicatedStorage.Variance.Core.Instruments)
local Format = require(ReplicatedStorage.Variance.Util.Format)

local LoreService = {}

function LoreService:Init(services)
	self.Services = services
end

local function qualifies(file, data): boolean
	local u = file.Unlock
	local kind = u.Kind
	if kind == "Default" then
		return true
	elseif kind == "Level" then
		return (data.Level or 1) >= u.Value
	elseif kind == "Matches" then
		return (data.Stats.Matches or 0) >= u.Value
	elseif kind == "Defeat" then
		local record = data.SurrogateWins[u.Value]
		if record == nil then
			return false
		end
		for _, n in record do
			if n > 0 then
				return true
			end
		end
		return false
	elseif kind == "Environment" then
		return (data.EnvironmentWins[u.Value] or 0) > 0
	elseif kind == "Achievement" then
		return data.Achievements[u.Value] ~= nil
	elseif kind == "Witness" then
		return data.Flags.WitnessedProctor == true
	elseif kind == "Proctor" then
		local record = data.SurrogateWins.Proctor
		if record then
			for _, n in record do
				if n > 0 then
					return true
				end
			end
		end
		return false
	end
	return false
end

-- Unlocks every file the profile qualifies for. Appends new ids to `collector`.
function LoreService:sync(player: Player, collector: { any }?)
	local fresh = {}
	self.Services.DataService:update(player, function(data)
		for _, file in Lore.Files do
			if not data.Lore.Unlocked[file.Id] and qualifies(file, data) then
				data.Lore.Unlocked[file.Id] = true
				table.insert(fresh, file)
			end
		end
	end)
	for _, file in fresh do
		if file.Unlock.Kind ~= "Default" then
			self.Services.NetworkService:push(player, "Unlock", { Kind = "Lore", Id = file.Id, Name = file.Title })
			if collector then
				table.insert(collector, { Id = file.Id, Title = file.Title })
			end
		end
	end
	if #fresh > 0 then
		self.Services.ProgressionService:changed(player)
	end
end

function LoreService:read(player: Player, id: string): (boolean, any)
	local file = Lore.ById[id]
	local profile = self.Services.DataService:get(player)
	if file == nil or profile == nil then
		return false, "Unknown file."
	end
	local data = profile.Data
	if not data.Lore.Unlocked[id] then
		return false, "CLEARANCE INSUFFICIENT"
	end
	local favourite, count = "NONE", 0
	for instrumentId, n in data.InstrumentUse do
		if n > count then
			local def = Instruments.get(instrumentId)
			favourite, count = def and def.Name or instrumentId, n
		end
	end
	local shots = data.Stats.Shots
	local values = {
		name = string.upper(player.DisplayName),
		matches = tostring(data.Stats.Matches),
		wins = tostring(data.Stats.Wins),
		selfshare = shots > 0 and Format.percent(data.Stats.SelfShots / shots) or "0%",
		favourite = favourite,
	}
	local title, body = Lore.render(file, values)
	local newlyRead = false
	self.Services.DataService:update(player, function(d)
		if not d.Lore.Read[id] then
			d.Lore.Read[id] = true
			newlyRead = true
		end
		local all = true
		for _, f in Lore.Files do
			if not d.Lore.Read[f.Id] then
				all = false
				break
			end
		end
		d.Lore.AllRead = all
	end)
	if newlyRead then
		self.Services.ProgressionService:changed(player)
		if data.Lore.AllRead then
			self.Services.CosmeticService:syncGrants(player)
			self.Services.AchievementService:evaluate(player, { Event = "Lore" })
		end
	end
	return true,
		{
			Id = file.Id,
			Title = title,
			Class = file.Class,
			Date = file.Date,
			Author = file.Author,
			Body = body,
		}
end

-- Records that a player saw the Proctor watching (rare match event).
function LoreService:witness(player: Player)
	local first = self.Services.DataService:update(player, function(d)
		if d.Flags.WitnessedProctor then
			return false
		end
		d.Flags.WitnessedProctor = true
		return true
	end)
	if first then
		self:sync(player)
		self.Services.AchievementService:evaluate(player, { Event = "Witness" })
	end
end

function LoreService:Start()
	self.Services.NetworkService:handle("Lore.Read", function(player, id)
		return self:read(player, id)
	end)
	self.Services.DataService.Loaded:Connect(function(player)
		self:sync(player)
	end)
end

return LoreService

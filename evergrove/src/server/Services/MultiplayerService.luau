-- Visiting farms, farm privacy, public profiles and text filtering.
--
-- Every server hosts up to six farms. Anyone can walk to a neighbour's lot,
-- but the owner's permission level for them (PermissionService) decides what
-- they can do there; "None" keeps them out entirely (they're sent home if they
-- wander in). VisitFarm teleports to a farm's gate, GoHome back to yours.
--
-- All player-written text (farm/animal/layout/guild names, signs, bios) goes
-- through FilterText, which fails closed: if filtering errors, the text is
-- rejected rather than shown unfiltered.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage.Shared
local World = require(Shared.Config.World)
local Net = require(Shared.Lib.Net)
local Stats = require(Shared.Lib.Stats)
local Format = require(Shared.Lib.Format)
local Collections = require(Shared.Lib.Collections)

local S = require(script.Parent)

local BIO_MAX = 140
local ENFORCE_EVERY = 2

local MultiplayerService = {}

local visited: { [Player]: { [number]: boolean } } = {} -- owner → visitor ids counted this session

-- Text filtering ----------------------------------------------------------------------------------------------

-- Filter text written by `author` for everyone to see. Returns the filtered
-- string, or nil if it can't be shown.
function MultiplayerService.FilterText(author: Player, text: string): string?
	if text == "" then
		return ""
	end
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, author.UserId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or type(result) ~= "string" then
		return nil
	end
	-- Fully hashed names aren't useful as names.
	if string.gsub(result, "#", "") == "" then
		return nil
	end
	return result
end

-- Visiting -------------------------------------------------------------------------------------------------------

local function sendTo(player: Player, cframe: CFrame?)
	if not cframe then
		cframe = CFrame.new(World.Spawn)
	end
	S.Security.AllowTeleport(player)
	S.Player.Teleport(player, cframe :: CFrame)
end

function MultiplayerService.GoHome(player: Player): boolean
	local cframe = S.Farm.SpawnCFrame(player)
	sendTo(player, cframe)
	return cframe ~= nil
end

-- Remove `visitor` from `owner`'s farm (permission lowered to None).
function MultiplayerService.EjectFrom(owner: Player, visitor: Player)
	local farm = S.Farm.Get(owner)
	local root = S.Security.RootPosition(visitor)
	if not farm or not root then
		return
	end
	local lotId = S.Farm.LotOfPosition(root)
	if lotId and lotId == farm.Lot.Id then
		MultiplayerService.GoHome(visitor)
		S.Notify.Toast(visitor, owner.DisplayName .. "'s farm is closed to visitors right now.", "Warning")
	end
end

local function visit(player: Player, userId: number)
	local owner = Players:GetPlayerByUserId(userId)
	if not owner or owner == player then
		return false, "That farmer isn't on this server"
	end
	if not S.Farm.Get(owner) then
		return false, "Their farm isn't ready"
	end
	if S.Permission.LevelFor(owner, player) == "None" then
		return false, owner.DisplayName .. " isn't accepting visitors"
	end
	sendTo(player, S.Farm.SpawnCFrame(owner))
	visited[owner] = visited[owner] or {}
	if not visited[owner][player.UserId] then
		visited[owner][player.UserId] = true
		S.Data.AddStat(owner, "FarmVisitors")
		S.Notify.Toast(owner, "👋 " .. player.DisplayName .. " is visiting your farm!", "Info")
	end
	S.Data.AddStat(player, "FarmsVisited")
	local level = S.Permission.LevelFor(owner, player)
	return true, { Owner = owner.UserId, Level = level }
end

-- Public profiles ---------------------------------------------------------------------------------------------------

local PUBLIC_STATS = {
	"CropsHarvested",
	"FishCaught",
	"AnimalProducts",
	"ArtisanMade",
	"ContestWins",
	"SecretsFound",
	"CoinsEarned",
	"QuestsCompleted",
}

local function profileCard(viewer: Player, userId: number)
	local target = Players:GetPlayerByUserId(userId)
	local profile = target and S.Data.Get(target)
	if not target or not profile then
		return false, "That farmer isn't on this server"
	end
	local skills = {}
	for skillId in profile.Skills do
		skills[skillId] = Stats.SkillLevel(profile, skillId)
	end
	local stats = nil
	if not profile.Public.HideStats or viewer == target then
		stats = {}
		for _, key in PUBLIC_STATS do
			stats[key] = profile.Stats[key] or 0
		end
	end
	local achievements = 0
	for _ in profile.Achievements do
		achievements += 1
	end
	return true,
		{
			UserId = target.UserId,
			Name = target.DisplayName,
			Estate = Stats.EstateLevel(profile),
			Title = profile.Cosmetics.Equipped.Title,
			Frame = profile.Cosmetics.Equipped.Frame,
			Banner = profile.Cosmetics.Equipped.Banner,
			FarmName = profile.Farm.Name,
			Bio = profile.Public.Bio,
			Skills = skills,
			Stats = stats,
			Showcase = profile.Showcase,
			Collection = Collections.TotalPercent(profile.Collection),
			Achievements = achievements,
			Guild = profile.Guild.Name,
			PlayDays = math.floor((os.time() - (profile.Created or os.time())) / 86400),
			Permission = if viewer ~= target then S.Permission.LevelFor(target, viewer) else "Trusted",
		}
end

local function profileSet(player: Player, field: string, value: any)
	local profile = S.Data.Get(player)
	if not profile then
		return false, "Not ready"
	end
	if field == "Bio" then
		local clean = Format.CleanName(tostring(value or ""), BIO_MAX)
		local filtered = MultiplayerService.FilterText(player, clean)
		if filtered == nil then
			return false, "That bio isn't allowed"
		end
		profile.Public.Bio = filtered
	elseif field == "HideStats" then
		profile.Public.HideStats = value == true
	else
		return false, "Unknown field"
	end
	S.Data.Changed(player, "Public")
	return true, profile.Public
end

-- Enforcement ------------------------------------------------------------------------------------------------------

local function enforce()
	for _, player in Players:GetPlayers() do
		local root = S.Security.RootPosition(player)
		if root then
			local lotId = S.Farm.LotOfPosition(root)
			local owner = lotId and S.Farm.OwnerOfLot(lotId)
			if owner and owner ~= player and S.Permission.LevelFor(owner, player) == "None" then
				MultiplayerService.EjectFrom(owner, player)
			end
		end
	end
end

-- Lifecycle -------------------------------------------------------------------------------------------------------

function MultiplayerService.Init()
	Net.Handle("VisitFarm", visit)
	Net.Handle("GoHome", function(player)
		if not MultiplayerService.GoHome(player) then
			return false, "Your farm isn't ready yet"
		end
		return true
	end)
	Net.Handle("ProfileGet", profileCard)
	Net.Handle("ProfileSet", profileSet)
end

function MultiplayerService.Start()
	Players.PlayerRemoving:Connect(function(player)
		visited[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(ENFORCE_EVERY)
			local ok, err = pcall(enforce)
			if not ok then
				warn("[Evergrove] Farm privacy check failed:", err)
			end
		end
	end)
end

return MultiplayerService

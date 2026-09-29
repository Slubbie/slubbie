-- Visitor permissions on farms.
--
-- Owners choose a default level for visitors and can override it per player.
-- Friends get a friendlier default. Every sensitive farm action asks
-- PermissionService.Allows(owner, actor, level) on the server; lowering a
-- visitor to "None" sends them home.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Social = require(Shared.Config.Social)
local Net = require(Shared.Lib.Net)

local S = require(script.Parent)

local ORDER = Social.Permissions.Order
local RANK = {}
for i, level in ORDER do
	RANK[level] = i
end

local PermissionService = {}

local friendCache: { [Player]: { [number]: boolean } } = {}

local function isFriend(owner: Player, other: Player): boolean
	local cache = friendCache[owner]
	if cache and cache[other.UserId] ~= nil then
		return cache[other.UserId]
	end
	friendCache[owner] = friendCache[owner] or {}
	-- Resolved asynchronously; until then treat as a regular visitor.
	friendCache[owner][other.UserId] = false
	task.spawn(function()
		local ok, result = pcall(function()
			return owner:IsFriendsWithAsync(other.UserId)
		end)
		if ok and friendCache[owner] then
			friendCache[owner][other.UserId] = result == true
		end
	end)
	return false
end

-- The level `actor` has on `owner`'s farm.
function PermissionService.LevelFor(owner: Player, actor: Player): string
	if owner == actor then
		return "Trusted"
	end
	local profile = S.Data.Get(owner)
	if not profile then
		return "None"
	end
	local perm = profile.Farm.Perm
	local explicit = perm.Players[tostring(actor.UserId)]
	if explicit and RANK[explicit] then
		return explicit
	end
	if isFriend(owner, actor) then
		local friendDefault = Social.Permissions.FriendDefault
		if RANK[friendDefault] > RANK[perm.Default or "View"] then
			return friendDefault
		end
	end
	local actorProfile = S.Data.Get(actor)
	if actorProfile and actorProfile.Guild.Id and actorProfile.Guild.Id == profile.Guild.Id then
		if RANK.Crops > RANK[perm.Default or "View"] then
			return "Crops"
		end
	end
	return perm.Default or Social.Permissions.Default
end

function PermissionService.Allows(owner: Player, actor: Player, level: string): boolean
	local have = RANK[PermissionService.LevelFor(owner, actor)] or 1
	local need = RANK[level] or #ORDER
	return have >= need
end

local function set(player: Player, target: string, level: string)
	local profile = S.Data.Get(player)
	if not profile then
		return false, "Not ready"
	end
	if not RANK[level] then
		return false, "Unknown level"
	end
	local perm = profile.Farm.Perm
	if target == "Default" then
		if level == "Trusted" then
			return false, "Trusted access can only be given to specific players"
		end
		perm.Default = level
	else
		local userId = tonumber(target)
		if not userId or userId == player.UserId then
			return false, "Unknown player"
		end
		perm.Players[tostring(userId)] = level
	end
	S.Data.Changed(player, "Farm", "Perm")
	-- Anyone now below View gets sent home.
	for _, other in Players:GetPlayers() do
		if other ~= player and not PermissionService.Allows(player, other, "View") then
			S.Multiplayer.EjectFrom(player, other)
		end
	end
	return true
end

local function get(player: Player)
	local profile = S.Data.Get(player)
	if not profile then
		return false, "Not ready"
	end
	local out = { Default = profile.Farm.Perm.Default, Players = {} }
	for userId, level in profile.Farm.Perm.Players do
		local name = userId
		local online = Players:GetPlayerByUserId(tonumber(userId) :: number)
		if online then
			name = online.DisplayName
		end
		table.insert(out.Players, { UserId = userId, Name = name, Level = level })
	end
	-- Also list everyone in the server so the owner can set them.
	out.Online = {}
	for _, other in Players:GetPlayers() do
		if other ~= player then
			table.insert(out.Online, {
				UserId = tostring(other.UserId),
				Name = other.DisplayName,
				Level = PermissionService.LevelFor(player, other),
			})
		end
	end
	return true, out
end

function PermissionService.Init()
	Net.Handle("PermSet", set)
	Net.Handle("PermGet", get)
end

function PermissionService.Start()
	Players.PlayerRemoving:Connect(function(player)
		friendCache[player] = nil
		for _, cache in friendCache do
			cache[player.UserId] = nil
		end
	end)
end

return PermissionService

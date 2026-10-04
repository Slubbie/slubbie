-- Social features: who's online in this server (and what they're up to),
-- invites to run together or join a race or relay, emotes, co-op pressure
-- switches, and saving each player's settings and key bindings.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cosmetics = require(ReplicatedStorage.Shared.Config.Cosmetics)
local Net = require(ReplicatedStorage.Shared.Net)
local SettingsConfig = require(ReplicatedStorage.Shared.Config.Settings)
local Tags = require(ReplicatedStorage.Shared.Tags)

local DataService = require(script.Parent.Parent.Data.DataService)
local Events = require(script.Parent.Parent.Events)
local CourseService = require(script.Parent.CourseService)
local DistrictService = require(script.Parent.DistrictService)
local MovementGuard = require(script.Parent.MovementGuard)
local Notify = require(script.Parent.Notify)
local RaceService = require(script.Parent.RaceService)
local RelayService = require(script.Parent.RelayService)

local SocialService = {}

type Invite = { From: Player, Kind: string, Target: string?, Expires: number }
local invites: { [Player]: { [number]: Invite } } = {}
local switches: { [string]: { Position: Vector3, Duration: number } } = {}
local gates: { [string]: Vector3 } = {}
local switchUntil: { [string]: number } = {}

local function activity(player: Player): string
	local run = CourseService.Active(player)
	if run then
		if run.Mode == "Race" then
			return "Racing"
		elseif run.Mode == "Relay" then
			return "Running a relay"
		elseif run.Mode == "Tower" then
			return "Climbing the Spire"
		end
		return "On a course"
	end
	return "Exploring"
end

local function onPlayers(player: Player): any
	local list = {}
	for _, other in Players:GetPlayers() do
		local isFriend = false
		if other ~= player then
			pcall(function()
				isFriend = (player :: any):IsFriendsWithAsync(other.UserId)
			end)
		end
		table.insert(list, {
			UserId = other.UserId,
			Name = other.DisplayName,
			Level = other:GetAttribute("Level") or 1,
			Rank = other:GetAttribute("Rank"),
			Title = other:GetAttribute("Title"),
			Crew = other:GetAttribute("CrewTag"),
			District = MovementGuard.District(other) or "Hub",
			Activity = activity(other),
			Friend = isFriend,
			You = other == player,
			Race = RaceService.LobbyOf(other),
			Relay = RelayService.TeamOf(other),
		})
	end
	return list
end

-- kind: "Join" (come to me) | "Race" | "Relay"
local function onInvite(player: Player, userId: any, kind: any)
	local target = type(userId) == "number" and Players:GetPlayerByUserId(userId)
	if not target or target == player then
		return
	end
	local invite: Invite = { From = player, Kind = "Join", Target = nil, Expires = os.clock() + 120 }
	if kind == "Race" then
		local lobby = RaceService.LobbyOf(player)
		if not lobby then
			return
		end
		invite.Kind, invite.Target = "Race", lobby
	elseif kind == "Relay" then
		local team = RelayService.TeamOf(player)
		if not team then
			return
		end
		invite.Kind, invite.Target = "Relay", team
	end
	invites[target] = invites[target] or {}
	invites[target][player.UserId] = invite
	Net.Push(target, "Social.Invite", {
		From = player.UserId,
		Name = player.DisplayName,
		Kind = invite.Kind,
		District = MovementGuard.District(player),
	})
	Notify.Toast(player, "Invite sent", target.DisplayName)
end

local function onRespond(player: Player, fromUserId: any, accept: any): (boolean, any)
	local pending = invites[player]
	local invite = pending and type(fromUserId) == "number" and pending[fromUserId]
	if not invite or os.clock() > invite.Expires then
		return false, "That invite has expired"
	end
	if pending then
		pending[fromUserId] = nil
	end
	if not accept then
		return true, nil
	end
	if invite.Kind == "Race" and invite.Target then
		return RaceService.Join(player, invite.Target)
	elseif invite.Kind == "Relay" and invite.Target then
		return RelayService.Join(player, invite.Target)
	end
	-- Join: travel to the inviter's side.
	local from = invite.From
	if not from.Parent then
		return false, "They've left"
	end
	if CourseService.Active(player) then
		return false, "Finish your current run first"
	end
	local district = MovementGuard.District(from) or "Hub"
	local ok, reason = DistrictService.CanEnter(player, district)
	if not ok then
		return false, reason
	end
	local position = MovementGuard.Position(from)
	if not position then
		return false, "They're between places"
	end
	local destination = CFrame.new(position + Vector3.new(3, 1, 3))
	MovementGuard.AllowTeleport(player, destination.Position, 20)
	return true, { Teleport = destination }
end

-- Emotes: only equipped ones (or your equipped victory animation after a finish).
local lastEmote: { [Player]: number } = {}
local function onEmote(player: Player, name: any)
	local character = player.Character
	local profile = DataService.Get(player)
	if not character or not profile or (os.clock() - (lastEmote[player] or 0)) < 0.5 then
		return
	end
	lastEmote[player] = os.clock()
	if name == nil then
		character:SetAttribute("Emote", nil)
		character:SetAttribute("EmoteAt", nil)
		return
	end
	if type(name) ~= "string" then
		return
	end
	local allowed = false
	for _, id in profile.Equipped.Emotes or {} do
		local item = Cosmetics.ById[id]
		if item and item.Style == name and profile.Inventory[id] then
			allowed = true
		end
	end
	local victory = Cosmetics.ById[profile.Equipped.Victory or ""]
	if victory and victory.Style == name then
		allowed = true
	end
	if not allowed then
		return
	end
	character:SetAttribute("Emote", name)
	character:SetAttribute("EmoteAt", workspace:GetServerTimeNow())
end

-- Pressure plates: opening a gate for everyone. Holding it for someone else counts as co-op.
local function onSwitch(player: Player, switchId: any)
	if type(switchId) ~= "string" then
		return
	end
	local switch = switches[switchId]
	if not switch or not MovementGuard.WasNear(player, switch.Position, 10, 1.5) then
		return
	end
	local now = workspace:GetServerTimeNow()
	local untilTime = now + switch.Duration
	local wasOpen = (switchUntil[switchId] or 0) > now
	switchUntil[switchId] = untilTime
	Net.PushAll("Switch.Opened", switchId, untilTime)
	if not wasOpen then
		local gate = gates[switchId]
		if gate then
			for _, other in Players:GetPlayers() do
				if other ~= player then
					local position = MovementGuard.Position(other)
					if position and (position - gate).Magnitude < 45 then
						local profile = DataService.Get(player)
						if profile then
							profile.Stats.CoopSwitches = (profile.Stats.CoopSwitches or 0) + 1
							DataService.MarkDirty(player)
						end
						Events.CoopSwitch:Fire(player)
						Events.StatChanged:Fire(player, "CoopSwitches")
						break
					end
				end
			end
		end
	end
end

local function onSettings(player: Player, values: any, bindings: any)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	if type(values) == "table" then
		for id, value in values do
			if type(id) == "string" then
				local clean = SettingsConfig.Sanitize(id, value)
				if clean ~= nil then
					profile.Settings[id] = clean
				end
			end
		end
	end
	if bindings ~= nil then
		local clean = SettingsConfig.SanitizeBindings(bindings)
		if clean then
			profile.Bindings = clean
		end
	end
	DataService.MarkDirty(player)
end

function SocialService.Start()
	for _, part in CollectionService:GetTagged(Tags.Switch) do
		if part:IsA("BasePart") then
			local id = part:GetAttribute("SwitchId")
			if type(id) == "string" then
				switches[id] = { Position = part.Position, Duration = part:GetAttribute("Duration") or 5 }
			end
		end
	end
	for _, part in CollectionService:GetTagged(Tags.SwitchGate) do
		if part:IsA("BasePart") then
			local id = part:GetAttribute("SwitchId")
			if type(id) == "string" then
				gates[id] = part.Position
			end
		end
	end
	Net.Handle("Social.Players", onPlayers)
	Net.On("Social.Invite", onInvite)
	Net.Handle("Social.Respond", onRespond)
	Net.On("Emote.Play", onEmote)
	Net.On("Switch.Press", onSwitch)
	Net.On("Settings.Save", onSettings)
	Players.PlayerRemoving:Connect(function(player)
		invites[player] = nil
		lastEmote[player] = nil
	end)
end

return SocialService

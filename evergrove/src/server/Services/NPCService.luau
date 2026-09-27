-- Villagers: their bodies, daily routines, walking the village roads, and
-- conversations (greetings by friendship tier, time, weather and season,
-- birthdays, heart events, quest hand-ins, shops and services).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage.Shared
local NPCs = require(Shared.Config.NPCs)
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local Stats = require(Shared.Lib.Stats)
local GameTime = require(Shared.Lib.GameTime)
local WeatherMath = require(Shared.Lib.WeatherMath)

local NpcBuilder = require(script.Parent.Parent.World.NpcBuilder)
local S = require(script.Parent)

local NPCService = {}

type Runtime = {
	Def: any,
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Tracks: { [string]: AnimationTrack },
	Target: string?,
	Path: { Vector3 },
	Moving: boolean,
	PausedUntil: number,
	Away: boolean,
}

local runtimes: { [string]: Runtime } = {}
local folder: Folder
local hidden: Folder
local random = Random.new()

-- Schedules ---------------------------------------------------------------------------------------

local function scheduleFor(def: any): { { any } }
	local info = GameTime.Info()
	local schedule = def.Schedule
	if schedule.Festival and S.Festival.Active() then
		return schedule.Festival
	end
	local weather = WeatherMath.Def(S.Weather.Current())
	if schedule.Rain and (weather.Waters or weather.Id == "Snow") then
		return schedule.Rain
	end
	if schedule[info.SeasonId] then
		return schedule[info.SeasonId]
	end
	if schedule.Weekend and info.Weekday >= 6 then
		return schedule.Weekend
	end
	return schedule.Default
end

local function currentWaypoint(def: any): string
	local hour = GameTime.Info().Hour
	local list = scheduleFor(def)
	local chosen = list[#list][2]
	for _, entry in list do
		if hour >= entry[1] then
			chosen = entry[2]
		end
	end
	-- Everyone gathers at the festival.
	if S.Festival.Active() and not def.Schedule.Festival and chosen ~= "Away" then
		local stage = S.World.Waypoint("FestivalStage")
		if stage and (def.Id ~= "wisp") then
			return "FestivalStage"
		end
	end
	return chosen
end

-- Movement ---------------------------------------------------------------------------------------------

local function setAway(rt: Runtime, away: boolean)
	if rt.Away == away then
		return
	end
	rt.Away = away
	rt.Model.Parent = if away then hidden else folder
end

local function playTrack(rt: Runtime, name: string)
	for trackName, track in rt.Tracks do
		if trackName == name then
			if not track.IsPlaying then
				track:Play(0.25)
			end
		elseif track.IsPlaying then
			track:Stop(0.25)
		end
	end
end

local function walkTo(rt: Runtime, waypoint: string)
	rt.Target = waypoint
	if waypoint == "Away" then
		setAway(rt, true)
		return
	end
	local destination = S.World.Waypoint(waypoint)
	if not destination then
		return
	end
	setAway(rt, false)
	local from = rt.Root.Position
	-- Far away (another region): travel off-screen instead of walking for minutes.
	if (destination - from).Magnitude > 420 then
		rt.Model:PivotTo(CFrame.new(destination + Vector3.new(random:NextNumber(-3, 3), 3, random:NextNumber(-3, 3))))
		rt.Path = {}
		return
	end
	rt.Path = S.World.Path(from, destination)
	-- Scatter a little so NPCs don't stack on the exact same spot.
	rt.Path[#rt.Path] = destination + Vector3.new(random:NextNumber(-4, 4), 0, random:NextNumber(-4, 4))
end

local function stepMovement(rt: Runtime)
	if rt.Away or rt.PausedUntil > os.clock() then
		if rt.Moving then
			rt.Humanoid:MoveTo(rt.Root.Position)
			rt.Moving = false
			playTrack(rt, "Idle")
		end
		return
	end
	local nextPoint = rt.Path[1]
	if not nextPoint then
		if rt.Moving then
			rt.Moving = false
			playTrack(rt, "Idle")
		end
		return
	end
	local flat = Vector3.new(nextPoint.X - rt.Root.Position.X, 0, nextPoint.Z - rt.Root.Position.Z)
	if flat.Magnitude < 3 then
		table.remove(rt.Path, 1)
		return
	end
	if not rt.Moving or (rt.Humanoid.MoveDirection.Magnitude < 0.1) then
		rt.Humanoid:MoveTo(nextPoint)
		rt.Moving = true
		playTrack(rt, "Walk")
	end
end

-- Public -----------------------------------------------------------------------------------------------

function NPCService.Position(npcId: string): Vector3?
	local rt = runtimes[npcId]
	if not rt or rt.Away then
		return nil
	end
	return rt.Root.Position
end

function NPCService.IsUnlocked(player: Player, npcId: string): boolean
	local profile = S.Data.Get(player)
	local npc = Registry.Npcs[npcId]
	return profile ~= nil and npc ~= nil and Stats.NpcUnlocked(profile, npc)
end

-- Close enough to talk/shop/deliver (and the NPC has arrived in town for them).
function NPCService.Near(player: Player, npcId: string): boolean
	local position = NPCService.Position(npcId)
	if not position or not NPCService.IsUnlocked(player, npcId) then
		return false
	end
	return S.Security.InReach(player, position, NPCs.InteractRange + 4)
end

function NPCService.Say(player: Player, npcId: string, lines: { string }, extra: { [string]: any }?)
	local payload = { Lines = lines }
	for k, v in pairs(extra or {}) do
		payload[k] = v
	end
	Net.Fire(player, "Dialogue", npcId, payload)
end

function NPCService.RefreshVisibility(player: Player)
	Net.Fire(player, "Dialogue", "", { Visibility = true })
end

-- Conversations ------------------------------------------------------------------------------------------

local function pick(list: { string }?): string?
	if not list or #list == 0 then
		return nil
	end
	return list[random:NextInteger(1, #list)]
end

local function tierKey(hearts: number): string
	local key = "Stranger"
	for _, tier in NPCs.Tiers do
		if hearts >= tier.Hearts then
			key = tier.Key
		end
	end
	return key
end

local function greeting(profile: any, npc: any): { string }
	local lines = {}
	local hearts = Stats.Hearts(profile, npc.Id)
	local info = GameTime.Info()
	local weather = WeatherMath.Def(S.Weather.Current())
	if S.Friendship.IsBirthday(npc.Id) then
		table.insert(lines, "It's my birthday today! " .. (pick(npc.Lines[tierKey(hearts)]) or ""))
		return lines
	end
	local situational = nil
	if weather.Id == "Rain" or weather.Id == "Thunderstorm" then
		situational = npc.Lines.Rain
	elseif weather.Id == "Snow" or weather.Id == "Blizzard" then
		situational = npc.Lines.Snow
	elseif weather.Id == "Heatwave" then
		situational = npc.Lines.Heatwave
	elseif info.IsNight then
		situational = npc.Lines.Night
	elseif info.Hour < 10 then
		situational = npc.Lines.Morning
	elseif info.Hour >= 17 then
		situational = npc.Lines.Evening
	end
	if situational and random:NextNumber() < 0.45 then
		table.insert(lines, pick(situational) :: string)
	else
		table.insert(lines, pick(npc.Lines[tierKey(hearts)]) or "Hello!")
	end
	return lines
end

local function talk(player: Player, npcId: string)
	local profile = S.Data.Get(player)
	local npc = Registry.Npcs[npcId]
	local rt = runtimes[npcId]
	if not profile or not npc or not rt then
		return false, "Nobody's there"
	end
	if not NPCService.Near(player, npcId) then
		return false, "Get closer"
	end
	-- Face the player and pause the routine for a moment.
	local root = S.Security.RootPosition(player)
	if root then
		rt.PausedUntil = os.clock() + 8
		local look = Vector3.new(root.X, rt.Root.Position.Y, root.Z)
		if (look - rt.Root.Position).Magnitude > 0.5 then
			rt.Root.CFrame = CFrame.lookAt(rt.Root.Position, look)
		end
	end
	local firstToday = S.Friendship.Talk(player, npcId)
	local completed = S.Quest.OnTalk(player, npcId)
	S.Tutorial.Event(player, "Talk:" .. npcId)
	S.Data.AddStat(player, "Conversations")

	local payload: { [string]: any } = {
		Npc = npcId,
		Hearts = Stats.Hearts(profile, npcId),
		Points = (profile.Friendship[npcId] and profile.Friendship[npcId].Pts) or 0,
		Birthday = S.Friendship.IsBirthday(npcId),
		FirstToday = firstToday,
		Completed = completed,
	}
	local event = S.Friendship.PendingEvent(profile, npcId)
	if event then
		payload.Event = { Title = event.Title, Lines = event.Lines, Hearts = event.Hearts }
		payload.Lines = event.Lines
		S.Friendship.PlayEvent(player, npcId, event)
	elseif #completed == 0 then
		payload.Lines = greeting(profile, npc)
	end
	-- Quests this villager can offer.
	local offers = {}
	for _, questId in S.Quest.Available(player) do
		local quest = Registry.Quests[questId]
		if quest.Giver == npcId and not quest.Auto then
			table.insert(offers, { Id = quest.Id, Name = quest.Name, Description = quest.Description })
		end
	end
	payload.Offers = offers
	payload.Shop = npc.Shop
	if npc.Shop then
		local shop = Registry.Shops[npc.Shop]
		payload.Services = shop and shop.Services
		payload.Open = S.Economy.IsOpen(npc.Shop)
	end
	return true, payload
end

local function choice(player: Player, npcId: string, index: number)
	local profile = S.Data.Get(player)
	local npc = Registry.Npcs[npcId]
	if not profile or not npc or not NPCService.Near(player, npcId) then
		return false, "Get closer"
	end
	-- Choice 1: "Tell me more" — another line from their current tier.
	if index == 1 then
		return true, { Lines = { pick(npc.Lines[tierKey(Stats.Hearts(profile, npcId))]) or "..." } }
	end
	-- Choice 2: "What do you like?" — a hint at a loved gift once you're friends.
	if index == 2 then
		if Stats.Hearts(profile, npcId) >= 2 then
			local loves = npc.Gifts.Love
			local spec = loves[random:NextInteger(1, #loves)]
			return true, { Lines = { "Honestly? I can never say no to " .. Registry.SpecName(spec) .. "." } }
		end
		return true, { Lines = { "Oh, I couldn't possibly say. Maybe when we know each other better." } }
	end
	return false, "Nothing to say"
end

-- Loop ------------------------------------------------------------------------------------------------------

local function spawnAll()
	for _, def in NPCs.List do
		local model = NpcBuilder.Build(def)
		local start = S.World.Waypoint("Home_" .. def.Id) or S.World.Waypoint("Plaza") or Vector3.new(0, 0, 0)
		model:PivotTo(CFrame.new(start + Vector3.new(0, 3, 0)))
		model.Parent = folder
		local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
		humanoid.WalkSpeed = NPCs.WalkSpeed
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
		local rt: Runtime = {
			Def = def,
			Model = model,
			Humanoid = humanoid,
			Root = root,
			Tracks = NpcBuilder.Tracks(model),
			Target = nil,
			Path = {},
			Moving = false,
			PausedUntil = 0,
			Away = false,
		}
		runtimes[def.Id] = rt
		playTrack(rt, "Idle")
	end
end

function NPCService.Init()
	folder = Instance.new("Folder")
	folder.Name = "NPCs"
	folder.Parent = workspace
	hidden = Instance.new("Folder")
	hidden.Name = "NPCsAway"
	hidden.Parent = ServerStorage
	Net.Handle("NpcTalk", talk)
	Net.Handle("NpcChoice", choice)
end

function NPCService.Start()
	spawnAll()
	-- Routine updates: pick the scheduled waypoint every few seconds.
	task.spawn(function()
		while true do
			for _, rt in runtimes do
				local wanted = currentWaypoint(rt.Def)
				if wanted ~= rt.Target then
					walkTo(rt, wanted)
				end
			end
			task.wait(3)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.4)
			for _, rt in runtimes do
				if rt.Model.Parent then
					local ok, err = pcall(stepMovement, rt)
					if not ok then
						warn("[NPC] movement error", rt.Def.Id, err)
					end
					-- Fell out of the world somehow: put them back.
					if rt.Root.Position.Y < -50 and rt.Root.Position.Y > -1500 then
						local home = S.World.Waypoint("Home_" .. rt.Def.Id) or Vector3.new(0, 5, 0)
						rt.Model:PivotTo(CFrame.new(home + Vector3.new(0, 4, 0)))
					end
				end
			end
		end
	end)
end

return NPCService

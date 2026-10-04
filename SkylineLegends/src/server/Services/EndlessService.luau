-- The Dreamline: endless runs of tested sections.
--
-- Each runner gets a lane off the Dreamline lobby. Sections from the library
-- (sized from the movement envelope, so always clearable) are built a few
-- ahead of you and torn down behind you; every gate you pass raises the
-- difficulty a little. You have three lives: a fall costs one and puts you
-- back at your last gate. Your best run is your Dreamline record.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Districts = require(ReplicatedStorage.Shared.Config.Districts)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Config.Progression)
local Rotation = require(ReplicatedStorage.Shared.Logic.Rotation)

local DataService = require(script.Parent.Parent.Data.DataService)
local Events = require(script.Parent.Parent.Events)
local CourseBuilder = require(script.Parent.Parent.World.CourseBuilder)
local Dreamline = require(script.Parent.Parent.World.Dreamline)
local Kit = require(script.Parent.Parent.World.Kit)
local Sections = require(script.Parent.Parent.World.Sections)
local CourseService = require(script.Parent.CourseService)
local MovementGuard = require(script.Parent.MovementGuard)
local Notify = require(script.Parent.Notify)
local ProgressionService = require(script.Parent.ProgressionService)

local EndlessService = {}

local AHEAD = 3
local KEEP_BEHIND = 2
local LIVES = 3

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local THEME = {
	Id = "Dreamline",
	Surface = rgb(70, 60, 110),
	SurfaceMaterial = Enum.Material.Glass,
	Trim = rgb(255, 160, 240),
	Wall = rgb(120, 110, 180),
	WallMaterial = Enum.Material.Marble,
	Accent = rgb(150, 255, 230),
	Signal = rgb(255, 160, 240),
	Beam = rgb(200, 180, 255),
	BeamMaterial = Enum.Material.Marble,
	Rope = rgb(255, 220, 250),
	Climb = "Mesh",
	BodyDepth = 0,
	Floating = true,
}

type Lane = {
	Index: number,
	Root: Folder,
	B: any,
	Ctx: any,
	Cursor: CFrame,
	Built: number, -- sections built
	Folders: { [number]: Folder },
	Cleared: number,
	Lives: number,
	Rng: Rotation.Rng,
	Abilities: { [string]: boolean },
	Started: number,
	XP: number,
	Credits: number,
}

local lanes: { [Player]: Lane } = {}
local laneTaken: { [number]: Player } = {}
local container: Folder

local function difficultyAt(cleared: number): number
	return math.min(1 + cleared * 0.32, 10)
end

local function lend(player: Player, lane: Lane)
	local kit = {}
	for _, set in lane.Ctx.Requires do
		for id in set do
			kit[id] = true
		end
	end
	ProgressionService.SetTemporary(player, kit)
end

local function buildNext(lane: Lane)
	lane.Built += 1
	local index = lane.Built
	local folder = lane.B:Group("Section" .. index)
	lane.Folders[index] = folder
	lane.B:Within(folder, function()
		local difficulty = difficultyAt(index - 1)
		local pool = Sections.Available(difficulty, lane.Abilities)
		local section = lane.Rng:Pick(pool)
		local segments = section.Make(lane.Rng, difficulty)
		table.insert(segments, { "CP" })
		lane.Cursor = CourseBuilder.Segments(lane.Ctx, lane.Cursor, segments)
	end)
end

local function state(lane: Lane): { [string]: any }
	local nextGate = lane.Ctx.Checkpoints[lane.Cleared + 1]
	return {
		Lane = lane.Index,
		CourseId = lane.Ctx.Id,
		Cleared = lane.Cleared,
		Lives = lane.Lives,
		KillY = lane.Ctx.MinY - 30,
		Respawn = if lane.Cleared > 0 then lane.Ctx.Checkpoints[lane.Cleared].Spawn else Dreamline.LaneStart(lane.Index) * CFrame.new(0, 3.5, -8),
		NextGate = if nextGate then nextGate.Volume.CFrame.Position else nil,
		Difficulty = math.floor(difficultyAt(lane.Cleared) * 10) / 10,
	}
end

local function finishRun(player: Player, reason: string)
	local lane = lanes[player]
	if not lane then
		return
	end
	lanes[player] = nil
	laneTaken[lane.Index] = nil
	ProgressionService.SetTemporary(player, nil)
	local profile = DataService.Get(player)
	local best = 0
	local record = false
	if profile then
		best = profile.Endless.Best or 0
		if lane.Cleared > best then
			profile.Endless.Best = lane.Cleared
			best = lane.Cleared
			record = true
		end
		profile.Stats.EndlessRuns = (profile.Stats.EndlessRuns or 0) + 1
		DataService.Push(player, "Endless")
		DataService.MarkDirty(player)
	end
	Events.EndlessEnded:Fire(player, lane.Cleared)
	Events.StatChanged:Fire(player, "EndlessBest")
	local lobbyCF = CFrame.lookAt(Districts.Dreamline + Vector3.new(0, 3.5, 6), Districts.Dreamline + Vector3.new(0, 3.5, -60))
	MovementGuard.AllowTeleport(player, lobbyCF.Position, 20)
	Net.Push(player, "Endless.Ended", {
		Reason = reason,
		Cleared = lane.Cleared,
		Best = best,
		Record = record,
		XP = lane.XP,
		Credits = lane.Credits,
		Seconds = os.clock() - lane.Started,
		Lobby = lobbyCF,
	})
	if record and lane.Cleared >= 5 then
		Notify.Send(player, { Kind = "Unlock", Title = "New Dreamline record", Text = ("%d sections"):format(lane.Cleared), Sound = "Medal" })
	end
	-- Let the runner get clear before the lane dissolves.
	local root = lane.Root
	task.delay(1, function()
		root:Destroy()
	end)
end

local function onStart(player: Player): (boolean, any)
	if lanes[player] then
		return false, "Already running"
	end
	if not MovementGuard.WasNear(player, Districts.Dreamline, 400, 3) then
		return false, "Enter the Dreamline from its lobby"
	end
	if CourseService.Active(player) then
		return false, "Finish your current run first"
	end
	local index: number? = nil
	for i = 1, Dreamline.Lanes do
		if not laneTaken[i] then
			index = i
			break
		end
	end
	if not index then
		return false, "Every lane is busy. Try again in a moment."
	end
	laneTaken[index] = player
	local seed = Rotation.Hash(player.UserId, os.time())
	local start = Dreamline.LaneStart(index)
	local B = Kit.new(container, "Lane" .. index, { Signal = THEME.Signal }, seed)
	local ctx = CourseBuilder.NewContext(B, THEME :: any, ("endless_%d_%d"):format(player.UserId, seed % 100000), 1, start, B.Core)
	local lane: Lane = {
		Index = index,
		Root = B.Root,
		B = B,
		Ctx = ctx,
		Cursor = start,
		Built = 0,
		Folders = {},
		Cleared = 0,
		Lives = LIVES,
		Rng = Rotation.Rng(seed),
		Abilities = ProgressionService.Abilities(player),
		Started = os.clock(),
		XP = 0,
		Credits = 0,
	}
	B:Within(B:Group("Start"), function()
		lane.Cursor = CourseBuilder.Segments(ctx, lane.Cursor, { { "Run", 18 } })
	end)
	for _ = 1, AHEAD do
		buildNext(lane)
	end
	lanes[player] = lane
	lend(player, lane)
	local spawn = start * CFrame.new(0, 3.5, -8)
	MovementGuard.AllowTeleport(player, spawn.Position, 20)
	local info = state(lane)
	info.Spawn = spawn
	return true, info
end

-- index > 0: passed that gate. index == -1: fell (costs a life).
local function onGate(player: Player, index: any)
	local lane = lanes[player]
	if not lane or type(index) ~= "number" then
		return
	end
	if index == -1 then
		lane.Lives -= 1
		Events.Break:Fire(player, "Fall")
		if lane.Lives <= 0 then
			finishRun(player, "Out of lives")
			return
		end
		local info = state(lane)
		MovementGuard.AllowTeleport(player, info.Respawn.Position, 20)
		Net.Push(player, "Endless.State", info)
		return
	end
	if index ~= lane.Cleared + 1 then
		return
	end
	local gate = lane.Ctx.Checkpoints[index]
	if not gate then
		return
	end
	local volume = gate.Volume
	local radius = math.max(volume.Size.X, volume.Size.Y, volume.Size.Z) / 2 + 8
	if not MovementGuard.WasNear(player, volume.CFrame.Position, radius, 1.6) then
		return
	end
	lane.Cleared = index
	-- Rewards grow slowly with depth.
	local scale = 1 + math.floor(index / 10) * 0.25
	local xp = math.floor(Progression.XP.EndlessSection * scale + 0.5)
	local credits = math.floor(Progression.Credits.EndlessSection * scale + 0.5)
	lane.XP += xp
	lane.Credits += credits
	ProgressionService.Grant(player, { XP = xp, Credits = credits }, nil, true)
	Events.EndlessSection:Fire(player, index)
	-- Keep sections ahead, clear the ones far behind.
	while lane.Built < index + AHEAD do
		buildNext(lane)
	end
	for old, folder in lane.Folders do
		if old < index - KEEP_BEHIND then
			folder:Destroy()
			lane.Folders[old] = nil
		end
	end
	lend(player, lane)
	Net.Push(player, "Endless.State", state(lane))
	if index % 10 == 0 then
		Notify.Send(player, { Kind = "Toast", Title = ("%d sections!"):format(index), Text = "The Dreamline bends harder from here." })
	end
end

local function onEnd(player: Player)
	finishRun(player, "Left")
end

function EndlessService.Active(player: Player): boolean
	return lanes[player] ~= nil
end

function EndlessService.Start()
	container = Instance.new("Folder")
	container.Name = "SkylineEndless"
	container.Parent = workspace
	Net.Handle("Endless.Start", onStart)
	Net.On("Endless.Gate", onGate)
	Net.On("Endless.End", onEnd)
	Players.PlayerRemoving:Connect(function(player)
		finishRun(player, "Left")
	end)
end

return EndlessService

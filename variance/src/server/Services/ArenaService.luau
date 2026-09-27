-- Evaluation rooms: allocates arena slots far from the lobby, builds the room
-- for a match (ArenaBuilder), seats surrogate puppets and tears it down after.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Variance.Config)
local TableLayout = require(ReplicatedStorage.Variance.Visual.TableLayout)
local Environments = require(ReplicatedStorage.Variance.Data.Environments)

local World = script.Parent.Parent.World
local ArenaBuilder = require(World.ArenaBuilder)
local PuppetBuilder = require(World.PuppetBuilder)

local ArenaService = {}

export type Arena = {
	Model: Model,
	Slot: number,
	Origin: CFrame,
	Environment: string,
	Seats: { number },
	Puppets: { [number]: Model },
	Released: boolean,
}

local slots: { [number]: Arena? } = {}
local folder: Folder
local rng = Random.new()
local lastEnvironment: string? = nil

function ArenaService:Init(services)
	self.Services = services
	folder = Instance.new("Folder")
	folder.Name = "Arenas"
	folder.Parent = workspace
end

function ArenaService:freeSlots(): number
	local n = 0
	for i = 1, Config.Match.MaxArenas do
		if slots[i] == nil then
			n += 1
		end
	end
	return n
end

-- Builds a room. Returns nil if every table is in use.
function ArenaService:acquire(environment: string?, subjectCount: number, tableTheme: { [string]: any }?): Arena?
	local slot = nil
	for i = 1, Config.Match.MaxArenas do
		if slots[i] == nil then
			slot = i
			break
		end
	end
	if slot == nil then
		return nil
	end
	local base = Config.Match.ArenaOrigin
	local origin = CFrame.new(base[1] + (slot - 1) * Config.Match.ArenaSpacing, base[2], base[3])
	local envId = Environments.pick(environment, rng, lastEnvironment)
	lastEnvironment = envId
	local seats = TableLayout.seatsFor(subjectCount)
	local ok, model = pcall(ArenaBuilder.build, slot, origin, envId, seats, tableTheme)
	if not ok then
		warn("[VARIANCE/Arena] build failed: " .. tostring(model))
		return nil
	end
	model.Parent = folder
	local arena: Arena = {
		Model = model,
		Slot = slot,
		Origin = origin,
		Environment = envId,
		Seats = seats,
		Puppets = {},
		Released = false,
	}
	slots[slot] = arena
	return arena
end

function ArenaService:seatOf(arena: Arena, subjectIndex: number): number
	return arena.Seats[subjectIndex] or arena.Seats[1]
end

function ArenaService:rootCFrame(arena: Arena, seat: number): CFrame
	return arena.Origin * TableLayout.rootCFrame(seat)
end

function ArenaService:centre(arena: Arena): Vector3
	return (arena.Origin * CFrame.new(0, TableLayout.TableTop, 0)).Position
end

-- Seats a surrogate rig for `subjectId` at `seat`. Replaces any previous one.
function ArenaService:addPuppet(arena: Arena, subjectId: number, seat: number, personality: string): Model
	local existing = arena.Puppets[subjectId]
	if existing then
		existing:Destroy()
	end
	local puppet = PuppetBuilder.build(personality, self:rootCFrame(arena, seat), "Puppet_" .. subjectId)
	puppet:SetAttribute("Seat", seat)
	puppet:SetAttribute("Subject", subjectId)
	puppet.Parent = arena.Model:FindFirstChild("Puppets") or arena.Model
	arena.Puppets[subjectId] = puppet
	return puppet
end

function ArenaService:clearPuppets(arena: Arena)
	for id, puppet in arena.Puppets do
		puppet:Destroy()
		arena.Puppets[id] = nil
	end
end

function ArenaService:applyTableTheme(arena: Arena, data: { [string]: any }?)
	ArenaBuilder.applyTableTheme(arena.Model, data)
end

function ArenaService:release(arena: Arena?)
	if arena == nil or arena.Released then
		return
	end
	arena.Released = true
	if slots[arena.Slot] == arena then
		slots[arena.Slot] = nil
	end
	if arena.Model then
		arena.Model:Destroy()
	end
end

function ArenaService:active(): { Arena }
	local out = {}
	for i = 1, Config.Match.MaxArenas do
		if slots[i] then
			table.insert(out, slots[i] :: Arena)
		end
	end
	return out
end

return ArenaService

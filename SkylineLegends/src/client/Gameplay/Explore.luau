-- Exploration: noticing discoveries (landmarks, lost letters, supply caches,
-- secrets) as you reach them, and making uncollected caches and letters
-- shimmer faintly so careful eyes are rewarded.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MathUtil = require(ReplicatedStorage.Shared.Util.MathUtil)
local Net = require(ReplicatedStorage.Shared.Net)
local Tags = require(ReplicatedStorage.Shared.Tags)

local State = require(script.Parent.Parent.Core.State)
local Controller = require(script.Parent.Parent.Movement.Controller)

local Explore = {}

type Spot = { Part: BasePart, Id: string, Kind: string, Small: boolean }

local spots: { Spot } = {}
local nearby: { Spot } = {}
local sent: { [string]: number } = {}
local lastScan = 0
local lastCheck = 0

local function index()
	table.clear(spots)
	for _, part in CollectionService:GetTagged(Tags.Discovery) do
		if part:IsA("BasePart") then
			local id = part:GetAttribute("Id")
			local kind = part:GetAttribute("Kind")
			if type(id) == "string" then
				table.insert(spots, {
					Part = part,
					Id = id,
					Kind = if type(kind) == "string" then kind else "Landmark",
					Small = part.Size.Magnitude < 12,
				})
			end
		end
	end
end

local function found(id: string): boolean
	local profile = State.Profile
	return profile ~= nil and profile.Discoveries ~= nil and profile.Discoveries[id] ~= nil
end

function Explore.Count(kind: string?, district: string?): (number, number)
	local total, have = 0, 0
	for _, spot in spots do
		if (not kind or spot.Kind == kind) and (not district or spot.Part:GetAttribute("District") == district) then
			total += 1
			if found(spot.Id) then
				have += 1
			end
		end
	end
	return have, total
end

-- The undiscovered spots within range of a position (for the map's hints).
function Explore.Undiscovered(): { Spot }
	local result = {}
	for _, spot in spots do
		if not found(spot.Id) then
			table.insert(result, spot)
		end
	end
	return result
end

function Explore.Start()
	index()
	CollectionService:GetInstanceAddedSignal(Tags.Discovery):Connect(function()
		task.defer(index)
	end)
	RunService.Heartbeat:Connect(function()
		local root = Controller.Info.Root
		if not root then
			return
		end
		local now = os.clock()
		local position = root.Position
		if now - lastScan > 1.5 then
			lastScan = now
			table.clear(nearby)
			for _, spot in spots do
				-- Collected caches and letters fade so the uncollected ones stand out.
				if spot.Small and found(spot.Id) and spot.Part.Transparency < 0.7 then
					spot.Part.Transparency = 0.7
				end
				if not found(spot.Id) and (spot.Part.Position - position).Magnitude < spot.Part.Size.Magnitude / 2 + 200 then
					table.insert(nearby, spot)
				end
			end
		end
		if now - lastCheck < 0.2 then
			return
		end
		lastCheck = now
		for _, spot in nearby do
			if found(spot.Id) or now - (sent[spot.Id] or 0) < 3 then
				continue
			end
			local part = spot.Part
			local inside = if spot.Small
				then (part.Position - position).Magnitude < 7
				else MathUtil.InBox(part.CFrame, part.Size, position, 2)
			if inside then
				sent[spot.Id] = now
				Net.Send("Discover.Touch", spot.Id)
			end
		end
	end)
end

return Explore

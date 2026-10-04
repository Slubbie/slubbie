-- Discoveries: hidden courier caches, lost letters, landmarks and secrets.
--
-- The world builder tags each one (Tags.Discovery) with Id, Kind and District.
-- Clients report touches; the server checks the character really was there.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Config.Progression)
local Tags = require(ReplicatedStorage.Shared.Tags)

local DataService = require(script.Parent.Parent.Data.DataService)
local Events = require(script.Parent.Parent.Events)
local MovementGuard = require(script.Parent.MovementGuard)
local Notify = require(script.Parent.Notify)
local ProgressionService = require(script.Parent.ProgressionService)

local DiscoveryService = {}

type Entry = { Part: BasePart, Kind: string, District: string, Title: string?, Text: string? }

local entries: { [string]: Entry } = {}
DiscoveryService.CacheTotals = {} :: { [string]: number }

function DiscoveryService.Index()
	table.clear(entries)
	table.clear(DiscoveryService.CacheTotals)
	for _, instance in CollectionService:GetTagged(Tags.Discovery) do
		if instance:IsA("BasePart") then
			local id = instance:GetAttribute("Id")
			local kind = instance:GetAttribute("Kind")
			local district = instance:GetAttribute("District")
			if type(id) == "string" and type(kind) == "string" and type(district) == "string" then
				entries[id] = {
					Part = instance,
					Kind = kind,
					District = district,
					Title = instance:GetAttribute("Title") :: string?,
					Text = instance:GetAttribute("Text") :: string?,
				}
				if kind == "Cache" then
					DiscoveryService.CacheTotals[district] = (DiscoveryService.CacheTotals[district] or 0) + 1
				end
			end
		end
	end
end

-- Counts per district for the map: { [district] = { Found, Total } }.
function DiscoveryService.Summary(player: Player): { [string]: { Found: number, Total: number } }
	local profile = DataService.Get(player)
	local result = {}
	for id, entry in entries do
		local bucket = result[entry.District]
		if not bucket then
			bucket = { Found = 0, Total = 0 }
			result[entry.District] = bucket
		end
		bucket.Total += 1
		if profile and profile.Discoveries[id] then
			bucket.Found += 1
		end
	end
	return result
end

local function discover(player: Player, id: any)
	if type(id) ~= "string" then
		return
	end
	local entry = entries[id]
	local profile = DataService.Get(player)
	if not entry or not profile or profile.Discoveries[id] then
		return
	end
	local radius = if entry.Kind == "Landmark" or entry.Kind == "Secret" then math.max(entry.Part.Size.Magnitude / 2, 12) + 8 else 12
	if not MovementGuard.WasNear(player, entry.Part.Position, radius, 2) then
		return
	end
	profile.Discoveries[id] = os.time()
	DataService.Push(player, "Discoveries")

	local perks = ProgressionService.Perks(player)
	local creditBonus = 1 + (perks.CreditBonus or 0)
	local xp, credits = Progression.XP.Discovery, Progression.Credits.Discovery
	if entry.Kind == "Cache" then
		credits = Progression.Credits.Cache
	elseif entry.Kind == "Letter" then
		xp = Progression.XP.Letter
	elseif entry.Kind == "Landmark" then
		xp = Progression.XP.Landmark
	elseif entry.Kind == "Secret" then
		xp = Progression.XP.Discovery * 2
		credits = Progression.Credits.Cache
	end
	ProgressionService.Grant(player, { XP = xp, Credits = math.floor(credits * creditBonus) }, nil, true)
	Notify.Send(player, {
		Kind = "Discovery",
		Title = entry.Title or (entry.Kind .. " found"),
		Text = entry.Text,
		Icon = entry.Kind,
		XP = xp,
		Credits = math.floor(credits * creditBonus),
		Sound = "Discovery",
	})
	Events.Discovery:Fire(player, id, entry.Kind, entry.District)
	Events.StatChanged:Fire(player, "Discoveries")
end

function DiscoveryService.Start()
	DiscoveryService.Index()
	Net.On("Discover.Touch", discover)
end

return DiscoveryService

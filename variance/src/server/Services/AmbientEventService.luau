-- Non-gameplay atmosphere during matches: power dips, cameras turning toward a
-- subject, monitors changing, vents, announcements, figures moving behind glass,
-- system warnings, and very rare events (the Proctor watching). The server only
-- picks *what* and *when* (so every viewer sees the same thing); clients play it.
-- Events never fire during the silence before a shot and never affect outcomes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Variance.Config)
local Environments = require(ReplicatedStorage.Variance.Data.Environments)
local Lore = require(ReplicatedStorage.Variance.Data.Lore)

local AmbientEventService = {}

local rng = Random.new()

function AmbientEventService:Init(services)
	self.Services = services
end

local function weightedPick(weights: { [string]: number }): string?
	local total = 0
	for _, w in weights do
		total += w
	end
	if total <= 0 then
		return nil
	end
	local keys = {}
	for k in weights do
		table.insert(keys, k)
	end
	table.sort(keys)
	local roll = rng:NextNumber() * total
	for _, k in keys do
		roll -= weights[k]
		if roll <= 0 then
			return k
		end
	end
	return keys[#keys]
end

function AmbientEventService:trigger(match, kind: string, extra: { [string]: any }?)
	local payload = {
		Kind = kind,
		Seed = rng:NextInteger(1, 2 ^ 30),
		Target = nil,
	}
	-- Cameras and figures turn toward a random subject.
	local ids = {}
	for id in match.Participants do
		table.insert(ids, id)
	end
	payload.Target = ids[rng:NextInteger(1, #ids)]
	if extra then
		for k, v in extra do
			payload[k] = v
		end
	end
	match.Dispatcher:broadcast("Ambient", payload, true)
end

local function rare(self, match)
	local hasProctor = false
	for _, p in match.Participants do
		if p.Personality == "Proctor" then
			hasProctor = true
		end
	end
	if not hasProctor and rng:NextNumber() < Config.Match.ProctorEventChance then
		self:trigger(match, "ProctorWatching", { Text = Lore.RareEvents[1].Text })
		for _, p in match.Participants do
			if p.Kind == "Player" and p.Player and p.Player.Parent then
				self.Services.LoreService:witness(p.Player)
			end
		end
		return
	end
	local event = Lore.RareEvents[rng:NextInteger(2, #Lore.RareEvents)]
	local text = string.gsub(event.Text, "{n}", tostring(rng:NextInteger(180, 9800)))
	self:trigger(match, event.Id, { Text = text })
end

function AmbientEventService:start(match)
	if match.Info.Tutorial then
		return
	end
	match.AmbientActive = true
	local env = Environments.get(match.Arena.Environment)
	task.spawn(function()
		task.wait(12)
		while match.AmbientActive and not match.Closed do
			local lo, hi = Config.Match.AmbientEventInterval[1], Config.Match.AmbientEventInterval[2]
			-- Later Trials are busier.
			local trial = math.max(match.State.Trial, 1)
			local scale = math.clamp(1.15 - trial * 0.15, 0.6, 1)
			task.wait(rng:NextNumber(lo, hi) * scale)
			if not match.AmbientActive or match.Closed then
				break
			end
			local runner = match.Runner
			if runner and not runner.critical and match.Phase == "Playing" then
				if rng:NextNumber() < Config.Match.RareEventChance then
					rare(self, match)
				else
					local kind = weightedPick(env.Events)
					if kind then
						self:trigger(match, kind)
					end
				end
			end
		end
	end)
end

function AmbientEventService:stop(match)
	match.AmbientActive = false
end

return AmbientEventService

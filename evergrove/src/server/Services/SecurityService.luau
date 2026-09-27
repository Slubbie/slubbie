-- Anti-exploit bookkeeping.
--
-- The Net router reports malformed/unknown/over-limit requests here, and
-- services report game-rule violations (acting out of reach, on someone
-- else's farm without permission, spending what they don't have...). Each
-- player's violations are counted in a sliding window; crossing the threshold
-- kicks them (configurable). Everything is logged with context.
--
-- Also tracks character movement so actions right after an impossible jump
-- (teleport exploits) are rejected.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Gameplay = require(Shared.Config.Gameplay)
local Net = require(Shared.Lib.Net)

local CFG = Gameplay.Security

local SecurityService = {}

type Record = { Times: { number }, Total: number }
local records: { [Player]: Record } = {}
local lastPositions: { [Player]: { Pos: Vector3, At: number } } = {}
local suspectUntil: { [Player]: number } = {}
local teleportGrace: { [Player]: number } = {}
local log: { string } = {}

local function record(player: Player): Record
	local r = records[player]
	if not r then
		r = { Times = {}, Total = 0 }
		records[player] = r
	end
	return r
end

local function addLog(line: string)
	table.insert(log, os.date("!%H:%M:%S") .. " " .. line)
	if #log > 300 then
		table.remove(log, 1)
	end
	if CFG.LogToOutput then
		warn("[Security] " .. line)
	end
end

-- Report a violation. `weight` lets clearly malicious things count more.
function SecurityService.Flag(player: Player, reason: string, weight: number?)
	local r = record(player)
	local now = os.clock()
	for _ = 1, weight or 1 do
		table.insert(r.Times, now)
	end
	r.Total += weight or 1
	while #r.Times > 0 and now - r.Times[1] > CFG.Window do
		table.remove(r.Times, 1)
	end
	addLog(string.format("%s (%d): %s [%d in window]", player.Name, player.UserId, reason, #r.Times))
	if CFG.KickThreshold > 0 and #r.Times >= CFG.KickThreshold and not RunService:IsStudio() then
		addLog("Kicking " .. player.Name)
		player:Kick("Connection problem detected. Please rejoin.")
	end
end

function SecurityService.RootPosition(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

-- Is `position` within `reach` studs of the player? Small overshoots are
-- forgiven (latency); large ones are flagged.
function SecurityService.InReach(player: Player, position: Vector3, reach: number): boolean
	local root = SecurityService.RootPosition(player)
	if not root then
		return false
	end
	if (suspectUntil[player] or 0) > os.clock() then
		return false
	end
	local distance = (root - position).Magnitude
	if distance <= reach + 6 then
		return true
	end
	if distance > reach * 3 + 40 then
		SecurityService.Flag(player, string.format("action %.0f studs away (reach %d)", distance, reach))
	end
	return false
end

-- Server-initiated teleports shouldn't look like speed hacks.
function SecurityService.AllowTeleport(player: Player)
	teleportGrace[player] = os.clock() + 3
end

function SecurityService.Log(): { string }
	return log
end

function SecurityService.Init()
	Net.OnViolation(function(player, action, reason)
		SecurityService.Flag(player, string.format("net %s: %s", action, reason))
	end)
end

function SecurityService.Start()
	-- Movement sanity: sample every half second.
	task.spawn(function()
		while true do
			task.wait(0.5)
			local now = os.clock()
			for _, player in Players:GetPlayers() do
				local pos = SecurityService.RootPosition(player)
				if pos then
					local last = lastPositions[player]
					if last and (teleportGrace[player] or 0) < now then
						local speed = (pos - last.Pos).Magnitude / math.max(now - last.At, 0.05)
						if speed > CFG.MaxSpeed then
							suspectUntil[player] = now + 2
							SecurityService.Flag(player, string.format("moved at %.0f studs/s", speed))
						end
					end
					lastPositions[player] = { Pos = pos, At = now }
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		records[player] = nil
		lastPositions[player] = nil
		suspectUntil[player] = nil
		teleportGrace[player] = nil
	end)
end

return SecurityService

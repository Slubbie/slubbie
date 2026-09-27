-- Developer tools, gated so they never reach regular players.
--
-- Access: Config.Debug.Enabled AND (Studio with AllowInStudio, OR the UserId is
-- in Config.Debug.Admins). Every command re-checks permission on the server;
-- a request without permission is reported to AntiExploitService as High.
--
-- Commands (Debug.Command name, args):
--   Sequence {Pattern="CCHH", Now=bool}   force the next Load, or replace the current one
--   Integrity {Subject, Value}            set a subject's Integrity
--   Give {Subject, Id}                    give an instrument
--   Infinite {On}                         instruments are not consumed
--   AI {Subject, Mode}                    Casual/Standard/Advanced/Expert, AlwaysSelf,
--                                         AlwaysOther, Random, Stall, or "" to clear
--   EndLoad {} / EndTrial {Team} / SkipToTrial {Trial}
--   Speed {Scale}                         presentation speed for your match
--   Latency {Ms}                          delay your own actions (latency testing)
--   Ambient {Kind}                        fire an ambient event in your match
--   Reveal {}                             print the hidden sequence (debug only)
--   Validation {}                         run the server-side validation suite
--   Flags {}                              recent anti-exploit flags
--   Grant {XP, Marks}                     progression testing
--   SoloQuick {Personality, Difficulty, Pattern}  start a solo match with a forced first Load

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Variance.Config)
local Engine = require(ReplicatedStorage.Variance.Core.Engine)
local Rules = require(ReplicatedStorage.Variance.Core.Rules)
local Instruments = require(ReplicatedStorage.Variance.Core.Instruments)
local Difficulty = require(ReplicatedStorage.Variance.Core.AI.Difficulty)
local Rng = require(ReplicatedStorage.Variance.Util.Rng)

local DebugService = {}

local latency: { [Player]: number } = {}

function DebugService:Init(services)
	self.Services = services
end

function DebugService:allowed(player: Player): boolean
	if not Config.Debug.Enabled then
		return false
	end
	if Config.Debug.AllowInStudio and RunService:IsStudio() then
		return true
	end
	return table.find(Config.Debug.Admins, player.UserId) ~= nil
end

function DebugService:latencyFor(player: Player): number
	return latency[player] or 0
end

local function matchFor(self, player: Player)
	return self.Services.MatchService:matchOf(player)
end

local function num(v: any, default: number): number
	if type(v) == "number" and v == v then
		return v
	end
	return default
end

-- Server validation suite: feeds hostile input through the real validators.
function DebugService:validationSuite()
	local results = {}
	local function check(name: string, passed: boolean)
		table.insert(results, { Name = name, Passed = passed })
	end
	local network = self.Services.NetworkService
	check("rejects NaN numbers", not network.checkArg("number", 0 / 0))
	check("rejects infinite numbers", not network.checkArg("number", math.huge))
	check("rejects oversized strings", not network.checkArg("string", string.rep("x", 500)))
	check("rejects functions in tables", not network.checkArg("table", { f = print }))
	local deep = {}
	local cursor = deep
	for _ = 1, 10 do
		cursor.x = {}
		cursor = cursor.x
	end
	check("rejects deeply nested tables", not network.checkArg("table", deep))
	local wide = {}
	for i = 1, 400 do
		wide[i] = i
	end
	check("rejects huge tables", not network.checkArg("table", wide))
	check("accepts optional nil", network.checkArg("table?", nil))

	local state = Engine.new({
		Rules = Rules.build("Standard"),
		Rng = Rng.pure(1),
		Subjects = { { Name = "A" }, { Name = "B" } },
	})
	while state.Phase ~= "AwaitAction" do
		Engine.advance(state)
	end
	local owner = state.Turn.Owner
	local other = owner == 1 and 2 or 1
	check("rejects acting out of turn", not Engine.act(state, other, { Kind = "Fire", Target = owner }, state.Turn.Token))
	check("rejects stale tokens", not Engine.act(state, owner, { Kind = "Fire", Target = owner }, state.Turn.Token - 1))
	check("rejects empty slots", not Engine.act(state, owner, { Kind = "Use", Slot = 1 }, state.Turn.Token))
	check("rejects fractional slots", not Engine.act(state, owner, { Kind = "Use", Slot = 1.5 }, state.Turn.Token))
	check("rejects unknown targets", not Engine.act(state, owner, { Kind = "Fire", Target = 9 }, state.Turn.Token))
	check("rejects unknown kinds", not Engine.act(state, owner, { Kind = "Win" }, state.Turn.Token))
	local ok = Engine.act(state, owner, { Kind = "Fire", Target = owner }, state.Turn.Token)
	check("accepts a legal action", ok == true)
	check("rejects the duplicate of that action", not Engine.act(state, owner, { Kind = "Fire", Target = owner }, state.Turn.Token - 1))
	check("custom rules are clamped", Rules.sanitizeCustom({ MaxIntegrity = 1e9 }).MaxIntegrity == 8)
	return results
end

local commands = {}

function commands.Sequence(self, player, args)
	local match = matchFor(self, player)
	local pattern = type(args.Pattern) == "string" and string.upper(args.Pattern) or ""
	if match == nil or Engine.parsePattern(pattern) == nil then
		return false, "Need a match and a pattern of C/H (max 16)."
	end
	if args.Now then
		if match.Runner.busy or match.State.Phase ~= "AwaitAction" then
			return false, "Wait for a turn."
		end
		Engine.debugSetSequence(match.State, pattern)
		match.Dispatcher:sendSnapshots()
		return true, "Current Load replaced."
	end
	match.State.ForcedNext = pattern
	return true, "Next Load forced."
end

function commands.Integrity(self, player, args)
	local match = matchFor(self, player)
	if match == nil then
		return false, "Not in a match."
	end
	local ok = Engine.debugSetIntegrity(match.State, num(args.Subject, 1), math.floor(num(args.Value, 1)))
	match.Dispatcher:sendSnapshots()
	return ok, ok and "Set." or "Unknown subject."
end

function commands.Give(self, player, args)
	local match = matchFor(self, player)
	if match == nil or not Instruments.isValid(args.Id) then
		return false, "Need a match and a valid instrument id."
	end
	local ok = Engine.debugGive(match.State, num(args.Subject, 1), args.Id)
	match.Dispatcher:sendSnapshots()
	return ok, ok and "Given." or "Tray full or unknown subject."
end

function commands.Infinite(self, player, args)
	local match = matchFor(self, player)
	if match == nil then
		return false, "Not in a match."
	end
	match.State.Rules.InfiniteInstruments = args.On == true
	return true, "Infinite instruments " .. (args.On and "on" or "off")
end

function commands.AI(self, player, args)
	local match = matchFor(self, player)
	local participant = match and match.Participants[num(args.Subject, 2)]
	if participant == nil or participant.AI == nil then
		return false, "No surrogate in that seat."
	end
	local mode = args.Mode
	if Difficulty.Tiers[mode] then
		participant.AI.Override = nil
		participant.AI.DifficultyId = mode
		participant.AI.Brain:setDifficulty(Difficulty.get(mode))
		return true, "Difficulty set to " .. mode
	end
	participant.AI.Override = (mode ~= "" and mode) or nil
	return true, "Behaviour: " .. tostring(participant.AI.Override or "normal")
end

function commands.EndLoad(self, player)
	local match = matchFor(self, player)
	if match == nil or match.Runner.busy then
		return false, "Wait for a turn."
	end
	local ok = Engine.debugEndLoad(match.State)
	match.Runner.wake:Fire()
	return ok, "Load ended."
end

function commands.EndTrial(self, player, args)
	local match = matchFor(self, player)
	if match == nil or match.Runner.busy then
		return false, "Wait for a turn."
	end
	local ok = Engine.debugEndTrial(match.State, math.floor(num(args.Team, 1)))
	match.Runner.wake:Fire()
	return ok, "Trial ended."
end

function commands.SkipToTrial(self, player, args)
	local match = matchFor(self, player)
	if match == nil or match.Runner.busy or match.State.Phase ~= "AwaitAction" then
		return false, "Wait for a turn."
	end
	local trial = math.clamp(math.floor(num(args.Trial, 3)), 1, 9)
	match.State.Trial = trial - 1
	match.State.Load = nil
	match.State.Phase = Engine.Phase.TrialSetup
	match.Runner.wake:Fire()
	return true, "Skipping to Trial " .. trial
end

function commands.Speed(self, player, args)
	local match = matchFor(self, player)
	if match == nil then
		return false, "Not in a match."
	end
	match.DebugSpeed = math.clamp(num(args.Scale, 1), 0.1, 3)
	return true, "Speed " .. match.DebugSpeed
end

function commands.Latency(_self, player, args)
	latency[player] = math.clamp(num(args.Ms, 0), 0, 3000) / 1000
	return true, "Simulated latency " .. math.floor(latency[player] * 1000) .. "ms"
end

function commands.Ambient(self, player, args)
	local match = matchFor(self, player)
	if match == nil or type(args.Kind) ~= "string" then
		return false, "Need a match and an event kind."
	end
	self.Services.AmbientEventService:trigger(match, args.Kind, { Text = args.Text })
	return true, "Triggered " .. args.Kind
end

function commands.Reveal(self, player)
	local match = matchFor(self, player)
	if match == nil or match.State.Load == nil then
		return false, "No Load."
	end
	local chars = {}
	for i, cell in match.State.Load.Cells do
		chars[i] = cell.Charged and "C" or "H"
	end
	return true, "Sequence: " .. table.concat(chars)
end

function commands.Validation(self)
	return true, self:validationSuite()
end

function commands.Flags(self)
	return true, self.Services.AntiExploitService:recent(40)
end

function commands.Grant(self, player, args)
	self.Services.ProgressionService:award(player, math.max(0, num(args.XP, 0)), math.max(0, num(args.Marks, 0)), "Debug")
	return true, "Granted."
end

function commands.SoloQuick(self, player, args)
	local ok, result = self.Services.MatchService:startSolo(player, args.Personality or "Ledger", args.Difficulty or "Standard")
	if ok and type(args.Pattern) == "string" then
		local match = self.Services.MatchService:get(result)
		if match then
			match.State.ForcedNext = string.upper(args.Pattern)
		end
	end
	return ok, result
end

function DebugService:Start()
	local network = self.Services.NetworkService
	network:handle("Debug.Command", function(player, name, args)
		if not self:allowed(player) then
			self.Services.AntiExploitService:flag(player, "debug without permission", "High", name)
			return false, "Not permitted."
		end
		local command = commands[name]
		if command == nil then
			return false, "Unknown command."
		end
		print(string.format("[VARIANCE/Debug] %s ran %s", player.Name, name))
		return command(self, player, args or {})
	end)
	self.Services.DataService.Loaded:Connect(function(player)
		if self:allowed(player) then
			network:push(player, "Debug", { Allowed = true })
		end
	end)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		latency[player] = nil
	end)
end

return DebugService

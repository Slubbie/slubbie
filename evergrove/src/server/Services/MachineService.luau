-- Artisan machines: queues, timers, output storage, upgrades and auto mode.
--
-- State lives on the placed record (profile.Farm.Placed[uid].M) so it moves,
-- saves and loads with the machine:
--   M = {
--     Lv = 1..MaxLevel,
--     Q  = { job... }       job = { I, Q, M?, G?, O, N, D, X? }  (input id/quality/mutations/genes,
--                                  output id, output count, base seconds, extra inputs taken)
--     S  = unix start of the head job (nil when idle)
--     B  = unix time the head job finished but output was full (blocked)
--     O  = { stack... }     finished goods waiting to be collected
--     A  = auto mode (with a Logistics Hub: pull inputs from / push outputs to silos)
--     In = input spec for auto mode ("strawberry", "#Fruit")
--   }
--
-- Nothing ticks per machine. `advance` works out what finished between two
-- timestamps; it runs when someone opens the machine, collects, queues, when
-- automation passes by, and in a light sweep that keeps the models' status
-- attributes fresh for the client (State, Ends, Item, Ready).
-- Offline progress is capped at Config/Machines.OfflineCap.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local MachinesConfig = require(Shared.Config.Machines)
local Net = require(Shared.Lib.Net)
local Signal = require(Shared.Lib.Signal)
local Registry = require(Shared.Lib.Registry)
local ItemUtil = require(Shared.Lib.ItemUtil)
local Genetics = require(Shared.Lib.Genetics)
local Stats = require(Shared.Lib.Stats)
local Format = require(Shared.Lib.Format)
local WeatherMath = require(Shared.Lib.WeatherMath)
local GameTime = require(Shared.Lib.GameTime)

local S = require(script.Parent)

local MachineService = {}
MachineService.Finished = Signal.new() -- (player, record, stack) a job completed

local REACH = 16
local SWEEP = 2
local random = Random.new()

-- Helpers ---------------------------------------------------------------------------------------------

local function now(): number
	return os.time()
end

local function recordOf(player: Player, uid: string): (any?, any?, any?)
	local profile = S.Data.Get(player)
	local record = profile and profile.Farm.Placed[uid]
	local placeable = record and Registry.Placeables[record.Id]
	if not placeable or not placeable.Function or placeable.Function.Kind ~= "Machine" then
		return nil, nil, nil
	end
	local machine = Registry.Machines[placeable.Function.Machine]
	if not machine then
		return nil, nil, nil
	end
	record.M = record.M or { Lv = 1, Q = {}, O = {} }
	record.M.Q = record.M.Q or {}
	record.M.O = record.M.O or {}
	record.M.Lv = math.clamp(tonumber(record.M.Lv) or 1, 1, MachinesConfig.MaxLevel)
	return record, machine, record.M
end

function MachineService.QueueSize(profile: any, state: any, machine: any): number
	return machine.Queue + (state.Lv - 1) * MachinesConfig.LevelQueue + math.floor(Stats.Effect(profile, "MachineQueue"))
end

function MachineService.OutputSize(state: any, machine: any): number
	return machine.Output + (state.Lv - 1) * MachinesConfig.LevelOutput
end

local function outputCount(state: any): number
	local n = 0
	for _, stack in state.O do
		n += stack.N
	end
	return n
end

-- Power boost from windmills/solar arrays whose radius covers the machine.
local function powerBoost(player: Player, record: any): number
	local farm = S.Farm.Get(player)
	if not farm then
		return 0
	end
	local cx, cz = S.Building.CenterTile(record)
	local best = 0
	local weather = WeatherMath.Current(GameTime.Now())
	local wdef = WeatherMath.Def(weather)
	for _, effect in farm.Effects do
		local fn = effect.Def.Function
		if fn and fn.Kind == "Power" then
			local r = (effect.Def.Radius or 0) + math.max(effect.Def.Size[1], effect.Def.Size[2]) / 2
			if (effect.X - cx) ^ 2 + (effect.Z - cz) ^ 2 <= r * r then
				local boost = fn.Speed
				if fn.Windy and wdef and (wdef.Wind or 0) >= 0.5 then
					boost = fn.Windy
				elseif fn.Sunny and (weather == "Sunny" or weather == "Heatwave") then
					boost = fn.Sunny
				end
				best = math.max(best, boost)
			end
		end
	end
	return best
end

-- Effective speed multiplier (higher = faster).
function MachineService.Speed(player: Player, record: any, machine: any): number
	local profile = S.Data.Get(player)
	local state = record.M
	local speed = 1 + (state.Lv - 1) * MachinesConfig.LevelSpeed
	if profile then
		speed += Stats.Effect(profile, "MachineSpeed")
		if machine.Id == "furnace" then
			speed += Stats.Effect(profile, "SmeltSpeed")
		end
	end
	speed += powerBoost(player, record)
	return math.max(0.1, speed)
end

local function addOutput(state: any, stack: any)
	for _, existing in state.O do
		if ItemUtil.CanStack(existing, stack) then
			existing.N += stack.N
			return
		end
	end
	table.insert(state.O, stack)
end

-- Build the output stack for a finished job.
local function produce(player: Player, machine: any, state: any, job: any): any
	local profile = S.Data.Get(player)
	local quality = job.Q or 1
	local upChance = MachinesConfig.QualityUpChance * (state.Lv - 1) + (if profile then Stats.Effect(profile, "QualityUp") else 0)
	if random:NextNumber() < upChance then
		quality = math.min(quality + 1, 6)
	end
	local count = job.N
	if profile and random:NextNumber() < Stats.Effect(profile, "MachineBonus") then
		count += 1
	end
	local stack = ItemUtil.New(job.O, count, quality, job.M)
	if machine.Id == "seed_maker" then
		-- Seeds carry the crop's genes (drifting a little) and maybe a latent trait.
		stack.N = random:NextInteger(1, 3)
		stack.Q = nil
		stack.M = nil
		local improve = if profile then math.clamp(Stats.SkillLevel(profile, "Farming") / 50, 0, 1) else 0
		stack.G = Genetics.Inherit(job.G, random, improve)
		local latent = Genetics.LatentFrom(job.M, random)
		if latent then
			stack.T = latent
		end
	end
	return stack
end

-- Work out finished jobs up to `t`. Returns true if anything changed.
local function advance(player: Player, record: any, machine: any, t: number): boolean
	local state = record.M
	if #state.Q == 0 then
		state.S = nil
		state.B = nil
		return false
	end
	state.S = state.S or t
	local changed = false
	local speed = MachineService.Speed(player, record, machine)
	local capacity = MachineService.OutputSize(state, machine)
	local guard = 0
	while #state.Q > 0 and guard < 200 do
		guard += 1
		local job = state.Q[1]
		local finishAt = state.S + job.D / speed
		if t < finishAt then
			break
		end
		if outputCount(state) + job.N > capacity then
			state.B = state.B or finishAt
			break
		end
		table.remove(state.Q, 1)
		local stack = produce(player, machine, state, job)
		addOutput(state, stack)
		MachineService.Finished:Fire(player, record, stack)
		-- A job released from a block starts the next one now, not in the past.
		state.S = if state.B then t else finishAt
		state.B = nil
		changed = true
	end
	if #state.Q == 0 then
		state.S = nil
	end
	return changed
end

function MachineService.Advance(player: Player, uid: string): boolean
	local record, machine = recordOf(player, uid)
	if not record then
		return false
	end
	local changed = advance(player, record, machine, now())
	if changed then
		S.Data.Changed(player, "Farm", "Placed")
	end
	return changed
end

-- Model status for the client (animations, "ready" bubbles).
local function publish(player: Player, uid: string, record: any, machine: any)
	local model = S.Building.Model(player, uid)
	if not model then
		return
	end
	local state = record.M
	local status = "Idle"
	local ends = 0
	if #state.Q > 0 then
		if state.B then
			status = "Blocked"
		else
			status = "Working"
			ends = math.floor((state.S or now()) + state.Q[1].D / MachineService.Speed(player, record, machine))
		end
	end
	local ready = outputCount(state)
	if status == "Idle" and ready > 0 then
		status = "Ready"
	end
	local function set(name: string, value: any)
		if model:GetAttribute(name) ~= value then
			model:SetAttribute(name, value)
		end
	end
	set("State", status)
	set("Ends", if ends > 0 then ends else nil)
	set("Item", if #state.Q > 0 then state.Q[1].O else nil)
	set("Ready", if ready > 0 then ready else nil)
	set("Queued", #state.Q)
	set("Level", state.Lv)
	set("Auto", state.A == true)
end

function MachineService.Publish(player: Player, uid: string)
	local record, machine = recordOf(player, uid)
	if record then
		publish(player, uid, record, machine)
	end
end

-- Access ---------------------------------------------------------------------------------------------------

-- Resolve the machine owner from the actor's position and check reach and permission.
local function access(actor: Player, uid: string, level: string): (Player?, any?, any?, string?)
	for owner in S.Farm.All() do
		local profile = S.Data.Get(owner)
		if profile and profile.Farm.Placed[uid] then
			local record, machine = recordOf(owner, uid)
			if not record then
				return nil, nil, nil, "That's not a machine"
			end
			if not S.Farm.CanAct(actor, owner, level) then
				return nil, nil, nil, "You need permission to use machines here"
			end
			local position = S.Building.WorldPosition(owner, uid)
			if not position or not S.Security.InReach(actor, position, REACH) then
				return nil, nil, nil, "Walk closer to the machine"
			end
			return owner, record, machine, nil
		end
	end
	return nil, nil, nil, "Machine not found"
end

-- Snapshot for the machine UI.
local function snapshot(owner: Player, uid: string, record: any, machine: any, viewer: Player): any
	local profile = S.Data.Get(owner)
	local state = record.M
	local speed = MachineService.Speed(owner, record, machine)
	local queue = {}
	for i, job in state.Q do
		queue[i] = { I = job.I, O = job.O, N = job.N, Q = job.Q, M = job.M, D = job.D / speed }
	end
	-- What the viewer could put in right now.
	local options = {}
	local viewerProfile = S.Data.Get(viewer)
	if viewerProfile then
		local seen = {}
		for ref, stack in viewerProfile.Inventory.Slots do
			local recipe, outId = Registry.MachineRecipe(machine.Id, stack.Id)
			local key = ItemUtil.Key(stack)
			if recipe and not seen[key] and (recipe.Level or 1) <= state.Lv then
				seen[key] = true
				table.insert(options, { Ref = "inv:" .. ref, Id = stack.Id, Q = stack.Q, M = stack.M, Have = stack.N, Need = recipe.In.N, Out = outId, N = recipe.N or 1, Time = recipe.Time / speed, Extra = recipe.Extra })
			end
		end
	end
	local nextLevel = state.Lv + 1
	return {
		Uid = uid,
		Machine = machine.Id,
		Owner = owner.UserId,
		Level = state.Lv,
		MaxLevel = MachinesConfig.MaxLevel,
		UpgradeCost = if nextLevel <= MachinesConfig.MaxLevel then MachinesConfig.UpgradeCost[nextLevel] else nil,
		UpgradeMats = if nextLevel <= MachinesConfig.MaxLevel then MachinesConfig.UpgradeMats[nextLevel] else nil,
		Speed = speed,
		Queue = queue,
		QueueSize = MachineService.QueueSize(profile, state, machine),
		Start = state.S,
		Blocked = state.B ~= nil,
		Output = state.O,
		OutputSize = MachineService.OutputSize(state, machine),
		Auto = state.A == true,
		Input = state.In,
		Logistics = MachineService.HasLogistics(owner),
		Options = options,
		Now = now(),
	}
end

function MachineService.HasLogistics(player: Player): boolean
	local profile = S.Data.Get(player)
	if not profile then
		return false
	end
	for _, record in profile.Farm.Placed do
		local def = Registry.Placeables[record.Id]
		if def and def.Function and def.Function.Kind == "Logistics" then
			return true
		end
	end
	return false
end

-- Queueing ----------------------------------------------------------------------------------------------------

-- Put `times` jobs into a machine using `source` stacks. `take(count)` removes
-- input items and returns the stack taken; `takeExtra(id, n)` removes extras.
local function enqueue(owner: Player, record: any, machine: any, sample: any, times: number, take: (number) -> any?, takeExtra: (string, number) -> boolean, haveExtra: (string, number) -> boolean): (number, string?)
	local profile = S.Data.Get(owner)
	local state = record.M
	local recipe, outId = Registry.MachineRecipe(machine.Id, sample.Id)
	if not recipe or not outId then
		return 0, "The " .. machine.Name .. " can't use that"
	end
	if (recipe.Level or 1) > state.Lv then
		return 0, "Upgrade the machine to level " .. recipe.Level .. " first"
	end
	advance(owner, record, machine, now())
	local free = MachineService.QueueSize(profile, state, machine) - #state.Q
	if free <= 0 then
		return 0, "The queue is full"
	end
	local queued = 0
	for _ = 1, math.min(times, free) do
		local extrasOk = true
		for _, extra in recipe.Extra or {} do
			if not haveExtra(extra.Id, extra.N) then
				extrasOk = false
			end
		end
		if not extrasOk then
			if queued == 0 then
				local names = {}
				for _, extra in recipe.Extra or {} do
					table.insert(names, extra.N .. " " .. Registry.Items[extra.Id].Name)
				end
				return 0, "You also need " .. table.concat(names, ", ")
			end
			break
		end
		local taken = take(recipe.In.N)
		if not taken then
			if queued == 0 then
				return 0, "You need " .. recipe.In.N .. " " .. ItemUtil.DisplayName(sample)
			end
			break
		end
		local extras = {}
		for _, extra in recipe.Extra or {} do
			takeExtra(extra.Id, extra.N)
			table.insert(extras, { Id = extra.Id, N = extra.N })
		end
		if #state.Q == 0 then
			state.S = now()
			state.B = nil
		end
		table.insert(state.Q, {
			I = taken.Id,
			Q = taken.Q,
			M = taken.M,
			G = taken.G,
			In = recipe.In.N,
			O = outId,
			N = recipe.N or 1,
			D = recipe.Time,
			X = if #extras > 0 then extras else nil,
		})
		queued += 1
	end
	return queued, nil
end

local function queue(actor: Player, uid: string, ref: string, times: number)
	local owner, record, machine, reason = access(actor, uid, "Machines")
	if not owner then
		return false, reason
	end
	times = math.clamp(times, 1, 50)
	local sample = S.Inventory.Slot(actor, ref)
	if not sample then
		return false, "Pick an item from your bag"
	end
	local queued, why = enqueue(owner, record, machine, sample, times, function(count)
		local current = S.Inventory.Slot(actor, ref)
		if not current or current.N < count or current.Id ~= sample.Id then
			return nil
		end
		return S.Inventory.TakeFromSlot(actor, ref, count)
	end, function(id, n)
		return S.Inventory.Remove(actor, id, n) ~= nil
	end, function(id, n)
		return S.Inventory.Count(actor, id) >= n
	end)
	if queued == 0 then
		return false, why
	end
	S.Data.Changed(owner, "Farm", "Placed")
	publish(owner, uid, record, machine)
	S.Tutorial.Event(actor, "Machine")
	local position = S.Building.WorldPosition(owner, uid)
	if position then
		S.Notify.FX(position, "MachineLoad", { Machine = machine.Id, Item = sample.Id }, 120)
	end
	return true, snapshot(owner, uid, record, machine, actor)
end

-- Collect finished goods into the actor's bag (owner's bag if a helper collects).
local function collect(actor: Player, uid: string)
	local owner, record, machine, reason = access(actor, uid, "Machines")
	if not owner then
		return false, reason
	end
	local state = record.M
	advance(owner, record, machine, now())
	if #state.O == 0 then
		return false, "Nothing is ready yet"
	end
	local receiver = owner
	local collected = 0
	local total = 0
	local remaining = {}
	for _, stack in state.O do
		if S.Inventory.CanFit(receiver, { stack }) then
			S.Inventory.Add(receiver, stack, { Source = machine.Name, Silent = true })
			collected += stack.N
			total += ItemUtil.UnitValue(stack) * stack.N
			S.Collection.OnItem(receiver, stack)
			S.Quest.Progress(receiver, "Process", stack.Id, stack.N)
			S.Data.AddStat(receiver, "Processed", stack.N)
			S.Data.AddStat(receiver, "ArtisanMade", stack.N)
		else
			table.insert(remaining, stack)
		end
	end
	state.O = remaining
	if collected == 0 then
		return false, "Your bag is full"
	end
	-- XP: a little per item, more for long jobs.
	S.Skill.AddXP(receiver, machine.Skill, math.max(1, math.floor(collected * 2 + total / 400)))
	-- Unblock: the head job (if finished) can flush now.
	advance(owner, record, machine, now())
	S.Data.Changed(owner, "Farm", "Placed")
	publish(owner, uid, record, machine)
	S.Notify.Toast(actor, string.format("Collected %d item%s from the %s", collected, if collected == 1 then "" else "s", machine.Name), "Success")
	if actor ~= owner then
		S.Notify.Toast(owner, actor.DisplayName .. " collected " .. collected .. " goods from your " .. machine.Name .. " for you.", "Info")
	end
	S.Tutorial.Event(actor, "Collect")
	if #remaining > 0 then
		S.Notify.Toast(actor, "Some goods didn't fit and are still in the machine.", "Warning")
	end
	return true, snapshot(owner, uid, record, machine, actor)
end

-- Refund one job's inputs.
local function refund(player: Player, job: any, source: string)
	S.Inventory.Add(player, { Id = job.I, N = job.In or 1, Q = job.Q, M = job.M, G = job.G }, { Source = source, Silent = true })
	for _, extra in job.X or {} do
		S.Inventory.Give(player, extra.Id, extra.N, nil, nil, { Source = source, Silent = true })
	end
end

local function cancel(actor: Player, uid: string, index: number)
	local owner, record, machine, reason = access(actor, uid, "Machines")
	if not owner then
		return false, reason
	end
	if actor ~= owner and not S.Farm.CanAct(actor, owner, "Trusted") then
		return false, "Only the owner can cancel jobs"
	end
	local state = record.M
	advance(owner, record, machine, now())
	local job = state.Q[index]
	if not job then
		return false, "Nothing in that slot"
	end
	table.remove(state.Q, index)
	if index == 1 then
		state.S = if #state.Q > 0 then now() else nil
		state.B = nil
	end
	refund(owner, job, "Cancelled job")
	S.Data.Changed(owner, "Farm", "Placed")
	publish(owner, uid, record, machine)
	return true, snapshot(owner, uid, record, machine, actor)
end

local function upgrade(actor: Player, uid: string)
	local owner, record, machine, reason = access(actor, uid, "Machines")
	if not owner or owner ~= actor then
		return false, reason or "Only the owner can upgrade machines"
	end
	local state = record.M
	local nextLevel = state.Lv + 1
	if nextLevel > MachinesConfig.MaxLevel then
		return false, "Already at max level"
	end
	local cost = MachinesConfig.UpgradeCost[nextLevel]
	local mats = MachinesConfig.UpgradeMats[nextLevel]
	local profile = S.Data.Get(owner)
	if profile.Coins < cost then
		return false, "Not enough coins (" .. Format.Commas(cost) .. ")"
	end
	for _, mat in mats do
		if S.Inventory.Count(owner, mat.Id) < mat.N then
			return false, "You need " .. mat.N .. " " .. Registry.Items[mat.Id].Name
		end
	end
	-- Settle work at the old speed first.
	advance(owner, record, machine, now())
	S.Economy.Spend(owner, cost, "Machine upgrade")
	for _, mat in mats do
		S.Inventory.Remove(owner, mat.Id, mat.N)
	end
	state.Lv = nextLevel
	S.Data.Changed(owner, "Farm", "Placed")
	S.Data.AddStat(owner, "MachineUpgrades")
	S.Quest.Progress(owner, "Upgrade", machine.Id, 1)
	publish(owner, uid, record, machine)
	local position = S.Building.WorldPosition(owner, uid)
	if position then
		S.Notify.FX(position, "LevelUp", { Machine = machine.Id, Level = nextLevel }, 120)
	end
	S.Notify.Toast(owner, machine.Name .. " upgraded to level " .. nextLevel .. "!", "Success")
	return true, snapshot(owner, uid, record, machine, actor)
end

local function configure(actor: Player, uid: string, config: any)
	local owner, record, machine, reason = access(actor, uid, "Machines")
	if not owner then
		return false, reason
	end
	if owner ~= actor and not S.Farm.CanAct(actor, owner, "Trusted") then
		return false, "Only the owner can change machine settings"
	end
	local state = record.M
	if config.Auto ~= nil then
		state.A = config.Auto == true or nil
	end
	if config.Input ~= nil then
		if config.Input == false or config.Input == "" then
			state.In = nil
		elseif type(config.Input) == "string" and #config.Input <= 48 then
			-- Must be something this machine accepts.
			local spec = config.Input
			local ok = false
			if string.sub(spec, 1, 1) == "#" then
				for _, recipe in machine.Recipes do
					if recipe.In.Tag == string.sub(spec, 2) then
						ok = true
					end
				end
			else
				ok = Registry.MachineRecipe(machine.Id, spec) ~= nil
			end
			if not ok then
				return false, "The " .. machine.Name .. " can't use that"
			end
			state.In = spec
		end
	end
	S.Data.Changed(owner, "Farm", "Placed")
	publish(owner, uid, record, machine)
	return true, snapshot(owner, uid, record, machine, actor)
end

-- Picking up a machine returns its queued inputs and finished goods.
function MachineService.Release(player: Player, uid: string)
	local record, machine = recordOf(player, uid)
	if not record then
		return
	end
	local state = record.M
	advance(player, record, machine, now())
	for _, job in state.Q do
		refund(player, job, machine.Name)
	end
	for _, stack in state.O do
		S.Inventory.Add(player, stack, { Source = machine.Name, Silent = true })
	end
	-- Keep the level on the item? Levels are per placed machine; refund upgrade value as coins.
	if state.Lv > 1 then
		local spent = 0
		for level = 2, state.Lv do
			spent += MachinesConfig.UpgradeCost[level]
		end
		S.Economy.AddCoins(player, math.floor(spent * 0.5), "Machine upgrade refund")
		S.Notify.Toast(player, "Half the upgrade cost was refunded.", "Info")
	end
	record.M = nil
end

-- Automation hooks ---------------------------------------------------------------------------------------------

-- One auto cycle for a machine: push output to silos, pull inputs from silos.
function MachineService.AutoCycle(player: Player, uid: string): (number, number)
	local record, machine = recordOf(player, uid)
	if not record or not record.M.A then
		return 0, 0
	end
	local state = record.M
	local t = now()
	advance(player, record, machine, t)
	local pushed, pulled = 0, 0
	local keep = {}
	for _, stack in state.O do
		local leftover = S.Inventory.SiloAdd(player, stack)
		pushed += stack.N - leftover
		if leftover > 0 then
			stack.N = leftover
			table.insert(keep, stack)
		end
	end
	state.O = keep
	advance(player, record, machine, t)
	if state.In then
		local profile = S.Data.Get(player)
		local free = MachineService.QueueSize(profile, state, machine) - #state.Q
		if free > 0 then
			-- Find a silo item matching the input spec with a valid recipe.
			local silo = profile.Silo.Items
			local sample
			for _, stack in silo do
				if Registry.Matches(stack.Id, state.In) and Registry.MachineRecipe(machine.Id, stack.Id) then
					sample = stack
					break
				end
			end
			if sample then
				local id = sample.Id
				local queued = enqueue(player, record, machine, sample, free, function(count)
					local taken = S.Inventory.SiloTake(player, id, count)
					if #taken == 0 then
						return nil
					end
					local total = 0
					for _, s in taken do
						total += s.N
					end
					if total < count then
						for _, s in taken do
							S.Inventory.SiloAdd(player, s)
						end
						return nil
					end
					-- Jobs use the first stack's quality/mutations.
					local first = taken[1]
					return { Id = first.Id, N = count, Q = first.Q, M = first.M, G = first.G }
				end, function(extraId, n)
					return #S.Inventory.SiloTake(player, extraId, n) > 0
				end, function(extraId, n)
					return S.Inventory.SiloCountOf(player, extraId) >= n
				end)
				pulled += queued
			end
		end
	end
	if pushed > 0 or pulled > 0 then
		S.Data.Changed(player, "Farm", "Placed")
		publish(player, uid, record, machine)
	end
	return pushed, pulled
end

-- Iterate over a player's machines.
function MachineService.Each(player: Player, fn: (string, any, any) -> ())
	local profile = S.Data.Get(player)
	if not profile then
		return
	end
	for uid, record in profile.Farm.Placed do
		local def = Registry.Placeables[record.Id]
		if def and def.Function and def.Function.Kind == "Machine" then
			local r, machine = recordOf(player, uid)
			if r then
				fn(uid, r, machine)
			end
		end
	end
end

-- Offline: shift start times so at most OfflineCap seconds count.
local function applyOfflineCap(player: Player, offlineSeconds: number)
	local excess = offlineSeconds - MachinesConfig.OfflineCap
	if excess <= 0 then
		return
	end
	MachineService.Each(player, function(_, record)
		local state = record.M
		if state.S then
			state.S += excess
		end
		if state.B then
			state.B += excess
		end
	end)
end

-- Lifecycle ------------------------------------------------------------------------------------------------------

function MachineService.Init()
	Net.Handle("MachineGet", function(player, uid)
		local owner, record, machine, reason = access(player, uid, "View")
		if not owner then
			return false, reason
		end
		if advance(owner, record, machine, now()) then
			S.Data.Changed(owner, "Farm", "Placed")
		end
		publish(owner, uid, record, machine)
		return true, snapshot(owner, uid, record, machine, player)
	end)
	Net.Handle("MachineQueue", queue)
	Net.Handle("MachineCollect", collect)
	Net.Handle("MachineCancel", cancel)
	Net.Handle("MachineUpgrade", upgrade)
	Net.Handle("MachineConfig", configure)
end

function MachineService.Start()
	S.Data.Loaded:Connect(function(player, _profile, info)
		applyOfflineCap(player, info.OfflineSeconds or 0)
	end)
	S.Building.Spawned:Connect(function(player, uid, _model, def)
		if def.Function and def.Function.Kind == "Machine" then
			MachineService.Publish(player, uid)
		end
	end)
	-- Light sweep: finish due jobs and refresh model status attributes.
	task.spawn(function()
		while true do
			task.wait(SWEEP)
			local t = now()
			for player in S.Farm.All() do
				local changed = false
				MachineService.Each(player, function(uid, record, machine)
					local state = record.M
					if #state.Q > 0 and not state.B then
						local finishAt = (state.S or t) + state.Q[1].D / MachineService.Speed(player, record, machine)
						if t >= finishAt then
							-- Either finishes the job or marks the machine blocked (output full).
							if advance(player, record, machine, t) then
								changed = true
							end
							publish(player, uid, record, machine)
						end
					end
				end)
				if changed then
					S.Data.Changed(player, "Farm", "Placed")
				end
			end
		end
	end)
end

return MachineService

-- The conductor. Turns each engine event into a staged moment: rigs, the
-- Arbiter, cells, props, camera, lights, sound and the big on-screen cards.
--
-- The server waits Core/Timeline.after(event) between events, so every beat
-- here is scheduled to finish inside that window (scaled by the match's timing
-- scale). Nothing in this file decides anything: it only presents what the
-- server said happened, from this viewer's point of view.
--
-- Also the bridge for the lobby <-> table transition (arena binding, rigs,
-- camera) and for per-match chatter (dialogue, presence, emotes, ambience).

local HapticService = game:GetService("HapticService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Dialogue = require(ReplicatedStorage.Variance.Data.Dialogue)
local Instruments = require(ReplicatedStorage.Variance.Core.Instruments)
local Modifiers = require(ReplicatedStorage.Variance.Core.Modifiers)
local Surrogates = require(ReplicatedStorage.Variance.Data.Surrogates)
local InstrumentProps = require(ReplicatedStorage.Variance.Visual.InstrumentProps)
local TableLayout = require(ReplicatedStorage.Variance.Visual.TableLayout)
local Format = require(ReplicatedStorage.Variance.Util.Format)
local Theme = require(script.Parent.Parent.UI.Theme)
local TableView = require(script.Parent.Parent.Match.TableView)

local MatchPresenter = {}

local C -- controllers
local arena: Model? = nil
local origin = CFrame.identity
local view = nil
local bound: { [number]: Model } = {}
local firing: { [string]: any }? = nil
local handles = { Bubbles = {}, Cuffs = {}, Links = {} }
local bindToken = 0
local stepConnection: RBXScriptConnection? = nil
local lastIntensity = 0

local EFFECT_DELAY_ON = { Clamped = 0.8, Dampener = 0.7, Capacitor = 0.65, Overclock = 0.65 }

function MatchPresenter:Init(controllers)
	C = controllers
	self.Controllers = controllers
end

---------------------------------------------------------------------------
-- Lookups
---------------------------------------------------------------------------

local function scene()
	return C.MatchClient.Scene
end

local function state()
	return C.MatchClient.State
end

local function scale(): number
	local s = scene()
	return s and s.Rules and s.Rules.TimingScale or 1
end

local function you(): number?
	return C.MatchClient:you()
end

local function isMe(id: number?): boolean
	return id ~= nil and id == you()
end

local function rig(id: number?)
	return C.AnimationController:rigOf(id)
end

local function nameOf(id: number?): string
	local info = C.MatchClient:info(id)
	if id ~= nil and isMe(id) then
		return "YOU"
	end
	return info and string.upper(info.Name or "SUBJECT") or "SUBJECT"
end

local function seatOf(id: number?): number?
	local info = C.MatchClient:info(id)
	return info and info.Seat or nil
end

local function seatPoint(id: number?, offset: Vector3): Vector3
	local seat = seatOf(id) or 1
	return (origin * TableLayout.rootCFrame(seat) * CFrame.new(offset)).Position
end

local function headPos(id: number?): Vector3
	local r = rig(id)
	if r and r.Head then
		return r.Head.Position
	end
	return seatPoint(id, Vector3.new(0, 1.5, 0))
end

local function chestPos(id: number?): Vector3
	local r = rig(id)
	if r and r.TorsoCF then
		return (r.TorsoCF * CFrame.new(0, 0.3, -0.5)).Position
	end
	return seatPoint(id, Vector3.new(0, 0.3, -0.5))
end

-- Point just under the chin, where a reversed muzzle rests.
local function chinPos(id: number?): Vector3
	local r = rig(id)
	if r and r.Head then
		return (r.Head * CFrame.new(0, -0.35, -0.55)).Position
	end
	return seatPoint(id, Vector3.new(0, 1.15, -0.55))
end

-- Public API for other controllers (EnvironmentController ambience).
function MatchPresenter:subjectHead(id: number?): Vector3?
	if id == nil or arena == nil then
		return nil
	end
	return headPos(id)
end

function MatchPresenter:arena(): Model?
	return arena
end

function MatchPresenter:tableView()
	return view
end

local function rumble(strength: number, duration: number)
	if C.SettingsController:get("Vibration") == false or C.InputController:lastInput() ~= "Gamepad" then
		return
	end
	pcall(function()
		HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Large, strength)
		HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, strength * 0.6)
	end)
	task.delay(duration, function()
		pcall(function()
			HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Large, 0)
			HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, 0)
		end)
	end)
end

local function after(seconds: number, fn: () -> ())
	local token = bindToken
	task.delay(seconds * scale(), function()
		if token == bindToken and arena then
			fn()
		end
	end)
end

local function announce(key: string, values: { [string]: any }?)
	local lines = Dialogue.Announcer[key]
	if lines == nil or #lines == 0 then
		return
	end
	local line = Dialogue.fill(lines[math.random(1, #lines)], values or {})
	C.AudioController:announce()
	C.UIController:subtitle(nil, line, 3.2)
end

---------------------------------------------------------------------------
-- Escalation: one number for lights and score
---------------------------------------------------------------------------

local function refreshIntensity()
	local st, sc = state(), scene()
	if st == nil or sc == nil then
		return
	end
	local trial = math.max(st.Trial or 1, 1)
	local toWin = st.TrialsToWin or 2
	local value = 0.1 + 0.18 * (trial - 1)
	local matchPoint = false
	local lowest = math.huge
	for _, s in st.Subjects do
		if not s.Eliminated then
			lowest = math.min(lowest, s.Integrity or 0)
		end
		if (s.TrialWins or 0) >= toWin - 1 then
			matchPoint = true
		end
	end
	if matchPoint and trial > 1 then
		value += 0.18
	end
	if lowest <= 1 then
		value += 0.2
	elseif lowest <= 2 then
		value += 0.08
	end
	if st.SuddenDeath then
		value = 1
	end
	value = math.clamp(value, 0, 1)
	lastIntensity = value
	C.EnvironmentController:setIntensity(value)
	C.AudioController:setMusic("Match", value)
	-- Heartbeat follows your own Integrity.
	local me = st.Subjects[you() or -1]
	if me and not me.Eliminated then
		local integrity = me.Integrity or 0
		local rate = if integrity <= 1 then 1 elseif integrity == 2 and (me.MaxIntegrity or 0) >= 4 then 0.45 else 0
		C.AudioController:setHeartbeat(rate)
	else
		C.AudioController:setHeartbeat(0)
	end
end

---------------------------------------------------------------------------
-- Persistent effect visuals
---------------------------------------------------------------------------

local function clearHandles()
	for _, h in handles.Bubbles do
		h.stop()
	end
	for _, h in handles.Cuffs do
		h.stop()
	end
	for _, h in handles.Links do
		h.stop()
	end
	handles = { Bubbles = {}, Cuffs = {}, Links = {} }
end

local function setEffectVisual(subjectId: number, effect: string, active: boolean)
	local vfx = C.VFXController
	if effect == "Dampener" then
		local existing = handles.Bubbles[subjectId]
		if active and existing == nil then
			handles.Bubbles[subjectId] = vfx:bubble(function()
				return chestPos(subjectId) + Vector3.new(0, 0.4, 0.3)
			end, Theme.Colors.Hollow, 2.2)
			C.AudioController:play("Dampener", { At = chestPos(subjectId) })
		elseif not active and existing then
			existing.pop()
			handles.Bubbles[subjectId] = nil
		end
	elseif effect == "Clamped" then
		local existing = handles.Cuffs[subjectId]
		C.AnimationController:setState(rig(subjectId), "Clamped", if active then 1 else 0)
		if active and existing == nil then
			handles.Cuffs[subjectId] = vfx:cuffs(function()
				local r = rig(subjectId)
				if r then
					return r.HandR, r.HandL
				end
				return nil, nil
			end, Theme.Colors.Accent)
		elseif not active and existing then
			existing.stop()
			handles.Cuffs[subjectId] = nil
		end
	elseif effect == "Capacitor" or effect == "Overclock" then
		local st = state()
		if st and st.Turn and st.Turn.Owner == subjectId then
			C.WeaponController:setCharge(effect, active)
			if active then
				local muzzle = C.WeaponController:muzzleCF()
				vfx:arc(C.WeaponController:chamberCF().Position, muzzle.Position, if effect == "Capacitor" then Theme.Colors.Accent else Theme.Colors.Bad, 0.5)
			end
		end
	end
end

local function setTether(active: boolean)
	for _, h in handles.Links do
		h.stop()
	end
	handles.Links = {}
	if not active then
		return
	end
	local st = state()
	if st == nil then
		return
	end
	for id, s in st.Subjects do
		if not s.Eliminated then
			table.insert(
				handles.Links,
				C.VFXController:link(function()
					return C.WeaponController:chamberCF().Position
				end, function()
					return chestPos(id)
				end, Color3.fromRGB(190, 140, 255))
			)
		end
	end
	C.AudioController:play("Tether", { At = C.WeaponController:chamberCF().Position })
end

-- Charge glow on the device follows whoever holds the turn.
local function refreshCharges(owner: number?)
	local st = state()
	local s = st and owner and st.Subjects[owner]
	C.WeaponController:setCharge("Capacitor", s ~= nil and s.Effects.Capacitor == true)
	C.WeaponController:setCharge("Overclock", s ~= nil and s.Effects.Overclock == true)
end

local function refreshGauge()
	C.WeaponController:setGauge(C.MatchClient:probability())
end

local function refreshMonitors()
	local st, sc = state(), scene()
	if st == nil or sc == nil or view == nil then
		return
	end
	for id, s in st.Subjects do
		local info = sc.Subjects[id]
		view:updateMonitor(id, s, info and info.Name or "SUBJECT", s.TrialWins or 0, st.TrialsToWin or 2)
	end
end

---------------------------------------------------------------------------
-- Binding the room
---------------------------------------------------------------------------

local function findArena(name: string): Model?
	local folder = workspace:FindFirstChild("Arenas")
	local found = folder and folder:FindFirstChild(name) or workspace:FindFirstChild(name, true)
	if found and found:IsA("Model") then
		return found
	end
	return nil
end

local function modelFor(id: number): Model?
	local info = C.MatchClient:info(id)
	if info == nil or arena == nil then
		return nil
	end
	if info.IsAI then
		local puppets = arena:FindFirstChild("Puppets")
		local puppet = puppets and puppets:FindFirstChild("Puppet_" .. id)
		return if puppet and puppet:IsA("Model") then puppet else nil
	end
	local player = info.UserId and Players:GetPlayerByUserId(info.UserId)
	return player and player.Character or nil
end

-- Registers every subject's rig, retrying while they stream in, and keeps
-- watching for the rest of the match (respawns, re-streams).
local function bindRigs(token: number)
	task.spawn(function()
		while token == bindToken and arena do
			local sc = scene()
			if sc == nil then
				return
			end
			local missing = false
			for id, info in sc.Subjects do
				local model = modelFor(id)
				if model == nil then
					missing = true
				elseif bound[id] ~= model or C.AnimationController:rigFor(model) == nil then
					local r = C.AnimationController:register(model, {
						Kind = "Seated",
						Subject = id,
						Personality = if info.IsAI then info.Personality else nil,
						Origin = origin,
						Seat = info.Seat,
						Local = isMe(id),
					})
					if r then
						bound[id] = model
						local st = state()
						local s = st and st.Subjects[id]
						if s then
							C.AnimationController:setState(r, "Slumped", if s.Eliminated then 1 else 0)
							C.AnimationController:setState(r, "Clamped", if s.Effects.Clamped then 1 else 0)
						end
					else
						missing = true
					end
				end
			end
			task.wait(if missing then 0.3 else 1)
		end
	end)
end

-- Places everything for a state we joined mid-way (rejoin, spectate, resync).
local function restoreScene()
	local st = state()
	if st == nil or view == nil then
		return
	end
	for id, s in st.Subjects do
		view:sync(id, s.Instruments or {})
		for effect, active in s.Effects or {} do
			if active then
				setEffectVisual(id, effect, true)
			end
		end
	end
	if st.Tether then
		setTether(true)
	end
	local owner = st.Turn and st.Turn.Owner
	if owner and st.Belief and #st.Belief.Track > 0 then
		C.WeaponController:present(seatOf(owner) or 1, 0.01)
		C.WeaponController:setLoaded(true)
	end
	refreshCharges(owner)
	refreshGauge()
	refreshMonitors()
	refreshIntensity()
end

function MatchPresenter:teardown()
	bindToken += 1
	clearHandles()
	firing = nil
	if view then
		view:destroy()
		view = nil
	end
	C.WeaponController:detach()
	C.AnimationController:clearSeated()
	table.clear(bound)
	arena = nil
	if stepConnection then
		stepConnection:Disconnect()
		stepConnection = nil
	end
end

function MatchPresenter:onBegan(sc)
	self:teardown()
	local token = bindToken
	task.spawn(function()
		-- Wait for the room to stream in.
		local found = nil
		local deadline = os.clock() + 15
		while token == bindToken and os.clock() < deadline do
			found = findArena(sc.Arena)
			if found and found:FindFirstChild("Table") and found:FindFirstChild("Arbiter") then
				break
			end
			task.wait(0.2)
		end
		if token ~= bindToken then
			return
		end
		if found == nil then
			warn("[VARIANCE/Presenter] room " .. tostring(sc.Arena) .. " never streamed in")
			C.UIController:toast("CONNECTION", "The evaluation room is still loading...", "Warn")
			return
		end
		arena = found
		origin = sc.Origin or found:GetAttribute("Origin") or CFrame.identity
		local seats = {}
		for id, info in sc.Subjects do
			seats[id] = info.Seat
		end
		view = TableView.new(found, origin, seats, sc.Rules.Capacity or 4, C)
		view:bindMonitors()
		stepConnection = RunService.Heartbeat:Connect(function()
			if view then
				view:step()
			end
		end)
		C.EnvironmentController:enter(found, sc.Environment)
		C.WeaponController:attach(found)
		bindRigs(token)
		if sc.Spectating then
			C.CameraController:toSpectate(origin)
		else
			C.CameraController:toSeat(origin, seatOf(sc.You) or 1)
		end
		C.AudioController:setMusic("Match", 0.1)
		restoreScene()
	end)
end

---------------------------------------------------------------------------
-- Instrument choreography
---------------------------------------------------------------------------

-- Carries a prop from the tray to a use point with the actor's hand, calls
-- `effect` on arrival, then dissolves it. All times scale with the match.
local function useProp(actorId: number, prop: Model?, usePoint: () -> Vector3, effect: () -> (), opts: { [string]: any }?)
	local o = opts or {}
	local r = rig(actorId)
	local s = scale()
	local anim = C.AnimationController
	local vfx = C.VFXController
	local token = bindToken
	task.spawn(function()
		local reachTime = 0.3 * s
		local carryTime = (o.Carry or 0.35) * s
		local propPos = prop and prop.PrimaryPart and prop.PrimaryPart.Position or chestPos(actorId)
		if r then
			anim:setIntent(r, { Kind = "Reach", Point = propPos + Vector3.new(0, 0.3, 0), Side = o.Side })
		end
		task.wait(reachTime)
		if token ~= bindToken then
			return
		end
		C.AudioController:play("Pickup", { At = propPos, Pitch = 1.6 })
		local carryStart = os.clock()
		local arrived = false
		while token == bindToken and os.clock() - carryStart < carryTime + (o.Hold or 0.25) * s do
			local t = (os.clock() - carryStart) / carryTime
			local point = usePoint()
			if r then
				anim:setIntent(r, { Kind = "Reach", Point = point, Side = o.Side })
			end
			if prop and prop.Parent and r and r.HandR then
				local hand = if o.Side == "L" then r.HandL else r.HandR
				if hand then
					InstrumentProps.place(prop, hand * CFrame.new(0, -0.35, 0) * CFrame.Angles(math.pi / 2, 0, 0))
				end
			end
			if not arrived and t >= 1 then
				arrived = true
				effect()
			end
			task.wait()
		end
		if not arrived then
			effect()
		end
		if prop and prop.Parent then
			vfx:dissolve(prop, 0.3, o.Color)
		end
		if r and token == bindToken then
			anim:setIntent(r, nil)
		end
	end)
end

local function playInstrument(data)
	local id = data.Id
	local actorId = data.Actor
	local st = state()
	if st == nil then
		return
	end
	local def = Instruments.get(id)
	local weapon = C.WeaponController
	local vfx = C.VFXController
	local audio = C.AudioController
	local anim = C.AnimationController
	local r = rig(actorId)

	-- Which prop left the tray.
	local prop = nil
	if view then
		local old = {}
		for i, p in view.Props[actorId] or {} do
			old[i] = p:GetAttribute("Instrument")
		end
		local slot = TableView.removedSlot(old, data.Inventory or {}, id)
		if slot then
			prop = view:take(actorId, slot)
		end
		view:reconcile(actorId, data.Inventory or {})
	end

	local mine = isMe(actorId)
	local reveal = data.Reveal and data.Reveal[1]
	local rare = def and def.Rarity == "Rare"
	if rare then
		C.UIController:banner(def.Name, string.upper(def.Short), "Accent", 1.4 * scale())
	end

	local port = function()
		return weapon:portCF().Position + Vector3.new(0, 0.3, 0)
	end
	local window = function()
		return (weapon:chamberCF() * CFrame.new(0.9, 0.1, 0)).Position
	end
	local chest = function()
		return chestPos(actorId) + Vector3.new(0, 0, -0.4)
	end
	local centre = function()
		return (origin * CFrame.new(0, TableLayout.TableTop + 0.6, 0)).Position
	end

	if id == "Lens" then
		useProp(actorId, prop, window, function()
			anim:play(r, "Peer")
			audio:play("Lens", { At = window() })
			weapon:showWindow(if mine and reveal then reveal.Charged else nil, 1.0 * scale())
			C.CameraController:focus(weapon:chamberCF().Position, if mine then 0.7 else 0.25, 1.1)
		end, { Carry = 0.35, Hold = 0.6, Color = Theme.Colors.Hollow })
	elseif id == "Ejector" then
		useProp(actorId, prop, port, function()
			audio:play("Ejector", { At = port() })
			local outcome = data.Outcome or {}
			weapon:ejectLoaded(outcome.Charged == true)
			C.CameraController:focus(weapon:chamberCF().Position, 0.4, 1)
		end, { Carry = 0.3, Hold = 0.4 })
	elseif id == "Suture" then
		useProp(actorId, prop, chest, function()
			audio:play("Suture", { At = chest() })
			vfx:motes(chest(), Theme.Colors.Hollow, 18)
			vfx:flash(chest(), Theme.Colors.Hollow, 1.4, 0.4, 2)
		end, { Carry = 0.35, Hold = 0.3, Color = Theme.Colors.Hollow })
	elseif id == "Capacitor" then
		useProp(actorId, prop, port, function()
			audio:play("Capacitor", { At = port() })
			vfx:arc(port(), weapon:muzzleCF().Position, Theme.Colors.Accent, 0.4)
		end, { Carry = 0.3, Hold = 0.3, Color = Theme.Colors.Accent })
	elseif id == "Clamp" then
		local targetId = data.Target
		useProp(actorId, nil, centre, function() end, { Carry = 0.2, Hold = 0.1 })
		if prop and view then
			local targetRig = rig(targetId)
			local to = if targetRig and targetRig.HandR then targetRig.HandR else CFrame.new(chestPos(targetId))
			view:move(prop, to, 0.55 * scale(), 1.2, 0.2 * scale(), function()
				audio:play("Clamp", { At = to.Position })
				vfx:sparks(to.Position, Vector3.new(0, 1, 0), Theme.Colors.Accent, 12)
				vfx:dissolve(prop, 0.25)
				anim:play(targetRig, "Flinch")
			end)
		end
	elseif id == "Inverter" then
		useProp(actorId, prop, port, function()
			audio:play("Inverter", { At = port() })
			local c = Color3.fromRGB(180, 130, 255)
			vfx:flash(weapon:chamberCF().Position, c, 1.8, 0.35, 4)
			vfx:ring(weapon:chamberCF() * CFrame.Angles(0, 0, 0), c, 1.6, 0.6)
			weapon:turnChamber(0.5)
		end, { Carry = 0.3, Hold = 0.35 })
	elseif id == "Sonar" then
		useProp(actorId, prop, port, function()
			audio:play("Sonar", { At = port() })
			local c = Color3.fromRGB(150, 220, 215)
			for i = 0, 2 do
				task.delay(i * 0.3 * scale(), function()
					if arena then
						vfx:ring(CFrame.new(weapon:chamberCF().Position), c, 3 + i * 1.5, 0.7)
					end
				end)
			end
		end, { Carry = 0.3, Hold = 0.7 })
	elseif id == "Dampener" then
		useProp(actorId, prop, chest, function()
			vfx:flash(chest(), Theme.Colors.Hollow, 1.6, 0.4, 2)
		end, { Carry = 0.35, Hold = 0.25, Color = Theme.Colors.Hollow })
	elseif id == "Rotor" then
		useProp(actorId, prop, port, function()
			weapon:turnChamber(1)
		end, { Carry = 0.3, Hold = 0.5 })
	elseif id == "Overclock" then
		useProp(actorId, prop, port, function()
			audio:play("Overclock", { At = port() })
			vfx:sparks(port(), Vector3.new(0, 1, 0), Theme.Colors.Bad, 14)
		end, { Carry = 0.3, Hold = 0.3, Color = Theme.Colors.Bad })
	elseif id == "Serum" then
		local good = data.Outcome and data.Outcome.Good
		anim:play(r, "Drink")
		audio:play("Drink", { At = headPos(actorId), Delay = 0.5 * scale() })
		useProp(actorId, prop, function()
			return headPos(actorId) + Vector3.new(0, -0.4, 0)
		end, function()
			after(0.5, function()
				if good then
					audio:play("SerumGood", { At = chestPos(actorId) })
					vfx:motes(chestPos(actorId), Theme.Colors.Good, 20)
					vfx:flash(chestPos(actorId), Theme.Colors.Good, 2, 0.4, 3)
				else
					audio:play("SerumBad", { At = chestPos(actorId) })
					vfx:sparks(chestPos(actorId), Vector3.new(0, 1, 0), Theme.Colors.Bad, 18)
					anim:play(r, "Flinch")
				end
			end)
		end, { Carry = 0.45, Hold = 0.7 })
	elseif id == "PowerTap" then
		useProp(actorId, prop, function()
			return (origin * TableLayout.trayCFrame(seatOf(actorId) or 1) * CFrame.new(1.8, 0.3, 0)).Position
		end, function()
			audio:play("PowerTap", { At = chestPos(actorId) })
			vfx:arc(chestPos(actorId), (origin * TableLayout.trayCFrame(seatOf(actorId) or 1)).Position, Theme.Colors.Accent, 0.6)
			vfx:sparks(chestPos(actorId), Vector3.new(0, 1, 0), Theme.Colors.Accent, 16)
			anim:play(r, "Flinch")
		end, { Carry = 0.35, Hold = 0.5 })
	elseif id == "Tether" then
		useProp(actorId, prop, centre, function()
			vfx:flash(centre(), Color3.fromRGB(190, 140, 255), 2.4, 0.5, 4)
		end, { Carry = 0.4, Hold = 0.4 })
	elseif id == "Scrambler" then
		useProp(actorId, prop, port, function()
			audio:play("Scrambler", { At = port() })
			weapon:rattle(1.1 * scale(), 0.07)
			local outcome = data.Outcome or {}
			local kinds = {}
			local size = outcome.PoolSize or 0
			local charged = outcome.PoolCharged
			for i = 1, size do
				table.insert(kinds, if charged == nil then "?" elseif i <= charged then "C" else "H")
			end
			weapon:showRack(kinds, 0.04)
			after(0.9, function()
				weapon:blankRack()
				weapon:loadRack(0.5 * scale())
			end)
			C.UIController:banner(
				"RE-CAST",
				if charged == nil then string.format("%d CELLS :: MIX UNKNOWN", size) else string.format("%d CHARGED · %d HOLLOW", charged, size - charged),
				"Accent",
				1.4 * scale()
			)
		end, { Carry = 0.3, Hold = 0.9 })
	else
		useProp(actorId, prop, port, function() end)
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local handlers: { [string]: (data: any) -> () } = {}

handlers.MatchStart = function()
	local sc = scene()
	if sc == nil or arena == nil then
		return
	end
	C.AudioController:play("Stinger")
	announce("MatchStart", { mode = sc.ModeName or "Standard" })
	local cams = arena:FindFirstChild("Cameras")
	local e1 = cams and cams:FindFirstChild("Establish1") :: BasePart?
	local e2 = cams and cams:FindFirstChild("Establish2") :: BasePart?
	local shots = {}
	if e1 then
		table.insert(shots, { From = e1.CFrame, To = e1.CFrame * CFrame.new(0, -1.2, -5), Duration = 2.2 * scale(), Fov = 45 })
	end
	if e2 then
		table.insert(shots, { From = e2.CFrame * CFrame.new(-1, 0, 0), To = e2.CFrame * CFrame.new(1, 0, -1.2), Duration = 1.7 * scale(), Fov = 38 })
	end
	if not sc.Spectating then
		local seat = seatOf(sc.You) or 1
		local eye = origin * TableLayout.eyeCFrame(seat)
		local facing = (origin * TableLayout.seatCFrame(seat)).Rotation
		local final = CFrame.new(eye.Position) * facing * CFrame.Angles(-0.3, 0, 0)
		table.insert(shots, { From = final * CFrame.new(0, 1.4, 3.5), To = final, Duration = 1.0 * scale(), Fov = 68, Essential = true })
	end
	C.CameraController:shots(shots, true)
	-- Surrogates take a look at who they are up against.
	for id, info in sc.Subjects do
		if info.IsAI then
			local r = rig(id)
			local others = C.MatchClient:opponents()
			local target = nil
			for _, other in others do
				if other ~= id then
					target = other
					break
				end
			end
			if target == nil then
				for otherId in sc.Subjects do
					if otherId ~= id then
						target = otherId
						break
					end
				end
			end
			C.AnimationController:lookAt(r, headPos(target))
			after(2.5, function()
				C.AnimationController:play(r, "Nod")
			end)
		end
	end
	refreshMonitors()
	refreshIntensity()
end

handlers.TrialStart = function(data)
	local st = state()
	if st == nil then
		return
	end
	clearHandles()
	C.WeaponController:clearSpent()
	C.WeaponController:clearRack()
	C.WeaponController:setCharge("Capacitor", false)
	C.WeaponController:setCharge("Overclock", false)
	C.WeaponController:rest(0.6)
	C.CameraController:setSlump(false)
	for id in st.Subjects do
		local r = rig(id)
		C.AnimationController:setState(r, "Slumped", if st.Subjects[id].Eliminated then 1 else 0)
		C.AnimationController:setState(r, "Clamped", 0)
		C.AnimationController:stop(r)
		if view then
			view:sync(id, (data.Inventories and data.Inventories[id]) or {})
		end
	end
	if view and data.Capacity then
		view:setCapacity(data.Capacity)
	end
	local final = data.Trial >= (st.TrialsToWin or 2) * 2 - 1
	local maxIntegrity = 0
	for _, v in data.MaxIntegrity or {} do
		maxIntegrity = math.max(maxIntegrity, v)
	end
	local parts = { string.format("INTEGRITY %d", maxIntegrity) }
	if (data.Draws or 0) > 0 then
		table.insert(parts, string.format("%d INSTRUMENT%s PER LOAD", data.Draws, data.Draws == 1 and "" or "S"))
	end
	if data.Rare then
		table.insert(parts, "RARE INSTRUMENTS")
	end
	if data.Surge then
		table.insert(parts, "SURGE ACTIVE")
	end
	C.UIController:banner("TRIAL " .. Format.roman(data.Trial), table.concat(parts, "  ·  "), if final then "Bad" else "Accent", 2.4 * scale())
	C.AudioController:play("Stinger", { Pitch = 1 + (data.Trial - 1) * 0.12 })
	announce(if final then "TrialStartFinal" else "TrialStart", { trial = Format.roman(data.Trial), integrity = maxIntegrity })
	if data.TrialModifiers and #data.TrialModifiers > 0 then
		local names = {}
		for _, modId in data.TrialModifiers do
			local m = Modifiers.get(modId)
			table.insert(names, m and m.Name or modId)
		end
		after(1.2, function()
			announce("Modifiers", { list = table.concat(names, ", ") })
		end)
	end
	if data.Trial > 1 and arena then
		local cams = arena:FindFirstChild("Cameras")
		local overhead = cams and cams:FindFirstChild("Overhead") :: BasePart?
		if overhead then
			C.CameraController:shots({ { From = overhead.CFrame * CFrame.new(0, 0, 2), To = overhead.CFrame, Duration = 1.4 * scale(), Fov = 55 } })
		end
	end
	refreshMonitors()
	refreshIntensity()
end

handlers.LoadStart = function(data)
	local weapon = C.WeaponController
	local s = scale()
	local n = data.PoolSize or 0
	local kinds = {}
	for i = 1, n do
		if data.PoolCharged == nil then
			kinds[i] = "?"
		else
			kinds[i] = if i <= data.PoolCharged then "C" else "H"
		end
	end
	weapon:clearSpent()
	weapon:centre(0.45 * s)
	weapon:showRack(kinds, 0.08 * s)
	local rackPos = (origin * TableLayout.rackCFrame()).Position
	C.CameraController:focus(rackPos, 0.55, (1.1 + 0.25 * n) * s)
	if data.PoolCharged == nil then
		C.UIController:banner(string.format("%d CELLS", n), "COMPOSITION WITHHELD", "Warn", (1.2 + 0.2 * n) * s)
		announce("LoadBlind", { total = n })
	else
		C.UIController:banner(
			string.format("%d CHARGED  ·  %d HOLLOW", data.PoolCharged, n - data.PoolCharged),
			if data.SuddenDeath then "SUDDEN DEATH" elseif data.Surge then "THE FINAL CELL CARRIES A SURGE" else "LOAD " .. tostring(data.LoadInTrial or 1),
			if data.Surge or data.SuddenDeath then "Bad" else "Text",
			(1.2 + 0.2 * n) * s
		)
		if (data.LoadInTrial or 1) == 1 or math.random() < 0.4 then
			announce("Load", { charged = data.PoolCharged, hollow = n - data.PoolCharged })
		end
	end
	after(0.55 + 0.12 * n, function()
		weapon:blankRack()
	end)
	after(0.8 + 0.12 * n, function()
		weapon:loadRack(0.2 * n * s)
	end)
	after(0.85 + 0.32 * n, function()
		weapon:cycle(nil, s)
		weapon:setLoaded(true)
		refreshGauge()
	end)
	-- Precision: your private glimpse.
	if data.Reveal and #data.Reveal > 0 then
		after(1.0 + 0.3 * n, function()
			C.AudioController:play("Lens")
		end)
	end
	-- Surrogates watch the rack.
	for id, info in (scene() or { Subjects = {} }).Subjects do
		if info.IsAI then
			C.AnimationController:lookAt(rig(id), rackPos)
		end
	end
	refreshIntensity()
end

handlers.Dealt = function(data)
	if view == nil then
		return
	end
	for id, list in data.Inventories or {} do
		view:deal(id, list, (data.Lost and data.Lost[id]) or {}, 0.22 * scale())
	end
	for id, lost in data.Lost or {} do
		if #lost > 0 and isMe(id) then
			C.UIController:toast("TRAY FULL", string.format("%d instrument%s lost.", #lost, #lost == 1 and " was" or "s were"), "Warn")
		end
	end
end

local function lookAtTurn(owner: number)
	local sc = scene()
	if sc == nil then
		return
	end
	for id, info in sc.Subjects do
		if info.IsAI then
			local r = rig(id)
			if id == owner then
				C.AnimationController:lookAt(r, C.WeaponController:presentCF(seatOf(id) or 1).Position)
				task.delay(0.9, function()
					if r and state() and state().Turn.Owner == id then
						local opponents = C.MatchClient:opponents()
						local target = nil
						for _, other in opponents do
							if other ~= id then
								target = other
							end
						end
						if target == nil then
							for other in sc.Subjects do
								if other ~= id then
									target = other
								end
							end
						end
						C.AnimationController:lookAt(r, headPos(target))
						if math.random() < 0.45 then
							C.AnimationController:play(r, "Think", 0.9 + math.random() * 0.3)
						end
					end
				end)
			else
				C.AnimationController:lookAt(r, headPos(owner))
			end
		end
	end
end

handlers.TurnStart = function(data)
	local owner = data.Owner
	C.WeaponController:present(seatOf(owner) or 1, 0.5 * scale())
	refreshCharges(owner)
	lookAtTurn(owner)
	if isMe(owner) then
		C.AudioController:play("Confirm")
		rumble(0.2, 0.08)
	elseif not C.MatchClient:spectating() then
		C.CameraController:focus(headPos(owner), 0.3, 1.2)
	else
		C.CameraController:focus(headPos(owner), 0.5, 2)
	end
end

handlers.TurnContinue = function(data)
	if not C.WeaponController:isHeld() then
		C.WeaponController:present(seatOf(data.Owner) or 1, 0.4 * scale())
	end
	refreshCharges(data.Owner)
end

handlers.TurnSkipped = function(data)
	local r = rig(data.Subject)
	C.AnimationController:play(r, "Flinch")
	after(0.3, function()
		C.AnimationController:play(r, "Twitch")
	end)
	C.UIController:banner(if isMe(data.Subject) then "YOUR TURN IS SKIPPED" else nameOf(data.Subject) .. " IS CLAMPED", "THE RESTRAINT RELEASES", "Warn", 1.4 * scale())
	C.AudioController:play("Clamp", { At = chestPos(data.Subject), Pitch = 1.3 })
end

handlers.InstrumentUsed = function(data)
	playInstrument(data)
	refreshGauge()
	refreshMonitors()
end

handlers.EffectChanged = function(data)
	if data.Effect == "Tether" then
		if data.Active then
			after(0.75, function()
				setTether(true)
			end)
		else
			setTether(false)
		end
		return
	end
	local delay = if data.Active then (EFFECT_DELAY_ON[data.Effect] or 0) else 0
	if delay > 0 then
		after(delay, function()
			local s = C.MatchClient:subject(data.Subject)
			-- Only if it is still active by then.
			if s and s.Effects[data.Effect] then
				setEffectVisual(data.Subject, data.Effect, true)
			end
		end)
	else
		setEffectVisual(data.Subject, data.Effect, data.Active == true)
	end
	refreshMonitors()
end

handlers.FireCommit = function(data)
	local actorId, targetId = data.Actor, data.Target
	local reverse = actorId == targetId
	local actorRig = rig(actorId)
	local s = scale()
	local tension = data.Tension or 0.5
	firing = { Actor = actorId, Target = targetId, Reverse = reverse, Tension = tension }
	local aim = if reverse then chinPos(actorId) else headPos(targetId) + Vector3.new(0, -0.2, 0)
	C.WeaponController:grab(actorRig, aim, reverse, s)
	C.AnimationController:setState(actorRig, "Tension", 0.4 + tension * 0.6)
	if not reverse then
		C.AnimationController:setState(rig(targetId), "Tension", 0.3 + tension * 0.5)
		C.AnimationController:lookAt(rig(targetId), C.WeaponController:muzzleCF().Position)
	end
	C.AudioController:play("Aim", { At = chestPos(actorId), Delay = 0.35 * s })
	-- Keep the aim locked on a moving head during the hold.
	local token = bindToken
	task.spawn(function()
		while firing and firing.Actor == actorId and token == bindToken do
			local point = if reverse then chinPos(actorId) else headPos(targetId) + Vector3.new(0, -0.2, 0)
			C.WeaponController:aim(point, reverse)
			task.wait()
		end
	end)
	-- The silence before the outcome.
	after(1.05, function()
		C.AudioController:duck(0.35 + tension * 0.65, 0.35)
		C.EnvironmentController:setIntensity(math.min(1, lastIntensity + 0.15 * tension))
		if isMe(actorId) and reverse then
			C.CameraController:setPullBack(0.55)
		end
		C.AudioController:play("Breath", { At = headPos(actorId) })
	end)
	if isMe(targetId) and not reverse then
		after(0.8, function()
			C.CameraController:focus(C.WeaponController:muzzleCF().Position, 0.65, 1.8)
			C.CameraController:punch(-4)
		end)
	elseif not isMe(actorId) then
		C.CameraController:focus(chestPos(actorId), if C.MatchClient:spectating() then 0.6 else 0.35, 1.8)
	end
	if data.Timeout then
		C.UIController:banner("TIME", "THE ARBITER DECIDES", "Bad", 1.2 * s)
	end
end

handlers.FireResult = function(data)
	local actorId, targetId = data.Actor, data.Target
	local reverse = actorId == targetId
	local actorRig, targetRig = rig(actorId), rig(targetId)
	local weapon = C.WeaponController
	local cam = C.CameraController
	local vfx = C.VFXController
	local s = scale()
	firing = nil
	C.AudioController:unduck(if data.Charged then 1.6 else 0.9)
	C.AnimationController:setState(actorRig, "Tension", 0)
	C.AnimationController:setState(targetRig, "Tension", 0)
	cam:setPullBack(0)
	local chargedColor = Theme.Colors.Charged
	if data.Charged then
		local strength = math.clamp((data.Damage or 1), 1, 4)
		weapon:discharge(true, strength)
		vfx:impact(chestPos(targetId), weapon:muzzleCF().Position, chargedColor, data.Damage or 1)
		C.AnimationController:play(targetRig, "Hit")
		C.AnimationController:play(actorRig, "Recoil")
		C.EnvironmentController:dim(0.45 + 0.12 * strength)
		C.AudioController:play("Zap", { At = chestPos(targetId) })
		if isMe(targetId) then
			cam:shake(0.85)
			cam:kick(0.14, (math.random() - 0.5) * 0.06)
			cam:punch(9)
			vfx:screenFlash(chargedColor, 0.5, 0.6)
			rumble(1, 0.35)
		elseif isMe(actorId) then
			cam:shake(0.4)
			cam:kick(0.07)
			cam:punch(4)
			rumble(0.6, 0.2)
		else
			cam:shake(0.25)
			cam:punch(2)
		end
		local label = if data.Surge then "SURGE" else "CHARGED"
		C.UIController:banner(label, string.format("%s  −%d INTEGRITY", nameOf(targetId), data.Damage or 1), "Bad", 1.0 * s)
	else
		weapon:discharge(false)
		cam:kick(0.02)
		if reverse then
			after(0.35, function()
				C.AnimationController:play(actorRig, "Relief")
				C.AudioController:play("Relief", { At = headPos(actorId) })
			end)
		else
			after(0.3, function()
				C.AnimationController:play(targetRig, "Relief")
			end)
		end
		C.UIController:banner("HOLLOW", if data.Kept then "THE TURN CONTINUES" else "", "Text", 0.8 * s)
	end
	after(if data.Charged then 0.5 else 0.35, function()
		weapon:cycle(data.Charged, s)
	end)
	after(if data.Charged then 0.85 else 0.6, function()
		weapon:release(nil, 0.35 * s)
	end)
	refreshGauge()
	refreshCharges(actorId)
	-- Surrogates react to what just happened to someone else.
	local sc = scene()
	if sc then
		for id, info in sc.Subjects do
			if info.IsAI and id ~= actorId and id ~= targetId then
				C.AnimationController:play(rig(id), if data.Charged then "Flinch" else "Glance")
			end
		end
	end
end

handlers.Damage = function(data)
	local id = data.Subject
	if view then
		view:flashMonitor(id, Theme.Colors.Bad)
	end
	if data.Source ~= "Shot" then
		local r = rig(id)
		C.AnimationController:play(r, "Hit")
		C.VFXController:sparks(chestPos(id), Vector3.new(0, 1, 0), Theme.Colors.Charged, 12)
		if data.Mirrored then
			C.VFXController:arc(C.WeaponController:chamberCF().Position, chestPos(id), Color3.fromRGB(190, 140, 255), 0.35)
		end
		if isMe(id) then
			C.CameraController:shake(0.45)
			C.VFXController:screenFlash(Theme.Colors.Charged, 0.3, 0.4)
			rumble(0.6, 0.2)
		end
	end
	if (data.Absorbed or 0) > 0 then
		C.UIController:toast("DAMPENED", nameOf(id) .. " absorbed " .. data.Absorbed .. ".", "Info")
	end
	refreshMonitors()
	refreshIntensity()
end

handlers.Heal = function(data)
	if view then
		view:flashMonitor(data.Subject, Theme.Colors.Hollow)
	end
	if (data.Amount or 0) > 0 then
		C.VFXController:motes(chestPos(data.Subject), Theme.Colors.Good, 10)
		if isMe(data.Subject) then
			C.VFXController:screenFlash(Theme.Colors.Good, 0.12, 0.5)
		end
	end
	refreshMonitors()
	refreshIntensity()
end

handlers.Eliminated = function(data)
	local id = data.Subject
	local r = rig(id)
	C.AnimationController:setState(r, "Slumped", 1)
	C.AnimationController:setState(r, "Tension", 0)
	C.AudioController:play("Slump", { At = chestPos(id) })
	C.AudioController:play("PowerDown", { At = chestPos(id), Delay = 0.2 })
	C.EnvironmentController:dim(0.35)
	if isMe(id) then
		C.CameraController:setSlump(true)
		C.UIController:banner("INTEGRITY LOST", "", "Bad", 1.2 * scale())
	end
	-- A surrogate's lights go out.
	local info = C.MatchClient:info(id)
	local model = bound[id]
	if info and info.IsAI and model then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Material == Enum.Material.Neon then
				d:SetAttribute("LitColor", d.Color)
				d.Color = d.Color:Lerp(Color3.new(0, 0, 0), 0.8)
			end
		end
	end
	refreshMonitors()
	refreshIntensity()
end

handlers.Echo = function(data)
	if isMe(data.Subject) then
		C.AudioController:play("Lens")
	end
end

handlers.LoadEnd = function()
	C.WeaponController:setLoaded(false)
	C.WeaponController:rest(0.6 * scale())
	after(0.3, function()
		C.WeaponController:clearSpent()
	end)
	setTether(false)
	for id, h in handles.Bubbles do
		h.stop()
		handles.Bubbles[id] = nil
	end
	refreshGauge()
end

local function relight(id: number)
	local model = bound[id]
	if model then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("LitColor") then
				d.Color = d:GetAttribute("LitColor")
				d:SetAttribute("LitColor", nil)
			end
		end
	end
end

handlers.TrialEnd = function(data)
	local st, sc = state(), scene()
	if st == nil or sc == nil then
		return
	end
	local myTeam = st.Subjects[you() or -1] and st.Subjects[you() :: number].TeamId
	local won = data.WinnerTeam ~= nil and data.WinnerTeam == myTeam
	local winners = {}
	for id, s in st.Subjects do
		if data.WinnerTeam ~= nil and s.TeamId == data.WinnerTeam then
			table.insert(winners, nameOf(id))
			C.AnimationController:play(rig(id), "Relief")
		end
	end
	local title
	if sc.Spectating or you() == nil then
		title = if #winners > 0 then table.concat(winners, " & ") .. " PREVAILS" else "NO SURVIVOR"
	else
		title = if won then "YOU PREVAIL" else "TRIAL LOST"
	end
	local score = {}
	for id, wins in data.Wins or {} do
		table.insert(score, string.format("%s %d", nameOf(id), wins))
	end
	C.UIController:banner(title, "TRIAL " .. Format.roman(data.Trial) .. "  ·  " .. table.concat(score, "  ·  "), if won then "Good" else "Bad", 2.6 * scale())
	C.AudioController:play(if won or sc.Spectating then "WinSting" else "LoseSting")
	if arena then
		local cams = arena:FindFirstChild("Cameras")
		local gallery = cams and cams:FindFirstChild("Gallery") :: BasePart?
		if gallery then
			C.CameraController:shots({ { From = gallery.CFrame, To = gallery.CFrame * CFrame.new(0, -0.6, -3), Duration = 2.6 * scale(), Fov = 42 } })
		end
	end
	after(3.6, function()
		C.CameraController:setSlump(false)
		for id in st.Subjects do
			relight(id)
		end
	end)
	refreshIntensity()
end

handlers.SuddenDeath = function(data)
	for _, id in data.Subjects or {} do
		C.AnimationController:setState(rig(id), "Slumped", 0)
		relight(id)
		if view then
			view:sync(id, {})
		end
	end
	C.CameraController:setSlump(false)
	clearHandles()
	C.UIController:banner("SUDDEN DEATH", "ONE INTEGRITY EACH  ·  NO INSTRUMENTS", "Bad", 2.4 * scale())
	C.AudioController:play("Alarm")
	C.AudioController:play("Alarm", { Delay = 0.5 })
	C.EnvironmentController:dim(0.6)
	announce("SuddenDeath")
	refreshMonitors()
	refreshIntensity()
end

handlers.MatchEnd = function(data)
	local sc = scene()
	if sc == nil then
		return
	end
	C.AudioController:setHeartbeat(0)
	local winners = {}
	for _, id in data.Winners or {} do
		winners[id] = true
	end
	for id, info in sc.Subjects do
		local r = rig(id)
		C.AnimationController:setState(r, "Tension", 0)
		if winners[id] then
			C.AnimationController:setState(r, "Slumped", 0)
			local pose = info.Look and info.Look.Victory and info.Look.Victory.Data and info.Look.Victory.Data.Pose or "Nod"
			C.AnimationController:victory(r, pose)
			if pose == "Raise" then
				C.WeaponController:hoist(r)
			end
		else
			local s = C.MatchClient:subject(id)
			if s and not s.Eliminated then
				C.AnimationController:play(r, "Defeat")
			end
		end
	end
	local first = (data.Winners or {})[1]
	if first then
		local head = headPos(first)
		local toward = (origin * CFrame.new(0, TableLayout.TableTop + 1.8, 0)).Position
		local from = CFrame.lookAt(toward + (toward - head).Unit * 0.5 + Vector3.new(0, 0.6, 0), head)
		C.CameraController:shots({
			{ From = from, To = CFrame.lookAt(head:Lerp(toward, 0.55), head), Duration = 2.6, Fov = 40, Essential = true },
		}, true)
	end
end

handlers.Forfeit = function(data)
	local id = data.Subject
	C.AnimationController:setState(rig(id), "Slumped", 1)
	local reason = if data.Reason == "AFK" then "REMOVED FOR INACTIVITY" elseif data.Reason == "Disconnected" then "CONNECTION LOST" else "LEFT THE EVALUATION"
	C.UIController:banner(nameOf(id) .. " FORFEITS", reason, "Warn", 1.3 * scale())
	refreshMonitors()
end

handlers.Timeout = function(data)
	announce("Timeout")
	if isMe(data.Subject) then
		C.UIController:toast("HESITATION LIMIT", "The Arbiter fired for you. Two timeouts in a row forfeit a live Trial.", "Warn")
	end
end

---------------------------------------------------------------------------
-- Chatter
---------------------------------------------------------------------------

local function onDialogue(data)
	local mode = C.SettingsController:get("Dialogue") or "Full"
	if mode == "Off" then
		return
	end
	if mode == "Brief" and #(data.Text or "") > 48 then
		return
	end
	local info = C.MatchClient:info(data.Speaker)
	local name = info and string.upper(info.Name or "") or "?"
	local surrogate = Surrogates.get(data.Personality)
	C.UIController:subtitle(name, data.Text, (data.Duration or 3) + 0.6, "Accent")
	local voice = surrogate and surrogate.Voice
	C.AudioController:voice(voice and voice.Tone, voice and voice.Pitch, voice and voice.Rate, data.Duration or 2)
	local r = rig(data.Speaker)
	C.AnimationController:play(r, "Talk", 2 / math.max(data.Duration or 2, 0.5))
end

local function onPresence(data)
	local name = nameOf(data.Subject)
	if data.Left then
		C.UIController:toast(name .. " LEFT", "Their seat is empty.", "Warn")
	elseif data.Connected then
		C.UIController:toast(name .. " RECONNECTED", nil, "Good")
	else
		C.UIController:toast(name .. " DISCONNECTED", string.format("Holding their seat for %d seconds.", data.Grace or 45), "Warn")
	end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

function MatchPresenter:Start()
	local client = C.MatchClient
	client.Began:Connect(function(sc)
		self:onBegan(sc)
	end)
	client.Event:Connect(function(kind, data)
		local handler = handlers[kind]
		if handler and arena then
			local ok, err = pcall(handler, data)
			if not ok then
				warn("[VARIANCE/Presenter] " .. kind .. ": " .. tostring(err))
			end
		end
	end)
	client.Resynced:Connect(function()
		clearHandles()
		restoreScene()
	end)
	client.Dialogue:Connect(onDialogue)
	client.Presence:Connect(onPresence)
	client.Emote:Connect(function(data)
		C.AnimationController:emote(rig(data.Subject), data.Anim)
	end)
	client.PostMatch:Connect(function(data)
		if arena then
			C.CameraController:toOrbit(origin)
		end
		C.UIController:open("PostMatch", data)
	end)
	client.Ended:Connect(function()
		self:teardown()
		C.CameraController:toLobby()
		C.EnvironmentController:enterLobby()
		C.AudioController:setMusic("Lobby", 0)
		C.AudioController:setHeartbeat(0)
		C.AudioController:unduck(0.5)
		C.UIController:close("PostMatch")
	end)
	C.NetworkClient:onLook(function(payload)
		if type(payload) == "table" and not isMe(payload.Subject) then
			C.AnimationController:setLook(rig(payload.Subject), payload.Yaw or 0, payload.Pitch or 0)
		end
	end)
end

return MatchPresenter

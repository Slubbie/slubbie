-- The Arbiter at the current table, and every cell you can see.
--
-- The server builds the device once per room and never moves it; each client
-- animates its own copy from the same public events (anchored parts moved
-- locally never replicate), so everyone sees the same beats.
--
-- Movement modes:
--   free   eased slides between table positions (rest, centre, presented to
--          a seat), with an optional hop.
--   held   attached to a rig's right hand (AnimationController solves the hand
--          analytically). Picking up blends from where the hand first touched
--          the body into a proper grip; aiming turns the barrel toward the
--          target (reversed, held by the barrel, when the subject aims at
--          themselves).
--
-- Cells are built client-side only (server never creates them): the rack shows
-- the announced mix, a shutter blanks them, they are loaded through the port,
-- and each spent or ejected cell lands in the spent tray showing its type.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArbiterModel = require(ReplicatedStorage.Variance.Visual.ArbiterModel)
local CellModel = require(ReplicatedStorage.Variance.Visual.CellModel)
local TableLayout = require(ReplicatedStorage.Variance.Visual.TableLayout)
local Theme = require(script.Parent.Parent.UI.Theme)

local WeaponController = {}

-- Device-local frames (grip origin, muzzle toward -Z).
local GRIP = CFrame.new(0, -0.62, 0.66)
local BARREL_GRIP = CFrame.new(0, 0.2, -1.55)
local MUZZLE = CFrame.new(0, 0.2, -2.55)
local PORT = CFrame.new(0, 0.6, 0.36)
local EJECT = CFrame.new(0.42, 0.28, 0.36)
local CHAMBER = CFrame.new(0, 0.2, 0.36)
local WINDOW = CFrame.new(0.3, 0.2, 0.36)
local BODY_TOP = CFrame.new(-0.3, 0.1, -0.2) -- where a hand first grabs the resting device

local BOLT_TRAVEL = 0.3

local model: Model? = nil
local origin = CFrame.identity
local current = CFrame.identity
local skinColors: { [string]: Color3 } = {}
local parts: { [string]: { BasePart } } = {}
local windowPart: BasePart? = nil
local glowLight: PointLight? = nil

local free = { From = CFrame.identity, To = CFrame.identity, Start = 0, Duration = 0, Hop = 0 }
local held: { [string]: any }? = nil
local kick: { Start: number, Strength: number }? = nil
local bolt: { Start: number, Duration: number }? = nil
local spin: { Start: number, Duration: number, Turns: number }? = nil
local shake: { Until: number, Amp: number }? = nil
local charges = { Capacitor = false, Overclock = false }
local gauge, gaugeTarget = 0.5, 0.5
local glow, glowTarget = 0, 0
local flashUntil = 0
local hoisted: any = nil

local rackCells: { Model } = {}
local spentCells: { Model } = {}
local flying: { { [string]: any } } = {}
local windowCell: Model? = nil
local cellFolder: Folder? = nil

function WeaponController:Init(controllers)
	self.Controllers = controllers
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function palette()
	return { Charged = Theme.Colors.Charged, Hollow = Theme.Colors.Hollow }
end

local function audio()
	return WeaponController.Controllers.AudioController
end

local function vfx()
	return WeaponController.Controllers.VFXController
end

---------------------------------------------------------------------------
-- Binding
---------------------------------------------------------------------------

function WeaponController:attach(arena: Model)
	self:detach()
	local device = arena:FindFirstChild("Arbiter")
	if device == nil or not device:IsA("Model") then
		return
	end
	model = device
	origin = arena:GetAttribute("Origin") or CFrame.identity
	parts = { Coil = {}, Strip = {} }
	for _, d in device:GetChildren() do
		if d:IsA("BasePart") then
			if d.Name:match("^Coil") then
				table.insert(parts.Coil, d)
			elseif d.Name == "Strip" then
				table.insert(parts.Strip, d)
			elseif d.Name == "Window" then
				windowPart = d
			end
		end
	end
	local body = device:FindFirstChild("Body")
	glowLight = body and body:FindFirstChild("ChamberGlow") :: PointLight? or nil
	current = self:restCF()
	free = { From = current, To = current, Start = 0, Duration = 0, Hop = 0 }
	held, kick, bolt, spin, shake, hoisted = nil, nil, nil, nil, nil, nil
	charges.Capacitor, charges.Overclock = false, false
	cellFolder = Instance.new("Folder")
	cellFolder.Name = "VarianceCells"
	cellFolder.Parent = workspace
	self:setSkin(nil)
end

function WeaponController:detach()
	if model and model.Parent then
		ArbiterModel.place(model, self:restCF(), 0, 0)
	end
	model = nil
	held = nil
	hoisted = nil
	self:clearRack()
	self:clearSpent()
	if windowCell then
		windowCell:Destroy()
		windowCell = nil
	end
	if cellFolder then
		cellFolder:Destroy()
		cellFolder = nil
	end
	table.clear(flying)
end

function WeaponController:attached(): boolean
	return model ~= nil and model.Parent ~= nil
end

-- Repaints with a DeviceSkin cosmetic (nil = factory finish).
function WeaponController:setSkin(data: { [string]: any }?)
	if model == nil then
		return
	end
	ArbiterModel.applySkin(model, data)
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and d:GetAttribute("Paint") then
			skinColors[d:GetAttribute("Paint")] = d.Color
		end
	end
end

---------------------------------------------------------------------------
-- Positions
---------------------------------------------------------------------------

function WeaponController:restCF(): CFrame
	return origin * TableLayout.deviceRest()
end

-- Lying on its side at the near edge of a seat's tray, grip toward the subject.
function WeaponController:presentCF(seat: number): CFrame
	return origin
		* TableLayout.seatCFrame(seat)
		* CFrame.new(0.35, TableLayout.TableTop + 0.42, -1.2)
		* CFrame.Angles(0, math.pi / 2, 0)
		* CFrame.Angles(0, 0, -math.pi / 2)
end

function WeaponController:centreCF(): CFrame
	return origin
		* CFrame.new(0, TableLayout.TableTop + 0.42, 0)
		* CFrame.Angles(0, math.pi / 2, 0)
		* CFrame.Angles(0, 0, -math.pi / 2)
end

function WeaponController:current(): CFrame
	return current
end

function WeaponController:muzzleCF(): CFrame
	return current * MUZZLE
end

function WeaponController:chamberCF(): CFrame
	return current * CHAMBER
end

function WeaponController:portCF(): CFrame
	return current * PORT
end

function WeaponController:isHeld(): boolean
	return held ~= nil
end

---------------------------------------------------------------------------
-- Free movement
---------------------------------------------------------------------------

function WeaponController:slideTo(target: CFrame, duration: number?, hop: number?)
	held = nil
	hoisted = nil
	free =
		{ From = current, To = target, Start = os.clock(), Duration = math.max(duration or 0.5, 0.01), Hop = hop or 0 }
	if (target.Position - current.Position).Magnitude > 0.2 then
		audio():play("Aim", { At = current.Position, Pitch = 0.8 })
	end
end

function WeaponController:present(seat: number, duration: number?)
	self:slideTo(self:presentCF(seat), duration or 0.55, 0.25)
end

function WeaponController:centre(duration: number?)
	self:slideTo(self:centreCF(), duration or 0.5, 0.2)
end

function WeaponController:rest(duration: number?)
	self:slideTo(self:restCF(), duration or 0.6, 0.2)
end

local function freeCF(now: number): CFrame
	local t = if free.Duration > 0 then (now - free.Start) / free.Duration else 1
	local a = smooth(t)
	local cf = free.From:Lerp(free.To, a)
	if free.Hop > 0 and t < 1 then
		cf = cf + Vector3.new(0, math.sin(a * math.pi) * free.Hop, 0)
	end
	return cf
end

---------------------------------------------------------------------------
-- Holding
---------------------------------------------------------------------------

-- Starts a pick-up: the rig reaches for the device, grabs it and brings it up
-- aimed at `aim`. Times scale with the match's timing.
function WeaponController:grab(rig, aim: Vector3, reverse: boolean, scale: number?)
	if model == nil or rig == nil then
		return
	end
	local s = scale or 1
	hoisted = nil
	held = {
		Rig = rig,
		Aim = aim,
		Reverse = reverse,
		Phase = "Reach",
		Start = os.clock(),
		ReachTime = 0.38 * s,
		LiftTime = 0.42 * s,
		ContactOffset = nil,
	}
	local anim = self.Controllers.AnimationController
	anim:setIntent(rig, { Kind = "Reach", Point = (current * BODY_TOP).Position })
end

function WeaponController:aim(point: Vector3, reverse: boolean?)
	if held then
		held.Aim = point
		if reverse ~= nil then
			held.Reverse = reverse
		end
	end
end

-- Puts the held device down at `target` (defaults to the holder's seat).
function WeaponController:release(target: CFrame?, duration: number?)
	local h = held
	if h == nil then
		return
	end
	held = nil
	local anim = self.Controllers.AnimationController
	anim:setIntent(h.Rig, nil)
	local to = target or (h.Rig.Seat and self:presentCF(h.Rig.Seat)) or self:restCF()
	free = { From = current, To = to, Start = os.clock(), Duration = duration or 0.45, Hop = 0.3 }
	task.delay(duration or 0.45, function()
		if model and not held then
			audio():play("SetDown", { At = to.Position })
		end
	end)
end

-- Victory "Raise": both hands lift the device overhead.
function WeaponController:hoist(rig)
	if model == nil or rig == nil then
		return
	end
	held = nil
	hoisted = { Rig = rig, Start = os.clock(), From = current }
end

-- World CFrame of the device when held in `hand`, aimed at `aim`.
local function holdCF(hand: CFrame, aim: Vector3, reverse: boolean): CFrame
	local p = hand.Position
	if reverse then
		local dir = aim - p
		if dir.Magnitude < 1e-3 then
			dir = -hand.UpVector
		end
		local rot = CFrame.lookAt(Vector3.zero, dir.Unit, Vector3.yAxis)
		return CFrame.new(p) * rot * BARREL_GRIP:Inverse()
	end
	-- The barrel runs ~0.8 above the grip: aim that line at the target.
	local dir = (aim - Vector3.new(0, 0.8, 0)) - p
	if dir.Magnitude < 1e-3 then
		dir = hand.LookVector
	end
	local rot = CFrame.lookAt(Vector3.zero, dir.Unit, Vector3.yAxis)
	return CFrame.new(p) * rot * GRIP:Inverse()
end

---------------------------------------------------------------------------
-- Action
---------------------------------------------------------------------------

-- The shot. charged: discharge with recoil; hollow: a dry click and a puff.
-- `style` carries the shooter's cosmetics: discharge colours (CellFX data:
-- Arc, Spark, Glow, Rainbow) and sound pack (Pitch, Variant).
function WeaponController:discharge(charged: boolean, strength: number?, style: { [string]: any }?)
	if model == nil then
		return
	end
	local st = style or {}
	local muzzle = self:muzzleCF()
	local glowColor = st.Glow or skinColors.Glow or Color3.fromRGB(255, 190, 110)
	if st.Rainbow then
		glowColor = Color3.fromHSV((os.clock() * 0.7) % 1, 0.55, 1)
	end
	local pitch = st.Pitch or 1
	local variant = st.Variant or "Standard"
	local volume = if variant == "Muted" then 0.55 else 1
	if charged then
		local s = strength or 1
		kick = { Start = os.clock(), Strength = s }
		flashUntil = os.clock() + 0.12
		vfx():muzzle(muzzle, glowColor, s, st.Spark)
		audio():play("Discharge", { At = muzzle.Position, Pitch = pitch / (0.9 + 0.1 * s), Volume = volume })
		if variant == "Retro" then
			audio():play("Zap", { At = muzzle.Position, Pitch = 1.8, Volume = 0.6 })
		elseif variant == "Heavy" then
			audio():play("DistantThud", { At = muzzle.Position, Pitch = 0.6 })
		end
		audio():play("Crack", { At = muzzle.Position, Delay = 0.02, Pitch = pitch, Volume = volume })
		if s > 1 then
			audio():play("Surge", { At = muzzle.Position })
		end
	else
		kick = { Start = os.clock(), Strength = 0.12 }
		audio():play("HollowClick", { At = muzzle.Position, Pitch = pitch, Volume = volume })
		audio():play("HollowHiss", { At = muzzle.Position, Delay = 0.1, Volume = volume })
		vfx():puff(muzzle, Color3.fromRGB(200, 214, 210))
	end
	glowTarget = 0
end

-- Cycles the bolt; the spent cell leaves the ejection port and lands in the
-- spent tray showing its type.
function WeaponController:cycle(charged: boolean?, scale: number?)
	if model == nil then
		return
	end
	local s = scale or 1
	bolt = { Start = os.clock(), Duration = 0.5 * s }
	audio():play("BoltBack", { At = current.Position })
	audio():play("BoltForward", { At = current.Position, Delay = 0.28 * s })
	if charged ~= nil then
		task.delay(0.14 * s, function()
			self:ejectCell(charged, true)
		end)
	end
end

-- Throws a cell out of the ejection port into the spent tray.
function WeaponController:ejectCell(charged: boolean, spent: boolean?)
	if model == nil or cellFolder == nil then
		return
	end
	local cell = CellModel.build(charged, palette(), true)
	cell.Parent = cellFolder
	local from = current * EJECT
	local index = #spentCells + 1
	local col = (index - 1) % 5
	local row = math.floor((index - 1) / 5)
	local land = origin
		* TableLayout.spentCFrame()
		* CFrame.new(-0.5 + col * 0.25, 0.12, -0.3 + row * 0.3)
		* CFrame.Angles(0, 0, math.pi / 2)
	table.insert(flying, {
		Model = cell,
		From = from,
		To = land,
		Start = os.clock(),
		Duration = 0.55,
		Height = 1.3,
		Spin = 9 + math.random() * 4,
		OnLand = function()
			audio():play("Tink", { At = land.Position })
			if not spent then
				vfx():flash(land.Position, charged and Theme.Colors.Charged or Theme.Colors.Hollow, 0.8, 0.3, 2)
			end
		end,
	})
	table.insert(spentCells, cell)
	audio():play("Eject", { At = from.Position })
end

-- Ejector: the loaded cell is thrown out unfired, revealed to everyone.
function WeaponController:ejectLoaded(charged: boolean)
	self:cycle(nil, 1)
	task.delay(0.16, function()
		self:ejectCell(charged, false)
	end)
end

-- Rotor: the chamber turns.
function WeaponController:turnChamber(turns: number?)
	spin = { Start = os.clock(), Duration = 0.9, Turns = turns or 1 }
	audio():play("Rotor", { At = current.Position })
end

-- Scrambler: the whole device rattles.
function WeaponController:rattle(duration: number, amplitude: number?)
	shake = { Until = os.clock() + duration, Amp = amplitude or 0.08 }
end

-- Capacitor / Overclock visual state.
function WeaponController:setCharge(kind: string, on: boolean)
	charges[kind] = on
end

-- Public odds shown on the device's own gauge (0 = certainly HOLLOW, 1 = CHARGED).
function WeaponController:setGauge(p: number?)
	gaugeTarget = if p then math.clamp(p, 0, 1) else 0.5
end

-- Chamber glow: on while cells are loaded.
function WeaponController:setLoaded(loaded: boolean)
	glowTarget = if loaded then 1 else 0
end

-- Lens: the loaded cell glows in the window. `charged` is nil for viewers who
-- don't learn it (they see a neutral glow).
function WeaponController:showWindow(charged: boolean?, duration: number?)
	if model == nil then
		return
	end
	if windowCell then
		windowCell:Destroy()
		windowCell = nil
	end
	local cell = if charged == nil then CellModel.blank() else CellModel.build(charged, palette(), true)
	for _, d in cell:GetDescendants() do
		if d:IsA("BasePart") then
			d.Size *= 0.7
		end
	end
	cell.Parent = cellFolder
	windowCell = cell
	local light = Instance.new("PointLight")
	light.Range = 4
	light.Brightness = 2.5
	light.Color = if charged == nil
		then Color3.fromRGB(230, 230, 220)
		elseif charged then Theme.Colors.Charged
		else Theme.Colors.Hollow
	light.Parent = cell.PrimaryPart
	if windowPart then
		windowPart.Transparency = 0.55
	end
	task.delay(duration or 1.4, function()
		if windowCell == cell then
			windowCell = nil
			cell:Destroy()
			if windowPart then
				windowPart.Transparency = 0.15
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Cells on the rack
---------------------------------------------------------------------------

-- Shows the announced cells on the rack. `kinds` is a list of "C" / "H" / "?"
-- (sorted by the caller: announcing the mix never reveals the order).
function WeaponController:showRack(kinds: { string }, interval: number?)
	self:clearRack()
	if cellFolder == nil then
		return
	end
	local n = #kinds
	for i, kind in kinds do
		local cell = if kind == "?" then CellModel.blank() else CellModel.build(kind == "C", palette(), true)
		cell.Parent = cellFolder
		local at = origin * TableLayout.rackSlot(i, n)
		CellModel.place(cell, at + Vector3.new(0, 1.2, 0))
		rackCells[i] = cell
		local delay = (i - 1) * (interval or 0.08)
		table.insert(flying, {
			Model = cell,
			From = at + Vector3.new(0, 1.2, 0),
			To = at,
			Start = os.clock() + delay,
			Duration = 0.22,
			Height = 0,
			Spin = 0,
			OnLand = function()
				audio():play("CellShow", { At = at.Position })
			end,
		})
	end
end

-- The shutter: every rack cell becomes an anonymous casing.
function WeaponController:blankRack()
	if cellFolder == nil then
		return
	end
	for i, cell in rackCells do
		local primary = cell.PrimaryPart
		local cf = primary and primary.CFrame or cell:GetPivot()
		cell:Destroy()
		local blank = CellModel.blank()
		blank.Parent = cellFolder
		CellModel.place(blank, cf)
		rackCells[i] = blank
	end
	audio():play("BoltBack", { At = (origin * TableLayout.rackCFrame()).Position, Pitch = 1.4 })
end

-- Loads the rack cells into the device's port, one after another.
function WeaponController:loadRack(duration: number)
	local n = #rackCells
	if n == 0 then
		return
	end
	local each = duration / n
	for i, cell in rackCells do
		local primary = cell.PrimaryPart
		local from = primary and primary.CFrame or cell:GetPivot()
		table.insert(flying, {
			Model = cell,
			From = from,
			Target = function()
				return current * PORT * CFrame.Angles(math.pi / 2, 0, 0)
			end,
			Start = os.clock() + (i - 1) * each,
			Duration = math.max(each * 0.9, 0.12),
			Height = 0.9,
			Spin = 0,
			OnLand = function()
				audio():play("CellInsert", { At = current.Position, Pitch = 0.95 + i * 0.02 })
				cell:Destroy()
			end,
		})
	end
	table.clear(rackCells)
end

function WeaponController:clearRack()
	for _, cell in rackCells do
		cell:Destroy()
	end
	table.clear(rackCells)
end

function WeaponController:clearSpent()
	local v = vfx()
	for _, cell in spentCells do
		if cell.Parent then
			if v then
				v:dissolve(cell, 0.4)
			else
				cell:Destroy()
			end
		end
	end
	table.clear(spentCells)
end

---------------------------------------------------------------------------
-- Per frame (driven by AnimationController, around rig posing)
---------------------------------------------------------------------------

-- Before rigs are posed: decide what the holder's arms should do.
function WeaponController:preStep(_dt: number)
	if model == nil then
		return
	end
	local now = os.clock()
	local anim = self.Controllers.AnimationController
	local h = held
	if h then
		local rig = h.Rig
		if rig.Root.Parent == nil then
			held = nil
			return
		end
		local t = now - h.Start
		if h.Phase == "Reach" and t >= h.ReachTime and rig.HandR then
			h.Phase = "Lift"
			h.LiftStart = now
			h.ContactOffset = rig.HandR:Inverse() * current
			audio():play("Pickup", { At = current.Position })
		end
		if h.Phase == "Reach" then
			anim:setIntent(rig, { Kind = "Reach", Point = (current * BODY_TOP).Position })
		else
			local lift = smooth((now - (h.LiftStart or now)) / h.LiftTime)
			local support = nil
			local brace = nil
			if h.Reverse then
				if rig.Origin and rig.Seat then
					-- The free hand grips the left armrest.
					local base = rig.Origin * TableLayout.chairCFrame(rig.Seat)
					brace = (base * CFrame.new(-1.25, TableLayout.SeatHeight + 1.05, -0.1)).Position
				end
			else
				support = (current * CHAMBER).Position
			end
			anim:setIntent(
				rig,
				{ Kind = "Hold", Aim = h.Aim, Reverse = h.Reverse, Lift = lift, Support = support, Brace = brace }
			)
		end
	elseif hoisted then
		anim:setIntent(hoisted.Rig, nil)
	end
end

-- After rigs are posed: attach the device to the hand and place everything.
function WeaponController:postStep(dt: number)
	if model == nil or model.Parent == nil then
		return
	end
	local now = os.clock()
	local h = held
	local cf
	if h and h.Rig.HandR and h.Phase ~= "Reach" and h.ContactOffset then
		local hand = h.Rig.HandR
		local target = holdCF(hand, h.Aim, h.Reverse)
		local blend = smooth((now - (h.LiftStart or now)) / h.LiftTime)
		cf = (hand * h.ContactOffset):Lerp(target, blend)
	elseif hoisted and hoisted.Rig.HandR and hoisted.Rig.HandL then
		local rig = hoisted.Rig
		local mid = (rig.HandR.Position + rig.HandL.Position) / 2
		local across = (rig.HandR.Position - rig.HandL.Position)
		local target =
			CFrame.lookAt(mid + Vector3.new(0, 0.35, 0), mid + Vector3.new(0, 0.35, 0) - across, Vector3.yAxis)
		local a = smooth((now - hoisted.Start) / 0.7)
		cf = hoisted.From:Lerp(target, a)
	else
		cf = freeCF(now)
	end

	-- Recoil: kicks back along the barrel and muzzle-up, then settles.
	if kick then
		local t = now - kick.Start
		if t > 0.8 then
			kick = nil
		else
			local k = math.exp(-11 * t) * math.min(1, t * 60) * kick.Strength
			cf = cf * CFrame.new(0, 0.05 * k, 0.45 * k) * CFrame.Angles(0.4 * k, 0, 0)
		end
	end
	if shake then
		if now > shake.Until then
			shake = nil
		else
			local a = shake.Amp
			cf = cf
				* CFrame.new(math.sin(now * 53) * a, math.sin(now * 61) * a, math.sin(now * 47) * a)
				* CFrame.Angles(math.sin(now * 39) * a, 0, math.sin(now * 43) * a)
		end
	end
	current = cf

	local boltOffset = 0
	if bolt then
		local t = (now - bolt.Start) / bolt.Duration
		if t >= 1 then
			bolt = nil
		else
			-- Snap back fast, return a little slower.
			boltOffset = BOLT_TRAVEL * (if t < 0.35 then smooth(t / 0.35) else 1 - smooth((t - 0.35) / 0.65))
		end
	end
	gauge += (gaugeTarget - gauge) * (1 - math.exp(-4 * dt))
	local needle = (gauge - 0.5) * 2.2 + math.sin(now * 20) * 0.02 * gauge
	ArbiterModel.place(model, cf, boltOffset, needle)

	-- Chamber spin (Rotor).
	if spin then
		local t = (now - spin.Start) / spin.Duration
		if t >= 1 then
			spin = nil
		else
			local chamber = model:FindFirstChild("Chamber") :: BasePart?
			if chamber then
				chamber.CFrame *= CFrame.Angles(0, 0, smooth(t) * math.pi * 2 * spin.Turns)
			end
		end
	end

	-- Glow and coils.
	glow += (glowTarget - glow) * (1 - math.exp(-3 * dt))
	if glowLight then
		local flash = if now < flashUntil then 8 else 0
		glowLight.Brightness = glow * (0.8 + 0.2 * math.sin(now * 3)) + flash
	end
	local coilBase = skinColors.Glow or Color3.fromRGB(255, 190, 110)
	local coilColor = coilBase
	if charges.Capacitor then
		local pulse = 0.5 + 0.5 * math.sin(now * 9)
		coilColor = coilBase:Lerp(Color3.new(1, 1, 1), 0.35 + 0.35 * pulse)
	end
	for _, coil in parts.Coil do
		coil.Color = coilColor
	end
	local stripBase = skinColors.Accent or Color3.fromRGB(225, 160, 60)
	local stripColor = stripBase
	if charges.Overclock then
		local pulse = 0.5 + 0.5 * math.sin(now * 16)
		stripColor = stripBase:Lerp(Color3.fromRGB(255, 50, 40), 0.6 + 0.4 * pulse)
	end
	for _, strip in parts.Strip do
		strip.Color = stripColor
	end

	-- Lens window cell follows the chamber.
	if windowCell then
		CellModel.place(windowCell, cf * WINDOW * CFrame.Angles(math.pi / 2, 0, 0))
	end

	-- Cells in flight.
	for i = #flying, 1, -1 do
		local f = flying[i]
		local t = (now - f.Start) / f.Duration
		if f.Model.Parent == nil then
			table.remove(flying, i)
		elseif t >= 0 then
			local to = if f.Target then f.Target() else f.To
			if t >= 1 then
				CellModel.place(f.Model, to)
				table.remove(flying, i)
				if f.OnLand then
					f.OnLand()
				end
			else
				local a = smooth(t)
				local pos = f.From.Position:Lerp(to.Position, a)
					+ Vector3.new(0, math.sin(t * math.pi) * (f.Height or 0), 0)
				local rot = f.From.Rotation:Lerp(to.Rotation, a) * CFrame.Angles(f.Spin * t, 0, 0)
				CellModel.place(f.Model, CFrame.new(pos) * rot)
			end
		end
	end
end

return WeaponController

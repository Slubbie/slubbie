-- The things on the table that belong to each subject: instrument props in
-- their tray and the integrity monitor beside it.
--
-- Props are client-side models (InstrumentProps) laid out by TableLayout's slot
-- grid; the list mirrors the subject's inventory exactly, so after any change
-- the remaining props slide into their new slots. The monitors are server
-- parts with two SurfaceGuis ("Owner" faces the subject, "Public" faces the
-- table); this module fills them with the same public read-out a spectator
-- would see: name, Integrity as shaped pips, Trial wins and active effects.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local InstrumentProps = require(ReplicatedStorage.Variance.Visual.InstrumentProps)
local TableLayout = require(ReplicatedStorage.Variance.Visual.TableLayout)
local Instruments = require(ReplicatedStorage.Variance.Core.Instruments)
local Theme = require(script.Parent.Parent.UI.Theme)

local TableView = {}
TableView.__index = TableView

local EFFECT_TAGS = {
	Dampener = "DAMPENED",
	Clamped = "CLAMPED",
	Capacitor = "CAPACITOR",
	Overclock = "OVERCLOCK",
}

export type View = typeof(setmetatable(
	{} :: {
		Arena: Model,
		Origin: CFrame,
		Seats: { [number]: number },
		Capacity: number,
		Props: { [number]: { Model } },
		Monitors: { [number]: { [string]: any } },
		Folder: Folder,
		Moving: { { [string]: any } },
		Highlight: Highlight?,
		Controllers: any,
	},
	TableView
))

function TableView.new(arena: Model, origin: CFrame, seats: { [number]: number }, capacity: number, controllers)
	local folder = Instance.new("Folder")
	folder.Name = "VarianceTable"
	folder.Parent = workspace
	local self = setmetatable({
		Arena = arena,
		Origin = origin,
		Seats = seats,
		Capacity = capacity,
		Props = {},
		Monitors = {},
		Folder = folder,
		Moving = {},
		Highlight = nil,
		Controllers = controllers,
	}, TableView)
	for subjectId in seats do
		self.Props[subjectId] = {}
	end
	return self
end

function TableView:destroy()
	self.Folder:Destroy()
	for _, monitor in self.Monitors do
		for _, gui in monitor.Guis do
			for _, child in gui:GetChildren() do
				child:Destroy()
			end
		end
	end
	table.clear(self.Monitors)
end

---------------------------------------------------------------------------
-- Props
---------------------------------------------------------------------------

function TableView:slotCFrame(subjectId: number, slot: number): CFrame
	local seat = self.Seats[subjectId] or 1
	return self.Origin * TableLayout.slotCFrame(seat, slot, math.max(self.Capacity, slot))
end

function TableView:setCapacity(capacity: number)
	if capacity ~= self.Capacity then
		self.Capacity = capacity
		for subjectId in self.Props do
			self:layout(subjectId, 0.3)
		end
	end
end

-- Eases a prop to a CFrame (with an optional hop).
function TableView:move(prop: Model, to: CFrame, duration: number, hop: number?, delay: number?, onDone: (() -> ())?)
	for i = #self.Moving, 1, -1 do
		if self.Moving[i].Prop == prop then
			table.remove(self.Moving, i)
		end
	end
	local primary = prop.PrimaryPart
	local from = prop:GetAttribute("At") or (primary and primary.CFrame) or to
	table.insert(self.Moving, {
		Prop = prop,
		From = from,
		To = to,
		Start = os.clock() + (delay or 0),
		Duration = math.max(duration, 0.01),
		Hop = hop or 0,
		OnDone = onDone,
	})
end

local function place(prop: Model, cf: CFrame)
	prop:SetAttribute("At", cf)
	InstrumentProps.place(prop, cf)
end

function TableView:step()
	local now = os.clock()
	for i = #self.Moving, 1, -1 do
		local m = self.Moving[i]
		if m.Prop.Parent == nil then
			table.remove(self.Moving, i)
		else
			local t = (now - m.Start) / m.Duration
			if t >= 0 then
				if t >= 1 then
					place(m.Prop, m.To)
					table.remove(self.Moving, i)
					if m.OnDone then
						m.OnDone()
					end
				else
					local a = t * t * (3 - 2 * t)
					local cf = m.From:Lerp(m.To, a) + Vector3.new(0, math.sin(t * math.pi) * m.Hop, 0)
					place(m.Prop, cf)
				end
			end
		end
	end
end

-- Moves every prop of a subject to its slot.
function TableView:layout(subjectId: number, duration: number?)
	for slot, prop in self.Props[subjectId] or {} do
		self:move(prop, self:slotCFrame(subjectId, slot), duration or 0.3, 0.1)
	end
end

local function build(self, id: string): Model
	local prop = InstrumentProps.build(id)
	prop.Parent = self.Folder
	return prop
end

-- Snaps a subject's tray to an inventory (join, resync, trial start).
function TableView:sync(subjectId: number, inventory: { string })
	local list = self.Props[subjectId]
	if list == nil then
		return
	end
	for _, prop in list do
		prop:Destroy()
	end
	table.clear(list)
	for slot, id in inventory do
		local prop = build(self, id)
		place(prop, self:slotCFrame(subjectId, slot))
		list[slot] = prop
	end
end

-- New instruments arrive: each drops into its slot, one after another.
-- `inventory` is the full list after the deal; `lost` the ones that didn't
-- fit (they fizzle above the tray).
function TableView:deal(subjectId: number, inventory: { string }, lost: { string }, stagger: number)
	local list = self.Props[subjectId]
	if list == nil then
		return
	end
	local audio = self.Controllers.AudioController
	local vfx = self.Controllers.VFXController
	-- Reconcile: keep existing props that still match, build the rest.
	local keep = #list
	for slot = 1, #list do
		if inventory[slot] ~= list[slot]:GetAttribute("Instrument") then
			keep = slot - 1
			break
		end
	end
	for slot = #list, keep + 1, -1 do
		list[slot]:Destroy()
		list[slot] = nil
	end
	local order = 0
	for slot = keep + 1, #inventory do
		local id = inventory[slot]
		local prop = build(self, id)
		local target = self:slotCFrame(subjectId, slot)
		place(prop, target + Vector3.new(0, 3.2, 0))
		list[slot] = prop
		local delay = order * stagger
		order += 1
		local def = Instruments.get(id)
		self:move(prop, target, 0.28, 0, delay, function()
			audio:play("Deal", { At = target.Position })
			if def and def.Rarity == "Rare" then
				vfx:flash(target.Position + Vector3.new(0, 0.4, 0), Theme.Colors.Accent, 1.2, 0.4, 2)
				vfx:motes(target.Position + Vector3.new(0, 0.4, 0), Theme.Colors.Accent, 10)
			end
		end)
	end
	for i, id in lost do
		local seat = self.Seats[subjectId] or 1
		local above = self.Origin * TableLayout.trayCFrame(seat) * CFrame.new((i - 1) * 0.9 - 0.4, 1.4, 0)
		local prop = build(self, id)
		place(prop, above)
		task.delay(order * stagger + i * 0.15, function()
			audio:play("Lost", { At = above.Position })
			vfx:sparks(above.Position, Vector3.new(0, 1, 0), Theme.Colors.Bad, 10)
			vfx:dissolve(prop, 0.5, Theme.Colors.Bad)
		end)
	end
end

-- Removes the prop at `slot` from the tray and returns it (for a use animation);
-- the rest slide down to close the gap.
function TableView:take(subjectId: number, slot: number): Model?
	local list = self.Props[subjectId]
	if list == nil or list[slot] == nil then
		return nil
	end
	local prop = table.remove(list, slot)
	self:layout(subjectId, 0.35)
	return prop
end

-- Finds which slot changed between an old inventory and the new one.
function TableView.removedSlot(old: { string }, new: { string }, id: string): number?
	for i = 1, #old do
		if old[i] ~= new[i] and old[i] == id then
			return i
		end
	end
	for i = #old, 1, -1 do
		if old[i] == id then
			return i
		end
	end
	return nil
end

-- Brings the tray back in line with an inventory without rebuilding it.
function TableView:reconcile(subjectId: number, inventory: { string })
	local list = self.Props[subjectId]
	if list == nil then
		return
	end
	local matches = #list == #inventory
	if matches then
		for slot, prop in list do
			if prop:GetAttribute("Instrument") ~= inventory[slot] then
				matches = false
				break
			end
		end
	end
	if not matches then
		self:sync(subjectId, inventory)
	end
end

function TableView:prop(subjectId: number, slot: number): Model?
	local list = self.Props[subjectId]
	return list and list[slot] or nil
end

-- Highlights one of the local subject's props (HUD hover / gamepad focus).
function TableView:highlight(subjectId: number?, slot: number?)
	local prop = subjectId and slot and self:prop(subjectId, slot) or nil
	if prop == nil then
		if self.Highlight then
			self.Highlight.Adornee = nil
		end
		return
	end
	if self.Highlight == nil then
		local h = Instance.new("Highlight")
		h.Name = "SlotFocus"
		h.FillTransparency = 0.8
		h.OutlineTransparency = 0
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = self.Folder
		self.Highlight = h
	end
	local h = self.Highlight :: Highlight
	h.FillColor = Theme.Colors.Accent
	h.OutlineColor = Theme.Colors.Focus
	h.Adornee = prop
end

---------------------------------------------------------------------------
-- Integrity monitors
---------------------------------------------------------------------------

local function monitorGui(gui: SurfaceGui)
	gui:ClearAllChildren()
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundColor3 = Color3.fromRGB(6, 9, 9)
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui
	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, -16, 0.26, 0)
	name.Position = UDim2.fromOffset(8, 4)
	name.Font = Theme.Fonts.Mono
	name.TextScaled = true
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextColor3 = Theme.Colors.Dim
	name.Parent = root
	local pips = Instance.new("Frame")
	pips.Name = "Pips"
	pips.BackgroundTransparency = 1
	pips.Size = UDim2.new(1, -16, 0.4, 0)
	pips.Position = UDim2.new(0, 8, 0.3, 0)
	pips.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0.02, 0)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = pips
	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Size = UDim2.new(1, -16, 0.22, 0)
	status.Position = UDim2.new(0, 8, 0.74, 0)
	status.Font = Theme.Fonts.Mono
	status.TextScaled = true
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextColor3 = Theme.Colors.Accent
	status.RichText = true
	status.Parent = root
	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.BorderSizePixel = 0
	flash.BackgroundTransparency = 1
	flash.Size = UDim2.fromScale(1, 1)
	flash.ZIndex = 5
	flash.Parent = root
	return { Root = root, Name = name, Pips = pips, Status = status, Flash = flash }
end

function TableView:bindMonitors()
	local tableModel = self.Arena:FindFirstChild("Table")
	if tableModel == nil then
		return
	end
	for subjectId, seat in self.Seats do
		local part = tableModel:FindFirstChild("Monitor_" .. seat)
		if part then
			local entry = { Guis = {}, Views = {} }
			for _, guiName in { "Owner", "Public" } do
				local gui = part:FindFirstChild(guiName)
				if gui and gui:IsA("SurfaceGui") then
					table.insert(entry.Guis, gui)
					table.insert(entry.Views, monitorGui(gui))
				end
			end
			self.Monitors[subjectId] = entry
		end
	end
end

-- Redraws one subject's monitors.
function TableView:updateMonitor(subjectId: number, subject: { [string]: any }, name: string, wins: number, trialsToWin: number)
	local entry = self.Monitors[subjectId]
	if entry == nil then
		return
	end
	for _, view in entry.Views do
		view.Name.Text = string.upper(name) .. "  " .. string.rep("■", wins) .. string.rep("□", math.max(0, trialsToWin - wins))
		local max = subject.MaxIntegrity or 0
		local value = subject.Integrity or 0
		local existing = view.Pips:GetChildren()
		local pips = {}
		for _, child in existing do
			if child:IsA("Frame") then
				table.insert(pips, child)
			end
		end
		for i = #pips + 1, max do
			local pip = Instance.new("Frame")
			pip.Name = "Pip"
			pip.BorderSizePixel = 0
			pip.LayoutOrder = i
			pip.Size = UDim2.new(1 / math.max(max, 4) - 0.02, 0, 0.9, 0)
			pip.Parent = view.Pips
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 2
			stroke.Parent = pip
			table.insert(pips, pip)
		end
		for i, pip in pips do
			if i > max then
				pip:Destroy()
			else
				local full = i <= value
				pip.Size = UDim2.new(1 / math.max(max, 4) - 0.02, 0, 0.9, 0)
				pip.BackgroundColor3 = if value <= 1 then Theme.Colors.Bad else Theme.Colors.Text
				pip.BackgroundTransparency = if full then 0 else 1
				local stroke = pip:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Color = if full then pip.BackgroundColor3 else Theme.Colors.Faint
				end
			end
		end
		local tags = {}
		if subject.Eliminated then
			table.insert(tags, '<font color="#e0482f">OFFLINE</font>')
		end
		for effect, label in EFFECT_TAGS do
			if subject.Effects and subject.Effects[effect] then
				table.insert(tags, label)
			end
		end
		view.Status.Text = table.concat(tags, "  ")
	end
end

-- Flashes a monitor (damage red, heal pale).
function TableView:flashMonitor(subjectId: number, color: Color3)
	local entry = self.Monitors[subjectId]
	if entry == nil then
		return
	end
	for _, view in entry.Views do
		view.Flash.BackgroundColor3 = color
		view.Flash.BackgroundTransparency = 0.2
		TweenService:Create(view.Flash, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
	end
end

return TableView

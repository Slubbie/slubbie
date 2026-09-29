-- Inventories and storage.
--
-- Containers (slot refs are "<container>:<slot>"):
--   inv            the backpack; slots 1-9 are the hotbar
--   home           house storage (size from the house level)
--   chest:<uid>    a placed chest / storage barn on your farm
-- Slots are saved as dictionaries with string keys ("1".."N") so DataStores
-- and remotes never see sparse arrays.
--
-- The silo is special: a key → stack map with a total item capacity, used by
-- automation (drones, collectors, auto machines, the shipping dock).
--
-- Everything that gives items goes through Add: it merges into matching
-- stacks, fills empty slots, and sends anything that doesn't fit to the
-- mailbox so nothing is ever lost.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Land = require(Shared.Config.Land)
local Net = require(Shared.Lib.Net)
local Registry = require(Shared.Lib.Registry)
local ItemUtil = require(Shared.Lib.ItemUtil)

local S = require(script.Parent)

local InventoryService = {}

local HOTBAR = 9
local MAX_SIZE = 72
local CHEST_RANGE = 22

type Stack = ItemUtil.Stack
type Container = { Slots: { [string]: Stack }, Size: number }

-- Containers ------------------------------------------------------------------------------------

local function homeSize(profile: any): number
	local house = Land.House[profile.Farm.House or 1]
	return if house then house.Storage else 0
end

-- Resolve a container name to its slot table and size (nil if not accessible).
function InventoryService.Container(player: Player, name: string, checkRange: boolean?): Container?
	local profile = S.Data.Get(player)
	if not profile then
		return nil
	end
	if name == "inv" then
		return profile.Inventory
	elseif name == "home" then
		local size = homeSize(profile)
		if size <= 0 then
			return nil
		end
		profile.Storage.home = profile.Storage.home or { Slots = {} }
		profile.Storage.home.Size = size
		return profile.Storage.home
	end
	local uid = string.match(name, "^chest:(.+)$")
	if uid then
		local placed = profile.Farm.Placed[uid]
		local def = placed and Registry.Placeables[placed.Id]
		if not def or not def.Function or def.Function.Kind ~= "Storage" then
			return nil
		end
		if checkRange then
			local position = S.Building.WorldPosition(player, uid)
			if not position or not S.Security.InReach(player, position, CHEST_RANGE) then
				return nil
			end
		end
		profile.Storage[uid] = profile.Storage[uid] or { Slots = {} }
		profile.Storage[uid].Size = def.Function.Slots
		return profile.Storage[uid]
	end
	return nil
end

local function changed(player: Player, name: string)
	if name == "inv" then
		S.Data.Changed(player, "Inventory")
	else
		S.Data.Changed(player, "Storage")
	end
end

local function parseRef(ref: string): (string?, number?)
	local container, slot = string.match(ref, "^(.+):(%d+)$")
	return container, tonumber(slot)
end

-- Queries ----------------------------------------------------------------------------------------

function InventoryService.Slot(player: Player, ref: string): (Stack?, Container?, string?)
	local containerName, slot = parseRef(ref)
	if not containerName or not slot then
		return nil, nil, nil
	end
	local container = InventoryService.Container(player, containerName, containerName ~= "inv")
	if not container or slot < 1 or slot > container.Size then
		return nil, nil, nil
	end
	return container.Slots[tostring(slot)], container, containerName
end

-- Total count of items matching a spec ("#Tag", id...) with at least `minQuality`.
function InventoryService.Count(player: Player, spec: string, minQuality: number?): number
	local profile = S.Data.Get(player)
	if not profile then
		return 0
	end
	local total = 0
	for _, stack in profile.Inventory.Slots do
		if Registry.Matches(stack.Id, spec) and (stack.Q or 1) >= (minQuality or 1) and not stack.L then
			total += stack.N
		end
	end
	return total
end

function InventoryService.Has(player: Player, spec: string, count: number, minQuality: number?): boolean
	return InventoryService.Count(player, spec, minQuality) >= count
end

function InventoryService.FreeSlots(player: Player): number
	local profile = S.Data.Get(player)
	if not profile then
		return 0
	end
	local used = 0
	for _ in profile.Inventory.Slots do
		used += 1
	end
	return profile.Inventory.Size - used
end

-- Would these stacks fit without overflowing to the mailbox?
function InventoryService.CanFit(player: Player, stacks: { Stack }): boolean
	local profile = S.Data.Get(player)
	if not profile then
		return false
	end
	local free = InventoryService.FreeSlots(player)
	for _, stack in stacks do
		local remaining = stack.N
		for _, existing in profile.Inventory.Slots do
			if ItemUtil.CanStack(existing, stack) then
				remaining -= math.max(0, ItemUtil.MaxStack(stack.Id) - existing.N)
			end
		end
		while remaining > 0 do
			free -= 1
			remaining -= ItemUtil.MaxStack(stack.Id)
		end
	end
	return free >= 0
end

-- Adding -------------------------------------------------------------------------------------------

-- Put a stack into a container. Returns the count that didn't fit.
local function insert(container: Container, stack: Stack, preferBackpack: boolean): number
	local remaining = stack.N
	local maxStack = ItemUtil.MaxStack(stack.Id)
	-- 1) merge into existing stacks
	for i = 1, container.Size do
		if remaining <= 0 then
			break
		end
		local existing = container.Slots[tostring(i)]
		if existing and ItemUtil.CanStack(existing, stack) and existing.N < maxStack then
			local take = math.min(remaining, maxStack - existing.N)
			existing.N += take
			remaining -= take
		end
	end
	-- 2) empty slots (backpack first so the hotbar stays how you arranged it)
	local order = {}
	if preferBackpack and container.Size > HOTBAR then
		for i = HOTBAR + 1, container.Size do
			table.insert(order, i)
		end
		for i = 1, HOTBAR do
			table.insert(order, i)
		end
	else
		for i = 1, container.Size do
			table.insert(order, i)
		end
	end
	for _, i in order do
		if remaining <= 0 then
			break
		end
		local key = tostring(i)
		if not container.Slots[key] then
			local take = math.min(remaining, maxStack)
			container.Slots[key] = ItemUtil.Split(stack, take)
			remaining -= take
		end
	end
	return remaining
end

export type AddOptions = {
	Silent: boolean?, -- no reward popup
	NoMail: boolean?, -- return overflow instead of mailing it
	Source: string?,
	Position: Vector3?,
}

-- Give items. Returns the number added to the bag (the rest went to mail unless NoMail).
function InventoryService.Add(player: Player, stack: Stack, options: AddOptions?): (number, number)
	local profile = S.Data.Get(player)
	if not profile or not ItemUtil.Valid(stack) then
		return 0, 0
	end
	local opts: AddOptions = options or {}
	local leftover = insert(profile.Inventory, stack, true)
	local added = stack.N - leftover
	S.Data.Changed(player, "Inventory")
	if leftover > 0 and not opts.NoMail then
		S.Mail.Send(player, {
			From = "Evergrove Post",
			Subject = "Your bag was full",
			Body = "We kept these safe for you.",
			Items = { ItemUtil.Split(stack, leftover) },
		})
		S.Notify.Toast(player, "Bag full: extra items were sent to your mailbox.", "Warning")
	end
	if not opts.Silent then
		S.Notify.Reward(player, { ItemUtil.Split(stack, stack.N) }, 0, opts.Source, opts.Position)
	end
	S.Quest.OnItemGained(player, stack)
	return added, if opts.NoMail then leftover else 0
end

-- Convenience: give by id.
function InventoryService.Give(
	player: Player,
	id: string,
	count: number,
	quality: number?,
	mutations: { string }?,
	opts: AddOptions?
)
	if count <= 0 then
		return 0, 0
	end
	return InventoryService.Add(player, ItemUtil.New(id, count, quality, mutations), opts)
end

-- Removing -----------------------------------------------------------------------------------------

-- Remove `count` items matching `spec` (lowest quality first, locked items skipped).
-- Returns the removed stacks, or nil (and removes nothing) if there aren't enough.
function InventoryService.Remove(player: Player, spec: string, count: number, minQuality: number?): { Stack }?
	local profile = S.Data.Get(player)
	if not profile or count <= 0 then
		return nil
	end
	local candidates = {}
	for key, stack in profile.Inventory.Slots do
		if not stack.L and Registry.Matches(stack.Id, spec) and (stack.Q or 1) >= (minQuality or 1) then
			table.insert(candidates, key)
		end
	end
	local total = 0
	for _, key in candidates do
		total += profile.Inventory.Slots[key].N
	end
	if total < count then
		return nil
	end
	table.sort(candidates, function(a, b)
		local sa, sb = profile.Inventory.Slots[a], profile.Inventory.Slots[b]
		if (sa.Q or 1) ~= (sb.Q or 1) then
			return (sa.Q or 1) < (sb.Q or 1)
		end
		local ma, mb = sa.M and #sa.M or 0, sb.M and #sb.M or 0
		if ma ~= mb then
			return ma < mb
		end
		return tonumber(a) :: number > tonumber(b) :: number
	end)
	local removed = {}
	local remaining = count
	for _, key in candidates do
		if remaining <= 0 then
			break
		end
		local stack = profile.Inventory.Slots[key]
		local take = math.min(stack.N, remaining)
		table.insert(removed, ItemUtil.Split(stack, take))
		stack.N -= take
		remaining -= take
		if stack.N <= 0 then
			profile.Inventory.Slots[key] = nil
		end
	end
	S.Data.Changed(player, "Inventory")
	S.Tool.OnInventoryChanged(player)
	return removed
end

-- Take items out of one slot. Returns the taken stack or nil.
function InventoryService.TakeFromSlot(player: Player, ref: string, count: number?, allowLocked: boolean?): Stack?
	local stack, container, containerName = InventoryService.Slot(player, ref)
	if not stack or not container or not containerName then
		return nil
	end
	if stack.L and not allowLocked then
		return nil
	end
	local take = math.clamp(count or stack.N, 1, stack.N)
	local taken = ItemUtil.Split(stack, take)
	stack.N -= take
	if stack.N <= 0 then
		local _, slot = parseRef(ref)
		container.Slots[tostring(slot)] = nil
	end
	changed(player, containerName)
	if containerName == "inv" then
		S.Tool.OnInventoryChanged(player)
	end
	return taken
end

-- Put a stack into a specific container (returns leftover count).
function InventoryService.AddTo(player: Player, containerName: string, stack: Stack): number
	local container = InventoryService.Container(player, containerName, containerName ~= "inv")
	if not container then
		return stack.N
	end
	local leftover = insert(container, stack, containerName == "inv")
	changed(player, containerName)
	return leftover
end

-- Player actions -------------------------------------------------------------------------------------

local function move(player: Player, from: string, to: string, count: number?)
	local fromContainerName, fromSlot = parseRef(from)
	local toContainerName, toSlot = parseRef(to)
	if not fromContainerName or not toContainerName or not fromSlot or not toSlot then
		return false, "Bad slot"
	end
	local fromContainer = InventoryService.Container(player, fromContainerName, fromContainerName ~= "inv")
	local toContainer = InventoryService.Container(player, toContainerName, toContainerName ~= "inv")
	if not fromContainer or not toContainer then
		return false, "You can't reach that"
	end
	if fromSlot < 1 or fromSlot > fromContainer.Size or toSlot < 1 or toSlot > toContainer.Size then
		return false, "Bad slot"
	end
	local fromKey, toKey = tostring(fromSlot), tostring(toSlot)
	local source = fromContainer.Slots[fromKey]
	if not source then
		return false, "Empty slot"
	end
	if fromContainer == toContainer and fromKey == toKey then
		return true
	end
	local def = Registry.Items[source.Id]
	if toContainerName ~= "inv" and def and def.Category == "Tool" then
		return false, "Tools stay in your bag"
	end
	local amount = math.clamp(count or source.N, 1, source.N)
	local target = toContainer.Slots[toKey]
	if not target then
		if amount == source.N then
			toContainer.Slots[toKey] = source
			fromContainer.Slots[fromKey] = nil
		else
			toContainer.Slots[toKey] = ItemUtil.Split(source, amount)
			source.N -= amount
		end
	elseif ItemUtil.CanStack(target, source) then
		local space = ItemUtil.MaxStack(source.Id) - target.N
		local moved = math.min(space, amount)
		if moved <= 0 then
			return false, "That stack is full"
		end
		target.N += moved
		source.N -= moved
		if source.N <= 0 then
			fromContainer.Slots[fromKey] = nil
		end
	else
		if amount ~= source.N then
			return false, "Can't split onto a different item"
		end
		local targetDef = Registry.Items[target.Id]
		if fromContainerName ~= "inv" and targetDef and targetDef.Category == "Tool" then
			return false, "Tools stay in your bag"
		end
		toContainer.Slots[toKey] = source
		fromContainer.Slots[fromKey] = target
	end
	changed(player, fromContainerName)
	changed(player, toContainerName)
	S.Tool.OnInventoryChanged(player)
	if toContainerName ~= "inv" and fromContainerName == "inv" then
		S.Tutorial.Event(player, "Store")
	end
	return true
end

local CATEGORY_ORDER = {
	Tool = 1,
	Seed = 2,
	Crop = 3,
	Fertilizer = 4,
	Supply = 5,
	Bait = 6,
	Fish = 7,
	AnimalProduct = 8,
	Artisan = 9,
	Food = 10,
	Potion = 11,
	Ingredient = 12,
	Feed = 13,
	Forage = 14,
	Bug = 15,
	Material = 16,
	Mineral = 17,
	Gem = 18,
	Artifact = 19,
	Treasure = 20,
	Placeable = 21,
	Book = 22,
	Special = 23,
}

local function sortContainer(player: Player, containerName: string)
	local container = InventoryService.Container(player, containerName, containerName ~= "inv")
	if not container then
		return false, "You can't reach that"
	end
	local first = if containerName == "inv" then HOTBAR + 1 else 1
	local items = {}
	for i = first, container.Size do
		local key = tostring(i)
		local stack = container.Slots[key]
		if stack then
			table.insert(items, stack)
			container.Slots[key] = nil
		end
	end
	-- Merge identical stacks first.
	local merged = {}
	for _, stack in items do
		local placed = false
		for _, m in merged do
			if ItemUtil.CanStack(m, stack) and m.N < ItemUtil.MaxStack(m.Id) then
				local space = ItemUtil.MaxStack(m.Id) - m.N
				local moved = math.min(space, stack.N)
				m.N += moved
				stack.N -= moved
				if stack.N <= 0 then
					placed = true
					break
				end
			end
		end
		if not placed then
			table.insert(merged, stack)
		end
	end
	table.sort(merged, function(a, b)
		if (a.L == true) ~= (b.L == true) then
			return a.L == true
		end
		local da, db = Registry.Items[a.Id], Registry.Items[b.Id]
		local ca, cb = CATEGORY_ORDER[da.Category] or 50, CATEGORY_ORDER[db.Category] or 50
		if ca ~= cb then
			return ca < cb
		end
		local ra, rb = Registry.RarityOrder(da.Rarity), Registry.RarityOrder(db.Rarity)
		if ra ~= rb then
			return ra > rb
		end
		if da.Name ~= db.Name then
			return da.Name < db.Name
		end
		return (a.Q or 1) > (b.Q or 1)
	end)
	for i, stack in merged do
		container.Slots[tostring(first + i - 1)] = stack
	end
	changed(player, containerName)
	return true
end

local function lock(player: Player, ref: string)
	local stack, _, containerName = InventoryService.Slot(player, ref)
	if not stack or not containerName then
		return false, "Empty slot"
	end
	stack.L = if stack.L then nil else true
	changed(player, containerName)
	return true, stack.L == true
end

local function trash(player: Player, ref: string, count: number?)
	local stack = InventoryService.Slot(player, ref)
	if not stack then
		return false, "Empty slot"
	end
	local def = Registry.Items[stack.Id]
	if not def or def.NoTrash then
		return false, "You can't throw that away"
	end
	if stack.L then
		return false, "Unlock it first"
	end
	local taken = InventoryService.TakeFromSlot(player, ref, count)
	if taken then
		S.Data.AddStat(player, "ItemsTrashed", taken.N)
	end
	return taken ~= nil
end

local function quick(player: Player, ref: string, targetName: string)
	local stack, _, fromName = InventoryService.Slot(player, ref)
	if not stack or not fromName then
		return false, "Empty slot"
	end
	if fromName == targetName then
		return false, "Same container"
	end
	local def = Registry.Items[stack.Id]
	if targetName ~= "inv" and def.Category == "Tool" then
		return false, "Tools stay in your bag"
	end
	local target = InventoryService.Container(player, targetName, targetName ~= "inv")
	if not target then
		return false, "You can't reach that"
	end
	local taken = InventoryService.TakeFromSlot(player, ref, nil, true)
	if not taken then
		return false, "Can't move that"
	end
	local leftover = insert(target, taken, targetName == "inv")
	if leftover > 0 then
		-- Put back what didn't fit.
		local back = ItemUtil.Split(taken, leftover)
		local sourceContainer = InventoryService.Container(player, fromName, false)
		if sourceContainer then
			insert(sourceContainer, back, fromName == "inv")
		end
	end
	changed(player, fromName)
	changed(player, targetName)
	if targetName ~= "inv" then
		S.Tutorial.Event(player, "Store")
	end
	return true, leftover
end

-- Move every stack from one container that also exists in the other (like "deposit matching").
local function stackAll(player: Player, fromName: string, toName: string)
	local from = InventoryService.Container(player, fromName, fromName ~= "inv")
	local to = InventoryService.Container(player, toName, toName ~= "inv")
	if not from or not to then
		return false, "You can't reach that"
	end
	local moved = 0
	for key, stack in from.Slots do
		local slot = tonumber(key) :: number
		if not stack.L and not (fromName == "inv" and slot <= HOTBAR) then
			local present = false
			for _, other in to.Slots do
				if ItemUtil.CanStack(other, stack) then
					present = true
					break
				end
			end
			if present then
				local leftover = insert(to, stack, toName == "inv")
				moved += stack.N - leftover
				if leftover <= 0 then
					from.Slots[key] = nil
				else
					stack.N = leftover
				end
			end
		end
	end
	changed(player, fromName)
	changed(player, toName)
	return true, moved
end

-- House storage size follows the house level.
function InventoryService.RecalculateHomeStorage(player: Player)
	local profile = S.Data.Get(player)
	if not profile then
		return
	end
	if homeSize(profile) > 0 then
		InventoryService.Container(player, "home", false)
		S.Data.Changed(player, "Storage")
	end
end

-- Backpack upgrades (bought at Pip's / granted by rewards).
function InventoryService.SetSize(player: Player, size: number)
	local profile = S.Data.Get(player)
	if not profile then
		return
	end
	profile.Inventory.Size = math.clamp(size, profile.Inventory.Size, MAX_SIZE)
	S.Data.Changed(player, "Inventory")
end

-- Silo (automation storage) ---------------------------------------------------------------------------

function InventoryService.SiloCapacity(player: Player): number
	local profile = S.Data.Get(player)
	if not profile then
		return 0
	end
	local capacity = 0
	for _, placed in profile.Farm.Placed do
		local def = Registry.Placeables[placed.Id]
		if def and def.Function and def.Function.Kind == "Silo" then
			capacity += def.Function.Capacity
		end
	end
	return capacity
end

function InventoryService.SiloCount(player: Player): number
	local profile = S.Data.Get(player)
	if not profile then
		return 0
	end
	local total = 0
	for _, stack in profile.Silo.Items do
		total += stack.N
	end
	return total
end

-- Store in the silo (returns leftover that didn't fit).
function InventoryService.SiloAdd(player: Player, stack: Stack): number
	local profile = S.Data.Get(player)
	if not profile then
		return stack.N
	end
	local space = InventoryService.SiloCapacity(player) - InventoryService.SiloCount(player)
	local amount = math.min(space, stack.N)
	if amount <= 0 then
		return stack.N
	end
	local key = ItemUtil.Key(stack)
	local existing = profile.Silo.Items[key]
	if existing then
		existing.N += amount
	else
		profile.Silo.Items[key] = ItemUtil.Split(stack, amount)
	end
	S.Data.Changed(player, "Silo")
	return stack.N - amount
end

-- Take up to `count` items matching `spec` from the silo. Returns taken stacks.
function InventoryService.SiloTake(player: Player, spec: string, count: number, minQuality: number?): { Stack }
	local profile = S.Data.Get(player)
	local taken = {}
	if not profile then
		return taken
	end
	local remaining = count
	for key, stack in profile.Silo.Items do
		if remaining <= 0 then
			break
		end
		if Registry.Matches(stack.Id, spec) and (stack.Q or 1) >= (minQuality or 1) then
			local take = math.min(remaining, stack.N)
			table.insert(taken, ItemUtil.Split(stack, take))
			stack.N -= take
			remaining -= take
			if stack.N <= 0 then
				profile.Silo.Items[key] = nil
			end
		end
	end
	if #taken > 0 then
		S.Data.Changed(player, "Silo")
	end
	return taken
end

function InventoryService.SiloCountOf(player: Player, spec: string): number
	local profile = S.Data.Get(player)
	local total = 0
	if profile then
		for _, stack in profile.Silo.Items do
			if Registry.Matches(stack.Id, spec) then
				total += stack.N
			end
		end
	end
	return total
end

-- Withdraw from the silo to the bag (player action via InvQuick with ref "silo:<key>" isn't slot-based,
-- so the UI uses InvMove from a pseudo-ref; handled here).
local function siloWithdraw(player: Player, key: string)
	local profile = S.Data.Get(player)
	if not profile then
		return false, "Not ready"
	end
	local stack = profile.Silo.Items[key]
	if not stack then
		return false, "Nothing there"
	end
	local farmPosition = S.Farm.SpawnCFrame(player)
	if not farmPosition or not S.Security.InReach(player, farmPosition.Position, 400) then
		return false, "Go to your farm to use the silo"
	end
	profile.Silo.Items[key] = nil
	S.Data.Changed(player, "Silo")
	InventoryService.Add(player, stack, { Silent = true })
	return true
end

function InventoryService.Init()
	Net.Handle("InvMove", function(player, from, to, count)
		if string.sub(from, 1, 5) == "silo:" then
			return siloWithdraw(player, string.sub(from, 6))
		end
		return move(player, from, to, count)
	end)
	Net.Handle("InvSort", sortContainer)
	Net.Handle("InvLock", lock)
	Net.Handle("InvTrash", trash)
	Net.Handle("InvQuick", quick)
	Net.Handle("InvStackAll", stackAll)
end

return InventoryService

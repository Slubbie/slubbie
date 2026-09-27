-- Geometry of the evaluation table, shared by the server (which builds and
-- seats) and the client (which animates, places props and frames the camera).
-- All CFrames are relative to the arena's origin; multiply by the arena origin
-- CFrame to get world space. Seat 1 is south (+Z), 2 north, 3 east, 4 west.

local TableLayout = {}

-- R6 bodies are rigid: seated, the thighs lie flat at hip height, so the
-- torso centre sits 1.55 above the chair pan and the table has to clear the
-- top of the thighs (hip + 0.5). The table top sits at mid-torso, like a desk.
TableLayout.TableTop = 2.8 -- height of the table surface
TableLayout.TableSize = Vector3.new(9, 0.2, 9)
TableLayout.RimHeight = 0.2
TableLayout.SeatDistance = 5.35 -- table centre to the seated subject's root
TableLayout.SeatHeight = 1.5 -- chair seat surface
TableLayout.TorsoHeight = TableLayout.SeatHeight + 1.55 -- seated torso centre
-- The chair's pivot sits behind the seat point so its back meets the torso.
TableLayout.ChairOffset = -0.3
-- How far a chair starts pulled out before its subject sits (client-side):
-- far enough that rigid R6 legs can swing up in front of the pan without
-- touching it or the underside of the table.
TableLayout.ChairPull = 2.9
-- Front edge of the chair pan, relative to the seat point (chair pushed in).
TableLayout.PanFront = TableLayout.ChairOffset - 1.05
TableLayout.TrayDistance = 3.1 -- table centre to the tray row
TableLayout.SlotSpacing = 0.82

local SEAT_DIRECTIONS = {
	Vector3.new(0, 0, 1),
	Vector3.new(0, 0, -1),
	Vector3.new(1, 0, 0),
	Vector3.new(-1, 0, 0),
}

-- Which physical seats a match of `count` subjects uses, by subject order.
function TableLayout.seatsFor(count: number): { number }
	if count <= 2 then
		return { 1, 2 }
	elseif count == 3 then
		return { 1, 3, 4 }
	end
	return { 1, 3, 2, 4 } -- clockwise turn order around the table
end

function TableLayout.direction(seat: number): Vector3
	return SEAT_DIRECTIONS[seat] or SEAT_DIRECTIONS[1]
end

-- The seat's frame on the floor: facing the table centre.
function TableLayout.seatCFrame(seat: number): CFrame
	local dir = TableLayout.direction(seat)
	local pos = dir * TableLayout.SeatDistance
	return CFrame.lookAt(pos, Vector3.zero)
end

-- Where a seated rig's HumanoidRootPart goes: the seated torso centre. It is
-- also exactly standing height (feet on the floor), so a body that has not
-- been posed yet stands beside the table instead of sinking into it.
function TableLayout.rootCFrame(seat: number): CFrame
	return TableLayout.seatCFrame(seat) + Vector3.new(0, TableLayout.TorsoHeight, 0)
end

-- Eye point for the first-person seat camera (head centre + 0.12, 0.3 forward).
function TableLayout.eyeCFrame(seat: number): CFrame
	return TableLayout.rootCFrame(seat) * CFrame.new(0, 1.62, -0.3)
end

-- The chair's frame on the floor (pulled out by `pull` studs).
function TableLayout.chairCFrame(seat: number, pull: number?): CFrame
	return TableLayout.seatCFrame(seat) * CFrame.new(0, 0, TableLayout.ChairOffset + (pull or 0))
end

function TableLayout.trayCFrame(seat: number): CFrame
	local dir = TableLayout.direction(seat)
	local pos = dir * TableLayout.TrayDistance + Vector3.new(0, TableLayout.TableTop, 0)
	return CFrame.lookAt(pos, Vector3.new(0, TableLayout.TableTop, 0))
end

-- Instrument slot `slot` of `capacity` in a seat's tray (two rows past 4).
function TableLayout.slotCFrame(seat: number, slot: number, capacity: number): CFrame
	local perRow = capacity > 4 and math.ceil(capacity / 2) or capacity
	local row = slot > perRow and 1 or 0
	local col = row == 1 and slot - perRow or slot
	local count = row == 1 and capacity - perRow or perRow
	local x = (col - (count + 1) / 2) * TableLayout.SlotSpacing
	-- The tray frame looks at the table centre, so local +Z points at the subject;
	-- row 0 sits nearest the subject, row 1 toward the centre.
	return TableLayout.trayCFrame(seat) * CFrame.new(x, 0.02, 0.35 - row * 0.8) * CFrame.Angles(0, math.pi, 0)
end

-- The Arbiter at rest: lying on the table centre, muzzle toward seat 3 (east).
function TableLayout.deviceRest(): CFrame
	return CFrame.new(0, TableLayout.TableTop + 0.42, 0)
		* CFrame.Angles(0, -math.pi / 2, 0)
		* CFrame.Angles(0, 0, -math.pi / 2)
end

-- The rack where announced cells are displayed before loading (table centre, north-west).
function TableLayout.rackCFrame(): CFrame
	return CFrame.new(-1.6, TableLayout.TableTop + 0.06, -1.2)
end

-- Position of cell `i` of `n` on the rack.
function TableLayout.rackSlot(i: number, n: number): CFrame
	local spacing = 0.36
	local x = (i - (n + 1) / 2) * spacing
	return TableLayout.rackCFrame() * CFrame.new(x, 0.34, 0)
end

-- Integrity monitor beside each seat's tray (to the subject's right). Its Front
-- face turns toward the subject, its Back face toward the rest of the table.
function TableLayout.monitorCFrame(seat: number): CFrame
	return TableLayout.trayCFrame(seat)
		* CFrame.new(2.75, 0.5, 0.25)
		* CFrame.Angles(0, math.pi, 0)
		* CFrame.Angles(math.rad(-18), 0, 0)
end

-- Where spent cells land after ejection (a small tray to the side).
function TableLayout.spentCFrame(): CFrame
	return CFrame.new(1.8, TableLayout.TableTop + 0.05, 1.3)
end

return TableLayout

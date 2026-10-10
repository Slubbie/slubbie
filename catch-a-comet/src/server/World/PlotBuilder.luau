-- Builds one personal sanctuary plot: a floating platform with an entrance
-- arch facing the hub, a courtyard, twelve habitat pads in two arcs, lanterns
-- and an owner sign. SetTier adds the decorations each Habitat level unlocks.
--
-- Plot space: X to the right (seen from the hub), Z toward the back.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldLayout = require(Shared.WorldLayout)

local Kit = require(script.Parent.Kit)

local PlotBuilder = {}

local C = Kit.Colors
local M = Enum.Material

export type Pad = {
	Slot: number,
	Base: Part,
	Glow: Part,
	Prompt: ProximityPrompt,
	Lock: BillboardGui,
	Anchor: CFrame,
}

export type Plot = {
	Index: number,
	Model: Model,
	Frame: CFrame,
	Pads: { Pad },
	Sign: BillboardGui,
	ArchSign: SurfaceGui,
	Beacon: Part,
	Tier: Folder,
	Displays: Folder,
	TierLevel: number,
}

local function plotFrame(index: number): CFrame
	return WorldLayout.Plots[index].CFrame
end

function PlotBuilder.Build(parent: Instance, index: number, rng: Random): Plot
	local layout = WorldLayout.Plots[index]
	local frame = plotFrame(index)
	local center = layout.Center
	local radius = WorldLayout.Sanctuary.PlotRadius
	local model = Kit.Model("Plot" .. index, parent)
	model:SetAttribute("PlotIndex", index)

	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end

	-- Platform.
	local floor = Kit.Disc(model, radius * 2, 4, center, C.Grass, M.Grass)
	floor.Name = "Floor"
	floor:AddTag("Walkable")
	Kit.Disc(model, radius * 2 + 3, 3, center - Vector3.new(0, 1.8, 0), C.Stone, M.Slate)
	local underside = { { 80, 27 }, { 62, 19 }, { 42, 11 }, { 22, 3 } }
	for _, layer in underside do
		Kit.Column(model, layer[1], 8, Vector3.new(center.X, layer[2], center.Z), C.StoneDark, M.Slate, true)
	end
	for k = 0, 3 do
		local a = k * math.pi / 2 + rng:NextNumber()
		local p = center + Vector3.new(math.cos(a) * 12, -38, math.sin(a) * 12)
		Kit.Wedge(
			model,
			Vector3.new(2, 7, 2),
			CFrame.new(p) * CFrame.Angles(math.rad(180), a, 0),
			C.Lavender,
			M.Neon,
			true
		)
	end

	-- Courtyard.
	local courtyard = (frame * CFrame.new(WorldLayout.CourtyardOffset)).Position
	local court = Kit.Disc(model, 17, 0.4, courtyard + Vector3.new(0, 0.3, 0), C.Marble, M.Marble)
	court.Name = "Courtyard"
	Kit.Ring(model, CFrame.new(courtyard + Vector3.new(0, 0.32, 0)), 7.6, Vector2.new(0.5, 0.15), 24, C.Gold, M.Neon)

	-- Entrance arch facing the hub.
	for _, side in { -1, 1 } do
		Kit.Column(model, 2.2, 12, at(side * 7, 0, -radius + 3).Position, C.Marble, M.Marble)
		Kit.Ball(model, 1.4, at(side * 7, 12.8, -radius + 3).Position, C.Gold, M.Neon)
	end
	local beam = Kit.Part(
		model,
		Vector3.new(17, 2.4, 1.6),
		at(0, 13, -radius + 3),
		{ Color = C.MarbleShade, Material = M.Marble }
	)
	beam.Name = "ArchBeam"
	local archSign = Kit.Sign(beam, Enum.NormalId.Front, { "Open Sanctuary" }, { PixelsPerStud = 30 })

	-- Habitat pads.
	local pads: { Pad } = {}
	for slot = 1, #WorldLayout.SlotOffsets do
		local top = WorldLayout.SlotPosition(index, slot)
		local base = Kit.Column(model, 11, 1.4, top - Vector3.new(0, 1.4, 0), C.Marble, M.Marble)
		base.Name = "Pad" .. slot
		base:SetAttribute("PlotIndex", index)
		base:SetAttribute("Slot", slot)
		base:AddTag("HabitatPad")
		local glow = Kit.Disc(model, 12.2, 0.45, Vector3.new(top.X, center.Y + 0.45, top.Z), C.Cyan, M.Neon, true)
		glow.Name = "PadGlow" .. slot
		local prompt = Kit.Prompt(base, "Habitat", "Place Creature", `Habitat {slot}`, 10)
		prompt:SetAttribute("PlotIndex", index)
		prompt:SetAttribute("Slot", slot)
		local lock = Kit.Billboard(
			base,
			"🔒",
			nil,
			{ Name = "Lock", Offset = Vector3.new(0, 3, 0), MaxDistance = 60, Width = 60 }
		)
		lock.Enabled = false
		local facing = courtyard + frame.LookVector * 12
		pads[slot] = {
			Slot = slot,
			Base = base,
			Glow = glow,
			Prompt = prompt,
			Lock = lock,
			Anchor = CFrame.lookAt(top, Vector3.new(facing.X, top.Y, facing.Z)),
		}
	end

	-- Lanterns around the rim, and a beacon at the back.
	for k = 0, 5 do
		local a = math.rad(k * 60 + 30)
		local p = center + Vector3.new(math.cos(a), 0, math.sin(a)) * (radius - 3)
		Kit.Lantern(model, p, C.Gold, k % 3 == 0)
	end
	local beacon = Kit.Column(model, 1.2, 26, at(0, 0, radius - 4).Position, C.Lavender, M.Neon, true)
	beacon.Name = "Beacon"
	beacon.Transparency = 0.4

	local signAnchor = Kit.Part(model, Vector3.new(1, 1, 1), CFrame.new(courtyard + Vector3.new(0, 2, 0)), {
		Name = "SignAnchor",
		Transparency = 1,
		Decor = true,
	})
	local sign = Kit.Billboard(signAnchor, "Open Sanctuary", "Unclaimed", {
		Name = "OwnerSign",
		Offset = Vector3.new(0, 15, 0),
		MaxDistance = 260,
		Width = 320,
	})

	local tier = Kit.Folder("Tier", model)
	local displays = Kit.Folder("Displays", model)
	return {
		Index = index,
		Model = model,
		Frame = frame,
		Pads = pads,
		Sign = sign,
		ArchSign = archSign,
		Beacon = beacon,
		Tier = tier,
		Displays = displays,
		TierLevel = 0,
	}
end

-- Rebuilds the decorations unlocked by Habitat levels (cumulative).
function PlotBuilder.SetTier(plot: Plot, habitatLevel: number)
	if plot.TierLevel == habitatLevel then
		return
	end
	plot.TierLevel = habitatLevel
	plot.Tier:ClearAllChildren()
	local frame = plot.Frame
	local radius = WorldLayout.Sanctuary.PlotRadius
	local courtyard = (frame * CFrame.new(WorldLayout.CourtyardOffset)).Position
	local tier = plot.Tier

	if habitatLevel >= 2 then
		-- Glowing star path from the entrance to the courtyard and around it.
		for k = 0, 8 do
			local z = -radius + 6 + k * 2.6
			local p = (frame * CFrame.new(0, 0.15, z)).Position
			Kit.Block(
				tier,
				Vector3.new(1.3, 0.25, 1.3),
				CFrame.new(p) * frame.Rotation * CFrame.Angles(0, math.rad(45), 0),
				C.Gold,
				M.Neon,
				true
			)
		end
		for k = 0, 9 do
			local a = k / 10 * math.pi * 2
			local p = courtyard + Vector3.new(math.cos(a) * 11, 0.15, math.sin(a) * 11)
			Kit.Block(
				tier,
				Vector3.new(1, 0.25, 1),
				CFrame.new(p) * CFrame.Angles(0, a + math.rad(45), 0),
				C.Lavender,
				M.Neon,
				true
			)
		end
	end
	if habitatLevel >= 3 then
		local ringModel, root = Kit.Animated(
			tier,
			"StarRing",
			CFrame.new(courtyard + Vector3.new(0, 22, 0)) * CFrame.Angles(math.rad(12), 0, 0),
			"Spinner",
			{
				SpinAxis = "Y",
				SpinSpeed = 0.15,
			}
		)
		for _, part in Kit.Ring(ringModel, root.CFrame, 15, Vector2.new(0.6, 0.6), 30, C.Lavender, M.Neon) do
			Kit.WeldTo(part, root)
		end
		for k = 0, 3 do
			local a = k * math.pi / 2
			local star = Kit.Block(
				ringModel,
				Vector3.new(1.6, 1.6, 0.4),
				root.CFrame * CFrame.new(math.cos(a) * 15, 0, math.sin(a) * 15) * CFrame.Angles(0, -a, math.rad(45)),
				C.Gold,
				M.Neon,
				true
			)
			Kit.WeldTo(star, root)
		end
	end
	if habitatLevel >= 4 then
		local fountain = Kit.Model("Fountain", tier)
		Kit.Column(fountain, 9, 1.6, courtyard + Vector3.new(0, 0.3, 0), C.MarbleShade, M.Marble)
		local water = Kit.Disc(fountain, 7.6, 0.3, courtyard + Vector3.new(0, 1.8, 0), C.Cyan, M.Glass, true)
		water.Transparency = 0.3
		Kit.Column(fountain, 1.2, 6, courtyard + Vector3.new(0, 1.9, 0), C.Marble, M.Marble)
		local orb = Kit.Ball(fountain, 1.8, courtyard + Vector3.new(0, 8.6, 0), C.Cyan, M.Neon)
		Kit.Light(orb, C.Cyan, 18, 1)
		Kit.Emitter(orb, {
			Color = ColorSequence.new(C.Cyan, Color3.new(1, 1, 1)),
			Rate = 18,
			Speed = NumberRange.new(5, 7),
			SpreadAngle = Vector2.new(25, 25),
			Acceleration = Vector3.new(0, -12, 0),
			Lifetime = NumberRange.new(1, 1.4),
			EmissionDirection = Enum.NormalId.Top,
		})
	end
	if habitatLevel >= 5 then
		for k = 0, 2 do
			local a = math.rad(-50 + k * 50)
			local offset = Vector3.new(math.sin(a) * (radius + 14), 14 + k * 3, math.cos(a) * (radius + 14))
			local p = (frame * CFrame.new(offset)).Position
			local islet, root = Kit.Animated(tier, "Islet", CFrame.new(p), "Bobber", {
				BobAmount = 1.4,
				BobSpeed = 0.5 + k * 0.1,
				SpinSpeed = 0.05,
			})
			local parts = {
				Kit.Disc(islet, 12, 1.5, p, C.Grass, M.Grass, true),
				Kit.Column(islet, 9, 3, p - Vector3.new(0, 4.5, 0), C.StoneDark, M.Slate, true),
				Kit.Column(islet, 5, 3, p - Vector3.new(0, 7.5, 0), C.StoneDark, M.Slate, true),
				Kit.Column(islet, 0.8, 5, p, C.WoodDark, M.Wood, true),
				Kit.Ball(islet, 3.6, p + Vector3.new(0, 5.5, 0), C.Leaf[k + 1], M.SmoothPlastic),
				Kit.Ball(islet, 1.2, p + Vector3.new(1.4, 5, -1), C.Gold, M.Neon),
			}
			for _, part in parts do
				Kit.WeldTo(part, root)
			end
		end
	end
end

return PlotBuilder

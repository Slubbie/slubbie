-- Character presentation for every player on the server:
--   * held tool models (character attribute Held/HeldTier) welded to the hand
--   * powered vehicles (Vehicle) and horses (Riding) under the character
--   * procedural action animations from the Act attribute ("Till@123.45"),
--     layered on top of Roblox's default animations through Motor6D.Transform
--   * emotes / poses (Pose attribute) and cosmetic companions (Companion)
--   * fishing line + bobber (Bobber attribute)
-- No animation assets are needed, so this works out of the box for R6 and R15.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Registry = require(Shared.Lib.Registry)
local Kit = require(Shared.Models.Kit)
local ToolModels = require(Shared.Models.Tools)

local C = require(script.Parent)

local AnimationController = {}

type Joints = { RightShoulder: Motor6D?, LeftShoulder: Motor6D?, Waist: Motor6D?, Neck: Motor6D?, RightHip: Motor6D?, LeftHip: Motor6D? }
type Rig = {
	Character: Model,
	Joints: Joints,
	Held: Model?,
	HeldKey: string,
	Vehicle: Model?,
	Mount: Model?,
	Companion: Model?,
	Action: string?,
	ActionStart: number,
	Line: Beam?,
	Bobber: BasePart?,
	R15: boolean,
}

local rigs: { [Model]: Rig } = {}

local ACTION_TIME = {
	Till = 0.55, Water = 0.7, Harvest = 0.45, Chop = 0.5, Mine = 0.5, Dig = 0.6, Cast = 0.7, Net = 0.45,
	Pick = 0.5, Catch = 0.8, Plant = 0.5, Prune = 0.4, Fertilize = 0.5, Spray = 0.6, Pet = 0.8, Eat = 0.9,
}

-- Rig discovery ------------------------------------------------------------------------------------------------------

local function findJoints(character: Model): (Joints, boolean)
	local j: Joints = {}
	local r15 = character:FindFirstChild("UpperTorso") ~= nil
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") then
			local n = d.Name
			if n == "RightShoulder" or n == "Right Shoulder" then
				j.RightShoulder = d
			elseif n == "LeftShoulder" or n == "Left Shoulder" then
				j.LeftShoulder = d
			elseif n == "Waist" or n == "RootJoint" and not r15 then
				j.Waist = d
			elseif n == "Neck" then
				j.Neck = d
			elseif n == "RightHip" or n == "Right Hip" then
				j.RightHip = d
			elseif n == "LeftHip" or n == "Left Hip" then
				j.LeftHip = d
			end
		end
	end
	return j, r15
end

local function hand(character: Model): BasePart?
	return (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")) :: any
end

-- Held items -----------------------------------------------------------------------------------------------------------

local function pouch(color: Color3): Model
	local m = Kit.Model("Pouch")
	Kit.Ball(m, Vector3.new(0.9, 1, 0.9), CFrame.new(0, -0.3, -0.3), color, { Collide = false, Shadow = false, Material = Enum.Material.Fabric })
	Kit.Box(m, Vector3.new(0.5, 0.2, 0.5), CFrame.new(0, 0.2, -0.3), color:Lerp(Color3.new(0, 0, 0), 0.3), { Collide = false, Shadow = false })
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.Massless = true
			d.CanQuery = false
		end
	end
	return m
end

local function weldTo(model: Model, part: BasePart, offset: CFrame)
	model:PivotTo(part.CFrame * offset)
	local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= primary then
			local w = Instance.new("WeldConstraint")
			w.Part0 = primary
			w.Part1 = d
			w.Parent = d
		end
	end
	if primary then
		local w = Instance.new("WeldConstraint")
		w.Part0 = part
		w.Part1 = primary
		w.Parent = primary
	end
	model.Parent = part.Parent
end

local function updateHeld(rig: Rig)
	local character = rig.Character
	local held = character:GetAttribute("Held")
	local tier = character:GetAttribute("HeldTier") or 1
	local owner = Players:GetPlayerFromCharacter(character)
	local skin = if owner == Players.LocalPlayer then C.State.Get("Cosmetics", "Equipped", "Tools") else nil
	local key = tostring(held) .. "|" .. tostring(tier) .. "|" .. tostring(skin)
	if key == rig.HeldKey then
		return
	end
	rig.HeldKey = key
	if rig.Held then
		rig.Held:Destroy()
		rig.Held = nil
	end
	if type(held) ~= "string" or character:GetAttribute("Vehicle") then
		return
	end
	local def = Registry.Items[held]
	local grip = hand(character)
	if not def or not grip then
		return
	end
	local model
	if def.Tool then
		model = ToolModels.Held(def.Tool, tier, skin)
	elseif def.Plants or def.Fertilizer or def.Category == "Seed" then
		model = pouch(if def.Tint then def.Tint else Color3.fromRGB(190, 150, 100))
	end
	if model then
		local offset = if rig.R15 then CFrame.new(0, -0.3, 0) * CFrame.Angles(math.rad(-90), 0, 0) else CFrame.new(0, -1, 0) * CFrame.Angles(math.rad(-90), 0, 0)
		weldTo(model, grip, offset)
		rig.Held = model
	end
end

local function updateVehicle(rig: Rig)
	local character = rig.Character
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local vehicle = character:GetAttribute("Vehicle")
	if rig.Vehicle and (not vehicle or rig.Vehicle.Name ~= "Vehicle_" .. tostring(vehicle)) then
		rig.Vehicle:Destroy()
		rig.Vehicle = nil
	end
	if vehicle and not rig.Vehicle and root then
		local def = Registry.Items[vehicle]
		local id = if def and def.Powered then def.Powered.Model or def.Id else vehicle
		local model = ToolModels.Vehicle((string.gsub(id, "^powered_", "")))
		weldTo(model, root, CFrame.new(0, -3, 0))
		rig.Vehicle = model
	end
	local riding = character:GetAttribute("Riding")
	if rig.Mount and not riding then
		rig.Mount:Destroy()
		rig.Mount = nil
	end
	if riding and not rig.Mount and root then
		local species = Registry.Species[riding]
		local coatId = character:GetAttribute("RideCoat")
		local color = Color3.fromRGB(140, 95, 60)
		if species then
			for _, a in species.Coats do
				if a.Id == coatId then
					color = a.Color
				end
			end
		end
		local mount = ToolModels.Mount(color)
		weldTo(mount, root, CFrame.new(0, -4.6, 0))
		rig.Mount = mount
	end
	-- The local player's own humanoid rides higher on a horse.
	if Players:GetPlayerFromCharacter(character) == Players.LocalPlayer then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local base = humanoid:GetAttribute("BaseHip") or humanoid.HipHeight
			humanoid:SetAttribute("BaseHip", base)
			humanoid.HipHeight = base + (if riding then 3.2 elseif vehicle then 1.2 else 0)
		end
	end
end

-- Companions --------------------------------------------------------------------------------------------------------------

local function companionModel(kind: string): Model
	local m = Kit.Model("Companion")
	if kind == "owl" then
		Kit.Ball(m, Vector3.new(0.9, 1.1, 0.9), CFrame.new(0, 0.55, 0), Color3.fromRGB(150, 120, 90), { Collide = false })
		Kit.Ball(m, Vector3.new(0.7, 0.6, 0.6), CFrame.new(0, 1.2, 0), Color3.fromRGB(170, 140, 110), { Collide = false })
		for _, x in { -0.18, 0.18 } do
			Kit.Ball(m, Vector3.new(0.25, 0.25, 0.1), CFrame.new(x, 1.25, -0.3), Color3.fromRGB(255, 220, 90), { Collide = false })
		end
	else
		Kit.Ball(m, Vector3.new(0.8, 0.7, 1.6), CFrame.new(0, 0.7, 0), Color3.fromRGB(220, 110, 50), { Collide = false })
		Kit.Ball(m, Vector3.new(0.7, 0.65, 0.75), CFrame.new(0, 1.05, -0.8), Color3.fromRGB(220, 110, 50), { Collide = false })
		Kit.Wedge(m, Vector3.new(0.15, 0.35, 0.25), CFrame.new(-0.2, 1.45, -0.8), Color3.fromRGB(200, 90, 40), { Collide = false })
		Kit.Wedge(m, Vector3.new(0.15, 0.35, 0.25), CFrame.new(0.2, 1.45, -0.8), Color3.fromRGB(200, 90, 40), { Collide = false })
		Kit.Ball(m, Vector3.new(0.5, 0.5, 1.2), CFrame.new(0, 0.8, 1) * CFrame.Angles(0.4, 0, 0), Color3.fromRGB(250, 240, 230), { Collide = false, Name = "Tail" })
		for _, p in { { -0.25, -0.5 }, { 0.25, -0.5 }, { -0.25, 0.5 }, { 0.25, 0.5 } } do
			Kit.Box(m, Vector3.new(0.18, 0.4, 0.18), CFrame.new(p[1], 0.2, p[2]), Color3.fromRGB(60, 40, 30), { Collide = false })
		end
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanQuery = false
			d.CanCollide = false
			d.CastShadow = false
		end
	end
	return m
end

local function updateCompanion(rig: Rig)
	local kind = rig.Character:GetAttribute("Companion")
	if rig.Companion and (not kind or rig.Companion:GetAttribute("Kind") ~= kind) then
		rig.Companion:Destroy()
		rig.Companion = nil
	end
	if kind and not rig.Companion then
		local m = companionModel(kind)
		m:SetAttribute("Kind", kind)
		m.Parent = workspace
		rig.Companion = m
	end
end

-- Procedural actions --------------------------------------------------------------------------------------------------

local function ease(t: number): number
	return math.sin(t * math.pi)
end

-- Returns joint overlays for an action at progress t (0..1).
local function actionPose(action: string, t: number): { [string]: CFrame }
	local s = ease(t)
	local swing = math.sin(t * math.pi * 2)
	if action == "Till" or action == "Chop" or action == "Mine" or action == "Dig" then
		-- Two-handed overhead swing down.
		local raise = if t < 0.45 then t / 0.45 else 1 - (t - 0.45) / 0.55
		local a = math.rad(-150 * raise + 40 * (1 - raise))
		return { RightShoulder = CFrame.Angles(a, 0, 0), LeftShoulder = CFrame.Angles(a, 0, 0), Waist = CFrame.Angles(math.rad(-15 * s), 0, 0) }
	elseif action == "Water" or action == "Spray" or action == "Fertilize" then
		return { RightShoulder = CFrame.Angles(math.rad(-70), 0, math.rad(-20 * s)), Waist = CFrame.Angles(math.rad(-10 * s), 0, 0) }
	elseif action == "Harvest" or action == "Prune" then
		return { RightShoulder = CFrame.Angles(math.rad(-60), math.rad(40 * swing), 0), Waist = CFrame.Angles(math.rad(-25 * s), math.rad(10 * swing), 0) }
	elseif action == "Plant" or action == "Pick" then
		return { RightShoulder = CFrame.Angles(math.rad(-50 * s), 0, 0), Waist = CFrame.Angles(math.rad(-40 * s), 0, 0) }
	elseif action == "Cast" then
		local back = if t < 0.35 then t / 0.35 else math.max(0, 1 - (t - 0.35) / 0.3)
		return { RightShoulder = CFrame.Angles(math.rad(-170 * back - 40 * (1 - back)), 0, 0) }
	elseif action == "Catch" then
		return { RightShoulder = CFrame.Angles(math.rad(-120 * s), 0, 0), LeftShoulder = CFrame.Angles(math.rad(-120 * s), 0, 0) }
	elseif action == "Net" then
		return { RightShoulder = CFrame.Angles(math.rad(-100), math.rad(-70 * swing), 0), Waist = CFrame.Angles(0, math.rad(20 * swing), 0) }
	elseif action == "Pet" then
		return { RightShoulder = CFrame.Angles(math.rad(-45), 0, math.rad(15 * swing)), Waist = CFrame.Angles(math.rad(-30 * s), 0, 0) }
	elseif action == "Eat" then
		return { RightShoulder = CFrame.Angles(math.rad(-110 * s), 0, math.rad(-30 * s)) }
	end
	return {}
end

-- Looping poses (emotes); t is seconds.
local function emotePose(pose: string, t: number): { [string]: CFrame }
	if pose == "Wave" then
		return { RightShoulder = CFrame.Angles(math.rad(-160), 0, math.rad(20 * math.sin(t * 8))) }
	elseif pose == "Cheer" or pose == "HarvestDance" then
		local b = math.sin(t * 6)
		return { RightShoulder = CFrame.Angles(math.rad(-160 + 20 * b), 0, 0), LeftShoulder = CFrame.Angles(math.rad(-160 - 20 * b), 0, 0), Waist = CFrame.Angles(0, math.rad(15 * b), 0) }
	elseif pose == "Think" then
		return { RightShoulder = CFrame.Angles(math.rad(-120), 0, math.rad(-40)), Neck = CFrame.Angles(math.rad(10), 0, math.rad(8)) }
	elseif pose == "Bow" or pose == "TipHat" then
		return { Waist = CFrame.Angles(math.rad(-35), 0, 0), RightShoulder = CFrame.Angles(math.rad(-40), 0, 0) }
	elseif pose == "Point" then
		return { RightShoulder = CFrame.Angles(math.rad(-90), 0, 0) }
	elseif pose == "Clap" then
		local c = math.sin(t * 14) * 0.3
		return { RightShoulder = CFrame.Angles(math.rad(-80), math.rad(30 + c * 30), 0), LeftShoulder = CFrame.Angles(math.rad(-80), math.rad(-30 - c * 30), 0) }
	elseif pose == "Scarecrow" then
		return { RightShoulder = CFrame.Angles(0, 0, math.rad(-90)), LeftShoulder = CFrame.Angles(0, 0, math.rad(90)), Neck = CFrame.Angles(0, 0, math.rad(15)) }
	elseif pose == "Yodel" then
		return { RightShoulder = CFrame.Angles(math.rad(-130), 0, math.rad(-30)), Neck = CFrame.Angles(math.rad(-20 + 5 * math.sin(t * 5)), 0, 0) }
	end
	return {}
end

local function applyOverlay(rig: Rig, overlay: { [string]: CFrame })
	for name, cf in overlay do
		local joint = (rig.Joints :: any)[name]
		if joint then
			if not rig.R15 and (name == "RightShoulder" or name == "LeftShoulder") then
				-- R6 shoulders rotate about X differently.
				local x, y, z = cf:ToEulerAnglesXYZ()
				cf = CFrame.Angles(0, 0, if name == "RightShoulder" then -x else x) * CFrame.Angles(z, y, 0)
			end
			joint.Transform = joint.Transform * cf
		end
	end
end

-- Fishing line -----------------------------------------------------------------------------------------------------------

local function updateLine(rig: Rig)
	local target = rig.Character:GetAttribute("Bobber")
	if typeof(target) ~= "Vector3" then
		if rig.Bobber then
			rig.Bobber:Destroy()
			rig.Bobber = nil
		end
		return
	end
	if not rig.Bobber then
		local bobber = Instance.new("Part")
		bobber.Name = "Bobber"
		bobber.Shape = Enum.PartType.Ball
		bobber.Size = Vector3.new(0.6, 0.6, 0.6)
		bobber.Color = Color3.fromRGB(230, 60, 50)
		bobber.Anchored = true
		bobber.CanCollide = false
		bobber.CanQuery = false
		bobber.Parent = workspace
		local att = Instance.new("Attachment")
		att.Parent = bobber
		local beam = Instance.new("Beam")
		beam.Width0 = 0.04
		beam.Width1 = 0.04
		beam.Color = ColorSequence.new(Color3.fromRGB(240, 240, 240))
		beam.FaceCamera = true
		beam.Segments = 12
		beam.CurveSize0 = -2
		beam.Attachment1 = att
		beam.Parent = bobber
		rig.Bobber = bobber
		rig.Line = beam
	end
	local tip = rig.Held and rig.Held:FindFirstChild("LineOrigin", true)
	if rig.Line then
		rig.Line.Attachment0 = if tip and tip:IsA("Attachment") then tip else nil
	end
	local bobber = rig.Bobber :: BasePart
	local bite = rig.Character:GetAttribute("Bite")
	local dip = if bite then math.abs(math.sin(os.clock() * 12)) * 0.4 else math.sin(os.clock() * 2) * 0.08
	bobber.Position = target - Vector3.new(0, dip, 0)
end

-- Lifecycle ---------------------------------------------------------------------------------------------------------------

local function attach(character: Model)
	if rigs[character] then
		return
	end
	character:WaitForChild("HumanoidRootPart", 10)
	local joints, r15 = findJoints(character)
	local rig: Rig = {
		Character = character,
		Joints = joints,
		Held = nil,
		HeldKey = "",
		Vehicle = nil,
		Mount = nil,
		Companion = nil,
		Action = nil,
		ActionStart = 0,
		Line = nil,
		Bobber = nil,
		R15 = r15,
	}
	rigs[character] = rig
	local function refresh()
		updateHeld(rig)
		updateVehicle(rig)
		updateCompanion(rig)
	end
	character.AttributeChanged:Connect(function(name)
		if name == "Act" then
			local act = character:GetAttribute("Act")
			local action = type(act) == "string" and string.match(act, "^(%a+)@")
			if action then
				rig.Action = action
				rig.ActionStart = os.clock()
			end
		elseif name == "Held" or name == "HeldTier" or name == "Vehicle" or name == "Riding" or name == "Companion" then
			refresh()
		end
	end)
	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			for _, m in { rig.Held, rig.Vehicle, rig.Mount, rig.Companion, rig.Bobber } do
				if m then
					m:Destroy()
				end
			end
			rigs[character] = nil
		end
	end)
	refresh()
end

-- Play an action locally right away (the server's Act echo will match).
function AnimationController.Play(action: string)
	local character = Players.LocalPlayer.Character
	local rig = character and rigs[character]
	if rig then
		rig.Action = action
		rig.ActionStart = os.clock()
	end
end

function AnimationController.Start()
	local function onPlayer(p: Player)
		if p.Character then
			task.spawn(attach, p.Character)
		end
		p.CharacterAdded:Connect(function(character)
			task.spawn(attach, character)
		end)
	end
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
	Players.PlayerAdded:Connect(onPlayer)
	C.State.Watch("Cosmetics", function()
		for _, rig in rigs do
			rig.HeldKey = ""
			updateHeld(rig)
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		local camPos = workspace.CurrentCamera.CFrame.Position
		for character, rig in rigs do
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and (root.Position - camPos).Magnitude < 250 then
				if rig.Action then
					local duration = ACTION_TIME[rig.Action] or 0.5
					local t = (now - rig.ActionStart) / duration
					if t >= 1 then
						rig.Action = nil
					else
						applyOverlay(rig, actionPose(rig.Action, t))
					end
				end
				local pose = character:GetAttribute("Pose")
				if type(pose) == "string" and not rig.Action then
					applyOverlay(rig, emotePose(pose, now))
				end
				if rig.Companion then
					local offset = root.CFrame * CFrame.new(3, -2.6, 2.5)
					local current = rig.Companion:GetPivot()
					local target = CFrame.new(offset.Position) * root.CFrame.Rotation
					if rig.Companion:GetAttribute("Kind") == "owl" then
						target = root.CFrame * CFrame.new(1.2, 1.6, 0)
					end
					rig.Companion:PivotTo(current:Lerp(target, math.min(1, dt * 5)))
				end
				updateLine(rig)
			end
		end
	end)
end

return AnimationController

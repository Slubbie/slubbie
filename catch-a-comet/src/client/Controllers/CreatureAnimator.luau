-- Brings creatures to life on the client: idle movement by archetype
-- (float, hop, swim, flutter, prowl, waddle, soar, coil), secondary motion
-- (wings, tails, orbiting rings, pulses), blinking, colour shimmer for
-- special mutations, and turning to look at nearby players.
--
-- One shared update loop for every creature. Distant creatures update less
-- often and creatures beyond the graphics preset's range don't animate at
-- all. Only the client's copy moves; the server's models never change.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CreatureAnimator = {}

type MotionPart = {
	Part: BasePart,
	Weld: Weld?,
	Base: CFrame,
	Kind: string,
	Axis: string,
	Speed: number,
	Amount: number,
	Phase: number,
	Mesh: SpecialMesh?,
	BaseScale: Vector3,
}

export type Record = {
	Model: Model,
	Root: BasePart,
	Base: CFrame,
	Idle: string,
	Phase: number,
	Motions: { MotionPart },
	Eyes: { MotionPart },
	Cycle: string?,
	CycleParts: { BasePart },
	CycleColors: { Color3 },
	NextBlink: number,
	BlinkUntil: number,
	Frame: number,
	Yaw: number,
}

local controllers: { [string]: any } = {}
local records: { [Model]: Record } = {}

local function axisAngles(axis: string, angle: number): CFrame
	if axis == "X" then
		return CFrame.Angles(angle, 0, 0)
	elseif axis == "Z" then
		return CFrame.Angles(0, 0, angle)
	end
	return CFrame.Angles(0, angle, 0)
end

-- Starts animating a creature model. `base` is where its feet rest.
function CreatureAnimator.Track(model: Model, base: CFrame?): Record?
	local existing = records[model]
	if existing then
		return existing
	end
	local root = model.PrimaryPart
	if not root then
		return nil
	end
	local record: Record = {
		Model = model,
		Root = root,
		Base = base or root.CFrame,
		Idle = (model:GetAttribute("Idle") :: string?) or "Float",
		Phase = math.random() * 10,
		Motions = {},
		Eyes = {},
		Cycle = model:GetAttribute("ColorCycle") :: string?,
		CycleParts = {},
		CycleColors = {},
		NextBlink = os.clock() + 1 + math.random() * 4,
		BlinkUntil = 0,
		Frame = math.random(1, 3),
		Yaw = 0,
	}
	if model:GetAttribute("Rarity") == "Mythic" and not record.Cycle then
		record.Cycle = "Mythic"
	end
	for _, part in model:GetChildren() do
		if not part:IsA("BasePart") then
			continue
		end
		local kind = part:GetAttribute("Motion") :: string?
		if kind then
			local weld = part:FindFirstChild("RigWeld") :: Weld?
			local mesh = part:FindFirstChildOfClass("SpecialMesh")
			local motion: MotionPart = {
				Part = part,
				Weld = weld,
				Base = if weld then weld.C0 else CFrame.identity,
				Kind = kind,
				Axis = (part:GetAttribute("MotionAxis") :: string?) or "Y",
				Speed = (part:GetAttribute("MotionSpeed") :: number?) or 1,
				Amount = (part:GetAttribute("MotionAmount") :: number?) or 0,
				Phase = (part:GetAttribute("MotionPhase") :: number?) or 0,
				Mesh = mesh,
				BaseScale = if mesh then mesh.Scale else Vector3.one,
			}
			if kind == "Blink" then
				table.insert(record.Eyes, motion)
			else
				table.insert(record.Motions, motion)
			end
		end
		if record.Cycle then
			local role = part:GetAttribute("Role")
			if role == "Primary" or role == "Glow" or role == "AccentGlow" or role == "Secondary" then
				table.insert(record.CycleParts, part)
				table.insert(record.CycleColors, part.Color)
			end
		end
	end
	records[model] = record
	return record
end

function CreatureAnimator.Untrack(model: Model)
	records[model] = nil
end

function CreatureAnimator.SetBase(model: Model, base: CFrame)
	local record = records[model]
	if record then
		record.Base = base
	end
end

local function idleOffset(record: Record, t: number): CFrame
	local p = t + record.Phase
	local idle = record.Idle
	if idle == "Hop" then
		local h = math.max(0, math.sin(p * 2.6)) ^ 2 * 0.7
		return CFrame.new(0, h, 0)
	elseif idle == "Swim" then
		return CFrame.new(0, 0.3 * math.sin(p * 1.3), 0)
			* CFrame.Angles(math.rad(4 * math.sin(p * 1.3)), 0, math.rad(5 * math.sin(p * 1.3 + 1)))
	elseif idle == "Flutter" then
		return CFrame.new(0, 0.25 * math.sin(p * 4), 0) * CFrame.Angles(0, math.rad(10 * math.sin(p * 0.6)), 0)
	elseif idle == "Prowl" then
		return CFrame.new(0, 0.05 * math.sin(p * 2), 0)
	elseif idle == "Waddle" then
		return CFrame.new(0, math.abs(math.sin(p * 3)) * 0.1, 0) * CFrame.Angles(0, 0, math.rad(6 * math.sin(p * 3)))
	elseif idle == "Soar" then
		return CFrame.new(0, 0.5 * math.sin(p), 0)
			* CFrame.Angles(math.rad(3 * math.sin(p * 0.9)), 0, math.rad(8 * math.sin(p * 0.7)))
	elseif idle == "Coil" then
		return CFrame.new(0, 0.3 * math.sin(p * 1.2), 0) * CFrame.Angles(0, p * 0.15, 0)
	end
	return CFrame.new(0, 0.35 * math.sin(p * 1.6), 0) * CFrame.Angles(0, math.rad(6 * math.sin(p * 0.5)), 0)
end

local function nearestPlayerYaw(record: Record): number?
	local base = record.Base
	local best, bestDistance = nil, 16
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local d = (root.Position - base.Position).Magnitude
			if d < bestDistance then
				best, bestDistance = root, d
			end
		end
	end
	if not best then
		return nil
	end
	local localDir = base:PointToObjectSpace(best.Position)
	local yaw = math.atan2(-localDir.X, -localDir.Z)
	return math.clamp(yaw, -math.rad(60), math.rad(60))
end

local function animate(record: Record, t: number, dt: number, detail: boolean)
	local offset = idleOffset(record, t)
	if record.Idle ~= "Coil" and record.Idle ~= "Soar" then
		local target = nearestPlayerYaw(record) or 0
		record.Yaw += (target - record.Yaw) * math.min(dt * 3, 1)
		offset = CFrame.Angles(0, record.Yaw, 0) * offset
	end
	record.Root.CFrame = record.Base * offset

	for _, motion in record.Motions do
		local kind = motion.Kind
		local weld = motion.Weld
		if kind == "Spin" and weld then
			weld.C0 = motion.Base * axisAngles(motion.Axis, t * motion.Speed)
		elseif kind == "Flap" and weld then
			weld.C0 = motion.Base
				* axisAngles(motion.Axis, math.rad(motion.Amount) * math.sin(t * motion.Speed + motion.Phase))
		elseif kind == "Bob" and weld then
			weld.C0 = motion.Base * CFrame.new(0, motion.Amount * math.sin(t * motion.Speed + motion.Phase), 0)
		elseif kind == "Pulse" and motion.Mesh then
			local s = 1 + motion.Amount * (0.5 + 0.5 * math.sin(t * motion.Speed))
			motion.Mesh.Scale = motion.BaseScale * Vector3.new(s, 1, s)
			motion.Part.Transparency = 0.5 + 0.4 * (s - 1) / math.max(motion.Amount, 0.01)
		end
	end

	-- Blink: squash the eyes for a moment every few seconds.
	local clock = os.clock()
	if clock >= record.NextBlink then
		record.BlinkUntil = clock + 0.12
		record.NextBlink = clock + 2.5 + math.random() * 4
	end
	local closed = clock < record.BlinkUntil
	for _, eye in record.Eyes do
		if eye.Mesh then
			eye.Mesh.Scale = if closed then eye.BaseScale * Vector3.new(1, 0.12, 1) else eye.BaseScale
		end
	end

	if detail and record.Cycle then
		for i, part in record.CycleParts do
			local original = record.CycleColors[i]
			if record.Cycle == "Prismatic" or record.Cycle == "Mythic" then
				local hue = (t * 0.08 + i * 0.03) % 1
				local amount = if record.Cycle == "Mythic" then 0.35 else 0.55
				part.Color = original:Lerp(Color3.fromHSV(hue, 0.5, 1), amount)
			elseif record.Cycle == "Aurora" then
				local wave = 0.5 + 0.5 * math.sin(t * 0.7 + i * 0.4)
				part.Color = original:Lerp(Color3.fromRGB(156, 245, 216):Lerp(Color3.fromRGB(232, 166, 255), wave), 0.3)
			end
		end
	end
end

local function onAdded(model: Instance)
	if model:IsA("Model") then
		CreatureAnimator.Track(model)
	end
end

function CreatureAnimator.Init(registry: { [string]: any })
	controllers = registry
end

function CreatureAnimator.Start()
	for _, model in CollectionService:GetTagged("CreatureDisplay") do
		onAdded(model)
	end
	CollectionService:GetInstanceAddedSignal("CreatureDisplay"):Connect(onAdded)
	CollectionService:GetInstanceRemovedSignal("CreatureDisplay"):Connect(function(model)
		if model:IsA("Model") then
			records[model] = nil
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		local camera = Workspace.CurrentCamera
		local eye = camera.CFrame.Position
		local preset = controllers.SettingsController.Quality()
		local t = os.clock()
		for model, record in records do
			if not model.Parent or not record.Root.Parent then
				records[model] = nil
				continue
			end
			local distance = (record.Base.Position - eye).Magnitude
			if distance > preset.CreatureAnimDistance then
				continue
			end
			record.Frame += 1
			-- Nearby creatures every frame, distant ones every third frame.
			if distance > 45 and record.Frame % 3 ~= 0 then
				continue
			end
			animate(record, t, if distance > 45 then dt * 3 else dt, distance <= preset.CreatureDetailDistance)
		end
	end)
end

return CreatureAnimator

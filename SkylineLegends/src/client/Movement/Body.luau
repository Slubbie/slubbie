-- Direct control of the character body for moves the Humanoid can't do:
-- holding on (ledges, climbing, ziplines), scripted paths (vaults, mantles,
-- pulls) and collision posture (standing / low / phasing).
--
-- While held or scripted the Humanoid is PlatformStanded and the root is
-- placed every frame after physics, so motion is exact and replicates
-- smoothly to other players.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MathUtil = require(ReplicatedStorage.Shared.Util.MathUtil)
local Tags = require(ReplicatedStorage.Shared.Tags)

local Body = {}

local humanoid: Humanoid? = nil
local root: BasePart? = nil
local parts: { BasePart } = {}
local group = Tags.Groups.Players
local holding = false

export type Path = {
	From: CFrame,
	Control: Vector3,
	To: CFrame,
	Duration: number,
	Elapsed: number,
	Exit: Vector3,
	Kind: string,
}

local path: Path? = nil
local finished: Path? = nil -- the path that most recently completed

function Body.Attach(newCharacter: Model?)
	parts = {}
	holding = false
	path = nil
	group = Tags.Groups.Players
	if not newCharacter then
		humanoid, root = nil, nil
		return
	end
	humanoid = newCharacter:FindFirstChildOfClass("Humanoid")
	root = newCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
	for _, name in { "HumanoidRootPart", "Torso", "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg" } do
		local part = newCharacter:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(parts, part)
		end
	end
end

-- Collision posture: "Players" (standing), "PlayersLow" (crouch/slide), "PlayersPhase" (scripted).
function Body.SetGroup(name: string)
	if name == group then
		return
	end
	group = name
	for _, part in parts do
		part.CollisionGroup = name
	end
end

function Body.Group(): string
	return group
end

function Body.IsHolding(): boolean
	return holding
end

function Body.BeginHold()
	local h = humanoid
	if h and not holding then
		holding = true
		h.PlatformStand = true
		h.AutoRotate = false
	end
end

-- Place the root exactly, with a velocity hint for animation and replication.
function Body.Place(cframe: CFrame, velocity: Vector3?)
	local r = root
	if not r then
		return
	end
	r.CFrame = cframe
	r.AssemblyLinearVelocity = velocity or Vector3.zero
	r.AssemblyAngularVelocity = Vector3.zero
end

function Body.EndHold(velocity: Vector3?, state: Enum.HumanoidStateType?)
	local h, r = humanoid, root
	path = nil
	if not holding then
		if velocity and r then
			r.AssemblyLinearVelocity = velocity
		end
		return
	end
	holding = false
	if h then
		h.PlatformStand = false
		h.AutoRotate = true
		if h.Health > 0 then
			h:ChangeState(state or Enum.HumanoidStateType.Freefall)
		end
	end
	if r and velocity then
		r.AssemblyLinearVelocity = velocity
	end
end

-- Scripted paths -----------------------------------------------------------------------------

function Body.StartPath(
	kind: string,
	from: CFrame,
	control: Vector3,
	to: CFrame,
	duration: number,
	exit: Vector3,
	phase: boolean?
)
	Body.BeginHold()
	if phase then
		Body.SetGroup(Tags.Groups.PlayersPhase)
	end
	finished = nil
	path = {
		From = from,
		Control = control,
		To = to,
		Duration = math.max(duration, 0.05),
		Elapsed = 0,
		Exit = exit,
		Kind = kind,
	}
end

function Body.PathKind(): string?
	return if path then path.Kind else nil
end

function Body.PathAlpha(): number
	return if path then math.clamp(path.Elapsed / path.Duration, 0, 1) else 0
end

-- Advance the scripted path. Returns true when it has finished.
function Body.StepPath(dt: number): boolean
	local p = path
	if not p then
		return true
	end
	p.Elapsed += dt
	local alpha = math.clamp(p.Elapsed / p.Duration, 0, 1)
	local eased = MathUtil.Smooth(alpha)
	local position = MathUtil.Bezier(p.From.Position, p.Control, p.To.Position, eased)
	local ahead = MathUtil.Bezier(p.From.Position, p.Control, p.To.Position, math.min(eased + 0.05, 1))
	local velocity = (ahead - position) / math.max(p.Duration * 0.05, 1e-3)
	local rotation = p.From.Rotation:Lerp(p.To.Rotation, eased)
	Body.Place(CFrame.new(position) * rotation, velocity)
	if alpha >= 1 then
		finished = p
		path = nil
		return true
	end
	return false
end

function Body.PathExit(): Vector3
	return if path then path.Exit else Vector3.zero
end

-- Kind and exit velocity of the path that just completed.
function Body.Finished(): (string?, Vector3)
	local p = finished
	if not p then
		return nil, Vector3.zero
	end
	return p.Kind, p.Exit
end

return Body

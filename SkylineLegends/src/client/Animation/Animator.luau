-- Procedural animation for every R6 rig: your runner, other players, ghosts
-- and Guild NPCs.
--
-- Each rig gets a target pose every frame from its movement state (run cycles
-- that follow real speed, wall-run leans toward the wall, hanging, climbing,
-- balancing with arms out, vault and mantle arcs that follow the scripted
-- path...). Poses blend smoothly; flips, rolls and landing squash are layered
-- on top. Everything is written to Motor6D.Transform, so nothing needs to be
-- uploaded and every client animates everyone locally from replicated state.
--
-- Pose space: rotations are in the torso's frame (X right, Y up, -Z forward).
--   arms/legs: +X angle swings the limb forward, +Z (times side) swings it outward
--   root: lean > 0 tips the body forward

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MathUtil = require(ReplicatedStorage.Shared.Util.MathUtil)
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Tags = require(ReplicatedStorage.Shared.Tags)

local Controller = require(script.Parent.Parent.Movement.Controller)

local player = Players.LocalPlayer
local rad = math.rad
local sin, cos = math.sin, math.cos

local Animator = {}

-- (model, side, speed) on every footfall of a running rig. Audio listens.
Animator.Footstep = Signal.new()

local JOINTS = {
	Root = { Part = "HumanoidRootPart", Name = "RootJoint" },
	Neck = { Part = "Torso", Name = "Neck" },
	RightArm = { Part = "Torso", Name = "Right Shoulder" },
	LeftArm = { Part = "Torso", Name = "Left Shoulder" },
	RightLeg = { Part = "Torso", Name = "Right Hip" },
	LeftLeg = { Part = "Torso", Name = "Left Hip" },
}
local JOINT_NAMES = { "Root", "Neck", "RightArm", "LeftArm", "RightLeg", "LeftLeg" }

type Pose = { [string]: CFrame }
type Overlay = { Start: number, Duration: number, Axis: string, Turns: number, Lift: number, Tuck: number }
type Rig = {
	Model: Model,
	Kind: string, -- "Local" | "Player" | "Ghost" | "NPC"
	Root: BasePart,
	Motors: { [string]: Motor6D },
	Basis: { [string]: CFrame },
	Pose: Pose,
	Phase: number,
	LastStep: number,
	State: string,
	StateStart: number,
	Flip: Overlay?,
	Squash: number,
	SquashVel: number,
	Emote: string?,
	EmoteStart: number,
	EmoteStamp: any,
	LastVelocity: Vector3,
	Accel: Vector3,
	Frame: number,
}

local rigs: { [Model]: Rig } = {}
local frameCount = 0

-- Helpers ------------------------------------------------------------------------------------------

local function angles(x: number, y: number, z: number): CFrame
	return CFrame.Angles(rad(x), rad(y), rad(z))
end

-- A limb rotation: forward swing, outward swing (mirrored per side), twist.
local function limb(side: number, forward: number, out: number?, twist: number?): CFrame
	return angles(forward, (twist or 0) * side, (out or 0) * side)
end

-- Root offset and lean (forward), yaw and roll (to the right).
local function body(y: number, lean: number, yaw: number?, roll: number?, x: number?, z: number?): CFrame
	return CFrame.new(x or 0, y, z or 0) * angles(-lean, yaw or 0, -(roll or 0))
end

local function head(pitch: number, yaw: number?, roll: number?): CFrame
	return angles(pitch, yaw or 0, roll or 0)
end

-- Rotation that points a hanging limb (rest direction -Y) along `direction` (torso space).
local function pointLimb(direction: Vector3): CFrame
	if direction.Magnitude < 1e-3 then
		return CFrame.identity
	end
	return MathUtil.RotationBetween(Vector3.new(0, -1, 0), direction.Unit)
end

local function neutral(): Pose
	return {
		Root = CFrame.identity,
		Neck = CFrame.identity,
		RightArm = CFrame.identity,
		LeftArm = CFrame.identity,
		RightLeg = CFrame.identity,
		LeftLeg = CFrame.identity,
	}
end

-- Inputs -----------------------------------------------------------------------------------------

type Input = {
	State: string,
	Velocity: Vector3,
	Aux: Vector3?,
	AuxNumber: number,
	Posture: string,
	PathKind: string?,
	PathAlpha: number,
	Grounded: boolean,
	Sprinting: boolean,
	AirTime: number,
	Look: Vector3?,
}

local function readInput(rig: Rig): Input
	if rig.Kind == "Local" then
		local info = Controller.Info
		local camera = workspace.CurrentCamera
		return {
			State = info.State,
			Velocity = info.Velocity,
			Aux = info.Aux,
			AuxNumber = info.Sway,
			Posture = info.Posture,
			PathKind = info.PathKind,
			PathAlpha = info.PathAlpha,
			Grounded = info.Grounded,
			Sprinting = info.Sprinting,
			AirTime = info.AirTime,
			Look = if camera then camera.CFrame.LookVector else nil,
		}
	end
	local model = rig.Model
	local state = model:GetAttribute("MS")
	local aux = model:GetAttribute("MA")
	local auxNumber = model:GetAttribute("MB")
	local velocity = model:GetAttribute("GV")
	if typeof(velocity) ~= "Vector3" then
		velocity = rig.Root.AssemblyLinearVelocity
	end
	local stateName = if type(state) == "string" then state else "Ground"
	return {
		State = stateName,
		Velocity = velocity,
		Aux = if typeof(aux) == "Vector3" then aux else nil,
		AuxNumber = if type(auxNumber) == "number" then auxNumber else 0,
		Posture = if stateName == "Slide" or stateName == "Crouch" then "Low" else "Stand",
		PathKind = if stateName == "Vault" or stateName == "Mantle" then stateName else nil,
		PathAlpha = math.clamp((os.clock() - rig.StateStart) / 0.35, 0, 1),
		Grounded = stateName == "Ground" or stateName == "Crouch" or stateName == "Slide" or stateName == "Roll",
		Sprinting = MathUtil.Flat(velocity).Magnitude > 24,
		AirTime = if stateName == "Air" then os.clock() - rig.StateStart else 0,
		Look = nil,
	}
end

-- Poses ------------------------------------------------------------------------------------------

local function idlePose(t: number): Pose
	local breathe = sin(t * 1.6)
	return {
		Root = body(breathe * 0.03, 1),
		Neck = head(breathe * 1.5 - 2),
		RightArm = limb(1, 4 + breathe * 2, 6),
		LeftArm = limb(-1, 2 - breathe * 2, 6),
		RightLeg = limb(1, 0, 3),
		LeftLeg = limb(-1, 0, 3),
	}
end

local function runPose(phase: number, speed: number, sprint: boolean, accel: number): Pose
	local k = math.clamp(speed / 28, 0.15, 1.25)
	local s, c = sin(phase), cos(phase)
	local legs = 22 + 34 * k
	local arms = (if sprint then 50 else 32) * k + 8
	local lean = 3 + 9 * k + math.clamp(accel * 0.25, -6, 10)
	local bob = -math.abs(c) * 0.22 * k
	return {
		Root = body(bob + 0.05, lean, s * 6 * k, 0),
		Neck = head(lean * 0.6 - 2, -s * 5 * k),
		RightArm = limb(1, -s * arms + (if sprint then 12 else 4), 6),
		LeftArm = limb(-1, s * arms + (if sprint then 12 else 4), 6),
		RightLeg = limb(1, s * legs + 4, 2),
		LeftLeg = limb(-1, -s * legs + 4, 2),
	}
end

local function crouchPose(phase: number, speed: number): Pose
	local k = math.clamp(speed / 10, 0, 1)
	local s = sin(phase)
	return {
		Root = body(-1.05, 16),
		Neck = head(10),
		RightArm = limb(1, 25 - s * 18 * k, 10),
		LeftArm = limb(-1, 25 + s * 18 * k, 10),
		RightLeg = limb(1, 62 + s * 22 * k, 4),
		LeftLeg = limb(-1, 18 - s * 22 * k, 4),
	}
end

local function slidePose(t: number): Pose
	local wobble = sin(t * 18) * 1.5
	return {
		Root = body(-1.75, -52, 0, 4),
		Neck = head(34),
		RightArm = limb(1, 55, 14),
		LeftArm = limb(-1, -28, 38 + wobble),
		RightLeg = limb(1, 46),
		LeftLeg = limb(-1, 14, 6),
	}
end

local function airPose(vy: number, speed: number, airTime: number, t: number): Pose
	local rising = math.clamp(vy / 50, -1, 1)
	local k = math.clamp(speed / 28, 0, 1)
	if rising > 0.1 then
		-- Take-off: stride split, arms driving up.
		return {
			Root = body(0, 6 + 8 * k),
			Neck = head(4),
			RightArm = limb(1, 70 * rising + 10, 18),
			LeftArm = limb(-1, -30 * k + 20, 22),
			RightLeg = limb(1, 55 + 15 * k, 2),
			LeftLeg = limb(-1, -25 * k - 5, 2),
		}
	end
	local fall = math.clamp(-vy / 90, 0, 1)
	local flail = math.clamp((airTime - 1.1) / 0.8, 0, 1)
	local f = sin(t * 14) * 35 * flail
	return {
		Root = body(0, 4 + 6 * k - 8 * fall),
		Neck = head(-6 * fall),
		RightArm = limb(1, 30 + f, 30 + 45 * fall),
		LeftArm = limb(-1, 30 - f, 30 + 45 * fall),
		RightLeg = limb(1, 22 - 10 * fall + f * 0.4, 4),
		LeftLeg = limb(-1, -8 + 16 * fall - f * 0.4, 4),
	}
end

local function wallRunPose(phase: number, wallRight: number): Pose
	local s = sin(phase)
	local wallArm = if wallRight > 0 then "RightArm" else "LeftArm"
	local freeArm = if wallRight > 0 then "LeftArm" else "RightArm"
	local pose = {
		Root = body(0, 10, 0, 20 * wallRight),
		Neck = head(0, 0, -10 * wallRight),
		RightLeg = limb(1, s * 48 + 6, 0),
		LeftLeg = limb(-1, -s * 48 + 6, 0),
	} :: Pose
	pose[wallArm] = limb(wallRight, 20, 72)
	pose[freeArm] = limb(-wallRight, s * 45 * wallRight + 15, 14)
	return pose
end

local function wallClimbPose(phase: number): Pose
	local s = sin(phase)
	return {
		Root = body(0, -14),
		Neck = head(28),
		RightArm = limb(1, 150 + s * 25, 10),
		LeftArm = limb(-1, 150 - s * 25, 10),
		RightLeg = limb(1, 50 + s * 40),
		LeftLeg = limb(-1, 50 - s * 40),
	}
end

local function hangPose(t: number, lateral: number): Pose
	local sway = sin(t * 2.2) * 4
	local shimmy = sin(t * 10) * 14 * math.clamp(math.abs(lateral) / 6, 0, 1)
	return {
		Root = body(-0.2, -4 + sway * 0.2),
		Neck = head(18),
		RightArm = limb(1, 172 + shimmy, -6),
		LeftArm = limb(-1, 172 - shimmy, -6),
		RightLeg = limb(1, 8 + sway, 4),
		LeftLeg = limb(-1, -4 - sway, 4),
	}
end

local function climbPose(phase: number, moving: boolean): Pose
	local s = if moving then sin(phase) else sin(phase) * 0.15
	return {
		Root = body(0, 6),
		Neck = head(16),
		RightArm = limb(1, 150 + s * 28, 8),
		LeftArm = limb(-1, 150 - s * 28, 8),
		RightLeg = limb(1, 30 - s * 30, 6),
		LeftLeg = limb(-1, 30 + s * 30, 6),
	}
end

local function balancePose(phase: number, speed: number, sway: number): Pose
	local s = sin(phase) * math.clamp(speed / 12, 0, 1)
	local tilt = math.clamp(sway, -1, 1)
	return {
		Root = body(-0.15, 6, 0, tilt * 22),
		Neck = head(-8, 0, -tilt * 12),
		RightArm = limb(1, 8, 82 - tilt * 30),
		LeftArm = limb(-1, 8, 82 + tilt * 30),
		RightLeg = limb(1, s * 22, 0),
		LeftLeg = limb(-1, -s * 22, 0),
	}
end

local function zipPose(t: number, speed: number): Pose
	local k = math.clamp(speed / 40, 0, 1)
	local sway = sin(t * 3) * 3
	return {
		Root = body(-0.4, -6 - 8 * k + sway),
		Neck = head(10),
		RightArm = limb(1, 176, -8),
		LeftArm = limb(-1, 172, -8),
		RightLeg = limb(1, 26 + 12 * k, 4),
		LeftLeg = limb(-1, 18 + 12 * k, 4),
	}
end

local function swingPose(root: BasePart, anchor: Vector3?, velocity: Vector3, grapple: boolean): Pose
	local local_ = root.CFrame:VectorToObjectSpace(velocity)
	local forward = math.clamp(-local_.Z / 40, -1, 1)
	local toAnchor = if anchor then root.CFrame:VectorToObjectSpace(anchor - root.Position) else Vector3.new(0, 1, 0)
	local reach = pointLimb(toAnchor)
	local pose = {
		Root = body(0, -forward * 22),
		Neck = head(20),
		RightArm = reach,
		LeftArm = if grapple then limb(-1, 20 - forward * 25, 26) else reach,
		RightLeg = limb(1, 30 * forward + 12, 4),
		LeftLeg = limb(-1, 30 * forward + 4, 4),
	}
	return pose
end

local function pullPose(root: BasePart, target: Vector3?): Pose
	local toTarget = if target then root.CFrame:VectorToObjectSpace(target - root.Position) else Vector3.new(0, 0.5, -1)
	return {
		Root = body(0, 30),
		Neck = head(10),
		RightArm = pointLimb(toTarget),
		LeftArm = limb(-1, -40, 20),
		RightLeg = limb(1, -14),
		LeftLeg = limb(-1, -24),
	}
end

local function dashPose(): Pose
	return {
		Root = body(0, 28),
		Neck = head(18),
		RightArm = limb(1, -55, 16),
		LeftArm = limb(-1, -55, 16),
		RightLeg = limb(1, -18),
		LeftLeg = limb(-1, -34),
	}
end

local function stumblePose(t: number, elapsed: number): Pose
	local recover = math.clamp(elapsed / 0.5, 0, 1)
	local f = sin(t * 16) * 20 * (1 - recover)
	return {
		Root = body(-0.4 * (1 - recover), 32 * (1 - recover) + 6),
		Neck = head(-10),
		RightArm = limb(1, 70 + f, 30),
		LeftArm = limb(-1, 60 - f, 34),
		RightLeg = limb(1, 30 * (1 - recover)),
		LeftLeg = limb(-1, -20 * (1 - recover)),
	}
end

local function pathPose(kind: string?, alpha: number): Pose
	local arc = sin(alpha * math.pi)
	if kind == "Vault" then
		-- Speed vault: a hand on the obstacle, legs swinging over to the side.
		return {
			Root = body(-0.2, 10 * arc, 0, -34 * arc),
			Neck = head(-6),
			RightArm = limb(1, 30 - 20 * arc, 30),
			LeftArm = limb(-1, 40 + 10 * arc, -10 * arc),
			RightLeg = limb(1, 40 * arc, 50 * arc),
			LeftLeg = limb(-1, 30 * arc, -30 * arc),
		}
	elseif kind == "Step" then
		return {
			Root = body(0, 14 * arc),
			Neck = head(-4),
			RightArm = limb(1, 30 * arc, 18),
			LeftArm = limb(-1, -10 * arc, 18),
			RightLeg = limb(1, 75 * arc),
			LeftLeg = limb(-1, -10 * arc),
		}
	elseif kind == "Leap" then
		return {
			Root = body(0, -8),
			Neck = head(26),
			RightArm = limb(1, 172, -4),
			LeftArm = limb(-1, 172, -4),
			RightLeg = limb(1, 40 * arc),
			LeftLeg = limb(-1, 20 * arc),
		}
	elseif kind == "Pull" then
		return pathPose("Leap", alpha)
	end
	-- Mantle: arms push down while the knees come up.
	local push = 170 * (1 - alpha) + 20 * alpha
	return {
		Root = body(-0.3 * arc, 26 * arc),
		Neck = head(10 * (1 - alpha)),
		RightArm = limb(1, push, 8),
		LeftArm = limb(-1, push, 8),
		RightLeg = limb(1, 70 * arc),
		LeftLeg = limb(-1, 35 * arc),
	}
end

-- Emotes and victories (`e` = seconds since start). Return nil when finished.
local EMOTES: { [string]: { Loop: boolean, Duration: number, Pose: (e: number, t: number) -> Pose } } = {
	Wave = {
		Loop = false,
		Duration = 2.6,
		Pose = function(e)
			local p = idlePose(e)
			p.RightArm = limb(1, 10, 160 + sin(e * 11) * 18)
			p.Neck = head(4, -8)
			return p
		end,
	},
	Salute = {
		Loop = false,
		Duration = 2.2,
		Pose = function()
			local p = idlePose(0)
			p.Root = body(0.05, -3)
			p.RightArm = limb(1, 135, -48, 20)
			p.RightLeg = limb(1, 0, 1)
			p.LeftLeg = limb(-1, 0, 1)
			return p
		end,
	},
	Stretch = {
		Loop = false,
		Duration = 3.2,
		Pose = function(e)
			local side = sin(e * 2)
			return {
				Root = body(0, 0, 0, side * 14),
				Neck = head(10, 0, -side * 8),
				RightArm = limb(1, 175, -6 + side * 8),
				LeftArm = limb(-1, 175, -6 - side * 8),
				RightLeg = limb(1, 0, 8),
				LeftLeg = limb(-1, 0, 8),
			}
		end,
	},
	Cheer = {
		Loop = false,
		Duration = 2.4,
		Pose = function(e)
			local pump = math.abs(sin(e * 7))
			return {
				Root = body(pump * 0.25, -6),
				Neck = head(22),
				RightArm = limb(1, 150 + pump * 25, 20),
				LeftArm = limb(-1, 150 + pump * 25, 20),
				RightLeg = limb(1, 0, 6),
				LeftLeg = limb(-1, 0, 6),
			}
		end,
	},
	Clap = {
		Loop = false,
		Duration = 2.4,
		Pose = function(e)
			local clap = math.abs(sin(e * 9))
			local p = idlePose(e)
			p.RightArm = limb(1, 75, -20 + clap * 22)
			p.LeftArm = limb(-1, 75, -20 + clap * 22)
			return p
		end,
	},
	Bow = {
		Loop = false,
		Duration = 2.2,
		Pose = function(e)
			local a = math.clamp(e / 0.5, 0, 1) * math.clamp((2.2 - e) / 0.5, 0, 1)
			return {
				Root = body(0, 50 * a),
				Neck = head(-20 * a),
				RightArm = limb(1, 40 * a, -40 * a),
				LeftArm = limb(-1, -20 * a, 8),
				RightLeg = limb(1, 0),
				LeftLeg = limb(-1, 0),
			}
		end,
	},
	Sit = {
		Loop = true,
		Duration = 0,
		Pose = function(e)
			local breathe = sin(e * 1.4)
			return {
				Root = body(-1.95, -8),
				Neck = head(4 + breathe * 2),
				RightArm = limb(1, -26, 20),
				LeftArm = limb(-1, -26, 20),
				RightLeg = limb(1, 88, 6),
				LeftLeg = limb(-1, 86, 10),
			}
		end,
	},
	Flex = {
		Loop = false,
		Duration = 2.6,
		Pose = function(e)
			local pulse = sin(e * 6) * 4
			return {
				Root = body(0, -6),
				Neck = head(10, sin(e * 2) * 15),
				RightArm = limb(1, 20, 100 + pulse),
				LeftArm = limb(-1, 20, 100 + pulse),
				RightLeg = limb(1, 0, 10),
				LeftLeg = limb(-1, 0, 10),
			}
		end,
	},
	Dance = {
		Loop = true,
		Duration = 0,
		Pose = function(e)
			local beat = e * 2 * math.pi * 1.8
			local s = sin(beat)
			return {
				Root = body(math.abs(cos(beat)) * 0.25, 0, s * 12, s * 8, s * 0.3),
				Neck = head(6, -s * 10, s * 6),
				RightArm = limb(1, 60 + s * 70, 30),
				LeftArm = limb(-1, 60 - s * 70, 30),
				RightLeg = limb(1, math.max(s, 0) * 40, 8),
				LeftLeg = limb(-1, math.max(-s, 0) * 40, 8),
			}
		end,
	},
	Shrug = {
		Loop = false,
		Duration = 1.6,
		Pose = function(e)
			local a = math.clamp(e / 0.25, 0, 1) * math.clamp((1.6 - e) / 0.3, 0, 1)
			local p = idlePose(e)
			p.Root = body(0.12 * a, 0)
			p.RightArm = limb(1, 25 * a, 30 * a)
			p.LeftArm = limb(-1, 25 * a, 30 * a)
			p.Neck = head(0, 0, 12 * a)
			return p
		end,
	},
	Point = {
		Loop = false,
		Duration = 2.2,
		Pose = function(e)
			local p = idlePose(e)
			p.RightArm = limb(1, 92, 4)
			p.Neck = head(2)
			return p
		end,
	},
	Handstand = {
		Loop = true,
		Duration = 0,
		Pose = function(e)
			local wobble = sin(e * 3) * 4
			local up = math.clamp(e / 0.5, 0, 1)
			return {
				Root = CFrame.new(0, 1.2 * up, 0) * angles(180 * up + wobble, 0, 0),
				Neck = head(30),
				RightArm = limb(1, 180 * up, 12),
				LeftArm = limb(-1, 180 * up, 12),
				RightLeg = limb(1, wobble, 6),
				LeftLeg = limb(-1, -wobble, 6),
			}
		end,
	},
	Spin = {
		Loop = false,
		Duration = 2,
		Pose = function(e)
			local turns = math.clamp(e / 1.6, 0, 1)
			return {
				Root = body(0.2 * sin(turns * math.pi), 0, MathUtil.Smooth(turns) * 720),
				Neck = head(12),
				RightArm = limb(1, 10, 95),
				LeftArm = limb(-1, 10, 95),
				RightLeg = limb(1, 0, 10),
				LeftLeg = limb(-1, 0, 10),
			}
		end,
	},
	-- Idle poses for Guild NPCs
	Arms = {
		Loop = true,
		Duration = 0,
		Pose = function(e)
			local breathe = sin(e * 1.5)
			return {
				Root = body(breathe * 0.03, -2),
				Neck = head(2 + breathe, sin(e * 0.4) * 12),
				RightArm = limb(1, 70, -55, 10),
				LeftArm = limb(-1, 62, -50, 10),
				RightLeg = limb(1, 0, 5),
				LeftLeg = limb(-1, 0, 5),
			}
		end,
	},
	Bounce = {
		Loop = true,
		Duration = 0,
		Pose = function(e)
			local hop = math.abs(sin(e * 5))
			return {
				Root = body(hop * 0.35, 4),
				Neck = head(6, sin(e * 1.3) * 10),
				RightArm = limb(1, 30 + hop * 30, 20),
				LeftArm = limb(-1, 30 + hop * 30, 20),
				RightLeg = limb(1, hop * 10, 4),
				LeftLeg = limb(-1, hop * 10, 4),
			}
		end,
	},
	-- Victory animations
	FistPump = {
		Loop = false,
		Duration = 2.2,
		Pose = function(e)
			local pump = math.abs(sin(e * 6)) * math.clamp((2.2 - e) / 0.4, 0, 1)
			local p = idlePose(e)
			p.Root = body(pump * 0.15, -4)
			p.RightArm = limb(1, 120 + pump * 50, 15)
			p.Neck = head(18)
			return p
		end,
	},
	Backflip = {
		Loop = false,
		Duration = 1.4,
		Pose = function(e)
			local a = math.clamp((e - 0.15) / 0.75, 0, 1)
			local crouch = math.clamp(1 - math.abs(e - 0.12) / 0.12, 0, 1)
			local tuck = sin(a * math.pi)
			return {
				Root = CFrame.new(0, -0.6 * crouch + 3.2 * tuck, 0) * angles(MathUtil.Smooth(a) * 360, 0, 0),
				Neck = head(10),
				RightArm = limb(1, 120 * tuck + 20, 20),
				LeftArm = limb(-1, 120 * tuck + 20, 20),
				RightLeg = limb(1, 90 * tuck),
				LeftLeg = limb(-1, 90 * tuck),
			}
		end,
	},
	PointSky = {
		Loop = false,
		Duration = 2.4,
		Pose = function(e)
			local p = idlePose(e)
			p.RightArm = limb(1, 168, 12)
			p.Neck = head(34)
			p.Root = body(0, -8)
			return p
		end,
	},
	Kneel = {
		Loop = false,
		Duration = 3,
		Pose = function(e)
			local a = math.clamp(e / 0.4, 0, 1)
			return {
				Root = body(-1.25 * a, 8 * a),
				Neck = head(-24 * a),
				RightArm = limb(1, 30 * a, 6),
				LeftArm = limb(-1, 8, 6),
				RightLeg = limb(1, 88 * a),
				LeftLeg = limb(-1, -70 * a),
			}
		end,
	},
}

-- Rig management ---------------------------------------------------------------------------------

local function findMotors(model: Model): ({ [string]: Motor6D }?, { [string]: CFrame }?)
	local motors: { [string]: Motor6D } = {}
	local basis: { [string]: CFrame } = {}
	for key, joint in JOINTS do
		local part = model:FindFirstChild(joint.Part)
		local motor = part and part:FindFirstChild(joint.Name)
		if not motor or not motor:IsA("Motor6D") then
			return nil, nil
		end
		motors[key] = motor
		basis[key] = motor.C0.Rotation
	end
	return motors, basis
end

function Animator.Track(model: Model, kind: string)
	if rigs[model] then
		return
	end
	task.spawn(function()
		local root = model:WaitForChild("HumanoidRootPart", 10)
		model:WaitForChild("Torso", 10)
		for _, joint in JOINTS do
			local part = model:WaitForChild(joint.Part, 10)
			if part then
				part:WaitForChild(joint.Name, 10)
			end
		end
		if not root or not root:IsA("BasePart") or not model.Parent then
			return
		end
		local motors, basis = findMotors(model)
		if not motors or not basis then
			return
		end
		rigs[model] = {
			Model = model,
			Kind = kind,
			Root = root,
			Motors = motors,
			Basis = basis,
			Pose = neutral(),
			Phase = 0,
			LastStep = 0,
			State = "Ground",
			StateStart = os.clock(),
			Flip = nil,
			Squash = 0,
			SquashVel = 0,
			Emote = nil,
			EmoteStart = 0,
			EmoteStamp = nil,
			LastVelocity = Vector3.zero,
			Accel = Vector3.zero,
			Frame = math.random(0, 7),
		}
		model.AncestryChanged:Connect(function()
			if not model:IsDescendantOf(workspace) then
				rigs[model] = nil
			end
		end)
	end)
end

local function overlay(rig: Rig, axis: string, duration: number, turns: number, lift: number, tuck: number)
	rig.Flip = { Start = os.clock(), Duration = duration, Axis = axis, Turns = turns, Lift = lift, Tuck = tuck }
end

-- One-shot reactions to actions (local controller or relayed from the server).
local function onAction(rig: Rig, action: string)
	if action == "DoubleJump" then
		overlay(rig, "X", 0.42, 1, 0.4, 1)
	elseif action == "WallJump" then
		overlay(rig, "Y", 0.32, 0.5, 0, 0.3)
	elseif action == "SlideJump" then
		overlay(rig, "X", 0.5, 0, 0, 0.6)
	elseif action == "GrappleRelease" then
		if math.random() < 0.5 then
			overlay(rig, "X", 0.55, 1, 0.3, 1)
		else
			overlay(rig, "Z", 0.5, 1, 0.2, 0.8)
		end
	elseif action == "Bounce" or action == "Launch" then
		overlay(rig, "X", 0.6, 1, 0.5, 1)
	end
	if rig.Emote then
		rig.Emote = nil
	end
end

local function setLanding(rig: Rig, impact: number)
	rig.SquashVel -= math.clamp(impact / 25, 0, 6)
end

-- Per-frame --------------------------------------------------------------------------------------

local function targetPose(rig: Rig, input: Input, t: number, dt: number): Pose
	local state = input.State
	local velocity = input.Velocity
	local flat = MathUtil.Flat(velocity)
	local speed = flat.Magnitude
	local root = rig.Root

	-- Emotes play only while standing still on the ground.
	if rig.Emote then
		local def = EMOTES[rig.Emote]
		local elapsed = t - rig.EmoteStart
		if not def or state ~= "Ground" or speed > 3 or (not def.Loop and elapsed > def.Duration) then
			rig.Emote = nil
		else
			return def.Pose(elapsed, t)
		end
	end

	-- Gait phase follows distance travelled.
	local function advance(stride: number, minRate: number?)
		local rate = math.max(speed / stride, minRate or 0)
		local before = rig.Phase
		rig.Phase += rate * math.pi * 2 * dt
		if input.Grounded and speed > 2 then
			-- A footfall at each half cycle.
			if math.floor(before / math.pi) ~= math.floor(rig.Phase / math.pi) then
				local side = if math.floor(rig.Phase / math.pi) % 2 == 0 then 1 else -1
				Animator.Footstep:Fire(rig.Model, side, speed)
			end
		end
		if rig.Phase > 1e4 then
			rig.Phase -= math.pi * 2 * 1000
		end
	end

	if state == "Ground" then
		if speed < 1.5 then
			return idlePose(t)
		end
		advance(9)
		local accel = rig.Root.CFrame:VectorToObjectSpace(rig.Accel)
		return runPose(rig.Phase, speed, input.Sprinting, -accel.Z)
	elseif state == "Crouch" then
		advance(5)
		return crouchPose(rig.Phase, speed)
	elseif state == "Slide" then
		return slidePose(t)
	elseif state == "Roll" then
		local p = airPose(0, speed, 0, t)
		p.RightArm = limb(1, 90, 10)
		p.LeftArm = limb(-1, 90, 10)
		p.RightLeg = limb(1, 95)
		p.LeftLeg = limb(-1, 95)
		p.Root = body(-1, 0)
		return p
	elseif state == "Stumble" then
		return stumblePose(t, t - rig.StateStart)
	elseif state == "Air" then
		return airPose(velocity.Y, speed, input.AirTime, t)
	elseif state == "WallRun" then
		advance(8, 3.2)
		local normal = input.Aux or Vector3.xAxis
		local wallRight = if root.CFrame.RightVector:Dot(-normal) > 0 then 1 else -1
		return wallRunPose(rig.Phase, wallRight)
	elseif state == "WallClimb" then
		rig.Phase += 3.4 * math.pi * 2 * dt
		return wallClimbPose(rig.Phase)
	elseif state == "Ledge" then
		local lateral = root.CFrame:VectorToObjectSpace(velocity).X
		return hangPose(t, lateral)
	elseif state == "Climb" then
		local moving = velocity.Magnitude > 1
		rig.Phase += (velocity.Magnitude / 5) * math.pi * 2 * dt
		return climbPose(rig.Phase, moving)
	elseif state == "Balance" then
		advance(6)
		return balancePose(rig.Phase, speed, input.AuxNumber)
	elseif state == "Zipline" then
		return zipPose(t, velocity.Magnitude)
	elseif state == "Swing" then
		local grapple = rig.Kind == "Local" and Controller.Info.GrappleTarget ~= nil
		return swingPose(root, input.Aux, velocity, grapple)
	elseif state == "Pull" then
		if input.PathKind then
			return pathPose("Pull", input.PathAlpha)
		end
		return pullPose(root, input.Aux)
	elseif state == "Dash" then
		return dashPose()
	elseif state == "Vault" or state == "Mantle" then
		return pathPose(input.PathKind or (if state == "Vault" then "Vault" else "Mantle"), input.PathAlpha)
	elseif state == "Emote" or state == "Idle" then
		return idlePose(t)
	end
	return idlePose(t)
end

local function blendSpeed(state: string): number
	if state == "Vault" or state == "Mantle" or state == "Dash" or state == "Roll" then
		return 26
	elseif state == "Air" then
		return 10
	elseif state == "Ledge" or state == "Climb" or state == "Zipline" then
		return 16
	end
	return 14
end

local function apply(rig: Rig, pose: Pose)
	for _, key in JOINT_NAMES do
		local motor = rig.Motors[key]
		local basis = rig.Basis[key]
		local cf = pose[key]
		if motor and basis and cf then
			motor.Transform = basis:Inverse() * cf * basis
		end
	end
end

local function stepRig(rig: Rig, t: number, dt: number)
	local input = readInput(rig)
	if input.State ~= rig.State then
		local old = rig.State
		rig.State = input.State
		rig.StateStart = os.clock()
		if input.State == "Roll" then
			overlay(rig, "X", 0.42, 1, 0, 1)
		elseif rig.Kind ~= "Local" and (old == "Air" or old == "WallRun") and (input.State == "Ground" or input.State == "Slide") then
			setLanding(rig, math.max(-rig.LastVelocity.Y, 0))
		end
	end
	-- Smoothed acceleration for lean.
	local velocity = input.Velocity
	rig.Accel = rig.Accel:Lerp((velocity - rig.LastVelocity) / math.max(dt, 1e-3), 1 - math.exp(-6 * dt))
	rig.LastVelocity = velocity

	local target = targetPose(rig, input, t, dt)
	local alpha = 1 - math.exp(-blendSpeed(input.State) * dt)
	local pose = rig.Pose
	for _, key in JOINT_NAMES do
		pose[key] = pose[key]:Lerp(target[key] or CFrame.identity, alpha)
	end

	-- Head looks where the camera looks (local runner, on the ground).
	local final = table.clone(pose)
	if input.Look and (input.State == "Ground" or input.State == "Crouch" or input.State == "Air") and not rig.Emote then
		local localLook = rig.Root.CFrame:VectorToObjectSpace(input.Look)
		local yaw = math.clamp(math.deg(math.atan2(-localLook.X, -localLook.Z)), -55, 55)
		local pitch = math.clamp(math.deg(math.asin(math.clamp(localLook.Y, -1, 1))), -30, 35)
		final.Neck = pose.Neck * head(pitch * 0.6, yaw * 0.7)
	end

	-- Landing squash (a damped spring).
	rig.SquashVel += (-rig.Squash * 160 - rig.SquashVel * 14) * dt
	rig.Squash += rig.SquashVel * dt
	if math.abs(rig.Squash) > 1e-3 then
		local squash = math.clamp(rig.Squash, -1.2, 0.4)
		final.Root = CFrame.new(0, squash * 0.6, 0) * final.Root
		final.RightLeg = final.RightLeg * angles(-squash * 30, 0, 0)
		final.LeftLeg = final.LeftLeg * angles(-squash * 30, 0, 0)
	end

	-- Flips, twists and rolls.
	local flip = rig.Flip
	if flip then
		local a = (os.clock() - flip.Start) / flip.Duration
		if a >= 1 then
			rig.Flip = nil
		else
			local eased = MathUtil.Smooth(a)
			local turn = eased * flip.Turns * 360
			local rotation = if flip.Axis == "X"
				then angles(-turn, 0, 0)
				elseif flip.Axis == "Y" then angles(0, turn, 0)
				else angles(0, 0, -turn)
			local tuck = sin(a * math.pi) * flip.Tuck
			final.Root = CFrame.new(0, sin(a * math.pi) * flip.Lift, 0) * rotation * final.Root
			if tuck > 0.05 then
				final.RightLeg = final.RightLeg:Lerp(limb(1, 100), tuck)
				final.LeftLeg = final.LeftLeg:Lerp(limb(-1, 100), tuck)
				final.RightArm = final.RightArm:Lerp(limb(1, 80, 10), tuck)
				final.LeftArm = final.LeftArm:Lerp(limb(-1, 80, 10), tuck)
			end
		end
	end
	apply(rig, final)
end

-- Public -------------------------------------------------------------------------------------------

function Animator.PlayEmote(name: string, model: Model?)
	local character = model or player.Character
	local rig = character and rigs[character]
	if not rig or not EMOTES[name] then
		return
	end
	rig.Emote = name
	rig.EmoteStart = os.clock()
end

function Animator.StopEmote(model: Model?)
	local character = model or player.Character
	local rig = character and rigs[character]
	if rig then
		rig.Emote = nil
	end
end

function Animator.HasEmote(name: string): boolean
	return EMOTES[name] ~= nil
end

function Animator.IsEmoting(): boolean
	local character = player.Character
	local rig = character and rigs[character]
	return rig ~= nil and rig.Emote ~= nil
end

function Animator.Start()
	local function onCharacter(target: Player, character: Model)
		Animator.Track(character, if target == player then "Local" else "Player")
	end
	local function onPlayer(target: Player)
		if target.Character then
			onCharacter(target, target.Character)
		end
		target.CharacterAdded:Connect(function(character)
			onCharacter(target, character)
		end)
	end
	for _, target in Players:GetPlayers() do
		onPlayer(target)
	end
	Players.PlayerAdded:Connect(onPlayer)

	for _, model in CollectionService:GetTagged(Tags.Rig) do
		if model:IsA("Model") then
			Animator.Track(model, tostring(model:GetAttribute("RigKind") or "NPC"))
		end
	end
	CollectionService:GetInstanceAddedSignal(Tags.Rig):Connect(function(model)
		if model:IsA("Model") then
			Animator.Track(model, tostring(model:GetAttribute("RigKind") or "NPC"))
		end
	end)

	Controller.Action:Connect(function(action: string)
		local character = player.Character
		local rig = character and rigs[character]
		if rig then
			onAction(rig, action)
		end
	end)
	Controller.Landed:Connect(function(impact: number, kind: string)
		local character = player.Character
		local rig = character and rigs[character]
		if rig and kind ~= "Roll" then
			setLanding(rig, impact)
		end
	end)
	Net.Listen("Move.Action", function(other: Player, action: string)
		local character = typeof(other) == "Instance" and other:IsA("Player") and other.Character
		local rig = character and rigs[character]
		if rig and type(action) == "string" then
			onAction(rig, action)
		end
	end)

	RunService.PreSimulation:Connect(function(dt: number)
		frameCount += 1
		local t = os.clock()
		local camera = workspace.CurrentCamera
		local focus = if camera then camera.CFrame.Position else Vector3.zero
		for model, rig in rigs do
			if not model.Parent or not rig.Root.Parent then
				continue
			end
			-- Emotes and victories announced by the server (other players, or yours echoed back).
			local stamp = model:GetAttribute("EmoteAt")
			if stamp ~= nil and stamp ~= rig.EmoteStamp then
				rig.EmoteStamp = stamp
				local name = model:GetAttribute("Emote")
				if type(name) == "string" and EMOTES[name] and (rig.Kind ~= "Local" or rig.Emote == nil) then
					rig.Emote = name
					rig.EmoteStart = os.clock()
				end
			end
			local distance = (rig.Root.Position - focus).Magnitude
			if rig.Kind ~= "Local" then
				if distance > 600 then
					continue
				elseif distance > 220 and (frameCount + rig.Frame) % 3 ~= 0 then
					continue
				end
			end
			stepRig(rig, t, if rig.Kind ~= "Local" and distance > 220 then dt * 3 else dt)
		end
	end)
end

return Animator

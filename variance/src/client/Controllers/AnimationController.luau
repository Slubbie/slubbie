-- Procedural R6 animation for every rig VARIANCE poses itself: subjects seated
-- at an evaluation table (players and surrogates alike) and the surrogates on
-- display in the Intake. Walking players in the lobby keep Roblox's default
-- Animate script; a rig is only posed here while it is registered.
--
-- Conventions (shared with the rest of the codebase):
--   joint.Transform = C0rot^-1 * pose * C0rot, written in PreSimulation (after
--   the engine's animation step, so these poses win over any playing track).
--   Limb poses live in torso space: +X rotation swings a limb forward.
--   The body pose lives in root space: +X rotation leans back.
--   Hands are solved analytically, never read back from parts:
--     torso = root * P.Root
--     arm   = torso * Pivot * P.Arm * (0.5, -0.5, 0)      (right arm)
--     hand  = torso * Pivot * P.Arm * (0.5, -1.4, 0)
--   so the device and props can be attached to the exact hand that renders.
--
-- Layers, bottom to top: base (seated / standing) -> idle (breathing, sway,
-- personality fidgets) -> persistent states (clamped, tension tremble) ->
-- intent (reach, hold the device) -> clips (emotes, reactions, victory poses)
-- -> slump (eliminated) -> head look.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Surrogates = require(ReplicatedStorage.Variance.Data.Surrogates)
local TableLayout = require(ReplicatedStorage.Variance.Visual.TableLayout)
local Signal = require(ReplicatedStorage.Variance.Util.Signal)

local AnimationController = {}
AnimationController.Stepped = Signal.new() -- (dt) after every rig is posed

local Angles = CFrame.Angles
local I = CFrame.identity
local DOWN = Vector3.new(0, -1, 0)

local JOINTS = {
	Root = { "HumanoidRootPart", "RootJoint" },
	Neck = { "Torso", "Neck" },
	RArm = { "Torso", "Right Shoulder" },
	LArm = { "Torso", "Left Shoulder" },
	RLeg = { "Torso", "Right Hip" },
	LLeg = { "Torso", "Left Hip" },
}
local PIVOT = { RArm = Vector3.new(1, 0.5, 0), LArm = Vector3.new(-1, 0.5, 0) }
local HAND = { RArm = CFrame.new(0.5, -1.4, 0), LArm = CFrame.new(-0.5, -1.4, 0) }
local HAND_OFFSET = { RArm = Vector3.new(0.5, -1.4, 0), LArm = Vector3.new(-0.5, -1.4, 0) }
local ARM_REACH = HAND_OFFSET.RArm.Magnitude
local NECK_PIVOT = CFrame.new(0, 1, 0)
local HEAD_OFFSET = CFrame.new(0, 0.5, 0)
-- Seated, the thighs lie flat on the chair pan (the root is already at the
-- seated torso height, see TableLayout.rootCFrame).
local LEG_ANGLE = 1.55

local defaultIdle = { Sway = 0.2, Fidget = 0, Tempo = 1, HeadTilt = 0 }

export type Rig = {
	Model: Model,
	Root: BasePart,
	Torso: BasePart,
	Joints: { [string]: Motor6D },
	Rot: { [string]: CFrame },
	RotInv: { [string]: CFrame },
	Current: { [string]: CFrame },
	Kind: string,
	[string]: any,
}

local rigs: { [Model]: Rig } = {}
local bySubject: { [number]: Rig } = {}

---------------------------------------------------------------------------
-- Math helpers
---------------------------------------------------------------------------

-- Rotation about the hip line (so leaning keeps the seat planted).
local function hip(theta: number, roll: number?): CFrame
	return CFrame.new(0, -1, 0) * Angles(theta, 0, roll or 0) * CFrame.new(0, 1, 0)
end

-- Shortest-arc rotation taking the arm's rest direction (down) onto `u`.
local function swing(u: Vector3): CFrame
	local axis = DOWN:Cross(u)
	local s = axis.Magnitude
	local c = DOWN:Dot(u)
	if s < 1e-5 then
		return if c > 0 then I else Angles(math.pi, 0, 0)
	end
	return CFrame.fromAxisAngle(axis / s, math.atan2(s, c))
end

-- Arm pose whose hand points at `q` (torso space). Returns (pose, distance).
local function reach(side: string, q: Vector3): (CFrame, number)
	local s = PIVOT[side]
	local d = q - s
	local dist = d.Magnitude
	if dist < 1e-3 then
		return I, 0
	end
	local dir = d / dist
	local offset = HAND_OFFSET[side]
	-- The hand sits beside the arm's centre line; iterate so the hand, not the
	-- centre line, lands on the ray.
	local u = dir
	local pose = swing(u)
	for _ = 1, 3 do
		local lateral = pose:VectorToWorldSpace(Vector3.new(offset.X, 0, 0))
		u = (dir * ARM_REACH - lateral).Unit
		pose = swing(u)
	end
	return pose, dist
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function noise(t: number, seed: number): number
	return math.sin(t * 1.7 + seed) * 0.5 + math.sin(t * 2.9 + seed * 2.3) * 0.3 + math.sin(t * 5.3 + seed * 0.7) * 0.2
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- 0..1 progress of `t` through [a, b].
local function span(t: number, a: number, b: number): number
	return math.clamp((t - a) / (b - a), 0, 1)
end

---------------------------------------------------------------------------
-- Clips
---------------------------------------------------------------------------
-- Keys: { time, { Joint = CFrame } }. Arms and legs are absolute (nil = base
-- pose); Root and Neck are additive on top of whatever the rig is doing.
-- Events: { time, soundName } played at the rig's right hand.

type Clip = {
	Duration: number?,
	Keys: { { any } }?,
	Fn: ((t: number, rig: Rig) -> { [string]: CFrame })?,
	Events: { { any } }?,
	FadeIn: number?,
	FadeOut: number?,
	Hold: boolean?, -- stays on its last key until cleared
	Loop: number?, -- loop the keys from this time after the first pass
	Additive: boolean?, -- every joint additive (reactions)
}

local ADDITIVE_JOINT = { Root = true, Neck = true }

local function R(x: number, y: number?, z: number?): CFrame
	return Angles(x, y or 0, z or 0)
end

local CLIPS: { [string]: Clip } = {
	-- Table emotes ---------------------------------------------------------
	Nod = {
		Duration = 1.2,
		Keys = {
			{ 0, {} },
			{ 0.25, { Neck = R(-0.38) } },
			{ 0.45, { Neck = R(0.04) } },
			{ 0.68, { Neck = R(-0.32) } },
			{ 0.95, { Neck = I } },
		},
	},
	Shrug = {
		Duration = 1.7,
		Keys = {
			{ 0, {} },
			{ 0.35, { RArm = R(0.95, 0, 0.55), LArm = R(0.95, 0, -0.55), Neck = R(0, 0, 0.22), Root = hip(0.05) } },
			{ 1.15, { RArm = R(1.0, 0, 0.62), LArm = R(1.0, 0, -0.62), Neck = R(0.05, 0, 0.26), Root = hip(0.05) } },
			{ 1.7, {} },
		},
	},
	Knock = {
		Duration = 1.4,
		Keys = {
			{ 0, {} },
			{ 0.3, { RArm = R(1.28, 0, -0.18) } },
			{ 0.45, { RArm = R(0.98, 0, -0.18) } },
			{ 0.6, { RArm = R(1.24, 0, -0.18) } },
			{ 0.75, { RArm = R(0.98, 0, -0.18) } },
			{ 0.95, { RArm = R(1.1, 0, -0.1) } },
			{ 1.4, {} },
		},
		Events = { { 0.45, "Knock" }, { 0.75, "Knock" } },
	},
	Point = {
		Duration = 1.9,
		Keys = {
			{ 0, {} },
			{ 0.35, { RArm = R(1.58, 0, -0.12), Neck = R(-0.08), Root = hip(-0.08) } },
			{ 1.45, { RArm = R(1.55, 0, -0.1), Neck = R(-0.06), Root = hip(-0.08) } },
			{ 1.9, {} },
		},
	},
	ThumbsUp = {
		Duration = 1.6,
		Keys = {
			{ 0, {} },
			{ 0.3, { RArm = R(1.95, 0, -0.25) } },
			{ 1.2, { RArm = R(1.9, 0, -0.22) } },
			{ 1.6, {} },
		},
	},
	Tsk = {
		Duration = 1.6,
		Keys = {
			{ 0, {} },
			{ 0.25, { Neck = R(-0.1, 0.28), Root = hip(0.06) } },
			{ 0.5, { Neck = R(-0.1, -0.28), Root = hip(0.06) } },
			{ 0.75, { Neck = R(-0.1, 0.24), Root = hip(0.06) } },
			{ 1.0, { Neck = R(-0.1, -0.2), Root = hip(0.04) } },
			{ 1.3, { Neck = I } },
		},
	},
	Wave = {
		Duration = 2.1,
		Keys = {
			{ 0, {} },
			{ 0.3, { RArm = R(2.9, 0, 0.35) } },
			{ 0.55, { RArm = R(2.9, 0, -0.1) } },
			{ 0.8, { RArm = R(2.9, 0, 0.35) } },
			{ 1.05, { RArm = R(2.9, 0, -0.1) } },
			{ 1.3, { RArm = R(2.9, 0, 0.3) } },
			{ 2.1, {} },
		},
	},
	Stretch = {
		Duration = 2.3,
		Keys = {
			{ 0, {} },
			{ 0.55, { RArm = R(3.0, 0, 0.28), LArm = R(3.0, 0, -0.28), Root = hip(0.16), Neck = R(0.25) } },
			{ 1.45, { RArm = R(3.05, 0, 0.3), LArm = R(3.05, 0, -0.3), Root = hip(0.18), Neck = R(0.28) } },
			{ 2.3, {} },
		},
	},

	-- Victory and defeat poses (held until the scene changes) ---------------
	VictoryNod = {
		Hold = true,
		Keys = {
			{ 0, {} },
			{ 0.4, { Neck = R(-0.35), Root = hip(0.04) } },
			{ 0.8, { Neck = R(0.02), Root = hip(0.06) } },
			{ 1.1, { Neck = R(-0.05), Root = hip(0.08) } },
		},
	},
	LeanBack = {
		Hold = true,
		Keys = {
			{ 0, {} },
			{
				0.7,
				{
					Root = hip(0.32),
					RArm = R(2.55, 0, 0.75),
					LArm = R(2.55, 0, -0.75),
					Neck = R(0.12),
					RLeg = R(1.25 - 0.32, 0, 0.12),
					LLeg = R(1.25 - 0.32, 0, -0.12),
				},
			},
		},
	},
	SlowClap = {
		Hold = true,
		Loop = 0.5,
		Keys = {
			{ 0, {} },
			{ 0.5, { RArm = R(1.35, 0, 0.32), LArm = R(1.35, 0, -0.32) } },
			{ 0.95, { RArm = R(1.35, 0, -0.1), LArm = R(1.35, 0, 0.1) } },
			{ 1.4, { RArm = R(1.35, 0, 0.32), LArm = R(1.35, 0, -0.32) } },
		},
		Events = { { 0.95, "Knock" } },
	},
	TapTemple = {
		Hold = true,
		Loop = 0.6,
		Keys = {
			{ 0, {} },
			{ 0.6, { RArm = R(2.3, 0, -0.95), Neck = R(0, 0, -0.12) } },
			{ 0.8, { RArm = R(2.35, 0, -0.9), Neck = R(0, 0, -0.12) } },
			{ 1.0, { RArm = R(2.3, 0, -0.95), Neck = R(0, 0, -0.12) } },
			{ 1.9, { RArm = R(2.3, 0, -0.95), Neck = R(0, 0, -0.12) } },
		},
	},
	Salute = {
		Hold = true,
		Keys = {
			{ 0, {} },
			{ 0.5, { RArm = R(2.5, 0, -1.02), Root = hip(0.04), Neck = R(0.05) } },
		},
	},
	ArmsCrossed = {
		Hold = true,
		Keys = {
			{ 0, {} },
			{ 0.6, { RArm = R(1.35, 0, -0.98), LArm = R(1.22, 0, 0.98), Root = hip(0.1), Neck = R(0.08) } },
		},
	},
	Bow = {
		Hold = true,
		Keys = {
			{ 0, {} },
			{ 0.8, { Root = hip(-0.5), Neck = R(-0.3), RArm = R(0.35, 0, 0.05), LArm = R(0.35, 0, -0.05) } },
			{ 1.8, { Root = hip(-0.52), Neck = R(-0.32), RArm = R(0.35, 0, 0.05), LArm = R(0.35, 0, -0.05) } },
			{ 2.4, { Root = hip(-0.05), Neck = R(-0.05) } },
		},
	},
	Raise = {
		Hold = true,
		Keys = {
			{ 0, {} },
			{ 0.7, { RArm = R(3.02, 0, 0.12), LArm = R(3.02, 0, -0.12), Root = hip(0.1), Neck = R(0.3) } },
		},
	},
	Defeat = {
		Hold = true,
		Keys = {
			{ 0, {} },
			{ 0.9, { RArm = R(2.2, 0, -0.55), LArm = R(2.2, 0, 0.55), Neck = R(-0.5), Root = hip(-0.32) } },
		},
	},

	-- Reactions (additive, short) ----------------------------------------
	Flinch = {
		Duration = 0.75,
		Additive = true,
		FadeIn = 0.04,
		Fn = function(t)
			local k = math.exp(-5 * t) * math.min(1, t * 20)
			return {
				Root = hip(0.16 * k),
				Neck = R(0.28 * k, 0.1 * k),
				RArm = R(0.45 * k, 0, 0.12 * k),
				LArm = R(0.45 * k, 0, -0.12 * k),
			}
		end,
	},
	Hit = {
		Duration = 1.3,
		Additive = true,
		FadeIn = 0.02,
		FadeOut = 0.4,
		Fn = function(t)
			local k = math.exp(-3.2 * t) * math.min(1, t * 30)
			local buzz = math.exp(-2.5 * t)
			local j = function(seed)
				return math.sin(t * 61 + seed) * 0.06 * buzz
			end
			return {
				Root = hip(0.38 * k + j(1), j(2)),
				Neck = R(0.55 * k + j(3), j(4) * 2, j(5)),
				RArm = R(0.7 * k + j(6), 0, 0.3 * k + j(7)),
				LArm = R(0.7 * k + j(8), 0, -0.3 * k + j(9)),
				RLeg = R(j(10) * 0.5),
				LLeg = R(j(11) * 0.5),
			}
		end,
	},
	Relief = {
		Duration = 1.4,
		Additive = true,
		Keys = {
			{ 0, {} },
			{ 0.3, { Root = hip(0.1), Neck = R(0.22) } },
			{ 0.7, { Root = hip(-0.12), Neck = R(-0.3) } },
			{ 1.4, {} },
		},
	},
	Recoil = {
		Duration = 0.6,
		Additive = true,
		FadeIn = 0.01,
		Fn = function(t)
			local k = math.exp(-9 * t) * math.min(1, t * 40)
			return { Root = hip(0.18 * k), RArm = R(0.55 * k), LArm = R(0.35 * k), Neck = R(0.2 * k) }
		end,
	},
	Peer = {
		Duration = 1.5,
		Additive = true,
		Keys = {
			{ 0, {} },
			{ 0.4, { Root = hip(-0.22), Neck = R(-0.3) } },
			{ 1.1, { Root = hip(-0.24), Neck = R(-0.34, 0.06) } },
			{ 1.5, {} },
		},
	},
	Laugh = {
		Duration = 1.6,
		Additive = true,
		Fn = function(t)
			local shake = math.sin(t * 22) * 0.06 * math.exp(-1.2 * t)
			local up = math.sin(math.min(1, t / 0.3) * math.pi / 2) * math.exp(-0.8 * t)
			return { Root = hip(0.14 * up + shake), Neck = R(0.3 * up + shake * 1.5) }
		end,
	},
	Glance = {
		Duration = 1.8,
		Additive = true,
		Keys = {
			{ 0, {} },
			{ 0.35, { Neck = R(0.05, 0.55) } },
			{ 1.3, { Neck = R(0.02, 0.5) } },
			{ 1.8, {} },
		},
	},
	GlanceRight = {
		Duration = 1.8,
		Additive = true,
		Keys = {
			{ 0, {} },
			{ 0.35, { Neck = R(0.05, -0.55) } },
			{ 1.3, { Neck = R(0.02, -0.5) } },
			{ 1.8, {} },
		},
	},
	Think = {
		Duration = 2.2,
		Keys = {
			{ 0, {} },
			{ 0.45, { RArm = R(2.05, 0, -0.78), Neck = R(-0.1, 0, 0.1), Root = hip(-0.06) } },
			{ 1.7, { RArm = R(2.1, 0, -0.8), Neck = R(-0.14, 0, 0.12), Root = hip(-0.06) } },
			{ 2.2, {} },
		},
	},
	Drink = {
		Duration = 1.8,
		Keys = {
			{ 0, {} },
			{ 0.45, { RArm = R(2.25, 0, -0.72), Neck = R(0.3) } },
			{ 1.3, { RArm = R(2.3, 0, -0.7), Neck = R(0.36) } },
			{ 1.8, {} },
		},
	},
	Tap = {
		Duration = 1.3,
		Keys = {
			{ 0, {} },
			{ 0.2, { RArm = R(1.18, 0, -0.1) } },
			{ 0.35, { RArm = R(1.02, 0, -0.1) } },
			{ 0.5, { RArm = R(1.15, 0, -0.1) } },
			{ 0.65, { RArm = R(1.02, 0, -0.1) } },
			{ 0.8, { RArm = R(1.15, 0, -0.1) } },
			{ 0.95, { RArm = R(1.02, 0, -0.1) } },
			{ 1.3, {} },
		},
	},
	Talk = {
		Duration = 2,
		Additive = true,
		FadeIn = 0.1,
		Fn = function(t)
			local bob = math.sin(t * 13) * 0.035 + math.sin(t * 7.3) * 0.02
			return {
				Neck = R(bob, math.sin(t * 2.1) * 0.05, math.sin(t * 1.7) * 0.03),
				Root = hip(math.sin(t * 3.1) * 0.015),
			}
		end,
	},
	Twitch = {
		Duration = 0.5,
		Additive = true,
		Fn = function(t)
			local k = math.sin(t * 50) * 0.05 * (1 - t / 0.5)
			return { Neck = R(k, k * 2), RArm = R(k), LArm = R(-k) }
		end,
	},
}

AnimationController.Clips = CLIPS

-- Victory pose ids (cosmetics) -> clip names.
local VICTORY = {
	Nod = "VictoryNod",
	LeanBack = "LeanBack",
	SlowClap = "SlowClap",
	TapTemple = "TapTemple",
	Salute = "Salute",
	ArmsCrossed = "ArmsCrossed",
	Bow = "Bow",
	Raise = "Raise",
}

local function sampleKeys(clip: Clip, t: number, joint: string, base: CFrame, additive: boolean): CFrame?
	local keys = clip.Keys :: { { any } }
	local used = false
	for _, key in keys do
		if key[2][joint] ~= nil then
			used = true
			break
		end
	end
	if not used then
		return nil
	end
	local last = keys[#keys][1]
	if clip.Loop and t > last then
		local span = last - clip.Loop
		if span > 0 then
			t = clip.Loop + ((t - clip.Loop) % span)
		end
	end
	local rest = if additive then I else base
	local a, b = keys[1], keys[#keys]
	for i = 1, #keys - 1 do
		if t >= keys[i][1] and t <= keys[i + 1][1] then
			a, b = keys[i], keys[i + 1]
			break
		end
	end
	if t >= last then
		a, b = keys[#keys], keys[#keys]
	end
	local va = a[2][joint] or rest
	local vb = b[2][joint] or rest
	local span = b[1] - a[1]
	local alpha = if span > 0 then smooth((t - a[1]) / span) else 1
	return va:Lerp(vb, alpha)
end

---------------------------------------------------------------------------
-- Arrival: walking in and sitting down
---------------------------------------------------------------------------
-- Every chair starts pulled out (TableLayout.ChairPull). The subject walks in
-- beside it, turns to the table, side-steps into the gap between the chair
-- and the table edge, sits back onto the chair, then scoots in with it. All
-- of it is in root space (the root is anchored at the final seated torso), so
-- the pose ends exactly on the seated base pose. Times at speed 1.

local ARRIVE = {
	WalkEnd = 1.0, -- walk along the table edge, facing along it
	TurnEnd = 1.3, -- turn to face the table
	StepEnd = 2.05, -- side-step in front of the chair
	SitEnd = 2.95, -- sit back onto the pulled-out chair
	ScootEnd = 3.65, -- pull the chair in
}
AnimationController.ArriveDuration = ARRIVE.ScootEnd
local WALK_FROM, STEP_FROM, WALK_LANE = 4.3, 2.1, 0.4

local function walkLegs(P, phase: number, amount: number)
	local s = math.sin(phase) * amount
	P.RLeg = R(0.55 * s)
	P.LLeg = R(-0.55 * s)
	P.RArm = R(-0.42 * s + 0.06, 0, 0.08)
	P.LArm = R(0.42 * s + 0.06, 0, -0.08)
end

-- Pose while arriving (nil when finished). Returns (P, lean, chairPull).
local function arrivalPose(rig: Rig, now: number): ({ [string]: CFrame }?, number, number)
	local a = rig.Arrival
	local t = (now - a.Start) * a.Speed
	if t >= ARRIVE.ScootEnd then
		return nil, 0, 0
	end
	local side = a.Side
	local pull = TableLayout.ChairPull
	local P = {}
	local x, z, yaw, bob, lean = 0, 0, 0, 0, 0
	local chair = pull
	P.Neck = R(-0.04)
	if t < ARRIVE.WalkEnd then
		-- Walk in along the lane beside the chair, facing the direction of travel.
		local k = smooth(t / ARRIVE.WalkEnd * 0.85 + 0.15) -- already moving at t = 0
		x = side * lerp(WALK_FROM, STEP_FROM, k)
		z = WALK_LANE
		yaw = side * math.pi / 2
		local travelled = math.abs(x - side * WALK_FROM)
		local phase = travelled / 1.1 * math.pi
		local amount = 1 - span(t, ARRIVE.WalkEnd - 0.25, ARRIVE.WalkEnd)
		walkLegs(P, phase, amount)
		bob = math.abs(math.sin(phase)) * 0.07 * amount
	elseif t < ARRIVE.TurnEnd then
		-- Turn to face the table while stepping off the lane.
		local k = smooth(span(t, ARRIVE.WalkEnd, ARRIVE.TurnEnd))
		x = side * STEP_FROM
		z = WALK_LANE * (1 - k)
		yaw = side * math.pi / 2 * (1 - k)
		local step = math.sin(k * math.pi)
		P.RLeg = R(0.18 * step)
		P.LLeg = R(-0.12 * step)
		P.RArm = R(0.06, 0, 0.08)
		P.LArm = R(0.06, 0, -0.08)
	elseif t < ARRIVE.StepEnd then
		-- Two side-steps into the gap between the chair and the table.
		local k = span(t, ARRIVE.TurnEnd, ARRIVE.StepEnd)
		x = side * STEP_FROM * (1 - smooth(k))
		local stepPhase = k * 2 * math.pi
		local open = math.max(0, math.sin(stepPhase)) * 0.3
		-- The leading leg (toward the chair) opens, then the trailing one follows.
		local lead = if side > 0 then "LLeg" else "RLeg"
		local trail = if side > 0 then "RLeg" else "LLeg"
		P[lead] = R(0, 0, -side * open)
		P[trail] = R(0, 0, side * math.max(0, -math.sin(stepPhase)) * 0.18)
		bob = math.abs(math.sin(stepPhase)) * 0.04
		P.RArm = R(0.08, 0, 0.1 + 0.06 * math.sin(stepPhase))
		P.LArm = R(0.08, 0, -0.1 - 0.06 * math.sin(stepPhase))
		P.Neck = R(-0.12)
	elseif t < ARRIVE.SitEnd then
		-- Sit back: hips travel onto the pulled-out chair while the thighs swing
		-- up, the body leaning forward to balance, hands reaching for the armrests.
		local k = span(t, ARRIVE.StepEnd, ARRIVE.SitEnd)
		local e = smooth(k)
		z = pull * e
		local legs = smooth(span(k, 0.1, 0.9))
		lean = -0.32 * math.sin(e * math.pi) + -0.06 * e
		bob = -0.12 * math.sin(e * math.pi)
		P.RLeg = R((LEG_ANGLE - lean) * legs, 0, 0.07 * legs)
		P.LLeg = R((LEG_ANGLE - lean) * legs, 0, -0.07 * legs)
		local reach = math.sin(e * math.pi)
		P.RArm = R(-0.35 * reach + 0.9 * legs * legs, 0, 0.18 * reach)
		P.LArm = R(-0.35 * reach + 0.9 * legs * legs, 0, -0.18 * reach)
		P.Neck = R(-0.18 + 0.14 * e)
	else
		-- Scoot in: the chair and the subject slide to the table together.
		local k = span(t, ARRIVE.SitEnd, ARRIVE.ScootEnd)
		local e = smooth(k)
		z = pull * (1 - e)
		chair = z
		lean = -0.06 - 0.1 * math.sin(k * math.pi)
		P.RLeg = R(LEG_ANGLE - lean, 0, 0.07)
		P.LLeg = R(LEG_ANGLE - lean, 0, -0.07)
		-- Hands take the table edge as it arrives.
		P.RArm = R(0.9 + 0.35 * e, 0, -0.05)
		P.LArm = R(0.9 + 0.35 * e, 0, 0.05)
		P.Neck = R(-0.04 - 0.05 * math.sin(k * math.pi))
	end
	P.Root = CFrame.new(x, bob, z) * Angles(0, yaw, 0) * hip(lean)
	return P, lean, chair
end

local function placeChair(rig: Rig, pull: number)
	local a = rig.Arrival
	if a and a.Chair and a.Chair.Parent then
		a.Chair:PivotTo(CFrame.new(a.Back * pull) * a.ChairBase)
	end
end

-- Starts the walk-in for a seated rig. `speed` scales the choreography.
function AnimationController:arrive(rig: Rig?, speed: number?, startAt: number?)
	if rig == nil or rig.Kind ~= "Seated" or rig.Origin == nil or rig.Seat == nil then
		return
	end
	local seats = rig.Origin and self.Arena and self.Arena:FindFirstChild("Seats")
	local chair = seats and seats:FindFirstChild("Chair_" .. rig.Seat)
	if chair == nil or not chair:IsA("Model") then
		return -- not streamed in: sit straight down rather than walk through it
	end
	local seatCF = rig.Origin * TableLayout.seatCFrame(rig.Seat)
	local base = if rig.Arrival then rig.Arrival.ChairBase else chair:GetPivot()
	rig.Arrival = {
		Start = startAt or os.clock(),
		Speed = speed or 1,
		Side = if rig.Seat % 2 == 1 then 1 else -1,
		Chair = chair,
		ChairBase = base,
		Back = seatCF.ZVector,
	}
	placeChair(rig, TableLayout.ChairPull)
	rig.Snap = true
end

function AnimationController:arriving(rig: Rig?): boolean
	return rig ~= nil and rig.Arrival ~= nil
end

-- Ends an arrival now (the chair goes home, the rig sits).
function AnimationController:settle(rig: Rig?)
	if rig and rig.Arrival then
		placeChair(rig, 0)
		rig.Arrival = nil
	end
end

-- The arena whose chairs arrivals move (set by the presenter).
function AnimationController:setArena(arena: Instance?)
	self.Arena = arena
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------

function AnimationController:Init(controllers)
	self.Controllers = controllers
end

-- Registers a rig. opts:
--   Kind        "Seated" | "Display"
--   Subject     subject id (match rigs)
--   Personality surrogate id (idle style)
--   Origin, Seat  arena origin CFrame and physical seat (seated rigs)
--   Local       true for the local player's own character
function AnimationController:register(model: Model, opts: { [string]: any }): Rig?
	local existing = rigs[model]
	if existing then
		for k, v in opts do
			existing[k] = v
		end
		if opts.Subject then
			bySubject[opts.Subject] = existing
		end
		return existing
	end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local torso = model:FindFirstChild("Torso") :: BasePart?
	if root == nil or torso == nil then
		return nil
	end
	local joints, rot, inv, current = {}, {}, {}, {}
	for name, path in JOINTS do
		local part = model:FindFirstChild(path[1])
		local joint = part and part:FindFirstChild(path[2])
		if joint == nil or not joint:IsA("Motor6D") then
			return nil
		end
		joints[name] = joint
		rot[name] = joint.C0.Rotation
		inv[name] = joint.C0.Rotation:Inverse()
		current[name] = I
	end
	local look = opts.Personality and Surrogates.get(opts.Personality)
	local rig: Rig = {
		Model = model,
		Root = root,
		Torso = torso,
		Joints = joints,
		Rot = rot,
		RotInv = inv,
		Current = current,
		Kind = opts.Kind or "Seated",
		Subject = opts.Subject,
		Personality = opts.Personality,
		Origin = opts.Origin,
		Seat = opts.Seat,
		Local = opts.Local == true,
		Idle = look and look.Idle or defaultIdle,
		Phase = math.random() * 100,
		Seed = math.random() * 50,
		Breath = 0,
		LookYaw = 0,
		LookPitch = 0,
		Look = nil, -- { Yaw, Pitch } explicit head direction (players)
		LookPoint = nil, -- world point to look at (surrogates, cinematic)
		Clips = {},
		States = { Slumped = 0, Clamped = 0, Tension = 0 },
		Weights = { Slumped = 0, Clamped = 0, Tension = 0 },
		Intent = nil,
		NextFidget = os.clock() + 3 + math.random() * 5,
		Snap = true,
	}
	rigs[model] = rig
	if rig.Subject then
		bySubject[rig.Subject] = rig
	end
	return rig
end

function AnimationController:unregister(model: Model)
	local rig = rigs[model]
	if rig == nil then
		return
	end
	rigs[model] = nil
	self:settle(rig)
	if rig.Subject and bySubject[rig.Subject] == rig then
		bySubject[rig.Subject] = nil
	end
	for _, joint in rig.Joints do
		if joint.Parent then
			joint.Transform = I
		end
	end
end

-- Drops every match rig (called when leaving a table).
function AnimationController:clearSeated()
	for model, rig in rigs do
		if rig.Kind == "Seated" then
			self:unregister(model)
		end
	end
	table.clear(bySubject)
end

function AnimationController:rigOf(subjectId: number?): Rig?
	if subjectId == nil then
		return nil
	end
	local rig = bySubject[subjectId]
	if rig and rig.Root.Parent == nil then
		return nil
	end
	return rig
end

function AnimationController:rigFor(model: Model): Rig?
	return rigs[model]
end

---------------------------------------------------------------------------
-- Control
---------------------------------------------------------------------------

-- Plays a clip. Returns its duration.
function AnimationController:play(rig: Rig?, name: string, speed: number?): number
	if rig == nil then
		return 0
	end
	local clip = CLIPS[name]
	if clip == nil then
		return 0
	end
	-- One instance per clip; held poses replace each other.
	for i = #rig.Clips, 1, -1 do
		local other = rig.Clips[i]
		if other.Name == name or (clip.Hold and other.Clip.Hold) then
			table.remove(rig.Clips, i)
		end
	end
	table.insert(rig.Clips, {
		Name = name,
		Clip = clip,
		Start = os.clock(),
		Speed = speed or 1,
		Fired = {},
	})
	return (clip.Duration or 0) / (speed or 1)
end

function AnimationController:stop(rig: Rig?, name: string?)
	if rig == nil then
		return
	end
	for i = #rig.Clips, 1, -1 do
		if name == nil or rig.Clips[i].Name == name then
			local entry = rig.Clips[i]
			-- Fade held poses out instead of snapping.
			entry.Release = os.clock()
		end
	end
end

function AnimationController:victory(rig: Rig?, pose: string?)
	self:play(rig, VICTORY[pose or "Nod"] or "VictoryNod")
end

function AnimationController:emote(rig: Rig?, anim: string)
	if CLIPS[anim] and not CLIPS[anim].Hold then
		self:play(rig, anim)
	end
end

-- Persistent states: Slumped (0/1), Clamped (0/1), Tension (0..1).
function AnimationController:setState(rig: Rig?, key: string, value: number)
	if rig then
		rig.States[key] = value
	end
end

-- Device / prop interaction. intent = nil | { Kind = "Reach", Point, Side? }
-- | { Kind = "Hold", Aim, Reverse, Lift, Support? } | { Kind = "Both", Point }.
function AnimationController:setIntent(rig: Rig?, intent: { [string]: any }?)
	if rig then
		rig.Intent = intent
	end
end

-- Head direction for player rigs (yaw/pitch relative to the torso).
function AnimationController:setLook(rig: Rig?, yaw: number, pitch: number)
	if rig then
		rig.Look = { Yaw = math.clamp(yaw, -1.3, 1.3), Pitch = math.clamp(pitch, -0.85, 0.6) }
		rig.LookPoint = nil
	end
end

function AnimationController:lookAt(rig: Rig?, point: Vector3?)
	if rig then
		rig.LookPoint = point
	end
end

-- World CFrame of a rig's head (eyes at +0.1 up, facing -Z).
function AnimationController:head(rig: Rig?): CFrame?
	return rig and rig.Head or nil
end

function AnimationController:hand(rig: Rig?, side: string?): CFrame?
	if rig == nil then
		return nil
	end
	return if side == "L" then rig.HandL else rig.HandR
end

---------------------------------------------------------------------------
-- Pose evaluation
---------------------------------------------------------------------------

-- World points a seated rig's hands rest on (table edge, armrests).
local function seatSpace(rig: Rig, offset: Vector3): Vector3?
	if rig.Origin == nil or rig.Seat == nil then
		return nil
	end
	return (rig.Origin * TableLayout.seatCFrame(rig.Seat) * CFrame.new(offset)).Position
end

local function basePose(rig: Rig, now: number, dt: number): ({ [string]: CFrame }, number)
	local idle = rig.Idle
	local tension = rig.Weights.Tension
	local tempo = (idle.Tempo or 1) * (1 + tension * 0.9)
	rig.Breath += dt * tempo * 1.6
	local b = math.sin(rig.Breath)
	local t = now + rig.Phase
	local sway = (idle.Sway or 0.2) * 0.035
	local P = {}
	if rig.Kind == "Seated" then
		if rig.Arrival then
			local arriving, arrivingLean, chair = arrivalPose(rig, now)
			if arriving then
				placeChair(rig, chair)
				return arriving, arrivingLean
			end
			AnimationController:settle(rig)
		end
		local lean = -0.06 + 0.012 * b
		P.Root = CFrame.new(0, 0.015 * b, 0) * hip(lean, sway * noise(t * 0.4, rig.Seed))
		P.RLeg = R(LEG_ANGLE - lean, 0, 0.07)
		P.LLeg = R(LEG_ANGLE - lean, 0, -0.07)
		P.Neck = R(-0.04 - 0.012 * b, 0, (idle.HeadTilt or 0))
		return P, lean
	end
	-- Standing on display.
	P.Root = CFrame.new(0, 0.02 * b, 0) * Angles(0.01 * b, sway * noise(t * 0.3, rig.Seed), 0)
	P.RLeg = I
	P.LLeg = I
	P.RArm = R(0.05 + 0.02 * b, 0, 0.1)
	P.LArm = R(0.05 + 0.02 * b, 0, -0.1)
	P.Neck = R(-0.03 * b, 0, idle.HeadTilt or 0)
	return P, 0
end

-- Converts a world point into the torso space of a pose.
local function toTorso(rig: Rig, rootPose: CFrame, point: Vector3): Vector3
	return (rig.Root.CFrame * rootPose):PointToObjectSpace(point)
end

local function applyIntent(rig: Rig, P: { [string]: CFrame }, lean: number)
	local intent = rig.Intent
	if intent == nil then
		return
	end
	local kind = intent.Kind
	if kind == "Reach" or kind == "Both" then
		local point = intent.Point :: Vector3
		-- Lean toward far targets (from the hips).
		local q0 = toTorso(rig, P.Root, point)
		local flat = Vector2.new(q0.X - 1, q0.Z).Magnitude
		local extra = math.clamp((flat - 1.2) * 0.32, 0, 0.5) * (intent.Weight or 1)
		if rig.Kind == "Seated" then
			P.Root = P.Root * hip(-extra)
			P.RLeg = R(LEG_ANGLE - lean + extra, 0, 0.07)
			P.LLeg = R(LEG_ANGLE - lean + extra, 0, -0.07)
		end
		local q = toTorso(rig, P.Root, point)
		if kind == "Both" then
			P.RArm = reach("RArm", q + Vector3.new(0.35, 0, 0))
			P.LArm = reach("LArm", q - Vector3.new(0.35, 0, 0))
		elseif intent.Side == "L" then
			P.LArm = reach("LArm", q)
		else
			P.RArm = reach("RArm", q)
		end
		P.Neck = P.Neck * R(-0.12 * math.min(1, extra * 3))
	elseif kind == "Hold" then
		local aim = intent.Aim :: Vector3?
		local lift = math.clamp(intent.Lift or 1, 0, 1)
		local twist = 0
		if aim then
			local a = toTorso(rig, P.Root, aim)
			local yaw = math.atan2(-a.X, -a.Z)
			if not intent.Reverse then
				twist = math.clamp(yaw * 0.45, -0.55, 0.55)
			end
		end
		if intent.Reverse then
			-- Muzzle to the chin: lean back a touch, head bowed toward it.
			P.Root = P.Root * hip(0.06 * lift) * Angles(0, 0.08 * lift, 0)
			P.Neck = P.Neck * R(-0.18 * lift, -0.1 * lift)
			local hand = Vector3.new(0.72, -0.35 + 0.8 * lift, -1.2 - 0.1 * lift)
			P.RArm = reach("RArm", hand)
		else
			P.Root = P.Root * hip(-0.08 * lift) * Angles(0, twist * lift, 0)
			local hand = Vector3.new(0.55, -0.55 + 0.45 * lift, -1.35)
			P.RArm = reach("RArm", hand)
		end
		if intent.Support then
			local q = toTorso(rig, P.Root, intent.Support :: Vector3)
			local pose, dist = reach("LArm", q)
			if dist < ARM_REACH + 0.9 then
				P.LArm = pose
			end
		elseif intent.Brace then
			local q = toTorso(rig, P.Root, intent.Brace :: Vector3)
			P.LArm = reach("LArm", q)
		end
	end
end

local function evaluate(rig: Rig, now: number, dt: number): { [string]: CFrame }
	local P, lean = basePose(rig, now, dt)
	local W = rig.Weights
	for key, target in rig.States do
		local rate = if key == "Slumped" then 2.2 else 5
		W[key] += (target - W[key]) * (1 - math.exp(-rate * dt))
	end

	local arriving = rig.Arrival ~= nil

	-- Hands resting on the table in front of a seated subject.
	if rig.Kind == "Seated" and P.RArm == nil then
		local right = seatSpace(rig, Vector3.new(0.78, TableLayout.TableTop + 0.08, -1.35))
		local left = seatSpace(rig, Vector3.new(-0.78, TableLayout.TableTop + 0.08, -1.35))
		if right and left then
			P.RArm = reach("RArm", toTorso(rig, P.Root, right))
			P.LArm = reach("LArm", toTorso(rig, P.Root, left))
		else
			P.RArm = R(1.0, 0, -0.08)
			P.LArm = R(1.0, 0, 0.08)
		end
	end

	-- Clamped: wrists together on the table.
	if W.Clamped > 0.01 and rig.Kind == "Seated" and not arriving then
		local centre = seatSpace(rig, Vector3.new(0, TableLayout.TableTop + 0.12, -1.55))
		if centre then
			local q = toTorso(rig, P.Root, centre)
			P.RArm = P.RArm:Lerp(reach("RArm", q + Vector3.new(0.3, 0, 0)), W.Clamped)
			P.LArm = P.LArm:Lerp(reach("LArm", q - Vector3.new(0.3, 0, 0)), W.Clamped)
		end
	end

	if not arriving then
		applyIntent(rig, P, lean)
	end

	-- Personality fidgets for surrogates (never while holding anything).
	if
		rig.Personality
		and not arriving
		and rig.Intent == nil
		and #rig.Clips == 0
		and now >= rig.NextFidget
		and W.Slumped < 0.1
	then
		local fidget = rig.Idle.Fidget or 0
		rig.NextFidget = now + (6 - fidget * 4) + math.random() * 5
		if fidget > 0 and math.random() < 0.35 + fidget * 0.6 then
			local options = { "Glance", "GlanceRight", "Tap" }
			if fidget > 0.4 then
				table.insert(options, "Twitch")
			end
			AnimationController:play(rig, options[math.random(1, #options)])
		end
	end

	-- Clips.
	for i = #rig.Clips, 1, -1 do
		local entry = rig.Clips[i]
		local clip = entry.Clip
		local t = (now - entry.Start) * entry.Speed
		local duration = clip.Duration
		local finished = duration ~= nil and not clip.Hold and t >= duration
		local released = entry.Release ~= nil and now - entry.Release >= 0.4
		if finished or released then
			table.remove(rig.Clips, i)
		else
			local fadeIn = clip.FadeIn or 0.2
			local w = math.min(1, t / math.max(fadeIn, 1e-3))
			if duration and not clip.Hold then
				w = math.min(w, (duration - t) / (clip.FadeOut or 0.25))
			end
			if entry.Release then
				w = math.min(w, 1 - (now - entry.Release) / 0.4)
			end
			w = smooth(w)
			if clip.Events then
				local keys = clip.Keys :: { { any } }
				local span = if clip.Loop and keys then keys[#keys][1] - clip.Loop else 0
				for index, event in clip.Events do
					local at = event[1]
					if t >= at then
						-- Which pass of the loop this is (0 for one-shot clips).
						local cycle = if span > 0 then math.floor((t - at) / span) else 0
						if entry.Fired[index] ~= cycle then
							entry.Fired[index] = cycle
							rig.PendingSound = event[2]
						end
					end
				end
			end
			if clip.Fn then
				local out = clip.Fn(t, rig)
				for joint, value in out do
					if P[joint] then
						P[joint] = P[joint] * I:Lerp(value, w)
					end
				end
			elseif clip.Keys then
				for joint in JOINTS do
					local additive = clip.Additive == true or ADDITIVE_JOINT[joint] == true
					local value = sampleKeys(clip, t, joint, P[joint], additive)
					if value then
						if additive then
							P[joint] = P[joint] * I:Lerp(value, w)
						else
							P[joint] = P[joint]:Lerp(value, w)
						end
					end
				end
			end
		end
	end

	-- Tension: a fine tremble in the hands and head, faster breathing.
	local tension = W.Tension
	if tension > 0.02 then
		local t = now * 13 + rig.Seed
		local a = 0.018 * tension
		P.RArm = P.RArm * R(math.sin(t) * a, 0, math.sin(t * 1.3) * a)
		P.LArm = P.LArm * R(math.sin(t * 0.9 + 1) * a, 0, math.sin(t * 1.1) * a)
		P.Neck = P.Neck * R(math.sin(t * 0.7) * a * 0.6, math.sin(t * 0.5) * a * 0.6)
	end

	-- Head look.
	local yaw, pitch = 0, 0
	if rig.LookPoint then
		local q = toTorso(rig, P.Root, rig.LookPoint) - Vector3.new(0, 1.5, 0)
		yaw = math.clamp(math.atan2(-q.X, -q.Z), -1.25, 1.25)
		pitch = math.clamp(math.atan2(q.Y, Vector2.new(q.X, q.Z).Magnitude), -0.8, 0.55)
	elseif rig.Look then
		yaw, pitch = rig.Look.Yaw, rig.Look.Pitch
	end
	local k = 1 - math.exp(-8 * dt)
	rig.LookYaw += (yaw - rig.LookYaw) * k
	rig.LookPitch += (pitch - rig.LookPitch) * k
	local lookWeight = 1 - W.Slumped
	P.Neck = Angles(0, rig.LookYaw * lookWeight, 0) * Angles(rig.LookPitch * lookWeight, 0, 0) * P.Neck

	-- Eliminated: the whole body sags forward onto the table, arms limp on it.
	local slump = W.Slumped
	if slump > 0.01 then
		local twitch = math.sin(now * 37 + rig.Seed) * 0.03 * math.max(0, math.sin(now * 0.7 + rig.Seed))
		P.Root = P.Root:Lerp(P.Root * hip(-0.58), slump)
		P.Neck = P.Neck:Lerp(R(-0.62 + twitch, 0, 0.18), slump)
		P.RArm = P.RArm:Lerp(R(0.95, 0, 0.1), slump)
		P.LArm = P.LArm:Lerp(R(0.95, 0, -0.1), slump)
		if rig.Kind == "Seated" then
			P.RLeg = P.RLeg:Lerp(R(LEG_ANGLE + 0.5, 0, 0.12), slump)
			P.LLeg = P.LLeg:Lerp(R(LEG_ANGLE + 0.5, 0, -0.12), slump)
		end
	end
	return P
end

local function step(rig: Rig, dt: number, now: number)
	local P = evaluate(rig, now, dt)
	local rate = if rig.Snap then 1 else 1 - math.exp(-16 * dt)
	rig.Snap = false
	local current = rig.Current
	for name, joint in rig.Joints do
		local target = P[name] or I
		local value = current[name]:Lerp(target, rate)
		current[name] = value
		joint.Transform = rig.RotInv[name] * value * rig.Rot[name]
	end
	local torso = rig.Root.CFrame * current.Root
	rig.TorsoCF = torso
	rig.HandR = torso * CFrame.new(PIVOT.RArm) * current.RArm * HAND.RArm
	rig.HandL = torso * CFrame.new(PIVOT.LArm) * current.LArm * HAND.LArm
	rig.Head = torso * NECK_PIVOT * current.Neck * HEAD_OFFSET
	if rig.PendingSound then
		local sound = rig.PendingSound
		rig.PendingSound = nil
		AnimationController.Controllers.AudioController:play(sound, { At = rig.HandR.Position })
	end
end

function AnimationController:Start()
	local function frame(dt: number)
		if dt <= 0 then
			return
		end
		local now = os.clock()
		local weapon = self.Controllers.WeaponController
		if weapon and weapon.preStep then
			weapon:preStep(dt)
		end
		for model, rig in rigs do
			if rig.Root.Parent and rig.Torso.Parent and model.Parent then
				local ok, err = pcall(step, rig, dt, now)
				if not ok then
					warn("[VARIANCE/Anim] " .. tostring(err))
					self:unregister(model)
				end
			else
				self:unregister(model)
			end
		end
		if weapon and weapon.postStep then
			weapon:postStep(dt)
		end
		AnimationController.Stepped:Fire(dt)
	end
	local ok = pcall(function()
		RunService.PreSimulation:Connect(frame)
	end)
	if not ok then
		RunService.Stepped:Connect(function(_, dt)
			frame(dt)
		end)
	end

	-- Our own character sheds any rig registration when it respawns.
	Players.LocalPlayer.CharacterRemoving:Connect(function(character)
		self:unregister(character)
	end)
end

return AnimationController

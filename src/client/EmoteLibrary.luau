-- Keyframed emote animations for R6, plus their sounds and particle effects.
--
-- Each keyframe gives joint rotations in degrees as { x, y, z, dy }:
--   limbs (torso space): +x swings forward, +z swings a RIGHT limb outward
--                        (a LEFT limb goes outward with -z)
--   Root  (body):        +x leans back, +y turns left, +z tilts left, dy moves up
--   Neck:                +x looks up, +y turns left
-- Joints left out of a keyframe relax to their rest pose. Frames are eased
-- (smooth by default), looping emotes wrap back to their first frame.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local rad = math.rad

export type Frame = { T: number, [string]: { number } }
export type Beat = { T: number, Sound: string }
export type Emote = {
	Name: string,
	Icon: string,
	Length: number,
	Loop: boolean,
	Ease: string?,
	-- Let the head keep looking around (false when the emote controls the head).
	FreeHead: boolean?,
	Particles: string?,
	Beats: { Beat }?,
	Frames: { Frame },
}

local JOINTS = { "Root", "Neck", "RArm", "LArm", "RLeg", "LLeg" }

local EmoteLibrary = {}

EmoteLibrary.Sounds = {
	Clap = { Id = Config.Sounds.Land, Pitch = 2.6, Volume = 0.6 },
	Chime = { Id = Config.Sounds.Ping, Pitch = 1.5, Volume = 0.35 },
	Pop = { Id = Config.Sounds.Ping, Pitch = 2.1, Volume = 0.3 },
	Whoosh = { Id = Config.Sounds.Whoosh, Pitch = 1.3, Volume = 0.35 },
}

local ARMS_REST = { RArm = { 0, 0, 5 }, LArm = { 0, 0, -5 } }

local function with(base: { [string]: { number } }, frame: Frame): Frame
	for joint, value in base do
		if frame[joint] == nil then
			frame[joint] = value
		end
	end
	return frame
end

EmoteLibrary.Emotes = {
	Wave = {
		Name = "Wave",
		Icon = "👋",
		Length = 0.8,
		Loop = true,
		FreeHead = true,
		Frames = {
			{ T = 0, RArm = { 10, 0, 140 }, LArm = { 0, 0, -6 }, Root = { 0, 0, 3 } },
			{ T = 0.4, RArm = { 10, 0, 168 }, LArm = { 0, 0, -6 }, Root = { 0, 0, 3 } },
			{ T = 0.8, RArm = { 10, 0, 140 }, LArm = { 0, 0, -6 }, Root = { 0, 0, 3 } },
		},
	},
	Groove = {
		Name = "Groove",
		Icon = "🕺",
		Length = 1,
		Loop = true,
		Particles = "Notes",
		Frames = {
			{
				T = 0,
				Root = { 0, 15, 0, -0.25 },
				RArm = { 70, 0, 25 },
				LArm = { -25, 0, -20 },
				RLeg = { 0, 0, 15 },
				LLeg = { 0, 0, -4 },
				Neck = { 0, -15, 6 },
			},
			{ T = 0.25, Root = { 0, 0, 0, 0.05 }, RArm = { 25, 0, 15 }, LArm = { 25, 0, -15 } },
			{
				T = 0.5,
				Root = { 0, -15, 0, -0.25 },
				RArm = { -25, 0, 20 },
				LArm = { 70, 0, -25 },
				RLeg = { 0, 0, 4 },
				LLeg = { 0, 0, -15 },
				Neck = { 0, 15, -6 },
			},
			{ T = 0.75, Root = { 0, 0, 0, 0.05 }, RArm = { 25, 0, 15 }, LArm = { 25, 0, -15 } },
			{
				T = 1,
				Root = { 0, 15, 0, -0.25 },
				RArm = { 70, 0, 25 },
				LArm = { -25, 0, -20 },
				RLeg = { 0, 0, 15 },
				LLeg = { 0, 0, -4 },
				Neck = { 0, -15, 6 },
			},
		},
	},
	Floss = {
		Name = "Floss",
		Icon = "💃",
		Length = 0.6,
		Loop = true,
		Frames = {
			{ T = 0, RArm = { -25, 0, 35 }, LArm = { 25, 0, 30 }, Root = { 0, 0, -9 }, Neck = { 0, 0, 6 } },
			{ T = 0.3, RArm = { 25, 0, -30 }, LArm = { -25, 0, -35 }, Root = { 0, 0, 9 }, Neck = { 0, 0, -6 } },
			{ T = 0.6, RArm = { -25, 0, 35 }, LArm = { 25, 0, 30 }, Root = { 0, 0, -9 }, Neck = { 0, 0, 6 } },
		},
	},
	Cheer = {
		Name = "Cheer",
		Icon = "🎉",
		Length = 0.8,
		Loop = true,
		Particles = "Confetti",
		Beats = { { T = 0.2, Sound = "Pop" } },
		Frames = {
			{
				T = 0,
				Root = { 0, 0, 0, -0.3 },
				RArm = { 10, 0, 145 },
				LArm = { 10, 0, -145 },
				RLeg = { 20, 0, 5 },
				LLeg = { 20, 0, -5 },
				Neck = { 15, 0, 0 },
			},
			{
				T = 0.2,
				Root = { 0, 0, 0, 1.1 },
				RArm = { 0, 0, 165 },
				LArm = { 0, 0, -165 },
				RLeg = { -10, 0, 12 },
				LLeg = { -10, 0, -12 },
				Neck = { 25, 0, 0 },
			},
			{ T = 0.45, Root = { 0, 0, 0, 0.2 }, RArm = { 5, 0, 155 }, LArm = { 5, 0, -155 }, Neck = { 20, 0, 0 } },
			{
				T = 0.8,
				Root = { 0, 0, 0, -0.3 },
				RArm = { 10, 0, 145 },
				LArm = { 10, 0, -145 },
				RLeg = { 20, 0, 5 },
				LLeg = { 20, 0, -5 },
				Neck = { 15, 0, 0 },
			},
		},
	},
	Clap = {
		Name = "Clap",
		Icon = "👏",
		Length = 0.5,
		Loop = true,
		FreeHead = true,
		Beats = { { T = 0.25, Sound = "Clap" } },
		Frames = {
			{ T = 0, RArm = { 70, 0, 18 }, LArm = { 70, 0, -18 }, Root = { 3, 0, 0 } },
			{ T = 0.25, RArm = { 78, 0, -16 }, LArm = { 78, 0, 16 }, Root = { 3, 0, 0, -0.05 } },
			{ T = 0.5, RArm = { 70, 0, 18 }, LArm = { 70, 0, -18 }, Root = { 3, 0, 0 } },
		},
	},
	Salute = {
		Name = "Salute",
		Icon = "🎖",
		Length = 2.4,
		Loop = false,
		Beats = { { T = 0.3, Sound = "Chime" } },
		Frames = {
			with(ARMS_REST, { T = 0 }),
			{ T = 0.3, RArm = { 144, 0, -30 }, LArm = { 0, 0, -3 }, Root = { 4, 0, 0 }, Neck = { 5, 0, 0 } },
			{ T = 2, RArm = { 144, 0, -30 }, LArm = { 0, 0, -3 }, Root = { 4, 0, 0 }, Neck = { 5, 0, 0 } },
			with(ARMS_REST, { T = 2.4 }),
		},
	},
	Bow = {
		Name = "Bow",
		Icon = "🙇",
		Length = 2.6,
		Loop = false,
		Particles = "Sparkles",
		Frames = {
			with(ARMS_REST, { T = 0 }),
			{
				T = 0.5,
				Root = { -50, 0, 0, -0.2 },
				RArm = { 45, 0, -40 },
				LArm = { -35, 0, -12 },
				Neck = { -15, 0, 0 },
			},
			{
				T = 1.9,
				Root = { -50, 0, 0, -0.2 },
				RArm = { 45, 0, -40 },
				LArm = { -35, 0, -12 },
				Neck = { -15, 0, 0 },
			},
			with(ARMS_REST, { T = 2.6 }),
		},
	},
	Laugh = {
		Name = "Laugh",
		Icon = "😂",
		Length = 0.5,
		Loop = true,
		Frames = {
			{ T = 0, Root = { 12, 0, 0 }, RArm = { 49, 0, -24 }, LArm = { 49, 0, 24 }, Neck = { 28, 0, 0 } },
			{ T = 0.12, Root = { 18, 0, 3, -0.08 }, RArm = { 52, 0, -22 }, LArm = { 52, 0, 22 }, Neck = { 34, 5, 0 } },
			{ T = 0.25, Root = { 12, 0, 0 }, RArm = { 49, 0, -24 }, LArm = { 49, 0, 24 }, Neck = { 28, 0, 0 } },
			{
				T = 0.37,
				Root = { 18, 0, -3, -0.08 },
				RArm = { 52, 0, -22 },
				LArm = { 52, 0, 22 },
				Neck = { 34, -5, 0 },
			},
			{ T = 0.5, Root = { 12, 0, 0 }, RArm = { 49, 0, -24 }, LArm = { 49, 0, 24 }, Neck = { 28, 0, 0 } },
		},
	},
	Flex = {
		Name = "Flex",
		Icon = "💪",
		Length = 1.2,
		Loop = true,
		Beats = { { T = 0.6, Sound = "Pop" } },
		Particles = "Sparkles",
		Frames = {
			{
				T = 0,
				Root = { 5, 0, 0 },
				RArm = { 10, 0, 100 },
				LArm = { 10, 0, -100 },
				RLeg = { 0, 0, 10 },
				LLeg = { 0, 0, -10 },
				Neck = { 8, 0, 0 },
			},
			{
				T = 0.6,
				Root = { 8, 0, 0, -0.12 },
				RArm = { 30, 0, 125 },
				LArm = { 30, 0, -125 },
				RLeg = { 0, 0, 12 },
				LLeg = { 0, 0, -12 },
				Neck = { 12, 0, 0 },
			},
			{
				T = 1.2,
				Root = { 5, 0, 0 },
				RArm = { 10, 0, 100 },
				LArm = { 10, 0, -100 },
				RLeg = { 0, 0, 10 },
				LLeg = { 0, 0, -10 },
				Neck = { 8, 0, 0 },
			},
		},
	},
	Spin = {
		Name = "Spin",
		Icon = "🌀",
		Length = 0.9,
		Loop = true,
		Ease = "Linear",
		Particles = "Sparkles",
		Beats = { { T = 0, Sound = "Whoosh" } },
		Frames = {
			{
				T = 0,
				Root = { 0, 0, 0, 0.1 },
				RArm = { 0, 0, 95 },
				LArm = { 0, 0, -95 },
				RLeg = { 0, 0, 12 },
				LLeg = { 0, 0, -12 },
			},
			{
				T = 0.225,
				Root = { 0, 90, 0, 0.25 },
				RArm = { 0, 0, 100 },
				LArm = { 0, 0, -100 },
				RLeg = { 0, 0, 14 },
				LLeg = { 0, 0, -14 },
			},
			{
				T = 0.45,
				Root = { 0, 180, 0, 0.1 },
				RArm = { 0, 0, 95 },
				LArm = { 0, 0, -95 },
				RLeg = { 0, 0, 12 },
				LLeg = { 0, 0, -12 },
			},
			{
				T = 0.675,
				Root = { 0, 270, 0, 0.25 },
				RArm = { 0, 0, 100 },
				LArm = { 0, 0, -100 },
				RLeg = { 0, 0, 14 },
				LLeg = { 0, 0, -14 },
			},
			{
				T = 0.9,
				Root = { 0, 360, 0, 0.1 },
				RArm = { 0, 0, 95 },
				LArm = { 0, 0, -95 },
				RLeg = { 0, 0, 12 },
				LLeg = { 0, 0, -12 },
			},
		},
	},
	Sit = {
		Name = "Sit",
		Icon = "💺",
		Length = 3,
		Loop = true,
		FreeHead = true,
		Frames = {
			{
				T = 0,
				Root = { 6, 0, 0, -2 },
				RLeg = { 86, 0, 6 },
				LLeg = { 83, 0, -7 },
				RArm = { -26, 0, 17 },
				LArm = { -26, 0, -17 },
			},
			{
				T = 1.5,
				Root = { 8, 0, 0, -1.97 },
				RLeg = { 86, 0, 6 },
				LLeg = { 83, 0, -7 },
				RArm = { -26, 0, 17 },
				LArm = { -26, 0, -17 },
			},
			{
				T = 3,
				Root = { 6, 0, 0, -2 },
				RLeg = { 86, 0, 6 },
				LLeg = { 83, 0, -7 },
				RArm = { -26, 0, 17 },
				LArm = { -26, 0, -17 },
			},
		},
	},
	Pushups = {
		Name = "Pushups",
		Icon = "🏋",
		Length = 1.2,
		Loop = true,
		Frames = {
			{
				T = 0,
				Root = { -88, 0, 0, -2.3 },
				RArm = { 50, 0, 25 },
				LArm = { 50, 0, -25 },
				RLeg = { 0, 0, 4 },
				LLeg = { 0, 0, -4 },
				Neck = { 40, 0, 0 },
			},
			{
				T = 0.6,
				Root = { -80, 0, 0, -1.6 },
				RArm = { 88, 0, 12 },
				LArm = { 88, 0, -12 },
				RLeg = { 0, 0, 4 },
				LLeg = { 0, 0, -4 },
				Neck = { 35, 0, 0 },
			},
			{
				T = 1.2,
				Root = { -88, 0, 0, -2.3 },
				RArm = { 50, 0, 25 },
				LArm = { 50, 0, -25 },
				RLeg = { 0, 0, 4 },
				LLeg = { 0, 0, -4 },
				Neck = { 40, 0, 0 },
			},
		},
	},
} :: { [string]: Emote }

local function toCFrame(value: { number }?): CFrame
	if not value then
		return CFrame.identity
	end
	return CFrame.new(0, value[4] or 0, 0) * CFrame.Angles(rad(value[1]), rad(value[2]), rad(value[3]))
end

local function smooth(alpha: number): number
	return alpha * alpha * (3 - 2 * alpha)
end

-- Pose at time `t`, plus whether a one-shot emote has finished.
function EmoteLibrary.Sample(emote: Emote, t: number): ({ [string]: CFrame }, boolean)
	local frames = emote.Frames
	local finished = not emote.Loop and t >= emote.Length
	local time = if emote.Loop then t % emote.Length else math.min(t, emote.Length)

	local a, b = frames[1], frames[#frames]
	for i = 1, #frames - 1 do
		if time >= frames[i].T and time <= frames[i + 1].T then
			a, b = frames[i], frames[i + 1]
			break
		end
	end
	local span = b.T - a.T
	local alpha = if span > 0 then (time - a.T) / span else 1
	if emote.Ease ~= "Linear" then
		alpha = smooth(alpha)
	end

	local pose = {}
	for _, joint in JOINTS do
		local from, to = a[joint], b[joint]
		if from or to then
			local va = from or { 0, 0, 0, 0 }
			local vb = to or { 0, 0, 0, 0 }
			local mixed = {}
			for k = 1, 4 do
				mixed[k] = (va[k] or 0) + ((vb[k] or 0) - (va[k] or 0)) * alpha
			end
			pose[joint] = toCFrame(mixed)
		else
			pose[joint] = CFrame.identity
		end
	end
	return pose, finished
end

function EmoteLibrary.Get(name: string): Emote?
	return EmoteLibrary.Emotes[name]
end

return EmoteLibrary

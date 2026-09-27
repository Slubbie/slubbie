-- Keyframed emote animations for R6, plus their sounds and particle effects.
--
-- Each keyframe gives joint rotations in degrees as { x, y, z, dy }:
--   limbs (torso space): +x swings forward, +z swings a RIGHT limb outward
--                        (a LEFT limb goes outward with -z)
--   Root  (body):        +x leans back, +y turns left, +z tilts left, dy moves up
--   Neck:                +x looks up, +y turns left
-- Joints left out of a keyframe relax to their rest pose.
--
-- Frames are joined with time-aware splines, so motion flows through each key
-- instead of stopping at it. Looping emotes end on a copy of their first frame;
-- any drift between the two (like a full 360 turn) carries on smoothly.
-- Animation tips used throughout: anticipation before big moves, a little
-- overshoot on arrival, and offset timing between body parts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local rad = math.rad

export type Frame = { [string]: any }
export type Beat = { T: number, Sound: string }
export type Emote = {
	Name: string,
	Icon: string,
	Length: number,
	Loop: boolean,
	-- "Linear" for constant motion (spins); splines otherwise.
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
	Strum = { Id = Config.Sounds.Ping, Pitch = 0.75, Volume = 0.3 },
	Whoosh = { Id = Config.Sounds.Whoosh, Pitch = 1.3, Volume = 0.35 },
	Yawn = { Id = Config.Sounds.Whoosh, Pitch = 0.45, Volume = 0.3 },
}

local REST: Frame = { RArm = { 0, 0, 4 }, LArm = { 0, 0, -4 } }

-- Copy of `base` with `changes` applied and time `t`.
local function frame(t: number, base: Frame?, changes: Frame?): Frame
	local result: Frame = { T = t }
	for joint, value in base or {} do
		if joint ~= "T" then
			result[joint] = value
		end
	end
	for joint, value in changes or {} do
		result[joint] = value
	end
	return result
end

-- Swap left/right limbs and flip sideways motion: builds the other half of a
-- symmetrical move (dance steps, floss) from the first half.
local function mirror(t: number, source: Frame): Frame
	local function flip(value: { number }?): { number }?
		if not value then
			return nil
		end
		return { value[1], -(value[2] or 0), -(value[3] or 0), value[4] }
	end
	return {
		T = t,
		Root = flip(source.Root),
		Neck = flip(source.Neck),
		RArm = flip(source.LArm),
		LArm = flip(source.RArm),
		RLeg = flip(source.LLeg),
		LLeg = flip(source.RLeg),
	}
end

local grooveA: Frame = {
	Root = { 0, 14, 0, -0.28 },
	RArm = { 78, 0, 28 },
	LArm = { -30, 0, -22 },
	RLeg = { 8, 0, 14 },
	LLeg = { -4, 0, -4 },
	Neck = { -8, -14, 6 },
}
local grooveB: Frame = {
	Root = { 0, 6, 0, -0.02 },
	RArm = { 50, 0, 20 },
	LArm = { 5, 0, -16 },
	RLeg = { 2, 0, 8 },
	LLeg = { 0, 0, -6 },
	Neck = { 4, -6, 2 },
}
local grooveUp: Frame = {
	Root = { 0, 0, 0, 0.08 },
	RArm = { 25, 0, 14 },
	LArm = { 25, 0, -14 },
	RLeg = { 0, 0, 6 },
	LLeg = { 0, 0, -6 },
	Neck = { 8, 0, 0 },
}

local flossA: Frame = {
	RArm = { -30, 0, 36 },
	LArm = { 30, 0, 33 },
	Root = { 0, -6, -10 },
	RLeg = { 0, 0, 9 },
	LLeg = { 0, 0, -3 },
	Neck = { 0, 6, 8 },
}
local flossPass: Frame = {
	RArm = { 0, 0, 6 },
	LArm = { 0, 0, -6 },
	Root = { 0, 0, 0, 0.05 },
	RLeg = { 0, 0, 6 },
	LLeg = { 0, 0, -6 },
}

local cheerCrouch: Frame = {
	Root = { -8, 0, 0, -0.45 },
	RArm = { 40, 0, 112 },
	LArm = { 40, 0, -112 },
	RLeg = { 38, 0, 6 },
	LLeg = { 38, 0, -6 },
	Neck = { 6, 0, 0 },
}

local clapOpen: Frame = { RArm = { 68, 0, 22 }, LArm = { 68, 0, -22 }, Root = { 2, 0, 0 }, Neck = { 8, 0, 0 } }

local salute: Frame = {
	RArm = { 144, 0, -30 },
	LArm = { 0, 0, -2 },
	Root = { 4, 0, 0, 0.04 },
	RLeg = { 0, 0, 1 },
	LLeg = { 0, 0, -1 },
	Neck = { 6, 0, 0 },
}

local bowDown: Frame = {
	Root = { -52, 0, 0, -0.2 },
	RArm = { 45, 0, -42 },
	LArm = { -40, 0, -10 },
	Neck = { -18, 0, 0 },
}

local laughBase: Frame = { Root = { 12, 0, 0 }, RArm = { 49, 0, -24 }, LArm = { 49, 0, 24 }, Neck = { 28, 0, 0 } }

local flexFront: Frame = {
	Root = { 8, 0, 0, -0.15 },
	RArm = { 28, 0, 124 },
	LArm = { 28, 0, -124 },
	RLeg = { 0, 0, 13 },
	LLeg = { 0, 0, -13 },
	Neck = { 10, 0, 0 },
}
local flexRelax: Frame = {
	Root = { 4, 0, 0 },
	RArm = { 12, 0, 98 },
	LArm = { 12, 0, -98 },
	RLeg = { 0, 0, 10 },
	LLeg = { 0, 0, -10 },
	Neck = { 6, 0, 0 },
}
local flexSide: Frame = {
	Root = { 6, 28, 0, -0.1 },
	RArm = { 70, 0, 60 },
	LArm = { 40, 0, -126 },
	RLeg = { 4, 0, 12 },
	LLeg = { -4, 0, -8 },
	Neck = { 8, -20, 0 },
}

local spinPose: Frame = { RArm = { 0, 0, 96 }, LArm = { 0, 0, -96 }, RLeg = { 0, 0, 12 }, LLeg = { 0, 0, -12 } }

local sitPose: Frame = {
	Root = { 6, 0, 0, -2 },
	RLeg = { 86, 0, 6 },
	LLeg = { 83, 0, -7 },
	RArm = { -26, 0, 17 },
	LArm = { -26, 0, -17 },
}

local pushDown: Frame = {
	Root = { -88, 0, 0, -2.3 },
	RArm = { 50, 0, 25 },
	LArm = { 50, 0, -25 },
	RLeg = { 0, 0, 4 },
	LLeg = { 0, 0, -4 },
	Neck = { 40, 0, 0 },
}

local guitar: Frame = {
	Root = { 10, 0, 0, -0.2 },
	LArm = { 72, 0, -32 },
	RArm = { 42, 0, -30 },
	RLeg = { 10, 0, 14 },
	LLeg = { -6, 0, -14 },
	Neck = { -12, 0, 0 },
}

local shrugUp: Frame = {
	Root = { 2, 0, 0, 0.06 },
	RArm = { 22, 0, 42 },
	LArm = { 22, 0, -42 },
	Neck = { 4, 0, 16 },
}

local stretchUp: Frame = {
	Root = { 6, 0, 0, 0.12 },
	RArm = { 0, 0, 172 },
	LArm = { 0, 0, -172 },
	Neck = { 18, 0, 0 },
}

local sleepPose: Frame = {
	Root = { 86, 0, 0, -2.4 },
	RArm = { 160, 0, 30 },
	LArm = { 160, 0, -30 },
	RLeg = { 0, 0, 6 },
	LLeg = { 6, 0, -8 },
	Neck = { -10, 15, 0 },
}

EmoteLibrary.Emotes = {
	Wave = {
		Name = "Wave",
		Icon = "👋",
		Length = 1.1,
		Loop = true,
		FreeHead = true,
		Frames = {
			frame(0, nil, { RArm = { 12, 0, 148 }, LArm = { 0, 0, -6 }, Root = { 0, 0, 3 }, Neck = { 0, 0, -4 } }),
			frame(0.28, nil, { RArm = { 8, -12, 172 }, LArm = { 0, 0, -6 }, Root = { 0, 0, 4 }, Neck = { 2, 0, -6 } }),
			frame(0.55, nil, { RArm = { 12, 0, 146 }, LArm = { 0, 0, -6 }, Root = { 0, 0, 3 }, Neck = { 0, 0, -4 } }),
			frame(0.82, nil, { RArm = { 8, 12, 170 }, LArm = { 0, 0, -6 }, Root = { 0, 0, 4 }, Neck = { 2, 0, -6 } }),
			frame(1.1, nil, { RArm = { 12, 0, 148 }, LArm = { 0, 0, -6 }, Root = { 0, 0, 3 }, Neck = { 0, 0, -4 } }),
		},
	},
	Groove = {
		Name = "Groove",
		Icon = "🕺",
		Length = 1,
		Loop = true,
		Particles = "Notes",
		Frames = {
			frame(0, grooveA),
			frame(0.125, grooveB),
			frame(0.25, grooveUp),
			mirror(0.375, grooveB),
			mirror(0.5, grooveA),
			mirror(0.625, grooveB),
			frame(0.75, grooveUp),
			frame(0.875, grooveB),
			frame(1, grooveA),
		},
	},
	Floss = {
		Name = "Floss",
		Icon = "💃",
		Length = 0.64,
		Loop = true,
		Frames = {
			frame(0, flossA),
			frame(0.16, flossPass),
			mirror(0.32, flossA),
			frame(0.48, flossPass),
			frame(0.64, flossA),
		},
	},
	Cheer = {
		Name = "Cheer",
		Icon = "🎉",
		Length = 1,
		Loop = true,
		Particles = "Confetti",
		Beats = { { T = 0.18, Sound = "Pop" } },
		Frames = {
			frame(0, cheerCrouch),
			frame(0.18, nil, {
				Root = { 4, 0, 0, 1.25 },
				RArm = { 0, 0, 170 },
				LArm = { 0, 0, -170 },
				RLeg = { -16, 0, 14 },
				LLeg = { -16, 0, -14 },
				Neck = { 26, 0, 0 },
			}),
			frame(0.36, nil, {
				Root = { 2, 0, 0, 0.85 },
				RArm = { 10, 0, 158 },
				LArm = { 10, 0, -158 },
				RLeg = { 12, 0, 10 },
				LLeg = { 12, 0, -10 },
				Neck = { 22, 0, 0 },
			}),
			frame(0.56, nil, {
				Root = { -5, 0, 0, -0.25 },
				RArm = { 22, 0, 146 },
				LArm = { 22, 0, -146 },
				RLeg = { 24, 0, 6 },
				LLeg = { 24, 0, -6 },
				Neck = { 14, 0, 0 },
			}),
			frame(0.8, cheerCrouch, { Root = { -6, 0, 0, -0.38 } }),
			frame(1, cheerCrouch),
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
			frame(0, clapOpen),
			frame(0.19, clapOpen, { RArm = { 75, 0, -4 }, LArm = { 75, 0, 4 } }),
			frame(0.25, clapOpen, { RArm = { 78, 0, -15 }, LArm = { 78, 0, 15 }, Root = { 3, 0, 0, -0.04 } }),
			frame(0.33, clapOpen, { RArm = { 74, 0, -1 }, LArm = { 74, 0, 1 } }),
			frame(0.5, clapOpen),
		},
	},
	Salute = {
		Name = "Salute",
		Icon = "🎖",
		Length = 2.7,
		Loop = false,
		Beats = { { T = 0.36, Sound = "Chime" } },
		Frames = {
			frame(0, REST),
			frame(0.18, salute, { RArm = { 96, 0, -18 }, Root = { 0, 0, 0, -0.04 } }),
			frame(0.36, salute, { RArm = { 152, 0, -33 } }),
			frame(0.52, salute),
			frame(2.15, salute),
			frame(2.7, REST),
		},
	},
	Bow = {
		Name = "Bow",
		Icon = "🙇",
		Length = 2.9,
		Loop = false,
		Particles = "Sparkles",
		Frames = {
			frame(0, REST),
			frame(0.22, REST, { RArm = { 55, 0, -34 }, Root = { 3, 0, 0, 0.03 }, Neck = { 4, 0, 0 } }),
			frame(0.62, bowDown, { Root = { -57, 0, 0, -0.22 } }),
			frame(0.8, bowDown),
			frame(2.05, bowDown, { Root = { -50, 0, 0, -0.2 } }),
			frame(2.5, REST, { Root = { 4, 0, 0 }, RArm = { 20, 0, -10 } }),
			frame(2.9, REST),
		},
	},
	Laugh = {
		Name = "Laugh",
		Icon = "😂",
		Length = 1,
		Loop = true,
		Frames = {
			frame(0, laughBase),
			frame(0.12, laughBase, { Root = { 18, 0, 3, -0.08 }, Neck = { 36, 6, 0 } }),
			frame(0.25, laughBase, { Root = { 11, 0, 0 } }),
			frame(0.37, laughBase, { Root = { 18, 0, -3, -0.08 }, Neck = { 36, -6, 0 } }),
			frame(
				0.5,
				laughBase,
				{ Root = { 6, 0, 0 }, RArm = { 55, 0, -20 }, LArm = { 55, 0, 20 }, Neck = { 20, 0, 0 } }
			),
			frame(0.62, laughBase, { Root = { -8, 0, 0, -0.12 }, Neck = { -6, 0, 0 } }),
			frame(0.8, laughBase, { Root = { 4, 0, 0 }, Neck = { 14, 0, 0 } }),
			frame(1, laughBase),
		},
	},
	Flex = {
		Name = "Flex",
		Icon = "💪",
		Length = 2.2,
		Loop = true,
		Particles = "Sparkles",
		Beats = { { T = 0.45, Sound = "Pop" }, { T = 1.35, Sound = "Pop" } },
		Frames = {
			frame(0, flexRelax),
			frame(0.35, flexFront, { RArm = { 30, 0, 130 }, LArm = { 30, 0, -130 } }),
			frame(0.5, flexFront),
			frame(0.85, flexFront, { Root = { 8, 0, 0, -0.12 } }),
			frame(1.15, flexRelax, { Root = { 5, 14, 0 } }),
			frame(1.35, flexSide, { RArm = { 74, 0, 58 }, LArm = { 42, 0, -132 } }),
			frame(1.8, flexSide),
			frame(2.2, flexRelax),
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
			frame(0, spinPose, { Root = { 0, 0, 0, 0.1 } }),
			frame(0.225, spinPose, { Root = { 0, 90, 0, 0.25 }, RArm = { 0, 0, 102 }, LArm = { 0, 0, -102 } }),
			frame(0.45, spinPose, { Root = { 0, 180, 0, 0.1 } }),
			frame(0.675, spinPose, { Root = { 0, 270, 0, 0.25 }, RArm = { 0, 0, 102 }, LArm = { 0, 0, -102 } }),
			frame(0.9, spinPose, { Root = { 0, 360, 0, 0.1 } }),
		},
	},
	Sit = {
		Name = "Sit",
		Icon = "💺",
		Length = 4,
		Loop = true,
		FreeHead = true,
		Frames = {
			frame(0, sitPose),
			frame(1, sitPose, { Root = { 8, 0, 0, -1.97 } }),
			frame(2, sitPose, { LLeg = { 80, 0, -10 } }),
			frame(2.3, sitPose, { LLeg = { 86, 0, -7 } }),
			frame(3, sitPose, { Root = { 8, 0, 0, -1.97 } }),
			frame(4, sitPose),
		},
	},
	Pushups = {
		Name = "Pushups",
		Icon = "🏋",
		Length = 1.2,
		Loop = true,
		Frames = {
			frame(0, pushDown),
			frame(0.5, pushDown, {
				Root = { -80, 0, 0, -1.6 },
				RArm = { 88, 0, 12 },
				LArm = { 88, 0, -12 },
				Neck = { 34, 0, 0 },
			}),
			frame(0.75, pushDown, {
				Root = { -81, 0, 0, -1.65 },
				RArm = { 86, 0, 13 },
				LArm = { 86, 0, -13 },
				Neck = { 35, 0, 0 },
			}),
			frame(1.2, pushDown),
		},
	},
	AirGuitar = {
		Name = "AirGuitar",
		Icon = "🎸",
		Length = 0.8,
		Loop = true,
		Particles = "Notes",
		Beats = { { T = 0.1, Sound = "Strum" }, { T = 0.5, Sound = "Strum" } },
		Frames = {
			frame(0, guitar, { RArm = { 58, 0, -10 } }),
			frame(0.1, guitar, { RArm = { 36, 0, -34 }, Neck = { -24, 0, 0 }, Root = { 12, 0, 0, -0.26 } }),
			frame(0.2, guitar, { RArm = { 56, 0, -12 }, Neck = { -6, 0, 0 } }),
			frame(0.3, guitar, { RArm = { 40, 0, -30 }, Neck = { -18, 0, 0 } }),
			frame(0.4, guitar, { RArm = { 58, 0, -10 }, Neck = { -4, 0, 0 } }),
			frame(0.5, guitar, { RArm = { 36, 0, -34 }, Neck = { -24, 0, 0 }, Root = { 12, 0, 0, -0.26 } }),
			frame(0.6, guitar, { RArm = { 56, 0, -12 }, Neck = { -6, 0, 0 } }),
			frame(0.7, guitar, { RArm = { 40, 0, -30 }, Neck = { -18, 0, 0 } }),
			frame(0.8, guitar, { RArm = { 58, 0, -10 } }),
		},
	},
	Shrug = {
		Name = "Shrug",
		Icon = "🤷",
		Length = 1.8,
		Loop = false,
		FreeHead = true,
		Frames = {
			frame(0, REST),
			frame(0.15, REST, { Root = { 0, 0, 0, -0.05 } }),
			frame(0.42, shrugUp, { RArm = { 24, 0, 46 }, LArm = { 24, 0, -46 }, Root = { 2, 0, 0, 0.09 } }),
			frame(0.6, shrugUp),
			frame(1.3, shrugUp, { Neck = { 4, 0, 12 } }),
			frame(1.8, REST),
		},
	},
	Stretch = {
		Name = "Stretch",
		Icon = "🙆",
		Length = 3.4,
		Loop = false,
		Beats = { { T = 0.6, Sound = "Yawn" } },
		Frames = {
			frame(0, REST),
			frame(0.3, REST, { Root = { -4, 0, 0, -0.08 }, RArm = { 30, 0, 20 }, LArm = { 30, 0, -20 } }),
			frame(0.8, stretchUp),
			frame(1.5, stretchUp, { Root = { 4, 0, 12, 0.08 }, Neck = { 14, 0, 10 } }),
			frame(2.2, stretchUp, { Root = { 4, 0, -12, 0.08 }, Neck = { 14, 0, -10 } }),
			frame(2.7, stretchUp),
			frame(3.4, REST),
		},
	},
	Sleep = {
		Name = "Sleep",
		Icon = "😴",
		Length = 3,
		Loop = true,
		Particles = "Sleep",
		Frames = {
			frame(0, sleepPose),
			frame(1.5, sleepPose, { Root = { 86, 0, 0, -2.34 }, RArm = { 158, 0, 31 }, LArm = { 158, 0, -31 } }),
			frame(3, sleepPose),
		},
	},
} :: { [string]: Emote }

-- Sampling --------------------------------------------------------------------------

-- Cubic Hermite through p1 → p2 with time-aware (Catmull-Rom style) tangents,
-- so velocity stays continuous even when keys are unevenly spaced.
local function spline(
	p0: number,
	p1: number,
	p2: number,
	p3: number,
	t0: number,
	t1: number,
	t2: number,
	t3: number,
	s: number
): number
	local span = t2 - t1
	local m1 = if t2 - t0 > 0 then (p2 - p0) / (t2 - t0) else 0
	local m2 = if t3 - t1 > 0 then (p3 - p1) / (t3 - t1) else 0
	local s2, s3 = s * s, s * s * s
	return (2 * s3 - 3 * s2 + 1) * p1 + (s3 - 2 * s2 + s) * span * m1 + (-2 * s3 + 3 * s2) * p2 + (s3 - s2) * span * m2
end

local function component(f: Frame, joint: string, k: number): number
	local value = f[joint]
	return if value then (value[k] or 0) else 0
end

-- Value of frame `index` (may run past either end). Loops wrap around and keep
-- any drift (a Spin's 360°); one-shots hold their end frames.
local function valueAt(emote: Emote, index: number, joint: string, k: number): number
	local frames = emote.Frames
	local count = #frames
	if not emote.Loop then
		return component(frames[math.clamp(index, 1, count)], joint, k)
	end
	local unique = count - 1 -- the last frame repeats the first
	local cycles = math.floor((index - 1) / unique)
	local wrapped = (index - 1) % unique + 1
	local drift = component(frames[count], joint, k) - component(frames[1], joint, k)
	return component(frames[wrapped], joint, k) + cycles * drift
end

-- Time of frame `index`, continuing past either end like valueAt.
local function timeAt(emote: Emote, index: number): number
	local frames = emote.Frames
	local count = #frames
	if not emote.Loop then
		local clamped = math.clamp(index, 1, count)
		-- Pretend the held end frames sit a little beyond the ends.
		return frames[clamped].T + (index - clamped) * 0.25
	end
	local unique = count - 1
	local cycles = math.floor((index - 1) / unique)
	local wrapped = (index - 1) % unique + 1
	return frames[wrapped].T + cycles * emote.Length
end

-- Pose at time `t` as joint CFrames, plus whether a one-shot emote has finished.
function EmoteLibrary.Sample(emote: Emote, t: number): ({ [string]: CFrame }, boolean)
	local frames = emote.Frames
	local finished = not emote.Loop and t >= emote.Length
	local time = if emote.Loop then t % emote.Length else math.clamp(t, 0, emote.Length)

	local segment = #frames - 1
	for i = 1, #frames - 1 do
		if time <= frames[i + 1].T then
			segment = i
			break
		end
	end
	local a, b = frames[segment], frames[segment + 1]
	local span = b.T - a.T
	local alpha = if span > 0 then math.clamp((time - a.T) / span, 0, 1) else 1

	local pose = {}
	for _, joint in JOINTS do
		local values = {}
		for k = 1, 4 do
			if emote.Ease == "Linear" then
				local from = valueAt(emote, segment, joint, k)
				values[k] = from + (valueAt(emote, segment + 1, joint, k) - from) * alpha
			else
				values[k] = spline(
					valueAt(emote, segment - 1, joint, k),
					valueAt(emote, segment, joint, k),
					valueAt(emote, segment + 1, joint, k),
					valueAt(emote, segment + 2, joint, k),
					timeAt(emote, segment - 1),
					timeAt(emote, segment),
					timeAt(emote, segment + 1),
					timeAt(emote, segment + 2),
					alpha
				)
			end
		end
		pose[joint] = CFrame.new(0, values[4], 0) * CFrame.Angles(rad(values[1]), rad(values[2]), rad(values[3]))
	end
	return pose, finished
end

function EmoteLibrary.Get(name: string): Emote?
	return EmoteLibrary.Emotes[name]
end

return EmoteLibrary

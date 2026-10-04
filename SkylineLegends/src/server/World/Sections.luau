-- The section library: short, self-contained obstacle sequences used by the
-- Spire challenge tower and the endless Dreamline.
--
-- Every section is made of CourseBuilder segments, whose sizes come from the
-- movement envelope (Logic/Reach), and difficulty only scales parameters within
-- the ranges validated by tools/headless/test_world.luau. That keeps endlessly
-- assembled routes physically achievable.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rotation = require(ReplicatedStorage.Shared.Logic.Rotation)

export type Section = {
	Id: string,
	Min: number, -- minimum difficulty (1..10)
	Requires: string?,
	Length: number, -- rough forward length, for fitting floors
	Rise: number, -- rough net height change
	Make: (Rotation.Rng, number) -> { any },
}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * math.clamp(t, 0, 1)
end

local function side(rng: Rotation.Rng): string
	return if rng:Next() < 0.5 then "L" else "R"
end

local Sections = {}

Sections.Library = {
	{
		Id = "hops",
		Min = 1,
		Length = 40,
		Rise = 2,
		Make = function(rng, d)
			return {
				{ "Gap", lerp(0.45, 0.85, d / 10) },
				{ "Gap", lerp(0.45, 0.82, d / 10), Rise = rng:Int(-2, 3) },
			}
		end,
	},
	{
		Id = "vaults",
		Min = 1,
		Length = 52,
		Rise = 0,
		Make = function(_, d)
			return { { "Vault", if d > 5 then 3 else 2 }, { "Slide", 1 } }
		end,
	},
	{
		Id = "ledge",
		Min = 1,
		Length = 20,
		Rise = 8,
		Make = function(_, d)
			return { { "Ledge", lerp(6, 11, d / 10) } }
		end,
	},
	{
		Id = "climb",
		Min = 1,
		Length = 20,
		Rise = 12,
		Make = function(rng, d)
			return { { "Climb", lerp(8, 16, d / 10), Type = if rng:Next() < 0.5 then "Ladder" else "Mesh" } }
		end,
	},
	{
		Id = "balance",
		Min = 1,
		Length = 34,
		Rise = 0,
		Make = function(_, d)
			return { { "Balance", lerp(16, 30, d / 10) } }
		end,
	},
	{
		Id = "zip",
		Min = 1,
		Length = 50,
		Rise = -6,
		Make = function()
			return { { "Zip", 34, Drop = 6 } }
		end,
	},
	{
		Id = "drop",
		Min = 1,
		Length = 21,
		Rise = -10,
		Make = function(_, d)
			return { { "Drop", lerp(8, 14, d / 10) } }
		end,
	},
	{
		Id = "wallrun",
		Min = 2,
		Length = 40,
		Rise = -4,
		Make = function(rng, d)
			return { { "WallRun", lerp(0.6, 1.1, d / 10), Side = side(rng) } }
		end,
	},
	{
		Id = "rope",
		Min = 2,
		Length = 34,
		Rise = 0,
		Make = function(_, d)
			return { { "Rope", if d > 6 then 2 else 1 } }
		end,
	},
	{
		Id = "bounce",
		Min = 2,
		Length = 24,
		Rise = 12,
		Make = function(_, d)
			return { { "Bounce", lerp(10, 18, d / 10) } }
		end,
	},
	{
		Id = "shaft",
		Min = 3,
		Length = 26,
		Rise = 14,
		Make = function(_, d)
			return { { "Shaft", lerp(10, 18, d / 10) } }
		end,
	},
	{
		Id = "collapse",
		Min = 3,
		Length = 34,
		Rise = 0,
		Make = function(_, d)
			return { { "Collapse", lerp(16, 26, d / 10) } }
		end,
	},
	{
		Id = "doors",
		Min = 3,
		Length = 30,
		Rise = 0,
		Make = function()
			return { { "Doors", 2 } }
		end,
	},
	{
		Id = "movers",
		Min = 4,
		Length = 35,
		Rise = 0,
		Make = function(rng)
			return { { "Movers", 1, Mode = if rng:Next() < 0.5 then "Linear" else "Pendulum" } }
		end,
	},
	{
		Id = "lasers",
		Min = 4,
		Length = 32,
		Rise = 0,
		Make = function(rng)
			return { { "Lasers", 2, Pattern = rng:Pick({ "Sweep", "Alternate", "Grid" }) } }
		end,
	},
	{
		Id = "holo",
		Min = 5,
		Length = 40,
		Rise = 0,
		Make = function()
			return { { "Holo", 2 } }
		end,
	},
	{
		Id = "tictac",
		Min = 5,
		Length = 52,
		Rise = -2,
		Make = function(rng)
			return { { "TicTac", 2, Side = side(rng) } }
		end,
	},
	{
		Id = "spinner",
		Min = 6,
		Length = 40,
		Rise = 0,
		Make = function(rng)
			return { { "Spinner", Mode = if rng:Next() < 0.5 then "Sweeper" else "Platform" } }
		end,
	},
	{
		Id = "double",
		Min = 4,
		Requires = "DoubleJump",
		Length = 36,
		Rise = 2,
		Make = function(rng, d)
			return { { "DoubleGap", lerp(0.45, 0.85, d / 10), Rise = rng:Int(0, 3) } }
		end,
	},
	{
		Id = "dash",
		Min = 6,
		Requires = "Dash",
		Length = 38,
		Rise = 0,
		Make = function(_, d)
			return { { "DashGap", lerp(0.45, 0.85, d / 10) } }
		end,
	},
	{
		Id = "grapple",
		Min = 6,
		Requires = "Grapple",
		Length = 46,
		Rise = 0,
		Make = function()
			return { { "Grapple", 1 } }
		end,
	},
	{
		Id = "pull",
		Min = 7,
		Requires = "GrapplePull",
		Length = 24,
		Rise = 16,
		Make = function()
			return { { "Pull", 15 } }
		end,
	},
	{
		Id = "lowgrav",
		Min = 7,
		Length = 50,
		Rise = 0,
		Make = function()
			return { { "LowGrav", 34 } }
		end,
	},
} :: { Section }

-- Sections available at a difficulty with a set of abilities.
function Sections.Available(difficulty: number, abilities: { [string]: boolean }?): { Section }
	local result = {}
	for _, section in Sections.Library do
		if section.Min <= difficulty and (not section.Requires or not abilities or abilities[section.Requires]) then
			table.insert(result, section)
		end
	end
	return result
end

-- Pick sections that fit a length budget and keep height change in bounds.
function Sections.Fill(
	rng: Rotation.Rng,
	difficulty: number,
	abilities: { [string]: boolean }?,
	budget: number,
	maxRise: number
): ({ any }, { string })
	local pool = Sections.Available(difficulty, abilities)
	local segments, ids = {}, {}
	local used, rise = 0, 0
	local attempts = 0
	while used < budget * 0.6 and attempts < 30 do
		attempts += 1
		local section = rng:Pick(pool)
		if
			used + section.Length <= budget
			and math.abs(rise + section.Rise) <= maxRise
			and not table.find(ids, section.Id)
		then
			for _, seg in section.Make(rng, difficulty) do
				table.insert(segments, seg)
			end
			table.insert(ids, section.Id)
			used += section.Length
			rise += section.Rise
		end
	end
	return segments, ids
end

return Sections

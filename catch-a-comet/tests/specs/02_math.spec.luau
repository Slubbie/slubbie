-- Economy, odds and capture math.

local Loader = require("../harness/Loader")
local Mock = require("../harness/Mock")
local T = require("../harness/T")

return function()
	local loader = Loader.new(".")
	local function shared(name: string): any
		return loader:require("Shared." .. name)
	end
	local EconomyMath = shared("EconomyMath")
	local RarityConfig = shared("RarityConfig")
	local CaptureMath = shared("CaptureMath")
	local GameConfig = shared("GameConfig")
	local Format = shared("Format")

	T.Suite("Economy math")

	T.Case("creature income = base × mutation × bond", function()
		T.Equal(EconomyMath.CreatureIncome({ Species = "Pebblepuff", Mutation = "Standard", Bond = 1 }), 1)
		T.Near(EconomyMath.CreatureIncome({ Species = "AuroraLynx", Mutation = "Aurora", Bond = 1 }), 9 * 1.1, 1e-9)
		T.Near(
			EconomyMath.CreatureIncome({ Species = "AstralGryphon", Mutation = "Prismatic", Bond = 3 }),
			90 * 1.25 * 1.2,
			1e-9
		)
		T.Equal(
			EconomyMath.CreatureIncome({ Species = "Unknown", Mutation = "Standard", Bond = 1 }),
			0,
			"unknown species earns nothing"
		)
	end)

	T.Case("sanctuary income sums deployed creatures only", function()
		local creatures = {
			a = { Species = "Pebblepuff", Mutation = "Standard", Bond = 1 },
			b = { Species = "CometFox", Mutation = "Charged", Bond = 1 },
			c = { Species = "TheFirstStar", Mutation = "Standard", Bond = 1 },
		}
		local rate = EconomyMath.SanctuaryIncome(creatures, { ["1"] = "a", ["2"] = "b" })
		T.Near(rate, 1 + 3 * 1.05, 1e-9)
	end)

	T.Case("XP rolls over levels and stops at the cap", function()
		local level, xp, gained = EconomyMath.AddXP(1, 90, 20)
		T.Equal(level, 2)
		T.Equal(xp, 10)
		T.Equal(gained, 1)
		level, xp, gained = EconomyMath.AddXP(1, 0, 742)
		T.Equal(level, 5, "742 XP from level 1 reaches level 5")
		T.Equal(xp, 0)
		T.Equal(gained, 4)
		level, xp = EconomyMath.AddXP(49, 0, 10 ^ 9)
		T.Equal(level, 50)
		T.Equal(xp, 0)
	end)

	T.Case("capture rewards scale with rank and comet type, never negative", function()
		local bronze = EconomyMath.CaptureReward("DawnCommons", "Ember", 0.3)
		local perfect, xp, rank = EconomyMath.CaptureReward("DawnCommons", "Ember", 0.95)
		T.Equal(bronze, 20)
		T.Equal(perfect, 40)
		T.Equal(rank, "Perfect")
		T.Equal(xp, math.floor(45 * 1.35 + 0.5))
		local nova = EconomyMath.CaptureReward("DawnCommons", "Nova", 0.3)
		T.Equal(nova, 36)
	end)

	T.Case("offline earnings: 25% for up to two hours, nothing for short absences", function()
		local amount, counted = EconomyMath.OfflineEarnings(10, 60)
		T.Equal(amount, 0, "under five minutes")
		amount, counted = EconomyMath.OfflineEarnings(10, 3600)
		T.Equal(amount, 9000)
		T.Equal(counted, 3600)
		amount, counted = EconomyMath.OfflineEarnings(10, 10 * 3600)
		T.Equal(amount, 18000, "capped at two hours")
		T.Equal(counted, 7200)
		T.Equal(EconomyMath.OfflineEarnings(0, 7200), 0)
	end)

	T.Suite("Rarity rolls")

	T.Case("weighted picks follow the table over many rolls", function()
		local rng = Mock.Random.new(42)
		local counts = {}
		local n = 200000
		for _ = 1, n do
			local id = RarityConfig.RollRarity(rng)
			counts[id] = (counts[id] or 0) + 1
		end
		for _, odd in RarityConfig.GetRarityOdds() do
			local observed = (counts[odd.Id] or 0) / n
			local sigma = math.sqrt(odd.Chance * (1 - odd.Chance) / n)
			T.Near(observed, odd.Chance, 5 * sigma + 1e-4, odd.Id)
		end
	end)

	T.Case("modifiers renormalize and the displayed odds stay exact", function()
		local odds = RarityConfig.GetRarityOdds({ Rarity = { Epic = 2 } })
		local total = 0
		local epic = 0
		for _, odd in odds do
			total += odd.Chance
			if odd.Id == "Epic" then
				epic = odd.Chance
			end
		end
		T.Near(total, 1, 1e-9)
		T.Near(epic, 10 / 105, 1e-9)
	end)

	T.Case("edge rolls land on the first and last entries", function()
		T.Equal(RarityConfig.RollRarity(Mock.ScriptedRandom({ 0 })), "Common")
		T.Equal(RarityConfig.RollRarity(Mock.ScriptedRandom({ 0.99999999 })), "Mythic")
		T.Equal(RarityConfig.RollMutation(Mock.ScriptedRandom({ 0.9999999 })), "Prismatic")
	end)

	T.Suite("Capture math")

	local params = CaptureMath.BuildParams(123456)

	T.Case("parameters are deterministic for a seed", function()
		local again = CaptureMath.BuildParams(123456)
		T.Equal(CaptureMath.ZoneCenter(params, 1), CaptureMath.ZoneCenter(again, 1))
		T.Equal(CaptureMath.BandCenter(params, 2, 0.7), CaptureMath.BandCenter(again, 2, 0.7))
		T.True(CaptureMath.ZoneCenter(params, 1) ~= CaptureMath.ZoneCenter(params, 2), "retries move the zone")
	end)

	T.Case("lock scores 1.0 at the centre, 0.55 at the edge, misses outside", function()
		local center = CaptureMath.ZoneCenter(params, 1)
		local function at(angle: number): number
			return angle / 360 * params.DialPeriod
		end
		local hit = CaptureMath.ScoreLock(params, 1, at(center))
		T.True(hit.Hit)
		T.Near(hit.Score, 1, 1e-6)
		local edge = CaptureMath.ScoreLock(params, 1, at(center + params.ZoneHalfWidth - 1e-6))
		T.True(edge.Hit)
		T.Near(edge.Score, 0.55, 1e-3)
		local early = CaptureMath.ScoreLock(params, 1, at(center - params.ZoneHalfWidth - 5))
		T.False(early.Hit)
		T.Equal(early.Reason, "Early")
		local late = CaptureMath.ScoreLock(params, 1, at(center + params.ZoneHalfWidth + 5))
		T.Equal(late.Reason, "Late")
		T.Equal(CaptureMath.ScoreLock(params, 1, 0.01).Reason, "TooFast")
		T.Equal(CaptureMath.ScoreLock(params, 1, params.StageTimeout + 1).Reason, "Timeout")
	end)

	T.Case("holding charges the meter; holding too long overcharges", function()
		local level, over = CaptureMath.ChargeLevel(params, params.ChargeTime)
		T.Near(level, 1, 1e-9)
		T.False(over)
		local _, overcharged = CaptureMath.ChargeLevel(params, params.OverchargeTime + 0.01)
		T.True(overcharged)
		T.Equal(CaptureMath.ScoreRelease(params, 1, 0, params.OverchargeTime + 0.1).Reason, "Overcharged")
		T.Equal(CaptureMath.ScoreRelease(params, 1, 0.5, 0.5).Reason, "TooFast")
	end)

	T.Case("quality combines both stages, misses cost, and the cap applies", function()
		T.Near(CaptureMath.FinalQuality(params, 1, 1, 0), 1, 1e-9)
		T.Near(CaptureMath.FinalQuality(params, 1, 1, 2), 0.9, 1e-9)
		local easy = CaptureMath.BuildParams(1, { QualityCap = GameConfig.Capture.EasyQualityCap })
		T.True(CaptureMath.FinalQuality(easy, 1, 1, 0) < 0.9, "Easy Capture can't reach Perfect")
		local tethered = CaptureMath.BuildParams(1, { QualityBonus = 0.08 })
		T.Near(CaptureMath.FinalQuality(tethered, 0.6, 0.6, 0), 0.68, 1e-9)
	end)

	T.Case("latency tolerance is bounded", function()
		T.Equal(CaptureMath.LatencyTolerance(0), GameConfig.Capture.LatencyBase)
		T.Equal(CaptureMath.LatencyTolerance(5), GameConfig.Capture.LatencyMax)
	end)

	T.Suite("Formatting")

	T.Case("numbers and durations", function()
		T.Equal(Format.Number(1234567), "1,234,567")
		T.Equal(Format.Number(999), "999")
		T.Equal(Format.Short(999), "999")
		T.Equal(Format.Short(1000), "1K")
		T.Equal(Format.Short(1250), "1.25K")
		T.Equal(Format.Short(12500), "12.5K")
		T.Equal(Format.Short(1500000), "1.5M")
		T.Equal(Format.Duration(45), "45s")
		T.Equal(Format.Duration(125), "2m 05s")
		T.Equal(Format.Duration(4380), "1h 13m")
		T.Equal(Format.Percent(0.55), "55%")
		T.Equal(Format.Percent(0.017), "1.7%")
		T.Equal(Format.Percent(0.003), "0.3%")
		T.Equal(Format.Percent(0.001), "0.1%")
		T.Equal(Format.Rate(3.15), "3.1")
	end)
end

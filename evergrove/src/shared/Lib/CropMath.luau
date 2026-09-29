-- Crop growth, moisture, nutrients, mutations and afflictions.
--
-- Everything is timestamp based. Advance(tile, crop, env, t0, t1, random)
-- moves a crop from game time t0 to t1 in a few analytic chunks (split at
-- weather-slot boundaries and at dawn, when sprinklers fire), so the same
-- function handles a 4-second live tick and a 12-hour offline catch-up
-- without simulating every second.
--
-- Saved tile fields:  W moisture · H health · N P K nutrients · Am amendments · Lf last family
-- Saved crop fields:  Id · P progress 0-1 · T last update · At planted · G genes · Lt latent
--                     M mutations · Wg good-water secs · Tt total secs · Cs climate secs
--                     Fe fertilizer id · Pr pruned · Af affliction · Rp ripe time · Hv harvests
--
-- `random` is only passed on the server; without it nothing random happens
-- (the client uses this module to preview growth times and quality).

local Config = script.Parent.Parent.Config
local CropsConfig = require(Config.Crops)
local Soil = require(Config.Soil)
local Mutations = require(Config.Mutations)
local QualityConfig = require(Config.Quality)
local TimeConfig = require(Config.Time)
local GameTime = require(script.Parent.GameTime)
local WeatherMath = require(script.Parent.WeatherMath)
local Registry = require(script.Parent.Registry)
local Genetics = require(script.Parent.Genetics)
local QualityMath = require(script.Parent.QualityMath)

local HOUR = GameTime.HOUR
local SLOT = TimeConfig.WeatherSlotHours * HOUR
local DAWN = TimeConfig.MorningHour

local CropMath = {}

export type Env = {
	Tags: { [string]: boolean },
	Indoor: boolean,
	Climate: boolean,
	Hydroponic: boolean,
	Sprinkler: number, -- 0 none · 1 waters at dawn · 2 keeps moist
	GrowthBonus: number, -- skills + companions + passives (fraction)
	QualityBonus: number,
	MutationMult: number,
	MutationBonus: { [string]: number }, -- per mutation (neighbours, placeables)
	PestMult: number,
	BlightMult: number,
	RetainBonus: number,
	Afflictions: boolean,
	MaxMutations: number,
	Region: any?, -- region def for regional weather (farms use none)
	WeatherAt: ((number) -> string)?,
}

function CropMath.DefaultEnv(): Env
	return {
		Tags = {},
		Indoor = false,
		Climate = false,
		Hydroponic = false,
		Sprinkler = 0,
		GrowthBonus = 0,
		QualityBonus = 0,
		MutationMult = 1,
		MutationBonus = {},
		PestMult = 1,
		BlightMult = 1,
		RetainBonus = 0,
		Afflictions = true,
		MaxMutations = Mutations.MaxPerCrop,
	}
end

local HEAT = { Heatwave = true, Sandstorm = true }
local COLD = { ColdSnap = true, Snow = true, Blizzard = true }
local WET = { Thunderstorm = true, Hail = true, ArcaneStorm = true }
local WIND = { Windy = true, Blizzard = true, Sandstorm = true }

local NEED_DRAIN = { Low = 0.7, Medium = 1, High = 1.3 }

local mutationById = {}
for _, m in Mutations.List do
	mutationById[m.Id] = m
end

function CropMath.WeatherAt(env: Env, t: number): string
	if env.WeatherAt then
		return env.WeatherAt(t)
	end
	return WeatherMath.ForRegion(WeatherMath.Current(t), env.Region)
end

function CropMath.StageOf(progress: number): number
	local stage = 1
	for i, threshold in CropsConfig.Stages do
		if progress >= threshold then
			stage = i
		end
	end
	return stage
end

function CropMath.InSeason(crop: any, seasonId: string): boolean
	for _, s in crop.Seasons do
		if s == seasonId or s == "Any" then
			return true
		end
	end
	return false
end

-- Does the tile satisfy the crop's Needs ("A|B" = any of)?
function CropMath.NeedsMet(crop: any, env: Env): boolean
	if not crop.Needs then
		return true
	end
	for option in string.gmatch(crop.Needs, "[^|]+") do
		if env.Tags[option] then
			return true
		end
	end
	return false
end

-- 0-1: how well the tile's nutrients cover the crop's demand.
function CropMath.NutrientBalance(tile: any, crop: any): number
	local npk = crop.NPK
	local total = npk.N + npk.P + npk.K
	if total <= 0 then
		return 1
	end
	local shortfall = 0
	for key, demand in npk do
		local level = (tile[key] or 50) / 100
		shortfall += (demand / total) * math.max(0, 0.5 - level) * 2
	end
	return math.clamp(1 - shortfall, 0, 1)
end

-- Weather tolerance factor for growth/climate (0.5-1). Hardiness gene helps.
local function tolerance(crop: any, weatherId: string, hardiness: number): number
	local tol = crop.Tolerance
	local function f(value: number): number
		return math.clamp(value + hardiness, 0, 1)
	end
	if HEAT[weatherId] then
		return 0.55 + 0.45 * f(tol.Heat)
	elseif COLD[weatherId] then
		return 0.55 + 0.45 * f(tol.Cold)
	elseif WET[weatherId] then
		return 0.7 + 0.3 * f(tol.Wet)
	elseif WIND[weatherId] then
		return 0.8 + 0.2 * f(tol.Wind)
	end
	return 1
end

local function fertOf(cs: any)
	return if cs.Fe then Registry.Fertilizers[cs.Fe] else nil
end

-- Growth multiplier (excluding moisture) at a moment.
function CropMath.GrowthMultiplier(tile: any, cs: any, env: Env, weatherId: string, info: any): number
	local crop = Registry.Crops[cs.Id]
	local mult = 1
	local weather = WeatherMath.Def(weatherId)

	-- Season
	if not CropMath.InSeason(crop, info.SeasonId) then
		if env.Climate then
			mult *= 1
		elseif env.Indoor then
			mult *= CropsConfig.GreenhouseGrowth
		else
			mult *= CropsConfig.OffSeasonGrowth
		end
	end

	-- Weather (outdoors, softened indoors)
	local hardiness = Genetics.Hardiness(cs.G)
	if env.Indoor then
		mult *= 1 + (weather.Growth - 1) * 0.3
	else
		mult *= weather.Growth * tolerance(crop, weatherId, hardiness)
	end

	-- Night crops
	if crop.Night and not info.IsNight then
		mult *= CropsConfig.NightCropDayGrowth
	end

	-- Needs
	if not CropMath.NeedsMet(crop, env) then
		mult *= CropsConfig.UnmetNeedsGrowth
	end

	-- Soil
	if not env.Hydroponic then
		mult *= 0.85 + 0.3 * math.clamp((tile.H or 50) / 100, 0, 1)
		mult *= 0.8 + 0.2 * CropMath.NutrientBalance(tile, crop)
	else
		mult *= 1.3
	end

	-- Afflictions
	if cs.Af then
		local aff = Soil.Afflictions[cs.Af]
		mult *= if aff then aff.Growth else 1
	end

	-- Crop specials
	if cs.Id == "stormcorn" and (weatherId == "Thunderstorm" or weatherId == "ArcaneStorm") then
		mult *= 2
	elseif cs.Id == "ember_pepper" and weatherId == "Heatwave" then
		mult *= 1.5
	elseif cs.Id == "rice" and env.Tags.Riverside then
		mult *= 1.3
	elseif crop.Family == "Fungus" and (env.Tags.Dark or env.Tags.Underground) then
		mult *= 2
	end

	-- Bonuses: fertilizer, genes, skills/companions
	local fert = fertOf(cs)
	local bonus = env.GrowthBonus + (if fert and fert.Speed then fert.Speed else 0)
	mult *= (1 + bonus) * Genetics.GrowthMult(cs.G)

	return math.max(0, mult)
end

-- Base progress per second (first growth or regrowth).
function CropMath.BaseRate(cs: any): number
	local crop = Registry.Crops[cs.Id]
	if (cs.Hv or 0) > 0 and crop.Regrow then
		return (1 - CropsConfig.RegrowFrom) / crop.Regrow
	end
	return 1 / crop.Grow
end

local function band(crop: any)
	return Soil.WaterBands[crop.Water] or Soil.WaterBands.Medium
end

function CropMath.DrainPerSecond(cs: any, env: Env, weatherId: string): number
	if env.Hydroponic then
		return 0
	end
	local crop = Registry.Crops[cs.Id]
	local weather = WeatherMath.Def(weatherId)
	local drain = Soil.DrainPerHour / HOUR * (NEED_DRAIN[crop.Water] or 1)
	if not env.Indoor then
		drain *= weather.Drain
	end
	local fert = fertOf(cs)
	local retain = math.clamp((if fert and fert.Retain then fert.Retain else 0) + env.RetainBonus, 0, 0.85)
	return drain * (1 - retain)
end

-- Chance per in-game hour of a mutation for this crop right now.
function CropMath.MutationChance(mutation: any, cs: any, env: Env, weatherId: string, info: any): number
	if mutation.OnHarvest then
		return 0
	end
	local chance = mutation.Base
	if mutation.FullMoon and info.FullMoon and info.IsNight then
		chance += mutation.FullMoon
	end
	if chance <= 0 then
		return 0
	end
	local weather = WeatherMath.Def(weatherId)
	local weatherMult = (weather.Mutations[mutation.Id] or 1)
		* ((mutation.Weather and mutation.Weather[weatherId]) or 1)
	if env.Indoor then
		weatherMult = 1 + (weatherMult - 1) * 0.5
	end
	chance *= weatherMult
	if mutation.Night and info.IsNight then
		chance *= mutation.Night
	end
	if mutation.Regions then
		for tag, mult in mutation.Regions do
			if env.Tags[tag] then
				chance *= mult
			end
		end
	end
	chance *= env.MutationBonus[mutation.Id] or 1
	local fert = fertOf(cs)
	if fert then
		chance *= (fert.Mutations and fert.Mutations[mutation.Id] or 1) * (fert.AllMutations or 1)
	end
	if cs.Lt == mutation.Id then
		chance *= Mutations.LatentMultiplier
	end
	-- Crop specials
	if cs.Id == "rainbow_fruit" and mutation.Id == "Rainbow" then
		chance *= 5
	elseif cs.Id == "stormcorn" and mutation.Id == "Charged" then
		chance *= 3
	end
	-- Golden hour for Sunkissed
	if mutation.Id == "Sunkissed" and not (info.Hour >= 16.5 and info.Hour < 19) then
		chance *= 0.15
	end
	if mutation.Id == "Dewy" and not (info.Hour >= 4.5 and info.Hour < 8) then
		chance *= 0.2
	end
	return math.clamp(chance * env.MutationMult, 0, 0.9)
end

local function hasGroupConflict(cs: any, mutation: any): boolean
	if not mutation.Group or not cs.M then
		return false
	end
	for _, id in cs.M do
		local other = mutationById[id]
		if other and other.Group == mutation.Group then
			return true
		end
	end
	return false
end

local function countBase(cs: any): number
	local n = 0
	for _, id in cs.M or {} do
		if mutationById[id] then
			n += 1
		end
	end
	return n
end

-- Adds any combos whose requirements are now met. Returns newly added combos.
function CropMath.ResolveCombos(cs: any): { string }
	local added = {}
	cs.M = cs.M or {}
	local has = {}
	for _, id in cs.M do
		has[id] = true
	end
	for _, combo in Mutations.Combos do
		if not has[combo.Id] then
			local ok = true
			for _, req in combo.Requires do
				if not has[req] then
					ok = false
					break
				end
			end
			if ok then
				table.insert(cs.M, combo.Id)
				has[combo.Id] = true
				table.insert(added, combo.Id)
			end
		end
	end
	return added
end

-- Try to add a mutation (respecting groups and the cap). Returns true if added.
function CropMath.AddMutation(cs: any, id: string, env: Env?): boolean
	local mutation = mutationById[id]
	if not mutation then
		return false
	end
	cs.M = cs.M or {}
	if table.find(cs.M, id) or hasGroupConflict(cs, mutation) then
		return false
	end
	if countBase(cs) >= ((env and env.MaxMutations) or Mutations.MaxPerCrop) then
		return false
	end
	table.insert(cs.M, id)
	return true
end

local function climateFit(crop: any, cs: any, env: Env, weatherId: string, info: any): number
	local seasonFit
	if CropMath.InSeason(crop, info.SeasonId) or env.Climate then
		seasonFit = 1
	elseif env.Indoor then
		seasonFit = 0.7
	else
		seasonFit = 0.3
	end
	local weatherFit = if env.Indoor then 1 else tolerance(crop, weatherId, Genetics.Hardiness(cs.G))
	return seasonFit * weatherFit
end

export type Events = {
	Ripened: boolean,
	Mutations: { string },
	Combos: { string },
	Afflicted: string?,
	Stage: number,
}

-- Advance a crop from t0 to t1. Mutates tile and cs. Returns what happened.
function CropMath.Advance(tile: any, cs: any, env: Env, t0: number, t1: number, random: Random?): Events
	local events: Events =
		{ Ripened = false, Mutations = {}, Combos = {}, Afflicted = nil, Stage = CropMath.StageOf(cs.P or 0) }
	local crop = Registry.Crops[cs.Id]
	if not crop or t1 <= t0 then
		cs.T = math.max(cs.T or t0, t1)
		return events
	end
	local waterBand = band(crop)
	local t = t0
	local guard = 0
	while t < t1 and guard < 400 do
		guard += 1
		-- Next boundary: weather slot end or next dawn.
		local slotEnd = (GameTime.SlotOf(t) + 1) * SLOT
		local dawnIn = GameTime.UntilHour(DAWN, t)
		local chunkEnd = math.min(t1, slotEnd, t + dawnIn)
		if chunkEnd <= t then
			chunkEnd = math.min(t1, t + 1)
		end
		local dt = chunkEnd - t
		local mid = t + dt / 2
		local info = GameTime.Info(mid)
		local weatherId = CropMath.WeatherAt(env, mid)
		local weather = WeatherMath.Def(weatherId)

		-- Moisture ---------------------------------------------------------------------------
		local w = tile.W or 0
		if env.Hydroponic then
			w = 100
		elseif weather.Waters and not env.Indoor then
			w = 100
		elseif env.Sprinkler >= 2 then
			w = math.max(w, 80)
		end
		local drain = CropMath.DrainPerSecond(cs, env, weatherId)
		if env.Sprinkler >= 2 or (weather.Waters and not env.Indoor) then
			drain = 0
		end
		local good
		if drain <= 0 then
			good = if w >= waterBand.Min then dt else 0
		else
			good = if w >= waterBand.Min then math.min(dt, (w - waterBand.Min) / drain) else 0
		end
		-- Soggy soil above the band (only matters for Low-water crops) counts at 60%.
		local soggy = 0
		if w > waterBand.Max then
			soggy = if drain <= 0 then dt else math.min(dt, (w - waterBand.Max) / drain)
		end
		local goodCredit = good - soggy * 0.4
		w = math.max(0, w - drain * dt)

		-- Growth -------------------------------------------------------------------------------
		local growing = (cs.P or 0) < 1
		if growing then
			local rate = CropMath.BaseRate(cs) * CropMath.GrowthMultiplier(tile, cs, env, weatherId, info)
			local before = cs.P or 0
			local effective = good + (dt - good) * Soil.DryGrowth
			cs.P = math.min(1, before + rate * effective)
			local gained = cs.P - before
			-- Nutrients consumed in proportion to growth.
			if not env.Hydroponic and gained > 0 then
				local total = crop.NPK.N + crop.NPK.P + crop.NPK.K
				for key, demand in crop.NPK do
					local use = Soil.NutrientUse * gained * (if total > 0 then demand / total else 0) * 3
					tile[key] = math.clamp((tile[key] or 50) - use, 0, 100)
				end
			end
			if cs.P >= 1 and before < 1 then
				-- Estimate the moment it ripened within the chunk.
				local fraction = if gained > 0 then (1 - before) / gained else 1
				cs.Rp = t + dt * math.clamp(fraction, 0, 1)
				events.Ripened = true
			end
			-- Care tracking (only while growing).
			cs.Tt = (cs.Tt or 0) + dt
			cs.Wg = (cs.Wg or 0) + math.max(0, goodCredit)
			cs.Cs = (cs.Cs or 0) + dt * climateFit(crop, cs, env, weatherId, info)

			-- Random events (server only) -------------------------------------------------------------
			if random then
				local hours = dt / HOUR
				for _, mutation in Mutations.List do
					if not (cs.M and table.find(cs.M, mutation.Id)) and not hasGroupConflict(cs, mutation) then
						local c = CropMath.MutationChance(mutation, cs, env, weatherId, info)
						if c > 0 then
							local p = 1 - (1 - c) ^ hours
							if random:NextNumber() < p and CropMath.AddMutation(cs, mutation.Id, env) then
								table.insert(events.Mutations, mutation.Id)
							end
						end
					end
				end
				if #events.Mutations > 0 then
					for _, combo in CropMath.ResolveCombos(cs) do
						table.insert(events.Combos, combo)
					end
				end
				if env.Afflictions and not cs.Af then
					for id, aff in Soil.Afflictions do
						local protected = env.Tags[aff.Protect] == true
						if not protected then
							local c = aff.ChancePerHour
								* (aff.Seasons[info.SeasonId] or 1)
								* (aff.Weather[weatherId] or 1)
							c *= if id == "Pests" then env.PestMult else env.BlightMult
							c *= math.max(0.1, 1 - Genetics.Hardiness(cs.G) * 2)
							if env.Indoor then
								c *= 0.3
							end
							if random:NextNumber() < 1 - (1 - c) ^ hours then
								cs.Af = id
								events.Afflicted = id
								break
							end
						end
					end
				end
			end
		end

		-- Dawn sprinklers fire at the end of this chunk if it ends at dawn.
		if env.Sprinkler >= 1 and math.abs(GameTime.HourOf(chunkEnd) - DAWN) < 1e-3 then
			w = 100
		end
		tile.W = w
		t = chunkEnd
	end
	cs.T = t1
	events.Stage = CropMath.StageOf(cs.P or 0)
	return events
end

-- Current care factors (for the tooltip and for harvest).
function CropMath.Factors(tile: any, cs: any, env: Env, now: number): QualityMath.Factors
	local crop = Registry.Crops[cs.Id]
	local total = math.max(cs.Tt or 0, 1)
	local fert = fertOf(cs)
	local sinceRipe = if cs.Rp then (now - cs.Rp) / HOUR else 0
	return {
		Water = math.clamp((cs.Wg or 0) / total, 0, 1),
		Soil = if env.Hydroponic then 0.8 else math.clamp((tile.H or 50) / 100, 0, 1),
		Nutrients = if env.Hydroponic then 0.8 else CropMath.NutrientBalance(tile, crop),
		Fertilizer = if fert and fert.Quality then fert.Quality else 0,
		Climate = math.clamp((cs.Cs or 0) / total, 0, 1),
		Genes = Genetics.Luster(cs.G),
		Timing = QualityMath.Timing(sinceRipe),
	}
end

-- Quality score now, before harvest noise. `bonus` = tool + pruning + skills.
function CropMath.Score(tile: any, cs: any, env: Env, now: number, bonus: number?): number
	local factors = CropMath.Factors(tile, cs, env, now)
	local extra = (bonus or 0) + env.QualityBonus
	if cs.Pr then
		extra += 0.04
	end
	if cs.Af then
		local aff = Soil.Afflictions[cs.Af]
		extra -= if aff then aff.QualityPenalty else 0
	end
	return QualityMath.Score(factors, extra)
end

function CropMath.MaxTier(cs: any, env: Env): number
	local crop = Registry.Crops[cs.Id]
	local cap = crop.MaxQuality
	if not CropMath.NeedsMet(crop, env) then
		cap = math.min(cap, CropsConfig.UnmetNeedsMaxQuality)
	end
	if env.Hydroponic then
		cap = math.min(cap, 4)
	end
	return cap
end

-- Rough seconds until ripe if conditions stay as they are now and it's kept watered.
function CropMath.TimeToRipe(tile: any, cs: any, env: Env, now: number): number
	if (cs.P or 0) >= 1 then
		return 0
	end
	local info = GameTime.Info(now)
	local weatherId = CropMath.WeatherAt(env, now)
	local rate = CropMath.BaseRate(cs) * CropMath.GrowthMultiplier(tile, cs, env, weatherId, info)
	if rate <= 0 then
		return math.huge
	end
	return (1 - (cs.P or 0)) / rate
end

-- Harvest roll: quality tier, yield, size, extra mutations (Perfect). Server only.
function CropMath.RollHarvest(tile: any, cs: any, env: Env, now: number, random: Random, opts: any)
	local crop = Registry.Crops[cs.Id]
	local score = CropMath.Score(tile, cs, env, now, opts.QualityBonus)
	score = math.clamp(score + (random:NextNumber() * 2 - 1) * QualityConfig.Noise, 0, 1)
	local tier = QualityMath.TierFor(score, CropMath.MaxTier(cs, env))
	local premium = random:NextNumber() < crop.Premium + (opts.PremiumBonus or 0)
	if premium then
		tier = math.min(tier + 1, CropMath.MaxTier(cs, env))
	end
	if opts.MinTier then
		tier = math.max(tier, opts.MinTier)
	end
	if score >= QualityConfig.PerfectScore then
		CropMath.AddMutation(cs, "Perfect", { MaxMutations = 99 } :: any)
		CropMath.ResolveCombos(cs)
	end

	-- Yield
	local count = random:NextInteger(crop.Yield[1], crop.Yield[2])
	if premium then
		count += 1
	end
	local extraChance = Genetics.YieldChance(cs.G) + (opts.YieldChance or 0)
	while extraChance > 0 do
		if random:NextNumber() < math.min(extraChance, 1) then
			count += 1
		end
		extraChance -= 1
	end
	local twin = false
	for _, id in cs.M or {} do
		local m = mutationById[id]
		if m and m.Yield then
			if m.Yield < 0 then
				twin = true
			else
				count += m.Yield
			end
		end
	end
	if twin then
		count *= 2
	end

	-- Size (kg), log-normal around the base with mutation multipliers.
	local base, variance = crop.Size[1], crop.Size[2]
	local size = base * math.exp((random:NextNumber() * 2 - 1) * variance * 1.6)
	for _, id in cs.M or {} do
		local m = mutationById[id]
		if m and m.Size then
			size *= m.Size
		end
	end
	if crop.Id == "giant_pumpkin" then
		size *= 0.5 + score * 1.5
	end
	return {
		Tier = tier,
		Score = score,
		Count = math.max(1, count),
		Size = size,
		Premium = premium,
		Mutations = table.clone(cs.M or {}),
	}
end

return CropMath

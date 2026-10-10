--!strict
-- Equipment upgrade tracks. Level 1 is what every player starts with.
-- Costs are starting design values; tune them against measured earning rates.

export type Level = {
	Cost: number,
	-- Scanner
	Radius: number?,
	-- Tether
	ZoneMult: number?,
	SpeedMult: number?,
	QualityBonus: number?,
	-- Habitat
	Slots: number?,
	-- Feature unlocked at this level (shown as "NEW" in the workshop)
	Feature: string?,
	FeatureText: string?,
}

export type Track = {
	Id: string,
	DisplayName: string,
	ProfileKey: string,
	Icon: string,
	Summary: string,
	Levels: { Level },
}

local UpgradeDefinitions = {}

UpgradeDefinitions.Order = { "Scanner", "Tether", "Habitat" }

UpgradeDefinitions.Tracks = {
	Scanner = {
		Id = "Scanner",
		DisplayName = "Comet Scanner",
		ProfileKey = "ScannerLevel",
		Icon = "📡",
		Summary = "Locks onto comets and reveals Stardust Wisps within its radius.",
		Levels = {
			{ Cost = 0, Radius = 38 },
			{ Cost = 250, Radius = 44, Feature = "TypeReadout", FeatureText = "Shows each comet's type and payout" },
			{ Cost = 1600, Radius = 51, Feature = "TimeReadout", FeatureText = "Shows how long each comet will last" },
			{
				Cost = 10000,
				Radius = 59,
				Feature = "GuideBeam",
				FeatureText = "A guide beam points to the nearest comet",
			},
			{ Cost = 65000, Radius = 68, Feature = "WispMagnet", FeatureText = "Pulls in nearby Stardust Wisps" },
		},
	},
	Tether = {
		Id = "Tether",
		DisplayName = "Stabilizer Tether",
		ProfileKey = "TetherLevel",
		Icon = "🌀",
		Summary = "Widens stabilization zones and steadies the dial for better capture quality.",
		Levels = {
			{ Cost = 0, ZoneMult = 1, SpeedMult = 1, QualityBonus = 0 },
			{ Cost = 400, ZoneMult = 1.12, SpeedMult = 0.97, QualityBonus = 0.02 },
			{ Cost = 2500, ZoneMult = 1.24, SpeedMult = 0.94, QualityBonus = 0.04 },
			{ Cost = 15000, ZoneMult = 1.36, SpeedMult = 0.91, QualityBonus = 0.06 },
			{ Cost = 90000, ZoneMult = 1.5, SpeedMult = 0.88, QualityBonus = 0.08 },
		},
	},
	Habitat = {
		Id = "Habitat",
		DisplayName = "Sanctuary Habitats",
		ProfileKey = "HabitatLevel",
		Icon = "🏡",
		Summary = "Opens more habitat slots and grows your sanctuary.",
		Levels = {
			{ Cost = 0, Slots = 4 },
			{ Cost = 1200, Slots = 6, Feature = "Paths", FeatureText = "Glowing star paths" },
			{ Cost = 10000, Slots = 8, Feature = "StarRing", FeatureText = "A floating star ring" },
			{ Cost = 80000, Slots = 10, Feature = "Fountain", FeatureText = "A celestial fountain" },
			{ Cost = 450000, Slots = 12, Feature = "Islets", FeatureText = "Floating crystal islets" },
		},
	},
} :: { [string]: Track }

function UpgradeDefinitions.Get(trackId: string): Track?
	return UpgradeDefinitions.Tracks[trackId]
end

function UpgradeDefinitions.MaxLevel(trackId: string): number
	local track = UpgradeDefinitions.Tracks[trackId]
	return if track then #track.Levels else 1
end

function UpgradeDefinitions.GetLevel(trackId: string, level: number): Level
	local track = UpgradeDefinitions.Tracks[trackId]
	assert(track, `Unknown upgrade track {trackId}`)
	return track.Levels[math.clamp(level, 1, #track.Levels)]
end

-- True when `feature` is unlocked at or below `level` on a track.
function UpgradeDefinitions.HasFeature(trackId: string, level: number, feature: string): boolean
	local track = UpgradeDefinitions.Tracks[trackId]
	if not track then
		return false
	end
	for i = 1, math.min(level, #track.Levels) do
		if track.Levels[i].Feature == feature then
			return true
		end
	end
	return false
end

function UpgradeDefinitions.ScannerRadius(level: number): number
	return UpgradeDefinitions.GetLevel("Scanner", level).Radius or 38
end

function UpgradeDefinitions.HabitatSlots(level: number): number
	return UpgradeDefinitions.GetLevel("Habitat", level).Slots or 4
end

export type StatLine = { Label: string, Current: string, Next: string? }

-- Human-readable stat rows for the workshop: what you have and what you'd get.
function UpgradeDefinitions.Describe(trackId: string, level: number): { StatLine }
	local current = UpgradeDefinitions.GetLevel(trackId, level)
	local nextLevel = if level < UpgradeDefinitions.MaxLevel(trackId)
		then UpgradeDefinitions.GetLevel(trackId, level + 1)
		else nil
	local lines: { StatLine } = {}
	if trackId == "Scanner" then
		table.insert(lines, {
			Label = "Detection radius",
			Current = `{current.Radius} studs`,
			Next = if nextLevel then `{nextLevel.Radius} studs` else nil,
		})
	elseif trackId == "Tether" then
		local function pct(mult: number?): string
			return string.format("+%d%%", math.floor(((mult or 1) - 1) * 100 + 0.5))
		end
		local function slow(mult: number?): string
			return string.format("-%d%%", math.floor((1 - (mult or 1)) * 100 + 0.5))
		end
		table.insert(lines, {
			Label = "Zone width",
			Current = pct(current.ZoneMult),
			Next = if nextLevel then pct(nextLevel.ZoneMult) else nil,
		})
		table.insert(lines, {
			Label = "Dial speed",
			Current = slow(current.SpeedMult),
			Next = if nextLevel then slow(nextLevel.SpeedMult) else nil,
		})
		table.insert(lines, {
			Label = "Quality bonus",
			Current = string.format("+%.2f", current.QualityBonus or 0),
			Next = if nextLevel then string.format("+%.2f", nextLevel.QualityBonus or 0) else nil,
		})
	elseif trackId == "Habitat" then
		table.insert(lines, {
			Label = "Habitat slots",
			Current = tostring(current.Slots),
			Next = if nextLevel then tostring(nextLevel.Slots) else nil,
		})
	end
	return lines
end

function UpgradeDefinitions.Validate(): { string }
	local problems = {}
	for _, id in UpgradeDefinitions.Order do
		local track = UpgradeDefinitions.Tracks[id]
		if not track then
			table.insert(problems, `Upgrade track '{id}' is not defined`)
			continue
		end
		if track.Levels[1].Cost ~= 0 then
			table.insert(problems, `Upgrade track '{id}' level 1 must be free`)
		end
		for i = 2, #track.Levels do
			if track.Levels[i].Cost <= track.Levels[i - 1].Cost then
				table.insert(problems, `Upgrade track '{id}' level {i} must cost more than level {i - 1}`)
			end
		end
	end
	return problems
end

return UpgradeDefinitions

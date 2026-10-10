--!strict
-- Every biome's unlock rules, rewards and capture modifiers.
--
-- `Implemented = false` biomes are shown at their hub portals with their real
-- requirements, but can't be entered until their world, creatures and comet
-- placements are built (Phase 2). Flip the flag once they are.

export type CaptureModifiers = {
	SpeedMult: number, -- dial speed
	ZoneMult: number, -- lock zone width
	BandMult: number, -- stabilize band width
	DriftMult: number, -- how much the stabilize band wanders
}

export type Biome = {
	Id: string,
	DisplayName: string,
	Order: number,
	Implemented: boolean,
	Unlock: { Level: number, Stardust: number },
	-- Base Stardust for a capture here (scaled by comet type and rank).
	CaptureStardust: number,
	XPMultiplier: number,
	WispValue: number,
	Capture: CaptureModifiers,
	Tagline: string,
	Description: string,
	Color: Color3,
	AccentColor: Color3,
}

local BiomeDefinitions = {}

BiomeDefinitions.Order = { "DawnCommons", "PrismCliffs", "ThunderReef", "ShadowCrater", "AstralExpanse" }

BiomeDefinitions.Biomes = {
	DawnCommons = {
		Id = "DawnCommons",
		DisplayName = "Dawn Commons",
		Order = 1,
		Implemented = true,
		Unlock = { Level = 1, Stardust = 0 },
		CaptureStardust = 20,
		XPMultiplier = 1,
		WispValue = 3,
		Capture = { SpeedMult = 1, ZoneMult = 1, BandMult = 1, DriftMult = 1 },
		Tagline = "Warm light, gentle comets",
		Description = "Pastel meadows and luminous streams where the friendliest comets land.",
		Color = Color3.fromRGB(255, 207, 140),
		AccentColor = Color3.fromRGB(182, 156, 255),
	},
	PrismCliffs = {
		Id = "PrismCliffs",
		DisplayName = "Prism Cliffs",
		Order = 2,
		Implemented = false,
		Unlock = { Level = 5, Stardust = 2500 },
		CaptureStardust = 120,
		XPMultiplier = 1.4,
		WispValue = 15,
		-- Crystal disturbances: a quicker dial and a more restless band.
		Capture = { SpeedMult = 1.08, ZoneMult = 0.95, BandMult = 0.95, DriftMult = 1.35 },
		Tagline = "Crystal canyons and refracted light",
		Description = "Violet cliffs and floating geometry. Comets land on high ledges.",
		Color = Color3.fromRGB(182, 156, 255),
		AccentColor = Color3.fromRGB(116, 229, 254),
	},
	ThunderReef = {
		Id = "ThunderReef",
		DisplayName = "Thunder Reef",
		Order = 3,
		Implemented = false,
		Unlock = { Level = 12, Stardust = 25000 },
		CaptureStardust = 600,
		XPMultiplier = 1.9,
		WispValue = 70,
		Capture = { SpeedMult = 1.14, ZoneMult = 0.9, BandMult = 0.92, DriftMult = 1.5 },
		Tagline = "Storm-lit coral in the sky",
		Description = "Floating ocean fragments, electric coral and telegraphed lightning.",
		Color = Color3.fromRGB(116, 229, 254),
		AccentColor = Color3.fromRGB(255, 236, 140),
	},
	ShadowCrater = {
		Id = "ShadowCrater",
		DisplayName = "Shadow Crater",
		Order = 4,
		Implemented = false,
		Unlock = { Level = 20, Stardust = 200000 },
		CaptureStardust = 3000,
		XPMultiplier = 2.6,
		WispValue = 320,
		Capture = { SpeedMult = 1.2, ZoneMult = 0.85, BandMult = 0.88, DriftMult = 1.7 },
		Tagline = "Gravity bends around old impacts",
		Description = "Dark floating rock, glowing seams and unstable gravity fields.",
		Color = Color3.fromRGB(150, 90, 220),
		AccentColor = Color3.fromRGB(255, 126, 152),
	},
	AstralExpanse = {
		Id = "AstralExpanse",
		DisplayName = "Astral Expanse",
		Order = 5,
		Implemented = false,
		Unlock = { Level = 30, Stardust = 1500000 },
		CaptureStardust = 15000,
		XPMultiplier = 3.5,
		WispValue = 1500,
		Capture = { SpeedMult = 1.26, ZoneMult = 0.8, BandMult = 0.85, DriftMult = 1.9 },
		Tagline = "The edge of the known sky",
		Description = "Nebula clouds, celestial rings and the most prestigious discoveries.",
		Color = Color3.fromRGB(255, 160, 230),
		AccentColor = Color3.fromRGB(255, 207, 112),
	},
} :: { [string]: Biome }

function BiomeDefinitions.Get(id: string): Biome?
	return BiomeDefinitions.Biomes[id]
end

function BiomeDefinitions.IsBiome(id: any): boolean
	return type(id) == "string" and BiomeDefinitions.Biomes[id] ~= nil
end

function BiomeDefinitions.Validate(): { string }
	local problems = {}
	local seen = {}
	for i, id in BiomeDefinitions.Order do
		local biome = BiomeDefinitions.Biomes[id]
		if not biome then
			table.insert(problems, `Biome '{id}' is listed but not defined`)
			continue
		end
		seen[id] = true
		if biome.Id ~= id or biome.Order ~= i then
			table.insert(problems, `Biome '{id}' has a mismatched Id or Order`)
		end
		if biome.Unlock.Level < 1 or biome.Unlock.Stardust < 0 then
			table.insert(problems, `Biome '{id}' has an invalid unlock requirement`)
		end
	end
	for id in BiomeDefinitions.Biomes do
		if not seen[id] then
			table.insert(problems, `Biome '{id}' is defined but missing from Order`)
		end
	end
	local first = BiomeDefinitions.Biomes[BiomeDefinitions.Order[1]]
	if first and (first.Unlock.Level ~= 1 or first.Unlock.Stardust ~= 0 or not first.Implemented) then
		table.insert(problems, "The first biome must be implemented and free")
	end
	return problems
end

return BiomeDefinitions

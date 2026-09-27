-- The cosmetic catalog. Every item is purely visual or audible; none of them can
-- change odds, damage, health, instruments, AI behaviour or Standing.
--
-- Source.Kind decides how an item is obtained:
--   Default      owned by everyone
--   Level        reaching Clearance Level Source.Value
--   Achievement  unlocking achievement Source.Value
--   Ranked       reaching division Source.Value (any season)
--   Season       season reward (Source.Value = "S1:Arbiter")
--   Challenge    weekly challenge reward pool
--   Shop         bought with Marks (Price)
--   Premium      granted by a developer product / game pass (Monetization config)
--   Tournament   winning a tournament
--   Lore         reading every archive file
--
-- Colors are {R, G, B} 0-255 so this module stays free of Roblox types.

local Cosmetics = {}

Cosmetics.Categories = {
	{ Id = "DeviceSkin", Name = "ARBITER FINISH", Slot = true },
	{ Id = "CellFX", Name = "DISCHARGE", Slot = true },
	{ Id = "TableTheme", Name = "TABLE", Slot = true },
	{ Id = "Gloves", Name = "GLOVES", Slot = true },
	{ Id = "Accessory", Name = "HEADWEAR", Slot = true },
	{ Id = "Victory", Name = "VICTORY", Slot = true },
	{ Id = "Emote", Name = "TABLE EMOTES", Slot = false },
	{ Id = "CardFrame", Name = "CARD FRAME", Slot = true },
	{ Id = "Banner", Name = "BANNER", Slot = true },
	{ Id = "Badge", Name = "BADGE", Slot = true },
	{ Id = "Title", Name = "TITLE", Slot = true },
	{ Id = "SoundPack", Name = "SOUND PACK", Slot = true },
	{ Id = "Nameplate", Name = "NAMEPLATE", Slot = true },
}

Cosmetics.Rarities = {
	Standard = { Order = 1, Label = "STANDARD", Color = { 170, 170, 165 } },
	Fine = { Order = 2, Label = "FINE", Color = { 120, 180, 170 } },
	Rare = { Order = 3, Label = "RARE", Color = { 225, 165, 70 } },
	Prestige = { Order = 4, Label = "PRESTIGE", Color = { 235, 85, 65 } },
}

export type Item = {
	Id: string,
	Category: string,
	Name: string,
	Description: string,
	Rarity: string,
	Source: { Kind: string, Value: any? },
	Price: number?,
	Data: { [string]: any },
}

local items: { Item } = {}
local function add(item: Item)
	table.insert(items, item)
end

-- Arbiter finishes ----------------------------------------------------------
local function skin(id, name, desc, rarity, source, price, data)
	add({ Id = id, Category = "DeviceSkin", Name = name, Description = desc, Rarity = rarity, Source = source, Price = price, Data = data })
end
skin("skin_standard", "STANDARD ISSUE", "Institutional grey. Scuffed at the grip.", "Standard", { Kind = "Default" }, nil, {
	Body = { 62, 66, 70 },
	Metal = { 150, 150, 145 },
	Material = "Metal",
	Accent = { 225, 160, 60 },
	Glow = { 255, 190, 110 },
})
skin("skin_graphite", "GRAPHITE", "Matte black, anodized trim.", "Fine", { Kind = "Shop" }, 600, {
	Body = { 28, 30, 33 },
	Metal = { 80, 84, 90 },
	Material = "Metal",
	Accent = { 200, 200, 205 },
	Glow = { 210, 225, 255 },
})
skin("skin_copper", "OXIDIZED COPPER", "Verdigris creeping through the seams.", "Fine", { Kind = "Shop" }, 750, {
	Body = { 70, 120, 105 },
	Metal = { 175, 110, 70 },
	Material = "Metal",
	Accent = { 110, 190, 160 },
	Glow = { 150, 255, 210 },
})
skin("skin_bone", "BONE", "Pale enamel over steel. Unsettlingly clean.", "Fine", { Kind = "Level", Value = 12 }, nil, {
	Body = { 215, 208, 190 },
	Metal = { 120, 115, 105 },
	Material = "SmoothPlastic",
	Accent = { 170, 60, 50 },
	Glow = { 255, 230, 200 },
})
skin("skin_green", "INSTITUTIONAL GREEN", "The colour of every Halden corridor since 1968.", "Standard", { Kind = "Level", Value = 4 }, nil, {
	Body = { 70, 90, 72 },
	Metal = { 140, 145, 130 },
	Material = "Metal",
	Accent = { 230, 220, 170 },
	Glow = { 220, 255, 190 },
})
skin("skin_hazard", "HAZARD", "Striped for visibility. Nobody needed reminding.", "Rare", { Kind = "Challenge" }, nil, {
	Body = { 40, 40, 40 },
	Metal = { 220, 175, 40 },
	Material = "DiamondPlate",
	Accent = { 235, 190, 40 },
	Glow = { 255, 220, 120 },
})
skin("skin_rust", "RUST", "Decommissioned in 1991. Recommissioned in 1992.", "Standard", { Kind = "Shop" }, 400, {
	Body = { 110, 60, 40 },
	Metal = { 140, 90, 60 },
	Material = "CorrodedMetal",
	Accent = { 210, 120, 70 },
	Glow = { 255, 170, 120 },
})
skin("skin_gilded", "GILDED", "For the subject who has everything but certainty.", "Rare", { Kind = "Level", Value = 30 }, nil, {
	Body = { 40, 32, 22 },
	Metal = { 212, 170, 80 },
	Material = "Foil",
	Accent = { 255, 215, 120 },
	Glow = { 255, 225, 150 },
})
skin("skin_obsidian", "OBSIDIAN GLASS", "Issued to Oracles. It reflects nothing.", "Prestige", { Kind = "Ranked", Value = "Oracle" }, nil, {
	Body = { 12, 10, 16 },
	Metal = { 60, 50, 80 },
	Material = "Glass",
	Accent = { 170, 120, 255 },
	Glow = { 200, 160, 255 },
})
skin("skin_proctor", "PROCTOR WHITE", "The Administrator's own finish.", "Prestige", { Kind = "Achievement", Value = "ach_proctor" }, nil, {
	Body = { 238, 238, 234 },
	Metal = { 200, 200, 198 },
	Material = "SmoothPlastic",
	Accent = { 220, 40, 40 },
	Glow = { 255, 80, 70 },
})
skin("skin_arbiter", "ARBITER BRASS", "Awarded for reaching Arbiter in ranked play.", "Rare", { Kind = "Ranked", Value = "Arbiter" }, nil, {
	Body = { 50, 40, 30 },
	Metal = { 190, 150, 90 },
	Material = "Metal",
	Accent = { 240, 190, 110 },
	Glow = { 255, 210, 140 },
})
skin("skin_founder", "FOUNDER'S FINISH", "Walnut and nickel. Thank you for supporting the Institute.", "Rare", { Kind = "Premium", Value = "Founder" }, nil, {
	Body = { 80, 52, 34 },
	Metal = { 190, 190, 185 },
	Material = "Wood",
	Accent = { 235, 225, 200 },
	Glow = { 255, 240, 210 },
})
skin("skin_champion", "CHAMPION'S CHROME", "Only tournament champions carry this.", "Prestige", { Kind = "Tournament" }, nil, {
	Body = { 180, 185, 190 },
	Metal = { 235, 238, 240 },
	Material = "Foil",
	Accent = { 90, 200, 255 },
	Glow = { 170, 230, 255 },
})

-- Discharge effects -----------------------------------------------------------
local function fx(id, name, desc, rarity, source, price, data)
	add({ Id = id, Category = "CellFX", Name = name, Description = desc, Rarity = rarity, Source = source, Price = price, Data = data })
end
fx("fx_standard", "STANDARD ARC", "Amber-white discharge.", "Standard", { Kind = "Default" }, nil, {
	Arc = { 255, 214, 150 },
	Spark = { 255, 170, 80 },
	Glow = { 255, 190, 120 },
})
fx("fx_cold", "COLD ARC", "A blue so clean it looks medical.", "Fine", { Kind = "Shop" }, 500, {
	Arc = { 170, 220, 255 },
	Spark = { 110, 170, 255 },
	Glow = { 140, 200, 255 },
})
fx("fx_violet", "VIOLET SURGE", "Ultraviolet overspill.", "Fine", { Kind = "Level", Value = 18 }, nil, {
	Arc = { 215, 170, 255 },
	Spark = { 170, 100, 255 },
	Glow = { 190, 140, 255 },
})
fx("fx_emerald", "EMERALD", "Copper salts in the coil.", "Fine", { Kind = "Shop" }, 500, {
	Arc = { 170, 255, 200 },
	Spark = { 70, 220, 140 },
	Glow = { 120, 255, 170 },
})
fx("fx_crimson", "CRIMSON", "Signal red, all the way through.", "Rare", { Kind = "Achievement", Value = "ach_ironnerve" }, nil, {
	Arc = { 255, 150, 140 },
	Spark = { 240, 60, 50 },
	Glow = { 255, 90, 80 },
})
fx("fx_void", "VOID", "Light that seems to go the wrong way.", "Rare", { Kind = "Level", Value = 45 }, nil, {
	Arc = { 120, 90, 160 },
	Spark = { 60, 30, 90 },
	Glow = { 90, 60, 140 },
})
fx("fx_prism", "PRISM", "Every colour at once. Mastery only.", "Prestige", { Kind = "Achievement", Value = "ach_perfect" }, nil, {
	Arc = { 255, 255, 255 },
	Spark = { 255, 255, 255 },
	Glow = { 255, 255, 255 },
	Rainbow = true,
})
fx("fx_static", "STATIC SNOW", "Like a dead channel.", "Fine", { Kind = "Challenge" }, nil, {
	Arc = { 230, 230, 230 },
	Spark = { 200, 200, 200 },
	Glow = { 220, 220, 220 },
})
fx("fx_oracle", "ORACLE FLARE", "Awarded to Oracles.", "Prestige", { Kind = "Ranked", Value = "Oracle" }, nil, {
	Arc = { 255, 200, 190 },
	Spark = { 255, 110, 80 },
	Glow = { 255, 140, 110 },
})

-- Table themes ----------------------------------------------------------------
local function tableTheme(id, name, desc, rarity, source, price, data)
	add({ Id = id, Category = "TableTheme", Name = name, Description = desc, Rarity = rarity, Source = source, Price = price, Data = data })
end
tableTheme("table_steel", "STEEL", "Bolted-down steel.", "Standard", { Kind = "Default" }, nil, {
	Top = { 70, 72, 75 },
	Material = "DiamondPlate",
	Trim = { 120, 120, 118 },
})
tableTheme("table_felt", "FELT", "Worn green baize from upstairs.", "Fine", { Kind = "Shop" }, 450, {
	Top = { 36, 82, 58 },
	Material = "Fabric",
	Trim = { 90, 60, 36 },
})
tableTheme("table_oxblood", "OXBLOOD", "Cracked leather, brass tacks.", "Fine", { Kind = "Level", Value = 22 }, nil, {
	Top = { 88, 26, 26 },
	Material = "Leather",
	Trim = { 190, 150, 80 },
})
tableTheme("table_lab", "LABORATORY", "Wipe-clean white laminate.", "Standard", { Kind = "Level", Value = 8 }, nil, {
	Top = { 220, 222, 218 },
	Material = "SmoothPlastic",
	Trim = { 150, 155, 160 },
})
tableTheme("table_walnut", "WALNUT", "A boardroom table, relocated.", "Fine", { Kind = "Shop" }, 600, {
	Top = { 82, 54, 34 },
	Material = "Wood",
	Trim = { 40, 28, 18 },
})
tableTheme("table_scorched", "SCORCHED", "Burn marks in rings. Don't ask.", "Rare", { Kind = "Achievement", Value = "ach_volatile" }, nil, {
	Top = { 36, 30, 28 },
	Material = "Slate",
	Trim = { 200, 90, 40 },
})
tableTheme("table_hazard", "HAZARD PLATE", "Yellow and black diamond plate.", "Rare", { Kind = "Challenge" }, nil, {
	Top = { 45, 45, 45 },
	Material = "DiamondPlate",
	Trim = { 230, 185, 40 },
})

-- Gloves ----------------------------------------------------------------------
local function gloves(id, name, desc, rarity, source, price, data)
	add({ Id = id, Category = "Gloves", Name = name, Description = desc, Rarity = rarity, Source = source, Price = price, Data = data })
end
gloves("gloves_none", "BARE HANDS", "Nothing between you and the grip.", "Standard", { Kind = "Default" }, nil, { None = true })
gloves("gloves_nitrile", "LAB NITRILE", "Blue, powder-free.", "Standard", { Kind = "Level", Value = 3 }, nil, {
	Color = { 70, 120, 200 },
	Material = "SmoothPlastic",
})
gloves("gloves_leather", "LEATHER", "Softened by other people's sweat.", "Fine", { Kind = "Shop" }, 350, {
	Color = { 70, 45, 30 },
	Material = "Leather",
})
gloves("gloves_insulated", "INSULATED", "Rated to 10,000 volts. Technically.", "Fine", { Kind = "Level", Value = 16 }, nil, {
	Color = { 220, 180, 40 },
	Material = "Rubber",
})
gloves("gloves_surgical", "SURGICAL WHITE", "Sterile. For now.", "Fine", { Kind = "Shop" }, 350, {
	Color = { 235, 235, 230 },
	Material = "SmoothPlastic",
})
gloves("gloves_tactical", "TACTICAL", "Black, knuckle-padded.", "Rare", { Kind = "Achievement", Value = "ach_wins50" }, nil, {
	Color = { 25, 25, 28 },
	Material = "Fabric",
})
gloves("gloves_gold", "GOLD LEAF", "Absurd. Earned.", "Prestige", { Kind = "Level", Value = 60 }, nil, {
	Color = { 212, 175, 90 },
	Material = "Foil",
})

-- Headwear --------------------------------------------------------------------
local function accessory(id, name, desc, rarity, source, price, data)
	add({ Id = id, Category = "Accessory", Name = name, Description = desc, Rarity = rarity, Source = source, Price = price, Data = data })
end
accessory("acc_none", "NONE", "Nothing on your head.", "Standard", { Kind = "Default" }, nil, { Kind = "None" })
accessory("acc_headset", "HEADSET", "Mic muted. Always.", "Standard", { Kind = "Level", Value = 6 }, nil, {
	Kind = "Headset",
	Color = { 40, 40, 44 },
})
accessory("acc_goggles", "LAB GOGGLES", "Scratched polycarbonate.", "Fine", { Kind = "Shop" }, 400, {
	Kind = "Goggles",
	Color = { 200, 220, 210 },
})
accessory("acc_visor", "ANALYST VISOR", "A green eyeshade for long nights of arithmetic.", "Fine", { Kind = "Achievement", Value = "ach_reads100" }, nil, {
	Kind = "Visor",
	Color = { 60, 140, 90 },
})
accessory("acc_fedora", "BACKROOM FEDORA", "Left behind in the Gilded Room.", "Fine", { Kind = "Shop" }, 550, {
	Kind = "Fedora",
	Color = { 45, 40, 38 },
})
accessory("acc_monocle", "MONOCLE", "One eye on the odds.", "Rare", { Kind = "Level", Value = 35 }, nil, {
	Kind = "Monocle",
	Color = { 212, 175, 90 },
})
accessory("acc_mask", "SURROGATE MASK", "Proof you beat all four surrogates on Expert.", "Prestige", { Kind = "Achievement", Value = "ach_allexpert" }, nil, {
	Kind = "Mask",
	Color = { 230, 228, 220 },
})
accessory("acc_halo", "ORACLE RING", "A thin ring of light. Awarded to Oracles.", "Prestige", { Kind = "Ranked", Value = "Oracle" }, nil, {
	Kind = "Halo",
	Color = { 255, 150, 110 },
})
accessory("acc_earpiece", "OBSERVER EARPIECE", "Someone is always listening.", "Rare", { Kind = "Lore" }, nil, {
	Kind = "Earpiece",
	Color = { 30, 30, 32 },
})

-- Victory poses ---------------------------------------------------------------
local function victory(id, name, desc, rarity, source, price, pose)
	add({ Id = id, Category = "Victory", Name = name, Description = desc, Rarity = rarity, Source = source, Price = price, Data = { Pose = pose } })
end
victory("vic_nod", "QUIET NOD", "Nothing to prove.", "Standard", { Kind = "Default" }, nil, "Nod")
victory("vic_lean", "LEAN BACK", "Chair tipped, arms behind the head.", "Fine", { Kind = "Level", Value = 7 }, nil, "LeanBack")
victory("vic_clap", "SLOW CLAP", "For your opponent. Mostly.", "Fine", { Kind = "Shop" }, 450, "SlowClap")
victory("vic_temple", "TAP TEMPLE", "It was maths all along.", "Fine", { Kind = "Achievement", Value = "ach_reads100" }, nil, "TapTemple")
victory("vic_salute", "SALUTE", "Institutional respect.", "Standard", { Kind = "Shop" }, 300, "Salute")
victory("vic_arms", "ARMS CROSSED", "Unimpressed.", "Fine", { Kind = "Level", Value = 26 }, nil, "ArmsCrossed")
victory("vic_bow", "TABLE BOW", "A formal bow over the Arbiter.", "Rare", { Kind = "Level", Value = 40 }, nil, "Bow")
victory("vic_raise", "RAISE THE ARBITER", "Held overhead. Champions only.", "Prestige", { Kind = "Tournament" }, nil, "Raise")

-- Table emotes ----------------------------------------------------------------
local function emote(id, name, desc, rarity, source, price, anim)
	add({ Id = id, Category = "Emote", Name = name, Description = desc, Rarity = rarity, Source = source, Price = price, Data = { Anim = anim } })
end
emote("emote_nod", "NOD", "Acknowledge.", "Standard", { Kind = "Default" }, nil, "Nod")
emote("emote_shrug", "SHRUG", "Who knows.", "Standard", { Kind = "Default" }, nil, "Shrug")
emote("emote_knock", "KNOCK TWICE", "Two knuckles on the table.", "Standard", { Kind = "Default" }, nil, "Knock")
emote("emote_point", "POINT", "You. Yes, you.", "Fine", { Kind = "Level", Value = 9 }, nil, "Point")
emote("emote_thumbs", "THUMBS UP", "Good luck. Genuinely.", "Standard", { Kind = "Level", Value = 2 }, nil, "ThumbsUp")
emote("emote_tsk", "TSK", "A slow shake of the head.", "Fine", { Kind = "Shop" }, 250, "Tsk")
emote("emote_wave", "WAVE", "Hello, opponent.", "Standard", { Kind = "Default" }, nil, "Wave")
emote("emote_stretch", "STRETCH", "Knuckles cracked.", "Fine", { Kind = "Shop" }, 250, "Stretch")

-- Card frames -----------------------------------------------------------------
local function frame(id, name, desc, rarity, source, price, data)
	add({ Id = id, Category = "CardFrame", Name = name, Description = desc, Rarity = rarity, Source = source, Price = price, Data = data })
end
frame("frame_intake", "INTAKE", "The standard file folder.", "Standard", { Kind = "Default" }, nil, {
	Stroke = { 90, 92, 95 },
	Accent = { 225, 160, 60 },
	Style = "Plain",
})
frame("frame_brass", "BRASS", "Polished corner plates.", "Fine", { Kind = "Level", Value = 14 }, nil, {
	Stroke = { 190, 150, 80 },
	Accent = { 240, 200, 120 },
	Style = "Double",
})
frame("frame_circuit", "CIRCUIT", "Traces run around the edge.", "Fine", { Kind = "Shop" }, 500, {
	Stroke = { 70, 160, 130 },
	Accent = { 120, 230, 180 },
	Style = "Notched",
})
frame("frame_redline", "REDLINE", "For those who live at one point.", "Rare", { Kind = "Achievement", Value = "ach_lastfilament" }, nil, {
	Stroke = { 220, 60, 50 },
	Accent = { 255, 120, 100 },
	Style = "Glow",
})
frame("frame_oracle", "ORACLE", "Seasonal top division frame.", "Prestige", { Kind = "Ranked", Value = "Oracle" }, nil, {
	Stroke = { 255, 130, 100 },
	Accent = { 255, 200, 170 },
	Style = "Glow",
})
frame("frame_strategist", "STRATEGIST", "Ranked division frame.", "Fine", { Kind = "Ranked", Value = "Strategist" }, nil, {
	Stroke = { 120, 170, 190 },
	Accent = { 190, 230, 240 },
	Style = "Double",
})
frame("frame_s1", "SEASON ONE", "Played ranked in Season One.", "Rare", { Kind = "Season", Value = "S1:Analyst" }, nil, {
	Stroke = { 200, 200, 190 },
	Accent = { 225, 160, 60 },
	Style = "Notched",
})

-- Banners ---------------------------------------------------------------------
local function banner(id, name, desc, rarity, source, price, data)
	add({ Id = id, Category = "Banner", Name = name, Description = desc, Rarity = rarity, Source = source, Price = price, Data = data })
end
banner("banner_static", "DEAD CHANNEL", "Grey on grey.", "Standard", { Kind = "Default" }, nil, {
	A = { 40, 42, 45 },
	B = { 70, 72, 75 },
	Pattern = "Gradient",
})
banner("banner_grid", "GRAPH PAPER", "Every square a probability.", "Standard", { Kind = "Level", Value = 5 }, nil, {
	A = { 30, 44, 40 },
	B = { 90, 150, 130 },
	Pattern = "Grid",
})
banner("banner_warning", "WARNING STRIPES", "Keep clear of the table.", "Fine", { Kind = "Shop" }, 350, {
	A = { 35, 35, 35 },
	B = { 230, 185, 40 },
	Pattern = "Stripes",
})
banner("banner_night", "NIGHT SHIFT", "Sodium orange into midnight.", "Fine", { Kind = "Level", Value = 11 }, nil, {
	A = { 20, 24, 44 },
	B = { 200, 110, 40 },
	Pattern = "Gradient",
})
banner("banner_aurora", "AURORA", "Seen once through a vent shaft.", "Rare", { Kind = "Level", Value = 50 }, nil, {
	A = { 20, 60, 80 },
	B = { 120, 255, 190 },
	Pattern = "Gradient",
})
banner("banner_signal", "SIGNAL RED", "A single colour, loudly.", "Fine", { Kind = "Shop" }, 350, {
	A = { 120, 20, 20 },
	B = { 230, 70, 50 },
	Pattern = "Solid",
})
banner("banner_tv", "TEST CARD", "Please stand by.", "Rare", { Kind = "Challenge" }, nil, {
	A = { 60, 60, 60 },
	B = { 230, 230, 230 },
	Pattern = "Static",
})

-- Badges ----------------------------------------------------------------------
local function badge(id, name, desc, rarity, source, glyph, color)
	add({ Id = id, Category = "Badge", Name = name, Description = desc, Rarity = rarity, Source = source, Data = { Glyph = glyph, Color = color } })
end
badge("badge_none", "NONE", "No badge.", "Standard", { Kind = "Default" }, "", { 120, 120, 120 })
badge("badge_first", "FIRST TRIAL", "Won your first match.", "Standard", { Kind = "Achievement", Value = "ach_first" }, "I", { 200, 200, 190 })
badge("badge_survivor", "SURVIVOR", "Survived a mutual collapse.", "Rare", { Kind = "Achievement", Value = "ach_collapse" }, "S", { 240, 120, 90 })
badge("badge_analyst", "ANALYST", "100 correct reads.", "Fine", { Kind = "Achievement", Value = "ach_reads100" }, "A", { 120, 200, 170 })
badge("badge_endurance", "ENDURANCE", "Completed all five Endurance stages.", "Rare", { Kind = "Achievement", Value = "ach_endurance" }, "E", { 225, 165, 70 })
badge("badge_proctor", "OBSERVED", "Defeated the Proctor.", "Prestige", { Kind = "Achievement", Value = "ach_proctor" }, "P", { 235, 70, 60 })
badge("badge_champion", "CHAMPION", "Won a tournament.", "Prestige", { Kind = "Tournament" }, "C", { 120, 210, 255 })

-- Titles ----------------------------------------------------------------------
local function title(id, text, desc, rarity, source)
	add({ Id = id, Category = "Title", Name = text, Description = desc, Rarity = rarity, Source = source, Data = { Text = text } })
end
title("title_level", "CLEARANCE TITLE", "Your title from Clearance Level.", "Standard", { Kind = "Default" })
title("title_ironnerve", "IRON NERVE", "Survived four dangerous self-shots in a row.", "Rare", { Kind = "Achievement", Value = "ach_ironnerve" })
title("title_lastfilament", "LAST FILAMENT", "Won from a single point of Integrity.", "Rare", { Kind = "Achievement", Value = "ach_lastfilament" })
title("title_bookkeeper", "BOOKKEEPER", "Won with perfect information tracking.", "Rare", { Kind = "Achievement", Value = "ach_perfect" })
title("title_barehanded", "BARE-HANDED", "Won without instruments against Advanced or better.", "Rare", { Kind = "Achievement", Value = "ach_barehands" })
title("title_witness", "WITNESS", "Saw the Proctor where it shouldn't be.", "Rare", { Kind = "Achievement", Value = "ach_witness" })
title("title_administrator", "ADMINISTRATOR", "Beat the Proctor at its own game.", "Prestige", { Kind = "Achievement", Value = "ach_proctor" })
title("title_archivist", "ARCHIVIST", "Read every file in the archive.", "Rare", { Kind = "Lore" })
title("title_champion", "CHAMPION", "Won a tournament.", "Prestige", { Kind = "Tournament" })

-- Sound packs -----------------------------------------------------------------
local function soundPack(id, name, desc, rarity, source, price, data)
	add({ Id = id, Category = "SoundPack", Name = name, Description = desc, Rarity = rarity, Source = source, Price = price, Data = data })
end
soundPack("sound_standard", "STANDARD", "The Arbiter as issued.", "Standard", { Kind = "Default" }, nil, { Pitch = 1, Variant = "Standard" })
soundPack("sound_heavy", "HEAVY INDUSTRIAL", "Lower, longer, more steel.", "Fine", { Kind = "Shop" }, 500, { Pitch = 0.82, Variant = "Heavy" })
soundPack("sound_retro", "RETRO SYNTH", "Discharges from a 1983 test lab.", "Fine", { Kind = "Level", Value = 20 }, nil, { Pitch = 1.25, Variant = "Retro" })
soundPack("sound_muted", "MUTED", "Everything wrapped in felt.", "Standard", { Kind = "Shop" }, 200, { Pitch = 0.95, Variant = "Muted" })

-- Lobby nameplates ------------------------------------------------------------
local function nameplate(id, name, desc, rarity, source, price, data)
	add({ Id = id, Category = "Nameplate", Name = name, Description = desc, Rarity = rarity, Source = source, Price = price, Data = data })
end
nameplate("plate_standard", "STANDARD", "Bone text on charcoal.", "Standard", { Kind = "Default" }, nil, { Color = { 230, 226, 214 }, Style = "Plain" })
nameplate("plate_amber", "AMBER", "Warm institutional amber.", "Standard", { Kind = "Level", Value = 10 }, nil, { Color = { 232, 163, 61 }, Style = "Plain" })
nameplate("plate_glitch", "GLITCH", "Your name never quite settles.", "Rare", { Kind = "Shop" }, 800, { Color = { 170, 220, 255 }, Style = "Glitch" })
nameplate("plate_gold", "GOLD", "A plate for the long-serving.", "Prestige", { Kind = "Level", Value = 75 }, nil, { Color = { 240, 200, 110 }, Style = "Glow" })

Cosmetics.List = items
Cosmetics.ById = {} :: { [string]: Item }
Cosmetics.ByCategory = {} :: { [string]: { Item } }
Cosmetics.Defaults = {} :: { [string]: string }
for _, item in items do
	Cosmetics.ById[item.Id] = item
	Cosmetics.ByCategory[item.Category] = Cosmetics.ByCategory[item.Category] or {}
	table.insert(Cosmetics.ByCategory[item.Category], item)
	if item.Source.Kind == "Default" and Cosmetics.Defaults[item.Category] == nil then
		Cosmetics.Defaults[item.Category] = item.Id
	end
end

function Cosmetics.get(id: string): Item?
	return Cosmetics.ById[id]
end

-- Items unlocked by reaching a level (inclusive range).
function Cosmetics.forLevels(fromLevel: number, toLevel: number): { string }
	local out = {}
	for _, item in items do
		if item.Source.Kind == "Level" and item.Source.Value >= fromLevel and item.Source.Value <= toLevel then
			table.insert(out, item.Id)
		end
	end
	return out
end

function Cosmetics.forSource(kind: string, value: any?): { string }
	local out = {}
	for _, item in items do
		if item.Source.Kind == kind and (value == nil or item.Source.Value == value) then
			table.insert(out, item.Id)
		end
	end
	return out
end

-- Human-readable unlock condition for locked items.
function Cosmetics.unlockText(item: Item, achievementName: ((string) -> string?)?): string
	local source = item.Source
	if source.Kind == "Default" then
		return "Owned by default"
	elseif source.Kind == "Level" then
		return "Reach Clearance Level " .. tostring(source.Value)
	elseif source.Kind == "Achievement" then
		local name = achievementName and achievementName(source.Value) or nil
		return "Achievement: " .. (name or "???")
	elseif source.Kind == "Ranked" then
		return "Reach " .. string.upper(tostring(source.Value)) .. " in ranked"
	elseif source.Kind == "Season" then
		return "Season reward"
	elseif source.Kind == "Challenge" then
		return "Weekly challenge reward"
	elseif source.Kind == "Shop" then
		return string.format("%d Marks", item.Price or 0)
	elseif source.Kind == "Premium" then
		return "Supporter bundle"
	elseif source.Kind == "Tournament" then
		return "Win a tournament"
	elseif source.Kind == "Lore" then
		return "Read every archive file"
	end
	return "Locked"
end

return Cosmetics

--!strict
-- Shapes of the saved player profile, shared so the client's state store
-- and the server's services agree. Only plain data: no Instances, no
-- functions, nothing that can't round-trip through a DataStore.

export type CreatureRecord = {
	Id: string, -- globally unique: "<owner userId base36>-<serial base36>"
	Species: string,
	Mutation: string,
	Bond: number,
	Obtained: number, -- os.time()
	Locked: boolean,
	Favorite: boolean,
	Origin: string, -- "Capture" | "Starter"
	Biome: string,
}

export type CoreRecord = {
	Id: string,
	Kind: string, -- "Normal" | "Starter"
	Biome: string,
	CometType: string,
	Quality: number,
	Obtained: number,
}

export type Discovery = {
	First: number,
	Count: number,
	Mutations: { [string]: boolean },
}

export type QuestProgress = {
	Onboarding: { Progress: number },
	Missions: { Index: number, Progress: number, Complete: boolean },
}

export type Settings = {
	MusicVolume: number,
	EffectsVolume: number,
	AmbientVolume: number,
	ReducedMotion: boolean,
	EasyCapture: boolean,
	AutoOpenCores: boolean,
	GraphicsQuality: string,
}

export type Profile = {
	SchemaVersion: number,
	Stardust: number,
	MeteorShards: number,
	Level: number,
	XP: number,
	TutorialStage: number,
	UnlockedBiomes: { [string]: boolean },
	Equipment: { ScannerLevel: number, TetherLevel: number, HabitatLevel: number },
	Creatures: { [string]: CreatureRecord },
	NextCreatureSerial: number,
	Cores: { [string]: CoreRecord },
	NextCoreSerial: number,
	-- Habitat slot ("1".."12") → creature id
	EquippedCreatures: { [string]: string },
	DiscoveredSpecies: { [string]: Discovery },
	QuestProgress: QuestProgress,
	Achievements: { [string]: number },
	SanctuaryDecorations: { [string]: any },
	AscensionCount: number,
	Settings: Settings,
	Stats: { [string]: number },
	LastSeenTimestamp: number,
	CreatedAt: number,
	IncomeRemainder: number,
	-- Developer product receipts already fulfilled (Phase 5).
	ProcessedReceipts: { [string]: number },
}

-- Runtime (unsaved) state the server mirrors to the client.
export type SessionState = {
	PlotIndex: number?,
	IncomeRate: number,
	SaveStatus: string, -- "OK" | "Degraded" | "SessionOnly" | "Locked"
	Area: string?,
}

return {}

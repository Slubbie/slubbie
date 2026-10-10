# Architecture

Catch a Comet! is a service/controller game. The server owns every number that matters: currency, XP, creatures, comets, capture results, habitats and saves. The client draws the world, runs the UI and gives instant feedback, but every outcome comes from the server. Content and tuning are data in shared modules, so adding a creature, biome, comet type or quest is mostly a data change.

## Folder structure

```
ReplicatedStorage
└── Shared                          src/shared        (ModuleScripts, used by both sides)
    ├── GameConfig                  systems tuning, feature flags, sounds, graphics presets
    ├── RarityConfig                rarity + mutation odds, weighted roll, odds display, validation
    ├── CreatureDefinitions         the 24 species (rarity, biomes, palette, idle style, description)
    ├── BiomeDefinitions            5 biomes (unlock rules, rewards, capture modifiers, Implemented flag)
    ├── UpgradeDefinitions          Scanner / Tether / Habitat levels, costs, features, stat lines
    ├── QuestDefinitions            objective types, the onboarding guide, Explorer missions
    ├── EconomyMath                 income, XP curve, capture rewards, offline earnings, release value
    ├── CaptureMath                 the minigame as deterministic math (client draws, server scores)
    ├── RemoteDefinitions           the remote contract: names, argument schemas, rate limits
    ├── WorldLayout                 fixed positions: hub stations, plots, slots, biome areas
    ├── CreatureRig                 procedural creature models + secondary-motion metadata
    ├── EquipmentRig                the handheld Comet Tether model, per upgrade level
    ├── UITheme                     palette, fonts, radii, motion tokens
    ├── ProfileTypes                profile/record type definitions
    ├── Signal, Loop, Format        small utilities
    └── (Remotes folder)            created at runtime by the server

ServerScriptService
└── Server                          src/server
    ├── Bootstrap (Script)          validates content, creates remotes, Init → Start all services
    ├── Services/                   one ModuleScript per service (below)
    ├── Data/
    │   ├── ProfileSchema           defaults, migrations, reconcile, integrity repair, client view
    │   └── ProfileStore            session-locked UpdateAsync storage with retries
    └── World/
        ├── Kit                     part/terrain/bridge/label/prompt helpers
        ├── Atmosphere              lighting, sky, post-processing, cloud sea, horizon
        ├── HubBuilder              Celestial Crossing
        ├── DawnCommonsBuilder      Dawn Commons islands, impact sites, wisp spots
        └── PlotBuilder             sanctuary plots, habitat pads, Habitat-level decorations

StarterPlayer.StarterPlayerScripts
└── Client                          src/client
    ├── ClientBootstrap (LocalScript)  loading screen, Init → load state → Start all controllers
    ├── Controllers/                one ModuleScript per controller (below)
    └── UI/
        ├── Components              the UI kit: panels, buttons, pills, tabs, toggles, steppers…
        └── Viewport                creature portraits in ViewportFrames

Workspace.World                     built at runtime: Hub, Biomes, Sanctuaries, Sky
```

### Differences from the proposed structure, and why

| Proposed | Built | Reason |
|---|---|---|
| `StarterGui/GameUI` | UI built in code by controllers into `PlayerGui` | One component system styles every screen consistently. Layouts adapt per device. No hand-placed GUI tree goes stale. |
| `ServerStorage/Assets/CreatureModels` | Optional `ReplicatedStorage/Assets/CreatureModels` | The client renders creatures too (portraits, reveals, wild critters), so override models must replicate. |
| `EventDefinitions`, `ExpeditionService`, `PurchaseService`, `PlaceDecoration`, `EventBroadcast` | Not created yet | Phase 3+. The spec asks for no empty modules. Their place in the architecture is described in the roadmap. |
| `StateSnapshot` as a pushed event | A `RemoteFunction` the client calls when ready | The client can't miss the snapshot. Later deltas carry sequence numbers. |
| — | `WorldService`, `TravelService`, `CharacterService`, `WispService`, `IncomeService`, `LeaderboardService`, `ReplicationService` | World building and validation, portals and quick travel, spawning and fall recovery, Stardust Wisps, passive and offline income, leaderstats, and state replication each get one clear owner. |

## Server services

Each service is a ModuleScript returning a table with `Init(registry)` (wire references, no gameplay) and `Start()` (connect events, bind remotes, start loops). The bootstrap initializes all of them, then starts all of them, in this order. Each service may rely on the ones above it. Profile loading begins only after every service has started (`PlayerDataService.BeginLoading`), so no service can miss a `ProfileLoaded` event. Services talk through public functions and `Signal`s, never by touching each other's internals. There are no circular requires: services reach each other through the registry.

| # | Service | Owns | Key API / signals |
|---|---|---|---|
| 1 | SecurityService | argument validation, rate limits, violation tracking, guarded remote binding | `BindFunction`, `BindEvent`, `ValidateArgs`, `GetRootPosition` |
| 2 | AnalyticsService | telemetry via Roblox AnalyticsService (funnel, economy, progression, custom) | `Funnel`, `Economy`, `Milestone`, `Custom` |
| 3 | PlayerDataService | in-memory profiles, session-locked persistence | `GetProfile`, `RequestSave`, `ProfileLoaded`, `ProfileReleasing`, `SaveStatusChanged` |
| 4 | ReplicationService | snapshot + ordered deltas + notifications to each client | `Set`, `SetSession`, `Notify`, `RegisterSnapshotProvider` |
| 5 | EconomyService | the only writer of currency balances | `Grant`, `Spend` (atomic), `Granted`, `Spent` |
| 6 | ProgressionService | XP, levels, level rewards, biome access | `AddXP`, `CanEnterBiome`, `UnlockBiome`, `LevelUp` |
| 7 | CreatureService | cores, server-side rolls, creature records, release, flags | `GrantCore`, `OpenCore`, `AddCreature`, `Release`, `CoreOpened`, `CreatureObtained` |
| 8 | WorldService | builds and validates the world; impact/wisp sites; plots; portals | `ImpactPoints`, `WispPoints`, `GetPlot`, `SetPlotTier` |
| 9 | UpgradeService | equipment purchases (atomic) | `Purchase`, `Upgraded` |
| 10 | IncomeService | one passive-income loop for the server; offline earnings | `GetRate`, `Tick`, `RateChanged`, `PassiveIncome` |
| 11 | SanctuaryService | plot assignment, slot placement, displays, tiers, owner signs | `Deploy`, `Withdraw`, `CreatureDeployed`, `EnteredOwnSanctuary` |
| 12 | CometService | the comet registry: spawn, claims, expiry, broadcasts | `Spawn`, `SpawnTutorial`, `CheckCapturable`, `MarkClaimed` |
| 13 | CaptureService | minigame sessions, timing validation, scoring, rewards | `HandleStart`, `HandleAction`, `CaptureSucceeded` |
| 14 | WispService | Stardust Wisps, per-player timers | `HandleCollect`, `WispCollected` |
| 15 | QuestService | onboarding and missions on data-driven objective types | `Record`, `Claim`, `QuestCompleted` |
| 16 | TravelService | portals and quick travel, with server-side destination checks | `Travel`, `Resolve` |
| 17 | CharacterService | spawning, respawning, walk speed, the visible device, fall recovery | `RefreshEquipment` |
| 18 | LeaderboardService | leaderstats and the hub's Top Collectors monument | — |

## Client controllers

Controllers share a registry the same way and start once the state snapshot has loaded.

| Controller | Job |
|---|---|
| ClientState | read-only mirror of the player's state: snapshot, then ordered deltas; `Observe(key, fn)` |
| InputController | device detection (keyboard, touch, gamepad), prompt wording, shortcuts, capture binding, movement lock |
| PanelManager | one modal panel at a time, backdrop, gamepad B to close, gamepad focus |
| AudioController | sound groups (Music, Effects, Ambient), pooled 2D/3D sounds, fanfares, generative chime ambience |
| SettingsController | settings UI, graphics presets, reduced motion, debounced save to the server |
| CameraController | impact shake and FOV punches (reduced with Reduced Motion) |
| EffectsController | pooled world effects: shockwaves, bursts, flashes, floating text, light pillars |
| NotificationController | toasts, banners, welcome-back card, save-status banner, travel fades |
| CometController | falling comets, impacts, crash sites, markers, capture prompts, scanner lock-on, guide beam |
| CaptureController | the minigame UI and protocol, other players' tether beams |
| RevealController | opening cores and presenting creatures by rarity tier |
| WispController | wisps inside scanner range; proximity collection |
| CreatureAnimator | one loop animating every creature: idle archetypes, secondary motion, blinking, colour shimmer, looking at players, distance throttling |
| AmbientController | spinning, bobbing and swaying decorations, sky meteors, wandering wild creatures, area titles and ambience |
| SanctuaryController | own-plot prompts, placement highlights, habitat and creature pickers, home beacon |
| InventoryController | creatures, cores, collection book, odds |
| WorkshopController | upgrades: current → next, features, exact costs, device preview |
| HUDController | top bar, navigation, scanner strip, travel and settings panels, world prompt routing |
| ObjectiveController | objective tracker, waypoint marker, off-screen arrow, Quests panel, mission claiming |

## Persistence model

**One profile per player**, key `Player_<UserId>` in DataStore `CatchAComet_Profiles_v1`. The stored record is `{ Data = <profile>, Meta = { Session, Heartbeat, Loads, Saves } }`.

The profile (see `ProfileSchema.Default` and `ProfileTypes`) holds every field from the spec (`SchemaVersion`, `Stardust`, `MeteorShards`, `Level`, `XP`, `TutorialStage`, `UnlockedBiomes`, `Equipment`, `Creatures`, `EquippedCreatures`, `DiscoveredSpecies`, `QuestProgress`, `Achievements`, `SanctuaryDecorations`, `AscensionCount`, `Settings`, `LastSeenTimestamp`), plus `Cores`, serial counters, `Stats`, `CreatedAt`, `IncomeRemainder` and `ProcessedReceipts` (for idempotent purchases later). It contains plain data only: no Instances, no Vector3s. The test harness's fake DataStore rejects anything a JSON save would lose.

**Creature IDs** are `<owner userId base36>-<serial base36>`, for example `2n9c-1a`. They're short, never reused (the serial only grows and integrity repair keeps it above every existing ID), and unique across all players, so future trading can move creatures between profiles safely. Records are keyed by ID. Habitats store IDs, never copies.

**Session locking** (`ProfileStore`). `Load` claims the lock with `UpdateAsync`. If another live server holds it (for example while it saves the player on leave), the load waits and retries. A lock with no heartbeat for 5 minutes is treated as a crashed server and taken over. `Save` writes only while this server still owns the lock. If another server took it, the result is `LockLost`: this server stops saving and kicks the player, so two live copies can never overwrite each other. Every request retries with exponential backoff and waits for request budget.

**When it saves.** Autosave every 60 s, which also refreshes the heartbeat. A debounced priority save after valuable moments (Epic+ or mutated creatures, upgrades, level ups, tutorial completion, mission claims). A final save that releases the lock when the player leaves. Every remaining profile in parallel on `BindToClose`. Saves for one player never overlap. Gameplay never saves per currency change: it mutates the in-memory profile, which is the source of truth during the session.

**Loading pipeline** (`ProfileSchema.Prepare`):

1. **Migrate** by `SchemaVersion` (ordered, one step per version). Data from a newer build is refused untouched, and the player is asked to rejoin.
2. **Reconcile:** add any field the template has.
3. **Sanitize:** fix negative or non-finite currency, out-of-range levels and XP, invalid equipment levels, broken habitat assignments (unknown slot, locked slot, not owned, same creature twice), invalid mutations and bonds, serial counters below existing IDs, missing discoveries, invalid settings.

Unknown species are **kept**, so content changes never delete player data. They just can't earn or sit in a habitat. Every repair is logged.

**Failure behaviour.**

| Situation | Response |
|---|---|
| Load keeps failing in a live server | Kick: "Roblox's data service is having trouble. Your progress is safe — please rejoin." Nothing is written. |
| Lock held by another server | Wait and retry, then kick: "Your save is still open on another server…" |
| Data from a newer game version | Release the lock untouched, kick: "rejoin to get the latest version" |
| Save fails during play | Keep retrying. The client shows "Saving is delayed — recent progress isn't saved yet", and "Saving restored" once a save succeeds. |
| Lock stolen | Stop saving and kick. The banner explains. |
| Studio without API access | Session-only mode with a visible banner. Nothing is saved, and nothing pretends to be. |
| Player leaves mid-load | The lock is released without changes. |
| Rejoin on the same server | The new load waits for the previous final save. |

## Remote contract

All remotes live in `ReplicatedStorage.Remotes`, created by the server from `RemoteDefinitions`. Every client→server remote has an argument schema (type, length, range, allowed values, argument count) and a token-bucket rate limit, enforced by `SecurityService` before any handler runs. Requests before the profile has loaded get `NotReady`. Handler errors return `ServerError` instead of hanging the client.

| Remote | Kind | Arguments | Returns / payload |
|---|---|---|---|
| StateSnapshot | Function | — | `{ Ok, Snapshot = { Seq, Profile, Session, Comets, Wisps, ServerTime } }` |
| StartCapture | Function | cometId | `{ Ok, Reason?, Session = { Id, CometId, Params, AttemptStart, IsTutorial } }` |
| CaptureAction | Function | sessionId, `"Lock" \| "Release" \| "Cancel"`, t1?, t2? | stage result: `Hit`, `Score`, `Stage`, `AttemptStart`, `Misses`, `Failed`, or on completion `Rank`, `Quality`, `Stardust`, `XP`, `CoreId` |
| OpenComet | Function | coreId | `{ Ok, Creature, IsNew }` |
| EquipCreature | Function | creatureId, slot 1–12 | `{ Ok, Reason?, Swapped? }` |
| RemoveCreature | Function | slot 1–12 | `{ Ok, Reason? }` |
| ReleaseCreature | Function | creatureId | `{ Ok, Reason?, Stardust? }` |
| SetCreatureFlag | Function | creatureId, `"Locked" \| "Favorite"`, boolean | `{ Ok, Reason? }` |
| PurchaseUpgrade | Function | `"Scanner" \| "Tether" \| "Habitat"` | `{ Ok, Reason?, Level? }` |
| ClaimQuest | Function | questId | `{ Ok, Reason?, Reward? }` |
| CollectWisp | Function | wispId | `{ Ok, Reason?, Stardust?, AvailableAt? }` |
| Travel | Function | `"Hub" \| "Sanctuary" \| <biomeId>` | `{ Ok, Reason? }` |
| UpdateSettings | Event | settings table (known keys only) | — |
| StateDelta | Event (to client) | seq, `{ { Path, Value } }` | applied in order, once |
| CometBroadcast | Event (to client) | `"Spawn" \| "Expire" \| "Claimed"`, payload | — |
| Notification | Event (to client) | kind, payload | toasts, level ups, offline earnings, save status… |

Clients never send amounts, rarities, rewards, success flags, positions or arbitrary tables.

## Capture: timing without trusting the client

The server sends a random seed plus the combined modifiers. Those come from the biome, comet type, Tether level, Easy Capture and the tutorial. The client draws the dial and meter from `CaptureMath` and reports when the player pressed, in seconds since the session began on its side. For each report the server checks the following.

- The session ID and stage match. Stale and repeated reports are refused.
- The time isn't ahead of the server's clock for that session.
- The time is no further behind it than `clamp(1.5 × ping + 0.25, 0.25, 1.0)` seconds.
- The time is never earlier than the previous report.

Then it scores the press with the same math. Misses move the zone and add a short pause. More than three misses fail the attempt with a 2.5 s cooldown; the comet stays available. Completion re-checks distance and the per-player claim, then grants the core, Stardust and XP in one non-yielding block.

Within the latency window a modified client could choose a slightly better moment to report. That only affects the capture-quality bonus (Stardust and XP), never which creature you get, and it still needs a real press inside the window. Quality is deliberately decoupled from creature odds so this residual risk has a small ceiling.

## Rewards and odds

`OpenCore` rolls rarity (55 / 26 / 12 / 5 / 1.7 / 0.3 %), then a species uniformly from that rarity's pool in the core's biome, then a mutation independently (88 / 8 / 3 / 0.9 / 0.1 %). It uses the server's `Random`. `CreatureDefinitions.Validate` guarantees every biome has every rarity. The UI's odds page reads the same tables through `GetRarityOdds` and `GetMutationOdds`, which also apply event modifiers, so displayed odds can't drift from real ones. The roll happens when the core is opened, and the core-to-creature swap is atomic: a disconnect during the reveal animation can't lose or duplicate anything (automated Test G).

## Security summary

- Every gameplay remote goes through `SecurityService` (schema, rate limit, profile loaded, pcall).
- Ownership is checked on every creature, core and habitat operation. Plots accept placement only from their owner.
- Distance checks run on capture start, again on completion, and on wisp pickup.
- Per-player comet claims and session IDs stop duplicates. Mission claims advance the mission before paying, so a repeat targets the next one.
- Currency changes go only through `EconomyService`, with whole, finite, non-negative amounts. Spends are atomic.
- A flood of invalid requests kicks the player.
- Travel destinations are re-checked on the server: biome unlocked and built, plot owned.

## Performance notes

Measured part counts from the build test: hub ≈ 1,050; Dawn Commons ≈ 1,200; all 12 sanctuaries at max tier ≈ 1,960; creatures 15–112 parts. A full 12-player server with full sanctuaries is under ~13k parts, with instance streaming (target radius 900) limiting what each client holds.

Hot paths stay cheap:

- The server runs one loop each for income, comets, capture sweeps, presence and the tutorial check, at ≤ 2 Hz except income at 1 Hz.
- Replication batches deltas and flushes once per frame.
- The client runs one animator loop for all creatures (distance-throttled, off beyond the preset range), one comet renderer, pooled effects, and portraits created only for visible inventory cards.
- Animated decorations move one anchored root with welded children.
- Graphics presets scale particles, animation range and post-processing.

These are budgets, not measurements on devices. Profiling with the MicroProfiler on a phone is in the testing plan.

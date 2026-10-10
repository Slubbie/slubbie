# Roadmap

Phase 1 (the playable core) is built and tested; see the README. This page covers what comes next, what each step depends on, and what is honestly still missing.

## Known limitations

These are true of the current build:

1. **One biome is built.** Dawn Commons is complete. Prism Cliffs, Thunder Reef, Shadow Crater and Astral Expanse exist as data (unlock rules, rewards, capture modifiers, species pools, reserved map space). Their hub portals show the real requirements and "Charting in progress", and travel to them is refused on the server.
2. **Creature art is procedural.** All 24 species are part-built models with their own silhouettes and procedural motion (bobbing, flapping, orbiting, blinking, looking at players). There are no handcrafted meshes and no keyframed animations yet. The override pipeline (`ReplicatedStorage.Assets.CreatureModels.<SpeciesId>`) is ready for them.
3. **Audio uses Roblox's built-in client sounds**, re-pitched, plus generative chimes for ambience. There are no licensed music tracks or bespoke SFX yet. Both are config entries (`GameConfig.Audio`).
4. **Not built yet:** world events and Rift Pulse, expeditions, Meteor Rush, bonding, Ascension, achievements and titles, daily and weekly quests, sanctuary decorations, movement abilities (dash, glide), trading and purchases. Trading and Purchases are behind `GameConfig.Features` flags. No button exists for any of them.
5. **Meteor Shards** exist in the profile and HUD (hidden while 0) but have no source or sink until bonding and events.
6. **The collection book** shows every species, discovery state, owned counts and mutations seen, but has no biome or mutation filter controls yet.
7. **The leaderboard is per-server.** A global OrderedDataStore board is planned.
8. **Not yet verified inside Roblox.** All automated tests run headless in Lune against mocked engine services. Visual tuning, physics feel, real networking, mobile hardware and frame rates still need the manual Studio procedure in [TESTING.md](TESTING.md).
9. **The capture latency window** lets a modified client choose a slightly better press moment within its ping tolerance. The effect is capped at the quality bonus (Stardust and XP) and never touches creature odds. See [ARCHITECTURE.md](ARCHITECTURE.md#capture-timing-without-trusting-the-client).
10. Selene's Roblox standard library couldn't be downloaded in the environment this was built in. luau-lsp (type checking plus lints) was used instead. Run `selene src` locally once.

## Phase 2 — content and presentation

| Work | Depends on | Notes |
|---|---|---|
| **Prism Cliffs** world builder (crystal canyons, elevated impact ledges, light-beam props) | `WorldService` builder pattern, `Kit`, `WorldLayout.Biomes.PrismCliffs` | Set `Implemented = true` and the comet spawner, capture modifiers, travel and species pools already work. |
| **Biome unlock flow**: an `UnlockBiome` remote and an "Unlock" prompt at portals | `ProgressionService.UnlockBiome` (built and tested: level check plus atomic Stardust spend) | Add the remote to `RemoteDefinitions` and bind it in `ProgressionService.Start`. |
| Thunder Reef, Shadow Crater, Astral Expanse builders and their hazards (telegraphed lightning, gravity fields, moving platforms) | Prism Cliffs pattern; a hazard service with telegraph → active → cooldown phases | Hazards must never cause unavoidable failure. Recovery already exists. |
| Handcrafted creature meshes and animations | Override pipeline | Keep the attributes (`Height`, `Radius`, `Idle`) and `Motion` tags so the animator, portraits and displays keep working. |
| Licensed music per biome and bespoke SFX | `GameConfig.Audio` | Replace IDs only. Volume groups and area switching already exist. |
| Collection book filters (rarity, biome, mutation, owned, favourites) | `InventoryController` collection tab | Data is already replicated. |
| Daily quests (3 per UTC day, deterministic rotation) | `QuestService` objective framework | Add a `Daily` chain plus a rotation seeded by the day number, and a tab in the Quests panel. |
| Creature interaction at the sanctuary (pet, feed animation) | `CreatureAnimator`, pad prompts | Cosmetic first. Bonding later uses it. |
| Mobile polish pass on real devices | Manual Test K | Check safe areas, minimum touch targets and text sizes. |

## Phase 3 — social and cooperative

| Work | Depends on | Notes |
|---|---|---|
| **EventService**: `Idle → Announcing → Active → Resolving → Cooldown` state machine, with `EventDefinitions` data | `Loop`, `ReplicationService.NotifyAll`, an `EventBroadcast` remote | One active major event per server. Clean up every instance and connection on Resolve or Cancel. |
| **Rift Pulse** (every ~12 min): fragments → anchors → core | EventService, `CaptureMath` (reuse the minigame for anchors and the core), a `Contribution` table per player | Every participant gets base rewards. Meaningful contribution adds more. Scales to small groups. Rarity modifiers go through `RarityConfig` so the odds UI stays truthful. |
| Aurora Surge, Meteor Rain, Gravity Distortion, Solar Bloom | EventService | Data plus small behaviours. |
| **Expeditions**: The Shattered Observatory (1–4 players, 5–8 min) | A party system; either a reserved area of this place or a reserved server via `TeleportService` | Checkpoints, time penalties only, no item loss. Modifiers rotate. |
| Sanctuary visiting: "Visit" in Travel, wave and inspect | `TravelService`, `SanctuaryService` (plots are already public and protected) | Respect privacy settings (`SocialService` and friend checks where relevant). |
| Achievements and titles | `QuestService` objective types, a new `AchievementService`, nametag BillboardGuis | The spec's list maps onto existing events: First Contact = CaptureSucceeded, and so on. |
| Global leaderboards | OrderedDataStore, updated on save | Throttle refreshes. Cache on the server. |

## Phase 4 — advanced progression

| Work | Depends on | Notes |
|---|---|---|
| **Bonding** to level 5 with a duplicate plus Meteor Shards | `CreatureService`; `Locked`/`Favorite` protection (exists); `EconomyMath.BondMultiplier` (exists) | Preview the creature kept, the duplicate consumed and the result. Atomic, by ID. |
| Meteor Shard sources | Events, expeditions, milestones | Shards appear in the HUD automatically once you have any. |
| **Ascension** | Profile fields (`AscensionCount` exists), `IncomeService.progressionBonus` hook (exists) | Never deletes creatures. Explicit confirmation and disclosure. Permanent bonus with a hard ceiling. |
| Weekly challenges, Meteor Rush (90 s scored captures) | Quest framework, CaptureService events | Competitive modes must never be the only efficient path. |
| Decorations and placement | `SanctuaryDecorations` (exists), a `PlaceDecoration` remote | Snap grid and server validation like habitats. |
| Endgame balance | Telemetry from Phase 1–3 | See below. |

## Phase 5 — production hardening

Exploit testing on live servers. DataStore stress (many concurrent joins and leaves, throttling). MicroProfiler passes on low-end phones. Memory-leak checks over long sessions. Accessibility review (contrast, text size, motion). Controller pass. Error logging (`ScriptContext.Error` to analytics). Content polish. Then **monetization**:

- Cosmetics only: tether skins, trails, sanctuary themes, emotes, titles.
- `MarketplaceService.ProcessReceipt` with idempotent fulfilment through `ProfileSchema.ProcessedReceipts`.
- Game passes checked with `UserOwnsGamePassAsync`.
- Product IDs in config. Purchase buttons only render when an ID is configured and `Features.Purchases` is on.
- No paid random rewards, no misleading timers, no prompts after failures.

### Trading: a safe design for later

Trading stays off (`Features.Trading = false`) until all of this exists:

1. **Escrow record per trade** in its own DataStore key (`Trade_<TxId>`), advanced only with `UpdateAsync`: `Proposed → Locked → Committed → Applied(A) → Applied(B) → Done`.
2. Both players must be in the same server, and that server must hold both session locks. Both sides confirm twice. Any edit to an offer resets both confirmations.
3. On commit, write the escrow first. Then, in one non-yielding step, move the creatures by ID between the two in-memory profiles and record `TxId` in each profile's trade log. Then priority-save both.
4. **Recovery on load:** a profile with a `TxId` in an `Applied` state checks the escrow and finishes or rolls back idempotently. A creature ID can only exist in one profile, so a duplicate is detectable and repairable.
5. Untradeable flags (starter, locked) are enforced. Rarity and mutation are shown for both sides. Every step is logged.

## Balance notes (to validate in playtests)

Early-game estimates from the current numbers:

| Moment | Estimate |
|---|---|
| First capture | ≈ 30–60 s after joining (guided comet lands at ~6 s) |
| First upgrade (Scanner 2, 250 ✦) | ≈ 2–3 min. The welcome gift covers it on its own. |
| Level 5 (Prism Cliffs requirement) | ≈ 10–12 min of active capturing (742 XP; captures give 45–61 XP; missions add more) |
| Habitat 2 (1,200 ✦) | ≈ 6–10 min (4 commons and uncommons at ~1–3 ✦/s each, plus captures) |
| Habitat 3 (10,000 ✦) | ≈ 30–45 min |
| Habitat 4–5, Scanner 5, Tether 5 | Hours. Intended to pair with Prism Cliffs and later biomes' higher payouts. |

Expected base production of a random Dawn Commons creature is ≈ 6 ✦/s (Σ rarity chance × rate). Most of that comes from rare drops, so a lucky Epic or Legendary is a big, visible jump. Watch Habitat 3–5 pacing once Phase 2 biomes exist, and tune costs or biome payouts through `UpgradeDefinitions` and `BiomeDefinitions`. The offline cap (2 h at 25%) keeps returning players moving without making idling better than playing.

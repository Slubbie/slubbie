# Testing

There are three layers:

1. **Static checks.** StyLua formatting, and luau-lsp type checking of every script against Roblox's full API definitions.
2. **Automated tests.** 91 tests run in [Lune](https://lune-org.github.io/docs). They load the real game modules through a small harness that mirrors the Rojo tree, and run them against mocked engine services and Lune's Roblox DOM. The DOM rejects unknown classes, properties and enum values.
3. **Manual Studio tests.** Rendering, feel, physics, devices and performance, which a headless runner can't judge.

`scripts/check.sh` runs layers 1 and 2 and builds the place file.

## What the automated suite covers

| Spec | What it proves |
|---|---|
| `01_content` | Every content validator passes. Odds, base rates, mutation bonuses, scanner radii, slots, upgrade costs, biome requirements, the XP formula and quality thresholds match the design tables. All 24 species have builders. Trading and purchases are flagged off. |
| `02_math` | Income formula, XP rollover and cap, capture rewards, offline earnings caps. 200,000 rarity rolls match the table within 5σ. Modifiers renormalize. Capture scoring: 1.0 at the centre, 0.55 at the edge, early/late/overcharge misses, quality cap. Number formatting. |
| `03_profile` | Defaults survive a JSON round trip. Missing fields fill in. Impossible values are repaired: negative/NaN currency, levels, equipment, settings, habitat slots, duplicate placements, bad mutations. Unknown species are kept. IDs stay unique. Newer-version data is refused. Migrations run. Private fields stay off the client. |
| `04_persistence` | Save → leave → rejoin on another server. Live locks block a second server. Stale locks are taken over and the old server gets `LockLost`. Retries on transient errors. Safe kick on persistent load failure. Degraded → restored saving. Studio session-only mode. Newer data untouched. Same-server rejoin waits for the final save. Reveal disconnect. Offline earnings once. |
| `05_gameplay` | The full first loop from join to tutorial complete, then rejoin. Tutorial resume. Ordinary capture. Quality never changes odds. Duplicates, stale sessions and spoofed timings rejected. Miss limit and cooldown. Upgrades (affordable, unaffordable, max level). Malformed arguments, ownership attacks, distance, rate limits and not-ready requests. Four players on one comet. Swaps and withdrawals. Release protection. Storage limits. Wisps. Missions claimed once. Level-up rewards. Locked biomes. Ordered deltas. Invalid economy amounts. Comet spawning and expiry. |
| `06_world` | Builds the whole world, all 24 species × 5 mutations, silhouettes, and the tether at all 25 level combinations. Impact sites sit on islands, at least 30 studs apart. Habitat pads stay inside plots and don't overlap. Key locations fall in the right areas. Reports part budgets. |
| `07_client` | Boots every client controller. Comets render from fall to impact. A capture is played with real timed inputs through to the automatic reveal. Every panel and inventory tab renders. Both habitat pickers work. Deltas update the UI (and old ones are ignored). Every notification type renders. Wisps are collected. Settings save. |

### The spec's acceptance tests

| Test | Covered by | How |
|---|---|---|
| **A** First-time player | `05` "join → guided comet → … → upgrade", "the tutorial resumes…" | Automated, end to end, then rejoin |
| **B** Ordinary capture | `05` "one validated capture…" | Automated |
| **C** Duplicate requests | `05` "repeating a completed capture…", "a stale session ID…", "timing reports…" | Automated |
| **D** Equipment purchase | `05` "an affordable upgrade…" | Automated |
| **E** Insufficient funds | `05` "an unaffordable upgrade…" (whole profile compared before and after) | Automated |
| **F** Save and rejoin | `04` "a new player is created, saved…", `05` Test A rejoin | Automated, across two simulated servers |
| **G** Reveal disconnect | `04` "leaving during a reveal…" | Automated |
| **H** Invalid remote request | `05` "malformed arguments…", "nobody can touch…", "captures from across the map…" | Automated |
| **I** Multiplayer | `05` "each player captures the same comet once…" | Automated for shared comets. The cooperative Rift Pulse event is Phase 3. |
| **J** Performance | Part budgets in `06` | **Manual** (below) |
| **K** Mobile interface | `07` boots and drives every screen | **Manual** on device emulation (below) |
| **L** DataStore failure | `04` load failure, save failure and recovery, Studio mode, newer data | Automated |

The suite can't judge how the game looks or feels, real physics, network latency, real DataStore throttling, or frame rates. That's what the manual tests are for.

## Manual Studio procedure: the first gameplay loop

Use a published place with **Enable Studio Access to API Services** on. Start with **Play** (one player). Times are from the moment you spawn.

| # | Do | Expect |
|---|---|---|
| 1 | Spawn | Loading screen fades out. You're on the south plaza facing the observatory. The HUD shows ✦ 0, Level 1, the tracker "GETTING STARTED · 1/7 — A comet just landed!". |
| 2 | Wait ~3 s | A guiding comet streaks in from behind the observatory with a trail, a landing ring, an impact flash, a shockwave, dust and a camera nudge, landing on the promenade ahead. A gold waypoint marker points at it. |
| 3 | Walk to it (≈ 55 studs) | The tracker moves on to "Stabilize the comet". The marker reads "☄️ LOCKED" and the comet is highlighted. A prompt "Stabilize · Guiding Comet" appears. |
| 4 | Press **E** | Movement pauses and the minigame opens. Press Space when the light crosses the glowing ticks. Hold Space, then release in the green band. The tutorial zones are very wide and you can't fail. |
| 5 | Finish | "CONTAINED! · <RANK> CAPTURE · +✦ +XP" appears, then the reveal opens automatically: **Pebblepuff**, Common, NEW SPECIES. Within about 40 s of joining. |
| 6 | Click **Place in Habitat** (or Continue and walk) | Either the habitat picker opens, or the tracker says "Bring Pebblepuff home" with a marker to your plot. **🏠 Home** works too. |
| 7 | Enter your plot, use a glowing pad (E) and choose Pebblepuff | The creature appears on the pad, bobbing and blinking. The pad glows white (Common). The tracker gives **+250 Stardust** (welcome gift). The HUD shows "+1/s" and Stardust counts up. The plot sign shows your name and income. |
| 8 | Wait ~5 s | The step "Watch your sanctuary work" completes. |
| 9 | Follow the marker to the Workshop (west side of the hub), press E | The Workshop shows Scanner Lv 1 → 2 (38 → 44 studs, NEW: type readout) with the cost **250 ✦**. |
| 10 | Upgrade | "Comet Scanner upgraded to Lv 2!". The device in your hand gains an antenna. The tutorial completes and Mission 1 "Comet Chaser" appears. |
| 11 | Press **T → Dawn Commons** | Fade, then you arrive in Dawn Commons with its title card. Comets land every 20–35 s, and wisps sparkle near you. |
| 12 | Capture a regular comet, open the core | Normal minigame difficulty. The reveal tier depends on rarity. |
| 13 | **Stop**, then **Play** again | No tutorial comet. Your creature is in its habitat. Stardust, level, scanner level and mission progress are as you left them. If you were away 5+ minutes with creatures deployed, a "Welcome back!" card shows offline earnings. |

### Multiplayer (Test I)

**Test → Clients and Servers → 3 players.**

- Each player gets a different plot.
- Comets appear for everyone.
- Two players can each capture the same comet, and each gets one core.
- While someone stabilizes, others see a lavender tether beam from their device.
- Habitat prompts on someone else's plot are disabled.
- The hub leaderboard lists all three.
- When a player leaves, their plot resets to "Open Sanctuary".

### Mobile and controller (Test K)

**Test → Device emulator** (a phone in landscape).

- The HUD switches to the touch layout: two rows of buttons top-right and the scanner strip top-left.
- The prompt is tappable.
- The minigame shows a large TAP/HOLD button. Holding charges and releasing locks the result.
- Panels fit the screen and scroll.

With a gamepad:

- X uses prompts and A drives the minigame.
- The D-pad opens Quests, Creatures, Workshop and Travel. B closes panels.
- Selection starts on a panel's first button.

### Performance (Test J)

12 players (Test → Local Server, 12 clients, or a live test with friends), full sanctuaries, several comets active. Open the MicroProfiler (Ctrl+F6) and the Developer Console (F9 → Memory, Network).

| Target | Expect |
|---|---|
| Desktop | 60 FPS |
| Low-end phone | 30 FPS on the Low preset |
| Server heartbeat | 60 Hz |
| Memory | No steady climb after comets come and go (sites are destroyed and effects are pooled) |
| Network | Replication stays small: one delta batch per frame, at most |

### DataStore failure (Test L, live)

- Turn off **Enable Studio Access to API Services** → the session-only banner appears and nothing is saved.
- To see the "Saving is delayed" banner in Studio, temporarily add `error("simulated outage")` as the first line of the transform function in `ProfileStore.Save`, play for a minute (autosave runs every 60 s), then remove it. The automated tests cover the same path.
- Join the same account in two servers at once → the second waits, then shows "Your save is still open on another server". It never loads stale data.

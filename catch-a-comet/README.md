# Catch a Comet! ☄️

A multiplayer Roblox creature-collecting adventure. Comets fall across a floating cosmic archipelago; you track them down, stabilize them in a short timing minigame, and open the sealed core to find a celestial creature. Creatures live in your personal sanctuary and gather Stardust, which pays for better equipment, bigger habitats and (soon) new regions of the sky.

This folder is **Phase 1: the fully playable core**. A new player can join, follow the guided comet, capture it, meet their first creature, place it in a habitat, earn Stardust, buy an upgrade, leave, and come back with everything intact. Later phases (more biomes, world events, expeditions, bonding) are planned in [docs/ROADMAP.md](docs/ROADMAP.md). They are not in this build and nothing in the game pretends they are.

## What's in Phase 1

- **The world.** Celestial Crossing, the central hub, is built in code: an observatory with a turning armillary sphere, the Equipment Workshop, a mission board, a leaderboard, the comet examination station, crystal sculptures, banners, waterfalls and portals. Twelve personal sanctuary plots ring the hub on bridges. **Dawn Commons** is five pastel islands with luminous streams, flower fields, observation decks and old craters, plus 27 validated comet impact sites and 22 wisp spots. A cloud sea lies below, with planets and a giant ring on the horizon.
- **Comets.** A server registry spawns a comet every 20–35 s at validated sites, capped per biome and in total. There are four comet types (Spark, Ember, Glacier, Nova) that differ in size, look, difficulty and payout. Comets are shared, but every player can capture each one once. On the client each comet falls with a trail and a landing telegraph, hits with a shockwave, flash and sound, and leaves a crater with a light pillar, a distance marker and the capture prompt.
- **The capture minigame.** Stage 1 is Energy Lock: press while the light crosses the zone. Stage 2 is Stabilize: hold, then release in a drifting band. Stage 3 is Containment. Quality ranks are Bronze, Silver, Gold and Perfect. Feedback is instant on the client while the server re-scores every press with the same shared math and owns the reward. It works with keyboard, mouse, gamepad and touch (a big on-screen button). An **Easy Capture** setting widens the zones and never touches creature odds.
- **Creatures.** All **24 species** from the design are built from parts, each with its own silhouette, blinking eyes and secondary motion (wings, tails, orbiting rings). There are **5 mutations** (Charged, Aurora, Eclipse, Prismatic) with their own visuals. The server rolls rarity, then species from the comet's biome, then mutation. Common finds get a quick reveal; Epic and above get rays, a flash and a fanfare. Reveals can be skipped.
- **Inventory and collection.** A creature grid with sorting and filters, a detail view (3D preview, stats, place or withdraw, favourite, lock, two-step release), sealed cores, a collection book with silhouettes for undiscovered species, and the exact discovery odds.
- **Sanctuaries.** Four habitat slots, up to twelve with upgrades. Place creatures from the inventory or from a pad; swaps and moves never duplicate or lose a creature. Deployed creatures idle, blink and look at nearby players. Each Habitat level visibly adds to the plot: glowing paths, a floating star ring, a fountain, then floating islets.
- **Economy.** Passive Stardust at the spec rates (Common 1/s … Mythic 250/s, × mutation × bond). Fractional income is carried over. Offline earnings are 25% of your rate for up to 2 h, measured on the server clock. Stardust Wisps, revealed by your scanner, give you something to collect between comets.
- **Equipment.** **Scanner** (38 → 68 studs; comet lock-on, type and time readouts, guide beam, wisp magnet), **Tether** (wider zones, steadier dial, quality bonus) and **Habitats** (4 → 12 slots). Costs match the spec. Your handheld Comet Tether changes look with each upgrade, and other players can see it.
- **Progression and quests.** Levels on the spec XP curve, a 7-step guided tutorial that resumes if you leave, and 11 Explorer missions on a data-driven quest framework.
- **UI.** A cosmic design system (palette, type, components) with a HUD, panels, toasts, banners, a welcome-back card, waypoints with off-screen arrows, a separate touch layout, gamepad shortcuts and selection, reduced-motion and graphics presets, and three volume groups.
- **Reliability.** Session-locked DataStore saves with retries, autosave, priority saves, release on leave and shutdown handling. Versioned migrations and integrity repair. Clear player messages when saving is degraded. Schema-validated, rate-limited remotes. Every reward is server-authoritative.

The honest gaps (no handcrafted meshes, built-in sounds only, unbuilt biomes) are listed in [docs/ROADMAP.md](docs/ROADMAP.md#known-limitations).

## Running it

The project uses [Rojo](https://rojo.space), like SKYBOUND in the repo root.

1. Install [Rokit](https://github.com/rojo-rbx/rokit) and run `rokit install` in this folder (installs Rojo, StyLua, Selene, Lune and luau-lsp).
2. In Roblox Studio, create a new **Baseplate** place and install the Rojo plugin.
3. Run `rojo serve` in this folder and click **Connect** in the plugin.
4. Press **Play**. The server builds the world on start (it removes the template baseplate).

Full setup, including where every script lives, Game Settings, DataStores and publishing, is in **[docs/STUDIO_SETUP.md](docs/STUDIO_SETUP.md)**. To build a place file instead: `rojo build -o catch-a-comet.rbxl`.

## Controls

| Action | Keyboard / mouse | Gamepad | Touch |
|---|---|---|---|
| Stabilize a comet, use a habitat | E (at the prompt) | X | tap the prompt |
| Minigame: lock / hold to charge | Space, E or click | A or R2 | big on-screen button |
| Quests · Creatures · Collection | J · I · C | D-pad up · D-pad left | HUD buttons |
| Workshop · Home · Travel · Settings | U · H · T · O | D-pad right · — · D-pad down · Select | HUD buttons |
| Close a panel | ✕ or click outside | B | ✕ or tap outside |

## Layout

```
src/shared/   → ReplicatedStorage.Shared       config, content, math, remotes, rigs
src/server/   → ServerScriptService.Server     Bootstrap, Services/, Data/, World/
src/client/   → StarterPlayerScripts.Client    ClientBootstrap, Controllers/, UI/
tests/        → not synced: Lune test harness and specs
docs/         → architecture, Studio setup, testing, roadmap
```

See **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** for every module's responsibility, the persistence model and the remote contract.

## Checking the code

```sh
scripts/check.sh               # everything below, in order
stylua --check src tests       # formatting
luau-lsp analyze …             # type check against Roblox's API (the script downloads the definitions)
lune run tests/run.luau        # 91 automated tests: content, math, profiles, persistence, gameplay, world, client
rojo build -o catch-a-comet.rbxl
```

[docs/TESTING.md](docs/TESTING.md) explains what the suite covers and gives the manual Studio procedure for the full first loop.

## Tuning

Every number lives in `src/shared`: systems tuning in `GameConfig`, odds in `RarityConfig`, content in the `*Definitions` modules. Shared modules feed both the UI and the server, so the displayed values and the real ones can't drift apart.

# Studio setup

## Option A — Rojo (recommended)

1. Install [Rokit](https://github.com/rojo-rbx/rokit), then run `rokit install` inside `catch-a-comet/`.
2. In Studio: **File → New → Baseplate**. Install the Rojo plugin (`rojo plugin install`, or from the Creator Store).
3. In `catch-a-comet/`, run `rojo serve`. In Studio, open the Rojo plugin and click **Connect**.
4. Apply the place settings below, then press **Play**.

Rojo also sets these properties from `default.project.json`:

| Instance | Property | Value |
|---|---|---|
| Players | CharacterAutoLoads | false (the server spawns characters once the world is built) |
| Workspace | StreamingEnabled / StreamingMinRadius / StreamingTargetRadius | true / 160 / 900 |
| Workspace | FallenPartsDestroyHeight | -500 (fall recovery catches players long before) |
| Lighting | Technology | Future |
| StarterPlayer | CharacterWalkSpeed / CameraMinZoomDistance / CameraMaxZoomDistance | 20 / 6 / 45 |
| SoundService | RespectFilteringEnabled | true |

To make a place file without syncing: `rojo build -o catch-a-comet.rbxl`, then open it in Studio.

## Option B — by hand

Create these instances and paste each file's contents into them. The **name** must match exactly, because scripts find each other by name.

| File | Create in Studio | Type |
|---|---|---|
| `src/shared/*.luau` (17 files) | `ReplicatedStorage › Shared` (Folder) — one per file, named after the file without `.luau` | ModuleScript |
| `src/server/Bootstrap.server.luau` | `ServerScriptService › Server` (Folder) › **Bootstrap** | Script |
| `src/server/Services/*.luau` (18 files) | `ServerScriptService › Server › Services` (Folder) | ModuleScript |
| `src/server/Data/ProfileSchema.luau`, `ProfileStore.luau` | `ServerScriptService › Server › Data` (Folder) | ModuleScript |
| `src/server/World/*.luau` (5 files) | `ServerScriptService › Server › World` (Folder) | ModuleScript |
| `src/client/ClientBootstrap.client.luau` | `StarterPlayer › StarterPlayerScripts › Client` (Folder) › **ClientBootstrap** | LocalScript |
| `src/client/Controllers/*.luau` (19 files) | `StarterPlayer › StarterPlayerScripts › Client › Controllers` (Folder) | ModuleScript |
| `src/client/UI/Components.luau`, `Viewport.luau` | `StarterPlayer › StarterPlayerScripts › Client › UI` (Folder) | ModuleScript |

Then set the properties in the table above by hand. Nothing else needs creating: the world, lighting, remotes, UI and sounds are all built by the scripts.

## Place settings (Game Settings)

| Where | Setting | Why |
|---|---|---|
| Security | **Enable Studio Access to API Services** | Lets Studio test real saving. Without it the game runs in *session-only mode*: everything works, a banner says progress won't be saved, and nothing is written. |
| Places | **Max Players = 12** | One sanctuary plot per player (`GameConfig.MaxPlayers`). A 13th player can still capture comets but has no plot, and is told so. |
| Avatar | R15 or R6 | Both work. The Comet Tether attaches to `RightHand` (R15) or `Right Arm` (R6). |
| Publish | **File → Publish to Roblox** | DataStores and AnalyticsService only work in a published place. |

Optional:

- **Terrain → Decoration** on: adds grass blades to the terrain islands. Scripts can't turn it on.
- **Analytics:** the game sends onboarding-funnel, economy, progression and custom events through `AnalyticsService`. View them under Creator Dashboard → Analytics once published.

## Content you can drop in

| What | Where | Notes |
|---|---|---|
| Handcrafted creature models | `ReplicatedStorage › Assets › CreatureModels › <SpeciesId>` (Model) | Needs a `PrimaryPart` at the feet, facing −Z. Used instead of the procedural model everywhere (displays, portraits, reveals). Part `Motion` attributes (see `CreatureRig`) animate sub-parts. |
| Extra comet impact sites | any Part tagged `ImpactLocation` with a string attribute `Biome` | Validated against ground and clearance like the built-in sites. |
| Music | `GameConfig.Audio.Music.<Area>` | `{ Id = "rbxassetid://…", Volume = 0.5 }`. With no tracks, the soft generative chimes play. |
| Better sound effects | `GameConfig.Audio.Sounds.<Name>.Id` | The defaults are Roblox's built-in client sounds, so nothing depends on assets that might be private or moderated. |

No asset IDs are invented anywhere in the project.

## Developer products and game passes

Not set up. `GameConfig.Features.Purchases` is `false`, and no purchase buttons exist. The profile already has `ProcessedReceipts` for idempotent receipt handling when products are added in Phase 5.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Yellow "Session-only mode" banner in Studio | Enable Studio Access to API Services (and publish the place). |
| Output shows `[Content] Invalid game content` and the server stops | A definitions table is inconsistent. The message lists each problem. |
| `[World] Dropped invalid Impact site …` | A generated or hand-placed impact site had no ground or was blocked. The game keeps the valid ones. |
| Stuck on "Charting the stars…" | The client couldn't load its state. Check the server Output for a bootstrap error. |
| No character spawns | Make sure `Players.CharacterAutoLoads` is false *and* the server bootstrap ran (`[Catch a Comet] Server ready` in Output). |

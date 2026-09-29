# Evergrove — design and architecture

This document explains how Evergrove is put together: the runtime structure, the data model, and how each gameplay system works. The code is heavily commented; this is the map.

## Principles

- **Server-authoritative.** Clients only *ask*: every action goes through one validated network router, and every rule (reach, ownership, permissions, costs, cooldowns, quantities) is checked on the server. The client renders and predicts nothing that matters.
- **Data-driven.** Content and balancing live in `src/shared/Config`. The item registry, collection book, shops, recipes, quests and models are generated from it, and the test harness checks every cross-reference.
- **Timestamps, not ticks.** Crops, machines, animals, exports and buffs store when things started; their state is *settled* from timestamps when someone looks, when automation passes, or in a light sweep. This makes offline progress exact and keeps the per-frame cost flat.
- **One shared world clock.** Calendar, weather, market trends, hot items and festivals are deterministic functions of real time, identical on every server and on every client — so they can be forecast and shown transparently.
- **Modular.** Server features are services, client features are controllers, UI screens are modules; all reach each other through lazy locators at call time, never at require time.

## Runtime structure

```
ReplicatedStorage.Shared   (src/shared)   Config · Lib · Models      — used by both sides
ServerScriptService.Server (src/server)   init → World build → Services.Boot()
StarterPlayerScripts.Client (src/client)  init → Controllers.Boot()
```

**Services** (`src/server/Services/init.luau`): 43 ModuleScripts, each an optional `Init()` (register handlers, create folders) and `Start()` (connect events, start loops). `S.Name` resolves lazily, so `S.Inventory.Add(...)` works from anywhere without require cycles. Boot runs every `Init` in order, then every `Start`, each in `pcall` so one failure can't take the server down.

**Controllers** (`src/client/Controllers/init.luau`): the same pattern on the client (`C.State`, `C.Windows`, `C.HUD`, …), 21 controllers.

**Screens** (`src/client/UI/Screens`): each module returns `{ Id, Title, Icon, Size, Watch?, Build(win, ctx) → { Refresh?, Destroy? } }`. `C.Windows.Open(id, args)` builds it inside a themed window; `Watch` lists profile keys whose changes re-render it (coalesced to one refresh per frame).

## Networking and security (`Lib/Net.luau`, `SecurityService`)

Two client→server channels — `Request` (RemoteFunction, returns `ok, result`) and `Signal` (RemoteEvent, fire-and-forget) — carry ~110 named actions. Each action is declared once with a token-bucket rate limit and an argument schema (`"string:40"`, `"int"`, `"Vector3"`, `"table?"`…). The router rejects unknown actions, bad types, NaN/inf, oversized strings/tables and anything over the limit before any handler runs, and reports each rejection to `SecurityService`.

Handlers then validate game rules: distance (`Security.InReach`), farm permissions (`Permission.Allows`), ownership, costs, and plausibility (fishing reel times, race speeds). Violations are counted in a sliding window; crossing `Gameplay.Security.KickThreshold` kicks. Character movement is tracked so actions straight after an impossible jump are refused.

Server→client channels: `Sync` (profile replication), `Notify` (toasts, banners, rewards, level-ups, discoveries, quests, tutorial), `FX` (world feedback), `Dialogue`, `Trade`, `Festival`, `AdminLog`.

## Player data (`DataService`)

One DataStore key per player: `{ Data, Lock, Saved, Version }`.

- **Session locking** with `UpdateAsync`: a server takes the lock on load, waits briefly for another server that's still saving, and never overwrites a save once it has lost the lock.
- **Safe writes**: every save is sanitised (only JSON types, no NaN/inf, bounded depth), retried with backoff, and a backup copy is written every few saves. A corrupt main record falls back to the backup.
- **Migrations**: profiles carry a schema version and are upgraded step by step, then reconciled with `NewProfile()` so new fields always exist.
- Autosave, save-on-leave, `BindToClose` waiting for every save, and immediate saves after trades/stall sales. Without API access (Studio) everything runs in memory.
- **Replication**: the owning client gets a full snapshot, then batched path patches whenever a service calls `Data.Changed(player, ...path)`. Large private tables (farm tiles, placed objects) are not replicated — the world carries them as instances/attributes instead.

## Time, seasons and weather (`Lib/GameTime`, `Lib/WeatherMath`, `TimeService`, `WeatherService`)

A day is 20 real minutes; seasons are 7 days; the calendar is computed from real time since the world's epoch. `ReplicatedStorage` attributes (`ClockBase`, `ClockAnchor`, `ClockScale`) let a solo private server slow time while a menu is open, and admins skip time. Weather rolls per 6-hour slot from a seeded hash (with persistence so it doesn't flicker), filtered by season and day/night, so every server and client agrees and the calendar can show a real forecast. Regions twist it (`WeatherMath.ForRegion`: in the Dunewind desert rain becomes a sandstorm, in the Hidden Valley it becomes rainbow mist). Each weather type drives lighting, precipitation, wind, sounds, crop moisture and growth, mutation chances, fish, animal happiness, hazards and market demand.

## Farming

**Lots** (`World/FarmBuilder`, `FarmService`): six lots, each a 5×5 grid of 12×12-tile parcels with its own soil character (fields, meadows, woods to clear, riverside ponds, hillsides, pasture) plus a yard with the farmhouse, bin, well, workbench and mailbox. Players buy adjacent parcels; the house has 5 levels.

**Tiles** carry moisture, soil health and N-P-K nutrients (`SoilService`). Watering, fertilizers, amendments, sprinklers and mist towers change them; neglected soil dries and eventually reverts to grass.

**Crops** (`CropService`, `Lib/CropMath`, `Lib/QualityMath`): growth is `CropMath.Advance(tile, crop, env, t0, t1)` — a pure function of time, the season, the weather timeline, moisture band, nutrients, rotation family, companion plants, tolerances, greenhouses, needs (special soils), skills and buffs. A round-robin scheduler advances a slice of crops per Heartbeat (`Gameplay.Performance.CropsPerStep`), so cost is flat. Harvest quality (6 tiers) comes from a score over care factors; premium harvests, yield chances and sizes roll at harvest.

**Mutations** (`Config/Mutations`): 22 mutations with conditions (weather, time, season, neighbours, fertilizer, region…) roll while a crop grows; combinations resolve into 7 combos. They multiply value, change the model's look and pass into artisan goods.

**Genetics** (`Lib/Genetics`): seeds carry four genes (Vigor, Bounty, Hardiness, Luster). Harvests pass genes on with small drift, the Genetics Lab crosses same-crop seeds, and 14 hybrid recipes create new species with a chance boosted by the right weather or season. Seeds can carry a latent mutation trait.

**Hazards**: pests and disease (blight spreads to same-family neighbours) are treated with sprays and prevented by rotation and companions; hail and scorching heat bruise quality but never destroy a crop; lightning can strike a crop (a Charged mutation or a setback), and a lightning rod catches strikes and turns them into batteries.

## Building and decoration (`BuildingService`, `DecorationService`, client `BuildController`)

Placed objects are records `{ Id, Px, Pz, Ry, Py?, Sc?, C?, Mt?, Tx?, … }` in lot-local studs. Placement validates bounds, parcel ownership, footprint overlap (with an occupancy grid), soil rules, per-item limits and permissions, then spawns a procedural model (`Models/*`) with prompts for its function (storage, machine, station, animal home, stall, sign, display, automation). Build mode offers grid and free placement, rotation, scaling, lifting, paint and materials, duplication, copy-style, undo/redo, path painting and a client-side validity preview. Layouts save and restore whole decorating schemes. `DecorationService` scores farm appeal (rarity, variety, theme sets, lighting and water) into tiers with titles.

## Machines and automation (`MachineService`, `AutomationService`)

Machines keep a job queue on their placed record; `advance` works out what finished between two timestamps (offline too, capped). Jobs keep input quality and mutations. Upgrades add speed, queue slots and output storage; windmills and solar arrays speed up nearby machines. With a logistics hub, machines in auto mode pull inputs from silos and push outputs back. Drones harvest and replant into silos, farmbots till/plant/water, collectors and auto-feeders tend animals, and the shipping dock sells silo items matching your rules each dawn.

## Animals (`AnimalService`, `BreedingService`)

Animals live in coops, barns, stables, apiaries and a sanctuary. Their state (happiness, friendship, fed/petted/brushed days, product readiness, pregnancy) settles lazily from timestamps. Personalities change happiness, friendship gain, quality and finds. Coats and patterns are allele pairs with dominance (rare looks are recessive); quantitative stats average parents with noise; rare alleles can appear by mutation. The breeding planner shows exact Punnett odds before you commit. Rare coats can change products (golden hens lay golden eggs). Horses can be ridden.

## Economy (`MarketService`, `EconomyService`, `Lib/MarketMath`)

Price = item value (quality × mutations) × season demand × weather demand × a smooth per-item trend × daily hot items/shortages × (1 − supply pressure) × seller skills × venue. Supply pressure rises with sales and recovers hourly; it's shared across servers through a MemoryStore sorted map. All deterministic parts are computed identically on the client, so the market screen shows history, forecasts (with a perk) and exact estimates. Venues: the shipping bin (paid at dawn), merchants (instant, spread, bulk bonus), contracts (bulk, collector and restaurant orders), exports (delayed premium payout by mail, storms can delay but never lose a shipment), player stalls (with a town fee) and trading. A weekly night market adds a bonus.

## Village life (`NPCService`, `FriendshipService`, `QuestService`, `TownService`)

18 villagers walk daily schedules over a road graph (with rain, season, weekend and festival variants), face you when you talk, and remember you: talking daily, gifts (with discovered preferences), quests and festivals build 10 hearts of friendship (with a gentle decay that never drops below a floor), heart events, birthday bonuses, perks (discounts, recipes, services) and shop unlocks. Quests have typed objectives, requirements and rewards; daily requests follow the real UTC day and scale with estate level; weekly challenges and a server-wide community goal add shared play. Town projects are funded with coins and items and permanently change the village, open regions and unlock features.

## Exploration and gathering

16 regions with unlock conditions (quests, items, skills, projects, estate level, night-only), hazards (cold, heat, darkness — countered by buffs or shelters), their own forage, bugs, fish waters, nodes and dig loot (`MiningService`, `ForagingService`, `FishingService`). Fishing is a skill minigame whose timing the server checks; legendary fish announce to the server. 20 secrets combine places, times, weather and items to reveal lore pages, items and hidden regions (`TownService`).

## Festivals (`EventService`, `Lib/ContestMath`)

Nine festivals run on their calendar days on every server at once: scavenger hunts (per-player collectibles), contests scored transparently by `ContestMath` (the client shows the exact breakdown before you enter), a fishing derby, races with server-validated checkpoints, token challenges and a token shop. Leaderboards are cross-server (MemoryStore) and prizes are mailed once per winner even with many servers.

## Social (`PermissionService`, `MultiplayerService`, `TradingService`, `GuildService`, `MailService`)

Farm permissions have 8 levels (from no visitors to trusted), a default, a friends default and per-player overrides; lowering someone sends them home. Helpers' harvests go to the owner. Trading is proximity-checked, both sides confirm after a review delay, the swap is atomic and both profiles save immediately. Co-ops (cross-server, DataStore-backed) have roles, a bank, weekly goals and upgrades. Mail never drops anything with attachments (overflow queue) and can be sent to offline players.

## Progression

Nine skills level 1–50 with a per-level passive, titles and a branching tree (one branch per tier, respec for escalating coins). Estate level (from total skill levels) gates buildings, land and regions. Ten tool families have six tiers (bigger areas, less energy, abilities) plus powered equipment. The collection book, museum, showcase and 158 achievements (with titles, banners, frames and auras) round it out. `Lib/Stats` computes every effect from a profile, shared by server rules and client display.

## Client

- **State** mirrors the replicated profile; controllers and screens watch keys.
- **Rendering from attributes.** The server exposes tiles, animals, gather spots and players as lightweight parts with attributes; client renderers build and animate the detailed models locally (`Models/Crops`, `Models/Animals`, `Models/Nodes`, `Models/Tools`) with distance-based LOD. This keeps replication tiny and lets every client animate smoothly.
- **Lighting & weather** blend palettes by season, time and region, drive precipitation, fog, wind, lightning, auroras, meteors and rainbows, seasonal terrain colours and festival decor.
- **Audio** plays named cues (captioned) and a generative soundtrack that follows season, weather, time and region.
- **Input** targets tiles (pointer or facing), shows area highlights and crop info, and maps keyboard, gamepad and touch.
- **UI kit** (`UI/Kit`, `UI/Theme`) provides every widget with live theming, colour-blind-safe rarity/quality (shapes and stars as well as colour), reduced motion, text scaling, tooltips and gamepad selection. `UI/Picker`, `UI/SellPanel`, `UI/Prices`, `UI/Describe` and `UI/AnimalInfo` are shared helpers.
- **Build mode, photo mode, the tutorial overlay** and **the HUD** are controllers of their own.

## Performance

StreamingEnabled with generous radii; one scheduler slice per Heartbeat for crops; lazy settlement for machines, animals and automation; attribute-driven client rendering with LOD; coalesced data patches and window refreshes; MemoryStore syncs batched on intervals.

## Monetization

Cosmetic and convenience only (themes, companions, emotes, nameplates, music, layout slots, a supporter pass, gift boxes). No crops, currency, growth, luck or competitive advantage is sold. Pass/product ids are configured in `Config/Store.luau`; unconfigured items show as coming soon. Receipts are idempotent.

## Testing

`tests/bundle.py` bundles `src/shared` with a small fake Roblox runtime and runs `tests/spec.luau` under the standalone Luau CLI: every config cross-reference, registry generation, and the crop, soil, market, genetics, quality and contest math. The code type-checks with `luau-lsp` against the Roblox definitions and is formatted with StyLua.

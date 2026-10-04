# Skyline Legends: design

This document describes how the game plays and where each system lives.
Module paths are relative to `src/`.

## The premise

Meridian was a vertical city held together by skyways and lifts. Ten years
ago the **Severance** cut them, and the city broke into islands of rooftops.
The **Runners' Guild** keeps it one city: runners carry what can't be carried
any other way, restore relays so districts can call for help, and climb toward
the settlements nobody has heard from since. The story (`shared/Config/Quests`,
`shared/Config/Lore`) follows a newcomer from the Training Yard to the top of
the Aether Citadel and the truth about the Severance.

## The loop

**Explore → attempt → improve → earn → unlock → return with new moves.**

1. **Explore** a district: plazas, rooftop routes, landmarks, letters, caches
   and secrets (`client/Gameplay/Explore`, `server/Services/DiscoveryService`).
2. **Attempt** a course or room from its start gate. The preview screen shows
   the route's difficulty, focus, medal times, your record, what each route
   needs, and the leaderboards (`client/UI/Overlay` → `CoursePreview`).
3. **Improve** with retries, practice checkpoints and assists, splits against
   your best, and ghosts of your best run, your friends and the leaders.
4. **Earn** XP, credits, medals, distinctions, mastery points and quest
   progress (`server/Services/CourseService`, `shared/Logic/Rewards`).
5. **Unlock** levels, abilities, skill points, districts, cosmetics and
   titles (`server/Services/ProgressionService`, `EconomyService`).
6. **Return** to earlier courses with new abilities to take the fast and
   expert routes and push for gold and platinum.

Direction is always visible: the pinned objective and its waypoint, "!" and
"?" markers over people with work or news, beacons over every place an active
quest needs, the next medal time during runs, and the next ability unlock in
the skill tree.

## Movement

All movement runs on the player's own client for responsiveness
(`client/Movement/Controller`) and is validated by the server
(`server/Services/MovementGuard`). Values live in `shared/Config/Movement`;
every course gap is sized from the same values (`shared/Logic/Reach`), so
routes stay clearable if movement is retuned.

| Technique | How it works |
|---|---|
| Run / sprint | Acceleration toward a target speed with momentum that decays slowly; skids cost speed when you reverse hard. Sprint drains stamina. |
| Jump | Fixed take-off speed, stronger gravity on the way down, short-hop on early release, **jump buffering** (0.12 s) and **coyote time** (0.1 s). Limited air control steers without killing momentum. |
| Crouch / slide | Slide at speed: slopes accelerate you, you steer gently, jump out to keep the speed. Crouch and slide use a low collision posture, so low gaps really are passable. |
| Vault / step-up | Jump (or sprint, with Auto Vault) into low cover for a scripted arc over it. |
| Ledge grab / mantle / shimmy / ledge leap | Catch ledges in reach, climb up, shimmy sideways, drop, kick off the wall, or leap to a higher ledge. |
| Climb | Ladders, vines and mesh in any direction, with hops at a stamina cost. |
| Wall run / wall climb | Run along walls at speed with a lift that fades; run up walls you face. |
| Wall jump / wall kick | Jump off walls mid-run or from a hang; an emergency kick off any wall saves a bad jump. |
| Double jump | One extra jump per airtime (unlocks at level 4). |
| Directional dash | A short burst toward your input, on charges with a cooldown (level 10). |
| Grapple swing / pull | Swing from rings on a physics rope; pull to diamond anchors (levels 16 and 24). |
| Rope swing / zipline / balance | Catch hanging ropes and pump; ride ziplines with momentum; balance on beams that sway with your speed. |
| Landing roll | Press crouch just before a hard landing to roll out at speed instead of stumbling. |

**Stamina** (`client/Movement/Stamina`) pays for sprinting, wall runs,
climbing, hanging and powerful moves. It refills quickly on the ground, slowly
in the air and never while hanging; running dry locks sprinting until it
recovers. The HUD shows the bar, a preview of what your next move would cost,
and TIRED / EXHAUSTED states in words.

**Recovery** is generous: ledge catches, emergency wall kicks, recovery
platforms built into courses, landing rolls, and instant retries. Falling
out of the world returns you to your checkpoint in a run, or to the most
recent safe ground you stood on while exploring (`client/World/Hazards`).

**Lessons**: the Training Yard has a station per technique
(`shared/Config/Lessons`, `client/Gameplay/Lessons`). Each shows the input for
your device and two short steps that track your real moves.

## The city

`server/World` builds the whole city at server start, deterministically, from
data: `Kit` (parts and details), `CourseBuilder` (course segments),
`DistrictBuilder` (plaza, rooftops, routes, fixtures), one module per district
for its landmarks and story places, the `Spire` and the `Dreamline`.

| District | Identity | Opens |
|---|---|---|
| Guildhall Commons | Hub: Training Yard, practice playground, advanced training, outfitters, quest givers, race board, travel gates, the Spire, the Dreamline portal | Start |
| Tinroof Terraces | Family rooftops, washing lines, water towers, narrow alleys | Graduation |
| Ironworks Quarter | Cranes, conveyors, pistons, steam vents, scrapyards | Level 6 + chapter 1 |
| Verdant Hollow | Overgrown gardens, rope swings, rising water, ruins | Level 14 + chapter 2 |
| Gilded Exchange | Neon financial towers at night, lasers, holograms, express lines | Level 22 + chapter 3 |
| Frostreach | Frozen mountain town: ice, wind, avalanches, the Hollowpeak Mast | Level 32 + chapter 4 |
| Aether Citadel | The sky fortress: low gravity, aether currents, the Keel | Level 44 + chapter 5 |

Every district has a social plaza (job board, race board, course board,
shop stall, lift gate, people), exploration routes between rooftops,
**8 to 12 courses plus challenge rooms**, landmarks, environmental story
(lost letters, abandoned relays, signs of the Severance), supply caches and
secrets. Large silhouettes of the other districts are always visible on the
horizon, so the next goal is always in sight.

### Courses

Courses are recipes of segments (`shared/Config/Courses`). Splits give each
section an **accessible** route (learn it), a **fast** route (confident
execution) and an **expert** route (precision and demanding transitions, often
an expert shortcut that earns a distinction). Scenery is readable: route signs
at every fork, icons on interactive surfaces (optional, by setting), and
hazards marked by shape and motion as well as colour.

Mechanisms are pure functions of shared server time (`shared/Logic/Schedule`),
animated on every client (`client/World/Mechanisms`) so everyone sees the same
door open at the same instant: moving and orbiting platforms, swinging cargo,
spinners and sweepers, collapsing walkways, retracting bridges, timed doors with
traffic lamps, pressure plates and gates (shared for co-op), bounce pads, launch
vents, wind gusts, conveyors, ice, low gravity, aether currents, holograms,
lasers (timed and sweeping) and rising water. Every timed element warns before
it changes: lamps blink, lasers flicker a thin sighting line, bridges shudder,
vents puff.

## Progression

| System | Where | Notes |
|---|---|---|
| Levels and ranks | `shared/Config/Progression`, `ProgressionService` | 100 levels, 14 named ranks from Newcomer to Skyline Legend |
| Abilities | `shared/Config/Abilities` | 16 techniques; the basics at level 1, then double jump (4), dash (10), grapple (16), grapple pull (24), ledge leap (30) |
| Skill tree | `shared/Config/SkillTree` | 28 nodes in Endurance, Agility, Aerial Control and Exploration; respec for credits |
| District milestones | `shared/Logic/Access` | Each district opens with a level and a story chapter |
| Mastery | `shared/Config/Mastery`, `MasteryService` | 8 categories, 5 tiers; a tier needs points from validated use **and** a proficiency challenge; points are capped per minute so spam doesn't work |
| XP sources | `shared/Logic/Rewards` and services | First completions, medal upgrades, distinctions, personal bests, repeat runs (scaled by performance, tapering after many repeats), discoveries, lessons, quests, dailies, weeklies, contracts, races, relays, Spire floors, Dreamline sections, achievements, mastery tiers |
| Flow | `shared/Config/Flow`, `client/Gameplay/Flow` | Varied, quickly linked techniques fill the meter through five tiers; repeats are worth less, stumbles and falls break the chain; in runs the multiplied points become the run's flow score (checked against the moves the server validated) |

### Quests

`server/Services/QuestService` checks every step against validated events,
never client claims.

- **Main story**: a prologue and seven chapters, one per district plus an
  epilogue, completing a chapter pays prestige.
- **Side quests** from the people of each district, and **expert trials**
  (platinum runs, no-fall golds, shortcut golds, legendary flow).
- **Daily objectives** (three per day, one per tier, picked from your unlocked
  techniques, with a bonus for all three), **weekly expeditions** (three per
  week, the same for everyone) and **contracts** from district job boards
  (timed deliveries, relay checks, route certifications).
- Step kinds include talking, reaching places, collecting, activating relays,
  deliveries (some fragile, some timed), course medals with conditions,
  technique counts, move chains, flow tiers, discoveries, lessons, races,
  relays, mastery, crews and the Spire.
- Quests show where they start, what they ask and what they pay before you
  accept, and up to three can be pinned to the HUD.

26 characters (`shared/Config/NPCs`) give work and colour, each with a
personality, a look, greetings and idle lines.

### Medals and distinctions

Each course has bronze, silver, gold and platinum times derived from its
route par times (`shared/Logic/Medals`). Distinctions: **Clean Run** (no falls
or retries), **Pathfinder** (expert shortcut), **Collector** (every token) and
**In the Flow** (flow score target).

## Modes

| Mode | What it is |
|---|---|
| Free exploration | The city itself, with discoveries, contracts and quests |
| Casual runs | Your own movement and upgrades; medals, rewards, records |
| Practice | Assists (endless stamina, generous grabs, relaxed timing, steady beams), custom checkpoints, no medals |
| Ranked time trials | Standardized attributes and the course's full ability kit for everyone; global and friends leaderboards; ghosts |
| Multiplayer races | Lobbies from any race board; everyone readies up, lines up and races on standardized attributes; places and rewards |
| Co-op relays | Teams split a relay course at its exchange gates; the baton passes when a runner crosses; shared medal on team time |
| The Spire | 25 enclosed floors of increasing difficulty and kit, milestones every five floors, a secret roof |
| The Dreamline | Endless lanes of tested sections built ahead of you; three lives; difficulty rises with each gate |

**Fairness:** ranked runs, races and relays use the standard movement values,
so skill-tree upgrades never decide competitive results. Every competitive
time is checked: checkpoints in order and where the character really was,
times bounded by the course's ideal par, and runs with movement anomalies kept
off the boards (`CourseService`, `MovementGuard`, `RecordService`).

## Competition tools

- **Ghosts** of your best run, your ranked best, the fastest friend and the
  board leader, recorded at 15 frames a second and stored compactly
  (`shared/Logic/GhostCodec`, `client/Gameplay/Ghosts`).
- **Splits** at every checkpoint against your best, live on the HUD and on
  the results screen.
- **Attempt inspection**: results show time, delta to best, the next medal and
  how far away it is, every distinction earned or missed, tokens, falls,
  retries, flow score, splits and the reward breakdown.

## Economy and cosmetics

**Credits** come from play; **prestige tokens** only from significant
achievements (platinums, chapters, expert trials, mastery tiers, Spire
milestones, weekly expeditions). 113 cosmetics (`shared/Config/Cosmetics`):
outfits, gloves, shoes, backpacks, trails, landing effects, emotes, titles and
victory animations, sold at the Guildhall outfitters and district stalls or
earned through play. Cosmetics are built from parts at runtime and never
affect movement.

The **achievement journal** (`shared/Config/Achievements`) has 62 entries in
six categories, with progress bars and hidden secrets.

## Social

- **Crews** (`server/Services/CrewService`): a name and tag on your nametag,
  members across servers, and a weekly crew goal everyone contributes to.
- **Players** page: who's here, what they're doing and where; invite them to
  run together, to your race or to your relay team.
- Emotes (an emote wheel of up to eight) and victory animations after a medal.

## Presentation

- **Animation** (`client/Animation/Animator`): procedural R6 poses for every
  state (run cycles that follow real speed, wall-run leans, hangs, climbs,
  balance, swings, vault and mantle arcs, flips, rolls, landing squash),
  emotes and victories, for every player, ghost and NPC.
- **Camera** (`client/Camera/CameraController`): third-person orbit with
  collision, an optional follow assist, speed FOV, wall-run tilt, landing dip
  and shake, all switchable.
- **Atmosphere** (`client/World/Atmosphere`): per-district lighting and
  colour grading, a shared time-of-day cycle and weather windows (motes,
  drizzle, embers, leaves, snow) that every player sees at the same time.
- **Audio** (`client/Audio`): material-aware footsteps for every runner,
  movement cues, speed wind, resource cues (can't afford, empty, refilled,
  dash ready), and adaptive generative music per district that adds layers
  during runs, races and high flow.
- **Effects** (`client/Effects/Effects`): trails at speed, cosmetic landing
  effects, speed lines, the grapple target marker, bursts for dashes and
  double jumps, and a flow aura.
- **Level of detail** (`client/World/Detail`): decoration of distant districts
  is unloaded; on Low quality distant districts collapse to their skyline.

## Interface

- **HUD** (`client/UI/Hud`): stamina with cost previews, air-action pips,
  level and currencies, pinned objectives with a waypoint arrow, the run panel
  (timer, splits, checkpoints, tokens, next medal), the flow meter and chain,
  contextual input hints, the lesson card and mode panels.
- **Menu** (`client/UI/Menu`, `client/UI/Pages`): map with travel, quest
  journal, skill tree, mastery, locker, shop, achievements, courses, records,
  races and relays, crew, players and settings; plus travel gates, the Spire
  and job boards from the world.
- **Overlays** (`client/UI/Overlay`): notifications, banners, countdown,
  course preview, results, dialogue, confirmations and mode results.

## Input and accessibility

Keyboard and mouse, gamepad and touch are all first-class (`client/Core/Input`,
`client/UI/Touch`), with on-screen glyphs for the current device. Settings
(`shared/Config/Settings`) include full key and button remapping, sprint and
crouch hold/toggle/auto, mouse/controller/touch sensitivity, invert Y, mouse
lock, camera follow assist, field of view, **reduced motion** (turns off every
camera effect at once) and individual motion toggles, text size, HUD size,
surface icons, high-contrast markers, input hints, default ghost, graphics
quality, weather, time of day, shadows, trails and five audio channels. States
are never shown by colour alone: medals have glyphs, timers and lamps blink,
locked things say why.

## Saving and security

- **Saving** (`server/Data/DataService`): session-locked profiles with
  migrations, autosave, save on leave and on shutdown, retries, and an
  in-memory mode with a clear notice when DataStores are unavailable.
- **Networking** (`shared/Net`): every client-to-server route is declared with
  a rate limit; handlers are isolated so one failure never takes others down.
- **Validation**: movement actions are checked against where the character
  is and what it has unlocked; positions are sampled for impossible speeds and
  unannounced teleports; checkpoints, tokens, shortcuts, quest points,
  discoveries, switches, lessons and gates are only accepted near the real
  place; ghosts are shape-checked before storage; player text is filtered.

## Extending it

- **A new course**: add a recipe to `shared/Config/Courses` with the district
  it belongs to; the world builder places and builds it, and every system
  (medals, preview, records, quests) picks it up.
- **A new district**: add it to `shared/Config/Districts` and a module under
  `server/World/Districts` with its landmarks, quest points and skyline.
- **A new mechanism**: tag a part (`shared/Tags`) and add its behaviour to
  `client/World/Mechanisms`.
- **A new quest step, achievement, cosmetic or mastery challenge**: add data
  to the matching config module.
- **A new remote**: declare it in `shared/Net` with a rate limit and handle it
  in a service.

The headless tests in `tools/headless` build the city, every course, boot the
server and client and play through the main loops; run them after changes.

# VARIANCE — Architecture

```
                        ReplicatedStorage.Variance (src/shared)
      ┌────────────────────────────────────────────────────────────────────┐
      │ Core/  Engine (pure state machine) · Probability · Instruments     │
      │        Modifiers · Modes · Rules · Timeline · Rating · Report      │
      │        TutorialDirector · AI/ (Solver, Brain, Difficulty, ...)     │
      │ Data/  content tables    Visual/  primitive builders    Util/      │
      │ Config · Net (remote contract)                                     │
      └────────────────────────────────────────────────────────────────────┘
               ▲ required by both                        ▲
   ServerScriptService.VarianceServer          StarterPlayerScripts.VarianceClient
   28 services + Match/ + World/               17 controllers + UI/ + Match/
         │   Act / Request / Look (client → server)   │
         └─────────── Match / Push / Look (server → client) ─┘
```

The rules live in one pure-Luau module with no Roblox dependencies. The
server owns a state per match and is the only authority; clients receive
exactly the information their seat is entitled to and present it.

---

## 1. The engine (src/shared/Core)

### State machine

`Engine.new({Rules, Subjects, Rng, Filter?})` creates a state that moves
through phases:

```
Created → TrialSetup → LoadSetup → TurnSetup → AwaitAction ─┐
             ▲            ▲           ▲           │ act()    │
             │            │           └───────────┤ (keep)   │
             │            └── LoadEnd ◄───────────┤          │
             └──────────── TrialEnd ◄─────────────┘          │
                              └─► MatchEnd → Ended           │
```

- `Engine.advance(state)` performs one automatic step (deal a Load, start a
  turn, end a Trial...) and returns the events it produced.
- `Engine.act(state, subjectId, action, token)` validates and applies one
  action. The **turn token** changes after every accepted action, so a stale
  or duplicated action is rejected even if it arrives between batches.
- `Engine.timeout`, `Engine.forfeit` are safe in any phase.
- `Engine.legal(state, subjectId)` lists every action with `Ok` and, when
  unavailable, a human-readable `Reason` (the HUD shows these verbatim).
- Randomness comes only from the injected RNG, so any match can be replayed
  from its seed (the tests do this).

### Events and privacy

Every event is `{ Type, Public, Private? }`. `Private[subjectId]` holds what
only that subject learns (a Lens reveal, a Precision glimpse, their own
belief). Events carry the **belief** of each viewer: per remaining cell its
public polarity parity and, if known to that viewer, its type. The real
sequence never leaves the server; the client builds cell models from the
announced counts only.

### Probability

`Probability` works on beliefs: unknown cells are exchangeable, so the chance
a position is CHARGED is (charged originals left − known charged originals) /
(unknown cells), adjusted for inversions (a cell's parity flips what its
original type means). Blind Loads use Laplace's rule of succession. The same
functions power the HUD, the AI and the post-match key moments.

### Timeline contract

`Timeline.after(event, scale)` is how long the server waits after sending an
event before the next one (a Load waits 1.6 s + 0.34 s per cell; the silence
before an outcome grows with public tension, never with hidden information).
The client choreographs every beat to fit inside these windows, so all
viewers see the same moment together and nobody can act while an outcome is
still on screen.

### Rules, modes, modifiers

`Modes` define metadata (queue, ranked, progression, XP scale) and a base rule
set; `Rules.build(modeId, custom?, overrides?)` expands it through escalation
profiles and modifiers into a flat rule table. `Rules.CustomSchema` is the
single schema for custom rules: the host UI is generated from it and the
server sanitizes every value through it.

### AI (Core/AI)

- `Solver`: memoized exact win probability over the public state.
- `Brain`: per-surrogate reasoning (see DESIGN §6): observes public events,
  maintains its own belief and memory (with tier-dependent lapses), models
  the opponent (`Tendencies`), scores actions by win-probability delta,
  applies personality biases and picks with a softmax temperature.
- `Difficulty`: tiers as reasoning modes (Gut / Heuristic / Utility) and
  parameters; `adaptive(skill)` for the Adaptive opponent.
- The AI only ever sees `Engine.aiView(state, id)` — exactly a player's view.

---

## 2. Server (src/server)

`init.server.luau` requires every service, calls `Init(services)` in a fixed
order (no yielding), then `Start()` on each in its own thread.

| Service | Responsibility |
|---|---|
| AntiExploitService | suspicion scoring with decay; severities Minor→Critical; logs and kicks |
| NetworkService | remotes, token-bucket rate limits, endpoint schemas and argument checks, push/match helpers |
| DataService | profiles: session-locked UpdateAsync, retries with backoff, schema versions and migrations, sanitizing, guest mode with background adoption, autosave, BindToClose |
| SettingsService | validated settings save/load |
| CosmeticService | ownership, grants from every source, equip, Mark purchases, the "look" sent to matches |
| ProgressionService | XP, levels, Marks, profile snapshots to the client, match rewards |
| StatisticsService | lifetime stats, history, adaptive skill, Proctor unlock |
| ChallengeService | daily/weekly directives, progress, claims |
| AchievementService | evaluation (incl. hidden) after matches and events |
| LoreService | unlocks, reading with personalised text |
| MonetizationService | idempotent ProcessReceipt, passes, prompts (cosmetic only) |
| LeaderboardService | OrderedDataStore boards with batched writes and cached reads |
| RankedService | ratings, divisions, placements, seasons, abandon penalties and lockouts, previews |
| CharacterService | R6 characters, nameplates, seating (anchored, match cosmetics), lobby spawns |
| ArenaService | arena slots far from the lobby, building and releasing rooms, puppets |
| DialogueService | surrogate lines by trigger and personality, cooldowns |
| AIService | brains per surrogate, decisions with think time, debug overrides |
| SpectatorService | live list, spectate via ReplicationFocus, competitive delay |
| ChatGuardService | TextChatService delivery rules (spectators muted in competitive Trials) |
| MatchService | match lifecycle, input handling, disconnects/rejoins, post-match, rematch, Endurance chaining, sandbox |
| MatchmakingService | queues (solo and party entries), widening rating windows, surrogate backfill |
| LobbyService | private lobbies, invite codes in MemoryStore, cross-server joins via TeleportAsync, friend invites via LaunchData, host migration |
| TournamentService | single-elimination brackets, instant AI-vs-AI pairings |
| ReconnectService | cross-server "return to your match" offers |
| TutorialService | lessons on the real engine via TutorialDirector hooks |
| AmbientEventService | per-room ambient and rare events |
| LobbyWorldService | builds the Intake, fills boards, PA broadcasts |
| DebugService | permission-gated debug commands and a validation suite |

### Match lifecycle

1. `MatchService:create(spec)` builds rules, acquires an arena, seats players
   (and surrogate puppets), sends each participant `Begin` (scene + their own
   snapshot) and starts a `MatchRunner`.
2. `MatchRunner:run()` loops: apply queued forfeits, `Engine.advance`, or wait
   for the acting subject. Each batch of events is sent through the
   `Dispatcher` and paced with `Timeline.after`.
3. Input: `Act` → `MatchService:handleAct` validates types and the instrument
   id the client saw → `MatchRunner:submit` validates through the engine
   **immediately** but only queues the events; the runner presents them. While
   a batch presents, the runner is `busy` and all other submissions are
   rejected, so two actions can never both apply.
4. Turns: the runner broadcasts `Turn` (owner, token, timer) and sends the
   actor its legal actions. Surrogates are scheduled with a think time.
   Timers pause while the acting subject is reconnecting; two consecutive
   timeouts in PvP forfeit.
5. `finish` builds the report, rates ranked matches, awards progression per
   player, sends `PostMatch`, then opens the rematch window or closes after
   the linger time. `close` detaches everyone and releases the arena.

### Dispatcher

Routes each event per recipient: `Public` merged with that recipient's own
`Private` entry. Spectators get `Public` only, delayed in competitive modes
(events and turn markers alike). Events are numbered so a client can detect
a gap and resync with `Match.Sync`.

### Data

- One DataStore key per user. Loads take a **session lock** inside
  `UpdateAsync` (JobId + time); a fresh lock held by another server makes the
  load wait and retry; a stale lock (older than `Config.Data.LockStaleAfter`)
  is taken over. Saves verify the lock is still ours; losing it stops saving.
- Budget-aware retries; permanent errors (no API access in Studio) fall back to
  a **guest session** that keeps retrying and adopts the saved profile when
  it becomes available, merging what was earned meanwhile.
- `SchemaVersion` with ordered migrations; every load is sanitized against the
  default template (types, ranges, unknown ids).
- Autosave on an interval for dirty profiles; release on leave; `BindToClose`
  saves and releases everyone.

### Security model

- The client never receives the cell sequence, other subjects' private
  knowledge, or anything the rules consider hidden. It cannot act out of turn
  (tokens + ownership), use what it doesn't hold (slot + expected id), target
  illegally, or bypass tutorials (engine filter).
- Every request is schema-checked (types and arity), rate-limited per player
  and per endpoint, and counted toward a decaying suspicion score.
- Remote payloads are built from plain tables with string keys or dense
  arrays only (checked by the integration test's serializer).
- Profile data is written only by server services.

---

## 3. Network contract (src/shared/Net.luau)

Remotes in `ReplicatedStorage.VarianceNet`:

| Remote | Direction | Carries |
|---|---|---|
| `Act` (RemoteEvent) | client → server | `{Kind = "Fire"/"Use", Target?, Slot?, Id?, Token}` |
| `Request` (RemoteFunction) | client → server | `(endpoint, ...)` → `(ok, result)` |
| `Match` (RemoteEvent) | server → client | `Begin, Event, Snapshot, Turn, Dialogue, Ambient, Presence, Emote, Rejected, PostMatch, Rematch, End` |
| `Push` (RemoteEvent) | server → client | `Profile, Settings, Queue, Lobby, Tutorial, Notify, Earned, Unlock, LevelUp, Broadcast, OpenScreen, Endurance, TutorialComplete, OfferTutorial, Reconnect, Debug` |
| `Look` (UnreliableRemoteEvent) | both | seated head direction (throttled) |

Endpoints (`Net.Endpoints` lists each with its argument types):
`Profile.Get · Settings.Save · Queue.Join/Leave · Solo.Start · Endurance.Start
· Sandbox.Start · Tutorial.Start/Continue/Answer/Quit · Lobby.Create/Join/
Leave/SetRules/SetReady/SetFormat/Start/Kick/AddBot/RemoveBot · Match.Sync/
Forfeit/Leave/Rematch/Emote · Spectate.List/Start/Stop · Cosmetics.Equip/Buy
· Challenges.Claim · Lore.Read · Leaderboard.Get · History.Get ·
Reconnect.Accept/Decline · Shop.Prompt · Debug.Command`.

---

## 4. Client (src/client)

`init.client.luau` loads every controller, calls `Init` in order, then `Start`.

| Controller | Role |
|---|---|
| NetworkClient | requests with timeouts, push/match subscriptions, throttled look |
| SettingsController | local settings, live `Changed`, debounced save |
| ProfileController | the client's read-only copy of its profile |
| InputController | one action map for keyboard (rebindable), gamepad and touch; look input |
| AudioController | mixer groups, pooled one-shots with fallbacks, positional sounds, ducking, room beds, generative score, heartbeat |
| UIController | layers (HUD, screens, overlay), screens, toasts, banners, subtitles |
| EnvironmentController | room lighting/atmosphere, escalation, flicker, monitors, ambient events, quality levels |
| VFXController | pooled flashes, sparks, smoke, arcs, rings, shields, tethers, cuffs, screen flashes |
| AnimationController | procedural R6 posing for seated subjects and display surrogates |
| WeaponController | the Arbiter: slides, grip and aim, recoil, bolt, cells on the rack, loading, ejection |
| CameraController | lobby, seat POV, cinematic shots, spectator orbit/seat views, shake/kick/FOV |
| MatchClient | the match store: scene, state, turn, sequence checks, resync, acting |
| MatchPresenter | turns each engine event into a staged moment within its Timeline window |
| LobbyController | terminals (proximity prompts), locker showcase, display surrogates |
| TutorialController | coach status, focus, continue/answer/quit |
| SpectatorController | live list, watching, view cycling |
| DebugController | the F8 panel for allowed players |

### Frame pipeline

- **PreSimulation** (after the engine's animation step, so these poses win):
  `WeaponController:preStep` decides what the holder's arms do →
  `AnimationController` poses every rig and solves hand frames analytically
  (`torso = root * P.Root`, `hand = torso * pivot * P.Arm * offset`) →
  `WeaponController:postStep` attaches the device to the exact hand that will
  render, then places cells in flight.
- **RenderStepped** (bound after the camera priority): the camera.
- **Heartbeat**: environment at 30 Hz, HUD re-render when dirty, table props.

### UI

`Theme` (tokens, palettes, live rebinding), `Kit` (components with hover,
press, gamepad focus, sounds, disabled-with-reason tooltips), `Icons` (frame
drawn, colour-independent silhouettes), `Window` (shared screen frame),
`RulesEditor` (generated from the rules schema). Screens are lazy-loaded
modules exposing `new(ui, controllers)`, `Open(args)`, `Close()`.

---

## 5. World building

Everything is built from primitives at runtime (no uploaded meshes): the
Intake lobby, six room dressers, the table, the Arbiter, surrogate puppets
(R6 Motor6D rigs), props. Rooms are placed far from the lobby
(`Config.Match.ArenaOrigin`, spacing 800) and use Atomic model streaming so a
client never sees half a room. Parts carry `Fx` attributes that the client
animates (key/fill lights, flicker, warnings, monitors, fans, CCTV, vents,
silhouettes); the client scans a room once on entry.

## 6. Performance

- Pooled effect parts, particle emitters that are moved and told to `Emit`,
  pooled sounds, cached room effect lists (no per-frame searches).
- Graphics quality (Auto/Low/Medium/High/Ultra) scales shadows, particles,
  bloom and effect counts; environment updates run at 30 Hz.
- StreamingEnabled with explicit stream-around requests when seating.
- The server's per-match work is event driven; surrogate reasoning is bounded
  (memoized solver, limited lookahead).

## 7. Extending

- **Instrument**: add a definition to `Core/Instruments.luau` (CanUse, Apply,
  visibility text, hold value); an icon in `UI/Icons.luau`, a prop in
  `Visual/InstrumentProps.luau`, a sound recipe in `Data/SoundLibrary.luau`,
  and its staging in `MatchPresenter.playInstrument`. The AI values it by
  simulation automatically; add a heuristic rule for Standard if needed.
- **Mode**: an entry in `Core/Modes.luau`; a queue in
  `Config.Matchmaking.Queues` if it is public.
- **Surrogate**: `Core/AI/Personalities.luau`, `Data/Surrogates.luau` (look,
  voice, idle), lines in `Data/Dialogue.luau`, a head builder in
  `World/PuppetBuilder.luau` if new.
- **Room**: palette/lighting/audio/events in `Data/Environments.luau` and a
  dresser module in `World/Environments/`.
- **Content**: cosmetics, achievements, directives and lore files are data
  tables in `src/shared/Data`; unlock sources are handled generically.

## 8. Configuration

`src/shared/Config.luau`: data (store names, schema version, autosave,
locks), network buckets and suspicion thresholds, match timings (reconnect
grace, AFK, rematch window, post-match linger, ambient intervals, rare
chances), matchmaking queues, ranked season, private lobbies, tournaments,
spectating, endurance stages, economy, monetization, debug access.

## 9. Testing

See [../tests/README.md](../tests/README.md): unit, fuzz and AI tests on the
pure core, and an end-to-end integration test that runs the real server and
real clients on a Roblox runtime mock (API-validated instances, virtual
time, serialization checks).

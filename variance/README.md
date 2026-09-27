# VARIANCE

A tense, systems-driven game of risk for Roblox (R6). Two subjects sit across
a table at **Halden Decision Sciences** with **the Arbiter**, a device loaded
with a known mix of **CHARGED** and **HOLLOW** cells in an unknown order. On
your turn you fire it at yourself or at your opponent. A HOLLOW shot at
yourself keeps your turn; a CHARGED one costs **Integrity**. **Instruments**
bend the odds. Win two of three **Trials** to pass the evaluation.

Everything is original: the setting, the device, the terminology, the
fourteen instruments, the surrogates (AI opponents with real reasoning), the
six evaluation rooms, the lobby, the story files and the progression.

- **Single player** against four surrogates on Casual / Standard / Advanced /
  Expert (genuinely different reasoning, not stat bumps), an **Adaptive**
  opponent that tracks your skill, and a secret fifth surrogate.
- **Multiplayer**: public 1v1 matchmaking, **Private Trials** with invite codes
  and Roblox friend invites (across servers), party queue, custom rules,
  surrogate seats, single-elimination **tournaments**, and **spectating** with
  a competitive delay.
- **Ranked**: transparent Elo-style Standing, seasons, five divisions with
  tiers, placements, abandon penalties and lockouts, match history, cosmetic
  rewards only.
- **Modes**: Standard, Rapid, Chaos, Precision, Crossfire (free-for-all),
  Endurance (five surrogates in a row), Custom Sandbox, Orientation and five
  advanced seminars.
- **Progression**: 100 clearance levels with titles, Marks (earned-only
  cosmetic currency), 99 cosmetics in 13 categories, 40 achievements (11
  hidden), daily and weekly directives, 22 story files, lifetime statistics.
- **Presentation**: procedural R6 animation (reach, grip, aim, recoil, flinch,
  slump, emotes, victory poses), a fully choreographed Arbiter (sliding
  delivery, bolt, cells loaded through the port, spent casings), escalating
  lighting, generative score and heartbeat, cinematic camera, six themed rooms
  with ambient events.
- **Accessible everywhere**: keyboard/mouse (rebindable), gamepad, touch;
  colour-blind palettes and shape-coded cells, high contrast, text scaling,
  reduced motion and flashing, subtitles, adjustable camera shake.

See **[docs/DESIGN.md](docs/DESIGN.md)** for the game design and
**[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** for how it is built.

## Controls

| Action | Keyboard & mouse (rebindable) | Gamepad | Touch |
|---|---|---|---|
| Fire at yourself | Q (hold) | X (hold) | FIRE AT SELF (hold) |
| Fire at opponent | E (hold) | Y (hold) | FIRE AT … (hold) |
| Use instrument | 1–8 or click | LB / RB to choose, A to use | tap |
| Cycle target (free-for-all) | Tab | D-pad left / right | arrows |
| Look around the table | right-mouse drag | right stick | drag on empty screen |
| Event log | L | D-pad down | LOG |
| Table emote | G | D-pad up | EMOTE |
| Menu (settings, forfeit) | M | Select | MENU |
| Terminals in the lobby | E at a terminal, or the menu | X | tap prompt |
| Debug panel (developers only) | F8 | | |

Firing can be set to *hold* (default), *tap* or *press twice* in Settings.

## Running it

### Open the place file

1. Build it from the repository root (needs [Rojo](https://rojo.space) 7.4+):
   `rojo build variance/default.project.json -o VARIANCE.rbxl`
2. In Roblox Studio: **File → Open from File…** and pick `VARIANCE.rbxl`.
3. Press **Play**. The workspace is empty in edit mode on purpose: the server
   builds the Intake (lobby), the six evaluation rooms and every prop when it
   starts.

The place file already has every script in place (server in
ServerScriptService, client in StarterPlayerScripts, shared modules in
ReplicatedStorage) and the service settings below. **File → Publish to
Roblox** turns it into a live experience.

### Develop with Rojo sync

The project syncs into Roblox Studio with [Rojo](https://rojo.space).

1. Install [Rokit](https://github.com/rojo-rbx/rokit) and run `rokit install`
   in the repository root (installs Rojo, StyLua and Selene).
2. Install the Rojo plugin in Studio (`rojo plugin install`, or Plugins →
   Manage Plugins).
3. Create a new **Baseplate** place in Studio.
4. From the repository root run `rojo serve variance/default.project.json`,
   then click **Connect** in the Rojo plugin.
5. Press **Play**. The server builds the Intake (lobby) and evaluation rooms on
   start; nothing needs to be placed by hand. New players are offered
   Orientation after a few seconds.

### Studio settings

- **Game Settings → Security → Enable Studio Access to API Services**: needed
  for saving (DataStores) and for private-lobby codes / reconnects across
  servers (MemoryStores). Without it the game runs normally and players get a
  clearly labelled guest session whose progress isn't saved.
- **Test → Clients and Servers** with 2–4 players to try public matchmaking,
  private lobbies, spectating and reconnects locally.
- The project file already sets StreamingEnabled, Future lighting, R6-friendly
  StarterPlayer values, `CharacterAutoLoads = false` (the server spawns
  R6 characters itself) and TextChatService chat (the in-match chat filter
  hooks its channels).
- The game is tested under Roblox's default **Deferred** signal behaviour
  (Workspace → SignalBehavior), and also works with Immediate.

### Before publishing

1. **Debug tools**: `src/shared/Config.luau` → `Config.Debug`. The panel is
   available to everyone in Studio (`AllowInStudio`) and to UserIds listed in
   `Admins` in live servers. Set `Enabled = false` to remove it entirely.
2. **Monetization (optional, cosmetic only)**: fill in the product and pass
   ids in `Config.Monetization` from the Creator Dashboard. Entries with id 0
   are hidden. Nothing for sale affects a Trial.
3. **Ranked season**: `Config.Ranked.Season` holds the season id, name and
   start/end times; bump the id and dates for a new season (Standing soft-resets
   automatically on first login in the new season).
4. **Audio (optional)**: every sound is built from sounds that ship with the
   Roblox client, so the game is fully audible with no uploads. To use your
   own sound design or licensed music, replace ids in
   `src/shared/Data/SoundLibrary.luau` (missing or moderated assets fall back
   automatically).
5. **Invites and cross-server features** (friend invites, joining a private
   lobby by code from another server, reconnecting to a match on another
   server) need a published place.
6. Leaderboard and profile DataStore names live in `Config.Data`; change them
   if you want a clean slate for a new release.

## Layout

```
variance/
  default.project.json    Rojo project
  src/shared/             ReplicatedStorage.Variance
    Core/                 pure rules engine: Engine, Probability, Instruments,
                          Modifiers, Modes, Rules, Timeline, Rating, Report,
                          TutorialDirector, AI/ (Solver, Brain, Difficulty, ...)
    Data/                 content: cosmetics, achievements, directives, lore,
                          dialogue, environments, surrogates, settings, sounds
    Visual/               primitive builders shared by server and client
                          (Arbiter, cells, instrument props, table layout)
    Util/                 Signal, Trove, Rng, Format, TableUtil
    Config.luau, Net.luau tuning and the network contract
  src/server/             ServerScriptService.VarianceServer
    Services/             28 services (data, match flow, matchmaking, lobbies,
                          ranked, progression, anti-exploit, ...)
    Match/                MatchRunner (pacing, turns, timers), Dispatcher
    World/                lobby, arenas, six environment dressers, puppets
  src/client/             StarterPlayerScripts.VarianceClient
    Controllers/          input, audio, camera, animation, the Arbiter, VFX,
                          environment, match state and presentation, lobby, ...
    UI/                   theme, component kit, icons, window, rules editor
    UI/Screens/           every screen and HUD
    Match/                table view (trays, props, integrity monitors)
  tests/                  unit, fuzz, AI and integration tests (see tests/README.md)
  tools/                  API checker, API-dump generator, luaurun source
  docs/                   DESIGN.md, ARCHITECTURE.md
```

## Checks and tests

```
# lint and format (from variance/)
selene src
stylua --check src tests

# unit, fuzz, AI and meta tests (pure core, headless)
luaurun tests/run.luau
luaurun tests/run.luau sim         # plus the AI balance simulation

# end-to-end: real server + real clients on a Roblox runtime mock
luaurun tests/integration.luau
```

`luaurun` is a tiny Luau runner (source in `tools/luaurun`, build with
`cargo build --release`). Details, and how to check the code against the
Roblox API dump, are in [tests/README.md](tests/README.md).

# VARIANCE tests

Everything here runs headless with `luaurun`, a minimal Luau runner (Luau via
mlua). Build it once:

```
cd tools/luaurun
cargo build --release
cp target/release/luaurun ~/.local/bin/   # or anywhere on PATH
```

It exposes a few globals to scripts: `__readfile`, `__writefile`, `__listdir`,
`__compile` (compile a chunk with its own environment), `__clock`, `__exit`
and `arg`.

Run everything from the `variance/` folder.

## Unit, fuzz, AI and meta tests

```
luaurun tests/run.luau          # ~60 tests, a few seconds
luaurun tests/run.luau sim      # plus the AI-vs-AI balance simulation
luaurun tests/run.luau sim 400  # more matches per pairing
```

`harness.luau` loads the pure modules in `src/shared` straight from the
source tree (emulating `require(script.Parent.X)`).

- `core.spec` rules engine: phases, turn tokens (stale and duplicate actions
  are rejected), every instrument, modifiers, sudden death, forfeits, private
  vs public event payloads.
- `fuzz.spec` hundreds of random matches across every mode, modifier and
  3–4 subject games, mixing legal, illegal and junk actions, timeouts and
  forfeits. After every step: Integrity and tray bounds, pool accounting,
  every viewer's knowledge agrees with the real sequence, the public range
  contains the true count, junk is rejected, and every match terminates.
- `ai.spec` tactical positions (e.g. never fire at yourself into a known
  CHARGED cell) and duels between tiers.
- `meta.spec` tutorials played to completion, data integrity of content
  tables, rating maths, settings validation, reports.

## Integration test (real server + real clients)

```
luaurun tests/integration.luau             # ~3 minutes, 104 checks
luaurun tests/integration.luau verbose     # also echo game prints
luaurun tests/integration.luau immediate   # Immediate signal behaviour
```

`tests/mock/` is a Roblox runtime mock that runs the actual server scripts and
the actual client scripts together:

- **Instances** are validated against the Roblox API dump
  (`mock/ApiDump.luau`): reading or writing a member the engine doesn't have
  raises the same error the engine would, and property writes are type
  checked. Parenting, events, attributes, property-changed signals, Destroy,
  Clone, part/model/attachment frames, GUI sizes, sounds, particles and tweens
  behave like the engine.
- **Virtual time**: a scheduler drives `task.*`, `os.clock`, `tick`,
  RunService frames and `workspace:GetServerTimeNow()`, so a whole evening of
  matches simulates in minutes.
- **Contexts**: the server and each client have their own module cache,
  globals, camera and `LocalPlayer`; every thread belongs to one of them.
- **Signal behaviour**: events are Deferred by default, like a new Roblox
  place (handlers run at the next resumption point, not inside the call that
  fired them); RunService frame events and `Destroying` stay immediate, as in
  the engine. `immediate` switches to the old behaviour.
- **Remotes** deliver asynchronously (one network hop) and check payloads
  against Roblox's serialization rules: functions, mixed tables and sparse
  arrays are reported, because the real engine would drop or mangle them.
- **Services**: in-memory DataStores (with injectable failures),
  OrderedDataStores, MemoryStores, TeleportService, MarketplaceService,
  SocialService, R6 character creation.

The scenario script joins players who each run the full client, and an
autopilot plays only through each client's own HUD (the same buttons and
hotkeys a player uses): orientation, every lobby screen and tab, going to
a table (the curtain, the ready handshake, everyone walking in and sitting
down, chairs pulled out and pushed back in, your own head hidden), solo,
sandbox, public PvP with a rematch, disconnect and same-server rejoin, a
cross-server reconnect offer, spectating, a private Crossfire lobby, a
tournament, the party queue, ranked, endurance, keyboard input and
rebinding, every accessibility setting, emotes and ambient events, the
locker, queue backfill, AFK timeouts, hostile payloads and rate limits, the
debug validation suite, and a shutdown save with session locks released.

It fails on any script error, any engine-API misuse, any unexpected warning,
or any remote payload the serializer would mangle.

## Seeing the game: snapshots and renders

`tests/snapshot.luau` runs a scenario on the same mock and writes what one
client would see, frame by frame, as JSON: every visible part with
joint-resolved world frames, lights, lighting, the camera, and the GUI tree.
`tools/render` draws those frames to PNG with three.js in headless Chromium
and lays the GUI out the way the engine does (UDim2 + AnchorPoint, padding,
list/grid layouts, AutomaticSize, constraints, UIScale, corners, strokes,
gradients, TextScaled, rich text). It is how the seating, the intro shots and
the HUD were checked.

```
cd tools/render && npm install && cd ../..
luaurun tests/snapshot.luau seat out/seat 0.25 7     # lobby -> table, every 0.25 s
luaurun tests/snapshot.luau turn out/turn FireSelf   # your turn, firing at yourself
luaurun tests/snapshot.luau screens out/screens      # every lobby screen
luaurun tests/snapshot.luau lobby out/lobby
node tools/render/render.mjs out/seat                # one PNG per frame
node tools/render/render.mjs out/seat --sheet seat.png --cols 4 --tile 400
node tools/render/render.mjs out/seat --no-gui --bright --camera 3011,3.4,5.3:3000,2.6,4.6:45
```

`--camera x,y,z:ax,ay,az[:fov]` renders from a free camera instead of the
client's; `--bright` adds flat light for checking shapes; `GUI_ISSUES=1`
lists text that overflows its box and frames left with Roblox's default
border. Lighting is an approximation of Future lighting, not a match for it.

## Checking against the Roblox API

`tools/check_api.py` statically checks every `Enum.X.Y`, `Instance.new`,
`GetService` and member used on locals created with `Instance.new` against the
API published in the `@rbxts/types` package:

```
npm pack @rbxts/types && tar xzf rbxts-types-*.tgz
python3 tools/check_api.py package/include/generated src
```

`tools/gen_api_dump.py package/include/generated` regenerates
`tests/mock/ApiDump.luau` (only the classes the code can touch, plus every
enum) when Roblox's API changes.

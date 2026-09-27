# VARIANCE tests

Everything here runs headless with `luaurun`, a minimal Luau runner (Luau via
mlua). Build it once:

```
cd tools/luaurun
cargo build --release
cp target/release/luaurun ~/.local/bin/   # or anywhere on PATH
```

It exposes a few globals to scripts: `__readfile`, `__listdir`, `__compile`
(compile a chunk with its own environment), `__clock`, `__exit` and `arg`.

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
luaurun tests/integration.luau           # ~3 minutes, 90 checks
luaurun tests/integration.luau verbose   # also echo game prints
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
- **Remotes** deliver asynchronously (one network hop) and check payloads
  against Roblox's serialization rules: functions, mixed tables and sparse
  arrays are reported, because the real engine would drop or mangle them.
- **Services**: in-memory DataStores (with injectable failures),
  OrderedDataStores, MemoryStores, TeleportService, MarketplaceService,
  SocialService, R6 character creation.

The scenario script joins players who each run the full client, and an
autopilot plays only through each client's own HUD (the same buttons and
hotkeys a player uses): orientation, every lobby screen and tab, solo,
sandbox, public PvP with a rematch, disconnect and same-server rejoin, a
cross-server reconnect offer, spectating, a private Crossfire lobby, a
tournament, the party queue, ranked, endurance, keyboard input and
rebinding, every accessibility setting, emotes and ambient events, the
locker, queue backfill, AFK timeouts, hostile payloads and rate limits, the
debug validation suite, and a shutdown save with session locks released.

It fails on any script error, any engine-API misuse, any unexpected warning,
or any remote payload the serializer would mangle.

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

# SKYBOUND

A momentum movement game for Roblox (R6 only): grapple-swing between floating sky islands, wall-run, slide and air-dash without touching the ground.

**Features:** smooth physics-rope grappling · sculpted terrain sky islands (meadow, blossom, ruins, alpine) with waterfalls, bridges and a beacon plaza · Future lighting · custom procedural R6 animation for every move (visible to everyone) · flips, rolls & superman dives · speed trails, dash afterimages, sparks, dust & shockwaves · wind and move sounds · style combos that pay out shards · time-trial ring courses with global leaderboards · rope/trail colour shop · saved progress · title screen · levels, titles & nametags · daily quests · ghost replays of your best trial runs · emotes · interactive tutorial · respawn where you last landed · settings menu (graphics quality, time of day, FOV, sensitivity, audio, sprint mode).

See **[docs/DESIGN.md](docs/DESIGN.md)** for the full design.

## Controls

| Action | PC | Gamepad | Mobile |
|---|---|---|---|
| Grapple (hold) | Left mouse | R2 | Hook button |
| Jump / wall-jump | Space | A | Jump |
| Fast reel-in (while grappling) | Hold Space | Hold A | |
| Sprint (hold or toggle) | Shift | L3 | Sprint button |
| Air dash | Ctrl (or Q) | X | Dash button |
| Slide (hold, at speed) | C | B | Slide button |
| Emotes: wave, dance, flex, sit | 1 2 3 4 | | |
| Skip tutorial | Enter | | |
| Menu (shop, trials, settings) | M | Select | MENU button |
| Cancel time trial | R | | |

## Running it

This project uses [Rojo](https://rojo.space) to sync code from this repo into Roblox Studio.

1. Install [Rokit](https://github.com/rojo-rbx/rokit), then run `rokit install` in this folder (installs Rojo).
2. In Studio, install the Rojo plugin (Plugins → Manage Plugins, or run `rojo plugin install`).
3. Create a new **Baseplate** place in Studio.
4. Run `rojo serve` here, then click **Connect** in the Studio Rojo plugin.
5. Press **Play**. The server generates the sky map on start (and removes the template baseplate).

For extra polish, select **Terrain** in Studio and tick **Decoration** for animated grass blades (scripts can't turn it on).

To test saving in Studio, enable **Game Settings → Security → Enable Studio Access to API Services**. Without it everything works, but progress resets each session.

To build a place file without Studio sync, run `rojo build -o skybound.rbxl`.

## Layout

```
src/
  shared/            → ReplicatedStorage.Shared
    Config.luau        every tuning number, shop items, courses, sounds (start here)
    Net.luau           all remotes
    MathUtil.luau
  client/            → StarterPlayerScripts.Client
    Movement.luau      momentum + state machine (ground/air/grapple/wallrun/slide)
    Grapple.luau       aim, hook, rope physics, rope visuals
    R6Animator.luau    procedural R6 animation for every character
    VFX.luau           trails, afterimages, dust, sparks, shockwaves
    Sounds.luau        wind, footsteps, move sounds
    CameraFX.luau      shoulder cam, FOV, roll, shake, speed lines
    HUD.luau           crosshair lock-on, speedometer, dash pips, shards
    Combo.luau         style combo meter + banking
    Trials.luau        ring detection, timer, results
    Menu.luau          title screen, shop, trials browser, settings
    Settings.luau      saved player settings
    Progress.luau      level/XP bar, level-up banner, daily quest tracker
    Tutorial.luau      first-time interactive tutorial
    Ghost.luau         best-run ghost recording + playback for trials
    Emotes.luau        emote keys (poses live in R6Animator)
    Graphics.luau      quality presets, time of day, vignette
    UI.luau            shared UI style + toasts
    WorldFX.luau       spinning shards, other players' ropes
  server/            → ServerScriptService.Server
    CharacterSpawner.luau  forces R6 spawns, respawning
    PlayerData.luau    DataStore saving
    WorldBuilder.luau  generated archipelago + lighting
    TimeTrials.luau    courses, validated timing, leaderboards
    Economy.luau       shop purchases + combo rewards
    StateRelay.luau    shares movement state/actions with other players
    Shards.luau        collectibles
    Progression.luau   XP, levels, daily quests, nametags, tutorial reward
```

## Checking the code

- `stylua src/` formats, `selene src/` lints (run `selene generate-roblox-std` once first).

## Tuning tips

- Swings feel floaty → raise `Grapple.PullAccel` or `Grapple.ReelSpeed`.
- Too easy to keep speed → raise `Movement.AirDrag` or lower `Grapple.ReleaseBoost`.
- Wall-runs too short → raise `WallRun.MaxDuration` or lower `WallRun.Gravity`.

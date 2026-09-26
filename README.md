# SKYBOUND

A momentum movement game for Roblox: grapple-swing between floating sky islands, wall-run, slide and air-dash without touching the ground.

See **[docs/DESIGN.md](docs/DESIGN.md)** for the full design.

## Controls

| Action | PC | Gamepad | Mobile |
|---|---|---|---|
| Grapple (hold) | Left mouse | R2 | Hook button |
| Jump / wall-jump | Space | A | Jump |
| Slide (hold, at speed) | Ctrl or C | B | Slide button |
| Air dash | Q or Shift | X | Dash button |

## Running it

This project uses [Rojo](https://rojo.space) to sync code from this repo into Roblox Studio.

1. Install [Rokit](https://github.com/rojo-rbx/rokit), then run `rokit install` in this folder (installs Rojo).
2. In Studio, install the Rojo plugin (Plugins → Manage Plugins, or run `rojo plugin install`).
3. Create a new **Baseplate** place in Studio.
4. Run `rojo serve` here, then click **Connect** in the Studio Rojo plugin.
5. Press **Play**. The server generates the sky map on start (and removes the template baseplate).

To build a place file without Studio sync, run `rojo build -o skybound.rbxl`.

## Layout

```
src/
  shared/          → ReplicatedStorage.Shared
    Config.luau      every tuning number (start here)
    MathUtil.luau
  client/          → StarterPlayerScripts.Client
    Movement.luau    momentum + state machine (ground/air/grapple/wallrun/slide)
    Grapple.luau     aim, hook, rope physics, rope visuals
    CameraFX.luau    shoulder cam, FOV, roll, shake, speed lines
    CharacterFX.luau procedural lean / rope hang / arm aim / slide / landing squash
    HUD.luau         crosshair lock-on, speedometer, dash pips
    WorldFX.luau     spinning shards, other players' ropes
  server/          → ServerScriptService.Server
    WorldBuilder.luau generated test archipelago + lighting
    Shards.luau      collectibles + leaderstats
    RopeRelay.luau   replicates ropes to other players
```

## Tuning tips

- Swings feel floaty → raise `Grapple.PullAccel` or `Grapple.ReelSpeed`.
- Too easy to keep speed → raise `Movement.AirDrag` or lower `Grapple.ReleaseBoost`.
- Wall-runs too short → raise `WallRun.MaxDuration` or lower `WallRun.Gravity`.

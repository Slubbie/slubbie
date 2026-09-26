# SKYBOUND — Design Doc

> A momentum movement game on floating sky islands. Grapple, swing, wall-run,
> slide, dash. **If moving around isn't fun on its own, nothing else matters.**

## Pillars

1. **Movement is the game.** Every mode (racing, collecting, combat) sits on top of the same movement kit.
2. **Easy to pick up, hard to master.** Hold click to swing. Mastery comes from release timing, chaining swings into wall-runs, slide-jumps and dash cancels.
3. **Speed you can feel.** FOV, speed lines, camera roll, body lean and rope whip all make speed readable.
4. **Momentum is earned and kept.** Air drag is tiny, and landings carry speed into your run. Skilled players never touch the ground.

## Movement kit (built in this prototype)

| Move | Input (PC / Pad / Mobile) | What it does | Skill expression |
|---|---|---|---|
| **Grapple** | Hold LMB / R2 / Hook | Fires a hook (200 studs, with aim assist). The rope only pulls when stretched, so you *swing*. Reels in slowly. | Release at the bottom of the arc for max speed. Release gives ×1.1 speed plus a pop upward. |
| **Swing pump** | WASD while attached | Pushes perpendicular to the rope | Pump to build arc height |
| **Wall-run** | Automatic when you hit a wall at 28+ speed | Runs along walls with growing gravity, max 1.8s | Chain wall ↔ wall through corridors |
| **Wall-jump** | Space / A while wall-running | Kicks off the wall and keeps your speed | 0.15s coyote time after leaving a wall |
| **Slide** | Hold Ctrl or C / B / Slide | Low-friction slide. Slopes speed you up. | Slide-jump keeps ×1.08 speed. Hold slide while landing to go straight into a slide. |
| **Air dash** | Q or Shift / X / Dash | Burst in your input direction. Also cancels a grapple. | 1 charge, refilled by landing, a wall, or attaching a grapple |
| **Bunny-hop** | Jump right as you land | Landing speed bleeds off over ~0.5s, so an instant jump keeps it | |

Every number is in `src/shared/Config.luau`.

## Core loop

```
Spawn island → launch pad → swing between islands → collect shards
     ↑                                                    ↓
  new cosmetics / unlocks  ←  spend shards  ←  bank shards / beat times
```

## Game modes (roadmap)

1. **Free roam + shards** (prototype) — explore the archipelago and collect shards.
2. **Time trials** — ring courses with ghosts of your best run and global leaderboards. Cheap to build, and the best showcase for skill.
3. **Sky Delivery** — carry a package between islands against the clock. Dropping it on a hard landing fails the run. Makes you think about route and speed.
4. **Sky Tag / Hunt** — one team hunts with harpoons that can reel in *players*, and everyone else runs. The social hook.
5. **Storm Run (roguelite)** — islands collapse behind you and a storm chases you. Survive as long as you can and pick upgrades between zones.

## Progression and monetization (without ruining the game)

- **Never sell speed.** Every stat that affects movement is identical for all players.
- Sell **style**: rope colors and trails, hook skins, landing effects, wall-run sparks, speed-line colors, emotes.
- **Shards** unlock cosmetics too, so free players get the same kind of goals.
- Game pass ideas: private servers, extra ghost slots for trials, a cosmetic "creator" hook.

## Visual direction

- Stylized pastel islands, bright neon grapple anchors, golden hour lighting, a sea of clouds below.
- Anything you can grapple should *look* grappleable (cyan glow). The crosshair locks on and shows the distance.

## Technical notes

- Movement runs on the **client** (the player owns their character's physics). We set `AssemblyLinearVelocity` every Heartbeat.
- Air momentum: above walk speed, we take over horizontal air velocity so the Humanoid's air control can't eat momentum. A sudden large speed loss counts as a collision and is accepted.
- Procedural animation edits `Motor6D.C0` (root lean, arm aim) after the Animator runs. This is local-only for now. **TODO:** replicate the poses through a compact remote, or switch to authored animations with blended weights.
- Ropes are drawn locally and relayed through `RopeRelay` so other players see them.
- **Anti-cheat TODO:** server-side speed and teleport sanity checks, and validate shard pickups by distance and time.

## Next up

- [ ] Sounds: rope fire/attach, wind that rises with speed, landing thuds, shard chime
- [ ] Authored animations: wall-run cycle, slide pose, swing pose (replace procedural poses where better)
- [ ] Rope trail particles and wall-run sparks
- [ ] Time trial mode with ring checkpoints plus DataStore best times
- [ ] Mobile tuning pass (aim assist radius, button layout)
- [ ] Hand-built showcase map (put it in `Workspace.Map` to skip generation)

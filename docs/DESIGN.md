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

## Built so far

- **R6 only**: the server spawns every player as R6 (keeping their avatar look).
- **Procedural animation** (no uploaded animations needed): idle breathing, a run cycle that scales with speed, a ninja run above 45 speed, jump tuck, a flailing fall, a superman dive at high speed, a rope hang with the arm aimed at the hook, a wall-run cycle with the hand skimming the wall, a slide pose, a landing crouch, cartwheels off walls, front flips off launch pads and slide jumps, backflips on slingshots, and forward rolls on hard landings. Everyone sees everyone's animations.
- **VFX**: speed trails in your rope colour, dash afterimages, wall-run sparks, slide dust, landing dust and shockwaves, grapple impact flashes, and shard pickup bursts.
- **Sound**: wind that rises with speed, wall-run footsteps, and a sound for every move.
- **Style combos**: chain moves without settling on the ground (bunny hops keep it alive). Stand still for 0.4s and it banks into shards.
- **Time trials**: three generated ring courses (Warm-Up, Sky Loop, Summit Rush). Timing is validated by the server, best times are saved, and global leaderboards show in the menu and on a board at spawn.
- **Shop**: 7 rope/trail colours, including an animated rainbow. Cosmetic only.
- **Saving**: shards, owned colours, and best times.
- **Title screen**: orbiting camera, PLAY / TIME TRIALS / SHOP.

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
- Animation: `R6Animator` sets every R6 `Motor6D.Transform` each frame from a pose built in torso space. Each client animates *all* characters itself, using their replicated velocity plus the `MoveState` / `WallNormal` / `GrapplePoint` attributes and `MoveAction` events that `StateRelay` relays. That's zero animation assets, and everyone sees the same moves.
- Ropes: your own is drawn instantly by `Grapple`, other players' ropes come from the `GrapplePoint` attribute.
- Time trials: the client reports rings and the server checks your distance to each ring and a minimum travel time between rings.
- **Anti-cheat TODO:** server-side speed and teleport sanity checks. Combo payouts are capped by elapsed time.

## Next up

- [ ] Custom uploaded sounds (swap the IDs in `Config.Sounds`)
- [ ] Ghost replays of your best trial run
- [ ] More cosmetics: hook skins, landing effects, emotes
- [ ] Sky Delivery and Sky Tag modes
- [ ] Mobile tuning pass (aim assist radius, button layout)
- [ ] Hand-built showcase map (put it in `Workspace.Map` to skip generation)
- [ ] Server-side movement sanity checks (anti-cheat)

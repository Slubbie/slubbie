# Skyline Legends

A Roblox parkour game about mastering movement, finding clever routes and
earning a name as one of the greatest runners in Meridian, a vertical city
broken into islands of rooftops after its skyways failed.

You join the **Runners' Guild** as a newcomer in the Guildhall Training Yard,
learn to move, and then carry the Guild's work out across six districts:
restoring relays, delivering supplies, reaching abandoned infrastructure and
finding out what happened to the settlements at the top of the city.

**Start here:** download [`build/SkylineLegends.rbxlx`](build/SkylineLegends.rbxlx)
and open it in Roblox Studio (**File → Open from File…**), then press **Play**.
The server generates the whole city when it starts; nothing needs to be
uploaded.

See **[docs/DESIGN.md](docs/DESIGN.md)** for how every system works.

## What's in it

- **Movement** with responsive acceleration and readable momentum: sprint,
  crouch, slide, vault, ledge grab, mantle, climb, wall run, wall jump and wall
  kick, double jump, directional dash, grapple swing and pull, rope swing,
  zipline, balance beams, landing rolls and ledge leaps. Jump buffering, coyote
  time, limited air control, stamina for sprinting and powerful moves, and
  forgiving recovery (ledge catches, emergency wall kicks, recovery platforms,
  safe landings, instant checkpoint retries).
- **A city to explore:** the Guildhall Commons hub and six districts
  (Tinroof Terraces, Ironworks Quarter, Verdant Hollow, Gilded Exchange,
  Frostreach and the Aether Citadel), each with a social plaza, exploration
  routes, landmarks, lost letters, supply caches and secrets.
- **81 courses and challenge rooms** with accessible, fast and expert routes,
  shortcuts and mechanisms (moving platforms, collapsing walkways, retracting
  bridges, spinners, timed doors, pressure plates, bounce pads, launch vents,
  swinging cargo, rising water, lasers, wind, ice, low gravity, holograms), plus
  co-op relays, the **25-floor Spire** challenge tower and the endless
  **Dreamline**.
- **Progression:** 100 levels with named ranks, 16 abilities, a 28-node skill
  tree across four branches, 8 mastery categories with proficiency
  challenges, 61 quests (a seven-chapter story, side quests and expert
  trials), daily objectives, weekly expeditions, district contracts, medals
  from bronze to platinum and four distinctions per course, 62 achievements
  and 113 cosmetics.
- **Competition:** ghosts, live splits, ranked time trials on standardized
  movement, global and friends leaderboards, multiplayer races and co-op relays.
- **Social:** crews with a shared weekly goal, a player list, invites to run
  together or join a race, emotes and victory animations.
- **Presentation:** procedural animation for every move, a parkour camera,
  per-district lighting, weather and time of day, material footsteps, adaptive
  generative music and readable effects.
- **Access:** keyboard and mouse, gamepad and touch, full remapping,
  per-device sensitivity, reduced motion, text and HUD size, high-contrast
  markers, input hints, and states shown by text or shape as well as colour.

## Controls

| Action | Keyboard & mouse | Gamepad | Touch |
|---|---|---|---|
| Move / look | WASD / hold right mouse (or lock mouse in Settings) | Left / right stick | Stick / drag right side |
| Jump, wall jump, climb up | Space | A | JUMP |
| Sprint | Left Shift | L3 or L2 | RUN (toggle) |
| Crouch, slide, roll, let go | C or Left Ctrl | B | SLIDE |
| Dash | Q | X | DASH |
| Grapple | F or left mouse | R2 | HOOK |
| Retry checkpoint (hold: restart) | R | D-pad down | ↻ |
| Practice checkpoint | V | L1 | |
| Interact (talk, boards, signs) | E | Y | tap the prompt |
| Menu / Map / Journal | M / Tab / J | D-pad up / D-pad right | ☰ |
| Emotes | G, then 1-8 | D-pad left | |
| Cycle pinned objective | T | R3 | |

Every binding can be changed in **Settings → Controls**.

## Working on it

The project is a [Rojo](https://rojo.space) project.

1. Install [Rokit](https://github.com/rojo-rbx/rokit) and run `rokit install` in
   this folder (installs Rojo, StyLua and Selene).
2. Install the Rojo plugin in Studio, open the place, run `rojo serve` here and
   click **Connect**.
3. To rebuild the place file: `rojo build -o build/SkylineLegends.rbxlx`.

To test saving in Studio, turn on **Game Settings → Security → Enable Studio
Access to API Services**. Without it everything still works, but progress,
leaderboards, ghosts and crews last for the session only (the game says so).

### Tests

`tools/headless` runs the game's real code outside Roblox against a small mock
of the engine, using the standalone [Luau](https://github.com/luau-lang/luau)
CLI:

```
python3 tools/headless/run.py <path-to-luau> tools/headless/test_world.luau    # builds and validates the whole city
python3 tools/headless/run.py <path-to-luau> tools/headless/test_courses.luau  # every course recipe builds and is reachable
python3 tools/headless/run.py <path-to-luau> tools/headless/test_server.luau   # boots the server, plays through the main loops
python3 tools/headless/run.py <path-to-luau> tools/headless/test_client.luau   # boots the client, runs frames, opens every screen
```

## Layout

```
src/shared   ReplicatedStorage.Shared   configuration (data for every system), shared logic, networking
src/server   ServerScriptService.Server world generation, data, services (courses, quests, modes...)
src/client   StarterPlayerScripts.Client movement, animation, camera, audio, effects, gameplay, interface
tools        headless test harness
build        the ready-to-open Studio place
```

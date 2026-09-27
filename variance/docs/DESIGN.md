# VARIANCE — Design

> *Halden Decision Sciences thanks you for your participation. Please remain
> seated. The Arbiter will be delivered to you when it is your turn.*

VARIANCE is a turn-based game of calculated risk. Its tension comes from three
things working together: **public information** (everyone knows how many
cells are CHARGED), **private information** (what you alone have learned),
and **tempo** (a HOLLOW shot at yourself keeps the device in your hands).
Every system in the game is built to make those three legible, fair and
dramatic.

---

## 1. The world

**Halden Decision Sciences** was founded in 1968 to study how people decide
when a choice has a real cost. Its instrument, **the Arbiter**, delivers
calibrated discharges; its subjects are paid volunteers ("candidates")
recruited from the desperate. Federal money ended after a 1979 inquiry;
anonymous **Observers** kept it running, watching Trials over a closed
channel and wagering on them. In 1996 the last staff installed **PROCTOR**, a
decision model trained on every Trial ever run. There have been no human
employees since. The Proctor builds **surrogates** from former subjects to
test new candidates, looking for the one part of human choice it still cannot
predict: *the residual*.

The story is told in fragments: 22 archive files (unlocked by play, never by
purchase, some personalised with your own record), PA announcements in the
Intake, monitor text in the rooms, surrogate dialogue, and rare events during
Trials (*THE PROCTOR IS WATCHING THIS TRIAL*).

### Vocabulary

| Term | Meaning |
|---|---|
| Arbiter | the device |
| Cell | a round: **CHARGED** (◆, filled diamond) or **HOLLOW** (○, open ring) |
| Load | one filling of the Arbiter; its mix is announced, its order is not |
| Trial | a round of the match; lose all Integrity and you lose the Trial |
| Integrity | health |
| Instrument | an item |
| Surge | the last cell of a Load deals +1 damage (final Trial) |
| Surrogate | an AI opponent |
| Standing | ranked rating; divisions Probationer → Analyst → Strategist → Arbiter → Oracle |
| Clearance | account level (1–100) with titles from CANDIDATE to VARIANCE |
| Marks | cosmetic currency, earned by playing |
| Directives | daily and weekly challenges |
| The Intake | the lobby |

---

## 2. Core rules

A match is **best of three Trials** (configurable). Each Trial:

1. Both subjects are set to the Trial's Integrity (Standard: **2 / 4 / 5**).
2. A **Load** is prepared: its size and CHARGED/HOLLOW mix are announced
   (at least one of each), then the cells are sealed in random order.
3. Each subject is dealt instruments (Standard: **0 / 2 / 3** per Load), up to
   their tray capacity; extras are lost.
4. Turns alternate. On your turn you may use any number of instruments, then
   you **fire**: at yourself or at an opponent.
   - A **HOLLOW** cell fired at yourself **keeps your turn**.
   - Any other shot passes the turn.
   - A **CHARGED** cell deals 1 damage (×2 with Capacitor, +1 on a Surge cell).
5. When the Load is empty a new one is prepared; the starting subject rotates.
6. The Trial ends when only one side has Integrity left.

**Escalation (Standard):**

| Trial | Integrity | Cells per Load | Instruments per Load | Rare instruments | Surge |
|---|---|---|---|---|---|
| I | 2 | 2–4 | 0 | no | no |
| II | 4 | 3–6 | 2 | no | no |
| III | 5 | 4–8 | 3 | yes | yes |

**Sudden death**: if a Tether makes every remaining subject collapse at once,
they return at 1 Integrity with no instruments and play a fresh Load.

**Turn timer** (public modes): when it expires the Arbiter fires at the
undecided subject. Two consecutive timeouts in a live PvP Trial forfeit it.

### Probability, shown honestly

The HUD shows exactly what *you* know: the spent cells, every remaining
position (known type, unknown, or "±" for an unknown cell whose polarity was
inverted), the exact remaining counts (or a range when inversions blur them),
and the chance the loaded cell is CHARGED given everything you have learned.
The same numbers drive the surrogates, the tutorial and the post-match
report's *key moments* ("fired at themselves at 67% odds and walked away").

Cells are never identified by colour alone: CHARGED is a filled diamond with
two bright bands and a pointed tip; HOLLOW is an open ring with one matte band
and a dark open end.

---

## 3. Instruments

Fourteen instruments in three rarities (Common 55%, Uncommon 33%, Rare 12% of
draws; Rare only in later Trials unless rules say otherwise). Every tooltip
states what the opponent learns.

| Instrument | Rarity | Effect | What others see |
|---|---|---|---|
| **Lens** | Common | Privately see the loaded cell. | that you used it, not what you saw |
| **Ejector** | Common | Throw the loaded cell out unfired; your turn continues. | the ejected cell |
| **Suture** | Common | Restore 1 Integrity. | public |
| **Capacitor** | Common | Your next CHARGED shot deals double damage. | the coils glow |
| **Clamp** | Uncommon | Your opponent loses their next turn (then is immune once). | public |
| **Inverter** | Uncommon | Flip the loaded cell's polarity. | that it was inverted, not its new type |
| **Sonar** | Uncommon | Privately learn one random later cell. | that you used it |
| **Dampener** | Uncommon | Absorb 1 damage from the next hit this Load. | the field |
| **Rotor** | Uncommon | Rotate the next three cells (knowledge moves with them). | public |
| **Overclock** | Rare | Your next shot doesn't end your turn. | public |
| **Unstable Serum** | Rare | 60%: +2 Integrity. 40%: −1 (can take your last point). | public, with the result |
| **Power Tap** | Rare | Pay 1 Integrity, draw 2 instruments. | public, with the draws |
| **Tether** | Rare | Until the Load ends, damage to anyone hits everyone. | the link |
| **Scrambler** | Rare | Re-cast the remaining cells at random; knowledge wiped. | the new counts |

Designed interactions: Lens → Capacitor (certain double), Inverter → self-shot
(turn a known CHARGED into a free turn), Sonar → Rotor (bring a known cell
forward), Ejector chains, Surge + Capacitor, Tether + Power Tap. The
statistics system records these combos for achievements and directives.

## 4. Modifiers

Experimental rules, rolled per Trial in Chaos or chosen by a host (up to four):

| Modifier | Effect |
|---|---|
| Volatile Cells | CHARGED cells deal +1 damage |
| Blind Load | only the total is announced, not the mix |
| Scarcity / Surplus | half the draws / +2 draws and +2 capacity |
| Mirror Draw | everyone is dealt the same instruments |
| Heavy / Light Loads | Loads skew CHARGED / HOLLOW |
| Surge | every Load's last cell deals +1, every Trial |
| Short Fuse | turn timers halved |
| Glass | maximum Integrity −1 every Trial |
| Echo | survive a shot at yourself and privately learn the next cell |
| Lockdown | tempo instruments (Clamp, Overclock) removed |

## 5. Modes

| Mode | Summary |
|---|---|
| Standard | the full evaluation, best of three, 1v1 |
| Ranked | Standard rules, locked; moves your Standing |
| Surrogate Trial | Standard against a surrogate of your choice and difficulty |
| Rapid | short timers, smaller Loads, four-slot trays, faster pacing |
| Chaos | two random modifiers per Trial, generous rarities, eight-slot trays |
| Precision | at every Load you privately learn one random cell; scarce draws |
| Crossfire | 3–4 subject free-for-all; choose any target |
| Endurance | five surrogates in a row (Ledger → Volta → Magpie → Kismet → the Proctor); Integrity and instruments carry over with a small recovery |
| Custom Sandbox | every rule adjustable, against surrogates; reduced XP, no directives |
| Private Trials | any rules, friends and surrogates, single match or tournament |
| Tournament | single-elimination bracket for 3–8 entrants; surrogate-vs-surrogate pairings resolve instantly; spectators on a delay |
| Orientation + 5 seminars | interactive lessons on the real engine |

The engine already supports **teams** (subjects share a TeamId, teammates
can't be targeted, a Trial ends when one team remains), so 2v2 is a mode
entry and a queue definition away.

---

## 6. Surrogates (AI)

Surrogates play by **reasoning**, not by cheating: they see exactly what a
player in their seat would see (the public counts plus their own private
knowledge).

### How they think

- An exact **win-probability solver** over (cells left, charged left,
  Integrity of both, whose turn, Surge, Tether) values every shot.
- A **utility brain** scores each legal action as the change in win
  probability it produces: firing (with turn retention, lethal lines and
  Integrity disparity), and each instrument by simulating its outcome
  (value of information for Lens and Sonar, the chance an Inverter turns a
  self-shot into a free turn, etc.) minus the value of keeping it for later.
- **Personalities** bias the margins: aggression, caution, appetite for
  variance, love of information, conservation, and per-instrument affinity.
- **Opponent modelling**: surrogates record how often you shoot yourself at
  given odds, how long you hesitate, and which instruments you use in what
  order; Expert blends that into its predictions and infers your hidden
  knowledge (a Lens followed by a self-shot means the loaded cell was HOLLOW).

### Difficulty tiers

| Tier | Reasoning |
|---|---|
| Casual | "gut" play: a noisy read of the odds, random instrument use, forgets observations, occasional blunders |
| Standard | reads the odds correctly and follows sensible rules of thumb, but never looks ahead |
| Advanced | full conditional probability, exact win-probability evaluation, value of information, conserves instruments |
| Expert | all of that plus two-step instrument sequencing, a model of *you*, and inference from your instrument patterns; still slightly noisy so it feels human |
| Adaptive | interpolates Standard → Expert from a skill estimate the server keeps per player, and shifts between Trials |

Measured over thousands of simulated matches: Standard beats Casual ~70%,
Advanced beats Standard ~80%, Expert beats Standard ~86% and Casual ~94%.

### The cast

| Surrogate | Epithet | Style |
|---|---|---|
| LEDGER | The Actuary | conservative; pure expected value |
| VOLTA | The Live Wire | aggressive; damage and tempo; loves a primed Capacitor |
| MAGPIE | The Archivist | information-hungry; hoards tools; strikes on certainty |
| KISMET | The Gambler | reckless; seeks variance and anything unstable |
| THE PROCTOR | The Administrator | secret: unlocked by beating all four on Expert; models your habits during the match |

Each has a distinct rig (monitor head, coil, beak, die, aperture), idle
style, voice (pitched blips under subtitles) and dialogue for dozens of
situations (your risky survival, their own near miss, match point, your
hesitation, the Proctor's reads of your habits).

---

## 7. The Arbiter on screen

Every action is staged, and every beat fits the server's timing contract so
all clients see the same moment at the same time:

- **Load**: the announced cells rise onto the rack (types visible, sorted so
  the order stays secret), a shutter blanks them, and they are fed one by one
  through the port; the bolt chambers the first.
- **Turn**: the device slides across the table to the subject whose turn it
  is, wearing that subject's cosmetic finish.
- **Fire**: the subject reaches, grabs the device by its body and swings it
  into a grip; aimed at an opponent it is held out at the target's head;
  aimed at yourself it is turned around and held by the barrel under the chin,
  the other hand gripping the armrest. The hold before the outcome lengthens
  with the moment's tension while music and ambience duck to near silence.
- **Outcome**: CHARGED is a muzzle flash, plasma cone, sparks, arcs across the
  target's body, a light dip, camera kick and screen flash (for the target);
  HOLLOW is a dry click and a puff of pale vapour, followed by relief. The bolt
  cycles and the spent casing lands in the tray showing its type.
- **Instruments** are real props: picked out of the tray, carried to where they
  act (the chamber window for a Lens, the chest for a Suture, the opponent's
  wrists for a Clamp) and dissolved when spent.
- **Escalation**: lights, fog, flicker, fans and monitors intensify with the
  Trial number, match point and low Integrity; the generative score gains a
  pulse and an arpeggio; a heartbeat follows your own Integrity. Sudden death
  turns everything red.

## 8. The Intake (lobby)

A walkable institutional hall, every terminal also reachable from the menu:
evaluation kiosks (queue), the surrogate gallery (glass cases with each
surrogate standing inside; challenge them from the plaque; the secret case
stays dark), live leaderboards and a *live trials* board (spectate from it),
the Locker booth with your Arbiter finish turning under a spotlight, practice
tables (sandbox), the Orientation door, the Archive, Directives and Records
terminals, PA announcements, and a sealed door to Sublevel 7.

## 9. Evaluation rooms

| Room | Mood |
|---|---|
| Test Chamber 04 | sealed industrial chamber, blast door, hazard paint, one caged lamp |
| Studio 9 | abandoned broadcast studio, trusses, dead cameras, empty seats |
| Sublevel C | underground research floor, server racks, specimen tanks, cold blue light |
| Customs 77-C | interrogation room in a freight terminal, one bulb, two-way mirror, rain |
| The Gilded Room | decaying casino backroom, velvet, failing chandelier |
| Evaluation Suite | sterile corporate chamber, frosted glass, silhouettes, a wall of metrics |

Each has its own palette, lighting, audio bed, escalation targets and ambient
events (power dips, cameras turning to watch the subject in danger, vents,
silhouettes shifting behind glass, warnings, PA lines, and rare events).

---

## 10. Progression

- **XP** from every Trial (by outcome, reads, survivals, damage, instruments,
  clutch play), scaled by mode and surrogate difficulty. **100 clearance
  levels**; titles every few levels; cosmetics and Marks at milestones.
- **Marks**: earned only by playing (Trials, directives, achievements, level
  rewards). They buy cosmetics. Nothing purchasable affects a Trial.
- **Cosmetics** (99 across 13 categories): Arbiter finishes, discharge
  effects, table themes, gloves, headwear, victory poses, table emotes,
  versus-card frames, banners, badges, titles, sound packs, lobby nameplates.
  Sources: default, levels, achievements, ranked peaks, seasons, directives,
  tournaments, lore, the Mark shop, optional cosmetic purchases.
- **Achievements** (40, 11 hidden): milestones, skill feats (survive a
  self-shot at high odds, perfect tracking, lethal long shots), combos,
  surrogates beaten on each tier, lore, the Proctor.
- **Directives**: three daily (easy / medium / hard) and a weekly set, chosen
  deterministically per player per period, always achievable in normal play.
- **Statistics**: lifetime counts, win rates by opponent tier and room,
  favourite instruments, boldest self-shot, recent match history.

## 11. Ranked

- Elo-style **Standing** starting at 1000: after each Trial, Standing moves by
  K × (result − expected), expected from the rating gap. K is 48 for the
  first five (placement) Trials, 32 until 30 Trials, then 24. Every win gains
  at least 1; every loss costs at least 1.
- **Divisions**: Probationer (0), Analyst (900), Strategist (1100),
  Arbiter (1300), Oracle (1500), each with tiers III → I.
- **Seasons** with a soft reset halfway to 1000; peak division earns its
  season cosmetic.
- **Integrity of the ladder**: leaving an active ranked Trial counts as a
  loss, adds an abandon strike and locks the queue (5 min, 15 min, 1 h, 4 h);
  clean Trials clear strikes; reconnecting in time refunds the penalty. The
  same opponent can only move your Standing a few times a day. Very short
  forfeited Trials don't reward the winner. Matchmaking widens its rating
  window the longer you wait.
- The whole formula is explained on the Standing terminal, and every change is
  shown before (versus card: win +x / loss −y) and after the Trial.

## 12. Multiplayer

- Public queues per mode; a surrogate takes an empty seat after a wait
  (never in ranked).
- **Private Trials**: invite codes (six characters, no look-alike letters)
  that work across servers, Roblox friend invites carrying the code, a host
  who sets every rule through the same schema the server enforces,
  surrogate seats, ready checks, host migration, party queue into Crossfire,
  and tournaments with a live bracket.
- **Reconnects**: a disconnected subject's seat is held (turn timer paused);
  rejoining the same server reseats them automatically; joining another
  server offers a teleport back to the exact server instance.
- **Rematch**: everyone at the table must accept within the window; seats swap
  so the other subject starts.
- **Spectating**: public information only; ranked and tournament Trials are
  delayed so nothing useful can be relayed, and in those Trials spectator
  chat never reaches the players.

## 13. Tutorials

**Orientation** is a real match against PROXY, a training unit, with forced
Loads, forced draws and an action filter, so everything taught behaves
exactly as in a live Trial. It covers the Arbiter, counts vs order,
Integrity, turn retention, odds, the first instruments, a quiz, and a free
final Trial. Five **seminars** go deeper: conditional probability,
information advantage, turn economy, instrument sequencing and common
mistakes. The coach panel highlights the relevant HUD element and pulls the
camera to what each beat is about.

## 14. Accessibility and platforms

- Controls for keyboard/mouse (rebindable), gamepad and touch share one
  action map; hold / tap / press-twice firing.
- Cell palettes for deuteranopia, protanopia, tritanopia and monochrome, on top
  of shape-coded cells; high-contrast interface; text scale; interface scale.
- Reduced motion and reduced flashing; camera shake slider; cinematic camera
  full / reduced / minimal.
- Subtitles for all dialogue and announcements; dialogue full / brief / off.
- Disabled controls always explain why (tooltip), and every instrument states
  what it reveals.

## 15. Monetization

Cosmetic only: an optional bundle (an Arbiter finish and banner), a supporter
pass (a nameplate) and Marks packs, all configurable and hidden until ids are
set. Nothing sold changes odds, instruments, Integrity, XP or matchmaking, and
the large majority of cosmetics can only be earned by playing.

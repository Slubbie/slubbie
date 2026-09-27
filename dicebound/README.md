# Dicebound: Roll & Riches

A Roblox treasure-collecting game: roll dice, reveal treasure, fill your bag, sell at the merchant, buy upgrades, and work toward new regions.

**Status: Stages 1–3 built.**

- **Five themed floating islands:** Meadow Market, Crystal Caverns, Frostfall Village, Emberforge and Astral Sanctuary. Each has its own lighting mood, merchant, second stall and travel portal.
- **50 treasures** with mutations.
- **Seven dice**, each with its own faces, perk and tradeoff, plus up to 3 dice slots with Pair / Triple / Straight / Jackpot combos.
- **Your bag:** sort, filter, lock and select items, then sell them.
- **Upgrades and auto-roll.**
- **Travel map** with region unlocks.
- **Collection book** with silhouettes and completion rewards.
- **Merchant orders.**
- **Crafting:** the Celestial Die, 5 auras (visible to everyone) and 3 tray skins.
- **Daily objectives** and **20 milestones.**
- **World events,** with a live countdown.
- **Notification badges.**
- **Polish:** coin, confetti and shake effects.
- **Tutorial and settings,** including reduced motion.
- **DataStore saving:** save format v2 with a migration, plus session locking.

See **[docs/DESIGN.md](docs/DESIGN.md)** for the design, probability model, balance table and save strategy.

## Open it in Roblox Studio (easiest)

1. Download **`Dicebound.rbxl`** from this folder.
2. Double-click it, or in Studio use **File → Open from File…** and pick it.
3. Press **Play** (F5). The server builds Meadow Market from parts when it starts.

To keep your changes, use **File → Publish to Roblox** (or Save to File).

### Turning on saving

Saving uses DataStores, which only work in a place that is **published to Roblox**:

1. **File → Publish to Roblox** (create a new experience).
2. **Home → Game Settings → Security →** turn on **Enable Studio Access to API Services**.
3. Press Play. Progress now saves every 90 seconds, when you leave, and when the server shuts down.

Without step 2, the game still runs, but a red banner says **"Studio test: saving is off"** and progress resets each session. That is deliberate: it never pretends to save.

## Or sync the source with Rojo

The source lives in `src/` and is the real project; `Dicebound.rbxl` is built from it. To develop with Rojo: install [Rokit](https://github.com/rojo-rbx/rokit), run `rokit install` in the repo root, then `rojo serve dicebound/default.project.json` and connect the Studio Rojo plugin. Rebuild the place file with `rojo build dicebound/default.project.json -o dicebound/Dicebound.rbxl`.

## Explorer layout

```
ReplicatedStorage
  Dicebound (Folder)                shared, read by server and client
    Config (ModuleScript)             all tuning, edit these to change the game
      Game, Items, Dice, Regions, Economy, Rarities, Sounds, Crafting
    LootMath, Odds, Net, Format, Signal (ModuleScripts)
ServerScriptService
  Dicebound (Script)                  server entry point
    Core (Folder)                     pure game rules (unit-tested)
      Schema, Bag, Shop, RollEngine, Tutorial, Orders, Workshop, Progress
    Services (Folder)                 Roblox-facing systems
      PlayerData, Requests, StateSync, RegionService, ActionState, RateLimiter,
      EventService, AuraService
    World (Folder)
      Builder, Props, WorldBuilder    builds all five islands from parts
StarterPlayer > StarterPlayerScripts
  Dicebound (LocalScript)             client entry point
    ClientState, Sound (ModuleScripts)
    Controllers > RollController, Atmosphere
    UI > Theme, Kit, Hud, DiceTray, Reveal, ItemIcon, Effects, Guide, Panels, Toasts, Confirm,
         InventoryPanel, UpgradesPanel, DicePanel, MapPanel, BookPanel, QuestsPanel,
         CraftPanel, OddsPanel, SettingsPanel
```

To rename the game, edit `Config > Game > Name`. Item values, loot weights, upgrade prices and dice live in the other Config modules.

## Controls

| Action | PC | Gamepad | Mobile |
|---|---|---|---|
| Roll | R, or the ROLL button | X | ROLL button |
| Bag / Upgrades / Dice | B / U / G | | Right-side menu |
| Map / Quests / Collection | M / Q / C | | Right-side menu |
| Talk to a stall or portal | E | | Tap the prompt |
| Close a panel | Esc | | ✕ |

## What you should see

- You spawn on a wooden pad in a sunny floating meadow, with a stone plaza, a big die on a pedestal, a striped **Merchant** stall (east) and an **Upgrades** stall (west), plus a sealed crystal gate to the north.
- Top-left: coins, bag (0 / 20 items) and a **Tutorial 1/3** goal card with a Skip button. Bottom-centre: a dice tray and a big green **ROLL** button.
- Press ROLL: the die jiggles, tumbles into the tray, lands with a number badge, and a card pops up with the item, rarity (stars + name, not just colour), mutation and value. Legendary+ finds get a short full-screen reveal you can tap to skip.
- The tutorial then draws a golden trail to Marta's stall. Press **E** at the counter to open your bag, select items and sell. Then it points you to Upgrades.
- A 3×3 menu on the right shows red number badges when something is ready: rewards to claim, a region you can unlock, a die you can afford.
- About every 10 minutes a **world event** banner appears (for example "👑 Golden Hour · Golden mutations are 4× as likely · 3m 12s left (in Crystal Caverns)").
- The **portal** at the north end of each island (or 🗺️ Map) unlocks regions and teleports you. Each region re-tints the lighting: purple cave glow, cold aurora dusk, smoky orange forge light, starry night.

## Testing checklist

| Scenario | How to check |
|---|---|
| New player flow | Fresh save: roll → follow trail → sell → buy Treasure Bag II. The tutorial finishes and gives +25 coins. |
| Full bag | Roll 20 times without selling. The ROLL button turns red ("BAG FULL") and the server refuses the roll. Nothing is lost. |
| Locked items | Lock a stack (🔓 → 🔒), then Sell All. The locked stack stays. |
| Legendary+ warning | Select a Legendary item and Sell Selected: a confirmation appears. Sell All offers "Sell all except these". |
| Insufficient funds | Upgrade buttons are grey with "Need 🪙 X more". |
| Duplicate requests | Double-click a buy button: only one level is bought (the server checks the level you saw). |
| Selling away from a stall | Open the bag in the plaza: sell buttons are disabled with a hint. |
| Leave and rejoin | In a published place with API access: earn coins, leave, rejoin. Coins, bag, locks and upgrades persist. |
| Two players | Studio **Test → Clients and Servers → 2 players**: each has their own coins and bag. The other player sees a toast for your Legendary finds. |
| Mobile | Studio **Device Emulator** (phone, landscape): HUD scales, buttons stay clear of the thumbstick and jump button. |
| Missing assets | Clear an id in `Config > Sounds`: that sound is skipped silently, with no errors. |
| Reduced motion | Settings → Reduced motion: dice appear already landed, no bursts or shaking. |
| Region unlock + travel | Earn 2,500 coins and 6 Meadow finds → Map → Unlock Crystal Caverns → Travel. You arrive on the cave island and rolls use its loot. |
| Dice + combos | Buy the Dice Tray upgrade and the Copper Die, equip both (Dice panel). Rolling two dice shows "Pair!" and gives ×2 sometimes. The bag must have 2 free slots to roll. |
| Orders | Quests → Orders shows 3 requests. Collect the items, go to a merchant, Deliver. Locked items are never used. Skip has a 3-minute cooldown. |
| Crafting | Collect 10 Lucky Acorns, 10 Old Copper Coins and 3 Teacup Snails → Craft → Petal Drift Aura. The aura appears on your character (another player can see it). |
| Dailies / milestones | Quests → Daily / Milestones. Claim buttons light up when done, and claiming twice is refused. |
| World events | Wait about 90 s after the server starts: a banner and toast announce the first event. The Odds panel shows an extra "with event" column while you're in that region. |

## What was tested, and what wasn't

**Tested here (outside Roblox):**
- 35 automated tests (`tests/`) run the real roll engine, bag, selling, upgrade, dice, region, order, crafting, daily, milestone, event, save-schema and tutorial code under Luau. They cover:
  - odds matching the documented tables (200,000 simulated rolls) and event odds matching simulation;
  - combo rules, and bag space reserved before each roll;
  - lock enforcement for selling, orders and crafting;
  - duplicate sales, purchases and claims;
  - the v1 → v2 save migration, save sanitising, and refusing newer save versions.
- Two balance simulations: the first hour (300 simulated players) and full progression through all five regions (100 simulated players). Numbers are in DESIGN.md.
- Every script type-checks against the full Roblox API (luau-lsp with Roblox type definitions), and the place file builds with Rojo.

**Not tested: please verify in Studio.** I can't run Roblox Studio here, so nothing above has been play-tested. That includes the visuals and layout of all five islands, the dice animation, UI feel on mobile, teleporting, auras, DataStore saving and session locking in a live server, and multiplayer. The testing checklist above covers these.

## Running the checks yourself

```
python3 tests/run.py path/to/luau          # logic tests + balance simulation
TOOLS=path/to/bin DEFS=globalTypes.d.luau tests/check.sh   # build + type-check + tests
```

## Stages

- **Stage 1:** Meadow Market, rolling, reveals, mutations, inventory, selling, upgrades, auto-roll, tutorial, odds, settings, saving.
- **Stage 2:** dice shop and equipping, 2–3 dice with combos, region unlocks and travel, four more regions, collection book.
- **Stage 3:** merchant orders, crafting (Celestial Die, auras, tray skins), daily objectives, milestones, world events, per-region lighting, effects and badges.

`Config > Game > Stage` gates content. Set it to 1 or 2 to play an earlier stage.

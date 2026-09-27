# Dicebound: Roll & Riches

A Roblox treasure-collecting game: roll dice, reveal treasure, fill your bag, sell at the merchant, buy upgrades, and work toward new regions.

**Status: Stage 1 (playable foundation).** Meadow Market with server-authoritative dice rolls, 10 Meadow treasures, mutations, inventory with sort/filter/lock/select, selling with Legendary+ confirmation, four upgrade paths (bag, roll speed, sell bonus, auto-roll), a 3-step skippable tutorial, an odds panel, settings, and DataStore saving with session locking. Config for all 50 items, 7 dice and 5 regions is already in place for Stage 2.

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
      Game, Items, Dice, Regions, Economy, Rarities, Sounds
    LootMath, Odds, Net, Format, Signal (ModuleScripts)
ServerScriptService
  Dicebound (Script)                  server entry point
    Core (Folder)                     pure game rules (unit-tested)
      Schema, Bag, Shop, RollEngine, Tutorial
    Services (Folder)                 Roblox-facing systems
      PlayerData, Requests, StateSync, RegionService, ActionState, RateLimiter
    World (Folder)
      Builder, WorldBuilder           builds Meadow Market from parts
StarterPlayer > StarterPlayerScripts
  Dicebound (LocalScript)             client entry point
    ClientState, Sound (ModuleScripts)
    Controllers > RollController
    UI > Theme, Kit, Hud, DiceTray, Reveal, ItemIcon, InventoryPanel, UpgradesPanel,
         OddsPanel, SettingsPanel, Guide, Panels, Toasts, Confirm
```

To rename the game, edit `Config > Game > Name`. Item values, loot weights, upgrade prices and dice live in the other Config modules.

## Controls

| Action | PC | Gamepad | Mobile |
|---|---|---|---|
| Roll | R, or the ROLL button | X | ROLL button |
| Bag / Upgrades | B / U | | Right-side buttons |
| Talk to a stall | E | | Tap the prompt |
| Close a panel | Esc | | ✕ |

## What you should see

- You spawn on a wooden pad in a sunny floating meadow, with a stone plaza, a big die on a pedestal, a striped **Merchant** stall (east) and an **Upgrades** stall (west), plus a sealed crystal gate to the north.
- Top-left: coins, bag (0 / 20 items) and a **Tutorial 1/3** goal card with a Skip button. Bottom-centre: a dice tray and a big green **ROLL** button.
- Press ROLL: the die jiggles, tumbles into the tray, lands with a number badge, and a card pops up with the item, rarity (stars + name, not just colour), mutation and value. Legendary+ finds get a short full-screen reveal you can tap to skip.
- The tutorial then draws a golden trail to Marta's stall. Press **E** at the counter to open your bag, select items and sell. Then it points you to Upgrades.

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

## What was tested, and what wasn't

**Tested here (outside Roblox):**
- 22 automated tests (`tests/`) run the real roll engine, bag, selling, upgrade, save-schema and tutorial code under Luau. They cover odds matching the documented tables (200,000 simulated rolls), combo rules, reserved bag space, lock enforcement, duplicate sales and purchases, save sanitising and refusing newer save versions.
- A 300-player balance simulation (numbers in DESIGN.md).
- Every script type-checks against the full Roblox API (luau-lsp with Roblox type definitions), and the place file builds with Rojo.

**Not tested: please verify in Studio.** I can't run Roblox Studio here, so nothing above has been play-tested. That includes the visuals and layout, the dice animation, UI feel on mobile, DataStore saving and session locking in a live server, and multiplayer. The testing checklist above covers these.

## Running the checks yourself

```
python3 tests/run.py path/to/luau          # logic tests + balance simulation
TOOLS=path/to/bin DEFS=globalTypes.d.luau tests/check.sh   # build + type-check + tests
```

## Stages

- **Stage 1 (this build):** Meadow Market, rolling, reveals, mutations, inventory, selling, upgrades, auto-roll, tutorial, odds, settings, saving.
- **Stage 2 (next):** dice shop and equip panel, 2-3 dice slots with combos (already implemented and tested in `RollEngine`), region unlocks and the other four regions, collection book with silhouettes and regional rewards.
- **Stage 3:** merchant orders, crafting (Celestial Die, cosmetics), daily objectives, world events, milestones, extra polish.

# Dicebound: Roll & Riches (design)

## Core loop

Roll dice → reveal treasure → it goes in your bag → sell what you don't want → buy upgrades → unlock new dice and regions → find better treasure.

There is always a visible next goal. The goal card shows the tutorial step, then "save up for X", "you can afford X", "bag full: sell", and your collection progress. There is one currency (coins). Nothing involves real money, betting or cashing out.

## Roll model (server-authoritative)

1. **Faces.** Every equipped die lands on one of its six listed faces, each with a 1-in-6 chance. Dice can list different faces (Glass has no 6; Clover is 1-1-3-5-6-6).
2. **Tier.** The *lead* die (slot 1) picks the reward tier using `Economy.FaceTiers`:

| Face | Common | Uncommon | Rare | Epic | Legendary | Mythic |
|---|---|---|---|---|---|---|
| 1 | 100% | | | | | |
| 2 | 85% | 15% | | | | |
| 3 | 60% | 35% | 5% | | | |
| 4 | 40% | 45% | 13% | 2% | | |
| 5 | | 55% | 33% | 10% | 2% | |
| 6 | | | 62% | 30% | 7% | 1% |

   With one Wooden Die, the chances per roll are Common 47.5%, Uncommon 25%, Rare 18.8%, Epic 7%, Legendary 1.5% and Mythic 0.17%. These match `tests/core.test.luau`.
3. **Item.** A separate weighted draw (`Items.Weight`) picks an item of that tier from the current region. If a region has no item of the tier, the draw steps down to the nearest lower tier.
4. **Mutation.** There is a 5% chance (×die perks, capped at 25%) that the find is mutated, with at most one mutation per item. Shiny ×2 (weight 60), Golden ×4 (22), Overgrown ×3 (18, Meadow/Caverns), Frozen ×3 (Frostfall), Cosmic ×8 (Astral). Multipliers never stack.
5. **Combos** (Stage 2, needs 2-3 dice). Exactly one combo applies, the first match in priority order:
   - **Jackpot** (2+ dice, every die on its own top face): one extra find from Legendary 80 / Mythic 18 / Secret 2, plus the region's JackpotCoins.
   - **Triple** (3 dice, same face): one extra find using the face-6 tier row.
   - **Straight** (3 consecutive faces): 5% chance of the region's special (Secret) collectible.
   - **Pair** (2+ dice share a face): the main find's quantity becomes 2.

   A roll yields at most 2 items, so the server only accepts a roll when the bag has 2 free slots (1 slot with a single die). Rewards are never dropped.

`Odds.luau` computes exact probabilities from these same tables, and the Odds panel shows base odds (one Wooden Die) next to your equipped dice.

## Dice

| Die | Faces | Strength | Tradeoff |
|---|---|---|---|
| Wooden | 1-6 | Starter | No perks |
| Copper | 1-6 | +10% sell price | Same odds as Wooden |
| Glass | 1-2-3-4-5-5 | Mutation chance ×2 | No 6, so a lower tier ceiling |
| Clover | 1-1-3-5-6-6 | Two 6s | Two 1s; misses many straights |
| Frost | 2-3-4-5-6-6 in Frostfall | Frozen mutations anywhere | Plain elsewhere |
| Magma | 2-3-4-5-6-6 in Emberforge | Golden ×2 weight | Plain elsewhere |
| Celestial | 1-6 | Undiscovered items ×3 within their tier | Crafted; no bonus once your collection is complete |

The same perk from two dice does not stack (the largest value wins), and the sell multiplier is capped at ×1.5.

## Inventory rule

Capacity counts **individual items**, not stacks. Items stack by item + mutation. Locks are per stack and enforced by the server. Discoveries are recorded when an item is earned, so selling never removes a collection entry.

## Upgrades and balance

| Upgrade | Levels (value @ cost) |
|---|---|
| Treasure Bag | 20 → 30 @40 → 45 @220 → 65 @800 → 90 @2,200 → 120 @6,000 → 160 @15,000 → 220 @40,000 |
| Quick Hands (cooldown) | 2.6s → 2.4 @150 → 2.2 @500 → 2.0 @1,400 → 1.85 @4,000 → 1.7 @11,000 → 1.6 @30,000 (floor 1.5s) |
| Silver Tongue | +5% @350 → +10% @1,800 → +15% @7,000 → +20% @25,000 |
| Auto-Roller | unlock @2,000 |
| Dice Tray (slots) | 1 → 2 @5,000 → 3 @30,000 |

Region unlocks (coins are spent; discoveries count finds in the previous region):

| Region | Unlock | Collection reward | Dice sold there |
|---|---|---|---|
| Meadow Market | start | 1,000 | Copper (2,500) |
| Crystal Caverns | 2,500 + 6 finds | 6,000 | Glass (6,000), Clover (15,000) |
| Frostfall Village | 30,000 + 7 finds | 40,000 | Frost (40,000) |
| Emberforge | 400,000 + 7 finds | 150,000 | Magma (120,000) |
| Astral Sanctuary | 3,000,000 + 7 finds | 600,000 | none; the Celestial Die is crafted from Astral treasure |

The average roll with a Wooden Die in the Meadow is worth about 15.6 coins.

**Simulated first hour** (`tests/balance.test.luau`, 300 simulated players, real roll/bag/shop code):

| Milestone | p10 | Median | p90 |
|---|---|---|---|
| First sale | 1:11 | 1:11 | 1:11 |
| First upgrade | 1:11 | 1:11 | 1:11 |
| First Epic | 0:02 | 0:26 | 1:31 |
| First Legendary+ | 0:14 | 2:06 | 7:02 |
| Crystal Caverns affordable | 11:15 | 13:30 | 14:12 |
| Auto-Roller | 25:12 | 29:31 | 32:19 |

At the median, a player buys 12 upgrades and discovers all 9 regular Meadow items in the first hour. The Golden Goose Egg needs Stage 2 combos.

The simulation assumes a 0.35s reaction per manual roll (0.1s on auto), a 12s round trip to sell, and selling everything when the bag is full. It buys upgrades costing ≤600 first, saves for the gate, then buys the cheapest upgrade available. These are targets to validate through playtesting, not guarantees. Real players will stop to look at reveals and keep some items.

**Full progression** (100 simulated players, real code). The simulated player buys anything costing ≤20% of the next region's price (cheapest first), unlocks each region as soon as possible and moves there, leads with the best die for the region and fills the other slots. Orders, dailies, milestones and collection rewards are *ignored*, so real players get there somewhat faster.

| Region unlocked | p10 | Median | p90 |
|---|---|---|---|
| Crystal Caverns | 0h11m | 0h12m | 0h14m |
| Frostfall Village | 0h41m | 0h44m | 0h48m |
| Emberforge | 1h20m | 1h26m | 1h32m |
| Astral Sanctuary | 2h40m | 2h52m | 2h59m |

Average value per roll grows from 15.6 coins (Meadow, one Wooden Die) to about 1,750 (Astral, three good dice).

## Activities (Stage 3)

- **Merchant orders:** 3 slots. Each asks for N× an item (Common 3–6 … Epic 1) from an unlocked region, or occasionally one specific mutation (15%). The reward is 1.6–2.1× the sell value, and ×1.3 more for mutation orders. Orders are handed in at any merchant; locked items never count, and plain copies are used first. A completed or skipped order is replaced after 45 s, and skipping has a 3-minute cooldown.
- **Crafting:** 9 recipes, each consuming duplicate treasure plus a coin fee. They make the Celestial Die (undiscovered items ×3 within their tier), 5 auras that everyone can see, and 3 dice-tray felts. The panel shows every requirement and what you have. Locked items are never consumed, and crafting is all-or-nothing.
- **Collection book:** silhouettes for undiscovered items (their rarity is shown), a find count and mutation variants for discovered ones, and a one-time reward per completed region. Completing a region requires its Secret, which only comes from Straights and Jackpots.
- **Daily objectives:** 3 per UTC day, stable per player per day, chosen from roll / find Rare+ / find mutations / sell coins / complete orders / roll combos. Combo dailies only appear with 2+ dice. Rewards scale with your best region (×1 up to ×32). There are no streaks, so missing a day costs nothing.
- **Milestones:** 20 permanent one-time rewards across rolls, unique discoveries, orders, regions, jackpots, mutations and crafts.
- **World events:** the first starts about 90 s after server start, then one every 10 minutes, each lasting 4 minutes in a random region:
  - Golden Hour: Golden ×4
  - Lucky Winds: mutation chance ×2
  - Treasure Rush: Rare+ tier weights ×1.5
  - Merchant Festival: +25% sell at that merchant
  - Discovery Day: undiscovered ×3

  Effects apply only in that region. They go through the same `LootMath.Perks`, so the Odds panel shows an accurate temporary "with event" column. The sell multiplier cap (×1.5) and the mutation chance cap (25%) still hold.

## Security model

- The client only sends *intent*: roll (auto flag), stack keys + quantities to sell, lock toggles, and an upgrade id + the level it saw. Prices, rewards, rarities and values are always taken from server config.
- Every remote is rate-limited, refused until data has loaded, type-checked, and runs synchronously: the check and the change happen in one server frame, so double requests cannot both succeed. A per-player `Busy` flag guards against future yields.
- Rolls are enforced by a server cooldown. The region is captured when the server accepts the roll, and rewards go straight into the bag. Leaving or walking away mid-animation cannot lose or duplicate anything.
- Selling requires being within 22 studs of a merchant. Sales are all-or-nothing and re-verified when applied.
- Legendary+ sales require an explicit confirmation flag, checked by the server as well as the client.
- Dice must be owned, unique and fit your slots. Regions are unlocked in order and travel only goes to unlocked ones (with a cooldown). Orders, crafting and claims re-check their conditions and mark themselves done in the same step, so repeat requests pay nothing.

## Saving

- The record `{ Data, Lock, SavedAt }` is stored under `u_<UserId>` using `UpdateAsync` only. The schema is versioned (`Schema.Version`), with step-by-step migrations and a sanitiser that fills defaults, clamps values and moves unknown items to `Orphans` instead of deleting them.
- **Session lock:** the server's JobId is written at load and refreshed on every autosave (90s, staggered, budget-checked). Another server that sees a fresh lock retries with backoff, then asks the player to rejoin. Locks older than 5 minutes (crashed servers) are taken over. Each save checks the lock is still held; if not, it stops saving and never overwrites.
- **Migration:** v1 saves (Stage 1) migrate to v2 on load. The migration backfills the new Mutated stat, and the sanitiser adds orders, dailies, milestones, collection and cosmetics with safe defaults. This is covered by a test.
- **Load failure:** the player is kicked with a friendly message and no default profile is ever written. A save from a newer version is refused, never downgraded.
- Saves happen on leave (3 attempts with backoff) and on shutdown (`BindToClose`, in parallel, 25s cap).
- In Studio without API access, the player gets an unsaved session with a visible banner.

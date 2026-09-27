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

## Dice (config ready; Stage 2 adds the shop and equipping)

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

## Upgrades and balance (Stage 1)

| Upgrade | Levels (value @ cost) |
|---|---|
| Treasure Bag | 20 → 30 @40 → 45 @220 → 65 @800 → 90 @2,200 → 120 @6,000 → 160 @15,000 → 220 @40,000 |
| Quick Hands (cooldown) | 2.6s → 2.4 @150 → 2.2 @500 → 2.0 @1,400 → 1.85 @4,000 → 1.7 @11,000 → 1.6 @30,000 (floor 1.5s) |
| Silver Tongue | +5% @350 → +10% @1,800 → +15% @7,000 → +20% @25,000 |
| Auto-Roller | unlock @2,000 |
| Crystal Caverns gate (Stage 2) | 2,500 coins + 6 Meadow discoveries |

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

## Security model

- The client only sends *intent*: roll (auto flag), stack keys + quantities to sell, lock toggles, and an upgrade id + the level it saw. Prices, rewards, rarities and values are always taken from server config.
- Every remote is rate-limited, refused until data has loaded, type-checked, and runs synchronously: the check and the change happen in one server frame, so double requests cannot both succeed. A per-player `Busy` flag guards against future yields.
- Rolls are enforced by a server cooldown. The region is captured when the server accepts the roll, and rewards go straight into the bag. Leaving or walking away mid-animation cannot lose or duplicate anything.
- Selling requires being within 22 studs of a merchant. Sales are all-or-nothing and re-verified when applied.
- Legendary+ sales require an explicit confirmation flag, checked by the server as well as the client.

## Saving

- The record `{ Data, Lock, SavedAt }` is stored under `u_<UserId>` using `UpdateAsync` only. The schema is versioned (`Schema.Version`), with step-by-step migrations and a sanitiser that fills defaults, clamps values and moves unknown items to `Orphans` instead of deleting them.
- **Session lock:** the server's JobId is written at load and refreshed on every autosave (90s, staggered, budget-checked). Another server that sees a fresh lock retries with backoff, then asks the player to rejoin. Locks older than 5 minutes (crashed servers) are taken over. Each save checks the lock is still held; if not, it stops saving and never overwrites.
- **Load failure:** the player is kicked with a friendly message and no default profile is ever written. A save from a newer version is refused, never downgraded.
- Saves happen on leave (3 attempts with backoff) and on shutdown (`BindToClose`, in parallel, 25s cap).
- In Studio without API access, the player gets an unsaved session with a visible banner.

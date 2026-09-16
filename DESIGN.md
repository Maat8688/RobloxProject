# Design decisions — Roblox Dungeon Crawler

> Decisions and the reasoning behind them, so they don't get silently
> re-litigated across sessions. Add to this file — don't edit history away.
> If a decision changes, keep the old line, note the new one, and say why.

## Status

Vertical slice + weapon/class framework + generalized enemy AI + dungeon
generator + chest gating + loot/inventory + blacksmith economy in progress
(Sept 2026): a
procedurally-chained sequence of gray-box rooms (one safe Start room with
the weapon pickups, 3-5 randomized Combat rooms) connected by corridors,
each combat room spawning one of two enemy types (TrainingDummy,
SkeletonWarrior) that guards that room's barrier-locked chest; opening a
chest grants a real, inventory-persisted `ItemInstance` (deterministic
rarity by enemy type, not rolled) viewable via a press-`I` panel; three
weapons (Tank, Assassin, Healer); server-authoritative parry/hit-reg/stagger
loop throughout, including a genuinely unparryable must-dodge attack
(`GroundSlam`); kills pay coins plus class-keyed crystals, spendable at a
physical anvil in the start room to upgrade the equipped weapon through five
tiers. No animations/models/VFX yet — confirmed with the user this stays
gray-box until step 10, per its own place in the build order below.
Healer-specific mechanics (burst heal), Assassin backstab, Mage, and PvP are
still ahead.

## Core loop

Choose a weapon at start → weapon determines class → run a procedurally
generated dungeon → kill enemies for XP/coins → find enemy-guarded chests
(barrier drops once the guarding encounter group is cleared) → loot gear or
spend coins/crystals at the blacksmith to upgrade existing gear → repeat.

## Locked-in decisions

- **Class = equipped weapon**, not a separate stat or picker. Switching
  weapon switches class. Upgrade materials are class/weapon-type specific,
  so respeccing has a real cost and specialization is the natural path.
- **Combat is server-authoritative.** Parry input is validated server-side
  against the enemy's telegraph timeline, with a latency-compensation buffer
  (~ping/2). No full client-side prediction planned initially.
- **Skill must count as much as level/gear** — enforced through the
  parry/telegraph system, not stat-scaling tricks. Some attacks are
  deliberately unparryable (must-dodge AoEs) so it isn't "parry everything."
- **Healer must be near-indispensable.** Achieved via: (a) healing itself
  tied to the skill loop — e.g. a parry near allies triggers burst heal —
  rather than a passive HoT bot, and (b) dungeon mechanics with unavoidable
  chip damage / DoTs / execute thresholds that specifically require a healer
  to counter. Do not erode this via solo-balance changes without logging the
  change here first.
- **Magic enhances combat, it doesn't replace it** — except Mage, which is
  the explicit, deliberate exception.
- **Dungeon generation is room-prefab + connector based**, not noise/terrain
  generation. Hand-built Room models with marked enemy spawns and
  chest-vault rooms, stitched together by a layout algorithm.
- **Economy has two currencies**: coins (common, any kill) and rare crystals
  (tougher enemies/guards only), gating the higher blacksmith tiers so
  trash-mob grinding alone can't reach max gear.
- **Combat is primarily PvE** (zombies/monsters); PvP exists but reuses the
  same combat system rather than a separate one.
- **RemoteEvents are created at runtime**, not represented as Rojo-synced
  files. A shared `Remotes.luau` module creates them under
  `ReplicatedStorage.Remotes` on first use server-side; clients `WaitForChild`
  them. Keeps the "everything lives in one place" rule from ARCHITECTURE.md
  without needing binary `.rbxm`/`.model.json` assets in git.
- **Parry timing is validated using server receipt time, not the client's
  timestamp.** Client/server `os.clock()` aren't synchronized, so the
  documented latency-compensation buffer (~ping/2) is applied to when the
  server *received* the ParryAttempt, not to a client-supplied clock value.
- **No weapon-select screen.** Weapons are picked up from physical stands
  near spawn (`ProximityPrompt`, server-side `Triggered`, no RemoteEvent
  needed for the interaction itself) — equipping is diegetic, not a menu.
  Re-equipping a different weapon later is unrestricted for now; the "real
  cost" to respeccing is meant to come from class-specific upgrade materials
  (step 7's economy), not a hard lock.
- **Equipped weapon is in-memory only** (`EquipService`), same as the rest of
  game state — resets on rejoin until DataStores land in step 10. Not a
  regression to fix now, just not built yet.
- **Correction**: ARCHITECTURE.md originally planned a separate
  `EnemyAI.luau` to generalize enemy behavior across types (step 3). That
  never got built — `Enemy.luau` already was the generalized class (every
  enemy already went through `Enemy.new`), so a second file would've just
  moved code around for no reason. Generalization instead meant: enemies
  pick randomly among their own `EnemyDefs.attacks` instead of a hardcoded
  attack name, and `TryParry` checks the pending attack's `parryable` flag.
  `EnemyAI.luau` is no longer planned.
- **Correction**: ARCHITECTURE.md originally sketched `PlayerData.inventory`
  as `{ [itemId]: ItemInstance }` (step 1's aspirational schema). Built as a
  plain list (`{ ItemInstance }`) instead — a dict keyed by `itemId` can't
  hold two instances of the same item (e.g. two Practice Tokens), and each
  copy can have its own `upgradeLevel`. `classTag` on `ItemInstance` is also
  now explicitly optional (`nil` for class-neutral materials like the
  step 5/6 chest loot, not every item has to be class gear).
- **Correction**: ARCHITECTURE.md originally sketched `Dungeon/RoomTemplates/`
  as a folder (step 4). Built as a single `RoomTemplates.luau` module instead
  — each room kind is a short geometry recipe (a function call), not enough
  content to warrant its own file, matching how `WeaponDefs.luau`/
  `EnemyDefs.luau` already keep all their entries in one module rather than
  one file per weapon/enemy. `RoomTemplates/` as a folder is no longer
  planned.
- **Rename (step 7)**: `Economy/LootService.luau` → `Economy/CurrencyService.luau`.
  "Loot" already means chest items in this codebase (`LootTables.luau`,
  `ChestOpened`), so a `LootService` that actually held coins and crystals
  would have read as the item pipeline to every future session. The module
  keeps the job the name was reserved for — paying out kill rewards — under a
  name that says which of the two it pays out. `LootService.luau` is no
  longer planned.
- **Correction**: ARCHITECTURE.md originally registered `RequestUpgrade` as a
  client→server RemoteFunction (`{ itemId }` → `{ success, newStats?, error? }`).
  Not built. The blacksmith is a physical anvil with a `ProximityPrompt`,
  and `Triggered` already fires server-side carrying the player — the same
  reasoning that made weapon pickups need no remote. Adding a RemoteFunction
  would have meant a second, client-callable path into spending currency for
  no gameplay gain and a wider trust surface. The upgrade *outcome* still
  needs to reach the client, so it goes back over a plain server→client
  `UpgradeResult` event instead. `RequestUpgrade` is no longer planned; if a
  real shop UI ever lands, it should re-open this rather than assume it.
- **Correction**: `Enemy:OnDeath` was documented as deliberately single-listener
  ("one listener is enough for chest-gating"). Step 7 made that false — the
  chest unlock and the kill payout are genuinely independent — so it now holds
  a list and passes the killing player to each callback. The killer argument
  is new: `_applyDamage`/`_die` previously discarded who dealt the damage,
  which is exactly what a kill reward needs.
- **Upgrades are deliberately weaker than the parry payoff.** A fully
  upgraded weapon is +50% damage; a hit on a staggered enemy is +100%
  (`CombatConstants.STAGGER_DAMAGE_MULTIPLIER`). That ordering is the
  "skill must count as much as level/gear" pillar expressed as numbers —
  don't raise the upgrade ceiling past the stagger bonus without logging why.

## Open / not yet decided

- Is solo play fully supported, or is this group-first content? This changes
  how hard healer-necessity can be tuned.
- Fixed class roster (Tank/Assassin/Healer/Mage/...) or open to add more later?
- PvP: does a simultaneous parry cause a clash/neutral outcome, or does one
  side win?

## Build order

1. ~~Vertical slice: one room, one enemy, one weapon~~ — get parry, hit-reg,
   and stagger feeling right, fully server-authoritative. **Implemented**:
   Tank vs. TrainingDummy, no room/level art yet (just a bare Workspace
   spawn point) — still needs in-Studio playtesting to confirm the feel.
2. ~~Weapon/class data framework (2–3 classes)~~. **Implemented**: Tank,
   Assassin, Healer in `WeaponDefs.luau` with distinct damage/cooldown/parry
   window/range, equipped via world pickups (no select screen). Still
   deferred to their proper later steps: Assassin's backstab (needs enemies
   to have a facing direction — not added by step 3 below, which kept enemy
   bodies static/non-rotating; still open), Healer's burst-heal-on-parry
   (step 8), Mage (its own combat model, not just another weapon row).
3. ~~Enemy AI + telegraph system, generalized across enemy types~~.
   **Implemented**: `Enemy.luau` picks randomly among an enemy's own
   `EnemyDefs` attacks each cycle (no more hardcoded attack name), proven
   with a second enemy (`SkeletonWarrior`) alongside `TrainingDummy`.
   `TryParry` now actually checks the pending attack's `parryable` flag —
   `GroundSlam` cannot be blocked by timing at all, only dodged by range,
   delivering the "some attacks are deliberately unparryable" decision above.
   A planned separate `EnemyAI.luau` turned out unnecessary since
   `Enemy.luau` was already the generalized class — see the correction below.
4. ~~Room-based dungeon generator~~. **Implemented**: a straight chain — one
   fixed Start room (safe, holds the weapon pickups) then `math.random(3, 5)`
   Combat rooms, each a random gray-box kind (`Empty`/`Pillars`) from
   `RoomTemplates.luau`, connected by corridor floor segments, each spawning
   one randomly-typed enemy at its marked spawn point. Deliberately a linear
   chain, not a branching graph layout — still genuinely room-prefab +
   connector based and procedurally varied (room count/kind/enemy type
   differ every server start), which is what the locked decision above
   requires; a real layout algorithm is a reasonable later enhancement, not
   a gap to backfill urgently. Chest-vault rooms wait for step 5, since
   there's no loot system yet to put in them.
5. ~~Chest/encounter gating~~. **Implemented**: each combat room's single
   enemy guards that room's chest 1:1 (`ChestService.luau`) — a real
   multi-enemy `encounterGroupId` group only matters once rooms can hold
   more than one enemy. A locked chest shows a visible barrier Part and has
   no `ProximityPrompt` at all; `Enemy:OnDeath` triggers a one-time unlock
   (destroys the barrier, turns the chest gold, attaches the prompt) that
   does not re-lock when the guard later respawns and dies again. Opening
   fires `ChestOpened` with a `LootTables` descriptor keyed by *which enemy
   type* guarded it, satisfying "what's inside reflects who you just beat."
   Deliberately minimal loot (`itemId`/`name`/`flavor`, no rarity/upgrade/
   inventory) and no currency — those are steps 6 and 7.
6. ~~Loot + inventory/equip system~~. **Implemented**: `ChestService` now
   builds a real `ItemInstance` (fixed `rarity`/`classTag` from
   `LootTables`, `upgradeLevel = 0`) and hands it to `InventoryService.
   AddItem` — the only place inventory state lives, same in-memory shape as
   `EquipService`. A press-`I` panel (client-side, `InventoryUpdated`)
   lists owned items by name/rarity. Deliberately no equip *effect* for
   these items yet (they're collectible, not stat-granting — that's step
   7's blacksmith job) and the existing weapon-pickup/`EquipService` flow
   is untouched, since that's proven pillar-aligned gameplay, not something
   to disrupt for this step.
7. ~~Blacksmith/economy~~. **Implemented**: `CurrencyService` pays whoever
   lands the killing blow that enemy's `EnemyDefs` reward — coins from every
   kill, crystals only from `SkeletonWarrior`. Crystals are keyed by the class
   you were *playing* at the time, so they don't carry across a respec, which
   is where the locked "respeccing has a real cost" decision finally becomes
   real (step 2 deliberately left re-equipping unrestricted, pointing here).
   `BlacksmithService` is an anvil in the start room: it prices the next
   upgrade from `EconomyDefs`, takes payment, then calls
   `EquipService.ApplyUpgrade`. Upgrades are +10% weapon damage each, five
   tiers max, and tiers 3+ also cost crystals — so trash-mob farming alone
   tops out at +2. Deliberately scoped out: the chest items
   (`PracticeToken`/`BoneHiltShard`) are still mementos and are *not* consumed
   as upgrade materials — the class-cost pillar is carried by crystals alone,
   and making loot spendable too would mean deciding what a neutral-material
   sink does to the "what's inside reflects who you beat" pillar, which is a
   step 8 balance question, not a plumbing one.
8. Healer-specific mechanics + a real balance pass.
9. PvP arena mode.
10. Persistence (DataStores), polish, VFX.

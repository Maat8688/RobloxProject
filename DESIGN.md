# Design decisions — Roblox Dungeon Crawler

> Decisions and the reasoning behind them, so they don't get silently
> re-litigated across sessions. Add to this file — don't edit history away.
> If a decision changes, keep the old line, note the new one, and say why.

## Status

Vertical slice in progress (Sept 2026): one weapon (Tank), one enemy
(TrainingDummy), server-authoritative parry/hit-reg/stagger loop implemented
per the build order below. Class framework, generalized enemy AI, dungeon
generation, loot, economy, healer balance, and PvP are still ahead.

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
2. Weapon/class data framework (2–3 classes).
3. Enemy AI + telegraph system, generalized across enemy types.
4. Room-based dungeon generator.
5. Chest/encounter gating.
6. Loot + inventory/equip system.
7. Blacksmith/economy.
8. Healer-specific mechanics + a real balance pass.
9. PvP arena mode.
10. Persistence (DataStores), polish, VFX.
